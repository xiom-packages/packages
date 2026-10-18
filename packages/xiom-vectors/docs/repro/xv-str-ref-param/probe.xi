// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// XVC-C-13 repro: `&Str` parameter types are unknown to the v0.64.2 type
// checker -- it warns `unknown type '&Str' -- defaulting to i64` and the
// function body reads the parameter as an integer. Expected: first_byte("A")
// = 65, exit 0. Observed on v0.64.2: see README (garbage / -1 / abort).

module repro_str_ref_param

use xiom.string.slice;
use xiom.convert;
use xiom.io;

fn first_byte(s: &Str) -> Int {
  var b = slice.str_bytes(s);
  if b.len() == 0 { return -1; }
  return b[0] as Int;
}

fn main() -> Int {
  var n = first_byte("A");
  io.println("first_byte(A)=" + convert.int_to_string(n) + " (expect 65)");
  if n == 65 { return 0; }
  return 1;
}
