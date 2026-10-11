// B-21 repro: `&mut` of a var initialized from a STRUCT-RETURNING call
// (including Result payload extraction) -> clang IR error `use of undefined
// value '%tmp4'` at `load %struct.<Module>.<Type>, %struct.<Module>.<Type>*`.
//
// Trigger bisect (v0.64.3 pin):
//   - var q = Pair{ a: 0, b: 0 };      set_pair(&mut q, 7, 9);  => GREEN
//   - var q = make_pair();             set_pair(&mut q, 7, 9);  => RED (this file)
//   - var api = result.value;          set_handles(&mut api, ..) => RED (seen in
//     the SDK100 Vulkan loader seam before the vk_api_load_full workaround)
//
// Workaround: do not take `&mut` of a var produced by a struct-returning call;
// construct the struct fully in place (a call that returns the final value) or
// avoid by-ref mutation of such temporaries.
//
// Run: xiom --run <this file> (see the bindings-lane repro conventions).

module mut_struct_return

use xiom.io;
use xiom.convert;

pub type Pair = {
  a: Int;
  b: Int;
}

fn set_pair(p: &mut Pair, x: Int, y: Int) {
  p.a = x;
  p.b = y;
}

fn make_pair() -> Pair {
  return Pair{ a: 3, b: 4 };
}

fn main() -> Int {
  var q = make_pair();
  unsafe {
    set_pair(&mut q, 7, 9);
  }
  io.println("a=" + to_string(q.a) + " b=" + to_string(q.b));
  return 0;
}
