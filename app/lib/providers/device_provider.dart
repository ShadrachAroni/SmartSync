import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/device_model.dart';
import '../services/firebase_service.dart';
import '../services/bluetooth_service.dart';

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
    _subscription = _firebase.getUserDevices(_userId).listen(
          (devices) => state = AsyncValue.data(devices),
          onError: (error, stack) => state = AsyncValue.error(error, stack),
        );
  }

  Future<void> toggleDevice(DeviceModel device, bool enabled) async {
    await _firebase.updateDevice(device.id, {
      'isOn': enabled,
      'value': enabled ? device.value : 0,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    if (_bluetooth.isConnected) {
      if (device.type == DeviceType.fan) {
        await _bluetooth.setFanSpeed(enabled ? device.value : 0);
      } else if (device.type == DeviceType.light) {
        await _bluetooth.setLEDBrightness(enabled ? device.value : 0);
      }
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
    _subscription?.cancel();
    super.dispose();
  }
}

final deviceControllerProvider = StateNotifierProvider.autoDispose
    .family<DeviceController, AsyncValue<List<DeviceModel>>, String>(
  (ref, userId) {
    final controller = DeviceController(ref, userId);
    ref.onDispose(controller.dispose);
    return controller;
  },
);

final bluetoothServiceProvider =
    Provider<BluetoothService>((ref) => BluetoothService());
