#!/bin/bash
# Update ML model

echo "Updating ML model..."

cd ml
python scripts/train_model.py
python scripts/convert_tflite.py
python scripts/deploy_model.py
cd ..

echo "ML model updated!"
