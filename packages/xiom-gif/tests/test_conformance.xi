// XIOM -- xiom.gif conformance tests (20 checks)
// Port task: prove the pure-XIOM xiom.gif container parser against synthetic
// GIF byte buffers (no external data files).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module gif_tests
use xiom.io; use xiom.test; use xiom.gif;
use xiom.string; use xiom.string.compare;

// All Str equality goes through str_compare: `==` on Str is unreliable in
// v0.61.3, so every expected message is compared with this helper.
fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// Unsigned byte `i` of `data` equals `want` (0..255).
fn byte_is(data: &Vec[UInt8], i: Int, want: Int) -> Bool {
  let b: Int = (data[i] as Int) & 0xFF;
  return b == want;
}

// Byte-wise equality of two vectors (widened to 0..255).
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

// ---------------------------------------------------------------------------
//  Fixture builders
// ---------------------------------------------------------------------------

fn push_u16(v: &mut Vec[UInt8], n: Int) {
  v.push((n % 256) as UInt8);
  v.push(((n / 256) % 256) as UInt8);
}

fn append(dst: &mut Vec[UInt8], src: &Vec[UInt8]) {
  var i = 0;
  while (i < src.len()) {
    let b: UInt8 = src[i];
    dst.push(b);
    i = i + 1;
  }
}

fn zeros(n: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while (i < n) {
    v.push(0 as UInt8);
    i = i + 1;
  }
  return v;
}

fn bytes6(a: Int, b: Int, c: Int, d: Int, e: Int, f: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  v.push(a as UInt8);
  v.push(b as UInt8);
  v.push(c as UInt8);
  v.push(d as UInt8);
  v.push(e as UInt8);
  v.push(f as UInt8);
  return v;
}

fn sig87() -> Vec[UInt8] {
  return bytes6(71, 73, 70, 56, 55, 97);
}

fn sig89() -> Vec[UInt8] {
  return bytes6(71, 73, 70, 56, 57, 97);
}

fn lsd(w: Int, h: Int, packed: Int, bg: Int, aspect: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  push_u16(&mut v, w);
  push_u16(&mut v, h);
  v.push(packed as UInt8);
  v.push(bg as UInt8);
  v.push(aspect as UInt8);
  return v;
}

// Four RGB entries: (1,2,3), (4,5,6), (7,8,9), (10,11,12).
fn gct4() -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  v.push(1 as UInt8);
  v.push(2 as UInt8);
  v.push(3 as UInt8);
  v.push(4 as UInt8);
  v.push(5 as UInt8);
  v.push(6 as UInt8);
  v.push(7 as UInt8);
  v.push(8 as UInt8);
  v.push(9 as UInt8);
  v.push(10 as UInt8);
  v.push(11 as UInt8);
  v.push(12 as UInt8);
  return v;
}

// 10-byte image descriptor with no local color table bytes.
fn image_head(left: Int, top: Int, w: Int, h: Int, packed: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  v.push(44 as UInt8);
  push_u16(&mut v, left);
  push_u16(&mut v, top);
  push_u16(&mut v, w);
  push_u16(&mut v, h);
  v.push(packed as UInt8);
  return v;
}

// Complete image block: descriptor, code size, one sub-block (when the
// payload is non-empty) and the 0x00 terminator.
fn image(left: Int, top: Int, w: Int, h: Int, packed: Int, min: Int, payload: &Vec[UInt8]) -> Vec[UInt8] {
  var v = image_head(left, top, w, h, packed);
  v.push(min as UInt8);
  if (payload.len() > 0) {
    v.push(payload.len() as UInt8);
    append(&mut v, payload);
  }
  v.push(0 as UInt8);
  return v;
}

// Graphic control extension: 0x21 0xF9 0x04 packed delay(LE16) index 0x00.
fn gce(packed: Int, delay: Int, ti: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  v.push(33 as UInt8);
  v.push(249 as UInt8);
  v.push(4 as UInt8);
  v.push(packed as UInt8);
  push_u16(&mut v, delay);
  v.push(ti as UInt8);
  v.push(0 as UInt8);
  return v;
}

// Comment extension carrying `text` (empty text writes just the terminator).
fn comment(text: &Vec[UInt8]) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  v.push(33 as UInt8);
  v.push(254 as UInt8);
  if (text.len() > 0) {
    v.push(text.len() as UInt8);
    append(&mut v, text);
  }
  v.push(0 as UInt8);
  return v;
}

// Application extension: 11-byte identifier plus sub-block data.
fn app(id8: &Vec[UInt8], auth3: &Vec[UInt8], data: &Vec[UInt8]) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  v.push(33 as UInt8);
  v.push(255 as UInt8);
  v.push(11 as UInt8);
  append(&mut v, id8);
  append(&mut v, auth3);
  if (data.len() > 0) {
    v.push(data.len() as UInt8);
    append(&mut v, data);
  }
  v.push(0 as UInt8);
  return v;
}

// NETSCAPE2.0 loop extension: data 01 <loop LE16>.
fn netscape(loop_count: Int) -> Vec[UInt8] {
  var id8 = bytes6(78, 69, 84, 83, 67, 65);
  id8.push(80 as UInt8);
  id8.push(69 as UInt8);
  var auth3 = Vec[UInt8].new();
  auth3.push(50 as UInt8);
  auth3.push(46 as UInt8);
  auth3.push(48 as UInt8);
  var data = Vec[UInt8].new();
  data.push(1 as UInt8);
  push_u16(&mut data, loop_count);
  return app(id8, auth3, data);
}

// Plain text extension: 12-byte header plus sub-block text.
fn plain_text(hdr: &Vec[UInt8], text: &Vec[UInt8]) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  v.push(33 as UInt8);
  v.push(1 as UInt8);
  v.push(12 as UInt8);
  append(&mut v, hdr);
  if (text.len() > 0) {
    v.push(text.len() as UInt8);
    append(&mut v, text);
  }
  v.push(0 as UInt8);
  return v;
}

// Deterministic 300-byte-capable payload: byte i is (i * 7 + 3) % 256.
fn pattern(n: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while (i < n) {
    v.push(((i * 7 + 3) % 256) as UInt8);
    i = i + 1;
  }
  return v;
}

// ---------------------------------------------------------------------------
//  Result helpers
// ---------------------------------------------------------------------------

fn empty_gif() -> Gif {
  return Gif{
    version: 0; width: 0; height: 0; packed: 0; has_gct: 0;
    color_resolution: 0; sort_flag: 0; gct_size: 0; bg_index: 0; aspect: 0;
    gct_bytes: Vec[UInt8].new();
    frame_left: Vec[Int].new();
    frame_top: Vec[Int].new();
    frame_width: Vec[Int].new();
    frame_height: Vec[Int].new();
    frame_interlace: Vec[Int].new();
    frame_has_lct: Vec[Int].new();
    frame_lct_size: Vec[Int].new();
    frame_lct_off: Vec[Int].new();
    frame_lct_len: Vec[Int].new();
    frame_lzw_min: Vec[Int].new();
    frame_lzw_min_off: Vec[Int].new();
    frame_data_off: Vec[Int].new();
    frame_data_len: Vec[Int].new();
    frame_block_end: Vec[Int].new();
    frame_pay_off: Vec[Int].new();
    frame_delay: Vec[Int].new();
    frame_disposal: Vec[Int].new();
    frame_user_input: Vec[Int].new();
    frame_transparent: Vec[Int].new();
    frame_trans_index: Vec[Int].new();
    frame_from_gce: Vec[Int].new();
    payload: Vec[UInt8].new();
    lct_bytes: Vec[UInt8].new();
    ext_kind: Vec[Int].new();
    ext_offset: Vec[Int].new();
    ext_hdr_off: Vec[Int].new();
    ext_hdr_len: Vec[Int].new();
    ext_data_off: Vec[Int].new();
    ext_data_len: Vec[Int].new();
    ext_bytes: Vec[UInt8].new();
  };
}

fn ok_gif(r: Result[Gif, Str]) -> Gif {
  match r {
    Ok(v) => { return v; },
    Err(e) => { return empty_gif(); },
  }
}

fn gif_err_is(r: Result[Gif, Str], want: Str) -> Bool {
  match r {
    Ok(v) => { return false; },
    Err(e) => { return streq(e, want); },
  }
}

fn empty_frame() -> GifFrame {
  return GifFrame{
    index: 0; left: 0; top: 0; width: 0; height: 0; interlace: 0;
    has_lct: 0; lct_size: 0; lzw_min: 0; lzw_min_offset: 0;
    data_offset: 0; data_bytes: 0; block_end: 0; delay: 0; disposal: 0;
    user_input: 0; transparent: 0; trans_index: 0; from_gce: 0;
  };
}

fn ok_frame(r: Result[GifFrame, Str]) -> GifFrame {
  match r {
    Ok(v) => { return v; },
    Err(e) => { return empty_frame(); },
  }
}

fn frame_err_is(r: Result[GifFrame, Str], want: Str) -> Bool {
  match r {
    Ok(v) => { return false; },
    Err(e) => { return streq(e, want); },
  }
}

fn empty_ext() -> GifExtension {
  return GifExtension{
    index: 0; kind: 0; offset: 0; hdr_offset: 0; hdr_size: 0;
    data_offset: 0; data_size: 0;
  };
}

fn ok_ext(r: Result[GifExtension, Str]) -> GifExtension {
  match r {
    Ok(v) => { return v; },
    Err(e) => { return empty_ext(); },
  }
}

fn ext_err_is(r: Result[GifExtension, Str], want: Str) -> Bool {
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

// ---------------------------------------------------------------------------
//  Fixtures used by several checks
// ---------------------------------------------------------------------------

// 51 bytes: 89a, 10x20 screen, 4-entry GCT at 13, GCE at 25, one 2x2 frame
// at 33 (code size at 43, sub-block at 44, payload 45..48, terminator at 49),
// trailer at 50.
fn fixture_single() -> Vec[UInt8] {
  var d = sig89();
  append(&mut d, lsd(10, 20, 145, 2, 49));
  append(&mut d, gct4());
  append(&mut d, gce(11, 7, 1));
  let payload = pattern(4);
  append(&mut d, image(1, 2, 2, 2, 0, 2, payload));
  d.push(59 as UInt8);
  return d;
}

// 85 bytes: 89a, 4x4 screen, 2-entry GCT at 13, NETSCAPE loop 5 at 19,
// GCE at 38, frame at 46 (code size 56), GCE at 61, frame at 69 (code size
// 79), trailer at 84.
fn fixture_anim() -> Vec[UInt8] {
  var d = sig89();
  append(&mut d, lsd(4, 4, 128, 1, 0));
  let gct2 = bytes6(1, 2, 3, 4, 5, 6);
  append(&mut d, gct2);
  append(&mut d, netscape(5));
  append(&mut d, gce(4, 10, 0));
  var p1b = Vec[UInt8].new();
  p1b.push(9 as UInt8);
  p1b.push(8 as UInt8);
  append(&mut d, image(0, 0, 2, 1, 0, 2, p1b));
  append(&mut d, gce(11, 20, 5));
  var p2b = Vec[UInt8].new();
  p2b.push(7 as UInt8);
  p2b.push(6 as UInt8);
  append(&mut d, image(0, 0, 2, 1, 0, 2, p2b));
  d.push(59 as UInt8);
  return d;
}

// 13-byte 87a header plus a no-table screen descriptor, the prefix shared by
// the malformed-stream checks.
fn base87() -> Vec[UInt8] {
  var v = sig87();
  append(&mut v, lsd(1, 1, 0, 0, 0));
  return v;
}

// 23-byte prefix: base87 plus a 1x1 image descriptor with no local table.
fn base87_head() -> Vec[UInt8] {
  var v = base87();
  append(&mut v, image_head(0, 0, 1, 1, 0));
  return v;
}

// ---------------------------------------------------------------------------
//  Tests
// ---------------------------------------------------------------------------

fn t1() -> TestResult {
  var d = sig87();
  append(&mut d, lsd(0, 0, 0, 0, 0));
  d.push(59 as UInt8);
  if (d.len() != 14) { return assert(false, "minimal 87a fixture is 14 bytes"); }
  let g = ok_gif(gif_parse(d));
  if (gif_version(&g) != 87) { return assert(false, "version is 87a"); }
  if (gif_version(&g) != GIF_VERSION_87A) { return assert(false, "87a constant matches"); }
  if (gif_width(&g) != 0) { return assert(false, "width 0"); }
  if (gif_height(&g) != 0) { return assert(false, "height 0"); }
  if (gif_has_gct(&g)) { return assert(false, "no global color table flag"); }
  if (gif_gct_size(&g) != 0) { return assert(false, "gct size 0"); }
  if (gif_color_resolution(&g) != 0) { return assert(false, "color resolution 0"); }
  if (gif_sort_flag(&g) != 0) { return assert(false, "sort flag 0"); }
  if (gif_bg_index(&g) != 0) { return assert(false, "background index 0"); }
  if (gif_aspect(&g) != 0) { return assert(false, "aspect 0"); }
  if (gif_frame_count(&g) != 0) { return assert(false, "frame count 0"); }
  if (gif_extension_count(&g) != 0) { return assert(false, "extension count 0"); }
  if (gif_is_animated(&g)) { return assert(false, "not animated"); }
  var d2 = sig87();
  append(&mut d2, lsd(320, 200, 112, 5, 49));
  d2.push(59 as UInt8);
  let g2 = ok_gif(gif_parse(d2));
  if (gif_width(&g2) != 320) { return assert(false, "width 320"); }
  if (gif_height(&g2) != 200) { return assert(false, "height 200"); }
  if (gif_color_resolution(&g2) != 7) { return assert(false, "color resolution 7"); }
  if (gif_sort_flag(&g2) != 0) { return assert(false, "sort flag clear in 0x70"); }
  if (gif_bg_index(&g2) != 5) { return assert(false, "background index 5"); }
  if (gif_aspect(&g2) != 49) { return assert(false, "aspect byte 49"); }
  return assert(true, "a trailer-only 87a stream exposes the full canvas header");
}

fn t2() -> TestResult {
  let d = fixture_single();
  if (d.len() != 51) { return assert(false, "single-frame fixture is 51 bytes"); }
  let g = ok_gif(gif_parse(d));
  if (gif_version(&g) != 89) { return assert(false, "version is 89a"); }
  if (gif_width(&g) != 10) { return assert(false, "canvas width 10"); }
  if (gif_height(&g) != 20) { return assert(false, "canvas height 20"); }
  if (!gif_has_gct(&g)) { return assert(false, "global color table present"); }
  if (gif_color_resolution(&g) != 1) { return assert(false, "color resolution 1"); }
  if (gif_gct_size(&g) != 4) { return assert(false, "four global colors"); }
  if (gif_global_color(&g, 0) != 66051) { return assert(false, "global color 0 is 010203"); }
  if (gif_global_color(&g, 1) != 263430) { return assert(false, "global color 1 is 040506"); }
  if (gif_global_color(&g, 3) != 658188) { return assert(false, "global color 3 is 0A0B0C"); }
  if (gif_bg_index(&g) != 2) { return assert(false, "background index 2"); }
  if (gif_aspect(&g) != 49) { return assert(false, "aspect byte 49"); }
  if (gif_frame_count(&g) != 1) { return assert(false, "one frame"); }
  if (gif_extension_count(&g) != 1) { return assert(false, "one extension"); }
  let f = ok_frame(gif_frame(&g, 0));
  if (f.left != 1 || f.top != 2 || f.width != 2 || f.height != 2) {
    return assert(false, "frame geometry 1,2 2x2");
  }
  if (f.interlace != 0) { return assert(false, "frame is not interlaced"); }
  if (f.has_lct != 0 || f.lct_size != 0) { return assert(false, "frame has no local table"); }
  if (f.lzw_min != 2) { return assert(false, "code size 2"); }
  if (f.lzw_min_offset != 43) { return assert(false, "code size byte at 43"); }
  if (f.data_offset != 44) { return assert(false, "sub-block at 44"); }
  if (f.data_bytes != 4) { return assert(false, "four payload bytes"); }
  if (f.block_end != 50) { return assert(false, "block ends at the trailer"); }
  if (f.delay != 7) { return assert(false, "delay 7"); }
  if (f.disposal != 2) { return assert(false, "disposal 2"); }
  if (f.user_input != 1) { return assert(false, "user input flag"); }
  if (f.transparent != 1) { return assert(false, "transparency flag"); }
  if (f.trans_index != 1) { return assert(false, "transparent index 1"); }
  if (f.from_gce != 1) { return assert(false, "graphic control applied"); }
  let want = pattern(4);
  let got = ok_bytes(gif_lzw_data(&g, 0));
  if (!vec_eq(got, want)) { return assert(false, "opaque payload bytes"); }
  let e = ok_ext(gif_extension(&g, 0));
  if (e.kind != GIF_EXT_KIND_CONTROL) { return assert(false, "extension kind control"); }
  if (e.offset != 25) { return assert(false, "extension at 25"); }
  if (e.hdr_size != 4 || e.data_size != 0) { return assert(false, "GCE header 4, data 0"); }
  if (gif_extension_header_byte(&g, 0, 0) != 11) { return assert(false, "GCE packed byte"); }
  if (gif_extension_header_byte(&g, 0, 1) != 7) { return assert(false, "GCE delay low byte"); }
  if (gif_extension_header_byte(&g, 0, 2) != 0) { return assert(false, "GCE delay high byte"); }
  if (gif_extension_header_byte(&g, 0, 3) != 1) { return assert(false, "GCE transparent index"); }
  if (!byte_is(d, 50, 59)) { return assert(false, "trailer byte at 50"); }
  return assert(true, "89a single-frame canvas, table, frame metadata and GCE decode");
}

fn t3() -> TestResult {
  let d = fixture_anim();
  if (d.len() != 85) { return assert(false, "animation fixture is 85 bytes"); }
  let g = ok_gif(gif_parse(d));
  if (gif_frame_count(&g) != 2) { return assert(false, "two frames"); }
  if (!gif_is_animated(&g)) { return assert(false, "animated"); }
  if (gif_extension_count(&g) != 3) { return assert(false, "three extensions"); }
  if (gif_gct_size(&g) != 2) { return assert(false, "two global colors"); }
  if (gif_application_loop_count(&g, 0) != 5) { return assert(false, "NETSCAPE loop count 5"); }
  if (gif_extension_data_byte(&g, 0, 0) != 1) { return assert(false, "loop data starts with 1"); }
  if (gif_extension_data_byte(&g, 0, 1) != 5) { return assert(false, "loop count low byte 5"); }
  if (gif_extension_data_byte(&g, 0, 2) != 0) { return assert(false, "loop count high byte 0"); }
  if (gif_extension_header_byte(&g, 0, 0) != 78) { return assert(false, "application id 'N'"); }
  if (gif_extension_header_byte(&g, 0, 10) != 48) { return assert(false, "auth code '0'"); }
  let e0 = ok_ext(gif_extension(&g, 0));
  let e1 = ok_ext(gif_extension(&g, 1));
  let e2 = ok_ext(gif_extension(&g, 2));
  if (e0.kind != GIF_EXT_KIND_APPLICATION || e0.offset != 19) {
    return assert(false, "application extension at 19");
  }
  if (e1.kind != GIF_EXT_KIND_CONTROL || e1.offset != 38) {
    return assert(false, "first GCE at 38");
  }
  if (e2.kind != GIF_EXT_KIND_CONTROL || e2.offset != 61) {
    return assert(false, "second GCE at 61");
  }
  if (gif_frame_delay(&g, 0) != 10) { return assert(false, "frame 0 delay 10"); }
  if (gif_frame_delay(&g, 1) != 20) { return assert(false, "frame 1 delay 20"); }
  if (gif_frame_disposal(&g, 0) != 1) { return assert(false, "frame 0 disposal 1"); }
  if (gif_frame_disposal(&g, 1) != 2) { return assert(false, "frame 1 disposal 2"); }
  if (gif_frame_transparent(&g, 0) != 0) { return assert(false, "frame 0 opaque"); }
  if (gif_frame_transparent(&g, 1) != 1) { return assert(false, "frame 1 transparent"); }
  if (gif_frame_trans_index(&g, 1) != 5) { return assert(false, "frame 1 transparent index 5"); }
  let f0 = ok_frame(gif_frame(&g, 0));
  let f1 = ok_frame(gif_frame(&g, 1));
  if (f0.lzw_min_offset != 56 || f0.data_offset != 57 || f0.block_end != 61) {
    return assert(false, "frame 0 offset chain 56/57/61");
  }
  if (f1.lzw_min_offset != 79 || f1.data_offset != 80 || f1.block_end != 84) {
    return assert(false, "frame 1 offset chain 79/80/84");
  }
  if (f1.user_input != 1) { return assert(false, "frame 1 user input flag"); }
  let p0 = ok_bytes(gif_lzw_data(&g, 0));
  let p1 = ok_bytes(gif_lzw_data(&g, 1));
  if (!byte_is(p0, 0, 9) || !byte_is(p0, 1, 8)) { return assert(false, "frame 0 payload 9,8"); }
  if (!byte_is(p1, 0, 7) || !byte_is(p1, 1, 6)) { return assert(false, "frame 1 payload 7,6"); }
  if (!byte_is(d, 84, 59)) { return assert(false, "trailer byte at 84"); }
  return assert(true, "two-frame animation, NETSCAPE loop and per-frame GCE metadata");
}

fn t4() -> TestResult {
  var d = sig89();
  append(&mut d, lsd(2, 2, 0, 0, 0));
  append(&mut d, image_head(0, 0, 2, 2, 192));
  let lct = bytes6(200, 201, 202, 203, 204, 205);
  append(&mut d, lct);
  d.push(2 as UInt8);
  d.push(2 as UInt8);
  d.push(1 as UInt8);
  d.push(2 as UInt8);
  d.push(0 as UInt8);
  d.push(59 as UInt8);
  if (d.len() != 35) { return assert(false, "LCT fixture is 35 bytes"); }
  let g = ok_gif(gif_parse(d));
  if (gif_frame_count(&g) != 1) { return assert(false, "one frame"); }
  if (gif_gct_size(&g) != 0) { return assert(false, "no global table"); }
  if (gif_global_color(&g, 0) != -1) { return assert(false, "global lookup fails"); }
  let f = ok_frame(gif_frame(&g, 0));
  if (f.has_lct != 1) { return assert(false, "local table flag"); }
  if (f.lct_size != 2) { return assert(false, "two local colors"); }
  if (f.interlace != 1) { return assert(false, "interlace flag"); }
  if (f.lzw_min_offset != 29) { return assert(false, "code size byte at 29"); }
  if (f.data_offset != 30) { return assert(false, "sub-block at 30"); }
  if (f.block_end != 34) { return assert(false, "block ends at the trailer"); }
  if (gif_local_color_count(&g, 0) != 2) { return assert(false, "local color count 2"); }
  if (gif_local_color(&g, 0, 0) != 13158858) { return assert(false, "local color 0 is C8C9CA"); }
  if (gif_local_color(&g, 0, 1) != 13356237) { return assert(false, "local color 1 is CBCCCD"); }
  if (gif_local_color(&g, 0, 2) != -1) { return assert(false, "local index 2 out of range"); }
  if (gif_local_color(&g, 0, -1) != -1) { return assert(false, "negative local index"); }
  if (!byte_is(d, 34, 59)) { return assert(false, "trailer byte at 34"); }
  return assert(true, "local color table and interlace flag decode without a global table");
}

fn t5() -> TestResult {
  var d = sig87();
  append(&mut d, lsd(1, 1, 0, 0, 0));
  append(&mut d, gce(12, 4, 0));
  var p1 = Vec[UInt8].new();
  p1.push(5 as UInt8);
  append(&mut d, image(1, 1, 1, 1, 0, 2, p1));
  var p2 = Vec[UInt8].new();
  p2.push(6 as UInt8);
  append(&mut d, image(2, 2, 1, 1, 0, 2, p2));
  append(&mut d, gce(4, 9, 0));
  d.push(59 as UInt8);
  if (d.len() != 58) { return assert(false, "GCE-scope fixture is 58 bytes"); }
  let g = ok_gif(gif_parse(d));
  if (gif_version(&g) != 87) { return assert(false, "87a version is preserved"); }
  if (gif_has_gct(&g)) { return assert(false, "no global table"); }
  if (gif_frame_count(&g) != 2) { return assert(false, "two frames"); }
  if (gif_extension_count(&g) != 2) { return assert(false, "two GCE records"); }
  if (gif_frame_delay(&g, 0) != 4) { return assert(false, "frame 0 delay 4"); }
  if (gif_frame_disposal(&g, 0) != 3) { return assert(false, "frame 0 disposal 3"); }
  let f0 = ok_frame(gif_frame(&g, 0));
  if (f0.from_gce != 1) { return assert(false, "frame 0 saw a GCE"); }
  if (gif_frame_delay(&g, 1) != 0) { return assert(false, "frame 1 delay resets to 0"); }
  if (gif_frame_disposal(&g, 1) != 0) { return assert(false, "frame 1 disposal resets to 0"); }
  if (gif_frame_transparent(&g, 1) != 0) { return assert(false, "frame 1 stays opaque"); }
  let f1 = ok_frame(gif_frame(&g, 1));
  if (f1.from_gce != 0) { return assert(false, "frame 1 saw no GCE"); }
  let e0 = ok_ext(gif_extension(&g, 0));
  let e1 = ok_ext(gif_extension(&g, 1));
  if (e0.offset != 13) { return assert(false, "first GCE at 13"); }
  if (e1.offset != 49) { return assert(false, "dangling GCE at 49 is recorded"); }
  if (!byte_is(d, 57, 59)) { return assert(false, "trailer byte at 57"); }
  return assert(true, "a GCE applies to the next frame only and resets afterwards");
}

fn t6() -> TestResult {
  var d = sig89();
  append(&mut d, lsd(1, 1, 0, 0, 0));
  var hello = Vec[UInt8].new();
  hello.push(104 as UInt8);
  hello.push(101 as UInt8);
  hello.push(108 as UInt8);
  hello.push(108 as UInt8);
  hello.push(111 as UInt8);
  append(&mut d, comment(hello));
  var empty = Vec[UInt8].new();
  append(&mut d, comment(empty));
  var p = Vec[UInt8].new();
  p.push(1 as UInt8);
  append(&mut d, image(0, 0, 1, 1, 0, 2, p));
  d.push(59 as UInt8);
  if (d.len() != 40) { return assert(false, "comment fixture is 40 bytes"); }
  let g = ok_gif(gif_parse(d));
  if (gif_extension_count(&g) != 2) { return assert(false, "two comments"); }
  let e0 = ok_ext(gif_extension(&g, 0));
  let e1 = ok_ext(gif_extension(&g, 1));
  if (e0.kind != GIF_EXT_KIND_COMMENT || e0.offset != 13) {
    return assert(false, "comment at 13");
  }
  if (e0.hdr_size != 0) { return assert(false, "comment has no fixed header"); }
  if (e0.data_size != 5) { return assert(false, "comment data is 5 bytes"); }
  if (e1.offset != 22 || e1.data_size != 0) {
    return assert(false, "empty comment at 22");
  }
  if (gif_extension_data_byte(&g, 0, 0) != 104) { return assert(false, "comment 'h'"); }
  if (gif_extension_data_byte(&g, 0, 4) != 111) { return assert(false, "comment 'o'"); }
  if (gif_extension_data_byte(&g, 0, 5) != -1) { return assert(false, "comment end sentinel"); }
  if (gif_extension_header_byte(&g, 0, 0) != -1) {
    return assert(false, "comment has no header bytes");
  }
  let got = ok_bytes(gif_extension_data_copy(&g, 0));
  if (!vec_eq(got, hello)) { return assert(false, "comment text copy"); }
  let got1 = ok_bytes(gif_extension_data_copy(&g, 1));
  if (got1.len() != 0) { return assert(false, "empty comment copies zero bytes"); }
  return assert(true, "comment extensions concatenate their sub-blocks and keep the order");
}

fn t7() -> TestResult {
  var d = sig89();
  append(&mut d, lsd(1, 1, 0, 0, 0));
  var hdr = Vec[UInt8].new();
  push_u16(&mut hdr, 1);
  push_u16(&mut hdr, 2);
  push_u16(&mut hdr, 3);
  push_u16(&mut hdr, 4);
  hdr.push(5 as UInt8);
  hdr.push(6 as UInt8);
  hdr.push(7 as UInt8);
  hdr.push(8 as UInt8);
  var text = Vec[UInt8].new();
  text.push(111 as UInt8);
  text.push(107 as UInt8);
  append(&mut d, plain_text(hdr, text));
  var p = Vec[UInt8].new();
  p.push(1 as UInt8);
  append(&mut d, image(0, 0, 1, 1, 0, 2, p));
  d.push(59 as UInt8);
  if (d.len() != 47) { return assert(false, "plain text fixture is 47 bytes"); }
  let g = ok_gif(gif_parse(d));
  let e = ok_ext(gif_extension(&g, 0));
  if (e.kind != GIF_EXT_KIND_PLAIN_TEXT || e.offset != 13) {
    return assert(false, "plain text at 13");
  }
  if (e.hdr_size != 12 || e.data_size != 2) {
    return assert(false, "plain text header 12, data 2");
  }
  if (gif_extension_header_byte(&g, 0, 0) != 1) { return assert(false, "grid left low byte 1"); }
  if (gif_extension_header_byte(&g, 0, 2) != 2) { return assert(false, "grid top low byte 2"); }
  if (gif_extension_header_byte(&g, 0, 4) != 3) { return assert(false, "grid width low byte 3"); }
  if (gif_extension_header_byte(&g, 0, 8) != 5) { return assert(false, "cell width 5"); }
  if (gif_extension_header_byte(&g, 0, 9) != 6) { return assert(false, "cell height 6"); }
  if (gif_extension_header_byte(&g, 0, 10) != 7) { return assert(false, "foreground index 7"); }
  if (gif_extension_header_byte(&g, 0, 11) != 8) { return assert(false, "background index 8"); }
  if (gif_extension_data_byte(&g, 0, 0) != 111) { return assert(false, "text 'o'"); }
  if (gif_extension_data_byte(&g, 0, 1) != 107) { return assert(false, "text 'k'"); }
  var bad = sig89();
  append(&mut bad, lsd(1, 1, 0, 0, 0));
  bad.push(33 as UInt8);
  bad.push(1 as UInt8);
  bad.push(11 as UInt8);
  append(&mut bad, zeros(20));
  if (!gif_err_is(gif_parse(bad), "gif: malformed plain text extension at offset 13")) {
    return assert(false, "plain text block size must be 12");
  }
  var cut = sig89();
  append(&mut cut, lsd(1, 1, 0, 0, 0));
  cut.push(33 as UInt8);
  cut.push(1 as UInt8);
  cut.push(12 as UInt8);
  cut.push(1 as UInt8);
  cut.push(2 as UInt8);
  cut.push(3 as UInt8);
  if (!gif_err_is(gif_parse(cut), "gif: malformed plain text extension at offset 13")) {
    return assert(false, "truncated plain text body is malformed");
  }
  var no_term = sig89();
  append(&mut no_term, lsd(1, 1, 0, 0, 0));
  no_term.push(33 as UInt8);
  no_term.push(1 as UInt8);
  no_term.push(12 as UInt8);
  append(&mut no_term, hdr);
  if (!gif_err_is(gif_parse(no_term), "gif: truncated extension sub-block at offset 28")) {
    return assert(false, "missing text terminator is reported at 28");
  }
  return assert(true, "plain text extensions expose their 12-byte header and text bytes");
}

fn t8() -> TestResult {
  var d = sig89();
  append(&mut d, lsd(1, 1, 0, 0, 0));
  var id8 = bytes6(65, 66, 67, 68, 69, 70);
  id8.push(71 as UInt8);
  id8.push(72 as UInt8);
  var auth = Vec[UInt8].new();
  auth.push(49 as UInt8);
  auth.push(46 as UInt8);
  auth.push(48 as UInt8);
  var data = Vec[UInt8].new();
  data.push(9 as UInt8);
  data.push(8 as UInt8);
  append(&mut d, app(id8, auth, data));
  var p = Vec[UInt8].new();
  p.push(1 as UInt8);
  append(&mut d, image(0, 0, 1, 1, 0, 2, p));
  d.push(59 as UInt8);
  if (d.len() != 46) { return assert(false, "application fixture is 46 bytes"); }
  let g = ok_gif(gif_parse(d));
  let e = ok_ext(gif_extension(&g, 0));
  if (e.kind != GIF_EXT_KIND_APPLICATION || e.offset != 13) {
    return assert(false, "application at 13");
  }
  if (e.hdr_size != 11 || e.data_size != 2) {
    return assert(false, "application header 11, data 2");
  }
  if (gif_extension_header_byte(&g, 0, 0) != 65) { return assert(false, "id starts with 'A'"); }
  if (gif_extension_header_byte(&g, 0, 7) != 72) { return assert(false, "id ends with 'H'"); }
  if (gif_extension_header_byte(&g, 0, 8) != 49) { return assert(false, "auth '1'"); }
  if (gif_extension_header_byte(&g, 0, 10) != 48) { return assert(false, "auth '0'"); }
  if (gif_extension_data_byte(&g, 0, 0) != 9) { return assert(false, "app data 9"); }
  if (gif_extension_data_byte(&g, 0, 1) != 8) { return assert(false, "app data 8"); }
  if (gif_application_loop_count(&g, 0) != -1) {
    return assert(false, "a non-NETSCAPE application has no loop count");
  }
  var ns = sig89();
  append(&mut ns, lsd(1, 1, 0, 0, 0));
  var short_id = bytes6(78, 69, 84, 83, 67, 65);
  short_id.push(80 as UInt8);
  short_id.push(69 as UInt8);
  var short_auth = Vec[UInt8].new();
  short_auth.push(50 as UInt8);
  short_auth.push(46 as UInt8);
  short_auth.push(48 as UInt8);
  var short_data = Vec[UInt8].new();
  short_data.push(1 as UInt8);
  short_data.push(5 as UInt8);
  append(&mut ns, app(short_id, short_auth, short_data));
  var p2 = Vec[UInt8].new();
  p2.push(1 as UInt8);
  append(&mut ns, image(0, 0, 1, 1, 0, 2, p2));
  ns.push(59 as UInt8);
  let g2 = ok_gif(gif_parse(ns));
  if (gif_application_loop_count(&g2, 0) != -1) {
    return assert(false, "a 2-byte NETSCAPE payload has no loop count");
  }
  if (gif_application_loop_count(&g2, 9) != -1) {
    return assert(false, "out-of-range extension has no loop count");
  }
  return assert(true, "application extensions expose id, auth and data; loops need NETSCAPE2.0");
}

fn t9() -> TestResult {
  var empty = Vec[UInt8].new();
  if (!gif_err_is(gif_parse(empty), "gif: truncated header at offset 0")) {
    return assert(false, "empty input");
  }
  var four = Vec[UInt8].new();
  four.push(71 as UInt8);
  four.push(73 as UInt8);
  four.push(70 as UInt8);
  four.push(56 as UInt8);
  if (!gif_err_is(gif_parse(four), "gif: truncated header at offset 4")) {
    return assert(false, "four-byte input");
  }
  var five = Vec[UInt8].new();
  five.push(71 as UInt8);
  five.push(73 as UInt8);
  five.push(70 as UInt8);
  five.push(56 as UInt8);
  five.push(55 as UInt8);
  if (!gif_err_is(gif_parse(five), "gif: truncated header at offset 5")) {
    return assert(false, "five-byte input");
  }
  let badver = bytes6(71, 73, 70, 56, 55, 120);
  if (!gif_err_is(gif_parse(badver), "gif: bad version at offset 3")) {
    return assert(false, "GIF87x has a bad version");
  }
  var badsig = bytes6(88, 73, 70, 56, 57, 97);
  append(&mut badsig, lsd(1, 1, 0, 0, 0));
  badsig.push(59 as UInt8);
  if (!gif_err_is(gif_parse(badsig), "gif: bad signature at offset 0")) {
    return assert(false, "XIF89a has a bad signature");
  }
  let badver2 = bytes6(71, 73, 70, 57, 48, 97);
  if (!gif_err_is(gif_parse(badver2), "gif: bad version at offset 3")) {
    return assert(false, "GIF90a has a bad version");
  }
  let header_only = sig87();
  if (!gif_err_is(gif_parse(header_only), "gif: truncated screen descriptor at offset 6")) {
    return assert(false, "header without a screen descriptor");
  }
  var twelve = sig87();
  append(&mut twelve, zeros(6));
  if (!gif_err_is(gif_parse(twelve), "gif: truncated screen descriptor at offset 6")) {
    return assert(false, "twelve-byte input");
  }
  return assert(true, "header, signature and version failures carry exact offsets");
}

fn t10() -> TestResult {
  var trunc = sig89();
  append(&mut trunc, lsd(1, 1, 135, 0, 0));
  append(&mut trunc, zeros(100));
  if (!gif_err_is(gif_parse(trunc), "gif: truncated global color table at offset 13")) {
    return assert(false, "100 bytes cannot hold a 256-entry table");
  }
  var small = sig89();
  append(&mut small, lsd(1, 1, 128, 0, 0));
  let gct2 = bytes6(1, 2, 3, 4, 5, 6);
  append(&mut small, gct2);
  small.push(59 as UInt8);
  if (small.len() != 20) { return assert(false, "2-entry table fixture is 20 bytes"); }
  let g = ok_gif(gif_parse(small));
  if (gif_gct_size(&g) != 2) { return assert(false, "2-entry table accepted"); }
  if (gif_global_color(&g, 1) != 263430) { return assert(false, "second global color"); }
  var full = sig89();
  append(&mut full, lsd(1, 1, 135, 0, 0));
  append(&mut full, zeros(768));
  full.push(59 as UInt8);
  if (full.len() != 782) { return assert(false, "256-entry table fixture is 782 bytes"); }
  let g2 = ok_gif(gif_parse(full));
  if (gif_gct_size(&g2) != 256) { return assert(false, "256-entry table accepted"); }
  if (gif_global_color(&g2, 255) != 0) { return assert(false, "last table entry reads"); }
  if (gif_global_color(&g2, 256) != -1) { return assert(false, "entry 256 is out of range"); }
  return assert(true, "the global color table is measured from its packed exponent and bounded");
}

fn t11() -> TestResult {
  var cut = base87();
  cut.push(44 as UInt8);
  cut.push(1 as UInt8);
  cut.push(0 as UInt8);
  cut.push(2 as UInt8);
  if (cut.len() != 17) { return assert(false, "truncated descriptor fixture is 17 bytes"); }
  if (!gif_err_is(gif_parse(cut), "gif: truncated image descriptor at offset 13")) {
    return assert(false, "four descriptor bytes are too few");
  }
  var complete = base87();
  append(&mut complete, image_head(1, 2, 1, 1, 0));
  if (complete.len() != 23) { return assert(false, "descriptor-only fixture is 23 bytes"); }
  if (!gif_err_is(gif_parse(complete), "gif: truncated lzw code size at offset 23")) {
    return assert(false, "descriptor without a code size byte");
  }
  return assert(true, "truncated image descriptors and missing code size bytes are located");
}

fn t12() -> TestResult {
  var d = sig87();
  append(&mut d, lsd(1, 1, 0, 0, 0));
  append(&mut d, image_head(0, 0, 1, 1, 128));
  append(&mut d, zeros(4));
  if (d.len() != 27) { return assert(false, "truncated LCT fixture is 27 bytes"); }
  if (!gif_err_is(gif_parse(d), "gif: truncated local color table at offset 23")) {
    return assert(false, "a 2-entry local table needs 6 bytes");
  }
  return assert(true, "a flagged local color table shorter than 3 * 2^(N+1) is rejected");
}

fn t13() -> TestResult {
  var over = base87();
  append(&mut over, image_head(0, 0, 1, 1, 0));
  over.push(2 as UInt8);
  over.push(5 as UInt8);
  over.push(1 as UInt8);
  over.push(2 as UInt8);
  if (over.len() != 27) { return assert(false, "overrun fixture is 27 bytes"); }
  if (!gif_err_is(gif_parse(over), "gif: truncated lzw sub-block at offset 24")) {
    return assert(false, "a 5-byte sub-block needs 5 bytes");
  }
  var no_term = base87();
  append(&mut no_term, image_head(0, 0, 1, 1, 0));
  no_term.push(2 as UInt8);
  no_term.push(2 as UInt8);
  no_term.push(9 as UInt8);
  no_term.push(8 as UInt8);
  if (no_term.len() != 27) { return assert(false, "missing-terminator fixture is 27 bytes"); }
  if (!gif_err_is(gif_parse(no_term), "gif: truncated lzw sub-block at offset 27")) {
    return assert(false, "a sub-block chain must end with 0x00");
  }
  return assert(true, "LZW sub-block overruns and missing terminators are rejected");
}

fn t14() -> TestResult {
  let base = base87();
  if (!gif_err_is(gif_parse(base), "gif: missing trailer at offset 13")) {
    return assert(false, "no trailer");
  }
  var okd = base87();
  okd.push(59 as UInt8);
  let g = ok_gif(gif_parse(okd));
  if (gif_frame_count(&g) != 0) { return assert(false, "trailer-only stream has no frames"); }
  var trail = base87();
  trail.push(59 as UInt8);
  trail.push(0 as UInt8);
  if (!gif_err_is(gif_parse(trail), "gif: trailing data at offset 14")) {
    return assert(false, "bytes after the trailer");
  }
  var zero_id = base87();
  zero_id.push(0 as UInt8);
  if (!gif_err_is(gif_parse(zero_id), "gif: unknown block id at offset 13")) {
    return assert(false, "0x00 is not a block id");
  }
  var bad_id = base87();
  bad_id.push(45 as UInt8);
  if (!gif_err_is(gif_parse(bad_id), "gif: unknown block id at offset 13")) {
    return assert(false, "0x2D is not a block id");
  }
  var p = Vec[UInt8].new();
  p.push(1 as UInt8);
  var no_trailer = base87();
  append(&mut no_trailer, image(0, 0, 1, 1, 0, 2, p));
  if (no_trailer.len() != 27) { return assert(false, "image-only fixture is 27 bytes"); }
  if (!gif_err_is(gif_parse(no_trailer), "gif: missing trailer at offset 27")) {
    return assert(false, "a stream with a frame still needs a trailer");
  }
  return assert(true, "missing trailer, trailing data and unknown block ids are distinct errors");
}

fn t15() -> TestResult {
  var label = sig87();
  append(&mut label, lsd(1, 1, 0, 0, 0));
  label.push(33 as UInt8);
  label.push(2 as UInt8);
  if (!gif_err_is(gif_parse(label), "gif: unknown extension label at offset 14")) {
    return assert(false, "0x02 is not an extension label");
  }
  var cut = sig87();
  append(&mut cut, lsd(1, 1, 0, 0, 0));
  cut.push(33 as UInt8);
  if (!gif_err_is(gif_parse(cut), "gif: truncated extension at offset 13")) {
    return assert(false, "0x21 without a label is truncated");
  }
  var gce_cut = sig87();
  append(&mut gce_cut, lsd(1, 1, 0, 0, 0));
  gce_cut.push(33 as UInt8);
  gce_cut.push(249 as UInt8);
  gce_cut.push(4 as UInt8);
  if (!gif_err_is(gif_parse(gce_cut), "gif: malformed graphic control extension at offset 13")) {
    return assert(false, "a 3-byte GCE body is malformed");
  }
  return assert(true, "unknown extension labels and truncated extensions are located");
}

fn t16() -> TestResult {
  var size3 = base87();
  size3.push(33 as UInt8);
  size3.push(249 as UInt8);
  size3.push(3 as UInt8);
  append(&mut size3, zeros(6));
  if (!gif_err_is(gif_parse(size3), "gif: malformed graphic control extension at offset 13")) {
    return assert(false, "GCE block size must be 4");
  }
  var bad_term = base87();
  bad_term.push(33 as UInt8);
  bad_term.push(249 as UInt8);
  bad_term.push(4 as UInt8);
  bad_term.push(0 as UInt8);
  bad_term.push(0 as UInt8);
  bad_term.push(0 as UInt8);
  bad_term.push(0 as UInt8);
  bad_term.push(1 as UInt8);
  if (!gif_err_is(gif_parse(bad_term), "gif: malformed graphic control extension at offset 13")) {
    return assert(false, "GCE terminator must be 0x00");
  }
  var cut = base87();
  cut.push(33 as UInt8);
  cut.push(249 as UInt8);
  cut.push(4 as UInt8);
  cut.push(0 as UInt8);
  cut.push(0 as UInt8);
  if (!gif_err_is(gif_parse(cut), "gif: malformed graphic control extension at offset 13")) {
    return assert(false, "a GCE cut mid-body is malformed");
  }
  var good = base87();
  append(&mut good, gce(0, 0, 0));
  good.push(59 as UInt8);
  let g = ok_gif(gif_parse(good));
  if (gif_extension_count(&g) != 1) { return assert(false, "a well-formed GCE parses"); }
  return assert(true, "graphic control extensions validate size, terminator and extent");
}

fn t17() -> TestResult {
  var min1 = base87_head();
  min1.push(1 as UInt8);
  if (!gif_err_is(gif_parse(min1), "gif: invalid lzw code size at offset 23")) {
    return assert(false, "code size 1 is invalid");
  }
  var min9 = base87_head();
  min9.push(9 as UInt8);
  if (!gif_err_is(gif_parse(min9), "gif: invalid lzw code size at offset 23")) {
    return assert(false, "code size 9 is invalid");
  }
  var min2 = base87_head();
  min2.push(2 as UInt8);
  min2.push(0 as UInt8);
  min2.push(59 as UInt8);
  let g2 = ok_gif(gif_parse(min2));
  if (gif_frame_lzw_min(&g2, 0) != 2) { return assert(false, "code size 2 accepted"); }
  if (gif_frame_lzw_size(&g2, 0) != 0) { return assert(false, "empty payload accepted"); }
  let empty_data = ok_bytes(gif_lzw_data(&g2, 0));
  if (empty_data.len() != 0) { return assert(false, "empty payload copies zero bytes"); }
  var min8 = base87_head();
  min8.push(8 as UInt8);
  min8.push(0 as UInt8);
  min8.push(59 as UInt8);
  let g8 = ok_gif(gif_parse(min8));
  if (gif_frame_lzw_min(&g8, 0) != 8) { return assert(false, "code size 8 accepted"); }
  return assert(true, "LZW code sizes outside 2..8 are rejected; empty payloads are valid");
}

fn t18() -> TestResult {
  var d = sig87();
  append(&mut d, lsd(1, 1, 0, 0, 0));
  append(&mut d, image_head(0, 0, 1, 1, 0));
  d.push(2 as UInt8);
  let payload = pattern(300);
  var first = Vec[UInt8].new();
  var i = 0;
  while (i < 255) {
    let b: UInt8 = payload[i];
    first.push(b);
    i = i + 1;
  }
  var second = Vec[UInt8].new();
  i = 255;
  while (i < 300) {
    let b: UInt8 = payload[i];
    second.push(b);
    i = i + 1;
  }
  d.push(255 as UInt8);
  append(&mut d, first);
  d.push(45 as UInt8);
  append(&mut d, second);
  d.push(0 as UInt8);
  d.push(59 as UInt8);
  if (d.len() != 328) { return assert(false, "300-byte payload fixture is 328 bytes"); }
  let g = ok_gif(gif_parse(d));
  if (gif_frame_lzw_size(&g, 0) != 300) { return assert(false, "300 payload bytes"); }
  let f = ok_frame(gif_frame(&g, 0));
  if (f.data_offset != 24) { return assert(false, "first sub-block at 24"); }
  if (f.block_end != 327) { return assert(false, "block ends just before the trailer"); }
  let got = ok_bytes(gif_lzw_data(&g, 0));
  if (!vec_eq(got, payload)) { return assert(false, "concatenation preserves order"); }
  if (!byte_is(got, 254, 245)) { return assert(false, "byte 254 is 245"); }
  if (!byte_is(got, 255, 252)) { return assert(false, "byte 255 is 252"); }
  if (!byte_is(got, 299, 48)) { return assert(false, "byte 299 is 48"); }
  if (!byte_is(d, 327, 59)) { return assert(false, "trailer at 327"); }
  return assert(true, "multi-chunk sub-block chains concatenate without length bytes");
}

fn t19() -> TestResult {
  let g = ok_gif(gif_parse(fixture_single()));
  if (!frame_err_is(gif_frame(&g, -1), "gif: frame index out of range")) {
    return assert(false, "negative frame index");
  }
  if (!frame_err_is(gif_frame(&g, 1), "gif: frame index out of range")) {
    return assert(false, "frame index past the end");
  }
  if (!bytes_err_is(gif_lzw_data(&g, 5), "gif: frame index out of range")) {
    return assert(false, "payload index out of range");
  }
  if (gif_frame_left(&g, -1) != -1) { return assert(false, "left sentinel"); }
  if (gif_frame_delay(&g, 9) != -1) { return assert(false, "delay sentinel"); }
  if (gif_frame_lzw_offset(&g, 4) != -1) { return assert(false, "offset sentinel"); }
  if (gif_local_color_count(&g, 5) != -1) { return assert(false, "local count sentinel"); }
  if (gif_local_color_count(&g, 0) != 0) { return assert(false, "no local table on frame 0"); }
  if (gif_local_color(&g, 0, 0) != -1) { return assert(false, "local lookup on a frame without LCT"); }
  if (gif_global_color(&g, 4) != -1) { return assert(false, "global lookup past the table"); }
  if (gif_global_color(&g, -1) != -1) { return assert(false, "negative global lookup"); }
  let e0 = ok_ext(gif_extension(&g, 0));
  if (e0.kind != 0) { return assert(false, "extension 0 is control"); }
  if (!ext_err_is(gif_extension(&g, 5), "gif: extension index out of range")) {
    return assert(false, "extension index out of range");
  }
  if (!bytes_err_is(gif_extension_data_copy(&g, 3), "gif: extension index out of range")) {
    return assert(false, "extension data copy out of range");
  }
  if (gif_extension_data_byte(&g, 0, 0) != -1) {
    return assert(false, "a GCE has no data bytes");
  }
  if (gif_extension_header_byte(&g, 0, 4) != -1) {
    return assert(false, "a GCE header is 4 bytes");
  }
  if (gif_extension_header_byte(&g, -1, 0) != -1) {
    return assert(false, "negative extension index");
  }
  return assert(true, "every accessor returns its documented sentinel outside its range");
}

fn t20() -> TestResult {
  let d = fixture_anim();
  let g = ok_gif(gif_parse(d));
  let n = gif_frame_count(&g);
  if (n != 2) { return assert(false, "two frames for the chain"); }
  var i = 0;
  while (i < n) {
    let f = ok_frame(gif_frame(&g, i));
    if (f.lzw_min_offset + 1 != f.data_offset) {
      return assert(false, "code size byte precedes the first sub-block");
    }
    if (f.data_offset + 1 > f.block_end) {
      return assert(false, "payload lies inside the block");
    }
    if (f.block_end <= f.lzw_min_offset) {
      return assert(false, "block end follows the code size byte");
    }
    if (!byte_is(d, f.lzw_min_offset, 2)) {
      return assert(false, "source byte at the recorded code size offset is 2");
    }
    i = i + 1;
  }
  let f0 = ok_frame(gif_frame(&g, 0));
  let f1 = ok_frame(gif_frame(&g, 1));
  if (f0.block_end != 61) { return assert(false, "frame 0 ends at the second GCE"); }
  if (f1.block_end != 84) { return assert(false, "frame 1 ends at the trailer"); }
  if (gif_frame_lzw_offset(&g, 0) + 1 != gif_frame_lzw_size(&g, 0) + 55) {
    return assert(false, "frame 0 payload span is 2 bytes from 57");
  }
  let e0 = ok_ext(gif_extension(&g, 0));
  let e1 = ok_ext(gif_extension(&g, 1));
  let e2 = ok_ext(gif_extension(&g, 2));
  if (e0.offset != 19 || e1.offset != 38 || e2.offset != 61) {
    return assert(false, "extension offsets 19, 38, 61");
  }
  if (e1.offset != f0.lzw_min_offset - 18) {
    return assert(false, "the first GCE sits 18 bytes before the code size byte");
  }
  if (!byte_is(d, 19, 33) || !byte_is(d, 38, 33) || !byte_is(d, 61, 33)) {
    return assert(false, "each recorded offset points at a 0x21 introducer");
  }
  if (!byte_is(d, 84, 59)) { return assert(false, "the last block ends at the trailer"); }
  if (!gif_is_animated(&g)) { return assert(false, "two frames are an animation"); }
  return assert(true, "recorded offsets agree with the raw fixture byte for byte");
}

fn main() -> Int {
  io.println("=== xiom.gif conformance tests ===");
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
    io.println("xiom.gif: all tests passed");
  } else {
    io.println("xiom.gif: tests failed");
  }
  return failed;
}
