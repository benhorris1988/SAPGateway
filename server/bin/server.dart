import 'dart:io';

import 'package:args/args.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

import 'package:sap_gateway_server/admin.dart';
import 'package:sap_gateway_server/odata.dart';
import 'package:sap_gateway_server/store.dart';

Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addOption('host', defaultsTo: '0.0.0.0')
    ..addOption('port', defaultsTo: '8080')
    ..addOption('data',
        defaultsTo: 'data/runtime.json',
        help: 'Path used to persist the configured gateway state.');
  final opts = parser.parse(args);

  final store = GatewayStore(persistencePath: opts['data'] as String);
  await store.load();

  final odata = ODataHandler(store);
  final admin = AdminHandler(store);

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
    ..get('/admin', (Request _) => Response.movedPermanently('/admin/services'))
    ..mount('/sap/opu/odata/sap/', odata.handler)
    ..mount('/admin/', admin.router.call);

  final pipeline = const Pipeline()
      .addMiddleware(_logRequests)
      .addMiddleware(_cors)
      .addHandler(root.call);

  final port = int.parse(opts['port'] as String);
  final host = opts['host'] as String;
  final server = await shelf_io.serve(pipeline, host, port);
  stdout.writeln('SAP Gateway mock listening on http://$host:${server.port}');
  stdout
      .writeln('  OData root: http://$host:${server.port}/sap/opu/odata/sap/');
  stdout.writeln('  Admin API:  http://$host:${server.port}/admin/services');
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
<p>OData v2 surface, configurable through the Flutter admin app or the
<code>/admin/*</code> JSON API.</p>
<ul>
  <li><a href="/sap/opu/odata/sap/">/sap/opu/odata/sap/</a> &mdash; service catalog</li>
  <li><a href="/sap/opu/odata/sap/ZSALES_SRV/\$metadata">/sap/opu/odata/sap/ZSALES_SRV/\$metadata</a> &mdash; EDMX schema</li>
  <li><a href="/sap/opu/odata/sap/ZSALES_SRV/CustomerSet?\$format=json&\$top=5">/sap/opu/odata/sap/ZSALES_SRV/CustomerSet?\$format=json&\$top=5</a> &mdash; sample query</li>
  <li><a href="/admin/services">/admin/services</a> &mdash; admin API</li>
</ul>
<pre>curl 'http://localhost:8080/sap/opu/odata/sap/ZSALES_SRV/CustomerSet?\$format=json&\$filter=Land1%20eq%20%27US%27'</pre>
</body></html>
''';
