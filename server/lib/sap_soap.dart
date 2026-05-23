import 'dart:convert';

import 'package:shelf/shelf.dart';

import 'filter.dart';
import 'models.dart';
import 'store.dart';

/// SOAP / BAPI / RFC simulation. Mounted at `/sap/bc/srt/`:
///
///   GET  /sap/bc/srt/             — list of exposed BAPI/RFC functions
///   GET  /sap/bc/srt/<fn>?wsdl    — WSDL stub
///   POST /sap/bc/srt/<fn>         — SOAP envelope OR JSON-RFC body
///
/// `<fn>` accepts a handful of canonical SAP BAPIs (`BAPI_CUSTOMER_GETLIST`,
/// `BAPI_MATERIAL_GETLIST`, `BAPI_VENDOR_GETLIST`, `BAPI_PO_GETITEMS`,
/// `BAPI_SALESORDER_GETLIST`) plus the generic `RFC_READ_TABLE` and
/// `RFC_GET_TABLE_ENTRIES` functions for arbitrary EntitySet reads.
///
/// JSON request bodies (when `Content-Type: application/json`) get a JSON
/// response so non-XML clients can drive the same surface easily.
class SapSoapHandler {
  SapSoapHandler(this.store);

  final GatewayStore store;

  static const _bapiToEntitySet = <String, _BapiBinding>{
    'BAPI_CUSTOMER_GETLIST':
        _BapiBinding('ZSALES_SRV', 'CustomerSet', 'CustomerList'),
    'BAPI_MATERIAL_GETLIST':
        _BapiBinding('ZMATERIAL_SRV', 'MaterialSet', 'MaterialList'),
    'BAPI_VENDOR_GETLIST':
        _BapiBinding('ZVENDOR_SRV', 'VendorSet', 'VendorList'),
    'BAPI_PO_GETITEMS':
        _BapiBinding('ZPURCH_SRV', 'PurchaseOrderSet', 'PurchaseOrderList'),
    'BAPI_SALESORDER_GETLIST':
        _BapiBinding('ZSALES_SRV', 'SalesOrderSet', 'SalesOrderList'),
    'BAPI_SALESORDER_GETITEMS':
        _BapiBinding('ZSALES_SRV', 'SalesOrderItemSet', 'SalesOrderItemList'),
    'BAPI_GL_ACC_GETLIST':
        _BapiBinding('ZFIN_SRV', 'GLAccountSet', 'GLAccountList'),
    'BAPI_COSTCENTER_GETLIST':
        _BapiBinding('ZFIN_SRV', 'CostCenterSet', 'CostCenterList'),
    'BAPI_MATERIAL_STOCK_REQ_LIST':
        _BapiBinding('ZSTOCK_SRV', 'StockSet', 'StockList'),
    'BAPI_PRICES_CONDITIONS':
        _BapiBinding('ZPRICE_SRV', 'ConditionSet', 'ConditionList'),
  };

  Handler get handler => (Request req) async {
        final tail = [...req.url.pathSegments];
        while (tail.isNotEmpty && tail.last.isEmpty) {
          tail.removeLast();
        }
        if (tail.isEmpty) {
          if (req.method == 'GET') return _listBapis();
          return Response(405, body: 'Method not allowed');
        }
        final fn = tail[0].toUpperCase();
        if (req.method == 'GET') {
          if (req.url.queryParameters.containsKey('wsdl') ||
              req.url.query.toLowerCase() == 'wsdl') {
            return _wsdlFor(req, fn);
          }
          return _bapiDescription(fn);
        }
        if (req.method != 'POST') {
          return Response(405, body: 'Method not allowed');
        }
        return _invoke(req, fn);
      };

  Response _listBapis() {
    final fns = [
      for (final e in _bapiToEntitySet.entries)
        {
          'name': e.key,
          'service': e.value.service,
          'entitySet': e.value.entitySet,
          'tableName': e.value.tableName,
        },
      {
        'name': 'RFC_READ_TABLE',
        'description':
            'Generic table read. POST {"QUERY_TABLE":"<EntitySet>","OPTIONS":["..."],"FIELDS":["..."]}',
      },
      {
        'name': 'RFC_GET_TABLE_ENTRIES',
        'description': 'Returns rows from any configured EntitySet by name.',
      },
    ];
    return _json({'functions': fns});
  }

  Response _bapiDescription(String fn) {
    if (fn == 'RFC_READ_TABLE' || fn == 'RFC_GET_TABLE_ENTRIES') {
      return _json({
        'name': fn,
        'description':
            'Generic ABAP table-read RFC. Use POST with QUERY_TABLE / OPTIONS / FIELDS to invoke.',
        'parameters': const {
          'QUERY_TABLE': 'EntitySet name (e.g. CustomerSet)',
          'OPTIONS': 'List of OData-style filter clauses joined by AND',
          'FIELDS': 'List of fields to return; empty = all',
          'ROWCOUNT': 'Max rows',
          'ROWSKIPS': 'Rows to skip from start',
        },
      });
    }
    final b = _bapiToEntitySet[fn];
    if (b == null) return _nf('Unknown BAPI: $fn');
    return _json({
      'name': fn,
      'service': b.service,
      'entitySet': b.entitySet,
      'tableName': b.tableName,
    });
  }

  Response _wsdlFor(Request req, String fn) {
    final target =
        '${_baseUrl(req)}/sap/bc/srt/$fn';
    final buf = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="utf-8"?>')
      ..writeln(
          '<wsdl:definitions name="$fn" targetNamespace="urn:sap-com:document:sap:rfc:functions"')
      ..writeln(
          '  xmlns:wsdl="http://schemas.xmlsoap.org/wsdl/" xmlns:tns="urn:sap-com:document:sap:rfc:functions"')
      ..writeln(
          '  xmlns:soap="http://schemas.xmlsoap.org/wsdl/soap/" xmlns:xsd="http://www.w3.org/2001/XMLSchema">')
      ..writeln('  <wsdl:service name="$fn">')
      ..writeln('    <wsdl:port name="${fn}Port" binding="tns:${fn}Binding">')
      ..writeln('      <soap:address location="$target"/>')
      ..writeln('    </wsdl:port>')
      ..writeln('  </wsdl:service>')
      ..writeln('</wsdl:definitions>');
    return Response.ok(buf.toString(),
        headers: const {'content-type': 'application/xml; charset=utf-8'});
  }

  Future<Response> _invoke(Request req, String fn) async {
    final ctype = (req.headers['content-type'] ?? '').toLowerCase();
    final body = await req.readAsString();
    final isJson = ctype.contains('json') ||
        body.trimLeft().startsWith('{') ||
        body.trimLeft().startsWith('[');

    Map<String, dynamic> params;
    if (isJson) {
      if (body.isEmpty) {
        params = const {};
      } else {
        final decoded = jsonDecode(body);
        if (decoded is! Map<String, dynamic>) {
          return _bad('JSON body must be an object');
        }
        params = decoded;
      }
    } else {
      params = _parseSoapEnvelope(body);
    }

    final result = _execute(fn, params);
    if (result.error != null) {
      if (isJson) {
        return _bad(result.error!);
      }
      return _soapFault(result.error!);
    }
    if (isJson) {
      return _json({
        'function': fn,
        'parameters': params,
        'tableName': result.tableName,
        'rowCount': result.rows.length,
        'rows': result.rows,
      });
    }
    return _soapResponse(fn, result);
  }

  _BapiResult _execute(String fn, Map<String, dynamic> params) {
    if (fn == 'RFC_READ_TABLE' || fn == 'RFC_GET_TABLE_ENTRIES') {
      final tableName =
          (params['QUERY_TABLE'] ?? params['TABLE'] ?? params['ENTITY_SET'])
              ?.toString();
      if (tableName == null || tableName.isEmpty) {
        return _BapiResult.error(
            'QUERY_TABLE / TABLE / ENTITY_SET parameter required');
      }
      final binding = _findEntitySetByName(tableName);
      if (binding == null) return _BapiResult.error('Unknown table $tableName');
      return _readTable(
        service: binding.$1,
        entitySet: binding.$2,
        entityType: binding.$3,
        tableName: tableName,
        options: ((params['OPTIONS'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
        fields: ((params['FIELDS'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
        rowCount: _asInt(params['ROWCOUNT']),
        rowSkips: _asInt(params['ROWSKIPS']) ?? 0,
      );
    }

    final bound = _bapiToEntitySet[fn];
    if (bound == null) return _BapiResult.error('Unknown BAPI / RFC: $fn');
    final svc = store.serviceByName(bound.service);
    if (svc == null) {
      return _BapiResult.error('Service ${bound.service} not configured');
    }
    final es = svc.entitySetByName(bound.entitySet);
    final et = es == null ? null : svc.entityTypeByName(es.entityTypeName);
    if (es == null || et == null) {
      return _BapiResult.error(
          '${bound.entitySet} missing from ${bound.service}');
    }
    return _readTable(
      service: svc,
      entitySet: es,
      entityType: et,
      tableName: bound.tableName,
      options: ((params['OPTIONS'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList(),
      fields: ((params['FIELDS'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList(),
      rowCount: _asInt(params['MAXROWS']) ?? _asInt(params['ROWCOUNT']),
      rowSkips: _asInt(params['ROWSKIPS']) ?? 0,
    );
  }

  _BapiResult _readTable({
    required GatewayService service,
    required EntitySet entitySet,
    required EntityType entityType,
    required String tableName,
    required List<String> options,
    required List<String> fields,
    int? rowCount,
    int rowSkips = 0,
  }) {
    var rows = entitySet.rows.toList();
    if (options.isNotEmpty) {
      final joined = options.map((o) => '($o)').join(' and ');
      try {
        final f = FilterParser(joined).parse();
        rows = rows.where((r) => f.evaluate(r) == true).toList();
      } catch (e) {
        return _BapiResult.error('invalid OPTIONS expression: $e');
      }
    }
    if (rowSkips > 0) rows = rows.skip(rowSkips).toList();
    if (rowCount != null && rowCount > 0) rows = rows.take(rowCount).toList();
    if (fields.isNotEmpty) {
      rows = [
        for (final r in rows) {for (final f in fields) f: r[f]},
      ];
    }
    return _BapiResult(
      tableName: tableName,
      service: service,
      entitySet: entitySet,
      entityType: entityType,
      rows: rows,
    );
  }

  (GatewayService, EntitySet, EntityType)? _findEntitySetByName(String name) {
    for (final s in store.services) {
      final es = s.entitySetByName(name);
      if (es == null) continue;
      final et = s.entityTypeByName(es.entityTypeName);
      if (et == null) continue;
      return (s, es, et);
    }
    return null;
  }

  Map<String, dynamic> _parseSoapEnvelope(String body) {
    // Pull QUERY_TABLE / OPTIONS / FIELDS-style children. Good enough for a
    // mock — accepts any SOAP envelope, walks innermost element children.
    final params = <String, dynamic>{};
    final scalarRe = RegExp(
        r'<(?:\w+:)?(QUERY_TABLE|TABLE|ENTITY_SET|ROWCOUNT|ROWSKIPS|MAXROWS|DELIMITER)>([^<]*)</(?:\w+:)?\1>',
        caseSensitive: false);
    for (final m in scalarRe.allMatches(body)) {
      params[m.group(1)!.toUpperCase()] = m.group(2);
    }
    final listRe = RegExp(
        r'<(?:\w+:)?(OPTIONS|FIELDS)>([\s\S]*?)</(?:\w+:)?\1>',
        caseSensitive: false);
    for (final m in listRe.allMatches(body)) {
      final inner = m.group(2) ?? '';
      final items = RegExp(r'<(?:\w+:)?item>([\s\S]*?)</(?:\w+:)?item>',
              caseSensitive: false)
          .allMatches(inner)
          .map((mm) => _decodeXml(
              (mm.group(1) ?? '').replaceAll(RegExp(r'<[^>]+>'), '').trim()))
          .toList();
      params[m.group(1)!.toUpperCase()] = items;
    }
    return params;
  }

  Response _soapResponse(String fn, _BapiResult r) {
    final buf = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="utf-8"?>')
      ..writeln(
          '<soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/"')
      ..writeln('  xmlns:rfc="urn:sap-com:document:sap:rfc:functions">')
      ..writeln('  <soap:Body>')
      ..writeln('    <rfc:${fn}Response>')
      ..writeln('      <DATA>');
    for (final row in r.rows) {
      buf.writeln('        <item>');
      row.forEach((k, v) {
        buf.writeln('          <$k>${_xml(v?.toString() ?? '')}</$k>');
      });
      buf.writeln('        </item>');
    }
    buf
      ..writeln('      </DATA>')
      ..writeln('      <RETURN>')
      ..writeln('        <TYPE>S</TYPE>')
      ..writeln('        <ID>00</ID>')
      ..writeln('        <NUMBER>000</NUMBER>')
      ..writeln(
          '        <MESSAGE>${r.rows.length} rows read from ${r.tableName}</MESSAGE>')
      ..writeln('      </RETURN>')
      ..writeln('    </rfc:${fn}Response>')
      ..writeln('  </soap:Body>')
      ..writeln('</soap:Envelope>');
    return Response.ok(buf.toString(),
        headers: const {'content-type': 'text/xml; charset=utf-8'});
  }

  Response _soapFault(String msg) {
    final body = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="utf-8"?>')
      ..writeln(
          '<soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">')
      ..writeln('  <soap:Body>')
      ..writeln('    <soap:Fault>')
      ..writeln('      <faultcode>Client</faultcode>')
      ..writeln('      <faultstring>${_xml(msg)}</faultstring>')
      ..writeln('    </soap:Fault>')
      ..writeln('  </soap:Body>')
      ..writeln('</soap:Envelope>');
    return Response(500,
        body: body.toString(),
        headers: const {'content-type': 'text/xml; charset=utf-8'});
  }

  Response _json(Object body, {int status = 200}) => Response(
        status,
        body: jsonEncode(body),
        headers: const {'content-type': 'application/json; charset=utf-8'},
      );

  Response _nf(String msg) => Response.notFound(jsonEncode({'error': msg}),
      headers: const {'content-type': 'application/json'});
  Response _bad(String msg) => Response.badRequest(
      body: jsonEncode({'error': msg}),
      headers: const {'content-type': 'application/json'});

  int? _asInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
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

  String _xml(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  String _decodeXml(String s) => s
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&amp;', '&');
}

class _BapiBinding {
  const _BapiBinding(this.service, this.entitySet, this.tableName);
  final String service;
  final String entitySet;
  final String tableName;
}

class _BapiResult {
  _BapiResult({
    required this.tableName,
    required this.service,
    required this.entitySet,
    required this.entityType,
    required this.rows,
  }) : error = null;

  _BapiResult.error(this.error)
      : tableName = '',
        service = null,
        entitySet = null,
        entityType = null,
        rows = const [];

  final String tableName;
  final GatewayService? service;
  final EntitySet? entitySet;
  final EntityType? entityType;
  final List<Map<String, dynamic>> rows;
  final String? error;
}
