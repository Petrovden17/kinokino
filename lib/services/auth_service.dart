import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  SupabaseClient get _client => Supabase.instance.client;

  Future<void> signIn({required String email, required String password}) async {
    await _client.auth.signInWithPassword(email: email.trim(), password: password);
  }

  Future<bool> signUp({
    required String email,
    required String password,
    required String displayName,
  }) async {
    final response = await _client.auth.signUp(
      email: email.trim(),
      password: password,
      data: {'display_name': displayName.trim()},
    );
    if (response.session != null && response.user != null) {
      await ensureProfile(response.user!.id, displayName.trim());
      return true;
    }
    return false;
  }

  Future<void> ensureProfile(String userId, [String? displayName]) async {
    await _client.from('profiles').upsert({
      'id': userId,
      if (displayName != null && displayName.isNotEmpty) 'display_name': displayName,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<void> resetPassword(String email) async {
    await _client.auth.resetPasswordForEmail(email.trim());
  }

  Future<void> signOut() => _client.auth.signOut();
}
