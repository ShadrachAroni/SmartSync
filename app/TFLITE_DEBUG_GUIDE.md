# TFLite Debugging Guide

This document explains the comprehensive debugging added to diagnose TFLite initialization issues.

## Debug Output Locations

### 1. Flutter Console (IDE/terminal)
All `[DEBUG]` messages from:
- `TFLiteService` initialization
- Model loading
- Interpreter creation
- Tensor allocation

### 2. Android Logcat
Look for:
- `TfliteFlutterPlugin` - Plugin initialization and library loading
- `tflite` - Native TFLite error messages
- `flutter` - Flutter app logs

## Debugging Commands

### Monitor TFLite logs in real-time:
```powershell
.\monitor_tflite_logs.ps1
```

### Check what libraries are in the APK:
```powershell
.\check_apk_libs.ps1
```

### Filter logcat for TFLite issues:
```powershell
& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" logcat | Select-String -Pattern "TfliteFlutterPlugin|tflite|TFLite|FlexConv2D|CAST" -CaseSensitive:$false
```

## What to Look For

### Successful Initialization:
1. **Bindings:**
   - `✅ Main TFLite library loaded successfully`
   - `✅ At least one Select TF Ops library variant loaded`

2. **Plugin (logcat):**
   - `TfliteFlutterPlugin: ✅✅✅ SUCCESS: Loaded Select TF Ops library`

3. **Service:**
   - `✅ Interpreter created successfully`
   - `✅ Tensors allocated successfully`
   - `✅ LOCAL TFLite model loaded successfully`

### Common Failure Points:

#### 1. Library Not Loaded
**Symptoms:**
- `❌ Could not explicitly load Select TF Ops library`
- `TfliteFlutterPlugin: ❌❌❌ CRITICAL: Could not load Select TF Ops library!`

**Fix:**
- Rebuild app: `flutter clean && flutter build apk --debug`
- Verify library in APK: `.\check_apk_libs.ps1`
- Check `build.gradle` has `tensorflow-lite-select-tf-ops:2.15.0`

#### 2. Interpreter Creation Fails
**Symptoms:**
- `❌ Failed to create TFLite interpreter`
- `Node number X (FlexConv2D) failed to prepare`

**Debug Info:**
- Check which creation method was attempted
- Check if Select TF Ops library was loaded
- Look for native TFLite errors in logcat

#### 3. Tensor Allocation Fails
**Symptoms:**
- `❌ Failed to allocate tensors`
- `Tensor allocation failed with status: X`

**Debug Info:**
- Status code indicates the specific error
- Check if model file is valid
- Verify Select TF Ops library is loaded

## Debug Output Format

All debug messages follow this format:
```
[DEBUG] Category: Message
   [DEBUG]    Details...
   [DEBUG]    More details...
```

Categories:
- `TFLite Service` - Service-level operations
- `TFLite Interpreter` - Interpreter creation
- `TFLite Bindings` - Library loading
- `Step X.Y` - Specific initialization steps

## Troubleshooting Steps

1. **Check logcat for plugin initialization:**
   - Look for `TfliteFlutterPlugin` messages
   - Verify library loading success

2. **Check Flutter console:**
   - Look for `[DEBUG]` messages
   - Note which step fails

3. **Verify APK contents:**
   - Run `.\check_apk_libs.ps1`
   - Ensure `libtensorflowlite_flex_jni.so` is present

4. **Check build configuration:**
   - Verify `build.gradle` dependencies
   - Ensure version matches (2.15.0)

5. **Rebuild if needed:**
   ```powershell
   flutter clean
   flutter build apk --debug
   ```

## Error Messages Reference

### `Node number X (FlexConv2D) failed to prepare`
- **Cause:** Select TF Ops library not loaded
- **Fix:** Rebuild app, verify library in APK

### `Bad state: failed precondition`
- **Cause:** Tensor allocation failed
- **Debug:** Check allocation status code in logs

### `Unable to create interpreter`
- **Cause:** Model incompatible or library missing
- **Debug:** Check which creation method was attempted

## Next Steps After Debugging

Once you identify the issue:
1. Note the exact error message and step
2. Check the corresponding section above
3. Apply the recommended fix
4. Rebuild and test again

