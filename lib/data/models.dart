class TokenMarket {
  final String id;
  final String symbol;
  final String name;
  final double price;
  final double volume24h;

  const TokenMarket({
    required this.id,
    required this.symbol,
    required this.name,
    required this.price,
    required this.volume24h,
  });
}

class WhaleTx {
  final String id; // unique id for duplicate filtering
  final String shortHash;
  final String chain;
  final String tokenSymbol;
  final String movementType; // transfer | buy | sell
  final String desc; // human text e.g. "Amount: 1,234.5678 SOL"
  final DateTime ts;
  final double? amount; // numeric amount in native units (e.g., ETH, BTC, SOL)
  final double? usdValue;

  const WhaleTx({
    required this.id,
    required this.shortHash,
    required this.chain,
    required this.tokenSymbol,
    required this.movementType,
    required this.desc,
    required this.ts,
    this.amount,
    this.usdValue,
  });
}

class WatchedToken {
  final String id; // CoinGecko token id
  final String label;
  final double thresholdUsd;
  final bool alertAbove;

  const WatchedToken({
    required this.id,
    required this.label,
    required this.thresholdUsd,
    required this.alertAbove,
  });

  WatchedToken copyWith({
    String? id,
    String? label,
    double? thresholdUsd,
    bool? alertAbove,
  }) {
    return WatchedToken(
      id: id ?? this.id,
      label: label ?? this.label,
      thresholdUsd: thresholdUsd ?? this.thresholdUsd,
      alertAbove: alertAbove ?? this.alertAbove,
    );
  }

  factory WatchedToken.fromJson(Map<String, dynamic> json) {
    return WatchedToken(
      id: json['id']?.toString() ?? '',
      label: json['label']?.toString() ?? (json['id']?.toString() ?? ''),
      thresholdUsd: (json['thresholdUsd'] as num?)?.toDouble() ?? 0,
      alertAbove: json['alertAbove'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'label': label,
      'thresholdUsd': thresholdUsd,
      'alertAbove': alertAbove,
    };
  }
}

class StablecoinInfo {
  final String symbol;
  final String chainLabel;
  final String coingeckoId;
  final List<String> mintAddresses; // addresses monitored on Solana
  final double whaleThresholdUsd; // min USD value to flag as whale

  const StablecoinInfo({
    required this.symbol,
    required this.chainLabel,
    required this.coingeckoId,
    this.mintAddresses = const [],
    this.whaleThresholdUsd = 250000,
  });
}

class StablecoinMarket {
  final StablecoinInfo info;
  final double price;
  final double volume24h;

  const StablecoinMarket({
    required this.info,
    required this.price,
    required this.volume24h,
  });
}

/// --- Stablecoin helpers ---------------------------------------------------

/// Update this list to add/remove supported stablecoins for both the
/// dedicated Stablecoins section and whale filtering logic.
const List<StablecoinInfo> supportedStablecoins = [
  StablecoinInfo(
    symbol: 'USDC',
    chainLabel: 'Solana',
    coingeckoId: 'usd-coin',
    mintAddresses: ['EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v'],
    whaleThresholdUsd: 250000,
  ),
  StablecoinInfo(
    symbol: 'USDT',
    chainLabel: 'Solana',
    coingeckoId: 'tether',
    mintAddresses: ['Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB'],
    whaleThresholdUsd: 250000,
  ),
];

final Set<String> _stableSymbols =
supportedStablecoins.map((e) => e.symbol.toUpperCase()).toSet();
final Set<String> _stableIds =
supportedStablecoins.map((e) => e.coingeckoId.toLowerCase()).toSet();
final Map<String, StablecoinInfo> _stableByMint = {
  for (final info in supportedStablecoins)
    for (final mint in info.mintAddresses)
      mint: info,
};

bool isStablecoinSymbol(String? symbol) =>
    symbol != null && _stableSymbols.contains(symbol.toUpperCase());

bool isStablecoinId(String? id) =>
    id != null && _stableIds.contains(id.toLowerCase());

bool isStablecoin(String? value) =>
    isStablecoinSymbol(value) || isStablecoinId(value);

StablecoinInfo? stablecoinByMint(String? mint) {
  if (mint == null) return null;
  return _stableByMint[mint];
}