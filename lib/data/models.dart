enum BlockchainApiProviderId {
  helius,
  quickNode,
  alchemy,
  ankr,
  chainbase,
  custom,
}

class BlockchainApiProvider {
  final BlockchainApiProviderId id;
  final String name;
  final String description;

  const BlockchainApiProvider({
    required this.id,
    required this.name,
    required this.description,
  });
}

const List<BlockchainApiProvider> kBlockchainApiProviders = [
  BlockchainApiProvider(
    id: BlockchainApiProviderId.helius,
    name: 'Helius',
    description:
    'Solana-focused RPC & webhooks. Paste your Helius mainnet RPC URL.',
  ),
  BlockchainApiProvider(
    id: BlockchainApiProviderId.quickNode,
    name: 'QuickNode',
    description:
    'Multi-chain RPC provider. Paste your QuickNode Solana endpoint URL.',
  ),
  BlockchainApiProvider(
    id: BlockchainApiProviderId.alchemy,
    name: 'Alchemy',
    description:
    'Blockchain data platform. Paste your Alchemy Solana RPC URL if available.',
  ),
  BlockchainApiProvider(
    id: BlockchainApiProviderId.ankr,
    name: 'Ankr',
    description: 'Multi-chain RPC & staking. Paste your Ankr Solana RPC URL.',
  ),
  BlockchainApiProvider(
    id: BlockchainApiProviderId.chainbase,
    name: 'Chainbase',
    description:
    'Blockchain data APIs. Paste your Chainbase Solana endpoint URL.',
  ),
  BlockchainApiProvider(
    id: BlockchainApiProviderId.custom,
    name: 'Custom RPC',
    description:
    'Any other RPC or API endpoint. Paste the full URL including key if needed.',
  ),
];

BlockchainApiProvider providerById(BlockchainApiProviderId id) {
  return kBlockchainApiProviders.firstWhere((p) => p.id == id);
}

// --- Solana API providers ---------------------------------------------------

enum SolanaApiProviderId {
  helius,
  solscan,
  quickNode,
  ankr,
  chainbase,
  blockPi,
  drpc,
  getBlock,
  alchemy,
  triton,
  custom,
}

class SolanaApiProvider {
  final SolanaApiProviderId id;
  final String name;
  final String description;

  const SolanaApiProvider({
    required this.id,
    required this.name,
    required this.description,
  });
}

const List<SolanaApiProvider> kSolanaApiProviders = [
  SolanaApiProvider(
    id: SolanaApiProviderId.helius,
    name: 'Helius',
    description: 'RPC + webhooks + rich indexing. Paste your Helius RPC URL.',
  ),
  SolanaApiProvider(
    id: SolanaApiProviderId.solscan,
    name: 'Solscan',
    description:
    'Explorer API & token data. Paste your Solscan API base URL + key if required.',
  ),
  SolanaApiProvider(
    id: SolanaApiProviderId.quickNode,
    name: 'QuickNode',
    description: 'High-performance RPC. Paste your QuickNode Solana endpoint.',
  ),
  SolanaApiProvider(
    id: SolanaApiProviderId.ankr,
    name: 'Ankr',
    description: 'Free Solana RPC. Paste or leave the default Ankr Solana RPC URL.',
  ),
  SolanaApiProvider(
    id: SolanaApiProviderId.chainbase,
    name: 'Chainbase',
    description: 'Blockchain data & analytics. Paste your Chainbase endpoint for Solana.',
  ),
  SolanaApiProvider(
    id: SolanaApiProviderId.blockPi,
    name: 'BlockPI',
    description:
    'Distributed RPC network. Paste your BlockPI Solana endpoint or use their public one.',
  ),
  SolanaApiProvider(
    id: SolanaApiProviderId.drpc,
    name: 'DRPC',
    description: 'Decentralized RPC. Paste DRPC Solana endpoint.',
  ),
  SolanaApiProvider(
    id: SolanaApiProviderId.getBlock,
    name: 'GetBlock',
    description: 'RPC provider. Paste your GetBlock Solana endpoint.',
  ),
  SolanaApiProvider(
    id: SolanaApiProviderId.alchemy,
    name: 'Alchemy',
    description: 'RPC + analytics. Paste your Alchemy Solana endpoint.',
  ),
  SolanaApiProvider(
    id: SolanaApiProviderId.triton,
    name: 'Triton',
    description: 'High-performance Solana RPC (GenesysGo). Paste your Triton endpoint.',
  ),
  SolanaApiProvider(
    id: SolanaApiProviderId.custom,
    name: 'Custom RPC',
    description: 'Any other Solana RPC URL, including full URL with your API key.',
  ),
];

SolanaApiProvider solanaProviderById(SolanaApiProviderId id) {
  return kSolanaApiProviders.firstWhere((p) => p.id == id);
}

class SolanaApiSettings {
  final SolanaApiProviderId providerId;

  /// Full Solana RPC / API endpoint URL.
  /// For most providers this already includes the API key/token.
  final String rpcUrl;

  const SolanaApiSettings({
    required this.providerId,
    required this.rpcUrl,
  });

  SolanaApiSettings copyWith({
    SolanaApiProviderId? providerId,
    String? rpcUrl,
  }) {
    return SolanaApiSettings(
      providerId: providerId ?? this.providerId,
      rpcUrl: rpcUrl ?? this.rpcUrl,
    );
  }

  Map<String, dynamic> toJson() => {
    'providerId': providerId.name,
    'rpcUrl': rpcUrl,
  };

  factory SolanaApiSettings.fromJson(Map<String, dynamic> json) {
    final providerName = json['providerId'] as String?;
    final providerId = SolanaApiProviderId.values.firstWhere(
          (e) => e.name == providerName,
      orElse: () => SolanaApiProviderId.helius,
    );
    return SolanaApiSettings(
      providerId: providerId,
      rpcUrl: (json['rpcUrl'] as String?) ?? '',
    );
  }
}

class TokenBubbleData {
  final String symbol; // e.g. "SOL", "USDC"
  final String mint; // token mint address
  final double valueUsd; // value of this holding in USD
  final double amount; // raw amount
  final String? logoUrl; // optional icon

  const TokenBubbleData({
    required this.symbol,
    required this.mint,
    required this.valueUsd,
    required this.amount,
    this.logoUrl,
  });
}

enum WalletViewMode { list, bubbles }

class ApiSettings {
  final BlockchainApiProviderId providerId;

  /// Full RPC / API endpoint URL. For most providers this already
  /// includes the API key or token.
  final String rpcUrl;

  const ApiSettings({
    required this.providerId,
    required this.rpcUrl,
  });

  ApiSettings copyWith({
    BlockchainApiProviderId? providerId,
    String? rpcUrl,
  }) {
    return ApiSettings(
      providerId: providerId ?? this.providerId,
      rpcUrl: rpcUrl ?? this.rpcUrl,
    );
  }

  Map<String, dynamic> toJson() => {
    'providerId': providerId.name,
    'rpcUrl': rpcUrl,
  };

  factory ApiSettings.fromJson(Map<String, dynamic> json) {
    final providerName = json['providerId'] as String?;
    final providerId = BlockchainApiProviderId.values.firstWhere(
          (e) => e.name == providerName,
      orElse: () => BlockchainApiProviderId.helius,
    );
    return ApiSettings(
      providerId: providerId,
      rpcUrl: (json['rpcUrl'] as String?) ?? '',
    );
  }
}

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