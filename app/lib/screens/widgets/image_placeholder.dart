import 'package:flutter/material.dart';

class ImagePlaceholder extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;

  const ImagePlaceholder({
    super.key,
    required this.icon,
    required this.color,
    this.size = 120,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size * 2,
      height: size * 2,
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        shape: BoxShape.circle,
      ),
      child: Icon(
        icon,
        size: size,
        color: color,
      ),
    );
  }
}
