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
// The root module carries package identity and the endpoint composition
// helper used by the client (pure, offline-testable).

module xiom.jev

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
