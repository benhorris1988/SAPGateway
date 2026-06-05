/// Client-side mirrors of the server models. Kept intentionally simple — the
/// admin API returns flat JSON shapes that map straight through.

class ServiceSummary {
  ServiceSummary({
    required this.name,
    required this.namespace,
    required this.description,
    required this.entityTypeCount,
    required this.entitySetCount,
    required this.rowCount,
  });

  final String name;
  final String namespace;
  final String description;
  final int entityTypeCount;
  final int entitySetCount;
  final int rowCount;

  factory ServiceSummary.fromJson(Map<String, dynamic> json) => ServiceSummary(
        name: json['name'] as String,
        namespace: (json['namespace'] as String?) ?? json['name'] as String,
        description: (json['description'] as String?) ?? '',
        entityTypeCount: (json['entityTypeCount'] as int?) ?? 0,
        entitySetCount: (json['entitySetCount'] as int?) ?? 0,
        rowCount: (json['rowCount'] as int?) ?? 0,
      );
}

class EntityType {
  EntityType({
    required this.name,
    required this.keys,
    required this.properties,
  });

  String name;
  List<String> keys;
  List<Property> properties;

  factory EntityType.fromJson(Map<String, dynamic> json) => EntityType(
        name: json['name'] as String,
        keys: ((json['keys'] as List?) ?? const []).cast<String>(),
        properties: ((json['properties'] as List?) ?? const [])
            .cast<Map<String, dynamic>>()
            .map(Property.fromJson)
            .toList(),
      );
}

class Property {
  Property({
    required this.name,
    required this.edmType,
    this.nullable = true,
    this.maxLength,
    this.precision,
    this.scale,
    this.label,
  });

  String name;
  String edmType;
  bool nullable;
  int? maxLength;
  int? precision;
  int? scale;
  String? label;

  Map<String, dynamic> toJson() => {
        'name': name,
        'edmType': edmType,
        'nullable': nullable,
        if (maxLength != null) 'maxLength': maxLength,
        if (precision != null) 'precision': precision,
        if (scale != null) 'scale': scale,
        if (label != null) 'label': label,
      };

  factory Property.fromJson(Map<String, dynamic> json) => Property(
        name: json['name'] as String,
        edmType: json['edmType'] as String,
        nullable: (json['nullable'] as bool?) ?? true,
        maxLength: json['maxLength'] as int?,
        precision: json['precision'] as int?,
        scale: json['scale'] as int?,
        label: json['label'] as String?,
      );

  /// All OData v2 EDM primitive types we surface in the picker.
  static const List<String> edmTypes = [
    'Edm.String',
    'Edm.Boolean',
    'Edm.Int16',
    'Edm.Int32',
    'Edm.Int64',
    'Edm.Decimal',
    'Edm.Double',
    'Edm.Single',
    'Edm.DateTime',
    'Edm.DateTimeOffset',
    'Edm.Time',
    'Edm.Guid',
    'Edm.Byte',
    'Edm.Binary',
  ];
}

class EntitySetSummary {
  EntitySetSummary({
    required this.name,
    required this.entityTypeName,
    required this.rowCount,
  });

  final String name;
  final String entityTypeName;
  final int rowCount;

  factory EntitySetSummary.fromJson(Map<String, dynamic> json) =>
      EntitySetSummary(
        name: json['name'] as String,
        entityTypeName: json['entityTypeName'] as String,
        rowCount: (json['rowCount'] as int?) ?? 0,
      );
}

// ─── Integration models ───────────────────────────────────────────────

class IntegrationConfig {
  IntegrationConfig({required this.surreal, required this.mappings});

  final SurrealConnection surreal;
  final List<MappingConfig> mappings;

  factory IntegrationConfig.fromJson(Map<String, dynamic> json) =>
      IntegrationConfig(
        surreal: SurrealConnection.fromJson(
            (json['surreal'] as Map?)?.cast<String, dynamic>() ?? const {}),
        mappings: ((json['mappings'] as List?) ?? const [])
            .cast<Map<String, dynamic>>()
            .map(MappingConfig.fromJson)
            .toList(),
      );
}

class SurrealConnection {
  SurrealConnection({
    required this.endpoint,
    required this.namespace,
    required this.database,
    required this.username,
    required this.passwordSet,
  });

  final String endpoint;
  final String namespace;
  final String database;
  final String username;
  final bool passwordSet;

  factory SurrealConnection.fromJson(Map<String, dynamic> json) =>
      SurrealConnection(
        endpoint: (json['endpoint'] as String?) ?? '',
        namespace: (json['namespace'] as String?) ?? '',
        database: (json['database'] as String?) ?? '',
        username: (json['username'] as String?) ?? '',
        passwordSet: (json['passwordSet'] as bool?) ?? false,
      );
}

class MappingConfig {
  MappingConfig({
    required this.collection,
    required this.table,
    required this.direction,
    this.fieldMap = const {},
    this.pushFilter = const {},
  });

  final String collection;
  final String table;
  final String direction; // inbound | outbound | both
  final Map<String, String> fieldMap;
  final Map<String, String> pushFilter;

  static const List<String> directions = ['inbound', 'outbound', 'both'];

  bool get canPull => direction == 'inbound' || direction == 'both';
  bool get canPush => direction == 'outbound' || direction == 'both';

  Map<String, dynamic> toJson() => {
        'collection': collection,
        'table': table,
        'direction': direction,
        'fieldMap': fieldMap,
        'pushFilter': pushFilter,
      };

  factory MappingConfig.fromJson(Map<String, dynamic> json) => MappingConfig(
        collection: json['collection'] as String,
        table: (json['table'] as String?) ?? json['collection'] as String,
        direction: (json['direction'] as String?) ?? 'inbound',
        fieldMap: ((json['fieldMap'] as Map?) ?? const {})
            .map((k, v) => MapEntry(k.toString(), v.toString())),
        pushFilter: ((json['pushFilter'] as Map?) ?? const {})
            .map((k, v) => MapEntry(k.toString(), v.toString())),
      );
}

class SyncResult {
  SyncResult({
    required this.direction,
    required this.collection,
    required this.status,
    required this.dryRun,
    this.rowsScanned = 0,
    this.rowsCreated = 0,
    this.rowsUpdated = 0,
    this.rowsSkipped = 0,
    this.rowsFailed = 0,
    this.durationMs = 0,
    this.error,
    this.errors = const [],
  });

  final String direction;
  final String collection;
  final String status;
  final bool dryRun;
  final int rowsScanned;
  final int rowsCreated;
  final int rowsUpdated;
  final int rowsSkipped;
  final int rowsFailed;
  final int durationMs;
  final String? error;
  final List<String> errors;

  factory SyncResult.fromJson(Map<String, dynamic> json) => SyncResult(
        direction: (json['direction'] as String?) ?? '',
        collection: (json['collection'] as String?) ?? '',
        status: (json['status'] as String?) ?? '',
        dryRun: (json['dryRun'] as bool?) ?? false,
        rowsScanned: (json['rowsScanned'] as int?) ?? 0,
        rowsCreated: (json['rowsCreated'] as int?) ?? 0,
        rowsUpdated: (json['rowsUpdated'] as int?) ?? 0,
        rowsSkipped: (json['rowsSkipped'] as int?) ?? 0,
        rowsFailed: (json['rowsFailed'] as int?) ?? 0,
        durationMs: (json['durationMs'] as int?) ?? 0,
        error: json['error'] as String?,
        errors: ((json['errors'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
      );
}

class AuditPage {
  AuditPage({required this.total, required this.events});

  final int total;
  final List<AuditEntry> events;

  factory AuditPage.fromJson(Map<String, dynamic> json) => AuditPage(
        total: (json['total'] as int?) ?? 0,
        events: ((json['events'] as List?) ?? const [])
            .cast<Map<String, dynamic>>()
            .map(AuditEntry.fromJson)
            .toList(),
      );
}

class AuditEntry {
  AuditEntry({
    required this.id,
    required this.timestamp,
    required this.action,
    this.collection,
    required this.status,
    this.dryRun = false,
    this.rowsScanned,
    this.rowsCreated,
    this.rowsUpdated,
    this.rowsSkipped,
    this.rowsFailed,
    this.durationMs,
    this.message,
  });

  final String id;
  final DateTime timestamp;
  final String action;
  final String? collection;
  final String status;
  final bool dryRun;
  final int? rowsScanned;
  final int? rowsCreated;
  final int? rowsUpdated;
  final int? rowsSkipped;
  final int? rowsFailed;
  final int? durationMs;
  final String? message;

  factory AuditEntry.fromJson(Map<String, dynamic> json) => AuditEntry(
        id: json['id'] as String,
        timestamp: DateTime.parse(json['timestamp'] as String),
        action: json['action'] as String,
        collection: json['collection'] as String?,
        status: json['status'] as String,
        dryRun: (json['dryRun'] as bool?) ?? false,
        rowsScanned: json['rowsScanned'] as int?,
        rowsCreated: json['rowsCreated'] as int?,
        rowsUpdated: json['rowsUpdated'] as int?,
        rowsSkipped: json['rowsSkipped'] as int?,
        rowsFailed: json['rowsFailed'] as int?,
        durationMs: json['durationMs'] as int?,
        message: json['message'] as String?,
      );
}
