import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../state.dart';
import '../widgets/error_banner.dart';
import 'service_detail.dart';

class ServicesScreen extends StatefulWidget {
  const ServicesScreen({super.key});

  @override
  State<ServicesScreen> createState() => _ServicesScreenState();
}

class _ServicesScreenState extends State<ServicesScreen> {
  late Future<List<ServiceSummary>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<ServiceSummary>> _load() {
    return context.read<AppState>().api.listServices();
  }

  void _refresh() {
    setState(() => _future = _load());
  }

  Future<void> _add() async {
    final result = await showDialog<_ServiceFormResult>(
      context: context,
      builder: (_) => const _ServiceDialog(),
    );
    if (result == null) return;
    try {
      await context.read<AppState>().api.createService(
            name: result.name,
            namespace: result.namespace,
            description: result.description,
          );
      _refresh();
    } catch (e) {
      _toast(e.toString());
    }
  }

  Future<void> _delete(ServiceSummary s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${s.name}?'),
        content: const Text(
            'This removes the service, its entity types, sets, and rows.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.errorContainer),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await context.read<AppState>().api.deleteService(s.name);
      _refresh();
    } catch (e) {
      _toast(e.toString());
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Selector<AppState, String>(
          selector: (_, s) => s.baseUrl,
          builder: (_, url, __) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Services'),
              Text(url,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(fontWeight: FontWeight.w400)),
            ],
          ),
        ),
        actions: [
          IconButton(
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: const Text('New service'),
      ),
      body: RefreshIndicator(
        onRefresh: () async => _refresh(),
        child: FutureBuilder<List<ServiceSummary>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return ListView(padding: const EdgeInsets.all(16), children: [
                ErrorBanner(message: snap.error.toString()),
              ]);
            }
            final items = snap.data ?? const [];
            if (items.isEmpty) {
              return ListView(
                padding: const EdgeInsets.symmetric(vertical: 80),
                children: const [
                  Center(child: Icon(Icons.cloud_off, size: 48)),
                  SizedBox(height: 12),
                  Center(child: Text('No services configured yet.')),
                ],
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final s = items[i];
                return Card(
                  child: ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.dns)),
                    title: Text(s.name,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      [
                        if (s.description.isNotEmpty) s.description,
                        '${s.entitySetCount} sets · ${s.entityTypeCount} types · ${s.rowCount} rows',
                      ].join('  ·  '),
                    ),
                    trailing: PopupMenuButton<String>(
                      onSelected: (v) {
                        if (v == 'delete') _delete(s);
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'delete', child: Text('Delete')),
                      ],
                    ),
                    onTap: () async {
                      await Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) =>
                              ServiceDetailScreen(serviceName: s.name)));
                      _refresh();
                    },
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _ServiceFormResult {
  _ServiceFormResult(this.name, this.namespace, this.description);
  final String name;
  final String namespace;
  final String description;
}

class _ServiceDialog extends StatefulWidget {
  const _ServiceDialog();

  @override
  State<_ServiceDialog> createState() => _ServiceDialogState();
}

class _ServiceDialogState extends State<_ServiceDialog> {
  final _name = TextEditingController();
  final _ns = TextEditingController();
  final _desc = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _ns.dispose();
    _desc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New service'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Service name',
                hintText: 'ZCUSTOM_SRV',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _ns,
              decoration: const InputDecoration(
                labelText: 'Namespace (defaults to service name)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _desc,
              decoration: const InputDecoration(
                labelText: 'Description',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            final n = _name.text.trim();
            if (n.isEmpty) return;
            Navigator.pop(
              context,
              _ServiceFormResult(
                  n,
                  _ns.text.trim().isEmpty ? n : _ns.text.trim(),
                  _desc.text.trim()),
            );
          },
          child: const Text('Create'),
        ),
      ],
    );
  }
}
