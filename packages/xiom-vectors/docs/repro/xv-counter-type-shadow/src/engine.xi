// XVC-C-14 repro, module B -- a struct whose field type is the module-A
// Counter (resolved inside this module through the shim import alone).
module repro.engine

use repro.shim;

pub type Eng = {
  upserts: Counter;
}

pub fn eng_new() -> Eng {
  return Eng{ upserts: counter_new("eng.upserts") };
}

pub fn eng_up(e: &mut Eng) {
  counter_inc(&mut e.upserts);
}
