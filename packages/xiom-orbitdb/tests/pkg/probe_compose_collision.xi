// C-ORBIT-11 repro (real composition): importing BOTH the xiom.btree package
// and ORBITDB's xiom.db.engine in one program fails at CODEGEN on v0.64.4:
//   error[C001]: unresolved function symbol(s): 'xiom.btree.BTreeNode.pop'
//     (first call from @db.engine.split_child), 'xiom.btree.BTreeNode.push'
//     (from @db.engine.insert_at_pos)
// Both modules declare same-named types (BTreeNode, NodeStore, BTree); the
// engine's own `payloads.pop()` / `payloads.push()` calls (a field the
// package's BTreeNode does not have) resolve against the FOREIGN declaration
// instead of a clean diagnostic or engine's own type.
// Pre-m267 this class was silently stubbed; now it is a hard C001 -- correct
// to refuse, but the trigger is only the name collision, not any real
// unresolved function.
//
// Expected when fixed: compiles and prints `compose ok` (rc 0).
// Composition: tests/pkg/xiom.toml (../../src + registry xiom.btree 0.1.1).
// Run: scripts\run.ps1 tests\pkg\probe_compose_collision.xi -TimeoutSec 180

module orbitdb_probe_compose_collision

use xiom.io;
use xiom.db.engine;
use xiom.btree;

fn main() -> Int {
  // Touch each module's own API once; no interaction between them.
  var t = btree_new(4);
  let _ = btree_insert(&mut t, 1, 10);
  var db_path = "probe-logs/compose-collision.wal";
  let _ = io.remove_file(db_path);
  let _ = io.remove_file(db_path + ".snap");
  var db = db_file_open(db_path, 4);
  if !db_file_put(&mut db, 1, 10) { return 1; }
  io.println("compose ok");
  return 0;
}
