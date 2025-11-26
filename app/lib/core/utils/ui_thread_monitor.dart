import 'dart:async';
import 'package:flutter/scheduler.dart';
import 'logger.dart';
import 'error_diagnostics.dart';

/// Monitors UI thread for blocking and frame drops
class UIThreadMonitor {
  static Timer? _monitorTimer;
  static DateTime? _lastFrameTime;
  static int _frameDropCount = 0;
  static bool _isMonitoring = false;
  static final List<FrameDropEvent> _frameDropHistory = [];
  static const int _maxHistory = 50;
  static DateTime? _lastFrameLogTime; // Rate limiting for frame drop logs
  static DateTime? _lastHealthCheckLog; // Rate limiting for health check logs
  
  /// Start monitoring UI thread performance
  static void startMonitoring() {
    if (_isMonitoring) return;
    
    try {
      // Ensure SchedulerBinding is available
      final binding = SchedulerBinding.instance;
      
      _isMonitoring = true;
      
      // Monitor frame timing
      binding.addTimingsCallback(_onFrameTimings);
      
    // Periodic health check - less frequent to reduce overhead
    _monitorTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _checkUIHealth();
    });
      
      try {
        Logger.info('UI Thread Monitor: Started');
      } catch (_) {
        // Logger might not be ready - continue silently
      }
    } catch (e) {
      // If monitoring fails to start, don't crash the app
      try {
        Logger.warning('UI Thread Monitor: Failed to start: $e');
      } catch (_) {
        // Logger might not be ready - continue silently
      }
      _isMonitoring = false;
    }
  }
  
  /// Stop monitoring
  static void stopMonitoring() {
    if (!_isMonitoring) return;
    _isMonitoring = false;
    
    _monitorTimer?.cancel();
    _monitorTimer = null;
    try {
      SchedulerBinding.instance.removeTimingsCallback(_onFrameTimings);
    } catch (e) {
      // Binding might not be available - continue
    }
    
    try {
      Logger.info('UI Thread Monitor: Stopped');
    } catch (_) {
      // Logger might not be ready - continue silently
    }
  }
  
  /// Handle frame timing callbacks
  /// CRITICAL: This must be lightweight and non-blocking
  static void _onFrameTimings(List<FrameTiming> timings) {
    // Keep this callback as fast as possible - defer heavy work
    try {
      for (final timing in timings) {
        final frameDuration = timing.totalSpan.inMilliseconds;
        final targetFrameTime = 16; // 60 FPS = 16ms per frame
        
        if (frameDuration > targetFrameTime * 2) {
          // Frame took more than 32ms - potential blocking
          _frameDropCount++;
          
          final event = FrameDropEvent(
            timestamp: DateTime.now(),
            frameDuration: frameDuration,
            targetDuration: targetFrameTime,
            dropPercentage: ((frameDuration - targetFrameTime) / targetFrameTime * 100),
          );
          
          // Only keep recent history - fast operation
          _frameDropHistory.add(event);
          if (_frameDropHistory.length > _maxHistory) {
            _frameDropHistory.removeAt(0);
          }
          
          // Defer heavy logging to avoid blocking UI thread
          if (frameDuration > 100) {
            // Schedule async logging to prevent blocking
            Future.microtask(() {
              try {
                // Rate limit: only log every 5 seconds to prevent spam
                final now = DateTime.now();
                if (_lastFrameLogTime == null || 
                    now.difference(_lastFrameLogTime!) > const Duration(seconds: 5)) {
                  _lastFrameLogTime = now;
                  
                  ErrorDiagnostics.captureError(
                    category: 'ui_performance',
                    message: 'Severe UI thread blocking detected',
                    context: {
                      'frameDuration': frameDuration,
                      'targetDuration': targetFrameTime,
                      'dropPercentage': event.dropPercentage.toStringAsFixed(1),
                      'consecutiveDrops': _frameDropCount,
                    },
                  );
                  
                  Logger.error(
                    '🚨 CRITICAL: UI thread blocked for ${frameDuration}ms '
                    '(${event.dropPercentage.toStringAsFixed(1)}% over target)',
                  );
                }
              } catch (_) {
                // Silently ignore logging errors to prevent cascading failures
              }
            });
          }
        } else {
          // Reset counter on good frame
          if (_frameDropCount > 0) {
            _frameDropCount = 0;
          }
        }
        
        _lastFrameTime = DateTime.now();
      }
    } catch (_) {
      // Silently ignore errors in frame callback to prevent UI blocking
    }
  }
  
  /// Periodic health check
  /// CRITICAL: Must be lightweight and non-blocking
  static void _checkUIHealth() {
    try {
      if (_lastFrameTime == null) return;
      
      final timeSinceLastFrame = DateTime.now().difference(_lastFrameTime!);
      
      // Rate limit: only check/log every 2 seconds to prevent spam
      final now = DateTime.now();
      final shouldLog = _lastHealthCheckLog == null || 
          now.difference(_lastHealthCheckLog!) > const Duration(seconds: 2);
      
      // If no frames for more than 1 second, UI might be frozen
      if (timeSinceLastFrame.inMilliseconds > 1000 && shouldLog) {
        _lastHealthCheckLog = now;
        
        // Defer heavy logging to prevent blocking
        Future.microtask(() {
          try {
            ErrorDiagnostics.captureError(
              category: 'ui_performance',
              message: 'UI thread appears frozen - no frames for ${timeSinceLastFrame.inSeconds}s',
              context: {
                'timeSinceLastFrame': timeSinceLastFrame.inMilliseconds,
                'frameDropCount': _frameDropCount,
              },
            );
            
            Logger.error(
              '🚨 CRITICAL: UI thread frozen - no frames for ${timeSinceLastFrame.inSeconds}s',
            );
          } catch (_) {
            // Silently ignore logging errors
          }
        });
      }
      
      // Check for excessive frame drops (lightweight check only)
      if (_frameDropCount > 10 && shouldLog) {
        Future.microtask(() {
          try {
            ErrorDiagnostics.captureError(
              category: 'ui_performance',
              message: 'Excessive frame drops detected',
              context: {
                'consecutiveDrops': _frameDropCount,
                'recentDrops': _frameDropHistory.length,
              },
            );
          } catch (_) {
            // Silently ignore
          }
        });
      }
    } catch (_) {
      // Silently ignore errors to prevent cascading failures
    }
  }
  
  /// Get performance summary
  static PerformanceSummary getSummary() {
    final recentDrops = _frameDropHistory.take(10).toList();
    final avgDrop = recentDrops.isEmpty 
        ? 0.0 
        : recentDrops.map((e) => e.dropPercentage).reduce((a, b) => a + b) / recentDrops.length;
    
    return PerformanceSummary(
      isMonitoring: _isMonitoring,
      frameDropCount: _frameDropCount,
      recentDrops: recentDrops.length,
      averageDropPercentage: avgDrop,
      lastFrameTime: _lastFrameTime,
    );
  }
  
  /// Clear history
  static void clear() {
    _frameDropHistory.clear();
    _frameDropCount = 0;
  }
}

class FrameDropEvent {
  final DateTime timestamp;
  final int frameDuration;
  final int targetDuration;
  final double dropPercentage;
  
  FrameDropEvent({
    required this.timestamp,
    required this.frameDuration,
    required this.targetDuration,
    required this.dropPercentage,
  });
}

class PerformanceSummary {
  final bool isMonitoring;
  final int frameDropCount;
  final int recentDrops;
  final double averageDropPercentage;
  final DateTime? lastFrameTime;
  
  PerformanceSummary({
    required this.isMonitoring,
    required this.frameDropCount,
    required this.recentDrops,
    required this.averageDropPercentage,
    this.lastFrameTime,
  });
}

