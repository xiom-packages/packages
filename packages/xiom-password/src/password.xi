// XIOM -- xiom.password: password strength scoring and structural checks
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure XIOM, no FFI, no crypto, no dictionaries. Every rule is a structural
// heuristic over the raw bytes of a Str and is pinned in SPEC.md:
//
// - classes: ASCII lowercase [a-z], uppercase [A-Z], digits [0-9], and
//   printable-ASCII symbols (bytes 33..126 that are not alphanumeric). Space
//   (32), control bytes (0..31 and 127) and every byte of a multi-byte UTF-8
//   sequence (>= 128) belong to no class; they still count toward length and
//   toward runs.
// - longest run: the longest maximal run of byte-identical bytes (0 for the
//   empty string, 1 for any non-empty repeat-free string).
// - score (0..100): min(len * 4, 60) + classes * 10, minus 5 points for every
//   byte beyond the first two of each run of length >= 3, minus 20 when the
//   password is non-empty, all ASCII digits, and shorter than 8 bytes; the
//   result is clamped into 0..100 and the empty password scores 0.
// - feedback: a fixed, ordered list of plain-English suggestions; the vector
//   is empty whenever the score is already 80 or more.
// - common-password check: case-insensitive (ASCII) whole-string match
//   against a caller-supplied list, never against a bundled dictionary.
// - recommend_min: a length/class policy gate with documented clamping.
//
// Every entry point is infallible (Bool/Int/Vec[Str] returns, no Result
// channel). The module compares the Str elements of a caller Vec only through
// xiom.string.compare.str_eq_ignore_case / str_compare (BUG 17: `==` on Str
// values read from Vec[Str] elements lowers to a pointer comparison).

module xiom.password

use xiom.string;
use xiom.string.compare;

// --- ASCII byte classes -----------------------------------------------------

// ASCII lowercase letter [a-z].
fn _is_lower_byte(b: UInt8) -> Bool {
  if b >= 97u8 && b <= 122u8 { return true; }
  return false;
}

// ASCII uppercase letter [A-Z].
fn _is_upper_byte(b: UInt8) -> Bool {
  if b >= 65u8 && b <= 90u8 { return true; }
  return false;
}

// ASCII digit [0-9].
fn _is_digit_byte(b: UInt8) -> Bool {
  if b >= 48u8 && b <= 57u8 { return true; }
  return false;
}

// ASCII letter or digit.
fn _is_alnum_byte(b: UInt8) -> Bool {
  if _is_lower_byte(b) { return true; }
  if _is_upper_byte(b) { return true; }
  if _is_digit_byte(b) { return true; }
  return false;
}

// Printable ASCII symbol: a byte in [33, 126] that is not a letter or a
// digit. Space (32), control bytes (0..31, 127) and non-ASCII bytes (>= 128)
// are not symbols.
fn _is_symbol_byte(b: UInt8) -> Bool {
  if b < 33u8 || b > 126u8 { return false; }
  if _is_alnum_byte(b) { return false; }
  return true;
}

// True when pw holds at least one byte of the class selected by the code:
// 1 = lowercase, 2 = uppercase, 3 = digit, 4 = symbol.
fn _scan_class(pw: Str, cls: Int) -> Bool {
  let len = pw.len();
  var i = 0;
  while i < len {
    let b: UInt8 = byte_at(pw, i);
    if cls == 1 && _is_lower_byte(b) { return true; }
    if cls == 2 && _is_upper_byte(b) { return true; }
    if cls == 3 && _is_digit_byte(b) { return true; }
    if cls == 4 && _is_symbol_byte(b) { return true; }
    i = i + 1;
  }
  return false;
}

// True when pw is non-empty and every byte is an ASCII digit.
fn _is_all_digits(pw: Str) -> Bool {
  let len = pw.len();
  if len == 0 { return false; }
  var i = 0;
  while i < len {
    let b: UInt8 = byte_at(pw, i);
    if !_is_digit_byte(b) { return false; }
    i = i + 1;
  }
  return true;
}

// Total score penalty of every maximal run of byte-identical bytes with
// length L >= 3: 5 points per byte beyond the first two.
fn _run_penalty(pw: Str) -> Int {
  let len = pw.len();
  if len == 0 { return 0; }
  var penalty = 0;
  var run = 1;
  var i = 1;
  while i < len {
    let prev: UInt8 = byte_at(pw, i - 1);
    let cur: UInt8 = byte_at(pw, i);
    if cur == prev {
      run = run + 1;
    } else {
      if run >= 3 { penalty = penalty + (run - 2) * 5; }
      run = 1;
    }
    i = i + 1;
  }
  if run >= 3 { penalty = penalty + (run - 2) * 5; }
  return penalty;
}

// Clamp the requested class count for password_recommend_min into 0..4.
fn _clamp_min_classes(min_classes: Int) -> Int {
  if min_classes < 0 { return 0; }
  if min_classes > 4 { return 4; }
  return min_classes;
}

// --- public API -------------------------------------------------------------

/// True when pw contains at least one ASCII lowercase letter [a-z].
/// Params: pw - the password bytes.
/// Returns: true when any byte is in 97..122. Non-ASCII letters (for example
/// U+00E9 "e-acute", whose UTF-8 bytes are >= 128) do not count.
/// Error case: none.
/// Complexity: O(pw.len()).
pub fn password_has_lower(pw: Str) -> Bool {
  return _scan_class(pw, 1);
}

/// True when pw contains at least one ASCII uppercase letter [A-Z].
/// Params: pw - the password bytes.
/// Returns: true when any byte is in 65..90. Non-ASCII uppercase letters do
/// not count.
/// Error case: none.
/// Complexity: O(pw.len()).
pub fn password_has_upper(pw: Str) -> Bool {
  return _scan_class(pw, 2);
}

/// True when pw contains at least one ASCII digit [0-9].
/// Params: pw - the password bytes.
/// Returns: true when any byte is in 48..57. Non-ASCII digit forms (for
/// example U+FF11) do not count.
/// Error case: none.
/// Complexity: O(pw.len()).
pub fn password_has_digit(pw: Str) -> Bool {
  return _scan_class(pw, 3);
}

/// True when pw contains at least one printable ASCII symbol.
/// Params: pw - the password bytes.
/// Returns: true when any byte is in 33..126 and is not a letter or digit.
/// Space (32), control bytes (0..31 and 127) and non-ASCII bytes (>= 128,
/// including every byte of a multi-byte UTF-8 sequence) are not symbols.
/// Error case: none.
/// Complexity: O(pw.len()).
pub fn password_has_symbol(pw: Str) -> Bool {
  return _scan_class(pw, 4);
}

/// Count how many of the four ASCII classes pw uses.
/// Params: pw - the password bytes.
/// Returns: 0..4, the number of true results among password_has_lower,
/// password_has_upper, password_has_digit and password_has_symbol. The empty
/// string scores 0.
/// Error case: none.
/// Complexity: O(pw.len()).
pub fn password_class_count(pw: Str) -> Int {
  var count = 0;
  if password_has_lower(pw) { count = count + 1; }
  if password_has_upper(pw) { count = count + 1; }
  if password_has_digit(pw) { count = count + 1; }
  if password_has_symbol(pw) { count = count + 1; }
  return count;
}

/// Length of the longest maximal run of byte-identical bytes.
/// Params: pw - the password bytes.
/// Returns: 0 for the empty string; otherwise the largest L such that L
/// consecutive bytes are equal. The comparison is byte equality, so it is
/// case-sensitive and counts spaces and non-ASCII bytes like any other byte.
/// "abc" is 1, "aab" is 2, "aaabbb" is 3.
/// Error case: none.
/// Complexity: O(pw.len()).
pub fn password_longest_run(pw: Str) -> Int {
  let len = pw.len();
  if len == 0 { return 0; }
  var best = 1;
  var run = 1;
  var i = 1;
  while i < len {
    let prev: UInt8 = byte_at(pw, i - 1);
    let cur: UInt8 = byte_at(pw, i);
    if cur == prev {
      run = run + 1;
    } else {
      run = 1;
    }
    if run > best { best = run; }
    i = i + 1;
  }
  return best;
}

/// Heuristic strength score in 0..100.
/// Params: pw - the password bytes.
/// Returns: clamp(min(len * 4, 60) + class_count * 10 - penalties, 0, 100),
/// where penalties are 5 points per byte beyond the first two of every
/// maximal run of identical bytes with length >= 3, plus 20 points when pw
/// is non-empty, every byte is an ASCII digit, and len < 8. The empty
/// password scores 0. This is a structural heuristic, not an entropy or
/// breach-aware estimate; see SPEC.md for the pinned examples.
/// Error case: none.
/// Complexity: O(pw.len()).
pub fn password_score(pw: Str) -> Int {
  let len = pw.len();
  if len == 0 { return 0; }
  var score = len * 4;
  if score > 60 { score = 60; }
  score = score + password_class_count(pw) * 10;
  score = score - _run_penalty(pw);
  if _is_all_digits(pw) && len < 8 { score = score - 20; }
  if score < 0 { score = 0; }
  if score > 100 { score = 100; }
  return score;
}

/// Ordered, human-readable suggestions for improving pw.
/// Params: pw - the password bytes.
/// Returns: an empty vector when password_score(pw) >= 80; otherwise the
/// suggestions whose conditions hold, in this fixed order (each at most
/// once): "Use at least 8 characters" (len < 8), "Add lowercase letters",
/// "Add uppercase letters", "Add digits", "Add symbols" (one per missing
/// class), "Avoid repeated characters" (longest run >= 3), and "Avoid
/// all-digit passwords" (non-empty and every byte an ASCII digit).
/// Error case: none.
/// Complexity: O(pw.len()).
pub fn password_feedback(pw: Str) -> Vec[Str] {
  var out = Vec[Str].new();
  if password_score(pw) >= 80 { return out; }
  if pw.len() < 8 { out.push("Use at least 8 characters"); }
  if !password_has_lower(pw) { out.push("Add lowercase letters"); }
  if !password_has_upper(pw) { out.push("Add uppercase letters"); }
  if !password_has_digit(pw) { out.push("Add digits"); }
  if !password_has_symbol(pw) { out.push("Add symbols"); }
  if password_longest_run(pw) >= 3 { out.push("Avoid repeated characters"); }
  if _is_all_digits(pw) { out.push("Avoid all-digit passwords"); }
  return out;
}

/// Case-insensitive exact match of pw against a caller-supplied list.
/// Params: pw - the password bytes; common - the candidate passwords to
/// compare against, read only. ASCII letters are folded before comparison
/// (str_eq_ignore_case); every other byte compares unchanged.
/// Returns: true when some element of common equals pw under that fold.
/// An empty list never matches, and an empty entry matches only the empty
/// password. The module bundles no dictionary of its own.
/// Error case: none.
/// Complexity: O(common.len() * min(pw.len(), element length)).
pub fn password_is_common(pw: Str, common: &Vec[Str]) -> Bool {
  var i = 0;
  while i < common.len() {
    let candidate: Str = common[i];
    if str_eq_ignore_case(pw, candidate) { return true; }
    i = i + 1;
  }
  return false;
}

/// Policy gate: does pw meet a minimum length and class count?
/// Params: pw - the password bytes; min_len - the required byte length;
/// min_classes - the required number of the four ASCII classes.
/// Returns: true when pw.len() >= min_len and password_class_count(pw) >=
/// min_classes. min_classes is clamped into 0..4, so a request above 4
/// behaves as "all four classes"; a min_len <= 0 imposes no length minimum.
/// Error case: none.
/// Complexity: O(pw.len()).
pub fn password_recommend_min(pw: Str, min_len: Int, min_classes: Int) -> Bool {
  if pw.len() < min_len { return false; }
  if password_class_count(pw) < _clamp_min_classes(min_classes) { return false; }
  return true;
}
