import 'package:cloud_firestore/cloud_firestore.dart';

class AlertModel {
  final String id;
  final String userId;
  final String type;
  final String severity;
  final String message;
  final Map<String, dynamic> data;
  final bool read;
  final bool acknowledged;
  final DateTime timestamp;

  const AlertModel({
    required this.id,
    required this.userId,
    required this.type,
    required this.severity,
    required this.message,
    this.data = const {},
    this.read = false,
    this.acknowledged = false,
    required this.timestamp,
  });

  factory AlertModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return AlertModel(
      id: doc.id,
      userId: data['userId'] ?? '',
      type: data['type'] ?? 'general',
      severity: data['severity'] ?? 'low',
      message: data['message'] ?? '',
      data: Map<String, dynamic>.from(data['data'] ?? {}),
      read: data['read'] ?? false,
      acknowledged: data['acknowledged'] ?? false,
      timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'type': type,
      'severity': severity,
      'message': message,
      'data': data,
      'read': read,
      'acknowledged': acknowledged,
      'timestamp': Timestamp.fromDate(timestamp),
    };
  }

  AlertModel copyWith({
    bool? read,
    bool? acknowledged,
  }) {
    return AlertModel(
      id: id,
      userId: userId,
      type: type,
      severity: severity,
      message: message,
      data: data,
      read: read ?? this.read,
      acknowledged: acknowledged ?? this.acknowledged,
      timestamp: timestamp,
    );
  }
}
