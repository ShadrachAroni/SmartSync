@echo off
REM Filter logcat to remove BLASTBufferQueue and other verbose system logs
REM Usage: filter_logcat.bat

adb logcat -c
adb logcat | findstr /V /C:"BLASTBufferQueue" /C:"BufferQueue" /C:"SurfaceFlinger" /C:"GraphicBufferAllocator" /C:"EGL_emulation" /C:"OpenGLRenderer" /C:"HWUI" /C:"Skia" /C:"libEGL" /C:"Gralloc" /C:"native" /C:"RenderThread"

