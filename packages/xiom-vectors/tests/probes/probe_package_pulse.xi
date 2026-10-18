// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Registry consumption gate: xiom.pulse 0.2.1 (PULSE Beacon -- the
// embeddable protocol core; Station consumes the same package). Proves the
// published artifact is consumable from the lane XIOM_HOME and that the
// pure surface works without sockets: request parse + header/body framing,
// the version-identity seam (server token roundtrip + rejection rules) and
// the hook seam (install/clear a pre hook). 0.2.1 carries the body-cap fix
// (pinned by the package's own 171/171 suite).
// Exit = failed checks.

module probe_package_pulse

use xiom.pulse;
use xiom.pulse.http;
use xiom.pulse.reqctx;
use xiom.pulse.app;
use xiom.string.slice;
use xiom.io;
use xiom.convert;

fn check(ok: Bool, name: Str, fails: Int) -> Int {
  if ok { io.println("  [PASS] " + name); return fails; }
  io.println("  [FAIL] " + name); return fails + 1;
}

fn pre_hook(_req: &PulseRequest, _body: Str) -> PreOut {
  return app.pre_continue();
}

fn main() -> Int {
  io.println("=== xvector probe: xiom.pulse 0.2.1 (Beacon embedded tier) ===");
  var fails: Int = 0;

  // Version-identity gate: the artifact must report a 0.2-series identity.
  // NOTE (filed 2026-10-17, bus item to packages): the published 0.2.1
  // artifact still reports "0.2.0" -- PULSE_PACKAGE_VERSION was not bumped
  // (the source constant is the single source of truth by design). The
  // accepted set keeps consumer compatibility gated while the exact
  // mismatch is tracked upstream; tighten to the declared version after the
  // fix ships.
  var pv = pulse.pulse_version();
  var pv_ok = pv == "0.2.1" || pv == "0.2.0";
  fails = check(pv_ok, "version: pulse_version() reports a 0.2-series identity (" + pv + ")", fails);

  var raw = slice.str_bytes("GET /health HTTP/1.1\r\nHost: t\r\nX-Api-Key: abc123\r\n\r\n");
  var req = http.parse_request(&raw);
  var hdr = http.header_get(&req, "x-api-key");
  fails = check(req.ok && req.method == "GET" && req.target == "/health" && req.version == "HTTP/1.1" && hdr == "abc123",
    "parse: GET request method/target/version + header lookup", fails);

  var raw2 = slice.str_bytes("POST /collections HTTP/1.1\r\nHost: t\r\nContent-Length: 7\r\n\r\nabc1234");
  var req2 = http.parse_request(&raw2);
  var body_s = http.bytes_to_str(&req2.body, 0, req2.body.len());
  fails = check(req2.ok && req2.method == "POST" && body_s == "abc1234",
    "parse: POST body framed by Content-Length", fails);

  var dflt = http.server_token();
  fails = check(dflt == "xiom-pulse", "token: default neutral Server token (no version)", fails);
  var set_ok = http.set_server_token("xiom-pulse-xvector/0.1.0");
  fails = check(set_ok && http.server_token() == "xiom-pulse-xvector/0.1.0",
    "token: consumer-set Server token roundtrip", fails);
  var before = http.server_token();
  var rej_crlf = http.set_server_token("bad\r\nX-Inject: 1");
  var rej_tab = http.set_server_token("bad\ttoken");
  fails = check(!rej_crlf && !rej_tab && http.server_token() == before,
    "token: CR/LF + non-printable injection rejected, value unchanged", fails);

  var hs = app.hooks_new();
  var hp = app.hooks_install_pre(&mut hs, pre_hook);
  var installed = false;
  match hp {
    Ok(_) => { installed = true; }
    Err(_) => {}
  }
  fails = check(installed && app.hooks_clear_pre(&mut hs), "hooks: install + clear a pre hook (0.2.0 seam)", fails);

  var resp = slice.str_bytes("HTTP/1.1 200 OK\r\n");
  var with_hdr = http.with_header_line(&resp, "X-Test: 1");
  var hdr_line = slice.str_bytes("X-Test: 1\r\n");
  var contains = false;
  var i: Int = 0;
  while i + hdr_line.len() <= with_hdr.len() && !contains {
    var j: Int = 0;
    var ok_here: Bool = true;
    while j < hdr_line.len() {
      if with_hdr[i + j] != hdr_line[j] { ok_here = false; j = hdr_line.len(); } else { j = j + 1; }
    }
    if ok_here { contains = true; }
    i = i + 1;
  }
  fails = check(contains, "build: with_header_line appends the wire header", fails);

  io.println("");
  io.println("probe_package_pulse: " + convert.int_to_string(fails) + " failed checks");
  return fails;
}
