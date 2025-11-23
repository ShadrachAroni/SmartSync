package org.tensorflow.tflite_flutter

import androidx.annotation.NonNull

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/** TfliteFlutterPlugin */
class TfliteFlutterPlugin: FlutterPlugin, MethodCallHandler {
  /// The MethodChannel that will the communication between Flutter and native Android
  ///
  /// This local reference serves to register the plugin with the Flutter Engine and unregister it
  /// when the Flutter Engine is detached from the Activity
  private lateinit var channel : MethodChannel

  companion object {
    init {
      // Load Select TF Ops library in static initializer - runs when class is first loaded
      // This ensures the library is loaded BEFORE any interpreter creation
      loadSelectTFOpsLibraryStatic()
    }
    
    private fun loadSelectTFOpsLibraryStatic() {
      android.util.Log.i("TfliteFlutterPlugin", "=== Attempting to load Select TF Ops library (static) ===")
      
      // The library name for tensorflow-lite-select-tf-ops:2.15.0
      // Try multiple possible names as they vary by version
      val libraryNames = listOf(
        "tensorflowlite_flex_jni",           // Most common name for 2.15.0
        "tensorflowlite_select_tf_ops_jni",  // Alternative name
        "tensorflowlite_flex"                 // Sometimes without _jni suffix
      )
      
      var loaded = false
      for (libName in libraryNames) {
        try {
          System.loadLibrary(libName)
          android.util.Log.i("TfliteFlutterPlugin", "✅✅✅ SUCCESS: Loaded Select TF Ops library: $libName")
          loaded = true
          break
        } catch (e: UnsatisfiedLinkError) {
          android.util.Log.d("TfliteFlutterPlugin", "❌ Failed to load $libName: ${e.message}")
          // Try next library name
        } catch (e: Exception) {
          android.util.Log.w("TfliteFlutterPlugin", "⚠️ Error loading $libName: ${e.message}")
        }
      }
      
      if (!loaded) {
        android.util.Log.e("TfliteFlutterPlugin", "❌❌❌ CRITICAL: Could not load Select TF Ops library!")
        android.util.Log.e("TfliteFlutterPlugin", "   This will cause models with FlexConv2D/CAST v5 to fail!")
        android.util.Log.e("TfliteFlutterPlugin", "   Ensure 'org.tensorflow:tensorflow-lite-select-tf-ops:2.15.0' is in build.gradle")
      }
    }
  }

  override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    // Library should already be loaded by static initializer, but try again if needed
    android.util.Log.i("TfliteFlutterPlugin", "onAttachedToEngine called")
    
    channel = MethodChannel(flutterPluginBinding.binaryMessenger, "tflite_flutter")
    channel.setMethodCallHandler(this)
  }

  override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
    if (call.method == "getPlatformVersion") {
      result.success("Android ${android.os.Build.VERSION.RELEASE}")
    } else {
      result.notImplemented()
    }
  }

  override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
  }
}
