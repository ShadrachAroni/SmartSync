import 'package:hive_flutter/hive_flutter.dart';
import 'notification_service.dart';
import 'ble_service.dart';
import 'log_service.dart';

part 'automation_rule.g.dart';

@HiveType(typeId: 2)
class AutomationRule {
  @HiveField(0)
  final String id;
  @HiveField(1)
  final String name;
  @HiveField(2)
  final DateTime? at; // scheduled time (local)
  @HiveField(3)
  final bool daily; // repeat daily if true
  @HiveField(4)
  final Map<String, dynamic>
      action; // {'fan':70} | {'bulb':40} | {'alarm':true}

  const AutomationRule({
    required this.id,
    required this.name,
    required this.at,
    required this.daily,
    required this.action,
  });
}

class AutomationService {
  static Box<AutomationRule>? _box;

  static Future<void> init() async {
    // Idempotent adapter registration
    if (!Hive.isAdapterRegistered(2)) {
      Hive.registerAdapter(AutomationRuleAdapter());
    }
    // Open or reuse box
    if (!Hive.isBoxOpen('automation')) {
      _box = await Hive.openBox<AutomationRule>('automation');
    } else {
      _box = Hive.box<AutomationRule>('automation');
    }
  }

  static Future<void> initIfNeeded() async {
    if (_box != null && _box!.isOpen) return;
    await init();
  }

  static List<AutomationRule> list() {
    final box = _box ??
        (Hive.isBoxOpen('automation')
            ? Hive.box<AutomationRule>('automation')
            : null);
    if (box == null) return const [];
    return box.values.toList();
  }

  static Future<void> add(AutomationRule r) async {
    await initIfNeeded();
    await _box!.put(r.id, r);
    await LogService.add('Rule added: ${r.name}');
  }

  static Future<void> remove(String id) async {
    await initIfNeeded();
    await _box!.delete(id);
    await LogService.add('Rule removed: $id');
  }

  // Evaluate due rules; called from Workmanager or desktop Timer
  static Future<void> evaluateDueRules({bool headless = false}) async {
    await initIfNeeded();
    final now = DateTime.now();
    for (final rule in _box!.values) {
      final t = rule.at;
      if (t == null) continue;

      // Compare hour/minute to trigger in a 1‑minute window
      final due = DateTime(now.year, now.month, now.day, t.hour, t.minute);
      if (now.difference(due).inMinutes.abs() <= 1) {
        await _perform(rule.action);
        await LogService.add('Automation fired: ${rule.name}');
        // Notify user
        await NotificationService.scheduleOnce(
          id: rule.id.hashCode & 0x7fffffff,
          atLocal: now.add(const Duration(seconds: 1)),
          title: 'Automation executed',
          body: rule.name,
        );
        if (!rule.daily) {
          await _box!.delete(rule.id);
        }
      }
    }
  }

  static Future<void> _perform(Map<String, dynamic> action) async {
    final ble = BLEService();
    if (action.containsKey('fan')) {
      await ble.setFanSpeed(action['fan'] as int);
    }
    if (action.containsKey('bulb')) {
      await ble.setBulbIntensity(action['bulb'] as int);
    }
    if (action.containsKey('alarm')) {
      await ble.setAlarm(action['alarm'] as bool);
    }
  }
}
