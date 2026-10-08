// Build with: xiom --run tests/probe.xi
// Expected on v0.64.0: compiler stack overflow (exit -1073741571 /
// 0xC00000FD, no program output) because the imported module exports
// associated fns named `up`/`down` and this test imports `xiom.test`.
// Rename them to migrate_up/migrate_down in src/migration.xi -> green.
module probe_up_down_test

use xiom.io;
use xiom.test;
use probe_up_down.ffi;
use probe_up_down.migration;

fn main() -> Int {
  let t = tick();
  var mgr = MigrationManager.new();
  let m1 = Migration.new(1, "one", "SELECT 1;", "SELECT 2;");
  MigrationManager.add(&mut mgr, m1);
  let up = MigrationManager.up(&mut mgr, 1);
  if !up.is_ok { io.println("up failed"); return 1; }
  let down = MigrationManager.down(&mut mgr, 1, 1);
  if !down.is_ok { io.println("down failed"); return 1; }
  io.println("up=" + "1" + " down=" + "1");
  return 0;
}
