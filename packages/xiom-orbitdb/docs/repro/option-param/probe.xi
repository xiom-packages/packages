// XIOM ORBITDB repro -- Option passed as a function argument is corrupt.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// The option-ref-write matrix routed every variant through report(label,
// Option[Int]) and NO arm of the callee's match ever ran (no OK/NONE lines at
// all, "done" still printed). This probe isolates how the argument is built:
//   A: literal Some(77)
//   B: local Option[Int] value
//   C: Vec[Option[Int]] element
//   D: call result (btree-like helper returning Option[Int])
//   E: &Option[Int] parameter (by reference)
//   F: inline match on the Vec element (control, no call)

module orbitdb_repro_option_param

use xiom.io;
use xiom.convert;

fn report(label: Str, o: Option[Int]) {
  match o {
    None => { io.println(label + "=NONE"); }
    Some(x) => { io.println(label + "=OK:" + convert.int_to_string(x)); }
  }
}

fn report_ref(label: Str, o: &Option[Int]) {
  match o {
    None => { io.println(label + "=NONE"); }
    Some(x) => { io.println(label + "=OK:" + convert.int_to_string(x)); }
  }
}

fn maybe(v: Int) -> Option[Int] {
  if v < 0 { return None; }
  return Some(v);
}

fn main() -> Int {
  // A: literal
  report("A", Some(77));

  // B: local value
  let g: Option[Int] = Some(88);
  report("B", g);

  // C: Vec element
  var v = Vec[Option[Int]].new();
  v.push(Some(99));
  report("C", v[0]);

  // D: call result
  report("D", maybe(44));
  report("D2", maybe(-1));

  // E: by reference
  report_ref("E", &g);
  report_ref("E2", &v[0]);

  // F: inline control
  match v[0] {
    None => { io.println("F=NONE"); }
    Some(x) => { io.println("F=OK:" + convert.int_to_string(x)); }
  }
  io.println("option-param probe done");
  return 0;
}
