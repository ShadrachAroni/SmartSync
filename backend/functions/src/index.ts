/**
 * SmartSync Firebase Cloud Functions
 * Main entry point - exports all cloud functions
 * 
 * File: backend/functions/src/index.ts
 */

import * as admin from 'firebase-admin';
import * as functions from 'firebase-functions';

// Initialize Firebase Admin SDK
admin.initializeApp();

const db = admin.firestore();

// ==================== ML FUNCTIONS ====================
// Import ML inference functions
export { predictSchedule, detectAnomalies } from './ml/mlInference';

// ==================== AUTH FUNCTIONS ====================

/**
 * Triggered when a new user is created
 * Creates initial user profile in Firestore
 */
export const onUserCreate = functions.auth.user().onCreate(async (user) => {
  const { uid, email, displayName, photoURL } = user;

  console.log(`👤 Creating profile for new user: ${uid}`);

  try {
    // Create user profile document
    await db.collection('users').doc(uid).set({
      email: email || '',
      name: displayName || '',
      profileImageUrl: photoURL || '',
      deviceIds: [],
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      preferences: {
        notifications: true,
        theme: 'light',
        language: 'en',
        temperatureUnit: 'celsius'
      },
      role: 'user' // Can be 'user' or 'caregiver'
    });

    console.log(`✅ User profile created for: ${uid}`);

  } catch (error) {
    console.error('❌ Error creating user profile:', error);
    throw error;
  }
});

/**
 * Triggered when a user is deleted
 * Cleans up all user-associated data
 */
export const onUserDelete = functions.auth.user().onDelete(async (user) => {
  const { uid } = user;

  console.log(`🗑️  Cleaning up data for deleted user: ${uid}`);

  try {
    // Delete in batches to avoid Firestore limits (500 ops per batch)
    await deleteUserData(uid);

    console.log(`✅ User data cleanup completed for: ${uid}`);

  } catch (error) {
    console.error('❌ Error during user cleanup:', error);
    throw error;
  }
});

/**
 * Helper function to delete all user data in batches
 */
async function deleteUserData(userId: string): Promise<void> {
  const batch = db.batch();
  let operationCount = 0;

  // Delete user profile
  batch.delete(db.collection('users').doc(userId));
  operationCount++;

  // Delete user's devices
  const devicesSnapshot = await db.collection('devices')
    .where('userId', '==', userId)
    .limit(500)
    .get();

  devicesSnapshot.docs.forEach(doc => {
    batch.delete(doc.ref);
    operationCount++;
  });

  // Delete user's sensor logs (in chunks)
  const logsSnapshot = await db.collection('sensor_logs')
    .where('userId', '==', userId)
    .limit(500)
    .get();

  logsSnapshot.docs.forEach(doc => {
    batch.delete(doc.ref);
    operationCount++;
  });

  // Commit if we have operations
  if (operationCount > 0) {
    await batch.commit();
    console.log(`Deleted ${operationCount} documents`);
  }

  // If there were 500+ logs, recursively delete more
  if (logsSnapshot.size === 500) {
    await deleteUserData(userId);
  }
}

/**
 * Generate custom token for Bluetooth device authentication
 * Allows devices to authenticate without email/password
 */
export const createCustomToken = functions.https.onCall(async (data, context) => {
  const { deviceId, secret } = data;

  console.log(`🔑 Custom token requested for device: ${deviceId}`);

  // Verify device secret (retrieve from Firebase config)
  const DEVICE_SECRET = functions.config().device?.secret || 'default-secret';

  if (secret !== DEVICE_SECRET) {
    console.warn('⚠️  Invalid device credentials');
    throw new functions.https.HttpsError(
      'permission-denied',
      'Invalid device credentials'
    );
  }

  try {
    // Create custom token for the device
    const customToken = await admin.auth().createCustomToken(deviceId, {
      deviceAuth: true,
      deviceId: deviceId
    });

    console.log(`✅ Custom token created for device: ${deviceId}`);

    return {
      success: true,
      token: customToken
    };

  } catch (error) {
    console.error('❌ Error creating custom token:', error);
    throw new functions.https.HttpsError(
      'internal',
      'Failed to create authentication token'
    );
  }
});

// ==================== ANALYTICS FUNCTIONS ====================

/**
 * Scheduled function: Aggregate daily analytics
 * Runs every day at midnight UTC
 */
export const aggregateData = functions.pubsub
  .schedule('0 0 * * *')
  .timeZone('UTC')
  .onRun(async (context) => {
    console.log('📊 Starting daily analytics aggregation...');

    const yesterday = new Date();
    yesterday.setDate(yesterday.getDate() - 1);
    yesterday.setHours(0, 0, 0, 0);

    const today = new Date(yesterday);
    today.setDate(today.getDate() + 1);

    try {
      // Process users in batches
      await processUsersAnalytics(yesterday, today);

      console.log('✅ Daily analytics aggregation completed');
      return null;

    } catch (error) {
      console.error('❌ Error during analytics aggregation:', error);
      throw error;
    }
  });

/**
 * Process analytics for all users in batches
 */
async function processUsersAnalytics(startDate: Date, endDate: Date): Promise<void> {
  let lastDoc: FirebaseFirestore.QueryDocumentSnapshot | null = null;
  let processedCount = 0;

  while (true) {
    let query = db.collection('users').limit(100);

    if (lastDoc) {
      query = query.startAfter(lastDoc);
    }

    const usersSnapshot = await query.get();

    if (usersSnapshot.empty) break;

    // Process each user
    for (const userDoc of usersSnapshot.docs) {
      const userId = userDoc.id;

      try {
        await aggregateUserData(userId, startDate, endDate);
        processedCount++;
      } catch (error) {
        console.error(`Error aggregating data for user ${userId}:`, error);
      }
    }

    lastDoc = usersSnapshot.docs[usersSnapshot.docs.length - 1];
    console.log(`Processed ${processedCount} users...`);
  }

  console.log(`✅ Total users processed: ${processedCount}`);
}

/**
 * Aggregate sensor data for a single user
 */
async function aggregateUserData(
  userId: string,
  startDate: Date,
  endDate: Date
): Promise<void> {
  // Query sensor logs for the day
  const sensorSnapshot = await db.collection('sensor_logs')
    .where('userId', '==', userId)
    .where('timestamp', '>=', startDate)
    .where('timestamp', '<', endDate)
    .get();

  if (sensorSnapshot.empty) return;

  // Calculate statistics
  let totalTemp = 0;
  let totalHumidity = 0;
  let motionEvents = 0;
  let fanUsage = 0;
  let ledUsage = 0;

  sensorSnapshot.docs.forEach(doc => {
    const data = doc.data();
    totalTemp += data.temperature || 0;
    totalHumidity += data.humidity || 0;
    motionEvents += data.motionDetected ? 1 : 0;
    fanUsage += data.fanSpeed || 0;
    ledUsage += data.ledBrightness || 0;
  });

  const count = sensorSnapshot.size;

  // Save daily summary
  await db.collection('daily_analytics').add({
    userId,
    date: admin.firestore.Timestamp.fromDate(startDate),
    avgTemperature: totalTemp / count,
    avgHumidity: totalHumidity / count,
    motionEvents,
    avgFanUsage: fanUsage / count,
    avgLedUsage: ledUsage / count,
    totalReadings: count,
    createdAt: admin.firestore.FieldValue.serverTimestamp()
  });
}

/**
 * Generate analytics report on demand
 */
export const generateReport = functions.https.onCall(async (data, context) => {
  // Authentication check
  if (!context.auth) {
    throw new functions.https.HttpsError(
      'unauthenticated',
      'User must be authenticated'
    );
  }

  const { userId, days } = data;
  const requesterId = context.auth.uid;

  console.log(`📈 Generating ${days}-day report for user ${userId}`);

  // Verify requester has access to this user's data
  if (userId !== requesterId) {
    const hasAccess = await verifyDataAccess(requesterId, userId);

    if (!hasAccess) {
      throw new functions.https.HttpsError(
        'permission-denied',
        'You do not have access to this user data'
      );
    }
  }

  try {
    const cutoffDate = new Date();
    cutoffDate.setDate(cutoffDate.getDate() - days);

    // Fetch daily analytics
    const analyticsSnapshot = await db.collection('daily_analytics')
      .where('userId', '==', userId)
      .where('date', '>=', admin.firestore.Timestamp.fromDate(cutoffDate))
      .orderBy('date', 'asc')
      .get();

    const analytics = analyticsSnapshot.docs.map(doc => doc.data());

    if (analytics.length === 0) {
      return {
        success: false,
        message: 'No analytics data available for this period'
      };
    }

    // Calculate summary
    const summary = {
      totalDays: analytics.length,
      avgTemperature: analytics.reduce((sum, a) => sum + a.avgTemperature, 0) / analytics.length,
      avgHumidity: analytics.reduce((sum, a) => sum + a.avgHumidity, 0) / analytics.length,
      totalMotionEvents: analytics.reduce((sum, a) => sum + a.motionEvents, 0),
      avgFanUsage: analytics.reduce((sum, a) => sum + a.avgFanUsage, 0) / analytics.length,
      avgLedUsage: analytics.reduce((sum, a) => sum + a.avgLedUsage, 0) / analytics.length
    };

    console.log(`✅ Report generated successfully`);

    return {
      success: true,
      summary,
      dailyData: analytics,
      generatedAt: admin.firestore.FieldValue.serverTimestamp()
    };

  } catch (error) {
    console.error('❌ Error generating report:', error);
    throw new functions.https.HttpsError(
      'internal',
      'Failed to generate report'
    );
  }
});

/**
 * Verify if requester has access to user's data (caregiver relationship)
 */
async function verifyDataAccess(caregiverId: string, userId: string): Promise<boolean> {
  const relationship = await db.collection('caregiver_relationships')
    .where('caregiverId', '==', caregiverId)
    .where('userId', '==', userId)
    .where('status', '==', 'active')
    .limit(1)
    .get();

  return !relationship.empty;
}

// ==================== NOTIFICATION FUNCTIONS ====================

/**
 * Send alert notification when new alert is created
 */
export const sendAlert = functions.firestore
  .document('alerts/{alertId}')
  .onCreate(async (snap, context) => {
    const alertData = snap.data();
    const { userId, type, severity, title, message } = alertData;

    console.log(`📢 New alert created: ${context.params.alertId}`);

    try {
      // Get user's caregivers
      const caregiversSnapshot = await db.collection('caregiver_relationships')
        .where('userId', '==', userId)
        .where('status', '==', 'active')
        .get();

      const notificationPromises: Promise<void>[] = [];

      // Send notifications to all caregivers
      for (const caregiverDoc of caregiversSnapshot.docs) {
        const caregiverId = caregiverDoc.data().caregiverId;
        notificationPromises.push(sendPushNotification(caregiverId, title, message, {
          alertId: context.params.alertId,
          userId,
          type,
          severity
        }));
      }

      await Promise.all(notificationPromises);
      console.log(`✅ Notifications sent to ${notificationPromises.length} caregivers`);

    } catch (error) {
      console.error('❌ Error sending alert notification:', error);
    }
  });

/**
 * Send push notification via FCM
 */
async function sendPushNotification(
  userId: string,
  title: string,
  body: string,
  data: Record<string, string>
): Promise<void> {
  try {
    const userDoc = await db.collection('users').doc(userId).get();
    const fcmToken = userDoc.data()?.fcmToken;

    if (!fcmToken) {
      console.log(`No FCM token for user ${userId}`);
      return;
    }

    await admin.messaging().send({
      token: fcmToken,
      notification: { title, body },
      data,
      android: {
        priority: 'high',
        notification: {
          sound: 'default',
          priority: 'high'
        }
      },
      apns: {
        payload: {
          aps: {
            sound: 'default',
            badge: 1,
            contentAvailable: true
          }
        }
      }
    });

    console.log(`📱 Notification sent to user ${userId}`);

  } catch (error: any) {
    // Handle invalid FCM tokens
    if (error.code === 'messaging/invalid-registration-token' ||
        error.code === 'messaging/registration-token-not-registered') {
      console.warn(`Invalid FCM token for user ${userId}, removing...`);
      await db.collection('users').doc(userId).update({
        fcmToken: admin.firestore.FieldValue.delete()
      });
    } else {
      console.error(`Error sending notification to ${userId}:`, error);
    }
  }
}

/**
 * Send schedule reminders
 * Runs every 5 minutes to check for upcoming schedules
 */
export const scheduleReminder = functions.pubsub
  .schedule('*/5 * * * *')
  .onRun(async (context) => {
    console.log('⏰ Checking for schedule reminders...');

    const now = new Date();
    const in10Minutes = new Date(now.getTime() + 10 * 60000);

    try {
      // Get schedules that should fire in the next 10 minutes
      const schedulesSnapshot = await db.collection('schedules')
        .where('enabled', '==', true)
        .where('nextRun', '>=', admin.firestore.Timestamp.fromDate(now))
        .where('nextRun', '<=', admin.firestore.Timestamp.fromDate(in10Minutes))
        .get();

      const reminderPromises: Promise<void>[] = [];

      for (const scheduleDoc of schedulesSnapshot.docs) {
        const schedule = scheduleDoc.data();
        const { userId, name, deviceType, value } = schedule;

        reminderPromises.push(sendPushNotification(
          userId,
          '⏰ Schedule Reminder',
          `"${name}" will run in 10 minutes`,
          {
            scheduleId: scheduleDoc.id,
            deviceType,
            value: value.toString()
          }
        ));
      }

      await Promise.all(reminderPromises);
      console.log(`✅ Sent ${reminderPromises.length} schedule reminders`);

      return null;

    } catch (error) {
      console.error('❌ Error sending schedule reminders:', error);
      throw error;
    }
  });

// ==================== STORAGE CLEANUP ====================

/**
 * Clean up old sensor logs (keep last 90 days)
 * Runs weekly on Sunday at 2 AM UTC
 */
export const cleanupOldLogs = functions.pubsub
  .schedule('0 2 * * 0')
  .timeZone('UTC')
  .onRun(async (context) => {
    console.log('🧹 Starting cleanup of old sensor logs...');

    const cutoffDate = new Date();
    cutoffDate.setDate(cutoffDate.getDate() - 90);

    try {
      let deletedCount = 0;

      // Delete in batches
      while (true) {
        const logsSnapshot = await db.collection('sensor_logs')
          .where('timestamp', '<', admin.firestore.Timestamp.fromDate(cutoffDate))
          .limit(500)
          .get();

        if (logsSnapshot.empty) break;

        const batch = db.batch();
        logsSnapshot.docs.forEach(doc => {
          batch.delete(doc.ref);
        });

        await batch.commit();
        deletedCount += logsSnapshot.size;

        console.log(`Deleted ${deletedCount} logs so far...`);
      }

      console.log(`✅ Cleanup complete. Deleted ${deletedCount} old sensor logs`);
      return null;

    } catch (error) {
      console.error('❌ Error during log cleanup:', error);
      throw error;
    }
  });

// ==================== DEVICE MANAGEMENT ====================

/**
 * Handle device status updates
 * Updates device last seen timestamp when sensor logs are created
 */
export const onDeviceStatusUpdate = functions.firestore
  .document('sensor_logs/{logId}')
  .onCreate(async (snap, context) => {
    const logData = snap.data();
    const { deviceId, userId } = logData;

    if (!deviceId) return;

    try {
      // Update device last seen
      await db.collection('devices').doc(deviceId).set({
        userId,
        lastSeen: admin.firestore.FieldValue.serverTimestamp(),
        isOnline: true,
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      }, { merge: true });

    } catch (error) {
      console.error('❌ Error updating device status:', error);
    }
  });

/**
 * Check for offline devices
 * Runs every hour to mark devices offline if no recent activity
 */
export const checkOfflineDevices = functions.pubsub
  .schedule('0 * * * *')
  .onRun(async (context) => {
    console.log('🔍 Checking for offline devices...');

    const cutoffTime = new Date();
    cutoffTime.setHours(cutoffTime.getHours() - 1); // 1 hour threshold

    try {
      const devicesSnapshot = await db.collection('devices')
        .where('isOnline', '==', true)
        .where('lastSeen', '<', admin.firestore.Timestamp.fromDate(cutoffTime))
        .get();

      const batch = db.batch();

      devicesSnapshot.docs.forEach(doc => {
        batch.update(doc.ref, {
          isOnline: false,
          updatedAt: admin.firestore.FieldValue.serverTimestamp()
        });
      });

      if (devicesSnapshot.size > 0) {
        await batch.commit();
        console.log(`✅ Marked ${devicesSnapshot.size} devices as offline`);
      } else {
        console.log('✅ All devices are online');
      }

      return null;

    } catch (error) {
      console.error('❌ Error checking offline devices:', error);
      throw error;
    }
  });

// ==================== EXPORTS SUMMARY ====================
/*
Exported Cloud Functions:

ML Functions:
  - predictSchedule: Generate AI schedule suggestions
  - detectAnomalies: Detect unusual behavior patterns

Auth Functions:
  - onUserCreate: Initialize user profile on signup
  - onUserDelete: Cleanup user data on account deletion
  - createCustomToken: Bluetooth device authentication

Analytics Functions:
  - aggregateData: Daily data aggregation (scheduled)
  - generateReport: On-demand analytics reports

Notification Functions:
  - sendAlert: Push notifications for alerts
  - scheduleReminder: Schedule execution reminders

Maintenance Functions:
  - cleanupOldLogs: Remove old sensor data (scheduled)
  - onDeviceStatusUpdate: Track device connectivity
  - checkOfflineDevices: Mark inactive devices as offline
*/