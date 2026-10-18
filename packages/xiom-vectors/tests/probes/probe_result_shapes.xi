// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pin probe (per build): the XVC-C-04 Result/Option payload-shape matrix.
// On v0.64.0 a Result/Option whose payload is DIRECTLY a Vec[non-scalar]
// lost element field data at the caller; v0.64.1 fixed it and the engine
// still wraps search hits (SearchHits) as a defensive boundary. This probe
// gates every shape on every build, plus the real engine path, so the
// wrapper can be unwound deliberately later if the family stays stable.
// Exit = failed checks.

module probe_result_shapes

use xiom.vector.engine;
use xiom.vector.engine.core;
use xiom.vectors;
use xiom.io;
use xiom.num.float;

pub type SR = {
  id: Int;
  distance: Float32;
}

pub enum CE {
  A,
  B,
}

pub enum SE {
  A,
  B,
  Bad(msg: Str),
}

pub type Hits = {
  items: Vec[SR];
}

pub fn r_scalar_int() -> Result[Int, CE] {
  return Ok(99);
}

pub fn r_struct() -> Result[SR, CE] {
  return Ok(SR{ id: 42, distance: 1.5 });
}

pub fn r_vec_int() -> Result[Vec[Int], CE] {
  var v = Vec[Int].new();
  v.push(7);
  v.push(8);
  return Ok(v);
}

pub fn r_vec_str() -> Result[Vec[Str], CE] {
  var v = Vec[Str].new();
  v.push("alpha");
  return Ok(v);
}

pub fn r_vec_struct_unit_err() -> Result[Vec[SR], CE] {
  var v = Vec[SR].new();
  v.push(SR{ id: 42, distance: 1.5 });
  return Ok(v);
}

pub fn r_vec_struct_str_err() -> Result[Vec[SR], SE] {
  var v = Vec[SR].new();
  v.push(SR{ id: 42, distance: 1.5 });
  return Ok(v);
}

pub fn o_vec_struct() -> Option[Vec[SR]] {
  var v = Vec[SR].new();
  v.push(SR{ id: 42, distance: 1.5 });
  return Some(v);
}

pub fn r_wrapped() -> Result[Hits, CE] {
  var v = Vec[SR].new();
  v.push(SR{ id: 42, distance: 1.5 });
  return Ok(Hits{ items: v });
}

fn int_to_str(n: Int) -> Str {
  if n == 0 { return "0"; }
  var num = n; var out = ""; var neg = false;
  if num < 0 { neg = true; num = 0 - num; }
  while num > 0 {
    let d = num % 10; var ds = "0";
    if d == 1 { ds = "1"; } elif d == 2 { ds = "2"; } elif d == 3 { ds = "3"; }
    elif d == 4 { ds = "4"; } elif d == 5 { ds = "5"; } elif d == 6 { ds = "6"; }
    elif d == 7 { ds = "7"; } elif d == 8 { ds = "8"; } elif d == 9 { ds = "9"; }
    out = ds + out; num = num / 10;
  }
  if neg { out = "-" + out; }
  return out;
}

fn check(ok: Bool, name: Str, fails: Int) -> Int {
  if ok { io.println("  [PASS] " + name); return fails; }
  io.println("  [FAIL] " + name); return fails + 1;
}

fn bits15() -> Int {
  return float.float_bits(1.5 as Float64);
}

fn main() -> Int {
  io.println("=== xvector probe: Result/Option payload shapes (XVC-C-04 pin) ===");
  var fails: Int = 0;

  match r_scalar_int() {
    Ok(x) => { fails = check(x == 99, "Result[Int]: scalar survives", fails); }
    Err(_) => { fails = check(false, "Result[Int] -> Ok", fails); }
  }
  match r_struct() {
    Ok(s) => { fails = check(s.id == 42 && float.float_bits(s.distance as Float64) == bits15(),
      "Result[SR]: struct fields survive", fails); }
    Err(_) => { fails = check(false, "Result[SR] -> Ok", fails); }
  }
  match r_vec_int() {
    Ok(v) => { fails = check(v.len() == 2 && v[0] == 7 && v[1] == 8,
      "Result[Vec[Int]]: scalars survive", fails); }
    Err(_) => { fails = check(false, "Result[Vec[Int]] -> Ok", fails); }
  }
  match r_vec_str() {
    Ok(v) => { fails = check(v.len() == 1 && v[0] == "alpha",
      "Result[Vec[Str]]: text survives", fails); }
    Err(_) => { fails = check(false, "Result[Vec[Str]] -> Ok", fails); }
  }
  match r_vec_struct_unit_err() {
    Ok(v) => { fails = check(v.len() == 1 && v[0].id == 42 && float.float_bits(v[0].distance as Float64) == bits15(),
      "Result[Vec[SR], unit-err]: element fields survive (C-04 shape)", fails); }
    Err(_) => { fails = check(false, "Result[Vec[SR], CE] -> Ok", fails); }
  }
  match r_vec_struct_str_err() {
    Ok(v) => { fails = check(v.len() == 1 && v[0].id == 42 && float.float_bits(v[0].distance as Float64) == bits15(),
      "Result[Vec[SR], str-err]: element fields survive (C-04 shape)", fails); }
    Err(_) => { fails = check(false, "Result[Vec[SR], SE] -> Ok", fails); }
  }
  match o_vec_struct() {
    Some(v) => { fails = check(v.len() == 1 && v[0].id == 42 && float.float_bits(v[0].distance as Float64) == bits15(),
      "Option[Vec[SR]]: element fields survive (C-04 shape)", fails); }
    None => { fails = check(false, "Option[Vec[SR]] -> Some", fails); }
  }
  match r_wrapped() {
    Ok(h) => { fails = check(h.items.len() == 1 && h.items[0].id == 42,
      "Result[Hits{items}]: wrapper control", fails); }
    Err(_) => { fails = check(false, "Result[Hits] -> Ok", fails); }
  }

  // Real engine path: wrapper + facade boundary + exact f32 distance bits.
  var eng = engine_new();
  create_collection(&mut eng, 2, DistanceMetric.Euclidean);
  var p1 = Vector.new(2);
  p1.set(0, 3.0); p1.set(1, 0.0);
  var p2 = Vector.new(2);
  p2.set(0, 0.0); p2.set(1, 4.0);
  upsert(&mut eng, 1, p1);
  upsert(&mut eng, 2, p2);
  var q = Vector.new(2);
  q.set(0, 0.0); q.set(1, 0.0);
  match search(&eng, &q, 2) {
    Ok(h) => {
      var d0 = float.float_bits(h.items[0].distance as Float64);
      var d1 = float.float_bits(h.items[1].distance as Float64);
      fails = check(h.items.len() == 2 && h.items[0].id == 1 && h.items[1].id == 2
        && d0 == float.float_bits(3.0 as Float64) && d1 == float.float_bits(4.0 as Float64),
        "engine search: ids + exact f32 distance bits survive the wrapper", fails);
    }
    Err(_) => { fails = check(false, "engine search -> Ok (extra failures counted above)", fails + 1); }
  }

  io.println("");
  io.println("probe_result_shapes: " + int_to_str(fails) + " failed checks");
  return fails;
}
