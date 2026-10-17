// XIOM ORBITDB repro -- precision pass on the Option-slot write bug.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// V1-V5 (docs/repro/option-vec-assign/probe.xi) showed: Vec[Option[Int]]
// push(None) then assign Some -> no match arm runs; push(Some) then match is
// fine; struct field overwrite is fine. This probe pins the remaining edges:
//   V6: push(Some(1)); v[0] = Some(2)      (Some -> Some overwrite)
//   V7: enum Vec: push(A); v[0] = B        (non-Option enum overwrite)
//   V8: Vec[Option[Str]]: push(None); assign Some("x")
//   V9: push(None); v[0] = None            (None -> None)
//   V10: push(None) x2; v[1] = Some(5); match v[0] and v[1]

module orbitdb_repro_option_assign2

use xiom.io;

enum E {
  A,
  B,
}

fn main() -> Int {
  // V6
  var v6 = Vec[Option[Int]].new();
  v6.push(Some(1));
  v6[0] = Some(2);
  match v6[0] {
    None => { io.println("V6=NONE"); }
    Some(x) => { io.println("V6=SOME"); }
  }

  // V7
  var v7 = Vec[E].new();
  v7.push(E.A);
  v7[0] = E.B;
  match v7[0] {
    A => { io.println("V7=A"); }
    B => { io.println("V7=B"); }
  }

  // V8
  var v8 = Vec[Option[Str]].new();
  v8.push(None);
  v8[0] = Some("x");
  match v8[0] {
    None => { io.println("V8=NONE"); }
    Some(x) => { io.println("V8=SOME"); }
  }

  // V9
  var v9 = Vec[Option[Int]].new();
  v9.push(None);
  v9[0] = None;
  match v9[0] {
    None => { io.println("V9=NONE"); }
    Some(x) => { io.println("V9=SOME"); }
  }

  // V10
  var v10 = Vec[Option[Int]].new();
  v10.push(None);
  v10.push(None);
  v10[1] = Some(5);
  match v10[0] {
    None => { io.println("V10.0=NONE"); }
    Some(x) => { io.println("V10.0=SOME"); }
  }
  match v10[1] {
    None => { io.println("V10.1=NONE"); }
    Some(x) => { io.println("V10.1=SOME"); }
  }

  io.println("assign2 probe done");
  return 0;
}
