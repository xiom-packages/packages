# AUDIT: xiom-postgres

## Status

Pure-XIOM, no-FFI PostgreSQL wire-protocol (v3) client. All 4 source files
(3 modules + manifest) compile on XIOM v0.64.5 and the conformance suite is
green: **38/38 passed, failed=0**, recorded x2 (identical counts) via
`scripts/port.ps1 -Package xiom.postgres -TimeoutSec 300`.

The 0.0.x stub's libpq path is fully removed:

- `libpq.xiom-bind` (C ABI mapping) -- deleted.
- root `postgres.xi` (libpq-shaped stub bodies) and `src/client.xi`
  (self-contained stub) -- replaced by `src/postgres.xi`,
  `src/wire.xi`, `src/auth.xi`.
- `tests/test_postgres.xi` (stub test) -- replaced by
  `tests/test_conformance.xi`.

## System library dependencies

**None beyond the XIOM runtime.** No libpq, no OpenSSL, no vendored C.
Transport is `xiom.net.socket` (`socket_tcp`, `socket_connect`,
`socket_send_all`, `socket_recv_timeout`, `socket_close`), and the crypto
primitives used by SCRAM are stdlib (`xiom.crypto` sha256/hmac_sha256/
pbkdf2, `xiom.rand.random_bytes_crypto`).

## Verification state

| Check | Result |
|---|---|
| `port.ps1 -Package xiom.postgres -TimeoutSec 300` run 1 | PASS (38 passed / 0 failed) |
| `port.ps1 -Package xiom.postgres -TimeoutSec 300` run 2 | PASS (38 passed / 0 failed) |
| namespace audit (in-harness) | `xiom.postgres OK (3 module(s))`, 0 conflicts |
| codec goldens (frontend exact bytes) | 5/5 (startup 35 B, password, query, terminate, SASL) |
| decode goldens + fault injection | 13/13 (typed errors with exact byte offsets) |
| auth KATs (RFC 1321, PostgreSQL MD5 challenge, RFC 7677) | 4/4 |
| scripted loopback (real TCP, in-process server) | 7/7 |
| error taxonomy / guards / quoting | 8/8 |
| live path (127.0.0.1:5432) | honest SKIP/result per environment |

Scratch transport probe (before building the client): a minimal
socket_tcp/connect/bind/listen/accept/send/recv_timeout round trip over
loopback compiled and ran green from a package-style layout, proving the
stdlib socket API is usable from package suites on this toolchain.

## Toolchain defects observed (and how the package copes)

1. **`xiom.crypto.md5` is defective in v0.64.5.** `md5("abc")` returns
   `5aac66a4e204752757366266cfad9c14`; RFC 1321 requires
   `900150983cd24fb0d6963f7d28e17f72`. The package carries its own
   byte-based MD5 (`auth.md5_digest`, RFC 1321 constants) pinned by three
   published vectors plus the PostgreSQL challenge vector.
2. **Tuple-typed codegen collision.** A program using tuple-returning
   helpers across modules produced a clang-level `%struct.Tuple__Int__Int`
   vs `Tuple__Str__Int` mismatch (`xiominput.ll`). Module-boundary helpers
   therefore return small structs (`PgCStr`, `SrvMsg`, `ListenAny`,
   `LoopPair`) - no tuples cross a module boundary in the package.
3. **`xiom.thread.spawn` is simulated** (executes the closure inline, see
   stdlib `xiom.thread.spawn`), so no real concurrency is available for a
   scripted server. The loopback harness pre-writes the server script and
   drives the client through `attach` (fd adoption) - still a real
   TCP loopback exchange with exact byte assertions on both sides.
4. **No `socket_local_addr`; `socket_bind` rejects port 0.** An OS-assigned
   ephemeral port is unreachable through the stdlib API, so the harness
   scans candidate ports 45440-45499 and uses the first that binds.
5. **Connect failure surfacing.** On this environment a refused/filtered
   connect can report success at `socket_connect` and fail at the first
   `send` (observed against a non-listening 5432 with Docker active). Both
   surfaces map to `PG_ERR_CONNECTION`; the taxonomy does not distinguish
   them.

## Known gaps (declared, not silent)

- TLS, extended protocol / `$1` parameters, COPY, notification-listening
  APIs, SASLprep, SCRAM channel binding, binary result formats: non-goals
  of 0.1.0 (see `SPEC.md` section 9, ordering in `ROADMAP.md`).
- The live-PG leg is SKIP-dependent on the machine (no PostgreSQL at
  127.0.0.1:5432 on the build host: the probe/connect path reports an
  explicit SKIP with the reason).
- The scripted loopback server is a test double, not PostgreSQL: it pins
  the documented byte shapes; end-to-end parity against a real server is
  the live leg when one is available.
