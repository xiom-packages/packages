module probe_bisect_a

use xiom.vector.engine;
use xiom.vector.engine.core;
use xiom.vectors;
use xiom.vector.query.search_service;
use xiom.io;
use xiom.num.float;

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

fn check(ok: Bool, name: Str, fails: Int) -> Int {
  if ok { io.println("  [PASS] " + name); return fails; }
  io.println("  [FAIL] " + name); return fails + 1;
}

fn f32_approx(a: Float32, b: Float32, eps: Float32) -> Bool {
  var diff = a - b;
  if diff < 0.0 { diff = -diff; }
  return diff < eps;
}

fn main() -> Int {
  var fails: Int = 0;
  var eng = engine_new();
  var cid = create_collection(&mut eng, 3, DistanceMetric.Cosine);
  match cid { Ok(_) => {} Err(_) => { fails = fails + 1; } }
  upsert(&mut eng, 1, mk_vec3(1.0, 0.0, 0.0));
  upsert(&mut eng, 2, mk_vec3(0.9, 0.1, 0.0));
  upsert(&mut eng, 3, mk_vec3(0.0, 0.0, 1.0));
  var query = mk_vec3(1.0, 0.0, 0.0);
  var before = Vec[SearchResult].new();
  match search(&eng, &query, 2) {
    Ok(h) => { before = h.items; }
    Err(_) => { fails = fails + 1; }
  }
  io.println("    diag len=" + int_to_str(before.len()) +
             " d1_bits=" + int_to_str(float.float_bits(before[1].distance as Float64)));
  var ok: Bool = before.len() == 2 && before[0].id == 1 && before[1].id == 2
    && f32_approx(before[0].distance, 0.0, 0.001) && f32_approx(before[1].distance, 0.00614, 0.001);
  fails = check(ok, "search top-2 -> {1, 2} with distances", fails);
  io.println("probe_bisect_a: " + int_to_str(fails) + " failed");
  return fails;
}
