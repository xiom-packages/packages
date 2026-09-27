// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Arity-laxness repro A -- a call with FEWER arguments than the declaration.
//
// v0.61.3 observed: compiles silently; the missing argument reads as 0
// (no diagnostic). This probe therefore runs, prints "SILENT-ACCEPT 3" and
// exits 10.
//
// Expected once the compiler item-3 batch lands (2026-09-27, row 8 of
// docs/COMPILER-FINDINGS.md): COMPILATION FAILS with an arity /
// argument-count diagnostic and the program never runs.
module repro_missing_arg

use xiom.convert;
use xiom.io;

pub fn add3(a: Int, b: Int, c: Int) -> Int {
  return a + b + c;
}

fn main() -> Int {
  let r = add3(1, 2);        // missing 3rd argument
  io.println("SILENT-ACCEPT " + int_to_string(r));
  if (r == 3) { return 10; } // 1 + 2 + (default 0)
  return 11;
}
