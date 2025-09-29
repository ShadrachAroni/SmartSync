import 'package:go_router/go_router.dart';
import 'screens/onboarding_screen.dart';
import 'screens/home_screen.dart';
import 'screens/room_detail_screen.dart';
import 'screens/device_detail_screen.dart';
import 'screens/logs_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/security_screen.dart';
import 'screens/device_connection_screen.dart';

final router = GoRouter(
  initialLocation: '/onboarding',
  routes: [
    GoRoute(
      path: '/onboarding',
      builder: (context, state) => const OnboardingScreen(),
    ),
    GoRoute(
      path: '/',
      builder: (context, state) => const HomeScreen(),
    ),
    GoRoute(
      path: '/room/:id',
      builder: (context, state) {
        final id = state.pathParameters['id'];
        if (id == null) {
          // handle missing id (navigate away, throw, or return a fallback widget)
          return const HomeScreen();
        }
        return RoomDetailScreen(roomId: id);
      },
    ),
    GoRoute(
      path: '/device/:id',
      builder: (context, state) {
        final id = state.pathParameters['id'];
        if (id == null) return const HomeScreen();
        return DeviceDetailScreen(deviceId: id);
      },
    ),
    GoRoute(
      path: '/logs',
      builder: (context, state) => const LogsScreen(),
    ),
    GoRoute(
      path: '/settings',
      builder: (context, state) => const SettingsScreen(),
    ),
    GoRoute(
      path: '/security',
      builder: (context, state) => const SecurityScreen(),
    ),
    GoRoute(
      path: '/connect',
      builder: (context, state) => const DeviceConnectionScreen(),
    ),
  ],
);
