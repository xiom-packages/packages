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

// --------------------------------------------------
//  system_one
// --------------------------------------------------

/// system_one evaluates `state` against `questions` on `model` at
/// `base_url` (e.g. "https://api.typesafe.ai"), returning the typed
/// Response or a typed JevError (see the module header for the mapping).
/// `api_key` must be non-empty; it is sent as `Authorization: Bearer` on the
/// wire via the xiom.http 0.1.8 headers path and never logged.
/// Complexity: O(body + network). Effector: performs one HTTP request when
/// reached; pure up to the transport call.
pub fn system_one(base_url: Str, api_key: Str, model: Str, state: State, questions: Vec[Question]) -> Result[Response, JevError] {
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
  let built: Result[Str, JevError] = request.build_request(model, state, questions);
  if !built.is_ok {
    let e: JevError = built.error;
    return _err_response(e);
  }
  let body: Str = built.value;
  // S8 body rule: the logical request body is capped at 32 MiB (inclusive).
  // This runs BEFORE any network call and before the header blob is built.
  let size_ok: Result[Int, JevError] = compression.body_size_check(body.len());
  if !size_ok.is_ok {
    let size_err: JevError = size_ok.error;
    return _err_response(size_err);
  }
  var hdrs: Vec[HttpHeader] = Vec[HttpHeader].new();
  hdrs.push(HttpHeader{ name: "Authorization", value: "Bearer " + key });
  hdrs.push(HttpHeader{ name: "Content-Type", value: "application/json" });
  let blob: Result[Str, Str] = xiom.http.headers.http_headers_blob(hdrs);
  if !blob.is_ok {
    return _err_bad("client: header build failed: " + blob.error);
  }
  let header_blob: Str = blob.value;
  let max_attempts: Int = retry.default_max_attempts();
  var attempt: Int = 1;
  while attempt <= max_attempts {
    let res: Result[HttpClientResponse, Str] = xiom.http.http_request(endpoint, "POST", body, header_blob);
    if !res.is_ok {
      let why: Str = res.error;
      return _err_transport(why);
    }
    let resp: HttpClientResponse = res.value;
    let status: Int = resp.status;
    if status < 200 || status >= 300 {
      let decoded: Str = response.api_error_detail(resp.body);
      var detail: Str = decoded;
      if detail.len() == 0 {
        detail = _preview(resp.body, 200);
      }
      if retry.retry_is_retryable(status) == 1 && attempt < max_attempts {
        let delay: Int = retry.retry_backoff_millis(attempt, retry.default_base_millis(), retry.default_cap_millis());
        time.sleep_ms(delay);
        attempt = attempt + 1;
        continue;
      }
      return _err_status(status, detail);
    }
    let parsed: Result[Response, JevError] = response.parse_response(resp.body);
    if !parsed.is_ok {
      let e2: JevError = parsed.error;
      return _err_response(e2);
    }
    return _ok_response(parsed.value);
  }
  return _err_transport("client: retry loop exhausted");
}
