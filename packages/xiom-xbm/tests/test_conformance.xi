// XIOM -- xiom.xbm conformance tests (20 checks)
// Port task: prove the pure-XIOM xiom.xbm module against X11 XBM.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module xbm_tests
use xiom.io; use xiom.test; use xiom.xbm;
use xiom.string; use xiom.string.compare;

// All Str equality goes through str_compare: `==` on Str is a pointer
// comparison in v0.61.3, so error-message and name checks use streq.

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

// Number of occurrences of byte `b` in `data` (LF/comma counting).
fn count_byte(data: &Vec[UInt8], b: Int) -> Int {
  var c = 0;
  var i = 0;
  while (i < data.len()) {
    let x: Int = (data[i] as Int) & 0xFF;
    if (x == b) { c = c + 1; }
    i = i + 1;
  }
  return c;
}

// True when every xbm_bit(x, y) matches the row-major pattern string.
fn raster_is(img: &XbmImage, w: Int, h: Int, pattern: Str) -> Bool {
  let want = bits_from_str(pattern);
  if (want.len() != w * h) { return false; }
  var y = 0;
  while (y < h) {
    var x = 0;
    while (x < w) {
      let got: Int = xbm_bit(img, x, y);
      let exp: Int = (want[y * w + x] as Int) & 0xFF;
      if (got != exp) { return false; }
      x = x + 1;
    }
    y = y + 1;
  }
  return true;
}

// A 1x1 XBM source with `body` spliced inside the byte-list braces.
fn one_by_one(body: Str) -> Vec[UInt8] {
  return bytes_of("#define a_width 1\n#define a_height 1\nstatic char a_bits[] = {" + body + "};\n");
}

fn ok_img(r: Result[XbmImage, Str]) -> XbmImage {
  match r {
    Ok(v) => { return v; },
    Err(e) => { return XbmImage{ width: 0; height: 0; name: ""; bits: Vec[UInt8].new() }; },
  }
}

fn img_err_is(r: Result[XbmImage, Str], want: Str) -> Bool {
  match r {
    Ok(v) => { return false; },
    Err(e) => { return streq(e, want); },
  }
}

fn ok_bytes(r: Result[Vec[UInt8], Str]) -> Vec[UInt8] {
  match r {
    Ok(v) => { return v; },
    Err(e) => { return Vec[UInt8].new(); },
  }
}

fn bytes_err_is(r: Result[Vec[UInt8], Str], want: Str) -> Bool {
  match r {
    Ok(v) => { return false; },
    Err(e) => { return streq(e, want); },
  }
}

fn t1() -> TestResult {
  let src = bytes_of("#define sample_width 2\n#define sample_height 2\nstatic char sample_bits[] = {\n   0x01, 0x02\n};\n");
  let img = ok_img(xbm_parse(src));
  if (xbm_width(&img) != 2) { return assert(false, "parsed width 2"); }
  if (xbm_height(&img) != 2) { return assert(false, "parsed height 2"); }
  if (!streq(xbm_name(&img), "sample")) { return assert(false, "parsed base name"); }
  if (xbm_byte_span(&img) != 2) { return assert(false, "byte span is 2"); }
  if (xbm_bit(&img, 0, 0) != 1) { return assert(false, "bit (0,0) is foreground"); }
  if (xbm_bit(&img, 1, 0) != 0) { return assert(false, "bit (1,0) is background"); }
  if (xbm_bit(&img, 0, 1) != 0) { return assert(false, "bit (0,1) is background"); }
  if (xbm_bit(&img, 1, 1) != 1) { return assert(false, "bit (1,1) is foreground"); }
  if (!raster_is(&img, 2, 2, "1001")) { return assert(false, "2x2 raster read-back"); }
  if (xbm_bit(&img, -1, 0) != -1) { return assert(false, "negative x sentinel"); }
  if (xbm_bit(&img, 0, -1) != -1) { return assert(false, "negative y sentinel"); }
  if (xbm_bit(&img, 2, 0) != -1) { return assert(false, "x == width sentinel"); }
  if (xbm_bit(&img, 0, 2) != -1) { return assert(false, "y == height sentinel"); }
  if (xbm_bit(&img, 99, 99) != -1) { return assert(false, "far coordinate sentinel"); }
  if (xbm_row_bytes(2) != 1) { return assert(false, "row_bytes(2) is 1"); }
  return assert(true, "canonical 2x2 parse exposes fields, bits and sentinels");
}

fn t2() -> TestResult {
  let src = bytes_of("/* head */# define /*a*/ sample_width /*b*/ 3 /*c*/\n#define sample_height 2\nstatic unsigned char /*d*/ sample_bits /*e*/ [ /*f*/ ] /*g*/ = /*h*/ { /*i*/ 0X5, /*j*/ 0x2, /*k*/ } /*l*/ ; /*m*/ \n");
  let img = ok_img(xbm_parse(src));
  if (xbm_width(&img) != 3) { return assert(false, "commented width 3"); }
  if (xbm_height(&img) != 2) { return assert(false, "commented height 2"); }
  if (!streq(xbm_name(&img), "sample")) { return assert(false, "commented base name"); }
  if (xbm_byte_span(&img) != 2) { return assert(false, "commented byte span 2"); }
  if (!raster_is(&img, 3, 2, "101010")) { return assert(false, "commented raster bits"); }
  return assert(true, "comments, '# define', unsigned char, 0X and 1-digit hex parse");
}

fn t3() -> TestResult {
  let d9 = bytes_of("#define p_width 9\n#define p_height 1\nstatic char p_bits[] = { 0x01, 0x01 };\n");
  let i9 = ok_img(xbm_parse(d9));
  if (xbm_byte_span(&i9) != 2) { return assert(false, "9-bit row spans 2 bytes"); }
  if (!raster_is(&i9, 9, 1, "100000001")) { return assert(false, "9x1 LSB-first read"); }
  let d3 = bytes_of("#define q_width 3\n#define q_height 1\nstatic char q_bits[] = { 0xff };\n");
  let i3 = ok_img(xbm_parse(d3));
  if (xbm_bit(&i3, 2, 0) != 1) { return assert(false, "3x1 bit 2 is the 0x04 bit"); }
  if (!raster_is(&i3, 3, 1, "111")) { return assert(false, "3x1 padding bits ignored"); }
  let d8 = bytes_of("#define r_width 8\n#define r_height 2\nstatic char r_bits[] = { 0x81, 0x80 };\n");
  let i8 = ok_img(xbm_parse(d8));
  if (!raster_is(&i8, 8, 2, "1000000100000001")) { return assert(false, "8x2 rows are independent"); }
  return assert(true, "bit 0 is the leftmost pixel and each row pads independently");
}

fn t4() -> TestResult {
  let pixels = bits_from_str("1001");
  let packed = ok_bytes(xbm_pack(pixels, 2, 2));
  if (packed.len() != 2) { return assert(false, "2x2 packs to 2 bytes"); }
  if (!byte_is(packed, 0, 1)) { return assert(false, "row 0 packs to 0x01"); }
  if (!byte_is(packed, 1, 2)) { return assert(false, "row 1 packs to 0x02"); }
  let text = ok_bytes(xbm_build("sample", packed, 2, 2));
  if (!vec_is_str(text, "#define sample_width 2\n#define sample_height 2\nstatic char sample_bits[] = {\n   0x01, 0x02\n};\n")) {
    return assert(false, "canonical 2x2 XBM literal");
  }
  return assert(true, "xbm_pack and xbm_build pin the canonical 2x2 output");
}

fn t5() -> TestResult {
  let bits = Vec[UInt8].new();
  var i = 0;
  while (i < 13) {
    bits.push(i as UInt8);
    i = i + 1;
  }
  let text = ok_bytes(xbm_build("wide", bits, 100, 1));
  if (!vec_is_str(text, "#define wide_width 100\n#define wide_height 1\nstatic char wide_bits[] = {\n   0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b,\n   0x0c\n};\n")) {
    return assert(false, "13 bytes wrap as 12 + 1");
  }
  let img = ok_img(xbm_parse(text));
  if (xbm_width(&img) != 100) { return assert(false, "wrapped build parses width 100"); }
  if (xbm_byte_span(&img) != 13) { return assert(false, "wrapped build has 13 bytes"); }
  if (xbm_bit(&img, 0, 0) != 0) { return assert(false, "first wrapped bit is 0"); }
  return assert(true, "canonical build wraps 12 bytes per line with lowercase hex");
}

fn t6() -> TestResult {
  let one = ok_bytes(xbm_pack(bits_from_str("1"), 1, 1));
  if (!byte_is(one, 0, 1)) { return assert(false, "single foreground pixel is 0x01"); }
  let zero = ok_bytes(xbm_pack(bits_from_str("0"), 1, 1));
  if (!byte_is(zero, 0, 0)) { return assert(false, "single background pixel is 0x00"); }
  let p8 = ok_bytes(xbm_pack(bits_from_str("10000001"), 8, 1));
  if (!byte_is(p8, 0, 129)) { return assert(false, "8x1 packs to 0x81"); }
  let p9 = ok_bytes(xbm_pack(bits_from_str("100000001"), 9, 1));
  if (p9.len() != 2) { return assert(false, "9x1 packs to 2 bytes"); }
  if (!byte_is(p9, 0, 1)) { return assert(false, "9x1 byte 0 is 0x01"); }
  if (!byte_is(p9, 1, 1)) { return assert(false, "9x1 byte 1 is 0x01"); }
  let p16 = ok_bytes(xbm_pack(bits_from_str("1000000000000001"), 16, 1));
  if (!byte_is(p16, 0, 1)) { return assert(false, "16x1 byte 0 is 0x01"); }
  if (!byte_is(p16, 1, 128)) { return assert(false, "16x1 byte 1 is 0x80"); }
  if (!bytes_err_is(xbm_pack(bits_from_str("1"), 2, 1), "xbm: pixel buffer size mismatch")) {
    return assert(false, "short pixel buffer");
  }
  let bad = Vec[UInt8].new();
  bad.push(2 as UInt8);
  if (!bytes_err_is(xbm_pack(bad, 1, 1), "xbm: non-binary pixel")) {
    return assert(false, "pixel value 2 is rejected");
  }
  let empty = Vec[UInt8].new();
  if (!bytes_err_is(xbm_pack(empty, 0, 1), "xbm: invalid width")) {
    return assert(false, "pack width 0");
  }
  if (!bytes_err_is(xbm_pack(empty, 1, 0), "xbm: invalid height")) {
    return assert(false, "pack height 0");
  }
  return assert(true, "xbm_pack LSB-first boundaries and validation");
}

fn t7() -> TestResult {
  let pattern = "101101001101110000001";
  let pixels = bits_from_str(pattern);
  let packed = ok_bytes(xbm_pack(pixels, 7, 3));
  if (packed.len() != 3) { return assert(false, "7x3 packs to 3 bytes"); }
  if (!byte_is(packed, 0, 45)) { return assert(false, "7x3 row 0 is 0x2d"); }
  if (!byte_is(packed, 1, 118)) { return assert(false, "7x3 row 1 is 0x76"); }
  if (!byte_is(packed, 2, 64)) { return assert(false, "7x3 row 2 is 0x40"); }
  let text = ok_bytes(xbm_build("rt", packed, 7, 3));
  let img = ok_img(xbm_parse(text));
  if (!streq(xbm_name(&img), "rt")) { return assert(false, "round-trip name"); }
  if (xbm_width(&img) != 7) { return assert(false, "round-trip width 7"); }
  if (xbm_height(&img) != 3) { return assert(false, "round-trip height 3"); }
  if (!raster_is(&img, 7, 3, pattern)) { return assert(false, "round-trip raster bits"); }
  if (!vec_eq(packed, ok_bytes(xbm_pack(bits_from_str(pattern), 7, 3)))) {
    return assert(false, "packing is deterministic");
  }
  let parsed_bits: Vec[UInt8] = img.bits;
  let text2 = ok_bytes(xbm_build("rt", parsed_bits, 7, 3));
  if (!vec_eq(text, text2)) { return assert(false, "build-parse-build is byte-exact"); }
  return assert(true, "non-byte-aligned 7x3 pack-build-parse round trip");
}

fn t8() -> TestResult {
  let empty = Vec[UInt8].new();
  if (!img_err_is(xbm_parse(empty), "xbm: missing width define")) {
    return assert(false, "empty input misses width");
  }
  if (!img_err_is(xbm_parse(bytes_of("   \n\t /* c */ ")), "xbm: missing width define")) {
    return assert(false, "trivia-only input misses width");
  }
  if (!img_err_is(xbm_parse(bytes_of("#define a_height 2\n")), "xbm: missing width define")) {
    return assert(false, "height define alone misses width");
  }
  if (!img_err_is(xbm_parse(bytes_of("#define a_width 2\n")), "xbm: missing height define")) {
    return assert(false, "width define alone misses height");
  }
  if (!img_err_is(xbm_parse(bytes_of("#define a_width 2\n#define a_height 2\n")), "xbm: missing array")) {
    return assert(false, "defines without array miss the array");
  }
  return assert(true, "missing width/height defines and missing array are reported");
}

fn t9() -> TestResult {
  let d1 = bytes_of("#define a_width 2\n#define a_width 3\n#define a_height 1\nstatic char a_bits[] = { 0x00, 0x00 };\n");
  if (!img_err_is(xbm_parse(d1), "xbm: duplicate width define")) {
    return assert(false, "second width define is a duplicate");
  }
  let d2 = bytes_of("#define a_width 2\n#define a_height 1\n#define a_height 1\nstatic char a_bits[] = { 0x00, 0x00 };\n");
  if (!img_err_is(xbm_parse(d2), "xbm: duplicate height define")) {
    return assert(false, "second height define is a duplicate");
  }
  return assert(true, "duplicate width and height defines are rejected");
}

fn t10() -> TestResult {
  if (!img_err_is(xbm_parse(bytes_of("#define z_width 0\n")), "xbm: invalid width")) {
    return assert(false, "width 0 is invalid");
  }
  if (!img_err_is(xbm_parse(bytes_of("#define z_width 1000001\n")), "xbm: invalid width")) {
    return assert(false, "width 1000001 exceeds the cap");
  }
  if (!img_err_is(xbm_parse(bytes_of("#define z_width 1234567890\n")), "xbm: invalid width")) {
    return assert(false, "10-digit width token is invalid");
  }
  if (!img_err_is(xbm_parse(bytes_of("#define z_height 0\n#define z_width 1\n")), "xbm: invalid height")) {
    return assert(false, "height 0 is invalid");
  }
  if (!img_err_is(xbm_parse(bytes_of("#define z_height 1000001\n#define z_width 1\n")), "xbm: invalid height")) {
    return assert(false, "height 1000001 exceeds the cap");
  }
  if (!img_err_is(xbm_parse(bytes_of("#define sample 5\n")), "xbm: malformed define")) {
    return assert(false, "define without _width/_height suffix");
  }
  if (!img_err_is(xbm_parse(bytes_of("#define _width 5\n")), "xbm: malformed define")) {
    return assert(false, "define with an empty base name");
  }
  if (!img_err_is(xbm_parse(bytes_of("#define sample_width\n")), "xbm: malformed define")) {
    return assert(false, "define without a value");
  }
  if (!img_err_is(xbm_parse(bytes_of("#definesample_width 5\n")), "xbm: malformed define")) {
    return assert(false, "#define must be a whole keyword");
  }
  return assert(true, "non-positive and oversized dimensions and malformed defines");
}

fn t11() -> TestResult {
  let d1 = bytes_of("#define a_width 2\n#define a_height 2\nstatic char b_bits[] = { 0x00, 0x00 };\n");
  if (!img_err_is(xbm_parse(d1), "xbm: name mismatch")) {
    return assert(false, "array base differs from the defines");
  }
  let d2 = bytes_of("#define a_width 2\n#define b_height 2\nstatic char a_bits[] = { 0x00, 0x00 };\n");
  if (!img_err_is(xbm_parse(d2), "xbm: name mismatch")) {
    return assert(false, "width and height bases differ");
  }
  let d3 = bytes_of("#define a_width 2\n#define a_height 2\nstatic char a[] = { 0x00, 0x00 };\n");
  if (!img_err_is(xbm_parse(d3), "xbm: malformed array declaration")) {
    return assert(false, "array without a _bits suffix");
  }
  let d4 = bytes_of("#define a_width 2\n#define a_height 2\nstatic char a_bits[2] = { 0x00, 0x00 };\n");
  if (!img_err_is(xbm_parse(d4), "xbm: malformed array declaration")) {
    return assert(false, "non-empty brackets are not accepted");
  }
  let d5 = bytes_of("#define a_width 2\n#define a_height 2\nchar a_bits[] = { 0x00, 0x00 };\n");
  if (!img_err_is(xbm_parse(d5), "xbm: malformed array declaration")) {
    return assert(false, "static keyword is required");
  }
  let d6 = bytes_of("#define a_width 2\n#define a_height 2\nstatic int a_bits[] = { 0x00, 0x00 };\n");
  if (!img_err_is(xbm_parse(d6), "xbm: malformed array declaration")) {
    return assert(false, "element type must be char");
  }
  let d7 = bytes_of("#define a_width 2\n#define a_height 2\nstatic char _bits[] = { 0x00, 0x00 };\n");
  if (!img_err_is(xbm_parse(d7), "xbm: malformed array declaration")) {
    return assert(false, "array with an empty base name");
  }
  return assert(true, "name mismatch and malformed array declarations are rejected");
}

fn t12() -> TestResult {
  if (!img_err_is(xbm_parse(one_by_one(" 0x")), "xbm: non-hex byte")) {
    return assert(false, "0x without digits");
  }
  if (!img_err_is(xbm_parse(one_by_one(" 0xg1")), "xbm: non-hex byte")) {
    return assert(false, "0x with a non-hex digit");
  }
  if (!img_err_is(xbm_parse(one_by_one(" 0x123")), "xbm: non-hex byte")) {
    return assert(false, "three hex digits");
  }
  if (!img_err_is(xbm_parse(one_by_one(" 0xzz")), "xbm: non-hex byte")) {
    return assert(false, "letters outside a..f");
  }
  if (!img_err_is(xbm_parse(one_by_one(" 123")), "xbm: non-hex byte")) {
    return assert(false, "byte token without the 0x prefix");
  }
  if (!img_err_is(xbm_parse(one_by_one(" 0x00 0x01")), "xbm: malformed byte list")) {
    return assert(false, "two bytes without a separating comma");
  }
  if (!img_err_is(xbm_parse(one_by_one(" 0x00 0x01")), "xbm: malformed byte list")) {
    return assert(false, "missing comma stays structural");
  }
  if (!img_err_is(xbm_parse(bytes_of("#define a_width 1\n#define a_height 1\nstatic char a_bits[] = { 0x00")), "xbm: malformed byte list")) {
    return assert(false, "unterminated byte list");
  }
  if (!img_err_is(xbm_parse(bytes_of("#define a_width 1\n#define a_height 1\nstatic char a_bits[] = { 0x00 }")), "xbm: malformed array declaration")) {
    return assert(false, "missing semicolon after the array");
  }
  if (!img_err_is(xbm_parse(bytes_of("#define a_width 1\n#define a_height 1\nstatic char a_bits[] = 0x00 };\n")), "xbm: malformed array declaration")) {
    return assert(false, "missing opening brace");
  }
  if (!img_err_is(xbm_parse(bytes_of("#define a_width 1\n#define a_height 1\nstatic char a_bits[] { 0x00 };\n")), "xbm: malformed array declaration")) {
    return assert(false, "missing equals sign");
  }
  if (!img_err_is(xbm_parse(bytes_of("#define a_width 1\n#define a_height 1\nstatic char a_bits[ = { 0x00 };\n")), "xbm: malformed array declaration")) {
    return assert(false, "missing closing bracket");
  }
  return assert(true, "non-hex bytes and malformed byte lists are rejected");
}

fn t13() -> TestResult {
  let d1 = bytes_of("#define a_width 2\n#define a_height 2\nstatic char a_bits[] = { 0x01 };\n");
  if (!img_err_is(xbm_parse(d1), "xbm: byte count mismatch")) {
    return assert(false, "2x2 with 1 byte");
  }
  let d2 = bytes_of("#define a_width 2\n#define a_height 2\nstatic char a_bits[] = { 0x01, 0x02, 0x03 };\n");
  if (!img_err_is(xbm_parse(d2), "xbm: byte count mismatch")) {
    return assert(false, "2x2 with 3 bytes");
  }
  let d3 = bytes_of("#define a_width 1\n#define a_height 1\nstatic char a_bits[] = { };\n");
  if (!img_err_is(xbm_parse(d3), "xbm: byte count mismatch")) {
    return assert(false, "1x1 with an empty byte list");
  }
  let d4 = bytes_of("#define a_width 9\n#define a_height 1\nstatic char a_bits[] = { 0x01 };\n");
  if (!img_err_is(xbm_parse(d4), "xbm: byte count mismatch")) {
    return assert(false, "9x1 with 1 of 2 bytes");
  }
  return assert(true, "the parsed byte count must match row_bytes*height");
}

fn t14() -> TestResult {
  if (!img_err_is(xbm_parse(bytes_of("/* a #define x_width 2")), "xbm: unclosed comment")) {
    return assert(false, "comment opened at the start");
  }
  if (!img_err_is(xbm_parse(bytes_of("#define x_width 2 /*")), "xbm: unclosed comment")) {
    return assert(false, "comment opened after a define");
  }
  if (!img_err_is(xbm_parse(bytes_of("#define /* c x_width 2\n")), "xbm: unclosed comment")) {
    return assert(false, "comment opened inside a define");
  }
  if (!img_err_is(xbm_parse(bytes_of("/*")), "xbm: unclosed comment")) {
    return assert(false, "bare comment opener");
  }
  if (!img_err_is(xbm_parse(bytes_of("/**/#define x_width 2\n")), "xbm: missing height define")) {
    return assert(false, "a balanced empty comment is not an error");
  }
  return assert(true, "unclosed comments are detected before parsing");
}

fn t15() -> TestResult {
  let base = "#define a_width 1\n#define a_height 1\nstatic char a_bits[] = { 0x01 };\n";
  let d1 = bytes_of(base + "garbage");
  if (!img_err_is(xbm_parse(d1), "xbm: trailing tokens")) {
    return assert(false, "garbage after the array");
  }
  let d2 = bytes_of(base + "#define z_width 2\n");
  if (!img_err_is(xbm_parse(d2), "xbm: trailing tokens")) {
    return assert(false, "defines after the array are trailing");
  }
  let d3 = bytes_of(base + "static char b_bits[] = { 0x01 };\n");
  if (!img_err_is(xbm_parse(d3), "xbm: trailing tokens")) {
    return assert(false, "a second array is trailing");
  }
  let d4 = bytes_of(base + " /* c */ \n\t ");
  let img = ok_img(xbm_parse(d4));
  if (xbm_bit(&img, 0, 0) != 1) { return assert(false, "trailing trivia still parses"); }
  return assert(true, "only whitespace and comments may follow the array");
}

fn t16() -> TestResult {
  let d1 = bytes_of("#define h_width 8\n#define h_height 1\nstatic char h_bits[] = { 0xFF };\n");
  let i1 = ok_img(xbm_parse(d1));
  if (!raster_is(&i1, 8, 1, "11111111")) { return assert(false, "0xFF is eight ones"); }
  let d2 = bytes_of("#define h_width 8\n#define h_height 1\nstatic char h_bits[] = { 0X80 };\n");
  let i2 = ok_img(xbm_parse(d2));
  if (!raster_is(&i2, 8, 1, "00000001")) { return assert(false, "0X80 sets the last bit"); }
  let d3 = bytes_of("#define h_width 8\n#define h_height 1\nstatic char h_bits[] = { 0xaA };\n");
  let i3 = ok_img(xbm_parse(d3));
  if (!raster_is(&i3, 8, 1, "01010101")) { return assert(false, "mixed-case 0xaA is LSB-first"); }
  return assert(true, "uppercase hex, 0X and case mixing read the same bytes");
}

fn t17() -> TestResult {
  if (xbm_row_bytes(0) != 0) { return assert(false, "row_bytes(0) is 0"); }
  if (xbm_row_bytes(-3) != 0) { return assert(false, "row_bytes(-3) is 0"); }
  if (xbm_row_bytes(1) != 1) { return assert(false, "row_bytes(1) is 1"); }
  if (xbm_row_bytes(7) != 1) { return assert(false, "row_bytes(7) is 1"); }
  if (xbm_row_bytes(8) != 1) { return assert(false, "row_bytes(8) is 1"); }
  if (xbm_row_bytes(9) != 2) { return assert(false, "row_bytes(9) is 2"); }
  if (xbm_row_bytes(1000000) != 125000) { return assert(false, "row_bytes(1000000) is 125000"); }
  let src = bytes_of("#define s_width 3\n#define s_height 2\nstatic char s_bits[] = { 0x05, 0x02 };\n");
  let img = ok_img(xbm_parse(src));
  if (xbm_byte_span(&img) != xbm_row_bytes(3) * 2) { return assert(false, "span is stride*height"); }
  return assert(true, "row stride and byte span boundaries");
}

fn t18() -> TestResult {
  let one = ok_bytes(xbm_pack(bits_from_str("1"), 1, 1));
  if (!bytes_err_is(xbm_build("", one, 1, 1), "xbm: invalid name")) {
    return assert(false, "empty name");
  }
  if (!bytes_err_is(xbm_build("2bad", one, 1, 1), "xbm: invalid name")) {
    return assert(false, "name starting with a digit");
  }
  if (!bytes_err_is(xbm_build("bad-name", one, 1, 1), "xbm: invalid name")) {
    return assert(false, "hyphen in the name");
  }
  if (!bytes_err_is(xbm_build("bad name", one, 1, 1), "xbm: invalid name")) {
    return assert(false, "space in the name");
  }
  if (!bytes_err_is(xbm_build("ok", one, 0, 1), "xbm: invalid width")) {
    return assert(false, "builder width 0");
  }
  if (!bytes_err_is(xbm_build("ok", one, 1, 0), "xbm: invalid height")) {
    return assert(false, "builder height 0");
  }
  if (!bytes_err_is(xbm_build("ok", one, 1000001, 1), "xbm: invalid width")) {
    return assert(false, "builder width above the cap");
  }
  if (!bytes_err_is(xbm_build("ok", one, 2, 2), "xbm: byte count mismatch")) {
    return assert(false, "builder byte count mismatch");
  }
  let text = ok_bytes(xbm_build("ok", one, 1, 1));
  if (!bytes_prefix_is(text, "#define ok_width 1\n#define ok_height 1\n")) {
    return assert(false, "valid name builds");
  }
  return assert(true, "xbm_build validates names, dimensions and byte count");
}

fn t19() -> TestResult {
  let src = bytes_of("#define b_height 1\r\n# define b_width 2\r\nstatic char b_bits[] = { 0x03 };\r\n  \t\n");
  let img = ok_img(xbm_parse(src));
  if (xbm_width(&img) != 2) { return assert(false, "height-before-width is accepted"); }
  if (xbm_height(&img) != 1) { return assert(false, "height-before-width keeps the height"); }
  if (!raster_is(&img, 2, 1, "11")) { return assert(false, "CRLF source bits"); }
  let d2 = bytes_of("#define c_width 1\n#define c_height 1\nstatic char c_bits[] = { 0x00, };\n");
  let i2 = ok_img(xbm_parse(d2));
  if (xbm_bit(&i2, 0, 0) != 0) { return assert(false, "trailing comma before } is accepted"); }
  return assert(true, "define order, CRLF and trailing commas are accepted");
}

fn t20() -> TestResult {
  let d = bytes_of("#define cap_width 1000000\n#define cap_height 1\nstatic char cap_bits[] = {\n");
  var i = 0;
  while (i < 125000) {
    d.push(48 as UInt8); d.push(120 as UInt8); d.push(48 as UInt8); d.push(48 as UInt8);
    if (i + 1 < 125000) {
      d.push(44 as UInt8);
      d.push(32 as UInt8);
    }
    i = i + 1;
  }
  d.push(10 as UInt8);
  d.push(125 as UInt8);
  d.push(59 as UInt8);
  let img = ok_img(xbm_parse(d));
  if (xbm_width(&img) != 1000000) { return assert(false, "width 1000000 parses"); }
  if (xbm_height(&img) != 1) { return assert(false, "cap-height 1"); }
  if (xbm_byte_span(&img) != 125000) { return assert(false, "cap span is 125000"); }
  if (xbm_bit(&img, 999999, 0) != 0) { return assert(false, "last pixel of a cap-width row"); }
  if (xbm_bit(&img, 1000000, 0) != -1) { return assert(false, "one past the cap width is sentinel"); }
  if (!img_err_is(xbm_parse(bytes_of("#define w2_width 1000001\n#define w2_height 1\nstatic char w2_bits[] = { 0x00 };\n")), "xbm: invalid width")) {
    return assert(false, "1000001 exceeds the cap");
  }
  return assert(true, "dimensions are capped at 1000000");
}

fn main() -> Int {
  io.println("=== xiom.xbm conformance tests ===");
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
    io.println("xiom.xbm: all tests passed");
  } else {
    io.println("xiom.xbm: tests failed");
  }
  return failed;
}
