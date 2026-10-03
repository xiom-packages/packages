// v0.62.2 regression repro (BOUNDARY): which `&mut Int` write forms survive?
//
// Matrix: callee body { bare `s = 99` | deref `*s = 99` } x call site
// { plain local `f(st)` | explicit `f(&mut st)` }.
//
// Known on v0.62.2 (installed, 2026-10-03):
//   bare  + explicit -> write DROPPED  (mut_int_write_drop.xi)
//   deref + plain    -> works          (mut-int-write-through/probe_out_params.xi)
//   deref + explicit -> works          (same probe, variants 6/7)
//   bare  + plain    -> pinned by this probe
//
// Also: `xiom.gbnf` (stable, published 0.1.1, 30/30 on v0.62.2) uses the
// deref form (`*pos = *pos + 1`) with plain call sites and is green in
// production -- the boundary is the WRITE FORM in the callee, not the call.
//
// Exit code = number of dropped writes (0 = all four correct).
//
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module mut_int_write_drop_matrix

use xiom.io;
use xiom.convert;

fn set_bare(s: &mut Int) { s = 99; }

fn set_deref(s: &mut Int) { *s = 99; }

fn main() -> Int {
  var bad = 0;

  var a: Int = 10;
  set_bare(a);
  io.println("plain+bare:     " + int_to_string(a) + " (expected 99)");
  if a != 99 { bad = bad + 1; }

  var b: Int = 10;
  set_bare(&mut b);
  io.println("explicit+bare:  " + int_to_string(b) + " (expected 99)");
  if b != 99 { bad = bad + 1; }

  var c: Int = 10;
  set_deref(c);
  io.println("plain+deref:    " + int_to_string(c) + " (expected 99)");
  if c != 99 { bad = bad + 1; }

  var d: Int = 10;
  set_deref(&mut d);
  io.println("explicit+deref: " + int_to_string(d) + " (expected 99)");
  if d != 99 { bad = bad + 1; }

  io.println("bad=" + int_to_string(bad));
  return bad;
}
