import 'dart:async';
import 'dart:convert';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as flutter_blue;
import 'package:firebase_auth/firebase_auth.dart';
import '../models/sensor_data.dart';
import '../models/schedule_model.dart';
import '../models/log_entry.dart';
import '../core/constants/ble_constants.dart';
import '../core/utils/logger.dart';
import 'appliance_state_service.dart';
import 'firebase_service.dart';
import 'monitoring_service.dart';
import 'notification_service.dart';
import 'logging_service.dart';

class BluetoothService {
  static final BluetoothService _instance = BluetoothService._internal();
  factory BluetoothService() => _instance;

  flutter_blue.BluetoothDevice? _connectedDevice;
  flutter_blue.BluetoothCharacteristic? _rxCharacteristic;
  flutter_blue.BluetoothCharacteristic? _txCharacteristic;

  final StreamController<SensorData> _sensorDataController =
      StreamController<SensorData>.broadcast();
  final StreamController<bool> _connectionController =
      StreamController<bool>.broadcast();
  final StreamController<String> _statusMessageController =
      StreamController<String>.broadcast();

  Stream<SensorData> get sensorDataStream => _sensorDataController.stream;
  Stream<bool> get connectionStream => _connectionController.stream;
  Stream<String> get statusMessages => _statusMessageController.stream;
  bool get isConnected => _connectedDevice != null;
  String? get connectedDeviceId => _connectedDevice?.remoteId.toString();

  BluetoothService._internal() {
    // Emit initial connection state (disconnected)
    _connectionController.add(false);
  }

  /// Get the first sensor data reading (useful for device type detection)
  /// Returns null if no data is received within the timeout
  Future<SensorData?> getFirstSensorData({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    try {
      return await sensorDataStream.timeout(timeout).first;
    } catch (e) {
      Logger.warning('BluetoothService: Could not get first sensor data: $e');
      return null;
    }
  }

  // Scan for devices
  Future<List<flutter_blue.BluetoothDevice>> scanForDevices({
    Duration timeout = const Duration(seconds: 15),
  }) async {
    Logger.info('Starting BLE scan...');
    _emitStatus('Scan started. Ensuring Bluetooth is ready...');
    List<flutter_blue.BluetoothDevice> devices = [];

    try {
      await _ensureBluetoothReady();

      // Start scanning
      await flutter_blue.FlutterBluePlus.startScan(
        timeout: timeout,
        androidUsesFineLocation: false,
      );

      // Listen to scan results
      final subscription =
          flutter_blue.FlutterBluePlus.scanResults.listen((results) {
        for (flutter_blue.ScanResult result in results) {
          if (result.device.advName.startsWith(BLEConstants.deviceNamePrefix)) {
            if (!devices.contains(result.device)) {
              devices.add(result.device);
              Logger.info('Found device: ${result.device.advName}');
            }
          }
        }
      });

      // Wait for scan to complete
      await Future.delayed(timeout);
      await subscription.cancel();
      await flutter_blue.FlutterBluePlus.stopScan();

      Logger.info('Scan complete. Found ${devices.length} devices');
      _emitStatus('Scan finished. Found ${devices.length} device(s).');
      return devices;
    } catch (e) {
      Logger.error('Scan error: $e');
      _emitStatus('Scan failed: $e');
      await flutter_blue.FlutterBluePlus.stopScan();
      rethrow;
    }
  }

  // Connect to device
  Future<bool> connectToDevice(flutter_blue.BluetoothDevice device) async {
    try {
      await _ensureBluetoothReady();
      Logger.info('Connecting to ${device.advName}...');
      _emitStatus('Connecting to ${device.advName}...');

      await device.connect(
        license: flutter_blue.License.free,
        timeout: BLEConstants.bleConnectionTimeout,
        autoConnect: false,
      );

      _connectedDevice = device;
      _connectionController.add(true);

      // Discover services
      List<flutter_blue.BluetoothService> services =
          await device.discoverServices();

      // Find SmartSync service
      for (var service in services) {
        if (service.uuid.toString() == BLEConstants.serviceUUID) {
          Logger.info('Found SmartSync service');

          for (var characteristic in service.characteristics) {
            if (characteristic.uuid.toString() ==
                BLEConstants.rxCharacteristicUUID) {
              _rxCharacteristic = characteristic;
              Logger.info('Found RX characteristic');
            }
            if (characteristic.uuid.toString() ==
                BLEConstants.txCharacteristicUUID) {
              _txCharacteristic = characteristic;
              Logger.info('Found TX characteristic');

              // Subscribe to notifications
              await _txCharacteristic!.setNotifyValue(true);
              _txCharacteristic!.value.listen(_handleIncomingData);
            }
          }
          break;
        }
      }

      if (_rxCharacteristic == null || _txCharacteristic == null) {
        throw Exception('SmartSync characteristics not found');
      }

      Logger.success('Connected successfully');
      _emitStatus('Connected to ${device.advName}');

      // Send connection notification
      try {
        final notificationService = NotificationService();
        await notificationService.showLocalNotification(
          id: DateTime.now().millisecondsSinceEpoch % 2147483647,
          title: '✅ Device Connected',
          body: 'Successfully connected to ${device.advName}',
          payload: jsonEncode({
            'type': 'device_connection',
            'status': 'connected',
            'deviceId': device.remoteId.toString(),
          }),
        );
      } catch (e) {
        Logger.warning('Failed to send connection notification: $e');
      }

      // Initialize MonitoringService to ensure data collection and storage
      // This ensures sensor data is stored even if sensorStreamProvider isn't being watched
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        try {
          final monitoringService = MonitoringService();
          await monitoringService.initialize(user.uid);
          Logger.info('BluetoothService: MonitoringService initialized for data collection');
        } catch (e) {
          Logger.warning('BluetoothService: Failed to initialize MonitoringService: $e');
          // Continue anyway - data collection will work if sensorStreamProvider is watched
        }
      }

      // Restore appliance state and sync schedules after connection is established
      await _restoreApplianceState();
      await _syncSchedulesToDevice();

      return true;
    } catch (e) {
      Logger.error('Connection failed: $e');
      _emitStatus('Connection failed: $e');
      await disconnect();
      return false;
    }
  }

  // Disconnect from device
  Future<void> disconnect() async {
    try {
      final deviceName = _connectedDevice?.advName ?? 'Device';
      if (_connectedDevice != null) {
        await _connectedDevice!.disconnect();
        _connectedDevice = null;
        _rxCharacteristic = null;
        _txCharacteristic = null;
        _connectionController.add(false);
        Logger.info('Disconnected');
        _emitStatus('Connection closed');
        
        // Send disconnection notification
        try {
          final notificationService = NotificationService();
          await notificationService.showLocalNotification(
            id: (DateTime.now().millisecondsSinceEpoch + 2) % 2147483647,
            title: '⚠️ Device Disconnected',
            body: 'Lost connection to $deviceName',
            payload: jsonEncode({
              'type': 'device_connection',
              'status': 'disconnected',
            }),
          );
        } catch (e) {
          Logger.warning('Failed to send disconnection notification: $e');
        }
      }
    } catch (e) {
      Logger.error('Disconnect error: $e');
    }
  }

  // Handle incoming data
  void _handleIncomingData(List<int> data) {
    try {
      String jsonString = utf8.decode(data);
      Logger.debug('Received: $jsonString');

      Map<String, dynamic> json = jsonDecode(jsonString);

      if (json['type'] == 'sensor_data') {
        SensorData sensorData = SensorData(
          deviceId: _connectedDevice?.remoteId.toString() ?? '',
          userId: '', // Will be set from auth
          temperature: (json['temperature'] as num).toDouble(),
          humidity: (json['humidity'] as num).toDouble(),
          fanSpeed: json['fan_speed'] as int,
          ledBrightness: json['led_brightness'] as int,
          motionDetected: json['motion'] as bool,
          distance: (json['distance'] as num).toDouble(),
          securityEnabled: json['security_enabled'] as bool? ?? true,
          timestamp: DateTime.now(),
        );

        _sensorDataController.add(sensorData);
      }
    } catch (e) {
      Logger.error('Data parsing error: $e');
    }
  }

  // Send command
  Future<bool> sendCommand(String cmd, dynamic value) async {
    if (_rxCharacteristic == null) {
      Logger.error('Not connected to device');
      return false;
    }

    try {
      Map<String, dynamic> command = {
        'cmd': cmd,
        'value': value,
      };

      String jsonString = jsonEncode(command);
      List<int> bytes = utf8.encode(jsonString);

      await _rxCharacteristic!.write(bytes, withoutResponse: false);
      Logger.debug('Sent command: $jsonString');

      return true;
    } catch (e) {
      Logger.error('Send command error: $e');
      return false;
    }
  }

  // Control methods
  Future<bool> setFanSpeed(int speed) async {
    int value = ((speed / 100) * 255).round().clamp(0, 255);
    
    // Get previous state for logging
    final stateService = ApplianceStateService();
    final currentState = await stateService.loadApplianceState();
    final previousSpeed = currentState?['fanSpeed'] ?? 0;
    final previousSpeedPercent = ((previousSpeed / 255) * 100).round();
    
    final success = await sendCommand(BLEConstants.cmdSetFan, value);
    if (success) {
      // Save state to Firebase
      await stateService.saveApplianceState(
        fanSpeed: value,
        ledBrightness: currentState?['ledBrightness'] ?? 0,
        securityEnabled: currentState?['securityEnabled'] ?? false,
        autoMode: currentState?['autoMode'],
      );
      
      // Log detailed action
      final loggingService = LoggingService();
      await loggingService.logAction(
        action: 'Fan Speed Changed',
        category: 'device_control',
        details: 'Fan speed changed from $previousSpeedPercent% to $speed% (raw: $previousSpeed → $value)',
        metadata: {
          'deviceType': 'fan',
          'previousSpeed': previousSpeed,
          'previousSpeedPercent': previousSpeedPercent,
          'newSpeed': value,
          'newSpeedPercent': speed,
          'rawValue': value,
          'percentageValue': speed,
          'bleConnected': isConnected,
          'deviceId': connectedDeviceId,
          'actionType': 'fan_speed_change',
          'timestamp': DateTime.now().toIso8601String(),
        },
        level: LogLevel.info,
      );
      
      // Send notification for manual device change
      try {
        final notificationService = NotificationService();
        await notificationService.showLocalNotification(
          id: DateTime.now().millisecondsSinceEpoch % 2147483647,
          title: '🔧 Device Updated',
          body: 'Fan speed set to ${speed}%',
          payload: jsonEncode({
            'type': 'device_change',
            'device': 'fan',
            'value': speed,
          }),
        );
      } catch (e) {
        Logger.warning('Failed to send notification: $e');
      }
    }
    return success;
  }

  Future<bool> setLEDBrightness(int brightness) async {
    int value = ((brightness / 100) * 255).round().clamp(0, 255);
    
    // Get previous state for logging
    final stateService = ApplianceStateService();
    final currentState = await stateService.loadApplianceState();
    final previousBrightness = currentState?['ledBrightness'] ?? 0;
    final previousBrightnessPercent = ((previousBrightness / 255) * 100).round();
    
    final success = await sendCommand(BLEConstants.cmdSetLED, value);
    if (success) {
      // Save state to Firebase
      await stateService.saveApplianceState(
        fanSpeed: currentState?['fanSpeed'] ?? 0,
        ledBrightness: value,
        securityEnabled: currentState?['securityEnabled'] ?? false,
        autoMode: currentState?['autoMode'],
      );
      
      // Log detailed action
      final loggingService = LoggingService();
      await loggingService.logAction(
        action: 'LED Brightness Changed',
        category: 'device_control',
        details: 'LED brightness changed from $previousBrightnessPercent% to $brightness% (raw: $previousBrightness → $value)',
        metadata: {
          'deviceType': 'light',
          'previousBrightness': previousBrightness,
          'previousBrightnessPercent': previousBrightnessPercent,
          'newBrightness': value,
          'newBrightnessPercent': brightness,
          'rawValue': value,
          'percentageValue': brightness,
          'bleConnected': isConnected,
          'deviceId': connectedDeviceId,
          'actionType': 'led_brightness_change',
          'timestamp': DateTime.now().toIso8601String(),
        },
        level: LogLevel.info,
      );
      
      // Send notification for manual device change
      try {
        final notificationService = NotificationService();
        await notificationService.showLocalNotification(
          id: (DateTime.now().millisecondsSinceEpoch + 1) % 2147483647,
          title: '💡 Device Updated',
          body: 'LED brightness set to ${brightness}%',
          payload: jsonEncode({
            'type': 'device_change',
            'device': 'led',
            'value': brightness,
          }),
        );
      } catch (e) {
        Logger.warning('Failed to send notification: $e');
      }
    }
    return success;
  }

  Future<bool> setAutoMode(bool enabled) async {
    // Get previous state for logging
    final stateService = ApplianceStateService();
    final currentState = await stateService.loadApplianceState();
    final previousAutoMode = currentState?['autoMode'] ?? false;
    
    final success = await sendCommand(BLEConstants.cmdSetAutoMode, enabled);
    if (success) {
      // Save state to Firebase
      await stateService.saveApplianceState(
        fanSpeed: currentState?['fanSpeed'] ?? 0,
        ledBrightness: currentState?['ledBrightness'] ?? 0,
        securityEnabled: currentState?['securityEnabled'] ?? false,
        autoMode: enabled,
      );
      
      // Log detailed action
      final loggingService = LoggingService();
      await loggingService.logAction(
        action: enabled ? 'Auto Mode ENABLED' : 'Auto Mode DISABLED',
        category: 'settings',
        details: 'Auto Mode ${enabled ? "enabled" : "disabled"} (previous state: ${previousAutoMode ? "enabled" : "disabled"})',
        metadata: {
          'feature': 'auto_mode',
          'previousState': previousAutoMode,
          'newState': enabled,
          'bleConnected': isConnected,
          'deviceId': connectedDeviceId,
          'actionType': 'auto_mode_toggle',
          'timestamp': DateTime.now().toIso8601String(),
        },
        level: LogLevel.info,
      );
    }
    return success;
  }

  Future<bool> setSecurityEnabled(bool enabled) async {
    // Get previous state for logging
    final stateService = ApplianceStateService();
    final currentState = await stateService.loadApplianceState();
    final previousSecurityState = currentState?['securityEnabled'] ?? false;
    
    final payload = {'enabled': enabled};
    final success = await sendCommand(BLEConstants.cmdSetSecurity, payload);
    if (success) {
      // Save state to Firebase
      await stateService.saveApplianceState(
        fanSpeed: currentState?['fanSpeed'] ?? 0,
        ledBrightness: currentState?['ledBrightness'] ?? 0,
        securityEnabled: enabled,
        autoMode: currentState?['autoMode'],
      );
      
      // Log detailed action
      final loggingService = LoggingService();
      await loggingService.logAction(
        action: enabled ? 'Security System ARMED' : 'Security System DISARMED',
        category: 'security',
        details: 'Security system ${enabled ? "armed" : "disarmed"} (previous state: ${previousSecurityState ? "armed" : "disarmed"})',
        metadata: {
          'feature': 'security_system',
          'previousState': previousSecurityState,
          'newState': enabled,
          'bleConnected': isConnected,
          'deviceId': connectedDeviceId,
          'actionType': 'security_toggle',
          'timestamp': DateTime.now().toIso8601String(),
        },
        level: LogLevel.info,
      );
    }
    return success;
  }

  Future<bool> triggerSecurityAlarm({int durationMs = 5000}) async {
    final payload = {'duration': durationMs};
    return await sendCommand(BLEConstants.cmdSOS, payload);
  }

  Future<bool> requestStatus() async {
    return await sendCommand(BLEConstants.cmdGetStatus, null);
  }

  // Schedule synchronization methods
  /// Add a schedule to the device
  Future<bool> addScheduleToDevice(ScheduleModel schedule) async {
    if (!isConnected) {
      Logger.warning('BluetoothService: Cannot add schedule - not connected');
      return false;
    }

    try {
      // Convert Firebase document ID to uint8_t (0-255)
      // Use hash of ID to get consistent value
      int scheduleId = schedule.id.hashCode.abs() % 255;
      if (scheduleId == 0) scheduleId = 1; // Ensure non-zero ID

      final payload = {
        'id': scheduleId,
        'hour': schedule.hour,
        'minute': schedule.minute,
        'fan': ((schedule.fanSpeed / 100) * 255).round().clamp(0, 255),
        'led': ((schedule.brightness / 100) * 255).round().clamp(0, 255),
        'enabled': schedule.enabled,
        'repeat': schedule.repeatDaily,
      };

      final success = await sendCommand(BLEConstants.cmdAddSchedule, payload);
      if (success) {
        Logger.info('BluetoothService: Schedule added to device - ID: $scheduleId, Time: ${schedule.hour}:${schedule.minute}');
      } else {
        Logger.error('BluetoothService: Failed to add schedule to device');
      }
      return success;
    } catch (e) {
      Logger.error('BluetoothService: Error adding schedule to device: $e');
      return false;
    }
  }

  /// Delete a schedule from the device
  Future<bool> deleteScheduleFromDevice(ScheduleModel schedule) async {
    if (!isConnected) {
      Logger.warning('BluetoothService: Cannot delete schedule - not connected');
      return false;
    }

    try {
      // Convert Firebase document ID to uint8_t (0-255)
      int scheduleId = schedule.id.hashCode.abs() % 255;
      if (scheduleId == 0) scheduleId = 1; // Ensure non-zero ID

      final payload = {'id': scheduleId};
      final success = await sendCommand(BLEConstants.cmdDeleteSchedule, payload);
      if (success) {
        Logger.info('BluetoothService: Schedule deleted from device - ID: $scheduleId');
      } else {
        Logger.error('BluetoothService: Failed to delete schedule from device');
      }
      return success;
    } catch (e) {
      Logger.error('BluetoothService: Error deleting schedule from device: $e');
      return false;
    }
  }

  /// Sync all schedules for the connected device from Firebase
  Future<void> _syncSchedulesToDevice() async {
    if (!isConnected) {
      Logger.warning('BluetoothService: Cannot sync schedules - not connected');
      return;
    }

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        Logger.warning('BluetoothService: No user, cannot sync schedules');
        return;
      }

      final deviceId = connectedDeviceId ?? '';
      if (deviceId.isEmpty) {
        Logger.warning('BluetoothService: No device ID, cannot sync schedules');
        return;
      }

      Logger.info('BluetoothService: Syncing schedules to device...');
      _emitStatus('Syncing schedules to device...');

      final firebaseService = FirebaseService();
      final schedules = await firebaseService
          .getSchedules(user.uid, deviceId: deviceId)
          .first
          .timeout(const Duration(seconds: 5));

      int syncedCount = 0;
      for (final schedule in schedules) {
        // Only sync schedules for this specific device
        if (schedule.deviceId == deviceId) {
          final success = await addScheduleToDevice(schedule).timeout(
            const Duration(seconds: 2),
            onTimeout: () => false,
          );
          if (success) {
            syncedCount++;
            // Small delay between schedule sends to avoid overwhelming the device
            await Future.delayed(const Duration(milliseconds: 200));
          }
        }
      }

      Logger.success('BluetoothService: Synced $syncedCount schedule(s) to device');
      _emitStatus('Synced $syncedCount schedule(s) to device');
    } catch (e) {
      Logger.error('BluetoothService: Error syncing schedules to device: $e');
      _emitStatus('Schedule sync failed: $e');
    }
  }

  /// Sync a single schedule (for real-time updates)
  Future<bool> syncScheduleToDevice(ScheduleModel schedule) async {
    return await addScheduleToDevice(schedule);
  }

  // Restore appliance state from Firebase
  Future<void> _restoreApplianceState() async {
    try {
      final stateService = ApplianceStateService();
      final state = await stateService.loadApplianceState();
      
      if (state != null && isConnected) {
        Logger.info('BluetoothService: Restoring appliance state from Firebase');
        final fanSpeed = state['fanSpeed'] as int? ?? 0;
        final ledBrightness = state['ledBrightness'] as int? ?? 0;
        final securityEnabled = state['securityEnabled'] as bool? ?? false;
        final autoMode = state['autoMode'] as bool? ?? false;
        
        // Restore fan speed
        if (fanSpeed > 0) {
          await setFanSpeed(fanSpeed).timeout(
            const Duration(seconds: 3),
            onTimeout: () => false,
          );
        }
        
        // Restore LED brightness
        if (ledBrightness > 0) {
          await setLEDBrightness(ledBrightness).timeout(
            const Duration(seconds: 3),
            onTimeout: () => false,
          );
        }
        
        // Restore security state
        await setSecurityEnabled(securityEnabled).timeout(
          const Duration(seconds: 3),
          onTimeout: () => false,
        );
        
        // Restore auto mode
        await setAutoMode(autoMode).timeout(
          const Duration(seconds: 3),
          onTimeout: () => false,
        );
        
        Logger.info('BluetoothService: Appliance state restored - Fan: $fanSpeed, LED: $ledBrightness, Security: $securityEnabled, AutoMode: $autoMode');
      }
    } catch (e) {
      Logger.error('BluetoothService: Error restoring state: $e');
    }
  }

  // Cleanup
  void dispose() {
    _sensorDataController.close();
    _connectionController.close();
    _statusMessageController.close();
  }

  Future<void> _ensureBluetoothReady() async {
    if (await flutter_blue.FlutterBluePlus.isSupported == false) {
      throw Exception('Bluetooth not supported on this device');
    }

    final adapterState =
        await flutter_blue.FlutterBluePlus.adapterState.first;

    if (adapterState != flutter_blue.BluetoothAdapterState.on) {
      throw Exception(
        adapterState == flutter_blue.BluetoothAdapterState.off
            ? 'Bluetooth is turned off. Please enable it.'
            : 'Bluetooth is not ready ($adapterState).',
      );
    }
  }

  void _emitStatus(String message) {
    Logger.info(message);
    if (!_statusMessageController.isClosed) {
      _statusMessageController.add(message);
    }
  }
}
