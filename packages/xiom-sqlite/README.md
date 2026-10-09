# xiom.sqlite

SQLite bindings for XIOM. The official SQLite 3.53.4 amalgamation is vendored
into `vendor/` (public domain) and compiled into the test binary with
`--c-source` -- no system library, no runtime DLL.

> **Status:** `incubating` -- conformance suite green on the pin (xiom
> v0.64.2, 16/16 across the 0.3.0 enum-model restore build cycles; published
> since `eco-v0.1.89`).
> **Lane:** bindings (`keywords: ["binding"]`).

## Quick start

```xiom
use xiom.io;
use xiom.sqlite;

fn main() {
  let o = sqlite.open(":memory:");
  if !o.is_ok { return; }
  let db: Int = o.value;
  let c = sqlite.exec(db, "CREATE TABLE t(id INTEGER PRIMARY KEY, name TEXT);");
  if !c.is_ok { return; }
  let i = sqlite.exec(db, "INSERT INTO t(name) VALUES ('hello');");
  if !i.is_ok { return; }
  let p = sqlite.prepare(db, "SELECT id, name FROM t;");
  if !p.is_ok { return; }
  let stmt: Int = p.value;
  let s = sqlite.step(stmt);
  if s.is_ok && s.value {
    io.println("row id=" + "? name=" + sqlite.column_text(stmt, 1));
  }
  let f = sqlite.finalize(stmt);
  let cl = sqlite.close(db);
}
```

Always qualify API calls with the module prefix (`sqlite.open`, not `open`):
unqualified `open`/`close` collide with `xiom.io` names in a consumer catalog
(stdlib collision).

## API surface

| Area | Functions |
|------|-----------|
| Version | `libversion`, `libversion_number` |
| Connection | `open`, `close`, `errcode`, `extended_errcode`, `errmsg`, `changes`, `last_insert_rowid` |
| Execution | `exec` |
| Statements | `prepare`, `bind_int64`, `bind_double`, `bind_text`, `bind_null`, `step`, `finalize` |
| Columns | `column_type`, `column_int64`, `column_double`, `column_text`, `column_count`, `column_name` |
| Errors | `error_name`, `SQLITE_*` constants |
| Results | `xiom.sqlite.rows.query_all`, `count_rows`; types in `xiom.sqlite.types` |
| Helpers | `xiom.sqlite.query`, `xiom.sqlite.schema`, `xiom.sqlite.migration` |

Full details: `SPEC.md`. Vendored binaries provenance + G2 pin: `SPEC.md` §2.

## Tests

From this directory (absolute `--c-source` path required):

```
xiom --run tests/test_conformance.xi --c-source <repo>\packages\xiom-sqlite\vendor\sqlite3.c
```

Expected: 16 `[PASS]`, exit 0. Allow ~3 minutes on a cold machine (clang
compiles the amalgamation at link time). The suite leaves
`sqlite_conformance_tmp.db` in the working directory (gitignored) for the
file-backed persistence check.
