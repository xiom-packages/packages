# PROVENANCE -- xiom.sqlite

Owner policy: docs/UPSTREAM-FIRST.md (upstream-first, 100% coverage).

- **Upstream project:** SQLite -- https://sqlite.org/ (public domain; the
  blessing text is vendored unmodified at `vendor/LICENSE`).
- **Vendored artifact (G2 pin):** the official amalgamation zip
  `sqlite-amalgamation-3530400.zip` (SQLite **3.53.4**, build 3530400),
  from https://sqlite.org/2026/sqlite-amalgamation-3530400.zip (2,946,650
  bytes; SHA256
  `1E71DDF93849C6A6ECF58B827C0692073D2DD7EE40196158068F7B29F422E87D`;
  upstream-published SHA3-256
  `628a44cfe82c66aed1ccbbe85a562d2e33ebe64b3288981ed76285612227934e`
  verified locally with `certutil`).
- **Vendored files (byte-for-byte, unmodified):**

  | File | Bytes | SHA256 |
  |------|-------|--------|
  | `vendor/sqlite3.c` | 9,515,341 | `B1DD5D74EC7F29055A6684FA06FB3C2F6821C87DD38F9A458DFD2E8A1DB28189` |
  | `vendor/sqlite3.h` | 690,838 | `919E7F2E8ED1D8F56AC17B412B8971C76AA5D1A879752CC6058F75E7D5910E1D` |
  | `vendor/sqlite3ext.h` | 39,175 | `AC9645E5C9FF0CF176EFDD6E75CB5E98F46295D38E02DB5C4D208826A39AB4BE` |

  `shell.c` from the upstream zip is intentionally not vendored (CLI only,
  not needed by the library API).  Re-pin procedure: `SPEC.md` sec. 2.
- **Declaration oracle:** `vendor/sqlite3.h` (the pinned amalgamation
  header) -- every extern signature and result-code constant bound by the
  package comes from it, not from memory.
- **Source study clone:** `E:\repos\sqlite` (sqlite.org source, public
  domain; registered in `E:\repos\CLEANUP.md`, review-after 2026-12-01).
- **Derived vs independent:** the vendored amalgamation is **upstream code**
  (compiled unmodified into the test binary); the XIOM side (`src/ffi.xi`,
  `src/types.xi`, `src/rows.xi`, `src/driver.xi`, `src/query.xi`,
  `src/schema.xi`, `src/migration.xi`, `src/sqlite.xi`) is **independent**
  -- written against the public SQLite C API documentation and the pinned
  header.  No upstream code was copied into the XIOM modules.
- **Declared surface (100% bound):** the package binds **25** C functions;
  24 have public safe wrappers in `src/ffi.xi` and `sqlite3_db_handle` is
  internal to `step`'s error path (0 skips):

  `sqlite3_libversion`, `sqlite3_libversion_number`, `sqlite3_open`,
  `sqlite3_close`, `sqlite3_errmsg`, `sqlite3_errcode`,
  `sqlite3_extended_errcode`, `sqlite3_get_autocommit`, `sqlite3_exec`,
  `sqlite3_prepare_v2`, `sqlite3_step`, `sqlite3_finalize`,
  `sqlite3_db_handle`, `sqlite3_bind_int64`, `sqlite3_bind_double`,
  `sqlite3_bind_text`, `sqlite3_bind_null`, `sqlite3_column_type`,
  `sqlite3_column_int64`, `sqlite3_column_double`, `sqlite3_column_text`,
  `sqlite3_column_count`, `sqlite3_column_name`, `sqlite3_changes`,
  `sqlite3_last_insert_rowid`.

  This is a declared binding subset of the C API by design (the full C API
  is out of the declared surface, not a coverage gap).  The 0.4.0 driver
  (`src/driver.xi`) adds no C surface -- pure XIOM over the same wrappers.
- **Link model:** static -- `--c-source vendor/sqlite3.c` at port time; no
  runtime DLL, no dl-load, no soname probe.
- **License:** `vendor/` is public domain (SQLite blessing); everything
  outside `vendor/` is MIT OR Apache-2.0.
- **Evidence:** `tests/test_conformance.xi` (21 checks, x2 green on
  v0.64.4, commit `4ba13167`); the version assertion
  (`libversion() == "3.53.4"`, `libversion_number() == 3053004`) pins the
  vendored artifact at run time.
