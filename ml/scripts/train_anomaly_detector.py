#!/usr/bin/env python3
"""
SmartSync Anomaly Detection Training Script

This script trains an autoencoder to detect anomalous behavior patterns
that may indicate health issues or emergencies for elderly users.

Anomaly Types Detected:
1. Extended inactivity (>12 hours no motion)
2. Unusual nighttime activity (frequent motion 22:00-06:00)
3. Temperature extremes (too hot/cold for extended period)
4. Sudden pattern changes (deviation from learned routine)
"""

import numpy as np
import pandas as pd
import tensorflow as tf
from tensorflow import keras
from sklearn.preprocessing import StandardScaler
from sklearn.model_selection import train_test_split
import json
from datetime import datetime, timedelta
from pathlib import Path
import matplotlib.pyplot as plt
import seaborn as sns

# ==================== CONFIGURATION ====================
PROJECT_ROOT = Path(__file__).parent.parent
DATA_DIR = PROJECT_ROOT / "data"
PROCESSED_DATA_DIR = DATA_DIR / "processed"
MODELS_DIR = PROJECT_ROOT / "models" / "saved_models"

# Model hyperparameters
LOOKBACK_HOURS = 24  # Analyze 24-hour windows
ENCODING_DIM = 8
BATCH_SIZE = 32
EPOCHS = 100
LEARNING_RATE = 0.001

print("=" * 70)
print("SmartSync Anomaly Detector - Training Pipeline")
print("=" * 70)

# ==================== DATA PREPARATION ====================
class AnomalyDataPreprocessor:
    """Prepare data for anomaly detection training"""
    
    def __init__(self):
        self.scaler = StandardScaler()
    
    def load_hourly_data(self, filepath):
        """Load preprocessed hourly data"""
        print(f"\n📥 Loading data from {filepath}...")
        df = pd.read_csv(filepath)
        df['hour'] = pd.to_datetime(df['hour'])
        print(f"   Loaded {len(df)} hourly records")
        return df
    
    def create_anomaly_features(self, df):
        """
        Create features specific to anomaly detection
        
        Features focus on:
        - Activity levels
        - Temperature comfort
        - Pattern consistency
        - Time-based behavior
        """
        print("\n🔧 Creating anomaly detection features...")
        
        # Rolling statistics (24-hour windows)
        df = df.sort_values('hour')
        
        # Motion-based features
        df['motion_24h_sum'] = df['motionDetected_sum'].rolling(24, min_periods=1).sum()
        df['motion_24h_mean'] = df['motionDetected_sum'].rolling(24, min_periods=1).mean()
        df['motion_24h_std'] = df['motionDetected_sum'].rolling(24, min_periods=1).std()
        
        # Temperature comfort features
        df['temp_deviation'] = (df['temperature_mean'] - 22).abs()  # 22°C = comfort
        df['temp_24h_range'] = df['temperature_max'].rolling(24).max() - \
                               df['temperature_min'].rolling(24).min()
        
        # Activity consistency
        df['hour_of_day'] = df['hour'].dt.hour
        df['active_nighttime'] = ((df['hour_of_day'] >= 22) | (df['hour_of_day'] <= 6)) & \
                                 (df['motionDetected_sum'] > 0)
        df['active_nighttime'] = df['active_nighttime'].astype(int)
        
        # Device usage patterns
        df['fan_running'] = (df['fanSpeed_<lambda>'] > 0).astype(int)
        df['led_running'] = (df['ledBrightness_<lambda>'] > 0).astype(int)
        
        # Time since last activity
        df['hours_since_motion'] = 0
        last_motion_hour = 0
        for idx, row in df.iterrows():
            if row['motionDetected_sum'] > 0:
                last_motion_hour = 0
            else:
                last_motion_hour += 1
            df.at[idx, 'hours_since_motion'] = last_motion_hour
        
        # Fill NaN values
        df = df.fillna(method='bfill').fillna(method='ffill')
        
        print(f"   Created {len(df.columns)} features")
        return df
    
    def create_sequences(self, df, lookback=24):
        """
        Create 24-hour sequences for autoencoder training
        
        Args:
            df: Hourly feature dataframe
            lookback: Hours to look back (default 24)
        
        Returns:
            X: Input sequences (only normal behavior for training)
        """
        print(f"\n📦 Creating {lookback}-hour sequences...")
        
        # Select relevant features
        feature_cols = [
            'temperature_mean', 'humidity_mean',
            'motion_24h_sum', 'motion_24h_mean', 'motion_24h_std',
            'temp_deviation', 'temp_24h_range',
            'active_nighttime', 'hours_since_motion',
            'fan_running', 'led_running',
            'hour_sin', 'hour_cos', 'day_sin', 'day_cos'
        ]
        
        # Normalize
        features = df[feature_cols].values
        features_normalized = self.scaler.fit_transform(features)
        
        # Create sequences
        X = []
        for i in range(len(df) - lookback):
            X.append(features_normalized[i:i+lookback])
        
        X = np.array(X)
        
        print(f"   Created {len(X)} sequences")
        print(f"   Input shape: {X.shape}")
        
        return X, feature_cols

# ==================== AUTOENCODER MODEL ====================
def build_autoencoder(input_shape, encoding_dim=8):
    """
    Build LSTM Autoencoder for anomaly detection
    
    Architecture:
    - Encoder: Compress sequence to low-dimensional representation
    - Decoder: Reconstruct original sequence
    - Anomalies have high reconstruction error
    """
    print("\n🏗️  Building autoencoder architecture...")
    
    # Encoder
    encoder_inputs = keras.layers.Input(shape=input_shape)
    
    # Encode temporal patterns
    encoded = keras.layers.LSTM(64, return_sequences=True)(encoder_inputs)
    encoded = keras.layers.Dropout(0.2)(encoded)
    encoded = keras.layers.LSTM(32, return_sequences=True)(encoded)
    encoded = keras.layers.Dropout(0.2)(encoded)
    encoded = keras.layers.LSTM(encoding_dim, return_sequences=False)(encoded)
    
    # Decoder
    decoded = keras.layers.RepeatVector(input_shape[0])(encoded)
    decoded = keras.layers.LSTM(encoding_dim, return_sequences=True)(decoded)
    decoded = keras.layers.Dropout(0.2)(decoded)
    decoded = keras.layers.LSTM(32, return_sequences=True)(decoded)
    decoded = keras.layers.Dropout(0.2)(decoded)
    decoded = keras.layers.LSTM(64, return_sequences=True)(decoded)
    decoded = keras.layers.TimeDistributed(keras.layers.Dense(input_shape[1]))(decoded)
    
    # Full model
    autoencoder = keras.Model(encoder_inputs, decoded)
    
    autoencoder.compile(
        optimizer=keras.optimizers.Adam(learning_rate=LEARNING_RATE),
        loss='mse'
    )
    
    print("\n📊 Autoencoder Summary:")
    autoencoder.summary()
    
    return autoencoder

# ==================== TRAINING ====================
def train_autoencoder(X_train, X_val):
    """Train the autoencoder on normal behavior data"""
    print("\n🚀 Starting autoencoder training...")
    print("   (Training only on NORMAL behavior patterns)")
    
    model = build_autoencoder(input_shape=(X_train.shape[1], X_train.shape[2]))
    
    # Callbacks
    early_stopping = keras.callbacks.EarlyStopping(
        monitor='val_loss',
        patience=15,
        restore_best_weights=True
    )
    
    reduce_lr = keras.callbacks.ReduceLROnPlateau(
        monitor='val_loss',
        factor=0.5,
        patience=7,
        min_lr=1e-6
    )
    
    checkpoint = keras.callbacks.ModelCheckpoint(
        MODELS_DIR / 'anomaly_detector_best.keras',
        monitor='val_loss',
        save_best_only=True
    )
    
    # Train
    history = model.fit(
        X_train, X_train,  # Autoencoder: input = output
        batch_size=BATCH_SIZE,
        epochs=EPOCHS,
        validation_data=(X_val, X_val),
        callbacks=[early_stopping, reduce_lr, checkpoint],
        verbose=1
    )
    
    return model, history

# ==================== THRESHOLD DETERMINATION ====================
def calculate_anomaly_threshold(model, X_train):
    """
    Calculate reconstruction error threshold for anomaly detection
    
    Threshold = mean + 2*std of reconstruction errors on training data
    """
    print("\n📏 Calculating anomaly threshold...")
    
    # Get reconstruction errors on training data
    X_train_pred = model.predict(X_train, verbose=0)
    mse = np.mean(np.square(X_train - X_train_pred), axis=(1, 2))
    
    # Calculate threshold (mean + 2 std)
    mean_mse = np.mean(mse)
    std_mse = np.std(mse)
    threshold = mean_mse + 2 * std_mse
    
    print(f"   Mean reconstruction error: {mean_mse:.6f}")
    print(f"   Std reconstruction error:  {std_mse:.6f}")
    print(f"   Anomaly threshold:         {threshold:.6f}")
    print(f"   (Sequences with error > {threshold:.6f} flagged as anomalies)")
    
    return threshold, mean_mse, std_mse

# ==================== EVALUATION ====================
def evaluate_autoencoder(model, X_test, threshold):
    """Evaluate autoencoder and visualize results"""
    print("\n📈 Evaluating model on test set...")
    
    # Predictions
    X_test_pred = model.predict(X_test, verbose=0)
    
    # Calculate errors
    mse = np.mean(np.square(X_test - X_test_pred), axis=(1, 2))
    
    # Flag anomalies
    anomalies = mse > threshold
    anomaly_rate = np.mean(anomalies) * 100
    
    print(f"\n✅ Test Results:")
    print(f"   Test sequences:     {len(X_test)}")
    print(f"   Flagged anomalies:  {np.sum(anomalies)} ({anomaly_rate:.2f}%)")
    print(f"   Max error:          {np.max(mse):.6f}")
    print(f"   Min error:          {np.min(mse):.6f}")
    
    # Visualization
    visualize_reconstruction_errors(mse, threshold)
    
    return {
        'threshold': float(threshold),
        'anomaly_rate': float(anomaly_rate),
        'max_error': float(np.max(mse)),
        'min_error': float(np.min(mse))
    }

def visualize_reconstruction_errors(errors, threshold):
    """Plot reconstruction error distribution"""
    print("\n📊 Generating visualization...")
    
    plt.figure(figsize=(12, 5))
    
    # Histogram
    plt.subplot(1, 2, 1)
    plt.hist(errors, bins=50, alpha=0.7, color='blue', edgecolor='black')
    plt.axvline(threshold, color='red', linestyle='--', linewidth=2, label=f'Threshold: {threshold:.4f}')
    plt.xlabel('Reconstruction Error (MSE)', fontsize=12)
    plt.ylabel('Frequency', fontsize=12)
    plt.title('Distribution of Reconstruction Errors', fontsize=14, fontweight='bold')
    plt.legend()
    plt.grid(alpha=0.3)
    
    # Time series
    plt.subplot(1, 2, 2)
    plt.plot(errors, alpha=0.7, label='Reconstruction Error')
    plt.axhline(threshold, color='red', linestyle='--', linewidth=2, label='Threshold')
    plt.xlabel('Sequence Index', fontsize=12)
    plt.ylabel('Reconstruction Error', fontsize=12)
    plt.title('Reconstruction Errors Over Time', fontsize=14, fontweight='bold')
    plt.legend()
    plt.grid(alpha=0.3)
    
    plt.tight_layout()
    
    # Save
    plot_path = MODELS_DIR / 'anomaly_detector_evaluation.png'
    plt.savefig(plot_path, dpi=300, bbox_inches='tight')
    print(f"   Saved visualization to {plot_path}")
    plt.close()

# ==================== MODEL SAVING ====================
def save_model(model, preprocessor, threshold, mean_mse, std_mse, metrics):
    """Save trained autoencoder and metadata"""
    print("\n💾 Saving model...")
    
    # Save Keras model
    model_path = MODELS_DIR / 'anomaly_detector_v1'
    model.save(model_path)
    print(f"   Saved model to {model_path}")
    
    # Save scaler
    import joblib
    scaler_path = PROCESSED_DATA_DIR / 'anomaly_scaler.pkl'
    joblib.dump(preprocessor.scaler, scaler_path)
    print(f"   Saved scaler to {scaler_path}")
    
    # Save metadata (including threshold)
    metadata = {
        'model_version': '1.0.0',
        'trained_date': datetime.now().isoformat(),
        'lookback_hours': LOOKBACK_HOURS,
        'encoding_dim': ENCODING_DIM,
        'anomaly_threshold': float(threshold),
        'mean_reconstruction_error': float(mean_mse),
        'std_reconstruction_error': float(std_mse),
        'metrics': metrics,
        'framework': 'TensorFlow',
        'framework_version': tf.__version__
    }
    
    metadata_path = MODELS_DIR / 'anomaly_detector_v1' / 'metadata.json'
    with open(metadata_path, 'w') as f:
        json.dump(metadata, f, indent=2)
    
    print(f"   Saved metadata to {metadata_path}")

# ==================== SYNTHETIC ANOMALY INJECTION ====================
def inject_synthetic_anomalies(df, num_anomalies=50):
    """
    Inject synthetic anomalies into dataset for testing
    
    Anomaly types:
    1. Extended inactivity
    2. Excessive nighttime activity
    3. Temperature extremes
    """
    print(f"\n🧪 Injecting {num_anomalies} synthetic anomalies...")
    
    anomaly_indices = np.random.choice(len(df) - 24, num_anomalies, replace=False)
    
    for idx in anomaly_indices:
        anomaly_type = np.random.choice(['inactivity', 'night_activity', 'temp_extreme'])
        
        if anomaly_type == 'inactivity':
            # Zero motion for 12+ hours
            df.loc[idx:idx+12, 'motionDetected_sum'] = 0
            
        elif anomaly_type == 'night_activity':
            # High motion during night (22:00-06:00)
            night_hours = df[(df['hour'].dt.hour >= 22) | (df['hour'].dt.hour <= 6)].index
            if len(night_hours) > 0:
                selected = np.random.choice(night_hours, min(8, len(night_hours)), replace=False)
                df.loc[selected, 'motionDetected_sum'] = 10
                
        elif anomaly_type == 'temp_extreme':
            # Extreme temperature for extended period
            df.loc[idx:idx+6, 'temperature_mean'] = np.random.choice([15, 35])
    
    print(f"   Injected {num_anomalies} anomalies")
    return df

# ==================== MAIN PIPELINE ====================
def main():
    """Main anomaly detection training pipeline"""
    
    # Step 1: Load preprocessed data
    print("\n" + "="*70)
    print("STEP 1: DATA LOADING")
    print("="*70)
    
    preprocessor = AnomalyDataPreprocessor()
    
    # Load hourly features from schedule predictor preprocessing
    hourly_data_path = PROCESSED_DATA_DIR / 'hourly_features.csv'
    
    if not hourly_data_path.exists():
        print(f"\n❌ Error: {hourly_data_path} not found!")
        print("   Please run train_model.py first to generate hourly_features.csv")
        return
    
    df = preprocessor.load_hourly_data(hourly_data_path)
    
    # Step 2: Feature engineering
    print("\n" + "="*70)
    print("STEP 2: FEATURE ENGINEERING")
    print("="*70)
    
    df = preprocessor.create_anomaly_features(df)
    
    # Optional: Inject synthetic anomalies for validation
    # df = inject_synthetic_anomalies(df, num_anomalies=50)
    
    # Step 3: Create sequences
    X, feature_cols = preprocessor.create_sequences(df, LOOKBACK_HOURS)
    
    # Step 4: Split data (only use "normal" data for training)
    print("\n📊 Splitting data...")
    X_train, X_temp = train_test_split(X, test_size=0.3, random_state=42)
    X_val, X_test = train_test_split(X_temp, test_size=0.5, random_state=42)
    
    print(f"   Training set:   {len(X_train)} sequences")
    print(f"   Validation set: {len(X_val)} sequences")
    print(f"   Test set:       {len(X_test)} sequences")
    
    # Step 5: Train autoencoder
    print("\n" + "="*70)
    print("STEP 3: AUTOENCODER TRAINING")
    print("="*70)
    
    model, history = train_autoencoder(X_train, X_val)
    
    # Step 6: Calculate threshold
    threshold, mean_mse, std_mse = calculate_anomaly_threshold(model, X_train)
    
    # Step 7: Evaluate
    print("\n" + "="*70)
    print("STEP 4: MODEL EVALUATION")
    print("="*70)
    
    metrics = evaluate_autoencoder(model, X_test, threshold)
    
    # Step 8: Save
    print("\n" + "="*70)
    print("STEP 5: MODEL EXPORT")
    print("="*70)
    
    save_model(model, preprocessor, threshold, mean_mse, std_mse, metrics)
    
    print("\n" + "="*70)
    print("✅ TRAINING COMPLETE!")
    print("="*70)
    print(f"\nAnomaly detection threshold: {threshold:.6f}")
    print(f"\nNext steps:")
    print(f"1. Run conversion script: python scripts/convert_tflite.py")
    print(f"2. Deploy to Firebase: python scripts/deploy_model.py")
    print(f"3. Integrate with Flutter app for real-time monitoring")

if __name__ == "__main__":
    main()