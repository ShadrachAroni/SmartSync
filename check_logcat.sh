#!/bin/bash
# Bash script to check logcat for Flutter app errors
# Usage: ./check_logcat.sh

echo "========================================"
echo "SmartSync App - Logcat Error Checker"
echo "========================================"
echo ""

# Check if adb is available
if ! command -v adb &> /dev/null; then
    echo "⚠️  ADB not found in PATH"
    echo "Please ensure Android SDK platform-tools is in your PATH"
    echo "Or use: flutter run -v"
    exit 1
fi

echo "📱 Checking for connected devices..."
adb devices

echo ""
echo "🔍 Filtering logcat for SmartSync errors..."
echo "Press Ctrl+C to stop"
echo ""

# Clear logcat first
adb logcat -c

# Filter for Flutter, SmartSync, and error messages
adb logcat | grep -iE "flutter|smartsync|error|exception|crash|fatal|❌|⚠️"

