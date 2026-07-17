// probe10 — float Vec element access matrix
module probe10

fn main() -> Int {
  // A. Float64 literal, direct compare (no annotation)
  let a: Vec[Float64] = [1.5, 2.5];
  if a[0] != 1.5 { return 1; }

  // B. Float64 unannotated literal binding
  let b = [1.5, 2.5];
  if b[0] != 1.5 { return 2; }

  // C. Float64 push, direct compare
  var c = Vec[Float64].new();
  c.push(3.5);
  if c[0] != 3.5 { return 3; }

  // D. Float32 literal, direct compare
  let d: Vec[Float32] = [4.5, 5.5];
  if d[0] != 4.5 { return 4; }

  // E. Float32 push, direct compare
  var e = Vec[Float32].new();
  e.push(6.5);
  if e[0] != 6.5 { return 5; }

  return 0;
}
