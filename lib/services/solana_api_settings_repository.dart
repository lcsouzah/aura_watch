import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import '../data/models.dart';

class SolanaApiSettingsRepository {
  SolanaApiSettingsRepository._();

  static final SolanaApiSettingsRepository instance =
  SolanaApiSettingsRepository._();

  static const _storageKey = 'solana_api_settings_v1';

  Future<SolanaApiSettings?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) return null;

    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return SolanaApiSettings.fromJson(map);
    } catch (_) {
      return null;
    }
  }

  Future<void> save(SolanaApiSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = jsonEncode(settings.toJson());
    await prefs.setString(_storageKey, jsonStr);
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
  }
}