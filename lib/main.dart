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
import 'services/adaptive_scheduler.dart';
import 'theme/theme_provider.dart';
import 'theme/themes.dart';
import 'screens/onboarding/onboarding_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/reset_password_screen.dart';
import 'screens/home/home_shell.dart';
import 'screens/home/bluetooth_screen.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

bool get _isMobile => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

Timer? _desktopTimer;

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, input) async {
    try {
      await Hive.initFlutter();
      await NotificationService.ensureInitialized();
      await AdaptiveScheduler.onBackgroundRun(success: true);
      return Future.value(true);
    } catch (_) {
      await AdaptiveScheduler.onBackgroundRun(success: false);
      return Future.value(false);
    }
  });
}

Future<void> _initDeepLinks() async {
  try {
    final links = AppLinks();
    links.uriLinkStream.listen((_) {});
  } catch (_) {}
}

Future<void> _initBackgroundScheduling() async {
  if (_isMobile) {
    await Workmanager().initialize(callbackDispatcher, isInDebugMode: false);
  }
  await AdaptiveScheduler.init();
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await _initDeepLinks();

  await Hive.initFlutter();
  await LogService.init();
  tz.initializeTimeZones();
  await NotificationService.ensureInitialized();

  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    anonKey: AppConfig.supabaseAnonKey,
  );

  // Listen for password recovery and route to reset screen
  Supabase.instance.client.auth.onAuthStateChange.listen((data) {
    if (data.event == AuthChangeEvent.passwordRecovery) {
      navigatorKey.currentState?.push(MaterialPageRoute(
        builder: (_) => const ResetPasswordScreen(),
      ));
    }
  });

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
      navigatorKey: navigatorKey, // <-- Add this
      title: 'SmartSync',
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: theme.mode,
      debugShowCheckedModeBanner: false,
      home: const OnboardingScreen(next: LoginScreen()),
      routes: {
        '/home': (_) => const HomeShell(),
        '/login': (_) => const LoginScreen(),
        '/bluetooth': (_) => const BluetoothScreen(),
        '/reset-password': (_) =>
            const ResetPasswordScreen(), // for pushNamed if needed
      },
    );
  }
}
