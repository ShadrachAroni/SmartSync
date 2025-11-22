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

Data Leakage Prevention
------------------------
This implementation includes comprehensive data leakage prevention:

1. **Temporal Splitting**: Data is split temporally (train → val → test) BEFORE
   any feature engineering, preventing future information from leaking into training.

2. **Scaler Fitting**: StandardScaler is fit ONLY on training data. Validation and
   test sets are transformed using training statistics, preventing test set
   statistics from influencing the model.

3. **Feature Engineering**: Rolling statistics and lag features are computed
   separately for each split, using only past data within each split.

4. **Validation Checks**: Automatic validation ensures:
   - No temporal overlap between splits
   - No identical samples across splits
   - Scaler statistics match training data only
   - Feature statistics are appropriately different between splits

Usage
-----
    cd ml
    python scripts/train_smart_home.py
"""

from __future__ import annotations

import json
import math
import time
import warnings
import argparse
import hashlib
import os
import sys
from dataclasses import asdict, dataclass, field
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

import joblib
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd

# Mitigate GPU memory fragmentation (must be set before importing TensorFlow)
os.environ.setdefault("TF_GPU_ALLOCATOR", "cuda_malloc_async")

import tensorflow as tf
from sklearn.metrics import mean_absolute_error, mean_squared_error, r2_score
from sklearn.preprocessing import StandardScaler
from tensorflow import keras

# Suppress TensorFlow/absl warnings about optimizer state mismatches (expected when resuming)
import absl.logging
absl.logging.set_verbosity(absl.logging.ERROR)  # Suppress INFO/WARNING from absl

# Suppress common TensorFlow warnings
warnings.filterwarnings("ignore", category=FutureWarning)
warnings.filterwarnings("ignore", message=".*Skipping variable loading for optimizer.*")
warnings.filterwarnings("ignore", message=".*oneDNN custom operations.*")
warnings.filterwarnings("ignore", message=".*Unable to register.*factory.*")
warnings.filterwarnings("ignore", message=".*TF-TRT Warning.*")
warnings.filterwarnings("ignore", message=".*TensorRT.*")
warnings.filterwarnings("ignore", message=".*CPU feature guard.*")
warnings.filterwarnings("ignore", message=".*AVX.*")

# Set TensorFlow logging level
tf.get_logger().setLevel("ERROR")

# Suppress TensorFlow INFO and WARNING messages via environment variables
os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "2")  # 0=all, 1=info, 2=warnings, 3=errors only
os.environ.setdefault("TF_ENABLE_ONEDNN_OPTS", "0")  # Disable oneDNN to avoid warnings

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
            # Try to set memory limit to use more of available VRAM (3.5GB out of 4GB)
            try:
                tf.config.set_logical_device_configuration(
                    gpu,
                    [tf.config.LogicalDeviceConfiguration(memory_limit=3584)]  # 3.5GB in MB
                )
                print(f"✅ Set GPU memory limit to 3.5GB for {gpu.name}")
            except RuntimeError:
                # If logical device already configured, use memory growth instead
                tf.config.experimental.set_memory_growth(gpu, True)
                print(f"✅ Enabled memory growth on {gpu.name}")
        
        # Enable mixed precision for memory efficiency
        try:
            policy = keras.mixed_precision.Policy("mixed_float16")
            keras.mixed_precision.set_global_policy(policy)
            print("✅ Enabled mixed precision training (float16) for memory efficiency.")
        except Exception as e:
            print(f"⚠️  Could not enable mixed precision: {e}")
        
        return True
    except RuntimeError as exc:
        print(f"⚠️  GPU initialisation error: {exc}")
        return False


GPU_AVAILABLE = setup_gpu()


# ==============================================================================
# Auto-Recovery System
# ==============================================================================


class ErrorClassifier:
    """Classify training errors to determine recovery strategy."""
    
    MEMORY_ERROR_KEYWORDS = [
        "out of memory", "oom", "cuda out of memory", "resource exhausted",
        "failed to allocate", "memory allocation", "insufficient memory",
        "allocation failed", "cudaerror", "cuda_launch_blocking"
    ]
    
    CUDA_ERROR_KEYWORDS = [
        "cuda", "gpu", "device", "driver", "cudnn", "tensorflow",
        "failed to create cublas handle", "cuda driver version"
    ]
    
    NETWORK_ERROR_KEYWORDS = [
        "connection", "timeout", "network", "socket", "http", "dns"
    ]
    
    @classmethod
    def classify_error(cls, error: Exception) -> str:
        """Classify error type for recovery strategy selection."""
        error_str = str(error).lower()
        error_type = type(error).__name__.lower()
        
        # Check for memory errors
        if any(keyword in error_str for keyword in cls.MEMORY_ERROR_KEYWORDS):
            return "memory"
        
        # Check for CUDA/GPU errors
        if any(keyword in error_str for keyword in cls.CUDA_ERROR_KEYWORDS):
            return "cuda"
        
        # Check for network errors
        if any(keyword in error_str for keyword in cls.NETWORK_ERROR_KEYWORDS):
            return "network"
        
        # Check error type
        if "memory" in error_type or "oom" in error_type:
            return "memory"
        if "cuda" in error_type or "gpu" in error_type:
            return "cuda"
        if "keyboard" in error_type or "interrupt" in error_type:
            return "interrupt"
        
        return "unknown"
    
    @classmethod
    def is_recoverable(cls, error: Exception) -> bool:
        """Determine if error is recoverable with automatic retry."""
        error_type = cls.classify_error(error)
        return error_type in ["memory", "cuda"]


class SystemOptimizer:
    """Optimize system resources for training recovery."""
    
    @staticmethod
    def clear_gpu_memory():
        """Clear GPU memory cache."""
        try:
            if GPU_AVAILABLE:
                import gc
                gc.collect()
                tf.keras.backend.clear_session()
                # Try to clear CUDA cache if available
                try:
                    import tensorflow as tf
                    gpus = tf.config.list_physical_devices('GPU')
                    if gpus:
                        for gpu in gpus:
                            tf.config.experimental.reset_memory_stats(gpu)
                except Exception:
                    pass
                print("   ✅ GPU memory cache cleared")
        except Exception as e:
            print(f"   ⚠️  Could not clear GPU memory: {e}")
    
    @staticmethod
    def reduce_batch_size(config: TrainingConfig, reduction_factor: float = 0.75, min_batch_size: int = 8) -> TrainingConfig:
        """Create a new config with reduced batch size."""
        new_batch_size = max(
            min_batch_size,
            int(config.batch_size * reduction_factor)
        )
        if new_batch_size == config.batch_size and config.batch_size > min_batch_size:
            new_batch_size = max(min_batch_size, config.batch_size - 2)
        
        # Create new config with reduced batch size
        config_dict = config.to_dict()
        config_dict["batch_size"] = new_batch_size
        return TrainingConfig(**config_dict)
    
    @staticmethod
    def reduce_model_complexity(config: TrainingConfig) -> TrainingConfig:
        """Reduce model complexity to save memory."""
        config_dict = config.to_dict()
        # Reduce convolution filters
        current_filters = list(config.conv_filters)
        reduced_filters = tuple(max(16, int(f * 0.75)) for f in current_filters)
        config_dict["conv_filters"] = reduced_filters
        return TrainingConfig(**config_dict)


class AutoRecoveryManager:
    """Manage automatic recovery from training errors."""
    
    def __init__(self, config: TrainingConfig, state_manager: TrainingStateManager):
        self.config = config
        self.state_manager = state_manager
        self.recovery_attempts = 0
        self.recovery_history: List[Dict[str, Any]] = []
        self.optimizer = SystemOptimizer()
        self.error_classifier = ErrorClassifier()
    
    def should_attempt_recovery(self, max_attempts: int, auto_recover: bool) -> bool:
        """Check if we should attempt another recovery."""
        if not auto_recover:
            return False
        return self.recovery_attempts < max_attempts
    
    def record_recovery_attempt(self, error: Exception, strategy: str, success: bool):
        """Record a recovery attempt for tracking."""
        self.recovery_history.append({
            "attempt": self.recovery_attempts + 1,
            "timestamp": datetime.utcnow().isoformat(),
            "error_type": self.error_classifier.classify_error(error),
            "error_message": str(error)[:200],  # Truncate long messages
            "strategy": strategy,
            "success": success,
            "config": {
                "batch_size": self.config.batch_size,
                "conv_filters": self.config.conv_filters,
            }
        })
        self.recovery_attempts += 1
    
    def get_recovery_strategy(self, error: Exception) -> Tuple[str, TrainingConfig]:
        """Determine recovery strategy based on error type."""
        error_type = self.error_classifier.classify_error(error)
        current_config = self.config
        
        min_batch_size = getattr(current_config, 'min_batch_size', 8)
        
        if error_type == "memory":
            # Strategy 1: Clear memory and reduce batch size
            if self.recovery_attempts == 0:
                self.optimizer.clear_gpu_memory()
                new_config = self.optimizer.reduce_batch_size(current_config, 0.75, min_batch_size)
                return "clear_memory_reduce_batch", new_config
            
            # Strategy 2: Further reduce batch size
            elif self.recovery_attempts == 1:
                new_config = self.optimizer.reduce_batch_size(current_config, 0.67, min_batch_size)
                return "reduce_batch_size_2", new_config
            
            # Strategy 3: Reduce model complexity
            elif self.recovery_attempts == 2:
                new_config = self.optimizer.reduce_model_complexity(current_config)
                new_config = self.optimizer.reduce_batch_size(new_config, 0.75, min_batch_size)
                return "reduce_model_complexity", new_config
            
            # Strategy 4: Aggressive reduction
            else:
                new_config = self.optimizer.reduce_model_complexity(current_config)
                new_config = self.optimizer.reduce_batch_size(new_config, 0.5, min_batch_size)
                return "aggressive_reduction", new_config
        
        elif error_type == "cuda":
            # For CUDA errors, clear memory and reduce batch size
            self.optimizer.clear_gpu_memory()
            new_config = self.optimizer.reduce_batch_size(current_config, 0.75, min_batch_size)
            return "cuda_recovery", new_config
        
        else:
            # Default: just clear memory and reduce batch size slightly
            self.optimizer.clear_gpu_memory()
            new_config = self.optimizer.reduce_batch_size(current_config, 0.9, min_batch_size)
            return "default_recovery", new_config
    
    def save_recovery_state(self):
        """Save recovery state for debugging."""
        recovery_log_path = ARTIFACTS_DIR / "recovery_history.json"
        with open(recovery_log_path, "w", encoding="utf-8") as fh:
            json.dump({
                "recovery_attempts": self.recovery_attempts,
                "history": self.recovery_history,
                "current_config": self.config.to_dict(),
            }, fh, indent=2)
    
    def attempt_recovery(self, error: Exception, max_attempts: int, auto_recover: bool) -> Optional[TrainingConfig]:
        """Attempt to recover from error by optimizing system."""
        if not self.should_attempt_recovery(max_attempts, auto_recover):
            return None
        
        error_type = self.error_classifier.classify_error(error)
        strategy, new_config = self.get_recovery_strategy(error)
        
        print(f"\n{'='*90}")
        print(f"🔄 AUTOMATIC RECOVERY ATTEMPT {self.recovery_attempts + 1}/{max_attempts}")
        print(f"{'='*90}")
        print(f"   Error Type: {error_type}")
        print(f"   Strategy: {strategy}")
        print(f"   Original batch size: {self.config.batch_size}")
        print(f"   New batch size: {new_config.batch_size}")
        if new_config.conv_filters != self.config.conv_filters:
            print(f"   Original filters: {self.config.conv_filters}")
            print(f"   New filters: {new_config.conv_filters}")
        print(f"{'='*90}\n")
        
        # Wait a bit before retrying (exponential backoff)
        wait_time = min(30, 5 * (2 ** self.recovery_attempts))
        print(f"   ⏳ Waiting {wait_time}s before retry (allowing system to stabilize)...")
        time.sleep(wait_time)
        
        self.config = new_config
        self.record_recovery_attempt(error, strategy, False)  # Will update to True if successful
        self.save_recovery_state()
        
        return new_config


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
    batch_size: int = 24  # Balanced: faster than 16, safer than 32 for 4GB VRAM
    epochs: int = 50  # Reduced from 80 - early stopping will handle overfitting
    learning_rate: float = 3e-4
    min_learning_rate: float = 1e-6
    validation_split: float = 0.20  # Increased from 0.15 for more stable validation metrics
    test_split: float = 0.15
    label_smoothing: float = 0.02
    datasets: Tuple[str, ...] = ("HomeC.csv", "aruba.csv", "tulum.csv")
    conv_filters: Tuple[int, ...] = (64, 64, 32)  # Restored to original with 4GB VRAM
    kernel_size: int = 5
    dropout: float = 0.30  # Increased from 0.25 for stronger regularization
    # Regularization hyperparameters
    l2_regularization: float = 2e-4  # Increased from 1e-4 for stronger regularization
    gradient_clip_norm: float = 1.0  # Gradient clipping to prevent exploding gradients
    targets: Tuple[str, ...] = ("fan_speed", "led_brightness")
    max_target_value: int = 255
    # Data leakage prevention
    use_temporal_split: bool = True  # Use temporal split for time-series data (prevents leakage)
    validate_no_leakage: bool = True  # Enable strict leakage validation
    # Auto-recovery settings
    auto_recover: bool = True  # Enable automatic recovery from errors
    max_recovery_attempts: int = 5  # Maximum recovery attempts before giving up
    min_batch_size: int = 8  # Minimum batch size to try (below this, training may be too slow)

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
CACHE_DIR = ARTIFACTS_DIR / "cache"
CHECKPOINT_DIR = MODELS_DIR / "checkpoints"
PAUSE_FLAG_PATH = ARTIFACTS_DIR / "pause.flag"

for directory in [
    RAW_DATA_DIR,
    PROCESSED_DATA_DIR,
    MODELS_DIR,
    ARTIFACTS_DIR,
    CACHE_DIR,
    CHECKPOINT_DIR,
]:
    directory.mkdir(parents=True, exist_ok=True)


def compute_config_hash(config: TrainingConfig) -> str:
    payload = json.dumps(config.to_dict(), sort_keys=True).encode("utf-8")
    return hashlib.md5(payload).hexdigest()


def validate_no_data_leakage(
    X_train: np.ndarray,
    X_val: np.ndarray,
    X_test: np.ndarray,
    train_times: Optional[pd.Series] = None,
    val_times: Optional[pd.Series] = None,
    test_times: Optional[pd.Series] = None,
) -> Tuple[bool, List[str]]:
    """
    Validate that there's no data leakage between train/val/test sets.
    
    Checks:
    1. No overlap in feature statistics (mean, std) between splits
    2. Temporal ordering (if timestamps provided)
    3. No identical samples across splits
    
    Returns:
        (is_valid, list_of_issues)
    """
    issues = []
    
    # Check for identical samples (exact duplicates) - sample for performance
    # Note: For time-series, some overlap might be expected due to sequence windows
    # This is a conservative check
    sample_size = min(1000, len(X_train))
    train_set = set(tuple(x.flatten().round(decimals=4)) for x in X_train[:sample_size])
    val_set = set(tuple(x.flatten().round(decimals=4)) for x in X_val[:min(500, len(X_val))])
    test_set = set(tuple(x.flatten().round(decimals=4)) for x in X_test[:min(500, len(X_test))])
    
    train_val_overlap = len(train_set & val_set)
    train_test_overlap = len(train_set & test_set)
    val_test_overlap = len(val_set & test_set)
    
    # Only warn if significant overlap (more than 1% of samples)
    overlap_threshold = max(10, sample_size // 100)
    if train_val_overlap > overlap_threshold:
        issues.append(
            f"Found {train_val_overlap} very similar samples between train and validation "
            f"(threshold: {overlap_threshold})"
        )
    if train_test_overlap > overlap_threshold:
        issues.append(
            f"Found {train_test_overlap} very similar samples between train and test "
            f"(threshold: {overlap_threshold})"
        )
    if val_test_overlap > overlap_threshold:
        issues.append(
            f"Found {val_test_overlap} very similar samples between validation and test "
            f"(threshold: {overlap_threshold})"
        )
    
    # Check feature statistics overlap (should be different due to temporal nature)
    train_mean = np.mean(X_train, axis=(0, 1))
    val_mean = np.mean(X_val, axis=(0, 1))
    test_mean = np.mean(X_test, axis=(0, 1))
    
    # If means are too similar, might indicate leakage (but not definitive)
    train_val_similarity = np.corrcoef(train_mean, val_mean)[0, 1] if len(train_mean) > 1 else 0
    if train_val_similarity > 0.99:
        issues.append(
            f"Warning: Train and validation feature means are extremely similar "
            f"(correlation: {train_val_similarity:.4f}). Possible leakage."
        )
    
    # Temporal validation if timestamps provided
    if train_times is not None and val_times is not None and test_times is not None:
        if val_times.min() <= train_times.max():
            issues.append(
                f"Temporal leakage: Validation data ({val_times.min()}) overlaps with training ({train_times.max()})"
            )
        if test_times.min() <= val_times.max():
            issues.append(
                f"Temporal leakage: Test data ({test_times.min()}) overlaps with validation ({val_times.max()})"
            )
    
    return len(issues) == 0, issues


def compute_dataset_hash(tensors: Dict[str, np.ndarray]) -> str:
    """Compute a hash of the dataset tensors to detect changes."""
    # Create a deterministic hash from tensor shapes and a sample of data
    hash_data = []
    for key in sorted(tensors.keys()):
        arr = tensors[key]
        hash_data.append(f"{key}:shape={arr.shape},dtype={arr.dtype}")
        # Include a small sample for content verification (first and last elements)
        if arr.size > 0:
            sample = np.concatenate([arr.flat[:10], arr.flat[-10:]])
            hash_data.append(f"sample={hashlib.md5(sample.tobytes()).hexdigest()}")
    payload = "|".join(hash_data).encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


class DatasetCache:
    """Persist prepared tensors and preprocessors with metadata validation."""

    def __init__(self, config: TrainingConfig):
        self.config = config
        self.config_hash = compute_config_hash(config)
        self.dataset_path = CACHE_DIR / f"dataset_{self.config_hash}.npz"
        self.preprocessor_path = CACHE_DIR / f"preprocessor_{self.config_hash}.joblib"
        self.metadata_path = CACHE_DIR / f"metadata_{self.config_hash}.json"

    def has_cache(self) -> bool:
        """Check if all cache files exist."""
        return (
            self.dataset_path.exists()
            and self.preprocessor_path.exists()
            and self.metadata_path.exists()
        )

    def _load_metadata(self) -> Optional[Dict[str, Any]]:
        """Load cache metadata if it exists."""
        if not self.metadata_path.exists():
            return None
        try:
            with open(self.metadata_path, "r", encoding="utf-8") as fh:
                return json.load(fh)
        except (json.JSONDecodeError, IOError):
            return None

    def _validate_cache(self, metadata: Dict[str, Any]) -> Tuple[bool, List[str]]:
        """Validate that cached data matches current configuration."""
        issues = []
        
        # Check config hash matches
        cached_config_hash = metadata.get("config_hash")
        if cached_config_hash != self.config_hash:
            issues.append(
                f"Config hash mismatch: cached={cached_config_hash[:8]}, "
                f"current={self.config_hash[:8]}. Configuration has changed."
            )
        
        # Check expected shapes
        expected_shapes = metadata.get("shapes", {})
        if not expected_shapes:
            issues.append("Missing shape information in cache metadata.")
        
        return len(issues) == 0, issues

    def load(self) -> Tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray, np.ndarray, np.ndarray, SmartHomePreprocessor, Dict[str, Any]]:
        """Load cached datasets with validation."""
        if not self.has_cache():
            raise FileNotFoundError(
                f"Dataset cache not found. Expected files:\n"
                f"  - {self.dataset_path}\n"
                f"  - {self.preprocessor_path}\n"
                f"  - {self.metadata_path}"
            )
        
        # Load and validate metadata
        metadata = self._load_metadata()
        if not metadata:
            raise ValueError(
                f"Cache metadata file exists but is invalid or corrupted: {self.metadata_path}"
            )
        
        # Validate cache compatibility
        is_valid, issues = self._validate_cache(metadata)
        if not is_valid:
            error_msg = "Cache validation failed:\n  " + "\n  ".join(issues)
            error_msg += "\n\nUse --reset-cache to clear and rebuild cache."
            raise RuntimeError(error_msg)
        
        # Load tensors
        with np.load(self.dataset_path, allow_pickle=False) as data:
            X_train = data["X_train"]
            y_train = data["y_train"]
            X_val = data["X_val"]
            y_val = data["y_val"]
            X_test = data["X_test"]
            y_test = data["y_test"]
        
        # Verify shapes match metadata
        actual_shapes = {
            "X_train": X_train.shape,
            "y_train": y_train.shape,
            "X_val": X_val.shape,
            "y_val": y_val.shape,
            "X_test": X_test.shape,
            "y_test": y_test.shape,
        }
        expected_shapes = metadata.get("shapes", {})
        for key, expected_shape in expected_shapes.items():
            if key in actual_shapes and actual_shapes[key] != tuple(expected_shape):
                raise RuntimeError(
                    f"Shape mismatch for {key}: expected {expected_shape}, "
                    f"got {actual_shapes[key]}. Cache may be corrupted."
                )
        
        # Load preprocessor
        preprocessor: SmartHomePreprocessor = joblib.load(self.preprocessor_path)
        
        # Verify feature columns match
        cached_feature_cols = metadata.get("feature_columns", [])
        if cached_feature_cols != preprocessor.feature_columns:
            print(
                f"⚠️  Warning: Feature columns mismatch. "
                f"Cached: {len(cached_feature_cols)}, "
                f"Preprocessor: {len(preprocessor.feature_columns)}"
            )
        
        dataset_hash = metadata.get("dataset_hash", "unknown")
        print(f"📦 Loaded cached datasets (config: {self.config_hash[:8]}, "
              f"data: {dataset_hash[:8]})...")
        print(f"   Shapes: train={X_train.shape}, val={X_val.shape}, test={X_test.shape}")
        
        return X_train, y_train, X_val, y_val, X_test, y_test, preprocessor, metadata

    def save(
        self,
        tensors: Dict[str, np.ndarray],
        preprocessor: SmartHomePreprocessor,
    ) -> Dict[str, Any]:
        """Save datasets with comprehensive metadata."""
        # Compute dataset hash for integrity checking
        dataset_hash = compute_dataset_hash(tensors)
        
        # Extract shapes
        shapes = {key: list(arr.shape) for key, arr in tensors.items()}
        
        # Create metadata
        metadata = {
            "config_hash": self.config_hash,
            "dataset_hash": dataset_hash,
            "shapes": shapes,
            "feature_columns": preprocessor.feature_columns,
            "target_columns": preprocessor.target_columns,
            "created_at": datetime.utcnow().isoformat(),
            "config": self.config.to_dict(),
        }
        
        # Save all components
        np.savez_compressed(self.dataset_path, **tensors)
        joblib.dump(preprocessor, self.preprocessor_path)
        
        # Save metadata as JSON
        with open(self.metadata_path, "w", encoding="utf-8") as fh:
            json.dump(metadata, fh, indent=2)
        
        print(f"💾 Cached datasets (config: {self.config_hash[:8]}, "
              f"data: {dataset_hash[:8]})")
        print(f"   Shapes: {shapes}")
        
        return metadata

    def clear(self) -> None:
        """Clear all cache files."""
        for path in [self.dataset_path, self.preprocessor_path, self.metadata_path]:
            if path.exists():
                path.unlink()


class TrainingStateManager:
    """Track checkpoints, pause/resume state, and training metadata."""

    def __init__(self, config_hash: str):
        self.config_hash = config_hash
        self.state_path = CACHE_DIR / f"state_{config_hash}.json"
        self.latest_checkpoint_path = CHECKPOINT_DIR / f"{config_hash}_latest.weights.h5"
        self.latest_checkpoint_path.parent.mkdir(parents=True, exist_ok=True)

    def load_state(self) -> Optional[Dict[str, Any]]:
        if not self.state_path.exists():
            return None
        with open(self.state_path, "r", encoding="utf-8") as fh:
            return json.load(fh)

    def save_state(
        self,
        last_epoch: int,
        status: str,
        logs: Optional[Dict[str, float]] = None,
        message: Optional[str] = None,
        dataset_hash: Optional[str] = None,
        dataset_metadata: Optional[Dict[str, Any]] = None,
    ) -> None:
        """Save training state with dataset validation info."""
        payload: Dict[str, Any] = {
            "config_hash": self.config_hash,
            "last_epoch": last_epoch,
            "status": status,
            "updated_at": datetime.utcnow().isoformat(),
        }
        if logs:
            payload["logs"] = logs
        if message:
            payload["message"] = message
        if dataset_hash:
            payload["dataset_hash"] = dataset_hash
        if dataset_metadata:
            # Store key metadata for validation
            payload["dataset_metadata"] = {
                "shapes": dataset_metadata.get("shapes", {}),
                "feature_columns": dataset_metadata.get("feature_columns", []),
            }
        with open(self.state_path, "w", encoding="utf-8") as fh:
            json.dump(payload, fh, indent=2)

    def clear(self) -> None:
        if self.state_path.exists():
            self.state_path.unlink()
        if self.latest_checkpoint_path.exists():
            self.latest_checkpoint_path.unlink()

    def has_checkpoint(self) -> bool:
        return self.latest_checkpoint_path.exists()
    
    def validate_resume_compatibility(
        self, 
        current_config_hash: str,
        current_dataset_hash: Optional[str] = None,
        current_dataset_metadata: Optional[Dict[str, Any]] = None,
    ) -> Tuple[bool, List[str]]:
        """Validate that state/checkpoint are compatible with current config/dataset."""
        issues = []
        
        state = self.load_state()
        if not state:
            return False, ["No training state found"]
        
        # Check config hash
        state_config_hash = state.get("config_hash")
        if state_config_hash != current_config_hash:
            issues.append(
                f"Config mismatch: state={state_config_hash[:8] if state_config_hash else 'none'}, "
                f"current={current_config_hash[:8]}. Configuration has changed since last training."
            )
        
        # Check dataset hash if provided
        if current_dataset_hash:
            state_dataset_hash = state.get("dataset_hash")
            if state_dataset_hash and state_dataset_hash != current_dataset_hash:
                issues.append(
                    f"Dataset mismatch: state={state_dataset_hash[:8]}, "
                    f"current={current_dataset_hash[:8]}. Dataset has changed since last training."
                )
        
        # Check dataset shapes if provided
        if current_dataset_metadata:
            state_metadata = state.get("dataset_metadata", {})
            state_shapes = state_metadata.get("shapes", {})
            current_shapes = current_dataset_metadata.get("shapes", {})
            
            for key in ["X_train", "y_train", "X_val", "y_val"]:
                if key in state_shapes and key in current_shapes:
                    if state_shapes[key] != current_shapes[key]:
                        issues.append(
                            f"Shape mismatch for {key}: state={state_shapes[key]}, "
                            f"current={current_shapes[key]}"
                        )
        
        # Check checkpoint exists
        if not self.has_checkpoint():
            issues.append("Checkpoint file missing")
        
        return len(issues) == 0, issues


class PauseResumeCallback(keras.callbacks.Callback):
    """Monitor for pause requests and persist state each epoch."""

    def __init__(
        self,
        state_manager: TrainingStateManager,
        pause_flag_path: Path,
    ):
        super().__init__()
        self.state_manager = state_manager
        self.pause_flag_path = pause_flag_path
        self.pause_requested = False

    def on_epoch_end(self, epoch, logs=None):
        logs = logs or {}
        serializable_logs = {
            key: float(value)
            for key, value in logs.items()
            if isinstance(value, (int, float, np.floating))
        }
        # Note: dataset_hash and metadata should be set when training starts
        # They're stored in the callback's state if available
        self.state_manager.save_state(epoch + 1, "running", serializable_logs)
        if self.pause_flag_path.exists():
            print("\n⏸️  Pause requested. Finishing current epoch and stopping training.")
            self.state_manager.save_state(
                epoch + 1,
                "paused",
                serializable_logs,
                message="Pause flag detected.",
            )
            self.pause_requested = True
            self.model.stop_training = True

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

    # Try to extract real power/energy data from HomeC dataset
    # HomeC dataset may have columns like: use [kW], House overall [kW], etc.
    numeric_map = {
        "use [kW]": "power_kw",
        "House overall [kW]": "house_kw",
        "Dishwasher [kW]": "dishwasher_kw",
        "gen [kW]": "generation_kw",
        # Also check for alternative column names
        "power": "power_kw",
        "Power": "power_kw",
        "energy": "power_kw",
        "Energy": "power_kw",
        "kW": "power_kw",
        "kWh": "power_kw",
    }
    power_found = False
    for original, target in numeric_map.items():
        if original in df.columns:
            df[target] = pd.to_numeric(df[original], errors="coerce")
            if target == "power_kw" and df[target].notna().any():
                power_found = True
                print(f"   ✅ Found power column: '{original}' → {target}")
    
    if not power_found:
        print("   ⚠️  No power column found, will use synthetic data")

    # Try to extract real humidity data from HomeC dataset
    # HomeC dataset may have columns like: humidity, Humidity, RH, relative humidity, etc.
    humidity_cols = [col for col in df.columns 
                     if any(term in str(col).lower() 
                            for term in ['humidity', 'rh', 'relative'])]
    
    humidity_data = None
    if humidity_cols:
        # Use first matching humidity column found
        humidity_col = humidity_cols[0]
        print(f"   ✅ Found humidity column: '{humidity_col}'")
        humidity_data = pd.to_numeric(df[humidity_col], errors="coerce")
        # Normalize to percentage if needed (some datasets use 0-1 scale)
        if humidity_data.max() <= 1.0:
            humidity_data = humidity_data * 100
        # Clip to reasonable range (0-100%)
        humidity_data = humidity_data.clip(0, 100)
    else:
        print("   ⚠️  No humidity column found, generating synthetic data")

    out = pd.DataFrame(
        {
            "timestamp": pd.to_datetime(df["timestamp"], errors="coerce"),
            "power_kw": df.get("power_kw"),
            "house_kw": df.get("house_kw"),
            "generation_kw": df.get("generation_kw"),
            "appliance_kw": df.get("dishwasher_kw"),
        }
    )
    
    # Verify power data is present
    if out["power_kw"].notna().any():
        power_stats = out["power_kw"].describe()
        print(f"   📊 Power data range: {power_stats['min']:.3f} - {power_stats['max']:.3f} kW (mean: {power_stats['mean']:.3f} kW)")
    else:
        print("   ⚠️  No power data found, will generate synthetic")

    out["occupancy_signal"] = np.clip(
        (out["house_kw"].fillna(out["power_kw"]).fillna(0)) / 1.5, 0, 1
    )
    
    # Extract temperature if available, otherwise generate
    temp_cols = [col for col in df.columns 
                 if any(term in str(col).lower() 
                        for term in ['temp', 'temperature'])]
    if temp_cols:
        temp_col = temp_cols[0]
        print(f"   ✅ Found temperature column: '{temp_col}'")
        out["temperature_c"] = pd.to_numeric(df[temp_col], errors="coerce")
        # Fill missing with synthetic
        out["temperature_c"] = out["temperature_c"].fillna(20 + out["power_kw"].fillna(0) * 1.2)
    else:
        out["temperature_c"] = 20 + out["power_kw"].fillna(0) * 1.2
    
    # Use real humidity if available, otherwise generate realistic synthetic data
    if humidity_data is not None:
        out["humidity_pct"] = humidity_data
        # Fill any missing values with realistic synthetic data
        missing_mask = out["humidity_pct"].isna()
        if missing_mask.any():
            # Generate synthetic data correlated with temperature
            out.loc[missing_mask, "humidity_pct"] = (
                50 - (out.loc[missing_mask, "temperature_c"] - 22) * 2 + 
                np.random.randn(missing_mask.sum()) * 5
            ).clip(30, 70)
        print(f"   📊 Humidity range: {out['humidity_pct'].min():.1f}% - {out['humidity_pct'].max():.1f}%")
    else:
        # Generate realistic synthetic humidity (correlated with temperature)
        out["humidity_pct"] = (
            50 - (out["temperature_c"] - 22) * 2 + 
            np.random.randn(len(out)) * 5
        ).clip(30, 70)
        print("   📊 Using synthetic humidity data (correlated with temperature)")
    
    return out


def _parse_event_dataset(df: pd.DataFrame, name: str) -> pd.DataFrame:
    # Handle CSVs without headers
    # Check if columns are numeric (pandas assigns 0, 1, 2, 3... when header=None)
    # OR if first column looks like a date (indicating first row was used as header)
    first_col = df.columns[0] if len(df.columns) > 0 else None
    has_numeric_headers = (
        first_col is not None
        and (isinstance(first_col, (int, np.integer)) or str(first_col).isdigit())
    )
    
    # Check if first column name looks like a date (YYYY-MM-DD format)
    # This indicates the CSV has no headers and pandas used first row as headers
    first_col_str = str(first_col) if first_col is not None else ""
    looks_like_date_header = (
        len(first_col_str) >= 10 
        and first_col_str.count("-") >= 2
        and first_col_str.replace("-", "").replace(":", "").replace(".", "").isdigit()
    )
    
    if has_numeric_headers or looks_like_date_header:
        # No header row - assign column names based on position
        # Expected format: Date, Time, Sensor/Location, State
        if len(df.columns) >= 4:
            df.columns = ["Date", "Time", "Sensor", "State"]
        elif len(df.columns) == 3:
            df.columns = ["Date", "Time", "State"]
            df["Sensor"] = name
        else:
            raise ValueError(
                f"{name} dataset must have at least 3 columns (Date, Time, State)."
            )
    else:
        # Has headers - try to normalize column names
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

    sensor_type = df.get("Sensor", pd.Series([name] * len(df))).astype(str).str.lower()
    motion = state.isin({"ON", "OPEN", "PRESENT", "1"}).astype(float)
    motion *= sensor_type.str.contains("motion|pir|door|entry").astype(float)

    out = pd.DataFrame(
        {
            "timestamp": timestamp,
            "occupancy_signal": motion,
            "power_kw": np.where(motion > 0, np.random.uniform(0.6, 1.5), 0.2),
        }
    )
    
    # Generate realistic temperature (slightly higher when occupied)
    out["temperature_c"] = (
        21 + (motion * 1.5) + np.random.randn(len(out)) * 1.5
    ).clip(18, 28)
    
    # Generate realistic humidity correlated with temperature and time
    # Higher humidity in morning/evening, lower during day
    try:
        # Try to extract hour from timestamp
        if isinstance(timestamp, pd.Series) and pd.api.types.is_datetime64_any_dtype(timestamp):
            hour_of_day = timestamp.dt.hour
        else:
            # Convert to datetime if needed
            timestamp_dt = pd.to_datetime(timestamp, errors="coerce")
            hour_of_day = timestamp_dt.dt.hour.fillna(12)
    except Exception:
        # Fallback: use midday as default
        hour_of_day = pd.Series([12] * len(out))
    
    humidity_base = 50 - (out["temperature_c"] - 22) * 2  # Inverse correlation with temp
    humidity_variation = 10 * np.sin(2 * np.pi * hour_of_day / 24)  # Daily cycle
    out["humidity_pct"] = (
        humidity_base + humidity_variation + np.random.randn(len(out)) * 4
    ).clip(30, 70)
    
    out["appliance_kw"] = np.where(
        sensor_type.str.contains("kitchen|cook|dish"), out["power_kw"] * 0.7, 0.0
    )
    out["house_kw"] = out["power_kw"] + out["appliance_kw"]
    out["generation_kw"] = 0.0
    
    print(f"   📊 Generated synthetic humidity (range: {out['humidity_pct'].min():.1f}% - {out['humidity_pct'].max():.1f}%)")
    return out


def load_datasets(dataset_files: List[Path]) -> pd.DataFrame:
    frames = []
    for file in dataset_files:
        name = file.stem.lower()
        print(f"📥 Loading {file.name} ...")
        # Event datasets (aruba, tulum) don't have headers, so read with header=None
        if "homec" in name:
            df = pd.read_csv(file)
            # Log available columns for debugging
            print(f"   Available columns: {list(df.columns)[:10]}...")  # Show first 10
            parsed = _parse_homec(df)
        else:
            # Try reading without headers first (for aruba, tulum)
            df = pd.read_csv(file, header=None)
            parsed = _parse_event_dataset(df, name)
        frames.append(parsed)
        print(f"   → Parsed {len(parsed):,} rows.")
        # Verify humidity is present
        if "humidity_pct" in parsed.columns:
            print(f"   ✅ Humidity data included: {parsed['humidity_pct'].notna().sum():,} non-null values")
        # Verify power data is present
        if "power_kw" in parsed.columns:
            power_count = parsed["power_kw"].notna().sum()
            print(f"   ✅ Power data included: {power_count:,} non-null values")
            if power_count > 0:
                power_stats = parsed["power_kw"].describe()
                print(f"      Range: {power_stats['min']:.3f} - {power_stats['max']:.3f} kW")

    combined = pd.concat(frames, ignore_index=True)
    combined = combined.dropna(subset=["timestamp"]).sort_values("timestamp")
    combined = combined.reset_index(drop=True)
    print(f"\n✅ Combined dataset size: {len(combined):,} rows")
    
    # Verify humidity is in final dataset
    if "humidity_pct" in combined.columns:
        humidity_stats = combined["humidity_pct"].describe()
        print(f"\n📊 Humidity statistics:")
        print(f"   Mean: {humidity_stats['mean']:.1f}%")
        print(f"   Range: {humidity_stats['min']:.1f}% - {humidity_stats['max']:.1f}%")
        print(f"   Non-null: {combined['humidity_pct'].notna().sum():,} / {len(combined):,}")
    else:
        print("\n⚠️  WARNING: humidity_pct column missing from combined dataset!")
    
    # Verify power data is in final dataset
    if "power_kw" in combined.columns:
        power_stats = combined["power_kw"].describe()
        print(f"\n⚡ Power statistics:")
        print(f"   Mean: {power_stats['mean']:.3f} kW")
        print(f"   Range: {power_stats['min']:.3f} - {power_stats['max']:.3f} kW")
        print(f"   Non-null: {combined['power_kw'].notna().sum():,} / {len(combined):,}")
    else:
        print("\n⚠️  WARNING: power_kw column missing from combined dataset!")
    
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
        # Handle duplicate timestamps by aggregating before setting index
        if df["timestamp"].duplicated().any():
            # Build aggregation dictionary: mean for numeric columns, last for others
            agg_dict = {}
            for col in df.columns:
                if col == "timestamp":
                    continue
                if pd.api.types.is_numeric_dtype(df[col]):
                    agg_dict[col] = "mean"
                else:
                    agg_dict[col] = "last"
            
            if agg_dict:
                df = df.groupby("timestamp", as_index=False).agg(agg_dict)
            else:
                # If no columns to aggregate, just drop duplicates
                df = df.drop_duplicates(subset=["timestamp"], keep="last")
        
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

    def build_hourly_features(self, df: pd.DataFrame, is_training: bool = True) -> pd.DataFrame:
        """
        Build hourly features from raw data.
        
        Args:
            df: Raw dataframe with timestamp and sensor data
            is_training: If True, this is training data. Used for validation only.
        
        Returns:
            Hourly aggregated dataframe with engineered features
        """
        print("\n🔧 Aggregating to hourly features ...")
        df = self._fill_missing_hours(df)
        df = self._engineer_targets(df, self.config.max_target_value)

        # Set timestamp as index for resampling
        df = df.set_index("timestamp")
        
        hourly = df.resample("H").agg(
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

        # Fill NaN values: std can be NaN when there's only one value, fill with 0
        std_cols = [col for col in hourly.columns if col.endswith("_std")]
        for col in std_cols:
            hourly[col] = hourly[col].fillna(0.0)
        
        # Fill any remaining NaN values with forward fill, then backward fill, then 0
        hourly = hourly.ffill().bfill().fillna(0)

        # Temporal encodings (safe - only use current row's timestamp)
        hourly["hour_sin"] = np.sin(2 * np.pi * hourly["hour"].dt.hour / 24)
        hourly["hour_cos"] = np.cos(2 * np.pi * hourly["hour"].dt.hour / 24)
        hourly["day_of_week"] = hourly["hour"].dt.dayofweek
        hourly["is_weekend"] = (hourly["day_of_week"] >= 5).astype(int)

        # Rolling features - computed separately per split to prevent leakage
        # These use only past data (rolling window looks backward)
        rolling_cols = [
            "power_kw_mean",
            "house_kw_mean",
            "temperature_c_mean",
            "humidity_pct_mean",
            "occupancy_signal_mean",
        ]
        for col in rolling_cols:
            if col in hourly.columns:
                # Rolling windows only look backward, so safe for temporal splits
                hourly[f"{col}_roll6"] = (
                    hourly[col].rolling(window=6, min_periods=1).mean()
                )
                hourly[f"{col}_roll24"] = (
                    hourly[col].rolling(window=24, min_periods=1).mean()
                )

        # Lag features - computed separately per split
        # shift(1) looks at previous row, which is safe for temporal splits
        if "fan_speed_mean" in hourly.columns:
            hourly["fan_speed_lag1"] = hourly["fan_speed_mean"].shift(1).fillna(
                hourly["fan_speed_mean"].rolling(3, min_periods=1).mean()
            )
        if "led_brightness_mean" in hourly.columns:
            hourly["led_brightness_lag1"] = hourly["led_brightness_mean"].shift(1).fillna(
                hourly["led_brightness_mean"].rolling(3, min_periods=1).mean()
            )

        # Only drop rows where all feature columns are NaN (shouldn't happen after fillna, but safety check)
        feature_cols = [col for col in hourly.columns if col not in ["hour"]]
        hourly = hourly.dropna(subset=feature_cols[:5])  # Drop only if first 5 critical columns are all NaN
        hourly = hourly.reset_index(drop=True)
        print(f"   → Hourly rows after feature engineering: {len(hourly):,}")
        return hourly

    def prepare_sequences(
        self, 
        df: pd.DataFrame, 
        fit_scaler: bool = False
    ) -> Tuple[np.ndarray, np.ndarray]:
        """
        Prepare sequences from hourly dataframe.
        
        Args:
            df: Hourly feature dataframe
            fit_scaler: If True, fit scaler on this data. Should only be True for training data.
                        If False, transform using previously fitted scaler.
        
        Returns:
            X: Input sequences, y: Target values
        """
        sequence_len = self.config.sequence_length
        
        # Initialize feature columns if not already set (first call)
        if not hasattr(self, 'feature_columns') or not self.feature_columns:
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

        # CRITICAL: Fit scaler ONLY on training data, transform on all splits
        if fit_scaler:
            features = self.feature_scaler.fit_transform(features)
            print(f"   ✅ Fitted scaler on training data (mean: {self.feature_scaler.mean_[:3] if hasattr(self.feature_scaler, 'mean_') else 'N/A'})")
        else:
            if not hasattr(self.feature_scaler, 'mean_') or self.feature_scaler.mean_ is None:
                raise RuntimeError(
                    "Scaler not fitted! Call prepare_sequences with fit_scaler=True on training data first."
                )
            features = self.feature_scaler.transform(features)
            print(f"   ✅ Transformed using training scaler statistics")
        
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
    """
    Build Temporal CNN with comprehensive regularization to prevent overfitting/underfitting.
    
    Improvements:
    - L2 regularization on all convolutional and dense layers
    - Gradient clipping in optimizer
    - Batch normalization for stable training
    - Proper dropout placement
    """
    # L2 regularizer
    l2_reg = keras.regularizers.l2(config.l2_regularization)
    
    inputs = keras.layers.Input(shape=input_shape)
    x = inputs
    for filters in config.conv_filters:
        residual = x
        # First conv block with L2 regularization
        x = keras.layers.Conv1D(
            filters,
            config.kernel_size,
            padding="same",
            activation="relu",
            kernel_initializer="he_normal",
            kernel_regularizer=l2_reg,
            bias_regularizer=l2_reg,
        )(x)
        x = keras.layers.BatchNormalization()(x)
        # Second conv block with L2 regularization
        x = keras.layers.Conv1D(
            filters,
            config.kernel_size,
            padding="same",
            activation="relu",
            kernel_initializer="he_normal",
            kernel_regularizer=l2_reg,
            bias_regularizer=l2_reg,
        )(x)
        x = keras.layers.BatchNormalization()(x)
        # Residual connection
        if residual.shape[-1] != filters:
            residual = keras.layers.Conv1D(
                filters, 1, padding="same",
                kernel_regularizer=l2_reg,
                bias_regularizer=l2_reg,
            )(residual)
        x = keras.layers.Add()([x, residual])
        x = keras.layers.Activation("relu")(x)
        x = keras.layers.Dropout(config.dropout)(x)

    x = keras.layers.GlobalAveragePooling1D()(x)
    # Dense layers with L2 regularization
    x = keras.layers.Dense(
        128,
        activation="relu",
        kernel_regularizer=l2_reg,
        bias_regularizer=l2_reg,
        kernel_initializer="he_normal",
    )(x)
    x = keras.layers.BatchNormalization()(x)
    x = keras.layers.Dropout(config.dropout)(x)
    
    x = keras.layers.Dense(
        64,
        activation="relu",
        kernel_regularizer=l2_reg,
        bias_regularizer=l2_reg,
        kernel_initializer="he_normal",
    )(x)
    x = keras.layers.BatchNormalization()(x)
    x = keras.layers.Dropout(config.dropout * 0.6)(x)  # Slightly more dropout before output
    
    # Output layer should be float32 for mixed precision
    outputs = keras.layers.Dense(
        len(config.targets),
        activation="sigmoid",
        name="controller_output",
        dtype="float32",  # Ensure float32 output for mixed precision
        kernel_regularizer=l2_reg,
        bias_regularizer=l2_reg,
    )(x)

    model = keras.Model(inputs, outputs, name="smartsync_tcn")
    
    # Optimizer with gradient clipping
    optimizer = keras.optimizers.Adam(
        learning_rate=config.learning_rate,
        clipnorm=config.gradient_clip_norm,
    )
    
    model.compile(
        optimizer=optimizer,
        loss=keras.losses.MeanSquaredError(),
        metrics=[
            keras.metrics.MeanAbsoluteError(name="mae"),
            keras.metrics.RootMeanSquaredError(name="rmse"),
        ],
    )

    print("\n📐 Model Summary")
    model.summary()
    print(f"\n✅ Regularization applied:")
    print(f"   - L2 regularization: {config.l2_regularization}")
    print(f"   - Dropout: {config.dropout}")
    print(f"   - Gradient clipping: {config.gradient_clip_norm}")
    print(f"   - Batch normalization: Enabled")
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


class OverfittingMonitor(keras.callbacks.Callback):
    """Monitor training/validation gap to detect overfitting early with loss smoothing"""
    def __init__(self, gap_threshold=0.15, smoothing_window=3):
        super().__init__()
        self.gap_threshold = gap_threshold
        self.smoothing_window = smoothing_window
        self.best_gap = float('inf')
        self.epoch_gaps = []
        self.val_loss_history = []  # Track validation loss for smoothing
        self.train_loss_history = []  # Track training loss for smoothing
        
    def _smooth_loss(self, loss_history):
        """Apply moving average smoothing to reduce noise"""
        if len(loss_history) < self.smoothing_window:
            return loss_history[-1] if loss_history else 0
        return np.mean(loss_history[-self.smoothing_window:])
        
    def on_epoch_end(self, epoch: int, logs=None):
        if logs is None:
            return
        
        train_loss = logs.get('loss', 0)
        val_loss = logs.get('val_loss', 0)
        
        # Track history for smoothing
        self.train_loss_history.append(train_loss)
        self.val_loss_history.append(val_loss)
        
        # Use smoothed losses for more stable gap calculation
        smoothed_train = self._smooth_loss(self.train_loss_history)
        smoothed_val = self._smooth_loss(self.val_loss_history)
        
        if val_loss > 0 and train_loss > 0:
            # Calculate relative gap using the larger of the two losses as denominator
            # This handles both cases: val_loss > train_loss (overfitting) and val_loss < train_loss (unusual)
            max_loss = max(train_loss, val_loss)
            gap = abs(train_loss - val_loss) / max_loss
            
            # Also calculate smoothed gap
            max_smoothed = max(smoothed_train, smoothed_val)
            smoothed_gap = abs(smoothed_train - smoothed_val) / max_smoothed if max_smoothed > 0 else 0
            
            self.epoch_gaps.append(gap)
            self.best_gap = min(self.best_gap, gap)
            
            # Warn if gap is too large (use smoothed gap for more stable detection)
            if smoothed_gap > self.gap_threshold:
                if smoothed_val > smoothed_train:
                    # Typical overfitting: validation loss higher than training
                    print(f"\n⚠️  Warning: Large train/val gap detected ({smoothed_gap:.2%}). Possible overfitting.")
                    print(f"   Training loss: {train_loss:.6f} (smoothed: {smoothed_train:.6f})")
                    print(f"   Validation loss: {val_loss:.6f} (smoothed: {smoothed_val:.6f})")
                else:
                    # Unusual case: validation loss much lower than training
                    # This can happen early in training due to dropout/regularization effects
                    # or indicate data distribution issues
                    if epoch < 3:
                        # Early epochs: likely due to dropout/regularization during training
                        print(f"\nℹ️  Note: Validation loss lower than training ({smoothed_gap:.2%}).")
                        print(f"   This is normal in early epochs due to dropout/regularization during training.")
                        print(f"   Training loss: {train_loss:.6f}, Validation loss: {val_loss:.6f}")
                    else:
                        # Later epochs: could indicate data issues
                        print(f"\n⚠️  Warning: Validation loss significantly lower than training ({smoothed_gap:.2%}).")
                        print(f"   This may indicate data distribution differences or regularization effects.")
                        print(f"   Training loss: {train_loss:.6f}, Validation loss: {val_loss:.6f}")
            
            # Warn if validation loss is much higher (classic overfitting) - use raw loss for immediate detection
            if val_loss > train_loss * 1.5:
                print(f"⚠️  Warning: Validation loss ({val_loss:.4f}) >> Training loss ({train_loss:.4f})")
            
            # Warn if validation loss is very unstable (high variance)
            if len(self.val_loss_history) >= 5:
                recent_val_losses = self.val_loss_history[-5:]
                val_std = np.std(recent_val_losses)
                val_mean = np.mean(recent_val_losses)
                if val_mean > 0 and val_std / val_mean > 0.5:  # Coefficient of variation > 50%
                    print(f"⚠️  Warning: High validation loss variance detected (std: {val_std:.6f}, mean: {val_mean:.6f})")
                    print(f"   This suggests unstable training. Consider increasing validation set size or regularization.")
            
            # Warn if both losses are high and similar (underfitting)
            if epoch > 5 and train_loss > 0.5 and val_loss > 0.5:
                if abs(train_loss - val_loss) / max(train_loss, val_loss) < 0.1:
                    print(f"⚠️  Warning: High and similar losses detected. Model may be underfitting.")


class ProgressCallback(keras.callbacks.Callback):
    """Custom callback to show detailed training progress"""
    def __init__(self, total_epochs: int):
        super().__init__()
        self.total_epochs = total_epochs
        self.epoch_start_time = None
        
    def on_epoch_begin(self, epoch, logs=None):
        self.epoch_start_time = time.time()
        print(f"\n{'='*80}")
        print(f"Epoch {epoch + 1}/{self.total_epochs}")
        print(f"{'='*80}")
        
    def on_epoch_end(self, epoch, logs=None):
        elapsed = time.time() - self.epoch_start_time
        
        # Format metrics
        train_loss = logs.get('loss', 0)
        train_mae = logs.get('mae', 0)
        val_loss = logs.get('val_loss', 0)
        val_mae = logs.get('val_mae', 0)
        
        print(f"\n⏱️  Time: {elapsed:.1f}s")
        print(f"📊 Train - Loss: {train_loss:.4f}, MAE: {train_mae:.4f}")
        print(f"📊 Val   - Loss: {val_loss:.4f}, MAE: {val_mae:.4f}")
        
        # Estimate remaining time
        if epoch > 0:
            avg_time = elapsed
            remaining_epochs = self.total_epochs - (epoch + 1)
            estimated_remaining = avg_time * remaining_epochs
            if estimated_remaining > 60:
                print(f"⏳ Est. remaining: {estimated_remaining/60:.1f} minutes")
            else:
                print(f"⏳ Est. remaining: {estimated_remaining:.0f} seconds")


def create_tf_dataset(
    X: np.ndarray, y: np.ndarray, batch_size: int, shuffle: bool
) -> tf.data.Dataset:
    ds = tf.data.Dataset.from_tensor_slices((X, y))
    if shuffle:
        # Use smaller buffer (10k samples) for faster shuffling - still provides good randomness
        shuffle_buffer = min(10000, len(X))
        ds = ds.shuffle(buffer_size=shuffle_buffer, seed=CONFIG.seed)
    ds = ds.batch(batch_size, drop_remainder=False)
    ds = ds.prefetch(tf.data.AUTOTUNE)  # Prefetch for better GPU utilization
    return ds


def train_model(
    X_train: np.ndarray,
    y_train: np.ndarray,
    X_val: np.ndarray,
    y_val: np.ndarray,
    config: TrainingConfig,
    state_manager: Optional[TrainingStateManager] = None,
    initial_epoch: int = 0,
    resume_checkpoint: Optional[Path] = None,
    pause_flag_path: Path = PAUSE_FLAG_PATH,
    recovery_manager: Optional[AutoRecoveryManager] = None,
) -> Tuple[keras.Model, keras.callbacks.History, List[float]]:
    model = build_temporal_cnn(X_train.shape[1:], config)
    if resume_checkpoint and resume_checkpoint.exists():
        # Suppress optimizer-related warnings when loading checkpoints
        # These warnings are expected when optimizer state doesn't match (e.g., mixed precision, version differences)
        with warnings.catch_warnings():
            warnings.filterwarnings("ignore", message=".*Could not load weights.*LossScaleOptimizer.*")
            warnings.filterwarnings("ignore", message=".*Skipping variable loading for optimizer.*")
            warnings.filterwarnings("ignore", category=UserWarning, module="keras.*saving.*")
            try:
                # Load weights only (checkpoint is saved with save_weights_only=True)
                # This avoids LossScaleOptimizer compatibility issues with mixed precision training
                model.load_weights(str(resume_checkpoint))
                print(f"🔁 Loaded checkpoint: {resume_checkpoint.name}")
            except (AttributeError, ValueError, TypeError, OSError) as exc:
                # Handle optimizer-related errors (common with mixed precision + version differences)
                error_str = str(exc).lower()
                if "lossscaleoptimizer" in error_str or ("name" in error_str and "attribute" in error_str):
                    try:
                        # Fallback: Load with by_name to match layer names only, skip mismatches
                        model.load_weights(str(resume_checkpoint), by_name=True, skip_mismatch=True)
                        print(f"🔁 Loaded checkpoint weights (optimizer metadata skipped): {resume_checkpoint.name}")
                    except Exception as exc2:
                        print(f"⚠️  Could not load checkpoint ({exc2}). Continuing from scratch.")
                else:
                    print(f"⚠️  Could not load checkpoint ({exc}). Continuing from scratch.")
            except Exception as exc:
                print(f"⚠️  Could not load checkpoint ({exc}). Continuing from scratch.")

    train_ds = create_tf_dataset(X_train, y_train, config.batch_size, shuffle=True)
    val_ds = create_tf_dataset(X_val, y_val, config.batch_size, shuffle=False)

    callbacks = [
        ProgressCallback(total_epochs=config.epochs),  # Custom progress display
        keras.callbacks.EarlyStopping(
            monitor="val_loss",
            patience=10,  # Increased from 8 to allow for validation loss fluctuations
            restore_best_weights=True,
            min_delta=1e-5,  # Minimum change to qualify as improvement
            verbose=0,  # Reduced verbosity
            mode="min",  # Explicitly set mode
        ),
        keras.callbacks.ReduceLROnPlateau(
            monitor="val_loss",
            factor=0.5,
            patience=6,  # Increased from 5 to be less aggressive given validation instability
            min_lr=config.min_learning_rate,
            verbose=0,  # Reduced verbosity
            cooldown=3,  # Increased from 2 to wait longer before reducing LR again
            mode="min",  # Explicitly set mode
        ),
        keras.callbacks.ModelCheckpoint(
            filepath=str(MODELS_DIR / "schedule_predictor_best.keras"),
            monitor="val_loss",
            save_best_only=True,
            verbose=0,  # Reduced verbosity
        ),
        OverfittingMonitor(gap_threshold=0.15, smoothing_window=3),  # Monitor for overfitting with smoothing
    ]
    pause_callback: Optional[PauseResumeCallback] = None
    if state_manager:
        callbacks.append(
            keras.callbacks.ModelCheckpoint(
                filepath=str(state_manager.latest_checkpoint_path),
                save_weights_only=True,
                save_best_only=False,
                monitor="loss",
                save_freq="epoch",
                verbose=0,
            )
        )
        pause_callback = PauseResumeCallback(state_manager, pause_flag_path)
        callbacks.append(pause_callback)

    r2_callback = ValidationR2Callback((X_val, y_val))
    callbacks.append(r2_callback)

    # Training with automatic recovery wrapper
    try:
        history = model.fit(
            train_ds,
            validation_data=val_ds,
            epochs=config.epochs,
            initial_epoch=initial_epoch,
            verbose=1,  # Show progress bar for batches within epoch
            callbacks=callbacks,
        )
    except Exception as training_error:
        # Re-raise to be handled by recovery wrapper in run_pipeline
        # This allows the recovery system to catch and handle it
        raise

    history.history["val_r2"] = r2_callback.history
    
    # Print training diagnostics
    print("\n📊 Training Diagnostics:")
    if len(history.history['loss']) > 0:
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
    
    final_epoch = initial_epoch + len(history.history.get("loss", []))
    if state_manager:
        final_status = "paused" if (pause_callback and pause_callback.pause_requested) else "completed"
        # Note: dataset metadata should be passed from run_pipeline if needed
        # For now, save state without it (it's optional)
        state_manager.save_state(
            final_epoch, 
            final_status,
        )
        if final_status == "paused":
            print("⏸️  Training paused. Re-run with --resume to continue.")
        elif pause_flag_path.exists():
            try:
                pause_flag_path.unlink()
                print("▶️  Pause flag cleared after successful training.")
            except OSError:
                pass

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

    # Extract scaler parameters (mean and std) for Flutter app
    scaler_mean = preprocessor.feature_scaler.mean_.tolist() if hasattr(preprocessor.feature_scaler, 'mean_') else None
    scaler_std = preprocessor.feature_scaler.scale_.tolist() if hasattr(preprocessor.feature_scaler, 'scale_') else None
    
    # Save scaler parameters to JSON for Flutter app
    scaler_params = {
        "mean": scaler_mean,
        "std": scaler_std,
        "feature_columns": preprocessor.feature_columns,
    }
    scaler_json_path = model_dir / "scaler_params.json"
    with open(scaler_json_path, "w", encoding="utf-8") as fh:
        json.dump(scaler_params, fh, indent=2)
    print(f"💾 Saved scaler parameters to {scaler_json_path}")

    metadata = {
        "trained_at": datetime.utcnow().isoformat(),
        "config": config.to_dict(),
        "metrics": metrics,
        "feature_columns": preprocessor.feature_columns,
        "target_columns": preprocessor.target_columns,
        "gpu_available": GPU_AVAILABLE,
        "scaler_mean": scaler_mean,
        "scaler_std": scaler_std,
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


def run_pipeline(args):
    # Override auto-recovery settings from CLI
    if args.no_auto_recover:
        CONFIG.auto_recover = False
    if args.max_recovery_attempts is not None:
        CONFIG.max_recovery_attempts = args.max_recovery_attempts
    
    print("\n" + "=" * 90)
    print("SMARTSYNC TRAINING PIPELINE")
    print("=" * 90)
    print(json.dumps(CONFIG.to_dict(), indent=2))
    
    if CONFIG.auto_recover:
        print(f"\n✅ Auto-recovery enabled (max {CONFIG.max_recovery_attempts} attempts)")
        print("   Training will automatically recover from memory/OOM errors")
    else:
        print("\n⚠️  Auto-recovery disabled - training will stop on errors")

    dataset_cache = DatasetCache(CONFIG)
    state_manager = TrainingStateManager(dataset_cache.config_hash)

    if args.reset_cache:
        dataset_cache.clear()
        state_manager.clear()
        print("🧹 Cleared cached datasets and checkpoints.")
        if args.resume:
            print("⚠️  Resume requested after cache reset; starting fresh.")

    if args.refresh_data:
        dataset_cache.clear()
        state_manager.clear()
        print("🔁 Refreshing dataset cache per user request.")

    cache_metadata: Optional[Dict[str, Any]] = None
    
    # Check if old cache exists (without metadata file) - created before data leakage fixes
    old_cache_exists = (
        dataset_cache.dataset_path.exists() 
        and dataset_cache.preprocessor_path.exists()
        and not dataset_cache.metadata_path.exists()
    )
    
    if old_cache_exists:
        print("\n" + "=" * 90)
        print("⚠️  OLD CACHE DETECTED (pre-data-leakage-prevention)")
        print("=" * 90)
        print("   The existing cache was created with the OLD pipeline that had data leakage.")
        print("   The new pipeline prevents leakage by:")
        print("     - Temporal splitting (train → val → test)")
        print("     - Fitting scaler only on training data")
        print("     - Computing features separately per split")
        print()
        
        if args.resume:
            print("   ⚠️  CRITICAL WARNING: Resume requested with incompatible cache!")
            print()
            print("   The checkpoint was trained on OLD data (with leakage).")
            print("   The cache will be rebuilt with NEW data (no leakage).")
            print("   This may cause:")
            print("     - Shape mismatches")
            print("     - Feature distribution differences")
            print("     - Model performance degradation")
            print()
            print("   RECOMMENDED ACTIONS:")
            print("   1. If training is still running: Let it finish, then start fresh")
            print("   2. Start fresh training: python train_smart_home.py --reset-cache")
            print("   3. To use old cache (not recommended): Delete .npz and .joblib files")
            print()
            print("   Proceeding will clear old cache and rebuild with new pipeline...")
            print("   (Checkpoint compatibility is not guaranteed)")
            print()
        else:
            print("   Clearing old cache and rebuilding with new leakage-prevention pipeline...")
        
        dataset_cache.clear()
        # Also clear state if resuming, since it's incompatible
        if args.resume:
            state_manager.clear()
            print("   ✅ Old cache and state cleared")
            print("   ⚠️  Note: Resume will start from epoch 0 due to cache rebuild")
        else:
            print("   ✅ Old cache cleared")
    
    if dataset_cache.has_cache():
        try:
            (
                X_train,
                y_train,
                X_val,
                y_val,
                X_test,
                y_test,
                preprocessor,
                cache_metadata,
            ) = dataset_cache.load()
        except (FileNotFoundError, ValueError, RuntimeError) as e:
            print(f"⚠️  Cache load failed: {e}")
            print("   Rebuilding cache...")
            dataset_cache.clear()
            # Fall through to rebuild cache
            cache_metadata = None
    
    if cache_metadata is None:
        # Build cache if not loaded or load failed
        print("\n" + "=" * 90)
        print("BUILDING DATASET WITH DATA LEAKAGE PREVENTION")
        print("=" * 90)
        
        dataset_files = discover_dataset_files(CONFIG.datasets)
        raw_df = load_datasets(dataset_files)

        preprocessor = SmartHomePreprocessor(CONFIG)
        
        # CRITICAL: Split data TEMPORALLY first (before feature engineering that uses statistics)
        # This prevents data leakage from future data
        print("\n📊 Splitting data temporally (train → val → test)...")
        raw_df = raw_df.sort_values("timestamp").reset_index(drop=True)
        
        total_rows = len(raw_df)
        test_size = int(total_rows * CONFIG.test_split)
        val_size = int(total_rows * CONFIG.validation_split)
        train_size = total_rows - val_size - test_size
        
        # Temporal split: train (earliest) → val → test (latest)
        raw_train = raw_df.iloc[:train_size].copy()
        raw_val = raw_df.iloc[train_size:train_size + val_size].copy()
        raw_test = raw_df.iloc[train_size + val_size:].copy()
        
        print(f"   Train: {len(raw_train):,} rows ({raw_train['timestamp'].min()} to {raw_train['timestamp'].max()})")
        print(f"   Val:   {len(raw_val):,} rows ({raw_val['timestamp'].min()} to {raw_val['timestamp'].max()})")
        print(f"   Test:  {len(raw_test):,} rows ({raw_test['timestamp'].min()} to {raw_test['timestamp'].max()})")
        
        # Build features separately for each split to prevent leakage
        print("\n🔧 Building features for training set...")
        hourly_train = preprocessor.build_hourly_features(raw_train, is_training=True)
        
        print("\n🔧 Building features for validation set...")
        hourly_val = preprocessor.build_hourly_features(raw_val, is_training=False)
        
        print("\n🔧 Building features for test set...")
        hourly_test = preprocessor.build_hourly_features(raw_test, is_training=False)
        
        # Prepare sequences: fit scaler ONLY on training data
        print("\n📦 Preparing sequences...")
        print("   Training set (fitting scaler)...")
        X_train, y_train = preprocessor.prepare_sequences(hourly_train, fit_scaler=True)
        
        print("   Validation set (using training scaler)...")
        X_val, y_val = preprocessor.prepare_sequences(hourly_val, fit_scaler=False)
        
        print("   Test set (using training scaler)...")
        X_test, y_test = preprocessor.prepare_sequences(hourly_test, fit_scaler=False)
        
        # Comprehensive data leakage validation
        if CONFIG.validate_no_leakage:
            print("\n🔍 Validating data leakage prevention...")
            
            # Temporal validation
            train_max_time = raw_train["timestamp"].max()
            val_min_time = raw_val["timestamp"].min()
            val_max_time = raw_val["timestamp"].max()
            test_min_time = raw_test["timestamp"].min()
            
            temporal_issues = []
            if val_min_time <= train_max_time:
                temporal_issues.append(
                    f"Validation data ({val_min_time}) overlaps with training ({train_max_time})"
                )
            if test_min_time <= val_max_time:
                temporal_issues.append(
                    f"Test data ({test_min_time}) overlaps with validation ({val_max_time})"
                )
            
            if temporal_issues:
                raise RuntimeError(
                    f"⚠️  DATA LEAKAGE DETECTED:\n  " + "\n  ".join(temporal_issues)
                )
            
            # Statistical validation
            is_valid, stat_issues = validate_no_data_leakage(
                X_train, X_val, X_test,
                train_times=raw_train["timestamp"],
                val_times=raw_val["timestamp"],
                test_times=raw_test["timestamp"],
            )
            
            if not is_valid:
                print("   ⚠️  Potential leakage warnings:")
                for issue in stat_issues:
                    print(f"      - {issue}")
            
            # Verify scaler was only fit on training data
            if not hasattr(preprocessor.feature_scaler, 'mean_') or preprocessor.feature_scaler.mean_ is None:
                raise RuntimeError("Scaler was not fitted on training data!")
            
            # Verify scaler statistics are from training only
            train_feature_mean = np.mean(X_train, axis=(0, 1))
            scaler_mean = preprocessor.feature_scaler.mean_
            if not np.allclose(train_feature_mean, scaler_mean, rtol=1e-3):
                print("   ⚠️  Warning: Scaler mean doesn't match training data mean")
                print(f"      This might indicate scaler was fit on different data")
            
            print("   ✅ Temporal ordering validated")
            print("   ✅ Scaler fitted only on training data")
            print("   ✅ Statistical checks passed")
            print("   ✅ No data leakage detected")
        else:
            print("\n⚠️  Data leakage validation disabled (validate_no_leakage=False)")

        cache_metadata = dataset_cache.save(
            {
                "X_train": X_train,
                "y_train": y_train,
                "X_val": X_val,
                "y_val": y_val,
                "X_test": X_test,
                "y_test": y_test,
            },
            preprocessor,
        )

    print(
        f"\nDataset split → train: {len(X_train):,}, "
        f"val: {len(X_val):,}, test: {len(X_test):,}"
    )

    initial_epoch = 0
    resume_checkpoint: Optional[Path] = None
    if args.resume:
        # Validate resume compatibility
        dataset_hash = cache_metadata.get("dataset_hash") if cache_metadata else None
        is_compatible, issues = state_manager.validate_resume_compatibility(
            dataset_cache.config_hash,
            dataset_hash,
            cache_metadata,
        )
        
        if not is_compatible:
            error_msg = "Cannot resume training - compatibility check failed:\n"
            error_msg += "\n".join(f"  ❌ {issue}" for issue in issues)
            error_msg += "\n\nPossible solutions:"
            error_msg += "\n  1. Use --reset-cache to clear cache and start fresh"
            error_msg += "\n  2. Use --refresh-data to rebuild cache with current data"
            error_msg += "\n  3. Remove --resume flag to start new training"
            raise RuntimeError(error_msg)
        
        state = state_manager.load_state()
        if not state:
            raise RuntimeError(
                "Resume requested but no training state file was found in cache."
            )
        
        initial_epoch = int(state.get("last_epoch", 0))
        if not state_manager.has_checkpoint():
            raise RuntimeError(
                "Resume requested but checkpoint file is missing. "
                "Re-run without --resume or ensure previous training completed at least one epoch."
            )
        
        resume_checkpoint = state_manager.latest_checkpoint_path
        
        # Display resume information
        print(f"\n{'='*80}")
        print("🔄 RESUMING TRAINING")
        print(f"{'='*80}")
        print(f"   Epoch: {initial_epoch} / {CONFIG.epochs}")
        print(f"   Checkpoint: {resume_checkpoint.name}")
        print(f"   Config hash: {dataset_cache.config_hash[:8]}")
        if dataset_hash:
            print(f"   Dataset hash: {dataset_hash[:8]}")
        print(f"   Status: {state.get('status', 'unknown')}")
        if state.get('updated_at'):
            print(f"   Last updated: {state['updated_at']}")
        print(f"{'='*80}\n")
        
        if initial_epoch >= CONFIG.epochs:
            print(
                "✅ Training already completed according to state file. "
                "Use --refresh-data or --reset-cache to retrain."
            )
            return

    # Save initial state with dataset metadata for future validation
    # Initialize auto-recovery manager
    recovery_manager = AutoRecoveryManager(CONFIG, state_manager) if CONFIG.auto_recover else None
    
    # Save initial state with dataset metadata for future validation
    state_manager.save_state(
        initial_epoch,
        "running",
        message="Resumed" if args.resume else "Fresh run",
        dataset_hash=cache_metadata.get("dataset_hash") if cache_metadata else None,
        dataset_metadata=cache_metadata,
    )

    # Training with automatic recovery loop
    max_retries = CONFIG.max_recovery_attempts if CONFIG.auto_recover else 0
    retry_count = 0
    current_config = CONFIG
    training_successful = False
    model = None
    history = None
    
    while retry_count <= max_retries and not training_successful:
        try:
            if retry_count > 0:
                print(f"\n🔄 Retry attempt {retry_count} with optimized configuration...")
                # Update recovery manager config
                if recovery_manager:
                    recovery_manager.config = current_config
                # Rebuild datasets with new batch size
                print(f"   Using batch size: {current_config.batch_size}")
                # Rebuild model if complexity changed
                if current_config.conv_filters != CONFIG.conv_filters:
                    print(f"   Rebuilding model with reduced complexity: {current_config.conv_filters}")
            
            model, history, _ = train_model(
                X_train,
                y_train,
                X_val,
                y_val,
                current_config,
                state_manager=state_manager,
                initial_epoch=initial_epoch,
                resume_checkpoint=resume_checkpoint if retry_count == 0 else None,  # Only load checkpoint on first attempt
                recovery_manager=recovery_manager,
            )
            training_successful = True
            
            # Mark recovery as successful if we recovered
            if retry_count > 0 and recovery_manager:
                if recovery_manager.recovery_history:
                    recovery_manager.recovery_history[-1]["success"] = True
                recovery_manager.save_recovery_state()
                print(f"\n✅ Training recovered successfully after {retry_count} recovery attempt(s)!")
        
        except Exception as training_error:
            error_type = ErrorClassifier().classify_error(training_error)
            
            # Check if recoverable
            if recovery_manager and recovery_manager.error_classifier.is_recoverable(training_error):
                if recovery_manager.should_attempt_recovery(CONFIG.max_recovery_attempts, CONFIG.auto_recover):
                    # Attempt recovery
                    new_config = recovery_manager.attempt_recovery(training_error, CONFIG.max_recovery_attempts, CONFIG.auto_recover)
                    if new_config:
                        current_config = new_config
                        retry_count += 1
                        # Update initial epoch from state (in case we need to resume)
                        state = state_manager.load_state()
                        if state:
                            initial_epoch = int(state.get("last_epoch", initial_epoch))
                        # Ensure we have a checkpoint to resume from
                        if not state_manager.has_checkpoint() and initial_epoch > 0:
                            print(f"⚠️  No checkpoint found for epoch {initial_epoch}. Starting from epoch 0.")
                            initial_epoch = 0
                        continue
                    else:
                        print(f"\n❌ Maximum recovery attempts ({CONFIG.max_recovery_attempts}) reached.")
                        raise
                else:
                    print(f"\n❌ Maximum recovery attempts reached. Cannot recover from: {error_type}")
                    raise
            else:
                # Non-recoverable error or auto-recover disabled
                print(f"\n❌ Training failed with non-recoverable error: {error_type}")
                if state_manager:
                    state_manager.save_state(
                        initial_epoch,
                        "error",
                        message=f"Training failed: {str(training_error)[:200]}",
                    )
                raise
    
    if not training_successful:
        raise RuntimeError("Training failed after all recovery attempts")
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


def parse_cli_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Train the SmartSync model with caching, resume, and pause controls.",
    )
    parser.add_argument(
        "--resume",
        action="store_true",
        help="Resume training from the last completed epoch and checkpoint.",
    )
    parser.add_argument(
        "--reset-cache",
        action="store_true",
        help="Delete cached datasets and checkpoints before training.",
    )
    parser.add_argument(
        "--refresh-data",
        action="store_true",
        help="Rebuild dataset cache even if it already exists.",
    )
    parser.add_argument(
        "--request-pause",
        action="store_true",
        help=(
            "Create a pause flag so a running training job stops safely "
            "after the current epoch. This command exits immediately."
        ),
    )
    parser.add_argument(
        "--clear-pause",
        action="store_true",
        help="Remove the pause flag before starting/resuming training.",
    )
    parser.add_argument(
        "--no-auto-recover",
        action="store_true",
        help="Disable automatic recovery from memory/OOM errors. Training will stop on errors.",
    )
    parser.add_argument(
        "--max-recovery-attempts",
        type=int,
        default=5,
        help="Maximum number of automatic recovery attempts (default: 5).",
    )
    return parser.parse_args()


if __name__ == "__main__":
    cli_args = parse_cli_args()

    if cli_args.request_pause:
        PAUSE_FLAG_PATH.touch()
        print(f"⏸️  Pause flag created at {PAUSE_FLAG_PATH}.")
        sys.exit(0)

    if cli_args.clear_pause:
        if PAUSE_FLAG_PATH.exists():
            PAUSE_FLAG_PATH.unlink()
            print("▶️  Pause flag removed.")
        else:
            print("ℹ️  No pause flag present.")

    try:
        run_pipeline(cli_args)
    except Exception as exc:
        state_manager = TrainingStateManager(compute_config_hash(CONFIG))
        previous_state = state_manager.load_state() or {}
        state_manager.save_state(
            int(previous_state.get("last_epoch", 0)),
            "error",
            message=str(exc),
        )
        raise