// XIOM -- xiom.plist: Apple XML property-list codec for a documented subset
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Supported subset (see SPEC.md for the full grammar, API contract, error
// catalog and test matrix): the optional <?xml ... ?> declaration and
// <!DOCTYPE ...> are skipped, <plist version="1.0"> is the root, and values
// are <dict> (alternating <key> then a value), <array>, <string>, <integer>
// (decimal, optional minus, 64-bit bounds-checked), <real> (validated text
// token), <true/> / <false/>, <data> (base64 text pass-through) and <date>
// (shape-validated text pass-through). Text is entity-decoded (&amp; &lt;
// &gt; &quot; &apos; plus numeric &#NN; / &#xNN;); comments and processing
// instructions between elements are skipped. plist_emit writes the document
// back canonically with deterministic tab indentation and is round-trip
// stable.
//
// v0.61.3 notes that shaped this module:
//   * The document is FLAT: kinds/texts/keys/parents are parallel node
//     vectors and children live in one flat Vec[Int] addressed by the
//     child_starts/child_lengths ranges (Vec[StructType] is unsupported in
//     this compiler, and child indices are not contiguous in parse order).
//   * Ok/Err for Result[PlistDoc, Str] are constructed only in the leaf
//     helpers _ok_doc/_err_doc (constructing Results directly inside other
//     functions miscompiles in this compiler).
//   * Str equality always goes through xiom.string.compare.str_compare
//     (BUG 17: `==` on Str values read from Vec[Str] elements lowers to a
//     pointer comparison).
//   * No Vec[Float64]: <real> values stay validated text tokens.
//   * Recursive descent over bytes. Every helper that pushes a node mirrors
//     all four parallel node vectors through _push_node, and every accessor
//     guards the child ranges before indexing (parallel-vector drift is an
//     access-violation source in this compiler).
//   * Str materialization from bytes uses the stdlib builder (single
//     allocation); raw NUL bytes are rejected before reaching it.

module xiom.plist

use xiom.string;
use xiom.string.builder;
use xiom.string.compare;
use xiom.convert;

// ---------------------------------------------------------------------------
//  Node kinds
// ---------------------------------------------------------------------------

/// Kind of a `<dict>` node.
pub const PLIST_KIND_DICT: Int = 0;
/// Kind of an `<array>` node.
pub const PLIST_KIND_ARRAY: Int = 1;
/// Kind of a `<string>` node.
pub const PLIST_KIND_STRING: Int = 2;
/// Kind of an `<integer>` node (canonical decimal text is stored).
pub const PLIST_KIND_INTEGER: Int = 3;
/// Kind of a `<real>` node (validated text token is stored).
pub const PLIST_KIND_REAL: Int = 4;
/// Kind of a `<true/>` or `<false/>` node ("true"/"false" is stored).
pub const PLIST_KIND_BOOL: Int = 5;
/// Kind of a `<data>` node (whitespace-stripped base64 text is stored).
pub const PLIST_KIND_DATA: Int = 6;
/// Kind of a `<date>` node (validated text token is stored).
pub const PLIST_KIND_DATE: Int = 7;
/// Kind of node 0, the synthetic document node that owns the root value.
pub const PLIST_KIND_DOC: Int = 8;

// ---------------------------------------------------------------------------
//  Document model
// ---------------------------------------------------------------------------

/// Parsed property list: a flat node list with parallel vectors. Node 0 is
/// the synthetic document node (kind PLIST_KIND_DOC, parent -1) and the root
/// value, when present, is its only child. `children` is a flat
/// concatenation of every node's child list; node i owns the slice
/// children[child_starts[i] .. child_starts[i] + child_lengths[i]].
/// kinds[i]: see the PLIST_KIND_* constants. texts[i]: the payload of scalar
/// nodes ("" for containers and the document node). keys[i]: the dict key of
/// node i when its parent is a dict ("" for array elements and the root).
/// parents[i]: the owning node index (-1 only for node 0). This layout
/// avoids Vec[StructType], which this compiler does not support.
pub type PlistDoc = {
  kinds: Vec[Int];
  texts: Vec[Str];
  keys: Vec[Str];
  parents: Vec[Int];
  child_starts: Vec[Int];
  child_lengths: Vec[Int];
  children: Vec[Int];
}

// ---------------------------------------------------------------------------
//  Result constructors (see the module header)
// ---------------------------------------------------------------------------

// Ok(d) for Result[PlistDoc, Str].
fn _ok_doc(d: PlistDoc) -> Result[PlistDoc, Str] {
  return Ok(d);
}

// Err(m) for Result[PlistDoc, Str].
fn _err_doc(m: Str) -> Result[PlistDoc, Str] {
  return Err(m);
}

// ---------------------------------------------------------------------------
//  Byte constants and byte predicates
// ---------------------------------------------------------------------------

const _PL_LT: UInt8 = 60u8;
const _PL_GT: UInt8 = 62u8;
const _PL_SLASH: UInt8 = 47u8;
const _PL_EQ: UInt8 = 61u8;
const _PL_AMP: UInt8 = 38u8;
const _PL_SEMI: UInt8 = 59u8;
const _PL_HASH: UInt8 = 35u8;
const _PL_DQUOTE: UInt8 = 34u8;
const _PL_SQUOTE: UInt8 = 39u8;
const _PL_SPACE: UInt8 = 32u8;
const _PL_TAB: UInt8 = 9u8;
const _PL_CR: UInt8 = 13u8;
const _PL_LF: UInt8 = 10u8;
const _PL_DASH: UInt8 = 45u8;
const _PL_PLUS: UInt8 = 43u8;
const _PL_DOT: UInt8 = 46u8;
const _PL_LOWER_X: UInt8 = 120u8;
const _PL_UPPER_X: UInt8 = 88u8;
const _PL_LOWER_E: UInt8 = 101u8;
const _PL_UPPER_E: UInt8 = 69u8;
const _PL_UPPER_T: UInt8 = 84u8;
const _PL_UPPER_Z: UInt8 = 90u8;
const _PL_BANG: UInt8 = 33u8;
const _PL_QUEST: UInt8 = 63u8;

// True for an ASCII space, tab, CR or LF.
fn _is_ws(b: UInt8) -> Bool {
  if b == _PL_SPACE {
    return true;
  }
  if b == _PL_TAB {
    return true;
  }
  if b == _PL_CR {
    return true;
  }
  if b == _PL_LF {
    return true;
  }
  return false;
}

// True when c terminates a tag or attribute name: whitespace, '=', '/', '>'
// or '<'.
fn _is_name_end(c: UInt8) -> Bool {
  if _is_ws(c) {
    return true;
  }
  if c == _PL_EQ {
    return true;
  }
  if c == _PL_SLASH {
    return true;
  }
  if c == _PL_GT {
    return true;
  }
  return c == _PL_LT;
}

// True when c is a base64 alphabet byte (padding included).
fn _is_base64_byte(c: UInt8) -> Bool {
  if c >= 65 && c <= 90 {
    return true;
  }
  if c >= 97 && c <= 122 {
    return true;
  }
  if c >= 48 && c <= 57 {
    return true;
  }
  return c == _PL_PLUS || c == _PL_SLASH || c == _PL_EQ;
}

// True when a and b hold the same bytes (BUG 17-safe Str equality).
fn _streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// True when name is one of the supported value element names.
fn _is_value_tag(name: Str) -> Bool {
  if _streq(name, "dict") {
    return true;
  }
  if _streq(name, "array") {
    return true;
  }
  if _streq(name, "string") {
    return true;
  }
  if _streq(name, "integer") {
    return true;
  }
  if _streq(name, "real") {
    return true;
  }
  if _streq(name, "true") {
    return true;
  }
  if _streq(name, "false") {
    return true;
  }
  if _streq(name, "data") {
    return true;
  }
  return _streq(name, "date");
}

// ---------------------------------------------------------------------------
//  Parser state
// ---------------------------------------------------------------------------

// Mutable parse state. `text`/`pos` are the input cursor; kinds/texts/keys/
// parents accumulate the flat node lists in lockstep; `tag`, `self_close`,
// `is_close` and the attribute fields hold the most recently scanned tag;
// `failed`/`error` carry the first failure (every parse helper stops at the
// first `false`).
type _PlistParser = {
  text: Str;
  pos: Int;
  kinds: Vec[Int];
  texts: Vec[Str];
  keys: Vec[Str];
  parents: Vec[Int];
  tag: Str;
  self_close: Bool;
  is_close: Bool;
  attr_count: Int;
  attr_name: Str;
  attr_value: Str;
  failed: Bool;
  error: Str;
}

// Record the first failure and return false (parse helpers propagate this).
fn _fail(p: &mut _PlistParser, m: Str) -> Bool {
  p.failed = true;
  p.error = m;
  return false;
}

// Byte at i of the input (0 past the end).
fn _byte(p: &mut _PlistParser, i: Int) -> UInt8 {
  return string.byte_at(p.text, i);
}

// Append one node, mirroring all four parallel node vectors, and return its
// index.
fn _push_node(p: &mut _PlistParser, kind: Int, text: Str, key: Str, parent: Int) -> Int {
  p.kinds.push(kind);
  p.texts.push(text);
  p.keys.push(key);
  p.parents.push(parent);
  return p.kinds.len() - 1;
}

// Skip a run of ASCII whitespace.
fn _skip_ws(p: &mut _PlistParser) {
  let n = p.text.len();
  while p.pos < n {
    if !_is_ws(_byte(p, p.pos)) {
      break;
    }
    p.pos = p.pos + 1;
  }
}

// True when `s` occurs at p.pos.
fn _starts_at(p: &mut _PlistParser, s: Str) -> Bool {
  let n = p.text.len();
  let m = s.len();
  if p.pos + m > n {
    return false;
  }
  var i = 0;
  while i < m {
    if _byte(p, p.pos + i) != string.byte_at(s, i) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// Index of the first occurrence of `needle` at or after `from`, -1 when
// absent.
fn _find_seq(p: &mut _PlistParser, needle: Str, from: Int) -> Int {
  let n = p.text.len();
  let m = needle.len();
  var i = from;
  while i + m <= n {
    var j = 0;
    var hit = true;
    while j < m {
      if _byte(p, i + j) != string.byte_at(needle, j) {
        hit = false;
        break;
      }
      j = j + 1;
    }
    if hit {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// Skip whitespace, comments, processing instructions (including the <?xml
// ... ?> declaration) and a <!DOCTYPE ...> prolog. Returns false only on a
// malformed unterminated construct.
fn _skip_misc(p: &mut _PlistParser) -> Bool {
  if p.failed {
    return false;
  }
  let n = p.text.len();
  loop {
    _skip_ws(p);
    if p.pos >= n {
      return true;
    }
    if _byte(p, p.pos) != _PL_LT {
      return true;
    }
    if p.pos + 2 < n {
      if _byte(p, p.pos + 1) == _PL_BANG && _byte(p, p.pos + 2) == _PL_DASH {
        if p.pos + 3 >= n || _byte(p, p.pos + 3) != _PL_DASH {
          return true;
        }
        let close = _find_seq(p, "-->", p.pos + 4);
        if close < 0 {
          return _fail(p, "plist: premature EOF");
        }
        p.pos = close + 3;
        continue;
      }
    }
    if p.pos + 1 < n && _byte(p, p.pos + 1) == _PL_QUEST {
      let close = _find_seq(p, "?>", p.pos + 2);
      if close < 0 {
        return _fail(p, "plist: premature EOF");
      }
      p.pos = close + 2;
      continue;
    }
    if _starts_at(p, "<!DOCTYPE") {
      let close = _find_seq(p, ">", p.pos + 9);
      if close < 0 {
        return _fail(p, "plist: premature EOF");
      }
      p.pos = close + 1;
      continue;
    }
    return true;
  }
}

// True when p.pos is at a "</" sequence.
fn _at_close(p: &mut _PlistParser) -> Bool {
  let n = p.text.len();
  if p.pos + 1 >= n {
    return false;
  }
  if _byte(p, p.pos) != _PL_LT {
    return false;
  }
  return _byte(p, p.pos + 1) == _PL_SLASH;
}

// Scan one tag at p.pos ('<'): name, optional attributes and '>' or '/>'.
// The scanned name and flags land in p.tag / p.self_close / p.is_close; an
// attribute value must be quoted.
fn _read_tag(p: &mut _PlistParser) -> Bool {
  if p.failed {
    return false;
  }
  p.tag = "";
  p.self_close = false;
  p.is_close = false;
  p.attr_count = 0;
  p.attr_name = "";
  p.attr_value = "";
  let n = p.text.len();
  if p.pos >= n {
    return _fail(p, "plist: premature EOF");
  }
  if _byte(p, p.pos) != _PL_LT {
    return _fail(p, "plist: malformed tag");
  }
  p.pos = p.pos + 1;
  if p.pos >= n {
    return _fail(p, "plist: premature EOF");
  }
  if _byte(p, p.pos) == _PL_SLASH {
    p.is_close = true;
    p.pos = p.pos + 1;
  }
  let name_start = p.pos;
  while p.pos < n {
    if _is_name_end(_byte(p, p.pos)) {
      break;
    }
    p.pos = p.pos + 1;
  }
  if p.pos == name_start {
    return _fail(p, "plist: malformed tag");
  }
  let first: Int = (_byte(p, name_start) as Int) & 0xFF;
  if !((first >= 65 && first <= 90) || (first >= 97 && first <= 122)) {
    return _fail(p, "plist: malformed tag");
  }
  p.tag = string.str_slice(p.text, name_start, p.pos);
  if p.is_close {
    _skip_ws(p);
    if p.pos >= n {
      return _fail(p, "plist: premature EOF");
    }
    if _byte(p, p.pos) != _PL_GT {
      return _fail(p, "plist: malformed tag");
    }
    p.pos = p.pos + 1;
    return true;
  }
  loop {
    _skip_ws(p);
    if p.pos >= n {
      return _fail(p, "plist: premature EOF");
    }
    let b = _byte(p, p.pos);
    if b == _PL_GT {
      p.pos = p.pos + 1;
      return true;
    }
    if b == _PL_SLASH {
      p.pos = p.pos + 1;
      if p.pos >= n {
        return _fail(p, "plist: premature EOF");
      }
      if _byte(p, p.pos) != _PL_GT {
        return _fail(p, "plist: malformed tag");
      }
      p.pos = p.pos + 1;
      p.self_close = true;
      return true;
    }
    if b == _PL_LT {
      return _fail(p, "plist: malformed tag");
    }
    let an_start = p.pos;
    while p.pos < n {
      let c = _byte(p, p.pos);
      if _is_name_end(c) {
        break;
      }
      p.pos = p.pos + 1;
    }
    if p.pos == an_start {
      return _fail(p, "plist: malformed tag");
    }
    let aname = string.str_slice(p.text, an_start, p.pos);
    _skip_ws(p);
    if p.pos >= n {
      return _fail(p, "plist: premature EOF");
    }
    if _byte(p, p.pos) != _PL_EQ {
      return _fail(p, "plist: malformed tag");
    }
    p.pos = p.pos + 1;
    _skip_ws(p);
    if p.pos >= n {
      return _fail(p, "plist: premature EOF");
    }
    let q = _byte(p, p.pos);
    if q != _PL_DQUOTE && q != _PL_SQUOTE {
      return _fail(p, "plist: unquoted attribute");
    }
    p.pos = p.pos + 1;
    let v_start = p.pos;
    while p.pos < n {
      if _byte(p, p.pos) == q {
        break;
      }
      p.pos = p.pos + 1;
    }
    if p.pos >= n {
      return _fail(p, "plist: premature EOF");
    }
    let raw_val = string.str_slice(p.text, v_start, p.pos);
    let aval = _decode_entities(p, raw_val, 0, raw_val.len());
    if p.failed {
      return false;
    }
    p.pos = p.pos + 1;
    if p.attr_count == 0 {
      p.attr_name = aname;
      p.attr_value = aval;
    }
    p.attr_count = p.attr_count + 1;
  }
}

// Read the character data of a leaf element up to the next '<' and
// entity-decode it. Fails on premature EOF or a malformed entity.
fn _scan_leaf_text(p: &mut _PlistParser) -> Str {
  if p.failed {
    return "";
  }
  let n = p.text.len();
  let start = p.pos;
  while p.pos < n {
    if _byte(p, p.pos) == _PL_LT {
      break;
    }
    p.pos = p.pos + 1;
  }
  if p.pos >= n {
    _fail(p, "plist: premature EOF");
    return "";
  }
  let src = p.text;
  return _decode_entities(p, src, start, p.pos);
}

// ---------------------------------------------------------------------------
//  Entity decoding
// ---------------------------------------------------------------------------

// Append the UTF-8 encoding of `code` (1..0x10FFFF) to `out`.
fn _push_utf8(out: &mut Vec[UInt8], code: Int) {
  if code <= 127 {
    out.push((code & 0xFF) as UInt8);
    return;
  }
  if code <= 2047 {
    out.push(((192 + code / 64) & 0xFF) as UInt8);
    out.push(((128 + code % 64) & 0xFF) as UInt8);
    return;
  }
  if code <= 65535 {
    out.push(((224 + code / 4096) & 0xFF) as UInt8);
    out.push(((128 + (code / 64) % 64) & 0xFF) as UInt8);
    out.push(((128 + code % 64) & 0xFF) as UInt8);
    return;
  }
  out.push(((240 + code / 262144) & 0xFF) as UInt8);
  out.push(((128 + (code / 4096) % 64) & 0xFF) as UInt8);
  out.push(((128 + (code / 64) % 64) & 0xFF) as UInt8);
  out.push(((128 + code % 64) & 0xFF) as UInt8);
}

// Codepoint of a "#NN" or "#xHH" reference body, -1 when malformed, NUL or
// out of range (> U+10FFFF).
fn _entity_code(body: Str) -> Int {
  let n = body.len();
  if n < 2 {
    return -1;
  }
  if string.byte_at(body, 0) != _PL_HASH {
    return -1;
  }
  var i = 1;
  var base = 10;
  let mark = string.byte_at(body, i);
  if mark == _PL_LOWER_X || mark == _PL_UPPER_X {
    base = 16;
    i = i + 1;
  }
  if i >= n {
    return -1;
  }
  var v = 0;
  while i < n {
    let b: Int = (string.byte_at(body, i) as Int) & 0xFF;
    var d = -1;
    if b >= 48 && b <= 57 {
      d = b - 48;
    } elif base == 16 && b >= 97 && b <= 102 {
      d = b - 87;
    } elif base == 16 && b >= 65 && b <= 70 {
      d = b - 55;
    } else {
      return -1;
    }
    if d >= base {
      return -1;
    }
    v = v * base + d;
    if v > 1114111 {
      return -1;
    }
    i = i + 1;
  }
  if v == 0 {
    return -1;
  }
  return v;
}

// Decode one entity at raw[at] (which must be '&'); returns the number of
// input bytes consumed, and fails on an unknown, malformed or unterminated
// reference (unlike xiom.xml, plist has no lenient pass-through).
fn _push_entity(p: &mut _PlistParser, raw: Str, at: Int, end: Int, out: &mut Vec[UInt8]) -> Int {
  var limit = at + 12;
  if limit > end {
    limit = end;
  }
  var semi = -1;
  var j = at + 1;
  while j < limit {
    if string.byte_at(raw, j) == _PL_SEMI {
      semi = j;
      break;
    }
    j = j + 1;
  }
  if semi < 0 {
    _fail(p, "plist: bad entity");
    return 0;
  }
  let body = string.str_slice(raw, at + 1, semi);
  if _streq(body, "amp") {
    out.push(_PL_AMP);
    return semi - at + 1;
  }
  if _streq(body, "lt") {
    out.push(_PL_LT);
    return semi - at + 1;
  }
  if _streq(body, "gt") {
    out.push(_PL_GT);
    return semi - at + 1;
  }
  if _streq(body, "quot") {
    out.push(_PL_DQUOTE);
    return semi - at + 1;
  }
  if _streq(body, "apos") {
    out.push(_PL_SQUOTE);
    return semi - at + 1;
  }
  let code = _entity_code(body);
  if code > 0 {
    _push_utf8(out, code);
    return semi - at + 1;
  }
  _fail(p, "plist: bad entity");
  return 0;
}

// Entity-decode raw[start, end) into a fresh Str. Raw NUL bytes are
// rejected because the builder materializes NUL-terminated buffers.
fn _decode_entities(p: &mut _PlistParser, raw: Str, start: Int, end: Int) -> Str {
  var out = Vec[UInt8].new();
  var i = start;
  while i < end {
    let b = string.byte_at(raw, i);
    if b == _PL_AMP {
      let adv = _push_entity(p, raw, i, end, &mut out);
      if p.failed {
        return "";
      }
      i = i + adv;
    } elif b == 0u8 {
      _fail(p, "plist: NUL byte in text");
      return "";
    } else {
      out.push(b);
      i = i + 1;
    }
  }
  return builder.sb_to_str(&out);
}

// ---------------------------------------------------------------------------
//  Scalar token validation
// ---------------------------------------------------------------------------

// Parse a decimal integer token: optional '-' then one or more ASCII digits,
// bounds-checked against the 64-bit Int range. Returns the value or
// Err("plist: bad integer").
fn _int_token(raw: Str) -> Result[Int, Str] {
  let s = string.str_trim(raw);
  let n = s.len();
  if n == 0 {
    return Err("plist: bad integer");
  }
  var i = 0;
  var neg = false;
  if string.byte_at(s, 0) == _PL_DASH {
    neg = true;
    i = 1;
  }
  if i >= n {
    return Err("plist: bad integer");
  }
  var acc = 0;
  var is_min = false;
  while i < n {
    let b: Int = (string.byte_at(s, i) as Int) & 0xFF;
    if b < 48 || b > 57 {
      return Err("plist: bad integer");
    }
    let d = b - 48;
    if acc > 922337203685477580 {
      return Err("plist: bad integer");
    }
    if acc == 922337203685477580 {
      if neg {
        if d > 8 {
          return Err("plist: bad integer");
        }
        if d == 8 {
          if i != n - 1 {
            return Err("plist: bad integer");
          }
          is_min = true;
        }
      } else {
        if d > 7 {
          return Err("plist: bad integer");
        }
      }
    }
    if !is_min {
      acc = acc * 10 + d;
    }
    i = i + 1;
  }
  if is_min {
    return Ok(0 - 9223372036854775807 - 1);
  }
  if neg {
    return Ok(0 - acc);
  }
  return Ok(acc);
}

// Validate a real token: optional '-', one or more digits, optional
// ".digits", optional exponent ("e"/"E", optional sign, digits). The text is
// kept verbatim (trimmed) -- no Vec[Float64] and no rounding.
fn _real_token(raw: Str) -> Result[Str, Str] {
  let s = string.str_trim(raw);
  let n = s.len();
  if n == 0 {
    return Err("plist: bad real");
  }
  var i = 0;
  if string.byte_at(s, 0) == _PL_DASH {
    i = 1;
  }
  var int_digits = 0;
  while i < n {
    let b: Int = (string.byte_at(s, i) as Int) & 0xFF;
    if b < 48 || b > 57 {
      break;
    }
    int_digits = int_digits + 1;
    i = i + 1;
  }
  if int_digits == 0 {
    return Err("plist: bad real");
  }
  if i < n && string.byte_at(s, i) == _PL_DOT {
    i = i + 1;
    var frac_digits = 0;
    while i < n {
      let b: Int = (string.byte_at(s, i) as Int) & 0xFF;
      if b < 48 || b > 57 {
        break;
      }
      frac_digits = frac_digits + 1;
      i = i + 1;
    }
    if frac_digits == 0 {
      return Err("plist: bad real");
    }
  }
  if i < n {
    let e = string.byte_at(s, i);
    if e == _PL_LOWER_E || e == _PL_UPPER_E {
      i = i + 1;
      if i < n {
        let sg = string.byte_at(s, i);
        if sg == _PL_DASH || sg == _PL_PLUS {
          i = i + 1;
        }
      }
      var exp_digits = 0;
      while i < n {
        let b: Int = (string.byte_at(s, i) as Int) & 0xFF;
        if b < 48 || b > 57 {
          break;
        }
        exp_digits = exp_digits + 1;
        i = i + 1;
      }
      if exp_digits == 0 {
        return Err("plist: bad real");
      }
    }
  }
  if i != n {
    return Err("plist: bad real");
  }
  return Ok(s);
}

// Strip all ASCII whitespace from a base64 body and validate the alphabet
// and padding placement ('=' may only form a trailing run). The base64 text
// is stored verbatim (pass-through, no decoding).
fn _data_token(raw: Str) -> Result[Str, Str] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < raw.len() {
    let b = string.byte_at(raw, i);
    if b == _PL_SPACE || b == _PL_TAB || b == _PL_CR || b == _PL_LF {
      i = i + 1;
    } elif _is_base64_byte(b) {
      out.push(b);
      i = i + 1;
    } else {
      return Err("plist: bad data");
    }
  }
  let m = out.len();
  var j = 0;
  var padded = false;
  while j < m {
    let c: UInt8 = out[j];
    if c == _PL_EQ {
      padded = true;
    } elif padded {
      return Err("plist: bad data");
    }
    j = j + 1;
  }
  return Ok(builder.sb_to_str(&out));
}

// Single ASCII digit value at i, or -1 when the byte is not a digit.
fn _digit_at(s: Str, i: Int) -> Int {
  let b: Int = (string.byte_at(s, i) as Int) & 0xFF;
  if b < 48 || b > 57 {
    return -1;
  }
  return b - 48;
}

// Two-digit decimal value at i, or -1 when either byte is not a digit.
fn _two_digits(s: Str, i: Int) -> Int {
  let a = _digit_at(s, i);
  let b = _digit_at(s, i + 1);
  if a < 0 || b < 0 {
    return -1;
  }
  return a * 10 + b;
}

// Validate a date token: exactly "YYYY-MM-DDThh:mm:ssZ" with digit
// components and calendar-ish ranges (month 1..12, day 1..31, hour 0..23,
// minute 0..59, second 0..59). The text is kept verbatim (trimmed).
fn _date_token(raw: Str) -> Result[Str, Str] {
  let s = string.str_trim(raw);
  if s.len() != 20 {
    return Err("plist: bad date");
  }
  var i = 0;
  while i < 4 {
    if _digit_at(s, i) < 0 {
      return Err("plist: bad date");
    }
    i = i + 1;
  }
  if string.byte_at(s, 4) != _PL_DASH {
    return Err("plist: bad date");
  }
  let month = _two_digits(s, 5);
  if month < 1 || month > 12 {
    return Err("plist: bad date");
  }
  if string.byte_at(s, 7) != _PL_DASH {
    return Err("plist: bad date");
  }
  let day = _two_digits(s, 8);
  if day < 1 || day > 31 {
    return Err("plist: bad date");
  }
  if string.byte_at(s, 10) != _PL_UPPER_T {
    return Err("plist: bad date");
  }
  let hour = _two_digits(s, 11);
  if hour < 0 || hour > 23 {
    return Err("plist: bad date");
  }
  if string.byte_at(s, 13) != 58u8 {
    return Err("plist: bad date");
  }
  let minute = _two_digits(s, 14);
  if minute < 0 || minute > 59 {
    return Err("plist: bad date");
  }
  if string.byte_at(s, 16) != 58u8 {
    return Err("plist: bad date");
  }
  let second = _two_digits(s, 17);
  if second < 0 || second > 59 {
    return Err("plist: bad date");
  }
  if string.byte_at(s, 19) != _PL_UPPER_Z {
    return Err("plist: bad date");
  }
  return Ok(s);
}

// ---------------------------------------------------------------------------
//  Value parsing
// ---------------------------------------------------------------------------

// Parse one value element: skip leading misc, read the start tag and
// dispatch. Used for the root value and array items.
fn _parse_value(p: &mut _PlistParser, parent: Int) -> Bool {
  if !_skip_misc(p) {
    return false;
  }
  let n = p.text.len();
  if p.pos >= n {
    return _fail(p, "plist: premature EOF");
  }
  if _byte(p, p.pos) != _PL_LT {
    return _fail(p, "plist: text outside elements");
  }
  if !_read_tag(p) {
    return false;
  }
  if p.is_close {
    return _fail(p, "plist: mismatched tag");
  }
  return _parse_value_open(p, parent, "");
}

// Complete a value element whose start tag has already been scanned: push
// the node and parse the element body when it is not self-closing. `key` is
// the owning dict key ("" outside a dict).
fn _parse_value_open(p: &mut _PlistParser, parent: Int, key: Str) -> Bool {
  let name = p.tag;
  if _streq(name, "dict") {
    return _parse_dict(p, parent, key);
  }
  if _streq(name, "array") {
    return _parse_array(p, parent, key);
  }
  if _streq(name, "string") {
    return _parse_scalar(p, parent, key, PLIST_KIND_STRING, "string");
  }
  if _streq(name, "integer") {
    return _parse_scalar(p, parent, key, PLIST_KIND_INTEGER, "integer");
  }
  if _streq(name, "real") {
    return _parse_scalar(p, parent, key, PLIST_KIND_REAL, "real");
  }
  if _streq(name, "data") {
    return _parse_scalar(p, parent, key, PLIST_KIND_DATA, "data");
  }
  if _streq(name, "date") {
    return _parse_scalar(p, parent, key, PLIST_KIND_DATE, "date");
  }
  if _streq(name, "true") {
    return _parse_bool(p, parent, key, true);
  }
  if _streq(name, "false") {
    return _parse_bool(p, parent, key, false);
  }
  if _streq(name, "key") {
    return _fail(p, "plist: key outside dict");
  }
  return _fail(p, "plist: unknown tag");
}

// Parse a dict: a sequence of <key> elements each followed by exactly one
// value element. Missing or extra elements are Err("plist: odd dict element
// count").
fn _parse_dict(p: &mut _PlistParser, parent: Int, key: Str) -> Bool {
  let node = _push_node(p, PLIST_KIND_DICT, "", key, parent);
  if p.self_close {
    return true;
  }
  let n = p.text.len();
  loop {
    if !_skip_misc(p) {
      return false;
    }
    if p.pos >= n {
      return _fail(p, "plist: premature EOF");
    }
    if _byte(p, p.pos) != _PL_LT {
      return _fail(p, "plist: text outside elements");
    }
    if _at_close(p) {
      if !_read_tag(p) {
        return false;
      }
      if !_streq(p.tag, "dict") {
        return _fail(p, "plist: mismatched tag");
      }
      return true;
    }
    if !_read_tag(p) {
      return false;
    }
    if p.is_close {
      return _fail(p, "plist: mismatched tag");
    }
    if !_streq(p.tag, "key") {
      if _is_value_tag(p.tag) {
        return _fail(p, "plist: odd dict element count");
      }
      return _fail(p, "plist: unknown tag");
    }
    var ktext = "";
    if !p.self_close {
      ktext = _scan_leaf_text(p);
      if p.failed {
        return false;
      }
      if !_read_tag(p) {
        return false;
      }
      if !p.is_close {
        return _fail(p, "plist: mismatched tag");
      }
      if !_streq(p.tag, "key") {
        return _fail(p, "plist: mismatched tag");
      }
    }
    if !_skip_misc(p) {
      return false;
    }
    if p.pos >= n {
      return _fail(p, "plist: premature EOF");
    }
    if _byte(p, p.pos) != _PL_LT {
      return _fail(p, "plist: text outside elements");
    }
    if _at_close(p) {
      if !_read_tag(p) {
        return false;
      }
      if !_streq(p.tag, "dict") {
        return _fail(p, "plist: mismatched tag");
      }
      return _fail(p, "plist: odd dict element count");
    }
    if !_read_tag(p) {
      return false;
    }
    if p.is_close {
      return _fail(p, "plist: mismatched tag");
    }
    if _streq(p.tag, "key") {
      return _fail(p, "plist: odd dict element count");
    }
    if !_parse_value_open(p, node, ktext) {
      return false;
    }
  }
}

// Parse an array: a sequence of value elements (text is rejected).
fn _parse_array(p: &mut _PlistParser, parent: Int, key: Str) -> Bool {
  let node = _push_node(p, PLIST_KIND_ARRAY, "", key, parent);
  if p.self_close {
    return true;
  }
  let n = p.text.len();
  loop {
    if !_skip_misc(p) {
      return false;
    }
    if p.pos >= n {
      return _fail(p, "plist: premature EOF");
    }
    if _byte(p, p.pos) != _PL_LT {
      return _fail(p, "plist: text outside elements");
    }
    if _at_close(p) {
      if !_read_tag(p) {
        return false;
      }
      if !_streq(p.tag, "array") {
        return _fail(p, "plist: mismatched tag");
      }
      return true;
    }
    if !_parse_value(p, node) {
      return false;
    }
  }
}

// Parse a text leaf element (string/integer/real/data/date): read the body,
// validate/canonicalize it and push the node.
fn _parse_scalar(p: &mut _PlistParser, parent: Int, key: Str, kind: Int, name: Str) -> Bool {
  var raw = "";
  if !p.self_close {
    raw = _scan_leaf_text(p);
    if p.failed {
      return false;
    }
    if !_read_tag(p) {
      return false;
    }
    if !p.is_close {
      return _fail(p, "plist: mismatched tag");
    }
    if !_streq(p.tag, name) {
      return _fail(p, "plist: mismatched tag");
    }
  }
  if kind == PLIST_KIND_STRING {
    _push_node(p, kind, raw, key, parent);
    return true;
  }
  if kind == PLIST_KIND_INTEGER {
    let r = _int_token(raw);
    match r {
      Ok(v) => {
        _push_node(p, kind, convert.int_to_string(v), key, parent);
        return true;
      },
      Err(e) => {
        return _fail(p, e);
      },
    }
  }
  if kind == PLIST_KIND_REAL {
    let r = _real_token(raw);
    match r {
      Ok(v) => {
        _push_node(p, kind, v, key, parent);
        return true;
      },
      Err(e) => {
        return _fail(p, e);
      },
    }
  }
  if kind == PLIST_KIND_DATA {
    let r = _data_token(raw);
    match r {
      Ok(v) => {
        _push_node(p, kind, v, key, parent);
        return true;
      },
      Err(e) => {
        return _fail(p, e);
      },
    }
  }
  let r = _date_token(raw);
  match r {
    Ok(v) => {
      _push_node(p, kind, v, key, parent);
      return true;
    },
    Err(e) => {
      return _fail(p, e);
    },
  }
}

// Parse <true/> or <false/>; the empty-element form is required.
fn _parse_bool(p: &mut _PlistParser, parent: Int, key: Str, want: Bool) -> Bool {
  if !p.self_close {
    return _fail(p, "plist: malformed tag");
  }
  if want {
    _push_node(p, PLIST_KIND_BOOL, "true", key, parent);
  } else {
    _push_node(p, PLIST_KIND_BOOL, "false", key, parent);
  }
  return true;
}

// ---------------------------------------------------------------------------
//  Document assembly
// ---------------------------------------------------------------------------

// Build the flat child-range model from the parse-time parallel vectors
// (counting sort by parent, so the child indices of every node are a
// contiguous slice of `children`).
fn _build_doc(kinds: Vec[Int], texts: Vec[Str], keys: Vec[Str], parents: Vec[Int]) -> PlistDoc {
  let n = kinds.len();
  var counts = Vec[Int].new();
  var i = 0;
  while i < n {
    counts.push(0);
    i = i + 1;
  }
  i = 1;
  while i < n {
    let par: Int = parents[i];
    if par >= 0 && par < n {
      let c: Int = counts[par];
      counts[par] = c + 1;
    }
    i = i + 1;
  }
  var starts = Vec[Int].new();
  var acc = 0;
  i = 0;
  while i < n {
    starts.push(acc);
    acc = acc + counts[i];
    i = i + 1;
  }
  var cursor = Vec[Int].new();
  i = 0;
  while i < n {
    cursor.push(starts[i]);
    i = i + 1;
  }
  var children = Vec[Int].new();
  while children.len() < n - 1 {
    children.push(0);
  }
  i = 1;
  while i < n {
    let par: Int = parents[i];
    if par >= 0 && par < n {
      let at: Int = cursor[par];
      if at >= 0 && at < children.len() {
        children[at] = i;
        cursor[par] = at + 1;
      }
    }
    i = i + 1;
  }
  return PlistDoc{
    kinds: kinds;
    texts: texts;
    keys: keys;
    parents: parents;
    child_starts: starts;
    child_lengths: counts;
    children: children;
  };
}

// ---------------------------------------------------------------------------
//  Public parsing API
// ---------------------------------------------------------------------------

/// Parse an Apple XML property list in the supported subset.
/// Params: text - the whole document as one Str (UTF-8 bytes pass through;
/// only markup bytes are interpreted).
/// Returns: Ok(doc) with the flat node model (node 0 is the synthetic
/// document node, node 1 the root value when present).
/// Error case: Err("plist: ...") on the first malformed construct; see
/// SPEC.md for the full catalog (premature EOF, malformed/unknown/mismatched
/// tags, key outside dict, odd dict element count, bad integer/real/data/
/// date, bad entity, unquoted/unknown/missing attribute, unsupported
/// version, text outside elements, missing root value, multiple root values,
/// content after the document root).
/// Complexity: O(n) over the document bytes.
pub fn plist_parse(text: Str) -> Result[PlistDoc, Str] {
  var p = _PlistParser{
    text: text; pos: 0;
    kinds: Vec[Int].new(); texts: Vec[Str].new(); keys: Vec[Str].new();
    parents: Vec[Int].new();
    tag: ""; self_close: false; is_close: false;
    attr_count: 0; attr_name: ""; attr_value: "";
    failed: false; error: "";
  };
  _push_node(&mut p, PLIST_KIND_DOC, "", "", -1);
  let n = text.len();
  if !_skip_misc(&mut p) {
    return _err_doc(p.error);
  }
  if p.pos >= n {
    return _err_doc("plist: premature EOF");
  }
  if _byte(&mut p, p.pos) != _PL_LT {
    return _err_doc("plist: text outside elements");
  }
  if !_read_tag(&mut p) {
    return _err_doc(p.error);
  }
  if p.is_close {
    return _err_doc("plist: mismatched tag");
  }
  if !_streq(p.tag, "plist") {
    return _err_doc("plist: unknown tag");
  }
  if p.attr_count == 0 {
    return _err_doc("plist: missing version attribute");
  }
  if p.attr_count > 1 {
    return _err_doc("plist: unknown attribute");
  }
  if !_streq(p.attr_name, "version") {
    return _err_doc("plist: unknown attribute");
  }
  if !_streq(p.attr_value, "1.0") {
    return _err_doc("plist: unsupported version");
  }
  if p.self_close {
    return _err_doc("plist: missing root value");
  }
  if !_skip_misc(&mut p) {
    return _err_doc(p.error);
  }
  if p.pos >= n {
    return _err_doc("plist: premature EOF");
  }
  if _byte(&mut p, p.pos) != _PL_LT {
    return _err_doc("plist: text outside elements");
  }
  if _at_close(&mut p) {
    return _err_doc("plist: missing root value");
  }
  if !_parse_value(&mut p, 0) {
    return _err_doc(p.error);
  }
  if !_skip_misc(&mut p) {
    return _err_doc(p.error);
  }
  if p.pos >= n {
    return _err_doc("plist: premature EOF");
  }
  if _byte(&mut p, p.pos) != _PL_LT {
    return _err_doc("plist: text outside elements");
  }
  if !_read_tag(&mut p) {
    return _err_doc(p.error);
  }
  if !p.is_close {
    return _err_doc("plist: multiple root values");
  }
  if !_streq(p.tag, "plist") {
    return _err_doc("plist: mismatched tag");
  }
  if !_skip_misc(&mut p) {
    return _err_doc(p.error);
  }
  if p.pos < n {
    return _err_doc("plist: content after document root");
  }
  return _ok_doc(_build_doc(p.kinds, p.texts, p.keys, p.parents));
}

// ---------------------------------------------------------------------------
//  Accessors
// ---------------------------------------------------------------------------

// True when node has a valid index and its child range fits inside
// `children`.
fn _range_ok(d: &PlistDoc, node: Int) -> Bool {
  if node < 0 || node >= d.kinds.len() {
    return false;
  }
  if node >= d.child_starts.len() || node >= d.child_lengths.len() {
    return false;
  }
  let s: Int = d.child_starts[node];
  let c: Int = d.child_lengths[node];
  if s < 0 || c < 0 {
    return false;
  }
  return s + c <= d.children.len();
}

/// Root value node of the document (the only child of the synthetic
/// document node 0).
/// Params: d - the parsed document.
/// Returns: the node index, or -1 when the document has no root value.
/// Complexity: O(1).
pub fn plist_root(d: &PlistDoc) -> Int {
  if !_range_ok(d, 0) {
    return -1;
  }
  let c: Int = d.child_lengths[0];
  if c < 1 {
    return -1;
  }
  let s: Int = d.child_starts[0];
  let node: Int = d.children[s];
  return node;
}

/// Kind of the document's root value.
/// Params: d - the parsed document.
/// Returns: one of the PLIST_KIND_* constants, or -1 when there is no root
/// value.
/// Complexity: O(1).
pub fn plist_root_kind(d: &PlistDoc) -> Int {
  return plist_kind(d, plist_root(d));
}

/// Number of nodes in the document, including the synthetic document node.
/// Params: d - the parsed document.
/// Returns: the node count; an empty synthetic document reports 1.
/// Complexity: O(1).
pub fn plist_node_count(d: &PlistDoc) -> Int {
  return d.kinds.len();
}

/// Node kind.
/// Params: d - the parsed document; node - the node index.
/// Returns: one of the PLIST_KIND_* constants, or -1 when node is out of
/// range.
/// Complexity: O(1).
pub fn plist_kind(d: &PlistDoc, node: Int) -> Int {
  if node < 0 || node >= d.kinds.len() {
    return -1;
  }
  let k: Int = d.kinds[node];
  return k;
}

/// Parent of a node.
/// Params: d - the parsed document; node - the node index.
/// Returns: Some(parent index); Some(-1) for the synthetic document node 0;
/// None when node is out of range.
/// Complexity: O(1).
pub fn plist_parent(d: &PlistDoc, node: Int) -> Option[Int] {
  if node < 0 || node >= d.parents.len() {
    return None;
  }
  let v: Int = d.parents[node];
  return Some(v);
}

/// Text payload of a scalar node.
/// Params: d - the parsed document; node - the node index.
/// Returns: the stored text for string/integer/real/bool/data/date nodes
/// ("" for containers, the document node and out-of-range indices).
/// Complexity: O(1).
pub fn plist_text(d: &PlistDoc, node: Int) -> Str {
  let k = plist_kind(d, node);
  if k == PLIST_KIND_STRING || k == PLIST_KIND_INTEGER || k == PLIST_KIND_REAL || k == PLIST_KIND_BOOL || k == PLIST_KIND_DATA || k == PLIST_KIND_DATE {
    if node >= 0 && node < d.texts.len() {
      let s: Str = d.texts[node];
      return s;
    }
  }
  return "";
}

/// Parsed integer value of an `<integer>` node.
/// Params: d - the parsed document; node - the node index.
/// Returns: Some(value); None for another kind or an out-of-range index.
/// Bounds: the stored canonical text always reparses to its value.
/// Complexity: O(digits).
pub fn plist_int_value(d: &PlistDoc, node: Int) -> Option[Int] {
  if plist_kind(d, node) != PLIST_KIND_INTEGER {
    return None;
  }
  if node < 0 || node >= d.texts.len() {
    return None;
  }
  let s: Str = d.texts[node];
  let r = _int_token(s);
  match r {
    Ok(v) => {
      return Some(v);
    },
    Err(_) => {
      return None;
    },
  }
  return None;
}

/// Boolean value of a `<true/>` / `<false/>` node.
/// Params: d - the parsed document; node - the node index.
/// Returns: Some(true/false); None for another kind or an out-of-range
/// index.
/// Complexity: O(1).
pub fn plist_bool_value(d: &PlistDoc, node: Int) -> Option[Bool] {
  if plist_kind(d, node) != PLIST_KIND_BOOL {
    return None;
  }
  if node < 0 || node >= d.texts.len() {
    return None;
  }
  let s: Str = d.texts[node];
  if compare.str_compare(s, "true") == 0 {
    return Some(true);
  }
  return Some(false);
}

/// Number of entries (key/value pairs) of a `<dict>` node.
/// Params: d - the parsed document; node - the node index.
/// Returns: the entry count; 0 for another kind or an out-of-range index.
/// Complexity: O(1).
pub fn plist_dict_count(d: &PlistDoc, node: Int) -> Int {
  if plist_kind(d, node) != PLIST_KIND_DICT {
    return 0;
  }
  if !_range_ok(d, node) {
    return 0;
  }
  let c: Int = d.child_lengths[node];
  return c;
}

/// Key of the dict entry at a zero-based position.
/// Params: d - the parsed document; node - the dict node index; index - the
/// zero-based entry position.
/// Returns: Some(key) (which may be ""); None for another kind,
/// out-of-range positions or out-of-range nodes.
/// Complexity: O(1).
pub fn plist_dict_key(d: &PlistDoc, node: Int, index: Int) -> Option[Str] {
  if plist_kind(d, node) != PLIST_KIND_DICT {
    return None;
  }
  if index < 0 || !_range_ok(d, node) {
    return None;
  }
  let s: Int = d.child_starts[node];
  let c: Int = d.child_lengths[node];
  if index >= c {
    return None;
  }
  let child: Int = d.children[s + index];
  if child < 0 || child >= d.keys.len() {
    return None;
  }
  let k: Str = d.keys[child];
  return Some(k);
}

/// Value node of a dict entry by key.
/// Params: d - the parsed document; node - the dict node index; key - the
/// exact key text (byte comparison).
/// Returns: Some(value node index) for the first entry whose key matches;
/// None when the key is absent, the node is not a dict or the node index is
/// out of range. plist_parse accepts duplicate keys (it does not police
/// uniqueness) and lookup returns the first match.
/// Complexity: O(entries).
pub fn plist_dict_get(d: &PlistDoc, node: Int, key: Str) -> Option[Int] {
  if plist_kind(d, node) != PLIST_KIND_DICT {
    return None;
  }
  if !_range_ok(d, node) {
    return None;
  }
  let s: Int = d.child_starts[node];
  let c: Int = d.child_lengths[node];
  var i = 0;
  while i < c {
    let child: Int = d.children[s + i];
    if child >= 0 && child < d.keys.len() {
      let k: Str = d.keys[child];
      if compare.str_compare(k, key) == 0 {
        return Some(child);
      }
    }
    i = i + 1;
  }
  return None;
}

/// Number of items of an `<array>` node.
/// Params: d - the parsed document; node - the node index.
/// Returns: the item count; 0 for another kind or an out-of-range index.
/// Complexity: O(1).
pub fn plist_array_count(d: &PlistDoc, node: Int) -> Int {
  if plist_kind(d, node) != PLIST_KIND_ARRAY {
    return 0;
  }
  if !_range_ok(d, node) {
    return 0;
  }
  let c: Int = d.child_lengths[node];
  return c;
}

/// Item node of an `<array>` by zero-based position.
/// Params: d - the parsed document; node - the array node index; index -
/// the zero-based item position.
/// Returns: Some(item node index); None for another kind, negative or
/// out-of-range positions or out-of-range nodes.
/// Complexity: O(1).
pub fn plist_array_get(d: &PlistDoc, node: Int, index: Int) -> Option[Int] {
  if plist_kind(d, node) != PLIST_KIND_ARRAY {
    return None;
  }
  if index < 0 || !_range_ok(d, node) {
    return None;
  }
  let s: Int = d.child_starts[node];
  let c: Int = d.child_lengths[node];
  if index >= c {
    return None;
  }
  let child: Int = d.children[s + index];
  return Some(child);
}

// ---------------------------------------------------------------------------
//  Canonical emitter
// ---------------------------------------------------------------------------

// True when all parallel vectors agree and every child slice fits inside
// `children`.
fn _doc_consistent(d: &PlistDoc) -> Bool {
  let n = d.kinds.len();
  if d.texts.len() != n || d.keys.len() != n {
    return false;
  }
  if d.parents.len() != n || d.child_starts.len() != n {
    return false;
  }
  if d.child_lengths.len() != n {
    return false;
  }
  var i = 0;
  while i < n {
    let s: Int = d.child_starts[i];
    let c: Int = d.child_lengths[i];
    if s < 0 || c < 0 {
      return false;
    }
    if s + c > d.children.len() {
      return false;
    }
    i = i + 1;
  }
  i = 0;
  while i < d.children.len() {
    let c: Int = d.children[i];
    if c < 0 || c >= n {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// Push `depth` tab bytes.
fn _push_indent(out: &mut Vec[UInt8], depth: Int) {
  var i = 0;
  while i < depth {
    out.push(_PL_TAB);
    i = i + 1;
  }
}

// Push `s` with &, < and > escaped as named entities.
fn _emit_escaped(out: &mut Vec[UInt8], s: Str) {
  var i = 0;
  while i < s.len() {
    let b = string.byte_at(s, i);
    if b == _PL_AMP {
      builder.sb_push_str(out, "&amp;");
    } elif b == _PL_LT {
      builder.sb_push_str(out, "&lt;");
    } elif b == _PL_GT {
      builder.sb_push_str(out, "&gt;");
    } else {
      out.push(b);
    }
    i = i + 1;
  }
}

// Emit one node at `depth` (recursive).
fn _emit_value(d: &PlistDoc, node: Int, depth: Int, out: &mut Vec[UInt8]) {
  let kind: Int = d.kinds[node];
  if kind == PLIST_KIND_DICT {
    _emit_dict(d, node, depth, out);
    return;
  }
  if kind == PLIST_KIND_ARRAY {
    _emit_array(d, node, depth, out);
    return;
  }
  _emit_scalar(d, node, depth, out);
}

// Emit a dict: one <key> line followed by the value for every entry.
fn _emit_dict(d: &PlistDoc, node: Int, depth: Int, out: &mut Vec[UInt8]) {
  let count: Int = d.child_lengths[node];
  _push_indent(out, depth);
  if count == 0 {
    builder.sb_push_str(out, "<dict/>\n");
    return;
  }
  builder.sb_push_str(out, "<dict>\n");
  let start: Int = d.child_starts[node];
  var i = 0;
  while i < count {
    let child: Int = d.children[start + i];
    _push_indent(out, depth + 1);
    builder.sb_push_str(out, "<key>");
    let k: Str = d.keys[child];
    _emit_escaped(out, k);
    builder.sb_push_str(out, "</key>\n");
    _emit_value(d, child, depth + 1, out);
    i = i + 1;
  }
  _push_indent(out, depth);
  builder.sb_push_str(out, "</dict>\n");
}

// Emit an array: one item per line.
fn _emit_array(d: &PlistDoc, node: Int, depth: Int, out: &mut Vec[UInt8]) {
  let count: Int = d.child_lengths[node];
  _push_indent(out, depth);
  if count == 0 {
    builder.sb_push_str(out, "<array/>\n");
    return;
  }
  builder.sb_push_str(out, "<array>\n");
  let start: Int = d.child_starts[node];
  var i = 0;
  while i < count {
    let child: Int = d.children[start + i];
    _emit_value(d, child, depth + 1, out);
    i = i + 1;
  }
  _push_indent(out, depth);
  builder.sb_push_str(out, "</array>\n");
}

// Emit a scalar node (string text is escaped; the other tokens are already
// canonical).
fn _emit_scalar(d: &PlistDoc, node: Int, depth: Int, out: &mut Vec[UInt8]) {
  let kind: Int = d.kinds[node];
  let t: Str = d.texts[node];
  _push_indent(out, depth);
  if kind == PLIST_KIND_STRING {
    builder.sb_push_str(out, "<string>");
    _emit_escaped(out, t);
    builder.sb_push_str(out, "</string>\n");
    return;
  }
  if kind == PLIST_KIND_INTEGER {
    builder.sb_push_str(out, "<integer>");
    builder.sb_push_str(out, t);
    builder.sb_push_str(out, "</integer>\n");
    return;
  }
  if kind == PLIST_KIND_REAL {
    builder.sb_push_str(out, "<real>");
    builder.sb_push_str(out, t);
    builder.sb_push_str(out, "</real>\n");
    return;
  }
  if kind == PLIST_KIND_DATA {
    builder.sb_push_str(out, "<data>");
    builder.sb_push_str(out, t);
    builder.sb_push_str(out, "</data>\n");
    return;
  }
  if kind == PLIST_KIND_DATE {
    builder.sb_push_str(out, "<date>");
    builder.sb_push_str(out, t);
    builder.sb_push_str(out, "</date>\n");
    return;
  }
  if compare.str_compare(t, "true") == 0 {
    builder.sb_push_str(out, "<true/>\n");
  } else {
    builder.sb_push_str(out, "<false/>\n");
  }
}

/// Serialize a document to canonical XML with deterministic tab indentation.
/// Params: d - the parsed document.
/// Returns: the canonical document text ending in a newline, starting with
/// the XML declaration and the Apple DOCTYPE, with `<plist version="1.0">`
/// as the root; `plist_parse(plist_emit(d))` reparses to an equivalent
/// document and `plist_emit` is idempotent on its own output. The empty
/// string is returned when `d` has no root value or its parallel vectors
/// disagree (documents from plist_parse are always consistent).
/// Complexity: O(nodes + text bytes).
pub fn plist_emit(d: &PlistDoc) -> Str {
  if !_doc_consistent(d) {
    return "";
  }
  let root = plist_root(d);
  if root < 0 {
    return "";
  }
  var out = Vec[UInt8].new();
  builder.sb_push_str(&mut out, "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");
  builder.sb_push_str(&mut out, "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n");
  builder.sb_push_str(&mut out, "<plist version=\"1.0\">\n");
  _emit_value(d, root, 1, &mut out);
  builder.sb_push_str(&mut out, "</plist>\n");
  return builder.sb_to_str(&out);
}
