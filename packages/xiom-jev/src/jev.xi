// XIOM -- xiom.jev: TypeSafe Jev client tier (System One)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// JEV = System One: fast, structured decisions where the answer space is
// known in advance (routing, classification, scoring). Send a state and
// typed questions; get typed answers, probability distributions and
// confidence that code branches on -- no text generation, no parsing.
// This package is the System One tier of the XIOM ML/AI coverage program;
// it pairs with the xiom.llm runner tier (System Two text).
//
// Module map (all under the xiom.jev namespace):
//   xiom.jev.types      state, typed questions, typed answers (micro units)
//   xiom.jev.request    the request builder (JSON body)
//   xiom.jev.response   the response parser (typed answers + usage)
//   xiom.jev.selection  argmax / threshold / sample (caller-supplied entropy)
//   xiom.jev.errors     the typed Err catalog
//   xiom.jev.client     transport over the xiom.http client surface
//
// The root module carries package identity, the endpoint composition helper
// and the transport input hygiene checks used by the client (all pure and
// offline-testable): api_key_validate (S2 trim + printable-ASCII rule) and
// base_url_validate (http/https scheme, non-empty host).

module xiom.jev

use xiom.jev.errors;
use xiom.string;
use xiom.string.compare;

/// default_model is the TypeSafe flagship model alias.
/// Complexity: O(1). Pure.
pub fn default_model() -> Str {
  return "jev-latest";
}

/// default_base_url is the public TypeSafe API base URL.
/// Complexity: O(1). Pure.
pub fn default_base_url() -> Str {
  return "https://api.typesafe.ai";
}

/// version is the package version. Complexity: O(1). Pure.
pub fn version() -> Str {
  return "0.1.0";
}

/// systemone_endpoint composes the System One endpoint URL from a base URL:
/// trailing slashes on the base are collapsed and "/v1/systemone" is
/// appended. An empty base (or one made only of slashes) returns "".
/// Whitespace is NOT trimmed (the caller validates). Complexity: O(len).
/// Pure.
pub fn systemone_endpoint(base_url: Str) -> Str {
  if base_url.len() == 0 { return ""; }
  var n: Int = base_url.len();
  while n > 0 {
    let last: Str = string.str_slice(base_url, n - 1, n);
    if compare.str_compare(last, "/") != 0 { break; }
    n = n - 1;
  }
  if n == 0 { return ""; }
  let trimmed: Str = string.str_slice(base_url, 0, n);
  return trimmed + "/v1/systemone";
}

// --------------------------------------------------
//  Transport input hygiene (S2 API keys; endpoint URL)
// --------------------------------------------------

// _has_prefix is true when s starts with p (byte-exact, case-sensitive).
// Complexity: O(|p|).
fn _has_prefix(s: Str, p: Str) -> Bool {
  if s.len() < p.len() { return false; }
  let head: Str = string.str_slice(s, 0, p.len());
  if compare.str_compare(head, p) == 0 { return true; }
  return false;
}

/// api_key_validate trims an API key and rejects it with a typed
/// JevError.BadRequest when it is empty or carries characters forbidden on
/// the wire (S2): after trimming, every byte must be printable ASCII
/// (0x21..0x7E), so internal whitespace, control bytes and non-ASCII are
/// rejected. On success the Ok payload is the trimmed key. The raw key is
/// never logged or stored. Complexity: O(len). Pure.
pub fn api_key_validate(raw: Str) -> Result[Str, JevError] {
  let key: Str = string.str_trim(raw);
  if key.len() == 0 {
    return Err(JevError.BadRequest("client: api_key is empty"));
  }
  var i: Int = 0;
  let n: Int = key.len();
  while i < n {
    let b: Int = (string.byte_at(key, i) as Int) & 0xFF;
    if b <= 0x20 || b >= 0x7F {
      return Err(JevError.BadRequest("client: api_key has invalid characters"));
    }
    i = i + 1;
  }
  return Ok(key);
}

/// base_url_validate rejects a base URL with a typed JevError.BadRequest when
/// its scheme is not http/https or its host is empty; the Ok payload is the
/// base URL unchanged (the caller still composes the endpoint). An empty or
/// all-slash base is `client: base_url is empty` (systemone_endpoint
/// semantics). Complexity: O(len). Pure.
pub fn base_url_validate(base_url: Str) -> Result[Str, JevError] {
  if systemone_endpoint(base_url).len() == 0 {
    return Err(JevError.BadRequest("client: base_url is empty"));
  }
  var scheme_len: Int = 0;
  if _has_prefix(base_url, "https://") {
    scheme_len = 8;
  } elif _has_prefix(base_url, "http://") {
    scheme_len = 7;
  } else {
    return Err(JevError.BadRequest("client: base_url scheme must be http or https"));
  }
  let n: Int = base_url.len();
  var host_end: Int = n;
  var i: Int = scheme_len;
  while i < n {
    let b: Int = (string.byte_at(base_url, i) as Int) & 0xFF;
    if b == 47 {
      host_end = i;
      break;
    }
    i = i + 1;
  }
  if host_end <= scheme_len {
    return Err(JevError.BadRequest("client: base_url host is empty"));
  }
  return Ok(base_url);
}
