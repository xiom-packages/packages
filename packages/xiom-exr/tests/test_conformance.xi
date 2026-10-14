// xiom.exr conformance suite -- vendored tinyexr v3.2.0 (BSD-3).
//
// Fixtures are built with tinyexr's own save path (exr_save_to_memory) and
// read back through the declared reader surface.  All plane values are
// exactly representable in float32 AND float16, so every check is exact
// (Float64 reconstruction of the float32 bytes; no bitcast intrinsic).
// Corrupt paths: garbage (magic), truncated blob (chunk decode), and
// save-spec validation.  Str equality goes through string.str_compare.
//
// Build+run (the --c-source list rides in port.args.json):
//   scripts/port.ps1 -Package xiom.exr

module exr_conformance

use xiom.io;
use xiom.io.fs;
use xiom.test;
use xiom.exr;
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

fn b2s(b: Bool) -> Str {
  if b { return "true"; }
  return "false";
}

fn str_eq(a: Str, b: Str) -> Bool {
  return string.str_compare(a, b) == 0;
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

fn push_u32le(v: &mut Vec[UInt8], bits: Int)
  requires: bits >= 0
{
  v.push((bits & 255) as UInt8);
  v.push(((bits >> 8) & 255) as UInt8);
  v.push(((bits >> 16) & 255) as UInt8);
  v.push(((bits >> 24) & 255) as UInt8);
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

fn names_grb() -> Vec[Str]
  requires: true
{
  var n = Vec[Str].new();
  n.push("G");
  n.push("R");
  n.push("B");
  return n;
}

fn names_grba() -> Vec[Str]
  requires: true
{
  var n = Vec[Str].new();
  n.push("R");
  n.push("G");
  n.push("B");
  n.push("A");
  return n;
}

// 3x2 planar float32 planes for channels [G, R, B] (the save order):
// all values are exact in float32 (and float16).
fn planes_grb() -> Vec[UInt8]
  requires: true
{
  var v = Vec[UInt8].new();
  // G plane
  push_u32le(&mut v, 0x3F800000); // 1.0
  push_u32le(&mut v, 0xBF000000); // -0.5
  push_u32le(&mut v, 0x3E000000); // 0.125
  push_u32le(&mut v, 0x40800000); // 4.0
  push_u32le(&mut v, 0x00000000); // 0.0
  push_u32le(&mut v, 0x3F400000); // 0.75
  // R plane
  push_u32le(&mut v, 0x00000000); // 0.0
  push_u32le(&mut v, 0x3E800000); // 0.25
  push_u32le(&mut v, 0x3F000000); // 0.5
  push_u32le(&mut v, 0x3F800000); // 1.0
  push_u32le(&mut v, 0x40200000); // 2.5
  push_u32le(&mut v, 0xC0400000); // -3.0
  // B plane
  push_u32le(&mut v, 0xBF800000); // -1.0
  push_u32le(&mut v, 0x40000000); // 2.0
  push_u32le(&mut v, 0xC0000000); // -2.0
  push_u32le(&mut v, 0x3F000000); // 0.5
  push_u32le(&mut v, 0xBE800000); // -0.25
  push_u32le(&mut v, 0x41000000); // 8.0
  return v;
}

// 3x2 planar RGBA float32 planes (same values as planes_grb + an A plane).
fn planes_grba() -> Vec[UInt8]
  requires: true
{
  var v = Vec[UInt8].new();
  push_u32le(&mut v, 0x00000000); // R
  push_u32le(&mut v, 0x3E800000);
  push_u32le(&mut v, 0x3F000000);
  push_u32le(&mut v, 0x3F800000);
  push_u32le(&mut v, 0x40200000);
  push_u32le(&mut v, 0xC0400000);
  push_u32le(&mut v, 0x3F800000); // G
  push_u32le(&mut v, 0xBF000000);
  push_u32le(&mut v, 0x3E000000);
  push_u32le(&mut v, 0x40800000);
  push_u32le(&mut v, 0x00000000);
  push_u32le(&mut v, 0x3F400000);
  push_u32le(&mut v, 0xBF800000); // B
  push_u32le(&mut v, 0x40000000);
  push_u32le(&mut v, 0xC0000000);
  push_u32le(&mut v, 0x3F000000);
  push_u32le(&mut v, 0xBE800000);
  push_u32le(&mut v, 0x41000000);
  push_u32le(&mut v, 0x3F800000); // A
  push_u32le(&mut v, 0x3F000000);
  push_u32le(&mut v, 0x3E800000);
  push_u32le(&mut v, 0x3F400000);
  push_u32le(&mut v, 0x3E000000);
  push_u32le(&mut v, 0x40000000);
  return v;
}

fn check_planes_grb(img: &ExrImage) -> Bool
  requires: true
{
  let ig = exr_channel_index(img, "G");
  let ir = exr_channel_index(img, "R");
  let ib = exr_channel_index(img, "B");
  if ig < 0 || ir < 0 || ib < 0 { return false; }
  var ok = exr_pixel_f64(img, ig, 0, 0) == 1.0
    && exr_pixel_f64(img, ig, 1, 0) == -0.5
    && exr_pixel_f64(img, ig, 2, 0) == 0.125
    && exr_pixel_f64(img, ig, 0, 1) == 4.0
    && exr_pixel_f64(img, ig, 1, 1) == 0.0
    && exr_pixel_f64(img, ig, 2, 1) == 0.75;
  ok = ok && exr_pixel_f64(img, ir, 0, 0) == 0.0
    && exr_pixel_f64(img, ir, 1, 0) == 0.25
    && exr_pixel_f64(img, ir, 2, 0) == 0.5
    && exr_pixel_f64(img, ir, 0, 1) == 1.0
    && exr_pixel_f64(img, ir, 1, 1) == 2.5
    && exr_pixel_f64(img, ir, 2, 1) == -3.0;
  ok = ok && exr_pixel_f64(img, ib, 0, 0) == -1.0
    && exr_pixel_f64(img, ib, 1, 0) == 2.0
    && exr_pixel_f64(img, ib, 2, 0) == -2.0
    && exr_pixel_f64(img, ib, 0, 1) == 0.5
    && exr_pixel_f64(img, ib, 1, 1) == -0.25
    && exr_pixel_f64(img, ib, 2, 1) == 8.0;
  return ok;
}

fn main() -> Int {
  io.println("=== xiom.exr conformance tests (vendored tinyexr v3.2.0) ===");
  io.flush_stdout();
  var failed: Int = 0;

  // 1. Constants pinned against the vendored header + typed error names.
  let cst = EXR_PIXELTYPE_UINT == 0 && EXR_PIXELTYPE_HALF == 1
    && EXR_PIXELTYPE_FLOAT == 2 && EXR_ERROR_INVALID_MAGIC_NUMBER == -1
    && EXR_ERROR_INVALID_ARGUMENT == -3 && EXR_ERROR_INVALID_DATA == -4
    && EXR_ERROR_CANT_OPEN_FILE == -7 && EXR_COMPRESSION_NONE == 0
    && EXR_COMPRESSION_ZIP == 3 && EXR_MAX_HEADER_ATTRIBUTES == 1024
    && EXR_MAX_CUSTOM_ATTRIBUTES == 128;
  var names_ok = true;
  var code = -1;
  while code >= -14 {
    if str_eq(exr_error_name(code), "UNKNOWN") { names_ok = false; }
    code = code - 1;
  }
  names_ok = names_ok && str_eq(exr_error_name(-3), "INVALID_ARGUMENT")
    && str_eq(exr_error_name(0), "SUCCESS");
  failed = failed + report(cst && names_ok, "constants: pixel types/errors/compression pinned + error names");

  // 2. Save a 3x2 3-channel float EXR through tinyexr's writer.
  let spec = ExrSaveSpec{
    width: 3;
    height: 2;
    fp16: false;
    names: names_grb();
    data: planes_grb();
  };
  let saved = exr_save_to_memory(&spec);
  var bytes: Vec[UInt8] = Vec[UInt8].new();
  if saved.is_ok {
    bytes = saved.value;
    failed = failed + report(bytes.len() > 64 && exr_is_exr_from_memory(&bytes),
      "save fp32: " + i2s(bytes.len()) + " bytes; is_exr=true");
  } else {
    failed = failed + report(false, "save fp32: " + saved.error.message);
  }

  // 3. Read back: dimensions, channel count, names via lookup, exact planes.
  var img_ok = false;
  if bytes.len() > 0 {
    let r = exr_load_from_memory(&bytes);
    if r.is_ok {
      let img = r.value;
      img_ok = img.width == 3 && img.height == 2 && img.channels == 3
        && img.names.len() == 3 && img.pixel_types.len() == 3
        && check_planes_grb(&img);
      let ig = exr_channel_index(&img, "G");
      if ig >= 0 && img.pixel_types[ig] != EXR_PIXELTYPE_FLOAT { img_ok = false; }
      failed = failed + report(img_ok, "load fp32: 3x2x3, names G/R/B via lookup, 18 values exact");
    } else {
      failed = failed + report(false, "load fp32: " + r.error.message);
    }
  } else {
    failed = failed + report(false, "load fp32: no fixture bytes");
  }

  // 4. Metadata: compression NONE, data window 0,0..2,1.
  if bytes.len() > 0 {
    let r = exr_load_from_memory(&bytes);
    var meta_ok = false;
    if r.is_ok {
      let img = r.value;
      meta_ok = img.compression == EXR_COMPRESSION_NONE
        && img.window_min_x == 0 && img.window_min_y == 0
        && img.window_max_x == 2 && img.window_max_y == 1;
    }
    failed = failed + report(meta_ok, "metadata: compression=NONE, data window 0,0..2,1");
  } else {
    failed = failed + report(false, "metadata: no fixture bytes");
  }

  // 5. Save determinism: the writer is byte-identical across runs.
  let saved2 = exr_save_to_memory(&spec);
  let det_ok = saved.is_ok && saved2.is_ok && bytes_equal(&bytes, &saved2.value);
  failed = failed + report(det_ok, "determinism: repeated saves byte-identical");

  // 6. fp16: declared types become HALF; values (half-exact) unchanged.
  let spec16 = ExrSaveSpec{
    width: 3;
    height: 2;
    fp16: true;
    names: names_grb();
    data: planes_grb();
  };
  let saved16 = exr_save_to_memory(&spec16);
  if saved16.is_ok {
    let r = exr_load_from_memory(&saved16.value);
    var ok16 = false;
    if r.is_ok {
      let img = r.value;
      let ir = exr_channel_index(&img, "R");
      ok16 = img.channels == 3 && check_planes_grb(&img);
      if ir >= 0 && img.pixel_types[ir] != EXR_PIXELTYPE_HALF { ok16 = false; }
    }
    failed = failed + report(ok16, "fp16: save -> load keeps exact values, declared types HALF");
  } else {
    failed = failed + report(false, "fp16 save: " + saved16.error.message);
  }

  // 7. File entries: is_exr_from_file + load_from_file + missing path.
  if bytes.len() > 0 {
    let tmp = io.join_paths(fs.fs_temp_dir(), "xiom_exr_fixture.exr");
    let wr = fs.fs_write(tmp, &bytes);
    var ok7 = false;
    if wr.is_ok {
      ok7 = exr_is_exr_from_file(tmp);
      let rf = exr_load_from_file(tmp);
      if rf.is_ok {
        ok7 = ok7 && rf.value.width == 3 && rf.value.height == 2
          && check_planes_grb(&rf.value);
      } else {
        ok7 = false;
      }
      let rm7 = io.remove_file(tmp);
    }
    let missing = io.join_paths(fs.fs_temp_dir(), "xiom_exr_no_such_file.exr");
    let miss_load = exr_load_from_file(missing);
    ok7 = ok7 && !exr_is_exr_from_file(missing) && !miss_load.is_ok
      && miss_load.error.message.len() > 0;
    failed = failed + report(ok7, "file: is_exr_from_file + load_from_file exact; missing path typed Err");
  } else {
    failed = failed + report(false, "file: no fixture bytes");
  }

  // 8. RGBA: 4 declared channels, alpha plane exact.
  let spec4 = ExrSaveSpec{
    width: 3;
    height: 2;
    fp16: false;
    names: names_grba();
    data: planes_grba();
  };
  let saved4 = exr_save_to_memory(&spec4);
  if saved4.is_ok {
    let r = exr_load_from_memory(&saved4.value);
    var ok8 = false;
    if r.is_ok {
      let img = r.value;
      let ia = exr_channel_index(&img, "A");
      ok8 = img.channels == 4 && img.names.len() == 4 && ia >= 0;
      if ia >= 0 {
        ok8 = ok8 && exr_pixel_f64(&img, ia, 0, 0) == 1.0
          && exr_pixel_f64(&img, ia, 1, 0) == 0.5
          && exr_pixel_f64(&img, ia, 2, 0) == 0.25
          && exr_pixel_f64(&img, ia, 0, 1) == 0.75
          && exr_pixel_f64(&img, ia, 1, 1) == 0.125
          && exr_pixel_f64(&img, ia, 2, 1) == 2.0;
      }
    }
    failed = failed + report(ok8, "rgba: 4 channels, alpha plane exact (6 values)");
  } else {
    failed = failed + report(false, "rgba save: " + saved4.error.message);
  }

  // 9. Corrupt: garbage -> INVALID_MAGIC_NUMBER typed error.
  var garbage = Vec[UInt8].new();
  var gi = 0;
  while gi < 16 {
    garbage.push(171 as UInt8);
    gi = gi + 1;
  }
  let rg = exr_load_from_memory(&garbage);
  let ok9 = !rg.is_ok && rg.error.code == EXR_ERROR_INVALID_MAGIC_NUMBER
    && rg.error.message.len() > 0 && !exr_is_exr_from_memory(&garbage);
  failed = failed + report(ok9, "corrupt: garbage -> INVALID_MAGIC_NUMBER (" + rg.error.message + ")");

  // 10. Corrupt: truncated blob -> INVALID_DATA typed error.
  if bytes.len() > 24 {
    var trunc = Vec[UInt8].new();
    let keep = bytes.len() - 24;
    var ti = 0;
    while ti < keep {
      trunc.push(bytes[ti]);
      ti = ti + 1;
    }
    let rt = exr_load_from_memory(&trunc);
    let ok10 = !rt.is_ok && rt.error.code == EXR_ERROR_INVALID_DATA
      && rt.error.message.len() > 0;
    failed = failed + report(ok10, "corrupt: truncated by 24 bytes -> INVALID_DATA (" + rt.error.message + ")");
  } else {
    failed = failed + report(false, "corrupt: fixture too small to truncate");
  }

  // 11. Save-spec validation: planar data size mismatch -> typed error.
  var short_data = Vec[UInt8].new();
  short_data.push(0 as UInt8);
  let bad_spec = ExrSaveSpec{
    width: 3;
    height: 2;
    fp16: false;
    names: names_grb();
    data: short_data;
  };
  let rb = exr_save_to_memory(&bad_spec);
  let ok11 = !rb.is_ok && rb.error.code == EXR_ERROR_INVALID_ARGUMENT
    && rb.error.message.len() > 0;
  failed = failed + report(ok11, "save: planar data size mismatch -> INVALID_ARGUMENT");

  // 12. Determinism: repeated loads are byte-identical.
  if bytes.len() > 0 {
    let l1 = exr_load_from_memory(&bytes);
    let l2 = exr_load_from_memory(&bytes);
    let ok12 = l1.is_ok && l2.is_ok && bytes_equal(&l1.value.data, &l2.value.data);
    failed = failed + report(ok12, "determinism: repeated loads byte-identical");
  } else {
    failed = failed + report(false, "determinism: no fixture bytes");
  }

  if failed == 0 {
    io.println("xiom.exr: all tests passed");
  } else {
    io.println("xiom.exr: tests failed");
  }
  return failed;
}
