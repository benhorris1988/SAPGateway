import 'filter.dart';

/// Tiny SELECT-only SQL parser. Used by the SQL Server and SurrealDB mock
/// surfaces so they share one definition of "what counts as queryable".
///
/// Supports:
///   SELECT [TOP n] [DISTINCT] <col-list>|*
///   FROM <table>           (qualified `<schema>.<table>` allowed)
///   [WHERE <predicate>]    (OData $filter-style: eq/ne/gt/ge/lt/le/and/or)
///   [GROUP BY <cols>]      (currently treated as ignored — no aggregations)
///   [ORDER BY <col> [ASC|DESC] [, ...]]
///   [OFFSET <n> ROWS [FETCH NEXT <m> ROWS ONLY]]
///   [LIMIT <m> [OFFSET <n>]]
///
/// `WHERE` accepts both OData operators (`Land1 eq 'US'`) and standard SQL
/// (`Land1 = 'US' AND Erdat > '2020-01-01'`). Internally everything is
/// rewritten to the OData grammar before parsing.
class SqlSelect {
  SqlSelect({
    required this.table,
    required this.schema,
    required this.columns,
    required this.allColumns,
    required this.where,
    required this.orderBy,
    required this.limit,
    required this.offset,
    required this.distinct,
  });

  final String table;
  final String? schema;
  final List<String> columns;
  final bool allColumns;
  final FilterNode? where;
  final List<({String field, bool desc})> orderBy;
  final int? limit;
  final int offset;
  final bool distinct;
}

class SqlParseException implements Exception {
  SqlParseException(this.message);
  final String message;
  @override
  String toString() => 'SqlParseException: $message';
}

SqlSelect parseSelect(String sql) {
  final stripped = _stripTrailingSemicolons(sql.trim());
  final p = _Parser(stripped);
  p.expectKw('select');
  bool distinct = false;
  if (p.matchKw('distinct')) distinct = true;

  int? topLimit;
  if (p.matchKw('top')) {
    final n = p.consumeInt();
    if (n == null) throw SqlParseException('expected number after TOP');
    topLimit = n;
  }

  bool allColumns = false;
  final cols = <String>[];
  if (p.peek() == '*') {
    p.advance();
    allColumns = true;
  } else {
    cols.add(p.consumeIdent());
    while (p.peek() == ',') {
      p.advance();
      cols.add(p.consumeIdent());
    }
  }
  p.expectKw('from');
  final ident1 = p.consumeIdent();
  String table = ident1;
  String? schema;
  if (p.peek() == '.') {
    p.advance();
    schema = ident1;
    table = p.consumeIdent();
  }

  FilterNode? where;
  if (p.matchKw('where')) {
    final start = p.position;
    final end = _consumeUntilOneOf(p, [
      'group',
      'order',
      'offset',
      'limit',
      'fetch',
    ]);
    final clause = p.source.substring(start, end).trim();
    final odataClause = _sqlToOData(clause);
    where = FilterParser(odataClause).parse();
  }

  // GROUP BY is accepted but ignored.
  if (p.matchKw('group')) {
    p.expectKw('by');
    _consumeUntilOneOf(p, ['order', 'offset', 'limit', 'fetch']);
  }

  final orderBy = <({String field, bool desc})>[];
  if (p.matchKw('order')) {
    p.expectKw('by');
    while (true) {
      final col = p.consumeIdent();
      var desc = false;
      if (p.matchKw('desc')) {
        desc = true;
      } else {
        p.matchKw('asc');
      }
      orderBy.add((field: col, desc: desc));
      if (p.peek() != ',') break;
      p.advance();
    }
  }

  int? limit = topLimit;
  int offset = 0;
  if (p.matchKw('offset')) {
    offset = p.consumeInt() ?? 0;
    p.matchKw('rows');
    if (p.matchKw('fetch')) {
      p.matchKw('next');
      final n = p.consumeInt() ?? 0;
      p.matchKw('rows');
      p.matchKw('only');
      limit = n;
    }
  }
  if (p.matchKw('limit')) {
    final n = p.consumeInt();
    if (n != null) limit = n;
    if (p.matchKw('offset')) {
      offset = p.consumeInt() ?? offset;
    }
  }

  p.skipWs();
  if (p.position != p.source.length) {
    throw SqlParseException(
        'unexpected trailing input: ${p.source.substring(p.position)}');
  }

  return SqlSelect(
    table: table,
    schema: schema,
    columns: cols,
    allColumns: allColumns,
    where: where,
    orderBy: orderBy,
    limit: limit,
    offset: offset,
    distinct: distinct,
  );
}

String _stripTrailingSemicolons(String s) {
  var t = s;
  while (t.endsWith(';')) {
    t = t.substring(0, t.length - 1).trimRight();
  }
  return t;
}

int _consumeUntilOneOf(_Parser p, List<String> kws) {
  p.skipWs();
  while (p.position < p.source.length) {
    final pos = p.position;
    for (final kw in kws) {
      if (p.matchKwNoConsume(kw)) {
        return pos;
      }
    }
    // Skip over string literals so 'order' inside a quoted value doesn't trip.
    if (p.source[p.position] == "'") {
      p.position++;
      while (p.position < p.source.length) {
        if (p.source[p.position] == "'") {
          if (p.position + 1 < p.source.length &&
              p.source[p.position + 1] == "'") {
            p.position += 2;
            continue;
          }
          p.position++;
          break;
        }
        p.position++;
      }
      continue;
    }
    p.position++;
  }
  return p.source.length;
}

/// Translate a SQL WHERE clause into OData $filter syntax. Idempotent for
/// expressions already written in OData form (the existing operators survive
/// untouched because we only swap specific symbols).
String _sqlToOData(String sql) {
  // Replace SQL comparison operators with their OData equivalents, taking care
  // not to mangle string literals.
  final out = StringBuffer();
  var i = 0;
  while (i < sql.length) {
    final c = sql[i];
    if (c == "'") {
      out.write(c);
      i++;
      while (i < sql.length) {
        out.write(sql[i]);
        if (sql[i] == "'") {
          if (i + 1 < sql.length && sql[i + 1] == "'") {
            out.write(sql[i + 1]);
            i += 2;
            continue;
          }
          i++;
          break;
        }
        i++;
      }
      continue;
    }
    if (c == '<' && i + 1 < sql.length && sql[i + 1] == '>') {
      out.write(' ne ');
      i += 2;
      continue;
    }
    if (c == '!' && i + 1 < sql.length && sql[i + 1] == '=') {
      out.write(' ne ');
      i += 2;
      continue;
    }
    if (c == '<' && i + 1 < sql.length && sql[i + 1] == '=') {
      out.write(' le ');
      i += 2;
      continue;
    }
    if (c == '>' && i + 1 < sql.length && sql[i + 1] == '=') {
      out.write(' ge ');
      i += 2;
      continue;
    }
    if (c == '=') {
      out.write(' eq ');
      i++;
      continue;
    }
    if (c == '<') {
      out.write(' lt ');
      i++;
      continue;
    }
    if (c == '>') {
      out.write(' gt ');
      i++;
      continue;
    }
    out.write(c);
    i++;
  }
  return out.toString();
}

class _Parser {
  _Parser(this.source);
  final String source;
  int position = 0;

  void skipWs() {
    while (position < source.length && source[position].trim().isEmpty) {
      position++;
    }
  }

  String? peek() {
    skipWs();
    if (position >= source.length) return null;
    return source[position];
  }

  void advance() {
    skipWs();
    position++;
  }

  bool matchKw(String kw) {
    skipWs();
    if (position + kw.length > source.length) return false;
    final slice = source.substring(position, position + kw.length).toLowerCase();
    if (slice != kw.toLowerCase()) return false;
    final next =
        position + kw.length < source.length ? source[position + kw.length] : ' ';
    if (RegExp(r'[A-Za-z0-9_]').hasMatch(next)) return false;
    position += kw.length;
    return true;
  }

  bool matchKwNoConsume(String kw) {
    final before = position;
    final ok = matchKw(kw);
    position = before;
    return ok;
  }

  void expectKw(String kw) {
    if (!matchKw(kw)) {
      throw SqlParseException(
          'expected keyword "$kw" at position $position in "$source"');
    }
  }

  String consumeIdent() {
    skipWs();
    // Allow bracket-quoted names: [Customer Set]
    if (position < source.length && source[position] == '[') {
      final end = source.indexOf(']', position + 1);
      if (end < 0) throw SqlParseException('unterminated [identifier]');
      final ident = source.substring(position + 1, end);
      position = end + 1;
      return ident;
    }
    if (position < source.length && source[position] == '"') {
      final end = source.indexOf('"', position + 1);
      if (end < 0) throw SqlParseException('unterminated "identifier"');
      final ident = source.substring(position + 1, end);
      position = end + 1;
      return ident;
    }
    final m = RegExp(r'[A-Za-z_][A-Za-z0-9_]*').matchAsPrefix(source, position);
    if (m == null) {
      throw SqlParseException(
          'expected identifier at position $position in "$source"');
    }
    position = m.end;
    return m.group(0)!;
  }

  int? consumeInt() {
    skipWs();
    final m = RegExp(r'\d+').matchAsPrefix(source, position);
    if (m == null) return null;
    position = m.end;
    return int.parse(m.group(0)!);
  }
}
