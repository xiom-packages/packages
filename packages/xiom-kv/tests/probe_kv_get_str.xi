// probe_kv_get_str.xi -- xiom.kv kv_get Str corruption (packages-lane repro).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Mirrors PULSE's consumer repro (C-PULSE-10, WSL Linux v0.64.0) and adds
// the multi-key kv_get_bytes length check called out in the PULSE wishlist
// (a 9-byte value read back as 6 after a second key write).
//
// Run from the repo root (pinned toolchain):
//   & .\scripts\xiom.ps1 -Stdlib "E:\xiom-lang\stdlib" --run packages\xiom-kv\tests\probe_kv_get_str.xi
//
// The probe documents behavior and exits 0; the [FAIL] lines are diagnostics.
module kv_get_str_probe

use xiom.kv;
use xiom.string;
use xiom.io;

var g_stores: Vec[KvStore] = Vec[KvStore].new();

fn str_to_bytes(s: Str) -> Vec[UInt8] {
  var out: Vec[UInt8] = Vec[UInt8].new();
  var i: Int = 0;
  while i < s.len() {
    out.push(s.byte_at(i));
    i = i + 1;
  }
  return out;
}

pub fn main() -> Int {
  let _c1 = io.remove_file("kvprobe-seg-0000000001.kv");
  let _c2 = io.remove_file("kvprobe-seg-0000000002.kv");

  let or1 = kv_open(".", "kvprobe-", 4096);
  if or1.is_err {
    io.println("[FAIL] open: " + or1.error);
    return 1;
  }
  g_stores.push(or1.value);

  // Single key, 10-byte value.
  let p1 = kv_put(&mut g_stores[0], "k", "abcdefghij");
  if p1.is_err {
    io.println("[FAIL] put: " + p1.error);
    return 1;
  }

  let gs = kv_get(&g_stores[0], "k");
  if gs.is_err || gs.value.is_none {
    io.println("[FAIL] get");
    return 1;
  }
  let got: Str = gs.value.value;
  if string.str_compare(got, "abcdefghij") == 0 {
    io.println("[PASS] kv_get      =[" + got + "]");
  } else {
    io.println("[FAIL] kv_get      =[" + got + "]  (expected [abcdefghij])");
  }

  let gb = kv_get_bytes(&g_stores[0], "k");
  if gb.is_err || gb.value.is_none {
    io.println("[FAIL] get_bytes");
    return 1;
  }
  let stored: Vec[UInt8] = gb.value.value;
  io.println("kv_get_bytes=[" + Str::from_utf8(stored) + "]  len=" + stored.len().to_str());

  // Multi-key: write a second key, then re-read the 9-byte value.
  let p2 = kv_put(&mut g_stores[0], "k2", "123456789");
  if p2.is_err {
    io.println("[FAIL] put k2: " + p2.error);
    return 1;
  }
  let gb2 = kv_get_bytes(&g_stores[0], "k2");
  if gb2.is_err || gb2.value.is_none {
    io.println("[FAIL] get_bytes k2");
    return 1;
  }
  let stored2: Vec[UInt8] = gb2.value.value;
  if stored2.len() == 9 {
    io.println("[PASS] k2 bytes    =[" + Str::from_utf8(stored2) + "]  len=9");
  } else {
    io.println("[FAIL] k2 bytes    =[" + Str::from_utf8(stored2) + "]  len=" + stored2.len().to_str() + "  (expected 9)");
  }

  // Re-read the first key after the second write (records still intact?).
  let gb1b = kv_get_bytes(&g_stores[0], "k");
  if gb1b.is_err || gb1b.value.is_none {
    io.println("[FAIL] get_bytes k after k2");
    return 1;
  }
  let stored1b: Vec[UInt8] = gb1b.value.value;
  io.println("k bytes later=[" + Str::from_utf8(stored1b) + "]  len=" + stored1b.len().to_str());

  // Control: from_utf8 over a locally built vector.
  let local: Vec[UInt8] = str_to_bytes("abcdefghij");
  io.println("control     =[" + Str::from_utf8(local) + "]");

  kv_close(&mut g_stores[0]);
  let _r1 = io.remove_file("kvprobe-seg-0000000001.kv");
  let _r2 = io.remove_file("kvprobe-seg-0000000002.kv");
  return 0;
}
