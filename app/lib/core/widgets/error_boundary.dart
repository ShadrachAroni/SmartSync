import 'package:flutter/material.dart';
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
  StackTrace? _stackTrace;

  @override
  void initState() {
    super.initState();
    // Catch Flutter framework errors
    FlutterError.onError = (FlutterErrorDetails details) {
      _handleError(details.exception, details.stack);
    };
  }

  void _handleError(Object error, StackTrace? stackTrace) {
    if (mounted) {
      setState(() {
        _hasError = true;
        _error = error;
        _stackTrace = stackTrace;
      });
      
      Logger.error(
        'ErrorBoundary${widget.context != null ? " (${widget.context})" : ""}: Widget build error',
        error,
        stackTrace,
      );
    }
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
          _handleError(e, stackTrace);
          return widget.fallback ??
              const SizedBox.shrink();
        }
      },
    );
  }
}

