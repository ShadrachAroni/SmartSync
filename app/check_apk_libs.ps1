# Script to check what native libraries are in the APK
# This helps verify if the Select TF Ops library is packaged

$apkPath = "build\app\outputs\flutter-apk\app-debug.apk"

if (-not (Test-Path $apkPath)) {
    Write-Host "APK not found at: $apkPath" -ForegroundColor Red
    Write-Host "Please build the app first: flutter build apk --debug" -ForegroundColor Yellow
    exit 1
}

Write-Host "Checking native libraries in APK..." -ForegroundColor Cyan
Write-Host "APK: $apkPath" -ForegroundColor Green
Write-Host ""

# Use aapt (Android Asset Packaging Tool) to list libraries
$aaptPath = "$env:LOCALAPPDATA\Android\Sdk\build-tools\*\aapt.exe"
$aapt = Get-Item $aaptPath -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1

if ($null -eq $aapt) {
    Write-Host "aapt not found. Trying alternative method..." -ForegroundColor Yellow
    
    # Alternative: Use unzip if available
    if (Get-Command unzip -ErrorAction SilentlyContinue) {
        Write-Host "Using unzip to extract library list..." -ForegroundColor Yellow
        unzip -l $apkPath | Select-String "lib/.*\.so" | ForEach-Object {
            $line = $_.Line.Trim()
            if ($line -match "lib/([^/]+)/([^/]+\.so)") {
                $arch = $matches[1]
                $lib = $matches[2]
                Write-Host "  $arch/$lib" -ForegroundColor Green
            }
        }
    } else {
        Write-Host "Neither aapt nor unzip found. Cannot check libraries." -ForegroundColor Red
        Write-Host "Install unzip or ensure Android SDK build-tools are installed." -ForegroundColor Yellow
    }
} else {
    Write-Host "Using aapt: $($aapt.FullName)" -ForegroundColor Green
    Write-Host ""
    
    # List native libraries
    & $aapt.FullName list $apkPath | Select-String "lib/.*\.so" | ForEach-Object {
        Write-Host "  $_" -ForegroundColor Green
    }
}

Write-Host ""
Write-Host "Looking for TensorFlow Lite libraries..." -ForegroundColor Cyan
Write-Host "Expected libraries:" -ForegroundColor Yellow
Write-Host "  - libtensorflowlite_jni.so (main TFLite library)" -ForegroundColor White
Write-Host "  - libtensorflowlite_flex_jni.so (Select TF Ops library)" -ForegroundColor White
Write-Host "  - libtensorflowlite_gpu_jni.so (GPU delegate, optional)" -ForegroundColor White

