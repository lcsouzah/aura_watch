import 'dart:async';

import 'package:flutter/material.dart';
import '../data/chain_watchers.dart';
import '../data/models.dart';

class MultiChainScreen extends StatefulWidget {
  const MultiChainScreen({super.key});
  @override
  State<MultiChainScreen> createState() => _MultiChainScreenState();
}

class _MultiChainScreenState extends State<MultiChainScreen> with SingleTickerProviderStateMixin {
  static const _refreshInterval = Duration(seconds: 60);
  late final TabController _tab;
  final _eth = EthereumWatcher();
  final _btc = BitcoinWatcher();

  String _ethPrice = '…';
  String _btcPrice = '…';
  List<WhaleTx> _ethWhales = const [];
  List<WhaleTx> _btcWhales = const [];
  bool _loading = false;
  String? _error;
  Timer? _refreshTimer;

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await Future.wait([
        _eth.fetchPriceUsd(),
        _eth.fetchWhales(limit: 5),
        _btc.fetchPriceUsd(),
        _btc.fetchWhales(limit: 5),
      ]);
      setState(() {
        _ethPrice = r[0] as String;
        _ethWhales = r[1] as List<WhaleTx>;
        _btcPrice = r[2] as String;
        _btcWhales = r[3] as List<WhaleTx>;
      });
    } catch (e) {
      setState(() => _error = e.toString());
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_error!)));
      }
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _refresh();
    _refreshTimer = Timer.periodic(_refreshInterval, (_) {
      if (!_loading) {
        _refresh();
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Multi-Chain Watch'),
        bottom: TabBar(
          controller: _tab,
          tabs: const [
            Tab(text: 'Ethereum'),
            Tab(text: 'Bitcoin'),
          ],
          isScrollable: false,
        ),
        actions: [
          IconButton(onPressed: _loading ? null : _refresh, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: TabBarView(
        controller: _tab,
        children: _error != null
            ? [
          Center(
              child: Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red),
              )),
          Center(
              child: Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red),
              )),
        ]
            : [
          _buildTab(_ethPrice, _ethWhales),
          _buildTab(_btcPrice, _btcWhales),
        ],
      ),
    );
  }

  Widget _buildTab(String price, List<WhaleTx> whales) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Price',
            style: TextStyle(fontSize: 14, color: Colors.grey)),
        const SizedBox(height: 6),
        Text(price,
            style:
            const TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        const Text('Whale Activity',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        if (whales.isEmpty)
          const Text('No data yet.')
        else
          ...whales.map((w) => ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(w.shortHash),
            subtitle: Text('${w.tokenSymbol} ${w.movementType} • ${w.desc}'),
          )),
      ],
    );
  }
}