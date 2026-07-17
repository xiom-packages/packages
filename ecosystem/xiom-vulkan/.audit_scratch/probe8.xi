// probe8 — which Vec element paths survive codegen on v0.46
module probe8

fn main() -> Int {
  // 1. Vec[Int] literal + read
  let a: Vec[Int] = [10, 20, 30];
  if a[0] != 10 { return 1; }
  if a[2] != 30 { return 2; }

  // 2. Vec[Int] push + read
  var b = Vec[Int].new();
  b.push(40);
  b.push(50);
  if b[0] != 40 { return 3; }
  if b[1] != 50 { return 4; }

  // 3. Vec[Int32] literal + annotated read
  let c: Vec[Int32] = [7, 8, 9];
  let c0: Int32 = c[0];
  if c0 != 7 { return 5; }

  // 4. Vec[Int32] push + annotated read
  var d = Vec[Int32].new();
  d.push(11);
  d.push(12);
  let d1: Int32 = d[1];
  if d1 != 12 { return 6; }

  // 5. Vec[UInt16] literal + read
  let e: Vec[UInt16] = [1, 2, 3];
  let e1: UInt16 = e[1];
  if e1 != 2 { return 7; }

  // 6. Vec[Float64] literal + read
  let f: Vec[Float64] = [1.5, 2.5];
  let f0: Float64 = f[0];
  if f0 != 1.5 { return 8; }

  // 7. Vec[Float64] push + read
  var g = Vec[Float64].new();
  g.push(4.5);
  let g0: Float64 = g[0];
  if g0 != 4.5 { return 9; }

  // 8. Vec[Float32] push + read
  var h = Vec[Float32].new();
  h.push(6.5);
  let h0: Float32 = h[0];
  if h0 != 6.5 { return 10; }

  // 9. Vec[Float32] literal + read (known-bad candidate)
  let i: Vec[Float32] = [7.5, 8.5];
  let i0: Float32 = i[0];
  if i0 != 7.5 { return 11; }

  return 0;
}
