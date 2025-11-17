import 'package:flutter/material.dart';

class PrivacySettingsScreen extends StatelessWidget {
  const PrivacySettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Privacy & Security')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _buildTile(
            icon: Icons.shield_moon_outlined,
            title: 'Data Encryption',
            description:
                'All communication between the app, firmware, and cloud is encrypted using TLS 1.2+.',
          ),
          _buildTile(
            icon: Icons.lock_clock_outlined,
            title: 'Data Retention',
            description:
                'Sensor logs older than 90 days are automatically anonymized.',
          ),
          _buildTile(
            icon: Icons.privacy_tip_outlined,
            title: 'Permissions',
            description:
                'SmartSync only requests Bluetooth, Notifications, and Internet access.',
          ),
        ],
      ),
    );
  }

  Widget _buildTile({
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: ListTile(
        leading: Icon(icon, color: const Color(0xFF00BFA5)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(description),
      ),
    );
  }
}
