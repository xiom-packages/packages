// C-ORBIT-13 repro: `&mut` on a >=3-level nested field path silently passes
// a COPY for Int and nested-struct fields (Vec element writes still leak
// through the shared buffer). Two-level paths work.
//
// Compiler: v0.64.8 (fixed) / v0.64.7 (defect). Expected on v0.64.8: all
// three cases PASS. Observed on v0.64.7: the two-level control PASSes, the
// three-level case prints n=1 g=0 v=1 and FAILs (only the Vec write
// survived). This file is the regression probe for C-ORBIT-13.
//
// Impact: ORBITDB M1.1b pager spills/commits via `&mut tree.store.bs`
// (3 levels) wrote blocks at a stale block_count and dropped the header
// update -- the checkpoint looked committed but the pager's directory was
// stale and keys were lost on reopen. Workaround: copy the nested struct to
// a local, mutate the local, write it back (`tree.store.bs = bsw`).
module orbitdb_repro_nested_mut_path

use xiom.io;
use xiom.convert;

pub type H = { g: Int; }
pub type BS = { n: Int; h: H; v: Vec[Int]; }
pub type NS = { bs: BS; }
pub type T = { store: NS; }
pub type Two = { bs: BS; }

pub fn bump(x: &mut BS) {
  x.n = x.n + 1;
  x.h.g = x.h.g + 10;
  x.v[0] = x.v[0] + 1;
}

// Two levels: works.
pub fn flush_two(t: &mut Two) {
  bump(&mut t.bs);
}

// Three levels: `&mut t.store.bs` is copied for scalar/struct fields.
pub fn flush_three(t: &mut T) {
  bump(&mut t.store.bs);
}

// Workaround: local copy + write-back.
pub fn flush_three_fixed(t: &mut T) {
  var bsw = t.store.bs;
  bump(&mut bsw);
  t.store.bs = bsw;
}

fn main() -> Int {
  var v2 = Vec[Int].new();
  v2.push(0);
  var two = Two{ bs: BS{ n: 1, h: H{ g: 0 }, v: v2 } };
  flush_two(&mut two);
  io.println("two-level: n=" + convert.int_to_string(two.bs.n)
    + " g=" + convert.int_to_string(two.bs.h.g)
    + " v=" + convert.int_to_string(two.bs.v[0]));
  let two_ok = two.bs.n == 2 && two.bs.h.g == 10 && two.bs.v[0] == 1;
  if two_ok { io.println("two-level: PASS"); } else { io.println("two-level: FAIL"); }

  var v3 = Vec[Int].new();
  v3.push(0);
  var three = T{ store: NS{ bs: BS{ n: 1, h: H{ g: 0 }, v: v3 } } };
  flush_three(&mut three);
  io.println("three-level: n=" + convert.int_to_string(three.store.bs.n)
    + " g=" + convert.int_to_string(three.store.bs.h.g)
    + " v=" + convert.int_to_string(three.store.bs.v[0]));
  let three_ok = three.store.bs.n == 2 && three.store.bs.h.g == 10
    && three.store.bs.v[0] == 1;
  if three_ok { io.println("three-level: PASS"); } else { io.println("three-level: FAIL"); }

  var vf = Vec[Int].new();
  vf.push(0);
  var fixed = T{ store: NS{ bs: BS{ n: 1, h: H{ g: 0 }, v: vf } } };
  flush_three_fixed(&mut fixed);
  io.println("workaround: n=" + convert.int_to_string(fixed.store.bs.n)
    + " g=" + convert.int_to_string(fixed.store.bs.h.g)
    + " v=" + convert.int_to_string(fixed.store.bs.v[0]));
  let fixed_ok = fixed.store.bs.n == 2 && fixed.store.bs.h.g == 10
    && fixed.store.bs.v[0] == 1;
  if fixed_ok { io.println("workaround: PASS"); } else { io.println("workaround: FAIL"); }

  if two_ok && three_ok && fixed_ok { return 0; }
  return 1;
}
