// XIOM -- xiom.tga conformance tests (18 checks)
// Port task: prove the pure-XIOM xiom.tga header/footer codec.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module tga_tests
use xiom.io; use xiom.test; use xiom.tga;
use xiom.string; use xiom.string.compare;

// All Str equality goes through str_compare: `==` on a Str lowered from a
// Vec[Str] element is a pointer comparison in v0.61.3, so error messages are
// compared with the helper below.

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

// True when `data[off..off+want.len()]` equals the literal `want`.
fn bytes_at_is(data: &Vec[UInt8], off: Int, want: Str) -> Bool {
  let n = want.len();
  if (data.len() < off + n) { return false; }
  var i = 0;
  while (i < n) {
    let b: UInt8 = data[off + i];
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

fn zero_hdr() -> TgaHeader {
  return TgaHeader{
    id_length: 0; color_map_type: 0; image_type: 0; cmap_first: 0;
    cmap_length: 0; cmap_entry_bits: 0; x_origin: 0; y_origin: 0;
    width: 0; height: 0; pixel_depth: 0; attribute_bits: 0; origin_bits: 0;
  };
}

fn zero_img() -> TgaImage {
  return TgaImage{
    header: zero_hdr(); version: 0; id_offset: 0; cmap_offset: 0;
    cmap_bytes: 0; data_offset: 0; data_bytes: 0; extension_offset: 0;
    developer_offset: 0;
  };
}

fn ok_hdr(r: Result[TgaHeader, Str]) -> TgaHeader {
  match r {
    Ok(v) => { return v; },
    Err(e) => { return zero_hdr(); },
  }
}

fn bad_hdr(r: Result[TgaHeader, Str]) -> Bool {
  match r {
    Ok(v) => { return false; },
    Err(e) => { return true; },
  }
}

fn hdr_err_is(r: Result[TgaHeader, Str], want: Str) -> Bool {
  match r {
    Ok(v) => { return false; },
    Err(e) => { return streq(e, want); },
  }
}

fn ok_foot(r: Result[TgaFooter, Str]) -> TgaFooter {
  match r {
    Ok(v) => { return v; },
    Err(e) => { return TgaFooter{ extension_offset: 0; developer_offset: 0; }; },
  }
}

fn foot_err_is(r: Result[TgaFooter, Str], want: Str) -> Bool {
  match r {
    Ok(v) => { return false; },
    Err(e) => { return streq(e, want); },
  }
}

fn ok_img(r: Result[TgaImage, Str]) -> TgaImage {
  match r {
    Ok(v) => { return v; },
    Err(e) => { return zero_img(); },
  }
}

fn bad_img(r: Result[TgaImage, Str]) -> Bool {
  match r {
    Ok(v) => { return false; },
    Err(e) => { return true; },
  }
}

fn img_err_is(r: Result[TgaImage, Str], want: Str) -> Bool {
  match r {
    Ok(v) => { return false; },
    Err(e) => { return streq(e, want); },
  }
}

// TgaHeader literal for the helper checks.
fn th(t: Int, cmap_type: Int, cmap_len: Int, bits: Int, w: Int, h: Int, depth: Int, attr: Int, origin: Int) -> TgaHeader {
  return TgaHeader{
    id_length: 0; color_map_type: cmap_type; image_type: t; cmap_first: 0;
    cmap_length: cmap_len; cmap_entry_bits: bits; x_origin: 0; y_origin: 0;
    width: w; height: h; pixel_depth: depth; attribute_bits: attr;
    origin_bits: origin;
  };
}

// Hand-built 18-byte header with id_length 0, origin 0,0 and cmap_first 0.
fn hdr_bytes(t: Int, cmap_type: Int, cmap_len: Int, bits: Int, w: Int, h: Int, depth: Int, desc: Int) -> Vec[UInt8] {
  let d = Vec[UInt8].new();
  d.push(0 as UInt8);
  d.push(cmap_type as UInt8);
  d.push(t as UInt8);
  d.push(0 as UInt8); d.push(0 as UInt8);
  d.push((cmap_len % 256) as UInt8);
  d.push(((cmap_len / 256) % 256) as UInt8);
  d.push(bits as UInt8);
  d.push(0 as UInt8); d.push(0 as UInt8);
  d.push(0 as UInt8); d.push(0 as UInt8);
  d.push((w % 256) as UInt8);
  d.push(((w / 256) % 256) as UInt8);
  d.push((h % 256) as UInt8);
  d.push(((h / 256) % 256) as UInt8);
  d.push(depth as UInt8);
  d.push(desc as UInt8);
  return d;
}

// Literal "TRUEVISION-XFILE." plus NUL, pinned independently of the library.
fn push_signature(out: &mut Vec[UInt8]) {
  out.push(84 as UInt8); out.push(82 as UInt8); out.push(85 as UInt8); out.push(69 as UInt8);
  out.push(86 as UInt8); out.push(73 as UInt8); out.push(83 as UInt8); out.push(73 as UInt8);
  out.push(79 as UInt8); out.push(78 as UInt8); out.push(45 as UInt8); out.push(88 as UInt8);
  out.push(70 as UInt8); out.push(73 as UInt8); out.push(76 as UInt8); out.push(69 as UInt8);
  out.push(46 as UInt8); out.push(0 as UInt8);
}

// Hand-built 26-byte footer with both 32-bit offsets.
fn push_footer_bytes(out: &mut Vec[UInt8], ext: Int, dev: Int) {
  out.push((ext % 256) as UInt8);
  out.push(((ext / 256) % 256) as UInt8);
  out.push(((ext / 65536) % 256) as UInt8);
  out.push(((ext / 16777216) % 256) as UInt8);
  out.push((dev % 256) as UInt8);
  out.push(((dev / 256) % 256) as UInt8);
  out.push(((dev / 65536) % 256) as UInt8);
  out.push(((dev / 16777216) % 256) as UInt8);
  push_signature(out);
}

// Version 1 uncompressed true-color 2x3 image: 18 header + 18 raster bytes.
fn mk_v1_24() -> Vec[UInt8] {
  let d = hdr_bytes(2, 0, 0, 0, 2, 3, 24, 32);
  var i = 0;
  while (i < 18) {
    d.push((i + 1) as UInt8);
    i = i + 1;
  }
  return d;
}

// Version 2 color-mapped 2x2 image: header + id "TGA1" + 2-entry 24-bit color
// map + 4 raster bytes + zero footer.
fn mk_v2_cmap() -> Vec[UInt8] {
  var d = Vec[UInt8].new();
  d.push(4 as UInt8);
  d.push(1 as UInt8);
  d.push(1 as UInt8);
  d.push(0 as UInt8); d.push(0 as UInt8);
  d.push(2 as UInt8); d.push(0 as UInt8);
  d.push(24 as UInt8);
  d.push(0 as UInt8); d.push(0 as UInt8);
  d.push(0 as UInt8); d.push(0 as UInt8);
  d.push(2 as UInt8); d.push(0 as UInt8);
  d.push(2 as UInt8); d.push(0 as UInt8);
  d.push(8 as UInt8);
  d.push(32 as UInt8);
  d.push(84 as UInt8); d.push(71 as UInt8); d.push(65 as UInt8); d.push(49 as UInt8);
  d.push(1 as UInt8); d.push(2 as UInt8); d.push(3 as UInt8);
  d.push(4 as UInt8); d.push(5 as UInt8); d.push(6 as UInt8);
  d.push(0 as UInt8); d.push(0 as UInt8); d.push(1 as UInt8); d.push(1 as UInt8);
  push_footer_bytes(&mut d, 0, 0);
  return d;
}

fn t1() -> TestResult {
  let d = hdr_bytes(2, 0, 0, 0, 2, 3, 24, 40);
  if (d.len() != 18) { return assert(false, "hand-built header is 18 bytes"); }
  let r = tga_parse_header(d);
  match r {
    Ok(h) => {
      if (h.id_length != 0) { return assert(false, "id_length is 0"); }
      if (h.color_map_type != 0) { return assert(false, "color map type is 0"); }
      if (h.image_type != 2) { return assert(false, "image type is 2"); }
      if (h.cmap_first != 0) { return assert(false, "cmap first is 0"); }
      if (h.cmap_length != 0) { return assert(false, "cmap length is 0"); }
      if (h.cmap_entry_bits != 0) { return assert(false, "cmap entry bits is 0"); }
      if (h.x_origin != 0) { return assert(false, "x origin is 0"); }
      if (h.y_origin != 0) { return assert(false, "y origin is 0"); }
      if (h.width != 2) { return assert(false, "width is 2"); }
      if (h.height != 3) { return assert(false, "height is 3"); }
      if (h.pixel_depth != 24) { return assert(false, "pixel depth is 24"); }
      if (h.attribute_bits != 8) { return assert(false, "attribute bits are 8"); }
      if (h.origin_bits != 2) { return assert(false, "origin bits are 2"); }
      return assert(true, "hand-built 2x3 24-bit header decodes every field");
    },
    Err(e) => { return assert(false, "hand-built header was rejected"); },
  }
}

fn t2() -> TestResult {
  let h = TgaHeader{
    id_length: 7; color_map_type: 1; image_type: 1; cmap_first: 3;
    cmap_length: 256; cmap_entry_bits: 24; x_origin: 5; y_origin: 6;
    width: 320; height: 240; pixel_depth: 8; attribute_bits: 3; origin_bits: 1;
  };
  let d = ok_bytes(tga_build_header(h));
  if (d.len() != 18) { return assert(false, "built header is 18 bytes"); }
  if (!byte_is(d, 0, 7)) { return assert(false, "id length byte"); }
  if (!byte_is(d, 1, 1)) { return assert(false, "color map type byte"); }
  if (!byte_is(d, 2, 1)) { return assert(false, "image type byte"); }
  if (!byte_is(d, 3, 3)) { return assert(false, "cmap first low byte"); }
  if (!byte_is(d, 4, 0)) { return assert(false, "cmap first high byte"); }
  if (!byte_is(d, 5, 0)) { return assert(false, "cmap length low byte"); }
  if (!byte_is(d, 6, 1)) { return assert(false, "cmap length high byte"); }
  if (!byte_is(d, 7, 24)) { return assert(false, "cmap entry bits byte"); }
  if (!byte_is(d, 8, 5)) { return assert(false, "x origin low byte"); }
  if (!byte_is(d, 9, 0)) { return assert(false, "x origin high byte"); }
  if (!byte_is(d, 10, 6)) { return assert(false, "y origin low byte"); }
  if (!byte_is(d, 11, 0)) { return assert(false, "y origin high byte"); }
  if (!byte_is(d, 12, 64)) { return assert(false, "width low byte"); }
  if (!byte_is(d, 13, 1)) { return assert(false, "width high byte"); }
  if (!byte_is(d, 14, 240)) { return assert(false, "height low byte"); }
  if (!byte_is(d, 15, 0)) { return assert(false, "height high byte"); }
  if (!byte_is(d, 16, 8)) { return assert(false, "pixel depth byte"); }
  if (!byte_is(d, 17, 19)) { return assert(false, "descriptor byte"); }
  let back = ok_hdr(tga_parse_header(d));
  if (back.id_length != 7) { return assert(false, "round-trip id length"); }
  if (back.color_map_type != 1) { return assert(false, "round-trip color map type"); }
  if (back.image_type != 1) { return assert(false, "round-trip image type"); }
  if (back.cmap_first != 3) { return assert(false, "round-trip cmap first"); }
  if (back.cmap_length != 256) { return assert(false, "round-trip cmap length"); }
  if (back.cmap_entry_bits != 24) { return assert(false, "round-trip cmap bits"); }
  if (back.x_origin != 5) { return assert(false, "round-trip x origin"); }
  if (back.y_origin != 6) { return assert(false, "round-trip y origin"); }
  if (back.width != 320) { return assert(false, "round-trip width"); }
  if (back.height != 240) { return assert(false, "round-trip height"); }
  if (back.pixel_depth != 8) { return assert(false, "round-trip pixel depth"); }
  if (back.attribute_bits != 3) { return assert(false, "round-trip attribute bits"); }
  if (back.origin_bits != 1) { return assert(false, "round-trip origin bits"); }
  return assert(true, "built header pins little-endian bytes and round-trips");
}

fn t3() -> TestResult {
  let f = ok_bytes(tga_build_footer(12, 7));
  if (f.len() != 26) { return assert(false, "built footer is 26 bytes"); }
  if (!byte_is(f, 0, 12)) { return assert(false, "extension offset low byte"); }
  if (!byte_is(f, 1, 0)) { return assert(false, "extension offset byte 1"); }
  if (!byte_is(f, 2, 0)) { return assert(false, "extension offset byte 2"); }
  if (!byte_is(f, 3, 0)) { return assert(false, "extension offset byte 3"); }
  if (!byte_is(f, 4, 7)) { return assert(false, "developer offset low byte"); }
  if (!bytes_at_is(f, 8, "TRUEVISION-XFILE.")) { return assert(false, "footer signature text"); }
  if (!byte_is(f, 24, 46)) { return assert(false, "signature terminator '.'"); }
  if (!byte_is(f, 25, 0)) { return assert(false, "signature NUL byte"); }
  let back = ok_foot(tga_parse_footer(f));
  if (back.extension_offset != 12) { return assert(false, "round-trip extension offset"); }
  if (back.developer_offset != 7) { return assert(false, "round-trip developer offset"); }
  let g = ok_bytes(tga_build_footer(16909060, 0));
  if (!byte_is(g, 0, 4)) { return assert(false, "0x01020304 byte 0"); }
  if (!byte_is(g, 1, 3)) { return assert(false, "0x01020304 byte 1"); }
  if (!byte_is(g, 2, 2)) { return assert(false, "0x01020304 byte 2"); }
  if (!byte_is(g, 3, 1)) { return assert(false, "0x01020304 byte 3"); }
  return assert(true, "footer builds, pins the signature and round-trips");
}

fn t4() -> TestResult {
  let v2 = mk_v2_cmap();
  if (!tga_has_footer(v2)) { return assert(false, "v2 buffer has a footer"); }
  if (tga_detect_version(v2) != 2) { return assert(false, "v2 buffer detects version 2"); }
  let v1 = mk_v1_24();
  if (tga_has_footer(v1)) { return assert(false, "v1 buffer has no footer"); }
  if (tga_detect_version(v1) != 1) { return assert(false, "v1 buffer detects version 1"); }
  let short = bytes_of("abc");
  if (tga_has_footer(short)) { return assert(false, "short buffer has no footer"); }
  if (tga_detect_version(short) != 1) { return assert(false, "short buffer detects version 1"); }
  let bad = mk_v2_cmap();
  let bn = bad.len();
  bad[bn - 1] = 1 as UInt8;
  if (tga_has_footer(bad)) { return assert(false, "NUL corruption breaks detection"); }
  if (tga_detect_version(bad) != 1) { return assert(false, "NUL corruption detects version 1"); }
  let bad2 = mk_v2_cmap();
  let b2 = bad2.len();
  bad2[b2 - 10] = 65 as UInt8;
  if (tga_has_footer(bad2)) { return assert(false, "signature corruption breaks detection"); }
  return assert(true, "footer presence and version detection are signature-exact");
}

fn t5() -> TestResult {
  let d = mk_v1_24();
  if (d.len() != 36) { return assert(false, "v1 fixture is 36 bytes"); }
  let img = ok_img(tga_parse(d));
  if (img.version != 1) { return assert(false, "v1 parse reports version 1"); }
  if (img.id_offset != 18) { return assert(false, "id offset is 18"); }
  if (img.cmap_offset != 18) { return assert(false, "cmap offset is 18"); }
  if (img.cmap_bytes != 0) { return assert(false, "cmap bytes is 0"); }
  if (img.data_offset != 18) { return assert(false, "data offset is 18"); }
  if (img.data_bytes != 18) { return assert(false, "data bytes is 18"); }
  if (img.extension_offset != 0) { return assert(false, "v1 has no extension offset"); }
  if (img.developer_offset != 0) { return assert(false, "v1 has no developer offset"); }
  if (img.header.image_type != 2) { return assert(false, "parsed image type 2"); }
  if (img.header.width != 2) { return assert(false, "parsed width 2"); }
  if (img.header.height != 3) { return assert(false, "parsed height 3"); }
  if (img.header.pixel_depth != 24) { return assert(false, "parsed depth 24"); }
  if (img.header.origin_bits != 2) { return assert(false, "parsed origin bits 2"); }
  if (img.header.attribute_bits != 0) { return assert(false, "parsed attribute bits 0"); }
  if (img.data_offset + img.data_bytes != d.len()) { return assert(false, "raster ends at buffer end"); }
  return assert(true, "v1 uncompressed buffer locates header and raster exactly");
}

fn t6() -> TestResult {
  let d = mk_v2_cmap();
  if (d.len() != 58) { return assert(false, "v2 fixture is 58 bytes"); }
  let img = ok_img(tga_parse(d));
  if (img.version != 2) { return assert(false, "v2 parse reports version 2"); }
  if (img.header.id_length != 4) { return assert(false, "id length 4"); }
  if (img.header.image_type != 1) { return assert(false, "color-mapped image type"); }
  if (img.header.color_map_type != 1) { return assert(false, "color map present"); }
  if (img.header.cmap_length != 2) { return assert(false, "2 color map entries"); }
  if (img.header.cmap_entry_bits != 24) { return assert(false, "24-bit entries"); }
  if (img.header.pixel_depth != 8) { return assert(false, "8-bit indices"); }
  if (img.id_offset != 18) { return assert(false, "id offset 18"); }
  if (img.cmap_offset != 22) { return assert(false, "cmap offset 22"); }
  if (img.cmap_bytes != 6) { return assert(false, "cmap bytes 6"); }
  if (img.data_offset != 28) { return assert(false, "data offset 28"); }
  if (img.data_bytes != 4) { return assert(false, "data bytes 4"); }
  if (img.extension_offset != 0) { return assert(false, "extension offset 0"); }
  if (img.developer_offset != 0) { return assert(false, "developer offset 0"); }
  let idb = ok_bytes(tga_id_field(d));
  if (!vec_is_str(idb, "TGA1")) { return assert(false, "image id slice is TGA1"); }
  let cm = ok_bytes(tga_color_map_data(d));
  if (cm.len() != 6) { return assert(false, "color map slice is 6 bytes"); }
  if (!byte_is(cm, 0, 1)) { return assert(false, "color map byte 0"); }
  if (!byte_is(cm, 2, 3)) { return assert(false, "color map byte 2"); }
  if (!byte_is(cm, 5, 6)) { return assert(false, "color map byte 5"); }
  let ras = ok_bytes(tga_image_data(d));
  if (ras.len() != 4) { return assert(false, "raster slice is 4 bytes"); }
  if (!byte_is(ras, 0, 0)) { return assert(false, "raster byte 0"); }
  if (!byte_is(ras, 2, 1)) { return assert(false, "raster byte 2"); }
  if (!byte_is(ras, 3, 1)) { return assert(false, "raster byte 3"); }
  return assert(true, "v2 image id, color map and raster slices round-trip");
}

fn t7() -> TestResult {
  let d = mk_v1_24();
  let idb = ok_bytes(tga_id_field(d));
  if (idb.len() != 0) { return assert(false, "empty image id field"); }
  let ras = ok_bytes(tga_image_data(d));
  if (ras.len() != 18) { return assert(false, "raster slice is 18 bytes"); }
  var i = 0;
  while (i < 18) {
    let b: Int = (ras[i] as Int) & 0xFF;
    if (b != i + 1) { return assert(false, "raster byte matches source"); }
    i = i + 1;
  }
  let e = hdr_bytes(2, 0, 0, 0, 4, 2, 32, 32);
  var j = 0;
  while (j < 32) {
    e.push((j + 100) as UInt8);
    j = j + 1;
  }
  let img = ok_img(tga_parse(e));
  if (img.data_bytes != 32) { return assert(false, "4x2 32-bit raster is 32 bytes"); }
  let ras2 = ok_bytes(tga_image_data(e));
  if (ras2.len() != 32) { return assert(false, "4x2 raster slice is 32 bytes"); }
  if (!byte_is(ras2, 0, 100)) { return assert(false, "4x2 raster first byte"); }
  if (!byte_is(ras2, 31, 131)) { return assert(false, "4x2 raster last byte"); }
  return assert(true, "uncompressed raster slices match the source bytes");
}

fn t8() -> TestResult {
  if (tga_bytes_per_pixel(0) != 0) { return assert(false, "depth 0 is 0 bytes"); }
  if (tga_bytes_per_pixel(8) != 1) { return assert(false, "depth 8 is 1 byte"); }
  if (tga_bytes_per_pixel(15) != 2) { return assert(false, "depth 15 is 2 bytes"); }
  if (tga_bytes_per_pixel(16) != 2) { return assert(false, "depth 16 is 2 bytes"); }
  if (tga_bytes_per_pixel(24) != 3) { return assert(false, "depth 24 is 3 bytes"); }
  if (tga_bytes_per_pixel(32) != 4) { return assert(false, "depth 32 is 4 bytes"); }
  if (tga_bytes_per_pixel(64) != 8) { return assert(false, "depth 64 is 8 bytes"); }
  if (!tga_is_rle(9)) { return assert(false, "type 9 is RLE"); }
  if (!tga_is_rle(10)) { return assert(false, "type 10 is RLE"); }
  if (!tga_is_rle(11)) { return assert(false, "type 11 is RLE"); }
  if (tga_is_rle(0)) { return assert(false, "type 0 is not RLE"); }
  if (tga_is_rle(1)) { return assert(false, "type 1 is not RLE"); }
  if (tga_is_rle(2)) { return assert(false, "type 2 is not RLE"); }
  if (tga_is_rle(3)) { return assert(false, "type 3 is not RLE"); }
  let h30 = th(2, 0, 0, 0, 3, 5, 16, 0, 0);
  if (tga_data_bytes(&h30) != 30) { return assert(false, "3x5 16-bit is 30 bytes"); }
  let h0 = th(0, 0, 0, 0, 0, 0, 0, 0, 0);
  if (tga_data_bytes(&h0) != 0) { return assert(false, "type 0 has no raster"); }
  let hr = th(10, 0, 0, 0, 4, 4, 24, 0, 0);
  if (tga_data_bytes(&hr) != -1) { return assert(false, "RLE raster length is unknown"); }
  let hm = th(1, 1, 4, 24, 2, 1, 8, 0, 0);
  if (tga_data_bytes(&hm) != 2) { return assert(false, "color-mapped raster ignores the map"); }
  return assert(true, "depth, RLE and raster-length helpers are exact");
}

fn t9() -> TestResult {
  let types = Vec[Int].new();
  types.push(4); types.push(5); types.push(8); types.push(12); types.push(255);
  var i = 0;
  while (i < types.len()) {
    let t: Int = types[i];
    let d = hdr_bytes(t, 0, 0, 0, 1, 1, 24, 0);
    if (!hdr_err_is(tga_parse_header(d), "tga: unknown image type")) {
      return assert(false, "unknown image type is Err");
    }
    if (!img_err_is(tga_parse(d), "tga: unknown image type")) {
      return assert(false, "full parse forwards unknown image type");
    }
    i = i + 1;
  }
  return assert(true, "unsupported image type codes are rejected");
}

fn t10() -> TestResult {
  let d0 = hdr_bytes(2, 0, 0, 0, 0, 1, 24, 0);
  if (!hdr_err_is(tga_parse_header(d0), "tga: invalid width")) {
    return assert(false, "zero width is Err");
  }
  let d1 = hdr_bytes(2, 0, 0, 0, 1, 0, 24, 0);
  if (!hdr_err_is(tga_parse_header(d1), "tga: invalid height")) {
    return assert(false, "zero height is Err");
  }
  let z = hdr_bytes(0, 0, 0, 0, 0, 0, 0, 0);
  if (bad_hdr(tga_parse_header(z))) { return assert(false, "type 0 with all-zero fields is Ok"); }
  let zi = ok_img(tga_parse(z));
  if (zi.data_bytes != 0) { return assert(false, "type 0 has data_bytes 0"); }
  if (zi.data_offset != 18) { return assert(false, "type 0 raster starts at 18"); }
  if (zi.version != 1) { return assert(false, "type 0 buffer is version 1"); }
  let z2 = hdr_bytes(0, 0, 0, 0, 1, 0, 0, 0);
  if (!hdr_err_is(tga_parse_header(z2), "tga: invalid width")) {
    return assert(false, "type 0 with nonzero width is Err");
  }
  let z3 = hdr_bytes(0, 0, 0, 0, 0, 0, 8, 0);
  if (!hdr_err_is(tga_parse_header(z3), "tga: unsupported pixel depth")) {
    return assert(false, "type 0 with a pixel depth is Err");
  }
  let z4 = hdr_bytes(0, 1, 1, 24, 0, 0, 0, 0);
  if (!hdr_err_is(tga_parse_header(z4), "tga: unexpected color map")) {
    return assert(false, "type 0 with a color map is Err");
  }
  return assert(true, "zero dimensions and the type 0 rules are enforced");
}

fn t11() -> TestResult {
  let a = hdr_bytes(2, 0, 0, 0, 1, 1, 8, 0);
  if (!hdr_err_is(tga_parse_header(a), "tga: unsupported pixel depth")) {
    return assert(false, "true-color 8-bit is Err");
  }
  let b = hdr_bytes(2, 0, 0, 0, 1, 1, 0, 0);
  if (!hdr_err_is(tga_parse_header(b), "tga: unsupported pixel depth")) {
    return assert(false, "true-color depth 0 is Err");
  }
  let c = hdr_bytes(1, 1, 1, 24, 1, 1, 24, 0);
  if (!hdr_err_is(tga_parse_header(c), "tga: unsupported pixel depth")) {
    return assert(false, "color-mapped 24-bit is Err");
  }
  let d = hdr_bytes(3, 0, 0, 0, 1, 1, 24, 0);
  if (!hdr_err_is(tga_parse_header(d), "tga: unsupported pixel depth")) {
    return assert(false, "grayscale 24-bit is Err");
  }
  let e = hdr_bytes(3, 0, 0, 0, 1, 1, 0, 0);
  if (!hdr_err_is(tga_parse_header(e), "tga: unsupported pixel depth")) {
    return assert(false, "grayscale depth 0 is Err");
  }
  let v1 = hdr_bytes(3, 0, 0, 0, 1, 1, 8, 0);
  if (bad_hdr(tga_parse_header(v1))) { return assert(false, "grayscale 8-bit is Ok"); }
  let v2 = hdr_bytes(3, 0, 0, 0, 1, 1, 16, 0);
  if (bad_hdr(tga_parse_header(v2))) { return assert(false, "grayscale 16-bit is Ok"); }
  let v3 = hdr_bytes(1, 1, 1, 16, 1, 1, 16, 0);
  if (bad_hdr(tga_parse_header(v3))) { return assert(false, "color-mapped 16-bit is Ok"); }
  let v4 = hdr_bytes(2, 0, 0, 0, 1, 1, 15, 0);
  if (bad_hdr(tga_parse_header(v4))) { return assert(false, "true-color 15-bit is Ok"); }
  let v5 = hdr_bytes(10, 0, 0, 0, 1, 1, 32, 0);
  if (bad_hdr(tga_parse_header(v5))) { return assert(false, "RLE true-color 32-bit is Ok"); }
  return assert(true, "pixel depth is validated per image type");
}

fn t12() -> TestResult {
  let a = hdr_bytes(1, 0, 0, 0, 1, 1, 8, 0);
  if (!hdr_err_is(tga_parse_header(a), "tga: color map required for image type")) {
    return assert(false, "color-mapped type needs a color map");
  }
  let b = hdr_bytes(1, 1, 0, 24, 1, 1, 8, 0);
  if (!hdr_err_is(tga_parse_header(b), "tga: invalid color map length")) {
    return assert(false, "color map type 1 needs entries");
  }
  let c = hdr_bytes(1, 1, 1, 12, 1, 1, 8, 0);
  if (!hdr_err_is(tga_parse_header(c), "tga: invalid color map entry size")) {
    return assert(false, "12-bit entries are Err");
  }
  let d = hdr_bytes(2, 0, 5, 0, 1, 1, 24, 0);
  if (!hdr_err_is(tga_parse_header(d), "tga: unexpected color map")) {
    return assert(false, "color map type 0 with entries is Err");
  }
  let e = hdr_bytes(2, 2, 1, 24, 1, 1, 24, 0);
  if (!hdr_err_is(tga_parse_header(e), "tga: invalid color map type")) {
    return assert(false, "color map type 2 is Err");
  }
  let v = hdr_bytes(2, 1, 1, 32, 1, 1, 24, 0);
  if (bad_hdr(tga_parse_header(v))) { return assert(false, "true-color with a map is Ok"); }
  return assert(true, "color map fields are cross-checked");
}

fn t13() -> TestResult {
  let empty = Vec[UInt8].new();
  if (!hdr_err_is(tga_parse_header(empty), "tga: truncated header")) {
    return assert(false, "empty buffer is a truncated header");
  }
  let h17 = Vec[UInt8].new();
  var i = 0;
  while (i < 17) { h17.push(0 as UInt8); i = i + 1; }
  if (!hdr_err_is(tga_parse_header(h17), "tga: truncated header")) {
    return assert(false, "17-byte buffer is a truncated header");
  }
  let idh = hdr_bytes(2, 0, 0, 0, 1, 1, 24, 0);
  idh[0] = 10 as UInt8;
  idh.push(1 as UInt8); idh.push(2 as UInt8); idh.push(3 as UInt8);
  if (!img_err_is(tga_parse(idh), "tga: truncated image id")) {
    return assert(false, "image ID beyond the buffer is Err");
  }
  if (!bytes_err_is(tga_id_field(idh), "tga: truncated image id")) {
    return assert(false, "id slice reports truncation");
  }
  let cm = hdr_bytes(1, 1, 4, 24, 1, 1, 8, 0);
  var j = 0;
  while (j < 5) { cm.push(0 as UInt8); j = j + 1; }
  if (!img_err_is(tga_parse(cm), "tga: truncated color map")) {
    return assert(false, "color map beyond the buffer is Err");
  }
  if (!bytes_err_is(tga_color_map_data(cm), "tga: truncated color map")) {
    return assert(false, "color map slice reports truncation");
  }
  let rk = hdr_bytes(2, 0, 0, 0, 2, 2, 24, 0);
  var k = 0;
  while (k < 11) { rk.push(0 as UInt8); k = k + 1; }
  if (!img_err_is(tga_parse(rk), "tga: truncated image data")) {
    return assert(false, "11 of 12 raster bytes is Err");
  }
  return assert(true, "declared regions must fit inside the buffer");
}

fn t14() -> TestResult {
  let few = Vec[UInt8].new();
  var i = 0;
  while (i < 25) { few.push(0 as UInt8); i = i + 1; }
  if (!foot_err_is(tga_parse_footer(few), "tga: truncated footer")) {
    return assert(false, "25-byte buffer is a truncated footer");
  }
  let zero26 = Vec[UInt8].new();
  i = 0;
  while (i < 26) { zero26.push(0 as UInt8); i = i + 1; }
  if (!foot_err_is(tga_parse_footer(zero26), "tga: missing v2 signature")) {
    return assert(false, "all-zero tail is a missing signature");
  }
  let g = ok_bytes(tga_build_footer(0, 0));
  g[25] = 1 as UInt8;
  if (!foot_err_is(tga_parse_footer(g), "tga: missing v2 signature")) {
    return assert(false, "corrupt NUL is a missing signature");
  }
  let h2 = ok_bytes(tga_build_footer(0, 0));
  h2[12] = 65 as UInt8;
  if (!foot_err_is(tga_parse_footer(h2), "tga: missing v2 signature")) {
    return assert(false, "corrupt signature byte is a missing signature");
  }
  let okf = ok_bytes(tga_build_footer(0, 0));
  let back = ok_foot(tga_parse_footer(okf));
  if (back.extension_offset != 0) { return assert(false, "zero offsets parse"); }
  return assert(true, "footer parse rejects truncation and bad signatures");
}

fn t15() -> TestResult {
  let d = hdr_bytes(10, 0, 0, 0, 4, 4, 24, 0);
  d.push(0 as UInt8);
  let img = ok_img(tga_parse(d));
  if (img.data_bytes != -1) { return assert(false, "RLE data_bytes is -1"); }
  if (img.data_offset != 18) { return assert(false, "RLE data offset 18"); }
  if (img.version != 1) { return assert(false, "RLE v1 buffer detects version 1"); }
  if (!bytes_err_is(tga_image_data(d), "tga: image data length unknown for RLE")) {
    return assert(false, "RLE raster slice is rejected");
  }
  let e = hdr_bytes(10, 0, 0, 0, 4, 4, 24, 0);
  if (!img_err_is(tga_parse(e), "tga: truncated image data")) {
    return assert(false, "RLE without any packet byte is Err");
  }
  let m = hdr_bytes(9, 1, 2, 24, 2, 2, 8, 0);
  var i = 0;
  while (i < 6) { m.push(0 as UInt8); i = i + 1; }
  m.push(0 as UInt8);
  let img2 = ok_img(tga_parse(m));
  if (img2.data_offset != 24) { return assert(false, "RLE color-mapped data offset 24"); }
  if (img2.cmap_bytes != 6) { return assert(false, "RLE color-mapped cmap bytes 6"); }
  if (img2.data_bytes != -1) { return assert(false, "RLE color-mapped data_bytes is -1"); }
  let cm = ok_bytes(tga_color_map_data(m));
  if (cm.len() != 6) { return assert(false, "RLE color map slice is 6 bytes"); }
  var f = hdr_bytes(11, 0, 0, 0, 2, 2, 8, 0);
  f.push(0 as UInt8);
  push_footer_bytes(&mut f, 0, 0);
  let img3 = ok_img(tga_parse(f));
  if (img3.version != 2) { return assert(false, "RLE buffer with a footer is version 2"); }
  if (img3.data_bytes != -1) { return assert(false, "RLE with footer keeps data_bytes -1"); }
  return assert(true, "RLE rasters are located but never length-checked");
}

fn t16() -> TestResult {
  var a = mk_v1_24();
  let an = a.len();
  push_footer_bytes(&mut a, 5, 5);
  let img = ok_img(tga_parse(a));
  if (img.version != 2) { return assert(false, "footer with small offsets parses"); }
  if (img.extension_offset != 5) { return assert(false, "extension offset 5 round-trips"); }
  if (img.developer_offset != 5) { return assert(false, "developer offset 5 round-trips"); }
  var lim = mk_v1_24();
  push_footer_bytes(&mut lim, an + 24, an + 23);
  let img2 = ok_img(tga_parse(lim));
  if (img2.version != 2) { return assert(false, "offsets up to n-2 are accepted"); }
  if (img2.extension_offset != an + 24) { return assert(false, "n-2 extension offset round-trips"); }
  if (img2.developer_offset != an + 23) { return assert(false, "n-3 developer offset round-trips"); }
  var b = mk_v1_24();
  push_footer_bytes(&mut b, an + 25, 0);
  if (!img_err_is(tga_parse(b), "tga: extension area out of bounds")) {
    return assert(false, "extension offset past n-2 is Err");
  }
  if (!foot_err_is(tga_parse_footer(b), "tga: extension area out of bounds")) {
    return assert(false, "footer parser checks extension bounds");
  }
  var c = mk_v1_24();
  push_footer_bytes(&mut c, 0, an + 100);
  if (!img_err_is(tga_parse(c), "tga: developer area out of bounds")) {
    return assert(false, "developer offset past the buffer is Err");
  }
  if (!foot_err_is(tga_parse_footer(c), "tga: developer area out of bounds")) {
    return assert(false, "footer parser checks developer bounds");
  }
  return assert(true, "extension and developer offsets are bounds-checked");
}

fn t17() -> TestResult {
  let types = Vec[Int].new();
  types.push(0); types.push(1); types.push(2);
  types.push(3); types.push(9); types.push(10); types.push(11);
  var i = 0;
  while (i < types.len()) {
    let t: Int = types[i];
    var cmap_type = 0;
    var cmap_len = 0;
    var bits = 0;
    var depth = 24;
    var w = 2;
    var h = 2;
    if (t == 1) { cmap_type = 1; cmap_len = 1; bits = 24; depth = 8; }
    if (t == 9) { cmap_type = 1; cmap_len = 1; bits = 16; depth = 8; }
    if (t == 3) { depth = 8; }
    if (t == 11) { depth = 8; }
    if (t == 0) { w = 0; h = 0; depth = 0; }
    let d = hdr_bytes(t, cmap_type, cmap_len, bits, w, h, depth, 32);
    var c = 0;
    while (c < cmap_len * tga_bytes_per_pixel(bits)) {
      d.push(0 as UInt8);
      c = c + 1;
    }
    var raster = w * h * tga_bytes_per_pixel(depth);
    if (tga_is_rle(t)) { raster = 1; }
    var r = 0;
    while (r < raster) {
      d.push(0 as UInt8);
      r = r + 1;
    }
    if (bad_hdr(tga_parse_header(d))) { return assert(false, "supported type header parses"); }
    if (bad_img(tga_parse(d))) { return assert(false, "supported type buffer parses"); }
    i = i + 1;
  }
  return assert(true, "all seven image types parse in valid buffers");
}

fn t18() -> TestResult {
  let h = TgaHeader{
    id_length: 3; color_map_type: 0; image_type: 2; cmap_first: 0;
    cmap_length: 0; cmap_entry_bits: 0; x_origin: 1; y_origin: 2;
    width: 3; height: 2; pixel_depth: 32; attribute_bits: 8; origin_bits: 3;
  };
  let file = ok_bytes(tga_build_header(h));
  if (file.len() != 18) { return assert(false, "rebuilt header is 18 bytes"); }
  file.push(88 as UInt8); file.push(89 as UInt8); file.push(90 as UInt8);
  var i = 0;
  while (i < 24) {
    file.push(((i * 7) % 251) as UInt8);
    i = i + 1;
  }
  if (file.len() != 45) { return assert(false, "raster ends at 45"); }
  file.push(2 as UInt8); file.push(0 as UInt8);
  file.push(1 as UInt8); file.push(0 as UInt8);
  file.push(0 as UInt8); file.push(0 as UInt8);
  let f = ok_bytes(tga_build_footer(45, 47));
  var j = 0;
  while (j < 26) {
    let b: UInt8 = f[j];
    file.push(b);
    j = j + 1;
  }
  if (file.len() != 77) { return assert(false, "v2 file is 77 bytes"); }
  if (!tga_has_footer(file)) { return assert(false, "rebuilt file carries a footer"); }
  let img = ok_img(tga_parse(file));
  if (img.version != 2) { return assert(false, "rebuilt file is version 2"); }
  if (img.extension_offset != 45) { return assert(false, "extension offset 45"); }
  if (img.developer_offset != 47) { return assert(false, "developer offset 47"); }
  if (img.id_offset != 18) { return assert(false, "id offset 18"); }
  if (img.cmap_offset != 21) { return assert(false, "cmap offset 21"); }
  if (img.cmap_bytes != 0) { return assert(false, "cmap bytes 0"); }
  if (img.data_offset != 21) { return assert(false, "data offset 21"); }
  if (img.data_bytes != 24) { return assert(false, "data bytes 24"); }
  if (img.header.width != 3) { return assert(false, "width round-trip"); }
  if (img.header.height != 2) { return assert(false, "height round-trip"); }
  if (img.header.pixel_depth != 32) { return assert(false, "depth round-trip"); }
  if (img.header.x_origin != 1) { return assert(false, "x origin round-trip"); }
  if (img.header.y_origin != 2) { return assert(false, "y origin round-trip"); }
  if (img.header.origin_bits != 3) { return assert(false, "origin bits round-trip"); }
  if (img.header.attribute_bits != 8) { return assert(false, "attribute bits round-trip"); }
  let idb = ok_bytes(tga_id_field(file));
  if (!vec_is_str(idb, "XYZ")) { return assert(false, "rebuilt image id is XYZ"); }
  let ras = ok_bytes(tga_image_data(file));
  if (ras.len() != 24) { return assert(false, "rebuilt raster is 24 bytes"); }
  if (!byte_is(ras, 1, 7)) { return assert(false, "rebuilt raster byte 1"); }
  if (!byte_is(ras, 23, 161)) { return assert(false, "rebuilt raster byte 23"); }
  if (!bytes_at_is(file, 77 - 26 + 8, "TRUEVISION-XFILE.")) {
    return assert(false, "footer signature sits at n-18");
  }
  return assert(true, "built v2 file parses back field-for-field");
}

fn main() -> Int {
  io.println("=== xiom.tga conformance tests ===");
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
    io.println("xiom.tga: all tests passed");
  } else {
    io.println("xiom.tga: tests failed");
  }
  return failed;
}
