/**
 * SmartSync Firebase Cloud Functions
 * Main entry point - exports all cloud functions
 * 
 * File location: backend/functions/src/index.ts
 */

import * as admin from 'firebase-admin';

// Initialize Firebase Admin SDK
admin.initializeApp();

// ==================== ML FUNCTIONS ====================
// Machine Learning inference functions
export { predictSchedule, detectAnomalies } from './ml/mlInference';

// ==================== AUTH FUNCTIONS ====================
// User authentication and profile management

import * as functions from 'firebase-functions';

/**
 * Triggered when a new user is created
 * Creates initial user profile in Firestore
 */
export const onUserCreate = functions.auth.user().onCreate(async (user) => {
  const { uid, email, displayName, photoURL } = user;
  
  console.log(`Creating profile for new user: ${uid}`);
  
  try {
    const db = admin.firestore();
    
    // Create user profile document
    await db.collection('users').doc(uid).set({
      email: email || '',
      name: displayName || '',
      profileImageUrl: photoURL || '',
      deviceIds: [],
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      preferences: {
        notifications: true,
        theme: 'light',
        language: 'en'
      }
    });
    
    console.log(`User profile created successfully for: ${uid}`);
    
  } catch (error) {
    console.error('Error creating user profile:', error);
  }
});

/**
 * Triggered when a user is deleted
 * Cleans up user data
 */
export const onUserDelete = functions.auth.user().onDelete(async (user) => {
  const { uid } = user;
  
  console.log(`Cleaning up data for deleted user: ${uid}`);
  
  try {
    const db = admin.firestore();
    const batch = db.batch();
    
    // Delete user profile
    batch.delete(db.collection('users').doc(uid));
    
    // Delete user's devices
    const devicesSnapshot = await db.collection('devices')
      .where('userId', '==', uid)
      .get();
    
    devicesSnapshot.docs.forEach(doc => {
      batch.delete(doc.ref);
    });
    
    // Delete user's sensor logs
    const logsSnapshot = await db.collection('sensor_logs')
      .where('userId', '==', uid)
      .limit(500) // Batch delete in chunks
      .get();
    
    logsSnapshot.docs.forEach(doc => {
      batch.delete(doc.ref);
    });
    
    await batch.commit();
    
    console.log(`User data cleanup completed for: ${uid}`);
    
  } catch (error) {
    console.error('Error during user cleanup:', error);
  }
});

/**
 * Generate custom token for Bluetooth authentication
 * Allows device-based login without email/password
 */
export const createCustomToken = functions.https.onCall(async (data, context) => {
  const { deviceId, secret } = data;
  
  // Verify device secret (implement your security logic)
  const DEVICE_SECRET = functions.config().device?.secret || 'default-secret';
  
  if (secret !== DEVICE_SECRET) {
    throw new functions.https.HttpsError(
      'permission-denied',
      'Invalid device credentials'
    );
  }
  
  try {
    // Create custom token for device
    const customToken = await admin.auth().createCustomToken(deviceId);
    
    return {
      success: true,
      token: customToken
    };
    
  } catch (error) {
    console.error('Error creating custom token:', error);
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
    console.log('Starting daily analytics aggregation...');
    
    const db = admin.firestore();
    const yesterday = new Date();
    yesterday.setDate(yesterday.getDate() - 1);
    yesterday.setHours(0, 0, 0, 0);
    
    const today = new Date(yesterday);
    today.setDate(today.getDate() + 1);
    
    try {
      // Get all users
      const usersSnapshot = await db.collection('users').get();
      
      for (const userDoc of usersSnapshot.docs) {
        const userId = userDoc.id;
        
        // Aggregate sensor data for the day
        const sensorSnapshot = await db.collection('sensor_logs')
          .where('userId', '==', userId)
          .where('timestamp', '>=', yesterday)
          .where('timestamp', '<', today)
          .get();
        
        if (sensorSnapshot.empty) continue;
        
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
          date: admin.firestore.Timestamp.fromDate(yesterday),
          avgTemperature: totalTemp / count,
          avgHumidity: totalHumidity / count,
          motionEvents,
          avgFanUsage: fanUsage / count,
          avgLedUsage: ledUsage / count,
          totalReadings: count,
          createdAt: admin.firestore.FieldValue.serverTimestamp()
        });
      }
      
      console.log('Daily analytics aggregation completed');
      return null;
      
    } catch (error) {
      console.error('Error during analytics aggregation:', error);
      throw error;
    }
  });

/**
 * Generate analytics report on demand
 */
export const generateReport = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError(
      'unauthenticated',
      'User must be authenticated'
    );
  }
  
  const { userId, days } = data;
  const requesterId = context.auth.uid;
  
  // Verify user can access this data
  if (userId !== requesterId) {
    const db = admin.firestore();
    const relationship = await db.collection('caregiver_relationships')
      .where('caregiverId', '==', requesterId)
      .where('userId', '==', userId)
      .where('status', '==', 'active')
      .get();
    
    if (relationship.empty) {
      throw new functions.https.HttpsError(
        'permission-denied',
        'You do not have access to this user data'
      );
    }
  }
  
  try {
    const db = admin.firestore();
    const cutoffDate = new Date();
    cutoffDate.setDate(cutoffDate.getDate() - days);
    
    // Fetch daily analytics
    const analyticsSnapshot = await db.collection('daily_analytics')
      .where('userId', '==', userId)
      .where('date', '>=', admin.firestore.Timestamp.fromDate(cutoffDate))
      .orderBy('date', 'asc')
      .get();
    
    const analytics = analyticsSnapshot.docs.map(doc => doc.data());
    
    // Calculate summary
    const summary = {
      totalDays: analytics.length,
      avgTemperature: analytics.reduce((sum, a) => sum + a.avgTemperature, 0) / analytics.length,
      avgHumidity: analytics.reduce((sum, a) => sum + a.avgHumidity, 0) / analytics.length,
      totalMotionEvents: analytics.reduce((sum, a) => sum + a.motionEvents, 0),
      avgFanUsage: analytics.reduce((sum, a) => sum + a.avgFanUsage, 0) / analytics.length,
      avgLedUsage: analytics.reduce((sum, a) => sum + a.avgLedUsage, 0) / analytics.length
    };
    
    return {
      success: true,
      summary,
      dailyData: analytics,
      generatedAt: admin.firestore.FieldValue.serverTimestamp()
    };
    
  } catch (error) {
    console.error('Error generating report:', error);
    throw new functions.https.HttpsError(
      'internal',
      'Failed to generate report'
    );
  }
});

// ==================== NOTIFICATION FUNCTIONS ====================

/**
 * Send alert notification when new alert is created
 */
export const sendAlert = functions.firestore
  .document('alerts/{alertId}')
  .onCreate(async (snap, context) => {
    const alertData = snap.data();
    const { userId, type, severity, title, message } = alertData;
    
    console.log(`New alert created: ${context.params.alertId} for user: ${userId}`);
    
    try {
      const db = admin.firestore();
      
      // Get user's caregivers
      const caregiversSnapshot = await db.collection('caregiver_relationships')
        .where('userId', '==', userId)
        .where('status', '==', 'active')
        .get();
      
      const caregiverIds = caregiversSnapshot.docs.map(doc => doc.data().caregiverId);
      
      // Send notifications to all caregivers
      for (const caregiverId of caregiverIds) {
        const caregiverDoc = await db.collection('users').doc(caregiverId).get();
        const fcmToken = caregiverDoc.data()?.fcmToken;
        
        if (fcmToken) {
          await admin.messaging().send({
            token: fcmToken,
            notification: {
              title: `⚠️ ${title}`,
              body: message
            },
            data: {
              alertId: context.params.alertId,
              userId,
              type,
              severity
            },
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
          
          console.log(`Notification sent to caregiver: ${caregiverId}`);
        }
      }
      
    } catch (error) {
      console.error('Error sending alert notification:', error);
    }
  });

/**
 * Send schedule reminders
 * Runs every 5 minutes to check for upcoming schedules
 */
export const scheduleReminder = functions.pubsub
  .schedule('*/5 * * * *')
  .onRun(async (context) => {
    console.log('Checking for schedule reminders...');
    
    const db = admin.firestore();
    const now = new Date();
    const in10Minutes = new Date(now.getTime() + 10 * 60000);
    
    try {
      // Get schedules that should fire in the next 10 minutes
      const schedulesSnapshot = await db.collection('schedules')
        .where('enabled', '==', true)
        .where('nextRun', '>=', admin.firestore.Timestamp.fromDate(now))
        .where('nextRun', '<=', admin.firestore.Timestamp.fromDate(in10Minutes))
        .get();
      
      for (const scheduleDoc of schedulesSnapshot.docs) {
        const schedule = scheduleDoc.data();
        const { userId, name, deviceType, value } = schedule;
        
        // Get user's FCM token
        const userDoc = await db.collection('users').doc(userId).get();
        const fcmToken = userDoc.data()?.fcmToken;
        
        if (fcmToken) {
          await admin.messaging().send({
            token: fcmToken,
            notification: {
              title: '⏰ Schedule Reminder',
              body: `"${name}" will run in 10 minutes`
            },
            data: {
              scheduleId: scheduleDoc.id,
              deviceType,
              value: value.toString()
            }
          });
          
          console.log(`Reminder sent for schedule: ${scheduleDoc.id}`);
        }
      }
      
      return null;
      
    } catch (error) {
      console.error('Error sending schedule reminders:', error);
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
    console.log('Starting cleanup of old sensor logs...');
    
    const db = admin.firestore();
    const cutoffDate = new Date();
    cutoffDate.setDate(cutoffDate.getDate() - 90);
    
    try {
      const logsSnapshot = await db.collection('sensor_logs')
        .where('timestamp', '<', admin.firestore.Timestamp.fromDate(cutoffDate))
        .limit(500)
        .get();
      
      if (logsSnapshot.empty) {
        console.log('No old logs to cleanup');
        return null;
      }
      
      const batch = db.batch();
      logsSnapshot.docs.forEach(doc => {
        batch.delete(doc.ref);
      });
      
      await batch.commit();
      
      console.log(`Deleted ${logsSnapshot.size} old sensor logs`);
      return null;
      
    } catch (error) {
      console.error('Error during log cleanup:', error);
      throw error;
    }
  });

// ==================== DEVICE MANAGEMENT ====================

/**
 * Handle device status updates
 * Updates device last seen timestamp
 */
export const onDeviceStatusUpdate = functions.firestore
  .document('sensor_logs/{logId}')
  .onCreate(async (snap, context) => {
    const logData = snap.data();
    const { deviceId, userId } = logData;
    
    if (!deviceId) return;
    
    try {
      const db = admin.firestore();
      
      // Update device last seen
      await db.collection('devices').doc(deviceId).set({
        lastSeen: admin.firestore.FieldValue.serverTimestamp(),
        isOnline: true
      }, { merge: true });
      
    } catch (error) {
      console.error('Error updating device status:', error);
    }
  });

// ==================== EXPORTS SUMMARY ====================
/*
ML Functions:
  - predictSchedule: Generate AI schedule suggestions
  - detectAnomalies: Detect unusual behavior patterns

Auth Functions:
  - onUserCreate: Initialize user profile
  - onUserDelete: Cleanup user data
  - createCustomToken: Bluetooth device authentication

Analytics Functions:
  - aggregateData: Daily data aggregation
  - generateReport: On-demand analytics reports

Notification Functions:
  - sendAlert: Push notifications for alerts
  - scheduleReminder: Schedule execution reminders

Maintenance Functions:
  - cleanupOldLogs: Remove old sensor data
  - onDeviceStatusUpdate: Track device connectivity
*/