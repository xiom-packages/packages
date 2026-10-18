module probe_debug_cosine

use xiom.vector.engine;
use xiom.vector.engine.core;
use xiom.vectors;
use xiom.io;
use xiom.num.float;
use xiom.math;

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
fn bits(f: Float32) -> Int { return float.float_bits(f as Float64); }
fn mk_vec3(a: Float32, b: Float32, c: Float32) -> Vector {
  var v = Vector.new(3);
  v.set(0, a); v.set(1, b); v.set(2, c);
  return v;
}
fn main() -> Int {
  var eng = engine_new();
  create_collection(&mut eng, 3, DistanceMetric.Cosine);
  upsert(&mut eng, 1, mk_vec3(1.0, 0.0, 0.0));
  upsert(&mut eng, 2, mk_vec3(0.9, 0.1, 0.0));
  upsert(&mut eng, 3, mk_vec3(0.0, 0.0, 1.0));
  var q = mk_vec3(1.0, 0.0, 0.0);
  io.println("q bits: " + int_to_str(bits(q.data[0])) + " " + int_to_str(bits(q.data[1])) + " " + int_to_str(bits(q.data[2])));
  match get_point(&eng, 2) {
    Some(v) => {
      io.println("p2 bits: " + int_to_str(bits(v.data[0])) + " " + int_to_str(bits(v.data[1])) + " " + int_to_str(bits(v.data[2])));
      io.println("p2 dot q = " + int_to_str(bits(vector_dot(&v, &q))));
      io.println("p2 mag   = " + int_to_str(bits(vector_magnitude(&v))));
      io.println("q  mag   = " + int_to_str(bits(vector_magnitude(&q))));
      io.println("p2 cosdist q = " + int_to_str(bits(cosine_distance(&v, &q))));
      io.println("p2 eucdist q = " + int_to_str(bits(euclidean_distance(&v, &q))));
    }
    None => { io.println("p2 missing"); }
  }
  match search(&eng, &q, 3) {
    Ok(h) => {
      var i: Int = 0;
      while i < h.items.len() {
        io.println("hit " + int_to_str(i) + ": id=" + int_to_str(h.items[i].id) + " dist_bits=" + int_to_str(bits(h.items[i].distance)));
        i = i + 1;
      }
    }
    Err(_) => {}
  }
  return 0;
}
