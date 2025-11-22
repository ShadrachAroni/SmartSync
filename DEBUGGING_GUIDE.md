# SmartSync App Debugging Guide

## AndroidManifest Permissions Check ✅

All required permissions are declared in `app/android/app/src/main/AndroidManifest.xml`:

### ✅ Declared Permissions:
- **Bluetooth** (Android 12+): `BLUETOOTH_SCAN`, `BLUETOOTH_CONNECT`, `BLUETOOTH_ADVERTISE`
- **Bluetooth** (Android 11-): `BLUETOOTH`, `BLUETOOTH_ADMIN`
- **Location**: `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION`
- **Network**: `INTERNET`, `ACCESS_NETWORK_STATE`
- **Foreground Service**: `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_CONNECTED_DEVICE`, `FOREGROUND_SERVICE_DATA_SYNC`
- **Notifications**: `POST_NOTIFICATIONS` (Android 13+)
- **Other**: `WAKE_LOCK`, `VIBRATE`

## Checking Logcat for Errors

### Option 1: Using Flutter (Recommended)
```bash
flutter run -v
```
This shows verbose output including all Flutter logs and errors.

### Option 2: Using ADB Logcat (Windows PowerShell)
```powershell
# Clear logcat first
adb logcat -c

# Filter for Flutter and error messages
adb logcat | Select-String -Pattern "flutter|smartsync|error|exception|crash|fatal|❌|⚠️" -CaseSensitive:$false

# Or use the provided script
.\check_logcat.ps1
```

### Option 3: Using ADB Logcat (Linux/Mac)
```bash
# Clear logcat first
adb logcat -c

# Filter for Flutter and error messages
adb logcat | grep -iE "flutter|smartsync|error|exception|crash|fatal|❌|⚠️"

# Or use the provided script
chmod +x check_logcat.sh
./check_logcat.sh
```

### Option 4: Filter by Package Name
```bash
# Filter only SmartSync app logs
adb logcat | grep -i "com.smartsync.smartsync_app"

# Filter for errors only
adb logcat *:E | grep -i "com.smartsync.smartsync_app"
```

### Option 5: Save Logs to File
```bash
# Save all logs to file
adb logcat > app_logs.txt

# Save only errors
adb logcat *:E > app_errors.txt
```

## Common Issues to Check

### 1. App Not Starting After Installation
- Check if you see the startup logs: `🚀 ========== APP STARTUP BEGIN ==========`
- Look for which step fails (Step 1-8)
- Check for Firebase initialization errors
- Check for missing assets

### 2. Permission Errors
- Look for: `Permission denied`, `SecurityException`
- Check if runtime permissions are being requested

### 3. Firebase Errors
- Look for: `FirebaseException`, `App Check`, `Network error`
- Check Firebase configuration

### 4. Asset Loading Errors
- Look for: `Unable to load asset`, `AssetNotFoundException`
- Verify assets are listed in `pubspec.yaml`

### 5. Crash on Startup
- Look for: `FATAL EXCEPTION`, `AndroidRuntime`, `Process crashed`
- Check stack traces for the exact error

## Debug Logging Added

The app now includes comprehensive debug logging:
- **Step-by-step initialization** (8 steps)
- **Widget lifecycle** logging
- **Error handling** with full stack traces
- **Provider state** changes

All logs are prefixed with emojis for easy identification:
- 🚀 App startup
- 📱 Step progress
- ✅ Success
- ⚠️ Warnings
- ❌ Errors

## Next Steps

1. **Run the app** and check console/logcat output
2. **Look for the last log message** - this shows where initialization stopped
3. **Check for error messages** with ❌ prefix
4. **Share the logs** if you need further assistance

