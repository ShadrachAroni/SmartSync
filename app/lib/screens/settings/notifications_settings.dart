import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/auth_provider.dart';
import '../../providers/settings_provider.dart';
import '../../core/widgets/app_notifications.dart';

class NotificationSettingsScreen extends ConsumerStatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  ConsumerState<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends ConsumerState<NotificationSettingsScreen> {
  final Map<String, String> _labels = const {
    'health': 'Health & inactivity alerts',
    'motion': 'Unusual motion',
    'battery': 'Low battery warnings',
    'firmware': 'Firmware updates',
  };

  final Map<String, bool> _prefs = {
    'health': true,
    'motion': true,
    'battery': true,
    'firmware': false,
  };

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final storage = ref.read(storageServiceProvider);
    await storage.initialize();
    for (final key in _prefs.keys) {
      _prefs[key] = storage.getBool('notifications.$key',
          defaultValue: _prefs[key] ?? true);
    }
    setState(() => _loading = false);
  }

  Future<void> _save() async {
    final user = ref.read(authStateProvider).value;
    if (user == null) return;
    final storage = ref.read(storageServiceProvider);
    for (final entry in _prefs.entries) {
      await storage.saveBool('notifications.${entry.key}', entry.value);
    }
    await ref
        .read(notificationServiceProvider)
        .updateAlertPreferences(user.uid, _prefs);
    if (!mounted) return;
    AppNotifications.showSnackBar(
      context,
      message: 'Notification preferences updated',
      type: AppNotificationType.success,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text('Save'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: _prefs.keys
                  .map(
                    (key) => SwitchListTile(
                      title: Text(_labels[key] ?? key),
                      value: _prefs[key] ?? true,
                      onChanged: (value) => setState(() => _prefs[key] = value),
                    ),
                  )
                  .toList(),
            ),
    );
  }
}
