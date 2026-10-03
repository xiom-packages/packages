// Uninitialized-local struct corruption probe (v0.62.3).
//
// Found while restoring `xiom.graphql`: `var root: GraphQLType;` followed by
// assignment inside a match arm produced garbage (Str pointers that hung on
// concatenation; `Vec.len()` 4294967295 -> runaway loops). Pre-initializing
// the local avoids it.
//
// The corrupt value is never printed (it can crash/hang); the probe reports
// only status strings so the run stays safe. Expected after the fix:
// `preinit=ok`, `uninit=ok`, `bad=0`, exit 0. Before the fix the uninit
// variant yields `uninit=corrupt` or a crash after the preinit line.
//
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module uninit_local_probe

use xiom.io;
use xiom.convert;

pub type Box = {
  name: Str;
  values: Vec[Int];
}

fn make_box() -> Box {
  var b: Box = Box{ name: "ok", values: Vec[Int].new() };
  b.values.push(7);
  return b;
}

fn copy_via_uninit_match() -> Int {
  var src: Box = make_box();
  var opt: Option[Box] = Some(src);
  var dst: Box;
  match opt {
    Some(x) => { dst = x; },
    None => { return -1; },
  };
  return dst.values.len();
}

fn copy_preinit_match() -> Int {
  var src: Box = make_box();
  var opt: Option[Box] = Some(src);
  var dst: Box = Box{ name: "", values: Vec[Int].new() };
  match opt {
    Some(x) => { dst = x; },
    None => { return -1; },
  };
  return dst.values.len();
}

fn main() -> Int {
  var bad = 0;

  let b = copy_preinit_match();
  if b == 1 {
    io.println("preinit=ok");
  } else {
    io.println("preinit=corrupt");
    bad = bad + 1;
  }

  let a = copy_via_uninit_match();
  if a == 1 {
    io.println("uninit=ok");
  } else {
    io.println("uninit=corrupt");
    bad = bad + 1;
  }

  io.println("bad=" + int_to_string(bad));
  return bad;
}
