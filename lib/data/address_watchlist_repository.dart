import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

class AddressWatchlistRepository {
  AddressWatchlistRepository._(this._prefs);

  static const _storageKey = 'watchlist_addresses_v1';

  final SharedPreferences _prefs;

  static Future<AddressWatchlistRepository> load() async {
    final prefs = await SharedPreferences.getInstance();
    return AddressWatchlistRepository._(prefs);
  }

  List<WatchedAddress> loadAddresses() {
    try {
      final raw = _prefs.getString(_storageKey);
      if (raw == null || raw.isEmpty) return const [];
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map((item) =>
          WatchedAddress.fromJson(item as Map<String, dynamic>))
          .where((addr) => addr.address.isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveAddresses(List<WatchedAddress> addresses) async {
    final payload =
    jsonEncode(addresses.map((e) => e.toJson()).toList(growable: false));
    await _prefs.setString(_storageKey, payload);
  }
}