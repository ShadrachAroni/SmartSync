import 'dart:async';

import '../models/sensor_data.dart';
import '../models/ml_prediction.dart';
import '../core/utils/logger.dart';
import 'bluetooth_service.dart';
import 'firebase_service.dart';
import 'ml_service.dart';

class MonitoringService {
  MonitoringService._internal();
  static final MonitoringService _instance = MonitoringService._internal();
  factory MonitoringService() => _instance;

  final BluetoothService _bluetoothService = BluetoothService();
  final FirebaseService _firebaseService = FirebaseService();
  final MLService _mlService = MLService();

  final StreamController<SensorData> _sensorController =
      StreamController<SensorData>.broadcast();
  final StreamController<AnomalyReport?> _anomalyController =
      StreamController<AnomalyReport?>.broadcast();

  StreamSubscription<SensorData>? _bleSubscription;
  SensorData? _latestReading;
  String? _userId;
  bool _initialized = false;

  Stream<SensorData> get sensorStream => _sensorController.stream;
  Stream<AnomalyReport?> get anomalyStream => _anomalyController.stream;
  SensorData? get latestReading => _latestReading;

  Future<void> initialize(String userId) async {
    if (_initialized && _userId == userId) return;

    _userId = userId;
    await _mlService.initialize();

    await _bleSubscription?.cancel();
    _bleSubscription =
        _bluetoothService.sensorDataStream.listen(_handleSensorPayload);

    _initialized = true;
    Logger.success('Monitoring service initialized for $userId');
  }

  Future<List<SensorData>> getHistory(String deviceId, int hours) {
    return _firebaseService.getSensorLogs(deviceId, hours).first;
  }

  Future<void> refreshAnomalies(
      {Duration window = const Duration(hours: 6)}) async {
    if (_userId == null) return;
    final report = await _mlService.detectAnomalies(_userId!, window);
    _anomalyController.add(report);
  }

  Future<void> _handleSensorPayload(SensorData raw) async {
    if (_userId == null) return;

    final enriched = SensorData(
      deviceId: raw.deviceId,
      userId: _userId!,
      temperature: raw.temperature,
      humidity: raw.humidity,
      fanSpeed: raw.fanSpeed,
      ledBrightness: raw.ledBrightness,
      motionDetected: raw.motionDetected,
      distance: raw.distance,
      securityEnabled: raw.securityEnabled,
      timestamp: DateTime.now(),
    );

    _latestReading = enriched;
    _sensorController.add(enriched);

    try {
      await _firebaseService.logSensorData(enriched);
    } catch (e) {
      Logger.error('Failed to log sensor data: $e');
    }
  }

  void dispose() {
    _bleSubscription?.cancel();
    _sensorController.close();
    _anomalyController.close();
    _initialized = false;
  }
}
