import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  // Replace with your values
  static const _url = 'https://ytoabjtymdvdwcybkzyc.supabase.co';
  static const _anonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inl0b2FianR5bWR2ZHdjeWJrenljIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTc5NTkxMTEsImV4cCI6MjA3MzUzNTExMX0.0d7D2RkmFye61zeh87gLrDizfdsf71z2631SUrG5lJI';

  static late final SupabaseClient client;

  static Future<void> initialize() async {
    await Supabase.initialize(
      url: _url,
      anonKey: _anonKey,
    );
    client = Supabase.instance.client;
  }

  /// Insert or update a device state
  static Future<void> upsertDeviceState(Map<String, dynamic> payload) async {
    try {
      await client.from('devices').upsert(payload);
    } catch (e) {
      // handle error
      // debugPrint("Supabase upsert error: $e");
    }
  }

  /// Fetch logs
  static Future<List<Map<String, dynamic>>> fetchLogs() async {
    try {
      final data = await client
          .from('logs')
          .select()
          .order('created_at', ascending: false);

      return (data as List).cast<Map<String, dynamic>>();
    } catch (e) {
      return [];
    }
  }

  /// Insert a log entry
  static Future<void> insertLog(String message) async {
    try {
      await client.from('logs').insert({'message': message});
    } catch (e) {
      // handle error
    }
  }

  /// Fetch devices
  static Future<List<Map<String, dynamic>>> fetchDevices() async {
    try {
      final data = await client.from('devices').select();
      return (data as List).cast<Map<String, dynamic>>();
    } catch (e) {
      return [];
    }
  }
}
