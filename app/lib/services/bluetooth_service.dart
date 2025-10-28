import 'dart:async';
import 'dart:convert';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as flutter_blue;
import '../models/sensor_data.dart';
import '../core/constants/ble_constants.dart';
import '../core/utils/logger.dart';

class BluetoothService {
  static final BluetoothService _instance = BluetoothService._internal();
  factory BluetoothService() => _instance;
  BluetoothService._internal();

  flutter_blue.BluetoothDevice? _connectedDevice;
  flutter_blue.BluetoothCharacteristic? _rxCharacteristic;
  flutter_blue.BluetoothCharacteristic? _txCharacteristic;

  final StreamController<SensorData> _sensorDataController =
      StreamController<SensorData>.broadcast();
  final StreamController<bool> _connectionController =
      StreamController<bool>.broadcast();

  Stream<SensorData> get sensorDataStream => _sensorDataController.stream;
  Stream<bool> get connectionStream => _connectionController.stream;
  bool get isConnected => _connectedDevice != null;

  // Scan for devices
  Future<List<flutter_blue.BluetoothDevice>> scanForDevices({
    Duration timeout = const Duration(seconds: 15),
  }) async {
    Logger.info('Starting BLE scan...');
    List<flutter_blue.BluetoothDevice> devices = [];

    try {
      // Check if Bluetooth is available
      if (await flutter_blue.FlutterBluePlus.isSupported == false) {
        throw Exception('Bluetooth not supported on this device');
      }

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
      return devices;
    } catch (e) {
      Logger.error('Scan error: $e');
      await flutter_blue.FlutterBluePlus.stopScan();
      rethrow;
    }
  }

  // Connect to device
  Future<bool> connectToDevice(flutter_blue.BluetoothDevice device) async {
    try {
      Logger.info('Connecting to ${device.advName}...');

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
      return true;
    } catch (e) {
      Logger.error('Connection failed: $e');
      await disconnect();
      return false;
    }
  }

  // Disconnect from device
  Future<void> disconnect() async {
    try {
      if (_connectedDevice != null) {
        await _connectedDevice!.disconnect();
        _connectedDevice = null;
        _rxCharacteristic = null;
        _txCharacteristic = null;
        _connectionController.add(false);
        Logger.info('Disconnected');
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
    return await sendCommand(BLEConstants.cmdSetFan, value);
  }

  Future<bool> setLEDBrightness(int brightness) async {
    int value = ((brightness / 100) * 255).round().clamp(0, 255);
    return await sendCommand(BLEConstants.cmdSetLED, value);
  }

  Future<bool> setAutoMode(bool enabled) async {
    return await sendCommand(BLEConstants.cmdSetAutoMode, enabled);
  }

  Future<bool> requestStatus() async {
    return await sendCommand(BLEConstants.cmdGetStatus, null);
  }

  // Cleanup
  void dispose() {
    _sensorDataController.close();
    _connectionController.close();
  }
}
