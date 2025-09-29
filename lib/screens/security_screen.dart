import 'package:flutter/material.dart';
import '../services/supabase_service.dart';
import '../widgets/bottom_nav.dart'; // <-- added bottom nav

class SecurityScreen extends StatefulWidget {
  const SecurityScreen({super.key});

  @override
  State<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends State<SecurityScreen>
    with SingleTickerProviderStateMixin {
  bool alarmArmed = true;
  bool pirEnabled = true;
  bool ultrasonicEnabled = true;
  double sensitivity = 0.6;
  late final AnimationController _armController;

  @override
  void initState() {
    super.initState();
    _armController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    if (alarmArmed) _armController.forward();
  }

  @override
  void dispose() {
    _armController.dispose();
    super.dispose();
  }

  Future<void> _testAlarm() async {
    // Insert a log into supabase for demonstration
    await SupabaseService.insertLog(
        'Test alarm triggered at ${DateTime.now()}');
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Test alarm triggered')));
  }

  @override
  Widget build(BuildContext context) {
    final armColor = alarmArmed ? Colors.redAccent : Colors.green;

    return Scaffold(
      appBar: AppBar(title: const Text('Security')),
      bottomNavigationBar: const BottomNav(), // <-- added here
      body: Padding(
        padding: const EdgeInsets.all(18.0),
        child: Column(
          children: [
            // Animated arm/disarm card
            GestureDetector(
              onTap: () {
                setState(() {
                  alarmArmed = !alarmArmed;
                  if (alarmArmed) {
                    _armController.forward();
                  } else {
                    _armController.reverse();
                  }
                });
              },
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(children: [
                    ScaleTransition(
                      scale: Tween(begin: 1.0, end: 1.04).animate(
                          CurvedAnimation(
                              parent: _armController, curve: Curves.easeInOut)),
                      child: Icon(Icons.lock, size: 46, color: armColor),
                    ),
                    const SizedBox(width: 14),
                    Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(alarmArmed ? 'Armed' : 'Disarmed',
                              style: const TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.bold)),
                          Text(
                              alarmArmed
                                  ? 'Home is secured'
                                  : 'System is offline',
                              style: const TextStyle(color: Colors.black54)),
                        ]),
                    const Spacer(),
                    Switch(
                        value: alarmArmed,
                        onChanged: (v) => setState(() => alarmArmed = v)),
                  ]),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Column(children: [
                SwitchListTile(
                  value: pirEnabled,
                  onChanged: (v) => setState(() => pirEnabled = v),
                  title: const Text('PIR Motion Sensor'),
                  subtitle: const Text('Detects motion in the monitored area'),
                ),
                SwitchListTile(
                  value: ultrasonicEnabled,
                  onChanged: (v) => setState(() => ultrasonicEnabled = v),
                  title: const Text('Ultrasonic Sensor'),
                  subtitle: const Text('Proximity readings for doors/windows'),
                ),
                ListTile(
                  leading: const Icon(Icons.tune),
                  title: const Text('Sensitivity'),
                  subtitle: Slider(
                      value: sensitivity,
                      onChanged: (v) => setState(() => sensitivity = v)),
                )
              ]),
            ),
            const SizedBox(height: 12),

            // place action button inside a safe region so it doesn't collide with bottom nav
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4.0),
              child: ElevatedButton.icon(
                  onPressed: _testAlarm,
                  icon: const Icon(Icons.alarm),
                  label: const Text('Test Alarm')),
            ),
            const SizedBox(height: 12),

            // make logs expand and have bottom padding to avoid being obscured by bottom nav
            Expanded(
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: SupabaseService.fetchLogs(),
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final logs = snap.data ?? [];
                  final alarmEvents = logs
                      .where((l) =>
                          (l['message'] ?? '')
                              .toString()
                              .toLowerCase()
                              .contains('alarm') ||
                          (l['message'] ?? '')
                              .toString()
                              .toLowerCase()
                              .contains('motion'))
                      .toList();
                  if (alarmEvents.isEmpty) {
                    return const Center(
                        child: Text('No recent security events'));
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.only(bottom: 18.0),
                    itemCount: alarmEvents.length,
                    separatorBuilder: (_, __) => const Divider(),
                    itemBuilder: (context, i) {
                      final l = alarmEvents[i];
                      return ListTile(
                        leading:
                            const Icon(Icons.warning, color: Colors.redAccent),
                        title: Text(l['message'] ?? 'Security event'),
                        subtitle: Text((l['created_at'] ?? '').toString()),
                      );
                    },
                  );
                },
              ),
            )
          ],
        ),
      ),
    );
  }
}
