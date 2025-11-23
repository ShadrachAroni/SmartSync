# PowerShell script to check TFLite and TfliteFlutterPlugin logs
# This script filters logcat output for TFLite-related messages

Write-Host "Checking for TFLite and TfliteFlutterPlugin log messages..." -ForegroundColor Cyan
Write-Host ""

# Try to find adb in common locations
$adbPath = $null
$possiblePaths = @(
    "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe",
    "$env:USERPROFILE\AppData\Local\Android\Sdk\platform-tools\adb.exe",
    "$env:ANDROID_HOME\platform-tools\adb.exe",
    "C:\Users\$env:USERNAME\AppData\Local\Android\Sdk\platform-tools\adb.exe"
)

foreach ($path in $possiblePaths) {
    if (Test-Path $path) {
        $adbPath = $path
        break
    }
}

if ($null -eq $adbPath) {
    Write-Host "ERROR: adb not found. Please ensure Android SDK platform-tools is in your PATH." -ForegroundColor Red
    Write-Host ""
    Write-Host "Alternative: Run the app and use Android Studio's Logcat viewer, or run:" -ForegroundColor Yellow
    Write-Host "  adb logcat | findstr /i 'TfliteFlutterPlugin tensorflow TFLite Select'" -ForegroundColor Yellow
    exit 1
}

Write-Host "Using adb at: $adbPath" -ForegroundColor Green
Write-Host ""

# Clear logcat buffer and get recent logs
Write-Host "Fetching recent logcat entries..." -ForegroundColor Cyan
Write-Host ""

# Get logs with filters for TFLite-related messages
& $adbPath logcat -d | Select-String -Pattern "TfliteFlutterPlugin|tensorflow|TFLite|Select.*TF.*Ops|FlexConv2D|CAST" -CaseSensitive:$false | Select-Object -Last 50

Write-Host ""
Write-Host "To see live logs, run:" -ForegroundColor Yellow
Write-Host "  & '$adbPath' logcat | Select-String -Pattern 'TfliteFlutterPlugin|tensorflow|TFLite' -CaseSensitive:`$false" -ForegroundColor Yellow

