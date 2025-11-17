import 'package:cloud_firestore/cloud_firestore.dart';

class ScheduleModel {
  final String id;
  final String userId;
  final String deviceId;
  final String? roomId;
  final int hour;
  final int minute;
  final int fanSpeed;
  final int brightness;
  final bool enabled;
  final bool repeatDaily;
  final List<int> daysOfWeek;
  final String source; // manual | ai
  final DateTime createdAt;

  const ScheduleModel({
    required this.id,
    required this.userId,
    required this.deviceId,
    this.roomId,
    required this.hour,
    required this.minute,
    required this.fanSpeed,
    required this.brightness,
    this.enabled = true,
    this.repeatDaily = true,
    this.daysOfWeek = const [1, 2, 3, 4, 5, 6, 7],
    this.source = 'manual',
    required this.createdAt,
  });

  factory ScheduleModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return ScheduleModel(
      id: doc.id,
      userId: data['userId'] ?? '',
      deviceId: data['deviceId'] ?? '',
      roomId: data['roomId'],
      hour: data['hour'] ?? 0,
      minute: data['minute'] ?? 0,
      fanSpeed: data['fanSpeed'] ?? 0,
      brightness: data['brightness'] ?? 0,
      enabled: data['enabled'] ?? true,
      repeatDaily: data['repeatDaily'] ?? true,
      daysOfWeek: List<int>.from(data['daysOfWeek'] ?? [1, 2, 3, 4, 5, 6, 7]),
      source: data['source'] ?? 'manual',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'deviceId': deviceId,
      'roomId': roomId,
      'hour': hour,
      'minute': minute,
      'fanSpeed': fanSpeed,
      'brightness': brightness,
      'enabled': enabled,
      'repeatDaily': repeatDaily,
      'daysOfWeek': daysOfWeek,
      'source': source,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  String get timeLabel {
    final h = hour.toString().padLeft(2, '0');
    final m = minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  ScheduleModel copyWith({
    bool? enabled,
  }) {
    return ScheduleModel(
      id: id,
      userId: userId,
      deviceId: deviceId,
      roomId: roomId,
      hour: hour,
      minute: minute,
      fanSpeed: fanSpeed,
      brightness: brightness,
      enabled: enabled ?? this.enabled,
      repeatDaily: repeatDaily,
      daysOfWeek: daysOfWeek,
      source: source,
      createdAt: createdAt,
    );
  }
}
