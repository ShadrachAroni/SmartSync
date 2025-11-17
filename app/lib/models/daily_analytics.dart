import 'package:cloud_firestore/cloud_firestore.dart';

class DailyAnalytics {
  final DateTime date;
  final double avgTemperature;
  final double avgHumidity;
  final int motionEvents;
  final double avgFanUsage;
  final double avgLightUsage;
  final int totalReadings;

  const DailyAnalytics({
    required this.date,
    required this.avgTemperature,
    required this.avgHumidity,
    required this.motionEvents,
    required this.avgFanUsage,
    required this.avgLightUsage,
    required this.totalReadings,
  });

  factory DailyAnalytics.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return DailyAnalytics(
      date: (data['date'] as Timestamp).toDate(),
      avgTemperature: (data['avgTemperature'] as num?)?.toDouble() ?? 0,
      avgHumidity: (data['avgHumidity'] as num?)?.toDouble() ?? 0,
      motionEvents: (data['motionEvents'] as num?)?.toInt() ?? 0,
      avgFanUsage: (data['avgFanUsage'] as num?)?.toDouble() ?? 0,
      avgLightUsage: (data['avgLedUsage'] as num?)?.toDouble() ?? 0,
      totalReadings: (data['totalReadings'] as num?)?.toInt() ?? 0,
    );
  }
}

