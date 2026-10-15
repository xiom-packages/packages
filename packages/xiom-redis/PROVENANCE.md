# PROVENANCE: xiom.redis

Upstream-first record (owner policy 2026-10-11, `docs/UPSTREAM-FIRST.md`).

This package is an **EXPLICITLY INDEPENDENT declaration: no vendored
upstream code, no translated code, no generated code, no upstream
implementation source consulted.** It is a pure-XIOM, from-scratch RESP2
client and codec for a protocol whose semantics are fully specified in
public documentation. The stub-era `hiredis.xiom-bind` placeholder and the
hiredis FFI lane were removed with this work: there is **no C bridge, no
FFI, no vendored hiredis and no linked C library** in the package.

## Reference basis

The implementation was written against the published Redis protocol
specification; the relay work item for this package explicitly framed the
work as an independent own-reader build on exactly these grounds ("RESP
codec from the Redis protocol specification; do NOT clone or vendor
hiredis; no upstream C library").

| Reference | Use |
|---|---|
| Redis serialization protocol specification, RESP2 ("Redis protocol specification", `https://redis.io/docs/latest/develop/reference/protocol-spec/`) -- the marker bytes (`+`, `-`, `:`, `$`, `*`), CRLF framing, the "array of bulk strings" command form, the `$-1` / `*-1` null forms and the error-prefix convention | declared wire format in `SPEC.md` section 2 and the encoder/decoder in `src/resp.xi` |
| Redis command reference (per-verb reply shapes: `+OK` for SET, integer for DEL/EXISTS/INCR/DECR/TTL/EXPIRE, bulk-or-null for GET, array-or-null for MGET, the SUBSCRIBE/UNSUBSCRIBE confirmation arrays and the `message` push framing, and the "subscribed mode" command subset) | the typed verb wrappers in `src/verbs.xi` and the client semantics in `SPEC.md` section 3 |
| The protocol's documented practical limits (inline vs. multibulk framing is not used; the 512 MB protocol bulk limit is an upper bound) | the package's own declared caps in `SPEC.md` section 2.3 are stricter sanity limits (`RESP_MAX_BULK` 64 MiB, `RESP_MAX_ARRAY` 1048576, `RESP_MAX_DEPTH` 32, `RESP_MAX_REPLY` 128 MiB), chosen so malformed input fails fast |

No implementation source was read for this work: not the hiredis C client,
not the redis/redis server sources, not any third-party RESP library
(Python/Go/Rust/JS client code bases were deliberately not consulted), so
nothing needed to be derived, attributed or re-licensed. The facts
reproduced here are the protocol's interoperability surface (marker bytes,
framing order, null forms, reply shapes), re-expressed in XIOM with no
shared identifiers, structure or text.

## Clone / cleanup ledger

**No oracle repository was cloned or consulted for this package.**
`E:\repos` was searched first: no redis-server, redis-client or hiredis
clone exists there, and none was created for this work. `E:\repos\
CLEANUP.md` therefore has no row for this work item and was not modified --
there is nothing to sweep. If a future revision wants live-oracle parity
(real server binaries exercised in CI), that re-carve should clone the
redis repository at a pinned release tag and add a ledger row at that time;
the response fixtures used here were composed from the specification, not
from any server run (see below).

## Fixture provenance (honest record)

- **No upstream-produced bytes or server output are read by the suite.**
  Every wire fixture (`tests/suite_codec.xi`) and every scripted server
  reply (`tests/suite_net.xi`) is a hand-written byte string composed
  directly from the specification's grammar; expectations are the declared
  encodings (lengths, CRLF placement, marker bytes, ordering), not any
  tool's output.
- All error paths are exercised with deliberately malformed fixtures: the
  nine `RESP_ERR_*` codes each have at least one suite assertion, and the
  client taxonomy (connect / protocol / timeout / server / closed / type)
  is exercised over real loopback TCP by the scripted server.
- The two **live** checks against `127.0.0.1:6379` ran the protocol against
  a real server only if one was reachable at verification time. In this
  build environment no Redis server was reachable (verified independently),
  so the live checks recorded the explicit `SKIP -- no live Redis at
  127.0.0.1:6379` state; a live run is a future verification step, not a
  claim made here.
- The scratch probes used during development (transport characterization,
  connect-refusal characterization) were deleted after the finding was
  recorded; their evidence is summarized in `AUDIT.md`.

## Tooling note

Developed against the pinned toolchain resolved by `scripts/port.ps1`
(XIOM v0.64.4 pin, runs recorded on the installed v0.64.4/v0.64.5) with
stdlib `E:\xiom-lang\stdlib`, as a read-only consumer of `xiom.net.socket`.
The toolchain issues that shaped the style (no `?` propagation, no
`Result[Option[T]]`, relative-path module-resolution quirk, the Windows
`socket_connect` refusal misreport) are restated in `SPEC.md` section 8
and `AUDIT.md`. The package contains no FFI, so the B-20/B-25 FFI rules
are satisfied by construction.
