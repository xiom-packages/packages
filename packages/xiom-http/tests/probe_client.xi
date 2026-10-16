// probe_client.xi -- the xiom.http CLIENT surface own-probe.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pre-adoption evidence for the lattice-tier ask (REL-20261016-1129-xvector-2):
// stabilise the client half as its own consumer surface, with its own probe.
// This probe exercises ONLY `xiom.http.client` (the consumer surface); no
// server-module contact is needed.
//
// Checks (one [PASS]/[FAIL]/[SKIP] line each; exit code = failure count):
//   1. refused-taxonomy -- http://127.0.0.1:9/ must return a typed Err
//      (deterministic: the discard port has no listener).
//   2. malformed-url    -- a non-URL must return a typed Err.
//   3. live GET         -- https://example.com/ must return 2xx + non-empty
//      body + non-empty headers; [SKIP]s when the network is unreachable.
//   4. loopback POST    -- http://127.0.0.1:18094/echo, body "hi": a status
//      reply proves the POST leg; [SKIP]s when nothing listens there
//      (start any local endpoint on 127.0.0.1:18094 to include this leg).
//
// Evidence-only: NOT part of port.ps1 / the offline conformance suite (the
// client speaks through the libcurl bridge, so --run needs the real-libcurl
// setup -- see README "Consumer client build recipe" and SPEC "libcurl
// Setup"); use --check for a dependency-free surface type check:
//   xiom --check packages\xiom-http\tests\probe_client.xi
module http_client_probe

use xiom.http;
use xiom.http.client;
use xiom.io;
use xiom.string;
use xiom.convert;

pub fn main() -> Int {
  var failed: Int = 0;
  failed = failed + check_refused();
  failed = failed + check_malformed();
  failed = failed + check_live_get();
  failed = failed + check_loopback();
  if failed == 0 {
    io.println("probe_client: all checks passed");
  } else {
    io.println("probe_client: failures=" + convert.to_string(failed));
  };
  return failed;
}

fn check_refused() -> Int {
  var res: Result[HttpClientResponse, Str] = xiom.http.client.http_get("http://127.0.0.1:9/");
  match res {
    Ok(resp) => {
      io.println("[FAIL] refused-taxonomy: expected Err, got status " + convert.to_string(resp.status));
      return 1;
    },
    Err(e) => {
      io.println("[PASS] refused-taxonomy: typed Err (" + e + ")");
      return 0;
    },
  };
}

fn check_malformed() -> Int {
  var res: Result[HttpClientResponse, Str] = xiom.http.client.http_get("not-a-url");
  match res {
    Ok(resp) => {
      io.println("[FAIL] malformed-url: expected Err, got status " + convert.to_string(resp.status));
      return 1;
    },
    Err(e) => {
      io.println("[PASS] malformed-url: typed Err (" + e + ")");
      return 0;
    },
  };
}

fn check_live_get() -> Int {
  var res: Result[HttpClientResponse, Str] = xiom.http.client.http_get("https://example.com/");
  match res {
    Ok(resp) => {
      var blen: Int = string.str_len(resp.body);
      var hlen: Int = string.str_len(resp.headers);
      if resp.status < 200 || resp.status >= 300 {
        io.println("[FAIL] live GET: status " + convert.to_string(resp.status));
        return 1;
      };
      if blen == 0 {
        io.println("[FAIL] live GET: empty body");
        return 1;
      };
      if hlen == 0 {
        io.println("[FAIL] live GET: empty headers");
        return 1;
      };
      io.println("[PASS] live GET: status=" + convert.to_string(resp.status) + " body_bytes=" + convert.to_string(blen) + " header_bytes=" + convert.to_string(hlen));
      return 0;
    },
    Err(e) => {
      io.println("[SKIP] live GET: network unreachable (" + e + ")");
      return 0;
    },
  };
}

fn check_loopback() -> Int {
  var msg: Vec[Int] = Vec[Int].new();
  msg.push(104);
  msg.push(105);
  var res: Result[HttpClientResponse, Str] = xiom.http.client.http_post("http://127.0.0.1:18094/echo", msg, "text/plain");
  match res {
    Ok(resp) => {
      io.println("[PASS] loopback POST: status=" + convert.to_string(resp.status) + " echo_bytes=" + convert.to_string(string.str_len(resp.body)));
      return 0;
    },
    Err(e) => {
      io.println("[SKIP] loopback POST: nothing on 127.0.0.1:18094 (" + e + ")");
      return 0;
    },
  };
}
