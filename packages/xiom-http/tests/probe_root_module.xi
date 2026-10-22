// probe_root_module.xi -- xiom.http root-module contract probe (fast-fail).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// The root module (http.xi, module xiom.http) is never imported by
// tests/test_conformance.xi, so its ensures-only clauses would otherwise get
// no runtime exercise. This probe drives the full helper chain through the
// public API with a refused connection (127.0.0.1:1, closed):
//   str_to_cstr -> setup_common_options -> perform_and_collect ->
//   get_response_code -> read_file_to_str -> curl_error_string ->
//   cstr_to_str -> byte_to_char -> char_to_str.
// curl_easy_perform fails fast with CURLE_COULDNT_CONNECT, so http_get
// returns Err(error-text) and exit code is 0 when the [PASS] checks hold.
//
// 0.1.8 additions (custom request headers): the same closed-port pattern
// exercises the new http_request entry through the probe bridge's
// deterministic curl_slist stubs -- header blob build, CURLOPT_HTTPHEADER
// setopt, and list free all run offline; the probe bridge additionally
// validates each split line ("Name: ..." required) so a malformed blob
// fails the probe instead of slipping through. The unsupported-method check
// is pure (Err before any FFI call).
//
// 0.1.10 additions (client transport): the probe bridge counts easy-handle
// init/cleanup and snapshots the millisecond timeout options. The probe proves
// one session handle serves two sequential requests (cleanup only at
// session_close), custom/default timeouts reach the bridge, and invalid
// options are rejected before any handle is created.
//
// Harness: the v0.64.5 toolchain ships only xiom_alloc in its runtime (no
// xiom_str_to_cstr / xiom_free_cstr / xiom_write_byte / xiom_read_byte /
// xiom_free_ptr symbols), so the probe links tests/probe_bridge.c. The bridge
// also stubs libcurl deterministically and offline; since the 0.1.4 fix pass
// it is FAITHFUL to libcurl's variadic setopt ABI: LONG options are read as
// the long VALUE from the register (never dereferenced) and implausible
// values are rejected with CURLE_BAD_FUNCTION_ARGUMENT (43). The old
// make_ptr_value bug (a heap pointer where libcurl reads a `long`) therefore
// fails this probe. The stub keeps the package's own chain deterministic and
// exercises the contract-checked helpers (the 0.1.3 p1 double-free removal
// uses a real libc free in the bridge; the 0.1.4 long-value fix is pinned by
// the bridge's LONG option expectations).
//
// Run from E:\xiom-packages\packages:
//   & .\scripts\xiom.ps1 -Stdlib "E:\xiom-lang\stdlib" --run `
//       packages\xiom-http\tests\probe_root_module.xi `
//       --c-source packages\xiom-http\tests\probe_bridge.c
module http_root_probe

// Probe-only snapshot accessors provided by tests/probe_bridge.c. They return
// the exact bytes the stub received at CURLOPT_POSTFIELDS/POSTFIELDSIZE, so
// the raw-bytes leg is verified at the package's own FFI transport seam.
extern "C" {
  fn xiom_probe_last_body_len() -> Int;
  fn xiom_probe_last_body_byte(offset: Int) -> Int;
  fn xiom_probe_easy_init_count() -> Int;
  fn xiom_probe_easy_cleanup_count() -> Int;
  fn xiom_probe_last_total_ms() -> Int;
  fn xiom_probe_last_connect_ms() -> Int;
}

use xiom.http;
use xiom.http.headers;
use xiom.http.options;
use xiom.http.types;
use xiom.string;
use xiom.io;
use xiom.convert;

pub fn main() -> Int {
  var failed: Int = 0;
  failed = failed + check_closed_port_get();
  failed = failed + check_unsupported_method();
  failed = failed + check_headers_closed_port();
  failed = failed + check_empty_headers_closed_port();
  failed = failed + check_binary_body_exact();
  failed = failed + check_binary_body_mismatch();
  failed = failed + check_timeout_defaults();
  failed = failed + check_timeout_custom();
  failed = failed + check_timeout_invalid();
  failed = failed + check_session_reuse();
  if failed == 0 {
    io.println("[PASS] probe_root_module: all checks passed");
  } else {
    io.println("[FAIL] probe_root_module: failures=" + convert.to_string(failed));
  };
  return failed;
}

fn check_closed_port_get() -> Int {
  var res: Result[HttpClientResponse, Str] = http_get("http://127.0.0.1:1/");
  match res {
    Ok(resp) => {
      io.println("[FAIL] closed-port http_get returned Ok (status " + xiom.convert.int_to_string(resp.status) + ")");
      return 1;
    },
    Err(e) => {
      var n: Int = string.str_len(e);
      if n > 0 {
        io.println("[PASS] http_get Err surfaced, error text non-empty (len " + xiom.convert.int_to_string(n) + ")");
      } else {
        io.println("[FAIL] http_get Err surfaced but error text is empty");
        return 1;
      };
      if string.str_contains(e, "curl_easy_perform failed") {
        io.println("[PASS] error text came from the perform path (get_response_code + read_file_to_str ran)");
      } else {
        io.println("[FAIL] unexpected error text: " + e);
        return 1;
      };
    },
  };
  return 0;
}

fn check_unsupported_method() -> Int {
  var res: Result[HttpClientResponse, Str] = http_request("http://127.0.0.1:1/", "BREW", "", "");
  match res {
    Ok(_) => {
      io.println("[FAIL] unsupported method returned Ok");
      return 1;
    },
    Err(e) => {
      if string.str_contains(e, "unsupported method") {
        io.println("[PASS] unsupported method rejected before any transfer (" + e + ")");
        return 0;
      };
      io.println("[FAIL] unsupported method: unexpected error text: " + e);
      return 1;
    },
  };
}

fn check_headers_closed_port() -> Int {
  var pairs: Vec[HttpHeader] = Vec[HttpHeader].new();
  pairs.push(HttpHeader{ name: "Authorization", value: "Bearer offline-probe" });
  pairs.push(HttpHeader{ name: "X-Offline-Probe", value: "1" });
  var blob: Str = "";
  match http_headers_blob(pairs) {
    Ok(b) => { blob = b; },
    Err(e) => {
      io.println("[FAIL] offline header blob build: " + e);
      return 1;
    },
  };
  var res: Result[HttpClientResponse, Str] = http_request("http://127.0.0.1:1/", "POST", "offline-body", blob);
  match res {
    Ok(resp) => {
      io.println("[FAIL] closed-port http_request returned Ok (status " + xiom.convert.int_to_string(resp.status) + ")");
      return 1;
    },
    Err(e) => {
      if string.str_contains(e, "curl_easy_perform failed") {
        io.println("[PASS] headers path ran offline: slist built, CURLOPT_HTTPHEADER set, list freed");
        return 0;
      };
      io.println("[FAIL] closed-port http_request: unexpected error text: " + e);
      return 1;
    },
  };
}

// Binary frame: gzip magic plus NUL, DEL, and every high-byte class.
fn binary_frame() -> Vec[UInt8] {
  var v: Vec[UInt8] = Vec[UInt8].new();
  v.push(31);
  v.push(139);
  v.push(8);
  v.push(0);
  v.push(127);
  v.push(128);
  v.push(129);
  v.push(254);
  v.push(255);
  return v;
}

fn check_binary_body_exact() -> Int {
  var frame: Vec[UInt8] = binary_frame();
  var res: Result[HttpClientResponse, HttpBytesRequestError] = http_request_bytes("http://127.0.0.1:1/", "POST", frame, 9, "");
  match res {
    Ok(resp) => {
      io.println("[FAIL] binary body: closed-port request returned Ok (status " + convert.to_string(resp.status) + ")");
      return 1;
    },
    Err(e) => {
      match e {
        HttpBytesRequestError.Transport(_) => {},
        _ => {
          io.println("[FAIL] binary body: expected Transport error after the transfer attempt");
          return 1;
        },
      };
    },
  };
  var n: Int = unsafe { xiom_probe_last_body_len() };
  if n != 9 {
    io.println("[FAIL] binary body: captured length " + convert.to_string(n) + ", expected 9");
    return 1;
  };
  var expect: Vec[UInt8] = binary_frame();
  var i: Int = 0;
  while i < 9 {
    var got: Int = unsafe { xiom_probe_last_body_byte(i) };
    if got != (expect[i] as Int) {
      io.println("[FAIL] binary body: byte " + convert.to_string(i) + " = " + convert.to_string(got) + ", expected " + convert.to_string(expect[i] as Int));
      return 1;
    };
    i = i + 1;
  };
  io.println("[PASS] binary body: 0x00 + 0x80..0xFF preserved exactly through CURLOPT_POSTFIELDS/POSTFIELDSIZE");
  return 0;
}

fn check_binary_body_mismatch() -> Int {
  var frame: Vec[UInt8] = binary_frame();
  var res: Result[HttpClientResponse, HttpBytesRequestError] = http_request_bytes("http://127.0.0.1:1/", "POST", frame, 8, "");
  match res {
    Ok(_) => {
      io.println("[FAIL] binary body mismatch: expected typed Err, got Ok");
      return 1;
    },
    Err(e) => {
      match e {
        HttpBytesRequestError.BodyLengthMismatch(declared, actual) => {
          if declared == 8 && actual == 9 {
            io.println("[PASS] binary body mismatch: typed LengthMismatch(8, 9) before any FFI call");
            return 0;
          };
          io.println("[FAIL] binary body mismatch: fields declared=" + convert.to_string(declared) + " actual=" + convert.to_string(actual));
          return 1;
        },
        _ => {
          io.println("[FAIL] binary body mismatch: expected BodyLengthMismatch, got another variant");
          return 1;
        },
      };
    },
  };
}

fn check_empty_headers_closed_port() -> Int {
  var res: Result[HttpClientResponse, Str] = http_request("http://127.0.0.1:1/", "PUT", "offline-put", "");
  match res {
    Ok(resp) => {
      io.println("[FAIL] closed-port empty-headers http_request returned Ok (status " + xiom.convert.int_to_string(resp.status) + ")");
      return 1;
    },
    Err(e) => {
      if string.str_contains(e, "curl_easy_perform failed") {
        io.println("[PASS] empty header blob keeps the wrapper path (no CURLOPT_HTTPHEADER)");
        return 0;
      };
      io.println("[FAIL] closed-port empty-headers http_request: unexpected error text: " + e);
      return 1;
    },
  };
}

// --- 0.1.10 transport options + session reuse ------------------------------

fn check_timeout_defaults() -> Int {
  var res: Result[HttpClientResponse, Str] = http_request("http://127.0.0.1:1/", "GET", "", "");
  match res {
    Ok(_) => {
      io.println("[FAIL] timeout defaults: closed-port request returned Ok");
      return 1;
    },
    Err(_) => {},
  };
  var total: Int = unsafe { xiom_probe_last_total_ms() };
  var connect: Int = unsafe { xiom_probe_last_connect_ms() };
  if total != 30000 || connect != 10000 {
    io.println("[FAIL] timeout defaults: got total=" + convert.to_string(total) + " connect=" + convert.to_string(connect) + ", expected 30000/10000");
    return 1;
  };
  io.println("[PASS] timeout defaults: CURLOPT_TIMEOUT_MS=30000, CURLOPT_CONNECTTIMEOUT_MS=10000");
  return 0;
}

fn check_timeout_custom() -> Int {
  var opts: HttpRequestOptions = HttpRequestOptions{ connect_ms: 1234, total_ms: 5678 };
  var res: Result[HttpClientResponse, HttpOptionsRequestError] = http_request_with_options("http://127.0.0.1:1/", "GET", "", "", opts);
  match res {
    Ok(_) => {
      io.println("[FAIL] custom timeout: closed-port request returned Ok");
      return 1;
    },
    Err(e) => {
      match e {
        HttpOptionsRequestError.Transport(_) => {},
        _ => {
          io.println("[FAIL] custom timeout: expected Transport after the transfer attempt");
          return 1;
        },
      };
    },
  };
  var total: Int = unsafe { xiom_probe_last_total_ms() };
  var connect: Int = unsafe { xiom_probe_last_connect_ms() };
  if total != 5678 || connect != 1234 {
    io.println("[FAIL] custom timeout: got total=" + convert.to_string(total) + " connect=" + convert.to_string(connect) + ", expected 5678/1234");
    return 1;
  };
  io.println("[PASS] custom timeout: values reach CURLOPT_TIMEOUT_MS / CURLOPT_CONNECTTIMEOUT_MS");
  return 0;
}

fn check_timeout_invalid() -> Int {
  var before: Int = unsafe { xiom_probe_easy_init_count() };
  var bad_connect: HttpRequestOptions = HttpRequestOptions{ connect_ms: -1, total_ms: 0 };
  match http_request_with_options("http://127.0.0.1:1/", "GET", "", "", bad_connect) {
    Ok(_) => {
      io.println("[FAIL] invalid connect timeout: expected typed Err, got Ok");
      return 1;
    },
    Err(e) => {
      match e {
        HttpOptionsRequestError.ConnectTimeoutNegative(value) => {
          if value != -1 {
            io.println("[FAIL] invalid connect timeout: value=" + convert.to_string(value));
            return 1;
          };
        },
        _ => {
          io.println("[FAIL] invalid connect timeout: wrong error variant");
          return 1;
        },
      };
    },
  };
  var bad_total: HttpRequestOptions = HttpRequestOptions{ connect_ms: 0, total_ms: -5 };
  match http_request_with_options("http://127.0.0.1:1/", "GET", "", "", bad_total) {
    Ok(_) => {
      io.println("[FAIL] invalid total timeout: expected typed Err, got Ok");
      return 1;
    },
    Err(e) => {
      match e {
        HttpOptionsRequestError.TotalTimeoutNegative(value) => {
          if value != -5 {
            io.println("[FAIL] invalid total timeout: value=" + convert.to_string(value));
            return 1;
          };
        },
        _ => {
          io.println("[FAIL] invalid total timeout: wrong error variant");
          return 1;
        },
      };
    },
  };
  var after: Int = unsafe { xiom_probe_easy_init_count() };
  if after != before {
    io.println("[FAIL] invalid timeout: FFI handle created before options were rejected");
    return 1;
  };
  io.println("[PASS] invalid timeouts: typed errors before any FFI call");
  return 0;
}

fn check_session_reuse() -> Int {
  var session: HttpClientSession;
  match session_new() {
    Ok(s) => { session = s; },
    Err(e) => {
      io.println("[FAIL] session: session_new failed: " + e);
      return 1;
    },
  };
  var inits_before: Int = unsafe { xiom_probe_easy_init_count() };
  var cleanups_before: Int = unsafe { xiom_probe_easy_cleanup_count() };

  match session_request(&session, "http://127.0.0.1:1/", "POST", "session-body", "") {
    Ok(_) => {
      io.println("[FAIL] session: first request returned Ok");
      return 1;
    },
    Err(_) => {},
  };
  match session_request(&session, "http://127.0.0.1:1/", "GET", "", "") {
    Ok(_) => {
      io.println("[FAIL] session: second request returned Ok");
      return 1;
    },
    Err(_) => {},
  };

  if unsafe { xiom_probe_easy_init_count() } != inits_before {
    io.println("[FAIL] session: a second easy handle was created (no reuse)");
    return 1;
  };
  if unsafe { xiom_probe_easy_cleanup_count() } != cleanups_before {
    io.println("[FAIL] session: handle was cleaned up mid-session");
    return 1;
  };

  session_close(session);
  if unsafe { xiom_probe_easy_cleanup_count() } != cleanups_before + 1 {
    io.println("[FAIL] session: session_close did not clean up exactly once");
    return 1;
  };
  io.println("[PASS] session: two requests on one easy handle, cleanup only at session_close");
  return 0;
}
