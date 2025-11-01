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