// cb-abi probe 2: can a fn-TYPED VALUE (param binding, not a bare top-level
// name) be cast to Int and handed to C? m130 says fn-typed values keep the
// uniform closure ENV representation -- if `f as Int` yields the env pointer
// (not the code address), C calling it directly would crash, so the glfw
// wrappers must know which one to accept.
//
// Run: & scripts\xiom.ps1 --run <abs>\probe2_relay.xi --c-source <abs>\cbhost.c

module cb_fnparam_relay_probe

use xiom.io;
use xiom.convert;

extern "C" {
  fn xt_cb_int(f: Int, x: Int32) -> Int32;
}

fn cb_double(x: Int32) -> Int32 { return x * 2; }

// Pass a fn-typed param through; cast the VALUE (not the name) to Int.
fn relay(f: fn(Int32) -> Int32) -> Int
  requires: true
{
  unsafe {
    return xt_cb_int(f as Int, 21) as Int;
  }
}

fn main() -> Int {
  unsafe {
    // also: local binding of a named fn, then cast the local
    let g: fn(Int32) -> Int32 = cb_double;
    let via_local = xt_cb_int(g as Int, 21) as Int;
    io.println("local=" + int_to_string(via_local));
    io.flush_stdout();

    let via_relay = relay(cb_double);
    io.println("relay=" + int_to_string(via_relay));
    io.flush_stdout();
  }
  return 0;
}
