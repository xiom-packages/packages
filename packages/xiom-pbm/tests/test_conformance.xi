// XIOM -- xiom.pbm conformance tests (20 checks)
// Port task: prove the pure-XIOM xiom.pbm module against Netpbm P1/P4.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module pbm_tests
use xiom.io; use xiom.test; use xiom.pbm;
use xiom.string; use xiom.string.compare;

// All Str equality goes through str_compare: `==` on Str lowered from a
// Vec[Str] element is a pointer comparison in v0.61.3, so error-message
// checks are routed through streq.

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// ASCII bytes of a literal, used to hand-build inputs.
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

// '0'/'1' characters of a pattern string as 0/1 bytes.
fn bits_from_str(s: Str) -> Vec[UInt8] {
  let v = Vec[UInt8].new();
  let n = s.len();
  var i = 0;
  while (i < n) {
    let b: UInt8 = string.byte_at(s, i);
    let d: Int = (b as Int) & 0xFF;
    if (d == 49) { v.push(1 as UInt8); } else { v.push(0 as UInt8); }
    i = i + 1;
  }
  return v;
}

// True when every pbm_bit(x, y) matches the row-major pattern string.
fn raster_is(data: &Vec[UInt8], w: Int, h: Int, pattern: Str) -> Bool {
  let want = bits_from_str(pattern);
  if (want.len() != w * h) { return false; }
  var y = 0;
  while (y < h) {
    var x = 0;
    while (x < w) {
      let got: Int = pbm_bit(data, x, y);
      let exp: Int = (want[y * w + x] as Int) & 0xFF;
      if (got != exp) { return false; }
      x = x + 1;
    }
    y = y + 1;
  }
  return true;
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

fn ok_img(r: Result[PbmImage, Str]) -> PbmImage {
  match r {
    Ok(v) => { return v; },
    Err(e) => { return PbmImage{ format: 0; width: 0; height: 0; data_offset: 0; }; },
  }
}

fn bad_img(r: Result[PbmImage, Str]) -> Bool {
  match r {
    Ok(v) => { return false; },
    Err(e) => { return true; },
  }
}

fn img_err_is(r: Result[PbmImage, Str], want: Str) -> Bool {
  match r {
    Ok(v) => { return false; },
    Err(e) => { return streq(e, want); },
  }
}

fn t1() -> TestResult {
  let bits = bits_from_str("1001");
  let data = ok_bytes(pbm_build_p4(bits, 2, 2, ""));
  if (data.len() != 9) { return assert(false, "built 2x2 P4 is 9 bytes"); }
  if (!bytes_prefix_is(data, "P4\n2 2\n")) { return assert(false, "P4 canonical header"); }
  if (!byte_is(data, 7, 128)) { return assert(false, "row 0 packs as 0x80"); }
  if (!byte_is(data, 8, 64)) { return assert(false, "row 1 packs as 0x40"); }
  let img = ok_img(pbm_parse_header(data));
  if (pbm_format(&img) != 4) { return assert(false, "P4 format is 4"); }
  if (pbm_width(&img) != 2) { return assert(false, "P4 width 2"); }
  if (pbm_height(&img) != 2) { return assert(false, "P4 height 2"); }
  if (img.data_offset != 7) { return assert(false, "P4 data offset 7"); }
  if (pbm_row_bytes(2) != 1) { return assert(false, "2-pixel P4 row is 1 byte"); }
  if (!raster_is(data, 2, 2, "1001")) { return assert(false, "P4 bit read-back"); }
  return assert(true, "built 2x2 P4 parses and reads back all bits");
}

fn t2() -> TestResult {
  let bits = bits_from_str("1001");
  let data = ok_bytes(pbm_build_p1(bits, 2, 2, 2, ""));
  if (data.len() != 15) { return assert(false, "built 2x2 P1 is 15 bytes"); }
  if (!vec_is_str(data, "P1\n2 2\n1 0\n0 1\n")) { return assert(false, "P1 canonical literal"); }
  let img = ok_img(pbm_parse_header(data));
  if (pbm_format(&img) != 1) { return assert(false, "P1 format is 1"); }
  if (pbm_width(&img) != 2) { return assert(false, "P1 width 2"); }
  if (pbm_height(&img) != 2) { return assert(false, "P1 height 2"); }
  if (img.data_offset != 7) { return assert(false, "P1 data offset 7"); }
  if (!raster_is(data, 2, 2, "1001")) { return assert(false, "P1 bit read-back"); }
  return assert(true, "built 2x2 P1 pins the canonical text and reads back");
}

fn t3() -> TestResult {
  let d1 = bytes_of("P1\n# first\n2 2 # inline\n# more\n1 0\n0 1\n");
  let i1 = ok_img(pbm_parse_header(d1));
  if (pbm_format(&i1) != 1) { return assert(false, "commented P1 format"); }
  if (pbm_width(&i1) != 2) { return assert(false, "commented P1 width 2"); }
  if (pbm_height(&i1) != 2) { return assert(false, "commented P1 height 2"); }
  if (i1.data_offset != 31) { return assert(false, "commented P1 offset 31"); }
  if (!raster_is(d1, 2, 2, "1001")) { return assert(false, "commented P1 bits"); }
  let d2 = bytes_of("P4\n# c\n2 2\n");
  d2.push(128 as UInt8);
  d2.push(64 as UInt8);
  let i2 = ok_img(pbm_parse_header(d2));
  if (pbm_format(&i2) != 4) { return assert(false, "commented P4 format"); }
  if (i2.data_offset != 11) { return assert(false, "commented P4 offset 11"); }
  if (!raster_is(d2, 2, 2, "1001")) { return assert(false, "commented P4 bits"); }
  return assert(true, "comments are skipped between header tokens");
}

fn t4() -> TestResult {
  let d = Vec[UInt8].new();
  d.push(80 as UInt8); d.push(52 as UInt8);
  d.push(13 as UInt8); d.push(10 as UInt8); d.push(9 as UInt8); d.push(32 as UInt8);
  d.push(50 as UInt8);
  d.push(11 as UInt8); d.push(12 as UInt8);
  d.push(50 as UInt8);
  d.push(10 as UInt8);
  d.push(128 as UInt8); d.push(64 as UInt8);
  let img = ok_img(pbm_parse_header(d));
  if (pbm_width(&img) != 2) { return assert(false, "mixed-space width 2"); }
  if (pbm_height(&img) != 2) { return assert(false, "mixed-space height 2"); }
  if (img.data_offset != 11) { return assert(false, "mixed-space offset 11"); }
  if (!raster_is(d, 2, 2, "1001")) { return assert(false, "mixed-space P4 bits"); }
  let p = Vec[UInt8].new();
  p.push(80 as UInt8); p.push(49 as UInt8);
  p.push(13 as UInt8); p.push(10 as UInt8);
  p.push(49 as UInt8);
  p.push(11 as UInt8); p.push(12 as UInt8);
  p.push(49 as UInt8);
  p.push(10 as UInt8);
  p.push(49 as UInt8);
  let img2 = ok_img(pbm_parse_header(p));
  if (img2.data_offset != 9) { return assert(false, "P1 mixed-space offset 9"); }
  if (!raster_is(p, 1, 1, "1")) { return assert(false, "P1 mixed-space bit"); }
  return assert(true, "CR LF TAB SPACE VT FF all separate tokens");
}

fn t5() -> TestResult {
  if (!img_err_is(pbm_parse_header(bytes_of("P2\n1 1\n1")), "pbm: bad magic")) {
    return assert(false, "P2 is bad magic");
  }
  if (!img_err_is(pbm_parse_header(bytes_of("P5\n1 1\n")), "pbm: bad magic")) {
    return assert(false, "P5 is bad magic");
  }
  if (!img_err_is(pbm_parse_header(bytes_of("X1\n1 1\n1")), "pbm: bad magic")) {
    return assert(false, "X1 is bad magic");
  }
  let hi = Vec[UInt8].new();
  hi.push(255 as UInt8);
  hi.push(49 as UInt8);
  if (!img_err_is(pbm_parse_header(hi), "pbm: bad magic")) {
    return assert(false, "0xFF magic is bad magic");
  }
  if (!img_err_is(pbm_parse_header(bytes_of("P1P4")), "pbm: missing whitespace after magic")) {
    return assert(false, "no whitespace after magic");
  }
  if (!img_err_is(pbm_parse_header(bytes_of("P")), "pbm: truncated header")) {
    return assert(false, "1-byte buffer is a truncated header");
  }
  if (!img_err_is(pbm_parse_header(bytes_of("P1")), "pbm: truncated header")) {
    return assert(false, "magic-only buffer is a truncated header");
  }
  return assert(true, "only P1/P4 magic is accepted after a whitespace");
}

fn t6() -> TestResult {
  if (!img_err_is(pbm_parse_header(bytes_of("P1\n")), "pbm: missing width")) {
    return assert(false, "header end after magic misses width");
  }
  if (!img_err_is(pbm_parse_header(bytes_of("P1\n# only\n")), "pbm: missing width")) {
    return assert(false, "comment-only first separator misses width");
  }
  if (!img_err_is(pbm_parse_header(bytes_of("P1\n2\n")), "pbm: missing height")) {
    return assert(false, "width without height");
  }
  if (!img_err_is(pbm_parse_header(bytes_of("P1\n2 # c\n")), "pbm: missing height")) {
    return assert(false, "comment after width still misses height");
  }
  if (!img_err_is(pbm_parse_header(bytes_of("P4\n7")), "pbm: missing height")) {
    return assert(false, "digit token then EOF misses height");
  }
  return assert(true, "missing width and height are reported separately");
}

fn t7() -> TestResult {
  if (!img_err_is(pbm_parse_header(bytes_of("P1\n0 1\n1")), "pbm: invalid width")) {
    return assert(false, "width 0 is invalid");
  }
  if (!img_err_is(pbm_parse_header(bytes_of("P1\n1 0\n1")), "pbm: invalid height")) {
    return assert(false, "height 0 is invalid");
  }
  if (!img_err_is(pbm_parse_header(bytes_of("P1\n1000001 1\n")), "pbm: invalid width")) {
    return assert(false, "width 1000001 exceeds the cap");
  }
  if (!img_err_is(pbm_parse_header(bytes_of("P1\n1 1000001\n")), "pbm: invalid height")) {
    return assert(false, "height 1000001 exceeds the cap");
  }
  if (!img_err_is(pbm_parse_header(bytes_of("P1\n1234567890 1\n")), "pbm: invalid width")) {
    return assert(false, "10-digit width token is invalid");
  }
  if (!img_err_is(pbm_parse_header(bytes_of("P4\n1 1234567890\n")), "pbm: invalid height")) {
    return assert(false, "10-digit height token is invalid");
  }
  return assert(true, "non-positive and oversized dimensions are rejected");
}

fn t8() -> TestResult {
  if (!img_err_is(pbm_parse_header(bytes_of("P1\n1 1\n2")), "pbm: non-binary digit")) {
    return assert(false, "digit '2' is not a raster bit");
  }
  if (!img_err_is(pbm_parse_header(bytes_of("P1\n1 1\nx")), "pbm: non-binary digit")) {
    return assert(false, "letter in the P1 raster");
  }
  if (!img_err_is(pbm_parse_header(bytes_of("P1\n1 1\n1 0")), "pbm: extra tokens")) {
    return assert(false, "one extra P1 digit");
  }
  if (!img_err_is(pbm_parse_header(bytes_of("P1\n2 2\n10 01 11 00 1")), "pbm: extra tokens")) {
    return assert(false, "extra P1 digits after a full raster");
  }
  let d = bytes_of("P4\n1 1\n");
  d.push(128 as UInt8);
  d.push(88 as UInt8);
  if (!img_err_is(pbm_parse_header(d), "pbm: extra tokens")) {
    return assert(false, "byte after the P4 raster is extra");
  }
  let okd = bytes_of("P4\n1 1\n");
  okd.push(128 as UInt8);
  okd.push(10 as UInt8);
  let img = ok_img(pbm_parse_header(okd));
  if (img.data_offset != 7) { return assert(false, "trailing LF keeps the raster"); }
  if (!raster_is(okd, 1, 1, "1")) { return assert(false, "trailing LF keeps the bit"); }
  return assert(true, "non-binary digits and extra tokens are rejected");
}

fn t9() -> TestResult {
  let short = bytes_of("P4\n2 2\n");
  short.push(128 as UInt8);
  if (!img_err_is(pbm_parse_header(short), "pbm: truncated raster")) {
    return assert(false, "1 of 2 P4 rows is truncated");
  }
  if (!img_err_is(pbm_parse_header(bytes_of("P4\n2 2")), "pbm: truncated raster")) {
    return assert(false, "EOF right after P4 height");
  }
  if (!img_err_is(pbm_parse_header(bytes_of("P4\n2 2x")), "pbm: missing whitespace after height")) {
    return assert(false, "P4 height must be followed by whitespace");
  }
  if (!img_err_is(pbm_parse_header(bytes_of("P1\n2 1\n1")), "pbm: truncated raster")) {
    return assert(false, "1 of 2 P1 digits is truncated");
  }
  if (!img_err_is(pbm_parse_header(bytes_of("P1\n1 1\n")), "pbm: truncated raster")) {
    return assert(false, "header-only P1 is truncated");
  }
  if (!img_err_is(pbm_parse_header(bytes_of("P1\n1 1")), "pbm: truncated raster")) {
    return assert(false, "EOF right after P1 height");
  }
  return assert(true, "missing raster data is rejected for P1 and P4");
}

fn t10() -> TestResult {
  let d1 = ok_bytes(pbm_build_p4(bits_from_str("101"), 3, 1, ""));
  if (d1.len() != 8) { return assert(false, "3x1 P4 is 7 + 1 byte"); }
  if (!byte_is(d1, 7, 160)) { return assert(false, "3 bits pad to 0xA0"); }
  let d2 = ok_bytes(pbm_build_p4(bits_from_str("01"), 2, 1, ""));
  if (!byte_is(d2, 7, 64)) { return assert(false, "2 bits pad to 0x40"); }
  let d8 = ok_bytes(pbm_build_p4(bits_from_str("11111111"), 8, 1, ""));
  if (d8.len() != 8) { return assert(false, "8 bits are exactly 1 byte"); }
  if (!byte_is(d8, 7, 255)) { return assert(false, "8 one-bits pack to 0xFF"); }
  let d9 = ok_bytes(pbm_build_p4(bits_from_str("111111111"), 9, 1, ""));
  if (d9.len() != 9) { return assert(false, "9 bits are 2 bytes"); }
  if (!byte_is(d9, 7, 255)) { return assert(false, "9th bit starts byte 2"); }
  if (!byte_is(d9, 8, 128)) { return assert(false, "9 bits pad to 0x80"); }
  let d0 = ok_bytes(pbm_build_p4(bits_from_str("0"), 1, 1, ""));
  if (!byte_is(d0, 7, 0)) { return assert(false, "single white bit packs to 0x00"); }
  return assert(true, "P4 rows are padded to whole bytes with zero low bits");
}

fn t11() -> TestResult {
  let d1 = bytes_of("P1 2 2 1001");
  let i1 = ok_img(pbm_parse_header(d1));
  if (i1.data_offset != 7) { return assert(false, "adjacent digits start at 7"); }
  if (!raster_is(d1, 2, 2, "1001")) { return assert(false, "adjacent digits parse"); }
  let d2 = Vec[UInt8].new();
  d2.push(80 as UInt8); d2.push(49 as UInt8); d2.push(10 as UInt8);
  d2.push(50 as UInt8); d2.push(32 as UInt8); d2.push(50 as UInt8); d2.push(10 as UInt8);
  d2.push(49 as UInt8); d2.push(9 as UInt8); d2.push(48 as UInt8);
  d2.push(13 as UInt8); d2.push(10 as UInt8);
  d2.push(48 as UInt8); d2.push(32 as UInt8); d2.push(32 as UInt8); d2.push(49 as UInt8);
  let i2 = ok_img(pbm_parse_header(d2));
  if (i2.data_offset != 7) { return assert(false, "mixed raster keeps offset 7"); }
  if (!raster_is(d2, 2, 2, "1001")) { return assert(false, "TAB CR LF and doubled spaces parse"); }
  let d3 = bytes_of("P1\n2 2\n1001");
  if (!raster_is(d3, 2, 2, "1001")) { return assert(false, "unseparated row digits parse"); }
  return assert(true, "P1 accepts arbitrary whitespace between digits");
}

fn t12() -> TestResult {
  let bits = Vec[UInt8].new();
  var y = 0;
  while (y < 3) {
    var x = 0;
    while (x < 5) {
      bits.push(((x + y) % 2) as UInt8);
      x = x + 1;
    }
    y = y + 1;
  }
  let data = ok_bytes(pbm_build_p4(bits, 5, 3, ""));
  if (data.len() != 10) { return assert(false, "5x3 P4 is 7 + 3 bytes"); }
  if (!byte_is(data, 7, 80)) { return assert(false, "row 0 packs to 0x50"); }
  if (!byte_is(data, 8, 168)) { return assert(false, "row 1 packs to 0xA8"); }
  if (!byte_is(data, 9, 80)) { return assert(false, "row 2 packs to 0x50"); }
  if (!raster_is(data, 5, 3, "010101010101010")) { return assert(false, "5x3 all-bit round trip"); }
  var yy = 0;
  while (yy < 3) {
    var xx = 0;
    while (xx < 5) {
      if (pbm_bit(data, xx, yy) != ((xx + yy) % 2)) {
        return assert(false, "5x3 coordinate matches the pattern");
      }
      xx = xx + 1;
    }
    yy = yy + 1;
  }
  if (pbm_bit(data, 5, 0) != -1) { return assert(false, "x=5 is out of range"); }
  return assert(true, "each P4 row is padded independently");
}

fn t13() -> TestResult {
  let p1 = bytes_of("P1\n3 2\n1 0 1\n0 1 1\n");
  let img1 = ok_img(pbm_parse_header(p1));
  if (pbm_format(&img1) != 1) { return assert(false, "round trip starts as P1"); }
  let bits = Vec[UInt8].new();
  var y = 0;
  while (y < 2) {
    var x = 0;
    while (x < 3) {
      bits.push(pbm_bit(p1, x, y) as UInt8);
      x = x + 1;
    }
    y = y + 1;
  }
  let p4 = ok_bytes(pbm_build_p4(bits, 3, 2, ""));
  let img4 = ok_img(pbm_parse_header(p4));
  if (pbm_format(&img4) != 4) { return assert(false, "P1 to P4 flips the format"); }
  if (!raster_is(p4, 3, 2, "101011")) { return assert(false, "P4 keeps every bit"); }
  let back = ok_bytes(pbm_build_p1(bits, 3, 2, 3, ""));
  if (!vec_is_str(back, "P1\n3 2\n1 0 1\n0 1 1\n")) {
    return assert(false, "P1 to P4 to P1 is byte-exact for canonical input");
  }
  if (!raster_is(back, 3, 2, "101011")) { return assert(false, "round-tripped P1 keeps every bit"); }
  return assert(true, "P1 to P4 to P1 is semantically and textually exact");
}

fn t14() -> TestResult {
  let p1 = bytes_of("P1\n3 2\n1 0 1\n0 1 1\n");
  let bits = Vec[UInt8].new();
  var y = 0;
  while (y < 2) {
    var x = 0;
    while (x < 3) {
      bits.push(pbm_bit(p1, x, y) as UInt8);
      x = x + 1;
    }
    y = y + 1;
  }
  let p4 = ok_bytes(pbm_build_p4(bits, 3, 2, ""));
  if (p4.len() != 9) { return assert(false, "canonical 3x2 P4 is 9 bytes"); }
  if (!bytes_prefix_is(p4, "P4\n3 2\n")) { return assert(false, "canonical P4 header"); }
  if (!byte_is(p4, 7, 160)) { return assert(false, "3-bit row 0 pads to 0xA0"); }
  if (!byte_is(p4, 8, 96)) { return assert(false, "3-bit row 1 pads to 0x60"); }
  let p4b = ok_bytes(pbm_build_p4(bits, 3, 2, ""));
  if (!vec_eq(p4, p4b)) { return assert(false, "two P4 builds are identical"); }
  let again = ok_bytes(pbm_build_p1(bits, 3, 2, 3, ""));
  if (!vec_eq(again, p1)) { return assert(false, "P1 rebuild matches the canonical input byte for byte"); }
  return assert(true, "canonical P1 and P4 builds are byte-exact and idempotent");
}

fn t15() -> TestResult {
  let bits = bits_from_str("11110000");
  let c0 = ok_bytes(pbm_build_p1(bits, 4, 2, 0, ""));
  if (!vec_is_str(c0, "P1\n4 2\n1\n1\n1\n1\n0\n0\n0\n0\n")) {
    return assert(false, "bits_per_line 0 clamps to 1");
  }
  let c2 = ok_bytes(pbm_build_p1(bits, 4, 2, 2, ""));
  if (!vec_is_str(c2, "P1\n4 2\n1 1\n1 1\n0 0\n0 0\n")) {
    return assert(false, "bits_per_line 2 wraps every two digits");
  }
  let c4 = ok_bytes(pbm_build_p1(bits, 4, 2, 4, ""));
  if (!vec_is_str(c4, "P1\n4 2\n1 1 1 1\n0 0 0 0\n")) {
    return assert(false, "bits_per_line 4 matches the row width");
  }
  let c100 = ok_bytes(pbm_build_p1(bits, 4, 2, 100, ""));
  if (!vec_is_str(c100, "P1\n4 2\n1 1 1 1 0 0 0 0\n")) {
    return assert(false, "bits_per_line above the raster keeps one line");
  }
  return assert(true, "pbm_build_p1 wraps, clamps and LF-terminates");
}

fn t16() -> TestResult {
  let one = bits_from_str("1");
  if (!bytes_err_is(pbm_build_p1(one, 2, 1, 2, ""), "pbm: bit buffer size mismatch")) {
    return assert(false, "short buffer for a 2x1 P1");
  }
  if (!bytes_err_is(pbm_build_p4(one, 2, 1, ""), "pbm: bit buffer size mismatch")) {
    return assert(false, "short buffer for a 2x1 P4");
  }
  let bad = Vec[UInt8].new();
  bad.push(2 as UInt8);
  if (!bytes_err_is(pbm_build_p1(bad, 1, 1, 1, ""), "pbm: non-binary bit")) {
    return assert(false, "bit value 2 is rejected by P1");
  }
  let big = Vec[UInt8].new();
  big.push(255 as UInt8);
  if (!bytes_err_is(pbm_build_p4(big, 1, 1, ""), "pbm: non-binary bit")) {
    return assert(false, "bit value 255 is rejected by P4");
  }
  let empty = Vec[UInt8].new();
  if (!bytes_err_is(pbm_build_p1(empty, 0, 1, 1, ""), "pbm: invalid width")) {
    return assert(false, "builder width 0");
  }
  if (!bytes_err_is(pbm_build_p1(empty, 1, 0, 1, ""), "pbm: invalid height")) {
    return assert(false, "builder height 0");
  }
  if (!bytes_err_is(pbm_build_p4(empty, -2, 1, ""), "pbm: invalid width")) {
    return assert(false, "builder negative width");
  }
  if (!bytes_err_is(pbm_build_p4(empty, 1, -2, ""), "pbm: invalid height")) {
    return assert(false, "builder negative height");
  }
  if (!bytes_err_is(pbm_build_p1(one, 1, 1, 1, "two\nlines"), "pbm: invalid comment")) {
    return assert(false, "newline in a P1 comment");
  }
  if (!bytes_err_is(pbm_build_p4(one, 1, 1, "two\nlines"), "pbm: invalid comment")) {
    return assert(false, "newline in a P4 comment");
  }
  let good = ok_bytes(pbm_build_p1(one, 1, 1, 1, "ok"));
  if (!vec_is_str(good, "P1\n# ok\n1 1\n1\n")) {
    return assert(false, "a printable comment builds");
  }
  return assert(true, "builders validate bits, dimensions and comments");
}

fn t17() -> TestResult {
  let one = bits_from_str("1");
  let p4 = ok_bytes(pbm_build_p4(one, 1, 1, "hello"));
  if (p4.len() != 16) { return assert(false, "commented 1x1 P4 is 16 bytes"); }
  if (!bytes_prefix_is(p4, "P4\n# hello\n1 1\n")) { return assert(false, "P4 comment line literal"); }
  if (!byte_is(p4, 15, 128)) { return assert(false, "P4 raster follows the comment"); }
  if (!raster_is(p4, 1, 1, "1")) { return assert(false, "commented P4 bit reads back"); }
  let zero = bits_from_str("0");
  let p1 = ok_bytes(pbm_build_p1(zero, 1, 1, 1, "hi"));
  if (!vec_is_str(p1, "P1\n# hi\n1 1\n0\n")) { return assert(false, "P1 comment line literal"); }
  let img = ok_img(pbm_parse_header(p1));
  if (img.data_offset != 12) { return assert(false, "comment shifts the P1 raster offset"); }
  if (!raster_is(p1, 1, 1, "0")) { return assert(false, "commented P1 bit reads back"); }
  let plain = ok_bytes(pbm_build_p1(zero, 1, 1, 1, ""));
  if (!vec_is_str(plain, "P1\n1 1\n0\n")) {
    return assert(false, "empty comment emits no comment line");
  }
  return assert(true, "comments are emitted as one '# <text>' header line");
}

fn t18() -> TestResult {
  let bits = bits_from_str("1001");
  let data = ok_bytes(pbm_build_p4(bits, 2, 2, ""));
  if (pbm_bit(data, -1, 0) != -1) { return assert(false, "negative x sentinel"); }
  if (pbm_bit(data, 0, -1) != -1) { return assert(false, "negative y sentinel"); }
  if (pbm_bit(data, 2, 0) != -1) { return assert(false, "x == width sentinel"); }
  if (pbm_bit(data, 0, 2) != -1) { return assert(false, "y == height sentinel"); }
  if (pbm_bit(data, 99, 99) != -1) { return assert(false, "far coordinate sentinel"); }
  let junk = bytes_of("not a pbm file");
  if (pbm_bit(junk, 0, 0) != -1) { return assert(false, "malformed input sentinel"); }
  let empty = Vec[UInt8].new();
  if (pbm_bit(empty, 0, 0) != -1) { return assert(false, "empty buffer sentinel"); }
  if (pbm_row_bytes(0) != 0) { return assert(false, "row_bytes(0) is 0"); }
  if (pbm_row_bytes(-3) != 0) { return assert(false, "row_bytes(-3) is 0"); }
  if (pbm_row_bytes(1) != 1) { return assert(false, "row_bytes(1) is 1"); }
  if (pbm_row_bytes(7) != 1) { return assert(false, "row_bytes(7) is 1"); }
  if (pbm_row_bytes(8) != 1) { return assert(false, "row_bytes(8) is 1"); }
  if (pbm_row_bytes(9) != 2) { return assert(false, "row_bytes(9) is 2"); }
  if (pbm_row_bytes(1000000) != 125000) { return assert(false, "row_bytes(1000000) is 125000"); }
  return assert(true, "pbm_bit sentinel and pbm_row_bytes boundaries");
}

fn t19() -> TestResult {
  let d = bytes_of("P1\n1 1\n# c\n1");
  let img = ok_img(pbm_parse_header(d));
  if (img.data_offset != 11) { return assert(false, "comment before the P1 raster sets offset 11"); }
  if (!raster_is(d, 1, 1, "1")) { return assert(false, "digit after a header comment"); }
  if (!img_err_is(pbm_parse_header(bytes_of("P1\n1 1\n1 # tail")), "pbm: non-binary digit")) {
    return assert(false, "'#' inside the P1 raster is data");
  }
  if (!img_err_is(pbm_parse_header(bytes_of("P1\n1 1\n1#c")), "pbm: non-binary digit")) {
    return assert(false, "'#' directly after a raster digit is data");
  }
  return assert(true, "comments belong to the header, not the P1 raster");
}

fn t20() -> TestResult {
  let d = bytes_of("P4\n1000000 1\n");
  var i = 0;
  while (i < 125000) {
    d.push(0 as UInt8);
    i = i + 1;
  }
  let img = ok_img(pbm_parse_header(d));
  if (pbm_width(&img) != 1000000) { return assert(false, "width 1000000 parses"); }
  if (pbm_height(&img) != 1) { return assert(false, "cap-height 1"); }
  if (pbm_bit(d, 999999, 0) != 0) { return assert(false, "last pixel of a cap-width row"); }
  if (pbm_bit(d, 1000000, 0) != -1) { return assert(false, "one past the cap width is sentinel"); }
  if (!img_err_is(pbm_parse_header(bytes_of("P4\n1000001 1\n")), "pbm: invalid width")) {
    return assert(false, "1000001 exceeds the cap");
  }
  return assert(true, "dimensions are capped at 1000000");
}

fn main() -> Int {
  io.println("=== xiom.pbm conformance tests ===");
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
  let r19 = t19();
  if r19.passed { io.println("  [PASS] " + r19.name); } else { io.println("  [FAIL] " + r19.name); failed = failed + 1; }
  let r20 = t20();
  if r20.passed { io.println("  [PASS] " + r20.name); } else { io.println("  [FAIL] " + r20.name); failed = failed + 1; }
  if failed == 0 {
    io.println("xiom.pbm: all tests passed");
  } else {
    io.println("xiom.pbm: tests failed");
  }
  return failed;
}
