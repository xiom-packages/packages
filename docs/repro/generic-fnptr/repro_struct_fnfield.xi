// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Repro 1 -- fn-pointer stored in a struct field, called through the field.
// v0.61.3: codegen fails (clang IR type error), NOT generic-specific.
// Expected once fixed: exit code 0.
module repro_struct_fnfield

pub type Op = { f: fn(&Int) -> Int; }

fn double(x: &Int) -> Int { return *x * 2; }

fn main() -> Int {
  let op = Op{ f: double; };
  let r = (op.f)(&3);
  return r - 6;
}
