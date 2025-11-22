# tflite_flutter - Local Fixed Version

This is a local copy of `tflite_flutter` version 0.10.4 with a Dart 3.0 compatibility fix.

## Fix Applied

**Issue:** The package uses `UnmodifiableUint8ListView` which was deprecated in Dart 3.0.

**Solution:** Replaced `UnmodifiableUint8ListView` with `Uint8List.fromList` in `lib/src/tensor.dart` (line 58).

## Usage

This package is automatically used via `dependency_overrides` in the main `pubspec.yaml`:

```yaml
dependency_overrides:
  tflite_flutter:
    path: packages/tflite_flutter
```

## Maintenance

- This local package will persist even after `flutter pub cache clean`
- If the official package releases a fix, you can remove this override and use the official version
- To update: Copy the latest version from pub cache and reapply the fix

## Original Package

- **Package:** [tflite_flutter](https://pub.dev/packages/tflite_flutter)
- **Version:** 0.10.4
- **GitHub:** [tensorflow/flutter-tflite](https://github.com/tensorflow/flutter-tflite)

