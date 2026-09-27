// XIOM -- xiom.webp conformance tests (20 checks)
// Port task: prove the pure-XIOM xiom.webp WebP (RIFF) container parser.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module webp_tests
use xiom.io; use xiom.test; use xiom.webp;
use xiom.string; use xiom.string.compare;
use xiom.convert;

// All Str equality goes through str_compare: `==` on a Str read from a
// Vec[Str] element is a pointer comparison in v0.61.3, so every expected
// message and every fourcc is compared with this helper.
fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn ok_img(r: Result[WebpImage, Str]) -> WebpImage {
  match r {
    Ok(v) => { return v; },
    Err(e) => { return empty_img(); },
  }
}

fn img_err_is(r: Result[WebpImage, Str], want: Str) -> Bool {
  match r {
    Ok(v) => { return false; },
    Err(e) => { return streq(e, want); },
  }
}

fn bad_img(r: Result[WebpImage, Str]) -> Bool {
  match r {
    Ok(v) => { return false; },
    Err(e) => { return true; },
  }
}

// Error message for an offset: "<base> at <off>".
fn at(base: Str, off: Int) -> Str {
  return base + " at " + convert.int_to_string(off);
}

// The dummy image returned by ok_img when a test unexpectedly hit an error.
fn empty_img() -> WebpImage {
  return WebpImage{
    kind: 0; size: 0; riff_size: 0; has_vp8x: 0; vp8x_offset: -1; flags: 0;
    flag_icc: 0; flag_alpha: 0; flag_exif: 0; flag_xmp: 0; flag_animation: 0;
    canvas_width: 0; canvas_height: 0; has_image: 0; image_format: 0;
    image_offset: -1; image_data_offset: -1; image_size: -1;
    image_width: 0; image_height: 0;
    vp8_version: -1; vp8_show_frame: -1; vp8_first_part_size: -1;
    vp8l_alpha: -1; vp8l_version: -1; has_alph: 0; alph_offset: -1;
    alph_size: -1; has_iccp: 0; iccp_offset: -1; iccp_size: -1; has_exif: 0;
    exif_offset: -1; exif_size: -1; has_xmp: 0; xmp_offset: -1; xmp_size: -1;
    has_anim: 0; anim_offset: -1; anim_background: 0; anim_loop_count: 0;
    chunk_fourcc: Vec[Str].new(); chunk_offset: Vec[Int].new();
    chunk_size: Vec[Int].new(); chunk_data_offset: Vec[Int].new();
    chunk_padding: Vec[Int].new(); chunk_kind: Vec[Int].new();
    frame_x: Vec[Int].new(); frame_y: Vec[Int].new(); frame_width: Vec[Int].new();
    frame_height: Vec[Int].new(); frame_duration: Vec[Int].new();
    frame_blend: Vec[Int].new(); frame_dispose: Vec[Int].new();
    frame_offset: Vec[Int].new(); frame_size: Vec[Int].new();
    frame_format: Vec[Int].new(); frame_data_offset: Vec[Int].new();
    frame_data_size: Vec[Int].new(); frame_has_alpha: Vec[Int].new();
    frame_nested_count: Vec[Int].new(); frame_unknown_count: Vec[Int].new();
  };
}

// --------------------------------------------------
//  Fixture builders (synthetic WebP byte buffers, no external files)
// --------------------------------------------------

fn push_fourcc(out: &mut Vec[UInt8], a: Int, b: Int, c: Int, d: Int) {
  out.push((a % 256) as UInt8);
  out.push((b % 256) as UInt8);
  out.push((c % 256) as UInt8);
  out.push((d % 256) as UInt8);
}

fn push_le16(out: &mut Vec[UInt8], v: Int) {
  out.push((v % 256) as UInt8);
  out.push(((v / 256) % 256) as UInt8);
}

fn push_le24(out: &mut Vec[UInt8], v: Int) {
  out.push((v % 256) as UInt8);
  out.push(((v / 256) % 256) as UInt8);
  out.push(((v / 65536) % 256) as UInt8);
}

fn push_le32(out: &mut Vec[UInt8], v: Int) {
  out.push((v % 256) as UInt8);
  out.push(((v / 256) % 256) as UInt8);
  out.push(((v / 65536) % 256) as UInt8);
  out.push(((v / 16777216) % 256) as UInt8);
}

fn push_bytes(out: &mut Vec[UInt8], v: &Vec[UInt8]) {
  var i = 0;
  while (i < v.len()) {
    out.push(v[i]);
    i = i + 1;
  }
}

// Deterministic payload of `n` bytes derived from `seed`.
fn raw_bytes(n: Int, seed: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while (i < n) {
    v.push(((seed + i) % 256) as UInt8);
    i = i + 1;
  }
  return v;
}

fn start_riff(out: &mut Vec[UInt8]) {
  push_fourcc(out, 82, 73, 70, 70);
  push_le32(out, 0);
  push_fourcc(out, 87, 69, 66, 80);
}

// Patch the RIFF size field (bytes 4..8) to `v`.
fn set_riff_size(out: &mut Vec[UInt8], v: Int) {
  out[4] = (v % 256) as UInt8;
  out[5] = ((v / 256) % 256) as UInt8;
  out[6] = ((v / 65536) % 256) as UInt8;
  out[7] = ((v / 16777216) % 256) as UInt8;
}

// Set the RIFF size field to the actual body length.
fn finish_riff(out: &mut Vec[UInt8]) {
  set_riff_size(out, out.len() - 8);
}

// Append one complete chunk: fourcc, LE32(payload length), payload and the
// zero padding byte when the payload length is odd.
fn push_chunk(out: &mut Vec[UInt8], a: Int, b: Int, c: Int, d: Int, payload: &Vec[UInt8]) {
  push_fourcc(out, a, b, c, d);
  push_le32(out, payload.len());
  push_bytes(out, payload);
  if (payload.len() % 2 != 0) { out.push(0 as UInt8); }
}

// Append one chunk header with an explicit declared size, then `payload`
// bytes (used to build malformed sizes).
fn push_chunk_sized(out: &mut Vec[UInt8], a: Int, b: Int, c: Int, d: Int, declared: Int, payload: &Vec[UInt8]) {
  push_fourcc(out, a, b, c, d);
  push_le32(out, declared);
  push_bytes(out, payload);
  if (declared % 2 != 0) { out.push(0 as UInt8); }
}

// VP8 payload with a valid key-frame header: key 0, version 0, show 1,
// 19-bit partition size `part`; `body` payload bytes follow the 10-byte
// uncompressed header.
fn vp8_payload(w: Int, h: Int, part: Int, body: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  push_le24(&mut v, part * 32 + 16);
  v.push(157 as UInt8);
  v.push(1 as UInt8);
  v.push(42 as UInt8);
  push_le16(&mut v, w);
  push_le16(&mut v, h);
  var i = 0;
  while (i < body) {
    v.push(((i + 11) % 256) as UInt8);
    i = i + 1;
  }
  return v;
}

// VP8L payload: 0x2F signature plus a LE32 packing width-1, height-1, the
// alpha hint and the 3-bit version.
fn vp8l_payload(w: Int, h: Int, alpha: Int, version: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  v.push(47 as UInt8);
  let bits = (h - 1) * 16384 + (w - 1) + alpha * 268435456 + version * 536870912;
  push_le32(&mut v, bits);
  return v;
}

fn vp8x_payload(flags: Int, cw: Int, ch: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  v.push(flags as UInt8);
  v.push(0 as UInt8);
  v.push(0 as UInt8);
  v.push(0 as UInt8);
  push_le24(&mut v, cw - 1);
  push_le24(&mut v, ch - 1);
  return v;
}

fn anim_payload(bg: Int, loop: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  push_le32(&mut v, bg);
  push_le16(&mut v, loop);
  return v;
}

// ANMF header: five 24-bit fields plus the blend/dispose flags byte. Frame
// data sub-chunks are appended by the caller.
fn anmf_payload(x: Int, y: Int, w: Int, h: Int, dur: Int, blend: Int, dispose: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  push_le24(&mut v, x / 2);
  push_le24(&mut v, y / 2);
  push_le24(&mut v, w - 1);
  push_le24(&mut v, h - 1);
  push_le24(&mut v, dur);
  v.push((dispose + blend * 2) as UInt8);
  return v;
}

// Canonical simple lossy file: header + one VP8 chunk.
fn mk_simple_vp8(w: Int, h: Int, body: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  start_riff(&mut out);
  let pl = vp8_payload(w, h, body, body);
  push_chunk(&mut out, 86, 80, 56, 32, pl);
  finish_riff(&mut out);
  return out;
}

// Canonical simple lossless file: header + one VP8L chunk.
fn mk_simple_vp8l(w: Int, h: Int, alpha: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  start_riff(&mut out);
  let pl = vp8l_payload(w, h, alpha, 0);
  push_chunk(&mut out, 86, 80, 56, 76, pl);
  finish_riff(&mut out);
  return out;
}

// Extended static file: VP8X + optional ICCP + optional ALPH + VP8/VP8L +
// optional EXIF + optional XMP. `fmt` is 1 VP8 or 2 VP8L; pass a payload
// size of -1 to omit a metadata chunk (0 is a legal empty payload).
fn mk_ext(fmt: Int, w: Int, h: Int, flags: Int, iccp: Int, alph: Int, exif: Int, xmp: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  start_riff(&mut out);
  let vx = vp8x_payload(flags, w, h);
  push_chunk(&mut out, 86, 80, 56, 88, vx);
  if (iccp >= 0) {
    let p = raw_bytes(iccp, 31);
    push_chunk(&mut out, 73, 67, 67, 80, p);
  }
  if (alph >= 0) {
    let p = raw_bytes(alph, 47);
    push_chunk(&mut out, 65, 76, 80, 72, p);
  }
  if (fmt == 1) {
    let p = vp8_payload(w, h, 0, 0);
    push_chunk(&mut out, 86, 80, 56, 32, p);
  } else {
    let p = vp8l_payload(w, h, 0, 0);
    push_chunk(&mut out, 86, 80, 56, 76, p);
  }
  if (exif >= 0) {
    let p = raw_bytes(exif, 59);
    push_chunk(&mut out, 69, 88, 73, 70, p);
  }
  if (xmp >= 0) {
    let p = raw_bytes(xmp, 71);
    push_chunk(&mut out, 88, 77, 80, 32, p);
  }
  finish_riff(&mut out);
  return out;
}

// VP8X (flags 0) plus a 1x1 VP8L image: lets a test choose a canvas that
// differs from the image dimensions.
fn mk_canvas_only(cw: Int, ch: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  start_riff(&mut out);
  let vx = vp8x_payload(0, cw, ch);
  push_chunk(&mut out, 86, 80, 56, 88, vx);
  let pl = vp8l_payload(1, 1, 0, 0);
  push_chunk(&mut out, 86, 80, 56, 76, pl);
  finish_riff(&mut out);
  return out;
}

// Animated file: VP8X(animation) + ANIM + `frames` ANMF frames. Frame 0 is
// ALPH + VP8, later frames are VP8L; every frame fills the canvas.
fn mk_animated(cw: Int, ch: Int, frames: Int, loop: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  start_riff(&mut out);
  let vx = vp8x_payload(2, cw, ch);
  push_chunk(&mut out, 86, 80, 56, 88, vx);
  let an = anim_payload(287454020, loop);
  push_chunk(&mut out, 65, 78, 73, 77, an);
  var i = 0;
  while (i < frames) {
    var fp = anmf_payload(0, 0, cw, ch, 40 + i, i % 2, (i + 1) % 2);
    if (i == 0) {
      let ap = raw_bytes(2, 91);
      push_chunk(&mut fp, 65, 76, 80, 72, ap);
      let bp = vp8_payload(cw, ch, 0, 2);
      push_chunk(&mut fp, 86, 80, 56, 32, bp);
    } else {
      let bp = vp8l_payload(cw, ch, 1, 0);
      push_chunk(&mut fp, 86, 80, 56, 76, bp);
    }
    push_chunk(&mut out, 65, 78, 77, 70, fp);
    i = i + 1;
  }
  finish_riff(&mut out);
  return out;
}

fn img_ok(r: Result[WebpImage, Str]) -> Bool {
  match r {
    Ok(v) => { return true; },
    Err(e) => { return false; },
  }
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  if (webp_header_size() != 12) { return assert(false, "header size 12"); }
  if (webp_chunk_header_size() != 8) { return assert(false, "chunk header size 8"); }
  let d = mk_simple_vp8(3, 2, 0);
  if (d.len() != 30) { return assert(false, "minimal lossy file is 30 bytes"); }
  if (!webp_is_webp(d)) { return assert(false, "buffer classifies as WebP"); }
  let img = ok_img(webp_parse(d));
  if (webp_kind(img) != 0) { return assert(false, "kind simple"); }
  if (webp_size(img) != 30) { return assert(false, "size 30"); }
  if (webp_riff_size(img) != 22) { return assert(false, "riff size 22"); }
  if (webp_has_vp8x(img)) { return assert(false, "no VP8X"); }
  if (webp_canvas_width(img) != 3) { return assert(false, "canvas width 3"); }
  if (webp_canvas_height(img) != 2) { return assert(false, "canvas height 2"); }
  if (!webp_has_image(img)) { return assert(false, "image present"); }
  if (webp_image_format(img) != 1) { return assert(false, "image format VP8"); }
  if (webp_image_width(img) != 3) { return assert(false, "image width 3"); }
  if (webp_image_height(img) != 2) { return assert(false, "image height 2"); }
  if (webp_image_offset(img) != 12) { return assert(false, "image chunk at 12"); }
  if (webp_image_data_offset(img) != 20) { return assert(false, "image data at 20"); }
  if (webp_image_size(img) != 10) { return assert(false, "image size 10"); }
  if (webp_vp8_version(img) != 0) { return assert(false, "vp8 version 0"); }
  if (webp_vp8_show_frame(img) != 1) { return assert(false, "vp8 show frame 1"); }
  if (webp_vp8_first_part_size(img) != 0) { return assert(false, "vp8 partition 0"); }
  if (webp_chunk_count(img) != 1) { return assert(false, "one chunk"); }
  let f0: Str = webp_chunk_fourcc(img, 0);
  if (!streq(f0, "VP8 ")) { return assert(false, "chunk 0 is VP8"); }
  if (webp_chunk_offset(img, 0) != 12) { return assert(false, "chunk at 12"); }
  if (webp_chunk_size(img, 0) != 10) { return assert(false, "chunk size 10"); }
  if (webp_chunk_data_offset(img, 0) != 20) { return assert(false, "chunk data at 20"); }
  if (webp_chunk_padding(img, 0) != 0) { return assert(false, "no padding"); }
  if (webp_chunk_kind(img, 0) != 1) { return assert(false, "kind VP8"); }
  if (webp_flags(img) != 0) { return assert(false, "flags 0"); }
  return assert(true, "minimal lossy VP8 file decodes header, chunk index and canvas exactly");
}

fn t2() -> TestResult {
  let d = mk_simple_vp8l(16, 8, 1);
  if (d.len() != 26) { return assert(false, "lossless file is 26 bytes"); }
  let img = ok_img(webp_parse(d));
  if (webp_kind(img) != 0) { return assert(false, "kind simple"); }
  if (webp_image_format(img) != 2) { return assert(false, "image format VP8L"); }
  if (webp_image_width(img) != 16) { return assert(false, "image width 16"); }
  if (webp_image_height(img) != 8) { return assert(false, "image height 8"); }
  if (webp_vp8l_alpha(img) != 1) { return assert(false, "alpha hint set"); }
  if (webp_vp8l_version(img) != 0) { return assert(false, "vp8l version 0"); }
  if (webp_canvas_width(img) != 16) { return assert(false, "canvas width 16"); }
  if (webp_canvas_height(img) != 8) { return assert(false, "canvas height 8"); }
  if (webp_chunk_count(img) != 1) { return assert(false, "one chunk"); }
  let f0: Str = webp_chunk_fourcc(img, 0);
  if (!streq(f0, "VP8L")) { return assert(false, "chunk 0 is VP8L"); }
  if (webp_chunk_size(img, 0) != 5) { return assert(false, "chunk size 5"); }
  if (webp_chunk_padding(img, 0) != 1) { return assert(false, "odd chunk is padded"); }
  if (webp_chunk_data_offset(img, 0) != 20) { return assert(false, "chunk data at 20"); }
  if (webp_vp8_version(img) != -1) { return assert(false, "VP8 fields absent"); }
  if (webp_vp8_first_part_size(img) != -1) { return assert(false, "VP8 partition absent"); }
  return assert(true, "lossless VP8L file decodes dimensions, alpha hint and padding");
}

fn t3() -> TestResult {
  var out = Vec[UInt8].new();
  start_riff(&mut out);
  let u = raw_bytes(3, 5);
  push_chunk(&mut out, 88, 89, 90, 87, u);
  let p = vp8l_payload(4, 4, 0, 0);
  push_chunk(&mut out, 86, 80, 56, 76, p);
  finish_riff(&mut out);
  if (out.len() != 38) { return assert(false, "file is 38 bytes"); }
  let img = ok_img(webp_parse(out));
  if (webp_chunk_count(img) != 2) { return assert(false, "two chunks"); }
  let c0: Str = webp_chunk_fourcc(img, 0);
  if (!streq(c0, "XYZW")) { return assert(false, "unknown fourcc kept"); }
  if (webp_chunk_kind(img, 0) != 0) { return assert(false, "unknown kind is other"); }
  if (webp_chunk_offset(img, 0) != 12) { return assert(false, "unknown at 12"); }
  if (webp_chunk_data_offset(img, 0) != 20) { return assert(false, "unknown data at 20"); }
  if (webp_chunk_size(img, 0) != 3) { return assert(false, "unknown size 3"); }
  if (webp_chunk_padding(img, 0) != 1) { return assert(false, "unknown padded"); }
  if (webp_chunk_offset(img, 1) != 24) { return assert(false, "VP8L at 24"); }
  if (webp_chunk_data_offset(img, 1) != 32) { return assert(false, "VP8L data at 32"); }
  if (webp_chunk_size(img, 1) != 5) { return assert(false, "VP8L size 5"); }
  if (webp_chunk_padding(img, 1) != 1) { return assert(false, "VP8L padded"); }
  if (webp_image_width(img) != 4) { return assert(false, "image 4 wide"); }
  if (webp_image_height(img) != 4) { return assert(false, "image 4 tall"); }
  return assert(true, "unknown chunks stay opaque and odd-size padding advances the walk exactly");
}

fn t4() -> TestResult {
  let empty = Vec[UInt8].new();
  if (!img_err_is(webp_parse(empty), "webp: truncated header at 0")) {
    return assert(false, "empty buffer is truncated header");
  }
  var three = Vec[UInt8].new();
  three.push(82 as UInt8);
  three.push(73 as UInt8);
  three.push(70 as UInt8);
  if (!img_err_is(webp_parse(three), "webp: truncated header at 0")) {
    return assert(false, "three bytes is truncated header");
  }
  var eight = Vec[UInt8].new();
  push_fourcc(&mut eight, 82, 73, 70, 70);
  push_le32(&mut eight, 0);
  if (!img_err_is(webp_parse(eight), "webp: truncated header at 0")) {
    return assert(false, "eight bytes is truncated header");
  }
  let bad0 = mk_simple_vp8(3, 2, 0);
  bad0[0] = 88 as UInt8;
  if (!img_err_is(webp_parse(bad0), "webp: bad magic at 0")) {
    return assert(false, "bad RIFF byte");
  }
  let bad8 = mk_simple_vp8(3, 2, 0);
  bad8[9] = 88 as UInt8;
  if (!img_err_is(webp_parse(bad8), "webp: bad magic at 9")) {
    return assert(false, "bad WEBP byte");
  }
  var small = mk_simple_vp8(3, 2, 0);
  set_riff_size(&mut small, 21);
  if (!img_err_is(webp_parse(small), "webp: riff size mismatch at 4")) {
    return assert(false, "small declared size");
  }
  var large = mk_simple_vp8(3, 2, 0);
  set_riff_size(&mut large, 23);
  if (!img_err_is(webp_parse(large), "webp: riff size mismatch at 4")) {
    return assert(false, "large declared size");
  }
  return assert(true, "RIFF header length, magic bytes and declared size are validated in order");
}

fn t5() -> TestResult {
  var shorthead = Vec[UInt8].new();
  start_riff(&mut shorthead);
  push_fourcc(&mut shorthead, 86, 80, 56, 32);
  push_le16(&mut shorthead, 10);
  finish_riff(&mut shorthead);
  if (shorthead.len() != 18) { return assert(false, "fixture is 18 bytes"); }
  if (!img_err_is(webp_parse(shorthead), at("webp: truncated chunk", 12))) {
    return assert(false, "truncated chunk header");
  }
  var shortpay = Vec[UInt8].new();
  start_riff(&mut shortpay);
  push_chunk_sized(&mut shortpay, 86, 80, 56, 32, 20, raw_bytes(10, 1));
  finish_riff(&mut shortpay);
  if (!img_err_is(webp_parse(shortpay), at("webp: truncated chunk", 12))) {
    return assert(false, "truncated chunk payload");
  }
  var nopad = Vec[UInt8].new();
  start_riff(&mut nopad);
  push_fourcc(&mut nopad, 86, 80, 56, 76);
  push_le32(&mut nopad, 5);
  push_bytes(&mut nopad, raw_bytes(5, 2));
  finish_riff(&mut nopad);
  if (nopad.len() != 25) { return assert(false, "fixture is 25 bytes"); }
  if (!img_err_is(webp_parse(nopad), at("webp: truncated padding", 25))) {
    return assert(false, "missing pad byte");
  }
  var badfour = Vec[UInt8].new();
  start_riff(&mut badfour);
  push_fourcc(&mut badfour, 86, 80, 1, 32);
  push_le32(&mut badfour, 0);
  finish_riff(&mut badfour);
  if (!img_err_is(webp_parse(badfour), at("webp: invalid FourCC", 12))) {
    return assert(false, "non-printable fourcc");
  }
  return assert(true, "chunk header/payload truncation, missing padding and bad fourcc are rejected");
}

fn t6() -> TestResult {
  let d = mk_simple_vp8l(16, 8, 0);
  if (d.len() != 26) { return assert(false, "file is 26 bytes"); }
  d[25] = 127 as UInt8;
  if (!img_err_is(webp_parse(d), at("webp: invalid padding byte", 25))) {
    return assert(false, "non-zero padding byte is rejected");
  }
  if (!img_ok(webp_parse(mk_simple_vp8l(16, 8, 0)))) {
    return assert(false, "zero padding byte is accepted");
  }
  return assert(true, "odd-size padding byte must be exactly zero");
}

fn t7() -> TestResult {
  var short = Vec[UInt8].new();
  start_riff(&mut short);
  let sp = raw_bytes(9, 1);
  push_chunk(&mut short, 86, 80, 56, 32, sp);
  finish_riff(&mut short);
  if (!img_err_is(webp_parse(short), at("webp: invalid VP8 length", 20))) {
    return assert(false, "short VP8 payload");
  }
  let code = mk_simple_vp8(3, 2, 0);
  code[23] = 156 as UInt8;
  if (!img_err_is(webp_parse(code), at("webp: invalid VP8 start code", 23))) {
    return assert(false, "bad start code");
  }
  let key = mk_simple_vp8(3, 2, 0);
  key[20] = 1 as UInt8;
  if (!img_err_is(webp_parse(key), at("webp: invalid VP8 frame tag", 20))) {
    return assert(false, "inter frame is rejected");
  }
  let ver = mk_simple_vp8(3, 2, 0);
  ver[20] = 24 as UInt8;
  if (!img_err_is(webp_parse(ver), at("webp: invalid VP8 version", 20))) {
    return assert(false, "reserved version is rejected");
  }
  let zero = mk_simple_vp8(0, 2, 0);
  if (!img_err_is(webp_parse(zero), at("webp: invalid VP8 dimensions", 26))) {
    return assert(false, "zero width is rejected");
  }
  var part = Vec[UInt8].new();
  start_riff(&mut part);
  let pp = vp8_payload(3, 2, 5, 0);
  push_chunk(&mut part, 86, 80, 56, 32, pp);
  finish_riff(&mut part);
  if (!img_err_is(webp_parse(part), at("webp: invalid VP8 partition size", 20))) {
    return assert(false, "partition past the payload");
  }
  return assert(true, "VP8 length, start code, key frame, version, dimensions and partition size are checked");
}

fn t8() -> TestResult {
  var short = Vec[UInt8].new();
  start_riff(&mut short);
  let sp = raw_bytes(4, 1);
  push_chunk(&mut short, 86, 80, 56, 76, sp);
  finish_riff(&mut short);
  if (!img_err_is(webp_parse(short), at("webp: invalid VP8L length", 20))) {
    return assert(false, "short VP8L payload");
  }
  let sig = mk_simple_vp8l(2, 2, 0);
  sig[20] = 46 as UInt8;
  if (!img_err_is(webp_parse(sig), at("webp: invalid VP8L signature", 20))) {
    return assert(false, "bad VP8L signature");
  }
  var ver = Vec[UInt8].new();
  start_riff(&mut ver);
  let vp = vp8l_payload(2, 2, 0, 1);
  push_chunk(&mut ver, 86, 80, 56, 76, vp);
  finish_riff(&mut ver);
  if (!img_err_is(webp_parse(ver), at("webp: invalid VP8L version", 20))) {
    return assert(false, "reserved VP8L version");
  }
  let big = ok_img(webp_parse(mk_simple_vp8l(16384, 16384, 1)));
  if (webp_image_width(big) != 16384) { return assert(false, "14-bit max width"); }
  if (webp_image_height(big) != 16384) { return assert(false, "14-bit max height"); }
  if (webp_vp8l_alpha(big) != 1) { return assert(false, "alpha hint preserved"); }
  let one = ok_img(webp_parse(mk_simple_vp8l(1, 1, 0)));
  if (webp_image_width(one) != 1) { return assert(false, "1x1 width"); }
  if (webp_image_height(one) != 1) { return assert(false, "1x1 height"); }
  return assert(true, "VP8L signature, version and 14-bit dimension extremes are exact");
}

fn t9() -> TestResult {
  let d = mk_ext(1, 3, 2, 60, 4, 2, 3, 5);
  if (d.len() != 96) { return assert(false, "file is 96 bytes"); }
  let img = ok_img(webp_parse(d));
  if (webp_kind(img) != 1) { return assert(false, "kind extended"); }
  if (!webp_has_vp8x(img)) { return assert(false, "VP8X present"); }
  if (webp_vp8x_offset(img) != 12) { return assert(false, "VP8X at 12"); }
  if (webp_flags(img) != 60) { return assert(false, "flags 60"); }
  if (webp_flag_icc(img) != 1) { return assert(false, "ICC flag"); }
  if (webp_flag_alpha(img) != 1) { return assert(false, "alpha flag"); }
  if (webp_flag_exif(img) != 1) { return assert(false, "EXIF flag"); }
  if (webp_flag_xmp(img) != 1) { return assert(false, "XMP flag"); }
  if (webp_flag_animation(img) != 0) { return assert(false, "animation flag clear"); }
  if (webp_canvas_width(img) != 3) { return assert(false, "canvas 3 wide"); }
  if (webp_canvas_height(img) != 2) { return assert(false, "canvas 2 tall"); }
  if (webp_chunk_count(img) != 6) { return assert(false, "six chunks"); }
  let c0: Str = webp_chunk_fourcc(img, 0);
  let c1: Str = webp_chunk_fourcc(img, 1);
  let c2: Str = webp_chunk_fourcc(img, 2);
  let c3: Str = webp_chunk_fourcc(img, 3);
  let c4: Str = webp_chunk_fourcc(img, 4);
  let c5: Str = webp_chunk_fourcc(img, 5);
  if (!streq(c0, "VP8X")) { return assert(false, "chunk 0 VP8X"); }
  if (!streq(c1, "ICCP")) { return assert(false, "chunk 1 ICCP"); }
  if (!streq(c2, "ALPH")) { return assert(false, "chunk 2 ALPH"); }
  if (!streq(c3, "VP8 ")) { return assert(false, "chunk 3 VP8"); }
  if (!streq(c4, "EXIF")) { return assert(false, "chunk 4 EXIF"); }
  if (!streq(c5, "XMP ")) { return assert(false, "chunk 5 XMP"); }
  if (webp_chunk_offset(img, 1) != 30) { return assert(false, "ICCP at 30"); }
  if (webp_chunk_offset(img, 2) != 42) { return assert(false, "ALPH at 42"); }
  if (webp_chunk_offset(img, 3) != 52) { return assert(false, "VP8 at 52"); }
  if (webp_chunk_offset(img, 4) != 70) { return assert(false, "EXIF at 70"); }
  if (webp_chunk_offset(img, 5) != 82) { return assert(false, "XMP at 82"); }
  if (webp_chunk_data_offset(img, 1) != 38) { return assert(false, "ICCP data at 38"); }
  if (webp_chunk_data_offset(img, 2) != 50) { return assert(false, "ALPH data at 50"); }
  if (webp_chunk_data_offset(img, 3) != 60) { return assert(false, "VP8 data at 60"); }
  if (webp_chunk_padding(img, 4) != 1) { return assert(false, "EXIF padded"); }
  if (webp_chunk_padding(img, 5) != 1) { return assert(false, "XMP padded"); }
  if (!webp_has_iccp(img)) { return assert(false, "ICCP presence"); }
  if (webp_iccp_size(img) != 4) { return assert(false, "ICCP size 4"); }
  if (webp_iccp_offset(img) != 30) { return assert(false, "ICCP offset 30"); }
  if (!webp_has_alph(img)) { return assert(false, "ALPH presence"); }
  if (webp_alph_size(img) != 2) { return assert(false, "ALPH size 2"); }
  if (!webp_has_exif(img)) { return assert(false, "EXIF presence"); }
  if (webp_exif_size(img) != 3) { return assert(false, "EXIF size 3"); }
  if (!webp_has_xmp(img)) { return assert(false, "XMP presence"); }
  if (webp_xmp_size(img) != 5) { return assert(false, "XMP size 5"); }
  if (!webp_has_image(img)) { return assert(false, "image present"); }
  if (webp_image_format(img) != 1) { return assert(false, "image VP8"); }
  if (webp_image_width(img) != 3) { return assert(false, "image 3 wide"); }
  if (webp_image_height(img) != 2) { return assert(false, "image 2 tall"); }
  if (webp_has_anim(img)) { return assert(false, "no ANIM"); }
  if (webp_frame_count(img) != 0) { return assert(false, "no frames"); }
  return assert(true, "extended static file with ICCP, ALPH, EXIF and XMP decodes fully");
}

fn t10() -> TestResult {
  var out = Vec[UInt8].new();
  start_riff(&mut out);
  let vx = vp8x_payload(0, 5, 5);
  push_chunk(&mut out, 86, 80, 56, 88, vx);
  let pl = vp8l_payload(5, 5, 0, 0);
  push_chunk(&mut out, 86, 80, 56, 76, pl);
  let uz = raw_bytes(4, 13);
  push_chunk(&mut out, 90, 90, 90, 90, uz);
  finish_riff(&mut out);
  if (out.len() != 56) { return assert(false, "file is 56 bytes"); }
  let img = ok_img(webp_parse(out));
  if (webp_kind(img) != 1) { return assert(false, "kind extended"); }
  if (webp_chunk_count(img) != 3) { return assert(false, "three chunks"); }
  let c2: Str = webp_chunk_fourcc(img, 2);
  if (!streq(c2, "ZZZZ")) { return assert(false, "unknown fourcc"); }
  if (webp_chunk_kind(img, 2) != 0) { return assert(false, "unknown kind"); }
  if (webp_chunk_offset(img, 2) != 44) { return assert(false, "unknown at 44"); }
  if (webp_chunk_data_offset(img, 2) != 52) { return assert(false, "unknown data at 52"); }
  if (webp_chunk_size(img, 2) != 4) { return assert(false, "unknown size 4"); }
  if (webp_chunk_padding(img, 2) != 0) { return assert(false, "unknown even"); }
  if (webp_image_format(img) != 2) { return assert(false, "VP8L image"); }
  if (webp_image_width(img) != 5) { return assert(false, "5 wide"); }
  if (webp_image_height(img) != 5) { return assert(false, "5 tall"); }
  if (webp_canvas_width(img) != 5) { return assert(false, "canvas 5"); }
  return assert(true, "trailing unknown chunks are recorded opaque without affecting the image");
}

fn t11() -> TestResult {
  var short = Vec[UInt8].new();
  start_riff(&mut short);
  let sx = raw_bytes(9, 1);
  push_chunk(&mut short, 86, 80, 56, 88, sx);
  finish_riff(&mut short);
  if (!img_err_is(webp_parse(short), at("webp: invalid VP8X length", 12))) {
    return assert(false, "nine-byte VP8X payload");
  }
  var rb = Vec[UInt8].new();
  start_riff(&mut rb);
  let rx = vp8x_payload(128, 1, 1);
  push_chunk(&mut rb, 86, 80, 56, 88, rx);
  finish_riff(&mut rb);
  if (!img_err_is(webp_parse(rb), at("webp: reserved VP8X bits", 20))) {
    return assert(false, "reserved VP8X flag bit");
  }
  var rby = Vec[UInt8].new();
  start_riff(&mut rby);
  let ry = vp8x_payload(0, 1, 1);
  ry[1] = 1 as UInt8;
  push_chunk(&mut rby, 86, 80, 56, 88, ry);
  finish_riff(&mut rby);
  if (!img_err_is(webp_parse(rby), at("webp: reserved VP8X bytes", 21))) {
    return assert(false, "reserved VP8X byte");
  }
  if (!img_err_is(webp_parse(mk_ext(1, 65536, 65536, 0, -1, -1, -1, -1)), at("webp: canvas too large", 12))) {
    return assert(false, "canvas product above 2^32-1");
  }
  var dup = Vec[UInt8].new();
  start_riff(&mut dup);
  let dx = vp8x_payload(0, 1, 1);
  push_chunk(&mut dup, 86, 80, 56, 88, dx);
  push_chunk(&mut dup, 86, 80, 56, 88, dx);
  finish_riff(&mut dup);
  if (!img_err_is(webp_parse(dup), at("webp: duplicate VP8X", 30))) {
    return assert(false, "second VP8X is a duplicate");
  }
  var nf = Vec[UInt8].new();
  start_riff(&mut nf);
  let none = Vec[UInt8].new();
  push_chunk(&mut nf, 90, 90, 90, 90, none);
  let nx = vp8x_payload(0, 1, 1);
  push_chunk(&mut nf, 86, 80, 56, 88, nx);
  finish_riff(&mut nf);
  if (!img_err_is(webp_parse(nf), at("webp: VP8X not first", 20))) {
    return assert(false, "VP8X after another chunk");
  }
  let bnd = ok_img(webp_parse(mk_canvas_only(65535, 65536)));
  if (webp_canvas_width(bnd) != 65535) { return assert(false, "canvas product boundary width"); }
  if (webp_canvas_height(bnd) != 65536) { return assert(false, "canvas product boundary height"); }
  return assert(true, "VP8X length, reserved fields, canvas cap, duplicate and first-chunk rules hold");
}

fn t12() -> TestResult {
  if (!img_err_is(webp_parse(mk_ext(2, 2, 2, 32, -1, -1, -1, -1)), at("webp: ICC flag without ICCP", 12))) {
    return assert(false, "ICC flag alone");
  }
  if (!img_err_is(webp_parse(mk_ext(2, 2, 2, 0, 3, -1, -1, -1)), at("webp: ICCP without ICC flag", 30))) {
    return assert(false, "ICCP without the flag");
  }
  if (!img_err_is(webp_parse(mk_ext(2, 2, 2, 8, -1, -1, -1, -1)), at("webp: EXIF flag without EXIF", 12))) {
    return assert(false, "EXIF flag alone");
  }
  if (!img_err_is(webp_parse(mk_ext(2, 2, 2, 4, -1, -1, -1, -1)), at("webp: XMP flag without XMP", 12))) {
    return assert(false, "XMP flag alone");
  }
  if (!img_err_is(webp_parse(mk_ext(1, 2, 2, 16, -1, -1, -1, -1)), at("webp: alpha flag without ALPH", 12))) {
    return assert(false, "alpha flag with VP8 and no ALPH");
  }
  if (!img_err_is(webp_parse(mk_ext(1, 2, 2, 0, -1, 2, -1, -1)), at("webp: ALPH without alpha flag", 30))) {
    return assert(false, "ALPH without the flag");
  }
  let vl = ok_img(webp_parse(mk_ext(2, 2, 2, 16, -1, -1, -1, -1)));
  if (webp_flag_alpha(vl) != 1) { return assert(false, "VP8L alpha with the flag is legal"); }
  if (webp_has_alph(vl)) { return assert(false, "no top-level ALPH in the VP8L file"); }
  return assert(true, "VP8X flag bits and metadata chunk presence must agree in both directions");
}

fn t13() -> TestResult {
  let d = mk_animated(10, 8, 2, 3);
  if (d.len() != 136) { return assert(false, "animated file is 136 bytes"); }
  let img = ok_img(webp_parse(d));
  if (webp_kind(img) != 2) { return assert(false, "kind animated"); }
  if (webp_flag_animation(img) != 1) { return assert(false, "animation flag set"); }
  if (webp_canvas_width(img) != 10) { return assert(false, "canvas 10 wide"); }
  if (webp_canvas_height(img) != 8) { return assert(false, "canvas 8 tall"); }
  if (webp_has_image(img)) { return assert(false, "no top-level image"); }
  if (webp_image_width(img) != 0) { return assert(false, "image width sentinel"); }
  if (webp_image_offset(img) != -1) { return assert(false, "image offset sentinel"); }
  if (!webp_has_anim(img)) { return assert(false, "ANIM present"); }
  if (webp_anim_background(img) != 287454020) { return assert(false, "background raw value"); }
  if (webp_anim_background_blue(img) != 68) { return assert(false, "blue 0x44"); }
  if (webp_anim_background_green(img) != 51) { return assert(false, "green 0x33"); }
  if (webp_anim_background_red(img) != 34) { return assert(false, "red 0x22"); }
  if (webp_anim_background_alpha(img) != 17) { return assert(false, "alpha 0x11"); }
  if (webp_anim_loop_count(img) != 3) { return assert(false, "loop count 3"); }
  if (webp_frame_count(img) != 2) { return assert(false, "two frames"); }
  if (webp_frame_x(img, 0) != 0) { return assert(false, "frame 0 x"); }
  if (webp_frame_y(img, 0) != 0) { return assert(false, "frame 0 y"); }
  if (webp_frame_width(img, 0) != 10) { return assert(false, "frame 0 width"); }
  if (webp_frame_height(img, 0) != 8) { return assert(false, "frame 0 height"); }
  if (webp_frame_duration(img, 0) != 40) { return assert(false, "frame 0 duration"); }
  if (webp_frame_blend(img, 0) != 0) { return assert(false, "frame 0 blend"); }
  if (webp_frame_dispose(img, 0) != 1) { return assert(false, "frame 0 dispose"); }
  if (webp_frame_format(img, 0) != 1) { return assert(false, "frame 0 is VP8"); }
  if (webp_frame_has_alpha(img, 0) != 1) { return assert(false, "frame 0 has ALPH"); }
  if (webp_frame_nested_count(img, 0) != 2) { return assert(false, "frame 0 nested count"); }
  if (webp_frame_unknown_count(img, 0) != 0) { return assert(false, "frame 0 unknown count"); }
  if (webp_frame_offset(img, 0) != 44) { return assert(false, "frame 0 ANMF at 44"); }
  if (webp_frame_size(img, 0) != 46) { return assert(false, "frame 0 ANMF size 46"); }
  if (webp_frame_data_offset(img, 0) != 86) { return assert(false, "frame 0 data at 86"); }
  if (webp_frame_data_size(img, 0) != 12) { return assert(false, "frame 0 data size 12"); }
  if (webp_frame_duration(img, 1) != 41) { return assert(false, "frame 1 duration"); }
  if (webp_frame_blend(img, 1) != 1) { return assert(false, "frame 1 blend"); }
  if (webp_frame_dispose(img, 1) != 0) { return assert(false, "frame 1 dispose"); }
  if (webp_frame_format(img, 1) != 2) { return assert(false, "frame 1 is VP8L"); }
  if (webp_frame_has_alpha(img, 1) != 0) { return assert(false, "frame 1 has no ALPH"); }
  if (webp_frame_nested_count(img, 1) != 1) { return assert(false, "frame 1 nested count"); }
  if (webp_frame_offset(img, 1) != 98) { return assert(false, "frame 1 ANMF at 98"); }
  if (webp_frame_size(img, 1) != 30) { return assert(false, "frame 1 ANMF size 30"); }
  if (webp_frame_data_offset(img, 1) != 130) { return assert(false, "frame 1 data at 130"); }
  if (webp_frame_data_size(img, 1) != 5) { return assert(false, "frame 1 data size 5"); }
  if (webp_chunk_kind(img, 1) != 5) { return assert(false, "chunk 1 is ANIM"); }
  if (webp_chunk_kind(img, 2) != 6) { return assert(false, "chunk 2 is ANMF"); }
  return assert(true, "animated file decodes ANIM parameters and both frame records exactly");
}

fn t14() -> TestResult {
  var alen = Vec[UInt8].new();
  start_riff(&mut alen);
  let ax = vp8x_payload(2, 1, 1);
  push_chunk(&mut alen, 86, 80, 56, 88, ax);
  let ab = raw_bytes(5, 3);
  push_chunk(&mut alen, 65, 78, 73, 77, ab);
  finish_riff(&mut alen);
  if (!img_err_is(webp_parse(alen), at("webp: invalid ANIM length", 30))) {
    return assert(false, "five-byte ANIM payload");
  }
  var adup = Vec[UInt8].new();
  start_riff(&mut adup);
  let ax2 = vp8x_payload(2, 1, 1);
  push_chunk(&mut adup, 86, 80, 56, 88, ax2);
  let an2 = anim_payload(0, 0);
  push_chunk(&mut adup, 65, 78, 73, 77, an2);
  push_chunk(&mut adup, 65, 78, 73, 77, an2);
  finish_riff(&mut adup);
  if (!img_err_is(webp_parse(adup), at("webp: duplicate ANIM", 44))) {
    return assert(false, "second ANIM is a duplicate");
  }
  var aafter = Vec[UInt8].new();
  start_riff(&mut aafter);
  let ax3 = vp8x_payload(2, 1, 1);
  push_chunk(&mut aafter, 86, 80, 56, 88, ax3);
  var f1 = anmf_payload(0, 0, 1, 1, 10, 0, 0);
  let b1 = vp8l_payload(1, 1, 0, 0);
  push_chunk(&mut f1, 86, 80, 56, 76, b1);
  push_chunk(&mut aafter, 65, 78, 77, 70, f1);
  let an3 = anim_payload(0, 0);
  push_chunk(&mut aafter, 65, 78, 73, 77, an3);
  finish_riff(&mut aafter);
  if (!img_err_is(webp_parse(aafter), at("webp: ANIM after ANMF", 68))) {
    return assert(false, "ANIM after the first frame");
  }
  var noanim = Vec[UInt8].new();
  start_riff(&mut noanim);
  let nx = vp8x_payload(2, 1, 1);
  push_chunk(&mut noanim, 86, 80, 56, 88, nx);
  finish_riff(&mut noanim);
  if (!img_err_is(webp_parse(noanim), at("webp: animation flag without ANIM", 12))) {
    return assert(false, "animation flag without ANIM");
  }
  var noflag = Vec[UInt8].new();
  start_riff(&mut noflag);
  let nfx = vp8x_payload(0, 1, 1);
  push_chunk(&mut noflag, 86, 80, 56, 88, nfx);
  let nfa = anim_payload(0, 0);
  push_chunk(&mut noflag, 65, 78, 73, 77, nfa);
  let nfp = vp8l_payload(1, 1, 0, 0);
  push_chunk(&mut noflag, 86, 80, 56, 76, nfp);
  finish_riff(&mut noflag);
  if (!img_err_is(webp_parse(noflag), at("webp: animation chunk without flag", 30))) {
    return assert(false, "ANIM without the animation flag");
  }
  var outb = Vec[UInt8].new();
  start_riff(&mut outb);
  let ox = vp8x_payload(2, 10, 8);
  push_chunk(&mut outb, 86, 80, 56, 88, ox);
  let oa = anim_payload(0, 0);
  push_chunk(&mut outb, 65, 78, 73, 77, oa);
  var of = anmf_payload(0, 0, 11, 8, 10, 0, 0);
  let ob = vp8l_payload(1, 1, 0, 0);
  push_chunk(&mut of, 86, 80, 56, 76, ob);
  push_chunk(&mut outb, 65, 78, 77, 70, of);
  finish_riff(&mut outb);
  if (!img_err_is(webp_parse(outb), at("webp: frame outside canvas", 44))) {
    return assert(false, "frame wider than the canvas");
  }
  var ashort = Vec[UInt8].new();
  start_riff(&mut ashort);
  let sx = vp8x_payload(2, 1, 1);
  push_chunk(&mut ashort, 86, 80, 56, 88, sx);
  let sa = anim_payload(0, 0);
  push_chunk(&mut ashort, 65, 78, 73, 77, sa);
  let sf = raw_bytes(15, 7);
  push_chunk(&mut ashort, 65, 78, 77, 70, sf);
  finish_riff(&mut ashort);
  if (!img_err_is(webp_parse(ashort), at("webp: invalid ANMF length", 44))) {
    return assert(false, "fifteen-byte ANMF payload");
  }
  var rb = Vec[UInt8].new();
  start_riff(&mut rb);
  let rx = vp8x_payload(2, 1, 1);
  push_chunk(&mut rb, 86, 80, 56, 88, rx);
  let ra = anim_payload(0, 0);
  push_chunk(&mut rb, 65, 78, 73, 77, ra);
  var rf = anmf_payload(0, 0, 1, 1, 10, 0, 0);
  rf[15] = 4 as UInt8;
  let rp = vp8l_payload(1, 1, 0, 0);
  push_chunk(&mut rf, 86, 80, 56, 76, rp);
  push_chunk(&mut rb, 65, 78, 77, 70, rf);
  finish_riff(&mut rb);
  if (!img_err_is(webp_parse(rb), at("webp: reserved ANMF bits", 67))) {
    return assert(false, "reserved ANMF flag bit");
  }
  var mi = Vec[UInt8].new();
  start_riff(&mut mi);
  let mx = vp8x_payload(2, 1, 1);
  push_chunk(&mut mi, 86, 80, 56, 88, mx);
  let ma = anim_payload(0, 0);
  push_chunk(&mut mi, 65, 78, 73, 77, ma);
  var mf = anmf_payload(0, 0, 1, 1, 10, 0, 0);
  let map = raw_bytes(2, 3);
  push_chunk(&mut mf, 65, 76, 80, 72, map);
  push_chunk(&mut mi, 65, 78, 77, 70, mf);
  finish_riff(&mut mi);
  if (!img_err_is(webp_parse(mi), at("webp: ANMF missing image data", 44))) {
    return assert(false, "frame without a bitstream");
  }
  var tf = Vec[UInt8].new();
  start_riff(&mut tf);
  let tx = vp8x_payload(2, 1, 1);
  push_chunk(&mut tf, 86, 80, 56, 88, tx);
  let ta = anim_payload(0, 0);
  push_chunk(&mut tf, 65, 78, 73, 77, ta);
  var tp = anmf_payload(0, 0, 1, 1, 10, 0, 0);
  push_fourcc(&mut tp, 86, 80, 56, 76);
  push_le16(&mut tp, 5);
  push_chunk(&mut tf, 65, 78, 77, 70, tp);
  finish_riff(&mut tf);
  if (!img_err_is(webp_parse(tf), at("webp: truncated frame chunk", 68))) {
    return assert(false, "truncated nested chunk header");
  }
  return assert(true, "ANIM/ANMF length, duplicate, ordering, bounds, reserved and truncation rules hold");
}

fn t15() -> TestResult {
  var da = Vec[UInt8].new();
  start_riff(&mut da);
  let dx = vp8x_payload(2, 1, 1);
  push_chunk(&mut da, 86, 80, 56, 88, dx);
  let dap = anim_payload(0, 0);
  push_chunk(&mut da, 65, 78, 73, 77, dap);
  var df = anmf_payload(0, 0, 1, 1, 10, 0, 0);
  let a1 = raw_bytes(2, 1);
  push_chunk(&mut df, 65, 76, 80, 72, a1);
  push_chunk(&mut df, 65, 76, 80, 72, a1);
  let db = vp8l_payload(1, 1, 0, 0);
  push_chunk(&mut df, 86, 80, 56, 76, db);
  push_chunk(&mut da, 65, 78, 77, 70, df);
  finish_riff(&mut da);
  if (!img_err_is(webp_parse(da), at("webp: duplicate frame alpha", 78))) {
    return assert(false, "two ALPH sub-chunks");
  }
  var fa = Vec[UInt8].new();
  start_riff(&mut fa);
  let fx = vp8x_payload(2, 1, 1);
  push_chunk(&mut fa, 86, 80, 56, 88, fx);
  let fap = anim_payload(0, 0);
  push_chunk(&mut fa, 65, 78, 73, 77, fap);
  var ff = anmf_payload(0, 0, 1, 1, 10, 0, 0);
  let fb = vp8l_payload(1, 1, 0, 0);
  push_chunk(&mut ff, 86, 80, 56, 76, fb);
  let fap2 = raw_bytes(2, 1);
  push_chunk(&mut ff, 65, 76, 80, 72, fap2);
  push_chunk(&mut fa, 65, 78, 77, 70, ff);
  finish_riff(&mut fa);
  if (!img_err_is(webp_parse(fa), at("webp: frame alpha after image", 82))) {
    return assert(false, "ALPH after the bitstream");
  }
  var mf = Vec[UInt8].new();
  start_riff(&mut mf);
  let mx = vp8x_payload(2, 1, 1);
  push_chunk(&mut mf, 86, 80, 56, 88, mx);
  let ma = anim_payload(0, 0);
  push_chunk(&mut mf, 65, 78, 73, 77, ma);
  var mfp = anmf_payload(0, 0, 1, 1, 10, 0, 0);
  let mb1 = vp8l_payload(1, 1, 0, 0);
  push_chunk(&mut mfp, 86, 80, 56, 76, mb1);
  let mb2 = vp8_payload(1, 1, 0, 0);
  push_chunk(&mut mfp, 86, 80, 56, 32, mb2);
  push_chunk(&mut mf, 65, 78, 77, 70, mfp);
  finish_riff(&mut mf);
  if (!img_err_is(webp_parse(mf), at("webp: multiple frame image chunks", 82))) {
    return assert(false, "two nested bitstreams");
  }
  var np = Vec[UInt8].new();
  start_riff(&mut np);
  let nx = vp8x_payload(2, 1, 1);
  push_chunk(&mut np, 86, 80, 56, 88, nx);
  let na = anim_payload(0, 0);
  push_chunk(&mut np, 65, 78, 73, 77, na);
  var nf = anmf_payload(0, 0, 1, 1, 10, 0, 0);
  let npl = vp8l_payload(1, 1, 0, 0);
  push_chunk(&mut nf, 86, 80, 56, 76, npl);
  push_chunk(&mut np, 65, 78, 77, 70, nf);
  finish_riff(&mut np);
  if (np.len() != 82) { return assert(false, "pad fixture is 82 bytes"); }
  np[81] = 85 as UInt8;
  if (!img_err_is(webp_parse(np), at("webp: invalid padding byte", 81))) {
    return assert(false, "non-zero nested padding byte");
  }
  var ntp = Vec[UInt8].new();
  start_riff(&mut ntp);
  let tx = vp8x_payload(2, 1, 1);
  push_chunk(&mut ntp, 86, 80, 56, 88, tx);
  let ta = anim_payload(0, 0);
  push_chunk(&mut ntp, 65, 78, 73, 77, ta);
  var tfp = anmf_payload(0, 0, 1, 1, 10, 0, 0);
  push_fourcc(&mut tfp, 86, 80, 56, 76);
  push_le32(&mut tfp, 5);
  push_bytes(&mut tfp, vp8l_payload(1, 1, 0, 0));
  push_chunk(&mut ntp, 65, 78, 77, 70, tfp);
  finish_riff(&mut ntp);
  if (!img_err_is(webp_parse(ntp), at("webp: truncated padding", 81))) {
    return assert(false, "nested odd payload without padding");
  }
  var zf = Vec[UInt8].new();
  start_riff(&mut zf);
  let zx = vp8x_payload(2, 1, 1);
  push_chunk(&mut zf, 86, 80, 56, 88, zx);
  let za = anim_payload(0, 0);
  push_chunk(&mut zf, 65, 78, 73, 77, za);
  var zfp = anmf_payload(0, 0, 1, 1, 10, 0, 0);
  let z0 = Vec[UInt8].new();
  push_chunk(&mut zfp, 65, 76, 80, 72, z0);
  let zb = vp8l_payload(1, 1, 0, 0);
  push_chunk(&mut zfp, 86, 80, 56, 76, zb);
  push_chunk(&mut zf, 65, 78, 77, 70, zfp);
  finish_riff(&mut zf);
  if (!img_err_is(webp_parse(zf), at("webp: invalid ALPH length", 68))) {
    return assert(false, "empty nested ALPH");
  }
  var uk = Vec[UInt8].new();
  start_riff(&mut uk);
  let ux = vp8x_payload(2, 1, 1);
  push_chunk(&mut uk, 86, 80, 56, 88, ux);
  let ua = anim_payload(0, 0);
  push_chunk(&mut uk, 65, 78, 73, 77, ua);
  var uf = anmf_payload(0, 0, 1, 1, 10, 0, 0);
  let ub = vp8l_payload(1, 1, 0, 0);
  push_chunk(&mut uf, 86, 80, 56, 76, ub);
  let uz = raw_bytes(4, 21);
  push_chunk(&mut uf, 90, 90, 90, 90, uz);
  push_chunk(&mut uk, 65, 78, 77, 70, uf);
  finish_riff(&mut uk);
  let ui = ok_img(webp_parse(uk));
  if (webp_frame_nested_count(ui, 0) != 2) { return assert(false, "nested count 2"); }
  if (webp_frame_unknown_count(ui, 0) != 1) { return assert(false, "one nested unknown"); }
  if (webp_frame_format(ui, 0) != 2) { return assert(false, "frame bitstream is VP8L"); }
  if (webp_frame_data_offset(ui, 0) != 76) { return assert(false, "frame data at 76"); }
  return assert(true, "nested ANMF sub-chunks enforce order, uniqueness and padding, unknowns stay opaque");
}

fn t16() -> TestResult {
  var ai = Vec[UInt8].new();
  start_riff(&mut ai);
  let aix = vp8x_payload(2, 1, 1);
  push_chunk(&mut ai, 86, 80, 56, 88, aix);
  let aia = anim_payload(0, 0);
  push_chunk(&mut ai, 65, 78, 73, 77, aia);
  var aif = anmf_payload(0, 0, 1, 1, 10, 0, 0);
  let aib = vp8l_payload(1, 1, 0, 0);
  push_chunk(&mut aif, 86, 80, 56, 76, aib);
  push_chunk(&mut ai, 65, 78, 77, 70, aif);
  let aip = vp8_payload(1, 1, 0, 0);
  push_chunk(&mut ai, 86, 80, 56, 32, aip);
  finish_riff(&mut ai);
  if (!img_err_is(webp_parse(ai), at("webp: image chunk in animation", 82))) {
    return assert(false, "top-level image inside an animation");
  }
  var aa = Vec[UInt8].new();
  start_riff(&mut aa);
  let aax = vp8x_payload(2, 1, 1);
  push_chunk(&mut aa, 86, 80, 56, 88, aax);
  let aaa = anim_payload(0, 0);
  push_chunk(&mut aa, 65, 78, 73, 77, aaa);
  var aaf = anmf_payload(0, 0, 1, 1, 10, 0, 0);
  let aab = vp8l_payload(1, 1, 0, 0);
  push_chunk(&mut aaf, 86, 80, 56, 76, aab);
  push_chunk(&mut aa, 65, 78, 77, 70, aaf);
  let aap = raw_bytes(2, 5);
  push_chunk(&mut aa, 65, 76, 80, 72, aap);
  finish_riff(&mut aa);
  if (!img_err_is(webp_parse(aa), at("webp: ALPH chunk in animation", 82))) {
    return assert(false, "top-level ALPH inside an animation");
  }
  var nofr = Vec[UInt8].new();
  start_riff(&mut nofr);
  let nox = vp8x_payload(2, 1, 1);
  push_chunk(&mut nofr, 86, 80, 56, 88, nox);
  let noa = anim_payload(0, 0);
  push_chunk(&mut nofr, 65, 78, 73, 77, noa);
  finish_riff(&mut nofr);
  if (!img_err_is(webp_parse(nofr), at("webp: animation without frames", 30))) {
    return assert(false, "animation flag and ANIM but no frames");
  }
  var stat = Vec[UInt8].new();
  start_riff(&mut stat);
  let stx = vp8x_payload(0, 1, 1);
  push_chunk(&mut stat, 86, 80, 56, 88, stx);
  var stf = anmf_payload(0, 0, 1, 1, 10, 0, 0);
  let stb = vp8l_payload(1, 1, 0, 0);
  push_chunk(&mut stf, 86, 80, 56, 76, stb);
  push_chunk(&mut stat, 65, 78, 77, 70, stf);
  finish_riff(&mut stat);
  if (!img_err_is(webp_parse(stat), at("webp: animation frame without flag", 30))) {
    return assert(false, "ANMF without the animation flag");
  }
  var em = Vec[UInt8].new();
  start_riff(&mut em);
  let emx = vp8x_payload(0, 1, 1);
  push_chunk(&mut em, 86, 80, 56, 88, emx);
  finish_riff(&mut em);
  if (!img_err_is(webp_parse(em), "webp: missing image data at 12")) {
    return assert(false, "extended static file without image data");
  }
  var sm = Vec[UInt8].new();
  start_riff(&mut sm);
  let none = Vec[UInt8].new();
  push_chunk(&mut sm, 90, 90, 90, 90, none);
  finish_riff(&mut sm);
  if (!img_err_is(webp_parse(sm), "webp: missing image data at 12")) {
    return assert(false, "simple file without image data");
  }
  var sa = Vec[UInt8].new();
  start_riff(&mut sa);
  let sap = raw_bytes(2, 9);
  push_chunk(&mut sa, 65, 76, 80, 72, sap);
  let sab = vp8l_payload(1, 1, 0, 0);
  push_chunk(&mut sa, 86, 80, 56, 76, sab);
  finish_riff(&mut sa);
  if (!img_err_is(webp_parse(sa), at("webp: metadata chunk without VP8X", 12))) {
    return assert(false, "ALPH without VP8X");
  }
  var mul = Vec[UInt8].new();
  start_riff(&mut mul);
  let mb1 = vp8l_payload(1, 1, 0, 0);
  push_chunk(&mut mul, 86, 80, 56, 76, mb1);
  let mb2 = vp8l_payload(2, 2, 0, 0);
  push_chunk(&mut mul, 86, 80, 56, 76, mb2);
  finish_riff(&mut mul);
  if (!img_err_is(webp_parse(mul), at("webp: multiple image chunks", 26))) {
    return assert(false, "two top-level image chunks");
  }
  return assert(true, "container-kind consistency guards simple, extended and animated layouts");
}

fn t17() -> TestResult {
  var ic = Vec[UInt8].new();
  start_riff(&mut ic);
  let icx = vp8x_payload(0, 1, 1);
  push_chunk(&mut ic, 86, 80, 56, 88, icx);
  let icp = raw_bytes(2, 1);
  push_chunk(&mut ic, 73, 67, 67, 80, icp);
  push_chunk(&mut ic, 73, 67, 67, 80, icp);
  finish_riff(&mut ic);
  if (!img_err_is(webp_parse(ic), at("webp: duplicate ICCP", 40))) {
    return assert(false, "two ICCP chunks");
  }
  var ex = Vec[UInt8].new();
  start_riff(&mut ex);
  let exx = vp8x_payload(0, 1, 1);
  push_chunk(&mut ex, 86, 80, 56, 88, exx);
  let exb = vp8l_payload(1, 1, 0, 0);
  push_chunk(&mut ex, 86, 80, 56, 76, exb);
  let exp = raw_bytes(2, 1);
  push_chunk(&mut ex, 69, 88, 73, 70, exp);
  push_chunk(&mut ex, 69, 88, 73, 70, exp);
  finish_riff(&mut ex);
  if (!img_err_is(webp_parse(ex), at("webp: duplicate EXIF", 54))) {
    return assert(false, "two EXIF chunks");
  }
  var xm = Vec[UInt8].new();
  start_riff(&mut xm);
  let xmx = vp8x_payload(0, 1, 1);
  push_chunk(&mut xm, 86, 80, 56, 88, xmx);
  let xmb = vp8l_payload(1, 1, 0, 0);
  push_chunk(&mut xm, 86, 80, 56, 76, xmb);
  let xmp = raw_bytes(2, 1);
  push_chunk(&mut xm, 88, 77, 80, 32, xmp);
  push_chunk(&mut xm, 88, 77, 80, 32, xmp);
  finish_riff(&mut xm);
  if (!img_err_is(webp_parse(xm), at("webp: duplicate XMP", 54))) {
    return assert(false, "two XMP chunks");
  }
  return assert(true, "ICCP, EXIF and XMP are unique per file");
}

fn t18() -> TestResult {
  let img = ok_img(webp_parse(mk_ext(1, 3, 2, 60, 4, 2, 3, 5)));
  if (webp_chunk_count(img) != 6) { return assert(false, "fixture has six chunks"); }
  let e: Str = webp_chunk_fourcc(img, 99);
  if (string.str_len(e) != 0) { return assert(false, "fourcc above count is empty"); }
  let en: Str = webp_chunk_fourcc(img, -1);
  if (string.str_len(en) != 0) { return assert(false, "negative fourcc index is empty"); }
  if (webp_chunk_offset(img, 99) != -1) { return assert(false, "chunk offset sentinel"); }
  if (webp_chunk_size(img, 99) != -1) { return assert(false, "chunk size sentinel"); }
  if (webp_chunk_data_offset(img, 99) != -1) { return assert(false, "chunk data offset sentinel"); }
  if (webp_chunk_padding(img, 99) != -1) { return assert(false, "chunk padding sentinel"); }
  if (webp_chunk_kind(img, 99) != -1) { return assert(false, "chunk kind sentinel"); }
  if (webp_chunk_kind(img, -1) != -1) { return assert(false, "negative chunk kind"); }
  if (webp_frame_count(img) != 0) { return assert(false, "no frames in the static fixture"); }
  let anim = ok_img(webp_parse(mk_animated(4, 4, 1, 0)));
  if (webp_frame_count(anim) != 1) { return assert(false, "one frame in the animated fixture"); }
  if (webp_frame_x(anim, 99) != -1) { return assert(false, "frame x sentinel"); }
  if (webp_frame_y(anim, 99) != -1) { return assert(false, "frame y sentinel"); }
  if (webp_frame_width(anim, 99) != -1) { return assert(false, "frame width sentinel"); }
  if (webp_frame_height(anim, 99) != -1) { return assert(false, "frame height sentinel"); }
  if (webp_frame_duration(anim, 99) != -1) { return assert(false, "frame duration sentinel"); }
  if (webp_frame_blend(anim, 99) != -1) { return assert(false, "frame blend sentinel"); }
  if (webp_frame_dispose(anim, 99) != -1) { return assert(false, "frame dispose sentinel"); }
  if (webp_frame_offset(anim, 99) != -1) { return assert(false, "frame offset sentinel"); }
  if (webp_frame_size(anim, 99) != -1) { return assert(false, "frame size sentinel"); }
  if (webp_frame_format(anim, 99) != -1) { return assert(false, "frame format sentinel"); }
  if (webp_frame_data_offset(anim, 99) != -1) { return assert(false, "frame data offset sentinel"); }
  if (webp_frame_data_size(anim, 99) != -1) { return assert(false, "frame data size sentinel"); }
  if (webp_frame_has_alpha(anim, 99) != -1) { return assert(false, "frame alpha sentinel"); }
  if (webp_frame_nested_count(anim, 99) != -1) { return assert(false, "nested count sentinel"); }
  if (webp_frame_unknown_count(anim, 99) != -1) { return assert(false, "unknown count sentinel"); }
  if (webp_frame_x(anim, -1) != -1) { return assert(false, "negative frame index"); }
  if (webp_frame_duration(anim, 0) != 40) { return assert(false, "frame 0 duration 40"); }
  if (webp_anim_loop_count(anim) != 0) { return assert(false, "loop 0 means forever"); }
  if (webp_vp8_version(anim) != -1) { return assert(false, "VP8 fields absent in animation"); }
  if (webp_vp8l_alpha(anim) != -1) { return assert(false, "VP8L fields absent in animation"); }
  if (webp_image_offset(anim) != -1) { return assert(false, "no top-level image in animation"); }
  if (webp_alph_offset(img) != 42) { return assert(false, "ALPH offset"); }
  if (webp_exif_offset(img) != 70) { return assert(false, "EXIF offset"); }
  if (webp_xmp_offset(img) != 82) { return assert(false, "XMP offset"); }
  if (webp_iccp_offset(img) != 30) { return assert(false, "ICCP offset"); }
  return assert(true, "out-of-range accessors return the documented -1 and empty-Str sentinels");
}

fn t19() -> TestResult {
  if (webp_vp8x_size() != 10) { return assert(false, "VP8X size 10"); }
  if (webp_anim_size() != 6) { return assert(false, "ANIM size 6"); }
  if (webp_anmf_header_size() != 16) { return assert(false, "ANMF header 16"); }
  if (webp_max_canvas_dimension() != 16777216) { return assert(false, "24-bit canvas max"); }
  if (webp_max_dimension_14() != 16384) { return assert(false, "14-bit image max"); }
  if (webp_kind_simple() != 0) { return assert(false, "kind simple 0"); }
  if (webp_kind_extended() != 1) { return assert(false, "kind extended 1"); }
  if (webp_kind_animated() != 2) { return assert(false, "kind animated 2"); }
  if (webp_chunk_other() != 0) { return assert(false, "chunk other 0"); }
  if (webp_chunk_vp8() != 1) { return assert(false, "chunk VP8 1"); }
  if (webp_chunk_vp8l() != 2) { return assert(false, "chunk VP8L 2"); }
  if (webp_chunk_vp8x() != 3) { return assert(false, "chunk VP8X 3"); }
  if (webp_chunk_alph() != 4) { return assert(false, "chunk ALPH 4"); }
  if (webp_chunk_anim() != 5) { return assert(false, "chunk ANIM 5"); }
  if (webp_chunk_anmf() != 6) { return assert(false, "chunk ANMF 6"); }
  if (webp_chunk_iccp() != 7) { return assert(false, "chunk ICCP 7"); }
  if (webp_chunk_exif() != 8) { return assert(false, "chunk EXIF 8"); }
  if (webp_chunk_xmp() != 9) { return assert(false, "chunk XMP 9"); }
  if (webp_format_none() != 0) { return assert(false, "format none 0"); }
  if (webp_format_vp8() != 1) { return assert(false, "format VP8 1"); }
  if (webp_format_vp8l() != 2) { return assert(false, "format VP8L 2"); }
  if (webp_mask_icc() != 32) { return assert(false, "ICC mask 0x20"); }
  if (webp_mask_alpha() != 16) { return assert(false, "alpha mask 0x10"); }
  if (webp_mask_exif() != 8) { return assert(false, "EXIF mask 0x08"); }
  if (webp_mask_xmp() != 4) { return assert(false, "XMP mask 0x04"); }
  if (webp_mask_animation() != 2) { return assert(false, "animation mask 0x02"); }
  if (webp_mask_reserved() != 193) { return assert(false, "reserved mask 0xC1"); }
  if (webp_mask_anmf_reserved() != 252) { return assert(false, "ANMF reserved mask 0xFC"); }
  return assert(true, "all public constants match the byte-level specification");
}

fn t20() -> TestResult {
  let d = mk_simple_vp8(16383, 16383, 0);
  let img = ok_img(webp_parse(d));
  if (webp_image_width(img) != 16383) { return assert(false, "14-bit max width"); }
  if (webp_image_height(img) != 16383) { return assert(false, "14-bit max height"); }
  if (webp_canvas_width(img) != 16383) { return assert(false, "simple canvas follows the image"); }
  if (webp_canvas_height(img) != 16383) { return assert(false, "simple canvas height"); }
  if (webp_size(img) != 30) { return assert(false, "size 30"); }
  if (webp_riff_size(img) != webp_size(img) - 8) { return assert(false, "riff size is size-8"); }
  if (webp_chunk_offset(img, 0) != 12) { return assert(false, "first chunk at 12"); }
  if (webp_chunk_data_offset(img, 0) != 20) { return assert(false, "first data at 20"); }
  if (webp_chunk_offset(img, 0) + webp_chunk_header_size() + webp_chunk_size(img, 0) + webp_chunk_padding(img, 0) != webp_size(img)) {
    return assert(false, "chunk span reaches the end of the buffer");
  }
  let big = ok_img(webp_parse(mk_canvas_only(65535, 65536)));
  if (webp_canvas_width(big) != 65535) { return assert(false, "canvas boundary width"); }
  if (webp_canvas_height(big) != 65536) { return assert(false, "canvas boundary height"); }
  let anim = ok_img(webp_parse(mk_animated(10, 8, 2, 3)));
  var i = 0;
  var pos = 12;
  while (i < webp_chunk_count(anim)) {
    let off = webp_chunk_offset(anim, i);
    if (off != pos) { return assert(false, "chunk chain is contiguous"); }
    pos = off + webp_chunk_header_size() + webp_chunk_size(anim, i) + webp_chunk_padding(anim, i);
    i = i + 1;
  }
  if (pos != webp_size(anim)) { return assert(false, "chunk chain ends at the buffer end"); }
  if (!webp_is_webp(mk_simple_vp8l(1, 1, 0))) { return assert(false, "VP8L file is WebP"); }
  let junk = Vec[UInt8].new();
  if (webp_is_webp(junk)) { return assert(false, "empty buffer is not WebP"); }
  var riffonly = Vec[UInt8].new();
  push_fourcc(&mut riffonly, 82, 73, 70, 70);
  if (webp_is_webp(riffonly)) { return assert(false, "RIFF alone is not WebP"); }
  return assert(true, "dimension extremes, canvas boundary and the exact chunk-offset chain hold");
}

fn check(r: TestResult) -> Int {
  if (r.passed) {
    io.println("  [PASS] " + r.name);
    return 0;
  }
  io.println("  [FAIL] " + r.name + " -- " + r.message);
  return 1;
}

fn main() -> Int {
  io.println("=== xiom.webp conformance tests ===");
  var failed: Int = 0;
  failed = failed + check(t1());
  failed = failed + check(t2());
  failed = failed + check(t3());
  failed = failed + check(t4());
  failed = failed + check(t5());
  failed = failed + check(t6());
  failed = failed + check(t7());
  failed = failed + check(t8());
  failed = failed + check(t9());
  failed = failed + check(t10());
  failed = failed + check(t11());
  failed = failed + check(t12());
  failed = failed + check(t13());
  failed = failed + check(t14());
  failed = failed + check(t15());
  failed = failed + check(t16());
  failed = failed + check(t17());
  failed = failed + check(t18());
  failed = failed + check(t19());
  failed = failed + check(t20());
  if failed == 0 {
    io.println("xiom.webp: all tests passed");
  } else {
    io.println("xiom.webp: tests failed");
  }
  return failed;
}
