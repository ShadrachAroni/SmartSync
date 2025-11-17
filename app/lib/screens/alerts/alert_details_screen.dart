import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/alert_model.dart';
import '../../services/firebase_service.dart';

class AlertDetailsScreen extends ConsumerWidget {
  const AlertDetailsScreen({super.key, required this.alert});

  final AlertModel alert;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Alert Details')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              alert.type.toUpperCase(),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade600,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              alert.message,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Detected on ${alert.timestamp.toLocal()}',
              style: TextStyle(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 24),
            const Text(
              'Additional Data',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              alert.data.isEmpty
                  ? 'No extra context'
                  : alert.data.entries
                      .map((e) => '${e.key}: ${e.value}')
                      .join('\n'),
            ),
            const Spacer(),
            ElevatedButton.icon(
              onPressed: () async {
                await ref
                    .read(firebaseServiceProvider)
                    .markAlertRead(alert.id, acknowledged: true);
                if (context.mounted) Navigator.pop(context);
              },
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('Mark as resolved'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
