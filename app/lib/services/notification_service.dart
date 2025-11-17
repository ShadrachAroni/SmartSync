import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import '../core/utils/logger.dart';

class NotificationService {
  NotificationService._internal();
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool _initialized = false;

  Future<void> initialize(String userId) async {
    if (_initialized) return;

    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      Logger.warning('Notification permission denied');
      return;
    }

    final token = await _messaging.getToken();
    if (token != null) {
      await _firestore.collection('users').doc(userId).set({
        'deviceTokens': FieldValue.arrayUnion([token]),
      }, SetOptions(merge: true));
      Logger.success('Registered FCM token');
    }

    FirebaseMessaging.onMessage.listen((message) {
      Logger.info('Foreground notification: ${message.notification?.title}');
    });

    _initialized = true;
  }

  Future<void> updateAlertPreferences(
      String userId, Map<String, bool> prefs) async {
    await _firestore.collection('users').doc(userId).set({
      'preferences': {
        'notifications': prefs,
      },
    }, SetOptions(merge: true));
  }

  Future<void> subscribeTopic(String topic) =>
      _messaging.subscribeToTopic(topic);
  Future<void> unsubscribeTopic(String topic) =>
      _messaging.unsubscribeFromTopic(topic);
}
