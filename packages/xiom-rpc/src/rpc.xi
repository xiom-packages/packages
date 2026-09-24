// XIOM -- xiom.rpc: JSON-RPC 2.0 envelope codec with a minimal response scanner
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// This module builds JSON-RPC 2.0 envelopes and scans them back with a
// byte-wise scanner. It is envelope-level only: `params_json`, `result_json`
// and `data_json` are RAW JSON text supplied by the caller and are inserted
// verbatim; they are NOT validated, parsed or re-encoded.
//
// What this module does:
//   * rpc_escape escapes a method name or error message (backslash, quote,
//     LF, CR, TAB and every other C0 control byte as \u00XX); raw UTF-8
//     bytes pass through unchanged;
//   * the four builders emit compact JSON with a fixed key order and omit
//     the params/data member when the caller passes empty text;
//   * rpc_is_request / rpc_is_error answer substring probes;
//   * rpc_id / rpc_method / rpc_error_code / rpc_error_message read the FIRST
//     quoted '"key"' occurrence anywhere in the text, expect ':' (whitespace
//     allowed) and then read a signed integer or a quoted string.
//
// Deliberate limitations (documented in SPEC.md):
//   * NO JSON parser. Nested objects, duplicate keys, a `"key"' inside another
//     string value and key-like text anywhere in raw params/result/data can
//     match; there is no notion of "top level". Batch arrays are not modeled.
//   * The string reader decodes exactly the escapes rpc_escape emits that have
//     a two-character form (\" \\ \n \r \t); `\uXXXX` sequences are returned
//     verbatim, including the backslash, so a control byte escaped by
//     rpc_escape is NOT recovered as the original byte by the scanner.
//   * Integers are signed 64-bit; anything outside the range is an Err.
//
// v0.61.3 notes that shaped this module:
//   * Free functions only; no methods, no lambdas, no Vec of structs. Every
//     byte read through xiom.string.byte_at is widened with
//     `(string.byte_at(s, i) as Int) & 0xFF` before any comparison.
//   * Ok/Err are constructed only in the tiny leaf helpers below; building
//     Results inline inside larger functions miscompiles.
//   * No `==` on Str values; this module compares bytes and delegates textual
//     comparison to callers (the tests route through str_compare).
//
// Error strings always start with the literal prefix "rpc: ".

module xiom.rpc

use xiom.string;
use xiom.convert;

// --------------------------------------------------
//  Result constructors (leaf helpers, see header)
// --------------------------------------------------

fn _ok_str(v: Str) -> Result[Str, Str] {
  return Ok(v);
}

fn _err_str(m: Str) -> Result[Str, Str] {
  return Err(m);
}

fn _ok_int(v: Int) -> Result[Int, Str] {
  return Ok(v);
}

fn _err_int(m: Str) -> Result[Int, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Byte helpers
// --------------------------------------------------

// True for the ASCII whitespace bytes the scanner may skip: TAB (9), LF (10),
// CR (13) and space (32). JSON also allows VT/FF but no encoder emits them.
fn _is_ws(b: Int) -> Bool {
  if b == 9 || b == 10 || b == 13 || b == 32 {
    return true;
  }
  return false;
}

// Lowercase hex digit for 0..15.
fn _hex_digit(v: Int) -> Str {
  return string.str_slice("0123456789abcdef", v, v + 1);
}

// --------------------------------------------------
//  Builders: escaping
// --------------------------------------------------

/// Escape a method name or error message for embedding between JSON quotes.
/// Params: s - the raw text.
/// Returns: `s` with '\\' -> `\\`, '"' -> `\"`, LF -> `\n`, CR -> `\r`,
/// TAB -> `\t` and every other byte below 0x20 -> `\u00xx` (lowercase hex).
/// Every other byte, including all UTF-8 continuation and lead bytes, passes
/// through unchanged; `/` is not escaped.
/// Error case: none.
/// Complexity: O(s.len()).
pub fn rpc_escape(s: Str) -> Str {
  let n = s.len();
  var out = "";
  var i = 0;
  while i < n {
    let b = (string.byte_at(s, i) as Int) & 0xFF;
    if b == 92 {
      out = out + "\\\\";
    } elif b == 34 {
      out = out + "\\\"";
    } elif b == 10 {
      out = out + "\\n";
    } elif b == 13 {
      out = out + "\\r";
    } elif b == 9 {
      out = out + "\\t";
    } elif b < 32 {
      out = out + "\\u00" + _hex_digit((b >> 4) & 15) + _hex_digit(b & 15);
    } else {
      out = out + string.str_slice(s, i, i + 1);
    }
    i = i + 1;
  }
  return out;
}

// --------------------------------------------------
//  Builders: envelopes
// --------------------------------------------------

/// Build a JSON-RPC 2.0 request: `{"jsonrpc":"2.0","method":M[,"params":P],
/// "id":I}`. The method name is escaped with rpc_escape; `params_json` is
/// inserted verbatim only when it is non-empty, directly after the method.
/// Params: id - the request id (any signed 64-bit Int); method - procedure
/// name; params_json - raw JSON text for "params", or "" to omit the member.
/// Returns: the compact envelope text.
/// Error case: none (the caller owns the validity of params_json).
/// Complexity: O(method.len() + params_json.len()).
pub fn rpc_request(id: Int, method: Str, params_json: Str) -> Str {
  var out = "{\"jsonrpc\":\"2.0\",\"method\":\"" + rpc_escape(method) + "\"";
  if params_json.len() > 0 {
    out = out + ",\"params\":" + params_json;
  }
  out = out + ",\"id\":" + convert.int_to_string(id) + "}";
  return out;
}

/// Build a JSON-RPC 2.0 notification: like rpc_request without the "id"
/// member: `{"jsonrpc":"2.0","method":M[,"params":P]}`.
/// Params: method - procedure name; params_json - raw JSON text for "params",
/// or "" to omit the member.
/// Returns: the compact envelope text.
/// Error case: none.
/// Complexity: O(method.len() + params_json.len()).
pub fn rpc_notification(method: Str, params_json: Str) -> Str {
  var out = "{\"jsonrpc\":\"2.0\",\"method\":\"" + rpc_escape(method) + "\"";
  if params_json.len() > 0 {
    out = out + ",\"params\":" + params_json;
  }
  out = out + "}";
  return out;
}

/// Build a JSON-RPC 2.0 success response:
/// `{"jsonrpc":"2.0","result":R,"id":I}`. `result_json` is inserted
/// verbatim; empty text is normalized to the JSON literal `null`, because a
/// response must carry a result member.
/// Params: id - the id of the request being answered; result_json - raw JSON
/// text for "result", or "" for `null`.
/// Returns: the compact envelope text.
/// Error case: none.
/// Complexity: O(result_json.len()).
pub fn rpc_response(id: Int, result_json: Str) -> Str {
  var result = result_json;
  if result.len() == 0 {
    result = "null";
  }
  return "{\"jsonrpc\":\"2.0\",\"result\":" + result + ",\"id\":" + convert.int_to_string(id) + "}";
}

/// Build a JSON-RPC 2.0 error response:
/// `{"jsonrpc":"2.0","error":{"code":C,"message":M[,"data":D]},"id":I}`.
/// The message is escaped with rpc_escape; `data_json` is inserted verbatim
/// only when it is non-empty.
/// Params: id - the id of the request being answered (may be negative);
/// code - the error code (any signed 64-bit Int, conventionally negative);
/// message - short human-readable error text; data_json - raw JSON text for
/// "data", or "" to omit the member.
/// Returns: the compact envelope text.
/// Error case: none.
/// Complexity: O(message.len() + data_json.len()).
pub fn rpc_error(id: Int, code: Int, message: Str, data_json: Str) -> Str {
  var out = "{\"jsonrpc\":\"2.0\",\"error\":{\"code\":" + convert.int_to_string(code) + ",\"message\":\"" + rpc_escape(message) + "\"";
  if data_json.len() > 0 {
    out = out + ",\"data\":" + data_json;
  }
  out = out + "},\"id\":" + convert.int_to_string(id) + "}";
  return out;
}

// --------------------------------------------------
//  Scanner: key and value positions
// --------------------------------------------------

// Skip the ASCII whitespace bytes _is_ws accepts, starting at `i`; returns the
// index of the first byte that is not whitespace (may be the end).
fn _skip_ws(text: Str, i: Int) -> Int {
  let n = text.len();
  var p = i;
  while p < n {
    let b = (string.byte_at(text, p) as Int) & 0xFF;
    if _is_ws(b) {
      p = p + 1;
    } else {
      return p;
    }
  }
  return p;
}

// Byte offset just past the closing quote of the FIRST `"name"` occurrence in
// `text`, or -1 when absent. The key is matched byte-wise, so non-ASCII keys
// work; nesting and escapes are not understood (documented subset).
fn _find_key(text: Str, name: Str) -> Int {
  let n = text.len();
  let klen = name.len();
  if klen == 0 { return -1; }
  var i = 0;
  while i < n {
    let b = (string.byte_at(text, i) as Int) & 0xFF;
    if b == 34 {
      if i + 1 + klen < n {
        var same = true;
        var j = 0;
        while j < klen {
          let c = (string.byte_at(text, i + 1 + j) as Int) & 0xFF;
          let d = (string.byte_at(name, j) as Int) & 0xFF;
          if c != d { same = false; }
          j = j + 1;
        }
        if same {
          let q = (string.byte_at(text, i + 1 + klen) as Int) & 0xFF;
          if q == 34 {
            return i + 1 + klen + 1;
          }
        }
      }
    }
    i = i + 1;
  }
  return -1;
}

// Position of the value that follows key occurrence position `k`: skip
// whitespace, require ':', skip whitespace again. Returns -1 when the colon
// is missing (an existing key without a value separator); the returned index
// may equal text.len() when the text ends right after the colon.
fn _value_pos(text: Str, k: Int) -> Int {
  let n = text.len();
  var i = _skip_ws(text, k);
  if i >= n {
    return -1;
  }
  let b = (string.byte_at(text, i) as Int) & 0xFF;
  if b != 58 {
    return -1;
  }
  return _skip_ws(text, i + 1);
}

// --------------------------------------------------
//  Scanner: value readers
// --------------------------------------------------

// Decode the two-character escapes that rpc_escape emits: \" \\ \n \r \t.
// Every other sequence, including \uXXXX, is copied verbatim (backslash
// included). Total: never fails, never allocates through FFI.
fn _unescape(raw: Str) -> Str {
  let n = raw.len();
  var out = "";
  var i = 0;
  while i < n {
    let b = (string.byte_at(raw, i) as Int) & 0xFF;
    if b == 92 && i + 1 < n {
      let e = (string.byte_at(raw, i + 1) as Int) & 0xFF;
      if e == 34 {
        out = out + "\"";
        i = i + 2;
      } elif e == 92 {
        out = out + "\\";
        i = i + 2;
      } elif e == 110 {
        out = out + "\n";
        i = i + 2;
      } elif e == 114 {
        out = out + "\r";
        i = i + 2;
      } elif e == 116 {
        out = out + "\t";
        i = i + 2;
      } else {
        out = out + string.str_slice(raw, i, i + 1);
        i = i + 1;
      }
    } else {
      out = out + string.str_slice(raw, i, i + 1);
      i = i + 1;
    }
  }
  return out;
}

// Read a quoted string value stored under `key`. The scan is escape-aware: a
// backslash consumes the next byte, so `\"` does not terminate the value. The
// returned text has the two-character escapes decoded (see _unescape).
// Err when the key is absent, the value is not a quoted string or the closing
// quote is missing.
fn _string_value(text: Str, key: Str) -> Result[Str, Str] {
  let k = _find_key(text, key);
  if k < 0 {
    return _err_str("rpc: key not found: " + key);
  }
  let n = text.len();
  let i = _value_pos(text, k);
  if i < 0 || i >= n {
    return _err_str("rpc: expected string value");
  }
  let b = (string.byte_at(text, i) as Int) & 0xFF;
  if b != 34 {
    return _err_str("rpc: expected string value");
  }
  var j = i + 1;
  while j < n {
    let c = (string.byte_at(text, j) as Int) & 0xFF;
    if c == 92 {
      j = j + 2;
    } elif c == 34 {
      return _ok_str(_unescape(string.str_slice(text, i + 1, j)));
    } else {
      j = j + 1;
    }
  }
  return _err_str("rpc: unterminated string value");
}

// Read an integer value stored under `key`: optional '-', then one or more
// digits, then end-of-text or a terminator byte (whitespace, ',' or '}').
// Err when the key is absent, the value starts with a non-digit, a non-digit
// interrupts the number without being a terminator, or the magnitude exceeds
// the 64-bit signed range.
fn _int_value(text: Str, key: Str) -> Result[Int, Str] {
  let k = _find_key(text, key);
  if k < 0 {
    return _err_int("rpc: key not found: " + key);
  }
  let n = text.len();
  var i = _value_pos(text, k);
  if i < 0 || i >= n {
    return _err_int("rpc: expected integer value");
  }
  var neg = false;
  var b = (string.byte_at(text, i) as Int) & 0xFF;
  if b == 45 {
    neg = true;
    i = i + 1;
    if i >= n {
      return _err_int("rpc: expected integer value");
    }
    b = (string.byte_at(text, i) as Int) & 0xFF;
  }
  if b < 48 || b > 57 {
    return _err_int("rpc: expected integer value");
  }
  var acc = 0;
  var stopped = false;
  while i < n && !stopped {
    b = (string.byte_at(text, i) as Int) & 0xFF;
    if b >= 48 && b <= 57 {
      let d = b - 48;
      if acc > 922337203685477580 {
        return _err_int("rpc: integer out of range");
      }
      acc = acc * 10;
      if acc < 0 {
        return _err_int("rpc: integer out of range");
      }
      acc = acc + d;
      if acc < 0 {
        return _err_int("rpc: integer out of range");
      }
      i = i + 1;
    } else {
      stopped = true;
    }
  }
  if i < n {
    b = (string.byte_at(text, i) as Int) & 0xFF;
    if !(b == 32 || b == 9 || b == 10 || b == 13 || b == 44 || b == 125) {
      return _err_int("rpc: malformed integer value");
    }
  }
  if neg {
    return _ok_int(0 - acc);
  }
  return _ok_int(acc);
}

// --------------------------------------------------
//  Public API -- structure probes
// --------------------------------------------------

/// Substring probe: true when `text` contains the bytes `jsonrpc` AND the
/// bytes `method` anywhere. It is NOT a structural test: a notification also
/// answers true, and `method` inside raw params/result text can produce a
/// false positive (documented).
/// Params: text - the envelope or arbitrary text.
/// Returns: true when both substrings occur.
/// Error case: none.
/// Complexity: O(text.len()).
pub fn rpc_is_request(text: Str) -> Bool {
  if !string.str_contains(text, "jsonrpc") {
    return false;
  }
  return string.str_contains(text, "method");
}

/// Substring probe: true when `text` contains the bytes `error` anywhere.
/// It is NOT a structural test: an "error"-bearing result string can produce
/// a false positive (documented).
/// Params: text - the envelope or arbitrary text.
/// Returns: true when the substring occurs.
/// Error case: none.
/// Complexity: O(text.len()).
pub fn rpc_is_error(text: Str) -> Bool {
  return string.str_contains(text, "error");
}

// --------------------------------------------------
//  Public API -- member extraction
// --------------------------------------------------

/// Extract the "id" member as a signed 64-bit integer with the minimal
/// scanner (first quoted `"id"` occurrence anywhere; JSON `null` and quoted
/// numbers are rejected).
/// Params: text - the envelope text.
/// Returns: Ok(id) for an integer id.
/// Error case: Err("rpc: key not found: id"); Err("rpc: expected integer
/// value") when the value is not `-?digit...`; Err("rpc: malformed integer
/// value") for junk after the digits; Err("rpc: integer out of range").
/// Complexity: O(text.len()).
pub fn rpc_id(text: Str) -> Result[Int, Str] {
  return _int_value(text, "id");
}

/// Extract the "method" member as a string with the minimal scanner (first
/// quoted `"method"` occurrence anywhere). The string scan is escape-aware,
/// so `\"` does not terminate the value; `\"`, `\\`, `\n`, `\r` and `\t` are
/// decoded, while `\uXXXX` is returned verbatim (documented).
/// Params: text - the envelope text.
/// Returns: Ok(method) for a quoted string member.
/// Error case: Err("rpc: key not found: method"); Err("rpc: expected string
/// value") when the value is not a quoted string; Err("rpc: unterminated
/// string value") when the closing quote is missing.
/// Complexity: O(text.len()).
pub fn rpc_method(text: Str) -> Result[Str, Str] {
  return _string_value(text, "method");
}

/// Extract the "code" member of an error object as a signed 64-bit integer
/// with the minimal scanner (first quoted `"code"` occurrence anywhere).
/// Params: text - the envelope text.
/// Returns: Ok(code) for an integer code.
/// Error case: Err("rpc: key not found: code") plus the integer errors of
/// rpc_id.
/// Complexity: O(text.len()).
pub fn rpc_error_code(text: Str) -> Result[Int, Str] {
  return _int_value(text, "code");
}

/// Extract the "message" member of an error object as a string with the
/// minimal scanner (first quoted `"message"` occurrence anywhere); escape
/// handling is the same as rpc_method.
/// Params: text - the envelope text.
/// Returns: Ok(message) for a quoted string member.
/// Error case: Err("rpc: key not found: message") plus the string errors of
/// rpc_method.
/// Complexity: O(text.len()).
pub fn rpc_error_message(text: Str) -> Result[Str, Str] {
  return _string_value(text, "message");
}
