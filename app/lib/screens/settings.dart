import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../logging.dart';
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
          Text('Diagnostics', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          const Text(
              'Recent client-side warnings and errors. Errors are also shipped '
              'to the gateway log (visible at /admin/logs).'),
          const SizedBox(height: 12),
          const _RecentLogs(),
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

/// Shows the most recent warning/error entries from the in-memory app log.
class _RecentLogs extends StatefulWidget {
  const _RecentLogs();

  @override
  State<_RecentLogs> createState() => _RecentLogsState();
}

class _RecentLogsState extends State<_RecentLogs> {
  List<AppLogEntry> _entries() => appLog.recent
      .where((e) =>
          e.level == AppLogLevel.warn || e.level == AppLogLevel.error)
      .toList()
      .reversed
      .toList();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entries = _entries();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: () => setState(() {}),
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Refresh'),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: entries.isEmpty
                  ? null
                  : () {
                      appLog.clear();
                      setState(() {});
                    },
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const Text('Clear'),
            ),
            const SizedBox(width: 8),
            if (entries.isNotEmpty)
              IconButton(
                tooltip: 'Copy all',
                icon: const Icon(Icons.copy, size: 18),
                onPressed: () {
                  final text = entries
                      .map((e) =>
                          '${e.timestamp.toIso8601String()} [${e.level.label}] ${e.message}'
                          '${e.error != null ? ' | ${e.error}' : ''}')
                      .join('\n');
                  Clipboard.setData(ClipboardData(text: text));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Log copied')),
                  );
                },
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (entries.isEmpty)
          Text('No warnings or errors recorded this session.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant))
        else
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: theme.colorScheme.outlineVariant),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                for (var i = 0; i < entries.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  _LogRow(entries[i]),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _LogRow extends StatelessWidget {
  const _LogRow(this.entry);
  final AppLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isError = entry.level == AppLogLevel.error;
    final color =
        isError ? theme.colorScheme.error : theme.colorScheme.tertiary;
    String hhmmss(DateTime t) {
      String two(int v) => v.toString().padLeft(2, '0');
      return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(isError ? Icons.error_outline : Icons.warning_amber_outlined,
              size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${entry.level.label} · ${hhmmss(entry.timestamp)}',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: color, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(entry.message, style: theme.textTheme.bodySmall),
                if (entry.error != null) ...[
                  const SizedBox(height: 2),
                  Text(entry.error!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontFamily: 'monospace',
                      )),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
