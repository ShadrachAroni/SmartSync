import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../models/user_model.dart';
import '../services/logging_service.dart';
import '../models/log_entry.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  final LoggingService _loggingService = LoggingService();

  // Get current user
  User? get currentUser => _auth.currentUser;

  // Auth state changes
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // Sign up with email and password
  Future<UserCredential> signUpWithEmail(
    String email,
    String password,
    String name,
  ) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Create Firestore user document
      final user = credential.user;
      if (user != null) {
        final userModel = UserModel(
          id: user.uid,
          name: name,
          email: email,
          createdAt: DateTime.now(),
        );

        await _firestore
            .collection('users')
            .doc(user.uid)
            .set(userModel.toFirestore());

        // Send verification email
        await user.sendEmailVerification();
      }

      return credential;
    } on FirebaseAuthException catch (e) {
      // Map Firebase errors to human-readable messages
      throw FirebaseAuthException(
        code: e.code,
        message: _mapAuthError(e),
      );
    } catch (e) {
      // Handles AppCheck / network / JSON / unknown issues
      throw FirebaseAuthException(
        code: 'unknown',
        message:
            'Unexpected sign-up failure. Please check your connection or App Check configuration.',
      );
    }
  }

  String _mapAuthError(FirebaseAuthException e) {
    switch (e.code) {
      case 'weak-password':
        return 'Password is too weak. Use a mix of letters and numbers.';
      case 'email-already-in-use':
        return 'This email is already registered.';
      case 'invalid-email':
        return 'Invalid email format.';
      case 'operation-not-allowed':
        return 'Email/password sign-in is not enabled in Firebase Console.';
      case 'network-request-failed':
        return 'Network error. Please check your internet connection.';
      case 'app-check-failed':
      case 'app-not-authorized':
        return 'App Check validation failed. Add your debug token in Firebase Console.';
      case 'aborted-by-user':
        return 'Google sign-in was cancelled.';
      case 'account-exists-with-different-credential':
        return 'An account already exists with the same email but different sign-in method.';
      default:
        return e.message ?? 'Failed to create account. Please try again.';
    }
  }

  // Sign in with email and password
  Future<UserCredential> signInWithEmail(
    String email,
    String password,
  ) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      await _loggingService.logAction(
        action: 'User Login',
        category: 'auth',
        details: 'Signed in with email & password',
        metadata: {
          'method': 'email',
          'email': email,
          'timestamp': DateTime.now().toIso8601String(),
        },
        level: LogLevel.info,
      );
      return credential;
    } on FirebaseAuthException catch (e) {
      throw FirebaseAuthException(
        code: e.code,
        message: _mapAuthError(e),
      );
    }
  }

  Future<UserCredential> signInWithGoogle() async {
    try {
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        throw FirebaseAuthException(
          code: 'aborted-by-user',
          message: 'Google sign-in was cancelled.',
        );
      }

      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCredential = await _auth.signInWithCredential(credential);
      final user = userCredential.user;

      if (user != null) {
        final docRef = _firestore.collection('users').doc(user.uid);
        final doc = await docRef.get();

        if (!doc.exists) {
          final userModel = UserModel(
            id: user.uid,
            name: user.displayName ?? '',
            email: user.email ?? '',
            profileImageUrl: user.photoURL,
            createdAt: DateTime.now(),
          );
          await docRef.set(userModel.toFirestore());
        }
      }

      await _loggingService.logAction(
        action: 'User Login',
        category: 'auth',
        details: 'Signed in with Google',
        metadata: {
          'method': 'google',
          'email': user?.email,
          'userId': user?.uid,
          'timestamp': DateTime.now().toIso8601String(),
        },
        level: LogLevel.info,
      );

      return userCredential;
    } on FirebaseAuthException catch (e) {
      throw FirebaseAuthException(
        code: e.code,
        message: _mapAuthError(e),
      );
    } catch (_) {
      throw FirebaseAuthException(
        code: 'unknown',
        message: 'Google sign-in failed. Please try again.',
      );
    }
  }

  Future<void> signOut() async {
    final user = _auth.currentUser;
    if (user != null) {
      final providers =
          user.providerData.map((info) => info.providerId).toList();
      final provider = providers.contains('google.com') ? 'google' : 'email';
      await _loggingService.logAction(
        action: 'User Logout',
        category: 'auth',
        details: 'Signed out',
        metadata: {
          'method': provider,
          'email': user.email,
          'userId': user.uid,
          'timestamp': DateTime.now().toIso8601String(),
        },
        level: LogLevel.info,
      );
    }
    await _auth.signOut();
    if (await _googleSignIn.isSignedIn()) {
      await _googleSignIn.signOut();
    }
  }

  /// Stream user data for real-time updates
  Stream<UserModel?> watchUserData(String uid) {
    return _firestore.collection('users').doc(uid).snapshots().map((doc) {
      if (!doc.exists || doc.data() == null) {
        return null;
      }
      return UserModel.fromFirestore(doc);
    }).handleError((error, stackTrace) {
      // Log error but continue stream - errors are handled by provider
      // Stream will continue with next snapshot
    });
  }

  Future<UserModel?> getUserData(String uid) async {
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      return doc.exists ? UserModel.fromFirestore(doc) : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> updateUserData(String uid, Map<String, dynamic> data) async {
    await _firestore.collection('users').doc(uid).update(data);
  }

  Future<void> resetPassword(String email) async {
    await _auth.sendPasswordResetEmail(email: email);
  }

  Future<void> deleteAccount(String password) async {
    final user = _auth.currentUser;
    if (user == null || user.email == null) {
      throw FirebaseAuthException(
        code: 'user-not-found',
        message: 'Session expired. Please sign in again.',
      );
    }

    try {
      final credential = EmailAuthProvider.credential(
        email: user.email!,
        password: password,
      );

      await user.reauthenticateWithCredential(credential).timeout(
            const Duration(seconds: 10),
          );

      await _firestore.collection('users').doc(user.uid).delete();
      await user.delete();
    } on FirebaseAuthException catch (e) {
      throw FirebaseAuthException(
        code: e.code,
        message: _mapDeleteAccountError(e),
      );
    } on FirebaseException catch (e) {
      throw FirebaseAuthException(
        code: e.code,
        message: 'Failed to remove your data. Please try again.',
      );
    } on TimeoutException {
      throw FirebaseAuthException(
        code: 'timeout',
        message: 'Request timed out. Please check your connection.',
      );
    } catch (_) {
      throw FirebaseAuthException(
        code: 'unknown',
        message: 'Failed to delete account. Please try again.',
      );
    }
  }

  String _mapDeleteAccountError(FirebaseAuthException e) {
    switch (e.code) {
      case 'wrong-password':
        return 'Current password is incorrect.';
      case 'requires-recent-login':
        return 'Please log in again and retry account deletion.';
      case 'network-request-failed':
        return 'Network error. Please check your connection.';
      default:
        return e.message ?? 'Failed to delete account. Please try again.';
    }
  }
}
