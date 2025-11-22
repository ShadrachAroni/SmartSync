import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

/// Success indicator using Lottie animation
class LottieSuccessIndicator extends StatelessWidget {
  final double size;
  final String? message;

  const LottieSuccessIndicator({
    super.key,
    this.size = 100,
    this.message,
  });

  @override
  Widget build(BuildContext context) {
    Widget successWidget = SizedBox(
      width: size,
      height: size,
      child: Lottie.asset(
        'assets/animations/success.json',
        fit: BoxFit.contain,
        repeat: false,
      ),
    );

    if (message != null) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          successWidget,
          const SizedBox(height: 16),
          Text(
            message!,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      );
    }

    return successWidget;
  }
}

