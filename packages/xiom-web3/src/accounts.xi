// XIOM -- xiom.web3.accounts: hex addresses and EIP-55 checksums
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Addresses are 20 bytes rendered as 0x + 40 hex digits. `account_address_
// normalize` is the canonical lowercase form; `account_address_checksum`
// applies EIP-55 (uppercase a hex letter when the matching nibble of
// keccak256(lowercase hex text) is >= 8). Verification accepts all-lowercase
// and all-uppercase input as "not checksummed" (Ok(false)).

module xiom.web3.accounts

use xiom.string;
use xiom.string.compare;
use xiom.string.builder;
use xiom.encoding.hex;
use xiom.web3.keccak;

/// Number of hex digits in a canonical address (without the 0x prefix).
pub const ACCOUNT_ADDRESS_HEX_LEN: Int = 40;

// Bytes of a Str, in order (local helper; xiom.string has no parent-level
// str_bytes).
fn _acct_str_bytes(s: Str) -> Vec[UInt8] {
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

// True when `s` contains at least one uppercase A-F and no lowercase a-f.
fn _acct_is_all_upper_hex(s: Str) -> Bool {
  let n = string.str_len(s);
  var i = 0;
  var saw_letter = false;
  while i < n {
    let c: Int = (string.byte_at(s, i) as Int) & 0xFF;
    if c >= 97 && c <= 102 { return false; }
    if c >= 65 && c <= 70 { saw_letter = true; }
    i = i + 1;
  }
  return saw_letter;
}

/// Decode an address: exactly 40 hex digits, optional 0x/0X prefix, digits
/// case-insensitive. Errors: `web3: address must be 40 hex digits with an
/// optional 0x prefix`, `web3: address contains a non-hex character`.
pub fn account_address_bytes(input: Str) -> Result[Vec[UInt8], Str] {
  let n = string.str_len(input);
  var off = 0;
  if n >= 2 {
    let c0: Int = (string.byte_at(input, 0) as Int) & 0xFF;
    let c1: Int = (string.byte_at(input, 1) as Int) & 0xFF;
    if c0 == 48 && (c1 == 120 || c1 == 88) {
      off = 2;
    }
  }
  if n - off != ACCOUNT_ADDRESS_HEX_LEN {
    return Err("web3: address must be 40 hex digits with an optional 0x prefix");
  }
  let body = string.str_slice(input, off, n);
  let dr = hex.hex_decode(body);
  if !dr.is_ok {
    return Err("web3: address contains a non-hex character");
  }
  let bytes: Vec[UInt8] = dr.value;
  return Ok(bytes);
}

/// Canonical lowercase rendering `0x` + 40 hex digits; same validation as
/// `account_address_bytes`. Mixed-case input is lowercased.
pub fn account_address_normalize(input: Str) -> Result[Str, Str] {
  let br = account_address_bytes(input);
  if !br.is_ok {
    return Err(br.error);
  }
  let b: Vec[UInt8] = br.value;
  let h = hex.hex_encode(&b);
  return Ok("0x" + h);
}

/// 20 raw bytes to the canonical lowercase address; other lengths are
/// `web3: address bytes must be 20 bytes`.
pub fn account_address_from_bytes(bytes: &Vec[UInt8]) -> Result[Str, Str] {
  if bytes.len() != 20 {
    return Err("web3: address bytes must be 20 bytes");
  }
  let h = hex.hex_encode(bytes);
  return Ok("0x" + h);
}

/// EIP-55 mixed-case checksum of an address (validated; output `0x` + 40
/// digits). Uppercases a hex letter when the matching nibble of
/// keccak256(lowercase hex) is >= 8.
pub fn account_address_checksum(input: Str) -> Result[Str, Str] {
  let nr = account_address_normalize(input);
  if !nr.is_ok {
    return Err(nr.error);
  }
  let norm: Str = nr.value;
  let hexpart = string.str_slice(norm, 2, 42);
  let hb = _acct_str_bytes(hexpart);
  let hash = keccak.keccak256(&hb);
  var sb = builder.sb_new();
  builder.sb_push_str(&mut sb, "0x");
  var i = 0;
  while i < 40 {
    let raw: UInt8 = string.byte_at(hexpart, i);
    let c: Int = (raw as Int) & 0xFF;
    var out_c = c;
    if c >= 97 && c <= 102 {
      let hraw: UInt8 = hash[i / 2];
      let h: Int = (hraw as Int) & 0xFF;
      var nib = h & 0x0F;
      if i % 2 == 0 {
        nib = (h >> 4) & 0x0F;
      }
      if nib >= 8 {
        out_c = c - 32;
      }
    }
    builder.sb_push_byte(&mut sb, out_c as UInt8);
    i = i + 1;
  }
  return Ok(builder.sb_to_str(&sb));
}

/// EIP-55 verification: `Ok(true)` only when mixed-case input matches the
/// checksum rendering; all-lowercase/all-uppercase input returns `Ok(false)`
/// (not checksummed, per EIP-55); structural errors are `Err`.
pub fn account_checksum_valid(input: Str) -> Result[Bool, Str] {
  let nr = account_address_normalize(input);
  if !nr.is_ok {
    return Err(nr.error);
  }
  let norm: Str = nr.value;
  if str_compare(input, norm) == 0 {
    return Ok(false);
  }
  if _acct_is_all_upper_hex(input) {
    return Ok(false);
  }
  let cr = account_address_checksum(input);
  if !cr.is_ok {
    return Err(cr.error);
  }
  let ck: Str = cr.value;
  return Ok(str_compare(input, ck) == 0);
}
