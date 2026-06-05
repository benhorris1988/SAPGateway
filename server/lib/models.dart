// Domain model for the mock SAP Gateway. Everything is JSON-serialisable so
// the same shapes are shared with the Flutter admin client.

class GatewayService {
  GatewayService({
    required this.name,
    required this.namespace,
    this.description = '',
    List<EntityType>? entityTypes,
    List<EntitySet>? entitySets,
  })  : entityTypes = entityTypes ?? <EntityType>[],
        entitySets = entitySets ?? <EntitySet>[];

  String name;
  String namespace;
  String description;
  final List<EntityType> entityTypes;
  final List<EntitySet> entitySets;

  EntityType? entityTypeByName(String name) {
    for (final t in entityTypes) {
      if (t.name == name) return t;
    }
    return null;
  }

  EntitySet? entitySetByName(String name) {
    for (final s in entitySets) {
      if (s.name == name) return s;
    }
    return null;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'name': name,
        'namespace': namespace,
        'description': description,
        'entityTypes': entityTypes.map((e) => e.toJson()).toList(),
        'entitySets': entitySets.map((e) => e.toJson()).toList(),
      };

  factory GatewayService.fromJson(Map<String, dynamic> json) => GatewayService(
        name: json['name'] as String,
        namespace: (json['namespace'] as String?) ?? json['name'] as String,
        description: (json['description'] as String?) ?? '',
        entityTypes: ((json['entityTypes'] as List?) ?? const [])
            .cast<Map<String, dynamic>>()
            .map(EntityType.fromJson)
            .toList(),
        entitySets: ((json['entitySets'] as List?) ?? const [])
            .cast<Map<String, dynamic>>()
            .map(EntitySet.fromJson)
            .toList(),
      );
}

class EntityType {
  EntityType({
    required this.name,
    List<Property>? properties,
    List<String>? keys,
  })  : properties = properties ?? <Property>[],
        keys = keys ?? <String>[];

  String name;
  final List<Property> properties;
  final List<String> keys;

  Property? propertyByName(String name) {
    for (final p in properties) {
      if (p.name == name) return p;
    }
    return null;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'name': name,
        'keys': keys,
        'properties': properties.map((p) => p.toJson()).toList(),
      };

  factory EntityType.fromJson(Map<String, dynamic> json) => EntityType(
        name: json['name'] as String,
        keys: ((json['keys'] as List?) ?? const []).cast<String>(),
        properties: ((json['properties'] as List?) ?? const [])
            .cast<Map<String, dynamic>>()
            .map(Property.fromJson)
            .toList(),
      );
}

/// One column on an EntityType. `edmType` is an OData v2 EDM primitive type
/// (`Edm.String`, `Edm.Int32`, `Edm.Decimal`, `Edm.DateTime`, `Edm.Boolean`,
/// `Edm.Double`, `Edm.Guid`).
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

  Map<String, dynamic> toJson() => <String, dynamic>{
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
}

class EntitySet {
  EntitySet({
    required this.name,
    required this.entityTypeName,
    List<Map<String, dynamic>>? rows,
  }) : rows = rows ?? <Map<String, dynamic>>[];

  String name;
  String entityTypeName;
  final List<Map<String, dynamic>> rows;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'name': name,
        'entityTypeName': entityTypeName,
        'rows': rows,
      };

  factory EntitySet.fromJson(Map<String, dynamic> json) => EntitySet(
        name: json['name'] as String,
        entityTypeName: json['entityTypeName'] as String,
        rows: ((json['rows'] as List?) ?? const [])
            .cast<Map<String, dynamic>>()
            .map((m) => Map<String, dynamic>.from(m))
            .toList(),
      );
}
