// Variant B: store the param into a local aggregate (Vec) then call.
module probe_fnptr_local

fn seven() -> Int { return 7; }

fn call_local(f: &fn() -> Int) -> Int {
  var g: fn() -> Int = *f;
  return g();
}

fn main() -> Int {
  var x: Int = call_local(&seven);
  if x == 7 { return 0; }
  return 1;
}
