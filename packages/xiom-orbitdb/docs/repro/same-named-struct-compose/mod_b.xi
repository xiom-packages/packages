// C-ORBIT-11 minimal repro, module B: its own Box2 (different field set).
module mod_b

pub type Box2 = {
  ys: Vec[Int];
}

pub fn make_b() -> Box2 {
  var b = Box2{ ys: Vec[Int].new() };
  return b;
}

pub fn fill2(b: &mut Box2) -> Int {
  b.ys.push(8);
  return b.ys.len();
}
