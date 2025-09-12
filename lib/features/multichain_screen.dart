import 'package:flutter/material.dart';
import '../data/chain_watchers.dart';

class MultiChainScreen extends StatefulWidget {
  const MultiChainScreen({super.key});
  @override
  State<MultiChainScreen> createState() => _MultiChainScreenState();
}

class _MultiChainScreenState extends State<MultiChainScreen> with SingleTickerProviderStateMixin {
  late final TabController _tab;
  final _eth = EthereumWatcher();
  final _btc = BitcoinWatcher();

  String _ethPrice = '…';
  String _btcPrice = '…';
  bool _loading = false;

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final p = await Future.wait([_eth.fetchPriceUsd(), _btc.fetchPriceUsd()]);
      setState(() {
        _ethPrice = p[0];
        _btcPrice = p[1];
      });
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Multi-Chain Watch'),
        bottom: const TabBar(tabs: [
          Tab(text: 'Ethereum'),
          Tab(text: 'Bitcoin'),
        ], isScrollable: false),
        actions: [
          IconButton(onPressed: _loading ? null : _refresh, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          Center(child: Text('ETH: $_ethPrice', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold))),
          Center(child: Text('BTC: $_btcPrice', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold))),
        ],
      ),
    );
  }
}
