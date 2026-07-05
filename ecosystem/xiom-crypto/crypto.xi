// XIOM — Crypto Library — Production OpenSSL FFI Binding
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.

module xiom.crypto

use xiom.encoding;
use xiom.rand;

// ---------------------------------------------------------------------------
// FFI declarations — OpenSSL libcrypto + XIOM runtime bridge
// ---------------------------------------------------------------------------

extern "C" {
  // OpenSSL libcrypto
  fn SHA256(data: *UInt8, len: Int, out: *UInt8) -> *UInt8;
  fn SHA512(data: *UInt8, len: Int, out: *UInt8) -> *UInt8;
  fn MD5(data: *UInt8, len: Int, out: *UInt8) -> *UInt8;

  // XIOM runtime bridge
  fn xiom_vec_ptr(vec_data: *UInt8, vec_len: Int, vec_cap: Int) -> *UInt8;
  fn xiom_vec_len(vec_data: *UInt8, vec_len: Int, vec_cap: Int) -> Int;
  fn xiom_alloc(size: Int) -> *UInt8;
  fn xiom_free_ptr(ptr: *UInt8);
  fn xiom_read_byte(buf: *UInt8, offset: Int) -> Int;
  fn xiom_write_byte(buf: *UInt8, offset: Int, value: Int);
  fn xiom_copy_from_vec(c_buf: *UInt8, vec_data: *UInt8, vec_len: Int, vec_cap: Int, offset: Int, count: Int);
  fn xiom_copy_to_vec(vec_data: *UInt8, vec_len: Int, vec_cap: Int, c_buf: *UInt8, count: Int);
}

// ===========================================================================
// SHA-256 (32-byte output)
// ===========================================================================

pub fn sha256(data: &Vec[Int]) -> Vec[Int]
  requires: data.len() > 0;
  ensures: result.len() == 32;
{
  var out_buf = unsafe { xiom_alloc(32) };
  if out_buf == 0 {
    var empty = Vec[Int].new();
    return empty;
  };

  var data_ptr = unsafe { xiom_vec_ptr(data) };
  if data_ptr == 0 {
    unsafe { xiom_free_ptr(out_buf); }
    var empty = Vec[Int].new();
    return empty;
  };

  var data_len = data.len();
  unsafe { SHA256(data_ptr, data_len, out_buf); }

  var result = Vec[Int].new();
  var i = 0;
  while i < 32 {
    var byte_val = unsafe { xiom_read_byte(out_buf, i) };
    result.push(byte_val);
    i = i + 1;
  }

  unsafe { xiom_free_ptr(out_buf); }
  return result;
}

pub fn sha256_hex(data: &Vec[Int]) -> Str
  requires: data.len() > 0;
  ensures: result.len() == 64;
{
  var hash = sha256(data);
  return hex_encode(&hash);
}

// ===========================================================================
// SHA-512 (64-byte output)
// ===========================================================================

pub fn sha512(data: &Vec[Int]) -> Vec[Int]
  requires: data.len() > 0;
  ensures: result.len() == 64;
{
  var out_buf = unsafe { xiom_alloc(64) };
  if out_buf == 0 {
    var empty = Vec[Int].new();
    return empty;
  };

  var data_ptr = unsafe { xiom_vec_ptr(data) };
  if data_ptr == 0 {
    unsafe { xiom_free_ptr(out_buf); }
    var empty = Vec[Int].new();
    return empty;
  };

  var data_len = data.len();
  unsafe { SHA512(data_ptr, data_len, out_buf); }

  var result = Vec[Int].new();
  var i = 0;
  while i < 64 {
    var byte_val = unsafe { xiom_read_byte(out_buf, i) };
    result.push(byte_val);
    i = i + 1;
  }

  unsafe { xiom_free_ptr(out_buf); }
  return result;
}

pub fn sha512_hex(data: &Vec[Int]) -> Str
  requires: data.len() > 0;
  ensures: result.len() == 128;
{
  var hash = sha512(data);
  return hex_encode(&hash);
}

// ===========================================================================
// MD5 (16-byte output)
// ===========================================================================

pub fn md5(data: &Vec[Int]) -> Vec[Int]
  requires: data.len() > 0;
  ensures: result.len() == 16;
{
  var out_buf = unsafe { xiom_alloc(16) };
  if out_buf == 0 {
    var empty = Vec[Int].new();
    return empty;
  };

  var data_ptr = unsafe { xiom_vec_ptr(data) };
  if data_ptr == 0 {
    unsafe { xiom_free_ptr(out_buf); }
    var empty = Vec[Int].new();
    return empty;
  };

  var data_len = data.len();
  unsafe { MD5(data_ptr, data_len, out_buf); }

  var result = Vec[Int].new();
  var i = 0;
  while i < 16 {
    var byte_val = unsafe { xiom_read_byte(out_buf, i) };
    result.push(byte_val);
    i = i + 1;
  }

  unsafe { xiom_free_ptr(out_buf); }
  return result;
}

pub fn md5_hex(data: &Vec[Int]) -> Str
  requires: data.len() > 0;
  ensures: result.len() == 32;
{
  var hash = md5(data);
  return hex_encode(&hash);
}

// ===========================================================================
// HMAC-SHA256 (RFC 2104) — pure XIOM on top of sha256
// ===========================================================================

pub fn hmac_sha256(data: &Vec[Int], key: &Vec[Int]) -> Vec[Int]
  requires: data.len() > 0;
  requires: key.len() > 0;
  ensures: result.len() == 32;
{
  var block_size = 64;

  var key_work = Vec[Int].new();
  if key.len() > block_size {
    var hashed = sha256(key);
    var i = 0;
    while i < hashed.len() {
      key_work.push(hashed[i]);
      i = i + 1;
    };
    i = hashed.len();
    while i < block_size {
      key_work.push(0);
      i = i + 1;
    };
  } else {
    var i = 0;
    while i < key.len() {
      key_work.push(key[i]);
      i = i + 1;
    };
    i = key.len();
    while i < block_size {
      key_work.push(0);
      i = i + 1;
    };
  };

  var o_key_pad = Vec[Int].new();
  var i_key_pad = Vec[Int].new();
  var i = 0;
  while i < block_size {
    o_key_pad.push(key_work[i] ^ 0x5c);
    i_key_pad.push(key_work[i] ^ 0x36);
    i = i + 1;
  };

  var inner_data = Vec[Int].new();
  i = 0;
  while i < i_key_pad.len() {
    inner_data.push(i_key_pad[i]);
    i = i + 1;
  };
  i = 0;
  while i < data.len() {
    inner_data.push(data[i]);
    i = i + 1;
  };
  var inner_hash = sha256(&inner_data);

  var outer_data = Vec[Int].new();
  i = 0;
  while i < o_key_pad.len() {
    outer_data.push(o_key_pad[i]);
    i = i + 1;
  };
  i = 0;
  while i < inner_hash.len() {
    outer_data.push(inner_hash[i]);
    i = i + 1;
  };
  return sha256(&outer_data);
}

// ===========================================================================
// CSPRNG — random_bytes via OpenSSL RAND_bytes
// ===========================================================================

pub fn random_bytes(count: Int) -> Result[Vec[Int], Str]
  requires: count > 0;
{
  if count <= 0 {
    return Err("random_bytes: count must be positive");
  };
  return Ok(xiom.rand.random_bytes(count));
}

// ===========================================================================
// Base64 (RFC 4648) — pure XIOM, no FFI required
// ===========================================================================

pub fn base64_encode(data: &Vec[Int]) -> Str
  requires: data.len() > 0;
  ensures: result.len() > 0;
{
  return xiom.encoding.base64_encode(data);
}

pub fn base64_decode(input: Str) -> Result[Vec[Int], Str]
  requires: input.len() > 0;
{
  return xiom.encoding.base64_decode(input);
}

// ===========================================================================
// Hexadecimal — pure XIOM, no FFI required
// ===========================================================================

pub fn hex_encode(data: &Vec[Int]) -> Str
  requires: data.len() > 0;
  ensures: result.len() == data.len() * 2;
{
  return xiom.encoding.hex_encode(data);
}

pub fn hex_decode(input: Str) -> Result[Vec[Int], Str]
  requires: input.len() > 0;
{
  return xiom.encoding.hex_decode(input);
}

