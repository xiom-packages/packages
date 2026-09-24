// XIOM -- xiom.useragent: User-Agent heuristics (browser, version, OS, bot, mobile)
// Port task: create the greenfield xiom.useragent package (pure XIOM, no FFI).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Every UA is normalized once with string.str_lower; all token matching then
// happens byte-wise against that lowercased copy, so matching is
// case-insensitive by construction. All functions are infallible: unknown
// input yields "" or false. See SPEC.md for the token tables, the precedence
// orders and the test plan.
//
// v0.61.3 notes that shaped this module:
//   * Free functions only; every scan is byte-wise over the input Str.
//   * All byte reads are widened to Int space once, in _byte_i
//     (`(string.byte_at(s, i) as Int) & 0xFF`), so no UInt8 value is ever
//     compared against an integer literal.
//   * No Vec values, no lambdas and no match arms: only if/elif/else, while,
//     Bool and Str.
//   * Str equality goes through string.str_compare, so BUG 17 (`==` on Str
//     values read from Vec[Str] elements) cannot apply.

module xiom.useragent

use xiom.string;

// --------------------------------------------------
//  Byte constants (Int space)
// --------------------------------------------------

const _UA_DOT: Int = 46;

// --------------------------------------------------
//  Shared helpers
// --------------------------------------------------

// Read byte i of s widened to Int space (0..255). Every byte read in this
// module goes through here, so byte comparisons never touch UInt8 values.
fn _byte_i(s: Str, i: Int) -> Int {
  return (string.byte_at(s, i) as Int) & 0xFF;
}

// True when byte i of s is an ASCII digit (0x30-0x39).
fn _is_digit_at(s: Str, i: Int) -> Bool {
  let c = _byte_i(s, i);
  return c >= 48 && c <= 57;
}

// Str equality routed through str_compare (BUG 17 safe).
fn _str_eq(a: Str, b: Str) -> Bool {
  return string.str_compare(a, b) == 0;
}

// Byte-wise match of needle at offset `at` of hay. The caller guarantees
// at + needle.len() <= hay.len().
fn _matches_at(hay: Str, at: Int, needle: Str) -> Bool {
  var i = 0;
  while i < needle.len() {
    if _byte_i(hay, at + i) != _byte_i(needle, i) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// Byte index of the first occurrence of needle in hay, or -1 when absent.
// The empty needle yields -1 so callers can distinguish "not found".
fn _find(hay: Str, needle: Str) -> Int {
  let hn = hay.len();
  let nn = needle.len();
  if nn == 0 {
    return -1;
  }
  if nn > hn {
    return -1;
  }
  var i = 0;
  while i + nn <= hn {
    if _matches_at(hay, i, needle) {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// First dotted number at or after start, or "" when none: a run of digits,
// then a '.', then a digit, then further digits and dot-digit pairs. A bare
// integer with no dot does not qualify ("curl/8" yields "").
fn _first_dotted_number(s: Str, start: Int) -> Str {
  let n = s.len();
  var i = start;
  while i < n {
    if _is_digit_at(s, i) {
      var j = i;
      while j < n && _is_digit_at(s, j) {
        j = j + 1;
      }
      if j < n && _byte_i(s, j) == _UA_DOT && j + 1 < n && _is_digit_at(s, j + 1) {
        var k = j;
        while k < n {
          if _is_digit_at(s, k) {
            k = k + 1;
          } elif _byte_i(s, k) == _UA_DOT && k + 1 < n && _is_digit_at(s, k + 1) {
            k = k + 1;
          } else {
            break;
          }
        }
        return string.str_slice(s, i, k);
      }
      i = j;
    } else {
      i = i + 1;
    }
  }
  return "";
}

// Browser token in precedence order, probed against the lowercased UA. The
// order IS the precedence: Edge and Opera ship a Chrome token, so they are
// probed before Chrome, and Chrome is probed before Safari because Chrome
// ships a Safari token.
fn _browser_token(low: Str) -> Str {
  if string.str_contains(low, "edg/") {
    return "edg/";
  }
  if string.str_contains(low, "opr/") {
    return "opr/";
  }
  if string.str_contains(low, "chrome/") {
    return "chrome/";
  }
  if string.str_contains(low, "firefox/") {
    return "firefox/";
  }
  if string.str_contains(low, "safari/") {
    return "safari/";
  }
  if string.str_contains(low, "curl/") {
    return "curl/";
  }
  if string.str_contains(low, "wget/") {
    return "wget/";
  }
  if string.str_contains(low, "python-requests") {
    return "python-requests";
  }
  return "";
}

// Display name for a token from _browser_token; "" for the empty token.
fn _browser_name(tok: Str) -> Str {
  if _str_eq(tok, "edg/") {
    return "Edge";
  }
  if _str_eq(tok, "opr/") {
    return "Opera";
  }
  if _str_eq(tok, "chrome/") {
    return "Chrome";
  }
  if _str_eq(tok, "firefox/") {
    return "Firefox";
  }
  if _str_eq(tok, "safari/") {
    return "Safari";
  }
  if _str_eq(tok, "curl/") {
    return "curl";
  }
  if _str_eq(tok, "wget/") {
    return "wget";
  }
  if _str_eq(tok, "python-requests") {
    return "python-requests";
  }
  return "";
}

// --------------------------------------------------
//  Public API
// --------------------------------------------------

/// Detect the browser family from a User-Agent string (case-insensitive).
/// Params: ua - the raw User-Agent header value.
/// Returns: "Edge", "Opera", "Chrome", "Firefox", "Safari", "curl", "wget" or
/// "python-requests"; "" when no token matches. Precedence: Edge (Edg/) >
/// Opera (OPR/) > Chrome (Chrome/) > Firefox (Firefox/) > Safari (Safari/
/// without Chrome) > curl > wget > python-requests.
/// Error case: none.
/// Complexity: O(ua.len()) per token probe.
pub fn ua_browser(ua: Str) -> Str {
  return _browser_name(_browser_token(string.str_lower(ua)));
}

/// Extract the browser version from a User-Agent string (case-insensitive).
/// Params: ua - the raw User-Agent header value.
/// Returns: the first dotted number after the browser token that
/// ua_browser detects, e.g. "120.0.0.0" from Chrome/120.0.0.0 or "8.4.0"
/// from curl/8.4.0; "" when no browser token is detected, when there is no
/// dotted number after it ("curl/unknown", "curl/8").
/// Error case: none.
/// Complexity: O(ua.len()).
pub fn ua_version(ua: Str) -> Str {
  let low = string.str_lower(ua);
  let tok = _browser_token(low);
  if tok.len() == 0 {
    return "";
  }
  let at = _find(low, tok);
  if at < 0 {
    return "";
  }
  return _first_dotted_number(low, at + tok.len());
}

/// Detect the operating system family from a User-Agent string
/// (case-insensitive).
/// Params: ua - the raw User-Agent header value.
/// Returns: "Windows", "Android", "iOS", "macOS" or "Linux"; "" when unknown.
/// Precedence: Windows (Windows NT) > Android > iOS (iPhone/iPad) > macOS
/// (Mac OS X) > Linux.
/// Error case: none.
/// Complexity: O(ua.len()) per probe.
pub fn ua_os(ua: Str) -> Str {
  let low = string.str_lower(ua);
  if string.str_contains(low, "windows nt") {
    return "Windows";
  }
  if string.str_contains(low, "android") {
    return "Android";
  }
  if string.str_contains(low, "iphone") {
    return "iOS";
  }
  if string.str_contains(low, "ipad") {
    return "iOS";
  }
  if string.str_contains(low, "mac os x") {
    return "macOS";
  }
  if string.str_contains(low, "linux") {
    return "Linux";
  }
  return "";
}

/// True when the User-Agent advertises a known bot, crawler or scripted
/// client (case-insensitive).
/// Params: ua - the raw User-Agent header value.
/// Returns: true when the lowercased UA contains any of "bot", "spider",
/// "crawler", "slurp", "curl/", "wget/", "python-requests" or "headless".
/// Error case: none.
/// Complexity: O(ua.len()) per token probe.
pub fn ua_is_bot(ua: Str) -> Bool {
  let low = string.str_lower(ua);
  if string.str_contains(low, "bot") {
    return true;
  }
  if string.str_contains(low, "spider") {
    return true;
  }
  if string.str_contains(low, "crawler") {
    return true;
  }
  if string.str_contains(low, "slurp") {
    return true;
  }
  if string.str_contains(low, "curl/") {
    return true;
  }
  if string.str_contains(low, "wget/") {
    return true;
  }
  if string.str_contains(low, "python-requests") {
    return true;
  }
  if string.str_contains(low, "headless") {
    return true;
  }
  return false;
}

/// True when the User-Agent advertises a mobile device (case-insensitive).
/// Params: ua - the raw User-Agent header value.
/// Returns: true when the lowercased UA contains any of "mobile", "android",
/// "iphone", "ipad", "ipod" or "windows phone".
/// Error case: none.
/// Complexity: O(ua.len()) per token probe.
pub fn ua_is_mobile(ua: Str) -> Bool {
  let low = string.str_lower(ua);
  if string.str_contains(low, "mobile") {
    return true;
  }
  if string.str_contains(low, "android") {
    return true;
  }
  if string.str_contains(low, "iphone") {
    return true;
  }
  if string.str_contains(low, "ipad") {
    return true;
  }
  if string.str_contains(low, "ipod") {
    return true;
  }
  if string.str_contains(low, "windows phone") {
    return true;
  }
  return false;
}
