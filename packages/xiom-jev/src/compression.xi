// XIOM -- xiom.jev.compression: request-body encodings and the 32 MiB rule
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// S8 carries two transport-side limits for POST /v1/systemone:
//
//   1. request-body compression (Content-Encoding) and
//   2. a 32 MiB request-body limit.
//
// This module is the pure, offline-testable seam for both. It never touches
// the network and it has no FFI:
//
//   * body_size_check / max_body_bytes pin the limit. The limit is inclusive:
//     33554432 bytes (32 MiB) is allowed, 33554433 bytes is rejected. The rule
//     applies to the logical request body produced by build_request (the
//     uncompressed JSON bytes), BEFORE any transport encoding is applied, so
//     compression can never be used to smuggle an oversized logical body past
//     the rule. `compress_body` enforces the same rule before compressing.
//   * encoding_name / encoding_from_name / encoding_supported map the
//     Content-Encoding tokens (`identity`, `gzip`, `zstd`) to the package's
//     stable integer tags.
//   * compress_bytes / compress_body produce the encoded representation.
//     gzip uses the pure-XIOM stdlib seam xiom.compress.gzip (RFC 1952), so no
//     vendored C is needed. zstd is declared but NOT available in this lane:
//     the in-tree xiom.zstd package is a vendored-C/FFI binding, and this
//     package's suite and live path are link-free, so asking for it returns
//     the typed BadRequest below instead of silently falling back.
//   * prepare_body / encoding_check are the pure request-build seam used by
//     xiom.jev.client: encoding_check fails unsupported compressors typed,
//     prepare_body enforces the logical-body rule and returns the exact wire
//     bytes, their Content-Length and the Content-Encoding token ("" for
//     identity, which keeps the Str transport path).
//
// Transport note (S8 resolved with xiom.http 0.1.9): `http_request_bytes`
// transmits a Vec[UInt8] verbatim (explicit CURLOPT_POSTFIELDSIZE, no UTF-8
// re-encode, no NUL truncation), so a gzip frame now reaches the endpoint
// unchanged. xiom.jev.client sends identity bodies through the existing
// `http_request` Str path (byte-identical to 0.1.8) and every other selected
// encoding through `http_request_bytes` with the exact encoded length and a
// `Content-Encoding` header.
//
// Error strings (JevError.BadRequest) are stable and pinned by the suite:
//
//   compression: body size is negative
//   request: body exceeds 32 MiB limit
//   compression: unknown encoding '<name>'
//   compression: unknown encoding <tag>
//   compression: zstd compressor is not available

module xiom.jev.compression

use xiom.jev.errors;
use xiom.compress.gzip;
use xiom.encoding;
use xiom.string.compare;
use xiom.convert;

// --------------------------------------------------
//  The 32 MiB body rule
// --------------------------------------------------

/// MAX_BODY_BYTES is the inclusive request-body limit from S8: 32 MiB.
/// 33554432 is allowed; 33554433 is rejected. Complexity: O(1). Pure.
pub const MAX_BODY_BYTES: Int = 33554432;

/// max_body_bytes returns the inclusive S8 request-body limit (33554432).
/// Complexity: O(1). Pure.
pub fn max_body_bytes() -> Int {
  return MAX_BODY_BYTES;
}

/// body_size_check enforces the inclusive 32 MiB rule on a body size in
/// bytes. 0..33554432 -> Ok(size) (the size is returned unchanged);
/// 33554433 and above -> Err(BadRequest("request: body exceeds 32 MiB
/// limit")); a negative size -> Err(BadRequest("compression: body size is
/// negative")). Complexity: O(1). Pure.
pub fn body_size_check(size: Int) -> Result[Int, JevError] {
  if size < 0 {
    return Err(JevError.BadRequest("compression: body size is negative"));
  }
  if size > MAX_BODY_BYTES {
    return Err(JevError.BadRequest("request: body exceeds 32 MiB limit"));
  }
  return Ok(size);
}

// --------------------------------------------------
//  Encoding tags
// --------------------------------------------------

/// ENCODING_IDENTITY is the no-encoding tag (no Content-Encoding header).
/// Complexity: O(1). Pure.
pub const ENCODING_IDENTITY: Int = 0;

/// ENCODING_GZIP is the gzip (RFC 1952) tag, sent as `Content-Encoding:
/// gzip`. Complexity: O(1). Pure.
pub const ENCODING_GZIP: Int = 1;

/// ENCODING_ZSTD is the Zstandard tag, sent as `Content-Encoding: zstd`.
/// The compressor itself is not available in this lane (see the module
/// header). Complexity: O(1). Pure.
pub const ENCODING_ZSTD: Int = 2;

/// encoding_name maps a tag to its Content-Encoding token; an unknown tag
/// yields "". Complexity: O(1). Pure.
pub fn encoding_name(enc: Int) -> Str {
  if enc == ENCODING_IDENTITY { return "identity"; }
  if enc == ENCODING_GZIP { return "gzip"; }
  if enc == ENCODING_ZSTD { return "zstd"; }
  return "";
}

/// encoding_from_name maps a Content-Encoding token (exact, case-sensitive:
/// "identity", "gzip", "zstd") to its tag. Anything else is a stable typed
/// BadRequest: `compression: unknown encoding '<name>'`.
/// Complexity: O(len). Pure.
pub fn encoding_from_name(name: Str) -> Result[Int, JevError] {
  if compare.str_compare(name, "identity") == 0 {
    return Ok(ENCODING_IDENTITY);
  }
  if compare.str_compare(name, "gzip") == 0 {
    return Ok(ENCODING_GZIP);
  }
  if compare.str_compare(name, "zstd") == 0 {
    return Ok(ENCODING_ZSTD);
  }
  return Err(JevError.BadRequest("compression: unknown encoding '" + name + "'"));
}

/// encoding_supported returns 1 when this build can encode `enc`, else 0.
/// identity and gzip are supported (the stdlib gzip seam); zstd is declared
/// but its compressor is absent in this lane.
/// Complexity: O(1). Pure.
pub fn encoding_supported(enc: Int) -> Int {
  if enc == ENCODING_IDENTITY { return 1; }
  if enc == ENCODING_GZIP { return 1; }
  return 0;
}

/// encoding_check validates a selected encoding for the request path. It
/// returns the tag unchanged for the supported identity/gzip encodings and a
/// typed BadRequest otherwise: zstd -> `compression: zstd compressor is not
/// available`, any other tag -> `compression: unknown encoding <tag>`. This is
/// the pure selection gate `system_one_with_encoding` runs before building a
/// body or touching the network.
/// Complexity: O(1). Pure.
pub fn encoding_check(enc: Int) -> Result[Int, JevError] {
  if enc == ENCODING_IDENTITY { return Ok(enc); }
  if enc == ENCODING_GZIP { return Ok(enc); }
  if enc == ENCODING_ZSTD {
    return Err(JevError.BadRequest("compression: zstd compressor is not available"));
  }
  return Err(JevError.BadRequest("compression: unknown encoding " + convert.to_string(enc)));
}

/// wire_uses_bytes reports whether a selected encoding needs the binary-safe
/// transport. identity (0) keeps the existing Str `http_request` path; gzip
/// (1) goes through `http_request_bytes`. Callers should run encoding_check
/// first: an unknown tag is handled as an error, not as a transport choice.
/// Complexity: O(1). Pure.
pub fn wire_uses_bytes(enc: Int) -> Int {
  if enc == ENCODING_IDENTITY { return 0; }
  return 1;
}

/// EncodedBody is the pure wire plan for a compressed request body: the exact
/// bytes to transmit, their length (the CURLOPT_POSTFIELDSIZE / Content-Length
/// value) and the Content-Encoding token ("" for identity, so no header is
/// emitted on the existing Str path).
pub type EncodedBody = {
  bytes: Vec[UInt8];
  content_length: Int;
  content_encoding: Str;
}

// --------------------------------------------------
//  Encoders (pure byte transforms)
// --------------------------------------------------

/// bytes_copy returns an owned copy of `data` (used per retry attempt, since
/// the binary transport takes the body by value). Complexity: O(len). Pure.
pub fn bytes_copy(data: &Vec[UInt8]) -> Vec[UInt8] {
  var out: Vec[UInt8] = Vec[UInt8].new();
  var i: Int = 0;
  while i < data.len() {
    out.push(data[i]);
    i = i + 1;
  }
  return out;
}

/// compress_bytes encodes `data` with `enc`. identity copies the bytes
/// unchanged; gzip returns an RFC 1952 frame via xiom.compress.gzip; zstd
/// returns Err(BadRequest("compression: zstd compressor is not available"))
/// because the in-tree xiom.zstd binding is FFI/vendored-C and this package
/// stays link-free; any other tag returns the unknown-encoding BadRequest.
/// Complexity: O(len) for identity, O(len) plus gzip work otherwise. Pure.
pub fn compress_bytes(data: &Vec[UInt8], enc: Int) -> Result[Vec[UInt8], JevError] {
  let checked: Result[Int, JevError] = encoding_check(enc);
  if !checked.is_ok {
    let e: JevError = checked.error;
    return Err(e);
  }
  if enc == ENCODING_IDENTITY {
    return Ok(bytes_copy(data));
  }
  let frame: Vec[UInt8] = gzip.gzip_compress(data);
  return Ok(frame);
}

/// compress_body encodes a UTF-8 request body. The 32 MiB rule is enforced on
/// the logical (uncompressed) body BEFORE any compression work, so an
/// oversized body fails typed and no encoder runs. The body is converted to
/// bytes with xiom.encoding.utf8_encode (the same bytes the identity transport
/// would send) and then handed to compress_bytes.
/// Complexity: O(len) plus compression work. Pure.
pub fn compress_body(body: Str, enc: Int) -> Result[Vec[UInt8], JevError] {
  let checked: Result[Int, JevError] = body_size_check(body.len());
  if !checked.is_ok {
    let e: JevError = checked.error;
    return Err(e);
  }
  let src: Vec[UInt8] = encoding.utf8_encode(body);
  return compress_bytes(&src, enc);
}

/// prepare_body builds the exact wire plan for a request body under `enc`.
/// Validation order is the logical-body rule FIRST (so an oversized logical
/// body is rejected before any encoder selection or work), then the encoding
/// gate (unsupported compressor -> typed BadRequest). On success the fields
/// are: `bytes` = the exact bytes to transmit, `content_length` =
/// `bytes.len()` (the declared Content-Length passed to http_request_bytes),
/// `content_encoding` = the Content-Encoding token, or "" for identity (the
/// existing Str path emits no such header). gzip bytes are deterministic and
/// the decompressed frame equals the UTF-8 body.
/// Complexity: O(len) for identity, O(len) plus gzip work otherwise. Pure.
pub fn prepare_body(body: Str, enc: Int) -> Result[EncodedBody, JevError] {
  let size_checked: Result[Int, JevError] = body_size_check(body.len());
  if !size_checked.is_ok {
    let size_err: JevError = size_checked.error;
    return Err(size_err);
  }
  let enc_checked: Result[Int, JevError] = encoding_check(enc);
  if !enc_checked.is_ok {
    let enc_err: JevError = enc_checked.error;
    return Err(enc_err);
  }
  let encoded: Result[Vec[UInt8], JevError] = compress_body(body, enc);
  if !encoded.is_ok {
    let encode_err: JevError = encoded.error;
    return Err(encode_err);
  }
  let wire: Vec[UInt8] = encoded.value;
  var token: Str = "";
  if enc != ENCODING_IDENTITY {
    token = encoding_name(enc);
  }
  return Ok(EncodedBody{ bytes: wire, content_length: wire.len(), content_encoding: token });
}
