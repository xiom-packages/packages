// xiom.sqlite conformance suite -- vendored SQLite amalgamation path.
//
// Proves the real (non-stub) binding against the vendored amalgamation
// compiled into the test binary:
//   xiom --run tests/test_conformance.xi --c-source vendor/sqlite3.c
//
// Coverage (G3/G4):
//   * version pin: sqlite.libversion()/sqlite.libversion_number() match the G2 pin 3.53.4
//   * connection lifecycle: open / close / errcode / errmsg
//   * exec: multi-statement DDL+DML, changes(), last_insert_rowid()
//   * prepared statements: prepare / bind (int, text, float, null) / step /
//     column type+value+name access / finalize / handle reuse
//   * error codes: malformed SQL, PRIMARY KEY constraint, code->name mapping
//   * transactions: BEGIN/ROLLBACK vs BEGIN/COMMIT
//   * rows module: query_all materialization, count_rows, typed values
//   * query builder integration: QueryBuilder SQL executes
//   * schema builder integration: TableDef DDL executes
//   * migration manager: up/down over a live handle
//   * file-backed database: create, close, reopen, persisted row count
//
// The file-backed check creates `sqlite_conformance_tmp.db` in the current
// directory (already covered by the package .gitignore).  It resets its own
// table on every run, so repeated runs are deterministic.

module sqlite_conformance

use xiom.io;
use xiom.io.fs;
use xiom.convert;
use xiom.test;
use xiom.string.compare;
use xiom.sqlite;
use xiom.sqlite.rows;
use xiom.sqlite.types;
use xiom.sqlite.query;
use xiom.sqlite.schema;
use xiom.sqlite.migration;

// ---------------------------------------------------------------------------
// helpers
// ---------------------------------------------------------------------------

fn str_eq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn b2s(b: Bool) -> Str {
  if b { return "true"; }
  return "false";
}

fn opt_int_is(v: Option[Int], want: Int) -> Bool {
  if !v.is_some { return false; }
  return v.value == want;
}

fn opt_str_eq(v: Option[Str], want: Str) -> Bool {
  if !v.is_some { return false; }
  return str_eq(v.value, want);
}

fn open_mem() -> Int {
  let o = sqlite.open(":memory:");
  if !o.is_ok {
    return 0;
  }
  return o.value;
}

// ---------------------------------------------------------------------------
// tests
// ---------------------------------------------------------------------------

// 1. The vendored amalgamation is the pinned upstream release.
fn t01_version_pin() -> TestResult {
  var ok = true;
  if !str_eq(sqlite.libversion(), "3.53.4") { ok = false; }
  if sqlite.libversion_number() != 3053004 { ok = false; }
  return assert(ok, "version: vendored amalgamation reports 3.53.4 (string + number)");
}

// 2. Connection lifecycle: open, errcode clean, close.
fn t02_connection_lifecycle() -> TestResult {
  let o = sqlite.open(":memory:");
  if !o.is_ok {
    return assert(false, "connection: open(:memory:) succeeds");
  }
  let db: Int = o.value;
  var ok = true;
  if db == 0 { ok = false; }
  if sqlite.errcode(db) != SQLITE_OK { ok = false; }
  if !str_eq(sqlite.error_name(sqlite.errcode(db)), "SQLITE_OK") { ok = false; }
  let c = sqlite.close(db);
  if !c.is_ok { ok = false; }
  return assert(ok, "connection: open/close lifecycle with clean errcode");
}

// 3. exec: multi-statement script, changes(), last_insert_rowid().
fn t03_exec_script() -> TestResult {
  let db = open_mem();
  if db == 0 { return assert(false, "exec: setup open"); }
  var ok = true;
  let r1 = sqlite.exec(db, "CREATE TABLE t(id INTEGER PRIMARY KEY, v TEXT);");
  if !r1.is_ok { ok = false; }
  let r2 = sqlite.exec(db, "INSERT INTO t(v) VALUES ('a'); INSERT INTO t(v) VALUES ('b'); INSERT INTO t(v) VALUES ('c');");
  if !r2.is_ok { ok = false; }
  if sqlite.changes(db) != 1 { ok = false; }
  if sqlite.last_insert_rowid(db) != 3 { ok = false; }
  let cr = sqlite.close(db);
  if !cr.is_ok { ok = false; }
  return assert(ok, "exec: multi-statement DDL/DML, changes()=1, last rowid=3");
}

// 4. prepare/step/column: full SELECT over typed columns.
fn t04_prepared_select() -> TestResult {
  let db = open_mem();
  if db == 0 { return assert(false, "select: setup open"); }
  var ok = true;
  let r1 = sqlite.exec(db, "CREATE TABLE t(id INTEGER PRIMARY KEY, name TEXT, score REAL, note TEXT);");
  if !r1.is_ok { ok = false; }
  let r2 = sqlite.exec(db, "INSERT INTO t(name, score, note) VALUES ('alpha', 2.5, NULL);");
  if !r2.is_ok { ok = false; }
  let p = sqlite.prepare(db, "SELECT id, name, score, note FROM t ORDER BY id;");
  if !p.is_ok { return assert(false, "select: prepare succeeds"); }
  let stmt: Int = p.value;
  if sqlite.column_count(stmt) != 4 { ok = false; }
  if !str_eq(sqlite.column_name(stmt, 0), "id") { ok = false; }
  if !str_eq(sqlite.column_name(stmt, 1), "name") { ok = false; }
  let s = sqlite.step(stmt);
  if !s.is_ok { ok = false; } else {
    if !s.value { ok = false; } else {
      if sqlite.column_type(stmt, 0) != SQLITE_INTEGER { ok = false; }
      if sqlite.column_int64(stmt, 0) != 1 { ok = false; }
      if sqlite.column_type(stmt, 1) != SQLITE_TEXT { ok = false; }
      if !str_eq(sqlite.column_text(stmt, 1), "alpha") { ok = false; }
      if sqlite.column_type(stmt, 2) != SQLITE_FLOAT { ok = false; }
      if sqlite.column_double(stmt, 2) as Int != 2 { ok = false; }
      if sqlite.column_type(stmt, 3) != SQLITE_NULL { ok = false; }
      if !str_eq(sqlite.column_text(stmt, 3), "") { ok = false; }
    }
  }
  let s2 = sqlite.step(stmt);
  if !s2.is_ok { ok = false; } else {
    if s2.value { ok = false; }
  }
  let f = sqlite.finalize(stmt);
  if !f.is_ok { ok = false; }
  let cr = sqlite.close(db);
  if !cr.is_ok { ok = false; }
  return assert(ok, "select: prepare/step/column types, values, names, NULL");
}

// 5. Parameter binding: int64, text, double, null.
fn t05_bind_parameters() -> TestResult {
  let db = open_mem();
  if db == 0 { return assert(false, "bind: setup open"); }
  var ok = true;
  let r1 = sqlite.exec(db, "CREATE TABLE t(id INTEGER PRIMARY KEY, name TEXT, score REAL);");
  if !r1.is_ok { ok = false; }
  let ins = sqlite.prepare(db, "INSERT INTO t(id, name, score) VALUES (?1, ?2, ?3);");
  if !ins.is_ok { ok = false; } else {
    let st: Int = ins.value;
    let b1 = sqlite.bind_int64(st, 1, 41);
    let b2 = sqlite.bind_text(st, 2, "bound-text");
    let b3 = sqlite.bind_double(st, 3, -7.25);
    if !b1.is_ok { ok = false; }
    if !b2.is_ok { ok = false; }
    if !b3.is_ok { ok = false; }
    let s = sqlite.step(st);
    if !s.is_ok { ok = false; } else {
      if s.value { ok = false; }
    }
    let f = sqlite.finalize(st);
    if !f.is_ok { ok = false; }
  }
  let n = sqlite.prepare(db, "SELECT name, score FROM t WHERE id = ?1;");
  if !n.is_ok { ok = false; } else {
    let st: Int = n.value;
    let b = sqlite.bind_int64(st, 1, 41);
    if !b.is_ok { ok = false; }
    let s = sqlite.step(st);
    if !s.is_ok { ok = false; } else {
      if !s.value { ok = false; } else {
        if !str_eq(sqlite.column_text(st, 0), "bound-text") { ok = false; }
        if sqlite.column_double(st, 1) as Int != -7 { ok = false; }
      }
    }
    let f = sqlite.finalize(st);
    if !f.is_ok { ok = false; }
  }
  let q = sqlite.prepare(db, "SELECT ?1 IS NULL;");
  if !q.is_ok { ok = false; } else {
    let st: Int = q.value;
    let b = sqlite.bind_null(st, 1);
    if !b.is_ok { ok = false; }
    let s = sqlite.step(st);
    if !s.is_ok { ok = false; } else {
      if !s.value { ok = false; } else {
        if sqlite.column_int64(st, 0) != 1 { ok = false; }
      }
    }
    let f = sqlite.finalize(st);
    if !f.is_ok { ok = false; }
  }
  let cr = sqlite.close(db);
  if !cr.is_ok { ok = false; }
  return assert(ok, "bind: int64/text/double/null round-trip through parameters");
}

// 6. Error codes: malformed SQL and PRIMARY KEY constraint.
fn t06_error_codes() -> TestResult {
  let db = open_mem();
  if db == 0 { return assert(false, "errors: setup open"); }
  var ok = true;
  let bad = sqlite.prepare(db, "SELEC * FROM t;");
  if bad.is_ok { ok = false; } else {
    if bad.error.code != SQLITE_ERROR { ok = false; }
    if !str_eq(sqlite.error_name(bad.error.code), "SQLITE_ERROR") { ok = false; }
    if bad.error.message.len() == 0 { ok = false; }
  }
  if sqlite.errcode(db) != SQLITE_ERROR { ok = false; }
  if sqlite.errmsg(db).len() == 0 { ok = false; }
  let r1 = sqlite.exec(db, "CREATE TABLE k(id INTEGER PRIMARY KEY);");
  if !r1.is_ok { ok = false; }
  let r2 = sqlite.exec(db, "INSERT INTO k VALUES (1);");
  if !r2.is_ok { ok = false; }
  let dup = sqlite.exec(db, "INSERT INTO k VALUES (1);");
  if dup.is_ok { ok = false; } else {
    if dup.error.code != SQLITE_CONSTRAINT { ok = false; }
    if !str_eq(sqlite.error_name(dup.error.code), "SQLITE_CONSTRAINT") { ok = false; }
  }
  if !str_eq(sqlite.error_name(SQLITE_BUSY), "SQLITE_BUSY") { ok = false; }
  if !str_eq(sqlite.error_name(SQLITE_ROW), "SQLITE_ROW") { ok = false; }
  if !str_eq(sqlite.error_name(999), "SQLITE_UNKNOWN") { ok = false; }
  let cr = sqlite.close(db);
  if !cr.is_ok { ok = false; }
  return assert(ok, "errors: malformed SQL -> SQLITE_ERROR, dup PK -> SQLITE_CONSTRAINT");
}

// 7. Transactions: rollback undoes, commit persists.
fn t07_transactions() -> TestResult {
  let db = open_mem();
  if db == 0 { return assert(false, "tx: setup open"); }
  var ok = true;
  let c1 = sqlite.exec(db, "CREATE TABLE t(x INTEGER);");
  if !c1.is_ok { ok = false; }
  let a = sqlite.exec(db, "BEGIN; INSERT INTO t VALUES (1); ROLLBACK;");
  if !a.is_ok { ok = false; }
  let n1 = count_rows(db, "SELECT x FROM t;");
  if !n1.is_ok { ok = false; } else {
    if n1.value != 0 { ok = false; }
  }
  let b = sqlite.exec(db, "BEGIN; INSERT INTO t VALUES (2); COMMIT;");
  if !b.is_ok { ok = false; }
  let n2 = count_rows(db, "SELECT x FROM t;");
  if !n2.is_ok { ok = false; } else {
    if n2.value != 1 { ok = false; }
  }
  let cr = sqlite.close(db);
  if !cr.is_ok { ok = false; }
  return assert(ok, "tx: ROLLBACK discards, COMMIT persists");
}

// 8. rows module: query_all materializes typed rows and names.
fn t08_query_all() -> TestResult {
  let db = open_mem();
  if db == 0 { return assert(false, "rows: setup open"); }
  var ok = true;
  let c = sqlite.exec(db, "CREATE TABLE t(id INTEGER PRIMARY KEY, name TEXT);");
  if !c.is_ok { ok = false; }
  let i = sqlite.exec(db, "INSERT INTO t(name) VALUES ('alpha'); INSERT INTO t(name) VALUES ('beta'); INSERT INTO t(name) VALUES ('gamma');");
  if !i.is_ok { ok = false; }
  let r = query_all(db, "SELECT id, name FROM t ORDER BY id;");
  if !r.is_ok { ok = false; } else {
    let res: SqliteResult = r.value;
    if res.row_count() != 3 { ok = false; }
    if res.column_count() != 2 { ok = false; }
    let row1 = SqliteResult.get_row(&res, 1);
    if !row1.is_some { ok = false; } else {
      let rw: SqliteRow = row1.value;
      let v0 = SqliteRow.get(&rw, 0);
      let v1 = SqliteRow.get(&rw, 1);
      if !v0.is_some { ok = false; } else {
        let iv: SqliteValue = v0.value;
        if !opt_int_is(SqliteValue.as_int(&iv), 2) { ok = false; }
      }
      if !v1.is_some { ok = false; } else {
        if !opt_str_eq(SqliteValue.as_text(&v1.value), "beta") { ok = false; }
      }
    }
    let names = res.column_names;
    if names.len() != 2 { ok = false; }
    if !str_eq(names[0], "id") { ok = false; }
    if !str_eq(names[1], "name") { ok = false; }
  }
  let cnt = count_rows(db, "SELECT id FROM t;");
  if !cnt.is_ok { ok = false; } else {
    if cnt.value != 3 { ok = false; }
  }
  let cr = sqlite.close(db);
  if !cr.is_ok { ok = false; }
  return assert(ok, "rows: query_all typed rows, column names, count_rows");
}

// 9. Column datatypes: NULL/BLOB/INTEGER/FLOAT/TEXT in one row.
fn t09_column_datatypes() -> TestResult {
  let db = open_mem();
  if db == 0 { return assert(false, "types: setup open"); }
  var ok = true;
  let p = sqlite.prepare(db, "SELECT NULL, CAST('x' AS BLOB), 42, 3.25, 'txt';");
  if !p.is_ok { ok = false; } else {
    let st: Int = p.value;
    let s = sqlite.step(st);
    if !s.is_ok { ok = false; } else {
      if !s.value { ok = false; } else {
        if sqlite.column_type(st, 0) != SQLITE_NULL { ok = false; }
        if sqlite.column_type(st, 1) != SQLITE_BLOB { ok = false; }
        if sqlite.column_type(st, 2) != SQLITE_INTEGER { ok = false; }
        if sqlite.column_type(st, 3) != SQLITE_FLOAT { ok = false; }
        if sqlite.column_type(st, 4) != SQLITE_TEXT { ok = false; }
        if sqlite.column_int64(st, 2) != 42 { ok = false; }
        if !str_eq(sqlite.column_text(st, 4), "txt") { ok = false; }
      }
    }
    let f = sqlite.finalize(st);
    if !f.is_ok { ok = false; }
  }
  let cr = sqlite.close(db);
  if !cr.is_ok { ok = false; }
  return assert(ok, "datatypes: NULL/BLOB/INTEGER/FLOAT/TEXT column tagging");
}

// 10. Wide values: large int, negative, unicode text.
fn t10_wide_values() -> TestResult {
  let db = open_mem();
  if db == 0 { return assert(false, "wide: setup open"); }
  var ok = true;
  let c = sqlite.exec(db, "CREATE TABLE t(big INTEGER, neg INTEGER, uni TEXT);");
  if !c.is_ok { ok = false; }
  let ins = sqlite.prepare(db, "INSERT INTO t(big, neg, uni) VALUES (?1, ?2, ?3);");
  if !ins.is_ok { ok = false; } else {
    let st: Int = ins.value;
    let b1 = sqlite.bind_int64(st, 1, 1099511627776);
    let b2 = sqlite.bind_int64(st, 2, -123456789012345);
    let b3 = sqlite.bind_text(st, 3, "héllo wörld");
    if !b1.is_ok { ok = false; }
    if !b2.is_ok { ok = false; }
    if !b3.is_ok { ok = false; }
    let s = sqlite.step(st);
    if !s.is_ok { ok = false; }
    let f = sqlite.finalize(st);
    if !f.is_ok { ok = false; }
  }
  let r = query_all(db, "SELECT big, neg, uni FROM t;");
  if !r.is_ok { ok = false; } else {
    let res: SqliteResult = r.value;
    if res.row_count() != 1 { ok = false; } else {
      let row1 = SqliteResult.get_row(&res, 0);
      if !row1.is_some { ok = false; } else {
        let rw: SqliteRow = row1.value;
        let v0 = SqliteRow.get(&rw, 0);
        let v1 = SqliteRow.get(&rw, 1);
        let v2 = SqliteRow.get(&rw, 2);
        if !v0.is_some { ok = false; } else {
          if !opt_int_is(SqliteValue.as_int(&v0.value), 1099511627776) { ok = false; }
        }
        if !v1.is_some { ok = false; } else {
          if !opt_int_is(SqliteValue.as_int(&v1.value), -123456789012345) { ok = false; }
        }
        if !v2.is_some { ok = false; } else {
          if !opt_str_eq(SqliteValue.as_text(&v2.value), "héllo wörld") { ok = false; }
        }
      }
    }
  }
  let cr = sqlite.close(db);
  if !cr.is_ok { ok = false; }
  return assert(ok, "values: 2^40 int, negative int, unicode text round-trip");
}

// 11. Statement handle reuse: repeated prepare/step/finalize cycles.
fn t11_handle_reuse() -> TestResult {
  let db = open_mem();
  if db == 0 { return assert(false, "reuse: setup open"); }
  var ok = true;
  var i: Int = 0;
  while i < 32 {
    let p = sqlite.prepare(db, "SELECT 1;");
    if !p.is_ok { ok = false; } else {
      let st: Int = p.value;
      let s = sqlite.step(st);
      if !s.is_ok { ok = false; } else {
        if !s.value { ok = false; } else {
          if sqlite.column_int64(st, 0) != 1 { ok = false; }
        }
      }
      let s2 = sqlite.step(st);
      if !s2.is_ok { ok = false; } else {
        if s2.value { ok = false; }
      }
      let f = sqlite.finalize(st);
      if !f.is_ok { ok = false; }
    }
    i = i + 1;
  }
  let cr = sqlite.close(db);
  if !cr.is_ok { ok = false; }
  return assert(ok, "reuse: 32 prepare/step/finalize cycles");
}

// 12. Query builder SQL executes against a real table.
fn t12_query_builder() -> TestResult {
  let db = open_mem();
  if db == 0 { return assert(false, "query: setup open"); }
  var ok = true;
  let c = sqlite.exec(db, "CREATE TABLE people(name TEXT, city TEXT);");
  if !c.is_ok { ok = false; }
  let i = sqlite.exec(db, "INSERT INTO people VALUES ('Ada', 'Athens'); INSERT INTO people VALUES ('Linus', 'Helsinki');");
  if !i.is_ok { ok = false; }
  var qb = QueryBuilder.select("people");
  QueryBuilder.column(&mut qb, "name");
  QueryBuilder.where_eq(&mut qb, "city", "Athens");
  QueryBuilder.order_by(&mut qb, "name", false);
  let sql = QueryBuilder.to_sql(&qb);
  let r = query_all(db, sql);
  if !r.is_ok { ok = false; } else {
    let res: SqliteResult = r.value;
    if res.row_count() != 1 { ok = false; } else {
      let row0 = SqliteResult.get_row(&res, 0);
      if !row0.is_some { ok = false; } else {
        let rw: SqliteRow = row0.value;
        let v = SqliteRow.get(&rw, 0);
        if !v.is_some { ok = false; } else {
          if !opt_str_eq(SqliteValue.as_text(&v.value), "Ada") { ok = false; }
        }
      }
    }
  }
  let cr = sqlite.close(db);
  if !cr.is_ok { ok = false; }
  return assert(ok, "query: QueryBuilder SQL prepared and executed");
}

// 13. Schema builder DDL executes against the database.
fn t13_schema_builder() -> TestResult {
  let db = open_mem();
  if db == 0 { return assert(false, "schema: setup open"); }
  var ok = true;
  var td = TableDef.new("inv");
  TableDef.add_auto_id(&mut td);
  TableDef.add_column(&mut td, "sku", SqliteAffinity.TextAff);
  TableDef.add_column(&mut td, "qty", SqliteAffinity.IntegerAff);
  if TableDef.column_count(&td) != 3 { ok = false; }
  let col = TableDef.get_column(&td, "qty");
  if !col.is_some { ok = false; }
  let ddl = TableDef.to_create_sql(&td);
  let c = sqlite.exec(db, ddl);
  if !c.is_ok { ok = false; }
  let i = sqlite.exec(db, "INSERT INTO inv(sku, qty) VALUES ('A-1', 7);");
  if !i.is_ok { ok = false; }
  let r = query_all(db, "SELECT sku, qty FROM inv;");
  if !r.is_ok { ok = false; } else {
    let res: SqliteResult = r.value;
    if res.row_count() != 1 { ok = false; } else {
      let row0 = SqliteResult.get_row(&res, 0);
      if !row0.is_some { ok = false; } else {
        let rw: SqliteRow = row0.value;
        let v1 = SqliteRow.get(&rw, 1);
        if !v1.is_some { ok = false; } else {
          if !opt_int_is(SqliteValue.as_int(&v1.value), 7) { ok = false; }
        }
      }
    }
  }
  let cr = sqlite.close(db);
  if !cr.is_ok { ok = false; }
  return assert(ok, "schema: TableDef DDL + live insert/select");
}

// 14. Migration manager: up applies in order, down rolls back.
fn t14_migration_manager() -> TestResult {
  let db = open_mem();
  if db == 0 { return assert(false, "migration: setup open"); }
  var ok = true;
  var mgr = MigrationManager.new();
  let m1 = Migration.new(1, "create", "CREATE TABLE m(x INTEGER);", "DROP TABLE m;");
  let m2 = Migration.new(2, "seed", "INSERT INTO m VALUES (7);", "DELETE FROM m;");
  MigrationManager.add(&mut mgr, m1);
  MigrationManager.add(&mut mgr, m2);
  let up = MigrationManager.migrate_up(&mut mgr, db);
  if !up.is_ok { ok = false; } else {
    if up.value != 2 { ok = false; }
  }
  if MigrationManager.version(&mgr) != 2 { ok = false; }
  let n1 = count_rows(db, "SELECT x FROM m;");
  if !n1.is_ok { ok = false; } else {
    if n1.value != 1 { ok = false; }
  }
  let down = MigrationManager.migrate_down(&mut mgr, db, 1);
  if !down.is_ok { ok = false; } else {
    if down.value != 1 { ok = false; }
  }
  if MigrationManager.version(&mgr) != 1 { ok = false; }
  let n2 = count_rows(db, "SELECT x FROM m;");
  if !n2.is_ok { ok = false; } else {
    if n2.value != 0 { ok = false; }
  }
  let cr = sqlite.close(db);
  if !cr.is_ok { ok = false; }
  return assert(ok, "migration: up(2) then down(1) over a live handle");
}

// 15. File-backed database: create, close, reopen, persisted count.
fn t15_file_persistence() -> TestResult {
  let path = "sqlite_conformance_tmp.db";
  var ok = true;
  let o1 = sqlite.open(path);
  if !o1.is_ok { return assert(false, "file: open for write"); }
  let db1: Int = o1.value;
  let d = sqlite.exec(db1, "DROP TABLE IF EXISTS t;");
  if !d.is_ok { ok = false; }
  let c = sqlite.exec(db1, "CREATE TABLE t(x INTEGER); INSERT INTO t VALUES (11); INSERT INTO t VALUES (22);");
  if !c.is_ok { ok = false; }
  let cl1 = sqlite.close(db1);
  if !cl1.is_ok { ok = false; }
  let o2 = sqlite.open(path);
  if !o2.is_ok { ok = false; } else {
    let db2: Int = o2.value;
    let n = count_rows(db2, "SELECT x FROM t;");
    if !n.is_ok { ok = false; } else {
      if n.value != 2 { ok = false; }
    }
    let v = query_all(db2, "SELECT x FROM t ORDER BY x;");
    if !v.is_ok { ok = false; } else {
      let res: SqliteResult = v.value;
      if res.row_count() != 2 { ok = false; } else {
        let row1 = SqliteResult.get_row(&res, 1);
        if !row1.is_some { ok = false; } else {
          let rw: SqliteRow = row1.value;
          let col = SqliteRow.get(&rw, 0);
          if !col.is_some { ok = false; } else {
            if !opt_int_is(SqliteValue.as_int(&col.value), 22) { ok = false; }
          }
        }
      }
    }
    let cl2 = sqlite.close(db2);
    if !cl2.is_ok { ok = false; }
  }
  return assert(ok, "file: create/close/reopen persistence");
}

// 16. errmsg changes after distinct failures (not a stale copy).
fn t16_errmsg_updates() -> TestResult {
  let db = open_mem();
  if db == 0 { return assert(false, "errmsg: setup open"); }
  var ok = true;
  let a = sqlite.exec(db, "SELECT * FROM missing_one;");
  if a.is_ok { ok = false; } else {
    let m1 = a.error.message;
    if m1.len() == 0 { ok = false; }
    let b = sqlite.exec(db, "SELECT * FROM missing_two;");
    if b.is_ok { ok = false; } else {
      let m2 = b.error.message;
      if m2.len() == 0 { ok = false; }
      if str_eq(m1, m2) { ok = false; }
    }
  }
  let cr = sqlite.close(db);
  if !cr.is_ok { ok = false; }
  return assert(ok, "errmsg: distinct failures carry distinct messages");
}

// ---------------------------------------------------------------------------
// runner
// ---------------------------------------------------------------------------

// Print one marker (flushed immediately so a mid-suite crash still shows how
// far the run got) and return 0 for pass, 1 for fail.
fn report(r: TestResult) -> Int {
  if r.passed {
    io.println("  [PASS] " + r.name);
    io.flush_stdout();
    return 0;
  }
  io.println("  [FAIL] " + r.name);
  io.flush_stdout();
  return 1;
}

fn main() -> Int {
  io.println("=== xiom.sqlite conformance tests (vendored amalgamation) ===");
  io.flush_stdout();
  var failed: Int = 0;
  failed = failed + report(t01_version_pin());
  failed = failed + report(t02_connection_lifecycle());
  failed = failed + report(t03_exec_script());
  failed = failed + report(t04_prepared_select());
  failed = failed + report(t05_bind_parameters());
  failed = failed + report(t06_error_codes());
  failed = failed + report(t07_transactions());
  failed = failed + report(t08_query_all());
  failed = failed + report(t09_column_datatypes());
  failed = failed + report(t10_wide_values());
  failed = failed + report(t11_handle_reuse());
  failed = failed + report(t12_query_builder());
  failed = failed + report(t13_schema_builder());
  failed = failed + report(t14_migration_manager());
  failed = failed + report(t15_file_persistence());
  failed = failed + report(t16_errmsg_updates());
  if failed == 0 {
    io.println("xiom.sqlite: all tests passed");
  } else {
    io.println("xiom.sqlite: tests failed");
  }
  return failed;
}
