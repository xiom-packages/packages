// cb-abi probe 5: fn-typed PARAMS are the broken path (probe2/probe4: a param
// value cast to Int -> 0, param re-passed to a fn-typed extern param -> 0).
// Locals and top-level names are fine. Decide the glfw 0.5.0 wrapper API:
// can the wrapper recover a usable callback from a fn-typed param by copying
// it to a local, or into a fn-typed struct field?
//
// Run: & scripts\xiom.ps1 --run <abs>\probe5_recover.xi --c-source <abs>\cbhost.c

module cb_fnparam_recover_probe

use xiom.io;
use xiom.convert;

extern "C" {
  fn xt_cb_int_fn(f: fn(Int32) -> Int32, x: Int32) -> Int32;
  fn xt_cb_int(f: Int, x: Int32) -> Int32;
}

type CbBox = { cb: fn(Int32) -> Int32; }

fn cb_double(x: Int32) -> Int32 { return x * 2; }

// 1. param -> local -> extern fn-typed param
fn relay_copy(f: fn(Int32) -> Int32) -> Int
  requires: true
{
  let g: fn(Int32) -> Int32 = f;
  unsafe {
    return xt_cb_int_fn(g, 21) as Int;
  }
}

// 2. param -> local -> cast -> extern Int param
fn relay_copy_cast(f: fn(Int32) -> Int32) -> Int
  requires: true
{
  let g: fn(Int32) -> Int32 = f;
  unsafe {
    return xt_cb_int(g as Int, 21) as Int;
  }
}

// 3. param -> fn-typed struct field -> extern fn-typed param
fn relay_box(f: fn(Int32) -> Int32) -> Int
  requires: true
{
  let b = CbBox{ cb: f };
  unsafe {
    return xt_cb_int_fn(b.cb, 21) as Int;
  }
}

fn main() -> Int {
  unsafe {
    let a = relay_copy(cb_double);
    io.println("param_to_local=" + int_to_string(a));
    io.flush_stdout();

    let b = relay_copy_cast(cb_double);
    io.println("param_to_local_cast=" + int_to_string(b));
    io.flush_stdout();

    let c = relay_box(cb_double);
    io.println("param_to_box=" + int_to_string(c));
    io.flush_stdout();
  }
  return 0;
}
