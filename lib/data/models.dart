class TokenMarket {
  final String name;
  final double price;
  final double volume24h;

  TokenMarket({required this.name, required this.price, required this.volume24h});
}

class WhaleTx {
  final String shortHash;
  final String chain;
  final String desc;    // human text e.g. "Amount: 1,234.5678 SOL"
  final DateTime ts;
  final double? amount; // numeric amount in native units (e.g., ETH, BTC, SOL)

  WhaleTx({
    required this.shortHash,
    required this.chain,
    required this.desc,
    required this.ts,
    this.amount,
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