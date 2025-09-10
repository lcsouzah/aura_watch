import 'package:flutter/material.dart';

void main() {
  runApp(const AuraWatchApp());
}

class AuraWatchApp extends StatelessWidget {
  const AuraWatchApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Aura Watch',
      theme: ThemeData.dark(),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String solPrice = "Loading...";

  Future<void> fetchSolPrice() async {
    try {
      final uri = Uri.parse(
        "https://api.coingecko.com/api/v3/simple/price?ids=solana&vs_currencies=usd",
      );
      final response = await Uri.base.resolveUri(uri).toFilePath(); // temp placeholder
    } catch (e) {
      setState(() => solPrice = "Error");
    }
  }

  @override
  void initState() {
    super.initState();
    fetchSolPrice();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Aura Watch")),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text("SOL Price:", style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(solPrice, style: Theme.of(context).textTheme.headlineMedium),
          ],
        ),
      ),
    );
  }
}

