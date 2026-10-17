// Control for C-ORBIT-09: a manually rebuilt copy OWNS its storage, so
// element assignment on it does not touch the source. This is the workaround
// ORBITDB applies in `cow_shadow`/`node_deep_copy` (src/engine.xi).
module orbitdb_repro_vec_clean

use xiom.io;
use xiom.convert;

fn main() -> Int {
  var src = Vec[Int].new();
  src.push(1);
  src.push(2);
  var copy = Vec[Int].new();
  var i = 0;
  while i < src.len() {
    copy.push(src[i]);
    i = i + 1;
  }
  copy[0] = 99;
  io.println("owned elem-assign: src[0]=" + convert.int_to_string(src[0])
    + " copy[0]=" + convert.int_to_string(copy[0]));
  return 0;
}
