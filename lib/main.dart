import 'package:flutter/material.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'data/notification_service.dart';
import 'features/home_screen.dart';
import 'features/multichain_screen.dart';
import 'features/wallet_bubble_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  await NotificationService.initialize();
  runApp(const AuraWatchApp());
}

class AuraWatchApp extends StatelessWidget {
  const AuraWatchApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Aura Watch',
      theme: ThemeData.dark(),
      routes: {
        '/': (_) => const HomeScreen(),
        '/multi': (_) => const MultiChainScreen(),
        '/wallet-bubbles': (_) => const WalletBubbleScreen(),

      },
      initialRoute: '/',
    );
  }
}
