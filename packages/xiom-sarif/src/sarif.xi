// XIOM -- xiom.sarif: SARIF 2.1.0 report codec for a documented JSON subset
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Supported subset (see SPEC.md for the grammar and the exact error catalog):
// a top-level object with `version` (must be exactly "2.1.0"), optional
// `$schema` (kept and re-emitted verbatim) and `runs`; every run has
// `tool.driver.name` and optional `results`; every result has optional
// `ruleId`, optional `level` (error|warning|note|none; an absent level means
// "warning", the SARIF default), a required `message.text` and optional
// `locations`; every location has `physicalLocation.artifactLocation.uri`
// and optional `physicalLocation.region.startLine` / `startColumn` (positive
// integers). Strings are printable ASCII plus the basic escapes (\" \\ \/
// \b \f \n \r \t) and \uXXXX for printable-ASCII code points; integers are
// non-negative and without leading zeros; true/false/null are recognized and
// rejected; floats are rejected; unknown, duplicate and missing keys are
// errors. No fixes, codeFlows, taxonomies, invocations, fingerprints or
// schema validation; no file IO.
//
// v0.61.3 notes that shaped this module:
//   * the report is FLAT: runs, results and locations live in parallel Vec
//     fields (Vec[StructType] is unsupported) plus sentinel-terminated range
//     vectors (run_result_offsets, result_location_offsets), so there are no
//     record vectors and no recursion;
//   * Ok/Err for Result[SarifDoc, Str] are constructed only in the leaf
//     helpers _ok_doc/_err_doc (constructing Results elsewhere miscompiles);
//   * all Str equality goes through xiom.string.compare.str_compare, and
//     neither .len() nor str_len is trusted on Str values read from Vec[Str]
//     elements (BUG 17): the emitter scans bytes up to the NUL terminator;
//   * every byte read from the input is widened with `(b as Int) & 0xFF`;
//   * no FFI: output is collected with xiom.string.builder over Vec[UInt8]
//     and materialized with sb_to_str once per emitted report.

module xiom.sarif

use xiom.string;
use xiom.string.builder;
use xiom.string.compare;
use xiom.convert;

// --------------------------------------------------
//  Level codes and version
// --------------------------------------------------

/// Level code of a result with level "error".
pub const SARIF_LEVEL_ERROR: Int = 0;
/// Level code of a result with level "warning" (also the default when the
/// `level` key is absent, matching SARIF 2.1.0).
pub const SARIF_LEVEL_WARNING: Int = 1;
/// Level code of a result with level "note".
pub const SARIF_LEVEL_NOTE: Int = 2;
/// Level code of a result with level "none".
pub const SARIF_LEVEL_NONE: Int = 3;

// --------------------------------------------------
//  Report container
// --------------------------------------------------

/// Parsed SARIF report: a flat, parallel-vector model.
///
/// schema is the `$schema` value ("") when the key was absent. Runs occupy
/// indices 0..sarif_run_count(d): run_driver_names[r] is the run's
/// tool.driver.name, and the results owned by run r are the indices
/// run_result_offsets[r]..run_result_offsets[r + 1] of the result vectors
/// (run_result_offsets has one sentinel entry per run plus a leading 0).
/// Results occupy indices 0..sarif_result_count(d): result_runs[i] is the
/// owning run index, result_levels[i] is a SARIF_LEVEL_* code and the
/// locations owned by result i are the indices result_location_offsets[i]..
/// result_location_offsets[i + 1] of the location vectors.
/// result_location_offsets likewise has one sentinel entry per result plus a
/// leading 0.
///
/// Fields are implementation details; read them through the accessors below,
/// which guard every index and vector length. A value is only produced by
/// sarif_parse, so the invariants (mirrored pushes, monotonic ranges, level
/// codes 0..3) always hold for parsed reports.
pub type SarifDoc = {
  schema: Str;
  run_driver_names: Vec[Str];
  run_result_offsets: Vec[Int];
  result_runs: Vec[Int];
  result_rule_ids: Vec[Str];
  result_levels: Vec[Int];
  result_messages: Vec[Str];
  result_location_offsets: Vec[Int];
  location_results: Vec[Int];
  location_uris: Vec[Str];
  location_lines: Vec[Int];
  location_columns: Vec[Int];
}

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(d) for Result[SarifDoc, Str].
fn _ok_doc(d: SarifDoc) -> Result[SarifDoc, Str] {
  return Ok(d);
}

// Err(m) for Result[SarifDoc, Str].
fn _err_doc(m: Str) -> Result[SarifDoc, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Parser state and sub-records
// --------------------------------------------------

// Mutable parse state. src/len/pos are the input cursor; the Vec fields
// mirror SarifDoc while parsing; failed/error carry the first failure.
type _SarifParser = {
  src: Str;
  len: Int;
  pos: Int;
  schema: Str;
  run_driver_names: Vec[Str];
  run_result_offsets: Vec[Int];
  result_runs: Vec[Int];
  result_rule_ids: Vec[Str];
  result_levels: Vec[Int];
  result_messages: Vec[Str];
  result_location_offsets: Vec[Int];
  location_results: Vec[Int];
  location_uris: Vec[Str];
  location_lines: Vec[Int];
  location_columns: Vec[Int];
  failed: Bool;
  error: Str;
}

// Collected fields of one artifactLocation object.
type _Artifact = {
  uri: Str;
  has_uri: Bool;
}

// Collected fields of one region object; absent keys stay 0/has_* false.
type _Region = {
  line: Int;
  has_line: Bool;
  col: Int;
  has_col: Bool;
}

// Record the first failure and return false so callers can `return _fail(...)`.
fn _fail(p: &mut _SarifParser, m: Str) -> Bool {
  p.failed = true;
  p.error = m;
  return false;
}

// --------------------------------------------------
//  Byte constants
// --------------------------------------------------

const _S_QUOTE: UInt8 = 34u8;
const _S_BACKSLASH: UInt8 = 92u8;
const _S_SLASH: UInt8 = 47u8;
const _S_OPEN_BRACE: UInt8 = 123u8;
const _S_CLOSE_BRACE: UInt8 = 125u8;
const _S_OPEN_BRACKET: UInt8 = 91u8;
const _S_CLOSE_BRACKET: UInt8 = 93u8;
const _S_COLON: UInt8 = 58u8;
const _S_COMMA: UInt8 = 44u8;
const _S_MINUS: UInt8 = 45u8;
const _S_DOT: UInt8 = 46u8;
const _S_ZERO: UInt8 = 48u8;
const _S_NINE: UInt8 = 57u8;
const _S_LOWER_E: UInt8 = 101u8;
const _S_UPPER_E: UInt8 = 69u8;
const _S_LOWER_U: UInt8 = 117u8;
const _S_SPACE: UInt8 = 32u8;
const _S_TAB: UInt8 = 9u8;
const _S_LF: UInt8 = 10u8;
const _S_CR: UInt8 = 13u8;

// --------------------------------------------------
//  Cursor helpers
// --------------------------------------------------

// Next raw byte as an Int in 0..255, or -1 at end of input (non-advancing).
fn _peek(p: &_SarifParser) -> Int {
  if p.pos >= p.len {
    return -1;
  }
  let b0 = string.byte_at(p.src, p.pos);
  return (b0 as Int) & 0xFF;
}

// Skip space, TAB, LF and CR.
fn _skip_ws(p: &mut _SarifParser) {
  var more = true;
  while more {
    if p.pos >= p.len {
      return;
    }
    let b = (string.byte_at(p.src, p.pos) as Int) & 0xFF;
    if b == 32 || b == 9 || b == 10 || b == 13 {
      p.pos = p.pos + 1;
    } else {
      more = false;
    }
  }
}

// "<msg> at byte <pos>" error text; the position makes every lexical error
// deterministic and locatable.
fn _at(msg: Str, pos: Int) -> Str {
  return "sarif: " + msg + " at byte " + convert.int_to_string(pos);
}

// True when the input at the cursor starts with the ASCII token `tok`
// (case-sensitive). Safe at end of input: byte_at yields 0 there, which never
// matches a token byte.
fn _starts_with(p: &_SarifParser, tok: Str) -> Bool {
  var i = 0;
  let n = string.str_len(tok);
  while i < n {
    let a = string.byte_at(p.src, p.pos + i);
    let b = string.byte_at(tok, i);
    if a != b {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// The JSON literals true/false/null are recognized value kinds but the
// subset has no boolean or null fields, so they are rejected everywhere a
// value is expected with a distinct message. Returns true when a literal was
// seen and the parser was marked failed.
fn _reject_literal(p: &mut _SarifParser) -> Bool {
  if _starts_with(p, "true") || _starts_with(p, "false") {
    p.failed = true;
    p.error = _at("boolean values are not supported", p.pos);
    return true;
  }
  if _starts_with(p, "null") {
    p.failed = true;
    p.error = _at("null values are not supported", p.pos);
    return true;
  }
  return false;
}

// --------------------------------------------------
//  String parser
// --------------------------------------------------

// Hex digit value of a masked byte, or -1.
fn _hex_val(c: Int) -> Int {
  if c >= 48 && c <= 57 {
    return c - 48;
  }
  if c >= 97 && c <= 102 {
    return c - 87;
  }
  if c >= 65 && c <= 70 {
    return c - 55;
  }
  return -1;
}

// Parse the four hex digits of a \u escape (cursor on `u`); only printable
// ASCII code points 0x20..0x7E are accepted.
fn _p_unicode(p: &mut _SarifParser, open: Int, out: &mut Vec[UInt8]) -> Bool {
  let us = p.pos;
  p.pos = p.pos + 1;
  if p.pos + 4 > p.len {
    p.failed = true;
    p.error = _at("unterminated string", open);
    return false;
  }
  var v: Int = 0;
  var k = 0;
  while k < 4 {
    let c = (string.byte_at(p.src, p.pos + k) as Int) & 0xFF;
    let d = _hex_val(c);
    if d < 0 {
      p.failed = true;
      p.error = _at("invalid \\u escape", p.pos + k);
      return false;
    }
    v = v * 16 + d;
    k = k + 1;
  }
  if v < 32 || v > 126 {
    p.failed = true;
    p.error = _at("non-printable \\u escape", us);
    return false;
  }
  out.push(v as UInt8);
  p.pos = p.pos + 4;
  return true;
}

// Parse one escape sequence (cursor on the backslash). Supported: \" \\ \/
// \b \f \n \r \t and \uXXXX for printable-ASCII code points. `open` is the
// opening quote position, used for the unterminated-string error.
fn _p_escape(p: &mut _SarifParser, open: Int, out: &mut Vec[UInt8]) -> Bool {
  p.pos = p.pos + 1;
  if p.pos >= p.len {
    p.failed = true;
    p.error = _at("unterminated string", open);
    return false;
  }
  let e = (string.byte_at(p.src, p.pos) as Int) & 0xFF;
  if e == 34 {
    out.push(_S_QUOTE);
    p.pos = p.pos + 1;
    return true;
  }
  if e == 92 {
    out.push(_S_BACKSLASH);
    p.pos = p.pos + 1;
    return true;
  }
  if e == 47 {
    out.push(_S_SLASH);
    p.pos = p.pos + 1;
    return true;
  }
  if e == 98 {
    out.push(8u8);
    p.pos = p.pos + 1;
    return true;
  }
  if e == 102 {
    out.push(12u8);
    p.pos = p.pos + 1;
    return true;
  }
  if e == 110 {
    out.push(_S_LF);
    p.pos = p.pos + 1;
    return true;
  }
  if e == 114 {
    out.push(_S_CR);
    p.pos = p.pos + 1;
    return true;
  }
  if e == 116 {
    out.push(_S_TAB);
    p.pos = p.pos + 1;
    return true;
  }
  if e == _S_LOWER_U {
    return _p_unicode(p, open, out);
  }
  p.failed = true;
  p.error = _at("unsupported escape", p.pos);
  return false;
}

// Parse a JSON string (cursor on the opening quote). Raw bytes must be
// printable ASCII; control bytes, non-ASCII bytes, unknown escapes and
// non-printable \u code points are deterministic errors. Returns "" when the
// parser was marked failed.
fn _p_string(p: &mut _SarifParser) -> Str {
  let open = p.pos;
  p.pos = p.pos + 1;
  var out = Vec[UInt8].new();
  var done = false;
  while !done {
    if p.pos >= p.len {
      p.failed = true;
      p.error = _at("unterminated string", open);
      return "";
    }
    let b = (string.byte_at(p.src, p.pos) as Int) & 0xFF;
    if b == 34 {
      p.pos = p.pos + 1;
      done = true;
    } elif b == 92 {
      if !_p_escape(p, open, &mut out) {
        return "";
      }
    } elif b < 32 {
      p.failed = true;
      p.error = _at("control character in string", p.pos);
      return "";
    } elif b > 126 {
      p.failed = true;
      p.error = _at("non-ASCII byte in string", p.pos);
      return "";
    } else {
      out.push(b as UInt8);
      p.pos = p.pos + 1;
    }
  }
  return builder.sb_to_str(&out);
}

// --------------------------------------------------
//  Value expectations
// --------------------------------------------------

// Parse a string value at the cursor; "" plus a marked parser on failure.
fn _expect_string(p: &mut _SarifParser) -> Str {
  let b = _peek(p);
  if b < 0 {
    p.failed = true;
    p.error = _at("unexpected end of input", p.len);
    return "";
  }
  if b == 34 {
    return _p_string(p);
  }
  if _reject_literal(p) {
    return "";
  }
  p.failed = true;
  p.error = _at("expected string", p.pos);
  return "";
}

// Consume the `{` at the cursor, or mark the parser failed.
fn _expect_object(p: &mut _SarifParser) -> Bool {
  let b = _peek(p);
  if b < 0 {
    return _fail(p, _at("unexpected end of input", p.len));
  }
  if b == 123 {
    p.pos = p.pos + 1;
    return true;
  }
  if _reject_literal(p) {
    return false;
  }
  return _fail(p, _at("expected object", p.pos));
}

// Consume the `[` at the cursor, or mark the parser failed.
fn _expect_array(p: &mut _SarifParser) -> Bool {
  let b = _peek(p);
  if b < 0 {
    return _fail(p, _at("unexpected end of input", p.len));
  }
  if b == 91 {
    p.pos = p.pos + 1;
    return true;
  }
  if _reject_literal(p) {
    return false;
  }
  return _fail(p, _at("expected array", p.pos));
}

// Consume `:` (whitespace before it is skipped), or mark the parser failed.
fn _p_colon(p: &mut _SarifParser) -> Bool {
  _skip_ws(p);
  let b = _peek(p);
  if b == 58 {
    p.pos = p.pos + 1;
    return true;
  }
  if b < 0 {
    return _fail(p, _at("unexpected end of input", p.len));
  }
  return _fail(p, _at("expected ':'", p.pos));
}

// Parse a decimal integer token starting at the cursor: digits only, no
// sign, no leading zeros, <= INT64_MAX. Returns 0 plus a marked parser on
// failure.
fn _p_int(p: &mut _SarifParser) -> Int {
  let start = p.pos;
  if string.byte_at(p.src, p.pos) == _S_ZERO {
    p.pos = p.pos + 1;
    let nb = _peek(p);
    if nb >= 48 && nb <= 57 {
      p.failed = true;
      p.error = _at("leading zero in integer", start);
      return 0;
    }
    if nb == 46 || nb == 101 || nb == 69 {
      p.failed = true;
      p.error = _at("float values are not supported", start);
      return 0;
    }
    return 0;
  }
  var v: Int = 0;
  var more = true;
  while more {
    let d = _peek(p);
    if d < 48 || d > 57 {
      more = false;
    } else {
      if v > 922337203685477580 {
        p.failed = true;
        p.error = _at("integer out of range", start);
        return 0;
      }
      v = v * 10;
      if v > 9223372036854775807 - (d - 48) {
        p.failed = true;
        p.error = _at("integer out of range", start);
        return 0;
      }
      v = v + (d - 48);
      p.pos = p.pos + 1;
    }
  }
  let nb = _peek(p);
  if nb == 46 || nb == 101 || nb == 69 {
    p.failed = true;
    p.error = _at("float values are not supported", start);
    return 0;
  }
  return v;
}

// Parse an integer value at the cursor; 0 plus a marked parser on failure.
fn _expect_int(p: &mut _SarifParser) -> Int {
  let b = _peek(p);
  if b < 0 {
    p.failed = true;
    p.error = _at("unexpected end of input", p.len);
    return 0;
  }
  if b == 45 {
    p.failed = true;
    p.error = _at("negative integers are not supported", p.pos);
    return 0;
  }
  if b < 48 || b > 57 {
    if _reject_literal(p) {
      return 0;
    }
    p.failed = true;
    p.error = _at("expected integer", p.pos);
    return 0;
  }
  return _p_int(p);
}

// Parse an object key (a quoted string) at the cursor.
fn _p_key(p: &mut _SarifParser) -> Str {
  let b = _peek(p);
  if b == 34 {
    return _p_string(p);
  }
  if b < 0 {
    p.failed = true;
    p.error = _at("unexpected end of input", p.len);
    return "";
  }
  p.failed = true;
  p.error = _at("expected key", p.pos);
  return "";
}

// Consume the separator after an object entry. Returns 1 for `,`, 0 for the
// closing `}` (already consumed), -1 on failure (parser marked).
fn _p_obj_sep(p: &mut _SarifParser) -> Int {
  _skip_ws(p);
  let b = _peek(p);
  if b == 44 {
    p.pos = p.pos + 1;
    return 1;
  }
  if b == 125 {
    p.pos = p.pos + 1;
    return 0;
  }
  if b < 0 {
    return _parse_sep_fail(p, _at("unexpected end of input", p.len));
  }
  return _parse_sep_fail(p, _at("expected ',' or '}'", p.pos));
}

// Consume the separator after an array entry. Returns 1 for `,`, 0 for the
// closing `]` (already consumed), -1 on failure (parser marked).
fn _p_arr_sep(p: &mut _SarifParser) -> Int {
  _skip_ws(p);
  let b = _peek(p);
  if b == 44 {
    p.pos = p.pos + 1;
    return 1;
  }
  if b == 93 {
    p.pos = p.pos + 1;
    return 0;
  }
  if b < 0 {
    return _parse_sep_fail(p, _at("unexpected end of input", p.len));
  }
  return _parse_sep_fail(p, _at("expected ',' or ']'", p.pos));
}

// Fail a separator helper (which returns an Int) with message `m`.
fn _parse_sep_fail(p: &mut _SarifParser, m: Str) -> Int {
  p.failed = true;
  p.error = m;
  return -1;
}

// --------------------------------------------------
//  Schema parsers
// --------------------------------------------------

// Parse a region object: optional positive startLine / startColumn.
fn _parse_region(p: &mut _SarifParser, reg: &mut _Region) -> Bool {
  if !_expect_object(p) {
    return false;
  }
  var seen_line = false;
  var seen_col = false;
  _skip_ws(p);
  if _peek(p) == 125 {
    p.pos = p.pos + 1;
    return true;
  }
  var more = true;
  while more {
    _skip_ws(p);
    let key = _p_key(p);
    if p.failed {
      return false;
    }
    if compare.str_compare(key, "startLine") == 0 {
      if seen_line {
        return _fail(p, "sarif: duplicate key 'startLine'");
      }
      seen_line = true;
      if !_p_colon(p) {
        return false;
      }
      _skip_ws(p);
      let v: Int = _expect_int(p);
      if p.failed {
        return false;
      }
      if v <= 0 {
        return _fail(p, "sarif: startLine must be a positive integer");
      }
      reg.line = v;
      reg.has_line = true;
    } elif compare.str_compare(key, "startColumn") == 0 {
      if seen_col {
        return _fail(p, "sarif: duplicate key 'startColumn'");
      }
      seen_col = true;
      if !_p_colon(p) {
        return false;
      }
      _skip_ws(p);
      let v: Int = _expect_int(p);
      if p.failed {
        return false;
      }
      if v <= 0 {
        return _fail(p, "sarif: startColumn must be a positive integer");
      }
      reg.col = v;
      reg.has_col = true;
    } else {
      return _fail(p, "sarif: unknown key '" + key + "'");
    }
    let sep = _p_obj_sep(p);
    if sep < 0 {
      return false;
    }
    if sep == 0 {
      more = false;
    }
  }
  return true;
}

// Parse an artifactLocation object: a required string `uri`.
fn _parse_artifact(p: &mut _SarifParser, art: &mut _Artifact) -> Bool {
  if !_expect_object(p) {
    return false;
  }
  _skip_ws(p);
  if _peek(p) == 125 {
    p.pos = p.pos + 1;
  } else {
    var more = true;
    while more {
      _skip_ws(p);
      let key = _p_key(p);
      if p.failed {
        return false;
      }
      if compare.str_compare(key, "uri") == 0 {
        if art.has_uri {
          return _fail(p, "sarif: duplicate key 'uri'");
        }
        if !_p_colon(p) {
          return false;
        }
        _skip_ws(p);
        let v: Str = _expect_string(p);
        if p.failed {
          return false;
        }
        art.uri = v;
        art.has_uri = true;
      } else {
        return _fail(p, "sarif: unknown key '" + key + "'");
      }
      let sep = _p_obj_sep(p);
      if sep < 0 {
        return false;
      }
      if sep == 0 {
        more = false;
      }
    }
  }
  if !art.has_uri {
    return _fail(p, "sarif: missing key 'uri'");
  }
  return true;
}

// Parse one location object and append it to the location vectors with
// `result_index` as its owner. The uri/line/column locals are only pushed
// after the whole object is known, so a location can never leave a partial
// row behind.
fn _parse_location(p: &mut _SarifParser, result_index: Int) -> Bool {
  if !_expect_object(p) {
    return false;
  }
  var art = _Artifact{ uri: ""; has_uri: false; };
  var reg = _Region{ line: 0; has_line: false; col: 0; has_col: false; };
  var seen_physical = false;
  var has_artifact = false;
  var seen_region = false;
  _skip_ws(p);
  if _peek(p) == 125 {
    p.pos = p.pos + 1;
  } else {
    var more = true;
    while more {
      _skip_ws(p);
      let key = _p_key(p);
      if p.failed {
        return false;
      }
      if compare.str_compare(key, "physicalLocation") == 0 {
        if seen_physical {
          return _fail(p, "sarif: duplicate key 'physicalLocation'");
        }
        seen_physical = true;
        if !_p_colon(p) {
          return false;
        }
        _skip_ws(p);
        if !_expect_object(p) {
          return false;
        }
        _skip_ws(p);
        if _peek(p) == 125 {
          p.pos = p.pos + 1;
        } else {
          var more2 = true;
          while more2 {
            _skip_ws(p);
            let key2 = _p_key(p);
            if p.failed {
              return false;
            }
            if compare.str_compare(key2, "artifactLocation") == 0 {
              if has_artifact {
                return _fail(p, "sarif: duplicate key 'artifactLocation'");
              }
              has_artifact = true;
              if !_p_colon(p) {
                return false;
              }
              _skip_ws(p);
              if !_parse_artifact(p, &mut art) {
                return false;
              }
            } elif compare.str_compare(key2, "region") == 0 {
              if seen_region {
                return _fail(p, "sarif: duplicate key 'region'");
              }
              seen_region = true;
              if !_p_colon(p) {
                return false;
              }
              _skip_ws(p);
              if !_parse_region(p, &mut reg) {
                return false;
              }
            } else {
              return _fail(p, "sarif: unknown key '" + key2 + "'");
            }
            let sep2 = _p_obj_sep(p);
            if sep2 < 0 {
              return false;
            }
            if sep2 == 0 {
              more2 = false;
            }
          }
        }
        if !has_artifact {
          return _fail(p, "sarif: missing key 'artifactLocation'");
        }
      } else {
        return _fail(p, "sarif: unknown key '" + key + "'");
      }
      let sep = _p_obj_sep(p);
      if sep < 0 {
        return false;
      }
      if sep == 0 {
        more = false;
      }
    }
  }
  if !seen_physical {
    return _fail(p, "sarif: missing key 'physicalLocation'");
  }
  p.location_results.push(result_index);
  p.location_uris.push(art.uri);
  p.location_lines.push(reg.line);
  p.location_columns.push(reg.col);
  return true;
}

// Parse a locations array for result `result_index`.
fn _parse_locations(p: &mut _SarifParser, result_index: Int) -> Bool {
  if !_expect_array(p) {
    return false;
  }
  _skip_ws(p);
  if _peek(p) == 93 {
    p.pos = p.pos + 1;
    return true;
  }
  var more = true;
  while more {
    _skip_ws(p);
    if !_parse_location(p, result_index) {
      return false;
    }
    let sep = _p_arr_sep(p);
    if sep < 0 {
      return false;
    }
    if sep == 0 {
      more = false;
    }
  }
  return true;
}

// Parse a message object: a required string `text` (which may be empty).
fn _parse_message(p: &mut _SarifParser) -> Str {
  if !_expect_object(p) {
    return "";
  }
  var text = "";
  var seen_text = false;
  _skip_ws(p);
  if _peek(p) == 125 {
    p.pos = p.pos + 1;
  } else {
    var more = true;
    while more {
      _skip_ws(p);
      let key = _p_key(p);
      if p.failed {
        return "";
      }
      if compare.str_compare(key, "text") == 0 {
        if seen_text {
          _fail(p, "sarif: duplicate key 'text'");
          return "";
        }
        if !_p_colon(p) {
          return "";
        }
        _skip_ws(p);
        let v: Str = _expect_string(p);
        if p.failed {
          return "";
        }
        text = v;
        seen_text = true;
      } else {
        _fail(p, "sarif: unknown key '" + key + "'");
        return "";
      }
      let sep = _p_obj_sep(p);
      if sep < 0 {
        return "";
      }
      if sep == 0 {
        more = false;
      }
    }
  }
  if !seen_text {
    _fail(p, "sarif: missing key 'text'");
    return "";
  }
  return text;
}

// Level code of a level string, -1 when the value is not a valid level.
fn _level_code(v: Str) -> Int {
  if compare.str_compare(v, "error") == 0 {
    return SARIF_LEVEL_ERROR;
  }
  if compare.str_compare(v, "warning") == 0 {
    return SARIF_LEVEL_WARNING;
  }
  if compare.str_compare(v, "note") == 0 {
    return SARIF_LEVEL_NOTE;
  }
  if compare.str_compare(v, "none") == 0 {
    return SARIF_LEVEL_NONE;
  }
  return -1;
}

// Level string of a level code, "" when the code is unknown.
fn _level_name(level: Int) -> Str {
  if level == SARIF_LEVEL_ERROR {
    return "error";
  }
  if level == SARIF_LEVEL_WARNING {
    return "warning";
  }
  if level == SARIF_LEVEL_NOTE {
    return "note";
  }
  if level == SARIF_LEVEL_NONE {
    return "none";
  }
  return "";
}

// Parse one result object. `run_index` is the owning run. The result row is
// appended only after the closing brace, so its locations (which may appear
// before or after the other keys) can reference the pending result index
// `p.result_runs.len()`.
fn _parse_result(p: &mut _SarifParser, run_index: Int) -> Bool {
  if !_expect_object(p) {
    return false;
  }
  let result_index = p.result_runs.len();
  var rule_id = "";
  var level = SARIF_LEVEL_WARNING;
  var message = "";
  var seen_rule_id = false;
  var seen_level = false;
  var seen_message = false;
  var seen_locations = false;
  _skip_ws(p);
  if _peek(p) == 125 {
    p.pos = p.pos + 1;
  } else {
    var more = true;
    while more {
      _skip_ws(p);
      let key = _p_key(p);
      if p.failed {
        return false;
      }
      if compare.str_compare(key, "ruleId") == 0 {
        if seen_rule_id {
          return _fail(p, "sarif: duplicate key 'ruleId'");
        }
        seen_rule_id = true;
        if !_p_colon(p) {
          return false;
        }
        _skip_ws(p);
        let v: Str = _expect_string(p);
        if p.failed {
          return false;
        }
        rule_id = v;
      } elif compare.str_compare(key, "level") == 0 {
        if seen_level {
          return _fail(p, "sarif: duplicate key 'level'");
        }
        seen_level = true;
        if !_p_colon(p) {
          return false;
        }
        _skip_ws(p);
        let v: Str = _expect_string(p);
        if p.failed {
          return false;
        }
        let code = _level_code(v);
        if code < 0 {
          return _fail(p, "sarif: invalid level '" + v + "'");
        }
        level = code;
      } elif compare.str_compare(key, "message") == 0 {
        if seen_message {
          return _fail(p, "sarif: duplicate key 'message'");
        }
        seen_message = true;
        if !_p_colon(p) {
          return false;
        }
        _skip_ws(p);
        let v: Str = _parse_message(p);
        if p.failed {
          return false;
        }
        message = v;
      } elif compare.str_compare(key, "locations") == 0 {
        if seen_locations {
          return _fail(p, "sarif: duplicate key 'locations'");
        }
        seen_locations = true;
        if !_p_colon(p) {
          return false;
        }
        _skip_ws(p);
        if !_parse_locations(p, result_index) {
          return false;
        }
      } else {
        return _fail(p, "sarif: unknown key '" + key + "'");
      }
      let sep = _p_obj_sep(p);
      if sep < 0 {
        return false;
      }
      if sep == 0 {
        more = false;
      }
    }
  }
  if !seen_message {
    return _fail(p, "sarif: missing key 'message'");
  }
  p.result_runs.push(run_index);
  p.result_rule_ids.push(rule_id);
  p.result_levels.push(level);
  p.result_messages.push(message);
  p.result_location_offsets.push(p.location_uris.len());
  return true;
}

// Parse a results array for run `run_index`.
fn _parse_results(p: &mut _SarifParser, run_index: Int) -> Bool {
  if !_expect_array(p) {
    return false;
  }
  _skip_ws(p);
  if _peek(p) == 93 {
    p.pos = p.pos + 1;
    return true;
  }
  var more = true;
  while more {
    _skip_ws(p);
    if !_parse_result(p, run_index) {
      return false;
    }
    let sep = _p_arr_sep(p);
    if sep < 0 {
      return false;
    }
    if sep == 0 {
      more = false;
    }
  }
  return true;
}

// Parse a driver object: a required non-empty string `name`. The name is
// returned to the caller ("" when the parser was marked failed).
fn _parse_driver(p: &mut _SarifParser) -> Str {
  if !_expect_object(p) {
    return "";
  }
  var name = "";
  var seen_name = false;
  _skip_ws(p);
  if _peek(p) == 125 {
    p.pos = p.pos + 1;
  } else {
    var more = true;
    while more {
      _skip_ws(p);
      let key = _p_key(p);
      if p.failed {
        return "";
      }
      if compare.str_compare(key, "name") == 0 {
        if seen_name {
          _fail(p, "sarif: duplicate key 'name'");
          return "";
        }
        if !_p_colon(p) {
          return "";
        }
        _skip_ws(p);
        let v: Str = _expect_string(p);
        if p.failed {
          return "";
        }
        if compare.str_compare(v, "") == 0 {
          _fail(p, "sarif: empty tool.driver.name");
          return "";
        }
        name = v;
        seen_name = true;
      } else {
        _fail(p, "sarif: unknown key '" + key + "'");
        return "";
      }
      let sep = _p_obj_sep(p);
      if sep < 0 {
        return "";
      }
      if sep == 0 {
        more = false;
      }
    }
  }
  if !seen_name {
    _fail(p, "sarif: missing key 'name'");
    return "";
  }
  return name;
}

// Parse a tool object: a required `driver` object whose name is returned.
fn _parse_tool(p: &mut _SarifParser) -> Str {
  if !_expect_object(p) {
    return "";
  }
  var name = "";
  var seen_driver = false;
  _skip_ws(p);
  if _peek(p) == 125 {
    p.pos = p.pos + 1;
  } else {
    var more = true;
    while more {
      _skip_ws(p);
      let key = _p_key(p);
      if p.failed {
        return "";
      }
      if compare.str_compare(key, "driver") == 0 {
        if seen_driver {
          _fail(p, "sarif: duplicate key 'driver'");
          return "";
        }
        seen_driver = true;
        if !_p_colon(p) {
          return "";
        }
        _skip_ws(p);
        name = _parse_driver(p);
        if p.failed {
          return "";
        }
      } else {
        _fail(p, "sarif: unknown key '" + key + "'");
        return "";
      }
      let sep = _p_obj_sep(p);
      if sep < 0 {
        return "";
      }
      if sep == 0 {
        more = false;
      }
    }
  }
  if !seen_driver {
    _fail(p, "sarif: missing key 'driver'");
    return "";
  }
  return name;
}

// Parse one run object. The run row (driver name and result range) is
// appended only after the closing brace; results parsed before the `tool`
// key still record this run's index.
fn _parse_run(p: &mut _SarifParser) -> Bool {
  if !_expect_object(p) {
    return false;
  }
  let run_index = p.run_driver_names.len();
  var driver_name = "";
  var seen_tool = false;
  var seen_results = false;
  _skip_ws(p);
  if _peek(p) == 125 {
    p.pos = p.pos + 1;
  } else {
    var more = true;
    while more {
      _skip_ws(p);
      let key = _p_key(p);
      if p.failed {
        return false;
      }
      if compare.str_compare(key, "tool") == 0 {
        if seen_tool {
          return _fail(p, "sarif: duplicate key 'tool'");
        }
        seen_tool = true;
        if !_p_colon(p) {
          return false;
        }
        _skip_ws(p);
        let nm: Str = _parse_tool(p);
        if p.failed {
          return false;
        }
        driver_name = nm;
      } elif compare.str_compare(key, "results") == 0 {
        if seen_results {
          return _fail(p, "sarif: duplicate key 'results'");
        }
        seen_results = true;
        if !_p_colon(p) {
          return false;
        }
        _skip_ws(p);
        if !_parse_results(p, run_index) {
          return false;
        }
      } else {
        return _fail(p, "sarif: unknown key '" + key + "'");
      }
      let sep = _p_obj_sep(p);
      if sep < 0 {
        return false;
      }
      if sep == 0 {
        more = false;
      }
    }
  }
  if !seen_tool {
    return _fail(p, "sarif: missing key 'tool'");
  }
  p.run_driver_names.push(driver_name);
  p.run_result_offsets.push(p.result_runs.len());
  return true;
}

// Parse a runs array.
fn _parse_runs(p: &mut _SarifParser) -> Bool {
  if !_expect_array(p) {
    return false;
  }
  _skip_ws(p);
  if _peek(p) == 93 {
    p.pos = p.pos + 1;
    return true;
  }
  var more = true;
  while more {
    _skip_ws(p);
    if !_parse_run(p) {
      return false;
    }
    let sep = _p_arr_sep(p);
    if sep < 0 {
      return false;
    }
    if sep == 0 {
      more = false;
    }
  }
  return true;
}

// Parse the top-level document object: `$schema` (optional), `version`
// (required, exactly "2.1.0") and `runs` (required array).
fn _parse_top(p: &mut _SarifParser) -> Bool {
  if !_expect_object(p) {
    return false;
  }
  var seen_schema = false;
  var seen_version = false;
  var seen_runs = false;
  _skip_ws(p);
  if _peek(p) == 125 {
    p.pos = p.pos + 1;
  } else {
    var more = true;
    while more {
      _skip_ws(p);
      let key = _p_key(p);
      if p.failed {
        return false;
      }
      if compare.str_compare(key, "$schema") == 0 {
        if seen_schema {
          return _fail(p, "sarif: duplicate key '$schema'");
        }
        seen_schema = true;
        if !_p_colon(p) {
          return false;
        }
        _skip_ws(p);
        let v: Str = _expect_string(p);
        if p.failed {
          return false;
        }
        p.schema = v;
      } elif compare.str_compare(key, "version") == 0 {
        if seen_version {
          return _fail(p, "sarif: duplicate key 'version'");
        }
        seen_version = true;
        if !_p_colon(p) {
          return false;
        }
        _skip_ws(p);
        let v: Str = _expect_string(p);
        if p.failed {
          return false;
        }
        if compare.str_compare(v, "2.1.0") != 0 {
          return _fail(p, "sarif: unsupported version '" + v + "'");
        }
      } elif compare.str_compare(key, "runs") == 0 {
        if seen_runs {
          return _fail(p, "sarif: duplicate key 'runs'");
        }
        seen_runs = true;
        if !_p_colon(p) {
          return false;
        }
        _skip_ws(p);
        if !_parse_runs(p) {
          return false;
        }
      } else {
        return _fail(p, "sarif: unknown key '" + key + "'");
      }
      let sep = _p_obj_sep(p);
      if sep < 0 {
        return false;
      }
      if sep == 0 {
        more = false;
      }
    }
  }
  if !seen_version {
    return _fail(p, "sarif: missing key 'version'");
  }
  if !seen_runs {
    return _fail(p, "sarif: missing key 'runs'");
  }
  return true;
}

// --------------------------------------------------
//  Public parsing API
// --------------------------------------------------

/// The SARIF version this codec accepts and emits ("2.1.0").
/// Returns: the literal "2.1.0".
/// Error case: none.
/// Complexity: O(1).
pub fn sarif_version() -> Str {
  return "2.1.0";
}

/// Parse a SARIF 2.1.0 report in the documented JSON subset.
/// Params: text - the whole report as one Str.
/// Returns: Ok(doc) with the flat model. Keys may appear in any order;
/// whitespace between tokens is ignored. An absent result `level` becomes
/// SARIF_LEVEL_WARNING (the SARIF default). `$schema` is kept verbatim and
/// re-emitted; every other key is limited to the subset in SPEC.md.
/// Error case: Err("sarif: ...") for the first malformed construct; the
/// catalog covers byte-level errors (unterminated strings, bad escapes,
/// floats, negative or overlong integers, unexpected tokens) and schema
/// errors (unsupported version, unknown/duplicate/missing keys, invalid
/// level, non-positive line/column). See SPEC.md for the full list.
/// Complexity: O(n) over the report bytes.
pub fn sarif_parse(text: Str) -> Result[SarifDoc, Str] {
  var p = _SarifParser{
    src: text;
    len: text.len();
    pos: 0;
    schema: "";
    run_driver_names: Vec[Str].new();
    run_result_offsets: Vec[Int].new();
    result_runs: Vec[Int].new();
    result_rule_ids: Vec[Str].new();
    result_levels: Vec[Int].new();
    result_messages: Vec[Str].new();
    result_location_offsets: Vec[Int].new();
    location_results: Vec[Int].new();
    location_uris: Vec[Str].new();
    location_lines: Vec[Int].new();
    location_columns: Vec[Int].new();
    failed: false;
    error: "";
  };
  p.run_result_offsets.push(0);
  p.result_location_offsets.push(0);
  if !_parse_top(&mut p) {
    return _err_doc(p.error);
  }
  _skip_ws(&mut p);
  if p.pos != p.len {
    return _err_doc(_at("trailing data", p.pos));
  }
  return _ok_doc(SarifDoc{
    schema: p.schema;
    run_driver_names: p.run_driver_names;
    run_result_offsets: p.run_result_offsets;
    result_runs: p.result_runs;
    result_rule_ids: p.result_rule_ids;
    result_levels: p.result_levels;
    result_messages: p.result_messages;
    result_location_offsets: p.result_location_offsets;
    location_results: p.location_results;
    location_uris: p.location_uris;
    location_lines: p.location_lines;
    location_columns: p.location_columns;
  });
}

// --------------------------------------------------
//  Emitter
// --------------------------------------------------

// Append every byte of `s` up to the NUL terminator. Used for Str values
// that may come from Vec[Str] elements, whose .len() is not trusted (BUG 17).
fn _push_str_bytes(out: &mut Vec[UInt8], s: Str) {
  var i = 0;
  loop {
    let b = string.byte_at(s, i);
    if b == 0u8 {
      break;
    }
    out.push(b);
    i = i + 1;
  }
}

// Append `s` as the body of a JSON string: `"` and `\` are escaped, the
// five JSON control escapes are used for 0x08/0x09/0x0A/0x0C/0x0D, and every
// other byte is copied verbatim (parse only produces printable ASCII plus
// those five control bytes).
fn _push_json_escaped(out: &mut Vec[UInt8], s: Str) {
  var i = 0;
  loop {
    let b = (string.byte_at(s, i) as Int) & 0xFF;
    if b == 0 {
      break;
    }
    if b == 34 {
      builder.sb_push_str(out, "\\\"");
    } elif b == 92 {
      builder.sb_push_str(out, "\\\\");
    } elif b == 8 {
      builder.sb_push_str(out, "\\b");
    } elif b == 9 {
      builder.sb_push_str(out, "\\t");
    } elif b == 10 {
      builder.sb_push_str(out, "\\n");
    } elif b == 12 {
      builder.sb_push_str(out, "\\f");
    } elif b == 13 {
      builder.sb_push_str(out, "\\r");
    } else {
      out.push(b as UInt8);
    }
    i = i + 1;
  }
}

// Append `"<escaped s>"`.
fn _push_json_str(out: &mut Vec[UInt8], s: Str) {
  out.push(_S_QUOTE);
  _push_json_escaped(out, s);
  out.push(_S_QUOTE);
}

// Emit one result object. Only results with a valid range are reached
// (callers clamp to sarif_result_count).
fn _emit_result(out: &mut Vec[UInt8], d: &SarifDoc, i: Int) {
  builder.sb_push_str(out, "{");
  let rid: Str = d.result_rule_ids[i];
  if compare.str_compare(rid, "") != 0 {
    builder.sb_push_str(out, "\"ruleId\":");
    _push_json_str(out, rid);
    builder.sb_push_str(out, ",");
  }
  builder.sb_push_str(out, "\"level\":");
  let lv: Int = d.result_levels[i];
  _push_json_str(out, _level_name(lv));
  builder.sb_push_str(out, ",\"message\":{\"text\":");
  let msg: Str = d.result_messages[i];
  _push_json_str(out, msg);
  builder.sb_push_str(out, "},\"locations\":[");
  var from: Int = d.result_location_offsets[i];
  var to: Int = d.result_location_offsets[i + 1];
  let lcount = sarif_location_count(d);
  if to > lcount {
    to = lcount;
  }
  if from < 0 {
    from = 0;
  }
  if from > to {
    from = to;
  }
  var k = from;
  while k < to {
    if k > from {
      out.push(_S_COMMA);
    }
    _emit_location(out, d, k);
    k = k + 1;
  }
  builder.sb_push_str(out, "]}");
}

// Emit one location object. The region is emitted only when a line or column
// is present, and its keys in the fixed order startLine, startColumn.
fn _emit_location(out: &mut Vec[UInt8], d: &SarifDoc, k: Int) {
  builder.sb_push_str(out, "{\"physicalLocation\":{\"artifactLocation\":{\"uri\":");
  let uri: Str = d.location_uris[k];
  _push_json_str(out, uri);
  builder.sb_push_str(out, "}");
  let line: Int = d.location_lines[k];
  let col: Int = d.location_columns[k];
  if line > 0 || col > 0 {
    builder.sb_push_str(out, ",\"region\":{");
    var need = false;
    if line > 0 {
      builder.sb_push_str(out, "\"startLine\":");
      builder.sb_push_str(out, convert.int_to_string(line));
      need = true;
    }
    if col > 0 {
      if need {
        out.push(_S_COMMA);
      }
      builder.sb_push_str(out, "\"startColumn\":");
      builder.sb_push_str(out, convert.int_to_string(col));
    }
    builder.sb_push_str(out, "}");
  }
  builder.sb_push_str(out, "}}");
}

/// Serialize a parsed report back to canonical, compact SARIF JSON.
/// Params: d - the report to emit.
/// Returns: a deterministic single-line Str with fixed key order: top-level
/// `$schema` (only when non-empty), `version`, `runs`; per run `tool` then
/// `results`; per result `ruleId` (only when non-empty), `level`, `message`,
/// `locations`; per location `physicalLocation` with `artifactLocation.uri`
/// and, only when a line or column is present, `region` with `startLine`
/// then `startColumn`. For any doc produced by sarif_parse, re-parsing the
/// output yields an equal model and re-emitting yields identical bytes.
/// Strings are JSON-escaped on the way out (`\"`, `\\`, `\b`, `\f`, `\n`,
/// `\r`, `\t`).
/// Error case: none.
/// Complexity: O(runs + results + locations + output bytes).
pub fn sarif_emit(d: &SarifDoc) -> Str {
  var out = Vec[UInt8].new();
  builder.sb_push_str(&mut out, "{");
  let sc: Str = d.schema;
  if compare.str_compare(sc, "") != 0 {
    builder.sb_push_str(&mut out, "\"$schema\":");
    _push_json_str(&mut out, sc);
    out.push(_S_COMMA);
  }
  builder.sb_push_str(&mut out, "\"version\":\"2.1.0\",\"runs\":[");
  var r = 0;
  while r < sarif_run_count(d) {
    if r > 0 {
      out.push(_S_COMMA);
    }
    builder.sb_push_str(&mut out, "{\"tool\":{\"driver\":{\"name\":");
    let nm: Str = d.run_driver_names[r];
    _push_json_str(&mut out, nm);
    builder.sb_push_str(&mut out, "}},\"results\":[");
    var from: Int = d.run_result_offsets[r];
    var to: Int = d.run_result_offsets[r + 1];
    let rcount = sarif_result_count(d);
    if to > rcount {
      to = rcount;
    }
    if from < 0 {
      from = 0;
    }
    if from > to {
      from = to;
    }
    var i = from;
    while i < to {
      if i > from {
        out.push(_S_COMMA);
      }
      _emit_result(&mut out, d, i);
      i = i + 1;
    }
    builder.sb_push_str(&mut out, "]}");
    r = r + 1;
  }
  builder.sb_push_str(&mut out, "]}");
  return builder.sb_to_str(&out);
}

// --------------------------------------------------
//  Document accessors
// --------------------------------------------------

/// The `$schema` value of the report.
/// Params: d - the report.
/// Returns: the schema string as written, or "" when the key was absent.
/// Error case: none.
/// Complexity: O(1).
pub fn sarif_schema(d: &SarifDoc) -> Str {
  return d.schema;
}

/// Number of runs.
/// Params: d - the report.
/// Returns: the run count, computed as the minimum of the run vectors, so a
/// hand-built report with drifted vectors stays safe to traverse; 0 for an
/// empty report.
/// Error case: none.
/// Complexity: O(1).
pub fn sarif_run_count(d: &SarifDoc) -> Int {
  var n = d.run_driver_names.len();
  let on: Int = d.run_result_offsets.len();
  if on == 0 {
    return 0;
  }
  if on - 1 < n {
    n = on - 1;
  }
  return n;
}

/// Driver name of run `r` (tool.driver.name).
/// Params: d - the report; r - the run index.
/// Returns: the name, or "" when `r` is out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn sarif_run_driver_name(d: &SarifDoc, r: Int) -> Str {
  if r < 0 || r >= sarif_run_count(d) {
    return "";
  }
  let v: Vec[Str] = d.run_driver_names;
  let s: Str = v[r];
  return s;
}

/// Number of results owned by run `r`.
/// Params: d - the report; r - the run index.
/// Returns: the result count; 0 when `r` is out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn sarif_run_result_count(d: &SarifDoc, r: Int) -> Int {
  if r < 0 || r >= sarif_run_count(d) {
    return 0;
  }
  let from: Int = d.run_result_offsets[r];
  let to: Int = d.run_result_offsets[r + 1];
  let total = sarif_result_count(d);
  var hi = to;
  if hi > total {
    hi = total;
  }
  if hi < from {
    return 0;
  }
  return hi - from;
}

/// Number of results owned by run `r` with level `level`.
/// Params: d - the report; r - the run index; level - a SARIF_LEVEL_* code
/// (any other value counts 0).
/// Returns: the count; 0 when `r` is out of range.
/// Error case: none.
/// Complexity: O(results of the run).
pub fn sarif_run_level_count(d: &SarifDoc, r: Int, level: Int) -> Int {
  if r < 0 || r >= sarif_run_count(d) {
    return 0;
  }
  let total = sarif_result_count(d);
  let from: Int = d.run_result_offsets[r];
  var hi: Int = d.run_result_offsets[r + 1];
  if hi > total {
    hi = total;
  }
  if hi < from {
    return 0;
  }
  var n = 0;
  var i = from;
  while i < hi {
    let lv: Int = d.result_levels[i];
    if lv == level {
      n = n + 1;
    }
    i = i + 1;
  }
  return n;
}

/// Total number of results across all runs.
/// Params: d - the report.
/// Returns: the result count, computed as the minimum of the result vectors
/// (including the result_location_offsets range); 0 for an empty report.
/// Error case: none.
/// Complexity: O(1).
pub fn sarif_result_count(d: &SarifDoc) -> Int {
  var n = d.result_runs.len();
  if d.result_rule_ids.len() < n {
    n = d.result_rule_ids.len();
  }
  if d.result_levels.len() < n {
    n = d.result_levels.len();
  }
  if d.result_messages.len() < n {
    n = d.result_messages.len();
  }
  let on: Int = d.result_location_offsets.len();
  if on == 0 {
    return 0;
  }
  if on - 1 < n {
    n = on - 1;
  }
  return n;
}

/// Owning run index of result `i`.
/// Params: d - the report; i - the result index.
/// Returns: the run index, or -1 when `i` is out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn sarif_result_run(d: &SarifDoc, i: Int) -> Int {
  if i < 0 || i >= sarif_result_count(d) {
    return -1;
  }
  let v: Int = d.result_runs[i];
  return v;
}

/// `ruleId` of result `i`.
/// Params: d - the report; i - the result index.
/// Returns: the rule id, or "" when the key was absent or `i` is out of
/// range.
/// Error case: none.
/// Complexity: O(1).
pub fn sarif_result_rule_id(d: &SarifDoc, i: Int) -> Str {
  if i < 0 || i >= sarif_result_count(d) {
    return "";
  }
  let v: Vec[Str] = d.result_rule_ids;
  let s: Str = v[i];
  return s;
}

/// Level of result `i` as a SARIF_LEVEL_* code.
/// Params: d - the report; i - the result index.
/// Returns: the level code, or -1 when `i` is out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn sarif_result_level(d: &SarifDoc, i: Int) -> Int {
  if i < 0 || i >= sarif_result_count(d) {
    return -1;
  }
  let v: Int = d.result_levels[i];
  return v;
}

/// Message text of result `i` (message.text).
/// Params: d - the report; i - the result index.
/// Returns: the text, or "" when `i` is out of range (the parsed text itself
/// may also be empty).
/// Error case: none.
/// Complexity: O(1).
pub fn sarif_result_message(d: &SarifDoc, i: Int) -> Str {
  if i < 0 || i >= sarif_result_count(d) {
    return "";
  }
  let v: Vec[Str] = d.result_messages;
  let s: Str = v[i];
  return s;
}

/// Number of locations owned by result `i`.
/// Params: d - the report; i - the result index.
/// Returns: the location count; 0 when `i` is out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn sarif_result_location_count(d: &SarifDoc, i: Int) -> Int {
  if i < 0 || i >= sarif_result_count(d) {
    return 0;
  }
  let from: Int = d.result_location_offsets[i];
  let to: Int = d.result_location_offsets[i + 1];
  let total = sarif_location_count(d);
  var hi = to;
  if hi > total {
    hi = total;
  }
  if hi < from {
    return 0;
  }
  return hi - from;
}

// Index of the first location of result `i`, or -1 when the result has none
// (or `i` is out of range). Shared by the first-location convenience
// accessors.
fn _first_location(d: &SarifDoc, i: Int) -> Int {
  if sarif_result_location_count(d, i) == 0 {
    return -1;
  }
  let from: Int = d.result_location_offsets[i];
  if from < 0 || from >= sarif_location_count(d) {
    return -1;
  }
  return from;
}

/// URI of result `i`'s first location (physicalLocation.artifactLocation.uri).
/// Params: d - the report; i - the result index.
/// Returns: the first location's uri, or "" when the result has no locations
/// or `i` is out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn sarif_result_uri(d: &SarifDoc, i: Int) -> Str {
  let k = _first_location(d, i);
  if k < 0 {
    return "";
  }
  let v: Vec[Str] = d.location_uris;
  let s: Str = v[k];
  return s;
}

/// startLine of result `i`'s first location, 0 when absent.
/// Params: d - the report; i - the result index.
/// Returns: the first location's startLine, or 0 when the result has no
/// locations, the region has no startLine, or `i` is out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn sarif_result_line(d: &SarifDoc, i: Int) -> Int {
  let k = _first_location(d, i);
  if k < 0 {
    return 0;
  }
  let v: Int = d.location_lines[k];
  return v;
}

/// startColumn of result `i`'s first location, 0 when absent.
/// Params: d - the report; i - the result index.
/// Returns: the first location's startColumn, or 0 when the result has no
/// locations, the region has no startColumn, or `i` is out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn sarif_result_column(d: &SarifDoc, i: Int) -> Int {
  let k = _first_location(d, i);
  if k < 0 {
    return 0;
  }
  let v: Int = d.location_columns[k];
  return v;
}

/// Total number of locations across all results.
/// Params: d - the report.
/// Returns: the location count, computed as the minimum of the location
/// vectors; 0 for an empty report.
/// Error case: none.
/// Complexity: O(1).
pub fn sarif_location_count(d: &SarifDoc) -> Int {
  var n = d.location_results.len();
  if d.location_uris.len() < n {
    n = d.location_uris.len();
  }
  if d.location_lines.len() < n {
    n = d.location_lines.len();
  }
  if d.location_columns.len() < n {
    n = d.location_columns.len();
  }
  return n;
}

/// Owning result index of location `i`.
/// Params: d - the report; i - the location index.
/// Returns: the result index, or -1 when `i` is out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn sarif_location_result(d: &SarifDoc, i: Int) -> Int {
  if i < 0 || i >= sarif_location_count(d) {
    return -1;
  }
  let v: Int = d.location_results[i];
  return v;
}

/// URI of location `i` (physicalLocation.artifactLocation.uri).
/// Params: d - the report; i - the location index.
/// Returns: the uri, or "" when `i` is out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn sarif_location_uri(d: &SarifDoc, i: Int) -> Str {
  if i < 0 || i >= sarif_location_count(d) {
    return "";
  }
  let v: Vec[Str] = d.location_uris;
  let s: Str = v[i];
  return s;
}

/// startLine of location `i`, 0 when absent.
/// Params: d - the report; i - the location index.
/// Returns: the startLine, or 0 when the region has no startLine or `i` is
/// out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn sarif_location_line(d: &SarifDoc, i: Int) -> Int {
  if i < 0 || i >= sarif_location_count(d) {
    return 0;
  }
  let v: Int = d.location_lines[i];
  return v;
}

/// startColumn of location `i`, 0 when absent.
/// Params: d - the report; i - the location index.
/// Returns: the startColumn, or 0 when the region has no startColumn or `i`
/// is out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn sarif_location_column(d: &SarifDoc, i: Int) -> Int {
  if i < 0 || i >= sarif_location_count(d) {
    return 0;
  }
  let v: Int = d.location_columns[i];
  return v;
}

/// Number of results with level `level` across all runs.
/// Params: d - the report; level - a SARIF_LEVEL_* code (any other value
/// counts 0).
/// Returns: the count.
/// Error case: none.
/// Complexity: O(results).
pub fn sarif_level_count(d: &SarifDoc, level: Int) -> Int {
  var n = 0;
  var i = 0;
  while i < d.result_levels.len() {
    let lv: Int = d.result_levels[i];
    if lv == level {
      n = n + 1;
    }
    i = i + 1;
  }
  return n;
}

/// Human-readable name of a level code: "error", "warning", "note" or
/// "none".
/// Params: level - a SARIF_LEVEL_* code.
/// Returns: the name, or "" for any other value.
/// Error case: none.
/// Complexity: O(1).
pub fn sarif_level_name(level: Int) -> Str {
  return _level_name(level);
}
