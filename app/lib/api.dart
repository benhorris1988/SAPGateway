import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

/// HTTP client for the gateway's admin API. Throws [GatewayException] on any
/// non-2xx response so the UI can surface a single failure path.
class GatewayApi {
  GatewayApi(this.baseUrl);

  /// e.g. http://localhost:8080
  String baseUrl;

  Uri _u(String path) => Uri.parse('$baseUrl$path');

  Future<List<ServiceSummary>> listServices() async {
    final res = await http.get(_u('/admin/services'));
    _check(res);
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
    final res = await http.post(
      _u('/admin/services'),
      headers: _jsonHeader,
      body: jsonEncode({
        'name': name,
        'namespace': namespace ?? name,
        'description': description,
      }),
    );
    _check(res);
  }

  Future<void> updateService(
    String svc, {
    String? name,
    String? namespace,
    String? description,
  }) async {
    final res = await http.patch(
      _u('/admin/services/$svc'),
      headers: _jsonHeader,
      body: jsonEncode({
        if (name != null) 'name': name,
        if (namespace != null) 'namespace': namespace,
        if (description != null) 'description': description,
      }),
    );
    _check(res);
  }

  Future<void> deleteService(String svc) async {
    _check(await http.delete(_u('/admin/services/$svc')));
  }

  // Entity types
  Future<List<EntityType>> listEntityTypes(String svc) async {
    final res = await http.get(_u('/admin/services/$svc/entity-types'));
    _check(res);
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
    final res = await http.post(
      _u('/admin/services/$svc/entity-types'),
      headers: _jsonHeader,
      body: jsonEncode({
        'name': name,
        'keys': keys,
        'properties': properties.map((p) => p.toJson()).toList(),
      }),
    );
    _check(res);
  }

  Future<void> updateEntityType(
    String svc,
    String et, {
    String? name,
    List<String>? keys,
  }) async {
    final res = await http.patch(
      _u('/admin/services/$svc/entity-types/$et'),
      headers: _jsonHeader,
      body: jsonEncode({
        if (name != null) 'name': name,
        if (keys != null) 'keys': keys,
      }),
    );
    _check(res);
  }

  Future<void> deleteEntityType(String svc, String et) async {
    _check(await http.delete(_u('/admin/services/$svc/entity-types/$et')));
  }

  // Properties
  Future<void> addProperty(String svc, String et, Property prop) async {
    final res = await http.post(
      _u('/admin/services/$svc/entity-types/$et/properties'),
      headers: _jsonHeader,
      body: jsonEncode(prop.toJson()),
    );
    _check(res);
  }

  Future<void> updateProperty(
      String svc, String et, String prop, Property updated) async {
    final res = await http.patch(
      _u('/admin/services/$svc/entity-types/$et/properties/$prop'),
      headers: _jsonHeader,
      body: jsonEncode(updated.toJson()),
    );
    _check(res);
  }

  Future<void> deleteProperty(String svc, String et, String prop) async {
    _check(await http
        .delete(_u('/admin/services/$svc/entity-types/$et/properties/$prop')));
  }

  // Entity sets
  Future<List<EntitySetSummary>> listEntitySets(String svc) async {
    final res = await http.get(_u('/admin/services/$svc/entity-sets'));
    _check(res);
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
    final res = await http.post(
      _u('/admin/services/$svc/entity-sets'),
      headers: _jsonHeader,
      body: jsonEncode({'name': name, 'entityTypeName': entityTypeName}),
    );
    _check(res);
  }

  Future<void> deleteEntitySet(String svc, String es) async {
    _check(await http.delete(_u('/admin/services/$svc/entity-sets/$es')));
  }

  // Rows
  Future<List<Map<String, dynamic>>> listRows(String svc, String es) async {
    final res = await http.get(_u('/admin/services/$svc/entity-sets/$es/rows'));
    _check(res);
    return (jsonDecode(res.body) as List)
        .cast<Map<String, dynamic>>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList();
  }

  Future<void> addRow(String svc, String es, Map<String, dynamic> row) async {
    final res = await http.post(
      _u('/admin/services/$svc/entity-sets/$es/rows'),
      headers: _jsonHeader,
      body: jsonEncode(row),
    );
    _check(res);
  }

  Future<void> updateRow(
      String svc, String es, int index, Map<String, dynamic> row) async {
    final res = await http.put(
      _u('/admin/services/$svc/entity-sets/$es/rows/$index'),
      headers: _jsonHeader,
      body: jsonEncode(row),
    );
    _check(res);
  }

  Future<void> deleteRow(String svc, String es, int index) async {
    _check(await http
        .delete(_u('/admin/services/$svc/entity-sets/$es/rows/$index')));
  }

  Future<void> resetToSeed() async {
    _check(await http.post(_u('/admin/reset')));
  }

  /// Catalogue of every protocol surface the gateway exposes (OData v2 + v4,
  /// REST, SOAP/BAPI, IDoc, SQL Server 2017/2022, SurrealDB).
  Future<List<ConnectionInfo>> listConnections() async {
    final res = await http.get(_u('/admin/connections'));
    _check(res);
    return (jsonDecode(res.body) as List)
        .cast<Map<String, dynamic>>()
        .map(ConnectionInfo.fromJson)
        .toList();
  }

  static const Map<String, String> _jsonHeader = {
    'content-type': 'application/json',
  };

  void _check(http.Response res) {
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
