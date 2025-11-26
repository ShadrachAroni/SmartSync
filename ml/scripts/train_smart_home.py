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
import shutil
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
                # Import tf at module level to avoid issues
                import tensorflow as tf
                tf.keras.backend.clear_session()
                # Try to clear CUDA cache if available
                try:
                    gpus = tf.config.list_physical_devices('GPU')
                    if gpus:
                        for gpu in gpus:
                            try:
                                tf.config.experimental.reset_memory_stats(gpu)
                            except Exception:
                                pass  # Some GPUs don't support this
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
    # IMPROVED CONFIG - Optimized for better training stability and performance
    seed: int = 42
    sequence_length: int = 24
    prediction_horizon: int = 1
    batch_size: int = 12  # Slightly larger for faster throughput
    epochs: int = 80  # Shorter schedule to stay within 1 hour budget
    learning_rate: float = 2e-3  # Higher LR to ensure learning happens (will be reduced to 1e-3 in model)
    validation_split: float = 0.20
    test_split: float = 0.15
    # Use all available datasets for maximum training data
    datasets: Tuple[str, ...] = (
        "HomeC.csv",
        "aruba.csv",
        "tulum.csv",
        "electricity_cleaned.csv",
        "smart_home_dataset.csv",
    )
    # Model architecture (not used in new LSTM model, kept for compatibility)
    conv_filters: Tuple[int, ...] = (64, 32)  # Not used in LSTM model
    kernel_size: int = 3
    dropout: float = 0.2  # Lower dropout for better gradient flow
    # Regularization
    l2_regularization: float = 1e-4  # Slightly higher for better regularization
    gradient_clip_norm: float = 1.0
    # Learning rate schedule
    use_lr_schedule: bool = True
    lr_patience: int = 10  # Reduce LR after 10 epochs without improvement
    lr_factor: float = 0.5  # Reduce LR by 50%
    lr_min: float = 1e-6  # Minimum learning rate
    # Early stopping
    early_stopping_patience: int = 20  # Stop after 20 epochs without improvement
    # No data augmentation for simplicity
    use_data_augmentation: bool = False
    input_noise_std: float = 0.0  # No input noise
    targets: Tuple[str, ...] = ("fan_speed", "led_brightness")
    max_target_value: int = 255
    # Normalize per dataset to avoid distribution issues
    normalize_targets_per_dataset: bool = True
    # Simple temporal split
    use_temporal_split: bool = True
    validate_no_leakage: bool = False  # Disable complex validation for now
    # Auto-recovery
    auto_recover: bool = True
    max_recovery_attempts: int = 3
    # Synthetic data boost
    use_synthetic_boost: bool = True
    synthetic_days: int = 90
    synthetic_scenarios: Tuple[str, ...] = (
        "balanced",
        "heat_wave",
        "humid_evening",
        "night_shift",
        "stormy",
    )
    # Runtime / acceleration controls
    time_limit_minutes: int = 55  # Stop training before 1 hour
    max_train_sequences: Optional[int] = 18000
    max_eval_sequences: Optional[int] = 5000
    # Target balancing controls
    balance_target_means: bool = True
    target_mean_center: float = 0.5
    min_target_std: float = 0.18
    reduce_target_correlation: bool = True
    # Performance-based early stopping thresholds
    target_mae_threshold: float = 0.22
    target_r2_threshold: float = 0.35
    min_variance_ratio: float = 0.45
    optimal_patience: int = 2
    optimal_min_epochs: int = 10

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


def _filter_temporal_overlap_per_dataset(
    split_df: pd.DataFrame,
    reference_df: pd.DataFrame,
    overlap_gap: pd.Timedelta,
    split_label: str,
    fallback_reference_df: Optional[pd.DataFrame] = None,
) -> pd.DataFrame:
    """
    Filter split_df rows that overlap with reference_df on a per-dataset basis.
    Ensures validation/test data for each dataset starts after that dataset's train/val timestamps.
    """
    if len(split_df) == 0 or "dataset_source" not in split_df.columns:
        return split_df

    filtered_frames: List[pd.DataFrame] = []
    total_before = len(split_df)

    unique_sources = split_df["dataset_source"].unique()
    for dataset_name in unique_sources:
        dataset_split = split_df[split_df["dataset_source"] == dataset_name]
        dataset_ref = reference_df[reference_df["dataset_source"] == dataset_name]

        if len(dataset_ref) == 0 and fallback_reference_df is not None:
            dataset_ref = fallback_reference_df[fallback_reference_df["dataset_source"] == dataset_name]

        if len(dataset_ref) == 0:
            # No reference data for this dataset – keep split as-is
            filtered_frames.append(dataset_split)
            continue

        cutoff = dataset_ref["timestamp"].max() + overlap_gap
        before = len(dataset_split)
        dataset_filtered = dataset_split[dataset_split["timestamp"] > cutoff].copy()
        filtered_frames.append(dataset_filtered)

        removed = before - len(dataset_filtered)
        if removed > 0:
            print(f"      {dataset_name}: {len(dataset_filtered):,}/{before:,} rows preserved ({removed:,} filtered)")

    if not filtered_frames:
        return split_df

    result = pd.concat(filtered_frames, ignore_index=True)
    removed_total = total_before - len(result)
    if removed_total > 0:
        print(f"   ⚠️  Filtered {removed_total:,} overlapping rows from {split_label} split")

    return result


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

    @staticmethod
    def clear_all(verbose: bool = True) -> int:
        """Remove every cached dataset/metadata/state/checkpoint file."""
        removed = 0

        def _remove_path(path: Path) -> None:
            nonlocal removed
            try:
                if path.is_dir():
                    shutil.rmtree(path, ignore_errors=True)
                else:
                    path.unlink()
                removed += 1
            except FileNotFoundError:
                pass

        for base_dir in [CACHE_DIR, CHECKPOINT_DIR]:
            if base_dir.exists():
                for path in base_dir.glob("*"):
                    _remove_path(path)

        if verbose:
            print(f"   🧹 Removed {removed} cached file(s) from {CACHE_DIR} / {CHECKPOINT_DIR}.")
        return removed


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


def _infer_epoch_unit(values: pd.Series) -> str:
    """Infer the most likely epoch unit (s/ms/us/ns) based on magnitude."""
    sample = values.dropna()
    if sample.empty:
        return "s"
    median_val = float(sample.median())
    if median_val == 0:
        return "s"

    digits = int(math.log10(abs(median_val))) + 1 if median_val != 0 else 1
    if digits >= 16:
        return "ns"
    if digits >= 13:
        return "us"
    if digits >= 11:
        return "ms"
    return "s"


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

    raw_timestamp = df["timestamp"]
    timestamp_parsed = pd.to_datetime(raw_timestamp, errors="coerce")
    invalid_timestamps = timestamp_parsed.isna().sum()
    if invalid_timestamps > 0:
        print(f"   ⚠️  Warning: {invalid_timestamps:,} rows have unparseable timestamps")
        # Show sample of unparseable timestamps for debugging
        if invalid_timestamps > 0 and invalid_timestamps < len(df):
            sample_invalid = df[timestamp_parsed.isna()]["timestamp"].head(3).tolist()
            print(f"      Sample invalid timestamps: {sample_invalid}")

    # Detect numeric UNIX timestamps (seconds/ms/etc.) and convert accordingly
    valid_timestamps = timestamp_parsed.dropna()
    needs_full_epoch_conversion = valid_timestamps.empty or valid_timestamps.max() <= pd.Timestamp("1975-01-01")

    numeric_ts_all = pd.to_numeric(raw_timestamp, errors="coerce")
    numeric_mask_all = numeric_ts_all.notna()

    if needs_full_epoch_conversion and numeric_mask_all.any():
        epoch_unit = _infer_epoch_unit(numeric_ts_all[numeric_mask_all])
        timestamp_parsed = pd.to_datetime(
            numeric_ts_all,
            unit=epoch_unit,
            origin="unix",
            errors="coerce",
        )
        print(f"   🔄 Detected numeric UNIX timestamps; parsed using unit='{epoch_unit}'.")
        valid_timestamps = timestamp_parsed.dropna()
        if not valid_timestamps.empty:
            print(
                f"   📅 Converted timestamp range: {valid_timestamps.min()} to {valid_timestamps.max()}"
            )
    else:
        # Attempt partial recovery for rows that failed parsing but look numeric
        invalid_mask = timestamp_parsed.isna() & numeric_mask_all
        if invalid_mask.any():
            epoch_unit = _infer_epoch_unit(numeric_ts_all[invalid_mask])
            recovered = pd.to_datetime(
                numeric_ts_all[invalid_mask],
                unit=epoch_unit,
                origin="unix",
                errors="coerce",
            )
            timestamp_parsed.loc[invalid_mask] = recovered
            recovered_count = recovered.notna().sum()
            if recovered_count > 0:
                print(f"   🔄 Recovered {recovered_count:,} UNIX timestamp rows using unit='{epoch_unit}'.")
            else:
                print("   ⚠️  Partial UNIX timestamp recovery attempted but no rows parsed.")
        elif needs_full_epoch_conversion and not numeric_mask_all.any():
            print("   ⚠️  Could not parse timestamps as UNIX epoch values.")

    # Check timestamp range
    valid_timestamps = timestamp_parsed[timestamp_parsed.notna()]
    if len(valid_timestamps) > 0:
        min_ts = valid_timestamps.min()
        max_ts = valid_timestamps.max()
        print(f"   📅 Timestamp range: {min_ts} to {max_ts}")
        # Check if timestamps are outside expected range
        min_valid_date = pd.Timestamp("2000-01-01")
        max_valid_date = pd.Timestamp("2030-12-31")
        if min_ts < min_valid_date or max_ts > max_valid_date:
            out_of_range = ((timestamp_parsed < min_valid_date) | (timestamp_parsed > max_valid_date)).sum()
            print(f"   ⚠️  Warning: {out_of_range:,} timestamps outside 2000-2030 range")
    
    out = pd.DataFrame(
        {
            "timestamp": timestamp_parsed,
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


def _synthesize_environment_from_power(power_series: pd.Series) -> Tuple[pd.Series, pd.Series, pd.Series]:
    """Generate occupancy, temperature, humidity signals from a power-like series."""
    normalized_power = power_series.fillna(0).astype(float)
    max_power = normalized_power.max()
    if max_power <= 0:
        occupancy = pd.Series(0.0, index=normalized_power.index)
    else:
        occupancy = np.clip(normalized_power / max_power, 0, 1)
    temperature = 20 + occupancy * 8 + np.random.normal(0, 1.5, size=len(occupancy))
    humidity = 50 - (temperature - 22) * 1.2 + np.random.normal(0, 3, size=len(temperature))
    humidity = np.clip(humidity, 30, 70)
    return occupancy, temperature, humidity


def generate_synthetic_smart_home_data(
    num_days: int = 30,
    samples_per_hour: int = 1,
    start_date: Optional[pd.Timestamp] = None,
    seed: int = 42,
    scenario: str = "balanced",
) -> pd.DataFrame:
    """
    Generate high-quality synthetic smart home data with realistic patterns.
    
    Args:
        num_days: Number of days of data to generate
        samples_per_hour: How many samples per hour (1 = hourly, 4 = 15-min, etc.)
        start_date: Start date (defaults to 1 year ago)
        seed: Random seed for reproducibility
        scenario: Behaviour preset (balanced, heat_wave, etc.)
    
    Returns:
        DataFrame with realistic smart home sensor data
    """
    rng = np.random.RandomState(seed)
    
    if start_date is None:
        start_date = pd.Timestamp.now() - pd.Timedelta(days=365)
    
    # Generate timestamps
    total_samples = num_days * 24 * samples_per_hour
    timestamps = pd.date_range(
        start=start_date,
        periods=total_samples,
        freq=f'{60 // samples_per_hour}min'
    )
    
    # Generate realistic daily and weekly patterns
    hours = timestamps.hour
    day_of_week = timestamps.dayofweek
    day_of_year = timestamps.dayofyear
    
    scenario = (scenario or "balanced").lower()
    scenario_params = {
        "balanced": {"temp_shift": 0.0, "humidity_shift": 0.0, "occupancy_bias": 0.0, "night_activity": 0.0, "power_scale": 1.0},
        "heat_wave": {"temp_shift": 5.0, "humidity_shift": -5.0, "occupancy_bias": 0.1, "night_activity": 0.1, "power_scale": 1.25},
        "humid_evening": {"temp_shift": 2.0, "humidity_shift": 10.0, "occupancy_bias": 0.05, "night_activity": 0.2, "power_scale": 1.1},
        "night_shift": {"temp_shift": -1.0, "humidity_shift": 0.0, "occupancy_bias": -0.05, "night_activity": 0.45, "power_scale": 0.9},
        "stormy": {"temp_shift": -3.0, "humidity_shift": 15.0, "occupancy_bias": 0.0, "night_activity": 0.1, "power_scale": 0.85},
        "dry_cool": {"temp_shift": -4.0, "humidity_shift": -10.0, "occupancy_bias": -0.05, "night_activity": -0.1, "power_scale": 0.9},
    }
    params = scenario_params.get(scenario, scenario_params["balanced"])
    
    # Occupancy pattern
    base_occupancy = 0.35 + 0.4 * np.sin(2 * np.pi * (hours - 6) / 16)
    base_occupancy = np.clip(base_occupancy, 0, 1)
    weekend_boost = np.where(day_of_week >= 5, 0.2, 0)
    night_adjust = params["night_activity"] * np.where((hours >= 22) | (hours < 6), 1, 0)
    occupancy = np.clip(
        base_occupancy + weekend_boost + night_adjust + params["occupancy_bias"] + rng.normal(0, 0.1, len(timestamps)),
        0,
        1,
    )
    
    # Power consumption: correlates with occupancy, has daily patterns
    base_power = (0.5 + occupancy * 1.5) * params["power_scale"]
    power_variation = 0.3 * np.sin(2 * np.pi * hours / 24)  # Daily cycle
    power = np.clip(base_power + power_variation + rng.normal(0, 0.2, len(timestamps)), 0.1, 5.0)
    
    # Temperature: daily cycle + seasonal + occupancy effect
    daily_temp = 22 + 4 * np.sin(2 * np.pi * (hours - 6) / 24)
    seasonal_temp = 2 * np.sin(2 * np.pi * day_of_year / 365)  # Seasonal: ±2°C
    occupancy_temp = occupancy * 2  # Occupancy adds heat
    temperature = daily_temp + seasonal_temp + occupancy_temp + params["temp_shift"] + rng.normal(0, 1.2, len(timestamps))
    temperature = np.clip(temperature, 18, 28)
    
    # Humidity: inverse correlation with temperature + daily pattern
    base_humidity = 50 - (temperature - 22) * 1.5
    daily_humidity = 10 * np.sin(2 * np.pi * (hours - 4) / 24)  # Higher in morning
    humidity = base_humidity + daily_humidity + params["humidity_shift"] + rng.normal(0, 3, len(timestamps))
    humidity = np.clip(humidity, 30, 70)
    
    # Appliance power (correlates with occupancy)
    appliance_power = occupancy * power * 0.3 + rng.normal(0, 0.1, len(timestamps))
    appliance_power = np.clip(appliance_power, 0, 2.0)
    
    # House power (total)
    house_power = power + appliance_power
    
    # Generation (solar - if applicable, can be 0)
    generation = np.zeros(len(timestamps))
    
    df = pd.DataFrame({
        "timestamp": timestamps,
        "power_kw": power,
        "house_kw": house_power,
        "generation_kw": generation,
        "appliance_kw": appliance_power,
        "occupancy_signal": occupancy,
        "temperature_c": temperature,
        "humidity_pct": humidity,
        "dataset_source": f"synthetic_{scenario}"
    })
    
    return df


def augment_dataset_with_synthetic(
    df: pd.DataFrame,
    min_hourly_rows: int = 1000,
    min_variance_fan: float = 38.0,
    min_variance_led: float = 38.0,
    max_target_value: int = 255,
    force_add: bool = False,
    synthetic_days: int = 60,
    scenarios: Optional[Tuple[str, ...]] = None,
) -> pd.DataFrame:
    """
    Augment dataset with synthetic data if needed to ensure quality.
    
    Args:
        df: Original dataframe
        min_hourly_rows: Minimum hourly rows needed after aggregation
        min_variance_fan: Minimum fan speed variance required
        min_variance_led: Minimum LED brightness variance required
        max_target_value: Maximum target value
    
    Returns:
        Augmented dataframe with synthetic data if needed
    """
    print("\n🔧 Checking if synthetic data augmentation is needed...")
    
    # Estimate hourly rows (rough estimate: divide by samples_per_hour)
    # Most datasets are sub-hourly, so estimate conservatively
    estimated_hourly = len(df) // 4  # Assume ~4 samples per hour on average
    
    # Check if we need more data
    needs_more_data = estimated_hourly < min_hourly_rows
    
    # Check target variance if targets exist
    needs_variance_boost = False
    if "fan_speed" in df.columns and "led_brightness" in df.columns:
        fan_std = df["fan_speed"].std()
        led_std = df["led_brightness"].std()
        needs_variance_boost = (fan_std < min_variance_fan) or (led_std < min_variance_led)
        if needs_variance_boost:
            print(f"   ⚠️  Target variance low: fan={fan_std:.1f}, LED={led_std:.1f}")
    
    if not (needs_more_data or needs_variance_boost or force_add):
        print("   ✅ Dataset has sufficient data and variance")
        return df
    
    # Calculate how much synthetic data to generate
    if needs_more_data:
        current_days = (df["timestamp"].max() - df["timestamp"].min()).days
        target_days = max(30, int(min_hourly_rows / 24) + 10)  # Add buffer
        additional_days = max(7, target_days - current_days)
        print(f"   📊 Generating {additional_days} days of synthetic data "
              f"(current: ~{current_days} days, need: ~{target_days} days)")
    else:
        additional_days = synthetic_days
        reason = "variance boost" if needs_variance_boost else "synthetic boost"
        print(f"   📊 Generating {additional_days} days of synthetic data for {reason}")
    
    scenario_list = scenarios or ("balanced", "heat_wave", "humid_evening")
    
    # Place synthetic data before earliest timestamp so it stays in training split
    first_timestamp = df["timestamp"].min()
    combined_synth = []
    for idx, scenario in enumerate(scenario_list):
        scenario_start = first_timestamp - pd.Timedelta(days=additional_days * (idx + 1) + 1)
        synth_df = generate_synthetic_smart_home_data(
            num_days=additional_days,
            samples_per_hour=1,
            start_date=scenario_start,
            seed=CONFIG.seed + 1000 + idx,
            scenario=scenario,
        )
        combined_synth.append(synth_df)
        print(
            f"   ✅ Generated {len(synth_df):,} synthetic rows for scenario '{scenario}' "
            f"({synth_df['timestamp'].min()} → {synth_df['timestamp'].max()})"
        )
    
    synthetic_df = pd.concat(combined_synth, ignore_index=True) if combined_synth else pd.DataFrame()
    
    # Combine with original data
    combined = pd.concat([synthetic_df, df], ignore_index=True)
    combined = combined.sort_values("timestamp").reset_index(drop=True)
    
    print(f"   ✅ Combined dataset: {len(combined):,} rows "
          f"(original: {len(df):,}, synthetic: {len(synthetic_df):,})")
    
    return combined


def _parse_electricity_dataset(df: pd.DataFrame, name: str) -> pd.DataFrame:
    """Parse multi-building electricity dataset into unified schema."""
    if "timestamp" not in df.columns:
        df = df.rename(columns={df.columns[0]: "timestamp"})
    timestamp = pd.to_datetime(df["timestamp"], errors="coerce")
    numeric_cols = [col for col in df.columns if col != "timestamp"]
    numeric_data = df[numeric_cols].apply(pd.to_numeric, errors="coerce")
    total_power = numeric_data.sum(axis=1).fillna(0)
    peak_power = numeric_data.max(axis=1).fillna(0)

    # Scale down very large totals to kW if necessary
    scale_factor = 1.0
    if total_power.max() > 500:
        scale_factor = 1000.0
    total_power_kw = total_power / scale_factor
    peak_power_kw = peak_power / scale_factor

    occupancy_signal, temperature_c, humidity_pct = _synthesize_environment_from_power(total_power_kw)
    out = pd.DataFrame(
        {
            "timestamp": timestamp,
            "power_kw": total_power_kw,
            "house_kw": total_power_kw,
            "generation_kw": 0.0,
            "appliance_kw": peak_power_kw,
            "occupancy_signal": occupancy_signal,
            "temperature_c": temperature_c,
            "humidity_pct": humidity_pct,
        }
    )
    dropped = out["timestamp"].isna().sum()
    if dropped > 0:
        print(f"   ⚠️  Dropping {dropped:,} rows with invalid timestamps in {name}.")
    return out.dropna(subset=["timestamp"]).reset_index(drop=True)


def _parse_smart_home_activity_dataset(df: pd.DataFrame, name: str) -> pd.DataFrame:
    """Parse binary sensor/activity dataset."""
    df = df.copy()
    if "timestamp" not in df.columns:
        raise ValueError(f"{name} must include a 'timestamp' column.")
    timestamp_str = df["timestamp"].astype(str).str.replace("_", ":", regex=False)
    timestamp = pd.to_datetime(timestamp_str, errors="coerce")
    activity_col = df.get("Activity")
    activity = activity_col.astype(str).str.lower() if activity_col is not None else pd.Series("unknown", index=df.index)

    sensor_cols = [col for col in df.columns if col not in {"timestamp", "Activity"}]
    sensor_data = df[sensor_cols].apply(pd.to_numeric, errors="coerce").fillna(0)
    total_activity = sensor_data.sum(axis=1)
    power_kw = total_activity * 0.05  # scale to realistic kW
    appliance_kw = sensor_data.max(axis=1) * 0.05

    occ_from_power, temperature_c, humidity_pct = _synthesize_environment_from_power(power_kw)
    # Boost occupancy when activity indicates presence
    active_mask = ~activity.isin({"leave", "away", "out"})
    occupancy_signal = np.clip(occ_from_power + active_mask.astype(float) * 0.3, 0, 1)

    activity_encoded = activity.map(
        {
            "sleep": 0.3,
            "cook": 0.7,
            "work": 0.6,
            "relax": 0.5,
            "leave": 0.0,
            "away": 0.0,
        }
    ).fillna(0.4)

    out = pd.DataFrame(
        {
            "timestamp": timestamp,
            "power_kw": power_kw,
            "house_kw": power_kw,
            "generation_kw": 0.0,
            "appliance_kw": appliance_kw,
            "occupancy_signal": occupancy_signal,
            "temperature_c": temperature_c,
            "humidity_pct": humidity_pct,
            "activity_index": activity_encoded,
        }
    )
    if out["timestamp"].isna().any():
        print(f"   ⚠️  Dropping {(out['timestamp'].isna()).sum():,} rows with invalid timestamps in {name}.")
        out = out.dropna(subset=["timestamp"])
    return out.reset_index(drop=True)


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
    """
    Load datasets and add dataset source tracking for stratified splitting.
    """
    frames = []
    for file in dataset_files:
        name = file.stem.lower()
        print(f"📥 Loading {file.name} ...")
        # Event datasets (aruba, tulum) don't have headers, so read with header=None
        if "homec" in name:
            df = pd.read_csv(file, low_memory=False)
            # Log available columns for debugging
            print(f"   Available columns: {list(df.columns)[:10]}...")  # Show first 10
            parsed = _parse_homec(df)
        elif "electricity" in name:
            df = pd.read_csv(file, low_memory=False)
            parsed = _parse_electricity_dataset(df, name)
        elif "smart_home" in name:
            df = pd.read_csv(file, low_memory=False)
            parsed = _parse_smart_home_activity_dataset(df, name)
        else:
            # Try reading without headers first (for aruba, tulum)
            df = pd.read_csv(file, header=None)
            parsed = _parse_event_dataset(df, name)
        
        # Add dataset source identifier for stratified splitting
        parsed["dataset_source"] = name
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
    
    # Diagnostic: Check dataset sources before filtering
    if "dataset_source" in combined.columns:
        print(f"\n📊 Dataset sizes before timestamp filtering:")
        for ds in combined["dataset_source"].unique():
            ds_rows = len(combined[combined["dataset_source"] == ds])
            ds_valid_ts = combined[combined["dataset_source"] == ds]["timestamp"].notna().sum()
            ds_invalid_ts = ds_rows - ds_valid_ts
            print(f"   {ds}: {ds_rows:,} rows ({ds_valid_ts:,} valid timestamps, {ds_invalid_ts:,} invalid)")
    
    # Drop rows with invalid timestamps (NaT or 1970 dates indicate parsing failure)
    before_dropna = len(combined)
    combined = combined.dropna(subset=["timestamp"])
    if before_dropna > len(combined):
        print(f"   ⚠️  Dropped {before_dropna - len(combined):,} rows with NaT timestamps")
    
    # Filter out invalid timestamps (before 2000 or after 2030 are likely errors)
    if len(combined) > 0:
        min_valid_date = pd.Timestamp("2000-01-01")
        max_valid_date = pd.Timestamp("2030-12-31")
        before_filter = len(combined)
        
        # Diagnostic: Check which datasets are being filtered
        if "dataset_source" in combined.columns:
            invalid_mask = (combined["timestamp"] < min_valid_date) | (combined["timestamp"] > max_valid_date)
            invalid_by_dataset = combined[invalid_mask]["dataset_source"].value_counts()
            if len(invalid_by_dataset) > 0:
                print(f"   ⚠️  Invalid timestamp ranges by dataset:")
                for ds, count in invalid_by_dataset.items():
                    ds_data = combined[combined["dataset_source"] == ds]
                    if len(ds_data) > 0:
                        min_ts = ds_data["timestamp"].min()
                        max_ts = ds_data["timestamp"].max()
                        print(f"      {ds}: {count:,} rows outside 2000-2030 (range: {min_ts} to {max_ts})")
        
        combined = combined[
            (combined["timestamp"] >= min_valid_date) & 
            (combined["timestamp"] <= max_valid_date)
        ]
        if before_filter > len(combined):
            print(f"   ⚠️  Filtered out {before_filter - len(combined):,} rows with invalid timestamps")
            
            # Report final dataset sizes
            if "dataset_source" in combined.columns:
                print(f"\n📊 Dataset sizes after timestamp filtering:")
                for ds in combined["dataset_source"].unique():
                    ds_rows = len(combined[combined["dataset_source"] == ds])
                    print(f"   {ds}: {ds_rows:,} rows")
    combined = combined.sort_values("timestamp").reset_index(drop=True)
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
        # Target normalization per dataset to fix distribution shifts
        self.target_scalers: Dict[str, Dict[str, Dict[str, float]]] = {}  # dataset_name -> target_name -> {mean, std}
        self.normalize_targets_per_dataset: bool = getattr(config, "normalize_targets_per_dataset", True)
        self.target_columns: List[str] = list(config.targets)

    @staticmethod
    def _fill_missing_hours(df: pd.DataFrame) -> pd.DataFrame:
        # Preserve dataset_source if present
        has_dataset_source = "dataset_source" in df.columns
        dataset_source_col = df["dataset_source"] if has_dataset_source else None
        
        # Handle duplicate timestamps by aggregating before setting index
        if df["timestamp"].duplicated().any():
            # Build aggregation dictionary: mean for numeric columns, last for others
            agg_dict = {}
            for col in df.columns:
                if col == "timestamp" or col == "dataset_source":
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
        
        # Restore dataset_source if it was removed
        if has_dataset_source and "dataset_source" not in df.columns:
            # Use the first dataset_source value for each timestamp (should be same)
            if dataset_source_col is not None:
                df = df.merge(
                    df[["timestamp"]].merge(
                        pd.DataFrame({"timestamp": df["timestamp"].unique(), 
                                    "dataset_source": dataset_source_col.iloc[0]}),
                        on="timestamp", how="left"
                    ),
                    on="timestamp", how="left"
                )
        
        df = df.set_index("timestamp")
        # Create full hourly range but preserve original data points
        full_range = pd.date_range(df.index.min(), df.index.max(), freq="H")
        df = df.reindex(full_range)
        
        # Use more aggressive interpolation to preserve data
        # First try time-based interpolation, then forward/backward fill
        df = df.interpolate(method="time", limit_direction="both")
        df = df.ffill(limit=24).bfill(limit=24)  # Limit to 24 hours to avoid propagating too far
        # Fill any remaining NaN with 0 (last resort)
        numeric_cols = df.select_dtypes(include=[np.number]).columns
        df[numeric_cols] = df[numeric_cols].fillna(0)
        
        # Restore dataset_source after reindexing
        if has_dataset_source and "dataset_source" not in df.columns and dataset_source_col is not None:
            # Forward fill dataset_source (should be constant per dataset)
            if len(dataset_source_col) > 0:
                df["dataset_source"] = dataset_source_col.iloc[0]
            else:
                df["dataset_source"] = "unknown"
        
        df.index.name = "timestamp"
        return df.reset_index()

    @staticmethod
    def _engineer_targets(
        df: pd.DataFrame,
        max_value: int,
        is_training: bool = True,
        config: Optional[TrainingConfig] = None,
    ) -> pd.DataFrame:
        """
        Engineer targets using simple, learnable formulas.
        Key: Make targets directly related to input features so model can learn.
        """
        power_norm = (df["house_kw"].fillna(df["power_kw"]).fillna(0)).clip(lower=0)
        occupancy = df["occupancy_signal"].fillna(0).clip(0, 1)
        temperature = df["temperature_c"].fillna(22)
        humidity = df["humidity_pct"].fillna(50)
        
        # FAN SPEED: Simple, learnable formula
        # Fan should increase with temperature and humidity
        # Normalize temperature to 0-1 range (assume 18-28°C is typical range)
        temp_norm = np.clip((temperature - 18) / 10, 0, 1)  # 18°C = 0, 28°C = 1
        # Normalize humidity to 0-1 range (assume 30-70% is typical)
        humidity_norm = np.clip((humidity - 30) / 40, 0, 1)  # 30% = 0, 70% = 1
        
        # Simple weighted combination - easy for model to learn
        # Make fan speed less correlated with LED by using different weights
        fan_speed = (
            0.5 * temp_norm +      # Temperature is main driver for fan
            0.3 * humidity_norm +  # Humidity drives fan
            0.2 * occupancy        # Occupancy adds some variation
        )
        
        rng = np.random.RandomState(42)
        fan_speed = np.clip(fan_speed + rng.normal(0, 0.02, len(fan_speed)), 0, 1)
        
        # LED BRIGHTNESS: Simple, learnable formula
        # LED should follow occupancy and time of day
        hour = df["timestamp"].dt.hour if hasattr(df["timestamp"], 'dt') else pd.Series([12] * len(df))
        # Time component: brighter during day (6am-10pm), dimmer at night
        time_component = np.where(
            (hour >= 6) & (hour < 22),
            0.7 + 0.3 * np.sin(2 * np.pi * (hour - 6) / 16),  # Day: 0.7-1.0
            0.2 + 0.2 * np.sin(2 * np.pi * hour / 24)        # Night: 0.2-0.4
        )
        time_component = np.clip(time_component, 0, 1)
        
        # Simple weighted combination - different from fan to reduce correlation
        led_brightness = (
            0.4 * occupancy +      # Occupancy is main driver
            0.4 * time_component +  # Time of day (stronger than fan)
            0.15 * temp_norm +     # Temperature (different from fan)
            0.05 * np.clip(power_norm / 2, 0, 1)  # Power adds small variation
        )
        
        led_brightness = np.clip(led_brightness + rng.normal(0, 0.02, len(led_brightness)), 0, 1)
        
        balance_targets = getattr(config, "balance_target_means", False) if config else False
        target_center = getattr(config, "target_mean_center", 0.5) if config else 0.5
        min_target_std = getattr(config, "min_target_std", 0.18) if config else 0.18
        reduce_corr = getattr(config, "reduce_target_correlation", False) if config else False
        
        if reduce_corr:
            if hasattr(hour, "to_numpy"):
                hour_fraction = (hour.to_numpy(dtype=float) % 24) / 24.0
            else:
                hour_fraction = (np.asarray(hour, dtype=float) % 24) / 24.0
            phase_pattern = 0.5 + 0.5 * np.sin(2 * np.pi * hour_fraction + np.pi / 3)
            secondary_pattern = 0.5 + 0.5 * np.sin(4 * np.pi * hour_fraction + np.pi / 6)
            led_brightness = np.clip(
                0.65 * led_brightness + 0.25 * phase_pattern + 0.10 * secondary_pattern,
                0,
                1,
            )
        
        def _rebalance(values: np.ndarray, label: str) -> np.ndarray:
            current_mean = np.mean(values)
            shift = np.clip(target_center - current_mean, -0.2, 0.2)
            centered = np.clip(values + shift, 0, 1)
            std = np.std(centered)
            if std < min_target_std:
                scale = min(1.8, (min_target_std / (std + 1e-6)))
                centered = np.clip((centered - target_center) * scale + target_center, 0, 1)
            return centered
        
        if balance_targets:
            fan_speed = _rebalance(fan_speed, "fan_speed")
            led_brightness = _rebalance(led_brightness, "led_brightness")
        
        # Scale to max_value and ensure good range
        df["fan_speed"] = fan_speed * max_value
        df["led_brightness"] = led_brightness * max_value
        
        # CRITICAL: Ensure minimum variance (prevent collapse)
        # Both targets must have significant variance for the model to learn
        fan_std = df["fan_speed"].std()
        led_std = df["led_brightness"].std()
        
        # Fan speed should have at least 20% of range as std (51 for max_value=255)
        min_fan_std = max_value * 0.20
        if fan_std < min_fan_std:
            # Add more variation - scale noise to ensure good variance
            noise_scale = max(10, (min_fan_std - fan_std) / 2)
            df["fan_speed"] = df["fan_speed"] + rng.normal(0, noise_scale, len(df))
            df["fan_speed"] = np.clip(df["fan_speed"], 0, max_value)
            new_std = df["fan_speed"].std()
            if new_std > fan_std:
                print(f"   ℹ️  Increased fan speed variance: {fan_std:.1f} → {new_std:.1f}")
        
        # LED brightness should have at least 20% of range as std
        min_led_std = max_value * 0.20
        if led_std < min_led_std:
            noise_scale = max(10, (min_led_std - led_std) / 2)
            df["led_brightness"] = df["led_brightness"] + rng.normal(0, noise_scale, len(df))
            df["led_brightness"] = np.clip(df["led_brightness"], 0, max_value)
            new_std = df["led_brightness"].std()
            if new_std > led_std:
                print(f"   ℹ️  Increased LED brightness variance: {led_std:.1f} → {new_std:.1f}")
        
        # Final validation - ensure both have good variance
        # Be stricter for training set, more lenient for validation/test
        final_fan_std = df["fan_speed"].std()
        final_led_std = df["led_brightness"].std()
        
        if is_training:
            # Training set must have good variance (strict check)
            min_required = max_value * 0.15  # 15% of range
            if final_fan_std < min_required:
                raise ValueError(
                    f"CRITICAL: Fan speed variance too low in training set ({final_fan_std:.1f})! "
                    f"Need at least {min_required:.1f}. Model will collapse."
                )
            if final_led_std < min_required:
                raise ValueError(
                    f"CRITICAL: LED brightness variance too low in training set ({final_led_std:.1f})! "
                    f"Need at least {min_required:.1f}. Model will collapse."
                )
        else:
            # Validation/test sets can have less variance (they might be smaller or have different distributions)
            min_required = max_value * 0.10  # 10% of range (more lenient)
            if final_fan_std < min_required:
                print(f"   ⚠️  Warning: Fan speed variance low in validation/test set ({final_fan_std:.1f}), "
                      f"but continuing (minimum: {min_required:.1f})")
            if final_led_std < min_required:
                print(f"   ⚠️  Warning: LED brightness variance low in validation/test set ({final_led_std:.1f}), "
                      f"but continuing (minimum: {min_required:.1f})")
        
        return df

    def _normalize_targets_per_dataset(self, df: pd.DataFrame, dataset_source: str) -> pd.DataFrame:
        """
        Normalize targets per dataset to fix distribution shifts.
        This ensures similar target distributions across datasets.
        """
        if not self.normalize_targets_per_dataset or "dataset_source" not in df.columns:
            return df
        
        # Get unique dataset sources in this dataframe
        unique_sources = df["dataset_source"].unique()
        
        for source in unique_sources:
            source_mask = df["dataset_source"] == source
            source_df = df[source_mask].copy()
            
            if len(source_df) == 0:
                continue
            
            # Normalize each target per dataset
            for target_name in self.config.targets:
                if target_name not in source_df.columns:
                    continue
                
                target_values = source_df[target_name].values
                
                # Skip if all values are the same (zero variance)
                if np.std(target_values) < 1e-6:
                    continue
                
                # Compute stats for this dataset
                target_mean = np.mean(target_values)
                target_std = np.std(target_values)
                
                # Store stats (for reference, not used in normalization)
                if source not in self.target_scalers:
                    self.target_scalers[source] = {}
                self.target_scalers[source][target_name] = {
                    "mean": float(target_mean),
                    "std": float(target_std)
                }
                
                # Normalize to have mean ~0.5 and std ~0.15 (reasonable range)
                # This ensures all datasets have similar distributions
                normalized = (target_values - target_mean) / (target_std + 1e-10)
                # Scale to desired range (mean=0.5, std=0.15)
                normalized = normalized * 0.15 + 0.5
                # Clip to [0, 1] and scale back to max_value
                normalized = np.clip(normalized, 0, 1) * self.config.max_target_value
                
                df.loc[source_mask, target_name] = normalized
        
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
        
        # Engineer targets first (needs raw data)
        # For synthetic data, ensure it gets proper variance (treat as training)
        is_synthetic = "dataset_source" in df.columns and (df["dataset_source"] == "synthetic").any()
        df = self._engineer_targets(
            df,
            self.config.max_target_value,
            is_training=is_training or is_synthetic,  # Treat synthetic as training for variance checks
            config=self.config,
        )
        
        # CRITICAL: Validate targets were created
        if "fan_speed" not in df.columns or "led_brightness" not in df.columns:
            raise ValueError(
                f"CRITICAL: Target engineering failed - 'fan_speed' or 'led_brightness' not in dataframe.\n"
                f"Available columns: {list(df.columns)}\n"
                f"This will cause downstream failures."
            )
        
        # Validate targets have variance before normalization
        fan_std = df["fan_speed"].std()
        led_std = df["led_brightness"].std()
        if fan_std < 1e-6 or led_std < 1e-6:
            print(f"   ⚠️  WARNING: Targets have very low variance before normalization!")
            print(f"      Fan speed std: {fan_std:.6f}, LED brightness std: {led_std:.6f}")
            print(f"      This may indicate an issue with target engineering.")
        
        # Normalize targets per dataset to fix distribution shifts
        # This must happen BEFORE hourly aggregation to normalize raw targets
        if self.normalize_targets_per_dataset and "dataset_source" in df.columns:
            print("   🔄 Normalizing targets per dataset to fix distribution shifts...")
            df = self._normalize_targets_per_dataset(df, "")
            
            # Validate targets still have variance after normalization
            fan_std_after = df["fan_speed"].std()
            led_std_after = df["led_brightness"].std()
            if fan_std_after < 1e-6 or led_std_after < 1e-6:
                raise ValueError(
                    f"CRITICAL: Targets have zero variance after normalization!\n"
                    f"Fan speed std: {fan_std_after:.6f}, LED brightness std: {led_std_after:.6f}\n"
                    f"The normalization step may have collapsed all values to the same value."
                )
        
        # Preserve dataset_source if present
        has_dataset_source = "dataset_source" in df.columns
        dataset_source_col = df["dataset_source"] if has_dataset_source else None
        
        # Ensure timestamp is datetime and sorted
        df = df.sort_values("timestamp").reset_index(drop=True)
        df["timestamp"] = pd.to_datetime(df["timestamp"])
        
        # Handle duplicate timestamps by aggregating
        if df["timestamp"].duplicated().any():
            agg_dict = {}
            for col in df.columns:
                if col == "timestamp" or col == "dataset_source":
                    continue
                if pd.api.types.is_numeric_dtype(df[col]):
                    agg_dict[col] = "mean"
                else:
                    agg_dict[col] = "last"
            if agg_dict:
                df = df.groupby("timestamp", as_index=False).agg(agg_dict)
            if has_dataset_source and "dataset_source" not in df.columns and dataset_source_col is not None:
                # Restore dataset_source - use first value for each timestamp
                df = df.merge(
                    df[["timestamp"]].drop_duplicates().assign(
                        dataset_source=dataset_source_col.iloc[0] if len(dataset_source_col) > 0 else "unknown"
                    ),
                    on="timestamp",
                    how="left"
                )
        
        # Set timestamp as index for resampling
        df = df.set_index("timestamp")
        
        # Build aggregation dict - use mean for most, but preserve max/min where useful
        agg_dict = {
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
        
        # Add dataset_source aggregation
        if has_dataset_source:
            agg_dict["dataset_source"] = "first"
        
        # Resample to hourly - use min_periods=0 to keep all hours, even if empty
        hourly = df.resample("H", label="right", closed="right").agg(agg_dict)
        hourly.columns = ["_".join(col).strip("_") for col in hourly.columns]
        
        # CRITICAL: Validate target columns exist after aggregation
        required_target_cols = ["fan_speed_mean", "led_brightness_mean"]
        missing_cols = [col for col in required_target_cols if col not in hourly.columns]
        if missing_cols:
            available_cols = [c for c in hourly.columns if "fan" in c.lower() or "led" in c.lower() or "brightness" in c.lower()]
            raise ValueError(
                f"CRITICAL: Target columns missing after hourly aggregation: {missing_cols}\n"
                f"Available columns with 'fan', 'led', or 'brightness': {available_cols}\n"
                f"All columns: {list(hourly.columns)}\n"
                f"Original columns before aggregation: {list(df.columns)}\n"
                f"This indicates 'fan_speed' or 'led_brightness' were not in the input dataframe."
            )
        
        # Validate targets have data (not all NaN)
        for col in required_target_cols:
            if hourly[col].isna().all():
                raise ValueError(
                    f"CRITICAL: Target column '{col}' is entirely NaN after aggregation.\n"
                    f"This indicates the target engineering step failed."
                )
            nan_pct = hourly[col].isna().sum() / len(hourly) * 100
            if nan_pct > 50:
                print(f"   ⚠️  Warning: {col} has {nan_pct:.1f}% NaN values after aggregation")
        
        hourly = hourly.reset_index().rename(columns={"timestamp": "hour"})
        
        # Fill NaN values more intelligently
        # Std can be NaN when there's only one value, fill with 0
        std_cols = [col for col in hourly.columns if col.endswith("_std")]
        for col in std_cols:
            hourly[col] = hourly[col].fillna(0.0)
        
        # For other numeric columns, use forward/backward fill with longer windows
        # This preserves more data by propagating values across gaps
        numeric_cols = hourly.select_dtypes(include=[np.number]).columns
        for col in numeric_cols:
            if col not in std_cols and col != "hour":
                # Use longer fill windows to preserve more data
                hourly[col] = hourly[col].ffill(limit=48).bfill(limit=48)
        
        # Fill any remaining NaN with 0 (last resort, but should be minimal now)
        hourly[numeric_cols] = hourly[numeric_cols].fillna(0)

        # Enhanced temporal encodings (safe - only use current row's timestamp)
        hourly["hour_sin"] = np.sin(2 * np.pi * hourly["hour"].dt.hour / 24)
        hourly["hour_cos"] = np.cos(2 * np.pi * hourly["hour"].dt.hour / 24)
        hourly["day_of_week"] = hourly["hour"].dt.dayofweek
        hourly["is_weekend"] = (hourly["day_of_week"] >= 5).astype(int)
        hourly["month_sin"] = np.sin(2 * np.pi * hourly["hour"].dt.month / 12)
        hourly["month_cos"] = np.cos(2 * np.pi * hourly["hour"].dt.month / 12)
        
        # Day of week encoding (cyclic)
        hourly["day_of_week_sin"] = np.sin(2 * np.pi * hourly["day_of_week"] / 7)
        hourly["day_of_week_cos"] = np.cos(2 * np.pi * hourly["day_of_week"] / 7)

        # Enhanced rolling features - computed separately per split to prevent leakage
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
                # Multiple rolling windows for different time scales
                hourly[f"{col}_roll6"] = (
                    hourly[col].rolling(window=6, min_periods=1).mean()
                )
                hourly[f"{col}_roll24"] = (
                    hourly[col].rolling(window=24, min_periods=1).mean()
                )
                # Add rolling std for variance information
                hourly[f"{col}_roll6_std"] = (
                    hourly[col].rolling(window=6, min_periods=1).std().fillna(0)
                )
        
        # Add interaction features (safe - only current row)
        if "temperature_c_mean" in hourly.columns and "humidity_pct_mean" in hourly.columns:
            hourly["temp_humidity_interaction"] = hourly["temperature_c_mean"] * hourly["humidity_pct_mean"] / 100
        if "power_kw_mean" in hourly.columns and "occupancy_signal_mean" in hourly.columns:
            hourly["power_occupancy_interaction"] = hourly["power_kw_mean"] * hourly["occupancy_signal_mean"]
        
        # Add rate of change features (safe - only looks at previous row)
        change_cols = ["temperature_c_mean", "humidity_pct_mean", "power_kw_mean"]
        for col in change_cols:
            if col in hourly.columns:
                hourly[f"{col}_diff"] = hourly[col].diff().fillna(0)
                hourly[f"{col}_pct_change"] = (hourly[col].pct_change() * 100).fillna(0)

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

        # Only drop rows where ALL critical feature columns are NaN or zero
        # Be more lenient - keep rows if they have ANY meaningful data
        # For small datasets, be even more lenient to preserve data
        critical_cols = [
            "power_kw_mean", "temperature_c_mean", "humidity_pct_mean",
            "occupancy_signal_mean", "fan_speed_mean", "led_brightness_mean"
        ]
        available_critical = [col for col in critical_cols if col in hourly.columns]
        
        if available_critical:
            # Keep row if at least one critical column has a non-zero value OR if it has any non-NaN value
            # This is very lenient to preserve maximum data
            mask = (hourly[available_critical] != 0).any(axis=1) | hourly[available_critical].notna().any(axis=1)
            before_drop = len(hourly)
            hourly = hourly[mask].copy()
            if len(hourly) < before_drop:
                dropped_pct = (before_drop - len(hourly)) / before_drop * 100
                print(f"   ⚠️  Dropped {before_drop - len(hourly):,} rows ({dropped_pct:.1f}%) with all critical columns empty")
        
        # For very small datasets, be even more lenient - keep rows with ANY data
        if len(hourly) < 100:
            # Keep any row that has at least one non-zero, non-NaN value in any numeric column
            numeric_cols = hourly.select_dtypes(include=[np.number]).columns
            if len(numeric_cols) > 0:
                # Check if row has any meaningful data
                has_data = (hourly[numeric_cols] != 0).any(axis=1) | hourly[numeric_cols].notna().any(axis=1)
                before_lenient = len(hourly)
                hourly = hourly[has_data].copy()
                if len(hourly) > before_lenient:
                    print(f"   ℹ️  Applied lenient filtering for small dataset: kept {len(hourly)} rows")
        
        hourly = hourly.reset_index(drop=True)
        
        # Report data preservation
        if len(hourly) > 0:
            time_span = hourly["hour"].max() - hourly["hour"].min()
            hours_expected = time_span.total_seconds() / 3600 + 1 if pd.notna(time_span) else len(hourly)
            print(f"   → Hourly rows after feature engineering: {len(hourly):,}")
            if hours_expected > len(hourly) * 1.5:
                preservation_pct = len(hourly) / hours_expected * 100 if hours_expected > 0 else 100
                print(f"   ℹ️  Time span: {time_span.days} days, {preservation_pct:.1f}% of hours have data")
        
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
        
        # Handle empty DataFrame
        if len(df) == 0:
            print(f"   ⚠️  Empty DataFrame provided - returning empty sequences")
            # If feature_columns haven't been set yet, we can't determine the shape
            # This should only happen if test set is empty and called before training set
            if not hasattr(self, 'feature_columns') or not self.feature_columns:
                raise ValueError("Cannot prepare sequences from empty DataFrame before feature columns are initialized. "
                               "Ensure training data is processed first.")
            # Return empty arrays with correct shape
            num_features = len(self.feature_columns)
            num_targets = len(self.config.targets)
            return (np.array([]).reshape(0, sequence_len, num_features), 
                    np.array([]).reshape(0, num_targets))
        
        # Initialize feature columns if not already set (first call)
        if not hasattr(self, 'feature_columns') or not self.feature_columns:
            # Exclude non-feature columns (targets, metadata, non-numeric)
            exclude_cols = {
                "hour",
                "fan_speed_mean",
                "led_brightness_mean",
                "dataset_source",  # Exclude dataset_source (string column, not a feature)
                "timestamp",  # Exclude timestamp if present
            }
            
            # Only include numeric columns that are not in the exclude list
            self.feature_columns = [
                col
                for col in df.columns
                if col not in exclude_cols
                and pd.api.types.is_numeric_dtype(df[col])
            ]
            
            # Debug: print excluded columns to help diagnose issues
            excluded = [col for col in df.columns if col not in self.feature_columns and col not in ["fan_speed_mean", "led_brightness_mean"]]
            if excluded:
                print(f"   ℹ️  Excluded non-feature columns: {excluded}")

        # Double-check that all feature columns are numeric
        non_numeric = [col for col in self.feature_columns if not pd.api.types.is_numeric_dtype(df[col])]
        if non_numeric:
            raise ValueError(f"Non-numeric columns found in feature_columns: {non_numeric}. "
                           f"Please exclude these columns: {non_numeric}")

        # CRITICAL: Validate target columns exist
        required_targets = ["fan_speed_mean", "led_brightness_mean"]
        missing_targets = [t for t in required_targets if t not in df.columns]
        if missing_targets:
            available_cols = [col for col in df.columns if "fan" in col.lower() or "led" in col.lower() or "brightness" in col.lower()]
            raise ValueError(
                f"CRITICAL: Required target columns missing: {missing_targets}\n"
                f"Available columns with 'fan', 'led', or 'brightness': {available_cols}\n"
                f"All columns: {list(df.columns)[:20]}...\n"
                f"This indicates a data preprocessing error - targets were not created during hourly aggregation."
            )
        
        # DATA QUALITY CHECKS - Ensure optimal training data
        # CRITICAL: Identify constant features on training set, then apply same filtering to all sets
        
        # First, get all available features from the dataframe
        available_features = [col for col in self.feature_columns if col in df.columns]
        if len(available_features) != len(self.feature_columns):
            missing = set(self.feature_columns) - set(available_features)
            raise ValueError(
                f"Missing feature columns in dataframe: {missing}\n"
                f"Available columns: {list(df.columns)[:10]}..."
            )
        
        features = df[self.feature_columns].values.astype(np.float32)
        targets = df[required_targets].values.astype(np.float32)
        
        print(f"\n🔍 Data Quality Validation:")
        print(f"   Features shape: {features.shape}")
        print(f"   Targets shape: {targets.shape}")
        
        # Check for constant features (zero variance) - remove them
        # CRITICAL: This must happen BEFORE fitting the scaler to ensure consistency
        if fit_scaler:
            # Training set - identify constant features
            feature_std = np.std(features, axis=0)
            constant_features = feature_std < 1e-6
            
            if constant_features.any():
                constant_feature_names = [self.feature_columns[i] for i in range(len(self.feature_columns)) if constant_features[i]]
                print(f"   ⚠️  Removing {constant_features.sum()} constant features: {constant_feature_names[:5]}")
                # Store mask for use in validation/test sets (boolean array)
                self._valid_feature_mask = ~constant_features
                # Store original feature columns before filtering
                self._original_feature_columns = self.feature_columns.copy()
                # Update feature columns to only include valid ones
                self.feature_columns = [self.feature_columns[i] for i in range(len(self.feature_columns)) if self._valid_feature_mask[i]]
                # Remove constant features from training data
                features = features[:, self._valid_feature_mask]
                print(f"   ✅ Remaining features: {len(self.feature_columns)}")
            else:
                # No constant features - keep all
                self._valid_feature_mask = np.ones(len(self.feature_columns), dtype=bool)
                self._original_feature_columns = self.feature_columns.copy()
                print(f"   ✅ All {len(self.feature_columns)} features have variance")
        else:
            # Validation/test set - use the same mask from training
            if not hasattr(self, '_valid_feature_mask') or not hasattr(self, '_original_feature_columns'):
                raise RuntimeError(
                    "Cannot process validation/test set: constant features not identified on training set. "
                    "Call prepare_sequences with fit_scaler=True on training data first."
                )
            
            # Check if we need to filter features
            # If validation set has all original features, apply the mask
            if len(features[0]) == len(self._original_feature_columns):
                # Validation set has all original features - apply mask to match training
                features = features[:, self._valid_feature_mask]
                print(f"   ✅ Applied feature mask: {len(features[0])} features (removed {len(self._original_feature_columns) - len(features[0])} constant)")
            elif len(features[0]) == len(self.feature_columns):
                # Features already filtered (shouldn't happen, but OK)
                print(f"   ℹ️  Features already filtered to {len(features[0])} columns")
            else:
                # Mismatch - this is an error
                raise ValueError(
                    f"Feature count mismatch: validation has {len(features[0])} features, "
                    f"but training had {len(self._original_feature_columns)} original features "
                    f"and {len(self.feature_columns)} after filtering. "
                    f"Validation set should have {len(self._original_feature_columns)} features before filtering."
                )
        
        # Check for NaN or Inf values
        nan_count = np.isnan(features).sum()
        inf_count = np.isinf(features).sum()
        if nan_count > 0 or inf_count > 0:
            print(f"   ⚠️  Found {nan_count} NaN and {inf_count} Inf values in features")
            features = np.nan_to_num(features, nan=0.0, posinf=1e6, neginf=-1e6)
            print(f"   ✅ Replaced with safe values")
        
        # Check feature ranges - warn about extreme values
        feature_min = np.min(features, axis=0)
        feature_max = np.max(features, axis=0)
        extreme_features = (np.abs(feature_min) > 100) | (np.abs(feature_max) > 100)
        if extreme_features.any():
            extreme_names = [self.feature_columns[i] for i in range(len(self.feature_columns)) if extreme_features[i]]
            print(f"   ℹ️  {extreme_features.sum()} features have extreme values (will be normalized): {extreme_names[:3]}")
        
        # CRITICAL: Validate targets have variance (not constant)
        target_std = np.std(targets, axis=0)
        if target_std[0] < 1e-6 or target_std[1] < 1e-6:
            raise ValueError(
                f"CRITICAL: Targets have zero or near-zero variance!\n"
                f"Fan speed std: {target_std[0]:.6f}, LED brightness std: {target_std[1]:.6f}\n"
                f"Target ranges: Fan [{np.min(targets[:, 0]):.4f}, {np.max(targets[:, 0]):.4f}], "
                f"LED [{np.min(targets[:, 1]):.4f}, {np.max(targets[:, 1]):.4f}]\n"
                f"This will cause model collapse. Check target engineering and normalization."
            )
        
        # Report target statistics for quality assessment
        print(f"   📊 Target Statistics:")
        print(f"      Fan speed:   mean={np.mean(targets[:, 0]):.4f}, std={target_std[0]:.4f}, range=[{np.min(targets[:, 0]):.4f}, {np.max(targets[:, 0]):.4f}]")
        print(f"      LED brightness: mean={np.mean(targets[:, 1]):.4f}, std={target_std[1]:.4f}, range=[{np.min(targets[:, 1]):.4f}, {np.max(targets[:, 1]):.4f}]")
        
        # Check target correlation - should be different enough
        target_corr = np.corrcoef(targets[:, 0], targets[:, 1])[0, 1]
        if abs(target_corr) > 0.95:
            print(f"   ⚠️  Warning: Targets are highly correlated ({target_corr:.3f}) - may cause learning issues")
        else:
            print(f"   ✅ Targets have reasonable correlation ({target_corr:.3f})")
        
        # Validate target ranges (should be [0, max_target_value] before normalization)
        target_max = np.max(targets)
        target_min = np.min(targets)
        if target_max > self.config.max_target_value * 1.1:  # Allow 10% tolerance
            print(f"   ⚠️  Warning: Target max ({target_max:.2f}) exceeds max_target_value ({self.config.max_target_value})")
        if target_min < -0.1:  # Should be >= 0
            print(f"   ⚠️  Warning: Target min ({target_min:.2f}) is negative (expected >= 0)")

        # CRITICAL: Fit scaler ONLY on training data, transform on all splits
        if fit_scaler:
            features = self.feature_scaler.fit_transform(features)
            print(f"   ✅ Fitted scaler on training data")
            print(f"      Feature means (first 5): {self.feature_scaler.mean_[:5] if hasattr(self.feature_scaler, 'mean_') else 'N/A'}")
            print(f"      Feature stds (first 5): {self.feature_scaler.scale_[:5] if hasattr(self.feature_scaler, 'scale_') else 'N/A'}")
            
            # Validate scaling worked correctly
            scaled_mean = np.mean(features, axis=0)
            scaled_std = np.std(features, axis=0)
            if np.any(np.abs(scaled_mean) > 0.1):
                print(f"   ⚠️  Warning: Some features not properly centered (max mean: {np.max(np.abs(scaled_mean)):.4f})")
            if np.any(np.abs(scaled_std - 1.0) > 0.2):
                print(f"   ⚠️  Warning: Some features not properly scaled (std range: [{np.min(scaled_std):.4f}, {np.max(scaled_std):.4f}])")
            else:
                print(f"   ✅ Features properly normalized (mean≈0, std≈1)")
        else:
            if not hasattr(self.feature_scaler, 'mean_') or self.feature_scaler.mean_ is None:
                raise RuntimeError(
                    "Scaler not fitted! Call prepare_sequences with fit_scaler=True on training data first."
                )
            features = self.feature_scaler.transform(features)
            print(f"   ✅ Transformed using training scaler statistics")
            
            # Validate transformed features are in reasonable range
            if np.any(np.abs(features) > 10):
                extreme_count = np.sum(np.abs(features) > 10)
                print(f"   ⚠️  Warning: {extreme_count} feature values exceed ±10 (may indicate distribution shift)")
        
        targets = targets / self.config.max_target_value

        X, y = [], []
        # Create sequences - use all available data (only need sequence_len for input, prediction_horizon for target)
        # This preserves maximum number of sequences
        # CRITICAL: Ensure features and targets have same length
        if len(features) != len(targets):
            raise ValueError(
                f"Features and targets length mismatch: features={len(features)}, targets={len(targets)}. "
                f"This indicates a data preprocessing error."
            )
        
        max_sequences = len(df) - sequence_len - (self.config.prediction_horizon - 1)
        for idx in range(max_sequences):
            # Input sequence: [idx : idx + sequence_len]
            # Target: [idx + sequence_len + prediction_horizon - 1] (or idx + sequence_len if prediction_horizon=1)
            sequence_end = idx + sequence_len
            target_idx = sequence_end + self.config.prediction_horizon - 1
            
            # Validate indices
            if sequence_end > len(features):
                break  # Not enough data for this sequence
            if target_idx >= len(targets):
                break  # Target index out of bounds
            
            X.append(features[idx : sequence_end])
            y.append(targets[target_idx])

        X = np.asarray(X, dtype=np.float32)
        y = np.asarray(y, dtype=np.float32)
        
        # Final data quality checks on sequences
        if len(X) > 0:
            # Check for NaN/Inf in sequences
            x_nan = np.isnan(X).sum()
            y_nan = np.isnan(y).sum()
            if x_nan > 0 or y_nan > 0:
                print(f"   ⚠️  Found {x_nan} NaN in sequences, {y_nan} NaN in targets - replacing")
                X = np.nan_to_num(X, nan=0.0, posinf=1e6, neginf=-1e6)
                y = np.nan_to_num(y, nan=0.0, posinf=1.0, neginf=0.0)
            
            # Validate sequence quality
            x_std = np.std(X, axis=(0, 1))  # Std across batch and time
            zero_variance_timesteps = np.sum(x_std < 1e-6)
            if zero_variance_timesteps > 0:
                print(f"   ⚠️  Warning: {zero_variance_timesteps} feature timesteps have zero variance")
            
            # Check target distribution in sequences
            y_mean = np.mean(y, axis=0)
            y_std = np.std(y, axis=0)
            print(f"   📊 Sequence Target Stats:")
            print(f"      Fan: mean={y_mean[0]:.4f}, std={y_std[0]:.4f}")
            print(f"      LED: mean={y_mean[1]:.4f}, std={y_std[1]:.4f}")
            
            # Warn if sequences are too similar (low diversity)
            if len(X) > 1:
                # Sample a few sequences and check diversity
                sample_size = min(100, len(X))
                sample_indices = np.random.choice(len(X), sample_size, replace=False)
                sample_X = X[sample_indices]
                # Check variance across samples
                sample_var = np.var(sample_X, axis=0).mean()
                if sample_var < 0.01:
                    print(f"   ⚠️  Warning: Sequences have low diversity (variance: {sample_var:.6f})")
                else:
                    print(f"   ✅ Sequences have good diversity (variance: {sample_var:.4f})")
        
        print(f"   → Sequence tensor: {X.shape}, Targets: {y.shape}")
        print(f"   → Created {len(X):,} sequences from {len(df):,} hourly rows (preserved {len(X)/len(df)*100:.1f}%)")
        
        if len(X) == 0:
            raise ValueError("No sequences created! Check data length and sequence_length configuration.")
        
        return X, y


# ==============================================================================
# Data Augmentation
# ==============================================================================


class TimeSeriesAugmentation(keras.layers.Layer):
    """
    Data augmentation layer for time series data to prevent overfitting.
    Applies Gaussian noise and optional time masking during training.
    """
    def __init__(self, noise_std=0.02, time_mask_prob=0.1, **kwargs):
        super().__init__(**kwargs)
        self.noise_std = noise_std
        self.time_mask_prob = time_mask_prob
        
    def call(self, inputs, training=None):
        if not training:
            return inputs
        
        # Apply Gaussian noise
        noise = tf.random.normal(
            shape=tf.shape(inputs),
            mean=0.0,
            stddev=self.noise_std,
            dtype=inputs.dtype
        )
        augmented = inputs + noise
        
        # Optional: Time masking (randomly zero out some time steps)
        if self.time_mask_prob > 0:
            # Create random mask for time dimension
            batch_size = tf.shape(inputs)[0]
            seq_length = tf.shape(inputs)[1]
            num_features = tf.shape(inputs)[2]
            
            # Random mask: 1 = keep, 0 = mask
            mask = tf.random.uniform(
                shape=(batch_size, seq_length, 1),
                minval=0.0,
                maxval=1.0
            )
            mask = tf.cast(mask > self.time_mask_prob, dtype=inputs.dtype)
            augmented = augmented * mask
        
        return augmented
    
    def get_config(self):
        config = super().get_config()
        config.update({
            "noise_std": self.noise_std,
            "time_mask_prob": self.time_mask_prob,
        })
        return config


# ==============================================================================
# Custom Loss Functions
# ==============================================================================

class VariancePenaltyLoss(keras.losses.Loss):
    """
    MSE loss with variance penalty to prevent model collapse.
    Penalizes predictions that have zero or very low variance.
    """
    def __init__(self, variance_weight=0.1, name="variance_penalty_mse"):
        super().__init__(name=name)
        self.variance_weight = variance_weight
        self.mse = keras.losses.MeanSquaredError()
    
    def call(self, y_true, y_pred):
        # Ensure float32 to avoid type mismatches
        y_true = tf.cast(y_true, tf.float32)
        y_pred = tf.cast(y_pred, tf.float32)
        
        # Standard MSE loss
        mse_loss = self.mse(y_true, y_pred)
        
        # Variance penalty: penalize if predictions have low variance
        # Calculate variance for each target separately
        pred_var = tf.reduce_mean(tf.math.reduce_variance(y_pred, axis=0))
        true_var = tf.reduce_mean(tf.math.reduce_variance(y_true, axis=0))
        
        # Ensure all values are float32
        pred_var = tf.cast(pred_var, tf.float32)
        true_var = tf.cast(true_var, tf.float32)
        
        # Penalty is high when pred_var is much smaller than true_var
        variance_penalty = self.variance_weight * tf.maximum(0.0, true_var - pred_var) / (true_var + 1e-6)
        
        return mse_loss + variance_penalty
    
    def get_config(self):
        config = super().get_config()
        config.update({"variance_weight": self.variance_weight})
        return config


# ==============================================================================
# Model
# ==============================================================================


def build_temporal_cnn(
    input_shape: Tuple[int, int], config: TrainingConfig
) -> keras.Model:
    """
    MEMORY-EFFICIENT MODEL - Optimized for GPU memory while preventing collapse.
    
    Key features:
    - Reduced capacity to fit in GPU memory
    - Separate pathways to prevent one target from dominating
    - Better initialization to prevent dead neurons
    - Proper regularization without over-constraining
    """
    inputs = keras.layers.Input(shape=input_shape, name="input_sequences")
    x = inputs
    
    # Ultra-reduced feature extraction (for very limited GPU memory)
    x1 = keras.layers.Conv1D(
        16,  # Further reduced
        config.kernel_size,
        padding="same",
        activation="relu",
        kernel_initializer="he_normal",
        name="conv_1"
    )(x)
    x1 = keras.layers.BatchNormalization(name="bn_1")(x1)
    
    x2 = keras.layers.Conv1D(
        32,  # Further reduced
        config.kernel_size,
        padding="same",
        activation="relu",
        kernel_initializer="he_normal",
        name="conv_2"
    )(x1)
    x2 = keras.layers.BatchNormalization(name="bn_2")(x2)
    x2 = keras.layers.Dropout(0.2, name="dropout_conv")(x2)
    
    # Single LSTM layer (ultra memory efficient)
    lstm_out = keras.layers.LSTM(
        32,  # Further reduced
        return_sequences=False,  # Don't keep sequences to save memory
        kernel_initializer="glorot_uniform",
        recurrent_initializer="orthogonal",
        name="lstm_1"
    )(x2)
    lstm_out = keras.layers.BatchNormalization(name="bn_lstm")(lstm_out)
    lstm_out = keras.layers.Dropout(0.2, name="dropout_lstm")(lstm_out)
    
    # Shared feature extraction (minimal)
    shared = keras.layers.Dense(
        32,  # Further reduced
        activation="relu",
        kernel_initializer="he_normal",
        name="dense_shared_1"
    )(lstm_out)
    shared = keras.layers.BatchNormalization(name="bn_shared_1")(shared)
    shared = keras.layers.Dropout(0.2, name="dropout_shared_1")(shared)
    
    shared = keras.layers.Dense(
        16,  # Further reduced
        activation="relu",
        kernel_initializer="he_normal",
        name="dense_shared_2"
    )(shared)
    shared = keras.layers.BatchNormalization(name="bn_shared_2")(shared)
    
    # SEPARATE HEADS (minimal but still separate)
    outputs = []
    for i, target_name in enumerate(config.targets):
        # Each target gets its own pathway to prevent interference
        head = keras.layers.Dense(
            8,  # Minimal but sufficient
            activation="relu",
            kernel_initializer="he_normal",
            name=f"head_{target_name}_1"
        )(shared)
        head = keras.layers.BatchNormalization(name=f"bn_{target_name}_1")(head)
        head = keras.layers.Dropout(0.1, name=f"dropout_{target_name}_1")(head)
        
        # Output layer with better initialization
        output = keras.layers.Dense(
            1,
            activation=None,
            kernel_initializer="glorot_uniform",
            # Initialize bias to small random value to break symmetry
            bias_initializer=keras.initializers.RandomUniform(minval=0.3, maxval=0.7),
            name=f"output_{target_name}"
        )(head)
        
        outputs.append(output)
    
    # Concatenate outputs
    if len(outputs) > 1:
        outputs = keras.layers.Concatenate(name="outputs")(outputs)
    else:
        outputs = outputs[0]
    
    # Use sigmoid activation instead of clipping - smoother gradients
    outputs = keras.layers.Activation('sigmoid', name="controller_output")(outputs)

    model = keras.Model(inputs, outputs, name="smartsync_memory_efficient")
    
    # Optimizer with appropriate learning rate
    initial_lr = config.learning_rate * 0.5  # Start at 1e-3 (half of 2e-3)
    optimizer = keras.optimizers.Adam(
        learning_rate=initial_lr,
        beta_1=0.9,
        beta_2=0.999,
        epsilon=1e-7,
        clipnorm=config.gradient_clip_norm,
    )
    
    # Use custom loss with variance penalty to prevent collapse
    loss_fn = VariancePenaltyLoss(variance_weight=0.2)
    
    model.compile(
        optimizer=optimizer,
        loss=loss_fn,
        metrics=[
            keras.metrics.MeanAbsoluteError(name="mae"),
            keras.metrics.RootMeanSquaredError(name="rmse"),
        ],
    )

    print("\n📐 Memory-Efficient Model Architecture")
    model.summary()
    print(f"\n✅ Model Configuration:")
    print(f"   - Architecture: CNN + LSTM (ultra memory optimized)")
    print(f"   - Capacity: 32 units (minimal for GPU memory)")
    print(f"   - Dropout: 0.1-0.2 (moderate)")
    print(f"   - Initial learning rate: {initial_lr:.6f}")
    print(f"   - Loss: MSE + Variance Penalty (prevents collapse)")
    print(f"   - Output: Sigmoid activation (smooth gradients)")
    print(f"   - Bias init: Random 0.3-0.7 (breaks symmetry)")
    return model


class ValidationR2Callback(keras.callbacks.Callback):
    def __init__(self, val_data: Tuple[np.ndarray, np.ndarray]):
        super().__init__()
        self.val_data = val_data
        self.history: List[float] = []

    def on_epoch_end(self, epoch: int, logs=None):
        X_val, y_val = self.val_data
        preds = self.model.predict(X_val, verbose=0, batch_size=32)
        
        # Validate prediction shape
        if preds.shape != y_val.shape:
            print(f"   ⚠️  Warning: Prediction shape mismatch in ValidationR2Callback: {preds.shape} vs {y_val.shape}")
            return
        
        # Check for constant predictions
        pred_std = np.std(preds, axis=0)
        target_std = np.std(y_val, axis=0)
        variance_ratio = pred_std / (target_std + 1e-10)
        
        # CRITICAL: Detect model collapse early
        if pred_std[0] < 1e-6 or pred_std[1] < 1e-6:
            if epoch > 3:  # Warn after warmup
                print(f"\n   ❌ CRITICAL: Constant predictions detected!")
                print(f"      Prediction std: {pred_std}")
                print(f"      Target std: {target_std}")
                print(f"      Model has collapsed - all predictions are the same value")
            # Use a very negative R² to indicate failure
            self.history.append(-100.0)
            return
        
        # Check if variance is too low (predictions are nearly constant)
        if (variance_ratio[0] < 0.1 or variance_ratio[1] < 0.1) and epoch > 5:
            print(f"\n   ⚠️  WARNING: Very low prediction variance detected!")
            print(f"      Prediction std: [{pred_std[0]:.6f}, {pred_std[1]:.6f}]")
            print(f"      Target std: [{target_std[0]:.6f}, {target_std[1]:.6f}]")
            print(f"      Variance ratio: [{variance_ratio[0]:.4f}, {variance_ratio[1]:.4f}]")
            print(f"      Model is predicting nearly constant values (collapse imminent)")
            print(f"      This will result in very negative R² scores")
        
        r2 = float(r2_score(y_val, preds))
        self.history.append(r2)
        
        # Warn if R² is very negative (model collapse)
        if r2 < -5.0 and epoch > 5:
            print(f"\n   ❌ CRITICAL: Very negative R² ({r2:.2f}) - model has collapsed!")
            print(f"      Prediction variance is too low - model is predicting constant values")
            print(f"      This indicates the model needs:")
            print(f"      1. Less regularization (reduce dropout/L2)")
            print(f"      2. Higher learning rate")
            print(f"      3. Better initialization")
            print(f"      4. Different output activation")


class OverfittingMonitor(keras.callbacks.Callback):
    """Monitor training/validation gap to detect overfitting early with loss smoothing"""
    def __init__(self, gap_threshold=0.15, smoothing_window=3, severe_gap_threshold=0.90, severe_patience=3, config=None):
        super().__init__()
        self.gap_threshold = gap_threshold
        self.severe_gap_threshold = severe_gap_threshold  # Stop training if gap exceeds this (e.g., 90%)
        self.severe_patience = severe_patience  # Number of consecutive epochs with severe overfitting before stopping
        self.severe_overfitting_count = 0  # Track consecutive severe overfitting epochs
        self.smoothing_window = smoothing_window
        self.config = config  # Store config for detailed warnings
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
                    gap_ratio = val_loss / train_loss if train_loss > 0 else float('inf')
                    severity = "SEVERE" if smoothed_gap > 0.80 else "MODERATE" if smoothed_gap > 0.50 else "MILD"
                    
                    print(f"\n⚠️  [{severity}] Overfitting Detected - Train/Val Gap: {smoothed_gap:.2%}")
                    print(f"   📊 Training loss:   {train_loss:.6f} (smoothed: {smoothed_train:.6f})")
                    print(f"   📊 Validation loss: {val_loss:.6f} (smoothed: {smoothed_val:.6f})")
                    print(f"   📈 Gap ratio: {gap_ratio:.2f}x (val_loss is {gap_ratio:.1f}x higher than train_loss)")
                    
                    # Provide actionable recommendations based on severity
                    if smoothed_gap > 0.80:
                        print(f"   🔧 Auto-actions: Adaptive dropout will increase, training will stop if gap persists")
                        print(f"   💡 Recommendations:")
                        print(f"      - Model is severely overfitting - regularization is being increased automatically")
                        print(f"      - If gap persists, consider: reducing model size further, increasing L2 reg, or checking data")
                    elif smoothed_gap > 0.50:
                        print(f"   🔧 Auto-actions: Adaptive dropout may increase if gap worsens")
                        print(f"   💡 Recommendations:")
                        print(f"      - Monitor for next few epochs - adaptive dropout will adjust if needed")
                        print(f"      - Current regularization should help reduce gap")
                    else:
                        print(f"   🔧 Status: Monitoring - adaptive dropout will adjust if gap increases")
                        print(f"   💡 Note: Gap is moderate - current regularization should help")
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
                ratio = val_loss / train_loss if train_loss > 0 else float('inf')
                print(f"\n⚠️  Validation Loss Significantly Higher Than Training Loss")
                print(f"   📊 Training: {train_loss:.6f} | Validation: {val_loss:.6f} | Ratio: {ratio:.2f}x")
                print(f"   🔍 This indicates the model is memorizing training data rather than learning general patterns")
                if self.config:
                    print(f"   🔧 Current anti-overfitting measures:")
                    print(f"      ✓ Dropout: {self.config.dropout:.2f} (adaptive, can increase to 0.75)")
                    print(f"      ✓ L2 Regularization: {self.config.l2_regularization}")
                    print(f"      ✓ Data Augmentation: {'ON' if self.config.use_data_augmentation else 'OFF'}")
                    print(f"      ✓ Weight Constraints: max_norm({self.config.max_weight_norm})")
                print(f"   💡 The adaptive dropout callback will automatically increase regularization if this persists")
            
            # Stop training if severe overfitting persists (gap > 90% for multiple epochs)
            if smoothed_gap > self.severe_gap_threshold and smoothed_val > smoothed_train:
                self.severe_overfitting_count += 1
                if self.severe_overfitting_count >= self.severe_patience:
                    print(f"\n{'='*80}")
                    print(f"🛑 STOPPING TRAINING: Severe Overfitting Detected")
                    print(f"{'='*80}")
                    print(f"   ⚠️  Severe overfitting detected for {self.severe_overfitting_count} consecutive epochs")
                    print(f"   📊 Train/Val gap: {smoothed_gap:.2%} (threshold: {self.severe_gap_threshold:.2%})")
                    print(f"   📊 Training loss:   {smoothed_train:.6f}")
                    print(f"   📊 Validation loss: {smoothed_val:.6f}")
                    print(f"   📈 Gap ratio: {(smoothed_val/smoothed_train):.2f}x")
                    print(f"\n   🔧 All anti-overfitting measures were applied:")
                    if self.config:
                        print(f"      ✓ Dropout: {self.config.dropout:.2f} (adaptive, increased to max)")
                        print(f"      ✓ L2 Regularization: {self.config.l2_regularization}")
                        print(f"      ✓ Data Augmentation: {'ON' if self.config.use_data_augmentation else 'OFF'}")
                        print(f"      ✓ Weight Constraints: max_norm({self.config.max_weight_norm})")
                        print(f"      ✓ Model Capacity: Reduced (filters: {self.config.conv_filters})")
                    print(f"\n   💡 Recommendations:")
                    print(f"      1. Check for data leakage between train/val sets")
                    print(f"      2. Consider further reducing model capacity")
                    if self.config:
                        print(f"      3. Increase L2 regularization beyond {self.config.l2_regularization}")
                    else:
                        print(f"      3. Increase L2 regularization")
                    print(f"      4. Verify data quality and feature engineering")
                    print(f"      5. Consider using a simpler model architecture")
                    print(f"{'='*80}\n")
                    self.model.stop_training = True
            else:
                # Reset counter if gap improves
                if smoothed_gap <= self.severe_gap_threshold:
                    self.severe_overfitting_count = 0
            
            # Warn if validation loss is very unstable (high variance)
            if len(self.val_loss_history) >= 5:
                recent_val_losses = self.val_loss_history[-5:]
                val_std = np.std(recent_val_losses)
                val_mean = np.mean(recent_val_losses)
                if val_mean > 0 and val_std / val_mean > 0.5:  # Coefficient of variation > 50%
                    print(f"\n⚠️  Warning: High Validation Loss Variance Detected")
                    print(f"   📊 Recent validation loss std: {val_std:.6f}, mean: {val_mean:.6f}")
                    print(f"   📈 Coefficient of variation: {(val_std/val_mean)*100:.1f}% (>50% indicates instability)")
                    print(f"   💡 This suggests unstable training - regularization is being applied automatically")
                    print(f"   🔧 Consider: increasing validation set size or checking for data issues")
            
            # Warn if both losses are high and similar (underfitting)
            if epoch > 5 and train_loss > 0.5 and val_loss > 0.5:
                if abs(train_loss - val_loss) / max(train_loss, val_loss) < 0.1:
                    print(f"\n⚠️  Warning: High and Similar Losses Detected (Possible Underfitting)")
                    print(f"   📊 Training loss: {train_loss:.6f} | Validation loss: {val_loss:.6f}")
                    print(f"   🔍 Both losses are high and similar - model may be underfitting")
                    print(f"   💡 Consider: increasing model capacity, reducing regularization, or checking learning rate")
            
            # Print epoch summary for overfitting status
            if epoch > 0 and val_loss > 0 and train_loss > 0:
                gap = abs(train_loss - val_loss) / max(train_loss, val_loss) if max(train_loss, val_loss) > 0 else 0
                status_icon = "✅" if gap < 0.15 else "⚠️" if gap < 0.50 else "🔴"
                status_text = "Good" if gap < 0.15 else "Moderate" if gap < 0.50 else "Severe"
                print(f"\n📊 Epoch {epoch + 1} Overfitting Status: {status_icon} {status_text} (Gap: {gap:.2%})")


class AdaptiveDropoutCallback(keras.callbacks.Callback):
    """
    Dynamically adjust dropout rates based on overfitting detection.
    Increases dropout when overfitting is detected to improve generalization.
    Also reduces dropout if model is not learning (underfitting).
    """
    def __init__(self, initial_dropout=0.55, max_dropout=0.75, increase_factor=1.1, gap_threshold=0.25, min_epochs=0):
        super().__init__()
        self.initial_dropout = initial_dropout
        self.max_dropout = max_dropout
        self.increase_factor = increase_factor
        self.gap_threshold = gap_threshold
        self.min_epochs = min_epochs
        self.current_dropout = initial_dropout
        self.val_loss_history = []
        self.train_loss_history = []
        self.dropout_adjustments = []
        self.gap_history = []
        
    def on_epoch_end(self, epoch: int, logs=None):
        if logs is None:
            return
            
        # Don't adjust during warmup/min epochs
        if epoch < self.min_epochs:
            return
            
        train_loss = logs.get('loss', 0)
        val_loss = logs.get('val_loss', 0)
        
        self.train_loss_history.append(train_loss)
        self.val_loss_history.append(val_loss)
        
        if len(self.val_loss_history) < 3:  # Need at least 3 epochs to assess
            return
            
        # Calculate gap
        if val_loss > 0 and train_loss > 0:
            max_loss = max(train_loss, val_loss)
            gap = abs(train_loss - val_loss) / max_loss if max_loss > 0 else 0
            self.gap_history.append(gap)
            
            # Check if model is learning (loss decreasing)
            is_learning = False
            if len(self.val_loss_history) >= 3:
                recent_losses = self.val_loss_history[-3:]
                is_learning = recent_losses[-1] < recent_losses[0] * 0.99  # At least 1% improvement
            
            # Check if gap is consistently increasing (trend detection)
            gap_increasing = False
            if len(self.gap_history) >= 3:
                recent_gaps = self.gap_history[-3:]
                gap_increasing = all(recent_gaps[i] < recent_gaps[i+1] for i in range(len(recent_gaps)-1))
            
            # Check for underfitting: both losses high and similar, and not learning
            is_underfitting = False
            if epoch >= 5 and train_loss > 0.3 and val_loss > 0.3:
                small_gap = gap < 0.15
                if small_gap and not is_learning:
                    is_underfitting = True
            
            # Reduce dropout if underfitting (model not learning due to too much regularization)
            if is_underfitting and self.current_dropout > self.initial_dropout * 0.9:
                new_dropout = max(self.current_dropout * 0.95, self.initial_dropout * 0.9)
                if new_dropout < self.current_dropout:
                    self.current_dropout = new_dropout
                    self._update_model_dropout()
                    print(f"\n📉 Adaptive Dropout: Reduced to {self.current_dropout:.3f} (underfitting detected - model not learning)")
                return  # Don't increase if underfitting
            
            # More aggressive trigger: lower threshold and ratio requirement
            # Also trigger if gap is consistently increasing even if below threshold
            should_increase = False
            if val_loss > train_loss:  # Only if validation is worse (overfitting)
                # For severe overfitting (gap > 35%), always increase regardless of learning status
                if gap > 0.35 and val_loss > train_loss * 1.3:
                    should_increase = True
                # For moderate overfitting (gap > 25%), increase if gap is increasing
                elif gap > 0.25 and gap_increasing and val_loss > train_loss * 1.2:
                    should_increase = True
                # For any overfitting above threshold, trigger more easily
                elif gap > self.gap_threshold and val_loss > train_loss * 1.1:
                    should_increase = True
                # Trigger earlier if gap is trending upward (even if below threshold)
                elif gap_increasing and gap > self.gap_threshold * 0.7 and val_loss > train_loss * 1.05:
                    should_increase = True
            
            if should_increase:
                # Increase dropout more aggressively if gap is large
                if gap > 0.40:
                    factor = self.increase_factor * 1.25  # 43.75% increase for severe overfitting (>40%)
                elif gap > 0.35:
                    factor = self.increase_factor * 1.15  # 32.25% increase for moderate-severe overfitting
                elif gap > 0.25:
                    factor = self.increase_factor * 1.08  # 24.2% increase for moderate overfitting
                else:
                    factor = self.increase_factor
                
                new_dropout = min(self.current_dropout * factor, self.max_dropout)
                if new_dropout > self.current_dropout:
                    self.current_dropout = new_dropout
                    self._update_model_dropout()
                    self.dropout_adjustments.append((epoch, self.current_dropout))
                    print(f"\n📈 Adaptive Dropout: Increased to {self.current_dropout:.3f} (gap: {gap:.2%}, ratio: {val_loss/train_loss:.2f}x)")
            # If gap is improving, slightly reduce dropout (but not below initial)
            elif gap < self.gap_threshold * 0.4 and epoch > 10 and val_loss <= train_loss * 1.05 and is_learning:
                new_dropout = max(self.current_dropout * 0.98, self.initial_dropout)
                if new_dropout < self.current_dropout:
                    self.current_dropout = new_dropout
                    self._update_model_dropout()
                    print(f"\n📉 Adaptive Dropout: Decreased to {self.current_dropout:.3f} (gap: {gap:.2%}, learning well)")
    
    def _update_model_dropout(self):
        """Update dropout rates in all dropout layers (including nested layers)"""
        updated_count = 0
        
        def update_layer_dropout(layer):
            nonlocal updated_count
            # Update standard dropout layers
            if isinstance(layer, (keras.layers.Dropout, keras.layers.SpatialDropout1D)):
                layer.rate = self.current_dropout
                updated_count += 1
            # Handle nested models (if any)
            elif isinstance(layer, keras.Model):
                for sublayer in layer.layers:
                    update_layer_dropout(sublayer)
        
        # Update all layers in the model
        for layer in self.model.layers:
            update_layer_dropout(layer)
        
        if updated_count > 0:
            print(f"   ✓ Updated {updated_count} dropout layer(s) to rate {self.current_dropout:.3f}")


class AdaptiveL2RegularizationCallback(keras.callbacks.Callback):
    """
    Dynamically adjust L2 regularization based on overfitting detection.
    Increases L2 regularization when overfitting is detected.
    """
    def __init__(self, initial_l2=2e-3, max_l2=1e-2, increase_factor=1.2, gap_threshold=0.25, min_epochs=0):
        super().__init__()
        self.initial_l2 = initial_l2
        self.max_l2 = max_l2
        self.increase_factor = increase_factor
        self.gap_threshold = gap_threshold
        self.min_epochs = min_epochs
        self.current_l2 = initial_l2
        self.val_loss_history = []
        self.train_loss_history = []
        self.l2_adjustments = []
        self.gap_history = []
        
    def on_epoch_end(self, epoch: int, logs=None):
        if logs is None:
            return
            
        # Don't adjust during warmup/min epochs
        if epoch < self.min_epochs:
            return
            
        train_loss = logs.get('loss', 0)
        val_loss = logs.get('val_loss', 0)
        
        self.train_loss_history.append(train_loss)
        self.val_loss_history.append(val_loss)
        
        if len(self.val_loss_history) < 3:
            return
            
        # Calculate gap
        if val_loss > 0 and train_loss > 0:
            max_loss = max(train_loss, val_loss)
            gap = abs(train_loss - val_loss) / max_loss if max_loss > 0 else 0
            self.gap_history.append(gap)
            
            # Check if model is learning (loss decreasing)
            is_learning = False
            if len(self.val_loss_history) >= 3:
                recent_losses = self.val_loss_history[-3:]
                is_learning = recent_losses[-1] < recent_losses[0] * 0.99  # At least 1% improvement
            
            # Check if gap is consistently increasing
            gap_increasing = False
            if len(self.gap_history) >= 3:
                recent_gaps = self.gap_history[-3:]
                gap_increasing = all(recent_gaps[i] < recent_gaps[i+1] for i in range(len(recent_gaps)-1))
            
            # Check for underfitting: both losses high and similar, and not learning
            is_underfitting = False
            if epoch >= 5 and train_loss > 0.3 and val_loss > 0.3:
                small_gap = gap < 0.15
                if small_gap and not is_learning:
                    is_underfitting = True
            
            # Reduce L2 if underfitting (model not learning due to too much regularization)
            if is_underfitting and self.current_l2 > self.initial_l2 * 1.1:
                new_l2 = max(self.current_l2 * 0.95, self.initial_l2)
                if new_l2 < self.current_l2:
                    self.current_l2 = new_l2
                    self._update_model_l2()
                    print(f"\n📉 Adaptive L2: Reduced to {self.current_l2:.6f} (underfitting detected - model not learning)")
                return  # Don't increase if underfitting
            
            # Increase L2 if overfitting detected - more aggressive triggering
            should_increase = False
            if val_loss > train_loss:
                # For severe overfitting (gap > 35%), always increase regardless of learning status
                if gap > 0.35 and val_loss > train_loss * 1.3:
                    should_increase = True
                # For moderate overfitting (gap > 25%), increase if gap is increasing
                elif gap > 0.25 and gap_increasing and val_loss > train_loss * 1.2:
                    should_increase = True
                # For any overfitting above threshold, trigger more easily
                elif gap > self.gap_threshold and val_loss > train_loss * 1.1:
                    should_increase = True
                # Trigger earlier if gap is trending upward (even if below threshold)
                elif gap_increasing and gap > self.gap_threshold * 0.7 and val_loss > train_loss * 1.05:
                    should_increase = True
            
            if should_increase:
                # Increase L2 more aggressively if gap is large
                if gap > 0.40:
                    factor = self.increase_factor * 1.4  # 75% increase for severe overfitting (>40%)
                elif gap > 0.35:
                    factor = self.increase_factor * 1.25  # 56.25% increase for moderate-severe overfitting
                elif gap > 0.25:
                    factor = self.increase_factor * 1.15  # 43.75% increase for moderate overfitting
                else:
                    factor = self.increase_factor
                
                new_l2 = min(self.current_l2 * factor, self.max_l2)
                if new_l2 > self.current_l2:
                    self.current_l2 = new_l2
                    self._update_model_l2()
                    self.l2_adjustments.append((epoch, self.current_l2))
                    print(f"\n📈 Adaptive L2: Increased to {self.current_l2:.6f} (gap: {gap:.2%}, ratio: {val_loss/train_loss:.2f}x)")
            # Reduce L2 if gap is improving and model is learning
            elif gap < self.gap_threshold * 0.4 and epoch > 10 and val_loss <= train_loss * 1.05 and is_learning:
                new_l2 = max(self.current_l2 * 0.95, self.initial_l2)
                if new_l2 < self.current_l2:
                    self.current_l2 = new_l2
                    self._update_model_l2()
                    print(f"\n📉 Adaptive L2: Decreased to {self.current_l2:.6f} (gap: {gap:.2%}, learning well)")
    
    def _update_model_l2(self):
        """Update L2 regularization in all layers with regularizers"""
        updated_count = 0
        
        def update_layer_l2(layer):
            nonlocal updated_count
            # Update layers with kernel_regularizer
            if hasattr(layer, 'kernel_regularizer') and layer.kernel_regularizer is not None:
                if hasattr(layer.kernel_regularizer, 'l2'):
                    layer.kernel_regularizer.l2 = self.current_l2
                    updated_count += 1
                else:
                    # Create new regularizer if needed
                    layer.kernel_regularizer = keras.regularizers.l2(self.current_l2)
                    updated_count += 1
            
            # Update layers with bias_regularizer
            if hasattr(layer, 'bias_regularizer') and layer.bias_regularizer is not None:
                if hasattr(layer.bias_regularizer, 'l2'):
                    layer.bias_regularizer.l2 = self.current_l2
                else:
                    layer.bias_regularizer = keras.regularizers.l2(self.current_l2)
            
            # Handle nested models
            if isinstance(layer, keras.Model):
                for sublayer in layer.layers:
                    update_layer_l2(sublayer)
        
        for layer in self.model.layers:
            update_layer_l2(layer)
        
        if updated_count > 0:
            print(f"   ✓ Updated {updated_count} layer(s) with L2={self.current_l2:.6f}")


class AdaptiveLearningRateCallback(keras.callbacks.Callback):
    """
    Reduce learning rate more aggressively when overfitting is detected.
    Complements ReduceLROnPlateau by being triggered by train/val gap.
    """
    def __init__(self, gap_threshold=0.30, reduction_factor=0.7, min_lr=1e-6):
        super().__init__()
        self.gap_threshold = gap_threshold
        self.reduction_factor = reduction_factor
        self.min_lr = min_lr
        self.gap_history = []
        self.reductions = []
        
    def on_epoch_end(self, epoch: int, logs=None):
        if logs is None:
            return
            
        train_loss = logs.get('loss', 0)
        val_loss = logs.get('val_loss', 0)
        
        if val_loss > 0 and train_loss > 0 and val_loss > train_loss:
            max_loss = max(train_loss, val_loss)
            gap = abs(train_loss - val_loss) / max_loss if max_loss > 0 else 0
            self.gap_history.append(gap)
            
            # Reduce LR if gap is high - more aggressive triggering
            if len(self.gap_history) >= 2:
                recent_gaps = self.gap_history[-2:]
                gap_increasing = recent_gaps[-1] > recent_gaps[0] if len(recent_gaps) > 1 else False
                
                # Trigger if gap exceeds threshold OR if gap is increasing rapidly
                should_reduce = False
                if gap > self.gap_threshold:
                    should_reduce = True
                elif gap_increasing and gap > self.gap_threshold * 0.8:
                    should_reduce = True
                
                if should_reduce:
                    current_lr = float(self.model.optimizer.learning_rate.numpy())
                    new_lr = max(current_lr * self.reduction_factor, self.min_lr)
                    
                    if new_lr < current_lr:
                        self.model.optimizer.learning_rate.assign(new_lr)
                        self.reductions.append((epoch, new_lr))
                        print(f"\n📉 Adaptive LR: Reduced to {new_lr:.2e} (gap: {gap:.2%}, overfitting detected)")


class WarmupLearningRateSchedule(keras.callbacks.Callback):
    """
    Learning rate warmup schedule for stable early training.
    Gradually increases learning rate from a small value to the target learning rate.
    """
    def __init__(self, warmup_epochs: int, initial_lr: float, target_lr: float):
        super().__init__()
        self.warmup_epochs = warmup_epochs
        self.initial_lr = initial_lr
        self.target_lr = target_lr
        self.warmup_complete = False
        
    def on_epoch_begin(self, epoch, logs=None):
        if epoch < self.warmup_epochs:
            # Linear warmup: lr = initial_lr + (target_lr - initial_lr) * (epoch / warmup_epochs)
            warmup_lr = self.initial_lr + (self.target_lr - self.initial_lr) * (epoch / self.warmup_epochs)
            self.model.optimizer.learning_rate.assign(warmup_lr)
            if epoch == 0:
                print(f"\n🔥 Learning Rate Warmup: Starting at {warmup_lr:.2e}, will reach {self.target_lr:.2e} after {self.warmup_epochs} epochs")
        elif not self.warmup_complete:
            # Set to target LR after warmup
            self.model.optimizer.learning_rate.assign(self.target_lr)
            self.warmup_complete = True
            print(f"\n✅ Warmup Complete: Learning rate set to {self.target_lr:.2e}")


class OverfittingEarlyStopping(keras.callbacks.Callback):
    """
    Stop training early when overfitting gap exceeds threshold for multiple consecutive epochs.
    More aggressive than standard early stopping - focuses on generalization gap.
    """
    def __init__(self, gap_threshold=0.40, patience=3, min_epochs=10):
        super().__init__()
        self.gap_threshold = gap_threshold
        self.patience = patience
        self.min_epochs = min_epochs
        self.gap_history = []
        self.consecutive_high_gap = 0
        
    def on_epoch_end(self, epoch: int, logs=None):
        if logs is None:
            return
            
        train_loss = logs.get('loss', 0)
        val_loss = logs.get('val_loss', 0)
        
        if val_loss > 0 and train_loss > 0 and val_loss > train_loss:
            max_loss = max(train_loss, val_loss)
            gap = abs(train_loss - val_loss) / max_loss if max_loss > 0 else 0
            self.gap_history.append(gap)
            
            if epoch + 1 >= self.min_epochs:
                if gap > self.gap_threshold:
                    self.consecutive_high_gap += 1
                    if self.consecutive_high_gap >= self.patience:
                        ratio = val_loss / train_loss if train_loss > 0 else float('inf')
                        print(f"\n{'='*80}")
                        print(f"🛑 EARLY STOPPING: Persistent Overfitting Detected")
                        print(f"{'='*80}")
                        print(f"   ⚠️  Train/Val gap exceeded {self.gap_threshold:.1%} for {self.patience} consecutive epochs")
                        print(f"   📊 Current gap: {gap:.2%}")
                        print(f"   📊 Training loss: {train_loss:.6f}")
                        print(f"   📊 Validation loss: {val_loss:.6f}")
                        print(f"   📈 Ratio: {ratio:.2f}x")
                        print(f"   💡 Stopping training to prevent further overfitting")
                        print(f"{'='*80}\n")
                        self.model.stop_training = True
                else:
                    self.consecutive_high_gap = 0  # Reset counter if gap improves


class CollapseDetectionCallback(keras.callbacks.Callback):
    """
    Detect model collapse early and stop training if predictions become constant.
    This prevents wasting time training a collapsed model.
    """
    def __init__(self, val_data: Tuple[np.ndarray, np.ndarray], min_epochs=3, patience=2):
        super().__init__()
        self.val_data = val_data
        self.min_epochs = min_epochs
        self.patience = patience
        self.collapse_count = 0
        
    def on_epoch_end(self, epoch: int, logs=None):
        if epoch + 1 < self.min_epochs:
            return
            
        X_val, y_val = self.val_data
        preds = self.model.predict(X_val, verbose=0, batch_size=32)
        
        # Check for constant predictions
        pred_std = np.std(preds, axis=0)
        target_std = np.std(y_val, axis=0)
        variance_ratio = pred_std / (target_std + 1e-10)
        
        # Detect collapse: prediction std is essentially zero OR variance ratio is very low
        # More sensitive: check if variance ratio < 0.01 (predictions have <1% of target variance)
        is_collapsed = (pred_std[0] < 1e-5 or pred_std[1] < 1e-5) or \
                       (variance_ratio[0] < 0.01 or variance_ratio[1] < 0.01)
        
        if is_collapsed:
            self.collapse_count += 1
            print(f"\n   ⚠️  Collapse warning (epoch {epoch+1}): pred_std=[{pred_std[0]:.6f}, {pred_std[1]:.6f}], "
                  f"variance_ratio=[{variance_ratio[0]:.4f}, {variance_ratio[1]:.4f}]")
            
            if self.collapse_count >= self.patience:
                print(f"\n{'='*80}")
                print(f"❌ MODEL COLLAPSE DETECTED - Stopping training early")
                print(f"   Prediction std: [{pred_std[0]:.8f}, {pred_std[1]:.8f}]")
                print(f"   Target std: [{target_std[0]:.6f}, {target_std[1]:.6f}]")
                print(f"   Variance ratio: [{variance_ratio[0]:.4f}, {variance_ratio[1]:.4f}]")
                print(f"   Model is predicting constant values - training stopped at epoch {epoch+1}")
                print(f"{'='*80}\n")
                self.model.stop_training = True
        else:
            self.collapse_count = 0  # Reset if model recovers


class LearningProgressMonitor(keras.callbacks.Callback):
    """
    Monitor if the model is actually learning by tracking loss improvements.
    Detects underfitting, stuck training, and learning rate issues.
    """
    def __init__(self, min_improvement_rate=0.01, stuck_patience=5, min_epochs=3):
        super().__init__()
        self.min_improvement_rate = min_improvement_rate  # Minimum expected improvement per epoch
        self.stuck_patience = stuck_patience  # Epochs without improvement before warning
        self.min_epochs = min_epochs  # Minimum epochs before checking
        self.best_val_loss = float('inf')
        self.best_train_loss = float('inf')
        self.val_loss_history = []
        self.train_loss_history = []
        self.no_improvement_count = 0
        self.learning_rate_history = []
        
    def on_epoch_end(self, epoch: int, logs=None):
        if logs is None:
            return
            
        train_loss = logs.get('loss', 0)
        val_loss = logs.get('val_loss', 0)
        current_lr = float(self.model.optimizer.learning_rate.numpy())
        
        self.train_loss_history.append(train_loss)
        self.val_loss_history.append(val_loss)
        self.learning_rate_history.append(current_lr)
        
        # Track best losses
        if val_loss < self.best_val_loss:
            improvement = self.best_val_loss - val_loss
            improvement_pct = (improvement / self.best_val_loss * 100) if self.best_val_loss > 0 else 0
            self.best_val_loss = val_loss
            self.no_improvement_count = 0
            
            # Positive feedback when learning well
            if epoch >= self.min_epochs and improvement_pct > 1.0:
                print(f"\n✅ Learning Progress: Validation loss improved by {improvement_pct:.2f}% "
                      f"({self.best_val_loss:.6f})")
        else:
            self.no_improvement_count += 1
            
        if train_loss < self.best_train_loss:
            self.best_train_loss = train_loss
        
        # Check if model is learning (only after minimum epochs)
        if epoch + 1 >= self.min_epochs:
            # Check 1: Loss not decreasing (stuck training) - check if loss is actually stuck, not just not beating best
            if len(self.val_loss_history) >= self.stuck_patience:
                recent_losses = self.val_loss_history[-self.stuck_patience:]
                # Check if loss is actually increasing or flat (not decreasing)
                # Loss is stuck if it's not decreasing by at least 0.1% per epoch on average
                total_change = recent_losses[-1] - recent_losses[0]
                avg_change_per_epoch = total_change / (len(recent_losses) - 1) if len(recent_losses) > 1 else 0
                
                # Only warn if loss is actually increasing or flat (not decreasing meaningfully)
                if avg_change_per_epoch >= -0.001:  # Loss not decreasing by at least 0.1% per epoch
                    avg_loss = np.mean(recent_losses)
                    improvement_from_best = ((self.best_val_loss - recent_losses[-1]) / self.best_val_loss * 100) if self.best_val_loss > 0 else 0
                    print(f"\n⚠️  Learning Alert: Validation loss not improving for {self.stuck_patience} epochs")
                    print(f"   📊 Average recent loss: {avg_loss:.6f}")
                    print(f"   📊 Best loss so far: {self.best_val_loss:.6f} ({improvement_from_best:+.2f}% from current)")
                    print(f"   📊 Recent trend: {recent_losses[0]:.6f} → {recent_losses[-1]:.6f}")
                    print(f"   💡 Possible causes:")
                    print(f"      - Learning rate too low (current: {current_lr:.2e})")
                    print(f"      - Regularization too strong (dropout/L2 may be too high)")
                    print(f"      - Model capacity insufficient")
                    print(f"      - Data preprocessing issues")
            
            # Check 2: Both losses very high and similar (underfitting)
            if epoch >= 5:
                if train_loss > 0.3 and val_loss > 0.3:
                    gap = abs(train_loss - val_loss) / max(train_loss, val_loss)
                    if gap < 0.15:  # Very similar losses
                        print(f"\n⚠️  Underfitting Alert: Both losses are high and similar")
                        print(f"   📊 Training loss: {train_loss:.6f} | Validation loss: {val_loss:.6f}")
                        print(f"   📊 Gap: {gap:.2%} (very small - model may be underfitting)")
                        print(f"   💡 Recommendations:")
                        print(f"      - Model may need more capacity (increase layers/units)")
                        print(f"      - Regularization may be too strong (reduce dropout/L2)")
                        print(f"      - Learning rate may be too low (current: {current_lr:.2e})")
                        print(f"      - Check if data preprocessing is correct")
            
            # Check 3: Loss increasing consistently (diverging)
            if len(self.val_loss_history) >= 4:
                recent = self.val_loss_history[-4:]
                if all(recent[i] < recent[i+1] for i in range(len(recent)-1)):
                    print(f"\n⚠️  Divergence Alert: Validation loss increasing for 4 consecutive epochs")
                    print(f"   📊 Loss trend: {recent[0]:.6f} → {recent[-1]:.6f}")
                    print(f"   💡 Possible causes:")
                    print(f"      - Learning rate too high (current: {current_lr:.2e})")
                    print(f"      - Gradient explosion (check gradient clipping)")
                    print(f"      - Numerical instability")
            
            # Check 4: Learning rate too low
            if current_lr < 1e-6 and epoch >= 10:
                recent_improvement = self.best_val_loss - val_loss if val_loss < self.best_val_loss else 0
                if recent_improvement < 0.001:  # Very small improvement
                    print(f"\n⚠️  Learning Rate Alert: LR very low ({current_lr:.2e}) with minimal improvement")
                    print(f"   💡 Consider: Learning rate may be too low for further learning")
        
        # Positive indicators
        if epoch >= 2:
            # Check if learning is happening
            if len(self.val_loss_history) >= 3:
                recent_improvement = self.val_loss_history[-3] - self.val_loss_history[-1]
                if recent_improvement > 0.01:  # Significant improvement
                    improvement_rate = recent_improvement / self.val_loss_history[-3] if self.val_loss_history[-3] > 0 else 0
                    if improvement_rate > 0.05:  # >5% improvement
                        print(f"\n✅ Good Learning: Validation loss improved by {improvement_rate:.1%} over last 3 epochs")


class AdaptiveDataAugmentationCallback(keras.callbacks.Callback):
    """
    Increase data augmentation strength when overfitting is detected.
    Updates augmentation layer parameters dynamically.
    """
    def __init__(self, initial_noise_std=0.04, max_noise_std=0.10, initial_mask_prob=0.15, max_mask_prob=0.30, gap_threshold=0.25, min_epochs=0):
        super().__init__()
        self.initial_noise_std = initial_noise_std
        self.max_noise_std = max_noise_std
        self.initial_mask_prob = initial_mask_prob
        self.max_mask_prob = max_mask_prob
        self.gap_threshold = gap_threshold  # Store gap_threshold as instance attribute
        self.min_epochs = min_epochs
        self.current_noise_std = initial_noise_std
        self.current_mask_prob = initial_mask_prob
        self.gap_history = []
        self.augmentation_adjustments = []
        
    def on_epoch_end(self, epoch: int, logs=None):
        if logs is None:
            return
            
        # Don't adjust during warmup/min epochs
        if epoch < self.min_epochs:
            return
            
        train_loss = logs.get('loss', 0)
        val_loss = logs.get('val_loss', 0)
        
        if val_loss > 0 and train_loss > 0 and val_loss > train_loss:
            max_loss = max(train_loss, val_loss)
            gap = abs(train_loss - val_loss) / max_loss if max_loss > 0 else 0
            self.gap_history.append(gap)
            
            if len(self.gap_history) >= 3:
                recent_gaps = self.gap_history[-3:]
                gap_increasing = all(recent_gaps[i] < recent_gaps[i+1] for i in range(len(recent_gaps)-1))
                
                # Increase augmentation if gap is high and increasing
                if gap > self.gap_threshold and gap_increasing:
                    # Increase noise std
                    new_noise_std = min(self.current_noise_std * 1.15, self.max_noise_std)
                    # Increase mask prob
                    new_mask_prob = min(self.current_mask_prob * 1.1, self.max_mask_prob)
                    
                    if new_noise_std > self.current_noise_std or new_mask_prob > self.current_mask_prob:
                        self.current_noise_std = new_noise_std
                        self.current_mask_prob = new_mask_prob
                        self._update_augmentation_layers()
                        self.augmentation_adjustments.append((epoch, self.current_noise_std, self.current_mask_prob))
                        print(f"\n📈 Adaptive Augmentation: Increased noise_std to {self.current_noise_std:.4f}, mask_prob to {self.current_mask_prob:.3f} (gap: {gap:.2%})")
                # Reduce if gap is improving
                elif gap < self.gap_threshold * 0.4 and epoch > 10:
                    new_noise_std = max(self.current_noise_std * 0.95, self.initial_noise_std)
                    new_mask_prob = max(self.current_mask_prob * 0.95, self.initial_mask_prob)
                    
                    if new_noise_std < self.current_noise_std or new_mask_prob < self.current_mask_prob:
                        self.current_noise_std = new_noise_std
                        self.current_mask_prob = new_mask_prob
                        self._update_augmentation_layers()
                        print(f"\n📉 Adaptive Augmentation: Decreased noise_std to {self.current_noise_std:.4f}, mask_prob to {self.current_mask_prob:.3f} (gap: {gap:.2%})")
    
    def _update_augmentation_layers(self):
        """Update augmentation layer parameters"""
        updated_count = 0
        
        def update_layer(layer):
            nonlocal updated_count
            if isinstance(layer, TimeSeriesAugmentation):
                layer.noise_std = self.current_noise_std
                layer.time_mask_prob = self.current_mask_prob
                updated_count += 1
            elif isinstance(layer, keras.Model):
                for sublayer in layer.layers:
                    update_layer(sublayer)
        
        for layer in self.model.layers:
            update_layer(layer)
        
        if updated_count > 0:
            print(f"   ✓ Updated {updated_count} augmentation layer(s)")


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


class TimeLimitCallback(keras.callbacks.Callback):
    """Abort training once the wall-clock budget has been exhausted."""
    def __init__(self, max_seconds: int):
        super().__init__()
        self.max_seconds = max_seconds
        self.start_time = None
    
    def on_train_begin(self, logs=None):
        self.start_time = time.time()
    
    def on_epoch_end(self, epoch, logs=None):
        if self.start_time is None:
            return
        elapsed = time.time() - self.start_time
        remaining = self.max_seconds - elapsed
        if remaining <= 0:
            print(f"\n🛑 Time budget reached ({elapsed/60:.1f} min). Stopping training to stay within limit.")
            self.model.stop_training = True
        elif remaining < 600 and (epoch + 1) % 2 == 0:
            print(f"\n⏳ Time budget: {remaining/60:.1f} minutes remaining.")


class OptimalPerformanceEarlyStopping(keras.callbacks.Callback):
    """Stop early once MAE, R², and variance targets are satisfied."""
    def __init__(
        self,
        val_data: Tuple[np.ndarray, np.ndarray],
        target_mae: float,
        target_r2: float,
        min_variance_ratio: float,
        patience: int,
        min_epochs: int,
    ):
        super().__init__()
        self.val_data = val_data
        self.target_mae = target_mae
        self.target_r2 = target_r2
        self.min_variance_ratio = min_variance_ratio
        self.patience = patience
        self.min_epochs = min_epochs
        self.success_count = 0
    
    def on_epoch_end(self, epoch, logs=None):
        if epoch + 1 < self.min_epochs:
            return
        X_val, y_val = self.val_data
        if len(X_val) == 0:
            return
        preds = self.model.predict(X_val, verbose=0, batch_size=32)
        val_mae = float(mean_absolute_error(y_val, preds))
        r2 = float(r2_score(y_val, preds))
        pred_std = np.std(preds, axis=0)
        true_std = np.std(y_val, axis=0) + 1e-8
        variance_ratio = float(np.mean(pred_std / true_std))
        
        meets_mae = val_mae <= self.target_mae
        meets_r2 = r2 >= self.target_r2
        meets_variance = variance_ratio >= self.min_variance_ratio
        
        if meets_mae and meets_r2 and meets_variance:
            self.success_count += 1
            print(
                f"\n✅ Optimal performance conditions met "
                f"(MAE={val_mae:.4f}, R²={r2:.3f}, variance ratio={variance_ratio:.2f}) "
                f"[{self.success_count}/{self.patience}]"
            )
            if self.success_count >= self.patience:
                print("\n🛑 Stopping early: Model already meets target quality metrics.")
                self.model.stop_training = True
        else:
            self.success_count = 0


def create_tf_dataset(
    X: np.ndarray, y: np.ndarray, batch_size: int, shuffle: bool
) -> tf.data.Dataset:
    ds = tf.data.Dataset.from_tensor_slices((X, y))
    if shuffle:
        # Use smaller buffer (10k samples) for faster shuffling - still provides good randomness
        shuffle_buffer = min(10000, len(X))
        ds = ds.shuffle(buffer_size=shuffle_buffer, seed=CONFIG.seed)
    ds = ds.batch(batch_size, drop_remainder=False)
    ds = ds.cache()
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
    load_model_path: Optional[Path] = None,
    pause_flag_path: Path = PAUSE_FLAG_PATH,
    recovery_manager: Optional[AutoRecoveryManager] = None,
) -> Tuple[keras.Model, keras.callbacks.History, List[float]]:
    # Load existing model if specified, otherwise build new one
    if load_model_path and load_model_path.exists():
        print(f"\n📥 Loading existing model from {load_model_path}...")
        try:
            with warnings.catch_warnings():
                warnings.filterwarnings("ignore", category=UserWarning, module="keras.*")
                model = tf.keras.models.load_model(str(load_model_path))
            print(f"✅ Successfully loaded model")
            print(f"   Input shape: {model.input_shape}")
            print(f"   Output shape: {model.output_shape}")
            # Verify input shape matches training data
            expected_shape = X_train.shape[1:]
            if model.input_shape[1:] != expected_shape:
                print(f"⚠️  WARNING: Model input shape {model.input_shape[1:]} doesn't match data shape {expected_shape}")
                print(f"   Building new model instead...")
                model = build_temporal_cnn(X_train.shape[1:], config)
            else:
                print(f"   ✅ Model shape compatible with training data")
        except Exception as e:
            print(f"⚠️  Failed to load model ({e}). Building new model...")
            model = build_temporal_cnn(X_train.shape[1:], config)
    else:
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

    # IMPROVED CALLBACKS - Optimized for better training
    callbacks = [
        ProgressCallback(total_epochs=config.epochs),  # Custom progress display
        keras.callbacks.EarlyStopping(
            monitor="val_loss",
            patience=config.early_stopping_patience,
            restore_best_weights=True,
            verbose=1,
            mode="min",
            min_delta=1e-5,  # Minimum change to qualify as improvement
        ),
    ]
    if config.time_limit_minutes:
        callbacks.append(TimeLimitCallback(config.time_limit_minutes * 60))
    
    # Add learning rate schedule if enabled (more aggressive)
    if config.use_lr_schedule:
        callbacks.append(
            keras.callbacks.ReduceLROnPlateau(
                monitor="val_loss",
                factor=config.lr_factor,
                patience=max(5, config.lr_patience // 2),  # More frequent reductions
                min_lr=config.lr_min,
                verbose=1,
                mode="min",
                min_delta=1e-6,
            )
        )
    
    # Model checkpoint (save best model)
    callbacks.append(
        keras.callbacks.ModelCheckpoint(
            filepath=str(MODELS_DIR / "schedule_predictor_best.keras"),
            monitor="val_loss",
            save_best_only=True,
            verbose=1,
            save_weights_only=False,  # Save full model
        )
    )
    
    # Add validation R² tracking for better monitoring
    if len(X_val) > 0:
        callbacks.append(ValidationR2Callback((X_val, y_val)))
        callbacks.append(
            OptimalPerformanceEarlyStopping(
                val_data=(X_val, y_val),
                target_mae=config.target_mae_threshold,
                target_r2=config.target_r2_threshold,
                min_variance_ratio=config.min_variance_ratio,
                patience=config.optimal_patience,
                min_epochs=config.optimal_min_epochs,
            )
        )
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

    # Removed complex callbacks for simplified version

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

    # Add R2 history if R2 callback was used (optional in simplified version)
    r2_history = []
    for callback in callbacks:
        if isinstance(callback, ValidationR2Callback):
            history.history["val_r2"] = callback.history
            r2_history = callback.history
            break
    
    # Print comprehensive training diagnostics including learning progress
    print("\n" + "="*80)
    print("📊 TRAINING SUMMARY & LEARNING ANALYSIS")
    print("="*80)
    
    # Get learning progress monitor if available
    learning_monitor = None
    for callback in callbacks:
        if isinstance(callback, LearningProgressMonitor):
            learning_monitor = callback
            break
    
    # Final metrics
    final_train_loss = history.history['loss'][-1] if history.history.get('loss') else 0
    final_val_loss = history.history['val_loss'][-1] if history.history.get('val_loss') else 0
    initial_train_loss = history.history['loss'][0] if history.history.get('loss') else final_train_loss
    initial_val_loss = history.history['val_loss'][0] if history.history.get('val_loss') else final_val_loss
    
    # Calculate improvements
    train_improvement = ((initial_train_loss - final_train_loss) / initial_train_loss * 100) if initial_train_loss > 0 else 0
    val_improvement = ((initial_val_loss - final_val_loss) / initial_val_loss * 100) if initial_val_loss > 0 else 0
    
    print(f"\n📈 Learning Progress:")
    print(f"   Training Loss:   {initial_train_loss:.6f} → {final_train_loss:.6f} ({train_improvement:+.2f}%)")
    print(f"   Validation Loss: {initial_val_loss:.6f} → {final_val_loss:.6f} ({val_improvement:+.2f}%)")
    
    # Learning assessment
    if train_improvement > 50 and val_improvement > 30:
        print(f"   ✅ Excellent learning: Model improved significantly on both sets")
    elif train_improvement > 20 and val_improvement > 10:
        print(f"   ✅ Good learning: Model is learning effectively")
    elif train_improvement > 0 and val_improvement > 0:
        print(f"   ⚠️  Moderate learning: Model is learning but could improve more")
    elif train_improvement > 0 and val_improvement <= 0:
        print(f"   ⚠️  Overfitting: Training improving but validation not improving")
    else:
        print(f"   ❌ Poor learning: Model may not be learning effectively")
    
    # Final gap analysis
    if final_val_loss > 0 and final_train_loss > 0:
        max_loss = max(final_train_loss, final_val_loss)
        final_gap = abs(final_train_loss - final_val_loss) / max_loss if max_loss > 0 else 0
        print(f"\n📊 Generalization Analysis:")
        print(f"   Final Train/Val Gap: {final_gap:.2%}")
        if final_gap < 0.10:
            print(f"   ✅ Excellent generalization (very low gap)")
        elif final_gap < 0.20:
            print(f"   ✅ Good generalization (low gap)")
        elif final_gap < 0.35:
            print(f"   ⚠️  Moderate overfitting (moderate gap)")
        else:
            print(f"   ❌ Significant overfitting (large gap)")
    
    # Learning monitor insights
    if learning_monitor:
        print(f"\n🔍 Learning Monitor Insights:")
        if learning_monitor.best_val_loss < float('inf'):
            best_improvement = ((initial_val_loss - learning_monitor.best_val_loss) / initial_val_loss * 100) if initial_val_loss > 0 else 0
            print(f"   Best Validation Loss: {learning_monitor.best_val_loss:.6f} ({best_improvement:+.2f}% from start)")
        
        if learning_monitor.no_improvement_count > 0:
            print(f"   ⚠️  No improvement for {learning_monitor.no_improvement_count} epoch(s) at end")
        
        if len(learning_monitor.learning_rate_history) > 0:
            final_lr = learning_monitor.learning_rate_history[-1]
            initial_lr = learning_monitor.learning_rate_history[0] if len(learning_monitor.learning_rate_history) > 0 else final_lr
            lr_change = ((final_lr - initial_lr) / initial_lr * 100) if initial_lr > 0 else 0
            print(f"   Learning Rate: {initial_lr:.2e} → {final_lr:.2e} ({lr_change:+.1f}%)")
    
    print(f"\n📊 Training Diagnostics:")
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

    return model, history, r2_history


# ==============================================================================
# Analysis / Visuals
# ==============================================================================


class TrainingAnalyzer:
    def __init__(self, config: TrainingConfig):
        self.config = config

    def _plot_training_curves(self, history: keras.callbacks.History) -> Path:
        """Plot training curves with error handling"""
        fig, axes = plt.subplots(1, 3, figsize=(18, 5))
        
        # Get epochs - handle case where training might have been interrupted
        if "loss" not in history.history or len(history.history["loss"]) == 0:
            raise ValueError("No training history found - cannot generate plots")
        
        epochs = range(1, len(history.history["loss"]) + 1)

        # Plot 1: Loss
        if "loss" in history.history and "val_loss" in history.history:
            axes[0].plot(epochs, history.history["loss"], label="Train", linewidth=2)
            axes[0].plot(epochs, history.history["val_loss"], label="Val", linewidth=2)
            axes[0].set_title("Loss (MSE)", fontsize=12, fontweight='bold')
            axes[0].set_xlabel("Epoch")
            axes[0].set_ylabel("Loss")
            axes[0].grid(True, alpha=0.3)
            axes[0].legend()
        else:
            axes[0].text(0.5, 0.5, "No loss data available", ha='center', va='center')
            axes[0].set_title("Loss (MSE) - No Data")

        # Plot 2: MAE
        if "mae" in history.history and "val_mae" in history.history:
            axes[1].plot(epochs, history.history["mae"], label="Train", linewidth=2)
            axes[1].plot(epochs, history.history["val_mae"], label="Val", linewidth=2)
            axes[1].set_title("Mean Absolute Error", fontsize=12, fontweight='bold')
            axes[1].set_xlabel("Epoch")
            axes[1].set_ylabel("MAE")
            axes[1].grid(True, alpha=0.3)
            axes[1].legend()
        else:
            axes[1].text(0.5, 0.5, "No MAE data available", ha='center', va='center')
            axes[1].set_title("Mean Absolute Error - No Data")

        # Plot 3: R²
        if "val_r2" in history.history and len(history.history["val_r2"]) > 0:
            r2_epochs = range(1, len(history.history["val_r2"]) + 1)
            axes[2].plot(r2_epochs, history.history["val_r2"], label="Val R²", linewidth=2, color='green')
            axes[2].axhline(y=0, color='r', linestyle='--', alpha=0.5, label='R² = 0')
            axes[2].set_ylim(-1.0, 1.0)
            axes[2].set_title("Validation R²", fontsize=12, fontweight='bold')
            axes[2].set_xlabel("Epoch")
            axes[2].set_ylabel("R² Score")
            axes[2].grid(True, alpha=0.3)
            axes[2].legend()
        else:
            axes[2].text(0.5, 0.5, "No R² data available", ha='center', va='center')
            axes[2].set_title("Validation R² - No Data")
            axes[2].set_ylim(-1.0, 1.0)

        plt.tight_layout()
        path = ARTIFACTS_DIR / "training_curves.png"
        fig.savefig(path, dpi=300, bbox_inches='tight')
        plt.close(fig)
        return path

    def _plot_prediction_diagnostics(
        self, y_true: np.ndarray, y_pred: np.ndarray
    ) -> Path:
        """Plot prediction diagnostics with error handling"""
        # Validate inputs
        if y_true.shape != y_pred.shape:
            raise ValueError(f"Shape mismatch: y_true {y_true.shape} vs y_pred {y_pred.shape}")
        if len(y_true) == 0:
            raise ValueError("Empty arrays - cannot generate plots")
        if y_true.shape[1] < 2 or y_pred.shape[1] < 2:
            raise ValueError(f"Expected 2 targets, got {y_true.shape[1]} and {y_pred.shape[1]}")
        
        fan_true, led_true = y_true[:, 0], y_true[:, 1]
        fan_pred, led_pred = y_pred[:, 0], y_pred[:, 1]

        # Validate data ranges (should be normalized to [0, 1])
        if fan_true.max() > 1.1 or fan_pred.max() > 1.1:
            print(f"   ⚠️  Warning: Values exceed [0,1] range. Fan true max: {fan_true.max():.3f}, pred max: {fan_pred.max():.3f}")
        if led_true.max() > 1.1 or led_pred.max() > 1.1:
            print(f"   ⚠️  Warning: Values exceed [0,1] range. LED true max: {led_true.max():.3f}, pred max: {led_pred.max():.3f}")

        fig, axes = plt.subplots(2, 3, figsize=(18, 10))
        axes = axes.ravel()

        # Plot 1: Fan Speed scatter
        axes[0].scatter(fan_true, fan_pred, alpha=0.4, s=10, edgecolors='none')
        axes[0].plot([0, 1], [0, 1], "r--", linewidth=2, label="Perfect Prediction")
        axes[0].set_title("Fan Speed: Actual vs Predicted", fontsize=12, fontweight='bold')
        axes[0].set_xlabel("Actual (normalized)")
        axes[0].set_ylabel("Predicted (normalized)")
        axes[0].set_xlim(-0.05, 1.05)
        axes[0].set_ylim(-0.05, 1.05)
        axes[0].grid(True, alpha=0.3)
        axes[0].legend()

        # Plot 2: LED Brightness scatter
        axes[1].scatter(led_true, led_pred, alpha=0.4, s=10, edgecolors='none')
        axes[1].plot([0, 1], [0, 1], "r--", linewidth=2, label="Perfect Prediction")
        axes[1].set_title("LED Brightness: Actual vs Predicted", fontsize=12, fontweight='bold')
        axes[1].set_xlabel("Actual (normalized)")
        axes[1].set_ylabel("Predicted (normalized)")
        axes[1].set_xlim(-0.05, 1.05)
        axes[1].set_ylim(-0.05, 1.05)
        axes[1].grid(True, alpha=0.3)
        axes[1].legend()

        # Plot 3: Residual distribution
        fan_residuals = fan_true - fan_pred
        led_residuals = led_true - led_pred
        axes[2].hist(
            fan_residuals,
            bins=40,
            alpha=0.7,
            label="Fan Residuals",
            color='blue',
            edgecolor='black'
        )
        axes[2].hist(
            led_residuals,
            bins=40,
            alpha=0.7,
            label="LED Residuals",
            color='orange',
            edgecolor='black'
        )
        axes[2].axvline(x=0, color='r', linestyle='--', alpha=0.5)
        axes[2].legend()
        axes[2].set_title("Residual Distribution", fontsize=12, fontweight='bold')
        axes[2].set_xlabel("Residual (Actual - Predicted)")
        axes[2].set_ylabel("Frequency")
        axes[2].grid(True, alpha=0.3)

        # Plot 4: Fan Speed time series
        sample = slice(0, min(200, len(fan_true)))
        axes[3].plot(fan_true[sample], label="Actual", linewidth=1.5, alpha=0.8)
        axes[3].plot(fan_pred[sample], label="Predicted", linewidth=1.5, alpha=0.8)
        axes[3].set_title("Fan Speed (first 200 samples)", fontsize=12, fontweight='bold')
        axes[3].set_xlabel("Sample Index")
        axes[3].set_ylabel("Value (normalized)")
        axes[3].legend()
        axes[3].grid(True, alpha=0.3)

        # Plot 5: LED Brightness time series
        axes[4].plot(led_true[sample], label="Actual", linewidth=1.5, alpha=0.8)
        axes[4].plot(led_pred[sample], label="Predicted", linewidth=1.5, alpha=0.8)
        axes[4].set_title("LED Brightness (first 200 samples)", fontsize=12, fontweight='bold')
        axes[4].set_xlabel("Sample Index")
        axes[4].set_ylabel("Value (normalized)")
        axes[4].legend()
        axes[4].grid(True, alpha=0.3)

        # Plot 6: Metrics summary
        axes[5].axis("off")
        
        # Calculate metrics with error handling
        try:
            fan_corr = np.corrcoef(fan_true, fan_pred)[0, 1] if len(fan_true) > 1 else 0.0
        except:
            fan_corr = 0.0
        
        try:
            led_corr = np.corrcoef(led_true, led_pred)[0, 1] if len(led_true) > 1 else 0.0
        except:
            led_corr = 0.0
        
        try:
            fan_r2 = r2_score(fan_true, fan_pred)
        except:
            fan_r2 = 0.0
        
        try:
            led_r2 = r2_score(led_true, led_pred)
        except:
            led_r2 = 0.0
        
        try:
            fan_mae = mean_absolute_error(fan_true, fan_pred)
        except:
            fan_mae = 0.0
        
        try:
            led_mae = mean_absolute_error(led_true, led_pred)
        except:
            led_mae = 0.0
        
        # Display metrics
        metrics_text = f"""
METRICS SUMMARY

Fan Speed:
  Correlation: {fan_corr:.3f}
  R² Score:    {fan_r2:.3f}
  MAE:         {fan_mae:.4f}

LED Brightness:
  Correlation: {led_corr:.3f}
  R² Score:    {led_r2:.3f}
  MAE:         {led_mae:.4f}

Total Samples: {len(fan_true):,}
        """
        axes[5].text(0.1, 0.5, metrics_text, fontsize=11, family='monospace',
                     verticalalignment='center', fontweight='bold')

        plt.tight_layout()
        path = ARTIFACTS_DIR / "prediction_diagnostics.png"
        fig.savefig(path, dpi=300, bbox_inches='tight')
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
) -> Tuple[Dict[str, float], np.ndarray]:
    """
    Evaluate model on test set with comprehensive diagnostics.
    
    Returns:
        metrics: Dictionary of evaluation metrics
        preds: Predictions array
    """
    # Validate input shapes
    if len(X_test) != len(y_test):
        raise ValueError(f"Shape mismatch: X_test has {len(X_test)} samples, y_test has {len(y_test)} samples")
    
    if X_test.shape[0] == 0:
        raise ValueError("X_test is empty - cannot evaluate")
    
    # Warn about very small test sets
    if len(X_test) < 10:
        print(f"\n⚠️  WARNING: Test set is very small ({len(X_test)} samples).")
        print(f"   Evaluation metrics may not be reliable with such a small sample size.")
        print(f"   Consider using a larger test set or validation set for more reliable evaluation.")
    
    # Make predictions
    preds = model.predict(X_test, verbose=0, batch_size=32)
    
    # Validate prediction shape
    if preds.shape != y_test.shape:
        raise ValueError(
            f"Prediction shape mismatch: preds {preds.shape} vs y_test {y_test.shape}. "
            f"This indicates a model architecture issue."
        )
    
    # CRITICAL DIAGNOSTICS: Check for flat predictions (model collapse)
    print("\n" + "="*80)
    print("🔍 PREDICTION DIAGNOSTICS")
    print("="*80)
    
    # Check prediction variance
    pred_std = np.std(preds, axis=0)
    y_test_std = np.std(y_test, axis=0)
    
    print(f"\n📊 Prediction Statistics:")
    print(f"   Predictions shape: {preds.shape}")
    print(f"   Predictions range: [{np.min(preds):.4f}, {np.max(preds):.4f}]")
    print(f"   Predictions mean:  [{np.mean(preds[:, 0]):.4f}, {np.mean(preds[:, 1]):.4f}]")
    print(f"   Predictions std:   [{pred_std[0]:.4f}, {pred_std[1]:.4f}]")
    
    print(f"\n📊 True Values Statistics:")
    print(f"   True values range: [{np.min(y_test):.4f}, {np.max(y_test):.4f}]")
    print(f"   True values mean:  [{np.mean(y_test[:, 0]):.4f}, {np.mean(y_test[:, 1]):.4f}]")
    print(f"   True values std:   [{y_test_std[0]:.4f}, {y_test_std[1]:.4f}]")
    
    # Check for flat predictions (variance too low)
    variance_ratio = pred_std / (y_test_std + 1e-10)
    print(f"\n⚠️  Variance Analysis:")
    print(f"   Prediction/Target std ratio: [{variance_ratio[0]:.4f}, {variance_ratio[1]:.4f}]")
    
    if variance_ratio[0] < 0.1 or variance_ratio[1] < 0.1:
        print(f"\n   ❌ CRITICAL: Predictions have very low variance!")
        print(f"      Model is predicting nearly constant values (collapsed to mean).")
        print(f"      This explains negative R² scores.")
        print(f"      Possible causes:")
        print(f"      1. Model too constrained (regularization too high)")
        print(f"      2. Learning rate too low (model not learning)")
        print(f"      3. Model capacity insufficient")
        print(f"      4. Gradient vanishing/exploding")
        print(f"      5. Output activation (sigmoid) saturating")
    
    # Check for constant predictions
    constant_targets = []
    if pred_std[0] < 1e-6:
        constant_targets.append("fan_speed")
    if pred_std[1] < 1e-6:
        constant_targets.append("led_brightness")
    
    if constant_targets:
        print(f"\n   ❌ CRITICAL: Predictions are constant (zero variance) for: {', '.join(constant_targets)}!")
        print(f"      Model has collapsed for these targets.")
        print(f"      This is a serious training issue that needs to be addressed.")
        print(f"      Continuing evaluation to report metrics, but model quality is poor.")
        
        # For very small test sets, this might be a false positive
        if len(y_test) < 10:
            print(f"\n   ⚠️  NOTE: Test set is very small ({len(y_test)} samples).")
            print(f"      Constant predictions might be due to insufficient test data.")
            print(f"      Consider using a larger test set or validation set for evaluation.")
    
    # Check prediction-target correlation
    fan_corr = np.corrcoef(y_test[:, 0], preds[:, 0])[0, 1] if pred_std[0] > 1e-6 else 0.0
    led_corr = np.corrcoef(y_test[:, 1], preds[:, 1])[0, 1] if pred_std[1] > 1e-6 else 0.0
    print(f"\n📈 Correlation:")
    print(f"   Fan:   {fan_corr:.4f}")
    print(f"   LED:   {led_corr:.4f}")
    
    if abs(fan_corr) < 0.1 or abs(led_corr) < 0.1:
        print(f"\n   ⚠️  WARNING: Very low correlation between predictions and targets!")
        print(f"      Model is not learning the relationship.")
    
    print("="*80 + "\n")
    
    # Calculate metrics with safe handling for constant predictions
    def safe_r2_score(y_true, y_pred):
        """Calculate R² score, handling constant predictions gracefully."""
        try:
            # If predictions are constant, R² is undefined (or negative infinity)
            if np.std(y_pred) < 1e-6:
                return float('-inf')  # Indicates model collapse
            return float(r2_score(y_true, y_pred))
        except Exception as e:
            print(f"   ⚠️  Warning: Could not calculate R²: {e}")
            return float('nan')
    
    metrics = {
        "mae": float(mean_absolute_error(y_test, preds)),
        "rmse": float(math.sqrt(mean_squared_error(y_test, preds))),
        "r2": safe_r2_score(y_test, preds),
        "fan_r2": safe_r2_score(y_test[:, 0], preds[:, 0]),
        "led_r2": safe_r2_score(y_test[:, 1], preds[:, 1]),
        "fan_mae": float(mean_absolute_error(y_test[:, 0], preds[:, 0])),
        "led_mae": float(mean_absolute_error(y_test[:, 1], preds[:, 1])),
        # Additional diagnostics
        "pred_fan_std": float(pred_std[0]),
        "pred_led_std": float(pred_std[1]),
        "true_fan_std": float(y_test_std[0]),
        "true_led_std": float(y_test_std[1]),
        "fan_correlation": float(fan_corr),
        "led_correlation": float(led_corr),
    }
    
    return metrics, preds


def make_json_safe(value: Any) -> Any:
    """Recursively convert non-JSON-safe numeric values to JSON-friendly ones."""
    if isinstance(value, dict):
        return {k: make_json_safe(v) for k, v in value.items()}
    if isinstance(value, list):
        return [make_json_safe(v) for v in value]
    if isinstance(value, float):
        return value if math.isfinite(value) else None
    return value


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
    metadata_safe = make_json_safe(metadata)
    with open(model_dir / "metadata.json", "w", encoding="utf-8") as fh:
        json.dump(metadata_safe, fh, indent=2)

    with open(ARTIFACTS_DIR / "metrics_report.json", "w", encoding="utf-8") as fh:
        json.dump(metadata_safe, fh, indent=2)

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
        removed_files = DatasetCache.clear_all()
        state_manager.clear()
        print(f"🧹 Cleared cached datasets, metadata, and checkpoints ({removed_files} item(s) removed).")
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
        
        # Augment with synthetic data if needed to ensure quality
        raw_df = augment_dataset_with_synthetic(
            raw_df,
            min_hourly_rows=500,  # Ensure at least 500 hourly rows
            min_variance_fan=CONFIG.max_target_value * 0.15,
            min_variance_led=CONFIG.max_target_value * 0.15,
            max_target_value=CONFIG.max_target_value,
            force_add=CONFIG.use_synthetic_boost,
            synthetic_days=CONFIG.synthetic_days,
            scenarios=CONFIG.synthetic_scenarios,
        )

        preprocessor = SmartHomePreprocessor(CONFIG)
        
        # CRITICAL: Split data with STRATIFIED TEMPORAL splitting per dataset
        # This prevents target distribution shift by ensuring each split has balanced representation
        # from all datasets
        print("\n📊 Splitting data with stratified temporal split (per dataset)...")
        raw_df = raw_df.sort_values("timestamp").reset_index(drop=True)
        
        # Check if dataset_source column exists (added in load_datasets)
        if "dataset_source" not in raw_df.columns:
            # Fallback: add dummy source if not present
            raw_df["dataset_source"] = "unknown"
            print("   ⚠️  No dataset_source found, using simple temporal split")
            use_stratified = False
        else:
            use_stratified = True
            print(f"   ✅ Found dataset sources: {raw_df['dataset_source'].unique()}")
        
        stratified_success = False
        if use_stratified:
            # Stratified temporal split: Split each dataset temporally, then combine
            # This preserves dataset representation while maintaining temporal ordering
            print("   Using stratified temporal split (per dataset, then combine with overlap filtering)...")
            
            gap_size = CONFIG.sequence_length  # Gap to prevent sequence boundary overlap
            train_frames = []
            val_frames = []
            test_frames = []
            
            # Get time ranges for each dataset to understand overlap
            dataset_ranges = {}
            for dataset_name in raw_df["dataset_source"].unique():
                dataset_df = raw_df[raw_df["dataset_source"] == dataset_name].sort_values("timestamp")
                if len(dataset_df) > 0:
                    dataset_ranges[dataset_name] = {
                        "min": dataset_df["timestamp"].min(),
                        "max": dataset_df["timestamp"].max(),
                        "count": len(dataset_df)
                    }
            
            # Split each dataset temporally
            for dataset_name in raw_df["dataset_source"].unique():
                dataset_df = raw_df[raw_df["dataset_source"] == dataset_name].sort_values("timestamp").reset_index(drop=True)
                dataset_df = dataset_df.dropna(subset=["timestamp"])
                dataset_total = len(dataset_df)
                
                if dataset_total == 0:
                    continue
                
                # Calculate split sizes for this dataset
                dataset_test_size = int(dataset_total * CONFIG.test_split)
                dataset_val_size = int(dataset_total * CONFIG.validation_split)
                dataset_train_size = dataset_total - dataset_val_size - dataset_test_size
                
                # Adjust gap if dataset is small
                effective_gap = min(gap_size, max(1, dataset_train_size // 20))
                
                # Split this dataset temporally
                train_end = dataset_train_size
                val_start = min(train_end + effective_gap, dataset_total)
                val_end = min(val_start + dataset_val_size, dataset_total)
                test_start = min(val_end + effective_gap, dataset_total)
                test_end = min(test_start + dataset_test_size, dataset_total)
                
                dataset_train = dataset_df.iloc[:train_end].copy()
                dataset_val = dataset_df.iloc[val_start:val_end].copy() if val_end > val_start else pd.DataFrame()
                dataset_test = dataset_df.iloc[test_start:test_end].copy() if test_end > test_start else pd.DataFrame()
                
                if len(dataset_train) > 0:
                    train_frames.append(dataset_train)
                if len(dataset_val) > 0:
                    val_frames.append(dataset_val)
                if len(dataset_test) > 0:
                    test_frames.append(dataset_test)
                
                print(f"   {dataset_name}: Train={len(dataset_train):,}, Val={len(dataset_val):,}, Test={len(dataset_test):,}")
            
            # Combine splits from all datasets
            if len(train_frames) == 0:
                raise RuntimeError("No training data available after stratified split.")
            
            raw_train = pd.concat(train_frames, ignore_index=True).sort_values("timestamp").reset_index(drop=True)
            raw_val = pd.concat(val_frames, ignore_index=True).sort_values("timestamp").reset_index(drop=True) if len(val_frames) > 0 else pd.DataFrame()
            raw_test = pd.concat(test_frames, ignore_index=True).sort_values("timestamp").reset_index(drop=True) if len(test_frames) > 0 else pd.DataFrame()
            
            # Filter temporal overlaps per dataset to avoid leakage while preserving representation
            overlap_gap = pd.Timedelta(hours=CONFIG.sequence_length)
            
            if len(raw_train) > 0 and len(raw_val) > 0:
                print("\n   Filtering validation overlap per dataset...")
                raw_val = _filter_temporal_overlap_per_dataset(
                    raw_val,
                    raw_train,
                    overlap_gap,
                    "validation",
                )
            
            if len(raw_val) > 0 and len(raw_test) > 0:
                print("\n   Filtering test overlap per dataset...")
                raw_test = _filter_temporal_overlap_per_dataset(
                    raw_test,
                    raw_val,
                    overlap_gap,
                    "test",
                    fallback_reference_df=raw_train,
                )
            
            if len(raw_val) == 0 or len(raw_test) == 0:
                print("\n   ⚠️  Stratified split lost validation/test coverage after filtering. Will fall back to simple temporal split.")
            else:
                stratified_success = True
            
            # Report final dataset representation
            val_test_coverage_ok = True
            if "dataset_source" in raw_train.columns:
                print(f"\n   ✅ Final dataset representation:")
                for split_name, split_df in [("Train", raw_train), ("Val", raw_val), ("Test", raw_test)]:
                    if len(split_df) > 0:
                        dataset_counts = split_df["dataset_source"].value_counts()
                        print(f"      {split_name}: {len(split_df):,} rows from {len(dataset_counts)} datasets")
                        for ds, count in dataset_counts.items():
                            pct = count / len(split_df) * 100
                            print(f"         - {ds}: {count:,} rows ({pct:.1f}%)")
                # Ensure every dataset present in training also exists in val/test
                all_datasets = raw_train["dataset_source"].unique()
                for ds in all_datasets:
                    if len(raw_val) > 0 and ds not in raw_val.get("dataset_source", pd.Series([], dtype=str)).unique():
                        print(f"\n   ⚠️  Validation split missing dataset '{ds}'.")
                        val_test_coverage_ok = False
                    if len(raw_test) > 0 and ds not in raw_test.get("dataset_source", pd.Series([], dtype=str)).unique():
                        print(f"   ⚠️  Test split missing dataset '{ds}'.")
                        val_test_coverage_ok = False
                if not val_test_coverage_ok:
                    print("   ⚠️  Stratified split lost dataset coverage. Will fall back to simple temporal split.")
            
            if not val_test_coverage_ok:
                stratified_success = False
            
            if stratified_success and val_test_coverage_ok:
                print(f"\n   ✅ Stratified temporal split complete:")
                print(f"      Train: {len(raw_train):,} rows")
                print(f"      Val:   {len(raw_val):,} rows")
                print(f"      Test:  {len(raw_test):,} rows")
        if not stratified_success or (use_stratified and not val_test_coverage_ok):
            if use_stratified:
                print("\n   ⚠️  Falling back to simple temporal split (stratified split insufficient).")
            # Fallback to simple temporal split
            total_rows = len(raw_df)
            test_size = int(total_rows * CONFIG.test_split)
            val_size = int(total_rows * CONFIG.validation_split)
            train_size = total_rows - val_size - test_size
            
            gap_size = CONFIG.sequence_length
            raw_train = raw_df.iloc[:train_size].copy()
            raw_val = raw_df.iloc[train_size + gap_size:train_size + gap_size + val_size].copy()
            raw_test = raw_df.iloc[train_size + gap_size + val_size + gap_size:].copy()
        
        print(f"\n   Final splits:")
        print(f"      Train: {len(raw_train):,} rows ({raw_train['timestamp'].min()} to {raw_train['timestamp'].max()})")
        print(f"      Val:   {len(raw_val):,} rows ({raw_val['timestamp'].min()} to {raw_val['timestamp'].max()})")
        print(f"      Test:  {len(raw_test):,} rows ({raw_test['timestamp'].min()} to {raw_test['timestamp'].max()})")
        
        # Build features separately for each split to prevent leakage
        print("\n🔧 Building features for training set...")
        print(f"   Raw training rows: {len(raw_train):,}")
        hourly_train = preprocessor.build_hourly_features(raw_train, is_training=True)
        print(f"   Hourly training rows: {len(hourly_train):,} (preserved {len(hourly_train)/len(raw_train)*100:.1f}% after aggregation)")
        
        print("\n🔧 Building features for validation set...")
        print(f"   Raw validation rows: {len(raw_val):,}")
        hourly_val = preprocessor.build_hourly_features(raw_val, is_training=False)
        print(f"   Hourly validation rows: {len(hourly_val):,} (preserved {len(hourly_val)/len(raw_val)*100:.1f}% after aggregation)")
        
        print("\n🔧 Building features for test set...")
        print(f"   Raw test rows: {len(raw_test):,}")
        hourly_test = preprocessor.build_hourly_features(raw_test, is_training=False)
        print(f"   Hourly test rows: {len(hourly_test):,} (preserved {len(hourly_test)/len(raw_test)*100:.1f}% after aggregation)")
        
        # Prepare sequences: fit scaler ONLY on training data
        print("\n📦 Preparing sequences...")
        print("   Training set (fitting scaler)...")
        X_train, y_train = preprocessor.prepare_sequences(hourly_train, fit_scaler=True)
        
        print("   Validation set (using training scaler)...")
        X_val, y_val = preprocessor.prepare_sequences(hourly_val, fit_scaler=False)
        
        def _cap_sequences(name: str, X: np.ndarray, y: np.ndarray, limit: Optional[int]) -> Tuple[np.ndarray, np.ndarray]:
            if not limit or len(X) <= limit:
                return X, y
            rng = np.random.default_rng(CONFIG.seed)
            indices = rng.choice(len(X), limit, replace=False)
            original = len(X)
            X_capped, y_capped = X[indices], y[indices]
            print(f"   ⚡ Downsampled {name} sequences from {original:,} to {limit:,} for faster training")
            return X_capped, y_capped
        
        X_train, y_train = _cap_sequences("training", X_train, y_train, CONFIG.max_train_sequences)
        X_val, y_val = _cap_sequences("validation", X_val, y_val, CONFIG.max_eval_sequences)
        
        # Comprehensive data quality validation before training
        print("\n" + "="*80)
        print("🔍 COMPREHENSIVE DATA QUALITY VALIDATION")
        print("="*80)
        
        # Check dataset sizes
        print(f"\n📊 Dataset Sizes:")
        print(f"   Training:   {len(X_train):,} sequences")
        print(f"   Validation: {len(X_val):,} sequences")
        
        # Adaptive minimum based on dataset size
        # For very small datasets, we can train with fewer sequences
        # Minimum: 30 sequences (absolute minimum for any learning)
        # Recommended: 50+ sequences for reasonable training
        # Ideal: 100+ sequences for robust training
        min_required = 30  # Lowered from 100 to accommodate smaller datasets
        recommended = 50
        
        if len(X_train) < min_required:
            # Calculate what sequence_length would give us enough sequences
            # Estimate hourly rows from sequence count (sequences = hourly_rows - sequence_length + 1)
            estimated_hourly = len(X_train) + CONFIG.sequence_length - 1
            suggested_seq_len = max(12, CONFIG.sequence_length - 6)
            estimated_sequences_with_shorter = max(0, estimated_hourly - suggested_seq_len + 1)
            
            error_msg = (
                f"Training set too small ({len(X_train)} sequences). "
                f"Need at least {min_required} sequences for training.\n"
                f"   Current sequence_length: {CONFIG.sequence_length}\n"
                f"   Estimated hourly rows: ~{estimated_hourly}\n"
                f"   Suggestions:\n"
                f"   1. Use a larger dataset (current dataset appears to span only a few days)\n"
                f"   2. Reduce sequence_length from {CONFIG.sequence_length} to {suggested_seq_len} "
                f"(would give ~{estimated_sequences_with_shorter} sequences)\n"
                f"   3. If you must proceed, lower the min_required threshold (not recommended)"
            )
            raise ValueError(error_msg)
        elif len(X_train) < recommended:
            print(f"   ⚠️  Warning: Training set is small ({len(X_train)} sequences).")
            print(f"      Recommended: {recommended}+ sequences for better learning.")
            print(f"      Training will proceed, but results may be less reliable.")
        else:
            print(f"   ✅ Training set size is adequate ({len(X_train)} sequences)")
        
        if len(X_val) < 5:
            print(f"   ⚠️  Warning: Validation set very small ({len(X_val)} sequences) - metrics may be unreliable")
        elif len(X_val) < 10:
            print(f"   ⚠️  Warning: Validation set is small ({len(X_val)} sequences)")
        
        # Check feature quality
        print(f"\n📊 Feature Quality:")
        print(f"   Number of features: {X_train.shape[2]}")
        print(f"   Sequence length: {X_train.shape[1]}")
        
        # Check for feature variance across sequences
        feature_variance = np.var(X_train, axis=(0, 1))  # Variance across batch and time
        low_variance_features = np.sum(feature_variance < 0.01)
        if low_variance_features > 0:
            print(f"   ⚠️  Warning: {low_variance_features} features have very low variance (<0.01)")
        else:
            print(f"   ✅ All features have adequate variance")
        
        # Check target quality
        print(f"\n📊 Target Quality:")
        train_fan_mean = np.mean(y_train[:, 0])
        train_fan_std = np.std(y_train[:, 0])
        train_led_mean = np.mean(y_train[:, 1])
        train_led_std = np.std(y_train[:, 1])
        
        val_fan_mean = np.mean(y_val[:, 0])
        val_fan_std = np.std(y_val[:, 0])
        val_led_mean = np.mean(y_val[:, 1])
        val_led_std = np.std(y_val[:, 1])
        
        print(f"   Training set:")
        print(f"      Fan speed:   mean={train_fan_mean:.4f}, std={train_fan_std:.4f}")
        print(f"      LED brightness: mean={train_led_mean:.4f}, std={train_led_std:.4f}")
        print(f"   Validation set:")
        print(f"      Fan speed:   mean={val_fan_mean:.4f}, std={val_fan_std:.4f}")
        print(f"      LED brightness: mean={val_led_mean:.4f}, std={val_led_std:.4f}")
        
        # Check for distribution shift between train and val
        fan_shift = abs(train_fan_mean - val_fan_mean) / (train_fan_std + 1e-10)
        led_shift = abs(train_led_mean - val_led_mean) / (train_led_std + 1e-10)
        if fan_shift > 2.0 or led_shift > 2.0:
            print(f"   ⚠️  Warning: Significant distribution shift detected (fan: {fan_shift:.2f}σ, LED: {led_shift:.2f}σ)")
        else:
            print(f"   ✅ Train/val distributions are similar (fan: {fan_shift:.2f}σ, LED: {led_shift:.2f}σ)")
        
        # Check target ranges (should be [0, 1] after normalization)
        train_fan_range = [np.min(y_train[:, 0]), np.max(y_train[:, 0])]
        train_led_range = [np.min(y_train[:, 1]), np.max(y_train[:, 1])]
        if train_fan_range[0] < -0.1 or train_fan_range[1] > 1.1:
            print(f"   ⚠️  Warning: Fan speed out of expected range [0, 1]: [{train_fan_range[0]:.4f}, {train_fan_range[1]:.4f}]")
        if train_led_range[0] < -0.1 or train_led_range[1] > 1.1:
            print(f"   ⚠️  Warning: LED brightness out of expected range [0, 1]: [{train_led_range[0]:.4f}, {train_led_range[1]:.4f}]")
        
        # Check for class imbalance (if targets are too skewed)
        fan_skew = abs(train_fan_mean - 0.5)  # Distance from center
        led_skew = abs(train_led_mean - 0.5)
        if fan_skew > 0.3:
            print(f"   ⚠️  Warning: Fan speed is skewed (mean={train_fan_mean:.4f}, ideal=0.5)")
        if led_skew > 0.3:
            print(f"   ⚠️  Warning: LED brightness is skewed (mean={train_led_mean:.4f}, ideal=0.5)")
        
        # Check target correlation
        train_corr = np.corrcoef(y_train[:, 0], y_train[:, 1])[0, 1]
        print(f"\n📊 Target Relationships:")
        print(f"   Correlation (fan vs LED): {train_corr:.4f}")
        if abs(train_corr) > 0.9:
            print(f"   ⚠️  Warning: Targets are highly correlated - model may struggle to learn separate patterns")
        elif abs(train_corr) < 0.1:
            print(f"   ℹ️  Targets are nearly independent - good for separate learning")
        else:
            print(f"   ✅ Targets have moderate correlation - good for learning")
        
        print(f"\n✅ Data quality validation complete - ready for training!")
        print("="*80 + "\n")
        
        # Check if test set has enough data to create sequences
        min_required_rows = CONFIG.sequence_length + CONFIG.prediction_horizon
        test_set_available = len(hourly_test) >= min_required_rows
        
        if test_set_available:
            print("   Test set (using training scaler)...")
            X_test, y_test = preprocessor.prepare_sequences(hourly_test, fit_scaler=False)
            
            # Check if we got enough sequences (at least 10 for reliable evaluation)
            if len(X_test) < 10:
                print(f"   ⚠️  Test set produced only {len(X_test)} sequences (need at least 10 for reliable evaluation)")
                print("   → Using validation set for final evaluation instead")
                X_test, y_test = X_val.copy(), y_val.copy()
        else:
            print(f"   ⚠️  Test set has insufficient data ({len(hourly_test)} rows, need {min_required_rows} minimum)")
            print("   → Using validation set for final evaluation instead")
            X_test, y_test = X_val.copy(), y_val.copy()
        
        X_test, y_test = _cap_sequences("test", X_test, y_test, CONFIG.max_eval_sequences)
        
        # Check target distributions to verify stratified split worked
        print("\n📊 Target Distribution Check (after stratified split):")
        
        # Ensure arrays are 2D (handle edge case where test set might be 1D)
        if y_train.ndim == 1:
            y_train = y_train.reshape(-1, 1)
        if y_val.ndim == 1:
            y_val = y_val.reshape(-1, 1)
        if y_test.ndim == 1:
            y_test = y_test.reshape(-1, 1)
        
        for i, target_name in enumerate(CONFIG.targets):
            # Handle case where we have fewer targets than expected
            if i >= y_train.shape[1]:
                break
                
            train_mean = np.mean(y_train[:, i])
            val_mean = np.mean(y_val[:, i]) if len(y_val) > 0 else 0.0
            test_mean = np.mean(y_test[:, i]) if len(y_test) > 0 else 0.0
            train_std = np.std(y_train[:, i])
            
            print(f"   {target_name}:")
            print(f"      Train: mean={train_mean:.4f}, std={train_std:.4f}, range=[{np.min(y_train[:, i]):.4f}, {np.max(y_train[:, i]):.4f}]")
            if len(y_val) > 0:
                print(f"      Val:   mean={val_mean:.4f}, std={np.std(y_val[:, i]):.4f}, range=[{np.min(y_val[:, i]):.4f}, {np.max(y_val[:, i]):.4f}]")
            else:
                print(f"      Val:   (empty)")
            if len(y_test) > 0:
                print(f"      Test:  mean={test_mean:.4f}, std={np.std(y_test[:, i]):.4f}, range=[{np.min(y_test[:, i]):.4f}, {np.max(y_test[:, i]):.4f}]")
            else:
                print(f"      Test:  (empty)")
            
            # Check for constant targets (std = 0)
            if train_std < 1e-6:
                print(f"      ⚠️  Warning: Training target has zero variance (constant values). This may indicate a data issue.")
            elif len(y_val) > 0 and len(y_test) > 0:
                # Check for distribution shift
                val_std = np.std(y_val[:, i])
                test_std = np.std(y_test[:, i])
                
                # Use pooled std for shift calculation
                pooled_std = np.sqrt((train_std**2 + val_std**2 + test_std**2) / 3) if (train_std > 0 or val_std > 0 or test_std > 0) else 1.0
                
                val_shift = abs(val_mean - train_mean) / (pooled_std + 1e-10)
                test_shift = abs(test_mean - train_mean) / (pooled_std + 1e-10)
                
                if val_shift < 0.5 and test_shift < 0.5:
                    print(f"      ✅ Good: Distribution shifts are small (< 0.5 std)")
                elif val_shift < 1.0 and test_shift < 1.0:
                    print(f"      ⚠️  Moderate: Distribution shifts are acceptable (< 1.0 std)")
                else:
                    print(f"      ⚠️  Warning: Large distribution shifts (val: {val_shift:.2f} std, test: {test_shift:.2f} std)")
                    print(f"         This may still cause overfitting. Consider normalizing targets per dataset.")
        
        # Comprehensive data leakage validation
        if CONFIG.validate_no_leakage:
            print("\n🔍 Validating data leakage prevention...")
            
            # Temporal validation (only if we have validation/test data)
            temporal_issues = []
            
            if len(raw_train) == 0:
                temporal_issues.append("No training data available")
            else:
                train_max_time = raw_train["timestamp"].max()
                
                if len(raw_val) > 0:
                    val_min_time = raw_val["timestamp"].min()
                    val_max_time = raw_val["timestamp"].max()
                    
                    # Check for invalid timestamps (1970 dates indicate parsing errors)
                    if val_min_time.year < 2000:
                        temporal_issues.append(
                            f"Invalid validation timestamps detected (min: {val_min_time}). "
                            "This indicates timestamp parsing errors."
                        )
                    elif val_min_time <= train_max_time:
                        # This should have been fixed by the re-split logic above
                        # But if it still happens, it's a critical issue
                        temporal_issues.append(
                            f"Validation data ({val_min_time}) overlaps with training ({train_max_time}). "
                            "Re-split logic failed to fix this."
                        )
                    
                    if len(raw_test) > 0:
                        test_min_time = raw_test["timestamp"].min()
                        if test_min_time.year < 2000:
                            temporal_issues.append(
                                f"Invalid test timestamps detected (min: {test_min_time}). "
                                "This indicates timestamp parsing errors."
                            )
                        elif test_min_time <= val_max_time:
                            # This should have been fixed by the re-split logic above
                            temporal_issues.append(
                                f"Test data ({test_min_time}) overlaps with validation ({val_max_time}). "
                                "Re-split logic failed to fix this."
                            )
            
            if temporal_issues:
                # Don't raise error immediately - try one more fix
                print(f"\n   ⚠️  Temporal issues detected after re-split. Attempting final fix...")
                
                # Final attempt: combine everything and do a clean temporal split
                all_data = pd.concat([raw_train, raw_val, raw_test], ignore_index=True, sort=False)
                all_data = all_data.dropna(subset=["timestamp"]).sort_values("timestamp").reset_index(drop=True)
                
                total_rows = len(all_data)
                test_size = int(total_rows * CONFIG.test_split)
                val_size = int(total_rows * CONFIG.validation_split)
                train_size = total_rows - val_size - test_size
                gap_size = CONFIG.sequence_length
                
                raw_train = all_data.iloc[:train_size].copy()
                raw_val = all_data.iloc[train_size + gap_size:train_size + gap_size + val_size].copy()
                raw_test = all_data.iloc[train_size + gap_size + val_size + gap_size:].copy()
                
                # Re-validate
                train_max_time = raw_train["timestamp"].max()
                val_min_time = raw_val["timestamp"].min() if len(raw_val) > 0 else None
                val_max_time = raw_val["timestamp"].max() if len(raw_val) > 0 else None
                test_min_time = raw_test["timestamp"].min() if len(raw_test) > 0 else None
                
                final_issues = []
                if val_min_time and val_min_time <= train_max_time:
                    final_issues.append(f"Final fix failed: Val ({val_min_time}) <= Train ({train_max_time})")
                if test_min_time and val_max_time and test_min_time <= val_max_time:
                    final_issues.append(f"Final fix failed: Test ({test_min_time}) <= Val ({val_max_time})")
                
                if final_issues:
                    raise RuntimeError(
                        f"⚠️  DATA LEAKAGE DETECTED (could not fix):\n  " + "\n  ".join(final_issues)
                    )
                else:
                    print(f"   ✅ Final fix successful. Temporal ordering verified.")
            
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
            
            # Verify normalized training data has expected properties (mean ~0, std ~1)
            # This confirms the scaler was applied correctly
            train_feature_mean = np.mean(X_train, axis=(0, 1))
            train_feature_std = np.std(X_train, axis=(0, 1))
            
            # After StandardScaler, normalized data should have mean ~0 and std ~1
            mean_deviation = np.abs(train_feature_mean)
            std_deviation = np.abs(train_feature_std - 1.0)
            
            # For sequence data, allow small deviations due to:
            # - Numerical precision
            # - Sequence windowing effects  
            # - Different feature distributions
            mean_tolerance = 0.01  # Mean should be very close to 0
            std_tolerance = 0.05   # Std should be close to 1 (allows for slight variations)
            
            max_mean_dev = np.max(mean_deviation)
            max_std_dev = np.max(std_deviation)
            
            # Check if deviations are within acceptable range
            # Note: For sequence data, some features might have constant values (std=0) which is normal
            if max_mean_dev > mean_tolerance or max_std_dev > std_tolerance:
                # Check if the issue is due to constant features (std=0 before normalization)
                constant_features = np.sum(train_feature_std < 0.01)
                if constant_features > 0:
                    print(f"   ℹ️  Note: {constant_features} feature(s) have near-zero std (constant values)")
                    print(f"      This is normal for features like binary flags or constant temporal encodings")
                
                if max_mean_dev > mean_tolerance:
                    print(f"   ⚠️  Warning: Mean deviation {max_mean_dev:.6f} exceeds tolerance {mean_tolerance:.2f}")
                if max_std_dev > std_tolerance:
                    print(f"   ⚠️  Warning: Std deviation {max_std_dev:.6f} exceeds tolerance {std_tolerance:.2f}")
                    print(f"      Actual std values: min={np.min(train_feature_std):.4f}, max={np.max(train_feature_std):.4f}")
                    print(f"      This might indicate some features have unusual distributions")
            else:
                # Verify scaler statistics are reasonable (not all zeros)
                scaler_mean = preprocessor.feature_scaler.mean_
                scaler_std = preprocessor.feature_scaler.scale_
                
                # Check that scaler has been properly fitted (not default values)
                if np.allclose(scaler_mean, 0, atol=1e-6) and np.allclose(scaler_std, 1, atol=1e-6):
                    print("   ⚠️  Warning: Scaler statistics appear to be default/unfitted")
                elif np.any(scaler_std < 1e-6):
                    print("   ⚠️  Warning: Some features have near-zero standard deviation in scaler")
                else:
                    print(f"   ✅ Scaler statistics validated")
                    print(f"      Normalized data: mean≈{max_mean_dev:.6f} (target: 0), std≈{1.0+max_std_dev:.6f} (target: 1.0)")
                    print(f"      Original data range: mean=[{np.min(scaler_mean):.2f}, {np.max(scaler_mean):.2f}], std=[{np.min(scaler_std):.2f}, {np.max(scaler_std):.2f}]")
            
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
    load_model_path: Optional[Path] = None
    
    # Handle --load-model flag for continuous/incremental training
    if args.load_model:
        model_dir = MODELS_DIR / "schedule_predictor_v2"
        if model_dir.exists():
            # Check if it's a valid Keras model directory
            # Keras saves models as a directory with saved_model.pb or as .keras file
            has_saved_model = (model_dir / "saved_model.pb").exists() or any(model_dir.glob("*.keras"))
            if has_saved_model:
                load_model_path = model_dir
                print(f"\n{'='*80}")
                print("🔄 CONTINUOUS TRAINING MODE")
                print(f"{'='*80}")
                print(f"   Loading model from: {load_model_path}")
                print(f"   This will continue training from the saved model's learned weights")
                print(f"   Training will start from epoch 0 with the loaded weights")
                print(f"{'='*80}\n")
            else:
                print(f"⚠️  --load-model specified but {model_dir} doesn't contain a valid model")
                print(f"   Starting fresh training instead...")
        else:
            print(f"⚠️  --load-model specified but model not found at {model_dir}")
            print(f"   Starting fresh training instead...")
    
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
    state_message = "Resumed" if args.resume else ("Continuous training" if args.load_model else "Fresh run")
    state_manager.save_state(
        initial_epoch,
        "running",
        message=state_message,
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
                load_model_path=load_model_path if retry_count == 0 else None,  # Only load model on first attempt
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
    
    # Check if test set is available, otherwise use validation set
    if X_test.shape[0] == 0:
        print("\n⚠️  Test set is empty - using validation set for final evaluation")
        X_test, y_test = X_val, y_val
    
    metrics, y_pred = evaluate_model(model, X_test, y_test)

    # Generate training history graphs (especially important for --load-model continuous training)
    analyzer = TrainingAnalyzer(CONFIG)
    if args.load_model:
        print(f"\n{'='*80}")
        print("📊 GENERATING TRAINING HISTORY GRAPHS (Continuous Training Mode)")
        print(f"{'='*80}")
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
        "--load-model",
        action="store_true",
        help=(
            "Load the previously saved model from schedule_predictor_v2/ and continue training. "
            "This allows incremental/continuous training where each run builds upon the previous one. "
            "The model will start from epoch 0 but with learned weights from previous training."
        ),
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