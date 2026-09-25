// XIOM -- xiom.cron: classic 5-field cron parser, validator and canonical emitter
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Model: a cron expression is five whitespace-separated fields -- minute,
// hour, day-of-month, month and day-of-week -- plus the documented @-macros.
// Parsing is set-based and syntax-lossy by design: every field reduces to its
// sorted, duplicate-free set of values, so "*/15" and "0,15,30,45" parse to
// the same expression. Accessors read the flat per-field vectors
// (cron_field_count / cron_field_at plus the five named count/at pairs),
// cron_emit renders the canonical five-field text, and cron_describe renders
// a labelled human-readable summary.
//
// Documented rules (see SPEC.md for the grammar, macro table and catalog):
//   * fields are separated by ASCII space, tab, CR or LF; leading and
//     trailing whitespace is ignored;
//   * a field is a comma-separated list of items; every item is "*", "a",
//     "a-b", "*/n" or "a-b/n" (a step requires "*" or a range, so "a/n" is
//     rejected, and an item holds at most one "/");
//   * values are decimal digit runs with leading zeros allowed ("07" = 7);
//   * month names JAN..DEC and day-of-week names SUN..SAT are accepted
//     case-insensitively and only as exact three-letter abbreviations;
//   * day-of-week accepts 0..7 and both 0 and 7 mean Sunday; the stored set
//     is normalized to 0..6;
//   * a range with start > end is a documented error (no reversal);
//   * a step must be a positive decimal integer; a step larger than the
//     field span simply yields the start value;
//   * "@" is special only as the first byte of the expression: the whole
//     input must then be exactly one documented macro name.
//
// Language notes (XIOM v0.61.3): free functions only; every Vec element read
// goes through a typed local (`let x: Int = v[i];`); Ok/Err values are built
// only in the leaf helpers below; no Vec[StructType] is used -- CronExpr
// holds five flat Vec[Int] fields instead.

module xiom.cron

use xiom.string;
use xiom.string.compare;
use xiom.convert;

// --------------------------------------------------
//  Field identifiers
// --------------------------------------------------

// Field indices for the generic accessors: minutes 0, hours 1, days 2,
// months 3, days-of-week 4.
pub const CRON_FIELD_MINUTE: Int = 0;
pub const CRON_FIELD_HOUR: Int = 1;
pub const CRON_FIELD_DAY: Int = 2;
pub const CRON_FIELD_MONTH: Int = 3;
pub const CRON_FIELD_DOW: Int = 4;

// --------------------------------------------------
//  Data model
// --------------------------------------------------

// Parsed cron expression: five flat, sorted, duplicate-free value vectors.
// Accessors return Int values and never expose the vectors, which is why the
// representation is parallel Vec[Int] fields rather than Vec[StructType]
// (unsupported in XIOM v0.61.3). Invariant, guaranteed by cron_parse: each
// vector is sorted ascending, free of duplicates and inside the field range
// (dows normalized to 0..6).
pub type CronExpr = {
  minutes: Vec[Int];
  hours: Vec[Int];
  days: Vec[Int];
  months: Vec[Int];
  dows: Vec[Int];
}

// --------------------------------------------------
//  Internal constants
// --------------------------------------------------

const _CRON_SEEN_MAX: Int = 60;      // minute values are 0..59
const _CRON_MAX_ACC: Int = 100000;   // accumulation cap before the bounds check
const _CRON_AT: Int = 64;            // '@'
const _CRON_STAR: Int = 42;          // '*'
const _CRON_COMMA: Int = 44;         // ','
const _CRON_HYPHEN: Int = 45;        // '-'
const _CRON_SLASH: Int = 47;         // '/'
const _CRON_ZERO: Int = 48;          // '0'
const _CRON_NINE: Int = 57;          // '9'
const _CRON_SPACE: Int = 32;         // ' '
const _CRON_TAB: Int = 9;            // '\t'
const _CRON_LF: Int = 10;            // '\n'
const _CRON_CR: Int = 13;            // '\r'

// --------------------------------------------------
//  Result leaf helpers
// --------------------------------------------------

// Constructing Ok/Err inline in larger functions miscompiles on XIOM
// v0.61.3, so every Result value in this module is built by a leaf helper.

fn _cron_expr_ok(v: CronExpr) -> Result[CronExpr, Str] {
  return Ok(v);
}

fn _cron_expr_err(m: Str) -> Result[CronExpr, Str] {
  return Err(m);
}

fn _cron_str_ok(v: Str) -> Result[Str, Str] {
  return Ok(v);
}

fn _cron_str_err(m: Str) -> Result[Str, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Byte and field helpers
// --------------------------------------------------

// Read byte i of s widened to Int space (0..255), so byte comparisons never
// touch a raw UInt8 value.
fn _cron_byte(s: Str, i: Int) -> Int {
  return (string.byte_at(s, i) as Int) & 0xFF;
}

// ASCII whitespace byte: space, tab, CR or LF.
fn _cron_is_space(c: Int) -> Bool {
  return c == _CRON_SPACE || c == _CRON_TAB || c == _CRON_LF || c == _CRON_CR;
}

// Index of the first byte equal to `ch` in s[start..stop), or -1.
fn _cron_index_of_range(s: Str, start: Int, stop: Int, ch: Int) -> Int {
  var i = start;
  while i < stop {
    if _cron_byte(s, i) == ch {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// Lowest accepted value of `field` (accepted for the raw day-of-week 0..7
// domain; the stored day-of-week values are normalized to 0..6).
fn _cron_field_lo(field: Int) -> Int {
  if field == CRON_FIELD_MINUTE { return 0; }
  if field == CRON_FIELD_HOUR { return 0; }
  if field == CRON_FIELD_DAY { return 1; }
  if field == CRON_FIELD_MONTH { return 1; }
  if field == CRON_FIELD_DOW { return 0; }
  return 0;
}

// Highest accepted value of `field` (raw: day-of-week accepts 7 = Sunday).
fn _cron_field_hi(field: Int) -> Int {
  if field == CRON_FIELD_MINUTE { return 59; }
  if field == CRON_FIELD_HOUR { return 23; }
  if field == CRON_FIELD_DAY { return 31; }
  if field == CRON_FIELD_MONTH { return 12; }
  if field == CRON_FIELD_DOW { return 7; }
  return 0;
}

/// Canonical name of a field index, as used in error messages.
/// Params: field - CRON_FIELD_MINUTE..CRON_FIELD_DOW.
/// Returns: "minute", "hour", "day-of-month", "month" or "day-of-week";
/// "" for any other index.
/// Error case: none.
/// Complexity: O(1).
pub fn cron_field_name(field: Int) -> Str {
  if field == CRON_FIELD_MINUTE { return "minute"; }
  if field == CRON_FIELD_HOUR { return "hour"; }
  if field == CRON_FIELD_DAY { return "day-of-month"; }
  if field == CRON_FIELD_MONTH { return "month"; }
  if field == CRON_FIELD_DOW { return "day-of-week"; }
  return "";
}

// --------------------------------------------------
//  Value and name parsing
// --------------------------------------------------

// Uppercase an ASCII byte; non-letters are returned unchanged.
fn _cron_upper(c: Int) -> Int {
  if c >= 97 && c <= 122 { return c - 32; }
  return c;
}

// Map the exact three-letter name s[start..stop) to its value for `field`
// (JAN..DEC for months, SUN..SAT for days-of-week, case-insensitive).
// Returns: the value 1..12 or 0..6; -1 when the token is not exactly one of
// the accepted three-letter names of that field.
fn _cron_name_value(s: Str, start: Int, stop: Int, field: Int) -> Int {
  if stop - start != 3 { return -1; }
  let b0 = _cron_upper(_cron_byte(s, start));
  let b1 = _cron_upper(_cron_byte(s, start + 1));
  let b2 = _cron_upper(_cron_byte(s, start + 2));
  let code = b0 * 65536 + b1 * 256 + b2;
  if field == CRON_FIELD_MONTH {
    if code == 0x4A414E { return 1; }   // JAN
    if code == 0x464542 { return 2; }   // FEB
    if code == 0x4D4152 { return 3; }   // MAR
    if code == 0x415052 { return 4; }   // APR
    if code == 0x4D4159 { return 5; }   // MAY
    if code == 0x4A554E { return 6; }   // JUN
    if code == 0x4A554C { return 7; }   // JUL
    if code == 0x415547 { return 8; }   // AUG
    if code == 0x534550 { return 9; }   // SEP
    if code == 0x4F4354 { return 10; }  // OCT
    if code == 0x4E4F56 { return 11; }  // NOV
    if code == 0x444543 { return 12; }  // DEC
    return -1;
  }
  if field == CRON_FIELD_DOW {
    if code == 0x53554E { return 0; }   // SUN
    if code == 0x4D4F4E { return 1; }   // MON
    if code == 0x545545 { return 2; }   // TUE
    if code == 0x574544 { return 3; }   // WED
    if code == 0x544855 { return 4; }   // THU
    if code == 0x465249 { return 5; }   // FRI
    if code == 0x534154 { return 6; }   // SAT
    return -1;
  }
  return -1;
}

// Parse one value token s[start..stop): all-digit values are bounds-checked
// against `field`, names are looked up for months and days-of-week. Raw
// day-of-week 7 is returned as 7; normalization to 0 happens at mark time.
// Returns: the value, -1 for an unknown token, -2 for a numeric value
// outside the field range.
fn _cron_value(s: Str, start: Int, stop: Int, field: Int) -> Int {
  if start >= stop { return -1; }
  var all_digits = true;
  var i = start;
  while i < stop {
    let c = _cron_byte(s, i);
    if c < _CRON_ZERO || c > _CRON_NINE {
      all_digits = false;
      break;
    }
    i = i + 1;
  }
  if all_digits {
    var v = 0;
    i = start;
    while i < stop {
      let c = _cron_byte(s, i);
      // Once past the cap the value can no longer be in range, so the
      // remaining digits are consumed without accumulating.
      if v <= _CRON_MAX_ACC { v = v * 10 + (c - _CRON_ZERO); }
      i = i + 1;
    }
    if v < _cron_field_lo(field) || v > _cron_field_hi(field) { return -2; }
    return v;
  }
  return _cron_name_value(s, start, stop, field);
}

// Mark one produced value in the presence vector; raw day-of-week 7 is
// normalized to Sunday 0 before marking.
fn _cron_mark(seen: &mut Vec[Int], field: Int, v: Int) {
  if field == CRON_FIELD_DOW && v == 7 {
    seen.set(0, 1);
  } else {
    seen.set(v, 1);
  }
}

// --------------------------------------------------
//  Field and segment parsing
// --------------------------------------------------

// Parse one comma-separated item s[start..stop) of `field`, marking every
// produced value in `seen`. Returns "" on success or a "cron: ..." message.
// Grammar: "*", "a", "a-b", "*/n" or "a-b/n".
fn _cron_segment_parse(s: Str, start: Int, stop: Int, field: Int, seen: &mut Vec[Int]) -> Str {
  let name = cron_field_name(field);
  let slash = _cron_index_of_range(s, start, stop, _CRON_SLASH);
  var base_stop = stop;
  var step = 1;
  var has_step = false;
  if slash >= 0 {
    has_step = true;
    if _cron_index_of_range(s, slash + 1, stop, _CRON_SLASH) >= 0 {
      return "cron: bad token: " + string.str_slice(s, start, stop) + " in " + name;
    }
    if slash + 1 >= stop {
      return "cron: bad step in " + name;
    }
    var step_ok = true;
    var step_value = 0;
    var k = slash + 1;
    while k < stop {
      let c = _cron_byte(s, k);
      if c < _CRON_ZERO || c > _CRON_NINE {
        step_ok = false;
        break;
      }
      if step_value <= _CRON_MAX_ACC { step_value = step_value * 10 + (c - _CRON_ZERO); }
      k = k + 1;
    }
    if !step_ok {
      return "cron: bad step: " + string.str_slice(s, slash + 1, stop) + " in " + name;
    }
    if step_value == 0 {
      return "cron: step must be > 0 in " + name;
    }
    step = step_value;
    base_stop = slash;
  }
  if base_stop <= start {
    return "cron: bad token: " + string.str_slice(s, start, stop) + " in " + name;
  }
  if base_stop - start == 1 && _cron_byte(s, start) == _CRON_STAR {
    let hi = _cron_field_hi(field);
    var x = _cron_field_lo(field);
    while x <= hi {
      _cron_mark(seen, field, x);
      x = x + step;
    }
    return "";
  }
  let hy = _cron_index_of_range(s, start, base_stop, _CRON_HYPHEN);
  if hy < 0 {
    if has_step {
      return "cron: bad token: " + string.str_slice(s, start, stop) + " in " + name;
    }
    let v = _cron_value(s, start, base_stop, field);
    if v == -1 {
      return "cron: unknown value: " + string.str_slice(s, start, base_stop) + " in " + name;
    }
    if v == -2 {
      return "cron: value out of range: " + string.str_slice(s, start, base_stop) + " in " + name;
    }
    _cron_mark(seen, field, v);
    return "";
  }
  if _cron_index_of_range(s, hy + 1, base_stop, _CRON_HYPHEN) >= 0 {
    return "cron: bad token: " + string.str_slice(s, start, stop) + " in " + name;
  }
  if hy == start || hy + 1 >= base_stop {
    return "cron: bad token: " + string.str_slice(s, start, stop) + " in " + name;
  }
  let a = _cron_value(s, start, hy, field);
  if a == -1 {
    return "cron: unknown value: " + string.str_slice(s, start, hy) + " in " + name;
  }
  if a == -2 {
    return "cron: value out of range: " + string.str_slice(s, start, hy) + " in " + name;
  }
  let b = _cron_value(s, hy + 1, base_stop, field);
  if b == -1 {
    return "cron: unknown value: " + string.str_slice(s, hy + 1, base_stop) + " in " + name;
  }
  if b == -2 {
    return "cron: value out of range: " + string.str_slice(s, hy + 1, base_stop) + " in " + name;
  }
  if a > b {
    return "cron: range start > end: " + string.str_slice(s, start, base_stop) + " in " + name;
  }
  var x = a;
  while x <= b {
    _cron_mark(seen, field, x);
    x = x + step;
  }
  return "";
}

// Parse a whole field s[start..stop) -- a comma-separated list of items --
// and append its sorted, duplicate-free values to `out` (which the caller
// passes empty). A presence vector distinguishes produced values from
// absent ones, so no in-place sort or dedupe pass is needed.
// Returns: "" on success, or a "cron: ..." message.
fn _cron_field_parse(s: Str, start: Int, stop: Int, field: Int, out: &mut Vec[Int]) -> Str {
  if start >= stop {
    return "cron: empty list item in " + cron_field_name(field);
  }
  var seen = Vec[Int].new();
  var z = 0;
  while z < _CRON_SEEN_MAX {
    seen.push(0);
    z = z + 1;
  }
  var seg_start = start;
  var i = start;
  while i <= stop {
    if i == stop || _cron_byte(s, i) == _CRON_COMMA {
      if i == seg_start {
        return "cron: empty list item in " + cron_field_name(field);
      }
      let e = _cron_segment_parse(s, seg_start, i, field, &mut seen);
      if e.len() > 0 {
        return e;
      }
      seg_start = i + 1;
    }
    i = i + 1;
  }
  var v = 0;
  while v < _CRON_SEEN_MAX {
    let flag: Int = seen[v];
    if flag == 1 {
      out.push(v);
    }
    v = v + 1;
  }
  return "";
}

// --------------------------------------------------
//  Macros
// --------------------------------------------------

// Append lo..hi inclusive to v.
fn _cron_fill(v: &mut Vec[Int], lo: Int, hi: Int) {
  var x = lo;
  while x <= hi {
    v.push(x);
    x = x + 1;
  }
}

// Resolve one documented macro name to its expression. Returns Ok(CronExpr)
// or Err("cron: bad macro: <name>").
fn _cron_from_macro(name: Str) -> Result[CronExpr, Str] {
  var minutes = Vec[Int].new();
  var hours = Vec[Int].new();
  var days = Vec[Int].new();
  var months = Vec[Int].new();
  var dows = Vec[Int].new();
  if compare.str_compare(name, "@hourly") == 0 {
    _cron_fill(&mut minutes, 0, 0);
    _cron_fill(&mut hours, 0, 23);
    _cron_fill(&mut days, 1, 31);
    _cron_fill(&mut months, 1, 12);
    _cron_fill(&mut dows, 0, 6);
  } elif compare.str_compare(name, "@daily") == 0 {
    _cron_fill(&mut minutes, 0, 0);
    _cron_fill(&mut hours, 0, 0);
    _cron_fill(&mut days, 1, 31);
    _cron_fill(&mut months, 1, 12);
    _cron_fill(&mut dows, 0, 6);
  } elif compare.str_compare(name, "@midnight") == 0 {
    _cron_fill(&mut minutes, 0, 0);
    _cron_fill(&mut hours, 0, 0);
    _cron_fill(&mut days, 1, 31);
    _cron_fill(&mut months, 1, 12);
    _cron_fill(&mut dows, 0, 6);
  } elif compare.str_compare(name, "@weekly") == 0 {
    _cron_fill(&mut minutes, 0, 0);
    _cron_fill(&mut hours, 0, 0);
    _cron_fill(&mut days, 1, 31);
    _cron_fill(&mut months, 1, 12);
    _cron_fill(&mut dows, 0, 0);
  } elif compare.str_compare(name, "@monthly") == 0 {
    _cron_fill(&mut minutes, 0, 0);
    _cron_fill(&mut hours, 0, 0);
    _cron_fill(&mut days, 1, 1);
    _cron_fill(&mut months, 1, 12);
    _cron_fill(&mut dows, 0, 6);
  } elif compare.str_compare(name, "@yearly") == 0 {
    _cron_fill(&mut minutes, 0, 0);
    _cron_fill(&mut hours, 0, 0);
    _cron_fill(&mut days, 1, 1);
    _cron_fill(&mut months, 1, 1);
    _cron_fill(&mut dows, 0, 6);
  } elif compare.str_compare(name, "@annually") == 0 {
    _cron_fill(&mut minutes, 0, 0);
    _cron_fill(&mut hours, 0, 0);
    _cron_fill(&mut days, 1, 1);
    _cron_fill(&mut months, 1, 1);
    _cron_fill(&mut dows, 0, 6);
  } else {
    return _cron_expr_err("cron: bad macro: " + name);
  }
  return _cron_expr_ok(CronExpr{
    minutes: minutes;
    hours: hours;
    days: days;
    months: months;
    dows: dows;
  });
}

// --------------------------------------------------
//  Parsing
// --------------------------------------------------

/// Parse a classic 5-field cron expression (or a documented @-macro).
/// Params: expr - "minute hour day-of-month month day-of-week" with fields
/// separated by one or more spaces, tabs, CRs or LFs; leading and trailing
/// whitespace is ignored. Every field is reduced to its sorted,
/// duplicate-free set of values.
/// Returns: Ok(CronExpr) on success. Day-of-week 0 and 7 both mean Sunday;
/// the stored set is normalized to 0..6.
/// Error case: Err("cron: empty expression") for "" or whitespace only;
/// Err("cron: bad macro: <text>") when the input starts with '@' but is not
/// exactly one documented macro name (trailing fields included);
/// Err("cron: expected 5 fields, got <n>") for any other field count;
/// field errors from the documented catalog, for example
/// Err("cron: value out of range: 60 in minute"),
/// Err("cron: range start > end: 5-1 in minute") or
/// Err("cron: step must be > 0 in minute").
/// Examples: "* * * * *" -> every field full; "@weekly" -> 0 0 * * 0;
/// "0,30 9-17 * * MON-FRI" -> minutes {0,30}, hours 9..17, dows 1..5.
/// Complexity: O(len(expr)) plus O(field span) per wildcard/step item.
pub fn cron_parse(expr: Str) -> Result[CronExpr, Str] {
  let n = expr.len();
  var starts = Vec[Int].new();
  var ends = Vec[Int].new();
  var i = 0;
  while i < n {
    while i < n && _cron_is_space(_cron_byte(expr, i)) {
      i = i + 1;
    }
    if i >= n {
      break;
    }
    let st = i;
    while i < n && !_cron_is_space(_cron_byte(expr, i)) {
      i = i + 1;
    }
    starts.push(st);
    ends.push(i);
  }
  let count = starts.len();
  if count == 0 {
    return _cron_expr_err("cron: empty expression");
  }
  let first: Int = starts[0];
  if _cron_byte(expr, first) == _CRON_AT {
    if count != 1 {
      let last: Int = ends[count - 1];
      return _cron_expr_err("cron: bad macro: " + string.str_slice(expr, first, last));
    }
    let last: Int = ends[0];
    return _cron_from_macro(string.str_slice(expr, first, last));
  }
  if count != 5 {
    return _cron_expr_err("cron: expected 5 fields, got " + convert.int_to_string(count));
  }
  let s0: Int = starts[0];
  let s1: Int = starts[1];
  let s2: Int = starts[2];
  let s3: Int = starts[3];
  let s4: Int = starts[4];
  let e0: Int = ends[0];
  let e1: Int = ends[1];
  let e2: Int = ends[2];
  let e3: Int = ends[3];
  let e4: Int = ends[4];
  var minutes = Vec[Int].new();
  var hours = Vec[Int].new();
  var days = Vec[Int].new();
  var months = Vec[Int].new();
  var dows = Vec[Int].new();
  let m0 = _cron_field_parse(expr, s0, e0, CRON_FIELD_MINUTE, &mut minutes);
  if m0.len() > 0 {
    return _cron_expr_err(m0);
  }
  let m1 = _cron_field_parse(expr, s1, e1, CRON_FIELD_HOUR, &mut hours);
  if m1.len() > 0 {
    return _cron_expr_err(m1);
  }
  let m2 = _cron_field_parse(expr, s2, e2, CRON_FIELD_DAY, &mut days);
  if m2.len() > 0 {
    return _cron_expr_err(m2);
  }
  let m3 = _cron_field_parse(expr, s3, e3, CRON_FIELD_MONTH, &mut months);
  if m3.len() > 0 {
    return _cron_expr_err(m3);
  }
  let m4 = _cron_field_parse(expr, s4, e4, CRON_FIELD_DOW, &mut dows);
  if m4.len() > 0 {
    return _cron_expr_err(m4);
  }
  return _cron_expr_ok(CronExpr{
    minutes: minutes;
    hours: hours;
    days: days;
    months: months;
    dows: dows;
  });
}

/// True when `expr` parses as a cron expression or documented macro.
/// Params: expr - candidate expression text.
/// Returns: true for any input cron_parse accepts, false otherwise.
/// Error case: none (the parse error is turned into false).
/// Complexity: same as cron_parse.
pub fn cron_valid(expr: Str) -> Bool {
  match cron_parse(expr) {
    Ok(c) => { return true; },
    Err(e) => { return false; },
  }
}

/// Canonical five-field text of a documented macro.
/// Params: macro_name - one of @hourly, @daily, @midnight, @weekly,
/// @monthly, @yearly, @annually (exact, lowercase).
/// Returns: Ok(<canonical expression>) -- for example "@weekly" ->
/// Ok("0 0 * * 0"), "@hourly" -> Ok("0 * * * *").
/// Error case: Err("cron: bad macro: <name>") for any other input,
/// including "" and a name without the leading '@'.
/// Complexity: O(field span).
pub fn cron_expand_macro(macro_name: Str) -> Result[Str, Str] {
  match _cron_from_macro(macro_name) {
    Ok(c) => {
      let ce = c;
      return _cron_str_ok(cron_emit(&ce));
    },
    Err(e) => { return _cron_str_err(e); },
  }
}

// --------------------------------------------------
//  Accessors
// --------------------------------------------------

/// Number of allowed values in a field.
/// Params: c - parsed expression; field - CRON_FIELD_MINUTE..CRON_FIELD_DOW.
/// Returns: the count (for example 60 for a full minute field, 7 for a full
/// day-of-week field); 0 for an unknown field index.
/// Error case: none.
/// Complexity: O(1).
pub fn cron_field_count(c: &CronExpr, field: Int) -> Int {
  if field == CRON_FIELD_MINUTE { return c.minutes.len(); }
  if field == CRON_FIELD_HOUR { return c.hours.len(); }
  if field == CRON_FIELD_DAY { return c.days.len(); }
  if field == CRON_FIELD_MONTH { return c.months.len(); }
  if field == CRON_FIELD_DOW { return c.dows.len(); }
  return 0;
}

/// Value of one entry of a field, in ascending order.
/// Params: c - parsed expression; field - CRON_FIELD_MINUTE..CRON_FIELD_DOW;
/// i - zero-based index into the field's sorted value set.
/// Returns: the value at `i` (for example cron_field_at(c, 0, 0) is the first
/// allowed minute); -1 when `field` is unknown or `i` is negative or at
/// least cron_field_count(c, field).
/// Error case: none.
/// Complexity: O(1).
pub fn cron_field_at(c: &CronExpr, field: Int, i: Int) -> Int {
  if i < 0 { return -1; }
  if field == CRON_FIELD_MINUTE {
    let v: Vec[Int] = c.minutes;
    if i >= v.len() { return -1; }
    let x: Int = v[i];
    return x;
  }
  if field == CRON_FIELD_HOUR {
    let v: Vec[Int] = c.hours;
    if i >= v.len() { return -1; }
    let x: Int = v[i];
    return x;
  }
  if field == CRON_FIELD_DAY {
    let v: Vec[Int] = c.days;
    if i >= v.len() { return -1; }
    let x: Int = v[i];
    return x;
  }
  if field == CRON_FIELD_MONTH {
    let v: Vec[Int] = c.months;
    if i >= v.len() { return -1; }
    let x: Int = v[i];
    return x;
  }
  if field == CRON_FIELD_DOW {
    let v: Vec[Int] = c.dows;
    if i >= v.len() { return -1; }
    let x: Int = v[i];
    return x;
  }
  return -1;
}

/// Number of allowed minutes (0..59).
/// Error case: none.
/// Complexity: O(1).
pub fn cron_minute_count(c: &CronExpr) -> Int {
  return cron_field_count(c, CRON_FIELD_MINUTE);
}

/// Allowed minute `i` in ascending order; -1 out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn cron_minute_at(c: &CronExpr, i: Int) -> Int {
  return cron_field_at(c, CRON_FIELD_MINUTE, i);
}

/// Number of allowed hours (0..23).
/// Error case: none.
/// Complexity: O(1).
pub fn cron_hour_count(c: &CronExpr) -> Int {
  return cron_field_count(c, CRON_FIELD_HOUR);
}

/// Allowed hour `i` in ascending order; -1 out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn cron_hour_at(c: &CronExpr, i: Int) -> Int {
  return cron_field_at(c, CRON_FIELD_HOUR, i);
}

/// Number of allowed days of the month (1..31).
/// Error case: none.
/// Complexity: O(1).
pub fn cron_day_count(c: &CronExpr) -> Int {
  return cron_field_count(c, CRON_FIELD_DAY);
}

/// Allowed day-of-month `i` in ascending order; -1 out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn cron_day_at(c: &CronExpr, i: Int) -> Int {
  return cron_field_at(c, CRON_FIELD_DAY, i);
}

/// Number of allowed months (1..12).
/// Error case: none.
/// Complexity: O(1).
pub fn cron_month_count(c: &CronExpr) -> Int {
  return cron_field_count(c, CRON_FIELD_MONTH);
}

/// Allowed month `i` in ascending order; -1 out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn cron_month_at(c: &CronExpr, i: Int) -> Int {
  return cron_field_at(c, CRON_FIELD_MONTH, i);
}

/// Number of allowed days of the week (0..6, Sunday = 0).
/// Error case: none.
/// Complexity: O(1).
pub fn cron_dow_count(c: &CronExpr) -> Int {
  return cron_field_count(c, CRON_FIELD_DOW);
}

/// Allowed day-of-week `i` in ascending order; -1 out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn cron_dow_at(c: &CronExpr, i: Int) -> Int {
  return cron_field_at(c, CRON_FIELD_DOW, i);
}

// --------------------------------------------------
//  Canonical rendering
// --------------------------------------------------

// True when v holds every value of lo..hi exactly once. The sorted,
// duplicate-free, in-range invariant makes the count plus the endpoints
// sufficient.
fn _cron_is_full(v: &Vec[Int], lo: Int, hi: Int) -> Bool {
  let n = v.len();
  if n == 0 { return false; }
  if n != hi - lo + 1 { return false; }
  let a: Int = v[0];
  let b: Int = v[n - 1];
  return a == lo && b == hi;
}

// Canonical numeric token of a field: "*" when the field is full, else
// comma-separated values with runs of two or more collapsed to "a-b".
fn _cron_token(v: &Vec[Int], lo: Int, hi: Int) -> Str {
  if _cron_is_full(v, lo, hi) { return "*"; }
  var out = "";
  let n = v.len();
  var i = 0;
  while i < n {
    let a: Int = v[i];
    var j = i;
    while j + 1 < n {
      let x: Int = v[j + 1];
      let y: Int = v[j];
      if x != y + 1 { break; }
      j = j + 1;
    }
    let b: Int = v[j];
    if i > 0 { out = out + ","; }
    if j > i {
      out = out + convert.int_to_string(a) + "-" + convert.int_to_string(b);
    } else {
      out = out + convert.int_to_string(a);
    }
    i = j + 1;
  }
  return out;
}

// Name of one value for cron_describe: month and day-of-week values use the
// canonical three-letter uppercase names, every other value is decimal.
fn _cron_value_name(field: Int, v: Int) -> Str {
  if field == CRON_FIELD_MONTH {
    if v == 1 { return "JAN"; }
    if v == 2 { return "FEB"; }
    if v == 3 { return "MAR"; }
    if v == 4 { return "APR"; }
    if v == 5 { return "MAY"; }
    if v == 6 { return "JUN"; }
    if v == 7 { return "JUL"; }
    if v == 8 { return "AUG"; }
    if v == 9 { return "SEP"; }
    if v == 10 { return "OCT"; }
    if v == 11 { return "NOV"; }
    if v == 12 { return "DEC"; }
  }
  if field == CRON_FIELD_DOW {
    if v == 0 { return "SUN"; }
    if v == 1 { return "MON"; }
    if v == 2 { return "TUE"; }
    if v == 3 { return "WED"; }
    if v == 4 { return "THU"; }
    if v == 5 { return "FRI"; }
    if v == 6 { return "SAT"; }
  }
  return convert.int_to_string(v);
}

// Named canonical token of a field for cron_describe: "*" when full, else
// comma-separated value names with runs collapsed to "A-B".
fn _cron_name_token(v: &Vec[Int], lo: Int, hi: Int, field: Int) -> Str {
  if _cron_is_full(v, lo, hi) { return "*"; }
  var out = "";
  let n = v.len();
  var i = 0;
  while i < n {
    let a: Int = v[i];
    var j = i;
    while j + 1 < n {
      let x: Int = v[j + 1];
      let y: Int = v[j];
      if x != y + 1 { break; }
      j = j + 1;
    }
    let b: Int = v[j];
    if i > 0 { out = out + ","; }
    if j > i {
      out = out + _cron_value_name(field, a) + "-" + _cron_value_name(field, b);
    } else {
      out = out + _cron_value_name(field, a);
    }
    i = j + 1;
  }
  return out;
}

/// Canonical five-field text of a parsed expression.
/// Params: c - a parsed expression.
/// Returns: the canonical expression, exactly five single-space-separated
/// fields. A field that covers its whole range renders as "*"; otherwise
/// values are ascending, comma-separated, with runs of two or more rendered
/// as "a-b". Rendering is set-canonical, not syntax-preserving: steps and
/// input lists are expanded, so "*/15 * * * *" emits "0,15,30,45 * * * *"
/// and "@yearly" emits "0 0 1 1 *". Day-of-week always emits normalized
/// 0..6 (Sunday = 0).
/// Error case: none.
/// Examples: (0,30 9-17 * * MON-FRI) -> "0,30 9-17 * * 1-5";
/// (* * * * *) -> "* * * * *".
/// Complexity: O(total values).
pub fn cron_emit(c: &CronExpr) -> Str {
  let mins: Vec[Int] = c.minutes;
  let hrs: Vec[Int] = c.hours;
  let ds: Vec[Int] = c.days;
  let mos: Vec[Int] = c.months;
  let dws: Vec[Int] = c.dows;
  return _cron_token(&mins, 0, 59) + " "
    + _cron_token(&hrs, 0, 23) + " "
    + _cron_token(&ds, 1, 31) + " "
    + _cron_token(&mos, 1, 12) + " "
    + _cron_token(&dws, 0, 6);
}

/// Human-readable labelled summary of a parsed expression.
/// Params: c - a parsed expression.
/// Returns: five labelled segments joined by "; ", in field order, with "*"
/// for a full field and the compact set notation of cron_emit otherwise.
/// Months and days-of-week use canonical three-letter uppercase names:
/// for example "minute 0,30; hour 9-17; day-of-month *; month JAN,JUL;
/// day-of-week MON-FRI".
/// Error case: none.
/// Examples: (* * * * *) -> "minute *; hour *; day-of-month *; month *;
/// day-of-week *".
/// Complexity: O(total values).
pub fn cron_describe(c: &CronExpr) -> Str {
  let mins: Vec[Int] = c.minutes;
  let hrs: Vec[Int] = c.hours;
  let ds: Vec[Int] = c.days;
  let mos: Vec[Int] = c.months;
  let dws: Vec[Int] = c.dows;
  return "minute " + _cron_token(&mins, 0, 59)
    + "; hour " + _cron_token(&hrs, 0, 23)
    + "; day-of-month " + _cron_token(&ds, 1, 31)
    + "; month " + _cron_name_token(&mos, 1, 12, CRON_FIELD_MONTH)
    + "; day-of-week " + _cron_name_token(&dws, 0, 6, CRON_FIELD_DOW);
}
