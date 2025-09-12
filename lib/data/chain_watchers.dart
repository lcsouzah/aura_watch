import 'dart:convert';
import 'package:http/http.dart' as http;
import 'models.dart';

abstract class ChainWatcher {
  String get id;           // 'solana' | 'ethereum' | 'bitcoin'
  Future<String> fetchPriceUsd();
  Future<List<WhaleTx>> fetchWhales({int limit});
}

/// Ethereum: uses CoinGecko for price; whale txs stub (can integrate Etherscan/Alchemy later)
class EthereumWatcher implements ChainWatcher {
  @override
  String get id => 'ethereum';

  @override
  Future<String> fetchPriceUsd() async {
    final uri = Uri.parse('https://api.coingecko.com/api/v3/simple/price?ids=ethereum&vs_currencies=usd');
    final res = await http.get(uri);
    if (res.statusCode != 200) throw Exception('ETH price error ${res.statusCode}');
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final usd = data['ethereum']?['usd'];
    if (usd == null) throw Exception('Invalid ETH price payload');
    return '\$${usd.toString()}';
  }

  @override
  Future<List<WhaleTx>> fetchWhales({int limit = 5}) async {
    // Placeholder — will swap in Etherscan/Alchemy/Arkham-like feed later
    return [];
  }
}

/// Bitcoin: uses CoinGecko for price; whales stub (can integrate mempool.space + threshold)
class BitcoinWatcher implements ChainWatcher {
  @override
  String get id => 'bitcoin';

  @override
  Future<String> fetchPriceUsd() async {
    final uri = Uri.parse('https://api.coingecko.com/api/v3/simple/price?ids=bitcoin&vs_currencies=usd');
    final res = await http.get(uri);
    if (res.statusCode != 200) throw Exception('BTC price error ${res.statusCode}');
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final usd = data['bitcoin']?['usd'];
    if (usd == null) throw Exception('Invalid BTC price payload');
    return '\$${usd.toString()}';
  }

  @override
  Future<List<WhaleTx>> fetchWhales({int limit = 5}) async {
    // Placeholder — later: poll mempool.space and flag txs over X BTC
    return [];
  }
}
