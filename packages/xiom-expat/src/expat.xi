// XIOM -- xiom.expat: expat-style XML 1.0 event parser
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// A pure-XIOM, event-based XML 1.0 parser in the spirit of expat: byte-oriented,
// no DTD validation, no namespace resolution beyond recording prefixed names
// and xmlns attribute strings verbatim. See SPEC.md for the exact grammar
// subset, the error catalog and the non-goals.
//
// Supported (documented subset):
//   * encoding: BOM detection (UTF-8 / UTF-16LE / UTF-16BE), XML declaration
//     version/encoding/standalone, byte-oriented UTF-8 default and a declared
//     Latin-1 fallback (ISO-8859-1 / latin1 spellings); UTF-16 BOMs are
//     detected and rejected because XIOM Str cannot carry NUL bytes;
//   * tokenizer events: XML declaration, DOCTYPE (name, optional SYSTEM/PUBLIC
//     ids, internal subset kept raw), comments, processing instructions,
//     CDATA sections, start/end/empty elements with attributes, character
//     data runs (whitespace preserved);
//   * entities: the five predefined ones, decimal/hex character references,
//     internal-subset general entities (literal values, recursive expansion
//     with depth and size caps), unknown entities are errors, references work
//     in text and attribute values;
//   * well-formedness: ASCII name subset (non-ASCII UTF-8 bytes pass through),
//     matching end tags, attribute quoting and whitespace normalization,
//     duplicate attribute detection, bounded open-element depth, single root
//     element, no text before/after the root, '<' in text is markup and a raw
//     "]]>" in text is rejected.
//
// Non-goals: DTD validation, external entity/parameter entity resolution,
// namespace URI resolution, attribute types (CDATA-only normalization),
// document type declarations beyond discovery of internal ENTITY declarations,
// error recovery (the first error aborts), streaming across buffers (the whole
// input is in one Str).
//
// Language notes (XIOM v0.61.3):
//   * free functions only; the event stream is stored as parallel Vec fields
//     (Vec[StructType] is unsupported);
//   * the parser cursor lives in ExpatState (Str field reads + Int locals;
//     `&mut Int` out-parameters miscompile, so every scanner returns its new
//     position through Result[Int, Str] instead);
//   * Ok/Err are constructed only in the leaf helpers _ok_int/_err_int,
//     _ok_str/_err_str and _ok_state/_err_state;
//   * Str values read from Vec[Str] elements are compared with
//     xiom.string.compare.str_compare (BUG 17) and bound to typed locals;
//   * decoded byte buffers are Vec[UInt8] materialized with Str::from_utf8 or
//     xiom.string.builder.sb_to_str; no NUL byte can reach either.

module xiom.expat

use xiom.string;
use xiom.string.builder;
use xiom.string.compare;
use xiom.convert;

// ---------------------------------------------------------------------------
//  Limits and event kinds
// ---------------------------------------------------------------------------

// Maximum open-element depth; deeper documents are rejected.
const _XP_MAX_DEPTH: Int = 256;
// Maximum entity-reference recursion depth (billion-laughs guard).
const _XP_MAX_ENTITY_DEPTH: Int = 16;
// Maximum bytes a single text/attribute run may expand to.
const _XP_MAX_EXPANSION: Int = 65536;
// Maximum relative nesting depth visited by expat_text_content.
const _XP_MAX_TEXT_DEPTH: Int = 1024;

const _XP_EV_DECL: Int = 0;
const _XP_EV_DOCTYPE: Int = 1;
const _XP_EV_COMMENT: Int = 2;
const _XP_EV_PI: Int = 3;
const _XP_EV_CDATA: Int = 4;
const _XP_EV_START: Int = 5;
const _XP_EV_END: Int = 6;
const _XP_EV_TEXT: Int = 7;

// Masked ASCII byte values (Int comparisons keep UInt8 widening in one place).
const _XP_TAB: Int = 9;
const _XP_LF: Int = 10;
const _XP_CR: Int = 13;
const _XP_SPACE: Int = 32;
const _XP_DQUOTE: Int = 34;
const _XP_HASH: Int = 35;
const _XP_AMP: Int = 38;
const _XP_SQUOTE: Int = 39;
const _XP_PERCENT: Int = 37;
const _XP_MINUS: Int = 45;
const _XP_SLASH: Int = 47;
const _XP_COLON: Int = 58;
const _XP_SEMI: Int = 59;
const _XP_LT: Int = 60;
const _XP_EQ: Int = 61;
const _XP_GT: Int = 62;
const _XP_QUESTION: Int = 63;
const _XP_LBRACKET: Int = 91;
const _XP_RBRACKET: Int = 93;
const _XP_UNDERSCORE: Int = 95;
const _XP_LOWER_X: Int = 120;
const _XP_UPPER_X: Int = 88;

// ---------------------------------------------------------------------------
//  Parsed-state container
// ---------------------------------------------------------------------------

/// One parse session: the (optionally re-decoded) XML text, the cursor, the
/// recorded document metadata and the event stream, all as parallel vectors
/// (Vec[StructType] is unsupported in XIOM v0.61.3). Event i is described by:
///   * kinds[i]        -- event kind constant (0..7);
///   * names[i]        -- element name (start/end) or PI target or DOCTYPE
///     name or XML-declaration version, else "";
///   * datas[i]        -- text run / comment body / CDATA body / PI data /
///     XML-declaration encoding label / raw DOCTYPE internal subset, else "";
///   * sids[i], pubids[i] -- DOCTYPE SYSTEM / PUBLIC identifiers, else "";
///   * flags[i]        -- declaration standalone value (-1 absent, 0 no, 1
///     yes), else -1;
///   * ev_offsets[i], ev_lines[i], ev_cols[i] -- byte offset plus 1-based line
///     and column of the byte that starts the event;
///   * ev_consumed[i]  -- document bytes the event consumed (0 for the
///     synthesized end event of an empty element);
///   * ev_attr_starts[i], ev_attr_counts[i] -- the attributes of start event i
///     in attr_names/attr_values (0/0 for other events).
/// The open-element stack and the parsed internal general entities are kept
/// as stack_names/stack_offsets and entities/entity_values.
/// Treat every field as read-only: build states with expat_open/expat_parse
/// and read them through the expat_* accessors.
pub type ExpatState = {
  text: Str;
  pos: Int;
  line: Int;
  col: Int;
  encoding: Str;
  version: Str;
  standalone: Int;
  has_decl: Bool;
  has_doctype: Bool;
  root_seen: Int;
  root_done: Bool;
  kinds: Vec[Int];
  names: Vec[Str];
  datas: Vec[Str];
  sids: Vec[Str];
  pubids: Vec[Str];
  flags: Vec[Int];
  ev_offsets: Vec[Int];
  ev_lines: Vec[Int];
  ev_cols: Vec[Int];
  ev_consumed: Vec[Int];
  ev_attr_starts: Vec[Int];
  ev_attr_counts: Vec[Int];
  attr_names: Vec[Str];
  attr_values: Vec[Str];
  attr_quotes: Vec[Int];
  attr_offsets: Vec[Int];
  stack_names: Vec[Str];
  stack_offsets: Vec[Int];
  entities: Vec[Str];
  entity_values: Vec[Str];
  elem_events: Vec[Int];
  elem_depths: Vec[Int];
}

// ---------------------------------------------------------------------------
//  Result constructors (see the module header)
// ---------------------------------------------------------------------------

// Ok(v) for Result[Int, Str].
fn _ok_int(v: Int) -> Result[Int, Str] {
  return Ok(v);
}

// Err(m) for Result[Int, Str].
fn _err_int(m: Str) -> Result[Int, Str] {
  return Err(m);
}

// Ok(v) for Result[Str, Str].
fn _ok_str(v: Str) -> Result[Str, Str] {
  return Ok(v);
}

// Err(m) for Result[Str, Str].
fn _err_str(m: Str) -> Result[Str, Str] {
  return Err(m);
}

// Ok(v) for Result[ExpatState, Str].
fn _ok_state(v: ExpatState) -> Result[ExpatState, Str] {
  return Ok(v);
}

// Err(m) for Result[ExpatState, Str].
fn _err_state(m: Str) -> Result[ExpatState, Str] {
  return Err(m);
}

// ---------------------------------------------------------------------------
//  Bytes, positions and character predicates
// ---------------------------------------------------------------------------

// Byte at `i` widened and masked to 0..255 (sign-safe for values >= 128).
fn _at(t: Str, i: Int) -> Int {
  return (string.byte_at(t, i) as Int) & 0xFF;
}

// "expat: <text> at <pos>"; the deterministic shape of every error.
fn _err_at(text: Str, pos: Int) -> Str {
  return "expat: " + text + " at " + convert.int_to_string(pos);
}

// XML whitespace byte: space, tab, LF or CR.
fn _is_xml_ws(b: Int) -> Bool {
  return b == _XP_SPACE || b == _XP_TAB || b == _XP_LF || b == _XP_CR;
}

// True when `v` is an XML Char (XML 1.0, 5th ed. production [2]).
fn _is_xml_char(v: Int) -> Bool {
  if v == _XP_TAB || v == _XP_LF || v == _XP_CR {
    return true;
  }
  if v >= 0x20 && v <= 0xD7FF {
    return true;
  }
  if v >= 0xE000 && v <= 0xFFFD {
    return true;
  }
  if v >= 0x10000 && v <= 0x10FFFF {
    return true;
  }
  return false;
}

// NameStartChar subset: ASCII letters, '_' and ':' are checked exactly; every
// byte >= 0x80 passes through (the input is validated UTF-8, so those bytes
// are well-formed sequences; the full Unicode ranges are a documented
// non-goal).
fn _is_name_start_byte(b: Int) -> Bool {
  if b >= 65 && b <= 90 {
    return true;
  }
  if b >= 97 && b <= 122 {
    return true;
  }
  if b == _XP_UNDERSCORE || b == _XP_COLON {
    return true;
  }
  return b >= 0x80;
}

// NameChar addition over NameStartChar: digits, '-', '.' and 0xB7; UTF-8
// bytes >= 0x80 pass through.
fn _is_name_char_byte(b: Int) -> Bool {
  if _is_name_start_byte(b) {
    return true;
  }
  if b >= 48 && b <= 57 {
    return true;
  }
  if b == _XP_MINUS || b == 46 || b == 0xB7 {
    return true;
  }
  return false;
}

// Value of a digit in the given base; -1 when not a digit.
fn _digit_value(b: Int, hex: Bool) -> Int {
  if b >= 48 && b <= 57 {
    return b - 48;
  }
  if !hex {
    return -1;
  }
  if b >= 97 && b <= 102 {
    return b - 87;
  }
  if b >= 65 && b <= 70 {
    return b - 55;
  }
  return -1;
}

// ---------------------------------------------------------------------------
//  UTF-8 and text preparation
// ---------------------------------------------------------------------------

// First offset >= `start` of an ill-formed UTF-8 sequence, a NUL byte, or -1
// when the rest of `text` is well-formed per RFC 3629 (rejects stray
// continuation bytes, truncated sequences, overlong forms, surrogates and
// values above U+10FFFF).
fn _utf8_problem_from(text: Str, start: Int) -> Int {
  let n = text.len();
  var i = start;
  while i < n {
    let b0 = _at(text, i);
    if b0 == 0 {
      return i;
    }
    if b0 < 0x80 {
      i = i + 1;
    } elif b0 >= 0xC2 && b0 <= 0xDF {
      if i + 1 >= n {
        return i;
      }
      let b1 = _at(text, i + 1);
      if b1 < 0x80 || b1 > 0xBF {
        return i;
      }
      i = i + 2;
    } elif b0 >= 0xE0 && b0 <= 0xEF {
      if i + 2 >= n {
        return i;
      }
      let b1 = _at(text, i + 1);
      let b2 = _at(text, i + 2);
      if b1 < 0x80 || b1 > 0xBF {
        return i;
      }
      if b2 < 0x80 || b2 > 0xBF {
        return i;
      }
      if b0 == 0xE0 && b1 < 0xA0 {
        return i;
      }
      if b0 == 0xED && b1 >= 0xA0 {
        return i;
      }
      i = i + 3;
    } elif b0 >= 0xF0 && b0 <= 0xF4 {
      if i + 3 >= n {
        return i;
      }
      let b1 = _at(text, i + 1);
      let b2 = _at(text, i + 2);
      let b3 = _at(text, i + 3);
      if b1 < 0x80 || b1 > 0xBF {
        return i;
      }
      if b2 < 0x80 || b2 > 0xBF {
        return i;
      }
      if b3 < 0x80 || b3 > 0xBF {
        return i;
      }
      if b0 == 0xF0 && b1 < 0x90 {
        return i;
      }
      if b0 == 0xF4 && b1 > 0x8F {
        return i;
      }
      i = i + 4;
    } else {
      return i;
    }
  }
  return -1;
}

// Append the UTF-8 encoding of `code` (a valid XML Char) to `out`.
fn _push_utf8(out: &mut Vec[UInt8], code: Int) {
  if code < 0x80 {
    out.push(code as UInt8);
    return;
  }
  if code < 0x800 {
    out.push((0xC0 + code / 64) as UInt8);
    out.push((0x80 + code % 64) as UInt8);
    return;
  }
  if code < 0x10000 {
    out.push((0xE0 + code / 4096) as UInt8);
    out.push((0x80 + (code / 64) % 64) as UInt8);
    out.push((0x80 + code % 64) as UInt8);
    return;
  }
  out.push((0xF0 + code / 262144) as UInt8);
  out.push((0x80 + (code / 4096) % 64) as UInt8);
  out.push((0x80 + (code / 64) % 64) as UInt8);
  out.push((0x80 + code % 64) as UInt8);
}

// BOM kind: 0 none, 1 UTF-8, 2 UTF-16LE, 3 UTF-16BE.
fn _detect_bom(t: Str) -> Int {
  let n = t.len();
  if n >= 3 && _at(t, 0) == 0xEF && _at(t, 1) == 0xBB && _at(t, 2) == 0xBF {
    return 1;
  }
  if n >= 2 && _at(t, 0) == 0xFF && _at(t, 1) == 0xFE {
    return 2;
  }
  if n >= 2 && _at(t, 0) == 0xFE && _at(t, 1) == 0xFF {
    return 3;
  }
  return 0;
}

// One-byte and two-byte BOM shapes are detected by _detect_bom; UTF-16 input
// is rejected because XIOM Str is NUL-terminated and cannot carry UTF-16 bytes
// (every ASCII code unit contains a NUL byte).

// Re-encode Latin-1 bytes 0x80-0xFF as UTF-8 code points U+0080-U+00FF;
// ASCII passes through and U+0000 is an error.
fn _transcode_latin1(text: Str, start: Int) -> Result[Str, Str] {
  let n = text.len();
  var out = Vec[UInt8].new();
  var i = start;
  while i < n {
    let b = _at(text, i);
    if b == 0 {
      return _err_str(_err_at("NUL byte", i));
    }
    if b < 0x80 {
      out.push(b as UInt8);
    } else {
      _push_utf8(&mut out, b);
    }
    i = i + 1;
  }
  if out.len() == 0 {
    return _ok_str("");
  }
  return _ok_str(Str::from_utf8(out));
}

// ---------------------------------------------------------------------------
//  Scanning primitives (pure: text + position -> new position)
// ---------------------------------------------------------------------------

// Skip XML whitespace from `pos`; returns the first non-whitespace offset.
fn _skip_ws(t: Str, pos: Int) -> Int {
  let n = t.len();
  var i = pos;
  while i < n && _is_xml_ws(_at(t, i)) {
    i = i + 1;
  }
  return i;
}

// True when `lit` occurs at `pos` (bounds-checked byte comparison).
fn _match(t: Str, pos: Int, lit: Str) -> Bool {
  let n = t.len();
  let m = lit.len();
  if pos < 0 || pos + m > n {
    return false;
  }
  var i = 0;
  while i < m {
    if _at(t, pos + i) != _at(lit, i) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// First offset >= `from` where `lit` occurs, or -1.
fn _find(t: Str, from: Int, lit: Str) -> Int {
  let n = t.len();
  let m = lit.len();
  if m == 0 {
    return from;
  }
  var i = from;
  while i + m <= n {
    if _match(t, i, lit) {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// Scan a Name starting at `pos`; Ok(the first offset after the name).
// `what` names the construct in the error message. Errors at `pos`.
fn _scan_name(t: Str, pos: Int, what: Str) -> Result[Int, Str] {
  let n = t.len();
  if pos < 0 || pos >= n {
    return _err_int(_err_at(what, pos));
  }
  if !_is_name_start_byte(_at(t, pos)) {
    return _err_int(_err_at(what, pos));
  }
  var j = pos + 1;
  while j < n && _is_name_char_byte(_at(t, j)) {
    j = j + 1;
  }
  return _ok_int(j);
}

// Scan a quoted literal ("..." or '...') starting at `pos`; Ok(the offset
// after the closing quote). The value is the text between the quotes.
fn _scan_quoted(t: Str, pos: Int, what: Str) -> Result[Int, Str] {
  let n = t.len();
  if pos >= n {
    return _err_int(_err_at(what, pos));
  }
  let q = _at(t, pos);
  if q != _XP_DQUOTE && q != _XP_SQUOTE {
    return _err_int(_err_at(what, pos));
  }
  var i = pos + 1;
  while i < n {
    if _at(t, i) == q {
      return _ok_int(i + 1);
    }
    i = i + 1;
  }
  return _err_int(_err_at(what, pos));
}

// True when the byte buffer holds any non-whitespace byte.
fn _has_non_ws(v: &Vec[UInt8]) -> Bool {
  let n = v.len();
  var i = 0;
  while i < n {
    let b = (v[i] as Int) & 0xFF;
    if b != _XP_SPACE && b != _XP_TAB && b != _XP_LF && b != _XP_CR {
      return true;
    }
    i = i + 1;
  }
  return false;
}

// Reject raw control bytes outside tab/LF/CR in [from, to).
fn _check_raw_chars(t: Str, from: Int, to: Int, what: Str) -> Result[Int, Str] {
  var i = from;
  while i < to {
    let b = _at(t, i);
    if b < 0x20 && b != _XP_TAB && b != _XP_LF && b != _XP_CR {
      return _err_int(_err_at(what, i));
    }
    i = i + 1;
  }
  return _ok_int(0);
}

// ---------------------------------------------------------------------------
//  Name, label and encoding predicates
// ---------------------------------------------------------------------------

// True for a target matching [Xx][Mm][Ll] (the reserved PI target).
fn _is_xml_target(s: Str) -> Bool {
  if s.len() != 3 {
    return false;
  }
  let c0 = _at(s, 0);
  let c1 = _at(s, 1);
  let c2 = _at(s, 2);
  if c0 != _XP_LOWER_X && c0 != _XP_UPPER_X {
    return false;
  }
  if c1 != 109 && c1 != 77 {
    return false;
  }
  if c2 != 108 && c2 != 76 {
    return false;
  }
  return true;
}

// True when `s` is exactly the lower-case target "xml".
fn _is_lower_xml(s: Str) -> Bool {
  if s.len() != 3 {
    return false;
  }
  if _at(s, 0) != _XP_LOWER_X {
    return false;
  }
  if _at(s, 1) != 109 {
    return false;
  }
  return _at(s, 2) == 108;
}

// VersionNum: '1.' followed by one or more ASCII digits.
fn _version_ok(v: Str) -> Bool {
  let n = v.len();
  if n < 3 {
    return false;
  }
  if _at(v, 0) != 49 || _at(v, 1) != 46 {
    return false;
  }
  var i = 2;
  while i < n {
    let b = _at(v, i);
    if b < 48 || b > 57 {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// EncName: [A-Za-z] ([A-Za-z0-9._] | '-')*.
fn _encoding_ok(v: Str) -> Bool {
  let n = v.len();
  if n == 0 {
    return false;
  }
  let f = _at(v, 0);
  if !((f >= 65 && f <= 90) || (f >= 97 && f <= 122)) {
    return false;
  }
  var i = 1;
  while i < n {
    let b = _at(v, i);
    let alpha = (b >= 65 && b <= 90) || (b >= 97 && b <= 122);
    let digit = b >= 48 && b <= 57;
    if !alpha && !digit && b != 46 && b != 95 && b != _XP_MINUS {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// Accepted UTF-8 spellings (case-insensitive).
fn _is_utf8_label(v: Str) -> Bool {
  let low = string.str_lower(v);
  if compare.str_compare(low, "utf-8") == 0 {
    return true;
  }
  return compare.str_compare(low, "utf8") == 0;
}

// Accepted Latin-1 spellings (case-insensitive).
fn _is_latin1_label(v: Str) -> Bool {
  let low = string.str_lower(v);
  if compare.str_compare(low, "iso-8859-1") == 0 {
    return true;
  }
  if compare.str_compare(low, "iso8859-1") == 0 {
    return true;
  }
  if compare.str_compare(low, "latin-1") == 0 {
    return true;
  }
  return compare.str_compare(low, "latin1") == 0;
}

// True when the declared encoding label is one this parser can decode.
fn _encoding_supported(v: Str) -> Bool {
  if _is_utf8_label(v) {
    return true;
  }
  return _is_latin1_label(v);
}

// True when `name` is one of the five predefined entities.
fn _is_predefined_name(name: Str) -> Bool {
  if compare.str_compare(name, "lt") == 0 {
    return true;
  }
  if compare.str_compare(name, "gt") == 0 {
    return true;
  }
  if compare.str_compare(name, "amp") == 0 {
    return true;
  }
  if compare.str_compare(name, "apos") == 0 {
    return true;
  }
  return compare.str_compare(name, "quot") == 0;
}

// Index of `name` in st.entities, or -1. str_compare because BUG 17 lowers
// `==` on Vec[Str] elements to a pointer comparison.
fn _entity_index(st: &ExpatState, name: Str) -> Int {
  var i = 0;
  while i < st.entities.len() {
    let en: Str = st.entities[i];
    if compare.str_compare(en, name) == 0 {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// Best-effort scan for the encoding pseudo-attribute of a leading XML
// declaration, starting at `start`. Returns the raw value or "" when absent or
// malformed (the declaration token reports the real error later).
fn _peek_declared_encoding(t: Str, start: Int) -> Str {
  let n = t.len();
  if !_match(t, start, "<?xml") {
    return "";
  }
  var i = start + 5;
  var guard = 0;
  while i < n && guard < 1024 {
    i = _skip_ws(t, i);
    if _match(t, i, "?>") {
      return "";
    }
    if _match(t, i, "encoding") {
      var p = _skip_ws(t, i + 8);
      if p < n && _at(t, p) == _XP_EQ {
        p = _skip_ws(t, p + 1);
        if p < n && (_at(t, p) == _XP_DQUOTE || _at(t, p) == _XP_SQUOTE) {
          let qr = _scan_quoted(t, p, "bad XML declaration");
          match qr {
            Ok(e) => { return string.str_slice(t, p + 1, e - 1); },
            Err(_) => { return ""; },
          };
        }
      }
      return "";
    }
    i = i + 1;
    guard = guard + 1;
  }
  return "";
}

// Effective encoding label: BOM first, then a declared label, else UTF-8.
fn _effective_encoding_label(t: Str) -> Str {
  let bom = _detect_bom(t);
  if bom == 2 {
    return "UTF-16LE";
  }
  if bom == 3 {
    return "UTF-16BE";
  }
  var start = 0;
  if bom == 1 {
    start = 3;
  }
  let enc = _peek_declared_encoding(t, start);
  if enc.len() > 0 {
    return enc;
  }
  return "UTF-8";
}

// One-byte and two-byte BOM shapes are detected by _detect_bom; UTF-16 input
// is rejected because XIOM Str is NUL-terminated and cannot carry UTF-16 bytes
// (every ASCII code unit contains a NUL byte).

// Decode the input to the working UTF-8 text: BOM handling, UTF-16 rejection,
// declared Latin-1 fallback, and strict UTF-8 validation otherwise.
fn _prepare_text(text: Str) -> Result[Str, Str] {
  let bom = _detect_bom(text);
  if bom == 2 {
    return _err_str(_err_at("UTF-16LE input unsupported", 0));
  }
  if bom == 3 {
    return _err_str(_err_at("UTF-16BE input unsupported", 0));
  }
  var start = 0;
  if bom == 1 {
    start = 3;
  }
  let enc = _peek_declared_encoding(text, start);
  if enc.len() > 0 && _is_latin1_label(enc) {
    return _transcode_latin1(text, start);
  }
  if enc.len() > 0 && !_is_utf8_label(enc) {
    var epos = _find(text, start, "encoding");
    if epos < 0 {
      epos = start;
    }
    return _err_str(_err_at("unsupported encoding", epos));
  }
  let bad = _utf8_problem_from(text, start);
  if bad >= 0 {
    if _at(text, bad) == 0 {
      return _err_str(_err_at("NUL byte", bad));
    }
    return _err_str(_err_at("invalid UTF-8 byte", bad));
  }
  return _ok_str(string.str_slice(text, start, text.len()));
}

// ---------------------------------------------------------------------------
//  Cursor, event emission
// ---------------------------------------------------------------------------

// Advance the cursor to `target` (>= st.pos), maintaining 1-based line and
// column counters. CR, LF and CRLF each count as one line end; columns count
// code points (continuation bytes do not advance the column).
fn _advance_to(st: &mut ExpatState, target: Int) {
  let t: Str = st.text;
  var i = st.pos;
  var l = st.line;
  var c = st.col;
  while i < target {
    let b = _at(t, i);
    if b == _XP_CR {
      l = l + 1;
      c = 1;
      if i + 1 < target && _at(t, i + 1) == _XP_LF {
        i = i + 1;
      }
    } elif b == _XP_LF {
      l = l + 1;
      c = 1;
    } elif b < 0x80 || b >= 0xC0 {
      c = c + 1;
    }
    i = i + 1;
  }
  st.pos = target;
  st.line = l;
  st.col = c;
}

// Append one event; every parallel event vector is pushed here so they can
// never drift out of sync. `depth` is the element depth for start events
// (ignored otherwise).
fn _emit_event(st: &mut ExpatState, kind: Int, name: Str, data: Str, sid: Str, pubid: Str, flag: Int, off: Int, line: Int, col: Int, consumed: Int, attr_start: Int, attr_count: Int, depth: Int) {
  let ev = st.kinds.len();
  st.kinds.push(kind);
  st.names.push(name);
  st.datas.push(data);
  st.sids.push(sid);
  st.pubids.push(pubid);
  st.flags.push(flag);
  st.ev_offsets.push(off);
  st.ev_lines.push(line);
  st.ev_cols.push(col);
  st.ev_consumed.push(consumed);
  st.ev_attr_starts.push(attr_start);
  st.ev_attr_counts.push(attr_count);
  if kind == _XP_EV_START {
    st.elem_events.push(ev);
    st.elem_depths.push(depth);
  }
}

// Number of currently open elements.
fn _depth_of(st: &ExpatState) -> Int {
  return st.stack_names.len();
}

// ---------------------------------------------------------------------------
//  References and content scanning
// ---------------------------------------------------------------------------

// Parse one reference at the '&' at `pos` and append its expansion to `out`.
// Ok(the offset after the terminating ';'). `origin` is the document offset
// reported by every error (the outer '&' when expanding nested entities);
// `depth` bounds entity recursion; a reference processed directly by a
// scanner starts at depth 1.
fn _scan_ref(st: &ExpatState, t: Str, pos: Int, origin: Int, out: &mut Vec[UInt8], depth: Int) -> Result[Int, Str] {
  let n = t.len();
  if depth >= _XP_MAX_ENTITY_DEPTH {
    return _err_int(_err_at("entity nesting too deep", origin));
  }
  var i = pos + 1;
  if i >= n {
    return _err_int(_err_at("malformed entity reference", origin));
  }
  if _at(t, i) == _XP_HASH {
    i = i + 1;
    var hex = false;
    if i < n && (_at(t, i) == _XP_LOWER_X || _at(t, i) == _XP_UPPER_X) {
      hex = true;
      i = i + 1;
    }
    var code = 0;
    var digits = 0;
    while i < n {
      let hv = _digit_value(_at(t, i), hex);
      if hv < 0 {
        break;
      }
      if hex {
        code = code * 16 + hv;
      } else {
        code = code * 10 + hv;
      }
      digits = digits + 1;
      if digits > 8 {
        return _err_int(_err_at("bad character reference", origin));
      }
      i = i + 1;
    }
    if digits == 0 {
      return _err_int(_err_at("bad character reference", origin));
    }
    if i >= n || _at(t, i) != _XP_SEMI {
      return _err_int(_err_at("bad character reference", origin));
    }
    if !_is_xml_char(code) {
      return _err_int(_err_at("bad character reference", origin));
    }
    _push_utf8(out, code);
    return _ok_int(i + 1);
  }
  let nr = _scan_name(t, i, "malformed entity reference");
  var ne = 0;
  match nr {
    Ok(v) => { ne = v; },
    Err(_) => { return _err_int(_err_at("malformed entity reference", origin)); },
  };
  if ne >= n || _at(t, ne) != _XP_SEMI {
    return _err_int(_err_at("malformed entity reference", origin));
  }
  let name = string.str_slice(t, i, ne);
  let endp = ne + 1;
  if compare.str_compare(name, "lt") == 0 {
    out.push(60 as UInt8);
    return _ok_int(endp);
  }
  if compare.str_compare(name, "gt") == 0 {
    out.push(62 as UInt8);
    return _ok_int(endp);
  }
  if compare.str_compare(name, "amp") == 0 {
    out.push(38 as UInt8);
    return _ok_int(endp);
  }
  if compare.str_compare(name, "apos") == 0 {
    out.push(39 as UInt8);
    return _ok_int(endp);
  }
  if compare.str_compare(name, "quot") == 0 {
    out.push(34 as UInt8);
    return _ok_int(endp);
  }
  let ei = _entity_index(st, name);
  if ei < 0 {
    return _err_int(_err_at("unknown entity", origin));
  }
  let val: Str = st.entity_values[ei];
  let vr = _append_entity_value(st, val, origin, out, depth + 1);
  match vr {
    Ok(_) => {},
    Err(e) => { return _err_int(e); },
  };
  return _ok_int(endp);
}

// Expand the literal value of an internal entity into `out`; references inside
// the value expand recursively. `origin` is the document offset of the outer
// reference (used by errors).
fn _append_entity_value(st: &ExpatState, val: Str, origin: Int, out: &mut Vec[UInt8], depth: Int) -> Result[Int, Str] {
  let n = val.len();
  var i = 0;
  while i < n {
    let b = _at(val, i);
    if b == _XP_AMP {
      let r = _scan_ref(st, val, i, origin, out, depth);
      match r {
        Ok(e) => { i = e; },
        Err(er) => { return _err_int(er); },
      };
    } elif b == _XP_PERCENT {
      return _err_int(_err_at("parameter entity not supported", origin));
    } elif b < 0x20 && b != _XP_TAB && b != _XP_LF && b != _XP_CR {
      return _err_int(_err_at("control character", origin));
    } else {
      out.push(b as UInt8);
      i = i + 1;
    }
    if out.len() > _XP_MAX_EXPANSION {
      return _err_int(_err_at("entity expansion too large", origin));
    }
  }
  return _ok_int(i);
}

// Scan a quoted attribute value starting at the opening quote at `pos` and
// append the normalized value (tab/LF/CR become space; references expand; a
// raw '<' is rejected). Ok(the offset after the closing quote).
fn _scan_attr_value(st: &ExpatState, t: Str, pos: Int, out: &mut Vec[UInt8]) -> Result[Int, Str] {
  let open = pos;
  let n = t.len();
  let q = _at(t, pos);
  var i = pos + 1;
  while i < n {
    let b = _at(t, i);
    if b == q {
      return _ok_int(i + 1);
    }
    if b == _XP_LT {
      return _err_int(_err_at("'<' in attribute value", i));
    }
    if b == _XP_AMP {
      let r = _scan_ref(st, t, i, i, out, 1);
      match r {
        Ok(e) => { i = e; },
        Err(er) => { return _err_int(er); },
      };
    } elif b == _XP_TAB || b == _XP_LF || b == _XP_CR {
      out.push(32 as UInt8);
      i = i + 1;
    } elif b < 0x20 {
      return _err_int(_err_at("control character", i));
    } else {
      out.push(b as UInt8);
      i = i + 1;
    }
    if out.len() > _XP_MAX_EXPANSION {
      return _err_int(_err_at("entity expansion too large", open));
    }
  }
  return _err_int(_err_at("unterminated attribute value", open));
}

// Scan a character-data run from `pos` to the next '<' (or end of input) and
// append its decoded text to `out`. References expand; a raw "]]>" sequence
// and raw control bytes outside tab/LF/CR are rejected. Ok(end offset).
fn _scan_text(st: &ExpatState, t: Str, pos: Int, out: &mut Vec[UInt8]) -> Result[Int, Str] {
  let start = pos;
  let n = t.len();
  var i = pos;
  while i < n {
    let b = _at(t, i);
    if b == _XP_LT {
      break;
    }
    if b == _XP_AMP {
      let r = _scan_ref(st, t, i, i, out, 1);
      match r {
        Ok(e) => { i = e; },
        Err(er) => { return _err_int(er); },
      };
    } elif b == _XP_GT {
      if i >= 2 && _at(t, i - 1) == _XP_RBRACKET && _at(t, i - 2) == _XP_RBRACKET {
        return _err_int(_err_at("']]>' in text", i));
      }
      out.push(62 as UInt8);
      i = i + 1;
    } elif b < 0x20 && b != _XP_TAB && b != _XP_LF && b != _XP_CR {
      return _err_int(_err_at("control character", i));
    } else {
      out.push(b as UInt8);
      i = i + 1;
    }
    if out.len() > _XP_MAX_EXPANSION {
      return _err_int(_err_at("entity expansion too large", start));
    }
  }
  return _ok_int(i);
}

// Scan a DOCTYPE internal subset at the '[' at `pos`, tracking bracket
// balance and skipping quoted literals and comments. Ok(the offset after the
// matching ']').
fn _scan_subset(t: Str, pos: Int) -> Result[Int, Str] {
  let n = t.len();
  var depth = 1;
  var i = pos + 1;
  while i < n {
    let b = _at(t, i);
    if b == _XP_LBRACKET {
      depth = depth + 1;
      i = i + 1;
    } elif b == _XP_RBRACKET {
      depth = depth - 1;
      i = i + 1;
      if depth == 0 {
        return _ok_int(i);
      }
    } elif b == _XP_DQUOTE || b == _XP_SQUOTE {
      let qr = _scan_quoted(t, i, "unterminated DOCTYPE");
      match qr {
        Ok(e) => { i = e; },
        Err(er) => { return _err_int(er); },
      };
    } elif _match(t, i, "<!--") {
      let fe = _find(t, i + 4, "-->");
      if fe < 0 {
        return _err_int(_err_at("unterminated DOCTYPE", pos));
      }
      i = fe + 3;
    } else {
      i = i + 1;
    }
  }
  return _err_int(_err_at("unterminated DOCTYPE", pos));
}

// Discover `<!ENTITY name "value">` declarations in a raw internal subset.
// Other declarations, comments and quoted literals are skipped without
// validation. `base` is the absolute offset of `subset` in the document, so
// errors carry document offsets. Parameter entities and redefinitions of the
// predefined entities are rejected.
fn _parse_entity_decls(st: &mut ExpatState, subset: Str, base: Int) -> Result[Int, Str] {
  let n = subset.len();
  var i = 0;
  while i < n {
    let b = _at(subset, i);
    if b == _XP_DQUOTE || b == _XP_SQUOTE {
      let qr = _scan_quoted(subset, i, "unterminated entity literal");
      match qr {
        Ok(e) => { i = e; },
        Err(er) => { return _err_int(er); },
      };
    } elif _match(subset, i, "<!--") {
      let fe = _find(subset, i + 4, "-->");
      if fe < 0 {
        return _err_int(_err_at("unterminated comment", base + i));
      }
      i = fe + 3;
    } elif _match(subset, i, "<!ENTITY") {
      var p = i + 8;
      if p >= n || !_is_xml_ws(_at(subset, p)) {
        i = i + 1;
      } else {
        p = _skip_ws(subset, p);
        if p >= n {
          return _err_int(_err_at("unterminated entity declaration", base + p));
        }
        if _at(subset, p) == _XP_PERCENT {
          return _err_int(_err_at("parameter entity not supported", base + p));
        }
        let nr = _scan_name(subset, p, "invalid entity name");
        var ne = 0;
        match nr {
          Ok(v) => { ne = v; },
          Err(er) => { return _err_int(er); },
        };
        let ename = string.str_slice(subset, p, ne);
        var p2 = _skip_ws(subset, ne);
        if p2 >= n {
          return _err_int(_err_at("unterminated entity declaration", base + p2));
        }
        let q = _at(subset, p2);
        if q != _XP_DQUOTE && q != _XP_SQUOTE {
          return _err_int(_err_at("unterminated entity declaration", base + p2));
        }
        let qr2 = _scan_quoted(subset, p2, "unterminated entity literal");
        var qe = 0;
        match qr2 {
          Ok(v) => { qe = v; },
          Err(er) => { return _err_int(er); },
        };
        let ev = string.str_slice(subset, p2 + 1, qe - 1);
        var p3 = _skip_ws(subset, qe);
        if p3 >= n || _at(subset, p3) != _XP_GT {
          return _err_int(_err_at("unterminated entity declaration", base + p3));
        }
        if _is_predefined_name(ename) {
          return _err_int(_err_at("reserved entity redeclared", base + p));
        }
        if _entity_index(st, ename) >= 0 {
          return _err_int(_err_at("duplicate entity", base + p));
        }
        st.entities.push(ename);
        st.entity_values.push(ev);
        i = p3 + 1;
      }
    } else {
      i = i + 1;
    }
  }
  return _ok_int(0);
}

// ---------------------------------------------------------------------------
//  Token handlers (each emits one event, except an empty element which emits
//  a start event and a synthesized end event)
// ---------------------------------------------------------------------------

// Character data: everything up to the next '<'. Whitespace is preserved;
// non-whitespace text is only allowed inside the root element.
fn _token_text(st: &mut ExpatState, off: Int, ev_line: Int, ev_col: Int) -> Result[Int, Str] {
  let t: Str = st.text;
  var out = Vec[UInt8].new();
  let tr = _scan_text(st, t, off, &mut out);
  var endp = 0;
  match tr {
    Ok(v) => { endp = v; },
    Err(e) => { return _err_int(e); },
  };
  if _has_non_ws(&out) && st.stack_names.len() == 0 {
    if st.root_seen == 0 {
      return _err_int(_err_at("text before root element", off));
    }
    if st.root_done {
      return _err_int(_err_at("junk after root element", off));
    }
  }
  let body = Str::from_utf8(out);
  _advance_to(st, endp);
  _emit_event(st, _XP_EV_TEXT, "", body, "", "", -1, off, ev_line, ev_col, endp - off, 0, 0, -1);
  return _ok_int(_XP_EV_TEXT);
}

// Comment: `<!--` body `-->`; a `--` inside the body is rejected.
fn _token_comment(st: &mut ExpatState, off: Int, ev_line: Int, ev_col: Int) -> Result[Int, Str] {
  let t: Str = st.text;
  let n = t.len();
  var i = off + 4;
  var body_end = -1;
  while i + 2 < n {
    if _at(t, i) == _XP_MINUS && _at(t, i + 1) == _XP_MINUS {
      if _at(t, i + 2) == _XP_GT {
        body_end = i;
        i = i + 3;
        break;
      }
      return _err_int(_err_at("double dash in comment", i));
    }
    i = i + 1;
  }
  if body_end < 0 {
    return _err_int(_err_at("unterminated comment", off));
  }
  let cr = _check_raw_chars(t, off + 4, body_end, "control character");
  match cr {
    Ok(_) => {},
    Err(e) => { return _err_int(e); },
  };
  let body = string.str_slice(t, off + 4, body_end);
  _advance_to(st, i);
  _emit_event(st, _XP_EV_COMMENT, "", body, "", "", -1, off, ev_line, ev_col, i - off, 0, 0, -1);
  return _ok_int(_XP_EV_COMMENT);
}

// CDATA section `<![CDATA[ body ]]>`; the body is taken verbatim and is only
// allowed inside the root element.
fn _token_cdata(st: &mut ExpatState, off: Int, ev_line: Int, ev_col: Int) -> Result[Int, Str] {
  if st.stack_names.len() == 0 {
    return _err_int(_err_at("CDATA outside root element", off));
  }
  let t: Str = st.text;
  let body_start = off + 9;
  let fe = _find(t, body_start, "]]>");
  if fe < 0 {
    return _err_int(_err_at("unterminated CDATA", off));
  }
  let cr = _check_raw_chars(t, body_start, fe, "control character");
  match cr {
    Ok(_) => {},
    Err(e) => { return _err_int(e); },
  };
  let body = string.str_slice(t, body_start, fe);
  let endp = fe + 3;
  _advance_to(st, endp);
  _emit_event(st, _XP_EV_CDATA, "", body, "", "", -1, off, ev_line, ev_col, endp - off, 0, 0, -1);
  return _ok_int(_XP_EV_CDATA);
}

// Processing instruction `<?target data?>`; the reserved target `xml` in any
// case is only accepted as the XML declaration at offset 0.
fn _token_pi_or_decl(st: &mut ExpatState, off: Int, ev_line: Int, ev_col: Int) -> Result[Int, Str] {
  let t: Str = st.text;
  let n = t.len();
  let nr = _scan_name(t, off + 2, "invalid PI target");
  var ne = 0;
  match nr {
    Ok(v) => { ne = v; },
    Err(e) => { return _err_int(e); },
  };
  let target = string.str_slice(t, off + 2, ne);
  if _is_lower_xml(target) {
    if off == 0 {
      return _token_decl(st, off, ne, ev_line, ev_col);
    }
    return _err_int(_err_at("reserved PI target", off));
  }
  if _is_xml_target(target) {
    return _err_int(_err_at("reserved PI target", off));
  }
  var pos = ne;
  if pos < n && _is_xml_ws(_at(t, pos)) {
    pos = _skip_ws(t, pos);
  }
  let fe = _find(t, pos, "?>");
  if fe < 0 {
    return _err_int(_err_at("unterminated PI", off));
  }
  let cr = _check_raw_chars(t, pos, fe, "control character");
  match cr {
    Ok(_) => {},
    Err(e) => { return _err_int(e); },
  };
  let data = string.str_slice(t, pos, fe);
  let endp = fe + 2;
  _advance_to(st, endp);
  _emit_event(st, _XP_EV_PI, target, data, "", "", -1, off, ev_line, ev_col, endp - off, 0, 0, -1);
  return _ok_int(_XP_EV_PI);
}

// XML declaration `<?xml version="1.0" encoding="..."? standalone="..."? ?>`.
// Pseudo-attributes must appear in that order; version is mandatory; the
// encoding label must be one this parser decodes.
fn _token_decl(st: &mut ExpatState, off: Int, name_end: Int, ev_line: Int, ev_col: Int) -> Result[Int, Str] {
  let t: Str = st.text;
  let n = t.len();
  if st.has_decl {
    return _err_int(_err_at("duplicate XML declaration", off));
  }
  var pos = name_end;
  if pos >= n || !_is_xml_ws(_at(t, pos)) {
    return _err_int(_err_at("bad XML declaration", pos));
  }
  var version = "";
  var enc = "";
  var standalone = -1;
  var step = 0;
  var closed = false;
  while pos < n {
    pos = _skip_ws(t, pos);
    if pos >= n {
      break;
    }
    if _at(t, pos) == _XP_QUESTION {
      if pos + 1 < n && _at(t, pos + 1) == _XP_GT {
        pos = pos + 2;
        closed = true;
      }
      break;
    }
    let pnr = _scan_name(t, pos, "bad XML declaration");
    var ne = 0;
    match pnr {
      Ok(v) => { ne = v; },
      Err(e) => { return _err_int(e); },
    };
    let pname = string.str_slice(t, pos, ne);
    var p2 = _skip_ws(t, ne);
    if p2 >= n || _at(t, p2) != _XP_EQ {
      return _err_int(_err_at("bad XML declaration", p2));
    }
    p2 = _skip_ws(t, p2 + 1);
    if p2 >= n {
      return _err_int(_err_at("bad XML declaration", p2));
    }
    let q = _at(t, p2);
    if q != _XP_DQUOTE && q != _XP_SQUOTE {
      return _err_int(_err_at("bad XML declaration", p2));
    }
    let qr = _scan_quoted(t, p2, "bad XML declaration");
    var qe = 0;
    match qr {
      Ok(v) => { qe = v; },
      Err(e) => { return _err_int(e); },
    };
    let pval = string.str_slice(t, p2 + 1, qe - 1);
    pos = qe;
    if compare.str_compare(pname, "version") == 0 {
      if step != 0 {
        return _err_int(_err_at("bad XML declaration", p2));
      }
      if !_version_ok(pval) {
        return _err_int(_err_at("bad XML declaration", p2));
      }
      version = pval;
      step = 1;
    } elif compare.str_compare(pname, "encoding") == 0 {
      if step != 1 {
        return _err_int(_err_at("bad XML declaration", p2));
      }
      if !_encoding_ok(pval) {
        return _err_int(_err_at("bad XML declaration", p2));
      }
      if !_encoding_supported(pval) {
        return _err_int(_err_at("unsupported encoding", p2));
      }
      enc = pval;
      step = 2;
    } elif compare.str_compare(pname, "standalone") == 0 {
      if step < 1 || step > 2 {
        return _err_int(_err_at("bad XML declaration", p2));
      }
      if compare.str_compare(pval, "yes") == 0 {
        standalone = 1;
      } elif compare.str_compare(pval, "no") == 0 {
        standalone = 0;
      } else {
        return _err_int(_err_at("bad XML declaration", p2));
      }
      step = 3;
    } else {
      return _err_int(_err_at("bad XML declaration", p2));
    }
  }
  if !closed {
    return _err_int(_err_at("unterminated XML declaration", off));
  }
  if step == 0 {
    return _err_int(_err_at("bad XML declaration", off));
  }
  st.version = version;
  st.standalone = standalone;
  st.has_decl = true;
  let cur: Str = st.encoding;
  if enc.len() > 0 && compare.str_compare(cur, "UTF-8") == 0 {
    st.encoding = enc;
  }
  _advance_to(st, pos);
  _emit_event(st, _XP_EV_DECL, version, enc, "", "", standalone, off, ev_line, ev_col, pos - off, 0, 0, -1);
  return _ok_int(_XP_EV_DECL);
}

// DOCTYPE `<!DOCTYPE name (SYSTEM|PUBLIC ...)? ( [ subset ] )? >`. Exactly one
// per document, before the root element. `<!ENTITY ...>` declarations found in
// the internal subset are recorded; the subset itself is kept raw.
fn _token_doctype(st: &mut ExpatState, off: Int, ev_line: Int, ev_col: Int) -> Result[Int, Str] {
  let t: Str = st.text;
  let n = t.len();
  if st.root_seen > 0 {
    return _err_int(_err_at("DOCTYPE after root element", off));
  }
  if st.has_doctype {
    return _err_int(_err_at("duplicate DOCTYPE", off));
  }
  var pos = off + 9;
  if pos >= n || !_is_xml_ws(_at(t, pos)) {
    return _err_int(_err_at("bad DOCTYPE", pos));
  }
  pos = _skip_ws(t, pos);
  let nr = _scan_name(t, pos, "invalid DOCTYPE name");
  var ne = 0;
  match nr {
    Ok(v) => { ne = v; },
    Err(e) => { return _err_int(e); },
  };
  let dname = string.str_slice(t, pos, ne);
  var p = _skip_ws(t, ne);
  var sid = "";
  var pubid = "";
  if _match(t, p, "SYSTEM") {
    p = _skip_ws(t, p + 6);
    let qr = _scan_quoted(t, p, "unterminated DOCTYPE literal");
    var qe = 0;
    match qr {
      Ok(v) => { qe = v; },
      Err(e) => { return _err_int(e); },
    };
    sid = string.str_slice(t, p + 1, qe - 1);
    p = qe;
  } elif _match(t, p, "PUBLIC") {
    p = _skip_ws(t, p + 6);
    let qr2 = _scan_quoted(t, p, "unterminated DOCTYPE literal");
    var qe2 = 0;
    match qr2 {
      Ok(v) => { qe2 = v; },
      Err(e) => { return _err_int(e); },
    };
    pubid = string.str_slice(t, p + 1, qe2 - 1);
    p = _skip_ws(t, qe2);
    let qr3 = _scan_quoted(t, p, "unterminated DOCTYPE literal");
    var qe3 = 0;
    match qr3 {
      Ok(v) => { qe3 = v; },
      Err(e) => { return _err_int(e); },
    };
    sid = string.str_slice(t, p + 1, qe3 - 1);
    p = qe3;
  }
  p = _skip_ws(t, p);
  var subset = "";
  if p < n && _at(t, p) == _XP_LBRACKET {
    let sr = _scan_subset(t, p);
    var se = 0;
    match sr {
      Ok(v) => { se = v; },
      Err(e) => { return _err_int(e); },
    };
    subset = string.str_slice(t, p + 1, se - 1);
    let er = _parse_entity_decls(st, subset, p + 1);
    match er {
      Ok(_) => {},
      Err(e) => { return _err_int(e); },
    };
    p = se;
  }
  p = _skip_ws(t, p);
  if p >= n || _at(t, p) != _XP_GT {
    return _err_int(_err_at("unterminated DOCTYPE", off));
  }
  p = p + 1;
  st.has_doctype = true;
  _advance_to(st, p);
  _emit_event(st, _XP_EV_DOCTYPE, dname, subset, sid, pubid, -1, off, ev_line, ev_col, p - off, 0, 0, -1);
  return _ok_int(_XP_EV_DOCTYPE);
}

// True when `name` already appears among the attributes at indices >= `from`
// (the attributes of the element currently being parsed).
fn _attr_dup(st: &ExpatState, from: Int, name: Str) -> Bool {
  var i = from;
  while i < st.attr_names.len() {
    let an: Str = st.attr_names[i];
    if compare.str_compare(an, name) == 0 {
      return true;
    }
    i = i + 1;
  }
  return false;
}

// Start tag `<name attr="value" ...>` or the empty-element form `<name/>`.
// Attributes keep their source order; empty elements emit a start event and a
// synthesized end event (offset of the start tag, consumed 0).
fn _token_start(st: &mut ExpatState, off: Int, ev_line: Int, ev_col: Int) -> Result[Int, Str] {
  let t: Str = st.text;
  let n = t.len();
  if st.stack_names.len() >= _XP_MAX_DEPTH {
    return _err_int(_err_at("element nesting too deep", off));
  }
  if st.stack_names.len() == 0 && st.root_seen >= 1 {
    return _err_int(_err_at("multiple root elements", off));
  }
  let nr = _scan_name(t, off + 1, "invalid element name");
  var ne = 0;
  match nr {
    Ok(v) => { ne = v; },
    Err(e) => { return _err_int(e); },
  };
  let name = string.str_slice(t, off + 1, ne);
  var p = ne;
  let attr_start = st.attr_names.len();
  var empty = false;
  var first = true;
  loop {
    let before = p;
    p = _skip_ws(t, p);
    if p >= n {
      return _err_int(_err_at("unterminated start tag", off));
    }
    let b = _at(t, p);
    if b == _XP_GT {
      p = p + 1;
      break;
    }
    if b == _XP_SLASH {
      if p + 1 < n && _at(t, p + 1) == _XP_GT {
        empty = true;
        p = p + 2;
        break;
      }
      return _err_int(_err_at("unterminated start tag", p));
    }
    if !first && p == before {
      return _err_int(_err_at("missing whitespace between attributes", p));
    }
    first = false;
    let anr = _scan_name(t, p, "invalid attribute name");
    var ane = 0;
    match anr {
      Ok(v) => { ane = v; },
      Err(e) => { return _err_int(e); },
    };
    let aname = string.str_slice(t, p, ane);
    if _attr_dup(st, attr_start, aname) {
      return _err_int(_err_at("duplicate attribute", p));
    }
    var p2 = _skip_ws(t, ane);
    if p2 >= n || _at(t, p2) != _XP_EQ {
      return _err_int(_err_at("missing '=' in attribute", p2));
    }
    p2 = _skip_ws(t, p2 + 1);
    if p2 >= n {
      return _err_int(_err_at("unterminated attribute value", p2));
    }
    let q = _at(t, p2);
    if q != _XP_DQUOTE && q != _XP_SQUOTE {
      return _err_int(_err_at("unterminated attribute value", p2));
    }
    var vbuf = Vec[UInt8].new();
    let vr = _scan_attr_value(st, t, p2, &mut vbuf);
    var ve = 0;
    match vr {
      Ok(v) => { ve = v; },
      Err(e) => { return _err_int(e); },
    };
    let aval = Str::from_utf8(vbuf);
    var qflag = 0;
    if q == _XP_SQUOTE {
      qflag = 1;
    }
    st.attr_names.push(aname);
    st.attr_values.push(aval);
    st.attr_quotes.push(qflag);
    st.attr_offsets.push(p);
    p = ve;
  }
  let attr_count = st.attr_names.len() - attr_start;
  let depth_before = st.stack_names.len();
  st.stack_names.push(name);
  st.stack_offsets.push(off);
  if depth_before == 0 {
    st.root_seen = 1;
  }
  _advance_to(st, p);
  _emit_event(st, _XP_EV_START, name, "", "", "", -1, off, ev_line, ev_col, p - off, attr_start, attr_count, depth_before);
  if empty {
    st.stack_names.pop();
    st.stack_offsets.pop();
    if st.stack_names.len() == 0 {
      st.root_done = true;
    }
    _emit_event(st, _XP_EV_END, name, "", "", "", -1, off, ev_line, ev_col, 0, 0, 0, -1);
  }
  return _ok_int(_XP_EV_START);
}

// End tag `</name>`; the name must equal the innermost open element.
fn _token_end(st: &mut ExpatState, off: Int, ev_line: Int, ev_col: Int) -> Result[Int, Str] {
  let t: Str = st.text;
  let n = t.len();
  let nr = _scan_name(t, off + 2, "invalid end tag name");
  var ne = 0;
  match nr {
    Ok(v) => { ne = v; },
    Err(e) => { return _err_int(e); },
  };
  let name = string.str_slice(t, off + 2, ne);
  var p = _skip_ws(t, ne);
  if p >= n || _at(t, p) != _XP_GT {
    return _err_int(_err_at("unterminated end tag", off));
  }
  p = p + 1;
  if st.stack_names.len() == 0 {
    return _err_int(_err_at("unexpected end tag", off));
  }
  let top: Str = st.stack_names[st.stack_names.len() - 1];
  if compare.str_compare(top, name) != 0 {
    return _err_int(_err_at("mismatched end tag", off));
  }
  st.stack_names.pop();
  st.stack_offsets.pop();
  if st.stack_names.len() == 0 {
    st.root_done = true;
  }
  _advance_to(st, p);
  _emit_event(st, _XP_EV_END, name, "", "", "", -1, off, ev_line, ev_col, p - off, 0, 0, -1);
  return _ok_int(_XP_EV_END);
}

// ---------------------------------------------------------------------------
//  Public API: open, parse, next event
// ---------------------------------------------------------------------------

/// Open a parse session over `text` without consuming any event. Applies BOM
/// handling, the declared Latin-1 fallback and strict UTF-8 validation; the
/// state cursor sits at offset 0 of the decoded text (so offsets in a Latin-1
/// document refer to the decoded UTF-8 text, not to the original bytes).
/// UTF-16LE/UTF-16BE BOMs are detected and rejected: XIOM Str is NUL-free, so
/// a UTF-16 document (whose ASCII code units contain NUL bytes) cannot survive
/// in a Str in the first place.
/// Params: text - the whole document as bytes in a Str.
/// Returns: Ok(ExpatState) with an empty event list; Err("expat: ...") when
/// the encoding is unsupported, the input is malformed UTF-8/UTF-16 or the
/// document declares an encoding this parser cannot decode. Element and
/// well-formedness checks happen while events are consumed.
/// Error case: encoding-level errors only.
/// Complexity: O(input length).
pub fn expat_open(text: Str) -> Result[ExpatState, Str] {
  let enc = _effective_encoding_label(text);
  let pr = _prepare_text(text);
  var t = "";
  match pr {
    Ok(v) => { t = v; },
    Err(e) => { return _err_state(e); },
  };
  var st = ExpatState{
    text: t;
    pos: 0;
    line: 1;
    col: 1;
    encoding: enc;
    version: "";
    standalone: -1;
    has_decl: false;
    has_doctype: false;
    root_seen: 0;
    root_done: false;
    kinds: Vec[Int].new();
    names: Vec[Str].new();
    datas: Vec[Str].new();
    sids: Vec[Str].new();
    pubids: Vec[Str].new();
    flags: Vec[Int].new();
    ev_offsets: Vec[Int].new();
    ev_lines: Vec[Int].new();
    ev_cols: Vec[Int].new();
    ev_consumed: Vec[Int].new();
    ev_attr_starts: Vec[Int].new();
    ev_attr_counts: Vec[Int].new();
    attr_names: Vec[Str].new();
    attr_values: Vec[Str].new();
    attr_quotes: Vec[Int].new();
    attr_offsets: Vec[Int].new();
    stack_names: Vec[Str].new();
    stack_offsets: Vec[Int].new();
    entities: Vec[Str].new();
    entity_values: Vec[Str].new();
    elem_events: Vec[Int].new();
    elem_depths: Vec[Int].new();
  };
  return _ok_state(st);
}

// Final document checks after the last event: the open stack must be empty
// and exactly one root element must have started.
fn _check_finish(st: &ExpatState) -> Result[Int, Str] {
  if st.stack_names.len() > 0 {
    let p: Int = st.stack_offsets[0];
    return _err_int(_err_at("unclosed element", p));
  }
  if st.root_seen == 0 {
    return _err_int(_err_at("no root element", st.text.len()));
  }
  return _ok_int(0);
}

/// Parse a whole XML document into an event stream.
/// Params: text - the whole document (see expat_open for encoding rules).
/// Returns: Ok(ExpatState) with every event recorded in document order;
/// Err("expat: ...") for the first well-formedness error, with a 0-based byte
/// offset into the decoded text (see SPEC.md for the catalog). Every event
/// carries its own offset/line/column in ev_offsets/ev_lines/ev_cols.
/// Error case: any error from expat_next_event plus the end-of-document
/// checks (unclosed element, no root element).
/// Complexity: O(input length).
pub fn expat_parse(text: Str) -> Result[ExpatState, Str] {
  let or_ = expat_open(text);
  match or_ {
    Ok(st) => {
      var s = st;
      loop {
        let r = expat_next_event(&mut s);
        match r {
          Ok(k) => { if k < 0 { break; } },
          Err(e) => { return _err_state(e); },
        };
      }
      let fc = _check_finish(&s);
      match fc {
        Ok(_) => { return _ok_state(s); },
        Err(e) => { return _err_state(e); },
      };
      return _err_state("expat: unreachable");
    },
    Err(e) => { return _err_state(e); },
  };
  return _err_state("expat: unreachable");
}

/// Produce the next event for an open session.
/// Params: st - a state from expat_open (or a partially consumed one).
/// Returns: Ok(kind) where kind is one of the _XP_EV_* values and the event
/// has been appended to the state's parallel vectors; Ok(-1) once the input
/// is exhausted (idempotent). The cursor advances by the event's
/// ev_consumed length and line/column are maintained for the next event.
/// Empty elements produce two events: a start event (consuming the whole
/// `<name/>` markup) followed by an end event with consumed 0.
/// Error case: Err("expat: ...") for the first malformed construct; the
/// state is then indeterminate and should be discarded.
/// Complexity: O(event length).
pub fn expat_next_event(st: &mut ExpatState) -> Result[Int, Str] {
  let t: Str = st.text;
  let n = t.len();
  if st.pos >= n {
    return _ok_int(-1);
  }
  let off = st.pos;
  let ev_line = st.line;
  let ev_col = st.col;
  let b = _at(t, off);
  if b != _XP_LT {
    return _token_text(st, off, ev_line, ev_col);
  }
  if _match(t, off, "<!--") {
    return _token_comment(st, off, ev_line, ev_col);
  }
  if _match(t, off, "<![CDATA[") {
    return _token_cdata(st, off, ev_line, ev_col);
  }
  if _match(t, off, "<!DOCTYPE") {
    return _token_doctype(st, off, ev_line, ev_col);
  }
  if _match(t, off, "<?") {
    return _token_pi_or_decl(st, off, ev_line, ev_col);
  }
  if _match(t, off, "</") {
    return _token_end(st, off, ev_line, ev_col);
  }
  if off + 1 < n && _is_name_start_byte(_at(t, off + 1)) {
    return _token_start(st, off, ev_line, ev_col);
  }
  return _err_int(_err_at("invalid markup", off));
}

// ---------------------------------------------------------------------------
//  Public API: document metadata
// ---------------------------------------------------------------------------

/// Effective encoding label: "UTF-16LE"/"UTF-16BE" when a BOM was detected,
/// else the declared XML-declaration label, else "UTF-8". Labels are reported
/// exactly as written (no case normalization).
/// Params: st - the parse session.
/// Returns: the encoding label.
/// Error case: none.
/// Complexity: O(1).
pub fn expat_encoding(st: &ExpatState) -> Str {
  let v: Str = st.encoding;
  return v;
}

/// XML-declaration version, e.g. "1.0"; "" when the document has no
/// declaration.
/// Params: st - the parse session.
/// Returns: the version text.
/// Error case: none.
/// Complexity: O(1).
pub fn expat_version(st: &ExpatState) -> Str {
  let v: Str = st.version;
  return v;
}

/// XML-declaration standalone value: 1 for "yes", 0 for "no", -1 when the
/// declaration omits it or the document has no declaration.
/// Params: st - the parse session.
/// Returns: the standalone flag.
/// Error case: none.
/// Complexity: O(1).
pub fn expat_standalone(st: &ExpatState) -> Int {
  let v: Int = st.standalone;
  return v;
}

/// True when the document carried an XML declaration.
/// Params: st - the parse session.
/// Returns: the has_decl flag.
/// Error case: none.
/// Complexity: O(1).
pub fn expat_has_decl(st: &ExpatState) -> Bool {
  return st.has_decl;
}

/// True when the document carried a DOCTYPE declaration.
/// Params: st - the parse session.
/// Returns: the has_doctype flag.
/// Error case: none.
/// Complexity: O(1).
pub fn expat_has_doctype(st: &ExpatState) -> Bool {
  return st.has_doctype;
}

/// Number of elements that are still open (0 after a complete parse).
/// Params: st - the parse session.
/// Returns: the open-element count.
/// Error case: none.
/// Complexity: O(1).
pub fn expat_depth(st: &ExpatState) -> Int {
  return st.stack_names.len();
}

/// Number of internal general entities declared in the DOCTYPE subset.
/// Params: st - the parse session.
/// Returns: the entity count.
/// Error case: none.
/// Complexity: O(1).
pub fn expat_entity_count(st: &ExpatState) -> Int {
  return st.entities.len();
}

/// Name of internal entity `i` in declaration order.
/// Params: st - the parse session; i - zero-based entity index.
/// Returns: the entity name; "" when `i` is out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn expat_entity_name(st: &ExpatState, i: Int) -> Str {
  if i < 0 || i >= st.entities.len() {
    return "";
  }
  let v: Str = st.entities[i];
  return v;
}

/// Literal value of internal entity `i`, exactly as declared (references are
/// expanded only when the entity is used).
/// Params: st - the parse session; i - zero-based entity index.
/// Returns: the literal value; "" when `i` is out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn expat_entity_value(st: &ExpatState, i: Int) -> Str {
  if i < 0 || i >= st.entity_values.len() {
    return "";
  }
  let v: Str = st.entity_values[i];
  return v;
}

// ---------------------------------------------------------------------------
//  Public API: events
// ---------------------------------------------------------------------------

/// Number of recorded events.
/// Params: st - the parse session.
/// Returns: the event count.
/// Error case: none.
/// Complexity: O(1).
pub fn expat_event_count(st: &ExpatState) -> Int {
  return st.kinds.len();
}

/// Kind of event `i` (an _XP_EV_* value: 0 decl, 1 doctype, 2 comment, 3 pi,
/// 4 cdata, 5 start, 6 end, 7 text).
/// Params: st - the parse session; i - zero-based event index.
/// Returns: the kind; -1 when `i` is out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn expat_event_kind(st: &ExpatState, i: Int) -> Int {
  if i < 0 || i >= st.kinds.len() {
    return -1;
  }
  let v: Int = st.kinds[i];
  return v;
}

/// Stable name for an event kind constant.
/// Params: kind - an _XP_EV_* value.
/// Returns: "decl", "doctype", "comment", "pi", "cdata", "start", "end" or
/// "text"; "" for any other value.
/// Error case: none.
/// Complexity: O(1).
pub fn expat_event_kind_name(kind: Int) -> Str {
  if kind == _XP_EV_DECL {
    return "decl";
  }
  if kind == _XP_EV_DOCTYPE {
    return "doctype";
  }
  if kind == _XP_EV_COMMENT {
    return "comment";
  }
  if kind == _XP_EV_PI {
    return "pi";
  }
  if kind == _XP_EV_CDATA {
    return "cdata";
  }
  if kind == _XP_EV_START {
    return "start";
  }
  if kind == _XP_EV_END {
    return "end";
  }
  if kind == _XP_EV_TEXT {
    return "text";
  }
  return "";
}

/// Name payload of event `i`: the element name for start/end, the PI target,
/// the DOCTYPE name or the declaration version; "" otherwise.
/// Params: st - the parse session; i - zero-based event index.
/// Returns: the name text; "" when `i` is out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn expat_event_name(st: &ExpatState, i: Int) -> Str {
  if i < 0 || i >= st.names.len() {
    return "";
  }
  let v: Str = st.names[i];
  return v;
}

/// Data payload of event `i`: text run, comment body, CDATA body, PI data, the
/// declaration encoding label or the raw DOCTYPE internal subset; "" for
/// start/end events.
/// Params: st - the parse session; i - zero-based event index.
/// Returns: the data text; "" when `i` is out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn expat_event_data(st: &ExpatState, i: Int) -> Str {
  if i < 0 || i >= st.datas.len() {
    return "";
  }
  let v: Str = st.datas[i];
  return v;
}

/// SYSTEM identifier of DOCTYPE event `i` ("http://..." from SYSTEM/PUBLIC),
/// or "" for every other event and out-of-range indices.
/// Params: st - the parse session; i - zero-based event index.
/// Returns: the system identifier text.
/// Error case: none.
/// Complexity: O(1).
pub fn expat_event_system_id(st: &ExpatState, i: Int) -> Str {
  if i < 0 || i >= st.sids.len() {
    return "";
  }
  let v: Str = st.sids[i];
  return v;
}

/// PUBLIC identifier of DOCTYPE event `i`, or "" (including DOCTYPEs that only
/// carry a SYSTEM identifier).
/// Params: st - the parse session; i - zero-based event index.
/// Returns: the public identifier text.
/// Error case: none.
/// Complexity: O(1).
pub fn expat_event_public_id(st: &ExpatState, i: Int) -> Str {
  if i < 0 || i >= st.pubids.len() {
    return "";
  }
  let v: Str = st.pubids[i];
  return v;
}

/// Standalone flag of declaration event `i`: 1 "yes", 0 "no", -1 absent (and
/// -1 for every other event).
/// Params: st - the parse session; i - zero-based event index.
/// Returns: the flag.
/// Error case: none.
/// Complexity: O(1).
pub fn expat_event_standalone(st: &ExpatState, i: Int) -> Int {
  if i < 0 || i >= st.flags.len() {
    return -1;
  }
  let v: Int = st.flags[i];
  return v;
}

/// 0-based byte offset of the byte that starts event `i`.
/// Params: st - the parse session; i - zero-based event index.
/// Returns: the offset; -1 when `i` is out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn expat_event_offset(st: &ExpatState, i: Int) -> Int {
  if i < 0 || i >= st.ev_offsets.len() {
    return -1;
  }
  let v: Int = st.ev_offsets[i];
  return v;
}

/// 1-based line number of the byte that starts event `i`.
/// Params: st - the parse session; i - zero-based event index.
/// Returns: the line; -1 when `i` is out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn expat_event_line(st: &ExpatState, i: Int) -> Int {
  if i < 0 || i >= st.ev_lines.len() {
    return -1;
  }
  let v: Int = st.ev_lines[i];
  return v;
}

/// 1-based column (in code points) of the byte that starts event `i`.
/// Params: st - the parse session; i - zero-based event index.
/// Returns: the column; -1 when `i` is out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn expat_event_column(st: &ExpatState, i: Int) -> Int {
  if i < 0 || i >= st.ev_cols.len() {
    return -1;
  }
  let v: Int = st.ev_cols[i];
  return v;
}

/// Bytes of the document the event consumed; 0 for the synthesized end event
/// of an empty element and for the final Ok(-1) of expat_next_event.
/// Params: st - the parse session; i - zero-based event index.
/// Returns: the consumed byte count; -1 when `i` is out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn expat_event_consumed(st: &ExpatState, i: Int) -> Int {
  if i < 0 || i >= st.ev_consumed.len() {
    return -1;
  }
  let v: Int = st.ev_consumed[i];
  return v;
}

/// Number of attributes of event `i` (non-zero only for start events).
/// Params: st - the parse session; i - zero-based event index.
/// Returns: the attribute count; 0 when `i` is out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn expat_event_attr_count(st: &ExpatState, i: Int) -> Int {
  if i < 0 || i >= st.ev_attr_counts.len() {
    return 0;
  }
  let v: Int = st.ev_attr_counts[i];
  return v;
}

/// Name of attribute `k` of event `i` (start events only, source order).
/// Params: st - the parse session; i - zero-based event index; k - zero-based
/// attribute index.
/// Returns: the attribute name; "" when either index is out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn expat_event_attr_name(st: &ExpatState, i: Int, k: Int) -> Str {
  if i < 0 || i >= st.ev_attr_counts.len() {
    return "";
  }
  let c: Int = st.ev_attr_counts[i];
  if k < 0 || k >= c {
    return "";
  }
  let s: Int = st.ev_attr_starts[i];
  let v: Str = st.attr_names[s + k];
  return v;
}

/// Normalized value of attribute `k` of event `i`. Tab/LF/CR became spaces,
/// references were expanded and a raw '<' would have been rejected.
/// Params: st - the parse session; i - zero-based event index; k - zero-based
/// attribute index.
/// Returns: the attribute value; "" when either index is out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn expat_event_attr_value(st: &ExpatState, i: Int, k: Int) -> Str {
  if i < 0 || i >= st.ev_attr_counts.len() {
    return "";
  }
  let c: Int = st.ev_attr_counts[i];
  if k < 0 || k >= c {
    return "";
  }
  let s: Int = st.ev_attr_starts[i];
  let v: Str = st.attr_values[s + k];
  return v;
}

/// Quote style of attribute `k` of event `i`: 0 double-quoted, 1
/// single-quoted.
/// Params: st - the parse session; i - zero-based event index; k - zero-based
/// attribute index.
/// Returns: the quote flag; -1 when either index is out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn expat_event_attr_quote(st: &ExpatState, i: Int, k: Int) -> Int {
  if i < 0 || i >= st.ev_attr_counts.len() {
    return -1;
  }
  let c: Int = st.ev_attr_counts[i];
  if k < 0 || k >= c {
    return -1;
  }
  let s: Int = st.ev_attr_starts[i];
  let v: Int = st.attr_quotes[s + k];
  return v;
}

// ---------------------------------------------------------------------------
//  Public API: elements and content helpers
// ---------------------------------------------------------------------------

/// Number of elements: one per start event, including empty elements.
/// Params: st - the parse session.
/// Returns: the element count.
/// Error case: none.
/// Complexity: O(1).
pub fn expat_element_count(st: &ExpatState) -> Int {
  return st.elem_events.len();
}

/// Event index of element `i` (the element's start event).
/// Params: st - the parse session; i - zero-based element index.
/// Returns: the event index; -1 when `i` is out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn expat_element_event(st: &ExpatState, i: Int) -> Int {
  if i < 0 || i >= st.elem_events.len() {
    return -1;
  }
  let v: Int = st.elem_events[i];
  return v;
}

/// Name of element `i`.
/// Params: st - the parse session; i - zero-based element index.
/// Returns: the element name; "" when `i` is out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn expat_element_name(st: &ExpatState, i: Int) -> Str {
  let ev = expat_element_event(st, i);
  if ev < 0 {
    return "";
  }
  return expat_event_name(st, ev);
}

/// Element depth of element `i`: 0 for the root, 1 for its children, etc.
/// Params: st - the parse session; i - zero-based element index.
/// Returns: the depth; -1 when `i` is out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn expat_element_depth(st: &ExpatState, i: Int) -> Int {
  if i < 0 || i >= st.elem_depths.len() {
    return -1;
  }
  let v: Int = st.elem_depths[i];
  return v;
}

/// Number of attributes of element `i`.
/// Params: st - the parse session; i - zero-based element index.
/// Returns: the attribute count; 0 when `i` is out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn expat_element_attr_count(st: &ExpatState, i: Int) -> Int {
  let ev = expat_element_event(st, i);
  if ev < 0 {
    return 0;
  }
  return expat_event_attr_count(st, ev);
}

/// Name of attribute `k` of element `i` (source order).
/// Params: st - the parse session; i - zero-based element index; k - zero-based
/// attribute index.
/// Returns: the attribute name; "" when either index is out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn expat_element_attr_name(st: &ExpatState, i: Int, k: Int) -> Str {
  let ev = expat_element_event(st, i);
  if ev < 0 {
    return "";
  }
  return expat_event_attr_name(st, ev, k);
}

/// Value of attribute `k` of element `i` (normalized as in the event API).
/// Params: st - the parse session; i - zero-based element index; k - zero-based
/// attribute index.
/// Returns: the attribute value; "" when either index is out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn expat_element_attr_value(st: &ExpatState, i: Int, k: Int) -> Str {
  let ev = expat_element_event(st, i);
  if ev < 0 {
    return "";
  }
  return expat_event_attr_value(st, ev, k);
}

/// Value of the attribute named `name` on element `i` (first exact match in
/// source order).
/// Params: st - the parse session; i - zero-based element index; name - the
/// attribute name to look up (case-sensitive).
/// Returns: the attribute value; "" when the element or attribute is absent.
/// Error case: none.
/// Complexity: O(attributes of element i).
pub fn expat_extract_attribute(st: &ExpatState, i: Int, name: Str) -> Str {
  let ev = expat_element_event(st, i);
  if ev < 0 {
    return "";
  }
  let c: Int = st.ev_attr_counts[ev];
  let s: Int = st.ev_attr_starts[ev];
  var k = 0;
  while k < c {
    let an: Str = st.attr_names[s + k];
    if compare.str_compare(an, name) == 0 {
      let av: Str = st.attr_values[s + k];
      return av;
    }
    k = k + 1;
  }
  return "";
}

/// Text content of element `i`: the concatenation of every text and CDATA
/// event between its start event and its matching end event, at any
/// descendant depth (comments and processing instructions are excluded).
/// Walking is bounded by the recorded event list; relative nesting deeper
/// than the internal cap contributes nothing.
/// Params: st - the parse session; i - zero-based element index.
/// Returns: the accumulated text; "" when `i` is out of range or the element
/// has no text.
/// Error case: none.
/// Complexity: O(events between the element's start and end).
pub fn expat_text_content(st: &ExpatState, i: Int) -> Str {
  let ev = expat_element_event(st, i);
  if ev < 0 {
    return "";
  }
  let cnt = st.kinds.len();
  var d = 0;
  var j = ev + 1;
  var sb = Vec[UInt8].new();
  while j < cnt {
    let k: Int = st.kinds[j];
    if k == _XP_EV_START {
      d = d + 1;
    } elif k == _XP_EV_END {
      if d == 0 {
        break;
      }
      d = d - 1;
    } elif k == _XP_EV_TEXT || k == _XP_EV_CDATA {
      if d <= _XP_MAX_TEXT_DEPTH {
        let piece: Str = st.datas[j];
        builder.sb_push_str(&mut sb, piece);
      }
    }
    j = j + 1;
  }
  if sb.len() == 0 {
    return "";
  }
  return builder.sb_to_str(&sb);
}

// ---------------------------------------------------------------------------
//  Public API: qualified names (recorded, never resolved)
// ---------------------------------------------------------------------------

/// Prefix part of a qualified name: the text before the first ':' ("" when the
/// name has no prefix). No namespace URI resolution is performed.
/// Params: name - a qualified name such as "ns:tag".
/// Returns: the prefix; "" when there is none.
/// Error case: none.
/// Complexity: O(name length).
pub fn expat_prefix_of(name: Str) -> Str {
  let c = _find(name, 0, ":");
  if c <= 0 {
    return "";
  }
  return string.str_slice(name, 0, c);
}

/// Local part of a qualified name: the text after the first ':' (the whole
/// name when there is none). No namespace URI resolution is performed.
/// Params: name - a qualified name such as "ns:tag".
/// Returns: the local part.
/// Error case: none.
/// Complexity: O(name length).
pub fn expat_local_of(name: Str) -> Str {
  let c = _find(name, 0, ":");
  if c < 0 {
    return name;
  }
  return string.str_slice(name, c + 1, name.len());
}

