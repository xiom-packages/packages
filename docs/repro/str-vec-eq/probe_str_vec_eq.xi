// `Str` equality on `Vec[Str]` elements -- current-status probe.
//
// COMPILER-FINDINGS trap (2026-09-25): `==`/`!=` on `Str` values read from
// `Vec[Str]` elements were reported to compare pointers, so equal text
// compared unequal; the repo routes such checks through
// `xiom.string.compare.str_compare`.
//
// Expected if the trap is STILL present: `elem==elem` and/or
// `elem==literal` print false although the text is equal (`bad > 0`).
// Expected if FIXED: all four checks pass (`bad=0`).
//
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module str_vec_eq_probe

use xiom.io;
use xiom.convert;
use xiom.string;
use xiom.string.compare;

fn main() -> Int {
  var bad = 0;

  var v: Vec[Str] = Vec[Str].new();
  v.push("alpha");
  v.push("alpha");
  let e0 = v[0];
  let e1 = v[1];

  if e0 == e1 {
    io.println("elem==elem: true");
  } else {
    io.println("elem==elem: false (pointer compare?)");
    bad = bad + 1;
  }

  if e0 == "alpha" {
    io.println("elem==literal: true");
  } else {
    io.println("elem==literal: false (pointer compare?)");
    bad = bad + 1;
  }

  if compare.str_compare(e0, e1) == 0 {
    io.println("str_compare: equal");
  } else {
    io.println("str_compare: unequal");
    bad = bad + 1;
  }

  // Runtime-built string (fresh pointer): content compare must still pass.
  v.push("al");
  v.push("pha");
  let joined = v[2] + v[3];
  if joined == "alpha" {
    io.println("derived==literal: true");
  } else {
    io.println("derived==literal: false (pointer compare!)");
    bad = bad + 1;
  }
  if compare.str_compare(joined, "alpha") == 0 {
    io.println("derived str_compare: equal");
  } else {
    io.println("derived str_compare: unequal");
    bad = bad + 1;
  }

  if string.str_len(e0) == 5 {
    io.println("str_len(elem): 5");
  } else {
    io.println("str_len(elem): wrong (" + int_to_string(string.str_len(e0)) + ")");
    bad = bad + 1;
  }

  io.println("bad=" + int_to_string(bad));
  return bad;
}
