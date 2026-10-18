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

/// app_set_server_token sets the process-wide `Server` header token that
/// both response builders emit (RFC 9110 `Server: <token>`). The default is
/// the neutral, version-free "xiom-pulse"; a product such as Station sets
/// "xiom-pulse-station/<own version>" once before serve(). Invalid input
/// (empty or non printable ASCII) returns false and leaves the token as-is.
/// Complexity: O(token).
pub fn app_set_server_token(token: Str) -> Bool {
  return http.set_server_token(token);
}

/// app_server_token returns the current `Server` header token.
/// Complexity: O(1).
pub fn app_server_token() -> Str {
  return http.server_token();
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

/// ResponseInfo is the observation a post-request hook receives: the final
/// status, the response body byte count (body_bytes when set, else body) and
/// the dispatch duration in milliseconds (pre hook + routing + handler, the
/// send excluded). The per-request id is available via reqctx.get_rid().
pub type ResponseInfo = {
  status: Int;
  bytes: Int;
  duration_ms: Int;
}

/// PreOut is the pre-request hook decision: short_circuit=true sends
/// `response` and skips routing and the registered handler; otherwise the
/// request continues through the normal dispatch. Build it with
/// pre_continue()/pre_stop().
pub type PreOut = {
  short_circuit: Bool;
  response: HandlerOut;
}

/// HookCtx is the per-install state bag handed to the stateful hook
/// variants: an opaque Vec[Int] of consumer-managed handles (for example a
/// rate-limiter bucket counter). The core never interprets the slots; it
/// only carries the same value through the pre hook, routing/handler and the
/// after hook (and across keep-alive cycles when the caller owns it through
/// serve_with_ctx / handle_connection_with_ctx).
pub type HookCtx = {
  state: Vec[Int];
}

/// hookctx_new returns an empty handle bag. Complexity: O(1).
pub fn hookctx_new() -> HookCtx {
  return HookCtx{ state: Vec[Int].new() };
}

/// hookctx_len reports the number of handles in the bag.
/// Complexity: O(1).
pub fn hookctx_len(ctx: &HookCtx) -> Int {
  return ctx.state.len();
}

/// hookctx_get reads handle `i`; out-of-range indices read as 0 (the bag is
/// a plain slot vector and never traps). Complexity: O(1).
pub fn hookctx_get(ctx: &HookCtx, i: Int) -> Int {
  if i < 0 || i >= ctx.state.len() { return 0; }
  return ctx.state[i];
}

/// hookctx_set writes handle `i`; false when `i` is out of range.
/// Complexity: O(1).
pub fn hookctx_set(ctx: &mut HookCtx, i: Int, v: Int) -> Bool {
  if i < 0 || i >= ctx.state.len() { return false; }
  ctx.state[i] = v;
  return true;
}

/// hookctx_push appends one handle and returns its index.
/// Complexity: O(1) amortized.
pub fn hookctx_push(ctx: &mut HookCtx, v: Int) -> Int {
  ctx.state.push(v);
  return ctx.state.len() - 1;
}

/// hookctx_clear drops every handle; returns whether the bag was non-empty.
/// Clearing is idempotent. Complexity: O(1).
pub fn hookctx_clear(ctx: &mut HookCtx) -> Bool {
  let had = ctx.state.len() > 0;
  ctx.state = Vec[Int].new();
  return had;
}

/// HookSet is the opt-in hook seam. A fresh set (hooks_new) has no hooks and
/// leaves dispatch byte-identical to the hook-free core.
///
/// The stateless pre hook is `fn(&PulseRequest, Str) -> PreOut`: it runs after
/// the request parses and before route matching; the second argument is the
/// decoded body. The stateless after hook is
/// `fn(&PulseRequest, Str, &HandlerOut, &ResponseInfo)`: it runs once per
/// dispatched response, including pre-hook short-circuits and the frozen
/// policy responses (400/404/405/501).
///
/// The stateful variants add a `&mut HookCtx` tail argument:
/// `fn(&PulseRequest, Str, &mut HookCtx) -> PreOut` and
/// `fn(&PulseRequest, Str, &HandlerOut, &ResponseInfo, &mut HookCtx)`. They
/// are dispatched by dispatch_with_ctx / handle_connection_with_ctx /
/// serve_with_ctx; the stateless variants run in the same order when both are
/// installed (stateless first, then stateful). The stateless variants never
/// see the bag.
///
/// All slots are written as direct fn types: an fn-typed alias used as a
/// callable parameter miscompiles at 0.64.6. Hooks live in one-element
/// vectors because adjacent fn-typed struct fields are laid out incorrectly
/// (both defects are minimized in docs/COMPILER-NOTES.md); do not simplify
/// the slots.
pub type HookSet = {
  pre: Vec[fn(&PulseRequest, Str) -> PreOut];
  after: Vec[fn(&PulseRequest, Str, &HandlerOut, &ResponseInfo)];
  pre_ctx: Vec[fn(&PulseRequest, Str, &mut HookCtx) -> PreOut];
  after_ctx: Vec[fn(&PulseRequest, Str, &HandlerOut, &ResponseInfo, &mut HookCtx)];
}

/// HookError is the typed misuse error for hook registration. Clearing is
/// idempotent and never fails.
pub enum HookError {
  PreAlreadyInstalled,
  AfterAlreadyInstalled,
  PreCtxAlreadyInstalled,
  AfterCtxAlreadyInstalled,
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

// ---------------------------------------------------------------------------
// Hook seam: pre_route + after_response (opt-in; empty set == frozen core).
// ---------------------------------------------------------------------------

/// hooks_new returns an empty hook set: dispatch through it behaves exactly
/// like the hook-free core. Complexity: O(1).
pub fn hooks_new() -> HookSet {
  return HookSet{ pre: Vec[fn(&PulseRequest, Str) -> PreOut].new(); after: Vec[fn(&PulseRequest, Str, &HandlerOut, &ResponseInfo)].new(); pre_ctx: Vec[fn(&PulseRequest, Str, &mut HookCtx) -> PreOut].new(); after_ctx: Vec[fn(&PulseRequest, Str, &HandlerOut, &ResponseInfo, &mut HookCtx)].new() };
}

/// pre_continue is the "dispatch normally" pre-hook decision.
/// Complexity: O(1).
pub fn pre_continue() -> PreOut {
  return PreOut{ short_circuit: false; response: HandlerOut{ status: 200; content_type: CONTENT_TEXT; headers: Vec[(Str, Str)].new(); body: ""; body_bytes: Vec[UInt8].new() } };
}

/// pre_stop is the short-circuit pre-hook decision: `response` is sent and
/// route matching + the registered handler are skipped (the after hook still
/// observes it). Complexity: O(1).
pub fn pre_stop(response: HandlerOut) -> PreOut {
  return PreOut{ short_circuit: true; response: response };
}

/// hooks_install_pre registers the one pre hook. A second install is misuse:
/// Err(PreAlreadyInstalled). Complexity: O(1).
pub fn hooks_install_pre(hs: &mut HookSet, h: fn(&PulseRequest, Str) -> PreOut) -> Result[Bool, HookError] {
  if hs.pre.len() > 0 { return Err(PreAlreadyInstalled); }
  hs.pre.push(h);
  return Ok(true);
}

/// hooks_install_after registers the one after hook. A second install is
/// misuse: Err(AfterAlreadyInstalled). Complexity: O(1).
pub fn hooks_install_after(hs: &mut HookSet, h: fn(&PulseRequest, Str, &HandlerOut, &ResponseInfo)) -> Result[Bool, HookError] {
  if hs.after.len() > 0 { return Err(AfterAlreadyInstalled); }
  hs.after.push(h);
  return Ok(true);
}

/// hooks_install_pre_ctx registers the one stateful pre hook. A second
/// install is misuse: Err(PreCtxAlreadyInstalled). A stateless pre hook may
/// coexist with it (stateless runs first). Complexity: O(1).
pub fn hooks_install_pre_ctx(hs: &mut HookSet, h: fn(&PulseRequest, Str, &mut HookCtx) -> PreOut) -> Result[Bool, HookError] {
  if hs.pre_ctx.len() > 0 { return Err(PreCtxAlreadyInstalled); }
  hs.pre_ctx.push(h);
  return Ok(true);
}

/// hooks_install_after_ctx registers the one stateful after hook. A second
/// install is misuse: Err(AfterCtxAlreadyInstalled). A stateless after hook
/// may coexist with it (stateless runs first). Complexity: O(1).
pub fn hooks_install_after_ctx(hs: &mut HookSet, h: fn(&PulseRequest, Str, &HandlerOut, &ResponseInfo, &mut HookCtx)) -> Result[Bool, HookError] {
  if hs.after_ctx.len() > 0 { return Err(AfterCtxAlreadyInstalled); }
  hs.after_ctx.push(h);
  return Ok(true);
}

/// hooks_clear_pre removes both the stateless and the stateful pre hook;
/// returns true when either was installed. Clearing is idempotent.
/// Complexity: O(1).
pub fn hooks_clear_pre(hs: &mut HookSet) -> Bool {
  let had = hs.pre.len() > 0 || hs.pre_ctx.len() > 0;
  hs.pre = Vec[fn(&PulseRequest, Str) -> PreOut].new();
  hs.pre_ctx = Vec[fn(&PulseRequest, Str, &mut HookCtx) -> PreOut].new();
  return had;
}

/// hooks_clear_after removes both the stateless and the stateful after hook;
/// returns true when either was installed. Clearing is idempotent.
/// Complexity: O(1).
pub fn hooks_clear_after(hs: &mut HookSet) -> Bool {
  let had = hs.after.len() > 0 || hs.after_ctx.len() > 0;
  hs.after = Vec[fn(&PulseRequest, Str, &HandlerOut, &ResponseInfo)].new();
  hs.after_ctx = Vec[fn(&PulseRequest, Str, &HandlerOut, &ResponseInfo, &mut HookCtx)].new();
  return had;
}

/// hooks_clear removes both hooks (stateless and stateful); returns true when
/// anything was installed. Complexity: O(1).
pub fn hooks_clear(hs: &mut HookSet) -> Bool {
  let had_pre = hooks_clear_pre(hs);
  let had_after = hooks_clear_after(hs);
  return had_pre || had_after;
}

/// hooks_has_pre / hooks_has_after report registration state (either the
/// stateless or the stateful variant). Complexity: O(1).
pub fn hooks_has_pre(hs: &HookSet) -> Bool {
  return hs.pre.len() > 0 || hs.pre_ctx.len() > 0;
}

pub fn hooks_has_after(hs: &HookSet) -> Bool {
  return hs.after.len() > 0 || hs.after_ctx.len() > 0;
}

/// hook_error_code is the stable misuse code for logs and tests:
/// "pre_already_installed" / "after_already_installed" /
/// "pre_ctx_already_installed" / "after_ctx_already_installed".
/// Complexity: O(1).
pub fn hook_error_code(e: &HookError) -> Str {
  match e {
    PreAlreadyInstalled => { return "pre_already_installed"; }
    AfterAlreadyInstalled => { return "after_already_installed"; }
    PreCtxAlreadyInstalled => { return "pre_ctx_already_installed"; }
    AfterCtxAlreadyInstalled => { return "after_ctx_already_installed"; }
  }
}

/// response_body_bytes is the byte count of the response body (raw bytes
/// when set, else the text body). Complexity: O(1).
fn response_body_bytes(out: &HandlerOut) -> Int {
  if out.body_bytes.len() > 0 { return out.body_bytes.len(); }
  return out.body.len();
}

/// dispatch_with is the hook-aware dispatch seam: pre hook -> route match +
/// frozen policy + handler -> after hook. With an empty HookSet it returns
/// exactly what the hook-free dispatch returns. The after hook runs once per
/// response, including short-circuits and 400/404/405/501 outcomes.
/// Complexity: O(request) + hook bodies.
pub fn dispatch_with(hooks: &HookSet, eff_method: Str, req: &PulseRequest, body: Str, handler: fn(&PulseRequest, &PulseRoute, Str) -> HandlerOut) -> HandlerOut {
  let t0 = time.monotonic_ms();
  var out: HandlerOut = HandlerOut{ status: 200; content_type: CONTENT_TEXT; headers: Vec[(Str, Str)].new(); body: ""; body_bytes: Vec[UInt8].new() };
  var short_circuited: Bool = false;
  if hooks.pre.len() > 0 {
    let ph = hooks.pre[0];
    let pd = ph(req, body);
    if pd.short_circuit {
      out = pd.response;
      short_circuited = true;
    }
  }
  if !short_circuited {
    out = dispatch_one(eff_method, req, body, handler);
  }
  if hooks.after.len() > 0 {
    let info = ResponseInfo{ status: out.status; bytes: response_body_bytes(&out); duration_ms: time.monotonic_ms() - t0 };
    let ah = hooks.after[0];
    ah(req, body, &out, &info);
  }
  return out;
}

/// dispatch_with_ctx is the stateful variant of dispatch_with: the stateless
/// pre hook (when installed) runs first, then the stateful pre hook with
/// `ctx`; the first short-circuit wins. Routing/policy/handler follow, then
/// the stateless after hook and the stateful after hook, each exactly once
/// (including short-circuits and 400/404/405/501). Mutations a pre hook makes
/// to the bag are visible to the after hooks. With no hooks installed it
/// returns exactly what the hook-free dispatch returns.
/// Complexity: O(request) + hook bodies.
pub fn dispatch_with_ctx(hooks: &HookSet, ctx: &mut HookCtx, eff_method: Str, req: &PulseRequest, body: Str, handler: fn(&PulseRequest, &PulseRoute, Str) -> HandlerOut) -> HandlerOut {
  let t0 = time.monotonic_ms();
  var out: HandlerOut = HandlerOut{ status: 200; content_type: CONTENT_TEXT; headers: Vec[(Str, Str)].new(); body: ""; body_bytes: Vec[UInt8].new() };
  var short_circuited: Bool = false;
  if hooks.pre.len() > 0 {
    let ph = hooks.pre[0];
    let pd = ph(req, body);
    if pd.short_circuit {
      out = pd.response;
      short_circuited = true;
    }
  }
  if !short_circuited && hooks.pre_ctx.len() > 0 {
    let phc = hooks.pre_ctx[0];
    let pdc = phc(req, body, ctx);
    if pdc.short_circuit {
      out = pdc.response;
      short_circuited = true;
    }
  }
  if !short_circuited {
    out = dispatch_one(eff_method, req, body, handler);
  }
  if hooks.after.len() > 0 {
    let info = ResponseInfo{ status: out.status; bytes: response_body_bytes(&out); duration_ms: time.monotonic_ms() - t0 };
    let ah = hooks.after[0];
    ah(req, body, &out, &info);
  }
  if hooks.after_ctx.len() > 0 {
    let infoc = ResponseInfo{ status: out.status; bytes: response_body_bytes(&out); duration_ms: time.monotonic_ms() - t0 };
    let ahc = hooks.after_ctx[0];
    ahc(req, body, &out, &infoc, ctx);
  }
  return out;
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
/// cycles (the frozen Phase A+B loop) with no hooks -- identical to the
/// hook-free core. handle_connection_with is the seam variant.
/// Complexity: O(request) per cycle.
pub fn handle_connection(client: Int, handler: fn(&PulseRequest, &PulseRoute, Str) -> HandlerOut) {
  let hooks = hooks_new();
  handle_connection_with(client, handler, &hooks);
}

/// handle_connection_with serves one accepted connection through the
/// stateless hook path (it supplies a fresh empty HookCtx for the whole
/// connection, so any stateful hooks installed in `hooks` run against a
/// per-connection bag). Use handle_connection_with_ctx to own the bag.
/// Complexity: O(request) per cycle.
pub fn handle_connection_with(client: Int, handler: fn(&PulseRequest, &PulseRoute, Str) -> HandlerOut, hooks: &HookSet) {
  var ctx = hookctx_new();
  handle_connection_with_ctx(client, handler, hooks, &mut ctx);
}

/// handle_connection_with_ctx serves one accepted connection through its
/// keep-alive cycles (the frozen Phase A+B loop, minus the dropped product
/// hooks) and dispatches through `hooks` + `ctx`:
///   * per-connection trailing buffer carried across cycles (h11 rule 4);
///   * one-way reuse latch: `Connection: close` token, HTTP/1.0 peers and
///     incomplete/oversize framing all close after the response;
///   * in-order pipelining: a fully buffered request is served without
///     another recv;
///   * silent idle expiry (PULSE_IDLE_TIMEOUT) on cycle > 0; 408 with
///     close on a deadline before the request completes on cycle 0;
///   * EOF mid-message closes with no answer (h11 rule 6);
///   * `PULSE_KEEPALIVE=0` restores close-per-request.
/// The same `ctx` is passed to every pre/after hook for every cycle on the
/// connection (stateful hooks see their own mutations across keep-alive
/// cycles; passing an empty HookSet is byte-identical to the hook-free core).
/// Exported so consumers and tests can drive one connection without owning
/// the accept loop (serve_with_ctx() is the loop). Sets quit_requested on
/// `X-Pulse-Quit: 1`. Complexity: O(request) per cycle.
pub fn handle_connection_with_ctx(client: Int, handler: fn(&PulseRequest, &PulseRoute, Str) -> HandlerOut, hooks: &HookSet, ctx: &mut HookCtx) {
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
        let out = dispatch_with_ctx(hooks, ctx, eff_method, &req, body_str, handler);
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

/// serve runs the frozen accept loop with no hooks -- identical to the
/// hook-free core. Complexity: O(runtime).
pub fn serve(handler: fn(&PulseRequest, &PulseRoute, Str) -> HandlerOut) -> Int {
  let hooks = hooks_new();
  return serve_with(handler, &hooks);
}

/// serve_with runs the stateless accept loop: it supplies one fresh
/// HookCtx for the whole run (stateful hooks installed in `hooks` share it
/// across all connections). Use serve_with_ctx to own the bag.
/// Complexity: O(runtime).
pub fn serve_with(handler: fn(&PulseRequest, &PulseRoute, Str) -> HandlerOut, hooks: &HookSet) -> Int {
  var ctx = hookctx_new();
  return serve_with_ctx(handler, hooks, &mut ctx);
}

/// serve_with_ctx runs the frozen accept loop: bind PULSE_BIND:PULSE_PORT,
/// accept one connection at a time and hand it to
/// handle_connection_with_ctx with `handler`, `hooks` and the caller-owned
/// `ctx`. The same bag is carried across every connection for the process
/// lifetime (a rate-limiter bucket therefore survives keep-alive cycles and
/// reconnects). Returns 0 on the clean shutdown path (X-Pulse-Quit) and 1
/// when the socket/bind/listen/accept fails. Complexity: O(runtime).
pub fn serve_with_ctx(handler: fn(&PulseRequest, &PulseRoute, Str) -> HandlerOut, hooks: &HookSet, ctx: &mut HookCtx) -> Int {
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
    handle_connection_with_ctx(client, handler, hooks, ctx);
    socket.socket_close(client);
  }

  socket.socket_close(fd);
  io.println("pulse: shutdown served=" + served.to_str());
  io.flush_stdout();
  return 0;
}
