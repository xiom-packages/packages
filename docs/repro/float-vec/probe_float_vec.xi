// `Vec[Float64]` capability probe.
//
// COMPILER-FINDINGS (2026-09-26): "No `Vec[Float64]`; no `Int <-> Float64`
// bitcast in v0.61.3" -- `avro`/`mkv`/`amqp` expose floats as raw octets.
// This probe checks whether `Vec[Float64]` works on the pin.
//
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module float_vec_probe

use xiom.io;
use xiom.convert;
use xiom.num.float;

fn main() -> Int {
  var bad = 0;

  var v: Vec[Float64] = Vec[Float64].new();
  v.push(1.5);
  v.push(-2.25);
  v.push(0.0);

  if v.len() == 3 {
    io.println("len=3");
  } else {
    io.println("len WRONG");
    bad = bad + 1;
  }

  if v[0] > 1.0 {
    io.println("v0>1");
  } else {
    io.println("v0 compare WRONG");
    bad = bad + 1;
  }

  if v[1] < 0.0 {
    io.println("v1<0");
  } else {
    io.println("v1 compare WRONG");
    bad = bad + 1;
  }

  var sum: Float64 = v[0] + v[1];
  if sum < 0.0 {
    io.println("sum<0");
  } else {
    io.println("sum WRONG");
    bad = bad + 1;
  }

  // Int <-> Float64 bitcast: 1.5 == 0x3FF8000000000000.
  let bits = float.float_bits(1.5);
  io.println("float_bits(1.5)=" + int_to_string(bits));
  if bits == 4609434218613702656 {
    io.println("bits exact");
  } else {
    io.println("bits WRONG");
    bad = bad + 1;
  }
  let back = float.bits_to_float(bits);
  if back == 1.5 {
    io.println("bits_to_float round-trip ok");
  } else {
    io.println("round-trip WRONG");
    bad = bad + 1;
  }

  io.println("bad=" + int_to_string(bad));
  return bad;
}
