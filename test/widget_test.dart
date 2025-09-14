import 'package:flutter_test/flutter_test.dart';
import 'package:aura_watch/main.dart';

void main() {
  testWidgets('Home screen displays key sections', (WidgetTester tester) async {
    await tester.pumpWidget(const AuraWatchApp());

    expect(find.text('SOL Price'), findsOneWidget);
    expect(find.text('Trending Tokens (Solana)'), findsOneWidget);
    expect(find.text('Whale Activity'), findsOneWidget);
    expect(find.text('Open Multi‑Chain Watch'), findsOneWidget);
  });
}