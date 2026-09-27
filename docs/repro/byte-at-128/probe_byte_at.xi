// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// `string.byte_at` vs bytes >= 128 battery. The documented trap (SESSION.md
// wave-31 guidance) is: "Never compare `byte_at(...)` directly to a UInt8
// constant >= 128; widen `(x as Int) & 0xFF`". Typed-local binds work
// (usb probe). This probe pins every path over a two-byte UTF-8 literal
// (U+00E9 -> C3 A9) and counts failures in `bad`:
//   A direct comparisons:  byte_at(s,0) == 195u8, byte_at(s,1) == 169u8,
//                          byte_at(s,0) >= 128u8        (reported failing)
//   B untyped let then compare
//   C typed UInt8 locals                                (working control)
//   D widen path: (byte_at(s,0) as Int) & 0xFF == 195
// Exit 0 = all correct; nonzero = number of failing checks.
// Expected once fixed: exit 0.
module probe_byte_at

use xiom.convert;
use xiom.io;
use xiom.string;

fn main() -> Int {
  var bad = 0;

  let s = "é"; // UTF-8 C3 A9, both bytes >= 128
  if (str_len(s) != 2) {
    io.println("len=" + int_to_string(str_len(s)));
    return 10;
  }

  // A. direct comparisons (reported failing shape)
  if (string.byte_at(s, 0) != 195u8) {
    io.println("direct b0 mismatch");
    bad = bad + 1;
  }
  if (string.byte_at(s, 1) != 169u8) {
    io.println("direct b1 mismatch");
    bad = bad + 1;
  }
  if (string.byte_at(s, 0) < 128u8) {
    io.println("direct b0 < 128");
    bad = bad + 1;
  }

  // B. untyped let
  let u0 = string.byte_at(s, 0);
  if (u0 != 195u8) {
    io.println("untyped u0 mismatch");
    bad = bad + 1;
  }

  // C. typed locals (working control)
  let b0: UInt8 = string.byte_at(s, 0);
  let b1: UInt8 = string.byte_at(s, 1);
  if (b0 != 195u8) {
    io.println("typed b0 mismatch");
    bad = bad + 1;
  }
  if (b1 != 169u8) {
    io.println("typed b1 mismatch");
    bad = bad + 1;
  }

  // D. widen path
  let w0 = (string.byte_at(s, 0) as Int) & 255;
  if (w0 != 195) {
    io.println("widen w0=" + int_to_string(w0));
    bad = bad + 1;
  }

  io.println("bad=" + int_to_string(bad));
  return bad;
}
