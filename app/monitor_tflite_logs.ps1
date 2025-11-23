# Real-time TFLite log monitoring script
# Run this script, then launch your app to see TFLite-related logs

$adbPath = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"

if (-not (Test-Path $adbPath)) {
    Write-Host "ERROR: adb not found at $adbPath" -ForegroundColor Red
    exit 1
}

Write-Host "Monitoring TFLite logs in real-time..." -ForegroundColor Cyan
Write-Host "Launch your app now to see the logs." -ForegroundColor Yellow
Write-Host "Press Ctrl+C to stop monitoring." -ForegroundColor Yellow
Write-Host ""

& $adbPath logcat -c  # Clear logcat first
& $adbPath logcat | Select-String -Pattern "TfliteFlutterPlugin|tensorflow|TFLite|Select.*TF|FlexConv2D|CAST|ML.*Service|schedule.*predictor" -CaseSensitive:$false

