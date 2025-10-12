import 'dart:async';
import 'package:flutter/material.dart';
import '../../../services/ble_service.dart';
import '../../../services/log_service.dart';

class SecurityTab extends StatefulWidget {
  const SecurityTab({super.key});
  @override
  State<SecurityTab> createState() => _SecurityTabState();
}

class _SecurityTabState extends State<SecurityTab> {
  bool pir = false;
  bool ultra = false;
  bool armed = false;

  StreamSubscription<bool>? _pirSub;
  StreamSubscription<bool>? _ultraSub;

  @override
  void initState() {
    super.initState();
    _pirSub = BLEService().pirStream.stream.listen((v) {
      if (!mounted) return;
      setState(() => pir = v);
    });
    _ultraSub = BLEService().ultraStream.stream.listen((v) {
      if (!mounted) return;
      setState(() => ultra = v);
    });
  }

  @override
  void dispose() {
    _pirSub?.cancel();
    _ultraSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final alert = armed && (pir || ultra);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SwitchListTile(
          value: armed,
          title: const Text('Alarm armed'),
          onChanged: (v) async {
            setState(() => armed = v);
            await BLEService().setAlarm(v);
            await LogService.add('Alarm ${v ? "armed" : "disarmed"}');
          },
        ),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading:
                Icon(pir ? Icons.motion_photos_on : Icons.motion_photos_off),
            title: const Text('PIR motion'),
            trailing: Text(
              pir ? 'DETECTED' : 'Idle',
              style: TextStyle(color: pir ? Colors.red : null),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Card(
          child: ListTile(
            leading: Icon(ultra ? Icons.sensors : Icons.sensors_off),
            title: const Text('Ultrasonic proximity'),
            trailing: Text(
              ultra ? 'DETECTED' : 'Clear',
              style: TextStyle(color: ultra ? Colors.red : null),
            ),
          ),
        ),
        if (alert)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: const ListTile(
                leading: Icon(Icons.warning_amber),
                title: Text('Intrusion detected!'),
              ),
            ),
          ),
      ],
    );
  }
}
