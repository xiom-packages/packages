// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Control for repro 3 -- the same Vec map with a fully concrete signature
// (fn(&Int) -> Str). v0.61.3: green, exit code 0 (proves the crash is
// generic-specific; the concrete element stride and push path are sound).
module control_concrete_vec_str

use xiom.convert;
use xiom.string.compare;

pub fn map_is(v: &Vec[Int], f: fn(&Int) -> Str) -> Vec[Str] {
  let out = Vec[Str].new();
  let i = 0;
  while (i < v.len()) {
    let x: Int = v[i];
    out.push(f(&x));
    i = i + 1;
  }
  return out;
}

fn to_s(x: &Int) -> Str { return int_to_string(*x); }

fn main() -> Int {
  let v = Vec[Int].new();
  v.push(7); v.push(8);
  let w = map_is(v, to_s);
  if (w.len() != 2) { return 10 + w.len(); }
  let a: Str = w[0];
  let b: Str = w[1];
  if (str_compare(a, "7") == 0 && str_compare(b, "8") == 0) { return 0; }
  return 30;
}
