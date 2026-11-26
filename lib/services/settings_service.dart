import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_settings.dart';

class SettingsService {
  static const _key = 'kinokino_settings_v1';
  AppSettings _settings = const AppSettings();
  AppSettings get settings => _settings;

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
  }
}
