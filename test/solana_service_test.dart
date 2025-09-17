import 'dart:convert';

import 'package:aura_watch/data/solana_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('SolanaService', () {
    test('fetchSolPrice returns formatted USD string on success', () async {
      final client = MockClient((request) async {
        expect(request.url.host, 'api.coingecko.com');
        expect(request.url.queryParameters['ids'], 'solana');
        return http.Response(jsonEncode({'solana': {'usd': 1234.5678}}), 200);
      });

      final result = await SolanaService.fetchSolPrice(client: client);

      expect(result, '\$1,234.57');
    });

    test('fetchSolPrice throws on non-200 responses', () async {
      final client = MockClient((request) async => http.Response('error', 500));

      expect(
        SolanaService.fetchSolPrice(client: client),
        throwsA(isA<Exception>()),
      );
    });

    test('fetchTrendingTokens maps market payload into TokenMarket values', () async {
      final response = [
        {
          'name': 'Bonk',
          'current_price': 0.00000123,
          'total_volume': 987654321.0,
        },
        {
          'name': null,
          'current_price': null,
          'total_volume': null,
        }
      ];
      final client = MockClient((request) async {
        expect(request.url.queryParameters['per_page'], '2');
        return http.Response(jsonEncode(response), 200);
      });

      final tokens = await SolanaService.fetchTrendingTokens(limit: 2, client: client);

      expect(tokens, hasLength(2));
      expect(tokens.first.name, 'Bonk');
      expect(tokens.first.price, closeTo(0.00000123, 1e-12));
      expect(tokens.first.volume24h, 987654321.0);
      expect(tokens.last.name, 'Unknown');
      expect(tokens.last.price, 0.0);
      expect(tokens.last.volume24h, 0.0);
    });

    test('fetchTrendingTokens throws on non-200 responses', () async {
      final client = MockClient((request) async => http.Response('oops', 404));

      expect(
        SolanaService.fetchTrendingTokens(client: client),
        throwsA(isA<Exception>()),
      );
    });

    test('fetchWhaleActivity parses Solscan payload into WhaleTx entries', () async {
      const timestamp = 1630000000;
      final payload = {
        'data': [
          {
            'txHash': 'abcdefghijklmnopqrstuvwxyz',
            'amount': 2500000000,
            'blockTime': timestamp,
          },
          {
            'txHash': 'shortHash',
            'timestamp': timestamp.toString(),
          }
        ],
      };
      final client = MockClient((request) async {
        expect(request.url.queryParameters['limit'], '2');
        expect(request.headers['accept'], 'application/json');
        return http.Response(jsonEncode(payload), 200);
      });

      final whales = await SolanaService.fetchWhaleActivity(limit: 2, client: client);

      expect(whales, hasLength(2));
      final first = whales.first;
      expect(first.shortHash, 'abcdefghijkl…');
      expect(first.chain, 'solana');
      expect(first.amount, closeTo(2.5, 1e-9));
      expect(first.desc, 'Amount: 2.5000 SOL');
      expect(
        first.ts,
        DateTime.fromMillisecondsSinceEpoch(timestamp * 1000, isUtc: true),
      );

      final second = whales.last;
      expect(second.shortHash, 'shortHash');
      expect(second.desc, 'Large transfer');
      expect(
        second.ts,
        DateTime.fromMillisecondsSinceEpoch(timestamp * 1000, isUtc: true),
      );
    });

    test('fetchWhaleActivity throws on non-200 responses', () async {
      final client = MockClient((request) async => http.Response('bad', 503));

      expect(
        SolanaService.fetchWhaleActivity(client: client),
        throwsA(isA<Exception>()),
      );
    });
  });
}