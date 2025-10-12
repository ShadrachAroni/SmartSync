import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:app_links/app_links.dart';

import 'package:workmanager/workmanager.dart';

import 'app_config.dart';
import 'services/notification_service.dart';
import 'services/log_service.dart';
import 'services/adaptive_scheduler.dart'; // NEW
import 'theme/theme_provider.dart';
import 'theme/themes.dart';
import 'screens/onboarding/onboarding_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/home/home_shell.dart';
import 'screens/home/bluetooth_screen.dart';

bool get _isMobile => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

Timer? _desktopTimer;

// WorkManager dispatcher must be top-level and entry-point in release.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, input) async {
    try {
      await Hive.initFlutter();
      await NotificationService.ensureInitialized();
      // Run adaptive background step (evaluates and reschedules)
      await AdaptiveScheduler.onBackgroundRun(success: true);
      return Future.value(true);
    } catch (_) {
      // On failure, reschedule with backoff
      await AdaptiveScheduler.onBackgroundRun(success: false);
      return Future.value(false);
    }
  });
}

Future<void> _initDeepLinks() async {
  try {
    final links = AppLinks();
    // Subscribing ensures plugin channels are registered early.
    links.uriLinkStream.listen((_) {});
  } catch (_) {
    // Ignore on unsupported platforms.
  }
}

Future<void> _initBackgroundScheduling() async {
  if (_isMobile) {
    await Workmanager().initialize(callbackDispatcher, isInDebugMode: false);
  }
  // Start adaptive chain (mobile uses WorkManager, desktop uses Timer)
  await AdaptiveScheduler.init();
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await _initDeepLinks(); // app_links early for recovery

  await Hive.initFlutter();
  await LogService.init();
  tz.initializeTimeZones();
  await NotificationService.ensureInitialized();

  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    anonKey: AppConfig.supabaseAnonKey,
  );

  // Optional: listen for auth events (e.g., passwordRecovery handled in UI)
  Supabase.instance.client.auth.onAuthStateChange.listen((_) {});

  await _initBackgroundScheduling();

  runApp(
    ChangeNotifierProvider(
      create: (_) => ThemeProvider(),
      child: const SmartSyncApp(),
    ),
  );
}

class SmartSyncApp extends StatefulWidget {
  const SmartSyncApp({super.key});
  @override
  State<SmartSyncApp> createState() => _SmartSyncAppState();
}

class _SmartSyncAppState extends State<SmartSyncApp> {
  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();
    return MaterialApp(
      title: 'SmartSync',
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: theme.mode,
      debugShowCheckedModeBanner: false,
      home: const OnboardingScreen(next: LoginScreen()),
      routes: {
        '/home': (_) => const HomeShell(),
        '/login': (_) => const LoginScreen(),
        '/bluetooth': (_) => const BluetoothScreen(), // keeps scan page
      },
    );
  }
}
