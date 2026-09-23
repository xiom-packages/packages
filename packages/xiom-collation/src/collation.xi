// XIOM -- xiom.collation: case-insensitive and natural (numeric-aware) collation
// Port task: replace the xiom.collation placeholder with a real, tested,
// pure-XIOM (no FFI) package.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Byte-oriented model: a Str is treated as its UTF-8 byte sequence and every
// comparison walks bytes with unsigned values. collate_compare ignores ASCII
// case in the primary pass and breaks remaining ties case-sensitively with
// lowercase first. collate_natural_compare additionally compares runs of
// ASCII digits by numeric value (then by run length, so "007" < "7"). The
// module is ASCII-oriented: bytes >= 0x80 are never folded and simply compare
// unsigned, which matches code-point order for well-formed UTF-8. See SPEC.md
// for the exact rules and the documented limitations.

module xiom.collation

use xiom.string;

const _COLL_ZERO: Int = 48;
const _COLL_NINE: Int = 57;
const _COLL_UPPER_A: Int = 65;
const _COLL_UPPER_Z: Int = 90;
const _COLL_CASE_DELTA: Int = 32;

// Unsigned byte value at `pos` (0..255).
fn _coll_byte(s: Str, pos: Int) -> Int {
  return (string.byte_at(s, pos) as Int) & 0xFF;
}

// True for ASCII '0'..'9'.
fn _coll_is_digit(b: Int) -> Bool {
  return b >= _COLL_ZERO && b <= _COLL_NINE;
}

// ASCII case fold: 'A'..'Z' -> 'a'..'z', every other byte unchanged.
fn _coll_fold(b: Int) -> Int {
  if b >= _COLL_UPPER_A && b <= _COLL_UPPER_Z {
    return b + _COLL_CASE_DELTA;
  }
  return b;
}

/// Compare `a` and `b` in case-insensitive collation order.
/// Primary pass: bytes compare by unsigned value after folding ASCII
/// uppercase letters to lowercase; when one string is a prefix of the other
/// the shorter sorts first. Tie-break: strings equal after folding are
/// ordered by their first differing raw byte with the larger value first,
/// which puts lowercase before uppercase ("apple" < "Apple").
/// Params: a, b - the strings to compare.
/// Returns: -1 when a sorts before b, 0 when the strings are byte-identical,
/// 1 when a sorts after b. The result is always exactly -1, 0 or 1.
/// Error case: none.
/// Complexity: O(min(|a|, |b|)).
pub fn collate_compare(a: Str, b: Str) -> Int {
  let la = string.str_len(a);
  let lb = string.str_len(b);
  var i = 0;
  while i < la && i < lb {
    let fa = _coll_fold(_coll_byte(a, i));
    let fb = _coll_fold(_coll_byte(b, i));
    if fa < fb {
      return -1;
    }
    if fa > fb {
      return 1;
    }
    i = i + 1;
  }
  if la < lb {
    return -1;
  }
  if la > lb {
    return 1;
  }
  var k = 0;
  while k < la {
    let ba = _coll_byte(a, k);
    let bb = _coll_byte(b, k);
    if ba != bb {
      if ba > bb {
        return -1;
      }
      return 1;
    }
    k = k + 1;
  }
  return 0;
}

/// Exact equality under the collation order: true iff collate_compare is 0.
/// Params: a, b - the strings to test.
/// Returns: true when the strings are byte-identical; false otherwise. Case
/// variants such as "Same" and "same" are ordered, not equal; for
/// case-insensitive equality compare collate_key results with str_compare.
/// Complexity: O(min(|a|, |b|)).
pub fn collate_equal(a: Str, b: Str) -> Bool {
  return collate_compare(a, b) == 0;
}

/// Compare `a` and `b` in natural (numeric-aware) collation order.
/// When the current byte of both strings is an ASCII digit, the two maximal
/// digit runs are compared as integers: leading zeros are ignored, then the
/// run with more significant digits is larger, then digits compare one by
/// one. When the integer values are equal the longer run sorts first, so
/// "007" < "7" and "file007" < "file7". Every other position compares like
/// collate_compare (case-insensitive primary pass, lowercase-first case
/// tie-break when the whole primary comparison is equal); when one string is
/// exhausted first the shorter sorts first.
/// Params: a, b - the strings to compare.
/// Returns: -1, 0 or 1; 0 only when the strings are byte-identical.
/// Error case: none.
/// Complexity: O(|a| + |b|).
pub fn collate_natural_compare(a: Str, b: Str) -> Int {
  let la = string.str_len(a);
  let lb = string.str_len(b);
  var i = 0;
  var j = 0;
  var case_tie: Int = 0;
  while i < la && j < lb {
    let ba = _coll_byte(a, i);
    let bb = _coll_byte(b, j);
    if _coll_is_digit(ba) && _coll_is_digit(bb) {
      var i_end = i;
      while i_end < la && _coll_is_digit(_coll_byte(a, i_end)) {
        i_end = i_end + 1;
      }
      var j_end = j;
      while j_end < lb && _coll_is_digit(_coll_byte(b, j_end)) {
        j_end = j_end + 1;
      }
      var a_sig = i;
      while a_sig < i_end - 1 && _coll_byte(a, a_sig) == _COLL_ZERO {
        a_sig = a_sig + 1;
      }
      var b_sig = j;
      while b_sig < j_end - 1 && _coll_byte(b, b_sig) == _COLL_ZERO {
        b_sig = b_sig + 1;
      }
      let a_digits = i_end - a_sig;
      let b_digits = j_end - b_sig;
      if a_digits < b_digits {
        return -1;
      }
      if a_digits > b_digits {
        return 1;
      }
      var k = 0;
      while k < a_digits {
        let da = _coll_byte(a, a_sig + k);
        let db = _coll_byte(b, b_sig + k);
        if da < db {
          return -1;
        }
        if da > db {
          return 1;
        }
        k = k + 1;
      }
      let a_run = i_end - i;
      let b_run = j_end - j;
      if a_run > b_run {
        return -1;
      }
      if a_run < b_run {
        return 1;
      }
      i = i_end;
      j = j_end;
    } else {
      let fa = _coll_fold(ba);
      let fb = _coll_fold(bb);
      if fa < fb {
        return -1;
      }
      if fa > fb {
        return 1;
      }
      if ba != bb && case_tie == 0 {
        if ba > bb {
          case_tie = -1;
        } else {
          case_tie = 1;
        }
      }
      i = i + 1;
      j = j + 1;
    }
  }
  if i < la {
    return 1;
  }
  if j < lb {
    return -1;
  }
  return case_tie;
}

/// Stable insertion sort by collate_compare.
/// Params: words - the strings to sort; read-only.
/// Returns: a fresh Vec[Str] in case-insensitive collation order. Elements
/// that compare equal (only byte-identical strings can) keep their relative
/// input order; the input vector is not modified.
/// Error case: none.
/// Complexity: O(n^2) comparisons, O(n) element moves.
pub fn collate_sort(words: &Vec[Str]) -> Vec[Str] {
  var out = Vec[Str].new();
  var i = 0;
  while i < words.len() {
    let w = words[i];
    out.push(w);
    var pos = out.len() - 1;
    while pos > 0 && collate_compare(out[pos - 1], w) > 0 {
      out[pos] = out[pos - 1];
      pos = pos - 1;
    }
    out[pos] = w;
    i = i + 1;
  }
  return out;
}

/// Stable insertion sort by collate_natural_compare.
/// Params: words - the strings to sort; read-only.
/// Returns: a fresh Vec[Str] in natural order, so "file2" precedes "file10"
/// and "x007" precedes "x7". Elements that compare equal (only byte-identical
/// strings can) keep their relative input order; the input is not modified.
/// Error case: none.
/// Complexity: O(n^2) comparisons, O(n) element moves.
pub fn collate_natural_sort(words: &Vec[Str]) -> Vec[Str] {
  var out = Vec[Str].new();
  var i = 0;
  while i < words.len() {
    let w = words[i];
    out.push(w);
    var pos = out.len() - 1;
    while pos > 0 && collate_natural_compare(out[pos - 1], w) > 0 {
      out[pos] = out[pos - 1];
      pos = pos - 1;
    }
    out[pos] = w;
    i = i + 1;
  }
  return out;
}

/// Case-folded collation key: an ASCII-lowercased copy of `s`.
/// Params: s - the string to key.
/// Returns: a copy with 'A'..'Z' mapped to 'a'..'z' and every other byte
/// unchanged; the length is preserved. Two strings that differ only by ASCII
/// letter case produce byte-identical keys, and comparing keys with
/// str_compare reproduces the case-insensitive primary order of
/// collate_compare. The lowercase-first case tie-break is not encoded, so
/// collate_compare(collate_key(a), collate_key(b)) is 0 for case variants
/// even when collate_compare(a, b) is not.
/// Error case: none.
/// Complexity: O(|s|).
pub fn collate_key(s: Str) -> Str {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < string.str_len(s) {
    let b = _coll_byte(s, i);
    out.push(_coll_fold(b) as UInt8);
    i = i + 1;
  }
  return Str::from_utf8(out);
}
