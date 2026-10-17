// Probe: adjacent fn-typed struct fields are laid out incorrectly at
// 0.64.6. Installing the second hook overwrites the first pointer, so the
// pre hook call returns garbage (here: exit 10 instead of 0).
module probe_two_hooks

pub type R = {
  a: Int;
}

pub type Hs = {
  pre_on: Bool;
  pre: fn(Int) -> R;
  after_on: Bool;
  after: fn(Int) -> Int;
}

fn pre_default(x: Int) -> R { return R{ a: x }; }
fn pre_real(x: Int) -> R { return R{ a: x + 1 }; }
fn after_default(x: Int) -> Int { return x; }
fn after_real(x: Int) -> Int { return x + 2; }

fn mk() -> Hs {
  return Hs{ pre_on: false; pre: pre_default; after_on: false; after: after_default };
}

pub fn main() -> Int {
  var hs = mk();
  hs.pre_on = true;
  hs.pre = pre_real;
  hs.after_on = true;
  hs.after = after_real;
  let pf = hs.pre;
  let af = hs.after;
  if pf(4).a != 5 { return 10; }
  if af(4) != 6 { return 11; }
  return 0;
}
