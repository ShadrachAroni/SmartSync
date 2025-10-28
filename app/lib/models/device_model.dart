import 'package:json_annotation/json_annotation.dart';

part 'device_model.g.dart';

@JsonSerializable()
class DeviceModel {
  final String deviceId;
  final String userId;
  final String name;
  final String type;
  final String location;
  final String firmwareVersion;
  final DateTime createdAt;
  final DateTime lastSeen;
  final bool online;
  final int? batteryLevel;

  DeviceModel({
    required this.deviceId,
    required this.userId,
    required this.name,
    required this.type,
    required this.location,
    required this.firmwareVersion,
    required this.createdAt,
    required this.lastSeen,
    required this.online,
    this.batteryLevel,
  });

  factory DeviceModel.fromJson(Map<String, dynamic> json) =>
      _$DeviceModelFromJson(json);

  Map<String, dynamic> toJson() => _$DeviceModelToJson(this);

  DeviceModel copyWith({
    String? deviceId,
    String? userId,
    String? name,
    String? type,
    String? location,
    String? firmwareVersion,
    DateTime? createdAt,
    DateTime? lastSeen,
    bool? online,
    int? batteryLevel,
  }) {
    return DeviceModel(
      deviceId: deviceId ?? this.deviceId,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      type: type ?? this.type,
      location: location ?? this.location,
      firmwareVersion: firmwareVersion ?? this.firmwareVersion,
      createdAt: createdAt ?? this.createdAt,
      lastSeen: lastSeen ?? this.lastSeen,
      online: online ?? this.online,
      batteryLevel: batteryLevel ?? this.batteryLevel,
    );
  }
}
