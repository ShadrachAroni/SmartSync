#!/usr/bin/env python3
"""
Deploy ML Models to Firebase Storage - COMPLETE VERSION

This script uploads trained TFLite models to Firebase Storage
and updates Firestore with model metadata for app consumption.

Usage: 
    cd ml
    python scripts/deploy_model.py
"""

import firebase_admin
from firebase_admin import credentials, storage, firestore
from pathlib import Path
import json
from datetime import datetime
import hashlib
import sys

# ==================== CONFIGURATION ====================
PROJECT_ROOT = Path(__file__).parent.parent
TFLITE_DIR = PROJECT_ROOT / "models" / "tflite"
CRED_PATH = PROJECT_ROOT / "serviceAccountKey.json"

# Firebase Storage bucket (update with your project ID)
STORAGE_BUCKET = "smartsync-cf370.firebasestorage.app"
MODELS_PATH = "models/"

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
        print("1. Go to Firebase Console: https://console.firebase.google.com")
        print("2. Select project: smartsync-cf370")
        print("3. Project Settings > Service Accounts")
        print("4. Generate New Private Key")
        print(f"5. Save as: {CRED_PATH}")
        return None, None
    
    try:
        if not firebase_admin._apps:
            cred = credentials.Certificate(str(CRED_PATH))
            firebase_admin.initialize_app(cred, {
                'storageBucket': STORAGE_BUCKET
            })
        
        bucket = storage.bucket()
        db = firestore.client()
        
        print("   ✅ Firebase initialized successfully")
        return bucket, db
        
    except Exception as e:
        print(f"\n❌ Firebase initialization failed: {e}")
        print("\nTroubleshooting:")
        print("1. Verify serviceAccountKey.json is valid")
        print("2. Check Firebase project ID matches")
        print("3. Ensure Storage is enabled in Firebase Console")
        return None, None

# ==================== HELPER FUNCTIONS ====================
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
        Dict with model info or None on failure
    """
    print(f"\n📤 Uploading {model_name}...")
    
    if not model_path.exists():
        print(f"   ❌ Model not found: {model_path}")
        return None
    
    try:
        # Calculate file size and checksum
        file_size = model_path.stat().st_size / 1024 / 1024  # MB
        checksum = calculate_checksum(model_path)
        
        print(f"   File size: {file_size:.2f} MB")
        print(f"   Checksum: {checksum}")
        
        # Upload to Storage
        blob_name = f"{MODELS_PATH}{model_name}_v1.tflite"
        blob = bucket.blob(blob_name)
        
        # Set metadata
        blob.metadata = {
            'version': '1.0.0',
            'uploaded_at': datetime.now().isoformat(),
            'checksum_md5': checksum,
            'size_mb': str(file_size),
            'model_type': model_name
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
        
    except Exception as e:
        print(f"   ❌ Upload failed: {e}")
        return None

def upload_metadata(bucket, metadata_path, model_name):
    """Upload model metadata JSON"""
    print(f"\n📝 Uploading metadata for {model_name}...")
    
    if not metadata_path.exists():
        print(f"   ⚠️  Metadata not found: {metadata_path}")
        return None
    
    try:
        blob_name = f"{MODELS_PATH}{model_name}_v1_metadata.json"
        blob = bucket.blob(blob_name)
        blob.upload_from_filename(str(metadata_path))
        blob.make_public()
        
        print(f"   ✅ Uploaded metadata to: {blob_name}")
        return blob.public_url
        
    except Exception as e:
        print(f"   ❌ Metadata upload failed: {e}")
        return None

# ==================== FIRESTORE UPDATE ====================
def update_firestore_config(db, model_info):
    """
    Update Firestore with model configuration
    
    This allows the Flutter app to:
    1. Check for model updates
    2. Download latest version
    3. Verify model integrity with checksum
    """
    print("\n📊 Updating Firestore configuration...")
    
    try:
        config_ref = db.collection('system_config').document('ml_models')
        
        config_data = {
            'lastUpdated': firestore.SERVER_TIMESTAMP,
            'models': {}
        }
        
        # Add each model's info
        for model_name, info in model_info.items():
            config_data['models'][model_name] = {
                'currentVersion': info['version'],
                'downloadUrl': info['url'],
                'checksum': info['checksum'],
                'sizeMB': info['size_mb'],
                'minAppVersion': '1.0.0',
                'releaseDate': datetime.now().isoformat(),
                'changelog': f'Initial release - {model_name}',
                'deployed': True,
                'modelPath': info['path']
            }
        
        config_ref.set(config_data, merge=True)
        
        print("   ✅ Firestore updated successfully")
        print(f"   Collection: system_config")
        print(f"   Document: ml_models")
        print(f"   Models: {', '.join(model_info.keys())}")
        
        return True
        
    except Exception as e:
        print(f"   ❌ Firestore update failed: {e}")
        return False

def create_model_version_history(db, model_info):
    """Create version history for rollback capability"""
    print("\n📚 Creating version history...")
    
    try:
        for model_name, info in model_info.items():
            version_ref = db.collection('ml_model_versions').document()
            
            version_ref.set({
                'modelName': model_name,
                'version': info['version'],
                'downloadUrl': info['url'],
                'checksum': info['checksum'],
                'sizeMB': info['size_mb'],
                'deployedAt': firestore.SERVER_TIMESTAMP,
                'deployedBy': 'deployment_script',
                'status': 'active'
            })
        
        print("   ✅ Version history created")
        
    except Exception as e:
        print(f"   ⚠️  Version history creation failed: {e}")

# ==================== VERIFICATION ====================
def verify_deployment(bucket, model_info):
    """Verify models are accessible"""
    print("\n🔍 Verifying deployment...")
    
    all_verified = True
    
    for model_name, info in model_info.items():
        try:
            # Check if blob exists
            blob = bucket.blob(info['path'])
            if blob.exists():
                print(f"   ✅ {model_name}: Accessible")
            else:
                print(f"   ❌ {model_name}: Not found in storage")
                all_verified = False
                
        except Exception as e:
            print(f"   ❌ {model_name}: Verification failed - {e}")
            all_verified = False
    
    return all_verified

# ==================== MAIN DEPLOYMENT ====================
def main():
    """Main deployment pipeline"""
    
    # Check if models exist locally
    schedule_model = TFLITE_DIR / "schedule_predictor.tflite"
    anomaly_model = TFLITE_DIR / "anomaly_detector.tflite"
    
    if not schedule_model.exists() and not anomaly_model.exists():
        print(f"\n❌ No TFLite models found in {TFLITE_DIR}")
        print(f"\n   Run conversion first:")
        print(f"   python scripts/convert_tflite.py")
        sys.exit(1)
    
    # Initialize Firebase
    bucket, db = initialize_firebase()
    if bucket is None or db is None:
        sys.exit(1)
    
    print("\n" + "="*70)
    print("DEPLOYING MODELS")
    print("="*70)
    
    model_info = {}
    
    # Upload schedule predictor
    if schedule_model.exists():
        schedule_info = upload_model(bucket, schedule_model, 'schedule_predictor')
        if schedule_info:
            model_info['schedule_predictor'] = {
                'version': '1.0.0',
                'url': schedule_info['url'],
                'checksum': schedule_info['checksum'],
                'size_mb': schedule_info['size_mb'],
                'path': schedule_info['path']
            }
            
            # Upload metadata
            schedule_metadata = TFLITE_DIR / "schedule_predictor.json"
            if schedule_metadata.exists():
                upload_metadata(bucket, schedule_metadata, 'schedule_predictor')
    
    # Upload anomaly detector
    if anomaly_model.exists():
        anomaly_info = upload_model(bucket, anomaly_model, 'anomaly_detector')
        if anomaly_info:
            model_info['anomaly_detector'] = {
                'version': '1.0.0',
                'url': anomaly_info['url'],
                'checksum': anomaly_info['checksum'],
                'size_mb': anomaly_info['size_mb'],
                'path': anomaly_info['path']
            }
            
            # Upload metadata
            anomaly_metadata = TFLITE_DIR / "anomaly_detector.json"
            if anomaly_metadata.exists():
                upload_metadata(bucket, anomaly_metadata, 'anomaly_detector')
    
    if not model_info:
        print("\n❌ No models were uploaded successfully")
        sys.exit(1)
    
    # Update Firestore
    if update_firestore_config(db, model_info):
        # Create version history
        create_model_version_history(db, model_info)
        
        # Verify deployment
        if verify_deployment(bucket, model_info):
            print("\n" + "="*70)
            print("✅ DEPLOYMENT COMPLETE!")
            print("="*70)
            
            print(f"\n📦 Deployed Models:")
            for model_name, info in model_info.items():
                print(f"\n  {model_name}:")
                print(f"    Version:  {info['version']}")
                print(f"    Size:     {info['size_mb']:.2f} MB")
                print(f"    Checksum: {info['checksum'][:16]}...")
                print(f"    URL:      {info['url'][:60]}...")
            
            print(f"\n📱 Flutter Integration:")
            print(f"  1. Models are now in Firebase Storage")
            print(f"  2. Metadata available in Firestore: system_config/ml_models")
            print(f"  3. App will auto-download on first run")
            print(f"  4. Next: Set up Cloud Functions for server-side inference")
            
        else:
            print("\n⚠️  Deployment completed with warnings")
    else:
        print("\n❌ Firestore update failed - deployment incomplete")
        sys.exit(1)

if __name__ == "__main__":
    main()