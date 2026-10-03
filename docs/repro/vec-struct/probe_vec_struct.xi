// `Vec[StructType]` probe (trap 10).
//
// COMPILER-FINDINGS (2026-09-27): "No `Vec[StructType]` -- struct payload
// lists need parallel `Vec` fields"; `nats`/`i2c` model struct lists as
// mirrored parallel Vecs. This probe checks push/read/mutate on the pin.
//
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module vec_struct_probe

use xiom.io;
use xiom.convert;
use xiom.string;
use xiom.string.compare;

pub type Row = { code: Int; name: Str; }

fn first_code(rows: &Vec[Row]) -> Int {
  return rows[0].code;
}

fn main() -> Int {
  var bad = 0;

  var v: Vec[Row] = Vec[Row].new();
  v.push(Row{ code: 1, name: "one" });
  v.push(Row{ code: 2, name: "two" });
  v.push(Row{ code: 3, name: "three" });

  if v.len() == 3 {
    io.println("len=3");
  } else {
    io.println("len WRONG");
    bad = bad + 1;
  }

  let r1 = v[1];
  io.println("r1.code=" + int_to_string(r1.code));
  if r1.code != 2 { bad = bad + 1; }
  if compare.str_compare(r1.name, "two") != 0 {
    io.println("r1.name WRONG");
    bad = bad + 1;
  }

  let r2 = v[2];
  io.println("r2.name len=" + int_to_string(string.str_len(r2.name)));
  if compare.str_compare(r2.name, "three") != 0 { bad = bad + 1; }

  // Field write through the index.
  v[0].code = 9;
  if v[0].code == 9 {
    io.println("field write ok");
  } else {
    io.println("field write LOST");
    bad = bad + 1;
  }

  // Runtime push in a loop with computed values.
  var i = 0;
  while i < 3 {
    v.push(Row{ code: 100 + i, name: "x" });
    i = i + 1;
  }
  if v.len() == 6 {
    io.println("loop push len=6");
  } else {
    io.println("loop push len WRONG");
    bad = bad + 1;
  }
  if v[5].code == 102 {
    io.println("v[5].code=102");
  } else {
    io.println("v[5].code WRONG");
    bad = bad + 1;
  }

  // Borrowed-vector parameter read.
  if first_code(&v) == 9 {
    io.println("&Vec[Row] param ok");
  } else {
    io.println("&Vec[Row] param WRONG");
    bad = bad + 1;
  }

  io.println("bad=" + int_to_string(bad));
  return bad;
}
