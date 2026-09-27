// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Sign-bit bit-ops battery. v0.61.3 reports `&`/`^` as unreliable on values
// with bit 31 or higher set (bolt: FNV-1a-64 XOR replaced by an arithmetic
// bit loop; radiotap/can use divisor/modulo end-to-end). Values here are
// produced at runtime through a helper so constant folding cannot hide the
// lowering:
//   a = 2^31 + 7 (runtime), m = 255 (runtime)
//   a & m = 7, a | 8 = 2^31 + 15, a ^ 3 = 2^31 + 4
//   h = 1099511628211 * 2^20 + 5 (bit 62 set): h & 255 must equal h % 256
// Exit 0 = correct; 11..15 identify the first failing identity.
// Expected once fixed: exit 0.
module probe_sign_bit

use xiom.convert;
use xiom.io;

fn _mul(x: Int, y: Int) -> Int {
  return x * y;
}

fn main() -> Int {
  let a = _mul(65536, 32768) + _mul(7, 1); // 2^31 + 7, runtime
  let m = _mul(51, 5);                     // 255, runtime

  let and_v = a & m;
  if (and_v != 7) {
    io.println("and=" + int_to_string(and_v));
    return 11;
  }

  let or_v = a | _mul(8, 1);
  if (or_v != 2147483663) { // 2^31 + 15
    io.println("or=" + int_to_string(or_v));
    return 12;
  }

  let xor_v = a ^ _mul(3, 1);
  if (xor_v != 2147483652) { // 2^31 + 4
    io.println("xor=" + int_to_string(xor_v));
    return 13;
  }

  let h = _mul(1099511628211, 1048576) + 5; // bit 62 set, runtime
  let hb = h & m;
  let hm = h % 256;
  if (hb != hm) {
    io.println("hb=" + int_to_string(hb) + " hm=" + int_to_string(hm));
    return 14;
  }

  // control: small runtime values
  let s = _mul(3, 2);
  if ((s & 1) != 0) { return 15; }
  if ((s ^ 3) != 5) { return 16; }

  // negative operands (sign bit naturally set)
  let neg1 = 0 - 1;
  let n1a = neg1 & m;
  if (n1a != 255) {
    io.println("neg1&=" + int_to_string(n1a));
    return 17;
  }
  let n1x = neg1 ^ _mul(3, 1);
  if (n1x != -4) {
    io.println("neg1^=" + int_to_string(n1x));
    return 18;
  }
  let neg2 = 0 - _mul(65536, 32768); // -2^31
  let n2a = neg2 & m;
  if (n2a != 0) {
    io.println("neg2&=" + int_to_string(n2a));
    return 19;
  }
  let n2o = neg2 | 1;
  if (n2o != -2147483647) {
    io.println("neg2|=" + int_to_string(n2o));
    return 20;
  }

  // wrapped 64-bit value: 2^63 + 5 wraps negative, low byte must stay 5
  let w = _mul(4611686018427387904, 2) + 5;
  let wa = w & m;
  if (wa != 5) {
    io.println("wrap&=" + int_to_string(wa));
    return 21;
  }
  return 0;
}
