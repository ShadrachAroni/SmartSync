import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/settings_provider.dart';

class AlertSettingsScreen extends ConsumerStatefulWidget {
  const AlertSettingsScreen({super.key});

  @override
  ConsumerState<AlertSettingsScreen> createState() =>
      _AlertSettingsScreenState();
}

class _AlertSettingsScreenState extends ConsumerState<AlertSettingsScreen> {
  bool _autoAcknowledge = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final storage = ref.read(storageServiceProvider);
    await storage.initialize();
    setState(() {
      _autoAcknowledge =
          storage.getBool('alerts.auto_ack', defaultValue: false);
    });
  }

  Future<void> _save(bool value) async {
    final storage = ref.read(storageServiceProvider);
    await storage.saveBool('alerts.auto_ack', value);
    setState(() => _autoAcknowledge = value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Alert Settings')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          SwitchListTile(
            title: const Text('Auto acknowledge low alerts'),
            subtitle:
                const Text('Mark low severity alerts as read automatically'),
            value: _autoAcknowledge,
            onChanged: _save,
          ),
        ],
      ),
    );
  }
}
