#!/usr/bin/env python3
"""
Convert Keras models to TensorFlow.js format for Cloud Functions
"""

import tensorflowjs as tfjs
import tensorflow as tf
from pathlib import Path
import json

PROJECT_ROOT = Path(__file__).parent.parent
MODELS_DIR = PROJECT_ROOT / "models" / "saved_models"
TFJS_DIR = PROJECT_ROOT / "models" / "tfjs"

TFJS_DIR.mkdir(parents=True, exist_ok=True)

def convert_to_tfjs(model_name):
    """Convert Keras model to TFJS format"""
    print(f"\n🔄 Converting {model_name} to TFJS format...")
    
    model_path = MODELS_DIR / f"{model_name}_v1"
    output_path = TFJS_DIR / f"{model_name}_v1"
    
    if not model_path.exists():
        print(f"   ❌ Model not found: {model_path}")
        return False
    
    # Load Keras model
    model = tf.keras.models.load_model(model_path)
    print(f"   ✅ Loaded Keras model")
    
    # Convert to TFJS
    tfjs.converters.save_keras_model(model, str(output_path))
    print(f"   ✅ Converted to TFJS format")
    
    # Verify output files
    model_json = output_path / "model.json"
    if model_json.exists():
        print(f"   ✅ Created: model.json")
        
        # List weight files
        weight_files = list(output_path.glob("group*.bin"))
        print(f"   ✅ Created: {len(weight_files)} weight shard(s)")
        
        # Get total size
        total_size = sum(f.stat().st_size for f in output_path.glob("*"))
        print(f"   📦 Total size: {total_size / 1024 / 1024:.2f} MB")
        
        return True
    else:
        print(f"   ❌ Conversion failed - model.json not found")
        return False

def main():
    print("=" * 70)
    print("Convert Keras Models to TensorFlow.js Format")
    print("=" * 70)
    
    # Install tensorflowjs if needed
    try:
        import tensorflowjs
    except ImportError:
        print("\n⚠️  tensorflowjs not installed!")
        print("   Run: pip install tensorflowjs")
        return
    
    # Convert schedule predictor
    success = convert_to_tfjs("schedule_predictor")
    
    if success:
        print("\n" + "=" * 70)
        print("✅ CONVERSION COMPLETE!")
        print("=" * 70)
        print(f"\n📁 Output: {TFJS_DIR}")
        print(f"\n🚀 Next steps:")
        print(f"   1. Deploy to Firebase: python scripts/deploy_tfjs.py")
        print(f"   2. Update Cloud Functions to use model.json")
    else:
        print("\n❌ Conversion failed")

if __name__ == "__main__":
    main()