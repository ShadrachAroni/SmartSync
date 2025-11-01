/**
 * SmartSync Firebase Cloud Functions - ML Inference
 * 
 * Server-side machine learning functions for:
 * 1. Schedule prediction (suggest optimal device schedules)
 * 2. Anomaly detection (alert caregivers of unusual patterns)
 * 
 * Note: TensorFlow.js is used for inference in Cloud Functions
 */

import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';
import * as tf from '@tensorflow/tfjs';

const db = admin.firestore();

// ==================== MODEL MANAGEMENT ====================

let scheduleModel: tf.LayersModel | null = null;
let anomalyModel: tf.LayersModel | null = null;

/**
 * Load TensorFlow.js model from Cloud Storage
 */
async function loadModel(modelName: string): Promise<tf.LayersModel> {
  const bucketName = 'smartsync-cf370.appspot.com';
  const modelUrl = `gs://${bucketName}/ml_models/${modelName}_v1.tflite`;
  
  console.log(`Loading model: ${modelName} from ${modelUrl}`);
  
  try {
    // For TFLite models, we need to convert them to TF.js format
    // Alternative: Use JSON format models or convert TFLite to TFJS
    const model = await tf.loadLayersModel(modelUrl);
    console.log(`Model ${modelName} loaded successfully`);
    return model;
  } catch (error) {
    console.error(`Failed to load model ${modelName}:`, error);
    throw new functions.https.HttpsError(
      'internal',
      `Model loading failed: ${error}`
    );
  }
}

/**
 * Initialize models (called on cold start)
 */
async function initializeModels() {
  if (!scheduleModel) {
    try {
      scheduleModel = await loadModel('schedule_predictor');
    } catch (error) {
      console.error('Schedule model initialization failed:', error);
    }
  }
  
  if (!anomalyModel) {
    try {
      anomalyModel = await loadModel('anomaly_detector');
    } catch (error) {
      console.error('Anomaly model initialization failed:', error);
    }
  }
}

// ==================== SCHEDULE PREDICTION ====================

/**
 * HTTP Callable Function: Predict Optimal Schedule
 * 
 * Client calls:
 * ```dart
 * final result = await FirebaseFunctions.instance
 *   .httpsCallable('predictSchedule')
 *   .call({ 'userId': userId });
 * ```
 */
export const predictSchedule = functions.https.onCall(async (data, context) => {
  // Authentication check
  if (!context.auth) {
    throw new functions.https.HttpsError(
      'unauthenticated',
      'User must be authenticated'
    );
  }
  
  const userId = data.userId || context.auth.uid;
  
  console.log(`Predicting schedule for user: ${userId}`);
  
  try {
    // 1. Fetch last 168 hours of sensor data
    const sensorLogs = await fetchSensorLogs(userId, 168);
    
    if (sensorLogs.length < 168) {
      throw new functions.https.HttpsError(
        'failed-precondition',
        `Insufficient data (need 168 hours, got ${sensorLogs.length})`
      );
    }
    
    // 2. Preprocess data
    const inputTensor = preprocessScheduleInput(sensorLogs);
    
    // 3. Load model if not loaded
    if (!scheduleModel) {
      await initializeModels();
    }
    
    if (!scheduleModel) {
      throw new functions.https.HttpsError(
        'internal',
        'Schedule prediction model not available'
      );
    }
    
    // 4. Run inference
    const prediction = scheduleModel.predict(inputTensor) as tf.Tensor;
    const predictionData = await prediction.array() as number[][];
    
    // 5. Post-process results
    const suggestedSchedules = postprocessSchedulePrediction(predictionData);
    
    // 6. Save to Firestore
    await savePredictedSchedules(userId, suggestedSchedules);
    
    // 7. Cleanup tensors
    inputTensor.dispose();
    prediction.dispose();
    
    return {
      success: true,
      schedules: suggestedSchedules,
      timestamp: admin.firestore.FieldValue.serverTimestamp()
    };
    
  } catch (error) {
    console.error('Schedule prediction error:', error);
    throw new functions.https.HttpsError('internal', `Prediction failed: ${error}`);
  }
});

/**
 * Fetch sensor logs from Firestore
 */
async function fetchSensorLogs(userId: string, hours: number) {
  const cutoffDate = new Date();
  cutoffDate.setHours(cutoffDate.getHours() - hours);
  
  const snapshot = await db.collection('sensor_logs')
    .where('userId', '==', userId)
    .where('timestamp', '>=', cutoffDate)
    .orderBy('timestamp', 'asc')
    .limit(hours)
    .get();
  
  return snapshot.docs.map(doc => doc.data());
}

/**
 * Preprocess sensor logs for schedule prediction model
 */
function preprocessScheduleInput(sensorLogs: any[]): tf.Tensor {
  // Extract features (13 features per hour)
  const features = sensorLogs.map(log => {
    const timestamp = log.timestamp.toDate();
    const hour = timestamp.getHours();
    const day = timestamp.getDay();
    
    return [
      normalizeTemperature(log.temperature),
      normalizeTemperature(log.temperature), // temp_max (simplified)
      normalizeTemperature(log.temperature), // temp_min (simplified)
      normalizeHumidity(log.humidity),
      log.motionDetected ? 1 : 0,
      log.distance / 400, // Normalize distance
      Math.sin(2 * Math.PI * hour / 24), // hour_sin
      Math.cos(2 * Math.PI * hour / 24), // hour_cos
      Math.sin(2 * Math.PI * day / 7),    // day_sin
      Math.cos(2 * Math.PI * day / 7),    // day_cos
      day >= 5 ? 1 : 0, // is_weekend
      (hour >= 22 || hour <= 6) ? 1 : 0, // is_night
      0 // manual_actions (placeholder)
    ];
  });
  
  // Convert to tensor with shape [1, 168, 13]
  return tf.tensor3d([features], [1, 168, 13]);
}

function normalizeTemperature(temp: number): number {
  return (temp - 22) / 10; // Center around 22°C, scale by 10
}

function normalizeHumidity(humidity: number): number {
  return (humidity - 50) / 20; // Center around 50%, scale by 20
}

/**
 * Post-process model output to suggested schedules
 */
function postprocessSchedulePrediction(prediction: number[][]): any[] {
  // prediction shape: [1, 2] - [fanSpeed, ledBrightness]
  const fanSpeed = Math.round(prediction[0][0] * 100); // Convert to percentage
  const ledBrightness = Math.round(prediction[0][1] * 100);
  
  const now = new Date();
  const nextHour = new Date(now);
  nextHour.setHours(now.getHours() + 1, 0, 0, 0);
  
  return [
    {
      name: 'AI Suggested: Fan Control',
      deviceType: 'fan',
      value: fanSpeed,
      hour: nextHour.getHours(),
      minute: 0,
      days: [0, 1, 2, 3, 4, 5, 6],
      enabled: false, // User must manually enable
      mode: 'suggested',
      confidence: 0.85,
      createdAt: admin.firestore.FieldValue.serverTimestamp()
    },
    {
      name: 'AI Suggested: Light Control',
      deviceType: 'led',
      value: ledBrightness,
      hour: nextHour.getHours(),
      minute: 0,
      days: [0, 1, 2, 3, 4, 5, 6],
      enabled: false,
      mode: 'suggested',
      confidence: 0.82,
      createdAt: admin.firestore.FieldValue.serverTimestamp()
    }
  ];
}

/**
 * Save predicted schedules to Firestore
 */
async function savePredictedSchedules(userId: string, schedules: any[]) {
  const batch = db.batch();
  
  for (const schedule of schedules) {
    const docRef = db.collection('ml_predictions').doc();
    batch.set(docRef, {
      userId,
      predictionType: 'schedule',
      ...schedule
    });
  }
  
  await batch.commit();
  console.log(`Saved ${schedules.length} predicted schedules for user ${userId}`);
}

// ==================== ANOMALY DETECTION ====================

/**
 * Background Function: Detect Anomalies (runs every 6 hours)
 */
export const detectAnomalies = functions.pubsub
  .schedule('every 6 hours')
  .onRun(async (context) => {
    console.log('Starting anomaly detection for all users...');
    
    try {
      // Get all active users
      const usersSnapshot = await db.collection('users').limit(100).get();
      
      for (const userDoc of usersSnapshot.docs) {
        const userId = userDoc.id;
        
        try {
          const anomalyResult = await detectUserAnomalies(userId);
          
          if (anomalyResult.isAnomalous) {
            // Send alert to caregivers
            await sendAnomalyAlert(userId, anomalyResult);
          }
        } catch (error) {
          console.error(`Anomaly detection failed for user ${userId}:`, error);
        }
      }
      
      console.log('Anomaly detection complete');
      return null;
      
    } catch (error) {
      console.error('Anomaly detection error:', error);
      throw error;
    }
  });

/**
 * Detect anomalies for a single user
 */
async function detectUserAnomalies(userId: string) {
  // 1. Fetch last 24 hours
  const sensorLogs = await fetchSensorLogs(userId, 24);
  
  if (sensorLogs.length < 24) {
    return { isAnomalous: false, reason: 'Insufficient data' };
  }
  
  // 2. Analyze patterns (simplified heuristics)
  const motionEvents = sensorLogs.filter(log => log.motionDetected).length;
  const avgTemp = sensorLogs.reduce((sum, log) => sum + log.temperature, 0) / sensorLogs.length;
  
  // Check for anomalies
  let isAnomalous = false;
  let anomalyType = '';
  let severity = 'low';
  let description = '';
  
  // 1. Extended inactivity
  if (motionEvents === 0) {
    isAnomalous = true;
    anomalyType = 'extended_inactivity';
    severity = 'high';
    description = 'No motion detected for 24 hours';
  }
  
  // 2. Temperature extreme
  if (avgTemp < 18 || avgTemp > 30) {
    isAnomalous = true;
    anomalyType = 'temperature_extreme';
    severity = 'medium';
    description = `Temperature outside comfort range: ${avgTemp.toFixed(1)}°C`;
  }
  
  // 3. Unusual nighttime activity
  const nightLogs = sensorLogs.filter(log => {
    const hour = log.timestamp.toDate().getHours();
    return (hour >= 22 || hour <= 6);
  });
  const nightMotion = nightLogs.filter(log => log.motionDetected).length;
  
  if (nightMotion > nightLogs.length * 0.5) {
    isAnomalous = true;
    anomalyType = 'excessive_night_activity';
    severity = 'medium';
    description = 'Unusual activity during nighttime hours';
  }
  
  return {
    isAnomalous,
    anomalyType,
    severity,
    description
  };
}

/**
 * Send anomaly alert to caregivers
 */
async function sendAnomalyAlert(userId: string, anomalyResult: any) {
  // 1. Get user's caregivers
  const caregiversSnapshot = await db.collection('caregiver_relationships')
    .where('userId', '==', userId)
    .where('status', '==', 'active')
    .get();
  
  const caregiverIds = caregiversSnapshot.docs.map(doc => doc.data().caregiverId);
  
  // 2. Create alert document
  const alertData = {
    userId,
    type: 'health',
    severity: anomalyResult.severity,
    title: 'Unusual Activity Detected',
    message: anomalyResult.description,
    data: {
      anomalyType: anomalyResult.anomalyType
    },
    read: false,
    acknowledged: false,
    timestamp: admin.firestore.FieldValue.serverTimestamp()
  };
  
  const alertRef = await db.collection('alerts').add(alertData);
  console.log(`Created alert: ${alertRef.id}`);
  
  // 3. Send push notifications to caregivers
  for (const caregiverId of caregiverIds) {
    try {
      const caregiverDoc = await db.collection('users').doc(caregiverId).get();
      const fcmToken = caregiverDoc.data()?.fcmToken;
      
      if (fcmToken) {
        await admin.messaging().send({
          token: fcmToken,
          notification: {
            title: '⚠️ SmartSync Alert',
            body: anomalyResult.description
          },
          data: {
            alertId: alertRef.id,
            userId: userId,
            type: 'anomaly'
          },
          android: {
            priority: 'high'
          },
          apns: {
            payload: {
              aps: {
                sound: 'default',
                badge: 1
              }
            }
          }
        });
        
        console.log(`Sent notification to caregiver: ${caregiverId}`);
      }
    } catch (error) {
      console.error(`Failed to notify caregiver ${caregiverId}:`, error);
    }
  }
}