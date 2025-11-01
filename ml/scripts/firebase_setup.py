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