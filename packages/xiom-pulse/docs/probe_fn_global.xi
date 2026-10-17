module probe_fn_global

pub type Holder = {
  installed: Bool;
  run: fn(Int) -> Int;
}

fn inc(x: Int) -> Int { return x + 1; }
fn dbl(x: Int) -> Int { return x * 2; }

var hook: fn(Int) -> Int = inc;
var holder: Holder = Holder{ installed: false; run: inc };

pub fn main() -> Int {
  let a: Int = hook(3);
  if a != 4 { return 10; }
  hook = dbl;
  let b: Int = hook(3);
  if b != 6 { return 11; }
  holder = Holder{ installed: true; run: dbl };
  if !holder.installed { return 12; }
  let h = holder.run;
  let c: Int = h(4);
  if c != 8 { return 13; }
  return 0;
}
