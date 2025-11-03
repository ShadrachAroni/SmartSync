#!/usr/bin/env python3
"""
SmartSync ML Training - Using Kaggle Smart Home Dataset
File: ml/scripts/train_smart_home.py

This script trains the schedule predictor using your downloaded Kaggle datasets.
No Firebase data required!

Usage:
    cd ml
    python scripts/train_smart_home.py
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
import shutil
import warnings
warnings.filterwarnings('ignore')

tf.get_logger().setLevel('ERROR')
# ==================== CONFIGURATION ====================
PROJECT_ROOT = Path(__file__).parent.parent
DATA_DIR = PROJECT_ROOT / "data"
RAW_DATA_DIR = DATA_DIR / "raw"
PROCESSED_DATA_DIR = DATA_DIR / "processed"
MODELS_DIR = PROJECT_ROOT / "models" / "saved_models"
TFLITE_DIR = PROJECT_ROOT / "models" / "tflite"
APP_ASSETS = PROJECT_ROOT.parent / "app" / "assets" / "models"

# Create directories
for dir_path in [RAW_DATA_DIR, PROCESSED_DATA_DIR, MODELS_DIR, TFLITE_DIR, APP_ASSETS]:
    dir_path.mkdir(parents=True, exist_ok=True)

SEQUENCE_LENGTH = 168  # 1 week of hourly data
BATCH_SIZE = 32
EPOCHS = 50
LEARNING_RATE = 0.001

print("=" * 80)
print("SmartSync Schedule Predictor Training")
print("Using Kaggle Smart Home Dataset")
print("=" * 80)

# ==================== LOAD KAGGLE DATASET ====================
def load_kaggle_dataset():
    """
    Load Kaggle smart home datasets from ml/data/raw/
    """
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
                
                # If columns aren't labeled properly (like '2010-11-04', etc.)
                if not any(col.lower() in ['date', 'time'] for col in df.columns):
                    df = pd.read_csv(file_path, header=None)
                    if 'HomeC' in file_path.name:
                        df.columns = ['time', 'use [kW]', 'gen [kW]', 'House overall [kW]', 'Dishwasher [kW]']
                    else:
                        df.columns = ['date', 'time', 'sensor', 'state']
                
                print(f"      → {len(df):,} records")
                print(f"      → Columns: {list(df.columns)[:5]}...")
                all_dfs.append(df)
            except Exception as e:
                print(f"      ⚠️  Error reading {file_path.name}: {e}")
        else:
            print(f"   ⚠️  Not found: {file_path.name}")
    
    if not all_dfs:
        print("\n❌ ERROR: No dataset files found!")
        return None

    print(f"\n   Combining {len(all_dfs)} dataset(s)...")
    combined_df = pd.concat(all_dfs, ignore_index=True)

    # Normalize timestamp column
    if 'time' not in combined_df.columns and 'date' in combined_df.columns:
        combined_df.rename(columns={'date': 'time'}, inplace=True)
    
    print(f"   ✅ Total records: {len(combined_df):,}")
    print(f"   ✅ Date range: {combined_df.iloc[0]['time']} to {combined_df.iloc[-1]['time']}")
    
    return combined_df

def convert_to_smartsync_format(df):
    """
    Convert mixed Kaggle smart home datasets (HomeC + Aruba + Tulum)
    into the SmartSync unified sensor log format.
    """

    print("\n🔄 STEP 2: Converting to SmartSync format...")

    smartsync_df = pd.DataFrame()

    # Identify time column (either 'time' or 'date')
    time_col = 'time' if 'time' in df.columns else 'date'
    smartsync_df['timestamp'] = pd.to_datetime(df[time_col], errors='coerce')

    # --- Synthetic or derived features ---

    # If power usage columns exist (HomeC dataset)
    if 'use [kW]' in df.columns:
        # Use power usage as a proxy for activity and temperature
        power = df['use [kW]'].astype(float)
        smartsync_df['temperature'] = 20 + (power * 2)  # synthetic temperature
        smartsync_df['humidity'] = 50 + (np.random.randn(len(df)) * 5)
        smartsync_df['motionDetected'] = (power > power.mean()).astype(int)
    elif 'sensor' in df.columns and 'state' in df.columns:
        # Convert ON/OFF states from Aruba/Tulum datasets
        smartsync_df['temperature'] = 22 + (np.random.randn(len(df)) * 2)
        smartsync_df['humidity'] = 55 + (np.random.randn(len(df)) * 4)
        smartsync_df['motionDetected'] = df['state'].apply(lambda x: 1 if str(x).upper() == 'ON' else 0)
    else:
        # Fallback synthetic values
        smartsync_df['temperature'] = 22 + np.random.randn(len(df))
        smartsync_df['humidity'] = 55 + np.random.randn(len(df))
        smartsync_df['motionDetected'] = np.random.randint(0, 2, len(df))

    # Fan speed: proportional to temperature
    smartsync_df['fanSpeed'] = smartsync_df['temperature'].apply(
        lambda t: int(max(0, min(255, (t - 20) / 15 * 255))) if t > 24 else 0
    )

    # LED brightness: inverse of motion (on when dark or no motion)
    smartsync_df['ledBrightness'] = smartsync_df['motionDetected'].apply(
        lambda m: np.random.randint(150, 255) if m == 1 else np.random.randint(0, 100)
    )

    # Distance: random variation depending on motion
    smartsync_df['distance'] = smartsync_df['motionDetected'].apply(
        lambda occ: np.random.uniform(50, 150) if occ == 1 else np.random.uniform(200, 400)
    )

    # Sort and clean
    smartsync_df = smartsync_df.dropna(subset=['timestamp']).sort_values('timestamp').reset_index(drop=True)

    print(f"   ✅ Converted {len(smartsync_df):,} records")
    print(f"   ✅ Features: {list(smartsync_df.columns)}")

    print("\n   Sample data (first 3 rows):")
    print(smartsync_df.head(3).to_string(index=False))

    return smartsync_df

# ==================== PREPROCESSING ====================
# ==================== PREPROCESSING ====================
class DataPreprocessor:
    """Preprocess data for LSTM training (robust version for sparse smart home logs)"""

    def __init__(self):
        self.scaler = StandardScaler()

    def create_hourly_features(self, df):
        """
        Aggregate minute/event-level data to hourly features

        For each hour, calculate:
        - Mean, max, min temperature
        - Mean humidity
        - Total motion events
        - Mean distance
        - Fan/LED usage duration
        """
        print("\n🔧 STEP 3: Creating hourly features...")

        # Floor timestamps to the nearest hour
        df['hour'] = df['timestamp'].dt.floor('H')

        # Aggregate by hour
        hourly = df.groupby('hour').agg({
            'temperature': ['mean', 'max', 'min'],
            'humidity': 'mean',
            'motionDetected': 'sum',  # number of motion detections in that hour
            'distance': 'mean',
            'fanSpeed': lambda x: (x > 0).sum(),
            'ledBrightness': lambda x: (x > 0).sum()
        }).reset_index()

        # Flatten column names
        hourly.columns = ['_'.join(col).strip('_') for col in hourly.columns]
        hourly.rename(columns={'hour_': 'hour'}, inplace=True)

        # 🩹 Ensure continuous hourly coverage (fill gaps)
        all_hours = pd.date_range(start=hourly['hour'].min(), end=hourly['hour'].max(), freq='H')
        hourly = hourly.set_index('hour').reindex(all_hours)
        hourly = hourly.interpolate(method='linear').reset_index().rename(columns={'index': 'hour'})

        print(f"   ✅ Created {len(hourly):,} hourly records (after filling gaps)")
        print(f"   ✅ Features: {list(hourly.columns)}")

        return hourly

    def add_temporal_features(self, df):
        """
        Add time-based features for pattern recognition

        Features:
        - Hour of day (0–23)
        - Day of week (0–6)
        - Is weekend (0/1)
        - Is night (0/1)
        - Cyclical encodings (sin/cos)
        """
        print("\n   Adding temporal features...")

        df['hour_of_day'] = df['hour'].dt.hour
        df['day_of_week'] = df['hour'].dt.dayofweek
        df['is_weekend'] = (df['day_of_week'] >= 5).astype(int)
        df['is_night'] = ((df['hour_of_day'] >= 22) | (df['hour_of_day'] <= 6)).astype(int)

        # Cyclical encoding for periodic patterns
        df['hour_sin'] = np.sin(2 * np.pi * df['hour_of_day'] / 24)
        df['hour_cos'] = np.cos(2 * np.pi * df['hour_of_day'] / 24)
        df['day_sin'] = np.sin(2 * np.pi * df['day_of_week'] / 7)
        df['day_cos'] = np.cos(2 * np.pi * df['day_of_week'] / 7)

        # No manual actions available → set to 0
        df['manual_actions'] = 0

        print(f"   ✅ Added temporal features")
        return df

    def create_sequences(self, df, sequence_length=168):
        """
        Create rolling sequences for LSTM input.

        Args:
            df: hourly DataFrame
            sequence_length: number of past hours to include (default = 168)

        Returns:
            X: np.ndarray [samples, timesteps, features]
            y: np.ndarray [samples, 2]
        """
        print(f"\n📦 STEP 4: Creating sequences (lookback={sequence_length}h)...")

        feature_cols = [
            'temperature_mean', 'temperature_max', 'temperature_min',
            'humidity_mean', 'motionDetected_sum', 'distance_mean',
            'hour_sin', 'hour_cos', 'day_sin', 'day_cos',
            'is_weekend', 'is_night', 'manual_actions'
        ]

        target_cols = ['fanSpeed_<lambda>', 'ledBrightness_<lambda>']

        # Safety check
        if len(df) <= sequence_length:
            print(f"⚠️ Not enough data to create sequences (rows={len(df)}, need>{sequence_length}).")
            print("   Lower SEQUENCE_LENGTH in your config (e.g., SEQUENCE_LENGTH = 24).")
            return np.array([]), np.array([])

        # Normalize inputs
        features = df[feature_cols].values
        features_normalized = self.scaler.fit_transform(features)

        # Normalize outputs (0–1)
        targets = df[target_cols].values / 255.0

        # Create sequences
        X, y = [], []
        for i in range(len(df) - sequence_length):
            X.append(features_normalized[i:i + sequence_length])
            y.append(targets[i + sequence_length])

        X = np.array(X, dtype=np.float32)
        y = np.array(y, dtype=np.float32)

        print(f"   ✅ Created {len(X):,} sequences")
        print(f"   ✅ Input shape:  {X.shape}")
        print(f"   ✅ Output shape: {y.shape}")
        print(f"   ✅ Memory usage: {X.nbytes / 1024 / 1024:.2f} MB")

        return X, y

# ==================== MODEL ARCHITECTURE ====================
def build_model(input_shape):
    """
    Build LSTM-based schedule prediction model
    
    Architecture:
    - Input: (168, 13) - 1 week of hourly features
    - LSTM layers with dropout for regularization
    - Dense output: (2,) - fan speed & LED brightness
    
    Args:
        input_shape: (timesteps, features)
    
    Returns:
        Compiled Keras model
    """
    print("\n🏗️  STEP 5: Building LSTM model...")
    
    model = keras.Sequential([
        keras.layers.Input(shape=input_shape),
        
        # First LSTM layer - capture long-term patterns
        keras.layers.LSTM(128, return_sequences=True, name='lstm_1'),
        keras.layers.Dropout(0.3),
        
        # Second LSTM layer - refine patterns
        keras.layers.LSTM(64, return_sequences=False, name='lstm_2'),
        keras.layers.Dropout(0.2),
        
        # Dense layers for final prediction
        keras.layers.Dense(32, activation='relu', name='dense_1'),
        keras.layers.Dropout(0.2),
        
        # Output: [fan_speed, led_brightness] in range [0, 1]
        keras.layers.Dense(2, activation='sigmoid', name='output')
    ])
    
    model.compile(
        optimizer=keras.optimizers.Adam(learning_rate=LEARNING_RATE),
        loss='mse',  # Mean squared error
        metrics=['mae']  # Mean absolute error
    )
    
    print("\n📊 Model Architecture:")
    model.summary()
    
    total_params = model.count_params()
    print(f"\n   Total parameters: {total_params:,}")
    
    return model

# ==================== TRAINING ====================
def train_model(X_train, y_train, X_val, y_val):
    """
    Train the schedule prediction model
    
    Args:
        X_train: Training sequences
        y_train: Training targets
        X_val: Validation sequences
        y_val: Validation targets
    
    Returns:
        model: Trained Keras model
        history: Training history
    """
    print("\n🚀 STEP 6: Training model...")
    print(f"   Batch size: {BATCH_SIZE}")
    print(f"   Max epochs: {EPOCHS}")
    print(f"   Learning rate: {LEARNING_RATE}")
    
    model = build_model((X_train.shape[1], X_train.shape[2]))
    
    # Callbacks for better training
    callbacks = [
        # Stop training if validation loss doesn't improve for 10 epochs
        keras.callbacks.EarlyStopping(
            monitor='val_loss',
            patience=10,
            restore_best_weights=True,
            verbose=1
        ),
        
        # Reduce learning rate when validation loss plateaus
        keras.callbacks.ReduceLROnPlateau(
            monitor='val_loss',
            factor=0.5,
            patience=5,
            min_lr=1e-6,
            verbose=1
        ),
        
        # Save best model during training
        keras.callbacks.ModelCheckpoint(
            str(MODELS_DIR / 'schedule_predictor_best.keras'),
            monitor='val_loss',
            save_best_only=True,
            verbose=1
        )

    ]
    
    # Train
    history = model.fit(
        X_train, y_train,
        batch_size=BATCH_SIZE,
        epochs=EPOCHS,
        validation_data=(X_val, y_val),
        callbacks=callbacks,
        verbose=1
    )
    
    # Plot training history
    print("\n   Generating training plots...")
    plot_training_history(history)
    
    return model, history

def plot_training_history(history):
    """Plot loss and MAE over epochs"""
    plt.figure(figsize=(14, 5))
    
    # Loss plot
    plt.subplot(1, 2, 1)
    plt.plot(history.history['loss'], label='Training Loss', linewidth=2)
    plt.plot(history.history['val_loss'], label='Validation Loss', linewidth=2)
    plt.xlabel('Epoch', fontsize=12)
    plt.ylabel('Loss (MSE)', fontsize=12)
    plt.title('Training History - Loss', fontsize=14, fontweight='bold')
    plt.legend(fontsize=11)
    plt.grid(True, alpha=0.3)
    
    # MAE plot
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
    print(f"      ✅ Saved to {plot_path}")
    plt.close()

# ==================== EVALUATION ====================
def evaluate_model(model, X_test, y_test):
    """
    Evaluate model performance on test set
    
    Metrics:
    - MAE: Mean Absolute Error
    - RMSE: Root Mean Squared Error
    - R²: Coefficient of determination
    """
    print("\n📈 STEP 7: Evaluating model...")
    
    # Predictions
    y_pred = model.predict(X_test, verbose=0)
    
    # Calculate metrics
    from sklearn.metrics import mean_absolute_error, mean_squared_error, r2_score
    
    mae = mean_absolute_error(y_test, y_pred)
    rmse = np.sqrt(mean_squared_error(y_test, y_pred))
    r2 = r2_score(y_test, y_pred)
    
    print(f"\n✅ Test Results:")
    print(f"   MAE:  {mae:.4f}")
    print(f"   RMSE: {rmse:.4f}")
    print(f"   R²:   {r2:.4f}")
    
    # Separate metrics for fan and LED
    mae_fan = mean_absolute_error(y_test[:, 0], y_pred[:, 0])
    mae_led = mean_absolute_error(y_test[:, 1], y_pred[:, 1])
    
    print(f"\n   Fan Speed MAE:       {mae_fan:.4f}")
    print(f"   LED Brightness MAE:  {mae_led:.4f}")
    
    # Visualize predictions
    print("\n   Generating prediction plots...")
    plot_predictions(y_test, y_pred)
    
    return {
        'mae': float(mae),
        'rmse': float(rmse),
        'r2': float(r2),
        'mae_fan': float(mae_fan),
        'mae_led': float(mae_led)
    }

def plot_predictions(y_test, y_pred):
    """Plot actual vs predicted values"""
    plt.figure(figsize=(14, 5))
    
    # Fan predictions
    plt.subplot(1, 2, 1)
    plt.scatter(y_test[:, 0], y_pred[:, 0], alpha=0.5, s=10)
    plt.plot([0, 1], [0, 1], 'r--', linewidth=2, label='Perfect Prediction')
    plt.xlabel('Actual Fan Speed', fontsize=12)
    plt.ylabel('Predicted Fan Speed', fontsize=12)
    plt.title('Fan Speed Predictions', fontsize=14, fontweight='bold')
    plt.legend(fontsize=11)
    plt.grid(True, alpha=0.3)
    
    # LED predictions
    plt.subplot(1, 2, 2)
    plt.scatter(y_test[:, 1], y_pred[:, 1], alpha=0.5, s=10)
    plt.plot([0, 1], [0, 1], 'r--', linewidth=2, label='Perfect Prediction')
    plt.xlabel('Actual LED Brightness', fontsize=12)
    plt.ylabel('Predicted LED Brightness', fontsize=12)
    plt.title('LED Brightness Predictions', fontsize=14, fontweight='bold')
    plt.legend(fontsize=11)
    plt.grid(True, alpha=0.3)
    
    plt.tight_layout()
    plot_path = MODELS_DIR / 'predictions.png'
    plt.savefig(plot_path, dpi=300, bbox_inches='tight')
    print(f"      ✅ Saved to {plot_path}")
    plt.close()

# ==================== SAVE MODEL ====================
def save_model(model, preprocessor, metrics):
    """
    Save trained model, scaler, and metadata
    
    Outputs:
    - models/saved_models/schedule_predictor_v1/ (Keras model)
    - data/processed/scaler.pkl (StandardScaler)
    - models/saved_models/schedule_predictor_v1/metadata.json
    """
    print("\n💾 STEP 8: Saving model...")
    
    # Save Keras model
    model_path = MODELS_DIR / 'schedule_predictor_v1'
    model.save(model_path)
    print(f"   ✅ Saved model to {model_path}")
    
    # Save scaler for feature normalization
    scaler_path = PROCESSED_DATA_DIR / 'scaler.pkl'
    joblib.dump(preprocessor.scaler, scaler_path)
    print(f"   ✅ Saved scaler to {scaler_path}")
    
    # Save metadata
    metadata = {
        'model_version': '1.0.0',
        'trained_date': datetime.now().isoformat(),
        'sequence_length': SEQUENCE_LENGTH,
        'batch_size': BATCH_SIZE,
        'epochs_trained': EPOCHS,
        'learning_rate': LEARNING_RATE,
        'metrics': metrics,
        'framework': 'TensorFlow',
        'framework_version': tf.__version__,
        'training_source': 'Kaggle Smart Home Dataset',
        'input_shape': [SEQUENCE_LENGTH, 13],
        'output_shape': [2],
        'features': [
            'temperature_mean', 'temperature_max', 'temperature_min',
            'humidity_mean', 'motionDetected_sum', 'distance_mean',
            'hour_sin', 'hour_cos', 'day_sin', 'day_cos',
            'is_weekend', 'is_night', 'manual_actions'
        ],
        'outputs': ['fan_speed_0to1', 'led_brightness_0to1']
    }
    
    metadata_path = model_path / 'metadata.json'
    with open(metadata_path, 'w') as f:
        json.dump(metadata, f, indent=2)
    print(f"   ✅ Saved metadata to {metadata_path}")

# ==================== AUTO-COPY TO FLUTTER ====================
def copy_to_flutter_assets():
    """
    Automatically copy TFLite models to Flutter assets folder
    
    This replaces the manual 'cp' command:
    cp ml/models/tflite/*.tflite app/assets/models/
    """
    print("\n📲 STEP 9: Copying to Flutter assets...")
    
    if not TFLITE_DIR.exists():
        print("   ⚠️  TFLite directory not found. Run convert_tflite.py first.")
        return False
    
    tflite_files = list(TFLITE_DIR.glob('*.tflite'))
    
    if not tflite_files:
        print("   ⚠️  No .tflite files found. Run convert_tflite.py first.")
        return False
    
    # Ensure Flutter assets directory exists
    APP_ASSETS.mkdir(parents=True, exist_ok=True)
    
    copied_count = 0
    for tflite_file in tflite_files:
        dest = APP_ASSETS / tflite_file.name
        try:
            shutil.copy2(tflite_file, dest)
            print(f"   ✅ Copied {tflite_file.name} → {dest}")
            copied_count += 1
        except Exception as e:
            print(f"   ❌ Failed to copy {tflite_file.name}: {e}")
    
    if copied_count > 0:
        print(f"\n   ✅ Successfully copied {copied_count} model(s) to Flutter assets!")
        return True
    else:
        print(f"\n   ❌ Failed to copy models to Flutter assets")
        return False

# ==================== MAIN PIPELINE ====================
def main():
    """Main training pipeline"""
    
    print("\n" + "="*80)
    print("STARTING TRAINING PIPELINE")
    print("="*80)
    
    # Step 1: Load Kaggle dataset
    raw_df = load_kaggle_dataset()
    if raw_df is None:
        print("\n❌ Training aborted: No dataset found")
        return
    
    # Step 2: Convert to SmartSync format
    smartsync_df = convert_to_smartsync_format(raw_df)
    
    # Save raw converted data
    smartsync_df.to_csv(RAW_DATA_DIR / 'smartsync_format.csv', index=False)
    print(f"\n   💾 Saved converted data to {RAW_DATA_DIR / 'smartsync_format.csv'}")
    
    # Step 3-4: Preprocess and create sequences
    preprocessor = DataPreprocessor()
    hourly_df = preprocessor.create_hourly_features(smartsync_df)
    hourly_df = preprocessor.add_temporal_features(hourly_df)
    
    # Save processed features
    hourly_df.to_csv(PROCESSED_DATA_DIR / 'hourly_features.csv', index=False)
    print(f"   💾 Saved hourly features to {PROCESSED_DATA_DIR / 'hourly_features.csv'}")
    
    X, y = preprocessor.create_sequences(hourly_df, SEQUENCE_LENGTH)
    
    # Split data: 70% train, 15% validation, 15% test
    print("\n📊 Splitting data...")
    X_train, X_temp, y_train, y_temp = train_test_split(
        X, y, test_size=0.3, random_state=42, shuffle=True
    )
    X_val, X_test, y_val, y_test = train_test_split(
        X_temp, y_temp, test_size=0.5, random_state=42, shuffle=True
    )
    
    print(f"   Training:   {len(X_train):,} samples ({len(X_train)/len(X)*100:.1f}%)")
    print(f"   Validation: {len(X_val):,} samples ({len(X_val)/len(X)*100:.1f}%)")
    print(f"   Test:       {len(X_test):,} samples ({len(X_test)/len(X)*100:.1f}%)")
    
    # Step 5-6: Build and train model
    model, history = train_model(X_train, y_train, X_val, y_val)
    
    # Step 7: Evaluate
    metrics = evaluate_model(model, X_test, y_test)
    
    # Step 8: Save
    save_model(model, preprocessor, metrics)
    
    # Display final summary
    print("\n" + "="*80)
    print("✅ TRAINING COMPLETE!")
    print("="*80)
    print(f"\n📊 Final Model Performance:")
    print(f"   MAE:  {metrics['mae']:.4f}")
    print(f"   RMSE: {metrics['rmse']:.4f}")
    print(f"   R²:   {metrics['r2']:.4f}")
    
    print(f"\n📁 Output Files:")
    print(f"   Model:    {MODELS_DIR / 'schedule_predictor_v1'}")
    print(f"   Scaler:   {PROCESSED_DATA_DIR / 'scaler.pkl'}")
    print(f"   Metadata: {MODELS_DIR / 'schedule_predictor_v1' / 'metadata.json'}")
    
    print(f"\n🎯 Next Steps:")
    print(f"   1. Convert to TFLite:  python scripts/convert_tflite.py")
    print(f"   2. Deploy to Firebase: python scripts/deploy_model.py")
    print(f"   3. Test in Flutter app")

if __name__ == "__main__":
    main()