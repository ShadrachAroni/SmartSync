import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../widgets/room_card.dart';
import '../widgets/bottom_nav.dart';
import '../providers/device_provider.dart';
import '../providers/theme_mode_provider.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devices = ref.watch(devicesProvider); // reserved for future use
    final themeMode = ref.watch(themeModeProvider);
    final scaffoldKey = GlobalKey<ScaffoldState>();

    return Scaffold(
      key: scaffoldKey,
      drawer: const _AppDrawer(),
      bottomNavigationBar: const BottomNav(),
      body: SafeArea(
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Theme.of(context).colorScheme.surface,
                Theme.of(context).colorScheme.surface.withOpacity(0.98),
              ],
            ),
          ),
          child: Column(
            children: [
              _Header(scaffoldKey: scaffoldKey, themeMode: themeMode),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18.0),
                child: _SectionHeader(),
              ),
              const SizedBox(height: 8),
              const Expanded(child: _RoomsGrid()),
            ],
          ),
        ),
      ),
      floatingActionButton: _FloatingButtons(themeMode: themeMode),
    );
  }
}

/// header (menu + greeting + avatar)
class _Header extends StatelessWidget {
  final GlobalKey<ScaffoldState> scaffoldKey;
  final ThemeMode themeMode;
  const _Header({required this.scaffoldKey, required this.themeMode});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 14),
      child: Row(
        children: [
          // menu button
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => scaffoldKey.currentState?.openDrawer(),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.03),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  )
                ],
              ),
              child:
                  Image.asset('assets/icons/menu.png', width: 26, height: 26),
            ),
          ),

          const SizedBox(width: 12),

          // greeting
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Hi User 👋',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  'Welcome to SmartSync',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.color
                            ?.withOpacity(0.8),
                      ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),

          const SizedBox(width: 12),

          // avatar
          GestureDetector(
            onTap: () => context.go('/settings'),
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: CircleAvatar(
                radius: 22,
                backgroundColor: Theme.of(context).cardColor,
                child: ClipOval(
                  child: Image.asset(
                    'assets/icons/avatar.png',
                    width: 40,
                    height: 40,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// section header (title + search)
class _SectionHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Rooms',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text('Control and monitor devices by room',
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => context.go('/search'),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(0.03),
                    blurRadius: 6,
                    offset: const Offset(0, 3)),
              ],
            ),
            child: const Icon(Icons.search, size: 20),
          ),
        ),
      ],
    );
  }
}

/// grid of rooms
class _RoomsGrid extends StatelessWidget {
  const _RoomsGrid();

  @override
  Widget build(BuildContext context) {
    const rooms = [
      {
        'title': 'Living Room',
        'subtitle': '5 devices',
        'colorHex': 'FF2E1AFF',
        'route': '/room/r1',
        'imageAsset': 'assets/rooms/living_room.jpg',
      },
      {
        'title': 'Kitchen',
        'subtitle': '4 devices',
        'colorHex': 'FFFB8B24',
        'route': '/room/r2',
        'imageAsset': 'assets/rooms/kitchen.jpg',
      },
      {
        'title': 'Office',
        'subtitle': '10 devices',
        'colorHex': 'FFE6E6F0',
        'route': '/room/r3',
        'imageAsset': 'assets/rooms/office.jpg',
      },
      {
        'title': 'Bedroom',
        'subtitle': '6 devices',
        'colorHex': 'FFB8E1FF',
        'route': '/room/r4',
        'imageAsset': 'assets/rooms/bedroom.jpg',
      },
      {
        'title': 'Bathroom',
        'subtitle': '7 devices',
        'colorHex': 'FFFFD6E0',
        'route': '/room/r5',
        'imageAsset': 'assets/rooms/bathroom.jpg',
      },
      {
        'title': 'Dining Room',
        'subtitle': '4 devices',
        'colorHex': 'FFE3F7E7',
        'route': '/room/r6',
        'imageAsset': 'assets/rooms/dining_room.jpg',
      },
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          const crossAxisCount = 2;
          const spacing = 12.0;
          const totalSpacing = spacing * (crossAxisCount - 1);
          final itemWidth =
              (constraints.maxWidth - totalSpacing) / crossAxisCount;
          final itemHeight = (constraints.maxHeight -
                  (spacing * (rooms.length / crossAxisCount))) /
              (rooms.length / crossAxisCount);
          final aspectRatio = itemWidth / itemHeight;

          return GridView.count(
            physics: const BouncingScrollPhysics(),
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: spacing,
            mainAxisSpacing: spacing,
            childAspectRatio: aspectRatio.clamp(0.8, 1.2),
            children: rooms.map((r) {
              return RoomCard(
                title: r['title'] as String,
                subtitle: r['subtitle'] as String,
                colorHex: r['colorHex'] as String,
                route: r['route'] as String,
                imageAsset: r['imageAsset'] as String,
              );
            }).toList(),
          );
        },
      ),
    );
  }
}

/// floating action buttons
class _FloatingButtons extends ConsumerWidget {
  final ThemeMode themeMode;
  const _FloatingButtons({required this.themeMode});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bg = Theme.of(context).colorScheme.primary;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FloatingActionButton.small(
          heroTag: 'themeToggle',
          backgroundColor: bg,
          onPressed: () {
            ref.read(themeModeProvider.notifier).state =
                themeMode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
          },
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: Icon(
            themeMode == ThemeMode.light
                ? Icons.dark_mode_outlined
                : Icons.light_mode_outlined,
            size: 18,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 12),
        FloatingActionButton.small(
          heroTag: 'connectFab',
          backgroundColor: bg,
          onPressed: () => context.go('/connect'),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: Image.asset(
            'assets/icons/bluetooth.png',
            width: 18,
            height: 18,
            color: Colors.white,
            errorBuilder: (c, e, s) =>
                const Icon(Icons.bluetooth, size: 18, color: Colors.white),
          ),
        ),
      ],
    );
  }
}

/// Drawer rewritten with GoRouter
class _AppDrawer extends StatelessWidget {
  const _AppDrawer();

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            const SizedBox(height: 6),
            ListTile(
              leading: const Icon(Icons.home),
              title: const Text('Home'),
              onTap: () {
                Navigator.pop(context);
                context.go('/');
              },
            ),
            ListTile(
              leading: const Icon(Icons.history),
              title: const Text('Logs'),
              onTap: () {
                Navigator.pop(context);
                context.go('/logs');
              },
            ),
            ListTile(
              leading: const Icon(Icons.bluetooth),
              title: const Text('Device Connect'),
              onTap: () {
                Navigator.pop(context);
                context.go('/connect');
              },
            ),
            ListTile(
              leading: const Icon(Icons.security),
              title: const Text('Security'),
              onTap: () {
                Navigator.pop(context);
                context.go('/security');
              },
            ),
            ListTile(
              leading: const Icon(Icons.settings),
              title: const Text('Settings'),
              onTap: () {
                Navigator.pop(context);
                context.go('/settings');
              },
            ),
          ],
        ),
      ),
    );
  }
}
