# SPEC: xiom.libpq -- PostgreSQL client library bindings (dynamic loader)

## 1. Identity

| Field | Value |
|-------|-------|
| Package | `xiom.libpq` |
| Version | 0.2.0 |
| Kind | binding (`keywords: ["binding"]`) |
| Upstream project | PostgreSQL (libpq) -- https://www.postgresql.org/ |
| Upstream license | PostgreSQL License (permissive); nothing vendored -- constants declared locally |
| Package license | MIT OR Apache-2.0 |
| Platform | Windows x64 (soname `libpq.dll`) |
| Compiler pin | v0.64.1 |

## 2. G2 pin: soname + entry-point set + constants

**Soname (runtime contract):** `libpq.dll`. Resolved at runtime via
`xiom.ffi.dl` (`LoadLibraryA`/`GetProcAddress`); no import library, no
headers, nothing vendored.

**Resolved entry points** (13): `PQlibVersion`, `PQconnectdb`, `PQstatus`,
`PQerrorMessage`, `PQfinish`, `PQexec`, `PQresultStatus`, `PQntuples`,
`PQnfields`, `PQfname`, `PQgetvalue`, `PQgetisnull`, `PQclear`.

**Constants pinned** (declared locally from libpq): `CONNECTION_OK=0`,
`CONNECTION_BAD=1`, `PGRES_EMPTY_QUERY=0`, `PGRES_COMMAND_OK=1`,
`PGRES_TUPLES_OK=2`.

**Local runtime samples used for positive-path proof (NOT the pin):**

| Artifact | Value |
|----------|-------|
| `Blackmagic Design\DaVinci Resolve\libpq.dll` (used for the recorded present-path runs) | 307,712 bytes, FileVersion 13.11 (x64), SHA256 `B43D05F89AC004934D8771F21D8BB0F3C80CD5C183221DFA6CB58BAFCE9F621E` |
| `Common Files\Reallusion\PostgreSQL\bin\libpq.dll` (secondary sample; bitness unverified) | 281,600 bytes, FileVersion 10.7, SHA256 `7D4A589E45ED04756DE72C8A94932EC94F88B9874E0AE9234AA88467255C002E` |
| Runtime report | `PQlibVersion` = `130011` (13.11); closed-port connect -> `CONNECTION_BAD` with error text `timeout expired` |

### Re-pin procedure

1. Re-verify the entry-point names/constants against the libpq ABI before
   touching the module.
2. Update the sample table and version rows in `README.md`/`AUDIT.md` in one
   commit.
3. Re-run `scripts/port.ps1 -Package xiom.libpq` in both configurations
   (library absent -> SKIP; library on PATH -> probe) and record the matrix.

## 3. Design and safe boundary (G5)

`libpq.xi` is the only module with `unsafe`: a `PqLibrary` loader struct plus
fn-pointer-cast wrappers (`pq_libversion`, `pq_connect_report`, `pq_probe`,
`pq_probe_default`, `pq_load(_named)`, `pq_close`).  The pilot needs **no
server**: `PQlibVersion` is connection-free, and the connect probe targets a
closed local port (`host=127.0.0.1 port=1 connect_timeout=2`) so the suite
exercises the real `PQconnectdb`/`PQstatus`/`PQerrorMessage`/`PQfinish`
paths and asserts `CONNECTION_BAD` + a non-empty error message.

Bridge-locals use the `f_` prefix (compiler finding B-10: an `alloc`-named
local fn-pointer is silently redirected to the guard allocator in confined
blocks).

## 4. Test matrix (recorded 2026-10-08/09, compiler v0.64.1)

| Configuration | Command | Result |
|---------------|---------|--------|
| libpq absent (CI shape; default PATH) | `scripts/port.ps1 -Package xiom.libpq` | **PASS 2/2 x2** -- deterministic SKIP classification (bogus soname) + `probe: SKIP` (code 126) |
| libpq present (DaVinci `libpq.dll` 13.11 prepended to PATH) | same | **PASS 4/4 x2** -- `PQlibVersion` 130011, closed port -> `CONNECTION_BAD`, error text `timeout expired` |
| Server-backed queries | Phase 2 (needs a running PostgreSQL instance) | not exercised |

## 5. Scope

Pilot: client-library identification and the connect/status/error path.
Successful connections, `PQexec` result sets and parameter arrays are Phase 2
(`ROADMAP.md`). The pre-pilot module declared static externs with stub
wrappers and is preserved in git history.
