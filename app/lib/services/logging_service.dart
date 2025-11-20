import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/log_entry.dart';

/// Service for logging all app actions and events
class LoggingService {
  static final LoggingService _instance = LoggingService._internal();
  factory LoggingService() => _instance;
  LoggingService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final List<LogEntry> _localLogs = [];
  static const int _maxLocalLogs = 100;

  /// Log an action
  Future<void> logAction({
    required String action,
    required String category,
    String? details,
    Map<String, dynamic>? metadata,
    LogLevel level = LogLevel.info,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final entry = LogEntry(
      id: '',
      userId: user.uid,
      action: action,
      category: category,
      details: details ?? '',
      metadata: metadata ?? {},
      level: level,
      timestamp: DateTime.now(),
    );

    // Add to local cache
    _localLogs.insert(0, entry);
    if (_localLogs.length > _maxLocalLogs) {
      _localLogs.removeLast();
    }

    try {
      // Save to Firestore with timeout
      final docRef = _firestore.collection('activity_logs').doc();
      await docRef.set(entry.toMap()).timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          // If timeout, just keep in local cache - don't throw
        },
      );
    } catch (e) {
      // Silently fail - logs are not critical
    }
  }

  /// Get logs for current user
  Stream<List<LogEntry>> getUserLogs({
    int limit = 100,
    DateTime? startDate,
    String? category,
    LogLevel? level,
  }) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      // Return local logs if no user
      return Stream.value(_localLogs);
    }

    try {
      Query query = _firestore
          .collection('activity_logs')
          .where('userId', isEqualTo: user.uid);

      if (startDate != null) {
        query = query.where('timestamp',
            isGreaterThan: Timestamp.fromDate(startDate));
      }

      if (category != null) {
        query = query.where('category', isEqualTo: category);
      }

      if (level != null) {
        query = query.where('level', isEqualTo: level.name);
      }

      return query
          .orderBy('timestamp', descending: true)
          .limit(limit)
          .snapshots()
          .timeout(const Duration(seconds: 10))
          .map((snapshot) {
            try {
              final logs = snapshot.docs
                  .map((doc) => LogEntry.fromMap(doc.id, doc.data() as Map<String, dynamic>))
                  .toList();
              // Merge with local logs if any
              if (_localLogs.isNotEmpty) {
                final allLogs = [...logs, ..._localLogs];
                allLogs.sort((a, b) => b.timestamp.compareTo(a.timestamp));
                return allLogs.take(limit).toList();
              }
              return logs;
            } catch (e) {
              // If parsing fails, return local logs
              return _localLogs;
            }
          })
          .handleError((error, stackTrace) {
            // On timeout or any error, this will be caught by the provider
            // The provider will handle it and show local logs
          });
    } catch (e) {
      // Return local logs immediately on exception
      return Stream.value(_localLogs);
    }
  }

  /// Get local cached logs
  List<LogEntry> getLocalLogs() => List.unmodifiable(_localLogs);

  /// Clear local logs
  void clearLocalLogs() {
    _localLogs.clear();
  }
}

