// XIOM ORBITDB repro (import variant) -- C-ORBIT-01 candidate.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Faithful copy of tests/test_conformance.xi run_tuple_encode_decode, using
// the REAL cross-module xiom.db.storage.tuple types/aliases. The local-type
// variant (probe.xi) is green on v0.64.0, so the trigger is expected to be
// the cross-module generic alias (DbResult[T] = Result[T, DbError]).
//
// Variants (exit code = OR of broken bits; 0 = all green):
//   bit0 (1): A -- suite shape exactly as written
//   bit1 (2): B -- rebind `let d = decoded;` before the call
//   bit2 (4): C -- explicit `DbResult[Row]` annotation on the decode result
//   bit3 (8): D -- control: construct Row locally, same imported method

module orbitdb_repro_ok_method_import

use xiom.io;
use xiom.convert;
use xiom.db.storage.tuple;

fn variant_a() -> Int {
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
      let c0 = decoded.get_column(0);
      match c0 { None => return 1, Some(v) => { if v != 42 { return 1; } } }
      let c1 = decoded.get_column(1);
      match c1 { None => return 1, Some(v) => { if v != 99 { return 1; } } }
    }
  }
  return 0;
}

fn variant_b() -> Int {
  var data = Vec[Int].new();
  data.push(42);
  let row = Row.new(7, data);
  let encoded = tuple_encode(&row);
  let r = tuple_decode(&encoded);
  match r {
    Err(_) => return 1,
    Ok(decoded) => {
      let d = decoded;
      let c0 = d.get_column(0);
      match c0 { None => return 1, Some(v) => { if v != 42 { return 1; } } }
    }
  }
  return 0;
}

fn variant_c() -> Int {
  var data = Vec[Int].new();
  data.push(42);
  let row = Row.new(7, data);
  let encoded = tuple_encode(&row);
  let r: DbResult[Row] = tuple_decode(&encoded);
  match r {
    Err(_) => return 1,
    Ok(decoded) => {
      let c0 = decoded.get_column(0);
      match c0 { None => return 1, Some(v) => { if v != 42 { return 1; } } }
    }
  }
  return 0;
}

fn variant_d() -> Int {
  var data = Vec[Int].new();
  data.push(42);
  let row = Row.new(7, data);
  let c0 = row.get_column(0);
  match c0 { None => return 1, Some(v) => { if v != 42 { return 1; } } }
  return 0;
}

// E: direct let-bound Row, zero-arg method FIRST, then the 1-arg method.
//    (This is the SUITE shape that compiled: row.column_count() precedes
//    row.get_column(0) in run_row_new_and_access.)
fn variant_e() -> Int {
  var data = Vec[Int].new();
  data.push(42);
  let row = Row.new(7, data);
  if row.column_count() != 1 { return 1; }
  let c0 = row.get_column(0);
  match c0 { None => return 1, Some(v) => { if v != 42 { return 1; } } }
  return 0;
}

// F: direct let-bound Row with an EXPLICIT type annotation, 1-arg call
//    first (mirrors variant C's fix shape for the decode result).
fn variant_f() -> Int {
  var data = Vec[Int].new();
  data.push(42);
  let row: Row = Row.new(7, data);
  let c0 = row.get_column(0);
  match c0 { None => return 1, Some(v) => { if v != 42 { return 1; } } }
  return 0;
}

// G: explicit-receiver call form `Row.get_column(&row, 0)` on an
//    unannotated let binding (candidate consumer workaround).
fn variant_g() -> Int {
  var data = Vec[Int].new();
  data.push(42);
  let row = Row.new(7, data);
  let c0 = Row.get_column(&row, 0);
  match c0 { None => return 1, Some(v) => { if v != 42 { return 1; } } }
  return 0;
}

// H: match-bound payload + EXPLICIT receiver call form (suite workaround
//    candidate): Row.get_column(&decoded, 0).
fn variant_h() -> Int {
  var data = Vec[Int].new();
  data.push(42);
  let row = Row.new(7, data);
  let encoded = tuple_encode(&row);
  let r = tuple_decode(&encoded);
  match r {
    Err(_) => return 1,
    Ok(decoded) => {
      let c0 = Row.get_column(&decoded, 0);
      match c0 { None => return 1, Some(v) => { if v != 42 { return 1; } } }
    }
  }
  return 0;
}

// I: match-bound payload + ANNOTATED rebind, then method call.
fn variant_i() -> Int {
  var data = Vec[Int].new();
  data.push(42);
  let row = Row.new(7, data);
  let encoded = tuple_encode(&row);
  let r = tuple_decode(&encoded);
  match r {
    Err(_) => return 1,
    Ok(decoded) => {
      let d: Row = decoded;
      let c0 = d.get_column(0);
      match c0 { None => return 1, Some(v) => { if v != 42 { return 1; } } }
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
  if variant_e() != 0 { bits = bits + 16; }
  if variant_f() != 0 { bits = bits + 32; }
  if variant_g() != 0 { bits = bits + 64; }
  if variant_h() != 0 { bits = bits + 128; }
  if variant_i() != 0 { bits = bits + 256; }
  io.println("orbitdb repro ok-method-import: bits=" + convert.int_to_string(bits));
  return bits;
}
