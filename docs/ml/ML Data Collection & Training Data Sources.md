# SmartSync ML Data Collection Guide

## 📊 Overview

This guide explains how to collect training data for SmartSync's machine learning models from multiple sources.

---

## 1. Training Data Sources

### Option A: Firebase Firestore (Real User Data)

**Best for:** Production models after app deployment

**Collections to query:**
- `sensor_logs` - Environmental data (temperature, humidity, motion)
- `logs` - User actions (manual device controls)
- `schedules` - User-created schedules
- `alerts` - Anomalous events

**Time requirements:**
- Minimum: 30 days of data per user
- Optimal: 90+ days for seasonal patterns

---

### Option B: Public Smart Home Datasets

**Best for:** Initial model training before deployment

#### 1. **Kaggle - Smart Home Dataset with Weather**
- **URL:** https://www.kaggle.com/datasets/taranvee/smart-home-dataset-with-weather-information
- **Size:** 100,000+ records
- **Features:** Temperature, humidity, light, CO2, occupancy, time
- **Format:** CSV
- **License:** Open Database License

**How to download:**
```bash
# Install Kaggle CLI
pip install kaggle

# Configure API credentials (get from kaggle.com/account)
mkdir ~/.kaggle
echo '{"username":"YOUR_USERNAME","key":"YOUR_KEY"}' > ~/.kaggle/kaggle.json
chmod 600 ~/.kaggle/kaggle.json

# Download dataset
kaggle datasets download -d taranvee/smart-home-dataset-with-weather-information
unzip smart-home-dataset-with-weather-information.zip -d ml/data/raw/
```

---

#### 2. **UCI Machine Learning Repository - Smart Home Dataset**
- **URL:** https://archive.ics.uci.edu/dataset/196/smart+home+dataset
- **Size:** 30,000+ sensor readings
- **Features:** Motion sensors, temperature, door/window status
- **Format:** ARFF (convertible to CSV)
- **License:** Creative Commons

**How to download:**
```bash
# Download manually from UCI website or use:
wget https://archive.ics.uci.edu/static/public/196/data.csv -O ml/data/raw/uci_smart_home.csv
```

---

#### 3. **Stanford Open Smart Home Dataset**
- **URL:** https://github.com/stanford-oval/home-assistant-datasets
- **Size:** Multiple months of data
- **Features:** Device states, automations, user interactions
- **Format:** JSON
- **License:** MIT

**How to download:**
```bash
git clone https://github.com/stanford-oval/home-assistant-datasets.git ml/data/raw/stanford_home
```

---

#### 4. **CASAS Smart Home Dataset (Washington State University)**
- **URL:** https://casas.wsu.edu/datasets/
- **Focus:** Activity recognition in smart homes
- **Features:** Motion, door, temperature sensors
- **Format:** Text files
- **License:** Research use

**Data files:**
- `casas_aruba.csv` - Single resident, 7 months
- `casas_tulum.csv` - Two residents, 8 months

---

### Option C: Synthetic Data Generation

**Best for:** Testing ML pipeline before real data

See `train_model.py` functions:
- `generate_synthetic_sensor_data(days=90)`
- `generate_synthetic_action_data(days=90)`

---

## 2. Firebase Data Collection Scripts

### Setup Firebase Admin SDK

**File:** `ml/scripts/firebase_setup.py`

```python
#!/usr/bin/env python3
"""Setup Firebase Admin SDK for data collection"""

import firebase_admin
from firebase_admin import credentials, firestore
import os
from pathlib import Path

def initialize_firebase():
    """Initialize Firebase Admin SDK"""
    
    # Download service account key from Firebase Console:
    # Project Settings > Service Accounts > Generate New Private Key
    
    cred_path = Path(__file__).parent.parent / "serviceAccountKey.json"
    
    if not cred_path.exists():
        print(f"❌ Error: {cred_path} not found!")
        print("\nDownload steps:")
        print("1. Go to Firebase Console: https://console.firebase.google.com")
        print("2. Select your project (smartsync-cf370)")
        print("3. Project Settings > Service Accounts")
        print("4. Click 'Generate New Private Key'")
        print(f"5. Save as: {cred_path}")
        return None
    
    cred = credentials.Certificate(str(cred_path))
    firebase_admin.initialize_app(cred)
    
    db = firestore.client()
    print("✅ Firebase initialized successfully")
    
    return db

if __name__ == "__main__":
    initialize_firebase()
```

---

### Collect Historical Data

**File:** `ml/scripts/collect_firebase_data.py`

```python
#!/usr/bin/env python3
"""Collect historical data from Firebase for ML training"""

import pandas as pd
from datetime import datetime, timedelta
from pathlib import Path
import firebase_admin
from firebase_admin import credentials, firestore
from tqdm import tqdm

DATA_DIR = Path(__file__).parent.parent / "data" / "raw"
DATA_DIR.mkdir(parents=True, exist_ok=True)

def collect_all_users_data(db, days=90):
    """
    Collect sensor logs from all users in Firebase
    
    Args:
        db: Firestore client
        days: Number of days to collect
    """
    print(f"📥 Collecting data for last {days} days from all users...")
    
    cutoff_date = datetime.now() - timedelta(days=days)
    
    # Query sensor logs
    sensor_logs_ref = db.collection('sensor_logs')
    query = sensor_logs_ref.where('timestamp', '>=', cutoff_date)
    
    docs = query.stream()
    
    all_data = []
    for doc in tqdm(docs, desc="Fetching sensor logs"):
        data = doc.to_dict()
        data['doc_id'] = doc.id
        all_data.append(data)
    
    # Convert to DataFrame
    df = pd.DataFrame(all_data)
    
    print(f"✅ Collected {len(df)} sensor log records")
    print(f"   Users: {df['userId'].nunique()}")
    print(f"   Devices: {df['deviceId'].nunique()}")
    print(f"   Date range: {df['timestamp'].min()} to {df['timestamp'].max()}")
    
    # Save
    output_path = DATA_DIR / f"firebase_sensor_logs_{days}days.csv"
    df.to_csv(output_path, index=False)
    print(f"💾 Saved to {output_path}")
    
    return df

def collect_action_logs(db, days=90):
    """Collect user action logs"""
    print(f"\n📥 Collecting action logs...")
    
    cutoff_date = datetime.now() - timedelta(days=days)
    
    logs_ref = db.collection('logs')
    query = logs_ref.where('eventType', '==', 'action') \
                   .where('timestamp', '>=', cutoff_date)
    
    docs = query.stream()
    
    actions = []
    for doc in tqdm(docs, desc="Fetching actions"):
        data = doc.to_dict()
        actions.append(data)
    
    df = pd.DataFrame(actions)
    
    print(f"✅ Collected {len(df)} action records")
    
    output_path = DATA_DIR / f"firebase_action_logs_{days}days.csv"
    df.to_csv(output_path, index=False)
    print(f"💾 Saved to {output_path}")
    
    return df

def collect_schedules(db):
    """Collect user-created schedules"""
    print(f"\n📥 Collecting schedules...")
    
    schedules_ref = db.collection('schedules')
    docs = schedules_ref.stream()
    
    schedules = []
    for doc in tqdm(docs, desc="Fetching schedules"):
        schedules.append(doc.to_dict())
    
    df = pd.DataFrame(schedules)
    
    print(f"✅ Collected {len(df)} schedules")
    
    output_path = DATA_DIR / "firebase_schedules.csv"
    df.to_csv(output_path, index=False)
    print(f"💾 Saved to {output_path}")
    
    return df

def main():
    """Main data collection pipeline"""
    
    # Initialize Firebase
    from firebase_setup import initialize_firebase
    db = initialize_firebase()
    
    if db is None:
        return
    
    print("\n" + "="*70)
    print("Firebase Data Collection")
    print("="*70)
    
    # Collect data
    sensor_df = collect_all_users_data(db, days=90)
    action_df = collect_action_logs(db, days=90)
    schedule_df = collect_schedules(db)
    
    # Statistics
    print("\n" + "="*70)
    print("Collection Summary")
    print("="*70)
    print(f"Sensor logs:  {len(sensor_df)} records")
    print(f"Action logs:  {len(action_df)} records")
    print(f"Schedules:    {len(schedule_df)} records")
    print(f"\nData saved to: {DATA_DIR}")
    print("\n✅ Collection complete! Ready for training.")

if __name__ == "__main__":
    main()
```

---

## 3. Data Preprocessing Pipeline

### Convert Public Datasets to SmartSync Format

**File:** `ml/scripts/preprocess_public_data.py`

```python
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
```

---

## 4. Training Workflow

### Complete Training Pipeline

```bash
# 1. Setup Firebase (first time only)
python ml/scripts/firebase_setup.py

# 2. Collect data from Firebase OR download public datasets
python ml/scripts/collect_firebase_data.py  # Firebase
# OR
python ml/scripts/download_public_datasets.sh  # Public datasets

# 3. Preprocess public datasets (if using)
python ml/scripts/preprocess_public_data.py

# 4. Train schedule predictor
python ml/scripts/train_model.py

# 5. Train anomaly detector
python ml/scripts/train_anomaly_detector.py

# 6. Convert to TFLite
python ml/scripts/convert_tflite.py

# 7. Deploy to Firebase
python ml/scripts/deploy_model.py

# 8. Copy to Flutter assets
cp ml/models/tflite/*.tflite app/assets/models/
```

---

## 5. Data Quality Checklist

Before training, ensure:

- ✅ **Sufficient data volume:** >30 days per user (90+ optimal)
- ✅ **Data diversity:** Multiple users, devices, and time periods
- ✅ **Complete features:** All required sensor readings present
- ✅ **Timestamp validity:** Chronological order, no future dates
- ✅ **No excessive missing values:** <5% NaN in critical features
- ✅ **Balanced patterns:** Mix of day/night, weekday/weekend data
- ✅ **Realistic ranges:** Temperature 0-50°C, Humidity 0-100%

### Data Quality Script

```python
def check_data_quality(df):
    """Validate training data quality"""
    
    issues = []
    
    # Check volume
    if len(df) < 720:  # 30 days * 24 hours
        issues.append("⚠️  Insufficient data (<30 days)")
    
    # Check missing values
    missing_pct = df.isnull().sum() / len(df) * 100
    if (missing_pct > 5).any():
        issues.append(f"⚠️  High missing values: {missing_pct[missing_pct > 5]}")
    
    # Check ranges
    if df['temperature'].min() < -20 or df['temperature'].max() > 60:
        issues.append("⚠️  Temperature out of realistic range")
    
    if issues:
        print("\n❌ Data Quality Issues:")
        for issue in issues:
            print(f"   {issue}")
        return False
    else:
        print("\n✅ Data quality checks passed")
        return True
```

---

## 6. Continuous Learning Pipeline

### Scheduled Retraining (Firebase Cloud Functions)

```javascript
// functions/src/ml/scheduledTraining.ts
import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';
import { spawn } from 'child_process';

export const weeklyModelRetraining = functions.pubsub
  .schedule('every sunday 03:00')
  .timeZone('UTC')
  .onRun(async (context) => {
    
    console.log('Starting weekly model retraining...');
    
    // 1. Export recent data from Firestore
    const db = admin.firestore();
    const cutoffDate = new Date();
    cutoffDate.setDate(cutoffDate.getDate() - 90);
    
    const snapshot = await db.collection('sensor_logs')
      .where('timestamp', '>=', cutoffDate)
      .get();
    
    console.log(`Collected ${snapshot.size} records`);
    
    // 2. Trigger Python training script (on Cloud Run or Compute Engine)
    // Note: Cloud Functions don't support TensorFlow, use Cloud Run instead
    
    const trainingResult = await triggerCloudRunTraining(snapshot.docs);
    
    // 3. Deploy updated model
    if (trainingResult.success) {
      await deployNewModel(trainingResult.modelUrl);
      
      // Notify admins
      await sendAdminNotification('ML model retrained successfully');
    }
    
    return null;
  });
```

---

## Next Steps

1. **Choose data source:**
   - Start with public datasets for initial training
   - Switch to Firebase data after app deployment
   
2. **Run training pipeline:**
   ```bash
   cd ml
   python scripts/train_model.py
   python scripts/train_anomaly_detector.py
   python scripts/convert_tflite.py
   ```

3. **Integrate with Flutter:**
   - Copy .tflite models to app/assets
   - Implement MLService (see convert_tflite.py output)
   - Test on real devices

4. **Monitor performance:**
   - Track prediction accuracy
   - Log inference latency
   - Collect user feedback

5. **Iterate:**
   - Retrain models monthly with new data
   - Tune hyperparameters based on metrics
   - Add new features as needed