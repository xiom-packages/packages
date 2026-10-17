module probe_fn_vec

fn inc(x: Int) -> Int { return x + 1; }
fn dbl(x: Int) -> Int { return x * 2; }

var hooks: Vec[fn(Int) -> Int] = Vec[fn(Int) -> Int].new();

pub fn main() -> Int {
  hooks.push(inc);
  hooks.push(dbl);
  let a: Int = hooks[0](3);
  if a != 4 { return 10; }
  let b: Int = hooks[1](3);
  if b != 6 { return 11; }
  return 0;
}
