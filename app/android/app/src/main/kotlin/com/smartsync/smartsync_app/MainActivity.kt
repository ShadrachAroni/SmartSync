package com.smartsync.smartsync_app

import android.os.Build
import android.util.Log
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        
        // Suppress BLASTBufferQueue verbose logging
        suppressBLASTBufferQueueLogging()
    }
    
    private fun suppressBLASTBufferQueueLogging() {
        try {
            // Method 1: Try to set log level using SystemProperties (requires reflection)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                val systemPropertiesClass = Class.forName("android.os.SystemProperties")
                val setMethod = systemPropertiesClass.getMethod(
                    "set",
                    String::class.java,
                    String::class.java
                )
                // Set BLASTBufferQueue log level to ASSERT (only shows critical errors)
                setMethod.invoke(null, "log.tag.BLASTBufferQueue", "ASSERT")
            }
        } catch (e: Exception) {
            // If SystemProperties.set() fails (requires system permissions), try alternative
            try {
                // Method 2: Try using Log.setTagLevel() if available (Android 11+)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    val logClass = Log::class.java
                    val setTagLevelMethod = logClass.getMethod(
                        "setTagLevel",
                        String::class.java,
                        Int::class.java
                    )
                    // Log.ASSERT = 7, which suppresses all logs except ASSERT level
                    setTagLevelMethod.invoke(null, "BLASTBufferQueue", 7)
                }
            } catch (e2: Exception) {
                // If both methods fail, the logging will continue but won't affect app functionality
                // This is expected on non-rooted devices without system permissions
            }
        }
    }
}
