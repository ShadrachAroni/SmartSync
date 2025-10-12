// lib/screens/home/home_shell.dart
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../theme/theme_provider.dart';
import '../../services/supabase_service.dart';
import 'tabs/dashboard_tab.dart';
import 'tabs/security_tab.dart';
import 'tabs/logs_tab.dart';
import 'tabs/settings_tab.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int index = 0;
  String username = '';

  @override
  void initState() {
    super.initState();
    _loadUsername();
  }

  Future<void> _loadUsername() async {
    final p = await SupabaseService.getMyProfile();
    final fallback =
        Supabase.instance.client.auth.currentUser?.email?.split('@').first ??
            '';
    setState(() => username =
        (p?['username'] as String?)?.trim().isNotEmpty == true
            ? p!['username']
            : fallback);
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();
    const pages = [DashboardTab(), SecurityTab(), LogsTab(), SettingsTab()];

    return Scaffold(
      extendBody: true,
      appBar: AppBar(
        title: Text('Hello $username'),
        actions: [
          IconButton(
            tooltip: theme.mode == ThemeMode.dark ? 'Light' : 'Dark',
            icon: Icon(theme.mode == ThemeMode.dark
                ? Icons.light_mode
                : Icons.dark_mode),
            onPressed: () => theme.setMode(theme.mode == ThemeMode.dark
                ? ThemeMode.light
                : ThemeMode.dark),
          ),
        ],
      ),
      body: pages[index],
      bottomNavigationBar: _GlassNavBar(
        index: index,
        onTap: (i) => setState(() => index = i),
        items: const [
          _GlassItem(Icons.home_outlined, 'Home'),
          _GlassItem(Icons.shield_moon_outlined, 'Security'),
          _GlassItem(Icons.list_alt_outlined, 'Logs'),
          _GlassItem(Icons.settings_outlined, 'Settings'),
        ],
      ),
    );
  }
}

class _GlassItem {
  final IconData icon;
  final String label;
  const _GlassItem(this.icon, this.label);
}

class _GlassNavBar extends StatelessWidget {
  final List<_GlassItem> items;
  final int index;
  final ValueChanged<int> onTap;
  const _GlassNavBar(
      {required this.items, required this.index, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              height: 66,
              decoration: BoxDecoration(
                color: cs.surface.withOpacity(0.75),
                border: Border.all(color: cs.outlineVariant),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List.generate(items.length, (i) {
                  final selected = i == index;
                  return Expanded(
                    child: InkWell(
                      onTap: () => onTap(i),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        margin: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 10),
                        decoration: BoxDecoration(
                          color: selected
                              ? cs.primary.withOpacity(.12)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(items[i].icon,
                                color: selected
                                    ? cs.primary
                                    : cs.onSurfaceVariant),
                            const SizedBox(width: 6),
                            AnimatedOpacity(
                              opacity: selected ? 1 : 0,
                              duration: const Duration(milliseconds: 180),
                              child: Text(items[i].label,
                                  style: TextStyle(
                                      color: cs.primary,
                                      fontWeight: FontWeight.w600)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
