import 'package:flutter/material.dart';
import 'package:smartsync_app/core/constants/colors.dart';

class Routes {
  static const String splash = '/';
  static const String login = '/login';
  static const String signup = '/signup';
  static const String emailVerification = '/email-verification';
  static const String bluetoothLogin = '/bluetooth-login';
  static const String forgotPassword = '/forgot-password';

  static const String home = '/home';
  static const String deviceScan = '/device-scan';
  static const String deviceControl = '/device-control';
  static const String schedules = '/schedules';
  static const String addSchedule = '/add-schedule';
  static const String analytics = '/analytics';
  static const String alerts = '/alerts';
  static const String settings = '/settings';
  static const String profile = '/profile';
  static const String caregivers = '/caregivers';
}

class AppRoutes {
  static Map<String, WidgetBuilder> get routes => {
        Routes.splash: (context) => const SplashScreen(),
        Routes.login: (context) => const LoginScreen(),
        Routes.home: (context) => const HomeScreen(),
        // Add other routes as you create screens
      };
}

// Placeholder screens (create these later)
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.home, size: 100, color: AppColors.primary),
            const SizedBox(height: 20),
            Text(
              'SmartSync',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 10),
            const CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Login')),
      body: const Center(child: Text('Login Screen - To be implemented')),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Home')),
      body: const Center(child: Text('Home Screen - To be implemented')),
    );
  }
}
