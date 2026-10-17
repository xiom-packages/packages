// XIOM ORBITDB repro -- variant I alone: annotated rebind from the match
// payload, then all method/field access through the annotated local.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module orbitdb_repro_only_i

use xiom.io;
use xiom.convert;
use xiom.db.storage.tuple;

fn main() -> Int {
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
  io.println("orbitdb repro only-i: OK");
  return 0;
}
