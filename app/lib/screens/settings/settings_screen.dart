import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/settings_provider.dart';
import '../../providers/auth_provider.dart';
import 'notifications_settings.dart';
import 'profile_screen.dart';
import 'privacy_settings.dart';
import 'about_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsControllerProvider);
    final user = ref.watch(authStateProvider).value;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _buildSectionHeader('Account'),
          _buildNavTile(
            context,
            icon: Icons.person_outline,
            title: 'Profile',
            subtitle: 'Name, contact, caregivers',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ProfileScreen()),
            ),
          ),
          const SizedBox(height: 24),
          _buildSectionHeader('Notifications'),
          SwitchListTile(
            title: const Text('Push Notifications'),
            subtitle: const Text('Critical alerts and reminders'),
            value: settings.notificationsEnabled,
            onChanged: user == null
                ? null
                : (value) => ref
                    .read(settingsControllerProvider.notifier)
                    .toggleNotifications(user.uid, value),
          ),
          SwitchListTile(
            title: const Text('Caregiver Alerts'),
            subtitle: const Text('Share emergencies with caregivers'),
            value: settings.caregiverAlerts,
            onChanged: (value) => ref
                .read(settingsControllerProvider.notifier)
                .toggleCaregiverAlerts(value),
          ),
          _buildNavTile(
            context,
            icon: Icons.notifications_active_outlined,
            title: 'Notification Preferences',
            subtitle: 'Customize alert types',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const NotificationSettingsScreen()),
            ),
          ),
          const SizedBox(height: 24),
          _buildSectionHeader('Automation'),
          SwitchListTile(
            title: const Text('Adaptive Auto Mode'),
            subtitle: const Text('Let AI adjust fan and lights'),
            value: settings.autoMode,
            onChanged: (value) => ref
                .read(settingsControllerProvider.notifier)
                .setAutoMode(value),
          ),
          const SizedBox(height: 24),
          _buildSectionHeader('Legal'),
          _buildNavTile(
            context,
            icon: Icons.lock_outline,
            title: 'Privacy & Security',
            subtitle: 'Policies and permissions',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PrivacySettingsScreen()),
            ),
          ),
          _buildNavTile(
            context,
            icon: Icons.info_outline,
            title: 'About SmartSync',
            subtitle: 'Version, licenses, feedback',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AboutScreen()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Colors.grey,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildNavTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: const Color(0xFF00BFA5).withOpacity(0.1),
        child: Icon(icon, color: const Color(0xFF00BFA5)),
      ),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
      onTap: onTap,
    );
  }
}
