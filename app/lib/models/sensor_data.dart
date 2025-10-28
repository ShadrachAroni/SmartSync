import 'package:json_annotation/json_annotation.dart';

part 'sensor_data.g.dart';

@JsonSerializable()
class SensorData {
  final String deviceId;
  final String userId;
  final double temperature;
  final double humidity;
  final int fanSpeed;
  final int ledBrightness;
  final bool motionDetected;
  final double distance;
  final DateTime timestamp;

  SensorData({
    required this.deviceId,
    required this.userId,
    required this.temperature,
    required this.humidity,
    required this.fanSpeed,
    required this.ledBrightness,
    required this.motionDetected,
    required this.distance,
    required this.timestamp,
  });

  factory SensorData.fromJson(Map<String, dynamic> json) =>
      _$SensorDataFromJson(json);

  Map<String, dynamic> toJson() => _$SensorDataToJson(this);

  // Helper methods
  int get fanSpeedPercentage => ((fanSpeed / 255) * 100).round();
  int get ledBrightnessPercentage => ((ledBrightness / 255) * 100).round();

  String get temperatureDisplay => '${temperature.toStringAsFixed(1)}°C';
  String get humidityDisplay => '${humidity.toStringAsFixed(0)}%';
  String get distanceDisplay => '${distance.toStringAsFixed(1)} cm';
}
