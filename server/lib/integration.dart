import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';

import 'models.dart';
import 'store.dart';

/// SAP <-> SurrealDB integration layer.
///
/// Owns three things:
///
/// 1. **SurrealDB connection config** + per-collection **mappings**
///    (persisted to disk so they survive restarts).
/// 2. A **sync engine** with two directions — `pull` (SAP -> Surreal)
///    and `push` (Surreal -> SAP). SAP data is read/written via the
///    in-process [GatewayStore] (since this server is the SAP gateway
///    mock); SurrealDB is reached via its HTTP REST API.
/// 3. A persistent **audit log** of every sync run, config change and
///    connection test.
///
/// Mounted at `/api/v1/integration/`:
///
///   GET    /config                       config + mappings
///   PUT    /config/surreal               update Surreal connection
///   PUT    /config/mappings/{collection} upsert mapping
///   DELETE /config/mappings/{collection} remove mapping
///   POST   /test-connection              probe Surreal connectivity
///   POST   /pull/{collection}?dryRun=    run pull SAP -> Surreal
///   POST   /push/{collection}?dryRun=    run push Surreal -> SAP
///   GET    /audit                        list audit events (paged)
///   DELETE /audit                        clear audit log
class IntegrationHandler {
  IntegrationHandler(this.store, this.config, this.audit, this.collectionFor);

  final GatewayStore store;
  final IntegrationConfigStore config;
  final AuditStore audit;

  /// Resolves a public REST collection name to its underlying
  /// (EntitySet, EntityType). Provided by the server so we don't
  /// duplicate the lookup logic that lives in `rest.dart`.
  final (EntitySet, EntityType)? Function(String collection) collectionFor;

  Handler get handler => (Request req) async {
        final segs = [
          for (final s in req.url.pathSegments)
            if (s.isNotEmpty) s,
        ];
        try {
          return await _route(req, segs);
        } catch (e, st) {
          return _err(500, 'Integration error: $e\n$st');
        }
      };

  Future<Response> _route(Request req, List<String> segs) async {
    if (segs.isEmpty) return _err(404, 'No route');
    final head = segs[0];

    if (head == 'config' && segs.length == 1 && req.method == 'GET') {
      return _json(config.toJson());
    }
    if (head == 'config' &&
        segs.length == 2 &&
        segs[1] == 'surreal' &&
        req.method == 'PUT') {
      final body = await _readBody(req);
      if (body == null) return _err(400, 'JSON body required');
      config.updateSurreal(SurrealConfig.fromJson(body));
      await config.save();
      audit.record(AuditEvent.now(
        action: 'config.surreal',
        status: 'success',
        message: 'Updated SurrealDB connection to ${config.surreal.endpoint}',
      ));
      await audit.save();
      return _json(config.surreal.toJson());
    }
    if (head == 'config' &&
        segs.length == 3 &&
        segs[1] == 'mappings' &&
        req.method == 'PUT') {
      final body = await _readBody(req);
      if (body == null) return _err(400, 'JSON body required');
      final m = Mapping.fromJson({...body, 'collection': segs[2]});
      config.upsertMapping(m);
      await config.save();
      audit.record(AuditEvent.now(
        action: 'config.mapping',
        collection: m.collection,
        status: 'success',
        message: 'Mapping ${m.collection} -> ${m.table} (${m.direction})',
      ));
      await audit.save();
      return _json(m.toJson());
    }
    if (head == 'config' &&
        segs.length == 3 &&
        segs[1] == 'mappings' &&
        req.method == 'DELETE') {
      config.removeMapping(segs[2]);
      await config.save();
      return Response(204);
    }

    if (head == 'test-connection' && req.method == 'POST') {
      final result = await _testConnection();
      audit.record(AuditEvent.now(
        action: 'connection.test',
        status: result['ok'] == true ? 'success' : 'error',
        message: result['detail']?.toString() ?? '',
      ));
      await audit.save();
      return _json(result);
    }

    if (head == 'pull' && segs.length == 2 && req.method == 'POST') {
      final dryRun = req.url.queryParameters['dryRun'] == 'true';
      return _json(await _pull(segs[1], dryRun: dryRun));
    }
    if (head == 'push' && segs.length == 2 && req.method == 'POST') {
      final dryRun = req.url.queryParameters['dryRun'] == 'true';
      return _json(await _push(segs[1], dryRun: dryRun));
    }

    if (head == 'audit' && segs.length == 1) {
      if (req.method == 'GET') {
        final qp = req.url.queryParameters;
        final limit = int.tryParse(qp['limit'] ?? '') ?? 100;
        final action = qp['action'];
        final collection = qp['collection'];
        var events = audit.events.reversed.toList();
        if (action != null && action.isNotEmpty) {
          events = events.where((e) => e.action == action).toList();
        }
        if (collection != null && collection.isNotEmpty) {
          events = events.where((e) => e.collection == collection).toList();
        }
        if (limit > 0 && events.length > limit) {
          events = events.take(limit).toList();
        }
        return _json({
          'total': audit.events.length,
          'events': events.map((e) => e.toJson()).toList(),
        });
      }
      if (req.method == 'DELETE') {
        audit.clear();
        await audit.save();
        return Response(204);
      }
    }

    return _err(404, 'No route for /${segs.join('/')}');
  }

  // ─── Sync engine ──────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _pull(String collection,
      {required bool dryRun}) async {
    final mapping = config.mappingFor(collection);
    if (mapping == null) {
      return _failRun('pull', collection, dryRun, 'No mapping configured');
    }
    if (mapping.direction == 'outbound') {
      return _failRun('pull', collection, dryRun,
          'Mapping direction "${mapping.direction}" forbids pull');
    }
    final resolved = collectionFor(collection);
    if (resolved == null) {
      return _failRun(
          'pull', collection, dryRun, 'Unknown SAP collection "$collection"');
    }
    final (es, et) = resolved;

    final sw = Stopwatch()..start();
    var created = 0;
    var updated = 0;
    var failed = 0;
    final errors = <String>[];

    final client = SurrealClient(config.surreal);
    for (final row in es.rows) {
      final id = _idFor(et, row);
      final body = _applyFieldMap(row, mapping.fieldMap);
      if (dryRun) {
        created++;
        continue;
      }
      try {
        final existed = await client.exists(mapping.table, id);
        await client.upsert(mapping.table, id, body);
        if (existed) {
          updated++;
        } else {
          created++;
        }
      } catch (e) {
        failed++;
        errors.add('$id: $e');
      }
    }
    client.close();
    sw.stop();

    final status = failed == 0 ? (dryRun ? 'dry-run' : 'success') : 'error';
    audit.record(AuditEvent.now(
      action: 'pull',
      collection: collection,
      status: status,
      dryRun: dryRun,
      rowsScanned: es.rows.length,
      rowsCreated: created,
      rowsUpdated: updated,
      rowsFailed: failed,
      durationMs: sw.elapsedMilliseconds,
      message: errors.isEmpty ? null : errors.take(3).join('; '),
    ));
    await audit.save();
    return {
      'direction': 'pull',
      'collection': collection,
      'dryRun': dryRun,
      'status': status,
      'rowsScanned': es.rows.length,
      'rowsCreated': created,
      'rowsUpdated': updated,
      'rowsFailed': failed,
      'durationMs': sw.elapsedMilliseconds,
      'errors': errors,
    };
  }

  Future<Map<String, dynamic>> _push(String collection,
      {required bool dryRun}) async {
    final mapping = config.mappingFor(collection);
    if (mapping == null) {
      return _failRun('push', collection, dryRun, 'No mapping configured');
    }
    if (mapping.direction == 'inbound') {
      return _failRun('push', collection, dryRun,
          'Mapping direction "${mapping.direction}" forbids push');
    }
    final resolved = collectionFor(collection);
    if (resolved == null) {
      return _failRun(
          'push', collection, dryRun, 'Unknown SAP collection "$collection"');
    }
    final (es, et) = resolved;

    final sw = Stopwatch()..start();
    var created = 0;
    var updated = 0;
    var skipped = 0;
    var failed = 0;
    final errors = <String>[];

    final client = SurrealClient(config.surreal);
    final List<Map<String, dynamic>> surrealRows;
    try {
      surrealRows = await client.selectAll(mapping.table);
    } catch (e) {
      client.close();
      sw.stop();
      audit.record(AuditEvent.now(
        action: 'push',
        collection: collection,
        status: 'error',
        dryRun: dryRun,
        durationMs: sw.elapsedMilliseconds,
        message: 'Surreal SELECT failed: $e',
      ));
      await audit.save();
      return {
        'direction': 'push',
        'collection': collection,
        'dryRun': dryRun,
        'status': 'error',
        'error': 'Surreal SELECT failed: $e',
      };
    }

    final inverse = _inverseFieldMap(mapping.fieldMap);
    for (final raw in surrealRows) {
      // Surface a clean row in SAP shape — strip the synthetic `id` column.
      final mapped = _applyFieldMap(raw, inverse);
      mapped.remove('id');
      if (!_matchesFilter(mapped, mapping.pushFilter)) {
        skipped++;
        continue;
      }
      // Backfill key from id if missing.
      if (et.keys.length == 1) {
        final k = et.keys.first;
        if ((mapped[k] == null || mapped[k].toString().isEmpty) &&
            raw['id'] != null) {
          mapped[k] = _stripTablePrefix(raw['id'].toString(), mapping.table);
        }
      }
      final missingKey = et.keys
          .where((k) => mapped[k] == null || mapped[k].toString().isEmpty)
          .toList();
      if (missingKey.isNotEmpty) {
        failed++;
        errors.add('${raw['id']}: missing key field(s) $missingKey');
        continue;
      }
      if (dryRun) {
        if (_findRow(es, et, mapped) != null) {
          updated++;
        } else {
          created++;
        }
        continue;
      }
      final existing = _findRow(es, et, mapped);
      if (existing == null) {
        es.rows.add(Map<String, dynamic>.from(mapped));
        created++;
      } else {
        existing
          ..addAll(mapped)
          ..addAll({for (final k in et.keys) k: mapped[k]});
        updated++;
      }
    }
    if (!dryRun && (created > 0 || updated > 0)) {
      await store.save();
    }
    client.close();
    sw.stop();

    final status = failed == 0 ? (dryRun ? 'dry-run' : 'success') : 'error';
    audit.record(AuditEvent.now(
      action: 'push',
      collection: collection,
      status: status,
      dryRun: dryRun,
      rowsScanned: surrealRows.length,
      rowsCreated: created,
      rowsUpdated: updated,
      rowsSkipped: skipped,
      rowsFailed: failed,
      durationMs: sw.elapsedMilliseconds,
      message: errors.isEmpty ? null : errors.take(3).join('; '),
    ));
    await audit.save();
    return {
      'direction': 'push',
      'collection': collection,
      'dryRun': dryRun,
      'status': status,
      'rowsScanned': surrealRows.length,
      'rowsCreated': created,
      'rowsUpdated': updated,
      'rowsSkipped': skipped,
      'rowsFailed': failed,
      'durationMs': sw.elapsedMilliseconds,
      'errors': errors,
    };
  }

  Future<Map<String, dynamic>> _testConnection() async {
    final client = SurrealClient(config.surreal);
    final sw = Stopwatch()..start();
    try {
      final ver = await client.version();
      sw.stop();
      return {
        'ok': true,
        'endpoint': config.surreal.endpoint,
        'namespace': config.surreal.namespace,
        'database': config.surreal.database,
        'version': ver,
        'durationMs': sw.elapsedMilliseconds,
        'detail': 'Connected to SurrealDB $ver',
      };
    } catch (e) {
      sw.stop();
      return {
        'ok': false,
        'endpoint': config.surreal.endpoint,
        'durationMs': sw.elapsedMilliseconds,
        'detail': '$e',
      };
    } finally {
      client.close();
    }
  }

  // ─── helpers ─────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _failRun(
      String action, String collection, bool dryRun, String reason) async {
    audit.record(AuditEvent.now(
      action: action,
      collection: collection,
      status: 'error',
      dryRun: dryRun,
      message: reason,
    ));
    await audit.save();
    return {
      'direction': action,
      'collection': collection,
      'dryRun': dryRun,
      'status': 'error',
      'error': reason,
    };
  }

  String _idFor(EntityType et, Map<String, dynamic> row) {
    if (et.keys.length == 1) return row[et.keys.first]?.toString() ?? '';
    return et.keys.map((k) => row[k]?.toString() ?? '').join(',');
  }

  Map<String, dynamic>? _findRow(
      EntitySet es, EntityType et, Map<String, dynamic> mapped) {
    for (final row in es.rows) {
      var ok = true;
      for (final k in et.keys) {
        if (row[k]?.toString() != mapped[k]?.toString()) {
          ok = false;
          break;
        }
      }
      if (ok) return row;
    }
    return null;
  }

  Map<String, dynamic> _applyFieldMap(
      Map<String, dynamic> row, Map<String, String> fieldMap) {
    if (fieldMap.isEmpty) return Map<String, dynamic>.from(row);
    final out = <String, dynamic>{};
    for (final entry in row.entries) {
      final target = fieldMap[entry.key] ?? entry.key;
      out[target] = entry.value;
    }
    return out;
  }

  Map<String, String> _inverseFieldMap(Map<String, String> fm) {
    final out = <String, String>{};
    for (final entry in fm.entries) {
      out[entry.value] = entry.key;
    }
    return out;
  }

  String _stripTablePrefix(String surrealId, String table) {
    final prefix = '$table:';
    if (surrealId.startsWith(prefix)) {
      var rest = surrealId.substring(prefix.length);
      // Surreal often returns id surrounded by ⟨ ⟩ when the segment
      // contains unusual characters. Strip those.
      if (rest.startsWith('⟨') && rest.endsWith('⟩')) {
        rest = rest.substring(1, rest.length - 1);
      }
      return rest;
    }
    return surrealId;
  }

  bool _matchesFilter(Map<String, dynamic> row, Map<String, String> filter) {
    if (filter.isEmpty) return true;
    for (final entry in filter.entries) {
      if (row[entry.key]?.toString() != entry.value) return false;
    }
    return true;
  }

  Future<Map<String, dynamic>?> _readBody(Request req) async {
    final raw = await req.readAsString();
    if (raw.isEmpty) return null;
    final decoded = jsonDecode(raw);
    return decoded is Map<String, dynamic> ? decoded : null;
  }

  Response _json(Object body, {int status = 200}) => Response(
        status,
        body: jsonEncode(body),
        headers: const {'content-type': 'application/json; charset=utf-8'},
      );

  Response _err(int status, String msg) => Response(
        status,
        body: jsonEncode({'error': msg}),
        headers: const {'content-type': 'application/json; charset=utf-8'},
      );
}

// ─── Config ─────────────────────────────────────────────────────────────

class IntegrationConfigStore {
  IntegrationConfigStore(this.path);

  final String path;
  SurrealConfig surreal = const SurrealConfig.empty();
  final List<Mapping> mappings = <Mapping>[];

  Future<void> load() async {
    final file = File(path);
    if (!await file.exists()) {
      mappings.addAll(_defaultMappings());
      await save();
      return;
    }
    final decoded = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    surreal = SurrealConfig.fromJson(
        (decoded['surreal'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{});
    mappings
      ..clear()
      ..addAll(((decoded['mappings'] as List?) ?? const [])
          .cast<Map<String, dynamic>>()
          .map(Mapping.fromJson));
  }

  Future<void> save() async {
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(toJson()),
    );
  }

  void updateSurreal(SurrealConfig c) => surreal = c;

  Mapping? mappingFor(String collection) {
    for (final m in mappings) {
      if (m.collection == collection) return m;
    }
    return null;
  }

  void upsertMapping(Mapping m) {
    final i = mappings.indexWhere((x) => x.collection == m.collection);
    if (i < 0) {
      mappings.add(m);
    } else {
      mappings[i] = m;
    }
  }

  void removeMapping(String collection) {
    mappings.removeWhere((m) => m.collection == collection);
  }

  Map<String, dynamic> toJson() => {
        'surreal': surreal.toJson(),
        'mappings': mappings.map((m) => m.toJson()).toList(),
      };

  List<Mapping> _defaultMappings() => [
        Mapping(
          collection: 'expenses',
          table: 'expenses',
          direction: 'both',
          pushFilter: const {'Status': 'SUBMITTED'},
        ),
        Mapping(collection: 'customers', table: 'customers', direction: 'inbound'),
        Mapping(collection: 'materials', table: 'materials', direction: 'inbound'),
        Mapping(collection: 'vendors', table: 'vendors', direction: 'inbound'),
      ];
}

class SurrealConfig {
  const SurrealConfig({
    required this.endpoint,
    required this.namespace,
    required this.database,
    required this.username,
    required this.password,
  });

  const SurrealConfig.empty()
      : endpoint = '',
        namespace = '',
        database = '',
        username = '',
        password = '';

  final String endpoint; // e.g. http://localhost:8000
  final String namespace;
  final String database;
  final String username;
  final String password;

  Map<String, dynamic> toJson() => {
        'endpoint': endpoint,
        'namespace': namespace,
        'database': database,
        'username': username,
        // password redacted on read-back; clients must POST it explicitly
        'passwordSet': password.isNotEmpty,
      };

  factory SurrealConfig.fromJson(Map<String, dynamic> json) => SurrealConfig(
        endpoint: (json['endpoint'] as String?) ?? '',
        namespace: (json['namespace'] as String?) ?? '',
        database: (json['database'] as String?) ?? '',
        username: (json['username'] as String?) ?? '',
        password: (json['password'] as String?) ?? '',
      );
}

class Mapping {
  Mapping({
    required this.collection,
    required this.table,
    required this.direction,
    Map<String, String>? fieldMap,
    Map<String, String>? pushFilter,
  })  : fieldMap = fieldMap ?? const {},
        pushFilter = pushFilter ?? const {};

  /// SAP REST collection name (e.g. `expenses`).
  final String collection;

  /// SurrealDB table name (e.g. `expenses`).
  final String table;

  /// `inbound` (SAP -> Surreal), `outbound` (Surreal -> SAP) or `both`.
  final String direction;

  /// Optional rename map: { sapField: surrealField }. Applied on pull,
  /// inverted on push. Empty map = identity (1:1 field names).
  final Map<String, String> fieldMap;

  /// Equality predicate applied to a Surreal record before push. Lets
  /// you e.g. only post expenses with Status=SUBMITTED.
  final Map<String, String> pushFilter;

  Map<String, dynamic> toJson() => {
        'collection': collection,
        'table': table,
        'direction': direction,
        'fieldMap': fieldMap,
        'pushFilter': pushFilter,
      };

  factory Mapping.fromJson(Map<String, dynamic> json) => Mapping(
        collection: json['collection'] as String,
        table: (json['table'] as String?) ?? json['collection'] as String,
        direction: (json['direction'] as String?) ?? 'inbound',
        fieldMap: ((json['fieldMap'] as Map?) ?? const {})
            .map((k, v) => MapEntry(k.toString(), v.toString())),
        pushFilter: ((json['pushFilter'] as Map?) ?? const {})
            .map((k, v) => MapEntry(k.toString(), v.toString())),
      );
}

// ─── Audit log ──────────────────────────────────────────────────────────

class AuditStore {
  AuditStore(this.path);

  final String path;
  final List<AuditEvent> events = <AuditEvent>[];

  static const int _maxEvents = 5000;

  Future<void> load() async {
    final file = File(path);
    if (!await file.exists()) return;
    final list = jsonDecode(await file.readAsString()) as List;
    events
      ..clear()
      ..addAll(list.cast<Map<String, dynamic>>().map(AuditEvent.fromJson));
  }

  Future<void> save() async {
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode(events.map((e) => e.toJson()).toList()),
    );
  }

  void record(AuditEvent e) {
    events.add(e);
    if (events.length > _maxEvents) {
      events.removeRange(0, events.length - _maxEvents);
    }
  }

  void clear() => events.clear();
}

class AuditEvent {
  AuditEvent({
    required this.id,
    required this.timestamp,
    required this.action,
    this.collection,
    required this.status,
    this.dryRun = false,
    this.rowsScanned,
    this.rowsCreated,
    this.rowsUpdated,
    this.rowsSkipped,
    this.rowsFailed,
    this.durationMs,
    this.message,
  });

  factory AuditEvent.now({
    required String action,
    String? collection,
    required String status,
    bool dryRun = false,
    int? rowsScanned,
    int? rowsCreated,
    int? rowsUpdated,
    int? rowsSkipped,
    int? rowsFailed,
    int? durationMs,
    String? message,
  }) {
    final now = DateTime.now().toUtc();
    return AuditEvent(
      id: '${now.microsecondsSinceEpoch}',
      timestamp: now,
      action: action,
      collection: collection,
      status: status,
      dryRun: dryRun,
      rowsScanned: rowsScanned,
      rowsCreated: rowsCreated,
      rowsUpdated: rowsUpdated,
      rowsSkipped: rowsSkipped,
      rowsFailed: rowsFailed,
      durationMs: durationMs,
      message: message,
    );
  }

  final String id;
  final DateTime timestamp;
  final String action;
  final String? collection;
  final String status;
  final bool dryRun;
  final int? rowsScanned;
  final int? rowsCreated;
  final int? rowsUpdated;
  final int? rowsSkipped;
  final int? rowsFailed;
  final int? durationMs;
  final String? message;

  Map<String, dynamic> toJson() => {
        'id': id,
        'timestamp': timestamp.toIso8601String(),
        'action': action,
        if (collection != null) 'collection': collection,
        'status': status,
        'dryRun': dryRun,
        if (rowsScanned != null) 'rowsScanned': rowsScanned,
        if (rowsCreated != null) 'rowsCreated': rowsCreated,
        if (rowsUpdated != null) 'rowsUpdated': rowsUpdated,
        if (rowsSkipped != null) 'rowsSkipped': rowsSkipped,
        if (rowsFailed != null) 'rowsFailed': rowsFailed,
        if (durationMs != null) 'durationMs': durationMs,
        if (message != null) 'message': message,
      };

  factory AuditEvent.fromJson(Map<String, dynamic> json) => AuditEvent(
        id: json['id'] as String,
        timestamp: DateTime.parse(json['timestamp'] as String),
        action: json['action'] as String,
        collection: json['collection'] as String?,
        status: json['status'] as String,
        dryRun: (json['dryRun'] as bool?) ?? false,
        rowsScanned: json['rowsScanned'] as int?,
        rowsCreated: json['rowsCreated'] as int?,
        rowsUpdated: json['rowsUpdated'] as int?,
        rowsSkipped: json['rowsSkipped'] as int?,
        rowsFailed: json['rowsFailed'] as int?,
        durationMs: json['durationMs'] as int?,
        message: json['message'] as String?,
      );
}

// ─── SurrealDB HTTP client ─────────────────────────────────────────────

/// Thin client over SurrealDB's HTTP API. Uses Basic auth + ns/db
/// headers, which is the standard root/namespace/database setup. For
/// scoped auth you'd swap this for `/signin` and a Bearer token, but
/// most server-to-server SurrealDB deployments use Basic.
class SurrealClient {
  SurrealClient(this.config) : _client = HttpClient() {
    _client.connectionTimeout = const Duration(seconds: 10);
  }

  final SurrealConfig config;
  final HttpClient _client;

  void close() => _client.close(force: true);

  Future<String> version() async {
    final req = await _client.getUrl(Uri.parse('${config.endpoint}/version'));
    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();
    if (res.statusCode >= 200 && res.statusCode < 300) return body.trim();
    throw SurrealException(res.statusCode, body);
  }

  Future<bool> exists(String table, String id) async {
    final res = await _send('GET', '/key/$table/${Uri.encodeComponent(id)}');
    if (res.statusCode == 404) return false;
    final body = await _body(res);
    if (res.statusCode >= 200 && res.statusCode < 300) {
      final decoded = jsonDecode(body);
      if (decoded is List) {
        for (final stmt in decoded.cast<Map<String, dynamic>>()) {
          final r = stmt['result'];
          if (r is List && r.isNotEmpty) return true;
        }
        return false;
      }
      return true;
    }
    throw SurrealException(res.statusCode, body);
  }

  /// PUT replaces the record at table:id, creating it if absent. That's
  /// the upsert semantics we want for a pull.
  Future<void> upsert(
      String table, String id, Map<String, dynamic> body) async {
    final res = await _send(
      'PUT',
      '/key/$table/${Uri.encodeComponent(id)}',
      body: jsonEncode(body),
    );
    final responseBody = await _body(res);
    if (res.statusCode >= 200 && res.statusCode < 300) {
      // Surreal returns `[{result: [...], status: "OK"}]`. Treat status
      // != OK as an error.
      try {
        final decoded = jsonDecode(responseBody);
        if (decoded is List) {
          for (final stmt in decoded.cast<Map<String, dynamic>>()) {
            final s = stmt['status']?.toString();
            if (s != null && s != 'OK') {
              throw SurrealException(
                  500, 'Surreal status $s: ${stmt['result']}');
            }
          }
        }
      } catch (_) {
        // Tolerate non-JSON 2xx responses.
      }
      return;
    }
    throw SurrealException(res.statusCode, responseBody);
  }

  Future<List<Map<String, dynamic>>> selectAll(String table) async {
    final res = await _send('GET', '/key/$table');
    final body = await _body(res);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw SurrealException(res.statusCode, body);
    }
    final decoded = jsonDecode(body);
    if (decoded is! List) return const [];
    final out = <Map<String, dynamic>>[];
    for (final stmt in decoded.cast<Map<String, dynamic>>()) {
      final r = stmt['result'];
      if (r is List) {
        out.addAll(r.cast<Map<String, dynamic>>());
      }
    }
    return out;
  }

  Future<HttpClientResponse> _send(String method, String path,
      {String? body}) async {
    final uri = Uri.parse('${config.endpoint}$path');
    final req = await _client.openUrl(method, uri);
    req.headers.set(HttpHeaders.acceptHeader, 'application/json');
    if (body != null) {
      req.headers.contentType = ContentType.json;
    }
    if (config.namespace.isNotEmpty) {
      req.headers.set('Surreal-NS', config.namespace);
      req.headers.set('NS', config.namespace);
    }
    if (config.database.isNotEmpty) {
      req.headers.set('Surreal-DB', config.database);
      req.headers.set('DB', config.database);
    }
    if (config.username.isNotEmpty) {
      final token =
          base64Encode(utf8.encode('${config.username}:${config.password}'));
      req.headers.set(HttpHeaders.authorizationHeader, 'Basic $token');
    }
    if (body != null) {
      req.add(utf8.encode(body));
    }
    return req.close();
  }

  Future<String> _body(HttpClientResponse res) =>
      res.transform(utf8.decoder).join();
}

class SurrealException implements Exception {
  SurrealException(this.statusCode, this.body);
  final int statusCode;
  final String body;
  @override
  String toString() => 'SurrealDB HTTP $statusCode: $body';
}
