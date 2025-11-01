#!/usr/bin/env python3
"""
SmartSync Schedule Predictor Training Script

This script trains a neural network to predict optimal device schedules
based on historical user behavior patterns.

Training Data Sources:
1. Firebase Firestore (sensor_logs, logs collections)
2. Kaggle: Smart Home Dataset - https://www.kaggle.com/datasets/taranvee/smart-home-dataset-with-weather-information
3. UCI ML Repository: Smart Home Dataset - https://archive.ics.uci.edu/dataset/196/smart+home+dataset
4. Open Smart Home Dataset - https://github.com/stanford-oval/home-assistant-datasets
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
import firebase_admin
from firebase_admin import credentials, firestore
import warnings
warnings.filterwarnings('ignore')

# ==================== CONFIGURATION ====================
PROJECT_ROOT = Path(__file__).parent.parent
DATA_DIR = PROJECT_ROOT / "data"
RAW_DATA_DIR = DATA_DIR / "raw"
PROCESSED_DATA_DIR = DATA_DIR / "processed"
MODELS_DIR = PROJECT_ROOT / "models" / "saved_models"
TFLITE_DIR = PROJECT_ROOT / "models" / "tflite"

# Create directories
for dir_path in [RAW_DATA_DIR, PROCESSED_DATA_DIR, MODELS_DIR, TFLITE_DIR]:
    dir_path.mkdir(parents=True, exist_ok=True)

# Model hyperparameters
SEQUENCE_LENGTH = 168  # 1 week of hourly data
BATCH_SIZE = 32
EPOCHS = 50
LEARNING_RATE = 0.001
VALIDATION_SPLIT = 0.2

print("=" * 70)
print("SmartSync Schedule Predictor - Training Pipeline")
print("=" * 70)

# ==================== DATA COLLECTION ====================
class FirebaseDataCollector:
    """Collect training data from Firebase Firestore"""
    
    def __init__(self, credentials_path='serviceAccountKey.json'):
        """Initialize Firebase connection"""
        if not firebase_admin._apps:
            cred = credentials.Certificate(credentials_path)
            firebase_admin.initialize_app(cred)
        self.db = firestore.client()
        print("\n✅ Firebase connection established")
    
    def collect_sensor_logs(self, user_id, days=90):
        """
        Collect sensor logs for a user from the last N days
        
        Args:
            user_id: Firebase user ID
            days: Number of days of historical data
        
        Returns:
            DataFrame with sensor readings
        """
        print(f"\n📥 Collecting {days} days of sensor data for user {user_id[:8]}...")
        
        cutoff_date = datetime.now() - timedelta(days=days)
        
        # Query Firestore
        logs_ref = self.db.collection('sensor_logs')
        query = logs_ref.where('userId', '==', user_id) \
                       .where('timestamp', '>=', cutoff_date) \
                       .order_by('timestamp')
        
        docs = query.stream()
        
        data = []
        for doc in docs:
            log = doc.to_dict()
            data.append({
                'timestamp': log['timestamp'],
                'temperature': log['temperature'],
                'humidity': log['humidity'],
                'fanSpeed': log['fanSpeed'],
                'ledBrightness': log['ledBrightness'],
                'motionDetected': int(log['motionDetected']),
                'distance': log.get('distance', 0)
            })
        
        df = pd.DataFrame(data)
        print(f"   Collected {len(df)} records")
        return df
    
    def collect_action_logs(self, user_id, days=90):
        """Collect user action logs (manual device controls)"""
        print(f"\n📥 Collecting action logs...")
        
        cutoff_date = datetime.now() - timedelta(days=days)
        
        logs_ref = self.db.collection('logs')
        query = logs_ref.where('userId', '==', user_id) \
                       .where('eventType', '==', 'action') \
                       .where('timestamp', '>=', cutoff_date)
        
        docs = query.stream()
        
        actions = []
        for doc in docs:
            log = doc.to_dict()
            actions.append({
                'timestamp': log['timestamp'],
                'event': log['event'],
                'data': log.get('data', {})
            })
        
        df = pd.DataFrame(actions)
        print(f"   Collected {len(df)} action records")
        return df

# ==================== DATA PREPROCESSING ====================
class DataPreprocessor:
    """Preprocess raw data for model training"""
    
    def __init__(self):
        self.scaler = StandardScaler()
    
    def create_hourly_features(self, sensor_df, action_df):
        """
        Create hourly aggregated features from raw data
        
        Features per hour:
        - avg_temperature, max_temperature, min_temperature
        - avg_humidity
        - total_motion_events
        - avg_distance
        - fan_usage_minutes (how long fan was on)
        - led_usage_minutes (how long LED was on)
        - manual_actions_count
        """
        print("\n🔧 Creating hourly feature aggregations...")
        
        # Convert timestamps to datetime
        sensor_df['datetime'] = pd.to_datetime(sensor_df['timestamp'])
        sensor_df['hour'] = sensor_df['datetime'].dt.floor('H')
        
        # Aggregate sensor data by hour
        hourly_sensors = sensor_df.groupby('hour').agg({
            'temperature': ['mean', 'max', 'min'],
            'humidity': 'mean',
            'motionDetected': 'sum',
            'distance': 'mean',
            'fanSpeed': lambda x: (x > 0).sum() * 10,  # Minutes fan was on
            'ledBrightness': lambda x: (x > 0).sum() * 10  # Minutes LED was on
        }).reset_index()
        
        # Flatten column names
        hourly_sensors.columns = ['_'.join(col).strip('_') for col in hourly_sensors.columns]
        hourly_sensors.rename(columns={'hour_': 'hour'}, inplace=True)
        
        # Process action logs
        if not action_df.empty:
            action_df['datetime'] = pd.to_datetime(action_df['timestamp'])
            action_df['hour'] = action_df['datetime'].dt.floor('H')
            
            hourly_actions = action_df.groupby('hour').size().reset_index(name='manual_actions')
            
            # Merge
            hourly_data = hourly_sensors.merge(hourly_actions, on='hour', how='left')
        else:
            hourly_data = hourly_sensors
            hourly_data['manual_actions'] = 0
        
        hourly_data['manual_actions'].fillna(0, inplace=True)
        
        print(f"   Created {len(hourly_data)} hourly records")
        return hourly_data
    
    def add_temporal_features(self, df):
        """Add time-based features (hour, day of week, weekend, etc.)"""
        print("\n🕐 Adding temporal features...")
        
        df['hour_of_day'] = df['hour'].dt.hour
        df['day_of_week'] = df['hour'].dt.dayofweek
        df['is_weekend'] = (df['day_of_week'] >= 5).astype(int)
        df['is_night'] = ((df['hour_of_day'] >= 22) | (df['hour_of_day'] <= 6)).astype(int)
        
        # Cyclical encoding for hour and day
        df['hour_sin'] = np.sin(2 * np.pi * df['hour_of_day'] / 24)
        df['hour_cos'] = np.cos(2 * np.pi * df['hour_of_day'] / 24)
        df['day_sin'] = np.sin(2 * np.pi * df['day_of_week'] / 7)
        df['day_cos'] = np.cos(2 * np.pi * df['day_of_week'] / 7)
        
        return df
    
    def create_sequences(self, df, sequence_length=168):
        """
        Create sequences for LSTM training
        
        Args:
            df: Hourly feature dataframe
            sequence_length: Number of hours in each sequence (default 168 = 1 week)
        
        Returns:
            X: Input sequences (features)
            y: Target labels (device usage in next hour)
        """
        print(f"\n📦 Creating sequences of length {sequence_length}...")
        
        # Select feature columns
        feature_cols = [
            'temperature_mean', 'temperature_max', 'temperature_min',
            'humidity_mean', 'motionDetected_sum', 'distance_mean',
            'hour_sin', 'hour_cos', 'day_sin', 'day_cos',
            'is_weekend', 'is_night', 'manual_actions'
        ]
        
        # Target: fan and LED usage in next hour
        target_cols = ['fanSpeed_<lambda>', 'ledBrightness_<lambda>']
        
        # Normalize features
        features = df[feature_cols].values
        features_normalized = self.scaler.fit_transform(features)
        
        targets = df[target_cols].values
        
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
        
        return X, y, feature_cols

# ==================== MODEL ARCHITECTURE ====================
def build_schedule_predictor(input_shape, output_dim=2):
    """
    Build LSTM-based schedule prediction model
    
    Architecture:
    - LSTM layers for temporal pattern learning
    - Dropout for regularization
    - Dense output for regression (device usage prediction)
    """
    print("\n🏗️  Building model architecture...")
    
    model = keras.Sequential([
        # Input layer
        keras.layers.Input(shape=input_shape),
        
        # LSTM layers
        keras.layers.LSTM(128, return_sequences=True),
        keras.layers.Dropout(0.3),
        
        keras.layers.LSTM(64, return_sequences=False),
        keras.layers.Dropout(0.2),
        
        # Dense layers
        keras.layers.Dense(32, activation='relu'),
        keras.layers.Dropout(0.2),
        
        # Output layer (predict fan speed & LED brightness)
        keras.layers.Dense(output_dim, activation='sigmoid')
    ])
    
    model.compile(
        optimizer=keras.optimizers.Adam(learning_rate=LEARNING_RATE),
        loss='mse',
        metrics=['mae']
    )
    
    print("\n📊 Model Summary:")
    model.summary()
    
    return model

# ==================== TRAINING ====================
def train_model(X_train, y_train, X_val, y_val):
    """Train the schedule prediction model"""
    print("\n🚀 Starting model training...")
    
    model = build_schedule_predictor(input_shape=(X_train.shape[1], X_train.shape[2]))
    
    # Callbacks
    early_stopping = keras.callbacks.EarlyStopping(
        monitor='val_loss',
        patience=10,
        restore_best_weights=True
    )
    
    reduce_lr = keras.callbacks.ReduceLROnPlateau(
        monitor='val_loss',
        factor=0.5,
        patience=5,
        min_lr=1e-6
    )
    
    checkpoint = keras.callbacks.ModelCheckpoint(
        MODELS_DIR / 'schedule_predictor_best.keras',
        monitor='val_loss',
        save_best_only=True
    )
    
    # Train
    history = model.fit(
        X_train, y_train,
        batch_size=BATCH_SIZE,
        epochs=EPOCHS,
        validation_data=(X_val, y_val),
        callbacks=[early_stopping, reduce_lr, checkpoint],
        verbose=1
    )
    
    return model, history

# ==================== EVALUATION ====================
def evaluate_model(model, X_test, y_test):
    """Evaluate model performance"""
    print("\n📈 Evaluating model...")
    
    # Predictions
    y_pred = model.predict(X_test)
    
    # Metrics
    from sklearn.metrics import mean_absolute_error, mean_squared_error, r2_score
    
    mae = mean_absolute_error(y_test, y_pred)
    mse = mean_squared_error(y_test, y_pred)
    rmse = np.sqrt(mse)
    r2 = r2_score(y_test, y_pred)
    
    print(f"\n✅ Test Results:")
    print(f"   MAE:  {mae:.4f}")
    print(f"   RMSE: {rmse:.4f}")
    print(f"   R²:   {r2:.4f}")
    
    return {
        'mae': float(mae),
        'rmse': float(rmse),
        'r2': float(r2)
    }

# ==================== MODEL SAVING ====================
def save_model(model, preprocessor, metrics):
    """Save trained model and metadata"""
    print("\n💾 Saving model...")
    
    # Save Keras model
    model_path = MODELS_DIR / 'schedule_predictor_v1'
    model.save(model_path)
    print(f"   Saved Keras model to {model_path}")
    
    # Save scaler
    import joblib
    scaler_path = PROCESSED_DATA_DIR / 'scaler.pkl'
    joblib.dump(preprocessor.scaler, scaler_path)
    print(f"   Saved scaler to {scaler_path}")
    
    # Save metadata
    metadata = {
        'model_version': '1.0.0',
        'trained_date': datetime.now().isoformat(),
        'sequence_length': SEQUENCE_LENGTH,
        'metrics': metrics,
        'framework': 'TensorFlow',
        'framework_version': tf.__version__
    }
    
    metadata_path = MODELS_DIR / 'schedule_predictor_v1' / 'metadata.json'
    with open(metadata_path, 'w') as f:
        json.dump(metadata, f, indent=2)
    
    print(f"   Saved metadata to {metadata_path}")

# ==================== MAIN PIPELINE ====================
def main():
    """Main training pipeline"""
    
    # Step 1: Collect data from Firebase
    print("\n" + "="*70)
    print("STEP 1: DATA COLLECTION")
    print("="*70)
    
    # OPTION A: Use Firebase data
    try:
        collector = FirebaseDataCollector('path/to/serviceAccountKey.json')
        
        # Replace with actual user ID from your Firebase
        user_id = 'YOUR_USER_ID_HERE'
        
        sensor_df = collector.collect_sensor_logs(user_id, days=90)
        action_df = collector.collect_action_logs(user_id, days=90)
        
        # Save raw data
        sensor_df.to_csv(RAW_DATA_DIR / 'sensor_logs.csv', index=False)
        action_df.to_csv(RAW_DATA_DIR / 'action_logs.csv', index=False)
        
    except Exception as e:
        print(f"\n⚠️  Firebase collection failed: {e}")
        print("   Using synthetic data for demonstration...")
        
        # OPTION B: Generate synthetic data for demonstration
        sensor_df = generate_synthetic_sensor_data(days=90)
        action_df = generate_synthetic_action_data(days=90)
    
    # Step 2: Preprocess data
    print("\n" + "="*70)
    print("STEP 2: DATA PREPROCESSING")
    print("="*70)
    
    preprocessor = DataPreprocessor()
    
    hourly_df = preprocessor.create_hourly_features(sensor_df, action_df)
    hourly_df = preprocessor.add_temporal_features(hourly_df)
    
    # Save processed data
    hourly_df.to_csv(PROCESSED_DATA_DIR / 'hourly_features.csv', index=False)
    
    # Step 3: Create sequences
    X, y, feature_cols = preprocessor.create_sequences(hourly_df, SEQUENCE_LENGTH)
    
    # Step 4: Split data
    print("\n📊 Splitting data...")
    X_train, X_temp, y_train, y_temp = train_test_split(X, y, test_size=0.3, random_state=42)
    X_val, X_test, y_val, y_test = train_test_split(X_temp, y_temp, test_size=0.5, random_state=42)
    
    print(f"   Training set:   {len(X_train)} samples")
    print(f"   Validation set: {len(X_val)} samples")
    print(f"   Test set:       {len(X_test)} samples")
    
    # Step 5: Train model
    print("\n" + "="*70)
    print("STEP 3: MODEL TRAINING")
    print("="*70)
    
    model, history = train_model(X_train, y_train, X_val, y_val)
    
    # Step 6: Evaluate
    print("\n" + "="*70)
    print("STEP 4: MODEL EVALUATION")
    print("="*70)
    
    metrics = evaluate_model(model, X_test, y_test)
    
    # Step 7: Save
    print("\n" + "="*70)
    print("STEP 5: MODEL EXPORT")
    print("="*70)
    
    save_model(model, preprocessor, metrics)
    
    print("\n" + "="*70)
    print("✅ TRAINING COMPLETE!")
    print("="*70)
    print(f"\nNext steps:")
    print(f"1. Run conversion script: python scripts/convert_tflite.py")
    print(f"2. Deploy to Firebase: python scripts/deploy_model.py")
    print(f"3. Integrate with Flutter app")

# ==================== SYNTHETIC DATA GENERATOR ====================
def generate_synthetic_sensor_data(days=90):
    """Generate synthetic sensor data for demonstration"""
    print("\n🧪 Generating synthetic sensor data...")
    
    hours = days * 24
    timestamps = [datetime.now() - timedelta(hours=i) for i in range(hours, 0, -1)]
    
    data = []
    for ts in timestamps:
        hour = ts.hour
        
        # Realistic patterns
        temp = 22 + 3 * np.sin(2 * np.pi * hour / 24) + np.random.normal(0, 1)
        humidity = 55 + 10 * np.sin(2 * np.pi * hour / 24) + np.random.normal(0, 3)
        motion = 1 if (6 <= hour <= 23) and np.random.random() > 0.7 else 0
        fan = int(255 * (temp - 20) / 10) if temp > 24 else 0
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
    
    return pd.DataFrame(data)

def generate_synthetic_action_data(days=90):
    """Generate synthetic action logs"""
    actions = []
    
    for i in range(days * 5):  # ~5 actions per day
        ts = datetime.now() - timedelta(hours=np.random.randint(0, days * 24))
        actions.append({
            'timestamp': ts,
            'event': np.random.choice(['fan_control', 'led_control']),
            'data': {}
        })
    
    return pd.DataFrame(actions)

if __name__ == "__main__":
    main()