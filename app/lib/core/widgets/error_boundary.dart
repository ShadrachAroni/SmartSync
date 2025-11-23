import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../utils/logger.dart';

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

    return Builder(
      builder: (context) {
        try {
          return widget.child;
        } catch (e, stackTrace) {
          // Defer error handling to avoid calling setState during build
          // Use microtask + postFrameCallback for extra safety
          Future.microtask(() {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _handleError(e, stackTrace);
            });
          });
          return widget.fallback ??
              const SizedBox.shrink();
        }
      },
    );
  }
}

