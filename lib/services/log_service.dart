import 'package:hive_flutter/hive_flutter.dart';

part 'log_entry.g.dart';

@HiveType(typeId: 1)
class LogEntry {
  @HiveField(0)
  final DateTime at;
  @HiveField(1)
  final String message;

  LogEntry(this.at, this.message);
}

class LogService {
  static Box<LogEntry>? _box;

  static Future<void> init() async {
    // Register adapter once
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(LogEntryAdapter());
    }
    // Open or reuse
    if (!Hive.isBoxOpen('logs')) {
      _box = await Hive.openBox<LogEntry>('logs');
    } else {
      _box = Hive.box<LogEntry>('logs');
    }
  }

  static Future<void> add(String message) async {
    final box = _box ??
        (Hive.isBoxOpen('logs')
            ? Hive.box<LogEntry>('logs')
            : await Hive.openBox<LogEntry>('logs'));
    await box.add(LogEntry(DateTime.now(), message));
  }

  static List<LogEntry> all() {
    final box =
        _box ?? (Hive.isBoxOpen('logs') ? Hive.box<LogEntry>('logs') : null);
    if (box == null) return const [];
    return box.values.toList().reversed.toList();
  }

  static Future<void> addRoom(String room, String message) async {
    await add('[$room] $message');
  }

  static Future<void> clear() async {
    final box = _box ??
        (Hive.isBoxOpen('logs')
            ? Hive.box<LogEntry>('logs')
            : await Hive.openBox<LogEntry>('logs'));
    await box.clear();
  }
}
