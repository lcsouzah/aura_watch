import 'dart:convert';

import 'package:aura_watch/data/chain_watchers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('EthereumWatcher', () {
    test('fetchPriceUsd returns formatted price string', () async {
      final client = MockClient((request) async {
        expect(request.url.host, 'api.coingecko.com');
        expect(request.url.queryParameters['ids'], 'ethereum');
        return http.Response(jsonEncode({'ethereum': {'usd': 3456.78}}), 200);
      });

      final watcher = EthereumWatcher();
      final price = await watcher.fetchPriceUsd(client: client);

      expect(price, r'$3456.78');
    });

    test('fetchPriceUsd throws when the API fails', () async {
      final client = MockClient((request) async => http.Response('bad', 502));

      final watcher = EthereumWatcher();

      expect(
        watcher.fetchPriceUsd(client: client),
        throwsA(isA<Exception>()),
      );
    });

    test('fetchWhales returns large transfers parsed from block data', () async {
      final valueWei = BigInt.parse('600000000000000000000');
      final client = MockClient((request) async {
        final action = request.url.queryParameters['action'];
        if (action == 'eth_blockNumber') {
          return http.Response(jsonEncode({'result': '0xa'}), 200);
        }
        if (action == 'eth_getBlockByNumber') {
          expect(request.url.queryParameters['tag'], '0xa');
          return http.Response(
            jsonEncode({
              'result': {
                'timestamp': '0x64',
                'transactions': [
                  {
                    'hash': '0x1234567890abcdef1234',
                    'value': '0x${valueWei.toRadixString(16)}',
                  },
                  {
                    'hash': '0x0',
                    'value': '0x10',
                  }
                ],
              },
            }),
            200,
          );
        }
        fail('Unexpected request: ${request.url}');
      });

      final watcher = EthereumWatcher();
      final whales = await watcher.fetchWhales(limit: 1, client: client);

      expect(whales, hasLength(1));
      final whale = whales.single;
      expect(whale.chain, 'ethereum');
      expect(whale.shortHash, '0x1234567890…');
      expect(whale.desc, 'Amount: 600.00 ETH');
      expect(whale.amount, closeTo(600, 1e-6));
      expect(
        whale.ts,
        DateTime.fromMillisecondsSinceEpoch(100 * 1000, isUtc: true),
      );
    });

    test('fetchWhales propagates API errors', () async {
      final client = MockClient((request) async => http.Response('oops', 500));

      final watcher = EthereumWatcher();

      expect(
        watcher.fetchWhales(client: client),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('BitcoinWatcher', () {
    test('fetchPriceUsd returns formatted price string', () async {
      final client = MockClient((request) async {
        expect(request.url.queryParameters['ids'], 'bitcoin');
        return http.Response(jsonEncode({'bitcoin': {'usd': 27123}}), 200);
      });

      final watcher = BitcoinWatcher();
      final price = await watcher.fetchPriceUsd(client: client);

      expect(price, r'$27123');
    });

    test('fetchPriceUsd throws when the API fails', () async {
      final client = MockClient((request) async => http.Response('nope', 404));

      final watcher = BitcoinWatcher();

      expect(
        watcher.fetchPriceUsd(client: client),
        throwsA(isA<Exception>()),
      );
    });

    test('fetchWhales filters for transactions above the BTC threshold', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode([
            {
              'txid': 'abcd1234efgh5678',
              'value': 15000000000,
              'time': 1700000000,
            },
            {
              'txid': 'smalltx',
              'value': 500000000,
              'time': 1700000500,
            }
          ]),
          200,
        );
      });

      final watcher = BitcoinWatcher();
      final whales = await watcher.fetchWhales(limit: 2, client: client);

      expect(whales, hasLength(1));
      final whale = whales.single;
      expect(whale.chain, 'bitcoin');
      expect(whale.shortHash, 'abcd1234efgh…');
      expect(whale.desc, 'Amount: 150.00 BTC');
      expect(whale.amount, closeTo(150, 1e-6));
      expect(
        whale.ts,
        DateTime.fromMillisecondsSinceEpoch(1700000000 * 1000, isUtc: true),
      );
    });

    test('fetchWhales throws on non-200 responses', () async {
      final client = MockClient((request) async => http.Response('bad', 502));

      final watcher = BitcoinWatcher();

      expect(
        watcher.fetchWhales(client: client),
        throwsA(isA<Exception>()),
      );
    });
  });
}