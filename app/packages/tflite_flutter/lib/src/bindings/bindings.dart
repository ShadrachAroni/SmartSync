/*
 * Copyright 2023 The TensorFlow Authors. All Rights Reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *             http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import 'dart:ffi';
import 'dart:io';

import 'package:tflite_flutter/src/bindings/tensorflow_lite_bindings_generated.dart';

final DynamicLibrary _dylib = () {
  if (Platform.isAndroid) {
    print('🔧 [TFLite Bindings] Initializing on Android...');
    
    // Load main TFLite library first
    print('   [DEBUG] Step 1: Loading main TFLite library (libtensorflowlite_jni.so)...');
    DynamicLibrary mainLib;
    try {
      mainLib = DynamicLibrary.open('libtensorflowlite_jni.so');
      print('   [DEBUG] ✅ Main TFLite library loaded successfully');
      print('   [DEBUG]    Library handle: ${mainLib.handle.address}');
    } catch (e, stackTrace) {
      print('   [DEBUG] ❌ Failed to load main TFLite library: $e');
      print('   [DEBUG]    Stack: $stackTrace');
      rethrow;
    }
    
    // Then try to load Select TF Ops library (if available)
    // This is required for models using TensorFlow ops (e.g., FlexConv2D, CAST v5)
    // Try multiple possible library names as they vary by version
    print('   [DEBUG] Step 2: Attempting to load Select TF Ops library...');
    print('   [DEBUG]    This library is required for FlexConv2D operations');
    final flexLibNames = [
      'libtensorflowlite_flex_jni.so',      // Most common for 2.16.1
      'libtensorflowlite_select_tf_ops_jni.so',  // Alternative name
      'libtensorflowlite_flex.so',          // Sometimes without _jni suffix
    ];
    
    bool anyFlexLibLoaded = false;
    for (final libName in flexLibNames) {
      print('   [DEBUG]    Trying: $libName...');
      try {
        final flexLib = DynamicLibrary.open(libName);
        print('   [DEBUG]    ✅ Successfully loaded: $libName');
        print('   [DEBUG]       Library handle: ${flexLib.handle.address}');
        anyFlexLibLoaded = true;
        // Don't break - try to load all variants to ensure compatibility
      } catch (e) {
        print('   [DEBUG]    ❌ Failed to load $libName: $e');
        // Continue trying other names
      }
    }
    
    if (!anyFlexLibLoaded) {
      print('   [DEBUG] ⚠️  Could not explicitly load Select TF Ops library via DynamicLibrary.open');
      print('   [DEBUG]    However, the library might be auto-loaded by:');
      print('   [DEBUG]    1. Android dependency system (via build.gradle)');
      print('   [DEBUG]    2. TfliteFlutterPlugin Kotlin code (System.loadLibrary)');
      print('   [DEBUG]    Check logcat for "TfliteFlutterPlugin" messages');
      print('   [DEBUG]    Interpreter creation will fail if library is truly missing');
    } else {
      print('   [DEBUG] ✅ At least one Select TF Ops library variant loaded');
    }
    
    // Note: Even if explicit loading fails, the library might be auto-loaded
    // by the Android dependency system or by the TfliteFlutterPlugin Kotlin code
    // The interpreter creation will fail later if the library is truly missing
    
    print('   [DEBUG] ✅ Bindings initialization complete');
    return mainLib;
  }

  if (Platform.isIOS) {
    return DynamicLibrary.process();
  }

  if (Platform.isMacOS) {
    return DynamicLibrary.open(
        '${Directory(Platform.resolvedExecutable).parent.parent.path}/resources/libtensorflowlite_c-mac.dylib');
  }

  if (Platform.isLinux) {
    return DynamicLibrary.open(
        '${Directory(Platform.resolvedExecutable).parent.path}/blobs/libtensorflowlite_c-linux.so');
  }
  if (Platform.isWindows) {
    return DynamicLibrary.open(
        '${Directory(Platform.resolvedExecutable).parent.path}/blobs/libtensorflowlite_c-win.dll');
  }

  throw UnsupportedError('Unknown platform: ${Platform.operatingSystem}');
}();

final DynamicLibrary _dylibGpu = () {
  if (Platform.isAndroid) {
    return DynamicLibrary.open('libtensorflowlite_gpu_jni.so');
  }

  throw UnsupportedError('Unknown platform: ${Platform.operatingSystem}');
}();

/// TensorFlowLite Bindings
final tfliteBinding = TensorFlowLiteBindings(_dylib);

/// TensorFlowLite Gpu Bindings
final tfliteBindingGpu = TensorFlowLiteBindings(_dylibGpu);
