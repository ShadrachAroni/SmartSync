import 'package:cloud_firestore/cloud_firestore.dart';

class LogEntry {
  final String id;
  final String userId;
  final String deviceId;
  final String category;
  final String message;
  final Map<String, dynamic> metadata;
  final DateTime timestamp;

  const LogEntry({
    required this.id,
    required this.userId,
    required this.deviceId,
    required this.category,
    required this.message,
    this.metadata = const {},
    required this.timestamp,
  });

  factory LogEntry.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return LogEntry(
      id: doc.id,
      userId: data['userId'] ?? '',
      deviceId: data['deviceId'] ?? '',
      category: data['category'] ?? 'system',
      message: data['message'] ?? '',
      metadata: Map<String, dynamic>.from(data['metadata'] ?? {}),
      timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'deviceId': deviceId,
      'category': category,
      'message': message,
      'metadata': metadata,
      'timestamp': Timestamp.fromDate(timestamp),
    };
  }
}
