// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Probe C -- the same as Probe A, but the struct holding the Vec[UInt8] field
// arrives as a `Result[Blob, Str]` payload: `&r.value.data`.
//
// Ownership context: two field hops from a local Result value (payload field
// of a returned Result, then a Vec[UInt8] field of that payload struct).
// This is the exact shape the xiom.aiff porter hit (7 test sites) and the
// shape wave 20's SESSION.md note labelled "&result.value".
//
// v0.61.3 observed: the callee reads the vector as EMPTY. Expected once
// fixed: exit 0.
module probe_result_struct_field

use xiom.convert;
use xiom.io;

pub type Blob = { data: Vec[UInt8]; tag: Int; }

// Ok leaf constructor (Ok/Err literals inside larger bodies miscompile).
fn _ok_blob(b: Blob) -> Result[Blob, Str] {
  return Ok(b);
}

fn make() -> Result[Blob, Str] {
  let d = Vec[UInt8].new();
  d.push(11);
  d.push(22);
  d.push(33);
  return _ok_blob(Blob{ data: d, tag: 7; });
}

// The callee under test.
pub fn byte_len(v: &Vec[UInt8]) -> Int {
  return v.len();
}

fn main() -> Int {
  let r = make();
  if !r.is_ok { return 90; }

  let direct = byte_len(&r.value.data);  // Result payload struct field
  let b = r.value;                       // bound local (control)
  let bound = byte_len(&b.data);

  io.println("result field : " + int_to_string(direct));
  io.println("bound local  : " + int_to_string(bound));

  if (direct != 3) { return 10 + direct; }
  if (bound != 3) { return 20 + bound; }
  return 0;
}
