import 'package:intl/intl.dart';

import '../../models/sensor_data.dart';

class DailyTrendPoint {
  final String label;
  final double temperature;
  final double humidity;

  const DailyTrendPoint({
    required this.label,
    required this.temperature,
    required this.humidity,
  });
}

class HourlyActivityPoint {
  final String hourLabel;
  final double activityValue;

  const HourlyActivityPoint({
    required this.hourLabel,
    required this.activityValue,
  });
}

List<DailyTrendPoint> buildDailyTrends(
  List<SensorData> logs,
  int days, {
  DateTime? reference,
}) {
  if (logs.isEmpty) return [];

  final cutoff = (reference ?? DateTime.now()).subtract(Duration(days: days));
  final Map<DateTime, List<SensorData>> grouped = {};

  for (final log in logs) {
    if (log.timestamp.isBefore(cutoff)) continue;
    final dayKey =
        DateTime(log.timestamp.year, log.timestamp.month, log.timestamp.day);
    grouped.putIfAbsent(dayKey, () => []).add(log);
  }

  final sortedKeys = grouped.keys.toList()..sort();

  return sortedKeys.map((day) {
    final entries = grouped[day]!;
    final avgTemp =
        entries.fold<double>(0, (sum, log) => sum + log.temperature) /
            entries.length;
    final avgHumidity =
        entries.fold<double>(0, (sum, log) => sum + log.humidity) /
            entries.length;

    return DailyTrendPoint(
      label: DateFormat('MMM dd').format(day),
      temperature: double.parse(avgTemp.toStringAsFixed(2)),
      humidity: double.parse(avgHumidity.toStringAsFixed(2)),
    );
  }).toList();
}

List<HourlyActivityPoint> buildHourlyActivity(List<SensorData> logs) {
  if (logs.isEmpty) return [];

  final buckets = List<double>.filled(24, 0);

  for (final log in logs) {
    final hour = log.timestamp.hour;
    buckets[hour] += log.motionDetected ? 1 : 0;
  }

  return List.generate(
    24,
    (hour) => HourlyActivityPoint(
      hourLabel: hour.toString().padLeft(2, '0'),
      activityValue: buckets[hour],
    ),
  );
}
