// cb-abi probe 6: the proposed glfw 0.5.0 wrapper design -- user-visible API
// takes fn-typed handlers (typed, no user-side unsafe); a fixed top-level
// dispatcher per event type is the thing whose address crosses into C; user
// handlers live in module-level Vec[fn] storage (m130 element semantics).
//
// Passing a fn-typed PARAM into the registry is the one path this probe must
// clear: register(f) -> handlers.push(f), then the dispatcher calls the
// ELEMENT (m130: elements keep the closure ENV repr and are callable).
//
// Run: & scripts\xiom.ps1 --run <abs>\probe6_registry.xi --c-source <abs>\cbhost.c

module cb_registry_probe

use xiom.io;
use xiom.convert;

extern "C" {
  fn xt_cb_int_fn(f: fn(Int32) -> Int32, x: Int32) -> Int32;
}

var handlers: Vec[fn(Int32) -> Int32] = Vec[fn(Int32) -> Int32].new();

fn cb_double(x: Int32) -> Int32 { return x * 2; }
fn cb_triple(x: Int32) -> Int32 { return x * 3; }

fn register(f: fn(Int32) -> Int32) {
  handlers.push(f);
}

// The fixed dispatcher: ONLY this top-level name's address crosses into C.
fn dispatch(x: Int32) -> Int32 {
  if handlers.len() == 0 { return -1; }
  let g = handlers[handlers.len() - 1];
  return g(x);
}

fn main() -> Int {
  unsafe {
    register(cb_double);
    let a = xt_cb_int_fn(dispatch, 21) as Int;
    io.println("reg_double=" + int_to_string(a));
    io.flush_stdout();

    register(cb_triple);
    let b = xt_cb_int_fn(dispatch, 21) as Int;
    io.println("reg_triple=" + int_to_string(b));
    io.flush_stdout();
  }
  return 0;
}
