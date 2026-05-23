import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../state.dart';
import '../widgets/error_banner.dart';

/// Lists every connection surface the gateway exposes — OData v2/v4, REST,
/// SOAP/BAPI, IDoc, SQL Server 2017/2022, SurrealDB. All read off the same
/// data, so changes made on the Services tab show up across every protocol.
class ConnectionsScreen extends StatefulWidget {
  const ConnectionsScreen({super.key});

  @override
  State<ConnectionsScreen> createState() => _ConnectionsScreenState();
}

class _ConnectionsScreenState extends State<ConnectionsScreen> {
  Future<List<ConnectionInfo>>? _future;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    setState(() {
      _future = context.read<AppState>().api.listConnections();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Connections'),
        actions: [
          IconButton(
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: FutureBuilder<List<ConnectionInfo>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Padding(
              padding: const EdgeInsets.all(24),
              child: ErrorBanner(message: snap.error.toString()),
            );
          }
          final conns = snap.data ?? const [];
          if (conns.isEmpty) {
            return const Center(child: Text('No connections registered.'));
          }
          final sapConns = conns.where((c) => c.kind == 'sap').toList();
          final dbConns = conns.where((c) => c.kind == 'database').toList();
          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
            children: [
              _Header('SAP ECC 6 connections', sapConns.length),
              for (final c in sapConns) _ConnectionTile(c),
              const SizedBox(height: 24),
              _Header('Databases', dbConns.length),
              for (final c in dbConns) _ConnectionTile(c),
            ],
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.label, this.count);
  final String label;
  final int count;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme.titleMedium;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
      child: Row(
        children: [
          Text(label, style: t),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text('$count',
                style: Theme.of(context).textTheme.labelSmall),
          ),
        ],
      ),
    );
  }
}

class _ConnectionTile extends StatelessWidget {
  const _ConnectionTile(this.c);
  final ConnectionInfo c;

  IconData _iconFor() {
    switch (c.id) {
      case 'odata_v2':
      case 'odata_v4':
        return Icons.api;
      case 'sap_rest':
        return Icons.http;
      case 'sap_soap':
        return Icons.layers_outlined;
      case 'sap_idoc':
        return Icons.markunread_mailbox_outlined;
      case 'sqlserver_2017':
      case 'sqlserver_2022':
        return Icons.storage;
      case 'surrealdb':
        return Icons.bubble_chart_outlined;
      default:
        return Icons.cable;
    }
  }

  Future<void> _copy(BuildContext context, String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Copied $value')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_iconFor(), color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(c.name,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                ),
                for (final m in c.methods)
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        border:
                            Border.all(color: theme.colorScheme.outlineVariant),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(m,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          )),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(c.description, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 12),
            _CopyableRow(label: 'Root', value: c.root, onCopy: _copy),
            const SizedBox(height: 4),
            _CopyableRow(label: 'Sample', value: c.example, onCopy: _copy),
          ],
        ),
      ),
    );
  }
}

class _CopyableRow extends StatelessWidget {
  const _CopyableRow({
    required this.label,
    required this.value,
    required this.onCopy,
  });
  final String label;
  final String value;
  final Future<void> Function(BuildContext, String) onCopy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        SizedBox(
          width: 56,
          child: Text(label,
              style: theme.textTheme.labelMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              value,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        const SizedBox(width: 4),
        IconButton(
          icon: const Icon(Icons.copy, size: 18),
          tooltip: 'Copy',
          onPressed: () => onCopy(context, value),
        ),
      ],
    );
  }
}
