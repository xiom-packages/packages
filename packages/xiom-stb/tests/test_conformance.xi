// xiom.stb conformance suite -- vendored stb_image + stb_image_write.
//
// Build+run (the --c-source list rides in port.args.json):
//   scripts/port.ps1 -Package xiom.stb

module stb_conformance

use xiom.io;
use xiom.test;
use xiom.stb;

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

fn b2s(b: Bool) -> Str {
  if b { return "true"; }
  return "false";
}

fn i2s(n: Int) -> Str {
  if n == 0 { return "0"; }
  var neg = false;
  var v = n;
  if v < 0 {
    neg = true;
    v = 0 - v;
  }
  var buf = "";
  while v > 0 {
    let digit = v % 10;
    v = v / 10;
    if digit == 0 { buf = "0" + buf; }
    elif digit == 1 { buf = "1" + buf; }
    elif digit == 2 { buf = "2" + buf; }
    elif digit == 3 { buf = "3" + buf; }
    elif digit == 4 { buf = "4" + buf; }
    elif digit == 5 { buf = "5" + buf; }
    elif digit == 6 { buf = "6" + buf; }
    elif digit == 7 { buf = "7" + buf; }
    elif digit == 8 { buf = "8" + buf; }
    elif digit == 9 { buf = "9" + buf; }
  }
  if neg { return "-" + buf; }
  return buf;
}

fn main() -> Int {
  io.println("=== xiom.stb conformance tests (vendored stb_image/-write) ===");
  io.flush_stdout();
  var failed: Int = 0;

  // 1. Version of the vendored stb_image.
  failed = failed + report(stb_version() == 1, "codec: STBI_VERSION=" + i2s(stb_version()));

  // 2. Codec probe (PNG encode -> decode round trip + BMP decode).
  let p = stb_probe();
  if p.is_ok {
    failed = failed + report(p.value.png_size > 0 && p.value.roundtrip_ok,
      "png: encoded " + i2s(p.value.png_size) + " bytes; round-trip "
        + b2s(p.value.roundtrip_ok));
    failed = failed + report(p.value.checksum == 8400,
      "png: decoded pixel checksum=" + i2s(p.value.checksum));
    failed = failed + report(p.value.bmp_ok,
      "bmp: 1x1 red decode ok=" + b2s(p.value.bmp_ok));
  } else {
    failed = failed + report(false, "probe: " + p.error);
  }

  // 3. Determinism: a repeated probe yields the identical size + checksum.
  let p2 = stb_probe();
  let same = p.is_ok && p2.is_ok
    && p2.value.png_size == p.value.png_size
    && p2.value.checksum == p.value.checksum;
  failed = failed + report(same, "determinism: repeated probe identical");

  if failed == 0 {
    io.println("xiom.stb: all tests passed");
  } else {
    io.println("xiom.stb: tests failed");
  }
  return failed;
}
