// XIOM ORBITDB -- CRC32C page-checksum KAT probe.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Locks the Phase-1 integrity gate: page_compute_checksum must be CRC32C
// (Castagnoli), not the old additive sum. Canonical check value:
//   CRC32C("123456789") == 0xE3069283 (3808858755)
// The stdlib implementation (xiom.hash.crc.crc32c) carries the same KAT; a
// direct cross-check is deferred until Vec[UInt8] <-> Vec[Int] conversions
// exist (stdlib byte-IO row), so this probe pins the numeric KAT directly.
//
// Exit: 0 = green, 1+ = first failing check.

module orbitdb_probe_crc32c

use xiom.io;
use xiom.convert;
use xiom.db.storage.page;

fn ascii_digits() -> Vec[Int] {
  var out = Vec[Int].new();
  var c = 49; // '1'
  while c <= 57 { // '9'
    out.push(c);
    c = c + 1;
  }
  return out;
}

fn ascii_abc() -> Vec[Int] {
  var out = Vec[Int].new();
  out.push(97);  // 'a'
  out.push(98);  // 'b'
  out.push(99);  // 'c'
  return out;
}

fn ascii_abd() -> Vec[Int] {
  var out = Vec[Int].new();
  out.push(97);  // 'a'
  out.push(98);  // 'b'
  out.push(100); // 'd'
  return out;
}

fn main() -> Int {
  // KAT 1: canonical CRC32C check value.
  let kat = ascii_digits();
  let got = page_compute_checksum(&kat);
  if got != 3808858755 {
    io.println("crc32c: KAT FAIL got=" + convert.int_to_string(got) + " want=3808858755");
    return 1;
  }

  // KAT 2: empty input -> 0 (standard CRC32C).
  let empty = Vec[Int].new();
  if page_compute_checksum(&empty) != 0 {
    io.println("crc32c: empty FAIL");
    return 2;
  }

  // KAT 3: determinism.
  let a = ascii_abc();
  let b = ascii_abc();
  if page_compute_checksum(&a) != page_compute_checksum(&b) {
    io.println("crc32c: determinism FAIL");
    return 3;
  }

  // KAT 4: avalanche -- one byte differs, checksum must differ.
  let c = ascii_abd();
  if page_compute_checksum(&a) == page_compute_checksum(&c) {
    io.println("crc32c: difference FAIL");
    return 4;
  }

  // KAT 5: low-byte view -- element 0x141 must contribute 0x41 like 0x41.
  var big = Vec[Int].new();
  big.push(0x141);
  var small = Vec[Int].new();
  small.push(0x41);
  if page_compute_checksum(&big) != page_compute_checksum(&small) {
    io.println("crc32c: low-byte view FAIL");
    return 5;
  }

  io.println("crc32c: OK kat=" + convert.int_to_string(got));
  return 0;
}
