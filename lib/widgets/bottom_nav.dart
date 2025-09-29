import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class BottomNav extends StatelessWidget {
  const BottomNav({super.key});

  int _indexFromLocation(String loc) {
    if (loc.startsWith('/security')) return 1;
    if (loc.startsWith('/logs')) return 2;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final loc = GoRouter.of(context).location;
    final currentIndex = _indexFromLocation(loc);

    return BottomNavigationBar(
      currentIndex: currentIndex,
      onTap: (i) {
        switch (i) {
          case 0:
            GoRouter.of(context).go('/');
            break;
          case 1:
            GoRouter.of(context).go('/security');
            break;
          case 2:
            GoRouter.of(context).go('/logs');
            break;
        }
      },
      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.home_outlined), label: 'Home'),
        BottomNavigationBarItem(
            icon: Icon(Icons.security_outlined), label: 'Security'),
        BottomNavigationBarItem(icon: Icon(Icons.history), label: 'Logs'),
      ],
    );
  }
}
