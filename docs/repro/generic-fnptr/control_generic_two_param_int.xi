// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Control for repro 2 -- the same [T, U] shape with U == Int.
// v0.61.3: green, exit code 0 (proves the defect is specific to the
// type-changing return path, not to two-type-parameter generics per se).
module control_generic_two_param_int

fn double(x: &Int) -> Int { return *x * 2; }

pub fn conv[T, U](x: T, f: fn(&T) -> U) -> U {
  return f(&x);
}

fn main() -> Int {
  return conv(3, double) - 6;
}
