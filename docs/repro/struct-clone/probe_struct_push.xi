// Control for probe_struct_clone.xi: identical operations WITHOUT clone().
// Expected: prints `before`, `len=2`, `second=2:two`, exit 0 on v0.64.0 --
// proving the crash in the sibling probe is the clone itself.
//
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module struct_push_control_probe

use xiom.io;
use xiom.convert;

pub type Pair = { a: Int; b: Str; }

fn main() -> Int {
  var v: Vec[Pair] = Vec[Pair].new();
  v.push(Pair{ a: 1; b: "one"; });
  v.push(Pair{ a: 2; b: "two"; });
  io.println("before");
  io.println("len=" + int_to_string(v.len()));
  let p: Pair = v[1];
  io.println("second=" + int_to_string(p.a) + ":" + p.b);
  return 0;
}
