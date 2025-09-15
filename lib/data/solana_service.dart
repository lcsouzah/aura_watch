import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'models.dart';

class SolanaService {

  /// CoinGecko – SOL price (USD)
  static Future<String> fetchSolPrice() async {
    final uri = Uri.parse('https://api.coingecko.com/api/v3/simple/price?ids=solana&vs_currencies=usd');
    final res = await http.get(uri);
    if (res.statusCode != 200) throw Exception('SOL price error ${res.statusCode}');
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final usd = (data['solana']?['usd'] as num?)?.toDouble();
    if (usd == null) throw Exception('Invalid SOL price payload');
    final formatted = NumberFormat('###,##0.00').format(usd);
    return '\$$formatted';
  }

  /// CoinGecko – Trending tokens (Solana category)
  static Future<List<TokenMarket>> fetchTrendingTokens({int limit = 5}) async {
    final uri = Uri.parse(
      'https://api.coingecko.com/api/v3/coins/markets'
          '?vs_currency=usd&category=solana-ecosystem&order=volume_desc&per_page=$limit',
    );
    final res = await http.get(uri);
    if (res.statusCode != 200) throw Exception('Trending error ${res.statusCode}');
    final list = jsonDecode(res.body) as List<dynamic>;
    return list.map((e) {
      final name = e['name']?.toString() ?? 'Unknown';
      final price = (e['current_price'] as num?)?.toDouble() ?? 0.0;
      final vol = (e['total_volume'] as num?)?.toDouble() ?? 0.0;
      return TokenMarket(name: name, price: price, volume24h: vol);
    }).toList();
  }

  /// Solscan “whale” txs (best-effort; API may change/rate-limit)
  static Future<List<WhaleTx>> fetchWhaleActivity({int limit = 5}) async {
    final uri = Uri.parse('https://api.solscan.io/transaction/whale?limit=$limit');
    final res = await http.get(uri, headers: {'accept': 'application/json'});
    if (res.statusCode != 200) throw Exception('Whales error ${res.statusCode}');
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final arr = (data['data'] as List<dynamic>? ?? []);
    return arr.map((tx) {
      final hash = (tx['txHash']?.toString() ?? '');
      final shortHash = hash.length > 12 ? '${hash.substring(0, 12)}…' : hash;
      // When provided: amount = lamports; format to SOL
      final amountLamports = (tx['amount'] as num?)?.toDouble();
      final sol = amountLamports != null ? (amountLamports / 1e9) : null;
      final desc =
      sol != null ? 'Amount: ${sol.toStringAsFixed(4)} SOL' : 'Large transfer';
      // Prefer timestamp from API (e.g., "blockTime") but fall back to now when absent
      final ts = _parseTimestamp(tx['blockTime']) ??
          _parseTimestamp(tx['timestamp']) ??
          _parseTimestamp(tx['time']) ??
          DateTime.now();
      return WhaleTx(
        shortHash: shortHash,
        chain: 'solana',
        desc: desc,
        ts: ts,
        amount: sol,
      );
    }).toList();
  }

  /// Attempt to parse a Solscan timestamp field.
  ///
  /// Fields may be integers (UNIX seconds) or strings. Returns `null` if the
  /// value cannot be parsed.
  static DateTime? _parseTimestamp(dynamic value) {
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value * 1000, isUtc: true);
    }
    if (value is String) {
      final asInt = int.tryParse(value);
      if (asInt != null) {
        return DateTime.fromMillisecondsSinceEpoch(asInt * 1000, isUtc: true);
      }
      return DateTime.tryParse(value);
    }
    return null;
  }
}