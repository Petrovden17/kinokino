import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_settings.dart';

class SettingsService extends ChangeNotifier {
  static const _key = 'kinokino_settings_v1';
  static const _lastUpdateCheckKey = 'kinokino_last_update_check';
  AppSettings _settings = const AppSettings();
  AppSettings get settings => _settings;

  Future<DateTime?> lastUpdateCheck() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getInt(_lastUpdateCheckKey);
    return value == null ? null : DateTime.fromMillisecondsSinceEpoch(value);
  }

  Future<void> markUpdateCheck() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_lastUpdateCheckKey, DateTime.now().millisecondsSinceEpoch);
  }

  Future<bool> isUpdateCheckDue(int intervalHours) async {
    final last = await lastUpdateCheck();
    return last == null || DateTime.now().difference(last) >= Duration(hours: intervalHours);
  }

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw != null) {
      try { _settings = AppSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>); }
      catch (_) { _settings = const AppSettings(); }
    }
  }

  Future<void> update(AppSettings value) async {
    _settings = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(value.toJson()));
    notifyListeners();
  }
}
