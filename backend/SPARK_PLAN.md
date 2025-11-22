# SmartSync on Firebase Spark Plan (Free)

## Overview

SmartSync is designed to work on **Firebase Spark Plan (Free)** using **local TFLite models** for ML inference. Cloud Functions are **optional** and only used as a fallback.

## What Works on Spark Plan

✅ **Fully Supported:**
- Firestore Database (with free tier limits)
- Firebase Authentication
- Cloud Storage (with free tier limits)
- Firestore Security Rules
- Storage Security Rules
- **Local TFLite ML Inference** (primary method)

❌ **Not Available:**
- Cloud Functions (requires Blaze plan)
- Server-side ML inference via Cloud Functions

## Architecture

```
Spark Plan Architecture:
┌─────────────────┐
│  Flutter App    │
│                 │
│  ┌───────────┐  │
│  │ TFLite    │  │ ← PRIMARY: Local ML inference
│  │ Service   │  │
│  └───────────┘  │
│                 │
│  ┌───────────┐  │
│  │ Firestore │  │ ← Data storage
│  │ Client    │  │
│  └───────────┘  │
└─────────────────┘
        │
        ▼
┌─────────────────┐
│  Firebase       │
│  (Spark Plan)   │
│                 │
│  • Firestore    │
│  • Auth         │
│  • Storage      │
└─────────────────┘
```

## Setup for Spark Plan

### 1. Ensure TFLite Models are Available

```bash
# From project root
cd app/assets/models

# Verify these files exist:
# - schedule_predictor.tflite
# - anomaly_detector.tflite (optional)
```

### 2. Deploy Firestore & Storage Rules

```bash
cd backend

# These work on Spark plan
firebase deploy --only firestore:rules
firebase deploy --only storage:rules
```

### 3. Configure Flutter App

The Flutter app is already configured to:
1. **Primary**: Use local TFLite models for ML inference
2. **Fallback**: Attempt Cloud Functions (will gracefully fail on Spark plan)

No additional configuration needed!

## ML Inference Flow

### On Spark Plan:

1. **User requests schedule prediction**
2. **App loads local TFLite model** from `assets/models/`
3. **Runs inference locally** on device
4. **Returns predictions** immediately
5. **No server calls needed**

### If Upgrading to Blaze Plan:

1. **User requests schedule prediction**
2. **App tries local TFLite first** (still primary)
3. **If local fails**, falls back to Cloud Function
4. **Cloud Function** runs server-side inference
5. **Returns predictions**

## Benefits of Spark Plan Setup

✅ **No billing required** - completely free  
✅ **Fast inference** - runs locally on device  
✅ **Works offline** - no internet needed for ML  
✅ **Privacy** - data never leaves device for ML  
✅ **No cold starts** - instant predictions  

## Limitations

⚠️ **Model updates** require app update (can't update server-side)  
⚠️ **No scheduled functions** (anomaly detection, cleanup, etc.)  
⚠️ **No server-side analytics** aggregation  

## Migration to Blaze Plan

If you want to enable Cloud Functions later:

1. **Upgrade to Blaze Plan**:
   - Firebase Console → Project Settings → Usage and Billing
   - Click "Upgrade to Blaze Plan"
   - Add billing account (won't be charged unless you exceed free tier)

2. **Deploy Cloud Functions**:
   ```bash
   cd backend
   firebase deploy --only functions
   ```

3. **Deploy ML Models to Storage**:
   ```bash
   cd ml
   python scripts/deploy_model.py
   ```

4. **App automatically uses both**:
   - Local TFLite (primary)
   - Cloud Functions (fallback)

## Free Tier Limits (Spark Plan)

- **Firestore**: 1 GB storage, 50K reads/day, 20K writes/day
- **Storage**: 5 GB storage, 1 GB downloads/day
- **Authentication**: Unlimited
- **Cloud Functions**: ❌ Not available

## Troubleshooting

### Issue: "Cloud Function not found" warning

**This is normal on Spark Plan!** The app gracefully handles this and uses local models instead.

### Issue: Local TFLite models not loading

1. Check `app/assets/models/` contains `.tflite` files
2. Verify `pubspec.yaml` includes assets:
   ```yaml
   flutter:
     assets:
       - assets/models/
   ```
3. Run `flutter pub get` and rebuild app

### Issue: Predictions not working

1. Ensure you have at least 24 hours of sensor data in Firestore
2. Check app logs for TFLite initialization errors
3. Verify TFLite models are valid (not corrupted)

## Summary

**SmartSync works perfectly on Spark Plan** using local TFLite models. Cloud Functions are optional enhancements that require Blaze plan, but are not required for core functionality.

The app is designed with **local-first** architecture, so ML inference works great even without server-side functions!

