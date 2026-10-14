// xiom.stb conformance suite -- vendored stb_image + stb_image_write.
//
// 0.3.0: the HDR class surface.  The .hdr fixture is generated in-test
// (Radiance RGBE bytes written by hand; width 4 < 8 so stb's flat
// non-RLE path decodes it), round-tripped through stbi_loadf family,
// remapped through stbi_hdr_to_ldr_gamma/scale, the LDR->HDR knobs are
// exercised through stbi_loadf on an in-test 1x1 24-bit gray BMP, and
// three corrupt inputs must yield typed errors.  Float checks are exact
// (Float64 reconstruction of the float32 bytes; no bitcast intrinsic).
//
// Build+run (the --c-source list rides in port.args.json):
//   scripts/port.ps1 -Package xiom.stb

module stb_conformance

use xiom.io;
use xiom.io.fs;
use xiom.test;
use xiom.stb;
use xiom.string;

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

fn bytes_equal(a: &Vec[UInt8], b: &Vec[UInt8]) -> Bool
  requires: true
{
  if a.len() != b.len() { return false; }
  var i = 0;
  while i < a.len() {
    if a[i] != b[i] { return false; }
    i = i + 1;
  }
  return true;
}

fn push_text(v: &mut Vec[UInt8], s: Str)
  requires: true
{
  var i = 0;
  let n = string.byte_count(s);
  while i < n {
    v.push(string.byte_at(s, i));
    i = i + 1;
  }
}

fn push_u16le(v: &mut Vec[UInt8], value: Int)
  requires: value >= 0
  requires: value <= 65535
{
  v.push((value & 255) as UInt8);
  v.push(((value >> 8) & 255) as UInt8);
}

fn push_u32le(v: &mut Vec[UInt8], value: Int)
  requires: value >= 0
{
  v.push((value & 255) as UInt8);
  v.push(((value >> 8) & 255) as UInt8);
  v.push(((value >> 16) & 255) as UInt8);
  v.push(((value >> 24) & 255) as UInt8);
}

// Tiny Radiance .hdr fixture: 4x1 RGBE, flat encoding (width < 8).
// Decoded float values (exact powers of two / small integers):
//   pixel 0: E=129 -> f=2^-7;  (128,64,32)  -> 1.0, 0.5, 0.25
//   pixel 1: E=130 -> f=2^-6;  (128,64,32)  -> 2.0, 1.0, 0.5
//   pixel 2: E=0   -> all zero
//   pixel 3: E=137 -> f=2;     (1,2,3)      -> 2.0, 4.0, 6.0
fn hdr_fixture() -> Vec[UInt8]
  requires: true
{
  var v = Vec[UInt8].new();
  push_text(&mut v, "#?RADIANCE\n");
  push_text(&mut v, "FORMAT=32-bit_rle_rgbe\n");
  push_text(&mut v, "\n");
  push_text(&mut v, "-Y 1 +X 4\n");
  v.push(128 as UInt8);
  v.push(64 as UInt8);
  v.push(32 as UInt8);
  v.push(129 as UInt8);
  v.push(128 as UInt8);
  v.push(64 as UInt8);
  v.push(32 as UInt8);
  v.push(130 as UInt8);
  v.push(0 as UInt8);
  v.push(0 as UInt8);
  v.push(0 as UInt8);
  v.push(0 as UInt8);
  v.push(1 as UInt8);
  v.push(2 as UInt8);
  v.push(3 as UInt8);
  v.push(137 as UInt8);
  return v;
}

fn hdr_bad_format() -> Vec[UInt8]
  requires: true
{
  var v = Vec[UInt8].new();
  push_text(&mut v, "#?RADIANCE\n");
  push_text(&mut v, "FORMAT=bogus\n");
  push_text(&mut v, "\n");
  push_text(&mut v, "-Y 1 +X 4\n");
  v.push(128 as UInt8);
  v.push(64 as UInt8);
  v.push(32 as UInt8);
  v.push(129 as UInt8);
  return v;
}

fn hdr_bad_layout() -> Vec[UInt8]
  requires: true
{
  var v = Vec[UInt8].new();
  push_text(&mut v, "#?RADIANCE\n");
  push_text(&mut v, "FORMAT=32-bit_rle_rgbe\n");
  push_text(&mut v, "\n");
  push_text(&mut v, "not-a-resolution-line\n");
  v.push(128 as UInt8);
  v.push(64 as UInt8);
  v.push(32 as UInt8);
  v.push(129 as UInt8);
  return v;
}

// 1x1 24-bit gray-128 BMP (58 bytes): the LDR->HDR knob witness.
fn gray_bmp() -> Vec[UInt8]
  requires: true
{
  var v = Vec[UInt8].new();
  v.push(66 as UInt8);
  v.push(77 as UInt8);
  push_u32le(&mut v, 58);
  push_u32le(&mut v, 0);
  push_u32le(&mut v, 54);
  push_u32le(&mut v, 40);
  push_u32le(&mut v, 1);
  push_u32le(&mut v, 1);
  push_u16le(&mut v, 1);
  push_u16le(&mut v, 24);
  push_u32le(&mut v, 0);
  push_u32le(&mut v, 4);
  push_u32le(&mut v, 0);
  push_u32le(&mut v, 0);
  push_u32le(&mut v, 0);
  push_u32le(&mut v, 0);
  v.push(128 as UInt8);
  v.push(128 as UInt8);
  v.push(128 as UInt8);
  v.push(0 as UInt8);
  return v;
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

  // ---- HDR class surface -------------------------------------------------

  let fixture = hdr_fixture();

  // 4. is_hdr classification: the fixture is HDR; a PNG signature and the
  //    1x1 BMP are not.
  var png_magic = Vec[UInt8].new();
  png_magic.push(137 as UInt8);
  png_magic.push(80 as UInt8);
  png_magic.push(78 as UInt8);
  png_magic.push(71 as UInt8);
  png_magic.push(13 as UInt8);
  png_magic.push(10 as UInt8);
  png_magic.push(26 as UInt8);
  png_magic.push(10 as UInt8);
  let bmp_fixture = gray_bmp();
  let cls = stb_hdr_is_from_memory(&fixture)
    && !stb_hdr_is_from_memory(&png_magic)
    && !stb_hdr_is_from_memory(&bmp_fixture)
    && stb_hdr_is_from_callbacks(&fixture);
  failed = failed + report(cls, "hdr: is_hdr classification (fixture vs png vs bmp)");

  // 5. stbi_loadf_from_memory: dimensions, channels, exact float values.
  let r5 = stb_loadf_from_memory(&fixture, 0);
  if r5.is_ok {
    let img = r5.value;
    var ok5 = img.width == 4 && img.height == 1 && img.channels == 3
      && img.file_channels == 3;
    ok5 = ok5 && stb_pixel_f64(&img, 0, 0, 0) == 1.0;
    ok5 = ok5 && stb_pixel_f64(&img, 0, 0, 1) == 0.5;
    ok5 = ok5 && stb_pixel_f64(&img, 0, 0, 2) == 0.25;
    ok5 = ok5 && stb_pixel_f64(&img, 1, 0, 0) == 2.0;
    ok5 = ok5 && stb_pixel_f64(&img, 1, 0, 1) == 1.0;
    ok5 = ok5 && stb_pixel_f64(&img, 1, 0, 2) == 0.5;
    ok5 = ok5 && stb_pixel_f64(&img, 2, 0, 0) == 0.0;
    ok5 = ok5 && stb_pixel_f64(&img, 2, 0, 1) == 0.0;
    ok5 = ok5 && stb_pixel_f64(&img, 2, 0, 2) == 0.0;
    ok5 = ok5 && stb_pixel_f64(&img, 3, 0, 0) == 2.0;
    ok5 = ok5 && stb_pixel_f64(&img, 3, 0, 1) == 4.0;
    ok5 = ok5 && stb_pixel_f64(&img, 3, 0, 2) == 6.0;
    failed = failed + report(ok5, "hdr: loadf_from_memory 4x1 RGB exact values (12 pixels)");
  } else {
    failed = failed + report(false, "hdr: loadf_from_memory: " + r5.error.message);
  }

  // 6. RGBA request: 4 channels, alpha 1.0, RGB preserved.
  let r6 = stb_loadf_from_memory(&fixture, 4);
  if r6.is_ok {
    let img = r6.value;
    var ok6 = img.channels == 4 && img.file_channels == 3;
    ok6 = ok6 && stb_pixel_f64(&img, 0, 0, 0) == 1.0;
    ok6 = ok6 && stb_pixel_f64(&img, 0, 0, 3) == 1.0;
    ok6 = ok6 && stb_pixel_f64(&img, 3, 0, 2) == 6.0;
    ok6 = ok6 && stb_pixel_f64(&img, 3, 0, 3) == 1.0;
    failed = failed + report(ok6, "hdr: loadf_from_memory desired=4 (alpha=1.0, file_channels=3)");
  } else {
    failed = failed + report(false, "hdr: loadf rgba request: " + r6.error.message);
  }

  // 7. Callbacks entry: same image as the memory entry, byte-identical.
  let r7 = stb_loadf_from_callbacks(&fixture, 0);
  if r5.is_ok && r7.is_ok {
    let a = r5.value;
    let b = r7.value;
    let ok7 = a.width == b.width && a.height == b.height
      && a.channels == b.channels && bytes_equal(&a.data, &b.data);
    failed = failed + report(ok7, "hdr: loadf_from_callbacks byte-identical to from_memory");
  } else {
    failed = failed + report(false, "hdr: loadf_from_callbacks failed");
  }

  // 8. File entries: is_hdr / is_hdr_from_file / loadf / loadf_from_file.
  let tmp = io.join_paths(fs.fs_temp_dir(), "xiom_stb_hdr_fixture.hdr");
  let w8 = fs.fs_write(tmp, &fixture);
  if w8.is_ok {
    var ok8 = stb_hdr_is(tmp) && stb_hdr_is_from_file(tmp);
    let rf = stb_loadf(tmp, 0);
    let rg = stb_loadf_from_file(tmp, 0);
    if rf.is_ok && rg.is_ok {
      let img = rf.value;
      ok8 = ok8 && img.width == 4 && img.height == 1 && img.channels == 3;
      ok8 = ok8 && stb_pixel_f64(&img, 0, 0, 0) == 1.0;
      ok8 = ok8 && stb_pixel_f64(&img, 3, 0, 2) == 6.0;
      ok8 = ok8 && rg.value.width == 4 && rg.value.height == 1
        && bytes_equal(&img.data, &rg.value.data);
    } else {
      ok8 = false;
    }
    let rm8 = io.remove_file(tmp);
    failed = failed + report(ok8, "hdr: file entries (is_hdr, is_hdr_from_file, loadf, loadf_from_file)");
  } else {
    failed = failed + report(false, "hdr: temp fixture write failed");
  }

  // 9. stbi_hdr_to_ldr_*: gamma 1.0 / scale 1.0 -> byte-exact linear remap.
  stb_hdr_to_ldr_gamma(1.0);
  stb_hdr_to_ldr_scale(1.0);
  let r9 = stb_load_rgba8_from_memory(&fixture, 3);
  if r9.is_ok {
    let img = r9.value;
    var ok9 = img.width == 4 && img.height == 1 && img.channels == 3;
    // pixel 0: 1.0/0.5/0.25 -> 255/128/64; pixel 1: 2.0/1.0/0.5 -> 255/255/128;
    // pixel 2: 0 -> 0; pixel 3: 2/4/6 -> 255 (clamped).
    ok9 = ok9 && img.data[0] == 255 as UInt8 && img.data[1] == 128 as UInt8
      && img.data[2] == 64 as UInt8;
    ok9 = ok9 && img.data[3] == 255 as UInt8 && img.data[4] == 255 as UInt8
      && img.data[5] == 128 as UInt8;
    ok9 = ok9 && img.data[6] == 0 as UInt8 && img.data[7] == 0 as UInt8
      && img.data[8] == 0 as UInt8;
    ok9 = ok9 && img.data[9] == 255 as UInt8 && img.data[10] == 255 as UInt8
      && img.data[11] == 255 as UInt8;
    failed = failed + report(ok9, "hdr->ldr: gamma=1.0 scale=1.0 byte-exact remap (12 bytes)");
  } else {
    failed = failed + report(false, "hdr->ldr gamma1: " + r9.error.message);
  }

  // 10. gamma 2.0 -> the library inverts to 0.5: 1.0/0.5/0.25 -> 255/180/128.
  stb_hdr_to_ldr_gamma(2.0);
  let r10 = stb_load_rgba8_from_memory(&fixture, 3);
  var ok10 = false;
  if r10.is_ok {
    ok10 = r10.value.data[0] == 255 as UInt8
      && r10.value.data[1] == 180 as UInt8
      && r10.value.data[2] == 128 as UInt8;
  }
  failed = failed + report(ok10, "hdr->ldr: gamma=2.0 -> pow(f,0.5) remap 255/180/128");
  stb_hdr_to_ldr_gamma(2.2);
  stb_hdr_to_ldr_scale(1.0);

  // 11. stbi_ldr_to_hdr_*: stbi_loadf on an 8-bit input.
  //     gamma=1/scale=1 -> 128/255 exactly; scale=2 doubles it exactly.
  stb_ldr_to_hdr_gamma(1.0);
  stb_ldr_to_hdr_scale(1.0);
  let rl1 = stb_loadf_from_memory(&bmp_fixture, 1);
  stb_ldr_to_hdr_scale(2.0);
  let rl2 = stb_loadf_from_memory(&bmp_fixture, 1);
  if rl1.is_ok && rl2.is_ok {
    let v1 = stb_pixel_f64(&rl1.value, 0, 0, 0);
    let v2 = stb_pixel_f64(&rl2.value, 0, 0, 0);
    let ok11 = v1 > 0.5019 && v1 < 0.5020 && v2 == v1 * 2.0
      && v2 > 1.0038 && v2 < 1.0040 && rl1.value.channels == 1;
    failed = failed + report(ok11, "ldr->hdr: gray128 gamma=1 scale=1 -> 128/255; scale=2 doubles exactly");
  } else {
    failed = failed + report(false, "ldr->hdr linear: load failed");
  }

  // 12. gamma=2.0 -> pow(128/255, 2) (nonlinear, range-checked).
  stb_ldr_to_hdr_gamma(2.0);
  stb_ldr_to_hdr_scale(1.0);
  let rl3 = stb_loadf_from_memory(&bmp_fixture, 1);
  var ok12 = false;
  if rl3.is_ok {
    let v3 = stb_pixel_f64(&rl3.value, 0, 0, 0);
    ok12 = v3 < 0.5019 && v3 > 0.2515 && v3 < 0.2525;
  }
  failed = failed + report(ok12, "ldr->hdr: gray128 gamma=2 -> pow(v,2) range-checked");
  stb_ldr_to_hdr_gamma(2.2);
  stb_ldr_to_hdr_scale(1.0);

  // ---- corrupt inputs ----------------------------------------------------

  // 13. Garbage -> typed error; the valid fixture still loads afterwards.
  var garbage = Vec[UInt8].new();
  var gi = 0;
  while gi < 10 {
    garbage.push((gi + 1) as UInt8);
    gi = gi + 1;
  }
  let r13 = stb_loadf_from_memory(&garbage, 0);
  var ok13 = !r13.is_ok && r13.error.code == STB_ERR_LOAD
    && r13.error.message.len() > 0;
  let r13b = stb_loadf_from_memory(&fixture, 0);
  ok13 = ok13 && r13b.is_ok && r13b.value.width == 4;
  failed = failed + report(ok13, "corrupt: garbage -> typed Err, valid fixture recovers");

  // 14. Bad FORMAT header -> typed error.
  let bad_format = hdr_bad_format();
  let r14 = stb_loadf_from_memory(&bad_format, 0);
  let ok14 = !r14.is_ok && r14.error.code == STB_ERR_LOAD
    && r14.error.message.len() > 0;
  failed = failed + report(ok14, "corrupt: FORMAT=bogus -> typed Err (" + r14.error.message + ")");

  // 15. Bad resolution line + missing file -> typed errors.
  let bad_layout = hdr_bad_layout();
  let r15 = stb_loadf_from_memory(&bad_layout, 0);
  var ok15 = !r15.is_ok && r15.error.code == STB_ERR_LOAD;
  let missing = io.join_paths(fs.fs_temp_dir(), "xiom_stb_no_such_file.hdr");
  let r15b = stb_loadf(missing, 0);
  ok15 = ok15 && !r15b.is_ok && r15b.error.code == STB_ERR_LOAD;
  ok15 = ok15 && !stb_hdr_is(missing) && !stb_hdr_is_from_file(missing);
  failed = failed + report(ok15, "corrupt: bad layout + missing file -> typed Err");

  // 16. Determinism: repeated HDR loads are byte-identical.
  let d1 = stb_loadf_from_memory(&fixture, 0);
  let d2 = stb_loadf_from_memory(&fixture, 0);
  let ok16 = d1.is_ok && d2.is_ok && bytes_equal(&d1.value.data, &d2.value.data);
  failed = failed + report(ok16, "determinism: repeated HDR loads byte-identical");

  if failed == 0 {
    io.println("xiom.stb: all tests passed");
  } else {
    io.println("xiom.stb: tests failed");
  }
  return failed;
}
