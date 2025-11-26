import 'dart:async';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
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

  static const bool _enableLocalInference = false;

  // Use default region (us-central1) - change if your functions are deployed to a different region
  // Example: FirebaseFunctions.instanceFor(region: 'us-east1')
  final FirebaseFunctions _functions = FirebaseFunctions.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TFLiteService _tfliteService = TFLiteService();

  bool _isInitialized = false;

  /// Initialize ML Service
  Future<void> initialize() async {
    if (_isInitialized) {
      return;
    }

    try {
      Logger.info('Initializing ML Service...');

      // Initialize local TFLite service (primary) when enabled
      if (_enableLocalInference) {
        final tfliteReady = await _tfliteService.initialize();
        if (tfliteReady) {
          Logger.success('Local TFLite models loaded');
        } else {
          Logger.warning('Local TFLite models not available, will use server-side');
        }
      } else {
        Logger.info('Local TFLite inference disabled. Using server-side predictions.');
      }

      // Note: Cloud Function verification happens on first call
      // See CLOUD_FUNCTION_TROUBLESHOOTING.md if you get "not-found" errors

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
      // Ensure ML Service is initialized before making predictions
      if (!_isInitialized) {
        await initialize();
      }

      // ========== PRIMARY: Try local TFLite inference first ==========
      if (_enableLocalInference && _tfliteService.isReady) {
        try {

          // Fetch sensor logs for local inference
          // Fetch up to 30 days to capture all available historical data
          // The model only uses the last 24 hours, but fetching more ensures we have enough
          // even if data is sparse. Works with minimum 1 day (24 hours) of data.
          final sensorLogs = await _fetchSensorLogs(userId, deviceId, hours: 30 * 24);

          // Check if we have at least 24 distinct hours of data (minimum requirement)
          final distinctHours = sensorLogs.map((log) {
            return DateTime(
              log.timestamp.year,
              log.timestamp.month,
              log.timestamp.day,
              log.timestamp.hour,
            );
          }).toSet();
          
          Logger.info('📊 Data check: ${sensorLogs.length} total logs, ${distinctHours.length} distinct hours');
          
          // Minimum requirement: 24 distinct hours (works with 1 day of data)
          // We check distinct hours first as that's what the model actually needs
          if (distinctHours.length >= 24) {
            final localPredictions = await _tfliteService.predictSchedulesLocal(
              userId,
              deviceId,
              sensorLogs,
            );

            if (localPredictions.isNotEmpty) {
              Logger.success('✅ PRIMARY SUCCESS: Local TFLite inference completed - ${localPredictions.length} predictions generated from local model');
              Logger.info('   📊 Using model: assets/models/schedule_predictor.tflite (from train_smart_home.py)');
              Logger.info('   📊 Data: ${sensorLogs.length} hours collected (model requires 24 hours)');
              return localPredictions; // Return immediately - local model takes priority
            } else {
              Logger.warning('⚠️  Local inference returned no predictions, falling back to server');
            }
          } else {
            Logger.warning('⚠️  Insufficient data for local inference: ${sensorLogs.length} data points, ${distinctHours.length} distinct hours');
            Logger.info('   💡 The model requires at least 24 distinct hours (1 day) of sensor data to generate predictions');
            Logger.info('   💡 You have ${distinctHours.length} distinct hours. Need 24+ hours with data.');
            Logger.info('   💡 Generate at least 1 day of test data to enable predictions.');
          }
        } catch (e) {
          Logger.warning('⚠️  Local inference failed: $e, falling back to server');
        }
      } else {
        // Local TFLite inference is disabled or models not ready
        // This is expected behavior - the app is configured to use server-side inference
        Logger.info('ℹ️  Local TFLite inference disabled. Using server-side inference (if available).');
      }

      // ========== FALLBACK: Server-side inference only if local fails ==========
      // Note: Cloud Functions require Blaze plan, so this fallback is disabled on Spark plan
      // Local TFLite inference unavailable
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
      Logger.info('📥 Fetching sensor logs: userId=$userId, deviceId=$deviceId, hours=$hours, cutoff=${cutoff.toIso8601String()}');

      // Build query - handle 'all' deviceId
      Query query = _firestore
          .collection('sensor_logs')
          .where('userId', isEqualTo: userId)
          .where('timestamp', isGreaterThan: Timestamp.fromDate(cutoff));

      // Only filter by deviceId if it's not 'all'
      if (deviceId != 'all' && deviceId.isNotEmpty) {
        query = query.where('deviceId', isEqualTo: deviceId);
      }

      // Add a reasonable limit to avoid fetching too much data at once
      // 30 days * 24 hours * 12 readings per hour (5-min intervals) = 8,640 max
      // Use 10,000 to be safe
      query = query.orderBy('timestamp').limit(10000);

      final snapshot = await query.get();

      final logs = snapshot.docs
          .map((doc) => SensorData.fromJson(doc.data() as Map<String, dynamic>))
          .toList();

      Logger.info('✅ Fetched ${logs.length} sensor logs from Firestore');
      if (logs.isNotEmpty) {
        final oldest = logs.first.timestamp;
        final newest = logs.last.timestamp;
        Logger.info('   Time range: ${oldest.toIso8601String()} to ${newest.toIso8601String()}');
      }

      return logs;
    } catch (e, stackTrace) {
      Logger.error('Failed to fetch sensor logs: $e', stackTrace);
      // If it's an index error, provide helpful message
      if (e.toString().contains('index') || e.toString().contains('Index')) {
        Logger.warning('⚠️  Firestore index may be missing. Check Firebase Console for required indexes.');
      }
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
    try {
      Logger.info('🔮 Calling Cloud Function predictSchedule for userId: $userId, deviceId: $deviceId');
      
      // Verify user is authenticated
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        Logger.error('❌ User not authenticated. Cloud Functions require authentication.');
        return [];
      }
      Logger.debug('✅ User authenticated: ${user.uid}');
      
      final callable = _functions.httpsCallable(
        'predictSchedule',
        options: HttpsCallableOptions(
          timeout: const Duration(seconds: 60),
        ),
      );
      
      Logger.debug('📞 Invoking Cloud Function predictSchedule...');
      Logger.debug('   Region: default (us-central1) - change if your functions are in a different region');
      Logger.debug('   Project: ${FirebaseFirestore.instance.app.options.projectId}');
      
      final result = await callable.call<Map<String, dynamic>>({
        'userId': userId,
        'deviceId': deviceId,
      });
      
      Logger.info('✅ Cloud Function responded successfully');

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
    } on FirebaseFunctionsException catch (e) {
      Logger.error(
          '❌ Cloud Function error: code=${e.code}, message=${e.message}, details=${e.details}');
      
      if (e.code == 'not-found') {
        Logger.error(
            '❌ Cloud Function "predictSchedule" not found. Possible causes:');
        Logger.error('   1. Function not deployed: Run "firebase deploy --only functions:predictSchedule"');
        Logger.error('   2. Wrong region: Function might be in a different region (check Firebase Console)');
        Logger.error('   3. Wrong project: App might be connected to different Firebase project');
        Logger.error('   4. Function name mismatch: Check function name in Firebase Console');
        Logger.error('   5. App Check blocking: If you see "App attestation failed", App Check might be blocking the call');
        Logger.error('   💡 To verify: Go to Firebase Console → Functions and check if predictSchedule exists');
        Logger.error('   💡 Current project: ${FirebaseFirestore.instance.app.options.projectId}');
        Logger.error('   💡 See CLOUD_FUNCTION_TROUBLESHOOTING.md for detailed steps');
        return [];
      } else if (e.code == 'unavailable' || e.code == 'deadline-exceeded') {
        Logger.warning(
            '⚠️  Cloud Function temporarily unavailable. This may be due to cold start or network issues.');
        Logger.warning('   💡 Try again in a few seconds - first invocation can take 30-60 seconds');
        return [];
      } else if (e.code == 'unauthenticated') {
        Logger.error('❌ Authentication failed. User must be logged in to call Cloud Functions.');
        return [];
      } else if (e.code == 'permission-denied') {
        Logger.error('❌ Permission denied. Check Firestore security rules and user permissions.');
        return [];
      } else if (e.code == 'failed-precondition') {
        Logger.warning('⚠️  Function precondition failed: ${e.message}');
        Logger.warning('   💡 This usually means insufficient data or validation failed');
        return [];
      } else if (e.code == 'internal') {
        Logger.error('❌ Internal server error in Cloud Function. Check function logs in Firebase Console.');
        Logger.error('   💡 View logs: Firebase Console → Functions → predictSchedule → Logs');
        return [];
      }
      Logger.error(
          '❌ Server-side schedule prediction failed: ${e.code} - ${e.message}');
      Logger.error('   Details: ${e.details}');
    } on TimeoutException catch (e) {
      Logger.error('⏱️  Cloud Function call timed out: $e');
      Logger.error('   💡 The function might be taking too long. Check function logs for errors.');
      return [];
    } catch (e, stackTrace) {
      // Handle any other errors gracefully
      Logger.error('❌ Unexpected error calling Cloud Function: $e');
      Logger.error('   Stack trace: $stackTrace');
      if (e.toString().contains('not found') || e.toString().contains('not-found')) {
        Logger.error('   💡 Function not found. Verify deployment: firebase functions:list');
        return [];
      }
    }

    return [];
  }

  SchedulePrediction? _parseSchedulePrediction(
      Map<String, dynamic> payload) {
    try {
      final hour = payload['hour'];
      final minute = payload['minute'];
      final deviceType = payload['deviceType'];
      final value = payload['value'];
      final confidence = payload['confidence'];

      if (hour is! int ||
          minute is! int ||
          deviceType is! String ||
          value is! int ||
          confidence is! num) {
        throw FormatException('Missing schedule fields: $payload');
      }

      return SchedulePrediction(
        dayOfWeek: payload['dayOfWeek'] as int? ?? (hour ~/ 24 % 7) + 1,
        hour: hour,
        minute: minute,
        deviceType: deviceType,
        value: value,
        confidence: confidence.toDouble(),
        reason: payload['reason'] as String? ??
            'AI predicted based on your usage patterns',
        deviceId: payload['deviceId'] as String?,
        deviceName: payload['deviceName'] as String?,
        roomId: payload['roomId'] as String?,
      );
    } catch (e) {
      Logger.error('Failed to parse schedule prediction: $e');
      return null;
    }
  }

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

  /// Stream analytics insights for real-time updates
  Stream<AnalyticsInsights> watchInsights(String userId, int days) {
    final cutoff = DateTime.now().subtract(Duration(days: days));
    
    return _firestore
        .collection('sensor_logs')
        .where('userId', isEqualTo: userId)
        .where('timestamp', isGreaterThan: Timestamp.fromDate(cutoff))
        .orderBy('timestamp', descending: true)
        .limit(1000)
        .snapshots()
        .map((snapshot) {
      try {
        if (snapshot.docs.isEmpty) {
          return _getDefaultInsights();
        }

        final logs = snapshot.docs
            .map((doc) => SensorData.fromJson(doc.data()))
            .toList();

        // Calculate statistics
        final avgTemp = logs.map((l) => l.temperature).reduce((a, b) => a + b) / logs.length;
        final avgHumidity = logs.map((l) => l.humidity).reduce((a, b) => a + b) / logs.length;
        final motionEvents = logs.where((l) => l.motionDetected).length;
        final avgFan = logs.map((l) => l.fanSpeed.toDouble()).reduce((a, b) => a + b) / logs.length;
        final avgLed = logs.map((l) => l.ledBrightness.toDouble()).reduce((a, b) => a + b) / logs.length;

        // Find peak usage hour
        final hourCounts = <int, int>{};
        for (var log in logs) {
          final hour = log.timestamp.hour;
          hourCounts[hour] = (hourCounts[hour] ?? 0) + 1;
        }
        final peakHour = hourCounts.isNotEmpty
            ? hourCounts.entries.reduce((a, b) => a.value > b.value ? a : b).key
            : 0;

        // Calculate energy consumption properly (Energy = Power × Time)
        final sortedLogs = List<SensorData>.from(logs)
          ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
        
        double energy = 0.0;
        
        if (sortedLogs.isNotEmpty) {
          // If we have very few logs, use average power over the entire time period
          if (sortedLogs.length < 10) {
            final firstLog = sortedLogs.first;
            final lastLog = sortedLogs.last;
            final totalDuration = lastLog.timestamp.difference(firstLog.timestamp);
            
            if (totalDuration.inHours > 0 || totalDuration.inMinutes > 0) {
              // Calculate average power across all logs
              double totalFanPower = 0.0;
              double totalLedPower = 0.0;
              for (var log in sortedLogs) {
                totalFanPower += (log.fanSpeed / 255.0) * 0.05;
                totalLedPower += (log.ledBrightness / 255.0) * 0.01;
              }
              final avgFanPower = totalFanPower / sortedLogs.length;
              final avgLedPower = totalLedPower / sortedLogs.length;
              final avgTotalPower = avgFanPower + avgLedPower;
              
              // Use the time span from first to last log, or until now if last log is recent
              final endTime = lastLog.timestamp.isAfter(DateTime.now().subtract(const Duration(hours: 1)))
                  ? DateTime.now()
                  : lastLog.timestamp;
              final hours = endTime.difference(firstLog.timestamp).inSeconds.clamp(60, 86400) / 3600.0;
              energy = avgTotalPower * hours;
            }
          } else {
            // For many logs, use interval-based calculation
            for (int i = 0; i < sortedLogs.length; i++) {
              final log = sortedLogs[i];
              
              final fanPowerKw = (log.fanSpeed / 255.0) * 0.05;
              final ledPowerKw = (log.ledBrightness / 255.0) * 0.01;
              final totalPowerKw = fanPowerKw + ledPowerKw;
              
              Duration duration;
              if (i < sortedLogs.length - 1) {
                duration = sortedLogs[i + 1].timestamp.difference(log.timestamp);
              } else {
                duration = DateTime.now().difference(log.timestamp);
                if (duration.isNegative || duration.inMinutes > 60) {
                  duration = const Duration(minutes: 5);
                }
              }
              
              // Use minimum of 1 minute, but don't clamp maximum too aggressively
              final hours = duration.inSeconds.clamp(60, 3600) / 3600.0;
              energy += totalPowerKw * hours;
            }
          }
          
          // Ensure minimum energy is shown if devices are actually being used
          if (energy < 0.01 && sortedLogs.any((log) => log.fanSpeed > 0 || log.ledBrightness > 0)) {
            // Estimate based on average usage if calculated energy is too small
            final avgFan = sortedLogs.map((l) => l.fanSpeed).reduce((a, b) => a + b) / sortedLogs.length;
            final avgLed = sortedLogs.map((l) => l.ledBrightness).reduce((a, b) => a + b) / sortedLogs.length;
            if (avgFan > 0 || avgLed > 0) {
              final avgPower = ((avgFan / 255.0) * 0.05) + ((avgLed / 255.0) * 0.01);
              final timeSpan = sortedLogs.last.timestamp.difference(sortedLogs.first.timestamp);
              final hours = timeSpan.inSeconds.clamp(3600, 86400) / 3600.0;
              energy = avgPower * hours;
            }
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
        Logger.error('Failed to calculate insights from stream: $e');
        return _getDefaultInsights();
      }
    }).handleError((error, stackTrace) {
      Logger.error('watchInsights: Stream error', error, stackTrace);
      // Return default insights on error to prevent stream from closing
      return _getDefaultInsights();
    });
  }

  /// Get analytics insights (one-time fetch)
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
      final peakHour = hourCounts.isNotEmpty
          ? hourCounts.entries.reduce((a, b) => a.value > b.value ? a : b).key
          : 0;

      // Calculate energy consumption properly (Energy = Power × Time)
      // Sort logs by timestamp to calculate time intervals
      final sortedLogs = List<SensorData>.from(logs)
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
      
      double energy = 0.0;
      
      if (sortedLogs.isEmpty) {
        energy = 0.0;
      } else {
        // If we have very few logs, use average power over the entire time period
        if (sortedLogs.length < 10) {
          final firstLog = sortedLogs.first;
          final lastLog = sortedLogs.last;
          final totalDuration = lastLog.timestamp.difference(firstLog.timestamp);
          
          if (totalDuration.inHours > 0 || totalDuration.inMinutes > 0) {
            // Calculate average power across all logs
            double totalFanPower = 0.0;
            double totalLedPower = 0.0;
            for (var log in sortedLogs) {
              totalFanPower += (log.fanSpeed / 255.0) * 0.05;
              totalLedPower += (log.ledBrightness / 255.0) * 0.01;
            }
            final avgFanPower = totalFanPower / sortedLogs.length;
            final avgLedPower = totalLedPower / sortedLogs.length;
            final avgTotalPower = avgFanPower + avgLedPower;
            
            // Use the time span from first to last log, or until now if last log is recent
            final endTime = lastLog.timestamp.isAfter(DateTime.now().subtract(const Duration(hours: 1)))
                ? DateTime.now()
                : lastLog.timestamp;
            final hours = endTime.difference(firstLog.timestamp).inSeconds.clamp(60, 86400) / 3600.0;
            energy = avgTotalPower * hours;
          }
        } else {
          // For many logs, use interval-based calculation
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
        
        // Ensure minimum energy is shown if devices are actually being used
        if (energy < 0.01 && sortedLogs.any((log) => log.fanSpeed > 0 || log.ledBrightness > 0)) {
          // Estimate based on average usage if calculated energy is too small
          final avgFan = sortedLogs.map((l) => l.fanSpeed).reduce((a, b) => a + b) / sortedLogs.length;
          final avgLed = sortedLogs.map((l) => l.ledBrightness).reduce((a, b) => a + b) / sortedLogs.length;
          if (avgFan > 0 || avgLed > 0) {
            final avgPower = ((avgFan / 255.0) * 0.05) + ((avgLed / 255.0) * 0.01);
            final timeSpan = sortedLogs.last.timestamp.difference(sortedLogs.first.timestamp);
            final hours = timeSpan.inSeconds.clamp(3600, 86400) / 3600.0;
            energy = avgPower * hours;
          }
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

  /// Get previous period insights for trend comparison
  Future<AnalyticsInsights?> getPreviousPeriodInsights(String userId, int days) async {
    try {
      // Calculate previous period range (same duration, but before current period)
      final currentCutoff = DateTime.now().subtract(Duration(days: days));
      final previousCutoff = currentCutoff.subtract(Duration(days: days));

      // Fetch sensor logs from previous period
      // Note: Firestore requires orderBy on the field used in range queries
      // We use a single range query with isGreaterThan and filter in memory for upper bound
      // to avoid needing a composite index
      final snapshot = await _firestore
          .collection('sensor_logs')
          .where('userId', isEqualTo: userId)
          .where('timestamp', isGreaterThan: Timestamp.fromDate(previousCutoff))
          .orderBy('timestamp', descending: false)
          .limit(1000)
          .get();
      
      // Filter to only include logs before current cutoff
      final filteredDocs = snapshot.docs.where((doc) {
        final timestamp = (doc.data()['timestamp'] as Timestamp?)?.toDate();
        if (timestamp == null) return false;
        return timestamp.isAfter(previousCutoff) && 
               (timestamp.isBefore(currentCutoff) || timestamp.isAtSameMomentAs(currentCutoff));
      }).toList();

      if (filteredDocs.isEmpty) {
        return null; // No previous period data available
      }

      final logs =
          filteredDocs.map((doc) => SensorData.fromJson(doc.data())).toList();

      // Calculate statistics for previous period
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
      final peakHour = hourCounts.isNotEmpty
          ? hourCounts.entries.reduce((a, b) => a.value > b.value ? a : b).key
          : 0;

      // Calculate energy consumption for previous period
      final sortedLogs = List<SensorData>.from(logs)
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
      
      double energy = 0.0;
      
      if (sortedLogs.isNotEmpty) {
        // If we have very few logs, use average power over the entire time period
        if (sortedLogs.length < 10) {
          final firstLog = sortedLogs.first;
          
          // Calculate average power across all logs
          double totalFanPower = 0.0;
          double totalLedPower = 0.0;
          for (var log in sortedLogs) {
            totalFanPower += (log.fanSpeed / 255.0) * 0.05;
            totalLedPower += (log.ledBrightness / 255.0) * 0.01;
          }
          final avgFanPower = totalFanPower / sortedLogs.length;
          final avgLedPower = totalLedPower / sortedLogs.length;
          final avgTotalPower = avgFanPower + avgLedPower;
          
          // Use the time span from first to last log, or until current cutoff
          final endTime = currentCutoff;
          final hours = endTime.difference(firstLog.timestamp).inSeconds.clamp(60, 86400) / 3600.0;
          energy = avgTotalPower * hours;
        } else {
          // For many logs, use interval-based calculation
          for (int i = 0; i < sortedLogs.length; i++) {
            final log = sortedLogs[i];
            
            final fanPowerKw = (log.fanSpeed / 255.0) * 0.05;
            final ledPowerKw = (log.ledBrightness / 255.0) * 0.01;
            final totalPowerKw = fanPowerKw + ledPowerKw;
            
            Duration duration;
            if (i < sortedLogs.length - 1) {
              duration = sortedLogs[i + 1].timestamp.difference(log.timestamp);
            } else {
              duration = currentCutoff.difference(log.timestamp);
              if (duration.isNegative || duration.inMinutes > 60) {
                duration = const Duration(minutes: 5);
              }
            }
            
            final hours = duration.inSeconds.clamp(60, 3600) / 3600.0;
            energy += totalPowerKw * hours;
          }
        }
        
        // Ensure minimum energy is shown if devices are actually being used
        if (energy < 0.01 && sortedLogs.any((log) => log.fanSpeed > 0 || log.ledBrightness > 0)) {
          final avgFan = sortedLogs.map((l) => l.fanSpeed).reduce((a, b) => a + b) / sortedLogs.length;
          final avgLed = sortedLogs.map((l) => l.ledBrightness).reduce((a, b) => a + b) / sortedLogs.length;
          if (avgFan > 0 || avgLed > 0) {
            final avgPower = ((avgFan / 255.0) * 0.05) + ((avgLed / 255.0) * 0.01);
            final timeSpan = currentCutoff.difference(sortedLogs.first.timestamp);
            final hours = timeSpan.inSeconds.clamp(3600, 86400) / 3600.0;
            energy = avgPower * hours;
          }
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
      Logger.error('Failed to get previous period insights: $e');
      return null;
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

  void clearPredictionCache() {
    _tfliteService.clearCache();
  }
}
