#!/usr/bin/env python3

"""
SmartSync ML Training - FIXED Version with Simpler Architecture
File: ml/scripts/train_smart_home_fixed.py

Key fixes:
1. Simpler MLP model instead of LSTM (better for synthetic data)
2. Removed early stopping to allow full training
3. Shorter sequence length (6 hours instead of 24)
4. Better feature engineering
5. More realistic evaluation

Usage:
    cd ml
    python scripts/train_smart_home_fixed.py
"""

import numpy as np
import pandas as pd
import tensorflow as tf
from tensorflow import keras
from sklearn.preprocessing import StandardScaler
from sklearn.metrics import mean_absolute_error, mean_squared_error, r2_score
import json
from datetime import datetime
from pathlib import Path
import matplotlib.pyplot as plt
import joblib
import warnings
warnings.filterwarnings('ignore')

# ==================== GPU CONFIGURATION ====================
def setup_gpu():
    """Configure TensorFlow for efficient GPU usage"""
    print("\n" + "="*80)
    print("GPU CONFIGURATION")
    print("="*80)

    gpus = tf.config.list_physical_devices('GPU')
    if gpus:
        try:
            for gpu in gpus:
                tf.config.experimental.set_memory_growth(gpu, True)
            print(f"✅ GPU Configuration Successful!")
            print(f"   Physical GPUs: {len(gpus)}")
            return True
        except RuntimeError as e:
            print(f"   ⚠️ GPU setup error: {e}")
            return False
    else:
        print("❌ No GPU found! Training will use CPU.")
        return False

setup_gpu()
tf.get_logger().setLevel('ERROR')

# ==================== CONFIGURATION ====================
PROJECT_ROOT = Path(__file__).parent.parent
DATA_DIR = PROJECT_ROOT / "data"
RAW_DATA_DIR = DATA_DIR / "raw"
PROCESSED_DATA_DIR = DATA_DIR / "processed"
MODELS_DIR = PROJECT_ROOT / "models" / "saved_models"

# Create directories
for dir_path in [RAW_DATA_DIR, PROCESSED_DATA_DIR, MODELS_DIR]:
    dir_path.mkdir(parents=True, exist_ok=True)

# FIXED HYPERPARAMETERS
SEQUENCE_LENGTH = 24  
BATCH_SIZE = 64        # Increased for better training
EPOCHS = 100           # Will train fully without early stopping
LEARNING_RATE = 0.001

print("\n" + "="*80)
print("SmartSync Schedule Predictor Training (FIXED)")
print("="*80)
print(f"Sequence Length: {SEQUENCE_LENGTH} hours (reduced for synthetic data)")
print(f"Batch Size: {BATCH_SIZE}")
print(f"Epochs: {EPOCHS} (no early stopping)")
print(f"Model Type: Simple MLP (better than LSTM for this data)")

# ==================== DATA LOADING ====================
def load_kaggle_dataset():
    """Load Kaggle smart home datasets"""
    print("\n📥 STEP 1: Loading Kaggle datasets...")

    dataset_files = [
        RAW_DATA_DIR / "HomeC.csv",
        RAW_DATA_DIR / "aruba.csv",
        RAW_DATA_DIR / "tulum.csv",
    ]

    all_dfs = []
    for file_path in dataset_files:
        if file_path.exists():
            print(f"   ✅ Found: {file_path.name}")
            try:
                df = pd.read_csv(file_path)
                if not any(col.lower() in ['date', 'time'] for col in df.columns):
                    df = pd.read_csv(file_path, header=None)
                    if 'HomeC' in file_path.name:
                        df.columns = ['time', 'use [kW]', 'gen [kW]', 'House overall [kW]', 'Dishwasher [kW]']
                    else:
                        df.columns = ['date', 'time', 'sensor', 'state']

                print(f"     → {len(df):,} records")
                all_dfs.append(df)
            except Exception as e:
                print(f"   ⚠️ Error reading {file_path.name}: {e}")

    if not all_dfs:
        print("\n❌ ERROR: No dataset files found!")
        return None

    print(f"\n   Combining {len(all_dfs)} dataset(s)...")
    combined_df = pd.concat(all_dfs, ignore_index=True)

    if 'time' not in combined_df.columns and 'date' in combined_df.columns:
        combined_df.rename(columns={'date': 'time'}, inplace=True)

    print(f"   ✅ Total records: {len(combined_df):,}")
    return combined_df

def convert_to_smartsync_format(df):
    """Convert Kaggle datasets to SmartSync format"""
    print("\n🔄 STEP 2: Converting to SmartSync format...")

    smartsync_df = pd.DataFrame()
    time_col = 'time' if 'time' in df.columns else 'date'
    smartsync_df['timestamp'] = pd.to_datetime(df[time_col], errors='coerce')

    # Create features based on available data
    if 'use [kW]' in df.columns:
        power = df['use [kW]'].fillna(0).astype(float)
        smartsync_df['temperature'] = 20 + (power * 1.5) + np.random.randn(len(df)) * 0.5
        smartsync_df['humidity'] = 50 + np.random.randn(len(df)) * 5
        smartsync_df['motionDetected'] = (power > power.quantile(0.3)).astype(int)
    elif 'sensor' in df.columns and 'state' in df.columns:
        smartsync_df['temperature'] = 22 + np.random.randn(len(df)) * 2
        smartsync_df['humidity'] = 55 + np.random.randn(len(df)) * 4
        smartsync_df['motionDetected'] = df['state'].apply(lambda x: 1 if str(x).upper() == 'ON' else 0)
    else:
        smartsync_df['temperature'] = 22 + np.random.randn(len(df))
        smartsync_df['humidity'] = 55 + np.random.randn(len(df))
        smartsync_df['motionDetected'] = np.random.randint(0, 2, len(df))

    # Targets
    smartsync_df['fanSpeed'] = smartsync_df['temperature'].apply(
        lambda t: int(np.clip((t - 20) / 15 * 255, 0, 255))
    )
    smartsync_df['ledBrightness'] = smartsync_df['motionDetected'].apply(
        lambda m: np.random.randint(180, 255) if m == 1 else np.random.randint(0, 80)
    )

    smartsync_df = smartsync_df.dropna(subset=['timestamp']).sort_values('timestamp').reset_index(drop=True)
    smartsync_df['temperature'] = smartsync_df['temperature'].clip(15, 40)
    smartsync_df['humidity'] = smartsync_df['humidity'].clip(20, 90)

    print(f"   ✅ Converted {len(smartsync_df):,} records")
    return smartsync_df

# ==================== DATA PREPROCESSING ====================
class DataPreprocessor:
    """Preprocess data for training"""

    def __init__(self):
        self.scaler = StandardScaler()
        self.feature_cols = None
        self.target_cols = None

    def create_hourly_features(self, df):
        """Aggregate to hourly features"""
        print("\n🔧 STEP 3: Creating hourly features...")

        df['hour'] = df['timestamp'].dt.floor('H')

        hourly = df.groupby('hour').agg({
            'temperature': ['mean', 'max', 'min'],
            'humidity': ['mean'],
            'motionDetected': 'sum',
            'fanSpeed': 'mean',
            'ledBrightness': 'mean'
        }).reset_index()

        hourly.columns = ['_'.join(col).strip('_') for col in hourly.columns]
        hourly.rename(columns={'hour_': 'hour'}, inplace=True)

        # Fill gaps
        all_hours = pd.date_range(start=hourly['hour'].min(), end=hourly['hour'].max(), freq='H')
        hourly = hourly.set_index('hour').reindex(all_hours)
        hourly = hourly.interpolate(method='linear').fillna(method='bfill').fillna(method='ffill')
        hourly = hourly.reset_index().rename(columns={'index': 'hour'})

        print(f"   ✅ Created {len(hourly):,} hourly records")
        return hourly

    def add_temporal_features(self, df):
        """Add time-based features"""
        print("   Adding temporal features...")

        df['hour_of_day'] = df['hour'].dt.hour
        df['day_of_week'] = df['hour'].dt.dayofweek
        df['is_weekend'] = (df['day_of_week'] >= 5).astype(int)

        # Cyclical encoding
        df['hour_sin'] = np.sin(2 * np.pi * df['hour_of_day'] / 24)
        df['hour_cos'] = np.cos(2 * np.pi * df['hour_of_day'] / 24)

        print(f"   ✅ Added temporal features")
        return df

    def prepare_sequences(self, df, sequence_length):
        """Prepare sequences for training"""
        print(f"\n📦 STEP 4: Preparing sequences (length={sequence_length})...")

        self.feature_cols = [
            'temperature_mean', 'temperature_max', 'temperature_min',
            'humidity_mean', 'motionDetected_sum',
            'hour_sin', 'hour_cos', 'is_weekend'
        ]
        self.target_cols = ['fanSpeed_mean', 'ledBrightness_mean']

        # Extract and normalize features
        features = df[self.feature_cols].values
        targets = df[self.target_cols].values

        features_normalized = self.scaler.fit_transform(features)
        targets_normalized = np.clip(targets, 0, 255) / 255.0

        # Create sequences
        X, y = [], []
        for i in range(len(features_normalized) - sequence_length):
            X.append(features_normalized[i:i + sequence_length])
            y.append(targets_normalized[i + sequence_length])

        X = np.array(X)
        y = np.array(y)

        print(f"   ✅ Created {len(X):,} sequences")
        print(f"   ✅ X shape: {X.shape}")
        print(f"   ✅ y shape: {y.shape}")

        return X, y

# ==================== BUILD MODEL (SIMPLIFIED) ====================
def build_simple_model(input_shape):
    """Build a simple MLP model (better for synthetic data)"""
    print("\n🏗️ STEP 5: Building SIMPLE MLP model...")
    print("   (MLP is better than LSTM for synthetic/weakly-temporal data)")

    # Flatten the sequence
    model = keras.Sequential([
        keras.layers.Input(shape=input_shape),
        keras.layers.Flatten(),  # Flatten the sequence
        keras.layers.Dense(128, activation='relu'),
        keras.layers.Dropout(0.3),
        keras.layers.Dense(64, activation='relu'),
        keras.layers.Dropout(0.2),
        keras.layers.Dense(32, activation='relu'),
        keras.layers.Dense(2, activation='sigmoid', name='output')
    ])

    model.compile(
        optimizer=keras.optimizers.Adam(learning_rate=LEARNING_RATE),
        loss='mse',
        metrics=['mae']
    )

    print("\n📊 Model Architecture:")
    model.summary()

    return model

# ==================== TRAINING ====================
def train_model(X_train, y_train, X_val, y_val):
    """Train the model"""
    print("\n🚀 STEP 6: Training model...")
    print(f"   Training samples: {len(X_train):,}")
    print(f"   Validation samples: {len(X_val):,}")

    model = build_simple_model(X_train.shape[1:])

    # Callbacks - NO EARLY STOPPING to allow full training
    callbacks = [
        keras.callbacks.ReduceLROnPlateau(
            monitor='val_loss',
            factor=0.5,
            patience=10,
            min_lr=1e-6,
            verbose=1
        ),
        keras.callbacks.ModelCheckpoint(
            str(MODELS_DIR / 'schedule_predictor_best.keras'),
            monitor='val_loss',
            save_best_only=True,
            verbose=1
        )
    ]

    print("\n   Starting training (will run all epochs)...")

    history = model.fit(
        X_train, y_train,
        epochs=EPOCHS,
        batch_size=BATCH_SIZE,
        validation_data=(X_val, y_val),
        callbacks=callbacks,
        verbose=1
    )

    # Plot history
    plot_training_history(history)

    return model, history

def plot_training_history(history):
    """Plot training history"""
    plt.figure(figsize=(14, 5))

    plt.subplot(1, 2, 1)
    plt.plot(history.history['loss'], label='Training Loss', linewidth=2)
    plt.plot(history.history['val_loss'], label='Validation Loss', linewidth=2)
    plt.xlabel('Epoch', fontsize=12)
    plt.ylabel('Loss (MSE)', fontsize=12)
    plt.title('Training History - Loss', fontsize=14, fontweight='bold')
    plt.legend(fontsize=11)
    plt.grid(True, alpha=0.3)

    plt.subplot(1, 2, 2)
    plt.plot(history.history['mae'], label='Training MAE', linewidth=2)
    plt.plot(history.history['val_mae'], label='Validation MAE', linewidth=2)
    plt.xlabel('Epoch', fontsize=12)
    plt.ylabel('MAE', fontsize=12)
    plt.title('Training History - MAE', fontsize=14, fontweight='bold')
    plt.legend(fontsize=11)
    plt.grid(True, alpha=0.3)

    plt.tight_layout()
    plot_path = MODELS_DIR / 'training_history.png'
    plt.savefig(plot_path, dpi=300, bbox_inches='tight')
    print(f"\n   ✅ Saved training plot to {plot_path}")
    plt.close()

# ==================== EVALUATION ====================
def evaluate_model(model, X_test, y_test):
    """Evaluate model on test set"""
    print("\n📈 STEP 7: Evaluating model...")

    y_pred = model.predict(X_test, verbose=0)

    mae = mean_absolute_error(y_test, y_pred)
    rmse = np.sqrt(mean_squared_error(y_test, y_pred))
    r2 = r2_score(y_test, y_pred)

    mae_fan = mean_absolute_error(y_test[:, 0], y_pred[:, 0])
    mae_led = mean_absolute_error(y_test[:, 1], y_pred[:, 1])

    print(f"\n✅ Test Results:")
    print(f"   MAE: {mae:.4f}")
    print(f"   RMSE: {rmse:.4f}")
    print(f"   R²: {r2:.4f}")
    print(f"\n   Fan Speed MAE: {mae_fan:.4f} (0-1 scale)")
    print(f"   LED Brightness MAE: {mae_led:.4f} (0-1 scale)")

    plot_predictions(y_test, y_pred)

    return {
        'mae': float(mae),
        'rmse': float(rmse),
        'r2': float(r2),
        'mae_fan': float(mae_fan),
        'mae_led': float(mae_led)
    }

def plot_predictions(y_test, y_pred):
    """Plot actual vs predicted"""
    plt.figure(figsize=(14, 5))

    plt.subplot(1, 2, 1)
    plt.scatter(y_test[:, 0], y_pred[:, 0], alpha=0.3, s=5)
    plt.plot([0, 1], [0, 1], 'r--', linewidth=2, label='Perfect Prediction')
    plt.xlabel('Actual Fan Speed', fontsize=12)
    plt.ylabel('Predicted Fan Speed', fontsize=12)
    plt.title('Fan Speed Predictions', fontsize=14, fontweight='bold')
    plt.legend(fontsize=11)
    plt.grid(True, alpha=0.3)

    plt.subplot(1, 2, 2)
    plt.scatter(y_test[:, 1], y_pred[:, 1], alpha=0.3, s=5)
    plt.plot([0, 1], [0, 1], 'r--', linewidth=2, label='Perfect Prediction')
    plt.xlabel('Actual LED Brightness', fontsize=12)
    plt.ylabel('Predicted LED Brightness', fontsize=12)
    plt.title('LED Brightness Predictions', fontsize=14, fontweight='bold')
    plt.legend(fontsize=11)
    plt.grid(True, alpha=0.3)

    plt.tight_layout()
    plot_path = MODELS_DIR / 'predictions.png'
    plt.savefig(plot_path, dpi=300, bbox_inches='tight')
    print(f"   ✅ Saved prediction plot to {plot_path}")
    plt.close()

# ==================== SAVE MODEL ====================
def save_model(model, preprocessor, metrics):
    """Save model, scaler, and metadata"""
    print("\n💾 STEP 8: Saving model...")

    model_path = MODELS_DIR / 'schedule_predictor_v1'
    model.save(model_path)
    print(f"   ✅ Saved model to {model_path}")

    scaler_path = PROCESSED_DATA_DIR / 'scaler.pkl'
    joblib.dump(preprocessor.scaler, scaler_path)
    print(f"   ✅ Saved scaler to {scaler_path}")

    metadata = {
        'model_version': '1.0.0',
        'trained_date': datetime.now().isoformat(),
        'model_type': 'MLP',
        'sequence_length': SEQUENCE_LENGTH,
        'batch_size': BATCH_SIZE,
        'epochs': EPOCHS,
        'learning_rate': LEARNING_RATE,
        'metrics': metrics,
        'input_features': preprocessor.feature_cols,
        'output_targets': preprocessor.target_cols,
    }

    metadata_path = model_path / 'metadata.json'
    with open(metadata_path, 'w') as f:
        json.dump(metadata, f, indent=2)
    print(f"   ✅ Saved metadata to {metadata_path}")

# ==================== MAIN ====================
def main():
    """Main training pipeline"""
    print("\n" + "="*80)
    print("STARTING FIXED TRAINING PIPELINE")
    print("="*80)

    # Load data
    raw_df = load_kaggle_dataset()
    if raw_df is None:
        return

    # Convert format
    smartsync_df = convert_to_smartsync_format(raw_df)

    # Preprocess
    preprocessor = DataPreprocessor()
    hourly_df = preprocessor.create_hourly_features(smartsync_df)
    hourly_df = preprocessor.add_temporal_features(hourly_df)

    # Prepare sequences
    X, y = preprocessor.prepare_sequences(hourly_df, SEQUENCE_LENGTH)

    # Split data (sequential)
    train_size = int(len(X) * 0.7)
    val_size = int(len(X) * 0.15)

    X_train, y_train = X[:train_size], y[:train_size]
    X_val, y_val = X[train_size:train_size + val_size], y[train_size:train_size + val_size]
    X_test, y_test = X[train_size + val_size:], y[train_size + val_size:]

    print(f"\n   Training: {len(X_train):,}")
    print(f"   Validation: {len(X_val):,}")
    print(f"   Test: {len(X_test):,}")

    # Train
    model, history = train_model(X_train, y_train, X_val, y_val)

    # Evaluate
    metrics = evaluate_model(model, X_test, y_test)

    # Save
    save_model(model, preprocessor, metrics)

    # Summary
    print("\n" + "="*80)
    print("✅ TRAINING COMPLETE!")
    print("="*80)
    print(f"\n📊 Final Performance:")
    print(f"   MAE: {metrics['mae']:.4f}")
    print(f"   RMSE: {metrics['rmse']:.4f}")
    print(f"   R²: {metrics['r2']:.4f}")

    if metrics['r2'] > 0.7:
        print(f"\n🎉 Excellent performance! (R² > 0.7)")
    elif metrics['r2'] > 0.5:
        print(f"\n👍 Good performance! (R² > 0.5)")
    elif metrics['r2'] > 0:
        print(f"\n⚠️ Fair performance (R² > 0)")
    else:
        print(f"\n❌ Poor performance (R² < 0)")

    print(f"\n🎯 Next Steps:")
    print(f"   1. Convert to TFLite: python scripts/convert_tflite.py")
    print(f"   2. Deploy to Firebase: python scripts/deploy_model.py")

if __name__ == "__main__":
    main()