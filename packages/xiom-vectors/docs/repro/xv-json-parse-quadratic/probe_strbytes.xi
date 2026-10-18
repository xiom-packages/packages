// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

// Repro: `slice.str_bytes(Str)` is superlinear in string size (found
// 2026-10-11 as the ROOT CAUSE of the json-parse quadratic and of every
// Str-heavy service path). Builds Strs of growing size in a LINEAR byte
// buffer (no concat noise) and times one `str_bytes` per size.
//
// Acceptance (re-pinned post-fix, wave-111 `9a2b5ab`): LINEARITY, not an
// absolute wall-clock number. The original 500 ms marker was a pre-fix
// severity gate; after the fix the platform spread is real (Windows
// ~380 ms, WSL ~650-750 ms for 400 KB -- both ~8.5x for 8x size, i.e.
// linear), so the gate is: 400 KB under 20x the 50 KB time (linear:
// ~8-9x; pre-fix quadratic: ~34x) AND under an absolute 3 s net.
//
// Run: .\scripts\build.ps1 docs\repro\xv-json-parse-quadratic\probe_strbytes.xi -Name repro_strbytes
//      .\out\repro_strbytes.exe

module xiom.vector.repro_str_bytes_quadratic

use xiom.io;
use xiom.time;
use xiom.convert;
use xiom.string.slice;

fn main() -> Int {
  var fails: Int = 0;
  var sizes = Vec[Int].new();
  sizes.push(50000);
  sizes.push(100000);
  sizes.push(200000);
  sizes.push(400000);
  var last: Int = 0;
  var first: Int = 0;
  var i: Int = 0;
  while i < sizes.len() {
    var n = sizes[i];
    var buf = Vec[UInt8].new();
    var k: Int = 0;
    while k < n {
      buf.push(65u8);
      k = k + 1;
    }
    var s = Str::from_utf8(&buf);
    var t0 = time.monotonic_ms();
    let b = slice.str_bytes(s);
    var dt = time.monotonic_ms() - t0;
    io.println("  len=" + convert.int_to_string(n)
      + " str_bytes_ms=" + convert.int_to_string(dt)
      + " bytes=" + convert.int_to_string(b.len()));
    if i == 0 { first = dt; }
    last = dt;
    i = i + 1;
  }
  var denom: Int = first;
  if denom < 1 { denom = 1; }
  if last > 20 * denom || last > 3000 {
    fails = 1;
    io.println("  [FAIL] 400 KB str_bytes superlinear (over 20x the 50 KB time) or over 3 s");
  } else {
    io.println("  [PASS] 400 KB linear (" + convert.int_to_string(last / denom) + "x the 50 KB time; under 3 s)");
  }
  io.println("repro_str_bytes_quadratic: exit=" + convert.int_to_string(fails));
  return fails;
}
