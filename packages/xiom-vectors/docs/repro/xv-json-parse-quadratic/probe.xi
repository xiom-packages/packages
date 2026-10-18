// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

// Repro: stdlib `xiom.serialize.json` parsing is superlinear on large
// numeric payloads (found 2026-10-11 by the xvector benchmark run).
//
// Self-contained: builds JSON number arrays in a linear byte buffer (no
// string-concat noise), parses each, prints the timing sweep, and gates
// the largest parse at 5 s (pre-fix: tens of seconds; post-fix: ms).
// Run: .\scripts\build.ps1 docs\repro\xv-json-parse-quadratic\probe.xi -Name repro_json_quad
//      .\out\repro_json_quad.exe

module xiom.vector.repro_json_parse_quadratic

use xiom.io;
use xiom.time;
use xiom.convert;
use xiom.string.slice;
use xiom.serialize.json;

fn gen_numbers_json(n: Int) -> Str {
  var b = Vec[UInt8].new();
  b.push(91u8); // [
  var i: Int = 0;
  while i < n {
    if i > 0 { b.push(44u8); }
    var s = convert.int_to_string(i % 97) + "." + convert.int_to_string((i * 7919) % 100000);
    let sb = slice.str_bytes(s);
    var j: Int = 0;
    while j < sb.len() {
      b.push(sb[j]);
      j = j + 1;
    }
    i = i + 1;
  }
  b.push(93u8); // ]
  return Str::from_utf8(&b);
}

fn parse_ms(s: Str) -> Int {
  var t0 = time.monotonic_ms();
  let r = json.json_parse(&s);
  var dt = time.monotonic_ms() - t0;
  match r {
    Ok(_) => {}
    Err(e) => { io.println("  parse error: " + e); }
  }
  return dt;
}

fn main() -> Int {
  var fails: Int = 0;
  var sizes = Vec[Int].new();
  sizes.push(2500);
  sizes.push(5000);
  sizes.push(10000);
  sizes.push(20000);
  var i: Int = 0;
  var last: Int = 0;
  while i < sizes.len() {
    var s = gen_numbers_json(sizes[i]);
    var ms = parse_ms(s);
    io.println("  numbers=" + convert.int_to_string(sizes[i])
      + " bytes=" + convert.int_to_string(s.len())
      + " parse_ms=" + convert.int_to_string(ms));
    last = ms;
    i = i + 1;
  }
  if last > 5000 {
    fails = 1;
    io.println("  [FAIL] 20000-number parse exceeds 5s (superlinear parser)");
  } else {
    io.println("  [PASS] 20000-number parse under 5s");
  }
  io.println("repro_json_parse_quadratic: exit=" + convert.int_to_string(fails));
  return fails;
}
