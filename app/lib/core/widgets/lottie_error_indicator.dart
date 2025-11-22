import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

/// Error indicator using Lottie animation
class LottieErrorIndicator extends StatelessWidget {
  final double size;
  final String? message;

  const LottieErrorIndicator({
    super.key,
    this.size = 100,
    this.message,
  });

  @override
  Widget build(BuildContext context) {
    Widget errorWidget = SizedBox(
      width: size,
      height: size,
      child: Lottie.asset(
        'assets/animations/error-exclamation.json',
        fit: BoxFit.contain,
        repeat: false,
      ),
    );

    if (message != null) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          errorWidget,
          const SizedBox(height: 16),
          Text(
            message!,
            style: const TextStyle(
              color: Colors.red,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      );
    }

    return errorWidget;
  }
}

