// XIOM -- xiom.term: ANSI/VT escape handling (detect, strip, count, truncate)
// Greenfield port task: implement xiom.term as a pure-XIOM module (no FFI, no
// Result channel). See SPEC.md for the sequence grammar, the per-function
// rules and the test plan.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Sequence grammar (pinned in SPEC.md, exercised by tests/test_conformance.xi):
//   * CSI: ESC '[' ... final byte 0x40..0x7E; consumed up to and including the
//     first final byte, or to end of input when unterminated (lenient,
//     documented);
//   * OSC: ESC ']' ... BEL (0x07) or ST (ESC '\'); consumed up to and including
//     the terminator, or to end of input when unterminated;
//   * any other ESC plus one following byte is a two-byte sequence; a trailing
//     ESC with nothing after it is dropped as a degenerate sequence.
// Every ESC byte starts exactly one removed unit, so term_count_escapes is the
// number of units term_strip removes (the number of ESC bytes for well-formed
// input) and term_visible_len is term_strip(s).len().
//
// v0.61.3 notes that shaped this module: free functions only (no self methods,
// no lambdas, no Vec[StructType], no Vec[fn]); no `==` on Str (this module
// performs no Str comparison at all); every Vec/Str byte read is bound with an
// explicit type and widened with `(string.byte_at(...) as Int) & 0xFF`; output
// is accumulated in a Vec[UInt8] and materialized once with
// xiom.string.builder.sb_to_str.

module xiom.term

use xiom.string;
use xiom.string.builder;

// --------------------------------------------------
//  Byte constants (Int space)
// --------------------------------------------------

const _TERM_ESC: Int = 27;
const _TERM_BEL: Int = 7;
const _TERM_DIGIT_0: Int = 48;
const _TERM_DIGIT_9: Int = 57;
const _TERM_COLON: Int = 58;
const _TERM_SEMI: Int = 59;
const _TERM_FINAL_MIN: Int = 64;
const _TERM_FINAL_MAX: Int = 126;
const _TERM_LBRACKET: Int = 91;
const _TERM_BACKSLASH: Int = 92;
const _TERM_RBRACKET: Int = 93;
const _TERM_M: Int = 109;

// --------------------------------------------------
//  Private helpers
// --------------------------------------------------

// End (exclusive) of the escape unit whose ESC byte sits at index `i`.
// The caller guarantees `i < s.len()` and `s[i] == ESC`; the grammar is the
// one pinned in SPEC.md section 2.
fn _seq_end(s: Str, i: Int) -> Int {
  let n = s.len();
  if i + 1 >= n {
    return i + 1;
  }
  let next: Int = (string.byte_at(s, i + 1) as Int) & 0xFF;
  if next == _TERM_LBRACKET {
    var j = i + 2;
    while j < n {
      let f: Int = (string.byte_at(s, j) as Int) & 0xFF;
      if f >= _TERM_FINAL_MIN && f <= _TERM_FINAL_MAX {
        return j + 1;
      }
      j = j + 1;
    }
    return n;
  }
  if next == _TERM_RBRACKET {
    var j = i + 2;
    while j < n {
      let f: Int = (string.byte_at(s, j) as Int) & 0xFF;
      if f == _TERM_BEL {
        return j + 1;
      }
      if f == _TERM_ESC && j + 1 < n && (((string.byte_at(s, j + 1) as Int) & 0xFF) == _TERM_BACKSLASH) {
        return j + 2;
      }
      j = j + 1;
    }
    return n;
  }
  return i + 2;
}

// True when the unit at ESC index `i` is a terminated SGR sequence, i.e. a CSI
// whose final byte is 'm'. Unterminated CSI and all non-CSI units are false.
fn _is_sgr_at(s: Str, i: Int) -> Bool {
  let n = s.len();
  if i + 1 >= n {
    return false;
  }
  if (((string.byte_at(s, i + 1) as Int) & 0xFF) != _TERM_LBRACKET) {
    return false;
  }
  var j = i + 2;
  while j < n {
    let f: Int = (string.byte_at(s, j) as Int) & 0xFF;
    if f >= _TERM_FINAL_MIN && f <= _TERM_FINAL_MAX {
      return f == _TERM_M;
    }
    j = j + 1;
  }
  return false;
}

// True when the byte range [from, s.len()) contains at least one SGR sequence.
fn _has_sgr_from(s: Str, from: Int) -> Bool {
  let n = s.len();
  var i = from;
  while i < n {
    let b: Int = (string.byte_at(s, i) as Int) & 0xFF;
    if b == _TERM_ESC {
      if _is_sgr_at(s, i) {
        return true;
      }
      i = _seq_end(s, i);
    } else {
      i = i + 1;
    }
  }
  return false;
}

// --------------------------------------------------
//  Public API
// --------------------------------------------------

/// True when `s` contains at least one ESC byte (0x1B).
/// Params: s - the raw text, read only.
/// Returns: true when any byte equals 0x1B; false otherwise (including "").
/// Error case: none.
/// Complexity: O(s.len()).
pub fn term_has_escapes(s: Str) -> Bool {
  let n = s.len();
  var i = 0;
  while i < n {
    let b: Int = (string.byte_at(s, i) as Int) & 0xFF;
    if b == _TERM_ESC {
      return true;
    }
    i = i + 1;
  }
  return false;
}

/// True when `s` contains no ESC byte; the complement of term_has_escapes.
/// Params: s - the raw text, read only.
/// Returns: false when any byte equals 0x1B; true otherwise (including "").
/// Error case: none.
/// Complexity: O(s.len()).
pub fn term_is_plain(s: Str) -> Bool {
  if term_has_escapes(s) {
    return false;
  }
  return true;
}

/// Drop every ANSI/VT escape sequence.
/// Params: s - the raw text, read only.
/// Returns: s with every escape unit removed, all other bytes copied verbatim
/// in order. CSI runs to its first final byte (0x40..0x7E) or to end of input
/// when unterminated; OSC runs to BEL or ST or to end of input; any other ESC
/// drops itself plus one following byte; a trailing lone ESC is dropped. No
/// byte is rewritten, so non-ASCII bytes pass through byte-exact.
/// Error case: none.
/// Complexity: O(s.len()).
pub fn term_strip(s: Str) -> Str {
  var out = Vec[UInt8].new();
  let n = s.len();
  var i = 0;
  while i < n {
    let b: Int = (string.byte_at(s, i) as Int) & 0xFF;
    if b == _TERM_ESC {
      i = _seq_end(s, i);
    } else {
      out.push(b as UInt8);
      i = i + 1;
    }
  }
  return builder.sb_to_str(&out);
}

/// Number of escape units term_strip removes.
/// Params: s - the raw text, read only.
/// Returns: the count of units dropped by term_strip: one per CSI, OSC,
/// two-byte ESC sequence and per trailing lone ESC. Because every ESC byte
/// starts exactly one unit, this equals the number of ESC bytes for
/// well-formed input; a malformed byte that ends a unit early (for example an
/// ESC inside a CSI parameter region) still counts once.
/// Error case: none.
/// Complexity: O(s.len()).
pub fn term_count_escapes(s: Str) -> Int {
  let n = s.len();
  var count = 0;
  var i = 0;
  while i < n {
    let b: Int = (string.byte_at(s, i) as Int) & 0xFF;
    if b == _TERM_ESC {
      count = count + 1;
      i = _seq_end(s, i);
    } else {
      i = i + 1;
    }
  }
  return count;
}

/// Byte length of the visible text: term_strip(s).len().
/// Params: s - the raw text, read only.
/// Returns: the number of bytes term_strip(s) would emit.
/// Error case: none.
/// Complexity: O(s.len()).
pub fn term_visible_len(s: Str) -> Int {
  let stripped = term_strip(s);
  return stripped.len();
}

/// Truncate to `n` visible bytes, preserving preceding escapes.
/// Params: s - the raw text, read only; n - the visible byte budget.
/// Returns:
///   * n <= 0: "".
///   * otherwise the first n visible bytes of s, with every escape unit
///     encountered before the cut copied verbatim. Scanning stops immediately
///     after the n-th visible byte; when bytes remain (the cut), they are
///     dropped, and if the dropped remainder contains at least one SGR
///     sequence (a terminated CSI ending in 'm') the result ends with
///     ESC '[' '0' 'm'. No reset is appended when the remainder holds no
///     terminated SGR, and a string that ends at or before the n-th visible
///     byte is returned unchanged (no truncation, no reset).
/// Error case: none.
/// Complexity: O(s.len()).
pub fn term_truncate_visible(s: Str, n: Int) -> Str {
  if n <= 0 {
    return "";
  }
  var out = Vec[UInt8].new();
  let total = s.len();
  var i = 0;
  var visible = 0;
  var cut = false;
  var cut_pos = 0;
  while i < total {
    if visible >= n {
      cut = true;
      cut_pos = i;
      break;
    }
    let b: Int = (string.byte_at(s, i) as Int) & 0xFF;
    if b == _TERM_ESC {
      let end = _seq_end(s, i);
      var k = i;
      while k < end {
        out.push(string.byte_at(s, k));
        k = k + 1;
      }
      i = end;
    } else {
      out.push(b as UInt8);
      visible = visible + 1;
      i = i + 1;
    }
  }
  if cut && _has_sgr_from(s, cut_pos) {
    out.push(_TERM_ESC as UInt8);
    out.push(_TERM_LBRACKET as UInt8);
    out.push(_TERM_DIGIT_0 as UInt8);
    out.push(_TERM_M as UInt8);
  }
  return builder.sb_to_str(&out);
}

/// All SGR parameters from CSI ... 'm' sequences, flattened in order.
/// Params: s - the raw text, read only.
/// Returns: one Vec[Int] holding the parameters of every terminated CSI
/// sequence whose final byte is 'm', in input order. Within a sequence the
/// parameter region is split on ';' and ':'; an empty parameter (or one with
/// no digits) contributes 0; a parameter contributes the value of its leading
/// run of ASCII digits; bytes that are neither digits nor separators are
/// ignored. Unterminated CSI sequences and non-CSI units contribute nothing.
/// A sequence with no parameter bytes (ESC '[' 'm') contributes one 0.
/// Error case: none.
/// Complexity: O(s.len()).
pub fn term_parse_sgr(s: Str) -> Vec[Int] {
  var out = Vec[Int].new();
  let n = s.len();
  var i = 0;
  while i < n {
    let b: Int = (string.byte_at(s, i) as Int) & 0xFF;
    if b == _TERM_ESC && i + 1 < n && (((string.byte_at(s, i + 1) as Int) & 0xFF) == _TERM_LBRACKET) {
      var j = i + 2;
      while j < n {
        let f: Int = (string.byte_at(s, j) as Int) & 0xFF;
        if f >= _TERM_FINAL_MIN && f <= _TERM_FINAL_MAX {
          break;
        }
        j = j + 1;
      }
      if j < n {
        let final_byte: Int = (string.byte_at(s, j) as Int) & 0xFF;
        if final_byte == _TERM_M {
          var value = 0;
          var seen = false;
          var k = i + 2;
          while k < j {
            let p: Int = (string.byte_at(s, k) as Int) & 0xFF;
            if p >= _TERM_DIGIT_0 && p <= _TERM_DIGIT_9 {
              value = value * 10 + (p - _TERM_DIGIT_0);
              seen = true;
            } elif p == _TERM_SEMI || p == _TERM_COLON {
              if seen {
                out.push(value);
              } else {
                out.push(0);
              }
              value = 0;
              seen = false;
            }
            k = k + 1;
          }
          if seen {
            out.push(value);
          } else {
            out.push(0);
          }
        }
        i = j + 1;
      } else {
        i = n;
      }
    } else {
      i = i + 1;
    }
  }
  return out;
}
