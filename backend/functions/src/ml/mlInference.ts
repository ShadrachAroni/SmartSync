/**
 * SmartSync ML Inference - Clean Implementation
 * File: backend/functions/src/ml/mlInference.ts
 * 
 * Handles server-side machine learning inference:
 * - Schedule prediction (optimal device schedules)
 * - Anomaly detection (unusual behavior patterns)
 * 
 * Uses TensorFlow.js with TFJS format models (model.json + shards)
 */

import * as functions from 'firebase-functions/v1';
import * as admin from 'firebase-admin';
import * as tf from '@tensorflow/tfjs-node';
import * as path from 'path';
import * as fs from 'fs';

const db = admin.firestore();
const MODEL_BASE_PATH = path.join(__dirname, '../../models');
const SCHEDULE_MODEL_DIR = path.join(MODEL_BASE_PATH, 'schedule_predictor_v1');
const SCALER_FILE = path.join(SCHEDULE_MODEL_DIR, 'scaler_params.json');
const INPUT_FEATURES = [
  'temperature_mean',
  'temperature_max',
  'temperature_min',
  'humidity_mean',
  'motionDetected_sum',
  'hour_sin',
  'hour_cos',
  'is_weekend',
];
const NUM_FEATURES = INPUT_FEATURES.length;

// ==================== TYPE DEFINITIONS ====================

interface SensorLog {
  timestamp: FirebaseFirestore.Timestamp;
  userId: string;
  deviceId: string;
  temperature: number;
  humidity: number;
  motionDetected: boolean;
  fanSpeed: number;
  ledBrightness: number;
  distance: number;
}

interface ScalerParams {
  mean: number[];
  scale?: number[];
  std?: number[];
  featureNames?: string[];
}

interface ModelCache {
  model: any;
  scaler: ScalerParams | null;
  loadedAt: number;
}

interface ValidationResult {
  valid: boolean;
  reason?: string;
}

interface Schedule {
  name: string;
  deviceType: string;
  value: number;
  hour: number;
  minute: number;
  days: number[];
  enabled: boolean;
  mode: string;
  confidence: number;
  createdAt: FirebaseFirestore.FieldValue;
  deviceId?: string;
  deviceName?: string;
  roomId?: string;
  reason?: string;
}

// ==================== CONFIGURATION ====================

const MODEL_CACHE: Record<string, ModelCache> = {};
const CACHE_TTL_MS = 3600000; // 1 hour
const REQUIRED_HOURS = 24; // 1 day - matches converted TFLite model sequence_length from train_smart_home.py
const MAX_DATA_SPAN_DAYS = 2; // Reduced to match 24-hour requirement
const MAX_GAP_HOURS = 2;

// ==================== MODEL MANAGEMENT ====================

/**
 * Load TensorFlow.js model from Firebase Storage
 * Uses caching to avoid repeated downloads
 */
async function loadModel(modelName: string): Promise<any> {
  console.log(`📥 Loading model: ${modelName}`);

  // Check cache
  const cached = MODEL_CACHE[modelName];
  const now = Date.now();

  if (cached?.model && (now - cached.loadedAt) < CACHE_TTL_MS) {
    console.log('✅ Using cached model');
    return cached.model;
  }

  try {
    const modelPath = SCHEDULE_MODEL_DIR;
    console.log(`Loading SavedModel from ${modelPath}`);

    const model = await tf.node.loadSavedModel(modelPath);

    console.log('🔥 Warming up model...');
    const dummyInput = tf.zeros([1, REQUIRED_HOURS, NUM_FEATURES]);
    const warmup = model.predict(dummyInput);

    if (Array.isArray(warmup)) {
      warmup.forEach((tensor) => tensor.dispose());
    } else if (warmup && typeof warmup['dispose'] === 'function') {
      (warmup as tf.Tensor).dispose();
    }
    dummyInput.dispose();

    if (!MODEL_CACHE[modelName]) {
      MODEL_CACHE[modelName] = { model: null, scaler: null, loadedAt: 0 };
    }
    MODEL_CACHE[modelName].model = model;
    MODEL_CACHE[modelName].loadedAt = now;

    console.log('✅ Model loaded from local filesystem');
    return model;
  } catch (error) {
    console.error('❌ Model loading failed:', error);
    throw new functions.https.HttpsError(
      'internal',
      `Failed to load model: ${error instanceof Error ? error.message : 'Unknown error'}`
    );
  }
}

/**
 * Load StandardScaler parameters from Firebase Storage
 * These are used to normalize input features the same way as during training
 */
async function loadScaler(modelName: string): Promise<ScalerParams> {
  console.log(`📥 Loading scaler for ${modelName}`);

  // Check cache
  const cached = MODEL_CACHE[modelName]?.scaler;
  if (cached) {
    console.log('✅ Using cached scaler');
    return cached;
  }

  try {
    if (!fs.existsSync(SCALER_FILE)) {
      console.warn('⚠️  Scaler file not found. Using identity scaling.');
      const identityScaler: ScalerParams = {
        mean: Array(NUM_FEATURES).fill(0),
        scale: Array(NUM_FEATURES).fill(1),
      };
      if (!MODEL_CACHE[modelName]) {
        MODEL_CACHE[modelName] = { model: null, scaler: null, loadedAt: 0 };
      }
      MODEL_CACHE[modelName].scaler = identityScaler;
      return identityScaler;
    }

    const scalerRaw = fs.readFileSync(SCALER_FILE, 'utf-8');
    const scalerData = JSON.parse(scalerRaw) as ScalerParams;

    if (!scalerData.mean) {
      throw new Error('Invalid scaler data: missing mean array');
    }

    if (!MODEL_CACHE[modelName]) {
      MODEL_CACHE[modelName] = { model: null, scaler: null, loadedAt: 0 };
    }
    MODEL_CACHE[modelName].scaler = scalerData;

    console.log('✅ Scaler loaded from local file');
    return scalerData;
  } catch (error) {
    console.error('❌ Scaler loading failed:', error);
    throw new functions.https.HttpsError(
      'internal',
      `Failed to load scaler: ${error instanceof Error ? error.message : 'Unknown error'}`
    );
  }
}

// ==================== DATA VALIDATION ====================

/**
 * Validate sensor data quality before inference
 * Checks for quantity, time gaps, and value ranges
 */
function validateSensorData(logs: SensorLog[]): ValidationResult {
  // Check minimum quantity
  if (logs.length < REQUIRED_HOURS) {
    return {
      valid: false,
      reason: `Insufficient data: ${logs.length} records (need ${REQUIRED_HOURS})`
    };
  }

  // Check time span (should be around 1 day, not spread over weeks)
  const timestamps = logs.map(l => l.timestamp.toDate());
  const timeSpanMs = timestamps[timestamps.length - 1].getTime() - timestamps[0].getTime();
  const days = timeSpanMs / (1000 * 60 * 60 * 24);

  if (days > MAX_DATA_SPAN_DAYS) {
    return {
      valid: false,
      reason: `Data too sparse: spans ${days.toFixed(1)} days (max ${MAX_DATA_SPAN_DAYS})`
    };
  }

  // Check for large gaps between consecutive readings
  for (let i = 1; i < timestamps.length; i++) {
    const gapMs = timestamps[i].getTime() - timestamps[i - 1].getTime();
    const gapHours = gapMs / (1000 * 60 * 60);

    if (gapHours > MAX_GAP_HOURS) {
      return {
        valid: false,
        reason: `Large gap detected: ${gapHours.toFixed(1)} hours between readings`
      };
    }
  }

  // Validate temperature range (reasonable indoor temperatures)
  const temps = logs.map(l => l.temperature);
  const invalidTemps = temps.filter(t => t < 10 || t > 45 || isNaN(t));

  if (invalidTemps.length > logs.length * 0.1) { // Allow max 10% invalid
    return {
      valid: false,
      reason: `Too many invalid temperatures: ${invalidTemps.length}/${logs.length}`
    };
  }

  // Validate humidity range
  const humidities = logs.map(l => l.humidity);
  const invalidHumidity = humidities.filter(h => h < 0 || h > 100 || isNaN(h));

  if (invalidHumidity.length > logs.length * 0.1) {
    return {
      valid: false,
      reason: `Too many invalid humidity readings: ${invalidHumidity.length}/${logs.length}`
    };
  }

  // Check for required fields
  const requiredFields: (keyof SensorLog)[] = [
    'temperature', 'humidity', 'motionDetected', 'fanSpeed', 'ledBrightness'
  ];

  for (const field of requiredFields) {
    const missingCount = logs.filter(log => 
      log[field] === undefined || log[field] === null
    ).length;

    if (missingCount > 0) {
      return {
        valid: false,
        reason: `Missing ${field} in ${missingCount} records`
      };
    }
  }

  return { valid: true };
}

// ==================== PREPROCESSING ====================

/**
 * Preprocess sensor logs into model input format
 * - Extracts features
 * - Adds temporal features (hour, day, cyclical encoding)
 * - Normalizes using StandardScaler parameters
 */
function preprocessScheduleInput(logs: SensorLog[], scaler: ScalerParams): tf.Tensor3D {
  console.log('🔧 Preprocessing input data...');

  const features: number[][] = logs.map(log => {
    const timestamp = log.timestamp.toDate();
    const hour = timestamp.getHours();
    const day = timestamp.getDay();

    return [
      log.temperature,                          // temperature_mean
      log.temperature,                          // temperature_max (approximate)
      log.temperature,                          // temperature_min (approximate)
      log.humidity,                             // humidity_mean
      log.motionDetected ? 1 : 0,               // motionDetected_sum
      Math.sin((2 * Math.PI * hour) / 24),      // hour_sin
      Math.cos((2 * Math.PI * hour) / 24),      // hour_cos
      day >= 5 ? 1 : 0,                         // is_weekend
    ];
  });

  // Normalize features using scaler parameters
  const divisors = scaler.scale ?? scaler.std ?? Array(NUM_FEATURES).fill(1);
  const normalizedFeatures = features.map(row =>
    row.map((val, idx) => {
      const mean = scaler.mean[idx] ?? 0;
      const divisor = divisors[idx] ?? 1;
      return (val - mean) / divisor;
    })
  );

  // Convert to tensor with shape [1, 24, N] where N is the number of features
  // Batch size = 1, Timesteps = 24 (1 day), Features = N
  // Ensure we have exactly 24 timesteps (pad or truncate if needed)
  let featuresToUse = normalizedFeatures;
  if (featuresToUse.length > 24) {
    // Take last 24 hours
    featuresToUse = featuresToUse.slice(-24);
  } else if (featuresToUse.length < 24) {
    // Pad with last hour's data
    const lastHour = featuresToUse[featuresToUse.length - 1] || new Array(normalizedFeatures[0]?.length || 8).fill(0);
    while (featuresToUse.length < 24) {
      featuresToUse.unshift([...lastHour]);
    }
  }
  
  const tensor = tf.tensor3d([featuresToUse], [1, REQUIRED_HOURS, NUM_FEATURES]);

  console.log(`✅ Preprocessed tensor shape: ${tensor.shape}`);
  return tensor;
}

/**
 * Post-process model output into schedule suggestions
 */
async function buildScheduleSuggestions(
  userId: string,
  prediction: number[][]
): Promise<Schedule[]> {
  const devicesSnapshot = await db.collection('devices')
    .where('userId', '==', userId)
    .get();

  if (devicesSnapshot.empty) {
    console.log('⚠️  No devices found for user, skipping schedule suggestions');
    return [];
  }

  const devices = devicesSnapshot.docs.map(doc => ({
    id: doc.id,
    ...(doc.data() as any)
  }));

  const fanDevice = devices.find(device => device.type === 'fan');
  const lightDevice = devices.find(device => device.type === 'light');

  if (!fanDevice && !lightDevice) {
    console.log('⚠️  User has no controllable fan/light devices');
    return [];
  }

  const nextHour = new Date();
  nextHour.setHours(nextHour.getHours() + 1, 0, 0, 0);

  const fanSpeed = Math.round(Math.max(0, Math.min(100, prediction[0][0] * 100)));
  const ledBrightness = Math.round(Math.max(0, Math.min(100, prediction[0][1] * 100)));

  const suggestions: Schedule[] = [];

  if (fanDevice) {
    suggestions.push({
      name: `AI Suggested: ${fanDevice.name}`,
      deviceType: 'fan',
      deviceId: fanDevice.id,
      deviceName: fanDevice.name,
      roomId: fanDevice.roomId ?? '',
      value: fanSpeed,
      hour: nextHour.getHours(),
      minute: nextHour.getMinutes(),
      days: [0, 1, 2, 3, 4, 5, 6],
      enabled: false,
      mode: 'suggested',
      confidence: 0.85,
      reason: 'Based on last 24 hours of fan usage patterns',
      createdAt: admin.firestore.FieldValue.serverTimestamp()
    });
  }

  if (lightDevice) {
    suggestions.push({
      name: `AI Suggested: ${lightDevice.name}`,
      deviceType: 'light',
      deviceId: lightDevice.id,
      deviceName: lightDevice.name,
      roomId: lightDevice.roomId ?? '',
      value: ledBrightness,
      hour: nextHour.getHours(),
      minute: nextHour.getMinutes(),
      days: [0, 1, 2, 3, 4, 5, 6],
      enabled: false,
      mode: 'suggested',
      confidence: 0.82,
      reason: 'Based on last 24 hours of lighting patterns',
      createdAt: admin.firestore.FieldValue.serverTimestamp()
    });
  }

  return suggestions;
}

// ==================== SCHEDULE PREDICTION ====================

/**
 * HTTP Callable Function: Predict Optimal Schedule
 * 
 * Client usage:
 * ```dart
 * final result = await FirebaseFunctions.instance
 *   .httpsCallable('predictSchedule')
 *   .call({'userId': userId});
 * ```
 */
export const predictSchedule = functions
  .runWith({
    timeoutSeconds: 300,  // 5 minutes
    memory: '1GB'         // Enough for TensorFlow.js
  })
  .https.onCall(async (data, context) => {
    console.log('🔮 Schedule prediction started');

    // 1. Authentication check
    if (!context.auth) {
      throw new functions.https.HttpsError(
        'unauthenticated',
        'User must be authenticated'
      );
    }

    const userId = data.userId || context.auth.uid;
    console.log(`User: ${userId}`);

    try {
      // 2. Fetch sensor logs (last 24 hours - matches converted TFLite model)
      const cutoffDate = new Date();
      cutoffDate.setHours(cutoffDate.getHours() - REQUIRED_HOURS);

      const logsSnapshot = await db.collection('sensor_logs')
        .where('userId', '==', userId)
        .where('timestamp', '>=', cutoffDate)
        .orderBy('timestamp', 'asc')
        .limit(REQUIRED_HOURS)
        .get();

      const sensorLogs = logsSnapshot.docs.map(doc => doc.data() as SensorLog);
      console.log(`📊 Fetched ${sensorLogs.length} sensor logs`);

      // 3. Validate data quality
      const validation = validateSensorData(sensorLogs);
      if (!validation.valid) {
        console.warn(`⚠️  Validation failed: ${validation.reason}`);
        throw new functions.https.HttpsError(
          'failed-precondition',
          validation.reason || 'Invalid sensor data'
        );
      }

      // 4. Load model and scaler
      console.log('🤖 Loading ML resources...');
      const [model, scaler] = await Promise.all([
        loadModel('schedule_predictor'),
        loadScaler('schedule_predictor')
      ]);

      // 5. Preprocess input
      const inputTensor = preprocessScheduleInput(sensorLogs, scaler);

      // 6. Run inference
      console.log('⚡ Running inference...');
      const predictionTensor = model.predict(inputTensor) as tf.Tensor;
      const predictionData = await predictionTensor.array() as number[][];

      // 7. Post-process results
      const suggestedSchedules = await buildScheduleSuggestions(userId, predictionData);
      console.log(`✅ Generated ${suggestedSchedules.length} schedule suggestions`);

      // 8. Save to Firestore
      const batch = db.batch();
      suggestedSchedules.forEach(schedule => {
        const docRef = db.collection('ml_predictions').doc();
        batch.set(docRef, {
          userId,
          predictionType: 'schedule',
          ...schedule
        });
      });
      await batch.commit();
      console.log('💾 Saved predictions to Firestore');

      // 9. Cleanup tensors to prevent memory leaks
      inputTensor.dispose();
      predictionTensor.dispose();

      // 10. Return results
      return {
        success: true,
        schedules: suggestedSchedules,
        timestamp: admin.firestore.FieldValue.serverTimestamp()
      };

    } catch (error) {
      console.error('❌ Prediction failed:', error);

      // Re-throw HttpsErrors as-is
      if (error instanceof functions.https.HttpsError) {
        throw error;
      }

      // Wrap other errors
      throw new functions.https.HttpsError(
        'internal',
        `Prediction failed: ${error instanceof Error ? error.message : 'Unknown error'}`
      );
    }
  });

// ==================== ANOMALY DETECTION ====================

/**
 * Scheduled Function: Detect Anomalies
 * Runs every 6 hours to check for unusual behavior patterns
 */
export const detectAnomalies = functions.pubsub
  .schedule('every 6 hours')
  .timeZone('UTC')
  .onRun(async (context) => {
    console.log('🔍 Starting anomaly detection...');

    try {
      // Get all active users
      const usersSnapshot = await db.collection('users')
        .limit(100) // Process in batches
        .get();

      let alertsCreated = 0;

      for (const userDoc of usersSnapshot.docs) {
        const userId = userDoc.id;

        try {
          const anomalyResult = await detectUserAnomalies(userId);

          if (anomalyResult.isAnomalous) {
            await createAnomalyAlert(userId, anomalyResult);
            alertsCreated++;
          }

        } catch (error) {
          console.error(`Error detecting anomalies for user ${userId}:`, error);
        }
      }

      console.log(`✅ Anomaly detection complete. Created ${alertsCreated} alerts.`);
      return null;

    } catch (error) {
      console.error('❌ Anomaly detection failed:', error);
      throw error;
    }
  });

/**
 * Detect anomalies for a single user
 */
async function detectUserAnomalies(userId: string): Promise<{
  isAnomalous: boolean;
  anomalyType?: string;
  severity?: string;
  description?: string;
}> {
  // Fetch last 24 hours of data
  const cutoffDate = new Date();
  cutoffDate.setHours(cutoffDate.getHours() - 24);

  const logsSnapshot = await db.collection('sensor_logs')
    .where('userId', '==', userId)
    .where('timestamp', '>=', cutoffDate)
    .get();

  const logs = logsSnapshot.docs.map(doc => doc.data() as SensorLog);

  if (logs.length < 24) {
    return { isAnomalous: false }; // Insufficient data
  }

  // Simple heuristic-based anomaly detection
  const motionEvents = logs.filter(log => log.motionDetected).length;
  const avgTemp = logs.reduce((sum, log) => sum + log.temperature, 0) / logs.length;

  // Check for anomalies
  let isAnomalous = false;
  let anomalyType = '';
  let severity = 'low';
  let description = '';

  // 1. Extended inactivity (no motion for 24 hours)
  if (motionEvents === 0) {
    isAnomalous = true;
    anomalyType = 'extended_inactivity';
    severity = 'high';
    description = 'No motion detected for 24 hours';
  }

  // 2. Temperature extremes
  else if (avgTemp < 18 || avgTemp > 30) {
    isAnomalous = true;
    anomalyType = 'temperature_extreme';
    severity = 'medium';
    description = `Temperature outside comfort range: ${avgTemp.toFixed(1)}°C`;
  }

  // 3. Unusual nighttime activity
  else {
    const nightLogs = logs.filter(log => {
      const hour = log.timestamp.toDate().getHours();
      return hour >= 22 || hour <= 6;
    });

    const nightMotion = nightLogs.filter(log => log.motionDetected).length;

    if (nightMotion > nightLogs.length * 0.5) {
      isAnomalous = true;
      anomalyType = 'excessive_night_activity';
      severity = 'medium';
      description = 'Unusual activity during nighttime hours';
    }
  }

  return { isAnomalous, anomalyType, severity, description };
}

/**
 * Create anomaly alert and notify caregivers
 */
async function createAnomalyAlert(userId: string, anomalyResult: {
  anomalyType?: string;
  severity?: string;
  description?: string;
}): Promise<void> {
  // Create alert document
  const alertData = {
    userId,
    type: 'health',
    severity: anomalyResult.severity || 'low',
    title: 'Unusual Activity Detected',
    message: anomalyResult.description || 'Anomaly detected',
    data: {
      anomalyType: anomalyResult.anomalyType
    },
    read: false,
    acknowledged: false,
    timestamp: admin.firestore.FieldValue.serverTimestamp()
  };

  const alertRef = await db.collection('alerts').add(alertData);
  console.log(`📢 Created alert ${alertRef.id} for user ${userId}`);

  // Get caregivers
  const caregiversSnapshot = await db.collection('caregiver_relationships')
    .where('userId', '==', userId)
    .where('status', '==', 'active')
    .get();

  // Send push notifications
  for (const caregiverDoc of caregiversSnapshot.docs) {
    const caregiverId = caregiverDoc.data().caregiverId;

    try {
      const caregiverUserDoc = await db.collection('users').doc(caregiverId).get();
      const fcmToken = caregiverUserDoc.data()?.fcmToken;

      if (fcmToken) {
        await admin.messaging().send({
          token: fcmToken,
          notification: {
            title: '⚠️ SmartSync Alert',
            body: anomalyResult.description || 'Anomaly detected'
          },
          data: {
            alertId: alertRef.id,
            userId: userId,
            type: 'anomaly'
          },
          android: {
            priority: 'high',
            notification: {
              sound: 'default'
            }
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

        console.log(`📱 Sent notification to caregiver ${caregiverId}`);
      }

    } catch (error) {
      console.error(`Failed to notify caregiver ${caregiverId}:`, error);
    }
  }
}