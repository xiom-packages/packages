// XIOM -- xiom.aws.base: pure-XIOM SHA-256 / HMAC-SHA-256 / hex primitives
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// The v0.62.2 stdlib exposes xiom.crypto.sha256 / hmac_sha256, but linking a
// package against them fails with `undefined symbol: xiom_sha256_hash` (probe
// 2026-10-02 via scripts/port.ps1: both the xiom.crypto facade and
// xiom.crypto.hash fail at link time). This module therefore hand-rolls the
// primitives in-package, following the xiom.saml precedent. They are pinned by
// NIST FIPS 180-4 SHA-256 KATs (abc, empty, 448-bit) and RFC 4231 HMAC-SHA-256
// cases 1/2/3/6 (including a key longer than the 64-byte block) in
// tests/test_conformance.xi.
//
// v0.62.2 discipline: free functions only, no match, no &mut scalar
// parameters, masked byte widening, bounded loops, no Vec[StructType].

module xiom.aws.base

use xiom.string;
use xiom.string.builder;

// --------------------------------------------------
//  Bytes
// --------------------------------------------------

/// Raw UTF-8 bytes of a Str (one byte per string index).
pub fn aws_bytes_of_str(s: Str) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  let n = s.len();
  var i = 0;
  while i < n {
    out.push(string.byte_at(s, i));
    i = i + 1;
  }
  return out;
}

/// `n` copies of the byte `b & 0xFF`.
pub fn aws_bytes_repeat(b: Int, n: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < n {
    out.push((b & 0xFF) as UInt8);
    i = i + 1;
  }
  return out;
}

/// Concatenation of two byte vectors.
pub fn aws_bytes_concat(a: &Vec[UInt8], b: &Vec[UInt8]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < a.len() {
    out.push(a[i]);
    i = i + 1;
  }
  i = 0;
  while i < b.len() {
    out.push(b[i]);
    i = i + 1;
  }
  return out;
}

/// Byte-content equality; compares masked widened bytes, never `==` on vectors.
pub fn aws_bytes_eq(a: &Vec[UInt8], b: &Vec[UInt8]) -> Bool {
  if a.len() != b.len() {
    return false;
  }
  var i = 0;
  while i < a.len() {
    let x: Int = (a[i] as Int) & 0xFF;
    let y: Int = (b[i] as Int) & 0xFF;
    if x != y {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// --------------------------------------------------
//  Hex
// --------------------------------------------------

const _HEX_LOWER: Str = "0123456789abcdef";

/// Lowercase hex of raw bytes (2 characters per byte).
pub fn aws_hex_encode_lower(v: &Vec[UInt8]) -> Str {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < v.len() {
    let b: Int = (v[i] as Int) & 0xFF;
    out.push(string.byte_at(_HEX_LOWER, b / 16));
    out.push(string.byte_at(_HEX_LOWER, b % 16));
    i = i + 1;
  }
  return builder.sb_to_str(&out);
}

// --------------------------------------------------
//  SHA-256 (FIPS 180-4)
// --------------------------------------------------

// 32-bit rotate right; x is masked to 32 bits, n is 1..31.
fn _sha_rotr32(x: Int, n: Int) -> Int {
  let a = x & 0xFFFFFFFF;
  return ((a >> n) | ((a << (32 - n)) & 0xFFFFFFFF)) & 0xFFFFFFFF;
}

// SHA-256 round constants (FIPS 180-4 section 4.2.2).
fn _sha256_k() -> Vec[Int] {
  var k = Vec[Int].new();
  k.push(0x428a2f98);
  k.push(0x71374491);
  k.push(0xb5c0fbcf);
  k.push(0xe9b5dba5);
  k.push(0x3956c25b);
  k.push(0x59f111f1);
  k.push(0x923f82a4);
  k.push(0xab1c5ed5);
  k.push(0xd807aa98);
  k.push(0x12835b01);
  k.push(0x243185be);
  k.push(0x550c7dc3);
  k.push(0x72be5d74);
  k.push(0x80deb1fe);
  k.push(0x9bdc06a7);
  k.push(0xc19bf174);
  k.push(0xe49b69c1);
  k.push(0xefbe4786);
  k.push(0x0fc19dc6);
  k.push(0x240ca1cc);
  k.push(0x2de92c6f);
  k.push(0x4a7484aa);
  k.push(0x5cb0a9dc);
  k.push(0x76f988da);
  k.push(0x983e5152);
  k.push(0xa831c66d);
  k.push(0xb00327c8);
  k.push(0xbf597fc7);
  k.push(0xc6e00bf3);
  k.push(0xd5a79147);
  k.push(0x06ca6351);
  k.push(0x14292967);
  k.push(0x27b70a85);
  k.push(0x2e1b2138);
  k.push(0x4d2c6dfc);
  k.push(0x53380d13);
  k.push(0x650a7354);
  k.push(0x766a0abb);
  k.push(0x81c2c92e);
  k.push(0x92722c85);
  k.push(0xa2bfe8a1);
  k.push(0xa81a664b);
  k.push(0xc24b8b70);
  k.push(0xc76c51a3);
  k.push(0xd192e819);
  k.push(0xd6990624);
  k.push(0xf40e3585);
  k.push(0x106aa070);
  k.push(0x19a4c116);
  k.push(0x1e376c08);
  k.push(0x2748774c);
  k.push(0x34b0bcb5);
  k.push(0x391c0cb3);
  k.push(0x4ed8aa4a);
  k.push(0x5b9cca4f);
  k.push(0x682e6ff3);
  k.push(0x748f82ee);
  k.push(0x78a5636f);
  k.push(0x84c87814);
  k.push(0x8cc70208);
  k.push(0x90befffa);
  k.push(0xa4506ceb);
  k.push(0xbef9a3f7);
  k.push(0xc67178f2);
  return k;
}

// SHA-256 initial hash state (FIPS 180-4 section 5.3.3).
fn _sha256_iv() -> Vec[Int] {
  var h = Vec[Int].new();
  h.push(0x6a09e667);
  h.push(0xbb67ae85);
  h.push(0x3c6ef372);
  h.push(0xa54ff53a);
  h.push(0x510e527f);
  h.push(0x9b05688c);
  h.push(0x1f83d9ab);
  h.push(0x5be0cd19);
  return h;
}

// 16 big-endian words of the 64-byte block starting at off.
fn _sha256_words(data: &Vec[UInt8], off: Int) -> Vec[Int] {
  var w = Vec[Int].new();
  var i = 0;
  while i < 16 {
    let b0: Int = (data[off + i * 4] as Int) & 0xFF;
    let b1: Int = (data[off + i * 4 + 1] as Int) & 0xFF;
    let b2: Int = (data[off + i * 4 + 2] as Int) & 0xFF;
    let b3: Int = (data[off + i * 4 + 3] as Int) & 0xFF;
    w.push((b0 * 16777216 + b1 * 65536 + b2 * 256 + b3) & 0xFFFFFFFF);
    i = i + 1;
  }
  return w;
}

// One compression round over the 8-word state h with one 16-word block.
fn _sha256_block(h: &mut Vec[Int], block: &Vec[Int]) {
  var w = Vec[Int].new();
  var i = 0;
  while i < 16 {
    let v: Int = block[i];
    w.push(v);
    i = i + 1;
  }
  while i < 64 {
    let w15: Int = w[i - 15];
    let w2: Int = w[i - 2];
    let s0 = (_sha_rotr32(w15, 7) ^ _sha_rotr32(w15, 18) ^ (w15 >> 3)) & 0xFFFFFFFF;
    let s1 = (_sha_rotr32(w2, 17) ^ _sha_rotr32(w2, 19) ^ (w2 >> 10)) & 0xFFFFFFFF;
    let wv: Int = w[i - 16];
    let w7: Int = w[i - 7];
    w.push((wv + s0 + w7 + s1) & 0xFFFFFFFF);
    i = i + 1;
  }
  let k = _sha256_k();
  let h0: Int = h[0];
  let h1: Int = h[1];
  let h2: Int = h[2];
  let h3: Int = h[3];
  let h4: Int = h[4];
  let h5: Int = h[5];
  let h6: Int = h[6];
  let h7: Int = h[7];
  var va = h0;
  var vb = h1;
  var vc = h2;
  var vd = h3;
  var ve = h4;
  var vf = h5;
  var vg = h6;
  var vh = h7;
  var t = 0;
  while t < 64 {
    let big_s1 = _sha_rotr32(ve, 6) ^ _sha_rotr32(ve, 11) ^ _sha_rotr32(ve, 25);
    let ch = (ve & vf) ^ ((ve ^ 0xFFFFFFFF) & vg);
    let kw: Int = k[t];
    let ww: Int = w[t];
    let temp1 = (vh + big_s1 + ch + kw + ww) & 0xFFFFFFFF;
    let big_s0 = _sha_rotr32(va, 2) ^ _sha_rotr32(va, 13) ^ _sha_rotr32(va, 22);
    let maj = (va & vb) ^ (va & vc) ^ (vb & vc);
    let temp2 = (big_s0 + maj) & 0xFFFFFFFF;
    vh = vg;
    vg = vf;
    vf = ve;
    ve = (vd + temp1) & 0xFFFFFFFF;
    vd = vc;
    vc = vb;
    vb = va;
    va = (temp1 + temp2) & 0xFFFFFFFF;
    t = t + 1;
  }
  h[0] = (h0 + va) & 0xFFFFFFFF;
  h[1] = (h1 + vb) & 0xFFFFFFFF;
  h[2] = (h2 + vc) & 0xFFFFFFFF;
  h[3] = (h3 + vd) & 0xFFFFFFFF;
  h[4] = (h4 + ve) & 0xFFFFFFFF;
  h[5] = (h5 + vf) & 0xFFFFFFFF;
  h[6] = (h6 + vg) & 0xFFFFFFFF;
  h[7] = (h7 + vh) & 0xFFFFFFFF;
}

/// SHA-256 digest (32 bytes) of raw bytes.
pub fn aws_sha256(data: &Vec[UInt8]) -> Vec[UInt8] {
  var h = _sha256_iv();
  let n = data.len();
  var pos = 0;
  while pos + 64 <= n {
    let blk = _sha256_words(data, pos);
    _sha256_block(&mut h, &blk);
    pos = pos + 64;
  }
  var tail = Vec[UInt8].new();
  var i = pos;
  while i < n {
    tail.push(data[i]);
    i = i + 1;
  }
  tail.push(128 as UInt8);
  while tail.len() % 64 != 56 {
    tail.push(0 as UInt8);
  }
  let bits = n * 8;
  var s = 56;
  while s >= 0 {
    tail.push(((bits >> s) & 0xFF) as UInt8);
    s = s - 8;
  }
  var p2 = 0;
  while p2 < tail.len() {
    let blk2 = _sha256_words(&tail, p2);
    _sha256_block(&mut h, &blk2);
    p2 = p2 + 64;
  }
  var out = Vec[UInt8].new();
  var j = 0;
  while j < 8 {
    let word: Int = h[j];
    out.push(((word >> 24) & 0xFF) as UInt8);
    out.push(((word >> 16) & 0xFF) as UInt8);
    out.push(((word >> 8) & 0xFF) as UInt8);
    out.push((word & 0xFF) as UInt8);
    j = j + 1;
  }
  return out;
}

/// Lowercase hex SHA-256 of raw bytes (64 characters).
pub fn aws_sha256_hex(data: &Vec[UInt8]) -> Str {
  let digest = aws_sha256(data);
  return aws_hex_encode_lower(&digest);
}

/// Lowercase hex SHA-256 of a Str's UTF-8 bytes.
pub fn aws_sha256_hex_str(s: Str) -> Str {
  let data = aws_bytes_of_str(s);
  return aws_sha256_hex(&data);
}

/// SHA-256 of the empty payload, the SigV4 hash for body-less requests
/// (e3b0c442...b855).
pub fn aws_empty_payload_sha256() -> Str {
  return "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855";
}

// --------------------------------------------------
//  HMAC-SHA-256 (RFC 2104)
// --------------------------------------------------

const _HMAC_BLOCK: Int = 64;
const _HMAC_IPAD: Int = 0x36;
const _HMAC_OPAD: Int = 0x5C;

// Block-sized key XOR pad. Keys longer than 64 bytes are hashed first.
fn _hmac_pad(key: &Vec[UInt8], pad: Int) -> Vec[UInt8] {
  var k = Vec[UInt8].new();
  if key.len() > _HMAC_BLOCK {
    let d = aws_sha256(key);
    var i = 0;
    while i < d.len() {
      k.push(d[i]);
      i = i + 1;
    }
  } else {
    var i = 0;
    while i < key.len() {
      k.push(key[i]);
      i = i + 1;
    }
  }
  while k.len() < _HMAC_BLOCK {
    k.push(0 as UInt8);
  }
  var out = Vec[UInt8].new();
  var j = 0;
  while j < _HMAC_BLOCK {
    let b: Int = (k[j] as Int) & 0xFF;
    out.push(((b ^ pad) & 0xFF) as UInt8);
    j = j + 1;
  }
  return out;
}

/// HMAC-SHA-256 tag (32 bytes).
pub fn aws_hmac_sha256(key: &Vec[UInt8], data: &Vec[UInt8]) -> Vec[UInt8] {
  let ipad = _hmac_pad(key, _HMAC_IPAD);
  let inner = aws_bytes_concat(&ipad, data);
  let inner_hash = aws_sha256(&inner);
  let opad = _hmac_pad(key, _HMAC_OPAD);
  let outer = aws_bytes_concat(&opad, &inner_hash);
  return aws_sha256(&outer);
}

/// Lowercase hex HMAC-SHA-256 tag.
pub fn aws_hmac_sha256_hex(key: &Vec[UInt8], data: &Vec[UInt8]) -> Str {
  let tag = aws_hmac_sha256(key, data);
  return aws_hex_encode_lower(&tag);
}
