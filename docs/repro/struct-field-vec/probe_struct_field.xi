// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Probe A -- a plain struct field of type Vec[UInt8], taken by reference and
// passed into a `&Vec[UInt8]` parameter.
//
// Ownership context: `b` is a local `var` struct; `b.data` is a field of a
// local value (not a Result payload, not a call result).
//
// v0.61.3 observed (waves 1-24, x BUG-4 family): the callee reads the field
// vector as EMPTY. Same value bound to a local first is read correctly.
// Expected once fixed: exit 0.
module probe_struct_field

use xiom.convert;
use xiom.io;

pub type Blob = { data: Vec[UInt8]; tag: Int; }

// The callee under test: length through a Vec reference parameter.
pub fn byte_len(v: &Vec[UInt8]) -> Int {
  return v.len();
}

fn main() -> Int {
  let d = Vec[UInt8].new();
  d.push(11);
  d.push(22);
  d.push(33);
  var b = Blob{ data: d, tag: 7; };

  let direct = byte_len(&b.data);   // struct field -> &Vec[UInt8]
  let v = b.data;                   // bound local (control)
  let bound = byte_len(&v);

  io.println("direct field: " + int_to_string(direct));
  io.println("bound local : " + int_to_string(bound));

  if (direct != 3) { return 10 + direct; }
  if (bound != 3) { return 20 + bound; }
  return 0;
}
