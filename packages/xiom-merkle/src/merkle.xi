// XIOM -- xiom.merkle: Merkle tree and inclusion proofs over byte buffers
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Contract (full rules and error catalog in SPEC.md):
//   * Leaves are caller-supplied byte buffers, passed as one flat
//     `Vec[UInt8]` plus an `offsets` vector: leaf i is
//     data[offsets[i] .. offsets[i + 1]], so offsets.len() == leaf_count + 1.
//     Empty leaves (equal consecutive offsets) are allowed.
//   * Hashing is RFC 6962 style with SHA-256:
//       leaf hash     = SHA256(0x00 || leaf bytes)
//       internal node = SHA256(0x01 || left hash || right hash)
//     Every node hash is 32 bytes. The tree is built level by level from the
//     ordered leaves; when a level has an odd number of nodes, the last node
//     is PROMOTED unchanged to the next level -- its hash is never
//     duplicated. Promotion reproduces exactly the RFC 6962
//     split-at-the-largest-smaller-power-of-two tree shape, iteratively.
//   * The empty tree root is SHA256("") (no prefix byte), as in RFC 6962.
//   * Deviations from RFC 6962: only the section 2.1 hashing and tree-shape
//     rules are implemented. The TLS-serialized inclusion-proof framing of
//     section 2.1.1 (leaf_index, tree_size, then the audit path) is NOT
//     implemented; a proof here is a raw sibling-hash list (bottom level
//     first) plus the leaf index and the leaf count it was generated for.
//   * SHA-256 is implemented inside this module (FIPS 180-4) and is
//     INTERNAL: it is not exported as a general hash API. It is pure XIOM
//     with divisor/modulo arithmetic because v0.61.3 miscompiles bitwise
//     AND on operands with bit 31 set (see docs/COMPILER-FINDINGS.md and the
//     xiom.crc / xiom.packet notes). The stdlib alternatives were rejected:
//     xiom.crypto.sha256 is FFI-backed and xiom.crypto.sha is the legacy
//     Vec[Int] module marked do-not-use-in-new-systems.
//   * Tree representation: one flat byte buffer `hashes` holding every
//     level concatenated (level 0 = leaf hashes first) plus parallel
//     `level_sizes` metadata. No Vec[StructType] anywhere (trap 10).
//
// v0.61.3 notes that shaped this module:
//   * free functions only; no methods, no lambdas, no Vec[fn] dispatch;
//   * no Vec[StructType]; parallel Vecs stay mirror-pushed (trap 16);
//   * every UInt8 read is widened and masked: (x as Int) & 0xFF;
//   * 32-bit words stay in 0..2^32-1 using `% 4294967296` arithmetic;
//     rotations are divisor/modulo, AND is the identity
//     a AND b = (a + b - (a XOR b)) / 2, and NOT is 2^32-1 - a, so no raw
//     `& 0xFFFFFFFF` / `~` ever touches a value with bit 31 set;
//   * `&struct.field` is never passed to a `&Vec[UInt8]` parameter: hash
//     bytes are copied into local Vecs first (trap 4);
//   * in-place `h = f(h)` hash updates go through a fresh local, and
//     `&mut Int` out-params are never used (return values instead);
//   * Ok/Err are constructed only in the tiny leaf helpers below.

module xiom.merkle

use xiom.string;
use xiom.string.builder;
use xiom.convert;

// --------------------------------------------------
//  Constants
// --------------------------------------------------

// Digest length in bytes (SHA-256).
const _M_HASH_LEN: Int = 32;

// 2^32, the modulus of every 32-bit word operation.
const _M_U32_MOD: Int = 4294967296;

// Leaf and internal-node domain separation prefixes (RFC 6962).
const _M_LEAF_PREFIX: Int = 0;
const _M_NODE_PREFIX: Int = 1;

// SHA-256 initial hash values H0..H7 (FIPS 180-4).
const _M_IV0: Int = 0x6A09E667;
const _M_IV1: Int = 0xBB67AE85;
const _M_IV2: Int = 0x3C6EF372;
const _M_IV3: Int = 0xA54FF53A;
const _M_IV4: Int = 0x510E527F;
const _M_IV5: Int = 0x9B05688C;
const _M_IV6: Int = 0x1F83D9AB;
const _M_IV7: Int = 0x5BE0CD19;

// --------------------------------------------------
//  Types and Result leaves
// --------------------------------------------------

/// A bottom-up Merkle tree over ordered leaves.
///
/// `hashes` stores every level concatenated, level 0 (the leaf hashes)
/// first; each node occupies 32 bytes. `level_sizes[l]` is the number of
/// nodes at level l, so the byte offset of level l's first node is
/// 32 * (level_sizes[0] + ... + level_sizes[l - 1]). Invariant for trees
/// built by this module: hashes.len() == 32 * sum(level_sizes),
/// level_count == level_sizes.len(), and the last level has exactly one
/// node. The empty tree has leaf_count == 0, level_count == 0 and both
/// vectors empty.
pub type MerkleTree = {
  leaf_count: Int;
  level_count: Int;
  level_sizes: Vec[Int];
  hashes: Vec[UInt8];
}

/// An inclusion proof for one leaf: the sibling hash on each level from the
/// leaf up to (but excluding) the root, bottom level first, plus the leaf
/// index and the leaf count of the tree it was generated from.
///
/// `siblings` is a flat buffer of ceil(sibling_count) * 32 bytes; sibling k
/// occupies bytes [k * 32, (k + 1) * 32). Siblings that the odd-node
/// promotion rule skips are simply absent, so sibling_count depends on the
/// leaf index and the tree shape.
pub type MerkleProof = {
  leaf_index: Int;
  leaf_count: Int;
  sibling_count: Int;
  siblings: Vec[UInt8];
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

// Ok(v) for Result[MerkleTree, Str].
fn _ok_tree(v: MerkleTree) -> Result[MerkleTree, Str] {
  return Ok(v);
}

// Err(m) for Result[MerkleTree, Str].
fn _err_tree(m: Str) -> Result[MerkleTree, Str] {
  return Err(m);
}

// Ok(v) for Result[MerkleProof, Str].
fn _ok_proof(v: MerkleProof) -> Result[MerkleProof, Str] {
  return Ok(v);
}

// Err(m) for Result[MerkleProof, Str].
fn _err_proof(m: Str) -> Result[MerkleProof, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Internal arithmetic helpers
// --------------------------------------------------

// 2^p for 0 <= p <= 32, by doubling.
fn _p2(p: Int) -> Int {
  var v = 1;
  var i = 0;
  while i < p {
    v = v * 2;
    i = i + 1;
  }
  return v;
}

// Ceiling of a / b for a >= 0, b > 0 (explicit remainder form, trap 18).
fn _ceil_div(a: Int, b: Int) -> Int {
  var q = a / b;
  if a % b > 0 {
    q = q + 1;
  }
  return q;
}

// --------------------------------------------------
//  Internal SHA-256 (FIPS 180-4), pure XIOM
// --------------------------------------------------

// 32-bit rotate right: rotr(x, n) = x / 2^n + (x mod 2^n) * 2^(32-n), for
// x in 0..2^32-1 and n in 1..31. Both terms stay below 2^32.
fn _rotr32(x: Int, n: Int) -> Int {
  let q = _p2(n);
  let hi = x / q;
  let lo = x % q;
  return (hi + lo * _p2(32 - n)) % _M_U32_MOD;
}

// 32-bit logical shift right.
fn _shr32(x: Int, n: Int) -> Int {
  return x / _p2(n);
}

// 32-bit AND without a raw mask: x AND y = (x + y - (x XOR y)) / 2, which is
// exact for x, y in 0..2^32-1 and cannot overflow (max 2^33 - 2).
fn _and32(a: Int, b: Int) -> Int {
  return ((a + b) - (a ^ b)) / 2;
}

// 32-bit NOT: 2^32 - 1 - x for x in 0..2^32-1.
fn _not32(a: Int) -> Int {
  return (_M_U32_MOD - 1) - a;
}

// Ch(x, y, z) = (x AND y) XOR ((NOT x) AND z).
fn _ch32(x: Int, y: Int, z: Int) -> Int {
  return _and32(x, y) ^ _and32(_not32(x), z);
}

// Maj(x, y, z) = (x AND y) XOR (x AND z) XOR (y AND z).
fn _maj32(x: Int, y: Int, z: Int) -> Int {
  return (_and32(x, y) ^ _and32(x, z)) ^ _and32(y, z);
}

// Big Sigma0(x) = rotr(x, 2) XOR rotr(x, 13) XOR rotr(x, 22).
fn _bsig0(x: Int) -> Int {
  return (_rotr32(x, 2) ^ _rotr32(x, 13)) ^ _rotr32(x, 22);
}

// Big Sigma1(x) = rotr(x, 6) XOR rotr(x, 11) XOR rotr(x, 25).
fn _bsig1(x: Int) -> Int {
  return (_rotr32(x, 6) ^ _rotr32(x, 11)) ^ _rotr32(x, 25);
}

// Small sigma0(x) = rotr(x, 7) XOR rotr(x, 18) XOR shr(x, 3).
fn _ssig0(x: Int) -> Int {
  return (_rotr32(x, 7) ^ _rotr32(x, 18)) ^ _shr32(x, 3);
}

// Small sigma1(x) = rotr(x, 17) XOR rotr(x, 19) XOR shr(x, 10).
fn _ssig1(x: Int) -> Int {
  return (_rotr32(x, 17) ^ _rotr32(x, 19)) ^ _shr32(x, 10);
}

// The 64 SHA-256 round constants K[0..63] (FIPS 180-4), built at runtime:
// module-level const arrays are mis-materialized by v0.61.3 (see the
// xiom.crypto SHA-512 note and xiom.compress.gzip).
fn _k_table() -> Vec[Int] {
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

// One big-endian 32-bit word from 4 bytes: data[off] is the most
// significant byte. Each byte is widened and masked (trap 3).
fn _be_word(data: &Vec[UInt8], off: Int) -> Int {
  let b0 = (data[off] as Int) & 0xFF;
  let b1 = (data[off + 1] as Int) & 0xFF;
  let b2 = (data[off + 2] as Int) & 0xFF;
  let b3 = (data[off + 3] as Int) & 0xFF;
  return b0 * 16777216 + b1 * 65536 + b2 * 256 + b3;
}

// Compress one 64-byte block of `padded` at byte offset `off` into the
// 8-word state `st`, using the round constants `k`. Returns the new state as
// a fresh 8-element Vec[Int] (return values, never &mut Int out-params).
fn _compress_block(padded: &Vec[UInt8], off: Int, k: &Vec[Int], st: &Vec[Int]) -> Vec[Int] {
  // Message schedule W[0..63].
  var w = Vec[Int].new();
  var i = 0;
  while i < 16 {
    let word = _be_word(padded, off + i * 4);
    w.push(word);
    i = i + 1;
  }
  i = 16;
  while i < 64 {
    let x2 = w[i - 2];
    let x15 = w[i - 15];
    let t7 = w[i - 7];
    let t16 = w[i - 16];
    let s1 = _ssig1(x2);
    let s0 = _ssig0(x15);
    let acc1 = (s1 + t7) % _M_U32_MOD;
    let acc2 = (acc1 + s0) % _M_U32_MOD;
    w.push((acc2 + t16) % _M_U32_MOD);
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
    let sig1 = _bsig1(e);
    let ch = _ch32(e, f, g);
    var t1 = (h + sig1) % _M_U32_MOD;
    t1 = (t1 + ch) % _M_U32_MOD;
    t1 = (t1 + kj) % _M_U32_MOD;
    t1 = (t1 + wj) % _M_U32_MOD;
    let sig0 = _bsig0(a);
    let maj = _maj32(a, b, c);
    let t2 = (sig0 + maj) % _M_U32_MOD;
    let new_e = (d + t1) % _M_U32_MOD;
    let new_a = (t1 + t2) % _M_U32_MOD;
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
  out.push((st[0] + a) % _M_U32_MOD);
  out.push((st[1] + b) % _M_U32_MOD);
  out.push((st[2] + c) % _M_U32_MOD);
  out.push((st[3] + d) % _M_U32_MOD);
  out.push((st[4] + e) % _M_U32_MOD);
  out.push((st[5] + f) % _M_U32_MOD);
  out.push((st[6] + g) % _M_U32_MOD);
  out.push((st[7] + h) % _M_U32_MOD);
  return out;
}

// SHA-256 digest (32 bytes) of `data`. Handles the empty input: the padding
// is 0x80, then zeros up to byte 56 of the block, then the 64-bit
// big-endian bit length (0). Internal to this module.
fn _sha256(data: &Vec[UInt8]) -> Vec[UInt8] {
  let k = _k_table();
  var st = Vec[Int].new();
  st.push(_M_IV0);
  st.push(_M_IV1);
  st.push(_M_IV2);
  st.push(_M_IV3);
  st.push(_M_IV4);
  st.push(_M_IV5);
  st.push(_M_IV6);
  st.push(_M_IV7);
  let n = data.len();
  var padded = Vec[UInt8].new();
  var i = 0;
  while i < n {
    padded.push(data[i]);
    i = i + 1;
  }
  padded.push(128 as UInt8);
  // Total padded byte length: the smallest multiple of 64 >= n + 9.
  let total = _ceil_div(n + 9, 64) * 64;
  let zeros = total - n - 9;
  i = 0;
  while i < zeros {
    padded.push(0 as UInt8);
    i = i + 1;
  }
  // 64-bit big-endian bit length, high word first.
  let bits = n * 8;
  let lo = bits % _M_U32_MOD;
  let hi = bits / _M_U32_MOD;
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
    let next = _compress_block(&padded, off, &k, &st);
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
//  Internal byte helpers
// --------------------------------------------------

// Copy `len` bytes of `src` starting at byte `off` into a fresh Vec.
fn _copy_slice(src: &Vec[UInt8], off: Int, len: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < len {
    out.push(src[off + i]);
    i = i + 1;
  }
  return out;
}

// Append `len` bytes of `src` starting at byte `off` to `out`.
fn _append_slice(out: &mut Vec[UInt8], src: &Vec[UInt8], off: Int, len: Int) {
  var i = 0;
  while i < len {
    out.push(src[off + i]);
    i = i + 1;
  }
}

// Exact byte-vector equality.
fn _bytes_equal(a: &Vec[UInt8], b: &Vec[UInt8]) -> Bool {
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

// One byte as two lowercase hex digits.
fn _hex2(v: Int) -> Str {
  var digits = "0123456789abcdef";
  let hi = v / 16;
  let lo = v % 16;
  return string.str_slice(digits, hi, hi + 1) + string.str_slice(digits, lo, lo + 1);
}

// --------------------------------------------------
//  Internal node hashing
// --------------------------------------------------

// SHA256(0x00 || data[start..end]).
fn _leaf_hash_range(data: &Vec[UInt8], start: Int, end: Int) -> Vec[UInt8] {
  var buf = Vec[UInt8].new();
  buf.push(_M_LEAF_PREFIX as UInt8);
  var i = start;
  while i < end {
    buf.push(data[i]);
    i = i + 1;
  }
  return _sha256(&buf);
}

// SHA256(0x01 || left || right) for two 32-byte child hashes.
fn _node_hash(left: &Vec[UInt8], right: &Vec[UInt8]) -> Vec[UInt8] {
  var buf = Vec[UInt8].new();
  buf.push(_M_NODE_PREFIX as UInt8);
  var i = 0;
  while i < left.len() {
    buf.push(left[i]);
    i = i + 1;
  }
  i = 0;
  while i < right.len() {
    buf.push(right[i]);
    i = i + 1;
  }
  return _sha256(&buf);
}

// --------------------------------------------------
//  Internal tree construction and access
// --------------------------------------------------

// Empty tree: no leaves, no levels, empty buffers.
fn _empty_tree() -> MerkleTree {
  var sizes = Vec[Int].new();
  var hashes = Vec[UInt8].new();
  return MerkleTree{ leaf_count: 0; level_count: 0; level_sizes: sizes; hashes: hashes };
}

// Byte offset of level `level` inside tree.hashes. Caller guarantees
// 0 <= level <= tree.level_count.
fn _level_start(tree: &MerkleTree, level: Int) -> Int {
  var sum = 0;
  var i = 0;
  while i < level {
    let s = tree.level_sizes[i];
    sum = sum + s;
    i = i + 1;
  }
  return sum * 32;
}

// Build the tree from n 32-byte leaf hashes (flat buffer). Level by level:
// pair nodes left to right with SHA256(0x01 || l || r); when the count is
// odd, the last node is promoted unchanged. O(n) hashes, O(n) memory.
fn _build_tree(leaf_hashes: &Vec[UInt8], n: Int) -> MerkleTree {
  var hashes = Vec[UInt8].new();
  var sizes = Vec[Int].new();
  _append_slice(&mut hashes, leaf_hashes, 0, n * 32);
  sizes.push(n);
  var count = n;
  var start = 0;
  while count > 1 {
    var i = 0;
    while i + 1 < count {
      let base = start + i * 32;
      let left = _copy_slice(&hashes, base, 32);
      let right = _copy_slice(&hashes, base + 32, 32);
      let node = _node_hash(&left, &right);
      _append_slice(&mut hashes, &node, 0, 32);
      i = i + 2;
    }
    if i < count {
      // Promotion: copy the lone last node unchanged (never duplicated).
      let promo = _copy_slice(&hashes, start + i * 32, 32);
      _append_slice(&mut hashes, &promo, 0, 32);
    }
    start = start + count * 32;
    count = _ceil_div(count, 2);
    sizes.push(count);
  }
  return MerkleTree{ leaf_count: n; level_count: sizes.len(); level_sizes: sizes; hashes: hashes };
}

// --------------------------------------------------
//  Public accessors
// --------------------------------------------------

/// Digest length in bytes of the hash used by this module: 32 (SHA-256).
/// Error case: none. Complexity: O(1).
pub fn merkle_hash_len() -> Int {
  return _M_HASH_LEN;
}

/// Number of leaves of the tree (0 for the empty tree).
/// Error case: none. Complexity: O(1).
pub fn merkle_leaf_count(tree: &MerkleTree) -> Int {
  return tree.leaf_count;
}

/// Number of levels of the tree: 0 for the empty tree, otherwise one level
/// per reduction until the single root node (level 0 holds the leaves).
/// Error case: none. Complexity: O(1).
pub fn merkle_level_count(tree: &MerkleTree) -> Int {
  return tree.level_count;
}

/// Lowercase hex of an arbitrary byte buffer, two characters per byte
/// ("" for an empty buffer). No byte can render as a raw NUL.
/// Error case: none. Complexity: O(buf.len()).
pub fn merkle_hex(buf: &Vec[UInt8]) -> Str {
  var sb = builder.sb_new();
  var i = 0;
  while i < buf.len() {
    let b = (buf[i] as Int) & 0xFF;
    builder.sb_push_str(&mut sb, _hex2(b));
    i = i + 1;
  }
  return builder.sb_to_str(&sb);
}

/// SHA256(0x00 || leaf): the leaf hash of one caller-supplied byte buffer
/// (empty leaves allowed). Returns 32 bytes.
/// Error case: none. Complexity: O(leaf.len()).
pub fn merkle_leaf_hash(leaf: &Vec[UInt8]) -> Vec[UInt8] {
  return _leaf_hash_range(leaf, 0, leaf.len());
}

/// SHA256(0x01 || left || right): the hash of an internal node from its two
/// 32-byte child hashes. Returns 32 bytes.
/// Error case: Err("merkle: internal hash children must be 32 bytes each
/// (left L, right R)") when either input is not exactly 32 bytes.
/// Complexity: O(1) (one SHA-256 over 65 bytes).
pub fn merkle_internal_hash(left: &Vec[UInt8], right: &Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  if left.len() != _M_HASH_LEN || right.len() != _M_HASH_LEN {
    return _err_bytes("merkle: internal hash children must be 32 bytes each (left " + convert.int_to_string(left.len()) + ", right " + convert.int_to_string(right.len()) + ")");
  }
  return _ok_bytes(_node_hash(left, right));
}

/// Build a Merkle tree from ordered leaves given as one flat buffer plus
/// offsets: leaf i is data[offsets[i] .. offsets[i + 1]]. Offsets must be
/// non-decreasing (empty leaves are allowed: equal consecutive offsets) and
/// must end at data.len(). offsets.len() == leaf_count + 1; an empty tree is
/// data.len() == 0 with offsets == [0].
/// Params: data - concatenated leaf bytes; offsets - leaf boundary offsets.
/// Returns: Ok(tree) with leaf_count == offsets.len() - 1, or Err with a
/// message naming the offending offset (see SPEC.md for the catalog).
/// Error case: Err("merkle: offsets must be non-empty") when offsets.len()
/// == 0; Err("merkle: offsets[0] must be 0 (got V)") when the first offset
/// is not 0; Err("merkle: offsets[i]=V is below offsets[j]=W") at the first
/// decrease; Err("merkle: offsets[i]=V must equal data length L") when the
/// last offset is not data.len().
/// Complexity: O(data.len() + leaf_count) time, O(leaf_count) hashes.
pub fn merkle_tree_from_leaves(data: &Vec[UInt8], offsets: &Vec[Int]) -> Result[MerkleTree, Str] {
  let nz = offsets.len();
  if nz == 0 {
    return _err_tree("merkle: offsets must be non-empty");
  }
  let first = offsets[0];
  if first != 0 {
    return _err_tree("merkle: offsets[0] must be 0 (got " + convert.int_to_string(first) + ")");
  }
  var i = 1;
  while i < nz {
    let cur = offsets[i];
    let prev = offsets[i - 1];
    if cur < prev {
      return _err_tree("merkle: offsets[" + convert.int_to_string(i) + "]=" + convert.int_to_string(cur) + " is below offsets[" + convert.int_to_string(i - 1) + "]=" + convert.int_to_string(prev));
    }
    i = i + 1;
  }
  let last = offsets[nz - 1];
  if last != data.len() {
    return _err_tree("merkle: offsets[" + convert.int_to_string(nz - 1) + "]=" + convert.int_to_string(last) + " must equal data length " + convert.int_to_string(data.len()));
  }
  let leaf_count = nz - 1;
  if leaf_count == 0 {
    return _ok_tree(_empty_tree());
  }
  var leaf_hashes = Vec[UInt8].new();
  var li = 0;
  while li < leaf_count {
    let start = offsets[li];
    let end = offsets[li + 1];
    let h = _leaf_hash_range(data, start, end);
    _append_slice(&mut leaf_hashes, &h, 0, 32);
    li = li + 1;
  }
  return _ok_tree(_build_tree(&leaf_hashes, leaf_count));
}

/// Number of nodes at `level`: level 0 holds the leaf hashes, the last
/// level holds the single root.
/// Params: tree - the tree; level - 0..merkle_level_count(tree) - 1.
/// Returns: Ok(size) with size >= 1, or Err with a message naming the level.
/// Error case: Err("merkle: tree has no levels (empty tree)") for the empty
/// tree; Err("merkle: level L out of range 0..H") when L is outside
/// 0..level_count - 1.
/// Complexity: O(1).
pub fn merkle_level_size(tree: &MerkleTree, level: Int) -> Result[Int, Str] {
  if tree.level_count == 0 {
    return _err_int("merkle: tree has no levels (empty tree)");
  }
  if level < 0 || level >= tree.level_count {
    return _err_int("merkle: level " + convert.int_to_string(level) + " out of range 0.." + convert.int_to_string(tree.level_count - 1));
  }
  return _ok_int(tree.level_sizes[level]);
}

/// The 32-byte hash of node `index` at `level` (level 0 = leaf hashes).
/// Params: tree - the tree; level - 0..level_count - 1; index -
/// 0..merkle_level_size(tree, level) - 1.
/// Returns: Ok(32 bytes), or Err naming the level or the node.
/// Error case: Err("merkle: tree has no levels (empty tree)");
/// Err("merkle: level L out of range 0..H");
/// Err("merkle: node I out of range at level L (size S)").
/// Complexity: O(level + 32).
pub fn merkle_level_hash(tree: &MerkleTree, level: Int, index: Int) -> Result[Vec[UInt8], Str] {
  if tree.level_count == 0 {
    return _err_bytes("merkle: tree has no levels (empty tree)");
  }
  if level < 0 || level >= tree.level_count {
    return _err_bytes("merkle: level " + convert.int_to_string(level) + " out of range 0.." + convert.int_to_string(tree.level_count - 1));
  }
  let size = tree.level_sizes[level];
  if index < 0 || index >= size {
    return _err_bytes("merkle: node " + convert.int_to_string(index) + " out of range at level " + convert.int_to_string(level) + " (size " + convert.int_to_string(size) + ")");
  }
  let off = _level_start(tree, level) + index * 32;
  var out = Vec[UInt8].new();
  var i = 0;
  while i < 32 {
    out.push(tree.hashes[off + i]);
    i = i + 1;
  }
  return _ok_bytes(out);
}

/// Root hash as 32 bytes. For the empty tree this is SHA256("") (RFC 6962);
/// for every non-empty tree it is the single node of the last level.
/// Error case: none. Complexity: O(level_count + 32).
pub fn merkle_root(tree: &MerkleTree) -> Vec[UInt8] {
  if tree.leaf_count == 0 {
    let empty = Vec[UInt8].new();
    return _sha256(&empty);
  }
  let off = _level_start(tree, tree.level_count - 1);
  var out = Vec[UInt8].new();
  var i = 0;
  while i < 32 {
    out.push(tree.hashes[off + i]);
    i = i + 1;
  }
  return out;
}

/// Lowercase hex of merkle_root(tree): 64 characters for every tree.
/// Error case: none. Complexity: O(level_count).
pub fn merkle_root_hex(tree: &MerkleTree) -> Str {
  let root = merkle_root(tree);
  return merkle_hex(&root);
}

// --------------------------------------------------
//  Inclusion proofs
// --------------------------------------------------

/// Generate the inclusion proof for leaf `leaf_index`.
/// The proof lists the sibling hash of each level that contributes to the
/// path from the leaf to the root, bottom level first; levels where the
/// node is promoted (no sibling) contribute nothing.
/// Params: tree - the tree; leaf_index - 0..leaf_count - 1.
/// Returns: Ok(proof) with proof.leaf_count == tree.leaf_count.
/// Error case: Err("merkle: empty tree has no inclusion proofs") for the
/// empty tree; Err("merkle: leaf index I out of range 0..M") when I is
/// outside 0..leaf_count - 1.
/// Complexity: O(leaf_count) time (one pass over the levels), O(log n)
/// siblings of 32 bytes.
pub fn merkle_proof_generate(tree: &MerkleTree, leaf_index: Int) -> Result[MerkleProof, Str] {
  if tree.leaf_count == 0 {
    return _err_proof("merkle: empty tree has no inclusion proofs");
  }
  if leaf_index < 0 || leaf_index >= tree.leaf_count {
    return _err_proof("merkle: leaf index " + convert.int_to_string(leaf_index) + " out of range 0.." + convert.int_to_string(tree.leaf_count - 1));
  }
  var siblings = Vec[UInt8].new();
  var sibling_count = 0;
  var idx = leaf_index;
  var level = 0;
  var start = 0;
  while level < tree.level_count - 1 {
    let size = tree.level_sizes[level];
    var sib_off = -1;
    if idx % 2 == 1 {
      sib_off = start + (idx - 1) * 32;
    } else {
      if idx + 1 < size {
        sib_off = start + (idx + 1) * 32;
      }
    }
    if sib_off >= 0 {
      var i = 0;
      while i < 32 {
        siblings.push(tree.hashes[sib_off + i]);
        i = i + 1;
      }
      sibling_count = sibling_count + 1;
    }
    start = start + size * 32;
    idx = idx / 2;
    level = level + 1;
  }
  return _ok_proof(MerkleProof{ leaf_index: leaf_index; leaf_count: tree.leaf_count; sibling_count: sibling_count; siblings: siblings });
}

/// Verify an inclusion proof against a root hash.
/// Recomputes the leaf hash from `leaf`, folds it up with the proof's
/// siblings in order (left or right depending on the running index), and
/// compares the result with `root`.
/// Params: proof - the proof to verify; leaf - the claimed leaf bytes;
/// root - the claimed 32-byte root.
/// Returns: Ok(true) when the proof is structurally valid and reproduces
/// `root`; Ok(false) when it is structurally valid but does not (wrong
/// leaf, tampered sibling, wrong index for this shape, or wrong root; a
/// root that is not 32 bytes simply cannot match).
/// Error case: Err("merkle: proof leaf count L must be positive");
/// Err("merkle: proof leaf index I out of range 0..M");
/// Err("merkle: proof sibling count C is negative");
/// Err("merkle: proof siblings length N is not a multiple of 32");
/// Err("merkle: proof sibling count C does not match siblings length N").
/// Complexity: O(log n) hashes.
pub fn merkle_proof_verify(proof: &MerkleProof, leaf: &Vec[UInt8], root: &Vec[UInt8]) -> Result[Bool, Str] {
  let lc = proof.leaf_count;
  if lc <= 0 {
    return _err_bool("merkle: proof leaf count " + convert.int_to_string(lc) + " must be positive");
  }
  let li = proof.leaf_index;
  if li < 0 || li >= lc {
    return _err_bool("merkle: proof leaf index " + convert.int_to_string(li) + " out of range 0.." + convert.int_to_string(lc - 1));
  }
  let sc = proof.sibling_count;
  if sc < 0 {
    return _err_bool("merkle: proof sibling count " + convert.int_to_string(sc) + " is negative");
  }
  let slen = proof.siblings.len();
  if slen % 32 != 0 {
    return _err_bool("merkle: proof siblings length " + convert.int_to_string(slen) + " is not a multiple of 32");
  }
  if slen / 32 != sc {
    return _err_bool("merkle: proof sibling count " + convert.int_to_string(sc) + " does not match siblings length " + convert.int_to_string(slen));
  }
  if root.len() != _M_HASH_LEN {
    return _ok_bool(false);
  }
  var h = _leaf_hash_range(leaf, 0, leaf.len());
  var idx = li;
  var size = lc;
  var consumed = 0;
  while size > 1 {
    var take = 0;
    var go_right = false;
    if idx % 2 == 1 {
      take = 1;
      go_right = true;
    } else {
      if idx + 1 < size {
        take = 1;
      }
    }
    if take == 1 {
      if consumed >= sc {
        return _ok_bool(false);
      }
      var sib = Vec[UInt8].new();
      var bi = 0;
      while bi < 32 {
        sib.push(proof.siblings[consumed * 32 + bi]);
        bi = bi + 1;
      }
      if go_right {
        let nh = _node_hash(&sib, &h);
        h = nh;
      } else {
        let nh = _node_hash(&h, &sib);
        h = nh;
      }
      consumed = consumed + 1;
    }
    idx = idx / 2;
    size = _ceil_div(size, 2);
  }
  if consumed != sc {
    return _ok_bool(false);
  }
  return _ok_bool(_bytes_equal(&h, root));
}

/// Leaf index the proof was generated for.
/// Error case: none. Complexity: O(1).
pub fn merkle_proof_leaf_index(proof: &MerkleProof) -> Int {
  return proof.leaf_index;
}

/// Leaf count of the tree the proof was generated from.
/// Error case: none. Complexity: O(1).
pub fn merkle_proof_leaf_count(proof: &MerkleProof) -> Int {
  return proof.leaf_count;
}

/// Number of sibling hashes the proof carries.
/// Error case: none. Complexity: O(1).
pub fn merkle_proof_sibling_count(proof: &MerkleProof) -> Int {
  return proof.sibling_count;
}

/// Sibling hash `i` (0-based, bottom level first) as 32 bytes.
/// Params: proof - the proof; i - 0..sibling_count - 1.
/// Returns: Ok(32 bytes), or Err naming the sibling index.
/// Error case: Err("merkle: sibling index I out of range 0..M") when I is
/// outside 0..sibling_count - 1; Err("merkle: sibling I is missing from the
/// proof buffer") when the buffer is shorter than the declared count.
/// Complexity: O(32).
pub fn merkle_proof_sibling(proof: &MerkleProof, i: Int) -> Result[Vec[UInt8], Str] {
  if i < 0 || i >= proof.sibling_count {
    return _err_bytes("merkle: sibling index " + convert.int_to_string(i) + " out of range 0.." + convert.int_to_string(proof.sibling_count - 1));
  }
  if (i + 1) * 32 > proof.siblings.len() {
    return _err_bytes("merkle: sibling " + convert.int_to_string(i) + " is missing from the proof buffer");
  }
  var out = Vec[UInt8].new();
  var k = 0;
  while k < 32 {
    out.push(proof.siblings[i * 32 + k]);
    k = k + 1;
  }
  return _ok_bytes(out);
}
