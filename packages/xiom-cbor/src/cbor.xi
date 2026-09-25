// XIOM -- xiom.cbor: pure-XIOM CBOR encoding and decoding
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// CBOR (RFC 8949, Concise Binary Object Representation) encodes every item in
// an initial byte `(major_type * 32) + additional_info` followed by an
// optional big-endian argument. This module implements a strict, documented
// subset in pure XIOM:
//
//   * major type 0 (unsigned integer) and major type 1 (negative integer,
//     value = -1 - argument);
//   * major type 2 (byte string) and major type 3 (text string);
//   * major type 4 (array) and major type 5 (map) with definite lengths;
//   * major type 7 simple values 20 (false), 21 (true), 22 (null) and
//     23 (undefined);
//   * definite lengths only, and the shortest-form argument required on
//     decode: additional info 24/25/26/27 must carry an argument that does
//     not fit the smaller forms (>= 24 / >= 256 / >= 65536 / >= 2^32);
//   * the token stream is stored flat -- parallel Vec fields, no
//     Vec[StructType] -- in depth-first pre-order: every subtree occupies a
//     contiguous token range, a container owns its direct children through
//     `first_child` + `child_count`, and direct children are linked by
//     `next_sibling` (needed because subtrees interleave the pre-order
//     sequence); every token is O(1)-indexable and O(1)-parented;
//   * `cbor_encode_*` emits canonical shortest-form bytes, and
//     `cbor_encode_map` sorts pairs by the bytewise lexicographic order of
//     the encoded keys (RFC 8949 core deterministic encoding) and rejects
//     duplicate keys;
//   * `cbor_decode` validates every structural rule it implements and returns
//     deterministic Err(Str) messages (truncation, reserved additional info,
//     indefinite lengths, tags, floats, simple values, breaks, length and
//     integer overflow, non-shortest form, trailing data, nesting depth);
//   * `cbor_reserialize` rebuilds the exact accepted bytes of a decoded
//     document from the token stream alone (map key order included).
//
// Non-goals: no tags (major type 6), no floats/half-floats (major type 7
// additional info 25/26/27), no indefinite-length items, no CBOR sequences,
// no semantic tags (dates, bignums) and no UTF-8 validation (text strings
// are opaque bytes).
//
// v0.61.3 notes that shaped this module:
//   * free functions only, no self methods; state travels by reference.
//   * Ok/Err construction is confined to the tiny leaf helpers below
//     (constructing Results inside other functions miscompiles).
//   * every byte read from a Vec[UInt8] is widened with
//     `(data[pos] as Int) & 0xFF` before entering Int arithmetic or
//     comparisons; every Vec[Int] element read is bound to a typed local
//     first (untyped element reads can mis-lower to Str comparisons).
//   * `&struct.field` is never passed where a `&Vec[UInt8]` parameter is
//     expected (that yields an empty vector); bytes are copied through
//     helpers that take the owning struct reference.
//   * big-endian integer arguments are decoded with an explicit
//     positive-accumulator overflow check, and encoded with arithmetic byte
//     extraction (no bit tricks on sign-extended UInt8 constants).

module xiom.cbor

use xiom.string;
use xiom.string.builder;

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(v) for Result[Int, Str].
fn _ok_int(v: Int) -> Result[Int, Str] {
  return Ok(v);
}

// Err(m) for Result[Int, Str].
fn _err_int(m: Str) -> Result[Int, Str] {
  return Err(m);
}

// Ok(v) for Result[CborDoc, Str].
fn _ok_doc(v: CborDoc) -> Result[CborDoc, Str] {
  return Ok(v);
}

// Err(m) for Result[CborDoc, Str].
fn _err_doc(m: Str) -> Result[CborDoc, Str] {
  return Err(m);
}

// Ok(v) for Result[Vec[UInt8], Str].
fn _ok_bytes(v: Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  return Ok(v);
}

// Err(m) for Result[Vec[UInt8], Str].
fn _err_bytes(m: Str) -> Result[Vec[UInt8], Str] {
  return Err(m);
}

// --------------------------------------------------
//  Types
// --------------------------------------------------

/// Parsed CBOR document: the source bytes plus a flat token stream.
///
/// Tokens are stored in depth-first pre-order in parallel vectors (one entry
/// per token); token 0 is the root value. `kind` holds one of the
/// `cbor_kind_*` codes. For arrays and maps, `first_child[i]` is the first
/// direct child and `child_count[i]` the number of direct children (twice
/// the pair count for a map); each direct child links to the next one through
/// `next_sibling` (-1 on the last child), because a child's own subtree
/// occupies the tokens immediately after it. For leaves, `first_child` is -1,
/// `next_sibling` is -1 and `child_count` is 0. `start`/`end` delimit the
/// whole token, `payload_start`/`payload_end` delimit a byte/text string's
/// payload bytes, and `value` holds the parsed integer (major type 0/1), the
/// boolean (0/1 for false/true), or a string's payload byte length.
///
/// Fields are implementation details; callers should use the free accessors
/// below. Documents are only produced by `cbor_decode`, so the token stream
/// always satisfies the format invariants (shortest-form arguments, definite
/// lengths).
pub type CborDoc = {
  data: Vec[UInt8];
  kind: Vec[Int];
  parent: Vec[Int];
  first_child: Vec[Int];
  child_count: Vec[Int];
  next_sibling: Vec[Int];
  start: Vec[Int];
  end: Vec[Int];
  payload_start: Vec[Int];
  payload_end: Vec[Int];
  value: Vec[Int];
}

// Internal mutable decode state: the token vectors plus the cursor. The
// fields mirror CborDoc; _finish copies them into the public type.
type _CborParser = {
  data: Vec[UInt8];
  pos: Int;
  kind: Vec[Int];
  parent: Vec[Int];
  first_child: Vec[Int];
  child_count: Vec[Int];
  next_sibling: Vec[Int];
  start: Vec[Int];
  end: Vec[Int];
  payload_start: Vec[Int];
  payload_end: Vec[Int];
  value: Vec[Int];
}

// --------------------------------------------------
//  Public constants and codec metadata
// --------------------------------------------------

/// Token kind code for a major type 0 unsigned integer.
pub fn cbor_kind_uint() -> Int {
  return 0;
}

/// Token kind code for a major type 1 negative integer (value = -1 - arg).
pub fn cbor_kind_negint() -> Int {
  return 1;
}

/// Token kind code for a major type 2 byte string.
pub fn cbor_kind_bytes() -> Int {
  return 2;
}

/// Token kind code for a major type 3 text string.
pub fn cbor_kind_text() -> Int {
  return 3;
}

/// Token kind code for a major type 4 array.
pub fn cbor_kind_array() -> Int {
  return 4;
}

/// Token kind code for a major type 5 map.
pub fn cbor_kind_map() -> Int {
  return 5;
}

/// Token kind code for a major type 7 boolean (value 0 = false, 1 = true).
pub fn cbor_kind_bool() -> Int {
  return 6;
}

/// Token kind code for a major type 7 null (0xf6).
pub fn cbor_kind_null() -> Int {
  return 7;
}

/// Token kind code for a major type 7 undefined (0xf7).
pub fn cbor_kind_undefined() -> Int {
  return 8;
}

/// Documented maximum container nesting depth accepted by the decoder.
///
/// The top-level value has depth 0, so a container at depth 63 is the
/// deepest accepted one; a container at depth 64 is rejected with
/// `Err("cbor: nesting depth exceeds limit of 64")`. Both arrays and maps
/// count against the same limit.
pub fn cbor_max_depth() -> Int {
  return 64;
}

// --------------------------------------------------
//  Byte helpers
// --------------------------------------------------

// Big-endian byte `shift_bytes` of `v` (0 = least significant byte).
// Arithmetic only: `& 0xFF` on values with bit 31 set miscompiles in
// v0.61.3, and this form is exact for the two's-complement bit pattern.
fn _be_byte(v: Int, shift_bytes: Int) -> UInt8 {
  var q = v;
  var k = 0;
  while k < shift_bytes {
    var r = q % 256;
    if r < 0 { r = r + 256; }
    q = (q - r) / 256;
    k = k + 1;
  }
  var b = q % 256;
  if b < 0 { b = b + 256; }
  return b as UInt8;
}

// Append the low `size` bytes of `v` in big-endian order.
fn _push_be(out: &mut Vec[UInt8], v: Int, size: Int) {
  var i = size - 1;
  while i >= 0 {
    out.push(_be_byte(v, i));
    i = i - 1;
  }
}

// Append the canonical (shortest-form) CBOR header for `major` with argument
// `arg` (0 <= arg <= INT64_MAX): initial byte plus the minimal argument
// width, as required by RFC 8949 preferred serialization.
fn _push_head(out: &mut Vec[UInt8], major: Int, arg: Int) {
  let m = major * 32;
  if arg < 24 {
    out.push((m + arg) as UInt8);
    return;
  }
  if arg <= 255 {
    out.push((m + 24) as UInt8);
    _push_be(out, arg, 1);
    return;
  }
  if arg <= 65535 {
    out.push((m + 25) as UInt8);
    _push_be(out, arg, 2);
    return;
  }
  if arg <= 4294967295 {
    out.push((m + 26) as UInt8);
    _push_be(out, arg, 4);
    return;
  }
  out.push((m + 27) as UInt8);
  _push_be(out, arg, 8);
}

// Byte at `pos` of the parser buffer widened to an Int (0..255).
fn _pbyte(p: &_CborParser, pos: Int) -> Int {
  return (p.data[pos] as Int) & 0xFF;
}

// Same as _pbyte but takes &mut, so parser bodies never mix a `&` call
// before a `&mut` access on the same local (advisory E001).
fn _pbyte_mut(p: &mut _CborParser, pos: Int) -> Int {
  return _pbyte(p, pos);
}

// Unsigned byte-wise lexicographic comparison of two byte vectors:
// -1 when a < b, 0 when equal, 1 when a > b.
fn _cmp_bytes(a: &Vec[UInt8], b: &Vec[UInt8]) -> Int {
  let la = a.len();
  let lb = b.len();
  var m = la;
  if lb < m { m = lb; }
  var i = 0;
  while i < m {
    let ca: UInt8 = a[i];
    let cb: UInt8 = b[i];
    let xa = (ca as Int) & 0xFF;
    let xb = (cb as Int) & 0xFF;
    if xa < xb { return -1; }
    if xa > xb { return 1; }
    i = i + 1;
  }
  if la < lb { return -1; }
  if la > lb { return 1; }
  return 0;
}

// Append every byte of `v` to `out`.
fn _push_vec(out: &mut Vec[UInt8], v: &Vec[UInt8]) {
  var i = 0;
  while i < v.len() {
    out.push(v[i]);
    i = i + 1;
  }
}

// --------------------------------------------------
//  Token bookkeeping
// --------------------------------------------------

// Append a placeholder token and return its index. Placeholders are filled
// in by the caller once the value's extent is known.
fn _push_token(p: &mut _CborParser, kind: Int, parent: Int, start: Int) -> Int {
  let idx = p.kind.len();
  p.kind.push(kind);
  p.parent.push(parent);
  p.first_child.push(-1);
  p.child_count.push(0);
  p.next_sibling.push(-1);
  p.start.push(start);
  p.end.push(0);
  p.payload_start.push(0);
  p.payload_end.push(0);
  p.value.push(0);
  return idx;
}

// Move the parser's token vectors into the public document type, dropping
// the cursor.
fn _finish(p: _CborParser) -> CborDoc {
  let data: Vec[UInt8] = p.data;
  let kind: Vec[Int] = p.kind;
  let parent: Vec[Int] = p.parent;
  let first_child: Vec[Int] = p.first_child;
  let child_count: Vec[Int] = p.child_count;
  let next_sibling: Vec[Int] = p.next_sibling;
  let start: Vec[Int] = p.start;
  let end: Vec[Int] = p.end;
  let payload_start: Vec[Int] = p.payload_start;
  let payload_end: Vec[Int] = p.payload_end;
  let value: Vec[Int] = p.value;
  return CborDoc{
    data: data;
    kind: kind;
    parent: parent;
    first_child: first_child;
    child_count: child_count;
    next_sibling: next_sibling;
    start: start;
    end: end;
    payload_start: payload_start;
    payload_end: payload_end;
    value: value;
  };
}

// --------------------------------------------------
//  Error message helpers
// --------------------------------------------------

// The documented message for a reserved additional-info value (28..30).
fn _reserved_msg(ai: Int) -> Str {
  if ai == 28 {
    return "cbor: reserved additional info 28";
  }
  if ai == 29 {
    return "cbor: reserved additional info 29";
  }
  return "cbor: reserved additional info 30";
}

// The documented nesting-depth error.
fn _depth_msg() -> Str {
  return "cbor: nesting depth exceeds limit of 64";
}

// --------------------------------------------------
//  Decoder
// --------------------------------------------------

// Read and validate an argument for additional info `ai` (0..27). The cursor
// must be on the initial byte, which this function consumes; on success the
// cursor sits one past the argument. `as_length` selects the overflow
// message: string/array/map lengths report `cbor: length overflow`, major
// type 0/1 integers report `cbor: integer out of range` (the signed 64-bit
// platform Int cannot hold the full unsigned 64-bit CBOR range).
//
// Rejects reserved additional info 28..30, indefinite length 31, arguments
// that do not fit the signed 64-bit Int, truncated arguments, and
// non-shortest forms (ai 24/25/26/27 must carry 24+/256+/65536+/2^32+).
fn _read_arg(p: &mut _CborParser, ai: Int, as_length: Bool) -> Result[Int, Str] {
  p.pos = p.pos + 1;
  if ai <= 23 {
    return _ok_int(ai);
  }
  var size = 0;
  if ai == 24 {
    size = 1;
  } elif ai == 25 {
    size = 2;
  } elif ai == 26 {
    size = 4;
  } else {
    size = 8;
  }
  let total = p.data.len();
  if p.pos + size > total {
    return _err_int("cbor: truncated input");
  }
  var v: Int = 0;
  var i = 0;
  while i < size {
    let b = (p.data[p.pos + i] as Int) & 0xFF;
    if v > (9223372036854775807 - b) / 256 {
      if as_length {
        return _err_int("cbor: length overflow");
      }
      return _err_int("cbor: integer out of range");
    }
    v = v * 256 + b;
    i = i + 1;
  }
  p.pos = p.pos + size;
  if ai == 24 && v < 24 {
    return _err_int("cbor: non-shortest form");
  }
  if ai == 25 && v < 256 {
    return _err_int("cbor: non-shortest form");
  }
  if ai == 26 && v < 65536 {
    return _err_int("cbor: non-shortest form");
  }
  if ai == 27 && v < 4294967296 {
    return _err_int("cbor: non-shortest form");
  }
  return _ok_int(v);
}

// Parse a major type 0 unsigned integer token.
fn _parse_uint(p: &mut _CborParser, ai: Int, parent: Int) -> Result[Int, Str] {
  let start = p.pos;
  let ar = _read_arg(p, ai, false);
  if !ar.is_ok {
    return _err_int(ar.error);
  }
  let idx = _push_token(p, cbor_kind_uint(), parent, start);
  let v: Int = ar.value;
  p.value[idx] = v;
  p.end[idx] = p.pos;
  return _ok_int(idx);
}

// Parse a major type 1 negative integer token. The encoded argument `n`
// represents the mathematical value -1 - n, which is exact for the whole
// signed 64-bit range (INT64_MIN needs n = INT64_MAX).
fn _parse_negint(p: &mut _CborParser, ai: Int, parent: Int) -> Result[Int, Str] {
  let start = p.pos;
  let ar = _read_arg(p, ai, false);
  if !ar.is_ok {
    return _err_int(ar.error);
  }
  let idx = _push_token(p, cbor_kind_negint(), parent, start);
  let v: Int = -1 - ar.value;
  p.value[idx] = v;
  p.end[idx] = p.pos;
  return _ok_int(idx);
}

// Parse a major type 2 byte string or major type 3 text string token:
// definite length, then that many payload bytes. `kind` is
// cbor_kind_bytes() or cbor_kind_text().
fn _parse_stringlike(p: &mut _CborParser, ai: Int, parent: Int, kind: Int) -> Result[Int, Str] {
  let start = p.pos;
  let ar = _read_arg(p, ai, true);
  if !ar.is_ok {
    return _err_int(ar.error);
  }
  let n = ar.value;
  let idx = _push_token(p, kind, parent, start);
  let remaining = p.data.len() - p.pos;
  if n > remaining {
    return _err_int("cbor: truncated input");
  }
  p.payload_start[idx] = p.pos;
  p.payload_end[idx] = p.pos + n;
  p.value[idx] = n;
  p.pos = p.pos + n;
  p.end[idx] = p.pos;
  return _ok_int(idx);
}

// Parse a major type 4 array token: definite element count, then that many
// values. The element count is rejected as truncation when it exceeds the
// bytes that remain (every element needs at least one byte), which keeps the
// parse linear even for hostile headers.
fn _parse_array(p: &mut _CborParser, ai: Int, depth: Int, parent: Int) -> Result[Int, Str] {
  if depth >= cbor_max_depth() {
    return _err_int(_depth_msg());
  }
  let start = p.pos;
  let ar = _read_arg(p, ai, true);
  if !ar.is_ok {
    return _err_int(ar.error);
  }
  let count = ar.value;
  let remaining = p.data.len() - p.pos;
  if count > remaining {
    return _err_int("cbor: truncated input");
  }
  let idx = _push_token(p, cbor_kind_array(), parent, start);
  var first: Int = -1;
  var prev: Int = -1;
  var i = 0;
  while i < count {
    let child = _parse_value(p, depth + 1, idx);
    if !child.is_ok {
      return _err_int(child.error);
    }
    if first == -1 {
      first = child.value;
    }
    if prev >= 0 {
      p.next_sibling[prev] = child.value;
    }
    prev = child.value;
    i = i + 1;
  }
  p.end[idx] = p.pos;
  p.first_child[idx] = first;
  p.child_count[idx] = count;
  return _ok_int(idx);
}

// Parse a major type 5 map token: definite pair count, then that many
// key/value pairs. Any value may be a key; key order is not validated (any
// order is accepted) and `cbor_reserialize` preserves the decoded order.
fn _parse_map(p: &mut _CborParser, ai: Int, depth: Int, parent: Int) -> Result[Int, Str] {
  if depth >= cbor_max_depth() {
    return _err_int(_depth_msg());
  }
  let start = p.pos;
  let ar = _read_arg(p, ai, true);
  if !ar.is_ok {
    return _err_int(ar.error);
  }
  let pairs = ar.value;
  let remaining = p.data.len() - p.pos;
  if pairs > remaining / 2 {
    return _err_int("cbor: truncated input");
  }
  let idx = _push_token(p, cbor_kind_map(), parent, start);
  var first: Int = -1;
  var prev: Int = -1;
  var i = 0;
  while i < pairs {
    let key = _parse_value(p, depth + 1, idx);
    if !key.is_ok {
      return _err_int(key.error);
    }
    if first == -1 {
      first = key.value;
    }
    if prev >= 0 {
      p.next_sibling[prev] = key.value;
    }
    prev = key.value;
    let val = _parse_value(p, depth + 1, idx);
    if !val.is_ok {
      return _err_int(val.error);
    }
    p.next_sibling[prev] = val.value;
    prev = val.value;
    i = i + 1;
  }
  p.end[idx] = p.pos;
  p.first_child[idx] = first;
  p.child_count[idx] = pairs * 2;
  return _ok_int(idx);
}

// Parse a major type 7 token. Only false (ai 20), true (ai 21), null (ai 22)
// and undefined (ai 23) are supported; ai 24 simple values, ai 0..19 simple
// values and ai 25/26/27 floats are rejected with documented messages, and
// ai 31 (break) is only valid inside an indefinite-length item, which this
// subset never accepts.
fn _parse_major7(p: &mut _CborParser, ai: Int, parent: Int) -> Result[Int, Str] {
  let start = p.pos;
  if ai == 20 {
    let idx = _push_token(p, cbor_kind_bool(), parent, start);
    p.value[idx] = 0;
    p.pos = p.pos + 1;
    p.end[idx] = p.pos;
    return _ok_int(idx);
  }
  if ai == 21 {
    let idx = _push_token(p, cbor_kind_bool(), parent, start);
    p.value[idx] = 1;
    p.pos = p.pos + 1;
    p.end[idx] = p.pos;
    return _ok_int(idx);
  }
  if ai == 22 {
    let idx = _push_token(p, cbor_kind_null(), parent, start);
    p.pos = p.pos + 1;
    p.end[idx] = p.pos;
    return _ok_int(idx);
  }
  if ai == 23 {
    let idx = _push_token(p, cbor_kind_undefined(), parent, start);
    p.pos = p.pos + 1;
    p.end[idx] = p.pos;
    return _ok_int(idx);
  }
  if ai == 24 {
    if p.pos + 1 >= p.data.len() {
      return _err_int("cbor: truncated input");
    }
    let sv = (p.data[p.pos + 1] as Int) & 0xFF;
    if sv < 32 {
      return _err_int("cbor: non-shortest form");
    }
    return _err_int("cbor: simple values not supported");
  }
  if ai >= 25 && ai <= 27 {
    return _err_int("cbor: floats not supported");
  }
  return _err_int("cbor: simple values not supported");
}

// Parse one value at the cursor and return its token index. `depth` is the
// number of enclosing containers (the root value is depth 0); `parent` is
// the enclosing token index, or -1 at the root.
fn _parse_value(p: &mut _CborParser, depth: Int, parent: Int) -> Result[Int, Str] {
  if p.pos >= p.data.len() {
    return _err_int("cbor: truncated input");
  }
  let b = _pbyte_mut(p, p.pos);
  let major = b / 32;
  let ai = b % 32;
  if ai >= 28 && ai <= 30 {
    return _err_int(_reserved_msg(ai));
  }
  if ai == 31 {
    if major == 7 {
      return _err_int("cbor: break outside indefinite item");
    }
    if major >= 2 && major <= 5 {
      return _err_int("cbor: indefinite length not supported");
    }
    return _err_int("cbor: reserved additional info 31");
  }
  if major == 0 {
    return _parse_uint(p, ai, parent);
  }
  if major == 1 {
    return _parse_negint(p, ai, parent);
  }
  if major == 2 {
    return _parse_stringlike(p, ai, parent, cbor_kind_bytes());
  }
  if major == 3 {
    return _parse_stringlike(p, ai, parent, cbor_kind_text());
  }
  if major == 4 {
    return _parse_array(p, ai, depth, parent);
  }
  if major == 5 {
    return _parse_map(p, ai, depth, parent);
  }
  if major == 6 {
    return _err_int("cbor: tags not supported");
  }
  return _parse_major7(p, ai, parent);
}

/// Decode one complete CBOR value from `data`.
///
/// The result is a `CborDoc` holding the input bytes and the flat token
/// stream; use the `cbor_*` accessors to inspect it. `data` must contain
/// exactly one value: bytes after the top-level value are rejected.
///
/// Err("cbor: truncated input") when the buffer ends inside a value, header
/// or payload; Err("cbor: reserved additional info NN") for additional info
/// 28..30 (and 31 on major types 0, 1 and 6); Err("cbor: indefinite length
/// not supported") for additional info 31 on major types 2..5;
/// Err("cbor: break outside indefinite item") for 0xff where a value is
/// expected; Err("cbor: tags not supported") for major type 6;
/// Err("cbor: floats not supported") for major type 7 additional info
/// 25/26/27; Err("cbor: simple values not supported") for the other
/// unsupported major type 7 values; Err("cbor: non-shortest form") when an
/// argument could have used a smaller encoding; Err("cbor: length
/// overflow") / Err("cbor: integer out of range") when an argument does not
/// fit the signed 64-bit Int; Err("cbor: trailing data after top-level
/// value") when bytes remain after the root value; Err("cbor: nesting depth
/// exceeds limit of 64") when a container is nested deeper than
/// `cbor_max_depth()`.
/// Complexity: O(data.len()).
pub fn cbor_decode(data: Vec[UInt8]) -> Result[CborDoc, Str] {
  var p = _CborParser{
    data: data;
    pos: 0;
    kind: Vec[Int].new();
    parent: Vec[Int].new();
    first_child: Vec[Int].new();
    child_count: Vec[Int].new();
    next_sibling: Vec[Int].new();
    start: Vec[Int].new();
    end: Vec[Int].new();
    payload_start: Vec[Int].new();
    payload_end: Vec[Int].new();
    value: Vec[Int].new();
  };
  let root = _parse_value(&mut p, 0, -1);
  if !root.is_ok {
    return _err_doc(root.error);
  }
  if p.pos != p.data.len() {
    return _err_doc("cbor: trailing data after top-level value");
  }
  return _ok_doc(_finish(p));
}

// --------------------------------------------------
//  Token accessors
// --------------------------------------------------

/// Number of tokens in the document (1 for a scalar root value, and one
/// token per array element / map key and value).
/// Complexity: O(1).
pub fn cbor_token_count(doc: &CborDoc) -> Int {
  return doc.kind.len();
}

/// Index of the root token: always 0 for a document produced by
/// `cbor_decode` (kept as a named accessor for symmetry).
/// Complexity: O(1).
pub fn cbor_root(doc: &CborDoc) -> Int {
  if doc.kind.len() == 0 {
    return -1;
  }
  return 0;
}

/// Kind code of token `i` (one of the `cbor_kind_*` values), or -1 when `i`
/// is outside [0, cbor_token_count(doc)).
/// Complexity: O(1).
pub fn cbor_kind(doc: &CborDoc, i: Int) -> Int {
  if i < 0 || i >= doc.kind.len() {
    return -1;
  }
  let k: Int = doc.kind[i];
  return k;
}

/// Index of the token that contains token `i`, or -1 for the root token and
/// for an out-of-range `i`.
/// Complexity: O(1).
pub fn cbor_parent(doc: &CborDoc, i: Int) -> Int {
  if i < 0 || i >= doc.parent.len() {
    return -1;
  }
  let v: Int = doc.parent[i];
  return v;
}

/// Index of the first direct child of token `i`, or -1 for a leaf token and
/// for an out-of-range `i`.
/// Complexity: O(1).
pub fn cbor_first_child(doc: &CborDoc, i: Int) -> Int {
  if i < 0 || i >= doc.first_child.len() {
    return -1;
  }
  let v: Int = doc.first_child[i];
  return v;
}

/// Number of direct children of token `i` (array elements, or twice the pair
/// count for a map, with keys and values alternating), or 0 for a leaf token
/// and for an out-of-range `i`.
/// Complexity: O(1).
pub fn cbor_child_count(doc: &CborDoc, i: Int) -> Int {
  if i < 0 || i >= doc.child_count.len() {
    return 0;
  }
  let v: Int = doc.child_count[i];
  return v;
}

/// Byte offset of the first byte of token `i`, or -1 when `i` is outside
/// [0, cbor_token_count(doc)).
/// Complexity: O(1).
pub fn cbor_token_start(doc: &CborDoc, i: Int) -> Int {
  if i < 0 || i >= doc.start.len() {
    return -1;
  }
  let v: Int = doc.start[i];
  return v;
}

/// Byte offset one past the last byte of token `i`, or -1 when `i` is
/// outside [0, cbor_token_count(doc)).
/// Complexity: O(1).
pub fn cbor_token_end(doc: &CborDoc, i: Int) -> Int {
  if i < 0 || i >= doc.end.len() {
    return -1;
  }
  let v: Int = doc.end[i];
  return v;
}

/// Index of the n-th direct child of token `i` (0-based), or -1 when `i` is
/// not a container or `n` is outside [0, cbor_child_count(doc, i)). Map
/// children alternate key, value: pair k is child 2*k (key) and child
/// 2*k + 1 (value).
/// Complexity: O(n).
pub fn cbor_child(doc: &CborDoc, i: Int, n: Int) -> Int {
  let count = cbor_child_count(doc, i);
  if n < 0 || n >= count {
    return -1;
  }
  var t = cbor_first_child(doc, i);
  var k = 0;
  while k < n {
    t = cbor_next_sibling(doc, t);
    k = k + 1;
  }
  return t;
}

/// Index of the next direct sibling of token `i` under the same parent, or
/// -1 when `i` is the last direct child (and for out-of-range `i`).
/// Pre-order token indices are not siblings just because they are adjacent:
/// a token's subtree sits between it and its next sibling, so callers must
/// use this accessor (or `cbor_child`) to iterate a container's children.
/// Complexity: O(1).
pub fn cbor_next_sibling(doc: &CborDoc, i: Int) -> Int {
  if i < 0 || i >= doc.next_sibling.len() {
    return -1;
  }
  let v: Int = doc.next_sibling[i];
  return v;
}

/// Parsed integer value of a uint (major type 0) or negint (major type 1)
/// token, or 0 when `i` is any other kind or is out of range (check the kind
/// first).
/// Complexity: O(1).
pub fn cbor_int_value(doc: &CborDoc, i: Int) -> Int {
  let k = cbor_kind(doc, i);
  if k != cbor_kind_uint() && k != cbor_kind_negint() {
    return 0;
  }
  let v: Int = doc.value[i];
  return v;
}

/// Boolean value of a bool token: 1 for true, 0 for false, -1 when `i` is
/// not a bool token or is out of range.
/// Complexity: O(1).
pub fn cbor_bool_value(doc: &CborDoc, i: Int) -> Int {
  if cbor_kind(doc, i) != cbor_kind_bool() {
    return -1;
  }
  let v: Int = doc.value[i];
  return v;
}

/// Byte length of a byte-string token's payload, or -1 when `i` is not a
/// bytes token or is out of range.
/// Complexity: O(1).
pub fn cbor_bytes_len(doc: &CborDoc, i: Int) -> Int {
  if cbor_kind(doc, i) != cbor_kind_bytes() {
    return -1;
  }
  let v: Int = doc.value[i];
  return v;
}

/// Copy of a byte-string token's payload bytes, or an empty vector when `i`
/// is not a bytes token or is out of range (a valid empty byte string is
/// therefore indistinguishable from a non-string here; check the kind
/// first).
/// Complexity: O(payload length).
pub fn cbor_bytes(doc: &CborDoc, i: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  if cbor_kind(doc, i) != cbor_kind_bytes() {
    return out;
  }
  let from: Int = doc.payload_start[i];
  let to: Int = doc.payload_end[i];
  var k = from;
  while k < to {
    out.push(doc.data[k]);
    k = k + 1;
  }
  return out;
}

/// Byte length of a text-string token's payload, or -1 when `i` is not a
/// text token or is out of range.
/// Complexity: O(1).
pub fn cbor_text_len(doc: &CborDoc, i: Int) -> Int {
  if cbor_kind(doc, i) != cbor_kind_text() {
    return -1;
  }
  let v: Int = doc.value[i];
  return v;
}

/// Copy of a text-string token's payload bytes (verbatim, no UTF-8
/// validation or decoding), or an empty vector when `i` is not a text token
/// or is out of range (a valid empty text string is therefore
/// indistinguishable from a non-string here; check the kind first).
/// Complexity: O(payload length).
pub fn cbor_text_bytes(doc: &CborDoc, i: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  if cbor_kind(doc, i) != cbor_kind_text() {
    return out;
  }
  let from: Int = doc.payload_start[i];
  let to: Int = doc.payload_end[i];
  var k = from;
  while k < to {
    out.push(doc.data[k]);
    k = k + 1;
  }
  return out;
}

/// Copy of the exact source bytes of token `i` (header plus payload), or an
/// empty vector when `i` is out of range.
/// Complexity: O(token length).
pub fn cbor_token_bytes(doc: &CborDoc, i: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  if i < 0 || i >= doc.kind.len() {
    return out;
  }
  let from: Int = doc.start[i];
  let to: Int = doc.end[i];
  var k = from;
  while k < to {
    out.push(doc.data[k]);
    k = k + 1;
  }
  return out;
}

// --------------------------------------------------
//  Encoders
// --------------------------------------------------

/// Encode an Int with the canonical CBOR representation: major type 0 for
/// `n >= 0`, major type 1 (argument -1 - n) for `n < 0`, each in the
/// shortest form. Exact for the full signed 64-bit range, including
/// `INT64_MIN` (which needs the 8-byte argument INT64_MAX).
/// Complexity: O(1).
pub fn cbor_encode_int(n: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  if n >= 0 {
    _push_head(&mut out, 0, n);
  } else {
    _push_head(&mut out, 1, -1 - n);
  }
  return out;
}

/// Encode a Bool as a major type 7 simple value: 0xf4 false / 0xf5 true.
/// Complexity: O(1).
pub fn cbor_encode_bool(b: Bool) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  if b {
    out.push(0xF5 as UInt8);
  } else {
    out.push(0xF4 as UInt8);
  }
  return out;
}

/// Encode null as the major type 7 simple value 22 (0xf6).
/// Complexity: O(1).
pub fn cbor_encode_null() -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  out.push(0xF6 as UInt8);
  return out;
}

/// Encode undefined as the major type 7 simple value 23 (0xf7).
/// Complexity: O(1).
pub fn cbor_encode_undefined() -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  out.push(0xF7 as UInt8);
  return out;
}

/// Encode raw bytes as a major type 2 definite-length byte string: shortest
/// header for `bytes.len()`, then the bytes verbatim.
/// Complexity: O(payload length).
pub fn cbor_encode_bytes(bytes: &Vec[UInt8]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  _push_head(&mut out, 2, bytes.len());
  var i = 0;
  while i < bytes.len() {
    out.push(bytes[i]);
    i = i + 1;
  }
  return out;
}

/// Encode a `Str` as a major type 3 definite-length text string: the header
/// length is the UTF-8 byte length (`string.str_len`) and the bytes are
/// copied verbatim. No UTF-8 validation is performed (a `Str` is already
/// valid UTF-8 by construction).
/// Complexity: O(byte length).
pub fn cbor_encode_text(s: Str) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  _push_head(&mut out, 3, string.str_len(s));
  builder.sb_push_str(&mut out, s);
  return out;
}

/// Encode raw bytes as a major type 3 definite-length text string, without
/// validating that they are UTF-8 (the caller asserts text semantics).
/// Complexity: O(payload length).
pub fn cbor_encode_text_bytes(bytes: &Vec[UInt8]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  _push_head(&mut out, 3, bytes.len());
  var i = 0;
  while i < bytes.len() {
    out.push(bytes[i]);
    i = i + 1;
  }
  return out;
}

/// Encode a major type 4 definite-length array from already-encoded element
/// chunks, in order: shortest header for `parts.len()`, then each chunk.
/// Chunks are already-encoded CBOR values; no validation is performed (the
/// caller composes the value).
/// Complexity: O(total element bytes).
pub fn cbor_encode_array(parts: &Vec[Vec[UInt8]]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  _push_head(&mut out, 4, parts.len());
  var i = 0;
  while i < parts.len() {
    let part: Vec[UInt8] = parts[i];
    _push_vec(&mut out, &part);
    i = i + 1;
  }
  return out;
}

/// Encode a major type 5 definite-length map from parallel already-encoded
/// key chunks and already-encoded value chunks.
///
/// Pairs are emitted sorted by the unsigned bytewise lexicographic order of
/// their encoded key chunks (RFC 8949 core deterministic encoding), so the
/// output re-decodes to the same pair order. Chunks are already-encoded CBOR
/// values; no validation is performed beyond key ordering and duplicates.
///
/// Err("cbor: map keys/values length mismatch") when the two vectors differ
/// in length; Err("cbor: duplicate map key") when two encoded keys are
/// byte-identical (strictly ascending output is impossible).
/// Complexity: O(pairs^2 * key length) comparisons.
pub fn cbor_encode_map(keys: &Vec[Vec[UInt8]], values: &Vec[Vec[UInt8]]) -> Result[Vec[UInt8], Str] {
  let n = keys.len();
  if n != values.len() {
    return _err_bytes("cbor: map keys/values length mismatch");
  }
  var order = Vec[Int].new();
  var i = 0;
  while i < n {
    order.push(i);
    i = i + 1;
  }
  // Selection sort: order[0..n) becomes a permutation sorted by encoded
  // key bytes.
  i = 0;
  while i < n {
    var best = i;
    var j = i + 1;
    while j < n {
      let oj: Int = order[j];
      let ob: Int = order[best];
      let kj: Vec[UInt8] = keys[oj];
      let kb: Vec[UInt8] = keys[ob];
      if _cmp_bytes(&kj, &kb) < 0 {
        best = j;
      }
      j = j + 1;
    }
    if best != i {
      let tmp: Int = order[i];
      let moved: Int = order[best];
      order[i] = moved;
      order[best] = tmp;
    }
    i = i + 1;
  }
  // Reject duplicates: adjacent equality after sorting.
  i = 1;
  while i < n {
    let pa: Int = order[i - 1];
    let pb: Int = order[i];
    let ka: Vec[UInt8] = keys[pa];
    let kb2: Vec[UInt8] = keys[pb];
    if _cmp_bytes(&ka, &kb2) == 0 {
      return _err_bytes("cbor: duplicate map key");
    }
    i = i + 1;
  }
  var out = Vec[UInt8].new();
  _push_head(&mut out, 5, n);
  i = 0;
  while i < n {
    let oi: Int = order[i];
    let key: Vec[UInt8] = keys[oi];
    _push_vec(&mut out, &key);
    let val: Vec[UInt8] = values[oi];
    _push_vec(&mut out, &val);
    i = i + 1;
  }
  return _ok_bytes(out);
}

// --------------------------------------------------
//  Reserialization
// --------------------------------------------------

// Append a string token's payload bytes to `out`.
fn _push_payload(doc: &CborDoc, i: Int, out: &mut Vec[UInt8]) {
  let from: Int = doc.payload_start[i];
  let to: Int = doc.payload_end[i];
  var j = from;
  while j < to {
    out.push(doc.data[j]);
    j = j + 1;
  }
}

// Append token `i` (and its subtree) to `out` in the accepted encoded form:
// shortest-form headers, payload bytes verbatim, map pairs in decoded order.
// Decoding is strict, so for documents produced by cbor_decode the rebuilt
// bytes equal the original input.
fn _reser_token(doc: &CborDoc, i: Int, out: &mut Vec[UInt8]) {
  let k: Int = doc.kind[i];
  if k == cbor_kind_uint() {
    let v: Int = doc.value[i];
    _push_head(out, 0, v);
    return;
  }
  if k == cbor_kind_negint() {
    let v: Int = doc.value[i];
    _push_head(out, 1, -1 - v);
    return;
  }
  if k == cbor_kind_bytes() {
    let n: Int = doc.value[i];
    _push_head(out, 2, n);
    _push_payload(doc, i, out);
    return;
  }
  if k == cbor_kind_text() {
    let n: Int = doc.value[i];
    _push_head(out, 3, n);
    _push_payload(doc, i, out);
    return;
  }
  if k == cbor_kind_bool() {
    let v: Int = doc.value[i];
    if v == 0 {
      out.push(0xF4 as UInt8);
    } else {
      out.push(0xF5 as UInt8);
    }
    return;
  }
  if k == cbor_kind_null() {
    out.push(0xF6 as UInt8);
    return;
  }
  if k == cbor_kind_undefined() {
    out.push(0xF7 as UInt8);
    return;
  }
  if k == cbor_kind_array() {
    let n: Int = doc.child_count[i];
    _push_head(out, 4, n);
  } else {
    let npairs: Int = doc.child_count[i] / 2;
    _push_head(out, 5, npairs);
  }
  let first: Int = doc.first_child[i];
  let count: Int = doc.child_count[i];
  var t = first;
  var j = 0;
  while j < count {
    _reser_token(doc, t, out);
    t = cbor_next_sibling(doc, t);
    j = j + 1;
  }
}

/// Re-encode a decoded document to CBOR bytes by walking the token stream
/// (it does not copy `data`, so it is a real reconstruction check). Headers
/// are re-emitted in shortest form and byte/text payloads are copied
/// verbatim; because `cbor_decode` rejects every argument that could have
/// used a smaller encoding, the result equals the original input for any
/// document it produced, including map pair order. An empty document yields
/// an empty vector.
/// Complexity: O(input bytes).
pub fn cbor_reserialize(doc: &CborDoc) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  if doc.kind.len() == 0 {
    return out;
  }
  _reser_token(doc, 0, &mut out);
  return out;
}
