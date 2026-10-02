// XIOM -- xiom.image conformance tests (24 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Deterministic, file-free fixtures: every image is built in memory (tiny
// hand-assembled headers and encoder output), so the suite needs no external
// assets. Result extraction helpers bind payloads to locals before passing
// them to &Vec parameters (v0.62.2 trap 4).

module image_tests
use xiom.io; use xiom.test; use xiom.image;

// --------------------------------------------------
//  Result extraction and comparison helpers
// --------------------------------------------------

fn extract_image(r: Result[RgbaImage, Str]) -> RgbaImage {
  match r {
    Ok(v) => { return v; },
    Err(e) => { return RgbaImage{ width: 0; height: 0; stride: 0; pixels: Vec[UInt8].new(); }; },
  }
}

fn extract_bytes(r: Result[Vec[UInt8], Str]) -> Vec[UInt8] {
  match r {
    Ok(v) => { return v; },
    Err(e) => { return Vec[UInt8].new(); },
  }
}

fn is_bad_image(r: Result[RgbaImage, Str]) -> Bool {
  match r {
    Ok(v) => { return false; },
    Err(e) => { return true; },
  }
}

fn is_bad_bytes(r: Result[Vec[UInt8], Str]) -> Bool {
  match r {
    Ok(v) => { return false; },
    Err(e) => { return true; },
  }
}

fn is_bad_meta(r: Result[ImageMeta, Str]) -> Bool {
  match r {
    Ok(v) => { return false; },
    Err(e) => { return true; },
  }
}

fn byte_at(v: &Vec[UInt8], i: Int) -> Int {
  return (v[i] as Int) & 0xFF;
}

fn bytes_eq(a: &Vec[UInt8], b: &Vec[UInt8]) -> Bool {
  if (a.len() != b.len()) { return false; }
  var i = 0;
  while (i < a.len()) {
    if (byte_at(a, i) != byte_at(b, i)) { return false; }
    i = i + 1;
  }
  return true;
}

fn rgba_eq(a: &RgbaImage, b: &RgbaImage) -> Bool {
  if (a.width != b.width || a.height != b.height) { return false; }
  var y = 0;
  while (y < a.height) {
    var x = 0;
    while (x < a.width) {
      if (image_get_rgba(a, x, y) != image_get_rgba(b, x, y)) { return false; }
      x = x + 1;
    }
    y = y + 1;
  }
  return true;
}

// --------------------------------------------------
//  Fixtures
// --------------------------------------------------

// Uniform width x height image.
fn mk(w: Int, h: Int, r: Int, g: Int, b: Int, a: Int) -> RgbaImage {
  return extract_image(image_new_rgba(w, h, r, g, b, a));
}

// 1x1 opaque pixel with distinct channels.
fn rgba_1x1(r: Int, g: Int, b: Int, a: Int) -> RgbaImage {
  return mk(1, 1, r, g, b, a);
}

// 2x1 with (7,8,9,255) and (10,11,12,255).
fn rgba_2x1() -> RgbaImage {
  let px = Vec[UInt8].new();
  px.push(7 as UInt8);
  px.push(8 as UInt8);
  px.push(9 as UInt8);
  px.push(255 as UInt8);
  px.push(10 as UInt8);
  px.push(11 as UInt8);
  px.push(12 as UInt8);
  px.push(255 as UInt8);
  return extract_image(image_from_rgba(2, 1, 8, px));
}

// 2x2 with four distinct opaque RGBA pixels (24-bit BMP and PPM drop alpha).
fn rgba_2x2() -> RgbaImage {
  let px = Vec[UInt8].new();
  px.push(10 as UInt8);
  px.push(20 as UInt8);
  px.push(30 as UInt8);
  px.push(255 as UInt8);
  px.push(40 as UInt8);
  px.push(50 as UInt8);
  px.push(60 as UInt8);
  px.push(255 as UInt8);
  px.push(70 as UInt8);
  px.push(80 as UInt8);
  px.push(90 as UInt8);
  px.push(255 as UInt8);
  px.push(100 as UInt8);
  px.push(110 as UInt8);
  px.push(120 as UInt8);
  px.push(255 as UInt8);
  return extract_image(image_from_rgba(2, 2, 8, px));
}

// The 8-byte PNG signature.
fn png_sig() -> Vec[UInt8] {
  let out = Vec[UInt8].new();
  out.push(137 as UInt8);
  out.push(80 as UInt8);
  out.push(78 as UInt8);
  out.push(71 as UInt8);
  out.push(13 as UInt8);
  out.push(10 as UInt8);
  out.push(26 as UInt8);
  out.push(10 as UInt8);
  return out;
}

// GIF89a + logical screen width/height (little-endian).
fn gif_header(w: Int, h: Int) -> Vec[UInt8] {
  let out = Vec[UInt8].new();
  out.push(71 as UInt8);
  out.push(73 as UInt8);
  out.push(70 as UInt8);
  out.push(56 as UInt8);
  out.push(57 as UInt8);
  out.push(97 as UInt8);
  out.push((w % 256) as UInt8);
  out.push(((w / 256) % 256) as UInt8);
  out.push((h % 256) as UInt8);
  out.push(((h / 256) % 256) as UInt8);
  return out;
}

// 18-byte uncompressed true-color TGA header, 24 bpp.
fn tga_header(w: Int, h: Int) -> Vec[UInt8] {
  let out = Vec[UInt8].new();
  out.push(0 as UInt8);
  out.push(0 as UInt8);
  out.push(2 as UInt8);
  out.push(0 as UInt8);
  out.push(0 as UInt8);
  out.push(0 as UInt8);
  out.push(0 as UInt8);
  out.push(0 as UInt8);
  out.push(0 as UInt8);
  out.push(0 as UInt8);
  out.push(0 as UInt8);
  out.push(0 as UInt8);
  out.push((w % 256) as UInt8);
  out.push(((w / 256) % 256) as UInt8);
  out.push((h % 256) as UInt8);
  out.push(((h / 256) % 256) as UInt8);
  out.push(24 as UInt8);
  out.push(0 as UInt8);
  return out;
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  var ok = image_format_name(IMG_FMT_BMP) == "bmp";
  if (image_format_name(IMG_FMT_PNG) != "png") { ok = false; }
  if (image_format_name(IMG_FMT_JPEG) != "jpeg") { ok = false; }
  if (image_format_name(IMG_FMT_GIF) != "gif") { ok = false; }
  if (image_format_name(IMG_FMT_PPM) != "ppm") { ok = false; }
  if (image_format_name(IMG_FMT_TGA) != "tga") { ok = false; }
  if (image_format_name(IMG_FMT_UNKNOWN) != "unknown") { ok = false; }
  return assert(ok, "format names for all six formats and unknown");
}

fn t2() -> TestResult {
  let im = mk(1, 1, 10, 20, 30, 255);
  let enc = image_encode_bmp24(&im);
  match enc {
    Ok(bytes) => {
      if (image_sniff(&bytes) != IMG_FMT_BMP) { return assert(false, "sniff encoded bmp24"); }
    },
    Err(e) => { return assert(false, "bmp24 encode for sniff"); },
  }
  return assert(true, "sniff recognizes an encoded BMP from magic bytes");
}

fn t3() -> TestResult {
  let d = png_sig();
  d.push(0 as UInt8);
  d.push(0 as UInt8);
  d.push(0 as UInt8);
  d.push(13 as UInt8);
  d.push(73 as UInt8);
  d.push(72 as UInt8);
  d.push(68 as UInt8);
  d.push(82 as UInt8);
  d.push(0 as UInt8);
  d.push(0 as UInt8);
  d.push(0 as UInt8);
  d.push(5 as UInt8);
  d.push(0 as UInt8);
  d.push(0 as UInt8);
  d.push(0 as UInt8);
  d.push(7 as UInt8);
  d.push(8 as UInt8);
  d.push(6 as UInt8);
  d.push(0 as UInt8);
  d.push(0 as UInt8);
  d.push(0 as UInt8);
  if (image_sniff(&d) != IMG_FMT_PNG) { return assert(false, "png signature sniff"); }
  let m = image_meta(&d);
  match m {
    Ok(mm) => {
      if (mm.width != 5 || mm.height != 7) { return assert(false, "png ihdr dimensions"); }
      if (mm.format != IMG_FMT_PNG || mm.bits != 8) { return assert(false, "png meta format and bits"); }
    },
    Err(e) => { return assert(false, "png meta parse"); },
  }
  return assert(true, "PNG signature sniffed and IHDR metadata extracted");
}

fn t4() -> TestResult {
  let d = Vec[UInt8].new();
  d.push(255 as UInt8);
  d.push(216 as UInt8);
  d.push(255 as UInt8);
  if (image_sniff(&d) != IMG_FMT_JPEG) { return assert(false, "jpeg soi sniff"); }
  d.push(224 as UInt8);
  d.push(0 as UInt8);
  d.push(16 as UInt8);
  var i = 0;
  while (i < 14) {
    d.push(0 as UInt8);
    i = i + 1;
  }
  d.push(255 as UInt8);
  d.push(192 as UInt8);
  d.push(0 as UInt8);
  d.push(17 as UInt8);
  d.push(8 as UInt8);
  d.push(0 as UInt8);
  d.push(2 as UInt8);
  d.push(0 as UInt8);
  d.push(3 as UInt8);
  d.push(3 as UInt8);
  i = 0;
  while (i < 9) {
    d.push(0 as UInt8);
    i = i + 1;
  }
  if (image_sniff(&d) != IMG_FMT_JPEG) { return assert(false, "jpeg sniff with segments"); }
  let m = image_meta(&d);
  match m {
    Ok(mm) => {
      if (mm.width != 3 || mm.height != 2) { return assert(false, "jpeg sof dimensions"); }
      if (mm.format != IMG_FMT_JPEG || mm.bits != 8) { return assert(false, "jpeg meta format and bits"); }
    },
    Err(e) => { return assert(false, "jpeg sof scan"); },
  }
  return assert(true, "JPEG sniffed and SOF0 dimensions extracted");
}

fn t5() -> TestResult {
  let d = gif_header(4, 3);
  if (image_sniff(&d) != IMG_FMT_GIF) { return assert(false, "gif sniff"); }
  let m = image_meta(&d);
  match m {
    Ok(mm) => {
      if (mm.width != 4 || mm.height != 3) { return assert(false, "gif dimensions"); }
      if (mm.format != IMG_FMT_GIF || mm.bits != 8) { return assert(false, "gif meta format and bits"); }
    },
    Err(e) => { return assert(false, "gif meta parse"); },
  }
  return assert(true, "GIF89a sniffed and logical screen size extracted");
}

fn t6() -> TestResult {
  let im = rgba_2x1();
  let enc = image_encode_ppm(&im);
  match enc {
    Ok(bytes) => {
      if (image_sniff(&bytes) != IMG_FMT_PPM) { return assert(false, "ppm sniff"); }
      let m = image_meta(&bytes);
      match m {
        Ok(mm) => {
          if (mm.width != 2 || mm.height != 1) { return assert(false, "ppm meta dimensions"); }
          if (mm.format != IMG_FMT_PPM || mm.bits != 8) { return assert(false, "ppm meta format and bits"); }
        },
        Err(e) => { return assert(false, "ppm meta parse"); },
      }
      let dec = extract_image(image_decode(&bytes));
      if (!rgba_eq(&im, &dec)) { return assert(false, "ppm decode round trip"); }
    },
    Err(e) => { return assert(false, "ppm encode"); },
  }
  return assert(true, "PPM sniff, metadata and round trip through image_decode");
}

fn t7() -> TestResult {
  let d = tga_header(3, 2);
  if (image_sniff(&d) != IMG_FMT_TGA) { return assert(false, "tga header sniff"); }
  let m = image_meta(&d);
  match m {
    Ok(mm) => {
      if (mm.width != 3 || mm.height != 2) { return assert(false, "tga dimensions"); }
      if (mm.format != IMG_FMT_TGA || mm.bits != 24) { return assert(false, "tga meta format and bits"); }
    },
    Err(e) => { return assert(false, "tga meta parse"); },
  }
  let z = Vec[UInt8].new();
  var i = 0;
  while (i < 18) {
    z.push(0 as UInt8);
    i = i + 1;
  }
  if (image_sniff(&z) == IMG_FMT_TGA) { return assert(false, "all-zero header is not tga"); }
  return assert(true, "TGA heuristic sniff and header metadata");
}

fn t8() -> TestResult {
  let empty = Vec[UInt8].new();
  if (image_sniff(&empty) != IMG_FMT_UNKNOWN) { return assert(false, "empty is unknown"); }
  let junk = Vec[UInt8].new();
  junk.push(104 as UInt8);
  junk.push(101 as UInt8);
  junk.push(108 as UInt8);
  junk.push(108 as UInt8);
  junk.push(111 as UInt8);
  if (image_sniff(&junk) != IMG_FMT_UNKNOWN) { return assert(false, "text is unknown"); }
  if (!is_bad_meta(image_meta(&junk))) { return assert(false, "unknown metadata is an error"); }
  return assert(true, "unknown buffers sniff as IMG_FMT_UNKNOWN and meta fails");
}

fn t9() -> TestResult {
  let im = rgba_2x2();
  let enc = image_encode_bmp24(&im);
  match enc {
    Ok(bytes) => {
      if (image_sniff(&bytes) != IMG_FMT_BMP) { return assert(false, "bmp24 sniff"); }
      let dec = extract_image(image_decode(&bytes));
      if (!rgba_eq(&im, &dec)) { return assert(false, "bmp24 round trip pixels"); }
    },
    Err(e) => { return assert(false, "bmp24 encode"); },
  }
  return assert(true, "BMP 24-bit round trip through the unified decode pipeline");
}

fn t10() -> TestResult {
  let px = Vec[UInt8].new();
  px.push(5 as UInt8);
  px.push(6 as UInt8);
  px.push(7 as UInt8);
  px.push(8 as UInt8);
  px.push(9 as UInt8);
  px.push(10 as UInt8);
  px.push(11 as UInt8);
  px.push(12 as UInt8);
  let im = extract_image(image_from_rgba(1, 2, 4, px));
  let enc = image_encode_bmp32(&im);
  match enc {
    Ok(bytes) => {
      let dec = extract_image(image_decode(&bytes));
      if (!rgba_eq(&im, &dec)) { return assert(false, "bmp32 round trip keeps alpha"); }
    },
    Err(e) => { return assert(false, "bmp32 encode"); },
  }
  return assert(true, "BMP 32-bit round trip preserves low alpha values");
}

fn t11() -> TestResult {
  let px = Vec[UInt8].new();
  px.push(10 as UInt8);
  px.push(20 as UInt8);
  px.push(30 as UInt8);
  px.push(255 as UInt8);
  px.push(40 as UInt8);
  px.push(50 as UInt8);
  px.push(60 as UInt8);
  px.push(255 as UInt8);
  let im = extract_image(image_from_rgba(1, 2, 4, px));
  let bytes = extract_bytes(image_encode_bmp24(&im));
  if (bytes.len() != 62) { return assert(false, "bmp24 file size for 1x2"); }
  if (byte_at(&bytes, 2) != 62) { return assert(false, "file size field"); }
  if (byte_at(&bytes, 18) != 1) { return assert(false, "width field"); }
  if (byte_at(&bytes, 22) != 2) { return assert(false, "height field"); }
  if (byte_at(&bytes, 28) != 24) { return assert(false, "bits field"); }
  if (byte_at(&bytes, 54) != 60) { return assert(false, "bottom row B first"); }
  if (byte_at(&bytes, 55) != 50) { return assert(false, "bottom row G"); }
  if (byte_at(&bytes, 56) != 40) { return assert(false, "bottom row R"); }
  if (byte_at(&bytes, 57) != 0) { return assert(false, "row pad zero"); }
  if (byte_at(&bytes, 58) != 30) { return assert(false, "top row B"); }
  if (byte_at(&bytes, 59) != 20) { return assert(false, "top row G"); }
  if (byte_at(&bytes, 60) != 10) { return assert(false, "top row R"); }
  if (byte_at(&bytes, 61) != 0) { return assert(false, "final pad zero"); }
  return assert(true, "BMP 24-bit canonical header and bottom-up padded rows");
}

fn t12() -> TestResult {
  let im = rgba_1x1(200, 100, 50, 255);
  var bytes = extract_bytes(image_encode_bmp24(&im));
  bytes[22] = 255 as UInt8;
  bytes[23] = 255 as UInt8;
  bytes[24] = 255 as UInt8;
  bytes[25] = 255 as UInt8;
  let hp = image_bmp_header(&bytes);
  match hp {
    Ok(h) => {
      if (h.height != -1) { return assert(false, "negative height parsed"); }
    },
    Err(e) => { return assert(false, "negative height header"); },
  }
  let dec = extract_image(image_decode(&bytes));
  if (!rgba_eq(&im, &dec)) { return assert(false, "top-down decode pixels"); }
  return assert(true, "negative-height top-down BMP parses and decodes");
}

fn t13() -> TestResult {
  let im = rgba_2x1();
  let bytes = extract_bytes(image_encode_ppm(&im));
  if (bytes.len() != 17) { return assert(false, "ppm size"); }
  if (byte_at(&bytes, 0) != 80 || byte_at(&bytes, 1) != 54) { return assert(false, "ppm magic"); }
  if (byte_at(&bytes, 2) != 10) { return assert(false, "ppm magic newline"); }
  if (byte_at(&bytes, 3) != 50 || byte_at(&bytes, 4) != 32 || byte_at(&bytes, 5) != 49) {
    return assert(false, "ppm dimensions");
  }
  if (byte_at(&bytes, 6) != 10) { return assert(false, "ppm dims newline"); }
  if (byte_at(&bytes, 7) != 50 || byte_at(&bytes, 8) != 53 || byte_at(&bytes, 9) != 53 || byte_at(&bytes, 10) != 10) {
    return assert(false, "ppm maxval");
  }
  if (byte_at(&bytes, 11) != 7 || byte_at(&bytes, 12) != 8 || byte_at(&bytes, 13) != 9) {
    return assert(false, "ppm first pixel");
  }
  if (byte_at(&bytes, 14) != 10 || byte_at(&bytes, 15) != 11 || byte_at(&bytes, 16) != 12) {
    return assert(false, "ppm second pixel");
  }
  return assert(true, "PPM P6 canonical header and RGB raster bytes");
}

fn t14() -> TestResult {
  let im = rgba_2x2();
  let enc = image_encode(&im, IMG_ENC_PPM);
  match enc {
    Ok(bytes) => {
      let dec = extract_image(image_decode(&bytes));
      if (!rgba_eq(&im, &dec)) { return assert(false, "ppm unified round trip"); }
    },
    Err(e) => { return assert(false, "ppm unified encode"); },
  }
  let px = Vec[UInt8].new();
  let broken = extract_image(image_from_rgba(1, 1, 4, px));
  if (!is_bad_bytes(image_encode(&broken, IMG_ENC_PPM))) { return assert(false, "empty image rejected"); }
  if (!is_bad_bytes(image_encode(&im, 99))) { return assert(false, "unknown encode target rejected"); }
  return assert(true, "unified encode dispatch and invalid target rejection");
}

fn t15() -> TestResult {
  let d = png_sig();
  if (!is_bad_image(image_decode(&d))) { return assert(false, "png decode rejected"); }
  let j = Vec[UInt8].new();
  j.push(255 as UInt8);
  j.push(216 as UInt8);
  j.push(255 as UInt8);
  if (!is_bad_image(image_decode(&j))) { return assert(false, "jpeg decode rejected"); }
  let empty = Vec[UInt8].new();
  if (!is_bad_image(image_decode(&empty))) { return assert(false, "empty decode rejected"); }
  return assert(true, "decode pipeline rejects non-proof formats");
}

fn t16() -> TestResult {
  let short = Vec[UInt8].new();
  short.push(66 as UInt8);
  short.push(77 as UInt8);
  var i = 0;
  while (i < 18) {
    short.push(0 as UInt8);
    i = i + 1;
  }
  if (!is_bad_image(image_decode_bmp(&short))) { return assert(false, "truncated bmp header"); }
  let im = rgba_1x1(1, 2, 3, 255);
  var bad = extract_bytes(image_encode_bmp24(&im));
  bad[0] = 88 as UInt8;
  if (!is_bad_image(image_decode_bmp(&bad))) { return assert(false, "bad bmp magic"); }
  return assert(true, "BMP truncated header and bad magic rejected");
}

fn t17() -> TestResult {
  let im = mk(2, 1, 1, 2, 3, 255);
  var d16 = extract_bytes(image_encode_bmp24(&im));
  d16[28] = 16 as UInt8;
  d16[29] = 0 as UInt8;
  if (!is_bad_image(image_decode_bmp(&d16))) { return assert(false, "unsupported depth rejected"); }
  var dcomp = extract_bytes(image_encode_bmp24(&im));
  dcomp[30] = 1 as UInt8;
  if (!is_bad_image(image_decode_bmp(&dcomp))) { return assert(false, "compression rejected"); }
  var dw = extract_bytes(image_encode_bmp24(&im));
  dw[18] = 0 as UInt8;
  dw[19] = 0 as UInt8;
  dw[20] = 0 as UInt8;
  dw[21] = 0 as UInt8;
  if (!is_bad_image(image_decode_bmp(&dw))) { return assert(false, "zero width rejected"); }
  let full = extract_bytes(image_encode_bmp24(&im));
  let cut = Vec[UInt8].new();
  var i = 0;
  while (i < 58) {
    let fb: UInt8 = full[i];
    cut.push(fb);
    i = i + 1;
  }
  if (!is_bad_image(image_decode_bmp(&cut))) { return assert(false, "truncated raster rejected"); }
  return assert(true, "BMP depth, compression, dimensions and raster bounds checked");
}

fn t18() -> TestResult {
  let im = mk(3, 2, 4, 5, 6, 255);
  let bytes = extract_bytes(image_encode_bmp24(&im));
  let m = image_meta(&bytes);
  match m {
    Ok(mm) => {
      if (mm.width != 3 || mm.height != 2) { return assert(false, "bmp meta dimensions"); }
      if (mm.format != IMG_FMT_BMP || mm.bits != 24) { return assert(false, "bmp meta format and bits"); }
    },
    Err(e) => { return assert(false, "bmp meta parse"); },
  }
  return assert(true, "BMP metadata width, height, bits and format");
}

fn t19() -> TestResult {
  let im = rgba_1x1(9, 8, 7, 6);
  let bytes = extract_bytes(image_encode_bmp32(&im));
  if (bytes.len() != 58) { return assert(false, "bmp32 size"); }
  if (byte_at(&bytes, 28) != 32) { return assert(false, "bmp32 bits field"); }
  if (byte_at(&bytes, 54) != 7 || byte_at(&bytes, 55) != 8 || byte_at(&bytes, 56) != 9 || byte_at(&bytes, 57) != 6) {
    return assert(false, "bmp32 bgra byte order");
  }
  let hp = image_bmp_header(&bytes);
  match hp {
    Ok(h) => {
      if (h.bits != 32 || h.row_bytes != 4) { return assert(false, "bmp32 header fields"); }
    },
    Err(e) => { return assert(false, "bmp32 header parse"); },
  }
  return assert(true, "BMP 32-bit header and BGRA byte order");
}

fn t20() -> TestResult {
  let px = Vec[UInt8].new();
  px.push(1 as UInt8);
  px.push(2 as UInt8);
  px.push(3 as UInt8);
  px.push(255 as UInt8);
  px.push(4 as UInt8);
  px.push(5 as UInt8);
  px.push(6 as UInt8);
  px.push(255 as UInt8);
  px.push(7 as UInt8);
  px.push(8 as UInt8);
  px.push(9 as UInt8);
  px.push(255 as UInt8);
  let im = extract_image(image_from_rgba(3, 1, 12, px));
  let bytes = extract_bytes(image_encode_bmp24(&im));
  if (bytes.len() != 66) { return assert(false, "padded bmp size"); }
  let hp = image_bmp_header(&bytes);
  match hp {
    Ok(h) => {
      if (h.row_bytes != 12) { return assert(false, "row stride 12"); }
    },
    Err(e) => { return assert(false, "padded header parse"); },
  }
  let dec = extract_image(image_decode_bmp(&bytes));
  if (!rgba_eq(&im, &dec)) { return assert(false, "padded bmp round trip"); }
  return assert(true, "BMP 3px-wide row pads to a 12-byte stride and round trips");
}

fn t21() -> TestResult {
  let px = Vec[UInt8].new();
  px.push(1 as UInt8);
  px.push(2 as UInt8);
  px.push(3 as UInt8);
  px.push(4 as UInt8);
  px.push(5 as UInt8);
  px.push(6 as UInt8);
  px.push(7 as UInt8);
  px.push(8 as UInt8);
  var i = 0;
  while (i < 4) {
    px.push(200 as UInt8);
    i = i + 1;
  }
  px.push(9 as UInt8);
  px.push(10 as UInt8);
  px.push(11 as UInt8);
  px.push(12 as UInt8);
  px.push(13 as UInt8);
  px.push(14 as UInt8);
  px.push(15 as UInt8);
  px.push(16 as UInt8);
  i = 0;
  while (i < 4) {
    px.push(201 as UInt8);
    i = i + 1;
  }
  let im = extract_image(image_from_rgba(2, 2, 12, px));
  if (image_stride(&im) != 12) { return assert(false, "explicit stride kept"); }
  let rgb = image_rgba_to_rgb(&im);
  if (rgb.len() != 12) { return assert(false, "rgb size"); }
  if (byte_at(&rgb, 0) != 1 || byte_at(&rgb, 1) != 2 || byte_at(&rgb, 2) != 3) { return assert(false, "rgb pixel 0"); }
  if (byte_at(&rgb, 3) != 5 || byte_at(&rgb, 4) != 6 || byte_at(&rgb, 5) != 7) { return assert(false, "rgb pixel 1"); }
  if (byte_at(&rgb, 6) != 9 || byte_at(&rgb, 7) != 10 || byte_at(&rgb, 8) != 11) { return assert(false, "rgb pixel 2"); }
  if (byte_at(&rgb, 9) != 13 || byte_at(&rgb, 10) != 14 || byte_at(&rgb, 11) != 15) { return assert(false, "rgb pixel 3"); }
  let one = rgba_1x1(1, 2, 3, 4);
  let bgra = image_rgba_to_bgra(&one);
  if (bgra.len() != 4) { return assert(false, "bgra size"); }
  if (byte_at(&bgra, 0) != 3 || byte_at(&bgra, 1) != 2 || byte_at(&bgra, 2) != 1 || byte_at(&bgra, 3) != 4) {
    return assert(false, "bgra channel order");
  }
  return assert(true, "RGBA to RGB compacts stride; RGBA to BGRA swaps channels");
}

fn t22() -> TestResult {
  let rgb = Vec[UInt8].new();
  rgb.push(10 as UInt8);
  rgb.push(20 as UInt8);
  rgb.push(30 as UInt8);
  rgb.push(40 as UInt8);
  rgb.push(50 as UInt8);
  rgb.push(60 as UInt8);
  let r1 = image_rgb_to_rgba(&rgb, 2, 1, 200);
  match r1 {
    Ok(im) => {
      if (image_get_rgba(&im, 0, 0) != 10 * 16777216 + 20 * 65536 + 30 * 256 + 200) {
        return assert(false, "rgb to rgba pixel 0");
      }
      if (image_get_rgba(&im, 1, 0) != 40 * 16777216 + 50 * 65536 + 60 * 256 + 200) {
        return assert(false, "rgb to rgba pixel 1");
      }
      if (image_stride(&im) != 8) { return assert(false, "rgb to rgba stride"); }
    },
    Err(e) => { return assert(false, "rgb to rgba"); },
  }
  if (!is_bad_image(image_rgb_to_rgba(&rgb, 3, 1, 255))) { return assert(false, "rgb size mismatch"); }
  let gray = Vec[UInt8].new();
  gray.push(0 as UInt8);
  gray.push(255 as UInt8);
  let r2 = image_gray_to_rgba(&gray, 2, 1);
  match r2 {
    Ok(im) => {
      if (image_get_rgba(&im, 0, 0) != 255) { return assert(false, "gray 0 is opaque black"); }
      if (image_get_rgba(&im, 1, 0) != 255 * 16777216 + 255 * 65536 + 255 * 256 + 255) {
        return assert(false, "gray 255 is opaque white");
      }
    },
    Err(e) => { return assert(false, "gray to rgba"); },
  }
  return assert(true, "RGB and gray expand to opaque packed RGBA");
}

fn t23() -> TestResult {
  let red = image_rgba_to_gray(&rgba_1x1(255, 0, 0, 255));
  if (red.len() != 1 || byte_at(&red, 0) != 77) { return assert(false, "red luma 77"); }
  let green = image_rgba_to_gray(&rgba_1x1(0, 255, 0, 255));
  if (byte_at(&green, 0) != 149) { return assert(false, "green luma 149"); }
  let blue = image_rgba_to_gray(&rgba_1x1(0, 0, 255, 255));
  if (byte_at(&blue, 0) != 29) { return assert(false, "blue luma 29"); }
  let white = image_rgba_to_gray(&rgba_1x1(255, 255, 255, 255));
  if (byte_at(&white, 0) != 255) { return assert(false, "white luma 255"); }
  let black = image_rgba_to_gray(&rgba_1x1(0, 0, 0, 0));
  if (byte_at(&black, 0) != 0) { return assert(false, "black luma 0"); }
  return assert(true, "Rec.601 integer luma for primaries, white and black");
}

fn t24() -> TestResult {
  let im = rgba_2x2();
  let bgra = image_rgba_to_bgra(&im);
  let back = extract_image(image_bgra_to_rgba(&bgra, 2, 2));
  if (!rgba_eq(&im, &back)) { return assert(false, "bgra round trip"); }
  var e = mk(1, 1, 0, 0, 0, 0);
  let ok = image_set_rgba(&mut e, 0, 0, 250, 200, 100, 50);
  if (!ok) { return assert(false, "set pixel succeeds"); }
  if (image_get_rgba(&e, 0, 0) != 250 * 16777216 + 200 * 65536 + 100 * 256 + 50) {
    return assert(false, "set then get pixel");
  }
  if (image_set_rgba(&mut e, 1, 0, 0, 0, 0, 0)) { return assert(false, "out of range set fails"); }
  if (image_get_rgba(&e, 1, 0) != -1) { return assert(false, "out of range get is -1"); }
  return assert(true, "BGRA round trip and pixel set/get bounds");
}

// --------------------------------------------------
//  Runner
// --------------------------------------------------

fn main() -> Int {
  var failed = 0;

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
  let r21 = t21();
  if r21.passed { io.println("  [PASS] " + r21.name); } else { io.println("  [FAIL] " + r21.name); failed = failed + 1; }
  let r22 = t22();
  if r22.passed { io.println("  [PASS] " + r22.name); } else { io.println("  [FAIL] " + r22.name); failed = failed + 1; }
  let r23 = t23();
  if r23.passed { io.println("  [PASS] " + r23.name); } else { io.println("  [FAIL] " + r23.name); failed = failed + 1; }
  let r24 = t24();
  if r24.passed { io.println("  [PASS] " + r24.name); } else { io.println("  [FAIL] " + r24.name); failed = failed + 1; }

  if failed == 0 {
    io.println("xiom.image: all tests passed");
  } else {
    io.println("xiom.image: tests failed");
  }
  return failed;
}
