import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_service.dart';
import '../models/user_model.dart';
import '../core/utils/logger.dart';

final authServiceProvider = Provider<AuthService>((ref) => AuthService());

final authStateProvider = StreamProvider<User?>((ref) {
  final authService = ref.watch(authServiceProvider);
  // Get auth state stream - Firebase Auth will emit current user immediately
  // then emit changes. The reload in main() ensures fresh data.
  return authService.authStateChanges;
});

final currentUserProvider = StreamProvider<UserModel?>((ref) {
  final authService = ref.watch(authServiceProvider);
  return authService.authStateChanges.asyncMap((user) async {
    if (user == null) {
      Logger.debug('currentUserProvider: User is null');
      return null;
    }
    
    try {
      Logger.debug('currentUserProvider: Loading user data for ${user.uid}');
      
      // Add comprehensive error handling with retry logic
      UserModel? userData;
      int retries = 0;
      const maxRetries = 2;
      
      while (retries <= maxRetries) {
        try {
          userData = await authService.getUserData(user.uid).timeout(
            const Duration(seconds: 8), // Reduced timeout
            onTimeout: () {
              Logger.warning('currentUserProvider: Timeout (attempt ${retries + 1}/$maxRetries)');
              throw TimeoutException('User data fetch timeout', const Duration(seconds: 8));
            },
          );
          Logger.debug('currentUserProvider: User data loaded successfully');
          break; // Success, exit retry loop
        } catch (e) {
          retries++;
          if (retries > maxRetries) {
            Logger.error('currentUserProvider: All retries exhausted. Error: $e');
            // Fall through to fallback
            break;
          } else {
            Logger.warning('currentUserProvider: Retry $retries/$maxRetries after error: $e');
            await Future.delayed(Duration(milliseconds: 500 * retries)); // Exponential backoff
          }
        }
      }
      
      // Return fetched data or fallback
      return userData ?? UserModel(
        id: user.uid,
        name: user.displayName ?? 'User',
        email: user.email ?? '',
        profileImageUrl: null,
        createdAt: DateTime.now(),
      );
    } catch (e, stackTrace) {
      Logger.error('currentUserProvider: Unexpected error: $e');
      Logger.error('currentUserProvider: Stack trace: $stackTrace');
      // Return basic user model on error to prevent infinite loading
      return UserModel(
        id: user.uid,
        name: user.displayName ?? 'User',
        email: user.email ?? '',
        profileImageUrl: null,
        createdAt: DateTime.now(),
      );
    }
  });
});
