// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Probe B -- the Vec[UInt8] held as a `Result[Vec[UInt8], Str]` payload,
// taken by reference through `r.value` and passed into a `&Vec[UInt8]`
// parameter.
//
// Ownership context: `r` is a local Result value returned from a function;
// `r.value` is the Ok payload field, read after `r.is_ok` is checked.
//
// v0.61.3 observed (reported by the xiom.quotedprintable and xiom.aiff
// porters; every test site binds the payload to a local first): the callee
// reads the payload as EMPTY. Expected once fixed: exit 0.
module probe_result_value

use xiom.convert;
use xiom.io;

// Ok leaf constructor (Ok/Err literals inside larger bodies miscompile).
fn _ok_bytes(v: Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  return Ok(v);
}

fn make() -> Result[Vec[UInt8], Str] {
  let d = Vec[UInt8].new();
  d.push(11);
  d.push(22);
  d.push(33);
  return _ok_bytes(d);
}

// The callee under test.
pub fn byte_len(v: &Vec[UInt8]) -> Int {
  return v.len();
}

fn main() -> Int {
  let r = make();
  if !r.is_ok { return 90; }

  let direct = byte_len(&r.value);  // Result payload -> &Vec[UInt8]
  let v = r.value;                  // bound local (control)
  let bound = byte_len(&v);

  io.println("result payload: " + int_to_string(direct));
  io.println("bound local   : " + int_to_string(bound));

  if (direct != 3) { return 10 + direct; }
  if (bound != 3) { return 20 + bound; }
  return 0;
}
