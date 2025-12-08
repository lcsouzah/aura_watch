import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/solana_service.dart';
import '../widgets/token_bubble_map.dart';

class WalletBubbleScreen extends StatefulWidget {
  const WalletBubbleScreen({super.key});

  @override
  State<WalletBubbleScreen> createState() => _WalletBubbleScreenState();
}

class _WalletBubbleScreenState extends State<WalletBubbleScreen> {
  final TextEditingController _addressController = TextEditingController();
  bool _loading = false;
  String? _error;
  List<TokenBubbleData> _bubbles = const [];

  Future<void> _load() async {
    final addr = _addressController.text.trim();
    if (addr.isEmpty) {
      setState(() {
        _error = 'Please paste a Solana address.';
        _bubbles = const [];
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _bubbles = const [];
    });

    try {
      final bubbles = await SolanaService.fetchWalletTokenBubbles(addr);
      if (!mounted) return;
      setState(() {
        _bubbles = bubbles;
        if (bubbles.isEmpty) {
          _error = 'No SPL token balances found for this address.';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _bubbles = const [];
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Wallet Bubble View'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _addressController,
              decoration: const InputDecoration(
                labelText: 'Solana address',
                hintText: 'Paste the wallet address to inspect',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.bubble_chart),
                label: _loading
                    ? const Text('Loading...')
                    : const Text('Load tokens'),
              ),
            ),
            const SizedBox(height: 12),
            if (_error != null) ...[
              Text(
                _error!,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: Colors.redAccent),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
            ],
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : TokenBubbleMap(
                tokens: _bubbles,
                onBubbleTap: (token) {
                  showModalBottomSheet(
                    context: context,
                    builder: (ctx) => Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            token.symbol,
                            style: theme.textTheme.titleLarge,
                          ),
                          const SizedBox(height: 8),
                          Text('Mint: ${token.mint}'),
                          const SizedBox(height: 4),
                          Text('Amount: ${token.amount}'),
                          const SizedBox(height: 4),
                          Text('Value (approx): ${token.valueUsd}'),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}