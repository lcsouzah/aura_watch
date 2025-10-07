import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'models.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

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

  /// Helius – whale feed using known exchange/whale addresses
  static Future<List<WhaleTx>> fetchWhaleActivity({
    int limit = 5,
    double minSol = 50,
    http.Client? client,
  }) async {
    final httpClient = client ?? http.Client();
    final shouldClose = client == null;
    try {
      final heliusKey = dotenv.env['HELIUS_API_KEY'] ?? '';
      if (heliusKey.isEmpty) throw Exception('Helius API key missing');
      final uri = Uri.parse('https://mainnet.helius-rpc.com/?api-key=$heliusKey');

      // Try a few known whale wallets until one yields transactions
      const whaleWallets = [
        '7bK3n6LiUPsTbnWeCjFJj3u4Z3dxFXVezU1DCGZ3d5dY', // Binance
        '8N9J6H4wY8AFJdwGJkTxgV1quQwcdKeKkzVxu1W9vGNo', // Coinbase
        'H3a41Xr1zThB2ETTtP7h66Yks3axS5pVq3F5V2X9A7kR', // Jump
        '2Ugqk3jmcgUMViFiD93SHf2FXS62m1ezfUcoBfK5d1U5', // Kraken
      ];

      final List<WhaleTx> whales = [];

      for (final address in whaleWallets) {
        final sigBody = jsonEncode({
          "jsonrpc": "2.0",
          "id": "aura_watch",
          "method": "getSignaturesForAddress",
          "params": [address, {"limit": limit}]
        });

        final sigRes = await httpClient.post(
          uri,
          headers: {"Content-Type": "application/json"},
          body: sigBody,
        );

        if (sigRes.statusCode != 200) continue;
        final sigData = jsonDecode(sigRes.body);
        final sigs = (sigData['result'] as List?) ?? [];
        if (sigs.isEmpty) continue;

        for (final s in sigs) {
          final sig = s['signature']?.toString();
          if (sig == null) continue;

          final txBody = jsonEncode({
            "jsonrpc": "2.0",
            "id": "aura_watch",
            "method": "getTransaction",
            "params": [sig, {"encoding": "jsonParsed"}],
          });

          final txRes = await httpClient.post(uri,
              headers: {"Content-Type": "application/json"}, body: txBody);
          if (txRes.statusCode != 200) continue;

          final txJson = jsonDecode(txRes.body);
          final tx = txJson['result'];
          if (tx == null) continue;

          final instructions =
              (tx['transaction']?['message']?['instructions'] as List?) ?? [];
          for (final ins in instructions) {
            final parsed = ins['parsed'];
            if (ins['program'] == 'system' &&
                parsed is Map &&
                parsed['type'] == 'transfer') {
              final info = parsed['info'] as Map?;
              final lamports = (info?['lamports'] as num?)?.toDouble() ?? 0;
              final sol = lamports / 1e9;
              if (sol >= minSol) {
                final src = info?['source']?.toString() ?? 'unknown';
                final dst = info?['destination']?.toString() ?? 'unknown';
                final blockTime = tx['blockTime'] ??
                    s['blockTime'] ??
                    DateTime.now().millisecondsSinceEpoch ~/ 1000;
                final ts = DateTime.fromMillisecondsSinceEpoch(
                    blockTime * 1000,
                    isUtc: true);
                final shortHash =
                sig.length > 12 ? '${sig.substring(0, 12)}…' : sig;

                whales.add(WhaleTx(
                  shortHash: shortHash,
                  chain: 'solana',
                  desc:
                  '$src → $dst: ${sol.toStringAsFixed(2)} SOL (${address.substring(0, 4)}...)',
                  ts: ts,
                  amount: sol,
                ));
              }
            }
          }
        }

        if (whales.isNotEmpty) break; // stop once we got some data
      }

      whales.sort((a, b) => b.ts.compareTo(a.ts));
      return whales;
    } finally {
      if (shouldClose) httpClient.close();
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