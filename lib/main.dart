import 'package:flutter/material.dart';
import 'features/home_screen.dart';
import 'features/multichain_screen.dart';

void main() => runApp(const AuraWatchApp());

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
      },
      initialRoute: '/',
    );
  }
}
