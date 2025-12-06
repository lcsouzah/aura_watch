import 'dart:math';
import 'package:flutter/material.dart';
import '../data/models.dart';

class TokenBubbleMap extends StatelessWidget {
  final List<TokenBubbleData> tokens;
  final void Function(TokenBubbleData)? onBubbleTap;

  const TokenBubbleMap({
    super.key,
    required this.tokens,
    this.onBubbleTap,
  });

  @override
  Widget build(BuildContext context) {
    if (tokens.isEmpty) {
      return const Center(child: Text('No tokens found for this address'));
    }

    final sorted = [...tokens]
      ..sort(
            (a, b) => b.valueUsd.compareTo(a.valueUsd),
      );

    final total = sorted.fold<double>(0, (sum, t) => sum + t.valueUsd);
    if (total <= 0) {
      return const Center(child: Text('No value to display'));
    }

    const double minRadius = 24;
    const double maxRadius = 80;

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: Center(
            child: Wrap(
              alignment: WrapAlignment.center,
              runSpacing: 12,
              spacing: 12,
              children: sorted.map((t) {
                final weight = (t.valueUsd / total).clamp(0.0, 1.0);
                final radius = minRadius +
                    (maxRadius - minRadius) * sqrt(weight);

                return GestureDetector(
                  onTap: onBubbleTap == null ? null : () => onBubbleTap!(t),
                  child: _TokenBubble(
                    token: t,
                    radius: radius,
                    weight: weight,
                  ),
                );
              }).toList(),
            ),
          ),
        );
      },
    );
  }
}

class _TokenBubble extends StatelessWidget {
  final TokenBubbleData token;
  final double radius;
  final double weight;

  const _TokenBubble({
    required this.token,
    required this.radius,
    required this.weight,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final baseColor = theme.colorScheme.primary;
    final bubbleColor = baseColor.withOpacity(0.4 + 0.4 * weight);

    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: bubbleColor,
        boxShadow: [
          BoxShadow(
            blurRadius: 8,
            spreadRadius: 1,
            offset: const Offset(0, 4),
            color: Colors.black.withOpacity(0.15),
          ),
        ],
      ),
      child: Center(
        child: FittedBox(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                token.symbol,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '\$${token.valueUsd.toStringAsFixed(0)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onPrimary.withOpacity(0.9),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}