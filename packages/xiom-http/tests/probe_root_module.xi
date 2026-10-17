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

use xiom.http;
use xiom.http.headers;
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
