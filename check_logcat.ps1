# PowerShell script to check logcat for Flutter app errors
# Usage: .\check_logcat.ps1

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "SmartSync App - Logcat Error Checker" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Check if adb is available
$adbPath = Get-Command adb -ErrorAction SilentlyContinue
if (-not $adbPath) {
    Write-Host "⚠️  ADB not found in PATH" -ForegroundColor Yellow
    Write-Host "Please ensure Android SDK platform-tools is in your PATH" -ForegroundColor Yellow
    Write-Host "Or use: flutter run -v" -ForegroundColor Yellow
    exit 1
}

Write-Host "📱 Checking for connected devices..." -ForegroundColor Green
$devices = adb devices
Write-Host $devices

Write-Host ""
Write-Host "🔍 Filtering logcat for SmartSync errors..." -ForegroundColor Green
Write-Host "Press Ctrl+C to stop" -ForegroundColor Yellow
Write-Host ""

# Filter for Flutter, SmartSync, and error messages
# Exclude BLASTBufferQueue verbose logs (known Android system log, not an error)
adb logcat -s Flutter:V flutter:V AndroidRuntime:E *:S | Select-String -Pattern "flutter|smartsync|error|exception|crash|fatal" -CaseSensitive:$false | Where-Object { $_ -notmatch "BLASTBufferQueue" }

