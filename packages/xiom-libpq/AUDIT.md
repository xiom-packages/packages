# AUDIT: xiom.libpq

## Status (2026-10-08/09)

Dynamic-loader implementation at 0.2.0. The pre-pilot module declared 17
static `extern "C"` libpq functions with stub wrappers ("Real C bridge will
be linked after xiom.ffi matures") and required a link-time libpq; it is
preserved in git history only as reference.

| Item | State |
|------|-------|
| Compiler | xiom v0.64.1 |
| Pin | soname + 13-entry-point set + constants + local DLL samples (`SPEC.md` §2) |
| Link model | none at build time; runtime `xiom.ffi.dl`; no headers, nothing vendored |
| FFI confinement | all `unsafe` in the root module `libpq.xi` (G5) |
| Suite | `tests/test_conformance.xi` |
| Runs | absent: **PASS 2/2 x2** (SKIP path); present (libpq 13.11): **PASS 4/4 x2** (version 130011, `CONNECTION_BAD`, `timeout expired`) |

## Design notes

- **No server needed**: `PQlibVersion` is connection-free and the connect
  probe targets a closed port, so the present-path suite exercises real
  `PQconnectdb`/`PQstatus`/`PQerrorMessage`/`PQfinish` behaviour with
  deterministic assertions.
- Present-path proof used the x64 libpq shipped with DaVinci Resolve 13.11
  (prepended to PATH for the run; not committed). A second local sample
  (Reallusion, 10.7) exists but its bitness is unverified.
- Bridge locals use the `f_` prefix per compiler finding B-10.
- No `port.args.json`: pure-XIOM loader.

## Known limitations

- Query execution and result-set access (`PQexec`, `PQntuples`, `PQfname`,
  `PQgetvalue`, `PQgetisnull`, `PQclear` are already resolved) are not yet
  wrapped/tested against a live server -- Phase 2.
- Parameterized queries (`PQexecParams`) and async (`PQsendQuery`) are not
  resolved yet.
- Windows soname only; POSIX `libpq.so.5` fallback is a Phase 2 item.
- Connection strings are passed through verbatim; no builder/validation yet.
