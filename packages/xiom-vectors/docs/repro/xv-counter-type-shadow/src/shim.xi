// XVC-C-14 repro, module A -- a user-defined Counter type (the role the
// xvector core shim played before the xiom.metrics adoption). Shares only
// the short name `Counter` with xiom.metrics' package type.
module repro.shim

pub type Counter = {
  name: Str;
  value: Int;
}

pub fn counter_new(name: Str) -> Counter {
  return Counter{ name: name, value: 0 };
}

pub fn counter_inc(c: &mut Counter) {
  c.value = c.value + 1;
}
