import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state.dart';
import '../widgets/error_banner.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _ctrl;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: context.read<AppState>().baseUrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _error = null;
      _busy = true;
    });
    try {
      await context.read<AppState>().setBaseUrl(_ctrl.text);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gateway URL saved')),
        );
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reset() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset gateway?'),
        content: const Text(
          'This restores all services, entity types, and rows to the original '
          'SAP-style seed. Any custom changes will be lost.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton.tonal(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Reset')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() {
      _error = null;
      _busy = true;
    });
    try {
      await context.read<AppState>().api.resetToSeed();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gateway reset to seed')),
        );
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          if (_error != null) ErrorBanner(message: _error!),
          Text('Gateway', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          TextField(
            controller: _ctrl,
            decoration: const InputDecoration(
              labelText: 'Base URL',
              helperText: 'e.g. http://localhost:8080',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.link),
            ),
            keyboardType: TextInputType.url,
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: _busy ? null : _save,
              icon: const Icon(Icons.save_outlined),
              label: const Text('Save'),
            ),
          ),
          const Divider(height: 48),
          Text('Danger zone', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          const Text(
              'Wipe the running configuration and restore the SAP-style seed.'),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _busy ? null : _reset,
              icon: const Icon(Icons.refresh),
              label: const Text('Reset to seed'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
                side: BorderSide(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
