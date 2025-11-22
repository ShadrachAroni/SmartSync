import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'logger.dart';

/// Utilities for safe async operations
class AsyncUtils {
  /// Safely execute an async operation with timeout and error handling
  static Future<T?> safeExecuteAsync<T>({
    required Future<T> Function() operation,
    required String operationName,
    Duration timeout = const Duration(seconds: 10),
    T? defaultValue,
    bool logError = true,
  }) async {
    try {
      final stopwatch = Stopwatch()..start();
      final result = await operation().timeout(
        timeout,
        onTimeout: () {
          Logger.warning(
              '⏱️ $operationName: Timeout after ${timeout.inSeconds}s');
          return defaultValue as T;
        },
      );
      stopwatch.stop();
      if (stopwatch.elapsedMilliseconds > 1000) {
        Logger.performance(operationName, stopwatch.elapsed);
      }
      return result;
    } catch (e, stackTrace) {
      if (logError) {
        Logger.error('$operationName: Failed', e, stackTrace);
      }
      return defaultValue;
    }
  }

  /// Execute async operation on next frame to avoid blocking UI
  static Future<T?> executeOnNextFrame<T>({
    required Future<T> Function() operation,
    required String operationName,
  }) async {
    return await Future.microtask(() async {
      await Future.delayed(Duration.zero);
      return await safeExecuteAsync(
        operation: operation,
        operationName: operationName,
      );
    });
  }

  /// Debounce function calls
  static Timer? _debounceTimer;

  static void debounce({
    required VoidCallback callback,
    Duration delay = const Duration(milliseconds: 300),
  }) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(delay, callback);
  }

  /// Throttle function calls
  static DateTime? _lastThrottleCall;

  static bool throttle({
    required VoidCallback callback,
    Duration delay = const Duration(milliseconds: 500),
  }) {
    final now = DateTime.now();
    if (_lastThrottleCall == null ||
        now.difference(_lastThrottleCall!) >= delay) {
      _lastThrottleCall = now;
      callback();
      return true;
    }
    return false;
  }
}

/// Widget that prevents rebuilds during async operations
class AsyncSafeBuilder extends StatefulWidget {
  final Future<void> Function()? onInit;
  final Widget Function(BuildContext context, bool isLoading) builder;
  final Widget? loadingWidget;
  final String? operationName;

  const AsyncSafeBuilder({
    super.key,
    this.onInit,
    required this.builder,
    this.loadingWidget,
    this.operationName,
  });

  @override
  State<AsyncSafeBuilder> createState() => _AsyncSafeBuilderState();
}

class _AsyncSafeBuilderState extends State<AsyncSafeBuilder> {
  bool _isLoading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    if (widget.onInit != null) {
      _executeInit();
    } else {
      _isLoading = false;
    }
  }

  Future<void> _executeInit() async {
    try {
      await AsyncUtils.safeExecuteAsync(
        operation: widget.onInit!,
        operationName: widget.operationName ?? 'AsyncSafeBuilder',
        defaultValue: null,
      );
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = e;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return widget.loadingWidget ??
          const Center(
            child: CircularProgressIndicator(),
          );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red),
            const SizedBox(height: 8),
            Text('Error: $_error'),
          ],
        ),
      );
    }

    return widget.builder(context, false);
  }
}
