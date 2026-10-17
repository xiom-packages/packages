// XIOM ORBITDB repro -- end-to-end check of the two workarounds for
// C-ORBIT-01 without the failing variants present (so codegen and execution
// actually run). Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
//   bit0 (1): H -- explicit receiver form Row.get_column(&decoded, 0)
//   bit1 (2): I -- annotated rebind `let d: Row = decoded;` + method call

module orbitdb_repro_rebind

use xiom.io;
use xiom.convert;
use xiom.db.storage.tuple;

fn variant_h() -> Int {
  var data = Vec[Int].new();
  data.push(42);
  data.push(99);
  let row = Row.new(7, data);
  let encoded = tuple_encode(&row);
  let r = tuple_decode(&encoded);
  match r {
    Err(_) => return 1,
    Ok(decoded) => {
      if decoded.id != 7 { return 1; }
      if decoded.column_count() != 2 { return 1; }
      let c0 = Row.get_column(&decoded, 0);
      match c0 { None => return 1, Some(v) => { if v != 42 { return 1; } } }
      let c1 = Row.get_column(&decoded, 1);
      match c1 { None => return 1, Some(v) => { if v != 99 { return 1; } } }
    }
  }
  return 0;
}

fn variant_i() -> Int {
  var data = Vec[Int].new();
  data.push(42);
  data.push(99);
  let row = Row.new(7, data);
  let encoded = tuple_encode(&row);
  let r = tuple_decode(&encoded);
  match r {
    Err(_) => return 1,
    Ok(decoded) => {
      let d: Row = decoded;
      if d.id != 7 { return 1; }
      if d.column_count() != 2 { return 1; }
      let c0 = d.get_column(0);
      match c0 { None => return 1, Some(v) => { if v != 42 { return 1; } } }
      let c1 = d.get_column(1);
      match c1 { None => return 1, Some(v) => { if v != 99 { return 1; } } }
    }
  }
  return 0;
}

fn main() -> Int {
  var bits = 0;
  if variant_h() != 0 { bits = bits + 1; }
  if variant_i() != 0 { bits = bits + 2; }
  io.println("orbitdb repro rebind: bits=" + convert.int_to_string(bits));
  return bits;
}
