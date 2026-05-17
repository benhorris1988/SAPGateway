import 'dart:convert';
import 'dart:io';

import 'models.dart';
import 'seed.dart';

/// In-memory store with optional JSON persistence. Single-process — protected
/// by Dart's single-isolate semantics, no extra locking needed.
class GatewayStore {
  GatewayStore({this.persistencePath});

  final String? persistencePath;
  final List<GatewayService> services = <GatewayService>[];

  Future<void> load() async {
    if (persistencePath != null) {
      final file = File(persistencePath!);
      if (await file.exists()) {
        final raw = await file.readAsString();
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        final list = (decoded['services'] as List).cast<Map<String, dynamic>>();
        services
          ..clear()
          ..addAll(list.map(GatewayService.fromJson));
        return;
      }
    }
    services
      ..clear()
      ..addAll(buildSeed());
    await save();
  }

  Future<void> save() async {
    if (persistencePath == null) return;
    final file = File(persistencePath!);
    await file.parent.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(<String, dynamic>{
        'services': services.map((s) => s.toJson()).toList(),
      }),
    );
  }

  Future<void> reset() async {
    services
      ..clear()
      ..addAll(buildSeed());
    await save();
  }

  GatewayService? serviceByName(String name) {
    for (final s in services) {
      if (s.name == name) return s;
    }
    return null;
  }
}
