# AUDIT: xiom.odbc

## Status (2026-10-08)

First implementation at 0.2.0 (the package was a manifest-less placeholder
with a README; `namespace-check -Module xiom.odbc` run before activation:
OK, 0 conflicts).

| Item | State |
|------|-------|
| Compiler | xiom v0.64.1 |
| Pin | soname + entry-point set + ODBC constants + System32 DLL sample (`SPEC.md` §2) |
| Link model | none at build time; runtime `xiom.ffi.dl`; no headers, no vendored code |
| FFI confinement | all `unsafe` in the root module `xiom.odbc` (G5) |
| Suite | `tests/test_conformance.xi` |
| Runs | **PASS 5/5 x2** via `scripts/port.ps1`: manager `03.80.0000`, 7 drivers, 3 DSNs; deterministic SKIP classification per run |

## Design notes

- **Compiler finding B-10** (new, from this package): a local fn-pointer
  variable named `alloc` inside a confined block gets its calls rewritten to
  the guard allocator -- `SQLAllocHandle` appeared to succeed while the
  out-param stayed zero. Renaming to `f_alloc` fixed it instantly; all bridge
  locals now use the `f_` prefix. Documented in
  `docs/BINDINGS-COMPILER-FINDINGS.md`.
- The C reference probe (compiled outside XIOM) showed the API call was
  correct all along (`SQLAllocHandle` -> handle, `SQLDrivers` -> "SQL
  Server"), which localized the bug to the XIOM call path.
- Driver enumeration runs on the environment handle; `SQLDataSources` and
  `SQLDrivers` are scanned with a 64/256 cap to bound misbehaving managers.
- Out-params use XIOM-owned slots; no malloc/free in confined blocks (B-05).

## Known limitations

- Connection handling (`SQLConnect`/`SQLDriverConnect`), statement
  execution, diagnostics (`SQLGetDiagRec`) and async are Phase 2; they need
  a reachable data source for meaningful tests.
- Wide (UTF-16) APIs (`SQLDriverConnectW`, ...) are not exposed yet.
- Windows-only soname; a POSIX `libodbc.so.2` fallback is a Phase 2 item when
  a Linux CI target exists.
