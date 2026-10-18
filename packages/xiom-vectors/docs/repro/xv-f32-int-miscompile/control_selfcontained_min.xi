// Minimal repro: does the same source always compile to the same numeric
// behavior? Expected: dot = 0.9 (bits 4606281698659794944), exit 0.
// Observed (v0.64.0): some builds print an address-like garbage value and
// exit 1 -- compile-level nondeterminism.
module probe_nondet_codegen

use xiom.io;
use xiom.num.float;

pub type V = {
  data: Vec[Float32];
  dimension: Int;
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

fn vnew(dim: Int) -> V {
  var data = Vec[Float32].new();
  var i: Int = 0;
  while i < dim {
    data.push(0.0);
    i = i + 1;
  }
  return V{ data: data, dimension: dim };
}

fn vset(v: &mut V, index: Int, value: Float32) {
  v.data[index] = value;
}

fn dot(a: &V, b: &V) -> Float32 {
  var sum: Float32 = 0.0;
  var i: Int = 0;
  while i < a.dimension {
    sum = sum + a.data[i] * b.data[i];
    i = i + 1;
  }
  return sum;
}

fn mk(a: Float32, b: Float32, c: Float32) -> V {
  var v = vnew(3);
  vset(&mut v, 0, a);
  vset(&mut v, 1, b);
  vset(&mut v, 2, c);
  return v;
}

fn main() -> Int {
  var p = mk(0.9, 0.1, 0.0);
  var q = mk(1.0, 0.0, 0.0);
  let d = dot(&p, &q);
  let b = float.float_bits(d as Float64);
  io.println("dot bits=" + int_to_str(b) + " p0=" + int_to_str(float.float_bits(p.data[0] as Float64)));
  if b == 4606281698659794944 { return 0; }
  return 1;
}
