// Minimal repro: `Vec[Struct].clone()` aborts on v0.64.0.
//
// Found by the xiom.session porter (PULSE wave 3, 2026-10-07) while
// implementing session_rotate: cloning the entries vector killed the
// process with an access violation. This probe isolates it.
//
// Expected on a healthy compiler: prints `before`, `cloned len=2`, exit 0.
// Observed on v0.64.0: access violation (exit -1073741819) at/after the
// clone; element-wise copies (docs/repro/struct-clone/README.md) stay green.
//
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module struct_clone_probe

use xiom.io;
use xiom.convert;

pub type Pair = { a: Int; b: Str; }

fn main() -> Int {
  var v: Vec[Pair] = Vec[Pair].new();
  v.push(Pair{ a: 1; b: "one"; });
  v.push(Pair{ a: 2; b: "two"; });
  io.println("before");
  let w = v.clone();
  io.println("cloned len=" + int_to_string(w.len()));
  let p: Pair = w[1];
  io.println("second=" + int_to_string(p.a) + ":" + p.b);
  return 0;
}
