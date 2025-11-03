import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/utils/logger.dart';
import '../models/sensor_data.dart';

/// ML Service for SmartSync
///
/// Handles ML inference via Firebase Cloud Functions
/// No local TFLite models needed - all inference on server
class MLService {
  static final MLService _instance = MLService._internal();
  factory MLService() => _instance;
  MLService._internal();

  final FirebaseFunctions _functions = FirebaseFunctions.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool _isInitialized = false;

  /// Initialize ML Service
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      Logger.info('Initializing ML Service...');

      // Check if models are deployed
      final config =
          await _firestore.collection('system_config').doc('ml_models').get();

      if (config.exists) {
        final models = config.data()?['models'] as Map<String, dynamic>?;

        if (models != null) {
          Logger.success('ML models available:');
          models.forEach((name, info) {
            Logger.info('  - $name: ${info['currentVersion']}');
          });
        }
      } else {
        Logger.warning('No ML models found in Firestore');
        Logger.info('Deploy models: python ml/scripts/deploy_model.py');
      }

      _isInitialized = true;
      Logger.success('ML Service initialized');
    } catch (e) {
      Logger.error('ML initialization failed: $e');
    }
  }

  /// Predict optimal schedules based on historical data
  ///
  /// Calls Cloud Function for server-side inference
  Future<List<SchedulePrediction>> predictSchedules(
    String userId,
    String deviceId,
  ) async {
    try {
      Logger.info('Requesting schedule prediction...');

      // Call Cloud Function
      final callable = _functions.httpsCallable('predictSchedule');
      final result = await callable.call<Map<String, dynamic>>({
        'userId': userId,
        'deviceId': deviceId,
      });

      if (result.data['success'] == true) {
        final schedules = result.data['schedules'] as List;

        return schedules
            .map((s) => SchedulePrediction(
                  dayOfWeek: s['hour'] ~/ 24 % 7 + 1,
                  hour: s['hour'] as int,
                  minute: s['minute'] as int,
                  deviceType: s['deviceType'] as String,
                  value: s['value'] as int,
                  confidence: (s['confidence'] as num).toDouble(),
                  reason: 'AI predicted based on your usage patterns',
                ))
            .toList();
      }

      return [];
    } catch (e) {
      Logger.error('Schedule prediction failed: $e');
      return [];
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

      // Estimate energy
      double energy = 0;
      for (var log in logs) {
        energy += (log.fanSpeed / 255.0) * 0.05; // Fan: 50W max
        energy += (log.ledBrightness / 255.0) * 0.01; // LED: 10W max
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
    return AnalyticsInsights(
      totalLogs: 0,
      avgTemperature: 22.0,
      avgHumidity: 50.0,
      motionEvents: 0,
      avgFanUsage: 0.0,
      avgLightUsage: 0.0,
      peakUsageHour: 12,
      energyConsumption: 0.0,
    );
  }

  void dispose() {
    // Cleanup if needed
  }
}

// ==================== DATA MODELS ====================

class SchedulePrediction {
  final int dayOfWeek; // 1-7 (Monday-Sunday)
  final int hour; // 0-23
  final int minute; // 0-59
  final String deviceType; // 'fan' or 'led'
  final int value; // 0-100
  final double confidence; // 0-100
  final String reason;

  SchedulePrediction({
    required this.dayOfWeek,
    required this.hour,
    required this.minute,
    required this.deviceType,
    required this.value,
    required this.confidence,
    required this.reason,
  });

  String get dayName {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[dayOfWeek - 1];
  }

  String get timeString {
    final h = hour.toString().padLeft(2, '0');
    final m = minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

enum AnomalyType {
  inactivity,
  unusualActivity,
  temperatureExtreme,
  suddenChange,
}

class Anomaly {
  final AnomalyType type;
  final String severity; // 'low', 'medium', 'high'
  final String message;
  final DateTime timestamp;
  final double confidence;

  Anomaly({
    required this.type,
    required this.severity,
    required this.message,
    required this.timestamp,
    required this.confidence,
  });
}

class AnomalyReport {
  final DateTime timestamp;
  final List<Anomaly> anomalies;
  final double overallScore;

  AnomalyReport({
    required this.timestamp,
    required this.anomalies,
    required this.overallScore,
  });

  bool get hasAnomalies => anomalies.isNotEmpty;
  bool get hasCritical => anomalies.any((a) => a.severity == 'high');
}

class AnalyticsInsights {
  final int totalLogs;
  final double avgTemperature;
  final double avgHumidity;
  final int motionEvents;
  final double avgFanUsage;
  final double avgLightUsage;
  final int peakUsageHour;
  final double energyConsumption;

  AnalyticsInsights({
    required this.totalLogs,
    required this.avgTemperature,
    required this.avgHumidity,
    required this.motionEvents,
    required this.avgFanUsage,
    required this.avgLightUsage,
    required this.peakUsageHour,
    required this.energyConsumption,
  });
}
