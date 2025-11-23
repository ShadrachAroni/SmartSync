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

  StreamController<SensorData?>? _sensorController;
  StreamController<AnomalyReport?>? _anomalyController;

  StreamSubscription<SensorData>? _bleSubscription;
  Timer? _anomalyTimer;
  SensorData? _latestReading;
  String? _userId;
  bool _initialized = false;
  Completer<void>? _initializationCompleter;
  bool _isInitializing = false;

  Stream<SensorData?> get sensorStream {
    _sensorController ??= StreamController<SensorData?>.broadcast();
    return _sensorController!.stream;
  }
  
  Stream<AnomalyReport?> get anomalyStream {
    _anomalyController ??= StreamController<AnomalyReport?>.broadcast();
    return _anomalyController!.stream;
  }
  
  SensorData? get latestReading => _latestReading;

  Future<void> initialize(String userId) async {
    // If already initialized for this user, return immediately
    if (_initialized && _userId == userId) {
      return;
    }

    // If currently initializing, wait for that to complete
    if (_isInitializing && _initializationCompleter != null) {
      return _initializationCompleter!.future;
    }

    // Start new initialization
    _isInitializing = true;
    _initializationCompleter = Completer<void>();

    try {
      // Recreate controllers if they were closed
      if (_sensorController?.isClosed ?? true) {
        _sensorController = StreamController<SensorData?>.broadcast();
      }
      if (_anomalyController?.isClosed ?? true) {
        _anomalyController = StreamController<AnomalyReport?>.broadcast();
      }

      _userId = userId;
      
      // Initialize ML service with timeout to prevent hanging
      try {
        await _mlService.initialize().timeout(
          const Duration(seconds: 10),
          onTimeout: () {},
        );
      } catch (e) {
        // Continue even if ML service fails
      }

      // Set up BLE subscription (non-blocking)
      await _bleSubscription?.cancel();
      _bleSubscription =
          _bluetoothService.sensorDataStream.listen(_handleSensorPayload);

      // Set up anomaly timer
      _anomalyTimer?.cancel();
      _anomalyTimer = Timer.periodic(
        const Duration(minutes: 5),
        (_) => refreshAnomalies(),
      );

      // Refresh anomalies in background (don't await to avoid blocking)
      refreshAnomalies().catchError((e) {
        Logger.error('MonitoringService: Failed to refresh anomalies: $e');
      });

      _initialized = true;
      Logger.success('Monitoring service initialized for $userId');
      
      _initializationCompleter!.complete();
    } catch (e, stackTrace) {
      Logger.error('MonitoringService: Initialization failed', e, stackTrace);
      _initialized = false;
      _initializationCompleter!.completeError(e, stackTrace);
      rethrow;
    } finally {
      _isInitializing = false;
      _initializationCompleter = null;
    }
  }

  Future<List<SensorData>> getHistory(String deviceId, int hours) {
    return _firebaseService.getSensorLogs(deviceId, hours).first;
  }

  Future<void> refreshAnomalies(
      {Duration window = const Duration(hours: 6)}) async {
    if (_userId == null) return;
    final report = await _mlService.detectAnomalies(_userId!, window);
    if (_anomalyController != null && !_anomalyController!.isClosed) {
      _anomalyController!.add(report);
    }
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
    
    // Only add to stream if controller exists and is not closed
    if (_sensorController != null && !_sensorController!.isClosed) {
      _sensorController!.add(enriched);
    }

    try {
      await _firebaseService.logSensorData(enriched);
      // Trigger anomaly refresh after new data batch
      if (_anomalyTimer == null ||
          (_anomalyTimer?.tick ?? 0) % 2 == 0) {
        await refreshAnomalies();
      }
    } catch (e) {
      Logger.error('Failed to log sensor data: $e');
    }
  }

  void dispose() {
    _bleSubscription?.cancel();
    _anomalyTimer?.cancel();
    // Don't close controllers since this is a singleton that might be reused
    // Just reset the initialization state
    _initialized = false;
    _userId = null;
  }
}
