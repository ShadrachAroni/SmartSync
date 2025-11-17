import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/alert_model.dart';
import '../../services/firebase_service.dart';
import '../../providers/auth_provider.dart';
import 'alert_details_screen.dart';
import 'alert_settings_screen.dart';

final alertsStreamProvider =
    StreamProvider.autoDispose.family<List<AlertModel>, String>(
  (ref, userId) => ref.watch(firebaseServiceProvider).getAlerts(userId),
);

class AlertsScreen extends ConsumerWidget {
  const AlertsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStateProvider).value;
    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('Login to view alerts')),
      );
    }

    final alertsAsync = ref.watch(alertsStreamProvider(user.uid));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Alerts'),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AlertSettingsScreen()),
            ),
          ),
        ],
      ),
      body: alertsAsync.when(
        data: (alerts) {
          if (alerts.isEmpty) {
            return const Center(
              child: Text('No alerts yet'),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(20),
            itemCount: alerts.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final alert = alerts[index];
              return _AlertCard(alert: alert);
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Error: $error')),
      ),
    );
  }
}

class _AlertCard extends ConsumerWidget {
  const _AlertCard({required this.alert});

  final AlertModel alert;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Color color;
    switch (alert.severity) {
      case 'high':
        color = Colors.red;
        break;
      case 'medium':
        color = Colors.orange;
        break;
      default:
        color = Colors.blue;
    }

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.15),
          child: Icon(Icons.warning_amber_rounded, color: color),
        ),
        title: Text(alert.message,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(alert.timestamp.toLocal().toString()),
        trailing: alert.read
            ? const Icon(Icons.check_circle_outline, color: Colors.green)
            : null,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => AlertDetailsScreen(alert: alert),
          ),
        ),
      ),
    );
  }
}
