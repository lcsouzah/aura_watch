import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/models.dart';
import '../data/notification_service.dart';
import '../data/address_watchlist_repository.dart';
import '../data/solana_service.dart';
import '../data/token_price_service.dart';
import '../data/watchlist_repository.dart';
import 'wallet_bubble_screen.dart';
import '../screens/solana_api_settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _refreshInterval = Duration(seconds: 60); // price + whale poll cadence
  static const _whaleWindow = Duration(hours: 1); // rolling whale window
  static final _num = NumberFormat.decimalPattern();
  String _solPrice = 'Loading…';
  List<TokenMarket> _trending = const [];
  List<WhaleTx> _whales = const [];
  List<StablecoinMarket> _stablecoinMarkets = const [];
  bool _loading = false;
  String? _error;
  String? _watchlistError;
  bool _watchlistLoading = true;
  Timer? _refreshTimer;
  WatchlistRepository? _watchlistRepository;
  List<WatchedToken> _watchlist = const [];
  Map<String, double> _latestWatchPrices = const {};
  final Map<String, bool> _lastThresholdState = {};
  final Set<String> _processedWhaleEventIds = {};
  AddressWatchlistRepository? _addressWatchRepo;
  List<WatchedAddress> _addressWatchlist = const [];
  bool _addressWatchLoading = true;
  String? _addressWatchError;

  Future<void> _refreshAll() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
      _watchlistError = null;
    });
    try {
      final results = await Future.wait([
        SolanaService.fetchSolPrice(),
        SolanaService.fetchTrendingTokens(limit: 5),
        SolanaService.fetchWhaleActivity(limit: 12, timeWindow: _whaleWindow),
        SolanaService.fetchStablecoinMarkets(),
      ]);
      final watchlistPrices = await _fetchWatchlistPrices();
      if (!mounted) return;
      setState(() {
        _solPrice = results[0] as String;
        _trending = results[1] as List<TokenMarket>;
        _whales = results[2] as List<WhaleTx>;
        _stablecoinMarkets = results[3] as List<StablecoinMarket>;
        _latestWatchPrices = watchlistPrices;
      });
      _handleWhaleNotifications(_whales);
      _evaluateWatchlistAlerts(watchlistPrices);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  void _handleWhaleNotifications(List<WhaleTx> events) {
    if (!mounted || events.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    for (final event in events) {
      if (_processedWhaleEventIds.contains(event.id)) {
        continue;
      }
      if (!_isWhaleEventRelevant(event)) {
        continue;
      }
      _processedWhaleEventIds.add(event.id);
      final amountText = event.amount != null
          ? '${event.amount!.toStringAsFixed(2)} ${event.tokenSymbol}'
          : event.tokenSymbol;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Whale ${event.movementType} • $amountText on ${event.chain.toUpperCase()}',
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
      unawaited(NotificationService.showWhaleAlert(event));
    }
  }

  bool _isWhaleEventRelevant(WhaleTx event) {
    if (isStablecoinSymbol(event.tokenSymbol)) {
      return true;
    }
    final needle = event.tokenSymbol.toLowerCase();
    for (final token in _watchlist) {
      if (token.id.toLowerCase().contains(needle) ||
          token.label.toLowerCase().contains(needle)) {
        return true;
      }
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    _initializeWatchlist();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _initializeWatchlist() async {
    final repo = await WatchlistRepository.load();
    if (!mounted) return;
    final tokens = repo.loadTokens();
    setState(() {
      _watchlistRepository = repo;
      _watchlist = tokens;
      _watchlistLoading = false;
    });
    try {
      final addrRepo = await AddressWatchlistRepository.load();
      final addrList = addrRepo.loadAddresses();
      if (mounted) {
        setState(() {
          _addressWatchRepo = addrRepo;
          _addressWatchlist = addrList;
          _addressWatchLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _addressWatchError = e.toString();
          _addressWatchLoading = false;
        });
      }
    }
    await _refreshAll();
    if (!mounted) return;
    _refreshTimer = Timer.periodic(_refreshInterval, (_) {
      if (!_loading) {
        _refreshAll();
      }
    });
  }

  String _normalizedId(String id) => id.trim().toLowerCase();

  Future<Map<String, double>> _fetchWatchlistPrices() async {
    if (_watchlist.isEmpty) {
      return const {};
    }
    try {
      final prices = await TokenPriceService.fetchUsdPrices(
        _watchlist.map((token) => token.id).toList(),
      );
      final normalized = <String, double>{};
      for (final entry in prices.entries) {
        normalized[_normalizedId(entry.key)] = entry.value;
      }
      return normalized;
    } catch (e) {
      if (mounted) {
        setState(() => _watchlistError = e.toString());
      }
      return const {};
    }
  }

  void _evaluateWatchlistAlerts(Map<String, double> priceMap) {
    if (priceMap.isEmpty) return;
    for (final token in _watchlist) {
      final key = _normalizedId(token.id);
      final price = priceMap[key];
      if (price == null) {
        _lastThresholdState[key] = false;
        continue;
      }
      final isTriggered = token.alertAbove
          ? price >= token.thresholdUsd
          : price <= token.thresholdUsd;
      final wasTriggered = _lastThresholdState[key] ?? false;
      if (isTriggered && !wasTriggered) {
        unawaited(NotificationService.showThresholdAlert(token, price));
      }
      _lastThresholdState[key] = isTriggered;
    }
  }

  Future<void> _refreshWatchlistSection() async {
    final prices = await _fetchWatchlistPrices();
    if (!mounted) return;
    setState(() {
      _latestWatchPrices = prices;
      if (prices.isNotEmpty || _watchlist.isEmpty) {
        _watchlistError = null;
      }
    });
    _evaluateWatchlistAlerts(prices);
  }

  Future<void> _updateWatchlist(List<WatchedToken> tokens) async {
    final validKeys = tokens.map((t) => _normalizedId(t.id)).toSet();
    _lastThresholdState.removeWhere((key, _) => !validKeys.contains(key));
    if (!mounted) return;
    setState(() {
      _watchlist = tokens;
    });
    final repo = _watchlistRepository;
    if (repo != null) {
      await repo.saveTokens(tokens);
    }
    await _refreshWatchlistSection();
  }

  Future<void> _updateAddressWatchlist(List<WatchedAddress> list) async {
    final repo = _addressWatchRepo;
    if (repo == null) return;
    if (!mounted) return;
    setState(() {
      _addressWatchlist = list;
    });
    await repo.saveAddresses(list);
  }

  Future<void> _removeToken(WatchedToken token) async {
    final updated = _watchlist.where((t) => t != token).toList();
    await _updateWatchlist(updated);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${token.label} removed from watchlist')),
    );
  }

  Future<void> _addToken() async {
    final token = await _showTokenDialog();
    if (token == null) return;
    final exists = _watchlist
        .any((t) => _normalizedId(t.id) == _normalizedId(token.id));
    if (exists) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Token already in watchlist')),
      );
      return;
    }
    await _updateWatchlist([..._watchlist, token]);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${token.label} added to watchlist')),
    );
  }
  Future<void> _searchAndAddToken() async {
    final queryController = TextEditingController();
    List<TokenSearchResult> results = const [];
    TokenSearchResult? selected;

    final result = await showDialog<TokenSearchResult>(
      context: context,
      builder: (ctx) {
        bool loading = false;
        String? error;

        Future<void> doSearch(void Function(void Function()) setState) async {
          final q = queryController.text.trim();
          if (q.isEmpty) return;
          setState(() {
            loading = true;
            error = null;
          });
          try {
            final resp = await TokenPriceService.searchTokens(q);
            setState(() {
              results = resp;
            });
          } catch (e) {
            setState(() {
              error = e.toString();
              results = const [];
            });
          } finally {
            setState(() {
              loading = false;
            });
          }
        }

        return StatefulBuilder(
          builder: (ctx, setState) {
            return AlertDialog(
              title: const Text('Search token'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: queryController,
                    decoration: const InputDecoration(
                      labelText: 'Name or symbol',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => doSearch(setState),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: loading ? null : () => doSearch(setState),
                      child: loading
                          ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                          : const Text('Search'),
                    ),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      error!,
                      style: const TextStyle(color: Colors.redAccent),
                    ),
                  ],
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 200,
                    child: results.isEmpty
                        ? const Center(child: Text('No results'))
                        : ListView.separated(
                      itemCount: results.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, index) {
                        final r = results[index];
                        return ListTile(
                          title: Text('${r.name} (${r.symbol.toUpperCase()})'),
                          subtitle: Text(r.id),
                          onTap: () {
                            selected = r;
                            Navigator.of(ctx).pop(selected);
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == null) return;
    selected = result;

    final normalized = _normalizedId(selected!.id);
    final exists = _watchlist.any((t) => _normalizedId(t.id) == normalized);
    if (exists) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Token already in watchlist')),
      );
      return;
    }

    final newToken = WatchedToken(
      id: selected!.id,
      label: '${selected!.name} (${selected!.symbol.toUpperCase()})',
      thresholdUsd: 1.0,
      alertAbove: true,
    );
    await _updateWatchlist([..._watchlist, newToken]);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${newToken.label} added to watchlist')),
    );
  }


  Future<void> _editToken(WatchedToken token) async {
    final updated = await _showTokenDialog(existing: token);
    if (updated == null) return;
    final normalized = _normalizedId(updated.id);
    final duplicates = _watchlist.where((t) =>
    t != token && _normalizedId(t.id) == normalized);
    if (duplicates.isNotEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Another token with this ID exists')),
      );
      return;
    }
    final idx = _watchlist.indexOf(token);
    if (idx == -1) return;
    final newList = [..._watchlist];
    newList[idx] = updated;
    await _updateWatchlist(newList);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${updated.label} updated')),
    );
  }

  Future<WatchedToken?> _showTokenDialog({WatchedToken? existing}) {
    final idController = TextEditingController(text: existing?.id ?? '');
    final labelController =
    TextEditingController(text: existing?.label ?? existing?.id ?? '');
    final thresholdController = TextEditingController(
      text: existing != null ? existing.thresholdUsd.toStringAsFixed(4) : '',
    );
    bool alertAbove = existing?.alertAbove ?? true;
    return showDialog<WatchedToken>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(existing == null ? 'Add token' : 'Edit token'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: idController,
                      decoration: const InputDecoration(
                        labelText: 'CoinGecko token ID',
                        hintText: 'e.g. solana',
                      ),
                      enabled: existing == null,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: labelController,
                      decoration: const InputDecoration(
                        labelText: 'Display label',
                        hintText: 'Friendly name',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: thresholdController,
                      decoration: const InputDecoration(
                        labelText: 'Alert threshold (USD)',
                        hintText: 'e.g. 150.00',
                      ),
                      keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Text('Trigger when price is'),
                        const SizedBox(width: 12),
                        DropdownButton<bool>(
                          value: alertAbove,
                          onChanged: (value) {
                            if (value == null) return;
                            setState(() => alertAbove = value);
                          },
                          items: const [
                            DropdownMenuItem(
                              value: true,
                              child: Text('≥ threshold'),
                            ),
                            DropdownMenuItem(
                              value: false,
                              child: Text('≤ threshold'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final id = idController.text.trim();
                    if (id.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Token ID is required')),
                      );
                      return;
                    }
                    final label = labelController.text.trim().isEmpty
                        ? id
                        : labelController.text.trim();
                    final thresholdValue =
                    double.tryParse(thresholdController.text.trim());
                    if (thresholdValue == null || thresholdValue <= 0) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Enter a valid threshold')),
                      );
                      return;
                    }
                    Navigator.pop(
                      context,
                      WatchedToken(
                        id: id,
                        label: label,
                        thresholdUsd: thresholdValue,
                        alertAbove: alertAbove,
                      ),
                    );
                  },
                  child: Text(existing == null ? 'Add' : 'Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _addAddress() async {
    final addr = await _showAddressDialog();
    if (addr == null) return;

    final normalized = addr.address.trim();
    final exists = _addressWatchlist
        .any((a) => a.chain == addr.chain && a.address.trim() == normalized);
    if (exists) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Address already in watchlist')),
      );
      return;
    }

    await _updateAddressWatchlist([..._addressWatchlist, addr]);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${addr.label} added to address watchlist')),
    );
  }

  Future<void> _removeAddress(WatchedAddress addr) async {
    final updated = _addressWatchlist.where((a) => a != addr).toList();
    await _updateAddressWatchlist(updated);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${addr.label} removed from address watchlist')),
    );
  }

  Future<WatchedAddress?> _showAddressDialog({WatchedAddress? existing}) {
    final addressController =
    TextEditingController(text: existing?.address ?? '');
    final labelController =
    TextEditingController(text: existing?.label ?? existing?.address ?? '');
    String chain = existing?.chain ?? 'solana';

    return showDialog<WatchedAddress>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(existing == null ? 'Add address' : 'Edit address'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: addressController,
                decoration: const InputDecoration(
                  labelText: 'Address',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: labelController,
                decoration: const InputDecoration(
                  labelText: 'Label',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: chain,
                decoration: const InputDecoration(
                  labelText: 'Chain',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'solana', child: Text('Solana')),
                  DropdownMenuItem(value: 'ethereum', child: Text('Ethereum')),
                  DropdownMenuItem(value: 'bitcoin', child: Text('Bitcoin')),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  chain = value;
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final addr = addressController.text.trim();
                if (addr.isEmpty) return;
                final label =
                labelController.text.trim().isEmpty ? addr : labelController.text.trim();
                Navigator.of(ctx).pop(
                  WatchedAddress(
                    address: addr,
                    label: label,
                    chain: chain,
                  ),
                );
              },
              child: Text(existing == null ? 'Add' : 'Save'),
            ),
          ],
        );
      },
    );
  }


  Widget _buildWatchTile(WatchedToken token) {
    final price = _latestWatchPrices[_normalizedId(token.id)];
    final priceText =
    price != null && price > 0 ? '\$${price.toStringAsFixed(4)}' : '—';
    final direction = token.alertAbove ? '≥' : '≤';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const Icon(Icons.notifications_active_outlined),
        title: Text(token.label),
        subtitle: Text(
          'Alert when price $direction ${token.thresholdUsd.toStringAsFixed(4)} USD',
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              priceText,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            IconButton(
              onPressed: () => _removeToken(token),
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Remove',
            ),
          ],
        ),
        onTap: () => _editToken(token),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Aura Watch'),
          actions: [
            IconButton(
              onPressed: _loading ? null : _refreshAll,
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh',
            ),
            IconButton(
              icon: const Icon(Icons.bubble_chart),
              tooltip: 'Wallet bubble view',
              onPressed: () {
                Navigator.of(context).pushNamed('/wallet-bubbles');
              },
            ),
            IconButton(
              icon: const Icon(Icons.settings_input_antenna),
              tooltip: 'Solana API / RPC Settings',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const SolanaApiSettingsScreen(),
                  ),
                );
              },
            ),
          ],
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildTopSummary(context),
            const TabBar(
              isScrollable: false,
              tabs: [
                Tab(text: 'Watchlist'),
                Tab(text: 'Trending'),
                Tab(text: 'Stablecoins'),
                Tab(text: 'Whales'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _buildWatchlistTab(),
                  _buildTrendingTab(),
                  _buildStablecoinsTab(),
                  _buildWhalesTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopSummary(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_error != null) ...[
            Text('Error: $_error', style: const TextStyle(color: Colors.redAccent)),
            const SizedBox(height: 12),
          ],
          Text('SOL Price', style: textTheme.labelMedium?.copyWith(color: Colors.grey)),
          const SizedBox(height: 6),
          Text(
            _solPrice,
            style: textTheme.displaySmall?.copyWith(fontWeight: FontWeight.bold) ??
                const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => Navigator.pushNamed(context, '/multi'),
              icon: const Icon(Icons.explore_outlined),
              label: const Text('Open Multi-Chain Watch'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWatchlistTab() {
    if (_watchlistLoading) {
      return _buildMessageTab('Loading watchlist…', loading: true);
    }
    final children = <Widget>[];
    if (_watchlistError != null) {
      children.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            'Watchlist error: $_watchlistError',
            style: const TextStyle(color: Colors.redAccent),
          ),
        ),
      );
    }
    if (_watchlist.isEmpty) {
      children.add(
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Text('Your watchlist is empty.'),
        ),
      );
    } else {
      children.addAll(_watchlist.map(_buildWatchTile));
    }
    children.add(
      Align(
        alignment: Alignment.centerLeft,
        child: Wrap(
          spacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: _addToken,
              icon: const Icon(Icons.add_alert_outlined),
              label: const Text('Add token (manual)'),
            ),
            OutlinedButton.icon(
              onPressed: _searchAndAddToken,
              icon: const Icon(Icons.search),
              label: const Text('Search token'),
            ),
          ],
        ),
      ),
    );

    children.add(const SizedBox(height: 24));
    children.add(
      Text(
        'Address watchlist',
        style: Theme.of(context).textTheme.titleMedium,
      ),
    );
    children.add(const SizedBox(height: 8));

    if (_addressWatchLoading) {
      children.add(
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    } else {
      if (_addressWatchError != null) {
        children.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              'Address watchlist error: $_addressWatchError',
              style: const TextStyle(color: Colors.redAccent),
            ),
          ),
        );
      }
      if (_addressWatchlist.isEmpty) {
        children.add(
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('No watched addresses yet.'),
          ),
        );
      } else {
        children.add(
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _addressWatchlist.length,
            separatorBuilder: (_, __) => const SizedBox(height: 4),
            itemBuilder: (context, index) {
              final addr = _addressWatchlist[index];
              final isSol = addr.chain.toLowerCase() == 'solana';
              return Card(
                child: ListTile(
                  title: Text(addr.label),
                  subtitle: Text(
                    '${addr.chain.toUpperCase()} • ${addr.address}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isSol)
                        IconButton(
                          icon: const Icon(Icons.bubble_chart),
                          tooltip: 'View wallet bubbles',
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => WalletBubbleScreen(
                                  initialAddress: addr.address,
                                ),
                              ),
                            );
                          },
                        ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _removeAddress(addr),
                      ),
                    ],
                  ),
                  onLongPress: () async {
                    final updated = await _showAddressDialog(existing: addr);
                    if (updated == null) return;
                    final list = [..._addressWatchlist];
                    final idx = list.indexOf(addr);
                    if (idx == -1) return;
                    list[idx] = updated;
                    await _updateAddressWatchlist(list);
                  },
                ),
              );
            },
          ),
        );
      }

      children.add(
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: _addAddress,
            icon: const Icon(Icons.add_location_alt_outlined),
            label: const Text('Add address'),
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: children,
    );
  }

  Widget _buildTrendingTab() {
    if (_trending.isEmpty) {
      return _buildMessageTab('No trending tokens to show.');
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _trending.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final t = _trending[index];
        return Card(
          child: ListTile(
            title: Text(t.name),
            subtitle: Text('Vol 24h: ${_num.format(t.volume24h)}'),
            trailing: Text('\$${t.price.toStringAsFixed(4)}'),
          ),
        );
      },
    );
  }

  Widget _buildStablecoinsTab() {
    if (_stablecoinMarkets.isEmpty) {
      return _buildMessageTab('No stablecoins available.');
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _stablecoinMarkets.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final market = _stablecoinMarkets[index];
        final events = _whaleEventsForSymbol(market.info.symbol);
        final latest = events.isNotEmpty ? events.first : null;
        final whaleSummary = latest != null
            ? '${latest.movementType.toUpperCase()} • '
            '${latest.amount?.toStringAsFixed(0) ?? '-'} ${market.info.symbol}'
            : 'Quiet (last ${_whaleWindow.inMinutes}m)';
        final whaleCount = events.length;
        return Card(
          child: ListTile(
            title: Text('${market.info.symbol} • ${market.info.chainLabel}'),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Price ≈ \$${market.price.toStringAsFixed(4)}'),
                Text('Volume 24h: ${_num.format(market.volume24h)}'),
                Text('$whaleSummary • $whaleCount whale moves'),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildWhalesTab() {
    if (_whales.isEmpty) {
      return _buildMessageTab('No recent whale activity.');
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _whales.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) => Card(child: _buildWhaleTile(_whales[index])),
    );
  }

  Widget _buildWhaleTile(WhaleTx w) {
    final amountText = w.amount != null
        ? '${w.amount!.toStringAsFixed(2)} ${w.tokenSymbol}'
        : w.tokenSymbol;
    final timeText = _formatRelativeTime(w.ts);
    Widget trailing = Text(timeText);
    if (w.chain.toLowerCase() == 'solana' && (w.address ?? '').isNotEmpty) {
      trailing = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(timeText),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.bubble_chart),
            tooltip: 'View wallet bubbles',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => WalletBubbleScreen(initialAddress: w.address),
                ),
              );
            },
          ),
        ],
      );
    }
    return ListTile(
      title: Text('${w.tokenSymbol} ${w.movementType.toUpperCase()}'),
      subtitle: Text('${w.chain.toUpperCase()} • ${w.desc} • $amountText'),
      trailing: trailing,
    );
  }

  Widget _buildMessageTab(String message, {bool loading = false}) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (loading) ...[
                const CircularProgressIndicator(),
                const SizedBox(height: 12),
              ],
              Text(message, textAlign: TextAlign.center),
            ],
          ),
        ),
      ],
    );
  }

  String _formatRelativeTime(DateTime ts) {
    final now = DateTime.now();
    final diff = now.difference(ts);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  List<WhaleTx> _whaleEventsForSymbol(String symbol) {
    final upper = symbol.toUpperCase();
    final events = _whales
        .where((event) => event.tokenSymbol.toUpperCase() == upper)
        .toList();
    events.sort((a, b) => b.ts.compareTo(a.ts));
    return events;
  }
}
