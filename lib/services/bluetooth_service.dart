import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class BluetoothService {
  // Example characteristic UUIDs — match with your firmware
  static const serviceUuid = "12345678-1234-5678-1234-56789abcdef0";
  static const brightnessCharUuid = "12345678-1234-5678-1234-56789abcdef1";
  static const fanCharUuid = "12345678-1234-5678-1234-56789abcdef2";

  /// Scans for devices and returns a single list after [timeout]
  static Future<List<BluetoothDevice>> scanForDevices({
    Duration timeout = const Duration(seconds: 4),
  }) async {
    final foundIds = <DeviceIdentifier>{};
    final found = <BluetoothDevice>[];

    // Use the static stream
    final sub = FlutterBluePlus.scanResults.listen((results) {
      for (final r in results) {
        final id = r.device.id;
        if (!foundIds.contains(id)) {
          foundIds.add(id);
          found.add(r.device);
        }
      }
    });

    // startScan is static on the class
    try {
      await FlutterBluePlus.startScan(timeout: timeout);
      // startScan with timeout will stop automatically, but wait the timeout to collect results
      await Future.delayed(timeout);
      // ensure stopped
      await FlutterBluePlus.stopScan();
    } catch (_) {
      // ignore or handle specific exceptions
      try {
        await FlutterBluePlus.stopScan();
      } catch (_) {}
    } finally {
      await sub.cancel();
    }

    return found;
  }

  /// Connects to a device (safe: ignores already-connected error)
  static Future<void> connect(BluetoothDevice device,
      {Duration timeout = const Duration(seconds: 10)}) async {
    try {
      // If connect signature needs options in your version, update accordingly
      await device.connect(timeout: timeout);
    } on Exception {
      // Some platforms throw if already connected — ignore that silently
      // Optionally check device.state and return if already connected
      final isConnected = await _isDeviceConnected(device);
      if (!isConnected) rethrow;
    }
  }

  static Future<bool> _isDeviceConnected(BluetoothDevice device) async {
    try {
      final states = await device.state.first;
      return states == BluetoothDeviceState.connected;
    } catch (_) {
      return false;
    }
  }

  /// Writes bytes to a characteristic identified by [charUuid]
  static Future<void> writeCharacteristic(
      BluetoothDevice device, String charUuid, List<int> bytes) async {
    final services = await device.discoverServices();
    final targetUuid = charUuid.toLowerCase();
    for (final svc in services) {
      for (final char in svc.characteristics) {
        if (char.uuid.toString().toLowerCase() == targetUuid) {
          // write may require withoutResponse true/false based on characteristic properties
          await char.write(bytes, withoutResponse: false);
          return;
        }
      }
    }
    throw Exception(
        'Characteristic $charUuid not found on device ${device.id}');
  }

  /// Convenience: send brightness 0-100
  static Future<void> setBrightness(
      BluetoothDevice device, int brightness) async {
    final value = brightness.clamp(0, 100) & 0xFF;
    final bytes = [value];
    await writeCharacteristic(device, brightnessCharUuid, bytes);
  }

  /// Convenience: send fan speed 0-100
  static Future<void> setFanSpeed(BluetoothDevice device, int speed) async {
    final value = speed.clamp(0, 100) & 0xFF;
    final bytes = [value];
    await writeCharacteristic(device, fanCharUuid, bytes);
  }
}
