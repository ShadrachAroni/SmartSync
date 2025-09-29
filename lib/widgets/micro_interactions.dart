import 'package:flutter/material.dart';
import 'package:animations/animations.dart';

class SmartTransition extends StatelessWidget {
  final Widget closedChild;
  final Widget openChild;
  final VoidCallback? onOpen;

  const SmartTransition(
      {super.key,
      required this.closedChild,
      required this.openChild,
      this.onOpen});

  @override
  Widget build(BuildContext context) {
    return OpenContainer(
      closedElevation: 0,
      openElevation: 6,
      closedShape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      openBuilder: (context, action) {
        onOpen?.call();
        return openChild;
      },
      closedBuilder: (context, action) => closedChild,
    );
  }
}
