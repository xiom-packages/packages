# SPEC: xiom.sqlite -- SQLite C API bindings (vendored amalgamation)

## 1. Identity

| Field | Value |
|-------|-------|
| Package | `xiom.sqlite` |
| Version | 0.4.0 |
| Kind | binding (`keywords: ["binding"]`) |
| Upstream project | SQLite -- https://sqlite.org/ |
| Upstream version | **3.53.4** (amalgamation build 3530400; `libversion_number` = 3053004) |
| Upstream license | Public domain (blessing text in `vendor/LICENSE`) |
| Package license | MIT OR Apache-2.0 (everything outside `vendor/`) |
| Platform | Windows x64 (primary); no platform-specific XIOM code |
| Compiler pin | xiom v0.64.4 |

## 2. Vendored path (G2 pin)

The SQLite amalgamation is vendored **unmodified** into `vendor/`. It is
compiled into each test binary with `xiom --c-source <abs path to
vendor/sqlite3.c>`; there is no soname, no system-installed library, and no
runtime DLL dependency. `shell.c` from the upstream zip is intentionally not
vendored (CLI only, not needed by the library API).

### Pinned files (SHA256)

| File | Bytes | SHA256 |
|------|-------|--------|
| `vendor/sqlite3.c` | 9,515,341 | `B1DD5D74EC7F29055A6684FA06FB3C2F6821C87DD38F9A458DFD2E8A1DB28189` |
| `vendor/sqlite3.h` | 690,838 | `919E7F2E8ED1D8F56AC17B412B8971C76AA5D1A879752CC6058F75E7D5910E1D` |
| `vendor/sqlite3ext.h` | 39,175 | `AC9645E5C9FF0CF176EFDD6E75CB5E98F46295D38E02DB5C4D208826A39AB4BE` |

### Source archive provenance

| Artifact | Value |
|----------|-------|
| Download | https://sqlite.org/2026/sqlite-amalgamation-3530400.zip |
| Size | 2,946,650 bytes |
| SHA256 (computed at vendor time) | `1E71DDF93849C6A6ECF58B827C0692073D2DD7EE40196158068F7B29F422E87D` |
| SHA3-256 (published by upstream, verified locally with `certutil`) | `628a44cfe82c66aed1ccbbe85a562d2e33ebe64b3288981ed76285612227934e` |

### Re-pin procedure

1. Download the new official amalgamation zip from sqlite.org and record its
   published SHA3-256.
2. Verify the hash (`certutil -hashfile <zip> SHA3-256`) before extracting.
3. Replace `vendor/sqlite3.c`, `vendor/sqlite3.h`, `vendor/sqlite3ext.h`
   byte-for-byte; do not edit vendored files.
4. Recompute and update the SHA256 table above and the version rows in this
   SPEC, `README.md`, and `AUDIT.md` in the same commit.
5. Run the conformance suite x2 (`--c-source` path) and update `STATUS.json`;
   version tests assert `libversion()` / `libversion_number()` against the pin.

## 3. Module layout and safe boundary (G5)

| Module | File | Role |
|--------|------|------|
| `xiom.sqlite` | `src/sqlite.xi` | Package entry. Public API facade; **no unsafe**; delegates to `xiom.sqlite.ffi` |
| `xiom.sqlite.ffi` | `src/ffi.xi` | **The only module with `unsafe` and `extern "C"`.** All foreign calls and pointer/memory handling confined here; exposes typed safe wrappers |
| `xiom.sqlite.types` | `src/types.xi` | Value/row/result/error types (+ `RowOutcome`); pure |
| `xiom.sqlite.rows` | `src/rows.xi` | Materializes statements into owned values (`query_all`, `count_rows`, `query_one`, by-name access); pure |
| `xiom.sqlite.query` | `src/query.xi` | SQL query builder; pure |
| `xiom.sqlite.schema` | `src/schema.xi` | DDL builder; pure |
| `xiom.sqlite.migration` | `src/migration.xi` | Migration manager over a live handle; pure |
| `xiom.sqlite.driver` | `src/driver.xi` | SQL driver facade for consumers (DSN, execute/query, transactions, caps); pure |

Handle model: connections and statements are opaque `Int` addresses owned by
the caller; `close`/`finalize` release them. No implicit frees. A statement
must be finalized before its connection is closed.

Call convention: call the facade with its module prefix (`sqlite.open(...)`)
or call `ffi.*` directly. Unqualified `open`/`close` resolve to `xiom.io`'s
same-named functions in a consumer catalog (stdlib collision, compiler
v0.64.0) -- always qualify.

Error mapping: fallible calls return `Result[T, SqliteError]` where
`SqliteError.code` is a SQLite primary result code and `.message` is the
connection's `sqlite3_errmsg` text (or a synthesized diagnostic when no
connection exists). `error_name(code)` maps codes to stable identifiers;
`SQLITE_*` constants are exported from the facade and the FFI module with
literal values.

### 3.1 Driver module (0.4.0 -- PULSE SQL driver contract)

`src/driver.xi` implements the consumer contract in
`docs/requirements/pulse-sql-driver.md` (option A): a pure-XIOM facade over
the FFI surface. No `unsafe`, no externs -- all foreign calls stay in
`xiom.sqlite.ffi`.

API (`SqlDriver`):

| Call | Contract |
|------|----------|
| `SqlDsn.parse(dsn)` | DSN grammar below; fails closed on unknown options / malformed values |
| `SqlDriver.open_from_dsn(dsn)` | open + apply `busy_timeout` / `journal_mode`; closes the handle on any failure |
| `SqlDriver.execute(sql)` | non-query (result rows discarded); Ok = rows affected + last insert rowid |
| `SqlDriver.query(sql)` | `SqliteResult` (typed values by index; column names for by-name access) |
| `SqlDriver.query_one(sql)` | flat `RowOutcome { has_row, row }` -- first row or empty |
| `SqlDriver.transaction_begin/commit/rollback` | explicit transaction control |
| `SqlDriver.in_transaction()` | true while an explicit transaction is open (`sqlite3_get_autocommit`) |
| `SqlDriver.last_error()` | `{code, message}` of the connection's most recent error |
| `SqlDriver.caps()` / `.transactional_ddl()` | capability flags (DDL is transactional; `:memory:` supported) |
| `SqlDriver.close()` | release the connection |

DSN grammar: `[sqlite:|sqlite3:|sqlite://]PATH[?opt=val[&opt=val]...]` with
`busy_timeout=<ms>` (default 5000; 0 disables the busy handler) and
`journal_mode=delete|truncate|persist|memory|wal|off`. Unknown options and
malformed values return `SQLITE_ERROR` with a printable description.
`journal_mode` is read back after open (`PRAGMA journal_mode;`), so
`SqlDriver.journal_mode` / `caps().journal_mode` report what is actually in
effect (SQLite may ignore WAL for `:memory:`, for example).

Transaction discipline (runner-side): begin; on the FIRST `Err` call
`transaction_rollback` and report the ORIGINAL error; otherwise `commit`.
The driver owns no migrations policy (locks, batches, ordering and the
backup fence are the runner's).  The `-- no-transaction` escape is runner
policy: sqlite reports `transactional_ddl == true`.

`query_one` returns a flat `RowOutcome` instead of
`Result[Option[SqliteRow]]` deliberately: the nested payload corrupts
struct-with-Vec values on the current pin (finding B-26; repro
`docs/repro/bindings-pilot/nested-payload/`). Restore the nested shape only
after the compiler fix, re-tested from that bundle.

## 4. Test contract

Suite: `tests/test_conformance.xi` (21 checks: version pin, connection
lifecycle, exec, prepared statements + binding, error codes, transactions,
typed rows, datatypes, wide values, handle reuse, query builder, schema
builder, migration manager, file persistence, errmsg freshness -- plus five
driver checks: DSN parse cases; `:memory:` round trip + capability flags;
transactions (commit/rollback visible state + `in_transaction`);
rollback-on-error + error mapping via `last_error`; file DSN options +
reopen persistence/defaults).

Command (cwd = this package directory):

```
xiom --run tests/test_conformance.xi --c-source <abs path>\vendor\sqlite3.c
```

`--c-source` requires an **absolute** path (the compiler runs clang from a
scratch directory). The bindings-lane runner hook resolves the package-relative
`vendor/sqlite3.c` for CI; see the relay block in `BINDINGS-SESSION.md`.

Watchdog: allow >= 180 s for this suite -- clang compiles the 9.5 MB
amalgamation at link time (observed 22-31 s total on the development machine;
first runs ~50 s).

## 5. Compiler findings pinned by this package (v0.64.0)

History: 0.2.0 was shaped around these v0.64.0 findings; fixed items are
restored, everything else stays avoided. Documented in
`docs/COMPILER-FINDINGS.md` (native lane) and
`docs/BINDINGS-COMPILER-FINDINGS.md` (lane detail):

1. **Enum payload reads were nondeterministically miscompiled across builds
   (B-01; same class as the `xiom.graphql` finding).** FIXED on v0.64.2
   (m231): the lane's repro produced 6/6 stable rebuilds and the native
   matrix 3/3. 0.3.0 **restores the original model** -- `SqliteValue` wraps
   `SqliteValueKind`, a user enum with payloads; accessors are match-based.
   The 0.2.0 tagged struct was the workaround and has been retired.
   Constructors and accessors are unchanged for callers; the obsolete
   `VALUE_*` kind constants were removed with the struct. 0.3.0 validation:
   16/16 across 6 fresh build cycles plus the pin matrix x1 (v0.64.2,
   2026-10-09).
2. **Const references inside confined `unsafe` blocks / large const chains
   can recurse the resolver** (`compiler stack overflow`, exit 0xC00000FD).
   `src/ffi.xi` uses numeric literals inside its confined functions and a
   literal-based `error_name`; the public consts remain the API.
3. **Cross-module const aliases recurse** (`pub const A = other.B`).
   Facade consts are literal values.
4. **Child modules cannot import their parent.** `xiom.sqlite.ffi` is a
   sibling of `rows`/`migration`; only the parent imports the children.
5. **Calling `xiom.ffi.alloc` inside a confined block and freeing through
   `xiom.ffi.free` spins the guard heap** (allocator mismatch). The FFI
   module avoids malloc/free entirely; C out-params use an XIOM-owned
   `Vec[UInt8]` slot.
6. **A module exporting an associated fn named `up`/`down` crashes the
   compiler when `xiom.test` is in the catalog.** Migration methods are
   `migrate_up`/`migrate_down`.
7. **Nested enum payloads (`Result[Option[T]]`) corrupt struct-with-Vec
   payloads** (B-26; found 2026-10-13 while building the 0.4.0 driver).
   Extracting the struct from the nested payload leaves its `Vec` length
   reading as a pointer-like value; using the value crashes (0xC0000005).
   Flat struct payloads and single-level `Option` extraction are correct.
   Workaround shipped: `query_one` returns the flat `RowOutcome`; repro
   `docs/repro/bindings-pilot/nested-payload/` (re-test after the compiler
   fix).
