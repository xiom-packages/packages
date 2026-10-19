// XIOM -- xiom.pulse conformance tests (suite driver).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// The declared suite for scripts/port.ps1. Ported from the frozen PULSE
// suite (tests/test_http.xi at 56eb9f8) plus the keep-alive A/B semantics
// checks mined from the source smoke run (scripts/http_smoke.ps1, sections
// 13e/13f) and four loopback round-trips driving the real connection loop
// (app.handle_connection with two fds on 127.0.0.1; no threads).
//
// Sections:
//   A. module identity + request/response goldens
//   B. framing + caps (content-length, overflow, header count)
//   C. TE/CL smuggling rules (handle_route) + chunked decoding
//   D. builders (keep-flag variants), status text, security headers
//   E. query parsing / URL decoding / v1 alias
//   F. router mechanism (registration order, :param, 404/405 + Allow)
//   G. keep-alive semantics: the reuse latch, deadlines, PULSE_KEEPALIVE
//   H. loopback end-to-end: pipelined reuse on one fd, silent idle expiry,
//      PULSE_KEEPALIVE=0 close-per-request, Expect: 100-continue interim
//   I. hook seam (pre_route + after_response)
//   J. declared Content-Length body-cap hardening (413 before dispatch)
//
// Every check prints one [PASS]/[FAIL] line; the driver returns the failure
// count as the process exit code. Offline-safe: the only network use is a
// loopback listener bound by the suite itself.
module pulse_conformance_tests

use xiom.io;
use xiom.string;
use xiom.time;
use xiom.env;
use xiom.net.socket;
use xiom.pulse;
use xiom.pulse.http;
use xiom.pulse.router;
use xiom.pulse.app;
use xiom.pulse.config;

fn check(name: Str, ok: Bool) -> Int {
  if ok {
    io.println("[PASS] " + name);
    return 0;
  }
  io.println("[FAIL] " + name);
  return 1;
}

fn req_bytes(s: Str) -> Vec[UInt8] {
  return http.str_to_bytes(s);
}

fn contains(hay: Str, needle: Str) -> Bool {
  return string.str_contains(hay, needle);
}

/// occurrences counts non-overlapping occurrences of `needle` in `hay`.
fn occurrences(hay: Str, needle: Str) -> Int {
  return string.str_split(hay, needle).len() - 1;
}

/// cl_request_bytes builds a raw non-chunked POST with the declared
/// Content-Length and exactly `actual` body bytes (may be truncated).
fn cl_request_bytes(declared: Int, actual: Int) -> Vec[UInt8] {
  var raw: Vec[UInt8] = req_bytes("POST /echo HTTP/1.1\r\nHost: t\r\nContent-Type: application/json\r\nContent-Length: " + declared.to_str() + "\r\n\r\n");
  var i: Int = 0;
  while i < actual {
    raw.push(97u8);
    i = i + 1;
  }
  return raw;
}

/// test_handler echoes the request target as JSON for dispatched routes.
fn test_handler(req: &PulseRequest, m: &PulseRoute, body: Str) -> HandlerOut {
  return app.out_json(200, "{\"echo\":\"" + req.target + "\"}");
}

// Hook-seam observability (section I): test hooks record what they saw.
var hook_order: Str = "";
var hook_handler_calls: Int = 0;
var hook_seen_status: Int = 0;
var hook_seen_bytes: Int = -1;
var hook_seen_duration: Int = -1;

fn hook_pre_order(_req: &PulseRequest, _body: Str) -> PreOut {
  hook_order = hook_order + "pre;";
  return app.pre_continue();
}

/// hook_pre_cors is the CORS-preflight shape: OPTIONS short-circuits with a
/// 204 + allow-origin header; every other method continues to the router.
fn hook_pre_cors(req: &PulseRequest, _body: Str) -> PreOut {
  hook_order = hook_order + "preflight;";
  if req.method == "OPTIONS" {
    var hs: Vec[(Str, Str)] = Vec[(Str, Str)].new();
    hs.push(("Access-Control-Allow-Origin", "*"));
    return app.pre_stop(HandlerOut{ status: 204; content_type: "text/plain; charset=utf-8"; headers: hs; body: ""; body_bytes: Vec[UInt8].new() });
  }
  return app.pre_continue();
}

fn hook_after_observe(_req: &PulseRequest, _body: Str, _out: &HandlerOut, info: &ResponseInfo) {
  hook_order = hook_order + "after;";
  hook_seen_status = info.status;
  hook_seen_bytes = info.bytes;
  hook_seen_duration = info.duration_ms;
}

fn hook_handler(_req: &PulseRequest, _m: &PulseRoute, _body: Str) -> HandlerOut {
  hook_handler_calls = hook_handler_calls + 1;
  hook_order = hook_order + "handler;";
  return app.out_text(201, "hello");
}

// Unmatched-route fallback observability (section L): a site tree shape.
var fallback_calls: Int = 0;
var fallback_last_body: Str = "";

/// site_fallback serves a site-like file for /site/index.html and a custom
/// HTML 404 for every other unmatched path.
fn site_fallback(req: &PulseRequest, body: Str) -> HandlerOut {
  fallback_calls = fallback_calls + 1;
  fallback_last_body = body;
  if req.target == "/site/index.html" {
    return app.out_html(200, "<html><body>site</body></html>");
  }
  return app.out_html(404, "<html><body>custom 404</body></html>");
}

/// response_body_start is the index just past the response head terminator,
/// or -1 when the buffer holds no complete head.
fn response_body_start(resp: Str) -> Int {
  let r = string.str_index_of(resp, "\r\n\r\n");
  if r.is_some { return r.value + 4; }
  return -1;
}

/// response_body is the bytes after the head terminator ("" when absent).
fn response_body(resp: Str) -> Str {
  let i = response_body_start(resp);
  if i < 0 { return ""; }
  return string.str_slice(resp, i, resp.len());
}

// Stateful-hook observability (section K): the ctx bag carries handles and
// the mix hooks record their relative order in one string.
var ctx_order: Str = "";
var ctx_after_seen: Int = -1;
var ctx_after_status: Int = 0;

fn mix_pre_order(_req: &PulseRequest, _body: Str) -> PreOut {
  ctx_order = ctx_order + "pre;";
  return app.pre_continue();
}

fn mix_pre_ctx(_req: &PulseRequest, _body: Str, ctx: &mut HookCtx) -> PreOut {
  ctx_order = ctx_order + "prectx;";
  let _ = app.hookctx_push(ctx, 7);
  return app.pre_continue();
}

fn mix_after_order(_req: &PulseRequest, _body: Str, _out: &HandlerOut, _info: &ResponseInfo) {
  ctx_order = ctx_order + "after;";
}

fn mix_after_ctx(_req: &PulseRequest, _body: Str, out: &HandlerOut, _info: &ResponseInfo, ctx: &mut HookCtx) {
  ctx_order = ctx_order + "afterctx;";
  ctx_after_seen = app.hookctx_get(ctx, 0);
  ctx_after_status = out.status;
}

/// limiter_bump is the Phase B shape: the bag holds [count, limit]; the pre
/// hook pulls both, increments the count and short-circuits with 429 once the
/// count exceeds the limit.
fn limiter_bump(_req: &PulseRequest, _body: Str, ctx: &mut HookCtx) -> PreOut {
  let n = app.hookctx_get(ctx, 0) + 1;
  let _ = app.hookctx_set(ctx, 0, n);
  let limit = app.hookctx_get(ctx, 1);
  if n > limit {
    return app.pre_stop(app.out_json(429, "{\"error\":{\"code\":\"rate_limited\",\"message\":\"too many requests\"}}"));
  }
  return app.pre_continue();
}

/// limiter_after records the final status so the test can prove the after
/// hook observed the 429 short-circuit.
var limiter_after_status: Int = 0;

fn limiter_after(_req: &PulseRequest, _body: Str, out: &HandlerOut, _info: &ResponseInfo, ctx: &mut HookCtx) {
  limiter_after_status = out.status;
}

/// bind_listener binds 127.0.0.1 on the first free port at/after `seed`
/// (SO_REUSEADDR best-effort). Returns (listener_fd, port); (0, -1) when
/// the whole range is busy.
fn bind_listener(seed: Int) -> (Int, Int) {
  var port: Int = seed;
  while port < seed + 24 {
    let sr = socket.socket_tcp();
    if sr.is_err { return (0, -1); }
    let fd = sr.value;
    let _ra = socket.socket_reuse_addr(fd, true);
    let br = socket.socket_bind(fd, "127.0.0.1", port);
    if br.is_err {
      socket.socket_close(fd);
      port = port + 1;
    } else {
      let lr = socket.socket_listen(fd, 8);
      if lr.is_err {
        socket.socket_close(fd);
        return (0, -1);
      }
      return (fd, port);
    }
  }
  return (0, -1);
}

/// e2e_round_trip sends `request` on a loopback client fd, drives the real
/// server-side loop (app.handle_connection) on the accepted fd, then reads
/// everything the client can still receive. Returns the raw response text,
/// or a "BIND_FAIL"/"CONN_FAIL"/"ACCEPT_FAIL" sentinel on setup failure.
/// e2e_round_trip drives the loop with an empty hook set (the hook-free
/// baseline); e2e_round_trip_with lets section I wire hooks into the real
/// connection loop.
fn e2e_round_trip(seed: Int, request: Str) -> Str {
  let none = app.hooks_new();
  return e2e_round_trip_with(seed, request, &none);
}

fn e2e_round_trip_with(seed: Int, request: Str, hooks: &HookSet) -> Str {
  let lp = bind_listener(seed);
  let lfd = lp.0;
  if lfd <= 0 { return "BIND_FAIL"; }
  let port = lp.1;
  let cr = socket.socket_tcp();
  if cr.is_err {
    socket.socket_close(lfd);
    return "CONN_FAIL";
  }
  let cfd = cr.value;
  let cn = socket.socket_connect(cfd, "127.0.0.1", port);
  if cn.is_err {
    socket.socket_close(cfd);
    socket.socket_close(lfd);
    return "CONN_FAIL";
  }
  let bytes = http.str_to_bytes(request);
  let _snd = socket.socket_send(cfd, &bytes);
  let ar = socket.socket_accept(lfd);
  if ar.is_err {
    socket.socket_close(cfd);
    socket.socket_close(lfd);
    return "ACCEPT_FAIL";
  }
  let conn = ar.value;
  app.handle_connection_with(conn, test_handler, hooks);
  socket.socket_close(conn);
  var all: Vec[UInt8] = Vec[UInt8].new();
  var rounds: Int = 0;
  var done: Bool = false;
  while !done && rounds < 64 && all.len() < 262144 {
    let rr = socket.socket_recv_timeout(cfd, 65536, 3000);
    if rr.is_err {
      done = true;
    } else if rr.value.len() == 0 {
      done = true;
    } else {
      var i: Int = 0;
      while i < rr.value.len() {
        all.push(rr.value[i]);
        i = i + 1;
      }
    }
    rounds = rounds + 1;
  }
  socket.socket_close(cfd);
  socket.socket_close(lfd);
  return http.bytes_to_str(&all, 0, all.len());
}

/// e2e_round_trip_ctx is e2e_round_trip_with with a caller-owned HookCtx
/// (drives app.handle_connection_with_ctx over one real fd).
fn e2e_round_trip_ctx(seed: Int, request: Str, hooks: &HookSet, ctx: &mut HookCtx) -> Str {
  let lp = bind_listener(seed);
  let lfd = lp.0;
  if lfd <= 0 { return "BIND_FAIL"; }
  let port = lp.1;
  let cr = socket.socket_tcp();
  if cr.is_err {
    socket.socket_close(lfd);
    return "CONN_FAIL";
  }
  let cfd = cr.value;
  let cn = socket.socket_connect(cfd, "127.0.0.1", port);
  if cn.is_err {
    socket.socket_close(cfd);
    socket.socket_close(lfd);
    return "CONN_FAIL";
  }
  let bytes = http.str_to_bytes(request);
  let _snd = socket.socket_send(cfd, &bytes);
  let ar = socket.socket_accept(lfd);
  if ar.is_err {
    socket.socket_close(cfd);
    socket.socket_close(lfd);
    return "ACCEPT_FAIL";
  }
  let conn = ar.value;
  app.handle_connection_with_ctx(conn, test_handler, hooks, ctx);
  socket.socket_close(conn);
  var all: Vec[UInt8] = Vec[UInt8].new();
  var rounds: Int = 0;
  var done: Bool = false;
  while !done && rounds < 64 && all.len() < 262144 {
    let rr = socket.socket_recv_timeout(cfd, 65536, 3000);
    if rr.is_err {
      done = true;
    } else if rr.value.len() == 0 {
      done = true;
    } else {
      var i: Int = 0;
      while i < rr.value.len() {
        all.push(rr.value[i]);
        i = i + 1;
      }
    }
    rounds = rounds + 1;
  }
  socket.socket_close(cfd);
  socket.socket_close(lfd);
  return http.bytes_to_str(&all, 0, all.len());
}

pub fn main() -> Int {
  var f: Int = 0;

  // --- A. module identity + request/response goldens -----------------------
  f = f + check("pulse_version package 0.3.1", pulse.pulse_version() == "0.3.1");

  let r1 = req_bytes("GET /health HTTP/1.1\r\nHost: example\r\nX-Test: yes\r\n\r\n");
  let he1 = http.find_header_end(&r1);
  f = f + check("find_header_end present", he1 >= 0 && he1 + 4 <= r1.len());
  let r0 = req_bytes("GET /health HTTP/1.1\r\nHost: example");
  f = f + check("find_header_end absent", http.find_header_end(&r0) == -1);

  let req1 = http.parse_request(&r1);
  f = f + check("parse ok", req1.ok);
  f = f + check("method", req1.method == "GET");
  f = f + check("target", req1.target == "/health");
  f = f + check("version", req1.version == "HTTP/1.1");
  f = f + check("header count", req1.header_names.len() == 2);
  f = f + check("header_get host", http.header_get(&req1, "host") == "example");
  f = f + check("header_get case-insensitive", http.header_get(&req1, "X-TEST") == "yes");
  f = f + check("header_get absent", http.header_get(&req1, "content-type") == "");

  let bad1 = http.parse_request(&r0);
  f = f + check("incomplete headers rejected", !bad1.ok && bad1.error.len() > 0);
  let bad2 = http.parse_request(&req_bytes("GET\r\n\r\n"));
  f = f + check("malformed request line rejected", !bad2.ok);
  let bad3 = http.parse_request(&req_bytes("GET /x HTTP/1.1\r\nBrokenHeader\r\n\r\n"));
  f = f + check("malformed header rejected", !bad3.ok);

  // --- B. framing + caps ----------------------------------------------------
  let r2 = req_bytes("POST /api/echo HTTP/1.1\r\nContent-Length: 7\r\n\r\n{\"a\":1}");
  let he2 = http.find_header_end(&r2);
  f = f + check("content_length_of", http.content_length_of(&r2, he2) == 7);
  let req2 = http.parse_request(&r2);
  f = f + check("post parse ok", req2.ok);
  f = f + check("post body len", req2.body.len() == 7);
  f = f + check("post body bytes", http.bytes_to_str(&req2.body, 0, req2.body.len()) == "{\"a\":1}");
  f = f + check("no content-length is 0", http.content_length_of(&r1, he1) == 0);

  f = f + check("caps: headers 16 KiB", http.header_limit_bytes() == 16384);
  f = f + check("caps: header count 100", http.header_count_limit() == 100);
  f = f + check("caps: body 1 MiB", http.body_limit_bytes() == 1048576);

  f = f + check("header_overflow normal false", !http.header_overflow(&r1));
  var big: Vec[UInt8] = Vec[UInt8].new();
  var bi: Int = 0;
  while bi < 20000 {
    big.push(65u8);
    bi = bi + 1;
  }
  f = f + check("header_overflow oversized true", http.header_overflow(&big));

  var many_hdr: Str = "GET /health HTTP/1.1\r\n";
  var hi: Int = 0;
  while hi < 101 {
    many_hdr = many_hdr + "X-H" + hi.to_str() + ": v\r\n";
    hi = hi + 1;
  }
  many_hdr = many_hdr + "\r\n";
  let pmany = http.parse_request(&req_bytes(many_hdr));
  f = f + check("too many headers rejected", !pmany.ok);

  let fe_ok = http.framed_end(&r2);
  f = f + check("framed_end complete", fe_ok == r2.len());
  let rpipe = req_bytes("POST /api/echo HTTP/1.1\r\nContent-Length: 7\r\n\r\n{\"a\":1}GET /health HTTP/1.1\r\n\r\n");
  let fe_pipe = http.framed_end(&rpipe);
  f = f + check("framed_end pipelined prefix", fe_pipe == 53);
  let r_partial = req_bytes("POST /api/echo HTTP/1.1\r\nContent-Length: 5\r\n\r\nab");
  f = f + check("framed_end incomplete", http.framed_end(&r_partial) == -1);
  let r_tegzip = req_bytes("POST /api/echo HTTP/1.1\r\nTransfer-Encoding: gzip\r\n\r\n");
  f = f + check("framed_end unsupported TE", http.framed_end(&r_tegzip) == -1);
  let r_oversize = req_bytes("POST /api/echo HTTP/1.1\r\nContent-Length: 2000000\r\n\r\n");
  f = f + check("framed_end oversize CL", http.framed_end(&r_oversize) == -1);

  // --- C. TE/CL smuggling rules + chunked decoding --------------------------
  var defs: Vec[(Str, Str)] = Vec[(Str, Str)].new();
  defs.push(("GET", "/health"));
  defs.push(("POST", "/echo"));
  defs.push(("GET", "/items/:id"));

  let m_echo = router.route_match("POST", "/echo", &defs);
  let r_te_cl = req_bytes("POST /echo HTTP/1.1\r\nHost: t\r\nTransfer-Encoding: chunked\r\nContent-Length: 7\r\n\r\n7\r\n{\"a\":1}\r\n0\r\n\r\n");
  let p_te_cl = http.parse_request(&r_te_cl);
  let h_te_cl = app.handle_route(m_echo, &p_te_cl, "{\"a\":1}", test_handler);
  f = f + check("TE+CL rejected 400", h_te_cl.status == 400);
  let r_te_gzip = req_bytes("POST /echo HTTP/1.1\r\nHost: t\r\nTransfer-Encoding: gzip\r\n\r\n");
  let p_te_gzip = http.parse_request(&r_te_gzip);
  let h_te_gzip = app.handle_route(m_echo, &p_te_gzip, "", test_handler);
  f = f + check("TE gzip rejected 501", h_te_gzip.status == 501);
  let r_te_chunked = req_bytes("POST /echo HTTP/1.1\r\nHost: t\r\nTransfer-Encoding: chunked\r\n\r\n4\r\nWiki\r\n5\r\npedia\r\n0\r\n\r\n");
  let he_ck1 = http.find_header_end(&r_te_chunked);
  f = f + check("te chunked detected", http.te_is_chunked(http.transfer_encoding_of(&r_te_chunked, he_ck1)));
  f = f + check("chunked_state complete", http.chunked_state(&r_te_chunked, he_ck1) == 1);
  let p_ck1 = http.parse_request(&r_te_chunked);
  f = f + check("chunked parse ok", p_ck1.ok);
  f = f + check("chunked body Wikipedia", http.bytes_to_str(&p_ck1.body, 0, p_ck1.body.len()) == "Wikipedia");
  let h_ck1 = app.handle_route(m_echo, &p_ck1, "Wikipedia", test_handler);
  f = f + check("chunked alone reaches handler", h_ck1.status == 200);
  let cdec = http.decode_chunked(&r_te_chunked, he_ck1, 3);
  f = f + check("chunked decoded cap", !cdec.ok && contains(cdec.error, "too large"));

  let r_ck2 = req_bytes("POST /echo HTTP/1.1\r\nHost: t\r\nTransfer-Encoding: chunked\r\n\r\n4;ext=1\r\nWiki\r\n0\r\nX-Trailer: v\r\n\r\n");
  let he_ck2 = http.find_header_end(&r_ck2);
  f = f + check("chunked trailer state complete", http.chunked_state(&r_ck2, he_ck2) == 1);
  let p_ck2 = http.parse_request(&r_ck2);
  f = f + check("chunked ext+trailer ok", p_ck2.ok && http.bytes_to_str(&p_ck2.body, 0, p_ck2.body.len()) == "Wiki");

  let r_ck3 = req_bytes("POST /echo HTTP/1.1\r\nHost: t\r\nTransfer-Encoding: chunked\r\n\r\nzz\r\n");
  let he_ck3 = http.find_header_end(&r_ck3);
  f = f + check("chunked malformed state", http.chunked_state(&r_ck3, he_ck3) == -1);
  let p_ck3 = http.parse_request(&r_ck3);
  f = f + check("chunked malformed parse", !p_ck3.ok && contains(p_ck3.error, "malformed"));

  let r_ck4 = req_bytes("POST /echo HTTP/1.1\r\nHost: t\r\nTransfer-Encoding: chunked\r\n\r\n4\r\nWiki\r\n");
  let he_ck4 = http.find_header_end(&r_ck4);
  f = f + check("chunked partial state", http.chunked_state(&r_ck4, he_ck4) == 0);
  let p_ck4 = http.parse_request(&r_ck4);
  f = f + check("chunked partial parse", !p_ck4.ok && contains(p_ck4.error, "incomplete"));

  let r_ck5 = req_bytes("POST /echo HTTP/1.1\r\nHost: t\r\nTransfer-Encoding: chunked\r\n\r\n1\r\na\r\n1\r\nb\r\n0\r\n\r\n");
  let p_ck5 = http.parse_request(&r_ck5);
  f = f + check("chunked multi-chunk", p_ck5.ok && http.bytes_to_str(&p_ck5.body, 0, p_ck5.body.len()) == "ab");
  let fe_ck5 = http.framed_end(&r_ck5);
  f = f + check("framed_end chunked complete", fe_ck5 == r_ck5.len());

  let r_ck6 = req_bytes("POST /echo HTTP/1.1\r\nHost: t\r\nTransfer-Encoding: gzip\r\n\r\n");
  let he_ck6 = http.find_header_end(&r_ck6);
  f = f + check("te gzip not chunked", !http.te_is_chunked(http.transfer_encoding_of(&r_ck6, he_ck6)));
  let p_ck6 = http.parse_request(&r_ck6);
  f = f + check("te gzip parse empty body", p_ck6.ok && p_ck6.body.len() == 0);

  let expl = http.parse_request(&req_bytes("POST /echo HTTP/1.1\r\nHost: t\r\nExpect: 100-continue\r\nContent-Length: 1\r\n\r\nz"));
  f = f + check("expects continue", http.expects_continue(&expl));
  let expn = http.parse_request(&req_bytes("POST /echo HTTP/1.1\r\nHost: t\r\n\r\n"));
  f = f + check("expects continue absent", !http.expects_continue(&expn));

  // --- D. builders, status text, security headers ---------------------------
  let resp = http.build_response(200, "{\"status\":\"ok\"}", false);
  let resp_str = http.bytes_to_str(&resp, 0, resp.len());
  f = f + check("status line", contains(resp_str, "HTTP/1.1 200 OK\r\n"));
  f = f + check("build_response close keeps close", contains(resp_str, "Connection: close\r\n"));
  f = f + check("content-type json", contains(resp_str, "Content-Type: application/json"));
  f = f + check("content-length 15", contains(resp_str, "Content-Length: 15\r\n"));
  f = f + check("body at end", string.str_ends_with(resp_str, "{\"status\":\"ok\"}"));
  let resp_keep = http.build_response(200, "{\"status\":\"ok\"}", true);
  let resp_keep_str = http.bytes_to_str(&resp_keep, 0, resp_keep.len());
  f = f + check("build_response keep omits close", !contains(resp_keep_str, "Connection: close"));
  f = f + check("build_response keep body intact", string.str_ends_with(resp_keep_str, "{\"status\":\"ok\"}"));

  f = f + check("status text 200", http.status_text(200) == "OK");
  f = f + check("status text 304", http.status_text(304) == "Not Modified");
  f = f + check("status text 408", http.status_text(408) == "Request Timeout");
  f = f + check("status text 501", http.status_text(501) == "Not Implemented");
  f = f + check("status text unknown", http.status_text(999) == "Unknown");

  let respd = http.with_header_line(&resp, "Date: Thu, 01 Jan 1970 00:00:00 GMT");
  let respd_str = http.bytes_to_str(&respd, 0, respd.len());
  f = f + check("with_header_line after status", contains(respd_str, "HTTP/1.1 200 OK\r\nDate: Thu, 01 Jan 1970 00:00:00 GMT\r\n"));
  f = f + check("with_header_line keeps body", contains(respd_str, "{\"status\":\"ok\"}"));

  var extra: Vec[(Str, Str)] = Vec[(Str, Str)].new();
  extra.push(("Allow", "GET, POST"));
  let resp_full = http.build_response_full(405, "application/json; charset=utf-8", &extra, "{\"error\":{}}", false);
  let resp_full_str = http.bytes_to_str(&resp_full, 0, resp_full.len());
  f = f + check("build_response_full extra header", contains(resp_full_str, "Allow: GET, POST\r\n"));
  var raw_body: Vec[UInt8] = Vec[UInt8].new();
  raw_body.push(1u8);
  raw_body.push(2u8);
  raw_body.push(3u8);
  var no_hdrs: Vec[(Str, Str)] = Vec[(Str, Str)].new();
  let resp_bytes = http.build_response_bytes(200, "application/octet-stream", &no_hdrs, &raw_body, true);
  let resp_bytes_str = http.bytes_to_str(&resp_bytes, 0, resp_bytes.len());
  f = f + check("build_response_bytes length", contains(resp_bytes_str, "Content-Length: 3\r\n"));
  f = f + check("build_response_bytes keep omits close", !contains(resp_bytes_str, "Connection: close"));

  // Server token seam: neutral default in BOTH builders, then override path.
  f = f + check("server default token accessor", app.app_server_token() == "xiom-pulse");
  f = f + check("server default header full bytes", contains(resp_str, "Server: xiom-pulse\r\n"));
  f = f + check("server default header bytes path", contains(resp_bytes_str, "Server: xiom-pulse\r\n"));
  f = f + check("server default exactly once full", occurrences(resp_str, "Server: ") == 1);
  f = f + check("server default exactly once bytes", occurrences(resp_bytes_str, "Server: ") == 1);
  f = f + check("server default version-free", !contains(resp_str, "Server: xiom-pulse/") && !contains(resp_bytes_str, "Server: xiom-pulse/"));

  let set_ok = app.app_set_server_token("xiom-pulse-station/1.4.2");
  f = f + check("server token override accepted", set_ok && app.app_server_token() == "xiom-pulse-station/1.4.2");
  let ov_full = http.build_response(200, "{}", false);
  let ov_full_str = http.bytes_to_str(&ov_full, 0, ov_full.len());
  f = f + check("server override reflected full", contains(ov_full_str, "Server: xiom-pulse-station/1.4.2\r\n") && occurrences(ov_full_str, "Server: ") == 1);
  let ov_bytes = http.build_response_bytes(200, "application/octet-stream", &no_hdrs, &raw_body, true);
  let ov_bytes_str = http.bytes_to_str(&ov_bytes, 0, ov_bytes.len());
  f = f + check("server override reflected bytes", contains(ov_bytes_str, "Server: xiom-pulse-station/1.4.2\r\n") && occurrences(ov_bytes_str, "Server: ") == 1);
  let bad_tok = app.app_set_server_token("bad\r\nX-Injected: 1");
  f = f + check("server token rejects CRLF injection", !bad_tok && app.app_server_token() == "xiom-pulse-station/1.4.2");
  let bad_tok2 = app.app_set_server_token("");
  f = f + check("server token rejects empty", !bad_tok2 && app.app_server_token() == "xiom-pulse-station/1.4.2");
  let restored = app.app_set_server_token("xiom-pulse");
  f = f + check("server token restore default", restored && app.app_server_token() == "xiom-pulse");

  f = f + check("security nosniff", contains(resp_str, "X-Content-Type-Options: nosniff"));
  f = f + check("security frame deny", contains(resp_str, "X-Frame-Options: DENY"));
  f = f + check("security coop", contains(resp_str, "Cross-Origin-Opener-Policy: same-origin"));
  f = f + check("security hsts", contains(resp_str, "Strict-Transport-Security: max-age=15552000; includeSubDomains"));
  f = f + check("security block on bytes path", contains(resp_bytes_str, "X-Content-Type-Options: nosniff"));

  // --- E. query parsing / URL decoding / v1 alias ---------------------------
  let st = router.split_target("/api/items/42?x=1&y=2");
  f = f + check("split_target path", st.0 == "/api/items/42");
  f = f + check("split_target query", st.1 == "x=1&y=2");
  let st2 = router.split_target("/health");
  f = f + check("split_target no query", st2.0 == "/health" && st2.1 == "");
  f = f + check("url_decode plus", router.url_decode("a+b") == "a b");
  f = f + check("url_decode hex", router.url_decode("x%21%7E") == "x!~");
  let qp = router.parse_query("a=1&b=hello%20world&c");
  let n2 = qp.0[2];
  let v1 = qp.1[1];
  let v2 = qp.1[2];
  f = f + check("parse_query count", qp.0.len() == 3 && n2 == "c");
  f = f + check("parse_query decoded", v1 == "hello world");
  f = f + check("parse_query flag empty", v2 == "");
  f = f + check("v1 alias path+query", router.v1_path("/v1/api/events?limit=1") == "/api/events?limit=1");
  f = f + check("v1 alias root", router.v1_path("/v1") == "/");
  f = f + check("v1 passthrough", router.v1_path("/health") == "/health");

  // --- F. router mechanism --------------------------------------------------
  let m_ok = router.route_match("GET", "/health", &defs);
  f = f + check("route matched kind/route_id", m_ok.kind == 1 && m_ok.route_id == 1);
  let m_405 = router.route_match("POST", "/health", &defs);
  f = f + check("route 405 kind", m_405.kind == 2);
  f = f + check("route 405 allow list", m_405.allow == "GET");
  let m_404 = router.route_match("GET", "/nope", &defs);
  f = f + check("route 404 kind", m_404.kind == 0);
  let mq = router.route_match("GET", "/items/7?x=1", &defs);
  let pv0 = mq.param_values[0];
  let pn0 = mq.param_names[0];
  let qn0 = mq.query_names[0];
  let qv0 = mq.query_values[0];
  f = f + check("route param captured", mq.kind == 1 && mq.route_id == 3 && pn0 == "id" && pv0 == "7");
  f = f + check("route query parsed", qn0 == "x" && qv0 == "1");
  let m_hq = router.route_match("GET", "/health?debug=1", &defs);
  f = f + check("route health with query", m_hq.kind == 1 && m_hq.route_id == 1);
  let m_g1 = router.route_match("GET", "/echo", &defs);
  f = f + check("shape-only method mismatch 405", m_g1.kind == 2 && m_g1.allow == "POST");
  let m_empty = router.route_match("GET", "/health", &no_hdrs);
  f = f + check("empty table -> 404", m_empty.kind == 0);

  let rid1 = app.register("GET", "/hello");
  let rid2 = app.register("GET", "/items/:id");
  f = f + check("register returns 1-based ids", rid1 == 1 && rid2 == 2);
  f = f + check("routes_list length", app.routes_list().len() == 2);
  let reg_routes = app.routes_list();
  let m_reg = router.route_match("GET", "/hello", &reg_routes);
  f = f + check("registered route matches", m_reg.kind == 1 && m_reg.route_id == 1);
  let r_quit_shape = req_bytes("GET /hello HTTP/1.1\r\nHost: t\r\nX-Pulse-Quit: 1\r\n\r\n");
  let p_quit_shape = http.parse_request(&r_quit_shape);
  f = f + check("quit header readable", http.header_get(&p_quit_shape, "x-pulse-quit") == "1");

  let r_post_hello = req_bytes("POST /hello HTTP/1.1\r\nHost: t\r\nContent-Length: 0\r\n\r\n");
  let p_post_hello = http.parse_request(&r_post_hello);
  let m_post_hello = router.route_match("POST", "/hello", &reg_routes);
  let h_post_hello = app.handle_route(m_post_hello, &p_post_hello, "", test_handler);
  let allow_hdr = h_post_hello.headers[0];
  f = f + check("dispatch 405 allow", h_post_hello.status == 405 && allow_hdr.1 == "GET");
  let r_nf = req_bytes("GET /missing HTTP/1.1\r\nHost: t\r\n\r\n");
  let p_nf = http.parse_request(&r_nf);
  let m_nf = router.route_match("GET", "/missing", &reg_routes);
  let h_nf = app.handle_route(m_nf, &p_nf, "", test_handler);
  f = f + check("dispatch 404 envelope", h_nf.status == 404 && contains(h_nf.body, "\"code\":\"not_found\""));
  let h_ok = app.handle_route(m_reg, &p_quit_shape, "", test_handler);
  f = f + check("dispatch handler reached", h_ok.status == 200 && contains(h_ok.body, "\"/hello\""));

  // --- I. hook seam (pre_route + after_response) ----------------------------
  let p_hook_req = http.parse_request(&req_bytes("GET /hello HTTP/1.1\r\nHost: t\r\n\r\n"));
  let p_hook_missing = http.parse_request(&req_bytes("GET /missing HTTP/1.1\r\nHost: t\r\n\r\n"));
  let p_hook_options = http.parse_request(&req_bytes("OPTIONS /hello HTTP/1.1\r\nHost: t\r\n\r\n"));

  let hs_empty = app.hooks_new();
  f = f + check("hooks empty by default", !app.hooks_has_pre(&hs_empty) && !app.hooks_has_after(&hs_empty));
  hook_order = "";
  hook_handler_calls = 0;
  let base_route = app.handle_route(m_reg, &p_hook_req, "", hook_handler);
  let base_calls = hook_handler_calls;
  let base_hook = app.dispatch_with(&hs_empty, "GET", &p_hook_req, "", hook_handler);
  f = f + check("no-hook dispatch matches handle_route", base_hook.status == base_route.status && base_hook.body == base_route.body);
  f = f + check("no-hook dispatch keeps handler path", hook_handler_calls == base_calls + 1);
  f = f + check("no-hook dispatch runs no hooks", hook_order == "handler;handler;");

  var hs_after = app.hooks_new();
  let after_installed = app.hooks_install_after(&mut hs_after, hook_after_observe);
  f = f + check("install after hook ok", after_installed.is_ok());
  f = f + check("has after hook", app.hooks_has_after(&hs_after) && !app.hooks_has_pre(&hs_after));
  hook_order = "";
  hook_handler_calls = 0;
  hook_seen_status = 0;
  hook_seen_bytes = -1;
  hook_seen_duration = -1;
  let out_after = app.dispatch_with(&hs_after, "GET", &p_hook_req, "", hook_handler);
  f = f + check("post hook sees status", out_after.status == 201 && hook_seen_status == 201);
  f = f + check("post hook sees response bytes", hook_seen_bytes == 5);
  f = f + check("post hook sees duration", hook_seen_duration >= 0);
  f = f + check("post hook runs after handler", hook_order == "handler;after;");

  var hs_both = app.hooks_new();
  let _ip = app.hooks_install_pre(&mut hs_both, hook_pre_order);
  let _ia = app.hooks_install_after(&mut hs_both, hook_after_observe);
  hook_order = "";
  hook_handler_calls = 0;
  let out_both = app.dispatch_with(&hs_both, "GET", &p_hook_req, "", hook_handler);
  f = f + check("hook ordering pre/handler/after", out_both.status == 201 && hook_order == "pre;handler;after;");

  hook_order = "";
  hook_handler_calls = 0;
  hook_seen_status = 0;
  let out_404 = app.dispatch_with(&hs_both, "GET", &p_hook_missing, "", hook_handler);
  f = f + check("post hook sees policy 404", out_404.status == 404 && hook_seen_status == 404);
  f = f + check("post hook wraps 404 without handler", hook_handler_calls == 0 && hook_order == "pre;after;");

  var hs_cors = app.hooks_new();
  let _cp = app.hooks_install_pre(&mut hs_cors, hook_pre_cors);
  let _ca = app.hooks_install_after(&mut hs_cors, hook_after_observe);
  hook_order = "";
  hook_handler_calls = 0;
  hook_seen_status = 0;
  let out_cors = app.dispatch_with(&hs_cors, "OPTIONS", &p_hook_options, "", hook_handler);
  f = f + check("pre hook short-circuits preflight", out_cors.status == 204);
  f = f + check("short-circuit response keeps headers", out_cors.headers.len() == 1 && out_cors.headers[0].1 == "*");
  f = f + check("short-circuit skips handler", hook_handler_calls == 0 && hook_order == "preflight;after;");
  f = f + check("post hook observes short-circuit", hook_seen_status == 204);

  var hs_err = app.hooks_new();
  let first_pre = app.hooks_install_pre(&mut hs_err, hook_pre_order);
  f = f + check("install pre hook ok", first_pre.is_ok() && app.hooks_has_pre(&hs_err));
  let dup_pre = app.hooks_install_pre(&mut hs_err, hook_pre_order);
  f = f + check("duplicate pre hook rejected", dup_pre.is_err());
  var dup_pre_code: Str = "";
  if dup_pre.is_err {
    let e = dup_pre.unwrap_err();
    dup_pre_code = app.hook_error_code(&e);
  }
  f = f + check("duplicate pre hook typed code", dup_pre_code == "pre_already_installed");
  var dup_after_code: Str = "";
  let first_after = app.hooks_install_after(&mut hs_err, hook_after_observe);
  let dup_after = app.hooks_install_after(&mut hs_err, hook_after_observe);
  if dup_after.is_err {
    let e2 = dup_after.unwrap_err();
    dup_after_code = app.hook_error_code(&e2);
  }
  f = f + check("duplicate after hook rejected typed", first_after.is_ok() && dup_after.is_err() && dup_after_code == "after_already_installed");
  f = f + check("clear pre hook", app.hooks_clear_pre(&mut hs_err) && !app.hooks_has_pre(&hs_err));
  f = f + check("clear pre hook idempotent", !app.hooks_clear_pre(&mut hs_err));
  f = f + check("clear both hooks", app.hooks_clear(&mut hs_err) && !app.hooks_has_after(&hs_err));

  // --- G. keep-alive semantics (pure decisions) -----------------------------
  let ka11 = http.parse_request(&req_bytes("GET /health HTTP/1.1\r\nHost: t\r\n\r\n"));
  f = f + check("ka 1.1 default reuse", !http.connection_close_requested(&ka11));
  let kaclose = http.parse_request(&req_bytes("GET /health HTTP/1.1\r\nHost: t\r\nConnection: close\r\n\r\n"));
  f = f + check("ka close token", http.connection_close_requested(&kaclose));
  let kact = http.parse_request(&req_bytes("GET /health HTTP/1.1\r\nHost: t\r\nConnection: keep-alive, CLOSE\r\n\r\n"));
  f = f + check("ka close comma token case-insensitive", http.connection_close_requested(&kact));
  let kakl = http.parse_request(&req_bytes("GET /health HTTP/1.1\r\nHost: t\r\nConnection: keep-alive\r\n\r\n"));
  f = f + check("ka keep-alive token stays open", !http.connection_close_requested(&kakl));
  let ka10 = http.parse_request(&req_bytes("GET /health HTTP/1.0\r\nHost: t\r\n\r\n"));
  f = f + check("ka 1.0 no reuse", http.connection_close_requested(&ka10));
  let ka10kl = http.parse_request(&req_bytes("GET /health HTTP/1.0\r\nHost: t\r\nConnection: keep-alive\r\n\r\n"));
  f = f + check("ka 1.0 keep-alive not honored", http.connection_close_requested(&ka10kl));

  env.remove_var("PULSE_KEEPALIVE");
  env.remove_var("PULSE_IDLE_TIMEOUT");
  env.remove_var("PULSE_READ_TIMEOUT");
  f = f + check("cfg_keepalive default on", config.cfg_keepalive());
  env.set_var("PULSE_KEEPALIVE", "0");
  f = f + check("PULSE_KEEPALIVE=0 disables", !config.cfg_keepalive());
  env.set_var("PULSE_KEEPALIVE", "1");
  f = f + check("PULSE_KEEPALIVE=1 enables", config.cfg_keepalive());
  env.remove_var("PULSE_KEEPALIVE");
  f = f + check("cfg_read_timeout default 30000", config.cfg_read_timeout() == 30000);
  f = f + check("cfg_write_timeout default 30000", config.cfg_write_timeout() == 30000);
  f = f + check("cfg_idle_timeout default 5000", config.cfg_idle_timeout() == 5000);
  env.set_var("PULSE_IDLE_TIMEOUT", "250");
  f = f + check("cfg_idle_timeout env override", config.cfg_idle_timeout() == 250);
  env.remove_var("PULSE_IDLE_TIMEOUT");

  // --- H. loopback end-to-end (runner + state machine) ----------------------
  env.set_var("PULSE_KEEPALIVE", "1");
  env.set_var("PULSE_IDLE_TIMEOUT", "300");
  env.set_var("PULSE_READ_TIMEOUT", "5000");
  env.set_var("PULSE_WRITE_TIMEOUT", "5000");

  let pipe_req = "GET /hello HTTP/1.1\r\nHost: t\r\n\r\nGET /items/9 HTTP/1.1\r\nHost: t\r\nConnection: close\r\n\r\n";
  let pipe_out = e2e_round_trip(18730, pipe_req);
  let pipe_ok = occurrences(pipe_out, "HTTP/1.1 200 OK") == 2;
  f = f + check("e2e pipelined two responses one fd", pipe_ok);
  if pipe_ok {
    let pparts = string.str_split(pipe_out, "HTTP/1.1 200 OK");
    f = f + check("e2e first response no close", !contains(pparts[1], "Connection: close"));
    f = f + check("e2e second response closes", contains(pparts[2], "Connection: close"));
    let idx_first = string.str_index_of(pipe_out, "\"/hello\"").value;
    let idx_second = string.str_index_of(pipe_out, "\"/items/9\"").value;
    f = f + check("e2e responses in order", idx_first < idx_second);
  } else {
    f = f + check("e2e first response no close", false);
    f = f + check("e2e second response closes", false);
    f = f + check("e2e responses in order", false);
  }

  let t_idle0 = time.monotonic_ms();
  let idle_out = e2e_round_trip(18760, "GET /hello HTTP/1.1\r\nHost: t\r\n\r\n");
  let t_idle1 = time.monotonic_ms();
  f = f + check("e2e idle one response", occurrences(idle_out, "HTTP/1.1 200 OK") == 1);
  f = f + check("e2e idle no 408", !contains(idle_out, "408 Request Timeout"));
  f = f + check("e2e idle no close header", !contains(idle_out, "Connection: close"));
  f = f + check("e2e idle deadline elapsed", (t_idle1 - t_idle0) >= 200);

  env.set_var("PULSE_KEEPALIVE", "0");
  let off_out = e2e_round_trip(18790, "GET /hello HTTP/1.1\r\nHost: t\r\n\r\n");
  f = f + check("e2e keepalive=0 one response", occurrences(off_out, "HTTP/1.1 200 OK") == 1);
  f = f + check("e2e keepalive=0 forces close", contains(off_out, "Connection: close"));

  env.set_var("PULSE_KEEPALIVE", "1");
  let cont_req = "GET /hello HTTP/1.1\r\nHost: t\r\nExpect: 100-continue\r\nContent-Length: 2\r\n\r\nok";
  let cont_out = e2e_round_trip(18820, cont_req);
  let has_interim = contains(cont_out, "HTTP/1.1 100 Continue");
  let has_final = occurrences(cont_out, "HTTP/1.1 200 OK") == 1;
  f = f + check("e2e 100-continue interim sent", has_interim);
  f = f + check("e2e 100-continue final response", has_final);
  if has_interim && has_final {
    f = f + check("e2e 100-continue interim first", string.str_index_of(cont_out, "HTTP/1.1 100 Continue").value < string.str_index_of(cont_out, "HTTP/1.1 200 OK").value);
  } else {
    f = f + check("e2e 100-continue interim first", false);
  }

  var hs_e2e = app.hooks_new();
  let _ep = app.hooks_install_pre(&mut hs_e2e, hook_pre_cors);
  let _ea = app.hooks_install_after(&mut hs_e2e, hook_after_observe);
  hook_order = "";
  hook_handler_calls = 0;
  hook_seen_status = 0;
  let cors_out = e2e_round_trip_with(18860, "OPTIONS /hello HTTP/1.1\r\nHost: t\r\n\r\n", &hs_e2e);
  let cors_204 = contains(cors_out, "HTTP/1.1 204");
  f = f + check("e2e hook preflight status 204", cors_204);
  f = f + check("e2e hook preflight cors header", contains(cors_out, "Access-Control-Allow-Origin: *"));
  f = f + check("e2e hook preflight skips handler", hook_handler_calls == 0);
  f = f + check("e2e hook post observed status", hook_seen_status == 204);

  env.remove_var("PULSE_KEEPALIVE");
  env.remove_var("PULSE_IDLE_TIMEOUT");
  env.remove_var("PULSE_READ_TIMEOUT");
  env.remove_var("PULSE_WRITE_TIMEOUT");

  // --- J. declared Content-Length body-cap hardening ------------------------
  // A non-chunked request whose declared Content-Length exceeds the body cap
  // must fail as "body too large" even when only a partial body arrived; the
  // server maps any "too large" error to 413. Raw bytes only, no network.
  let lim = http.body_limit_bytes();
  let r_cl_limit = cl_request_bytes(lim, lim);
  let p_cl_limit = http.parse_request(&r_cl_limit);
  f = f + check("CL at body limit accepted", p_cl_limit.ok && p_cl_limit.body.len() == lim);
  let r_cl_over = cl_request_bytes(lim + 1, lim + 1);
  let p_cl_over = http.parse_request(&r_cl_over);
  f = f + check("CL limit+1 rejected", !p_cl_over.ok && p_cl_over.error == "body too large");
  f = f + check("CL limit+1 maps to 413 class", contains(p_cl_over.error, "too large"));
  let r_cl_repro = cl_request_bytes(1048600, 1048600);
  let p_cl_repro = http.parse_request(&r_cl_repro);
  f = f + check("CL 1048600 repro rejected", !p_cl_repro.ok && p_cl_repro.error == "body too large" && p_cl_repro.body.len() == 0);
  let r_cl_trunc_over = cl_request_bytes(1048600, 100);
  let p_cl_trunc_over = http.parse_request(&r_cl_trunc_over);
  f = f + check("CL oversized truncated body rejected", !p_cl_trunc_over.ok && p_cl_trunc_over.error == "body too large");
  let r_cl_trunc_ok = req_bytes("POST /echo HTTP/1.1\r\nHost: t\r\nContent-Length: 5\r\n\r\nab");
  let p_cl_trunc_ok = http.parse_request(&r_cl_trunc_ok);
  f = f + check("CL truncated at/below limit unchanged", p_cl_trunc_ok.ok && p_cl_trunc_ok.body.len() == 2);

  // --- K. stateful hook seam (HookCtx) --------------------------------------
  // Handle-bag accessors: push/len/get/set/clear, out-of-range safe.
  var bag = app.hookctx_new();
  f = f + check("ctx new is empty", app.hookctx_len(&bag) == 0);
  let pushed_idx = app.hookctx_push(&mut bag, 7);
  f = f + check("ctx push index/len/get", pushed_idx == 0 && app.hookctx_len(&bag) == 1 && app.hookctx_get(&bag, 0) == 7);
  f = f + check("ctx get out of range is 0", app.hookctx_get(&bag, -1) == 0 && app.hookctx_get(&bag, 99) == 0);
  f = f + check("ctx set out of range false", !app.hookctx_set(&mut bag, 1, 5));
  f = f + check("ctx set in range true", app.hookctx_set(&mut bag, 0, 11) && app.hookctx_get(&bag, 0) == 11);
  f = f + check("ctx clear non-empty true", app.hookctx_clear(&mut bag) && app.hookctx_len(&bag) == 0);
  f = f + check("ctx clear idempotent false", !app.hookctx_clear(&mut bag));

  // Pre-hook mutation is visible to the stateful after hook.
  var hs_mut = app.hooks_new();
  let _ma = app.hooks_install_after_ctx(&mut hs_mut, mix_after_ctx);
  var bag_mut = app.hookctx_new();
  let _bm = app.hookctx_push(&mut bag_mut, 42);
  ctx_after_seen = -1;
  ctx_after_status = 0;
  let out_mut = app.dispatch_with_ctx(&hs_mut, &mut bag_mut, "GET", &p_hook_req, "", hook_handler);
  f = f + check("ctx mutation visible in after", out_mut.status == 201 && ctx_after_seen == 42 && ctx_after_status == 201);

  // Mixing stateless + stateful: stateless first, then stateful; mutation
  // made by the stateful pre hook is visible to the stateful after hook.
  var hs_mix = app.hooks_new();
  let _mp = app.hooks_install_pre(&mut hs_mix, mix_pre_order);
  let _mpc = app.hooks_install_pre_ctx(&mut hs_mix, mix_pre_ctx);
  let _ma2 = app.hooks_install_after(&mut hs_mix, mix_after_order);
  let _mac = app.hooks_install_after_ctx(&mut hs_mix, mix_after_ctx);
  ctx_order = "";
  hook_handler_calls = 0;
  ctx_after_seen = -1;
  var bag_mix = app.hookctx_new();
  let out_mix = app.dispatch_with_ctx(&hs_mix, &mut bag_mix, "GET", &p_hook_req, "", hook_handler);
  f = f + check("mixed hook order", out_mix.status == 201 && ctx_order == "pre;prectx;after;afterctx;");
  f = f + check("mixed hooks run stateless first", hook_handler_calls == 1);
  f = f + check("mixed hooks share ctx", app.hookctx_len(&bag_mix) == 1 && ctx_after_seen == 7);

  // Phase B limiter shape: bag = [count, limit]; short-circuit on the
  // request after the limit and keep mutating the same bag.
  var hs_lim = app.hooks_new();
  let _lp = app.hooks_install_pre_ctx(&mut hs_lim, limiter_bump);
  let _la = app.hooks_install_after_ctx(&mut hs_lim, limiter_after);
  var bag_lim = app.hookctx_new();
  let _l0 = app.hookctx_push(&mut bag_lim, 0);
  let _l1 = app.hookctx_push(&mut bag_lim, 3);
  hook_handler_calls = 0;
  limiter_after_status = 0;
  let lim1 = app.dispatch_with_ctx(&hs_lim, &mut bag_lim, "GET", &p_hook_req, "", hook_handler);
  let lim2 = app.dispatch_with_ctx(&hs_lim, &mut bag_lim, "GET", &p_hook_req, "", hook_handler);
  let lim3 = app.dispatch_with_ctx(&hs_lim, &mut bag_lim, "GET", &p_hook_req, "", hook_handler);
  let lim4 = app.dispatch_with_ctx(&hs_lim, &mut bag_lim, "GET", &p_hook_req, "", hook_handler);
  f = f + check("limiter allows first three", lim1.status == 201 && lim2.status == 201 && lim3.status == 201);
  f = f + check("limiter short-circuits Nth", lim4.status == 429 && contains(lim4.body, "rate_limited"));
  f = f + check("limiter counter persisted", app.hookctx_get(&bag_lim, 0) == 4);
  f = f + check("limiter skips handler on stop", hook_handler_calls == 3);
  f = f + check("limiter after sees 429", limiter_after_status == 429);
  var bag_404 = app.hookctx_new();
  ctx_after_status = 0;
  let out_ctx_404 = app.dispatch_with_ctx(&hs_mut, &mut bag_404, "GET", &p_hook_missing, "", hook_handler);
  f = f + check("ctx after sees policy 404", out_ctx_404.status == 404 && ctx_after_status == 404);

  // Empty-hook and stateless-only paths stay byte-identical to the
  // hook-free dispatch (the ctx-carrying path with no ctx hooks included).
  let base_plain = app.handle_route(m_reg, &p_hook_req, "", hook_handler);
  var bag_none = app.hookctx_new();
  let base_ctx = app.dispatch_with_ctx(&hs_empty, &mut bag_none, "GET", &p_hook_req, "", hook_handler);
  let base_plain_resp = http.build_response_full(base_plain.status, base_plain.content_type, &base_plain.headers, base_plain.body, false);
  let base_ctx_resp = http.build_response_full(base_ctx.status, base_ctx.content_type, &base_ctx.headers, base_ctx.body, false);
  let base_plain_bytes = http.bytes_to_str(&base_plain_resp, 0, base_plain_resp.len());
  let base_ctx_bytes = http.bytes_to_str(&base_ctx_resp, 0, base_ctx_resp.len());
  f = f + check("empty hooks ctx path byte-identical", base_plain_bytes == base_ctx_bytes);

  var hs_stateless = app.hooks_new();
  let _sp = app.hooks_install_pre(&mut hs_stateless, hook_pre_order);
  let _sa = app.hooks_install_after(&mut hs_stateless, hook_after_observe);
  var bag_stateless = app.hookctx_new();
  hook_order = "";
  let stat_plain = app.dispatch_with(&hs_stateless, "GET", &p_hook_req, "", hook_handler);
  let stat_order_plain = hook_order;
  hook_order = "";
  let stat_ctx = app.dispatch_with_ctx(&hs_stateless, &mut bag_stateless, "GET", &p_hook_req, "", hook_handler);
  let stat_order_ctx = hook_order;
  let stat_plain_resp = http.build_response_full(stat_plain.status, stat_plain.content_type, &stat_plain.headers, stat_plain.body, false);
  let stat_ctx_resp = http.build_response_full(stat_ctx.status, stat_ctx.content_type, &stat_ctx.headers, stat_ctx.body, false);
  let stat_plain_bytes = http.bytes_to_str(&stat_plain_resp, 0, stat_plain_resp.len());
  let stat_ctx_bytes = http.bytes_to_str(&stat_ctx_resp, 0, stat_ctx_resp.len());
  f = f + check("stateless-only ctx bytes identical", stat_plain_bytes == stat_ctx_bytes);
  f = f + check("stateless-only hook order unchanged", stat_order_plain == "pre;handler;after;" && stat_order_ctx == stat_order_plain);
  f = f + check("stateless hooks ignore ctx bag", app.hookctx_len(&bag_stateless) == 0);

  // Typed error arms + coexistence of stateless and stateful registration.
  var hs_cerr = app.hooks_new();
  let ipc1 = app.hooks_install_pre_ctx(&mut hs_cerr, limiter_bump);
  let ipc2 = app.hooks_install_pre_ctx(&mut hs_cerr, limiter_bump);
  let iac1 = app.hooks_install_after_ctx(&mut hs_cerr, limiter_after);
  let iac2 = app.hooks_install_after_ctx(&mut hs_cerr, limiter_after);
  let ipc_err = ipc2.unwrap_err();
  let iac_err = iac2.unwrap_err();
  let ipc_code = app.hook_error_code(&ipc_err);
  let iac_code = app.hook_error_code(&iac_err);
  f = f + check("install pre_ctx ok", ipc1.is_ok() && app.hooks_has_pre(&hs_cerr));
  f = f + check("duplicate pre_ctx rejected typed", ipc2.is_err() && ipc_code == "pre_ctx_already_installed");
  f = f + check("install after_ctx ok", iac1.is_ok() && app.hooks_has_after(&hs_cerr));
  f = f + check("duplicate after_ctx rejected typed", iac2.is_err() && iac_code == "after_ctx_already_installed");
  let ip_mix = app.hooks_install_pre(&mut hs_cerr, mix_pre_order);
  let ia_mix = app.hooks_install_after(&mut hs_cerr, mix_after_order);
  f = f + check("stateless coexists with stateful", ip_mix.is_ok() && ia_mix.is_ok());
  f = f + check("clear removes both pre kinds", app.hooks_clear_pre(&mut hs_cerr) && !app.hooks_has_pre(&hs_cerr));
  f = f + check("clear leaves after installed", app.hooks_has_after(&hs_cerr));
  f = f + check("clear all removes after kinds", app.hooks_clear(&mut hs_cerr) && !app.hooks_has_after(&hs_cerr));

  // Real-fd plumbing: handle_connection_with_ctx carries the caller's bag.
  env.set_var("PULSE_KEEPALIVE", "0");
  env.set_var("PULSE_IDLE_TIMEOUT", "300");
  env.set_var("PULSE_READ_TIMEOUT", "5000");
  env.set_var("PULSE_WRITE_TIMEOUT", "5000");
  var hs_e2e_ctx = app.hooks_new();
  let _ecp = app.hooks_install_pre_ctx(&mut hs_e2e_ctx, limiter_bump);
  let _eca = app.hooks_install_after_ctx(&mut hs_e2e_ctx, limiter_after);
  var bag_e2e = app.hookctx_new();
  let _e0 = app.hookctx_push(&mut bag_e2e, 0);
  let _e1 = app.hookctx_push(&mut bag_e2e, 5);
  limiter_after_status = 0;
  let e2e_ctx_out = e2e_round_trip_ctx(18910, "GET /hello HTTP/1.1\r\nHost: t\r\n\r\n", &hs_e2e_ctx, &mut bag_e2e);
  f = f + check("e2e ctx pre hook ran", app.hookctx_get(&bag_e2e, 0) == 1);
  f = f + check("e2e ctx response ok", contains(e2e_ctx_out, "HTTP/1.1 200 OK"));
  f = f + check("e2e ctx after hook observed", limiter_after_status == 200);
  env.remove_var("PULSE_KEEPALIVE");
  env.remove_var("PULSE_IDLE_TIMEOUT");
  env.remove_var("PULSE_READ_TIMEOUT");
  env.remove_var("PULSE_WRITE_TIMEOUT");

  // --- L. unmatched-route fallback seam -------------------------------------
  // Absent fallback: dispatch_with with an empty HookSet is byte-identical
  // to the hook-free package 404.
  let p_site = http.parse_request(&req_bytes("GET /site/index.html HTTP/1.1\r\nHost: t\r\n\r\n"));
  let p_missing_fb = http.parse_request(&req_bytes("GET /missing HTTP/1.1\r\nHost: t\r\n\r\n"));
  let p_post_fb = http.parse_request(&req_bytes("POST /hello HTTP/1.1\r\nHost: t\r\nContent-Length: 0\r\n\r\n"));
  let hs_nofb = app.hooks_new();
  f = f + check("fallback absent by default", !app.hooks_has_fallback(&hs_nofb));
  let m_missing_fb = router.route_match("GET", "/missing", &app.routes_list());
  let direct_missing_fb = app.handle_route(m_missing_fb, &p_missing_fb, "", hook_handler);
  let nofb_out = app.dispatch_with(&hs_nofb, "GET", &p_missing_fb, "", hook_handler);
  let nofb_resp = http.build_response_full(nofb_out.status, nofb_out.content_type, &nofb_out.headers, nofb_out.body, false);
  let direct_resp = http.build_response_full(direct_missing_fb.status, direct_missing_fb.content_type, &direct_missing_fb.headers, direct_missing_fb.body, false);
  f = f + check("fallback absent keeps 404 body", nofb_out.status == 404 && nofb_out.body == direct_missing_fb.body);
  f = f + check("fallback absent 404 byte-identical", http.bytes_to_str(&nofb_resp, 0, nofb_resp.len()) == http.bytes_to_str(&direct_resp, 0, direct_resp.len()));

  // Installed fallback: unmatched paths become the fallback's HandlerOut
  // (site-like content + custom 404), and the registered handler never runs.
  var hs_fb = app.hooks_new();
  let install_fb = app.hooks_install_fallback(&mut hs_fb, site_fallback);
  f = f + check("install fallback ok", install_fb.is_ok() && app.hooks_has_fallback(&hs_fb));
  fallback_calls = 0;
  hook_handler_calls = 0;
  let site_out = app.dispatch_with(&hs_fb, "GET", &p_site, "", hook_handler);
  f = f + check("fallback serves site content", site_out.status == 200 && site_out.body == "<html><body>site</body></html>");
  f = f + check("fallback skips registered handler", hook_handler_calls == 0 && fallback_calls == 1);
  let custom404_out = app.dispatch_with(&hs_fb, "GET", &p_missing_fb, "", hook_handler);
  f = f + check("fallback custom 404 body", custom404_out.status == 404 && custom404_out.body == "<html><body>custom 404</body></html>");
  f = f + check("fallback receives decoded body", fallback_last_body == "");

  // The fallback is kind 0 only: a method mismatch stays 405.
  let post_fb_calls = fallback_calls;
  let fb_405 = app.dispatch_with(&hs_fb, "POST", &p_post_fb, "", hook_handler);
  f = f + check("fallback not used for kind 2", fb_405.status == 405 && fallback_calls == post_fb_calls && fb_405.headers[0].0 == "Allow");

  // The stateful dispatch path consults the same slot.
  var bag_fb = app.hookctx_new();
  let ctx_fb_out = app.dispatch_with_ctx(&hs_fb, &mut bag_fb, "GET", &p_missing_fb, "", hook_handler);
  f = f + check("fallback on ctx dispatch path", ctx_fb_out.status == 404 && ctx_fb_out.body == "<html><body>custom 404</body></html>");

  // Duplicate install is typed misuse.
  let dup_fb = app.hooks_install_fallback(&mut hs_fb, site_fallback);
  var dup_fb_code: Str = "";
  if dup_fb.is_err {
    let e_fb = dup_fb.unwrap_err();
    dup_fb_code = app.hook_error_code(&e_fb);
  }
  f = f + check("duplicate fallback rejected typed", dup_fb.is_err() && dup_fb_code == "fallback_already_installed");

  // Clearing restores the package 404; clearing is idempotent.
  f = f + check("clear fallback restores 404", app.hooks_clear_fallback(&mut hs_fb) && !app.hooks_has_fallback(&hs_fb));
  let cleared_out = app.dispatch_with(&hs_fb, "GET", &p_missing_fb, "", hook_handler);
  f = f + check("cleared fallback emits package 404", cleared_out.status == 404 && cleared_out.body == direct_missing_fb.body);
  f = f + check("clear fallback idempotent", !app.hooks_clear_fallback(&mut hs_fb));
  let _reinstall_fb = app.hooks_install_fallback(&mut hs_fb, site_fallback);
  f = f + check("hooks_clear removes fallback", app.hooks_clear(&mut hs_fb) && !app.hooks_has_fallback(&hs_fb));

  // Real-fd: the connection loop consults the fallback.
  env.set_var("PULSE_KEEPALIVE", "1");
  env.set_var("PULSE_IDLE_TIMEOUT", "300");
  env.set_var("PULSE_READ_TIMEOUT", "5000");
  env.set_var("PULSE_WRITE_TIMEOUT", "5000");
  var hs_fb_e2e = app.hooks_new();
  let _ifb_e2e = app.hooks_install_fallback(&mut hs_fb_e2e, site_fallback);
  let fb_e2e_out = e2e_round_trip_with(19000, "GET /site/index.html HTTP/1.1\r\nHost: t\r\nConnection: close\r\n\r\n", &hs_fb_e2e);
  f = f + check("e2e fallback custom route", contains(fb_e2e_out, "HTTP/1.1 200 OK") && contains(fb_e2e_out, "<html><body>site</body></html>"));

  // --- M. HEAD body trim ----------------------------------------------------
  // Build the response exactly as GET (same head, same Content-Length) and
  // send headers only: zero body bytes after the head terminator.
  let get_out = e2e_round_trip(19040, "GET /hello HTTP/1.1\r\nHost: t\r\nConnection: close\r\n\r\n");
  let get_body = response_body(get_out);
  let get_head_len = response_body_start(get_out);
  f = f + check("GET baseline status 200", contains(get_out, "HTTP/1.1 200 OK"));
  f = f + check("GET baseline unchanged body", get_body == "{\"echo\":\"/hello\"}");
  let head_out = e2e_round_trip(19080, "HEAD /hello HTTP/1.1\r\nHost: t\r\nConnection: close\r\n\r\n");
  let head_body = response_body(head_out);
  let head_head_len = response_body_start(head_out);
  f = f + check("HEAD status 200", contains(head_out, "HTTP/1.1 200 OK"));
  f = f + check("HEAD sends zero body bytes", head_body.len() == 0);
  let heads_equal = get_head_len > 0 && head_head_len == get_head_len && string.str_slice(head_out, 0, head_head_len) == string.str_slice(get_out, 0, get_head_len);
  f = f + check("HEAD headers identical to GET", heads_equal);
  f = f + check("HEAD Content-Length equals GET body", contains(head_out, "Content-Length: " + get_body.len().to_str() + "\r\n"));

  // HEAD through the hook path: hooks run, the handler is dispatched as GET,
  // and the body is still trimmed.
  var hs_head = app.hooks_new();
  let _ha_head = app.hooks_install_after(&mut hs_head, hook_after_observe);
  hook_seen_status = 0;
  let head_hook_out = e2e_round_trip_with(19120, "HEAD /hello HTTP/1.1\r\nHost: t\r\nConnection: close\r\n\r\n", &hs_head);
  f = f + check("HEAD hook path zero body", response_body(head_hook_out).len() == 0);
  f = f + check("HEAD hook path observes 200", contains(head_hook_out, "HTTP/1.1 200 OK") && hook_seen_status == 200);

  // HEAD through the caller-owned ctx loop (same trim, same Content-Length).
  var hs_head_ctx = app.hooks_new();
  var bag_head = app.hookctx_new();
  let head_ctx_out = e2e_round_trip_ctx(19160, "HEAD /hello HTTP/1.1\r\nHost: t\r\nConnection: close\r\n\r\n", &hs_head_ctx, &mut bag_head);
  f = f + check("HEAD ctx loop zero body", response_body(head_ctx_out).len() == 0);
  f = f + check("HEAD ctx loop keeps GET length", contains(head_ctx_out, "Content-Length: " + get_body.len().to_str() + "\r\n"));

  // HEAD + fallback: the fallback response is also built as GET and trimmed.
  var hs_head_fb = app.hooks_new();
  let _hfb = app.hooks_install_fallback(&mut hs_head_fb, site_fallback);
  let head_fb_out = e2e_round_trip_with(19200, "HEAD /site/index.html HTTP/1.1\r\nHost: t\r\nConnection: close\r\n\r\n", &hs_head_fb);
  let site_body_len = fb_e2e_out.len() - response_body_start(fb_e2e_out);
  f = f + check("HEAD fallback zero body", contains(head_fb_out, "HTTP/1.1 200 OK") && response_body(head_fb_out).len() == 0);
  f = f + check("HEAD fallback keeps GET length", contains(head_fb_out, "Content-Length: " + site_body_len.to_str() + "\r\n"));

  env.remove_var("PULSE_KEEPALIVE");
  env.remove_var("PULSE_IDLE_TIMEOUT");
  env.remove_var("PULSE_READ_TIMEOUT");
  env.remove_var("PULSE_WRITE_TIMEOUT");

  if f == 0 {
    io.println("xiom.pulse: all tests passed");
  } else {
    io.println("xiom.pulse: RED failures=" + f.to_str());
  }
  return f;
}
