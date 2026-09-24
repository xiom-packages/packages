// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Repro 2 -- [T, U] scalar generic with a type-changing callback (Int -> Str).
// v0.61.3: compiles, returns a corrupt Str (length 1, wrong content), exit 21.
// The U == Int control (control_generic_two_param_int.xi) is green, so the
// monomorphised return ABI uses the erased/generic type for U.
// Expected once fixed: exit code 0.
module repro_generic_two_param_str

use xiom.convert;
use xiom.string;
use xiom.string.compare;

pub fn conv[T, U](x: T, f: fn(&T) -> U) -> U {
  return f(&x);
}

fn to_s(x: &Int) -> Str { return int_to_string(*x); }

fn main() -> Int {
  let a = conv(7, to_s);
  if (str_compare(a, "7") == 0) { return 0; }
  return 21 + str_len(a);
}
