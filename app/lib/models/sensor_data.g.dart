// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sensor_data.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

SensorData _$SensorDataFromJson(Map<String, dynamic> json) => SensorData(
      deviceId: json['deviceId'] as String,
      userId: json['userId'] as String,
      temperature: (json['temperature'] as num).toDouble(),
      humidity: (json['humidity'] as num).toDouble(),
      fanSpeed: (json['fanSpeed'] as num).toInt(),
      ledBrightness: (json['ledBrightness'] as num).toInt(),
      motionDetected: json['motionDetected'] as bool,
      distance: (json['distance'] as num).toDouble(),
      timestamp: DateTime.parse(json['timestamp'] as String),
    );

Map<String, dynamic> _$SensorDataToJson(SensorData instance) =>
    <String, dynamic>{
      'deviceId': instance.deviceId,
      'userId': instance.userId,
      'temperature': instance.temperature,
      'humidity': instance.humidity,
      'fanSpeed': instance.fanSpeed,
      'ledBrightness': instance.ledBrightness,
      'motionDetected': instance.motionDetected,
      'distance': instance.distance,
      'timestamp': instance.timestamp.toIso8601String(),
    };
