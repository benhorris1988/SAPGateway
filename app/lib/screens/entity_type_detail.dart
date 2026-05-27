import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../models.dart';
import '../state.dart';
import '../widgets/error_banner.dart';

/// Manage properties (columns) of a single Entity Type.
class EntityTypeDetailScreen extends StatefulWidget {
  const EntityTypeDetailScreen({
    super.key,
    required this.service,
    required this.typeName,
  });

  final String service;
  final String typeName;

  @override
  State<EntityTypeDetailScreen> createState() => _EntityTypeDetailScreenState();
}

class _EntityTypeDetailScreenState extends State<EntityTypeDetailScreen> {
  late Future<EntityType> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<EntityType> _load() async {
    final list =
        await context.read<AppState>().api.listEntityTypes(widget.service);
    return list.firstWhere((t) => t.name == widget.typeName);
  }

  void _refresh() {
    setState(() => _future = _load());
  }

  Future<void> _addOrEdit(EntityType type, [Property? existing]) async {
    final result = await showDialog<Property>(
      context: context,
      builder: (_) => _PropertyDialog(existing: existing),
    );
    if (result == null) return;
    final api = context.read<AppState>().api;
    try {
      if (existing == null) {
        await api.addProperty(widget.service, widget.typeName, result);
      } else {
        await api.updateProperty(
            widget.service, widget.typeName, existing.name, result);
      }
      _refresh();
    } on GatewayException catch (e) {
      _toast(e.message);
    }
  }

  Future<void> _delete(Property p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${p.name}?'),
        content: const Text(
            'The property and its values in every row of every Entity Set using '
            'this type will be removed.'),
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
      await context
          .read<AppState>()
          .api
          .deleteProperty(widget.service, widget.typeName, p.name);
      _refresh();
    } on GatewayException catch (e) {
      _toast(e.message);
    }
  }

  Future<void> _editKeys(EntityType type) async {
    final ctrl = TextEditingController(text: type.keys.join(', '));
    final keys = await showDialog<List<String>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit key fields'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Comma-separated property names',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final parts = ctrl.text
                  .split(',')
                  .map((s) => s.trim())
                  .where((s) => s.isNotEmpty)
                  .toList();
              Navigator.pop(ctx, parts);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (keys == null || keys.isEmpty) return;
    try {
      await context
          .read<AppState>()
          .api
          .updateEntityType(widget.service, widget.typeName, keys: keys);
      _refresh();
    } on GatewayException catch (e) {
      _toast(e.message);
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.typeName),
        actions: [
          IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh)),
        ],
      ),
      floatingActionButton: FutureBuilder<EntityType>(
        future: _future,
        builder: (_, snap) {
          if (!snap.hasData) return const SizedBox.shrink();
          return FloatingActionButton.extended(
            onPressed: () => _addOrEdit(snap.data!),
            icon: const Icon(Icons.add),
            label: const Text('Add property'),
          );
        },
      ),
      body: FutureBuilder<EntityType>(
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
          final type = snap.data!;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              Card(
                child: ListTile(
                  title: const Text('Keys'),
                  subtitle: Text(type.keys.join(', ')),
                  trailing: IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () => _editKeys(type),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text('Properties',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              for (final p in type.properties)
                Card(
                  child: ListTile(
                    leading: Icon(
                      type.keys.contains(p.name)
                          ? Icons.key
                          : Icons.label_outline,
                    ),
                    title: Text(p.name,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(_propSubtitle(p)),
                    trailing: PopupMenuButton<String>(
                      onSelected: (v) {
                        if (v == 'edit') _addOrEdit(type, p);
                        if (v == 'delete') _delete(p);
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'edit', child: Text('Edit')),
                        PopupMenuItem(value: 'delete', child: Text('Delete')),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  String _propSubtitle(Property p) {
    final parts = <String>[p.edmType];
    if (!p.nullable) parts.add('not null');
    if (p.maxLength != null) parts.add('max ${p.maxLength}');
    if (p.precision != null) {
      parts.add(
          'precision ${p.precision}${p.scale != null ? ',${p.scale}' : ''}');
    }
    if (p.label != null && p.label!.isNotEmpty) parts.add('"${p.label!}"');
    return parts.join(' · ');
  }
}

class _PropertyDialog extends StatefulWidget {
  const _PropertyDialog({this.existing});
  final Property? existing;

  @override
  State<_PropertyDialog> createState() => _PropertyDialogState();
}

class _PropertyDialogState extends State<_PropertyDialog> {
  late final TextEditingController _name;
  late final TextEditingController _maxLength;
  late final TextEditingController _precision;
  late final TextEditingController _scale;
  late final TextEditingController _label;
  late String _type;
  late bool _nullable;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _maxLength = TextEditingController(text: e?.maxLength?.toString() ?? '');
    _precision = TextEditingController(text: e?.precision?.toString() ?? '');
    _scale = TextEditingController(text: e?.scale?.toString() ?? '');
    _label = TextEditingController(text: e?.label ?? '');
    _type = e?.edmType ?? 'Edm.String';
    _nullable = e?.nullable ?? true;
  }

  @override
  void dispose() {
    _name.dispose();
    _maxLength.dispose();
    _precision.dispose();
    _scale.dispose();
    _label.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'Add property' : 'Edit property'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _name,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Property name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _type,
                decoration: const InputDecoration(
                  labelText: 'EDM type',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final t in Property.edmTypes)
                    DropdownMenuItem(value: t, child: Text(t)),
                ],
                onChanged: (v) => setState(() => _type = v ?? _type),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _label,
                decoration: const InputDecoration(
                  labelText: 'Label (sap:label)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _maxLength,
                      decoration: const InputDecoration(
                        labelText: 'maxLength',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _precision,
                      decoration: const InputDecoration(
                        labelText: 'precision',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _scale,
                      decoration: const InputDecoration(
                        labelText: 'scale',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _nullable,
                onChanged: (v) => setState(() => _nullable = v),
                title: const Text('Nullable'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            final name = _name.text.trim();
            if (name.isEmpty) return;
            int? toIntOrNull(String s) =>
                s.trim().isEmpty ? null : int.tryParse(s.trim());
            Navigator.pop(
              context,
              Property(
                name: name,
                edmType: _type,
                nullable: _nullable,
                maxLength: toIntOrNull(_maxLength.text),
                precision: toIntOrNull(_precision.text),
                scale: toIntOrNull(_scale.text),
                label: _label.text.trim().isEmpty ? null : _label.text.trim(),
              ),
            );
          },
          child: Text(widget.existing == null ? 'Add' : 'Save'),
        ),
      ],
    );
  }
}
