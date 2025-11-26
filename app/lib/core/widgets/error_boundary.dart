import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/foundation.dart';
import '../utils/logger.dart';
import '../utils/error_diagnostics.dart';
import '../utils/black_screen_diagnostic.dart';

/// Error boundary widget that catches errors during widget building
class ErrorBoundary extends StatefulWidget {
  final Widget child;
  final Widget? fallback;
  final String? context;

  const ErrorBoundary({
    super.key,
    required this.child,
    this.fallback,
    this.context,
  });

  @override
  State<ErrorBoundary> createState() => _ErrorBoundaryState();
}

class _ErrorBoundaryState extends State<ErrorBoundary> {
  bool _hasError = false;
  Object? _error;
  // ignore: unused_field
  StackTrace? _stackTrace; // Used for logging in _handleError

  void _handleError(Object error, StackTrace? stackTrace) {
    if (!mounted) return;
    
    // Track error for black screen diagnostics
    BlackScreenDiagnostic.logWidgetBuild(
      widget.context ?? 'unknown',
      success: false,
      error: error,
    );
    
    // Track error for diagnostics
    ErrorDiagnostics.captureError(
      category: 'widget_build',
      message: 'ErrorBoundary caught widget build error${widget.context != null ? " (${widget.context})" : ""}',
      error: error,
      stackTrace: stackTrace,
      context: {
        'context': widget.context ?? 'unknown',
        'widgetType': widget.child.runtimeType.toString(),
      },
    );
    
    // Always defer setState to after the current build phase
    // This prevents "setState() called during build" errors
    // Use microtask to ensure it runs even if called during build
    Future.microtask(() {
      if (mounted) {
        // Double-check we're not in a build phase
        SchedulerBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {
              _hasError = true;
              _error = error;
              _stackTrace = stackTrace;
            });
          }
        });
      }
    });
    
    Logger.error(
      'ErrorBoundary${widget.context != null ? " (${widget.context})" : ""}: Widget build error',
      error,
      stackTrace,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return widget.fallback ??
          Container(
            padding: const EdgeInsets.all(20),
            color: const Color(0xFF0A0E27),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.error_outline,
                    color: Colors.red,
                    size: 48,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Something went wrong',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _error?.toString() ?? 'Unknown error',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _hasError = false;
                        _error = null;
                        _stackTrace = null;
                      });
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00BFA5),
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          );
    }

    // Enhanced error catching: Wrap in multiple layers to catch all build errors
    return Builder(
      builder: (context) {
        try {
          // Log successful widget build
          BlackScreenDiagnostic.logWidgetBuild(
            widget.context ?? widget.child.runtimeType.toString(),
            success: true,
          );
          
          // Wrap child in additional error boundary for nested widget errors
          return _SafeWidgetBuilder(
            context: widget.context,
            onError: (error, stackTrace) {
              Future.microtask(() {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _handleError(error, stackTrace);
                });
              });
            },
            child: widget.child,
          );
        } catch (e, stackTrace) {
          // Log failed widget build
          BlackScreenDiagnostic.logWidgetBuild(
            widget.context ?? widget.child.runtimeType.toString(),
            success: false,
            error: e,
          );
          // Defer error handling to avoid calling setState during build
          Future.microtask(() {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _handleError(e, stackTrace);
            });
          });
          // Return a visible placeholder instead of empty widget to prevent black screen
          return widget.fallback ??
              Container(
                color: const Color(0xFF0A0E27),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const CircularProgressIndicator(
                        color: Color(0xFF00BFA5),
                      ),
                      const SizedBox(height: 16),
                      if (kDebugMode)
                        Text(
                          'Widget Error: ${widget.context ?? "unknown"}',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ),
              );
        }
      },
    );
  }
}

/// Internal widget builder that catches errors during widget construction
/// This provides an additional layer of error catching for nested widgets
class _SafeWidgetBuilder extends StatelessWidget {
  final String? context;
  final void Function(Object error, StackTrace stackTrace) onError;
  final Widget child;

  const _SafeWidgetBuilder({
    this.context,
    required this.onError,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    try {
      return child;
    } catch (e, stackTrace) {
      // Catch errors during build and report them
      BlackScreenDiagnostic.logWidgetBuild(
        this.context ?? child.runtimeType.toString(),
        success: false,
        error: e,
      );
      
      ErrorDiagnostics.captureError(
        category: 'widget_build_nested',
        message: 'Error in nested widget build${this.context != null ? " (${this.context})" : ""}',
        error: e,
        stackTrace: stackTrace,
        context: {
          'context': this.context ?? 'unknown',
          'widgetType': child.runtimeType.toString(),
        },
      );
      
      // Notify parent error boundary
      onError(e, stackTrace);
      
      // Return a safe fallback widget
      return Container(
        color: const Color(0xFF0A0E27),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(
                color: Color(0xFF00BFA5),
              ),
              const SizedBox(height: 16),
              if (kDebugMode)
                Text(
                  'Nested Widget Error: ${this.context ?? "unknown"}',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                ),
            ],
          ),
        ),
      );
    }
  }
}

