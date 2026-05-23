import 'dart:convert';

import 'package:shelf/shelf.dart';

import 'filter.dart';
import 'models.dart';
import 'sql_parser.dart';
import 'store.dart';

/// SurrealDB-shaped HTTP surface. Mimics the SurrealDB v1.x HTTP API:
///
///   GET  /surrealdb/                         — version + status
///   GET  /surrealdb/version                  — version string
///   GET  /surrealdb/key/<table>              — list of records
///   GET  /surrealdb/key/<table>/<id>         — single record (id == primary key)
///   POST /surrealdb/sql                      — run a SurrealQL / SQL query
///   POST /surrealdb/key/<table>              — insert a record
///   PATCH/DELETE /surrealdb/key/<table>/<id> — update / delete
///
/// Tables in this mock are the same EntitySets exposed elsewhere. Each row gets
/// a synthetic SurrealDB record id of the form `<table>:<primaryKeyValue>`.
class SurrealDbHandler {
  SurrealDbHandler(this.store);

  final GatewayStore store;

  static const _version = 'surrealdb-2.1.0-sap-gateway-mock';

  Handler get handler => (Request req) async {
        final tail = [...req.url.pathSegments];
        while (tail.isNotEmpty && tail.last.isEmpty) {
          tail.removeLast();
        }
        if (tail.isEmpty) return _root();
        switch (tail[0]) {
          case 'version':
            return Response.ok(_version,
                headers: const {'content-type': 'text/plain; charset=utf-8'});
          case 'status':
            return _ok({'status': 'OK', 'version': _version});
          case 'health':
            return Response.ok('OK',
                headers: const {'content-type': 'text/plain; charset=utf-8'});
          case 'sql':
            return _sql(req);
          case 'key':
            return _key(req, tail.skip(1).toList());
          default:
            return _nf('unknown path ${tail.join('/')}');
        }
      };

  Response _root() => _ok({
        'name': 'SurrealDB (SAP Gateway mock)',
        'version': _version,
        'namespaces': ['sap'],
        'databases': [for (final s in store.services) s.name.toLowerCase()],
        'tables': [
          for (final s in store.services)
            for (final es in s.entitySets) es.name.toLowerCase(),
        ],
      });

  Future<Response> _sql(Request req) async {
    if (req.method != 'POST') {
      return Response(405, body: 'POST required');
    }
    final body = await req.readAsString();
    if (body.trim().isEmpty) return _badSurreal('empty query');
    final statements = _splitStatements(body);
    final responses = <Map<String, dynamic>>[];
    for (final stmt in statements) {
      final start = DateTime.now();
      Map<String, dynamic> response;
      try {
        response = _runStatement(stmt);
      } catch (e) {
        response = {
          'status': 'ERR',
          'time': _elapsed(start),
          'detail': e.toString(),
        };
      }
      responses.add({
        'time': response['time'] ?? _elapsed(start),
        'status': response['status'] ?? 'OK',
        if (response['detail'] != null) 'detail': response['detail'],
        if (response['result'] != null) 'result': response['result'],
      });
    }
    return _ok(responses);
  }

  Map<String, dynamic> _runStatement(String stmt) {
    final lower = stmt.trim().toLowerCase();
    if (lower.startsWith('info for db') || lower.startsWith('info for ns') ||
        lower == 'info for kv') {
      return {
        'status': 'OK',
        'result': {
          'tables': {
            for (final s in store.services)
              for (final es in s.entitySets)
                es.name.toLowerCase(): 'TABLE ${es.name}',
          },
        }
      };
    }
    if (lower.startsWith('version')) {
      return {'status': 'OK', 'result': _version};
    }
    if (!lower.startsWith('select')) {
      // Lenient: just echo non-SELECT statements as accepted-but-unsupported.
      return {
        'status': 'OK',
        'result': [],
        'detail':
            'Mock SurrealDB only implements SELECT-style queries; statement accepted as no-op.',
      };
    }
    final SqlSelect select;
    try {
      select = parseSelect(stmt);
    } on SqlParseException catch (e) {
      return {'status': 'ERR', 'detail': e.message};
    } catch (e) {
      return {'status': 'ERR', 'detail': e.toString()};
    }
    final binding = _findEntitySet(select.table);
    if (binding == null) {
      return {'status': 'ERR', 'detail': 'No such table: ${select.table}'};
    }
    final (_, es, et) = binding;
    var rows = es.rows.toList();
    if (select.where != null) {
      rows = rows.where((r) => select.where!.evaluate(r) == true).toList();
    }
    if (select.orderBy.isNotEmpty) {
      rows.sort((a, b) {
        for (final o in select.orderBy) {
          final cmp = compareValues(a[o.field], b[o.field]);
          if (cmp != 0) return o.desc ? -cmp : cmp;
        }
        return 0;
      });
    }
    if (select.offset > 0) rows = rows.skip(select.offset).toList();
    if (select.limit != null) rows = rows.take(select.limit!).toList();

    final out = rows.map((r) => _toSurrealRecord(es, et, r, select)).toList();
    if (select.distinct) {
      final seen = <String>{};
      out.removeWhere((row) {
        final key = jsonEncode(row);
        if (seen.contains(key)) return true;
        seen.add(key);
        return false;
      });
    }
    return {'status': 'OK', 'result': out};
  }

  Map<String, dynamic> _toSurrealRecord(
      EntitySet es, EntityType et, Map<String, dynamic> row, SqlSelect select) {
    final id = '${es.name.toLowerCase()}:${_keyOf(et, row)}';
    final cols = select.allColumns
        ? [for (final p in et.properties) p.name]
        : select.columns;
    final out = <String, dynamic>{'id': id};
    for (final c in cols) {
      out[c] = row[c];
    }
    return out;
  }

  String _keyOf(EntityType et, Map<String, dynamic> row) {
    if (et.keys.isEmpty) return row.hashCode.toString();
    return et.keys.map((k) => '${row[k] ?? 'null'}').join('_');
  }

  Future<Response> _key(Request req, List<String> tail) async {
    if (tail.isEmpty) return _badSurreal('table required');
    final tableName = tail[0];
    final binding = _findEntitySet(tableName);
    if (binding == null) {
      return _nf('table $tableName not found');
    }
    final (_, es, et) = binding;
    final start = DateTime.now();
    if (tail.length == 1) {
      switch (req.method) {
        case 'GET':
          return _surrealResult(
            [
              for (final r in es.rows) _toSurrealRecord(es, et, r, _allCols()),
            ],
            start,
          );
        case 'POST':
          final body = await _readJson(req);
          if (body == null) return _badSurreal('body required');
          es.rows.add(Map<String, dynamic>.from(body));
          await store.save();
          return _surrealResult([
            _toSurrealRecord(es, et, body, _allCols()),
          ], start);
        default:
          return Response(405, body: 'Method not allowed');
      }
    }
    final id = tail[1];
    final idx = _findIndexById(es, et, id);
    if (idx < 0 && req.method != 'POST') return _surrealResult([], start);
    switch (req.method) {
      case 'GET':
        return _surrealResult([
          _toSurrealRecord(es, et, es.rows[idx], _allCols()),
        ], start);
      case 'PATCH':
      case 'PUT':
        final body = await _readJson(req);
        if (body == null) return _badSurreal('body required');
        es.rows[idx].addAll(body);
        await store.save();
        return _surrealResult([
          _toSurrealRecord(es, et, es.rows[idx], _allCols()),
        ], start);
      case 'DELETE':
        final removed = es.rows.removeAt(idx);
        await store.save();
        return _surrealResult([
          _toSurrealRecord(es, et, removed, _allCols()),
        ], start);
      default:
        return Response(405, body: 'Method not allowed');
    }
  }

  SqlSelect _allCols() => SqlSelect(
        table: '',
        schema: null,
        columns: const [],
        allColumns: true,
        where: null,
        orderBy: const [],
        limit: null,
        offset: 0,
        distinct: false,
      );

  int _findIndexById(EntitySet es, EntityType et, String id) {
    for (var i = 0; i < es.rows.length; i++) {
      if (_keyOf(et, es.rows[i]) == id) return i;
    }
    return -1;
  }

  (GatewayService, EntitySet, EntityType)? _findEntitySet(String name) {
    final lower = name.toLowerCase();
    for (final s in store.services) {
      for (final es in s.entitySets) {
        if (es.name.toLowerCase() == lower) {
          final et = s.entityTypeByName(es.entityTypeName);
          if (et != null) return (s, es, et);
        }
      }
    }
    return null;
  }

  List<String> _splitStatements(String body) {
    // Naive — split on `;` outside string literals.
    final out = <String>[];
    final buf = StringBuffer();
    var quoted = false;
    for (var i = 0; i < body.length; i++) {
      final c = body[i];
      if (c == "'") {
        quoted = !quoted;
        buf.write(c);
        continue;
      }
      if (!quoted && c == ';') {
        if (buf.toString().trim().isNotEmpty) out.add(buf.toString().trim());
        buf.clear();
        continue;
      }
      buf.write(c);
    }
    if (buf.toString().trim().isNotEmpty) out.add(buf.toString().trim());
    return out;
  }

  Future<Map<String, dynamic>?> _readJson(Request req) async {
    final raw = await req.readAsString();
    if (raw.isEmpty) return null;
    final decoded = jsonDecode(raw);
    return decoded is Map<String, dynamic> ? decoded : null;
  }

  String _elapsed(DateTime start) {
    final us = DateTime.now().difference(start).inMicroseconds;
    if (us < 1000) return '${us}µs';
    return '${(us / 1000).toStringAsFixed(2)}ms';
  }

  Response _surrealResult(List<dynamic> records, DateTime start) => _ok([
        {'time': _elapsed(start), 'status': 'OK', 'result': records},
      ]);

  Response _ok(Object body, {int status = 200}) => Response(
        status,
        body: jsonEncode(body),
        headers: const {'content-type': 'application/json; charset=utf-8'},
      );

  Response _nf(String msg) => Response.notFound(
      jsonEncode([
        {'status': 'ERR', 'time': '0µs', 'detail': msg}
      ]),
      headers: const {'content-type': 'application/json'});

  Response _badSurreal(String msg) => Response.badRequest(
      body: jsonEncode([
        {'status': 'ERR', 'time': '0µs', 'detail': msg}
      ]),
      headers: const {'content-type': 'application/json'});
}
