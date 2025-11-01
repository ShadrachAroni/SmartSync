#!/usr/bin/env python3
"""
Deploy ML Models to Firebase Storage

This script uploads trained TFLite models to Firebase Storage
and updates Firestore with model metadata for app consumption.

Usage: python scripts/deploy_model.py
"""

import firebase_admin
from firebase_admin import credentials, storage, firestore
from pathlib import Path
import json
from datetime import datetime
import hashlib

# ==================== CONFIGURATION ====================
PROJECT_ROOT = Path(__file__).parent.parent
TFLITE_DIR = PROJECT_ROOT / "models" / "tflite"
CRED_PATH = PROJECT_ROOT / "serviceAccountKey.json"

# Firebase Storage paths
STORAGE_BUCKET = "smartsync-cf370.appspot.com"
MODELS_PATH = "ml_models/"

print("=" * 70)
print("Deploy ML Models to Firebase")
print("=" * 70)

# ==================== FIREBASE INITIALIZATION ====================
def initialize_firebase():
    """Initialize Firebase Admin SDK"""
    print("\n🔧 Initializing Firebase...")
    
    if not CRED_PATH.exists():
        print(f"\n❌ Error: {CRED_PATH} not found!")
        print("\nDownload steps:")
        print("1. Go to Firebase Console")
        print("2. Project Settings > Service Accounts")
        print("3. Generate New Private Key")
        print(f"4. Save as: {CRED_PATH}")
        return None, None
    
    if not firebase_admin._apps:
        cred = credentials.Certificate(str(CRED_PATH))
        firebase_admin.initialize_app(cred, {
            'storageBucket': STORAGE_BUCKET
        })
    
    bucket = storage.bucket()
    db = firestore.client()
    
    print("   ✅ Firebase initialized")
    return bucket, db

# ==================== UPLOAD FUNCTIONS ====================
def calculate_checksum(file_path):
    """Calculate MD5 checksum of file"""
    md5 = hashlib.md5()
    with open(file_path, 'rb') as f:
        for chunk in iter(lambda: f.read(4096), b""):
            md5.update(chunk)
    return md5.hexdigest()

def upload_model(bucket, model_path, model_name):
    """
    Upload TFLite model to Firebase Storage
    
    Args:
        bucket: Firebase Storage bucket
        model_path: Local path to .tflite file
        model_name: Name identifier (e.g., 'schedule_predictor')
    
    Returns:
        Public URL of uploaded model
    """
    print(f"\n📤 Uploading {model_name}...")
    
    if not model_path.exists():
        print(f"   ❌ Model not found: {model_path}")
        return None
    
    # Calculate file size and checksum
    file_size = model_path.stat().st_size / 1024 / 1024  # MB
    checksum = calculate_checksum(model_path)
    
    print(f"   File size: {file_size:.2f} MB")
    print(f"   Checksum: {checksum}")
    
    # Upload to Storage
    blob_name = f"{MODELS_PATH}{model_name}.tflite"
    blob = bucket.blob(blob_name)
    
    # Set metadata
    blob.metadata = {
        'version': '1.0.0',
        'uploaded_at': datetime.now().isoformat(),
        'checksum_md5': checksum,
        'size_mb': str(file_size)
    }
    
    blob.upload_from_filename(str(model_path))
    blob.make_public()
    
    public_url = blob.public_url
    print(f"   ✅ Uploaded to: {blob_name}")
    print(f"   🔗 Public URL: {public_url}")
    
    return {
        'url': public_url,
        'path': blob_name,
        'size_mb': file_size,
        'checksum': checksum
    }

def upload_metadata(bucket, metadata_path, model_name):
    """Upload model metadata JSON"""
    print(f"\n📝 Uploading metadata for {model_name}...")
    
    if not metadata_path.exists():
        print(f"   ⚠️  Metadata not found: {metadata_path}")
        return None
    
    blob_name = f"{MODELS_PATH}{model_name}_metadata.json"
    blob = bucket.blob(blob_name)
    blob.upload_from_filename(str(metadata_path))
    blob.make_public()
    
    print(f"   ✅ Uploaded metadata")
    return blob.public_url

# ==================== FIRESTORE UPDATE ====================
def update_firestore_config(db, model_info):
    """
    Update Firestore with model configuration
    
    This allows the Flutter app to check for model updates
    and download the latest version.
    """
    print("\n📊 Updating Firestore configuration...")
    
    config_ref = db.collection('system_config').document('ml_models')
    
    config_data = {
        'schedule_predictor': {
            'currentVersion': model_info['schedule_predictor']['version'],
            'downloadUrl': model_info['schedule_predictor']['url'],
            'checksum': model_info['schedule_predictor']['checksum'],
            'sizeMB': model_info['schedule_predictor']['size_mb'],
            'minAppVersion': '1.0.0',
            'releaseDate': datetime.now().isoformat(),
            'changelog': 'Initial release - trained on public datasets',
            'deployed': True
        },
        'last_updated': firestore.SERVER_TIMESTAMP
    }
    
    config_ref.set(config_data, merge=True)
    
    print("   ✅ Firestore updated")
    print(f"   Collection: system_config")
    print(f"   Document: ml_models")

# ==================== MAIN DEPLOYMENT ====================
def main():
    """Main deployment pipeline"""
    
    # Initialize Firebase
    bucket, db = initialize_firebase()
    if bucket is None:
        return
    
    # Check if models exist
    schedule_model = TFLITE_DIR / "schedule_predictor.tflite"
    schedule_metadata = TFLITE_DIR / "schedule_predictor.json"
    
    if not schedule_model.exists():
        print(f"\n❌ TFLite model not found!")
        print(f"   Expected: {schedule_model}")
        print(f"\n   Run conversion first:")
        print(f"   python scripts/convert_tflite.py")
        return
    
    print("\n" + "="*70)
    print("DEPLOYING MODELS")
    print("="*70)
    
    # Upload schedule predictor
    model_info = {}
    
    schedule_info = upload_model(bucket, schedule_model, 'schedule_predictor')
    if schedule_info:
        model_info['schedule_predictor'] = {
            'version': '1.0.0',
            'url': schedule_info['url'],
            'checksum': schedule_info['checksum'],
            'size_mb': schedule_info['size_mb']
        }
        
        # Upload metadata if exists
        if schedule_metadata.exists():
            upload_metadata(bucket, schedule_metadata, 'schedule_predictor')
    
    # Upload anomaly detector (if exists)
    anomaly_model = TFLITE_DIR / "anomaly_detector.tflite"
    if anomaly_model.exists():
        anomaly_info = upload_model(bucket, anomaly_model, 'anomaly_detector')
        if anomaly_info:
            model_info['anomaly_detector'] = {
                'version': '1.0.0',
                'url': anomaly_info['url'],
                'checksum': anomaly_info['checksum'],
                'size_mb': anomaly_info['size_mb']
            }
    
    # Update Firestore
    if model_info:
        update_firestore_config(db, model_info)
    
    # Summary
    print("\n" + "="*70)
    print("✅ DEPLOYMENT COMPLETE!")
    print("="*70)
    print(f"\nDeployed Models:")
    for model_name, info in model_info.items():
        print(f"  • {model_name}:")
        print(f"    Version: {info['version']}")
        print(f"    Size: {info['size_mb']:.2f} MB")
        print(f"    URL: {info['url']}")
    
    print(f"\nFlutter Integration:")
    print(f"  1. Models are now available in Firebase Storage")
    print(f"  2. App will auto-download on first run")
    print(f"  3. Check system_config/ml_models in Firestore")

if __name__ == "__main__":
    main()