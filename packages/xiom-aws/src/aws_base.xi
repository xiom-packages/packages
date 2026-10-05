// XIOM -- xiom.aws.base: SHA-256 / HMAC-SHA-256 / hex primitives
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// SHA-256 / HMAC-SHA-256 delegate to the stdlib (xiom.crypto.sha256 /
// xiom.crypto.hmac_sha256); v0.64.0 resolves the runtime-link failure that
// previously forced hand-rolled cores. The outputs stay pinned by the NIST
// FIPS 180-4 SHA-256 KATs (abc, empty, 448-bit) and RFC 4231 HMAC-SHA-256
// cases 1/2/3/6 (including a key longer than the 64-byte block) in
// tests/test_conformance.xi.
//
// v0.62.2 discipline: free functions only, no match, no &mut scalar
// parameters, masked byte widening, bounded loops, no Vec[StructType].

module xiom.aws.base

use xiom.crypto;
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

/// SHA-256 digest (32 bytes) of raw bytes.
pub fn aws_sha256(data: &Vec[UInt8]) -> Vec[UInt8] {
  return crypto.sha256(data);
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

/// HMAC-SHA-256 tag (32 bytes).
pub fn aws_hmac_sha256(key: &Vec[UInt8], data: &Vec[UInt8]) -> Vec[UInt8] {
  return crypto.hmac_sha256(key, data);
}

/// Lowercase hex HMAC-SHA-256 tag.
pub fn aws_hmac_sha256_hex(key: &Vec[UInt8], data: &Vec[UInt8]) -> Str {
  let tag = aws_hmac_sha256(key, data);
  return aws_hex_encode_lower(&tag);
}
