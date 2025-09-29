import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'routes.dart';
import 'app_theme.dart';
import 'services/supabase_service.dart';
import 'providers/theme_mode_provider.dart'; // <- make sure path is correct

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SupabaseService.initialize();
  runApp(const ProviderScope(child: SmartSync()));
}

class SmartSync extends ConsumerWidget {
  const SmartSync({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Read the current ThemeMode from Riverpod
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'SmartSync',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode, // drives the active theme
      routerConfig: router,
    );
  }
}
