import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_profile.dart';

class ProfileService {
  static const _storageKey = 'kinokino_profiles_v1';
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final List<UserProfile> _profiles = [];
  String? _activeId;
  final _uuid = const Uuid();

  List<UserProfile> get profiles => List.unmodifiable(_profiles);
  UserProfile? get activeProfile {
    for (final p in _profiles) { if (p.id == _activeId) return p; }
    return null;
  }

  Future<void> initialize() async {
    String? raw;
    try { raw = await _storage.read(key: _storageKey); }
    catch (_) {
      final prefs = await SharedPreferences.getInstance();
      raw = prefs.getString(_storageKey);
    }
    if (raw != null) {
      final decoded = jsonDecode(raw) as List;
      _profiles.addAll(decoded.map((e) => UserProfile.fromJson(Map<String, dynamic>.from(e))));
    }
    try { _activeId = await _storage.read(key: 'kinokino_active_profile'); }
    catch (_) {
      final prefs = await SharedPreferences.getInstance();
      _activeId = prefs.getString('kinokino_active_profile');
    }
  }

  Future<String> createProfile({
    required String name, required String password,
    required bool isChild, String? pin,
  }) async {
    if (_profiles.length >= 8) throw Exception('Можно создать не более 8 профилей.');
    if (name.trim().length < 2) throw Exception('Имя должно содержать минимум 2 символа.');
    if (password.length < 8) throw Exception('Пароль должен содержать минимум 8 символов.');
    if (isChild && (pin == null || !RegExp(r'^\d{4,6}$').hasMatch(pin))) {
      throw Exception('Для детского профиля задайте PIN из 4–6 цифр.');
    }
    final recovery = _newRecoveryCode();
    final salt = _randomSalt();
    final recoverySalt = _randomSalt();
    final pinSalt = isChild ? _randomSalt() : null;
    final profile = UserProfile(
      id: _uuid.v4(), name: name.trim(), isChild: isChild,
      passwordSalt: salt, passwordHash: _hash(password, salt),
      recoverySalt: recoverySalt, recoveryHash: _hash(_normalizeRecovery(recovery), recoverySalt),
      pinSalt: pinSalt, pinHash: pinSalt == null ? null : _hash(pin!, pinSalt),
    );
    _profiles.add(profile);
    await _save();
    if (_activeId == null) await selectProfile(profile.id);
    return recovery;
  }

  Future<bool> authenticate(String id, String password) async {
    final p = _byId(id);
    return p != null && _constantEquals(_hash(password, p.passwordSalt), p.passwordHash);
  }

  Future<bool> authenticatePin(String id, String pin) async {
    final p = _byId(id);
    if (p == null || p.pinSalt == null || p.pinHash == null) return false;
    return _constantEquals(_hash(pin, p.pinSalt!), p.pinHash!);
  }

  Future<bool> recoverPassword(String id, String recoveryCode, String newPassword) async {
    final p = _byId(id);
    if (p == null || newPassword.length < 8) return false;
    if (!_constantEquals(_hash(_normalizeRecovery(recoveryCode), p.recoverySalt), p.recoveryHash)) return false;
    final salt = _randomSalt();
    _replace(p, UserProfile(
      id: p.id, name: p.name, isChild: p.isChild,
      passwordSalt: salt, passwordHash: _hash(newPassword, salt),
      recoverySalt: p.recoverySalt, recoveryHash: p.recoveryHash,
      pinSalt: p.pinSalt, pinHash: p.pinHash,
    ));
    await _save();
    return true;
  }

  Future<void> selectProfile(String id) async {
    if (_byId(id) == null) throw Exception('Профиль не найден.');
    _activeId = id;
    await _writeValue('kinokino_active_profile', id);
  }

  Future<void> deleteProfile(String id) async {
    _profiles.removeWhere((p) => p.id == id);
    if (_activeId == id) {
      _activeId = _profiles.isEmpty ? null : _profiles.first.id;
      if (_activeId == null) {
        try { await _storage.delete(key: 'kinokino_active_profile'); } catch (_) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.remove('kinokino_active_profile');
        }
      } else {
        await _writeValue('kinokino_active_profile', _activeId!);
      }
    }
    await _save();
  }

  UserProfile? _byId(String id) {
    for (final p in _profiles) { if (p.id == id) return p; }
    return null;
  }

  void _replace(UserProfile old, UserProfile value) {
    final i = _profiles.indexWhere((p) => p.id == old.id);
    if (i >= 0) _profiles[i] = value;
  }

  Future<void> _save() => _writeValue(
    _storageKey,
    jsonEncode(_profiles.map((p) => p.toJson()).toList()),
  );

  Future<void> _writeValue(String key, String value) async {
    try { await _storage.write(key: key, value: value); }
    catch (_) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, value);
    }
  }

  String _newRecoveryCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random.secure();
    final parts = List.generate(4, (_) =>
      List.generate(4, (_) => chars[random.nextInt(chars.length)]).join());
    return parts.join('-');
  }

  String _randomSalt() {
    final random = Random.secure();
    return base64UrlEncode(List.generate(16, (_) => random.nextInt(256)));
  }

  // PBKDF2-HMAC-SHA256; 120,000 iterations. Never stores the original password/PIN.
  String _hash(String value, String salt) {
    final key = utf8.encode(value);
    final saltBytes = utf8.encode(salt);
    final hmac = Hmac(sha256, key);
    var u = hmac.convert([...saltBytes, 0, 0, 0, 1]).bytes;
    final result = List<int>.from(u);
    for (var i = 1; i < 120000; i++) {
      u = hmac.convert(u).bytes;
      for (var j = 0; j < result.length; j++) { result[j] ^= u[j]; }
    }
    return base64UrlEncode(result);
  }

  String _normalizeRecovery(String value) =>
      value.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

  bool _constantEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) { diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i); }
    return diff == 0;
  }
}
