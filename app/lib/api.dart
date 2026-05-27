import 'dart:convert';

import 'package:http/http.dart' as http;

import 'logging.dart';
import 'models.dart';

/// HTTP client for the gateway's admin API. Throws [GatewayException] on any
/// non-2xx response so the UI can surface a single failure path. Every request
/// goes through [_send], which logs transport failures and error responses via
/// [appLog].
class GatewayApi {
  GatewayApi(this.baseUrl);

  /// e.g. http://localhost:8080
  String baseUrl;

  Uri _u(String path) => Uri.parse('$baseUrl$path');

  Future<List<ServiceSummary>> listServices() async {
    final res = await _send('GET', '/admin/services');
    return (jsonDecode(res.body) as List)
        .cast<Map<String, dynamic>>()
        .map(ServiceSummary.fromJson)
        .toList();
  }

  Future<void> createService({
    required String name,
    String? namespace,
    String description = '',
  }) async {
    await _send('POST', '/admin/services',
        body: {
          'name': name,
          'namespace': namespace ?? name,
          'description': description,
        });
  }

  Future<void> updateService(
    String svc, {
    String? name,
    String? namespace,
    String? description,
  }) async {
    await _send('PATCH', '/admin/services/$svc', body: {
      if (name != null) 'name': name,
      if (namespace != null) 'namespace': namespace,
      if (description != null) 'description': description,
    });
  }

  Future<void> deleteService(String svc) async {
    await _send('DELETE', '/admin/services/$svc');
  }

  // Entity types
  Future<List<EntityType>> listEntityTypes(String svc) async {
    final res = await _send('GET', '/admin/services/$svc/entity-types');
    return (jsonDecode(res.body) as List)
        .cast<Map<String, dynamic>>()
        .map(EntityType.fromJson)
        .toList();
  }

  Future<void> createEntityType(
    String svc, {
    required String name,
    required List<String> keys,
    List<Property> properties = const [],
  }) async {
    await _send('POST', '/admin/services/$svc/entity-types', body: {
      'name': name,
      'keys': keys,
      'properties': properties.map((p) => p.toJson()).toList(),
    });
  }

  Future<void> updateEntityType(
    String svc,
    String et, {
    String? name,
    List<String>? keys,
  }) async {
    await _send('PATCH', '/admin/services/$svc/entity-types/$et', body: {
      if (name != null) 'name': name,
      if (keys != null) 'keys': keys,
    });
  }

  Future<void> deleteEntityType(String svc, String et) async {
    await _send('DELETE', '/admin/services/$svc/entity-types/$et');
  }

  // Properties
  Future<void> addProperty(String svc, String et, Property prop) async {
    await _send('POST', '/admin/services/$svc/entity-types/$et/properties',
        body: prop.toJson());
  }

  Future<void> updateProperty(
      String svc, String et, String prop, Property updated) async {
    await _send(
        'PATCH', '/admin/services/$svc/entity-types/$et/properties/$prop',
        body: updated.toJson());
  }

  Future<void> deleteProperty(String svc, String et, String prop) async {
    await _send(
        'DELETE', '/admin/services/$svc/entity-types/$et/properties/$prop');
  }

  // Entity sets
  Future<List<EntitySetSummary>> listEntitySets(String svc) async {
    final res = await _send('GET', '/admin/services/$svc/entity-sets');
    return (jsonDecode(res.body) as List)
        .cast<Map<String, dynamic>>()
        .map(EntitySetSummary.fromJson)
        .toList();
  }

  Future<void> createEntitySet(
    String svc, {
    required String name,
    required String entityTypeName,
  }) async {
    await _send('POST', '/admin/services/$svc/entity-sets',
        body: {'name': name, 'entityTypeName': entityTypeName});
  }

  Future<void> deleteEntitySet(String svc, String es) async {
    await _send('DELETE', '/admin/services/$svc/entity-sets/$es');
  }

  // Rows
  Future<List<Map<String, dynamic>>> listRows(String svc, String es) async {
    final res = await _send('GET', '/admin/services/$svc/entity-sets/$es/rows');
    return (jsonDecode(res.body) as List)
        .cast<Map<String, dynamic>>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList();
  }

  Future<void> addRow(String svc, String es, Map<String, dynamic> row) async {
    await _send('POST', '/admin/services/$svc/entity-sets/$es/rows',
        body: row);
  }

  Future<void> updateRow(
      String svc, String es, int index, Map<String, dynamic> row) async {
    await _send('PUT', '/admin/services/$svc/entity-sets/$es/rows/$index',
        body: row);
  }

  Future<void> deleteRow(String svc, String es, int index) async {
    await _send('DELETE', '/admin/services/$svc/entity-sets/$es/rows/$index');
  }

  Future<void> resetToSeed() async {
    await _send('POST', '/admin/reset');
  }

  /// Catalogue of every protocol surface the gateway exposes (OData v2 + v4,
  /// REST, SOAP/BAPI, IDoc, SQL Server 2017/2022, SurrealDB).
  Future<List<ConnectionInfo>> listConnections() async {
    final res = await _send('GET', '/admin/connections');
    return (jsonDecode(res.body) as List)
        .cast<Map<String, dynamic>>()
        .map(ConnectionInfo.fromJson)
        .toList();
  }

  /// Fire-and-forget: pushes a client error to the gateway's log. Deliberately
  /// bypasses [_send] and swallows all failures so it can never trigger more
  /// logging (which would loop).
  void logClientError(AppLogEntry entry) {
    () async {
      try {
        await http.post(
          _u('/admin/logs/client'),
          headers: _jsonHeader,
          body: jsonEncode(entry.toJson()),
        );
      } catch (_) {
        // Best-effort; the entry is already in the console + local buffer.
      }
    }();
  }

  /// Single choke point for every request. Logs transport failures (no
  /// connection, timeout, DNS) as errors and delegates response-status checks
  /// to [_check].
  Future<http.Response> _send(
    String method,
    String path, {
    Object? body,
  }) async {
    final uri = _u(path);
    final encoded = body == null ? null : jsonEncode(body);
    http.Response res;
    try {
      res = await switch (method) {
        'GET' => http.get(uri),
        'DELETE' => http.delete(uri),
        'POST' => http.post(uri, headers: _jsonHeader, body: encoded),
        'PUT' => http.put(uri, headers: _jsonHeader, body: encoded),
        'PATCH' => http.patch(uri, headers: _jsonHeader, body: encoded),
        _ => throw ArgumentError('Unsupported method: $method'),
      };
    } catch (e, st) {
      appLog.error('Network failure: $method $path',
          error: e, stackTrace: st);
      rethrow;
    }
    _check(res, method, path);
    return res;
  }

  static const Map<String, String> _jsonHeader = {
    'content-type': 'application/json',
  };

  void _check(http.Response res, String method, String path) {
    if (res.statusCode >= 200 && res.statusCode < 300) return;
    String message;
    try {
      final decoded = jsonDecode(res.body);
      if (decoded is Map && decoded['error'] != null) {
        message = decoded['error'].toString();
      } else {
        message = res.body;
      }
    } catch (_) {
      message = res.body.isEmpty ? 'HTTP ${res.statusCode}' : res.body;
    }
    final detail = '$method $path -> ${res.statusCode}: $message';
    if (res.statusCode >= 500) {
      appLog.error('Gateway server error: $detail');
    } else {
      appLog.warn('Gateway request failed: $detail');
    }
    throw GatewayException(res.statusCode, message);
  }
}

class GatewayException implements Exception {
  GatewayException(this.statusCode, this.message);
  final int statusCode;
  final String message;
  @override
  String toString() => 'Gateway error $statusCode: $message';
}
