// probe_real_libcurl.xi -- optional 0.1.4 REAL-libcurl local proof.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// NOT part of port.ps1 (the conformance suite stays offline via
// tests/probe_bridge.c). This probe links the production `xiom.http` client
// against a trusted libcurl DLL build to prove the 0.1.4 LONG-option fix
// against the real variadic `curl_easy_setopt`:
//   1. every `CURLOPT_*` setup must succeed through real libcurl (the old
//      heap-pointer code could not: libcurl read the ADDRESS as the long);
//   2. with network access, a real GET against https://example.com must
//      return a 2xx status with a non-empty body.
//
// Local invocation sketch (paths resolved locally; binaries stay in %TEMP%):
//   1. fetch curl-for-win (e.g. https://curl.se/windows/), extract to
//      %TEMP%\kilo\http-libcurl;
//   2. provide the xiom_* bridge-only C file (no libcurl stubs; see the
//      0.1.4 report) and put bin\libcurl-x64.dll on PATH;
//   3. Put the packaged bin\curl-ca-bundle.crt on CURL_CA_BUNDLE;
//   4. curl-for-win ships the mingw import archive lib\libcurl.dll.a while
//      lld-link searches for `curl.lib` -- copy it to a scratch dir as
//      curl.lib and point --link-path there;
//   5. from the repo root:
//        xiom --run packages\xiom-http\tests\probe_real_libcurl.xi `
//            --c-source <bridge_nocurl.c> `
//            --link curl --link-path <scratch-with-curl.lib>
//
// This probe intentionally does not run in CI/port; it is evidence-only.
module http_real_libcurl_probe

use xiom.http;
use xiom.io;
use xiom.string;
use xiom.convert;

pub fn main() -> Int {
  var res: Result[HttpClientResponse, Str] = http_get("https://example.com/");
  match res {
    Ok(resp) => {
      io.println("[PASS] real libcurl GET https://example.com/ status=" + convert.to_string(resp.status));
      if resp.status < 200 || resp.status >= 300 {
        io.println("[FAIL] unexpected status " + convert.to_string(resp.status));
        return 1;
      };
      var blen: Int = string.str_len(resp.body);
      var hlen: Int = string.str_len(resp.headers);
      if blen == 0 {
        io.println("[FAIL] empty response body (real transfer produced no bytes)");
        return 1;
      };
      io.println("[PASS] real body bytes=" + convert.to_string(blen) + " header bytes=" + convert.to_string(hlen));
      return 0;
    },
    Err(e) => {
      io.println("[FAIL] real-libcurl http_get: " + e);
      return 1;
    },
  };
}
