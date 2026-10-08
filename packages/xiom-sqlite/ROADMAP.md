# xiom.sqlite -- Roadmap

**Version**: v0.2.0 | **Compiler**: xiom v0.64.0 | **Last updated**: 2026-10-08

## Current state

| Criterion | Status |
|-----------|--------|
| Vendored amalgamation | Done -- SQLite 3.53.4, SHA256-pinned (`SPEC.md` §2) |
| FFI core | Done -- all unsafe confined to `src/ffi.xi` (G5) |
| Conformance suite | Done -- 16 checks, green x6 build cycles |
| Typed safe API | Done -- `Result[_, SqliteError]`, codes + messages |
| Query/schema/migration helpers | Done -- pure XIOM |
| Publish allowlist | Pending native lane (`xiom.sqlite` not yet allowlisted) |

## Phase 2 (next touch)

1. BLOB round-trip: `column_blob` + `bind_blob` with an owned-bytes API.
2. Parameter binding in `xiom.sqlite.query` (`?` placeholders instead of
   literal concatenation) so the builder is safe for untrusted input.
3. `busy_timeout` / `open_v2` flags (readonly, create) exposure.
4. Transaction helper object (BEGIN/COMMIT/ROLLBACK with error recovery).
5. Compiler v0.64.1+ re-test: restore enum-payload `SqliteValue` if the
   upstream enum fix lands (see `SPEC.md` §5 finding 1); the tagged struct is
   a portability workaround, not a design preference.
6. Multi-statement tail execution API (`sqlite3_prepare_v3` tail pointer).
