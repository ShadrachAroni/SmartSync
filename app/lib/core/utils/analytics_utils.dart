import 'package:intl/intl.dart';

import '../../models/sensor_data.dart';
import 'logger.dart';

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
  return Logger.safeExecute(
    'buildDailyTrends',
    () {
      if (logs.isEmpty) {
        Logger.info('buildDailyTrends: Empty logs, returning empty list');
        return <DailyTrendPoint>[];
      }

      final cutoff = (reference ?? DateTime.now()).subtract(Duration(days: days));
      final Map<DateTime, List<SensorData>> grouped = {};

      for (final log in logs) {
        try {
          if (log.timestamp.isBefore(cutoff)) continue;
          final dayKey = DateTime(
            log.timestamp.year,
            log.timestamp.month,
            log.timestamp.day,
          );
          grouped.putIfAbsent(dayKey, () => []).add(log);
        } catch (e, stackTrace) {
          Logger.error('buildDailyTrends: Error processing log', e, stackTrace);
        }
      }

      if (grouped.isEmpty) {
        Logger.info('buildDailyTrends: No logs after filtering, returning empty list');
        return <DailyTrendPoint>[];
      }

      final sortedKeys = grouped.keys.toList()..sort();

      return sortedKeys.map((day) {
        try {
          final entries = grouped[day]!;
          if (entries.isEmpty) {
            return DailyTrendPoint(
              label: DateFormat('MMM dd').format(day),
              temperature: 0.0,
              humidity: 0.0,
            );
          }
          
          final avgTemp = entries.fold<double>(
                0,
                (sum, log) => sum + log.temperature,
              ) /
              entries.length;
          final avgHumidity = entries.fold<double>(
                0,
                (sum, log) => sum + log.humidity,
              ) /
              entries.length;

          return DailyTrendPoint(
            label: DateFormat('MMM dd').format(day),
            temperature: double.parse(avgTemp.toStringAsFixed(2)),
            humidity: double.parse(avgHumidity.toStringAsFixed(2)),
          );
        } catch (e, stackTrace) {
          Logger.error('buildDailyTrends: Error processing day $day', e, stackTrace);
          return DailyTrendPoint(
            label: DateFormat('MMM dd').format(day),
            temperature: 0.0,
            humidity: 0.0,
          );
        }
      }).toList();
    },
    defaultValue: <DailyTrendPoint>[],
  )!;
}

List<HourlyActivityPoint> buildHourlyActivity(List<SensorData> logs) {
  return Logger.safeExecute(
    'buildHourlyActivity',
    () {
      if (logs.isEmpty) {
        Logger.info('buildHourlyActivity: Empty logs, returning empty list');
        return <HourlyActivityPoint>[];
      }

      final buckets = List<double>.filled(24, 0);

      for (final log in logs) {
        try {
          final hour = log.timestamp.hour;
          if (hour >= 0 && hour < 24) {
            buckets[hour] += log.motionDetected ? 1 : 0;
          }
        } catch (e, stackTrace) {
          Logger.error('buildHourlyActivity: Error processing log', e, stackTrace);
        }
      }

      return List.generate(
        24,
        (hour) => HourlyActivityPoint(
          hourLabel: hour.toString().padLeft(2, '0'),
          activityValue: buckets[hour],
        ),
      );
    },
    defaultValue: <HourlyActivityPoint>[],
  )!;
}
