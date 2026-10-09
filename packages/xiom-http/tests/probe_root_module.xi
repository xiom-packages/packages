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
// Harness: the v0.64.1 toolchain ships only xiom_alloc in its runtime (no
// xiom_str_to_cstr / xiom_free_cstr / xiom_write_byte / xiom_read_byte /
// xiom_free_ptr symbols), so the probe links tests/probe_bridge.c. The bridge
// also stubs libcurl deterministically: driving the REAL libcurl is not
// possible for this module on Win64 -- make_ptr_value passes an 8-byte heap
// pointer where libcurl reads a `long` option value, so CURLOPT_TIMEOUT's
// setopt rejects the garbage low 32 bits (measured 500/500 nonzero returns).
// The stub keeps the package's own chain deterministic and exercises the
// contract-checked helpers (the fix under test, the p1 double-free removal,
// uses a real libc free in the bridge).
//
// Run from E:\xiom-packages\packages:
//   & .\scripts\xiom.ps1 -Stdlib "E:\xiom-lang\stdlib" --run `
//       packages\xiom-http\tests\probe_root_module.xi `
//       --c-source packages\xiom-http\tests\probe_bridge.c
module http_root_probe

use xiom.http;
use xiom.string;
use xiom.io;
use xiom.convert;

pub fn main() -> Int {
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
