// XIOM -- xiom.secret: secret redaction for logs and text
// Port task: replace the xiom.secret placeholder with a real, tested, pure-XIOM
// module (no FFI): Luhn checks, email masking/detection, sensitive-key
// detection and one-pass text redaction.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// What is covered (see SPEC.md for the exact patterns, the order of
// application and the test plan):
//   * secret_luhn_ok: digits-only strings that pass the Luhn checksum;
//   * secret_mask_email: whole-string email addresses masked as a***@b;
//   * secret_contains_email: ASCII email tokens anywhere in the text;
//   * secret_contains_card: Luhn-valid 13..19 digit runs with optional single
//     spaces or dashes between digits;
//   * secret_is_sensitive_key: heuristic key-name screening;
//   * secret_redact: single-pass replacement of PEM private-key blocks,
//     Bearer credentials, AWS AKIA access key ids, 32+ byte token runs,
//     card-like runs and email addresses with a verbatim placeholder.
//
// v0.61.3 notes that shaped this module:
//   * Free functions only; no methods, no lambdas, no Vec[StructType], no
//     Vec[fn] dispatch and no match arms (only if/elif/else and while).
//   * Every byte read goes through _byte_at_i, which widens the UInt8 to Int
//     space once ((string.byte_at(s, i) as Int) & 0xFF), so no UInt8 value is
//     ever compared against an integer literal.
//   * Output bytes are collected in a Vec[UInt8] and materialized with
//     xiom.string.builder.sb_to_str (one allocation per result Str).
//   * Str equality goes through xiom.string.compare.str_compare (BUG 17:
//     `==` on Str values can lower to a pointer comparison).
//   * The public API is error-free by design: every function returns Bool or
//     Str, never fails, and has no error channel.

module xiom.secret

use xiom.string;
use xiom.string.builder;
use xiom.string.compare;

// --------------------------------------------------
//  Byte constants (Int space)
// --------------------------------------------------

const _SEC_TAB: Int = 9;
const _SEC_LF: Int = 10;
const _SEC_CR: Int = 13;
const _SEC_SPACE: Int = 32;
const _SEC_PLUS: Int = 43;
const _SEC_DASH: Int = 45;
const _SEC_DOT: Int = 46;
const _SEC_SLASH: Int = 47;
const _SEC_PERCENT: Int = 37;
const _SEC_EQ: Int = 61;
const _SEC_AT: Int = 64;
const _SEC_UNDERSCORE: Int = 95;

// --------------------------------------------------
//  Shared helpers
// --------------------------------------------------

// Read byte `i` of `s` widened to Int space (0..255). Every byte read in this
// module goes through here, so byte comparisons never touch UInt8 values.
fn _byte_at_i(s: Str, i: Int) -> Int {
  return (string.byte_at(s, i) as Int) & 0xFF;
}

// True for an ASCII digit byte (0x30-0x39).
fn _is_digit(c: Int) -> Bool {
  return c >= 48 && c <= 57;
}

// True for an ASCII uppercase letter byte (0x41-0x5A).
fn _is_upper_alpha(c: Int) -> Bool {
  return c >= 65 && c <= 90;
}

// True for an ASCII lowercase letter byte (0x61-0x7A).
fn _is_lower_alpha(c: Int) -> Bool {
  return c >= 97 && c <= 122;
}

// True for an ASCII letter byte (either case).
fn _is_alpha(c: Int) -> Bool {
  if _is_upper_alpha(c) {
    return true;
  }
  return _is_lower_alpha(c);
}

// True for [A-Za-z0-9].
fn _is_alnum(c: Int) -> Bool {
  if _is_alpha(c) {
    return true;
  }
  return _is_digit(c);
}

// True for the token-run class [A-Za-z0-9+/=_-] used by the long-token rule
// and by the AKIA/token boundary checks.
fn _is_token_char(c: Int) -> Bool {
  if _is_alnum(c) {
    return true;
  }
  if c == _SEC_PLUS {
    return true;
  }
  if c == _SEC_SLASH {
    return true;
  }
  if c == _SEC_EQ {
    return true;
  }
  if c == _SEC_UNDERSCORE {
    return true;
  }
  return c == _SEC_DASH;
}

// True for an email local-part byte: [A-Za-z0-9._%+-].
fn _is_email_local(c: Int) -> Bool {
  if _is_alnum(c) {
    return true;
  }
  if c == _SEC_DOT {
    return true;
  }
  if c == _SEC_UNDERSCORE {
    return true;
  }
  if c == _SEC_PERCENT {
    return true;
  }
  if c == _SEC_PLUS {
    return true;
  }
  return c == _SEC_DASH;
}

// True for an email domain byte: [A-Za-z0-9-].
fn _is_domain_char(c: Int) -> Bool {
  if _is_alnum(c) {
    return true;
  }
  return c == _SEC_DASH;
}

// True for a Bearer credential byte: the token class plus '.'.
fn _is_bearer_char(c: Int) -> Bool {
  if _is_token_char(c) {
    return true;
  }
  return c == _SEC_DOT;
}

// True when `lit` occurs in `s` at byte offset `at`. The caller guarantees
// at + lit.len() <= s.len().
fn _matches_at(s: Str, at: Int, lit: Str) -> Bool {
  let n = lit.len();
  var i = 0;
  while i < n {
    if _byte_at_i(s, at + i) != _byte_at_i(lit, i) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// --------------------------------------------------
//  Email
// --------------------------------------------------

// Byte length of the email token starting at `at`, or 0 when no token starts
// there. ASCII only: 1..64 local bytes [A-Za-z0-9._%+-] with no leading,
// trailing or doubled dot, one `@`, then 1..255 domain bytes of dot-separated
// [A-Za-z0-9-] labels that are non-empty and do not start or end with `-`.
// A trailing dot after the last label is not part of the span.
fn _email_span(s: Str, at: Int) -> Int {
  let n = s.len();
  if at >= n {
    return 0;
  }
  if at > 0 {
    if _is_email_local(_byte_at_i(s, at - 1)) {
      return 0;
    }
  }
  var j = at;
  var local_len = 0;
  var prev_dot = false;
  while j < n {
    let c = _byte_at_i(s, j);
    if !_is_email_local(c) {
      break;
    }
    if c == _SEC_DOT {
      if local_len == 0 {
        return 0;
      }
      if prev_dot {
        return 0;
      }
      prev_dot = true;
    } else {
      prev_dot = false;
    }
    local_len = local_len + 1;
    j = j + 1;
  }
  if local_len == 0 {
    return 0;
  }
  if local_len > 64 {
    return 0;
  }
  if prev_dot {
    return 0;
  }
  if j >= n {
    return 0;
  }
  if _byte_at_i(s, j) != _SEC_AT {
    return 0;
  }
  var k = j + 1;
  var label_start = k;
  var last_good = -1;
  while k < n {
    let c = _byte_at_i(s, k);
    if c == _SEC_DOT {
      if k == label_start {
        break;
      }
      if _byte_at_i(s, k - 1) == _SEC_DASH {
        break;
      }
      if _byte_at_i(s, label_start) == _SEC_DASH {
        break;
      }
      last_good = k;
      label_start = k + 1;
      k = k + 1;
    } elif _is_domain_char(c) {
      k = k + 1;
    } else {
      break;
    }
  }
  if k > label_start {
    if _byte_at_i(s, label_start) != _SEC_DASH {
      if _byte_at_i(s, k - 1) != _SEC_DASH {
        last_good = k;
      }
    }
  }
  if last_good < 0 {
    return 0;
  }
  if last_good - (j + 1) > 255 {
    return 0;
  }
  return last_good - at;
}

/// Mask a whole-string email address, keeping its first byte.
/// Params: s - the candidate address.
/// Returns: `s` with the local part replaced by `***` after the first byte
/// when the ENTIRE string is one email token (`a@b` -> `a***@b`,
/// `alice@example.com` -> `a***@example.com`); any string that is not exactly
/// one email token is returned unchanged (including `@b`, `a@`, `a@b.` and
/// text that merely contains an address).
/// Error case: none.
/// Complexity: O(s.len()).
pub fn secret_mask_email(s: Str) -> Str {
  let n = s.len();
  if n == 0 {
    return s;
  }
  let span = _email_span(s, 0);
  if span != n {
    return s;
  }
  var at = 0;
  while at < span {
    if _byte_at_i(s, at) == _SEC_AT {
      break;
    }
    at = at + 1;
  }
  return string.str_slice(s, 0, 1) + "***" + string.str_slice(s, at, span);
}

/// True when `s` contains an ASCII email token anywhere.
/// Params: s - the text to scan.
/// Returns: true when some token start yields a non-empty email span under the
/// same rules as secret_mask_email (pragmatic ASCII subset; no display names,
/// no quoted local parts, no non-ASCII bytes).
/// Error case: none.
/// Complexity: O(s.len()).
pub fn secret_contains_email(s: Str) -> Bool {
  let n = s.len();
  var i = 0;
  while i < n {
    if _email_span(s, i) > 0 {
      return true;
    }
    i = i + 1;
  }
  return false;
}

// --------------------------------------------------
//  Luhn and card-like runs
// --------------------------------------------------

/// True when a digits-only string passes the Luhn checksum.
/// Params: digits - must consist only of ASCII digits.
/// Returns: true when every byte is 0-9, the string is non-empty, and the
/// Luhn sum (double every second digit from the right, subtract 9 when a
/// doubled digit exceeds 9) is a multiple of 10; false for any non-digit byte
/// (spaces and dashes included) and for the empty string.
/// Error case: none.
/// Complexity: O(digits.len()).
pub fn secret_luhn_ok(digits: Str) -> Bool {
  let n = digits.len();
  if n == 0 {
    return false;
  }
  var sum = 0;
  var double = false;
  var i = n - 1;
  while i >= 0 {
    let c = _byte_at_i(digits, i);
    if !_is_digit(c) {
      return false;
    }
    var d = c - 48;
    if double {
      d = d * 2;
      if d > 9 {
        d = d - 9;
      }
    }
    sum = sum + d;
    double = !double;
    i = i - 1;
  }
  return sum % 10 == 0;
}

// True when a card-like run may start at `i`: the byte is a digit (caller
// checked) and it is not already inside a digit run, i.e. the previous byte is
// neither a digit nor a single space/dash separator that follows a digit.
fn _is_card_run_start(s: Str, i: Int) -> Bool {
  if i == 0 {
    return true;
  }
  let p = _byte_at_i(s, i - 1);
  if _is_digit(p) {
    return false;
  }
  if p == _SEC_SPACE || p == _SEC_DASH {
    if i >= 2 {
      if _is_digit(_byte_at_i(s, i - 2)) {
        return false;
      }
    }
  }
  return true;
}

// Byte length of the maximal card-like run starting at `at` (a digit):
// digits with optional single space/dash separators, each separator only
// between two digits.
fn _card_span(s: Str, at: Int) -> Int {
  let n = s.len();
  var k = at;
  while k < n {
    let c = _byte_at_i(s, k);
    if _is_digit(c) {
      k = k + 1;
    } elif c == _SEC_SPACE || c == _SEC_DASH {
      if k == at {
        break;
      }
      if k + 1 >= n {
        break;
      }
      if !_is_digit(_byte_at_i(s, k + 1)) {
        break;
      }
      if !_is_digit(_byte_at_i(s, k - 1)) {
        break;
      }
      k = k + 2;
    } else {
      break;
    }
  }
  return k - at;
}

// True when the digit run in s[start, end) has 13..19 digits and passes Luhn.
fn _luhn_run(s: Str, start: Int, end: Int) -> Bool {
  var digits = 0;
  var k = start;
  while k < end {
    if _is_digit(_byte_at_i(s, k)) {
      digits = digits + 1;
    }
    k = k + 1;
  }
  if digits < 13 || digits > 19 {
    return false;
  }
  var sum = 0;
  var double = false;
  var i = end - 1;
  while i >= start {
    let c = _byte_at_i(s, i);
    if _is_digit(c) {
      var d = c - 48;
      if double {
        d = d * 2;
        if d > 9 {
          d = d - 9;
        }
      }
      sum = sum + d;
      double = !double;
    }
    i = i - 1;
  }
  return sum % 10 == 0;
}

/// True when `s` contains a card-like run.
/// Params: s - the text to scan.
/// Returns: true when some maximal run of digits with optional single
/// space/dash separators holds 13..19 digits and passes the Luhn checksum
/// (for example `4539 5787 6362 1486` and `4539-5787-6362-1486`); a run of 20+
/// digits, doubled separators, 12 or fewer digits and failed checksums are all
/// false.
/// Error case: none.
/// Complexity: O(s.len()).
pub fn secret_contains_card(s: Str) -> Bool {
  let n = s.len();
  var i = 0;
  while i < n {
    let c = _byte_at_i(s, i);
    if _is_digit(c) {
      if _is_card_run_start(s, i) {
        let run = _card_span(s, i);
        if run <= 0 {
          i = i + 1;
        } else {
          if _luhn_run(s, i, i + run) {
            return true;
          }
          i = i + run;
        }
      } else {
        i = i + 1;
      }
    } else {
      i = i + 1;
    }
  }
  return false;
}

// --------------------------------------------------
//  Sensitive key names
// --------------------------------------------------

/// True when a key/config name looks sensitive.
/// Params: name - the key name to screen (any case).
/// Returns: true when the ASCII-lowercased name contains `password`,
/// `secret`, `token`, `api_key`, `apikey`, `authorization` or `private_key`
/// as a substring; a documented heuristic, not a parser.
/// Error case: none.
/// Complexity: O(name.len()).
pub fn secret_is_sensitive_key(name: Str) -> Bool {
  let lower = string.str_lower(name);
  if string.str_contains(lower, "password") {
    return true;
  }
  if string.str_contains(lower, "secret") {
    return true;
  }
  if string.str_contains(lower, "token") {
    return true;
  }
  if string.str_contains(lower, "api_key") {
    return true;
  }
  if string.str_contains(lower, "apikey") {
    return true;
  }
  if string.str_contains(lower, "authorization") {
    return true;
  }
  return string.str_contains(lower, "private_key");
}

// --------------------------------------------------
//  Redaction patterns
// --------------------------------------------------

// Byte length of the PEM private-key block starting at `at`, or 0 when `at`
// is not the start of a complete block. A block is a line
// `-----BEGIN <label>-----` whose label ends with `PRIVATE KEY`, followed by
// lines until a `-----END <same label>-----` line; the span ends at the last
// byte of the END line (before CR/LF). CRLF line endings are accepted.
fn _pem_span(s: Str, at: Int) -> Int {
  let n = s.len();
  if at > 0 {
    if _byte_at_i(s, at - 1) != _SEC_LF {
      return 0;
    }
  }
  if at + 11 > n {
    return 0;
  }
  if !_matches_at(s, at, "-----BEGIN ") {
    return 0;
  }
  var le = at;
  while le < n && _byte_at_i(s, le) != _SEC_LF {
    le = le + 1;
  }
  var ce = le;
  if ce > at && _byte_at_i(s, ce - 1) == _SEC_CR {
    ce = ce - 1;
  }
  if ce < at + 17 {
    return 0;
  }
  if !_matches_at(s, ce - 5, "-----") {
    return 0;
  }
  let label_at = at + 11;
  let label_len = ce - 5 - label_at;
  if label_len < 11 {
    return 0;
  }
  if !_matches_at(s, ce - 5 - 11, "PRIVATE KEY") {
    return 0;
  }
  var k = le;
  while k < n {
    if _byte_at_i(s, k) != _SEC_LF {
      return 0;
    }
    k = k + 1;
    if k >= n {
      return 0;
    }
    var lend = k;
    while lend < n && _byte_at_i(s, lend) != _SEC_LF {
      lend = lend + 1;
    }
    var cend = lend;
    if cend > k && _byte_at_i(s, cend - 1) == _SEC_CR {
      cend = cend - 1;
    }
    if cend - k >= 9 + label_len + 5 {
      if _matches_at(s, k, "-----END ") {
        if _matches_at(s, cend - 5, "-----") {
          let elabel_at = k + 9;
          let a = string.str_slice(s, label_at, label_at + label_len);
          let b = string.str_slice(s, elabel_at, elabel_at + label_len);
          if compare.str_compare(a, b) == 0 {
            return cend - at;
          }
        }
      }
    }
    k = lend;
  }
  return 0;
}

// Byte length of a `Bearer <token>` credential starting at `at`, or 0. The
// keyword is case-sensitive, must start on a token boundary, and is followed
// by one or more spaces and a non-empty token of [A-Za-z0-9+/=_.-].
fn _bearer_span(s: Str, at: Int) -> Int {
  let n = s.len();
  if at > 0 {
    if _is_token_char(_byte_at_i(s, at - 1)) {
      return 0;
    }
  }
  if at + 6 > n {
    return 0;
  }
  if !_matches_at(s, at, "Bearer") {
    return 0;
  }
  var k = at + 6;
  if k >= n {
    return 0;
  }
  if _byte_at_i(s, k) != _SEC_SPACE {
    return 0;
  }
  while k < n && _byte_at_i(s, k) == _SEC_SPACE {
    k = k + 1;
  }
  let tok_start = k;
  while k < n && _is_bearer_char(_byte_at_i(s, k)) {
    k = k + 1;
  }
  if k == tok_start {
    return 0;
  }
  return k - at;
}

// Byte length of an AWS access key id (`AKIA` + 16 of [0-9A-Z]) starting at
// `at`, or 0. Both token boundaries must be chars outside the token class, so
// a longer alphanumeric run is never partially redacted.
fn _akia_span(s: Str, at: Int) -> Int {
  let n = s.len();
  if at + 20 > n {
    return 0;
  }
  if at > 0 {
    if _is_token_char(_byte_at_i(s, at - 1)) {
      return 0;
    }
  }
  if !_matches_at(s, at, "AKIA") {
    return 0;
  }
  var i = at + 4;
  while i < at + 20 {
    let c = _byte_at_i(s, i);
    if !_is_upper_alpha(c) && !_is_digit(c) {
      return 0;
    }
    i = i + 1;
  }
  if i < n {
    if _is_token_char(_byte_at_i(s, i)) {
      return 0;
    }
  }
  return 20;
}

// Byte length of the maximal token run starting at `at` (caller checked that
// `at` is a run start), over [A-Za-z0-9+/=_-].
fn _token_span(s: Str, at: Int) -> Int {
  let n = s.len();
  var k = at;
  while k < n && _is_token_char(_byte_at_i(s, k)) {
    k = k + 1;
  }
  return k - at;
}

// --------------------------------------------------
//  Redaction
// --------------------------------------------------

/// Redact secrets from `text` in one left-to-right pass.
/// Params: text - the text to sanitize; placeholder - inserted verbatim for
/// every replaced span (it is never rescanned, so a placeholder can itself
/// contain token-like or email-like text).
/// Returns: `text` with, in this priority order at every position, complete
/// PEM private-key blocks, `Bearer <token>` credentials, AWS `AKIA[0-9A-Z]{16}`
/// access key ids, token runs of 32+ bytes of [A-Za-z0-9+/=_-], Luhn-valid
/// 13..19 digit card-like runs, and email addresses replaced by `placeholder`;
/// text with no match is returned byte-for-byte unchanged.
/// Error case: none.
/// Complexity: O(text.len()) amortized; overlapping rules are resolved by the
/// order above.
pub fn secret_redact(text: Str, placeholder: Str) -> Str {
  var out = Vec[UInt8].new();
  let n = text.len();
  var i = 0;
  while i < n {
    let c = _byte_at_i(text, i);
    var span = _pem_span(text, i);
    if span == 0 && c == 66 {
      span = _bearer_span(text, i);
    }
    if span == 0 && c == 65 {
      span = _akia_span(text, i);
    }
    if span == 0 && _is_token_char(c) {
      if i == 0 || !_is_token_char(_byte_at_i(text, i - 1)) {
        let run = _token_span(text, i);
        if run >= 32 {
          span = run;
        }
      }
    }
    if span == 0 && _is_digit(c) {
      if _is_card_run_start(text, i) {
        let run = _card_span(text, i);
        if run > 0 && _luhn_run(text, i, i + run) {
          span = run;
        }
      }
    }
    if span == 0 {
      span = _email_span(text, i);
    }
    if span > 0 {
      builder.sb_push_str(&mut out, placeholder);
      i = i + span;
    } else {
      out.push(string.byte_at(text, i));
      i = i + 1;
    }
  }
  return builder.sb_to_str(&out);
}
