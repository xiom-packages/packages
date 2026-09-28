// XIOM -- xiom.dynamo: Amazon DynamoDB JSON (wire) API shape codec
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure-XIOM (no FFI, no sockets, no signing) STRUCTURE codec for the
// DynamoDB JSON wire protocol: AttributeValue objects, items, request
// shapes and response shapes. The module encodes the payloads a caller
// exchanges over its own HTTPS transport (SigV4 signing is a caller
// concern); it never performs network I/O and never authenticates.
//
// Covered surface:
//   * AttributeValue codec for S, N, B, SS, NS, BS, M, L, NULL and BOOL:
//     parse/validate/render over a bounded raw-byte JSON scanner that is
//     escape-aware (\/, \\, \b, \f, \n, \r, \t, \uXXXX with surrogate
//     pairs decoded to UTF-8), boundary-checked and offset-diagnosed.
//   * Item codec: an item is a map of attribute name -> AttributeValue,
//     stored in a flat node tape (parallel Vec fields, no Vec[StructType])
//     with typed accessors (kind, string, number text, number int/frac/exp
//     text, bool, null, map lookup by key, list by index, set members).
//   * Request shapes: GetItem, PutItem, UpdateItem (UpdateExpression or
//     AttributeUpdates), DeleteItem, Query, Scan, BatchGetItem,
//     BatchWriteItem and TransactWriteItems, each with a canonical JSON
//     render helper.
//   * Response shapes: Item/Items, ConsumedCapacity (table and index
//     breakdown), LastEvaluatedKey, Count/ScannedCount, UnprocessedItems /
//     UnprocessedKeys and the {__type, message} error envelope.
//   * Validation: DynamoDB table/key name charset (3..255 of
//     [a-zA-Z0-9_.-]) and the 400KB item cap, with typed errors that carry
//     byte offsets. No network and no signing (caller concerns).
//
// v0.61.3 notes that shaped this module:
//   * Ok/Err construction is confined to the leaf helpers _ok_* / _err_*.
//   * Free functions only; no methods, no lambdas, no match, no floats, no
//     Vec[StructType] (flat node tape with parallel Vec fields instead).
//   * Every byte read from a Vec[UInt8] widens once with `(x as Int) & 0xFF`.
//   * No Str value is compared with `==`; everything goes through
//     xiom.string.compare.str_compare with typed locals.
//   * Struct fields are copied into typed locals before they are passed by
//     reference; &mut write-through is used only for Vec pushes.
//   * sb_to_str is never fed a 0x00 byte: parsed strings reject NUL escapes
//     and rendered JSON escapes every control byte.

module xiom.dynamo

use xiom.string;
use xiom.string.builder;
use xiom.string.compare;

// --------------------------------------------------
//  Byte constants (Int space, always compared masked)
// --------------------------------------------------

const _DYN_TAB: Int = 9;
const _DYN_LF: Int = 10;
const _DYN_CR: Int = 13;
const _DYN_SPACE: Int = 32;
const _DYN_QUOTE: Int = 34;
const _DYN_PLUS: Int = 43;
const _DYN_COMMA: Int = 44;
const _DYN_MINUS: Int = 45;
const _DYN_DOT: Int = 46;
const _DYN_SLASH: Int = 47;
const _DYN_COLON: Int = 58;
const _DYN_EQUALS: Int = 61;
const _DYN_LBRACKET: Int = 91;
const _DYN_BACKSLASH: Int = 92;
const _DYN_RBRACKET: Int = 93;
const _DYN_UNDERSCORE: Int = 95;
const _DYN_LBRACE: Int = 123;
const _DYN_RBRACE: Int = 125;
const _DYN_LOWER_A: Int = 97;
const _DYN_LOWER_B: Int = 98;
const _DYN_LOWER_E: Int = 101;
const _DYN_LOWER_F: Int = 102;
const _DYN_LOWER_L: Int = 108;
const _DYN_LOWER_N: Int = 110;
const _DYN_LOWER_R: Int = 114;
const _DYN_LOWER_S: Int = 115;
const _DYN_LOWER_T: Int = 116;
const _DYN_LOWER_U: Int = 117;
const _DYN_UPPER_E: Int = 69;

// --------------------------------------------------
//  Attribute value kind ids
// --------------------------------------------------

const _DYN_K_S: Int = 1;
const _DYN_K_N: Int = 2;
const _DYN_K_B: Int = 3;
const _DYN_K_SS: Int = 4;
const _DYN_K_NS: Int = 5;
const _DYN_K_BS: Int = 6;
const _DYN_K_M: Int = 7;
const _DYN_K_L: Int = 8;
const _DYN_K_NULL: Int = 9;
const _DYN_K_BOOL: Int = 10;
const _DYN_K_KEY: Int = 11;
const _DYN_K_UNKNOWN: Int = -1;

// Limits.
const _DYN_MAX_JSON: Int = 1048576;
const _DYN_ITEM_MAX: Int = 409600;
const _DYN_MAX_DEPTH: Int = 32;
const _DYN_NAME_MIN: Int = 3;
const _DYN_NAME_MAX: Int = 255;

// Bounds of the scanner.
/// Upper bound on JSON text scanned by the helpers. Params: none.
/// Returns: 1048576. Error case: none. Complexity: O(1).
pub fn dynamo_max_json_bytes() -> Int {
  return _DYN_MAX_JSON;
}

// 400KB item limit in bytes.
/// DynamoDB item size limit: 409600 bytes (400KB). Params: none.
/// Returns: 409600. Error case: none. Complexity: O(1).
pub fn dynamo_item_max_bytes() -> Int {
  return _DYN_ITEM_MAX;
}

/// Version of the xiom.dynamo package. Params: none. Returns: "0.1.0".
/// Error case: none. Complexity: O(1).
pub fn dynamo_version() -> Str {
  return "0.1.0";
}

// Standard base64 alphabet with padding (RFC 4648 section 4).
const _DYN_B64_ALPHABET: Str = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

fn _ok_str(v: Str) -> Result[Str, Str] { return Ok(v); }
fn _err_str(m: Str) -> Result[Str, Str] { return Err(m); }
fn _ok_int(v: Int) -> Result[Int, Str] { return Ok(v); }
fn _err_int(m: Str) -> Result[Int, Str] { return Err(m); }
fn _ok_bool(v: Bool) -> Result[Bool, Str] { return Ok(v); }
fn _err_bool(m: Str) -> Result[Bool, Str] { return Err(m); }
fn _ok_pair(v: (Int, Int)) -> Result[(Int, Int), Str] { return Ok(v); }
fn _err_pair(m: Str) -> Result[(Int, Int), Str] { return Err(m); }
fn _ok_bytes(v: Vec[UInt8]) -> Result[Vec[UInt8], Str] { return Ok(v); }
fn _err_bytes(m: Str) -> Result[Vec[UInt8], Str] { return Err(m); }

// --------------------------------------------------
//  Kind accessors
// --------------------------------------------------

/// Kind id of the S (string) attribute value. Params: none. Returns: 1.
pub fn dynamo_av_s() -> Int { return _DYN_K_S; }
/// Kind id of the N (number) attribute value. Params: none. Returns: 2.
pub fn dynamo_av_n() -> Int { return _DYN_K_N; }
/// Kind id of the B (binary) attribute value. Params: none. Returns: 3.
pub fn dynamo_av_b() -> Int { return _DYN_K_B; }
/// Kind id of the SS (string set) attribute value. Params: none. Returns: 4.
pub fn dynamo_av_ss() -> Int { return _DYN_K_SS; }
/// Kind id of the NS (number set) attribute value. Params: none. Returns: 5.
pub fn dynamo_av_ns() -> Int { return _DYN_K_NS; }
/// Kind id of the BS (binary set) attribute value. Params: none. Returns: 6.
pub fn dynamo_av_bs() -> Int { return _DYN_K_BS; }
/// Kind id of the M (map) attribute value. Params: none. Returns: 7.
pub fn dynamo_av_m() -> Int { return _DYN_K_M; }
/// Kind id of the L (list) attribute value. Params: none. Returns: 8.
pub fn dynamo_av_l() -> Int { return _DYN_K_L; }
/// Kind id of the NULL attribute value. Params: none. Returns: 9.
pub fn dynamo_av_null() -> Int { return _DYN_K_NULL; }
/// Kind id of the BOOL attribute value. Params: none. Returns: 10.
pub fn dynamo_av_bool() -> Int { return _DYN_K_BOOL; }

/// True when kind is a set kind (SS, NS or BS). Params: kind - a kind id.
/// Returns: the predicate. Error case: none. Complexity: O(1).
pub fn dynamo_av_kind_is_set(kind: Int) -> Bool {
  if kind == _DYN_K_SS { return true; }
  if kind == _DYN_K_NS { return true; }
  if kind == _DYN_K_BS { return true; }
  return false;
}

/// Wire name of a kind id ("S".."BOOL", "KEY" for map keys), "UNKNOWN"
/// otherwise. Params: kind - a kind id. Returns: the name.
/// Error case: none. Complexity: O(1).
pub fn dynamo_av_kind_name(kind: Int) -> Str {
  if kind == _DYN_K_S { return "S"; }
  if kind == _DYN_K_N { return "N"; }
  if kind == _DYN_K_B { return "B"; }
  if kind == _DYN_K_SS { return "SS"; }
  if kind == _DYN_K_NS { return "NS"; }
  if kind == _DYN_K_BS { return "BS"; }
  if kind == _DYN_K_M { return "M"; }
  if kind == _DYN_K_L { return "L"; }
  if kind == _DYN_K_NULL { return "NULL"; }
  if kind == _DYN_K_BOOL { return "BOOL"; }
  if kind == _DYN_K_KEY { return "KEY"; }
  return "UNKNOWN";
}

// Kind id of a wire type name; _DYN_K_UNKNOWN when unrecognised.
fn _kind_of_name(name: Str) -> Int {
  if compare.str_compare(name, "S") == 0 { return _DYN_K_S; }
  if compare.str_compare(name, "N") == 0 { return _DYN_K_N; }
  if compare.str_compare(name, "B") == 0 { return _DYN_K_B; }
  if compare.str_compare(name, "SS") == 0 { return _DYN_K_SS; }
  if compare.str_compare(name, "NS") == 0 { return _DYN_K_NS; }
  if compare.str_compare(name, "BS") == 0 { return _DYN_K_BS; }
  if compare.str_compare(name, "M") == 0 { return _DYN_K_M; }
  if compare.str_compare(name, "L") == 0 { return _DYN_K_L; }
  if compare.str_compare(name, "NULL") == 0 { return _DYN_K_NULL; }
  if compare.str_compare(name, "BOOL") == 0 { return _DYN_K_BOOL; }
  return _DYN_K_UNKNOWN;
}

// --------------------------------------------------
//  Shared byte helpers
// --------------------------------------------------

// Byte of a Str at pos, widened to 0..255. Callers guarantee the bounds.
fn _byte(s: Str, pos: Int) -> Int {
  return (string.byte_at(s, pos) as Int) & 0xFF;
}

// Byte of a Vec[UInt8] at pos, widened to 0..255.
fn _vbyte(data: &Vec[UInt8], pos: Int) -> Int {
  return (data[pos] as Int) & 0xFF;
}

// Decimal text of v for error messages (sign/digits only; never 0x00).
fn _int_str(v: Int) -> Str {
  var out = Vec[UInt8].new();
  builder.sb_push_int(&mut out, v);
  return builder.sb_to_str(&out);
}

// "<what> at offset <off>": the offset-bearing error convention.
fn _perr(what: Str, off: Int) -> Str {
  return "dynamo: " + what + " at offset " + _int_str(off);
}

fn _is_digit(c: Int) -> Bool {
  if c >= 48 && c <= 57 { return true; }
  return false;
}

fn _is_alpha(c: Int) -> Bool {
  if c >= 65 && c <= 90 { return true; }
  if c >= 97 && c <= 122 { return true; }
  return false;
}

// Numeric value of a hex digit byte (0-9, A-F, a-f); -1 for any other byte.
fn _hex_value(c: Int) -> Int {
  if c >= 48 && c <= 57 { return c - 48; }
  if c >= 65 && c <= 70 { return c - 55; }
  if c >= 97 && c <= 102 { return c - 87; }
  return -1;
}

// Uppercase hex digit byte for a nibble value (0..15).
fn _hex_upper(n: Int) -> UInt8 {
  if n < 10 {
    return (48 + n) as UInt8;
  }
  return (55 + n) as UInt8;
}

// Raw bytes of a Str (one byte per index).
fn _bytes_of(s: Str) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  let n = s.len();
  var i = 0;
  while i < n {
    out.push(string.byte_at(s, i));
    i = i + 1;
  }
  return out;
}

// True when a and b hold the same bytes.
fn _streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// True when items already contains text (linear scan; sets are small).
fn _contains_text(items: &Vec[Str], text: Str) -> Bool {
  var i = 0;
  while i < items.len() {
    let cur: Str = items[i];
    if compare.str_compare(cur, text) == 0 {
      return true;
    }
    i = i + 1;
  }
  return false;
}

// --------------------------------------------------
//  Base64 (B / BS payloads, local helper)
// --------------------------------------------------

// Value of a standard base64 character; -1 for any other byte.
fn _b64_val(c: Int) -> Int {
  if c >= 65 && c <= 90 { return c - 65; }
  if c >= 97 && c <= 122 { return c - 71; }
  if c >= 48 && c <= 57 { return c + 4; }
  if c == _DYN_PLUS { return 62; }
  if c == _DYN_SLASH { return 63; }
  return -1;
}

// Validate standard base64 text: alphabet bytes, at most two trailing '='
// pads, no length remainder of 1. Errors carry offsets.
fn _b64_check(s: Str) -> Result[Str, Str] {
  let n = s.len();
  if n == 0 {
    return _ok_str("");
  }
  var pad = 0;
  var i = n - 1;
  while i >= 0 && _byte(s, i) == _DYN_EQUALS {
    pad = pad + 1;
    if pad > 2 {
      return _err_str(_perr("base64 bad padding", i));
    }
    i = i - 1;
  }
  let body = n - pad;
  if body % 4 == 1 {
    return _err_str(_perr("base64 bad length", body));
  }
  if pad > 0 && n % 4 != 0 {
    return _err_str(_perr("base64 bad padding", body));
  }
  var j = 0;
  while j < body {
    if _b64_val(_byte(s, j)) < 0 {
      return _err_str(_perr("base64 bad character", j));
    }
    j = j + 1;
  }
  return _ok_str("");
}

/// True when s is valid standard base64 (padded or unpadded).
/// Params: s - the candidate text. Returns: the predicate.
/// Error case: none. Complexity: O(s.len()).
pub fn dynamo_base64_is_valid(s: Str) -> Bool {
  let r = _b64_check(s);
  return r.is_ok;
}

/// Decode standard base64 (padded or unpadded) to raw bytes.
/// Params: s - the base64 text.
/// Returns: Ok(bytes); an empty input yields Ok(empty).
/// Error case: Err("dynamo: base64 bad character at offset N"), Err(
/// "dynamo: base64 bad padding at offset N"), Err("dynamo: base64 bad
/// length at offset N").
/// Complexity: O(s.len()).
pub fn dynamo_base64_decode(s: Str) -> Result[Vec[UInt8], Str] {
  let chk = _b64_check(s);
  if !chk.is_ok {
    return _err_bytes(chk.error);
  }
  var out = Vec[UInt8].new();
  let n = s.len();
  var pad = 0;
  var i = n - 1;
  while i >= 0 && _byte(s, i) == _DYN_EQUALS {
    pad = pad + 1;
    i = i - 1;
  }
  let body = n - pad;
  var j = 0;
  while j < body {
    let c0 = _b64_val(_byte(s, j));
    let c1 = _b64_val(_byte(s, j + 1));
    let rem = body - j;
    out.push(((c0 << 2) | (c1 >> 4)) as UInt8);
    if rem >= 3 {
      let c2 = _b64_val(_byte(s, j + 2));
      out.push((((c1 & 15) << 4) | (c2 >> 2)) as UInt8);
      if rem >= 4 {
        let c3 = _b64_val(_byte(s, j + 3));
        out.push((((c2 & 3) << 6) | c3) as UInt8);
      }
    }
    j = j + 4;
  }
  return _ok_bytes(out);
}

/// Encode raw bytes as standard padded base64.
/// Params: data - the raw bytes.
/// Returns: the base64 text (empty input yields "").
/// Error case: none. Complexity: O(data.len()).
pub fn dynamo_base64_encode(data: &Vec[UInt8]) -> Str {
  var out = Vec[UInt8].new();
  let n = data.len();
  var i = 0;
  while i + 3 <= n {
    let b0 = _vbyte(data, i);
    let b1 = _vbyte(data, i + 1);
    let b2 = _vbyte(data, i + 2);
    out.push(string.byte_at(_DYN_B64_ALPHABET, b0 >> 2));
    out.push(string.byte_at(_DYN_B64_ALPHABET, ((b0 & 3) << 4) | (b1 >> 4)));
    out.push(string.byte_at(_DYN_B64_ALPHABET, ((b1 & 15) << 2) | (b2 >> 6)));
    out.push(string.byte_at(_DYN_B64_ALPHABET, b2 & 63));
    i = i + 3;
  }
  let rem = n - i;
  if rem == 1 {
    let b0 = _vbyte(data, i);
    out.push(string.byte_at(_DYN_B64_ALPHABET, b0 >> 2));
    out.push(string.byte_at(_DYN_B64_ALPHABET, (b0 & 3) << 4));
    out.push(_DYN_EQUALS as UInt8);
    out.push(_DYN_EQUALS as UInt8);
  } elif rem == 2 {
    let b0 = _vbyte(data, i);
    let b1 = _vbyte(data, i + 1);
    out.push(string.byte_at(_DYN_B64_ALPHABET, b0 >> 2));
    out.push(string.byte_at(_DYN_B64_ALPHABET, ((b0 & 3) << 4) | (b1 >> 4)));
    out.push(string.byte_at(_DYN_B64_ALPHABET, (b1 & 15) << 2));
    out.push(_DYN_EQUALS as UInt8);
  }
  return builder.sb_to_str(&out);
}

// --------------------------------------------------
//  Number strings (N / NS payloads)
// --------------------------------------------------

/// Validate a DynamoDB number string: optional '+'/'-' sign, one or more
/// integer digits, optional '.' plus fraction digits, optional 'e'/'E'
/// exponent with optional sign. NaN, Inf and whitespace are rejected.
/// Params: s - the candidate text.
/// Returns: Ok("") when valid.
/// Error case: Err("dynamo: number is empty"), Err("dynamo: number has no
/// digits at offset N"), Err("dynamo: number bad character at offset N"),
/// Err("dynamo: number missing fraction digits at offset N"), Err("dynamo:
/// number missing exponent digits at offset N").
/// Complexity: O(s.len()).
pub fn dynamo_number_check(s: Str) -> Result[Str, Str] {
  let n = s.len();
  if n == 0 {
    return _err_str("dynamo: number is empty");
  }
  var i = 0;
  let c0 = _byte(s, 0);
  if c0 == _DYN_PLUS || c0 == _DYN_MINUS {
    i = 1;
  }
  if i >= n {
    return _err_str(_perr("number has no digits", i));
  }
  if !_is_digit(_byte(s, i)) {
    return _err_str(_perr("number bad character", i));
  }
  while i < n && _is_digit(_byte(s, i)) {
    i = i + 1;
  }
  if i < n && _byte(s, i) == _DYN_DOT {
    i = i + 1;
    if i >= n || !_is_digit(_byte(s, i)) {
      return _err_str(_perr("number missing fraction digits", i));
    }
    while i < n && _is_digit(_byte(s, i)) {
      i = i + 1;
    }
  }
  if i < n && (_byte(s, i) == _DYN_LOWER_E || _byte(s, i) == _DYN_UPPER_E) {
    i = i + 1;
    if i < n && (_byte(s, i) == _DYN_PLUS || _byte(s, i) == _DYN_MINUS) {
      i = i + 1;
    }
    if i >= n || !_is_digit(_byte(s, i)) {
      return _err_str(_perr("number missing exponent digits", i));
    }
    while i < n && _is_digit(_byte(s, i)) {
      i = i + 1;
    }
  }
  if i != n {
    return _err_str(_perr("number bad character", i));
  }
  return _ok_str("");
}

/// True when s is a valid DynamoDB number string.
/// Params: s - the candidate text. Returns: the predicate.
/// Error case: none. Complexity: O(s.len()).
pub fn dynamo_number_is_valid(s: Str) -> Bool {
  let r = dynamo_number_check(s);
  return r.is_ok;
}

// --------------------------------------------------
//  Node tape (flat tree; parallel Vec fields)
// --------------------------------------------------

/// An attribute value tape: nodes in post-order. kinds[i] holds the kind
/// id; texts[i] the S/N/B/base64/map-key text; flags[i] the BOOL value
/// (0/1) or NULL marker; children[i] the contiguous child node indices in
/// [starts[i], starts[i] + counts[i]). Maps store children as
/// key-node, value-node pairs; sets store one leaf per member.
pub type DynamoValue = {
  kinds: Vec[Int];
  texts: Vec[Str];
  flags: Vec[Int];
  starts: Vec[Int];
  counts: Vec[Int];
  children: Vec[Int];
}

/// A node inside a DynamoValue tape: `values` owns the tape and `node` is
/// the root index of this item / attribute value (-1 means absent).
pub type DynamoItem = {
  values: DynamoValue;
  node: Int;
}

fn _ok_value(v: DynamoValue) -> Result[DynamoValue, Str] { return Ok(v); }
fn _err_value(m: Str) -> Result[DynamoValue, Str] { return Err(m); }
fn _ok_item(v: DynamoItem) -> Result[DynamoItem, Str] { return Ok(v); }
fn _err_item(m: Str) -> Result[DynamoItem, Str] { return Err(m); }

/// A fresh empty tape. Params: none. Returns: the tape.
/// Error case: none. Complexity: O(1).
pub fn dynamo_value_new() -> DynamoValue {
  return DynamoValue{
    kinds: Vec[Int].new();
    texts: Vec[Str].new();
    flags: Vec[Int].new();
    starts: Vec[Int].new();
    counts: Vec[Int].new();
    children: Vec[Int].new();
  };
}

/// Number of nodes in the tape. Params: v - the tape. Returns: the count.
/// Error case: none. Complexity: O(1).
pub fn dynamo_value_count(v: &DynamoValue) -> Int {
  return v.kinds.len();
}

// Push one node to every parallel array. Internal.
fn _dyn_push_node(v: &mut DynamoValue, kind: Int, text: Str, flag: Int, start: Int, count: Int) -> Int {
  v.kinds.push(kind);
  v.texts.push(text);
  v.flags.push(flag);
  v.starts.push(start);
  v.counts.push(count);
  return v.kinds.len() - 1;
}

// Push one leaf node (no children). Internal.
fn _dyn_push_leaf(v: &mut DynamoValue, kind: Int, text: Str, flag: Int) -> Int {
  return _dyn_push_node(v, kind, text, flag, 0, 0);
}

// Push one container node and its children, contiguously. Internal.
fn _dyn_push_container(v: &mut DynamoValue, kind: Int, kids: &Vec[Int]) -> Int {
  let start = v.children.len();
  let count = kids.len();
  let node = _dyn_push_node(v, kind, "", 0, start, count);
  var i = 0;
  while i < count {
    let k: Int = kids[i];
    v.children.push(k);
    i = i + 1;
  }
  return node;
}

/// Append every node of src to dst, shifting node indices and child spans;
/// returns the node offset (src node n becomes dst node n + offset).
/// Params: dst - the destination tape; src - the source tape.
/// Returns: the node offset. Error case: none.
/// Complexity: O(src nodes + src children).
pub fn dynamo_value_merge(dst: &mut DynamoValue, src: &DynamoValue) -> Int {
  let off = dst.kinds.len();
  let child_base = dst.children.len();
  var i = 0;
  while i < src.kinds.len() {
    let k: Int = src.kinds[i];
    let s: Str = src.texts[i];
    let f: Int = src.flags[i];
    let st: Int = src.starts[i];
    let ct: Int = src.counts[i];
    dst.kinds.push(k);
    dst.texts.push(s);
    dst.flags.push(f);
    dst.starts.push(st + child_base);
    dst.counts.push(ct);
    i = i + 1;
  }
  var j = 0;
  while j < src.children.len() {
    let c: Int = src.children[j];
    dst.children.push(c + off);
    j = j + 1;
  }
  return off;
}

/// Wrap a tape and node index as a DynamoItem.
/// Params: v - the tape; node - the root node (-1 for absent).
/// Returns: the item. Error case: none. Complexity: O(1).
pub fn dynamo_item_wrap(v: DynamoValue, node: Int) -> DynamoItem {
  return DynamoItem{ values: v; node: node; };
}

/// The root node index of an item. Params: item - the item.
/// Returns: the node index. Error case: none. Complexity: O(1).
pub fn dynamo_item_node(item: &DynamoItem) -> Int {
  let n: Int = item.node;
  return n;
}

/// A fresh empty map item ({}). Params: none. Returns: the item.
/// Error case: none. Complexity: O(1).
pub fn dynamo_item_new_map() -> DynamoItem {
  var v = dynamo_value_new();
  var empty = Vec[Int].new();
  let node = _dyn_push_container(&mut v, _DYN_K_M, &empty);
  return DynamoItem{ values: v; node: node; };
}

/// Push an S leaf. Params: v - the tape; s - the string text.
/// Returns: the new node index. Error case: none. Complexity: O(1).
pub fn dynamo_value_push_string(v: &mut DynamoValue, s: Str) -> Int {
  return _dyn_push_leaf(v, _DYN_K_S, s, 0);
}

/// Push a validated N leaf. Params: v - the tape; s - the number text.
/// Returns: Ok(node). Error case: the dynamo_number_check catalog.
/// Complexity: O(s.len()).
pub fn dynamo_value_push_number(v: &mut DynamoValue, s: Str) -> Result[Int, Str] {
  let chk = dynamo_number_check(s);
  if !chk.is_ok {
    return _err_int(chk.error);
  }
  return _ok_int(_dyn_push_leaf(v, _DYN_K_N, s, 0));
}

/// Push a validated B leaf. Params: v - the tape; base64_text - the base64.
/// Returns: Ok(node). Error case: the _b64_check catalog.
/// Complexity: O(base64_text.len()).
pub fn dynamo_value_push_binary(v: &mut DynamoValue, base64_text: Str) -> Result[Int, Str] {
  let chk = _b64_check(base64_text);
  if !chk.is_ok {
    return _err_int(chk.error);
  }
  return _ok_int(_dyn_push_leaf(v, _DYN_K_B, base64_text, 0));
}

/// Push a BOOL leaf. Params: v - the tape; b - the value.
/// Returns: the new node index. Error case: none. Complexity: O(1).
pub fn dynamo_value_push_bool(v: &mut DynamoValue, b: Bool) -> Int {
  var flag = 0;
  if b {
    flag = 1;
  }
  return _dyn_push_leaf(v, _DYN_K_BOOL, "", flag);
}

/// Push a NULL leaf (always true). Params: v - the tape.
/// Returns: the new node index. Error case: none. Complexity: O(1).
pub fn dynamo_value_push_null(v: &mut DynamoValue) -> Int {
  return _dyn_push_leaf(v, _DYN_K_NULL, "", 1);
}

/// Push a non-empty set of validated members. Params: v - the tape; kind -
/// SS, NS or BS; items - the member texts (numbers for NS, base64 for BS).
/// Returns: Ok(node). Error case: Err("dynamo: set kind must be SS, NS or
/// BS"), Err("dynamo: empty set"), Err("dynamo: duplicate set member") or
/// the dynamo_number_check / _b64_check catalogs.
/// Complexity: O(items^2 + total text).
pub fn dynamo_value_push_set(v: &mut DynamoValue, kind: Int, items: &Vec[Str]) -> Result[Int, Str] {
  if !dynamo_av_kind_is_set(kind) {
    return _err_int("dynamo: set kind must be SS, NS or BS");
  }
  if items.len() == 0 {
    return _err_int("dynamo: empty set");
  }
  var i = 0;
  while i < items.len() {
    let s: Str = items[i];
    if kind == _DYN_K_NS {
      let nchk = dynamo_number_check(s);
      if !nchk.is_ok {
        return _err_int(nchk.error);
      }
    }
    if kind == _DYN_K_BS {
      let bchk = _b64_check(s);
      if !bchk.is_ok {
        return _err_int(bchk.error);
      }
    }
    if _contains_text(items, s) && i > 0 {
      var first = -1;
      var j = 0;
      while j < i {
        let cur: Str = items[j];
        if compare.str_compare(cur, s) == 0 {
          first = j;
          break;
        }
        j = j + 1;
      }
      if first >= 0 {
        return _err_int("dynamo: duplicate set member");
      }
    }
    i = i + 1;
  }
  var kids = Vec[Int].new();
  var k = 0;
  while k < items.len() {
    let s2: Str = items[k];
    var kk = _DYN_K_S;
    if kind == _DYN_K_NS {
      kk = _DYN_K_N;
    }
    if kind == _DYN_K_BS {
      kk = _DYN_K_B;
    }
    kids.push(_dyn_push_leaf(v, kk, s2, 0));
    k = k + 1;
  }
  return _ok_int(_dyn_push_container(v, kind, &kids));
}

/// Push an L container over existing nodes. Params: v - the tape; items -
/// node indices (all < dynamo_value_count(v)). Returns: Ok(node).
/// Error case: Err("dynamo: list item is not a node index").
/// Complexity: O(items.len()).
pub fn dynamo_value_push_list(v: &mut DynamoValue, items: &Vec[Int]) -> Result[Int, Str] {
  var i = 0;
  while i < items.len() {
    let k: Int = items[i];
    if k < 0 || k >= v.kinds.len() {
      return _err_int("dynamo: list item is not a node index");
    }
    i = i + 1;
  }
  return _ok_int(_dyn_push_container(v, _DYN_K_L, items));
}

/// Push an M container. Params: v - the tape; keys - attribute names
/// (non-empty, unique); nodes - parallel value node indices.
/// Returns: Ok(node). Error case: Err("dynamo: map keys/values length
/// mismatch"), Err("dynamo: empty map key"), Err("dynamo: duplicate map
/// key"), Err("dynamo: map value is not a node index").
/// Complexity: O(keys^2 + keys).
pub fn dynamo_value_push_map(v: &mut DynamoValue, keys: &Vec[Str], nodes: &Vec[Int]) -> Result[Int, Str] {
  if keys.len() != nodes.len() {
    return _err_int("dynamo: map keys/values length mismatch");
  }
  var kids = Vec[Int].new();
  var i = 0;
  while i < keys.len() {
    let k: Str = keys[i];
    if k.len() == 0 {
      return _err_int("dynamo: empty map key");
    }
    if _contains_text(keys, k) {
      var first = -1;
      var j = 0;
      while j < i {
        let cur: Str = keys[j];
        if compare.str_compare(cur, k) == 0 {
          first = j;
          break;
        }
        j = j + 1;
      }
      if first >= 0 {
        return _err_int("dynamo: duplicate map key");
      }
    }
    let nd: Int = nodes[i];
    if nd < 0 || nd >= v.kinds.len() {
      return _err_int("dynamo: map value is not a node index");
    }
    i = i + 1;
  }
  var n2 = 0;
  while n2 < keys.len() {
    let k2: Str = keys[n2];
    let nd2: Int = nodes[n2];
    kids.push(_dyn_push_leaf(v, _DYN_K_KEY, k2, 0));
    kids.push(nd2);
    n2 = n2 + 1;
  }
  return _ok_int(_dyn_push_container(v, _DYN_K_M, &kids));
}

// --------------------------------------------------
//  JSON scanner (bounded, escape-aware, offset-diagnosed)
// --------------------------------------------------

fn _skip_ws(data: &Vec[UInt8], i: Int, end: Int) -> Int {
  var j = i;
  while j < end {
    let c = _vbyte(data, j);
    if c == _DYN_SPACE || c == _DYN_TAB || c == _DYN_LF || c == _DYN_CR {
      j = j + 1;
    } else {
      break;
    }
  }
  return j;
}

// Four hex digits at pos -> value; -1 when any byte is not a hex digit.
fn _hex4(data: &Vec[UInt8], pos: Int) -> Int {
  var v = 0;
  var i = 0;
  while i < 4 {
    let h = _hex_value(_vbyte(data, pos + i));
    if h < 0 {
      return -1;
    }
    v = (v << 4) | h;
    i = i + 1;
  }
  return v;
}

// UTF-8 encode one code point (<= 0x10FFFF, no surrogates) into out.
fn _push_utf8(out: &mut Vec[UInt8], cp: Int) {
  if cp < 128 {
    out.push(cp as UInt8);
  } elif cp < 2048 {
    out.push((192 | (cp >> 6)) as UInt8);
    out.push((128 | (cp & 63)) as UInt8);
  } elif cp < 65536 {
    out.push((224 | (cp >> 12)) as UInt8);
    out.push((128 | ((cp >> 6) & 63)) as UInt8);
    out.push((128 | (cp & 63)) as UInt8);
  } else {
    out.push((240 | (cp >> 18)) as UInt8);
    out.push((128 | ((cp >> 12) & 63)) as UInt8);
    out.push((128 | ((cp >> 6) & 63)) as UInt8);
    out.push((128 | (cp & 63)) as UInt8);
  }
}

// Decode the JSON string starting at data[pos] ('"') into out, decoding
// escapes to UTF-8 bytes; returns the position after the closing quote.
fn _decode_string(data: &Vec[UInt8], pos: Int, end: Int, what: Str, out: &mut Vec[UInt8]) -> Result[Int, Str] {
  if pos >= end {
    return _err_int(_perr(what + " truncated", pos));
  }
  if _vbyte(data, pos) != _DYN_QUOTE {
    return _err_int(_perr(what + " expected string", pos));
  }
  var i = pos + 1;
  while i < end {
    let c = _vbyte(data, i);
    if c == _DYN_QUOTE {
      return _ok_int(i + 1);
    }
    if c == _DYN_BACKSLASH {
      if i + 1 >= end {
        return _err_int(_perr(what + " truncated escape", i));
      }
      let e = _vbyte(data, i + 1);
      if e == _DYN_QUOTE || e == _DYN_BACKSLASH || e == _DYN_SLASH {
        out.push(e as UInt8);
        i = i + 2;
      } elif e == _DYN_LOWER_B {
        out.push(8 as UInt8);
        i = i + 2;
      } elif e == _DYN_LOWER_F {
        out.push(12 as UInt8);
        i = i + 2;
      } elif e == _DYN_LOWER_N {
        out.push(_DYN_LF as UInt8);
        i = i + 2;
      } elif e == _DYN_LOWER_R {
        out.push(_DYN_CR as UInt8);
        i = i + 2;
      } elif e == _DYN_LOWER_T {
        out.push(_DYN_TAB as UInt8);
        i = i + 2;
      } elif e == _DYN_LOWER_U {
        if i + 5 >= end {
          return _err_int(_perr(what + " truncated unicode escape", i));
        }
        let cp = _hex4(data, i + 2);
        if cp < 0 {
          return _err_int(_perr(what + " bad unicode escape", i + 2));
        }
        if cp == 0 {
          return _err_int(_perr(what + " unicode escape is NUL", i));
        }
        let next_i = i + 6;
        if cp >= 55296 && cp <= 56319 {
          if next_i + 5 >= end {
            return _err_int(_perr(what + " truncated surrogate pair", next_i));
          }
          if _vbyte(data, next_i) != _DYN_BACKSLASH || _vbyte(data, next_i + 1) != _DYN_LOWER_U {
            return _err_int(_perr(what + " lone surrogate", i));
          }
          let lo = _hex4(data, next_i + 2);
          if lo < 0 {
            return _err_int(_perr(what + " bad unicode escape", next_i + 2));
          }
          if lo < 56320 || lo > 57343 {
            return _err_int(_perr(what + " lone surrogate", i));
          }
          let combined = 65536 + ((cp - 55296) << 10) + (lo - 56320);
          _push_utf8(out, combined);
          i = i + 12;
        } elif cp >= 56320 && cp <= 57343 {
          return _err_int(_perr(what + " lone surrogate", i));
        } else {
          _push_utf8(out, cp);
          i = i + 6;
        }
      } else {
        return _err_int(_perr(what + " bad escape", i));
      }
    } elif c < _DYN_SPACE {
      return _err_int(_perr(what + " control byte in string", i));
    } else {
      out.push(c as UInt8);
      i = i + 1;
    }
  }
  return _err_int(_perr(what + " unterminated string", pos));
}

// Literal match at pos ("true"/"false").
fn _match_lit(data: &Vec[UInt8], pos: Int, end: Int, lit: Str) -> Bool {
  if pos + lit.len() > end {
    return false;
  }
  var i = 0;
  while i < lit.len() {
    if _vbyte(data, pos + i) != _byte(lit, i) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// Parse true/false at pos: (1|0, next position).
fn _parse_bool_literal(data: &Vec[UInt8], pos: Int, end: Int) -> Result[(Int, Int), Str] {
  if _match_lit(data, pos, end, "true") {
    return _ok_pair((1, pos + 4));
  }
  if _match_lit(data, pos, end, "false") {
    return _ok_pair((0, pos + 5));
  }
  return _err_pair(_perr("expected true or false", pos));
}

// Bounds-checked object/array open at pos.
fn _expect_byte(data: &Vec[UInt8], pos: Int, end: Int, want: Int, what: Str) -> Result[Int, Str] {
  if pos >= end {
    return _err_int(_perr(what + " truncated", pos));
  }
  if _vbyte(data, pos) != want {
    return _err_int(_perr(what, pos));
  }
  return _ok_int(pos + 1);
}

// Parse a set payload (array of strings) starting at '['; pushes members.
fn _parse_set(data: &Vec[UInt8], pos: Int, end: Int, kind: Int, t: &mut DynamoValue) -> Result[(Int, Int), Str] {
  let op = _expect_byte(data, pos, end, _DYN_LBRACKET, "set must be an array");
  if !op.is_ok {
    return _err_pair(op.error);
  }
  var i = _skip_ws(data, op.value, end);
  if i < end && _vbyte(data, i) == _DYN_RBRACKET {
    return _err_pair(_perr("empty set", pos));
  }
  var items = Vec[Str].new();
  var closed = false;
  while i < end && !closed {
    let item_pos = i;
    var sbuf = Vec[UInt8].new();
    let sr = _decode_string(data, i, end, "set member", &mut sbuf);
    if !sr.is_ok {
      return _err_pair(sr.error);
    }
    let text = builder.sb_to_str(&sbuf);
    if kind == _DYN_K_NS {
      let nchk = dynamo_number_check(text);
      if !nchk.is_ok {
        return _err_pair(nchk.error);
      }
    }
    if kind == _DYN_K_BS {
      let bchk = _b64_check(text);
      if !bchk.is_ok {
        return _err_pair(bchk.error);
      }
    }
    if _contains_text(items, text) {
      return _err_pair(_perr("duplicate set member", item_pos));
    }
    items.push(text);
    i = _skip_ws(data, sr.value, end);
    if i >= end {
      return _err_pair(_perr("truncated set", i));
    }
    let c = _vbyte(data, i);
    if c == _DYN_COMMA {
      i = _skip_ws(data, i + 1, end);
    } elif c == _DYN_RBRACKET {
      closed = true;
    } else {
      return _err_pair(_perr("expected ',' or ']' in set", i));
    }
  }
  if !closed {
    return _err_pair(_perr("truncated set", i));
  }
  var kids = Vec[Int].new();
  var k = 0;
  while k < items.len() {
    let s: Str = items[k];
    var kk = _DYN_K_S;
    if kind == _DYN_K_NS {
      kk = _DYN_K_N;
    }
    if kind == _DYN_K_BS {
      kk = _DYN_K_B;
    }
    kids.push(_dyn_push_leaf(t, kk, s, 0));
    k = k + 1;
  }
  let node = _dyn_push_container(t, kind, &kids);
  return _ok_pair((node, i + 1));
}

// Parse an L payload starting at '['.
fn _parse_list(data: &Vec[UInt8], pos: Int, end: Int, depth: Int, t: &mut DynamoValue) -> Result[(Int, Int), Str] {
  let op = _expect_byte(data, pos, end, _DYN_LBRACKET, "list must be an array");
  if !op.is_ok {
    return _err_pair(op.error);
  }
  var i = _skip_ws(data, op.value, end);
  var kids = Vec[Int].new();
  if i < end && _vbyte(data, i) == _DYN_RBRACKET {
    return _ok_pair((_dyn_push_container(t, _DYN_K_L, &kids), i + 1));
  }
  var closed = false;
  while i < end && !closed {
    let er = _parse_av(data, i, end, depth + 1, &mut t);
    if !er.is_ok {
      return _err_pair(er.error);
    }
    let esp = er.value;
    let child: Int = esp.0;
    let npos: Int = esp.1;
    kids.push(child);
    i = _skip_ws(data, npos, end);
    if i >= end {
      return _err_pair(_perr("truncated list", i));
    }
    let c = _vbyte(data, i);
    if c == _DYN_COMMA {
      i = _skip_ws(data, i + 1, end);
    } elif c == _DYN_RBRACKET {
      closed = true;
    } else {
      return _err_pair(_perr("expected ',' or ']' in list", i));
    }
  }
  if !closed {
    return _err_pair(_perr("truncated list", i));
  }
  let node = _dyn_push_container(t, _DYN_K_L, &kids);
  return _ok_pair((node, i + 1));
}

// Parse an M payload starting at '{' (also the item body).
fn _parse_map(data: &Vec[UInt8], pos: Int, end: Int, depth: Int, t: &mut DynamoValue) -> Result[(Int, Int), Str] {
  let op = _expect_byte(data, pos, end, _DYN_LBRACE, "map must be an object");
  if !op.is_ok {
    return _err_pair(op.error);
  }
  var i = _skip_ws(data, op.value, end);
  var kids = Vec[Int].new();
  var names = Vec[Str].new();
  var closed = false;
  if i < end && _vbyte(data, i) == _DYN_RBRACE {
    closed = true;
  }
  while i < end && !closed {
    let key_pos = i;
    var kbuf = Vec[UInt8].new();
    let kr = _decode_string(data, i, end, "map key", &mut kbuf);
    if !kr.is_ok {
      return _err_pair(kr.error);
    }
    let key = builder.sb_to_str(&kbuf);
    if key.len() == 0 {
      return _err_pair(_perr("empty attribute name", key_pos));
    }
    if _contains_text(names, key) {
      return _err_pair(_perr("duplicate attribute name", key_pos));
    }
    i = _skip_ws(data, kr.value, end);
    if i >= end || _vbyte(data, i) != _DYN_COLON {
      return _err_pair(_perr("expected ':' in map", i));
    }
    i = _skip_ws(data, i + 1, end);
    let vr = _parse_av(data, i, end, depth + 1, &mut t);
    if !vr.is_ok {
      return _err_pair(vr.error);
    }
    let vsp = vr.value;
    let vnode: Int = vsp.0;
    let vpos: Int = vsp.1;
    kids.push(_dyn_push_leaf(t, _DYN_K_KEY, key, 0));
    kids.push(vnode);
    names.push(key);
    i = _skip_ws(data, vpos, end);
    if i >= end {
      return _err_pair(_perr("truncated map", i));
    }
    let c = _vbyte(data, i);
    if c == _DYN_COMMA {
      i = _skip_ws(data, i + 1, end);
    } elif c == _DYN_RBRACE {
      closed = true;
    } else {
      return _err_pair(_perr("expected ',' or '}' in map", i));
    }
  }
  if !closed {
    return _err_pair(_perr("truncated map", i));
  }
  let node = _dyn_push_container(t, _DYN_K_M, &kids);
  return _ok_pair((node, i + 1));
}

// Parse one AttributeValue object starting at '{'.
fn _parse_av(data: &Vec[UInt8], pos: Int, end: Int, depth: Int, t: &mut DynamoValue) -> Result[(Int, Int), Str] {
  if depth > _DYN_MAX_DEPTH {
    return _err_pair(_perr("nesting too deep", pos));
  }
  let op = _expect_byte(data, pos, end, _DYN_LBRACE, "attribute value must be an object");
  if !op.is_ok {
    return _err_pair(op.error);
  }
  var i = _skip_ws(data, op.value, end);
  if i >= end {
    return _err_pair(_perr("truncated attribute value", i));
  }
  if _vbyte(data, i) == _DYN_RBRACE {
    return _err_pair(_perr("attribute value object is empty", i));
  }
  var kbuf = Vec[UInt8].new();
  let kr = _decode_string(data, i, end, "attribute value type", &mut kbuf);
  if !kr.is_ok {
    return _err_pair(kr.error);
  }
  let kind_name = builder.sb_to_str(&kbuf);
  let kind = _kind_of_name(kind_name);
  if kind == _DYN_K_UNKNOWN {
    return _err_pair(_perr("unknown attribute value type: " + kind_name, i));
  }
  var j = _skip_ws(data, kr.value, end);
  if j >= end || _vbyte(data, j) != _DYN_COLON {
    return _err_pair(_perr("expected ':'", j));
  }
  j = _skip_ws(data, j + 1, end);
  var result_node = 0;
  var after = j;
  if kind == _DYN_K_S || kind == _DYN_K_N || kind == _DYN_K_B {
    var sbuf = Vec[UInt8].new();
    let sr = _decode_string(data, j, end, "string value", &mut sbuf);
    if !sr.is_ok {
      return _err_pair(sr.error);
    }
    let text = builder.sb_to_str(&sbuf);
    if kind == _DYN_K_N {
      let nchk = dynamo_number_check(text);
      if !nchk.is_ok {
        return _err_pair(nchk.error);
      }
    }
    if kind == _DYN_K_B {
      let bchk = _b64_check(text);
      if !bchk.is_ok {
        return _err_pair(bchk.error);
      }
    }
    result_node = _dyn_push_leaf(t, kind, text, 0);
    after = sr.value;
  } elif kind == _DYN_K_NULL || kind == _DYN_K_BOOL {
    let lr = _parse_bool_literal(data, j, end);
    if !lr.is_ok {
      return _err_pair(lr.error);
    }
    let lsp = lr.value;
    let bval: Int = lsp.0;
    let npos: Int = lsp.1;
    if kind == _DYN_K_NULL {
      if bval != 1 {
        return _err_pair(_perr("NULL must be true", j));
      }
      result_node = _dyn_push_leaf(t, _DYN_K_NULL, "", 1);
    } else {
      result_node = _dyn_push_leaf(t, _DYN_K_BOOL, "", bval);
    }
    after = npos;
  } elif kind == _DYN_K_SS || kind == _DYN_K_NS || kind == _DYN_K_BS {
    let ar = _parse_set(data, j, end, kind, &mut t);
    if !ar.is_ok {
      return _err_pair(ar.error);
    }
    let asp = ar.value;
    let anode: Int = asp.0;
    let apos: Int = asp.1;
    result_node = anode;
    after = apos;
  } elif kind == _DYN_K_L {
    let lr2 = _parse_list(data, j, end, depth, &mut t);
    if !lr2.is_ok {
      return _err_pair(lr2.error);
    }
    let lsp2 = lr2.value;
    let lnode: Int = lsp2.0;
    let lpos: Int = lsp2.1;
    result_node = lnode;
    after = lpos;
  } elif kind == _DYN_K_M {
    let mr = _parse_map(data, j, end, depth, &mut t);
    if !mr.is_ok {
      return _err_pair(mr.error);
    }
    let msp = mr.value;
    let mnode: Int = msp.0;
    let mpos: Int = msp.1;
    result_node = mnode;
    after = mpos;
  }
  let k2 = _skip_ws(data, after, end);
  if k2 >= end || _vbyte(data, k2) != _DYN_RBRACE {
    return _err_pair(_perr("attribute value must close with '}'", k2));
  }
  return _ok_pair((result_node, k2 + 1));
}

/// Parse one AttributeValue object out of data[a, b).
/// Params: data - raw JSON bytes; a - start; b - end (exclusive).
/// Returns: Ok(item) whose root node is the attribute value.
/// Error case: offset-bearing "dynamo: ..." errors for malformed JSON,
/// unknown types, invalid numbers, invalid base64, NUL escapes, lone
/// surrogates, empty/duplicate names and deep nesting.
/// Complexity: O(b - a).
pub fn dynamo_av_parse(data: &Vec[UInt8], a: Int, b: Int) -> Result[DynamoItem, Str] {
  if a < 0 || b > data.len() || a > b {
    return _err_item(_perr("bad span", a));
  }
  if b - a > _DYN_MAX_JSON {
    return _err_item("dynamo: json too large");
  }
  var t = dynamo_value_new();
  let r = _parse_av(data, a, b, 0, &mut t);
  if !r.is_ok {
    return _err_item(r.error);
  }
  let sp = r.value;
  let node: Int = sp.0;
  let next: Int = sp.1;
  let tail = _skip_ws(data, next, b);
  if tail != b {
    return _err_item(_perr("trailing bytes after attribute value", tail));
  }
  return _ok_item(DynamoItem{ values: t; node: node; });
}

/// Parse one AttributeValue object out of a Str.
/// Params: s - the JSON text.
/// Returns: Ok(item); see dynamo_av_parse.
/// Error case: the dynamo_av_parse catalog.
/// Complexity: O(s.len()).
pub fn dynamo_av_parse_str(s: Str) -> Result[DynamoItem, Str] {
  let data = _bytes_of(s);
  let n = data.len();
  return dynamo_av_parse(&data, 0, n);
}

/// Parse one item (map of attribute name -> AttributeValue) out of
/// data[a, b). Params: data - raw JSON bytes; a - start; b - end.
/// Returns: Ok(item) whose root node is kind M.
/// Error case: the dynamo_av_parse catalog (empty/duplicate attribute
/// names included).
/// Complexity: O(b - a).
pub fn dynamo_item_parse(data: &Vec[UInt8], a: Int, b: Int) -> Result[DynamoItem, Str] {
  if a < 0 || b > data.len() || a > b {
    return _err_item(_perr("bad span", a));
  }
  if b - a > _DYN_MAX_JSON {
    return _err_item("dynamo: json too large");
  }
  var t = dynamo_value_new();
  let r = _parse_map(data, a, b, 0, &mut t);
  if !r.is_ok {
    return _err_item(r.error);
  }
  let sp = r.value;
  let node: Int = sp.0;
  let next: Int = sp.1;
  let tail = _skip_ws(data, next, b);
  if tail != b {
    return _err_item(_perr("trailing bytes after item", tail));
  }
  return _ok_item(DynamoItem{ values: t; node: node; });
}

/// Parse one item out of a Str. Params: s - the JSON text.
/// Returns: Ok(item). Error case: the dynamo_item_parse catalog.
/// Complexity: O(s.len()).
pub fn dynamo_item_parse_str(s: Str) -> Result[DynamoItem, Str] {
  let data = _bytes_of(s);
  let n = data.len();
  return dynamo_item_parse(&data, 0, n);
}

// --------------------------------------------------
//  Name and size validation
// --------------------------------------------------

// True for [a-zA-Z0-9_.-].
fn _is_name_char(c: Int) -> Bool {
  if _is_alpha(c) {
    return true;
  }
  if _is_digit(c) {
    return true;
  }
  if c == _DYN_UNDERSCORE || c == _DYN_DOT || c == _DYN_MINUS {
    return true;
  }
  return false;
}

// Shared 3..255 charset check; `what` names the context in errors.
fn _name_check(what: Str, name: Str) -> Result[Str, Str] {
  let n = name.len();
  if n < _DYN_NAME_MIN || n > _DYN_NAME_MAX {
    return _err_str("dynamo: " + what + " name length must be 3..255");
  }
  var i = 0;
  while i < n {
    if !_is_name_char(_byte(name, i)) {
      return _err_str(_perr(what + " name invalid character", i));
    }
    i = i + 1;
  }
  return _ok_str("");
}

/// Validate a DynamoDB table name: 3..255 characters of [a-zA-Z0-9_.-].
/// Params: name - the candidate. Returns: Ok("") when valid.
/// Error case: Err("dynamo: table name length must be 3..255") or
/// Err("dynamo: table name invalid character at offset N").
/// Complexity: O(name.len()).
pub fn dynamo_table_name_check(name: Str) -> Result[Str, Str] {
  return _name_check("table", name);
}

/// True when name is a valid table name. Params: name - the candidate.
/// Returns: the predicate. Error case: none. Complexity: O(name.len()).
pub fn dynamo_table_name_is_valid(name: Str) -> Bool {
  let r = _name_check("table", name);
  return r.is_ok;
}

/// Validate a DynamoDB key attribute name: 3..255 characters of
/// [a-zA-Z0-9_.-]. Params: name - the candidate. Returns: Ok("").
/// Error case: Err("dynamo: key name length must be 3..255") or
/// Err("dynamo: key name invalid character at offset N").
/// Complexity: O(name.len()).
pub fn dynamo_key_name_check(name: Str) -> Result[Str, Str] {
  return _name_check("key", name);
}

/// True when name is a valid key attribute name. Params: name - the
/// candidate. Returns: the predicate. Error case: none.
/// Complexity: O(name.len()).
pub fn dynamo_key_name_is_valid(name: Str) -> Bool {
  let r = _name_check("key", name);
  return r.is_ok;
}

/// Enforce the 400KB item cap over data[a, b).
/// Params: data - the wire bytes; a - start; b - end.
/// Returns: Ok(size) when within the cap.
/// Error case: Err("dynamo: item exceeds 400KB (409600 bytes) at offset
/// 409600") or Err("dynamo: bad span at offset a").
/// Complexity: O(1).
pub fn dynamo_item_check(data: &Vec[UInt8], a: Int, b: Int) -> Result[Int, Str] {
  if a < 0 || b > data.len() || a > b {
    return _err_int(_perr("bad span", a));
  }
  let n = b - a;
  if n > _DYN_ITEM_MAX {
    return _err_int(_perr("item exceeds 400KB (409600 bytes)", _DYN_ITEM_MAX));
  }
  return _ok_int(n);
}

// --------------------------------------------------
//  Canonical render
// --------------------------------------------------

// Append s as a JSON string literal: '"' and '\' escaped, C0 controls as
// \b \f \n \r \t or \u00XX. Bytes >= 0x20 are copied verbatim.
fn _push_json_string(out: &mut Vec[UInt8], s: Str) {
  out.push(_DYN_QUOTE as UInt8);
  var i = 0;
  while i < s.len() {
    let c = _byte(s, i);
    if c == _DYN_QUOTE {
      out.push(_DYN_BACKSLASH as UInt8);
      out.push(_DYN_QUOTE as UInt8);
    } elif c == _DYN_BACKSLASH {
      out.push(_DYN_BACKSLASH as UInt8);
      out.push(_DYN_BACKSLASH as UInt8);
    } elif c == _DYN_LF {
      out.push(_DYN_BACKSLASH as UInt8);
      out.push(_DYN_LOWER_N as UInt8);
    } elif c == _DYN_CR {
      out.push(_DYN_BACKSLASH as UInt8);
      out.push(_DYN_LOWER_R as UInt8);
    } elif c == _DYN_TAB {
      out.push(_DYN_BACKSLASH as UInt8);
      out.push(_DYN_LOWER_T as UInt8);
    } elif c == 8 {
      out.push(_DYN_BACKSLASH as UInt8);
      out.push(_DYN_LOWER_B as UInt8);
    } elif c == 12 {
      out.push(_DYN_BACKSLASH as UInt8);
      out.push(_DYN_LOWER_F as UInt8);
    } elif c < _DYN_SPACE {
      out.push(_DYN_BACKSLASH as UInt8);
      out.push(_DYN_LOWER_U as UInt8);
      out.push(48 as UInt8);
      out.push(48 as UInt8);
      out.push(_hex_upper(c >> 4));
      out.push(_hex_upper(c & 15));
    } else {
      out.push(string.byte_at(s, i));
    }
    i = i + 1;
  }
  out.push(_DYN_QUOTE as UInt8);
}

// Text of a node as a typed local copy.
fn _str_at(v: &DynamoValue, node: Int) -> Str {
  let s: Str = v.texts[node];
  return s;
}

// Canonical AttributeValue rendering of one node into out.
fn _render_into(v: &DynamoValue, node: Int, out: &mut Vec[UInt8]) {
  let kind: Int = v.kinds[node];
  if kind == _DYN_K_S {
    builder.sb_push_str(out, "{\"S\":");
    _push_json_string(out, _str_at(v, node));
    out.push(_DYN_RBRACE as UInt8);
  } elif kind == _DYN_K_N {
    builder.sb_push_str(out, "{\"N\":");
    _push_json_string(out, _str_at(v, node));
    out.push(_DYN_RBRACE as UInt8);
  } elif kind == _DYN_K_B {
    builder.sb_push_str(out, "{\"B\":");
    _push_json_string(out, _str_at(v, node));
    out.push(_DYN_RBRACE as UInt8);
  } elif kind == _DYN_K_SS {
    _render_set_into(v, node, out, "{\"SS\":[");
  } elif kind == _DYN_K_NS {
    _render_set_into(v, node, out, "{\"NS\":[");
  } elif kind == _DYN_K_BS {
    _render_set_into(v, node, out, "{\"BS\":[");
  } elif kind == _DYN_K_M {
    builder.sb_push_str(out, "{\"M\":");
    _render_map_body(v, node, out);
    out.push(_DYN_RBRACE as UInt8);
  } elif kind == _DYN_K_L {
    builder.sb_push_str(out, "{\"L\":[");
    let count: Int = v.counts[node];
    let start: Int = v.starts[node];
    var i = 0;
    while i < count {
      if i > 0 {
        out.push(_DYN_COMMA as UInt8);
      }
      let pos = start + i;
      let child: Int = v.children[pos];
      _render_into(v, child, &mut out);
      i = i + 1;
    }
    builder.sb_push_str(out, "]}");
  } elif kind == _DYN_K_NULL {
    builder.sb_push_str(out, "{\"NULL\":true}");
  } elif kind == _DYN_K_BOOL {
    let f: Int = v.flags[node];
    if f == 1 {
      builder.sb_push_str(out, "{\"BOOL\":true}");
    } else {
      builder.sb_push_str(out, "{\"BOOL\":false}");
    }
  } else {
    builder.sb_push_str(out, "{\"NULL\":true}");
  }
}

// Set body rendering: prefix is the open text, e.g. "{\"SS\":[".
fn _render_set_into(v: &DynamoValue, node: Int, out: &mut Vec[UInt8], prefix: Str) {
  builder.sb_push_str(out, prefix);
  let count: Int = v.counts[node];
  let start: Int = v.starts[node];
  var i = 0;
  while i < count {
    if i > 0 {
      out.push(_DYN_COMMA as UInt8);
    }
    let pos = start + i;
    let child: Int = v.children[pos];
    _push_json_string(out, _str_at(v, child));
    i = i + 1;
  }
  builder.sb_push_str(out, "]}");
}

// Bare map body rendering: {...} of key -> AttributeValue.
fn _render_map_body(v: &DynamoValue, node: Int, out: &mut Vec[UInt8]) {
  out.push(_DYN_LBRACE as UInt8);
  let count: Int = v.counts[node];
  let start: Int = v.starts[node];
  let len = count / 2;
  var i = 0;
  while i < len {
    if i > 0 {
      out.push(_DYN_COMMA as UInt8);
    }
    let kpos = start + i * 2;
    let kn: Int = v.children[kpos];
    _push_json_string(out, _str_at(v, kn));
    out.push(_DYN_COLON as UInt8);
    let vn: Int = v.children[kpos + 1];
    _render_into(v, vn, &mut out);
    i = i + 1;
  }
  out.push(_DYN_RBRACE as UInt8);
}

/// Canonical AttributeValue rendering of a node in a tape.
/// Params: v - the tape; node - the node index.
/// Returns: the JSON text ("" for an out-of-range node).
/// Error case: none. Complexity: O(subtree).
pub fn dynamo_value_render(v: &DynamoValue, node: Int) -> Str {
  if node < 0 || node >= v.kinds.len() {
    return "";
  }
  var out = Vec[UInt8].new();
  _render_into(v, node, &mut out);
  return builder.sb_to_str(&out);
}

/// Canonical AttributeValue rendering of an item's root node.
/// Params: item - the item. Returns: the JSON text ("" when absent).
/// Error case: none. Complexity: O(subtree).
pub fn dynamo_av_render(item: &DynamoItem) -> Str {
  let present = dynamo_item_present(item);
  if !present {
    return "";
  }
  let t: DynamoValue = item.values;
  let n: Int = item.node;
  return dynamo_value_render(&t, n);
}

/// Canonical item rendering: the bare map body {...} for an M root, or the
/// AttributeValue text for any other root.
/// Params: item - the item. Returns: the JSON text ("" when absent).
/// Error case: none. Complexity: O(subtree).
pub fn dynamo_item_render(item: &DynamoItem) -> Str {
  let present = dynamo_item_present(item);
  if !present {
    return "";
  }
  let t: DynamoValue = item.values;
  let n: Int = item.node;
  let kind: Int = t.kinds[n];
  var out = Vec[UInt8].new();
  if kind == _DYN_K_M {
    _render_map_body(&t, n, &mut out);
  } else {
    _render_into(&t, n, &mut out);
  }
  return builder.sb_to_str(&out);
}

// --------------------------------------------------
//  Typed accessors
// --------------------------------------------------

/// True when the item node is inside its tape (node >= 0).
/// Params: item - the item. Returns: the predicate.
/// Error case: none. Complexity: O(1).
pub fn dynamo_item_present(item: &DynamoItem) -> Bool {
  let t: DynamoValue = item.values;
  let n: Int = item.node;
  if n < 0 {
    return false;
  }
  if n >= t.kinds.len() {
    return false;
  }
  return true;
}

/// Kind id of the item node; -1 when absent.
/// Params: item - the item. Returns: the kind id.
/// Error case: none. Complexity: O(1).
pub fn dynamo_item_kind(item: &DynamoItem) -> Int {
  let t: DynamoValue = item.values;
  let n: Int = item.node;
  if n < 0 || n >= t.kinds.len() {
    return _DYN_K_UNKNOWN;
  }
  let k: Int = t.kinds[n];
  return k;
}

/// Wire name of the item kind. Params: item - the item.
/// Returns: "S".."BOOL", "KEY" or "UNKNOWN". Error case: none.
/// Complexity: O(1).
pub fn dynamo_item_kind_name(item: &DynamoItem) -> Str {
  return dynamo_av_kind_name(dynamo_item_kind(item));
}

/// True when the item root is an M. Params: item - the item.
/// Returns: the predicate. Error case: none. Complexity: O(1).
pub fn dynamo_item_is_map(item: &DynamoItem) -> Bool {
  if dynamo_item_kind(item) == _DYN_K_M {
    return true;
  }
  return false;
}

// Text of the item node ("" when absent).
fn _item_text(item: &DynamoItem) -> Str {
  let t: DynamoValue = item.values;
  let n: Int = item.node;
  if n < 0 || n >= t.texts.len() {
    return "";
  }
  let s: Str = t.texts[n];
  return s;
}

// Count field of the item node (0 when absent).
fn _item_count(item: &DynamoItem) -> Int {
  let t: DynamoValue = item.values;
  let n: Int = item.node;
  if n < 0 || n >= t.counts.len() {
    return 0;
  }
  let c: Int = t.counts[n];
  return c;
}

// Child i of the item node, or -1 when out of range.
fn _item_child(item: &DynamoItem, i: Int) -> Int {
  let t: DynamoValue = item.values;
  let n: Int = item.node;
  if n < 0 || n >= t.starts.len() {
    return -1;
  }
  let start: Int = t.starts[n];
  let count: Int = t.counts[n];
  if i < 0 || i >= count {
    return -1;
  }
  let pos = start + i;
  if pos < 0 || pos >= t.children.len() {
    return -1;
  }
  let c: Int = t.children[pos];
  return c;
}

/// S text of the item ("" unless kind S). Params: item - the item.
/// Returns: the string. Error case: none. Complexity: O(1).
pub fn dynamo_item_string(item: &DynamoItem) -> Str {
  if dynamo_item_kind(item) != _DYN_K_S {
    return "";
  }
  return _item_text(item);
}

/// N text of the item ("" unless kind N). Params: item - the item.
/// Returns: the number text. Error case: none. Complexity: O(1).
pub fn dynamo_item_number_text(item: &DynamoItem) -> Str {
  if dynamo_item_kind(item) != _DYN_K_N {
    return "";
  }
  return _item_text(item);
}

/// B base64 text of the item ("" unless kind B). Params: item - the item.
/// Returns: the base64 text. Error case: none. Complexity: O(1).
pub fn dynamo_item_binary_text(item: &DynamoItem) -> Str {
  if dynamo_item_kind(item) != _DYN_K_B {
    return "";
  }
  return _item_text(item);
}

/// BOOL value of the item (false unless kind BOOL).
/// Params: item - the item. Returns: the value.
/// Error case: none. Complexity: O(1).
pub fn dynamo_item_bool(item: &DynamoItem) -> Bool {
  if dynamo_item_kind(item) != _DYN_K_BOOL {
    return false;
  }
  let t: DynamoValue = item.values;
  let n: Int = item.node;
  if n < 0 || n >= t.flags.len() {
    return false;
  }
  let f: Int = t.flags[n];
  if f == 1 {
    return true;
  }
  return false;
}

/// True when the item is NULL (always stored as true).
/// Params: item - the item. Returns: the predicate.
/// Error case: none. Complexity: O(1).
pub fn dynamo_item_is_null(item: &DynamoItem) -> Bool {
  if dynamo_item_kind(item) == _DYN_K_NULL {
    return true;
  }
  return false;
}

/// Number of map entries (0 unless kind M). Params: item - the item.
/// Returns: the entry count. Error case: none. Complexity: O(1).
pub fn dynamo_item_map_len(item: &DynamoItem) -> Int {
  if dynamo_item_kind(item) != _DYN_K_M {
    return 0;
  }
  return _item_count(item) / 2;
}

/// Attribute name of map entry i ("" when out of range).
/// Params: item - the item; i - the entry index.
/// Returns: the name. Error case: none. Complexity: O(1).
pub fn dynamo_item_map_key_at(item: &DynamoItem, i: Int) -> Str {
  let kn = _item_child(item, i * 2);
  if kn < 0 {
    return "";
  }
  let t: DynamoValue = item.values;
  if kn >= t.kinds.len() {
    return "";
  }
  let s: Str = t.texts[kn];
  return s;
}

/// Value node index of map entry i (-1 when out of range).
/// Params: item - the item; i - the entry index.
/// Returns: the node index. Error case: none. Complexity: O(1).
pub fn dynamo_item_map_node_at(item: &DynamoItem, i: Int) -> Int {
  return _item_child(item, i * 2 + 1);
}

/// Value node index of the first map entry named key (-1 when absent).
/// Params: item - the item; key - the attribute name.
/// Returns: the node index. Error case: none.
/// Complexity: O(map_len).
pub fn dynamo_item_map_get_node(item: &DynamoItem, key: Str) -> Int {
  let len = dynamo_item_map_len(item);
  var i = 0;
  while i < len {
    let k: Str = dynamo_item_map_key_at(item, i);
    if compare.str_compare(k, key) == 0 {
      return dynamo_item_map_node_at(item, i);
    }
    i = i + 1;
  }
  return -1;
}

/// First map entry named key as an item (node -1 when absent).
/// Params: item - the item; key - the attribute name.
/// Returns: the entry item. Error case: none. Complexity: O(map_len).
pub fn dynamo_item_map_get(item: &DynamoItem, key: Str) -> DynamoItem {
  let n = dynamo_item_map_get_node(item, key);
  let t: DynamoValue = item.values;
  return DynamoItem{ values: t; node: n; };
}

/// Number of list elements (0 unless kind L). Params: item - the item.
/// Returns: the element count. Error case: none. Complexity: O(1).
pub fn dynamo_item_list_len(item: &DynamoItem) -> Int {
  if dynamo_item_kind(item) != _DYN_K_L {
    return 0;
  }
  return _item_count(item);
}

/// Element node index i (-1 when out of range). Params: item - the item;
/// i - the element index. Returns: the node index. Error case: none.
/// Complexity: O(1).
pub fn dynamo_item_list_node_at(item: &DynamoItem, i: Int) -> Int {
  return _item_child(item, i);
}

/// Element i as an item (node -1 when out of range). Params: item - the
/// item; i - the element index. Returns: the element item.
/// Error case: none. Complexity: O(1).
pub fn dynamo_item_list_get(item: &DynamoItem, i: Int) -> DynamoItem {
  let n = dynamo_item_list_node_at(item, i);
  let t: DynamoValue = item.values;
  return DynamoItem{ values: t; node: n; };
}

/// Number of set members (0 unless kind SS/NS/BS). Params: item - the item.
/// Returns: the member count. Error case: none. Complexity: O(1).
pub fn dynamo_item_set_len(item: &DynamoItem) -> Int {
  let kind = dynamo_item_kind(item);
  if !dynamo_av_kind_is_set(kind) {
    return 0;
  }
  return _item_count(item);
}

/// Member text i of a set ("" when out of range). Params: item - the item;
/// i - the member index. Returns: the member text (number or base64 text
/// for NS/BS). Error case: none. Complexity: O(1).
pub fn dynamo_item_set_text_at(item: &DynamoItem, i: Int) -> Str {
  let cn = _item_child(item, i);
  if cn < 0 {
    return "";
  }
  let t: DynamoValue = item.values;
  if cn >= t.kinds.len() {
    return "";
  }
  let s: Str = t.texts[cn];
  return s;
}

/// Decoded bytes of a B item. Params: item - the item.
/// Returns: Ok(bytes). Error case: Err("dynamo: value is not a B attribute
/// value") or the dynamo_base64_decode catalog.
/// Complexity: O(text).
pub fn dynamo_item_binary(item: &DynamoItem) -> Result[Vec[UInt8], Str] {
  if dynamo_item_kind(item) != _DYN_K_B {
    return _err_bytes("dynamo: value is not a B attribute value");
  }
  let s = _item_text(item);
  return dynamo_base64_decode(s);
}

// Position of the first fraction '.' of a number text, or -1.
fn _number_dot(text: Str) -> Int {
  var i = 0;
  while i < text.len() {
    if _byte(text, i) == _DYN_DOT {
      return i;
    }
    if _byte(text, i) == _DYN_LOWER_E || _byte(text, i) == _DYN_UPPER_E {
      return -1;
    }
    i = i + 1;
  }
  return -1;
}

// Position of the 'e'/'E' of a number text, or -1.
fn _number_exp(text: Str) -> Int {
  var i = 0;
  while i < text.len() {
    let c = _byte(text, i);
    if c == _DYN_LOWER_E || c == _DYN_UPPER_E {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

/// Integer part text of an N item ("-12" for "-12.34e5"; "" unless a
/// valid N). Params: item - the item. Returns: sign + integer digits.
/// Error case: none. Complexity: O(text).
pub fn dynamo_item_number_int_text(item: &DynamoItem) -> Str {
  if dynamo_item_kind(item) != _DYN_K_N {
    return "";
  }
  let s = _item_text(item);
  let chk = dynamo_number_check(s);
  if !chk.is_ok {
    return "";
  }
  var i = 0;
  if _byte(s, 0) == _DYN_PLUS || _byte(s, 0) == _DYN_MINUS {
    i = 1;
  }
  while i < s.len() && _is_digit(_byte(s, i)) {
    i = i + 1;
  }
  return string.str_slice(s, 0, i);
}

/// Fraction digits of an N item without the dot ("34" for "-12.34e5";
/// "" when absent or not a valid N). Params: item - the item.
/// Returns: the fraction digits. Error case: none. Complexity: O(text).
pub fn dynamo_item_number_frac_text(item: &DynamoItem) -> Str {
  if dynamo_item_kind(item) != _DYN_K_N {
    return "";
  }
  let s = _item_text(item);
  let chk = dynamo_number_check(s);
  if !chk.is_ok {
    return "";
  }
  let dot = _number_dot(s);
  if dot < 0 {
    return "";
  }
  var i = dot + 1;
  while i < s.len() && _is_digit(_byte(s, i)) {
    i = i + 1;
  }
  return string.str_slice(s, dot + 1, i);
}

/// Exponent text of an N item after 'e'/'E' (sign included; "" when
/// absent or not a valid N). Params: item - the item.
/// Returns: the exponent digits. Error case: none. Complexity: O(text).
pub fn dynamo_item_number_exp_text(item: &DynamoItem) -> Str {
  if dynamo_item_kind(item) != _DYN_K_N {
    return "";
  }
  let s = _item_text(item);
  let chk = dynamo_number_check(s);
  if !chk.is_ok {
    return "";
  }
  let e = _number_exp(s);
  if e < 0 {
    return "";
  }
  return string.str_slice(s, e + 1, s.len());
}

// --------------------------------------------------
//  Request rendering helpers
// --------------------------------------------------

// Append `,"name":<json string>`; returns the new first flag (false).
fn _push_member_str(out: &mut Vec[UInt8], first: Bool, name: Str, value: Str) -> Bool {
  if !first {
    out.push(_DYN_COMMA as UInt8);
  }
  _push_json_string(out, name);
  out.push(_DYN_COLON as UInt8);
  _push_json_string(out, value);
  return false;
}

// Append `,"name":<raw json>`; returns the new first flag (false).
fn _push_member_raw(out: &mut Vec[UInt8], first: Bool, name: Str, raw: Str) -> Bool {
  if !first {
    out.push(_DYN_COMMA as UInt8);
  }
  _push_json_string(out, name);
  out.push(_DYN_COLON as UInt8);
  builder.sb_push_str(out, raw);
  return false;
}

// Append `,"name":<attribute value>` for an item root; returns first flag.
fn _push_member_av(out: &mut Vec[UInt8], first: Bool, name: Str, item: &DynamoItem) -> Bool {
  if !first {
    out.push(_DYN_COMMA as UInt8);
  }
  _push_json_string(out, name);
  out.push(_DYN_COLON as UInt8);
  let t: DynamoValue = item.values;
  let n: Int = item.node;
  _render_into(&t, n, &mut out);
  return false;
}

// Append `,"name":<bare map body>` for an item root; returns first flag.
fn _push_member_item(out: &mut Vec[UInt8], first: Bool, name: Str, item: &DynamoItem) -> Bool {
  if !first {
    out.push(_DYN_COMMA as UInt8);
  }
  _push_json_string(out, name);
  out.push(_DYN_COLON as UInt8);
  let t: DynamoValue = item.values;
  let n: Int = item.node;
  _render_map_body(&t, n, &mut out);
  return false;
}

// "true" / "false".
fn _bool_text(b: Bool) -> Str {
  if b {
    return "true";
  }
  return "false";
}

// True for the three AttributeUpdates actions.
fn _action_is_valid(action: Str) -> Bool {
  if _streq(action, "PUT") {
    return true;
  }
  if _streq(action, "DELETE") {
    return true;
  }
  if _streq(action, "ADD") {
    return true;
  }
  return false;
}

// Validate that an item is a present map (Key / Item payloads).
fn _item_map_check(item: &DynamoItem, what: Str) -> Result[Str, Str] {
  if !dynamo_item_present(item) {
    return _err_str("dynamo: " + what + " is missing");
  }
  if !dynamo_item_is_map(item) {
    return _err_str("dynamo: " + what + " must be a map item");
  }
  return _ok_str("");
}

// --------------------------------------------------
//  UpdateItem AttributeUpdates
// --------------------------------------------------

/// Legacy UpdateItem AttributeUpdates: per-name {Value, Action} entries.
/// The values live in one merged tape; value_nodes[i] is the node of
/// names[i] / actions[i].
pub type DynamoAttributeUpdates = {
  names: Vec[Str];
  actions: Vec[Str];
  values: DynamoValue;
  value_nodes: Vec[Int];
}

/// A fresh empty AttributeUpdates map. Params: none. Returns: the map.
/// Error case: none. Complexity: O(1).
pub fn dynamo_attribute_updates_new() -> DynamoAttributeUpdates {
  return DynamoAttributeUpdates{
    names: Vec[Str].new();
    actions: Vec[Str].new();
    values: dynamo_value_new();
    value_nodes: Vec[Int].new();
  };
}

/// Number of update entries. Params: u - the map. Returns: the count.
/// Error case: none. Complexity: O(1).
pub fn dynamo_attribute_updates_count(u: &DynamoAttributeUpdates) -> Int {
  return u.names.len();
}

/// Add one entry. Params: u - the map; name - the attribute name (unique,
/// non-empty); action - "PUT", "DELETE" or "ADD"; value - the value item.
/// Returns: Ok(""). Error case: Err("dynamo: empty attribute name"), Err(
/// "dynamo: attribute update action must be PUT, DELETE or ADD"), Err(
/// "dynamo: attribute update value is missing"), Err("dynamo: duplicate
/// attribute update: <name>").
/// Complexity: O(u.names.len()).
pub fn dynamo_attribute_updates_add(u: &mut DynamoAttributeUpdates, name: Str, action: Str, value: &DynamoItem) -> Result[Str, Str] {
  if name.len() == 0 {
    return _err_str("dynamo: empty attribute name");
  }
  if !_action_is_valid(action) {
    return _err_str("dynamo: attribute update action must be PUT, DELETE or ADD");
  }
  if !dynamo_item_present(value) {
    return _err_str("dynamo: attribute update value is missing");
  }
  var i = 0;
  while i < u.names.len() {
    let cur: Str = u.names[i];
    if compare.str_compare(cur, name) == 0 {
      return _err_str("dynamo: duplicate attribute update: " + name);
    }
    i = i + 1;
  }
  let vnode0 = dynamo_item_node(value);
  let vtape: DynamoValue = value.values;
  var tape: DynamoValue = u.values;
  let off = dynamo_value_merge(&mut tape, &vtape);
  u.values = tape;
  u.names.push(name);
  u.actions.push(action);
  u.value_nodes.push(vnode0 + off);
  return _ok_str("");
}

// Render {"name":{"Value":<av>,"Action":"PUT"},...}.
fn _render_attribute_updates(u: &DynamoAttributeUpdates) -> Str {
  var out = Vec[UInt8].new();
  out.push(_DYN_LBRACE as UInt8);
  let tape: DynamoValue = u.values;
  var i = 0;
  while i < u.names.len() {
    if i > 0 {
      out.push(_DYN_COMMA as UInt8);
    }
    let name: Str = u.names[i];
    let action: Str = u.actions[i];
    let node: Int = u.value_nodes[i];
    _push_json_string(&mut out, name);
    builder.sb_push_str(&mut out, ":{\"Value\":");
    _render_into(&tape, node, &mut out);
    builder.sb_push_str(&mut out, ",\"Action\":");
    _push_json_string(&mut out, action);
    out.push(_DYN_RBRACE as UInt8);
    i = i + 1;
  }
  out.push(_DYN_RBRACE as UInt8);
  return builder.sb_to_str(&out);
}

// --------------------------------------------------
//  Expression attribute name/value maps
// --------------------------------------------------

/// ExpressionAttributeNames: placeholder -> real attribute name.
pub type DynamoNameMap = {
  keys: Vec[Str];
  values: Vec[Str];
}

/// A fresh empty name map. Params: none. Returns: the map.
/// Error case: none. Complexity: O(1).
pub fn dynamo_name_map_new() -> DynamoNameMap {
  return DynamoNameMap{ keys: Vec[Str].new(); values: Vec[Str].new(); };
}

/// Number of name entries. Params: m - the map. Returns: the count.
/// Error case: none. Complexity: O(1).
pub fn dynamo_name_map_count(m: &DynamoNameMap) -> Int {
  return m.keys.len();
}

/// Add one name binding. Params: m - the map; key - the "#alias"
/// placeholder (non-empty, unique); value - the attribute name.
/// Returns: Ok(""). Error case: Err("dynamo: empty expression attribute
/// name placeholder"), Err("dynamo: duplicate expression attribute name
/// placeholder: <key>").
/// Complexity: O(m.keys.len()).
pub fn dynamo_name_map_add(m: &mut DynamoNameMap, key: Str, value: Str) -> Result[Str, Str] {
  if key.len() == 0 {
    return _err_str("dynamo: empty expression attribute name placeholder");
  }
  var i = 0;
  while i < m.keys.len() {
    let cur: Str = m.keys[i];
    if compare.str_compare(cur, key) == 0 {
      return _err_str("dynamo: duplicate expression attribute name placeholder: " + key);
    }
    i = i + 1;
  }
  m.keys.push(key);
  m.values.push(value);
  return _ok_str("");
}

// Render {"#alias":"name",...}.
fn _render_name_map(m: &DynamoNameMap) -> Str {
  var out = Vec[UInt8].new();
  out.push(_DYN_LBRACE as UInt8);
  var i = 0;
  while i < m.values.len() {
    if i > 0 {
      out.push(_DYN_COMMA as UInt8);
    }
    let k: Str = m.keys[i];
    let v: Str = m.values[i];
    _push_json_string(&mut out, k);
    out.push(_DYN_COLON as UInt8);
    _push_json_string(&mut out, v);
    i = i + 1;
  }
  out.push(_DYN_RBRACE as UInt8);
  return builder.sb_to_str(&out);
}

/// ExpressionAttributeValues: ":placeholder" -> AttributeValue, with all
/// values merged into one tape.
pub type DynamoValueMap = {
  keys: Vec[Str];
  values: DynamoValue;
  value_nodes: Vec[Int];
}

/// A fresh empty value map. Params: none. Returns: the map.
/// Error case: none. Complexity: O(1).
pub fn dynamo_value_map_new() -> DynamoValueMap {
  return DynamoValueMap{
    keys: Vec[Str].new();
    values: dynamo_value_new();
    value_nodes: Vec[Int].new();
  };
}

/// Number of value entries. Params: m - the map. Returns: the count.
/// Error case: none. Complexity: O(1).
pub fn dynamo_value_map_count(m: &DynamoValueMap) -> Int {
  return m.keys.len();
}

/// Add one value binding. Params: m - the map; key - the ":placeholder"
/// (non-empty, unique); value - the attribute value item.
/// Returns: Ok(""). Error case: Err("dynamo: empty expression attribute
/// value placeholder"), Err("dynamo: duplicate expression attribute value
/// placeholder: <key>"), Err("dynamo: expression attribute value is
/// missing").
/// Complexity: O(m.keys.len()).
pub fn dynamo_value_map_add(m: &mut DynamoValueMap, key: Str, value: &DynamoItem) -> Result[Str, Str] {
  if key.len() == 0 {
    return _err_str("dynamo: empty expression attribute value placeholder");
  }
  if !dynamo_item_present(value) {
    return _err_str("dynamo: expression attribute value is missing");
  }
  var i = 0;
  while i < m.keys.len() {
    let cur: Str = m.keys[i];
    if compare.str_compare(cur, key) == 0 {
      return _err_str("dynamo: duplicate expression attribute value placeholder: " + key);
    }
    i = i + 1;
  }
  let vnode0 = dynamo_item_node(value);
  let vtape: DynamoValue = value.values;
  var tape: DynamoValue = m.values;
  let off = dynamo_value_merge(&mut tape, &vtape);
  m.values = tape;
  m.keys.push(key);
  m.value_nodes.push(vnode0 + off);
  return _ok_str("");
}

// Render {":placeholder":<av>,...}.
fn _render_value_map(m: &DynamoValueMap) -> Str {
  var out = Vec[UInt8].new();
  out.push(_DYN_LBRACE as UInt8);
  let tape: DynamoValue = m.values;
  var i = 0;
  while i < m.keys.len() {
    if i > 0 {
      out.push(_DYN_COMMA as UInt8);
    }
    let k: Str = m.keys[i];
    let node: Int = m.value_nodes[i];
    _push_json_string(&mut out, k);
    out.push(_DYN_COLON as UInt8);
    _render_into(&tape, node, &mut out);
    i = i + 1;
  }
  out.push(_DYN_RBRACE as UInt8);
  return builder.sb_to_str(&out);
}

// --------------------------------------------------
//  GetItem / PutItem / UpdateItem / DeleteItem
// --------------------------------------------------

/// GetItem request body.
pub type DynamoGetItem = {
  table_name: Str;
  key: DynamoItem;
  consistent_read: Bool;
  projection_expression: Str;
  return_consumed_capacity: Str;
}

/// A new GetItem request (ConsistentRead false, no projection).
/// Params: table_name - the table; key - the key item.
/// Returns: the request. Error case: none. Complexity: O(1).
pub fn dynamo_get_item_new(table_name: Str, key: DynamoItem) -> DynamoGetItem {
  return DynamoGetItem{
    table_name: table_name;
    key: key;
    consistent_read: false;
    projection_expression: "";
    return_consumed_capacity: "";
  };
}

/// Render the GetItem JSON body.
/// Params: r - the request.
/// Returns: Ok(body) with fields in fixed order: TableName, Key,
/// ConsistentRead, ProjectionExpression, ReturnConsumedCapacity.
/// Error case: the table-name catalog; Err("dynamo: GetItem Key is
/// missing"/"must be a map item").
/// Complexity: O(key subtree).
pub fn dynamo_get_item_render(r: &DynamoGetItem) -> Result[Str, Str] {
  let tn: Str = r.table_name;
  let nchk = _name_check("table", tn);
  if !nchk.is_ok {
    return _err_str(nchk.error);
  }
  let key: DynamoItem = r.key;
  let kchk = _item_map_check(&key, "GetItem Key");
  if !kchk.is_ok {
    return _err_str(kchk.error);
  }
  var out = Vec[UInt8].new();
  out.push(_DYN_LBRACE as UInt8);
  var first = true;
  first = _push_member_str(&mut out, first, "TableName", tn);
  first = _push_member_item(&mut out, first, "Key", &key);
  let cr: Bool = r.consistent_read;
  if cr {
    first = _push_member_raw(&mut out, first, "ConsistentRead", "true");
  }
  let pe: Str = r.projection_expression;
  if pe.len() > 0 {
    first = _push_member_str(&mut out, first, "ProjectionExpression", pe);
  }
  let rcc: Str = r.return_consumed_capacity;
  if rcc.len() > 0 {
    first = _push_member_str(&mut out, first, "ReturnConsumedCapacity", rcc);
  }
  out.push(_DYN_RBRACE as UInt8);
  return _ok_str(builder.sb_to_str(&out));
}

/// PutItem request body.
pub type DynamoPutItem = {
  table_name: Str;
  item: DynamoItem;
  condition_expression: Str;
  return_values: Str;
}

/// A new PutItem request. Params: table_name - the table; item - the item.
/// Returns: the request. Error case: none. Complexity: O(1).
pub fn dynamo_put_item_new(table_name: Str, item: DynamoItem) -> DynamoPutItem {
  return DynamoPutItem{
    table_name: table_name;
    item: item;
    condition_expression: "";
    return_values: "";
  };
}

/// Render the PutItem JSON body.
/// Params: r - the request.
/// Returns: Ok(body) with fields in fixed order: TableName, Item,
/// ConditionExpression, ReturnValues.
/// Error case: the table-name catalog; Err("dynamo: PutItem Item is
/// missing"/"must be a map item").
/// Complexity: O(item subtree).
pub fn dynamo_put_item_render(r: &DynamoPutItem) -> Result[Str, Str] {
  let tn: Str = r.table_name;
  let nchk = _name_check("table", tn);
  if !nchk.is_ok {
    return _err_str(nchk.error);
  }
  let item: DynamoItem = r.item;
  let ichk = _item_map_check(&item, "PutItem Item");
  if !ichk.is_ok {
    return _err_str(ichk.error);
  }
  var out = Vec[UInt8].new();
  out.push(_DYN_LBRACE as UInt8);
  var first = true;
  first = _push_member_str(&mut out, first, "TableName", tn);
  first = _push_member_item(&mut out, first, "Item", &item);
  let ce: Str = r.condition_expression;
  if ce.len() > 0 {
    first = _push_member_str(&mut out, first, "ConditionExpression", ce);
  }
  let rv: Str = r.return_values;
  if rv.len() > 0 {
    first = _push_member_str(&mut out, first, "ReturnValues", rv);
  }
  out.push(_DYN_RBRACE as UInt8);
  return _ok_str(builder.sb_to_str(&out));
}

/// UpdateItem request body (UpdateExpression or legacy AttributeUpdates).
pub type DynamoUpdateItem = {
  table_name: Str;
  key: DynamoItem;
  update_expression: Str;
  return_values: Str;
  attribute_updates: DynamoAttributeUpdates;
  has_attribute_updates: Bool;
}

/// A new UpdateItem request (no expressions).
/// Params: table_name - the table; key - the key item.
/// Returns: the request. Error case: none. Complexity: O(1).
pub fn dynamo_update_item_new(table_name: Str, key: DynamoItem) -> DynamoUpdateItem {
  let updates = dynamo_attribute_updates_new();
  return DynamoUpdateItem{
    table_name: table_name;
    key: key;
    update_expression: "";
    return_values: "";
    attribute_updates: updates;
    has_attribute_updates: false;
  };
}

/// Render the UpdateItem JSON body. UpdateExpression wins when set;
/// otherwise AttributeUpdates renders when has_attribute_updates is true.
/// Params: r - the request.
/// Returns: Ok(body) with fields in fixed order: TableName, Key,
/// UpdateExpression | AttributeUpdates, ReturnValues.
/// Error case: the table-name catalog; Err("dynamo: UpdateItem Key is
/// missing"/"must be a map item"); Err("dynamo: UpdateItem needs an
/// UpdateExpression or AttributeUpdates").
/// Complexity: O(key subtree + updates).
pub fn dynamo_update_item_render(r: &DynamoUpdateItem) -> Result[Str, Str] {
  let tn: Str = r.table_name;
  let nchk = _name_check("table", tn);
  if !nchk.is_ok {
    return _err_str(nchk.error);
  }
  let key: DynamoItem = r.key;
  let kchk = _item_map_check(&key, "UpdateItem Key");
  if !kchk.is_ok {
    return _err_str(kchk.error);
  }
  let ue: Str = r.update_expression;
  let has_updates: Bool = r.has_attribute_updates;
  if ue.len() == 0 && !has_updates {
    return _err_str("dynamo: UpdateItem needs an UpdateExpression or AttributeUpdates");
  }
  var out = Vec[UInt8].new();
  out.push(_DYN_LBRACE as UInt8);
  var first = true;
  first = _push_member_str(&mut out, first, "TableName", tn);
  first = _push_member_item(&mut out, first, "Key", &key);
  if ue.len() > 0 {
    first = _push_member_str(&mut out, first, "UpdateExpression", ue);
  } else {
    let updates: DynamoAttributeUpdates = r.attribute_updates;
    first = _push_member_raw(&mut out, first, "AttributeUpdates", _render_attribute_updates(&updates));
  }
  let rv: Str = r.return_values;
  if rv.len() > 0 {
    first = _push_member_str(&mut out, first, "ReturnValues", rv);
  }
  out.push(_DYN_RBRACE as UInt8);
  return _ok_str(builder.sb_to_str(&out));
}

/// DeleteItem request body.
pub type DynamoDeleteItem = {
  table_name: Str;
  key: DynamoItem;
  condition_expression: Str;
  return_values: Str;
}

/// A new DeleteItem request. Params: table_name - the table; key - the key.
/// Returns: the request. Error case: none. Complexity: O(1).
pub fn dynamo_delete_item_new(table_name: Str, key: DynamoItem) -> DynamoDeleteItem {
  return DynamoDeleteItem{
    table_name: table_name;
    key: key;
    condition_expression: "";
    return_values: "";
  };
}

/// Render the DeleteItem JSON body.
/// Params: r - the request.
/// Returns: Ok(body) with fields in fixed order: TableName, Key,
/// ConditionExpression, ReturnValues.
/// Error case: the table-name catalog; Err("dynamo: DeleteItem Key is
/// missing"/"must be a map item").
/// Complexity: O(key subtree).
pub fn dynamo_delete_item_render(r: &DynamoDeleteItem) -> Result[Str, Str] {
  let tn: Str = r.table_name;
  let nchk = _name_check("table", tn);
  if !nchk.is_ok {
    return _err_str(nchk.error);
  }
  let key: DynamoItem = r.key;
  let kchk = _item_map_check(&key, "DeleteItem Key");
  if !kchk.is_ok {
    return _err_str(kchk.error);
  }
  var out = Vec[UInt8].new();
  out.push(_DYN_LBRACE as UInt8);
  var first = true;
  first = _push_member_str(&mut out, first, "TableName", tn);
  first = _push_member_item(&mut out, first, "Key", &key);
  let ce: Str = r.condition_expression;
  if ce.len() > 0 {
    first = _push_member_str(&mut out, first, "ConditionExpression", ce);
  }
  let rv: Str = r.return_values;
  if rv.len() > 0 {
    first = _push_member_str(&mut out, first, "ReturnValues", rv);
  }
  out.push(_DYN_RBRACE as UInt8);
  return _ok_str(builder.sb_to_str(&out));
}

// --------------------------------------------------
//  Query / Scan
// --------------------------------------------------

/// Query request body.
pub type DynamoQuery = {
  table_name: Str;
  index_name: Str;
  key_condition_expression: Str;
  expression_attribute_names: DynamoNameMap;
  expression_attribute_values: DynamoValueMap;
  limit: Int;
  exclusive_start_key: DynamoItem;
  has_exclusive_start_key: Bool;
  scan_index_forward: Bool;
  scan_index_forward_set: Bool;
  select: Str;
}

/// A new Query request (no expression, no limit, forward order default).
/// Params: table_name - the table. Returns: the request.
/// Error case: none. Complexity: O(1).
pub fn dynamo_query_new(table_name: Str) -> DynamoQuery {
  let names = dynamo_name_map_new();
  let values = dynamo_value_map_new();
  let start = dynamo_item_new_map();
  return DynamoQuery{
    table_name: table_name;
    index_name: "";
    key_condition_expression: "";
    expression_attribute_names: names;
    expression_attribute_values: values;
    limit: 0;
    exclusive_start_key: start;
    has_exclusive_start_key: false;
    scan_index_forward: true;
    scan_index_forward_set: false;
    select: "";
  };
}

/// Render the Query JSON body.
/// Params: q - the request.
/// Returns: Ok(body) with fields in fixed order: TableName, IndexName,
/// KeyConditionExpression, ExpressionAttributeNames,
/// ExpressionAttributeValues, Limit, ExclusiveStartKey, ScanIndexForward,
/// Select. Absent optionals are omitted; ScanIndexForward renders only
/// when scan_index_forward_set is true.
/// Error case: the table-name catalog; Err("dynamo: Query
/// ExclusiveStartKey is missing"/"must be a map item").
/// Complexity: O(expression maps + key subtree).
pub fn dynamo_query_render(q: &DynamoQuery) -> Result[Str, Str] {
  let tn: Str = q.table_name;
  let nchk = _name_check("table", tn);
  if !nchk.is_ok {
    return _err_str(nchk.error);
  }
  let esk: DynamoItem = q.exclusive_start_key;
  let has_esk: Bool = q.has_exclusive_start_key;
  if has_esk {
    let echk = _item_map_check(&esk, "Query ExclusiveStartKey");
    if !echk.is_ok {
      return _err_str(echk.error);
    }
  }
  var out = Vec[UInt8].new();
  out.push(_DYN_LBRACE as UInt8);
  var first = true;
  first = _push_member_str(&mut out, first, "TableName", tn);
  let iname: Str = q.index_name;
  if iname.len() > 0 {
    first = _push_member_str(&mut out, first, "IndexName", iname);
  }
  let kce: Str = q.key_condition_expression;
  if kce.len() > 0 {
    first = _push_member_str(&mut out, first, "KeyConditionExpression", kce);
  }
  let nm: DynamoNameMap = q.expression_attribute_names;
  if dynamo_name_map_count(&nm) > 0 {
    first = _push_member_raw(&mut out, first, "ExpressionAttributeNames", _render_name_map(&nm));
  }
  let vm: DynamoValueMap = q.expression_attribute_values;
  if dynamo_value_map_count(&vm) > 0 {
    first = _push_member_raw(&mut out, first, "ExpressionAttributeValues", _render_value_map(&vm));
  }
  let lim: Int = q.limit;
  if lim > 0 {
    first = _push_member_raw(&mut out, first, "Limit", _int_str(lim));
  }
  if has_esk {
    first = _push_member_item(&mut out, first, "ExclusiveStartKey", &esk);
  }
  let sif_set: Bool = q.scan_index_forward_set;
  if sif_set {
    let sif: Bool = q.scan_index_forward;
    first = _push_member_raw(&mut out, first, "ScanIndexForward", _bool_text(sif));
  }
  let sel: Str = q.select;
  if sel.len() > 0 {
    first = _push_member_str(&mut out, first, "Select", sel);
  }
  out.push(_DYN_RBRACE as UInt8);
  return _ok_str(builder.sb_to_str(&out));
}

/// Scan request body.
pub type DynamoScan = {
  table_name: Str;
  index_name: Str;
  filter_expression: Str;
  expression_attribute_names: DynamoNameMap;
  expression_attribute_values: DynamoValueMap;
  limit: Int;
  exclusive_start_key: DynamoItem;
  has_exclusive_start_key: Bool;
  select: Str;
  consistent_read: Bool;
}

/// A new Scan request (no expression, no limit).
/// Params: table_name - the table. Returns: the request.
/// Error case: none. Complexity: O(1).
pub fn dynamo_scan_new(table_name: Str) -> DynamoScan {
  let names = dynamo_name_map_new();
  let values = dynamo_value_map_new();
  let start = dynamo_item_new_map();
  return DynamoScan{
    table_name: table_name;
    index_name: "";
    filter_expression: "";
    expression_attribute_names: names;
    expression_attribute_values: values;
    limit: 0;
    exclusive_start_key: start;
    has_exclusive_start_key: false;
    select: "";
    consistent_read: false;
  };
}

/// Render the Scan JSON body.
/// Params: s - the request.
/// Returns: Ok(body) with fields in fixed order: TableName, IndexName,
/// FilterExpression, ExpressionAttributeNames, ExpressionAttributeValues,
/// Limit, ExclusiveStartKey, Select, ConsistentRead.
/// Error case: the table-name catalog; Err("dynamo: Scan ExclusiveStartKey
/// is missing"/"must be a map item").
/// Complexity: O(expression maps + key subtree).
pub fn dynamo_scan_render(s: &DynamoScan) -> Result[Str, Str] {
  let tn: Str = s.table_name;
  let nchk = _name_check("table", tn);
  if !nchk.is_ok {
    return _err_str(nchk.error);
  }
  let esk: DynamoItem = s.exclusive_start_key;
  let has_esk: Bool = s.has_exclusive_start_key;
  if has_esk {
    let echk = _item_map_check(&esk, "Scan ExclusiveStartKey");
    if !echk.is_ok {
      return _err_str(echk.error);
    }
  }
  var out = Vec[UInt8].new();
  out.push(_DYN_LBRACE as UInt8);
  var first = true;
  first = _push_member_str(&mut out, first, "TableName", tn);
  let iname: Str = s.index_name;
  if iname.len() > 0 {
    first = _push_member_str(&mut out, first, "IndexName", iname);
  }
  let fe: Str = s.filter_expression;
  if fe.len() > 0 {
    first = _push_member_str(&mut out, first, "FilterExpression", fe);
  }
  let nm: DynamoNameMap = s.expression_attribute_names;
  if dynamo_name_map_count(&nm) > 0 {
    first = _push_member_raw(&mut out, first, "ExpressionAttributeNames", _render_name_map(&nm));
  }
  let vm: DynamoValueMap = s.expression_attribute_values;
  if dynamo_value_map_count(&vm) > 0 {
    first = _push_member_raw(&mut out, first, "ExpressionAttributeValues", _render_value_map(&vm));
  }
  let lim: Int = s.limit;
  if lim > 0 {
    first = _push_member_raw(&mut out, first, "Limit", _int_str(lim));
  }
  if has_esk {
    first = _push_member_item(&mut out, first, "ExclusiveStartKey", &esk);
  }
  let sel: Str = s.select;
  if sel.len() > 0 {
    first = _push_member_str(&mut out, first, "Select", sel);
  }
  let cr: Bool = s.consistent_read;
  if cr {
    first = _push_member_raw(&mut out, first, "ConsistentRead", "true");
  }
  out.push(_DYN_RBRACE as UInt8);
  return _ok_str(builder.sb_to_str(&out));
}

// --------------------------------------------------
//  BatchGetItem / BatchWriteItem
// --------------------------------------------------

/// Kind id of a BatchWrite PutRequest. Params: none. Returns: 0.
pub fn dynamo_batch_put() -> Int { return 0; }
/// Kind id of a BatchWrite DeleteRequest. Params: none. Returns: 1.
pub fn dynamo_batch_delete() -> Int { return 1; }

/// BatchGetItem RequestItems: tables with their key lists. `key_table[i]`
/// names the table of key_nodes[i]; keys live in one merged tape.
pub type DynamoBatchGet = {
  table_names: Vec[Str];
  consistent_read: Vec[Int];
  projections: Vec[Str];
  keys: DynamoValue;
  key_nodes: Vec[Int];
  key_table: Vec[Int];
}

/// A fresh empty BatchGet request. Params: none. Returns: the request.
/// Error case: none. Complexity: O(1).
pub fn dynamo_batch_get_new() -> DynamoBatchGet {
  return DynamoBatchGet{
    table_names: Vec[Str].new();
    consistent_read: Vec[Int].new();
    projections: Vec[Str].new();
    keys: dynamo_value_new();
    key_nodes: Vec[Int].new();
    key_table: Vec[Int].new();
  };
}

/// Add a table to a BatchGet request. All tables must be added before
/// their keys. Params: b - the request; table_name - the table;
/// consistent_read - the per-table flag; projection - "" for none.
/// Returns: Ok(""). Error case: the table-name catalog; Err("dynamo:
/// duplicate batch table: <name>").
/// Complexity: O(b.table_names.len()).
pub fn dynamo_batch_get_add_table(b: &mut DynamoBatchGet, table_name: Str, consistent_read: Bool, projection: Str) -> Result[Str, Str] {
  let nchk = _name_check("table", table_name);
  if !nchk.is_ok {
    return _err_str(nchk.error);
  }
  var i = 0;
  while i < b.table_names.len() {
    let cur: Str = b.table_names[i];
    if compare.str_compare(cur, table_name) == 0 {
      return _err_str("dynamo: duplicate batch table: " + table_name);
    }
    i = i + 1;
  }
  var cr = 0;
  if consistent_read {
    cr = 1;
  }
  b.table_names.push(table_name);
  b.consistent_read.push(cr);
  b.projections.push(projection);
  return _ok_str("");
}

/// Add one key item to the most recently added BatchGet table.
/// Params: b - the request; key - the key item (must be a map).
/// Returns: Ok(""). Error case: Err("dynamo: batch key needs a table
/// first"), Err("dynamo: batch key must be a map item").
/// Complexity: O(key subtree).
pub fn dynamo_batch_get_add_key(b: &mut DynamoBatchGet, key: &DynamoItem) -> Result[Str, Str] {
  let ti = b.table_names.len() - 1;
  if ti < 0 {
    return _err_str("dynamo: batch key needs a table first");
  }
  if !dynamo_item_present(key) {
    return _err_str("dynamo: batch key must be a map item");
  }
  if !dynamo_item_is_map(key) {
    return _err_str("dynamo: batch key must be a map item");
  }
  let vnode0 = dynamo_item_node(key);
  let vtape: DynamoValue = key.values;
  var tape: DynamoValue = b.keys;
  let off = dynamo_value_merge(&mut tape, &vtape);
  b.keys = tape;
  b.key_nodes.push(vnode0 + off);
  b.key_table.push(ti);
  return _ok_str("");
}

/// Number of tables in a BatchGet request. Params: b - the request.
/// Returns: the count. Error case: none. Complexity: O(1).
pub fn dynamo_batch_get_table_count(b: &DynamoBatchGet) -> Int {
  return b.table_names.len();
}

// Keys belonging to table index ti (0 when none).
fn _batch_keys_for(b: &DynamoBatchGet, ti: Int) -> Int {
  var n = 0;
  var i = 0;
  while i < b.key_table.len() {
    let t: Int = b.key_table[i];
    if t == ti {
      n = n + 1;
    }
    i = i + 1;
  }
  return n;
}

/// Render the BatchGetItem JSON body {"RequestItems":{...}}.
/// Params: b - the request.
/// Returns: Ok(body). Error case: Err("dynamo: batch request has no
/// tables"), Err("dynamo: batch table has no keys: <name>") or the batch
/// add catalog.
/// Complexity: O(tables * keys + key subtrees).
pub fn dynamo_batch_get_render(b: &DynamoBatchGet) -> Result[Str, Str] {
  if b.table_names.len() == 0 {
    return _err_str("dynamo: batch request has no tables");
  }
  let keys: DynamoValue = b.keys;
  var out = Vec[UInt8].new();
  builder.sb_push_str(&mut out, "{\"RequestItems\":{");
  var i = 0;
  while i < b.table_names.len() {
    let tn: Str = b.table_names[i];
    if i > 0 {
      out.push(_DYN_COMMA as UInt8);
    }
    _push_json_string(&mut out, tn);
    let kcount = _batch_keys_for(b, i);
    if kcount == 0 {
      return _err_str("dynamo: batch table has no keys: " + tn);
    }
    builder.sb_push_str(&mut out, ":{\"Keys\":[");
    var k = 0;
    var emitted = 0;
    while k < b.key_nodes.len() {
      let t: Int = b.key_table[k];
      if t == i {
        if emitted > 0 {
          out.push(_DYN_COMMA as UInt8);
        }
        let node: Int = b.key_nodes[k];
        _render_map_body(&keys, node, &mut out);
        emitted = emitted + 1;
      }
      k = k + 1;
    }
    out.push(_DYN_RBRACKET as UInt8);
    let cr: Int = b.consistent_read[i];
    if cr == 1 {
      builder.sb_push_str(&mut out, ",\"ConsistentRead\":true");
    }
    let proj: Str = b.projections[i];
    if proj.len() > 0 {
      builder.sb_push_str(&mut out, ",\"ProjectionExpression\":");
      _push_json_string(&mut out, proj);
    }
    out.push(_DYN_RBRACE as UInt8);
    i = i + 1;
  }
  builder.sb_push_str(&mut out, "}}");
  return _ok_str(builder.sb_to_str(&out));
}

/// BatchWriteItem RequestItems: tables with Put/Delete requests.
/// `req_table[i]` names the table of req_nodes[i]; `req_kinds[i]` is
/// dynamo_batch_put() or dynamo_batch_delete().
pub type DynamoBatchWrite = {
  table_names: Vec[Str];
  items: DynamoValue;
  req_nodes: Vec[Int];
  req_table: Vec[Int];
  req_kinds: Vec[Int];
}

/// A fresh empty BatchWrite request. Params: none. Returns: the request.
/// Error case: none. Complexity: O(1).
pub fn dynamo_batch_write_new() -> DynamoBatchWrite {
  return DynamoBatchWrite{
    table_names: Vec[Str].new();
    items: dynamo_value_new();
    req_nodes: Vec[Int].new();
    req_table: Vec[Int].new();
    req_kinds: Vec[Int].new();
  };
}

/// Add a table to a BatchWrite request. All tables must be added before
/// their requests. Params: b - the request; table_name - the table.
/// Returns: Ok(""). Error case: the table-name catalog; Err("dynamo:
/// duplicate batch table: <name>").
/// Complexity: O(b.table_names.len()).
pub fn dynamo_batch_write_add_table(b: &mut DynamoBatchWrite, table_name: Str) -> Result[Str, Str] {
  let nchk = _name_check("table", table_name);
  if !nchk.is_ok {
    return _err_str(nchk.error);
  }
  var i = 0;
  while i < b.table_names.len() {
    let cur: Str = b.table_names[i];
    if compare.str_compare(cur, table_name) == 0 {
      return _err_str("dynamo: duplicate batch table: " + table_name);
    }
    i = i + 1;
  }
  b.table_names.push(table_name);
  return _ok_str("");
}

// Shared request add: merge item tape and record (table, kind, node).
fn _batch_write_add_item(b: &mut DynamoBatchWrite, kind: Int, item: &DynamoItem, what: Str) -> Result[Str, Str] {
  let ti = b.table_names.len() - 1;
  if ti < 0 {
    return _err_str("dynamo: batch request needs a table first");
  }
  if !dynamo_item_present(item) {
    return _err_str("dynamo: batch " + what + " must be a map item");
  }
  if !dynamo_item_is_map(item) {
    return _err_str("dynamo: batch " + what + " must be a map item");
  }
  let vnode0 = dynamo_item_node(item);
  let vtape: DynamoValue = item.values;
  var tape: DynamoValue = b.items;
  let off = dynamo_value_merge(&mut tape, &vtape);
  b.items = tape;
  b.req_nodes.push(vnode0 + off);
  b.req_table.push(ti);
  b.req_kinds.push(kind);
  return _ok_str("");
}

/// Add a PutRequest. Params: b - the request; item - the item.
/// Returns: Ok(""). Error case: Err("dynamo: batch request needs a table
/// first"), Err("dynamo: batch item must be a map item").
/// Complexity: O(item subtree).
pub fn dynamo_batch_write_add_put(b: &mut DynamoBatchWrite, item: &DynamoItem) -> Result[Str, Str] {
  return _batch_write_add_item(b, 0, item, "item");
}

/// Add a DeleteRequest. Params: b - the request; key - the key item.
/// Returns: Ok(""). Error case: Err("dynamo: batch request needs a table
/// first"), Err("dynamo: batch key must be a map item").
/// Complexity: O(key subtree).
pub fn dynamo_batch_write_add_delete(b: &mut DynamoBatchWrite, key: &DynamoItem) -> Result[Str, Str] {
  return _batch_write_add_item(b, 1, key, "key");
}

/// Number of tables in a BatchWrite request. Params: b - the request.
/// Returns: the count. Error case: none. Complexity: O(1).
pub fn dynamo_batch_write_table_count(b: &DynamoBatchWrite) -> Int {
  return b.table_names.len();
}

// Requests belonging to table index ti (0 when none).
fn _batch_reqs_for(b: &DynamoBatchWrite, ti: Int) -> Int {
  var n = 0;
  var i = 0;
  while i < b.req_table.len() {
    let t: Int = b.req_table[i];
    if t == ti {
      n = n + 1;
    }
    i = i + 1;
  }
  return n;
}

/// Render the BatchWriteItem JSON body {"RequestItems":{...}}.
/// Params: b - the request.
/// Returns: Ok(body). Error case: Err("dynamo: batch request has no
/// tables"), Err("dynamo: batch table has no requests: <name>") or the
/// batch add catalog.
/// Complexity: O(tables * requests + item subtrees).
pub fn dynamo_batch_write_render(b: &DynamoBatchWrite) -> Result[Str, Str] {
  if b.table_names.len() == 0 {
    return _err_str("dynamo: batch request has no tables");
  }
  let items: DynamoValue = b.items;
  var out = Vec[UInt8].new();
  builder.sb_push_str(&mut out, "{\"RequestItems\":{");
  var i = 0;
  while i < b.table_names.len() {
    let tn: Str = b.table_names[i];
    if i > 0 {
      out.push(_DYN_COMMA as UInt8);
    }
    _push_json_string(&mut out, tn);
    let rcount = _batch_reqs_for(b, i);
    if rcount == 0 {
      return _err_str("dynamo: batch table has no requests: " + tn);
    }
    builder.sb_push_str(&mut out, ":[");
    var k = 0;
    var emitted = 0;
    while k < b.req_nodes.len() {
      let t: Int = b.req_table[k];
      if t == i {
        if emitted > 0 {
          out.push(_DYN_COMMA as UInt8);
        }
        let kind: Int = b.req_kinds[k];
        let node: Int = b.req_nodes[k];
        if kind == 1 {
          builder.sb_push_str(&mut out, "{\"DeleteRequest\":{\"Key\":");
        } else {
          builder.sb_push_str(&mut out, "{\"PutRequest\":{\"Item\":");
        }
        _render_map_body(&items, node, &mut out);
        builder.sb_push_str(&mut out, "}}");
        emitted = emitted + 1;
      }
      k = k + 1;
    }
    out.push(_DYN_RBRACKET as UInt8);
    i = i + 1;
  }
  builder.sb_push_str(&mut out, "}}");
  return _ok_str(builder.sb_to_str(&out));
}

// --------------------------------------------------
//  TransactWriteItems
// --------------------------------------------------

/// Kind id of a TransactWriteItems Put. Params: none. Returns: 0.
pub fn dynamo_tx_put() -> Int { return 0; }
/// Kind id of a TransactWriteItems Update. Params: none. Returns: 1.
pub fn dynamo_tx_update() -> Int { return 1; }
/// Kind id of a TransactWriteItems Delete. Params: none. Returns: 2.
pub fn dynamo_tx_delete() -> Int { return 2; }
/// Kind id of a TransactWriteItems ConditionCheck. Params: none. Returns: 3.
pub fn dynamo_tx_condition_check() -> Int { return 3; }

/// TransactWriteItems: parallel arrays for kinds, table names, the merged
/// item/key tape, item nodes and one expression per entry (UpdateExpression
/// for Update entries, ConditionExpression otherwise; "" omits it).
pub type DynamoTransactWrite = {
  kinds: Vec[Int];
  table_names: Vec[Str];
  items: DynamoValue;
  item_nodes: Vec[Int];
  exprs: Vec[Str];
}

/// A fresh empty TransactWriteItems request. Params: none. Returns: it.
/// Error case: none. Complexity: O(1).
pub fn dynamo_transact_write_new() -> DynamoTransactWrite {
  return DynamoTransactWrite{
    kinds: Vec[Int].new();
    table_names: Vec[Str].new();
    items: dynamo_value_new();
    item_nodes: Vec[Int].new();
    exprs: Vec[Str].new();
  };
}

// Shared transact add.
fn _transact_add(t: &mut DynamoTransactWrite, kind: Int, table_name: Str, item: &DynamoItem, expr: Str, what: Str) -> Result[Str, Str] {
  let nchk = _name_check("table", table_name);
  if !nchk.is_ok {
    return _err_str(nchk.error);
  }
  if !dynamo_item_present(item) {
    return _err_str("dynamo: transact " + what + " must be a map item");
  }
  if !dynamo_item_is_map(item) {
    return _err_str("dynamo: transact " + what + " must be a map item");
  }
  let vnode0 = dynamo_item_node(item);
  let vtape: DynamoValue = item.values;
  var tape: DynamoValue = t.items;
  let off = dynamo_value_merge(&mut tape, &vtape);
  t.items = tape;
  t.kinds.push(kind);
  t.table_names.push(table_name);
  t.item_nodes.push(vnode0 + off);
  t.exprs.push(expr);
  return _ok_str("");
}

/// Add a Put entry. Params: t - the request; table_name - the table;
/// item - the item; condition - "" for none. Returns: Ok("").
/// Error case: the table-name catalog; Err("dynamo: transact item must be
/// a map item").
/// Complexity: O(item subtree).
pub fn dynamo_transact_add_put(t: &mut DynamoTransactWrite, table_name: Str, item: &DynamoItem, condition: Str) -> Result[Str, Str] {
  return _transact_add(t, 0, table_name, item, condition, "item");
}

/// Add an Update entry. Params: t - the request; table_name - the table;
/// key - the key item; update_expression - non-empty. Returns: Ok("").
/// Error case: the table-name catalog; Err("dynamo: transact key must be
/// a map item"), Err("dynamo: transact update needs an UpdateExpression").
/// Complexity: O(key subtree).
pub fn dynamo_transact_add_update(t: &mut DynamoTransactWrite, table_name: Str, key: &DynamoItem, update_expression: Str) -> Result[Str, Str] {
  if update_expression.len() == 0 {
    return _err_str("dynamo: transact update needs an UpdateExpression");
  }
  return _transact_add(t, 1, table_name, key, update_expression, "key");
}

/// Add a Delete entry. Params: t - the request; table_name - the table;
/// key - the key item; condition - "" for none. Returns: Ok("").
/// Error case: the table-name catalog; Err("dynamo: transact key must be
/// a map item").
/// Complexity: O(key subtree).
pub fn dynamo_transact_add_delete(t: &mut DynamoTransactWrite, table_name: Str, key: &DynamoItem, condition: Str) -> Result[Str, Str] {
  return _transact_add(t, 2, table_name, key, condition, "key");
}

/// Add a ConditionCheck entry. Params: t - the request; table_name - the
/// table; key - the key item; condition - non-empty. Returns: Ok("").
/// Error case: the table-name catalog; Err("dynamo: transact key must be
/// a map item"), Err("dynamo: transact condition check needs a
/// ConditionExpression").
/// Complexity: O(key subtree).
pub fn dynamo_transact_add_condition_check(t: &mut DynamoTransactWrite, table_name: Str, key: &DynamoItem, condition: Str) -> Result[Str, Str] {
  if condition.len() == 0 {
    return _err_str("dynamo: transact condition check needs a ConditionExpression");
  }
  return _transact_add(t, 3, table_name, key, condition, "key");
}

/// Number of transact entries. Params: t - the request. Returns: it.
/// Error case: none. Complexity: O(1).
pub fn dynamo_transact_count(t: &DynamoTransactWrite) -> Int {
  return t.kinds.len();
}

/// Render the TransactWriteItems JSON body {"TransactItems":[...]}.
/// Params: t - the request.
/// Returns: Ok(body). Error case: Err("dynamo: transact request has no
/// items") or the transact add catalog.
/// Complexity: O(entries * item subtrees).
pub fn dynamo_transact_write_render(t: &DynamoTransactWrite) -> Result[Str, Str] {
  if t.kinds.len() == 0 {
    return _err_str("dynamo: transact request has no items");
  }
  let items: DynamoValue = t.items;
  var out = Vec[UInt8].new();
  builder.sb_push_str(&mut out, "{\"TransactItems\":[");
  var i = 0;
  while i < t.kinds.len() {
    if i > 0 {
      out.push(_DYN_COMMA as UInt8);
    }
    let kind: Int = t.kinds[i];
    let tn: Str = t.table_names[i];
    let node: Int = t.item_nodes[i];
    let expr: Str = t.exprs[i];
    if kind == 1 {
      builder.sb_push_str(&mut out, "{\"Update\":{\"TableName\":");
      _push_json_string(&mut out, tn);
      builder.sb_push_str(&mut out, ",\"Key\":");
      _render_map_body(&items, node, &mut out);
      if expr.len() > 0 {
        builder.sb_push_str(&mut out, ",\"UpdateExpression\":");
        _push_json_string(&mut out, expr);
      }
      builder.sb_push_str(&mut out, "}}");
    } elif kind == 2 {
      builder.sb_push_str(&mut out, "{\"Delete\":{\"TableName\":");
      _push_json_string(&mut out, tn);
      builder.sb_push_str(&mut out, ",\"Key\":");
      _render_map_body(&items, node, &mut out);
      if expr.len() > 0 {
        builder.sb_push_str(&mut out, ",\"ConditionExpression\":");
        _push_json_string(&mut out, expr);
      }
      builder.sb_push_str(&mut out, "}}");
    } elif kind == 3 {
      builder.sb_push_str(&mut out, "{\"ConditionCheck\":{\"TableName\":");
      _push_json_string(&mut out, tn);
      builder.sb_push_str(&mut out, ",\"Key\":");
      _render_map_body(&items, node, &mut out);
      if expr.len() > 0 {
        builder.sb_push_str(&mut out, ",\"ConditionExpression\":");
        _push_json_string(&mut out, expr);
      }
      builder.sb_push_str(&mut out, "}}");
    } else {
      builder.sb_push_str(&mut out, "{\"Put\":{\"TableName\":");
      _push_json_string(&mut out, tn);
      builder.sb_push_str(&mut out, ",\"Item\":");
      _render_map_body(&items, node, &mut out);
      if expr.len() > 0 {
        builder.sb_push_str(&mut out, ",\"ConditionExpression\":");
        _push_json_string(&mut out, expr);
      }
      builder.sb_push_str(&mut out, "}}");
    }
    i = i + 1;
  }
  builder.sb_push_str(&mut out, "]}");
  return _ok_str(builder.sb_to_str(&out));
}

// --------------------------------------------------
//  Response scanner (top-level member lookup)
// --------------------------------------------------

// True when data[kstart, kstart + key.len()) equals key and the next byte
// is a closing quote (kstart points just after the opening quote).
fn _key_matches(data: &Vec[UInt8], kstart: Int, key: Str) -> Bool {
  let n = data.len();
  if kstart + key.len() >= n {
    return false;
  }
  var i = 0;
  while i < key.len() {
    if _vbyte(data, kstart + i) != _byte(key, i) {
      return false;
    }
    i = i + 1;
  }
  return _vbyte(data, kstart + key.len()) == _DYN_QUOTE;
}

// Span (start, end) of the JSON value at pos: string (quotes included),
// composite ({...}/[...]) or bare scalar. Escape-aware and bounded.
fn _scan_value(data: &Vec[UInt8], pos: Int, end: Int) -> Result[(Int, Int), Str] {
  if pos >= end {
    return _err_pair(_perr("json bad value", pos));
  }
  let c = _vbyte(data, pos);
  if c == _DYN_QUOTE {
    var i = pos + 1;
    while i < end {
      let b = _vbyte(data, i);
      if _json_control(b) {
        return _err_pair(_perr("json control byte", i));
      }
      if b == _DYN_BACKSLASH {
        if i + 1 >= end {
          return _err_pair(_perr("json truncated escape", i));
        }
        let nb = _vbyte(data, i + 1);
        if _json_control(nb) {
          return _err_pair(_perr("json control byte", i + 1));
        }
        i = i + 2;
      } elif b == _DYN_QUOTE {
        return _ok_pair((pos, i + 1));
      } else {
        i = i + 1;
      }
    }
    return _err_pair(_perr("json unterminated string", pos));
  }
  if c == _DYN_LBRACE || c == _DYN_LBRACKET {
    var depth = 0;
    var i2 = pos;
    while i2 < end {
      let b2 = _vbyte(data, i2);
      if _json_control(b2) {
        return _err_pair(_perr("json control byte", i2));
      }
      if b2 == _DYN_QUOTE {
        var si = i2 + 1;
        var sc = false;
        while si < end {
          let sb = _vbyte(data, si);
          if _json_control(sb) {
            return _err_pair(_perr("json control byte", si));
          }
          if sb == _DYN_BACKSLASH {
            si = si + 2;
          } elif sb == _DYN_QUOTE {
            sc = true;
            si = si + 1;
            break;
          } else {
            si = si + 1;
          }
        }
        if !sc {
          return _err_pair(_perr("json unterminated string", i2));
        }
        i2 = si;
        continue;
      }
      if b2 == _DYN_LBRACE || b2 == _DYN_LBRACKET {
        depth = depth + 1;
        i2 = i2 + 1;
        continue;
      }
      if b2 == _DYN_RBRACE || b2 == _DYN_RBRACKET {
        depth = depth - 1;
        i2 = i2 + 1;
        if depth == 0 {
          return _ok_pair((pos, i2));
        }
        continue;
      }
      i2 = i2 + 1;
    }
    return _err_pair(_perr("json unterminated value", pos));
  }
  var j = pos;
  while j < end {
    let b3 = _vbyte(data, j);
    if b3 == _DYN_COMMA || b3 == _DYN_RBRACE || b3 == _DYN_RBRACKET {
      break;
    }
    if b3 == _DYN_SPACE || b3 == _DYN_TAB || b3 == _DYN_LF || b3 == _DYN_CR {
      break;
    }
    if _json_control(b3) {
      return _err_pair(_perr("json control byte", j));
    }
    j = j + 1;
  }
  if j == pos {
    return _err_pair(_perr("json bad value", pos));
  }
  return _ok_pair((pos, j));
}

// Raw control byte predicate (below 0x20, excluding TAB/LF/CR).
fn _json_control(c: Int) -> Bool {
  if c < _DYN_SPACE && c != _DYN_TAB && c != _DYN_LF && c != _DYN_CR {
    return true;
  }
  return false;
}

/// Byte span of the first top-level member `key` of the response object
/// text: (start, end) of its value, quotes/braces included.
/// Params: data - the response bytes; key - the member name.
/// Returns: Ok((start, end)).
/// Error case: Err("dynamo: json empty key"), Err("dynamo: json too
/// large"), Err("dynamo: json control byte at offset N"), Err("dynamo:
/// response is not a JSON object at offset N"), Err("dynamo: json key not
/// found: <key>") or a _scan_value error.
/// Complexity: O(len(data)).
pub fn dynamo_response_span(data: &Vec[UInt8], key: Str) -> Result[(Int, Int), Str] {
  if key.len() == 0 {
    return _err_pair("dynamo: json empty key");
  }
  let n = data.len();
  if n > _DYN_MAX_JSON {
    return _err_pair("dynamo: json too large");
  }
  var i = _skip_ws(data, 0, n);
  if i >= n || _vbyte(data, i) != _DYN_LBRACE {
    return _err_pair(_perr("response is not a JSON object", i));
  }
  i = i + 1;
  var depth = 1;
  var in_str = false;
  var expect_key = true;
  while i < n {
    let c = _vbyte(data, i);
    if _json_control(c) {
      return _err_pair(_perr("json control byte", i));
    }
    if in_str {
      if c == _DYN_BACKSLASH {
        if i + 1 >= n {
          return _err_pair(_perr("json truncated escape", i));
        }
        let nb = _vbyte(data, i + 1);
        if _json_control(nb) {
          return _err_pair(_perr("json control byte", i + 1));
        }
        i = i + 2;
      } elif c == _DYN_QUOTE {
        in_str = false;
        i = i + 1;
      } else {
        i = i + 1;
      }
      continue;
    }
    if c == _DYN_QUOTE {
      if depth == 1 && expect_key && _key_matches(data, i + 1, key) {
        var j = i + 2 + key.len();
        j = _skip_ws(data, j, n);
        if j >= n || _vbyte(data, j) != _DYN_COLON {
          return _err_pair(_perr("json expected ':' after key", j));
        }
        j = _skip_ws(data, j + 1, n);
        return _scan_value(data, j, n);
      }
      in_str = true;
      i = i + 1;
      continue;
    }
    if c == _DYN_LBRACE || c == _DYN_LBRACKET {
      depth = depth + 1;
      i = i + 1;
      continue;
    }
    if c == _DYN_RBRACE || c == _DYN_RBRACKET {
      depth = depth - 1;
      if depth <= 0 {
        return _err_pair("dynamo: json key not found: " + key);
      }
      i = i + 1;
      continue;
    }
    if depth == 1 && c == _DYN_COMMA {
      expect_key = true;
    }
    if depth == 1 && c == _DYN_COLON {
      expect_key = false;
    }
    i = i + 1;
  }
  return _err_pair("dynamo: json key not found: " + key);
}

/// True when the response carries a top-level member `key`.
/// Params: data - the response bytes; key - the member name.
/// Returns: the predicate. Error case: none. Complexity: O(len(data)).
pub fn dynamo_response_has(data: &Vec[UInt8], key: Str) -> Bool {
  let r = dynamo_response_span(data, key);
  return r.is_ok;
}

// Decode a string value span [a, b) (quotes included) as a Str.
fn _span_str(data: &Vec[UInt8], a: Int, b: Int, what: Str) -> Result[Str, Str] {
  var buf = Vec[UInt8].new();
  let r = _decode_string(data, a, b, what, &mut buf);
  if !r.is_ok {
    return _err_str(r.error);
  }
  if r.value != b {
    return _err_str(_perr(what + " has trailing bytes", r.value));
  }
  return _ok_str(builder.sb_to_str(&buf));
}

// Verbatim text of a value span [a, b).
fn _span_text(data: &Vec[UInt8], a: Int, b: Int) -> Str {
  var out = Vec[UInt8].new();
  var i = a;
  while i < b {
    out.push(data[i]);
    i = i + 1;
  }
  return builder.sb_to_str(&out);
}

// Signed decimal of a bare scalar span; magnitude <= 2147483647.
fn _parse_int_span(data: &Vec[UInt8], a: Int, b: Int) -> Result[Int, Str] {
  if a >= b {
    return _err_int(_perr("expected integer", a));
  }
  var i = a;
  var neg = false;
  if _vbyte(data, i) == _DYN_MINUS {
    neg = true;
    i = i + 1;
  }
  if i >= b {
    return _err_int(_perr("expected integer", a));
  }
  let maxv: Int = 2147483647;
  let lim = maxv / 10;
  let rem = maxv % 10;
  var v: Int = 0;
  while i < b {
    let c = _vbyte(data, i);
    if !_is_digit(c) {
      return _err_int(_perr("expected integer", i));
    }
    let d = c - 48;
    if v > lim {
      return _err_int(_perr("integer out of range", a));
    }
    if v == lim && d > rem {
      return _err_int(_perr("integer out of range", a));
    }
    v = v * 10 + d;
    i = i + 1;
  }
  if neg {
    return _ok_int(0 - v);
  }
  return _ok_int(v);
}

// Walk a top-level object value span [a, b): collect member names and
// their value spans into parallel output vectors; returns the count.
fn _obj_members(data: &Vec[UInt8], a: Int, b: Int, names: &mut Vec[Str], starts: &mut Vec[Int], ends: &mut Vec[Int]) -> Result[Int, Str] {
  if a >= b || _vbyte(data, a) != _DYN_LBRACE {
    return _err_int(_perr("expected JSON object", a));
  }
  var i = _skip_ws(data, a + 1, b);
  if i < b && _vbyte(data, i) == _DYN_RBRACE {
    return _ok_int(0);
  }
  var closed = false;
  while i < b && !closed {
    let key_pos = i;
    var kbuf = Vec[UInt8].new();
    let kr = _decode_string(data, i, b, "response key", &mut kbuf);
    if !kr.is_ok {
      return _err_int(kr.error);
    }
    let key = builder.sb_to_str(&kbuf);
    if key.len() == 0 {
      return _err_int(_perr("empty response key", key_pos));
    }
    i = _skip_ws(data, kr.value, b);
    if i >= b || _vbyte(data, i) != _DYN_COLON {
      return _err_int(_perr("expected ':' in object", i));
    }
    i = _skip_ws(data, i + 1, b);
    let sr = _scan_value(data, i, b);
    if !sr.is_ok {
      return _err_int(sr.error);
    }
    let sp = sr.value;
    let va: Int = sp.0;
    let vb: Int = sp.1;
    names.push(key);
    starts.push(va);
    ends.push(vb);
    i = _skip_ws(data, vb, b);
    if i >= b {
      return _err_int(_perr("truncated object", i));
    }
    let c = _vbyte(data, i);
    if c == _DYN_COMMA {
      i = _skip_ws(data, i + 1, b);
    } elif c == _DYN_RBRACE {
      closed = true;
    } else {
      return _err_int(_perr("expected ',' or '}' in object", i));
    }
  }
  if !closed {
    return _err_int(_perr("truncated object", i));
  }
  return _ok_int(names.len());
}

// Index of names entry `key`, or -1.
fn _member_index(names: &Vec[Str], key: Str) -> Int {
  var i = 0;
  while i < names.len() {
    let cur: Str = names[i];
    if compare.str_compare(cur, key) == 0 {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// --------------------------------------------------
//  Response types
// --------------------------------------------------

fn _ok_items(v: DynamoItems) -> Result[DynamoItems, Str] { return Ok(v); }
fn _err_items(m: Str) -> Result[DynamoItems, Str] { return Err(m); }

/// Items array payload: every item merged into one tape, nodes[i] is the
/// root node of item i.
pub type DynamoItems = {
  tape: DynamoValue;
  nodes: Vec[Int];
}

/// LastEvaluatedKey payload: present false when the response had none.
pub type DynamoLastKey = {
  present: Bool;
  item: DynamoItem;
}

/// Count / ScannedCount payload with presence flags.
pub type DynamoCounts = {
  count: Int;
  count_present: Bool;
  scanned_count: Int;
  scanned_present: Bool;
}

/// ConsumedCapacity payload; absent entries are "". Index breakdowns cover
/// GlobalSecondaryIndexes and LocalSecondaryIndexes (parallel vectors).
pub type DynamoCapacity = {
  present: Bool;
  table_name: Str;
  capacity_units: Str;
  read_units: Str;
  write_units: Str;
  table_units: Str;
  table_read_units: Str;
  table_write_units: Str;
  index_names: Vec[Str];
  index_units: Vec[Str];
  index_read_units: Vec[Str];
  index_write_units: Vec[Str];
}

/// UnprocessedItems / UnprocessedKeys: table names with each table's raw
/// JSON payload kept verbatim.
pub type DynamoUnprocessed = {
  present: Bool;
  table_names: Vec[Str];
  payloads: Vec[Str];
}

/// DynamoDB error envelope {__type, message}.
pub type DynamoApiError = {
  has_error: Bool;
  error_type: Str;
  message: Str;
}

/// Parse the "Item" member of a GetItem response.
/// Params: data - the response bytes.
/// Returns: Ok(item) (root kind M).
/// Error case: the dynamo_response_span catalog and dynamo_item_parse
/// catalog; Err("dynamo: json key not found: Item") when absent.
/// Complexity: O(len(data)).
pub fn dynamo_response_item(data: &Vec[UInt8]) -> Result[DynamoItem, Str] {
  let r = dynamo_response_span(data, "Item");
  if !r.is_ok {
    return _err_item(r.error);
  }
  let sp = r.value;
  let a: Int = sp.0;
  let b: Int = sp.1;
  return dynamo_item_parse(data, a, b);
}

/// Parse the "Items" member of a Query/Scan response.
/// Params: data - the response bytes.
/// Returns: Ok(items) with every item merged into one tape.
/// Error case: the dynamo_response_span catalog, Err("dynamo: Items must
/// be an array at offset N") or the dynamo_item_parse catalog.
/// Complexity: O(len(data)).
pub fn dynamo_response_items(data: &Vec[UInt8]) -> Result[DynamoItems, Str] {
  let r = dynamo_response_span(data, "Items");
  if !r.is_ok {
    return _err_items(r.error);
  }
  let sp = r.value;
  let a: Int = sp.0;
  let b: Int = sp.1;
  if a >= b || _vbyte(data, a) != _DYN_LBRACKET {
    return _err_items(_perr("Items must be an array", a));
  }
  var tape = dynamo_value_new();
  var nodes = Vec[Int].new();
  var i = _skip_ws(data, a + 1, b);
  if i < b && _vbyte(data, i) == _DYN_RBRACKET {
    return _ok_items(DynamoItems{ tape: tape; nodes: nodes; });
  }
  var closed = false;
  while i < b && !closed {
    let er = _scan_value(data, i, b);
    if !er.is_ok {
      return _err_items(er.error);
    }
    let esp = er.value;
    let ea: Int = esp.0;
    let eb: Int = esp.1;
    let ir = dynamo_item_parse(data, ea, eb);
    if !ir.is_ok {
      return _err_items(ir.error);
    }
    let it = ir.value;
    let vnode0 = dynamo_item_node(&it);
    let vt: DynamoValue = it.values;
    let off = dynamo_value_merge(&mut tape, &vt);
    nodes.push(vnode0 + off);
    i = _skip_ws(data, eb, b);
    if i >= b {
      return _err_items(_perr("truncated Items array", i));
    }
    let c = _vbyte(data, i);
    if c == _DYN_COMMA {
      i = _skip_ws(data, i + 1, b);
    } elif c == _DYN_RBRACKET {
      closed = true;
    } else {
      return _err_items(_perr("expected ',' or ']' in Items", i));
    }
  }
  if !closed {
    return _err_items(_perr("truncated Items array", i));
  }
  return _ok_items(DynamoItems{ tape: tape; nodes: nodes; });
}

/// Number of items in a DynamoItems payload.
/// Params: items - the payload. Returns: the count.
/// Error case: none. Complexity: O(1).
pub fn dynamo_items_count(items: &DynamoItems) -> Int {
  return items.nodes.len();
}

/// Root node of item i (-1 when out of range).
/// Params: items - the payload; i - the index.
/// Returns: the node. Error case: none. Complexity: O(1).
pub fn dynamo_items_node_at(items: &DynamoItems, i: Int) -> Int {
  if i < 0 || i >= items.nodes.len() {
    return -1;
  }
  let n: Int = items.nodes[i];
  return n;
}

/// Item i as a DynamoItem (node -1 when out of range).
/// Params: items - the payload; i - the index.
/// Returns: the item. Error case: none. Complexity: O(1).
pub fn dynamo_items_get(items: &DynamoItems, i: Int) -> DynamoItem {
  let n = dynamo_items_node_at(items, i);
  let t: DynamoValue = items.tape;
  return DynamoItem{ values: t; node: n; };
}

/// Parse the "LastEvaluatedKey" member (absent -> present false).
/// Params: data - the response bytes. Returns: the payload.
/// Error case: the dynamo_item_parse catalog when the member is present
/// but malformed.
/// Complexity: O(len(data)).
pub fn dynamo_response_last_key(data: &Vec[UInt8]) -> DynamoLastKey {
  let r = dynamo_response_span(data, "LastEvaluatedKey");
  if !r.is_ok {
    let empty = dynamo_item_new_map();
    return DynamoLastKey{ present: false; item: empty; };
  }
  let sp = r.value;
  let a: Int = sp.0;
  let b: Int = sp.1;
  let ir = dynamo_item_parse(data, a, b);
  if !ir.is_ok {
    let empty2 = dynamo_item_new_map();
    return DynamoLastKey{ present: false; item: empty2; };
  }
  let it = ir.value;
  return DynamoLastKey{ present: true; item: it; };
}

/// Parse the "Count" and "ScannedCount" members.
/// Params: data - the response bytes. Returns: the counts payload.
/// Error case: none (malformed members leave present false).
/// Complexity: O(len(data)).
pub fn dynamo_response_counts(data: &Vec[UInt8]) -> DynamoCounts {
  var count = 0;
  var cp = false;
  var scanned = 0;
  var sp2 = false;
  let r = dynamo_response_span(data, "Count");
  if r.is_ok {
    let sp = r.value;
    let a: Int = sp.0;
    let b: Int = sp.1;
    let iv = _parse_int_span(data, a, b);
    if iv.is_ok {
      count = iv.value;
      cp = true;
    }
  }
  let r2 = dynamo_response_span(data, "ScannedCount");
  if r2.is_ok {
    let sp3 = r2.value;
    let a2: Int = sp3.0;
    let b2: Int = sp3.1;
    let iv2 = _parse_int_span(data, a2, b2);
    if iv2.is_ok {
      scanned = iv2.value;
      sp2 = true;
    }
  }
  return DynamoCounts{ count: count; count_present: cp; scanned_count: scanned; scanned_present: sp2; };
}

// Decode member i of a parallel member list as a Str ("" when missing);
// string spans are unescaped, bare scalars (numbers) are kept verbatim.
fn _member_str_at(data: &Vec[UInt8], i: Int, starts: &Vec[Int], ends: &Vec[Int]) -> Str {
  if i < 0 || i >= starts.len() {
    return "";
  }
  let a: Int = starts[i];
  let b: Int = ends[i];
  if a < b && _vbyte(data, a) == _DYN_QUOTE {
    let sr = _span_str(data, a, b, "response string");
    if !sr.is_ok {
      return "";
    }
    let v: Str = sr.value;
    return v;
  }
  return _span_text(data, a, b);
}

// Capacity-units text from an object span; returns "" when absent.
fn _capacity_units_of(data: &Vec[UInt8], a: Int, b: Int) -> Str {
  var names = Vec[Str].new();
  var starts = Vec[Int].new();
  var ends = Vec[Int].new();
  let mr = _obj_members(data, a, b, &mut names, &mut starts, &mut ends);
  if !mr.is_ok {
    return "";
  }
  let idx = _member_index(&names, "CapacityUnits");
  return _member_str_at(data, idx, &starts, &ends);
}

// Read/write units of an object span by member name.
fn _capacity_field(data: &Vec[UInt8], a: Int, b: Int, key: Str) -> Str {
  var names = Vec[Str].new();
  var starts = Vec[Int].new();
  var ends = Vec[Int].new();
  let mr = _obj_members(data, a, b, &mut names, &mut starts, &mut ends);
  if !mr.is_ok {
    return "";
  }
  let idx = _member_index(&names, key);
  return _member_str_at(data, idx, &starts, &ends);
}

// Append the index breakdown of an indexes object span.
fn _collect_index_breakdown(data: &Vec[UInt8], a: Int, b: Int, names_out: &mut Vec[Str], units_out: &mut Vec[Str], reads_out: &mut Vec[Str], writes_out: &mut Vec[Str]) {
  var names = Vec[Str].new();
  var starts = Vec[Int].new();
  var ends = Vec[Int].new();
  let mr = _obj_members(data, a, b, &mut names, &mut starts, &mut ends);
  if !mr.is_ok {
    return;
  }
  var i = 0;
  while i < names.len() {
    let a2: Int = starts[i];
    let b2: Int = ends[i];
    let iname: Str = names[i];
    names_out.push(iname);
    units_out.push(_capacity_units_of(data, a2, b2));
    reads_out.push(_capacity_field(data, a2, b2, "ReadCapacityUnits"));
    writes_out.push(_capacity_field(data, a2, b2, "WriteCapacityUnits"));
    i = i + 1;
  }
}

/// Parse the "ConsumedCapacity" member (object or first array element).
/// Params: data - the response bytes. Returns: the capacity payload.
/// Error case: none (malformed members are left "").
/// Complexity: O(len(data)).
pub fn dynamo_response_capacity(data: &Vec[UInt8]) -> DynamoCapacity {
  var cap = DynamoCapacity{
    present: false;
    table_name: "";
    capacity_units: "";
    read_units: "";
    write_units: "";
    table_units: "";
    table_read_units: "";
    table_write_units: "";
    index_names: Vec[Str].new();
    index_units: Vec[Str].new();
    index_read_units: Vec[Str].new();
    index_write_units: Vec[Str].new();
  };
  let r = dynamo_response_span(data, "ConsumedCapacity");
  if !r.is_ok {
    return cap;
  }
  let sp = r.value;
  var a: Int = sp.0;
  var b: Int = sp.1;
  if a < b && _vbyte(data, a) == _DYN_LBRACKET {
    var i = _skip_ws(data, a + 1, b);
    if i >= b || _vbyte(data, i) != _DYN_LBRACE {
      return cap;
    }
    let er = _scan_value(data, i, b);
    if !er.is_ok {
      return cap;
    }
    let esp = er.value;
    a = esp.0;
    b = esp.1;
  }
  if a >= b || _vbyte(data, a) != _DYN_LBRACE {
    return cap;
  }
  var names = Vec[Str].new();
  var starts = Vec[Int].new();
  var ends = Vec[Int].new();
  let mr = _obj_members(data, a, b, &mut names, &mut starts, &mut ends);
  if !mr.is_ok {
    return cap;
  }
  cap.present = true;
  cap.table_name = _member_str_at(data, _member_index(&names, "TableName"), &starts, &ends);
  cap.capacity_units = _member_str_at(data, _member_index(&names, "CapacityUnits"), &starts, &ends);
  cap.read_units = _member_str_at(data, _member_index(&names, "ReadCapacityUnits"), &starts, &ends);
  cap.write_units = _member_str_at(data, _member_index(&names, "WriteCapacityUnits"), &starts, &ends);
  let ti = _member_index(&names, "Table");
  if ti >= 0 {
    let ta: Int = starts[ti];
    let tb: Int = ends[ti];
    if ta < tb && _vbyte(data, ta) == _DYN_LBRACE {
      cap.table_units = _capacity_units_of(data, ta, tb);
      cap.table_read_units = _capacity_field(data, ta, tb, "ReadCapacityUnits");
      cap.table_write_units = _capacity_field(data, ta, tb, "WriteCapacityUnits");
    }
  }
  let gi = _member_index(&names, "GlobalSecondaryIndexes");
  if gi >= 0 {
    let ga: Int = starts[gi];
    let gb: Int = ends[gi];
    if ga < gb && _vbyte(data, ga) == _DYN_LBRACE {
      var inames: Vec[Str] = cap.index_names;
      var iunits: Vec[Str] = cap.index_units;
      var ireads: Vec[Str] = cap.index_read_units;
      var iwrites: Vec[Str] = cap.index_write_units;
      _collect_index_breakdown(data, ga, gb, &mut inames, &mut iunits, &mut ireads, &mut iwrites);
      cap.index_names = inames;
      cap.index_units = iunits;
      cap.index_read_units = ireads;
      cap.index_write_units = iwrites;
    }
  }
  let li = _member_index(&names, "LocalSecondaryIndexes");
  if li >= 0 {
    let la: Int = starts[li];
    let lb: Int = ends[li];
    if la < lb && _vbyte(data, la) == _DYN_LBRACE {
      var inames2: Vec[Str] = cap.index_names;
      var iunits2: Vec[Str] = cap.index_units;
      var ireads2: Vec[Str] = cap.index_read_units;
      var iwrites2: Vec[Str] = cap.index_write_units;
      _collect_index_breakdown(data, la, lb, &mut inames2, &mut iunits2, &mut ireads2, &mut iwrites2);
      cap.index_names = inames2;
      cap.index_units = iunits2;
      cap.index_read_units = ireads2;
      cap.index_write_units = iwrites2;
    }
  }
  return cap;
}

/// Number of index breakdown entries in a capacity payload.
/// Params: cap - the payload. Returns: the count.
/// Error case: none. Complexity: O(1).
pub fn dynamo_capacity_index_count(cap: &DynamoCapacity) -> Int {
  return cap.index_names.len();
}

/// Index name i of a capacity payload ("" when out of range).
/// Params: cap - the payload; i - the index. Returns: the name.
/// Error case: none. Complexity: O(1).
pub fn dynamo_capacity_index_name_at(cap: &DynamoCapacity, i: Int) -> Str {
  if i < 0 || i >= cap.index_names.len() {
    return "";
  }
  let v: Str = cap.index_names[i];
  return v;
}

/// Index CapacityUnits i of a capacity payload ("" when out of range).
/// Params: cap - the payload; i - the index. Returns: the units text.
/// Error case: none. Complexity: O(1).
pub fn dynamo_capacity_index_units_at(cap: &DynamoCapacity, i: Int) -> Str {
  if i < 0 || i >= cap.index_units.len() {
    return "";
  }
  let v: Str = cap.index_units[i];
  return v;
}

// Shared unprocessed parser.
fn _unprocessed(data: &Vec[UInt8], key: Str) -> DynamoUnprocessed {
  var u = DynamoUnprocessed{ present: false; table_names: Vec[Str].new(); payloads: Vec[Str].new(); };
  let r = dynamo_response_span(data, key);
  if !r.is_ok {
    return u;
  }
  let sp = r.value;
  let a: Int = sp.0;
  let b: Int = sp.1;
  if a >= b || _vbyte(data, a) != _DYN_LBRACE {
    return u;
  }
  var names = Vec[Str].new();
  var starts = Vec[Int].new();
  var ends = Vec[Int].new();
  let mr = _obj_members(data, a, b, &mut names, &mut starts, &mut ends);
  if !mr.is_ok {
    return u;
  }
  u.present = true;
  var i = 0;
  while i < names.len() {
    let nm: Str = names[i];
    let va: Int = starts[i];
    let vb: Int = ends[i];
    u.table_names.push(nm);
    u.payloads.push(_span_text(data, va, vb));
    i = i + 1;
  }
  return u;
}

/// Parse the "UnprocessedItems" member (BatchWriteItem).
/// Params: data - the response bytes. Returns: the payload.
/// Error case: none. Complexity: O(len(data)).
pub fn dynamo_response_unprocessed_items(data: &Vec[UInt8]) -> DynamoUnprocessed {
  return _unprocessed(data, "UnprocessedItems");
}

/// Parse the "UnprocessedKeys" member (BatchGetItem).
/// Params: data - the response bytes. Returns: the payload.
/// Error case: none. Complexity: O(len(data)).
pub fn dynamo_response_unprocessed_keys(data: &Vec[UInt8]) -> DynamoUnprocessed {
  return _unprocessed(data, "UnprocessedKeys");
}

/// Parse the {__type, message} error envelope.
/// Params: data - the response bytes. Returns: the payload (has_error
/// false when no __type member is present).
/// Error case: none. Complexity: O(len(data)).
pub fn dynamo_response_error(data: &Vec[UInt8]) -> DynamoApiError {
  var out = DynamoApiError{ has_error: false; error_type: ""; message: ""; };
  let r = dynamo_response_span(data, "__type");
  if !r.is_ok {
    return out;
  }
  let sp = r.value;
  let a: Int = sp.0;
  let b: Int = sp.1;
  let tr = _span_str(data, a, b, "error __type");
  if tr.is_ok {
    let v: Str = tr.value;
    out.error_type = v;
    out.has_error = true;
  }
  let r2 = dynamo_response_span(data, "message");
  if r2.is_ok {
    let sp2 = r2.value;
    let a2: Int = sp2.0;
    let b2: Int = sp2.1;
    let mr = _span_str(data, a2, b2, "error message");
    if mr.is_ok {
      let v2: Str = mr.value;
      out.message = v2;
      out.has_error = true;
    }
  }
  return out;
}

/// True when the response is a DynamoDB error envelope.
/// Params: data - the response bytes. Returns: the predicate.
/// Error case: none. Complexity: O(len(data)).
pub fn dynamo_response_is_error(data: &Vec[UInt8]) -> Bool {
  let e = dynamo_response_error(data);
  return e.has_error;
}
