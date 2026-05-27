import 'dart:collection';
import 'dart:developer' as developer;

/// Severity levels, ordered. `error` is the highest.
enum AppLogLevel { debug, info, warn, error }

extension AppLogLevelName on AppLogLevel {
  String get label => switch (this) {
        AppLogLevel.debug => 'DEBUG',
        AppLogLevel.info => 'INFO',
        AppLogLevel.warn => 'WARN',
        AppLogLevel.error => 'ERROR',
      };

  /// Maps onto the integer levels `dart:developer` expects (mirrors the
  /// `logging` package: FINE=500, INFO=800, WARNING=900, SEVERE=1000).
  int get developerLevel => switch (this) {
        AppLogLevel.debug => 500,
        AppLogLevel.info => 800,
        AppLogLevel.warn => 900,
        AppLogLevel.error => 1000,
      };
}

class AppLogEntry {
  AppLogEntry({
    required this.timestamp,
    required this.level,
    required this.message,
    this.error,
    this.stackTrace,
  });

  final DateTime timestamp;
  final AppLogLevel level;
  final String message;
  final String? error;
  final String? stackTrace;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'timestamp': timestamp.toUtc().toIso8601String(),
        'level': level.label,
        'message': message,
        if (error != null) 'error': error,
        if (stackTrace != null) 'stackTrace': stackTrace,
      };
}

/// Called for entries the app wants pushed to the backend. Implementations
/// must never throw and must not log (to avoid feedback loops).
typedef LogShipper = void Function(AppLogEntry entry);

/// App-wide error logger. Writes to the Dart DevTools / `flutter logs` console
/// via `dart:developer`, keeps a bounded in-memory buffer (surfaced on the
/// Settings screen), and optionally ships error-level entries to the gateway's
/// `/admin/logs/client` endpoint so client and server failures share one log.
class AppLog {
  AppLog._();
  static final AppLog instance = AppLog._();

  static const int _bufferSize = 300;
  final ListQueue<AppLogEntry> _buffer = ListQueue<AppLogEntry>();
  LogShipper? _shipper;

  void attachShipper(LogShipper shipper) => _shipper = shipper;

  void debug(String message, {Object? error, StackTrace? stackTrace}) =>
      _log(AppLogLevel.debug, message, error, stackTrace);
  void info(String message, {Object? error, StackTrace? stackTrace}) =>
      _log(AppLogLevel.info, message, error, stackTrace);
  void warn(String message, {Object? error, StackTrace? stackTrace}) =>
      _log(AppLogLevel.warn, message, error, stackTrace);
  void error(String message, {Object? error, StackTrace? stackTrace}) =>
      _log(AppLogLevel.error, message, error, stackTrace);

  void _log(
    AppLogLevel level,
    String message,
    Object? error,
    StackTrace? stackTrace,
  ) {
    final entry = AppLogEntry(
      timestamp: DateTime.now(),
      level: level,
      message: message,
      error: error?.toString(),
      stackTrace: stackTrace?.toString(),
    );

    _buffer.add(entry);
    while (_buffer.length > _bufferSize) {
      _buffer.removeFirst();
    }

    developer.log(
      message,
      name: 'SAPGateway',
      level: level.developerLevel,
      error: error,
      stackTrace: stackTrace,
      time: entry.timestamp,
    );

    // Only ship the most severe entries so we don't flood the backend with
    // routine 404s / validation warnings.
    if (level == AppLogLevel.error) {
      try {
        _shipper?.call(entry);
      } catch (_) {
        // Shipping is best-effort; never let it surface a new error.
      }
    }
  }

  /// Recent entries, oldest first.
  List<AppLogEntry> get recent => _buffer.toList();

  void clear() => _buffer.clear();
}

/// Shorthand used across the app.
AppLog get appLog => AppLog.instance;
