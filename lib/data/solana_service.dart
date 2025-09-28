import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'models.dart';

class SolanaService {

  /// CoinGecko – SOL price (USD)
  static Future<String> fetchSolPrice({http.Client? client}) async {
    final httpClient = client ?? http.Client();
    final shouldClose = client == null;
    try {
      final uri = Uri.parse('https://api.coingecko.com/api/v3/simple/price?ids=solana&vs_currencies=usd');
      final res = await httpClient.get(uri);
      if (res.statusCode != 200) throw Exception('SOL price error ${res.statusCode}');
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final usd = (data['solana']?['usd'] as num?)?.toDouble();
      if (usd == null) throw Exception('Invalid SOL price payload');
      final formatted = NumberFormat('###,##0.00').format(usd);
      return '\$$formatted';
    } finally {
      if (shouldClose) {
        httpClient.close();
      }
    }
  }

  /// CoinGecko – Trending tokens (Solana category)
  static Future<List<TokenMarket>> fetchTrendingTokens({int limit = 5, http.Client? client}) async {
    final httpClient = client ?? http.Client();
    final shouldClose = client == null;
    try {
      final uri = Uri.parse(
        'https://api.coingecko.com/api/v3/coins/markets'
            '?vs_currency=usd&category=solana-ecosystem&order=volume_desc&per_page=$limit',
      );
      final res = await httpClient.get(uri);
      if (res.statusCode != 200) throw Exception('Trending error ${res.statusCode}');
      final list = jsonDecode(res.body) as List<dynamic>;
      return list.map((e) {
        final name = e['name']?.toString() ?? 'Unknown';
        final price = (e['current_price'] as num?)?.toDouble() ?? 0.0;
        final vol = (e['total_volume'] as num?)?.toDouble() ?? 0.0;
        return TokenMarket(name: name, price: price, volume24h: vol);
      }).toList();
    } finally {
      if (shouldClose) {
        httpClient.close();
      }
    }
  }

  /// Solscan “whale” txs (best-effort; API may change/rate-limit)
  static Future<List<WhaleTx>> fetchWhaleActivity({int limit = 5, http.Client? client}) async {
    final httpClient = client ?? http.Client();
    final shouldClose = client == null;
    try {
      final uri = Uri.parse('https://public-api.solscan.io/transaction/whale?limit=$limit');
      final res = await httpClient.get(uri, headers: {'accept': 'application/json'});
      if (res.statusCode != 200) throw Exception('Whales error ${res.statusCode}');
      final decoded = jsonDecode(res.body);
      final arr = _extractWhaleTransactions(decoded);
      return arr.map((tx) {
        final hash = tx['txHash']?.toString() ?? tx['signature']?.toString() ?? '';
        final shortHash = hash.length > 12 ? '${hash.substring(0, 12)}…' : hash;
        // When provided: amount = lamports; format to SOL
        final amountLamports = _parseLamports(tx);
        final sol = amountLamports != null ? (amountLamports / 1e9) : null;
        final desc = sol != null
            ? 'Amount: ${sol.toStringAsFixed(4)} SOL'
            : (tx['description']?.toString() ?? 'Large transfer');
        // Prefer timestamp from API (e.g., "blockTime") but fall back to now when absent
        final ts = _parseTimestamp(tx['blockTime']) ??
            _parseTimestamp(tx['timestamp']) ??
            _parseTimestamp(tx['time']) ??
            _parseTimestamp(tx['block_time']) ??
            DateTime.now();
        return WhaleTx(
          shortHash: shortHash,
          chain: 'solana',
          desc: desc,
          ts: ts,
          amount: sol,
        );
      }).toList();
    } finally {
      if (shouldClose) {
        httpClient.close();
      }
    }
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
  static List<Map<String, dynamic>> _extractWhaleTransactions(dynamic decoded) {
    Iterable<dynamic> raw = const [];
    if (decoded is List) {
      raw = decoded;
    } else if (decoded is Map<String, dynamic>) {
      final dataField = decoded['data'];
      if (dataField is List) {
        raw = dataField;
      } else if (dataField is Map<String, dynamic>) {
        final nested = dataField['list'] ?? dataField['data'] ?? dataField['items'];
        if (nested is List) {
          raw = nested;
        }
      }
      if (raw.isEmpty) {
        for (final key in const ['transactions', 'result']) {
          final value = decoded[key];
          if (value is List) {
            raw = value;
            break;
          }
        }
      }
    }
    return raw.whereType<Map<String, dynamic>>().toList();
  }

  static double? _parseLamports(Map<String, dynamic> tx) {
    for (final key in const ['amount', 'lamports', 'amountLamports', 'amount_lamports']) {
      final value = _asDouble(tx[key]);
      if (value != null) {
        return value;
      }
    }
    final solAmount = _asDouble(tx['solAmount'] ?? tx['sol_amount'] ?? tx['amountSol']);
    if (solAmount != null) {
      return solAmount * 1e9;
    }
    return null;
  }

  static double? _asDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      return double.tryParse(value);
    }
    return null;
  }
}