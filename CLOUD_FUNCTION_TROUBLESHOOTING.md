# Cloud Function Troubleshooting Guide

## Issue: "Cloud Function predictSchedule not found"

If you're seeing this error even though you've deployed the function, follow these steps:

### Step 1: Verify Function Deployment

1. **Check Firebase Console**:
   - Go to [Firebase Console](https://console.firebase.google.com)
   - Select your project
   - Navigate to **Functions** section
   - Look for `predictSchedule` function
   - Check the **Region** (should be `us-central1` by default)

2. **Check via CLI**:
   ```bash
   cd backend
   firebase functions:list
   ```
   You should see `predictSchedule` in the list.

3. **Check Function Logs**:
   ```bash
   firebase functions:log --only predictSchedule
   ```
   This will show if the function is being called and any errors.

### Step 2: Verify Region Configuration

The app uses `us-central1` by default. If your function is in a different region:

1. **Check function region** in Firebase Console
2. **Update the app** to use the correct region:

   In `app/lib/services/ml_service.dart`, change:
   ```dart
   final FirebaseFunctions _functions = FirebaseFunctions.instance;
   ```
   
   To:
   ```dart
   final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(
     region: 'us-east1' // or whatever region your function is in
   );
   ```

### Step 3: Check App Check Configuration

If you see "App attestation failed" in logs, App Check might be blocking the function:

1. **In Firebase Console**:
   - Go to **App Check** section
   - Check if App Check is enabled
   - For development, ensure **Debug tokens** are configured

2. **For Development**:
   - App Check should be in **Debug mode** (see `app/lib/main.dart`)
   - Get your debug token from logs
   - Add it to Firebase Console → App Check → Apps → Your App → Debug tokens

3. **Temporarily Disable App Check** (for testing):
   - In Firebase Console → App Check
   - Temporarily disable App Check for Cloud Functions
   - Or add your app's debug token

### Step 4: Verify Authentication

Cloud Functions require authentication:

1. **Ensure user is logged in**:
   - Check that `FirebaseAuth.instance.currentUser` is not null
   - User must have verified email

2. **Check Firestore Security Rules**:
   - Ensure rules allow the user to read their own data
   - Function needs to query `sensor_logs` collection

### Step 5: Check Function Requirements

The function needs:
- **At least 24 hours of sensor data** (you have 30 days, so this is fine)
- **Data in `sensor_logs` collection** with:
  - `userId` field matching the logged-in user
  - `timestamp` field
  - `temperature`, `humidity`, `motionDetected`, `fanSpeed`, `ledBrightness` fields

### Step 6: Test Function Directly

1. **From Firebase Console**:
   - Go to Functions → `predictSchedule`
   - Click "Test" tab
   - Enter test data:
     ```json
     {
       "userId": "YOUR_USER_ID",
       "deviceId": "all"
     }
     ```
   - Click "Test Function"
   - Check the response and logs

2. **From Terminal** (requires auth token):
   ```bash
   # Get your ID token from the app logs or Firebase Console
   # Then call the function:
   curl -X POST \
     https://us-central1-YOUR_PROJECT_ID.cloudfunctions.net/predictSchedule \
     -H "Authorization: Bearer YOUR_ID_TOKEN" \
     -H "Content-Type: application/json" \
     -d '{"userId": "YOUR_USER_ID", "deviceId": "all"}'
   ```

### Step 7: Check Function Code

Verify the function is exported correctly:

1. **Check `backend/functions/src/index.ts`**:
   ```typescript
   export { predictSchedule, detectAnomalies } from './ml/mlInference';
   ```

2. **Check `backend/functions/lib/index.js`** (compiled):
   - Should have `exports.predictSchedule = ...`

3. **Rebuild if needed**:
   ```bash
   cd backend/functions
   npm run build
   ```

### Step 8: Redeploy Function

If everything looks correct but still not working:

```bash
cd backend
firebase deploy --only functions:predictSchedule
```

Wait for deployment to complete, then try again.

### Step 9: Check Function Logs for Errors

The function might be deployed but failing at runtime:

1. **View logs in Firebase Console**:
   - Functions → `predictSchedule` → Logs
   - Look for errors like:
     - Model loading failures
     - Data validation errors
     - TensorFlow.js errors
     - Memory issues

2. **Common Runtime Errors**:
   - **"Model not found"**: ML models not uploaded to Storage
   - **"Insufficient data"**: Need at least 24 hours of data
   - **"Memory limit exceeded"**: Function needs more memory (increase in function config)
   - **"Timeout"**: Function taking too long (increase timeout)

### Step 10: Verify Data Format

Ensure your sensor logs have the correct format:

```javascript
{
  userId: "user_id",
  deviceId: "device_id",
  timestamp: Timestamp,
  temperature: number,
  humidity: number,
  motionDetected: boolean,
  fanSpeed: number (0-255),
  ledBrightness: number (0-255),
  distance: number
}
```

### Quick Diagnostic Commands

```bash
# 1. List all functions
firebase functions:list

# 2. Check function details
firebase functions:describe predictSchedule

# 3. View recent logs
firebase functions:log --only predictSchedule --limit 20

# 4. Test function locally (if emulator is set up)
firebase emulators:start --only functions
```

### Still Not Working?

1. **Check Firebase Project**:
   - Ensure app is connected to the same Firebase project
   - Check `firebase_options.dart` has correct project ID

2. **Check Network**:
   - Ensure device has internet connection
   - Check if firewall/proxy is blocking Firebase

3. **Check Billing**:
   - Cloud Functions require Blaze plan
   - Verify project is on Blaze plan (not Spark)

4. **Contact Support**:
   - Share function logs from Firebase Console
   - Share app logs showing the error
   - Include function deployment output

## Expected Behavior

When working correctly:
- Function should respond within 30-60 seconds (first call may be slower due to cold start)
- Function logs should show: "🔮 Schedule prediction started"
- Function should return predictions in format:
  ```json
  {
    "success": true,
    "schedules": [
      {
        "hour": 8,
        "minute": 0,
        "deviceType": "fan",
        "value": 50,
        "confidence": 0.85
      }
    ]
  }
  ```

