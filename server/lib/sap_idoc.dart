import 'dart:convert';

import 'package:shelf/shelf.dart';

import 'models.dart';
import 'store.dart';

/// IDoc surface — the ALE/EDI interchange format that ECC 6 uses for batch
/// integration. Mounted at `/sap/idoc/`:
///
///   GET  /sap/idoc/types                              — list available IDoc types
///   GET  /sap/idoc/<TYPE>?format=xml|json             — full inbound IDoc batch
///   POST /sap/idoc/<TYPE>                             — accept inbound IDoc (echoes the IDOC_NUMBER it would receive on a real system)
///
/// Supported types match the SAP-out-of-the-box message catalogue:
///
///   DEBMAS06    — Customer master (from CustomerSet)
///   CREMAS05    — Vendor master (from VendorSet)
///   MATMAS05    — Material master (from MaterialSet)
///   ORDERS05    — Sales orders + items (SalesOrderSet + SalesOrderItemSet)
///   ORDERS_PURCH_05 — Purchase orders (PurchaseOrderSet)
///   COND_A05    — Pricing conditions (ConditionSet)
class SapIdocHandler {
  SapIdocHandler(this.store);

  final GatewayStore store;

  static const _types = <String, _IdocMapping>{
    'DEBMAS06': _IdocMapping(
      messageType: 'DEBMAS',
      basicType: 'DEBMAS06',
      service: 'ZSALES_SRV',
      headerSet: 'CustomerSet',
      itemSet: null,
      segment: 'E1KNA1M',
    ),
    'CREMAS05': _IdocMapping(
      messageType: 'CREMAS',
      basicType: 'CREMAS05',
      service: 'ZVENDOR_SRV',
      headerSet: 'VendorSet',
      itemSet: null,
      segment: 'E1LFA1M',
    ),
    'MATMAS05': _IdocMapping(
      messageType: 'MATMAS',
      basicType: 'MATMAS05',
      service: 'ZMATERIAL_SRV',
      headerSet: 'MaterialSet',
      itemSet: null,
      segment: 'E1MARAM',
    ),
    'ORDERS05': _IdocMapping(
      messageType: 'ORDERS',
      basicType: 'ORDERS05',
      service: 'ZSALES_SRV',
      headerSet: 'SalesOrderSet',
      itemSet: 'SalesOrderItemSet',
      segment: 'E1EDK01',
      itemSegment: 'E1EDP01',
      itemJoinKey: 'Vbeln',
    ),
    'ORDERS_PURCH_05': _IdocMapping(
      messageType: 'ORDERS',
      basicType: 'ORDERS05',
      service: 'ZPURCH_SRV',
      headerSet: 'PurchaseOrderSet',
      itemSet: null,
      segment: 'E1EDK01',
    ),
    'COND_A05': _IdocMapping(
      messageType: 'COND_A',
      basicType: 'COND_A05',
      service: 'ZPRICE_SRV',
      headerSet: 'ConditionSet',
      itemSet: null,
      segment: 'E1KOMG',
    ),
  };

  Handler get handler => (Request req) async {
        final tail = [...req.url.pathSegments];
        while (tail.isNotEmpty && tail.last.isEmpty) {
          tail.removeLast();
        }
        if (tail.isEmpty) return _listTypes();
        if (tail.length == 1 && tail[0] == 'types') return _listTypes();
        final typeName = tail[0].toUpperCase();
        final mapping = _types[typeName];
        if (mapping == null) return _nf('Unknown IDoc type: $typeName');

        if (req.method == 'GET') {
          return _emit(req, typeName, mapping);
        }
        if (req.method == 'POST') {
          return _acceptInbound(req, typeName, mapping);
        }
        return Response(405, body: 'Method not allowed');
      };

  Response _listTypes() => Response.ok(
        jsonEncode({
          'types': [
            for (final e in _types.entries)
              {
                'name': e.key,
                'messageType': e.value.messageType,
                'basicType': e.value.basicType,
                'service': e.value.service,
                'headerSet': e.value.headerSet,
                'itemSet': e.value.itemSet,
                'segment': e.value.segment,
              }
          ],
        }),
        headers: const {'content-type': 'application/json; charset=utf-8'},
      );

  Response _emit(Request req, String typeName, _IdocMapping m) {
    final svc = store.serviceByName(m.service);
    if (svc == null) return _err('Service ${m.service} missing', 500);
    final header = svc.entitySetByName(m.headerSet);
    if (header == null) return _err('${m.headerSet} missing', 500);
    final headerType = svc.entityTypeByName(header.entityTypeName);
    if (headerType == null) return _err('header type missing', 500);
    EntitySet? items;
    EntityType? itemsType;
    if (m.itemSet != null) {
      items = svc.entitySetByName(m.itemSet!);
      if (items != null) {
        itemsType = svc.entityTypeByName(items.entityTypeName);
      }
    }

    final format = (req.url.queryParameters['format'] ?? 'xml').toLowerCase();
    if (format == 'json') {
      return _emitJson(typeName, m, header, items);
    }
    return _emitXml(typeName, m, header, items);
  }

  Response _emitJson(
      String typeName, _IdocMapping m, EntitySet header, EntitySet? items) {
    final docs = <Map<String, dynamic>>[];
    var counter = 1;
    for (final row in header.rows) {
      final docNumber = _docNumber(counter++);
      final segs = <Map<String, dynamic>>[
        {'segment': m.segment, 'fields': Map<String, dynamic>.from(row)},
      ];
      if (items != null && m.itemSegment != null && m.itemJoinKey != null) {
        for (final i in items.rows) {
          if (i[m.itemJoinKey] == row[m.itemJoinKey]) {
            segs.add({
              'segment': m.itemSegment,
              'fields': Map<String, dynamic>.from(i),
            });
          }
        }
      }
      docs.add({
        'IDOC_NUMBER': docNumber,
        'MESTYP': m.messageType,
        'IDOCTYP': m.basicType,
        'SNDPRN': 'SAPCLNT100',
        'RCVPRN': 'SAPCLNT200',
        'CREDAT': _today(),
        'segments': segs,
      });
    }
    return Response.ok(jsonEncode({'idocs': docs}),
        headers: const {'content-type': 'application/json; charset=utf-8'});
  }

  Response _emitXml(
      String typeName, _IdocMapping m, EntitySet header, EntitySet? items) {
    final buf = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="utf-8"?>')
      ..writeln('<${m.basicType}>');
    var counter = 1;
    for (final row in header.rows) {
      final docNumber = _docNumber(counter++);
      buf
        ..writeln('  <IDOC BEGIN="1">')
        ..writeln('    <EDI_DC40 SEGMENT="1">')
        ..writeln('      <TABNAM>EDI_DC40</TABNAM>')
        ..writeln('      <MANDT>100</MANDT>')
        ..writeln('      <DOCNUM>$docNumber</DOCNUM>')
        ..writeln('      <DOCREL>700</DOCREL>')
        ..writeln('      <STATUS>03</STATUS>')
        ..writeln('      <DIRECT>1</DIRECT>')
        ..writeln('      <OUTMOD>2</OUTMOD>')
        ..writeln('      <IDOCTYP>${m.basicType}</IDOCTYP>')
        ..writeln('      <MESTYP>${m.messageType}</MESTYP>')
        ..writeln('      <SNDPOR>SAPCLNT100</SNDPOR>')
        ..writeln('      <SNDPRT>LS</SNDPRT>')
        ..writeln('      <SNDPRN>SAPCLNT100</SNDPRN>')
        ..writeln('      <RCVPOR>SAPCLNT200</RCVPOR>')
        ..writeln('      <RCVPRT>LS</RCVPRT>')
        ..writeln('      <RCVPRN>SAPCLNT200</RCVPRN>')
        ..writeln('      <CREDAT>${_today()}</CREDAT>')
        ..writeln('      <CRETIM>120000</CRETIM>')
        ..writeln('    </EDI_DC40>')
        ..writeln('    <${m.segment} SEGMENT="1">');
      row.forEach((k, v) {
        buf.writeln('      <$k>${_xml(v?.toString() ?? '')}</$k>');
      });
      buf.writeln('    </${m.segment}>');
      if (items != null && m.itemSegment != null && m.itemJoinKey != null) {
        for (final i in items.rows) {
          if (i[m.itemJoinKey] == row[m.itemJoinKey]) {
            buf.writeln('    <${m.itemSegment} SEGMENT="1">');
            i.forEach((k, v) {
              buf.writeln('      <$k>${_xml(v?.toString() ?? '')}</$k>');
            });
            buf.writeln('    </${m.itemSegment}>');
          }
        }
      }
      buf.writeln('  </IDOC>');
    }
    buf.writeln('</${m.basicType}>');
    return Response.ok(buf.toString(),
        headers: const {'content-type': 'application/xml; charset=utf-8'});
  }

  Future<Response> _acceptInbound(
      Request req, String typeName, _IdocMapping m) async {
    final body = await req.readAsString();
    // Echo back the IDOC_NUMBER and STATUS=53 (processed) for inbound feeds.
    final docNumber = _docNumber(DateTime.now().millisecondsSinceEpoch % 100000);
    return Response.ok(
      jsonEncode({
        'status': '53',
        'message': 'IDoc posted (mock)',
        'IDOC_NUMBER': docNumber,
        'MESTYP': m.messageType,
        'IDOCTYP': m.basicType,
        'receivedBytes': body.length,
      }),
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );
  }

  String _docNumber(int n) => n.toString().padLeft(16, '0');

  String _today() {
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${now.year}${two(now.month)}${two(now.day)}';
  }

  String _xml(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  Response _nf(String msg) => Response.notFound(jsonEncode({'error': msg}),
      headers: const {'content-type': 'application/json'});
  Response _err(String msg, int status) => Response(status,
      body: jsonEncode({'error': msg}),
      headers: const {'content-type': 'application/json'});
}

class _IdocMapping {
  const _IdocMapping({
    required this.messageType,
    required this.basicType,
    required this.service,
    required this.headerSet,
    required this.itemSet,
    required this.segment,
    this.itemSegment,
    this.itemJoinKey,
  });
  final String messageType;
  final String basicType;
  final String service;
  final String headerSet;
  final String? itemSet;
  final String segment;
  final String? itemSegment;
  final String? itemJoinKey;
}
