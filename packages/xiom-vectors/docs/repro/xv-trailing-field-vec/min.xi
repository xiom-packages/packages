// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Candidate repro, minimization step 1: conditional assignment to locals
// followed by a struct literal inside a loop. Expected exit 0.

module probe_min

use xiom.io;

pub type T = {
  a: Int;
  b: Bool;
}

fn f(with: Bool) -> Vec[T] {
  var out = Vec[T].new();
  var i: Int = 0;
  while i < 2 {
    var x: Int = 0;
    var have: Bool = false;
    if with {
      x = 7;
      have = true;
    }
    out.push(T{ a: x, b: have });
    i = i + 1;
  }
  return out;
}

fn main() -> Int {
  var off = f(false);
  if off[0].b { io.println("BAD b0"); return 1; }
  if off[1].b { io.println("BAD b1"); return 2; }
  var on = f(true);
  if !on[0].b { io.println("BAD on0"); return 3; }
  if on[0].a != 7 { io.println("BAD a0"); return 4; }
  io.println("min: green");
  return 0;
}
