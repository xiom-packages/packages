// XIOM -- xiom.bloom: Bloom filter over a flat byte buffer
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Contract (see SPEC.md for the full definition):
//   * A BloomFilter is (m, k, bits): m bits stored in ceil(m/8) bytes of a
//     flat Vec[UInt8]. Bit j lives in bits[j / 8] at position j % 8, least
//     significant bit first; the high padding bits of the last byte are
//     always zero.
//   * insert/contains derive k probe indexes from two 32-bit hashes with
//     double hashing: index_i = (h1 + i * h2) mod m for i in 0..k-1. Hash
//     values are reduced mod m with floor semantics, so negative Int
//     arguments are accepted and mapped into 0..m-1.
//   * The two stable integer hashes are bloom_hash1 (FNV-1a 32-bit over the
//     UTF-8 bytes of a Str) and bloom_hash2 (a distinct multiplicative
//     mixing hash over the same bytes). Both are non-cryptographic: a
//     membership answer of true is probabilistic and can be a false
//     positive. False negatives are impossible for values inserted through
//     this API.
//   * bloom_fp_permille estimates the current false-positive rate in
//     permille (tenths of a percent): 1000 * (X / m)^k, where X is the
//     number of set bits. The fixed-point evaluation is documented in
//     SPEC.md; it is an approximation of (1 - e^(-kn/m))^k, not an exact
//     bound.
//   * Serialization v1 is an 11-byte header plus payload: [0] version = 1,
//     [1..5) m as u32 little-endian, [5..7) k as u16 little-endian,
//     [7..11) payload byte length as u32 little-endian, then exactly
//     ceil(m/8) payload bytes. Decoding validates every field strictly.
//   * union is exact. intersection is the bitwise AND of two equal-shape
//     filters and only approximates the intersection of the two key sets:
//     it can report false positives for keys that were in neither input.
//
// v0.61.3 notes that shaped this module:
//   * Free functions only; no methods, no lambdas, no Vec[StructType].
//   * Every raw byte read from a Vec[UInt8] is widened with
//     `(x as Int) & 0xFF` before arithmetic or comparison.
//   * Bit access is arithmetic: powers of two are built by doubling and bit
//     positions are read with division/remainder, so no shift operator and
//     no bitwise AND on values with bit 31 set is ever used.
//   * 32-bit multiplies go through _mul32, which splits the operands into
//     16-bit halves; a raw 32x32 product can exceed the signed 64-bit Int,
//     the split form cannot.
//   * Ok/Err are constructed only in the tiny leaf helpers below.

module xiom.bloom

use xiom.string;

// --------------------------------------------------
//  Constants
// --------------------------------------------------

// Maximum number of bits a filter may declare (2^30 bits = 128 MiB).
const _BL_MAX_BITS: Int = 1073741824;

// Maximum number of derived hashes (probes) per filter.
const _BL_MAX_HASHES: Int = 1024;

// Serialization format version emitted and accepted by this module.
const _BL_VERSION: Int = 1;

// Serialization header length in bytes.
const _BL_HEADER_LEN: Int = 11;

// 2^32, the modulus of both 32-bit hashes.
const _BL_U32_MOD: Int = 4294967296;

// FNV-1a 32-bit offset basis (0x811C9DC5).
const _BL_FNV_OFFSET: Int = 2166136261;

// FNV-1a 32-bit prime (0x01000193).
const _BL_FNV_PRIME: Int = 16777619;

// Seed of the mixing hash (0x9E3779B9, the Knuth golden-ratio constant).
const _BL_MIX_SEED: Int = 2654435761;

// Finalizer multiplier of the mixing hash (0x85EBCA6B).
const _BL_MIX_PRIME: Int = 2246822519;

// --------------------------------------------------
//  Types and Result leaves
// --------------------------------------------------

/// Bloom filter with m bits and k derived hashes.
///
/// Fields are implementation details; construct through bloom_new or
/// bloom_from_bytes and mutate through the free functions below.
/// Invariant for filters built by this module: bits.len() == ceil(m / 8),
/// 0 < m <= bloom_max_bits(), 0 < k <= bloom_max_hashes(), and every bit at
/// position >= m (the padding bits of the last byte) is zero.
pub type BloomFilter = {
  m: Int;
  k: Int;
  bits: Vec[UInt8];
}

// Ok(v) for Result[BloomFilter, Str].
fn _ok_filter(v: BloomFilter) -> Result[BloomFilter, Str] {
  return Ok(v);
}

// Err(m) for Result[BloomFilter, Str].
fn _err_filter(m: Str) -> Result[BloomFilter, Str] {
  return Err(m);
}

// Ok(v) for Result[Int, Str].
fn _ok_int(v: Int) -> Result[Int, Str] {
  return Ok(v);
}

// Err(m) for Result[Int, Str].
fn _err_int(m: Str) -> Result[Int, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Internal arithmetic
// --------------------------------------------------

// 2^p for 0 <= p <= 7 (the bit positions inside one byte), by doubling.
fn _p2(p: Int) -> Int {
  var v = 1;
  var i = 0;
  while i < p {
    v = v * 2;
    i = i + 1;
  }
  return v;
}

// x mod m forced into 0..m-1 for any Int x and m > 0; negative x wraps
// upward, so this is floor-mod regardless of the platform remainder sign.
fn _mod_floor(x: Int, m: Int) -> Int {
  var r = x % m;
  if r < 0 {
    r = r + m;
  }
  return r;
}

// (a * b) mod 2^32 for 0 <= a, b < 2^32, computed exactly. The product is
// split into 16-bit halves: a raw 32x32 product can reach ~2^64 and overflow
// the signed 64-bit Int, while every intermediate below stays below 2^34.
fn _mul32(a: Int, b: Int) -> Int {
  let ahi = a / 65536;
  let alo = a % 65536;
  let bhi = b / 65536;
  let blo = b % 65536;
  let mid1 = (ahi * blo) % 65536;
  let mid2 = (alo * bhi) % 65536;
  let low = alo * blo;
  return (mid1 * 65536 + mid2 * 65536 + low) % _BL_U32_MOD;
}

// Number of payload bytes for m bits: ceil(m / 8). Callers pass m > 0.
fn _byte_len(m: Int) -> Int {
  return (m + 7) / 8;
}

// Deterministic size-validation message for (m, k): "" when the pair is
// valid, otherwise the first failing rule's message. Rule order: m <= 0,
// k <= 0, m above cap, k above cap.
fn _size_error(m: Int, k: Int) -> Str {
  if m <= 0 {
    return "bloom: m must be positive";
  }
  if k <= 0 {
    return "bloom: k must be positive";
  }
  if m > _BL_MAX_BITS {
    return "bloom: m exceeds maximum";
  }
  if k > _BL_MAX_HASHES {
    return "bloom: k exceeds maximum";
  }
  return "";
}

// Zero-filled filter of a pre-validated (m, k) pair. Complexity: O(m).
fn _make_filter(m: Int, k: Int) -> BloomFilter {
  var bits = Vec[UInt8].new();
  let n = _byte_len(m);
  var i = 0;
  while i < n {
    bits.push(0 as UInt8);
    i = i + 1;
  }
  return BloomFilter{ m: m; k: k; bits: bits };
}

// --------------------------------------------------
//  Internal hash construction
// --------------------------------------------------

// FNV-1a 32-bit over the UTF-8 bytes of `s`: h = offset_basis; for each byte
// b: h = (h XOR b) * prime mod 2^32. Result in 0..2^32-1.
fn _fnv1a32(s: Str) -> Int {
  var h = _BL_FNV_OFFSET;
  var i = 0;
  while i < s.len() {
    let b = (string.byte_at(s, i) as Int) & 0xFF;
    h = h ^ b;
    h = _mul32(h, _BL_FNV_PRIME);
    i = i + 1;
  }
  return h;
}

// Mixing hash 32-bit over the UTF-8 bytes of `s`, distinct from FNV-1a:
// h = seed; for each byte b: h = (h + b + 1) * seed mod 2^32; then two
// finalizer rounds h = (h + h / 65536) * prime mod 2^32, where the last
// multiplication of each round uses _mul32. Result in 0..2^32-1.
fn _mix32(s: Str) -> Int {
  var h = _BL_MIX_SEED;
  var i = 0;
  while i < s.len() {
    let b = (string.byte_at(s, i) as Int) & 0xFF;
    h = (h + b + 1) % _BL_U32_MOD;
    h = _mul32(h, _BL_MIX_SEED);
    i = i + 1;
  }
  h = (h + h / 65536) % _BL_U32_MOD;
  h = _mul32(h, _BL_MIX_PRIME);
  h = (h + h / 65536) % _BL_U32_MOD;
  return h;
}

// --------------------------------------------------
//  Internal bit storage
// --------------------------------------------------

// True when bit `idx` of the filter is set. `idx` must be in 0..m-1.
fn _bit_is_set(bf: &BloomFilter, idx: Int) -> Bool {
  let byte = idx / 8;
  let p = idx % 8;
  let x = (bf.bits[byte] as Int) & 0xFF;
  if (x / _p2(p)) % 2 == 1 {
    return true;
  }
  return false;
}

// Set bit `idx` of the filter. `idx` must be in 0..m-1.
fn _set_bit(bf: &mut BloomFilter, idx: Int) {
  let byte = idx / 8;
  let p = idx % 8;
  var x = (bf.bits[byte] as Int) & 0xFF;
  if (x / _p2(p)) % 2 == 0 {
    bf.bits[byte] = (x + _p2(p)) as UInt8;
  }
}

// Bit p (0..7) of a widened byte value, as 0 or 1.
fn _byte_bit(x: Int, p: Int) -> Int {
  return (x / _p2(p)) % 2;
}

// OR of two widened byte values, bit by bit. Complexity: O(8).
fn _or_byte(x: Int, y: Int) -> Int {
  var out = 0;
  var p = 0;
  while p < 8 {
    if _byte_bit(x, p) == 1 || _byte_bit(y, p) == 1 {
      out = out + _p2(p);
    }
    p = p + 1;
  }
  return out;
}

// AND of two widened byte values, bit by bit. Complexity: O(8).
fn _and_byte(x: Int, y: Int) -> Int {
  var out = 0;
  var p = 0;
  while p < 8 {
    if _byte_bit(x, p) == 1 && _byte_bit(y, p) == 1 {
      out = out + _p2(p);
    }
    p = p + 1;
  }
  return out;
}

// --------------------------------------------------
//  Parameters and accessors
// --------------------------------------------------

/// Largest m a filter may declare: 1073741824 (2^30 bits = 128 MiB of
/// storage). Error case: none. Complexity: O(1).
pub fn bloom_max_bits() -> Int {
  return _BL_MAX_BITS;
}

/// Largest k a filter may declare: 1024 probes. Error case: none.
/// Complexity: O(1).
pub fn bloom_max_hashes() -> Int {
  return _BL_MAX_HASHES;
}

/// Serialization format version emitted by bloom_to_bytes and accepted by
/// bloom_from_bytes: 1. Error case: none. Complexity: O(1).
pub fn bloom_version() -> Int {
  return _BL_VERSION;
}

/// Serialization header length in bytes: 11. Error case: none.
/// Complexity: O(1).
pub fn bloom_header_len() -> Int {
  return _BL_HEADER_LEN;
}

/// Create a zeroed filter with m bits and k derived hashes.
/// Params: m - number of bits, 1..bloom_max_bits(); k - number of probes,
/// 1..bloom_max_hashes().
/// Returns: Ok(filter) with all bits clear, or Err with the first failing
/// rule's message (see bloom_from_bytes for the message catalog).
/// Error case: Err("bloom: m must be positive") when m <= 0;
/// Err("bloom: k must be positive") when k <= 0;
/// Err("bloom: m exceeds maximum") when m > bloom_max_bits();
/// Err("bloom: k exceeds maximum") when k > bloom_max_hashes().
/// Complexity: O(m) time and memory.
pub fn bloom_new(m: Int, k: Int) -> Result[BloomFilter, Str] {
  let msg = _size_error(m, k);
  if msg.len() > 0 {
    return _err_filter(msg);
  }
  return _ok_filter(_make_filter(m, k));
}

/// Number of bits of the filter. Error case: none. Complexity: O(1).
pub fn bloom_m(bf: &BloomFilter) -> Int {
  return bf.m;
}

/// Number of derived hashes (probes) per lookup. Error case: none.
/// Complexity: O(1).
pub fn bloom_k(bf: &BloomFilter) -> Int {
  return bf.k;
}

/// Payload length in bytes: ceil(m / 8). Error case: none.
/// Complexity: O(1).
pub fn bloom_byte_len(bf: &BloomFilter) -> Int {
  return bf.bits.len();
}

// --------------------------------------------------
//  Hashes
// --------------------------------------------------

/// FNV-1a 32-bit hash of `s` over its UTF-8 bytes, as a non-negative Int in
/// 0..2^32-1. offset_basis = 2166136261, prime = 16777619; empty input
/// yields the offset basis. This is a checksum, not a cryptographic hash.
/// Params: s - the text to hash (empty allowed).
/// Error case: none. Complexity: O(s.len()).
pub fn bloom_hash1(s: Str) -> Int {
  return _fnv1a32(s);
}

/// Mixing hash 32-bit of `s` over its UTF-8 bytes, as a non-negative Int in
/// 0..2^32-1. Independent of bloom_hash1: seed = 2654435761, per byte
/// h = (h + b + 1) * seed mod 2^32, then two multiplicative finalizer
/// rounds. Empty input yields a fixed value (the seed plus finalization),
/// not the FNV offset basis. Non-cryptographic.
/// Params: s - the text to hash (empty allowed).
/// Error case: none. Complexity: O(s.len()).
pub fn bloom_hash2(s: Str) -> Int {
  return _mix32(s);
}

// --------------------------------------------------
//  Insert, query, clear
// --------------------------------------------------

/// Derive the i-th probe index of the pair (h1, h2): (h1 + i * h2) mod m,
/// with both hashes reduced mod m using floor semantics first (negative
/// Int arguments are accepted).
/// Params: bf - the filter (only m and k are read); h1 - first hash;
/// h2 - second hash; i - probe ordinal, 0..k-1.
/// Returns: Ok(index) with index in 0..m-1.
/// Error case: Err("bloom: hash index out of range") when i < 0 or i >= k.
/// Complexity: O(1).
pub fn bloom_derive_index(bf: &BloomFilter, h1: Int, h2: Int, i: Int) -> Result[Int, Str] {
  if i < 0 || i >= bf.k {
    return _err_int("bloom: hash index out of range");
  }
  let a = _mod_floor(h1, bf.m);
  let b = _mod_floor(h2, bf.m);
  return _ok_int(_mod_floor(a + i * b, bf.m));
}

/// Insert the value represented by the hash pair (h1, h2).
/// Params: bf - the filter; h1, h2 - the two 32-bit hash values (negative
/// values are accepted and wrapped mod m).
/// Sets the k bits at bloom_derive_index(bf, h1, h2, i) for i in 0..k-1.
/// Re-inserting an already present pair changes nothing. When h2 mod m == 0
/// every probe hits index h1 mod m; the two built-in hashes are independent
/// enough that this is rare, and callers passing explicit hashes control it.
/// Error case: none. Complexity: O(k).
pub fn bloom_insert(bf: &mut BloomFilter, h1: Int, h2: Int) {
  let a = _mod_floor(h1, bf.m);
  let b = _mod_floor(h2, bf.m);
  var cur = a;
  var i = 0;
  while i < bf.k {
    _set_bit(bf, cur);
    cur = _mod_floor(cur + b, bf.m);
    i = i + 1;
  }
}

/// Membership query for the value represented by the hash pair (h1, h2).
/// Params: bf - the filter; h1, h2 - the two 32-bit hash values.
/// Returns: true when all k probe bits are set, false when any is clear.
/// true is probabilistic (false positives are possible); false is exact for
/// values inserted through this API (no false negatives).
/// Error case: none. Complexity: O(k).
pub fn bloom_contains(bf: &BloomFilter, h1: Int, h2: Int) -> Bool {
  let a = _mod_floor(h1, bf.m);
  let b = _mod_floor(h2, bf.m);
  var cur = a;
  var i = 0;
  while i < bf.k {
    if !_bit_is_set(bf, cur) {
      return false;
    }
    cur = _mod_floor(cur + b, bf.m);
    i = i + 1;
  }
  return true;
}

/// Hash `s` with both built-in hashes and insert it.
/// Params: bf - the filter; s - the value (hashed over its UTF-8 bytes).
/// Equivalent to bloom_insert(bf, bloom_hash1(s), bloom_hash2(s)).
/// Error case: none. Complexity: O(s.len() + k).
pub fn bloom_add_str(bf: &mut BloomFilter, s: Str) {
  bloom_insert(bf, _fnv1a32(s), _mix32(s));
}

/// Hash `s` with both built-in hashes and query membership.
/// Params: bf - the filter; s - the value (hashed over its UTF-8 bytes).
/// Returns: bloom_contains(bf, bloom_hash1(s), bloom_hash2(s)); true is
/// probabilistic.
/// Error case: none. Complexity: O(s.len() + k).
pub fn bloom_has_str(bf: &BloomFilter, s: Str) -> Bool {
  return bloom_contains(bf, _fnv1a32(s), _mix32(s));
}

/// Clear every bit of the filter. m and k are preserved.
/// Params: bf - the filter.
/// Error case: none. Complexity: O(m).
pub fn bloom_clear(bf: &mut BloomFilter) {
  var i = 0;
  while i < bf.bits.len() {
    bf.bits[i] = 0 as UInt8;
    i = i + 1;
  }
}

// --------------------------------------------------
//  Statistics
// --------------------------------------------------

/// Number of set bits among the m valid bits.
/// Params: bf - the filter.
/// Returns: the population count of bits 0..m-1 (padding bits are always
/// zero in filters built by this module). Complexity: O(m).
pub fn bloom_set_count(bf: &BloomFilter) -> Int {
  var count = 0;
  var i = 0;
  while i < bf.bits.len() {
    let x = (bf.bits[i] as Int) & 0xFF;
    var p = 0;
    while p < 8 {
      count = count + _byte_bit(x, p);
      p = p + 1;
    }
    i = i + 1;
  }
  return count;
}

/// True when no bit is set. Params: bf - the filter. Error case: none.
/// Complexity: O(m).
pub fn bloom_is_empty(bf: &BloomFilter) -> Bool {
  return bloom_set_count(bf) == 0;
}

/// Estimated false-positive rate in permille: 1000 * (X / m)^k, where X is
/// bloom_set_count(bf). This is the standard set-bit estimate of
/// (1 - e^(-kn/m))^k and is an approximation, not an exact bound.
///
/// Integer evaluation: p = floor(10^6 * X / m) is the fill ratio in
/// millionths; acc starts at 10^6 and is multiplied by p / 10^6 (truncating)
/// k times; the result is acc / 1000 rounded to nearest. The final value is
/// in 0..1000.
/// Params: bf - the filter.
/// Error case: none. Complexity: O(m + k).
pub fn bloom_fp_permille(bf: &BloomFilter) -> Int {
  let x = bloom_set_count(bf);
  if x == 0 {
    return 0;
  }
  let p = (1000000 * x) / bf.m;
  var acc = 1000000;
  var i = 0;
  while i < bf.k {
    acc = (acc * p) / 1000000;
    i = i + 1;
  }
  return (acc + 500) / 1000;
}

/// Structural equality: same m, same k and the same payload bytes.
/// Params: a, b - the filters to compare.
/// Returns: true when the two filters have identical shape and content.
/// Error case: none. Complexity: O(m).
pub fn bloom_equal(a: &BloomFilter, b: &BloomFilter) -> Bool {
  if a.m != b.m {
    return false;
  }
  if a.k != b.k {
    return false;
  }
  if a.bits.len() != b.bits.len() {
    return false;
  }
  var i = 0;
  while i < a.bits.len() {
    let x = (a.bits[i] as Int) & 0xFF;
    let y = (b.bits[i] as Int) & 0xFF;
    if x != y {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// --------------------------------------------------
//  Serialization
// --------------------------------------------------

// Append v (0..2^32-1) as four little-endian bytes.
fn _write_u32_le(out: &mut Vec[UInt8], v: Int) {
  out.push((v % 256) as UInt8);
  out.push(((v / 256) % 256) as UInt8);
  out.push(((v / 65536) % 256) as UInt8);
  out.push(((v / 16777216) % 256) as UInt8);
}

// Append v (0..65535) as two little-endian bytes.
fn _write_u16_le(out: &mut Vec[UInt8], v: Int) {
  out.push((v % 256) as UInt8);
  out.push(((v / 256) % 256) as UInt8);
}

// Read four little-endian bytes at `off` as an Int in 0..2^32-1. The caller
// guarantees off + 4 <= data.len().
fn _read_u32_le(data: &Vec[UInt8], off: Int) -> Int {
  let b0 = (data[off] as Int) & 0xFF;
  let b1 = (data[off + 1] as Int) & 0xFF;
  let b2 = (data[off + 2] as Int) & 0xFF;
  let b3 = (data[off + 3] as Int) & 0xFF;
  return b0 + b1 * 256 + b2 * 65536 + b3 * 16777216;
}

// Read two little-endian bytes at `off` as an Int in 0..65535. The caller
// guarantees off + 2 <= data.len().
fn _read_u16_le(data: &Vec[UInt8], off: Int) -> Int {
  let b0 = (data[off] as Int) & 0xFF;
  let b1 = (data[off + 1] as Int) & 0xFF;
  return b0 + b1 * 256;
}

/// Serialize the filter into a fresh byte buffer (format version 1).
/// Layout: [0] version = 1; [1..5) m as u32 little-endian; [5..7) k as u16
/// little-endian; [7..11) payload byte length as u32 little-endian; then
/// ceil(m/8) payload bytes, bit j of the filter in payload[j / 8] at bit
/// position j % 8 (least significant bit first). Total length is
/// bloom_header_len() + bloom_byte_len(bf); padding bits are zero.
/// Params: bf - the filter to serialize.
/// Error case: none. Complexity: O(m).
pub fn bloom_to_bytes(bf: &BloomFilter) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  out.push(_BL_VERSION as UInt8);
  _write_u32_le(&mut out, bf.m);
  _write_u16_le(&mut out, bf.k);
  _write_u32_le(&mut out, bf.bits.len());
  var i = 0;
  while i < bf.bits.len() {
    out.push(bf.bits[i]);
    i = i + 1;
  }
  return out;
}

/// Parse a buffer produced by bloom_to_bytes (format version 1).
/// Params: data - the byte buffer to parse.
/// Returns: Ok(filter) for a buffer that passes every check below.
/// Error case: Err("bloom: truncated buffer") when the buffer is shorter
/// than the 11-byte header or shorter than header + declared payload;
/// Err("bloom: unsupported version") when byte 0 is not 1;
/// Err("bloom: m must be positive") when the encoded m is 0;
/// Err("bloom: k must be positive") when the encoded k is 0;
/// Err("bloom: m exceeds maximum") when the encoded m exceeds
/// bloom_max_bits(); Err("bloom: k exceeds maximum") when the encoded k
/// exceeds bloom_max_hashes(); Err("bloom: byte length mismatch") when the
/// declared payload length differs from ceil(m / 8);
/// Err("bloom: trailing bytes") when the buffer is longer than
/// header + declared payload; Err("bloom: padding not zero") when a bit at
/// position >= m is set.
/// Complexity: O(data.len()).
pub fn bloom_from_bytes(data: &Vec[UInt8]) -> Result[BloomFilter, Str] {
  if data.len() < _BL_HEADER_LEN {
    return _err_filter("bloom: truncated buffer");
  }
  let version = (data[0] as Int) & 0xFF;
  if version != _BL_VERSION {
    return _err_filter("bloom: unsupported version");
  }
  let m = _read_u32_le(data, 1);
  let k = _read_u16_le(data, 5);
  let declared = _read_u32_le(data, 7);
  let msg = _size_error(m, k);
  if msg.len() > 0 {
    return _err_filter(msg);
  }
  let need = _byte_len(m);
  if declared != need {
    return _err_filter("bloom: byte length mismatch");
  }
  let total = _BL_HEADER_LEN + need;
  if data.len() < total {
    return _err_filter("bloom: truncated buffer");
  }
  if data.len() > total {
    return _err_filter("bloom: trailing bytes");
  }
  let used = m % 8;
  if used != 0 {
    let last = (data[_BL_HEADER_LEN + need - 1] as Int) & 0xFF;
    if last / _p2(used) != 0 {
      return _err_filter("bloom: padding not zero");
    }
  }
  var bf = _make_filter(m, k);
  var i = 0;
  while i < need {
    bf.bits[i] = data[_BL_HEADER_LEN + i];
    i = i + 1;
  }
  return _ok_filter(bf);
}

// --------------------------------------------------
//  Set algebra
// --------------------------------------------------

/// Union of two filters with equal shape: the exact bitwise OR.
/// Any value inserted into either input is reported by the result, and the
/// result's set of inserted values is exactly the union of the inputs' (the
/// false-positive rate can only grow).
/// Params: a, b - filters with the same m and the same k.
/// Returns: Ok(new filter) with a.m == b.m and a.k == b.k.
/// Error case: Err("bloom: union size mismatch") when a.m != b.m or
/// a.k != b.k.
/// Complexity: O(m).
pub fn bloom_union(a: &BloomFilter, b: &BloomFilter) -> Result[BloomFilter, Str] {
  if a.m != b.m || a.k != b.k {
    return _err_filter("bloom: union size mismatch");
  }
  var out = _make_filter(a.m, a.k);
  var i = 0;
  while i < a.bits.len() {
    let x = (a.bits[i] as Int) & 0xFF;
    let y = (b.bits[i] as Int) & 0xFF;
    out.bits[i] = _or_byte(x, y) as UInt8;
    i = i + 1;
  }
  return _ok_filter(out);
}

/// Intersection of two filters with equal shape: the bitwise AND.
///
/// This is APPROXIMATE as a set operation: a bit is kept only when both
/// inputs had it set, so every value inserted into both inputs is still
/// reported, but keys that share the k probe positions with the intersection
/// become additional false positives. The result is a valid filter of the
/// same shape, not the exact intersection of the two key sets.
/// Params: a, b - filters with the same m and the same k.
/// Returns: Ok(new filter) with a.m == b.m and a.k == b.k.
/// Error case: Err("bloom: intersection size mismatch") when a.m != b.m or
/// a.k != b.k.
/// Complexity: O(m).
pub fn bloom_intersection(a: &BloomFilter, b: &BloomFilter) -> Result[BloomFilter, Str] {
  if a.m != b.m || a.k != b.k {
    return _err_filter("bloom: intersection size mismatch");
  }
  var out = _make_filter(a.m, a.k);
  var i = 0;
  while i < a.bits.len() {
    let x = (a.bits[i] as Int) & 0xFF;
    let y = (b.bits[i] as Int) & 0xFF;
    out.bits[i] = _and_byte(x, y) as UInt8;
    i = i + 1;
  }
  return _ok_filter(out);
}
