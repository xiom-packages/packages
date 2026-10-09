# Bindings-lane package wishlist (responses to PULSE / ORBITDB / XVECTOR)

The bindings lane answers the package-level asks filed by the project lanes.
Companions: `docs/BINDINGS-STDLIB-WISHLIST.md` (stdlib asks),
`docs/BINDINGS-COMPILER-FINDINGS.md` (compiler defects), `docs/BINDINGS-LANE.md`
(process). The project lanes file requests in their own wishlists; the
packages lane forwards them here and relays these answers back through
`BINDINGS-SESSION.md`.

## Sources (fetched 2026-10-09, v0.64.2-era)

| Lane | Source wishlist | Notes |
|------|-----------------|-------|
| PULSE (web) | `E:\xiom-projects\xiom-pulse\docs\PACKAGE-WISHLIST-PULSE.md` | "Bindings lane (added 2026-10-08)" heads-up section |
| ORBITDB (embedded DB) | `E:\xiom-projects\xiom-orbitdb\docs\PACKAGE-WISHLIST-ORBITDB.md` | pin v0.64.2; all workarounds dropped |
| XVECTOR (vector DB) | `E:\xiom-projects\xiom-xvector\docs\PACKAGE-WISHLIST-XVECTOR.md` | accelerator row on Watch |

Registry checks below were run live with `xiom pkg info` on 2026-10-09
(compiler v0.64.2 install).

## 1. PULSE -- binding-relevant asks

PULSE's asks are marked "heads-up; final-stage work"; its consumption
contract: each binding is wrapped in exactly one PULSE module behind a
stable PULSE API (route code never calls a binding directly).

| Ask | Bindings-lane answer | Status |
|-----|----------------------|--------|
| Durable database/KV client binding (SQLite/Postgres or similar) to back the event store and sessions beyond JSONL | **Available from the registry now**: `xiom.sqlite` 0.2.0 (signed; vendored SQLite 3.53.4 amalgamation, no external dependency; 0.3.0 enum restore pending batch 22), `xiom.libpq` 0.2.0 (signed; PostgreSQL client via `libpq.dll` at runtime, SKIP when absent) and `xiom.odbc` 0.2.0 (signed; ODBC driver manager, DSNs/drivers on the host, SKIP when absent). `xiom.sqlite` is the dependency-free embedded option | **SERVED** |
| Optional outbound HTTP client binding (webhooks/proxying) | Not needed from this lane: `xiom.http` 0.1.4 ships the real-libcurl path (native-verified GET/POST). Revisit only if a standalone client package is wanted | NO ACTION (not needed yet) |
| TLS as a binding | Acknowledged NOT a binding for PULSE (front proxy terminates TLS; app stays loopback plaintext). `xiom.openssl` 0.2.0 (signed; libcrypto dynamic loader) exists if that posture changes | ACK |
| Wrap-behind-one-module consumption contract | Acknowledged; matches the lane's design (typed safe facade, all `unsafe` confined to one module; SKIP-when-absent classification keeps CI green without the native library) | ACK |

**Consumer flow -- VERIFIED end-to-end 2026-10-09** (scratch `XIOM_HOME`,
compiler v0.64.2, registry installs checksum+signature-verified):
- `xiom.sqlite` 0.2.0 (vendored C): `xiom pkg install xiom.sqlite@0.2.0`,
  declare `"xiom.sqlite" = "0.2.0"` in `xiom.toml` `[dependencies]` (module
  resolves automatically, no `source-roots`), then build with the installed
  amalgamation:
  `xiom --run src/main.xi --c-source %XIOM_HOME%/packages/xiom-sqlite-<ver>/xiom-sqlite/vendor/sqlite3.c`
  -- a real consumer probe inserted and read a row back (PASS). WITHOUT the
  `--c-source`, the build fails with undefined `sqlite3_*` symbols: the
  installed package ships `port.args.json`, but consumer builds do not apply
  it (confirmed gap -- see the cross-lane note below).
- `xiom.libpq` 0.2.0 (pure XIOM): same install + `[dependencies]`, plain
  `xiom --run` -- no C step; consumer probe green (SKIP classification when
  no `libpq.dll` is on PATH). `xiom.odbc` shares that shape.

## 2. ORBITDB -- no bindings asks

ORBITDB states it **targets pure XIOM (no FFI) through Phase 2** and will
file here first if that changes (e.g. mmap). Nothing requested; no lane
work. The `xiom.wal` / `xiom.btree` extraction is the native lane's
(already in the tree, pending the ops allowlist append); the bindings lane
has no storage-format stake (recorded 2026-10-08).

## 3. XVECTOR -- accelerators stay GATED

XVECTOR keeps the accelerator row on **Watch** for the Phase 10 SIMD/kernel
path; its extraction gate for `xiom.vectors` is met, with owner greenlight
and porter scheduling outstanding (its 2026-10-09 wishlist).

| Ask | Bindings-lane answer | Status |
|-----|----------------------|--------|
| `xiom-blas` / `xiom-eigen` / `xiom-openblas` accelerators | **Pre-rostered incubating placeholders** in this worktree (stubs, tests `unknown`, no promised timeline -- verified 2026-10-09). When built they are **opt-in FFI accelerators that mirror the portable `xiom.vectors` contract, never define it** | **GATED** on the `xiom.vectors` freeze (XVECTOR extraction) |
| Pure-XIOM `xiom.simd`-class kernel package | This lane plans **none** -- native/stdlib territory; if one lands there, the FFI libs become accelerators behind it | ACK |
| `xiom.wal` name/scope coordination | No bindings-lane stake; native lane's call | ACK |

Pilot context (2026-10-09): the bindings program is complete through batch
22 -- window/input, GPU, compression, data/drivers, audio and crypto/media
(openssl system-lib; ffmpeg system-lib SKIP-only) are built and green on
v0.64.2. Accelerators remain the one unscheduled sector, behind the
`xiom.vectors` contract freeze.

## 4. Cross-lane integration note (for the packages/native lane)

- **Registry consumption of vendored-C bindings -- CONFIRMED GAP
  (2026-10-09, end-to-end tested)**: the dependency flow resolves the module
  but the consumer build does not apply the package's shipped
  `port.args.json`, so vendored-C packages (`xiom.sqlite`) need an explicit
  `--c-source <installed>/vendor/sqlite3.c` in the consumer build. Suggested
  fix (compiler/package lanes): apply a dependency's `port.args.json` build
  args when compiling a consumer, or expose a `xiom pkg` helper that prints
  them. Until then the README recipe is the workaround (satisfies PULSE's
  consumer-snippet convention).
- **fsync**: the ORBITDB/XVECTOR durable-store gates are the stdlib
  `fsync` row (filed in their own stdlib wishlists); not a bindings ask,
  noted for routing.

## Routing

- PULSE/ORBITDB/XVECTOR file asks in their own wishlists; the packages lane
  forwards them to the bindings lane; answers are recorded here and relayed
  back via `BINDINGS-SESSION.md`.
- Registry publication is the native lane's flow (wrapped batches); versions
  above were verified live on 2026-10-09.
