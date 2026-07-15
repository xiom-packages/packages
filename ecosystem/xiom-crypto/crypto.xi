// XIOM — Crypto Library — Production OpenSSL FFI Binding
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.

module xiom.crypto

use xiom.encoding;
use xiom.rand;
use xiom.math;

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

type LoopState = { i: Int; }
type BufPtr = { ptr: *UInt8; }
type DataPtr = { ptr: *UInt8; }

// ===========================================================================
// SHA-256 (32-byte output)
// ===========================================================================

pub fn sha256(data: &Vec[Int]) -> Vec[Int]
  requires: data.len() > 0
  ensures: result.len() == 32
{
  var out_buf_raw = unsafe { xiom_alloc(32) };
  var out_buf = BufPtr{ ptr: out_buf_raw };
  if out_buf.ptr == 0 {
    var empty = Vec[Int].new();
    return empty;
  };

  var data_ptr_raw = unsafe { xiom_vec_ptr(data) };
  var data_ptr = DataPtr{ ptr: data_ptr_raw };
  if data_ptr.ptr == 0 {
    unsafe { xiom_free_ptr(out_buf.ptr); }
    var empty = Vec[Int].new();
    return empty;
  };

  var data_len = data.len();
  unsafe { SHA256(data_ptr.ptr, data_len, out_buf.ptr); }

  var result = Vec[Int].new();
  var cur = LoopState{ i: 0; };
  while cur.i < 32 {
    var byte_val = unsafe { xiom_read_byte(out_buf.ptr, cur.i) };
    result.push(byte_val);
    cur = LoopState{ i: cur.i + 1; };
  }

  unsafe { xiom_free_ptr(out_buf.ptr); }
  return result;
}

pub fn sha256_hex(data: &Vec[Int]) -> Str
  requires: data.len() > 0
  ensures: result.len() == 64
{
  var hash = sha256(data);
  return hex_encode(&hash);
}

// ===========================================================================
// SHA-512 (64-byte output)
// ===========================================================================

pub fn sha512(data: &Vec[Int]) -> Vec[Int]
  requires: data.len() > 0
  ensures: result.len() == 64
{
  var out_buf_raw = unsafe { xiom_alloc(64) };
  var out_buf = BufPtr{ ptr: out_buf_raw };
  if out_buf.ptr == 0 {
    var empty = Vec[Int].new();
    return empty;
  };

  var data_ptr_raw = unsafe { xiom_vec_ptr(data) };
  var data_ptr = DataPtr{ ptr: data_ptr_raw };
  if data_ptr.ptr == 0 {
    unsafe { xiom_free_ptr(out_buf.ptr); }
    var empty = Vec[Int].new();
    return empty;
  };

  var data_len = data.len();
  unsafe { SHA512(data_ptr.ptr, data_len, out_buf.ptr); }

  var result = Vec[Int].new();
  var cur = LoopState{ i: 0; };
  while cur.i < 64 {
    var byte_val = unsafe { xiom_read_byte(out_buf.ptr, cur.i) };
    result.push(byte_val);
    cur = LoopState{ i: cur.i + 1; };
  }

  unsafe { xiom_free_ptr(out_buf.ptr); }
  return result;
}

pub fn sha512_hex(data: &Vec[Int]) -> Str
  requires: data.len() > 0
  ensures: result.len() == 128
{
  var hash = sha512(data);
  return hex_encode(&hash);
}

// ===========================================================================
// MD5 (16-byte output)
// ===========================================================================

pub fn md5(data: &Vec[Int]) -> Vec[Int]
  requires: data.len() > 0
  ensures: result.len() == 16
{
  var out_buf_raw = unsafe { xiom_alloc(16) };
  var out_buf = BufPtr{ ptr: out_buf_raw };
  if out_buf.ptr == 0 {
    var empty = Vec[Int].new();
    return empty;
  };

  var data_ptr_raw = unsafe { xiom_vec_ptr(data) };
  var data_ptr = DataPtr{ ptr: data_ptr_raw };
  if data_ptr.ptr == 0 {
    unsafe { xiom_free_ptr(out_buf.ptr); }
    var empty = Vec[Int].new();
    return empty;
  };

  var data_len = data.len();
  unsafe { MD5(data_ptr.ptr, data_len, out_buf.ptr); }

  var result = Vec[Int].new();
  var cur = LoopState{ i: 0; };
  while cur.i < 16 {
    var byte_val = unsafe { xiom_read_byte(out_buf.ptr, cur.i) };
    result.push(byte_val);
    cur = LoopState{ i: cur.i + 1; };
  }

  unsafe { xiom_free_ptr(out_buf.ptr); }
  return result;
}

pub fn md5_hex(data: &Vec[Int]) -> Str
  requires: data.len() > 0
  ensures: result.len() == 32
{
  var hash = md5(data);
  return hex_encode(&hash);
}

// ===========================================================================
// HMAC-SHA256 (RFC 2104) — pure XIOM on top of sha256
// ===========================================================================

pub fn hmac_sha256(data: &Vec[Int], key: &Vec[Int]) -> Vec[Int]
  requires: data.len() > 0
  requires: key.len() > 0
  ensures: result.len() == 32
{
  var block_size = 64;

  var key_work = Vec[Int].new();
  if key.len() > block_size {
    var hashed = sha256(key);
    var ks = LoopState{ i: 0; };
    while ks.i < hashed.len() {
      key_work.push(hashed[ks.i]);
      ks = LoopState{ i: ks.i + 1; };
    };
    var ks2 = LoopState{ i: hashed.len(); };
    while ks2.i < block_size {
      key_work.push(0);
      ks2 = LoopState{ i: ks2.i + 1; };
    };
  } else {
    var ks = LoopState{ i: 0; };
    while ks.i < key.len() {
      key_work.push(key[ks.i]);
      ks = LoopState{ i: ks.i + 1; };
    };
    var ks2 = LoopState{ i: key.len(); };
    while ks2.i < block_size {
      key_work.push(0);
      ks2 = LoopState{ i: ks2.i + 1; };
    };
  };

  var o_key_pad = Vec[Int].new();
  var i_key_pad = Vec[Int].new();
  var ls = LoopState{ i: 0; };
  while ls.i < block_size {
    o_key_pad.push(xiom.math.bit_xor(key_work[ls.i], 0x5c));
    i_key_pad.push(xiom.math.bit_xor(key_work[ls.i], 0x36));
    ls = LoopState{ i: ls.i + 1; };
  };

  var inner_data = Vec[Int].new();
  var ls2 = LoopState{ i: 0; };
  while ls2.i < i_key_pad.len() {
    inner_data.push(i_key_pad[ls2.i]);
    ls2 = LoopState{ i: ls2.i + 1; };
  };
  var ls3 = LoopState{ i: 0; };
  while ls3.i < data.len() {
    inner_data.push(data[ls3.i]);
    ls3 = LoopState{ i: ls3.i + 1; };
  };
  var inner_hash = sha256(&inner_data);

  var outer_data = Vec[Int].new();
  var ls4 = LoopState{ i: 0; };
  while ls4.i < o_key_pad.len() {
    outer_data.push(o_key_pad[ls4.i]);
    ls4 = LoopState{ i: ls4.i + 1; };
  };
  var ls5 = LoopState{ i: 0; };
  while ls5.i < inner_hash.len() {
    outer_data.push(inner_hash[ls5.i]);
    ls5 = LoopState{ i: ls5.i + 1; };
  };
  return sha256(&outer_data);
}

// ===========================================================================
// CSPRNG — random_bytes via OpenSSL RAND_bytes
// ===========================================================================

pub fn random_bytes(count: Int) -> Result[Vec[Int], Str]
  requires: count > 0
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
  requires: data.len() > 0
  ensures: result.len() > 0
{
  return xiom.encoding.base64_encode(data);
}

pub fn base64_decode(input: Str) -> Result[Vec[Int], Str]
  requires: input.len() > 0
{
  return xiom.encoding.base64_decode(input);
}

// ===========================================================================
// Hexadecimal — pure XIOM, no FFI required
// ===========================================================================

pub fn hex_encode(data: &Vec[Int]) -> Str
  requires: data.len() > 0
  ensures: result.len() == data.len() * 2
{
  return xiom.encoding.hex_encode(data);
}

pub fn hex_decode(input: Str) -> Result[Vec[Int], Str]
  requires: input.len() > 0
{
  return xiom.encoding.hex_decode(input);
}
