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
// LIVE LEG (resolved 2026-10-16): the Authorization: Bearer header now goes
// out through the xiom.http 0.1.8 custom-headers surface (see SPEC.md
// section 8). api_key is validated (non-empty); it is never logged, stored
// or echoed in errors.

module xiom.jev.client

use xiom.jev;
use xiom.jev.errors;
use xiom.jev.request;
use xiom.jev.response;
use xiom.jev.types;
use xiom.http;
use xiom.http.headers;
use xiom.http.types;
use xiom.string;

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
  if api_key.len() == 0 {
    return _err_bad("client: api_key is empty");
  }
  let built: Result[Str, JevError] = request.build_request(model, state, questions);
  if !built.is_ok {
    let e: JevError = built.error;
    return _err_response(e);
  }
  let body: Str = built.value;
  var hdrs: Vec[HttpHeader] = Vec[HttpHeader].new();
  hdrs.push(HttpHeader{ name: "Authorization", value: "Bearer " + api_key });
  hdrs.push(HttpHeader{ name: "Content-Type", value: "application/json" });
  let blob: Result[Str, Str] = xiom.http.headers.http_headers_blob(hdrs);
  if !blob.is_ok {
    return _err_bad("client: header build failed: " + blob.error);
  }
  let res: Result[HttpClientResponse, Str] = xiom.http.http_request(endpoint, "POST", body, blob.value);
  if !res.is_ok {
    let why: Str = res.error;
    return _err_transport(why);
  }
  let resp: HttpClientResponse = res.value;
  let status: Int = resp.status;
  if status < 200 || status >= 300 {
    let decoded: Str = response.api_error_detail(resp.body);
    if decoded.len() > 0 {
      return _err_status(status, decoded);
    }
    return _err_status(status, _preview(resp.body, 200));
  }
  let parsed: Result[Response, JevError] = response.parse_response(resp.body);
  if !parsed.is_ok {
    let e2: JevError = parsed.error;
    return _err_response(e2);
  }
  return _ok_response(parsed.value);
}
