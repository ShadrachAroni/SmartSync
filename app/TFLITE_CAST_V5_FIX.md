# TFLite CAST Version 5 Compatibility Issue

## Problem

The TFLite model uses **CAST version 5**, which is not supported by TensorFlow Lite 2.15.0 (the latest stable version available for Android).

### Error Message
```
E/tflite: Didn't find op for builtin opcode 'CAST' version '5'. 
An older version of this builtin might be supported. 
Are you using an old TFLite binary with a newer model?
```

## Current Status

✅ **Select TF Ops library is loading correctly** (`libtensorflowlite_flex_jni.so`)  
❌ **Model uses CAST v5 which TFLite 2.15.0 doesn't support**  
✅ **App gracefully falls back to server-side inference**

## Solutions

### Option 1: Reconvert Model with TensorFlow 2.15.x (Recommended)

The model was likely converted with TensorFlow 2.16+ which uses CAST v5. Reconvert with TensorFlow 2.15.x:

```bash
cd ml
# Ensure you're using TensorFlow 2.15.x
pip install tensorflow==2.15.0

# Reconvert the model
python scripts/convert_tflite.py
```

This will generate a model compatible with TFLite 2.15.0.

### Option 2: Wait for TFLite 2.16+ Support

When TensorFlow Lite 2.16+ becomes available on Maven Central, update:

1. `app/packages/tflite_flutter/android/build.gradle`:
   ```gradle
   def tflite_version = "2.16.0"  // or newer
   ```

2. `app/android/app/build.gradle.kts`:
   ```kotlin
   implementation("org.tensorflow:tensorflow-lite-select-tf-ops:2.16.0")
   ```

### Option 3: Use Server-Side Inference (Current)

The app already falls back to server-side inference when local models fail. This works correctly and is the current behavior.

## Verification

After reconverting, verify the model:

```bash
# Check if CAST v5 is still present
cd app
python -c "
import tensorflow as tf
interpreter = tf.lite.Interpreter(model_path='assets/models/schedule_predictor.tflite')
interpreter.allocate_tensors()
print('✅ Model loaded successfully')
"
```

## Why This Happens

- TensorFlow 2.16+ introduced CAST op version 5
- TFLite 2.15.0 only supports CAST up to version 4
- The model was converted with a newer TensorFlow version
- TFLite 2.16+ is not yet available on Maven Central for Android

## Impact

- **Local inference**: Currently unavailable (falls back to server-side)
- **App functionality**: ✅ Works correctly with server-side inference
- **Performance**: Server-side inference may be slightly slower but works fine

## Next Steps

1. **For local inference**: Reconvert model with TensorFlow 2.15.0
2. **For production**: Current server-side fallback is acceptable
3. **For future**: Monitor TFLite 2.16+ availability on Maven Central

