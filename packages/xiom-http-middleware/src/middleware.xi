// XIOM -- xiom.http.middleware: envelope-agnostic HTTP middleware helpers
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Small, deterministic helpers that an HTTP envelope composes over its own
// request/response types: request-id generation and validation, one-line
// access logging, CORS response header lines, CSRF token generation and
// constant-time validation, and an escaped JSON error body with its content
// type. The package is transport- and envelope-free: it never touches the
// network, never parses a request, and keeps no global state; every function
// takes and returns plain values.
//
// What is covered:
//   * middleware_request_id_new / middleware_request_id_valid: 32-char
//     lowercase hex ids from 16 CSPRNG bytes (xiom.crypto), validated by
//     length and charset;
//   * middleware_access_log_line: the exact single-line format
//     `request_id=<id> method=<M> path=<p> status=<s> duration_ms=<d>
//     bytes=<b>`;
//   * middleware_cors_headers: complete CORS "Name: value" lines in fixed
//     order, skipping empty values and non-positive Max-Age;
//   * middleware_csrf_token_new / middleware_csrf_valid: 32-char lowercase
//     hex tokens; validation is constant-time over raw bytes via
//     xiom.crypto.constant_time_compare;
//   * middleware_error_body / middleware_error_content_type: the JSON body
//     `{"error":{"status":<status>,"message":"<escaped>"}}` with minimal
//     JSON string escaping and the `application/json` content type.
//
// Deliberate boundaries: no header parsing or serialization beyond the CORS
// lines above (the caller owns the envelope), no HTML escaping, no log sink,
// no clock (duration_ms is supplied by the caller), no cookie plumbing and no
// token storage; access-log fields are not escaped, so `path` (or any other
// field) must not contain spaces; bytes other than the five escaped ones pass
// through middleware_error_body unchanged.
//
// v0.64.0 notes that shaped this module:
//   * free functions only; helpers are pure and private, state travels in
//     arguments and return values;
//   * every raw byte read via xiom.string.byte_at is widened with
//     `(x as Int) & 0xFF` before comparison (_byte_at_i);
//   * no `==` on Str is used anywhere (this module compares no Str values at
//     all -- equality work is byte- or length-based);
//   * header lines are a plain Vec[Str]; a Vec of (Str, Str) pairs is never
//     used (the live m192 crash class);
//   * every Vec element read is bound to a typed local first.

module xiom.http.middleware

use xiom.crypto;
use xiom.string;

// --------------------------------------------------
//  Byte and formatting helpers
// --------------------------------------------------

// Read byte i of s widened to Int space (0..255). Every byte read in this
// module goes through here, so comparisons never touch raw UInt8 values.
fn _byte_at_i(s: Str, i: Int) -> Int {
  return (string.byte_at(s, i) as Int) & 0xFF;
}

// Lowercase hex character for a nibble value 0..15 (undefined outside that
// range: str_slice then returns an empty or clipped fragment).
fn _hex_digit(d: Int) -> Str {
  return string.str_slice("0123456789abcdef", d, d + 1);
}

// Lowercase hex of a byte vector: two chars per byte, in order.
fn _hex_lower(bytes: &Vec[UInt8]) -> Str {
  var out = "";
  var i = 0;
  while i < bytes.len() {
    let b: UInt8 = bytes[i];
    let v = (b as Int) & 0xFF;
    out = out + _hex_digit(v / 16) + _hex_digit(v % 16);
    i = i + 1;
  }
  return out;
}

// Decimal string of an Int: no leading zeros, "-" prefix for negatives.
// Mirrors the stdlib algorithm (magnitude via truncated division and
// remainder), so Int min renders exactly.
fn _int_to_str(n: Int) -> Str {
  if n == 0 {
    return "0";
  }
  var x = n;
  var neg = false;
  if x < 0 {
    neg = true;
  }
  var out = "";
  while x != 0 {
    var d = x % 10;
    if d < 0 {
      d = 0 - d;
    }
    out = string.str_slice("0123456789", d, d + 1) + out;
    x = x / 10;
  }
  if neg {
    out = "-" + out;
  }
  return out;
}

// The raw bytes of a Str in order (one Vec[UInt8] element per byte).
fn _bytes_of(s: Str) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < s.len() {
    out.push(string.byte_at(s, i));
    i = i + 1;
  }
  return out;
}

// Escape `s` as a minimal JSON string body: backslash, double quote, LF, CR
// and TAB get their two-character escapes; every other byte (including other
// control bytes and raw UTF-8) is copied through unchanged.
fn _escape_json(s: Str) -> Str {
  var out = "";
  var i = 0;
  while i < s.len() {
    let b = _byte_at_i(s, i);
    if b == 92 {
      out = out + "\\\\";
    } else if b == 34 {
      out = out + "\\\"";
    } else if b == 10 {
      out = out + "\\n";
    } else if b == 13 {
      out = out + "\\r";
    } else if b == 9 {
      out = out + "\\t";
    } else {
      out = out + string.str_slice(s, i, i + 1);
    }
    i = i + 1;
  }
  return out;
}

// --------------------------------------------------
//  Request ids
// --------------------------------------------------

/// Generate a new request id: the lowercase hex of 16 CSPRNG bytes, so
/// exactly 32 chars from [0-9a-f].
/// Returns: Ok(id) with id.len() == 32 and every byte in [0-9a-f].
/// Error case: Err("middleware: id generation failed") when the CSPRNG does
/// not return exactly 16 bytes (not observed on supported platforms).
/// Complexity: O(1).
pub fn middleware_request_id_new() -> Result[Str, Str] {
  let bytes = crypto.secure_random_bytes(16);
  if bytes.len() != 16 {
    return Err("middleware: id generation failed");
  }
  return Ok(_hex_lower(&bytes));
}

/// True when `id` is exactly 32 bytes of lowercase hex: every byte in
/// [0-9a-f]. Uppercase hex, spaces, and any other byte make it false. This
/// checks shape only; it cannot prove an id was generated by this module.
/// Params: id - the candidate id string.
/// Returns: true for a well-formed 32-char lowercase hex id, false otherwise.
/// Error case: none.
/// Complexity: O(id length).
pub fn middleware_request_id_valid(id: Str) -> Bool {
  if id.len() != 32 {
    return false;
  }
  var i = 0;
  while i < 32 {
    let b = _byte_at_i(id, i);
    let digit = b >= 48 && b <= 57;
    let lower = b >= 97 && b <= 102;
    if !digit && !lower {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// --------------------------------------------------
//  Access log
// --------------------------------------------------

/// Build one access-log line:
/// `request_id=<id> method=<M> path=<p> status=<s> duration_ms=<d>
/// bytes=<b>` with single spaces between fields and no escaping. `status`,
/// `duration_ms` and `bytes` render as decimal integers (negative values get
/// a leading '-'); `request_id` is expected to be a middleware_request_id_new
/// value.
/// Params: request_id - the request id; method - the HTTP method; path - the
/// request path without the query string and WITHOUT SPACES (a space would
/// split the field when the line is tokenized); status - the HTTP status
/// code; duration_ms - the handler duration in milliseconds; bytes - the
/// response body size in bytes.
/// Returns: the exact line above (deterministic for fixed inputs).
/// Error case: none.
/// Complexity: O(total input length + digits).
pub fn middleware_access_log_line(request_id: Str, method: Str, path: Str, status: Int, duration_ms: Int, bytes: Int) -> Str {
  var out = "request_id=" + request_id;
  out = out + " method=" + method;
  out = out + " path=" + path;
  out = out + " status=" + _int_to_str(status);
  out = out + " duration_ms=" + _int_to_str(duration_ms);
  out = out + " bytes=" + _int_to_str(bytes);
  return out;
}

// --------------------------------------------------
//  CORS
// --------------------------------------------------

/// CORS response header lines as complete "Name: value" strings, in this
/// fixed order, each included only when its value is non-empty:
/// `Access-Control-Allow-Origin: <allow_origin>`,
/// `Access-Control-Allow-Methods: <allow_methods>`,
/// `Access-Control-Allow-Headers: <allow_headers>`,
/// `Access-Control-Max-Age: <max_age_secs>` (skipped when
/// max_age_secs <= 0; otherwise decimal).
/// `allow_origin` (and every other value) is passed through as-is: the
/// wildcard `*` stays `*`, and no origin is echoed or validated.
/// Params: allow_origin - the Origin value or `*`; allow_methods - the
/// comma-separated method list; allow_headers - the comma-separated header
/// list; max_age_secs - the preflight cache lifetime in seconds.
/// Returns: a fresh Vec[Str] of header lines, in the order above, empty
/// values omitted; empty when all four inputs are empty/non-positive.
/// Error case: none.
/// Complexity: O(total input length + digits).
pub fn middleware_cors_headers(allow_origin: Str, allow_methods: Str, allow_headers: Str, max_age_secs: Int) -> Vec[Str] {
  var out = Vec[Str].new();
  if allow_origin.len() > 0 {
    out.push("Access-Control-Allow-Origin: " + allow_origin);
  }
  if allow_methods.len() > 0 {
    out.push("Access-Control-Allow-Methods: " + allow_methods);
  }
  if allow_headers.len() > 0 {
    out.push("Access-Control-Allow-Headers: " + allow_headers);
  }
  if max_age_secs > 0 {
    out.push("Access-Control-Max-Age: " + _int_to_str(max_age_secs));
  }
  return out;
}

// --------------------------------------------------
//  CSRF
// --------------------------------------------------

/// Generate a new CSRF token: the lowercase hex of 16 CSPRNG bytes, exactly
/// 32 chars from [0-9a-f]. Same generation shape as request ids, but a
/// separate entry point (the two are independent functions, not aliases).
/// Returns: Ok(token) with token.len() == 32 and every byte in [0-9a-f].
/// Error case: Err("middleware: token generation failed") when the CSPRNG
/// does not return exactly 16 bytes (not observed on supported platforms).
/// Complexity: O(1).
pub fn middleware_csrf_token_new() -> Result[Str, Str] {
  let bytes = crypto.secure_random_bytes(16);
  if bytes.len() != 16 {
    return Err("middleware: token generation failed");
  }
  return Ok(_hex_lower(&bytes));
}

/// Validate a CSRF token against the expected one in constant time.
/// False when either input is empty or the lengths differ; otherwise the raw
/// byte vectors are compared with xiom.crypto.constant_time_compare, so the
/// running time does not depend on the first mismatching byte position.
/// Params: token - the token from the request; expected - the token held by
/// the session (the caller supplies it; this module stores nothing).
/// Returns: true only when both are non-empty, equally long, and equal.
/// Error case: none.
/// Complexity: O(token length).
pub fn middleware_csrf_valid(token: Str, expected: Str) -> Bool {
  if token.len() == 0 || expected.len() == 0 {
    return false;
  }
  if token.len() != expected.len() {
    return false;
  }
  let a = _bytes_of(token);
  let b = _bytes_of(expected);
  return crypto.constant_time_compare(&a, &b);
}

// --------------------------------------------------
//  Error response
// --------------------------------------------------

/// JSON error body with a minimal escape pass:
/// `{"error":{"status":<status>,"message":"<escaped message>"}}`.
/// `<status>` is decimal (negative gets a leading '-'); in `<escaped
/// message>` a backslash becomes `\\`, a double quote becomes `\"`, LF
/// becomes `\n`, CR becomes `\r` and TAB becomes `\t`; every other byte --
/// including other control bytes and raw UTF-8 -- is passed through
/// unchanged (so the result is not valid JSON for those bytes).
/// Params: status - the HTTP status code to echo; message - the message
/// text (any bytes).
/// Returns: the exact body string above (deterministic for fixed inputs).
/// Error case: none.
/// Complexity: O(message length + digits).
pub fn middleware_error_body(status: Int, message: Str) -> Str {
  return "{\"error\":{\"status\":" + _int_to_str(status) + ",\"message\":\"" + _escape_json(message) + "\"}}";
}

/// Content type of middleware_error_body responses: `application/json`.
/// Returns: the literal "application/json" (no charset parameter).
/// Error case: none.
/// Complexity: O(1).
pub fn middleware_error_content_type() -> Str {
  return "application/json";
}
