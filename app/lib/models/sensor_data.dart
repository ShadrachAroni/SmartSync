import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:json_annotation/json_annotation.dart';

part 'sensor_data.g.dart';

@JsonSerializable()
class SensorData {
  final String deviceId;
  final String userId;
  final double temperature;
  final double humidity;
  final double? heatIndex;
  final int fanSpeed;
  final int ledBrightness;
  final bool motionDetected;
  final double distance;
  final bool securityEnabled;
  final DateTime timestamp;

  SensorData({
    required this.deviceId,
    required this.userId,
    required this.temperature,
    required this.humidity,
    this.heatIndex,
    required this.fanSpeed,
    required this.ledBrightness,
    required this.motionDetected,
    required this.distance,
    required this.securityEnabled,
    required this.timestamp,
  });

  factory SensorData.fromJson(Map<String, dynamic> json) {
    // Handle Firestore Timestamp conversion
    final jsonCopy = Map<String, dynamic>.from(json);
    if (jsonCopy['timestamp'] is Timestamp) {
      jsonCopy['timestamp'] = (jsonCopy['timestamp'] as Timestamp)
          .toDate()
          .toIso8601String();
    } else if (jsonCopy['timestamp'] is! String) {
      // If it's already a DateTime, convert to string
      jsonCopy['timestamp'] = (jsonCopy['timestamp'] as DateTime)
          .toIso8601String();
    }
    return _$SensorDataFromJson(jsonCopy);
  }

  Map<String, dynamic> toJson() => _$SensorDataToJson(this);

  // Helper methods
  int get fanSpeedPercentage => ((fanSpeed / 255) * 100).round();
  int get ledBrightnessPercentage => ((ledBrightness / 255) * 100).round();

  String get temperatureDisplay => '${temperature.toStringAsFixed(1)}°C';
  String get humidityDisplay => '${humidity.toStringAsFixed(0)}%';
  String get distanceDisplay => '${distance.toStringAsFixed(1)} cm';
  String get securityStatus => securityEnabled ? 'Armed' : 'Disarmed';
  
  String get heatIndexDisplay {
    if (heatIndex == null || heatIndex!.isNaN) {
      return '--°C';
    }
    return '${heatIndex!.toStringAsFixed(1)}°C';
  }
  
  String get comfortLevel {
    // Calculate comfort level based on temperature and humidity
    if (humidity < 30) {
      return 'Too Dry';
    } else if (humidity > 70) {
      return 'Too Humid';
    } else if (temperature < 18) {
      return 'Too Cold';
    } else if (temperature > 28) {
      return 'Too Hot';
    } else if (humidity >= 50 && humidity <= 60 && temperature >= 20 && temperature <= 24) {
      return 'Comfortable';
    } else if (humidity >= 40 && humidity <= 70 && temperature >= 18 && temperature <= 26) {
      return 'Acceptable';
    } else {
      return 'Moderate';
    }
  }
}
