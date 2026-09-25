// XIOM -- xiom.xpm conformance tests (19 checks)
// Port task: prove the pure-XIOM xiom.xpm module against X11 XPM.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module xpm_tests
use xiom.io; use xiom.test; use xiom.xpm;
use xiom.string; use xiom.string.compare;

// All Str equality goes through str_compare: `==` on Str is a pointer
// comparison in v0.61.3, so error-message and color checks use streq.

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

// A canonical XPM source: header comment, declaration for base name "s",
// value line `hdr` and the pre-formatted string-list `body`.
fn xpm_src(hdr: Str, body: Str) -> Vec[UInt8] {
  return bytes_of("/* XPM */\nstatic char * s[] = {\n\"" + hdr + "\"" + body + "\n};\n");
}

// A 1x1 image with the one value line `hdr`, one color line and one row.
fn one_hdr(hdr: Str) -> Vec[UInt8] {
  return xpm_src(hdr, ",\n\"a c #000000\",\n\"a\"");
}

// The canonical 2x2 two-color fixture used by several checks.
fn basic_src() -> Vec[UInt8] {
  return bytes_of("/* XPM */\nstatic char * sample[] = {\n\"2 2 2 1\",\n\"  c #ffffff\",\n\"X c #000000\",\n\" X\",\n\"X \"\n};\n");
}

// An empty XpmImage used as the Err fallback in accessor helpers.
fn empty_img() -> XpmImage {
  return XpmImage{
    width: 0;
    height: 0;
    cpp: 0;
    has_hotspot: false;
    x_hot: -1;
    y_hot: -1;
    symbols: Vec[UInt8].new();
    colors: Vec[Str].new();
    color_lens: Vec[Int].new();
    pixels: Vec[Int].new();
  };
}

// Full struct literal for builder checks (no hotspot).
fn img4(w: Int, h: Int, cpp: Int, symbols: Vec[UInt8], colors: Vec[Str], color_lens: Vec[Int], pixels: Vec[Int]) -> XpmImage {
  return XpmImage{
    width: w;
    height: h;
    cpp: cpp;
    has_hotspot: false;
    x_hot: -1;
    y_hot: -1;
    symbols: symbols;
    colors: colors;
    color_lens: color_lens;
    pixels: pixels;
  };
}

// Full struct literal for builder checks with a hotspot.
fn img_hot(w: Int, h: Int, cpp: Int, symbols: Vec[UInt8], colors: Vec[Str], color_lens: Vec[Int], pixels: Vec[Int], xh: Int, yh: Int) -> XpmImage {
  return XpmImage{
    width: w;
    height: h;
    cpp: cpp;
    has_hotspot: true;
    x_hot: xh;
    y_hot: yh;
    symbols: symbols;
    colors: colors;
    color_lens: color_lens;
    pixels: pixels;
  };
}

// One-byte symbol pool.
fn syms1(b0: Int) -> Vec[UInt8] {
  let v = Vec[UInt8].new();
  v.push(b0 as UInt8);
  return v;
}

// One-entry color table.
fn cols1(c: Str) -> Vec[Str] {
  let v = Vec[Str].new();
  v.push(c);
  return v;
}

// One-entry color-length table.
fn lens1(cl: Int) -> Vec[Int] {
  let v = Vec[Int].new();
  v.push(cl);
  return v;
}

// One-entry pixel buffer.
fn pix1(k: Int) -> Vec[Int] {
  let v = Vec[Int].new();
  v.push(k);
  return v;
}

// A consistent 1x1 image: symbol 'a', color #000000, pixel 0.
fn img_one() -> XpmImage {
  return img4(1, 1, 1, syms1(97), cols1("#000000"), lens1(7), pix1(0));
}

fn ok_img(r: Result[XpmImage, Str]) -> XpmImage {
  match r {
    Ok(v) => { return v; },
    Err(e) => { return empty_img(); },
  }
}

fn img_err_is(r: Result[XpmImage, Str], want: Str) -> Bool {
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
  let img = ok_img(xpm_parse(basic_src()));
  if (xpm_width(&img) != 2) { return assert(false, "width 2"); }
  if (xpm_height(&img) != 2) { return assert(false, "height 2"); }
  if (xpm_ncolors(&img) != 2) { return assert(false, "ncolors 2"); }
  if (xpm_cpp(&img) != 1) { return assert(false, "cpp 1"); }
  if (xpm_has_hotspot(&img)) { return assert(false, "no hotspot"); }
  if (xpm_hotspot_x(&img) != -1) { return assert(false, "absent hotspot x is -1"); }
  if (xpm_hotspot_y(&img) != -1) { return assert(false, "absent hotspot y is -1"); }
  if (xpm_pixel_index(&img, 0, 0) != 0) { return assert(false, "pixel (0,0)"); }
  if (xpm_pixel_index(&img, 1, 0) != 1) { return assert(false, "pixel (1,0)"); }
  if (xpm_pixel_index(&img, 0, 1) != 1) { return assert(false, "pixel (0,1)"); }
  if (xpm_pixel_index(&img, 1, 1) != 0) { return assert(false, "pixel (1,1)"); }
  if (!streq(xpm_pixel_color(&img, 0, 0), "#ffffff")) { return assert(false, "color (0,0)"); }
  if (!streq(xpm_pixel_color(&img, 1, 0), "#000000")) { return assert(false, "color (1,0)"); }
  if (!streq(xpm_color_at(&img, 1), "#000000")) { return assert(false, "color entry 1"); }
  if (!streq(xpm_color_at(&img, 2), "")) { return assert(false, "color entry out of range"); }
  if (!streq(xpm_color_at(&img, -1), "")) { return assert(false, "negative color entry"); }
  if (xpm_symbol_index(&img, " ") != 0) { return assert(false, "space symbol"); }
  if (xpm_symbol_index(&img, "X") != 1) { return assert(false, "X symbol"); }
  if (xpm_symbol_index(&img, "Z") != -1) { return assert(false, "unknown symbol"); }
  if (xpm_symbol_index(&img, "") != -1) { return assert(false, "empty symbol"); }
  if (!streq(xpm_symbol_at(&img, 0), " ")) { return assert(false, "symbol_at 0"); }
  if (!streq(xpm_symbol_at(&img, 1), "X")) { return assert(false, "symbol_at 1"); }
  if (!streq(xpm_symbol_at(&img, 2), "")) { return assert(false, "symbol_at out of range"); }
  if (xpm_pixel_index(&img, -1, 0) != -1) { return assert(false, "negative x"); }
  if (xpm_pixel_index(&img, 0, -1) != -1) { return assert(false, "negative y"); }
  if (xpm_pixel_index(&img, 2, 0) != -1) { return assert(false, "x == width"); }
  if (xpm_pixel_index(&img, 0, 2) != -1) { return assert(false, "y == height"); }
  if (xpm_pixel_index(&img, 99, 99) != -1) { return assert(false, "far coordinate"); }
  if (!streq(xpm_pixel_color(&img, 9, 9), "")) { return assert(false, "out-of-range color"); }
  return assert(true, "canonical 2x2 parse exposes fields, colors, symbols and sentinels");
}

fn t2() -> TestResult {
  let src1 = bytes_of("static char * sample[] = {\n\"2 2 2 1\",\n\"  c #ffffff\",\n\"X c #000000\",\n\" X\",\n\"X \"\n};\n");
  let a = ok_img(xpm_parse(src1));
  if (xpm_width(&a) != 2) { return assert(false, "header comment is optional"); }
  let src2 = bytes_of("/* XPM */ static /* a */ char /* b */ * /* c */ sample /* d */ [ /* e */ ] /* f */ = /* g */ { /* h */ \"2 2 2 1\" /* i */ , /* j */ \"  c #ffffff\" , \"X c #000000\" , \" X\" , \"X \" /* k */ } /* l */ ; /* m */ \n");
  let b = ok_img(xpm_parse(src2));
  if (xpm_pixel_index(&b, 1, 1) != 0) { return assert(false, "comments between tokens"); }
  if (!streq(xpm_pixel_color(&b, 0, 0), "#ffffff")) { return assert(false, "commented color value"); }
  let src3 = xpm_src("2 1 2 1", ",\n\"/ c #000000\",\n\"* c #ffffff\",\n\"/*\"");
  let c = ok_img(xpm_parse(src3));
  if (xpm_pixel_index(&c, 0, 0) != 0) { return assert(false, "slash symbol"); }
  if (xpm_pixel_index(&c, 1, 0) != 1) { return assert(false, "star symbol"); }
  if (!streq(xpm_symbol_at(&c, 1), "*")) { return assert(false, "star symbol text"); }
  return assert(true, "the header comment is optional and comment openers inside strings are data");
}

fn t3() -> TestResult {
  let src = xpm_src("2 1 3 1", ",\n\"a c red m white s solid\",\n\"b c None\",\n\"c c #AbCdEf g red\",\n\"ab\"");
  let img = ok_img(xpm_parse(src));
  if (xpm_ncolors(&img) != 3) { return assert(false, "three colors"); }
  if (!streq(xpm_color_at(&img, 0), "red")) { return assert(false, "named color passes through"); }
  if (!streq(xpm_color_at(&img, 1), "None")) { return assert(false, "None passes through"); }
  if (!streq(xpm_color_at(&img, 2), "#AbCdEf")) { return assert(false, "hex spelling preserved"); }
  if (!streq(xpm_pixel_color(&img, 0, 0), "red")) { return assert(false, "pixel color name"); }
  if (!streq(xpm_pixel_color(&img, 1, 0), "None")) { return assert(false, "pixel color None"); }
  return assert(true, "named colors pass through and extension keys are accepted and ignored");
}

fn t4() -> TestResult {
  let src = bytes_of("/* XPM */\nstatic char * hot[] = {\n\"3 2 3 2 1 1\",\n\"aa c #ff0000\",\n\"ab c #00ff00 m extra\",\n\"ba c #0000ff\",\n\"aaabaa\",\n\"baaaab\"\n};\n");
  let img = ok_img(xpm_parse(src));
  if (xpm_width(&img) != 3) { return assert(false, "cpp2 width 3"); }
  if (xpm_height(&img) != 2) { return assert(false, "cpp2 height 2"); }
  if (xpm_cpp(&img) != 2) { return assert(false, "cpp2 cpp 2"); }
  if (xpm_ncolors(&img) != 3) { return assert(false, "cpp2 ncolors 3"); }
  if (!xpm_has_hotspot(&img)) { return assert(false, "cpp2 hotspot present"); }
  if (xpm_hotspot_x(&img) != 1) { return assert(false, "hotspot x 1"); }
  if (xpm_hotspot_y(&img) != 1) { return assert(false, "hotspot y 1"); }
  if (xpm_pixel_index(&img, 0, 0) != 0) { return assert(false, "cpp2 pixel (0,0)"); }
  if (xpm_pixel_index(&img, 1, 0) != 1) { return assert(false, "cpp2 pixel (1,0)"); }
  if (xpm_pixel_index(&img, 2, 0) != 0) { return assert(false, "cpp2 pixel (2,0)"); }
  if (xpm_pixel_index(&img, 0, 1) != 2) { return assert(false, "cpp2 pixel (0,1)"); }
  if (xpm_pixel_index(&img, 1, 1) != 0) { return assert(false, "cpp2 pixel (1,1)"); }
  if (xpm_pixel_index(&img, 2, 1) != 1) { return assert(false, "cpp2 pixel (2,1)"); }
  if (xpm_symbol_index(&img, "ab") != 1) { return assert(false, "cpp2 symbol ab"); }
  if (!streq(xpm_symbol_at(&img, 2), "ba")) { return assert(false, "cpp2 symbol_at ba"); }
  if (!streq(xpm_color_at(&img, 1), "#00ff00")) { return assert(false, "cpp2 color 1"); }
  let text = ok_bytes(xpm_build("hot", &img));
  if (!vec_is_str(text, "/* XPM */\nstatic char * hot[] = {\n\"3 2 3 2 1 1\",\n\"aa\tc #ff0000\",\n\"ab\tc #00ff00\",\n\"ba\tc #0000ff\",\n\"aaabaa\",\n\"baaaab\"\n};\n")) {
    return assert(false, "canonical cpp2 hotspot build");
  }
  let img2 = ok_img(xpm_parse(text));
  if (xpm_hotspot_x(&img2) != 1) { return assert(false, "round-trip hotspot x"); }
  if (xpm_hotspot_y(&img2) != 1) { return assert(false, "round-trip hotspot y"); }
  if (xpm_pixel_index(&img2, 2, 1) != 1) { return assert(false, "round-trip pixel"); }
  if (!streq(xpm_color_at(&img2, 2), "#0000ff")) { return assert(false, "round-trip color"); }
  let text2 = ok_bytes(xpm_build("hot", &img2));
  if (!vec_eq(text, text2)) { return assert(false, "build-parse-build is byte-exact"); }
  return assert(true, "cpp greater than 1 with a hotspot round-trips through the canonical builder");
}

fn t5() -> TestResult {
  let img = ok_img(xpm_parse(basic_src()));
  if (xpm_has_hotspot(&img)) { return assert(false, "basic image has no hotspot"); }
  let text = ok_bytes(xpm_build_hotspot("sample", &img, 1, 0));
  if (!bytes_prefix_is(text, "/* XPM */\nstatic char * sample[] = {\n\"2 2 2 1 1 0\",")) {
    return assert(false, "hotspot header emitted");
  }
  let img2 = ok_img(xpm_parse(text));
  if (!xpm_has_hotspot(&img2)) { return assert(false, "hotspot added"); }
  if (xpm_hotspot_x(&img2) != 1) { return assert(false, "added hotspot x"); }
  if (xpm_hotspot_y(&img2) != 0) { return assert(false, "added hotspot y"); }
  if (xpm_pixel_index(&img2, 1, 1) != 0) { return assert(false, "hotspot build keeps pixels"); }
  let text2 = ok_bytes(xpm_build("sample", &img2));
  if (!bytes_prefix_is(text2, "/* XPM */\nstatic char * sample[] = {\n\"2 2 2 1 1 0\",")) {
    return assert(false, "xpm_build preserves hotspot");
  }
  if (!bytes_err_is(xpm_build_hotspot("sample", &img, 3, 0), "xpm: invalid hotspot")) {
    return assert(false, "hotspot x past width");
  }
  if (!bytes_err_is(xpm_build_hotspot("sample", &img, 0, 3), "xpm: invalid hotspot")) {
    return assert(false, "hotspot y past height");
  }
  if (!bytes_err_is(xpm_build_hotspot("sample", &img, -1, 0), "xpm: invalid hotspot")) {
    return assert(false, "negative hotspot");
  }
  let edge = ok_bytes(xpm_build_hotspot("sample", &img, 2, 2));
  let edge_img = ok_img(xpm_parse(edge));
  if (xpm_hotspot_x(&edge_img) != 2) { return assert(false, "hotspot equal to width"); }
  if (xpm_hotspot_y(&edge_img) != 2) { return assert(false, "hotspot equal to height"); }
  return assert(true, "xpm_build_hotspot adds, xpm_build preserves and bounds are enforced");
}

fn t6() -> TestResult {
  let src = xpm_src("3 1 3 1", ",\n\"a\\tc #000000\",\n\"b\\nc #ffffff\",\n\"\\\\ c #123456\",\n\"ab\\\\\"");
  let img = ok_img(xpm_parse(src));
  if (xpm_cpp(&img) != 1) { return assert(false, "escape fixture cpp 1"); }
  if (xpm_ncolors(&img) != 3) { return assert(false, "escape fixture ncolors 3"); }
  if (xpm_symbol_index(&img, "a") != 0) { return assert(false, "escaped tab separator"); }
  if (xpm_symbol_index(&img, "b") != 1) { return assert(false, "escaped LF separator"); }
  if (xpm_symbol_index(&img, "\\") != 2) { return assert(false, "escaped backslash symbol"); }
  if (!streq(xpm_symbol_at(&img, 2), "\\")) { return assert(false, "backslash symbol text"); }
  if (xpm_pixel_index(&img, 2, 0) != 2) { return assert(false, "backslash pixel"); }
  if (!streq(xpm_color_at(&img, 2), "#123456")) { return assert(false, "backslash color line"); }
  let bad1 = xpm_src("1 1 1 1", ",\n\"a c #000000\",\n\"\\z\"");
  if (!img_err_is(xpm_parse(bad1), "xpm: invalid escape")) { return assert(false, "unknown escape"); }
  let bad2 = xpm_src("1 1 1 1", ",\n\"a c #000000\",\n\"a\nb\"");
  if (!img_err_is(xpm_parse(bad2), "xpm: invalid character")) { return assert(false, "raw control byte"); }
  let bad3 = bytes_of("/* XPM */\nstatic char * s[] = {\n\"1 1 1 1");
  if (!img_err_is(xpm_parse(bad3), "xpm: unterminated string")) { return assert(false, "unterminated string"); }
  let bad4 = bytes_of("/* XPM */\nstatic char * s[] = {\n\"1 1 1 1\",\n\"a\\");
  if (!img_err_is(xpm_parse(bad4), "xpm: invalid escape")) { return assert(false, "trailing backslash"); }
  return assert(true, "backslash, quote, n and t escapes decode and bad escapes are rejected");
}

fn t7() -> TestResult {
  if (!img_err_is(xpm_parse(one_hdr("0 1 1 1")), "xpm: invalid width")) { return assert(false, "width 0"); }
  if (!img_err_is(xpm_parse(one_hdr("1000001 1 1 1")), "xpm: invalid width")) { return assert(false, "width cap"); }
  if (!img_err_is(xpm_parse(one_hdr("1234567890 1 1 1")), "xpm: invalid width")) { return assert(false, "10-digit width"); }
  if (!img_err_is(xpm_parse(one_hdr("1 0 1 1")), "xpm: invalid height")) { return assert(false, "height 0"); }
  if (!img_err_is(xpm_parse(one_hdr("1 1000001 1 1")), "xpm: invalid height")) { return assert(false, "height cap"); }
  if (!img_err_is(xpm_parse(one_hdr("1 1 0 1")), "xpm: invalid ncolors")) { return assert(false, "ncolors 0"); }
  if (!img_err_is(xpm_parse(one_hdr("1 1 4097 1")), "xpm: invalid ncolors")) { return assert(false, "ncolors cap"); }
  if (!img_err_is(xpm_parse(one_hdr("1 1 1 0")), "xpm: invalid cpp")) { return assert(false, "cpp 0"); }
  if (!img_err_is(xpm_parse(one_hdr("1 1 1 5")), "xpm: invalid cpp")) { return assert(false, "cpp 5"); }
  if (!img_err_is(xpm_parse(one_hdr("1 1 1")), "xpm: malformed header")) { return assert(false, "three tokens"); }
  if (!img_err_is(xpm_parse(one_hdr("1 1 1 1 0")), "xpm: malformed header")) { return assert(false, "five tokens"); }
  if (!img_err_is(xpm_parse(one_hdr("1 1 1 1 0 0 0")), "xpm: malformed header")) { return assert(false, "seven tokens"); }
  if (!img_err_is(xpm_parse(one_hdr("1 1 1 x")), "xpm: malformed header")) { return assert(false, "non-digit token"); }
  if (!img_err_is(xpm_parse(one_hdr("")), "xpm: malformed header")) { return assert(false, "empty header"); }
  if (!img_err_is(xpm_parse(one_hdr("1 1 1 1 2 0")), "xpm: invalid hotspot")) { return assert(false, "hotspot x past width"); }
  if (!img_err_is(xpm_parse(one_hdr("1 1 1 1 0 2")), "xpm: invalid hotspot")) { return assert(false, "hotspot y past height"); }
  let spaced = ok_img(xpm_parse(one_hdr("1  1\t1 1")));
  if (xpm_width(&spaced) != 1) { return assert(false, "extra whitespace in header"); }
  let hot_ok = ok_img(xpm_parse(one_hdr("1 1 1 1 1 1")));
  if (!xpm_has_hotspot(&hot_ok)) { return assert(false, "hotspot equal to the dimensions parses"); }
  if (xpm_hotspot_x(&hot_ok) != 1) { return assert(false, "parsed hotspot x"); }
  return assert(true, "value-line token counts, ranges and hotspot bounds are validated");
}

fn t8() -> TestResult {
  let d = xpm_src("1 1 1 1", ",\n\"a c #000000\",\n\"a\"");
  let img = ok_img(xpm_parse(d));
  if (xpm_pixel_index(&img, 0, 0) != 0) { return assert(false, "exact counts parse"); }
  let a = xpm_src("1 1 3 1", ",\n\"a c #000000\",\n\"b c #ffffff\"");
  if (!img_err_is(xpm_parse(a), "xpm: missing color lines")) { return assert(false, "fewer colors than ncolors"); }
  let b = xpm_src("1 2 2 1", ",\n\"a c #000000\",\n\"b c #ffffff\",\n\"a\"");
  if (!img_err_is(xpm_parse(b), "xpm: missing pixel rows")) { return assert(false, "fewer rows than height"); }
  let c = xpm_src("1 1 1 1", ",\n\"a c #000000\",\n\"a\",\n\"a\"");
  if (!img_err_is(xpm_parse(c), "xpm: trailing strings")) { return assert(false, "extra strings"); }
  return assert(true, "ncolors and height are checked against the number of strings");
}

fn t9() -> TestResult {
  let a = xpm_src("2 1 2 1", ",\n\"a c #000000\",\n\"b c #ffffff\",\n\"a\"");
  if (!img_err_is(xpm_parse(a), "xpm: row length mismatch")) { return assert(false, "row too short"); }
  let b = xpm_src("2 1 2 1", ",\n\"a c #000000\",\n\"b c #ffffff\",\n\"abc\"");
  if (!img_err_is(xpm_parse(b), "xpm: row length mismatch")) { return assert(false, "row too long"); }
  let c = xpm_src("2 1 2 1", ",\n\"a c #000000\",\n\"b c #ffffff\",\n\"ac\"");
  if (!img_err_is(xpm_parse(c), "xpm: unknown symbol")) { return assert(false, "unknown row symbol"); }
  return assert(true, "pixel rows must be width * cpp long and use known symbols");
}

fn t10() -> TestResult {
  let a = xpm_src("1 1 2 1", ",\n\"a c #000000\",\n\"a c #ffffff\",\n\"a\"");
  if (!img_err_is(xpm_parse(a), "xpm: duplicate symbol")) { return assert(false, "repeated symbol"); }
  let b = xpm_src("1 1 2 2", ",\n\"aa c #000000\",\n\"aa c #ffffff\",\n\"aa\"");
  if (!img_err_is(xpm_parse(b), "xpm: duplicate symbol")) { return assert(false, "repeated 2-char symbol"); }
  return assert(true, "duplicate color symbols are rejected for cpp 1 and cpp 2");
}

fn t11() -> TestResult {
  if (!img_err_is(xpm_parse(xpm_src("1 1 1 1", ",\n\"a b #ffffff\",\n\"a\"")), "xpm: malformed color line")) {
    return assert(false, "missing c key");
  }
  if (!img_err_is(xpm_parse(xpm_src("1 1 1 1", ",\n\"ac #ffffff\",\n\"a\"")), "xpm: malformed color line")) {
    return assert(false, "missing separator before c");
  }
  if (!img_err_is(xpm_parse(xpm_src("1 1 1 1", ",\n\"a c \",\n\"a\"")), "xpm: malformed color line")) {
    return assert(false, "missing value");
  }
  if (!img_err_is(xpm_parse(xpm_src("1 1 1 1", ",\n\"a c #gggggg\",\n\"a\"")), "xpm: malformed color value")) {
    return assert(false, "non-hex digits");
  }
  if (!img_err_is(xpm_parse(xpm_src("1 1 1 1", ",\n\"a c #fff\",\n\"a\"")), "xpm: malformed color value")) {
    return assert(false, "short hex");
  }
  if (!img_err_is(xpm_parse(xpm_src("1 1 1 1", ",\n\"a c #fffff\",\n\"a\"")), "xpm: malformed color value")) {
    return assert(false, "five hex digits");
  }
  if (!img_err_is(xpm_parse(xpm_src("1 1 1 1", ",\n\"a c #ffffffz\",\n\"a\"")), "xpm: malformed color value")) {
    return assert(false, "hex with trailing junk");
  }
  if (!img_err_is(xpm_parse(xpm_src("1 1 1 1", ",\n\"a c re#d\",\n\"a\"")), "xpm: malformed color value")) {
    return assert(false, "hash inside a name");
  }
  if (!img_err_is(xpm_parse(xpm_src("1 1 1 1", ",\n\"\tc #000000\",\n\"a\"")), "xpm: invalid symbol")) {
    return assert(false, "control byte as symbol");
  }
  return assert(true, "malformed color lines, values and symbol bytes are rejected");
}

fn t12() -> TestResult {
  if (!img_err_is(xpm_parse(bytes_of("char * s[] = {\n\"1 1 1 1\"\n};\n")), "xpm: malformed declaration")) {
    return assert(false, "missing static");
  }
  if (!img_err_is(xpm_parse(bytes_of("/* XPM */\nstatic int * s[] = {\n\"1 1 1 1\"\n};\n")), "xpm: malformed declaration")) {
    return assert(false, "wrong element type");
  }
  if (!img_err_is(xpm_parse(bytes_of("/* XPM */\nstatic char s[] = {\n\"1 1 1 1\"\n};\n")), "xpm: malformed declaration")) {
    return assert(false, "missing star");
  }
  if (!img_err_is(xpm_parse(bytes_of("/* XPM */\nstatic char * s = {\n\"1 1 1 1\"\n};\n")), "xpm: malformed declaration")) {
    return assert(false, "missing brackets");
  }
  if (!img_err_is(xpm_parse(bytes_of("/* XPM */\nstatic char * s[] {\n\"1 1 1 1\"\n};\n")), "xpm: malformed declaration")) {
    return assert(false, "missing equals");
  }
  if (!img_err_is(xpm_parse(bytes_of("/* XPM */\nstatic char * s[] = \n\"1 1 1 1\"\n};\n")), "xpm: malformed declaration")) {
    return assert(false, "missing brace");
  }
  if (!img_err_is(xpm_parse(bytes_of("/* XPM */\nstatic char * s[] = {\n\"1 1 1 1\",\n\"a c #000000\",\n\"a\"\n}\n")), "xpm: malformed declaration")) {
    return assert(false, "missing semicolon");
  }
  if (!img_err_is(xpm_parse(bytes_of("/* XPM */\nstatic char * s[] = {\n\"1 1 1 1\",\n")), "xpm: unclosed string list")) {
    return assert(false, "EOF in the list");
  }
  if (!img_err_is(xpm_parse(bytes_of("/* XPM */\nstatic char * s[] = {\n};\n")), "xpm: missing header")) {
    return assert(false, "empty list");
  }
  if (!img_err_is(xpm_parse(bytes_of("/* XPM */\nstatic char * s[] = {\n\"1 1 1 1\" \"a c #000000\"\n};\n")), "xpm: malformed declaration")) {
    return assert(false, "missing comma");
  }
  if (!img_err_is(xpm_parse(bytes_of("/* XPM */\nstatic char * s[] = {\n,\"1 1 1 1\"\n};\n")), "xpm: malformed declaration")) {
    return assert(false, "leading comma");
  }
  if (!img_err_is(xpm_parse(bytes_of("/* XPM */\nstatic char * s[] = {\n\"1 1 1 1\"\n};\ngarbage")), "xpm: trailing tokens")) {
    return assert(false, "garbage after the declaration");
  }
  if (!img_err_is(xpm_parse(bytes_of("/* XPM\nstatic char * s[] = {\n\"1 1 1 1\"\n};\n")), "xpm: unclosed comment")) {
    return assert(false, "unclosed comment");
  }
  if (!img_err_is(xpm_parse(bytes_of("/* XPM */\nstatic char * s[] = {\n\"1 1 1 1\",\n/* nope\n")), "xpm: unclosed comment")) {
    return assert(false, "unclosed comment in the list");
  }
  let trailing_ok = ok_img(xpm_parse(bytes_of("/* XPM */\nstatic char * s[] = {\n\"1 1 1 1\",\n\"a c #000000\",\n\"a\"\n}; /* done */ \n\t ")));
  if (xpm_pixel_index(&trailing_ok, 0, 0) != 0) { return assert(false, "trailing trivia is accepted"); }
  return assert(true, "declaration, string-list and trailing-token structure is enforced");
}

fn t13() -> TestResult {
  let one = img_one();
  if (!bytes_err_is(xpm_build("", &one), "xpm: invalid name")) { return assert(false, "empty name"); }
  if (!bytes_err_is(xpm_build("2bad", &one), "xpm: invalid name")) { return assert(false, "digit start"); }
  if (!bytes_err_is(xpm_build("bad-name", &one), "xpm: invalid name")) { return assert(false, "hyphen name"); }
  if (!bytes_err_is(xpm_build("bad name", &one), "xpm: invalid name")) { return assert(false, "space name"); }
  let w0 = img4(0, 1, 1, syms1(97), cols1("#000000"), lens1(7), Vec[Int].new());
  if (!bytes_err_is(xpm_build("ok", &w0), "xpm: invalid width")) { return assert(false, "builder width 0"); }
  let wcap = img4(1000001, 1, 1, syms1(97), cols1("#000000"), lens1(7), Vec[Int].new());
  if (!bytes_err_is(xpm_build("ok", &wcap), "xpm: invalid width")) { return assert(false, "builder width cap"); }
  let h0 = img4(1, 0, 1, syms1(97), cols1("#000000"), lens1(7), Vec[Int].new());
  if (!bytes_err_is(xpm_build("ok", &h0), "xpm: invalid height")) { return assert(false, "builder height 0"); }
  let c0 = img4(1, 1, 0, syms1(97), cols1("#000000"), lens1(7), pix1(0));
  if (!bytes_err_is(xpm_build("ok", &c0), "xpm: invalid cpp")) { return assert(false, "builder cpp 0"); }
  let c5 = img4(1, 1, 5, syms1(97), cols1("#000000"), lens1(7), pix1(0));
  if (!bytes_err_is(xpm_build("ok", &c5), "xpm: invalid cpp")) { return assert(false, "builder cpp 5"); }
  let n0 = img4(1, 1, 1, Vec[UInt8].new(), Vec[Str].new(), Vec[Int].new(), Vec[Int].new());
  if (!bytes_err_is(xpm_build("ok", &n0), "xpm: invalid ncolors")) { return assert(false, "builder ncolors 0"); }
  let s2 = img4(1, 1, 1, bytes_of("ab"), cols1("#000000"), lens1(7), pix1(0));
  if (!bytes_err_is(xpm_build("ok", &s2), "xpm: symbol pool size mismatch")) { return assert(false, "symbol pool size"); }
  let lm = img4(1, 1, 1, syms1(97), cols1("#000000"), Vec[Int].new(), pix1(0));
  if (!bytes_err_is(xpm_build("ok", &lm), "xpm: color table size mismatch")) { return assert(false, "color length size"); }
  let pm = img4(1, 1, 1, syms1(97), cols1("#000000"), lens1(7), Vec[Int].new());
  if (!bytes_err_is(xpm_build("ok", &pm), "xpm: pixel buffer size mismatch")) { return assert(false, "pixel buffer size"); }
  let p1 = img4(1, 1, 1, syms1(97), cols1("#000000"), lens1(7), pix1(1));
  if (!bytes_err_is(xpm_build("ok", &p1), "xpm: invalid pixel index")) { return assert(false, "pixel index bound"); }
  let pneg = img4(1, 1, 1, syms1(97), cols1("#000000"), lens1(7), pix1(-1));
  if (!bytes_err_is(xpm_build("ok", &pneg), "xpm: invalid pixel index")) { return assert(false, "negative pixel index"); }
  let sym2 = bytes_of("aa");
  let col2 = Vec[Str].new();
  col2.push("#111111");
  col2.push("#222222");
  let len2 = Vec[Int].new();
  len2.push(7);
  len2.push(7);
  let dup = img4(1, 1, 1, sym2, col2, len2, pix1(0));
  if (!bytes_err_is(xpm_build("ok", &dup), "xpm: duplicate symbol")) { return assert(false, "builder duplicate symbol"); }
  let bs = img4(1, 1, 1, syms1(9), cols1("#000000"), lens1(7), pix1(0));
  if (!bytes_err_is(xpm_build("ok", &bs), "xpm: invalid symbol")) { return assert(false, "builder invalid symbol"); }
  let bcv = img4(1, 1, 1, syms1(97), cols1("red x"), lens1(5), pix1(0));
  if (!bytes_err_is(xpm_build("ok", &bcv), "xpm: malformed color value")) { return assert(false, "builder bad name"); }
  let bch = img4(1, 1, 1, syms1(97), cols1("#fff"), lens1(4), pix1(0));
  if (!bytes_err_is(xpm_build("ok", &bch), "xpm: malformed color value")) { return assert(false, "builder bad hex"); }
  let bh = img_hot(1, 1, 1, syms1(97), cols1("#000000"), lens1(7), pix1(0), 5, 0);
  if (!bytes_err_is(xpm_build("ok", &bh), "xpm: invalid hotspot")) { return assert(false, "stored hotspot bound"); }
  if (!bytes_err_is(xpm_build_hotspot("ok", &one, 2, 0), "xpm: invalid hotspot")) { return assert(false, "builder hotspot bound"); }
  let good = ok_bytes(xpm_build("ok", &one));
  if (!bytes_prefix_is(good, "/* XPM */\nstatic char * ok[] = {")) { return assert(false, "valid build prefix"); }
  return assert(true, "the builder validates names, dimensions, arrays, symbols, colors, pixels and hotspots");
}

fn t14() -> TestResult {
  let img = ok_img(xpm_parse(basic_src()));
  let text = ok_bytes(xpm_build("sample", &img));
  if (!vec_is_str(text, "/* XPM */\nstatic char * sample[] = {\n\"2 2 2 1\",\n\" \tc #ffffff\",\n\"X\tc #000000\",\n\" X\",\n\"X \"\n};\n")) {
    return assert(false, "canonical 2x2 build literal");
  }
  let back = ok_img(xpm_parse(text));
  if (!streq(xpm_symbol_at(&back, 0), " ")) { return assert(false, "space symbol after rebuild"); }
  if (xpm_pixel_index(&back, 0, 1) != 1) { return assert(false, "pixels after rebuild"); }
  return assert(true, "the canonical cpp-1 build is byte-exact and reparses");
}

fn t15() -> TestResult {
  let syms = Vec[UInt8].new();
  syms.push(34 as UInt8);
  syms.push(92 as UInt8);
  let cols = Vec[Str].new();
  cols.push("#111111");
  cols.push("#222222");
  let clens = Vec[Int].new();
  clens.push(7);
  clens.push(7);
  let pix = Vec[Int].new();
  pix.push(0);
  pix.push(1);
  let img = img4(2, 1, 1, syms, cols, clens, pix);
  let text = ok_bytes(xpm_build("esc", &img));
  let bs: Str = "\\";
  let q: Str = "\"";
  let tab: Str = "\t";
  let want: Str = "/* XPM */\nstatic char * esc[] = {\n\"2 1 2 1\",\n\"" + bs + q + tab + "c #111111\",\n\"" + bs + bs + tab + "c #222222\",\n\"" + bs + q + bs + bs + "\"\n};\n";
  if (!vec_is_str(text, want)) { return assert(false, "escaped canonical bytes"); }
  let back = ok_img(xpm_parse(text));
  if (xpm_symbol_index(&back, q) != 0) { return assert(false, "quote symbol round-trips"); }
  if (xpm_symbol_index(&back, bs) != 1) { return assert(false, "backslash symbol round-trips"); }
  if (!streq(xpm_symbol_at(&back, 0), q)) { return assert(false, "quote symbol text"); }
  if (xpm_pixel_index(&back, 1, 0) != 1) { return assert(false, "backslash pixel"); }
  if (!streq(xpm_pixel_color(&back, 1, 0), "#222222")) { return assert(false, "backslash pixel color"); }
  return assert(true, "quote and backslash symbols are escaped on build and decoded on parse");
}

fn t16() -> TestResult {
  let img = ok_img(xpm_parse(basic_src()));
  if (!streq(xpm_symbol_at(&img, 9), "")) { return assert(false, "symbol_at out of range"); }
  if (xpm_pixel_index(&img, 1, 0) != 1) { return assert(false, "valid pixel still works"); }
  let no_syms = img4(1, 1, 1, Vec[UInt8].new(), cols1("#000000"), lens1(7), pix1(0));
  if (xpm_pixel_index(&no_syms, 0, 0) != -1) { return assert(false, "inconsistent pixel_index"); }
  if (!streq(xpm_pixel_color(&no_syms, 0, 0), "")) { return assert(false, "inconsistent pixel_color"); }
  if (xpm_symbol_index(&no_syms, "a") != -1) { return assert(false, "inconsistent symbol_index"); }
  if (!streq(xpm_symbol_at(&no_syms, 0), "")) { return assert(false, "inconsistent symbol_at"); }
  let no_pix = img4(1, 1, 1, syms1(97), cols1("#000000"), lens1(7), Vec[Int].new());
  if (xpm_pixel_index(&no_pix, 0, 0) != -1) { return assert(false, "missing pixel buffer"); }
  let bad_cpp = img4(1, 1, 9, syms1(97), cols1("#000000"), lens1(7), pix1(0));
  if (xpm_pixel_index(&bad_cpp, 0, 0) != -1) { return assert(false, "inconsistent cpp"); }
  return assert(true, "accessors return sentinels for inconsistent images and bad indices");
}

fn t17() -> TestResult {
  let src = bytes_of("/* XPM */\r\nstatic char * s[] = {\r\n\"1 1 1 1\" , \r\n\"a   c    #000000\" ,\r\n\"a\" ,\r\n};\r\n");
  let img = ok_img(xpm_parse(src));
  if (!streq(xpm_color_at(&img, 0), "#000000")) { return assert(false, "CRLF and spacing color"); }
  if (xpm_pixel_index(&img, 0, 0) != 0) { return assert(false, "CRLF pixel"); }
  if (xpm_cpp(&img) != 1) { return assert(false, "CRLF cpp"); }
  if (!streq(xpm_symbol_at(&img, 0), "a")) { return assert(false, "CRLF symbol"); }
  return assert(true, "CRLF endings, spaces around commas and wide color-line gaps parse");
}

fn t18() -> TestResult {
  let src = xpm_src("1 1 1 4", ",\n\"abcd c #000000\",\n\"abcd\"");
  let img = ok_img(xpm_parse(src));
  if (xpm_cpp(&img) != 4) { return assert(false, "cpp 4"); }
  if (xpm_ncolors(&img) != 1) { return assert(false, "single color"); }
  if (xpm_symbol_index(&img, "abcd") != 0) { return assert(false, "4-char symbol"); }
  if (xpm_symbol_index(&img, "abc") != -1) { return assert(false, "short symbol"); }
  if (xpm_symbol_index(&img, "abce") != -1) { return assert(false, "wrong symbol"); }
  if (!streq(xpm_symbol_at(&img, 0), "abcd")) { return assert(false, "symbol_at 4 chars"); }
  if (!streq(xpm_pixel_color(&img, 0, 0), "#000000")) { return assert(false, "cpp4 pixel color"); }
  let text = ok_bytes(xpm_build("one", &img));
  let back = ok_img(xpm_parse(text));
  if (xpm_symbol_index(&back, "abcd") != 0) { return assert(false, "cpp4 round trip"); }
  return assert(true, "cpp 4 with one color parses, builds and round-trips");
}

fn t19() -> TestResult {
  let src = Vec[UInt8].new();
  let head = bytes_of("/* XPM */\nstatic char * big[] = {\n\"1000000 1 1 1\",\n\"a c #000000\",\n\"");
  var i = 0;
  while (i < head.len()) {
    let b: UInt8 = head[i];
    src.push(b);
    i = i + 1;
  }
  i = 0;
  while (i < 1000000) {
    src.push(97 as UInt8);
    i = i + 1;
  }
  let tail = bytes_of("\"\n};\n");
  i = 0;
  while (i < tail.len()) {
    let b: UInt8 = tail[i];
    src.push(b);
    i = i + 1;
  }
  let img = ok_img(xpm_parse(src));
  if (xpm_width(&img) != 1000000) { return assert(false, "cap width parses"); }
  if (xpm_height(&img) != 1) { return assert(false, "cap height 1"); }
  if (xpm_pixel_index(&img, 999999, 0) != 0) { return assert(false, "last cap pixel"); }
  if (xpm_pixel_index(&img, 1000000, 0) != -1) { return assert(false, "one past the cap"); }
  if (!img_err_is(xpm_parse(one_hdr("1000001 1 1 1")), "xpm: invalid width")) { return assert(false, "cap plus one"); }
  return assert(true, "the 1000000 width cap is accepted and 1000001 is rejected");
}

fn main() -> Int {
  io.println("=== xiom.xpm conformance tests ===");
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
  if failed == 0 {
    io.println("xiom.xpm: all tests passed");
  } else {
    io.println("xiom.xpm: tests failed");
  }
  return failed;
}
