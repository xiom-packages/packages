// probe15 — push-built float vec element reads + .data to C
module probe15

extern "C" {
  fn xvk_recv_f32s(data: Int, count: Int);
}

fn main() -> Int {
  // A. Float64 push + read
  var c = Vec[Float64].new();
  c.push(3.5);
  let c0: Float64 = c[0];
  if c0 != 3.5 { return 1; }

  // B. Float32 push + read
  var e = Vec[Float32].new();
  e.push(6.5);
  let e0: Float32 = e[0];
  if e0 != 6.5 { return 2; }

  // C. Float32 push-built .data to C
  var f = Vec[Float32].new();
  f.push(1.5);
  f.push(2.5);
  f.push(3.5);
  unsafe { xvk_recv_f32s(f.data, f.len()); }

  return 0;
}
