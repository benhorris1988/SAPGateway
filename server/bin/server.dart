import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

import 'package:sap_gateway_server/admin.dart';
import 'package:sap_gateway_server/logging.dart';
import 'package:sap_gateway_server/odata.dart';
import 'package:sap_gateway_server/odata_v4.dart';
import 'package:sap_gateway_server/sap_idoc.dart';
import 'package:sap_gateway_server/sap_rest.dart';
import 'package:sap_gateway_server/sap_soap.dart';
import 'package:sap_gateway_server/sql_server.dart';
import 'package:sap_gateway_server/store.dart';
import 'package:sap_gateway_server/surrealdb.dart';

Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addOption('host', defaultsTo: '0.0.0.0')
    ..addOption('port', defaultsTo: '8080')
    ..addOption('data',
        defaultsTo: 'data/runtime.json',
        help: 'Path used to persist the configured gateway state.')
    ..addOption('log',
        defaultsTo: 'data/server.log',
        help: 'File path for the error/request log. Empty string disables '
            'file logging (console logging always stays on).')
    ..addOption('log-level',
        defaultsTo: 'info',
        allowed: ['debug', 'info', 'warn', 'error'],
        help: 'Minimum severity written to console and file.');
  final opts = parser.parse(args);

  logger.configure(
    minLevel: LogLevelName.parse(opts['log-level'] as String) ?? LogLevel.info,
    filePath: opts['log'] as String,
  );

  final store = GatewayStore(persistencePath: opts['data'] as String);
  await store.load();

  final odataV2 = ODataHandler(store);
  final odataV4 = ODataV4Handler(store);
  final rest = SapRestHandler(store);
  final soap = SapSoapHandler(store);
  final idoc = SapIdocHandler(store);
  final sql2017 = SqlServerHandler(store, version: '2017');
  final sql2022 = SqlServerHandler(store, version: '2022');
  final surreal = SurrealDbHandler(store);
  final admin = AdminHandler(store);

  final root = Router()
    ..get(
        '/',
        (Request _) => Response.ok(_landing,
            headers: const {'content-type': 'text/html; charset=utf-8'}))
    ..get('/healthz', (Request _) => Response.ok('ok'))
    // Redirect bare prefixes so users land on the catalog/service doc.
    ..get('/sap/opu/odata/sap',
        (Request _) => Response.movedPermanently('/sap/opu/odata/sap/'))
    ..get('/sap/opu/odata4/sap',
        (Request _) => Response.movedPermanently('/sap/opu/odata4/sap/'))
    ..get('/sap/rest', (Request _) => Response.movedPermanently('/sap/rest/'))
    ..get(
        '/sap/bc/srt', (Request _) => Response.movedPermanently('/sap/bc/srt/'))
    ..get('/sap/idoc', (Request _) => Response.movedPermanently('/sap/idoc/'))
    ..get('/sqlserver',
        (Request _) => Response.movedPermanently('/sqlserver/2022/info'))
    ..get('/surrealdb',
        (Request _) => Response.movedPermanently('/surrealdb/'))
    ..get('/admin', (Request _) => Response.movedPermanently('/admin/services'))
    // OData
    ..mount('/sap/opu/odata/sap/', odataV2.handler)
    ..mount('/sap/opu/odata4/sap/', odataV4.handler)
    // SAP-style protocols
    ..mount('/sap/rest/', rest.handler)
    ..mount('/sap/bc/srt/', soap.handler)
    ..mount('/sap/idoc/', idoc.handler)
    // Databases
    ..mount('/sqlserver/2017/', sql2017.handler)
    ..mount('/sqlserver/2022/', sql2022.handler)
    ..mount('/surrealdb/', surreal.handler)
    // Admin
    ..mount('/admin/', admin.router.call);

  final pipeline = const Pipeline()
      .addMiddleware(_logRequests)
      .addMiddleware(_cors)
      .addMiddleware(_errorHandler)
      .addHandler(root.call);

  final port = int.parse(opts['port'] as String);
  final host = opts['host'] as String;
  final server = await shelf_io.serve(pipeline, host, port);
  final base = 'http://$host:${server.port}';
  stdout.writeln('SAP Gateway mock listening on $base');
  stdout.writeln('  OData v2:        $base/sap/opu/odata/sap/');
  stdout.writeln('  OData v4:        $base/sap/opu/odata4/sap/');
  stdout.writeln('  SAP REST:        $base/sap/rest/');
  stdout.writeln('  SOAP / BAPI:     $base/sap/bc/srt/');
  stdout.writeln('  IDoc:            $base/sap/idoc/');
  stdout.writeln('  SQL Server 2017: $base/sqlserver/2017/');
  stdout.writeln('  SQL Server 2022: $base/sqlserver/2022/');
  stdout.writeln('  SurrealDB:       $base/surrealdb/');
  stdout.writeln('  Admin API:       $base/admin/services');
  stdout.writeln('  Error log:       $base/admin/logs');
  logger.info('SAP Gateway mock started on $base');
}

/// Catches anything a handler throws, logs it with a stack trace, and returns
/// a clean 500 so the connection isn't left hanging. Sits inside the CORS
/// middleware so error responses still carry CORS headers.
Middleware get _errorHandler => (inner) => (req) async {
      try {
        return await inner(req);
      } catch (e, st) {
        logger.error('Unhandled error for ${req.method} /${req.url}',
            error: e, stackTrace: st);
        return Response.internalServerError(
          body: jsonEncode(<String, dynamic>{
            'error': {
              'code': '500',
              'message': {'lang': 'en', 'value': 'Internal server error'},
            }
          }),
          headers: const {'content-type': 'application/json; charset=utf-8'},
        );
      }
    };

Middleware get _cors => (inner) => (req) async {
      if (req.method == 'OPTIONS') {
        return Response.ok('', headers: _corsHeaders);
      }
      final res = await inner(req);
      return res.change(headers: {...res.headers, ..._corsHeaders});
    };

const _corsHeaders = {
  'access-control-allow-origin': '*',
  'access-control-allow-methods': 'GET,POST,PUT,PATCH,DELETE,MERGE,OPTIONS',
  'access-control-allow-headers':
      'content-type,authorization,accept,dataserviceversion,maxdataserviceversion,odata-version,odata-maxversion,x-requested-with',
  'access-control-expose-headers':
      'dataserviceversion,odata-version,content-length,content-type',
};

Middleware get _logRequests => (inner) => (req) async {
      final sw = Stopwatch()..start();
      final res = await inner(req);
      sw.stop();
      final line =
          '${req.method.padRight(6)} ${res.statusCode} ${sw.elapsedMilliseconds}ms  /${req.url}';
      if (res.statusCode >= 500) {
        logger.error(line);
      } else if (res.statusCode >= 400) {
        logger.warn(line);
      } else {
        logger.info(line);
      }
      return res;
    };

const _landing = r'''
<!doctype html>
<html><head><meta charset="utf-8"><title>SAP Gateway (mock)</title>
<style>
  body { font: 14px/1.5 system-ui, sans-serif; max-width: 880px; margin: 40px auto; color: #1d1d1f; padding: 0 16px; }
  h1 { color: #1E3A5F; }
  h2 { margin-top: 32px; color: #1E3A5F; font-size: 18px; border-bottom: 1px solid #e4e4e7; padding-bottom: 4px; }
  code { background: #f4f4f5; padding: 2px 6px; border-radius: 4px; font-size: 13px; }
  pre  { background: #0f172a; color: #f1f5f9; padding: 12px 16px; border-radius: 6px; overflow:auto; font-size: 12px; }
  ul   { padding-left: 22px; }
  li   { margin: 6px 0; }
  table { border-collapse: collapse; width: 100%; margin: 12px 0; }
  th, td { text-align: left; padding: 6px 10px; border-bottom: 1px solid #e4e4e7; font-size: 13px; }
  th { background: #f4f4f5; }
  .pill { display: inline-block; padding: 1px 8px; border-radius: 9999px; background: #e0f2fe; color: #075985; font-size: 11px; font-weight: 600; }
</style></head><body>
<h1>SAP Gateway (mock)</h1>
<p>One simulated SAP ECC 6 / NetWeaver Gateway, exposed through every connection
shape you’re likely to hit in the wild — plus SQL Server and SurrealDB on top
of the same data.</p>

<h2>SAP connections</h2>
<table>
  <tr><th>Protocol</th><th>Root</th><th>Try it</th></tr>
  <tr><td><span class="pill">OData v2</span></td><td><code>/sap/opu/odata/sap/</code></td><td><a href="/sap/opu/odata/sap/ZSALES_SRV/CustomerSet?$format=json&$top=5">CustomerSet (v2)</a></td></tr>
  <tr><td><span class="pill">OData v4</span></td><td><code>/sap/opu/odata4/sap/</code></td><td><a href="/sap/opu/odata4/sap/ZSALES_SRV/CustomerSet?$top=5&$count=true">CustomerSet (v4)</a></td></tr>
  <tr><td><span class="pill">REST</span></td><td><code>/sap/rest/</code></td><td><a href="/sap/rest/ZSALES_SRV/CustomerSet?limit=5">CustomerSet (REST)</a></td></tr>
  <tr><td><span class="pill">SOAP / BAPI / RFC</span></td><td><code>/sap/bc/srt/</code></td><td><a href="/sap/bc/srt/">BAPI catalogue</a></td></tr>
  <tr><td><span class="pill">IDoc (ALE/EDI)</span></td><td><code>/sap/idoc/</code></td><td><a href="/sap/idoc/ORDERS05">ORDERS05 outbound</a></td></tr>
</table>

<h2>Databases</h2>
<table>
  <tr><th>Engine</th><th>Root</th><th>Try it</th></tr>
  <tr><td><span class="pill">SQL Server 2017</span></td><td><code>/sqlserver/2017/</code></td><td><a href="/sqlserver/2017/info">/info</a> · <a href="/sqlserver/2017/tables">/tables</a></td></tr>
  <tr><td><span class="pill">SQL Server 2022</span></td><td><code>/sqlserver/2022/</code></td><td><a href="/sqlserver/2022/info">/info</a> · <a href="/sqlserver/2022/tables">/tables</a></td></tr>
  <tr><td><span class="pill">SurrealDB</span></td><td><code>/surrealdb/</code></td><td><a href="/surrealdb/">root</a> · <a href="/surrealdb/key/CustomerSet">/key/CustomerSet</a></td></tr>
</table>

<h2>Quick samples</h2>
<pre>curl 'http://localhost:8080/sap/opu/odata/sap/ZSALES_SRV/CustomerSet?$format=json&$filter=Land1%20eq%20%27US%27'

curl 'http://localhost:8080/sap/opu/odata4/sap/ZSALES_SRV/CustomerSet?$count=true&$top=3'

curl -X POST 'http://localhost:8080/sap/bc/srt/BAPI_MATERIAL_GETLIST' \
  -H 'Content-Type: application/json' \
  -d '{"OPTIONS":["Matkl eq '0010'"],"FIELDS":["Matnr","Maktx"]}'

curl 'http://localhost:8080/sap/idoc/ORDERS05'

curl -X POST 'http://localhost:8080/sqlserver/2022/query' \
  -H 'Content-Type: application/json' \
  -d '{"sql":"SELECT TOP 5 * FROM ZSALES_SRV.CustomerSet WHERE Land1 = '"'"'US'"'"'"}'

curl -X POST 'http://localhost:8080/surrealdb/sql' \
  -H 'Content-Type: text/plain' \
  -d 'SELECT * FROM CustomerSet WHERE Land1 = "US" LIMIT 5;'</pre>

<h2>Admin / configuration</h2>
<ul>
  <li><a href="/admin/services">/admin/services</a> — JSON CRUD over services, entity types, sets, rows</li>
  <li><a href="/admin/connections">/admin/connections</a> — machine-readable catalogue of every connection surface above</li>
</ul>
</body></html>
''';
