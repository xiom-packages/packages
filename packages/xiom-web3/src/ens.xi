// XIOM -- xiom.web3.ens: ASCII-subset ENS normalization and namehash
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// EIP-137 namehash with a documented UTS-46-lite normalization: ASCII
// uppercase folds to lowercase; labels use [a-z0-9-] only, never start/end
// with a hyphen, and never use the punycode `xn--` prefix; labels are 1..63
// bytes and names at most 255 bytes. Unicode is rejected, not transliterated
// (full UTS-46/ENSIP-15 is out of scope).

module xiom.web3.ens

use xiom.string;
use xiom.string.builder;
use xiom.encoding.hex;
use xiom.web3.keccak;

/// Maximum label length in bytes (ENS limit; unchanged by normalization).
pub const ENS_MAX_LABEL_LEN: Int = 63;

/// Maximum normalized name length in bytes, dots included.
pub const ENS_MAX_NAME_LEN: Int = 255;

// Bytes of a Str, in order (local helper; xiom.string has no parent-level
// str_bytes).
fn _ens_str_bytes(s: Str) -> Vec[UInt8] {
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

// True for ASCII lower-case letters and digits.
fn _ens_is_ens_char(c: Int) -> Bool {
  if c >= 97 && c <= 122 { return true; }
  if c >= 48 && c <= 57 { return true; }
  return false;
}

/// Normalize an ENS name to the documented ASCII subset: ASCII uppercase
/// folds to lowercase, labels are non-empty and at most 63 bytes, characters
/// are [a-z0-9-] only, no label starts or ends with a hyphen, no punycode
/// `xn--` labels, total length at most 255 bytes. The empty name (root) is
/// accepted and normalizes to "". Unicode/UTS-46 is out of scope and rejected.
pub fn ens_normalize(name: Str) -> Result[Str, Str] {
  let n = string.str_len(name);
  if n == 0 {
    return Ok("");
  }
  var sb = builder.sb_new();
  var i = 0;
  var label_len = 0;
  var last_hyphen = false;
  while i < n {
    let raw: UInt8 = string.byte_at(name, i);
    let b: Int = (raw as Int) & 0xFF;
    var c = b;
    if b >= 65 && b <= 90 {
      c = b + 32;
    }
    if c == 46 {
      if label_len == 0 {
        return Err("web3: ENS name has an empty label");
      }
      if last_hyphen {
        return Err("web3: ENS label starts or ends with a hyphen");
      }
      builder.sb_push_byte(&mut sb, 46 as UInt8);
      label_len = 0;
      last_hyphen = false;
    } else if _ens_is_ens_char(c) || c == 45 {
      if c == 45 && label_len == 0 {
        return Err("web3: ENS label starts or ends with a hyphen");
      }
      builder.sb_push_byte(&mut sb, c as UInt8);
      label_len = label_len + 1;
      if label_len > ENS_MAX_LABEL_LEN {
        return Err("web3: ENS label exceeds 63 bytes");
      }
      last_hyphen = c == 45;
    } else {
      return Err("web3: ENS name contains a character outside the ASCII subset");
    }
    i = i + 1;
  }
  if label_len == 0 {
    return Err("web3: ENS name has an empty label");
  }
  if last_hyphen {
    return Err("web3: ENS label starts or ends with a hyphen");
  }
  let out = builder.sb_to_str(&sb);
  if string.str_len(out) > ENS_MAX_NAME_LEN {
    return Err("web3: ENS name exceeds 255 bytes");
  }
  if string.str_starts_with(out, "xn--") || string.str_contains(out, ".xn--") {
    return Err("web3: ENS punycode labels are outside the documented ASCII subset");
  }
  return Ok(out);
}

/// keccak256 of one normalized label's bytes (EIP-137 labelhash); 32 bytes.
pub fn ens_labelhash(label: Str) -> Result[Vec[UInt8], Str] {
  let nr = ens_normalize(label);
  if !nr.is_ok {
    return Err(nr.error);
  }
  let norm: Str = nr.value;
  if string.str_len(norm) == 0 {
    return Err("web3: ENS label must not be empty");
  }
  if string.str_contains(norm, ".") {
    return Err("web3: ENS label must not contain a dot");
  }
  let lb = _ens_str_bytes(norm);
  return Ok(keccak.keccak256(&lb));
}

/// EIP-137 namehash of a normalized name; 32 bytes. The root hashes to 32
/// zero bytes; labels fold right-to-left:
/// node = keccak256(node ++ keccak256(label)).
pub fn ens_namehash(name: Str) -> Result[Vec[UInt8], Str] {
  let nr = ens_normalize(name);
  if !nr.is_ok {
    return Err(nr.error);
  }
  let norm: Str = nr.value;
  var node = Vec[UInt8].new();
  var z = 0;
  while z < 32 {
    node.push(0 as UInt8);
    z = z + 1;
  }
  let n = string.str_len(norm);
  var end = n;
  while end > 0 {
    var start = end;
    while start > 0 {
      let b: Int = (string.byte_at(norm, start - 1) as Int) & 0xFF;
      if b == 46 { break; }
      start = start - 1;
    }
    let label = string.str_slice(norm, start, end);
    let lb = _ens_str_bytes(label);
    let lh = keccak.keccak256(&lb);
    var buf = Vec[UInt8].new();
    var i = 0;
    while i < 32 {
      let x: UInt8 = node[i];
      buf.push(x);
      i = i + 1;
    }
    i = 0;
    while i < 32 {
      let x: UInt8 = lh[i];
      buf.push(x);
      i = i + 1;
    }
    node = keccak.keccak256(&buf);
    if start == 0 {
      end = 0;
    } else {
      end = start - 1;
    }
  }
  return Ok(node);
}

/// `0x` + lowercase hex of the namehash; same validation as `ens_namehash`.
pub fn ens_namehash_hex(name: Str) -> Result[Str, Str] {
  let nr = ens_namehash(name);
  if !nr.is_ok {
    return Err(nr.error);
  }
  let node: Vec[UInt8] = nr.value;
  let h = hex.hex_encode(&node);
  return Ok("0x" + h);
}
