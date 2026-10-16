// XIOM PULSE -- HTTP/1.1 server loop, routing and dispatch.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Single-threaded sequential-accept server: read/write deadlines bound
// every client wait (PULSE_READ_TIMEOUT / PULSE_WRITE_TIMEOUT); no
// select/threads -- one connection at a time by design.
// Reads go through the raw fd socket API because C-PULSE-01 disables one-arg
// `.read(...)` methods. TLS is terminated by the front proxy.
//
// Extraction note (xiom.pulse 0.1.0, 2026-10-16): verbatim carve of the
// frozen PULSE protocol core at 56eb9f8 (see PROVENANCE.md). Dropped from
// this file: site/static serving, icon, JWT, game, multipart, openapi,
// audit, metrics and access-log hooks, store/session wiring, CORS, CSRF,
// rate limiting and the product route table. The generic seam replaces the
// product dispatch: consumers call register(method, pattern) and pass one
// handler fn to serve(); handle_route keeps the frozen TE/CL smuggling
// policy and the 404/405 outcomes around that seam (see SPEC.md).
//
// Quit: send any request with header `X-Pulse-Quit: 1` (kept from the
// frozen loop as the clean-shutdown seam).
//
// Module name note (2026-10-08, from the frozen source): renamed from
// xiom.pulse.server to xiom.pulse.app -- a module whose last segment is
// `server` shadows the stdlib alias `server` (xiom.net.server) in every
// compilation that includes it, which broke src/http.xi's stdlib parser
// import.
module xiom.pulse.app

use xiom.net.socket;
use xiom.io;
use xiom.time;
use xiom.string;
use xiom.pulse.http;
use xiom.pulse.router;
use xiom.pulse.envelope;
use xiom.pulse.config;
use xiom.pulse.reqctx;

const MAX_BODY: Int = 1048576;
const CONTENT_JSON: Str = "application/json; charset=utf-8";
const CONTENT_TEXT: Str = "text/plain; charset=utf-8";

var req_counter: Int = 0;
var served: Int = 0;
var quit_requested: Bool = false;
var route_table: Vec[(Str, Str)] = Vec[(Str, Str)].new();

fn next_rid() -> Str {
  req_counter = req_counter + 1;
  return "r-" + req_counter.to_str();
}

/// HandlerOut - one dispatched response. When `body_bytes` is non-empty the
/// response is sent as raw bytes (icons/assets); otherwise `body` is text.
pub type HandlerOut = {
  status: Int;
  content_type: Str;
  headers: Vec[(Str, Str)];
  body: Str;
  body_bytes: Vec[UInt8];
}

// error_status_body injects the HTTP status into an error envelope
// ({"error":{"status":N,"code":...,"message":...}}) -- RFC 9457-friendly
// without changing the stable code/message contract; non-error bodies pass
// through untouched.
fn error_status_body(status: Int, body: Str) -> Str {
  if string.str_starts_with(body, "{\"error\":{") {
    return "{\"error\":{\"status\":" + status.to_str() + "," + string.str_slice(body, 10, body.len());
  }
  return body;
}

/// out_json wraps a JSON body with the status error envelope.
/// Complexity: O(body). Pure.
pub fn out_json(status: Int, body: Str) -> HandlerOut {
  return HandlerOut{ status: status; content_type: CONTENT_JSON; headers: Vec[(Str, Str)].new(); body: error_status_body(status, body); body_bytes: Vec[UInt8].new(); };
}

/// out_text wraps a text/plain body.
/// Complexity: O(body). Pure.
pub fn out_text(status: Int, body: Str) -> HandlerOut {
  return HandlerOut{ status: status; content_type: CONTENT_TEXT; headers: Vec[(Str, Str)].new(); body: body; body_bytes: Vec[UInt8].new(); };
}

/// out_html wraps a text/html body.
/// Complexity: O(body). Pure.
pub fn out_html(status: Int, body: Str) -> HandlerOut {
  return HandlerOut{ status: status; content_type: "text/html; charset=utf-8"; headers: Vec[(Str, Str)].new(); body: body; body_bytes: Vec[UInt8].new(); };
}

/// register adds one (method, pattern) route in registration order and
/// returns its 1-based route id (the index route_match reports). The pattern
/// grammar is the frozen one: literal segments compared byte-for-byte and
/// `:name` segments capturing exactly one non-empty path segment (see
/// xiom.pulse.router). Complexity: O(1).
pub fn register(method: Str, pattern: Str) -> Int {
  route_table.push((method, pattern));
  return route_table.len();
}

/// routes_list returns the registered (method, pattern) routes in
/// registration order (a copy; the live table is not exposed).
/// Complexity: O(routes).
pub fn routes_list() -> Vec[(Str, Str)] {
  var out: Vec[(Str, Str)] = Vec[(Str, Str)].new();
  var i: Int = 0;
  while i < route_table.len() {
    out.push(route_table[i]);
    i = i + 1;
  }
  return out;
}

/// dispatch_one routes one registered request: the `/v1` alias prefix is
/// stripped first (router.v1_path), then the table is matched and the
/// matched route is handed to `handler`. Complexity: O(request).
fn dispatch_one(eff_method: Str, req: &PulseRequest, body_str: Str, handler: fn(&PulseRequest, &PulseRoute, Str) -> HandlerOut) -> HandlerOut {
  let tgt = router.v1_path(req.target);
  let m = router.route_match(eff_method, tgt, &route_table);
  return handle_route(m, &req, body_str, handler);
}

/// handle_route applies the frozen pre-dispatch policy and dispatches a
/// matched route to `handler`:
///   * `chunked` + Content-Length -> 400: ambiguous framing is the classic
///     CL.TE smuggling shape and is refused outright;
///   * any other non-chunked Transfer-Encoding -> 501 (unsupported
///     transfer-coding, RFC 9110);
///   * kind 0 -> the JSON 404 envelope; kind 2 -> 405 with the Allow list;
///   * otherwise the registered handler receives the request (the body is
///     already decoded by the parser).
/// Complexity: O(body).
pub fn handle_route(m: PulseRoute, req: &PulseRequest, body: Str, handler: fn(&PulseRequest, &PulseRoute, Str) -> HandlerOut) -> HandlerOut {
  // Transfer-Encoding policy (chunked support since 2026-10-08):
  //   * `chunked` alone -> decoded body reaches the route;
  //   * `chunked` + Content-Length -> 400: ambiguous framing is the classic
  //     CL.TE smuggling shape and is refused outright;
  //   * any other coding -> 501 (unsupported transfer-coding, RFC 9110).
  let te_hdr = http.header_get(req, "transfer-encoding");
  if te_hdr.len() > 0 {
    if !http.te_is_chunked(te_hdr) {
      return out_json(501, envelope.error_body("unsupported_transfer_encoding", "Transfer-Encoding is not supported"));
    }
    if http.header_get(req, "content-length").len() > 0 {
      return out_json(400, envelope.error_body("bad_request", "Transfer-Encoding with Content-Length is ambiguous"));
    }
  }
  if m.kind == 0 {
    return out_json(404, envelope.error_body("not_found", "not found"));
  }
  if m.kind == 2 {
        var hs: Vec[(Str, Str)] = Vec[(Str, Str)].new();
        hs.push(("Allow", m.allow));
        return HandlerOut{ status: 405; content_type: CONTENT_JSON; headers: hs; body: error_status_body(405, envelope.error_body("method_not_allowed", "method not allowed")); body_bytes: Vec[UInt8].new(); };
  }
  return handler(req, &m, body);
}

/// recv_bounded receives up to 65536 bytes under the remaining request
/// budget: the per-call deadline shrinks as the request is read
/// (PULSE_READ_TIMEOUT semantics, fasthttp model). budget_ms <= 0 means
/// no deadline. Complexity: O(1) syscalls.
fn recv_bounded(client: Int, budget_ms: Int, t0: Int) -> Result[Vec[UInt8], Str] {
  if budget_ms <= 0 { return socket.socket_recv(client, 65536); }
  let remaining = budget_ms - (time.monotonic_ms() - t0);
  if remaining <= 0 { return Err("read deadline exceeded"); }
  return socket.socket_recv_timeout(client, 65536, remaining);
}

/// request_complete mirrors the read_request framing checks: true when
/// `raw` already holds a fully framed request (head + body, or the capped
/// oversize/overflow condition the read loop treats as done). Used to
/// serve a fully-buffered pipelined request without another recv.
/// Complexity: O(n). Pure.
fn request_complete(raw: &Vec[UInt8]) -> Bool {
  let he = find_header_end(raw);
  if he < 0 { return header_overflow(raw); }
  let te = http.transfer_encoding_of(raw, he);
  if te.len() > 0 {
    if !http.te_is_chunked(te) { return true; }
    let tcap: Int = he + 4 + MAX_BODY + 16384;
    return http.chunked_state(raw, he) != 0 || raw.len() >= tcap;
  }
  var want: Int = he + 4 + content_length_of(raw, he);
  let cap: Int = he + 4 + MAX_BODY;
  if want > cap { want = cap; }
  return raw.len() >= want;
}

/// read_request buffers one request per connection until headers and the
/// Content-Length body are complete. `initial` seeds the buffer with
/// trailing bytes from a pipelined keep-alive cycle; `first_ms` bounds
/// the wait for the FIRST byte (the idle deadline on cycle > 0), after
/// which `budget_ms` bounds the rest of the request. Returns
/// (raw, err, idle): err = 1 deadline/socket error (408 path), err = 2
/// clean EOF mid-message (close with no response, h11 rule 6), idle = 1
/// the idle deadline expired before any byte (silent close, fasthttp
/// model). Complexity: O(n) syscalls.
fn read_request(client: Int, budget_ms: Int, initial: &Vec[UInt8], first_ms: Int, cycling: Bool) -> (Vec[UInt8], Int, Int) {
  var raw: Vec[UInt8] = Vec[UInt8].new();
  var i0: Int = 0;
  while i0 < initial.len() {
    raw.push(initial[i0]);
    i0 = i0 + 1;
  }
  // A fully buffered pipelined request is served without another recv
  // (its bytes may arrive with the previous cycle's last read).
  if request_complete(&raw) {
    return (raw, 0, 0);
  }
  var done: Bool = false;
  var err: Int = 0;
  var idle: Int = 0;
  var rounds: Int = 0;
  var sent100: Bool = false;
  var started: Bool = raw.len() > 0;
  var t0 = time.monotonic_ms();
  while !done && rounds < 1024 {
    var bud: Int = budget_ms;
    if !started { bud = first_ms; }
    let rr = recv_bounded(client, bud, t0);
    if rr.is_err {
      if !started && cycling {
        idle = 1;
      } else {
        err = 1;
      }
      done = true;
    } else {
      let chunk = rr.value;
      if chunk.len() == 0 {
        // EOF: a clean close only BETWEEN requests; mid-message it is a
        // protocol error with no answer (h11 rule 6).
        if raw.len() > 0 { err = 2; }
        done = true;
      } else {
        if !started {
          started = true;
          t0 = time.monotonic_ms();
        }
        var i: Int = 0;
        while i < chunk.len() {
          raw.push(chunk[i]);
          i = i + 1;
        }
        let he = find_header_end(&raw);
        if he >= 0 {
          // Expect: 100-continue -- answer the interim before waiting for
          // the body (curl waits 1s and stalls large POSTs otherwise).
          if !sent100 {
            let preq = http.parse_request(&raw);
            if http.expects_continue(&preq) {
              let interim: Vec[UInt8] = http.str_to_bytes("HTTP/1.1 100 Continue\r\n\r\n");
              let _w = send_all(client, &interim);
              sent100 = true;
            }
          }
          let te = http.transfer_encoding_of(&raw, he);
          if te.len() > 0 {
            if http.te_is_chunked(te) {
              // Wait for the terminating zero chunk (or malformed framing);
              // the raw cap leaves a 16 KiB budget for chunk metadata.
              let tcap: Int = he + 4 + MAX_BODY + 16384;
              let st = http.chunked_state(&raw, he);
              if st != 0 || raw.len() >= tcap { done = true; }
            } else {
              // Unsupported coding: the body (if any) is not ours to read;
              // the route layer answers 501 after this head.
              done = true;
            }
          } else {
            var want: Int = he + 4 + content_length_of(&raw, he);
            let cap: Int = he + 4 + MAX_BODY;
            if want > cap { want = cap; }
            if raw.len() >= want { done = true; }
          }
        } else if header_overflow(&raw) {
          done = true;
        }
      }
    }
    rounds = rounds + 1;
  }
  return (raw, err, idle);
}

/// send_step queues one 64 KiB slice; -1 on failure. Complexity: O(chunk).
fn send_step(fd: Int, data: &Vec[UInt8], off: Int, n: Int) -> Int {
  var take: Int = n - off;
  if take > 65536 { take = 65536; }
  var chunk: Vec[UInt8] = Vec[UInt8].with_capacity(take as UInt);
  var ci: Int = 0;
  while ci < take {
    chunk.push(data[off + ci]);
    ci = ci + 1;
  }
  let wr = socket.socket_send(fd, &chunk);
  if wr.is_err { return -1; }
  return wr.value;
}

/// send_all writes the whole buffer with the write deadline enforced
/// (PULSE_WRITE_TIMEOUT): the fd goes non-blocking, every slice is gated
/// on a writability poll, and the deadline caps the total wait -- a
/// stalled reader drops the connection (fasthttp model; a half-written
/// response is never retried). Non-blocking is what makes the gate real:
/// a blocking send() can freeze on partial buffer space past the poll
/// (found by the Linux sweep while streaming a large file). Returns
/// false on error or deadline expiry. Complexity: O(n) syscalls.
fn send_all(fd: Int, data: &Vec[UInt8]) -> Bool {
  let n = data.len();
  if n == 0 { return true; }
  let budget = config.cfg_write_timeout();
  let t0 = time.monotonic_ms();
  let nb = socket.socket_set_nonblocking(fd, true);
  let _ = nb;
  var off: Int = 0;
  var ok: Bool = true;
  while off < n && ok {
    if budget > 0 {
      let remaining = budget - (time.monotonic_ms() - t0);
      if remaining <= 0 {
        ok = false;
      } else {
        var fds: Vec[Int] = Vec[Int].new();
        fds.push(fd);
        let pr = socket.socket_poll_write(&fds, remaining);
        if pr.is_err { ok = false; } else if pr.value.len() == 0 { ok = false; }
      }
    }
    if ok {
      let sent = send_step(fd, data, off, n);
      if sent <= 0 { ok = false; } else { off = off + sent; }
    }
  }
  let rb = socket.socket_set_nonblocking(fd, false);
  let _ = rb;
  return ok;
}

/// handle_connection serves one accepted connection through its keep-alive
/// cycles (the frozen Phase A+B loop, minus the dropped product hooks):
///   * per-connection trailing buffer carried across cycles (h11 rule 4);
///   * one-way reuse latch: `Connection: close` token, HTTP/1.0 peers and
///     incomplete/oversize framing all close after the response;
///   * in-order pipelining: a fully buffered request is served without
///     another recv;
///   * silent idle expiry (PULSE_IDLE_TIMEOUT) on cycle > 0; 408 with
///     close on a deadline before the request completes on cycle 0;
///   * EOF mid-message closes with no answer (h11 rule 6);
///   * `PULSE_KEEPALIVE=0` restores close-per-request.
/// Exported so consumers and tests can drive one connection without owning
/// the accept loop (serve() is the loop). Sets quit_requested on
/// `X-Pulse-Quit: 1`. Complexity: O(request) per cycle.
pub fn handle_connection(client: Int, handler: fn(&PulseRequest, &PulseRoute, Str) -> HandlerOut) {
  var conn_open: Bool = true;
  var keep: Bool = config.cfg_keepalive();
  var buf: Vec[UInt8] = Vec[UInt8].new();
  var cycle: Int = 0;
  while conn_open && !quit_requested {
    var first_ms: Int = config.cfg_read_timeout();
    if cycle > 0 { first_ms = config.cfg_idle_timeout(); }
    let rreq = read_request(client, config.cfg_read_timeout(), &buf, first_ms, cycle > 0);
    let raw = rreq.0;
    let read_err = rreq.1;
    let idle_out = rreq.2;
    var reuse: Bool = false;

    if idle_out == 1 {
      // Idle keep-alive expiry: silent close, no 408 (fasthttp model).
      conn_open = false;
    } else if raw.len() == 0 && read_err == 0 {
      conn_open = false;
    } else if read_err == 2 {
      // EOF mid-message: close with no response (h11 rule 6).
      conn_open = false;
    } else if read_err == 1 {
      // Deadline (or socket error) before the request completed: answer
      // 408 best-effort (the send fails harmlessly on a dead socket) and
      // close -- one slow client cannot stall the loop (slowloris guard,
      // fasthttp model).
      let rid = next_rid();
      reqctx.set_rid(rid);
      var no_headers: Vec[(Str, Str)] = Vec[(Str, Str)].new();
      let rbody = envelope.error_body("request_timeout", "request timed out");
      let resp = http.build_response_full(408, CONTENT_JSON, &no_headers, rbody, false);
      let _w = send_all(client, &resp);
      conn_open = false;
    } else {
      let rid = next_rid();
      reqctx.set_rid(rid);
      let req = http.parse_request(&raw);
      // Reuse gate (h11 rules): complete framing consumed, no close
      // request from the peer, still open for reuse. The latch is
      // one-way: once a cycle closes, the connection never reuses.
      let fend = http.framed_end(&raw);
      keep = keep && fend >= 0 && !http.connection_close_requested(&req);
      reuse = keep;
      if !req.ok {
        var status: Int = 400;
        var code: Str = "bad_request";
        if string.str_contains(req.error, "too large") {
          status = 413;
          code = "payload_too_large";
        }
        var no_headers: Vec[(Str, Str)] = Vec[(Str, Str)].new();
        let resp = http.build_response_full(status, CONTENT_JSON, &no_headers, envelope.error_body(code, "bad request"), false);
        let w_ok = send_all(client, &resp);
        if !w_ok { io.println("pulse: send failed (" + status.to_str() + ")"); io.flush_stdout(); }
        conn_open = false;
      } else if http.header_get(&req, "x-pulse-quit") == "1" {
        quit_requested = true;
        conn_open = false;
      } else {
        let body_str = http.bytes_to_str(&req.body, 0, req.body.len());
        var eff_method: Str = req.method;
        if req.method == "HEAD" { eff_method = "GET"; }
        let out = dispatch_one(eff_method, &req, body_str, handler);
        var resp: Vec[UInt8] = Vec[UInt8].new();
        if out.body_bytes.len() > 0 {
          resp = http.build_response_bytes(out.status, out.content_type, &out.headers, &out.body_bytes, reuse);
        } else {
          resp = http.build_response_full(out.status, out.content_type, &out.headers, out.body, reuse);
        }
        if req.method == "HEAD" {
          let he = find_header_end(&resp);
          if he >= 0 {
            var trimmed: Vec[UInt8] = Vec[UInt8].new();
            var ti: Int = 0;
            while ti < he + 4 {
              trimmed.push(resp[ti]);
              ti = ti + 1;
            }
            resp = trimmed;
          }
        }
        let w_ok = send_all(client, &resp);
        if !w_ok {
          io.println("pulse: send failed");
          io.flush_stdout();
        }
        conn_open = reuse;
        served = served + 1;
      }
      if conn_open && reuse {
        // Carry pipelined trailing bytes into the next cycle (h11 rule
        // 4: never lose unparsed bytes).
        buf = Vec[UInt8].new();
        var ti: Int = fend;
        while ti < raw.len() {
          buf.push(raw[ti]);
          ti = ti + 1;
        }
      }
    }
    cycle = cycle + 1;
  }
}

/// serve runs the frozen accept loop: bind PULSE_BIND:PULSE_PORT, accept
/// one connection at a time and hand it to handle_connection with `handler`.
/// Returns 0 on the clean shutdown path (X-Pulse-Quit) and 1 when the
/// socket/bind/listen/accept fails. Complexity: O(runtime).
pub fn serve(handler: fn(&PulseRequest, &PulseRoute, Str) -> HandlerOut) -> Int {
  let sr = socket.socket_tcp();
  if sr.is_err {
    io.println("pulse: socket create failed");
    io.flush_stdout();
    return 1;
  }
  let fd = sr.value;
  let port = config.cfg_port();
  let bind_addr = config.cfg_bind();

  let br = socket.socket_bind(fd, bind_addr, port);
  if br.is_err {
    io.println("pulse: bind " + bind_addr + ":" + port.to_str() + " failed");
    io.flush_stdout();
    return 1;
  }
  let lr = socket.socket_listen(fd, 128);
  if lr.is_err {
    io.println("pulse: listen failed");
    io.flush_stdout();
    return 1;
  }
  io.println("pulse: listening on " + bind_addr + ":" + port.to_str());
  io.flush_stdout();

  io.println("pulse: deadlines read=" + config.cfg_read_timeout().to_str() + "ms write=" + config.cfg_write_timeout().to_str() + "ms idle=" + config.cfg_idle_timeout().to_str() + "ms");
  io.flush_stdout();
  var ka_note: Str = "on";
  if !config.cfg_keepalive() { ka_note = "off"; }
  io.println("pulse: keep-alive " + ka_note + " (PULSE_KEEPALIVE=0 disables reuse)");
  io.flush_stdout();

  while !quit_requested {
    let ar = socket.socket_accept(fd);
    if ar.is_err {
      io.println("pulse: accept failed");
      io.flush_stdout();
      return 1;
    }
    let client = ar.value;
    handle_connection(client, handler);
    socket.socket_close(client);
  }

  socket.socket_close(fd);
  io.println("pulse: shutdown served=" + served.to_str());
  io.flush_stdout();
  return 0;
}
