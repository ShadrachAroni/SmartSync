import 'package:flutter/foundation.dart' show kDebugMode;
import 'dart:developer' as developer;
import 'logger.dart';

/// Advanced error diagnostics system for pinpointing issues
class ErrorDiagnostics {
  static final Map<String, ErrorInfo> _errorHistory = {};
  static final List<DiagnosticReport> _reports = [];
  static const int _maxReports = 50;
  
  /// Capture detailed error information
  static void captureError({
    required String category,
    required String message,
    Object? error,
    StackTrace? stackTrace,
    Map<String, dynamic>? context,
  }) {
    final errorId = _generateErrorId(category, message);
    final now = DateTime.now();
    
    // Get widget info from context if provided
    String? widgetInfo;
    if (context != null && context.containsKey('widgetDiagnostics')) {
      widgetInfo = context['widgetDiagnostics'] as String?;
    }
    
    final errorInfo = ErrorInfo(
      id: errorId,
      category: category,
      message: message,
      error: error?.toString(),
      stackTrace: stackTrace?.toString(),
      context: context ?? {},
      widgetInfo: widgetInfo,
      timestamp: now,
      count: (_errorHistory[errorId]?.count ?? 0) + 1,
    );
    
    _errorHistory[errorId] = errorInfo;
    
    // Create diagnostic report
    final report = DiagnosticReport(
      errorId: errorId,
      category: category,
      message: message,
      severity: _determineSeverity(category, message),
      timestamp: now,
      context: {
        ...(context ?? {}),
        if (widgetInfo != null) 'widget': widgetInfo,
        if (error != null) 'errorType': error.runtimeType.toString(),
      },
    );
    
    _reports.add(report);
    if (_reports.length > _maxReports) {
      _reports.removeAt(0);
    }
    
    // Log critical errors immediately
    if (report.severity == ErrorSeverity.critical) {
      _logCriticalError(errorInfo, report);
    }
  }
  
  // Removed unused _analyzeWidget method
  
  /// Determine error severity
  static ErrorSeverity _determineSeverity(String category, String message) {
    final lowerMessage = message.toLowerCase();
    
    // Critical errors
    if (category == 'layout' || 
        lowerMessage.contains('boxconstraints') ||
        lowerMessage.contains('infinite width') ||
        lowerMessage.contains('hasSize') ||
        lowerMessage.contains('not laid out')) {
      return ErrorSeverity.critical;
    }
    
    // High severity
    if (category == 'bluetooth' && 
        (lowerMessage.contains('parse') || 
         lowerMessage.contains('decode') ||
         lowerMessage.contains('sensor'))) {
      return ErrorSeverity.high;
    }
    
    // Medium severity
    if (category == 'firestore' || category == 'network') {
      return ErrorSeverity.medium;
    }
    
    return ErrorSeverity.low;
  }
  
  /// Log critical errors with full details
  /// CRITICAL: Defer heavy logging to prevent UI blocking
  static void _logCriticalError(ErrorInfo errorInfo, DiagnosticReport report) {
    // Defer all logging to microtask to prevent blocking UI thread
    Future.microtask(() {
      try {
        Logger.error(
          '🔴 CRITICAL ERROR [${errorInfo.category}]: ${errorInfo.message}',
          errorInfo.error != null ? errorInfo.error : null,
          errorInfo.stackTrace != null 
              ? StackTrace.fromString(errorInfo.stackTrace!) 
              : null,
        );
        
        // Only print detailed diagnostics in debug mode to reduce overhead
        if (kDebugMode) {
          print('═══════════════════════════════════════════════════════════');
          print('🔍 DIAGNOSTIC REPORT');
          print('═══════════════════════════════════════════════════════════');
          print('Category: ${errorInfo.category}');
          print('Message: ${errorInfo.message}');
          print('Occurrences: ${errorInfo.count}');
          print('Timestamp: ${errorInfo.timestamp}');
          
          if (errorInfo.widgetInfo != null) {
            print('\n📱 Widget Analysis:');
            print(errorInfo.widgetInfo);
          }
          
          if (errorInfo.context.isNotEmpty) {
            print('\n📋 Context:');
            errorInfo.context.forEach((key, value) {
              print('  $key: $value');
            });
          }
          
          if (errorInfo.stackTrace != null) {
            print('\n📚 Stack Trace (first 20 lines):');
            final lines = errorInfo.stackTrace!.split('\n');
            for (var i = 0; i < lines.length && i < 20; i++) {
              print('  ${lines[i]}');
            }
            if (lines.length > 20) {
              print('  ... (${lines.length - 20} more lines)');
            }
          }
          
          print('═══════════════════════════════════════════════════════════\n');
        }
        
        // Send to developer log (async, non-blocking)
        developer.log(
          errorInfo.message,
          name: 'ErrorDiagnostics',
          error: errorInfo.error,
          stackTrace: errorInfo.stackTrace != null 
              ? StackTrace.fromString(errorInfo.stackTrace!) 
              : null,
          level: 1000,
        );
      } catch (_) {
        // Silently ignore logging errors to prevent cascading failures
      }
    });
  }
  
  /// Generate unique error ID
  static String _generateErrorId(String category, String message) {
    // Create ID from category and first 50 chars of message
    final messageHash = message.length > 50 
        ? message.substring(0, 50).replaceAll(RegExp(r'[^\w]'), '_')
        : message.replaceAll(RegExp(r'[^\w]'), '_');
    return '${category}_$messageHash';
  }
  
  /// Get diagnostic summary
  static DiagnosticSummary getSummary() {
    final critical = _reports.where((r) => r.severity == ErrorSeverity.critical).length;
    final high = _reports.where((r) => r.severity == ErrorSeverity.high).length;
    final medium = _reports.where((r) => r.severity == ErrorSeverity.medium).length;
    final low = _reports.where((r) => r.severity == ErrorSeverity.low).length;
    
    // Group by category
    final byCategory = <String, int>{};
    for (var report in _reports) {
      byCategory[report.category] = (byCategory[report.category] ?? 0) + 1;
    }
    
    return DiagnosticSummary(
      totalErrors: _reports.length,
      critical: critical,
      high: high,
      medium: medium,
      low: low,
      byCategory: byCategory,
      recentErrors: _reports.take(10).toList(),
    );
  }
  
  /// Clear all diagnostics
  static void clear() {
    _errorHistory.clear();
    _reports.clear();
  }
  
  /// Get all error history
  static Map<String, ErrorInfo> getErrorHistory() {
    return Map.unmodifiable(_errorHistory);
  }
}

enum ErrorSeverity {
  critical,
  high,
  medium,
  low,
}

class ErrorInfo {
  final String id;
  final String category;
  final String message;
  final String? error;
  final String? stackTrace;
  final Map<String, dynamic> context;
  final String? widgetInfo;
  final DateTime timestamp;
  final int count;
  
  ErrorInfo({
    required this.id,
    required this.category,
    required this.message,
    this.error,
    this.stackTrace,
    required this.context,
    this.widgetInfo,
    required this.timestamp,
    required this.count,
  });
}

class DiagnosticReport {
  final String errorId;
  final String category;
  final String message;
  final ErrorSeverity severity;
  final DateTime timestamp;
  final Map<String, dynamic> context;
  
  DiagnosticReport({
    required this.errorId,
    required this.category,
    required this.message,
    required this.severity,
    required this.timestamp,
    required this.context,
  });
}

class DiagnosticSummary {
  final int totalErrors;
  final int critical;
  final int high;
  final int medium;
  final int low;
  final Map<String, int> byCategory;
  final List<DiagnosticReport> recentErrors;
  
  DiagnosticSummary({
    required this.totalErrors,
    required this.critical,
    required this.high,
    required this.medium,
    required this.low,
    required this.byCategory,
    required this.recentErrors,
  });
}

