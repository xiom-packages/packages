// XIOM -- xiom.farbfeld conformance tests (17 checks)
// Port task: prove the pure-XIOM xiom.farbfeld module against farbfeld.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module farbfeld_tests
use xiom.io; use xiom.test; use xiom.farbfeld;
use xiom.string; use xiom.string.compare;

// All Str equality goes through str_compare: `==` on Str lowered from a
// Vec[Str] element is a pointer comparison in v0.61.3, so every error-message
// comparison is routed through streq.

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// ASCII bytes of a literal.
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

// Byte-wise equality of two vectors (0..255 widened).
fn vec_eq(a: &Vec[UInt8], b: &Vec[UInt8]) -> Bool {
  if (a.len() != b.len()) { return false; }
  var i = 0;
  while (i < a.len()) {
    let x: Int = (a[i] as Int) & 0xFF;
    let y: Int = (b[i] as Int) & 0xFF;
    if (x != y) { return false; }
    i = i + 1;
  }
  return true;
}

fn byte_is(data: &Vec[UInt8], i: Int, want: Int) -> Bool {
  let b: Int = (data[i] as Int) & 0xFF;
  return b == want;
}

// True when `data` starts with every byte of `want`.
fn prefix_is(data: &Vec[UInt8], want: &Vec[UInt8]) -> Bool {
  if (data.len() < want.len()) { return false; }
  var i = 0;
  while (i < want.len()) {
    let a: UInt8 = data[i];
    let b: UInt8 = want[i];
    if (a != b) { return false; }
    i = i + 1;
  }
  return true;
}

// Append a big-endian 32-bit value (test-side header construction).
fn push_be32(v: &mut Vec[UInt8], n: Int) {
  v.push(((n / 16777216) % 256) as UInt8);
  v.push(((n / 65536) % 256) as UInt8);
  v.push(((n / 256) % 256) as UInt8);
  v.push((n % 256) as UInt8);
}

// Hand-built 16-byte header for (w, h): magic, BE32(w), BE32(h).
fn raw_header(w: Int, h: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  v.push(102 as UInt8);
  v.push(97 as UInt8);
  v.push(114 as UInt8);
  v.push(98 as UInt8);
  v.push(102 as UInt8);
  v.push(101 as UInt8);
  v.push(108 as UInt8);
  v.push(100 as UInt8);
  push_be32(&mut v, w);
  push_be32(&mut v, h);
  return v;
}

// Four channels as a flat Vec[Int].
fn channels4(r: Int, g: Int, b: Int, a: Int) -> Vec[Int] {
  let v = Vec[Int].new();
  v.push(r);
  v.push(g);
  v.push(b);
  v.push(a);
  return v;
}

// The first n integers as a flat Vec[Int] (channel ramp).
fn ramp(n: Int) -> Vec[Int] {
  let v = Vec[Int].new();
  var i = 0;
  while (i < n) {
    v.push(i);
    i = i + 1;
  }
  return v;
}

// The first n integers as bytes (pre-encoded raster ramp).
fn ramp_bytes(n: Int) -> Vec[UInt8] {
  let v = Vec[UInt8].new();
  var i = 0;
  while (i < n) {
    v.push(i as UInt8);
    i = i + 1;
  }
  return v;
}

// n zero bytes.
fn zeros(n: Int) -> Vec[UInt8] {
  let v = Vec[UInt8].new();
  var i = 0;
  while (i < n) {
    v.push(0 as UInt8);
    i = i + 1;
  }
  return v;
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

fn ok_img(r: Result[FarbfeldImage, Str]) -> FarbfeldImage {
  match r {
    Ok(v) => { return v; },
    Err(e) => { return FarbfeldImage{ width: 0; height: 0; data_offset: 0; }; },
  }
}

fn bad_img(r: Result[FarbfeldImage, Str]) -> Bool {
  match r {
    Ok(v) => { return false; },
    Err(e) => { return true; },
  }
}

fn img_err_is(r: Result[FarbfeldImage, Str], want: Str) -> Bool {
  match r {
    Ok(v) => { return false; },
    Err(e) => { return streq(e, want); },
  }
}

fn ok_px(r: Result[FarbfeldPixel, Str]) -> FarbfeldPixel {
  match r {
    Ok(v) => { return v; },
    Err(e) => { return FarbfeldPixel{ r: -1; g: -1; b: -1; a: -1; }; },
  }
}

fn px_err_is(data: &Vec[UInt8], x: Int, y: Int, want: Str) -> Bool {
  match farbfeld_pixel_rgba(data, x, y) {
    Ok(p) => { return false; },
    Err(e) => { return streq(e, want); },
  }
}

// farbfeld_pixel_channel collapsed to -1 on any error (safe because every
// valid channel value is >= 0).
fn chan(data: &Vec[UInt8], x: Int, y: Int, c: Int) -> Int {
  match farbfeld_pixel_channel(data, x, y, c) {
    Ok(v) => { return v; },
    Err(e) => { return -1; },
  }
}

fn chan_err_is(data: &Vec[UInt8], x: Int, y: Int, c: Int, want: Str) -> Bool {
  match farbfeld_pixel_channel(data, x, y, c) {
    Ok(v) => { return false; },
    Err(e) => { return streq(e, want); },
  }
}

fn t1() -> TestResult {
  let data = ok_bytes(farbfeld_build(ramp(16), 2, 2));
  if (data.len() != 48) { return assert(false, "2x2 build is 16 + 32 bytes"); }
  let img = ok_img(farbfeld_parse_header(data));
  if (farbfeld_width(&img) != 2) { return assert(false, "parsed width 2"); }
  if (farbfeld_height(&img) != 2) { return assert(false, "parsed height 2"); }
  if (farbfeld_data_offset(&img) != 16) { return assert(false, "data offset is 16"); }
  if (farbfeld_pixel_count(&img) != 4) { return assert(false, "pixel count 4"); }
  if (farbfeld_row_bytes(&img) != 16) { return assert(false, "row bytes 16"); }
  if (farbfeld_raster_len(&img) != 32) { return assert(false, "raster length 32"); }
  if (farbfeld_pixel_offset(&img, 0, 0) != 16) { return assert(false, "pixel (0,0) offset 16"); }
  if (farbfeld_pixel_offset(&img, 1, 1) != 40) { return assert(false, "pixel (1,1) offset 40"); }
  let p00 = ok_px(farbfeld_pixel_rgba(data, 0, 0));
  if (p00.r != 0) { return assert(false, "pixel (0,0) R is 0"); }
  if (p00.g != 1) { return assert(false, "pixel (0,0) G is 1"); }
  if (p00.b != 2) { return assert(false, "pixel (0,0) B is 2"); }
  if (p00.a != 3) { return assert(false, "pixel (0,0) A is 3"); }
  let p11 = ok_px(farbfeld_pixel_rgba(data, 1, 1));
  if (p11.r != 12) { return assert(false, "pixel (1,1) R is 12"); }
  if (p11.g != 13) { return assert(false, "pixel (1,1) G is 13"); }
  if (p11.b != 14) { return assert(false, "pixel (1,1) B is 14"); }
  if (p11.a != 15) { return assert(false, "pixel (1,1) A is 15"); }
  let copy = ok_bytes(farbfeld_raster_copy(data, &img));
  if (copy.len() != 32) { return assert(false, "raster copy is 32 bytes"); }
  var k = 0;
  while (k < 32) {
    let b: Int = (copy[k] as Int) & 0xFF;
    let s: Int = (data[16 + k] as Int) & 0xFF;
    if (b != s) { return assert(false, "raster copy equals the source span"); }
    k = k + 1;
  }
  return assert(true, "2x2 ramp builds, parses and span-copies exactly");
}

fn t2() -> TestResult {
  let data = raw_header(1, 1);
  data.push(0 as UInt8); data.push(1 as UInt8);
  data.push(0 as UInt8); data.push(2 as UInt8);
  data.push(0 as UInt8); data.push(3 as UInt8);
  data.push(0 as UInt8); data.push(4 as UInt8);
  let img = ok_img(farbfeld_parse_header(data));
  if (farbfeld_width(&img) != 1) { return assert(false, "hand-built width 1"); }
  if (farbfeld_height(&img) != 1) { return assert(false, "hand-built height 1"); }
  if (farbfeld_raster_len(&img) != 8) { return assert(false, "hand-built raster length 8"); }
  if (farbfeld_row_bytes(&img) != 8) { return assert(false, "hand-built row bytes 8"); }
  let p = ok_px(farbfeld_pixel_rgba(data, 0, 0));
  if (p.r != 1) { return assert(false, "hand-built R is 1"); }
  if (p.g != 2) { return assert(false, "hand-built G is 2"); }
  if (p.b != 3) { return assert(false, "hand-built B is 3"); }
  if (p.a != 4) { return assert(false, "hand-built A is 4"); }
  if (chan(data, 0, 0, 0) != 1) { return assert(false, "channel 0 is R"); }
  if (chan(data, 0, 0, 1) != 2) { return assert(false, "channel 1 is G"); }
  if (chan(data, 0, 0, 2) != 3) { return assert(false, "channel 2 is B"); }
  if (chan(data, 0, 0, 3) != 4) { return assert(false, "channel 3 is A"); }
  return assert(true, "hand-built 1x1 header and channels decode exactly");
}

fn t3() -> TestResult {
  let zeros1x1 = ok_bytes(farbfeld_build(channels4(0, 0, 0, 0), 1, 1));
  if (zeros1x1.len() != 24) { return assert(false, "1x1 zero build is 24 bytes"); }
  if (!prefix_is(zeros1x1, bytes_of("farbfeld"))) { return assert(false, "magic is the farbfeld literal"); }
  if (!byte_is(zeros1x1, 8, 0)) { return assert(false, "width byte 0"); }
  if (!byte_is(zeros1x1, 9, 0)) { return assert(false, "width byte 1"); }
  if (!byte_is(zeros1x1, 10, 0)) { return assert(false, "width byte 2"); }
  if (!byte_is(zeros1x1, 11, 1)) { return assert(false, "width byte 3"); }
  if (!byte_is(zeros1x1, 12, 0)) { return assert(false, "height byte 0"); }
  if (!byte_is(zeros1x1, 13, 0)) { return assert(false, "height byte 1"); }
  if (!byte_is(zeros1x1, 14, 0)) { return assert(false, "height byte 2"); }
  if (!byte_is(zeros1x1, 15, 1)) { return assert(false, "height byte 3"); }
  var k = 16;
  while (k < 24) {
    if (!byte_is(zeros1x1, k, 0)) { return assert(false, "1x1 zero raster is all zero"); }
    k = k + 1;
  }
  let maxed = ok_bytes(farbfeld_build(channels4(65535, 65535, 65535, 65535), 1, 1));
  if (maxed.len() != 24) { return assert(false, "1x1 max build is 24 bytes"); }
  k = 16;
  while (k < 24) {
    if (!byte_is(maxed, k, 255)) { return assert(false, "1x1 max raster is all 0xFF"); }
    k = k + 1;
  }
  return assert(true, "canonical 1x1 emit is pinned byte-for-byte");
}

fn t4() -> TestResult {
  let good = ok_bytes(farbfeld_build(channels4(1, 2, 3, 4), 1, 1));
  good[0] = 70 as UInt8;
  if (!img_err_is(farbfeld_parse_header(good), "farbfeld: bad magic")) {
    return assert(false, "wrong first magic byte is bad magic");
  }
  let wrong = ok_bytes(farbfeld_build(channels4(1, 2, 3, 4), 1, 1));
  wrong[7] = 116 as UInt8;
  if (!img_err_is(farbfeld_parse_header(wrong), "farbfeld: bad magic")) {
    return assert(false, "wrong last magic byte is bad magic");
  }
  let seven = zeros(7);
  if (!img_err_is(farbfeld_parse_header(seven), "farbfeld: truncated header")) {
    return assert(false, "7-byte buffer is truncated");
  }
  let magic_only = raw_header(1, 1);
  magic_only.pop(); magic_only.pop(); magic_only.pop(); magic_only.pop();
  magic_only.pop(); magic_only.pop(); magic_only.pop(); magic_only.pop();
  if (magic_only.len() != 8) { return assert(false, "magic-only buffer is 8 bytes"); }
  if (!img_err_is(farbfeld_parse_header(magic_only), "farbfeld: truncated header")) {
    return assert(false, "8-byte magic-only buffer is truncated");
  }
  magic_only[3] = 88 as UInt8;
  if (!img_err_is(farbfeld_parse_header(magic_only), "farbfeld: bad magic")) {
    return assert(false, "8-byte wrong magic is bad magic");
  }
  let fifteen = raw_header(1, 1);
  fifteen.pop();
  if (fifteen.len() != 15) { return assert(false, "15-byte buffer is 15 bytes"); }
  if (!img_err_is(farbfeld_parse_header(fifteen), "farbfeld: truncated header")) {
    return assert(false, "15-byte header is truncated");
  }
  return assert(true, "magic and header truncation are validated in order");
}

fn t5() -> TestResult {
  let short = ok_bytes(farbfeld_build(ramp(16), 2, 2));
  short.pop();
  if (!img_err_is(farbfeld_parse_header(short), "farbfeld: truncated pixels")) {
    return assert(false, "47 of 48 bytes is truncated");
  }
  let long = ok_bytes(farbfeld_build(ramp(16), 2, 2));
  long.push(0 as UInt8);
  if (!img_err_is(farbfeld_parse_header(long), "farbfeld: extra pixel data")) {
    return assert(false, "49 bytes is an extra pixel byte");
  }
  let header_only = raw_header(2, 2);
  if (!img_err_is(farbfeld_parse_header(header_only), "farbfeld: truncated pixels")) {
    return assert(false, "header with no raster is truncated");
  }
  return assert(true, "the raster must be exactly 8*width*height bytes");
}

fn t6() -> TestResult {
  if (!img_err_is(farbfeld_parse_header(raw_header(0, 1)), "farbfeld: zero width")) {
    return assert(false, "header width 0 is rejected");
  }
  if (!img_err_is(farbfeld_parse_header(raw_header(1, 0)), "farbfeld: zero height")) {
    return assert(false, "header height 0 is rejected");
  }
  if (!bytes_err_is(farbfeld_build(channels4(0, 0, 0, 0), 0, 1), "farbfeld: zero width")) {
    return assert(false, "build width 0 is rejected");
  }
  if (!bytes_err_is(farbfeld_build(channels4(0, 0, 0, 0), 1, 0), "farbfeld: zero height")) {
    return assert(false, "build height 0 is rejected");
  }
  if (!bytes_err_is(farbfeld_build(channels4(0, 0, 0, 0), -1, 1), "farbfeld: invalid width")) {
    return assert(false, "build width -1 is invalid");
  }
  if (!bytes_err_is(farbfeld_build(channels4(0, 0, 0, 0), 1, -1), "farbfeld: invalid height")) {
    return assert(false, "build height -1 is invalid");
  }
  let raw1 = zeros(8);
  if (!bytes_err_is(farbfeld_build_raw(raw1, 0, 1), "farbfeld: zero width")) {
    return assert(false, "build_raw width 0 is rejected");
  }
  return assert(true, "zero and negative dimensions are rejected everywhere");
}

fn t7() -> TestResult {
  if (farbfeld_max_dim() != 1000000) { return assert(false, "documented cap is 1000000"); }
  if (!img_err_is(farbfeld_parse_header(raw_header(1000001, 1)), "farbfeld: dimension overflow")) {
    return assert(false, "header width above the cap overflows");
  }
  if (!img_err_is(farbfeld_parse_header(raw_header(1, 1000001)), "farbfeld: dimension overflow")) {
    return assert(false, "header height above the cap overflows");
  }
  if (!img_err_is(farbfeld_parse_header(raw_header(4294967295, 1)), "farbfeld: dimension overflow")) {
    return assert(false, "u32 max width overflows");
  }
  if (!img_err_is(farbfeld_parse_header(raw_header(1, 4294967295)), "farbfeld: dimension overflow")) {
    return assert(false, "u32 max height overflows");
  }
  if (!bytes_err_is(farbfeld_build(channels4(0, 0, 0, 0), 1000001, 1), "farbfeld: dimension overflow")) {
    return assert(false, "build width above the cap overflows");
  }
  let raw8 = zeros(8);
  if (!bytes_err_is(farbfeld_build_raw(raw8, 1, 1000001), "farbfeld: dimension overflow")) {
    return assert(false, "build_raw height above the cap overflows");
  }
  return assert(true, "dimensions are capped at 1000000 on both axes");
}

fn t8() -> TestResult {
  let data = ok_bytes(farbfeld_build(ramp(16), 2, 2));
  let img = ok_img(farbfeld_parse_header(data));
  if (!px_err_is(data, -1, 0, "farbfeld: pixel out of range")) { return assert(false, "x=-1 is out of range"); }
  if (!px_err_is(data, 0, -1, "farbfeld: pixel out of range")) { return assert(false, "y=-1 is out of range"); }
  if (!px_err_is(data, 2, 0, "farbfeld: pixel out of range")) { return assert(false, "x=width is out of range"); }
  if (!px_err_is(data, 0, 2, "farbfeld: pixel out of range")) { return assert(false, "y=height is out of range"); }
  if (!px_err_is(data, 5, 5, "farbfeld: pixel out of range")) { return assert(false, "far coordinate is out of range"); }
  if (farbfeld_pixel_offset(&img, -1, 0) != -1) { return assert(false, "offset x=-1 is -1"); }
  if (farbfeld_pixel_offset(&img, 0, -1) != -1) { return assert(false, "offset y=-1 is -1"); }
  if (farbfeld_pixel_offset(&img, 2, 0) != -1) { return assert(false, "offset x=width is -1"); }
  if (farbfeld_pixel_offset(&img, 0, 2) != -1) { return assert(false, "offset y=height is -1"); }
  if (farbfeld_pixel_offset(&img, 1, 0) != 24) { return assert(false, "offset (1,0) is 24"); }
  if (farbfeld_pixel_offset(&img, 0, 1) != 32) { return assert(false, "offset (0,1) is 32"); }
  let bad = ok_bytes(farbfeld_build(channels4(1, 2, 3, 4), 1, 1));
  bad[1] = 88 as UInt8;
  if (!px_err_is(bad, 0, 0, "farbfeld: bad magic")) {
    return assert(false, "header errors propagate through pixel access");
  }
  return assert(true, "out-of-range checks and the -1 offset sentinel are exact");
}

fn t9() -> TestResult {
  let data = ok_bytes(farbfeld_build(ramp(16), 2, 2));
  if (chan(data, 1, 0, 0) != 4) { return assert(false, "channel R of (1,0)"); }
  if (chan(data, 1, 0, 1) != 5) { return assert(false, "channel G of (1,0)"); }
  if (chan(data, 1, 0, 2) != 6) { return assert(false, "channel B of (1,0)"); }
  if (chan(data, 1, 0, 3) != 7) { return assert(false, "channel A of (1,0)"); }
  if (chan(data, 0, 1, 0) != 8) { return assert(false, "channel R of (0,1)"); }
  if (chan(data, 0, 1, 3) != 11) { return assert(false, "channel A of (0,1)"); }
  if (!chan_err_is(data, 1, 0, -1, "farbfeld: channel index out of range")) {
    return assert(false, "channel -1 is out of range");
  }
  if (!chan_err_is(data, 1, 0, 4, "farbfeld: channel index out of range")) {
    return assert(false, "channel 4 is out of range");
  }
  if (!chan_err_is(data, 6, 0, 0, "farbfeld: pixel out of range")) {
    return assert(false, "pixel errors win over channel index errors");
  }
  return assert(true, "channel selection and index validation are exact");
}

fn t10() -> TestResult {
  let short = ramp(15);
  if (!bytes_err_is(farbfeld_build(short, 2, 2), "farbfeld: channel buffer size mismatch")) {
    return assert(false, "15 channels for 2x2");
  }
  let long = ramp(17);
  if (!bytes_err_is(farbfeld_build(long, 2, 2), "farbfeld: channel buffer size mismatch")) {
    return assert(false, "17 channels for 2x2");
  }
  let exact = ramp(16);
  if (bad_bytes(farbfeld_build(exact, 2, 2))) {
    return assert(false, "16 channels for 2x2 succeeds");
  }
  let raw_short = zeros(31);
  if (!bytes_err_is(farbfeld_build_raw(raw_short, 2, 2), "farbfeld: raster buffer size mismatch")) {
    return assert(false, "31 raster bytes for 2x2");
  }
  let raw_long = zeros(33);
  if (!bytes_err_is(farbfeld_build_raw(raw_long, 2, 2), "farbfeld: raster buffer size mismatch")) {
    return assert(false, "33 raster bytes for 2x2");
  }
  return assert(true, "both builders require exactly width*height*(4 or 8) inputs");
}

fn t11() -> TestResult {
  if (!bytes_err_is(farbfeld_build(channels4(-1, 0, 0, 0), 1, 1), "farbfeld: channel out of range")) {
    return assert(false, "channel -1 is out of range");
  }
  if (!bytes_err_is(farbfeld_build(channels4(0, 0, 0, 65536), 1, 1), "farbfeld: channel out of range")) {
    return assert(false, "channel 65536 is out of range");
  }
  let data = ok_bytes(farbfeld_build(channels4(65535, 0, 65535, 0), 1, 1));
  if (data.len() != 24) { return assert(false, "max channels build is 24 bytes"); }
  if (chan(data, 0, 0, 0) != 65535) { return assert(false, "channel value 65535 is accepted"); }
  if (chan(data, 0, 0, 2) != 65535) { return assert(false, "second 65535 channel"); }
  if (chan(data, 0, 0, 1) != 0) { return assert(false, "zero channel stays zero"); }
  return assert(true, "builder channels must be 0..65535 inclusive");
}

fn t12() -> TestResult {
  let data = ok_bytes(farbfeld_build(channels4(65535, 65535, 65535, 65535), 1, 1));
  let p = ok_px(farbfeld_pixel_rgba(data, 0, 0));
  if (p.r != 65535) { return assert(false, "max R"); }
  if (p.g != 65535) { return assert(false, "max G"); }
  if (p.b != 65535) { return assert(false, "max B"); }
  if (p.a != 65535) { return assert(false, "max A"); }
  let img = ok_img(farbfeld_parse_header(data));
  let copy = ok_bytes(farbfeld_raster_copy(data, &img));
  if (copy.len() != 8) { return assert(false, "max raster copy is 8 bytes"); }
  var k = 0;
  while (k < 8) {
    if (!byte_is(copy, k, 255)) { return assert(false, "max raster bytes are 0xFF"); }
    k = k + 1;
  }
  let again = ok_bytes(farbfeld_build(channels4(p.r, p.g, p.b, p.a), farbfeld_width(&img), farbfeld_height(&img)));
  if (!vec_eq(again, data)) { return assert(false, "rebuild is byte-identical"); }
  return assert(true, "1x1 with maximum channels round-trips byte-exactly");
}

fn t13() -> TestResult {
  let px = Vec[Int].new();
  var i = 0;
  while (i < 28) {
    px.push(i * 100);
    i = i + 1;
  }
  let data = ok_bytes(farbfeld_build(px, 7, 1));
  if (data.len() != 72) { return assert(false, "1x7 build is 16 + 56 bytes"); }
  let img = ok_img(farbfeld_parse_header(data));
  if (farbfeld_width(&img) != 7) { return assert(false, "1x7 width 7"); }
  if (farbfeld_height(&img) != 1) { return assert(false, "1x7 height 1"); }
  if (farbfeld_row_bytes(&img) != 56) { return assert(false, "1x7 row bytes 56"); }
  if (farbfeld_raster_len(&img) != 56) { return assert(false, "1x7 raster length 56"); }
  if (farbfeld_pixel_count(&img) != 7) { return assert(false, "1x7 pixel count 7"); }
  var x = 0;
  while (x < 7) {
    if (chan(data, x, 0, 0) != x * 400) { return assert(false, "1x7 R ramp"); }
    if (chan(data, x, 0, 1) != x * 400 + 100) { return assert(false, "1x7 G ramp"); }
    if (chan(data, x, 0, 2) != x * 400 + 200) { return assert(false, "1x7 B ramp"); }
    if (chan(data, x, 0, 3) != x * 400 + 300) { return assert(false, "1x7 A ramp"); }
    x = x + 1;
  }
  let row = ok_bytes(farbfeld_row_copy(data, &img, 0));
  if (row.len() != 56) { return assert(false, "1x7 row copy is 56 bytes"); }
  let all = ok_bytes(farbfeld_raster_copy(data, &img));
  if (!vec_eq(row, all)) { return assert(false, "the single row spans the whole raster"); }
  if (!bytes_err_is(farbfeld_row_copy(data, &img, 1), "farbfeld: row out of range")) {
    return assert(false, "row 1 does not exist in a 1-row image");
  }
  return assert(true, "wide 1x7 raster round-trips channel by channel");
}

fn t14() -> TestResult {
  let raw = ramp_bytes(32);
  let data = ok_bytes(farbfeld_build_raw(raw, 2, 2));
  if (data.len() != 48) { return assert(false, "raw 2x2 build is 48 bytes"); }
  if (!byte_is(data, 8, 0)) { return assert(false, "raw header width byte 0"); }
  if (!byte_is(data, 11, 2)) { return assert(false, "raw header width byte 3"); }
  if (!byte_is(data, 15, 2)) { return assert(false, "raw header height byte 3"); }
  if (!byte_is(data, 16, 0)) { return assert(false, "raw raster first byte"); }
  if (!byte_is(data, 47, 31)) { return assert(false, "raw raster last byte"); }
  let img = ok_img(farbfeld_parse_header(data));
  let copy = ok_bytes(farbfeld_raster_copy(data, &img));
  if (!vec_eq(copy, raw)) { return assert(false, "raw raster copy matches the source bytes"); }
  let p = ok_px(farbfeld_pixel_rgba(data, 1, 0));
  if (p.r != 2057) { return assert(false, "raw big-endian R"); }
  if (p.g != 2571) { return assert(false, "raw big-endian G"); }
  if (p.a != 3599) { return assert(false, "raw big-endian A"); }
  return assert(true, "build_raw copies pre-encoded big-endian bytes verbatim");
}

fn t15() -> TestResult {
  let raw = ramp_bytes(48);
  let data = ok_bytes(farbfeld_build_raw(raw, 2, 3));
  if (data.len() != 64) { return assert(false, "2x3 raw build is 16 + 48 bytes"); }
  if (!byte_is(data, 8, 0)) { return assert(false, "width byte 0"); }
  if (!byte_is(data, 9, 0)) { return assert(false, "width byte 1"); }
  if (!byte_is(data, 10, 0)) { return assert(false, "width byte 2"); }
  if (!byte_is(data, 11, 2)) { return assert(false, "width byte 3"); }
  if (!byte_is(data, 12, 0)) { return assert(false, "height byte 0"); }
  if (!byte_is(data, 13, 0)) { return assert(false, "height byte 1"); }
  if (!byte_is(data, 14, 0)) { return assert(false, "height byte 2"); }
  if (!byte_is(data, 15, 3)) { return assert(false, "height byte 3"); }
  let img = ok_img(farbfeld_parse_header(data));
  if (farbfeld_width(&img) != 2) { return assert(false, "2x3 width 2"); }
  if (farbfeld_height(&img) != 3) { return assert(false, "2x3 height 3"); }
  if (farbfeld_row_bytes(&img) != 16) { return assert(false, "2x3 row bytes 16"); }
  if (farbfeld_raster_len(&img) != 48) { return assert(false, "2x3 raster length 48"); }
  if (farbfeld_pixel_offset(&img, 1, 2) != 56) { return assert(false, "2x3 last pixel offset 56"); }
  let row2 = ok_bytes(farbfeld_row_copy(data, &img, 2));
  if (row2.len() != 16) { return assert(false, "row 2 is 16 bytes"); }
  var i = 0;
  while (i < 16) {
    let b: Int = (row2[i] as Int) & 0xFF;
    let s: Int = (data[48 + i] as Int) & 0xFF;
    if (b != s) { return assert(false, "row 2 equals the third raster row"); }
    i = i + 1;
  }
  if (!img_err_is(farbfeld_parse_header(raw), "farbfeld: bad magic")) {
    return assert(false, "a bare raster is not an image");
  }
  return assert(true, "the header is big-endian and rows map onto exact offsets");
}

fn t16() -> TestResult {
  let data = ok_bytes(farbfeld_build(ramp(16), 2, 2));
  let img = ok_img(farbfeld_parse_header(data));
  let row0 = ok_bytes(farbfeld_row_copy(data, &img, 0));
  if (row0.len() != 16) { return assert(false, "row 0 is 16 bytes"); }
  if (!byte_is(row0, 0, 0)) { return assert(false, "row 0 first byte"); }
  if (!byte_is(row0, 15, 7)) { return assert(false, "row 0 last byte"); }
  if (!bytes_err_is(farbfeld_row_copy(data, &img, 2), "farbfeld: row out of range")) {
    return assert(false, "row 2 is out of range for height 2");
  }
  if (!bytes_err_is(farbfeld_row_copy(data, &img, -1), "farbfeld: row out of range")) {
    return assert(false, "row -1 is out of range");
  }
  let forged = FarbfeldImage{ width: 1; height: 1; data_offset: 100; };
  if (!bytes_err_is(farbfeld_raster_copy(data, &forged), "farbfeld: raster out of range")) {
    return assert(false, "span past the buffer is rejected");
  }
  let forged2 = FarbfeldImage{ width: 1; height: 1; data_offset: -1; };
  if (!bytes_err_is(farbfeld_raster_copy(data, &forged2), "farbfeld: raster out of range")) {
    return assert(false, "negative offset is rejected");
  }
  let empty = Vec[UInt8].new();
  if (!bytes_err_is(farbfeld_raster_copy(empty, &img), "farbfeld: raster out of range")) {
    return assert(false, "empty buffer cannot hold the raster");
  }
  return assert(true, "row copies and span guards reject out-of-bounds spans");
}

fn t17() -> TestResult {
  let data = raw_header(1000000, 1);
  var i = 0;
  while (i < 8000000) {
    data.push(0 as UInt8);
    i = i + 1;
  }
  let img = ok_img(farbfeld_parse_header(data));
  if (farbfeld_width(&img) != 1000000) { return assert(false, "cap width is accepted"); }
  if (farbfeld_raster_len(&img) != 8000000) { return assert(false, "cap raster length is 8000000"); }
  if (farbfeld_pixel_offset(&img, 999999, 0) != 8000008) { return assert(false, "last cap pixel offset"); }
  if (farbfeld_pixel_offset(&img, 1000000, 0) != -1) { return assert(false, "one past the cap is -1"); }
  return assert(true, "the 1000000-pixel cap is inclusive and exact-size checked");
}

fn main() -> Int {
  io.println("=== xiom.farbfeld conformance tests ===");
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
  if failed == 0 {
    io.println("xiom.farbfeld: all tests passed");
  } else {
    io.println("xiom.farbfeld: tests failed");
  }
  return failed;
}
