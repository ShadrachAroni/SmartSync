// lib/screens/home/tabs/widgets/device_tile.dart
import 'package:flutter/material.dart';

class DeviceTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget trailing;
  final Widget? footer;

  const DeviceTile({
    super.key,
    required this.icon,
    required this.title,
    required this.trailing,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Card(
      elevation: 0,
      color: cs.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: cs.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  height: 36,
                  width: 36,
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: cs.onSurfaceVariant),
                ),
                const Spacer(),
                trailing,
              ],
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const Spacer(),
            if (footer != null) footer!,
          ],
        ),
      ),
    );
  }
}
