// XIOM ORBITDB -- C-ORBIT-08 repro B: UInt8 -> Int element casts may
// sign-extend instead of zero-extend on v0.64.3 (0xF8 -> -8).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Expected: both lines print 248 (zero-extension). Observed on v0.64.3:
// element reads >= 0x80 come back negative.

module repro_u8_cast

use xiom.io;
use xiom.convert;

// Fixed-size array read (the tuple2 float writer path).
fn array_byte_6(f: Float64) -> Int
  requires: true
{
  unsafe {
    var b: [8]UInt8;
    let fp: *mut Float64 = &b[0] as *mut Float64;
    *fp = f;
    return b[6] as Int;
  }
}

// Vec[UInt8] read (the byte_io file-read path).
fn vec_byte(v: &Vec[UInt8]) -> Int {
  return v[0] as Int;
}

fn main() -> Int {
  let a = array_byte_6(1.5);
  io.println("repro B: array cast = " + convert.int_to_string(a) + " (expected 248)");
  var v = Vec[UInt8].new();
  v.push(248);
  let w = vec_byte(&v);
  io.println("repro B: vec cast   = " + convert.int_to_string(w) + " (expected 248)");
  var vin = Vec[Int].new();
  vin.push(248);
  io.println("repro B: int value  = " + convert.int_to_string(vin[0]) + " (expected 248)");
  io.println("repro B: done");
  return 0;
}
