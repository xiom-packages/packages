// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Arity-laxness control -- exact argument counts.
//
// Must stay green (exit 0) both before the fix and after it: the fix may
// reject wrong arity, never the correct one.
module control_exact_arity

use xiom.convert;
use xiom.io;

pub fn add2(a: Int, b: Int) -> Int {
  return a + b;
}

fn main() -> Int {
  let r = add2(1, 2);
  io.println("CONTROL OK " + int_to_string(r));
  if (r != 3) { return 14; }
  return 0;
}
