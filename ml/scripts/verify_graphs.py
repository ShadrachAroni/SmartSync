#!/usr/bin/env python3
"""Verify that the generated graphs are correct"""

from pathlib import Path
import json

ARTIFACTS_DIR = Path("models/saved_models/artifacts")
METADATA_PATH = Path("models/saved_models/schedule_predictor_v2/metadata.json")

print("=" * 60)
print("GRAPH VERIFICATION")
print("=" * 60)

# Check if graph files exist
training_curves = ARTIFACTS_DIR / "training_curves.png"
prediction_diagnostics = ARTIFACTS_DIR / "prediction_diagnostics.png"

print("\n📊 Checking graph files...")
print(f"   Training curves: {'✅ EXISTS' if training_curves.exists() else '❌ MISSING'}")
print(f"   Prediction diagnostics: {'✅ EXISTS' if prediction_diagnostics.exists() else '❌ MISSING'}")

if training_curves.exists():
    size_kb = training_curves.stat().st_size / 1024
    print(f"   Training curves size: {size_kb:.1f} KB")
    if size_kb < 10:
        print("   ⚠️  Warning: File seems too small (might be empty or corrupted)")

if prediction_diagnostics.exists():
    size_kb = prediction_diagnostics.stat().st_size / 1024
    print(f"   Prediction diagnostics size: {size_kb:.1f} KB")
    if size_kb < 10:
        print("   ⚠️  Warning: File seems too small (might be empty or corrupted)")

# Check metadata for expected metrics
if METADATA_PATH.exists():
    print("\n📊 Checking metadata consistency...")
    with open(METADATA_PATH) as f:
        meta = json.load(f)
    
    metrics = meta.get("metrics", {})
    print(f"   Metrics found: {len(metrics)}")
    
    expected_metrics = ["mae", "rmse", "r2", "fan_r2", "led_r2", "fan_mae", "led_mae"]
    for metric in expected_metrics:
        if metric in metrics:
            value = metrics[metric]
            status = "✅" if not (isinstance(value, float) and (value != value or abs(value) > 1e10)) else "⚠️"
            print(f"   {status} {metric}: {value:.4f}")
        else:
            print(f"   ❌ {metric}: MISSING")
    
    # Check if R² values are reasonable (can be negative for poor models)
    if "fan_r2" in metrics and "led_r2" in metrics:
        fan_r2 = metrics["fan_r2"]
        led_r2 = metrics["led_r2"]
        if fan_r2 < -10 or led_r2 < -10:
            print(f"\n   ⚠️  Warning: Very negative R² scores indicate poor model performance")
            print(f"      Fan R²: {fan_r2:.3f}, LED R²: {led_r2:.3f}")
        elif fan_r2 < 0 or led_r2 < 0:
            print(f"\n   ⚠️  Note: Negative R² scores (model worse than baseline)")
            print(f"      Fan R²: {fan_r2:.3f}, LED R²: {led_r2:.3f}")
        else:
            print(f"\n   ✅ R² scores are positive (model better than baseline)")

print("\n" + "=" * 60)
print("VERIFICATION COMPLETE")
print("=" * 60)

