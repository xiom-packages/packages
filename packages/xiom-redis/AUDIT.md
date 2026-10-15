# AUDIT: xiom-redis

## Status

Complete, pure-XIOM Redis RESP2 client. Conformance-tested **19/19,
recorded x2 green** on the installed XIOM v0.64.5 (repo pin v0.64.4),
stdlib `E:\xiom-lang\stdlib`:

```
port: PASS (passed=19 failed=0 program_exit=0 exit=0)   (run 1)
port: PASS (passed=19 failed=0 program_exit=0 exit=0)   (run 2)
```

Run with `.\scripts\port.ps1 -Package xiom.redis -TimeoutSec 300`.
The suite driver is `tests/test_conformance.xi`; the checks live in
`tests/suite_codec.xi` (7), `tests/suite_net.xi` (9) and
`tests/suite_live.xi` (3).

## System library dependencies

**None.** The stub-era hiredis FFI lane is removed: no C bridge, no
vendored hiredis, no linked C library, no `hiredis.xiom-bind`. The
transport is the stdlib TCP socket (`xiom.net.socket`), which the runtime
already links. A Redis server is required only for the two live checks
(which print an explicit SKIP line when `127.0.0.1:6379` is unreachable --
the state in this build environment, verified independently).

## What changed from the stub

- `hiredis.xiom-bind` deleted; `redis.xi`/`src/client.xi` stub bodies
  replaced by a real implementation split over five modules:
  `xiom.redis` (public surface), `xiom.redis.value` (value model,
  constants, accessors), `xiom.redis.resp` (codec), `xiom.redis.client`
  (session/transport), `xiom.redis.verbs` (typed verbs, pub/sub).
- `package.xi`: description/keywords updated (hiredis -> RESP2), modules
  list added; name/version/categories/license unchanged.
- `set` / `del` are plain module functions again (the stub-era temporary
  `rset`/`rdel` renames are gone; the public surface lives in module
  `xiom.redis`, where `set`/`del` resolve -- pinned by the suite).
- `tests/test_redis.xi` (stub self-test) removed; superseded by the
  19-check conformance suite.
- `README.md` / `SPEC.md` / `PROVENANCE.md` rewritten; this file and
  `ROADMAP.md` brought in line.

## Verification record

- Codec: exact wire bytes for PING/SET/ECHO/DEL, empty-argument and
  CRLF-in-argument framing; decode of every RESP2 type incl. `$-1`/`*-1`
  nulls, nested arrays, non-zero offsets and relative consumed counts; the
  truncated / garbage / cap / depth error codes; typed accessors and the
  wrong-type error path.
- Client: deterministic loopback scenarios against an in-process scripted
  server asserting the **exact request bytes** for every scenario (PING,
  SET/GET/ECHO, GET-null, INCR/TTL, MGET with a null element, GET-error
  raw/checked/verb, a 4-command pipeline, SUBSCRIBE+push); read timeout on
  a stalled server; clean-FIN mid-reply truncation; refused-port
  classification; live checks (SKIP recorded; executed against a real
  Redis when one is reachable).
- Development probes (socket transport, connect-refusal
  characterization) were scratch scaffolding under `tests/` and were
  deleted after their findings were recorded below.

## Known gaps and deviations (honest record)

1. **Windows refused-connect misreport (runtime, not this package).**
   Evidence probe: `socket_connect` to a closed loopback port returned
   `Ok(fd)` while the same fd then failed `send_all` immediately
   (`socket_send_all: send failed`) and `recv` (`socket_recv: recv
   failed`); a healthy connection sends fine. The client therefore
   classifies a **first-command send failure before any byte has been
   sent** as `REDIS_ERR_CONNECT`; `ping` against a refused connection
   yields kind 1 (`REDIS_ERR_CONNECT`). Pinned by suite check n17: a
   refused port must produce `REDIS_ERR_CONNECT` (at connect or first
   command). On runtimes that report the connect error correctly the
   classification happens at `connect` directly.
2. **TCP connect deadline.** `connect_timeout` applies `timeout_sec` as
   the session read deadline; the TCP handshake itself is OS-bounded
   because the runtime exposes no connect deadline and the library keeps
   no internal wall clock (design constraint, documented in SPEC 3.1).
3. **Compiler module resolution with relative entry paths.** Direct
   `xiom --emit-ir tests/test_conformance.xi` from the package directory
   fails to resolve `use xiom.redis...`; the identical invocation with an
   **absolute** path succeeds (`port.ps1` always passes absolute paths).
   Reproduced on v0.64.4 and v0.64.5; recorded for the toolchain owners.
4. **Live-server parity not yet exercised here.** The live checks n18/n19
   were verified in SKIP mode (no Redis reachable in this environment);
   their live path compiles and is ready but is not claimed as run. A
   live-server record is a follow-up (`ROADMAP.md`).
5. **Non-goals** (RESP3, TLS, cluster/sentinel, scripting, transactions,
   blocking commands, auth helpers, streams, pooling) are declared in
   `SPEC.md` section 9 -- absent by declaration, not by omission.

## Files

| File | Role |
|---|---|
| `redis.xi` | module `xiom.redis`: public plain-name surface |
| `src/value.xi` | module `xiom.redis.value`: values, errors, accessors |
| `src/resp.xi` | module `xiom.redis.resp`: RESP2 codec |
| `src/client.xi` | module `xiom.redis.client`: session/transport |
| `src/verbs.xi` | module `xiom.redis.verbs`: typed verbs, pub/sub |
| `tests/test_conformance.xi` | suite driver (declared for `port.ps1`) |
| `tests/suite_codec.xi`, `tests/suite_net.xi`, `tests/suite_live.xi` | the 19 checks |
| `README.md`, `SPEC.md`, `PROVENANCE.md`, `AUDIT.md`, `ROADMAP.md` | docs |
