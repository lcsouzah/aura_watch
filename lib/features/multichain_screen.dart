import 'dart:async';

import 'package:flutter/material.dart';
import '../data/chain_watchers.dart';
import '../data/models.dart';
import '../widgets/token_bubble_map.dart';

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


  final Map<String, WalletViewMode> _viewModes = {
    'ethereum': WalletViewMode.list,
    'bitcoin': WalletViewMode.list,
  };

  // TODO: Replace demo holdings with live wallet balances once API wiring is ready.
  final Map<String, List<TokenBubbleData>> _demoHoldings = {
    'ethereum': const [
      TokenBubbleData(
        symbol: 'ETH',
        mint: 'eth-native',
        valueUsd: 15230,
        amount: 4.8,
      ),
      TokenBubbleData(
        symbol: 'USDC',
        mint: 'usdc-eth',
        valueUsd: 8200,
        amount: 8200,
      ),
      TokenBubbleData(
        symbol: 'ARB',
        mint: 'arb-token',
        valueUsd: 2900,
        amount: 1800,
      ),
    ],
    'bitcoin': const [
      TokenBubbleData(
        symbol: 'BTC',
        mint: 'btc-native',
        valueUsd: 38000,
        amount: 0.55,
      ),
      TokenBubbleData(
        symbol: 'wBTC',
        mint: 'wrapped-btc',
        valueUsd: 6100,
        amount: 0.1,
      ),
    ],
  };

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
          _buildTab('ethereum', _ethPrice, _ethWhales),
          _buildTab('bitcoin', _btcPrice, _btcWhales),
        ],
      ),
    );
  }

  WalletViewMode _viewModeForChain(String chainId) {
    return _viewModes[chainId] ?? WalletViewMode.list;
  }

  List<TokenBubbleData> _holdingsForChain(String chainId) {
    return _demoHoldings[chainId] ?? const [];
  }

  Widget _buildTab(String chainId, String price, List<WhaleTx> whales) {
    final mode = _viewModeForChain(chainId);
    final holdings = _holdingsForChain(chainId);

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
        const SizedBox(height: 24),
        const Text(
          'Wallet Tokens',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ChoiceChip(
              label: const Text('List'),
              selected: mode == WalletViewMode.list,
              onSelected: (_) {
                setState(() {
                  _viewModes[chainId] = WalletViewMode.list;
                });
              },
            ),
            const SizedBox(width: 8),
            ChoiceChip(
              label: const Text('Bubble map'),
              selected: mode == WalletViewMode.bubbles,
              onSelected: (_) {
                setState(() {
                  _viewModes[chainId] = WalletViewMode.bubbles;
                });
              },
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (mode == WalletViewMode.list)
          _buildHoldingsList(holdings)
        else
          SizedBox(
            height: 360,
            child: TokenBubbleMap(
              tokens: holdings,
              onBubbleTap: (token) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      '${token.symbol} • ${token.amount.toStringAsFixed(2)} @ '
                          '\$${token.valueUsd.toStringAsFixed(0)}',
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildHoldingsList(List<TokenBubbleData> holdings) {
    if (holdings.isEmpty) {
      return const Text('No tokens found for this wallet yet.');
    }

    return Column(
      children: [
        ...holdings.map(
              (t) => Card(
            child: ListTile(
              leading: const Icon(Icons.token),
              title: Text(t.symbol),
              subtitle: Text(t.mint),
              trailing: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('\$${t.valueUsd.toStringAsFixed(2)}'),
                  Text('${t.amount.toStringAsFixed(4)}'),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}