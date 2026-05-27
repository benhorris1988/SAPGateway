import 'dart:collection';
import 'dart:io';

/// Severity levels, ordered. `error` is the highest.
enum LogLevel { debug, info, warn, error }

extension LogLevelName on LogLevel {
  String get label => switch (this) {
        LogLevel.debug => 'DEBUG',
        LogLevel.info => 'INFO',
        LogLevel.warn => 'WARN',
        LogLevel.error => 'ERROR',
      };

  static LogLevel? parse(String? s) {
    switch (s?.toLowerCase()) {
      case 'debug':
        return LogLevel.debug;
      case 'info':
        return LogLevel.info;
      case 'warn':
      case 'warning':
        return LogLevel.warn;
      case 'error':
        return LogLevel.error;
    }
    return null;
  }
}

class LogEntry {
  LogEntry({
    required this.timestamp,
    required this.level,
    required this.message,
    this.source = 'server',
    this.error,
    this.stackTrace,
  });

  final DateTime timestamp;
  final LogLevel level;
  final String message;

  /// `server` for backend-originated entries, `client` for entries shipped in
  /// from the Flutter app via `/admin/logs/client`.
  final String source;
  final String? error;
  final String? stackTrace;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'timestamp': timestamp.toUtc().toIso8601String(),
        'level': level.label,
        'source': source,
        'message': message,
        if (error != null) 'error': error,
        if (stackTrace != null) 'stackTrace': stackTrace,
      };
}

/// Process-wide logger. Writes human-readable lines to stdout/stderr, keeps a
/// bounded in-memory ring buffer (served from `/admin/logs`), and optionally
/// appends every entry to a file.
///
/// A single shared instance is used so the store, request pipeline, and admin
/// handlers can all log without threading a logger through every constructor.
class GatewayLogger {
  GatewayLogger._();
  static final GatewayLogger instance = GatewayLogger._();

  LogLevel _minLevel = LogLevel.info;
  String? _filePath;
  int _bufferSize = 1000;
  final ListQueue<LogEntry> _buffer = ListQueue<LogEntry>();

  void configure({
    LogLevel minLevel = LogLevel.info,
    String? filePath,
    int bufferSize = 1000,
  }) {
    _minLevel = minLevel;
    _filePath = (filePath != null && filePath.trim().isEmpty) ? null : filePath;
    _bufferSize = bufferSize;
  }

  void debug(String message, {Object? error, StackTrace? stackTrace}) =>
      log(LogLevel.debug, message, error: error, stackTrace: stackTrace);
  void info(String message, {Object? error, StackTrace? stackTrace}) =>
      log(LogLevel.info, message, error: error, stackTrace: stackTrace);
  void warn(String message, {Object? error, StackTrace? stackTrace}) =>
      log(LogLevel.warn, message, error: error, stackTrace: stackTrace);
  void error(String message, {Object? error, StackTrace? stackTrace}) =>
      log(LogLevel.error, message, error: error, stackTrace: stackTrace);

  void log(
    LogLevel level,
    String message, {
    Object? error,
    StackTrace? stackTrace,
    String source = 'server',
  }) {
    if (level.index < _minLevel.index) return;
    final entry = LogEntry(
      timestamp: DateTime.now(),
      level: level,
      message: message,
      source: source,
      error: error?.toString(),
      stackTrace: stackTrace?.toString(),
    );
    _record(entry);
  }

  /// Ingest a log entry that originated outside the server (i.e. the Flutter
  /// client). Always recorded regardless of [_minLevel] so client crashes are
  /// never silently dropped.
  void ingest(LogEntry entry) => _record(entry, force: true);

  void _record(LogEntry entry, {bool force = false}) {
    if (!force && entry.level.index < _minLevel.index) return;

    _buffer.add(entry);
    while (_buffer.length > _bufferSize) {
      _buffer.removeFirst();
    }

    final ts = entry.timestamp.toUtc().toIso8601String();
    final line = StringBuffer(
        '$ts [${entry.level.label}] (${entry.source}) ${entry.message}');
    if (entry.error != null) line.write(' | error: ${entry.error}');
    final sink =
        entry.level.index >= LogLevel.warn.index ? stderr : stdout;
    sink.writeln(line.toString());
    if (entry.stackTrace != null &&
        entry.level.index >= LogLevel.warn.index) {
      sink.writeln(entry.stackTrace);
    }

    _appendToFile(entry, line.toString());
  }

  void _appendToFile(LogEntry entry, String line) {
    final path = _filePath;
    if (path == null) return;
    try {
      final file = File(path);
      file.parent.createSync(recursive: true);
      final buf = StringBuffer(line)..write('\n');
      if (entry.stackTrace != null) buf
        ..write(entry.stackTrace)
        ..write('\n');
      file.writeAsStringSync(buf.toString(), mode: FileMode.append);
    } catch (e) {
      // Never let logging failures take down a request. Surface once on stderr.
      stderr.writeln('(logger) failed to write to $path: $e');
    }
  }

  /// Most recent entries, oldest first. Optionally filtered by minimum level
  /// and capped to [limit].
  List<LogEntry> recent({int? limit, LogLevel? minLevel, String? source}) {
    Iterable<LogEntry> entries = _buffer;
    if (minLevel != null) {
      entries = entries.where((e) => e.level.index >= minLevel.index);
    }
    if (source != null) {
      entries = entries.where((e) => e.source == source);
    }
    var list = entries.toList();
    if (limit != null && list.length > limit) {
      list = list.sublist(list.length - limit);
    }
    return list;
  }

  void clear() => _buffer.clear();
}

/// Shorthand used across the server.
GatewayLogger get logger => GatewayLogger.instance;
