// v0.62.2 regression repro (minimal): push to a MODULE-LEVEL Vec[Str]
// Result on v0.62.2 (installed): clang fails with exit code 1; the emitted
// IR contains a malformed strided store (see README.md for the exact lines):
//   error: '%tmp1035' defined with type 'ptr' but expected 'i8'
//            store i8 %tmp1035, i8* %tmp1034
// Trigger: the Vec is a module-level global (`var v: Vec[Str] = Vec[Str].new();`)
// and the push happens anywhere. A LOCAL Vec[Str] with the same pushes
// compiles and runs correctly (verified), so the global is the differentiator.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module vecstr_probe_c

use xiom.io;

var v: Vec[Str] = Vec[Str].new();

fn main() -> Int {
  v.push("alpha");
  v.push("beta");
  io.println("count=" + "?");
  return 0;
}
