import 'dart:io';

import 'package:args/args.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

import 'package:sap_gateway_server/admin.dart';
import 'package:sap_gateway_server/integration.dart';
import 'package:sap_gateway_server/odata.dart';
import 'package:sap_gateway_server/rest.dart';
import 'package:sap_gateway_server/store.dart';

Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addOption('host', defaultsTo: '0.0.0.0')
    ..addOption('port', defaultsTo: '8080')
    ..addOption('data',
        defaultsTo: 'data/runtime.json',
        help: 'Path used to persist the configured gateway state.');
  final opts = parser.parse(args);

  final dataPath = opts['data'] as String;
  final dataDir = File(dataPath).parent.path;

  final store = GatewayStore(persistencePath: dataPath);
  await store.load();

  final integrationConfig = IntegrationConfigStore('$dataDir/integration.json');
  await integrationConfig.load();
  final auditStore = AuditStore('$dataDir/audit.json');
  await auditStore.load();

  final odata = ODataHandler(store);
  final rest = RestHandler(store);
  final admin = AdminHandler(store);
  final integration = IntegrationHandler(
    store,
    integrationConfig,
    auditStore,
    rest.resolveCollection,
  );

  final root = Router()
    ..get(
        '/',
        (Request _) => Response.ok(_landing,
            headers: const {'content-type': 'text/html; charset=utf-8'}))
    ..get('/healthz', (Request _) => Response.ok('ok'))
    // Redirect bare prefixes so users get the catalog/service doc with a
    // trailing slash — shelf_router's mount requires one.
    ..get('/sap/opu/odata/sap',
        (Request _) => Response.movedPermanently('/sap/opu/odata/sap/'))
    ..get('/api/v1', (Request _) => Response.movedPermanently('/api/v1/'))
    ..get('/admin', (Request _) => Response.movedPermanently('/admin/services'))
    ..mount('/sap/opu/odata/sap/', odata.handler)
    ..mount('/api/v1/integration/', integration.handler)
    ..mount('/api/v1/', rest.handler)
    ..mount('/admin/', admin.router.call);

  final pipeline = const Pipeline()
      .addMiddleware(_logRequests)
      .addMiddleware(_cors)
      .addHandler(root.call);

  final port = int.parse(opts['port'] as String);
  final host = opts['host'] as String;
  final server = await shelf_io.serve(pipeline, host, port);
  stdout.writeln('SAP Gateway mock listening on http://$host:${server.port}');
  stdout.writeln('  REST API:    http://$host:${server.port}/api/v1/');
  stdout.writeln(
      '  Integration: http://$host:${server.port}/api/v1/integration/config');
  stdout.writeln(
      '  OData root:  http://$host:${server.port}/sap/opu/odata/sap/');
  stdout.writeln('  Admin API:   http://$host:${server.port}/admin/services');
}

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
      'content-type,authorization,accept,dataserviceversion,maxdataserviceversion,x-requested-with',
  'access-control-expose-headers':
      'dataserviceversion,content-length,content-type',
};

Middleware get _logRequests => (inner) => (req) async {
      final sw = Stopwatch()..start();
      final res = await inner(req);
      sw.stop();
      stdout.writeln(
          '${req.method.padRight(6)} ${res.statusCode} ${sw.elapsedMilliseconds}ms  /${req.url}');
      return res;
    };

const _landing = '''
<!doctype html>
<html><head><meta charset="utf-8"><title>SAP Gateway (mock)</title>
<style>
  body { font: 14px/1.5 system-ui, sans-serif; max-width: 720px; margin: 40px auto; color: #1d1d1f; }
  code { background: #f4f4f5; padding: 2px 6px; border-radius: 4px; }
  pre  { background: #0f172a; color: #f1f5f9; padding: 12px 16px; border-radius: 6px; overflow:auto; }
</style></head><body>
<h1>SAP Gateway (mock)</h1>
<p>Two consumer surfaces over the same data:</p>
<ul>
  <li><a href="/api/v1/">/api/v1/</a> &mdash; <strong>REST API</strong> (recommended)</li>
  <li><a href="/api/v1/integration/config">/api/v1/integration/config</a> &mdash; SAP &harr; SurrealDB integration (sync + audit)</li>
  <li><a href="/sap/opu/odata/sap/">/sap/opu/odata/sap/</a> &mdash; OData v2 surface (legacy / SAP NetWeaver compatibility)</li>
  <li><a href="/admin/services">/admin/services</a> &mdash; admin API (schema + row CRUD)</li>
</ul>
<h2>REST examples</h2>
<pre># list expenses
curl http://localhost:8080/api/v1/expenses

# write an expense back to SAP
curl -X POST http://localhost:8080/api/v1/expenses \\
  -H 'content-type: application/json' \\
  -d '{"Belnr":"1900000099","Pernr":"00010001","Wrbtr":"42.50","Waers":"GBP","Sgtxt":"Lunch"}'</pre>
</body></html>
''';
