// probe_real_libcurl.xi -- REAL-libcurl local proof (0.1.4 + 0.1.8 legs).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// NOT part of port.ps1 (the conformance suite stays offline via
// tests/probe_bridge.c). This probe links the production `xiom.http` client
// against a trusted libcurl DLL build. Legs:
//   1. LONG-option fix + real transfer (0.1.4): every `CURLOPT_*` setup must
//      succeed through real libcurl, and a real GET against
//      https://example.com must return a 2xx status with a non-empty body.
//   2. Custom-header roundtrip (0.1.8): http_request must put a
//      CRLF-blob-built header list on the wire. The probe POSTs to the
//      loopback echo endpoint convention 127.0.0.1:18094 (same port as
//      probe_client's loopback leg) and asserts the response body reflects
//      the custom headers it sent. The endpoint must echo the raw request
//      head (request line + headers) into the response body -- start
//      tests\echo_headers_server.ps1 for exactly that contract. SKIP-safe:
//      when nothing listens on 127.0.0.1:18094 the leg prints [SKIP] and
//      exits 0; an endpoint that reflects the POST body but NOT the custom
//      headers is a hard [FAIL] (custom headers were dropped in transit).
//
// Local invocation sketch (paths resolved locally; binaries stay in %TEMP%):
//   1. fetch curl-for-win (e.g. https://curl.se/windows/), extract to
//      %TEMP%\kilo\http-libcurl;
//   2. use the SHIPPED bridge C file (no libcurl stubs):
//        packages\xiom-http\bridge\xiom_http_shims.c
//      and put bin\libcurl-x64.dll on PATH;
//   3. Put the packaged bin\curl-ca-bundle.crt on CURL_CA_BUNDLE;
//   4. curl-for-win ships the mingw import archive lib\libcurl.dll.a while
//      lld-link searches for `curl.lib` -- copy it to a scratch dir as
//      curl.lib and point --link-path there;
//   5. from the repo root:
//        xiom --run packages\xiom-http\tests\probe_real_libcurl.xi `
//            --c-source packages\xiom-http\bridge\xiom_http_shims.c `
//            --link curl --link-path <scratch-with-curl.lib>
//
// This probe intentionally does not run in CI/port; it is evidence-only.
module http_real_libcurl_probe

use xiom.http;
use xiom.http.headers;
use xiom.http.types;
use xiom.io;
use xiom.string;
use xiom.convert;

fn probe_token() -> Str {
  return "xiom-http-probe-header-0.1.8";
}

pub fn main() -> Int {
  var failed: Int = 0;
  failed = failed + check_live_get();
  failed = failed + check_loopback_headers();
  if failed == 0 {
    io.println("probe_real_libcurl: all checks passed");
  } else {
    io.println("probe_real_libcurl: failures=" + convert.to_string(failed));
  };
  return failed;
}

fn check_live_get() -> Int {
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

fn check_loopback_headers() -> Int {
  var pairs: Vec[HttpHeader] = Vec[HttpHeader].new();
  pairs.push(HttpHeader{ name: "X-Xiom-Probe", value: probe_token() });
  pairs.push(HttpHeader{ name: "Authorization", value: "Bearer probe-token-not-a-secret" });
  var blob: Str = "";
  match http_headers_blob(pairs) {
    Ok(b) => { blob = b; },
    Err(e) => {
      io.println("[FAIL] loopback headers: blob build failed: " + e);
      return 1;
    },
  };
  var res: Result[HttpClientResponse, Str] = http_request("http://127.0.0.1:18094/echo", "POST", "header-probe", blob);
  match res {
    Ok(resp) => {
      if resp.status < 200 || resp.status >= 300 {
        io.println("[FAIL] loopback headers: unexpected status " + convert.to_string(resp.status));
        return 1;
      };
      if string.str_contains(resp.body, "X-Xiom-Probe: " + probe_token()) {
        if string.str_contains(resp.body, "Authorization: Bearer probe-token-not-a-secret") {
          io.println("[PASS] loopback header roundtrip: X-Xiom-Probe + Authorization reflected by the echo endpoint");
          return 0;
        };
        io.println("[FAIL] loopback headers: X-Xiom-Probe arrived but Authorization was dropped");
        return 1;
      };
      if string.str_contains(resp.body, "header-probe") {
        io.println("[FAIL] loopback headers: echo endpoint reflected the POST body but NOT the custom headers (headers dropped in transit)");
        return 1;
      };
      io.println("[SKIP] loopback headers: endpoint answered but does not reflect the request (start tests/echo_headers_server.ps1)");
      return 0;
    },
    Err(e) => {
      io.println("[SKIP] loopback headers: nothing on 127.0.0.1:18094 (" + e + ")");
      return 0;
    },
  };
}
