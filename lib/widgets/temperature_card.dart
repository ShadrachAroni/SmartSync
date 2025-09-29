import 'package:flutter/material.dart';
import 'package:percent_indicator/percent_indicator.dart';

class TemperatureCard extends StatelessWidget {
  final double temperature;
  const TemperatureCard({super.key, required this.temperature});

  @override
  Widget build(BuildContext context) {
    final t = temperature.clamp(0.0, 50.0);
    final percent = (t / 50).clamp(0.0, 1.0);
    final color = Color.lerp(Colors.blue, Colors.red, percent)!;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            CircularPercentIndicator(
              radius: 54,
              lineWidth: 10,
              percent: percent,
              center: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('${t.round()}°',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    const Text('Room')
                  ]),
              progressColor: color,
              circularStrokeCap: CircularStrokeCap.round,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Room Temperature',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Text(
                        'Live temperature from the sensor — updated in real time',
                        style: TextStyle(color: Colors.grey.shade600)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.thermostat, color: color),
                        const SizedBox(width: 8),
                        Text('${t.toStringAsFixed(1)}°C',
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold)),
                        const Spacer(),
                        Text(percent < 0.5 ? 'Cool' : 'Warm',
                            style: TextStyle(color: color)),
                      ],
                    ),
                  ]),
            ),
          ],
        ),
      ),
    );
  }
}
