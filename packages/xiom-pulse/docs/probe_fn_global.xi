// Probe: a module-global fn-typed variable is accepted by the type checker
// but fails codegen at 0.64.6 (undefined @__fnwrap / malformed top-level IR).
module probe_fn_global

fn inc(x: Int) -> Int { return x + 1; }

var hook: fn(Int) -> Int = inc;

pub fn main() -> Int {
  return hook(1);
}
