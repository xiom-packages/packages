// XIOM -- xiom.http.options: per-request client transport options (0.1.10)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Pure, FFI-free half of the 0.1.10 client transport pass. A caller fills an
// HttpRequestOptions value and the root client translates it into libcurl's
// millisecond options (CURLOPT_CONNECTTIMEOUT_MS / CURLOPT_TIMEOUT_MS).
//
// Semantics (frozen):
//   - connect_ms == 0 -> library default (10000 ms)
//   - total_ms   == 0 -> library default (30000 ms)
//   - otherwise the value is used verbatim (milliseconds)
//   - negative values are rejected by validate_request_options with a typed
//     HttpRequestOptionError; no FFI call is made for an invalid value.
//
// The historical one-shot entries (http_get/http_post/...) keep using the
// library defaults, so adding options is purely additive.

module xiom.http.options

use xiom.convert;

pub type HttpRequestOptions = {
  connect_ms: Int;
  total_ms: Int;
} derive[Clone]

pub enum HttpRequestOptionError {
  ConnectTimeoutNegative(value: Int),
  TotalTimeoutNegative(value: Int),
}

// http_request_options_default returns the library defaults used by every
// pre-0.1.10 entry (30 s total, 10 s connect). Effector: pure.
pub fn http_request_options_default() -> HttpRequestOptions {
  return HttpRequestOptions{ connect_ms: 10000, total_ms: 30000 };
}

// validate_request_options rejects negative timeouts. Zero and positive
// values pass through unchanged. The value is borrowed, so callers can keep
// using their options after validation. Effector: pure.
pub fn validate_request_options(options: &HttpRequestOptions) -> Result[Unit, HttpRequestOptionError] {
  if options.connect_ms < 0 {
    return Err(HttpRequestOptionError.ConnectTimeoutNegative(options.connect_ms));
  };
  if options.total_ms < 0 {
    return Err(HttpRequestOptionError.TotalTimeoutNegative(options.total_ms));
  };
  return Ok(Unit);
}

// effective_connect_ms resolves the 0 sentinel to the library default.
// Effector: pure.
pub fn effective_connect_ms(options: &HttpRequestOptions) -> Int {
  if options.connect_ms == 0 {
    return 10000;
  };
  return options.connect_ms;
}

// effective_total_ms resolves the 0 sentinel to the library default.
// Effector: pure.
pub fn effective_total_ms(options: &HttpRequestOptions) -> Int {
  if options.total_ms == 0 {
    return 30000;
  };
  return options.total_ms;
}

// http_request_option_error_message renders a typed option error as
// deterministic, secret-free text. Effector: pure.
pub fn http_request_option_error_message(err: &HttpRequestOptionError) -> Str {
  match err {
    HttpRequestOptionError.ConnectTimeoutNegative(value) => {
      return "http options: negative connect timeout " + convert.int_to_string(value);
    },
    HttpRequestOptionError.TotalTimeoutNegative(value) => {
      return "http options: negative total timeout " + convert.int_to_string(value);
    },
  };
}
