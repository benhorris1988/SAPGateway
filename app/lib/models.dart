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

/// One row from `/admin/connections` — describes one connection surface the
/// gateway exposes (OData v2, v4, REST, SOAP, IDoc, SQL Server, SurrealDB).
class ConnectionInfo {
  ConnectionInfo({
    required this.id,
    required this.name,
    required this.kind,
    required this.description,
    required this.root,
    required this.example,
    required this.methods,
  });

  final String id;
  final String name;
  final String kind; // "sap" or "database"
  final String description;
  final String root;
  final String example;
  final List<String> methods;

  factory ConnectionInfo.fromJson(Map<String, dynamic> json) => ConnectionInfo(
        id: json['id'] as String,
        name: json['name'] as String,
        kind: (json['kind'] as String?) ?? 'sap',
        description: (json['description'] as String?) ?? '',
        root: (json['root'] as String?) ?? '',
        example: (json['example'] as String?) ?? '',
        methods: ((json['methods'] as List?) ?? const []).cast<String>(),
      );
}
