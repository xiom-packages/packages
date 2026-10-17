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
//
// Transport note (blocker recorded in SPEC.md section 15 and ROADMAP.md):
// xiom.http 0.1.8 accepts request bodies as `Str` and re-encodes them as
// UTF-8 before the C call (http.xi str_to_cstr). A gzip/zstd frame is binary
// and not necessarily valid UTF-8, so the current transport cannot carry an
// encoded body unchanged. The encoders are therefore exposed for callers with
// a binary-capable transport; xiom.jev.client continues to send the identity
// body and applies body_size_check to it before the POST.
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

// --------------------------------------------------
//  Encoders (pure byte transforms)
// --------------------------------------------------

// _copy_bytes returns an owned copy of data.
fn _copy_bytes(data: &Vec[UInt8]) -> Vec[UInt8] {
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
  if enc == ENCODING_IDENTITY {
    return Ok(_copy_bytes(data));
  }
  if enc == ENCODING_GZIP {
    let frame: Vec[UInt8] = gzip.gzip_compress(data);
    return Ok(frame);
  }
  if enc == ENCODING_ZSTD {
    return Err(JevError.BadRequest("compression: zstd compressor is not available"));
  }
  return Err(JevError.BadRequest("compression: unknown encoding " + convert.to_string(enc)));
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
