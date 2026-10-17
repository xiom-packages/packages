// XIOM ORBITDB repro -- Option write through &mut reference is corrupt.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Claim: assigning `Some(v)` into a Vec element through a `&mut` parameter
// stores a value that matches NEITHER `None` NOR `Some(_)`; the match
// silently runs no arm and execution continues with no diagnostic.
// Observed in tests/probes/probe_write_drop2.xi (BufferPool.put path).
//
// Matrix (each variant writes, then matches and prints one of OK / NONE /
// NOARM):
//   A: explicit BoxO.put(&mut b, i, v), Vec[Option[Int]] field
//   B: method sugar b.put(i, v)
//   C: plain &mut Vec[Option[Int]] param
//   D: inline write in main (control)
//   E: struct payload Option[P] through explicit BoxP.put
//   F: local Option value assigned to Vec element (control: Some into local)

module orbitdb_repro_option_ref_write

use xiom.io;
use xiom.convert;

type P = { id: Int; }

type BoxO = {
  slots: Vec[Option[Int]];
}

pub fn BoxO.put(b: &mut BoxO, idx: Int, v: Int) {
  b.slots[idx] = Some(v);
}

type BoxP = {
  slots: Vec[Option[P]];
}

pub fn BoxP.put(b: &mut BoxP, idx: Int, p: P) {
  b.slots[idx] = Some(p);
}

fn set_opt(p: &mut Vec[Option[Int]], idx: Int, v: Int) {
  p[idx] = Some(v);
}

fn report(label: Str, o: Option[Int]) {
  match o {
    None => { io.println(label + "=NONE"); }
    Some(x) => { io.println(label + "=OK:" + convert.int_to_string(x)); }
  }
}

fn main() -> Int {
  // A
  var a = BoxO{ slots: Vec[Option[Int]].new() };
  a.slots.push(None);
  BoxO.put(&mut a, 0, 11);
  report("A", a.slots[0]);

  // B
  var b = BoxO{ slots: Vec[Option[Int]].new() };
  b.slots.push(None);
  b.put(0, 22);
  report("B", b.slots[0]);

  // C
  var c = Vec[Option[Int]].new();
  c.push(None);
  set_opt(&mut c, 0, 33);
  report("C", c[0]);

  // D
  var d = Vec[Option[Int]].new();
  d.push(None);
  d[0] = Some(44);
  report("D", d[0]);

  // E
  var e = BoxP{ slots: Vec[Option[P]].new() };
  e.slots.push(None);
  BoxP.put(&mut e, 0, P{ id: 55 });
  match e.slots[0] {
    None => { io.println("E=NONE"); }
    Some(p) => { io.println("E=OK:" + convert.int_to_string(p.id)); }
  }

  // F
  var f = Vec[Option[Int]].new();
  f.push(None);
  let local: Option[Int] = Some(66);
  f[0] = local;
  report("F", f[0]);

  io.println("option-ref-write probe done");
  return 0;
}
