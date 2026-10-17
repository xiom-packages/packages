// XIOM ORBITDB repro (name-collision variant) -- C-ORBIT-01 candidate.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Hypothesis: the failing receiver resolution is a NAME COLLISION between the
// local `row` and the imported type `Row`. The checker's is_static_call test
// looks the receiver ident up in the TYPE registry (lib.rs:7688) without
// consulting locals; if type names intern case-insensitively, `row` reads as
// the type -> static-call semantics -> receiver not implicit -> T001.
//
// Variants (exit code = OR of broken bits; 0 = all green):
//   bit0 (1): I -- variable named `row` (collides with type Row)
//   bit1 (2): H -- variable named `rec` (no collision), same everything else

module orbitdb_repro_name_collision

use xiom.io;
use xiom.convert;
use xiom.db.storage.tuple;

fn variant_i() -> Int {
  var data = Vec[Int].new();
  data.push(42);
  let row = Row.new(7, data);
  let c0 = row.get_column(0);
  match c0 { None => return 1, Some(v) => { if v != 42 { return 1; } } }
  return 0;
}

fn variant_h() -> Int {
  var data = Vec[Int].new();
  data.push(42);
  let rec = Row.new(7, data);
  let c0 = rec.get_column(0);
  match c0 { None => return 1, Some(v) => { if v != 42 { return 1; } } }
  return 0;
}

fn main() -> Int {
  var bits = 0;
  if variant_i() != 0 { bits = bits + 1; }
  if variant_h() != 0 { bits = bits + 2; }
  io.println("orbitdb repro name-collision: bits=" + convert.int_to_string(bits));
  return bits;
}
