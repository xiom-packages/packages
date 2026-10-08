# SPEC: xiom.sqlite -- SQLite C API bindings (vendored amalgamation)

## 1. Identity

| Field | Value |
|-------|-------|
| Package | `xiom.sqlite` |
| Version | 0.2.0 |
| Kind | binding (`keywords: ["binding"]`) |
| Upstream project | SQLite -- https://sqlite.org/ |
| Upstream version | **3.53.4** (amalgamation build 3530400; `libversion_number` = 3053004) |
| Upstream license | Public domain (blessing text in `vendor/LICENSE`) |
| Package license | MIT OR Apache-2.0 (everything outside `vendor/`) |
| Platform | Windows x64 (primary); no platform-specific XIOM code |
| Compiler pin | xiom v0.64.0 |

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
| `xiom.sqlite.types` | `src/types.xi` | Value/row/result/error types; pure |
| `xiom.sqlite.rows` | `src/rows.xi` | Materializes statements into owned values; pure |
| `xiom.sqlite.query` | `src/query.xi` | SQL query builder; pure |
| `xiom.sqlite.schema` | `src/schema.xi` | DDL builder; pure |
| `xiom.sqlite.migration` | `src/migration.xi` | Migration manager over a live handle; pure |

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

## 4. Test contract

Suite: `tests/test_conformance.xi` (16 checks: version pin, connection
lifecycle, exec, prepared statements + binding, error codes, transactions,
typed rows, datatypes, wide values, handle reuse, query builder, schema
builder, migration manager, file persistence, errmsg freshness).

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

These are documented in `docs/COMPILER-FINDINGS.md` by the native lane; the
package is shaped to avoid them:

1. **Enum payload reads are nondeterministically miscompiled across builds.**
   A user enum with payloads (`Integer(Int)`, `Text(Str)`, ...) produced
   build-to-build flaky accessor results (11/16 vs 16/16 passes across
   rebuilds of the identical source). `SqliteValue` therefore uses a tagged
   struct with plain fields (see `src/types.xi`). This mirrors the existing
   `xiom.graphql` enum-payload finding.
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
