// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'device_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

DeviceModel _$DeviceModelFromJson(Map<String, dynamic> json) => DeviceModel(
      deviceId: json['deviceId'] as String,
      userId: json['userId'] as String,
      name: json['name'] as String,
      type: json['type'] as String,
      location: json['location'] as String,
      firmwareVersion: json['firmwareVersion'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      lastSeen: DateTime.parse(json['lastSeen'] as String),
      online: json['online'] as bool,
      batteryLevel: (json['batteryLevel'] as num?)?.toInt(),
    );

Map<String, dynamic> _$DeviceModelToJson(DeviceModel instance) =>
    <String, dynamic>{
      'deviceId': instance.deviceId,
      'userId': instance.userId,
      'name': instance.name,
      'type': instance.type,
      'location': instance.location,
      'firmwareVersion': instance.firmwareVersion,
      'createdAt': instance.createdAt.toIso8601String(),
      'lastSeen': instance.lastSeen.toIso8601String(),
      'online': instance.online,
      'batteryLevel': instance.batteryLevel,
    };
