// C-ORBIT-11 repro entry: compose two modules that each declare `Box2` and
// call field-method operations from each module's own function.
//
// Real-composition symptom (v0.64.4): importing BOTH `xiom.btree` (package)
// and `xiom.db.engine` (which declare same-named BTreeNode/NodeStore/BTree
// types) fails at codegen with
//   error[C001]: unresolved function symbol(s): 'xiom.btree.BTreeNode.pop'
//   ... from @db.engine.split_child; 'xiom.btree.BTreeNode.push' ... from
//   @db.engine.insert_at_pos
// The engine's own `payloads.pop()` / `payloads.push()` calls (a field the
// package's BTreeNode does not have) resolved against the foreign
// declaration instead of engine's own type or a clean diagnostic. This
// minimal pair isolates the cross-module same-name shape.
module repro_same_named_struct

use xiom.io;
use xiom.convert;
use mod_a;
use mod_b;

fn main() -> Int {
  var a1 = mod_a.make_a();
  var b1 = mod_b.make_b();
  let la = mod_a.fill(&mut a1);
  let lb = mod_b.fill2(&mut b1);
  let ld = mod_a.deep(&mut a1);
  io.println("a.xs.len=" + convert.int_to_string(la) + " b.ys.len=" + convert.int_to_string(lb)
    + " a.kid.xs.len=" + convert.int_to_string(ld));
  return 0;
}
