# xiom.sqlite -- Roadmap

**Version**: v0.5.0 | **Compiler**: xiom v0.64.7 | **Last updated**: 2026-10-18

## Current state

| Criterion | Status |
|-----------|--------|
| Vendored amalgamation | Done -- SQLite 3.53.4, SHA256-pinned (`SPEC.md` §2) |
| FFI core | Done -- all unsafe confined to `src/ffi.xi` (G5) |
| Conformance suite | Done -- 21 checks, green x2 on v0.64.7 (2026-10-18) |
| Typed safe API | Done -- `Result[_, SqliteError]`, codes + messages |
| Query/schema/migration helpers | Done -- pure XIOM |
| **SQL driver (0.4.0; `query_one` restored 0.5.0)** | **Done -- `xiom.sqlite.driver`: DSN parse/open, execute/query/`query_one -> Result[Option[SqliteRow]]`, explicit transactions + `in_transaction`, capability flags, `last_error` (PULSE contract, `docs/requirements/pulse-sql-driver.md`) |
| Publish allowlist | Live -- published since `eco-v0.1.89`; 0.3.0 in `eco-v0.1.122`; 0.4.1 live; 0.5.0 restore requested (2026-10-18) |

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

## Driver follow-ons (0.4.0 lineage; query_one restored 0.5.0)

- ~~Restore `Result[Option[SqliteRow]]` for `query_one`~~ DONE in 0.5.0:
  B-26 is re-verified fixed on v0.64.7 (bundle
  `docs/repro/bindings-pilot/nested-payload/`, failures=0, all shapes
  len=2). Read the result with `is_some` / `value`; the in-situ `match`
  lowering residual is compiler-side B-32.
- Non-sqlite engines (option B from the requirements): extract a shared
  facade only when a second engine class (e.g. postgres) is targeted.
- Prepared-statement binding through the driver (today binds live on
  `xiom.sqlite` handles obtained via `SqlDriver.db()`).
