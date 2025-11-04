# SmartSync Backend - Firebase Cloud Functions

This directory contains Firebase Cloud Functions for the SmartSync smart home monitoring system. The backend provides server-side ML inference, real-time alerts, data analytics, and automated maintenance tasks.

---

## 📋 Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Initial Setup](#initial-setup)
- [ML Model Integration](#ml-model-integration)
- [Deployment](#deployment)
- [Testing Functions](#testing-functions)
- [Available Functions](#available-functions)
- [Troubleshooting](#troubleshooting)

---

## 🎯 Overview

### Architecture

```
SmartSync Backend
│
├── Cloud Functions (Node.js/TypeScript)
│   ├── ML Inference (schedule prediction, anomaly detection)
│   ├── Authentication (user management, custom tokens)
│   ├── Analytics (data aggregation, report generation)
│   ├── Notifications (push alerts, schedule reminders)
│   └── Maintenance (data cleanup, device status)
│
├── Firestore Security Rules
├── Storage Security Rules
└── ML Models (TFLite) in Firebase Storage
```

### Key Features

- 🤖 **Server-side ML**: Run predictions on Firebase using TensorFlow.js
- 📊 **Analytics**: Daily data aggregation and on-demand reports
- 🔔 **Real-time Alerts**: Push notifications for anomalies and schedules
- 🔒 **Secure**: Firestore rules enforce user data privacy
- 🧹 **Auto-cleanup**: Remove old data to control storage costs

---

## 📦 Prerequisites

Before setting up the backend, ensure you have:

### 1. Software Requirements

```bash
# Node.js 18+ (required by Firebase Functions)
node --version  # Should be v18.x or higher

# npm (comes with Node.js)
npm --version

# Firebase CLI
npm install -g firebase-tools
firebase --version
```

### 2. Firebase Project Setup

1. **Create Firebase Project** (if not done):
   - Go to [Firebase Console](https://console.firebase.google.com)
   - Create new project or use existing `smartsync-cf370`

2. **Enable Required Services**:
   - ✅ Authentication (Email/Password, Google)
   - ✅ Cloud Firestore
   - ✅ Cloud Storage
   - ✅ Cloud Functions
   - ✅ Cloud Messaging (for push notifications)

3. **Upgrade to Blaze Plan** (required for Cloud Functions):
   - Firebase Console → Project Settings → Usage and Billing
   - Note: Pay-as-you-go, but includes generous free tier

### 3. ML Models Ready

Your ML models must be trained and converted to TFLite format:

```bash
# From project root
cd ml

# Train model (uses HomeC.csv, aruba.csv, tulum.csv)
python scripts/train_smart_home.py

# Convert to TFLite
python scripts/convert_tflite.py

# Deploy to Firebase Storage
python scripts/deploy_model.py
```

**Important**: The backend functions expect models at:
- `gs://smartsync-cf370.appspot.com/models/schedule_predictor_v1.tflite`
- `gs://smartsync-cf370.appspot.com/models/anomaly_detector_v1.tflite`

---

## 🚀 Initial Setup

### Step 1: Firebase Login

```bash
# Login to Firebase
firebase login

# Verify logged in account
firebase projects:list
```

### Step 2: Initialize Firebase Project

```bash
cd backend

# Link to your Firebase project
firebase use smartsync-cf370

# Or select interactively
firebase use --add
```

### Step 3: Install Dependencies

```bash
cd functions

# Install all npm packages
npm install

# Expected packages:
# - firebase-admin (Firestore, Storage, Auth)
# - firebase-functions (Cloud Functions runtime)
# - @tensorflow/tfjs (ML inference)
```

### Step 4: Configure Service Account (Optional)

For ML model deployment, you need a service account key:

1. **Download Service Account Key**:
   - Firebase Console → Project Settings → Service Accounts
   - Click "Generate New Private Key"
   - Save as `backend/serviceAccountKey.json`

2. **Add to .gitignore** (already configured):
   ```
   backend/functions/node_modules
   backend/serviceAccountKey.json
   ```

---

## 🤖 ML Model Integration

### How Backend Uses ML Models

The backend loads TFLite models from Firebase Storage and uses TensorFlow.js for inference:

```typescript
// In backend/functions/src/ml/mlInference.ts

// Model loading (on cold start)
const model = await tf.loadLayersModel(
  'gs://smartsync-cf370.appspot.com/models/schedule_predictor_v1.tflite'
);

// Inference
const prediction = model.predict(inputTensor);
```

### Linking ML Training to Backend

#### 1. Train Models Locally

```bash
cd ml

# Train using Kaggle datasets
python scripts/train_smart_home.py

# Output:
# - ml/models/saved_models/schedule_predictor_v1/ (Keras)
# - ml/data/processed/scaler.pkl
```

#### 2. Convert to TFLite

```bash
# Convert Keras → TFLite
python scripts/convert_tflite.py

# Output:
# - ml/models/tflite/schedule_predictor.tflite
# - ml/models/tflite/schedule_predictor.json (metadata)
```

#### 3. Deploy to Firebase Storage

```bash
# Upload models to Cloud Storage
python scripts/deploy_model.py

# What it does:
# 1. Uploads .tflite files to gs://smartsync-cf370.appspot.com/models/
# 2. Updates Firestore: system_config/ml_models with URLs
# 3. Makes models accessible to Cloud Functions
```

#### 4. Verify Deployment

```bash
# Check if models are in Storage
firebase storage:list models/

# Expected output:
# models/schedule_predictor_v1.tflite
# models/anomaly_detector_v1.tflite
```

### Model Update Workflow

When you retrain models:

```bash
# 1. Retrain (ml folder)
cd ml
python scripts/train_smart_home.py

# 2. Convert
python scripts/convert_tflite.py

# 3. Deploy new version
python scripts/deploy_model.py

# 4. Redeploy Cloud Functions (backend folder)
cd ../backend
firebase deploy --only functions
```

The functions automatically load the latest models on cold start.

---

## 🚢 Deployment

### Deploy All Functions

```bash
cd backend

# Deploy everything (functions, Firestore rules, Storage rules)
firebase deploy

# Or deploy selectively:
firebase deploy --only functions        # Just Cloud Functions
firebase deploy --only firestore:rules  # Just Firestore security
firebase deploy --only storage:rules    # Just Storage security
```

### Deploy Individual Functions

```bash
# Deploy specific function
firebase deploy --only functions:predictSchedule
firebase deploy --only functions:detectAnomalies
firebase deploy --only functions:sendAlert
```

### First Deployment

On first deployment, Firebase will:
1. Create Cloud Functions in your project
2. Apply Firestore security rules
3. Apply Storage security rules
4. Set up scheduled functions (cron jobs)

**Expected output:**
```
✔  Deploy complete!

Functions:
  predictSchedule(us-central1)
  detectAnomalies(us-central1)
  onUserCreate(us-central1)
  onUserDelete(us-central1)
  createCustomToken(us-central1)
  aggregateData(us-central1)
  generateReport(us-central1)
  sendAlert(us-central1)
  scheduleReminder(us-central1)
  cleanupOldLogs(us-central1)
  onDeviceStatusUpdate(us-central1)
```

---

## 🧪 Testing Functions

### Test ML Prediction Function

#### From Flutter App:

```dart
// In your Flutter app
import 'package:cloud_functions/cloud_functions.dart';

final functions = FirebaseFunctions.instance;

// Call predictSchedule
final result = await functions
  .httpsCallable('predictSchedule')
  .call({
    'userId': FirebaseAuth.instance.currentUser!.uid,
  });

print(result.data['schedules']);
```

#### From Firebase Console:

1. Go to Firebase Console → Functions
2. Select `predictSchedule`
3. Click "Logs" to see execution history
4. Use "Test" feature (requires Firebase Extensions)

#### Using curl:

```bash
# Get your function URL
firebase functions:config:get

# Call function (requires auth token)
curl -X POST https://us-central1-smartsync-cf370.cloudfunctions.net/predictSchedule \
  -H "Authorization: Bearer YOUR_ID_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"userId": "USER_ID_HERE"}'
```

### Test Scheduled Functions

Scheduled functions run automatically:

- `aggregateData`: Every day at midnight UTC
- `detectAnomalies`: Every 6 hours
- `scheduleReminder`: Every 5 minutes
- `cleanupOldLogs`: Weekly on Sunday at 2 AM UTC

To test manually:

```bash
# Trigger scheduled function locally
firebase functions:shell

# In the shell:
aggregateData()
```

### View Function Logs

```bash
# Stream logs in real-time
firebase functions:log --only predictSchedule

# View last 50 log entries
firebase functions:log --limit 50

# Filter by severity
firebase functions:log --only error
```

---

## 📚 Available Functions

### 🤖 ML Functions

#### `predictSchedule(data, context)`
**Type**: HTTPS Callable  
**Trigger**: Client call  
**Purpose**: Generate AI-powered schedule suggestions

**Input**:
```json
{
  "userId": "firebase_user_id"
}
```

**Output**:
```json
{
  "success": true,
  "schedules": [
    {
      "name": "AI Suggested: Fan Control",
      "deviceType": "fan",
      "value": 75,
      "hour": 14,
      "minute": 0,
      "confidence": 0.85
    }
  ]
}
```

**Error Cases**:
- `unauthenticated`: User not logged in
- `failed-precondition`: Insufficient historical data (need 168 hours)
- `internal`: Model loading or inference failed

---

#### `detectAnomalies(context)`
**Type**: PubSub Scheduled  
**Trigger**: Every 6 hours (automatic)  
**Purpose**: Detect unusual behavior patterns

**What it does**:
1. Analyzes last 24 hours of sensor data for all users
2. Detects anomalies:
   - Extended inactivity (no motion for 24h)
   - Temperature extremes (<18°C or >30°C)
   - Excessive nighttime activity
3. Creates alerts in Firestore (`alerts` collection)
4. Sends push notifications to caregivers

**No direct client call** - runs automatically in background.

---

### 🔐 Auth Functions

#### `onUserCreate(user)`
**Type**: Auth Trigger  
**Trigger**: New user signs up  
**Purpose**: Create initial user profile

**Auto-creates Firestore document**:
```javascript
// Collection: users/{userId}
{
  email: "user@example.com",
  name: "John Doe",
  deviceIds: [],
  createdAt: Timestamp,
  preferences: {
    notifications: true,
    theme: "light",
    language: "en"
  }
}
```

---

#### `onUserDelete(user)`
**Type**: Auth Trigger  
**Trigger**: User account deleted  
**Purpose**: Cleanup all user data

**Deletes**:
- User profile (`users/{userId}`)
- User's devices (`devices` collection)
- User's sensor logs (`sensor_logs` collection)
- Associated schedules, alerts, etc.

---

#### `createCustomToken(data, context)`
**Type**: HTTPS Callable  
**Trigger**: Client call  
**Purpose**: Generate custom auth token for Bluetooth devices

**Input**:
```json
{
  "deviceId": "ESP32_MAC_ADDRESS",
  "secret": "DEVICE_SECRET_KEY"
}
```

**Output**:
```json
{
  "success": true,
  "token": "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9..."
}
```

**Use Case**: Arduino/ESP32 devices can authenticate without email/password.

---

### 📊 Analytics Functions

#### `aggregateData(context)`
**Type**: PubSub Scheduled  
**Trigger**: Daily at midnight UTC  
**Purpose**: Create daily analytics summaries

**Creates documents in `daily_analytics` collection**:
```javascript
{
  userId: "user_id",
  date: Timestamp,
  avgTemperature: 23.5,
  avgHumidity: 55.2,
  motionEvents: 45,
  avgFanUsage: 30,
  avgLedUsage: 180,
  totalReadings: 1440
}
```

---

#### `generateReport(data, context)`
**Type**: HTTPS Callable  
**Trigger**: Client call  
**Purpose**: Generate analytics report on demand

**Input**:
```json
{
  "userId": "firebase_user_id",
  "days": 30
}
```

**Output**:
```json
{
  "success": true,
  "summary": {
    "totalDays": 30,
    "avgTemperature": 23.2,
    "avgHumidity": 54.8,
    "totalMotionEvents": 1350
  },
  "dailyData": [ /* array of daily stats */ ]
}
```

---

### 🔔 Notification Functions

#### `sendAlert(snap, context)`
**Type**: Firestore Trigger  
**Trigger**: New document in `alerts` collection  
**Purpose**: Send push notifications for alerts

**Triggered when**:
- Anomaly detected
- Device offline
- Manual alert created

**Sends FCM notification to**:
- User's caregivers
- User's devices with FCM tokens

---

#### `scheduleReminder(context)`
**Type**: PubSub Scheduled  
**Trigger**: Every 5 minutes  
**Purpose**: Send reminders for upcoming schedules

**Logic**:
1. Query schedules running in next 10 minutes
2. Send FCM notification: "Fan will turn on in 10 minutes"
3. User can cancel/modify schedule

---

### 🧹 Maintenance Functions

#### `cleanupOldLogs(context)`
**Type**: PubSub Scheduled  
**Trigger**: Weekly on Sunday at 2 AM UTC  
**Purpose**: Delete sensor logs older than 90 days

**Why**: Control Firestore storage costs while keeping recent data.

---

#### `onDeviceStatusUpdate(snap, context)`
**Type**: Firestore Trigger  
**Trigger**: New sensor log created  
**Purpose**: Update device "last seen" timestamp

**Updates**:
```javascript
// devices/{deviceId}
{
  lastSeen: Timestamp,
  isOnline: true
}
```

---

## 🔧 Troubleshooting

### Issue: Functions fail to deploy

**Error**: `Build failed: npm install returned exit code 1`

**Solution**:
```bash
cd backend/functions
rm -rf node_modules package-lock.json
npm install
npm run build  # Verify TypeScript compiles
firebase deploy --only functions
```

---

### Issue: Model not loading in Cloud Functions

**Error**: `Model loading failed: gs://smartsync-cf370.appspot.com/models/schedule_predictor_v1.tflite not found`

**Solution**:
```bash
# 1. Verify model exists in Storage
firebase storage:list models/

# 2. If missing, deploy from ml folder
cd ml
python scripts/deploy_model.py

# 3. Check Firestore for model metadata
# Collection: system_config
# Document: ml_models

# 4. Redeploy functions
cd ../backend
firebase deploy --only functions
```

---

### Issue: Insufficient data for predictions

**Error**: `failed-precondition: Insufficient data (need 168 hours, got 0)`

**Cause**: User has no sensor logs in Firestore.

**Solution**:
1. **Arduino device must be running** and sending data to Firestore
2. **Wait 168 hours** (7 days) for sufficient data
3. For testing, populate Firestore with synthetic data:

```javascript
// Run this in Firebase Console or Node.js script
const db = admin.firestore();
const userId = 'YOUR_USER_ID';

for (let i = 0; i < 168; i++) {
  await db.collection('sensor_logs').add({
    userId: userId,
    deviceId: 'test_device',
    timestamp: new Date(Date.now() - i * 3600000), // 1 hour ago each
    temperature: 22 + Math.random() * 5,
    humidity: 55 + Math.random() * 10,
    motionDetected: Math.random() > 0.5,
    fanSpeed: Math.floor(Math.random() * 255),
    ledBrightness: Math.floor(Math.random() * 255),
    distance: 100 + Math.random() * 200
  });
}
```

---

### Issue: Push notifications not working

**Error**: Notifications not received on Flutter app

**Checklist**:
1. ✅ FCM enabled in Firebase Console
2. ✅ Flutter app has FCM token saved in Firestore:
   ```javascript
   // users/{userId}
   { fcmToken: "fcm_token_here" }
   ```
3. ✅ Caregiver relationship exists:
   ```javascript
   // caregiver_relationships
   {
     userId: "elderly_user_id",
     caregiverId: "caregiver_user_id",
     status: "active"
   }
   ```
4. ✅ Test notification:
   ```bash
   # Firebase Console → Cloud Messaging → Send test message
   ```

---

### Issue: Functions timeout

**Error**: `Function execution took 60000 ms, finished with status: timeout`

**Cause**: ML inference can be slow on cold start (model loading).

**Solutions**:
1. **Increase timeout** (default 60s):
   ```typescript
   // In functions/src/index.ts
   export const predictSchedule = functions
     .runWith({ timeoutSeconds: 300 }) // 5 minutes
     .https.onCall(async (data, context) => { ... });
   ```

2. **Use Cloud Run** for ML inference (faster, auto-scaling)

3. **Optimize model**: Use smaller model or quantization

---

### View Detailed Logs

```bash
# Real-time logs
firebase functions:log

# Filter by function
firebase functions:log --only predictSchedule

# Filter by time
firebase functions:log --since 2h

# View in Firebase Console
# https://console.firebase.google.com/project/smartsync-cf370/functions/logs
```

---

## 📞 Support & Resources

### Documentation
- [Firebase Cloud Functions](https://firebase.google.com/docs/functions)
- [TensorFlow.js](https://www.tensorflow.org/js)
- [Firestore Security Rules](https://firebase.google.com/docs/firestore/security/get-started)

### Project Structure
```
backend/
├── .firebaserc              # Firebase project config
├── firebase.json            # Deployment config
├── firestore.rules          # Firestore security rules
├── storage.rules            # Storage security rules
├── functions/
│   ├── package.json         # Dependencies
│   ├── tsconfig.json        # TypeScript config
│   └── src/
│       ├── index.ts         # Main entry point
│       ├── ml/
│       │   └── mlInference.ts
│       ├── auth/
│       ├── analytics/
│       └── notifications/
```

### Useful Commands
```bash
# Check function status
firebase functions:list

# View function config
firebase functions:config:get

# Delete function
firebase functions:delete functionName

# View quota/usage
firebase projects:list

# Emulate locally (optional)
firebase emulators:start
```

---

## ✅ Checklist: Backend Deployment

Before going live, ensure:

- [ ] Firebase project created and Blaze plan enabled
- [ ] ML models trained (`train_smart_home.py`)
- [ ] Models converted to TFLite (`convert_tflite.py`)
- [ ] Models deployed to Storage (`deploy_model.py`)
- [ ] Functions deployed (`firebase deploy`)
- [ ] Firestore rules deployed
- [ ] Storage rules deployed
- [ ] Test `predictSchedule` function works
- [ ] Test alerts are sent
- [ ] Scheduled functions verified (check logs after 24h)
- [ ] Flutter app can call functions successfully

---

## 🎉 You're Ready!

Your backend is now connected to your ML models and ready to serve the SmartSync Flutter app!

**Next Steps**:
1. Test functions from Flutter app
2. Monitor logs for errors
3. Set up Firebase Analytics (optional)
4. Configure Firebase Crashlytics (optional)

For issues, check logs:
```bash
firebase functions:log --limit 100
```

Happy coding! 🚀