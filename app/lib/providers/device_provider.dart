import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/device_model.dart';
import '../services/firebase_service.dart';
import '../services/bluetooth_service.dart';
import '../services/logging_service.dart';
import '../models/log_entry.dart';
import '../core/utils/logger.dart';

class DeviceController extends StateNotifier<AsyncValue<List<DeviceModel>>> {
  DeviceController(this._ref, this._userId)
      : super(const AsyncValue.loading()) {
    _listen();
  }

  final Ref _ref;
  final String _userId;
  StreamSubscription<List<DeviceModel>>? _subscription;

  FirebaseService get _firebase => _ref.read(firebaseServiceProvider);
  BluetoothService get _bluetooth => _ref.read(bluetoothServiceProvider);

  void _listen() {
    Logger.debug('DeviceController: Starting to listen for devices for user $_userId');
    _subscription = _firebase.getUserDevices(_userId).listen(
          (devices) {
            if (!disposed) {
              Logger.debug('DeviceController: Received ${devices.length} devices');
              state = AsyncValue.data(devices);
            }
          },
          onError: (error, stack) {
            Logger.error('DeviceController: Error listening to devices: $error');
            if (!disposed) {
              state = AsyncValue.error(error, stack);
            }
          },
          cancelOnError: false,
        );
  }
  
  bool disposed = false;

  Future<void> toggleDevice(DeviceModel device, bool enabled) async {
    Logger.info('DeviceController: Toggling device ${device.id} to ${enabled ? "on" : "off"}');
    
    final previousState = device.isOn;
    final previousValue = device.value;
    final newValue = enabled ? device.value : 0;
    
    await _firebase.updateDevice(device.id, {
      'isOn': enabled,
      'value': newValue,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    Logger.debug('DeviceController: Device state updated in Firebase');

    // Get room name for detailed logging
    String? roomName;
    try {
      final rooms = await _firebase.getUserRooms(_userId).first;
      final room = rooms.firstWhere((r) => r.id == device.roomId, orElse: () => rooms.first);
      roomName = room.name;
    } catch (e) {
      roomName = 'Unknown Room';
    }

    // Log detailed action
    final loggingService = LoggingService();
    await loggingService.logAction(
      action: enabled ? 'Device Turned ON' : 'Device Turned OFF',
      category: 'device_control',
      details: '${device.type.name.toUpperCase()} "${device.name}" in room "$roomName" ${enabled ? "turned ON" : "turned OFF"}',
      metadata: {
        'deviceId': device.id,
        'deviceName': device.name,
        'deviceType': device.type.name,
        'roomId': device.roomId,
        'roomName': roomName,
        'previousState': previousState,
        'newState': enabled,
        'previousValue': previousValue,
        'newValue': newValue,
        'valuePercentage': enabled ? newValue : 0,
        'bleConnected': _bluetooth.isConnected,
        'actionType': 'toggle',
        'timestamp': DateTime.now().toIso8601String(),
      },
      level: LogLevel.info,
    );

    if (_bluetooth.isConnected) {
      Logger.debug('DeviceController: Sending command to BLE device');
      if (device.type == DeviceType.fan) {
        await _bluetooth.setFanSpeed(newValue);
        Logger.info('DeviceController: Fan speed set to $newValue');
      } else if (device.type == DeviceType.light) {
        await _bluetooth.setLEDBrightness(newValue);
        Logger.info('DeviceController: Ambient lights set to $newValue');
      }
    } else {
      Logger.warning('DeviceController: BLE not connected, device state only updated in Firebase');
    }
  }

  Future<void> updateValue(DeviceModel device, int value) async {
    final previousValue = device.value;
    final previousState = device.isOn;
    final newState = value > 0;
    
    await _firebase.updateDevice(device.id, {
      'value': value,
      'isOn': newState,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // Get room name for detailed logging
    String? roomName;
    try {
      final rooms = await _firebase.getUserRooms(_userId).first;
      final room = rooms.firstWhere((r) => r.id == device.roomId, orElse: () => rooms.first);
      roomName = room.name;
    } catch (e) {
      roomName = 'Unknown Room';
    }

    // Determine value type based on device type
    String valueType = device.type == DeviceType.fan ? 'Fan Speed' : 'Brightness';
    String unit = '%';

    // Log detailed action
    final loggingService = LoggingService();
    await loggingService.logAction(
      action: 'Device Value Changed',
      category: 'device_control',
      details: '$valueType of ${device.type.name.toUpperCase()} "${device.name}" in room "$roomName" changed from $previousValue$unit to $value$unit',
      metadata: {
        'deviceId': device.id,
        'deviceName': device.name,
        'deviceType': device.type.name,
        'roomId': device.roomId,
        'roomName': roomName,
        'valueType': valueType,
        'previousValue': previousValue,
        'newValue': value,
        'previousState': previousState,
        'newState': newState,
        'valuePercentage': value,
        'rawValue': value,
        'bleConnected': _bluetooth.isConnected,
        'actionType': 'value_update',
        'timestamp': DateTime.now().toIso8601String(),
      },
      level: LogLevel.info,
    );

    if (_bluetooth.isConnected) {
      if (device.type == DeviceType.fan) {
        await _bluetooth.setFanSpeed(value);
      } else if (device.type == DeviceType.light) {
        await _bluetooth.setLEDBrightness(value);
      }
    }
  }

  @override
  void dispose() {
    disposed = true;
    _subscription?.cancel();
    super.dispose();
  }
}

// Changed from autoDispose to keep state persistent across tab changes
final deviceControllerProvider = StateNotifierProvider
    .family<DeviceController, AsyncValue<List<DeviceModel>>, String>(
  (ref, userId) {
    final controller = DeviceController(ref, userId);
    ref.onDispose(controller.dispose);
    return controller;
  },
);

final bluetoothServiceProvider =
    Provider<BluetoothService>((ref) => BluetoothService());
