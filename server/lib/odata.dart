import 'dart:convert';

import 'package:shelf/shelf.dart';

import 'models.dart';
import 'store.dart';

/// OData v2 surface. URL shape mirrors SAP NetWeaver Gateway:
///
///   /sap/opu/odata/sap/                            -> service catalog
///   /sap/opu/odata/sap/<SVC>/                      -> service document
///   /sap/opu/odata/sap/<SVC>/$metadata             -> EDMX schema
///   /sap/opu/odata/sap/<SVC>/<EntitySet>           -> list (GET, POST)
///   /sap/opu/odata/sap/<SVC>/<EntitySet>(<key>)    -> single (GET, PUT, DELETE)
class ODataHandler {
  ODataHandler(this.store);

  final GatewayStore store;

  /// Mounted at `/sap/opu/odata/sap/` — by the time we get here the prefix is
  /// stripped, so `req.url.pathSegments[0]` is already the service name. A
  /// trailing slash produces an empty final segment which we discard.
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
        if (second == r'$metadata') return _metadata(service);

        // EntitySet (possibly with key segment baked into the path component).
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

        if (keyExpr != null) {
          return _handleSingle(req, service, entitySet, entityType, keyExpr);
        }
        return _handleCollection(req, service, entitySet, entityType);
      };

  // ─── Routes ────────────────────────────────────────────────────────────

  Response _serviceCatalog(Request req) {
    final services = store.services
        .map((s) => <String, dynamic>{
              'name': s.name,
              'url': '${_baseUrl(req)}/sap/opu/odata/sap/${s.name}/',
              'description': s.description,
            })
        .toList();
    return _json(<String, dynamic>{
      'd': <String, dynamic>{
        'EntitySets': store.services.map((s) => s.name).toList(),
        'Services': services,
      },
    });
  }

  Response _serviceDocument(Request req, GatewayService s) {
    final fmt = req.url.queryParameters['\$format'];
    if (fmt == 'json') {
      return _json(<String, dynamic>{
        'd': <String, dynamic>{
          'EntitySets': s.entitySets.map((e) => e.name).toList(),
        },
      });
    }
    final buf = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="utf-8"?>')
      ..writeln(
          '<service xml:base="${_baseUrl(req)}/sap/opu/odata/sap/${s.name}/"')
      ..writeln('         xmlns="http://www.w3.org/2007/app"')
      ..writeln('         xmlns:atom="http://www.w3.org/2005/Atom">')
      ..writeln('  <workspace>')
      ..writeln(
          '    <atom:title>${_xml(s.description.isEmpty ? s.name : s.description)}</atom:title>');
    for (final es in s.entitySets) {
      buf
        ..writeln('    <collection href="${es.name}">')
        ..writeln('      <atom:title>${es.name}</atom:title>')
        ..writeln('    </collection>');
    }
    buf
      ..writeln('  </workspace>')
      ..writeln('</service>');
    return Response.ok(buf.toString(),
        headers: {'content-type': 'application/xml; charset=utf-8'});
  }

  Response _metadata(GatewayService s) {
    final buf = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="utf-8"?>')
      ..writeln(
          '<edmx:Edmx Version="1.0" xmlns:edmx="http://schemas.microsoft.com/ado/2007/06/edmx">')
      ..writeln(
          '  <edmx:DataServices m:DataServiceVersion="2.0" xmlns:m="http://schemas.microsoft.com/ado/2007/08/dataservices/metadata">')
      ..writeln(
          '    <Schema Namespace="${s.namespace}" xmlns="http://schemas.microsoft.com/ado/2008/09/edm" xmlns:sap="http://www.sap.com/Protocols/SAPData">');
    for (final t in s.entityTypes) {
      buf.writeln(
          '      <EntityType Name="${t.name}" sap:content-version="1">');
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
          if (p.label != null) 'sap:label="${_xml(p.label!)}"',
        ];
        buf.writeln('        <Property ${attrs.join(' ')} />');
      }
      buf.writeln('      </EntityType>');
    }
    buf.writeln(
        '      <EntityContainer Name="${s.name}_Entities" m:IsDefaultEntityContainer="true">');
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
      'dataserviceversion': '2.0',
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
        if (_findByKeys(es, et, body) != null) {
          return _conflict('Entity with that key already exists');
        }
        es.rows.add(Map<String, dynamic>.from(body));
        await store.save();
        return _json(<String, dynamic>{
          'd': _wrapEntity(req, svc, es, et, body),
        }, status: 201);
      default:
        return Response(405, body: 'Method not allowed');
    }
  }

  Future<Response> _handleSingle(Request req, GatewayService svc, EntitySet es,
      EntityType et, String keyExpr) async {
    final keys = _parseKeyExpr(keyExpr, et);
    if (keys == null) {
      return _bad('Could not parse key "$keyExpr" for ${es.name}');
    }
    final idx = _indexByKeys(es, et, keys);
    if (idx < 0) return _notFound('Entity not found');

    switch (req.method) {
      case 'GET':
        return _json(<String, dynamic>{
          'd': _wrapEntity(req, svc, es, et, es.rows[idx]),
        });
      case 'PUT':
      case 'PATCH':
      case 'MERGE':
        final body = jsonDecode(await req.readAsString());
        if (body is! Map<String, dynamic>)
          return _bad('Body must be a JSON object');
        es.rows[idx]
          ..addAll(body)
          ..addAll(keys); // keys are immutable
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

  // ─── $filter / $orderby / paging ───────────────────────────────────────

  Response _queryCollection(
      Request req, GatewayService svc, EntitySet es, EntityType et) {
    final qp = req.url.queryParameters;
    var rows = es.rows.toList();

    // $filter
    final filterExpr = qp['\$filter'];
    if (filterExpr != null && filterExpr.trim().isNotEmpty) {
      try {
        final filter = _FilterParser(filterExpr).parse();
        rows = rows.where((r) => filter.evaluate(r) == true).toList();
      } catch (e) {
        return _bad('Invalid \$filter: $e');
      }
    }

    // $orderby
    final orderBy = qp['\$orderby'];
    if (orderBy != null && orderBy.trim().isNotEmpty) {
      final parts = orderBy.split(',').map((s) => s.trim()).toList();
      rows.sort((a, b) {
        for (final part in parts) {
          final tokens = part.split(RegExp(r'\s+'));
          final field = tokens[0];
          final desc = tokens.length > 1 && tokens[1].toLowerCase() == 'desc';
          final av = a[field];
          final bv = b[field];
          final cmp = _compareValues(av, bv);
          if (cmp != 0) return desc ? -cmp : cmp;
        }
        return 0;
      });
    }

    final totalBeforePaging = rows.length;

    // $skip / $top
    final skip = int.tryParse(qp['\$skip'] ?? '') ?? 0;
    final top = int.tryParse(qp['\$top'] ?? '');
    if (skip > 0) rows = rows.skip(skip).toList();
    if (top != null) rows = rows.take(top).toList();

    // $select
    final selectExpr = qp['\$select'];
    List<String>? selectFields;
    if (selectExpr != null &&
        selectExpr.trim().isNotEmpty &&
        selectExpr.trim() != '*') {
      selectFields = selectExpr.split(',').map((s) => s.trim()).toList();
    }

    final wrappedRows = rows.map((r) {
      final row = selectFields == null
          ? r
          : <String, dynamic>{
              for (final f in selectFields) f: r[f],
            };
      return _wrapEntity(req, svc, es, et, row);
    }).toList();

    final response = <String, dynamic>{'results': wrappedRows};
    if (qp['\$inlinecount']?.toLowerCase() == 'allpages') {
      response['__count'] = totalBeforePaging.toString();
    }
    return _json(<String, dynamic>{'d': response});
  }

  // ─── Helpers ────────────────────────────────────────────────────────────

  Map<String, dynamic> _wrapEntity(Request req, GatewayService svc,
      EntitySet es, EntityType et, Map<String, dynamic> row) {
    final keyPart = _buildKeyForUri(et, row);
    final out = <String, dynamic>{
      '__metadata': <String, dynamic>{
        'uri':
            '${_baseUrl(req)}/sap/opu/odata/sap/${svc.name}/${es.name}($keyPart)',
        'type': '${svc.namespace}.${et.name}',
      },
    };
    for (final p in et.properties) {
      if (row.containsKey(p.name)) out[p.name] = row[p.name];
    }
    // Any row fields the entity-type doesn't yet know about (e.g. just after a
    // property was deleted) are still surfaced so the admin UI can see them.
    for (final k in row.keys) {
      if (!out.containsKey(k) && k != '__metadata') out[k] = row[k];
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
    // Always quote strings — SAP keys are nearly always strings.
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

  Map<String, dynamic>? _findByKeys(
      EntitySet es, EntityType et, Map<String, dynamic> body) {
    final i = _indexByKeys(es, et, body);
    return i >= 0 ? es.rows[i] : null;
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
          'dataserviceversion': '2.0',
        },
      );

  Response _notFound(String msg) =>
      Response.notFound(jsonEncode(_odataError('404', msg)),
          headers: const {'content-type': 'application/json'});
  Response _bad(String msg) => Response.badRequest(
      body: jsonEncode(_odataError('400', msg)),
      headers: const {'content-type': 'application/json'});
  Response _conflict(String msg) => Response(409,
      body: jsonEncode(_odataError('409', msg)),
      headers: const {'content-type': 'application/json'});
  Response _internal(String msg) => Response.internalServerError(
      body: jsonEncode(_odataError('500', msg)),
      headers: const {'content-type': 'application/json'});

  Map<String, dynamic> _odataError(String code, String msg) => {
        'error': {
          'code': code,
          'message': {'lang': 'en', 'value': msg},
        }
      };

  String _xml(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}

// ─── Filter parser ────────────────────────────────────────────────────────

abstract class _FilterNode {
  bool? evaluate(Map<String, dynamic> row);
}

class _BinOp implements _FilterNode {
  _BinOp(this.op, this.left, this.right);
  final String op;
  final _FilterNode left;
  final _FilterNode right;

  @override
  bool? evaluate(Map<String, dynamic> row) {
    if (op == 'and')
      return (left.evaluate(row) ?? false) && (right.evaluate(row) ?? false);
    if (op == 'or')
      return (left.evaluate(row) ?? false) || (right.evaluate(row) ?? false);
    final l = (left as _Value).value(row);
    final r = (right as _Value).value(row);
    return _compare(op, l, r);
  }

  static bool _compare(String op, dynamic l, dynamic r) {
    final cmp = _compareValues(l, r);
    switch (op) {
      case 'eq':
        return cmp == 0;
      case 'ne':
        return cmp != 0;
      case 'gt':
        return cmp > 0;
      case 'ge':
        return cmp >= 0;
      case 'lt':
        return cmp < 0;
      case 'le':
        return cmp <= 0;
    }
    return false;
  }
}

abstract class _Value implements _FilterNode {
  dynamic value(Map<String, dynamic> row);
  @override
  bool? evaluate(Map<String, dynamic> row) {
    final v = value(row);
    if (v is bool) return v;
    return null;
  }
}

class _Lit extends _Value {
  _Lit(this.v);
  final dynamic v;
  @override
  dynamic value(Map<String, dynamic> row) => v;
}

class _Field extends _Value {
  _Field(this.name);
  final String name;
  @override
  dynamic value(Map<String, dynamic> row) => row[name];
}

class _Func extends _Value {
  _Func(this.name, this.args);
  final String name;
  final List<_Value> args;
  @override
  dynamic value(Map<String, dynamic> row) {
    String? s(int i) => args[i].value(row)?.toString();
    switch (name) {
      case 'substringof':
        return (s(1) ?? '').contains(s(0) ?? '');
      case 'startswith':
        return (s(0) ?? '').startsWith(s(1) ?? '');
      case 'endswith':
        return (s(0) ?? '').endsWith(s(1) ?? '');
      case 'tolower':
        return (s(0) ?? '').toLowerCase();
      case 'toupper':
        return (s(0) ?? '').toUpperCase();
      case 'length':
        return (s(0) ?? '').length;
    }
    return null;
  }

  @override
  bool? evaluate(Map<String, dynamic> row) {
    final v = value(row);
    if (v is bool) return v;
    return null;
  }
}

int _compareValues(dynamic a, dynamic b) {
  if (a == null && b == null) return 0;
  if (a == null) return -1;
  if (b == null) return 1;
  if (a is num && b is num) return a.compareTo(b);
  final an = num.tryParse(a.toString());
  final bn = num.tryParse(b.toString());
  if (an != null && bn != null) return an.compareTo(bn);
  return a.toString().compareTo(b.toString());
}

class _FilterParser {
  _FilterParser(this._src);

  final String _src;
  int _pos = 0;

  _FilterNode parse() {
    final node = _parseOr();
    _skipWs();
    if (_pos != _src.length) {
      throw FormatException('Unexpected trailing input at $_pos');
    }
    return node;
  }

  _FilterNode _parseOr() {
    var left = _parseAnd();
    while (true) {
      _skipWs();
      if (_consumeKeyword('or')) {
        final right = _parseAnd();
        left = _BinOp('or', left, right);
      } else {
        return left;
      }
    }
  }

  _FilterNode _parseAnd() {
    var left = _parseCmp();
    while (true) {
      _skipWs();
      if (_consumeKeyword('and')) {
        final right = _parseCmp();
        left = _BinOp('and', left, right);
      } else {
        return left;
      }
    }
  }

  _FilterNode _parseCmp() {
    final left = _parsePrim();
    _skipWs();
    for (final op in const ['eq', 'ne', 'ge', 'le', 'gt', 'lt']) {
      if (_consumeKeyword(op)) {
        final right = _parsePrim();
        if (left is! _Value || right is! _Value) {
          throw FormatException('Operands of "$op" must be values');
        }
        return _BinOp(op, left, right);
      }
    }
    return left;
  }

  _FilterNode _parsePrim() {
    _skipWs();
    if (_pos >= _src.length) throw const FormatException('Unexpected end');
    final c = _src[_pos];
    if (c == '(') {
      _pos++;
      final inner = _parseOr();
      _skipWs();
      if (_pos >= _src.length || _src[_pos] != ')') {
        throw const FormatException('Missing ")"');
      }
      _pos++;
      return inner;
    }
    if (c == "'") return _parseString();
    if (RegExp(r'[0-9\-]').hasMatch(c)) return _parseNumber();

    final ident = _parseIdent();
    _skipWs();
    if (_pos < _src.length && _src[_pos] == '(') {
      // function call
      _pos++;
      final args = <_Value>[];
      _skipWs();
      if (_pos < _src.length && _src[_pos] != ')') {
        while (true) {
          final v = _parsePrim();
          if (v is! _Value) {
            throw const FormatException('Function arguments must be values');
          }
          args.add(v);
          _skipWs();
          if (_pos < _src.length && _src[_pos] == ',') {
            _pos++;
            continue;
          }
          break;
        }
      }
      _skipWs();
      if (_pos >= _src.length || _src[_pos] != ')') {
        throw FormatException('Missing ")" after function $ident');
      }
      _pos++;
      return _Func(ident, args);
    }
    // identifier as bare value
    if (ident == 'true') return _Lit(true);
    if (ident == 'false') return _Lit(false);
    if (ident == 'null') return _Lit(null);
    return _Field(ident);
  }

  _Value _parseString() {
    final buf = StringBuffer();
    _pos++; // opening quote
    while (_pos < _src.length) {
      final c = _src[_pos];
      if (c == "'") {
        // doubled quote escape
        if (_pos + 1 < _src.length && _src[_pos + 1] == "'") {
          buf.write("'");
          _pos += 2;
          continue;
        }
        _pos++;
        return _Lit(buf.toString());
      }
      buf.write(c);
      _pos++;
    }
    throw const FormatException('Unterminated string literal');
  }

  _Value _parseNumber() {
    final m = RegExp(r'-?\d+(\.\d+)?').matchAsPrefix(_src, _pos);
    if (m == null) throw const FormatException('Expected number');
    _pos = m.end;
    final txt = m.group(0)!;
    final n = num.parse(txt);
    return _Lit(n);
  }

  String _parseIdent() {
    final m = RegExp(r'[A-Za-z_][A-Za-z0-9_]*').matchAsPrefix(_src, _pos);
    if (m == null) {
      throw FormatException('Expected identifier at $_pos in "$_src"');
    }
    _pos = m.end;
    return m.group(0)!;
  }

  bool _consumeKeyword(String kw) {
    _skipWs();
    if (_pos + kw.length > _src.length) return false;
    final slice = _src.substring(_pos, _pos + kw.length).toLowerCase();
    if (slice != kw) return false;
    // must be followed by whitespace or EOF or ( - keyword must not be a prefix
    final next = _pos + kw.length < _src.length ? _src[_pos + kw.length] : ' ';
    if (RegExp(r'[A-Za-z0-9_]').hasMatch(next)) return false;
    _pos += kw.length;
    return true;
  }

  void _skipWs() {
    while (_pos < _src.length && _src[_pos].trim().isEmpty) {
      _pos++;
    }
  }
}
