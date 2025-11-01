#!/usr/bin/env python3
"""Convert public datasets to SmartSync format"""

import pandas as pd
from pathlib import Path
from datetime import datetime

RAW_DIR = Path(__file__).parent.parent / "data" / "raw"
PROCESSED_DIR = Path(__file__).parent.parent / "data" / "processed"
PROCESSED_DIR.mkdir(parents=True, exist_ok=True)

def process_kaggle_dataset():
    """
    Convert Kaggle Smart Home dataset to SmartSync format
    
    Input columns: timestamp, temperature, humidity, light, co2, humidity_ratio, occupancy
    Output: SmartSync sensor_logs format
    """
    print("🔄 Processing Kaggle dataset...")
    
    kaggle_path = RAW_DIR / "Occupancy_Estimation.csv"  # Adjust filename
    
    if not kaggle_path.exists():
        print(f"⚠️  {kaggle_path} not found. Skipping.")
        return None
    
    df = pd.read_csv(kaggle_path)
    
    # Convert to SmartSync format
    smartsync_df = pd.DataFrame({
        'timestamp': pd.to_datetime(df['date']),
        'deviceId': 'kaggle_synthetic',
        'userId': 'training_data',
        'temperature': df['Temperature'],
        'humidity': df['Humidity'],
        'motionDetected': df['Occupancy'],  # 1 if occupied
        'fanSpeed': (df['Temperature'] > 24).astype(int) * 128,  # Fan on if temp > 24
        'ledBrightness': (df['Light'] > 0).astype(int) * 255,
        'distance': 100  # Placeholder
    })
    
    output_path = PROCESSED_DIR / "kaggle_smartsync_format.csv"
    smartsync_df.to_csv(output_path, index=False)
    
    print(f"✅ Processed {len(smartsync_df)} records")
    print(f"   Saved to {output_path}")
    
    return smartsync_df

def process_uci_dataset():
    """Convert UCI Smart Home dataset"""
    print("\n🔄 Processing UCI dataset...")
    
    uci_path = RAW_DIR / "uci_smart_home.csv"
    
    if not uci_path.exists():
        print(f"⚠️  {uci_path} not found. Skipping.")
        return None
    
    # Process UCI data (format varies, adjust accordingly)
    # ...
    
    return None

def merge_all_datasets():
    """Merge all datasets into single training file"""
    print("\n📦 Merging all datasets...")
    
    all_files = list(PROCESSED_DIR.glob("*_smartsync_format.csv"))
    
    if not all_files:
        print("⚠️  No processed datasets found.")
        return
    
    dfs = [pd.read_csv(f) for f in all_files]
    merged = pd.concat(dfs, ignore_index=True)
    
    # Sort by timestamp
    merged = merged.sort_values('timestamp')
    
    output_path = PROCESSED_DIR / "merged_training_data.csv"
    merged.to_csv(output_path, index=False)
    
    print(f"✅ Merged {len(merged)} total records")
    print(f"   Output: {output_path}")

def main():
    """Main preprocessing pipeline"""
    
    print("="*70)
    print("Public Dataset Preprocessing")
    print("="*70)
    
    process_kaggle_dataset()
    process_uci_dataset()
    merge_all_datasets()
    
    print("\n✅ Preprocessing complete!")

if __name__ == "__main__":
    main()