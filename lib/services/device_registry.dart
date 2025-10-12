// lib/services/device_registry.dart
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class DeviceRegistry {
  static const _k = 'device_bindings_v1';

  // bleId -> {"room": "...", "label": "..."}
  static Future<Map<String, Map<String, String>>> _read() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_k);
    if (raw == null) return {};
    final m = jsonDecode(raw) as Map<String, dynamic>;
    return m.map((k, v) => MapEntry(k, Map<String, String>.from(v as Map)));
  }

  static Future<void> bind(
      {required String bleId, required String room, String? label}) async {
    final sp = await SharedPreferences.getInstance();
    final m = await _read();
    m[bleId] = {"room": room, "label": label ?? ''};
    await sp.setString(_k, jsonEncode(m));
  }

  static Future<String?> roomFor(String bleId) async {
    final m = await _read();
    return m[bleId]?["room"];
  }

  static Future<Map<String, String>> allRooms() async {
    final m = await _read();
    return {for (final e in m.entries) e.key: e.value["room"] ?? ''};
  }
}
