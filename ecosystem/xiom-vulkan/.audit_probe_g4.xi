// G4 probe: are Float Vec element reads fixed in v0.47.2?
module probe_g4
fn main() -> Int {
  let a: Vec[Float64] = [1.5, 2.5, 3.5];
  if a[0] != 1.5 { return 1; }
  let c = Vec[Float64].new(); c.push(3.5);
  if c[0] != 3.5 { return 2; }
  let e = Vec[Float32].new(); e.push(6.5); let e0: Float32 = e[0];
  if e0 != 6.5 { return 3; }
  return 0;
}
