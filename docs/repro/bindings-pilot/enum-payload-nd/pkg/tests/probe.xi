// Build+run repeatedly. v0.64.0: in a fraction of builds every accessor
// check below reports false (enum payloads miscompiled globally for that
// build). Observed 3 failing builds in 6 with this exact shape while
// developing xiom.sqlite 0.2.0.
module probe_enum_nd_test

use xiom.io;
use probe_enum_nd.ffi;
use probe_enum_nd.rows;
use probe_enum_nd.types;

fn b2s(b: Bool) -> Str {
  if b { return "true"; }
  return "false";
}

fn main() -> Int {
  let o = ffi.open(":memory:");
  if !o.is_ok { io.println("A=false (open failed)"); return 1; }
  let db: Int = o.value;
  let c = ffi.exec(db, "CREATE TABLE t(id INTEGER PRIMARY KEY, name TEXT);");
  if !c.is_ok { io.println("A=false (create failed)"); return 1; }
  let i = ffi.exec(db, "INSERT INTO t(name) VALUES ('alpha'); INSERT INTO t(name) VALUES ('beta'); INSERT INTO t(name) VALUES ('gamma');");
  if !i.is_ok { io.println("A=false (insert failed)"); return 1; }

  // A: rows module materialization
  let r = query_all(db, "SELECT id, name FROM t ORDER BY id;");
  var a = false;
  if r.is_ok {
    let res: SqliteResult = r.value;
    if res.row_count() == 3 {
      if res.column_count() == 2 {
        a = true;
      }
    }
  }

  // B: row/column accessors through the enum model
  var b = false;
  if r.is_ok {
    let res: SqliteResult = r.value;
    let row1 = SqliteResult.get_row(&res, 1);
    if row1.is_some {
      let rw: SqliteRow = row1.value;
      let v0 = SqliteRow.get(&rw, 0);
      let v1 = SqliteRow.get(&rw, 1);
      if v0.is_some {
        if v1.is_some {
          let i0 = SqliteValue.as_int(&v0.value);
          let t1 = SqliteValue.as_text(&v1.value);
          if i0.is_some {
            if t1.is_some {
              b = (i0.value == 2);
              if t1.value.len() != 4 { b = false; }
            }
          }
        }
      }
    }
  }

  // C: direct prepared-statement + accessor path
  var cc = false;
  let p = ffi.prepare(db, "SELECT 7, 'gamma';");
  if p.is_ok {
    let st: Int = p.value;
    let s = ffi.step(st);
    if s.is_ok {
      if s.value {
        if ffi.column_int64(st, 0) == 7 {
          let tx = ffi.column_text(st, 1);
          if tx.len() == 5 { cc = true; }
        }
      }
    }
    var fin = ffi.finalize(st);
    if !fin.is_ok { cc = false; }
  }

  let cl = ffi.close(db);
  var d = cl.is_ok;

  io.println("A=" + b2s(a) + " B=" + b2s(b) + " C=" + b2s(cc) + " D=" + b2s(d));
  var all = a;
  if !b { all = false; }
  if !cc { all = false; }
  if !d { all = false; }
  if all { return 0; }
  return 1;
}
