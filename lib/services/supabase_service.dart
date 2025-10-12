import 'package:supabase_flutter/supabase_flutter.dart';
import '../app_config.dart';

final supa = Supabase.instance.client;

class SupabaseService {
  static Future<AuthResponse> signUp({
    required String email,
    required String password,
    required String username,
  }) {
    return supa.auth.signUp(
      email: email,
      password: password,
      data: {'username': username},
    );
  }

  static Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) =>
      supa.auth.signInWithPassword(email: email, password: password);

  static Future<void> signOut() => supa.auth.signOut();

  static Future<void> sendResetPasswordEmail(String email) async {
    await supa.auth
        .resetPasswordForEmail(email, redirectTo: AppConfig.resetScheme);
  }

  static Future<void> updatePassword(String newPassword) async {
    await supa.auth.updateUser(UserAttributes(password: newPassword));
  }

  static Future<Map<String, dynamic>?> getMyProfile() async {
    final uid = supa.auth.currentUser?.id;
    if (uid == null) return null;
    final data =
        await supa.from('profiles').select().eq('id', uid).maybeSingle();
    return data;
  }

  static Future<void> updateUsername(String username) async {
    final uid = supa.auth.currentUser?.id;
    if (uid == null) return;
    await supa.from('profiles').update({'username': username}).eq('id', uid);
  }
}
