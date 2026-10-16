// XIOM -- xiom.jev.errors: the typed Err catalog
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Every fallible public function of the package returns a JevError inside a
// Result. Four variants, one per failure stage of a System One call:
//
//   kind  variant      trigger
//   0     BadRequest   request construction rejected (empty model, empty
//                      question list, duplicate ids, malformed criteria)
//   1     Transport    the libcurl bridge failed (no HTTP response reached
//                      the endpoint: DNS/TLS/connect/refusal)
//   2     HttpStatus   the endpoint answered with a non-2xx status; `code`
//                      is the status and `detail` the best-effort decoded
//                      API error message, else the truncated raw body
//   3     Parse        the response body is not a valid TypeSafe response
//                      (invalid JSON, missing field, out-of-range value,
//                      inconsistent choice/legend)
//
// jev_error_kind exposes the variant as an Int (0..3) so callers can branch
// without matching; jev_error_text renders a stable single-line ASCII
// message. The catalog of exact Parse/BadRequest reason strings is pinned in
// SPEC.md section 6 and by the conformance suite.

module xiom.jev.errors

pub enum JevError {
  BadRequest(reason: Str),
  Transport(reason: Str),
  HttpStatus(code: Int, detail: Str),
  Parse(reason: Str),
}

/// jev_error_kind returns 0 BadRequest, 1 Transport, 2 HttpStatus,
/// 3 Parse. Complexity: O(1). Pure.
pub fn jev_error_kind(e: JevError) -> Int {
  match e {
    JevError.BadRequest(reason) => { return 0; },
    JevError.Transport(reason) => { return 1; },
    JevError.HttpStatus(code, detail) => { return 2; },
    JevError.Parse(reason) => { return 3; },
  };
}

/// jev_error_text renders a stable single-line ASCII message:
///   "jev: bad request: <reason>"
///   "jev: transport: <reason>"
///   "jev: http <code>: <detail>"
///   "jev: parse: <reason>"
/// `detail` may be empty when the API error body could not be decoded.
/// Complexity: O(len). Pure.
pub fn jev_error_text(e: JevError) -> Str {
  match e {
    JevError.BadRequest(reason) => { return "jev: bad request: " + reason; },
    JevError.Transport(reason) => { return "jev: transport: " + reason; },
    JevError.HttpStatus(code, detail) => { return "jev: http " + code.to_string() + ": " + detail; },
    JevError.Parse(reason) => { return "jev: parse: " + reason; },
  };
}
