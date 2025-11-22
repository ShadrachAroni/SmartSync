import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

/// Reusable Lottie loading widget
class LottieLoading extends StatelessWidget {
  final double? size;
  final String? message;
  final Color? messageColor;
  final bool showMessage;

  const LottieLoading({
    super.key,
    this.size,
    this.message,
    this.messageColor,
    this.showMessage = false,
  });

  /// Full screen loading with optional message
  const LottieLoading.fullScreen({
    super.key,
    this.size,
    this.message,
    this.messageColor,
    this.showMessage = true,
  });

  /// Small inline loading indicator
  const LottieLoading.small({
    super.key,
    this.size = 40,
    this.message,
    this.messageColor,
    this.showMessage = false,
  });

  /// Medium sized loading indicator
  const LottieLoading.medium({
    super.key,
    this.size = 80,
    this.message,
    this.messageColor,
    this.showMessage = false,
  });

  /// Large loading indicator
  const LottieLoading.large({
    super.key,
    this.size = 120,
    this.message,
    this.messageColor,
    this.showMessage = false,
  });

  @override
  Widget build(BuildContext context) {
    final defaultSize = size ?? 80.0;
    final defaultMessageColor = messageColor ?? Colors.white70;

    Widget loadingWidget = SizedBox(
      width: defaultSize,
      height: defaultSize,
      child: Lottie.asset(
        'assets/animations/loading.json',
        fit: BoxFit.contain,
        repeat: true,
        errorBuilder: (context, error, stackTrace) {
          // Fallback to CircularProgressIndicator if Lottie fails
          return SizedBox(
            width: defaultSize,
            height: defaultSize,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              valueColor: AlwaysStoppedAnimation<Color>(
                Colors.blue.shade300,
              ),
            ),
          );
        },
      ),
    );

    if (showMessage || message != null) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          loadingWidget,
          if (message != null) ...[
            const SizedBox(height: 16),
            Text(
              message!,
              style: TextStyle(
                color: defaultMessageColor,
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      );
    }

    return loadingWidget;
  }
}

