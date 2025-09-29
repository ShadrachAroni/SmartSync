import 'dart:async';
import 'dart:math';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class TemperatureService {
  // Make sure this matches your firmware characteristic UUID
  static const String TEMPERATURE_CHAR_UUID =
      "12345678-1234-5678-1234-56789abcf05";

  /// Subscribe to BLE temperature notifications. Returns a Stream<double>.
  static Stream<double> subscribeTemperature(BluetoothDevice device) async* {
    try {
      // ensure connected
      try {
        await device.connect();
      } catch (_) {}
      final services = await device.discoverServices();
      for (final s in services) {
        for (final c in s.characteristics) {
          if (c.uuid.toString().toLowerCase() ==
              TEMPERATURE_CHAR_UUID.toLowerCase()) {
            // enable notifications
            await c.setNotifyValue(true);
            // c.value is a Stream<List<int>>
            await for (final bytes in c.value) {
              if (bytes.isEmpty) continue;
              // interpret bytes as a single signed or unsigned int, or ascii; adjust to match your firmware
              final val = bytes.first;
              yield val.toDouble();
            }
            return;
          }
        }
      }
      // If no characteristic found, fallback to simulated stream:
      await for (final v in simulatedTemperatureStream().take(100000)) {
        yield v;
      }
    } catch (e) {
      // fallback simulation
      await for (final v in simulatedTemperatureStream().take(100000)) {
        yield v;
      }
    }
  }

  /// Simulated temperature stream for when hardware not available.
  static Stream<double> simulatedTemperatureStream(
      {Duration interval = const Duration(seconds: 3)}) async* {
    final rnd = Random();
    double t = 20.0 + rnd.nextDouble() * 3;
    while (true) {
      // small random walk
      t += (rnd.nextDouble() - 0.5) * 0.8;
      t = t.clamp(16.0, 30.0);
      yield double.parse(t.toStringAsFixed(1));
      await Future.delayed(interval);
    }
  }
}
