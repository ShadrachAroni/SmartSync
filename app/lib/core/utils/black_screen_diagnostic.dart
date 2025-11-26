import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Diagnostic tool to track EXACTLY what causes black screen
class BlackScreenDiagnostic {
  static final List<DiagnosticEvent> _events = [];
  static const int _maxEvents = 100;
  static bool _isMonitoring = false;
  static DateTime? _lastFrameTime;
  static int _consecutiveFrameDrops = 0;

  /// Start monitoring for black screen causes
  static void startMonitoring() {
    if (_isMonitoring) return;
    
    try {
      // Ensure SchedulerBinding is available
      final binding = SchedulerBinding.instance;
      if (binding == null) {
        if (kDebugMode) {
          developer.log('🔍 BlackScreenDiagnostic: SchedulerBinding not available yet');
        }
        return;
      }
      
      _isMonitoring = true;
      _events.clear();

      // Monitor frame timing
      binding.addTimingsCallback(_onFrameTiming);

      // Monitor widget builds
      _logEvent('system', 'BlackScreenDiagnostic started');

      if (kDebugMode) {
        developer.log('🔍 BlackScreenDiagnostic: Started monitoring');
      }
    } catch (e) {
      // If monitoring fails to start, don't crash the app
      if (kDebugMode) {
        developer.log('🔍 BlackScreenDiagnostic: Failed to start: $e');
      }
    }
  }

  /// Stop monitoring
  static void stopMonitoring() {
    if (!_isMonitoring) return;
    _isMonitoring = false;

    try {
      SchedulerBinding.instance.removeTimingsCallback(_onFrameTiming);
    } catch (e) {
      // Ignore
    }

    if (kDebugMode) {
      developer.log('🔍 BlackScreenDiagnostic: Stopped monitoring');
    }
  }

  /// Log a diagnostic event
  static void _logEvent(String category, String message, {Map<String, dynamic>? data}) {
    final event = DiagnosticEvent(
      timestamp: DateTime.now(),
      category: category,
      message: message,
      data: data ?? {},
    );

    _events.add(event);
    if (_events.length > _maxEvents) {
      _events.removeAt(0);
    }

    if (kDebugMode) {
      developer.log(
        '🔍 [$category] $message',
        name: 'BlackScreenDiagnostic',
        error: data?['error'],
        stackTrace: data?['stackTrace'] != null
            ? StackTrace.fromString(data!['stackTrace'].toString())
            : null,
      );
    }
  }

  /// Log widget build event
  static void logWidgetBuild(String widgetName, {bool success = true, Object? error}) {
    _logEvent(
      'widget_build',
      success ? 'Widget built: $widgetName' : 'Widget build FAILED: $widgetName',
      data: error != null
          ? {
              'widget': widgetName,
              'error': error.toString(),
              'success': success,
            }
          : {
              'widget': widgetName,
              'success': success,
            },
    );
  }

  /// Log data processing event
  static void logDataProcessing(String event, {int? dataSize, Object? error}) {
    _logEvent(
      'data_processing',
      event,
      data: {
        if (dataSize != null) 'dataSize': dataSize,
        if (error != null) 'error': error.toString(),
      },
    );
  }

  /// Log Bluetooth event
  static void logBluetooth(String event, {String? deviceId, Object? error}) {
    _logEvent(
      'bluetooth',
      event,
      data: {
        if (deviceId != null) 'deviceId': deviceId,
        if (error != null) 'error': error.toString(),
      },
    );
  }

  /// Log UI thread blocking
  static void logUIBlocking(int durationMs, String reason) {
    _logEvent(
      'ui_blocking',
      'UI blocked for ${durationMs}ms',
      data: {
        'duration': durationMs,
        'reason': reason,
      },
    );
  }

  /// Handle frame timing
  static void _onFrameTiming(List<FrameTiming> timings) {
    for (final timing in timings) {
      final frameDuration = timing.totalSpan.inMilliseconds;
      final now = DateTime.now();

      if (frameDuration > 100) {
        // Frame took more than 100ms - potential blocking
        _consecutiveFrameDrops++;
        _logEvent(
          'frame_drop',
          'Frame took ${frameDuration}ms (target: 16ms)',
          data: {
            'duration': frameDuration,
            'consecutiveDrops': _consecutiveFrameDrops,
          },
        );
      } else {
        _consecutiveFrameDrops = 0;
      }

      // Check for frozen UI (no frames for >1s)
      if (_lastFrameTime != null) {
        final timeSinceLastFrame = now.difference(_lastFrameTime!);
        if (timeSinceLastFrame.inMilliseconds > 1000) {
          _logEvent(
            'ui_frozen',
            'UI frozen - no frames for ${timeSinceLastFrame.inSeconds}s',
            data: {
              'seconds': timeSinceLastFrame.inSeconds,
            },
          );
        }
      }

      _lastFrameTime = now;
    }
  }

  /// Get diagnostic report
  static DiagnosticReport getReport() {
    final widgetBuilds = _events.where((e) => e.category == 'widget_build').length;
    final widgetFailures = _events
        .where((e) => e.category == 'widget_build' && e.data['success'] == false)
        .length;
    final dataProcessing = _events.where((e) => e.category == 'data_processing').length;
    final bluetoothEvents = _events.where((e) => e.category == 'bluetooth').length;
    final uiBlocking = _events.where((e) => e.category == 'ui_blocking').length;
    final frameDrops = _events.where((e) => e.category == 'frame_drop').length;
    final uiFrozen = _events.where((e) => e.category == 'ui_frozen').length;

    return DiagnosticReport(
      totalEvents: _events.length,
      widgetBuilds: widgetBuilds,
      widgetFailures: widgetFailures,
      dataProcessingEvents: dataProcessing,
      bluetoothEvents: bluetoothEvents,
      uiBlockingEvents: uiBlocking,
      frameDrops: frameDrops,
      uiFrozenEvents: uiFrozen,
      recentEvents: _events.take(20).toList(),
      failureEvents: _events
          .where((e) => e.data.containsKey('error') || e.data['success'] == false)
          .take(10)
          .toList(),
    );
  }

  /// Print full diagnostic report
  static void printReport() {
    final report = getReport();
    
    print('\n═══════════════════════════════════════════════════════════');
    print('🔍 BLACK SCREEN DIAGNOSTIC REPORT');
    print('═══════════════════════════════════════════════════════════');
    print('Total Events: ${report.totalEvents}');
    print('Widget Builds: ${report.widgetBuilds} (${report.widgetFailures} failed)');
    print('Data Processing Events: ${report.dataProcessingEvents}');
    print('Bluetooth Events: ${report.bluetoothEvents}');
    print('UI Blocking Events: ${report.uiBlockingEvents}');
    print('Frame Drops: ${report.frameDrops}');
    print('UI Frozen Events: ${report.uiFrozenEvents}');
    print('\n📋 Recent Events (last 20):');
    for (var event in report.recentEvents) {
      print('  [${event.timestamp}] ${event.category}: ${event.message}');
    }
    print('\n❌ Failure Events (last 10):');
    for (var event in report.failureEvents) {
      print('  [${event.timestamp}] ${event.category}: ${event.message}');
      if (event.data.containsKey('error')) {
        print('    Error: ${event.data['error']}');
      }
    }
    print('═══════════════════════════════════════════════════════════\n');
  }

  /// Clear all events
  static void clear() {
    _events.clear();
    _consecutiveFrameDrops = 0;
    _lastFrameTime = null;
  }
}

class DiagnosticEvent {
  final DateTime timestamp;
  final String category;
  final String message;
  final Map<String, dynamic> data;

  DiagnosticEvent({
    required this.timestamp,
    required this.category,
    required this.message,
    required this.data,
  });
}

class DiagnosticReport {
  final int totalEvents;
  final int widgetBuilds;
  final int widgetFailures;
  final int dataProcessingEvents;
  final int bluetoothEvents;
  final int uiBlockingEvents;
  final int frameDrops;
  final int uiFrozenEvents;
  final List<DiagnosticEvent> recentEvents;
  final List<DiagnosticEvent> failureEvents;

  DiagnosticReport({
    required this.totalEvents,
    required this.widgetBuilds,
    required this.widgetFailures,
    required this.dataProcessingEvents,
    required this.bluetoothEvents,
    required this.uiBlockingEvents,
    required this.frameDrops,
    required this.uiFrozenEvents,
    required this.recentEvents,
    required this.failureEvents,
  });
}

