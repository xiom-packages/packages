// Pin probe: on v0.64.0, matching a `&Enum` binds unit payloads BY VALUE
// (a `match x { I(v) => ... }` with `x: &FV` gives `v: Int`, so `&v`
// produces a valid `&Int`). The by-reference bind variant fails T001
// ("expected FV, found Int" at `take_ref(&v)`).
module probe_bind_semantics

pub enum FV { I(v: Int), T(v: Str), }

fn take_int(x: Int) -> Int { return x; }

fn extract(x: &FV) -> Int {
  match x {
    I(v) => { return take_int(v); }
    T(_) => { return 0; }
  }
}

fn main() -> Int {
  var a = FV.I(7);
  var b = FV.T("s");
  if extract(&a) == 7 && extract(&b) == 0 { return 0; }
  return 1;
}
