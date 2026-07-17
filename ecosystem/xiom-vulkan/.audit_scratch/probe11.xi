// probe11 — minimal Float64 vec literal read
module probe11

fn main() -> Int {
  let a: Vec[Float64] = [1.5, 2.5];
  if a[0] != 1.5 { return 1; }
  return 0;
}
