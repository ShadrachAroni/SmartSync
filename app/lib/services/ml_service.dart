// import 'package:cloud_functions/cloud_functions.dart'; // Unused - Cloud Functions disabled for Spark plan
import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/utils/logger.dart';
import '../models/sensor_data.dart';
import '../models/ml_prediction.dart';
import 'tflite_service.dart';

/// ML Service for SmartSync
///
/// Uses local TFLite models for inference (primary)
/// Falls back to Firebase Cloud Functions if local inference fails
class MLService {
  static final MLService _instance = MLService._internal();
  factory MLService() => _instance;
  MLService._internal();

  // final FirebaseFunctions _functions = FirebaseFunctions.instance; // Unused - Cloud Functions disabled for Spark plan
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TFLiteService _tfliteService = TFLiteService();

  bool _isInitialized = false;

  /// Initialize ML Service
  Future<void> initialize() async {
    if (_isInitialized) {
      Logger.debug('ML Service already initialized');
      return;
    }

    try {
      Logger.info('Initializing ML Service...');

      // Initialize local TFLite service (primary)
      final tfliteReady = await _tfliteService.initialize();
      if (tfliteReady) {
        Logger.success('Local TFLite models loaded');
      } else {
        Logger.warning('Local TFLite models not available, will use server-side');
      }

      // Check if server-side models are deployed (fallback)
      // Use timeout to prevent hanging if Firestore is slow
      try {
        final config = await _firestore
            .collection('system_config')
            .doc('ml_models')
            .get()
            .timeout(const Duration(seconds: 5));

        if (config.exists) {
          final models = config.data()?['models'] as Map<String, dynamic>?;

          if (models != null) {
            Logger.info('Server-side ML models available (fallback):');
            models.forEach((name, info) {
              Logger.info('  - $name: ${info['currentVersion']}');
            });
          }
        } else {
          Logger.info('No server-side ML models found (local models will be used)');
        }
      } catch (e) {
        Logger.warning('Could not check server-side models: $e (continuing with local models)');
      }

      _isInitialized = true;
      Logger.success('ML Service initialized');
    } catch (e) {
      Logger.error('ML initialization failed: $e');
      // Still mark as initialized to prevent infinite retries
      _isInitialized = true;
    }
  }

  /// Predict optimal schedules based on historical data
  ///
  /// Uses local TFLite model first (primary)
  /// Falls back to Cloud Function if local inference fails
  Future<List<SchedulePrediction>> predictSchedules(
    String userId,
    String deviceId,
  ) async {
    try {
      Logger.info('Requesting schedule prediction...');

      // Ensure ML Service is initialized before making predictions
      if (!_isInitialized) {
        Logger.info('ML Service not initialized, initializing now...');
        await initialize();
      }

      // ========== PRIMARY: Try local TFLite inference first ==========
      if (_tfliteService.isReady) {
        try {
          Logger.info('🤖 PRIMARY: Attempting local TFLite inference (using trained model from assets)...');

          // Fetch sensor logs for local inference
          final sensorLogs = await _fetchSensorLogs(userId, deviceId, hours: 24);

          if (sensorLogs.length >= 24) {
            final localPredictions = await _tfliteService.predictSchedulesLocal(
              userId,
              deviceId,
              sensorLogs,
            );

            if (localPredictions.isNotEmpty) {
              Logger.success('✅ PRIMARY SUCCESS: Local TFLite inference completed - ${localPredictions.length} predictions generated from local model');
              Logger.info('   📊 Using model: assets/models/schedule_predictor.tflite (from train_smart_home.py)');
              return localPredictions; // Return immediately - local model takes priority
            } else {
              Logger.warning('⚠️  Local inference returned no predictions, falling back to server');
            }
          } else {
            Logger.warning('⚠️  Insufficient sensor data for local inference (${sensorLogs.length}/24 hours), falling back to server');
          }
        } catch (e) {
          Logger.warning('⚠️  Local inference failed: $e, falling back to server');
        }
      } else {
        Logger.warning('⚠️  Local TFLite models not ready, using server-side inference (fallback)');
      }

      // ========== FALLBACK: Server-side inference only if local fails ==========
      // Note: Cloud Functions require Blaze plan, so this fallback is disabled on Spark plan
      Logger.warning('⚠️  Local TFLite inference unavailable. Server-side inference requires Blaze plan.');
      Logger.info('💡 Please ensure local TFLite models are available in assets/models/');
      return await _predictSchedulesServer(userId, deviceId);
    } catch (e) {
      Logger.error('Schedule prediction failed: $e');
      return [];
    }
  }

  /// Fetch sensor logs from Firestore
  Future<List<SensorData>> _fetchSensorLogs(
    String userId,
    String deviceId, {
    int hours = 24,
  }) async {
    try {
      final cutoff = DateTime.now().subtract(Duration(hours: hours));

      // Build query - handle 'all' deviceId
      Query query = _firestore
          .collection('sensor_logs')
          .where('userId', isEqualTo: userId)
          .where('timestamp', isGreaterThan: Timestamp.fromDate(cutoff));

      // Only filter by deviceId if it's not 'all'
      if (deviceId != 'all' && deviceId.isNotEmpty) {
        query = query.where('deviceId', isEqualTo: deviceId);
      }

      final snapshot = await query.orderBy('timestamp').get();

      final logs = snapshot.docs
          .map((doc) => SensorData.fromJson(doc.data() as Map<String, dynamic>))
          .toList();

      Logger.info('Fetched ${logs.length} sensor logs');
      return logs;
    } catch (e) {
      Logger.error('Failed to fetch sensor logs: $e');
      return [];
    }
  }

  /// Server-side schedule prediction (fallback)
  /// 
  /// NOTE: Cloud Functions require Blaze plan. This fallback is disabled
  /// when running on Spark plan. The app uses local TFLite models instead.
  Future<List<SchedulePrediction>> _predictSchedulesServer(
    String userId,
    String deviceId,
  ) async {
    // Cloud Functions are not available on Spark plan
    // Return empty list - local TFLite inference should have been used instead
    Logger.info('ℹ️  Server-side inference skipped (Cloud Functions require Blaze plan). Using local TFLite models only.');
    Logger.info('💡 Tip: Ensure local TFLite models are loaded for ML predictions.');
    return [];
    
    // Original Cloud Function code (disabled for Spark plan compatibility):
    /*
    try {
      // Call Cloud Function
      final callable = _functions.httpsCallable('predictSchedule');
      final result = await callable.call<Map<String, dynamic>>({
        'userId': userId,
        'deviceId': deviceId,
      });

      if (result.data['success'] == true) {
        final schedulesRaw = result.data['schedules'];

        if (schedulesRaw is! List) {
          Logger.warning('ML response missing schedules payload');
          return [];
        }

        final predictions = schedulesRaw
            .whereType<Map<String, dynamic>>()
            .map(_parseSchedulePrediction)
            .whereType<SchedulePrediction>()
            .toList();

        if (predictions.isEmpty) {
          Logger.warning('ML response contained no valid schedules');
        }

        return predictions;
      } else {
        final message = result.data['message'] ?? 'Unknown ML response error';
        Logger.warning('ML prediction unsuccessful: $message');
      }

      return [];
    } on FirebaseFunctionsException catch (e) {
      // Handle NOT_FOUND gracefully - function may not be deployed
      if (e.code == 'not-found') {
        Logger.warning('⚠️  Cloud Function "predictSchedule" not found. It may not be deployed yet. Returning empty predictions.');
        return [];
      }
      // Handle other Firebase function errors gracefully
      Logger.error('Server-side schedule prediction failed: ${e.code} - ${e.message}');
      return [];
    } catch (e) {
      Logger.error('Server-side schedule prediction failed with unexpected error: $e');
      return [];
    }
    */
  }

  // Unused - Only needed when Cloud Functions are enabled (Blaze plan)
  // SchedulePrediction? _parseSchedulePrediction(
  //     Map<String, dynamic> payload) {
  //   try {
  //     final hour = payload['hour'];
  //     final minute = payload['minute'];
  //     final deviceType = payload['deviceType'];
  //     final value = payload['value'];
  //     final confidence = payload['confidence'];
  //
  //     if (hour is! int ||
  //         minute is! int ||
  //         deviceType is! String ||
  //         value is! int ||
  //         confidence is! num) {
  //       throw FormatException('Missing schedule fields: $payload');
  //     }
  //
  //     return SchedulePrediction(
  //       dayOfWeek: payload['dayOfWeek'] as int? ?? (hour ~/ 24 % 7) + 1,
  //       hour: hour,
  //       minute: minute,
  //       deviceType: deviceType,
  //       value: value,
  //       confidence: confidence.toDouble(),
  //       reason: payload['reason'] as String? ??
  //           'AI predicted based on your usage patterns',
  //       deviceId: payload['deviceId'] as String?,
  //       deviceName: payload['deviceName'] as String?,
  //       roomId: payload['roomId'] as String?,
  //     );
  //   } catch (e) {
  //     Logger.error('Failed to parse schedule prediction: $e');
  //     return null;
  //   }
  // }

  /// Detect anomalies in user activity
  ///
  /// Note: Anomaly detection runs automatically every 6 hours via Cloud Scheduler
  /// This method checks for recent anomaly alerts
  Future<AnomalyReport?> detectAnomalies(
    String userId,
    Duration window,
  ) async {
    try {
      final cutoff = DateTime.now().subtract(window);

      // Query recent alerts
      final snapshot = await _firestore
          .collection('alerts')
          .where('userId', isEqualTo: userId)
          .where('type', isEqualTo: 'health')
          .where('timestamp', isGreaterThan: Timestamp.fromDate(cutoff))
          .orderBy('timestamp', descending: true)
          .get();

      if (snapshot.docs.isEmpty) {
        return AnomalyReport(
          timestamp: DateTime.now(),
          anomalies: [],
          overallScore: 0.0,
        );
      }

      final anomalies = snapshot.docs.map((doc) {
        final data = doc.data();
        return Anomaly(
          type: _parseAnomalyType(data['data']?['anomalyType']),
          severity: data['severity'] ?? 'low',
          message: data['message'] ?? '',
          timestamp: (data['timestamp'] as Timestamp).toDate(),
          confidence: 0.85,
        );
      }).toList();

      return AnomalyReport(
        timestamp: DateTime.now(),
        anomalies: anomalies,
        overallScore: anomalies.isNotEmpty ? 0.75 : 0.0,
      );
    } catch (e) {
      Logger.error('Anomaly detection check failed: $e');
      return null;
    }
  }

  AnomalyType _parseAnomalyType(String? type) {
    switch (type) {
      case 'extended_inactivity':
        return AnomalyType.inactivity;
      case 'excessive_night_activity':
        return AnomalyType.unusualActivity;
      case 'temperature_extreme':
        return AnomalyType.temperatureExtreme;
      default:
        return AnomalyType.suddenChange;
    }
  }

  /// Get analytics insights
  Future<AnalyticsInsights> getInsights(String userId, int days) async {
    try {
      final cutoff = DateTime.now().subtract(Duration(days: days));

      // Fetch sensor logs
      final snapshot = await _firestore
          .collection('sensor_logs')
          .where('userId', isEqualTo: userId)
          .where('timestamp', isGreaterThan: Timestamp.fromDate(cutoff))
          .orderBy('timestamp', descending: true)
          .limit(1000)
          .get();

      if (snapshot.docs.isEmpty) {
        return _getDefaultInsights();
      }

      final logs =
          snapshot.docs.map((doc) => SensorData.fromJson(doc.data())).toList();

      // Calculate statistics
      final avgTemp =
          logs.map((l) => l.temperature).reduce((a, b) => a + b) / logs.length;
      final avgHumidity =
          logs.map((l) => l.humidity).reduce((a, b) => a + b) / logs.length;
      final motionEvents = logs.where((l) => l.motionDetected).length;
      final avgFan =
          logs.map((l) => l.fanSpeed.toDouble()).reduce((a, b) => a + b) /
              logs.length;
      final avgLed =
          logs.map((l) => l.ledBrightness.toDouble()).reduce((a, b) => a + b) /
              logs.length;

      // Find peak usage hour
      final hourCounts = <int, int>{};
      for (var log in logs) {
        final hour = log.timestamp.hour;
        hourCounts[hour] = (hourCounts[hour] ?? 0) + 1;
      }
      final peakHour =
          hourCounts.entries.reduce((a, b) => a.value > b.value ? a : b).key;

      // Calculate energy consumption properly (Energy = Power × Time)
      // Sort logs by timestamp to calculate time intervals
      final sortedLogs = List<SensorData>.from(logs)
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
      
      double energy = 0.0;
      
      if (sortedLogs.isEmpty) {
        energy = 0.0;
      } else {
        // Calculate energy for each time interval
        for (int i = 0; i < sortedLogs.length; i++) {
          final log = sortedLogs[i];
          
          // Calculate power in kW
          final fanPowerKw = (log.fanSpeed / 255.0) * 0.05; // 0-0.05 kW
          final ledPowerKw = (log.ledBrightness / 255.0) * 0.01; // 0-0.01 kW
          final totalPowerKw = fanPowerKw + ledPowerKw;
          
          // Calculate time duration
          Duration duration;
          if (i < sortedLogs.length - 1) {
            duration = sortedLogs[i + 1].timestamp.difference(log.timestamp);
          } else {
            // Last log: use time until now or default 5 minutes
            duration = DateTime.now().difference(log.timestamp);
            if (duration.isNegative || duration.inMinutes > 60) {
              duration = const Duration(minutes: 5);
            }
          }
          
          // Ensure minimum duration of 1 minute
          final hours = duration.inSeconds.clamp(60, 3600) / 3600.0;
          
          // Energy = Power × Time
          energy += totalPowerKw * hours;
        }
      }

      return AnalyticsInsights(
        totalLogs: logs.length,
        avgTemperature: avgTemp,
        avgHumidity: avgHumidity,
        motionEvents: motionEvents,
        avgFanUsage: avgFan,
        avgLightUsage: avgLed,
        peakUsageHour: peakHour,
        energyConsumption: energy,
      );
    } catch (e) {
      Logger.error('Failed to get insights: $e');
      return _getDefaultInsights();
    }
  }

  AnalyticsInsights _getDefaultInsights() {
    // Return insights with zero values to indicate no data
    // The UI should handle this appropriately
    return AnalyticsInsights(
      totalLogs: 0,
      avgTemperature: 0.0,
      avgHumidity: 0.0,
      motionEvents: 0,
      avgFanUsage: 0.0,
      avgLightUsage: 0.0,
      peakUsageHour: 0,
      energyConsumption: 0.0,
    );
  }

  void dispose() {
    _tfliteService.dispose();
  }
}
