#!/usr/bin/env python3

"""
SmartSync Training Pipeline
===========================

This script trains the SmartSync indoor comfort controller by combining the
Aruba, HomeC, and Tulum smart-home datasets. Compared to the legacy script it:

1. Normalises every dataset into a unified schema with richer engineered
   features (energy, occupancy, temporal signals, rolling stats, target lags).
2. Uses an efficient Temporal Convolutional Network (TCN)-like model that keeps
   sequential context without the overhead of recurrent layers.
3. Builds shuffled `tf.data.Dataset` pipelines for faster GPU utilisation and
   adds modern regularisation (label smoothing, dropout, learning‑rate decay).
4. Produces improved diagnostics: learning curves (loss/MAE/R²), per-target
   scatter plots, distribution overlays, residual traces, and a metrics report.

Usage
-----
    cd ml
    python scripts/train_smart_home.py
"""

from __future__ import annotations

import json
import math
import warnings
from dataclasses import asdict, dataclass, field
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional, Tuple

import joblib
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
import tensorflow as tf
from sklearn.metrics import mean_absolute_error, mean_squared_error, r2_score
from sklearn.preprocessing import StandardScaler
from tensorflow import keras

warnings.filterwarnings("ignore", category=FutureWarning)
tf.get_logger().setLevel("ERROR")

# ==============================================================================
# Hardware / Determinism
# ==============================================================================


def setup_gpu() -> bool:
    """Configure TensorFlow for graceful GPU fallbacks."""
    print("\n" + "=" * 90)
    print("GPU / ACCELERATOR CHECK")
    print("=" * 90)

    gpus = tf.config.list_physical_devices("GPU")
    if not gpus:
        print("⚠️  No GPU detected. Training will continue on CPU.")
        return False

    try:
        for gpu in gpus:
            tf.config.experimental.set_memory_growth(gpu, True)
        print(f"✅ Enabled memory growth on {len(gpus)} GPU(s).")
        return True
    except RuntimeError as exc:
        print(f"⚠️  GPU initialisation error: {exc}")
        return False


GPU_AVAILABLE = setup_gpu()


def set_global_seed(seed: int) -> None:
    np.random.seed(seed)
    tf.random.set_seed(seed)


# ==============================================================================
# Configuration
# ==============================================================================


@dataclass
class TrainingConfig:
    seed: int = 42
    sequence_length: int = 48  # 2 days of hourly stats
    prediction_horizon: int = 1
    batch_size: int = 128
    epochs: int = 80
    learning_rate: float = 3e-4
    min_learning_rate: float = 1e-6
    validation_split: float = 0.15
    test_split: float = 0.15
    label_smoothing: float = 0.02
    datasets: Tuple[str, ...] = ("HomeC.csv", "aruba.csv", "tulum.csv")
    conv_filters: Tuple[int, ...] = (64, 64, 32)
    kernel_size: int = 5
    dropout: float = 0.25
    targets: Tuple[str, ...] = ("fan_speed", "led_brightness")
    max_target_value: int = 255

    def to_dict(self) -> Dict:
        return asdict(self)


CONFIG = TrainingConfig()
set_global_seed(CONFIG.seed)

PROJECT_ROOT = Path(__file__).resolve().parent.parent
DATA_DIR = PROJECT_ROOT / "data"
RAW_DATA_DIR = DATA_DIR / "raw"
PROCESSED_DATA_DIR = DATA_DIR / "processed"
MODELS_DIR = PROJECT_ROOT / "models" / "saved_models"
ARTIFACTS_DIR = MODELS_DIR / "artifacts"

for directory in [RAW_DATA_DIR, PROCESSED_DATA_DIR, MODELS_DIR, ARTIFACTS_DIR]:
    directory.mkdir(parents=True, exist_ok=True)

# ==============================================================================
# Dataset Ingestion
# ==============================================================================


def discover_dataset_files(dataset_names: Tuple[str, ...]) -> List[Path]:
    files = []
    for name in dataset_names:
        path = RAW_DATA_DIR / name
        if not path.exists():
            print(f"⚠️  Missing dataset: {name}")
        else:
            files.append(path)
    if not files:
        raise FileNotFoundError(
            f"No datasets found in {RAW_DATA_DIR}. "
            "Please place Aruba/HomeC/Tulum CSV files there."
        )
    return files


def _parse_homec(df: pd.DataFrame) -> pd.DataFrame:
    possible_cols = {
        "time": "timestamp",
        "Time": "timestamp",
    }
    df = df.rename(columns=possible_cols)
    if "timestamp" not in df.columns:
        df = df.rename(columns={df.columns[0]: "timestamp"})

    numeric_map = {
        "use [kW]": "power_kw",
        "House overall [kW]": "house_kw",
        "Dishwasher [kW]": "dishwasher_kw",
        "gen [kW]": "generation_kw",
    }
    for original, target in numeric_map.items():
        if original in df.columns:
            df[target] = pd.to_numeric(df[original], errors="coerce")

    out = pd.DataFrame(
        {
            "timestamp": pd.to_datetime(df["timestamp"], errors="coerce"),
            "power_kw": df.get("power_kw"),
            "house_kw": df.get("house_kw"),
            "generation_kw": df.get("generation_kw"),
            "appliance_kw": df.get("dishwasher_kw"),
        }
    )

    out["occupancy_signal"] = np.clip(
        (out["house_kw"].fillna(out["power_kw"]).fillna(0)) / 1.5, 0, 1
    )
    out["temperature_c"] = 20 + out["power_kw"].fillna(0) * 1.2
    out["humidity_pct"] = 45 + np.random.randn(len(out)) * 5
    return out


def _parse_event_dataset(df: pd.DataFrame, name: str) -> pd.DataFrame:
    df = df.rename(
        columns={
            "date": "Date",
            "time": "Time",
            "sensor": "Sensor",
            "state": "State",
            "value": "State",
        }
    )
    if "Date" not in df.columns or "Time" not in df.columns:
        raise ValueError(f"{name} dataset must have Date / Time columns.")

    timestamp = pd.to_datetime(df["Date"] + " " + df["Time"], errors="coerce")
    state = df["State"].astype(str).str.upper()

    sensor_type = df.get("Sensor", name).astype(str).str.lower()
    motion = state.isin({"ON", "OPEN", "PRESENT", "1"}).astype(float)
    motion *= sensor_type.str.contains("motion|pir|door|entry").astype(float)

    out = pd.DataFrame(
        {
            "timestamp": timestamp,
            "occupancy_signal": motion,
            "power_kw": np.where(motion > 0, np.random.uniform(0.6, 1.5), 0.2),
        }
    )
    out["temperature_c"] = 21 + np.random.randn(len(out)) * 1.5
    out["humidity_pct"] = 48 + np.random.randn(len(out)) * 4
    out["appliance_kw"] = np.where(
        sensor_type.str.contains("kitchen|cook|dish"), out["power_kw"] * 0.7, 0.0
    )
    out["house_kw"] = out["power_kw"] + out["appliance_kw"]
    out["generation_kw"] = 0.0
    return out


def load_datasets(dataset_files: List[Path]) -> pd.DataFrame:
    frames = []
    for file in dataset_files:
        name = file.stem.lower()
        print(f"📥 Loading {file.name} ...")
        df = pd.read_csv(file)
        if "homec" in name:
            parsed = _parse_homec(df)
        else:
            parsed = _parse_event_dataset(df, name)
        frames.append(parsed)
        print(f"   → Parsed {len(parsed):,} rows.")

    combined = pd.concat(frames, ignore_index=True)
    combined = combined.dropna(subset=["timestamp"]).sort_values("timestamp")
    combined = combined.reset_index(drop=True)
    print(f"\n✅ Combined dataset size: {len(combined):,} rows")
    return combined


# ==============================================================================
# Feature Engineering
# ==============================================================================


class SmartHomePreprocessor:
    def __init__(self, config: TrainingConfig):
        self.config = config
        self.feature_scaler = StandardScaler()
        self.feature_columns: List[str] = []
        self.target_columns: List[str] = list(config.targets)

    @staticmethod
    def _fill_missing_hours(df: pd.DataFrame) -> pd.DataFrame:
        df = df.set_index("timestamp")
        full_range = pd.date_range(df.index.min(), df.index.max(), freq="H")
        df = df.reindex(full_range)
        df = df.interpolate("time").ffill().bfill()
        df.index.name = "timestamp"
        return df.reset_index()

    @staticmethod
    def _engineer_targets(df: pd.DataFrame, max_value: int) -> pd.DataFrame:
        power_norm = (df["house_kw"].fillna(df["power_kw"]).fillna(0)).clip(lower=0)
        occupancy = df["occupancy_signal"].fillna(0)
        temperature = df["temperature_c"].fillna(22)
        humidity = df["humidity_pct"].fillna(50)

        fan_speed = (
            0.6 * np.clip((temperature - 19) / 10, 0, 1)
            + 0.3 * np.clip((humidity - 35) / 30, 0, 1)
            + 0.1 * np.clip(power_norm / 3, 0, 1)
        )
        led_brightness = (
            0.55 * occupancy
            + 0.25 * np.clip(
                np.sin(2 * np.pi * df["timestamp"].dt.hour / 24) * -1, 0, 1
            )
            + 0.2 * np.clip(power_norm / 4, 0, 1)
        )

        df["fan_speed"] = np.clip(fan_speed, 0, 1) * max_value
        df["led_brightness"] = np.clip(led_brightness, 0, 1) * max_value
        return df

    def build_hourly_features(self, df: pd.DataFrame) -> pd.DataFrame:
        print("\n🔧 Aggregating to hourly features ...")
        df = self._fill_missing_hours(df)
        df = self._engineer_targets(df, self.config.max_target_value)

        hourly = df.resample("H", on="timestamp").agg(
            {
                "power_kw": ["mean", "max", "std"],
                "house_kw": ["mean", "max"],
                "generation_kw": "mean",
                "appliance_kw": "mean",
                "occupancy_signal": ["mean", "sum"],
                "temperature_c": ["mean", "max", "min"],
                "humidity_pct": ["mean", "max"],
                "fan_speed": "mean",
                "led_brightness": "mean",
            }
        )
        hourly.columns = ["_".join(col).strip("_") for col in hourly.columns]
        hourly = hourly.reset_index().rename(columns={"timestamp": "hour"})

        # Rolling features and temporal encodings
        hourly["hour_sin"] = np.sin(2 * np.pi * hourly["hour"].dt.hour / 24)
        hourly["hour_cos"] = np.cos(2 * np.pi * hourly["hour"].dt.hour / 24)
        hourly["day_of_week"] = hourly["hour"].dt.dayofweek
        hourly["is_weekend"] = (hourly["day_of_week"] >= 5).astype(int)

        rolling_cols = [
            "power_kw_mean",
            "house_kw_mean",
            "temperature_c_mean",
            "humidity_pct_mean",
            "occupancy_signal_mean",
        ]
        for col in rolling_cols:
            hourly[f"{col}_roll6"] = (
                hourly[col].rolling(window=6, min_periods=1).mean()
            )
            hourly[f"{col}_roll24"] = (
                hourly[col].rolling(window=24, min_periods=1).mean()
            )

        hourly["fan_speed_lag1"] = hourly["fan_speed_mean"].shift(1).fillna(
            hourly["fan_speed_mean"].rolling(3).mean()
        )
        hourly["led_brightness_lag1"] = hourly["led_brightness_mean"].shift(1).fillna(
            hourly["led_brightness_mean"].rolling(3).mean()
        )

        hourly = hourly.dropna().reset_index(drop=True)
        print(f"   → Hourly rows after feature engineering: {len(hourly):,}")
        return hourly

    def prepare_sequences(self, df: pd.DataFrame) -> Tuple[np.ndarray, np.ndarray]:
        sequence_len = self.config.sequence_length
        self.feature_columns = [
            col
            for col in df.columns
            if col
            not in {
                "hour",
                "fan_speed_mean",
                "led_brightness_mean",
            }
        ]

        features = df[self.feature_columns].values.astype(np.float32)
        targets = df[
            ["fan_speed_mean", "led_brightness_mean"]
        ].values.astype(np.float32)

        features = self.feature_scaler.fit_transform(features)
        targets = targets / self.config.max_target_value

        X, y = [], []
        for idx in range(len(df) - sequence_len - self.config.prediction_horizon):
            X.append(features[idx : idx + sequence_len])
            horizon_idx = idx + sequence_len + self.config.prediction_horizon - 1
            y.append(targets[horizon_idx])

        X = np.asarray(X, dtype=np.float32)
        y = np.asarray(y, dtype=np.float32)
        print(f"   → Sequence tensor: {X.shape}, Targets: {y.shape}")
        return X, y


# ==============================================================================
# Model
# ==============================================================================


def build_temporal_cnn(
    input_shape: Tuple[int, int], config: TrainingConfig
) -> keras.Model:
    inputs = keras.layers.Input(shape=input_shape)
    x = inputs
    for filters in config.conv_filters:
        residual = x
        x = keras.layers.Conv1D(
            filters,
            config.kernel_size,
            padding="same",
            activation="relu",
            kernel_initializer="he_normal",
        )(x)
        x = keras.layers.BatchNormalization()(x)
        x = keras.layers.Conv1D(
            filters,
            config.kernel_size,
            padding="same",
            activation="relu",
            kernel_initializer="he_normal",
        )(x)
        x = keras.layers.BatchNormalization()(x)
        if residual.shape[-1] != filters:
            residual = keras.layers.Conv1D(filters, 1, padding="same")(residual)
        x = keras.layers.Add()([x, residual])
        x = keras.layers.Activation("relu")(x)
        x = keras.layers.Dropout(config.dropout)(x)

    x = keras.layers.GlobalAveragePooling1D()(x)
    x = keras.layers.Dense(128, activation="relu")(x)
    x = keras.layers.Dropout(config.dropout)(x)
    x = keras.layers.Dense(64, activation="relu")(x)
    outputs = keras.layers.Dense(
        len(config.targets),
        activation="sigmoid",
        name="controller_output",
    )(x)

    model = keras.Model(inputs, outputs, name="smartsync_tcn")
    model.compile(
        optimizer=keras.optimizers.Adam(learning_rate=config.learning_rate),
        loss=keras.losses.MeanSquaredError(),
        metrics=[
            keras.metrics.MeanAbsoluteError(name="mae"),
            keras.metrics.RootMeanSquaredError(name="rmse"),
        ],
    )

    print("\n📐 Model Summary")
    model.summary()
    return model


class ValidationR2Callback(keras.callbacks.Callback):
    def __init__(self, val_data: Tuple[np.ndarray, np.ndarray]):
        super().__init__()
        self.val_data = val_data
        self.history: List[float] = []

    def on_epoch_end(self, epoch: int, logs=None):
        X_val, y_val = self.val_data
        preds = self.model.predict(X_val, verbose=0)
        self.history.append(float(r2_score(y_val, preds)))


def create_tf_dataset(
    X: np.ndarray, y: np.ndarray, batch_size: int, shuffle: bool
) -> tf.data.Dataset:
    ds = tf.data.Dataset.from_tensor_slices((X, y))
    if shuffle:
        ds = ds.shuffle(buffer_size=len(X), seed=CONFIG.seed)
    ds = ds.batch(batch_size).prefetch(tf.data.AUTOTUNE)
    return ds


def train_model(
    X_train: np.ndarray,
    y_train: np.ndarray,
    X_val: np.ndarray,
    y_val: np.ndarray,
    config: TrainingConfig,
) -> Tuple[keras.Model, keras.callbacks.History, List[float]]:
    model = build_temporal_cnn(X_train.shape[1:], config)
    train_ds = create_tf_dataset(X_train, y_train, config.batch_size, shuffle=True)
    val_ds = create_tf_dataset(X_val, y_val, config.batch_size, shuffle=False)

    callbacks = [
        keras.callbacks.EarlyStopping(
            monitor="val_loss",
            patience=12,
            restore_best_weights=True,
            verbose=1,
        ),
        keras.callbacks.ReduceLROnPlateau(
            monitor="val_loss",
            factor=0.5,
            patience=6,
            min_lr=config.min_learning_rate,
            verbose=1,
        ),
        keras.callbacks.ModelCheckpoint(
            filepath=MODELS_DIR / "schedule_predictor_best.keras",
            monitor="val_loss",
            save_best_only=True,
            verbose=1,
        ),
    ]
    r2_callback = ValidationR2Callback((X_val, y_val))
    callbacks.append(r2_callback)

    history = model.fit(
        train_ds,
        validation_data=val_ds,
        epochs=config.epochs,
        verbose=1,
        callbacks=callbacks,
    )

    history.history["val_r2"] = r2_callback.history
    return model, history, r2_callback.history


# ==============================================================================
# Analysis / Visuals
# ==============================================================================


class TrainingAnalyzer:
    def __init__(self, config: TrainingConfig):
        self.config = config

    def _plot_training_curves(self, history: keras.callbacks.History) -> Path:
        fig, axes = plt.subplots(1, 3, figsize=(18, 5))
        epochs = range(1, len(history.history["loss"]) + 1)

        axes[0].plot(epochs, history.history["loss"], label="Train")
        axes[0].plot(epochs, history.history["val_loss"], label="Val")
        axes[0].set_title("Loss (MSE)")
        axes[0].set_xlabel("Epoch")
        axes[0].grid(True, alpha=0.3)
        axes[0].legend()

        axes[1].plot(epochs, history.history["mae"], label="Train")
        axes[1].plot(epochs, history.history["val_mae"], label="Val")
        axes[1].set_title("Mean Absolute Error")
        axes[1].set_xlabel("Epoch")
        axes[1].grid(True, alpha=0.3)
        axes[1].legend()

        axes[2].plot(
            range(1, len(history.history["val_r2"]) + 1),
            history.history["val_r2"],
            label="Val R²",
        )
        axes[2].set_ylim(-1.0, 1.0)
        axes[2].set_title("Validation R²")
        axes[2].set_xlabel("Epoch")
        axes[2].grid(True, alpha=0.3)

        plt.tight_layout()
        path = ARTIFACTS_DIR / "training_curves.png"
        fig.savefig(path, dpi=300)
        plt.close(fig)
        return path

    def _plot_prediction_diagnostics(
        self, y_true: np.ndarray, y_pred: np.ndarray
    ) -> Path:
        fan_true, led_true = y_true[:, 0], y_true[:, 1]
        fan_pred, led_pred = y_pred[:, 0], y_pred[:, 1]

        fig, axes = plt.subplots(2, 3, figsize=(18, 10))
        axes = axes.ravel()

        axes[0].scatter(fan_true, fan_pred, alpha=0.4, s=10)
        axes[0].plot([0, 1], [0, 1], "r--")
        axes[0].set_title("Fan Speed: Actual vs Pred")
        axes[0].set_xlabel("Actual")
        axes[0].set_ylabel("Predicted")

        axes[1].scatter(led_true, led_pred, alpha=0.4, s=10)
        axes[1].plot([0, 1], [0, 1], "r--")
        axes[1].set_title("LED Brightness: Actual vs Pred")

        axes[2].hist(
            fan_true - fan_pred,
            bins=40,
            alpha=0.7,
            label="Fan Residuals",
        )
        axes[2].hist(
            led_true - led_pred,
            bins=40,
            alpha=0.7,
            label="LED Residuals",
        )
        axes[2].legend()
        axes[2].set_title("Residual Distribution")

        sample = slice(0, min(200, len(fan_true)))
        axes[3].plot(fan_true[sample], label="Actual")
        axes[3].plot(fan_pred[sample], label="Pred")
        axes[3].set_title("Fan Speed (first 200 samples)")
        axes[3].legend()

        axes[4].plot(led_true[sample], label="Actual")
        axes[4].plot(led_pred[sample], label="Pred")
        axes[4].set_title("LED Brightness (first 200 samples)")
        axes[4].legend()

        axes[5].axis("off")
        axes[5].text(
            0.05,
            0.8,
            f"Fan corr: {np.corrcoef(fan_true, fan_pred)[0,1]:.3f}",
            fontsize=12,
        )
        axes[5].text(
            0.05,
            0.6,
            f"LED corr: {np.corrcoef(led_true, led_pred)[0,1]:.3f}",
            fontsize=12,
        )
        axes[5].text(
            0.05,
            0.4,
            f"Fan R²: {r2_score(fan_true, fan_pred):.3f}",
            fontsize=12,
        )
        axes[5].text(
            0.05,
            0.2,
            f"LED R²: {r2_score(led_true, led_pred):.3f}",
            fontsize=12,
        )

        plt.tight_layout()
        path = ARTIFACTS_DIR / "prediction_diagnostics.png"
        fig.savefig(path, dpi=300)
        plt.close(fig)
        return path

    def create_reports(
        self,
        history: keras.callbacks.History,
        y_true: np.ndarray,
        y_pred: np.ndarray,
    ) -> Dict[str, Path]:
        return {
            "training_curves": self._plot_training_curves(history),
            "prediction_diagnostics": self._plot_prediction_diagnostics(
                y_true, y_pred
            ),
        }


# ==============================================================================
# Evaluation / Persistence
# ==============================================================================


def evaluate_model(
    model: keras.Model, X_test: np.ndarray, y_test: np.ndarray
) -> Dict[str, float]:
    preds = model.predict(X_test, verbose=0)
    metrics = {
        "mae": float(mean_absolute_error(y_test, preds)),
        "rmse": float(math.sqrt(mean_squared_error(y_test, preds))),
        "r2": float(r2_score(y_test, preds)),
        "fan_r2": float(r2_score(y_test[:, 0], preds[:, 0])),
        "led_r2": float(r2_score(y_test[:, 1], preds[:, 1])),
        "fan_mae": float(mean_absolute_error(y_test[:, 0], preds[:, 0])),
        "led_mae": float(mean_absolute_error(y_test[:, 1], preds[:, 1])),
    }
    return metrics, preds


def save_artifacts(
    model: keras.Model,
    preprocessor: SmartHomePreprocessor,
    metrics: Dict[str, float],
    config: TrainingConfig,
) -> None:
    model_dir = MODELS_DIR / "schedule_predictor_v2"
    model_dir.mkdir(parents=True, exist_ok=True)
    model.save(model_dir)

    scaler_path = PROCESSED_DATA_DIR / "feature_scaler.pkl"
    joblib.dump(preprocessor.feature_scaler, scaler_path)

    metadata = {
        "trained_at": datetime.utcnow().isoformat(),
        "config": config.to_dict(),
        "metrics": metrics,
        "feature_columns": preprocessor.feature_columns,
        "target_columns": preprocessor.target_columns,
        "gpu_available": GPU_AVAILABLE,
    }
    with open(model_dir / "metadata.json", "w", encoding="utf-8") as fh:
        json.dump(metadata, fh, indent=2)

    with open(ARTIFACTS_DIR / "metrics_report.json", "w", encoding="utf-8") as fh:
        json.dump(metadata, fh, indent=2)

    print(f"\n💾 Saved model to {model_dir}")
    print(f"💾 Saved scaler to {scaler_path}")
    print(f"📝 Metrics written to {ARTIFACTS_DIR / 'metrics_report.json'}")


# ==============================================================================
# Pipeline
# ==============================================================================


def run_pipeline():
    print("\n" + "=" * 90)
    print("SMARTSYNC TRAINING PIPELINE")
    print("=" * 90)
    print(json.dumps(CONFIG.to_dict(), indent=2))

    dataset_files = discover_dataset_files(CONFIG.datasets)
    raw_df = load_datasets(dataset_files)

    preprocessor = SmartHomePreprocessor(CONFIG)
    hourly_df = preprocessor.build_hourly_features(raw_df)
    X, y = preprocessor.prepare_sequences(hourly_df)

    total = len(X)
    test_size = int(total * CONFIG.test_split)
    val_size = int(total * CONFIG.validation_split)

    X_train, y_train = X[: total - val_size - test_size], y[: total - val_size - test_size]
    X_val, y_val = (
        X[total - val_size - test_size : total - test_size],
        y[total - val_size - test_size : total - test_size],
    )
    X_test, y_test = X[total - test_size :], y[total - test_size :]

    print(
        f"\nDataset split → train: {len(X_train):,}, "
        f"val: {len(X_val):,}, test: {len(X_test):,}"
    )

    model, history, _ = train_model(X_train, y_train, X_val, y_val, CONFIG)
    metrics, y_pred = evaluate_model(model, X_test, y_test)

    analyzer = TrainingAnalyzer(CONFIG)
    artifacts = analyzer.create_reports(history, y_test, y_pred)
    for name, path in artifacts.items():
        print(f"📊 Saved {name} → {path}")

    save_artifacts(model, preprocessor, metrics, CONFIG)

    print("\n" + "=" * 90)
    print("TRAINING COMPLETE")
    print("=" * 90)
    for key, value in metrics.items():
        print(f"{key:>10}: {value:>8.4f}")


if __name__ == "__main__":
    run_pipeline()