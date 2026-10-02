// XIOM -- xiom.web3.contract: function selectors and minimal ABI words
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Solidity ABI subset: every statically-sized value is one 32-byte
// big-endian word. Supported: uint256 (non-negative), int256 (two's
// complement, sign-extended), bool, address (20 bytes right-aligned) and
// pre-encoded 32-byte word arrays / call data. A selector is the first 4
// bytes of keccak256 over a canonical signature. Dynamic ABI types are out
// of scope; decoded 256-bit values must fit the signed 64-bit Int range.

module xiom.web3.contract

use xiom.string;
use xiom.encoding.hex;
use xiom.web3.keccak;

/// First 4 bytes of keccak256 over a canonical signature such as
/// "transfer(address,uint256)" (printable ASCII, no spaces, balanced
/// parentheses, name before the argument list, trailing ')').
pub fn contract_selector(signature: Str) -> Result[Vec[UInt8], Str] {
  let n = string.str_len(signature);
  if n < 3 {
    return Err("web3: signature must be a non-empty function signature");
  }
  var opens = 0;
  var closes = 0;
  var first_open = -1;
  var i = 0;
  while i < n {
    let b: Int = (string.byte_at(signature, i) as Int) & 0xFF;
    if b < 33 || b > 126 {
      return Err("web3: signature must be printable ASCII without spaces");
    }
    if b == 40 {
      opens = opens + 1;
      if first_open < 0 { first_open = i; }
    }
    if b == 41 {
      closes = closes + 1;
      if closes > opens {
        return Err("web3: signature has unbalanced parentheses");
      }
    }
    i = i + 1;
  }
  if opens == 0 {
    return Err("web3: signature has no argument list");
  }
  if opens != closes {
    return Err("web3: signature has unbalanced parentheses");
  }
  let last: Int = (string.byte_at(signature, n - 1) as Int) & 0xFF;
  if last != 41 {
    return Err("web3: signature must end with ')'");
  }
  if first_open <= 0 {
    return Err("web3: signature must start with a function name");
  }
  let sb = _ctr_str_bytes(signature);
  let h = keccak.keccak256(&sb);
  var sel = Vec[UInt8].new();
  var k = 0;
  while k < 4 {
    let b: UInt8 = h[k];
    sel.push(b);
    k = k + 1;
  }
  return Ok(sel);
}

/// `0x` + lowercase hex of the 4-byte selector.
pub fn contract_selector_hex(signature: Str) -> Result[Str, Str] {
  let sr = contract_selector(signature);
  if !sr.is_ok {
    return Err(sr.error);
  }
  let sel: Vec[UInt8] = sr.value;
  let h = hex.hex_encode(&sel);
  return Ok("0x" + h);
}

// Bytes of a Str, in order (local helper; xiom.string has no parent-level
// str_bytes).
fn _ctr_str_bytes(s: Str) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  let n = string.str_len(s);
  var i = 0;
  while i < n {
    let b: UInt8 = string.byte_at(s, i);
    v.push(b);
    i = i + 1;
  }
  return v;
}

// Byte `k` of a non-negative Int in big-endian position k (0 = least
// significant), k in 0..7; divisor/modulo only.
fn _ctr_be_byte_u(value: Int, k: Int) -> Int {
  var v = value;
  var i = 0;
  while i < k {
    v = v / 256;
    i = i + 1;
  }
  return v % 256;
}

// Two's-complement byte at big-endian position k for any Int: floor division
// then a non-negative remainder.
fn _ctr_be_byte_s(value: Int, k: Int) -> Int {
  var v = value;
  var i = 0;
  while i < k {
    let r = v % 256;
    var q = v / 256;
    if r != 0 && v < 0 {
      q = q - 1;
    }
    v = q;
    i = i + 1;
  }
  var b = v % 256;
  if b < 0 {
    b = b + 256;
  }
  return b;
}

/// One 32-byte big-endian uint256 word; negative input is
/// `web3: ABI uint value is negative`.
pub fn abi_encode_uint(value: Int) -> Result[Vec[UInt8], Str] {
  if value < 0 {
    return Err("web3: ABI uint value is negative");
  }
  var out = Vec[UInt8].new();
  var i = 0;
  while i < 24 {
    out.push(0 as UInt8);
    i = i + 1;
  }
  var k = 7;
  while k >= 0 {
    let b: Int = _ctr_be_byte_u(value, k);
    out.push(b as UInt8);
    k = k - 1;
  }
  return Ok(out);
}

/// One 32-byte two's-complement int256 word (sign-extended); infallible.
pub fn abi_encode_int(value: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var sign: Int = 0;
  if value < 0 {
    sign = 255;
  }
  var i = 0;
  while i < 24 {
    out.push(sign as UInt8);
    i = i + 1;
  }
  var k = 7;
  while k >= 0 {
    let b: Int = _ctr_be_byte_s(value, k);
    out.push(b as UInt8);
    k = k - 1;
  }
  return out;
}

/// One 32-byte bool word: 31 zero bytes, then 0 or 1.
pub fn abi_encode_bool(value: Bool) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < 31 {
    out.push(0 as UInt8);
    i = i + 1;
  }
  if value {
    out.push(1 as UInt8);
  } else {
    out.push(0 as UInt8);
  }
  return out;
}

/// One 32-byte address word: 12 zero bytes then the 20 address bytes; other
/// lengths are `web3: ABI address value must be 20 bytes`.
pub fn abi_encode_address(bytes: &Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  if bytes.len() != 20 {
    return Err("web3: ABI address value must be 20 bytes");
  }
  var out = Vec[UInt8].new();
  var i = 0;
  while i < 12 {
    out.push(0 as UInt8);
    i = i + 1;
  }
  i = 0;
  while i < 20 {
    let b: UInt8 = bytes[i];
    out.push(b);
    i = i + 1;
  }
  return Ok(out);
}

/// Concatenate pre-encoded ABI words verbatim; every word must be exactly 32
/// bytes (`web3: ABI word must be 32 bytes`). An empty vector is valid (no
/// arguments).
pub fn abi_encode_words(words: &Vec[Vec[UInt8]]) -> Result[Vec[UInt8], Str] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < words.len() {
    let w: Vec[UInt8] = words[i];
    if w.len() != 32 {
      return Err("web3: ABI word must be 32 bytes");
    }
    var j = 0;
    while j < 32 {
      let b: UInt8 = w[j];
      out.push(b);
      j = j + 1;
    }
    i = i + 1;
  }
  return Ok(out);
}

/// Call data: a 4-byte selector (`web3: ABI selector must be 4 bytes`)
/// followed by the concatenated 32-byte argument words.
pub fn abi_encode_call(selector: &Vec[UInt8],
                       words: &Vec[Vec[UInt8]]) -> Result[Vec[UInt8], Str] {
  if selector.len() != 4 {
    return Err("web3: ABI selector must be 4 bytes");
  }
  let wr = abi_encode_words(words);
  if !wr.is_ok {
    return Err(wr.error);
  }
  let tail: Vec[UInt8] = wr.value;
  var out = Vec[UInt8].new();
  var i = 0;
  while i < 4 {
    let b: UInt8 = selector[i];
    out.push(b);
    i = i + 1;
  }
  i = 0;
  while i < tail.len() {
    let b: UInt8 = tail[i];
    out.push(b);
    i = i + 1;
  }
  return Ok(out);
}

/// Copy the 32 bytes at absolute `off` (`web3: ABI word out of bounds` when
/// negative or past the end of `data`).
pub fn abi_read_word(data: &Vec[UInt8], off: Int) -> Result[Vec[UInt8], Str] {
  if off < 0 || off + 32 > data.len() {
    return Err("web3: ABI word out of bounds");
  }
  var out = Vec[UInt8].new();
  var i = 0;
  while i < 32 {
    let b: UInt8 = data[off + i];
    out.push(b);
    i = i + 1;
  }
  return Ok(out);
}

/// Decode one 32-byte word as uint256 into the signed 64-bit Int range.
/// Errors: `web3: ABI word must be 32 bytes`,
/// `web3: ABI uint word does not fit Int`.
pub fn abi_decode_uint_word(word: &Vec[UInt8]) -> Result[Int, Str] {
  if word.len() != 32 {
    return Err("web3: ABI word must be 32 bytes");
  }
  var i = 0;
  while i < 24 {
    let b: Int = (word[i] as Int) & 0xFF;
    if b != 0 {
      return Err("web3: ABI uint word does not fit Int");
    }
    i = i + 1;
  }
  let top: Int = (word[24] as Int) & 0xFF;
  if top >= 128 {
    return Err("web3: ABI uint word does not fit Int");
  }
  var v: Int = 0;
  var j = 24;
  while j < 32 {
    let b: Int = (word[j] as Int) & 0xFF;
    v = v * 256 + b;
    j = j + 1;
  }
  return Ok(v);
}

/// Decode one 32-byte word as an address: bytes 0..11 must be zero
/// (`web3: ABI address word is not right-aligned`), then 20 bytes are copied.
pub fn abi_decode_address_word(word: &Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  if word.len() != 32 {
    return Err("web3: ABI word must be 32 bytes");
  }
  var i = 0;
  while i < 12 {
    let b: Int = (word[i] as Int) & 0xFF;
    if b != 0 {
      return Err("web3: ABI address word is not right-aligned");
    }
    i = i + 1;
  }
  var out = Vec[UInt8].new();
  i = 12;
  while i < 32 {
    let b: UInt8 = word[i];
    out.push(b);
    i = i + 1;
  }
  return Ok(out);
}
