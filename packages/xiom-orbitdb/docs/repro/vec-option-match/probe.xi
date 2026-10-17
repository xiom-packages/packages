// XIOM ORBITDB repro -- match on Vec[Option[...]] index drops the Some arm.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Evidence trail: tests/probes/probe_write_drop2.xi printed the None arms of
// matches on pool.pages[s] (Vec[Option[Page]]) but produced NO output for any
// Some arm, with exit 0 and no diagnostic. This probe isolates:
//   A: match on v[1] (Vec[Option[Int]] index)
//   B: same value rebound to a local first
//   C: match on w[1] (Vec[Option[Struct]] index)
//   D: control -- plain local Option[Int]

module orbitdb_probe_match

use xiom.io;
use xiom.convert;

type P = { id: Int; }

fn show(label: Str, n: Int) {
  io.println(label + "=" + convert.int_to_string(n));
}

fn main() -> Int {
  var v = Vec[Option[Int]].new();
  v.push(None);
  v.push(Some(5));

  // A: index directly
  match v[1] {
    None => { io.println("A=None"); }
    Some(x) => { show("A", x); }
  }

  // B: rebind to a local first
  let o = v[1];
  match o {
    None => { io.println("B=None"); }
    Some(x) => { show("B", x); }
  }

  // C: struct payload
  var w = Vec[Option[P]].new();
  w.push(None);
  w.push(Some(P{ id: 9 }));
  match w[1] {
    None => { io.println("C=None"); }
    Some(p) => { show("C", p.id); }
  }

  // D: control, plain local
  let d: Option[Int] = Some(7);
  match d {
    None => { io.println("D=None"); }
    Some(x) => { show("D", x); }
  }
  io.println("match probe done");
  return 0;
}
