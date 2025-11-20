import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/device_model.dart';
import '../services/firebase_service.dart';
import '../services/bluetooth_service.dart';
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
    await _firebase.updateDevice(device.id, {
      'isOn': enabled,
      'value': enabled ? device.value : 0,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    Logger.debug('DeviceController: Device state updated in Firebase');

    if (_bluetooth.isConnected) {
      Logger.debug('DeviceController: Sending command to BLE device');
      if (device.type == DeviceType.fan) {
        await _bluetooth.setFanSpeed(enabled ? device.value : 0);
        Logger.info('DeviceController: Fan speed set to ${enabled ? device.value : 0}');
      } else if (device.type == DeviceType.light) {
        await _bluetooth.setLEDBrightness(enabled ? device.value : 0);
        Logger.info('DeviceController: LED brightness set to ${enabled ? device.value : 0}');
      }
    } else {
      Logger.warning('DeviceController: BLE not connected, device state only updated in Firebase');
    }
  }

  Future<void> updateValue(DeviceModel device, int value) async {
    await _firebase.updateDevice(device.id, {
      'value': value,
      'isOn': value > 0,
      'updatedAt': FieldValue.serverTimestamp(),
    });

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
