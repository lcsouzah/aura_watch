import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

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
  String _solPrice = 'Loading...';
  bool _loading = false;

  Future<void> _fetchSolPrice() async {
    setState(() => _loading = true);
    try {
      final uri = Uri.parse(
        'https://api.coingecko.com/api/v3/simple/price?ids=solana&vs_currencies=usd',
      );
      final res = await http.get(uri);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final price = data['solana']?['usd'];
        setState(() => _solPrice = price != null ? '\$${price.toString()}' : 'N/A');
      } else {
        setState(() => _solPrice = 'Error ${res.statusCode}');
      }
    } catch (e) {
      setState(() => _solPrice = 'Error');
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _fetchSolPrice();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Aura Watch')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('SOL Price', style: TextStyle(fontSize: 18)),
            const SizedBox(height: 8),
            Text(_solPrice, style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loading ? null : _fetchSolPrice,
              child: Text(_loading ? 'Refreshing...' : 'Refresh'),
            ),
          ],
        ),
      ),
    );
  }
}


