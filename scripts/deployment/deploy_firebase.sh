#!/bin/bash
# Deploy Firebase backend

echo "Deploying Firebase backend..."

cd backend
firebase deploy --only functions,firestore,storage
cd ..

echo "Firebase backend deployed!"
