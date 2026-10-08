# AUDIT: xiom.sqlite

## Status (2026-10-08)

Real vendored implementation -- the previous "FFI bridge not linked" stubs are
gone (`src/connection.xi` and `src/demo.xi` deleted). The package compiles and
its conformance suite is green on the pinned compiler.

| Item | State |
|------|-------|
| Compiler | xiom v0.64.0 |
| Upstream | SQLite 3.53.4 amalgamation, vendored (public domain) |
| Link model | `--c-source vendor/sqlite3.c` (static, no soname) |
| FFI confinement | all `unsafe`/`extern` in `src/ffi.xi` only |
| Suite | `tests/test_conformance.xi`, 16 checks |
| Runs | 16/16 PASS x6 consecutive build+run cycles (default flags, 2026-10-08) |

## Provenance

- Download: https://sqlite.org/2026/sqlite-amalgamation-3530400.zip (2,946,650 B)
- Zip SHA3-256 verified against the upstream publication:
  `628a44cf...27934e`
- `sqlite3.c` SHA256 `B1DD5D74...DB28189`; `sqlite3.h` SHA256
  `919E7F2E...5910E1D`; `sqlite3ext.h` SHA256 `AC9645E5...39AB4BE`.
  Full table + re-pin procedure: `SPEC.md` §2.

## Design notes

- `SqliteValue` is a tagged struct (kind + payload fields), not an enum:
  enum payload reads are nondeterministically miscompiled on v0.64.0
  (build-to-build flakiness observed in this package; same class as the
  `xiom.graphql` finding). See `SPEC.md` §5.
- C out-params (`sqlite3_open`, `sqlite3_prepare_v2`) write into an
  XIOM-owned 8-byte `Vec[UInt8]` slot; the FFI module does not call
  malloc/free (guard-heap allocator mismatch on this pin).
- `src/ffi.xi` uses numeric literals inside confined functions and in
  `error_name`; the exported `SQLITE_*` consts are literal values. Both avoid
  the const-resolution recursion on this pin.

## Known limitations

- BLOB values are surfaced as `SqliteValueKind` kind 4 only by tagging;
  `column_blob`/`bind_blob` are Phase 2 (see ROADMAP.md).
- `xiom.sqlite.query` WHERE helpers build literal SQL (parameter binding is
  available through prepared statements; the builder is convenience-only and
  not injection-safe for untrusted input).
- File-backed tests leave a gitignored `sqlite_conformance_tmp.db` in the
  package working directory.
