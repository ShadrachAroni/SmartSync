import 'package:flutter_test/flutter_test.dart';

import 'package:smartsync_app/core/utils/analytics_utils.dart';
import 'package:smartsync_app/models/sensor_data.dart';

void main() {
  final DateTime now = DateTime.now();

  SensorData buildSensor({
    required DateTime timestamp,
    double temperature = 22,
    double humidity = 50,
    bool motion = false,
  }) {
    return SensorData(
      deviceId: 'device',
      userId: 'user',
      temperature: temperature,
      humidity: humidity,
      fanSpeed: 100,
      ledBrightness: 80,
      motionDetected: motion,
      distance: 120,
      securityEnabled: true,
      timestamp: timestamp,
    );
  }

  group('Analytics Utils', () {
    test('buildDailyTrends aggregates per day', () {
      final logs = [
        buildSensor(timestamp: now.subtract(const Duration(days: 1))),
        buildSensor(
          timestamp: now.subtract(const Duration(days: 1, hours: -3)),
          temperature: 24,
          humidity: 55,
        ),
        buildSensor(
          timestamp: now.subtract(const Duration(days: 2)),
          temperature: 20,
          humidity: 45,
        ),
      ];

      final result = buildDailyTrends(logs, 3, reference: now);

      expect(result.length, 2);
      expect(result.last.temperature, greaterThan(result.first.temperature));
    });

    test('buildHourlyActivity counts motion events by hour', () {
      final logs = [
        buildSensor(
          timestamp: DateTime(now.year, now.month, now.day, 10),
          motion: true,
        ),
        buildSensor(
          timestamp: DateTime(now.year, now.month, now.day, 10, 30),
          motion: true,
        ),
        buildSensor(
          timestamp: DateTime(now.year, now.month, now.day, 21),
          motion: false,
        ),
      ];

      final result = buildHourlyActivity(logs);

      expect(result.length, 24);
      expect(
        result.firstWhere((point) => point.hourLabel == '10').activityValue,
        2,
      );
      expect(
        result.firstWhere((point) => point.hourLabel == '21').activityValue,
        0,
      );
    });
  });
}

