// C-ORBIT-11 minimal repro, module A: declares Box2 with `xs` plus a Vec of
// its own type; `deep` infers a local's type from the vector element and
// then does a field-method call on it -- the engine's
// `child = tree.store.nodes[idx]; child.payloads.pop()` shape.
module mod_a

pub type Box2 = {
  xs: Vec[Int];
  kids: Vec[Box2];
}

pub fn make_a() -> Box2 {
  var b = Box2{ xs: Vec[Int].new(), kids: Vec[Box2].new() };
  var kid = Box2{ xs: Vec[Int].new(), kids: Vec[Box2].new() };
  b.kids.push(kid);
  return b;
}

pub fn fill(b: &mut Box2) -> Int {
  b.xs.push(7);
  return b.xs.len();
}

pub fn deep(b: &mut Box2) -> Int {
  if b.kids.len() == 0 { return 0; }
  var c = b.kids[0];
  c.xs.push(9);
  return c.xs.len();
}
