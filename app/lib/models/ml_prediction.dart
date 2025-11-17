class SchedulePrediction {
  final int dayOfWeek; // 1-7
  final int hour; // 0-23
  final int minute; // 0-59
  final String deviceType;
  final int value;
  final double confidence;
  final String reason;
  final String? deviceId;
  final String? deviceName;
  final String? roomId;

  const SchedulePrediction({
    required this.dayOfWeek,
    required this.hour,
    required this.minute,
    required this.deviceType,
    required this.value,
    required this.confidence,
    required this.reason,
    this.deviceId,
    this.deviceName,
    this.roomId,
  });

  String get dayName {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[(dayOfWeek - 1).clamp(0, days.length - 1)];
  }

  String get timeString {
    final h = hour.toString().padLeft(2, '0');
    final m = minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

enum AnomalyType {
  inactivity,
  unusualActivity,
  temperatureExtreme,
  suddenChange,
}

class Anomaly {
  final AnomalyType type;
  final String severity; // low, medium, high
  final String message;
  final DateTime timestamp;
  final double confidence;

  const Anomaly({
    required this.type,
    required this.severity,
    required this.message,
    required this.timestamp,
    required this.confidence,
  });
}

class AnomalyReport {
  final DateTime timestamp;
  final List<Anomaly> anomalies;
  final double overallScore;

  const AnomalyReport({
    required this.timestamp,
    required this.anomalies,
    required this.overallScore,
  });

  bool get hasAnomalies => anomalies.isNotEmpty;
  bool get hasCritical => anomalies.any((a) => a.severity == 'high');
}

class AnalyticsInsights {
  final int totalLogs;
  final double avgTemperature;
  final double avgHumidity;
  final int motionEvents;
  final double avgFanUsage;
  final double avgLightUsage;
  final int peakUsageHour;
  final double energyConsumption;

  const AnalyticsInsights({
    required this.totalLogs,
    required this.avgTemperature,
    required this.avgHumidity,
    required this.motionEvents,
    required this.avgFanUsage,
    required this.avgLightUsage,
    required this.peakUsageHour,
    required this.energyConsumption,
  });

  AnalyticsInsights copyWith({
    int? totalLogs,
    double? avgTemperature,
    double? avgHumidity,
    int? motionEvents,
    double? avgFanUsage,
    double? avgLightUsage,
    int? peakUsageHour,
    double? energyConsumption,
  }) {
    return AnalyticsInsights(
      totalLogs: totalLogs ?? this.totalLogs,
      avgTemperature: avgTemperature ?? this.avgTemperature,
      avgHumidity: avgHumidity ?? this.avgHumidity,
      motionEvents: motionEvents ?? this.motionEvents,
      avgFanUsage: avgFanUsage ?? this.avgFanUsage,
      avgLightUsage: avgLightUsage ?? this.avgLightUsage,
      peakUsageHour: peakUsageHour ?? this.peakUsageHour,
      energyConsumption: energyConsumption ?? this.energyConsumption,
    );
  }
}
