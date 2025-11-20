import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'firebase_options.dart';
import 'core/theme/app_theme.dart';
import 'core/constants/routes.dart';
import 'screens/home/home_screen.dart';
import 'screens/onboarding/onboarding_screen.dart';
import 'providers/auth_provider.dart';
import 'package:flutter/foundation.dart' show kDebugMode;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load environment variables (optional - app can work without .env)
  try {
    await dotenv.load(fileName: ".env");
    debugPrint('✅ Environment variables loaded');
  } catch (e) {
    debugPrint('⚠️ .env file not found or could not be loaded: $e');
    debugPrint('⚠️ App will continue with default values');
  }

  // Initialize Firebase only once
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    debugPrint('✅ Firebase initialized: ${Firebase.app().name}');
  } else {
    debugPrint('⚠️ Firebase already initialized');
  }

  // Force refresh auth state to ensure we get fresh state, not cached
  // This prevents showing old layout on first build
  try {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser != null) {
      // Reload user to get fresh data
      await currentUser.reload();
      debugPrint('✅ Auth state refreshed for user: ${currentUser.uid}');
    }
  } catch (e) {
    debugPrint('⚠️ Could not refresh auth state: $e');
  }

  // Enable Firebase App Check
  try {
    await FirebaseAppCheck.instance.activate(
      androidProvider:
          kDebugMode ? AndroidProvider.debug : AndroidProvider.playIntegrity,
      appleProvider:
          kDebugMode ? AppleProvider.debug : AppleProvider.deviceCheck,
    );
    debugPrint('✅ Firebase App Check initialized successfully');
  } catch (e) {
    debugPrint('⚠️ App Check activation failed — falling back to Debug: $e');
    await FirebaseAppCheck.instance
        .activate(androidProvider: AndroidProvider.debug);
  }

  // Set system UI overlay style
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );

  runApp(
    const ProviderScope(
      child: SmartSyncApp(),
    ),
  );
}

class SmartSyncApp extends ConsumerStatefulWidget {
  const SmartSyncApp({super.key});

  @override
  ConsumerState<SmartSyncApp> createState() => _SmartSyncAppState();
}

class _SmartSyncAppState extends ConsumerState<SmartSyncApp> {
  @override
  void initState() {
    super.initState();
    // Refresh auth provider on app start to force fresh state
    // This ensures we don't use cached/stale auth state from previous session
    // Wait a frame to ensure ref is available
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        // Small delay to ensure Firebase Auth has finished reloading
        Future.delayed(const Duration(milliseconds: 50), () {
          if (mounted) {
            ref.refresh(authStateProvider);
          }
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);

    return MaterialApp(
      title: 'SmartSync',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark,

      // ✅ Use onGenerateRoute for internal navigation
      onGenerateRoute: AppRoutes.generateRoute,

      // ✅ Use home widget for auth-based initial screen
      // This takes precedence and handles authentication logic
      home: authState.when(
        data: (user) {
          if (user == null) {
            // Not logged in - show onboarding
            return const OnboardingScreen();
          }

          if (!user.emailVerified) {
            // Email not verified - show onboarding/login
            // User can verify and login again
            return const OnboardingScreen();
          }

          // Logged in and verified - show home
          return const HomeScreen();
        },
        loading: () => const SplashScreen(),
        error: (_, __) => const OnboardingScreen(),
      ),
    );
  }
}

/// Minimal Splash Screen (only shows during auth state loading)
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF00BFA5).withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.home_rounded,
                size: 80,
                color: Color(0xFF00BFA5),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'SmartSync',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Color(0xFF00BFA5),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Smart Home for Elderly Care',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 60),
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00BFA5)),
            ),
          ],
        ),
      ),
    );
  }
}
