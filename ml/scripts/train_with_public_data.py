#!/usr/bin/env python3
"""
Train SmartSync ML Models Using Public Datasets
No Firebase data required - uses Kaggle/UCI datasets

Run this script: python scripts/train_with_public_data.py
"""

import numpy as np
import pandas as pd
import tensorflow as tf
from tensorflow import keras
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import StandardScaler
import json
from datetime import datetime, timedelta
from pathlib import Path
import matplotlib.pyplot as plt
import seaborn as sns
import joblib

# ==================== CONFIGURATION ====================
PROJECT_ROOT = Path(__file__).parent.parent
DATA_DIR = PROJECT_ROOT / "data"
RAW_DATA_DIR = DATA_DIR / "raw"
PROCESSED_DATA_DIR = DATA_DIR / "processed"
MODELS_DIR = PROJECT_ROOT / "models" / "saved_models"

# Create directories
for dir_path in [RAW_DATA_DIR, PROCESSED_DATA_DIR, MODELS_DIR]:
    dir_path.mkdir(parents=True, exist_ok=True)

SEQUENCE_LENGTH = 168  # 1 week
BATCH_SIZE = 32
EPOCHS = 50

print("=" * 80)
print("SmartSync ML Training - Using Public Datasets")
print("=" * 80)

# ==================== LOAD PUBLIC DATASETS ====================
def load_smart_home_dataset():
    """Load and process public smart home datasets"""
    print("\n📥 Loading public smart home datasets...")
    
    # Try different dataset files
    possible_files = [
        RAW_DATA_DIR / "HomeC.csv",
        RAW_DATA_DIR / "smart_home_dataset.csv",
        RAW_DATA_DIR / "occupancy_data.csv",
        RAW_DATA_DIR / "aruba.csv",
    ]
    
    df = None
    for file_path in possible_files:
        if file_path.exists():
            print(f"   Found: {file_path.name}")
            df = pd.read_csv(file_path)
            break
    
    if df is None:
        print("\n❌ No dataset found!")
        print("   Please download datasets first:")
        print("   1. Go to: https://www.kaggle.com/datasets/taranvee/smart-home-dataset-with-weather-information")
        print("   2. Download and extract to ml/data/raw/")
        return None
    
    print(f"   Loaded {len(df)} records")
    print(f"   Columns: {list(df.columns)}")
    
    return df

def convert_to_smartsync_format(df):
    """Convert public dataset to SmartSync format"""
    print("\n🔄 Converting to SmartSync format...")
    
    # Detect dataset type and convert
    if 'Temperature' in df.columns:
        # Kaggle format
        smartsync_df = pd.DataFrame({
            'timestamp': pd.to_datetime(df['date'] if 'date' in df.columns else df['Time']),
            'temperature': df['Temperature'],
            'humidity': df['Humidity'],
            'motionDetected': df['Occupancy'] if 'Occupancy' in df.columns else 0,
            'fanSpeed': ((df['Temperature'] > 24).astype(int) * 200),  # Auto fan
            'ledBrightness': ((df['Light'] > 100).astype(int) * 255) if 'Light' in df.columns else 0,
            'distance': 150  # Default
        })
    else:
        # Generate synthetic data based on patterns
        print("   Generating synthetic training data...")
        days = 90
        hours = days * 24
        
        timestamps = pd.date_range(
            end=datetime.now(),
            periods=hours,
            freq='H'
        )
        
        data = []
        for ts in timestamps:
            hour = ts.hour
            day = ts.dayofweek
            
            # Realistic patterns
            base_temp = 22
            temp = base_temp + 3 * np.sin(2 * np.pi * hour / 24) + np.random.normal(0, 1)
            humidity = 55 + 10 * np.sin(2 * np.pi * hour / 24) + np.random.normal(0, 3)
            
            # Motion: active during day (6am-11pm)
            motion = 1 if (6 <= hour <= 23) and np.random.random() > 0.3 else 0
            
            # Fan: on when temp > 24°C
            fan = int((temp - 20) / 15 * 255) if temp > 24 else 0
            fan = max(0, min(255, fan))
            
            # LED: on during evening (6pm-11pm)
            led = 255 if 18 <= hour <= 23 else 0
            
            data.append({
                'timestamp': ts,
                'temperature': temp,
                'humidity': humidity,
                'fanSpeed': fan,
                'ledBrightness': led,
                'motionDetected': motion,
                'distance': np.random.uniform(50, 300)
            })
        
        smartsync_df = pd.DataFrame(data)
    
    print(f"   Converted {len(smartsync_df)} records")
    return smartsync_df

# ==================== PREPROCESSING ====================
class DataPreprocessor:
    def __init__(self):
        self.scaler = StandardScaler()
    
    def create_hourly_features(self, df):
        """Create hourly aggregated features"""
        print("\n🔧 Creating hourly features...")
        
        df['hour'] = pd.to_datetime(df['timestamp']).dt.floor('H')
        
        hourly = df.groupby('hour').agg({
            'temperature': ['mean', 'max', 'min'],
            'humidity': 'mean',
            'motionDetected': 'sum',
            'distance': 'mean',
            'fanSpeed': lambda x: (x > 0).sum(),
            'ledBrightness': lambda x: (x > 0).sum()
        }).reset_index()
        
        hourly.columns = ['_'.join(col).strip('_') for col in hourly.columns]
        hourly.rename(columns={'hour_': 'hour'}, inplace=True)
        
        return hourly
    
    def add_temporal_features(self, df):
        """Add time-based features"""
        print("   Adding temporal features...")
        
        df['hour_of_day'] = df['hour'].dt.hour
        df['day_of_week'] = df['hour'].dt.dayofweek
        df['is_weekend'] = (df['day_of_week'] >= 5).astype(int)
        df['is_night'] = ((df['hour_of_day'] >= 22) | (df['hour_of_day'] <= 6)).astype(int)
        
        # Cyclical encoding
        df['hour_sin'] = np.sin(2 * np.pi * df['hour_of_day'] / 24)
        df['hour_cos'] = np.cos(2 * np.pi * df['hour_of_day'] / 24)
        df['day_sin'] = np.sin(2 * np.pi * df['day_of_week'] / 7)
        df['day_cos'] = np.cos(2 * np.pi * df['day_of_week'] / 7)
        
        return df
    
    def create_sequences(self, df, sequence_length=168):
        """Create LSTM sequences"""
        print(f"\n📦 Creating sequences (length={sequence_length})...")
        
        feature_cols = [
            'temperature_mean', 'temperature_max', 'temperature_min',
            'humidity_mean', 'motionDetected_sum', 'distance_mean',
            'hour_sin', 'hour_cos', 'day_sin', 'day_cos',
            'is_weekend', 'is_night'
        ]
        
        # Add manual_actions column (set to 0 for public data)
        df['manual_actions'] = 0
        feature_cols.append('manual_actions')
        
        target_cols = ['fanSpeed_<lambda>', 'ledBrightness_<lambda>']
        
        # Normalize
        features = df[feature_cols].values
        features_normalized = self.scaler.fit_transform(features)
        targets = df[target_cols].values / 255.0  # Normalize to 0-1
        
        # Create sequences
        X, y = [], []
        for i in range(len(df) - sequence_length):
            X.append(features_normalized[i:i+sequence_length])
            y.append(targets[i+sequence_length])
        
        X = np.array(X)
        y = np.array(y)
        
        print(f"   Created {len(X)} sequences")
        print(f"   Input shape: {X.shape}")
        print(f"   Output shape: {y.shape}")
        
        return X, y

# ==================== MODEL ====================
def build_model(input_shape):
    """Build LSTM model"""
    print("\n🏗️  Building LSTM model...")
    
    model = keras.Sequential([
        keras.layers.Input(shape=input_shape),
        keras.layers.LSTM(128, return_sequences=True),
        keras.layers.Dropout(0.3),
        keras.layers.LSTM(64, return_sequences=False),
        keras.layers.Dropout(0.2),
        keras.layers.Dense(32, activation='relu'),
        keras.layers.Dropout(0.2),
        keras.layers.Dense(2, activation='sigmoid')  # Fan & LED predictions
    ])
    
    model.compile(
        optimizer=keras.optimizers.Adam(0.001),
        loss='mse',
        metrics=['mae']
    )
    
    model.summary()
    return model

# ==================== TRAINING ====================
def train_model(X_train, y_train, X_val, y_val):
    """Train the model"""
    print("\n🚀 Training model...")
    
    model = build_model((X_train.shape[1], X_train.shape[2]))
    
    callbacks = [
        keras.callbacks.EarlyStopping(
            monitor='val_loss',
            patience=10,
            restore_best_weights=True
        ),
        keras.callbacks.ReduceLROnPlateau(
            monitor='val_loss',
            factor=0.5,
            patience=5,
            min_lr=1e-6
        )
    ]
    
    history = model.fit(
        X_train, y_train,
        batch_size=BATCH_SIZE,
        epochs=EPOCHS,
        validation_data=(X_val, y_val),
        callbacks=callbacks,
        verbose=1
    )
    
    # Plot training history
    plt.figure(figsize=(12, 4))
    
    plt.subplot(1, 2, 1)
    plt.plot(history.history['loss'], label='Training Loss')
    plt.plot(history.history['val_loss'], label='Validation Loss')
    plt.xlabel('Epoch')
    plt.ylabel('Loss')
    plt.legend()
    plt.title('Training History')
    plt.grid(True, alpha=0.3)
    
    plt.subplot(1, 2, 2)
    plt.plot(history.history['mae'], label='Training MAE')
    plt.plot(history.history['val_mae'], label='Validation MAE')
    plt.xlabel('Epoch')
    plt.ylabel('MAE')
    plt.legend()
    plt.title('Mean Absolute Error')
    plt.grid(True, alpha=0.3)
    
    plt.tight_layout()
    plt.savefig(MODELS_DIR / 'training_history.png', dpi=300)
    print(f"\n   Saved training plot to {MODELS_DIR / 'training_history.png'}")
    
    return model, history

# ==================== EVALUATION ====================
def evaluate_model(model, X_test, y_test):
    """Evaluate model"""
    print("\n📈 Evaluating model...")
    
    y_pred = model.predict(X_test)
    
    from sklearn.metrics import mean_absolute_error, mean_squared_error, r2_score
    
    mae = mean_absolute_error(y_test, y_pred)
    rmse = np.sqrt(mean_squared_error(y_test, y_pred))
    r2 = r2_score(y_test, y_pred)
    
    print(f"\n✅ Test Results:")
    print(f"   MAE:  {mae:.4f}")
    print(f"   RMSE: {rmse:.4f}")
    print(f"   R²:   {r2:.4f}")
    
    # Visualize predictions
    plt.figure(figsize=(12, 5))
    
    plt.subplot(1, 2, 1)
    plt.scatter(y_test[:, 0], y_pred[:, 0], alpha=0.5)
    plt.plot([0, 1], [0, 1], 'r--', label='Perfect Prediction')
    plt.xlabel('Actual Fan Speed')
    plt.ylabel('Predicted Fan Speed')
    plt.title('Fan Speed Predictions')
    plt.legend()
    plt.grid(True, alpha=0.3)
    
    plt.subplot(1, 2, 2)
    plt.scatter(y_test[:, 1], y_pred[:, 1], alpha=0.5)
    plt.plot([0, 1], [0, 1], 'r--', label='Perfect Prediction')
    plt.xlabel('Actual LED Brightness')
    plt.ylabel('Predicted LED Brightness')
    plt.title('LED Brightness Predictions')
    plt.legend()
    plt.grid(True, alpha=0.3)
    
    plt.tight_layout()
    plt.savefig(MODELS_DIR / 'predictions.png', dpi=300)
    print(f"   Saved predictions plot to {MODELS_DIR / 'predictions.png'}")
    
    return {'mae': float(mae), 'rmse': float(rmse), 'r2': float(r2)}

# ==================== SAVE MODEL ====================
def save_model(model, preprocessor, metrics):
    """Save trained model"""
    print("\n💾 Saving model...")
    
    # Save Keras model
    model_path = MODELS_DIR / 'schedule_predictor_v1'
    model.save(model_path)
    print(f"   ✅ Saved model to {model_path}")
    
    # Save scaler
    scaler_path = PROCESSED_DATA_DIR / 'scaler.pkl'
    joblib.dump(preprocessor.scaler, scaler_path)
    print(f"   ✅ Saved scaler to {scaler_path}")
    
    # Save metadata
    metadata = {
        'model_version': '1.0.0',
        'trained_date': datetime.now().isoformat(),
        'sequence_length': SEQUENCE_LENGTH,
        'metrics': metrics,
        'framework': 'TensorFlow',
        'framework_version': tf.__version__,
        'training_source': 'Public Datasets (Kaggle)'
    }
    
    metadata_path = model_path / 'metadata.json'
    with open(metadata_path, 'w') as f:
        json.dump(metadata, f, indent=2)
    print(f"   ✅ Saved metadata to {metadata_path}")

# ==================== MAIN ====================
def main():
    """Main training pipeline"""
    
    # Load data
    print("\n" + "="*80)
    print("STEP 1: DATA LOADING")
    print("="*80)
    
    raw_df = load_smart_home_dataset()
    if raw_df is None:
        return
    
    smartsync_df = convert_to_smartsync_format(raw_df)
    
    # Save raw data
    smartsync_df.to_csv(RAW_DATA_DIR / 'smartsync_format.csv', index=False)
    
    # Preprocess
    print("\n" + "="*80)
    print("STEP 2: PREPROCESSING")
    print("="*80)
    
    preprocessor = DataPreprocessor()
    hourly_df = preprocessor.create_hourly_features(smartsync_df)
    hourly_df = preprocessor.add_temporal_features(hourly_df)
    
    # Save processed data
    hourly_df.to_csv(PROCESSED_DATA_DIR / 'hourly_features.csv', index=False)
    
    # Create sequences
    X, y = preprocessor.create_sequences(hourly_df, SEQUENCE_LENGTH)
    
    # Split data
    print("\n📊 Splitting data...")
    X_train, X_temp, y_train, y_temp = train_test_split(X, y, test_size=0.3, random_state=42)
    X_val, X_test, y_val, y_test = train_test_split(X_temp, y_temp, test_size=0.5, random_state=42)
    
    print(f"   Training:   {len(X_train)} samples")
    print(f"   Validation: {len(X_val)} samples")
    print(f"   Test:       {len(X_test)} samples")
    
    # Train
    print("\n" + "="*80)
    print("STEP 3: TRAINING")
    print("="*80)
    
    model, history = train_model(X_train, y_train, X_val, y_val)
    
    # Evaluate
    print("\n" + "="*80)
    print("STEP 4: EVALUATION")
    print("="*80)
    
    metrics = evaluate_model(model, X_test, y_test)
    
    # Save
    print("\n" + "="*80)
    print("STEP 5: SAVING")
    print("="*80)
    
    save_model(model, preprocessor, metrics)
    
    print("\n" + "="*80)
    print("✅ TRAINING COMPLETE!")
    print("="*80)
    print(f"\nModel Performance:")
    print(f"  • MAE:  {metrics['mae']:.4f}")
    print(f"  • RMSE: {metrics['rmse']:.4f}")
    print(f"  • R²:   {metrics['r2']:.4f}")
    print(f"\nNext Steps:")
    print(f"  1. Convert to TFLite: python scripts/convert_tflite.py")
    print(f"  2. Copy to Flutter: cp models/tflite/*.tflite ../app/assets/models/")

if __name__ == "__main__":
    main()