import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

class WatchlistRepository {
  WatchlistRepository._(this._prefs);

  static const _storageKey = 'watchlist_tokens_v1';

  final SharedPreferences _prefs;

  static Future<WatchlistRepository> load() async {
    final prefs = await SharedPreferences.getInstance();
    return WatchlistRepository._(prefs);
  }

  List<WatchedToken> loadTokens() {
    final raw = _prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) {
      return const [];
    }
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map((item) => WatchedToken.fromJson(item as Map<String, dynamic>))
          .where((token) => token.id.isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveTokens(List<WatchedToken> tokens) async {
    final payload = jsonEncode(tokens.map((e) => e.toJson()).toList());
    await _prefs.setString(_storageKey, payload);
  }
}