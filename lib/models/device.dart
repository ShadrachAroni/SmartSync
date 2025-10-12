// lib/models/device.dart
import 'package:flutter/material.dart';

enum DeviceType { bulb, fan, tv, lock }

class Device {
  final String id; // internal id
  String room; // room label
  final String name; // display name
  final DeviceType type; // device kind
  final String image; // assets/images/...
  final IconData icon; // fallback
  final String? bleId; // remoteId.str or MAC to bind a persisted room

  bool power; // on/off
  int level; // 0..100 -> intensity/speed

  Device({
    required this.id,
    required this.room,
    required this.name,
    required this.type,
    required this.image,
    required this.icon,
    this.bleId,
    this.power = false,
    this.level = 0,
  });
}
