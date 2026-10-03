// Module-level const-array / table materialization probe (row 25).
//
// Simple `[N]Int` module-level const arrays were reported CORRECT on
// v0.62.2; complex initializers (Str / struct tables) are UNTESTED.
// This probe covers Int, Str and struct tables with runtime-indexed
// loop reads and content checks.
//
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module const_tables_probe

use xiom.io;
use xiom.convert;
use xiom.string;
use xiom.string.compare;

const K: [4]Int = [3, 1, 4, 1];

const NAMES: [3]Str = ["alpha", "beta", "gamma"];

pub type Row = { code: Int; name: Str; }

const ROWS: [3]Row = [
  Row{ code: 1, name: "one" },
  Row{ code: 2, name: "two" },
  Row{ code: 3, name: "three" }
];

fn main() -> Int {
  var bad = 0;

  // Control 1: runtime struct literal with the same field syntax.
  let r = Row{ code: 9, name: "nine" };
  io.println("rt row code=" + int_to_string(r.code));
  if r.code != 9 { bad = bad + 1; }
  if compare.str_compare(r.name, "nine") != 0 { bad = bad + 1; }

  // Control 2: runtime-built Vec[Str] with the same content as NAMES.
  var nv: Vec[Str] = Vec[Str].new();
  nv.push("alpha");
  nv.push("beta");
  nv.push("gamma");
  var vlen = 0;
  var j = 0;
  while j < 3 {
    vlen = vlen + string.str_len(nv[j]);
    j = j + 1;
  }
  io.println("vec str lens sum=" + int_to_string(vlen));
  if vlen != 14 { bad = bad + 1; }

  var sum = 0;
  var i = 0;
  while i < 4 {
    sum = sum + K[i];
    i = i + 1;
  }
  io.println("int sum=" + int_to_string(sum));
  if sum != 9 { bad = bad + 1; }

  var slen = 0;
  var csum = 0;
  var nlen = 0;
  i = 0;
  while i < 3 {
    slen = slen + string.str_len(NAMES[i]);
    csum = csum + ROWS[i].code;
    nlen = nlen + string.str_len(ROWS[i].name);
    i = i + 1;
  }
  io.println("str lens sum=" + int_to_string(slen));
  io.println("code sum=" + int_to_string(csum));
  io.println("name lens sum=" + int_to_string(nlen));
  if slen != 14 { bad = bad + 1; }
  if csum != 6 { bad = bad + 1; }
  if nlen != 11 { bad = bad + 1; }

  if compare.str_compare(NAMES[1], "beta") == 0 {
    io.println("NAMES[1] content ok");
  } else {
    io.println("NAMES[1] content WRONG");
    bad = bad + 1;
  }

  if compare.str_compare(ROWS[2].name, "three") == 0 {
    io.println("ROWS[2] content ok");
  } else {
    io.println("ROWS[2] content WRONG");
    bad = bad + 1;
  }

  io.println("bad=" + int_to_string(bad));
  return bad;
}
