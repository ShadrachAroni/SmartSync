import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import '../core/utils/logger.dart';
import '../models/sensor_data.dart';
import '../models/ml_prediction.dart';

/// Cached prediction for TFLite service
class _CachedPrediction {
  final List<SchedulePrediction> predictions;
  final DateTime timestamp;
  
  _CachedPrediction(this.predictions, this.timestamp);
  
  bool get isExpired => DateTime.now().difference(timestamp) > const Duration(minutes: 30);
}

/// TFLite Service for local ML inference
///
/// Handles loading and running TFLite models locally on device
class TFLiteService {
  static final TFLiteService _instance = TFLiteService._internal();
  factory TFLiteService() => _instance;
  TFLiteService._internal();

  Interpreter? _schedulePredictor;
  bool _isInitialized = false;
  
  // Scaler parameters from training
  List<double>? _scalerMean;
  List<double>? _scalerStd;
  
  // Prediction cache
  final Map<String, _CachedPrediction> _predictionCache = {};

  /// Initialize TFLite service and load models
  Future<bool> initialize() async {
    if (_isInitialized) {
      Logger.debug('TFLite Service already initialized');
      return _schedulePredictor != null;
    }

    try {
      Logger.info('🔧 ========== TFLite Service Initialization ==========');
      Logger.info('   Platform: ${Platform.operatingSystem}');
      Logger.info('   Timestamp: ${DateTime.now().toIso8601String()}');
      
      // Check platform support
      if (!Platform.isAndroid) {
        Logger.warning('⚠️  TFLite is primarily tested on Android. Current platform: ${Platform.operatingSystem}');
      }

      // Load schedule predictor model
      Logger.info('   Step 1: Loading schedule predictor model...');
      await _loadSchedulePredictor();
      
      // Load scaler parameters (non-critical, can fail gracefully)
      Logger.info('   Step 2: Loading scaler parameters...');
      try {
        await _loadScalerParameters();
      } catch (e, stackTrace) {
        Logger.warning('   ⚠️  Scaler parameters loading failed, using defaults: $e');
        Logger.debug('   Stack: $stackTrace');
        // Continue without scaler - will use default normalization
      }

      _isInitialized = true;
      Logger.success('✅ ========== TFLite Service Initialization Complete ==========');
      Logger.info('   Status: Ready for local inference');
      return true;
    } catch (e, stackTrace) {
      Logger.error('❌ ========== TFLite Service Initialization Failed ==========');
      Logger.error('   Error: $e');
      Logger.error('   Error Type: ${e.runtimeType}');
      Logger.error('   Stack Trace:');
      Logger.error('   $stackTrace');
      Logger.error('   ============================================================');
      // Mark as initialized to prevent infinite retries
      // Service will fall back to server-side inference
      _isInitialized = true;
      return false;
    }
  }

  /// Load schedule predictor model from assets
  /// 
  /// This loads the TFLite model converted from train_smart_home.py
  /// Model location: app/assets/models/schedule_predictor.tflite
  Future<void> _loadSchedulePredictor() async {
    try {
      Logger.info('📥 [DEBUG] Loading LOCAL TFLite model from assets...');
      Logger.info('   [DEBUG] Source: assets/models/schedule_predictor.tflite');
      Logger.info('   [DEBUG] Origin: Converted from train_smart_home.py via convert_tflite.py');

      // Step 1: Load model bytes
      Logger.info('   [DEBUG] Step 1.1: Loading model file from assets...');
      Uint8List modelBuffer;
      try {
        final modelBytes = await rootBundle.load('assets/models/schedule_predictor.tflite');
        modelBuffer = modelBytes.buffer.asUint8List();
        Logger.info('   [DEBUG] ✅ Model file loaded: ${(modelBuffer.length / 1024).toStringAsFixed(2)} KB');
        Logger.info('   [DEBUG]    Buffer length: ${modelBuffer.length} bytes');
        Logger.info('   [DEBUG]    First 16 bytes (hex): ${modelBuffer.take(16).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
      } catch (e, stackTrace) {
        Logger.error('   [DEBUG] ❌ Failed to load model file: $e');
        Logger.error('   [DEBUG]    Stack: $stackTrace');
        Logger.error('   [DEBUG]    Make sure schedule_predictor.tflite exists in app/assets/models/');
        Logger.error('   [DEBUG]    Check pubspec.yaml has the asset listed');
        rethrow;
      }

      // Step 2: Wait for Select TF Ops library
      Logger.info('   [DEBUG] Step 1.2: Waiting for Select TF Ops library to initialize...');
      Logger.info('   [DEBUG]    The TfliteFlutterPlugin should load the library in a static initializer');
      Logger.info('   [DEBUG]    Check logcat for "TfliteFlutterPlugin" messages');
      await Future.delayed(const Duration(milliseconds: 500));
      Logger.info('   [DEBUG]    Wait complete (500ms)');

      // Step 3: Create interpreter
      Logger.info('   [DEBUG] Step 1.3: Creating TFLite interpreter...');
      Logger.info('   [DEBUG]    This model uses FlexConv2D which requires Select TF Ops library');
      Logger.info('   [DEBUG]    Attempting Interpreter.fromBuffer()...');
      
      try {
        final stopwatch = Stopwatch()..start();
        _schedulePredictor = Interpreter.fromBuffer(modelBuffer);
        stopwatch.stop();
        Logger.info('   [DEBUG] ✅ Interpreter created successfully in ${stopwatch.elapsedMilliseconds}ms');
        Logger.info('   [DEBUG]    Interpreter instance: ${_schedulePredictor.hashCode}');
      } catch (e, stackTrace) {
        Logger.error('   [DEBUG] ❌ Failed to create TFLite interpreter');
        Logger.error('   [DEBUG]    Error: $e');
        Logger.error('   [DEBUG]    Error Type: ${e.runtimeType}');
        Logger.error('   [DEBUG]    Stack Trace:');
        Logger.error('   [DEBUG]    $stackTrace');
        Logger.error('   [DEBUG]    ============================================');
        Logger.error('   [DEBUG]    DIAGNOSTIC INFORMATION:');
        Logger.error('   [DEBUG]    1. This model uses FlexConv2D which requires Select TF Ops');
        Logger.error('   [DEBUG]    2. Ensure org.tensorflow:tensorflow-lite-select-tf-ops:2.16.1 is in build.gradle');
        Logger.error('   [DEBUG]    3. Check logcat for "TfliteFlutterPlugin" messages');
        Logger.error('   [DEBUG]    4. Look for "SUCCESS: Loaded Select TF Ops library" in logcat');
        Logger.error('   [DEBUG]    5. If library failed to load, rebuild app: flutter clean && flutter build apk');
        Logger.error('   [DEBUG]    6. Verify library in APK: .\\check_apk_libs.ps1');
        Logger.error('   [DEBUG]    ============================================');
        throw Exception('TFLite interpreter creation failed: $e');
      }

      // Step 4: Get tensor details
      Logger.info('   [DEBUG] Step 1.4: Getting model tensor details...');
      try {
        final inputDetails = _schedulePredictor!.getInputTensors();
        final outputDetails = _schedulePredictor!.getOutputTensors();

        Logger.success('✅ LOCAL TFLite model loaded successfully');
        Logger.info('   [DEBUG] Input Tensors: ${inputDetails.length}');
        for (int i = 0; i < inputDetails.length; i++) {
          final tensor = inputDetails[i];
          Logger.info('   [DEBUG]    Input[$i]: shape=${tensor.shape}, type=${tensor.type}, name=${tensor.name}');
        }
        Logger.info('   [DEBUG] Output Tensors: ${outputDetails.length}');
        for (int i = 0; i < outputDetails.length; i++) {
          final tensor = outputDetails[i];
          Logger.info('   [DEBUG]    Output[$i]: shape=${tensor.shape}, type=${tensor.type}, name=${tensor.name}');
        }
        Logger.info('   🎯 Model ready for local inference (no server required)');
      } catch (e, stackTrace) {
        Logger.warning('   [DEBUG] ⚠️ Could not get model tensor details: $e');
        Logger.warning('   [DEBUG]    Stack: $stackTrace');
        // Don't throw - model is loaded, just missing metadata
        Logger.success('✅ LOCAL TFLite model loaded (metadata unavailable)');
      }
    } catch (e, stackTrace) {
      Logger.error('❌ Failed to load LOCAL TFLite model: $e');
      Logger.error('   Error Type: ${e.runtimeType}');
      Logger.error('   Full Stack Trace:');
      Logger.error('   $stackTrace');
      Logger.error('   Make sure schedule_predictor.tflite exists in app/assets/models/');
      // Rethrow to let initialize() handle it gracefully
      rethrow;
    }
  }
  
  /// Load scaler parameters (mean/std) from training
  Future<void> _loadScalerParameters() async {
    try {
      Logger.info('📥 Loading scaler parameters...');
      
      // Try to load from scaler_params.json
      try {
        final scalerString = await rootBundle.loadString('assets/models/scaler_params.json');
        final scalerData = jsonDecode(scalerString) as Map<String, dynamic>;
        
        _scalerMean = (scalerData['mean'] as List?)?.map((e) => (e as num).toDouble()).toList();
        _scalerStd = (scalerData['std'] as List?)?.map((e) => (e as num).toDouble()).toList();
        // Note: feature_columns from scaler_params.json is loaded but not currently used
        
        if (_scalerMean != null && _scalerStd != null) {
          Logger.success('✅ Loaded scaler parameters from training data');
          Logger.info('   Mean/std for ${_scalerMean!.length} features');
        } else {
          Logger.warning('⚠️  Scaler parameters missing mean/std, using defaults');
        }
      } catch (e) {
        // scaler_params.json is optional - use defaults if not found
        Logger.info('ℹ️  scaler_params.json not found, using default normalization parameters');
      }
    } catch (e) {
      Logger.warning('⚠️  Failed to load scaler parameters: $e');
    }
  }

  /// Check if models are loaded and ready
  bool get isReady => _isInitialized && _schedulePredictor != null;

  /// Predict schedules using local TFLite model
  ///
  /// Input: 24 hours of sensor data (8 features per hour)
  /// Output: Fan speed and ambient light predictions
  Future<List<SchedulePrediction>> predictSchedulesLocal(
    String userId,
    String deviceId,
    List<SensorData> sensorLogs,
  ) async {
    if (!isReady) {
      throw StateError('TFLite service not initialized');
    }

    try {
      // Check cache first
      final cacheKey = _generateCacheKey(userId, deviceId, sensorLogs);
      final cached = _predictionCache[cacheKey];
      if (cached != null && !cached.isExpired) {
        Logger.info('📦 Using cached predictions (${DateTime.now().difference(cached.timestamp).inMinutes} min old)');
        return cached.predictions;
      }
      
      Logger.info('Running local TFLite inference...');

      // Preprocess sensor data to model input format
      final inputTensor = _preprocessInput(sensorLogs);

      // Verify input shape
      final inputShape = _schedulePredictor!.getInputTensors()[0].shape;
      Logger.info('Model input shape: $inputShape');
      Logger.info('Preprocessed input shape: [${inputTensor.length}, ${inputTensor[0].length}, ${inputTensor[0][0].length}]');

      // Prepare output buffer
      final outputShape = _schedulePredictor!.getOutputTensors()[0].shape;
      final outputBuffer = List<List<double>>.filled(
        outputShape[0],
        List<double>.filled(outputShape[1], 0.0),
      );

      // Run inference
      _schedulePredictor!.run(inputTensor, outputBuffer);

      Logger.success('Local inference completed');
      Logger.info('  Output shape: ${outputBuffer.length}x${outputBuffer[0].length}');
      Logger.info('  Values: ${outputBuffer[0]}');

      // Post-process predictions into schedule suggestions
      final predictions = _postprocessPredictions(
        userId,
        deviceId,
        outputBuffer[0],
        sensorLogs,
      );
      
      // Cache predictions
      _predictionCache[cacheKey] = _CachedPrediction(predictions, DateTime.now());
      
      // Clean expired cache entries
      _predictionCache.removeWhere((key, value) => value.isExpired);
      if (_predictionCache.length > 10) {
        // Keep only 10 most recent entries
        final sorted = _predictionCache.entries.toList()
          ..sort((a, b) => b.value.timestamp.compareTo(a.value.timestamp));
        _predictionCache.clear();
        for (var entry in sorted.take(10)) {
          _predictionCache[entry.key] = entry.value;
        }
      }

      return predictions;
    } catch (e) {
      Logger.error('Local TFLite inference failed: $e');
      rethrow;
    }
  }

  /// Preprocess sensor logs into model input format
  ///
  /// Model expects: [1, 24, 8]
  /// Features: temperature_mean, temperature_max, temperature_min,
  ///           humidity_mean, motionDetected_sum, hour_sin, hour_cos, is_weekend
  List<List<List<double>>> _preprocessInput(List<SensorData> logs) {
    // Need at least 24 hours of data
    if (logs.length < 24) {
      throw ArgumentError('Need at least 24 hours of sensor data');
    }

    // Take last 24 hours
    final recentLogs = logs.length > 24 ? logs.sublist(logs.length - 24) : logs;

    // Group by hour and aggregate
    final hourlyData = <DateTime, List<SensorData>>{};
    for (var log in recentLogs) {
      final hour = DateTime(
        log.timestamp.year,
        log.timestamp.month,
        log.timestamp.day,
        log.timestamp.hour,
      );
      hourlyData.putIfAbsent(hour, () => []).add(log);
    }

    // Create 24-hour sequence
    final sequence = <List<double>>[];
    final sortedHours = hourlyData.keys.toList()..sort();
    
    // Use last 24 hours
    final hoursToUse = sortedHours.length > 24
        ? sortedHours.sublist(sortedHours.length - 24)
        : sortedHours;

    for (var hour in hoursToUse) {
      final hourLogs = hourlyData[hour]!;
      
      // Aggregate features for this hour
      final tempValues = hourLogs.map((l) => l.temperature).toList();
      final tempMean = tempValues.reduce((a, b) => a + b) / tempValues.length;
      final tempMax = tempValues.reduce((a, b) => a > b ? a : b);
      final tempMin = tempValues.reduce((a, b) => a < b ? a : b);
      
      final humidityMean = hourLogs.map((l) => l.humidity).reduce((a, b) => a + b) / hourLogs.length;
      final motionSum = hourLogs.where((l) => l.motionDetected).length;
      
      // Temporal features
      final hourOfDay = hour.hour;
      final hourSin = _sinEncode(hourOfDay, 24);
      final hourCos = _cosEncode(hourOfDay, 24);
      final isWeekend = hour.weekday >= 6 ? 1.0 : 0.0;

      // Normalize features using z-score normalization
      // Use actual scaler parameters from training if available, otherwise use defaults
      final features = [
        _zScoreNormalize(
          tempMean, 
          _scalerMean?[0] ?? 22.0, 
          _scalerStd?[0] ?? 5.0
        ),      // temperature_mean
        _zScoreNormalize(
          tempMax, 
          _scalerMean?[1] ?? 25.0, 
          _scalerStd?[1] ?? 5.0
        ),       // temperature_max
        _zScoreNormalize(
          tempMin, 
          _scalerMean?[2] ?? 20.0, 
          _scalerStd?[2] ?? 5.0
        ),      // temperature_min
        _zScoreNormalize(
          humidityMean, 
          _scalerMean?[3] ?? 50.0, 
          _scalerStd?[3] ?? 15.0
        ),  // humidity_mean
        _zScoreNormalize(
          motionSum.toDouble(), 
          _scalerMean?[4] ?? 10.0, 
          _scalerStd?[4] ?? 10.0
        ), // motionDetected_sum
        hourSin,                                     // hour_sin (already normalized -1 to 1)
        hourCos,                                    // hour_cos (already normalized -1 to 1)
        isWeekend,                                  // is_weekend (binary 0 or 1)
      ];

      sequence.add(features);
    }

    // Pad or truncate to exactly 24 hours
    while (sequence.length < 24) {
      // Pad with last hour's data
      sequence.insert(0, sequence.isNotEmpty ? sequence.first : List.filled(8, 0.0));
    }
    if (sequence.length > 24) {
      sequence.removeRange(0, sequence.length - 24);
    }

    // Return as [1, 24, 8] batch
    return [sequence];
  }

  /// Normalize value using z-score normalization (StandardScaler)
  /// Formula: (value - mean) / std
  double _zScoreNormalize(double value, double mean, double std) {
    if (std == 0.0) return 0.0;
    return (value - mean) / std;
  }

  /// Sin encoding for cyclical features
  double _sinEncode(int value, int period) {
    return sin(2 * 3.141592653589793 * value / period);
  }

  /// Cos encoding for cyclical features
  double _cosEncode(int value, int period) {
    return cos(2 * 3.141592653589793 * value / period);
  }

  /// Post-process model output into schedule predictions
  List<SchedulePrediction> _postprocessPredictions(
    String userId,
    String deviceId,
    List<double> output,
    List<SensorData> sensorLogs,
  ) {
    if (output.length < 2) {
      Logger.warning('Invalid model output: ${output.length} values');
      return [];
    }

    // Model outputs: [fanSpeed, ledBrightness] in 0-1 range
    final fanSpeedNormalized = output[0].clamp(0.0, 1.0);
    final ledBrightnessNormalized = output[1].clamp(0.0, 1.0);

    // Convert to 0-255 range
    final fanSpeed = (fanSpeedNormalized * 255).round().clamp(0, 255);
    final ledBrightness = (ledBrightnessNormalized * 255).round().clamp(0, 255);

    // Generate predictions for next 24 hours (one per hour)
    // This provides more useful predictions for the user
    final now = DateTime.now();
    final predictions = <SchedulePrediction>[];

    // Generate predictions for next 24 hours
    for (int hourOffset = 1; hourOffset <= 24; hourOffset++) {
      final predictionTime = now.add(Duration(hours: hourOffset));
      
      // Calculate confidence based on how far in the future (closer = higher confidence)
      final confidence = (1.0 - (hourOffset / 24.0) * 0.3).clamp(0.7, 0.95);

      // Fan schedule - only add if value is significant (>10%)
      if (fanSpeed > 25) { // ~10% threshold
        predictions.add(SchedulePrediction(
          dayOfWeek: predictionTime.weekday,
          hour: predictionTime.hour,
          minute: 0,
          deviceType: 'fan',
          value: fanSpeed,
          confidence: confidence,
          reason: hourOffset <= 6 
              ? 'AI predicted based on your recent usage patterns'
              : 'AI predicted based on your historical patterns',
          deviceId: deviceId,
        ));
      }

      // LED/Light schedule - only add if value is significant (>10%)
      if (ledBrightness > 25) { // ~10% threshold
        predictions.add(SchedulePrediction(
          dayOfWeek: predictionTime.weekday,
          hour: predictionTime.hour,
          minute: 0,
          deviceType: 'light', // Changed from 'led' to 'light' to match UI expectations
          value: ledBrightness,
          confidence: confidence,
          reason: hourOffset <= 6 
              ? 'AI predicted based on your recent usage patterns'
              : 'AI predicted based on your historical patterns',
          deviceId: deviceId,
        ));
      }
    }

    // Limit to top 12 predictions (6 fan + 6 LED max) to avoid overwhelming UI
    // Sort by confidence and take top ones
    predictions.sort((a, b) => b.confidence.compareTo(a.confidence));
    final limitedPredictions = predictions.take(12).toList();

    Logger.info('Generated ${limitedPredictions.length} local predictions for next 24 hours');
    return limitedPredictions;
  }

  /// Generate cache key from input parameters
  String _generateCacheKey(String userId, String deviceId, List<SensorData> logs) {
    // Use last 24 hours of data hash for cache key
    final recentLogs = logs.length > 24 ? logs.sublist(logs.length - 24) : logs;
    final keyData = recentLogs.map((l) => 
      '${l.timestamp.millisecondsSinceEpoch}-${l.temperature.toStringAsFixed(1)}-${l.humidity.toStringAsFixed(1)}-${l.motionDetected}'
    ).join('|');
    return '$userId|$deviceId|${keyData.hashCode}';
  }
  
  /// Clear prediction cache
  void clearCache() {
    _predictionCache.clear();
    Logger.info('🗑️  Prediction cache cleared');
  }

  /// Dispose resources
  void dispose() {
    _schedulePredictor?.close();
    _schedulePredictor = null;
    _isInitialized = false;
    _predictionCache.clear();
  }
}

