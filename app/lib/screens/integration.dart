import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../models.dart';
import '../state.dart';
import '../widgets/error_banner.dart';

/// One-stop screen for the SAP <-> SurrealDB integration:
/// - Surreal connection card (test/save)
/// - Mappings list (run pull/push, edit, delete, add)
/// - Audit log
class IntegrationScreen extends StatefulWidget {
  const IntegrationScreen({super.key});

  @override
  State<IntegrationScreen> createState() => _IntegrationScreenState();
}

class _IntegrationScreenState extends State<IntegrationScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  IntegrationConfig? _config;
  AuditPage? _audit;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _refresh();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = context.read<AppState>().api;
      final (cfg, aud) = await (api.getIntegrationConfig(), api.listAudit())
          .wait;
      if (!mounted) return;
      setState(() {
        _config = cfg;
        _audit = aud;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _refreshAudit() async {
    try {
      final aud = await context.read<AppState>().api.listAudit();
      if (!mounted) return;
      setState(() => _audit = aud);
    } catch (_) {
      // Non-fatal; the banner on the main screen already shows hard errors.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Integration'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(icon: Icon(Icons.cable_outlined), text: 'Connection'),
            Tab(icon: Icon(Icons.swap_horiz), text: 'Mappings'),
            Tab(icon: Icon(Icons.fact_check_outlined), text: 'Audit'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: ErrorBanner(message: _error!),
                  ),
                Expanded(
                  child: TabBarView(
                    controller: _tabs,
                    children: [
                      _ConnectionTab(
                        connection: _config?.surreal,
                        onSaved: _refresh,
                      ),
                      _MappingsTab(
                        config: _config,
                        onChanged: _refresh,
                        onRunComplete: _refreshAudit,
                      ),
                      _AuditTab(audit: _audit, onChanged: _refreshAudit),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

// ─── Connection tab ─────────────────────────────────────────────────────

class _ConnectionTab extends StatefulWidget {
  const _ConnectionTab({required this.connection, required this.onSaved});
  final SurrealConnection? connection;
  final VoidCallback onSaved;

  @override
  State<_ConnectionTab> createState() => _ConnectionTabState();
}

class _ConnectionTabState extends State<_ConnectionTab> {
  late final TextEditingController _endpoint;
  late final TextEditingController _ns;
  late final TextEditingController _db;
  late final TextEditingController _user;
  late final TextEditingController _pass;
  bool _busy = false;
  String? _testResult;
  bool _testOk = false;

  @override
  void initState() {
    super.initState();
    final c = widget.connection;
    _endpoint = TextEditingController(text: c?.endpoint ?? 'http://localhost:8000');
    _ns = TextEditingController(text: c?.namespace ?? 'sap');
    _db = TextEditingController(text: c?.database ?? 'gateway');
    _user = TextEditingController(text: c?.username ?? 'root');
    _pass = TextEditingController();
  }

  @override
  void dispose() {
    _endpoint.dispose();
    _ns.dispose();
    _db.dispose();
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await context.read<AppState>().api.updateSurrealConfig(
            endpoint: _endpoint.text.trim().replaceAll(RegExp(r'/+$'), ''),
            namespace: _ns.text.trim(),
            database: _db.text.trim(),
            username: _user.text.trim(),
            password: _pass.text,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('SurrealDB connection saved')),
      );
      _pass.clear();
      widget.onSaved();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Save failed: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _test() async {
    setState(() {
      _busy = true;
      _testResult = null;
    });
    try {
      final res = await context.read<AppState>().api.testSurrealConnection();
      if (!mounted) return;
      setState(() {
        _testOk = res['ok'] == true;
        _testResult = res['detail']?.toString() ?? '';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _testOk = false;
        _testResult = e.toString();
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.connection;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('SurrealDB', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          'Where to read/write the mirrored data. The gateway authenticates '
          'with Basic auth and sends NS/DB headers on every request.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _endpoint,
          decoration: const InputDecoration(
            labelText: 'Endpoint URL',
            helperText: 'e.g. http://my-server:8000',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.public),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _ns,
                decoration: const InputDecoration(
                  labelText: 'Namespace',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _db,
                decoration: const InputDecoration(
                  labelText: 'Database',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _user,
                decoration: const InputDecoration(
                  labelText: 'Username',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person_outline),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _pass,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'Password',
                  helperText: c?.passwordSet == true
                      ? 'A password is already stored. Leave blank to keep it.'
                      : 'Not yet set',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.lock_outline),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 12,
          children: [
            FilledButton.icon(
              onPressed: _busy ? null : _save,
              icon: const Icon(Icons.save_outlined),
              label: const Text('Save'),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : _test,
              icon: const Icon(Icons.bolt_outlined),
              label: const Text('Test connection'),
            ),
          ],
        ),
        if (_testResult != null) ...[
          const SizedBox(height: 16),
          Card(
            color: _testOk
                ? Colors.green.withOpacity( 0.12)
                : Theme.of(context).colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(_testOk ? Icons.check_circle : Icons.error_outline),
                  const SizedBox(width: 12),
                  Expanded(child: Text(_testResult!)),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ─── Mappings tab ───────────────────────────────────────────────────────

class _MappingsTab extends StatelessWidget {
  const _MappingsTab({
    required this.config,
    required this.onChanged,
    required this.onRunComplete,
  });

  final IntegrationConfig? config;
  final VoidCallback onChanged;
  final VoidCallback onRunComplete;

  @override
  Widget build(BuildContext context) {
    final mappings = config?.mappings ?? const <MappingConfig>[];
    return Stack(
      children: [
        if (mappings.isEmpty)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(40),
              child: Text(
                'No mappings yet.\nTap + to wire a SAP collection up to a SurrealDB table.',
                textAlign: TextAlign.center,
              ),
            ),
          )
        else
          ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            itemCount: mappings.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (ctx, i) => _MappingCard(
              mapping: mappings[i],
              onChanged: onChanged,
              onRunComplete: onRunComplete,
            ),
          ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton.extended(
            onPressed: () async {
              final created = await _editMapping(context, null);
              if (created == true) onChanged();
            },
            icon: const Icon(Icons.add),
            label: const Text('Add mapping'),
          ),
        ),
      ],
    );
  }
}

class _MappingCard extends StatefulWidget {
  const _MappingCard({
    required this.mapping,
    required this.onChanged,
    required this.onRunComplete,
  });

  final MappingConfig mapping;
  final VoidCallback onChanged;
  final VoidCallback onRunComplete;

  @override
  State<_MappingCard> createState() => _MappingCardState();
}

class _MappingCardState extends State<_MappingCard> {
  bool _busy = false;
  SyncResult? _lastResult;

  Future<void> _run(bool isPull, {required bool dryRun}) async {
    setState(() {
      _busy = true;
      _lastResult = null;
    });
    try {
      final api = context.read<AppState>().api;
      final res = isPull
          ? await api.runPull(widget.mapping.collection, dryRun: dryRun)
          : await api.runPush(widget.mapping.collection, dryRun: dryRun);
      if (!mounted) return;
      setState(() => _lastResult = res);
      widget.onRunComplete();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Run failed: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete mapping "${widget.mapping.collection}"?'),
        content: const Text('This removes the mapping. Data is untouched.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton.tonal(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await context
          .read<AppState>()
          .api
          .deleteMapping(widget.mapping.collection);
      widget.onChanged();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Delete failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.mapping;
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('SAP: ${m.collection}',
                          style: theme.textTheme.titleMedium),
                      const SizedBox(height: 2),
                      Text('Surreal: ${m.table}',
                          style: theme.textTheme.bodyMedium),
                    ],
                  ),
                ),
                _DirectionChip(direction: m.direction),
                const SizedBox(width: 4),
                PopupMenuButton<String>(
                  onSelected: (v) async {
                    if (v == 'edit') {
                      final changed = await _editMapping(context, m);
                      if (changed == true) widget.onChanged();
                    } else if (v == 'delete') {
                      await _delete();
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('Edit')),
                    PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
              ],
            ),
            if (m.pushFilter.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                children: [
                  const Icon(Icons.filter_alt_outlined, size: 16),
                  for (final entry in m.pushFilter.entries)
                    Chip(
                      label: Text('${entry.key} = ${entry.value}'),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: !m.canPull || _busy
                      ? null
                      : () => _run(true, dryRun: false),
                  icon: const Icon(Icons.download),
                  label: const Text('Pull SAP -> Surreal'),
                ),
                OutlinedButton.icon(
                  onPressed: !m.canPull || _busy
                      ? null
                      : () => _run(true, dryRun: true),
                  icon: const Icon(Icons.preview_outlined),
                  label: const Text('Dry-run pull'),
                ),
                FilledButton.icon(
                  onPressed: !m.canPush || _busy
                      ? null
                      : () => _run(false, dryRun: false),
                  icon: const Icon(Icons.upload),
                  label: const Text('Push Surreal -> SAP'),
                ),
                OutlinedButton.icon(
                  onPressed: !m.canPush || _busy
                      ? null
                      : () => _run(false, dryRun: true),
                  icon: const Icon(Icons.preview_outlined),
                  label: const Text('Dry-run push'),
                ),
              ],
            ),
            if (_busy) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
            if (_lastResult != null) ...[
              const SizedBox(height: 12),
              _RunSummary(result: _lastResult!),
            ],
          ],
        ),
      ),
    );
  }
}

class _DirectionChip extends StatelessWidget {
  const _DirectionChip({required this.direction});
  final String direction;

  @override
  Widget build(BuildContext context) {
    final (label, icon, color) = switch (direction) {
      'inbound' => ('Pull only', Icons.arrow_downward, Colors.blue),
      'outbound' => ('Push only', Icons.arrow_upward, Colors.orange),
      _ => ('Bidirectional', Icons.swap_vert, Colors.green),
    };
    return Chip(
      avatar: Icon(icon, size: 16, color: color),
      label: Text(label),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _RunSummary extends StatelessWidget {
  const _RunSummary({required this.result});
  final SyncResult result;

  @override
  Widget build(BuildContext context) {
    final ok = result.status == 'success' || result.status == 'dry-run';
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ok ? Colors.green.withOpacity( 0.10) : colors.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(ok ? Icons.check_circle_outline : Icons.error_outline,
                  color: ok ? Colors.green : colors.onErrorContainer),
              const SizedBox(width: 8),
              Text(
                  '${result.direction.toUpperCase()} '
                  '${result.dryRun ? "(dry-run) " : ""}'
                  '${result.status}',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              const Spacer(),
              Text('${result.durationMs} ms',
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 12,
            children: [
              _stat('scanned', result.rowsScanned),
              _stat('created', result.rowsCreated),
              _stat('updated', result.rowsUpdated),
              if (result.rowsSkipped > 0) _stat('skipped', result.rowsSkipped),
              if (result.rowsFailed > 0) _stat('failed', result.rowsFailed),
            ],
          ),
          if (result.error != null) ...[
            const SizedBox(height: 8),
            Text(result.error!,
                style: TextStyle(color: colors.onErrorContainer)),
          ],
          if (result.errors.isNotEmpty) ...[
            const SizedBox(height: 6),
            for (final e in result.errors)
              Text('• $e', style: const TextStyle(fontSize: 12)),
          ],
        ],
      ),
    );
  }

  Widget _stat(String label, int v) =>
      Text('$label: $v', style: const TextStyle(fontSize: 13));
}

Future<bool?> _editMapping(BuildContext context, MappingConfig? initial) async {
  return showDialog<bool>(
    context: context,
    builder: (_) => _MappingEditor(initial: initial),
  );
}

class _MappingEditor extends StatefulWidget {
  const _MappingEditor({this.initial});
  final MappingConfig? initial;

  @override
  State<_MappingEditor> createState() => _MappingEditorState();
}

class _MappingEditorState extends State<_MappingEditor> {
  late final TextEditingController _collection;
  late final TextEditingController _table;
  late String _direction;
  late final TextEditingController _filter;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final m = widget.initial;
    _collection = TextEditingController(text: m?.collection ?? '');
    _table = TextEditingController(text: m?.table ?? '');
    _direction = m?.direction ?? 'inbound';
    _filter = TextEditingController(
      text: m?.pushFilter.entries.map((e) => '${e.key}=${e.value}').join(',') ??
          '',
    );
  }

  @override
  void dispose() {
    _collection.dispose();
    _table.dispose();
    _filter.dispose();
    super.dispose();
  }

  Map<String, String> _parseFilter() {
    final out = <String, String>{};
    for (final part in _filter.text.split(',')) {
      final t = part.trim();
      if (t.isEmpty) continue;
      final eq = t.indexOf('=');
      if (eq < 0) continue;
      out[t.substring(0, eq).trim()] = t.substring(eq + 1).trim();
    }
    return out;
  }

  Future<void> _save() async {
    if (_collection.text.trim().isEmpty || _table.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Collection and table are required')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await context.read<AppState>().api.upsertMapping(MappingConfig(
            collection: _collection.text.trim(),
            table: _table.text.trim(),
            direction: _direction,
            pushFilter: _parseFilter(),
          ));
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Save failed: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.initial != null;
    return AlertDialog(
      title: Text(editing ? 'Edit mapping' : 'New mapping'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _collection,
              enabled: !editing,
              decoration: const InputDecoration(
                labelText: 'SAP collection',
                helperText: 'e.g. expenses, employees, absences',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _table,
              decoration: const InputDecoration(
                labelText: 'SurrealDB table',
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _direction,
              decoration: const InputDecoration(labelText: 'Direction'),
              items: [
                for (final d in MappingConfig.directions)
                  DropdownMenuItem(value: d, child: Text(d)),
              ],
              onChanged: (v) =>
                  setState(() => _direction = v ?? _direction),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _filter,
              decoration: const InputDecoration(
                labelText: 'Push filter (optional)',
                helperText: 'Comma-separated key=value, e.g. Status=SUBMITTED',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}

// ─── Audit tab ──────────────────────────────────────────────────────────

class _AuditTab extends StatelessWidget {
  const _AuditTab({required this.audit, required this.onChanged});
  final AuditPage? audit;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final events = audit?.events ?? const <AuditEntry>[];
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Text(
                  '${audit?.total ?? 0} event${(audit?.total ?? 0) == 1 ? '' : 's'} '
                  '(showing ${events.length})',
                  style: Theme.of(context).textTheme.bodySmall),
              const Spacer(),
              TextButton.icon(
                onPressed: events.isEmpty
                    ? null
                    : () async {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Clear audit log?'),
                            content: const Text(
                                'Removes all audit events. This cannot be undone.'),
                            actions: [
                              TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text('Cancel')),
                              FilledButton.tonal(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: const Text('Clear')),
                            ],
                          ),
                        );
                        if (ok == true) {
                          await context.read<AppState>().api.clearAudit();
                          onChanged();
                        }
                      },
                icon: const Icon(Icons.delete_sweep_outlined),
                label: const Text('Clear'),
              ),
            ],
          ),
        ),
        Expanded(
          child: events.isEmpty
              ? const Center(child: Text('No audit events yet'))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  itemCount: events.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) => _AuditTile(entry: events[i]),
                ),
        ),
      ],
    );
  }
}

class _AuditTile extends StatelessWidget {
  const _AuditTile({required this.entry});
  final AuditEntry entry;

  @override
  Widget build(BuildContext context) {
    final color = switch (entry.status) {
      'success' => Colors.green,
      'dry-run' => Colors.blueGrey,
      'error' => Theme.of(context).colorScheme.error,
      _ => Colors.grey,
    };
    final stats = <String>[
      if (entry.rowsScanned != null) 'scanned ${entry.rowsScanned}',
      if ((entry.rowsCreated ?? 0) > 0) 'created ${entry.rowsCreated}',
      if ((entry.rowsUpdated ?? 0) > 0) 'updated ${entry.rowsUpdated}',
      if ((entry.rowsSkipped ?? 0) > 0) 'skipped ${entry.rowsSkipped}',
      if ((entry.rowsFailed ?? 0) > 0) 'failed ${entry.rowsFailed}',
    ];
    return ListTile(
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: color.withOpacity( 0.15),
        child: Icon(_iconFor(entry.action), size: 18, color: color),
      ),
      title: Row(
        children: [
          Text(entry.action,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          if (entry.collection != null) ...[
            const SizedBox(width: 6),
            Text(entry.collection!,
                style: Theme.of(context).textTheme.bodySmall),
          ],
          if (entry.dryRun) ...[
            const SizedBox(width: 6),
            const Chip(
                label: Text('dry-run'),
                visualDensity: VisualDensity.compact),
          ],
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
              '${entry.timestamp.toLocal().toString().split('.').first}  •  '
              '${entry.status}'
              '${entry.durationMs != null ? '  •  ${entry.durationMs} ms' : ''}',
              style: Theme.of(context).textTheme.bodySmall),
          if (stats.isNotEmpty)
            Text(stats.join('  •  '),
                style: Theme.of(context).textTheme.bodySmall),
          if (entry.message != null)
            Text(entry.message!,
                style: TextStyle(color: color, fontSize: 12)),
        ],
      ),
    );
  }

  IconData _iconFor(String action) => switch (action) {
        'pull' => Icons.download,
        'push' => Icons.upload,
        'connection.test' => Icons.bolt_outlined,
        'config.surreal' => Icons.cable_outlined,
        'config.mapping' => Icons.swap_horiz,
        _ => Icons.bookmark_border,
      };
}
