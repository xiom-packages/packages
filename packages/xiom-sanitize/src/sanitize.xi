// XIOM -- xiom.sanitize: byte-oriented input sanitization
// Port task: replace the xiom.sanitize placeholder with a real, tested,
// pure-XIOM package (no FFI).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// What is covered (see SPEC.md for the exact per-function rules, the decision
// list and the test plan):
//   * control characters: replace C0 controls (0x00-0x1F) and DEL (0x7F),
//     preserving LF (0x0A) and TAB (0x09);
//   * ASCII: drop every byte >= 0x80;
//   * whitespace: collapse space/tab runs to one space, strip trailing
//     spaces/tabs before LF, trim the ends, always preserve LF;
//   * allow-list filtering: keep [A-Za-z0-9] plus a caller-supplied byte set;
//   * filenames: replace path-hostile bytes with '_' and strip leading and
//     trailing spaces and dots;
//   * digits: extract ASCII digits only;
//   * slugs: lowercase ASCII letters, non-alphanumeric runs -> one '-', trim
//     '-' at both ends.
//
// v0.61.3 notes that shaped this module:
//   * Free functions only; all scanning is byte-wise over the input Str.
//   * Output bytes are collected in a Vec[UInt8]; replacement text is pushed
//     with xiom.string.builder.sb_push_str, and the final Str is materialized
//     once with sb_to_str (one allocation per result).
//   * Guard predicates work in Int space (`(byte as Int) & 0xFF`) so no UInt8
//     literal arithmetic is needed; byte pushes cast back with `as UInt8`.
//   * No Str equality is performed here, so xiom.string.compare is not
//     imported (BUG 17 concerns Str comparisons in callers/tests).
//
// Infallible by design: every function returns Str; dropped or replaced bytes
// are never reported. All functions are ASCII-centric and byte-oriented.

module xiom.sanitize

use xiom.string;
use xiom.string.builder;

// --------------------------------------------------
//  Byte constants (Int space)
// --------------------------------------------------

const _SAN_TAB: Int = 9;
const _SAN_LF: Int = 10;
const _SAN_SPACE: Int = 32;
const _SAN_DASH: Int = 45;
const _SAN_DOT: Int = 46;
const _SAN_UNDERSCORE: Int = 95;
const _SAN_DEL: Int = 127;

// --------------------------------------------------
//  Shared helpers
// --------------------------------------------------

// True for an ASCII digit byte (0x30-0x39).
fn _is_ascii_digit(b: Int) -> Bool {
  return b >= 48 && b <= 57;
}

// True for an ASCII uppercase letter byte (0x41-0x5A).
fn _is_ascii_upper(b: Int) -> Bool {
  return b >= 65 && b <= 90;
}

// True for an ASCII lowercase letter byte (0x61-0x7A).
fn _is_ascii_lower(b: Int) -> Bool {
  return b >= 97 && b <= 122;
}

// True for an ASCII letter byte (either case).
fn _is_ascii_alpha(b: Int) -> Bool {
  if _is_ascii_upper(b) {
    return true;
  }
  return _is_ascii_lower(b);
}

// True for [A-Za-z0-9].
fn _is_ascii_alnum(b: Int) -> Bool {
  if _is_ascii_digit(b) {
    return true;
  }
  return _is_ascii_alpha(b);
}

// True for a C0 control byte (0x00-0x1F) or DEL (0x7F).
fn _is_control_byte(b: Int) -> Bool {
  if b < 32 {
    return true;
  }
  return b == _SAN_DEL;
}

// Lowercase one ASCII letter byte; every other byte is returned unchanged.
fn _lower_ascii(b: Int) -> Int {
  if _is_ascii_upper(b) {
    return b + 32;
  }
  return b;
}

// True for a byte sanitize_filename must replace: < > : " / \ | ? *.
fn _is_filename_special(b: Int) -> Bool {
  if b == 34 {
    return true;
  }
  if b == 42 {
    return true;
  }
  if b == 47 {
    return true;
  }
  if b == 58 {
    return true;
  }
  if b == 60 {
    return true;
  }
  if b == 62 {
    return true;
  }
  if b == 63 {
    return true;
  }
  if b == 92 {
    return true;
  }
  if b == 124 {
    return true;
  }
  return false;
}

// True when byte `b` occurs anywhere in `set` (byte-wise membership).
fn _byte_in_set(b: Int, set: Str) -> Bool {
  var i = 0;
  while i < set.len() {
    if (((string.byte_at(set, i) as Int) & 0xFF) == b) {
      return true;
    }
    i = i + 1;
  }
  return false;
}

// --------------------------------------------------
//  Public API
// --------------------------------------------------

/// Replace control bytes with `replacement`, keeping LF and TAB.
/// Params: s - the raw text; replacement - the text substituted for each
/// control byte, used verbatim (may be empty or multi-byte).
/// Returns: s with every C0 control byte (0x00-0x1F) and DEL (0x7F) replaced
/// by `replacement`, except LF (0x0A) and TAB (0x09), which pass through.
/// Every other byte (including UTF-8 sequences) passes through byte-exact.
/// Error case: none.
/// Complexity: O(s.len()).
pub fn sanitize_control_chars(s: Str, replacement: Str) -> Str {
  var out = Vec[UInt8].new();
  let n = s.len();
  var i = 0;
  while i < n {
    let b = string.byte_at(s, i);
    let v: Int = (b as Int) & 0xFF;
    if _is_control_byte(v) && v != _SAN_TAB && v != _SAN_LF {
      builder.sb_push_str(&mut out, replacement);
    } else {
      out.push(b);
    }
    i = i + 1;
  }
  return builder.sb_to_str(&out);
}

/// Drop every non-ASCII byte.
/// Params: s - the raw text.
/// Returns: s with all bytes >= 0x80 removed; bytes 0x00-0x7F (including
/// control bytes) pass through unchanged. Non-ASCII input can therefore be
/// truncated mid-character.
/// Error case: none.
/// Complexity: O(s.len()).
pub fn sanitize_ascii(s: Str) -> Str {
  var out = Vec[UInt8].new();
  let n = s.len();
  var i = 0;
  while i < n {
    let b = string.byte_at(s, i);
    if ((b as Int) & 0xFF) < 128 {
      out.push(b);
    }
    i = i + 1;
  }
  return builder.sb_to_str(&out);
}

/// Normalize whitespace: collapse space/tab runs, trim ends, keep LF.
/// Params: s - the raw text.
/// Returns: s with
///   1. every run of spaces (0x20) and tabs (0x09) replaced by a single
///      space,
///   2. a run immediately before LF (0x0A) removed entirely (the LF stays),
///   3. a run at the start or end removed entirely,
///   4. LF preserved; all other bytes (including CR) pass through unchanged.
/// Error case: none.
/// Complexity: O(s.len()).
pub fn sanitize_whitespace(s: Str) -> Str {
  var out = Vec[UInt8].new();
  let n = s.len();
  var pending = false;
  var i = 0;
  while i < n {
    let b = string.byte_at(s, i);
    let v: Int = (b as Int) & 0xFF;
    if v == _SAN_SPACE || v == _SAN_TAB {
      pending = true;
    } elif v == _SAN_LF {
      pending = false;
      out.push(b);
    } else {
      if pending && out.len() > 0 {
        out.push(_SAN_SPACE as UInt8);
      }
      pending = false;
      out.push(b);
    }
    i = i + 1;
  }
  return builder.sb_to_str(&out);
}

/// Keep ASCII alphanumerics plus the caller's allowed bytes; drop the rest.
/// Params: s - the raw text; allow - a set of bytes to keep in addition to
/// [A-Za-z0-9]; membership is byte-wise, so multi-byte characters in `allow`
/// allow each of their UTF-8 bytes.
/// Returns: s with every byte kept that is [A-Za-z0-9] or occurs in `allow`;
/// every other byte (including all bytes >= 0x80 that are not in `allow`) is
/// dropped.
/// Error case: none.
/// Complexity: O(s.len() * allow.len()).
pub fn sanitize_keep(s: Str, allow: Str) -> Str {
  var out = Vec[UInt8].new();
  let n = s.len();
  var i = 0;
  while i < n {
    let b = string.byte_at(s, i);
    let v: Int = (b as Int) & 0xFF;
    if _is_ascii_alnum(v) || _byte_in_set(v, allow) {
      out.push(b);
    }
    i = i + 1;
  }
  return builder.sb_to_str(&out);
}

/// Make text safe to use as a single filename component.
/// Params: s - the raw text.
/// Returns: s with every one of < > : " / \ | ? * and every control byte
/// (0x00-0x1F and 0x7F) replaced by '_', then with leading and trailing
/// spaces (0x20) and dots (0x2E) stripped. Runs of '_' are NOT collapsed and
/// non-ASCII bytes pass through. An empty result becomes "_".
/// Error case: none.
/// Complexity: O(s.len()).
pub fn sanitize_filename(s: Str) -> Str {
  var mapped = Vec[UInt8].new();
  let n = s.len();
  var i = 0;
  while i < n {
    let b = string.byte_at(s, i);
    let v: Int = (b as Int) & 0xFF;
    if _is_control_byte(v) || _is_filename_special(v) {
      mapped.push(_SAN_UNDERSCORE as UInt8);
    } else {
      mapped.push(b);
    }
    i = i + 1;
  }
  let m = mapped.len();
  var start = 0;
  while start < m {
    let c: Int = (mapped[start] as Int) & 0xFF;
    if c == _SAN_SPACE || c == _SAN_DOT {
      start = start + 1;
    } else {
      break;
    }
  }
  var stop = m;
  while stop > start {
    let c: Int = (mapped[stop - 1] as Int) & 0xFF;
    if c == _SAN_SPACE || c == _SAN_DOT {
      stop = stop - 1;
    } else {
      break;
    }
  }
  if start >= stop {
    return "_";
  }
  var out = Vec[UInt8].new();
  var j = start;
  while j < stop {
    out.push(mapped[j]);
    j = j + 1;
  }
  return builder.sb_to_str(&out);
}

/// Extract ASCII digits, dropping everything else.
/// Params: s - the raw text.
/// Returns: s with every byte outside 0x30-0x39 removed; signs, decimal
/// points, separators and non-ASCII bytes are dropped. The result is NOT
/// validated as a number (it may be empty or leading-zero padded).
/// Error case: none.
/// Complexity: O(s.len()).
pub fn sanitize_numeric(s: Str) -> Str {
  var out = Vec[UInt8].new();
  let n = s.len();
  var i = 0;
  while i < n {
    let b = string.byte_at(s, i);
    if _is_ascii_digit((b as Int) & 0xFF) {
      out.push(b);
    }
    i = i + 1;
  }
  return builder.sb_to_str(&out);
}

/// Convert text to a lowercase ASCII slug.
/// Params: s - the raw text.
/// Returns: s with ASCII letters A-Z lowercased, every run of non-alphanumeric
/// bytes (including all bytes >= 0x80) replaced by a single '-', and leading
/// and trailing '-' trimmed. An input with no ASCII alphanumerics yields "".
/// Error case: none.
/// Complexity: O(s.len()).
pub fn sanitize_slug(s: Str) -> Str {
  var out = Vec[UInt8].new();
  let n = s.len();
  var pending_dash = false;
  var i = 0;
  while i < n {
    let b = string.byte_at(s, i);
    let v: Int = (b as Int) & 0xFF;
    if _is_ascii_alnum(v) {
      if pending_dash && out.len() > 0 {
        out.push(_SAN_DASH as UInt8);
      }
      pending_dash = false;
      out.push(_lower_ascii(v) as UInt8);
    } else {
      pending_dash = true;
    }
    i = i + 1;
  }
  return builder.sb_to_str(&out);
}
