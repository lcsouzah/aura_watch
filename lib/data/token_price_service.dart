import 'dart:convert';

import 'package:http/http.dart' as http;

class TokenPriceService {
  const TokenPriceService._();

  static Future<Map<String, double>> fetchUsdPrices(List<String> tokenIds,
      {http.Client? client}) async {
    if (tokenIds.isEmpty) {
      return const {};
    }
    final ids = tokenIds.map((e) => e.trim().toLowerCase()).where((e) => e.isNotEmpty).toList();
    if (ids.isEmpty) {
      return const {};
    }
    final httpClient = client ?? http.Client();
    final shouldClose = client == null;
    try {
      final joined = ids.join(',');
      final uri = Uri.parse(
          'https://api.coingecko.com/api/v3/simple/price?ids=$joined&vs_currencies=usd');
      final res = await httpClient.get(uri);
      if (res.statusCode != 200) {
        throw Exception('Price check failed ${res.statusCode}');
      }
      final decoded = jsonDecode(res.body) as Map<String, dynamic>;
      return decoded.map((key, value) {
        final usd = (value as Map<String, dynamic>)['usd'] as num?;
        return MapEntry(key, usd?.toDouble() ?? 0.0);
      });
    } finally {
      if (shouldClose) {
        httpClient.close();
      }
    }
  }
}