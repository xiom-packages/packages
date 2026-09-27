// XIOM -- xiom.ethereum: Ethereum RLP and ABI encoding structures
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure-XIOM Ethereum serialization structures, no cryptography and no
// networking:
//
//   * RLP (Recursive Length Prefix, Ethereum Yellow Paper Appendix B):
//     `rlp_decode` accepts one complete item -- a single byte, a short or
//     long byte string, or a short or long list of items -- and enforces
//     every canonical rule: a single byte below 0x80 must be encoded as
//     itself (0x81 0x00..0x7F is rejected), long-form lengths must be >= 56
//     and their length-of-length must have no leading zero byte (the
//     shortest form is required), payloads may contain 0x00 freely, and
//     trailing bytes after the top-level item are rejected. Decoded items
//     are stored as a flat token stream in parallel Vec fields (no
//     Vec[StructType]): tokens are in depth-first pre-order, every item is
//     O(1)-indexable, a list owns its direct children through `first_child`
//     + `child_count`, and direct children are linked by `next_sibling`.
//     `rlp_encode_*` emits canonical bytes and `rlp_reserialize` rebuilds
//     the exact accepted bytes from the token stream.
//
//   * Transaction field listing for the legacy (pre-typed) transaction
//     shape: `tx_nonce`, `tx_gas_price`, `tx_gas_limit`, `tx_to`, `tx_value`,
//     `tx_data`, `tx_v`, `tx_r`, `tx_s` return the RLP item index of each
//     field (or -1), and `tx_is_unsigned_155` / `tx_chain_id` recognize the
//     EIP-155 signing preimage list [nonce, gasPrice, gasLimit, to, value,
//     data, chainId, 0, 0]. No signature checking, no v interpretation.
//
//   * ABI static words (Solidity ABI): uint<M>/int<M> for M = 8..256 step 8
//     encoded as one 32-byte big-endian word (two's complement for int),
//     bool (0/1 only), address (20 bytes right-aligned), bytes<M> fixed
//     (1..32 bytes left-aligned), bytes32, plus one level of dynamic types:
//     bytes/string (offset word + length word + zero-padded data) and
//     dynamic arrays of 32-byte static words (offset word + length word +
//     elements), with bounds-checked offset resolution. Function-call data
//     is selector (4 caller bytes, no keccak) + head + tail sections.
//
//   * Hex rendering (0x-prefixed, lowercase, two digits per byte) and
//     address validation/normalization to the all-lowercase form. EIP-55
//     mixed-case checksums are deliberately NOT verified: the checksum is
//     keccak256-based, and this package excludes hashing (documented in the
//     `eth_address_normalize` doc comment).
//
// Non-goals: no keccak/SHA hashing, no secp256k1 signing or recovery, no
// EIP-2718 typed-envelope parsing (the field helpers describe the legacy
// 9-item shape only), no JSON-RPC, no state, no floating point, no nested
// dynamic ABI types (arrays of bytes/strings are out of scope).
//
// Value range: the platform Int is signed 64-bit, so decoded ABI integers
// and RLP lengths must fit it; a 256-bit word with a value outside the
// signed 64-bit range is rejected with an explicit error rather than
// silently truncated.
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
//     expected; bytes are copied through helpers that take the owning
//     struct reference, and Vec[Vec[UInt8]] elements are bound to typed
//     locals before being passed by reference.
//   * big-endian words are extracted with divisor/modulo arithmetic
//     (`_be_byte`), not bit tests: shifting or masking values with the sign
//     bit set is unreliable in v0.61.3. The same helper encodes negative
//     Ints exactly as their two's-complement byte pattern, which is what
//     ABI int<M> needs.
//   * `&mut Int` out-parameters miscompile; every helper returns its value.

module xiom.ethereum

use xiom.string;
use xiom.convert;
use xiom.encoding.hex;

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

// Ok(v) for Result[Bool, Str].
fn _ok_bool(v: Bool) -> Result[Bool, Str] {
  return Ok(v);
}

// Err(m) for Result[Bool, Str].
fn _err_bool(m: Str) -> Result[Bool, Str] {
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

// Ok(v) for Result[Vec[UInt8], Str].
fn _ok_bytes(v: Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  return Ok(v);
}

// Err(m) for Result[Vec[UInt8], Str].
fn _err_bytes(m: Str) -> Result[Vec[UInt8], Str] {
  return Err(m);
}

// Ok(v) for Result[Vec[Int], Str].
fn _ok_ints(v: Vec[Int]) -> Result[Vec[Int], Str] {
  return Ok(v);
}

// Err(m) for Result[Vec[Int], Str].
fn _err_ints(m: Str) -> Result[Vec[Int], Str] {
  return Err(m);
}

// Ok(v) for Result[RlpDoc, Str].
fn _ok_doc(v: RlpDoc) -> Result[RlpDoc, Str] {
  return Ok(v);
}

// Err(m) for Result[RlpDoc, Str].
fn _err_doc(m: Str) -> Result[RlpDoc, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Number and byte helpers
// --------------------------------------------------

// Big-endian byte `shift_bytes` of `v` (0 = least significant byte), using
// division and remainder only. For negative `v` this yields the
// two's-complement byte pattern (all leading 0xFF), which is exactly the ABI
// int<M> encoding. Exact for the whole signed 64-bit range.
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

// Append the low `size` bytes of `v` in big-endian order (v >= 0).
fn _push_be(out: &mut Vec[UInt8], v: Int, size: Int) {
  var i = size - 1;
  while i >= 0 {
    out.push(_be_byte(v, i));
    i = i - 1;
  }
}

// Append one 32-byte ABI word holding `v` as a big-endian two's-complement
// integer (sign-extended to 256 bits).
fn _push_word(out: &mut Vec[UInt8], v: Int) {
  var k = 31;
  while k >= 0 {
    out.push(_be_byte(v, k));
    k = k - 1;
  }
}

// Append every byte of `v` to `out`.
fn _push_all(out: &mut Vec[UInt8], v: &Vec[UInt8]) {
  var i = 0;
  while i < v.len() {
    out.push(v[i]);
    i = i + 1;
  }
}

// 2^m for 0 <= m <= 62 (the caller keeps m in range).
fn _pow2(m: Int) -> Int {
  var v = 1;
  var i = 0;
  while i < m {
    v = v * 2;
    i = i + 1;
  }
  return v;
}

// Zero bytes needed to pad `n` payload bytes up to a 32-byte boundary.
fn _abi_pad_bytes(n: Int) -> Int {
  let r = n % 32;
  if r == 0 {
    return 0;
  }
  return 32 - r;
}

// --------------------------------------------------
//  RLP types and metadata
// --------------------------------------------------

/// Parsed RLP item: the source bytes plus a flat token stream.
///
/// Tokens are in depth-first pre-order in parallel vectors (one entry per
/// token); token 0 is the root item. `kind` holds one of the `rlp_kind_*`
/// codes. For lists, `first_child[i]` is the first direct child and
/// `child_count[i]` the number of direct children; each direct child links to
/// the next one through `next_sibling` (-1 on the last child). For byte
/// strings, `first_child` is -1, `next_sibling` is -1 and `child_count` is 0.
/// `start`/`end` delimit the whole item (header included),
/// `payload_start`/`payload_end` delimit the payload (the bytes after the
/// header for a string, or the children for a list), and `value` holds the
/// payload byte length.
///
/// Fields are implementation details; callers should use the free accessors
/// below. Documents are only produced by `rlp_decode`, so the token stream
/// always satisfies the format invariants (canonical encoding).
pub type RlpDoc = {
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
// fields mirror RlpDoc; _finish copies them into the public type.
type _RlpParser = {
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

/// Token kind code for a byte string (including the single-byte form).
pub fn rlp_kind_bytes() -> Int {
  return 0;
}

/// Token kind code for a list.
pub fn rlp_kind_list() -> Int {
  return 1;
}

/// Documented maximum container nesting depth accepted by the decoder.
///
/// The top-level item has depth 0, so a list at depth 63 is the deepest
/// accepted one; a list at depth 64 is rejected with
/// `Err("rlp: nesting depth exceeds limit of 64")`.
pub fn rlp_max_depth() -> Int {
  return 64;
}

// The documented nesting-depth error.
fn _depth_msg() -> Str {
  return "rlp: nesting depth exceeds limit of 64";
}

// --------------------------------------------------
//  RLP decoder
// --------------------------------------------------

// Byte at `pos` of the parser buffer widened to an Int (0..255).
fn _pbyte(p: &_RlpParser, pos: Int) -> Int {
  return (p.data[pos] as Int) & 0xFF;
}

// Same as _pbyte but takes &mut, so parser bodies never mix a `&` call
// before a `&mut` access on the same local (advisory E001).
fn _pbyte_mut(p: &mut _RlpParser, pos: Int) -> Int {
  return _pbyte(p, pos);
}

// Append a placeholder token and return its index. Placeholders are filled
// in by the caller once the item's extent is known.
fn _push_token(p: &mut _RlpParser, kind: Int, parent: Int, start: Int) -> Int {
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
fn _finish(p: _RlpParser) -> RlpDoc {
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
  return RlpDoc{
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

// Read a long-form length of `k` bytes (1..8) at the cursor, advancing the
// cursor past it. Rejects a truncated length, a leading zero byte (a
// non-minimal length-of-length), and a value that does not fit the signed
// 64-bit Int.
fn _read_long_length(p: &mut _RlpParser, k: Int) -> Result[Int, Str] {
  let total = p.data.len();
  if p.pos + k > total {
    return _err_int("rlp: truncated input");
  }
  let first = _pbyte_mut(p, p.pos);
  if first == 0 {
    return _err_int("rlp: leading zero in length");
  }
  var v: Int = 0;
  var i = 0;
  while i < k {
    let b = _pbyte_mut(p, p.pos + i);
    if v > (9223372036854775807 - b) / 256 {
      return _err_int("rlp: length overflow");
    }
    v = v * 256 + b;
    i = i + 1;
  }
  p.pos = p.pos + k;
  return _ok_int(v);
}

// Parse a single-byte item (0x00..0x7F): the byte is its own payload.
fn _parse_single(p: &mut _RlpParser, parent: Int) -> Result[Int, Str] {
  let start = p.pos;
  let idx = _push_token(p, rlp_kind_bytes(), parent, start);
  p.pos = p.pos + 1;
  p.end[idx] = p.pos;
  p.payload_start[idx] = start;
  p.payload_end[idx] = p.pos;
  p.value[idx] = 1;
  return _ok_int(idx);
}

// Parse a short byte string (0x80..0xB7): `len` payload bytes follow the
// header. Canonical: a 1-byte payload must be >= 0x80 (otherwise the single
// byte form was required).
fn _parse_short_str(p: &mut _RlpParser, parent: Int, len: Int) -> Result[Int, Str] {
  let start = p.pos;
  let remaining = p.data.len() - p.pos - 1;
  if len > remaining {
    return _err_int("rlp: truncated input");
  }
  if len == 1 {
    let single = _pbyte_mut(p, p.pos + 1);
    if single < 128 {
      return _err_int("rlp: non-canonical single byte");
    }
  }
  let idx = _push_token(p, rlp_kind_bytes(), parent, start);
  p.pos = p.pos + 1;
  p.end[idx] = p.pos + len;
  p.payload_start[idx] = p.pos;
  p.payload_end[idx] = p.pos + len;
  p.value[idx] = len;
  p.pos = p.pos + len;
  return _ok_int(idx);
}

// Parse a long byte string (0xB8..0xBF): `k` length bytes, then the payload.
// Canonical: the length must be >= 56 and its first byte must not be zero.
fn _parse_long_str(p: &mut _RlpParser, parent: Int, k: Int) -> Result[Int, Str] {
  let start = p.pos;
  p.pos = p.pos + 1;
  let lr = _read_long_length(p, k);
  if !lr.is_ok {
    return _err_int(lr.error);
  }
  let len: Int = lr.value;
  if len < 56 {
    return _err_int("rlp: non-canonical long length");
  }
  let remaining = p.data.len() - p.pos;
  if len > remaining {
    return _err_int("rlp: truncated input");
  }
  let idx = _push_token(p, rlp_kind_bytes(), parent, start);
  p.end[idx] = p.pos + len;
  p.payload_start[idx] = p.pos;
  p.payload_end[idx] = p.pos + len;
  p.value[idx] = len;
  p.pos = p.pos + len;
  return _ok_int(idx);
}

// Parse the children of a list whose payload is `plen` bytes starting at the
// cursor (the header has already been consumed and the payload bounds were
// checked by the caller). Fills the list token's child links and returns its
// token index.
fn _parse_list_body(p: &mut _RlpParser, depth: Int, parent: Int, start: Int, plen: Int) -> Result[Int, Str] {
  if depth >= rlp_max_depth() {
    return _err_int(_depth_msg());
  }
  let idx = _push_token(p, rlp_kind_list(), parent, start);
  let payload_end = p.pos + plen;
  var count: Int = 0;
  var first: Int = -1;
  var prev: Int = -1;
  while p.pos < payload_end {
    let child = _parse_value(p, depth + 1, idx);
    if !child.is_ok {
      return _err_int(child.error);
    }
    if p.pos > payload_end {
      return _err_int("rlp: list payload overrun");
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
  p.end[idx] = p.pos;
  p.payload_start[idx] = p.pos - plen;
  p.payload_end[idx] = p.pos;
  p.value[idx] = plen;
  p.first_child[idx] = first;
  p.child_count[idx] = count;
  return _ok_int(idx);
}

// Parse a short list (0xC0..0xF7): `plen` payload bytes follow the header.
fn _parse_short_list(p: &mut _RlpParser, depth: Int, parent: Int, plen: Int) -> Result[Int, Str] {
  let start = p.pos;
  let remaining = p.data.len() - p.pos - 1;
  if plen > remaining {
    return _err_int("rlp: truncated input");
  }
  p.pos = p.pos + 1;
  return _parse_list_body(p, depth, parent, start, plen);
}

// Parse a long list (0xF8..0xFF): `k` length bytes, then the payload.
// Canonical: the length must be >= 56 and its first byte must not be zero.
fn _parse_long_list(p: &mut _RlpParser, depth: Int, parent: Int, k: Int) -> Result[Int, Str] {
  let start = p.pos;
  p.pos = p.pos + 1;
  let lr = _read_long_length(p, k);
  if !lr.is_ok {
    return _err_int(lr.error);
  }
  let plen: Int = lr.value;
  if plen < 56 {
    return _err_int("rlp: non-canonical long length");
  }
  let remaining = p.data.len() - p.pos;
  if plen > remaining {
    return _err_int("rlp: truncated input");
  }
  return _parse_list_body(p, depth, parent, start, plen);
}

// Parse one item at the cursor and return its token index. `depth` is the
// number of enclosing lists (the root item is depth 0); `parent` is the
// enclosing token index, or -1 at the root.
fn _parse_value(p: &mut _RlpParser, depth: Int, parent: Int) -> Result[Int, Str] {
  if p.pos >= p.data.len() {
    return _err_int("rlp: truncated input");
  }
  let b = _pbyte_mut(p, p.pos);
  if b < 128 {
    return _parse_single(p, parent);
  }
  if b <= 183 {
    return _parse_short_str(p, parent, b - 128);
  }
  if b <= 191 {
    return _parse_long_str(p, parent, b - 183);
  }
  if b <= 247 {
    return _parse_short_list(p, depth, parent, b - 192);
  }
  return _parse_long_list(p, depth, parent, b - 247);
}

/// Decode one complete RLP item from `data`.
///
/// The result is an `RlpDoc` holding the input bytes and the flat token
/// stream; use the `rlp_*` accessors to inspect it. `data` must contain
/// exactly one item: bytes after the top-level item are rejected.
///
/// Errors:
/// Err("rlp: truncated input") -- the buffer ends inside a header or payload;
/// Err("rlp: non-canonical single byte") -- 0x81 followed by a byte < 0x80;
/// Err("rlp: leading zero in length") -- a long-form length starts with 0x00;
/// Err("rlp: non-canonical long length") -- a long-form length below 56;
/// Err("rlp: length overflow") -- a length that does not fit the signed
/// 64-bit Int; Err("rlp: list payload overrun") -- a child claims bytes past
/// its list; Err("rlp: nesting depth exceeds limit of 64"); Err("rlp:
/// trailing data after top-level item") -- bytes remain after the root item.
/// Complexity: O(data.len()).
pub fn rlp_decode(data: Vec[UInt8]) -> Result[RlpDoc, Str] {
  var p = _RlpParser{
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
    return _err_doc("rlp: trailing data after top-level item");
  }
  return _ok_doc(_finish(p));
}

// --------------------------------------------------
//  RLP accessors
// --------------------------------------------------

/// Number of tokens in the document (1 for a scalar root item, and one token
/// per nested item).
/// Complexity: O(1).
pub fn rlp_token_count(doc: &RlpDoc) -> Int {
  return doc.kind.len();
}

/// Index of the root token: always 0 for a document produced by
/// `rlp_decode` (kept as a named accessor for symmetry).
/// Complexity: O(1).
pub fn rlp_root(doc: &RlpDoc) -> Int {
  if doc.kind.len() == 0 {
    return -1;
  }
  return 0;
}

/// Kind code of token `i` (one of the `rlp_kind_*` values), or -1 when `i`
/// is outside [0, rlp_token_count(doc)).
/// Complexity: O(1).
pub fn rlp_kind(doc: &RlpDoc, i: Int) -> Int {
  if i < 0 || i >= doc.kind.len() {
    return -1;
  }
  let k: Int = doc.kind[i];
  return k;
}

/// True when token `i` is a byte string (including the single-byte form).
/// Complexity: O(1).
pub fn rlp_is_bytes(doc: &RlpDoc, i: Int) -> Bool {
  return rlp_kind(doc, i) == rlp_kind_bytes();
}

/// True when token `i` is a list.
/// Complexity: O(1).
pub fn rlp_is_list(doc: &RlpDoc, i: Int) -> Bool {
  return rlp_kind(doc, i) == rlp_kind_list();
}

/// Index of the token that contains token `i`, or -1 for the root token and
/// for an out-of-range `i`.
/// Complexity: O(1).
pub fn rlp_parent(doc: &RlpDoc, i: Int) -> Int {
  if i < 0 || i >= doc.parent.len() {
    return -1;
  }
  let v: Int = doc.parent[i];
  return v;
}

/// Index of the first direct child of token `i`, or -1 for a byte string and
/// for an out-of-range `i`.
/// Complexity: O(1).
pub fn rlp_first_child(doc: &RlpDoc, i: Int) -> Int {
  if i < 0 || i >= doc.first_child.len() {
    return -1;
  }
  let v: Int = doc.first_child[i];
  return v;
}

/// Number of direct children of token `i` (the item count of a list), or 0
/// for a byte string and for an out-of-range `i`.
/// Complexity: O(1).
pub fn rlp_child_count(doc: &RlpDoc, i: Int) -> Int {
  if i < 0 || i >= doc.child_count.len() {
    return 0;
  }
  let v: Int = doc.child_count[i];
  return v;
}

/// Index of the n-th direct child of token `i` (0-based), or -1 when `i` is
/// not a list or `n` is outside [0, rlp_child_count(doc, i)).
/// Complexity: O(n).
pub fn rlp_child(doc: &RlpDoc, i: Int, n: Int) -> Int {
  let count = rlp_child_count(doc, i);
  if n < 0 || n >= count {
    return -1;
  }
  var t = rlp_first_child(doc, i);
  var k = 0;
  while k < n {
    t = rlp_next_sibling(doc, t);
    k = k + 1;
  }
  return t;
}

/// Index of the next direct sibling of token `i` under the same parent, or
/// -1 when `i` is the last direct child (and for out-of-range `i`).
/// Pre-order token indices are not siblings just because they are adjacent:
/// a token's subtree sits between it and its next sibling, so callers must
/// use this accessor (or `rlp_child`) to iterate a list's children.
/// Complexity: O(1).
pub fn rlp_next_sibling(doc: &RlpDoc, i: Int) -> Int {
  if i < 0 || i >= doc.next_sibling.len() {
    return -1;
  }
  let v: Int = doc.next_sibling[i];
  return v;
}

/// Byte offset of the first byte of item `i` (header included), or -1 when
/// `i` is outside [0, rlp_token_count(doc)).
/// Complexity: O(1).
pub fn rlp_token_start(doc: &RlpDoc, i: Int) -> Int {
  if i < 0 || i >= doc.start.len() {
    return -1;
  }
  let v: Int = doc.start[i];
  return v;
}

/// Byte offset one past the last byte of item `i`, or -1 when `i` is outside
/// [0, rlp_token_count(doc)).
/// Complexity: O(1).
pub fn rlp_token_end(doc: &RlpDoc, i: Int) -> Int {
  if i < 0 || i >= doc.end.len() {
    return -1;
  }
  let v: Int = doc.end[i];
  return v;
}

/// Byte offset of the first payload byte of item `i` (the bytes after the
/// header for a string, the first child for a list), or -1 when `i` is
/// outside [0, rlp_token_count(doc)). Together with `rlp_payload_end` this
/// is the payload span.
/// Complexity: O(1).
pub fn rlp_payload_start(doc: &RlpDoc, i: Int) -> Int {
  if i < 0 || i >= doc.payload_start.len() {
    return -1;
  }
  let v: Int = doc.payload_start[i];
  return v;
}

/// Byte offset one past the last payload byte of item `i`, or -1 when `i` is
/// outside [0, rlp_token_count(doc)).
/// Complexity: O(1).
pub fn rlp_payload_end(doc: &RlpDoc, i: Int) -> Int {
  if i < 0 || i >= doc.payload_end.len() {
    return -1;
  }
  let v: Int = doc.payload_end[i];
  return v;
}

/// Payload byte length of item `i` (the string payload length, or the total
/// payload bytes of a list), or -1 when `i` is outside
/// [0, rlp_token_count(doc)).
/// Complexity: O(1).
pub fn rlp_payload_len(doc: &RlpDoc, i: Int) -> Int {
  if i < 0 || i >= doc.value.len() {
    return -1;
  }
  let v: Int = doc.value[i];
  return v;
}

/// Copy of a byte-string item's payload, or an empty vector when `i` is a
/// list or is out of range (a valid empty byte string is therefore
/// indistinguishable from a non-string here; check the kind first).
/// Complexity: O(payload length).
pub fn rlp_item_bytes(doc: &RlpDoc, i: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  if rlp_kind(doc, i) != rlp_kind_bytes() {
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

/// Copy of the exact source bytes of item `i` (header plus payload), or an
/// empty vector when `i` is out of range.
/// Complexity: O(item length).
pub fn rlp_token_bytes(doc: &RlpDoc, i: Int) -> Vec[UInt8] {
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
//  RLP encoders
// --------------------------------------------------

// Append the canonical RLP header for a payload of `len` bytes: `short_base`
// + len when len <= 55, else `long_base` + the number of length bytes, then
// the length big-endian.
fn _push_rlp_header(out: &mut Vec[UInt8], short_base: Int, long_base: Int, len: Int) {
  if len <= 55 {
    out.push((short_base + len) as UInt8);
    return;
  }
  var k = 0;
  var t = len;
  while t > 0 {
    k = k + 1;
    t = t / 256;
  }
  out.push((long_base + k) as UInt8);
  _push_be(out, len, k);
}

/// Canonical RLP encoding of a byte string: the empty string is 0x80, a
/// single byte below 0x80 is itself, otherwise the length-prefixed form
/// (short when <= 55 bytes, long otherwise).
/// Complexity: O(bytes.len()).
pub fn rlp_encode_bytes(bytes: &Vec[UInt8]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  let n = bytes.len();
  if n == 1 {
    let b: UInt8 = bytes[0];
    let x = (b as Int) & 0xFF;
    if x < 128 {
      out.push(b);
      return out;
    }
  }
  _push_rlp_header(&mut out, 128, 183, n);
  _push_all(&mut out, bytes);
  return out;
}

/// Canonical RLP encoding of a `Str` as a byte string: the length is the
/// UTF-8 byte length and the bytes are copied verbatim.
/// Complexity: O(byte length).
pub fn rlp_encode_str(s: Str) -> Vec[UInt8] {
  var bytes = Vec[UInt8].new();
  let n = string.str_len(s);
  var i = 0;
  while i < n {
    let b: UInt8 = string.byte_at(s, i);
    bytes.push(b);
    i = i + 1;
  }
  return rlp_encode_bytes(&bytes);
}

/// Canonical RLP encoding of a non-negative integer: the shortest
/// big-endian byte string with no leading zeros (zero is the empty string
/// 0x80).
/// Err("rlp: integer must be non-negative") for negative input.
/// Complexity: O(log n).
pub fn rlp_encode_int(n: Int) -> Result[Vec[UInt8], Str] {
  if n < 0 {
    return _err_bytes("rlp: integer must be non-negative");
  }
  var out = Vec[UInt8].new();
  if n == 0 {
    out.push(128 as UInt8);
    return _ok_bytes(out);
  }
  if n < 128 {
    out.push(n as UInt8);
    return _ok_bytes(out);
  }
  var k = 0;
  var t = n;
  while t > 0 {
    k = k + 1;
    t = t / 256;
  }
  _push_rlp_header(&mut out, 128, 183, k);
  _push_be(&mut out, n, k);
  return _ok_bytes(out);
}

/// Canonical RLP encoding of a list from already-encoded item chunks, in
/// order: the list header (short when the total payload is <= 55 bytes, long
/// otherwise) followed by the chunks verbatim. The empty list is 0xC0.
/// Complexity: O(total chunk bytes).
pub fn rlp_encode_list(parts: &Vec[Vec[UInt8]]) -> Vec[UInt8] {
  var total = 0;
  var i = 0;
  while i < parts.len() {
    let part: Vec[UInt8] = parts[i];
    total = total + part.len();
    i = i + 1;
  }
  var out = Vec[UInt8].new();
  _push_rlp_header(&mut out, 192, 247, total);
  i = 0;
  while i < parts.len() {
    let part: Vec[UInt8] = parts[i];
    _push_all(&mut out, &part);
    i = i + 1;
  }
  return out;
}

// Append token `i` (and its subtree) to `out` in canonical form. Decoding is
// strict, so the rebuilt bytes equal the original input.
fn _reser_token(doc: &RlpDoc, i: Int, out: &mut Vec[UInt8]) {
  let k: Int = doc.kind[i];
  let plen: Int = doc.value[i];
  if k == rlp_kind_bytes() {
    let from: Int = doc.payload_start[i];
    let to: Int = doc.payload_end[i];
    if plen == 1 {
      let b: UInt8 = doc.data[from];
      if ((b as Int) & 0xFF) < 128 {
        out.push(b);
        return;
      }
    }
    _push_rlp_header(out, 128, 183, plen);
    var j = from;
    while j < to {
      out.push(doc.data[j]);
      j = j + 1;
    }
  } else {
    _push_rlp_header(out, 192, 247, plen);
    let first: Int = doc.first_child[i];
    let count: Int = doc.child_count[i];
    var t = first;
    var j = 0;
    while j < count {
      _reser_token(doc, t, out);
      t = rlp_next_sibling(doc, t);
      j = j + 1;
    }
  }
}

/// Re-encode a decoded document to canonical RLP bytes by walking the token
/// stream (it does not copy `data`, so it is a real reconstruction check).
/// Because `rlp_decode` rejects every non-canonical form, the result equals
/// the original input for any document it produced. An empty document yields
/// an empty vector.
/// Complexity: O(input bytes).
pub fn rlp_reserialize(doc: &RlpDoc) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  if doc.kind.len() == 0 {
    return out;
  }
  _reser_token(doc, 0, &mut out);
  return out;
}

// --------------------------------------------------
//  Legacy transaction field listing
// --------------------------------------------------

/// Number of direct children of transaction token `tx` (9 for a legacy
/// signed transaction or an EIP-155 preimage), or 0 when `tx` is not a list.
/// Complexity: O(1).
pub fn tx_field_count(doc: &RlpDoc, tx: Int) -> Int {
  if rlp_kind(doc, tx) != rlp_kind_list() {
    return 0;
  }
  return rlp_child_count(doc, tx);
}

/// RLP item index of field `field` (0-based, listed order) of transaction
/// token `tx`, or -1 when `tx` is not a list or `field` is out of range.
/// Complexity: O(field).
pub fn tx_field(doc: &RlpDoc, tx: Int, field: Int) -> Int {
  if rlp_kind(doc, tx) != rlp_kind_list() {
    return -1;
  }
  return rlp_child(doc, tx, field);
}

/// RLP item index of the `nonce` field (0), or -1.
/// Complexity: O(1).
pub fn tx_nonce(doc: &RlpDoc, tx: Int) -> Int {
  return tx_field(doc, tx, 0);
}

/// RLP item index of the `gasPrice` field (1), or -1.
/// Complexity: O(1).
pub fn tx_gas_price(doc: &RlpDoc, tx: Int) -> Int {
  return tx_field(doc, tx, 1);
}

/// RLP item index of the `gasLimit` field (2), or -1.
/// Complexity: O(1).
pub fn tx_gas_limit(doc: &RlpDoc, tx: Int) -> Int {
  return tx_field(doc, tx, 2);
}

/// RLP item index of the `to` field (3), or -1. The value is either a
/// 20-byte byte string or the empty byte string (contract creation); use
/// `rlp_payload_len` to tell them apart.
/// Complexity: O(1).
pub fn tx_to(doc: &RlpDoc, tx: Int) -> Int {
  return tx_field(doc, tx, 3);
}

/// RLP item index of the `value` field (4), or -1.
/// Complexity: O(1).
pub fn tx_value(doc: &RlpDoc, tx: Int) -> Int {
  return tx_field(doc, tx, 4);
}

/// RLP item index of the `data` field (5), or -1.
/// Complexity: O(1).
pub fn tx_data(doc: &RlpDoc, tx: Int) -> Int {
  return tx_field(doc, tx, 5);
}

/// RLP item index of the `v` field (6), or -1. This is the raw item: for a
/// signed legacy transaction it is the recovery id (27/28, or 35/36 plus
/// twice the chain id under EIP-155); this module does not interpret it.
/// Complexity: O(1).
pub fn tx_v(doc: &RlpDoc, tx: Int) -> Int {
  return tx_field(doc, tx, 6);
}

/// RLP item index of the `r` field (7), or -1.
/// Complexity: O(1).
pub fn tx_r(doc: &RlpDoc, tx: Int) -> Int {
  return tx_field(doc, tx, 7);
}

/// RLP item index of the `s` field (8), or -1.
/// Complexity: O(1).
pub fn tx_s(doc: &RlpDoc, tx: Int) -> Int {
  return tx_field(doc, tx, 8);
}

/// True when `tx` is the EIP-155 signing preimage:
/// [nonce, gasPrice, gasLimit, to, value, data, chainId, 0, 0] -- a 9-item
/// list whose last two fields are empty byte strings.
/// Complexity: O(1).
pub fn tx_is_unsigned_155(doc: &RlpDoc, tx: Int) -> Bool {
  if rlp_kind(doc, tx) != rlp_kind_list() {
    return false;
  }
  if rlp_child_count(doc, tx) != 9 {
    return false;
  }
  let f7 = tx_field(doc, tx, 7);
  let f8 = tx_field(doc, tx, 8);
  if f7 < 0 || f8 < 0 {
    return false;
  }
  if rlp_kind(doc, f7) != rlp_kind_bytes() {
    return false;
  }
  if rlp_kind(doc, f8) != rlp_kind_bytes() {
    return false;
  }
  if rlp_payload_len(doc, f7) != 0 {
    return false;
  }
  if rlp_payload_len(doc, f8) != 0 {
    return false;
  }
  return true;
}

/// RLP item index of the EIP-155 `chainId` in the signing preimage (field 6
/// when `tx_is_unsigned_155` holds), or -1 otherwise.
///
/// ChainId note: in a signed 9-item legacy transaction field 6 is `v`, not
/// the chain id, so this accessor refuses to guess; callers that want a
/// signed transaction's chain id must combine `tx_v` with `tx_r`/`tx_s`
/// themselves (v = chainId * 2 + 35/36). No signature interpretation is
/// performed here.
/// Complexity: O(1).
pub fn tx_chain_id(doc: &RlpDoc, tx: Int) -> Int {
  if !tx_is_unsigned_155(doc, tx) {
    return -1;
  }
  return tx_field(doc, tx, 6);
}

// --------------------------------------------------
//  ABI: widths, words, static type encoding
// --------------------------------------------------

/// ABI word size in bytes.
pub fn abi_word_size() -> Int {
  return 32;
}

/// Function selector size in bytes (keccak of the signature is the caller's
/// job).
pub fn abi_selector_size() -> Int {
  return 4;
}

/// Byte offset at which a function call's argument section starts (right
/// after the 4-byte selector); dynamic offsets are relative to this base.
pub fn abi_call_args_offset() -> Int {
  return 4;
}

/// True for M = 8, 16, ..., 256 (the valid uint<M>/int<M> widths).
pub fn abi_valid_int_bits(m: Int) -> Bool {
  if m < 8 {
    return false;
  }
  if m > 256 {
    return false;
  }
  if m % 8 != 0 {
    return false;
  }
  return true;
}

/// True for M = 1..32 (the valid bytes<M> widths).
pub fn abi_valid_bytes_m(m: Int) -> Bool {
  return m >= 1 && m <= 32;
}

// Read byte `i` of a 32-byte word (0..255).
fn _word_byte(w: &Vec[UInt8], i: Int) -> Int {
  let b: UInt8 = w[i];
  return (b as Int) & 0xFF;
}

/// Copy the 32-byte word at absolute byte offset `off` of `data`.
/// Err("abi: word out of bounds at offset N") when the word does not fit.
/// Complexity: O(1).
pub fn abi_read_word(data: &Vec[UInt8], off: Int) -> Result[Vec[UInt8], Str] {
  if off < 0 {
    return _err_bytes("abi: word out of bounds at offset " + convert.int_to_string(off));
  }
  if data.len() < 32 {
    return _err_bytes("abi: word out of bounds at offset " + convert.int_to_string(off));
  }
  if off > data.len() - 32 {
    return _err_bytes("abi: word out of bounds at offset " + convert.int_to_string(off));
  }
  var out = Vec[UInt8].new();
  var i = 0;
  while i < 32 {
    out.push(data[off + i]);
    i = i + 1;
  }
  return _ok_bytes(out);
}

// Decode a 32-byte offset word (non-negative, fits Int) into an Int.
// `at` is the word's byte offset, used only for the error message.
fn _abi_offset_of_word(word: &Vec[UInt8], at: Int) -> Result[Int, Str] {
  var i = 0;
  while i < 24 {
    if _word_byte(word, i) != 0 {
      return _err_int("abi: offset word exceeds Int at offset " + convert.int_to_string(at));
    }
    i = i + 1;
  }
  if _word_byte(word, 24) >= 128 {
    return _err_int("abi: offset word exceeds Int at offset " + convert.int_to_string(at));
  }
  var v: Int = 0;
  i = 24;
  while i < 32 {
    v = v * 256 + _word_byte(word, i);
    i = i + 1;
  }
  return _ok_int(v);
}

// Decode a 32-byte length word (non-negative, fits Int) into an Int.
// `at` is the word's byte offset, used only for the error message.
fn _abi_length_of_word(word: &Vec[UInt8], at: Int) -> Result[Int, Str] {
  var i = 0;
  while i < 24 {
    if _word_byte(word, i) != 0 {
      return _err_int("abi: length word exceeds Int at offset " + convert.int_to_string(at));
    }
    i = i + 1;
  }
  if _word_byte(word, 24) >= 128 {
    return _err_int("abi: length word exceeds Int at offset " + convert.int_to_string(at));
  }
  var v: Int = 0;
  i = 24;
  while i < 32 {
    v = v * 256 + _word_byte(word, i);
    i = i + 1;
  }
  return _ok_int(v);
}

/// Encode a uint<M> value (M = 8..256 step 8) as one 32-byte big-endian
/// word. The value must be non-negative and below 2^M; values that fit the
/// width but not the signed 64-bit Int cannot be supplied to this Int-based
/// API.
/// Err("abi: invalid uint width M") for a bad M, Err("abi: uint value is
/// negative"), Err("abi: uint value exceeds uint width M").
/// Complexity: O(1).
pub fn abi_encode_uint(value: Int, m: Int) -> Result[Vec[UInt8], Str] {
  if !abi_valid_int_bits(m) {
    return _err_bytes("abi: invalid uint width " + convert.int_to_string(m));
  }
  if value < 0 {
    return _err_bytes("abi: uint value is negative");
  }
  if m <= 62 {
    let lim = _pow2(m);
    if value >= lim {
      return _err_bytes("abi: uint value exceeds uint width " + convert.int_to_string(m));
    }
  }
  var out = Vec[UInt8].new();
  _push_word(&mut out, value);
  return _ok_bytes(out);
}

/// Encode an int<M> value (M = 8..256 step 8) as one 32-byte two's
/// complement big-endian word. The value must lie in [-2^(M-1),
/// 2^(M-1) - 1].
/// Err("abi: invalid int width M") for a bad M, Err("abi: int value exceeds
/// int width M") when out of range.
/// Complexity: O(1).
pub fn abi_encode_int(value: Int, m: Int) -> Result[Vec[UInt8], Str] {
  if !abi_valid_int_bits(m) {
    return _err_bytes("abi: invalid int width " + convert.int_to_string(m));
  }
  if m <= 63 {
    let lim = _pow2(m - 1);
    if value < -lim {
      return _err_bytes("abi: int value exceeds int width " + convert.int_to_string(m));
    }
    if value > lim - 1 {
      return _err_bytes("abi: int value exceeds int width " + convert.int_to_string(m));
    }
  }
  var out = Vec[UInt8].new();
  _push_word(&mut out, value);
  return _ok_bytes(out);
}

/// Encode an ABI bool word from 0 (false) or 1 (true).
/// Err("abi: bool value must be 0 or 1") for any other value.
/// Complexity: O(1).
pub fn abi_encode_bool(value: Int) -> Result[Vec[UInt8], Str] {
  if value != 0 && value != 1 {
    return _err_bytes("abi: bool value must be 0 or 1");
  }
  var out = Vec[UInt8].new();
  _push_word(&mut out, value);
  return _ok_bytes(out);
}

/// Encode a 20-byte address as a 32-byte word, right-aligned (12 zero bytes
/// then the address).
/// Err("abi: address value must be 20 bytes") otherwise.
/// Complexity: O(1).
pub fn abi_encode_address(address: &Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  if address.len() != 20 {
    return _err_bytes("abi: address value must be 20 bytes");
  }
  var out = Vec[UInt8].new();
  var i = 0;
  while i < 12 {
    out.push(0 as UInt8);
    i = i + 1;
  }
  _push_all(&mut out, address);
  return _ok_bytes(out);
}

/// Encode a bytes<M> fixed value (M = 1..32) as a 32-byte word,
/// left-aligned and zero-padded on the right. At most M bytes may be
/// supplied.
/// Err("abi: invalid fixed-bytes width M"), Err("abi: fixed bytes value
/// exceeds width M").
/// Complexity: O(1).
pub fn abi_encode_bytes_m(value: &Vec[UInt8], m: Int) -> Result[Vec[UInt8], Str] {
  if !abi_valid_bytes_m(m) {
    return _err_bytes("abi: invalid fixed-bytes width " + convert.int_to_string(m));
  }
  if value.len() > m {
    return _err_bytes("abi: fixed bytes value exceeds width " + convert.int_to_string(m));
  }
  var out = Vec[UInt8].new();
  _push_all(&mut out, value);
  while out.len() < 32 {
    out.push(0 as UInt8);
  }
  return _ok_bytes(out);
}

/// Encode up to 32 bytes as a bytes32 word (left-aligned, zero-padded).
/// Complexity: O(1).
pub fn abi_encode_bytes32(value: &Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  return abi_encode_bytes_m(value, 32);
}

/// Decode one 32-byte word as a uint<M>. Requires the high 24 bytes to be
/// zero and the value to fit the signed 64-bit Int, then checks the uint<M>
/// bound.
/// Err("abi: word must be 32 bytes"), Err("abi: invalid uint width M"),
/// Err("abi: uint word does not fit Int"), Err("abi: uint word exceeds uint
/// width M").
/// Complexity: O(1).
pub fn abi_decode_uint_word(word: &Vec[UInt8], m: Int) -> Result[Int, Str] {
  if word.len() != 32 {
    return _err_int("abi: word must be 32 bytes");
  }
  if !abi_valid_int_bits(m) {
    return _err_int("abi: invalid uint width " + convert.int_to_string(m));
  }
  var i = 0;
  while i < 24 {
    if _word_byte(word, i) != 0 {
      return _err_int("abi: uint word does not fit Int");
    }
    i = i + 1;
  }
  if _word_byte(word, 24) >= 128 {
    return _err_int("abi: uint word does not fit Int");
  }
  var v: Int = 0;
  i = 24;
  while i < 32 {
    v = v * 256 + _word_byte(word, i);
    i = i + 1;
  }
  if m <= 62 {
    let lim = _pow2(m);
    if v >= lim {
      return _err_int("abi: uint word exceeds uint width " + convert.int_to_string(m));
    }
  }
  return _ok_int(v);
}

/// Decode one 32-byte word as an int<M>. Requires the high 24 bytes to be
/// the sign extension of byte 24 and the value to fit the signed 64-bit
/// Int, then checks the int<M> bound.
/// Err("abi: word must be 32 bytes"), Err("abi: invalid int width M"),
/// Err("abi: int word does not fit Int"), Err("abi: int word exceeds int
/// width M").
/// Complexity: O(1).
pub fn abi_decode_int_word(word: &Vec[UInt8], m: Int) -> Result[Int, Str] {
  if word.len() != 32 {
    return _err_int("abi: word must be 32 bytes");
  }
  if !abi_valid_int_bits(m) {
    return _err_int("abi: invalid int width " + convert.int_to_string(m));
  }
  let top = _word_byte(word, 24);
  var fill = 0;
  if top >= 128 {
    fill = 255;
  }
  var i = 0;
  while i < 24 {
    if _word_byte(word, i) != fill {
      return _err_int("abi: int word does not fit Int");
    }
    i = i + 1;
  }
  var v: Int = 0;
  if top >= 128 {
    v = -1;
  }
  i = 24;
  while i < 32 {
    v = v * 256 + _word_byte(word, i);
    i = i + 1;
  }
  if m <= 63 {
    let lim = _pow2(m - 1);
    if v < -lim {
      return _err_int("abi: int word exceeds int width " + convert.int_to_string(m));
    }
    if v > lim - 1 {
      return _err_int("abi: int word exceeds int width " + convert.int_to_string(m));
    }
  }
  return _ok_int(v);
}

/// Decode one 32-byte word as an ABI bool: 31 zero bytes then 0x00 or 0x01.
/// Err("abi: word must be 32 bytes"), Err("abi: bool word must be 0 or 1").
/// Complexity: O(1).
pub fn abi_decode_bool_word(word: &Vec[UInt8]) -> Result[Bool, Str] {
  if word.len() != 32 {
    return _err_bool("abi: word must be 32 bytes");
  }
  var i = 0;
  while i < 31 {
    if _word_byte(word, i) != 0 {
      return _err_bool("abi: bool word must be 0 or 1");
    }
    i = i + 1;
  }
  let last = _word_byte(word, 31);
  if last == 0 {
    return _ok_bool(false);
  }
  if last == 1 {
    return _ok_bool(true);
  }
  return _err_bool("abi: bool word must be 0 or 1");
}

/// Decode one 32-byte word as an address: 12 zero bytes then 20 address
/// bytes.
/// Err("abi: word must be 32 bytes"), Err("abi: address word is not
/// right-aligned").
/// Complexity: O(1).
pub fn abi_decode_address_word(word: &Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  if word.len() != 32 {
    return _err_bytes("abi: word must be 32 bytes");
  }
  var i = 0;
  while i < 12 {
    if _word_byte(word, i) != 0 {
      return _err_bytes("abi: address word is not right-aligned");
    }
    i = i + 1;
  }
  var out = Vec[UInt8].new();
  i = 12;
  while i < 32 {
    out.push(word[i]);
    i = i + 1;
  }
  return _ok_bytes(out);
}

/// Decode one 32-byte word as bytes<M> (M = 1..32): the first M bytes are
/// the value and the remaining 32 - M bytes must be zero.
/// Err("abi: word must be 32 bytes"), Err("abi: invalid fixed-bytes width
/// M"), Err("abi: fixed bytes padding is not zero").
/// Complexity: O(1).
pub fn abi_decode_bytes_m_word(word: &Vec[UInt8], m: Int) -> Result[Vec[UInt8], Str] {
  if word.len() != 32 {
    return _err_bytes("abi: word must be 32 bytes");
  }
  if !abi_valid_bytes_m(m) {
    return _err_bytes("abi: invalid fixed-bytes width " + convert.int_to_string(m));
  }
  var i = m;
  while i < 32 {
    if _word_byte(word, i) != 0 {
      return _err_bytes("abi: fixed bytes padding is not zero");
    }
    i = i + 1;
  }
  var out = Vec[UInt8].new();
  i = 0;
  while i < m {
    out.push(word[i]);
    i = i + 1;
  }
  return _ok_bytes(out);
}

/// Decode one 32-byte word as bytes32.
/// Complexity: O(1).
pub fn abi_decode_bytes32_word(word: &Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  return abi_decode_bytes_m_word(word, 32);
}

/// Decode the uint<M> word at absolute byte offset `off` of `data` (bounds
/// checked).
/// Complexity: O(1).
pub fn abi_decode_uint(data: &Vec[UInt8], off: Int, m: Int) -> Result[Int, Str] {
  let wr = abi_read_word(data, off);
  if !wr.is_ok {
    return _err_int(wr.error);
  }
  let w: Vec[UInt8] = wr.value;
  return abi_decode_uint_word(&w, m);
}

/// Decode the int<M> word at absolute byte offset `off` of `data` (bounds
/// checked).
/// Complexity: O(1).
pub fn abi_decode_int(data: &Vec[UInt8], off: Int, m: Int) -> Result[Int, Str] {
  let wr = abi_read_word(data, off);
  if !wr.is_ok {
    return _err_int(wr.error);
  }
  let w: Vec[UInt8] = wr.value;
  return abi_decode_int_word(&w, m);
}

/// Decode the bool word at absolute byte offset `off` of `data` (bounds
/// checked).
/// Complexity: O(1).
pub fn abi_decode_bool(data: &Vec[UInt8], off: Int) -> Result[Bool, Str] {
  let wr = abi_read_word(data, off);
  if !wr.is_ok {
    return _err_bool(wr.error);
  }
  let w: Vec[UInt8] = wr.value;
  return abi_decode_bool_word(&w);
}

/// Decode the address word at absolute byte offset `off` of `data` (bounds
/// checked).
/// Complexity: O(1).
pub fn abi_decode_address(data: &Vec[UInt8], off: Int) -> Result[Vec[UInt8], Str] {
  let wr = abi_read_word(data, off);
  if !wr.is_ok {
    return _err_bytes(wr.error);
  }
  let w: Vec[UInt8] = wr.value;
  return abi_decode_address_word(&w);
}

/// Decode the bytes<M> word at absolute byte offset `off` of `data` (bounds
/// checked).
/// Complexity: O(1).
pub fn abi_decode_bytes_m(data: &Vec[UInt8], off: Int, m: Int) -> Result[Vec[UInt8], Str] {
  let wr = abi_read_word(data, off);
  if !wr.is_ok {
    return _err_bytes(wr.error);
  }
  let w: Vec[UInt8] = wr.value;
  return abi_decode_bytes_m_word(&w, m);
}

/// Decode the bytes32 word at absolute byte offset `off` of `data` (bounds
/// checked).
/// Complexity: O(1).
pub fn abi_decode_bytes32(data: &Vec[UInt8], off: Int) -> Result[Vec[UInt8], Str] {
  return abi_decode_bytes_m(data, off, 32);
}

// --------------------------------------------------
//  ABI: dynamic types
// --------------------------------------------------

// Resolve the dynamic offset word stored at absolute offset `head_off` of
// `data` and return the absolute offset of the referenced length word.
// Offsets are relative to `base` (0 for a standalone block, 4 for call
// arguments after the selector). Bounds checked: the offset must be
// word-aligned, must point after the head word (`base + 32`), and the length
// word must fit in `data`.
fn _abi_resolve_tail(data: &Vec[UInt8], head_off: Int, base: Int) -> Result[Int, Str] {
  let wr = abi_read_word(data, head_off);
  if !wr.is_ok {
    return _err_int(wr.error);
  }
  let word: Vec[UInt8] = wr.value;
  let od = _abi_offset_of_word(&word, head_off);
  if !od.is_ok {
    return _err_int(od.error);
  }
  let rel: Int = od.value;
  if rel % 32 != 0 {
    return _err_int("abi: dynamic offset is not word-aligned at offset " + convert.int_to_string(head_off));
  }
  if rel > 9223372036854775807 - base {
    return _err_int("abi: dynamic offset out of bounds at offset " + convert.int_to_string(head_off));
  }
  let target = base + rel;
  if target < base + 32 {
    return _err_int("abi: dynamic offset points into the head at offset " + convert.int_to_string(head_off));
  }
  if data.len() < 32 {
    return _err_int("abi: dynamic offset out of bounds at offset " + convert.int_to_string(head_off));
  }
  if target > data.len() - 32 {
    return _err_int("abi: dynamic offset out of bounds at offset " + convert.int_to_string(head_off));
  }
  return _ok_int(target);
}

// Read the length word at absolute offset `target` and return the element
// count, requiring all `count` 32-byte elements to fit in `data`.
fn _abi_array_count_at(data: &Vec[UInt8], target: Int) -> Result[Int, Str] {
  let lr = abi_read_word(data, target);
  if !lr.is_ok {
    return _err_int(lr.error);
  }
  let lw: Vec[UInt8] = lr.value;
  let ld = _abi_length_of_word(&lw, target);
  if !ld.is_ok {
    return _err_int(ld.error);
  }
  let count: Int = ld.value;
  let dstart = target + 32;
  let avail = data.len() - dstart;
  if count > avail / 32 {
    return _err_int("abi: array elements out of bounds at offset " + convert.int_to_string(dstart));
  }
  return _ok_int(count);
}

/// Encode the tail of a dynamic bytes/string value: the 32-byte length word
/// followed by the payload, zero-padded to a 32-byte boundary. In a function
/// call this is the tail chunk; the matching offset word goes in the head.
/// Complexity: O(payload length).
pub fn abi_encode_dynamic_bytes_tail(payload: &Vec[UInt8]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  let n = payload.len();
  _push_word(&mut out, n);
  _push_all(&mut out, payload);
  let pad = _abi_pad_bytes(n);
  var i = 0;
  while i < pad {
    out.push(0 as UInt8);
    i = i + 1;
  }
  return out;
}

/// Encode a standalone dynamic bytes/string value: a 32-byte offset word
/// (0x20, the tail starts right after the head) followed by the length word
/// and zero-padded payload. Solidity `string` values are uninterpreted
/// UTF-8 bytes here, so the same encoding serves both.
/// Complexity: O(payload length).
pub fn abi_encode_dynamic_bytes(payload: &Vec[UInt8]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  _push_word(&mut out, 32);
  let tail = abi_encode_dynamic_bytes_tail(payload);
  _push_all(&mut out, &tail);
  return out;
}

/// Decode a dynamic bytes/string value whose offset word sits at absolute
/// offset `head_off` of `data`; offsets are relative to `base` (0 for a
/// standalone block, `abi_call_args_offset()` for call arguments). The
/// offset must be word-aligned and point past the head word, the length word
/// must fit, and the zero-padded payload must fit in `data`.
/// Errors are `abi: word out of bounds at offset N`, `abi: offset word
/// exceeds Int at offset N`, `abi: dynamic offset is not word-aligned at
/// offset N`, `abi: dynamic offset points into the head at offset N`,
/// `abi: dynamic offset out of bounds at offset N`, `abi: length word
/// exceeds Int at offset N`, `abi: dynamic data out of bounds at offset N`.
/// Complexity: O(payload length).
pub fn abi_decode_dynamic_bytes(data: &Vec[UInt8], head_off: Int, base: Int) -> Result[Vec[UInt8], Str] {
  let tr = _abi_resolve_tail(data, head_off, base);
  if !tr.is_ok {
    return _err_bytes(tr.error);
  }
  let target: Int = tr.value;
  let lr = abi_read_word(data, target);
  if !lr.is_ok {
    return _err_bytes(lr.error);
  }
  let lw: Vec[UInt8] = lr.value;
  let ld = _abi_length_of_word(&lw, target);
  if !ld.is_ok {
    return _err_bytes(ld.error);
  }
  let len: Int = ld.value;
  let dstart = target + 32;
  let avail = data.len() - dstart;
  if len > avail {
    return _err_bytes("abi: dynamic data out of bounds at offset " + convert.int_to_string(dstart));
  }
  let pad = _abi_pad_bytes(len);
  if len + pad > avail {
    return _err_bytes("abi: dynamic data out of bounds at offset " + convert.int_to_string(dstart));
  }
  var out = Vec[UInt8].new();
  var i = 0;
  while i < len {
    out.push(data[dstart + i]);
    i = i + 1;
  }
  return _ok_bytes(out);
}

/// Encode the tail of a dynamic array of 32-byte static words: the 32-byte
/// length word followed by the elements. Every element must be exactly 32
/// bytes.
/// Err("abi: array element must be 32 bytes").
/// Complexity: O(elements).
pub fn abi_encode_word_array_tail(words: &Vec[Vec[UInt8]]) -> Result[Vec[UInt8], Str] {
  var i = 0;
  while i < words.len() {
    let w: Vec[UInt8] = words[i];
    if w.len() != 32 {
      return _err_bytes("abi: array element must be 32 bytes");
    }
    i = i + 1;
  }
  var out = Vec[UInt8].new();
  _push_word(&mut out, words.len());
  i = 0;
  while i < words.len() {
    let w: Vec[UInt8] = words[i];
    _push_all(&mut out, &w);
    i = i + 1;
  }
  return _ok_bytes(out);
}

/// Encode a standalone dynamic array of 32-byte static words: a 32-byte
/// offset word (0x20) then the length word and the elements. Use the typed
/// `abi_encode_uint`/`abi_encode_int`/... functions to build each element
/// word first.
/// Complexity: O(elements).
pub fn abi_encode_word_array(words: &Vec[Vec[UInt8]]) -> Result[Vec[UInt8], Str] {
  let tr = abi_encode_word_array_tail(words);
  if !tr.is_ok {
    return _err_bytes(tr.error);
  }
  var out = Vec[UInt8].new();
  _push_word(&mut out, 32);
  let tail: Vec[UInt8] = tr.value;
  _push_all(&mut out, &tail);
  return _ok_bytes(out);
}

/// Element count of the dynamic array whose offset word sits at absolute
/// offset `head_off` of `data` (offsets relative to `base`), requiring all
/// elements to fit in `data`.
/// Complexity: O(1).
pub fn abi_decode_array_count(data: &Vec[UInt8], head_off: Int, base: Int) -> Result[Int, Str] {
  let tr = _abi_resolve_tail(data, head_off, base);
  if !tr.is_ok {
    return _err_int(tr.error);
  }
  let target: Int = tr.value;
  return _abi_array_count_at(data, target);
}

/// Copy of the 32-byte element at `index` (0-based) of the dynamic array
/// whose offset word sits at absolute offset `head_off` of `data` (offsets
/// relative to `base`). The index is bounds checked against the decoded
/// element count.
/// Err("abi: array index out of range") when the index is outside the array.
/// Complexity: O(1).
pub fn abi_array_element(data: &Vec[UInt8], head_off: Int, base: Int, index: Int) -> Result[Vec[UInt8], Str] {
  let tr = _abi_resolve_tail(data, head_off, base);
  if !tr.is_ok {
    return _err_bytes(tr.error);
  }
  let target: Int = tr.value;
  let cr = _abi_array_count_at(data, target);
  if !cr.is_ok {
    return _err_bytes(cr.error);
  }
  let count: Int = cr.value;
  if index < 0 || index >= count {
    return _err_bytes("abi: array index out of range");
  }
  let eoff = target + 32 + index * 32;
  return abi_read_word(data, eoff);
}

/// Decode a full dynamic array of uint<M> words into a Vec[Int].
/// Complexity: O(count).
pub fn abi_decode_uint_array(data: &Vec[UInt8], head_off: Int, base: Int, m: Int) -> Result[Vec[Int], Str] {
  if !abi_valid_int_bits(m) {
    return _err_ints("abi: invalid uint width " + convert.int_to_string(m));
  }
  let tr = _abi_resolve_tail(data, head_off, base);
  if !tr.is_ok {
    return _err_ints(tr.error);
  }
  let target: Int = tr.value;
  let cr = _abi_array_count_at(data, target);
  if !cr.is_ok {
    return _err_ints(cr.error);
  }
  let count: Int = cr.value;
  var out = Vec[Int].new();
  var i = 0;
  while i < count {
    let er = abi_read_word(data, target + 32 + i * 32);
    if !er.is_ok {
      return _err_ints(er.error);
    }
    let w: Vec[UInt8] = er.value;
    let dr = abi_decode_uint_word(&w, m);
    if !dr.is_ok {
      return _err_ints(dr.error);
    }
    let v: Int = dr.value;
    out.push(v);
    i = i + 1;
  }
  return _ok_ints(out);
}

// --------------------------------------------------
//  ABI: function call data
// --------------------------------------------------

/// Assemble function-call data: the caller-supplied 4-byte selector (this
/// package does not compute keccak selectors) followed by the head and tail
/// argument sections. Dynamic offset words in the head are relative to the
/// start of the argument section, i.e. `abi_call_args_offset()` bytes into
/// the assembled data.
/// Err("abi: selector must be 4 bytes").
/// Complexity: O(head + tail).
pub fn abi_encode_call(selector: &Vec[UInt8], head: &Vec[UInt8], tail: &Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  if selector.len() != 4 {
    return _err_bytes("abi: selector must be 4 bytes");
  }
  var out = Vec[UInt8].new();
  _push_all(&mut out, selector);
  _push_all(&mut out, head);
  _push_all(&mut out, tail);
  return _ok_bytes(out);
}

/// Copy of the 4-byte selector at the start of call data.
/// Err("abi: call data shorter than selector").
/// Complexity: O(1).
pub fn abi_call_selector(data: &Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  if data.len() < 4 {
    return _err_bytes("abi: call data shorter than selector");
  }
  var out = Vec[UInt8].new();
  var i = 0;
  while i < 4 {
    out.push(data[i]);
    i = i + 1;
  }
  return _ok_bytes(out);
}

/// Copy of the argument section of call data (everything after the 4-byte
/// selector).
/// Err("abi: call data shorter than selector").
/// Complexity: O(argument bytes).
pub fn abi_call_args(data: &Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  if data.len() < 4 {
    return _err_bytes("abi: call data shorter than selector");
  }
  var out = Vec[UInt8].new();
  var i = 4;
  while i < data.len() {
    out.push(data[i]);
    i = i + 1;
  }
  return _ok_bytes(out);
}

// --------------------------------------------------
//  Hex and address helpers
// --------------------------------------------------

/// Hex value (0..15) of an ASCII byte, or -1 when it is not a hex digit.
fn _hex_val(b: Int) -> Int {
  if b >= 48 && b <= 57 {
    return b - 48;
  }
  if b >= 97 && b <= 102 {
    return b - 87;
  }
  if b >= 65 && b <= 70 {
    return b - 55;
  }
  return -1;
}

/// Render bytes as a 0x-prefixed lowercase hex string with exactly two
/// digits per byte (zero-padded).
/// Complexity: O(bytes.len()).
pub fn eth_hex_bytes(data: &Vec[UInt8]) -> Str {
  return "0x" + hex.hex_encode(data);
}

/// Render a non-negative quantity as a 0x-prefixed lowercase hex string
/// zero-padded to exactly `width_bytes` bytes.
/// Err("eth: quantity is negative"), Err("eth: quantity width must be 1..32
/// bytes"), Err("eth: quantity exceeds width N bytes").
/// Complexity: O(width_bytes).
pub fn eth_hex_uint(n: Int, width_bytes: Int) -> Result[Str, Str] {
  if n < 0 {
    return _err_str("eth: quantity is negative");
  }
  if width_bytes < 1 || width_bytes > 32 {
    return _err_str("eth: quantity width must be 1..32 bytes");
  }
  if width_bytes <= 7 {
    let lim = _pow2(width_bytes * 8);
    if n >= lim {
      return _err_str("eth: quantity exceeds width " + convert.int_to_string(width_bytes) + " bytes");
    }
  }
  var out = Vec[UInt8].new();
  var k = width_bytes - 1;
  while k >= 0 {
    out.push(_be_byte(n, k));
    k = k - 1;
  }
  return _ok_str(eth_hex_bytes(&out));
}

/// Decode an address string to its 20 raw bytes. Accepts the 40 hex digits
/// with an optional 0x/0X prefix, in any letter case.
/// Err("eth: address must be 40 hex digits with optional 0x prefix"),
/// Err("eth: address contains a non-hex character").
/// Complexity: O(1).
pub fn eth_address_bytes(input: Str) -> Result[Vec[UInt8], Str] {
  let n = string.str_len(input);
  var start = 0;
  if n == 40 {
    start = 0;
  } elif n == 42 {
    let c0: UInt8 = string.byte_at(input, 0);
    let c1: UInt8 = string.byte_at(input, 1);
    let p0 = (c0 as Int) & 0xFF;
    let p1 = (c1 as Int) & 0xFF;
    if p0 != 48 {
      return _err_bytes("eth: address must be 40 hex digits with optional 0x prefix");
    }
    if p1 != 120 && p1 != 88 {
      return _err_bytes("eth: address must be 40 hex digits with optional 0x prefix");
    }
    start = 2;
  } else {
    return _err_bytes("eth: address must be 40 hex digits with optional 0x prefix");
  }
  var out = Vec[UInt8].new();
  var i = 0;
  while i < 20 {
    let ch: UInt8 = string.byte_at(input, start + i * 2);
    let cl: UInt8 = string.byte_at(input, start + i * 2 + 1);
    let hi = _hex_val((ch as Int) & 0xFF);
    let lo = _hex_val((cl as Int) & 0xFF);
    if hi < 0 || lo < 0 {
      return _err_bytes("eth: address contains a non-hex character");
    }
    out.push((hi * 16 + lo) as UInt8);
    i = i + 1;
  }
  return _ok_bytes(out);
}

/// Normalize an address string to the canonical all-lowercase 0x-prefixed
/// form, validating the 40 hex digits on the way.
///
/// EIP-55 note: the mixed-case checksum is NOT verified here. EIP-55 is
/// defined as a keccak256 hash of the lowercase address used to choose the
/// case of each hex letter; keccak is a cryptographic hash and this package
/// deliberately contains no hashing (see the module header). Callers that
/// need checksummed addresses must verify the case themselves with a
/// keccak256 implementation; this function returns the all-lowercase form,
/// which is itself a valid EIP-55 input to hash.
/// Err("eth: address must be 40 hex digits with optional 0x prefix"),
/// Err("eth: address contains a non-hex character").
/// Complexity: O(1).
pub fn eth_address_normalize(input: Str) -> Result[Str, Str] {
  let br = eth_address_bytes(input);
  if !br.is_ok {
    return _err_str(br.error);
  }
  let bytes: Vec[UInt8] = br.value;
  return _ok_str(eth_hex_bytes(&bytes));
}

/// Render 20 raw address bytes as the canonical all-lowercase 0x-prefixed
/// hex form.
/// Err("eth: address bytes must be 20 bytes").
/// Complexity: O(1).
pub fn eth_address_from_bytes(bytes: &Vec[UInt8]) -> Result[Str, Str] {
  if bytes.len() != 20 {
    return _err_str("eth: address bytes must be 20 bytes");
  }
  return _ok_str(eth_hex_bytes(bytes));
}
