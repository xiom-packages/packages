# AUDIT: xiom.sqlite

## Status (2026-10-18)

Real vendored implementation -- the previous "FFI bridge not linked" stubs are
gone (`src/connection.xi` and `src/demo.xi` deleted). The package compiles and
its conformance suite is green on the pinned compiler.

| Item | State |
|------|-------|
| Compiler | xiom v0.64.7 |
| Upstream | SQLite 3.53.4 amalgamation, vendored (public domain) |
| Link model | `--c-source vendor/sqlite3.c` (static, no soname) |
| FFI confinement | all `unsafe`/`extern` in `src/ffi.xi` only |
| Suite | `tests/test_conformance.xi`, 21 checks |
| Runs | **21/21 PASS x2 on v0.64.7 (2026-10-18, 0.5.0 nested `query_one` restore)**; 21/21 PASS x2 on v0.64.4 (2026-10-13, 0.4.0 driver wave); 16/16 PASS x6 consecutive build+run cycles + pin matrix x1 with the restored enum model (v0.64.2, 2026-10-09) |

## Provenance

- Download: https://sqlite.org/2026/sqlite-amalgamation-3530400.zip (2,946,650 B)
- Zip SHA3-256 verified against the upstream publication:
  `628a44cf...27934e`
- `sqlite3.c` SHA256 `B1DD5D74...DB28189`; `sqlite3.h` SHA256
  `919E7F2E...5910E1D`; `sqlite3ext.h` SHA256 `AC9645E5...39AB4BE`.
  Full table + re-pin procedure: `SPEC.md` §2.

## Design notes

- `SqliteValue` wraps `SqliteValueKind`, a user enum with payloads: the
  0.2.0 tagged-struct workaround is retired (B-01 fixed on v0.64.2/m231;
  6/6 stable rebuilds). Constructors/accessors unchanged; see `SPEC.md` §5.
- C out-params (`sqlite3_open`, `sqlite3_prepare_v2`) write into an
  XIOM-owned 8-byte `Vec[UInt8]` slot; the FFI module does not call
  malloc/free (guard-heap allocator mismatch on this pin).
- `src/ffi.xi` uses numeric literals inside confined functions and in
  `error_name`; the exported `SQLITE_*` consts are literal values. Both avoid
  the const-resolution recursion on this pin.
- 0.4.0 adds `xiom.sqlite.driver` (PULSE contract): DSN parse/open,
  execute/query/query_one, explicit transactions with `in_transaction`, and
  capability flags. 0.5.0 restores `query_one -> Result[Option[SqliteRow]]`
  after B-26 was re-verified fixed on v0.64.7 (bundle
  `docs/repro/bindings-pilot/nested-payload/`, failures=0, all shapes len=2);
  the public `RowOutcome` workaround is gone. The first-row hand-off helper
  is private; the suite reads the result via `is_some` / `value` because the
  in-situ `match` lowering residual is compiler-side B-32.

## Known limitations

- BLOB values are constructible (`SqliteValueKind.Blob`) but `column_blob`/
  `bind_blob` are Phase 2 (see ROADMAP.md).
- `xiom.sqlite.query` WHERE helpers build literal SQL (parameter binding is
  available through prepared statements; the builder is convenience-only and
  not injection-safe for untrusted input).
- File-backed tests leave gitignored `sqlite_conformance_tmp.db` /
  `sqlite_driver_tmp.db` in the package working directory.
