import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

enum DeviceType {
  light,
  fan,
  airConditioner,
  camera,
  tv,
  vacuum,
  sensor,
}

class DeviceModel {
  final String id;
  final String name;
  final DeviceType type;
  final String roomId;
  final bool isOn;
  final int value; // 0-100 for lights, fan speed, etc.
  final bool isOnline;
  final DateTime lastSeen;
  final Map<String, dynamic> metadata;

  DeviceModel({
    required this.id,
    required this.name,
    required this.type,
    required this.roomId,
    this.isOn = false,
    this.value = 0,
    this.isOnline = false,
    required this.lastSeen,
    this.metadata = const {},
  });

  factory DeviceModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return DeviceModel(
      id: doc.id,
      name: data['name'] ?? '',
      type: DeviceType.values.firstWhere(
        (e) => e.name == data['type'],
        orElse: () => DeviceType.sensor,
      ),
      roomId: data['roomId'] ?? '',
      isOn: data['isOn'] ?? false,
      value: data['value'] ?? 0,
      isOnline: data['isOnline'] ?? false,
      lastSeen: (data['lastSeen'] as Timestamp).toDate(),
      metadata: data['metadata'] ?? {},
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'type': type.name,
      'roomId': roomId,
      'isOn': isOn,
      'value': value,
      'isOnline': isOnline,
      'lastSeen': Timestamp.fromDate(lastSeen),
      'metadata': metadata,
    };
  }

  DeviceModel copyWith({
    String? id,
    String? name,
    DeviceType? type,
    String? roomId,
    bool? isOn,
    int? value,
    bool? isOnline,
    DateTime? lastSeen,
    Map<String, dynamic>? metadata,
  }) {
    return DeviceModel(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      roomId: roomId ?? this.roomId,
      isOn: isOn ?? this.isOn,
      value: value ?? this.value,
      isOnline: isOnline ?? this.isOnline,
      lastSeen: lastSeen ?? this.lastSeen,
      metadata: metadata ?? this.metadata,
    );
  }

  IconData get icon {
    switch (type) {
      case DeviceType.light:
        return Icons.lightbulb_outline;
      case DeviceType.fan:
        return Icons.air;
      case DeviceType.airConditioner:
        return Icons.ac_unit;
      case DeviceType.camera:
        return Icons.videocam;
      case DeviceType.tv:
        return Icons.tv;
      case DeviceType.vacuum:
        return Icons.cleaning_services;
      case DeviceType.sensor:
        return Icons.sensors;
    }
  }
}
