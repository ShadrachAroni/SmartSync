import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/sensor_data.dart';
import '../models/device_model.dart';
import '../core/utils/logger.dart';
import '../core/widgets/app_notifications.dart';
import 'bluetooth_service.dart';
import 'ml_service.dart';
import 'firebase_service.dart';
import 'weather_service.dart';
import 'logging_service.dart';
import 'notification_service.dart';

/// AI-Powered Adaptive Auto Mode Service
/// 
/// Uses ML predictions and sensor data to intelligently adjust
/// fan speed and light brightness in real-time
class AdaptiveAutoService {
  static final AdaptiveAutoService _instance = AdaptiveAutoService._internal();
  factory AdaptiveAutoService() => _instance;
  AdaptiveAutoService._internal();

  final BluetoothService _bluetooth = BluetoothService();
  final MLService _mlService = MLService();
  final FirebaseService _firebase = FirebaseService();
  final WeatherService _weather = WeatherService();
  final LoggingService _logging = LoggingService();
  final NotificationService _notificationService = NotificationService();

  Timer? _autoModeTimer;
  StreamSubscription<SensorData>? _sensorSubscription;
  String? _userId;
  bool _isEnabled = false;
  bool _isRunning = false;
  
  // Latest sensor data cache
  SensorData? _latestSensorData;
  
  // Cache for ML predictions (update every 30 minutes)
  Map<String, int>? _cachedPredictions;
  DateTime? _lastPredictionUpdate;
  static const _predictionCacheDuration = Duration(minutes: 30);

  // Last applied values to avoid unnecessary updates
  int _lastFanSpeed = -1;
  int _lastLedBrightness = -1;
  
  // Track previous values for revert functionality
  final List<_AutomationChange> _changeHistory = [];
  static const _maxHistorySize = 50;
  
  /// Represents an automation change that can be reverted
  class _AutomationChange {
    final String deviceType; // 'fan' or 'light'
    final int previousValue;
    final int newValue;
    final DateTime timestamp;
    final String reason;
    final Map<String, dynamic> context;
    
    _AutomationChange({
      required this.deviceType,
      required this.previousValue,
      required this.newValue,
      required this.timestamp,
      required this.reason,
      required this.context,
    });
  }

  bool get isEnabled => _isEnabled;
  bool get isRunning => _isRunning;

  /// Enable/Disable adaptive auto mode
  Future<void> setEnabled(bool enabled) async {
    if (_isEnabled == enabled) return;

    _isEnabled = enabled;
    Logger.info('Adaptive Auto Mode: ${enabled ? "ENABLED" : "DISABLED"}');

    if (enabled) {
      await _start();
    } else {
      await _stop();
    }
  }

  /// Start adaptive auto mode
  Future<void> _start() async {
    if (_isRunning) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      Logger.warning('Adaptive Auto Mode: No user logged in');
      return;
    }

    _userId = user.uid;
    _isRunning = true;

    // Initialize ML service
    await _mlService.initialize();
    
    // Initialize notification service for automation notifications
    await _notificationService.initialize(user.uid);

    // Subscribe to sensor data stream
    _sensorSubscription?.cancel();
    _sensorSubscription = _bluetooth.sensorDataStream.listen(
      _onSensorData,
      onError: (error) {
        Logger.error('Adaptive Auto Mode: Sensor stream error: $error');
      },
    );

    // Start periodic updates (every 2 minutes)
    _autoModeTimer?.cancel();
    _autoModeTimer = Timer.periodic(
      const Duration(minutes: 2),
      (_) => _updateAdaptiveSettings(),
    );

    // Initial update
    await _updateAdaptiveSettings();

    Logger.success('Adaptive Auto Mode: Started');
  }

  /// Stop adaptive auto mode
  Future<void> _stop() async {
    if (!_isRunning) return;

    _isRunning = false;
    _autoModeTimer?.cancel();
    _autoModeTimer = null;
    _sensorSubscription?.cancel();
    _sensorSubscription = null;
    _cachedPredictions = null;
    _lastPredictionUpdate = null;
    _lastFanSpeed = -1;
    _lastLedBrightness = -1;

    Logger.info('Adaptive Auto Mode: Stopped');
  }

  /// Handle incoming sensor data
  Future<void> _onSensorData(SensorData data) async {
    if (!_isRunning || !_isEnabled) return;

    // Store latest sensor data
    _latestSensorData = data;

    // Update settings when significant changes occur
    final tempChange = _latestSensorData != null
        ? (data.temperature - _latestSensorData!.temperature).abs()
        : 999.0;
    final motionChange = data.motionDetected;

    if (tempChange > 2.0 || motionChange) {
      await _updateAdaptiveSettings(sensorData: data);
    }
  }

  /// Update adaptive settings using AI predictions
  Future<void> _updateAdaptiveSettings({SensorData? sensorData}) async {
    if (!_isRunning || !_isEnabled || !_bluetooth.isConnected) return;

    try {
      // Get current sensor data
      final currentData = sensorData ?? _getLatestSensorData();

      if (currentData == null) {
        Logger.warning('Adaptive Auto Mode: No sensor data available');
        return;
      }

      // Get or update ML predictions
      final predictions = await _getMLPredictions();

      // Calculate optimal settings using AI + sensor data
      final optimalSettings = _calculateOptimalSettings(
        currentData,
        predictions,
      );

      // Apply settings if different from current
      await _applySettings(optimalSettings);

    } catch (e) {
      Logger.error('Adaptive Auto Mode: Error updating settings: $e');
    }
  }

  /// Get latest sensor data from cache
  SensorData? _getLatestSensorData() {
    return _latestSensorData;
  }

  /// Get ML predictions (with caching)
  Future<Map<String, int>?> _getMLPredictions() async {
    // Check cache
    if (_cachedPredictions != null && 
        _lastPredictionUpdate != null &&
        DateTime.now().difference(_lastPredictionUpdate!) < _predictionCacheDuration) {
      return _cachedPredictions;
    }

    if (_userId == null) return null;

    try {
      // Get user devices
      final devices = await _firebase.fetchUserDevices(_userId!);
      if (devices.isEmpty) return null;

      // Find fan device
      final fanDevice = devices.firstWhere(
        (d) => d.type == DeviceType.fan,
        orElse: () => devices.first,
      );

      // Get ML schedule predictions
      final predictions = await _mlService.predictSchedules(
        _userId!,
        fanDevice.id,
      );

      if (predictions.isEmpty) {
        Logger.warning('Adaptive Auto Mode: No ML predictions available');
        return null;
      }

      // Use the most recent prediction
      final latest = predictions.first;
      _cachedPredictions = {
        'fanSpeed': latest.value,
        'ledBrightness': latest.value, // Simplified - could be separate
      };
      _lastPredictionUpdate = DateTime.now();

      Logger.info('Adaptive Auto Mode: Updated ML predictions');
      return _cachedPredictions;

    } catch (e) {
      Logger.error('Adaptive Auto Mode: Failed to get ML predictions: $e');
      return null;
    }
  }

  /// Calculate optimal settings using AI + sensor data
  Map<String, int> _calculateOptimalSettings(
    SensorData sensorData,
    Map<String, int>? mlPredictions,
  ) {
    // Base calculations on sensor data
    final temp = sensorData.temperature;
    final humidity = sensorData.humidity;
    final motion = sensorData.motionDetected;
    final hour = DateTime.now().hour;

    // Fan speed calculation (AI-enhanced)
    int fanSpeed = _calculateFanSpeed(
      temp: temp,
      humidity: humidity,
      mlPrediction: mlPredictions?['fanSpeed'],
      hour: hour,
    );

    // LED brightness calculation (AI-enhanced)
    int ledBrightness = _calculateLedBrightness(
      motion: motion,
      hour: hour,
      mlPrediction: mlPredictions?['ledBrightness'],
    );

    return {
      'fanSpeed': fanSpeed.clamp(0, 100),
      'ledBrightness': ledBrightness.clamp(0, 100),
    };
  }

  /// Calculate optimal fan speed using AI + temperature
  int _calculateFanSpeed({
    required double temp,
    required double humidity,
    int? mlPrediction,
    required int hour,
  }) {
    // Base temperature-based calculation
    double baseSpeed = 0.0;

    if (temp < 18.0) {
      baseSpeed = 0.0; // Too cold
    } else if (temp < 24.0) {
      baseSpeed = 30.0 + ((temp - 18.0) / 6.0) * 20.0; // 30-50%
    } else if (temp < 28.0) {
      baseSpeed = 50.0 + ((temp - 24.0) / 4.0) * 30.0; // 50-80%
    } else {
      baseSpeed = 80.0 + ((temp - 28.0) / 4.0) * 20.0; // 80-100%
    }

    // Humidity adjustment
    if (humidity > 70) {
      baseSpeed += 10.0; // Increase fan for high humidity
    } else if (humidity < 30) {
      baseSpeed -= 5.0; // Slight decrease for low humidity
    }

    // Time-of-day adjustment (less fan at night)
    if (hour >= 22 || hour < 6) {
      baseSpeed *= 0.7; // 30% reduction at night
    }

    // Blend with ML prediction if available (70% sensor, 30% ML)
    if (mlPrediction != null) {
      baseSpeed = (baseSpeed * 0.7) + (mlPrediction * 0.3);
    }

    return baseSpeed.round();
  }

  /// Calculate optimal LED brightness using AI + motion
  int _calculateLedBrightness({
    required bool motion,
    required int hour,
    int? mlPrediction,
  }) {
    // Base motion-based calculation
    double baseBrightness = motion ? 70.0 : 20.0;

    // Time-of-day adjustment
    if (hour >= 6 && hour < 8) {
      baseBrightness = motion ? 80.0 : 30.0; // Morning
    } else if (hour >= 8 && hour < 18) {
      baseBrightness = motion ? 90.0 : 40.0; // Daytime
    } else if (hour >= 18 && hour < 22) {
      baseBrightness = motion ? 75.0 : 25.0; // Evening
    } else {
      baseBrightness = motion ? 30.0 : 10.0; // Night (dim)
    }

    // Blend with ML prediction if available
    if (mlPrediction != null) {
      baseBrightness = (baseBrightness * 0.6) + (mlPrediction * 0.4);
    }

    return baseBrightness.round();
  }

  /// Apply optimal settings to device
  Future<void> _applySettings(Map<String, int> settings) async {
    if (!_bluetooth.isConnected) return;

    final fanSpeed = settings['fanSpeed']!;
    final ledBrightness = settings['ledBrightness']!;

    // Only update if values changed significantly (>5% difference)
    if ((_lastFanSpeed - fanSpeed).abs() < 5 &&
        (_lastLedBrightness - ledBrightness).abs() < 5) {
      return; // Skip if change is too small
    }

    try {
      // Convert percentage to 0-255 range
      final fanValue = ((fanSpeed / 100.0) * 255).round().clamp(0, 255);
      final ledValue = ((ledBrightness / 100.0) * 255).round().clamp(0, 255);

      await _bluetooth.setFanSpeed(fanValue).timeout(
        const Duration(seconds: 3),
        onTimeout: () => false,
      );

      await _bluetooth.setLEDBrightness(ledValue).timeout(
        const Duration(seconds: 3),
        onTimeout: () => false,
      );

      // Track changes for revert functionality
      if (_lastFanSpeed >= 0 && _lastFanSpeed != fanSpeed) {
        _trackChange(
          deviceType: 'fan',
          previousValue: _lastFanSpeed,
          newValue: fanSpeed,
          reason: 'AI adjusted based on temperature and usage patterns',
        );
      }
      
      if (_lastLedBrightness >= 0 && _lastLedBrightness != ledBrightness) {
        _trackChange(
          deviceType: 'light',
          previousValue: _lastLedBrightness,
          newValue: ledBrightness,
          reason: 'AI adjusted based on motion and time of day',
        );
      }

      _lastFanSpeed = fanSpeed;
      _lastLedBrightness = ledBrightness;

      Logger.info(
        'Adaptive Auto Mode: Applied settings (Fan: $fanSpeed%, LED: $ledBrightness%)',
      );

    } catch (e) {
      Logger.error('Adaptive Auto Mode: Failed to apply settings: $e');
    }
  }
  
  /// Track an automation change for logging and revert functionality
  Future<void> _trackChange({
    required String deviceType,
    required int previousValue,
    required int newValue,
    required String reason,
  }) async {
    final change = _AutomationChange(
      deviceType: deviceType,
      previousValue: previousValue,
      newValue: newValue,
      timestamp: DateTime.now(),
      reason: reason,
      context: {
        'temperature': _latestSensorData?.temperature ?? 0.0,
        'humidity': _latestSensorData?.humidity ?? 0.0,
        'motion': _latestSensorData?.motionDetected ?? false,
        'hour': DateTime.now().hour,
      },
    );
    
    // Add to history
    _changeHistory.insert(0, change);
    if (_changeHistory.length > _maxHistorySize) {
      _changeHistory.removeLast();
    }
    
    // Log to activity logs
    _logging.logAction(
      action: 'Automation Change',
      category: 'automation',
      details: '${deviceType.toUpperCase()}: ${previousValue}% → ${newValue}%',
      metadata: {
        'deviceType': deviceType,
        'previousValue': previousValue,
        'newValue': newValue,
        'reason': reason,
        'context': change.context,
        'revertable': true,
        'changeId': change.timestamp.millisecondsSinceEpoch.toString(),
      },
      level: LogLevel.info,
    );
    
    // Send notification
    await _sendAutomationNotification(change);
  }
  
  /// Send notification for automation change
  Future<void> _sendAutomationNotification(_AutomationChange change) async {
    try {
      final changeId = change.timestamp.millisecondsSinceEpoch.toString();
      
      // Show local notification
      await _notificationService.showAutomationNotification(
        deviceType: change.deviceType,
        previousValue: change.previousValue,
        newValue: change.newValue,
        reason: change.reason,
        changeId: changeId,
      );
      
      Logger.info(
        '🔔 Automation Notification sent: ${change.deviceType} ${change.previousValue}% → ${change.newValue}%',
      );
    } catch (e) {
      Logger.error('Failed to send automation notification: $e');
    }
  }
  
  /// Revert a specific automation change
  Future<bool> revertChange(String changeId) async {
    try {
      final change = _changeHistory.firstWhere(
        (c) => c.timestamp.millisecondsSinceEpoch.toString() == changeId,
        orElse: () => throw StateError('Change not found'),
      );
      
      if (!_bluetooth.isConnected) {
        Logger.warning('Cannot revert: Bluetooth not connected');
        return false;
      }
      
      // Revert the change
      final revertValue = change.previousValue;
      final revertValue255 = ((revertValue / 100.0) * 255).round().clamp(0, 255);
      
      if (change.deviceType == 'fan') {
        await _bluetooth.setFanSpeed(revertValue255);
        _lastFanSpeed = revertValue;
      } else {
        await _bluetooth.setLEDBrightness(revertValue255);
        _lastLedBrightness = revertValue;
      }
      
      // Log the revert
      _logging.logAction(
        action: 'Reverted Automation Change',
        category: 'automation',
        details: '${change.deviceType.toUpperCase()}: ${change.newValue}% → ${change.previousValue}% (reverted)',
        metadata: {
          'originalChangeId': changeId,
          'deviceType': change.deviceType,
          'revertedFrom': change.newValue,
          'revertedTo': change.previousValue,
        },
        level: LogLevel.info,
      );
      
      Logger.success('✅ Reverted automation change: ${change.deviceType} to ${revertValue}%');
      return true;
    } catch (e) {
      Logger.error('Failed to revert change: $e');
      return false;
    }
  }
  
  /// Get recent automation changes (for UI display)
  List<Map<String, dynamic>> getRecentChanges({int limit = 10}) {
    return _changeHistory.take(limit).map((change) => {
      'changeId': change.timestamp.millisecondsSinceEpoch.toString(),
      'deviceType': change.deviceType,
      'previousValue': change.previousValue,
      'newValue': change.newValue,
      'timestamp': change.timestamp,
      'reason': change.reason,
      'context': change.context,
    }).toList();
  }

  /// Dispose resources
  void dispose() {
    _stop();
  }
}

