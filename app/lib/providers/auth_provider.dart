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
  return authService.authStateChanges.handleError((error, stackTrace) {
    Logger.error('authStateProvider: Stream error', error, stackTrace);
    // Return null on error - let UI handle it gracefully
    // This prevents the app from crashing if Firebase Auth fails
  });
});

final currentUserProvider = StreamProvider<UserModel?>((ref) {
  final authService = ref.watch(authServiceProvider);
  
  // Combine auth state changes with user data stream for real-time updates
  return authService.authStateChanges.asyncExpand((user) {
    if (user == null) {
      return Stream.value(null);
    }
    
    // Use real-time stream for user data updates
    return authService.watchUserData(user.uid).map((userData) {
      // If stream returns null, provide fallback from auth user
      if (userData == null) {
        return UserModel(
          id: user.uid,
          name: user.displayName ?? 'User',
          email: user.email ?? '',
          profileImageUrl: null,
          createdAt: DateTime.now(),
        );
      }
      return userData;
    });
  }).handleError((error, stackTrace) {
    Logger.error('currentUserProvider: Stream error', error, stackTrace);
    // Return null on error - let UI handle it
    return null;
  });
});
