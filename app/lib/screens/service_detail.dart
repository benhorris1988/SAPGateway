import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../models.dart';
import '../state.dart';
import '../widgets/error_banner.dart';
import 'entity_type_detail.dart';
import 'rows.dart';

class ServiceDetailScreen extends StatefulWidget {
  const ServiceDetailScreen({super.key, required this.serviceName});

  final String serviceName;

  @override
  State<ServiceDetailScreen> createState() => _ServiceDetailScreenState();
}

class _ServiceDetailScreenState extends State<ServiceDetailScreen> {
  late Future<_ServiceBundle> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_ServiceBundle> _load() async {
    final api = context.read<AppState>().api;
    final sets = api.listEntitySets(widget.serviceName);
    final types = api.listEntityTypes(widget.serviceName);
    return _ServiceBundle(await sets, await types);
  }

  void _refresh() {
    setState(() => _future = _load());
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.serviceName),
          bottom: const TabBar(tabs: [
            Tab(icon: Icon(Icons.table_view_outlined), text: 'Entity Sets'),
            Tab(icon: Icon(Icons.schema_outlined), text: 'Entity Types'),
          ]),
          actions: [
            IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh)),
          ],
        ),
        body: FutureBuilder<_ServiceBundle>(
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
            final bundle = snap.data!;
            return TabBarView(children: [
              _EntitySetsTab(
                service: widget.serviceName,
                sets: bundle.sets,
                types: bundle.types,
                onChanged: _refresh,
              ),
              _EntityTypesTab(
                service: widget.serviceName,
                types: bundle.types,
                onChanged: _refresh,
              ),
            ]);
          },
        ),
      ),
    );
  }
}

class _ServiceBundle {
  _ServiceBundle(this.sets, this.types);
  final List<EntitySetSummary> sets;
  final List<EntityType> types;
}

// ─── Entity Sets tab ─────────────────────────────────────────────────────

class _EntitySetsTab extends StatelessWidget {
  const _EntitySetsTab({
    required this.service,
    required this.sets,
    required this.types,
    required this.onChanged,
  });

  final String service;
  final List<EntitySetSummary> sets;
  final List<EntityType> types;
  final VoidCallback onChanged;

  Future<void> _add(BuildContext context) async {
    if (types.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Create an Entity Type first.'),
      ));
      return;
    }
    final res = await showDialog<_NewSet>(
      context: context,
      builder: (_) => _NewSetDialog(types: types),
    );
    if (res == null) return;
    try {
      await context.read<AppState>().api.createEntitySet(
            service,
            name: res.name,
            entityTypeName: res.typeName,
          );
      onChanged();
    } on GatewayException catch (e) {
      _toast(context, e.message);
    }
  }

  Future<void> _delete(BuildContext context, EntitySetSummary s) async {
    final ok = await _confirmDelete(context, 'Delete ${s.name}?',
        'All rows in this Entity Set will be removed.');
    if (!ok) return;
    try {
      await context.read<AppState>().api.deleteEntitySet(service, s.name);
      onChanged();
    } on GatewayException catch (e) {
      _toast(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab-sets',
        onPressed: () => _add(context),
        icon: const Icon(Icons.add),
        label: const Text('New Entity Set'),
      ),
      body: sets.isEmpty
          ? const Center(child: Text('No Entity Sets yet.'))
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              itemCount: sets.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final s = sets[i];
                return Card(
                  child: ListTile(
                    leading: const CircleAvatar(
                        child: Icon(Icons.table_rows_outlined)),
                    title: Text(s.name,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text('${s.entityTypeName} · ${s.rowCount} rows'),
                    trailing: PopupMenuButton<String>(
                      onSelected: (v) {
                        if (v == 'delete') _delete(context, s);
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'delete', child: Text('Delete')),
                      ],
                    ),
                    onTap: () async {
                      await Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => RowsScreen(
                          service: service,
                          entitySetName: s.name,
                          entityType: types.firstWhere(
                              (t) => t.name == s.entityTypeName,
                              orElse: () => EntityType(
                                  name: s.entityTypeName,
                                  keys: const [],
                                  properties: const [])),
                        ),
                      ));
                      onChanged();
                    },
                  ),
                );
              },
            ),
    );
  }
}

class _NewSet {
  _NewSet(this.name, this.typeName);
  final String name;
  final String typeName;
}

class _NewSetDialog extends StatefulWidget {
  const _NewSetDialog({required this.types});
  final List<EntityType> types;

  @override
  State<_NewSetDialog> createState() => _NewSetDialogState();
}

class _NewSetDialogState extends State<_NewSetDialog> {
  final _name = TextEditingController();
  String? _type;

  @override
  void initState() {
    super.initState();
    _type = widget.types.isNotEmpty ? widget.types.first.name : null;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New Entity Set'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'EntitySet name',
                hintText: 'EmployeeSet',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _type,
              decoration: const InputDecoration(
                labelText: 'Entity Type',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final t in widget.types)
                  DropdownMenuItem(value: t.name, child: Text(t.name)),
              ],
              onChanged: (v) => setState(() => _type = v),
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
            if (n.isEmpty || _type == null) return;
            Navigator.pop(context, _NewSet(n, _type!));
          },
          child: const Text('Create'),
        ),
      ],
    );
  }
}

// ─── Entity Types tab ────────────────────────────────────────────────────

class _EntityTypesTab extends StatelessWidget {
  const _EntityTypesTab({
    required this.service,
    required this.types,
    required this.onChanged,
  });

  final String service;
  final List<EntityType> types;
  final VoidCallback onChanged;

  Future<void> _add(BuildContext context) async {
    final res = await showDialog<_NewType>(
      context: context,
      builder: (_) => const _NewTypeDialog(),
    );
    if (res == null) return;
    try {
      await context.read<AppState>().api.createEntityType(
            service,
            name: res.name,
            keys: res.keys,
          );
      onChanged();
    } on GatewayException catch (e) {
      _toast(context, e.message);
    }
  }

  Future<void> _delete(BuildContext context, EntityType t) async {
    final ok = await _confirmDelete(context, 'Delete ${t.name}?',
        'Any Entity Sets using this type will also be removed.');
    if (!ok) return;
    try {
      await context.read<AppState>().api.deleteEntityType(service, t.name);
      onChanged();
    } on GatewayException catch (e) {
      _toast(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab-types',
        onPressed: () => _add(context),
        icon: const Icon(Icons.add),
        label: const Text('New Entity Type'),
      ),
      body: types.isEmpty
          ? const Center(child: Text('No Entity Types yet.'))
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              itemCount: types.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final t = types[i];
                return Card(
                  child: ListTile(
                    leading:
                        const CircleAvatar(child: Icon(Icons.schema_outlined)),
                    title: Text(t.name,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      '${t.properties.length} properties · key: ${t.keys.join(', ')}',
                    ),
                    trailing: PopupMenuButton<String>(
                      onSelected: (v) {
                        if (v == 'delete') _delete(context, t);
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'delete', child: Text('Delete')),
                      ],
                    ),
                    onTap: () async {
                      await Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => EntityTypeDetailScreen(
                                service: service,
                                typeName: t.name,
                              )));
                      onChanged();
                    },
                  ),
                );
              },
            ),
    );
  }
}

class _NewType {
  _NewType(this.name, this.keys);
  final String name;
  final List<String> keys;
}

class _NewTypeDialog extends StatefulWidget {
  const _NewTypeDialog();

  @override
  State<_NewTypeDialog> createState() => _NewTypeDialogState();
}

class _NewTypeDialogState extends State<_NewTypeDialog> {
  final _name = TextEditingController();
  final _keys = TextEditingController(text: 'Id');

  @override
  void dispose() {
    _name.dispose();
    _keys.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New Entity Type'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Type name',
                hintText: 'Customer',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _keys,
              decoration: const InputDecoration(
                labelText: 'Key property names (comma-separated)',
                hintText: 'Id  or  Vbeln,Posnr',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'You can add properties (columns) after the type is created.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
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
            final keys = _keys.text
                .split(',')
                .map((s) => s.trim())
                .where((s) => s.isNotEmpty)
                .toList();
            if (n.isEmpty || keys.isEmpty) return;
            Navigator.pop(context, _NewType(n, keys));
          },
          child: const Text('Create'),
        ),
      ],
    );
  }
}

// ─── shared helpers ──────────────────────────────────────────────────────

Future<bool> _confirmDelete(
    BuildContext context, String title, String body) async {
  final res = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(body),
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
  return res == true;
}

void _toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
}
