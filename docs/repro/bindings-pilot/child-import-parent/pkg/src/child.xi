// B-04 minimal shape: `use parent;` from a child module, then an unqualified
// call to the parent's pub function. On v0.64.0 the import silently failed
// to resolve (`undefined variable`).
module probe.parent.child

use probe.parent;

pub fn child_value() -> Int {
  return parent_value();
}
