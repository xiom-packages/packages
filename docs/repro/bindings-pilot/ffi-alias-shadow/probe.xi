// B-07 minimal shape: a module whose own path ends with the imported stdlib
// alias (`probe.ffi` + `use xiom.ffi;`). On v0.64.0 the import line looked
// legal but unqualified calls failed to resolve (alias self-collision).
//
// Build+run (workdir = this directory):
//   xiom --run probe.xi
// Green = the unqualified call resolves (`b07: resolved, c_strlen=3`).
module probe.ffi

use xiom.io;
use xiom.ffi;

fn main() -> Int {
  let n = c_strlen("abc".c_str() as Int);
  if n == 3 {
    io.println("b07: resolved, c_strlen=3");
    return 0;
  }
  io.println("b07: resolved but wrong length");
  return 1;
}
