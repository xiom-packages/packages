module probe_child_import_test

use xiom.io;
use probe.parent.child;

fn main() -> Int {
  let v = child_value();
  if v == 42 {
    io.println("b04: child imported parent, value=42");
    return 0;
  }
  io.println("b04: wrong value");
  return 1;
}
