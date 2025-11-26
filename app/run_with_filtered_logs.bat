@echo off
REM Run Flutter app with filtered logcat (removes BLASTBufferQueue logs)
REM Usage: run_with_filtered_logs.bat

echo Starting Flutter app with filtered logs...
echo BLASTBufferQueue and other verbose system logs will be filtered out.
echo.

REM Start logcat filter in background
start /B cmd /c "adb logcat -c && adb logcat | findstr /V /C:\"BLASTBufferQueue\" /C:\"BufferQueue\" /C:\"SurfaceFlinger\" /C:\"GraphicBufferAllocator\" /C:\"EGL_emulation\" /C:\"OpenGLRenderer\" /C:\"HWUI\" /C:\"Skia\" /C:\"libEGL\" /C:\"Gralloc\" /C:\"native\" /C:\"RenderThread\""

REM Wait a moment for logcat to start
timeout /t 2 /nobreak >nul

REM Run Flutter app
flutter run

REM Cleanup: Kill logcat process (optional)
taskkill /F /IM adb.exe /FI "WINDOWTITLE eq *logcat*" 2>nul

