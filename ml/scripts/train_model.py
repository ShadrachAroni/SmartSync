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

try:
    import psutil  # type: ignore
except ImportError:  # pragma: no cover - optional dependency
    psutil = None

try:
    import GPUtil  # type: ignore
except ImportError:  # pragma: no cover - optional dependency
    GPUtil = None

# ==================== CONFIGURATION ====================
PROJECT_ROOT = Path(__file__).parent.parent
DATA_DIR = PROJECT_ROOT / "data"
RAW_DATA_DIR = DATA_DIR / "raw"
PROCESSED_DATA_DIR = DATA_DIR / "processed"
MODELS_DIR = PROJECT_ROOT / "models" / "saved_models"
TFLITE_DIR = PROJECT_ROOT / "models" / "tflite"
BEST_MODEL_PATH = MODELS_DIR / "schedule_predictor_best.keras"
CHECKPOINT_WEIGHTS_PATH = MODELS_DIR / "schedule_predictor_latest.weights.h5"
TRAINING_STATE_PATH = MODELS_DIR / "schedule_predictor_state.json"

# Create directories
for dir_path in [RAW_DATA_DIR, PROCESSED_DATA_DIR, MODELS_DIR, TFLITE_DIR]:
    dir_path.mkdir(parents=True, exist_ok=True)

# Model hyperparameters
SEQUENCE_LENGTH = 168  # 1 week of hourly data
BATCH_SIZE = 32
EPOCHS = 50
LEARNING_RATE = 0.001
VALIDATION_SPLIT = 0.2

# Regularization hyperparameters
L2_REGULARIZATION = 1e-4  # L2 weight regularization to prevent overfitting
DROPOUT_RATE_LSTM = 0.4  # Increased dropout for LSTM layers
DROPOUT_RATE_DENSE = 0.3  # Dropout for dense layers
GRADIENT_CLIP_NORM = 1.0  # Gradient clipping to prevent exploding gradients

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
    Build LSTM-based schedule prediction model with comprehensive regularization
    
    Architecture improvements to prevent overfitting/underfitting:
    - Reduced LSTM units to prevent overfitting
    - Batch normalization for stable training
    - L2 regularization on all layers
    - Increased dropout rates
    - Proper weight initialization
    """
    print("\n🏗️  Building model architecture with regularization...")
    
    # L2 regularizer for all layers
    l2_reg = keras.regularizers.l2(L2_REGULARIZATION)
    
    model = keras.Sequential([
        # Input layer
        keras.layers.Input(shape=input_shape),
        
        # First LSTM layer with regularization
        keras.layers.LSTM(
            96,  # Reduced from 128 to prevent overfitting
            return_sequences=True,
            kernel_regularizer=l2_reg,
            recurrent_regularizer=l2_reg,
            bias_regularizer=l2_reg,
            kernel_initializer='glorot_uniform',
            recurrent_initializer='orthogonal'
        ),
        keras.layers.BatchNormalization(),  # Stabilize activations
        keras.layers.Dropout(DROPOUT_RATE_LSTM),
        
        # Second LSTM layer with regularization
        keras.layers.LSTM(
            48,  # Reduced from 64 to prevent overfitting
            return_sequences=False,
            kernel_regularizer=l2_reg,
            recurrent_regularizer=l2_reg,
            bias_regularizer=l2_reg,
            kernel_initializer='glorot_uniform',
            recurrent_initializer='orthogonal'
        ),
        keras.layers.BatchNormalization(),
        keras.layers.Dropout(DROPOUT_RATE_LSTM),
        
        # Dense layers with regularization
        keras.layers.Dense(
            32,
            activation='relu',
            kernel_regularizer=l2_reg,
            bias_regularizer=l2_reg,
            kernel_initializer='he_normal'
        ),
        keras.layers.BatchNormalization(),
        keras.layers.Dropout(DROPOUT_RATE_DENSE),
        
        # Additional smaller dense layer for better feature extraction
        keras.layers.Dense(
            16,
            activation='relu',
            kernel_regularizer=l2_reg,
            bias_regularizer=l2_reg,
            kernel_initializer='he_normal'
        ),
        keras.layers.BatchNormalization(),
        keras.layers.Dropout(DROPOUT_RATE_DENSE * 0.5),  # Less dropout before output
        
        # Output layer (predict fan speed & LED brightness)
        keras.layers.Dense(
            output_dim,
            activation='sigmoid',
            kernel_regularizer=l2_reg,
            bias_regularizer=l2_reg
        )
    ])
    
    # Optimizer with gradient clipping
    optimizer = keras.optimizers.Adam(
        learning_rate=LEARNING_RATE,
        clipnorm=GRADIENT_CLIP_NORM  # Prevent exploding gradients
    )
    
    model.compile(
        optimizer=optimizer,
        loss='mse',
        metrics=['mae']
    )
    
    print("\n📊 Model Summary:")
    model.summary()
    print(f"\n✅ Regularization applied:")
    print(f"   - L2 regularization: {L2_REGULARIZATION}")
    print(f"   - LSTM dropout: {DROPOUT_RATE_LSTM}")
    print(f"   - Dense dropout: {DROPOUT_RATE_DENSE}")
    print(f"   - Gradient clipping: {GRADIENT_CLIP_NORM}")
    print(f"   - Batch normalization: Enabled")
    
    return model

# ==================== TRAINING ====================
class OverfittingMonitor(keras.callbacks.Callback):
    """Monitor training/validation gap to detect overfitting early"""
    def __init__(self, gap_threshold=0.15):
        super().__init__()
        self.gap_threshold = gap_threshold
        self.best_gap = float('inf')
        
    def on_epoch_end(self, epoch, logs=None):
        if logs is None:
            return
        
        train_loss = logs.get('loss', 0)
        val_loss = logs.get('val_loss', 0)
        
        if val_loss > 0:
            gap = abs(train_loss - val_loss) / val_loss
            self.best_gap = min(self.best_gap, gap)
            
            # Warn if gap is too large (overfitting)
            if gap > self.gap_threshold:
                print(f"\n⚠️  Warning: Large train/val gap detected ({gap:.2%}). Possible overfitting.")
            
            # Warn if validation loss is much higher (overfitting)
            if val_loss > train_loss * 1.5:
                print(f"⚠️  Warning: Validation loss ({val_loss:.4f}) >> Training loss ({train_loss:.4f})")
            
            # Warn if both losses are high and similar (underfitting)
            if epoch > 5 and train_loss > 0.5 and val_loss > 0.5:
                if abs(train_loss - val_loss) / max(train_loss, val_loss) < 0.1:
                    print(f"⚠️  Warning: High and similar losses detected. Model may be underfitting.")


class TrainingStateSaver(keras.callbacks.Callback):
    """
    Persist lightweight training metadata so long-running jobs
    can be resumed after interruptions.
    """

    def __init__(self, state_path=TRAINING_STATE_PATH):
        super().__init__()
        self.state_path = Path(state_path)

    def on_epoch_end(self, epoch, logs=None):
        logs = logs or {}
        state = {
            "last_epoch": int(epoch + 1),
            "updated_at": datetime.now().isoformat(),
            "learning_rate": float(tf.keras.backend.get_value(self.model.optimizer.learning_rate)),
            "loss": float(logs.get("loss", 0.0)),
            "val_loss": float(logs.get("val_loss", 0.0)),
            "val_mae": float(logs.get("val_mae", logs.get("mae", 0.0))),
            "status": "in_progress"
        }
        self.state_path.parent.mkdir(parents=True, exist_ok=True)
        with self.state_path.open("w", encoding="utf-8") as fp:
            json.dump(state, fp, indent=2)


class ResourceMonitorCallback(keras.callbacks.Callback):
    """
    Observe system resources during training and adjust optimizer
    hyperparameters when headroom gets tight.
    """

    def __init__(
        self,
        log_every=1,
        min_free_gpu_mb=1024,
        min_free_ram_mb=2048,
        lr_floor=1e-6,
        cooldown_epochs=1
    ):
        super().__init__()
        self.log_every = log_every
        self.min_free_gpu_mb = min_free_gpu_mb
        self.min_free_ram_mb = min_free_ram_mb
        self.lr_floor = lr_floor
        self.cooldown_epochs = cooldown_epochs
        self._last_adjustment_epoch = -cooldown_epochs

    def on_epoch_begin(self, epoch, logs=None):
        if epoch % self.log_every != 0:
            return

        snapshot = self._capture_snapshot()
        self._log_snapshot(epoch, snapshot)
        self._maybe_optimize(epoch, snapshot)

    def _capture_snapshot(self):
        snapshot = {
            "cpu_percent": None,
            "ram_percent": None,
            "ram_available_mb": None,
            "gpu_free_mb": None,
            "gpu_util": None,
        }

        if psutil:
            snapshot["cpu_percent"] = psutil.cpu_percent(interval=None)
            ram_info = psutil.virtual_memory()
            snapshot["ram_percent"] = ram_info.percent
            snapshot["ram_available_mb"] = ram_info.available / (1024 ** 2)

        if GPUtil:
            gpus = GPUtil.getGPUs()
            if gpus:
                gpu = gpus[0]
                snapshot["gpu_free_mb"] = gpu.memoryFree
                snapshot["gpu_util"] = gpu.load * 100

        return snapshot

    def _log_snapshot(self, epoch, snapshot):
        parts = [f"Epoch {epoch + 1} resource check:"]
        if snapshot["cpu_percent"] is not None:
            parts.append(f"CPU {snapshot['cpu_percent']:.1f}%")
        if snapshot["ram_percent"] is not None:
            parts.append(
                f"RAM {snapshot['ram_percent']:.1f}% (free {snapshot['ram_available_mb']:.0f} MB)"
            )
        if snapshot["gpu_free_mb"] is not None:
            util = snapshot["gpu_util"]
            util_txt = f"{util:.1f}%" if util is not None else "n/a"
            parts.append(f"GPU free {snapshot['gpu_free_mb']:.0f} MB (util {util_txt})")

        print("   " + " | ".join(parts))

    def _maybe_optimize(self, epoch, snapshot):
        if epoch - self._last_adjustment_epoch < self.cooldown_epochs:
            return

        lr = float(tf.keras.backend.get_value(self.model.optimizer.learning_rate))
        adjusted = False

        if snapshot["gpu_free_mb"] is not None and snapshot["gpu_free_mb"] < self.min_free_gpu_mb:
            new_lr = max(self.lr_floor, lr * 0.8)
            if new_lr < lr:
                tf.keras.backend.set_value(self.model.optimizer.learning_rate, new_lr)
                print(f"   🔧 Reduced learning rate to {new_lr:.2e} due to low GPU memory headroom.")
                adjusted = True

        if snapshot["ram_available_mb"] is not None and snapshot["ram_available_mb"] < self.min_free_ram_mb:
            new_lr = max(self.lr_floor, lr * 0.9)
            if new_lr < lr:
                tf.keras.backend.set_value(self.model.optimizer.learning_rate, new_lr)
                print(f"   🔧 Reduced learning rate to {new_lr:.2e} due to low RAM.")
                adjusted = True

        if adjusted:
            self._last_adjustment_epoch = epoch


def load_training_checkpoint(model, checkpoint_path=CHECKPOINT_WEIGHTS_PATH, state_path=TRAINING_STATE_PATH):
    """
    Load the latest checkpoint if it exists and return the epoch to resume from.
    Handles LossScaleOptimizer compatibility issues with mixed precision training.
    """
    resume_epoch = 0

    if Path(checkpoint_path).exists():
        try:
            # Load weights only (checkpoint should be saved with save_weights_only=True)
            model.load_weights(str(checkpoint_path))
            print(f"\n🔁 Loaded weights from {checkpoint_path}")
        except (AttributeError, ValueError, TypeError, OSError) as exc:
            # Handle optimizer-related errors (common with mixed precision + version differences)
            error_str = str(exc).lower()
            if "lossscaleoptimizer" in error_str or ("name" in error_str and "attribute" in error_str):
                try:
                    # Fallback: Load with by_name to match layer names only, skip mismatches
                    model.load_weights(str(checkpoint_path), by_name=True, skip_mismatch=True)
                    print(f"\n🔁 Loaded weights from {checkpoint_path} (optimizer metadata skipped)")
                except Exception as exc2:
                    print(f"\n⚠️  Could not load checkpoint ({exc2}). Starting from scratch.")
                    return resume_epoch
            else:
                print(f"\n⚠️  Could not load checkpoint ({exc}). Starting from scratch.")
                return resume_epoch
        except Exception as exc:
            print(f"\n⚠️  Could not load checkpoint ({exc}). Starting from scratch.")
            return resume_epoch

        if Path(state_path).exists():
            with open(state_path, "r", encoding="utf-8") as fp:
                state = json.load(fp)
            resume_epoch = int(state.get("last_epoch", 0))
            print(f"   Resuming training from epoch {resume_epoch + 1}")

    return resume_epoch

def train_model(X_train, y_train, X_val, y_val, resume=True):
    """Train the schedule prediction model with enhanced regularization"""
    print("\n🚀 Starting model training with anti-overfitting measures...")
    
    model = build_schedule_predictor(input_shape=(X_train.shape[1], X_train.shape[2]))
    
    initial_epoch = 0
    if resume:
        initial_epoch = load_training_checkpoint(model)
        if initial_epoch >= EPOCHS:
            print("   ✅ Existing checkpoint already reached configured epochs. Running a final consolidation epoch for safety.")
            initial_epoch = max(0, EPOCHS - 1)

    # Enhanced callbacks for better training control
    early_stopping = keras.callbacks.EarlyStopping(
        monitor='val_loss',
        patience=8,  # Reduced from 10 for faster stopping when overfitting
        restore_best_weights=True,
        min_delta=1e-5,  # Minimum change to qualify as improvement
        verbose=1
    )
    
    reduce_lr = keras.callbacks.ReduceLROnPlateau(
        monitor='val_loss',
        factor=0.5,
        patience=4,  # Reduced from 5 for more aggressive LR reduction
        min_lr=1e-7,  # Lower minimum LR
        verbose=1,
        cooldown=2  # Wait 2 epochs before reducing LR again
    )
    
    # Learning rate schedule
    lr_schedule = keras.callbacks.LearningRateScheduler(
        lambda epoch: LEARNING_RATE * (0.95 ** epoch),  # Gradual decay
        verbose=0
    )
    
    checkpoint = keras.callbacks.ModelCheckpoint(
        BEST_MODEL_PATH,
        monitor='val_loss',
        save_best_only=True,
        verbose=1
    )

    latest_checkpoint = keras.callbacks.ModelCheckpoint(
        CHECKPOINT_WEIGHTS_PATH,
        monitor='val_loss',
        save_best_only=False,
        save_weights_only=True,
        verbose=0
    )
    
    # Overfitting monitor
    overfitting_monitor = OverfittingMonitor(gap_threshold=0.15)
    resource_monitor = ResourceMonitorCallback()
    state_saver = TrainingStateSaver()
    
    # Train with all callbacks
    history = model.fit(
        X_train, y_train,
        batch_size=BATCH_SIZE,
        epochs=EPOCHS,
        validation_data=(X_val, y_val),
        callbacks=[
            early_stopping,
            reduce_lr,
            lr_schedule,
            checkpoint,
            latest_checkpoint,
            overfitting_monitor,
            resource_monitor,
            state_saver
        ],
        verbose=1,
        shuffle=True,  # Shuffle training data each epoch
        initial_epoch=initial_epoch
    )
    
    # Print training diagnostics
    print("\n📊 Training Diagnostics:")
    final_train_loss = history.history['loss'][-1]
    final_val_loss = history.history['val_loss'][-1]
    gap = abs(final_train_loss - final_val_loss) / final_val_loss if final_val_loss > 0 else 0
    
    print(f"   Final training loss: {final_train_loss:.4f}")
    print(f"   Final validation loss: {final_val_loss:.4f}")
    print(f"   Train/Val gap: {gap:.2%}")
    
    if gap < 0.05:
        print("   ✅ Good generalization (low gap)")
    elif gap < 0.15:
        print("   ⚠️  Moderate gap - monitor for overfitting")
    else:
        print("   ❌ Large gap - possible overfitting detected")
    
    if final_val_loss < final_train_loss * 0.9:
        print("   ✅ Validation loss lower than training - good sign!")
    elif final_val_loss > final_train_loss * 1.2:
        print("   ⚠️  Validation loss much higher - possible overfitting")
    
    final_epoch = initial_epoch + len(history.history['loss'])
    completion_state = {
        "last_epoch": int(final_epoch),
        "completed_at": datetime.now().isoformat(),
        "status": "completed"
    }
    try:
        with open(TRAINING_STATE_PATH, "w", encoding="utf-8") as fp:
            json.dump(completion_state, fp, indent=2)
    except OSError:
        pass
    
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

    # Clear transient training state once artifacts are persisted
    try:
        TRAINING_STATE_PATH.unlink()
    except FileNotFoundError:
        pass

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
    
    model, history = train_model(X_train, y_train, X_val, y_val, resume=True)
    
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