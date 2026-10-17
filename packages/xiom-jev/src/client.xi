// XIOM -- xiom.jev.client: transport over the xiom.http client surface
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// system_one is the one-call client: build the request body
// (xiom.jev.request), build the header blob (via xiom.http.headers), POST it
// to <base_url>/v1/systemone through the xiom.http 0.1.8 headers-capable
// entry (xiom.http.http_request; TLS is the consumer's libcurl bridge -- this
// package adds no FFI), then parse the response (xiom.jev.response). Failures
// map onto the typed Err catalog:
//
//   BadRequest  -- empty base_url / api_key, or request validation
//   Transport   -- the libcurl bridge failed (no HTTP response)
//   HttpStatus  -- a non-2xx status; `detail` is the decoded API error
//                  message (response.api_error_detail) or the first 200
//                  characters of the raw body when decoding fails
//   Parse       -- the endpoint answered 2xx with an invalid body
//
// M2 chunk 1: transient non-2xx statuses (429/503/529) are retried up to
// xiom.jev.retry.default_max_attempts() total attempts with the deterministic
// bounded backoff of xiom.jev.retry (xiom.time.sleep_ms between attempts). No
// retry policy lives here; the client only drives the pure policy module.
//
// M2 chunk 4 (S8): the logical request body is capped at 32 MiB (inclusive;
// see xiom.jev.compression). body_size_check runs before the header blob and
// before any transport call, so an oversized body fails typed and offline.
//
// M2 chunk 5 (S8 completion): a compression mode can now be selected with
// system_one_with_encoding. identity keeps the exact 0.1.8 Str path
// (http_request, no Content-Encoding); gzip compresses the LOGICAL body
// through xiom.jev.compression.prepare_body and sends the exact frame via
// xiom.http 0.1.9 http_request_bytes (binary-safe, exact content_length) with
// Content-Encoding: gzip. The supported/unsupported selection is the pure
// compression.encoding_check gate, so zstd stays a typed BadRequest.
//
// LIVE LEG (resolved 2026-10-16): the Authorization: Bearer header now goes
// out through the xiom.http 0.1.8 custom-headers surface (see SPEC.md
// section 8). base_url and api_key are validated up front through the pure
// hygiene helpers of xiom.jev (base_url_validate: http/https scheme and a
// non-empty host; api_key_validate: trim + printable-ASCII), so a malformed
// input fails as a typed BadRequest before any network call. api_key is never
// logged, stored or echoed in errors.

module xiom.jev.client

use xiom.jev;
use xiom.jev.compression;
use xiom.jev.errors;
use xiom.jev.request;
use xiom.jev.response;
use xiom.jev.retry;
use xiom.jev.types;
use xiom.http;
use xiom.http.headers;
use xiom.http.types;
use xiom.convert;
use xiom.string;
use xiom.time;

// --------------------------------------------------
//  Result leaf constructors
// --------------------------------------------------

fn _ok_response(v: Response) -> Result[Response, JevError] {
  return Ok(v);
}

fn _err_response(e: JevError) -> Result[Response, JevError] {
  return Err(e);
}

fn _err_bad(reason: Str) -> Result[Response, JevError] {
  return Err(JevError.BadRequest(reason));
}

fn _err_transport(reason: Str) -> Result[Response, JevError] {
  return Err(JevError.Transport(reason));
}

fn _err_status(code: Int, detail: Str) -> Result[Response, JevError] {
  return Err(JevError.HttpStatus(code, detail));
}

// --------------------------------------------------
//  Helpers
// --------------------------------------------------

// _preview returns the first `n` characters of s (s itself when shorter).
fn _preview(s: Str, n: Int) -> Str {
  if s.len() <= n { return s; }
  return string.str_slice(s, 0, n);
}

// _status_detail decodes the API error detail, falling back to a 200-char
// preview of the raw body. Complexity: O(body). Pure.
fn _status_detail(resp: HttpClientResponse) -> Str {
  let decoded: Str = response.api_error_detail(resp.body);
  if decoded.len() > 0 { return decoded; }
  return _preview(resp.body, 200);
}

// _bytes_error_reason renders the xiom.http 0.1.9 binary-entry error. A
// Transport payload is the same curl-level message as the Str entry, so it
// maps onto JevError.Transport unchanged; the pre-FFI length checks can only
// fire on a caller bug and become a descriptive transport reason.
fn _bytes_error_reason(e: HttpBytesRequestError) -> Str {
  match e {
    HttpBytesRequestError.Transport(message) => { return message; },
    HttpBytesRequestError.BodyLengthMismatch(declared, actual) => {
      return "client: body length mismatch (declared " + convert.to_string(declared) + ", actual " + convert.to_string(actual) + ")";
    },
    HttpBytesRequestError.BodyLengthNegative(declared) => {
      return "client: body length is negative (" + convert.to_string(declared) + ")";
    },
    HttpBytesRequestError.UnsupportedMethod(method) => {
      return "client: unsupported method " + method;
    },
  };
}

// _post_identity drives the retry policy over the existing Str http_request
// path (byte-identical to the 0.1.8 behavior). Returns the first 2xx response.
fn _post_identity(endpoint: Str, body: Str, header_blob: Str, max_attempts: Int) -> Result[HttpClientResponse, JevError] {
  var attempt: Int = 1;
  while attempt <= max_attempts {
    let res: Result[HttpClientResponse, Str] = xiom.http.http_request(endpoint, "POST", body, header_blob);
    if !res.is_ok {
      let why: Str = res.error;
      return Err(JevError.Transport(why));
    }
    let resp: HttpClientResponse = res.value;
    let status: Int = resp.status;
    if status >= 200 && status < 300 {
      return Ok(resp);
    }
    let detail: Str = _status_detail(resp);
    if retry.retry_is_retryable(status) == 1 && attempt < max_attempts {
      let delay: Int = retry.retry_backoff_millis(attempt, retry.default_base_millis(), retry.default_cap_millis());
      time.sleep_ms(delay);
      attempt = attempt + 1;
      continue;
    }
    return Err(JevError.HttpStatus(status, detail));
  }
  return Err(JevError.Transport("client: retry loop exhausted"));
}

// _post_bytes drives the retry policy over the xiom.http 0.1.9 binary-safe
// entry: the exact encoded bytes and their exact content_length go out
// unchanged. Each attempt copies the prepared frame (the entry takes it by
// value). Returns the first 2xx response.
fn _post_bytes(endpoint: Str, bytes: &Vec[UInt8], content_length: Int, header_blob: Str, max_attempts: Int) -> Result[HttpClientResponse, JevError] {
  var attempt: Int = 1;
  while attempt <= max_attempts {
    let payload: Vec[UInt8] = compression.bytes_copy(bytes);
    let res: Result[HttpClientResponse, HttpBytesRequestError] = xiom.http.http_request_bytes(endpoint, "POST", payload, content_length, header_blob);
    if !res.is_ok {
      let why: HttpBytesRequestError = res.error;
      return Err(JevError.Transport(_bytes_error_reason(why)));
    }
    let resp: HttpClientResponse = res.value;
    let status: Int = resp.status;
    if status >= 200 && status < 300 {
      return Ok(resp);
    }
    let detail: Str = _status_detail(resp);
    if retry.retry_is_retryable(status) == 1 && attempt < max_attempts {
      let delay: Int = retry.retry_backoff_millis(attempt, retry.default_base_millis(), retry.default_cap_millis());
      time.sleep_ms(delay);
      attempt = attempt + 1;
      continue;
    }
    return Err(JevError.HttpStatus(status, detail));
  }
  return Err(JevError.Transport("client: retry loop exhausted"));
}

// _parse_ok parses a 2xx response body into the typed Response.
fn _parse_ok(resp: HttpClientResponse) -> Result[Response, JevError] {
  let parsed: Result[Response, JevError] = response.parse_response(resp.body);
  if !parsed.is_ok {
    let e: JevError = parsed.error;
    return Err(e);
  }
  return Ok(parsed.value);
}

// --------------------------------------------------
//  system_one
// --------------------------------------------------

/// system_one evaluates `state` against `questions` on `model` at
/// `base_url` (e.g. "https://api.typesafe.ai"), returning the typed
/// Response or a typed JevError (see the module header for the mapping).
/// `api_key` must be non-empty; it is sent as `Authorization: Bearer` on the
/// wire and never logged. This is the identity (uncompressed) path; see
/// system_one_with_encoding to select gzip.
/// Complexity: O(body + network). Effector: performs one HTTP request when
/// reached; pure up to the transport call.
pub fn system_one(base_url: Str, api_key: Str, model: Str, state: State, questions: Vec[Question]) -> Result[Response, JevError] {
  return system_one_with_encoding(base_url, api_key, model, state, questions, compression.ENCODING_IDENTITY);
}

/// system_one_with_encoding is system_one with an explicit Content-Encoding
/// selection (`compression.ENCODING_IDENTITY` or `ENCODING_GZIP`). The
/// logical body is validated against the 32 MiB rule first. identity keeps
/// the existing Str http_request path byte-identical; gzip compresses the
/// logical body and sends the exact frame plus an exact Content-Length
/// through xiom.http 0.1.9 http_request_bytes with `Content-Encoding: gzip`.
/// zstd and unknown tags fail typed before any network call, and transport
/// failures map onto JevError.Transport unchanged.
/// Complexity: O(body + network). Effector: performs one HTTP request when
/// reached; pure up to the transport call.
pub fn system_one_with_encoding(base_url: Str, api_key: Str, model: Str, state: State, questions: Vec[Question], encoding: Int) -> Result[Response, JevError] {
  let endpoint: Str = jev.systemone_endpoint(base_url);
  if endpoint.len() == 0 {
    return _err_bad("client: base_url is empty");
  }
  let base_ok: Result[Str, JevError] = jev.base_url_validate(base_url);
  if !base_ok.is_ok {
    return _err_response(base_ok.error);
  }
  let key_ok: Result[Str, JevError] = jev.api_key_validate(api_key);
  if !key_ok.is_ok {
    return _err_response(key_ok.error);
  }
  let key: Str = key_ok.value;
  // Selection gate: unsupported compressors fail typed before any body work.
  let enc_ok: Result[Int, JevError] = compression.encoding_check(encoding);
  if !enc_ok.is_ok {
    let enc_err: JevError = enc_ok.error;
    return _err_response(enc_err);
  }
  let built: Result[Str, JevError] = request.build_request(model, state, questions);
  if !built.is_ok {
    let e: JevError = built.error;
    return _err_response(e);
  }
  let body: Str = built.value;
  // S8 body rule: the LOGICAL (uncompressed) request body is capped at 32 MiB
  // (inclusive). This runs BEFORE any encoding or network call.
  let size_ok: Result[Int, JevError] = compression.body_size_check(body.len());
  if !size_ok.is_ok {
    let size_err: JevError = size_ok.error;
    return _err_response(size_err);
  }
  var hdrs: Vec[HttpHeader] = Vec[HttpHeader].new();
  hdrs.push(HttpHeader{ name: "Authorization", value: "Bearer " + key });
  hdrs.push(HttpHeader{ name: "Content-Type", value: "application/json" });
  // Prepare the encoded payload only when a non-identity mode is selected.
  var wire_bytes: Vec[UInt8] = Vec[UInt8].new();
  var wire_length: Int = 0;
  var use_bytes: Bool = false;
  if compression.wire_uses_bytes(encoding) == 1 {
    let prepared: Result[EncodedBody, JevError] = compression.prepare_body(body, encoding);
    if !prepared.is_ok {
      let prep_err: JevError = prepared.error;
      return _err_response(prep_err);
    }
    let plan: EncodedBody = prepared.value;
    let plan_token: Str = plan.content_encoding;
    wire_length = plan.content_length;
    wire_bytes = plan.bytes;
    hdrs.push(HttpHeader{ name: "Content-Encoding", value: plan_token });
    use_bytes = true;
  }
  let blob: Result[Str, Str] = xiom.http.headers.http_headers_blob(hdrs);
  if !blob.is_ok {
    return _err_bad("client: header build failed: " + blob.error);
  }
  let header_blob: Str = blob.value;
  let max_attempts: Int = retry.default_max_attempts();
  if use_bytes {
    let sent: Result[HttpClientResponse, JevError] = _post_bytes(endpoint, &wire_bytes, wire_length, header_blob, max_attempts);
    if !sent.is_ok {
      let sent_err: JevError = sent.error;
      return _err_response(sent_err);
    }
    return _parse_ok(sent.value);
  }
  let sent_identity: Result[HttpClientResponse, JevError] = _post_identity(endpoint, body, header_blob, max_attempts);
  if !sent_identity.is_ok {
    let id_err: JevError = sent_identity.error;
    return _err_response(id_err);
  }
  return _parse_ok(sent_identity.value);
}
