module probe_fn_scalar

fn inc(x: Int) -> Int { return x + 1; }
fn dbl(x: Int) -> Int { return x * 2; }

var hook: fn(Int) -> Int = inc;

pub fn main() -> Int {
  let a: Int = hook(3);
  if a != 4 { return 10; }
  hook = dbl;
  let b: Int = hook(3);
  if b != 6 { return 11; }
  return 0;
}
