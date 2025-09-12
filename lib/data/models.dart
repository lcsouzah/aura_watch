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

  WhaleTx({required this.shortHash, required this.chain, required this.desc, required this.ts});
}
