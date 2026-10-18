// Minimal repro: calling a function-pointer parameter (`&fn() -> T`).
module probe_fnptr

fn seven() -> Int { return 7; }

fn call_ref(f: &fn() -> Int) -> Int {
  return f();
}

fn main() -> Int {
  var x: Int = call_ref(&seven);
  if x == 7 { return 0; }
  return 1;
}
