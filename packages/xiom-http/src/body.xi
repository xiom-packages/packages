// XIOM -- xiom.http.body: raw-bytes request bodies (0.1.9)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// The Str-body client entries re-encode a Str through UTF-8 on the way to C,
// which corrupts binary payloads (gzip frames, images, protobuf, ...). This
// module is the pure, FFI-free half of the binary path: it carries the exact
// request bytes plus the caller-declared Content-Length and validates that
// the two agree before any transfer starts.
//
// The bytes are NEVER converted, encoded, trimmed, or NUL-terminated here.
// `http_bytes_body_wire` returns the exact byte sequence a transport must put
// on the wire (a byte-for-byte copy of the input), so a binary frame with
// 0x00 and 0x80..0xFF roundtrips unchanged.
//
// Typed errors (frozen):
//   - HttpBodyError.LengthMismatch(declared, actual) -- declared
//     Content-Length does not equal the byte-span length.
//   - HttpBodyError.NegativeLength(declared) -- caller passed a negative
//     Content-Length.
// `http_body_error_message` renders a deterministic, secret-free message for
// logging; the typed variant stays the primary contract.

module xiom.http.body

use xiom.convert;

pub enum HttpBodyError {
  LengthMismatch(declared: Int, actual: Int),
  NegativeLength(declared: Int),
}

pub type HttpBytesBody = {
  bytes: Vec[UInt8];
  content_length: Int;
}

// http_bytes_body validates a raw byte span against its explicit
// Content-Length and returns an owned body value. Complexity: O(1)
// (length check only); Effector: pure.
pub fn http_bytes_body(bytes: Vec[UInt8], content_length: Int) -> Result[HttpBytesBody, HttpBodyError] {
  if content_length < 0 {
    return Err(HttpBodyError.NegativeLength(content_length));
  };
  if content_length != bytes.len() {
    return Err(HttpBodyError.LengthMismatch(content_length, bytes.len()));
  };
  return Ok(HttpBytesBody{ bytes: bytes, content_length: content_length });
}

// http_bytes_body_wire copies the body bytes exactly, with no UTF-8
// conversion and no NUL handling. This is the byte sequence a transport must
// transmit for `body`. Complexity: O(n); Effector: pure.
pub fn http_bytes_body_wire(body: &HttpBytesBody) -> Vec[UInt8] {
  var out: Vec[UInt8] = Vec[UInt8].new();
  var i: Int = 0;
  while i < body.bytes.len() {
    out.push(body.bytes[i]);
    i = i + 1;
  };
  return out;
}

// http_body_error_message renders a typed body error as deterministic text.
// Effector: pure.
pub fn http_body_error_message(err: &HttpBodyError) -> Str {
  match err {
    HttpBodyError.LengthMismatch(declared, actual) => {
      return "http body: Content-Length " + convert.int_to_string(declared) + " does not match body length " + convert.int_to_string(actual);
    },
    HttpBodyError.NegativeLength(declared) => {
      return "http body: negative Content-Length " + convert.int_to_string(declared);
    },
  };
}
