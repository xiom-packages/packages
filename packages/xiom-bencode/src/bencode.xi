// XIOM -- xiom.bencode: pure-XIOM bencode encoding and decoding
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Bencode is the BitTorrent data serialization format: integers `i<n>e`,
// byte strings `<len>:<bytes>`, lists `l...e` and dictionaries `d...e`.
// This module implements a strict, documented subset in pure XIOM:
//
//   * `bencode_decode` validates every structural rule it implements and
//     returns deterministic Err(Str) messages (truncated input, bad
//     delimiters, bad length digits, integer overflow, dict key order,
//     duplicate keys, trailing data, nesting depth);
//   * the token stream is stored flat -- parallel Vec fields, no
//     Vec[StructType] -- in depth-first pre-order: every subtree occupies a
//     contiguous token range, a container owns its direct children through
//     `first_child` + `child_count`, and direct children are linked by
//     `next_sibling` (needed because subtrees interleave the pre-order
//     sequence); every token is O(1)-indexable and O(1)-parented;
//   * `bencode_encode_*` emits canonical bytes: the decimal integer form,
//     and dictionary keys sorted byte-wise ascending;
//   * `bencode_reserialize` rebuilds the exact canonical bytes of a decoded
//     document from the token stream alone.
//
// Non-goals: no .torrent metadata semantics, no UTF-8 validation or
// decoding (byte strings are opaque), no streaming/incremental decoding.
// Integers must fit the signed 64-bit platform Int; larger values are an
// overflow error, not an arbitrary-precision fallback.
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
//     expected (that yields an empty vector); reads go through helpers that
//     take the owning struct reference, or through locals bound first.
//   * integer parsing never negates an Int (INT64_MIN cannot be negated), so
//     the magnitude is accumulated positively with an explicit overflow
//     check and INT64_MIN is recognized structurally.

module xiom.bencode

use xiom.string;
use xiom.string.builder;
use xiom.convert;

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

// Ok(v) for Result[BencodeDoc, Str].
fn _ok_doc(v: BencodeDoc) -> Result[BencodeDoc, Str] {
  return Ok(v);
}

// Err(m) for Result[BencodeDoc, Str].
fn _err_doc(m: Str) -> Result[BencodeDoc, Str] {
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

/// Parsed bencode document: the source bytes plus a flat token stream.
///
/// Tokens are stored in depth-first pre-order in parallel vectors (one entry
/// per token); token 0 is the root value. `kind` holds one of the
/// `bencode_kind_*` codes. For containers, `first_child[i]` is the first
/// direct child and `child_count[i]` the number of direct children; each
/// direct child links to the next one through `next_sibling` (-1 on the last
/// child), because a child's own subtree occupies the tokens immediately
/// after it. For leaves, `first_child` is -1, `next_sibling` is -1 and
/// `child_count` is 0. `start`/`end` delimit the whole token,
/// `payload_start`/`payload_end` delimit the integer digit text (between `i`
/// and `e`) or the string payload bytes (after `:`), and `value` holds the
/// parsed integer or the string byte length.
///
/// Fields are implementation details; callers should use the free accessors
/// below. Documents are only produced by `bencode_decode`, so the token
/// stream always satisfies the format invariants (including dict key order).
pub type BencodeDoc = {
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
// fields mirror BencodeDoc; _finish copies them into the public type.
type _Parser = {
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

/// Token kind code for an integer (`i<n>e`).
pub fn bencode_kind_int() -> Int {
  return 0;
}

/// Token kind code for a byte string (`<len>:<bytes>`).
pub fn bencode_kind_str() -> Int {
  return 1;
}

/// Token kind code for a list (`l...e`).
pub fn bencode_kind_list() -> Int {
  return 2;
}

/// Token kind code for a dictionary (`d...e`).
pub fn bencode_kind_dict() -> Int {
  return 3;
}

/// Documented maximum container nesting depth accepted by the decoder.
///
/// The top-level value has depth 0, so a container at depth 63 is the
/// deepest accepted one; a container at depth 64 is rejected with
/// `Err("bencode: nesting depth exceeds limit of 64")`.
pub fn bencode_max_depth() -> Int {
  return 64;
}

// --------------------------------------------------
//  Byte and text helpers
// --------------------------------------------------

// True for an ASCII decimal digit byte (0..255 domain).
fn _is_digit(c: Int) -> Bool {
  return c >= 48 && c <= 57;
}

// Two lowercase hex digits for a byte value (0..255).
fn _hex2(b: Int) -> Str {
  let digits = "0123456789abcdef";
  let hi = b / 16;
  let lo = b % 16;
  return string.str_slice(digits, hi, hi + 1) + string.str_slice(digits, lo, lo + 1);
}

// "bencode: bad type byte 0xNN" for a rejected first byte.
fn _bad_type_msg(b: Int) -> Str {
  return "bencode: bad type byte 0x" + _hex2(b);
}

// The documented nesting-depth error.
fn _depth_msg() -> Str {
  return "bencode: nesting depth exceeds limit of 64";
}

// Byte at `pos` of the parser buffer widened to an Int (0..255).
fn _pbyte(p: &_Parser, pos: Int) -> Int {
  return (p.data[pos] as Int) & 0xFF;
}

// Same as _pbyte but takes &mut, so parser bodies never mix a `&` call
// before a `&mut` access on the same local (advisory E001).
fn _pbyte_mut(p: &mut _Parser, pos: Int) -> Int {
  return _pbyte(p, pos);
}

// Byte at `pos` of a document buffer widened to an Int (0..255). Callers
// guarantee the bounds.
fn _dbyte(d: &BencodeDoc, pos: Int) -> Int {
  return (d.data[pos] as Int) & 0xFF;
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

// Unsigned byte-wise comparison of two string-token payloads in the parser.
fn _cmp_tokens(p: &_Parser, a: Int, b: Int) -> Int {
  let sa: Int = p.payload_start[a];
  let ea: Int = p.payload_end[a];
  let sb: Int = p.payload_start[b];
  let eb: Int = p.payload_end[b];
  let la = ea - sa;
  let lb = eb - sb;
  var m = la;
  if lb < m { m = lb; }
  var i = 0;
  while i < m {
    let xa = _pbyte(p, sa + i);
    let xb = _pbyte(p, sb + i);
    if xa < xb { return -1; }
    if xa > xb { return 1; }
    i = i + 1;
  }
  if la < lb { return -1; }
  if la > lb { return 1; }
  return 0;
}

// Same as _cmp_tokens but takes &mut (E001 advisory avoidance in _parse_dict).
fn _cmp_tokens_mut(p: &mut _Parser, a: Int, b: Int) -> Int {
  return _cmp_tokens(p, a, b);
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
fn _push_token(p: &mut _Parser, kind: Int, parent: Int, start: Int) -> Int {
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
fn _finish(p: _Parser) -> BencodeDoc {
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
  return BencodeDoc{
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
//  Decoder
// --------------------------------------------------

// Parse an integer token: `i`, optional `-`, digits, `e`.
//
// Rejects an empty digit run, a non-digit inside the run, a leading zero,
// `-0`, an integer not terminated by `e`, and any magnitude that does not
// fit the signed 64-bit Int range (including exactly INT64_MIN, which is
// accepted). `parent` is the index of the enclosing token (-1 at the root).
fn _parse_int(p: &mut _Parser, parent: Int) -> Result[Int, Str] {
  let start = p.pos;
  let idx = _push_token(p, bencode_kind_int(), parent, start);
  p.pos = p.pos + 1;
  let total = p.data.len();
  if p.pos >= total {
    return _err_int("bencode: truncated input");
  }
  var is_neg = false;
  let sign_byte = _pbyte_mut(p, p.pos);
  if sign_byte == 45 {
    is_neg = true;
    p.pos = p.pos + 1;
    if p.pos >= total {
      return _err_int("bencode: truncated input");
    }
  }
  let lead = _pbyte_mut(p, p.pos);
  if lead == 48 {
    if is_neg {
      return _err_int("bencode: negative zero in integer");
    }
    p.pos = p.pos + 1;
    if p.pos >= total {
      return _err_int("bencode: truncated input");
    }
    let after = _pbyte_mut(p, p.pos);
    if _is_digit(after) {
      return _err_int("bencode: bad integer digits");
    }
    if after != 101 {
      return _err_int("bencode: bad delimiter");
    }
    p.pos = p.pos + 1;
    p.end[idx] = p.pos;
    p.payload_start[idx] = start + 1;
    p.payload_end[idx] = p.pos - 1;
    p.value[idx] = 0;
    return _ok_int(idx);
  }
  var mag: Int = 0;
  var digits: Int = 0;
  var min_mag = false;
  while p.pos < total {
    let c = _pbyte_mut(p, p.pos);
    if !_is_digit(c) {
      break;
    }
    let d = c - 48;
    if min_mag {
      return _err_int("bencode: integer overflow");
    }
    if is_neg && mag == 922337203685477580 && d == 8 {
      min_mag = true;
    } else {
      if mag > (9223372036854775807 - d) / 10 {
        return _err_int("bencode: integer overflow");
      }
      mag = mag * 10 + d;
    }
    digits = digits + 1;
    p.pos = p.pos + 1;
  }
  if digits == 0 {
    return _err_int("bencode: bad integer digits");
  }
  if p.pos >= total {
    return _err_int("bencode: truncated input");
  }
  let term = _pbyte_mut(p, p.pos);
  if term != 101 {
    return _err_int("bencode: bad delimiter");
  }
  p.pos = p.pos + 1;
  var value: Int = mag;
  if min_mag {
    value = 0 - 9223372036854775807 - 1;
  } else {
    if is_neg {
      value = 0 - mag;
    }
  }
  p.end[idx] = p.pos;
  p.payload_start[idx] = start + 1;
  p.payload_end[idx] = p.pos - 1;
  p.value[idx] = value;
  return _ok_int(idx);
}

// Parse a byte string token: decimal length digits, `:`, then that many
// payload bytes. The first byte at the cursor must already be a digit.
//
// Rejects a leading zero in the length, a length that overflows Int, a
// missing `:`, and a payload that runs past the end of the buffer.
fn _parse_str(p: &mut _Parser, parent: Int) -> Result[Int, Str] {
  let start = p.pos;
  let idx = _push_token(p, bencode_kind_str(), parent, start);
  let total = p.data.len();
  var len: Int = 0;
  var digits: Int = 0;
  var first_zero = false;
  var overflow = false;
  while p.pos < total {
    let c = _pbyte_mut(p, p.pos);
    if !_is_digit(c) {
      break;
    }
    let d = c - 48;
    if digits == 0 && d == 0 {
      first_zero = true;
    }
    if len > (9223372036854775807 - d) / 10 {
      overflow = true;
    } else {
      len = len * 10 + d;
    }
    digits = digits + 1;
    p.pos = p.pos + 1;
  }
  if digits == 0 {
    return _err_int("bencode: bad length digits");
  }
  if first_zero && digits > 1 {
    return _err_int("bencode: bad length digits");
  }
  if overflow {
    return _err_int("bencode: string length overflow");
  }
  if p.pos >= total {
    return _err_int("bencode: truncated input");
  }
  let colon = _pbyte_mut(p, p.pos);
  if colon != 58 {
    return _err_int("bencode: bad delimiter");
  }
  p.pos = p.pos + 1;
  let remaining = total - p.pos;
  if len > remaining {
    return _err_int("bencode: truncated input");
  }
  p.end[idx] = p.pos + len;
  p.payload_start[idx] = p.pos;
  p.payload_end[idx] = p.pos + len;
  p.value[idx] = len;
  p.pos = p.pos + len;
  return _ok_int(idx);
}

// Parse a list token: `l`, then values until `e`.
fn _parse_list(p: &mut _Parser, depth: Int, parent: Int) -> Result[Int, Str] {
  if depth >= bencode_max_depth() {
    return _err_int(_depth_msg());
  }
  let start = p.pos;
  let idx = _push_token(p, bencode_kind_list(), parent, start);
  p.pos = p.pos + 1;
  var count: Int = 0;
  var first: Int = -1;
  var prev: Int = -1;
  var closed = false;
  while !closed {
    if p.pos >= p.data.len() {
      return _err_int("bencode: truncated input");
    }
    let b = _pbyte_mut(p, p.pos);
    if b == 101 {
      closed = true;
    } else {
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
      count = count + 1;
    }
  }
  p.pos = p.pos + 1;
  p.end[idx] = p.pos;
  p.first_child[idx] = first;
  p.child_count[idx] = count;
  return _ok_int(idx);
}

// Parse a dictionary token: `d`, then strictly ascending key/value pairs
// until `e`. Keys must be byte strings; each key is compared byte-wise with
// its predecessor (equal -> duplicate, descending -> order violation).
fn _parse_dict(p: &mut _Parser, depth: Int, parent: Int) -> Result[Int, Str] {
  if depth >= bencode_max_depth() {
    return _err_int(_depth_msg());
  }
  let start = p.pos;
  let idx = _push_token(p, bencode_kind_dict(), parent, start);
  p.pos = p.pos + 1;
  var pairs: Int = 0;
  var first: Int = -1;
  var prev: Int = -1;
  var prev_key: Int = -1;
  var closed = false;
  while !closed {
    if p.pos >= p.data.len() {
      return _err_int("bencode: truncated input");
    }
    let b = _pbyte_mut(p, p.pos);
    if b == 101 {
      closed = true;
    } else {
      if !_is_digit(b) {
        return _err_int("bencode: dict key must be a byte string");
      }
      let key = _parse_str(p, idx);
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
      if prev_key >= 0 {
        let cmp = _cmp_tokens_mut(p, prev_key, key.value);
        if cmp == 0 {
          return _err_int("bencode: duplicate dict key");
        }
        if cmp > 0 {
          return _err_int("bencode: dict key order violation");
        }
      }
      let value = _parse_value(p, depth + 1, idx);
      if !value.is_ok {
        return _err_int(value.error);
      }
      p.next_sibling[prev] = value.value;
      prev = value.value;
      prev_key = key.value;
      pairs = pairs + 1;
    }
  }
  p.pos = p.pos + 1;
  p.end[idx] = p.pos;
  p.first_child[idx] = first;
  p.child_count[idx] = pairs * 2;
  return _ok_int(idx);
}

// Parse one value at the cursor and return its token index. `depth` is the
// number of enclosing containers (the root value is depth 0); `parent` is
// the enclosing token index, or -1 at the root.
fn _parse_value(p: &mut _Parser, depth: Int, parent: Int) -> Result[Int, Str] {
  if p.pos >= p.data.len() {
    return _err_int("bencode: truncated input");
  }
  let b = _pbyte_mut(p, p.pos);
  if b == 105 {
    return _parse_int(p, parent);
  }
  if b == 108 {
    return _parse_list(p, depth, parent);
  }
  if b == 100 {
    return _parse_dict(p, depth, parent);
  }
  if _is_digit(b) {
    return _parse_str(p, parent);
  }
  return _err_int(_bad_type_msg(b));
}

/// Decode one complete bencode value from `data`.
///
/// The result is a `BencodeDoc` holding the input bytes and the flat token
/// stream; use the `bencode_*` accessors to inspect it. `data` must contain
/// exactly one value: bytes after the top-level value are rejected.
///
/// Err("bencode: truncated input") when the buffer ends inside a value,
/// header or payload; Err("bencode: bad type byte 0xNN") when a value starts
/// with a byte that is not `i`, `l`, `d` or a length digit;
/// Err("bencode: bad integer digits") / Err("bencode: negative zero in
/// integer") / Err("bencode: integer overflow") / Err("bencode: bad
/// delimiter") for malformed integers; Err("bencode: bad length digits") /
/// Err("bencode: string length overflow") / Err("bencode: bad delimiter")
/// for malformed string lengths; Err("bencode: dict key must be a byte
/// string") / Err("bencode: duplicate dict key") / Err("bencode: dict key
/// order violation") for malformed dictionaries; Err("bencode: nesting depth
/// exceeds limit of 64") when a container is nested deeper than
/// `bencode_max_depth()`; Err("bencode: trailing data after top-level
/// value") when bytes remain after the root value.
/// Complexity: O(data.len()).
pub fn bencode_decode(data: Vec[UInt8]) -> Result[BencodeDoc, Str] {
  var p = _Parser{
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
    return _err_doc("bencode: trailing data after top-level value");
  }
  return _ok_doc(_finish(p));
}

// --------------------------------------------------
//  Token accessors
// --------------------------------------------------

/// Number of tokens in the document (1 for a scalar root value, and one
/// token per list/dict element).
/// Complexity: O(1).
pub fn bencode_token_count(doc: &BencodeDoc) -> Int {
  return doc.kind.len();
}

/// Index of the root token: always 0 for a document produced by
/// `bencode_decode` (kept as a named accessor for symmetry).
/// Complexity: O(1).
pub fn bencode_root(doc: &BencodeDoc) -> Int {
  if doc.kind.len() == 0 {
    return -1;
  }
  return 0;
}

/// Kind code of token `i` (one of the `bencode_kind_*` values), or -1 when
/// `i` is outside [0, bencode_token_count(doc)).
/// Complexity: O(1).
pub fn bencode_kind(doc: &BencodeDoc, i: Int) -> Int {
  if i < 0 || i >= doc.kind.len() {
    return -1;
  }
  let k: Int = doc.kind[i];
  return k;
}

/// Index of the token that contains token `i`, or -1 for the root token and
/// for an out-of-range `i`.
/// Complexity: O(1).
pub fn bencode_parent(doc: &BencodeDoc, i: Int) -> Int {
  if i < 0 || i >= doc.parent.len() {
    return -1;
  }
  let v: Int = doc.parent[i];
  return v;
}

/// Index of the first direct child of token `i`, or -1 for a leaf token and
/// for an out-of-range `i`.
/// Complexity: O(1).
pub fn bencode_first_child(doc: &BencodeDoc, i: Int) -> Int {
  if i < 0 || i >= doc.first_child.len() {
    return -1;
  }
  let v: Int = doc.first_child[i];
  return v;
}

/// Number of direct children of token `i` (list elements, or twice the pair
/// count for a dictionary), or 0 for a leaf token and for an out-of-range
/// `i`.
/// Complexity: O(1).
pub fn bencode_child_count(doc: &BencodeDoc, i: Int) -> Int {
  if i < 0 || i >= doc.child_count.len() {
    return 0;
  }
  let v: Int = doc.child_count[i];
  return v;
}

/// Byte offset of the first byte of token `i`, or -1 when `i` is outside
/// [0, bencode_token_count(doc)).
/// Complexity: O(1).
pub fn bencode_token_start(doc: &BencodeDoc, i: Int) -> Int {
  if i < 0 || i >= doc.start.len() {
    return -1;
  }
  let v: Int = doc.start[i];
  return v;
}

/// Byte offset one past the last byte of token `i`, or -1 when `i` is
/// outside [0, bencode_token_count(doc)).
/// Complexity: O(1).
pub fn bencode_token_end(doc: &BencodeDoc, i: Int) -> Int {
  if i < 0 || i >= doc.end.len() {
    return -1;
  }
  let v: Int = doc.end[i];
  return v;
}

/// Index of the n-th direct child of token `i` (0-based), or -1 when `i` is
/// not a container or `n` is outside [0, bencode_child_count(doc, i)).
/// Dictionary children alternate key, value: pair k is child 2*k (key) and
/// child 2*k + 1 (value).
/// Complexity: O(n).
pub fn bencode_child(doc: &BencodeDoc, i: Int, n: Int) -> Int {
  let count = bencode_child_count(doc, i);
  if n < 0 || n >= count {
    return -1;
  }
  var t = bencode_first_child(doc, i);
  var k = 0;
  while k < n {
    t = bencode_next_sibling(doc, t);
    k = k + 1;
  }
  return t;
}

/// Index of the next direct sibling of token `i` under the same parent, or
/// -1 when `i` is the last direct child (and for out-of-range `i`).
/// Pre-order token indices are not siblings just because they are adjacent:
/// a token's subtree sits between it and its next sibling, so callers must
/// use this accessor (or `bencode_child`) to iterate a container's children.
/// Complexity: O(1).
pub fn bencode_next_sibling(doc: &BencodeDoc, i: Int) -> Int {
  if i < 0 || i >= doc.next_sibling.len() {
    return -1;
  }
  let v: Int = doc.next_sibling[i];
  return v;
}

/// Parsed integer value of an int token, or 0 when `i` is not an int token
/// (check the kind first) or is out of range.
/// Complexity: O(1).
pub fn bencode_int_value(doc: &BencodeDoc, i: Int) -> Int {
  if bencode_kind(doc, i) != bencode_kind_int() {
    return 0;
  }
  let v: Int = doc.value[i];
  return v;
}

/// Byte length of a byte-string token's payload, or -1 when `i` is not a
/// str token or is out of range.
/// Complexity: O(1).
pub fn bencode_str_len(doc: &BencodeDoc, i: Int) -> Int {
  if bencode_kind(doc, i) != bencode_kind_str() {
    return -1;
  }
  let v: Int = doc.value[i];
  return v;
}

/// Copy of a byte-string token's payload bytes, or an empty vector when `i`
/// is not a str token or is out of range (a valid empty string is therefore
/// indistinguishable from a non-string here; check the kind first).
/// Complexity: O(payload length).
pub fn bencode_str_bytes(doc: &BencodeDoc, i: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  if bencode_kind(doc, i) != bencode_kind_str() {
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
pub fn bencode_token_bytes(doc: &BencodeDoc, i: Int) -> Vec[UInt8] {
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

// Unsigned byte-wise comparison of a dict key token's payload against a raw
// key: -1 when token < key, 0 when equal, 1 when token > key.
fn _cmp_doc_key(doc: &BencodeDoc, key_tok: Int, key: &Vec[UInt8]) -> Int {
  let from: Int = doc.payload_start[key_tok];
  let to: Int = doc.payload_end[key_tok];
  let tlen = to - from;
  let klen = key.len();
  var m = tlen;
  if klen < m { m = klen; }
  var i = 0;
  while i < m {
    let a = _dbyte(doc, from + i);
    let kb: UInt8 = key[i];
    let b = (kb as Int) & 0xFF;
    if a < b { return -1; }
    if a > b { return 1; }
    i = i + 1;
  }
  if tlen < klen { return -1; }
  if tlen > klen { return 1; }
  return 0;
}

/// Index of the value token stored under `key` (raw bytes) in the dictionary
/// token `i`, or -1 when `i` is not a dict token, when `key` is absent, or
/// when `i` is out of range.
///
/// Keys are strictly ascending, so this is a binary search with unsigned
/// byte-wise comparison.
/// Complexity: O(log pairs * key length).
pub fn bencode_dict_get(doc: &BencodeDoc, i: Int, key: &Vec[UInt8]) -> Int {
  if bencode_kind(doc, i) != bencode_kind_dict() {
    return -1;
  }
  let first = bencode_first_child(doc, i);
  let pairs = bencode_child_count(doc, i) / 2;
  var lo = 0;
  var hi = pairs - 1;
  while lo <= hi {
    let mid = lo + (hi - lo) / 2;
    var key_tok = first;
    var step = 0;
    while step < mid * 2 {
      key_tok = bencode_next_sibling(doc, key_tok);
      step = step + 1;
    }
    let cmp = _cmp_doc_key(doc, key_tok, key);
    if cmp == 0 {
      return bencode_next_sibling(doc, key_tok);
    }
    if cmp < 0 {
      lo = mid + 1;
    } else {
      hi = mid - 1;
    }
  }
  return -1;
}

// --------------------------------------------------
//  Encoders
// --------------------------------------------------

/// Encode an integer as `i<n>e`, decimal and exact for the full signed
/// 64-bit Int range (including INT64_MIN).
/// Complexity: O(log |n|).
pub fn bencode_encode_int(n: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  out.push(105 as UInt8);
  let text = convert.int_to_string(n);
  builder.sb_push_str(&mut out, text);
  out.push(101 as UInt8);
  return out;
}

/// Encode raw bytes as `<len>:<bytes>` (UTF-8 agnostic; bytes are copied
/// verbatim).
/// Complexity: O(payload length).
pub fn bencode_encode_bytes(bytes: &Vec[UInt8]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  let n = bytes.len();
  let text = convert.int_to_string(n);
  builder.sb_push_str(&mut out, text);
  out.push(58 as UInt8);
  var i = 0;
  while i < n {
    out.push(bytes[i]);
    i = i + 1;
  }
  return out;
}

/// Encode a `Str` as a bencode byte string: the length is the UTF-8 byte
/// length and the bytes are copied verbatim (no character re-encoding).
/// Complexity: O(byte length).
pub fn bencode_encode_str(s: Str) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  let n = string.str_len(s);
  let text = convert.int_to_string(n);
  builder.sb_push_str(&mut out, text);
  out.push(58 as UInt8);
  builder.sb_push_str(&mut out, s);
  return out;
}

/// Encode a list from already-encoded element chunks, in order:
/// `l` + chunks + `e`.
/// Complexity: O(total element bytes).
pub fn bencode_encode_list(parts: &Vec[Vec[UInt8]]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  out.push(108 as UInt8);
  var i = 0;
  while i < parts.len() {
    let part: Vec[UInt8] = parts[i];
    _push_vec(&mut out, &part);
    i = i + 1;
  }
  out.push(101 as UInt8);
  return out;
}

/// Encode a dictionary from parallel raw key bytes and already-encoded value
/// chunks: `d` + sorted (key, value) pairs + `e`.
///
/// Keys are sorted byte-wise ascending and emitted as bencode byte strings,
/// so the output is canonical and re-decodes with the same order.
/// Err("bencode: dict keys/values length mismatch") when the two vectors
/// differ in length; Err("bencode: duplicate dict key") when two keys are
/// equal (strictly ascending output is impossible).
/// Complexity: O(pairs^2 * key length) comparisons.
pub fn bencode_encode_dict(keys: &Vec[Vec[UInt8]], values: &Vec[Vec[UInt8]]) -> Result[Vec[UInt8], Str] {
  let n = keys.len();
  if n != values.len() {
    return _err_bytes("bencode: dict keys/values length mismatch");
  }
  var order = Vec[Int].new();
  var i = 0;
  while i < n {
    order.push(i);
    i = i + 1;
  }
  // Selection sort: order[0..n) becomes a permutation sorted by key bytes.
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
      return _err_bytes("bencode: duplicate dict key");
    }
    i = i + 1;
  }
  var out = Vec[UInt8].new();
  out.push(100 as UInt8);
  i = 0;
  while i < n {
    let oi: Int = order[i];
    let key: Vec[UInt8] = keys[oi];
    let enc_key: Vec[UInt8] = bencode_encode_bytes(&key);
    _push_vec(&mut out, &enc_key);
    let val: Vec[UInt8] = values[oi];
    _push_vec(&mut out, &val);
    i = i + 1;
  }
  out.push(101 as UInt8);
  return _ok_bytes(out);
}

// --------------------------------------------------
//  Reserialization
// --------------------------------------------------

// Append token `i` (and its subtree) to `out` in canonical form. Decoding is
// strict, so the rebuilt bytes equal the original input.
fn _reser_token(doc: &BencodeDoc, i: Int, out: &mut Vec[UInt8]) {
  let k: Int = doc.kind[i];
  if k == bencode_kind_int() {
    out.push(105 as UInt8);
    let v: Int = doc.value[i];
    let text = convert.int_to_string(v);
    builder.sb_push_str(out, text);
    out.push(101 as UInt8);
  } elif k == bencode_kind_str() {
    let n: Int = doc.value[i];
    let text = convert.int_to_string(n);
    builder.sb_push_str(out, text);
    out.push(58 as UInt8);
    let from: Int = doc.payload_start[i];
    let to: Int = doc.payload_end[i];
    var j = from;
    while j < to {
      out.push(doc.data[j]);
      j = j + 1;
    }
  } else {
    if k == bencode_kind_list() {
      out.push(108 as UInt8);
    } else {
      out.push(100 as UInt8);
    }
    let first: Int = doc.first_child[i];
    let count: Int = doc.child_count[i];
    var t = first;
    var j = 0;
    while j < count {
      _reser_token(doc, t, out);
      t = bencode_next_sibling(doc, t);
      j = j + 1;
    }
    out.push(101 as UInt8);
  }
}

/// Re-encode a decoded document to canonical bencode bytes by walking the
/// token stream (it does not copy `data`, so it is a real reconstruction
/// check). Because `bencode_decode` rejects every non-canonical form, the
/// result equals the original input for any document it produced. An empty
/// document yields an empty vector.
/// Complexity: O(input bytes).
pub fn bencode_reserialize(doc: &BencodeDoc) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  if doc.kind.len() == 0 {
    return out;
  }
  _reser_token(doc, 0, &mut out);
  return out;
}
