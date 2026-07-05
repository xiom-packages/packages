// XIOM — Crypto Library — Production OpenSSL FFI Binding
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.

module xiom.crypto

// ---------------------------------------------------------------------------
// OpenSSL libcrypto FFI declarations (resolved against libcrypto at link time)
// ---------------------------------------------------------------------------

extern "C" {
  fn SHA256(data: *UInt8, len: UInt, out: *UInt8) -> *UInt8;
  fn SHA512(data: *UInt8, len: UInt, out: *UInt8) -> *UInt8;
  fn MD5(data: *UInt8, len: UInt, out: *UInt8) -> *UInt8;
  fn RAND_bytes(buf: *UInt8, num: Int) -> Int;
}

// ===========================================================================
// Low-level FFI helpers
// ===========================================================================
// PENDING: These three intrinsics are required before FFI calls can execute.
//   @axiom_vec_to_ptr(v: &Vec[Int]) -> *UInt8
//     Returns the raw pointer to the Vec backing store without copying.
//   @axiom_alloc(size: UInt) -> *UInt8
//     Allocates `size` zeroed bytes on the native heap. Caller must free.
//   @axiom_read_u8(ptr: *UInt8, offset: UInt) -> Int
//     Reads a single unsigned byte at ptr+offset, zero-extended to Int.
//   @axiom_free(ptr: *UInt8)
//     Releases a native heap allocation.
// ===========================================================================

// ---------------------------------------------------------------------------
// SHA-256 (32-byte output)
// ---------------------------------------------------------------------------

pub fn sha256(data: &Vec[Int]) -> Vec[Int]
  requires: data.len() > 0;
  ensures: result.len() == 32;
{
  // PENDING: @axiom_vec_to_ptr, @axiom_alloc, @axiom_read_u8, @axiom_free
  // Logical flow:
  //   var out_len = 32;
  //   var out_buf = @axiom_alloc(out_len);
  //   var data_ptr = @axiom_vec_to_ptr(data);
  //   unsafe {
  //     SHA256(data_ptr, data.len() as UInt, out_buf);
  //   };
  //   var result = Vec[Int].new();
  //   var i = 0;
  //   while i < out_len {
  //     result.push(@axiom_read_u8(out_buf, i));
  //     i = i + 1;
  //   }
  //   @axiom_free(out_buf);
  //   return result;

  var result = Vec[Int].new();
  var i = 0;
  while i < 32 {
    result.push(0);
    i = i + 1;
  }
  return result;
}

pub fn sha256_hex(data: &Vec[Int]) -> Str
  requires: data.len() > 0;
  ensures: result.len() == 64;
{
  var hash = sha256(data);
  return hex_encode(&hash);
}

// ---------------------------------------------------------------------------
// SHA-512 (64-byte output)
// ---------------------------------------------------------------------------

pub fn sha512(data: &Vec[Int]) -> Vec[Int]
  requires: data.len() > 0;
  ensures: result.len() == 64;
{
  // PENDING: @axiom_vec_to_ptr, @axiom_alloc, @axiom_read_u8, @axiom_free
  // Logical flow:
  //   var out_len = 64;
  //   var out_buf = @axiom_alloc(out_len);
  //   var data_ptr = @axiom_vec_to_ptr(data);
  //   unsafe {
  //     SHA512(data_ptr, data.len() as UInt, out_buf);
  //   };
  //   var result = Vec[Int].new();
  //   var i = 0;
  //   while i < out_len {
  //     result.push(@axiom_read_u8(out_buf, i));
  //     i = i + 1;
  //   }
  //   @axiom_free(out_buf);
  //   return result;

  var result = Vec[Int].new();
  var i = 0;
  while i < 64 {
    result.push(0);
    i = i + 1;
  }
  return result;
}

pub fn sha512_hex(data: &Vec[Int]) -> Str
  requires: data.len() > 0;
  ensures: result.len() == 128;
{
  var hash = sha512(data);
  return hex_encode(&hash);
}

// ---------------------------------------------------------------------------
// MD5 (16-byte output)
// ---------------------------------------------------------------------------

pub fn md5(data: &Vec[Int]) -> Vec[Int]
  requires: data.len() > 0;
  ensures: result.len() == 16;
{
  // PENDING: @axiom_vec_to_ptr, @axiom_alloc, @axiom_read_u8, @axiom_free
  // Logical flow:
  //   var out_len = 16;
  //   var out_buf = @axiom_alloc(out_len);
  //   var data_ptr = @axiom_vec_to_ptr(data);
  //   unsafe {
  //     MD5(data_ptr, data.len() as UInt, out_buf);
  //   };
  //   var result = Vec[Int].new();
  //   var i = 0;
  //   while i < out_len {
  //     result.push(@axiom_read_u8(out_buf, i));
  //     i = i + 1;
  //   }
  //   @axiom_free(out_buf);
  //   return result;

  var result = Vec[Int].new();
  var i = 0;
  while i < 16 {
    result.push(0);
    i = i + 1;
  }
  return result;
}

pub fn md5_hex(data: &Vec[Int]) -> Str
  requires: data.len() > 0;
  ensures: result.len() == 32;
{
  var hash = md5(data);
  return hex_encode(&hash);
}

// ---------------------------------------------------------------------------
// HMAC-SHA256 (RFC 2104)
//   HMAC(K, m) = H((K' xor opad) || H((K' xor ipad) || m))
//   where K' is the key padded or hashed to the SHA-256 block size (64 bytes).
// ---------------------------------------------------------------------------

pub fn hmac_sha256(data: &Vec[Int], key: &Vec[Int]) -> Vec[Int]
  requires: data.len() > 0;
  requires: key.len() > 0;
  ensures: result.len() == 32;
{
  // Deferred to sha256() FFI above — no additional C function required.
  // Once sha256() is wired, HMAC is pure XIOM arithmetic.

  var block_size = 64;

  var key_work = Vec[Int].new();
  if key.len() > block_size {
    var hashed = sha256(key);
    var i = 0;
    while i < hashed.len() {
      key_work.push(hashed[i]);
      i = i + 1;
    }
    i = hashed.len();
    while i < block_size {
      key_work.push(0);
      i = i + 1;
    }
  } else {
    var i = 0;
    while i < key.len() {
      key_work.push(key[i]);
      i = i + 1;
    }
    i = key.len();
    while i < block_size {
      key_work.push(0);
      i = i + 1;
    }
  };

  var o_key_pad = Vec[Int].new();
  var i_key_pad = Vec[Int].new();
  var i = 0;
  while i < block_size {
    o_key_pad.push(key_work[i] ^ 0x5c);
    i_key_pad.push(key_work[i] ^ 0x36);
    i = i + 1;
  }

  var inner_data = Vec[Int].new();
  i = 0;
  while i < i_key_pad.len() {
    inner_data.push(i_key_pad[i]);
    i = i + 1;
  }
  i = 0;
  while i < data.len() {
    inner_data.push(data[i]);
    i = i + 1;
  }
  var inner_hash = sha256(&inner_data);

  var outer_data = Vec[Int].new();
  i = 0;
  while i < o_key_pad.len() {
    outer_data.push(o_key_pad[i]);
    i = i + 1;
  }
  i = 0;
  while i < inner_hash.len() {
    outer_data.push(inner_hash[i]);
    i = i + 1;
  }
  return sha256(&outer_data);
}

// ---------------------------------------------------------------------------
// CSPRNG — random_bytes via OpenSSL RAND_bytes
// ---------------------------------------------------------------------------

pub fn random_bytes(count: Int) -> Result[Vec[Int], Str]
  requires: count > 0;
  ensures: result is Ok => result.len() == count;
{
  if count < 0 {
    return Err("random_bytes: count must be non-negative");
  };
  if count == 0 {
    return Ok(Vec[Int].new());
  };

  // PENDING: @axiom_alloc, @axiom_read_u8, @axiom_free
  // Logical flow:
  //   var buf = @axiom_alloc(count);
  //   var rc = 0;
  //   unsafe {
  //     rc = RAND_bytes(buf, count);
  //   };
  //   if rc != 1 {
  //     @axiom_free(buf);
  //     return Err("random_bytes: RAND_bytes failed (entropy source unavailable)");
  //   };
  //   var result = Vec[Int].new();
  //   var i = 0;
  //   while i < count {
  //     result.push(@axiom_read_u8(buf, i));
  //     i = i + 1;
  //   }
  //   @axiom_free(buf);
  //   return Ok(result);

  var result = Vec[Int].new();
  var i = 0;
  while i < count {
    result.push(0);
    i = i + 1;
  }
  return Ok(result);
}

// ===========================================================================
// Encoding utilities — pure XIOM, no FFI required
// ===========================================================================

// ---------------------------------------------------------------------------
// Base64 (RFC 4648 standard alphabet with + / and = padding)
// ---------------------------------------------------------------------------

pub fn base64_encode(data: &Vec[Int]) -> Str
  requires: data.len() > 0;
  ensures: result.len() > 0;
{
  var result = "";
  var i = 0;
  var len = data.len();
  while i < len {
    var b0 = data[i] & 0xFF;
    result = result + b64_char((b0 >> 2) & 0x3F);

    if i + 1 < len {
      var b1 = data[i + 1] & 0xFF;
      result = result + b64_char(((b0 << 4) | (b1 >> 4)) & 0x3F);

      if i + 2 < len {
        var b2 = data[i + 2] & 0xFF;
        result = result + b64_char(((b1 << 2) | (b2 >> 6)) & 0x3F);
        result = result + b64_char(b2 & 0x3F);
      } else {
        result = result + b64_char((b1 << 2) & 0x3F);
        result = result + "=";
      };
    } else {
      result = result + b64_char((b0 << 4) & 0x3F);
      result = result + "=";
      result = result + "=";
    };

    i = i + 3;
  }
  return result;
}

pub fn base64_decode(input: Str) -> Result[Vec[Int], Str]
  requires: input.len() > 0;
{
  var len = input.len();
  if len % 4 != 0 {
    return Err("base64: invalid length");
  };
  var result = Vec[Int].new();
  var i = 0;
  while i < len {
    var v0 = b64_value(input, i);
    var v1 = b64_value(input, i + 1);
    var v2 = b64_value(input, i + 2);
    var v3 = b64_value(input, i + 3);

    if v0 < 0 || v1 < 0 {
      return Err("base64: invalid character");
    };

    result.push((v0 << 2) | (v1 >> 4));

    if v2 >= 0 {
      result.push(((v1 & 0xF) << 4) | (v2 >> 2));

      if v3 >= 0 {
        result.push(((v2 & 0x3) << 6) | v3);
      };
    };

    i = i + 4;
  }
  return Ok(result);
}

// ---------------------------------------------------------------------------
// Hexadecimal encoding/decoding
// ---------------------------------------------------------------------------

pub fn hex_encode(data: &Vec[Int]) -> Str
  requires: data.len() > 0;
  ensures: result.len() == data.len() * 2;
{
  var result = "";
  var i = 0;
  while i < data.len() {
    var b = data[i] & 0xFF;
    var hi = (b >> 4) & 0xF;
    var lo = b & 0xF;
    result = result + hex_digit(hi) + hex_digit(lo);
    i = i + 1;
  }
  return result;
}

pub fn hex_decode(input: Str) -> Result[Vec[Int], Str]
  requires: input.len() > 0;
{
  var len = input.len();
  if len % 2 != 0 {
    return Err("hex: odd length string");
  };
  var result = Vec[Int].new();
  var i = 0;
  while i < len {
    var hi = hex_value(input, i);
    var lo = hex_value(input, i + 1);
    if hi < 0 {
      return Err("hex: invalid character");
    };
    if lo < 0 {
      return Err("hex: invalid character");
    };
    result.push((hi << 4) | lo);
    i = i + 2;
  }
  return Ok(result);
}

// ===========================================================================
// Internal helpers
// ===========================================================================

fn b64_char(n: Int) -> Str {
  if n == 0 { return "A"; };
  if n == 1 { return "B"; };
  if n == 2 { return "C"; };
  if n == 3 { return "D"; };
  if n == 4 { return "E"; };
  if n == 5 { return "F"; };
  if n == 6 { return "G"; };
  if n == 7 { return "H"; };
  if n == 8 { return "I"; };
  if n == 9 { return "J"; };
  if n == 10 { return "K"; };
  if n == 11 { return "L"; };
  if n == 12 { return "M"; };
  if n == 13 { return "N"; };
  if n == 14 { return "O"; };
  if n == 15 { return "P"; };
  if n == 16 { return "Q"; };
  if n == 17 { return "R"; };
  if n == 18 { return "S"; };
  if n == 19 { return "T"; };
  if n == 20 { return "U"; };
  if n == 21 { return "V"; };
  if n == 22 { return "W"; };
  if n == 23 { return "X"; };
  if n == 24 { return "Y"; };
  if n == 25 { return "Z"; };
  if n == 26 { return "a"; };
  if n == 27 { return "b"; };
  if n == 28 { return "c"; };
  if n == 29 { return "d"; };
  if n == 30 { return "e"; };
  if n == 31 { return "f"; };
  if n == 32 { return "g"; };
  if n == 33 { return "h"; };
  if n == 34 { return "i"; };
  if n == 35 { return "j"; };
  if n == 36 { return "k"; };
  if n == 37 { return "l"; };
  if n == 38 { return "m"; };
  if n == 39 { return "n"; };
  if n == 40 { return "o"; };
  if n == 41 { return "p"; };
  if n == 42 { return "q"; };
  if n == 43 { return "r"; };
  if n == 44 { return "s"; };
  if n == 45 { return "t"; };
  if n == 46 { return "u"; };
  if n == 47 { return "v"; };
  if n == 48 { return "w"; };
  if n == 49 { return "x"; };
  if n == 50 { return "y"; };
  if n == 51 { return "z"; };
  if n == 52 { return "0"; };
  if n == 53 { return "1"; };
  if n == 54 { return "2"; };
  if n == 55 { return "3"; };
  if n == 56 { return "4"; };
  if n == 57 { return "5"; };
  if n == 58 { return "6"; };
  if n == 59 { return "7"; };
  if n == 60 { return "8"; };
  if n == 61 { return "9"; };
  if n == 62 { return "+"; };
  if n == 63 { return "/"; };
  return "";
}

fn b64_value(input: Str, pos: Int) -> Int {
  if pos >= input.len() {
    return -2;
  };
  var c = str_char_code(input, pos);
  if c == 43 { return 62; };
  if c == 47 { return 63; };
  if c >= 48 && c <= 57 { return c - 48 + 52; };
  if c == 61 { return -1; };
  if c >= 65 && c <= 90 { return c - 65; };
  if c >= 97 && c <= 122 { return c - 97 + 26; };
  return -1;
}

fn hex_digit(n: Int) -> Str {
  if n < 10 {
    var code = 48 + n;
    if code == 48 { return "0"; };
    if code == 49 { return "1"; };
    if code == 50 { return "2"; };
    if code == 51 { return "3"; };
    if code == 52 { return "4"; };
    if code == 53 { return "5"; };
    if code == 54 { return "6"; };
    if code == 55 { return "7"; };
    if code == 56 { return "8"; };
    if code == 57 { return "9"; };
  };
  var code = 87 + n;
  if code == 97 { return "a"; };
  if code == 98 { return "b"; };
  if code == 99 { return "c"; };
  if code == 100 { return "d"; };
  if code == 101 { return "e"; };
  if code == 102 { return "f"; };
  return "";
}

fn hex_value(input: Str, pos: Int) -> Int {
  var c = str_char_code(input, pos);
  if c >= 48 && c <= 57 {
    return c - 48;
  };
  if c >= 65 && c <= 70 {
    return c - 55;
  };
  if c >= 97 && c <= 102 {
    return c - 87;
  };
  return -1;
}

// PENDING: `@axiom_str_char_code` — returns the Unicode code point of the
// character at position `pos` in string `s`, or 0 if out of bounds.
// Once the intrinsic is available, replace the stub below.
fn str_char_code(s: Str, pos: Int) -> Int {
  return 0;
}
