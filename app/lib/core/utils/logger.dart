import 'package:flutter/foundation.dart';
import 'dart:developer' as developer;

/// Improved logger with error deduplication and filtering
class Logger {
  // Error deduplication: track seen errors with timestamps
  static final Map<String, DateTime> _errorHistory = {};
  static final Map<String, int> _errorCounts = {};
  static const Duration _errorThrottleDuration = Duration(seconds: 5);
  static const int _maxErrorRepeats = 3; // Max times to show same error
  
  // Patterns to filter out (framework internal errors)
  static final List<RegExp> _filteredPatterns = [
    RegExp(r'RenderBox.*was not laid out'),
    RegExp(r'BoxConstraints.*forces an infinite'),
    RegExp(r'hasSize.*is not true'),
    RegExp(r'Failed assertion.*hasSize'),
    RegExp(r'Render.*relayoutBoundary'),
    RegExp(r'Another exception was thrown'),
    RegExp(r'package:flutter/src/rendering'),
  ];

  static void debug(String message) {
    if (kDebugMode) {
      print('🐛 DEBUG: $message');
    }
  }

  static void info(String message) {
    if (kDebugMode) {
      print('ℹ️ INFO: $message');
    }
  }

  static void success(String message) {
    if (kDebugMode) {
      print('✅ SUCCESS: $message');
    }
  }

  static void warning(String message) {
    // Throttle warnings too
    if (_shouldLog(message, isWarning: true)) {
      print('⚠️ WARNING: $message');
    }
  }

  static void error(String message, [Object? error, StackTrace? stackTrace]) {
    // Create error signature for deduplication
    final errorSignature = _createErrorSignature(message, error);
    
    // Check if this is a filtered framework error
    if (_isFilteredError(message, error)) {
      // Only log once with a summary
      if (!_errorHistory.containsKey(errorSignature)) {
        print('❌ ERROR: $message');
        if (error != null) {
          print('   Error: $error');
        }
        print('   [Framework internal error - subsequent similar errors suppressed]');
        _errorHistory[errorSignature] = DateTime.now();
        _errorCounts[errorSignature] = 1;
      } else {
        _errorCounts[errorSignature] = (_errorCounts[errorSignature] ?? 0) + 1;
      }
      return;
    }
    
    // For non-filtered errors, check throttling
    if (!_shouldLog(errorSignature)) {
      return;
    }
    
    // Log the error
    final count = _errorCounts[errorSignature] ?? 0;
    if (count > 0) {
      print('❌ ERROR: $message [Repeated ${count + 1}x]');
    } else {
      print('❌ ERROR: $message');
    }
    
    if (error != null) {
      print('   Error: $error');
    }
    
    // Only print full stack trace for first occurrence or critical errors
    if (stackTrace != null && (count == 0 || _isCriticalError(message))) {
      print('   StackTrace: ${_getRelevantStackTrace(stackTrace)}');
      developer.log(
        message,
        name: 'Logger',
        error: error,
        stackTrace: stackTrace,
        level: 1000, // Error level
      );
    }
    
    // Update history
    _errorHistory[errorSignature] = DateTime.now();
    _errorCounts[errorSignature] = (count + 1);
  }

  static void performance(String operation, Duration duration) {
    if (kDebugMode) {
      final ms = duration.inMilliseconds;
      final emoji = ms > 5000 ? '🐌' : ms > 2000 ? '⏱️' : '⚡';
      print('$emoji PERFORMANCE: $operation took ${ms}ms');
    }
  }

  static T? safeExecute<T>(
    String operation,
    T Function() fn, {
    T? defaultValue,
    bool logError = true,
  }) {
    try {
      final stopwatch = Stopwatch()..start();
      final result = fn();
      stopwatch.stop();
      performance(operation, stopwatch.elapsed);
      return result;
    } catch (e, stackTrace) {
      if (logError) {
        error('Failed to execute: $operation', e, stackTrace);
      }
      return defaultValue;
    }
  }

  static Future<T?> safeExecuteAsync<T>(
    String operation,
    Future<T> Function() fn, {
    T? defaultValue,
    bool logError = true,
  }) async {
    try {
      final stopwatch = Stopwatch()..start();
      final result = await fn();
      stopwatch.stop();
      performance(operation, stopwatch.elapsed);
      return result;
    } catch (e, stackTrace) {
      if (logError) {
        error('Failed to execute async: $operation', e, stackTrace);
      }
      return defaultValue;
    }
  }

  /// Clear error history (useful for testing or after fixing issues)
  static void clearErrorHistory() {
    _errorHistory.clear();
    _errorCounts.clear();
  }

  /// Get error statistics
  static Map<String, int> getErrorStats() {
    return Map.unmodifiable(_errorCounts);
  }

  // Private helper methods

  static String _createErrorSignature(String message, Object? error) {
    // Create a signature from the error message and type
    final errorType = error?.runtimeType.toString() ?? 'Unknown';
    final messageHash = message.length > 100 
        ? message.substring(0, 100) 
        : message;
    return '$errorType|$messageHash';
  }

  static bool _isFilteredError(String message, Object? error) {
    final fullMessage = '$message ${error?.toString() ?? ''}';
    return _filteredPatterns.any((pattern) => pattern.hasMatch(fullMessage));
  }

  static bool _isCriticalError(String message) {
    // Define what constitutes a critical error
    final criticalPatterns = [
      'FATAL',
      'Crash',
      'NullPointerException',
      'OutOfMemoryError',
      'Firebase',
      'Authentication',
      'Permission denied',
    ];
    return criticalPatterns.any((pattern) => 
        message.toUpperCase().contains(pattern.toUpperCase()));
  }

  static bool _shouldLog(String signature, {bool isWarning = false}) {
    final now = DateTime.now();
    final lastSeen = _errorHistory[signature];
    final count = _errorCounts[signature] ?? 0;
    
    // If we've seen this error too many times, stop logging
    if (count >= _maxErrorRepeats) {
      return false;
    }
    
    // If we've never seen it, log it
    if (lastSeen == null) {
      return true;
    }
    
    // If enough time has passed since last log, log again
    final timeSinceLastLog = now.difference(lastSeen);
    final throttleDuration = isWarning 
        ? _errorThrottleDuration * 2 
        : _errorThrottleDuration;
    
    return timeSinceLastLog >= throttleDuration;
  }

  static String _getRelevantStackTrace(StackTrace stackTrace) {
    // Extract only relevant parts of stack trace (first 10 lines)
    final lines = stackTrace.toString().split('\n');
    final relevantLines = lines.take(10).join('\n');
    if (lines.length > 10) {
      return '$relevantLines\n   ... (${lines.length - 10} more lines)';
    }
    return relevantLines;
  }
}
