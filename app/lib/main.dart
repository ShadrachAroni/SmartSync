import 'dart:async';
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
import 'core/widgets/lottie_loading.dart';
import 'core/widgets/app_error_handler.dart';
import 'core/utils/ui_thread_monitor.dart';
import 'core/utils/black_screen_diagnostic.dart';
import 'screens/home/home_screen.dart';
import 'screens/onboarding/onboarding_screen.dart';
import 'providers/auth_provider.dart';
import 'services/ml_service.dart';
import 'services/hub_reconnection_service.dart';
import 'services/unregistered_hub_scanner.dart';
import 'package:flutter/foundation.dart' show kDebugMode;

Future<void> main() async {
  debugPrint('🚀 ========== APP STARTUP BEGIN ==========');
  debugPrint('🚀 Timestamp: ${DateTime.now().toIso8601String()}');

  // Initialize error handlers
  AppErrorHandler.initialize();

  // Handle async errors
  runZonedGuarded(() async {
    debugPrint('📱 Step 1: Ensuring Flutter binding initialized...');
    WidgetsFlutterBinding.ensureInitialized();
    debugPrint('✅ Step 1: Flutter binding initialized');
    
    // Start UI thread monitoring AFTER binding is initialized
    try {
      UIThreadMonitor.startMonitoring();
      debugPrint('✅ UI Thread Monitor: Started');
    } catch (e) {
      debugPrint('⚠️ UI Thread Monitor: Failed to start: $e');
      // Continue without monitoring - not critical
    }
    
    // Start black screen diagnostic monitoring
    try {
      BlackScreenDiagnostic.startMonitoring();
      debugPrint('✅ Black Screen Diagnostic: Started');
    } catch (e) {
      debugPrint('⚠️ Black Screen Diagnostic: Failed to start: $e');
      // Continue without monitoring - not critical
    }

    // Load environment variables (optional - app can work without .env)
    debugPrint('📱 Step 2: Loading environment variables...');
    try {
      await dotenv.load(fileName: ".env");
      debugPrint('✅ Step 2: Environment variables loaded');
    } catch (e) {
      debugPrint('⚠️ Step 2: .env file not found or could not be loaded: $e');
      debugPrint('⚠️ Step 2: App will continue with default values');
    }

    // Initialize Firebase only once
    debugPrint('📱 Step 3: Initializing Firebase...');
    try {
      if (Firebase.apps.isEmpty) {
        debugPrint(
            '📱 Step 3: No existing Firebase apps, initializing new instance...');
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
        debugPrint('✅ Step 3: Firebase initialized: ${Firebase.app().name}');
      } else {
        debugPrint(
            '⚠️ Step 3: Firebase already initialized (${Firebase.apps.length} app(s))');
      }
    } catch (e, stackTrace) {
      debugPrint('❌ Step 3: Firebase initialization failed: $e');
      debugPrint('❌ Step 3: Stack trace: $stackTrace');
      debugPrint(
          '⚠️ Step 3: Continuing without Firebase - some features may not work');
    }

    // Force refresh auth state to ensure we get fresh state, not cached
    // This prevents showing old layout on first build
    debugPrint('📱 Step 4: Refreshing auth state...');
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null) {
        debugPrint('📱 Step 4: User found (${currentUser.uid}), reloading...');
        // Reload user to get fresh data
        await currentUser.reload();
        debugPrint(
            '✅ Step 4: Auth state refreshed for user: ${currentUser.uid}');
      } else {
        debugPrint('📱 Step 4: No current user found');
      }
    } catch (e) {
      debugPrint('⚠️ Step 4: Could not refresh auth state: $e');
    }

    // Enable Firebase App Check (non-blocking - don't wait if it fails)
    debugPrint('📱 Step 5: Initializing Firebase App Check...');
    debugPrint('📱 Step 5: Debug mode: $kDebugMode');
    try {
      debugPrint('📱 Step 5: Activating App Check with timeout (5s)...');
      await FirebaseAppCheck.instance
          .activate(
        androidProvider:
            kDebugMode ? AndroidProvider.debug : AndroidProvider.playIntegrity,
        appleProvider:
            kDebugMode ? AppleProvider.debug : AppleProvider.deviceCheck,
      )
          .timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          debugPrint(
              '⚠️ Step 5: App Check activation timed out after 5 seconds');
          throw TimeoutException('App Check timeout');
        },
      );
      debugPrint('✅ Step 5: Firebase App Check initialized successfully');
    } on TimeoutException {
      debugPrint(
          '⚠️ Step 5: App Check activation timed out - continuing without App Check');
    } catch (e) {
      debugPrint(
          '⚠️ Step 5: App Check activation failed — falling back to Debug: $e');
      try {
        debugPrint('📱 Step 5: Attempting fallback with Debug provider...');
        await FirebaseAppCheck.instance
            .activate(androidProvider: AndroidProvider.debug)
            .timeout(const Duration(seconds: 3));
        debugPrint('✅ Step 5: Firebase App Check fallback initialized');
      } catch (e2) {
        debugPrint('⚠️ Step 5: App Check fallback also failed: $e2');
        debugPrint('⚠️ Step 5: App will continue without App Check');
      }
    }

    // Set system UI overlay style
    debugPrint('📱 Step 6: Setting system UI overlay style...');
    try {
      SystemChrome.setSystemUIOverlayStyle(
        const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
        ),
      );
      debugPrint('✅ Step 6: System UI overlay style set');
    } catch (e) {
      debugPrint('⚠️ Step 6: Failed to set system UI overlay: $e');
    }

    // Pre-initialize ML Service in background (non-blocking)
    // This ensures models are loaded early for better UX
    // Use a delayed future to ensure it doesn't block app startup
    debugPrint(
        '📱 Step 7: Scheduling ML Service pre-initialization (non-blocking)...');
    Future.delayed(const Duration(milliseconds: 100), () {
      debugPrint('📱 Step 7: Starting ML Service pre-initialization...');
      try {
        final mlService = MLService();
        mlService.initialize().then((_) {
          debugPrint('✅ Step 7: ML Service pre-initialized successfully');
        }).catchError((e, stackTrace) {
          debugPrint('⚠️ Step 7: ML Service pre-initialization failed: $e');
          debugPrint('⚠️ Step 7: Stack: $stackTrace');
          debugPrint('⚠️ Step 7: Models will be loaded on first use');
        });
      } catch (e, stackTrace) {
        debugPrint('⚠️ Step 7: Could not pre-initialize ML Service: $e');
        debugPrint('⚠️ Step 7: Stack: $stackTrace');
      }
    });

    debugPrint('📱 Step 8: Starting runApp...');
    try {
      runApp(
        const ProviderScope(
          child: SmartSyncApp(),
        ),
      );
      debugPrint('✅ Step 8: runApp called successfully');
      debugPrint('✅ ========== APP STARTUP COMPLETE ==========');
    } catch (e, stackTrace) {
      debugPrint('❌ Step 8: runApp failed: $e');
      debugPrint('❌ Step 8: Stack: $stackTrace');
      rethrow;
    }
  }, (error, stack) {
    debugPrint('❌ ========== UNHANDLED ERROR IN MAIN ==========');
    debugPrint('❌ Error: $error');
    debugPrint('❌ Stack: $stack');
    debugPrint('❌ ============================================');
  });
}

class SmartSyncApp extends ConsumerStatefulWidget {
  const SmartSyncApp({super.key});

  @override
  ConsumerState<SmartSyncApp> createState() => _SmartSyncAppState();
}

class _SmartSyncAppState extends ConsumerState<SmartSyncApp> with WidgetsBindingObserver {
  // Hub reconnection service enabled for Bluetooth stability (simplified - no primary hub logic)
  final HubReconnectionService _hubReconnectionService = HubReconnectionService();
  final UnregisteredHubScanner _unregisteredHubScanner = UnregisteredHubScanner();

  @override
  void initState() {
    debugPrint('📱 SmartSyncApp: initState called');
    super.initState();
    // Listen to app lifecycle changes first
    WidgetsBinding.instance.addObserver(this);
    
    // Defer service initialization until after first frame to avoid blocking startup
    WidgetsBinding.instance.addPostFrameCallback((_) {
      debugPrint('📱 SmartSyncApp: First frame rendered, initializing services...');
      // Initialize hub reconnection service for Bluetooth stability
      try {
        _hubReconnectionService.initialize();
        debugPrint('✅ SmartSyncApp: Hub reconnection service initialized');
      } catch (e, stackTrace) {
        debugPrint('⚠️ SmartSyncApp: Failed to initialize hub reconnection service: $e');
        debugPrint('⚠️ Stack: $stackTrace');
      }
      
      // Start scanning for unregistered hubs (deferred to avoid blocking)
      Future.delayed(const Duration(seconds: 2), () {
        try {
          _unregisteredHubScanner.startPeriodicScan();
          debugPrint('✅ SmartSyncApp: Unregistered hub scanner started');
        } catch (e, stackTrace) {
          debugPrint('⚠️ SmartSyncApp: Failed to start unregistered hub scanner: $e');
          debugPrint('⚠️ Stack: $stackTrace');
        }
      });
    });
    // Removed unnecessary auth state invalidation to prevent rebuild loops
    // Auth state is already refreshed in main() before runApp
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hubReconnectionService.dispose();
    _unregisteredHubScanner.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // Trigger hub reconnection when app comes to foreground for Bluetooth stability
    if (state == AppLifecycleState.resumed) {
      debugPrint('📱 SmartSyncApp: App resumed, triggering hub reconnection...');
      _hubReconnectionService.onAppResumed();
    }
  }

  @override
  Widget build(BuildContext context) {
    debugPrint('📱 SmartSyncApp: build() called');
    try {
      debugPrint('📱 SmartSyncApp: Watching authStateProvider...');
      final authState = ref.watch(authStateProvider);
      debugPrint(
          '📱 SmartSyncApp: Auth state received: ${authState.runtimeType}');

      authState.when(
        data: (user) => debugPrint(
            '📱 SmartSyncApp: Auth state data - user: ${user?.uid ?? "null"}'),
        loading: () => debugPrint('📱 SmartSyncApp: Auth state loading...'),
        error: (error, stack) =>
            debugPrint('📱 SmartSyncApp: Auth state error: $error'),
      );

      debugPrint('📱 SmartSyncApp: Building MaterialApp...');
      final homeWidget = authState.when(
        data: (user) {
          debugPrint(
              '📱 SmartSyncApp: Auth data received - user: ${user?.uid ?? "null"}');
          if (user == null) {
            debugPrint('📱 SmartSyncApp: No user - showing OnboardingScreen');
            // Not logged in - show onboarding
            return const OnboardingScreen();
          }

          if (!user.emailVerified) {
            debugPrint(
                '📱 SmartSyncApp: User email not verified - showing OnboardingScreen');
            // Email not verified - show onboarding/login
            // User can verify and login again
            return const OnboardingScreen();
          }

          debugPrint(
              '📱 SmartSyncApp: User authenticated and verified - showing HomeScreen');
          // Logged in and verified - show home
          return const HomeScreen();
        },
        loading: () {
          debugPrint(
              '📱 SmartSyncApp: Auth state loading - showing SplashScreen');
          return const SplashScreen();
        },
        error: (error, stackTrace) {
          debugPrint('❌ SmartSyncApp: Auth state error: $error');
          debugPrint('❌ SmartSyncApp: Stack: $stackTrace');
          debugPrint('📱 SmartSyncApp: Showing OnboardingScreen due to error');
          return const OnboardingScreen();
        },
      );

      debugPrint(
          '📱 SmartSyncApp: Creating MaterialApp with home widget: ${homeWidget.runtimeType}');
      final materialApp = MaterialApp(
        title: 'SmartSync',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.dark,
        builder: (context, child) {
          // Wrap with error boundary (performance monitor disabled by default)
          // Enable PerformanceMonitor only when needed for debugging
          return AppErrorHandler.wrapWithErrorBoundary(
            child ?? const SizedBox.shrink(),
            context: 'MaterialApp',
          );
        },

        // ✅ Use onGenerateRoute for internal navigation
        onGenerateRoute: AppRoutes.generateRoute,

        // ✅ Use home widget for auth-based initial screen
        // This takes precedence and handles authentication logic
        home: AppErrorHandler.wrapWithErrorBoundary(
          homeWidget,
          context: 'HomeWidget',
        ),
      );
      debugPrint('✅ SmartSyncApp: MaterialApp created successfully');
      return materialApp;
    } catch (e, stackTrace) {
      debugPrint('❌ ========== ERROR BUILDING APP ==========');
      debugPrint('❌ Exception: $e');
      debugPrint('❌ Stack: $stackTrace');
      debugPrint('❌ ========================================');
      // Return a minimal error screen - fallback to onboarding
      debugPrint(
          '📱 SmartSyncApp: Returning fallback MaterialApp with OnboardingScreen');
      return MaterialApp(
        title: 'SmartSync',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.dark,
        home: const OnboardingScreen(),
      );
    }
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
                color: const Color(0xFF00BFA5).withValues(alpha: 0.1),
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
            const LottieLoading(
              size: 80,
            ),
          ],
        ),
      ),
    );
  }
}
