# xiom.sqlite

SQLite bindings for XIOM. The official SQLite 3.53.4 amalgamation is vendored
into `vendor/` (public domain) and compiled into the test binary with
`--c-source` -- no system library, no runtime DLL.

> **Status:** `incubating` -- conformance suite green on the pin (xiom
> v0.64.4, **21/21 x2 on 2026-10-13** for 0.4.0; 16/16 across the 0.3.0
> enum-model restore build cycles on v0.64.2; published since `eco-v0.1.89`;
> 0.3.0 live in `eco-v0.1.122`; 0.4.0 in `eco-v0.1.174` (sha256
> `1e142acc...`); **0.4.1 in `eco-v0.1.175` (sha256 `21c1f673...`, modules list)**).
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

## Driver (0.4.0 -- PULSE SQL driver)

`xiom.sqlite.driver` is the consumer-facing facade (contract:
`docs/requirements/pulse-sql-driver.md` in the packages repo): open from a
DSN, execute, query/query_one, explicit transactions with a
rollback-on-error discipline, capability flags, and error mapping that
keeps the SQLite code+message pair.

```xiom
use xiom.io;
use xiom.sqlite.driver;
use xiom.sqlite.types;

fn main() {
  let o = driver.SqlDriver.open_from_dsn("pulse.db?busy_timeout=5000&journal_mode=wal");
  if !o.is_ok { return; }
  let drv = o.value;
  let c = driver.SqlDriver.execute(&drv, "CREATE TABLE IF NOT EXISTS t(id INTEGER PRIMARY KEY, name TEXT);");
  if !c.is_ok { return; }
  let b = driver.SqlDriver.transaction_begin(&drv);
  if !b.is_ok { return; }
  let i = driver.SqlDriver.execute(&drv, "INSERT INTO t(name) VALUES ('hello');");
  if !i.is_ok {
    let rb = driver.SqlDriver.transaction_rollback(&drv);   // report the ORIGINAL error
    return;
  }
  let cm = driver.SqlDriver.transaction_commit(&drv);
  let q = driver.SqlDriver.query(&drv, "SELECT id, name FROM t;");
  if q.is_ok {
    let res: SqliteResult = q.value;
    let name = SqliteResult.value_by_name(&res, 0, "name");
    if name.is_some {
      let s = SqliteValue.as_text(&name.value);
      if s.is_some { io.println(s.value); }
    }
  }
  let cl = driver.SqlDriver.close(&drv);
}
```

DSN: `[sqlite:|sqlite3:|sqlite://]PATH[?busy_timeout=<ms>&journal_mode=<mode>]`;
defaults: `busy_timeout=5000`, journal mode = engine default (the effective
mode is read back into `SqlDriver.journal_mode` / `caps()`).  Unknown
options and malformed values fail closed with `SQLITE_ERROR`.

`query_one` returns a flat `RowOutcome { has_row: Bool; row: SqliteRow; }`
by design -- the nested `Result[Option[SqliteRow]]` shape corrupts the row
on the current pin (finding B-26; repro
`docs/repro/bindings-pilot/nested-payload/`).

## Registry use (consumer, verified 2026-10-09)

```
xiom pkg install xiom.sqlite@0.2.0
```

```toml
# xiom.toml
[dependencies]
"xiom.sqlite" = "0.2.0"
```

The module then resolves automatically (no `source-roots`). Because the
amalgamation is vendored, the consumer build compiles it too -- pass the
installed copy (required until a package build-hook lands; `port.args.json`
serves this package's own runner only):

```
xiom --run src/main.xi --c-source "%XIOM_HOME%/packages/xiom-sqlite-<version>/xiom-sqlite/vendor/sqlite3.c"
```

## API surface

| Area | Functions |
|------|-----------|
| Version | `libversion`, `libversion_number` |
| Connection | `open`, `close`, `errcode`, `extended_errcode`, `errmsg`, `changes`, `last_insert_rowid` |
| Execution | `exec` |
| Statements | `prepare`, `bind_int64`, `bind_double`, `bind_text`, `bind_null`, `step`, `finalize` |
| Columns | `column_type`, `column_int64`, `column_double`, `column_text`, `column_count`, `column_name` |
| Errors | `error_name`, `SQLITE_*` constants |
| Results | `xiom.sqlite.rows.query_all`, `count_rows`, `query_one`; `SqliteResult.column_index` / `value_by_name`; types in `xiom.sqlite.types` |
| Driver | `xiom.sqlite.driver`: `SqlDriver.open_from_dsn` / `execute` / `query` / `query_one` / `transaction_begin`-`commit`-`rollback` / `in_transaction` / `caps` / `last_error` / `close`; `SqlDsn.parse` |
| Helpers | `xiom.sqlite.query`, `xiom.sqlite.schema`, `xiom.sqlite.migration` |

Full details: `SPEC.md`. Vendored binaries provenance + G2 pin: `SPEC.md` §2.

## Tests

From this directory (absolute `--c-source` path required):

```
xiom --run tests/test_conformance.xi --c-source <repo>\packages\xiom-sqlite\vendor\sqlite3.c
```

Expected: 21 `[PASS]`, exit 0. Allow ~3 minutes on a cold machine (clang
compiles the amalgamation at link time). The suite leaves
`sqlite_conformance_tmp.db` and `sqlite_driver_tmp.db` in the working
directory (gitignored) for the file-backed checks.
