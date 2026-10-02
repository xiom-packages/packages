// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// XIOM -- xiom.helm.base: shared primitives for the xiom.helm modules
// Port task: shared limits, byte helpers and validators used by the xiom.helm,
// xiom.helm.release, xiom.helm.repo and xiom.helm.tmpl modules. This module is
// the only shared dependency, so the other modules stay sibling imports (the
// installed compiler v0.62.2 does not resolve a child importing its parent
// module, verified with a minimal probe).

module xiom.helm.base

use xiom.string;
use xiom.string.compare;
use xiom.misc.semver;

// --------------------------------------------------
//  Limits and byte constants
// --------------------------------------------------

/// Maximum chart name length (DNS-subdomain rule, as in Helm).
pub const HELM_CHART_NAME_MAX: Int = 253;
/// Maximum accepted input length for every parse entry point, in bytes.
pub const HELM_MAX_INPUT: Int = 65536;

const _DOT: Int = 46;
const _DASH: Int = 45;
const _SLASH: Int = 47;
const _USCORE: Int = 95;
const _ZERO: Int = 48;
const _NINE: Int = 57;
const _UPPER_A: Int = 65;
const _UPPER_Z: Int = 90;
const _LOWER_A: Int = 97;
const _LOWER_Z: Int = 122;

// --------------------------------------------------
//  Shared primitives (public)
// --------------------------------------------------

/// Byte-exact Str equality through str_compare. Use this instead of `==` for
/// every Str comparison (BUG 17: Vec[Str] element equality mislowers).
pub fn helm_streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

/// True when `s` contains a NUL byte. Parse entry points reject such input.
pub fn helm_has_nul(s: Str) -> Bool {
  var i = 0;
  let n = string.str_len(s);
  while i < n {
    if _byte(s, i) == 0 {
      return true;
    }
    i = i + 1;
  }
  return false;
}

/// DNS-subdomain-ish name rule used for release and chart names: 1..max_len
/// bytes, only lowercase ASCII letters, digits, '-' and '.', and the first
/// and last bytes must be alphanumeric.
pub fn helm_dns_name_valid(name: Str, max_len: Int) -> Bool {
  let n = string.str_len(name);
  if n == 0 || n > max_len {
    return false;
  }
  var i = 0;
  while i < n {
    let c = _byte(name, i);
    let alnum = _is_digit(c) || _is_lower(c);
    if i == 0 || i == n - 1 {
      if !alnum {
        return false;
      }
    } else {
      if !alnum && c != _DASH && c != _DOT {
        return false;
      }
    }
    i = i + 1;
  }
  return true;
}

/// SemVer 2.0.0 validity, delegated to xiom.misc.semver (which also accepts a
/// single leading 'v'/'V', like its documented contract).
pub fn helm_semver_valid(v: Str) -> Bool {
  if string.str_len(v) == 0 {
    return false;
  }
  let r = semver.semver_parse(v);
  match r {
    Some(_) => { return true; },
    None => { return false; },
  }
  return false;
}

/// Values path rule: 1..256 bytes, 1..64 dot-separated non-empty segments;
/// bytes allowed are ASCII letters, digits, '_', '-' and '/'.
pub fn helm_values_path_valid(path: Str) -> Bool {
  let n = string.str_len(path);
  if n == 0 || n > 256 {
    return false;
  }
  let segs = string.str_split(path, ".");
  let sc = segs.len();
  if sc == 0 || sc > 64 {
    return false;
  }
  var i = 0;
  while i < sc {
    let seg: Str = segs[i];
    let sn = string.str_len(seg);
    if sn == 0 {
      return false;
    }
    var j = 0;
    while j < sn {
      if !_is_path_char(_byte(seg, j)) {
        return false;
      }
      j = j + 1;
    }
    i = i + 1;
  }
  return true;
}

// --------------------------------------------------
//  Private byte helpers
// --------------------------------------------------

// Widen and mask one byte of `s` (comparisons on raw UInt8 >= 128 miscompile).
fn _byte(s: Str, i: Int) -> Int {
  return (string.byte_at(s, i) as Int) & 0xFF;
}

fn _is_digit(c: Int) -> Bool {
  return c >= _ZERO && c <= _NINE;
}

fn _is_lower(c: Int) -> Bool {
  return c >= _LOWER_A && c <= _LOWER_Z;
}

fn _is_path_char(c: Int) -> Bool {
  if _is_digit(c) || _is_lower(c) {
    return true;
  }
  if c >= _UPPER_A && c <= _UPPER_Z {
    return true;
  }
  return c == _USCORE || c == _DASH || c == _SLASH;
}
