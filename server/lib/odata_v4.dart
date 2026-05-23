import 'dart:convert';

import 'package:shelf/shelf.dart';

import 'filter.dart';
import 'models.dart';
import 'store.dart';

/// OData v4 surface. Reuses the same store as the v2 handler, so every change
/// made through the admin API is reflected on both versions at once.
///
///   /sap/opu/odata4/sap/                            -> service catalog
///   /sap/opu/odata4/sap/<SVC>/                      -> service document
///   /sap/opu/odata4/sap/<SVC>/$metadata             -> EDMX 4.0 schema
///   /sap/opu/odata4/sap/<SVC>/<EntitySet>           -> list (GET, POST)
///   /sap/opu/odata4/sap/<SVC>/<EntitySet>(<key>)    -> single (GET, PATCH, PUT, DELETE)
///   /sap/opu/odata4/sap/<SVC>/$count                -> total entity count across sets
class ODataV4Handler {
  ODataV4Handler(this.store);

  final GatewayStore store;

  Handler get handler => (Request req) async {
        final tail = [...req.url.pathSegments];
        while (tail.isNotEmpty && tail.last.isEmpty) {
          tail.removeLast();
        }
        if (tail.isEmpty) return _serviceCatalog(req);
        final serviceName = tail[0];
        final service = store.serviceByName(serviceName);
        if (service == null) {
          return _notFound('Service "$serviceName" does not exist');
        }
        if (tail.length == 1) return _serviceDocument(req, service);
        final second = tail[1];
        if (second == r'$metadata') return _metadata(req, service);

        final keyMatch =
            RegExp(r'^([A-Za-z_][\w]*)\((.*)\)$').firstMatch(second);
        String entitySetName;
        String? keyExpr;
        if (keyMatch != null) {
          entitySetName = keyMatch.group(1)!;
          keyExpr = keyMatch.group(2);
        } else {
          entitySetName = second;
        }

        final entitySet = service.entitySetByName(entitySetName);
        if (entitySet == null) {
          return _notFound(
              'EntitySet "$entitySetName" not found in $serviceName');
        }
        final entityType = service.entityTypeByName(entitySet.entityTypeName);
        if (entityType == null) {
          return _internal(
              'EntityType "${entitySet.entityTypeName}" missing for set $entitySetName');
        }

        // Tail segments after the set name: count, value, property access.
        if (tail.length >= 3 && keyExpr == null && tail[2] == r'$count') {
          return _setCount(req, entitySet, entityType);
        }

        if (keyExpr != null) {
          return _handleSingle(req, service, entitySet, entityType, keyExpr,
              extra: tail.skip(2).toList());
        }
        return _handleCollection(req, service, entitySet, entityType);
      };

  Response _serviceCatalog(Request req) {
    final base = _baseUrl(req);
    return _json(<String, dynamic>{
      '@odata.context': '$base/sap/opu/odata4/sap/\$metadata',
      'value': [
        for (final s in store.services)
          <String, dynamic>{
            'name': s.name,
            'url': '${s.name}/',
            'kind': 'Service',
            'title': s.description.isEmpty ? s.name : s.description,
          },
      ],
    });
  }

  Response _serviceDocument(Request req, GatewayService s) {
    final base = _baseUrl(req);
    return _json(<String, dynamic>{
      '@odata.context':
          '$base/sap/opu/odata4/sap/${s.name}/\$metadata',
      'value': [
        for (final es in s.entitySets)
          <String, dynamic>{
            'name': es.name,
            'kind': 'EntitySet',
            'url': es.name,
          },
      ],
    });
  }

  Response _metadata(Request req, GatewayService s) {
    final buf = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="utf-8"?>')
      ..writeln(
          '<edmx:Edmx Version="4.0" xmlns:edmx="http://docs.oasis-open.org/odata/ns/edmx">')
      ..writeln('  <edmx:DataServices>')
      ..writeln(
          '    <Schema Namespace="${s.namespace}" xmlns="http://docs.oasis-open.org/odata/ns/edm">');
    for (final t in s.entityTypes) {
      buf.writeln('      <EntityType Name="${t.name}">');
      if (t.keys.isNotEmpty) {
        buf.writeln('        <Key>');
        for (final k in t.keys) {
          buf.writeln('          <PropertyRef Name="$k"/>');
        }
        buf.writeln('        </Key>');
      }
      for (final p in t.properties) {
        final attrs = <String>[
          'Name="${p.name}"',
          'Type="${p.edmType}"',
          'Nullable="${p.nullable}"',
          if (p.maxLength != null) 'MaxLength="${p.maxLength}"',
          if (p.precision != null) 'Precision="${p.precision}"',
          if (p.scale != null) 'Scale="${p.scale}"',
        ];
        buf.writeln('        <Property ${attrs.join(' ')} />');
      }
      buf.writeln('      </EntityType>');
    }
    buf.writeln('      <EntityContainer Name="${s.name}_Container">');
    for (final es in s.entitySets) {
      buf.writeln(
          '        <EntitySet Name="${es.name}" EntityType="${s.namespace}.${es.entityTypeName}"/>');
    }
    buf
      ..writeln('      </EntityContainer>')
      ..writeln('    </Schema>')
      ..writeln('  </edmx:DataServices>')
      ..writeln('</edmx:Edmx>');
    return Response.ok(buf.toString(), headers: {
      'content-type': 'application/xml; charset=utf-8',
      'odata-version': '4.0',
    });
  }

  Response _setCount(Request req, EntitySet es, EntityType et) {
    final qp = req.url.queryParameters;
    var rows = es.rows.toList();
    final filterExpr = qp['\$filter'];
    if (filterExpr != null && filterExpr.trim().isNotEmpty) {
      try {
        final filter = FilterParser(filterExpr).parse();
        rows = rows.where((r) => filter.evaluate(r) == true).toList();
      } catch (e) {
        return _bad('Invalid \$filter: $e');
      }
    }
    return Response.ok('${rows.length}', headers: {
      'content-type': 'text/plain; charset=utf-8',
      'odata-version': '4.0',
    });
  }

  Future<Response> _handleCollection(
      Request req, GatewayService svc, EntitySet es, EntityType et) async {
    switch (req.method) {
      case 'GET':
        return _queryCollection(req, svc, es, et);
      case 'POST':
        final body = jsonDecode(await req.readAsString());
        if (body is! Map<String, dynamic>) {
          return _bad('Body must be a JSON object');
        }
        final keyVals = et.keys
            .map((k) => body[k]?.toString())
            .where((v) => v != null && v.isNotEmpty)
            .toList();
        if (keyVals.length != et.keys.length) {
          return _bad('Missing key field(s): ${et.keys}');
        }
        if (_indexByKeys(es, et, body) >= 0) {
          return _conflict('Entity with that key already exists');
        }
        es.rows.add(Map<String, dynamic>.from(body));
        await store.save();
        return _json(_wrapEntity(req, svc, es, et, body), status: 201);
      default:
        return Response(405, body: 'Method not allowed');
    }
  }

  Future<Response> _handleSingle(Request req, GatewayService svc, EntitySet es,
      EntityType et, String keyExpr,
      {required List<String> extra}) async {
    final keys = _parseKeyExpr(keyExpr, et);
    if (keys == null) {
      return _bad('Could not parse key "$keyExpr" for ${es.name}');
    }
    final idx = _indexByKeys(es, et, keys);
    if (idx < 0) return _notFound('Entity not found');

    // /<set>(key)/<Property> — primitive value access
    if (extra.length >= 2) {
      final prop = extra[1];
      final tail = extra.skip(2).toList();
      if (et.propertyByName(prop) == null) {
        return _notFound('Property "$prop" not found on ${et.name}');
      }
      final row = es.rows[idx];
      if (tail.isNotEmpty && tail[0] == r'$value') {
        return Response.ok(row[prop]?.toString() ?? '',
            headers: {'content-type': 'text/plain; charset=utf-8'});
      }
      return _json(<String, dynamic>{
        '@odata.context':
            '${_baseUrl(req)}/sap/opu/odata4/sap/${svc.name}/\$metadata#${es.name}($prop)',
        'value': row[prop],
      });
    }

    switch (req.method) {
      case 'GET':
        return _json(_wrapEntity(req, svc, es, et, es.rows[idx]));
      case 'PUT':
      case 'PATCH':
        final body = jsonDecode(await req.readAsString());
        if (body is! Map<String, dynamic>) {
          return _bad('Body must be a JSON object');
        }
        es.rows[idx]
          ..addAll(body)
          ..addAll(keys);
        await store.save();
        return Response(204);
      case 'DELETE':
        es.rows.removeAt(idx);
        await store.save();
        return Response(204);
      default:
        return Response(405, body: 'Method not allowed');
    }
  }

  Response _queryCollection(
      Request req, GatewayService svc, EntitySet es, EntityType et) {
    final qp = req.url.queryParameters;
    var rows = es.rows.toList();

    final filterExpr = qp['\$filter'];
    if (filterExpr != null && filterExpr.trim().isNotEmpty) {
      try {
        final filter = FilterParser(filterExpr).parse();
        rows = rows.where((r) => filter.evaluate(r) == true).toList();
      } catch (e) {
        return _bad('Invalid \$filter: $e');
      }
    }

    final orderBy = qp['\$orderby'];
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

    final skip = int.tryParse(qp['\$skip'] ?? '') ?? 0;
    final top = int.tryParse(qp['\$top'] ?? '');
    if (skip > 0) rows = rows.skip(skip).toList();
    if (top != null) rows = rows.take(top).toList();

    final selectExpr = qp['\$select'];
    List<String>? selectFields;
    if (selectExpr != null &&
        selectExpr.trim().isNotEmpty &&
        selectExpr.trim() != '*') {
      selectFields = selectExpr.split(',').map((s) => s.trim()).toList();
    }

    final base = _baseUrl(req);
    final wrappedRows = rows.map((r) {
      final row = selectFields == null
          ? r
          : <String, dynamic>{
              for (final f in selectFields) f: r[f],
            };
      return _wrapEntity(req, svc, es, et, row, isInner: true);
    }).toList();

    final response = <String, dynamic>{
      '@odata.context':
          '$base/sap/opu/odata4/sap/${svc.name}/\$metadata#${es.name}',
      if (qp['\$count']?.toLowerCase() == 'true') '@odata.count': total,
      'value': wrappedRows,
    };
    return _json(response);
  }

  Map<String, dynamic> _wrapEntity(Request req, GatewayService svc,
      EntitySet es, EntityType et, Map<String, dynamic> row,
      {bool isInner = false}) {
    final base = _baseUrl(req);
    final out = <String, dynamic>{
      if (!isInner)
        '@odata.context':
            '$base/sap/opu/odata4/sap/${svc.name}/\$metadata#${es.name}/\$entity',
      '@odata.id':
          '${es.name}(${_buildKeyForUri(et, row)})',
      '@odata.type': '#${svc.namespace}.${et.name}',
    };
    for (final p in et.properties) {
      if (row.containsKey(p.name)) out[p.name] = row[p.name];
    }
    for (final k in row.keys) {
      if (!out.containsKey(k) && !k.startsWith('@')) out[k] = row[k];
    }
    return out;
  }

  String _buildKeyForUri(EntityType et, Map<String, dynamic> row) {
    if (et.keys.length == 1) {
      return _formatKeyValue(row[et.keys.first]);
    }
    return et.keys.map((k) => '$k=${_formatKeyValue(row[k])}').join(',');
  }

  String _formatKeyValue(dynamic v) {
    if (v == null) return 'null';
    if (v is num) return v.toString();
    final s = v.toString();
    return "'${s.replaceAll("'", "''")}'";
  }

  Map<String, dynamic>? _parseKeyExpr(String expr, EntityType et) {
    final result = <String, dynamic>{};
    if (!expr.contains('=')) {
      if (et.keys.length != 1) return null;
      result[et.keys.first] = _unquote(expr.trim());
      return result;
    }
    for (final segment in _splitTopLevel(expr, ',')) {
      final eq = segment.indexOf('=');
      if (eq < 0) return null;
      final name = segment.substring(0, eq).trim();
      final value = segment.substring(eq + 1).trim();
      result[name] = _unquote(value);
    }
    return result;
  }

  List<String> _splitTopLevel(String s, String sep) {
    final out = <String>[];
    var depth = 0;
    var quoted = false;
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      final c = s[i];
      if (c == "'") quoted = !quoted;
      if (!quoted) {
        if (c == '(') depth++;
        if (c == ')') depth--;
        if (depth == 0 && c == sep) {
          out.add(buf.toString());
          buf.clear();
          continue;
        }
      }
      buf.write(c);
    }
    out.add(buf.toString());
    return out;
  }

  dynamic _unquote(String s) {
    final t = s.trim();
    if (t.length >= 2 && t.startsWith("'") && t.endsWith("'")) {
      return t.substring(1, t.length - 1).replaceAll("''", "'");
    }
    return t;
  }

  int _indexByKeys(EntitySet es, EntityType et, Map<String, dynamic> keys) {
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

  String _baseUrl(Request req) {
    final scheme = req.requestedUri.scheme;
    final host = req.requestedUri.host;
    final port = req.requestedUri.port;
    final defaultPort = (scheme == 'https' && port == 443) ||
        (scheme == 'http' && port == 80) ||
        port == 0;
    return defaultPort ? '$scheme://$host' : '$scheme://$host:$port';
  }

  Response _json(Object body, {int status = 200}) => Response(
        status,
        body: jsonEncode(body),
        headers: const {
          'content-type': 'application/json; charset=utf-8',
          'odata-version': '4.0',
        },
      );

  Response _notFound(String msg) =>
      Response.notFound(jsonEncode(_v4Error('404', msg)),
          headers: const {'content-type': 'application/json'});
  Response _bad(String msg) => Response.badRequest(
      body: jsonEncode(_v4Error('400', msg)),
      headers: const {'content-type': 'application/json'});
  Response _conflict(String msg) => Response(409,
      body: jsonEncode(_v4Error('409', msg)),
      headers: const {'content-type': 'application/json'});
  Response _internal(String msg) => Response.internalServerError(
      body: jsonEncode(_v4Error('500', msg)),
      headers: const {'content-type': 'application/json'});

  Map<String, dynamic> _v4Error(String code, String msg) => {
        'error': {'code': code, 'message': msg},
      };
}
