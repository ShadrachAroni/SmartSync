import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'dart:async';
import 'dart:ui' show PlatformDispatcher;
import '../utils/logger.dart';
import '../utils/error_diagnostics.dart';
import 'error_boundary.dart';

/// Global error handler for the app with improved error filtering
class AppErrorHandler {
  static String? _lastErrorSignature;
  static DateTime? _lastErrorTime;
  static int _cascadingErrorCount = 0;
  static const int _maxCascadingErrors = 5;
  static const Duration _cascadingErrorWindow = Duration(seconds: 2);

  static void initialize() {
    // Handle Flutter framework errors with filtering
    FlutterError.onError = (FlutterErrorDetails details) {
      final exception = details.exception.toString();
      final errorSignature = _createErrorSignature(exception, details.stack);
      
      // Capture error for diagnostics
      // Extract widget info from context if available
      String? widgetInfo;
      if (details.context != null) {
        try {
          // Get widget information from diagnostics node
          widgetInfo = details.context!.toStringDeep();
        } catch (e) {
          widgetInfo = 'Error extracting widget info: $e';
        }
      }
      
      ErrorDiagnostics.captureError(
        category: 'layout',
        message: _getMainError(exception),
        error: details.exception,
        stackTrace: details.stack,
        context: {
          'library': details.library,
          'informationCollector': details.informationCollector != null ? 'present' : 'absent',
          if (widgetInfo != null) 'widgetDiagnostics': widgetInfo,
        },
      );
      
      // Check if this is a cascading error (same error repeating rapidly)
      if (_isCascadingError(errorSignature)) {
        _cascadingErrorCount++;
        if (_cascadingErrorCount <= _maxCascadingErrors) {
          // Log first few, then suppress
          Logger.error(
            'Flutter Framework Error: ${_getMainError(exception)}',
            details.exception,
            details.stack,
          );
        } else if (_cascadingErrorCount == _maxCascadingErrors + 1) {
          // Log a summary message
          print('❌ ERROR: [Suppressing ${_maxCascadingErrors}+ cascading framework errors]');
          print('   Main error: ${_getMainError(exception)}');
        }
        return;
      } else {
        // Reset counter for new error type
        _cascadingErrorCount = 0;
        _lastErrorSignature = errorSignature;
        _lastErrorTime = DateTime.now();
      }

      // Filter out known framework internal errors
      if (_shouldFilterError(exception)) {
        // Only log once with a note
        if (_cascadingErrorCount == 0) {
          Logger.error(
            'Flutter Framework Error: ${_getMainError(exception)}',
            details.exception,
            details.stack,
          );
        }
        return;
      }

      // Log important errors normally
      Logger.error(
        'Flutter Framework Error: ${_getMainError(exception)}',
        details.exception,
        details.stack,
      );
      
      // Still present error to user in debug mode
      if (kDebugMode) {
        FlutterError.presentError(details);
      }
    };

    // Handle async errors
    PlatformDispatcher.instance.onError = (error, stack) {
      final errorStr = error.toString();
      
      // Filter platform errors too
      if (!_shouldFilterError(errorStr)) {
        Logger.error('Platform Error: ${_getMainError(errorStr)}', error, stack);
      }
      
      return true; // Handled
    };
  }

  /// Wrap a widget with error boundary
  static Widget wrapWithErrorBoundary(
    Widget child, {
    String? context,
    Widget? fallback,
  }) {
    final contextName = context ?? 'App';
    // Create a unique key based on context and child type to prevent duplicates
    final childType = child.runtimeType.toString();
    return ErrorBoundary(
      key: ValueKey('ErrorBoundary_${contextName}_$childType'),
      context: contextName,
      fallback: fallback,
      child: child,
    );
  }

  // Private helper methods

  static String _createErrorSignature(String exception, StackTrace? stack) {
    // Create signature from exception type and first stack frame
    final exceptionType = exception.split(':').first;
    if (stack != null) {
      final stackLines = stack.toString().split('\n');
      if (stackLines.isNotEmpty) {
        final firstFrame = stackLines.first;
        return '$exceptionType|${firstFrame.substring(0, firstFrame.length.clamp(0, 50))}';
      }
    }
    return exceptionType;
  }

  static bool _isCascadingError(String signature) {
    if (_lastErrorSignature == signature && _lastErrorTime != null) {
      final timeSince = DateTime.now().difference(_lastErrorTime!);
      return timeSince < _cascadingErrorWindow;
    }
    return false;
  }

  static bool _shouldFilterError(String error) {
    // Filter patterns for framework internal errors
    final filterPatterns = [
      'RenderBox',
      'BoxConstraints',
      'hasSize',
      'relayoutBoundary',
      'Another exception was thrown',
      'package:flutter/src/rendering',
      'RenderFlex',
      'RenderPositionedBox',
      'RenderPadding',
      'RenderProxyBox',
      'RenderConstrainedBox',
    ];
    
    return filterPatterns.any((pattern) => 
        error.contains(pattern));
  }

  static String _getMainError(String error) {
    // Extract the main error message (first line or before first colon)
    final lines = error.split('\n');
    final firstLine = lines.first;
    
    // Try to extract meaningful part
    if (firstLine.contains(':')) {
      final parts = firstLine.split(':');
      if (parts.length > 1) {
        return parts.sublist(1).join(':').trim();
      }
    }
    
    // Limit length
    return firstLine.length > 150 
        ? '${firstLine.substring(0, 150)}...' 
        : firstLine;
  }
}

/// Frame rate monitor to detect performance issues
/// Lightweight implementation that doesn't block UI thread
class FrameRateMonitor {
  static final FrameRateMonitor _instance = FrameRateMonitor._internal();
  factory FrameRateMonitor() => _instance;
  FrameRateMonitor._internal();

  Timer? _monitorTimer;
  int _frameCount = 0;
  DateTime? _lastFrameTime;
  bool _isActive = false;
  bool _isMonitoring = false;
  int _consecutiveLowFpsCount = 0;
  DateTime? _lastWarningTime;
  double _cachedAverageFps = 60.0;

  bool get isMonitoring => _isMonitoring;

  void start() {
    if (_isMonitoring) return;
    _isActive = true;
    _isMonitoring = true;
    _lastFrameTime = DateTime.now();

    // Use a longer interval to reduce overhead
    _monitorTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!_isActive) {
        _frameCount = 0;
        return;
      }

      // Calculate fps based on actual time elapsed, not frame count
      final now = DateTime.now();
      if (_lastFrameTime == null) {
        _lastFrameTime = now;
        _frameCount = 0;
        return;
      }

      final elapsed = now.difference(_lastFrameTime!);
      if (elapsed.inMilliseconds == 0) {
        _frameCount = 0;
        return;
      }

      // Only check if we got frames
      if (_frameCount == 0) {
        // App might be paused - don't log
        _lastFrameTime = now;
        return;
      }

      // Calculate fps: frames per second
      final fps = (_frameCount / elapsed.inSeconds).round();

      // Update cached average (simple moving average)
      _cachedAverageFps = (_cachedAverageFps * 0.8) + (fps * 0.2);

      // Only warn if fps is consistently low
      if (fps < 30) {
        _consecutiveLowFpsCount++;
        // Only log warning every 30 seconds to prevent spam and reduce overhead
        final warningTime = DateTime.now();
        if (_lastWarningTime == null ||
            warningTime.difference(_lastWarningTime!) >=
                const Duration(seconds: 30)) {
          if (_consecutiveLowFpsCount >= 2) {
            // Use cached value to avoid expensive calculation
            Logger.warning(
                '⚠️ Low frame rate: $fps fps (avg: ${_cachedAverageFps.toStringAsFixed(1)})');
            _lastWarningTime = warningTime;
          }
        }
      } else {
        _consecutiveLowFpsCount = 0;
      }

      _frameCount = 0;
      _lastFrameTime = now;
    });

    // Schedule frame callback asynchronously to avoid blocking
    Future.microtask(() {
      if (_isMonitoring && _isActive) {
        _scheduleFrameCallback();
      }
    });
  }

  void _scheduleFrameCallback() {
    if (!_isActive || !_isMonitoring) return;

    try {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!_isActive || !_isMonitoring) return;

        _frameCount++;
        // Schedule next callback asynchronously to avoid blocking
        Future.microtask(() => _scheduleFrameCallback());
      });
    } catch (e) {
      // If scheduling fails, stop monitoring
      stop();
    }
  }

  void stop() {
    _isActive = false;
    _isMonitoring = false;
    _monitorTimer?.cancel();
    _monitorTimer = null;
    _frameCount = 0;
    _consecutiveLowFpsCount = 0;
    _lastWarningTime = null;
    _lastFrameTime = null;
  }

  void pause() {
    _isActive = false;
    _frameCount = 0;
  }

  void resume() {
    _isActive = true;
    _frameCount = 0;
    _consecutiveLowFpsCount = 0;
    _lastFrameTime = DateTime.now();
    // Restart frame callback scheduling
    if (_isMonitoring) {
      Future.microtask(() => _scheduleFrameCallback());
    }
  }

  double get averageFrameRate => _cachedAverageFps;
}

/// Widget that monitors frame rate and logs performance issues
/// Disabled by default to avoid performance overhead
class PerformanceMonitor extends StatefulWidget {
  final Widget child;
  final bool enabled;

  const PerformanceMonitor({
    super.key,
    required this.child,
    this.enabled = false, // Disabled by default to prevent hangs
  });

  @override
  State<PerformanceMonitor> createState() => _PerformanceMonitorState();
}

class _PerformanceMonitorState extends State<PerformanceMonitor>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    if (widget.enabled) {
      WidgetsBinding.instance.addObserver(this);
      // Delay start to avoid blocking initial render
      Future.microtask(() {
        if (mounted && widget.enabled) {
          FrameRateMonitor().start();
        }
      });
    }
  }

  @override
  void dispose() {
    if (widget.enabled) {
      WidgetsBinding.instance.removeObserver(this);
      FrameRateMonitor().stop();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final monitor = FrameRateMonitor();
    switch (state) {
      case AppLifecycleState.resumed:
        if (widget.enabled) {
          monitor.resume();
          if (!monitor.isMonitoring) {
            monitor.start();
          }
        }
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        monitor.pause();
        break;
      case AppLifecycleState.hidden:
        monitor.pause();
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
