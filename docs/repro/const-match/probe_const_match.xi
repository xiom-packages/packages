// Const-pattern match probe (v0.62.3).
//
// Found in `xiom.grpc`: `status_to_str` matches an Int against `pub const`
// Int values and always falls through to the wildcard arm (every code
// printed "UNKNOWN").
//
// Expected after the fix: `two=two`, `bad=0`, exit 0.
// On v0.62.3: `two=other` (const arm never matches).
//
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module const_match_probe

use xiom.io;
use xiom.convert;

const TWO: Int = 2;

fn name(x: Int) -> Str {
  match x {
    TWO => { return "two"; },
    _ => { return "other"; },
  }
}

fn main() -> Int {
  var bad = 0;
  let got = name(2);
  io.println("two=" + got);
  if got == "two" {
    io.println("ok");
  } else {
    io.println("const-arm-missed");
    bad = bad + 1;
  }
  io.println("bad=" + int_to_string(bad));
  return bad;
}
