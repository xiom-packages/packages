// XIOM ORBITDB -- C-ORBIT-08 addendum (a.k.a. C-ORBIT-12): a tuple with an
// enum element inside a Result whose ERROR type is ALSO an enum miscompiles
// on v0.64.5 (m305 fixed only the Int-error shape).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Found by the ORBITDB v0.64.5 re-verification wave (2026-10-15): after the
// PART A workaround drop attempt, `DbResult[(TValue, Int)]` (DbError is an
// enum) still emits `unknown type 'Tuple__TValue__Int' -- defaulting to
// i64` and 6 typed-value suite tests fail (decode returns Err).
//
// Minimal shape (this file): `Result[(T8Val, Int), T8Err]` with both types
// enums. The compiler emits TWO names for the same tuple struct:
//   %struct.Tuple__repro_ee.T8Val__Int   (module-qualified element key)
//   %struct.Tuple__T8Val__Int            (bare element key)
// one construction site stores the former into the latter ->
//   error: '%tmp17' defined with type '%struct.Tuple__...' but expected ...
// and clang hard-fails (exit 1).
//
// Control (paths with an INT error type -- `Result[(T8Val, Int), Int]`)
// compile and run correctly on v0.64.5; the differences:
//   - Int error  -> sum=110, exit 0 (control t9 in the ORBITDB session logs)
//   - enum error -> clang type-name mismatch (this file)
// The payload variants (Str/Vec/Float) and their count are NOT needed;
// two variants (Vn, Vi(Int)) suffice.

module repro_enum_tuple_enum_error

use xiom.io;
use xiom.convert;

pub type T8Val = enum { Vn, Vi(x: Int) }
pub type T8Err = enum { Bad, Worse }

fn t8_read(k: Int) -> Result[(T8Val, Int), T8Err] {
  if k == 0 {
    let x = 7;
    return Ok((T8Val.Vi(x), 9));
  }
  return Ok((T8Val.Vn, 1));
}

fn t8_kindof(v: T8Val) -> Int {
  match v {
    Vn => { return 0; }
    Vi(_) => { return 1; }
  }
}

fn t8_decode(k: Int) -> Int {
  match t8_read(k) {
    Err(_) => { return -1; }
    Ok(p) => {
      let v = p.0;
      let len = p.1;
      return t8_kindof(v) * 100 + len;
    }
  }
}

fn main() -> Int {
  var sum = 0;
  sum = sum + t8_decode(0);
  sum = sum + t8_decode(1);
  io.println("repro C: sum=" + convert.int_to_string(sum) + " (expected 110)");
  return 0;
}
