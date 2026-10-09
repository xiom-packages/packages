module probe_const_alias_test

use xiom.io;
use probe.constalias;

fn main() -> Int {
  let v = FACADE_VALUE;
  if v == 7 {
    io.println("b03: alias const resolved, value=7");
    return 0;
  }
  io.println("b03: wrong value");
  return 1;
}
