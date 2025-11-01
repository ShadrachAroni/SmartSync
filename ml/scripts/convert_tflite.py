#!/usr/bin/env python3
"""
SmartSync TFLite Conversion Script

Convert trained TensorFlow models to TensorFlow Lite format
for mobile deployment in Flutter app.

Optimizations applied:
- Quantization (INT8) for reduced model size
- Optimization for inference speed
- Metadata embedding for easy integration
"""

import tensorflow as tf
import numpy as np
import json
from pathlib import Path
import shutil

# ==================== CONFIGURATION ====================
PROJECT_ROOT = Path(__file__).parent.parent
MODELS_DIR = PROJECT_ROOT / "models" / "saved_models"
TFLITE_DIR = PROJECT_ROOT / "models" / "tflite"
PROCESSED_DATA_DIR = PROJECT_ROOT / "data" / "processed"

# Ensure output directory exists
TFLITE_DIR.mkdir(parents=True, exist_ok=True)

print("=" * 70)
print("SmartSync TFLite Conversion Pipeline")
print("=" * 70)

# ==================== CONVERSION FUNCTIONS ====================
def convert_schedule_predictor():
    """
    Convert schedule predictor model to TFLite
    
    Model: LSTM-based sequence prediction
    Input: (1, 168, 13) - 1 week of hourly data, 13 features
    Output: (1, 2) - Fan speed and LED brightness predictions
    """
    print("\n" + "="*70)
    print("CONVERTING: Schedule Predictor")
    print("="*70)
    
    model_path = MODELS_DIR / "schedule_predictor_v1"
    
    if not model_path.exists():
        print(f"\n❌ Error: Model not found at {model_path}")
        print("   Please run scripts/train_model.py first")
        return False
    
    print(f"\n📥 Loading model from {model_path}...")
    model = tf.keras.models.load_model(model_path)
    
    print("\n📊 Model Information:")
    print(f"   Input shape:  {model.input_shape}")
    print(f"   Output shape: {model.output_shape}")
    model.summary()
    
    # Create converter
    print("\n🔧 Creating TFLite converter...")
    converter = tf.lite.TFLiteConverter.from_keras_model(model)
    
    # Apply optimizations
    print("   Applying optimizations:")
    print("   • Default optimization")
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
    
    # Representative dataset for quantization
    print("   • INT8 quantization with representative dataset")
    
    def representative_dataset():
        """Generate representative data for quantization"""
        # Load sample data
        import pandas as pd
        import joblib
        
        data_path = PROCESSED_DATA_DIR / 'hourly_features.csv'
        if data_path.exists():
            df = pd.read_csv(data_path)
            scaler = joblib.load(PROCESSED_DATA_DIR / 'scaler.pkl')
            
            feature_cols = [
                'temperature_mean', 'temperature_max', 'temperature_min',
                'humidity_mean', 'motionDetected_sum', 'distance_mean',
                'hour_sin', 'hour_cos', 'day_sin', 'day_cos',
                'is_weekend', 'is_night', 'manual_actions'
            ]
            
            features = df[feature_cols].values[:200]  # Use first 200 records
            features_normalized = scaler.transform(features)
            
            # Create sequences
            for i in range(len(features_normalized) - 168):
                sample = features_normalized[i:i+168]
                yield [np.array([sample], dtype=np.float32)]
        else:
            # Generate synthetic data if real data unavailable
            for _ in range(100):
                yield [np.random.randn(1, 168, 13).astype(np.float32)]
    
    converter.representative_dataset = representative_dataset
    converter.target_spec.supported_ops = [tf.lite.OpsSet.TFLITE_BUILTINS_INT8]
    converter.inference_input_type = tf.float32  # Keep float32 inputs
    converter.inference_output_type = tf.float32  # Keep float32 outputs
    
    # Convert
    print("\n⚙️  Converting model...")
    try:
        tflite_model = converter.convert()
        
        # Save
        output_path = TFLITE_DIR / "schedule_predictor.tflite"
        with open(output_path, 'wb') as f:
            f.write(tflite_model)
        
        # Get model size
        model_size = len(tflite_model) / 1024 / 1024  # MB
        
        print(f"\n✅ Conversion successful!")
        print(f"   Output: {output_path}")
        print(f"   Size: {model_size:.2f} MB")
        
        # Verify model
        verify_tflite_model(output_path)
        
        # Create metadata
        save_model_metadata(output_path, model, model_size, 'schedule_predictor')
        
        return True
        
    except Exception as e:
        print(f"\n❌ Conversion failed: {e}")
        return False

def convert_anomaly_detector():
    """
    Convert anomaly detector model to TFLite
    
    Model: LSTM Autoencoder
    Input: (1, 24, 14) - 24 hours of data, 14 features
    Output: (1, 24, 14) - Reconstructed sequence
    """
    print("\n" + "="*70)
    print("CONVERTING: Anomaly Detector")
    print("="*70)
    
    model_path = MODELS_DIR / "anomaly_detector_v1"
    
    if not model_path.exists():
        print(f"\n❌ Error: Model not found at {model_path}")
        print("   Please run scripts/train_anomaly_detector.py first")
        return False
    
    print(f"\n📥 Loading model from {model_path}...")
    model = tf.keras.models.load_model(model_path)
    
    print("\n📊 Model Information:")
    print(f"   Input shape:  {model.input_shape}")
    print(f"   Output shape: {model.output_shape}")
    
    # Create converter
    print("\n🔧 Creating TFLite converter...")
    converter = tf.lite.TFLiteConverter.from_keras_model(model)
    
    # Apply optimizations
    print("   Applying optimizations:")
    print("   • Default optimization")
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
    
    # Representative dataset
    print("   • INT8 quantization")
    
    def representative_dataset():
        """Generate representative data for anomaly detector"""
        import pandas as pd
        import joblib
        
        data_path = PROCESSED_DATA_DIR / 'hourly_features.csv'
        if data_path.exists():
            df = pd.read_csv(data_path)
            scaler = joblib.load(PROCESSED_DATA_DIR / 'anomaly_scaler.pkl')
            
            feature_cols = [
                'temperature_mean', 'humidity_mean',
                'motion_24h_sum', 'motion_24h_mean', 'motion_24h_std',
                'temp_deviation', 'temp_24h_range',
                'active_nighttime', 'hours_since_motion',
                'fan_running', 'led_running',
                'hour_sin', 'hour_cos', 'day_sin', 'day_cos'
            ]
            
            # Fill NaN and normalize
            df = df.fillna(method='bfill').fillna(method='ffill')
            features = df[feature_cols].values[:200]
            features_normalized = scaler.transform(features)
            
            for i in range(len(features_normalized) - 24):
                sample = features_normalized[i:i+24]
                yield [np.array([sample], dtype=np.float32)]
        else:
            for _ in range(100):
                yield [np.random.randn(1, 24, 15).astype(np.float32)]
    
    converter.representative_dataset = representative_dataset
    converter.target_spec.supported_ops = [tf.lite.OpsSet.TFLITE_BUILTINS_INT8]
    converter.inference_input_type = tf.float32
    converter.inference_output_type = tf.float32
    
    # Convert
    print("\n⚙️  Converting model...")
    try:
        tflite_model = converter.convert()
        
        # Save
        output_path = TFLITE_DIR / "anomaly_detector.tflite"
        with open(output_path, 'wb') as f:
            f.write(tflite_model)
        
        model_size = len(tflite_model) / 1024 / 1024
        
        print(f"\n✅ Conversion successful!")
        print(f"   Output: {output_path}")
        print(f"   Size: {model_size:.2f} MB")
        
        # Verify
        verify_tflite_model(output_path)
        
        # Metadata
        save_model_metadata(output_path, model, model_size, 'anomaly_detector')
        
        return True
        
    except Exception as e:
        print(f"\n❌ Conversion failed: {e}")
        return False

# ==================== VERIFICATION ====================
def verify_tflite_model(tflite_path):
    """Verify TFLite model can be loaded and run inference"""
    print("\n🔍 Verifying TFLite model...")
    
    try:
        # Load TFLite model
        interpreter = tf.lite.Interpreter(model_path=str(tflite_path))
        interpreter.allocate_tensors()
        
        # Get input/output details
        input_details = interpreter.get_input_details()
        output_details = interpreter.get_output_details()
        
        print("   ✅ Model loaded successfully")
        print(f"   Input details:  {input_details[0]['shape']} ({input_details[0]['dtype']})")
        print(f"   Output details: {output_details[0]['shape']} ({output_details[0]['dtype']})")
        
        # Test inference with random data
        input_shape = input_details[0]['shape']
        test_input = np.random.randn(*input_shape).astype(np.float32)
        
        interpreter.set_tensor(input_details[0]['index'], test_input)
        interpreter.invoke()
        output = interpreter.get_tensor(output_details[0]['index'])
        
        print(f"   ✅ Test inference successful")
        print(f"   Output shape: {output.shape}")
        
        return True
        
    except Exception as e:
        print(f"   ❌ Verification failed: {e}")
        return False

# ==================== METADATA ====================
def save_model_metadata(tflite_path, keras_model, model_size_mb, model_name):
    """Save model metadata for Flutter integration"""
    print("\n📝 Saving metadata...")
    
    # Load existing metadata from training
    metadata_path = MODELS_DIR / f"{model_name}_v1" / "metadata.json"
    
    if metadata_path.exists():
        with open(metadata_path, 'r') as f:
            metadata = json.load(f)
    else:
        metadata = {}
    
    # Add TFLite-specific information
    metadata.update({
        'tflite_model_path': str(tflite_path.relative_to(PROJECT_ROOT)),
        'tflite_model_size_mb': float(model_size_mb),
        'input_shape': list(keras_model.input_shape),
        'output_shape': list(keras_model.output_shape),
        'quantized': True,
        'quantization_type': 'INT8',
        'conversion_date': tf.timestamp().numpy().item(),
        'tensorflow_version': tf.__version__
    })
    
    # Save updated metadata
    tflite_metadata_path = tflite_path.with_suffix('.json')
    with open(tflite_metadata_path, 'w') as f:
        json.dump(metadata, f, indent=2)
    
    print(f"   Saved metadata to {tflite_metadata_path}")

# ==================== FLUTTER INTEGRATION GUIDE ====================
def generate_flutter_integration_guide():
    """Generate integration instructions for Flutter developers"""
    print("\n📚 Generating Flutter integration guide...")
    
    guide = """
# TFLite Model Integration Guide for Flutter

## 1. Copy Models to Flutter Assets

```bash
# From project root
cp ml/models/tflite/schedule_predictor.tflite app/assets/models/
cp ml/models/tflite/anomaly_detector.tflite app/assets/models/
```

## 2. Update pubspec.yaml

Ensure models are listed in assets:

```yaml
flutter:
  assets:
    - assets/models/schedule_predictor.tflite
    - assets/models/anomaly_detector.tflite
```

## 3. Flutter ML Service Implementation

File: `lib/services/ml_service.dart`

```dart
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:tflite_flutter_helper/tflite_flutter_helper.dart';

class MLService {
  Interpreter? _schedulePredictor;
  Interpreter? _anomalyDetector;
  
  Future<void> loadModels() async {
    _schedulePredictor = await Interpreter.fromAsset(
      'assets/models/schedule_predictor.tflite'
    );
    
    _anomalyDetector = await Interpreter.fromAsset(
      'assets/models/anomaly_detector.tflite'
    );
  }
  
  // Predict next hour's device usage
  Future<Map<String, double>> predictSchedule(List<List<double>> input) async {
    // Input shape: [1, 168, 13]
    var output = List.filled(1 * 2, 0.0).reshape([1, 2]);
    
    _schedulePredictor!.run(input, output);
    
    return {
      'fanSpeed': output[0][0] * 100,  // Convert to percentage
      'ledBrightness': output[0][1] * 100
    };
  }
  
  // Detect anomalies in 24-hour window
  Future<bool> detectAnomaly(List<List<double>> input) async {
    // Input shape: [1, 24, 15]
    var output = List.filled(1 * 24 * 15, 0.0).reshape([1, 24, 15]);
    
    _anomalyDetector!.run(input, output);
    
    // Calculate reconstruction error
    double mse = 0.0;
    for (int i = 0; i < 24; i++) {
      for (int j = 0; j < 15; j++) {
        double diff = input[0][i][j] - output[0][i][j];
        mse += diff * diff;
      }
    }
    mse /= (24 * 15);
    
    // Load threshold from metadata.json
    const threshold = 0.05;  // Update with actual threshold
    
    return mse > threshold;
  }
}
```

## 4. Usage Example

```dart
// Initialize
final mlService = MLService();
await mlService.loadModels();

// Predict schedule
final prediction = await mlService.predictSchedule(last168Hours);
print('Predicted fan speed: \${prediction['fanSpeed']}%');

// Detect anomaly
final isAnomalous = await mlService.detectAnomaly(last24Hours);
if (isAnomalous) {
  // Send alert to caregivers
  alertService.sendEmergencyNotification();
}
```

## 5. Data Preparation for Inference

```dart
List<List<double>> prepareScheduleInput(List<SensorData> sensorLogs) {
  // Convert last 168 hours of sensor data to model input format
  // Normalize using same scaler parameters from training
  
  List<List<double>> normalized = [];
  
  for (var log in sensorLogs) {
    normalized.add([
      normalizeTemperature(log.temperature),
      normalizeHumidity(log.humidity),
      // ... all 13 features
    ]);
  }
  
  return [normalized];  // Add batch dimension
}
```

## 6. Performance Optimization

- Run inference in background isolate to avoid UI blocking
- Cache model outputs for frequently accessed predictions
- Batch multiple predictions when possible
- Monitor inference latency and memory usage

## 7. Testing

Write unit tests for ML service:

```dart
test('Schedule predictor returns valid output', () async {
  final service = MLService();
  await service.loadModels();
  
  final input = generateSyntheticInput(168, 13);
  final prediction = await service.predictSchedule(input);
  
  expect(prediction['fanSpeed'], inRangeOf(0, 100));
  expect(prediction['ledBrightness'], inRangeOf(0, 100));
});
```

## 8. Monitoring

Track ML model performance in production:

```dart
await FirebaseAnalytics.instance.logEvent(
  name: 'ml_prediction',
  parameters: {
    'model': 'schedule_predictor',
    'latency_ms': predictionTime,
    'input_size': inputData.length,
  },
);
```
"""
    
    guide_path = TFLITE_DIR / "FLUTTER_INTEGRATION.md"
    with open(guide_path, 'w') as f:
        f.write(guide.strip())
    
    print(f"   Saved guide to {guide_path}")

# ==================== MAIN ====================
def main():
    """Main conversion pipeline"""
    
    print("\n🎯 Starting TFLite conversion for all models...")
    
    results = {
        'schedule_predictor': False,
        'anomaly_detector': False
    }
    
    # Convert schedule predictor
    results['schedule_predictor'] = convert_schedule_predictor()
    
    # Convert anomaly detector
    results['anomaly_detector'] = convert_anomaly_detector()
    
    # Generate integration guide
    generate_flutter_integration_guide()
    
    # Summary
    print("\n" + "="*70)
    print("CONVERSION SUMMARY")
    print("="*70)
    
    for model_name, success in results.items():
        status = "✅ SUCCESS" if success else "❌ FAILED"
        print(f"   {model_name}: {status}")
    
    if all(results.values()):
        print("\n🎉 All models converted successfully!")
        print("\nNext steps:")
        print("1. Copy .tflite files to app/assets/models/")
        print("2. Implement MLService in Flutter (see FLUTTER_INTEGRATION.md)")
        print("3. Test inference on device")
        print("4. Deploy to Firebase Storage: python scripts/deploy_model.py")
    else:
        print("\n⚠️  Some conversions failed. Check error messages above.")

if __name__ == "__main__":
    main()