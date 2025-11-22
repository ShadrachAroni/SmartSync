import 'package:flutter/foundation.dart';
import 'dart:developer' as developer;

class Logger {
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
    print('⚠️ WARNING: $message');
  }

  static void error(String message, [Object? error, StackTrace? stackTrace]) {
    print('❌ ERROR: $message');
    if (error != null) {
      print('   Error: $error');
    }
    if (stackTrace != null) {
      print('   StackTrace: $stackTrace');
      developer.log(
        message,
        name: 'Logger',
        error: error,
        stackTrace: stackTrace,
        level: 1000, // Error level
      );
    }
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
}
