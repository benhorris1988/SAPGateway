import 'dart:convert';

import 'package:shelf/shelf.dart';

import 'filter.dart';
import 'models.dart';
import 'store.dart';

/// Plain REST surface — what an SAP custom REST API or a Z-program wrapper
/// would typically expose: `GET /sap/rest/<service>/<entitySet>` returns an
/// array of plain JSON objects, no `d.results` / OData wrapping.
///
/// Query options use simple, REST-flavoured names: `where`, `limit`, `offset`,
/// `orderBy`, `fields`. `where` accepts the same expression grammar as OData
/// `$filter`, so anyone comfortable with one can use the other.
class SapRestHandler {
  SapRestHandler(this.store);

  final GatewayStore store;

  Handler get handler => (Request req) async {
        final tail = [...req.url.pathSegments];
        while (tail.isNotEmpty && tail.last.isEmpty) {
          tail.removeLast();
        }
        if (tail.isEmpty) return _catalog();
        final serviceName = tail[0];
        final service = store.serviceByName(serviceName);
        if (service == null) return _nf('service $serviceName not found');
        if (tail.length == 1) return _serviceListing(service);
        final entitySetName = tail[1];
        final es = service.entitySetByName(entitySetName);
        if (es == null) return _nf('entitySet $entitySetName not found');
        final et = service.entityTypeByName(es.entityTypeName);
        if (et == null) return _err('entityType missing on server', 500);

        if (tail.length == 3) {
          return _handleOne(req, service, es, et, tail[2]);
        }
        return _handleMany(req, service, es, et);
      };

  Response _catalog() => _ok({
        'services': [
          for (final s in store.services)
            {
              'name': s.name,
              'description': s.description,
              'entitySets': [for (final es in s.entitySets) es.name],
            },
        ],
      });

  Response _serviceListing(GatewayService s) => _ok({
        'name': s.name,
        'description': s.description,
        'entitySets': [
          for (final es in s.entitySets)
            {
              'name': es.name,
              'entityTypeName': es.entityTypeName,
              'rowCount': es.rows.length,
            }
        ],
        'entityTypes': [for (final t in s.entityTypes) t.toJson()],
      });

  Future<Response> _handleOne(Request req, GatewayService svc, EntitySet es,
      EntityType et, String key) async {
    final keys = _keysFor(key, et);
    final idx = _findIndex(es, et, keys);
    if (idx < 0) return _nf('row not found');
    switch (req.method) {
      case 'GET':
        return _ok(es.rows[idx]);
      case 'PUT':
      case 'PATCH':
        final body = await _readJson(req);
        if (body == null) return _bad('body required');
        es.rows[idx]
          ..addAll(body)
          ..addAll(keys);
        await store.save();
        return _ok(es.rows[idx]);
      case 'DELETE':
        es.rows.removeAt(idx);
        await store.save();
        return Response(204);
      default:
        return Response(405, body: 'Method not allowed');
    }
  }

  Future<Response> _handleMany(Request req, GatewayService svc, EntitySet es,
      EntityType et) async {
    if (req.method == 'POST') {
      final body = await _readJson(req);
      if (body == null) return _bad('body required');
      if (et.keys.any((k) => body[k] == null)) {
        return _bad('missing key(s) ${et.keys}');
      }
      if (_findIndex(es, et, body) >= 0) {
        return _conflict('row with that key already exists');
      }
      es.rows.add(Map<String, dynamic>.from(body));
      await store.save();
      return _ok(body, status: 201);
    }
    if (req.method != 'GET') {
      return Response(405, body: 'Method not allowed');
    }

    final qp = req.url.queryParameters;
    var rows = es.rows.toList();

    final whereExpr = qp['where'] ?? qp['filter'];
    if (whereExpr != null && whereExpr.trim().isNotEmpty) {
      try {
        final f = FilterParser(whereExpr).parse();
        rows = rows.where((r) => f.evaluate(r) == true).toList();
      } catch (e) {
        return _bad('invalid where clause: $e');
      }
    }

    final orderBy = qp['orderBy'] ?? qp['order_by'];
    if (orderBy != null && orderBy.trim().isNotEmpty) {
      final parts = orderBy.split(',').map((s) => s.trim()).toList();
      rows.sort((a, b) {
        for (final part in parts) {
          final tokens = part.split(RegExp(r'\s+'));
          final field = tokens[0];
          final desc = tokens.length > 1 && tokens[1].toLowerCase() == 'desc';
          final cmp = compareValues(a[field], b[field]);
          if (cmp != 0) return desc ? -cmp : cmp;
        }
        return 0;
      });
    }

    final total = rows.length;
    final offset = int.tryParse(qp['offset'] ?? '') ?? 0;
    final limit = int.tryParse(qp['limit'] ?? '');
    if (offset > 0) rows = rows.skip(offset).toList();
    if (limit != null) rows = rows.take(limit).toList();

    final fieldsExpr = qp['fields'];
    List<String>? fields;
    if (fieldsExpr != null && fieldsExpr.trim().isNotEmpty) {
      fields = fieldsExpr.split(',').map((s) => s.trim()).toList();
    }

    final shaped = rows.map((r) {
      if (fields == null) return r;
      return <String, dynamic>{for (final f in fields!) f: r[f]};
    }).toList();

    return _ok({
      'count': total,
      'offset': offset,
      'limit': limit,
      'items': shaped,
    });
  }

  Map<String, dynamic> _keysFor(String keyExpr, EntityType et) {
    // Allow "/<set>/key" for single-key types and "/<set>/key1,key2" multi.
    final segments = keyExpr.split(',').map((s) => s.trim()).toList();
    if (segments.length == 1 && et.keys.length == 1) {
      return {et.keys.first: segments.first};
    }
    final out = <String, dynamic>{};
    for (var i = 0; i < et.keys.length && i < segments.length; i++) {
      out[et.keys[i]] = segments[i];
    }
    return out;
  }

  int _findIndex(EntitySet es, EntityType et, Map<String, dynamic> keys) {
    for (var i = 0; i < es.rows.length; i++) {
      var match = true;
      for (final k in et.keys) {
        if (es.rows[i][k]?.toString() != keys[k]?.toString()) {
          match = false;
          break;
        }
      }
      if (match) return i;
    }
    return -1;
  }

  Future<Map<String, dynamic>?> _readJson(Request req) async {
    final raw = await req.readAsString();
    if (raw.isEmpty) return null;
    final decoded = jsonDecode(raw);
    return decoded is Map<String, dynamic> ? decoded : null;
  }

  Response _ok(Object body, {int status = 200}) => Response(
        status,
        body: jsonEncode(body),
        headers: const {'content-type': 'application/json; charset=utf-8'},
      );

  Response _nf(String msg) => Response.notFound(
      jsonEncode({'error': 'not_found', 'message': msg}),
      headers: const {'content-type': 'application/json'});
  Response _bad(String msg) => Response.badRequest(
      body: jsonEncode({'error': 'bad_request', 'message': msg}),
      headers: const {'content-type': 'application/json'});
  Response _conflict(String msg) => Response(409,
      body: jsonEncode({'error': 'conflict', 'message': msg}),
      headers: const {'content-type': 'application/json'});
  Response _err(String msg, int status) => Response(status,
      body: jsonEncode({'error': 'server_error', 'message': msg}),
      headers: const {'content-type': 'application/json'});
}
