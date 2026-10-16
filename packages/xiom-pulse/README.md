# xiom.pulse -- PULSE Beacon (embeddable core)

> **Status:** `incubating` -- conformance-tested (125/125), recorded x2 green
> on XIOM v0.64.5. Published: `0.1.0` in `eco-v0.1.192`
> (sha256 `53fcc56e...`).
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
  response builders with the reviewed security-header block.
- **Connection loop** (`xiom.pulse.app`): named deadlines
  (`PULSE_READ_TIMEOUT` / `PULSE_WRITE_TIMEOUT` / `PULSE_IDLE_TIMEOUT`),
  the keep-alive A/B semantics -- one-way reuse latch (`Connection: close`
  token, HTTP/1.0 never reuses, incomplete framing closes), per-connection
  trailing buffer with in-order pipelining, silent idle expiry,
  `PULSE_KEEPALIVE=0` restore, EOF-mid-message close-with-no-answer -- and
  a 408 slowloris guard.
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

## Public surface

| Module | Surface |
|---|---|
| `xiom.pulse` | `pulse_version()` |
| `xiom.pulse.http` | `PulseRequest`, `RouteResult`, `ChunkedBody`; `parse_request`, `framed_end`, `chunked_state`, `decode_chunked`, `connection_close_requested`, `expects_continue`, `status_text`, `security_head_lines`, `build_response`, `build_response_full`, `build_response_bytes`, `with_header_line`, `header_get`, `transfer_encoding_of`, `te_is_chunked`, `content_length_of`, `raw_header_value`, `str_to_bytes`, `bytes_to_str`, `find_header_end`, `header_limit_bytes`, `header_overflow`, `header_count_limit`, `body_limit_bytes`, `bearer_token`, `idem_key_valid` |
| `xiom.pulse.router` | `PulseRoute`; `route_match(method, target, defs)`, `split_target`, `parse_query`, `url_decode`, `v1_path` |
| `xiom.pulse.envelope` | `error_body`, `ok_bool`, `single_field` |
| `xiom.pulse.reqctx` | `set_rid`, `get_rid` |
| `xiom.pulse.config` | `cfg_read_timeout`, `cfg_write_timeout`, `cfg_idle_timeout`, `cfg_keepalive`, `cfg_port`, `cfg_bind` |
| `xiom.pulse.app` | `HandlerOut`; `register`, `routes_list`, `out_json`, `out_text`, `out_html`, `handle_route`, `handle_connection`, `serve` |
| `xiom.pulse.minimal` | the runnable example (`main`) |

## Verify

```
.\scripts\port.ps1 -Package xiom-pulse
```

`tests/test_conformance.xi` (driver with explicit `fn main`) carries the
protocol-hardening fixtures, the keep-alive A/B decisions, and four
loopback end-to-end checks (pipelined reuse on one fd, silent idle expiry,
`PULSE_KEEPALIVE=0`, `Expect: 100-continue`) over real sockets --
offline-safe, no threads.

Spec details: `SPEC.md` (surface, caps, A/B semantics, deviations).
Extraction record: `PROVENANCE.md` (pinned commit + per-file SHA256).
Next steps: `ROADMAP.md`.
