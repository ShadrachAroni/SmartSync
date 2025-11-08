// app/lib/core/constants/routes.dart
import 'package:flutter/material.dart';
import '../../screens/onboarding/onboarding_screen.dart';
import '../../screens/auth/login_screen.dart';
import '../../screens/auth/signup_screen.dart';
import '../../screens/auth/forgot_password_screen.dart';
import '../../screens/home/home_screen.dart';
import '../../screens/devices/device_scan_screen.dart';
import '../../screens/analytics/analytics_screen.dart'; // ✅ ADDED
import '../../screens/rooms/rooms_screen.dart';
import '../../screens/rooms/room_detail_screen.dart';
import '../../screens/rooms/add_room_screen.dart';
import '../../screens/rooms/edit_room_screen.dart';
import '../../screens/settings/settings_screen.dart';
import '../../models/room_model.dart';

/// Route names as constants
class Routes {
  // Auth routes
  static const String splash = '/';
  static const String onboarding = '/onboarding';
  static const String login = '/login';
  static const String signup = '/signup';
  static const String forgotPassword = '/forgot-password';

  // Main app routes
  static const String home = '/home';
  static const String deviceScan = '/device-scan';
  static const String analytics = '/analytics';
  static const String rooms = '/rooms';
  static const String roomDetail = '/room-detail';
  static const String addRoom = '/add-room';
  static const String editRoom = '/edit-room';
  static const String settings = '/settings';

  // Prevent instantiation
  Routes._();
}

/// App route generator
class AppRoutes {
  /// Generate route based on RouteSettings
  static Route<dynamic> generateRoute(RouteSettings settings) {
    switch (settings.name) {
      case Routes.splash:
        return MaterialPageRoute(
          builder: (_) => const SplashScreen(),
          settings: settings,
        );

      case Routes.onboarding:
        return MaterialPageRoute(
          builder: (_) => const OnboardingScreen(),
          settings: settings,
        );

      case Routes.login:
        return MaterialPageRoute(
          builder: (_) => const LoginScreen(),
          settings: settings,
        );

      case Routes.signup:
        return MaterialPageRoute(
          builder: (_) => const SignupScreen(),
          settings: settings,
        );

      case Routes.forgotPassword:
        return MaterialPageRoute(
          builder: (_) => const ForgotPasswordScreen(),
          settings: settings,
        );

      case Routes.home:
        return MaterialPageRoute(
          builder: (_) => const HomeScreen(),
          settings: settings,
        );

      case Routes.deviceScan:
        return MaterialPageRoute(
          builder: (_) => const DeviceScanScreen(),
          settings: settings,
        );

      case Routes.analytics: // ✅ ADDED
        return MaterialPageRoute(
          builder: (_) => const AnalyticsScreen(),
          settings: settings,
        );

      case Routes.rooms:
        return MaterialPageRoute(
          builder: (_) => const RoomsScreen(),
          settings: settings,
        );

      case Routes.roomDetail:
        // Extract room argument
        final room = settings.arguments as RoomModel?;
        if (room == null) {
          return _errorRoute('Room data is required');
        }
        return MaterialPageRoute(
          builder: (_) => RoomDetailScreen(room: room),
          settings: settings,
        );

      case Routes.addRoom:
        return MaterialPageRoute(
          builder: (_) => const AddRoomScreen(),
          settings: settings,
        );

      case Routes.editRoom:
        // Extract room argument
        final room = settings.arguments as RoomModel?;
        if (room == null) {
          return _errorRoute('Room data is required');
        }
        return MaterialPageRoute(
          builder: (_) => EditRoomScreen(room: room),
          settings: settings,
        );

      case Routes.settings:
        return MaterialPageRoute(
          builder: (_) => const SettingsScreen(),
          settings: settings,
        );

      default:
        return _errorRoute('No route defined for ${settings.name}');
    }
  }

  /// Error route helper
  static Route<dynamic> _errorRoute(String message) {
    return MaterialPageRoute(
      builder: (_) => Scaffold(
        appBar: AppBar(
          title: const Text('Error'),
          backgroundColor: Colors.red.shade600,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 64,
                  color: Colors.red.shade300,
                ),
                const SizedBox(height: 24),
                Text(
                  'Navigation Error',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.red.shade700,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 32),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.of(_).popUntil((route) => route.isFirst);
                  },
                  icon: const Icon(Icons.home),
                  label: const Text('Go Home'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade600,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Prevent instantiation
  AppRoutes._();
}

/// Splash Screen with proper navigation logic
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    try {
      // Show splash for minimum 2 seconds
      await Future.delayed(const Duration(seconds: 2));

      if (!mounted) return;

      // Navigate based on auth state
      // Note: Auth state checking is handled in main.dart
      // This splash is just for initial app loading
      Navigator.of(context).pushReplacementNamed(Routes.onboarding);
    } catch (e) {
      debugPrint('Splash initialization error: $e');
      if (!mounted) return;
      _showErrorDialog(e.toString());
    }
  }

  void _showErrorDialog(String error) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Row(
          children: [
            Icon(Icons.error_outline, color: Colors.red[700]),
            const SizedBox(width: 8),
            const Text('Connection Error'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Failed to initialize the app. Please check:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text('• Internet connection'),
            const Text('• Firebase configuration'),
            const SizedBox(height: 16),
            Text(
              'Error: $error',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _initializeApp(); // Retry
            },
            child: const Text('RETRY'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.of(context).pushReplacementNamed(Routes.onboarding);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00BFA5),
              foregroundColor: Colors.white,
            ),
            child: const Text('CONTINUE'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // App Icon
            Container(
              padding: const EdgeInsets.all(20),
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
            const SizedBox(height: 32),

            // App Name
            const Text(
              'SmartSync',
              style: TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.bold,
                color: Color(0xFF00BFA5),
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 8),

            // Tagline
            Text(
              'Smart Home for Elderly Care',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
                fontWeight: FontWeight.w300,
              ),
            ),
            const SizedBox(height: 60),

            // Loading Indicator
            const SizedBox(
              width: 40,
              height: 40,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00BFA5)),
              ),
            ),
            const SizedBox(height: 16),

            // Loading Text
            Text(
              'Initializing...',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[500],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
