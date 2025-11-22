import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'dart:async';
import 'dart:ui' show PlatformDispatcher;
import '../utils/logger.dart';
import 'error_boundary.dart';

/// Global error handler for the app
class AppErrorHandler {
  static void initialize() {
    // Handle Flutter framework errors
    FlutterError.onError = (FlutterErrorDetails details) {
      final message = 'Flutter Framework Error: ${details.exception}';
      if (details.stack != null) {
        print('❌ ERROR: $message');
        print('   Error: ${details.exception}');
        print('   StackTrace: ${details.stack}');
      } else {
        Logger.error(message);
      }
      FlutterError.presentError(details);
    };

    // Handle async errors
    PlatformDispatcher.instance.onError = (error, stack) {
      print('❌ ERROR: Platform Error: $error');
      print('   Error: $error');
      print('   StackTrace: $stack');
      return true; // Handled
    };
  }

  /// Wrap a widget with error boundary
  static Widget wrapWithErrorBoundary(
    Widget child, {
    String? context,
    Widget? fallback,
  }) {
    return ErrorBoundary(
      context: context ?? 'App',
      fallback: fallback,
      child: child,
    );
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
