// XVC-C-14 repro, main -- importing BOTH the engine module (whose Counter
// comes from repro.shim) and xiom.metrics (which has its own Counter) puts
// two same-named struct types in one program. On v0.64.2 the engine's
// field layout takes the package Counter while the value still comes from
// the shim constructor, and clang rejects the generated store (see
// README.md). The healthy end state prints both counters' values.
module repro.main

use repro.engine;
use repro.tally;
use xiom.io;
use xiom.convert;

fn main() -> Int {
  var e = eng_new();
  eng_up(&mut e);
  var t = tally_new();
  tally_hit(&mut t);
  io.println("shim counter=" + convert.int_to_string(e.upserts.value)
    + " tally hits=" + convert.int_to_string(tally_hits(&t)));
  return 0;
}
