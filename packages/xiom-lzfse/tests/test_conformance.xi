// xiom.lzfse conformance suite -- vendored Apple sources path.
//
// Proves the real binding against the vendored lzfse-1.0 sources compiled
// into the test binary:
//   scripts/port.ps1 -Package xiom.lzfse
// (port.args.json passes the seven --c-source entries).
//
// Coverage: scratch sizes, compressible round-trip with a real ratio,
// larger-buffer round-trip, incompressible round-trip, invalid stream
// rejection.  LZFSE frames carry no queryable content size, so decode uses
// the known original length.

module lzfse_conformance

use xiom.io;
use xiom.convert;
use xiom.test;
use xiom.lzfse;

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
  io.println("=== xiom.lzfse conformance tests (vendored sources) ===");
  io.flush_stdout();
  var failed: Int = 0;

  failed = failed + report(lzfse_encode_scratch_required() > 0,
    "scratch: encode scratch required = " + to_string(lzfse_encode_scratch_required()));
  failed = failed + report(lzfse_decode_scratch_required() > 0,
    "scratch: decode scratch required = " + to_string(lzfse_decode_scratch_required()));

  // Compressible round-trip with a real ratio.
  var data: Vec[UInt8] = Vec[UInt8].new();
  var i: Int = 0;
  while i < 4096 {
    data.push(((i % 16) + 65) as UInt8);
    i = i + 1;
  }
  let er = lzfse_encode(&mut data, 8192);
  if !er.is_ok {
    failed = failed + report(false, "encode failed -- " + er.error);
  } else {
    var packed: Vec[UInt8] = er.value;
    failed = failed + report(packed.len() < data.len(),
      "encode: 4096 -> " + to_string(packed.len()) + " bytes");
    let dr = lzfse_decode(&mut packed, 4096);
    if !dr.is_ok {
      failed = failed + report(false, "decode failed -- " + dr.error);
    } else {
      var restored: Vec[UInt8] = dr.value;
      failed = failed + report(buffers_equal(&data, &restored), "round-trip: restored bytes are identical");
    }
  }

  // Larger buffer.
  var big: Vec[UInt8] = Vec[UInt8].new();
  var b: Int = 0;
  while b < 65536 {
    big.push(((b % 7) * 3 + 11) as UInt8);
    b = b + 1;
  }
  let ber = lzfse_encode(&mut big, 131072);
  if !ber.is_ok {
    failed = failed + report(false, "large encode failed -- " + ber.error);
  } else {
    var bp: Vec[UInt8] = ber.value;
    let bdr = lzfse_decode(&mut bp, 65536);
    if !bdr.is_ok {
      failed = failed + report(false, "large decode failed -- " + bdr.error);
    } else {
      var br: Vec[UInt8] = bdr.value;
      failed = failed + report(buffers_equal(&big, &br), "large: 65536-byte round-trip identical");
    }
  }

  // Incompressible round-trip (LCG bytes).
  var noise: Vec[UInt8] = Vec[UInt8].new();
  var seed: Int = 987654321;
  var n: Int = 0;
  while n < 1024 {
    seed = (seed * 1103515245 + 12345) % 2147483648;
    noise.push((seed % 256) as UInt8);
    n = n + 1;
  }
  let ner = lzfse_encode(&mut noise, 4096);
  if !ner.is_ok {
    failed = failed + report(false, "noise encode failed -- " + ner.error);
  } else {
    var np: Vec[UInt8] = ner.value;
    let ndr = lzfse_decode(&mut np, 1024);
    if !ndr.is_ok {
      failed = failed + report(false, "noise decode failed -- " + ndr.error);
    } else {
      var nr: Vec[UInt8] = ndr.value;
      failed = failed + report(buffers_equal(&noise, &nr), "incompressible: 1024-byte round-trip identical");
    }
  }

  // Invalid stream rejection.
  var garbage: Vec[UInt8] = Vec[UInt8].new();
  var g: Int = 0;
  while g < 64 {
    garbage.push(204 as UInt8);
    g = g + 1;
  }
  let bad = lzfse_decode(&mut garbage, 256);
  if bad.is_ok {
    failed = failed + report(false, "invalid stream unexpectedly decoded");
  } else {
    failed = failed + report(true, "invalid stream rejected (" + bad.error + ")");
  }

  if failed == 0 {
    io.println("xiom.lzfse: all tests passed");
  } else {
    io.println("xiom.lzfse: tests failed");
  }
  return failed;
}
