import 'dart:convert';

import 'package:shelf/shelf.dart';

import 'models.dart';
import 'store.dart';

/// Clean REST surface over the same data the OData layer exposes.
/// Mounted at `/api/v1/`.
///
///   GET    /api/v1/                  -> { collections: [...] }
///   GET    /api/v1/{collection}      -> { data, total, limit, offset }
///   GET    /api/v1/{collection}/{id} -> single entity
///   POST   /api/v1/{collection}      -> 201 + created entity
///   PUT    /api/v1/{collection}/{id} -> 200 + replaced entity
///   PATCH  /api/v1/{collection}/{id} -> 200 + patched entity
///   DELETE /api/v1/{collection}/{id} -> 204
///
/// Collection name is the EntitySet name lowercased with the trailing
/// "Set" stripped and "s" appended (EmployeeSet -> employees,
/// ExpenseSet -> expenses). Composite keys are joined with commas in
/// declaration order, e.g. `/api/v1/timesheets/00010001,2026-05-18T00:00:00`.
///
/// List query params: `limit`, `offset`, `sort` (comma-separated, `-`
/// prefix for descending), `search` (case-insensitive substring across
/// all fields). Any other query param is treated as an equality filter
/// on the matching field.
class RestHandler {
  RestHandler(this.store);

  final GatewayStore store;

  Handler get handler => (Request req) async {
        final segs = [
          for (final s in req.url.pathSegments)
            if (s.isNotEmpty) s,
        ];

        if (segs.isEmpty) return _discovery();

        final collection = segs[0].toLowerCase();
        final hit = _resolve(collection);
        if (hit == null) {
          return _err(404, 'Unknown collection "$collection"');
        }
        final (es, et) = hit;

        if (segs.length == 1) {
          switch (req.method) {
            case 'GET':
              return _list(req, es, et);
            case 'POST':
              return _create(req, es, et);
            default:
              return _err(405, 'Method not allowed on collection');
          }
        }

        final id = Uri.decodeComponent(segs[1]);
        switch (req.method) {
          case 'GET':
            return _getOne(es, et, id);
          case 'PUT':
            return _put(req, es, et, id);
          case 'PATCH':
            return _patch(req, es, et, id);
          case 'DELETE':
            return _delete(es, et, id);
          default:
            return _err(405, 'Method not allowed on item');
        }
      };

  // ─── Routes ────────────────────────────────────────────────────────────

  Response _discovery() {
    final cols = <Map<String, dynamic>>[];
    for (final svc in store.services) {
      for (final es in svc.entitySets) {
        cols.add({
          'name': _collectionName(es),
          'service': svc.name,
          'entitySet': es.name,
          'entityType': es.entityTypeName,
          'count': es.rows.length,
        });
      }
    }
    cols.sort((a, b) =>
        (a['name'] as String).compareTo(b['name'] as String));
    return _json({'collections': cols});
  }

  Future<Response> _list(Request req, EntitySet es, EntityType et) async {
    final qp = req.url.queryParameters;
    var rows = es.rows.toList();

    const reserved = {'limit', 'offset', 'sort', 'search'};
    for (final entry in qp.entries) {
      if (reserved.contains(entry.key)) continue;
      rows = rows
          .where((r) => r[entry.key]?.toString() == entry.value)
          .toList();
    }

    final search = qp['search'];
    if (search != null && search.isNotEmpty) {
      final needle = search.toLowerCase();
      rows = rows
          .where((r) => r.values.any(
              (v) => v?.toString().toLowerCase().contains(needle) ?? false))
          .toList();
    }

    final sort = qp['sort'];
    if (sort != null && sort.isNotEmpty) {
      final parts = sort.split(',').map((s) => s.trim()).toList();
      rows.sort((a, b) {
        for (final part in parts) {
          final desc = part.startsWith('-');
          final field = desc ? part.substring(1) : part;
          final cmp = _cmp(a[field], b[field]);
          if (cmp != 0) return desc ? -cmp : cmp;
        }
        return 0;
      });
    }

    final total = rows.length;
    final offset = int.tryParse(qp['offset'] ?? '') ?? 0;
    final limit = int.tryParse(qp['limit'] ?? '') ?? 50;
    if (offset > 0) rows = rows.skip(offset).toList();
    if (limit > 0) rows = rows.take(limit).toList();

    return _json({
      'data': rows,
      'total': total,
      'limit': limit,
      'offset': offset,
    });
  }

  Future<Response> _create(Request req, EntitySet es, EntityType et) async {
    final body = await _readBody(req);
    if (body == null) return _err(400, 'JSON object required');
    final missing = et.keys
        .where((k) => body[k] == null || body[k].toString().isEmpty)
        .toList();
    if (missing.isNotEmpty) {
      return _err(400, 'Missing key field(s): $missing');
    }
    if (_findIdx(es, et, body) >= 0) {
      return _err(409, 'Entity with that key already exists');
    }
    final row = Map<String, dynamic>.from(body);
    es.rows.add(row);
    await store.save();
    return _json(row, status: 201);
  }

  Response _getOne(EntitySet es, EntityType et, String id) {
    final keys = _parseId(id, et);
    if (keys == null) return _err(400, 'Bad id');
    final i = _findIdx(es, et, keys);
    if (i < 0) return _err(404, 'Not found');
    return _json(es.rows[i]);
  }

  Future<Response> _put(
      Request req, EntitySet es, EntityType et, String id) async {
    final keys = _parseId(id, et);
    if (keys == null) return _err(400, 'Bad id');
    final i = _findIdx(es, et, keys);
    if (i < 0) return _err(404, 'Not found');
    final body = await _readBody(req);
    if (body == null) return _err(400, 'JSON object required');
    final row = Map<String, dynamic>.from(body)..addAll(keys);
    es.rows[i] = row;
    await store.save();
    return _json(row);
  }

  Future<Response> _patch(
      Request req, EntitySet es, EntityType et, String id) async {
    final keys = _parseId(id, et);
    if (keys == null) return _err(400, 'Bad id');
    final i = _findIdx(es, et, keys);
    if (i < 0) return _err(404, 'Not found');
    final body = await _readBody(req);
    if (body == null) return _err(400, 'JSON object required');
    es.rows[i]
      ..addAll(body)
      ..addAll(keys);
    await store.save();
    return _json(es.rows[i]);
  }

  Future<Response> _delete(EntitySet es, EntityType et, String id) async {
    final keys = _parseId(id, et);
    if (keys == null) return _err(400, 'Bad id');
    final i = _findIdx(es, et, keys);
    if (i < 0) return _err(404, 'Not found');
    es.rows.removeAt(i);
    await store.save();
    return Response(204);
  }

  // ─── Helpers ───────────────────────────────────────────────────────────

  /// Public lookup so other handlers (e.g. the integration layer) can
  /// resolve the same REST collection names this handler exposes.
  (EntitySet, EntityType)? resolveCollection(String collection) =>
      _resolve(collection.toLowerCase());

  (EntitySet, EntityType)? _resolve(String collection) {
    for (final svc in store.services) {
      for (final es in svc.entitySets) {
        if (_collectionName(es) == collection) {
          final et = svc.entityTypeByName(es.entityTypeName);
          if (et != null) return (es, et);
        }
      }
    }
    return null;
  }

  String _collectionName(EntitySet es) {
    var n = es.name;
    if (n.toLowerCase().endsWith('set')) {
      n = n.substring(0, n.length - 3);
    }
    return '${n.toLowerCase()}s';
  }

  Map<String, dynamic>? _parseId(String id, EntityType et) {
    final parts = id.split(',');
    if (parts.length != et.keys.length) return null;
    return {for (var i = 0; i < et.keys.length; i++) et.keys[i]: parts[i]};
  }

  int _findIdx(EntitySet es, EntityType et, Map<String, dynamic> keys) {
    for (var i = 0; i < es.rows.length; i++) {
      var ok = true;
      for (final k in et.keys) {
        if (es.rows[i][k]?.toString() != keys[k]?.toString()) {
          ok = false;
          break;
        }
      }
      if (ok) return i;
    }
    return -1;
  }

  Future<Map<String, dynamic>?> _readBody(Request req) async {
    final raw = await req.readAsString();
    if (raw.isEmpty) return null;
    final decoded = jsonDecode(raw);
    return decoded is Map<String, dynamic> ? decoded : null;
  }

  int _cmp(dynamic a, dynamic b) {
    if (a == null && b == null) return 0;
    if (a == null) return -1;
    if (b == null) return 1;
    final an = num.tryParse(a.toString());
    final bn = num.tryParse(b.toString());
    if (an != null && bn != null) return an.compareTo(bn);
    return a.toString().compareTo(b.toString());
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
