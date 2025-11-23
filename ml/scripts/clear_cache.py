#!/usr/bin/env python3
"""
Clear all checkpoints and cache files for training.
This will delete:
- All checkpoint files in models/saved_models/checkpoints/
- All cache files in models/saved_models/artifacts/cache/
- Best model checkpoint (schedule_predictor_best.keras)
- Pause flag file
- Training state files
"""

from pathlib import Path

# Define paths directly (matching train_smart_home.py)
PROJECT_ROOT = Path(__file__).resolve().parent.parent
MODELS_DIR = PROJECT_ROOT / "models" / "saved_models"
ARTIFACTS_DIR = MODELS_DIR / "artifacts"
CACHE_DIR = ARTIFACTS_DIR / "cache"
CHECKPOINT_DIR = MODELS_DIR / "checkpoints"
PAUSE_FLAG_PATH = ARTIFACTS_DIR / "pause.flag"

def clear_all():
    """Clear all checkpoints and cache files."""
    print("🧹 Clearing all checkpoints and cache...")
    
    deleted_count = 0
    
    # Clear checkpoint directory
    if CHECKPOINT_DIR.exists():
        for checkpoint_file in CHECKPOINT_DIR.glob("*"):
            if checkpoint_file.is_file():
                checkpoint_file.unlink()
                deleted_count += 1
                print(f"   ✓ Deleted checkpoint: {checkpoint_file.name}")
    
    # Clear cache directory
    if CACHE_DIR.exists():
        for cache_file in CACHE_DIR.glob("*"):
            if cache_file.is_file():
                cache_file.unlink()
                deleted_count += 1
                print(f"   ✓ Deleted cache: {cache_file.name}")
    
    # Clear best model checkpoint
    best_model = MODELS_DIR / "schedule_predictor_best.keras"
    if best_model.exists():
        best_model.unlink()
        deleted_count += 1
        print(f"   ✓ Deleted best model: {best_model.name}")
    
    # Clear pause flag
    if PAUSE_FLAG_PATH.exists():
        PAUSE_FLAG_PATH.unlink()
        deleted_count += 1
        print(f"   ✓ Deleted pause flag")
    
    # Also clear old checkpoint files from train_model.py
    old_checkpoint = MODELS_DIR / "schedule_predictor_latest.weights.h5"
    if old_checkpoint.exists():
        old_checkpoint.unlink()
        deleted_count += 1
        print(f"   ✓ Deleted old checkpoint: {old_checkpoint.name}")
    
    old_state = MODELS_DIR / "schedule_predictor_state.json"
    if old_state.exists():
        old_state.unlink()
        deleted_count += 1
        print(f"   ✓ Deleted old state file: {old_state.name}")
    
    print(f"\n✅ Cleared {deleted_count} file(s)")
    print("   All checkpoints and cache have been reset.")
    print("   Next training run will start from scratch.")

if __name__ == "__main__":
    try:
        clear_all()
    except Exception as e:
        print(f"\n❌ Error clearing cache: {e}")
        sys.exit(1)

