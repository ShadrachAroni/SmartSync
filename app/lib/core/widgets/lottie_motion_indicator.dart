import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

/// Motion detection indicator using Lottie animation
class LottieMotionIndicator extends StatelessWidget {
  final bool motionDetected;
  final double size;

  const LottieMotionIndicator({
    super.key,
    required this.motionDetected,
    this.size = 48,
  });

  @override
  Widget build(BuildContext context) {
    if (!motionDetected) {
      // Show static icon when no motion
      return Icon(
        Icons.directions_walk_rounded,
        size: size,
        color: Colors.grey,
      );
    }

    // Show animated motion when detected
    return SizedBox(
      width: size,
      height: size,
      child: Lottie.asset(
        'assets/animations/motion.json',
        fit: BoxFit.contain,
        repeat: true,
      ),
    );
  }
}

