// Probe: a fn-typed alias used as a callable parameter is accepted by the
// type checker but miscompiled at codegen/runtime (0.64.6). The same call
// with the direct fn type in the signature works.
module probe_fn_alias

pub type F = fn(Int) -> Int;

fn inc(x: Int) -> Int { return x + 1; }

fn install(v: &mut Vec[fn(Int) -> Int], f: F) {
  v.push(f);
}

pub fn main() -> Int {
  var v: Vec[fn(Int) -> Int] = Vec[fn(Int) -> Int].new();
  install(&mut v, inc);
  let f = v[0];
  let n: Int = f(4);
  if n != 5 { return 10; }
  return 0;
}
