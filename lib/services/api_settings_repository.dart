import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../data/models.dart';

class ApiSettingsRepository {
  ApiSettingsRepository._();

  static final ApiSettingsRepository instance = ApiSettingsRepository._();

  static const _storageKey = 'api_settings_v1';

  Future<ApiSettings?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) return null;

    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return ApiSettings.fromJson(map);
    } catch (_) {
      return null;
    }
  }

  Future<void> save(ApiSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = jsonEncode(settings.toJson());
    await prefs.setString(_storageKey, jsonStr);
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
  }
}