# xiom.pulse -- PULSE Beacon (embeddable core)

> **Status:** `incubating` -- conformance-tested (231/231), recorded x2 green
> on XIOM v0.65.1. Current version: `0.3.2` (single tag `xiom-pulse/v0.3.2`,
> sha256 `6f2b6ff8...`, 2026-10-27 -- Beacon response-path allocation fix:
> 5,590 -> 60 B/iter build, keep-alive 40.9 -> 29.9 KB/req, byte-identical
> output; `0.3.1` in `xiom-pulse/v0.3.1` -- unmatched-route fallback seam +
> HEAD body trim; `0.3.0` in `xiom-pulse/v0.3.0` -- stateful HookCtx seam; `0.2.2` in
> `eco-v0.1.198` -- version-identity fix; `0.2.1` in `eco-v0.1.197` -- body-cap
> hardening; `0.2.0` in `eco-v0.1.195` -- hook seam + Server-token seam;
> previous publish: `0.1.0` in `eco-v0.1.192`, sha256 `53fcc56e...`).
> **Scope:** the frozen PULSE protocol core (Beacon extraction): HTTP/1.1
> request parser + response builders, the keep-alive A/B connection loop
> with named deadlines, the route matching mechanism and the uniform JSON
> error envelope. Pure XIOM, no FFI, no bridge C.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` only. The PULSE family packages
> (session / static / kv / rate / metrics / middleware / sqlite) stay out;
> consumers compose them separately.

## Identity (tiers)

The PULSE line is one core, two products: **Beacon** is this embeddable
package (the registry tier); **Station** is the standalone PULSE product,
built on this same package -- one core, never a fork.

## What it is

`xiom.pulse` is a single-threaded sequential-accept HTTP/1.1 service core,
carved verbatim from the PULSE repo at commit `56eb9f8` (pair `7924222`;
see `PROVENANCE.md`):

- **Parser + framing** (`xiom.pulse.http`): request line + headers with the
  frozen caps (16 KiB head, 100 header lines, 1 MiB body), Content-Length
  framing, chunked decoding (extensions ignored, trailers validated, 1 MiB
  decoded cap), `Expect: 100-continue`, TE/CL smuggling rejection, and the
  response builders with the reviewed security-header block. A non-chunked
  declared `Content-Length` above the 1 MiB cap is rejected as **413**
  `"body too large"` before dispatch -- even when only a partial body
  arrived -- so truncated oversized bodies never parse as `ok=true`.
- **Connection loop** (`xiom.pulse.app`): named deadlines
  (`PULSE_READ_TIMEOUT` / `PULSE_WRITE_TIMEOUT` / `PULSE_IDLE_TIMEOUT`),
  the keep-alive A/B semantics -- one-way reuse latch (`Connection: close`
  token, HTTP/1.0 never reuses, incomplete framing closes), per-connection
  trailing buffer with in-order pipelining, silent idle expiry,
  `PULSE_KEEPALIVE=0` restore, EOF-mid-message close-with-no-answer -- and
  a 408 slowloris guard. `HEAD` is dispatched as `GET`, so the response is
  built exactly as GET (same `Content-Length`) but only the headers are
  sent; the reuse latch keys off the request framing, so keep-alive stays
  correct.
- **Routing** (`xiom.pulse.router`): `:name` path parameters in
  registration order, 404/405 + Allow, query splitting and percent
  decoding, `/v1` alias mapping.
- **Envelope** (`xiom.pulse.envelope`): the uniform
  `{"error":{"code":...,"message":...,"rid":...}}` JSON body.

## Quick start (three lines)

```xi
fn health(_req: &PulseRequest, _m: &PulseRoute, _body: Str) -> HandlerOut {
  return app.out_json(200, "{\"status\":\"ok\"}");
}

pub fn main() -> Int {
  let _ = app.register("GET", "/health");
  return app.serve(health);
}
```

`src/minimal.xi` is exactly this shape; run it with
`xiom --run src/minimal.xi`, then `curl http://127.0.0.1:8080/health`.
`PULSE_PORT` / `PULSE_BIND` move the listener; stop the loop with one
request carrying `X-Pulse-Quit: 1`.

## Consumer integration

Declare the dependency; namespace any modules you own that share the
package's module names. Package modules take precedence over consumer
modules with the same name -- a local module that collides is shadowed
silently, with only warning W001 -- so name product modules under your own
root (for example `station.app`, not `xiom.pulse.app`).

The product behaviors that PULSE's Station adds (metrics start/finish,
audit append, structured access log with rid/duration, CORS preflight) hang
off the opt-in hook seam in `xiom.pulse.app`. With no hooks installed,
`serve` / `dispatch` behave exactly like the carved core.

```xi
use xiom.pulse.app;
use xiom.pulse.http;
use xiom.pulse.reqctx;

fn cors_preflight(req: &PulseRequest, _body: Str) -> PreOut {
  if req.method == "OPTIONS" {
    var hs: Vec[(Str, Str)] = Vec[(Str, Str)].new();
    hs.push(("Access-Control-Allow-Origin", "*"));
    return app.pre_stop(HandlerOut{ status: 204; content_type: "text/plain; charset=utf-8"; headers: hs; body: ""; body_bytes: Vec[UInt8].new() });
  }
  return app.pre_continue();
}

fn access_log(_req: &PulseRequest, _body: Str, out: &HandlerOut, info: &ResponseInfo) {
  // Metrics/audit/access-log finish: rid, status, response bytes, duration.
  // let rid = reqctx.get_rid();
  let _status = out.status;
  let _bytes = info.bytes;
  let _dur = info.duration_ms;
}

pub fn main() -> Int {
  let _ = app.register("GET", "/health");
  var hooks = app.hooks_new();
  let _ = app.hooks_install_pre(&mut hooks, cors_preflight);
  let _ = app.hooks_install_after(&mut hooks, access_log);
  return app.serve_with(health, &hooks);
}
```

Semantics: the pre hook runs after parsing and before route matching and
may short-circuit (`pre_stop`); the after hook runs once per dispatched
response, including short-circuits and 404/405/400/501 outcomes, with
`ResponseInfo{status, bytes, duration_ms}` (send time excluded; rid via
`reqctx.get_rid()`). Re-installing a hook returns the typed
`HookError` (`pre_already_installed` / `after_already_installed`);
clearing is idempotent.

### Stateful hooks: `HookCtx` (rate-limiter seam)

Stateless fn-pointer hooks cannot carry per-install state. The additive
stateful variants take a `&mut HookCtx` tail argument, where `HookCtx` is a
consumer-managed handle bag (`Vec[Int]`); the core never interprets it. The
same bag goes to the pre hook before routing and to the after hooks exactly
once per outcome, so a pre-hook mutation is visible to the after hook.
Stateless hooks run first, then stateful hooks; mixing both in one
`HookSet` is supported, and the stateless API (plus no-hook behavior) is
unchanged.

```xi
// Token bucket in the bag: state[0] = count, state[1] = limit.
fn limiter(req: &PulseRequest, _body: Str, ctx: &mut HookCtx) -> PreOut {
  let n = app.hookctx_get(ctx, 0) + 1;
  let _ = app.hookctx_set(ctx, 0, n);
  if n > app.hookctx_get(ctx, 1) {
    return app.pre_stop(app.out_json(429, "{\"error\":{\"code\":\"rate_limited\",\"message\":\"too many requests\"}}"));
  }
  return app.pre_continue();
}

pub fn main() -> Int {
  let _ = app.register("GET", "/health");
  var hooks = app.hooks_new();
  let _ = app.hooks_install_pre_ctx(&mut hooks, limiter);
  var ctx = app.hookctx_new();
  let _ = app.hookctx_push(&mut ctx, 0);    // count
  let _ = app.hookctx_push(&mut ctx, 100);  // limit
  return app.serve_with_ctx(health, &hooks, &mut ctx);
}
```

API: `hookctx_new`, `hookctx_get(ctx, i)`, `hookctx_set(ctx, i, v)`,
`hookctx_len`, `hookctx_push`, `hookctx_clear`;
`hooks_install_pre_ctx` / `hooks_install_after_ctx` (with
`pre_ctx_already_installed` / `after_ctx_already_installed`);
`dispatch_with_ctx(hooks, ctx, eff_method, req, body, handler)`,
`handle_connection_with_ctx(client, handler, hooks, ctx)` and
`serve_with_ctx(handler, hooks, ctx)`. `serve_with` /
`handle_connection_with` supply a fresh bag automatically; use the `_ctx`
variants to own a bucket across keep-alive cycles and reconnects.

### Unmatched-route fallback (site/static tree seam)

`HookSet.fallback` is consulted for route kind 0 (no registered route)
before the package JSON 404. It receives the parsed request and the decoded
body and its `HandlerOut` becomes the response, so a site tree can serve
files and supply a custom 404 body while registered routes keep the normal
handler. The fallback is not used for kind 2 (method mismatch -> 405), and
the TE/CL framing policy still runs first. With no fallback installed the
404 is byte-identical to the hook-free core. `dispatch_with`,
`dispatch_with_ctx` and the connection loops all consult the same slot;
`handle_route` (which has no `HookSet`) always emits the package 404.

```xi
fn site(_req: &PulseRequest, _body: Str) -> HandlerOut {
  // Serve /site/... from a static tree; otherwise a custom 404 page.
  return app.out_html(404, "<html><body>not found</body></html>");
}

pub fn main() -> Int {
  let _ = app.register("GET", "/health");
  var hooks = app.hooks_new();
  let _ = app.hooks_install_fallback(&mut hooks, site);
  return app.serve_with(health, &hooks);
}
```

API: `hooks_install_fallback(hs, h)`, `hooks_clear_fallback(hs)` and
`hooks_has_fallback(hs)`; a second install returns the typed
`fallback_already_installed` (`HookError.FallbackAlreadyInstalled`).
`hooks_clear` removes the fallback with the other hooks.

### Release identity + `Server` header

`pulse.pulse_version()` reports the package version from the single
`PULSE_PACKAGE_VERSION` constant in `src/pulse.xi` (`0.3.0`, kept in sync
with `package.xi`). The response `Server` header is deliberately
version-free and consumer-controlled: both builders emit
`Server: xiom-pulse` by default. Set your own token once before `serve` /
`serve_with`:

```xi
use xiom.pulse;
use xiom.pulse.app;

pub fn main() -> Int {
  // Advertise the Station release, not the embedded core release.
  let _ = app.app_set_server_token("xiom-pulse-station/1.4.2");
  let _ = app.register("GET", "/health");
  return app.serve(health);
}
```

The token is process-wide and must be non-empty printable ASCII; empty or
CR/LF/control input returns `false` and leaves the previous token intact,
so a token can never inject another header line. `app.app_server_token()`
(and `http.server_token()` / `http.set_server_token()` for direct builder
users) exposes the same seam. The parser and both response builders are
covered by exact byte assertions in the suite.

## Public surface

| Module | Surface |
|---|---|
| `xiom.pulse` | `pulse_version()` (single `PULSE_PACKAGE_VERSION` source) |
| `xiom.pulse.http` | `PulseRequest`, `RouteResult`, `ChunkedBody`; `parse_request`, `framed_end`, `chunked_state`, `decode_chunked`, `connection_close_requested`, `expects_continue`, `status_text`, `security_head_lines`, `server_token`, `set_server_token`, `build_response`, `build_response_full`, `build_response_bytes`, `with_header_line`, `header_get`, `transfer_encoding_of`, `te_is_chunked`, `content_length_of`, `raw_header_value`, `str_to_bytes`, `bytes_to_str`, `find_header_end`, `header_limit_bytes`, `header_overflow`, `header_count_limit`, `body_limit_bytes`, `bearer_token`, `idem_key_valid` |
| `xiom.pulse.router` | `PulseRoute`; `route_match(method, target, defs)`, `split_target`, `parse_query`, `url_decode`, `v1_path` |
| `xiom.pulse.envelope` | `error_body`, `ok_bool`, `single_field` |
| `xiom.pulse.reqctx` | `set_rid`, `get_rid` |
| `xiom.pulse.config` | `cfg_read_timeout`, `cfg_write_timeout`, `cfg_idle_timeout`, `cfg_keepalive`, `cfg_port`, `cfg_bind` |
| `xiom.pulse.app` | `HandlerOut`, `ResponseInfo`, `PreOut`, `HookCtx`, `HookSet`, `HookError`; `register`, `routes_list`, `out_json`, `out_text`, `out_html`, `handle_route`, `dispatch_with`, `dispatch_with_ctx`, `handle_connection`, `handle_connection_with`, `handle_connection_with_ctx`, `serve`, `serve_with`, `serve_with_ctx`, `app_set_server_token`, `app_server_token`, `hooks_new`, `pre_continue`, `pre_stop`, `hooks_install_pre`, `hooks_install_after`, `hooks_install_pre_ctx`, `hooks_install_after_ctx`, `hooks_install_fallback`, `hooks_clear_pre`, `hooks_clear_after`, `hooks_clear_fallback`, `hooks_clear`, `hooks_has_pre`, `hooks_has_after`, `hooks_has_fallback`, `hook_error_code`, `hookctx_new`, `hookctx_get`, `hookctx_set`, `hookctx_len`, `hookctx_push`, `hookctx_clear` |
| `xiom.pulse.minimal` | the runnable example (`main`) |

## Verify

```
.\scripts\port.ps1 -Package xiom-pulse
```

`tests/test_conformance.xi` (driver with explicit `fn main`) carries the
protocol-hardening fixtures, the keep-alive A/B decisions, the hook-seam
checks (pre/post ordering, short-circuit, registration/clear, typed misuse,
stateful `HookCtx` accessors, limiter short-circuit, stateless+stateful
mixing, unmatched-route fallback install/clear/typed misuse and site-like
serving, HEAD body trim with GET-equal `Content-Length`), release-identity/
Server-token byte checks, and loopback end-to-end checks (pipelined reuse on
one fd, silent idle expiry, `PULSE_KEEPALIVE=0`, `Expect: 100-continue`,
hooked CORS preflight, fallback serving, HEAD/GET header equality) over real
sockets -- offline-safe, no threads.

Spec details: `SPEC.md` (surface, caps, A/B semantics, deviations).
Extraction record: `PROVENANCE.md` (pinned commit + per-file SHA256).
Next steps: `ROADMAP.md`.
