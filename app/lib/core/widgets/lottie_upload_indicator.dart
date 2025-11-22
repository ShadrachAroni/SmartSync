import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

/// Upload progress indicator using Lottie animation
class LottieUploadIndicator extends StatelessWidget {
  final double size;
  final String? message;

  const LottieUploadIndicator({
    super.key,
    this.size = 80,
    this.message,
  });

  @override
  Widget build(BuildContext context) {
    Widget uploadWidget = SizedBox(
      width: size,
      height: size,
      child: Lottie.asset(
        'assets/animations/uploading.json',
        fit: BoxFit.contain,
        repeat: true,
      ),
    );

    if (message != null) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          uploadWidget,
          const SizedBox(height: 16),
          Text(
            message!,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      );
    }

    return uploadWidget;
  }
}

