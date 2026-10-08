// Stand-in for the xiom.sqlite.ffi module: same signature the migration
// manager calls (`Result[Unit, SqliteError]`), so the probe needs no native
// library -- the defect under test is a compile-time crash.
module probe_up_down.ffi

use probe_up_down.types;

extern "C" {
  fn GetTickCount64() -> UInt64;
}

pub fn tick() -> Int
  requires: true
{
  unsafe { return GetTickCount64() as Int; }
}

pub fn exec(db: Int, sql: Str) -> Result[Unit, SqliteError]
  requires: db != 0
  requires: sql.len() > 0
{
  return Ok({});
}
