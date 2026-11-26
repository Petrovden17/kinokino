import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Keeps the Supabase session in Windows-protected storage.
/// Existing SharedPreferences sessions are migrated on the first launch.
class SecureAuthLocalStorage extends LocalStorage {
  static const String _sessionKey =
      'sb-rsubtcrfnpqijpwjcbyc-auth-token';

  final FlutterSecureStorage _secure = const FlutterSecureStorage();
  late final SharedPreferencesLocalStorage _legacy =
      SharedPreferencesLocalStorage(persistSessionKey: _sessionKey);

  @override
  Future<void> initialize() async {
    await _legacy.initialize();

    final existingSecureSession = await _secure.read(key: _sessionKey);
    if (existingSecureSession == null) {
      final existingSession = await _legacy.accessToken();
      if (existingSession != null && existingSession.isNotEmpty) {
        await _secure.write(key: _sessionKey, value: existingSession);
        await _legacy.removePersistedSession();
      }
    }
  }

  @override
  Future<String?> accessToken() async {
    final session = await _secure.read(key: _sessionKey);
    if (session != null && session.isNotEmpty) return session;
    return _legacy.accessToken();
  }

  @override
  Future<bool> hasAccessToken() async {
    if (await _secure.containsKey(key: _sessionKey)) return true;
    return _legacy.hasAccessToken();
  }

  @override
  Future<void> persistSession(String persistSessionString) async {
    await _secure.write(key: _sessionKey, value: persistSessionString);
    await _legacy.removePersistedSession();
  }

  @override
  Future<void> removePersistedSession() async {
    await _secure.delete(key: _sessionKey);
    await _legacy.removePersistedSession();
  }
}
