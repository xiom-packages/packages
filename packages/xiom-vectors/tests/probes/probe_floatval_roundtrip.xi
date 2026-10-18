// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pin probe for XVC-C-06: Float32 enum payloads must read back with the exact
// IEEE-754 bit pattern, both directly and through the payload store.
// Exit 0 = green; 1 = direct bind corrupt; 2 = payload-store roundtrip corrupt.

module probe_floatval_roundtrip

use xiom.num.float;
use xiom.vector.payload.payload;

fn main() -> Int {
  var v = FieldValue.FloatVal(10.0);
  var bits: Int = -1;
  match v {
    FloatVal(f) => { bits = float.float_bits(f as Float64); }
    _ => {}
  }
  let want = float.float_bits(10.0);
  if bits != want { return 1; }

  var p = payload_new();
  payload_set(&mut p, "f", v);
  var stored: Int = -1;
  match payload_get(&p, "f") {
    Some(sv) => {
      match sv {
        FloatVal(g) => { stored = float.float_bits(g as Float64); }
        _ => {}
      }
    }
    None => {}
  }
  if stored != want { return 2; }
  return 0;
}
