import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../models.dart';
import '../state.dart';
import '../widgets/error_banner.dart';

/// Browse and edit the row data backing a single Entity Set.
class RowsScreen extends StatefulWidget {
  const RowsScreen({
    super.key,
    required this.service,
    required this.entitySetName,
    required this.entityType,
  });

  final String service;
  final String entitySetName;
  final EntityType entityType;

  @override
  State<RowsScreen> createState() => _RowsScreenState();
}

class _RowsScreenState extends State<RowsScreen> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() {
    return context
        .read<AppState>()
        .api
        .listRows(widget.service, widget.entitySetName);
  }

  void _refresh() {
    setState(() => _future = _load());
  }

  Future<void> _addOrEdit({
    Map<String, dynamic>? initial,
    int? index,
  }) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _RowDialog(
        type: widget.entityType,
        initial: initial,
        editing: index != null,
      ),
    );
    if (result == null) return;
    final api = context.read<AppState>().api;
    try {
      if (index == null) {
        await api.addRow(widget.service, widget.entitySetName, result);
      } else {
        await api.updateRow(
            widget.service, widget.entitySetName, index, result);
      }
      _refresh();
    } on GatewayException catch (e) {
      _toast(e.message);
    }
  }

  Future<void> _delete(int index) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete row?'),
        content: const Text('This action cannot be undone.'),
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
          .deleteRow(widget.service, widget.entitySetName, index);
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
    final props = widget.entityType.properties;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.entitySetName),
            Text(widget.entityType.name,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(fontWeight: FontWeight.w400)),
          ],
        ),
        actions: [
          IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addOrEdit(),
        icon: const Icon(Icons.add),
        label: const Text('Add row'),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
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
          final rows = snap.data ?? const [];
          if (rows.isEmpty) {
            return const Center(child: Text('No rows yet. Tap "Add row".'));
          }
          if (props.isEmpty) {
            return const Center(
                child: Text('Add properties to the entity type first.'));
          }
          return LayoutBuilder(builder: (ctx, constraints) {
            return Scrollbar(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: constraints.maxWidth),
                  child: DataTable(
                    columnSpacing: 24,
                    columns: [
                      for (final p in props)
                        DataColumn(
                            label: _ColumnHeader(
                                p, widget.entityType.keys.contains(p.name))),
                      const DataColumn(label: Text('')),
                    ],
                    rows: [
                      for (int i = 0; i < rows.length; i++)
                        DataRow(cells: [
                          for (final p in props)
                            DataCell(
                              Text(rows[i][p.name]?.toString() ?? ''),
                              onTap: () =>
                                  _addOrEdit(initial: rows[i], index: i),
                            ),
                          DataCell(
                            Row(mainAxisSize: MainAxisSize.min, children: [
                              IconButton(
                                tooltip: 'Edit',
                                icon: const Icon(Icons.edit_outlined),
                                onPressed: () =>
                                    _addOrEdit(initial: rows[i], index: i),
                              ),
                              IconButton(
                                tooltip: 'Delete',
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => _delete(i),
                              ),
                            ]),
                          ),
                        ]),
                    ],
                  ),
                ),
              ),
            );
          });
        },
      ),
    );
  }
}

class _ColumnHeader extends StatelessWidget {
  const _ColumnHeader(this.prop, this.isKey);
  final Property prop;
  final bool isKey;
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isKey) const Icon(Icons.key, size: 14),
        if (isKey) const SizedBox(width: 4),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(prop.name,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            Text(prop.edmType,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Theme.of(context).hintColor)),
          ],
        ),
      ],
    );
  }
}

class _RowDialog extends StatefulWidget {
  const _RowDialog({
    required this.type,
    required this.editing,
    this.initial,
  });

  final EntityType type;
  final bool editing;
  final Map<String, dynamic>? initial;

  @override
  State<_RowDialog> createState() => _RowDialogState();
}

class _RowDialogState extends State<_RowDialog> {
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, bool> _boolValues = {};

  @override
  void initState() {
    super.initState();
    for (final p in widget.type.properties) {
      final initial = widget.initial?[p.name];
      if (p.edmType == 'Edm.Boolean') {
        _boolValues[p.name] =
            initial == true || initial?.toString().toLowerCase() == 'true';
      } else {
        _controllers[p.name] =
            TextEditingController(text: initial?.toString() ?? '');
      }
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextInputType _keyboard(String edmType) {
    switch (edmType) {
      case 'Edm.Int16':
      case 'Edm.Int32':
      case 'Edm.Int64':
      case 'Edm.Byte':
        return TextInputType.number;
      case 'Edm.Decimal':
      case 'Edm.Double':
      case 'Edm.Single':
        return const TextInputType.numberWithOptions(
            decimal: true, signed: true);
      case 'Edm.DateTime':
      case 'Edm.DateTimeOffset':
        return TextInputType.datetime;
      default:
        return TextInputType.text;
    }
  }

  String? _hint(String edmType) {
    switch (edmType) {
      case 'Edm.DateTime':
      case 'Edm.DateTimeOffset':
        return 'YYYY-MM-DDTHH:MM:SS';
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.editing ? 'Edit row' : 'New row'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final p in widget.type.properties) ...[
                if (p.edmType == 'Edm.Boolean')
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _boolValues[p.name] ?? false,
                    onChanged: (v) => setState(() => _boolValues[p.name] = v),
                    title: Text(_labelFor(p)),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: TextField(
                      controller: _controllers[p.name],
                      keyboardType: _keyboard(p.edmType),
                      decoration: InputDecoration(
                        labelText: _labelFor(p),
                        hintText: _hint(p.edmType),
                        helperText: p.edmType,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
              ],
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
            final out = <String, dynamic>{};
            for (final p in widget.type.properties) {
              if (p.edmType == 'Edm.Boolean') {
                out[p.name] = _boolValues[p.name] ?? false;
              } else {
                final txt = _controllers[p.name]!.text;
                if (txt.isEmpty) {
                  if (!p.nullable) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text('${p.name} cannot be empty'),
                    ));
                    return;
                  }
                  continue;
                }
                out[p.name] = _coerce(txt, p.edmType);
              }
            }
            Navigator.pop(context, out);
          },
          child: Text(widget.editing ? 'Save' : 'Add'),
        ),
      ],
    );
  }

  String _labelFor(Property p) {
    final label = p.label;
    if (label != null && label.isNotEmpty) return '${p.name} — $label';
    return p.name;
  }

  dynamic _coerce(String text, String edmType) {
    switch (edmType) {
      case 'Edm.Int16':
      case 'Edm.Int32':
      case 'Edm.Int64':
      case 'Edm.Byte':
        return int.tryParse(text) ?? text;
      case 'Edm.Double':
      case 'Edm.Single':
        return double.tryParse(text) ?? text;
      case 'Edm.Decimal':
        // Keep decimals as strings so we don't lose precision/trailing zeros.
        return text;
      default:
        return text;
    }
  }
}
