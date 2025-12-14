import 'dart:convert';
import 'package:http/http.dart' as http;
import 'models.dart';

abstract class ChainWatcher {
  String get id;           // 'solana' | 'ethereum' | 'bitcoin'
  Future<String> fetchPriceUsd({http.Client? client});
  Future<List<WhaleTx>> fetchWhales({int limit = 5, http.Client? client});
}

/// Ethereum: uses CoinGecko for price; whale txs stub (can integrate Etherscan/Alchemy later)
class EthereumWatcher implements ChainWatcher {
  @override
  String get id => 'ethereum';

  @override
  Future<String> fetchPriceUsd({http.Client? client}) async {
    final httpClient = client ?? http.Client();
    final shouldClose = client == null;
    try {
      final uri = Uri.parse('https://api.coingecko.com/api/v3/simple/price?ids=ethereum&vs_currencies=usd');
      final res = await httpClient.get(uri);
      if (res.statusCode != 200) throw Exception('ETH price error ${res.statusCode}');
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final usd = data['ethereum']?['usd'];
      if (usd == null) throw Exception('Invalid ETH price payload');
      return '\$${usd.toString()}';
    } finally {
      if (shouldClose) {
        httpClient.close();
      }
    }
  }

  @override
  Future<List<WhaleTx>> fetchWhales({int limit = 5, http.Client? client}) async {
    final httpClient = client ?? http.Client();
    final shouldClose = client == null;
    const thresholdEth = 500.0; // flag transfers >= 500 ETH
    final apiKey = const String.fromEnvironment('ETHERSCAN_API_KEY',
        defaultValue: 'YourApiKeyToken');
    final base =
        'https://api.etherscan.io/api?module=proxy&apikey=$apiKey';

    Never _throwEtherscanError(Map<String, dynamic> payload) {
      final status = payload['status']?.toString();
      final message = payload['message'];
      final result = payload['result'];
      final errorMessage = message ?? result ?? 'Unknown Etherscan error';

      if (status == '0' && errorMessage is String) {
        throw Exception('Etherscan error: $errorMessage');
      }

      if (result is Map<String, dynamic>) {
        final innerMessage = result['message'];
        if (innerMessage is String && innerMessage.isNotEmpty) {
          throw Exception('Etherscan error: $innerMessage');
        }
      }

      throw Exception('Etherscan error: $errorMessage');
    }

    String _extractHexString(Map<String, dynamic> payload) {
      final result = payload['result'];
      if (result is String && result.startsWith('0x')) {
        return result;
      }
      _throwEtherscanError(payload);
    }

    int _parseHexInt(String hex) => int.parse(hex.substring(2), radix: 16);

    // Fetch latest block number
    try {
      final latestRes =
      await httpClient.get(Uri.parse('$base&action=eth_blockNumber'));
      if (latestRes.statusCode != 200) {
        throw Exception('ETH block error ${latestRes.statusCode}');
      }
      final latestJson = jsonDecode(latestRes.body) as Map<String, dynamic>;
      final latestHex = _extractHexString(latestJson);
      var blockNum = _parseHexInt(latestHex);

      final whales = <WhaleTx>[];
      while (whales.length < limit && blockNum >= 0) {
        final tag = '0x${blockNum.toRadixString(16)}';
        final uri = Uri.parse(
            '$base&action=eth_getBlockByNumber&tag=$tag&boolean=true');
        final res = await httpClient.get(uri);
        if (res.statusCode != 200) {
          throw Exception('ETH block fetch error ${res.statusCode}');
        }
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        if (data.containsKey('error')) {
          final err = data['error'];
          throw Exception('Etherscan error: ${err?['message'] ?? err}');
        }

        final result = data['result'];
        if (result == null) {
          break;
        }
        if (result is! Map<String, dynamic>) {
          _throwEtherscanError(data);
        }
        final block = result;
        final tsHex = block['timestamp']?.toString() ?? '0x0';
        final ts = DateTime.fromMillisecondsSinceEpoch(
            _parseHexInt(tsHex) * 1000,
            isUtc: true);
        final txs = block['transactions'] as List<dynamic>? ?? [];
        for (final t in txs) {
          final valueHex = t['value']?.toString() ?? '0x0';
          BigInt valueWei;
          if (valueHex.startsWith('0x')) {
            valueWei = BigInt.tryParse(valueHex.substring(2), radix: 16) ??
                BigInt.zero;
          } else {
            valueWei = BigInt.zero;
          }
          final eth = valueWei.toDouble() / 1e18;
          if (eth >= thresholdEth) {
            final hash = t['hash']?.toString() ?? '';
            final shortHash =
            hash.length > 12 ? '${hash.substring(0, 12)}…' : hash;
            whales.add(WhaleTx(
              id: '$hash|ETH',
              shortHash: shortHash,
              chain: 'ethereum',
              tokenSymbol: 'ETH',
              movementType: 'transfer',
              desc: 'Amount: ${eth.toStringAsFixed(2)} ETH',
              ts: ts,
              amount: eth,
              address: null,
            ));
            if (whales.length >= limit) break;
          }
        }
        blockNum--;
      }
      return whales;
    } finally {
      if (shouldClose) {
        httpClient.close();
      }
    }
  }
}

/// Bitcoin: uses CoinGecko for price; whales stub (can integrate mempool.space + threshold)
class BitcoinWatcher implements ChainWatcher {
  @override
  String get id => 'bitcoin';

  @override
  Future<String> fetchPriceUsd({http.Client? client}) async {
    final httpClient = client ?? http.Client();
    final shouldClose = client == null;
    try {
      final uri = Uri.parse('https://api.coingecko.com/api/v3/simple/price?ids=bitcoin&vs_currencies=usd');
      final res = await httpClient.get(uri);
      if (res.statusCode != 200) throw Exception('BTC price error ${res.statusCode}');
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final usd = data['bitcoin']?['usd'];
      if (usd == null) throw Exception('Invalid BTC price payload');
      return '\$${usd.toString()}';
    } finally {
      if (shouldClose) {
        httpClient.close();
      }
    }
  }

  @override
  Future<List<WhaleTx>> fetchWhales({int limit = 5, http.Client? client}) async {
    final httpClient = client ?? http.Client();
    final shouldClose = client == null;
    const thresholdBtc = 100.0; // flag transfers >= 100 BTC
    final uri = Uri.parse('https://mempool.space/api/mempool/recent');
    try {
      final res = await httpClient.get(uri);
      if (res.statusCode != 200) {
        throw Exception('BTC whales error ${res.statusCode}');
      }
      final data = jsonDecode(res.body) as List<dynamic>;
      final whales = <WhaleTx>[];
      for (final tx in data) {
        final valueSats = (tx['value'] as num?)?.toDouble() ?? 0.0;
        final btc = valueSats / 1e8;
        if (btc >= thresholdBtc) {
          final hash = tx['txid']?.toString() ?? '';
          final shortHash = hash.length > 12 ? '${hash.substring(0, 12)}…' : hash;
          final timeVal = tx['time'] ?? tx['firstSeen'] ?? tx['seenTime'];
          DateTime ts;
          if (timeVal is int) {
            ts = DateTime.fromMillisecondsSinceEpoch(timeVal * 1000,
                isUtc: true);
          } else if (timeVal is String) {
            final asInt = int.tryParse(timeVal);
            ts = asInt != null
                ? DateTime.fromMillisecondsSinceEpoch(asInt * 1000,
                isUtc: true)
                : DateTime.now();
          } else {
            ts = DateTime.now();
          }
          whales.add(WhaleTx(
            id: '$hash|BTC',
            shortHash: shortHash,
            chain: 'bitcoin',
            tokenSymbol: 'BTC',
            movementType: 'transfer',
            desc: 'Amount: ${btc.toStringAsFixed(2)} BTC',
            ts: ts,
            amount: btc,
            address: null,
          ));
          if (whales.length >= limit) break;
        }
      }
      return whales;
    } finally {
      if (shouldClose) {
        httpClient.close();
      }
    }
  }
}