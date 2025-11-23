import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'models.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

enum SolanaRpcProvider {
  helius,
  generic,
}

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
  static Future<List<TokenMarket>> fetchTrendingTokens({
    int limit = 5,
    http.Client? client,
  }) async {
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
      final filtered = list.where((e) {
        final id = e['id']?.toString();
        final symbol = e['symbol']?.toString();
        // Stablecoins are filtered here to keep the Trending section volatile.
        return !isStablecoinId(id) && !isStablecoinSymbol(symbol);
      }).map((e) {
        final name = e['name']?.toString() ?? 'Unknown';
        final price = (e['current_price'] as num?)?.toDouble() ?? 0.0;
        final vol = (e['total_volume'] as num?)?.toDouble() ?? 0.0;
        final id = e['id']?.toString() ?? name.toLowerCase();
        final rawSymbol = e['symbol']?.toString();
        final computedSymbol = (rawSymbol != null && rawSymbol.isNotEmpty)
            ? rawSymbol
            : (name.isNotEmpty
            ? name.substring(0, name.length >= 3 ? 3 : name.length)
            : 'TOK');
        return TokenMarket(
          id: id,
          symbol: computedSymbol.toUpperCase(),
          name: name,
          price: price,
          volume24h: vol,
        );
      }).toList();
      return filtered;
    } finally {
      if (shouldClose) {
        httpClient.close();
      }
    }
  }

  /// CoinGecko – Dedicated stablecoin metrics for the Stablecoins section.
  static Future<List<StablecoinMarket>> fetchStablecoinMarkets({
    List<StablecoinInfo> stablecoins = supportedStablecoins,
    http.Client? client,
  }) async {
    if (stablecoins.isEmpty) {
      return const [];
    }
    final httpClient = client ?? http.Client();
    final shouldClose = client == null;
    try {
      final ids = stablecoins.map((e) => e.coingeckoId).join(',');
      final uri = Uri.parse(
        'https://api.coingecko.com/api/v3/coins/markets'
            '?vs_currency=usd&ids=$ids&order=market_cap_desc&per_page=${stablecoins.length}',
      );
      final res = await httpClient.get(uri);
      if (res.statusCode != 200) {
        throw Exception('Stablecoin fetch failed ${res.statusCode}');
      }
      final list = jsonDecode(res.body) as List<dynamic>;
      final markets = <StablecoinMarket>[];
      for (final info in stablecoins) {
        final entry = list.cast<Map<String, dynamic>?>().firstWhere(
              (item) => item?['id']?.toString() == info.coingeckoId,
          orElse: () => null,
        );
        final price = (entry?['current_price'] as num?)?.toDouble() ?? 1.0;
        final volume = (entry?['total_volume'] as num?)?.toDouble() ?? 0.0;
        markets.add(StablecoinMarket(info: info, price: price, volume24h: volume));
      }
      return markets;
    } finally {
      if (shouldClose) httpClient.close();
    }
  }

  /// Helius – whale feed using known exchange/whale addresses.
  ///
  /// [minSol] is the native SOL threshold (default 50 SOL) and [timeWindow]
  /// defines how far back we scan (defaults to the last hour). Both values
  /// are documented here so the whale cadence is easy to tune.
  static Future<List<WhaleTx>> fetchWhaleActivity({
    int limit = 10,
    double minSol = 50,
    Duration timeWindow = const Duration(hours: 1),
    http.Client? client,

    /// New optional config to select RPC provider and credentials.
    SolanaRpcProvider provider = SolanaRpcProvider.helius,
    String? rpcUrl,
    String? apiKey,
  }) async {
    final httpClient = client ?? http.Client();
    final shouldClose = client == null;
    try {
      // Decide which base URL to use depending on the provider and arguments.
      late final String rpcEndpoint;

      switch (provider) {
        case SolanaRpcProvider.helius:
        // Use the explicit apiKey if provided, otherwise fall back to .env
          final effectiveKey = (apiKey ?? dotenv.env['HELIUS_API_KEY'] ?? '').trim();
          if (effectiveKey.isEmpty) {
            throw Exception('Helius API key missing');
          }
          rpcEndpoint = 'https://mainnet.helius-rpc.com/?api-key=$effectiveKey';
          break;

        case SolanaRpcProvider.generic:
        // For a generic Solana RPC node, we do not assume any key format.
        // Use rpcUrl if provided, otherwise default to the public mainnet endpoint.
          final effectiveUrl =
          (rpcUrl ?? 'https://api.mainnet-beta.solana.com').trim();
          if (effectiveUrl.isEmpty) {
            throw Exception('Generic RPC URL is empty');
          }
          rpcEndpoint = effectiveUrl;
          break;
      }

      final uri = Uri.parse(rpcEndpoint);

      // Try a few known whale wallets until one yields transactions
      const whaleWallets = [
        '7bK3n6LiUPsTbnWeCjFJj3u4Z3dxFXVezU1DCGZ3d5dY', // Binance
        '8N9J6H4wY8AFJdwGJkTxgV1quQwcdKeKkzVxu1W9vGNo', // Coinbase
        'H3a41Xr1zThB2ETTtP7h66Yks3axS5pVq3F5V2X9A7kR', // Jump
        '2Ugqk3jmcgUMViFiD93SHf2FXS62m1ezfUcoBfK5d1U5', // Kraken
      ];

      final List<WhaleTx> whales = [];
      final now = DateTime.now().toUtc();

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
          final blockTime = tx['blockTime'] ??
              s['blockTime'] ??
              DateTime.now().millisecondsSinceEpoch ~/ 1000;
          final ts = DateTime.fromMillisecondsSinceEpoch(
            blockTime * 1000,
            isUtc: true,
          );

          if (now.difference(ts) > timeWindow) {
            continue; // Skip stale events outside the monitoring window.
          }

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
                final shortHash =
                sig.length > 12 ? '${sig.substring(0, 12)}…' : sig;

                whales.add(WhaleTx(
                  id: '$sig|SOL|$src|$dst',
                  shortHash: shortHash,
                  chain: 'solana',
                  tokenSymbol: 'SOL',
                  movementType: 'transfer',
                  desc:
                  '$src → $dst: ${sol.toStringAsFixed(2)} SOL (${address.substring(0, 4)}...)',
                  ts: ts,
                  amount: sol,
                ));
              }
            }
          }

          // Track stablecoin whale movements by comparing token balances.
          final stableEvents = _extractStableWhales(
            tx,
            signature: sig,
            shortHash: sig.length > 12 ? '${sig.substring(0, 12)}…' : sig,
            timestamp: ts,
          );
          whales.addAll(stableEvents);
        }

        if (whales.isNotEmpty) break; // stop once we got some data
      }

      whales.sort((a, b) => b.ts.compareTo(a.ts));
      if (whales.length > limit) {
        return whales.take(limit).toList();
      }
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

  static List<WhaleTx> _extractStableWhales(
      Map<String, dynamic> tx, {
        required String signature,
        required String shortHash,
        required DateTime timestamp,
      }) {
    final meta = tx['meta'] as Map<String, dynamic>?;
    if (meta == null) return const [];
    final preBalances =
        (meta['preTokenBalances'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ??
            const <Map<String, dynamic>>[];
    final postBalances =
        (meta['postTokenBalances'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ??
            const <Map<String, dynamic>>[];

    final Map<int, _TokenBalanceSnapshot> pre = {};
    for (final item in preBalances) {
      final idx = item['accountIndex'];
      if (idx is! int) continue;
      final mint = item['mint']?.toString();
      final info = stablecoinByMint(mint);
      if (info == null) continue;
      final owner = item['owner']?.toString() ?? 'unknown';
      final amount = _parseUiAmount(item['uiTokenAmount']) ?? 0;
      pre[idx] = _TokenBalanceSnapshot(info: info, owner: owner, amount: amount);
    }

    final Map<int, _TokenBalanceSnapshot> post = {};
    for (final item in postBalances) {
      final idx = item['accountIndex'];
      if (idx is! int) continue;
      final mint = item['mint']?.toString();
      final info = stablecoinByMint(mint);
      if (info == null) continue;
      final owner = item['owner']?.toString() ?? 'unknown';
      final amount = _parseUiAmount(item['uiTokenAmount']) ?? 0;
      post[idx] = _TokenBalanceSnapshot(info: info, owner: owner, amount: amount);
    }

    final whaleEvents = <WhaleTx>[];
    final accountIndexes = {...pre.keys, ...post.keys};
    for (final idx in accountIndexes) {
      final before = pre[idx];
      final after = post[idx];
      final info = after?.info ?? before?.info;
      if (info == null) continue;
      final owner = after?.owner ?? before?.owner ?? 'unknown';
      final amountChange = (after?.amount ?? 0) - (before?.amount ?? 0);
      final absChange = amountChange.abs();
      final usdValue = absChange * 1.0; // Stablecoins hover ≈ $1
      if (usdValue < info.whaleThresholdUsd) continue;
      final movementType = amountChange > 0 ? 'buy' : 'sell';
      whaleEvents.add(WhaleTx(
        id: '$signature|${info.symbol}|$idx|$movementType',
        shortHash: shortHash,
        chain: 'solana',
        tokenSymbol: info.symbol,
        movementType: movementType,
        desc:
        '$owner ${movementType == 'buy' ? 'received' : 'sent'} ${absChange.toStringAsFixed(0)} ${info.symbol}',
        ts: timestamp,
        amount: absChange,
        usdValue: usdValue,
      ));
    }
    return whaleEvents;
  }

  static double? _parseUiAmount(dynamic payload) {
    if (payload is Map<String, dynamic>) {
      final raw = payload['uiAmount'] ?? payload['uiAmountString'];
      if (raw is num) return raw.toDouble();
      if (raw is String) return double.tryParse(raw);
    } else if (payload is num) {
      return payload.toDouble();
    } else if (payload is String) {
      return double.tryParse(payload);
    }
    return null;
  }
}

class _TokenBalanceSnapshot {
  final StablecoinInfo info;
  final String owner;
  final double amount;

  const _TokenBalanceSnapshot({
    required this.info,
    required this.owner,
    required this.amount,
  });
}