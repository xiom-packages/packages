// XIOM ORBITDB repro -- writing Some into a pre-existing None slot.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Minimal form of the BufferPool.put corruption: a Vec[Option[T]] element
// that was pushed as `None` and later assigned `Some(...)` matches NEITHER
// arm; no diagnostic, execution falls through the match.
// All checks are inline (no helper calls) to rule out argument lowering.

module orbitdb_repro_option_assign

use xiom.io;

type S = { o: Option[Int]; }

fn main() -> Int {
  // V1: push(None) then assign Some into the slot
  var d = Vec[Option[Int]].new();
  d.push(None);
  d[0] = Some(44);
  match d[0] {
    None => { io.println("V1=NONE"); }
    Some(x) => { io.println("V1=SOME"); }
  }
  io.println("after-v1");

  // V2: push(Some) directly (control)
  var c = Vec[Option[Int]].new();
  c.push(Some(44));
  match c[0] {
    None => { io.println("V2=NONE"); }
    Some(x) => { io.println("V2=SOME"); }
  }

  // V3: local value assigned into a None slot
  var e = Vec[Option[Int]].new();
  e.push(None);
  let loc: Option[Int] = Some(55);
  e[0] = loc;
  match e[0] {
    None => { io.println("V3=NONE"); }
    Some(x) => { io.println("V3=SOME"); }
  }

  // V4: struct field overwritten None -> Some
  var s = S{ o: None };
  s.o = Some(66);
  match s.o {
    None => { io.println("V4=NONE"); }
    Some(x) => { io.println("V4=SOME"); }
  }

  // V5: Int control -- pre-existing value overwritten
  var n = Vec[Int].new();
  n.push(0);
  n[0] = 77;
  if n[0] == 77 { io.println("V5=OK"); } else { io.println("V5=WRONG"); }

  io.println("assign probe done");
  return 0;
}
