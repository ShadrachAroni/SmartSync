import 'package:flutter/material.dart';
import '../core/constants/colors.dart';

class TestScreen extends StatefulWidget {
  const TestScreen({super.key});

  @override
  State<TestScreen> createState() => _TestScreenState();
}

class _TestScreenState extends State<TestScreen> {
  double _fanSpeed = 50;
  double _ledBrightness = 75;
  bool _autoMode = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SmartSync Test'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Temperature Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Icon(Icons.thermostat,
                        size: 48, color: AppColors.temperature),
                    const SizedBox(height: 8),
                    const Text(
                      '24.5°C',
                      style:
                          TextStyle(fontSize: 36, fontWeight: FontWeight.bold),
                    ),
                    const Text(
                      'Temperature',
                      style: TextStyle(
                          fontSize: 18, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Fan Control Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Fan Control',
                          style: TextStyle(
                              fontSize: 22, fontWeight: FontWeight.bold),
                        ),
                        Switch(
                          value: _autoMode,
                          onChanged: (value) {
                            setState(() => _autoMode = value);
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '${_fanSpeed.round()}%',
                      style: const TextStyle(
                          fontSize: 32, fontWeight: FontWeight.bold),
                    ),
                    Slider(
                      value: _fanSpeed,
                      min: 0,
                      max: 100,
                      divisions: 20,
                      label: '${_fanSpeed.round()}%',
                      onChanged: (value) {
                        setState(() => _fanSpeed = value);
                      },
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // LED Control Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Light Control',
                      style:
                          TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '${_ledBrightness.round()}%',
                      style: const TextStyle(
                          fontSize: 32, fontWeight: FontWeight.bold),
                    ),
                    Slider(
                      value: _ledBrightness,
                      min: 0,
                      max: 100,
                      divisions: 20,
                      label: '${_ledBrightness.round()}%',
                      onChanged: (value) {
                        setState(() => _ledBrightness = value);
                      },
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // SOS Button
            ElevatedButton(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('SOS Alert Sent!'),
                    backgroundColor: AppColors.emergency,
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.emergency,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 70),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.emergency, size: 32),
                  SizedBox(width: 12),
                  Text('EMERGENCY HELP', style: TextStyle(fontSize: 24)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
