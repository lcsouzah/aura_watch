import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/models.dart';
import '../data/notification_service.dart';
import '../data/solana_service.dart';
import '../data/token_price_service.dart';
import '../data/watchlist_repository.dart';
import '../screens/api_settings_screen.dart';

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
              icon: const Icon(Icons.settings),
              tooltip: 'API Settings',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const ApiSettingsScreen(),
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
        child: OutlinedButton.icon(
          onPressed: _addToken,
          icon: const Icon(Icons.add_alert_outlined),
          label: const Text('Add token'),
        ),
      ),
    );
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
    return ListTile(
      title: Text('${w.tokenSymbol} ${w.movementType.toUpperCase()}'),
      subtitle: Text('${w.chain.toUpperCase()} • ${w.desc} • $amountText'),
      trailing: Text(timeText),
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
