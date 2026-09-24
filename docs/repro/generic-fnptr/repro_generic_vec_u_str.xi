// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Repro 3a -- [T, U] Vec[U] map with a type-changing callback (Int -> Str).
// v0.61.3: compiles, runtime access violation: exit code -1073741819
// (0xC0000005), reproduced 3/3.
// Expected once fixed: exit code 0.
module repro_generic_vec_u_str

use xiom.convert;
use xiom.string.compare;

pub fn map_to[T, U](v: &Vec[T], f: fn(&T) -> U) -> Vec[U] {
  let out = Vec[U].new();
  let i = 0;
  while (i < v.len()) {
    let x: T = v[i];
    out.push(f(&x));
    i = i + 1;
  }
  return out;
}

fn to_s(x: &Int) -> Str { return int_to_string(*x); }

fn main() -> Int {
  let v = Vec[Int].new();
  v.push(7); v.push(8);
  let w = map_to(v, to_s);
  if (w.len() == 2) {
    let a: Str = w[0];
    let b: Str = w[1];
    if (str_compare(a, "7") == 0 && str_compare(b, "8") == 0) { return 0; }
  }
  return 1;
}
