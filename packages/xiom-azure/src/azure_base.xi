// XIOM -- xiom.azure.base: shared pure-XIOM helpers for the Azure model
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Small, dependency-free helpers shared by every xiom.azure sibling module:
// byte-safe Str comparison (never `==` on Str), slicing, ASCII lowercasing,
// byte classification, GUID-shape validation and Vec[Str] joining. No state,
// no FFI, no network, no clocks: every function is deterministic.
//
// v0.62.2 discipline: free functions only, no match, no &mut scalar
// parameters, masked byte widening, bounded loops, no Vec[StructType].

module xiom.azure.base

use xiom.string;
use xiom.string.builder;
use xiom.string.compare;

/// True when `a` and `b` are byte-identical.
pub fn azure_streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

/// True when `a` and `b` differ only in ASCII letter case.
pub fn azure_streq_ignore_case(a: Str, b: Str) -> Bool {
  return compare.str_eq_ignore_case(a, b);
}

/// Copy of s[from, min(to, len)) as a fresh Str; a negative `from` clamps to 0.
pub fn azure_substr(s: Str, from: Int, to: Int) -> Str {
  var out = Vec[UInt8].new();
  var i = from;
  if i < 0 {
    i = 0;
  }
  while i < to && i < s.len() {
    out.push(string.byte_at(s, i));
    i = i + 1;
  }
  return builder.sb_to_str(&out);
}

/// First index of byte `ch` in s[from, to), or -1.
pub fn azure_index_of(s: Str, from: Int, to: Int, ch: Int) -> Int {
  var i = from;
  while i < to && i < s.len() {
    let b: Int = (string.byte_at(s, i) as Int) & 0xFF;
    if b == ch {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

/// ASCII-lowercased copy (bytes outside 'A'..'Z' pass through unchanged).
pub fn azure_lower(s: Str) -> Str {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < s.len() {
    let b: Int = (string.byte_at(s, i) as Int) & 0xFF;
    if b >= 65 && b <= 90 {
      out.push((b + 32) as UInt8);
    } else {
      out.push((b & 0xFF) as UInt8);
    }
    i = i + 1;
  }
  return builder.sb_to_str(&out);
}

/// True for ASCII decimal digit bytes ('0'..'9'); other bytes are masked first.
pub fn azure_is_digit(b: Int) -> Bool {
  let x = b & 0xFF;
  return x >= 48 && x <= 57;
}

/// True for ASCII letters (masked to one byte first).
pub fn azure_is_alpha(b: Int) -> Bool {
  let x = b & 0xFF;
  if x >= 65 && x <= 90 {
    return true;
  }
  if x >= 97 && x <= 122 {
    return true;
  }
  return false;
}

/// True for ASCII hex digits (masked to one byte first).
pub fn azure_is_hex_digit(b: Int) -> Bool {
  let x = b & 0xFF;
  if x >= 48 && x <= 57 {
    return true;
  }
  if x >= 65 && x <= 70 {
    return true;
  }
  if x >= 97 && x <= 102 {
    return true;
  }
  return false;
}

/// True when `s` has no byte below 0x20 and no 0x7F (printable ASCII).
pub fn azure_is_printable_ascii(s: Str) -> Bool {
  var i = 0;
  while i < s.len() {
    let b: Int = (string.byte_at(s, i) as Int) & 0xFF;
    if b < 32 || b == 127 {
      return false;
    }
    i = i + 1;
  }
  return true;
}

/// Canonical GUID shape: 36 characters, '-' at indices 8/13/18/23, hex
/// elsewhere (upper- and lowercase both accepted).
pub fn azure_guid_valid(s: Str) -> Bool {
  if s.len() != 36 {
    return false;
  }
  var i = 0;
  while i < 36 {
    let b: Int = (string.byte_at(s, i) as Int) & 0xFF;
    if i == 8 || i == 13 || i == 18 || i == 23 {
      if b != 45 {
        return false;
      }
    } else {
      if !azure_is_hex_digit(b) {
        return false;
      }
    }
    i = i + 1;
  }
  return true;
}

/// Join `items[from .. from+count)` with `sep` (caller guarantees bounds).
pub fn azure_join(items: &Vec[Str], from: Int, count: Int, sep: Str) -> Str {
  var out = "";
  var i = 0;
  while i < count {
    let s: Str = items[from + i];
    if i > 0 {
      out = out + sep;
    }
    out = out + s;
    i = i + 1;
  }
  return out;
}

/// Join every element with `sep`; an empty vector yields "".
pub fn azure_join_all(items: &Vec[Str], sep: Str) -> Str {
  return azure_join(items, 0, items.len(), sep);
}

/// True when every element has the same non-zero length (empty vector: false).
pub fn azure_all_same_len(items: &Vec[Str]) -> Bool {
  let n = items.len();
  if n == 0 {
    return false;
  }
  let first: Str = items[0];
  let width = first.len();
  if width == 0 {
    return false;
  }
  var i = 1;
  while i < n {
    let cur: Str = items[i];
    if cur.len() != width {
      return false;
    }
    i = i + 1;
  }
  return true;
}
