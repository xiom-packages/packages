// XIOM -- xiom.http.headers: deterministic header-list builder (0.1.8)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Pure layer: no FFI, no I/O. http_headers_blob turns declared (name, value)
// pairs into the single CRLF-joined blob the C bridge path expects for
// CURLOPT_HTTPHEADER (xiom_http_headers_build splits it into a curl_slist).
//
// Wire shape (frozen): every pair renders as "Name: value\r\n"; the blob is
// the concatenation in declaration order, so the last line is CRLF-terminated
// too. An empty input yields the empty string (Ok("")), which callers pass to
// mean "no custom headers". Duplicate names are preserved in order (no
// deduplication, no overwriting) so the caller keeps full wire control.
//
// Validation (frozen):
//   - name: non-empty and every character a RFC 7230 token character
//     (ALPHA / DIGIT / "!#$%&'*+-.^_`|~" -- ASCII only, no space, no colon,
//     no control characters). Rejected pairs return Err and render nothing.
//   - value: any length, including empty; must not contain control
//     characters (code point < 32) except horizontal tab (9), and must not
//     contain DEL (127). CR/LF are therefore rejected -- header injection
//     cannot be built from this module. Bytes >= 128 (obs-text) pass
//     through unchanged.
//   - leading/trailing spaces in a value are preserved verbatim (the caller
//     owns the exact value; nothing is trimmed or re-encoded).
//
// No secrets logged: values are never included in error text and nothing is
// printed. Error messages carry the header NAME at most (a name is an
// identifier, not a credential).
//
// Error strings (golden-tested):
//   "http_headers_blob: empty header name"
//   "http_headers_blob: invalid header name: <name>"
//   "http_headers_blob: header value contains a control character: <name>"

module xiom.http.headers

use xiom.string;
use xiom.http.types;

// is_token_char: RFC 7230 token character (ASCII subset used here).
fn is_token_char(c: Int) -> Bool {
  if c >= 65 && c <= 90 { return true; };
  if c >= 97 && c <= 122 { return true; };
  if c >= 48 && c <= 57 { return true; };
  if c == 33 || c == 35 || c == 36 || c == 37 || c == 38 || c == 39 { return true; };
  if c == 42 || c == 43 || c == 45 || c == 46 { return true; };
  if c == 94 || c == 95 || c == 96 || c == 124 || c == 126 { return true; };
  return false;
}

fn is_valid_header_name(name: Str) -> Bool {
  var len: Int = xiom.string.str_len(name);
  if len == 0 { return false; };
  var i: Int = 0;
  while i < len {
    match xiom.string.char_at(name, i) {
      Some(c) => {
        if !is_token_char(xiom.convert.char_to_int(c)) { return false; };
      },
      None => { return false; },
    };
    i = i + 1;
  };
  return true;
}

fn is_valid_header_value(value: Str) -> Bool {
  var len: Int = xiom.string.str_len(value);
  var i: Int = 0;
  while i < len {
    match xiom.string.char_at(value, i) {
      Some(c) => {
        var code: Int = xiom.convert.char_to_int(c);
        if code < 32 && code != 9 { return false; };
        if code == 127 { return false; };
      },
      None => { return false; },
    };
    i = i + 1;
  };
  return true;
}

// http_headers_blob builds the wire blob for the libcurl header path.
// Complexity: O(total header text). Effector: pure.
pub fn http_headers_blob(headers: Vec[HttpHeader]) -> Result[Str, Str] {
  var blob: Str = "";
  var i: Int = 0;
  while i < headers.len() {
    var h: HttpHeader = headers[i];
    if h.name.len() == 0 {
      return Err("http_headers_blob: empty header name");
    };
    if !is_valid_header_name(h.name) {
      return Err("http_headers_blob: invalid header name: " + h.name);
    };
    if !is_valid_header_value(h.value) {
      return Err("http_headers_blob: header value contains a control character: " + h.name);
    };
    blob = blob + h.name + ": " + h.value + "\r\n";
    i = i + 1;
  };
  return Ok(blob);
}
