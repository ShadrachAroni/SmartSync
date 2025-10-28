import 'package:flutter/material.dart';

class CustomSlider extends StatelessWidget {
  final String title;
  final IconData icon;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final String suffix;
  final Color color;
  final ValueChanged<double>? onChanged;
  final Widget? trailing;
  final String? trailingLabel;

  const CustomSlider({
    super.key,
    required this.title,
    required this.icon,
    required this.value,
    this.min = 0,
    this.max = 100,
    this.divisions,
    this.suffix = '',
    required this.color,
    this.onChanged,
    this.trailing,
    this.trailingLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 28, color: color),
                    const SizedBox(width: 12),
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                if (trailing != null)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (trailingLabel != null) ...[
                        Text(
                          trailingLabel!,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      trailing!,
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${value.round()}$suffix',
                    style: const TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: color,
                inactiveTrackColor: color.withOpacity(0.3),
                thumbColor: color,
                overlayColor: color.withOpacity(0.2),
                trackHeight: 8,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 16),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 28),
              ),
              child: Slider(
                value: value,
                min: min,
                max: max,
                divisions: divisions,
                label: '${value.round()}$suffix',
                onChanged: onChanged,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
