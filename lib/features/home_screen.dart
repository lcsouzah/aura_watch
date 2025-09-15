import 'dart:async';

import 'package:flutter/material.dart';
import '../data/solana_service.dart';
import '../data/models.dart';
import 'package:intl/intl.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _refreshInterval = Duration(seconds: 60) ;
  static final _num = NumberFormat.decimalPattern();
  String _solPrice = 'Loading…';
  List<TokenMarket> _trending = const [];
  List<WhaleTx> _whales = const [];
  bool _loading = false;
  String? _error;
  Timer? _refreshTimer;

  Future<void> _refreshAll() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        SolanaService.fetchSolPrice(),
        SolanaService.fetchTrendingTokens(limit: 5),
        SolanaService.fetchWhaleActivity(limit: 5),
      ]);
      setState(() {
        _solPrice = results[0] as String;
        _trending = results[1] as List<TokenMarket>;
        _whales = results[2] as List<WhaleTx>;
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _refreshAll();
    _refreshTimer = Timer.periodic(_refreshInterval, (_) {
      if (!_loading) {
        _refreshAll();
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Widget _sectionTitle(String text) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 8),
    child: Text(text, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Aura Watch'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _refreshAll,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          )
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_error != null) ...[
            Text('Error: $_error', style: const TextStyle(color: Colors.redAccent)),
            const SizedBox(height: 12),
          ],
          const Text('SOL Price', style: TextStyle(fontSize: 14, color: Colors.grey)),
          const SizedBox(height: 6),
          Text(_solPrice, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),

          _sectionTitle('Trending Tokens (Solana)'),
          if (_trending.isEmpty)
            const Text('No data yet.')
          else
            ..._trending.map((t) => ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(t.name),
              subtitle: Text('Vol 24h: ${_num.format(t.volume24h)}'),
              trailing: Text('\$${t.price.toStringAsFixed(4)}'),
            )),

          _sectionTitle('Whale Activity'),
          if (_whales.isEmpty)
            const Text('No data yet.')
          else
            ..._whales.map((w) => ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text('${w.chain.toUpperCase()} • ${w.shortHash}'),
              subtitle: Text(w.desc),
            )),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () => Navigator.pushNamed(context, '/multi'),
            child: const Text('Open Multi‑Chain Watch'),
          ),
        ],
      ),
    );
  }
}
