// B-14 / B-15 repro (v0.64.3) -- this file FAILS type-check BY DESIGN.
//
//   B-14: `return;` inside a function declared with an explicit `-> Unit`
//         annotation -> T001 "expected Unit, found ()".  The stdlib avoids
//         this by leaving the annotation implicit (e.g. array.rotate_left).
//         Workaround: drop the annotation or use structured ifs (the
//         ixom.sdl3 0.5.0 dispatchers do the latter).
//
//   B-15: a `Vec[fn]` ELEMENT call with >= 2 arguments types its result as
//         `()` at use sites -- `if h(a, b)` / `let r = h(a, b)` are T001
//         errors even when the fn type declares a real return.  1-argument
//         element calls type correctly, and statement-position calls
//         silently discard the value (why the glfw 0.5.0 dispatchers, which
//         ignore results, worked).  Workaround: 1-arg handler shapes
//         (sdl3_filter_dispatch) or out-params.
//
// Expected on v0.64.3: exactly 2 type errors (`if h(a, b)` and `return;`).
// Verified 2026-10-11 by the bindings lane during ixom.sdl3 0.5.0.

module cb_element_units_probe

var h1: Vec[fn(Int, Int) -> Bool] = Vec[fn(Int, Int) -> Bool].new();

fn f1(a: Int, b: Int) -> Bool { return a == b; }

// B-15 shape: element call with two arguments, result used.
fn d1(a: Int, b: Int) -> Bool {
  if h1.len() == 0 { return false; }
  let h = h1[h1.len() - 1];
  if h(a, b) { return true; }   // T001: if condition must be Bool, found ()
  return false;
}

// B-14 shape: bare `return;` in an explicitly `-> Unit` fn.
fn early(x: Int) -> Unit {
  if x == 0 { return; }         // T001: expected Unit, found ()
}

fn main() -> Int {
  h1.push(f1);
  var r = 0;
  if d1(1, 1) { r = r + 1; }
  early(0);
  return r;
}
