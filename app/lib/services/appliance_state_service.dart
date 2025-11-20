import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../core/utils/logger.dart';

/// Service to persist and restore appliance state (fan speed, brightness, security)
class ApplianceStateService {
  static final ApplianceStateService _instance = ApplianceStateService._internal();
  factory ApplianceStateService() => _instance;
  ApplianceStateService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const String _collection = 'appliance_states';

  /// Save appliance state to Firebase
  Future<void> saveApplianceState({
    required int fanSpeed,
    required int ledBrightness,
    required bool securityEnabled,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      Logger.warning('ApplianceStateService: No user, cannot save state');
      return;
    }

    try {
      await _firestore
          .collection('users')
          .doc(user.uid)
          .collection(_collection)
          .doc('current')
          .set({
        'fanSpeed': fanSpeed,
        'ledBrightness': ledBrightness,
        'securityEnabled': securityEnabled,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      Logger.info('ApplianceStateService: State saved - Fan: $fanSpeed, LED: $ledBrightness, Security: $securityEnabled');
    } catch (e) {
      Logger.error('ApplianceStateService: Error saving state: $e');
    }
  }

  /// Load appliance state from Firebase
  Future<Map<String, dynamic>?> loadApplianceState() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      Logger.warning('ApplianceStateService: No user, cannot load state');
      return null;
    }

    try {
      final doc = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection(_collection)
          .doc('current')
          .get();

      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        Logger.info('ApplianceStateService: State loaded - Fan: ${data['fanSpeed']}, LED: ${data['ledBrightness']}, Security: ${data['securityEnabled']}');
        return {
          'fanSpeed': data['fanSpeed'] ?? 0,
          'ledBrightness': data['ledBrightness'] ?? 0,
          'securityEnabled': data['securityEnabled'] ?? false,
        };
      }
      return null;
    } catch (e) {
      Logger.error('ApplianceStateService: Error loading state: $e');
      return null;
    }
  }

  /// Stream appliance state changes
  Stream<Map<String, dynamic>?> watchApplianceState() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Stream.value(null);
    }

    return _firestore
        .collection('users')
        .doc(user.uid)
        .collection(_collection)
        .doc('current')
        .snapshots()
        .map((doc) {
      try {
        if (doc.exists && doc.data() != null) {
          final data = doc.data()!;
          return {
            'fanSpeed': data['fanSpeed'] ?? 0,
            'ledBrightness': data['ledBrightness'] ?? 0,
            'securityEnabled': data['securityEnabled'] ?? false,
          };
        }
        return null;
      } catch (e) {
        Logger.error('ApplianceStateService: Error parsing stream data: $e');
        return null;
      }
    }).handleError((error) {
      Logger.error('ApplianceStateService: Stream error: $error');
      // Return null on error to prevent stream from closing
    });
  }
}

