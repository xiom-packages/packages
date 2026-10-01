// v0.62.2 regression repro (consensus shape): a Str function parameter is
// pushed into a module-level Vec[Str] behind a Bool guard. This is the exact
// construct `xiom.consensus` used for its trace store before the workaround:
//
//   var _cs_trace: Vec[Str] = Vec[Str].new();
//   var _cs_trace_on: Bool = true;
//   fn _cs_trace_ev(s: Str) { if _cs_trace_on { _cs_trace.push(s); } }
//
// Result on v0.62.2: same clang failure (malformed store i8 of a ptr into an
// 8-byte-strided element) as the literal-push global variant. Workaround used
// in the package: single `Str` + parallel `Vec[Int]` line-start offsets.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module vecstr_probe

use xiom.io;
use xiom.convert;

var v: Vec[Str] = Vec[Str].new();
var on: Bool = true;

fn ev(s: Str) {
  if on {
    v.push(s);
  }
}

fn main() -> Int {
  ev("alpha");
  ev("beta");
  io.println("count=" + int_to_string(v.len()));
  let first: Str = v[0];
  io.println("first=" + first);
  return 0;
}
