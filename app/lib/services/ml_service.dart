import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/sensor_data.dart';
import '../core/utils/logger.dart';

/// ML Service for TensorFlow Lite model inference
/// Handles schedule prediction and anomaly detection
class MLService {
  static final MLService _instance = MLService._internal();
  factory MLService() => _instance;
  MLService._internal();

  // TFLite interpreter would go here (commented out for now)
  // late Interpreter _scheduleInterpreter;
  // late Interpreter _anomalyInterpreter;

  bool _isInitialized = false;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Initialize ML models
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      Logger.info('Initializing ML Service...');

      // TODO: Uncomment when tflite_flutter is properly configured
      // _scheduleInterpreter = await _loadModel('assets/models/schedule_predictor.tflite');
      // _anomalyInterpreter = await _loadModel('assets/models/anomaly_detector.tflite');

      _isInitialized = true;
      Logger.success('ML Service initialized');
    } catch (e) {
      Logger.error('ML initialization failed: $e');
      // Continue without ML features
    }
  }

  /// Load TFLite model from assets
  // Future<Interpreter> _loadModel(String path) async {
  //   final data = await rootBundle.load(path);
  //   return Interpreter.fromBuffer(data.buffer.asUint8List());
  // }

  /// Predict optimal schedules based on historical data
  Future<List<SchedulePrediction>> predictSchedules(
    String userId,
    String deviceId,
  ) async {
    try {
      // Fetch last 90 days of data
      final logs = await _fetchHistoricalLogs(userId, deviceId, 90);

      if (logs.length < 100) {
        Logger.warning(
            'Insufficient data for prediction (${logs.length} records)');
        return [];
      }

      // Prepare features
      final features = _prepareScheduleFeatures(logs);

      // Run inference (mock for now)
      final predictions = _mockSchedulePrediction(features);

      return predictions;
    } catch (e) {
      Logger.error('Schedule prediction failed: $e');
      return [];
    }
  }

  /// Detect anomalies in user activity
  Future<AnomalyReport?> detectAnomalies(
    String userId,
    Duration window,
  ) async {
    try {
      // Fetch recent data
      final logs = await _fetchRecentLogs(userId, window);

      if (logs.isEmpty) return null;

      // Prepare features
      final features = _prepareAnomalyFeatures(logs);

      // Run inference (mock for now)
      final report = _mockAnomalyDetection(features);

      return report;
    } catch (e) {
      Logger.error('Anomaly detection failed: $e');
      return null;
    }
  }

  /// Fetch historical sensor logs
  Future<List<SensorData>> _fetchHistoricalLogs(
    String userId,
    String deviceId,
    int days,
  ) async {
    final cutoff = DateTime.now().subtract(Duration(days: days));

    final snapshot = await _firestore
        .collection('sensor_logs')
        .where('userId', isEqualTo: userId)
        .where('deviceId', isEqualTo: deviceId)
        .where('timestamp', isGreaterThan: Timestamp.fromDate(cutoff))
        .orderBy('timestamp', descending: true)
        .limit(10000)
        .get();

    return snapshot.docs.map((doc) => SensorData.fromJson(doc.data())).toList();
  }

  /// Fetch recent logs for anomaly detection
  Future<List<SensorData>> _fetchRecentLogs(
    String userId,
    Duration window,
  ) async {
    final cutoff = DateTime.now().subtract(window);

    final snapshot = await _firestore
        .collection('sensor_logs')
        .where('userId', isEqualTo: userId)
        .where('timestamp', isGreaterThan: Timestamp.fromDate(cutoff))
        .orderBy('timestamp', descending: true)
        .limit(1000)
        .get();

    return snapshot.docs.map((doc) => SensorData.fromJson(doc.data())).toList();
  }

  /// Prepare features for schedule prediction
  Map<String, dynamic> _prepareScheduleFeatures(List<SensorData> logs) {
    // Group by day of week and hour
    final hourlyActivity = <int, Map<int, List<SensorData>>>{};

    for (var log in logs) {
      final day = log.timestamp.weekday; // 1-7
      final hour = log.timestamp.hour; // 0-23

      hourlyActivity.putIfAbsent(day, () => {});
      hourlyActivity[day]!.putIfAbsent(hour, () => []);
      hourlyActivity[day]![hour]!.add(log);
    }

    // Calculate features
    final features = <String, dynamic>{
      'hourlyActivity': hourlyActivity,
      'totalLogs': logs.length,
      'avgTemperature': _calculateAverage(logs.map((l) => l.temperature)),
      'avgHumidity': _calculateAverage(logs.map((l) => l.humidity)),
    };

    return features;
  }

  /// Prepare features for anomaly detection
  Map<String, dynamic> _prepareAnomalyFeatures(List<SensorData> logs) {
    final now = DateTime.now();
    final last24h =
        logs.where((l) => now.difference(l.timestamp).inHours <= 24).toList();

    return {
      'motionEvents': last24h.where((l) => l.motionDetected).length,
      'avgTemperature': _calculateAverage(last24h.map((l) => l.temperature)),
      'tempDeviation': _calculateStdDev(last24h.map((l) => l.temperature)),
      'nightActivity': _countNightActivity(last24h),
      'lastActivity': logs.isNotEmpty ? logs.first.timestamp : null,
    };
  }

  /// Mock schedule prediction (replace with actual TFLite inference)
  List<SchedulePrediction> _mockSchedulePrediction(
      Map<String, dynamic> features) {
    final predictions = <SchedulePrediction>[];

    // Example: Predict common usage patterns
    final hourlyActivity =
        features['hourlyActivity'] as Map<int, Map<int, List<SensorData>>>;

    for (var day = 1; day <= 7; day++) {
      if (!hourlyActivity.containsKey(day)) continue;

      for (var hour = 0; hour < 24; hour++) {
        final logs = hourlyActivity[day]?[hour] ?? [];
        if (logs.isEmpty) continue;

        // Calculate frequency
        final frequency = logs.length / 90.0; // Over 90 days
        final confidence = (frequency * 100).clamp(0, 100);

        if (confidence >= 30) {
          // Suggest schedule if used frequently
          final avgFanSpeed =
              _calculateAverage(logs.map((l) => l.fanSpeed.toDouble()));
          final avgLedBrightness =
              _calculateAverage(logs.map((l) => l.ledBrightness.toDouble()));

          predictions.add(SchedulePrediction(
            dayOfWeek: day,
            hour: hour,
            minute: 0,
            deviceType: avgFanSpeed > 50 ? 'fan' : 'led',
            value: avgFanSpeed > 50
                ? avgFanSpeed.round()
                : avgLedBrightness.round(),
            confidence: confidence.toDouble(),
            reason: 'You frequently use this device at this time',
          ));
        }
      }
    }

    // Sort by confidence
    predictions.sort((a, b) => b.confidence.compareTo(a.confidence));

    return predictions.take(10).toList();
  }

  /// Mock anomaly detection (replace with actual TFLite inference)
  AnomalyReport _mockAnomalyDetection(Map<String, dynamic> features) {
    final anomalies = <Anomaly>[];

    // Check for inactivity
    final lastActivity = features['lastActivity'] as DateTime?;
    if (lastActivity != null) {
      final hoursSinceActivity =
          DateTime.now().difference(lastActivity).inHours;
      if (hoursSinceActivity > 12) {
        anomalies.add(Anomaly(
          type: AnomalyType.inactivity,
          severity: hoursSinceActivity > 24 ? 'high' : 'medium',
          message: 'No activity detected for $hoursSinceActivity hours',
          timestamp: DateTime.now(),
          confidence: 0.95,
        ));
      }
    }

    // Check for unusual night activity
    final nightActivity = features['nightActivity'] as int;
    if (nightActivity > 5) {
      anomalies.add(Anomaly(
        type: AnomalyType.unusualActivity,
        severity: 'medium',
        message: 'Unusual nighttime activity detected ($nightActivity events)',
        timestamp: DateTime.now(),
        confidence: 0.85,
      ));
    }

    // Check for temperature extremes
    final avgTemp = features['avgTemperature'] as double;
    if (avgTemp < 18 || avgTemp > 32) {
      anomalies.add(Anomaly(
        type: AnomalyType.temperatureExtreme,
        severity: avgTemp < 15 || avgTemp > 35 ? 'high' : 'medium',
        message:
            'Temperature outside comfort range: ${avgTemp.toStringAsFixed(1)}°C',
        timestamp: DateTime.now(),
        confidence: 0.90,
      ));
    }

    return AnomalyReport(
      timestamp: DateTime.now(),
      anomalies: anomalies,
      overallScore: anomalies.isEmpty
          ? 0.0
          : anomalies.map((a) => a.confidence).reduce((a, b) => a + b) /
              anomalies.length,
    );
  }

  /// Helper: Calculate average
  double _calculateAverage(Iterable<double> values) {
    if (values.isEmpty) return 0;
    return values.reduce((a, b) => a + b) / values.length;
  }

  /// Helper: Calculate standard deviation
  double _calculateStdDev(Iterable<double> values) {
    if (values.isEmpty) return 0;
    final mean = _calculateAverage(values);
    final variance =
        values.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b) /
            values.length;
    return variance.sqrt();
  }

  /// Helper: Count night activity (22:00 - 06:00)
  int _countNightActivity(List<SensorData> logs) {
    return logs.where((log) {
      final hour = log.timestamp.hour;
      return (hour >= 22 || hour < 6) && log.motionDetected;
    }).length;
  }

  /// Get analytics insights
  Future<AnalyticsInsights> getInsights(String userId, int days) async {
    final logs = await _fetchHistoricalLogs(userId, '', days);

    return AnalyticsInsights(
      totalLogs: logs.length,
      avgTemperature: _calculateAverage(logs.map((l) => l.temperature)),
      avgHumidity: _calculateAverage(logs.map((l) => l.humidity)),
      motionEvents: logs.where((l) => l.motionDetected).length,
      avgFanUsage: _calculateAverage(logs.map((l) => l.fanSpeed.toDouble())),
      avgLightUsage:
          _calculateAverage(logs.map((l) => l.ledBrightness.toDouble())),
      peakUsageHour: _findPeakUsageHour(logs),
      energyConsumption: _estimateEnergyConsumption(logs),
    );
  }

  int _findPeakUsageHour(List<SensorData> logs) {
    final hourCounts = <int, int>{};
    for (var log in logs) {
      hourCounts[log.timestamp.hour] =
          (hourCounts[log.timestamp.hour] ?? 0) + 1;
    }
    return hourCounts.entries.reduce((a, b) => a.value > b.value ? a : b).key;
  }

  double _estimateEnergyConsumption(List<SensorData> logs) {
    double total = 0;
    for (var log in logs) {
      // Simplified energy calculation
      total += (log.fanSpeed / 255.0) * 0.05; // Fan: 50W max
      total += (log.ledBrightness / 255.0) * 0.01; // LED: 10W max
    }
    return total;
  }

  void dispose() {
    // Close interpreters
    // _scheduleInterpreter.close();
    // _anomalyInterpreter.close();
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

// Add sqrt extension for double
extension on double {
  double sqrt() => this >= 0 ? this.sign * (this.abs()).toDouble() : double.nan;
}
