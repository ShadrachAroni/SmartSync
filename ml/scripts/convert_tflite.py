#!/usr/bin/env python3
"""
SmartSync TFLite Conversion Script
File: ml/scripts/convert_tflite.py

Convert trained Keras models to TensorFlow Lite format for Flutter deployment.

Features:
- INT8 quantization for reduced model size
- Automatic verification of converted models
- Auto-copy to Flutter assets folder
- Metadata generation for easy integration

Usage:
    cd ml
    python scripts/convert_tflite.py
"""

import tensorflow as tf
import numpy as np
import pandas as pd
import json
from pathlib import Path
import shutil
import joblib
import warnings
warnings.filterwarnings('ignore')

# ==================== CONFIGURATION ====================
PROJECT_ROOT = Path(__file__).parent.parent
MODELS_DIR = PROJECT_ROOT / "models" / "saved_models"
TFLITE_DIR = PROJECT_ROOT / "models" / "tflite"
PROCESSED_DATA_DIR = PROJECT_ROOT / "data" / "processed"
APP_ASSETS_DIR = PROJECT_ROOT.parent / "app" / "assets" / "models"

# Ensure directories exist
TFLITE_DIR.mkdir(parents=True, exist_ok=True)
APP_ASSETS_DIR.mkdir(parents=True, exist_ok=True)

print("=" * 80)
print("SmartSync TFLite Conversion Pipeline")
print("=" * 80)

# ==================== HELPER FUNCTIONS ====================
def load_scaler(scaler_path):
    """Load StandardScaler used during training"""
    if scaler_path.exists():
        return joblib.load(scaler_path)
    else:
        print(f"   ⚠️  Scaler not found at {scaler_path}")
        return None

def generate_representative_dataset(sequence_length=168, num_features=13):
    """
    Generate representative dataset for INT8 quantization
    
    Uses actual training data if available, otherwise generates synthetic data.
    This helps the quantizer understand the range of input values.
    
    Args:
        sequence_length: Number of timesteps (default 168 = 1 week)
        num_features: Number of input features (default 13)
    
    Yields:
        Batches of input data for quantization calibration
    """
    data_path = PROCESSED_DATA_DIR / 'hourly_features.csv'
    scaler_path = PROCESSED_DATA_DIR / 'scaler.pkl'
    
    if data_path.exists() and scaler_path.exists():
        print("   📊 Using real training data for quantization")
        
        # Load data
        df = pd.read_csv(data_path)
        scaler = load_scaler(scaler_path)
        
        feature_cols = [
            'temperature_mean', 'temperature_max', 'temperature_min',
            'humidity_mean', 'motionDetected_sum', 'distance_mean',
            'hour_sin', 'hour_cos', 'day_sin', 'day_cos',
            'is_weekend', 'is_night', 'manual_actions'
        ]
        
        # Get features and normalize
        features = df[feature_cols].values[:200]  # Use first 200 records
        features_normalized = scaler.transform(features)
        
        # Create sequences
        for i in range(len(features_normalized) - sequence_length):
            sample = features_normalized[i:i+sequence_length]
            yield [np.array([sample], dtype=np.float32)]
    
    else:
        print("   🧪 Using synthetic data for quantization")
        
        # Generate synthetic data
        for _ in range(100):
            # Random data with realistic ranges
            sample = np.random.randn(1, sequence_length, num_features).astype(np.float32)
            yield [sample]

# ==================== MODEL CONVERSION ====================
def convert_schedule_predictor():
    """
    Convert schedule predictor model to TFLite
    
    Model details:
    - Input:  (1, 168, 13) - 1 week of hourly data, 13 features
    - Output: (1, 2) - Fan speed and LED brightness predictions (0-1 range)
    
    Returns:
        bool: True if conversion successful, False otherwise
    """
    print("\n" + "="*80)
    print("CONVERTING: Schedule Predictor")
    print("="*80)
    
    model_path = MODELS_DIR / "schedule_predictor_v1"
    
    # Check if model exists
    if not model_path.exists():
        print(f"\n❌ ERROR: Model not found at {model_path}")
        print("   Please run train_smart_home.py first")
        return False
    
    # Load Keras model
    print(f"\n📥 Loading Keras model from {model_path.name}...")
    try:
        model = tf.keras.models.load_model(model_path)
    except Exception as e:
        print(f"   ❌ Failed to load model: {e}")
        return False
    
    print(f"   ✅ Model loaded successfully")
    print(f"   Input shape:  {model.input_shape}")
    print(f"   Output shape: {model.output_shape}")
    
    # Display model architecture
    print("\n📊 Model Architecture:")
    model.summary()
    
    # Create TFLite converter
    print("\n🔧 Creating TFLite converter...")
    converter = tf.lite.TFLiteConverter.from_keras_model(model)
    
    # Apply optimizations
    print("   Applying optimizations:")
    print("   • Default optimization (speed + size)")
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
    
    print("   • INT8 quantization (with representative dataset)")
    converter.representative_dataset = lambda: generate_representative_dataset(168, 13)
    converter.target_spec.supported_ops = [tf.lite.OpsSet.TFLITE_BUILTINS_INT8]
    
    # Keep input/output as float32 for easier Flutter integration
    converter.inference_input_type = tf.float32
    converter.inference_output_type = tf.float32
    
    # Convert
    print("\n⚙️  Converting to TFLite...")
    try:
        tflite_model = converter.convert()
    except Exception as e:
        print(f"   ❌ Conversion failed: {e}")
        return False
    
    # Save TFLite model
    output_path = TFLITE_DIR / "schedule_predictor.tflite"
    with open(output_path, 'wb') as f:
        f.write(tflite_model)
    
    model_size_mb = len(tflite_model) / 1024 / 1024
    
    print(f"\n✅ Conversion successful!")
    print(f"   Output file: {output_path}")
    print(f"   Model size:  {model_size_mb:.2f} MB")
    
    # Verify the converted model
    if not verify_tflite_model(output_path):
        return False
    
    # Save metadata
    save_model_metadata(output_path, model, model_size_mb, 'schedule_predictor')
    
    return True

def convert_anomaly_detector():
    """
    Convert anomaly detector model to TFLite
    
    Model details:
    - Input:  (1, 24, 15) - 24 hours of data, 15 features
    - Output: (1, 24, 15) - Reconstructed sequence
    
    Note: This model may not exist yet. The conversion is optional.
    
    Returns:
        bool: True if conversion successful, False otherwise
    """
    print("\n" + "="*80)
    print("CONVERTING: Anomaly Detector")
    print("="*80)
    
    model_path = MODELS_DIR / "anomaly_detector_v1"
    
    # Check if model exists
    if not model_path.exists():
        print(f"\n⚠️  Model not found at {model_path}")
        print("   Skipping anomaly detector conversion")
        print("   (Run train_anomaly_detector.py if you need this model)")
        return False
    
    # Load Keras model
    print(f"\n📥 Loading Keras model from {model_path.name}...")
    try:
        model = tf.keras.models.load_model(model_path)
    except Exception as e:
        print(f"   ❌ Failed to load model: {e}")
        return False
    
    print(f"   ✅ Model loaded successfully")
    print(f"   Input shape:  {model.input_shape}")
    print(f"   Output shape: {model.output_shape}")
    
    # Create TFLite converter
    print("\n🔧 Creating TFLite converter...")
    converter = tf.lite.TFLiteConverter.from_keras_model(model)
    
    # Apply optimizations
    print("   Applying optimizations:")
    print("   • Default optimization")
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
    
    print("   • INT8 quantization")
    
    # Representative dataset for anomaly detector
    def anomaly_representative_dataset():
        data_path = PROCESSED_DATA_DIR / 'hourly_features.csv'
        scaler_path = PROCESSED_DATA_DIR / 'anomaly_scaler.pkl'
        
        if data_path.exists() and scaler_path.exists():
            df = pd.read_csv(data_path)
            scaler = load_scaler(scaler_path)
            
            # Anomaly detector features (15 features)
            feature_cols = [
                'temperature_mean', 'humidity_mean',
                'motion_24h_sum', 'motion_24h_mean', 'motion_24h_std',
                'temp_deviation', 'temp_24h_range',
                'active_nighttime', 'hours_since_motion',
                'fan_running', 'led_running',
                'hour_sin', 'hour_cos', 'day_sin', 'day_cos'
            ]
            
            # Handle missing columns
            available_cols = [col for col in feature_cols if col in df.columns]
            if len(available_cols) < len(feature_cols):
                print(f"   ⚠️  Only {len(available_cols)}/{len(feature_cols)} features available")
                # Use synthetic data instead
                for _ in range(100):
                    yield [np.random.randn(1, 24, 15).astype(np.float32)]
                return
            
            # Fill NaN and normalize
            df = df.fillna(method='bfill').fillna(method='ffill')
            features = df[available_cols].values[:200]
            features_normalized = scaler.transform(features)
            
            # Create 24-hour sequences
            for i in range(len(features_normalized) - 24):
                sample = features_normalized[i:i+24]
                yield [np.array([sample], dtype=np.float32)]
        else:
            # Generate synthetic data
            for _ in range(100):
                yield [np.random.randn(1, 24, 15).astype(np.float32)]
    
    converter.representative_dataset = anomaly_representative_dataset
    converter.target_spec.supported_ops = [tf.lite.OpsSet.TFLITE_BUILTINS_INT8]
    converter.inference_input_type = tf.float32
    converter.inference_output_type = tf.float32
    
    # Convert
    print("\n⚙️  Converting to TFLite...")
    try:
        tflite_model = converter.convert()
    except Exception as e:
        print(f"   ❌ Conversion failed: {e}")
        return False
    
    # Save TFLite model
    output_path = TFLITE_DIR / "anomaly_detector.tflite"
    with open(output_path, 'wb') as f:
        f.write(tflite_model)
    
    model_size_mb = len(tflite_model) / 1024 / 1024
    
    print(f"\n✅ Conversion successful!")
    print(f"   Output file: {output_path}")
    print(f"   Model size:  {model_size_mb:.2f} MB")
    
    # Verify the converted model
    if not verify_tflite_model(output_path):
        return False
    
    # Save metadata
    save_model_metadata(output_path, model, model_size_mb, 'anomaly_detector')
    
    return True

# ==================== VERIFICATION ====================
def verify_tflite_model(tflite_path):
    """
    Verify TFLite model can be loaded and run inference
    
    Args:
        tflite_path: Path to .tflite file
    
    Returns:
        bool: True if verification successful
    """
    print("\n🔍 Verifying TFLite model...")
    
    try:
        # Load TFLite interpreter
        interpreter = tf.lite.Interpreter(model_path=str(tflite_path))
        interpreter.allocate_tensors()
        
        # Get input/output details
        input_details = interpreter.get_input_details()
        output_details = interpreter.get_output_details()
        
        print("   ✅ Model loaded successfully")
        print(f"   Input:  shape={input_details[0]['shape']}, dtype={input_details[0]['dtype']}")
        print(f"   Output: shape={output_details[0]['shape']}, dtype={output_details[0]['dtype']}")
        
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
    """
    Save metadata JSON for Flutter integration
    
    Args:
        tflite_path: Path to .tflite file
        keras_model: Original Keras model
        model_size_mb: Size of TFLite model in MB
        model_name: Name of the model
    """
    print("\n📝 Saving metadata...")
    
    # Load existing metadata from training (if available)
    training_metadata_path = MODELS_DIR / f"{model_name}_v1" / "metadata.json"
    
    if training_metadata_path.exists():
        with open(training_metadata_path, 'r') as f:
            metadata = json.load(f)
    else:
        metadata = {}
    
    # Add TFLite-specific information
    metadata.update({
        'model_name': model_name,
        'model_version': '1.0.0',
        'tflite_model_path': str(tflite_path.relative_to(PROJECT_ROOT)),
        'tflite_model_size_mb': float(model_size_mb),
        'input_shape': list(keras_model.input_shape),
        'output_shape': list(keras_model.output_shape),
        'quantized': True,
        'quantization_type': 'INT8',
        'conversion_date': str(tf.timestamp().numpy()),
        'tensorflow_version': tf.__version__,
        'framework': 'TensorFlow Lite',
        'inference_type': 'float32',
    })
    
    # Save metadata next to .tflite file
    metadata_path = tflite_path.with_suffix('.json')
    with open(metadata_path, 'w') as f:
        json.dump(metadata, f, indent=2)
    
    print(f"   ✅ Saved metadata to {metadata_path.name}")

# ==================== AUTO-COPY TO FLUTTER ====================
def copy_to_flutter_assets():
    """
    Automatically copy TFLite models to Flutter assets folder
    
    This replaces the manual command:
    cp ml/models/tflite/*.tflite app/assets/models/
    
    Returns:
        bool: True if at least one file was copied successfully
    """
    print("\n" + "="*80)
    print("AUTO-COPY TO FLUTTER ASSETS")
    print("="*80)
    
    print(f"\n📲 Copying models to Flutter app...")
    print(f"   Source: {TFLITE_DIR}")
    print(f"   Destination: {APP_ASSETS_DIR}")
    
    # Find all .tflite files
    tflite_files = list(TFLITE_DIR.glob('*.tflite'))
    
    if not tflite_files:
        print("\n   ⚠️  No .tflite files found to copy")
        return False
    
    # Copy each file
    copied_count = 0
    for tflite_file in tflite_files:
        dest_path = APP_ASSETS_DIR / tflite_file.name
        
        try:
            shutil.copy2(tflite_file, dest_path)
            size_mb = tflite_file.stat().st_size / 1024 / 1024
            print(f"   ✅ {tflite_file.name} → {dest_path.relative_to(PROJECT_ROOT.parent)} ({size_mb:.2f} MB)")
            copied_count += 1
        except Exception as e:
            print(f"   ❌ Failed to copy {tflite_file.name}: {e}")
    
    # Copy metadata files too
    json_files = list(TFLITE_DIR.glob('*.json'))
    for json_file in json_files:
        if json_file.name != 'FLUTTER_INTEGRATION.md':
            dest_path = APP_ASSETS_DIR / json_file.name
            try:
                shutil.copy2(json_file, dest_path)
                print(f"   ✅ {json_file.name} → {dest_path.relative_to(PROJECT_ROOT.parent)}")
            except Exception as e:
                print(f"   ⚠️  Failed to copy {json_file.name}: {e}")
    
    if copied_count > 0:
        print(f"\n   ✅ Successfully copied {copied_count} model(s) to Flutter assets!")
        return True
    else:
        print(f"\n   ❌ No models were copied")
        return False

# ==================== FLUTTER INTEGRATION GUIDE ====================
def generate_flutter_guide():
    """Generate quick-start guide for Flutter integration"""
    print("\n📚 Generating Flutter integration guide...")
    
    guide = """# SmartSync ML - Flutter Integration Guide

## ✅ Models Copied to Assets

The TFLite models have been automatically copied to `app/assets/models/`

## 1. Verify pubspec.yaml

Ensure your `pubspec.yaml` includes:

```yaml
flutter:
  assets:
    - assets/models/schedule_predictor.tflite
    - assets/models/schedule_predictor.json  # Metadata
```

## 2. Install Dependencies

```bash
cd app
flutter pub add tflite_flutter
flutter pub add tflite_flutter_helper
flutter pub get
```

## 3. MLService is Already Implemented

Check `app/lib/services/ml_service.dart` - it's already integrated!

## 4. Usage in Your App

```dart
// In your screen or provider
final mlService = ref.read(mlServiceProvider);
await mlService.initialize();

// Get predictions for schedule suggestions
final predictions = await mlService.predictSchedules(userId, deviceId);

// Check for anomalies
final report = await mlService.detectAnomalies(userId, Duration(hours: 24));
```

## 5. Test on Device

```bash
flutter run
```

The ML service will automatically load models on first use.

## 6. Next Steps

- ✅ Models converted and copied
- ⏭️  Deploy to Firebase: `python scripts/deploy_model.py`
- ⏭️  Set up Cloud Functions for server-side inference
- ⏭️  Test predictions in Analytics screen

## Troubleshooting

**Model not loading?**
- Check file paths in `pubspec.yaml`
- Run `flutter clean && flutter pub get`
- Verify files exist in `app/assets/models/`

**Poor predictions?**
- Model needs more training data
- Check scaler normalization in preprocessing
- Verify input feature order matches training

---

Generated by SmartSync ML Pipeline
"""
    
    guide_path = TFLITE_DIR / "FLUTTER_GUIDE.md"
    with open(guide_path, 'w') as f:
        f.write(guide.strip())
    
    print(f"   ✅ Saved guide to {guide_path.name}")

# ==================== MAIN PIPELINE ====================
def main():
    """Main conversion pipeline"""
    
    print("\n🎯 Starting TFLite conversion pipeline...\n")
    
    conversion_results = {}
    
    # Convert schedule predictor (required)
    conversion_results['schedule_predictor'] = convert_schedule_predictor()
    
    # Convert anomaly detector (optional)
    conversion_results['anomaly_detector'] = convert_anomaly_detector()
    
    # Auto-copy to Flutter assets
    copy_success = copy_to_flutter_assets()
    
    # Generate integration guide
    generate_flutter_guide()
    
    # Final summary
    print("\n" + "="*80)
    print("CONVERSION SUMMARY")
    print("="*80)
    
    print("\n📊 Model Conversion Results:")
    for model_name, success in conversion_results.items():
        status = "✅ SUCCESS" if success else "❌ FAILED"
        print(f"   {model_name:20s}: {status}")
    
    print(f"\n📲 Flutter Assets Copy:")
    print(f"   {'Auto-copy':20s}: {'✅ SUCCESS' if copy_success else '❌ FAILED'}")
    
    # Next steps
    print("\n" + "="*80)
    print("NEXT STEPS")
    print("="*80)
    
    if conversion_results.get('schedule_predictor') and copy_success:
        print("\n✅ Models ready for Flutter app!")
        print("\n1. ✅ Models converted to TFLite")
        print("2. ✅ Models copied to app/assets/models/")
        print("3. ⏭️  Run your Flutter app: flutter run")
        print("4. ⏭️  Deploy to Firebase: python scripts/deploy_model.py")
        print("\n📖 See FLUTTER_GUIDE.md for integration details")
    else:
        print("\n⚠️  Some conversions failed")
        print("\nTroubleshooting:")
        print("- Ensure train_smart_home.py completed successfully")
        print("- Check that schedule_predictor_v1 model exists")
        print("- Verify scaler.pkl is in data/processed/")

if __name__ == "__main__":
    main()