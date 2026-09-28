// XIOM -- xiom.hashchain: hash-linked record chains over caller byte buffers
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Contract (full rules and error catalog in SPEC.md):
//   * A chain is a sequence of blocks. Block i carries a caller-supplied
//     payload (an arbitrary byte buffer, possibly empty) and two 32-byte
//     SHA-256 digests: the digest of the PREVIOUS block it commits to
//     (`prev_digests`) and its own digest (`digests`), which commits to that
//     previous digest and to the payload.
//   * Block 0 is the GENESIS block. Genesis rule: its prev digest is the 32
//     zero bytes. Every later block i must satisfy prev_digests[i] ==
//     digests[i - 1].
//   * Block digest: SHA256(D || prev_digest || uint64_be(payload_len) ||
//     payload), with D the ASCII domain separator "xiom.hashchain.v1.block".
//     The length field makes the preimage unambiguous for every payload
//     split; the domain separator keeps these digests out of every other
//     SHA-256 use.
//   * Storage is parallel Vec fields only (no Vec[StructType]): payloads are
//     flattened into payload_bytes with payload_offsets (count + 1 entries,
//     offsets[0] == 0, non-decreasing, offsets[count] == payload_bytes.len()).
//     Block i's payload is payload_bytes[offsets[i] .. offsets[i + 1]] and
//     may be empty. prev_digests and digests hold count * 32 bytes each;
//     block i's digest lives at [i * 32, (i + 1) * 32).
//   * chain_verify re-checks the structural invariants, the genesis rule, the
//     prev links and every recomputed digest, and reports the FIRST broken
//     index in a precise error message.
//   * Determinism: a block digest depends only on the previous digest and the
//     payload bytes; no clock, no IO, no randomness. Same inputs -> same
//     digests.
//   * SHA-256 is implemented inside this module (FIPS 180-4) as the private
//     pure-XIOM `_hc_sha256`, mirroring the KAT-verified private `_sha256` of
//     packages/xiom-merkle/src/merkle.xi. The stdlib xiom.crypto.sha256 is
//     FFI-backed and fails to link from packages at v0.62.0/v0.62.1
//     (undefined symbol: xiom_sha256_hash), so it cannot be used here. This
//     module contains no FFI, performs no IO and reads no clock; see SPEC.md
//     ("Digest construction").
//
// v0.62.0 notes that shape this module:
//   * free functions only; no methods, no lambdas, no Vec[fn] dispatch;
//   * no Vec[StructType]; parallel Vecs are mirror-pushed (trap 16);
//   * every UInt8 read is widened and masked: (x as Int) & 0xFF;
//   * struct fields are bound to locals before they are passed by reference
//     (trap 4); in-place updates go through fresh locals;
//   * Ok/Err are constructed only in the tiny leaf helpers below;
//   * `log` is never used as a function name.

module xiom.hashchain

use xiom.string;
use xiom.convert;

// --------------------------------------------------
//  Constants
// --------------------------------------------------

// Digest length in bytes (SHA-256).
const _HC_DIGEST: Int = 32;

// ASCII domain separator mixed into every block digest preimage.
const _HC_DOMAIN: Str = "xiom.hashchain.v1.block";

// 2^32, used to split a 64-bit payload length into two 32-bit words.
const _HC_U32_MOD: Int = 4294967296;

// SHA-256 initial hash values H0..H7 (FIPS 180-4).
const _HC_IV0: Int = 0x6A09E667;
const _HC_IV1: Int = 0xBB67AE85;
const _HC_IV2: Int = 0x3C6EF372;
const _HC_IV3: Int = 0xA54FF53A;
const _HC_IV4: Int = 0x510E527F;
const _HC_IV5: Int = 0x9B05688C;
const _HC_IV6: Int = 0x1F83D9AB;
const _HC_IV7: Int = 0x5BE0CD19;

// --------------------------------------------------
//  Types and Result leaves
// --------------------------------------------------

/// An append-only chain of hash-linked blocks.
///
/// `count` is the number of blocks (0 for the empty chain). `payload_offsets`
/// holds count + 1 boundaries into `payload_bytes`: block i's payload is
/// payload_bytes[payload_offsets[i] .. payload_offsets[i + 1]], and empty
/// payloads are allowed (equal consecutive offsets). `prev_digests` and
/// `digests` each hold count * 32 bytes; block i occupies bytes
/// [i * 32, (i + 1) * 32) of both. Invariants for chains built by this
/// module: payload_offsets[0] == 0, offsets are non-decreasing,
/// payload_offsets[count] == payload_bytes.len(), and the digest buffers are
/// exactly count * 32 bytes. The empty chain has count == 0,
/// payload_offsets == [0] and three empty buffers.
pub type HashChain = {
  count: Int;
  payload_offsets: Vec[Int];
  payload_bytes: Vec[UInt8];
  prev_digests: Vec[UInt8];
  digests: Vec[UInt8];
}

// Ok(v) for Result[Vec[UInt8], Str].
fn _ok_bytes(v: Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  return Ok(v);
}

// Err(m) for Result[Vec[UInt8], Str].
fn _err_bytes(m: Str) -> Result[Vec[UInt8], Str] {
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

// Ok(v) for Result[Bool, Str].
fn _ok_bool(v: Bool) -> Result[Bool, Str] {
  return Ok(v);
}

// Err(m) for Result[Bool, Str].
fn _err_bool(m: Str) -> Result[Bool, Str] {
  return Err(m);
}

// Ok(v) for Result[HashChain, Str].
fn _ok_chain(v: HashChain) -> Result[HashChain, Str] {
  return Ok(v);
}

// Err(m) for Result[HashChain, Str].
fn _err_chain(m: Str) -> Result[HashChain, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Internal byte helpers
// --------------------------------------------------

// Fresh 32-byte all-zero digest (the genesis prev digest, and the link of the
// first block appended to the empty chain).
fn _hc_zero_digest() -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < _HC_DIGEST {
    v.push(0 as UInt8);
    i = i + 1;
  }
  return v;
}

// Copy `len` bytes of `src` starting at byte `off` into a fresh Vec.
fn _hc_copy_slice(src: &Vec[UInt8], off: Int, len: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < len {
    out.push(src[off + i]);
    i = i + 1;
  }
  return out;
}

// Append `len` bytes of `src` starting at byte `off` to `out`.
fn _hc_append_slice(out: &mut Vec[UInt8], src: &Vec[UInt8], off: Int, len: Int) {
  var i = 0;
  while i < len {
    out.push(src[off + i]);
    i = i + 1;
  }
}

// Copy an Int vector (used to mirror the parallel payload offsets).
fn _hc_copy_ints(src: &Vec[Int]) -> Vec[Int] {
  var out = Vec[Int].new();
  var i = 0;
  while i < src.len() {
    out.push(src[i]);
    i = i + 1;
  }
  return out;
}

// Exact byte-vector equality (all reads widened and masked, trap 3).
fn _hc_bytes_equal(a: &Vec[UInt8], b: &Vec[UInt8]) -> Bool {
  if a.len() != b.len() {
    return false;
  }
  var i = 0;
  while i < a.len() {
    let x = (a[i] as Int) & 0xFF;
    let y = (b[i] as Int) & 0xFF;
    if x != y {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// True when the 32 bytes of `d` at offset `off` are all zero.
fn _hc_is_zero_digest(d: &Vec[UInt8], off: Int) -> Bool {
  var i = 0;
  while i < _HC_DIGEST {
    let b = (d[off + i] as Int) & 0xFF;
    if b != 0 {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// The ASCII bytes of _HC_DOMAIN as a fresh Vec (Str -> bytes bridge).
fn _hc_domain_bytes() -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < _HC_DOMAIN.len() {
    v.push(string.byte_at(_HC_DOMAIN, i));
    i = i + 1;
  }
  return v;
}

// Push `v` (>= 0) as 8 big-endian bytes (high 32-bit word first), trap 18.
fn _hc_push_u64be(out: &mut Vec[UInt8], v: Int) {
  let hi = v / _HC_U32_MOD;
  let lo = v % _HC_U32_MOD;
  out.push(((hi / 16777216) % 256) as UInt8);
  out.push(((hi / 65536) % 256) as UInt8);
  out.push(((hi / 256) % 256) as UInt8);
  out.push((hi % 256) as UInt8);
  out.push(((lo / 16777216) % 256) as UInt8);
  out.push(((lo / 65536) % 256) as UInt8);
  out.push(((lo / 256) % 256) as UInt8);
  out.push((lo % 256) as UInt8);
}

// One nibble (0..15) as a lowercase hex character.
fn _hc_hex_digit(v: Int) -> Str {
  let digits = "0123456789abcdef";
  return string.str_slice(digits, v, v + 1);
}

// --------------------------------------------------
//  Internal SHA-256 (FIPS 180-4), pure XIOM
// --------------------------------------------------
//
// Mirror of the private _sha256 in packages/xiom-merkle/src/merkle.xi,
// adapted from v0.61.3 to the v0.62.x compiler and kept private. 32-bit words
// stay in 0..2^32-1 using `% 4294967296` arithmetic: rotations are
// divisor/modulo, AND is the identity a AND b = (a + b - (a XOR b)) / 2 and
// NOT is 2^32-1 - a, so no raw `& 0xFFFFFFFF` / `~` ever touches a value with
// bit 31 set (v0.62.x trap 3/13).

// 2^p for 0 <= p <= 32, by doubling.
fn _hc_p2(p: Int) -> Int {
  var v = 1;
  var i = 0;
  while i < p {
    v = v * 2;
    i = i + 1;
  }
  return v;
}

// Ceiling of a / b for a >= 0, b > 0 (explicit remainder form, trap 18).
fn _hc_ceil_div(a: Int, b: Int) -> Int {
  var q = a / b;
  if a % b > 0 {
    q = q + 1;
  }
  return q;
}

// 32-bit rotate right: rotr(x, n) = x / 2^n + (x mod 2^n) * 2^(32-n), for
// x in 0..2^32-1 and n in 1..31. Both terms stay below 2^32.
fn _hc_rotr32(x: Int, n: Int) -> Int {
  let q = _hc_p2(n);
  let hi = x / q;
  let lo = x % q;
  return (hi + lo * _hc_p2(32 - n)) % _HC_U32_MOD;
}

// 32-bit logical shift right.
fn _hc_shr32(x: Int, n: Int) -> Int {
  return x / _hc_p2(n);
}

// 32-bit AND without a raw mask: x AND y = (x + y - (x XOR y)) / 2, which is
// exact for x, y in 0..2^32-1 and cannot overflow (max 2^33 - 2).
fn _hc_and32(a: Int, b: Int) -> Int {
  return ((a + b) - (a ^ b)) / 2;
}

// 32-bit NOT: 2^32 - 1 - x for x in 0..2^32-1.
fn _hc_not32(a: Int) -> Int {
  return (_HC_U32_MOD - 1) - a;
}

// Ch(x, y, z) = (x AND y) XOR ((NOT x) AND z).
fn _hc_ch32(x: Int, y: Int, z: Int) -> Int {
  return _hc_and32(x, y) ^ _hc_and32(_hc_not32(x), z);
}

// Maj(x, y, z) = (x AND y) XOR (x AND z) XOR (y AND z).
fn _hc_maj32(x: Int, y: Int, z: Int) -> Int {
  return (_hc_and32(x, y) ^ _hc_and32(x, z)) ^ _hc_and32(y, z);
}

// Big Sigma0(x) = rotr(x, 2) XOR rotr(x, 13) XOR rotr(x, 22).
fn _hc_bsig0(x: Int) -> Int {
  return (_hc_rotr32(x, 2) ^ _hc_rotr32(x, 13)) ^ _hc_rotr32(x, 22);
}

// Big Sigma1(x) = rotr(x, 6) XOR rotr(x, 11) XOR rotr(x, 25).
fn _hc_bsig1(x: Int) -> Int {
  return (_hc_rotr32(x, 6) ^ _hc_rotr32(x, 11)) ^ _hc_rotr32(x, 25);
}

// Small sigma0(x) = rotr(x, 7) XOR rotr(x, 18) XOR shr(x, 3).
fn _hc_ssig0(x: Int) -> Int {
  return (_hc_rotr32(x, 7) ^ _hc_rotr32(x, 18)) ^ _hc_shr32(x, 3);
}

// Small sigma1(x) = rotr(x, 17) XOR rotr(x, 19) XOR shr(x, 10).
fn _hc_ssig1(x: Int) -> Int {
  return (_hc_rotr32(x, 17) ^ _hc_rotr32(x, 19)) ^ _hc_shr32(x, 10);
}

// The 64 SHA-256 round constants K[0..63] (FIPS 180-4), built at runtime:
// module-level const arrays are mis-materialized by the toolchain (see the
// xiom.crypto SHA-512 note and xiom.compress.gzip).
fn _hc_k_table() -> Vec[Int] {
  var k = Vec[Int].new();
  k.push(0x428A2F98);
  k.push(0x71374491);
  k.push(0xB5C0FBCF);
  k.push(0xE9B5DBA5);
  k.push(0x3956C25B);
  k.push(0x59F111F1);
  k.push(0x923F82A4);
  k.push(0xAB1C5ED5);
  k.push(0xD807AA98);
  k.push(0x12835B01);
  k.push(0x243185BE);
  k.push(0x550C7DC3);
  k.push(0x72BE5D74);
  k.push(0x80DEB1FE);
  k.push(0x9BDC06A7);
  k.push(0xC19BF174);
  k.push(0xE49B69C1);
  k.push(0xEFBE4786);
  k.push(0x0FC19DC6);
  k.push(0x240CA1CC);
  k.push(0x2DE92C6F);
  k.push(0x4A7484AA);
  k.push(0x5CB0A9DC);
  k.push(0x76F988DA);
  k.push(0x983E5152);
  k.push(0xA831C66D);
  k.push(0xB00327C8);
  k.push(0xBF597FC7);
  k.push(0xC6E00BF3);
  k.push(0xD5A79147);
  k.push(0x06CA6351);
  k.push(0x14292967);
  k.push(0x27B70A85);
  k.push(0x2E1B2138);
  k.push(0x4D2C6DFC);
  k.push(0x53380D13);
  k.push(0x650A7354);
  k.push(0x766A0ABB);
  k.push(0x81C2C92E);
  k.push(0x92722C85);
  k.push(0xA2BFE8A1);
  k.push(0xA81A664B);
  k.push(0xC24B8B70);
  k.push(0xC76C51A3);
  k.push(0xD192E819);
  k.push(0xD6990624);
  k.push(0xF40E3585);
  k.push(0x106AA070);
  k.push(0x19A4C116);
  k.push(0x1E376C08);
  k.push(0x2748774C);
  k.push(0x34B0BCB5);
  k.push(0x391C0CB3);
  k.push(0x4ED8AA4A);
  k.push(0x5B9CCA4F);
  k.push(0x682E6FF3);
  k.push(0x748F82EE);
  k.push(0x78A5636F);
  k.push(0x84C87814);
  k.push(0x8CC70208);
  k.push(0x90BEFFFA);
  k.push(0xA4506CEB);
  k.push(0xBEF9A3F7);
  k.push(0xC67178F2);
  return k;
}

// One big-endian 32-bit word from 4 bytes: data[off] is the most significant
// byte. Each byte is widened and masked (trap 3).
fn _hc_be_word(data: &Vec[UInt8], off: Int) -> Int {
  let b0 = (data[off] as Int) & 0xFF;
  let b1 = (data[off + 1] as Int) & 0xFF;
  let b2 = (data[off + 2] as Int) & 0xFF;
  let b3 = (data[off + 3] as Int) & 0xFF;
  return b0 * 16777216 + b1 * 65536 + b2 * 256 + b3;
}

// Compress one 64-byte block of `padded` at byte offset `off` into the 8-word
// state `st`, using the round constants `k`. Returns the new state as a fresh
// 8-element Vec[Int] (return values, never &mut Int out-params).
fn _hc_compress_block(padded: &Vec[UInt8], off: Int, k: &Vec[Int], st: &Vec[Int]) -> Vec[Int] {
  // Message schedule W[0..63].
  var w = Vec[Int].new();
  var i = 0;
  while i < 16 {
    let word = _hc_be_word(padded, off + i * 4);
    w.push(word);
    i = i + 1;
  }
  i = 16;
  while i < 64 {
    let x2 = w[i - 2];
    let x15 = w[i - 15];
    let t7 = w[i - 7];
    let t16 = w[i - 16];
    let s1 = _hc_ssig1(x2);
    let s0 = _hc_ssig0(x15);
    let acc1 = (s1 + t7) % _HC_U32_MOD;
    let acc2 = (acc1 + s0) % _HC_U32_MOD;
    w.push((acc2 + t16) % _HC_U32_MOD);
    i = i + 1;
  }
  // Working variables.
  var a = st[0];
  var b = st[1];
  var c = st[2];
  var d = st[3];
  var e = st[4];
  var f = st[5];
  var g = st[6];
  var h = st[7];
  var j = 0;
  while j < 64 {
    let kj = k[j];
    let wj = w[j];
    let sig1 = _hc_bsig1(e);
    let ch = _hc_ch32(e, f, g);
    var t1 = (h + sig1) % _HC_U32_MOD;
    t1 = (t1 + ch) % _HC_U32_MOD;
    t1 = (t1 + kj) % _HC_U32_MOD;
    t1 = (t1 + wj) % _HC_U32_MOD;
    let sig0 = _hc_bsig0(a);
    let maj = _hc_maj32(a, b, c);
    let t2 = (sig0 + maj) % _HC_U32_MOD;
    let new_e = (d + t1) % _HC_U32_MOD;
    let new_a = (t1 + t2) % _HC_U32_MOD;
    h = g;
    g = f;
    f = e;
    e = new_e;
    d = c;
    c = b;
    b = a;
    a = new_a;
    j = j + 1;
  }
  var out = Vec[Int].new();
  out.push((st[0] + a) % _HC_U32_MOD);
  out.push((st[1] + b) % _HC_U32_MOD);
  out.push((st[2] + c) % _HC_U32_MOD);
  out.push((st[3] + d) % _HC_U32_MOD);
  out.push((st[4] + e) % _HC_U32_MOD);
  out.push((st[5] + f) % _HC_U32_MOD);
  out.push((st[6] + g) % _HC_U32_MOD);
  out.push((st[7] + h) % _HC_U32_MOD);
  return out;
}

// SHA-256 digest (32 bytes) of `data`. Handles the empty input: the padding
// is 0x80, then zeros up to byte 56 of the block, then the 64-bit big-endian
// bit length (0). Internal to this module.
fn _hc_sha256(data: &Vec[UInt8]) -> Vec[UInt8] {
  let k = _hc_k_table();
  var st = Vec[Int].new();
  st.push(_HC_IV0);
  st.push(_HC_IV1);
  st.push(_HC_IV2);
  st.push(_HC_IV3);
  st.push(_HC_IV4);
  st.push(_HC_IV5);
  st.push(_HC_IV6);
  st.push(_HC_IV7);
  let n = data.len();
  var padded = Vec[UInt8].new();
  var i = 0;
  while i < n {
    padded.push(data[i]);
    i = i + 1;
  }
  padded.push(128 as UInt8);
  // Total padded byte length: the smallest multiple of 64 >= n + 9.
  let total = _hc_ceil_div(n + 9, 64) * 64;
  let zeros = total - n - 9;
  i = 0;
  while i < zeros {
    padded.push(0 as UInt8);
    i = i + 1;
  }
  // 64-bit big-endian bit length, high word first.
  let bits = n * 8;
  let lo = bits % _HC_U32_MOD;
  let hi = bits / _HC_U32_MOD;
  padded.push(((hi / 16777216) % 256) as UInt8);
  padded.push(((hi / 65536) % 256) as UInt8);
  padded.push(((hi / 256) % 256) as UInt8);
  padded.push((hi % 256) as UInt8);
  padded.push(((lo / 16777216) % 256) as UInt8);
  padded.push(((lo / 65536) % 256) as UInt8);
  padded.push(((lo / 256) % 256) as UInt8);
  padded.push((lo % 256) as UInt8);
  // Block loop.
  var off = 0;
  while off < total {
    let next = _hc_compress_block(&padded, off, &k, &st);
    st = next;
    off = off + 64;
  }
  var out = Vec[UInt8].new();
  var wi = 0;
  while wi < 8 {
    let v = st[wi];
    out.push(((v / 16777216) % 256) as UInt8);
    out.push(((v / 65536) % 256) as UInt8);
    out.push(((v / 256) % 256) as UInt8);
    out.push((v % 256) as UInt8);
    wi = wi + 1;
  }
  return out;
}

// --------------------------------------------------
//  Internal digest construction
// --------------------------------------------------

// SHA256(D || prev || uint64_be(payload.len()) || payload). `prev` must be
// exactly 32 bytes; public callers go through chain_compute_digest, which
// validates it.
fn _hc_block_digest(prev: &Vec[UInt8], payload: &Vec[UInt8]) -> Vec[UInt8] {
  var buf = Vec[UInt8].new();
  let dom = _hc_domain_bytes();
  _hc_append_slice(&mut buf, &dom, 0, dom.len());
  _hc_append_slice(&mut buf, prev, 0, _HC_DIGEST);
  _hc_push_u64be(&mut buf, payload.len());
  _hc_append_slice(&mut buf, payload, 0, payload.len());
  return _hc_sha256(&buf);
}

// --------------------------------------------------
//  Internal structural checks
// --------------------------------------------------

// Problem with `offsets` for a payload buffer of `data_len` bytes, or "" when
// the offsets are valid. One catalog for chain_from_payloads and chain_verify.
fn _hc_offset_problem(offsets: &Vec[Int], data_len: Int) -> Str {
  let n = offsets.len();
  if n == 0 {
    return "hashchain: payload_offsets must be non-empty";
  }
  let first = offsets[0];
  if first != 0 {
    return "hashchain: payload_offsets[0] must be 0 (got " + convert.int_to_string(first) + ")";
  }
  var i = 1;
  while i < n {
    let cur = offsets[i];
    let pre = offsets[i - 1];
    if cur < pre {
      return "hashchain: payload_offsets[" + convert.int_to_string(i) + "]=" + convert.int_to_string(cur) + " is below payload_offsets[" + convert.int_to_string(i - 1) + "]=" + convert.int_to_string(pre);
    }
    i = i + 1;
  }
  let last = offsets[n - 1];
  if last != data_len {
    return "hashchain: payload_offsets[" + convert.int_to_string(n - 1) + "]=" + convert.int_to_string(last) + " must equal payload bytes length " + convert.int_to_string(data_len);
  }
  return "";
}

// Problem with the chain structure, or "" when it satisfies every invariant
// chain_verify needs before the per-block checks. Reads only lengths, so it is
// safe on malformed chains.
fn _hc_structural_problem(chain: &HashChain) -> Str {
  let n = chain.count;
  if n < 0 {
    return "hashchain: chain count " + convert.int_to_string(n) + " is negative";
  }
  let ol = chain.payload_offsets.len();
  if ol != n + 1 {
    return "hashchain: payload_offsets length " + convert.int_to_string(ol) + " must equal count + 1 = " + convert.int_to_string(n + 1);
  }
  let pvl = chain.prev_digests.len();
  if pvl != n * _HC_DIGEST {
    return "hashchain: prev_digests length " + convert.int_to_string(pvl) + " must equal count * 32 = " + convert.int_to_string(n * _HC_DIGEST);
  }
  let dl = chain.digests.len();
  if dl != n * _HC_DIGEST {
    return "hashchain: digests length " + convert.int_to_string(dl) + " must equal count * 32 = " + convert.int_to_string(n * _HC_DIGEST);
  }
  let offs = chain.payload_offsets;
  let pl = chain.payload_bytes.len();
  return _hc_offset_problem(&offs, pl);
}

// --------------------------------------------------
//  Internal bounded readers (need a valid structure)
// --------------------------------------------------

// Copy the 32 bytes of block `i`'s stored digest. Caller guarantees the
// structural invariants (see _hc_structural_problem).
fn _hc_digest_at(chain: &HashChain, i: Int) -> Vec[UInt8] {
  let src = chain.digests;
  return _hc_copy_slice(&src, i * _HC_DIGEST, _HC_DIGEST);
}

// Copy the 32 bytes of block `i`'s stored prev digest. Same precondition.
fn _hc_prev_at(chain: &HashChain, i: Int) -> Vec[UInt8] {
  let src = chain.prev_digests;
  return _hc_copy_slice(&src, i * _HC_DIGEST, _HC_DIGEST);
}

// Copy block `i`'s payload bytes. Same precondition.
fn _hc_payload_at(chain: &HashChain, i: Int) -> Vec[UInt8] {
  let offs = chain.payload_offsets;
  let start = offs[i];
  let end = offs[i + 1];
  let src = chain.payload_bytes;
  return _hc_copy_slice(&src, start, end - start);
}

// --------------------------------------------------
//  Public API -- construction and shape
// --------------------------------------------------

/// Digest length in bytes of every block digest: 32 (SHA-256).
/// Error case: none. Complexity: O(1).
pub fn chain_digest_size() -> Int {
  return _HC_DIGEST;
}

/// The empty chain: count 0, no blocks, payload_offsets == [0]. The first
/// chain_append turns it into a chain holding the genesis block.
/// Error case: none. Complexity: O(1).
pub fn chain_new() -> HashChain {
  var offs = Vec[Int].new();
  offs.push(0);
  var pay = Vec[UInt8].new();
  var pv = Vec[UInt8].new();
  var dg = Vec[UInt8].new();
  return HashChain{ count: 0; payload_offsets: offs; payload_bytes: pay; prev_digests: pv; digests: dg };
}

/// Number of blocks in the chain (0 for the empty chain).
/// Error case: none. Complexity: O(1).
pub fn chain_len(chain: &HashChain) -> Int {
  return chain.count;
}

/// True when the chain holds no blocks (the state before the genesis block).
/// Error case: none. Complexity: O(1).
pub fn chain_is_empty(chain: &HashChain) -> Bool {
  return chain.count <= 0;
}

/// Append one block carrying `payload` (possibly empty) and return the new
/// chain; the input chain is not modified. On the empty chain this creates
/// the GENESIS block: block 0's prev digest is the 32 zero bytes. Every later
/// block links prev_digests[new] = digests[count - 1]. The result satisfies
/// the structural invariants when the input did.
/// Error case: none (the payload bytes are copied). A malformed input chain
/// that is missing its last digest falls back to the zero prev digest, so the
/// resulting chain fails chain_verify instead of crashing.
/// Complexity: O(chain bytes + payload.len()), one SHA-256.
pub fn chain_append(chain: &HashChain, payload: &Vec[UInt8]) -> HashChain {
  let n = chain.count;
  let pl = payload.len();
  let offs_in = chain.payload_offsets;
  let pay_in = chain.payload_bytes;
  let pv_in = chain.prev_digests;
  let dg_in = chain.digests;
  var offs = _hc_copy_ints(&offs_in);
  var pay = _hc_copy_slice(&pay_in, 0, pay_in.len());
  var pv = _hc_copy_slice(&pv_in, 0, pv_in.len());
  var dg = _hc_copy_slice(&dg_in, 0, dg_in.len());
  var prev = Vec[UInt8].new();
  if n <= 0 {
    prev = _hc_zero_digest();
  } else {
    let dl = dg_in.len();
    if dl >= n * _HC_DIGEST {
      prev = _hc_copy_slice(&dg_in, (n - 1) * _HC_DIGEST, _HC_DIGEST);
    } else {
      prev = _hc_zero_digest();
    }
  }
  let d = _hc_block_digest(&prev, payload);
  _hc_append_slice(&mut pv, &prev, 0, _HC_DIGEST);
  _hc_append_slice(&mut dg, &d, 0, _HC_DIGEST);
  _hc_append_slice(&mut pay, payload, 0, pl);
  let new_end = pay.len();
  offs.push(new_end);
  return HashChain{ count: n + 1; payload_offsets: offs; payload_bytes: pay; prev_digests: pv; digests: dg };
}

/// Build a chain from ordered payloads given as one flat buffer plus offsets:
/// payload i is data[offsets[i] .. offsets[i + 1]]. Offsets must be
/// non-decreasing (empty payloads are allowed: equal consecutive offsets) and
/// must end at data.len(). offsets.len() == block_count + 1; an empty chain is
/// data.len() == 0 with offsets == [0]. Block 0 is the genesis block (prev
/// digest == 32 zero bytes); later blocks link the digest of block i - 1.
/// Params: data - concatenated payload bytes; offsets - payload boundaries.
/// Returns: Ok(chain) with count == offsets.len() - 1, or Err naming the
/// offending offset (see SPEC.md for the catalog).
/// Error case: Err("hashchain: payload_offsets must be non-empty");
/// Err("hashchain: payload_offsets[0] must be 0 (got V)");
/// Err("hashchain: payload_offsets[i]=V is below payload_offsets[j]=W");
/// Err("hashchain: payload_offsets[n]=V must equal payload bytes length L").
/// Complexity: O(data.len() + block_count), one SHA-256 per block.
pub fn chain_from_payloads(data: &Vec[UInt8], offsets: &Vec[Int]) -> Result[HashChain, Str] {
  let op = _hc_offset_problem(offsets, data.len());
  if op.len() > 0 {
    return _err_chain(op);
  }
  let count = offsets.len() - 1;
  var offs = _hc_copy_ints(offsets);
  var pay = _hc_copy_slice(data, 0, data.len());
  var pv = Vec[UInt8].new();
  var dg = Vec[UInt8].new();
  var i = 0;
  while i < count {
    let start = offsets[i];
    let end = offsets[i + 1];
    var prev = Vec[UInt8].new();
    if i == 0 {
      prev = _hc_zero_digest();
    } else {
      prev = _hc_copy_slice(&dg, (i - 1) * _HC_DIGEST, _HC_DIGEST);
    }
    let payload = _hc_copy_slice(data, start, end - start);
    let d = _hc_block_digest(&prev, &payload);
    _hc_append_slice(&mut pv, &prev, 0, _HC_DIGEST);
    _hc_append_slice(&mut dg, &d, 0, _HC_DIGEST);
    i = i + 1;
  }
  return _ok_chain(HashChain{ count: count; payload_offsets: offs; payload_bytes: pay; prev_digests: pv; digests: dg });
}

// --------------------------------------------------
//  Public API -- digest
// --------------------------------------------------

/// Recompute the digest a block with previous digest `prev_digest` and
/// payload `payload` must carry: SHA256(D || prev_digest ||
/// uint64_be(payload.len()) || payload) with D = "xiom.hashchain.v1.block".
/// The genesis block uses the 32 zero bytes as prev_digest.
/// Params: prev_digest - 32 bytes; payload - arbitrary bytes (possibly empty).
/// Returns: Ok(32 bytes).
/// Error case: Err("hashchain: prev digest must be 32 bytes (got N)").
/// Complexity: O(prev_digest.len() + payload.len()).
pub fn chain_compute_digest(prev_digest: &Vec[UInt8], payload: &Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  let pl = prev_digest.len();
  if pl != _HC_DIGEST {
    return _err_bytes("hashchain: prev digest must be 32 bytes (got " + convert.int_to_string(pl) + ")");
  }
  return _ok_bytes(_hc_block_digest(prev_digest, payload));
}

// --------------------------------------------------
//  Public API -- verification
// --------------------------------------------------

/// Verify the whole chain and report the FIRST problem. Checks, in order:
/// (1) the structural invariants (count, parallel vector lengths, offsets);
/// (2) the genesis rule for block 0 (prev digest == 32 zero bytes);
/// (3) every prev link prev_digests[i] == digests[i - 1];
/// (4) every stored digest against the digest recomputed from the stored prev
///     digest and payload.
/// Params: chain - the chain to verify.
/// Returns: Ok(true) when every check passes (the empty chain included); Err
/// with a message naming the first broken block and the failed check.
/// Error case: Err("hashchain: chain count C is negative");
/// Err("hashchain: payload_offsets length L must equal count + 1 = N");
/// Err("hashchain: prev_digests length L must equal count * 32 = N");
/// Err("hashchain: digests length L must equal count * 32 = N");
/// the payload_offsets catalog of chain_from_payloads;
/// Err("hashchain: block 0 prev digest must be the 32 zero bytes (genesis rule)");
/// Err("hashchain: block I prev link broken (prev digest mismatch)");
/// Err("hashchain: block I digest mismatch (payload or stored digest tampered)").
/// Complexity: O(chain bytes), one SHA-256 per block.
pub fn chain_verify(chain: &HashChain) -> Result[Bool, Str] {
  let sp = _hc_structural_problem(chain);
  if sp.len() > 0 {
    return _err_bool(sp);
  }
  let n = chain.count;
  var i = 0;
  while i < n {
    let prev = _hc_prev_at(chain, i);
    if i == 0 {
      if !_hc_is_zero_digest(&prev, 0) {
        return _err_bool("hashchain: block 0 prev digest must be the 32 zero bytes (genesis rule)");
      }
    } else {
      let linked = _hc_digest_at(chain, i - 1);
      if !_hc_bytes_equal(&prev, &linked) {
        return _err_bool("hashchain: block " + convert.int_to_string(i) + " prev link broken (prev digest mismatch)");
      }
    }
    let payload = _hc_payload_at(chain, i);
    let want = _hc_block_digest(&prev, &payload);
    let have = _hc_digest_at(chain, i);
    if !_hc_bytes_equal(&want, &have) {
      return _err_bool("hashchain: block " + convert.int_to_string(i) + " digest mismatch (payload or stored digest tampered)");
    }
    i = i + 1;
  }
  return _ok_bool(true);
}

// --------------------------------------------------
//  Public API -- block access and traversal
// --------------------------------------------------

/// Stored digest of block `index` as 32 bytes. chain_compute_digest
/// recomputes the expected value from a previous digest and a payload.
/// Error case: Err("hashchain: block index I out of range (chain is empty)")
/// when the chain has no blocks; Err("hashchain: block index I out of range
/// 0..M (count C)") when I is outside 0..count - 1;
/// Err("hashchain: digests length L is too short for block I") on a malformed
/// chain.
/// Complexity: O(32).
pub fn chain_block_digest(chain: &HashChain, index: Int) -> Result[Vec[UInt8], Str] {
  let n = chain.count;
  if n <= 0 {
    return _err_bytes("hashchain: block index " + convert.int_to_string(index) + " out of range (chain is empty)");
  }
  if index < 0 || index >= n {
    return _err_bytes("hashchain: block index " + convert.int_to_string(index) + " out of range 0.." + convert.int_to_string(n - 1) + " (count " + convert.int_to_string(n) + ")");
  }
  let dl = chain.digests.len();
  if (index + 1) * _HC_DIGEST > dl {
    return _err_bytes("hashchain: digests length " + convert.int_to_string(dl) + " is too short for block " + convert.int_to_string(index));
  }
  let src = chain.digests;
  return _ok_bytes(_hc_copy_slice(&src, index * _HC_DIGEST, _HC_DIGEST));
}

/// Prev digest block `index` commits to as 32 bytes (the 32 zero bytes for the
/// genesis block of a valid chain).
/// Error case: the same out-of-range and too-short messages as
/// chain_block_digest, with "prev_digests" in place of "digests".
/// Complexity: O(32).
pub fn chain_block_prev(chain: &HashChain, index: Int) -> Result[Vec[UInt8], Str] {
  let n = chain.count;
  if n <= 0 {
    return _err_bytes("hashchain: block index " + convert.int_to_string(index) + " out of range (chain is empty)");
  }
  if index < 0 || index >= n {
    return _err_bytes("hashchain: block index " + convert.int_to_string(index) + " out of range 0.." + convert.int_to_string(n - 1) + " (count " + convert.int_to_string(n) + ")");
  }
  let pvl = chain.prev_digests.len();
  if (index + 1) * _HC_DIGEST > pvl {
    return _err_bytes("hashchain: prev_digests length " + convert.int_to_string(pvl) + " is too short for block " + convert.int_to_string(index));
  }
  let src = chain.prev_digests;
  return _ok_bytes(_hc_copy_slice(&src, index * _HC_DIGEST, _HC_DIGEST));
}

/// Payload bytes of block `index` as a fresh buffer (possibly empty).
/// Error case: Err("hashchain: block index I out of range (chain is empty)");
/// Err("hashchain: block index I out of range 0..M (count C)");
/// Err("hashchain: payload_offsets length L is too short for block I");
/// Err("hashchain: payload offsets are malformed for block I (start S, end E,
/// bytes L)").
/// Complexity: O(payload length).
pub fn chain_block_payload(chain: &HashChain, index: Int) -> Result[Vec[UInt8], Str] {
  let n = chain.count;
  if n <= 0 {
    return _err_bytes("hashchain: block index " + convert.int_to_string(index) + " out of range (chain is empty)");
  }
  if index < 0 || index >= n {
    return _err_bytes("hashchain: block index " + convert.int_to_string(index) + " out of range 0.." + convert.int_to_string(n - 1) + " (count " + convert.int_to_string(n) + ")");
  }
  let ol = chain.payload_offsets.len();
  if ol < index + 2 {
    return _err_bytes("hashchain: payload_offsets length " + convert.int_to_string(ol) + " is too short for block " + convert.int_to_string(index));
  }
  let start = chain.payload_offsets[index];
  let end = chain.payload_offsets[index + 1];
  let pl = chain.payload_bytes.len();
  if start < 0 || end < start || end > pl {
    return _err_bytes("hashchain: payload offsets are malformed for block " + convert.int_to_string(index) + " (start " + convert.int_to_string(start) + ", end " + convert.int_to_string(end) + ", bytes " + convert.int_to_string(pl) + ")");
  }
  let src = chain.payload_bytes;
  return _ok_bytes(_hc_copy_slice(&src, start, end - start));
}

/// Length in bytes of block `index`'s payload (0 for an empty payload).
/// Error case: the same messages as chain_block_payload.
/// Complexity: O(1).
pub fn chain_block_len(chain: &HashChain, index: Int) -> Result[Int, Str] {
  let n = chain.count;
  if n <= 0 {
    return _err_int("hashchain: block index " + convert.int_to_string(index) + " out of range (chain is empty)");
  }
  if index < 0 || index >= n {
    return _err_int("hashchain: block index " + convert.int_to_string(index) + " out of range 0.." + convert.int_to_string(n - 1) + " (count " + convert.int_to_string(n) + ")");
  }
  let ol = chain.payload_offsets.len();
  if ol < index + 2 {
    return _err_int("hashchain: payload_offsets length " + convert.int_to_string(ol) + " is too short for block " + convert.int_to_string(index));
  }
  let start = chain.payload_offsets[index];
  let end = chain.payload_offsets[index + 1];
  let pl = chain.payload_bytes.len();
  if start < 0 || end < start || end > pl {
    return _err_int("hashchain: payload offsets are malformed for block " + convert.int_to_string(index) + " (start " + convert.int_to_string(start) + ", end " + convert.int_to_string(end) + ", bytes " + convert.int_to_string(pl) + ")");
  }
  return _ok_int(end - start);
}

/// Index of the last block (0 for a one-block chain). The tip is the block
/// every later append links.
/// Error case: Err("hashchain: chain has no tip (count C)") when C <= 0.
/// Complexity: O(1).
pub fn chain_tip_index(chain: &HashChain) -> Result[Int, Str] {
  let n = chain.count;
  if n <= 0 {
    return _err_int("hashchain: chain has no tip (count " + convert.int_to_string(n) + ")");
  }
  return _ok_int(n - 1);
}

/// Digest of the last block as 32 bytes (the chain's tip digest).
/// Error case: Err("hashchain: chain has no tip (count C)") when C <= 0; the
/// chain_block_digest errors otherwise.
/// Complexity: O(32).
pub fn chain_tip_digest(chain: &HashChain) -> Result[Vec[UInt8], Str] {
  let n = chain.count;
  if n <= 0 {
    return _err_bytes("hashchain: chain has no tip (count " + convert.int_to_string(n) + ")");
  }
  return chain_block_digest(chain, n - 1);
}

/// Index of the first block whose payload equals `payload` byte for byte, or
/// -1 when no block matches (also -1 for the empty chain). A malformed offset
/// table stops the scan and reports -1, so the function never reads out of
/// bounds. First match in block order wins.
/// Error case: none. Complexity: O(chain payload bytes).
pub fn chain_index_of(chain: &HashChain, payload: &Vec[UInt8]) -> Int {
  let n = chain.count;
  let pl = payload.len();
  let plb = chain.payload_bytes.len();
  let ol = chain.payload_offsets.len();
  var i = 0;
  while i < n {
    if ol < i + 2 {
      return -1;
    }
    let start = chain.payload_offsets[i];
    let end = chain.payload_offsets[i + 1];
    if start < 0 || end < start || end > plb {
      return -1;
    }
    if end - start == pl {
      var same = true;
      var k = 0;
      while k < pl {
        let x = (chain.payload_bytes[start + k] as Int) & 0xFF;
        let y = (payload[k] as Int) & 0xFF;
        if x != y {
          same = false;
        }
        k = k + 1;
      }
      if same {
        return i;
      }
    }
    i = i + 1;
  }
  return -1;
}

/// Lowercase hex of an arbitrary byte buffer, two characters per byte ("" for
/// an empty buffer). No byte can render as a raw NUL.
/// Error case: none. Complexity: O(buf.len()).
pub fn chain_hex(buf: &Vec[UInt8]) -> Str {
  var out = "";
  var i = 0;
  while i < buf.len() {
    let b = (buf[i] as Int) & 0xFF;
    out = out + _hc_hex_digit(b / 16) + _hc_hex_digit(b % 16);
    i = i + 1;
  }
  return out;
}
