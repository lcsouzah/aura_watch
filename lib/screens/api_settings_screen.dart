import 'package:flutter/material.dart';

import '../data/models.dart';
import '../services/api_settings_repository.dart';

class ApiSettingsScreen extends StatefulWidget {
  const ApiSettingsScreen({super.key});

  @override
  State<ApiSettingsScreen> createState() => _ApiSettingsScreenState();
}

class _ApiSettingsScreenState extends State<ApiSettingsScreen> {
  BlockchainApiProviderId _selectedId = BlockchainApiProviderId.helius;
  final TextEditingController _rpcUrlController = TextEditingController();
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _rpcUrlController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final existing = await ApiSettingsRepository.instance.load();
    if (!mounted) return;
    setState(() {
      if (existing != null) {
        _selectedId = existing.providerId;
        _rpcUrlController.text = existing.rpcUrl;
      }
      _loading = false;
    });
  }

  Future<void> _save() async {
    final rpcUrl = _rpcUrlController.text.trim();
    if (rpcUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please paste a valid RPC / API URL.')),
      );
      return;
    }

    setState(() => _saving = true);
    final settings = ApiSettings(providerId: _selectedId, rpcUrl: rpcUrl);
    await ApiSettingsRepository.instance.save(settings);
    if (!mounted) return;
    setState(() => _saving = false);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('API settings saved')),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final provider = providerById(_selectedId);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Blockchain API Settings'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            DropdownButtonFormField<BlockchainApiProviderId>(
              value: _selectedId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Provider',
                border: OutlineInputBorder(),
              ),
              items: BlockchainApiProviderId.values.map((id) {
                final p = providerById(id);
                return DropdownMenuItem(
                  value: id,
                  child: Text(p.name),
                );
              }).toList(),
              onChanged: (value) {
                if (value == null) return;
                setState(() => _selectedId = value);
              },
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                provider.description,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _rpcUrlController,
              decoration: const InputDecoration(
                labelText: 'RPC / API endpoint URL',
                hintText: 'Paste the full URL from your provider dashboard',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const CircularProgressIndicator()
                    : const Text('Save'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}