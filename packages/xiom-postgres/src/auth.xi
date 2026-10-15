// XIOM -- xiom.postgres authentication helpers
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Client-side authentication computations for the PostgreSQL v3 protocol:
// the MD5 password challenge and SCRAM-SHA-256 (RFC 5802 / RFC 7677).
// Built on the stdlib primitives (xiom.crypto sha256/hmac_sha256/pbkdf2,
// xiom.encoding base64, xiom.rand CSPRNG). Pure functions: no sockets, no
// global state, no wall clock. The RFC 7677 test vector is pinned in the
// conformance suite.

module xiom.postgres.auth

use xiom.crypto;
use xiom.encoding;
use xiom.rand;
use xiom.string;
use xiom.postgres.wire;

fn bytes_of_str(s: Str) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < s.len() {
    out.push(s.byte_at(i));
    i = i + 1;
  }
  return out;
}

fn hex_lower(b: &Vec[UInt8]) -> Str {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < b.len() {
    let v = b[i] as Int;
    let hi = v / 16;
    let lo = v % 16;
    if hi < 10 {
      out.push((48 + hi) as UInt8);
    } else {
      out.push((87 + hi) as UInt8);
    }
    if lo < 10 {
      out.push((48 + lo) as UInt8);
    } else {
      out.push((87 + lo) as UInt8);
    }
    i = i + 1;
  }
  return Str::from_utf8(out);
}

fn xor_bytes(a: &Vec[UInt8], b: &Vec[UInt8]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < a.len() && i < b.len() {
    let xa = a[i] as Int;
    let xb = b[i] as Int;
    out.push((xa ^ xb) as UInt8);
    i = i + 1;
  }
  return out;
}

fn bytes_eq(a: &Vec[UInt8], b: &Vec[UInt8]) -> Bool {
  if a.len() != b.len() {
    return false;
  }
  var i = 0;
  while i < a.len() {
    if a[i] != b[i] {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// ------------------------------------------------------------------ MD5
//
// xiom.crypto.md5 (v0.64.5) does not produce RFC 1321 digests (checked:
// md5("abc") yields 5aac66a4..., the RFC value is 900150983cd24fb0d6963f7d
// 28e17f72), so this module carries its own byte-based MD5. RFC 1321
// constants; the suite pins md5("abc") and md5("") against the RFC values.

fn rotl32(x: Int, s: Int) -> Int {
  let v = x & 4294967295;
  if s == 0 {
    return v;
  }
  return ((v << s) | (v >> (32 - s))) & 4294967295;
}

/// MD5 digest (16 bytes) of arbitrary input.
pub fn md5_digest(data: &Vec[UInt8]) -> Vec[UInt8] {
  var padded = Vec[UInt8].new();
  var i = 0;
  while i < data.len() {
    padded.push(data[i]);
    i = i + 1;
  }
  padded.push(128);
  while padded.len() % 64 != 56 {
    padded.push(0);
  }
  var bit_len = data.len() * 8;
  i = 0;
  while i < 8 {
    padded.push((bit_len & 255) as UInt8);
    bit_len = bit_len >> 8;
    i = i + 1;
  }
  var k: Vec[Int] = [
    0xd76aa478, 0xe8c7b756, 0x242070db, 0xc1bdceee,
    0xf57c0faf, 0x4787c62a, 0xa8304613, 0xfd469501,
    0x698098d8, 0x8b44f7af, 0xffff5bb1, 0x895cd7be,
    0x6b901122, 0xfd987193, 0xa679438e, 0x49b40821,
    0xf61e2562, 0xc040b340, 0x265e5a51, 0xe9b6c7aa,
    0xd62f105d, 0x02441453, 0xd8a1e681, 0xe7d3fbc8,
    0x21e1cde6, 0xc33707d6, 0xf4d50d87, 0x455a14ed,
    0xa9e3e905, 0xfcefa3f8, 0x676f02d9, 0x8d2a4c8a,
    0xfffa3942, 0x8771f681, 0x6d9d6122, 0xfde5380c,
    0xa4beea44, 0x4bdecfa9, 0xf6bb4b60, 0xbebfbc70,
    0x289b7ec6, 0xeaa127fa, 0xd4ef3085, 0x04881d05,
    0xd9d4d039, 0xe6db99e5, 0x1fa27cf8, 0xc4ac5665,
    0xf4292244, 0x432aff97, 0xab9423a7, 0xfc93a039,
    0x655b59c3, 0x8f0ccc92, 0xffeff47d, 0x85845dd1,
    0x6fa87e4f, 0xfe2ce6e0, 0xa3014314, 0x4e0811a1,
    0xf7537e82, 0xbd3af235, 0x2ad7d2bb, 0xeb86d391];
  var sh: Vec[Int] = [
    7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,
    5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20,
    4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
    6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21];
  var a = 0x67452301;
  var b = 0xefcdab89;
  var c = 0x98badcfe;
  var d = 0x10325476;
  var off = 0;
  while off < padded.len() {
    var m: Vec[Int] = Vec[Int].new();
    var wi = 0;
    while wi < 16 {
      let idx = off + wi * 4;
      let w0 = padded[idx] as Int;
      let w1 = padded[idx + 1] as Int;
      let w2 = padded[idx + 2] as Int;
      let w3 = padded[idx + 3] as Int;
      m.push(w0 | (w1 << 8) | (w2 << 16) | (w3 << 24));
      wi = wi + 1;
    }
    var aa = a;
    var bb = b;
    var cc = c;
    var dd = d;
    i = 0;
    while i < 64 {
      var f = 0;
      var g = 0;
      if i < 16 {
        f = (bb & cc) | ((~bb & 4294967295) & dd);
        g = i;
      } elif i < 32 {
        f = (dd & bb) | ((~dd & 4294967295) & cc);
        g = (5 * i + 1) % 16;
      } elif i < 48 {
        f = bb ^ cc ^ dd;
        g = (3 * i + 5) % 16;
      } else {
        f = cc ^ (bb | (~dd & 4294967295));
        g = (7 * i) % 16;
      }
      let fv = f & 4294967295;
      let tmp = dd;
      dd = cc;
      cc = bb;
      let x = (aa + fv + k[i] + m[g]) & 4294967295;
      bb = (bb + rotl32(x, sh[i])) & 4294967295;
      aa = tmp;
      i = i + 1;
    }
    a = (a + aa) & 4294967295;
    b = (b + bb) & 4294967295;
    c = (c + cc) & 4294967295;
    d = (d + dd) & 4294967295;
    off = off + 64;
  }
  var out = Vec[UInt8].new();
  var words: Vec[Int] = [a, b, c, d];
  var w = 0;
  while w < 4 {
    var v = words[w];
    var j = 0;
    while j < 4 {
      out.push((v & 255) as UInt8);
      v = v >> 8;
      j = j + 1;
    }
    w = w + 1;
  }
  return out;
}

/// Lowercase-hex MD5 of arbitrary input.
pub fn md5_hex(data: &Vec[UInt8]) -> Str {
  return hex_lower(&md5_digest(data));
}

/// The 'p' PasswordMessage payload for the MD5 auth request (auth code 5):
/// "md5" + md5_hex( md5_hex(password + user) || salt ). Matches the
/// PostgreSQL MD5 authentication scheme.
pub fn pg_md5_password(password: Str, user: Str, salt: &Vec[UInt8]) -> Str {
  var inner_in = Vec[UInt8].new();
  var i = 0;
  while i < password.len() {
    inner_in.push(password.byte_at(i));
    i = i + 1;
  }
  i = 0;
  while i < user.len() {
    inner_in.push(user.byte_at(i));
    i = i + 1;
  }
  let inner = md5_hex(&inner_in);
  var outer_in = Vec[UInt8].new();
  i = 0;
  while i < inner.len() {
    outer_in.push(inner.byte_at(i));
    i = i + 1;
  }
  i = 0;
  while i < salt.len() {
    outer_in.push(salt[i]);
    i = i + 1;
  }
  let outer = md5_hex(&outer_in);
  return string.str_concat("md5", outer);
}

// ------------------------------------------------------------------ SCRAM-SHA-256

fn saslname_escape(s: Str) -> Str {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < s.len() {
    let c = s.byte_at(i);
    if c == (61 as UInt8) {
      out.push(61);
      out.push(51);
      out.push(68);
    } elif c == (44 as UInt8) {
      out.push(61);
      out.push(50);
      out.push(67);
    } else {
      out.push(c);
    }
    i = i + 1;
  }
  return Str::from_utf8(out);
}

/// Fresh client nonce: 18 CSPRNG bytes, base64, padding stripped. Printable
/// US-ASCII with no comma (SCRAM's nonce alphabet).
pub fn scram_client_nonce() -> Str {
  let raw = rand.random_bytes_crypto(18);
  let b64 = encoding.base64_encode(&raw);
  var end = b64.len();
  while end > 0 && b64.byte_at(end - 1) == (61 as UInt8) {
    end = end - 1;
  }
  return string.str_slice(b64, 0, end);
}

/// The SCRAM client-first message with the gs2 header omitted:
/// "n=<saslname(user)>,r=<nonce>".
pub fn scram_client_first_bare(user: Str, nonce: Str) -> Str {
  return string.str_concat(
    string.str_concat(
      string.str_concat("n=", saslname_escape(user)),
      ",r="),
    nonce);
}

/// The full SCRAM client-first message with the "n,," gs2 header (no
/// channel binding).
pub fn scram_client_first(user: Str, nonce: Str) -> Str {
  return string.str_concat("n,,", scram_client_first_bare(user, nonce));
}

/// Parsed SCRAM server-first message.
pub type ScramServerFirst = {
  nonce: Str;
  salt_b64: Str;
  iterations: Int;
}

/// Parse the server-first message ("r=...,s=...,i=..."). A server-reported
/// error ("e=...") or a missing attribute is a typed PG_ERR_AUTH error.
pub fn scram_parse_server_first(text: Str) -> Result[ScramServerFirst, PgError] {
  let parts = string.str_split(text, ",");
  var nonce = "";
  var salt = "";
  var iters = 0;
  var err_msg = "";
  var i = 0;
  while i < parts.len() {
    let p = parts[i];
    if string.str_starts_with(p, "r=") {
      nonce = string.str_slice(p, 2, p.len());
    } elif string.str_starts_with(p, "s=") {
      salt = string.str_slice(p, 2, p.len());
    } elif string.str_starts_with(p, "i=") {
      let ir = string.str_to_int(string.str_slice(p, 2, p.len()));
      match ir {
        Ok(v) => {
          iters = v;
        },
        Err(_) => {
          iters = 0;
        },
      }
    } elif string.str_starts_with(p, "e=") {
      err_msg = string.str_slice(p, 2, p.len());
    }
    i = i + 1;
  }
  if err_msg.len() > 0 {
    return Err(err_auth(string.str_concat("SCRAM server error: ", err_msg)));
  }
  if nonce.len() == 0 || salt.len() == 0 || iters <= 0 {
    return Err(err_auth("malformed SCRAM server-first message"));
  }
  return Ok(ScramServerFirst{ nonce: nonce; salt_b64: salt; iterations: iters });
}

fn salted_password_bytes(password: Str, salt_b64: Str, iterations: Int) -> Result[Vec[UInt8], PgError] {
  let dr = encoding.base64_decode(salt_b64);
  match dr {
    Ok(salt) => {
      if salt.len() == 0 {
        return Err(err_auth("empty SCRAM salt"));
      }
      return Ok(crypto.pbkdf2(password, &salt, iterations, 32));
    },
    Err(_) => {
      return Err(err_auth("invalid base64 SCRAM salt"));
    },
  }
}

/// SCRAM client-final computation result: the exact message to send plus the
/// expected server signature (base64) to verify the server-final message.
pub type ScramClientFinal = {
  message: Str;
  server_sig_b64: Str;
}

/// Compute the client-final message for a server-first message.
/// `client_first_bare` is the value previously produced by
/// `scram_client_first_bare`; `client_nonce` is the local nonce. The
/// combined server nonce must extend the client nonce (RFC 5802 check).
pub fn scram_client_final(password: Str, client_first_bare: Str, client_nonce: Str, server_first_text: Str) -> Result[ScramClientFinal, PgError] {
  let pr = scram_parse_server_first(server_first_text);
  var sf_nonce = "";
  var salt = "";
  var iters = 0;
  match pr {
    Ok(sf) => {
      sf_nonce = sf.nonce;
      salt = sf.salt_b64;
      iters = sf.iterations;
    },
    Err(e) => {
      return Err(e);
    },
  }
  if !string.str_starts_with(sf_nonce, client_nonce) {
    return Err(err_auth("SCRAM server nonce does not extend the client nonce"));
  }
  let sp_r = salted_password_bytes(password, salt, iters);
  var sp = Vec[UInt8].new();
  match sp_r {
    Ok(v) => {
      sp = v;
    },
    Err(e) => {
      return Err(e);
    },
  }
  let client_key = crypto.hmac_sha256(&sp, &bytes_of_str("Client Key"));
  let stored_key = crypto.sha256(&client_key);
  let final_no_proof = string.str_concat("c=biws,r=", sf_nonce);
  let auth_message = string.str_concat(
    string.str_concat(
      string.str_concat(client_first_bare, ","),
      string.str_concat(server_first_text, ",")),
    final_no_proof);
  let client_sig = crypto.hmac_sha256(&stored_key, &bytes_of_str(auth_message));
  let proof = xor_bytes(&client_key, &client_sig);
  let message = string.str_concat(
    string.str_concat(final_no_proof, ",p="),
    encoding.base64_encode(&proof));
  let server_key = crypto.hmac_sha256(&sp, &bytes_of_str("Server Key"));
  let server_sig = crypto.hmac_sha256(&server_key, &bytes_of_str(auth_message));
  return Ok(ScramClientFinal{
    message: message;
    server_sig_b64: encoding.base64_encode(&server_sig);
  });
}

/// Verify a server-final message ("v=<b64>"): the signature must equal the
/// expected value computed by `scram_client_final`.
pub fn scram_verify_server_final(text: Str, expected_sig_b64: Str) -> Result[Unit, PgError] {
  if string.str_starts_with(text, "e=") {
    return Err(err_auth(string.str_concat("SCRAM server error: ", string.str_slice(text, 2, text.len()))));
  }
  if !string.str_starts_with(text, "v=") {
    return Err(err_auth("malformed SCRAM server-final message"));
  }
  let v = string.str_slice(text, 2, text.len());
  if string.str_compare(v, expected_sig_b64) != 0 {
    return Err(err_auth("SCRAM server signature mismatch"));
  }
  return Ok(());
}

// ------------------------------------------------ server-side check helpers
// (exported so the conformance suite's scripted server can verify the exact
// bytes the client produced, and any backend can reuse the same primitives)

/// Check a base64 client proof against the salted-password computation.
pub fn scram_verify_proof_b64(password: Str, salt_b64: Str, iterations: Int, auth_message: Str, proof_b64: Str) -> Bool {
  let sp_r = salted_password_bytes(password, salt_b64, iterations);
  var sp = Vec[UInt8].new();
  match sp_r {
    Ok(v) => {
      sp = v;
    },
    Err(_) => {
      return false;
    },
  }
  let client_key = crypto.hmac_sha256(&sp, &bytes_of_str("Client Key"));
  let stored_key = crypto.sha256(&client_key);
  let client_sig = crypto.hmac_sha256(&stored_key, &bytes_of_str(auth_message));
  let expected = xor_bytes(&client_key, &client_sig);
  let dr = encoding.base64_decode(proof_b64);
  match dr {
    Ok(proof) => {
      return bytes_eq(&expected, &proof);
    },
    Err(_) => {
      return false;
    },
  }
}

/// Base64 server-signature for an auth_message (the scripted test server
/// sends this as its server-final message).
pub fn scram_server_signature_b64(password: Str, salt_b64: Str, iterations: Int, auth_message: Str) -> Str {
  let sp_r = salted_password_bytes(password, salt_b64, iterations);
  var sp = Vec[UInt8].new();
  match sp_r {
    Ok(v) => {
      sp = v;
    },
    Err(_) => {
      return "";
    },
  }
  let server_key = crypto.hmac_sha256(&sp, &bytes_of_str("Server Key"));
  let sig = crypto.hmac_sha256(&server_key, &bytes_of_str(auth_message));
  return encoding.base64_encode(&sig);
}
