// Shared OData $filter parser. Used by both the v2 and v4 handlers — the
// query grammar is identical between the two specs for the subset of
// operators we expose (eq, ne, gt, ge, lt, le, and, or, plus the standard
// string functions).

abstract class FilterNode {
  bool? evaluate(Map<String, dynamic> row);
}

class FilterBinOp implements FilterNode {
  FilterBinOp(this.op, this.left, this.right);
  final String op;
  final FilterNode left;
  final FilterNode right;

  @override
  bool? evaluate(Map<String, dynamic> row) {
    if (op == 'and') {
      return (left.evaluate(row) ?? false) && (right.evaluate(row) ?? false);
    }
    if (op == 'or') {
      return (left.evaluate(row) ?? false) || (right.evaluate(row) ?? false);
    }
    final l = (left as FilterValue).value(row);
    final r = (right as FilterValue).value(row);
    return _compare(op, l, r);
  }

  static bool _compare(String op, dynamic l, dynamic r) {
    final cmp = compareValues(l, r);
    switch (op) {
      case 'eq':
        return cmp == 0;
      case 'ne':
        return cmp != 0;
      case 'gt':
        return cmp > 0;
      case 'ge':
        return cmp >= 0;
      case 'lt':
        return cmp < 0;
      case 'le':
        return cmp <= 0;
    }
    return false;
  }
}

abstract class FilterValue implements FilterNode {
  dynamic value(Map<String, dynamic> row);
  @override
  bool? evaluate(Map<String, dynamic> row) {
    final v = value(row);
    if (v is bool) return v;
    return null;
  }
}

class FilterLit extends FilterValue {
  FilterLit(this.v);
  final dynamic v;
  @override
  dynamic value(Map<String, dynamic> row) => v;
}

class FilterField extends FilterValue {
  FilterField(this.name);
  final String name;
  @override
  dynamic value(Map<String, dynamic> row) => row[name];
}

class FilterFunc extends FilterValue {
  FilterFunc(this.name, this.args);
  final String name;
  final List<FilterValue> args;

  @override
  dynamic value(Map<String, dynamic> row) {
    String? s(int i) => args[i].value(row)?.toString();
    switch (name) {
      case 'substringof':
        return (s(1) ?? '').contains(s(0) ?? '');
      case 'contains':
        return (s(0) ?? '').contains(s(1) ?? '');
      case 'startswith':
        return (s(0) ?? '').startsWith(s(1) ?? '');
      case 'endswith':
        return (s(0) ?? '').endsWith(s(1) ?? '');
      case 'tolower':
        return (s(0) ?? '').toLowerCase();
      case 'toupper':
        return (s(0) ?? '').toUpperCase();
      case 'length':
        return (s(0) ?? '').length;
      case 'indexof':
        return (s(0) ?? '').indexOf(s(1) ?? '');
      case 'trim':
        return (s(0) ?? '').trim();
    }
    return null;
  }

  @override
  bool? evaluate(Map<String, dynamic> row) {
    final v = value(row);
    if (v is bool) return v;
    return null;
  }
}

int compareValues(dynamic a, dynamic b) {
  if (a == null && b == null) return 0;
  if (a == null) return -1;
  if (b == null) return 1;
  if (a is num && b is num) return a.compareTo(b);
  final an = num.tryParse(a.toString());
  final bn = num.tryParse(b.toString());
  if (an != null && bn != null) return an.compareTo(bn);
  return a.toString().compareTo(b.toString());
}

class FilterParser {
  FilterParser(this._src);

  final String _src;
  int _pos = 0;

  FilterNode parse() {
    final node = _parseOr();
    _skipWs();
    if (_pos != _src.length) {
      throw FormatException('Unexpected trailing input at $_pos');
    }
    return node;
  }

  FilterNode _parseOr() {
    var left = _parseAnd();
    while (true) {
      _skipWs();
      if (_consumeKeyword('or')) {
        final right = _parseAnd();
        left = FilterBinOp('or', left, right);
      } else {
        return left;
      }
    }
  }

  FilterNode _parseAnd() {
    var left = _parseCmp();
    while (true) {
      _skipWs();
      if (_consumeKeyword('and')) {
        final right = _parseCmp();
        left = FilterBinOp('and', left, right);
      } else {
        return left;
      }
    }
  }

  FilterNode _parseCmp() {
    final left = _parsePrim();
    _skipWs();
    for (final op in const ['eq', 'ne', 'ge', 'le', 'gt', 'lt']) {
      if (_consumeKeyword(op)) {
        final right = _parsePrim();
        if (left is! FilterValue || right is! FilterValue) {
          throw FormatException('Operands of "$op" must be values');
        }
        return FilterBinOp(op, left, right);
      }
    }
    return left;
  }

  FilterNode _parsePrim() {
    _skipWs();
    if (_pos >= _src.length) throw const FormatException('Unexpected end');
    final c = _src[_pos];
    if (c == '(') {
      _pos++;
      final inner = _parseOr();
      _skipWs();
      if (_pos >= _src.length || _src[_pos] != ')') {
        throw const FormatException('Missing ")"');
      }
      _pos++;
      return inner;
    }
    if (c == "'") return _parseString();
    if (RegExp(r'[0-9\-]').hasMatch(c)) return _parseNumber();

    final ident = _parseIdent();
    _skipWs();
    if (_pos < _src.length && _src[_pos] == '(') {
      _pos++;
      final args = <FilterValue>[];
      _skipWs();
      if (_pos < _src.length && _src[_pos] != ')') {
        while (true) {
          final v = _parsePrim();
          if (v is! FilterValue) {
            throw const FormatException('Function arguments must be values');
          }
          args.add(v);
          _skipWs();
          if (_pos < _src.length && _src[_pos] == ',') {
            _pos++;
            continue;
          }
          break;
        }
      }
      _skipWs();
      if (_pos >= _src.length || _src[_pos] != ')') {
        throw FormatException('Missing ")" after function $ident');
      }
      _pos++;
      return FilterFunc(ident, args);
    }
    if (ident == 'true') return FilterLit(true);
    if (ident == 'false') return FilterLit(false);
    if (ident == 'null') return FilterLit(null);
    return FilterField(ident);
  }

  FilterValue _parseString() {
    final buf = StringBuffer();
    _pos++;
    while (_pos < _src.length) {
      final c = _src[_pos];
      if (c == "'") {
        if (_pos + 1 < _src.length && _src[_pos + 1] == "'") {
          buf.write("'");
          _pos += 2;
          continue;
        }
        _pos++;
        return FilterLit(buf.toString());
      }
      buf.write(c);
      _pos++;
    }
    throw const FormatException('Unterminated string literal');
  }

  FilterValue _parseNumber() {
    final m = RegExp(r'-?\d+(\.\d+)?').matchAsPrefix(_src, _pos);
    if (m == null) throw const FormatException('Expected number');
    _pos = m.end;
    final txt = m.group(0)!;
    final n = num.parse(txt);
    return FilterLit(n);
  }

  String _parseIdent() {
    final m = RegExp(r'[A-Za-z_][A-Za-z0-9_]*').matchAsPrefix(_src, _pos);
    if (m == null) {
      throw FormatException('Expected identifier at $_pos in "$_src"');
    }
    _pos = m.end;
    return m.group(0)!;
  }

  bool _consumeKeyword(String kw) {
    _skipWs();
    if (_pos + kw.length > _src.length) return false;
    final slice = _src.substring(_pos, _pos + kw.length).toLowerCase();
    if (slice != kw) return false;
    final next = _pos + kw.length < _src.length ? _src[_pos + kw.length] : ' ';
    if (RegExp(r'[A-Za-z0-9_]').hasMatch(next)) return false;
    _pos += kw.length;
    return true;
  }

  void _skipWs() {
    while (_pos < _src.length && _src[_pos].trim().isEmpty) {
      _pos++;
    }
  }
}
