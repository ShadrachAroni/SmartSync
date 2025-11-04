#!/usr/bin/env python3
"""
Deploy TensorFlow.js models to Firebase Storage
"""

import firebase_admin
from firebase_admin import credentials, storage, firestore
from pathlib import Path
import json

PROJECT_ROOT = Path(__file__).parent.parent
TFJS_DIR = PROJECT_ROOT / "models" / "tfjs"
PROCESSED_DIR = PROJECT_ROOT / "data" / "processed"
CRED_PATH = PROJECT_ROOT / "serviceAccountKey.json"

STORAGE_BUCKET = "smartsync-cf370.appspot.com"

def initialize_firebase():
    """Initialize Firebase Admin SDK"""
    if not CRED_PATH.exists():
        print(f"❌ Error: {CRED_PATH} not found!")
        return None, None
    
    if not firebase_admin._apps:
        cred = credentials.Certificate(str(CRED_PATH))
        firebase_admin.initialize_app(cred, {
            'storageBucket': STORAGE_BUCKET
        })
    
    bucket = storage.bucket()
    db = firestore.client()
    
    return bucket, db

def upload_tfjs_model(bucket, model_name):
    """Upload TFJS model directory to Storage"""
    print(f"\n📤 Uploading {model_name}...")
    
    model_dir = TFJS_DIR / f"{model_name}_v1"
    
    if not model_dir.exists():
        print(f"   ❌ Model directory not found: {model_dir}")
        return None
    
    uploaded_files = []
    
    # Upload all files in the model directory
    for file_path in model_dir.glob("*"):
        blob_name = f"models/{model_name}_v1/{file_path.name}"
        blob = bucket.blob(blob_name)
        
        print(f"   Uploading {file_path.name}...")
        blob.upload_from_filename(str(file_path))
        blob.make_public()
        
        uploaded_files.append({
            'name': file_path.name,
            'url': blob.public_url,
            'size': file_path.stat().st_size
        })
    
    # Get model.json URL
    model_json_url = next(
        (f['url'] for f in uploaded_files if f['name'] == 'model.json'),
        None
    )
    
    print(f"   ✅ Uploaded {len(uploaded_files)} files")
    print(f"   🔗 Model URL: {model_json_url}")
    
    return {
        'model_url': model_json_url,
        'files': uploaded_files
    }

def upload_scaler_json(bucket):
    """Convert and upload scaler as JSON"""
    print(f"\n📤 Uploading scaler parameters...")
    
    scaler_path = PROCESSED_DIR / "scaler.pkl"
    
    if not scaler_path.exists():
        print(f"   ⚠️  Scaler not found: {scaler_path}")
        return None
    
    import joblib
    scaler = joblib.load(scaler_path)
    
    # Convert to JSON
    scaler_json = {
        'mean': scaler.mean_.tolist(),
        'scale': scaler.scale_.tolist(),
        'var': scaler.var_.tolist(),
        'n_features': int(scaler.n_features_in_),
        'feature_names': [
            'temperature_mean', 'temperature_max', 'temperature_min',
            'humidity_mean', 'motionDetected_sum', 'distance_mean',
            'hour_sin', 'hour_cos', 'day_sin', 'day_cos',
            'is_weekend', 'is_night', 'manual_actions'
        ]
    }
    
    # Upload to Storage
    blob = bucket.blob("models/schedule_predictor_v1/scaler.json")
    blob.upload_from_string(
        json.dumps(scaler_json, indent=2),
        content_type='application/json'
    )
    blob.make_public()
    
    print(f"   ✅ Uploaded scaler.json")
    print(f"   🔗 URL: {blob.public_url}")
    
    return blob.public_url

def update_firestore_config(db, model_info, scaler_url):
    """Update Firestore with model configuration"""
    print(f"\n📊 Updating Firestore configuration...")
    
    config_ref = db.collection('system_config').document('ml_models')
    
    config_data = {
        'lastUpdated': firestore.SERVER_TIMESTAMP,
        'models': {
            'schedule_predictor': {
                'currentVersion': 'v1',
                'format': 'tfjs',
                'modelUrl': model_info['model_url'],
                'scalerUrl': scaler_url,
                'deployed': True,
                'deployedAt': firestore.SERVER_TIMESTAMP
            }
        }
    }
    
    config_ref.set(config_data, merge=True)
    print(f"   ✅ Firestore updated")

def main():
    print("=" * 70)
    print("Deploy TensorFlow.js Models to Firebase")
    print("=" * 70)
    
    # Initialize Firebase
    bucket, db = initialize_firebase()
    if not bucket:
        return
    
    # Upload TFJS model
    model_info = upload_tfjs_model(bucket, "schedule_predictor")
    if not model_info:
        return
    
    # Upload scaler
    scaler_url = upload_scaler_json(bucket)
    
    # Update Firestore
    update_firestore_config(db, model_info, scaler_url)
    
    print("\n" + "=" * 70)
    print("✅ DEPLOYMENT COMPLETE!")
    print("=" * 70)
    print(f"\n📦 Deployed:")
    print(f"   • TFJS Model: {model_info['model_url']}")
    print(f"   • Scaler: {scaler_url}")
    print(f"\n🚀 Next: Deploy Cloud Functions")
    print(f"   cd backend && firebase deploy --only functions")

if __name__ == "__main__":
    main()