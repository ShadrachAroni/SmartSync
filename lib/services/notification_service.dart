import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;

class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  static Future<void> ensureInitialized() async {
    if (_ready) return;
    tz.initializeTimeZones();
    const initAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initIOS = DarwinInitializationSettings();
    const init = InitializationSettings(android: initAndroid, iOS: initIOS);
    await _plugin.initialize(init);
    _ready = true;
  }

  static Future<void> scheduleOnce({
    required int id,
    required DateTime atLocal,
    required String title,
    required String body,
  }) async {
    await _plugin.zonedSchedule(
      id,
      title,
      body,
      tz.TZDateTime.from(atLocal, tz.local),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'smartsync_main',
          'SmartSync',
          importance: Importance.max,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }
}
