#!/bin/bash
# Filter logcat to remove BLASTBufferQueue and other verbose system logs
# Usage: ./filter_logcat.sh

adb logcat -c
adb logcat | grep -v "BLASTBufferQueue" | grep -v "BufferQueue" | grep -v "SurfaceFlinger" | grep -v "GraphicBufferAllocator" | grep -v "EGL_emulation" | grep -v "OpenGLRenderer" | grep -v "HWUI" | grep -v "Skia" | grep -v "libEGL" | grep -v "Gralloc" | grep -v "native" | grep -v "RenderThread"

