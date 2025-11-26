import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/utils/logger.dart';
import '../services/firebase_service.dart';

class NotificationService {
  NotificationService._internal();
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  bool _localNotificationsInitialized = false;

  Future<void> initialize(String userId) async {
    if (_initialized) return;

    // Initialize FCM (Firebase Cloud Messaging)
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      Logger.warning('Notification permission denied');
      return;
    }

    await _registerDeviceToken(userId);

    FirebaseMessaging.onMessage.listen((message) {
      Logger.info('Foreground notification: ${message.notification?.title}');
    });

    // Initialize local notifications
    await _initializeLocalNotifications();

    _initialized = true;
  }
  
  /// Initialize local notifications plugin
  Future<void> _initializeLocalNotifications() async {
    if (_localNotificationsInitialized) return;

    try {
      // Request notification permission
      final status = await Permission.notification.request();
      if (status.isDenied) {
        Logger.warning('Local notification permission denied');
        return;
      }

      // Android initialization settings
      const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
      
      // iOS initialization settings
      const iosSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );

      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );

      final initialized = await _localNotifications.initialize(
        initSettings,
        onDidReceiveNotificationResponse: _onNotificationTapped,
      );

      if (initialized == true) {
        _localNotificationsInitialized = true;
        Logger.success('Local notifications initialized');
      } else {
        Logger.warning('Failed to initialize local notifications');
      }
    } catch (e) {
      Logger.error('Error initializing local notifications: $e');
    }
  }
  
  /// Handle notification tap
  /// 
  /// This is called when a user taps on a local notification.
  /// For automation notifications, this could navigate to the logs screen.
  void _onNotificationTapped(NotificationResponse response) {
    Logger.info('Notification tapped: ${response.payload}');
    
    if (response.payload != null) {
      try {
        final data = jsonDecode(response.payload!) as Map<String, dynamic>;
        final type = data['type'] as String?;
        
        if (type == 'automation_change') {
          final changeId = data['changeId'] as String?;
          final deviceType = data['deviceType'] as String?;
          Logger.info('Automation notification tapped: $deviceType change ($changeId)');
          Logger.info('   → User can view and revert this change in Activity Logs');
          // Note: Navigation to logs screen would require a global navigator key
          // This can be added later if needed. For now, the notification serves
          // as an alert and users can manually navigate to logs.
        } else {
          Logger.info('Notification payload: $data');
        }
      } catch (e) {
        Logger.warning('Failed to parse notification payload: $e');
      }
    }
  }
  
  /// Show a local notification
  /// 
  /// This will show a phone notification AND save it to the alerts screen
  Future<void> showLocalNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
    NotificationDetails? details,
    bool saveToAlerts = true, // Default to true - save all notifications to alerts
  }) async {
    if (!_localNotificationsInitialized) {
      await _initializeLocalNotifications();
      if (!_localNotificationsInitialized) {
        Logger.warning('Cannot show notification: Local notifications not initialized');
        return;
      }
    }

    try {
      final notificationDetails = details ?? _getDefaultNotificationDetails();
      
      await _localNotifications.show(
        id,
        title,
        body,
        notificationDetails,
        payload: payload,
      );
      
      Logger.info('Local notification shown: $title');
      
      // CRITICAL: Save notification to alerts screen
      if (saveToAlerts) {
        _saveNotificationToAlerts(title, body, payload);
      }
    } catch (e) {
      Logger.error('Failed to show local notification: $e');
    }
  }
  
  /// Save notification to alerts collection in Firestore
  Future<void> _saveNotificationToAlerts(String title, String body, String? payload) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        Logger.debug('NotificationService: No user logged in, skipping alert creation');
        return;
      }

      // Parse payload to determine type and severity
      String type = 'general';
      String severity = 'low';
      Map<String, dynamic> alertData = {
        'title': title,
        'payload': payload,
      };

      if (payload != null) {
        try {
          final payloadData = jsonDecode(payload) as Map<String, dynamic>;
          type = payloadData['type'] as String? ?? 'general';
          alertData.addAll(payloadData);
          
          // Determine severity based on notification type and title
          if (title.contains('⚠️') || title.contains('Disconnected') || 
              title.contains('Shut Down') || title.contains('Error')) {
            severity = 'high';
          } else if (title.contains('🔍') || title.contains('Found')) {
            severity = 'medium';
          } else if (title.contains('✅') || title.contains('Updated')) {
            severity = 'low';
          }
        } catch (e) {
          Logger.warning('NotificationService: Failed to parse payload: $e');
        }
      } else {
        // Determine severity from title if no payload
        if (title.contains('⚠️') || title.contains('Disconnected') || 
            title.contains('Shut Down') || title.contains('Error')) {
          severity = 'high';
        } else if (title.contains('🔍') || title.contains('Found')) {
          severity = 'medium';
        } else if (title.contains('✅') || title.contains('Updated')) {
          severity = 'low';
        }
      }

      // Create alert in Firestore
      final firebaseService = FirebaseService();
      await firebaseService.createAlert(
        userId: user.uid,
        type: type,
        severity: severity,
        message: body, // Use body as the alert message
        data: alertData,
      );
      
      Logger.info('NotificationService: Saved notification to alerts: $title');
    } catch (e) {
      // Don't fail notification if alert creation fails
      Logger.warning('NotificationService: Failed to save notification to alerts: $e');
    }
  }
  
  /// Get default notification details
  NotificationDetails _getDefaultNotificationDetails() {
    const androidDetails = AndroidNotificationDetails(
      'automation_channel',
      'Automation Changes',
      channelDescription: 'Notifications for automation system changes',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
      enableVibration: true,
      playSound: true,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    return const NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );
  }
  
  /// Show automation change notification
  Future<void> showAutomationNotification({
    required String deviceType,
    required int previousValue,
    required int newValue,
    required String reason,
    required String changeId,
  }) async {
    final deviceName = deviceType == 'fan' ? 'Fan' : 'Light';
    final changeText = newValue > previousValue ? 'increased' : 'decreased';
    
    final title = '🤖 Automation Adjustment';
    final body = '$deviceName $changeText from $previousValue% to $newValue%\n$reason';
    
    final payload = jsonEncode({
      'type': 'automation_change',
      'changeId': changeId,
      'deviceType': deviceType,
      'previousValue': previousValue,
      'newValue': newValue,
    });
    
    await showLocalNotification(
      id: changeId.hashCode.abs() % 2147483647, // Use changeId hash as notification ID
      title: title,
      body: body,
      payload: payload,
    );
  }

  Future<void> updateAlertPreferences(
      String userId, Map<String, bool> prefs) async {
    await _firestore.collection('users').doc(userId).set({
      'preferences': {
        'notifications': prefs,
      },
    }, SetOptions(merge: true));
  }

  Future<bool?> getStoredPreference(String userId) async {
    try {
      final doc = await _firestore.collection('users').doc(userId).get();
      return (doc.data()?['preferences']?['notificationsEnabled']) as bool?;
    } catch (e) {
      Logger.warning('NotificationService: Failed to load preference: $e');
      return null;
    }
  }

  Future<void> updateGlobalNotificationPreference(
      String userId, bool enabled) async {
    await _firestore.collection('users').doc(userId).set({
      'preferences': {
        'notificationsEnabled': enabled,
      },
    }, SetOptions(merge: true));

    if (enabled) {
      await _registerDeviceToken(userId);
    } else {
      await _removeDeviceToken(userId);
    }
  }

  Future<bool> isSystemPermissionGranted() async {
    try {
      final settings = await _messaging.getNotificationSettings();
      if (settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional) {
        return true;
      }
    } catch (e) {
      Logger.warning('NotificationService: Failed to get FCM settings: $e');
    }

    final status = await Permission.notification.status;
    return status.isGranted;
  }

  Future<void> _registerDeviceToken(String userId) async {
    try {
      final token = await _messaging.getToken();
      if (token != null) {
        await _firestore.collection('users').doc(userId).set({
          'deviceTokens': FieldValue.arrayUnion([token]),
        }, SetOptions(merge: true));
        Logger.success('Registered FCM token');
      }
    } catch (e) {
      Logger.warning('NotificationService: Failed to register FCM token: $e');
    }
  }

  Future<void> _removeDeviceToken(String userId) async {
    try {
      final token = await _messaging.getToken();
      if (token != null) {
        await _firestore.collection('users').doc(userId).set({
          'deviceTokens': FieldValue.arrayRemove([token]),
        }, SetOptions(merge: true));
        Logger.info('NotificationService: Removed FCM token for $userId');
      }
    } catch (e) {
      Logger.warning('NotificationService: Failed to remove FCM token: $e');
    }
  }

  Future<void> subscribeTopic(String topic) =>
      _messaging.subscribeToTopic(topic);
  Future<void> unsubscribeTopic(String topic) =>
      _messaging.unsubscribeFromTopic(topic);
}
