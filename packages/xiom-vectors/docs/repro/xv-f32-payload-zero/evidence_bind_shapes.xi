module probe_filter_bind

use xiom.io;

pub enum FV { I(v: Int), T(v: Str), }
pub enum E { Eq(f: Str, value: FV), Range(f: Str, lo: Float32, hi: Float32), }
pub type PF = { key: Str; value: FV; }
pub type P = { fields: Vec[PF]; }

fn fv_eq(a: &FV, b: &FV) -> Bool {
  match a {
    I(av) => { match b { I(bv) => { return av == bv; } _ => { return false; } } }
    T(av) => { match b { T(bv) => { return av == bv; } _ => { return false; } } }
  }
}

fn pget(p: &P, key: Str) -> Option[FV] {
  var i: Int = 0;
  while i < p.fields.len() {
    if p.fields[i].key == key { return Some(p.fields[i].value); }
    i = i + 1;
  }
  return None;
}

fn eq_arm_nested(e: &E, p: &P) -> Bool {
  match e {
    Eq(f, value) => {
      match pget(p, f) {
        Some(fv) => { return fv_eq(&fv, &value); }
        None => { return false; }
      }
    }
    Range(f, lo, hi) => { return false; }
  }
}

fn range_arm_nested(e: &E, p: &P) -> Bool {
  match e {
    Range(f, lo, hi) => {
      match pget(p, f) {
        Some(fv) => {
          match fv {
            I(n) => { var x = n as Float32; return x >= lo && x <= hi; }
            T(_) => { return false; }
          }
        }
        None => { return false; }
      }
    }
    Eq(f, value) => { return false; }
  }
}

fn main() -> Int {
  var p = P{ fields: Vec[PF].new() };
  p.fields.push(PF{ key: "color", value: FV.T("red") });
  var e = E.Eq("color", FV.T("red"));
  if !eq_arm_nested(&e, &p) { return 1; }
  var p2 = P{ fields: Vec[PF].new() };
  p2.fields.push(PF{ key: "n", value: FV.I(5) });
  var e2 = E.Range("n", 1.0, 10.0);
  if !range_arm_nested(&e2, &p2) { return 2; }
  return 0;
}
