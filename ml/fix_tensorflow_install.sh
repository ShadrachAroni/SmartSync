#!/bin/bash
# Fix corrupted TensorFlow installation by cleaning up invalid distributions
# Usage: ./fix_tensorflow_install.sh

set -e

echo "🔧 Fixing corrupted TensorFlow installation..."

# Get the virtual environment path
VENV_PATH="${VIRTUAL_ENV:-./tf-gpu}"
SITE_PACKAGES="${VENV_PATH}/lib/python3.10/site-packages"

if [ ! -d "$SITE_PACKAGES" ]; then
    echo "❌ Error: Site-packages directory not found at $SITE_PACKAGES"
    echo "   Make sure you're in the ml directory and the virtual environment is activated"
    exit 1
fi

echo "📂 Checking site-packages directory: $SITE_PACKAGES"

# Find and remove corrupted tensorflow distributions
echo "🔍 Searching for corrupted TensorFlow distributions..."

# Look for directories/files starting with "-ensorflow" or other malformed names
CORRUPTED=$(find "$SITE_PACKAGES" -maxdepth 1 -type d -name "-*ensorflow*" -o -name "*ensorflow*" ! -name "tensorflow*" 2>/dev/null || true)

if [ -n "$CORRUPTED" ]; then
    echo "⚠️  Found corrupted distributions:"
    echo "$CORRUPTED"
    echo ""
    read -p "Remove these corrupted distributions? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "$CORRUPTED" | while read -r dir; do
            if [ -n "$dir" ]; then
                echo "🗑️  Removing: $dir"
                rm -rf "$dir"
            fi
        done
        echo "✅ Corrupted distributions removed"
    else
        echo "❌ Aborted. Please manually remove corrupted distributions."
        exit 1
    fi
else
    echo "✅ No corrupted distributions found"
fi

# Also check for corrupted .dist-info directories
echo "🔍 Checking for corrupted .dist-info directories..."
CORRUPTED_DIST_INFO=$(find "$SITE_PACKAGES" -maxdepth 1 -type d -name "-*ensorflow*.dist-info" 2>/dev/null || true)

if [ -n "$CORRUPTED_DIST_INFO" ]; then
    echo "⚠️  Found corrupted .dist-info directories:"
    echo "$CORRUPTED_DIST_INFO"
    echo ""
    read -p "Remove these corrupted .dist-info directories? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "$CORRUPTED_DIST_INFO" | while read -r dir; do
            if [ -n "$dir" ]; then
                echo "🗑️  Removing: $dir"
                rm -rf "$dir"
            fi
        done
        echo "✅ Corrupted .dist-info directories removed"
    fi
fi

# Uninstall existing tensorflow if present (clean uninstall)
echo ""
echo "🧹 Cleaning up existing TensorFlow installation..."
pip uninstall -y tensorflow tensorflow-gpu 2>/dev/null || true

# Reinstall tensorflow
echo ""
echo "📦 Reinstalling TensorFlow 2.15.0..."
pip install --no-cache-dir tensorflow==2.15.0

echo ""
echo "✅ TensorFlow installation fixed!"
echo "🧪 Verifying installation..."
python -c "import tensorflow as tf; print(f'✅ TensorFlow {tf.__version__} installed successfully')" || {
    echo "❌ Verification failed. Please check the error messages above."
    exit 1
}

echo ""
echo "🎉 Done! TensorFlow should now work correctly."

