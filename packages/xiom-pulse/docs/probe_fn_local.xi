module probe_fn_local

pub type Holder = {
  installed: Bool;
  run: fn(Int) -> Int;
}

fn inc(x: Int) -> Int { return x + 1; }
fn dbl(x: Int) -> Int { return x * 2; }

pub fn main() -> Int {
  let hook: fn(Int) -> Int = inc;
  let a: Int = hook(3);
  if a != 4 { return 10; }
  let h2: fn(Int) -> Int = dbl;
  var holder: Holder = Holder{ installed: false; run: inc };
  holder.installed = true;
  holder.run = h2;
  let h = holder.run;
  let c: Int = h(4);
  if c != 8 { return 13; }
  if !holder.installed { return 14; }
  return 0;
}
