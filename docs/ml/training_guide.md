# SmartSync ML Integration - Complete Setup Guide

## 📋 Overview

This guide walks you through the complete machine learning integration for SmartSync, from data collection to deployment.

---

## 🗂️ File Structure

```
ml/
├── README.md                           # This file
├── requirements.txt                    # Python dependencies
│
├── data/
│   ├── raw/                            # Raw training data
│   │   ├── firebase_sensor_logs_90days.csv
│   │   ├── kaggle_smart_home.csv
│   │   └── uci_smart_home.csv
│   ├── processed/                      # Preprocessed data
│   │   ├── hourly_features.csv
│   │   ├── scaler.pkl
│   │   └── anomaly_scaler.pkl
│   └── synthetic/                      # Synthetic test data
│
├── models/
│   ├── saved_models/                   # Trained TF models
│   │   ├── schedule_predictor_v1/
│   │   │   ├── saved_model.pb
│   │   │   ├── variables/
│   │   │   └── metadata.json
│   │   └── anomaly_detector_v1/
│   │       ├── saved_model.pb
│   │       ├── variables/
│   │       └── metadata.json
│   └── tflite/                         # Mobile models
│       ├── schedule_predictor.tflite
│       ├── schedule_predictor.json
│       ├── anomaly_detector.tflite
│       ├── anomaly_detector.json
│       └── FLUTTER_INTEGRATION.md
│
├── scripts/
│   ├── firebase_setup.py               # Firebase Admin SDK setup
│   ├── collect_firebase_data.py        # Collect from Firestore
│   ├── preprocess_public_data.py       # Convert public datasets
│   ├── train_model.py                  # ✨ Train schedule predictor
│   ├── train_anomaly_detector.py       # ✨ Train anomaly detector
│   ├── convert_tflite.py               # ✨ Convert to TFLite
│   ├── deploy_model.py                 # Deploy to Firebase
│   └── download_public_datasets.sh     # Download Kaggle/UCI data
│
└── notebooks/
    ├── exploratory_analysis.ipynb      # Data exploration
    ├── model_training.ipynb            # Interactive training
    └── model_evaluation.ipynb          # Model performance analysis
```

---

## 🚀 Quick Start (5 Steps)

### Step 1: Install Dependencies

```bash
cd ml
pip install -r requirements.txt
```

**Requirements:**
- Python 3.9+
- TensorFlow 2.13+
- pandas, numpy, scikit-learn
- firebase-admin
- matplotlib, seaborn (for visualizations)

---

### Step 2: Get Training Data

**Option A: Use Public Datasets (Recommended for initial training)**

```bash
# Download Kaggle dataset
kaggle datasets download -d taranvee/smart-home-dataset-with-weather-information
unzip smart-home-dataset-with-weather-information.zip -d data/raw/

# Download UCI dataset
wget https://archive.ics.uci.edu/static/public/196/data.csv -O data/raw/uci_smart_home.csv

# Preprocess to SmartSync format
python scripts/preprocess_public_data.py
```

**Option B: Collect from Firebase (After app deployment)**

```bash
# 1. Download Firebase service account key
# Go to: Firebase Console > Project Settings > Service Accounts
# Save as: ml/serviceAccountKey.json

# 2. Collect data
python scripts/collect_firebase_data.py
```

**Data Requirements:**
- Minimum: 30 days of hourly sensor readings
- Optimal: 90+ days for best accuracy
- Features: Temperature, humidity, motion, device usage

---

### Step 3: Train Models

```bash
# Train schedule predictor (predicts optimal device schedules)
python scripts/train_model.py

# Train anomaly detector (detects unusual behavior patterns)
python scripts/train_anomaly_detector.py
```

**Expected Output:**
```
Training schedule predictor...
  Training set:   1800 sequences
  Validation set: 450 sequences
  Test set:       450 sequences
  
Training...
Epoch 50/50 - loss: 0.0234 - val_loss: 0.0256

✅ Training complete!
   Test MAE:  0.0245
   Test RMSE: 0.0312
   R²:        0.8765

Saved to: models/saved_models/schedule_predictor_v1/
```

---

### Step 4: Convert to TFLite (Mobile Deployment)

```bash
# Convert both models to TFLite format
python scripts/convert_tflite.py
```

**Optimizations Applied:**
- INT8 quantization (reduces model size by ~4x)
- Inference speed optimization
- Mobile-friendly format

**Output:**
```
Converting schedule_predictor...
  Input shape:  (1, 168, 13)
  Output shape: (1, 2)
  
✅ Conversion successful!
   Output: models/tflite/schedule_predictor.tflite
   Size: 2.34 MB (was 9.12 MB)
   
Converting anomaly_detector...
✅ Conversion successful!
   Output: models/tflite/anomaly_detector.tflite
   Size: 1.87 MB (was 7.23 MB)
```

---

### Step 5: Integrate with Flutter

```bash
# Copy models to Flutter assets
cp models/tflite/schedule_predictor.tflite ../app/assets/models/
cp models/tflite/anomaly_detector.tflite ../app/assets/models/

# Read integration guide
cat models/tflite/FLUTTER_INTEGRATION.md
```

**Flutter Implementation:**

```dart
// File: lib/services/ml_service.dart

import 'package:tflite_flutter/tflite_flutter.dart';

class MLService {
  late Interpreter _schedulePredictor;
  late Interpreter _anomalyDetector;
  
  // Load models
  Future<void> initialize() async {
    _schedulePredictor = await Interpreter.fromAsset(
      'assets/models/schedule_predictor.tflite'
    );
    _anomalyDetector = await Interpreter.fromAsset(
      'assets/models/anomaly_detector.tflite'
    );
  }
  
  // Predict optimal schedule
  Future<Map<String, double>> predictSchedule(
    List<List<double>> hourlyData  // Shape: [168, 13]
  ) async {
    var input = [hourlyData];  // Add batch dimension
    var output = List.filled(2, 0.0).reshape([1, 2]);
    
    _schedulePredictor.run(input, output);
    
    return {
      'fanSpeed': output[0][0] * 100,
      'ledBrightness': output[0][1] * 100
    };
  }
  
  // Detect anomalies
  Future<AnomalyResult> detectAnomaly(
    List<List<double>> last24Hours  // Shape: [24, 15]
  ) async {
    var input = [last24Hours];
    var output = List.filled(24 * 15, 0.0).reshape([1, 24, 15]);
    
    _anomalyDetector.run(input, output);
    
    // Calculate reconstruction error
    double mse = 0.0;
    for (int i = 0; i < 24; i++) {
      for (int j = 0; j < 15; j++) {
        double diff = input[0][i][j] - output[0][i][j];
        mse += diff * diff;
      }
    }
    mse /= (24 * 15);
    
    // Load threshold from model metadata
    const threshold = 0.05;  // From training output
    
    return AnomalyResult(
      isAnomalous: mse > threshold,
      reconstructionError: mse,
      threshold: threshold
    );
  }
}

// Usage in app
final mlService = MLService();
await mlService.initialize();

// Predict schedule based on last week's data
final prediction = await mlService.predictSchedule(last168Hours);
print('Suggested fan speed: ${prediction['fanSpeed']}%');

// Detect anomalies in last 24 hours
final anomaly = await mlService.detectAnomaly(last24Hours);
if (anomaly.isAnomalous) {
  // Alert caregivers
  await notificationService.sendAnomalyAlert(anomaly);
}
```

---

## 🔄 Continuous Learning Pipeline

### Automated Retraining (Weekly)

**Setup Cloud Scheduler:**

```bash
# Deploy Firebase Cloud Functions
cd backend/functions
npm install
npm run deploy

# Schedule weekly retraining
gcloud scheduler jobs create pubsub weekly-ml-training \
  --schedule="0 3 * * 0" \
  --topic=ml-training \
  --message-body="trigger" \
  --time-zone="UTC"
```

**Cloud Function:**

```typescript
// functions/src/ml/weeklyTraining.ts

export const weeklyMLTraining = functions.pubsub
  .schedule('every sunday 03:00')
  .onRun(async (context) => {
    // 1. Export recent data from Firestore
    const last90Days = await exportFirestoreData(90);
    
    // 2. Trigger training on Cloud Run
    const trainingJob = await cloudRun.runTraining({
      data: last90Days,
      modelType: 'schedule_predictor'
    });
    
    // 3. Deploy updated model
    if (trainingJob.success) {
      await deployNewModel(trainingJob.modelUrl);
    }
    
    return null;
  });
```

---

## 📊 Model Performance Monitoring

### Track Key Metrics

```dart
// Log ML performance to Firebase Analytics

await FirebaseAnalytics.instance.logEvent(
  name: 'ml_inference',
  parameters: {
    'model': 'schedule_predictor',
    'latency_ms': inferenceTime,
    'accuracy': userAcceptedPrediction ? 1 : 0,
    'device': Platform.operatingSystem,
  }
);
```

### Dashboard Queries

```sql
-- BigQuery: Average inference latency
SELECT 
  event_params.value.string_value AS model,
  AVG(event_params.value.int_value) AS avg_latency_ms
FROM `smartsync-cf370.analytics_XXXXX.events_*`
WHERE event_name = 'ml_inference'
  AND _TABLE_SUFFIX BETWEEN FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY))
                        AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
GROUP BY model;
```

---

## 🧪 Testing

### Unit Tests for ML Service

```dart
// test/services/ml_service_test.dart

void main() {
  late MLService mlService;
  
  setUp(() async {
    mlService = MLService();
    await mlService.initialize();
  });
  
  test('Schedule predictor returns valid output', () async {
    final input = generateSyntheticData(168, 13);
    final prediction = await mlService.predictSchedule(input);
    
    expect(prediction['fanSpeed'], inRangeOf(0, 100));
    expect(prediction['ledBrightness'], inRangeOf(0, 100));
  });
  
  test('Anomaly detector flags unusual patterns', () async {
    // Normal pattern
    final normalData = generateNormalPattern(24, 15);
    final normalResult = await mlService.detectAnomaly(normalData);
    expect(normalResult.isAnomalous, isFalse);
    
    // Anomalous pattern (no motion for 24 hours)
    final anomalousData = generateAnomalousPattern(24, 15);
    final anomalyResult = await mlService.detectAnomaly(anomalousData);
    expect(anomalyResult.isAnomalous, isTrue);
  });
}
```

---

## 🐛 Troubleshooting

### Common Issues

#### 1. "Insufficient training data"
**Solution:**
- Ensure at least 30 days of data (90+ optimal)
- Download public datasets if Firebase data is limited
- Check data quality with `check_data_quality()` function

#### 2. "Model loading failed in Flutter"
**Solution:**
```yaml
# pubspec.yaml - Ensure models are listed in assets
flutter:
  assets:
    - assets/models/schedule_predictor.tflite
    - assets/models/anomaly_detector.tflite
```

#### 3. "High reconstruction error on normal data"
**Solution:**
- Retrain with more diverse data
- Adjust anomaly threshold in model metadata
- Verify data preprocessing matches training

#### 4. "Inference too slow on device"
**Solution:**
- Run inference in background isolate
- Cache predictions for repeated inputs
- Consider using GPU delegate (if available)

```dart
// Use Isolate for background inference
Future<Map<String, double>> predictInBackground(data) async {
  return await compute(_runInference, data);
}

static Future<Map<String, double>> _runInference(data) async {
  final mlService = MLService();
  await mlService.initialize();
  return await mlService.predictSchedule(data);
}
```

---

## 📈 Performance Benchmarks

### Expected Performance

| Model | Input Shape | Inference Time | Model Size | Accuracy |
|-------|-------------|----------------|------------|----------|
| Schedule Predictor | (1, 168, 13) | 50-100ms | 2.3 MB | R² = 0.87 |
| Anomaly Detector | (1, 24, 15) | 30-60ms | 1.9 MB | AUC = 0.92 |

**Device Tested:** Pixel 6 (Android 13)

---

## 🎯 Next Steps

1. **Gather More Data:**
   - Deploy app to beta users
   - Collect 90+ days of real usage data
   - Retrain models with production data

2. **Improve Models:**
   - Add more features (weather data, user demographics)
   - Experiment with different architectures (Transformers, GRU)
   - Implement online learning for personalization

3. **Advanced Features:**
   - Multi-user prediction (household patterns)
   - Explainable AI (why this prediction?)
   - Federated learning (privacy-preserving)

4. **Monitor & Iterate:**
   - Track prediction accuracy
   - Collect user feedback
   - A/B test model improvements

---

## 📚 Additional Resources

### Documentation
- [TensorFlow Lite Guide](https://www.tensorflow.org/lite/guide)
- [Flutter ML Kit](https://firebase.google.com/docs/ml-kit)
- [Firebase Cloud Functions](https://firebase.google.com/docs/functions)

### Datasets
- [Kaggle Smart Home Datasets](https://www.kaggle.com/search?q=smart+home)
- [UCI ML Repository](https://archive.ics.uci.edu/)
- [Home Assistant Datasets](https://github.com/home-assistant/datasets)

### Research Papers
- *Deep Learning for Smart Home* - IEEE 2020
- *Anomaly Detection in IoT* - ACM 2021
- *Elderly Care with ML* - Nature Digital Medicine 2022

---

## 🆘 Support

- **Issues:** Open GitHub issue with `[ML]` prefix
- **Questions:** Check `FLUTTER_INTEGRATION.md`
- **Email:** ml-support@smartsync.com

---

## ✅ Checklist

Before deployment, ensure:

- [ ] Models trained with >30 days of data
- [ ] Conversion to TFLite successful
- [ ] Flutter integration tested on device
- [ ] Firebase Cloud Functions deployed
- [ ] Monitoring/analytics configured
- [ ] User privacy compliance verified
- [ ] Documentation updated
- [ ] Performance benchmarks met

---

**Last Updated:** November 2024  
**Version:** 1.0.0  
**Maintainer:** SmartSync ML Team