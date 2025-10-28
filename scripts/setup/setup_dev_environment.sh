#!/bin/bash
# Setup development environment

echo "Setting up SmartSync development environment..."

# Install Python dependencies
cd ml
pip install -r requirements.txt
cd ..

# Install Node dependencies for Firebase Functions
cd backend/functions
npm install
cd ../..

echo "Development environment setup complete!"
