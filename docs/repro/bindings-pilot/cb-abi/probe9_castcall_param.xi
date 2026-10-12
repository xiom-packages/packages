// cb-abi probe 9 (B-22 witness): fn-typed values at a CAST-CALL argument
// position.  The glfw dynamic-loader setter shape: resolve an export, cast
// it to a fn pointer, call it with a callback value.
//
// Hypothesis (from the glfw 0.6.0 lift attempt, v0.64.4): the
// env->code-address unwrap fires for extern-declared callees (probe2/4)
// but NOT for cast-call argument positions -- a fn-typed PARAM passed as
// the callback argument reaches C as the closure ENV/entry (C's first
// argument then gets consumed as a hidden env), while a BARE name (or a
// local bound from a bare name) yields the raw code address.
//
// Each helper resolves the export itself (the setter shape: callee = local
// from a cast; only the ARGUMENT varies).
//
// Run: & scripts\xiom.ps1 --run <abs>\probe9_castcall_param.xi --c-source <abs>\cbhost.c

module cb_fnval_castcall_probe

use xiom.io;
use xiom.convert;
use xiom.ffi.dl;

fn cb_double(x: Int32) -> Int32 { return x * 2; }

// Argument is a BARE name.
fn via_bare_arg() -> Int
  requires: true
{
  let h = dl.dl_self();
  let ar = dl.dl_sym(h, "xt_cb_int_fn_export");
  if !ar.is_ok { return -1; }
  unsafe {
    let fp = ar.value as fn(fn(Int32) -> Int32, Int32) -> Int32;
    return fp(cb_double, 21) as Int;
  }
}

// Argument is a fn-typed PARAM (the glfw setter shape).
fn via_param_arg(p: fn(Int32) -> Int32) -> Int
  requires: true
{
  let h = dl.dl_self();
  let ar = dl.dl_sym(h, "xt_cb_int_fn_export");
  if !ar.is_ok { return -1; }
  unsafe {
    let fp = ar.value as fn(fn(Int32) -> Int32, Int32) -> Int32;
    return fp(p, 21) as Int;
  }
}

// Argument is a local bound from a bare name.
fn via_local_arg() -> Int
  requires: true
{
  let g: fn(Int32) -> Int32 = cb_double;
  let h = dl.dl_self();
  let ar = dl.dl_sym(h, "xt_cb_int_fn_export");
  if !ar.is_ok { return -1; }
  unsafe {
    let fp = ar.value as fn(fn(Int32) -> Int32, Int32) -> Int32;
    return fp(g, 21) as Int;
  }
}

fn main() -> Int {
  io.println("via_bare_arg=" + int_to_string(via_bare_arg()));
  io.println("via_param_arg=" + int_to_string(via_param_arg(cb_double)));
  io.println("via_local_arg=" + int_to_string(via_local_arg()));
  io.flush_stdout();
  return 0;
}
