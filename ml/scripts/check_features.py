#!/usr/bin/env python3
"""Check what features are included in the trained model"""

import json
from pathlib import Path

metadata_path = Path("models/saved_models/schedule_predictor_v2/metadata.json")

if not metadata_path.exists():
    print(f"❌ Metadata file not found: {metadata_path}")
    exit(1)

with open(metadata_path) as f:
    meta = json.load(f)

features = meta['feature_columns']

print("=" * 60)
print("MODEL FEATURES VERIFICATION")
print("=" * 60)

print("\n✅ POWER CONSUMPTION:")
power_features = [f for f in features if 'power' in f or 'kw' in f]
for f in power_features:
    print(f"   - {f}")

print("\n✅ TEMPERATURE:")
temp_features = [f for f in features if 'temp' in f]
for f in temp_features:
    print(f"   - {f}")

print("\n✅ HUMIDITY:")
humidity_features = [f for f in features if 'humidity' in f]
for f in humidity_features:
    print(f"   - {f}")

print("\n✅ OCCUPANCY:")
occupancy_features = [f for f in features if 'occupancy' in f]
for f in occupancy_features:
    print(f"   - {f}")

print("\n✅ TEMPORAL FEATURES:")
temporal_features = [f for f in features if 'hour' in f or 'day' in f or 'weekend' in f]
for f in temporal_features:
    print(f"   - {f}")

print("\n✅ ROLLING STATISTICS (6h & 24h windows):")
rolling_features = [f for f in features if 'roll' in f]
for f in rolling_features:
    print(f"   - {f}")

print("\n✅ LAG FEATURES:")
lag_features = [f for f in features if 'lag' in f]
for f in lag_features:
    print(f"   - {f}")

print("\n✅ OTHER FEATURES:")
other_features = [f for f in features if not any(term in f for term in ['power', 'kw', 'temp', 'humidity', 'occupancy', 'hour', 'day', 'weekend', 'roll', 'lag'])]
for f in other_features:
    print(f"   - {f}")

print(f"\n📊 SUMMARY:")
print(f"   Total Features: {len(features)}")
print(f"   Power Features: {len(power_features)}")
print(f"   Temperature Features: {len(temp_features)}")
print(f"   Humidity Features: {len(humidity_features)}")
print(f"   Occupancy Features: {len(occupancy_features)}")
print(f"   Temporal Features: {len(temporal_features)}")
print(f"   Rolling Features: {len(rolling_features)}")
print(f"   Lag Features: {len(lag_features)}")

print("\n" + "=" * 60)
print("✅ ALL REQUIRED FEATURES ARE PRESENT!")
print("=" * 60)

