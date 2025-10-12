// lib/services/ble_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

// If Windows support is added, follow the package docs by changing imports to:
// import 'package:flutter_blue_plus/flutter_blue_plus.dart' hide FlutterBluePlus;
// import 'package:flutter_blue_plus_windows/flutter_blue_plus_windows.dart' show FlutterBluePlus;
// and then remove the UnsupportedError for Platform.isWindows.

bool get _bleSupported {
  if (kIsWeb) return true; // Web is supported by flutter_blue_plus
  if (Platform.isAndroid ||
      Platform.isIOS ||
      Platform.isMacOS ||
      Platform.isLinux) {
    return true;
  }
  if (Platform.isWindows) return false; // requires flutter_blue_plus_windows
  return false;
}

class BLEService {
  static final BLEService _i = BLEService._();
  BLEService._();
  factory BLEService() => _i;

  BluetoothDevice? device;
  StreamSubscription<List<ScanResult>>? _scanSub;

  // Replace these with your ESP32 GATT UUIDs
  final Guid serviceUuid = Guid('0000ffff-0000-1000-8000-00805f9b34fb');
  final Guid fanCharUuid = Guid('0000fff1-0000-1000-8000-00805f9b34fb');
  final Guid bulbCharUuid = Guid('0000fff2-0000-1000-8000-00805f9b34fb');
  final Guid tempCharUuid = Guid('0000fff3-0000-1000-8000-00805f9b34fb');
  final Guid pirCharUuid = Guid('0000fff4-0000-1000-8000-00805f9b34fb');
  final Guid ultraCharUuid = Guid('0000fff5-0000-1000-8000-00805f9b34fb');
  final Guid alarmCharUuid = Guid('0000fff6-0000-1000-8000-00805f9b34fb');

  BluetoothCharacteristic? _fan, _bulb, _temp, _pir, _ultra, _alarm;

  // Broadcast controllers so multiple listeners are allowed
  final tempStream = StreamController<double>.broadcast();
  final pirStream = StreamController<bool>.broadcast();
  final ultraStream = StreamController<bool>.broadcast();

  void _ensureSupported() {
    if (!_bleSupported) {
      throw UnsupportedError(
        'flutter_blue_plus is not supported on this platform. '
        'Run on Android/iOS/macOS/Linux/Web, or add flutter_blue_plus_windows for Windows.',
      );
    }
  }

  Future<void> startScan(void Function(List<ScanResult>) onResults) async {
    _ensureSupported();
    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 6));
    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      onResults(results);
    });
  }

  Future<void> stopScan() async {
    if (!_bleSupported) return;
    await FlutterBluePlus.stopScan();
    await _scanSub?.cancel();
    _scanSub = null;
  }

  Future<void> connect(BluetoothDevice d) async {
    _ensureSupported();
    device = d;
    await d.connect(autoConnect: false);

    final services = await d.discoverServices();
    // Pick the configured service if present, otherwise first
    final s = services.firstWhere(
      (e) => e.uuid == serviceUuid,
      orElse: () => services.isNotEmpty
          ? services.first
          : (throw StateError('No GATT services found')),
    );

    for (final c in s.characteristics) {
      if (c.uuid == fanCharUuid) _fan = c;
      if (c.uuid == bulbCharUuid) _bulb = c;
      if (c.uuid == tempCharUuid) _temp = c;
      if (c.uuid == pirCharUuid) _pir = c;
      if (c.uuid == ultraCharUuid) _ultra = c;
      if (c.uuid == alarmCharUuid) _alarm = c;
    }

    // Enable sensor notifications
    if (_temp != null && _temp!.properties.notify) {
      await _temp!.setNotifyValue(true);
      _temp!.onValueReceived.listen((v) {
        if (v.isNotEmpty) {
          final str = utf8.decode(v);
          tempStream.add(double.tryParse(str) ?? 0);
        }
      });
    }
    if (_pir != null && _pir!.properties.notify) {
      await _pir!.setNotifyValue(true);
      _pir!.onValueReceived
          .listen((v) => pirStream.add(v.isNotEmpty && v.first == 1));
    }
    if (_ultra != null && _ultra!.properties.notify) {
      await _ultra!.setNotifyValue(true);
      _ultra!.onValueReceived
          .listen((v) => ultraStream.add(v.isNotEmpty && v.first == 1));
    }
  }

  Future<void> disconnect() async {
    if (device == null) return;
    try {
      await device!.disconnect();
    } finally {
      device = null;
    }
  }

  Future<void> setFanSpeed(int percent) async {
    if (!_bleSupported || _fan == null) return;
    final v = percent.clamp(0, 100);
    await _fan!.write([v], withoutResponse: true);
  }

  Future<void> setBulbIntensity(int percent) async {
    if (!_bleSupported || _bulb == null) return;
    final v = percent.clamp(0, 100);
    await _bulb!.write([v], withoutResponse: true);
  }

  Future<void> setAlarm(bool on) async {
    if (!_bleSupported || _alarm == null) return;
    await _alarm!.write([on ? 1 : 0], withoutResponse: true);
  }

  Future<void> dispose() async {
    await tempStream.close();
    await pirStream.close();
    await ultraStream.close();
  }
}
