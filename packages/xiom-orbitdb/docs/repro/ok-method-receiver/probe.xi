// XIOM ORBITDB repro -- C-ORBIT-01 candidate.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Claim: a method call on a value bound by an `Ok(...)` match pattern loses
// the receiver. `decoded.get_column(0)` lowers as if the receiver were
// dropped and the first explicit argument were passed as `self`, producing:
//   'get_column' expects 2 argument(s), found 1
//   argument 1 type mismatch: expected Row, found Int
// while the same call on a directly constructed Row compiles and runs.
//
// Variants (exit code = OR of broken bits; 0 = all green):
//   bit0 (1): A -- match-bound Ok payload, call method with 1 arg
//   bit1 (2): B -- same, rebound through `let d = decoded;`
//   bit2 (4): C -- control: directly constructed Row
//   bit3 (8): D -- match on Option Some binding, same method shape

module orbitdb_repro_ok_method

use xiom.io;
use xiom.convert;

pub type Row = {
  id: Int;
  data: Vec[Int];
}

pub fn Row.get_column(row: &Row, index: Int) -> Option[Int] {
  if index < 0 { return None; }
  if index >= row.data.len() { return None; }
  return Some(row.data[index]);
}

pub fn Row.column_count(row: &Row) -> Int {
  return row.data.len();
}

fn make_row() -> Row {
  var data = Vec[Int].new();
  data.push(42);
  return Row{ id: 7, data: data };
}

fn variant_a() -> Int {
  let r: Result[Row, Int] = Ok(make_row());
  match r {
    Err(_) => return 1,
    Ok(decoded) => {
      // Field + zero-arg method are fine; the 1-arg method is the suspect.
      if decoded.id != 7 { return 1; }
      if decoded.column_count() != 1 { return 1; }
      let c0 = decoded.get_column(0);
      match c0 {
        None => return 1,
        Some(v) => { if v != 42 { return 1; } }
      }
    }
  }
  return 0;
}

fn variant_b() -> Int {
  let r: Result[Row, Int] = Ok(make_row());
  match r {
    Err(_) => return 1,
    Ok(decoded) => {
      let d = decoded;
      let c0 = d.get_column(0);
      match c0 {
        None => return 1,
        Some(v) => { if v != 42 { return 1; } }
      }
    }
  }
  return 0;
}

fn variant_c() -> Int {
  let row = make_row();
  let c0 = row.get_column(0);
  match c0 {
    None => return 1,
    Some(v) => { if v != 42 { return 1; } }
  }
  return 0;
}

fn variant_d() -> Int {
  let o: Option[Row] = Some(make_row());
  match o {
    None => return 1,
    Some(decoded) => {
      let c0 = decoded.get_column(0);
      match c0 {
        None => return 1,
        Some(v) => { if v != 42 { return 1; } }
      }
    }
  }
  return 0;
}

fn main() -> Int {
  var bits = 0;
  if variant_a() != 0 { bits = bits + 1; }
  if variant_b() != 0 { bits = bits + 2; }
  if variant_c() != 0 { bits = bits + 4; }
  if variant_d() != 0 { bits = bits + 8; }
  io.println("orbitdb repro ok-method: bits=" + convert.int_to_string(bits));
  return bits;
}
