// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Arity-laxness repro B -- a call with MORE arguments than the declaration.
//
// v0.61.3 observed: compiles silently; extra arguments are dropped. This
// probe therefore runs, prints "SILENT-ACCEPT 3" and exits 12.
//
// Expected once the compiler item-3 batch lands (2026-09-27, row 8 of
// docs/COMPILER-FINDINGS.md): COMPILATION FAILS with an arity /
// argument-count diagnostic and the program never runs.
module repro_extra_arg

use xiom.convert;
use xiom.io;

pub fn add2(a: Int, b: Int) -> Int {
  return a + b;
}

fn main() -> Int {
  let r = add2(1, 2, 99);    // extra 3rd argument
  io.println("SILENT-ACCEPT " + int_to_string(r));
  if (r == 3) { return 12; } // the extra 99 is dropped
  return 13;
}
