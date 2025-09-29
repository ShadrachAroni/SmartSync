import 'package:flutter/material.dart';
import '../services/supabase_service.dart';
import '../widgets/bottom_nav.dart'; // <-- added

class LogsScreen extends StatefulWidget {
  const LogsScreen({super.key});

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> {
  late Future<List<Map<String, dynamic>>> _logs;

  @override
  void initState() {
    super.initState();
    _logs = SupabaseService.fetchLogs();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Logs'),
      ),
      bottomNavigationBar: const BottomNav(), // <-- added
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _logs,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final logs = snap.data ?? [];
          if (logs.isEmpty) return const Center(child: Text('No logs yet'));
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: logs.length,
            separatorBuilder: (_, __) => const Divider(),
            itemBuilder: (context, i) {
              final l = logs[i];
              return ListTile(
                leading: const Icon(Icons.event_note),
                title: Text(l['message'] ?? 'Event'),
                subtitle: Text((l['created_at'] ?? '').toString()),
              );
            },
          );
        },
      ),
    );
  }
}
