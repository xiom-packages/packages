// cb-abi probe 3: does the checker accept a fn-TYPED extern param
// (`fn xt_cb_int_fn(f: fn(Int32) -> Int32, x: Int32) -> Int32;`) and does the
// call marshal the fn value as a C function pointer? If yes, wrappers can
// take engine-facing fn values directly instead of `as Int` at the call site.
//
// Run: & scripts\xiom.ps1 --run <abs>\probe3_fnparam.xi --c-source <abs>\cbhost.c

module cb_fnparam_direct_probe

use xiom.io;
use xiom.convert;

extern "C" {
  fn xt_cb_int_fn(f: fn(Int32) -> Int32, x: Int32) -> Int32;
}

fn cb_double(x: Int32) -> Int32 { return x * 2; }

fn main() -> Int {
  unsafe {
    let r = xt_cb_int_fn(cb_double, 21) as Int;
    io.println("fnparam=" + int_to_string(r));
    io.flush_stdout();
  }
  return 0;
}
