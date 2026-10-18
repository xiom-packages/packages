module probe_debug_search

use xiom.vector.engine;
use xiom.vector.engine.core;
use xiom.vectors;
use xiom.vector.query.search_service;
use xiom.io;

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
fn mk_vec3(a: Float32, b: Float32, c: Float32) -> Vector {
  var v = Vector.new(3);
  v.set(0, a); v.set(1, b); v.set(2, c);
  return v;
}
fn f32_approx(a: Float32, b: Float32, eps: Float32) -> Bool {
  var diff = a - b;
  if diff < 0.0 { diff = -diff; }
  return diff < eps;
}
fn main() -> Int {
  var eng = engine_new();
  create_collection(&mut eng, 3, DistanceMetric.Cosine);
  upsert(&mut eng, 1, mk_vec3(1.0, 0.0, 0.0));
  upsert(&mut eng, 2, mk_vec3(0.9, 0.1, 0.0));
  upsert(&mut eng, 3, mk_vec3(0.0, 0.0, 1.0));
  var q = mk_vec3(1.0, 0.0, 0.0);
  var hits = Vec[SearchResult].new();
  match search(&eng, &q, 2) {
    Ok(h) => { hits = h.items; }
    Err(_) => { return 9; }
  }
  if hits.len() != 2 { return 1; }
  if hits[0].id != 1 { return 2; }
  if hits[1].id != 2 { return 3; }
  if !f32_approx(hits[0].distance, 0.0, 0.001) { return 4; }
  if !f32_approx(hits[1].distance, 0.00614, 0.001) { return 5; }
  io.println("search-check: green");
  return 0;
}
