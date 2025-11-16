import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/models.dart';
import '../data/notification_service.dart';
import '../data/solana_service.dart';
import '../data/token_price_service.dart';
import '../data/watchlist_repository.dart';

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

  Widget _buildWatchlistSection() {
    final hasTokens = _watchlist.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Watchlist Alerts'),
        if (_watchlistError != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: Text(
              'Watchlist error: $_watchlistError',
              style: const TextStyle(color: Colors.redAccent),
            ),
          ),
        if (_watchlistLoading)
          const Center(child: CircularProgressIndicator())
        else if (!hasTokens)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('Add a token to start receiving alerts.'),
          )
        else
          ..._watchlist.map(_buildWatchTile),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: _addToken,
            icon: const Icon(Icons.add_alert_outlined),
            label: const Text('Add token'),
          ),
        ),
      ],
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

          _buildStablecoinSection(),

          _sectionTitle('Whale Activity'),
          if (_whales.isEmpty)
            const Text('No data yet.')
          else
            ..._whales.map(_buildWhaleTile),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () => Navigator.pushNamed(context, '/multi'),
            child: const Text('Open Multi‑Chain Watch'),
          ),
        ],
      ),
    );
  }

  Widget _buildStablecoinSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Stablecoins'),
        if (_stablecoinMarkets.isEmpty)
          const Text('No stablecoin data yet.')
        else
          ..._stablecoinMarkets.map((market) {
            final events = _whaleEventsForSymbol(market.info.symbol);
            final latest = events.isNotEmpty ? events.first : null;
            final whaleSummary = latest != null
                ? '${latest.movementType.toUpperCase()} • '
                '${latest.amount?.toStringAsFixed(0) ?? '-'} ${market.info.symbol}'
                : 'Quiet (last ${_whaleWindow.inMinutes}m)';
            final whaleCount = events.length;
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text('${market.info.symbol} • ${market.info.chainLabel}'),
                subtitle: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Volume 24h: ${_num.format(market.volume24h)}'),
                    Text('$whaleSummary • $whaleCount whale moves'),
                  ],
                ),
                trailing: Text('~\$${market.price.toStringAsFixed(4)}'),
              ),
            );
          }),
      ],
    );
  }

  Widget _buildWhaleTile(WhaleTx w) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text('${w.chain.toUpperCase()} • ${w.shortHash}'),
      subtitle: Text('${w.tokenSymbol} ${w.movementType} • ${w.desc}'),
    );
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
