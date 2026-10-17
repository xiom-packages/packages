# xiom.pulse -- Specification

Version: 0.1.0 (incubating).
Pure XIOM, no FFI, no bridge C. `xiom.pulse` is the **Beacon extraction of
the frozen PULSE protocol core**: the HTTP/1.1 request parser + response
builders, the keep-alive A/B connection loop with named deadlines, the route
matching mechanism and the uniform JSON error envelope, carved from the
PULSE repo at commit `56eb9f8` (pair `7924222`; see `PROVENANCE.md`).

Tier identity: **Beacon** is this embeddable registry package; **Station**
is the standalone PULSE product -- both consume this same package (one
core, never a fork).

Dependencies: `xiom.std >=0.60.0 <1.0.0` only (the library modules use
`xiom.string`, `xiom.string.slice`, `xiom.string.compare`,
`xiom.convert.parse`, `xiom.net.socket`, `xiom.net.server`,
`xiom.serialize.json`, `xiom.env` and `xiom.time`; the tests additionally use
`xiom.io`). The PULSE family packages (session / static / kv / rate /
metrics / middleware / sqlite) stay **out** of this bundle: consumers
compose them separately.

Frozen identity strings are kept from the source: `pulse_version()` returns
`"0.2.1"` and the response `Server` header is `xiom-pulse/0.2.1`; the
**package** version is `0.1.0`.

## 1. Module map

| Module | File | Contents |
|---|---|---|
| `xiom.pulse` | `src/pulse.xi` | `pulse_version()` (verbatim) |
| `xiom.pulse.http` | `src/http.xi` | request parser, framing, chunked decoding, response builders (verbatim) |
| `xiom.pulse.router` | `src/router.xi` | `PulseRoute`, query splitting/decoding, `route_match` over a caller-supplied table + inlined router shim |
| `xiom.pulse.envelope` | `src/envelope.xi` | JSON error envelope helpers (verbatim) |
| `xiom.pulse.reqctx` | `src/reqctx.xi` | per-request id plumbing (verbatim) |
| `xiom.pulse.config` | `src/config.xi` | the six loop knobs actually read by the core (slimmed) |
| `xiom.pulse.app` | `src/server.xi` | `HandlerOut`, hook seam (`HookSet`, `ResponseInfo`, `PreOut`), registration seam, dispatch policy, `read_request`/`send_all`, the connection loop, the accept loop |
| `xiom.pulse.minimal` | `src/minimal.xi` | the minimal example: register a route + start the loop |

## 2. Frozen surface

### 2.1 `xiom.pulse.http`

Types:

| Type | Shape | Meaning |
|---|---|---|
| `PulseRequest` | `{ method: Str; target: Str; version: Str; header_names: Vec[Str]; header_values: Vec[Str]; body: Vec[UInt8]; ok: Bool; error: Str }` | parsed request head + buffered body |
| `RouteResult` | `{ status: Int; body: Str }` | status + JSON body for one dispatch |
| `ChunkedBody` | `{ body: Vec[UInt8]; ok: Bool; error: Str }` | decoded chunked body or failure reason |

Functions: `str_to_bytes`, `bytes_to_str`, `find_header_end`,
`header_limit_bytes`, `header_overflow`, `header_count_limit`,
`parse_request`, `header_get`, `connection_close_requested`,
`content_length_of`, `raw_header_value`, `transfer_encoding_of`,
`te_is_chunked`, `body_limit_bytes`, `chunked_state`, `framed_end`,
`decode_chunked`, `with_header_line`, `expects_continue`, `status_text`,
`security_head_lines`, `build_response_full`, `build_response_bytes`,
`build_response`, `bearer_token`, `idem_key_valid`.

Key semantics (frozen):

- `header_limit_bytes()` = 16384, `header_count_limit()` = 100,
  `body_limit_bytes()` = 1048576 (see section 4 caps).
- `parse_request` never traps: failures set `ok=false` + `error`
  (`"incomplete headers"`, `"malformed request line"`, `"too many
  headers"`, `"malformed request"`, `"incomplete/malformed chunked body"`,
  `"chunked body too large"`). Header names arrive lowercased; values are
  trimmed; an invalid Content-Length is rejected.
- `Transfer-Encoding: chunked` alone is decoded here (chunk extensions
  ignored, trailers validated + skipped, decoded-size cap). Any other
  coding keeps the body empty for the route layer's 501 guard.
- `connection_close_requested` is true for a `Connection` comma-token
  `close` (case-insensitive) or any version below HTTP/1.1 -- a 1.0 peer
  never reuses, even with `Connection: keep-alive` (h11 rule, deliberately
  adopted).
- `framed_end` returns the offset just past a complete request (head +
  body), or -1 when incomplete/oversize/unsupported-TE; the loop closes
  after responding on -1 (an unread body must never be reused as a
  request).
- `chunked_state` scans chunk framing: 1 = terminating zero chunk +
  trailers fully present, 0 = need more bytes, -1 = malformed.
- `status_text` covers the frozen phrase set (200/201/204/206/301/302/304/
  400/401/403/404/405/408/411/413/415/416/429/500/501/502/503/504;
  unknown -> `"Unknown"`).
- `build_response*` emit the reviewed security-header block
  (`security_head_lines`); `keep=false` emits `Connection: close`,
  `keep=true` emits nothing (HTTP/1.1 default; a 1.0 peer never sees
  keep-alive).

### 2.2 `xiom.pulse.router`

| Type | Shape | Meaning |
|---|---|---|
| `PulseRoute` | `{ kind: Int; route_id: Int; allow: Str; param_names: Vec[Str]; param_values: Vec[Str]; query_names: Vec[Str]; query_values: Vec[Str] }` | kind 0 = not found, 1 = matched, 2 = method not allowed (`allow` holds `"GET, POST"`) |

Functions: `split_target`, `v1_path`, `url_decode`, `parse_query`,
`route_match(method, target, defs)`.

- `route_match` matches against the caller's `(method, pattern)` list in
  registration order; `route_id` is the 1-based index into that list.
  `:name` segments capture exactly one non-empty path segment (raw text);
  the first registration-order route whose pattern shape and method match
  wins; a shape-only match yields kind 2 with the deduplicated Allow list;
  otherwise kind 0.
- `v1_path` maps `/v1/<rest>` onto `/<rest>` (query preserved), `/v1` and
  `/v1/` onto `/`, and passes anything else through.

### 2.3 `xiom.pulse.envelope` / `xiom.pulse.reqctx`

`error_body(code, message)` builds
`{"error":{"code":"...","message":"...","rid":"..."}}` (`rid` included when
set); `ok_bool(v)` -> `{"ok":true|false}`; `single_field(key, value)` ->
`{"<key>":"<value>"}`. `set_rid`/`get_rid` carry the per-request id used by
the envelope.

### 2.4 `xiom.pulse.config`

Exactly the loop knobs the carved core reads: `cfg_read_timeout()` (30000),
`cfg_write_timeout()` (30000), `cfg_idle_timeout()` (5000),
`cfg_keepalive()` (`PULSE_KEEPALIVE != "0"`), `cfg_port()` (8080),
`cfg_bind()` (`127.0.0.1`). `0` disables a deadline (dev only). Every
product knob and the `PULSE_CONFIG` file loader are dropped (section 6).

### 2.5 `xiom.pulse.app` -- the public seam

```xi
use xiom.pulse.app;
use xiom.pulse.http;
use xiom.pulse.router;

fn health(_req: &PulseRequest, _m: &PulseRoute, _body: Str) -> HandlerOut {
  return app.out_json(200, "{\"status\":\"ok\"}");
}

pub fn main() -> Int {
  let _ = app.register("GET", "/health");
  return app.serve(health);
}
```

| Fn | Behavior |
|---|---|
| `register(method, pattern) -> Int` | appends one route to the process-wide table, returns its 1-based route id |
| `routes_list() -> Vec[(Str, Str)]` | a copy of the registered routes in registration order |
| `out_json` / `out_text` / `out_html(status, body) -> HandlerOut` | façade builders (the frozen private `out_*` helpers made public) |
| `handle_route(m, req, body, handler) -> HandlerOut` | the frozen pre-dispatch policy + dispatch (below) |
| `dispatch_with(hooks, eff_method, req, body, handler) -> HandlerOut` | hook-aware dispatch: pre -> route match + policy + handler -> after (section 2.6) |
| `handle_connection(client, handler)` | drives one accepted fd through its keep-alive cycles with an empty hook set (section 3) |
| `handle_connection_with(client, handler, hooks)` | the same loop, dispatching through `hooks` |
| `serve(handler) -> Int` | binds `PULSE_BIND:PULSE_PORT`, accepts sequentially, calls `handle_connection`; returns 0 on `X-Pulse-Quit`, 1 on socket failure |
| `serve_with(handler, hooks) -> Int` | the same accept loop with the hook-aware connection loop |

`HandlerOut` is the frozen type: `{ status: Int; content_type: Str;
headers: Vec[(Str, Str)]; body: Str; body_bytes: Vec[UInt8] }`; a non-empty
`body_bytes` selects the raw-bytes builder. The handler signature is
`fn(&PulseRequest, &PulseRoute, Str) -> HandlerOut` (non-capturing XIOM fn
value; no closures).

`handle_route` keeps the frozen policy before dispatch:

- `chunked` + `Content-Length` -> **400** (`Transfer-Encoding` and
  `Content-Length` together is the classic CL.TE smuggling shape);
- any non-chunked `Transfer-Encoding` -> **501**;
- kind 0 -> the JSON 404 envelope; kind 2 -> **405** with `Allow`;
- otherwise the registered handler is called (body already decoded).

`HEAD` is dispatched as `GET` and the body is trimmed at the head
terminator (frozen behavior). `X-Pulse-Quit: 1` stops the accept loop after
the connection closes (kept from the frozen loop as the clean-shutdown
seam).

### 2.6 Hook seam (`pre_route` + `after_response`)

The hook seam is the Station adoption point: product behaviors (metrics,
audit, access log, CORS preflight) live in hooks and the carved loop stays
unchanged. A `HookSet` is a value; an empty set (`hooks_new`) produces the
same response bytes as the hook-free core.

```xi
pub type ResponseInfo = {
  status: Int;
  bytes: Int;        // body_bytes.len() when non-empty, else body.len()
  duration_ms: Int;  // pre + routing + handler; send excluded
}

pub type PreOut = {
  short_circuit: Bool;
  response: HandlerOut;
}

pub type HookSet = {
  pre: Vec[fn(&PulseRequest, Str) -> PreOut];
  after: Vec[fn(&PulseRequest, Str, &HandlerOut, &ResponseInfo)];
}

pub enum HookError {
  PreAlreadyInstalled,
  AfterAlreadyInstalled,
}
```

| Fn | Behavior |
|---|---|
| `hooks_new() -> HookSet` | an empty set (both slots empty) |
| `pre_continue() -> PreOut` | "dispatch normally" |
| `pre_stop(response) -> PreOut` | short-circuit with `response` |
| `hooks_install_pre(hs, h) -> Result[Bool, HookError]` | installs the single pre hook; a second install is `Err(PreAlreadyInstalled)` |
| `hooks_install_after(hs, h) -> Result[Bool, HookError]` | installs the single after hook; a second install is `Err(AfterAlreadyInstalled)` |
| `hooks_clear_pre` / `hooks_clear_after` / `hooks_clear(hs) -> Bool` | removes one/both; returns whether anything was installed; idempotent |
| `hooks_has_pre` / `hooks_has_after(hs) -> Bool` | registration state |
| `hook_error_code(e) -> Str` | `"pre_already_installed"` / `"after_already_installed"` |

Call order for one parsed request (the `dispatch_with` path used by the
connection loop):

1. **pre hook** runs after `parse_request`, before `v1_path`/`route_match`,
   with the decoded body. `pre_continue()` falls through; `pre_stop(resp)`
   skips route matching and the handler and uses `resp` (e.g. an OPTIONS
   preflight 204).
2. **dispatch**: routing, the frozen TE/CL policy, 404/405, then the
   registered handler.
3. **after hook** runs exactly once per dispatch outcome -- including
   pre-hook short-circuits and the policy responses -- and observes the
   final `HandlerOut` plus `ResponseInfo{status, bytes, duration_ms}`. The
   per-request id is available through `reqctx.get_rid()`.

The seam does not wrap outcomes that bypass dispatch: parse failures,
`X-Pulse-Quit`, the 408 deadline path, idle/EOF closes. `HEAD` still
dispatches as `GET` and is trimmed at send time; `bytes` reports the
produced body.

Implementation note: the slot vectors and direct fn types are deliberate
workarounds for three 0.64.6 fn-value defects, with minimization probes in
`docs/COMPILER-NOTES.md` (global fn var, adjacent fn struct fields, fn
alias as a callable parameter). Do not "simplify" the slots back to fn
fields or aliases.

## 3. Keep-alive + deadlines (frozen A/B semantics)

Mirrors `docs/DESIGN-KEEPALIVE-DEADLINES.md` in the source repo at
`56eb9f8` (normative): Phase A deadlines + Phase B keep-alive.

Deadlines (Phase A):

- `PULSE_READ_TIMEOUT` bounds the whole request; the per-recv budget
  **shrinks** with elapsed time (cumulative semantics, fasthttp model:
  `recv_bounded`).
- On cycle 0 the first byte waits under `PULSE_READ_TIMEOUT`; on cycle > 0
  under `PULSE_IDLE_TIMEOUT`.
- A deadline (or socket error) before the request completes answers
  **408 Request Timeout with close** (best-effort) and closes -- one slow
  client cannot stall the single-threaded loop (slowloris guard).
- `PULSE_WRITE_TIMEOUT` bounds one response write: the fd goes
  non-blocking, every 64 KiB slice is poll-gated (`socket_poll_write`), and
  expiry drops the connection (a half-written response is never retried).
- `0` in any deadline disables it (dev only; the source `--check-config`
  warnings are dropped with the product config).

Keep-alive (Phase B):

- **Reuse latch (one-way):** `keep = keep && framed_end(raw) >= 0 &&
  !connection_close_requested(req)`; once a cycle closes, the connection
  never reuses. A `Connection: close` comma-token closes; HTTP/1.0 peers
  never reuse (not even with `Connection: keep-alive`); incomplete/oversize
  framing closes after the response.
- **Per-connection trailing buffer:** bytes past the framed request are
  carried into the next cycle (h11 rule 4 -- unparsed bytes are never
  lost); a fully buffered pipelined request is served without another recv
  (`request_complete` pre-check).
- **In-order pipelining:** requests are parsed and answered strictly in the
  order received, one cycle each.
- **Silent idle expiry:** on cycle > 0, an idle deadline before the first
  byte closes silently -- no 408 (fasthttp model).
- **EOF semantics:** EOF mid-message closes with no answer (h11 rule 6);
  EOF between cycles is a clean close.
- **Garbage at cycle 2:** an unparsable second request yields the 400
  envelope on that cycle and closes (no bleed into the previous response).
- **Response head:** reuse emits no `Connection` header; close emits
  `Connection: close` (frozen builders).
- **`PULSE_KEEPALIVE=0`** restores close-per-request (the latch starts
  closed for the connection).
- **100-continue** stays per request: `read_request` answers
  `HTTP/1.1 100 Continue` before waiting for the body when the head
  carries `Expect: 100-continue`.

The single-threaded sequential-accept architecture is unchanged (no
select, no threads; `accept` has no deadline and stays out of scope).

## 4. Caps and limits (re-verified at `56eb9f8`)

| Cap | Value | Where |
|---|---|---|
| Request head buffer | 16384 bytes | `http.header_limit_bytes` / `header_overflow` |
| Header lines | 100 | `http.header_count_limit` / `parse_request` |
| Request body (CL and decoded chunked) | 1048576 bytes | `http.body_limit_bytes`, `server.xi MAX_BODY` (kept in sync) |
| Recv rounds per request | 1024 | `read_request` |
| Recv chunk | 65536 bytes | `recv_bounded` / `socket_recv` cap |
| Chunked raw headroom | head + 4 + 1 MiB + 16 KiB | `read_request` tcap / `request_complete` |
| Chunk/trailer scan guards | 1000000 chunks / 1000 trailer lines / 1024-byte partial line | `chunked_state`, `chunked_end`, `decode_chunked` |
| Send slice | 65536 bytes | `send_step` |
| Listen backlog | 128 | `serve` |

## 5. Extraction deviations and shims (full list)

The brief's rule: stdlib-only, drop imports that force other packages, add
the smallest documented local shim, keep carved code verbatim wherever
possible. Recorded deltas from the frozen files:

1. **Router shim (new code, no contracts).** `src/router.xi` dropped
   `use xiom.router;` (registry package, out of the dependency target) and
   inlines the matching mechanism as private `local_router_*` functions
   ported 1:1 from `xiom.router` 0.1.0 (pattern shapes, `:param` capture,
   registration-order first match, 404/405 + deduplicated Allow list).
2. **`route_match` signature.** Gained a `defs: &Vec[(Str, Str)]`
   parameter; the product `route_defs()`/`routes_list()` table (25 routes)
   is dropped. App-level registration lives in `xiom.pulse.app`
   (`register`/`routes_list`).
3. **`config.xi` slimmed** to the six getters in 2.4; dropped:
   `cfg_load_file`/`cfg_apply_str` (PULSE_CONFIG JSON loader),
   `cfg_validate`, and every product knob (rate limit, uploads, site,
   assets, landing, csp, cors, csrf, log, audit, store, kv, session, jwt,
   icon, openapi, game, static).
4. **`server.xi` carve.** Dropped: site/static serving, icon, JWT, game,
   multipart, openapi, audit, metrics and access-log hooks,
   store/session wiring, CORS (incl. the OPTIONS preflight branch), CSRF,
   rate limiting, the product route table and all product CLI
   (`--version`/`--check-config`/`routes`/`openapi`). Kept verbatim:
   `HandlerOut`, `next_rid`, `error_status_body`, `out_*`, `recv_bounded`,
   `request_complete`, `read_request`, `send_step`, `send_all`,
   `dispatch_one`/`handle_route` generic forms, and the loop body.
5. **`Date` header assembly dropped** (`with_std_headers` used the
   registry `xiom.static` HTTP-date formatter and `PULSE_CSP`); responses
   carry no `Date`/`Content-Security-Policy` from the core. Consumers can
   inject either with `http.with_header_line` (kept, public) at their
   handler/wrapper level.
6. **New public fns / seams (no contracts, per the porter rule):**
   `app.register`, `app.routes_list`, `app.out_json`/`out_text`/`out_html`
   (previously private helpers), `app.handle_connection` (the per-
   connection cycle loop extracted from the frozen `main` so tests and
   consumers can drive one fd without owning the accept loop),
   `app.serve` (the frozen accept loop parametrized by one handler
   instead of the product route table), the hook seam (section 2.6:
   `hooks_new`, `pre_continue`, `pre_stop`, `hooks_install_pre`,
   `hooks_install_after`, `hooks_clear_pre`, `hooks_clear_after`,
   `hooks_clear`, `hooks_has_pre`, `hooks_has_after`, `hook_error_code`,
   `dispatch_with`, `handle_connection_with`, `serve_with`), and the
   `xiom.pulse.minimal` example.
7. **`http.xi` is byte-verbatim**, including `bearer_token` and
   `idem_key_valid` (small pure helpers the frozen parser module ships;
   they carry no dependency and are documented here for completeness).
8. **`envelope.xi`, `reqctx.xi`, `pulse.xi` are byte-verbatim.**

## 6. Conformance suite

`tests/test_conformance.xi` (driver with explicit `fn main`) ports the
hardening fixtures from the source `tests/test_http.xi` plus the keep-alive
A/B checks mined from `scripts/http_smoke.ps1` sections 13e/13f, adds
hook-seam checks (section I), and adds five loopback end-to-end checks over
two real fds (no threads):

- A/B/E/F: parser + framing goldens, caps, chunked (Wikipedia golden,
  state transitions 1/0/-1, extension + trailer, decoded cap), TE/CL
  smuggling rules through `handle_route`, `Expect: 100-continue`
  detection, builders incl. keep-flag variants, status text, security
  headers, query/URL decoding, v1 alias, router mechanism (registration
  order, `:param`, 405 + Allow, empty table).
- G: reuse latch decisions (`Connection: close` token, comma-token case,
  HTTP/1.0 no-reuse), `PULSE_KEEPALIVE`, deadline defaults/env.
- H (E2E): pipelined two requests on one fd (two ordered responses; the
  first without `Connection: close`, the second with it), silent idle
  expiry (~PULSE_IDLE_TIMEOUT, no 408, no close header),
  `PULSE_KEEPALIVE=0` close-per-request, the `Expect: 100-continue`
  interim arriving before the final response, and one hooked preflight
  over a real fd (204 + CORS header, handler skipped). Ports are bound by
  the suite on 127.0.0.1 with a 24-port retry range; the suite is
  offline-safe.
- I (hook seam): empty-set equivalence with `handle_route`, the post hook's
  status/bytes/duration observation, pre -> handler -> after ordering,
  policy-outcome observation (404), pre-hook short-circuit (no handler),
  registration/clear (including idempotent clear), and the typed misuse
  errors (`pre_already_installed` / `after_already_installed`).

## 7. Provenance

Upstream: `https://github.com/xiom-projects/xiom-pulse.git`, commit
`56eb9f888e3bb5ae1d85bd9bd484fd769a45ff23` (`56eb9f8`, 2026-10-16
17:00:49 +0300; Phase B keep-alive), pair `7924222` (Phase A), design doc
`docs/DESIGN-KEEPALIVE-DEADLINES.md` (normative). Carve method, the
per-file SHA256 table at extraction time, and the reconciliation record
are in `PROVENANCE.md`.
