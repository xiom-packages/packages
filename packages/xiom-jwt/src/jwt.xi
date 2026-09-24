// XIOM -- xiom.jwt: structural JWT decoding (headers, claims, timestamps)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// SECURITY: decode-only. This module performs NO signature verification, NO
// JSON parsing, no key handling and no crypto. Never make an authentication
// or authorization decision from its output without verifying the token's
// signature elsewhere against a trusted key.
//
// What this module does:
//   * count the '.'-separated segments of a compact JWS/JWE token;
//   * base64url-decode a segment and validate the decoded bytes as UTF-8;
//   * expose the header and payload text and the raw signature segment;
//   * read the "alg" header value and top-level string/integer claims with a
//     minimal scanner, then derive exp/nbf time checks.
//
// Deliberate limitations (documented in SPEC.md):
//   * NO JSON parser. `jwt_alg`, `jwt_claim_str` and `jwt_claim_int` find the
//     FIRST occurrence of the quoted `"name"` anywhere in the text, expect a
//     ':' (whitespace allowed around it) and then read a quoted string or a
//     signed integer. Escapes are NOT decoded, nested objects are not
//     understood and a `"name"` inside another string value can match.
//   * base64url decoding is strict RFC 4648 section 5: only `A-Z a-z 0-9 - _`
//     plus an optional trailing '=' run. `+`/`/` are NOT accepted.
//   * The stdlib `xiom.encoding.base64` module provides base64url helpers but
//     they allocate through FFI (malloc/free) and its `base64url_decode`
//     silently drops a 1-character tail; this package therefore carries its
//     own small pure-XIOM helper instead of depending on it (or on
//     xiom.codec).
//
// v0.61.3 notes that shaped this module:
//   * Free functions only; every `byte_at` read is widened with
//     `(string.byte_at(s, i) as Int) & 0xFF` before any comparison.
//   * Ok/Err are constructed only in the tiny leaf helpers below; building
//     Results inline inside larger functions miscompiles.
//   * No `==` on Str values (callers/tests use
//     xiom.string.compare.str_compare); this module only compares bytes.
//
// Error strings always start with the literal prefix "jwt: ".

module xiom.jwt

use xiom.string;

// --------------------------------------------------
//  Result constructors (leaf helpers, see header)
// --------------------------------------------------

fn _ok_str(v: Str) -> Result[Str, Str] {
  return Ok(v);
}

fn _err_str(m: Str) -> Result[Str, Str] {
  return Err(m);
}

fn _ok_bool(v: Bool) -> Result[Bool, Str] {
  return Ok(v);
}

fn _err_bool(m: Str) -> Result[Bool, Str] {
  return Err(m);
}

fn _ok_int(v: Int) -> Result[Int, Str] {
  return Ok(v);
}

fn _err_int(m: Str) -> Result[Int, Str] {
  return Err(m);
}

fn _ok_bytes(v: Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  return Ok(v);
}

fn _err_bytes(m: Str) -> Result[Vec[UInt8], Str] {
  return Err(m);
}

// --------------------------------------------------
//  Byte helpers
// --------------------------------------------------

// True for the ASCII whitespace bytes the scanner may skip: TAB (9), LF (10),
// CR (13) and space (32). JSON also allows VT/FF but no encoder emits them.
fn _is_ws(b: Int) -> Bool {
  if b == 9 || b == 10 || b == 13 || b == 32 {
    return true;
  }
  return false;
}

// Base64url value of one byte; -1 when the byte is not in the RFC 4648
// section 5 alphabet (A-Z a-z 0-9 - _). '=' is not a data character.
fn _b64u_value(b: Int) -> Int {
  if b >= 65 && b <= 90 { return b - 65; }
  if b >= 97 && b <= 122 { return b - 71; }
  if b >= 48 && b <= 57 { return b + 4; }
  if b == 45 { return 62; }
  if b == 95 { return 63; }
  return -1;
}

// True when (core data characters, '=' pad characters) cannot decode: a data
// length of 1 (mod 4) is impossible and explicit padding must complete the
// final quantum (3+1 or 2+2 data/pad split).
fn _b64u_bad_count(core: Int, pad: Int) -> Bool {
  let m = core % 4;
  if pad == 0 {
    if m == 1 { return true; }
    return false;
  }
  if (core + pad) % 4 != 0 { return true; }
  if pad == 1 { return m != 3; }
  if pad == 2 { return m != 2; }
  return true;
}

// True when the byte is a UTF-8 continuation byte (10xxxxxx).
fn _is_cont(b: Int) -> Bool {
  return (b & 0xC0) == 0x80;
}

// True when `data` is well-formed UTF-8 per RFC 3629. Rejects stray
// continuation bytes, truncated sequences, overlong forms, UTF-16 surrogate
// code points (U+D800..U+DFFF) and code points above U+10FFFF. Implemented
// locally because the pinned stdlib validator is too permissive.
fn _utf8_valid(data: &Vec[UInt8]) -> Bool {
  let n = data.len();
  var i = 0;
  while i < n {
    let b0 = (data[i] as Int) & 0xFF;
    if b0 <= 0x7F {
      i = i + 1;
    } elif b0 >= 0xC2 && b0 <= 0xDF {
      if i + 1 >= n { return false; }
      let b1 = (data[i + 1] as Int) & 0xFF;
      if !_is_cont(b1) { return false; }
      i = i + 2;
    } elif b0 >= 0xE0 && b0 <= 0xEF {
      if i + 2 >= n { return false; }
      let b1 = (data[i + 1] as Int) & 0xFF;
      let b2 = (data[i + 2] as Int) & 0xFF;
      if !_is_cont(b1) || !_is_cont(b2) { return false; }
      if b0 == 0xE0 && b1 < 0xA0 { return false; }
      if b0 == 0xED && b1 >= 0xA0 { return false; }
      i = i + 3;
    } elif b0 >= 0xF0 && b0 <= 0xF4 {
      if i + 3 >= n { return false; }
      let b1 = (data[i + 1] as Int) & 0xFF;
      let b2 = (data[i + 2] as Int) & 0xFF;
      let b3 = (data[i + 3] as Int) & 0xFF;
      if !_is_cont(b1) || !_is_cont(b2) || !_is_cont(b3) { return false; }
      if b0 == 0xF0 && b1 < 0x90 { return false; }
      if b0 == 0xF4 && b1 > 0x8F { return false; }
      i = i + 4;
    } else {
      return false;
    }
  }
  return true;
}

// --------------------------------------------------
//  Token segmentation
// --------------------------------------------------

// Number of '.'-separated pieces: 1 plus the number of '.' bytes. An empty
// token has one (empty) piece, not zero. A compact JWS has 3, a JWE-style
// token has 5.
fn _seg_count(s: Str) -> Int {
  let n = s.len();
  var count = 1;
  var i = 0;
  while i < n {
    let b = (string.byte_at(s, i) as Int) & 0xFF;
    if b == 46 {
      count = count + 1;
    }
    i = i + 1;
  }
  return count;
}

// Byte offset where segment `index` starts, or -1 when out of range.
fn _seg_start(s: Str, index: Int) -> Int {
  if index < 0 { return -1; }
  let n = s.len();
  var seg = 0;
  var start = 0;
  var i = 0;
  while i < n {
    let b = (string.byte_at(s, i) as Int) & 0xFF;
    if b == 46 {
      if seg == index { return start; }
      seg = seg + 1;
      start = i + 1;
    }
    i = i + 1;
  }
  if seg == index { return start; }
  return -1;
}

// Byte offset just past segment `index` (exclusive), or -1 when out of range.
fn _seg_end(s: Str, index: Int) -> Int {
  if index < 0 { return -1; }
  let n = s.len();
  var seg = 0;
  var i = 0;
  while i < n {
    let b = (string.byte_at(s, i) as Int) & 0xFF;
    if b == 46 {
      if seg == index { return i; }
      seg = seg + 1;
    }
    i = i + 1;
  }
  if seg == index { return n; }
  return -1;
}

// True when [start, end) is a non-empty run of base64url alphabet bytes.
fn _seg_is_b64u(s: Str, start: Int, end: Int) -> Bool {
  if end <= start { return false; }
  var i = start;
  while i < end {
    let b = (string.byte_at(s, i) as Int) & 0xFF;
    if _b64u_value(b) < 0 { return false; }
    i = i + 1;
  }
  return true;
}

// Require exactly 3 segments; Err("jwt: token is not a 3-segment JWT")
// otherwise. Used by the text accessors (they accept optional padding, which
// the stricter jwt_is_shaped predicate rejects).
fn _require_three(token: Str) -> Result[Str, Str] {
  if _seg_count(token) != 3 {
    return _err_str("jwt: token is not a 3-segment JWT");
  }
  return _ok_str("");
}

// --------------------------------------------------
//  base64url decode and UTF-8
// --------------------------------------------------

// Decode strict base64url (RFC 4648 section 5) into bytes. Optional trailing
// '=' padding is accepted and checked; trailing bits of a partial tail are
// ignored (non-canonical encodings decode).
fn _b64u_decode(s: Str) -> Result[Vec[UInt8], Str] {
  var vals = Vec[Int].new();
  let n = s.len();
  var pad = 0;
  var seen_pad = false;
  var i = 0;
  while i < n {
    let b = (string.byte_at(s, i) as Int) & 0xFF;
    if b == 61 {
      pad = pad + 1;
      seen_pad = true;
      i = i + 1;
    } else {
      if seen_pad {
        return _err_bytes("jwt: invalid base64url padding");
      }
      let v = _b64u_value(b);
      if v < 0 {
        return _err_bytes("jwt: invalid base64url character");
      }
      vals.push(v);
      i = i + 1;
    }
  }
  if pad > 2 || _b64u_bad_count(vals.len(), pad) {
    return _err_bytes("jwt: invalid base64url padding");
  }
  var out = Vec[UInt8].new();
  let core = vals.len();
  var k = 0;
  while k + 4 <= core {
    let v0: Int = vals[k];
    let v1: Int = vals[k + 1];
    let v2: Int = vals[k + 2];
    let v3: Int = vals[k + 3];
    out.push(((v0 << 2) | (v1 >> 4)) as UInt8);
    out.push(((v1 << 4) | (v2 >> 2)) as UInt8);
    out.push(((v2 << 6) | v3) as UInt8);
    k = k + 4;
  }
  let rem = core - k;
  if rem == 2 {
    let v0: Int = vals[k];
    let v1: Int = vals[k + 1];
    out.push(((v0 << 2) | (v1 >> 4)) as UInt8);
  } elif rem == 3 {
    let v0: Int = vals[k];
    let v1: Int = vals[k + 1];
    let v2: Int = vals[k + 2];
    out.push(((v0 << 2) | (v1 >> 4)) as UInt8);
    out.push(((v1 << 4) | (v2 >> 2)) as UInt8);
  }
  return _ok_bytes(out);
}

// Decode one segment as base64url and validate the bytes as UTF-8 text.
fn _segment_to_text(seg: Str) -> Result[Str, Str] {
  let decoded = _b64u_decode(seg);
  if !decoded.is_ok {
    return _err_str(decoded.error);
  }
  let bytes = decoded.value;
  if !_utf8_valid(&bytes) {
    return _err_str("jwt: invalid UTF-8");
  }
  return _ok_str(Str::from_utf8(bytes));
}

// --------------------------------------------------
//  Claim scanner (documented JSON subset, see header)
// --------------------------------------------------

// Skip the ASCII whitespace bytes _is_ws accepts, starting at `i`; returns the
// index of the first byte that is not whitespace (may be the end).
fn _skip_ws(text: Str, i: Int) -> Int {
  let n = text.len();
  var p = i;
  while p < n {
    let b = (string.byte_at(text, p) as Int) & 0xFF;
    if _is_ws(b) {
      p = p + 1;
    } else {
      return p;
    }
  }
  return p;
}

// Byte offset just past the closing quote of the FIRST `"name"` occurrence in
// `text`, or -1 when absent. The key is matched byte-wise, so non-ASCII keys
// work; nesting and escapes are not understood (documented subset).
fn _find_key(text: Str, name: Str) -> Int {
  let n = text.len();
  let klen = name.len();
  if klen == 0 { return -1; }
  var i = 0;
  while i < n {
    let b = (string.byte_at(text, i) as Int) & 0xFF;
    if b == 34 {
      if i + 1 + klen < n {
        var same = true;
        var j = 0;
        while j < klen {
          let c = (string.byte_at(text, i + 1 + j) as Int) & 0xFF;
          let d = (string.byte_at(name, j) as Int) & 0xFF;
          if c != d { same = false; }
          j = j + 1;
        }
        if same {
          let q = (string.byte_at(text, i + 1 + klen) as Int) & 0xFF;
          if q == 34 {
            return i + 1 + klen + 1;
          }
        }
      }
    }
    i = i + 1;
  }
  return -1;
}

// Position of the value that follows key occurrence position `k`: skip
// whitespace, require ':', skip whitespace again. Returns -1 when the colon
// is missing (an existing key without a value separator); the returned index
// may equal text.len() when the text ends right after the colon.
fn _value_pos(text: Str, k: Int) -> Int {
  let n = text.len();
  var i = _skip_ws(text, k);
  if i >= n {
    return -1;
  }
  let b = (string.byte_at(text, i) as Int) & 0xFF;
  if b != 58 {
    return -1;
  }
  return _skip_ws(text, i + 1);
}

// Read a quoted string value stored under `key`; Err when the key is absent,
// the value is not a quoted string or the closing quote is missing. Escapes
// are not decoded: the value ends at the next '"' byte.
fn _string_value(text: Str, key: Str) -> Result[Str, Str] {
  let k = _find_key(text, key);
  if k < 0 {
    return _err_str("jwt: key not found: " + key);
  }
  let n = text.len();
  let i = _value_pos(text, k);
  if i < 0 || i >= n {
    return _err_str("jwt: expected string value");
  }
  let b = (string.byte_at(text, i) as Int) & 0xFF;
  if b != 34 {
    return _err_str("jwt: expected string value");
  }
  var j = i + 1;
  while j < n {
    let c = (string.byte_at(text, j) as Int) & 0xFF;
    if c == 34 {
      return _ok_str(string.str_slice(text, i + 1, j));
    }
    j = j + 1;
  }
  return _err_str("jwt: unterminated string value");
}

// Read an integer value stored under `key`: optional '-', then one or more
// digits, then end-of-text or a terminator byte (whitespace, ',' or '}').
// Err when the key is absent, the value starts with a non-digit, a non-digit
// interrupts the number without being a terminator, or the magnitude exceeds
// the 64-bit signed range.
fn _int_value(text: Str, key: Str) -> Result[Int, Str] {
  let k = _find_key(text, key);
  if k < 0 {
    return _err_int("jwt: key not found: " + key);
  }
  let n = text.len();
  var i = _value_pos(text, k);
  if i < 0 || i >= n {
    return _err_int("jwt: expected integer value");
  }
  var neg = false;
  var b = (string.byte_at(text, i) as Int) & 0xFF;
  if b == 45 {
    neg = true;
    i = i + 1;
    if i >= n {
      return _err_int("jwt: expected integer value");
    }
    b = (string.byte_at(text, i) as Int) & 0xFF;
  }
  if b < 48 || b > 57 {
    return _err_int("jwt: expected integer value");
  }
  var acc = 0;
  var stopped = false;
  while i < n && !stopped {
    b = (string.byte_at(text, i) as Int) & 0xFF;
    if b >= 48 && b <= 57 {
      let d = b - 48;
      if acc > 922337203685477580 {
        return _err_int("jwt: integer out of range");
      }
      acc = acc * 10;
      if acc < 0 {
        return _err_int("jwt: integer out of range");
      }
      acc = acc + d;
      if acc < 0 {
        return _err_int("jwt: integer out of range");
      }
      i = i + 1;
    } else {
      stopped = true;
    }
  }
  if i < n {
    b = (string.byte_at(text, i) as Int) & 0xFF;
    if !(b == 32 || b == 9 || b == 10 || b == 13 || b == 44 || b == 125) {
      return _err_int("jwt: malformed integer value");
    }
  }
  if neg {
    return _ok_int(0 - acc);
  }
  return _ok_int(acc);
}

// --------------------------------------------------
//  Public API -- token structure
// --------------------------------------------------

/// Count the '.'-separated segments of a compact token (1 + number of dots).
/// Params: token - the raw token text.
/// Returns: 3 for `header.payload.signature` (compact JWS), 5 for a
/// JWE-style token (`header.encrypted_key.iv.ciphertext.tag`), 1 for a token
/// without dots, 1 for the empty string (one empty piece).
/// Error case: none.
/// Complexity: O(token.len()).
pub fn jwt_segment_count(token: Str) -> Int {
  return _seg_count(token);
}

/// Structural predicate for a compact JWS: exactly 3 non-empty segments, each
/// made only of RFC 4648 section 5 base64url alphabet characters. Optional
/// '=' padding is NOT part of the alphabet, so a padded token returns false
/// here even though the decoders accept it; an unsecured JWT with an empty
/// signature (`h.p.`) also returns false.
/// Params: token - the raw token text.
/// Returns: true when the token has the exact 3-segment base64url shape.
/// Error case: none.
/// Complexity: O(token.len()).
pub fn jwt_is_shaped(token: Str) -> Bool {
  if _seg_count(token) != 3 {
    return false;
  }
  var k = 0;
  while k < 3 {
    let start = _seg_start(token, k);
    let end = _seg_end(token, k);
    if start < 0 { return false; }
    if !_seg_is_b64u(token, start, end) { return false; }
    k = k + 1;
  }
  return true;
}

// --------------------------------------------------
//  Public API -- segment decoding
// --------------------------------------------------

/// Base64url-decode one segment of `token` and validate it as UTF-8 text.
/// Params: token - the raw token text; index - 0-based segment index.
/// Returns: Ok(text) for a valid segment. Optional trailing '=' padding is
/// accepted and must complete the final quantum; trailing bits of a partial
/// tail are ignored. Both the encoded bytes and the decoded bytes must be
/// valid: an invalid base64url alphabet byte, bad padding or malformed UTF-8
/// is an Err.
/// Error case: Err("jwt: segment index out of range") when index < 0 or
/// beyond the last segment; Err("jwt: empty segment") for an empty segment;
/// Err("jwt: invalid base64url character"); Err("jwt: invalid base64url
/// padding"); Err("jwt: invalid UTF-8").
/// Complexity: O(segment.len()).
pub fn jwt_decode_segment(token: Str, index: Int) -> Result[Str, Str] {
  if index < 0 || index >= _seg_count(token) {
    return _err_str("jwt: segment index out of range");
  }
  let start = _seg_start(token, index);
  let end = _seg_end(token, index);
  if start < 0 || end < start {
    return _err_str("jwt: segment index out of range");
  }
  if end == start {
    return _err_str("jwt: empty segment");
  }
  return _segment_to_text(string.str_slice(token, start, end));
}

/// Decode segment 0 (the JOSE header) as UTF-8 text.
/// Params: token - the raw token text; exactly 3 segments are required.
/// Returns: Ok(header text) with the same base64url/UTF-8 rules as
/// jwt_decode_segment.
/// Error case: Err("jwt: token is not a 3-segment JWT") for any other
/// segment count; Err("jwt: empty segment") for an empty header; plus the
/// base64url/UTF-8 errors of jwt_decode_segment.
/// Complexity: O(token.len()).
pub fn jwt_header_text(token: Str) -> Result[Str, Str] {
  let three = _require_three(token);
  if !three.is_ok {
    return _err_str(three.error);
  }
  let start = _seg_start(token, 0);
  let end = _seg_end(token, 0);
  if end <= start {
    return _err_str("jwt: empty segment");
  }
  return _segment_to_text(string.str_slice(token, start, end));
}

/// Decode segment 1 (the claims payload) as UTF-8 text.
/// Params: token - the raw token text; exactly 3 segments are required.
/// Returns: Ok(payload text) with the same base64url/UTF-8 rules as
/// jwt_decode_segment.
/// Error case: Err("jwt: token is not a 3-segment JWT") for any other
/// segment count; Err("jwt: empty segment") for an empty payload; plus the
/// base64url/UTF-8 errors of jwt_decode_segment.
/// Complexity: O(token.len()).
pub fn jwt_payload_text(token: Str) -> Result[Str, Str] {
  let three = _require_three(token);
  if !three.is_ok {
    return _err_str(three.error);
  }
  let start = _seg_start(token, 1);
  let end = _seg_end(token, 1);
  if end <= start {
    return _err_str("jwt: empty segment");
  }
  return _segment_to_text(string.str_slice(token, start, end));
}

/// Return segment 2 (the signature) verbatim -- NOT decoded. The value is the
/// raw base64url text as it appears in the token; an unsecured JWT with an
/// empty signature yields Ok("").
/// Params: token - the raw token text; exactly 3 segments are required.
/// Returns: Ok(raw signature segment).
/// Error case: Err("jwt: token is not a 3-segment JWT") for any other
/// segment count.
/// Complexity: O(token.len()).
pub fn jwt_signature_text(token: Str) -> Result[Str, Str] {
  let three = _require_three(token);
  if !three.is_ok {
    return _err_str(three.error);
  }
  let start = _seg_start(token, 2);
  let end = _seg_end(token, 2);
  return _ok_str(string.str_slice(token, start, end));
}

// --------------------------------------------------
//  Public API -- claims
// --------------------------------------------------

/// Extract the "alg" string value from the JOSE header with the minimal
/// scanner (first quoted `"alg"` occurrence; escapes not decoded).
/// Params: token - the raw token text.
/// Returns: Ok(alg) e.g. "HS256" or "none".
/// Error case: Err("jwt: token is not a 3-segment JWT"); the header decode
/// errors of jwt_header_text; Err("jwt: key not found: alg") when the header
/// has no quoted "alg"; Err("jwt: expected string value") when "alg" is not
/// followed by a quoted string.
/// Complexity: O(token.len()).
pub fn jwt_alg(token: Str) -> Result[Str, Str] {
  let decoded = jwt_header_text(token);
  if !decoded.is_ok {
    return _err_str(decoded.error);
  }
  return _string_value(decoded.value, "alg");
}

/// Extract a top-level string claim from the payload with the minimal scanner
/// (first quoted `"name"` occurrence; escapes not decoded).
/// Params: token - the raw token text; name - the claim name without quotes.
/// Returns: Ok(value) for a quoted string claim.
/// Error case: the payload decode errors of jwt_payload_text;
/// Err("jwt: key not found: <name>") when absent;
/// Err("jwt: expected string value") when the value is not a quoted string;
/// Err("jwt: unterminated string value") when the closing quote is missing.
/// Complexity: O(token.len()).
pub fn jwt_claim_str(token: Str, name: Str) -> Result[Str, Str] {
  let decoded = jwt_payload_text(token);
  if !decoded.is_ok {
    return _err_str(decoded.error);
  }
  return _string_value(decoded.value, name);
}

/// Extract a top-level integer claim from the payload with the minimal
/// scanner: optional '-', one or more digits, then end-of-text, whitespace,
/// ',' or '}'. A quoted number (`"exp":"100"`), a float (`12.5`) or trailing
/// junk (`12abc`) is rejected rather than coerced.
/// Params: token - the raw token text; name - the claim name without quotes.
/// Returns: Ok(value) for a signed 64-bit integer claim.
/// Error case: the payload decode errors of jwt_payload_text;
/// Err("jwt: key not found: <name>") when absent;
/// Err("jwt: expected integer value") when the value does not start with a
/// digit or '-'; Err("jwt: malformed integer value") for junk after the
/// digits; Err("jwt: integer out of range") beyond the signed 64-bit range.
/// Complexity: O(token.len()).
pub fn jwt_claim_int(token: Str, name: Str) -> Result[Int, Str] {
  let decoded = jwt_payload_text(token);
  if !decoded.is_ok {
    return _err_int(decoded.error);
  }
  return _int_value(decoded.value, name);
}

/// Evaluate the "exp" claim against a caller-supplied clock.
/// Policy (documented in SPEC.md): a token is EXPIRED when `exp <= now`;
/// there is NO built-in clock-skew allowance -- callers that want skew must
/// subtract it from `now_secs` themselves. The function never reads the
/// system clock.
/// Params: token - the raw token text; now_secs - current Unix time in
/// seconds, supplied by the caller.
/// Returns: Ok(true) when exp <= now_secs, Ok(false) otherwise.
/// Error case: the payload/decode errors of jwt_claim_int; Err when "exp" is
/// absent or malformed (never a silent Ok(true)).
/// Complexity: O(token.len()).
pub fn jwt_expired(token: Str, now_secs: Int) -> Result[Bool, Str] {
  let exp = jwt_claim_int(token, "exp");
  if !exp.is_ok {
    return _err_bool(exp.error);
  }
  if exp.value <= now_secs {
    return _ok_bool(true);
  }
  return _ok_bool(false);
}

/// Evaluate the "nbf" (not before) claim against a caller-supplied clock.
/// Policy (documented in SPEC.md): the token is usable when `now >= nbf`;
/// there is NO built-in clock-skew allowance -- callers that want skew must
/// add it to `now_secs` themselves. The function never reads the system
/// clock.
/// Params: token - the raw token text; now_secs - current Unix time in
/// seconds, supplied by the caller.
/// Returns: Ok(true) when now_secs >= nbf, Ok(false) otherwise.
/// Error case: the payload/decode errors of jwt_claim_int; Err when "nbf" is
/// absent or malformed.
/// Complexity: O(token.len()).
pub fn jwt_not_before_ok(token: Str, now_secs: Int) -> Result[Bool, Str] {
  let nbf = jwt_claim_int(token, "nbf");
  if !nbf.is_ok {
    return _err_bool(nbf.error);
  }
  if now_secs >= nbf.value {
    return _ok_bool(true);
  }
  return _ok_bool(false);
}
