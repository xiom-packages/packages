// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// `&mut Int` write-through battery. v0.61.3 is reported to miscompile
// write-through updates to `&mut Int` out-parameters (xiom.upnp replaced its
// out-params with a value-returning `VersionParts`; documented in
// xiom-optimizer). All variants run; `bad` counts failures.
//   1 plain call, single out-param                (gbnf-style shape)
//   2 plain call, two out-params                   (upnp-style shape)
//   3 read-modify-write through the out-param
//   4 write in a branch + returned Bool
//   5 repeated plain call in a loop
//   6 explicit `&mut` at the call site, single out-param
//   7 explicit `&mut` at the call site, two out-params
// Exit 0 = all writes visible; nonzero = number of failing variants.
// Expected once fixed: exit 0.
module probe_out_params

use xiom.convert;
use xiom.io;

fn set_one(out: &mut Int) {
  *out = 7;
}

fn split2(v: Int, a: &mut Int, b: &mut Int) {
  *a = v / 2;
  *b = v - (v / 2);
}

fn bump(out: &mut Int) {
  *out = *out + 1;
}

fn set_even(out: &mut Int, x: Int) -> Bool {
  if (x % 2) == 0 {
    *out = x;
    return true;
  }
  return false;
}

fn main() -> Int {
  var bad = 0;

  var x = 0;
  set_one(x);
  io.println("plain set_one: " + int_to_string(x));
  if (x != 7) { bad = bad + 1; }

  var a = 0;
  var b = 0;
  split2(10, a, b);
  io.println("plain split2: " + int_to_string(a) + "," + int_to_string(b));
  if (a != 5) { bad = bad + 1; }
  if (b != 5) { bad = bad + 1; }

  var c = 41;
  bump(c);
  io.println("bump: " + int_to_string(c));
  if (c != 42) { bad = bad + 1; }

  var d = 0;
  let ok = set_even(d, 8);
  if (ok) {
    io.println("set_even: " + int_to_string(d) + " ok");
  } else {
    io.println("set_even: " + int_to_string(d) + " not ok");
    bad = bad + 1;
  }
  if (d != 8) { bad = bad + 1; }

  var acc = 0;
  var i = 0;
  while i < 5 {
    bump(acc);
    i = i + 1;
  }
  io.println("loop bump: " + int_to_string(acc));
  if (acc != 5) { bad = bad + 1; }

  var e = 0;
  set_one(&mut e);
  io.println("explicit set_one: " + int_to_string(e));
  if (e != 7) { bad = bad + 1; }

  var g = 0;
  var h = 0;
  split2(10, &mut g, &mut h);
  io.println("explicit split2: " + int_to_string(g) + "," + int_to_string(h));
  if (g != 5) { bad = bad + 1; }
  if (h != 5) { bad = bad + 1; }

  io.println("bad=" + int_to_string(bad));
  return bad;
}
