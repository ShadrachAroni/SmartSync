import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  String _version = '1.0.0';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      setState(() => _version = info.version);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('About SmartSync')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'SmartSync v$_version',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'SmartSync is an AI-powered home automation platform focused on elderly care. '
              'Sensors, firmware, and mobile apps work together to detect anomalies, run automations, '
              'and alert caregivers in real-time.',
            ),
            const SizedBox(height: 24),
            const Text(
              'Credits',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            const Text('• Firmware: ESP32 with NimBLE + RTOS scheduler'),
            const Text('• Mobile: Flutter + Firebase + Riverpod'),
            const Text('• ML: TensorFlow models served via Cloud Functions'),
          ],
        ),
      ),
    );
  }
}
