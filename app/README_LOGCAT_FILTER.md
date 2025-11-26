# Logcat Filtering Guide

## Problem
BLASTBufferQueue and other verbose Android system logs spam the console, making it hard to see important app logs.

## Solutions

### Option 1: Use the Filter Scripts (Recommended)

#### Windows:
```bash
# Run app with filtered logs
run_with_filtered_logs.bat

# Or filter existing logcat output
filter_logcat.bat
```

#### Linux/Mac:
```bash
# Make script executable
chmod +x filter_logcat.sh

# Run app with filtered logs
./filter_logcat.sh
```

### Option 2: Manual ADB Command

Filter logs directly using adb:
```bash
# Clear logcat and start filtering
adb logcat -c
adb logcat | grep -v "BLASTBufferQueue" | grep -v "BufferQueue" | grep -v "SurfaceFlinger"
```

### Option 3: Use Logcat Filters in Android Studio

1. Open **Logcat** tab in Android Studio
2. Click the filter dropdown
3. Add a filter with:
   - **Filter Name**: No System Logs
   - **Log Tag**: `^(?!.*(BLASTBufferQueue|BufferQueue|SurfaceFlinger|GraphicBufferAllocator|EGL_emulation|OpenGLRenderer|HWUI|Skia|libEGL)).*$`
   - **Log Level**: Any

### Option 4: PowerShell Filter (Windows)

```powershell
adb logcat | Where-Object { $_ -notmatch "BLASTBufferQueue|BufferQueue|SurfaceFlinger" }
```

## Filtered Log Tags

The following verbose system logs are filtered:
- `BLASTBufferQueue` - SurfaceView buffer management
- `BufferQueue` - Buffer queue operations
- `SurfaceFlinger` - Surface composition
- `GraphicBufferAllocator` - Graphics buffer allocation
- `EGL_emulation` - EGL emulation logs
- `OpenGLRenderer` - OpenGL rendering
- `HWUI` - Hardware UI rendering
- `Skia` - Skia graphics library
- `libEGL` - EGL library logs
- `Gralloc` - Graphics memory allocator
- `native` - Native code logs
- `RenderThread` - Rendering thread logs

## Quick Reference

**Filter all system logs except your app:**
```bash
adb logcat | grep -v "BLASTBufferQueue\|BufferQueue\|SurfaceFlinger\|GraphicBufferAllocator\|EGL_emulation\|OpenGLRenderer\|HWUI\|Skia\|libEGL\|Gralloc\|native\|RenderThread"
```

**Show only Flutter/your app logs:**
```bash
adb logcat | grep -E "flutter|FBP|SmartSync|com.smartsync"
```

