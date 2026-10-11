// cb-abi probe 4: fn-typed values through the two remaining marshalling paths
// a glfw callback setter can use:
//   A. fn-typed param -> extern fn-typed param (wrapper accepts user cb value)
//   B. local fn value -> extern fn-typed param
//   C. dynamic-loader cast-call with a fn-typed param (the real glfw loader
//      pattern: resolve the setter address, cast, call with the cb value)
//
// Run: & scripts\xiom.ps1 --run <abs>\probe4_marshal.xi --c-source <abs>\cbhost.c

module cb_fnparam_marshal_probe

use xiom.io;
use xiom.convert;
use xiom.ffi;
use xiom.ffi.dl;

extern "C" {
  fn xt_cb_int_fn(f: fn(Int32) -> Int32, x: Int32) -> Int32;
}

fn cb_double(x: Int32) -> Int32 { return x * 2; }

// A: wrapper-shaped relay -- accept a user fn value, pass it straight on.
fn relay_param(f: fn(Int32) -> Int32) -> Int
  requires: true
{
  unsafe {
    return xt_cb_int_fn(f, 21) as Int;
  }
}

fn main() -> Int {
  unsafe {
    // A
    let a = relay_param(cb_double);
    io.println("param_to_fnparam=" + int_to_string(a));
    io.flush_stdout();

    // B
    let g: fn(Int32) -> Int32 = cb_double;
    let b = xt_cb_int_fn(g, 21) as Int;
    io.println("local_to_fnparam=" + int_to_string(b));
    io.flush_stdout();

    // C: dynamic resolution + cast-call (glfw loader pattern)
    let h = dl.dl_self();
    let ar = dl.dl_sym(h, "xt_cb_int_fn_export");
    if ar.is_ok {
      let fp = ar.value as fn(fn(Int32) -> Int32, Int32) -> Int32;
      let c = fp(cb_double, 21) as Int;
      io.println("cast_fnparam=" + int_to_string(c));
    } else {
      io.println("cast_fnparam=resolve_failed");
    }
    io.flush_stdout();
  }
  return 0;
}
