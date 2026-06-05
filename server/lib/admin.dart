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

    // ─── Misc ────────────────────────────────────────────────────────
    r.post('/reset', (Request _) async {
      await store.reset();
      return _ok({'ok': true});
    });

    return r;
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
