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
  String? _error;

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final p = await Future.wait([
        _eth.fetchPriceUsd(),
        _btc.fetchPriceUsd(),
      ]);
      setState(() {
        _ethPrice = p[0];
        _btcPrice = p[1];
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
          Center(
              child: Text('ETH: $_ethPrice',
                  style: const TextStyle(
                      fontSize: 24, fontWeight: FontWeight.bold))),
          Center(
              child: Text('BTC: $_btcPrice',
                  style: const TextStyle(
                      fontSize: 24, fontWeight: FontWeight.bold))),
        ],
      ),
    );
  }
}