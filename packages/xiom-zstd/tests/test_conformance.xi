// xiom.zstd conformance suite -- vendored amalgamation path.
//
// Proves the real binding against the vendored single-file zstd (v1.5.7)
// compiled into the test binary:
//   scripts/port.ps1 -Package xiom.zstd
// (port.args.json passes `--c-source vendor/zstd.c`).
//
// Coverage: version pin, compressBound sanity, compressible round-trip with
// a real ratio, frame content size, auto-size decompression, incompressible
// round-trip, invalid-frame rejection.

module zstd_conformance

use xiom.io;
use xiom.convert;
use xiom.test;
use xiom.zstd;

fn report(ok: Bool, name: Str) -> Int {
  if ok {
    io.println("  [PASS] " + name);
    io.flush_stdout();
    return 0;
  }
  io.println("  [FAIL] " + name);
  io.flush_stdout();
  return 1;
}

fn buffers_equal(a: &Vec[UInt8], b: &Vec[UInt8]) -> Bool {
  if a.len() != b.len() { return false; }
  var i = 0;
  var same = true;
  while i < a.len() {
    if (a[i] as Int) != (b[i] as Int) { same = false; }
    i = i + 1;
  }
  return same;
}

fn main() -> Int {
  io.println("=== xiom.zstd conformance tests (vendored amalgamation) ===");
  io.flush_stdout();
  var failed: Int = 0;

  // Version pin.
  let v = zstd_version_number();
  failed = failed + report(v >= 10500, "version: zstd " + zstd_version() + " (" + to_string(v) + ")");
  failed = failed + report(zstd_compress_bound(1000) >= 1000, "compressBound(1000) >= 1000");

  // Compressible round-trip with a real ratio.
  var data: Vec[UInt8] = Vec[UInt8].new();
  var i: Int = 0;
  while i < 8192 {
    data.push(((i % 16) + 65) as UInt8);
    i = i + 1;
  }
  let cr = zstd_compress(&mut data, 3);
  if !cr.is_ok {
    failed = failed + report(false, "compress failed -- " + cr.error);
  } else {
    var packed: Vec[UInt8] = cr.value;
    failed = failed + report(packed.len() < data.len(),
      "compress: 8192 -> " + to_string(packed.len()) + " bytes at level 3");
    let fcs = zstd_frame_content_size(&mut packed);
    failed = failed + report(fcs == 8192, "frame content size = " + to_string(fcs));

    let dr = zstd_decompress(&mut packed, 8192);
    if !dr.is_ok {
      failed = failed + report(false, "decompress failed -- " + dr.error);
    } else {
      var restored: Vec[UInt8] = dr.value;
      failed = failed + report(buffers_equal(&data, &restored), "round-trip: restored bytes are identical");
    }

    let ar = zstd_decompress_auto(&mut packed);
    if !ar.is_ok {
      failed = failed + report(false, "auto decompress failed -- " + ar.error);
    } else {
      var restored2: Vec[UInt8] = ar.value;
      failed = failed + report(buffers_equal(&data, &restored2), "auto-size decompress: identical");
    }
  }

  // Incompressible round-trip (LCG bytes).
  var noise: Vec[UInt8] = Vec[UInt8].new();
  var seed: Int = 12345;
  var n: Int = 0;
  while n < 2048 {
    seed = (seed * 1103515245 + 12345) % 2147483648;
    noise.push((seed % 256) as UInt8);
    n = n + 1;
  }
  let nr = zstd_compress(&mut noise, 1);
  if !nr.is_ok {
    failed = failed + report(false, "noise compress failed -- " + nr.error);
  } else {
    var np: Vec[UInt8] = nr.value;
    let nd = zstd_decompress_auto(&mut np);
    if !nd.is_ok {
      failed = failed + report(false, "noise decompress failed -- " + nd.error);
    } else {
      var nr2: Vec[UInt8] = nd.value;
      failed = failed + report(buffers_equal(&noise, &nr2), "incompressible: 2048-byte round-trip identical");
    }
  }

  // Invalid frame rejection.
  var garbage: Vec[UInt8] = Vec[UInt8].new();
  var g: Int = 0;
  while g < 32 {
    garbage.push(170 as UInt8);
    g = g + 1;
  }
  let bad = zstd_decompress_auto(&mut garbage);
  if bad.is_ok {
    failed = failed + report(false, "invalid frame unexpectedly decompressed");
  } else {
    failed = failed + report(true, "invalid frame rejected (" + bad.error + ")");
  }

  if failed == 0 {
    io.println("xiom.zstd: all tests passed");
  } else {
    io.println("xiom.zstd: tests failed");
  }
  return failed;
}
