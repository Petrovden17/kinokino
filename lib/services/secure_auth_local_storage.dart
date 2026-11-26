import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Android stores the Supabase session in SharedPreferences so Android Auto
/// Backup can restore it after reinstall (when the user's Google/device backup
/// is enabled). Windows continues to use OS-protected secure storage.
class SecureAuthLocalStorage extends LocalStorage {
  static const String _sessionKey =
      'sb-rsubtcrfnpqijpwjcbyc-auth-token';

  final FlutterSecureStorage _secure = const FlutterSecureStorage();
  late final SharedPreferencesLocalStorage _legacy =
      SharedPreferencesLocalStorage(persistSessionKey: _sessionKey);

  bool get _useAndroidBackupStorage =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  Future<void> initialize() async {
    await _legacy.initialize();

    // Android Keystore keys are removed on uninstall, so encrypted storage
    // cannot be decrypted after reinstall. Keep the Supabase refresh session
    // in the app's backed-up SharedPreferences on Android instead.
    if (_useAndroidBackupStorage) return;

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
    if (_useAndroidBackupStorage) return _legacy.accessToken();

    final session = await _secure.read(key: _sessionKey);
    if (session != null && session.isNotEmpty) return session;
    return _legacy.accessToken();
  }

  @override
  Future<bool> hasAccessToken() async {
    if (_useAndroidBackupStorage) return _legacy.hasAccessToken();

    if (await _secure.containsKey(key: _sessionKey)) return true;
    return _legacy.hasAccessToken();
  }

  @override
  Future<void> persistSession(String persistSessionString) async {
    if (_useAndroidBackupStorage) {
      await _legacy.persistSession(persistSessionString);
      return;
    }

    await _secure.write(key: _sessionKey, value: persistSessionString);
    await _legacy.removePersistedSession();
  }

  @override
  Future<void> removePersistedSession() async {
    await _secure.delete(key: _sessionKey);
    await _legacy.removePersistedSession();
  }
}
