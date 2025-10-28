#!/bin/bash
# Install all project dependencies

echo "Installing dependencies..."

# Python
pip install -r ml/requirements.txt

# Node.js
cd backend/functions && npm install && cd ../..

echo "Dependencies installed!"
