// lib/screens/home/tabs/logs_tab.dart
import 'package:flutter/material.dart';
import '../../../services/log_service.dart';

class LogsTab extends StatefulWidget {
  const LogsTab({super.key});
  @override
  State<LogsTab> createState() => _LogsTabState();
}

class _LogsTabState extends State<LogsTab> {
  String filter = 'All';
  final rooms = const ['All', 'Living', 'Kitchen', 'Bedroom', 'Office'];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final entries = LogService.all().where((e) {
      if (filter == 'All') return true;
      return e.message.startsWith('[$filter]');
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Activity Logs'),
        actions: [
          IconButton(
            tooltip: 'Clear logs',
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('Clear all logs?'),
                  content: const Text('This will remove all log entries.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel')),
                    FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Clear')),
                  ],
                ),
              );
              if (ok == true) {
                await LogService.clear();
                if (mounted) setState(() {});
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Logs cleared')));
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Room filter chips
          SizedBox(
            height: 48,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              scrollDirection: Axis.horizontal,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemCount: rooms.length,
              itemBuilder: (_, i) {
                final r = rooms[i];
                final sel = r == filter;
                return ChoiceChip(
                  label: Text(r),
                  selected: sel,
                  onSelected: (_) => setState(() => filter = r),
                  selectedColor: cs.primary.withOpacity(.12),
                );
              },
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
              itemCount: entries.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final e = entries[i];
                final roomTag = _roomOf(e.message);
                return Container(
                  decoration: BoxDecoration(
                    color: cs.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: cs.outlineVariant),
                  ),
                  child: ListTile(
                    title: Text(e.message),
                    subtitle: Text(e.at.toLocal().toString()),
                    trailing: roomTag == null
                        ? null
                        : Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                                color: cs.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(10)),
                            child: Text(roomTag,
                                style: Theme.of(context).textTheme.labelSmall),
                          ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String? _roomOf(String msg) {
    final rx = RegExp(r'^\[(.*?)\]\s');
    final m = rx.firstMatch(msg);
    return m?.group(1);
  }
}
