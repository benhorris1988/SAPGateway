import 'dart:convert';

import 'package:shelf/shelf.dart';

import 'filter.dart';
import 'models.dart';
import 'sql_parser.dart';
import 'store.dart';

/// SQL Server simulated HTTP endpoint. Two version flavours are exposed under
/// `/sqlserver/2017/` and `/sqlserver/2022/` so consumers can choose:
///
///   GET  /sqlserver/<v>/info                            — @@VERSION etc.
///   GET  /sqlserver/<v>/databases                       — services-as-DBs
///   GET  /sqlserver/<v>/tables                          — entity sets exposed as tables
///   GET  /sqlserver/<v>/tables/<set>?top=&where=        — convenience read
///   POST /sqlserver/<v>/query                           — full SELECT engine
///
/// The query endpoint accepts JSON or `text/plain` bodies. JSON looks like:
///
///   {"sql": "SELECT TOP 5 * FROM ZSALES_SRV.CustomerSet WHERE Land1 = 'US'"}
///
/// 2017 and 2022 differ in three ways:
///   * `@@VERSION` string returned by /info
///   * 2017 caps the result set at 50,000 rows by default (mock of resource governor)
///   * 2022 advertises JSON & ledger features via /info.features
class SqlServerHandler {
  SqlServerHandler(this.store, {required this.version}) : assert(
            version == '2017' || version == '2022',
            'only 2017 and 2022 are simulated');

  final GatewayStore store;
  final String version;

  static const _versionStrings = <String, String>{
    '2017':
        'Microsoft SQL Server 2017 (RTM-CU31) (KB5016884) - 14.0.3456.2 (X64) on Linux (Ubuntu 20.04 LTS) <Mock>',
    '2022':
        'Microsoft SQL Server 2022 (RTM-CU14) (KB5038325) - 16.0.4135.4 (X64) on Linux (Ubuntu 22.04 LTS) <Mock>',
  };

  static const _features2017 = ['stretch-db', 'json', 'temporal', 'r-services'];
  static const _features2022 = [
    'json',
    'ledger',
    'azure-synapse-link',
    'parameter-sensitive-plan-optimization',
    'qat-backup-compression',
  ];

  int get _defaultRowCap => version == '2017' ? 50000 : 200000;

  Handler get handler => (Request req) async {
        final tail = [...req.url.pathSegments];
        while (tail.isNotEmpty && tail.last.isEmpty) {
          tail.removeLast();
        }
        if (tail.isEmpty) return _info();
        switch (tail[0]) {
          case 'info':
            return _info();
          case 'databases':
            return _databases();
          case 'tables':
            if (tail.length == 1) return _tables();
            return _readTable(req, tail[1]);
          case 'query':
            return _query(req);
          default:
            return _nf('unknown path ${tail.join('/')}');
        }
      };

  Response _info() => _ok({
        'version': version,
        '@@VERSION': _versionStrings[version],
        '@@SERVERNAME': 'SAPGATEWAY\\SQLEXPRESS-MOCK',
        '@@SERVICENAME': 'MSSQLSERVER',
        'edition': version == '2017'
            ? 'Developer Edition (64-bit)'
            : 'Developer Edition (64-bit)',
        'collation': 'SQL_Latin1_General_CP1_CI_AS',
        'productLevel': version == '2017' ? 'RTM-CU31' : 'RTM-CU14',
        'features': version == '2017' ? _features2017 : _features2022,
        'rowCap': _defaultRowCap,
      });

  Response _databases() => _ok({
        'databases': [
          for (final s in store.services)
            {
              'name': s.name,
              'compatibilityLevel': version == '2017' ? 140 : 160,
              'recoveryModel': 'FULL',
              'tableCount': s.entitySets.length,
            },
          // System databases included for realism.
          {'name': 'master', 'compatibilityLevel': version == '2017' ? 140 : 160},
          {'name': 'tempdb', 'compatibilityLevel': version == '2017' ? 140 : 160},
          {'name': 'model', 'compatibilityLevel': version == '2017' ? 140 : 160},
          {'name': 'msdb', 'compatibilityLevel': version == '2017' ? 140 : 160},
        ],
      });

  Response _tables() {
    final tables = <Map<String, dynamic>>[];
    for (final s in store.services) {
      for (final es in s.entitySets) {
        final et = s.entityTypeByName(es.entityTypeName);
        tables.add({
          'database': s.name,
          'schema': 'dbo',
          'table': es.name,
          'qualifiedName': '[${s.name}].[dbo].[${es.name}]',
          'rowCount': es.rows.length,
          'columns': [
            if (et != null)
              for (final p in et.properties)
                {
                  'name': p.name,
                  'sqlType': _edmToSqlType(p),
                  'nullable': p.nullable,
                  'isPrimaryKey': et.keys.contains(p.name),
                },
          ],
        });
      }
    }
    return _ok({'tables': tables});
  }

  Response _readTable(Request req, String name) {
    final binding = _findEntitySet(name);
    if (binding == null) return _nf('table $name not found');
    final (_, es, et) = binding;
    final qp = req.url.queryParameters;
    var rows = es.rows.toList();
    final whereExpr = qp['where'];
    if (whereExpr != null && whereExpr.trim().isNotEmpty) {
      try {
        final f = FilterParser(whereExpr).parse();
        rows = rows.where((r) => f.evaluate(r) == true).toList();
      } catch (e) {
        return _bad('invalid where: $e');
      }
    }
    final top = int.tryParse(qp['top'] ?? '');
    if (top != null) rows = rows.take(top).toList();
    return _ok({
      'table': es.name,
      'columns': [for (final p in et.properties) p.name],
      'rows': rows,
    });
  }

  Future<Response> _query(Request req) async {
    if (req.method != 'POST') {
      return Response(405, body: 'POST required');
    }
    final ctype = (req.headers['content-type'] ?? '').toLowerCase();
    final raw = await req.readAsString();
    String sql;
    if (ctype.contains('json') || raw.trimLeft().startsWith('{')) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is! Map<String, dynamic>) {
          return _bad('JSON body must be {"sql": "..."}');
        }
        sql = (decoded['sql'] ?? decoded['query'] ?? '').toString();
      } catch (e) {
        return _bad('invalid JSON: $e');
      }
    } else {
      sql = raw;
    }
    if (sql.trim().isEmpty) return _bad('sql required');

    // Special pseudo-statements supported in both versions.
    final trimmed = sql.trim().toLowerCase();
    if (trimmed.startsWith('select @@version')) {
      return _resultSet(['version'], [
        [_versionStrings[version]]
      ]);
    }
    if (trimmed == 'select @@servername' ||
        trimmed == 'select @@servername;') {
      return _resultSet(['servername'], [
        ['SAPGATEWAY\\SQLEXPRESS-MOCK']
      ]);
    }
    if (trimmed.startsWith('exec sp_databases') ||
        trimmed == 'select name from sys.databases') {
      return _resultSet(
        ['name'],
        [for (final s in store.services) [s.name]] +
            const [
              ['master'],
              ['tempdb'],
              ['model'],
              ['msdb'],
            ],
      );
    }

    final SqlSelect select;
    try {
      select = parseSelect(sql);
    } on SqlParseException catch (e) {
      return _bad(e.message);
    } catch (e) {
      return _bad('parse error: $e');
    }

    final binding = _findEntitySet(select.table);
    if (binding == null) {
      return _bad('invalid object name: ${select.table}');
    }
    final (svc, es, et) = binding;
    if (select.schema != null &&
        select.schema!.toLowerCase() != svc.name.toLowerCase() &&
        select.schema!.toLowerCase() != 'dbo') {
      // Allow `database.table` or `schema.table`. Other schemas error.
      return _bad('unknown schema: ${select.schema}');
    }

    var rows = es.rows.toList();
    if (select.where != null) {
      rows = rows.where((r) => select.where!.evaluate(r) == true).toList();
    }
    if (select.orderBy.isNotEmpty) {
      rows.sort((a, b) {
        for (final o in select.orderBy) {
          final cmp = compareValues(a[o.field], b[o.field]);
          if (cmp != 0) return o.desc ? -cmp : cmp;
        }
        return 0;
      });
    }
    if (select.offset > 0) rows = rows.skip(select.offset).toList();
    final effectiveLimit = select.limit ?? _defaultRowCap;
    if (rows.length > effectiveLimit) {
      rows = rows.take(effectiveLimit).toList();
    }

    final cols = select.allColumns
        ? [for (final p in et.properties) p.name]
        : select.columns;

    final out = rows.map((r) => [for (final c in cols) r[c]]).toList();

    if (select.distinct) {
      final seen = <String>{};
      out.removeWhere((row) {
        final key = jsonEncode(row);
        if (seen.contains(key)) return true;
        seen.add(key);
        return false;
      });
    }

    return _resultSet(cols, out);
  }

  Response _resultSet(List<String> columns, List<List<Object?>> rows) => _ok({
        'columns': [
          for (final c in columns) {'name': c, 'type': 'sql_variant'}
        ],
        'rows': rows,
        'rowsAffected': rows.length,
        'version': version,
        'serverEngine': _versionStrings[version],
      });

  (GatewayService, EntitySet, EntityType)? _findEntitySet(String name) {
    for (final s in store.services) {
      final es = s.entitySetByName(name);
      if (es == null) continue;
      final et = s.entityTypeByName(es.entityTypeName);
      if (et == null) continue;
      return (s, es, et);
    }
    return null;
  }

  String _edmToSqlType(Property p) {
    switch (p.edmType) {
      case 'Edm.String':
        return 'NVARCHAR(${p.maxLength ?? 255})';
      case 'Edm.Int32':
        return 'INT';
      case 'Edm.Int64':
        return 'BIGINT';
      case 'Edm.Int16':
        return 'SMALLINT';
      case 'Edm.Boolean':
        return 'BIT';
      case 'Edm.Decimal':
        return 'DECIMAL(${p.precision ?? 18},${p.scale ?? 2})';
      case 'Edm.Double':
        return 'FLOAT';
      case 'Edm.DateTime':
      case 'Edm.DateTimeOffset':
        return version == '2017' ? 'DATETIME2' : 'DATETIME2(7)';
      case 'Edm.Guid':
        return 'UNIQUEIDENTIFIER';
      default:
        return 'SQL_VARIANT';
    }
  }

  Response _ok(Object body, {int status = 200}) => Response(
        status,
        body: jsonEncode(body),
        headers: const {'content-type': 'application/json; charset=utf-8'},
      );
  Response _nf(String msg) => Response.notFound(
      jsonEncode({'error': 'object_not_found', 'message': msg}),
      headers: const {'content-type': 'application/json'});
  Response _bad(String msg) => Response.badRequest(
      body: jsonEncode({
        'error': 'sql_error',
        'message': msg,
        'severity': 16,
        'number': 102,
      }),
      headers: const {'content-type': 'application/json'});
}
