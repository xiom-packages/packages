// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Control for repro 3 -- single-type-parameter Vec[T] map (fn(&T) -> T).
// v0.61.3: green, exit code 0 (proves the Vec[U] failures are specific to the
// two-type-parameter shape with a distinct result type U).
module control_generic_vec_single_t

fn double(x: &Int) -> Int { return *x * 2; }

pub fn map_vec[T](v: &Vec[T], f: fn(&T) -> T) -> Vec[T] {
  let out = Vec[T].new();
  let i = 0;
  while (i < v.len()) {
    let x: T = v[i];
    out.push(f(&x));
    i = i + 1;
  }
  return out;
}

fn main() -> Int {
  let v = Vec[Int].new();
  v.push(1); v.push(2); v.push(3);
  let w = map_vec(v, double);
  if (w.len() == 3) {
    let a: Int = w[0]; let b: Int = w[1]; let c: Int = w[2];
    if (a == 2 && b == 4 && c == 6) { return 0; }
  }
  return 1;
}
