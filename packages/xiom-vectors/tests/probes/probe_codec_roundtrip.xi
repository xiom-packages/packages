// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Adapted codec acceptance probe (from XVECTOR's
// tests/probes/probe_floatval_roundtrip.xi, XVC-C-06): the xiom.vectors WAL
// value codec must read back the exact IEEE-754 bit pattern of every Float32
// element, must be idempotent under encode(decode(encode(v))), and must
// reject a torn payload.
// Exit 0 = green; 1 = payload shape wrong; 2 = decode None; 3 = bit mismatch;
// 4 = re-encode not idempotent; 5 = torn payload accepted.

module probe_codec_roundtrip

use xiom.io;
use xiom.num.float;
use xiom.vectors;

fn main() -> Int {
  io.println("=== xiom.vectors codec round-trip probe ===");
  var v = Vector.new(4);
  v.set(0, 10.0);
  v.set(1, -0.0);
  v.set(2, 1.1754944e-38);
  v.set(3, -3.4028235e38);

  var payload = vector_encode(&v);
  if payload.len() != 5 { return 1; }
  if payload[0] != 4 { return 1; }

  match vector_decode(&payload) {
    Some(w) => {
      if w.dimension != 4 { return 2; }
      var i: Int = 0;
      while i < 4 {
        let want = float.float_bits(v.data[i] as Float64);
        let got = float.float_bits(w.data[i] as Float64);
        if want != got { return 3; }
        i = i + 1;
      }
      var repayload = vector_encode(&w);
      if repayload.len() != payload.len() { return 4; }
      i = 0;
      while i < payload.len() {
        if repayload[i] != payload[i] { return 4; }
        i = i + 1;
      }
      io.println("  [PASS] 4/4 elements bit-exact; encode(decode(encode(v))) idempotent");
    }
    None => { return 2; }
  }

  var torn = Vec[Int].new();
  torn.push(4); torn.push(1);
  match vector_decode(&torn) {
    Some(_) => { return 5; }
    None => {}
  }
  io.println("  [PASS] torn payload rejected (None)");
  io.println("probe_codec_roundtrip: GREEN");
  return 0;
}
