import 'dart:math';
import 'package:flutter/material.dart';
import '../../services/automation_service.dart';
import '../../services/notification_service.dart';
import '../../services/ble_service.dart';
import '../../services/log_service.dart';

class AutomationScreen extends StatefulWidget {
  const AutomationScreen({super.key});
  @override
  State<AutomationScreen> createState() => _AutomationScreenState();
}

class _AutomationScreenState extends State<AutomationScreen> {
  List<AutomationRule> rules = [];

  @override
  void initState() {
    super.initState();
    rules = AutomationService.list();
  }

  @override
  Widget build(BuildContext context) {
    rules = AutomationService.list();
    return Scaffold(
      appBar: AppBar(title: const Text('Automation rules')),
      floatingActionButton: FloatingActionButton(
        onPressed: _addRule,
        child: const Icon(Icons.add),
      ),
      body: rules.isEmpty
          ? const Center(child: Text('No rules yet'))
          : ListView.builder(
              itemCount: rules.length,
              itemBuilder: (_, i) {
                final r = rules[i];
                final actionText = r.action.containsKey('fan')
                    ? 'Fan -> ${r.action['fan']}%'
                    : r.action.containsKey('bulb')
                        ? 'Bulb -> ${r.action['bulb']}%'
                        : r.action.containsKey('alarm')
                            ? 'Alarm -> ${r.action['alarm'] ? "ON" : "OFF"}'
                            : 'Custom';
                final when = r.at != null
                    ? '${r.daily ? "Every day" : "Once"} @ ${r.at!.hour.toString().padLeft(2, '0')}:${r.at!.minute.toString().padLeft(2, '0')}'
                    : '—';
                return Dismissible(
                  key: ValueKey(r.id),
                  background: Container(color: Colors.redAccent),
                  onDismissed: (_) async {
                    await AutomationService.remove(r.id);
                    setState(() {});
                  },
                  child: Card(
                    child: ListTile(
                      title: Text(r.name),
                      subtitle: Text('$actionText • $when'),
                      trailing: IconButton(
                        icon: const Icon(Icons.play_arrow),
                        onPressed: () async {
                          await _runAction(r.action);
                          await LogService.add('Manual run: ${r.name}');
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Executed ${r.name}')));
                        },
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }

  Future<void> _addRule() async {
    TimeOfDay? time =
        await showTimePicker(context: context, initialTime: TimeOfDay.now());
    if (time == null) return;

    String type = 'fan';
    int value = 50;
    bool alarm = false;
    bool daily = true;
    final name = TextEditingController(text: 'Rule ${Random().nextInt(999)}');

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 24,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: StatefulBuilder(builder: (context, setS) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Rule name')),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('Type'),
                  const SizedBox(width: 12),
                  DropdownButton<String>(
                    value: type,
                    items: const [
                      DropdownMenuItem(value: 'fan', child: Text('Fan')),
                      DropdownMenuItem(value: 'bulb', child: Text('Bulb')),
                      DropdownMenuItem(value: 'alarm', child: Text('Alarm')),
                    ],
                    onChanged: (v) => setS(() => type = v ?? 'fan'),
                  ),
                  const Spacer(),
                  SwitchListTile(
                    value: daily,
                    onChanged: (v) => setS(() => daily = v),
                    title: const Text('Repeat daily'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ),
              if (type != 'alarm') ...[
                const SizedBox(height: 8),
                Slider(
                  value: value.toDouble(),
                  onChanged: (v) => setS(() => value = v.round()),
                  min: 0,
                  max: 100,
                  divisions: 20,
                  label: '$value%',
                ),
              ] else
                SwitchListTile(
                  value: alarm,
                  onChanged: (v) => setS(() => alarm = v),
                  title: const Text('Alarm ON'),
                ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () async {
                  final now = DateTime.now();
                  final at = DateTime(
                      now.year, now.month, now.day, time.hour, time.minute);
                  final rule = AutomationRule(
                    id: DateTime.now().microsecondsSinceEpoch.toString(),
                    name: name.text.trim().isEmpty ? 'Rule' : name.text.trim(),
                    at: at,
                    daily: daily,
                    action: type == 'fan'
                        ? {'fan': value}
                        : type == 'bulb'
                            ? {'bulb': value}
                            : {'alarm': alarm},
                  );
                  await AutomationService.add(rule);
                  await NotificationService.scheduleOnce(
                    id: rule.id.hashCode & 0x7fffffff,
                    atLocal: at,
                    title: 'Automation scheduled',
                    body: rule.name,
                  );
                  if (Navigator.of(context).canPop()) {
                    Navigator.of(context).pop();
                  }
                  setState(() {});
                },
                child: const Text('Save rule'),
              ),
            ],
          );
        }),
      ),
    );
  }

  Future<void> _runAction(Map<String, dynamic> action) async {
    final ble = BLEService();
    if (action.containsKey('fan')) await ble.setFanSpeed(action['fan'] as int);
    if (action.containsKey('bulb')) {
      await ble.setBulbIntensity(action['bulb'] as int);
    }
    if (action.containsKey('alarm')) {
      await ble.setAlarm(action['alarm'] as bool);
    }
  }
}
