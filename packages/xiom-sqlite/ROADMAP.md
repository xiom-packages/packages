# xiom.sqlite -- Roadmap

**Version**: v0.4.0 | **Compiler**: xiom v0.64.4 | **Last updated**: 2026-10-13

## Current state

| Criterion | Status |
|-----------|--------|
| Vendored amalgamation | Done -- SQLite 3.53.4, SHA256-pinned (`SPEC.md` §2) |
| FFI core | Done -- all unsafe confined to `src/ffi.xi` (G5) |
| Conformance suite | Done -- 21 checks, green x2 on v0.64.4 (2026-10-13) |
| Typed safe API | Done -- `Result[_, SqliteError]`, codes + messages |
| Query/schema/migration helpers | Done -- pure XIOM |
| **SQL driver (0.4.0)** | **Done -- `xiom.sqlite.driver`: DSN parse/open, execute/query/query_one, explicit transactions + `in_transaction`, capability flags, `last_error` (PULSE contract, `docs/requirements/pulse-sql-driver.md`) |
| Publish allowlist | Live -- published since `eco-v0.1.89`; 0.3.0 in `eco-v0.1.122`; 0.4.0 publish requested (2026-10-13) |

## Phase 2 (next touch)

1. BLOB round-trip: `column_blob` + `bind_blob` with an owned-bytes API.
2. Parameter binding in `xiom.sqlite.query` (`?` placeholders instead of
   literal concatenation) so the builder is safe for untrusted input.
3. `open_v2` flags (readonly, create) exposure -- `busy_timeout` is DONE in
   0.4.0 via the driver DSN.
4. ~~Transaction helper object (BEGIN/COMMIT/ROLLBACK with error
   recovery).~~ DONE in 0.4.0 (`SqlDriver.transaction_begin/commit/rollback`
   + `in_transaction`; rollback-on-error discipline documented).
5. Compiler v0.64.1+ re-test: restore enum-payload `SqliteValue` if the
   upstream enum fix lands (see `SPEC.md` §5 finding 1); the 0.3.0 restore
   is verified on v0.64.2+ and rides the current pin.
6. Multi-statement tail execution API (`sqlite3_prepare_v3` tail pointer).

## Driver follow-ons (0.4.0 lineage)

- Restore `Result[Option[SqliteRow]]` for `query_one` when the nested-payload
  fix ships (B-26; re-test from `docs/repro/bindings-pilot/nested-payload/`).
- Non-sqlite engines (option B from the requirements): extract a shared
  facade only when a second engine class (e.g. postgres) is targeted.
- Prepared-statement binding through the driver (today binds live on
  `xiom.sqlite` handles obtained via `SqlDriver.db()`).
