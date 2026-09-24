// XIOM -- xiom.ppm conformance tests (18 checks)
// Port task: prove the pure-XIOM xiom.ppm module against Netpbm P3/P6.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module ppm_tests
use xiom.io; use xiom.test; use xiom.ppm;
use xiom.string; use xiom.string.compare;

// All Str equality goes through str_compare: `==` on Str lowered from a
// Vec[Str] element is a pointer comparison in v0.61.3, so comparisons are
// routed through streq and the typed Vec reads below.

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// ASCII bytes of a literal, used to hand-build malformed inputs.
fn bytes_of(s: Str) -> Vec[UInt8] {
  let v = Vec[UInt8].new();
  let n = s.len();
  var i = 0;
  while (i < n) {
    let b: UInt8 = string.byte_at(s, i);
    v.push(b);
    i = i + 1;
  }
  return v;
}

// Byte-wise equality of a built vector against a literal.
fn vec_is_str(data: &Vec[UInt8], want: Str) -> Bool {
  if (data.len() != want.len()) { return false; }
  var i = 0;
  while (i < data.len()) {
    let b: UInt8 = data[i];
    let c: UInt8 = string.byte_at(want, i);
    if (b != c) { return false; }
    i = i + 1;
  }
  return true;
}

// True when `data` starts with the literal `want`.
fn bytes_prefix_is(data: &Vec[UInt8], want: Str) -> Bool {
  let n = want.len();
  if (data.len() < n) { return false; }
  var i = 0;
  while (i < n) {
    let b: UInt8 = data[i];
    let c: UInt8 = string.byte_at(want, i);
    if (b != c) { return false; }
    i = i + 1;
  }
  return true;
}

fn byte_is(data: &Vec[UInt8], i: Int, want: Int) -> Bool {
  let b: Int = (data[i] as Int) & 0xFF;
  return b == want;
}

fn ok_bytes(r: Result[Vec[UInt8], Str]) -> Vec[UInt8] {
  match r {
    Ok(v) => { return v; },
    Err(e) => { return Vec[UInt8].new(); },
  }
}

fn bad_bytes(r: Result[Vec[UInt8], Str]) -> Bool {
  match r {
    Ok(v) => { return false; },
    Err(e) => { return true; },
  }
}

fn bytes_err_is(r: Result[Vec[UInt8], Str], want: Str) -> Bool {
  match r {
    Ok(v) => { return false; },
    Err(e) => { return streq(e, want); },
  }
}

fn ok_img(r: Result[PpmImage, Str]) -> PpmImage {
  match r {
    Ok(v) => { return v; },
    Err(e) => { return PpmImage{ format: 0; width: 0; height: 0; maxval: 0; data_offset: 0; }; },
  }
}

fn bad_img(r: Result[PpmImage, Str]) -> Bool {
  match r {
    Ok(v) => { return false; },
    Err(e) => { return true; },
  }
}

fn img_err_is(r: Result[PpmImage, Str], want: Str) -> Bool {
  match r {
    Ok(v) => { return false; },
    Err(e) => { return streq(e, want); },
  }
}

fn pix(data: &Vec[UInt8], x: Int, y: Int) -> Int {
  match ppm_pixel_rgb(data, x, y) {
    Ok(v) => { return v; },
    Err(e) => { return -1; },
  }
}

fn bad_pixel(data: &Vec[UInt8], x: Int, y: Int) -> Bool {
  match ppm_pixel_rgb(data, x, y) {
    Ok(v) => { return false; },
    Err(e) => { return true; },
  }
}

fn pixel_err_is(data: &Vec[UInt8], x: Int, y: Int, want: Str) -> Bool {
  match ppm_pixel_rgb(data, x, y) {
    Ok(v) => { return false; },
    Err(e) => { return streq(e, want); },
  }
}

fn rgb3(r: Int, g: Int, b: Int) -> Int {
  return r * 65536 + g * 256 + b;
}

// Top-left scan order: TL red, TR green, BL blue, BR white.
fn make_rgb2x2() -> Vec[UInt8] {
  let v = Vec[UInt8].new();
  v.push(255 as UInt8); v.push(0 as UInt8); v.push(0 as UInt8);
  v.push(0 as UInt8); v.push(255 as UInt8); v.push(0 as UInt8);
  v.push(0 as UInt8); v.push(0 as UInt8); v.push(255 as UInt8);
  v.push(255 as UInt8); v.push(255 as UInt8); v.push(255 as UInt8);
  return v;
}

fn t1() -> TestResult {
  let data = ok_bytes(ppm_build_p6(make_rgb2x2(), 2, 2));
  if (data.len() != 23) { return assert(false, "built 2x2 P6 is 23 bytes"); }
  let r = ppm_parse_header(data);
  match r {
    Ok(img) => {
      if (img.format != 6) { return assert(false, "P6 format is 6"); }
      if (img.width != 2) { return assert(false, "parsed width 2"); }
      if (img.height != 2) { return assert(false, "parsed height 2"); }
      if (img.maxval != 255) { return assert(false, "parsed maxval 255"); }
      if (img.data_offset != 11) { return assert(false, "P6 data offset is 11"); }
      if (ppm_sample_count(&img) != 12) { return assert(false, "sample count 12"); }
      return assert(true, "P6 header parses with offset 11");
    },
    Err(e) => { return assert(false, "built P6 header failed to parse"); },
  }
}

fn t2() -> TestResult {
  let data = bytes_of("P3\n2 1\n255\n10 20 30 40 50 60");
  let r = ppm_parse_header(data);
  match r {
    Ok(img) => {
      if (img.format != 3) { return assert(false, "P3 format is 3"); }
      if (img.width != 2) { return assert(false, "parsed width 2"); }
      if (img.height != 1) { return assert(false, "parsed height 1"); }
      if (img.maxval != 255) { return assert(false, "parsed maxval 255"); }
      if (img.data_offset != 11) { return assert(false, "P3 data offset is 11"); }
      if (ppm_sample_count(&img) != 6) { return assert(false, "sample count 6"); }
      return assert(true, "P3 header parses with offset 11");
    },
    Err(e) => { return assert(false, "P3 header failed to parse"); },
  }
}

fn t3() -> TestResult {
  let d1 = bytes_of("P6\n# first\n2 2 # inline\n255\n");
  var i = 0;
  while (i < 12) { d1.push((i + 7) as UInt8); i = i + 1; }
  let r1 = ppm_parse_header(d1);
  match r1 {
    Ok(img) => {
      if (img.data_offset != 28) { return assert(false, "comment header sets offset 28"); }
      if (img.width != 2) { return assert(false, "comment width 2"); }
      if (img.height != 2) { return assert(false, "comment height 2"); }
      if (pix(d1, 0, 0) != rgb3(7, 8, 9)) { return assert(false, "comment raster first pixel"); }
    },
    Err(e) => { return assert(false, "comment P6 header failed to parse"); },
  }
  let d2 = bytes_of("P3\n# a\n1 1\n# b\n255\n# c\n7 8 9");
  let r2 = ppm_parse_header(d2);
  match r2 {
    Ok(img) => {
      if (img.data_offset != 23) { return assert(false, "P3 comment offset is 23"); }
      if (img.width != 1) { return assert(false, "P3 comment width 1"); }
      if (img.maxval != 255) { return assert(false, "P3 comment maxval 255"); }
    },
    Err(e) => { return assert(false, "comment P3 header failed to parse"); },
  }
  return assert(true, "comments are skipped between header tokens");
}

fn t4() -> TestResult {
  let d = Vec[UInt8].new();
  d.push(80 as UInt8); d.push(54 as UInt8);
  d.push(13 as UInt8); d.push(10 as UInt8); d.push(9 as UInt8); d.push(32 as UInt8);
  d.push(50 as UInt8);
  d.push(11 as UInt8); d.push(12 as UInt8);
  d.push(50 as UInt8);
  d.push(32 as UInt8);
  d.push(50 as UInt8); d.push(53 as UInt8); d.push(53 as UInt8);
  d.push(10 as UInt8);
  var i = 0;
  while (i < 12) { d.push(i as UInt8); i = i + 1; }
  let r = ppm_parse_header(d);
  match r {
    Ok(img) => {
      if (img.width != 2) { return assert(false, "mixed-space width 2"); }
      if (img.height != 2) { return assert(false, "mixed-space height 2"); }
      if (img.maxval != 255) { return assert(false, "mixed-space maxval 255"); }
      if (img.data_offset != 15) { return assert(false, "mixed-space offset 15"); }
      if (pix(d, 0, 0) != rgb3(0, 1, 2)) { return assert(false, "mixed-space first pixel"); }
    },
    Err(e) => { return assert(false, "mixed whitespace header failed to parse"); },
  }
  return assert(true, "CR LF TAB VT FF and SPACE all separate tokens");
}

fn t5() -> TestResult {
  let d1 = bytes_of("P6\n1 1\n0\n");
  d1.push(1 as UInt8); d1.push(2 as UInt8); d1.push(3 as UInt8);
  if (!img_err_is(ppm_parse_header(d1), "ppm: invalid maxval")) {
    return assert(false, "P6 maxval 0 is invalid maxval");
  }
  let d2 = bytes_of("P3\n1 1\n0\n1 2 3");
  if (!img_err_is(ppm_parse_header(d2), "ppm: invalid maxval")) {
    return assert(false, "P3 maxval 0 is invalid maxval");
  }
  let d3 = bytes_of("P6\n1 1\n65536\n");
  d3.push(1 as UInt8); d3.push(2 as UInt8); d3.push(3 as UInt8);
  if (!img_err_is(ppm_parse_header(d3), "ppm: invalid maxval")) {
    return assert(false, "maxval above 65535 is invalid");
  }
  return assert(true, "maxval must be 1..65535");
}

fn t6() -> TestResult {
  let data = ok_bytes(ppm_build_p6(make_rgb2x2(), 2, 2));
  data[0] = 88 as UInt8;
  if (!img_err_is(ppm_parse_header(data), "ppm: bad magic")) {
    return assert(false, "non-P byte is bad magic");
  }
  let d2 = ok_bytes(ppm_build_p6(make_rgb2x2(), 2, 2));
  d2[1] = 55 as UInt8;
  if (!bad_img(ppm_parse_header(d2))) { return assert(false, "P7 is rejected"); }
  let short = Vec[UInt8].new();
  short.push(80 as UInt8);
  if (!bad_img(ppm_parse_header(short))) { return assert(false, "1-byte buffer is rejected"); }
  return assert(true, "only P3/P6 magic is accepted");
}

fn t7() -> TestResult {
  let d1 = bytes_of("P6\n2 2\n255\n");
  var i = 0;
  while (i < 5) { d1.push(i as UInt8); i = i + 1; }
  if (!img_err_is(ppm_parse_header(d1), "ppm: truncated pixel data")) {
    return assert(false, "5 of 12 raster bytes is truncated");
  }
  let d2 = bytes_of("P6\n2 2\n255x");
  if (!img_err_is(ppm_parse_header(d2), "ppm: missing whitespace after maxval")) {
    return assert(false, "raster byte directly after maxval is rejected");
  }
  let d3 = bytes_of("P6\n2 2\n255");
  if (!img_err_is(ppm_parse_header(d3), "ppm: truncated pixel data")) {
    return assert(false, "EOF right after maxval is truncated");
  }
  let d4 = bytes_of("P3\n2 1\n255\n10 20");
  if (!img_err_is(ppm_parse_header(d4), "ppm: truncated pixel data")) {
    return assert(false, "2 of 6 P3 samples is truncated");
  }
  let d5 = bytes_of("P3\n1 1\n255\n");
  if (!img_err_is(ppm_parse_header(d5), "ppm: truncated pixel data")) {
    return assert(false, "header-only P3 is truncated");
  }
  return assert(true, "missing raster data is rejected for P6 and P3");
}

fn t8() -> TestResult {
  let src = make_rgb2x2();
  let data = ok_bytes(ppm_build_p6(src, 2, 2));
  if (data.len() != 11 + 12) { return assert(false, "raster starts at 11 and is 12 bytes"); }
  var i = 0;
  while (i < 12) {
    let b: Int = (data[11 + i] as Int) & 0xFF;
    let s: Int = (src[i] as Int) & 0xFF;
    if (b != s) { return assert(false, "raster bytes match the source with no padding"); }
    i = i + 1;
  }
  if (pix(data, 0, 0) != rgb3(255, 0, 0)) { return assert(false, "TL is red"); }
  if (pix(data, 1, 0) != rgb3(0, 255, 0)) { return assert(false, "TR is green"); }
  if (pix(data, 0, 1) != rgb3(0, 0, 255)) { return assert(false, "BL is blue"); }
  if (pix(data, 1, 1) != rgb3(255, 255, 255)) { return assert(false, "BR is white"); }
  return assert(true, "2x2 P6 round-trips with padding-free exact bytes");
}

fn t9() -> TestResult {
  let data = ok_bytes(ppm_build_p6(make_rgb2x2(), 2, 2));
  if (!bad_pixel(data, -1, 0)) { return assert(false, "x=-1 is Err"); }
  if (!bad_pixel(data, 0, -1)) { return assert(false, "y=-1 is Err"); }
  if (!bad_pixel(data, 2, 0)) { return assert(false, "x=width is Err"); }
  if (!bad_pixel(data, 0, 2)) { return assert(false, "y=height is Err"); }
  if (!pixel_err_is(data, 5, 5, "ppm: pixel out of range")) {
    return assert(false, "out-of-range message");
  }
  return assert(true, "out-of-range pixels are Err");
}

fn t10() -> TestResult {
  let d1 = bytes_of("P6\n2 2\n512\n");
  var i = 0;
  while (i < 24) { d1.push((i % 256) as UInt8); i = i + 1; }
  let r = ppm_parse_header(d1);
  match r {
    Ok(img) => {
      if (img.maxval != 512) { return assert(false, "16-bit header keeps maxval"); }
      if (img.data_offset != 11) { return assert(false, "16-bit header offset 11"); }
      if (!pixel_err_is(d1, 0, 0, "ppm: 16-bit samples unsupported")) {
        return assert(false, "pixel access on 16-bit P6 is Err");
      }
    },
    Err(e) => { return assert(false, "16-bit P6 header should still parse"); },
  }
  let d2 = bytes_of("P6\n1 1\n1000\n");
  i = 0;
  while (i < 6) { d2.push(0 as UInt8); i = i + 1; }
  if (!bad_pixel(d2, 0, 0)) { return assert(false, "maxval 1000 pixel access is Err"); }
  return assert(true, "16-bit maxval parses but pixel access is Err");
}

fn t11() -> TestResult {
  let data = ok_bytes(ppm_build_p3(make_rgb2x2(), 2, 2, 3));
  if (!pixel_err_is(data, 0, 0, "ppm: pixel accessor requires P6")) {
    return assert(false, "P3 pixel access is Err");
  }
  if (!pixel_err_is(data, 1, 1, "ppm: pixel accessor requires P6")) {
    return assert(false, "P3 pixel access is Err for every coordinate");
  }
  return assert(true, "ppm_pixel_rgb only serves binary P6");
}

fn t12() -> TestResult {
  let one = Vec[UInt8].new();
  one.push(1 as UInt8); one.push(2 as UInt8); one.push(3 as UInt8);
  let data = ok_bytes(ppm_build_p6(one, 1, 1));
  if (data.len() != 14) { return assert(false, "1x1 P6 is 11 + 3 bytes"); }
  if (!bytes_prefix_is(data, "P6\n1 1\n255\n")) { return assert(false, "1x1 header literal"); }
  if (!byte_is(data, 11, 1)) { return assert(false, "1x1 R byte"); }
  if (!byte_is(data, 12, 2)) { return assert(false, "1x1 G byte"); }
  if (!byte_is(data, 13, 3)) { return assert(false, "1x1 B byte"); }
  let data2 = ok_bytes(ppm_build_p6(make_rgb2x2(), 2, 2));
  if (data2.len() != 23) { return assert(false, "2x2 P6 is 11 + 12 bytes"); }
  if (!bytes_prefix_is(data2, "P6\n2 2\n255\n")) { return assert(false, "2x2 header literal"); }
  return assert(true, "build_p6 emits the canonical header and exact length");
}

fn t13() -> TestResult {
  let one = Vec[UInt8].new();
  one.push(1 as UInt8);
  if (!bytes_err_is(ppm_build_p6(one, 2, 2), "ppm: pixel buffer size mismatch")) {
    return assert(false, "short buffer for 2x2 P6");
  }
  let two = Vec[UInt8].new();
  two.push(1 as UInt8); two.push(2 as UInt8);
  if (!bytes_err_is(ppm_build_p3(two, 1, 1, 3), "ppm: pixel buffer size mismatch")) {
    return assert(false, "short buffer for 1x1 P3");
  }
  let exact = ppm_build_p6(make_rgb2x2(), 2, 2);
  match exact {
    Ok(v) => {
      if (v.len() != 23) { return assert(false, "exact-size build succeeds"); }
    },
    Err(e) => { return assert(false, "exact-size build must succeed"); },
  }
  return assert(true, "rgb length must equal width*height*3");
}

fn t14() -> TestResult {
  let src = Vec[UInt8].new();
  src.push(1 as UInt8); src.push(2 as UInt8); src.push(3 as UInt8);
  let data = ok_bytes(ppm_build_p3(src, 1, 1, 3));
  if (data.len() != 17) { return assert(false, "1x1 P3 is 17 bytes"); }
  if (!vec_is_str(data, "P3\n1 1\n255\n1 2 3\n")) {
    return assert(false, "canonical 1x1 P3 output is pinned");
  }
  return assert(true, "build_p3 pins the canonical 1x1 output");
}

fn t15() -> TestResult {
  let src = Vec[UInt8].new();
  src.push(1 as UInt8); src.push(2 as UInt8); src.push(3 as UInt8);
  src.push(4 as UInt8); src.push(5 as UInt8); src.push(6 as UInt8);
  src.push(7 as UInt8); src.push(8 as UInt8); src.push(9 as UInt8);
  src.push(10 as UInt8); src.push(20 as UInt8); src.push(30 as UInt8);
  let wrap2 = ok_bytes(ppm_build_p3(src, 2, 2, 2));
  if (!vec_is_str(wrap2, "P3\n2 2\n255\n1 2\n3 4\n5 6\n7 8\n9 10\n20 30\n")) {
    return assert(false, "samples_per_line 2 wraps with single spaces and LF");
  }
  let back = ok_img(ppm_parse_header(wrap2));
  if (back.data_offset != 11) { return assert(false, "wrapped P3 still parses (offset 11)"); }
  if (back.width != 2) { return assert(false, "wrapped P3 width 2"); }
  let clamped = ok_bytes(ppm_build_p3(src, 2, 2, 0));
  if (!vec_is_str(clamped, "P3\n2 2\n255\n1\n2\n3\n4\n5\n6\n7\n8\n9\n10\n20\n30\n")) {
    return assert(false, "samples_per_line below 1 clamps to 1");
  }
  let wide = ok_bytes(ppm_build_p3(src, 2, 2, 100));
  if (!vec_is_str(wide, "P3\n2 2\n255\n1 2 3 4 5 6 7 8 9 10 20 30\n")) {
    return assert(false, "samples_per_line above the raster keeps one line");
  }
  return assert(true, "build_p3 wraps, clamps and terminates with one LF");
}

fn t16() -> TestResult {
  let v = Vec[UInt8].new();
  if (!bytes_err_is(ppm_build_p6(v, 0, 1), "ppm: invalid width")) {
    return assert(false, "P6 width 0 is Err");
  }
  if (!bytes_err_is(ppm_build_p6(v, 1, 0), "ppm: invalid height")) {
    return assert(false, "P6 height 0 is Err");
  }
  if (!bytes_err_is(ppm_build_p6(v, -1, 1), "ppm: invalid width")) {
    return assert(false, "P6 negative width is Err");
  }
  if (!bytes_err_is(ppm_build_p3(v, 0, 0, 3), "ppm: invalid width")) {
    return assert(false, "P3 width 0 is Err");
  }
  if (!bytes_err_is(ppm_build_p3(v, 1, -1, 3), "ppm: invalid height")) {
    return assert(false, "P3 negative height is Err");
  }
  return assert(true, "non-positive dimensions are rejected");
}

fn t17() -> TestResult {
  let src = Vec[UInt8].new();
  var y = 0;
  while (y < 7) {
    var x = 0;
    while (x < 5) {
      src.push((x * 30) as UInt8);
      src.push((y * 20) as UInt8);
      src.push(((x + y) * 10) as UInt8);
      x = x + 1;
    }
    y = y + 1;
  }
  let data = ok_bytes(ppm_build_p6(src, 5, 7));
  if (data.len() != 11 + 105) { return assert(false, "5x7 P6 is 11 + 105 bytes"); }
  var i = 0;
  while (i < 105) {
    let b: Int = (data[11 + i] as Int) & 0xFF;
    let s: Int = (src[i] as Int) & 0xFF;
    if (b != s) { return assert(false, "5x7 raster bytes match"); }
    i = i + 1;
  }
  var yy = 0;
  while (yy < 7) {
    var xx = 0;
    while (xx < 5) {
      if (pix(data, xx, yy) != rgb3(xx * 30, yy * 20, (xx + yy) * 10)) {
        return assert(false, "5x7 pixel mismatch");
      }
      xx = xx + 1;
    }
    yy = yy + 1;
  }
  return assert(true, "5x7 P6 all-pixel round-trip");
}

fn t18() -> TestResult {
  let p6 = ok_bytes(ppm_build_p6(make_rgb2x2(), 2, 2));
  let i6 = ok_img(ppm_parse_header(p6));
  if (ppm_sample_count(&i6) != 12) { return assert(false, "2x2 has 12 samples"); }
  let p3 = bytes_of("P3\n1 1\n255\n1 2 3");
  let i3 = ok_img(ppm_parse_header(p3));
  if (ppm_sample_count(&i3) != 3) { return assert(false, "1x1 has 3 samples"); }
  let d = bytes_of("P6\n3 4\n255\n");
  var i = 0;
  while (i < 36) { d.push(0 as UInt8); i = i + 1; }
  let i34 = ok_img(ppm_parse_header(d));
  if (ppm_sample_count(&i34) != 36) { return assert(false, "3x4 has 36 samples"); }
  return assert(true, "ppm_sample_count is width*height*3");
}

fn main() -> Int {
  io.println("=== xiom.ppm conformance tests ===");
  var failed: Int = 0;
  let r1 = t1();
  if r1.passed { io.println("  [PASS] " + r1.name); } else { io.println("  [FAIL] " + r1.name); failed = failed + 1; }
  let r2 = t2();
  if r2.passed { io.println("  [PASS] " + r2.name); } else { io.println("  [FAIL] " + r2.name); failed = failed + 1; }
  let r3 = t3();
  if r3.passed { io.println("  [PASS] " + r3.name); } else { io.println("  [FAIL] " + r3.name); failed = failed + 1; }
  let r4 = t4();
  if r4.passed { io.println("  [PASS] " + r4.name); } else { io.println("  [FAIL] " + r4.name); failed = failed + 1; }
  let r5 = t5();
  if r5.passed { io.println("  [PASS] " + r5.name); } else { io.println("  [FAIL] " + r5.name); failed = failed + 1; }
  let r6 = t6();
  if r6.passed { io.println("  [PASS] " + r6.name); } else { io.println("  [FAIL] " + r6.name); failed = failed + 1; }
  let r7 = t7();
  if r7.passed { io.println("  [PASS] " + r7.name); } else { io.println("  [FAIL] " + r7.name); failed = failed + 1; }
  let r8 = t8();
  if r8.passed { io.println("  [PASS] " + r8.name); } else { io.println("  [FAIL] " + r8.name); failed = failed + 1; }
  let r9 = t9();
  if r9.passed { io.println("  [PASS] " + r9.name); } else { io.println("  [FAIL] " + r9.name); failed = failed + 1; }
  let r10 = t10();
  if r10.passed { io.println("  [PASS] " + r10.name); } else { io.println("  [FAIL] " + r10.name); failed = failed + 1; }
  let r11 = t11();
  if r11.passed { io.println("  [PASS] " + r11.name); } else { io.println("  [FAIL] " + r11.name); failed = failed + 1; }
  let r12 = t12();
  if r12.passed { io.println("  [PASS] " + r12.name); } else { io.println("  [FAIL] " + r12.name); failed = failed + 1; }
  let r13 = t13();
  if r13.passed { io.println("  [PASS] " + r13.name); } else { io.println("  [FAIL] " + r13.name); failed = failed + 1; }
  let r14 = t14();
  if r14.passed { io.println("  [PASS] " + r14.name); } else { io.println("  [FAIL] " + r14.name); failed = failed + 1; }
  let r15 = t15();
  if r15.passed { io.println("  [PASS] " + r15.name); } else { io.println("  [FAIL] " + r15.name); failed = failed + 1; }
  let r16 = t16();
  if r16.passed { io.println("  [PASS] " + r16.name); } else { io.println("  [FAIL] " + r16.name); failed = failed + 1; }
  let r17 = t17();
  if r17.passed { io.println("  [PASS] " + r17.name); } else { io.println("  [FAIL] " + r17.name); failed = failed + 1; }
  let r18 = t18();
  if r18.passed { io.println("  [PASS] " + r18.name); } else { io.println("  [FAIL] " + r18.name); failed = failed + 1; }
  if failed == 0 {
    io.println("xiom.ppm: all tests passed");
  } else {
    io.println("xiom.ppm: tests failed");
  }
  return failed;
}
