// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Repro 3b -- the same [T, U] Vec[U] map with U == Int: no crash, but the
// mapped elements are mis-written (w[0] reads back 0 instead of 2).
// v0.61.3: exit code 100 (100 + w[0], w[0] == 0).
// Expected once fixed: exit code 0.
module repro_generic_vec_u_int

fn double(x: &Int) -> Int { return *x * 2; }

pub fn map2[T, U](v: &Vec[T], f: fn(&T) -> U) -> Vec[U] {
  let out = Vec[U].new();
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
  v.push(1); v.push(2);
  let w = map2(v, double);
  if (w.len() != 2) { return 10 + w.len(); }
  let a: Int = w[0];
  let b: Int = w[1];
  if (a != 2) { return 100 + a; }
  if (b != 4) { return 120 + b; }
  return 0;
}
