import 'package:cloud_firestore/cloud_firestore.dart';

enum LogLevel {
  debug,
  info,
  warning,
  error,
}

class LogEntry {
  final String id;
  final String userId;
  final String action;
  final String category;
  final String details;
  final Map<String, dynamic> metadata;
  final LogLevel level;
  final DateTime timestamp;

  LogEntry({
    required this.id,
    required this.userId,
    required this.action,
    required this.category,
    required this.details,
    required this.metadata,
    required this.level,
    required this.timestamp,
  });

  factory LogEntry.fromMap(String id, Map<String, dynamic> map) {
    return LogEntry(
      id: id,
      userId: map['userId'] ?? '',
      action: map['action'] ?? '',
      category: map['category'] ?? '',
      details: map['details'] ?? '',
      metadata: Map<String, dynamic>.from(map['metadata'] ?? {}),
      level: LogLevel.values.firstWhere(
        (e) => e.name == map['level'],
        orElse: () => LogLevel.info,
      ),
      timestamp: (map['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'action': action,
      'category': category,
      'details': details,
      'metadata': metadata,
      'level': level.name,
      'timestamp': Timestamp.fromDate(timestamp),
    };
  }
}
