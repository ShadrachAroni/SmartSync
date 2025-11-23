# How to Check TFLite Select TF Ops Library Loading

## Method 1: Using Android Studio Logcat (Recommended)

1. Open Android Studio
2. Connect your device or start an emulator
3. Run the app on the device/emulator
4. Open the **Logcat** tab at the bottom of Android Studio
5. In the Logcat filter box, enter: `TfliteFlutterPlugin|tensorflow|TFLite|Select`
6. Look for messages containing:
   - `TfliteFlutterPlugin` - Our plugin initialization messages
   - `Successfully loaded tensorflowlite_flex_jni` - Library loaded successfully
   - `Successfully loaded tensorflowlite_select_tf_ops_jni` - Alternative library name
   - `Could not explicitly load Select TF Ops library` - Warning (may still work if auto-loaded)
   - `Select TensorFlow op(s)` - Errors related to Select TF Ops

## Method 2: Using ADB Command Line

### Find ADB Location
ADB is typically located at:
- `%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe`
- `%USERPROFILE%\AppData\Local\Android\Sdk\platform-tools\adb.exe`

### Check Logs
1. Open PowerShell or Command Prompt
2. Navigate to the platform-tools directory or add it to your PATH
3. Run one of these commands:

**PowerShell:**
```powershell
adb logcat -d | Select-String -Pattern "TfliteFlutterPlugin|tensorflow|TFLite|Select" -CaseSensitive:$false
```

**Command Prompt:**
```cmd
adb logcat -d | findstr /i "TfliteFlutterPlugin tensorflow TFLite Select"
```

**Live monitoring:**
```powershell
adb logcat | Select-String -Pattern "TfliteFlutterPlugin|tensorflow|TFLite|Select" -CaseSensitive:$false
```

## What to Look For

### Success Indicators:
- ✅ `Successfully loaded tensorflowlite_flex_jni` or `tensorflowlite_select_tf_ops_jni`
- ✅ No errors about "Select TensorFlow op(s) not supported"
- ✅ TFLite model loads without errors

### Warning Messages (may still work):
- ⚠️ `Could not explicitly load Select TF Ops library, relying on automatic loading`
  - This is OK if the library is auto-loaded by Android dependency system

### Error Indicators:
- ❌ `Select TensorFlow op(s), included in the given model, is(are) not supported`
- ❌ `FlexConv2D failed to prepare`
- ❌ `CAST version 5 not supported`

## Expected Log Sequence

When the app starts and initializes ML Service, you should see:

1. `TfliteFlutterPlugin: Successfully loaded tensorflowlite_flex_jni` (or similar)
2. `INFO: Initializing TFLite Service...`
3. `INFO: 📥 Loading LOCAL TFLite model from assets...`
4. `SUCCESS: ✅ LOCAL TFLite model loaded successfully`

If you see errors instead, the Select TF Ops library may not be properly loaded or linked.

