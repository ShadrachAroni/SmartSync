// lib/services/adaptive_scheduler.dart
import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import 'automation_service.dart';
import 'notification_service.dart';

class AdaptiveScheduler {
  static const _unique = 'smartsync_adaptive_task';
  static const _name = 'evaluateAutomationAdaptive';
  static const _kLastActive = 'as_last_active';
  static const _kLastRun = 'as_last_run';
  static const _kBackoff = 'as_backoff_step';

  static Timer? _desktopTimer;

  static bool get _isMobile =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  static Future<void> bump({String reason = 'interaction'}) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setInt(_kLastActive, DateTime.now().millisecondsSinceEpoch);
    await sp.setInt(_kBackoff, 0);
  }

  static Future<void> init() async {
    await scheduleNext();
  }

  static Future<Duration> _computeNextInterval() async {
    final sp = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final lastActiveMs = sp.getInt(_kLastActive) ?? 0;
    final lastActive = DateTime.fromMillisecondsSinceEpoch(lastActiveMs);
    final sinceActive = now.difference(lastActive);

    if (sinceActive.inMinutes <= 20) return const Duration(minutes: 10);
    if (sinceActive.inHours <= 2) return const Duration(minutes: 30);

    final step = (sp.getInt(_kBackoff) ?? 0).clamp(0, 2);
    return Duration(minutes: 60 * (step + 1));
  }

  static Future<void> scheduleNext() async {
    final delay = await _computeNextInterval();

    if (_isMobile) {
      await Workmanager().cancelByUniqueName(_unique);
      await Workmanager().registerOneOffTask(
        _unique,
        _name,
        initialDelay: delay,
        // FIX: remove `const` — Constraints is not a const constructor.
        constraints: Constraints(networkType: NetworkType.not_required),
        existingWorkPolicy: ExistingWorkPolicy.replace,
      );
    } else {
      _desktopTimer?.cancel();
      _desktopTimer = Timer(delay, () async {
        await AutomationService.evaluateDueRules(headless: false);
        await NotificationService.scheduleOnce(
          id: DateTime.now().millisecondsSinceEpoch & 0x7fffffff,
          atLocal: DateTime.now().add(const Duration(seconds: 1)),
          title: 'Automation check',
          body: 'Adaptive scan completed',
        );
        await _afterRun(success: true);
        await scheduleNext();
      });
    }
  }

  static Future<void> onBackgroundRun({required bool success}) async {
    await AutomationService.evaluateDueRules(headless: true);
    await _afterRun(success: success);
    await scheduleNext();
  }

  static Future<void> _afterRun({required bool success}) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setInt(_kLastRun, DateTime.now().millisecondsSinceEpoch);
    if (success) {
      await sp.setInt(_kBackoff, 0);
    } else {
      final step = (sp.getInt(_kBackoff) ?? 0) + 1;
      await sp.setInt(_kBackoff, step.clamp(0, 2));
    }
  }
}
