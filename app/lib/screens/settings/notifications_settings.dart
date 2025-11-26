import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../providers/auth_provider.dart';
import '../../providers/settings_provider.dart';
import '../../core/widgets/app_notifications.dart';
import '../../core/widgets/lottie_loading.dart';
import '../../services/logging_service.dart';
import '../../models/log_entry.dart';

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
    'health': false,
    'motion': false,
    'battery': false,
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
    final user = ref.read(authStateProvider).value;
    Map<String, bool> remotePrefs = {};

    if (user != null) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        final prefs =
            (doc.data()?['preferences']?['notifications']) as Map<String, dynamic>?;
        if (prefs != null) {
          remotePrefs = prefs.map(
            (key, value) => MapEntry(key, value == true),
          );
        }
      } catch (_) {
        // Ignore remote sync errors - UI will fallback to local cache.
      }
    }

    for (final key in _prefs.keys) {
      bool value = storage.getBool('notifications.$key',
          defaultValue: _prefs[key] ?? false);
      if (remotePrefs.containsKey(key)) {
        value = remotePrefs[key]!;
        await storage.saveBool('notifications.$key', value);
      }
      _prefs[key] = value;
    }

    setState(() => _loading = false);
  }

  Future<void> _save() async {
    final user = ref.read(authStateProvider).value;
    if (user == null) return;

    // Get previous preferences for logging
    final storage = ref.read(storageServiceProvider);
    final previousPrefs = <String, bool>{};
    for (final key in _prefs.keys) {
      previousPrefs[key] = storage.getBool('notifications.$key',
          defaultValue: _prefs[key] ?? false);
    }

    // Save new preferences
    for (final entry in _prefs.entries) {
      await storage.saveBool('notifications.${entry.key}', entry.value);
    }
    await ref
        .read(notificationServiceProvider)
        .updateAlertPreferences(user.uid, _prefs);

    // Log detailed changes
    final loggingService = LoggingService();
    final changes = <String, Map<String, dynamic>>{};
    for (final entry in _prefs.entries) {
      if (previousPrefs[entry.key] != entry.value) {
        changes[entry.key] = {
          'previous': previousPrefs[entry.key],
          'new': entry.value,
          'label': _labels[entry.key] ?? entry.key,
        };
      }
    }

    if (changes.isNotEmpty) {
      await loggingService.logAction(
        action: 'Notification Preferences Updated',
        category: 'settings',
        details:
            'Updated ${changes.length} notification preference(s): ${changes.keys.map((k) => _labels[k] ?? k).join(", ")}',
        metadata: {
          'setting': 'notification_preferences',
          'changes': changes,
          'allPreferences': _prefs,
          'actionType': 'notification_preferences_update',
          'timestamp': DateTime.now().toIso8601String(),
        },
        level: LogLevel.info,
      );
    }

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
          ? const Center(child: LottieLoading.medium())
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
