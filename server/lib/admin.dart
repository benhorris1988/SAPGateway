import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'models.dart';
import 'store.dart';

/// JSON CRUD API used by the Flutter management UI.
///
/// Routes are mounted under `/admin/`.
class AdminHandler {
  AdminHandler(this.store);

  final GatewayStore store;

  Router get router {
    final r = Router();

    r.get('/services', (Request _) {
      return _ok(store.services.map((s) => _summary(s)).toList());
    });

    r.post('/services', (Request req) async {
      final body = await _readJson(req);
      final name = body?['name'] as String?;
      if (name == null || name.isEmpty) return _bad('name required');
      if (store.serviceByName(name) != null) return _conflict('exists');
      final s = GatewayService(
        name: name,
        namespace: (body?['namespace'] as String?) ?? name,
        description: (body?['description'] as String?) ?? '',
      );
      store.services.add(s);
      await store.save();
      return _ok(s.toJson(), status: 201);
    });

    r.get('/services/<svc>', (Request _, String svc) {
      final s = store.serviceByName(svc);
      if (s == null) return _nf();
      return _ok(s.toJson());
    });

    r.patch('/services/<svc>', (Request req, String svc) async {
      final s = store.serviceByName(svc);
      if (s == null) return _nf();
      final body = await _readJson(req) ?? const {};
      if (body['name'] is String) s.name = body['name'] as String;
      if (body['namespace'] is String)
        s.namespace = body['namespace'] as String;
      if (body['description'] is String)
        s.description = body['description'] as String;
      await store.save();
      return _ok(s.toJson());
    });

    r.delete('/services/<svc>', (Request _, String svc) async {
      store.services.removeWhere((s) => s.name == svc);
      await store.save();
      return Response(204);
    });

    // ─── Entity types ─────────────────────────────────────────────────
    r.get('/services/<svc>/entity-types', (Request _, String svc) {
      final s = store.serviceByName(svc);
      if (s == null) return _nf();
      return _ok(s.entityTypes.map((e) => e.toJson()).toList());
    });

    r.post('/services/<svc>/entity-types', (Request req, String svc) async {
      final s = store.serviceByName(svc);
      if (s == null) return _nf();
      final body = await _readJson(req);
      final name = body?['name'] as String?;
      if (name == null || name.isEmpty) return _bad('name required');
      if (s.entityTypeByName(name) != null) return _conflict('exists');
      final et = EntityType(
        name: name,
        keys: ((body?['keys'] as List?) ?? const []).cast<String>(),
        properties: ((body?['properties'] as List?) ?? const [])
            .cast<Map<String, dynamic>>()
            .map(Property.fromJson)
            .toList(),
      );
      s.entityTypes.add(et);
      await store.save();
      return _ok(et.toJson(), status: 201);
    });

    r.patch('/services/<svc>/entity-types/<et>',
        (Request req, String svc, String et) async {
      final s = store.serviceByName(svc);
      if (s == null) return _nf();
      final t = s.entityTypeByName(et);
      if (t == null) return _nf();
      final body = await _readJson(req) ?? const {};
      if (body['name'] is String) {
        final newName = body['name'] as String;
        if (newName != t.name && s.entityTypeByName(newName) != null) {
          return _conflict('name in use');
        }
        // cascade to entity sets that point at the old name
        for (final es in s.entitySets) {
          if (es.entityTypeName == t.name) es.entityTypeName = newName;
        }
        t.name = newName;
      }
      if (body['keys'] is List) {
        t.keys
          ..clear()
          ..addAll((body['keys'] as List).cast<String>());
      }
      await store.save();
      return _ok(t.toJson());
    });

    r.delete('/services/<svc>/entity-types/<et>',
        (Request _, String svc, String et) async {
      final s = store.serviceByName(svc);
      if (s == null) return _nf();
      s.entitySets.removeWhere((e) => e.entityTypeName == et);
      s.entityTypes.removeWhere((t) => t.name == et);
      await store.save();
      return Response(204);
    });

    // ─── Properties (columns) ─────────────────────────────────────────
    r.post('/services/<svc>/entity-types/<et>/properties',
        (Request req, String svc, String et) async {
      final s = store.serviceByName(svc);
      if (s == null) return _nf();
      final t = s.entityTypeByName(et);
      if (t == null) return _nf();
      final body = await _readJson(req);
      if (body == null) return _bad('body required');
      final p = Property.fromJson(body);
      if (t.propertyByName(p.name) != null) return _conflict('exists');
      t.properties.add(p);
      await store.save();
      return _ok(p.toJson(), status: 201);
    });

    r.patch('/services/<svc>/entity-types/<et>/properties/<prop>',
        (Request req, String svc, String et, String prop) async {
      final s = store.serviceByName(svc);
      if (s == null) return _nf();
      final t = s.entityTypeByName(et);
      if (t == null) return _nf();
      final p = t.propertyByName(prop);
      if (p == null) return _nf();
      final body = await _readJson(req) ?? const {};
      if (body['name'] is String) {
        final newName = body['name'] as String;
        if (newName != p.name && t.propertyByName(newName) != null) {
          return _conflict('name in use');
        }
        if (newName != p.name) {
          // rename across all rows of any EntitySet using this type
          for (final es in s.entitySets) {
            if (es.entityTypeName != t.name) continue;
            for (final row in es.rows) {
              if (row.containsKey(p.name)) {
                row[newName] = row.remove(p.name);
              }
            }
          }
          if (t.keys.contains(p.name)) {
            final idx = t.keys.indexOf(p.name);
            t.keys[idx] = newName;
          }
          p.name = newName;
        }
      }
      if (body['edmType'] is String) p.edmType = body['edmType'] as String;
      if (body['nullable'] is bool) p.nullable = body['nullable'] as bool;
      if (body.containsKey('maxLength'))
        p.maxLength = body['maxLength'] as int?;
      if (body.containsKey('precision'))
        p.precision = body['precision'] as int?;
      if (body.containsKey('scale')) p.scale = body['scale'] as int?;
      if (body.containsKey('label')) p.label = body['label'] as String?;
      await store.save();
      return _ok(p.toJson());
    });

    r.delete('/services/<svc>/entity-types/<et>/properties/<prop>',
        (Request _, String svc, String et, String prop) async {
      final s = store.serviceByName(svc);
      if (s == null) return _nf();
      final t = s.entityTypeByName(et);
      if (t == null) return _nf();
      t.properties.removeWhere((p) => p.name == prop);
      t.keys.remove(prop);
      // also strip from existing rows so the wire shape stays clean
      for (final es in s.entitySets) {
        if (es.entityTypeName != t.name) continue;
        for (final row in es.rows) {
          row.remove(prop);
        }
      }
      await store.save();
      return Response(204);
    });

    // ─── Entity sets ──────────────────────────────────────────────────
    r.get('/services/<svc>/entity-sets', (Request _, String svc) {
      final s = store.serviceByName(svc);
      if (s == null) return _nf();
      return _ok(s.entitySets
          .map((e) => {
                'name': e.name,
                'entityTypeName': e.entityTypeName,
                'rowCount': e.rows.length,
              })
          .toList());
    });

    r.post('/services/<svc>/entity-sets', (Request req, String svc) async {
      final s = store.serviceByName(svc);
      if (s == null) return _nf();
      final body = await _readJson(req);
      final name = body?['name'] as String?;
      final etName = body?['entityTypeName'] as String?;
      if (name == null || etName == null) {
        return _bad('name and entityTypeName required');
      }
      if (s.entitySetByName(name) != null) return _conflict('exists');
      if (s.entityTypeByName(etName) == null) {
        return _bad('Unknown entityType: $etName');
      }
      final es = EntitySet(name: name, entityTypeName: etName);
      s.entitySets.add(es);
      await store.save();
      return _ok(es.toJson(), status: 201);
    });

    r.delete('/services/<svc>/entity-sets/<es>',
        (Request _, String svc, String es) async {
      final s = store.serviceByName(svc);
      if (s == null) return _nf();
      s.entitySets.removeWhere((e) => e.name == es);
      await store.save();
      return Response(204);
    });

    // ─── Rows ────────────────────────────────────────────────────────
    r.get('/services/<svc>/entity-sets/<es>/rows',
        (Request _, String svc, String es) {
      final s = store.serviceByName(svc);
      if (s == null) return _nf();
      final set = s.entitySetByName(es);
      if (set == null) return _nf();
      return _ok(set.rows);
    });

    r.post('/services/<svc>/entity-sets/<es>/rows',
        (Request req, String svc, String es) async {
      final s = store.serviceByName(svc);
      if (s == null) return _nf();
      final set = s.entitySetByName(es);
      if (set == null) return _nf();
      final body = await _readJson(req);
      if (body == null) return _bad('body required');
      set.rows.add(Map<String, dynamic>.from(body));
      await store.save();
      return _ok(body, status: 201);
    });

    r.put('/services/<svc>/entity-sets/<es>/rows/<idx>',
        (Request req, String svc, String es, String idx) async {
      final s = store.serviceByName(svc);
      if (s == null) return _nf();
      final set = s.entitySetByName(es);
      if (set == null) return _nf();
      final i = int.tryParse(idx);
      if (i == null || i < 0 || i >= set.rows.length) return _nf();
      final body = await _readJson(req);
      if (body == null) return _bad('body required');
      set.rows[i] = Map<String, dynamic>.from(body);
      await store.save();
      return _ok(set.rows[i]);
    });

    r.delete('/services/<svc>/entity-sets/<es>/rows/<idx>',
        (Request _, String svc, String es, String idx) async {
      final s = store.serviceByName(svc);
      if (s == null) return _nf();
      final set = s.entitySetByName(es);
      if (set == null) return _nf();
      final i = int.tryParse(idx);
      if (i == null || i < 0 || i >= set.rows.length) return _nf();
      set.rows.removeAt(i);
      await store.save();
      return Response(204);
    });

    // ─── Connections ─────────────────────────────────────────────────
    r.get('/connections', (Request req) {
      final base = _baseUrlOf(req);
      return _ok(_connectionCatalogue(base));
    });

    // ─── Misc ────────────────────────────────────────────────────────
    r.post('/reset', (Request _) async {
      await store.reset();
      return _ok({'ok': true});
    });

    return r;
  }

  /// Catalogue of every connection surface this gateway exposes. Consumed by
  /// the Flutter admin UI so a single list reflects every protocol it offers.
  List<Map<String, dynamic>> _connectionCatalogue(String base) {
    final firstService = store.services.isEmpty ? null : store.services.first;
    final firstSet =
        firstService == null || firstService.entitySets.isEmpty
            ? null
            : firstService.entitySets.first;

    String odataExampleV2() => firstService == null
        ? '$base/sap/opu/odata/sap/'
        : '$base/sap/opu/odata/sap/${firstService.name}/${firstSet?.name ?? ''}?\$format=json&\$top=5';

    String odataExampleV4() => firstService == null
        ? '$base/sap/opu/odata4/sap/'
        : '$base/sap/opu/odata4/sap/${firstService.name}/${firstSet?.name ?? ''}?\$count=true&\$top=5';

    String restExample() => firstService == null
        ? '$base/sap/rest/'
        : '$base/sap/rest/${firstService.name}/${firstSet?.name ?? ''}?limit=5';

    return [
      {
        'id': 'odata_v2',
        'name': 'OData v2',
        'kind': 'sap',
        'description':
            'NetWeaver Gateway compatible SAP OData v2 surface (XML metadata, '
                'JSON or XML payloads, \$filter / \$expand subset).',
        'root': '$base/sap/opu/odata/sap/',
        'example': odataExampleV2(),
        'methods': ['GET', 'POST', 'PUT', 'PATCH', 'MERGE', 'DELETE'],
      },
      {
        'id': 'odata_v4',
        'name': 'OData v4',
        'kind': 'sap',
        'description':
            'OASIS OData v4 (S/4HANA Gateway style). JSON-only by default, '
                'EDMX 4.0 metadata, \$count=true, \$select, \$filter.',
        'root': '$base/sap/opu/odata4/sap/',
        'example': odataExampleV4(),
        'methods': ['GET', 'POST', 'PUT', 'PATCH', 'DELETE'],
      },
      {
        'id': 'sap_rest',
        'name': 'SAP REST',
        'kind': 'sap',
        'description':
            'Plain JSON REST shape — what a Z-program / custom REST API on '
                'top of SAP typically exposes. Uses where, limit, offset, fields.',
        'root': '$base/sap/rest/',
        'example': restExample(),
        'methods': ['GET', 'POST', 'PUT', 'PATCH', 'DELETE'],
      },
      {
        'id': 'sap_soap',
        'name': 'SOAP / BAPI / RFC',
        'kind': 'sap',
        'description':
            'ECC-era SOAP envelopes for BAPI_*_GETLIST functions and the '
                'generic RFC_READ_TABLE call. Accepts both SOAP XML and JSON-RFC bodies.',
        'root': '$base/sap/bc/srt/',
        'example': '$base/sap/bc/srt/',
        'methods': ['GET', 'POST'],
      },
      {
        'id': 'sap_idoc',
        'name': 'IDoc (ALE / EDI)',
        'kind': 'sap',
        'description':
            'ORDERS05, DEBMAS06, CREMAS05, MATMAS05, ORDERS_PURCH_05, COND_A05 — '
                'XML-shaped IDoc batches with EDI_DC40 control records.',
        'root': '$base/sap/idoc/',
        'example': '$base/sap/idoc/ORDERS05',
        'methods': ['GET', 'POST'],
      },
      {
        'id': 'sqlserver_2017',
        'name': 'SQL Server 2017',
        'kind': 'database',
        'description':
            'T-SQL SELECT surface mimicking SQL Server 2017 (compat level 140, '
                'classic @@VERSION string).',
        'root': '$base/sqlserver/2017/',
        'example': '$base/sqlserver/2017/info',
        'methods': ['GET', 'POST'],
      },
      {
        'id': 'sqlserver_2022',
        'name': 'SQL Server 2022',
        'kind': 'database',
        'description':
            'T-SQL SELECT surface mimicking SQL Server 2022 (compat level 160, '
                'ledger / PSPO / Synapse Link advertised on /info).',
        'root': '$base/sqlserver/2022/',
        'example': '$base/sqlserver/2022/info',
        'methods': ['GET', 'POST'],
      },
      {
        'id': 'surrealdb',
        'name': 'SurrealDB',
        'kind': 'database',
        'description':
            'SurrealDB v1.x-shaped HTTP API: /sql, /key/<table>[/<id>], '
                '/version. Same store, surfaced as SurrealQL.',
        'root': '$base/surrealdb/',
        'example': '$base/surrealdb/key/CustomerSet',
        'methods': ['GET', 'POST', 'PATCH', 'DELETE'],
      },
    ];
  }

  String _baseUrlOf(Request req) {
    final scheme = req.requestedUri.scheme;
    final host = req.requestedUri.host;
    final port = req.requestedUri.port;
    final defaultPort = (scheme == 'https' && port == 443) ||
        (scheme == 'http' && port == 80) ||
        port == 0;
    return defaultPort ? '$scheme://$host' : '$scheme://$host:$port';
  }

  // ─── helpers ────────────────────────────────────────────────────────
  Map<String, dynamic> _summary(GatewayService s) => {
        'name': s.name,
        'namespace': s.namespace,
        'description': s.description,
        'entityTypeCount': s.entityTypes.length,
        'entitySetCount': s.entitySets.length,
        'rowCount': s.entitySets.fold<int>(0, (a, e) => a + e.rows.length),
      };

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

  Response _bad(String msg) =>
      Response.badRequest(body: jsonEncode({'error': msg}), headers: _ct);
  Response _nf() =>
      Response.notFound(jsonEncode({'error': 'not_found'}), headers: _ct);
  Response _conflict(String msg) =>
      Response(409, body: jsonEncode({'error': msg}), headers: _ct);

  static const _ct = {'content-type': 'application/json; charset=utf-8'};
}
