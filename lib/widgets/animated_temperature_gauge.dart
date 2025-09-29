import 'package:flutter/material.dart';
import 'package:percent_indicator/percent_indicator.dart';

class AnimatedTemperatureGauge extends StatelessWidget {
  final int value; // 0 - 100

  const AnimatedTemperatureGauge({super.key, required this.value});

  @override
  Widget build(BuildContext context) {
    final percent = (value.clamp(0, 100) / 100.0);
    return Column(
      children: [
        CircularPercentIndicator(
          radius: 120.0,
          lineWidth: 14.0,
          percent: percent,
          center: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('$value\u00B0',
                  style: const TextStyle(
                      fontSize: 28, fontWeight: FontWeight.bold)),
              const Text('Room Temperature'),
            ],
          ),
          circularStrokeCap: CircularStrokeCap.round,
          animation: true,
        ),
      ],
    );
  }
}
