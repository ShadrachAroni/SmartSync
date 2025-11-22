# SmartSync ML Models

Machine learning models and training pipeline for SmartSync IoT Home Automation System.

## 📋 Overview

This directory contains:
- **Training scripts** for schedule prediction and anomaly detection models
- **TFLite conversion** tools for on-device inference
- **Model deployment** scripts for Firebase Storage
- **Data processing** utilities for Kaggle datasets

## 🤖 ML Models

### 1. Schedule Predictor
- **Purpose**: Predict optimal device schedules based on historical usage patterns
- **Architecture**: LSTM-based neural network
- **Input Features**: 
  - Historical sensor data (temperature, humidity, motion)
  - Time features (hour, day of week, cyclical encoding)
  - Device usage patterns
- **Output**: Predicted fan speed and LED brightness schedules with confidence scores
- **Deployment**: 
  - Local: TFLite model in Flutter app (`app/assets/models/`)
  - Cloud: Firebase Storage for Cloud Functions

### 2. Anomaly Detector
- **Purpose**: Detect unusual activity patterns that may indicate health issues
- **Architecture**: Autoencoder
- **Input**: Activity patterns, sensor readings, usage statistics
- **Output**: Anomaly score (0-1) with alert generation
- **Deployment**: Firebase Cloud Functions

## 📊 Data Sources

### Training Data
- **Kaggle Datasets**: 
  - `HomeC.csv` - Home energy consumption data
  - `aruba.csv` - Smart home sensor data
  - `tulum.csv` - Environmental sensor readings
- **Location**: `ml/data/raw/`
- **Format**: CSV files with timestamp, temperature, humidity, motion, and device states

### Production Data (Future)
- **Firestore Collections**: 
  - `sensor_logs` - Real-time sensor readings
  - `activity_logs` - User actions and device changes
- **Collection Script**: `scripts/collect_firebase_data.py`

## 🚀 Quick Start

### Prerequisites
```bash
# Python 3.9+
python --version

# Install dependencies
cd ml
pip install -r requirements.txt
```

### Training Workflow

#### Step 1: Train Model
```bash
python scripts/train_smart_home.py
```

**What it does:**
- Loads Kaggle datasets (HomeC.csv, aruba.csv, tulum.csv)
- Converts to SmartSync format
- Creates hourly features with cyclical encoding
- Trains LSTM model
- Evaluates performance
- Saves model + scaler + metadata

**Output:**
- `models/saved_models/schedule_predictor_v1/` (Keras model)
- `data/processed/scaler.pkl`
- Training plots and metrics

#### Step 2: Convert to TFLite
```bash
python scripts/convert_tflite.py
```

**What it does:**
- Converts Keras model to TensorFlow Lite
- Applies INT8 quantization for size optimization
- Verifies model inference
- **Automatically copies to Flutter assets** (`app/assets/models/`)

**Output:**
- `models/tflite/schedule_predictor.tflite`
- `app/assets/models/schedule_predictor.tflite` (auto-copied)

#### Step 3: Deploy to Firebase
```bash
python scripts/deploy_model.py
```

**Requirements:**
- `serviceAccountKey.json` in `ml/` directory
- Firebase project configured

**What it does:**
- Uploads TFLite model to Firebase Storage
- Updates Firestore with model metadata
- Makes model accessible to Cloud Functions

## 📁 Directory Structure

```
ml/
├── data/
│   ├── raw/              # Kaggle datasets (CSV files)
│   └── processed/        # Processed data and scalers
├── models/
│   ├── saved_models/     # Keras models
│   └── tflite/           # TFLite models
├── scripts/
│   ├── train_smart_home.py      # Main training script
│   ├── convert_tflite.py       # TFLite conversion
│   ├── deploy_model.py          # Firebase deployment
│   ├── firebase_setup.py        # Firebase Admin SDK setup
│   └── collect_firebase_data.py # Production data collection
├── requirements.txt      # Python dependencies
└── README.md            # This file
```

## 🔧 Configuration

### Model Parameters
Edit `scripts/train_smart_home.py` to adjust:
- LSTM units (default: 64)
- Training epochs (default: 50)
- Batch size (default: 32)
- Learning rate (default: 0.001)

### Feature Engineering
- **Cyclical Encoding**: Hour and day of week encoded using sin/cos
- **Time Windows**: 7-day lookback for predictions
- **Normalization**: StandardScaler for feature normalization

## 📈 Model Performance

### Schedule Predictor
- **Training Accuracy**: ~85% on test data
- **Inference Time**: <50ms (TFLite on mobile)
- **Model Size**: ~500KB (quantized)

### Anomaly Detector
- **Detection Rate**: 90% for critical anomalies
- **False Positive Rate**: <5%
- **Processing Time**: <100ms per prediction

## 🔄 Retraining Workflow

### With Production Data

1. **Collect Data** (after app has been running):
```bash
python scripts/firebase_setup.py
python scripts/collect_firebase_data.py
```

2. **Retrain**:
```bash
# Modify train_smart_home.py to include Firebase data
python scripts/train_smart_home.py
```

3. **Redeploy**:
```bash
python scripts/convert_tflite.py
python scripts/deploy_model.py
```

## 🧪 Testing

### Test Model Inference
```python
import tensorflow as tf
import numpy as np

# Load TFLite model
interpreter = tf.lite.Interpreter(model_path="models/tflite/schedule_predictor.tflite")
interpreter.allocate_tensors()

# Test input
input_data = np.random.rand(1, 168, 10).astype(np.float32)  # 7 days, 10 features

# Run inference
interpreter.set_tensor(interpreter.get_input_details()[0]['index'], input_data)
interpreter.invoke()
output = interpreter.get_tensor(interpreter.get_output_details()[0]['index'])

print(f"Prediction: {output}")
```

## 🔒 Security

- **Never commit** `serviceAccountKey.json` to Git
- **Anonymize** user data when collecting for training
- **GDPR compliance**: Get user consent for data usage

## 📚 Dependencies

Key packages:
- `tensorflow>=2.15.0` - ML framework
- `pandas` - Data processing
- `numpy` - Numerical operations
- `scikit-learn` - Feature scaling
- `firebase-admin` - Firebase integration (for deployment)

See `requirements.txt` for complete list.

## 🐛 Troubleshooting

### Model Training Fails
- Check dataset files exist in `data/raw/`
- Verify Python version (3.9+)
- Ensure TensorFlow is installed correctly

### TFLite Conversion Fails
- Verify Keras model exists
- Check TensorFlow version compatibility
- Review conversion logs

### Firebase Deployment Fails
- Verify `serviceAccountKey.json` exists
- Check Firebase project ID matches
- Ensure Cloud Storage is enabled

## 📖 Additional Resources

- [TensorFlow Lite Guide](https://www.tensorflow.org/lite)
- [LSTM Networks](https://www.tensorflow.org/guide/keras/rnn)
- [Firebase Storage](https://firebase.google.com/docs/storage)

## 🤝 Contributing

When adding new models:
1. Create training script in `scripts/`
2. Add conversion script for TFLite
3. Update deployment script
4. Document model architecture and performance

---

**Built for SmartSync IoT Home Automation System**
