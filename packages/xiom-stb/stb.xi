// XIOM -- xiom.stb: stb image codecs (vendored stb_image + stb_image_write).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// DESIGN: vendored single-header pattern (the miniaudio method).  Both
// stb headers are vendored unmodified in `vendor/` and one TU
// (`src/stb_all.c`) carries `STB_IMAGE_IMPLEMENTATION` +
// `STB_IMAGE_WRITE_IMPLEMENTATION` plus the probe bridge; no system
// library, no SDK.
//
// The probe is self-contained: it encodes a 4x4 RGBA gradient to PNG in
// memory, decodes it back and verifies every pixel and the checksum, then
// decodes a hardcoded 1x1 24-bit BMP.  All `unsafe`/`extern "C"` live in
// this single module (G5); scalar getters only (no out-param slots; the
// B-11 family avoidance).
//
// G2 pin (SPEC.md): upstream commit 2c980bb5... + per-header SHA256.

module xiom.stb

extern "C" {
  fn stbprobe_version() -> Int32;
  fn stbprobe_run() -> Int32;
  fn stbprobe_png_size() -> Int32;
  fn stbprobe_roundtrip_ok() -> Int32;
  fn stbprobe_checksum() -> Int32;
  fn stbprobe_bmp_ok() -> Int32;
}

pub type StbProbe = {
  version: Int;       // STBI_VERSION
  png_size: Int;      // bytes of the in-memory PNG produced by the encoder
  checksum: Int;      // sum of the 64 decoded RGBA bytes (expected 8400)
  roundtrip_ok: Bool; // every decoded pixel equals the encoded source
  bmp_ok: Bool;       // the 1x1 red BMP decoded as 1x1x3 with (255,0,0)
}

/// STBI_VERSION of the vendored stb_image.  Complexity: O(1).
pub fn stb_version() -> Int
  requires: true
{
  unsafe { return stbprobe_version() as Int; }
}

/// Run the in-memory codec probe (PNG encode/decode round trip + BMP
/// decode).  Complexity: O(image).
pub fn stb_probe() -> Result[StbProbe, Str]
  requires: true
{
  let rc = unsafe { stbprobe_run() as Int };
  if rc != 0 {
    return Err("stb: probe rc=" + stb_i2s(0 - rc));
  }
  return Ok(StbProbe{
    version: unsafe { stbprobe_version() as Int };
    png_size: unsafe { stbprobe_png_size() as Int };
    checksum: unsafe { stbprobe_checksum() as Int };
    roundtrip_ok: unsafe { stbprobe_roundtrip_ok() as Int } != 0;
    bmp_ok: unsafe { stbprobe_bmp_ok() as Int } != 0;
  });
}

// ---- internals -----------------------------------------------------------

fn stb_i2s(n: Int) -> Str
  requires: n >= 0
{
  if n == 0 { return "0"; }
  var val = n;
  var buf = "";
  while val > 0 {
    let digit = val % 10;
    val = val / 10;
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
  return buf;
}
