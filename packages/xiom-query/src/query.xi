// XIOM -- xiom.query: simple filter expressions over flat key/value records
// Port task: replace the xiom.query placeholder with a real, tested,
// pure-XIOM package (no FFI).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Model: an expression such as `age >= 30 AND city = "New York"` parses into
// Query: four parallel Vec[Str] fields (fields, ops, values, joins) with one
// entry per term. joins[i] is the connector before term i -- "and" or "or" --
// and joins[0] is always "". Terms are whitespace-separated tokens; a quoted
// token may contain whitespace. There are no parentheses and no precedence:
// query_matches folds the terms strictly left to right with the recorded
// connectors (see SPEC.md section 3).
//
// Language notes (XIOM v0.61.3): free functions only, no self methods, no
// lambdas, no Vec[StructType]; Result values are constructed only inside the
// leaf helpers _ok_*/_err_* (direct Ok/Err construction in struct-returning
// functions miscompiles; see the scheduler precedent); Str values read from
// Vec[Str] elements are compared with string.str_compare (BUG 17 lowers `==`
// on such elements to a pointer comparison); integer parsing rejects
// magnitudes above 2^63 - 1 so a numeric comparison never wraps silently; a
// reference-typed local passed on to another &-parameter is re-referenced
// with an explicit `&` (query_matches(&q, ...) below) because a bare
// reference argument miscompiles.

module xiom.query

use xiom.string;

const _Q_SPACE: UInt8 = 32u8;
const _Q_TAB: UInt8 = 9u8;
const _Q_LF: UInt8 = 10u8;
const _Q_CR: UInt8 = 13u8;
const _Q_DQUOTE: UInt8 = 34u8;
const _Q_SQUOTE: UInt8 = 39u8;
const _Q_MINUS: UInt8 = 45u8;
const _Q_PLUS: UInt8 = 43u8;
const _Q_ZERO: UInt8 = 48u8;
const _Q_NINE: UInt8 = 57u8;
const _Q_INT_MAX_DIV10: Int = 922337203685477580;
const _Q_INT_MAX_LAST_DIGIT: Int = 7;

/// Parsed filter expression. fields, ops and values hold one entry per term;
/// joins[i] is the connector ("and" or "or") evaluated before term i and is
/// "" when i == 0. All four vectors have the same length and are kept
/// parallel by query_parse.
pub type Query = {
  fields: Vec[Str];
  ops: Vec[Str];
  values: Vec[Str];
  joins: Vec[Str];
}

// ---------------------------------------------------------------------------
// Small helpers
// ---------------------------------------------------------------------------

fn _streq(a: Str, b: Str) -> Bool {
  return string.str_compare(a, b) == 0;
}

fn _is_ws(b: UInt8) -> Bool {
  return b == _Q_SPACE || b == _Q_TAB || b == _Q_LF || b == _Q_CR;
}

fn _is_quote(b: UInt8) -> Bool {
  return b == _Q_DQUOTE || b == _Q_SQUOTE;
}

// ASCII-lowercase byte; non-letters pass through.
fn _lower(b: UInt8) -> UInt8 {
  if b >= 65u8 && b <= 90u8 {
    return ((b as Int) + 32) as UInt8;
  }
  return b;
}

// Case-insensitive equality of an ASCII token against a lowercase literal.
fn _lower_eq(s: Str, lit: Str) -> Bool {
  let n = s.len();
  if n != lit.len() {
    return false;
  }
  var i = 0;
  while i < n {
    let a = _lower(string.byte_at(s, i));
    let b = string.byte_at(lit, i);
    if a != b {
      return false;
    }
    i = i + 1;
  }
  return true;
}

fn _is_and(tok: Str) -> Bool {
  return _lower_eq(tok, "and");
}

fn _is_or(tok: Str) -> Bool {
  return _lower_eq(tok, "or");
}

fn _is_connector(tok: Str) -> Bool {
  return _is_and(tok) || _is_or(tok);
}

fn _is_operator(op: Str) -> Bool {
  if _streq(op, "=") {
    return true;
  }
  if _streq(op, "!=") {
    return true;
  }
  if _streq(op, "<") {
    return true;
  }
  if _streq(op, "<=") {
    return true;
  }
  if _streq(op, ">") {
    return true;
  }
  if _streq(op, ">=") {
    return true;
  }
  if _streq(op, "contains") {
    return true;
  }
  if _streq(op, "startswith") {
    return true;
  }
  if _streq(op, "endswith") {
    return true;
  }
  return false;
}

// ---------------------------------------------------------------------------
// Result and struct constructors (compiler workaround; see the header)
// ---------------------------------------------------------------------------

fn _ok_query(q: Query) -> Result[Query, Str] {
  return Ok(q);
}

fn _err_query(m: Str) -> Result[Query, Str] {
  return Err(m);
}

fn _ok_tokens(v: Vec[Str]) -> Result[Vec[Str], Str] {
  return Ok(v);
}

fn _err_tokens(m: Str) -> Result[Vec[Str], Str] {
  return Err(m);
}

fn _make_query(fields: Vec[Str], ops: Vec[Str], values: Vec[Str], joins: Vec[Str]) -> Query {
  return Query{
    fields: fields;
    ops: ops;
    values: values;
    joins: joins;
  };
}

// ---------------------------------------------------------------------------
// Tokenizer
// ---------------------------------------------------------------------------

// Split into whitespace-separated tokens. A token that starts with a quote
// byte is quoted: it runs to the matching quote and may contain whitespace
// (no escape sequences). A token that does not start with a quote byte is
// bare: it runs to the next whitespace byte and may contain quote bytes.
// Err("query: unterminated quote") when a quoted token has no closing quote.
fn _tokenize(expr: Str) -> Result[Vec[Str], Str] {
  var out = Vec[Str].new();
  let n = expr.len();
  var i = 0;
  while i < n {
    let b = string.byte_at(expr, i);
    if _is_ws(b) {
      i = i + 1;
    } elif _is_quote(b) {
      let quote = b;
      var j = i + 1;
      while j < n && string.byte_at(expr, j) != quote {
        j = j + 1;
      }
      if j >= n {
        return _err_tokens("query: unterminated quote");
      }
      out.push(string.str_slice(expr, i + 1, j));
      i = j + 1;
    } else {
      var j = i;
      while j < n && !_is_ws(string.byte_at(expr, j)) {
        j = j + 1;
      }
      out.push(string.str_slice(expr, i, j));
      i = j;
    }
  }
  return _ok_tokens(out);
}

// ---------------------------------------------------------------------------
// Parsing
// ---------------------------------------------------------------------------

/// Parse a filter expression into a Query.
/// Params: expr - whitespace-separated tokens forming
/// `term (connector term)*`, where a term is `field op value`, a connector is
/// AND/OR (case-insensitive), a field is a token, ops are `=`, `!=`, `<`,
/// `<=`, `>`, `>=`, `contains`, `startswith` and `endswith` (case-sensitive),
/// and a value is a token. A token is either quoted with `"` or `'` -- it may
/// then contain whitespace -- or bare (runs to the next whitespace byte).
/// There are no parentheses; a leading connector is rejected.
/// Returns: Ok(Query) with parallel fields/ops/values/joins vectors.
/// Error case: Err("query: ...") -- empty expression, expression starting
/// with a connector, incomplete term, empty field name, unknown operator,
/// missing connector, connector without a following term, or an unterminated
/// quote.
/// Complexity: O(len(expr)).
pub fn query_parse(expr: Str) -> Result[Query, Str] {
  let tokenized = _tokenize(expr);
  var toks = Vec[Str].new();
  match tokenized {
    Ok(v) => { toks = v; },
    Err(e) => { return _err_query(e); },
  }
  let n = toks.len();
  if n == 0 {
    return _err_query("query: empty expression");
  }
  let head: Str = toks[0];
  if _is_connector(head) {
    return _err_query("query: expression must start with a term");
  }
  var fields = Vec[Str].new();
  var ops = Vec[Str].new();
  var values = Vec[Str].new();
  var joins = Vec[Str].new();
  var i = 0;
  var first = true;
  loop {
    if i >= n {
      break;
    }
    if i + 3 > n {
      return _err_query("query: incomplete term");
    }
    let field: Str = toks[i];
    let op: Str = toks[i + 1];
    let value: Str = toks[i + 2];
    if field.len() == 0 {
      return _err_query("query: empty field name");
    }
    if !_is_operator(op) {
      return _err_query("query: unknown operator: " + op);
    }
    fields.push(field);
    ops.push(op);
    values.push(value);
    if first {
      joins.push("");
      first = false;
    }
    i = i + 3;
    if i >= n {
      break;
    }
    let connector: Str = toks[i];
    if _is_and(connector) {
      joins.push("and");
    } elif _is_or(connector) {
      joins.push("or");
    } else {
      return _err_query("query: expected connector, got: " + connector);
    }
    i = i + 1;
    if i >= n {
      return _err_query("query: expected term after connector");
    }
  }
  return _ok_query(_make_query(fields, ops, values, joins));
}

/// Number of terms in a parsed query.
/// Params: q - the query.
/// Returns: q.fields.len(); 0 for a hand-built query with no terms.
/// Complexity: O(1).
pub fn query_term_count(q: &Query) -> Int {
  return q.fields.len();
}

// ---------------------------------------------------------------------------
// Canonical text
// ---------------------------------------------------------------------------

fn _join_text(j: Str) -> Str {
  if _streq(j, "and") {
    return "AND";
  }
  if _streq(j, "or") {
    return "OR";
  }
  return j;
}

// Quoting style for a canonical value: 0 = bare, 1 = double quotes,
// 2 = single quotes. A value is quoted when it is empty, contains a
// whitespace byte, or starts with a quote byte (quotes are special at token
// start). A value that contains a double quote but no single quote is
// wrapped in single quotes; a value containing both quote bytes is wrapped
// in double quotes and may not re-parse (documented limitation).
fn _value_style(v: Str) -> Int {
  if v.len() == 0 {
    return 1;
  }
  let first = string.byte_at(v, 0);
  var need = false;
  if first == _Q_DQUOTE || first == _Q_SQUOTE {
    need = true;
  }
  var has_double = false;
  var has_single = false;
  var i = 0;
  while i < v.len() {
    let b = string.byte_at(v, i);
    if _is_ws(b) {
      need = true;
    }
    if b == _Q_DQUOTE {
      has_double = true;
    }
    if b == _Q_SQUOTE {
      has_single = true;
    }
    i = i + 1;
  }
  if !need {
    return 0;
  }
  if has_double && !has_single {
    return 2;
  }
  return 1;
}

fn _value_text(v: Str) -> Str {
  let style = _value_style(v);
  if style == 0 {
    return v;
  }
  if style == 2 {
    return "'" + v + "'";
  }
  return "\"" + v + "\"";
}

/// Canonical text form of a parsed query: `field op value`, terms joined by
/// " AND " / " OR " (uppercase). Fields and operators are emitted verbatim;
/// values are quoted only when needed (see _value_style).
/// Params: q - the query.
/// Returns: the canonical expression; empty for a query with no terms.
/// Complexity: O(total text length).
pub fn query_to_string(q: &Query) -> Str {
  var out = "";
  var i = 0;
  while i < q.fields.len() {
    if i > 0 {
      let join: Str = q.joins[i];
      out = out + " " + _join_text(join) + " ";
    }
    let field: Str = q.fields[i];
    let op: Str = q.ops[i];
    let value: Str = q.values[i];
    out = out + field + " " + op + " " + _value_text(value);
    i = i + 1;
  }
  return out;
}

// ---------------------------------------------------------------------------
// Numeric values
// ---------------------------------------------------------------------------

// Decimal integer with an optional leading '+' or '-', at least one digit,
// leading zeros allowed. Some(value) only when the magnitude fits the signed
// 64-bit range (so "-9223372036854775808" is not numeric); None otherwise.
fn _parse_int(s: Str) -> Option[Int] {
  let n = s.len();
  if n == 0 {
    return None;
  }
  var i = 0;
  var neg = false;
  let first = string.byte_at(s, 0);
  if first == _Q_MINUS {
    neg = true;
    i = 1;
  } elif first == _Q_PLUS {
    i = 1;
  }
  if i >= n {
    return None;
  }
  var mag: Int = 0;
  while i < n {
    let b = string.byte_at(s, i);
    if b < _Q_ZERO || b > _Q_NINE {
      return None;
    }
    let d = (b as Int) - 48;
    if mag > _Q_INT_MAX_DIV10 {
      return None;
    }
    if mag == _Q_INT_MAX_DIV10 && d > _Q_INT_MAX_LAST_DIGIT {
      return None;
    }
    mag = mag * 10 + d;
    i = i + 1;
  }
  if neg {
    if mag == 0 {
      return Some(0);
    }
    return Some(0 - mag);
  }
  return Some(mag);
}

// Some((left, right)) only when both sides parse as integers.
fn _both_ints(a: Str, b: Str) -> Option[(Int, Int)] {
  let ma = _parse_int(a);
  let mb = _parse_int(b);
  match ma {
    Some(x) => {
      match mb {
        Some(y) => { return Some((x, y)); },
        None => {},
      }
    },
    None => {},
  }
  return None;
}

// ---------------------------------------------------------------------------
// Matching
// ---------------------------------------------------------------------------

/// Evaluate one term: `left op right`.
/// Params: op - an operator from the query_parse set; left - the record cell;
/// right - the term value.
/// Returns: for `=`, `!=`, `<`, `<=`, `>` and `>=` the comparison is numeric
/// when BOTH sides parse as integers (optional sign, leading zeros allowed,
/// magnitude <= 2^63 - 1) and byte-wise via string.str_compare otherwise;
/// `contains`, `startswith` and `endswith` are byte-wise substring tests
/// (an empty needle is found in every string). An unknown operator returns
/// false.
/// Complexity: O(len(left) + len(right)).
pub fn query_match_one(op: Str, left: Str, right: Str) -> Bool {
  if _streq(op, "=") {
    let pair = _both_ints(left, right);
    match pair {
      Some((x, y)) => { return x == y; },
      None => {},
    }
    return _streq(left, right);
  }
  if _streq(op, "!=") {
    let pair = _both_ints(left, right);
    match pair {
      Some((x, y)) => { return x != y; },
      None => {},
    }
    return !_streq(left, right);
  }
  if _streq(op, "<") {
    let pair = _both_ints(left, right);
    match pair {
      Some((x, y)) => { return x < y; },
      None => {},
    }
    return string.str_compare(left, right) < 0;
  }
  if _streq(op, "<=") {
    let pair = _both_ints(left, right);
    match pair {
      Some((x, y)) => { return x <= y; },
      None => {},
    }
    return string.str_compare(left, right) <= 0;
  }
  if _streq(op, ">") {
    let pair = _both_ints(left, right);
    match pair {
      Some((x, y)) => { return x > y; },
      None => {},
    }
    return string.str_compare(left, right) > 0;
  }
  if _streq(op, ">=") {
    let pair = _both_ints(left, right);
    match pair {
      Some((x, y)) => { return x >= y; },
      None => {},
    }
    return string.str_compare(left, right) >= 0;
  }
  if _streq(op, "contains") {
    if right.len() == 0 {
      return true;
    }
    return string.str_contains(left, right);
  }
  if _streq(op, "startswith") {
    return string.str_starts_with(left, right);
  }
  if _streq(op, "endswith") {
    return string.str_ends_with(left, right);
  }
  return false;
}

/// Evaluate a whole query against one flat record.
/// Params: q - the query; keys - the record's field names; values - the
/// record's cell values, parallel to keys (keys[i] names values[i]).
/// Returns: the terms folded strictly left to right: the running result
/// starts as term 0 and each following term is ANDed or ORed with it using
/// joins[i] (no precedence -- see SPEC.md section 3). A term whose field is
/// not present among keys is false, except for `!=`, which is true; a key
/// without a parallel value counts as missing. The first key equal to the
/// term's field wins. A query with no terms matches everything.
/// Complexity: O(terms * keys * cell length).
pub fn query_matches(q: &Query, keys: &Vec[Str], values: &Vec[Str]) -> Bool {
  let count = q.fields.len();
  if count == 0 {
    return true;
  }
  var result = false;
  var i = 0;
  while i < count {
    let op: Str = q.ops[i];
    let want: Str = q.fields[i];
    let rhs: Str = q.values[i];
    var term = false;
    var found = false;
    var j = 0;
    while j < keys.len() {
      let key: Str = keys[j];
      if _streq(key, want) {
        if j < values.len() {
          let cell: Str = values[j];
          term = query_match_one(op, cell, rhs);
          found = true;
        }
        break;
      }
      j = j + 1;
    }
    if !found {
      term = _streq(op, "!=");
    }
    if i == 0 {
      result = term;
    } elif _streq(q.joins[i], "or") {
      result = result || term;
    } else {
      result = result && term;
    }
    i = i + 1;
  }
  return result;
}

/// Filter rows by a query over their cells.
/// Params: headers - the column names; rows - the records; q - the query.
/// Each row is interpreted as the record keys = headers[0..min(width, row
/// width)], values = the row's cells; cells beyond the header width are not
/// matched but are preserved. A ragged row simply lacks its trailing fields
/// (missing-field semantics). Rows keep their original cell order and values.
/// Returns: the matching rows in their original order (empty when nothing
/// matches, including when rows is empty).
/// Complexity: O(rows * terms * columns * cell length).
pub fn query_select(headers: &Vec[Str], rows: &Vec[Vec[Str]], q: &Query) -> Vec[Vec[Str]] {
  var out = Vec[Vec[Str]].new();
  var r = 0;
  while r < rows.len() {
    let width = rows[r].len();
    var keys = Vec[Str].new();
    var vals = Vec[Str].new();
    var copy = Vec[Str].new();
    var c = 0;
    while c < width {
      let cell: Str = rows[r][c];
      copy.push(cell);
      if c < headers.len() {
        let header: Str = headers[c];
        keys.push(header);
        vals.push(cell);
      }
      c = c + 1;
    }
    if query_matches(&q, &keys, &vals) {
      out.push(copy);
    }
    r = r + 1;
  }
  return out;
}
