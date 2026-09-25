// XIOM -- xiom.dds conformance tests (18 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Covers the documented API: the 128-byte prefix byte layout, the RGB
// mask rules, the DXT1..DXT5 and DX10 fourCC handling, the DDS_HEADER_DXT10
// block, payload span/copy, builder round-trips with and without a DXT10
// block, the pass-through predicate for unknown fourCCs, and the full error
// catalog (truncation, magic, size fields, reserved1, required/pitch/mipmap/
// depth flags, pixel format flags, masks, DXT10 fields, builder ranges).
//
// Err strings are compared with compare.str_compare (BUG 17 discipline:
// `==` on a Str lowered from a Vec element is a pointer comparison).

module dds_tests
use xiom.io; use xiom.test;
use xiom.dds;
use xiom.string;
use xiom.string.compare;

// --------------------------------------------------
//  Result and byte helpers
// --------------------------------------------------

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn ok_bytes(r: Result[Vec[UInt8], Str]) -> Vec[UInt8] {
  if r.is_ok { return r.value; }
  return Vec[UInt8].new();
}

fn bytes_err_is(r: Result[Vec[UInt8], Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return streq(r.error, want);
}

fn ok_hdr(r: Result[DdsHeader, Str]) -> DdsHeader {
  if r.is_ok { return r.value; }
  return zero_hdr();
}

fn hdr_err_is(r: Result[DdsHeader, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return streq(r.error, want);
}

fn bad_hdr(r: Result[DdsHeader, Str]) -> Bool {
  return !r.is_ok;
}

fn ok_img(r: Result[DdsImage, Str]) -> DdsImage {
  if r.is_ok { return r.value; }
  return zero_img();
}

fn bad_img(r: Result[DdsImage, Str]) -> Bool {
  return !r.is_ok;
}

fn img_err_is(r: Result[DdsImage, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return streq(r.error, want);
}

fn byte_is(data: &Vec[UInt8], i: Int, want: Int) -> Bool {
  let b: Int = (data[i] as Int) & 0xFF;
  return b == want;
}

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

fn bytes_equal(a: &Vec[UInt8], b: &Vec[UInt8]) -> Bool {
  if (a.len() != b.len()) { return false; }
  var i = 0;
  while (i < a.len()) {
    if (a[i] != b[i]) { return false; }
    i = i + 1;
  }
  return true;
}

fn le_byte(v: Int, k: Int) -> UInt8 {
  var q = v;
  var i = 0;
  while (i < k) {
    q = q / 256;
    i = i + 1;
  }
  return (q % 256) as UInt8;
}

fn push_le32(out: &mut Vec[UInt8], v: Int) {
  out.push(le_byte(v, 0));
  out.push(le_byte(v, 1));
  out.push(le_byte(v, 2));
  out.push(le_byte(v, 3));
}

fn set_le32(data: &Vec[UInt8], pos: Int, v: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while (i < data.len()) {
    if (i >= pos && i < pos + 4) {
      out.push(le_byte(v, i - pos));
    } else {
      out.push(data[i]);
    }
    i = i + 1;
  }
  return out;
}

fn truncate(data: &Vec[UInt8], n: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while (i < n) {
    out.push(data[i]);
    i = i + 1;
  }
  return out;
}

// --------------------------------------------------
//  Struct fixtures
// --------------------------------------------------

fn zero_pf() -> DdsPixelFormat {
  return DdsPixelFormat{
    size: 0; flags: 0; four_cc: 0; rgb_bit_count: 0;
    r_mask: 0; g_mask: 0; b_mask: 0; a_mask: 0;
  };
}

fn zero_hdr() -> DdsHeader {
  return DdsHeader{
    size: 0; flags: 0; height: 0; width: 0; pitch_or_linear_size: 0;
    depth: 0; mip_map_count: 0; pixel_format: zero_pf();
    caps: 0; caps2: 0; caps3: 0; caps4: 0; reserved2: 0;
  };
}

fn zero_dx10() -> DdsDxt10 {
  return DdsDxt10{
    dxgi_format: 0; resource_dimension: 0; misc_flag: 0;
    array_size: 0; misc_flags2: 0;
  };
}

fn zero_img() -> DdsImage {
  return DdsImage{
    header: zero_hdr(); dx10: zero_dx10(); has_dx10: false;
    data_offset: 0; data_bytes: 0;
  };
}

// Uncompressed RGB header with explicit width/height/bit count/masks.
fn rgb_hdr_of(w: Int, ht: Int, bits: Int, r: Int, g: Int, b: Int, a: Int) -> DdsHeader {
  return DdsHeader{
    size: 124;
    flags: DDSD_CAPS + DDSD_HEIGHT + DDSD_WIDTH + DDSD_PIXELFORMAT + DDSD_PITCH;
    height: ht; width: w; pitch_or_linear_size: w * bits / 8;
    depth: 0; mip_map_count: 0;
    pixel_format: DdsPixelFormat{
      size: 32; flags: DDPF_RGB; four_cc: 0; rgb_bit_count: bits;
      r_mask: r; g_mask: g; b_mask: b; a_mask: a;
    };
    caps: DDSCAPS_TEXTURE; caps2: 0; caps3: 0; caps4: 0; reserved2: 0;
  };
}

fn rgb_hdr() -> DdsHeader {
  return rgb_hdr_of(32, 64, 24, 16711680, 65280, 255, 0);
}

// Compressed fourCC header (DDSD_LINEARSIZE, no masks).
fn fourcc_hdr(code: Int) -> DdsHeader {
  return DdsHeader{
    size: 124;
    flags: DDSD_CAPS + DDSD_HEIGHT + DDSD_WIDTH + DDSD_PIXELFORMAT + DDSD_LINEARSIZE;
    height: 64; width: 32; pitch_or_linear_size: 2048;
    depth: 0; mip_map_count: 0;
    pixel_format: DdsPixelFormat{
      size: 32; flags: DDPF_FOURCC; four_cc: code; rgb_bit_count: 0;
      r_mask: 0; g_mask: 0; b_mask: 0; a_mask: 0;
    };
    caps: DDSCAPS_TEXTURE; caps2: 0; caps3: 0; caps4: 0; reserved2: 0;
  };
}

fn dx10_of(dxgi: Int, dim: Int, misc: Int, array_size: Int, misc2: Int) -> DdsDxt10 {
  return DdsDxt10{
    dxgi_format: dxgi; resource_dimension: dim; misc_flag: misc;
    array_size: array_size; misc_flags2: misc2;
  };
}

fn dx10_block() -> DdsDxt10 {
  return dx10_of(28, 3, 0, 1, 0);
}

fn append_bytes(dst: &mut Vec[UInt8], src: &Vec[UInt8]) {
  var i = 0;
  while (i < src.len()) {
    dst.push(src[i]);
    i = i + 1;
  }
}

fn built_rgb() -> Vec[UInt8] {
  let h = rgb_hdr();
  return ok_bytes(dds_build_header(&h));
}

fn built_dxt(code: Int) -> Vec[UInt8] {
  let h = fourcc_hdr(code);
  return ok_bytes(dds_build_header(&h));
}

fn built_dx10() -> Vec[UInt8] {
  let h = fourcc_hdr(DDS_FOURCC_DX10);
  let d = dx10_block();
  var out = ok_bytes(dds_build_header(&h));
  let db = ok_bytes(dds_build_dx10(&d));
  append_bytes(&mut out, &db);
  return out;
}

fn with_payload(prefix: &Vec[UInt8], n: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  append_bytes(&mut out, prefix);
  var j = 0;
  while (j < n) {
    out.push(((j * 7 + 3) % 251) as UInt8);
    j = j + 1;
  }
  return out;
}

// --------------------------------------------------
//  Checks
// --------------------------------------------------

// 1. Builder pins the 128-byte prefix byte for byte and round-trips.
fn t1() -> TestResult {
  let h = rgb_hdr();
  let d = ok_bytes(dds_build_header(&h));
  if (d.len() != 128) { return assert(false, "built prefix is 128 bytes"); }
  if (!bytes_at_is(d, 0, "DDS ")) { return assert(false, "magic is DDS followed by space"); }
  if (!byte_is(d, 4, 124)) { return assert(false, "header size low byte is 124"); }
  if (!byte_is(d, 5, 0)) { return assert(false, "header size byte 1 is 0"); }
  if (!byte_is(d, 6, 0)) { return assert(false, "header size byte 2 is 0"); }
  if (!byte_is(d, 7, 0)) { return assert(false, "header size byte 3 is 0"); }
  if (!byte_is(d, 8, 15)) { return assert(false, "flags low byte is 0x0F"); }
  if (!byte_is(d, 9, 16)) { return assert(false, "flags byte 1 is 0x10"); }
  if (!byte_is(d, 10, 0)) { return assert(false, "flags byte 2 is 0"); }
  if (!byte_is(d, 11, 0)) { return assert(false, "flags byte 3 is 0"); }
  if (!byte_is(d, 12, 64)) { return assert(false, "height low byte is 64"); }
  if (!byte_is(d, 13, 0)) { return assert(false, "height high byte is 0"); }
  if (!byte_is(d, 16, 32)) { return assert(false, "width low byte is 32"); }
  if (!byte_is(d, 20, 96)) { return assert(false, "pitch low byte is 96"); }
  var i = 32;
  while (i < 76) {
    if (!byte_is(d, i, 0)) { return assert(false, "reserved1 is all zero"); }
    i = i + 1;
  }
  if (!byte_is(d, 76, 32)) { return assert(false, "pixel format size is 32"); }
  if (!byte_is(d, 80, 64)) { return assert(false, "DDPF_RGB byte is 64"); }
  if (!byte_is(d, 84, 0)) { return assert(false, "fourCC is 0"); }
  if (!byte_is(d, 88, 24)) { return assert(false, "RGB bit count is 24"); }
  if (!byte_is(d, 92, 0)) { return assert(false, "red mask byte 0"); }
  if (!byte_is(d, 93, 0)) { return assert(false, "red mask byte 1"); }
  if (!byte_is(d, 94, 255)) { return assert(false, "red mask byte 2"); }
  if (!byte_is(d, 95, 0)) { return assert(false, "red mask byte 3"); }
  if (!byte_is(d, 108, 0)) { return assert(false, "caps low byte is 0"); }
  if (!byte_is(d, 109, 16)) { return assert(false, "caps high byte is 16"); }
  let back = ok_hdr(dds_parse_header(&d));
  if (back.size != 124) { return assert(false, "round-trip header size"); }
  if (back.flags != h.flags) { return assert(false, "round-trip flags"); }
  if (back.height != 64) { return assert(false, "round-trip height"); }
  if (back.width != 32) { return assert(false, "round-trip width"); }
  if (back.pitch_or_linear_size != 96) { return assert(false, "round-trip pitch"); }
  if (back.depth != 0) { return assert(false, "round-trip depth"); }
  if (back.mip_map_count != 0) { return assert(false, "round-trip mip count"); }
  if (back.pixel_format.size != 32) { return assert(false, "round-trip pf size"); }
  if (back.pixel_format.flags != DDPF_RGB) { return assert(false, "round-trip pf flags"); }
  if (back.pixel_format.rgb_bit_count != 24) { return assert(false, "round-trip bit count"); }
  if (back.pixel_format.r_mask != 16711680) { return assert(false, "round-trip red mask"); }
  if (back.pixel_format.g_mask != 65280) { return assert(false, "round-trip green mask"); }
  if (back.pixel_format.b_mask != 255) { return assert(false, "round-trip blue mask"); }
  if (back.pixel_format.a_mask != 0) { return assert(false, "round-trip alpha mask"); }
  if (back.caps != DDSCAPS_TEXTURE) { return assert(false, "round-trip caps"); }
  return assert(true, "built header pins little-endian bytes and round-trips");
}

// 2. RGB accessors report every decoded field.
fn t2() -> TestResult {
  let d = built_rgb();
  let img = ok_img(dds_parse(&d));
  if (img.has_dx10) { return assert(false, "rgb file has no dx10 block"); }
  if (img.data_offset != 128) { return assert(false, "data offset is 128"); }
  if (img.data_bytes != 0) { return assert(false, "header-only payload is empty"); }
  if (dds_width(&img) != 32) { return assert(false, "width 32"); }
  if (dds_height(&img) != 64) { return assert(false, "height 64"); }
  if (dds_depth(&img) != 0) { return assert(false, "depth 0"); }
  if (dds_mipmaps(&img) != 0) { return assert(false, "no mipmap count"); }
  if (dds_fourcc(&img) != 0) { return assert(false, "no fourCC"); }
  if (dds_has_dx10(&img)) { return assert(false, "has_dx10 is false"); }
  if (dds_rgb_bit_count(&img) != 24) { return assert(false, "bit count 24"); }
  if (dds_red_mask(&img) != 16711680) { return assert(false, "red mask 0x00FF0000"); }
  if (dds_green_mask(&img) != 65280) { return assert(false, "green mask 0x0000FF00"); }
  if (dds_blue_mask(&img) != 255) { return assert(false, "blue mask 0x000000FF"); }
  if (dds_alpha_mask(&img) != 0) { return assert(false, "alpha mask 0"); }
  if (dds_payload_offset(&img) != 128) { return assert(false, "payload offset 128"); }
  if (dds_payload_size(&img) != 0) { return assert(false, "payload size 0"); }
  if (!streq(dds_fourcc_text(dds_fourcc(&img)), "")) { return assert(false, "fourCC text is empty"); }
  if (!dds_is_valid(&d)) { return assert(false, "rgb buffer is valid"); }
  return assert(true, "rgb accessors report the decoded header fields");
}

// 3. Payload span and verbatim copy; truncation is rejected.
fn t3() -> TestResult {
  let p = built_rgb();
  let d = with_payload(&p, 10);
  if (d.len() != 138) { return assert(false, "128 + 10 bytes"); }
  let img = ok_img(dds_parse(&d));
  if (img.data_bytes != 10) { return assert(false, "payload is 10 bytes"); }
  if (dds_payload_offset(&img) != 128) { return assert(false, "payload starts at 128"); }
  if (dds_payload_size(&img) != 10) { return assert(false, "payload size accessor is 10"); }
  let copy = ok_bytes(dds_payload(&d));
  if (copy.len() != 10) { return assert(false, "payload copy is 10 bytes"); }
  var i = 0;
  while (i < 10) {
    let want = (i * 7 + 3) % 251;
    if (!byte_is(copy, i, want)) { return assert(false, "payload byte survives the copy"); }
    i = i + 1;
  }
  if (!dds_is_valid(&d)) { return assert(false, "payload buffer is valid"); }
  let short = truncate(&d, 100);
  if (dds_is_valid(&short)) { return assert(false, "100-byte buffer is invalid"); }
  if (!img_err_is(dds_parse(&short), "dds: truncated header")) {
    return assert(false, "100-byte buffer is a truncated header");
  }
  return assert(true, "payload is offset..end and copies verbatim");
}

// 4. fourCC text, recognition and the supported-shape predicate.
fn t4() -> TestResult {
  if (!streq(dds_fourcc_text(DDS_FOURCC_DXT1), "DXT1")) { return assert(false, "DXT1 text"); }
  if (!streq(dds_fourcc_text(DDS_FOURCC_DXT2), "DXT2")) { return assert(false, "DXT2 text"); }
  if (!streq(dds_fourcc_text(DDS_FOURCC_DXT3), "DXT3")) { return assert(false, "DXT3 text"); }
  if (!streq(dds_fourcc_text(DDS_FOURCC_DXT4), "DXT4")) { return assert(false, "DXT4 text"); }
  if (!streq(dds_fourcc_text(DDS_FOURCC_DXT5), "DXT5")) { return assert(false, "DXT5 text"); }
  if (!streq(dds_fourcc_text(DDS_FOURCC_DX10), "DX10")) { return assert(false, "DX10 text"); }
  if (!streq(dds_fourcc_text(843666497), "ATI2")) { return assert(false, "ATI2 text"); }
  if (!streq(dds_fourcc_text(1429488450), "BC4U")) { return assert(false, "BC4U text"); }
  if (!streq(dds_fourcc_text(1498831189), "UYVY")) { return assert(false, "UYVY text"); }
  if (!streq(dds_fourcc_text(0), "")) { return assert(false, "code 0 has no text"); }
  if (!streq(dds_fourcc_text(1), "....")) { return assert(false, "non-printable bytes render as dots"); }
  if (!dds_fourcc_recognized(DDS_FOURCC_DXT1)) { return assert(false, "DXT1 is recognized"); }
  if (!dds_fourcc_recognized(DDS_FOURCC_DXT2)) { return assert(false, "DXT2 is recognized"); }
  if (!dds_fourcc_recognized(DDS_FOURCC_DXT3)) { return assert(false, "DXT3 is recognized"); }
  if (!dds_fourcc_recognized(DDS_FOURCC_DXT4)) { return assert(false, "DXT4 is recognized"); }
  if (!dds_fourcc_recognized(DDS_FOURCC_DXT5)) { return assert(false, "DXT5 is recognized"); }
  if (!dds_fourcc_recognized(DDS_FOURCC_DX10)) { return assert(false, "DX10 is recognized"); }
  if (dds_fourcc_recognized(1498831189)) { return assert(false, "UYVY is pass-through"); }
  if (dds_fourcc_recognized(0)) { return assert(false, "code 0 is not recognized"); }
  if (!dds_pixel_format_supported(DDPF_FOURCC, 1498831189)) {
    return assert(false, "unknown fourCC is inside the supported shape");
  }
  if (dds_pixel_format_supported(DDPF_FOURCC, 0)) {
    return assert(false, "fourCC with code 0 is unsupported");
  }
  if (dds_pixel_format_supported(DDPF_FOURCC + DDPF_RGB, DDS_FOURCC_DXT1)) {
    return assert(false, "FOURCC plus RGB is unsupported");
  }
  if (dds_pixel_format_supported(DDPF_RGB, DDS_FOURCC_DXT1)) {
    return assert(false, "RGB with a fourCC code is unsupported");
  }
  if (!dds_pixel_format_supported(DDPF_RGB, 0)) { return assert(false, "RGB shape is supported"); }
  if (dds_pixel_format_supported(0, 0)) { return assert(false, "empty flags are unsupported"); }
  return assert(true, "fourCC text, recognition and support predicate are exact");
}

// 5. DXT1 file parses with zeroed masks.
fn t5() -> TestResult {
  let d = built_dxt(DDS_FOURCC_DXT1);
  let img = ok_img(dds_parse(&d));
  if (dds_fourcc(&img) != DDS_FOURCC_DXT1) { return assert(false, "fourCC is DXT1"); }
  if (dds_rgb_bit_count(&img) != 0) { return assert(false, "bit count is 0 for fourCC"); }
  if (dds_red_mask(&img) != 0) { return assert(false, "red mask is 0 for fourCC"); }
  if (dds_alpha_mask(&img) != 0) { return assert(false, "alpha mask is 0 for fourCC"); }
  if (dds_has_dx10(&img)) { return assert(false, "DXT1 has no dx10 block"); }
  if (dds_payload_offset(&img) != 128) { return assert(false, "DXT1 payload starts at 128"); }
  if (!streq(dds_fourcc_text(dds_fourcc(&img)), "DXT1")) { return assert(false, "DXT1 text accessor"); }
  if (!dds_fourcc_recognized(dds_fourcc(&img))) { return assert(false, "DXT1 is recognized"); }
  let h = ok_hdr(dds_parse_header(&d));
  if (h.pixel_format.flags != DDPF_FOURCC) { return assert(false, "pf flags are DDPF_FOURCC"); }
  if (h.flags != fourcc_hdr(DDS_FOURCC_DXT1).flags) { return assert(false, "header flags round-trip"); }
  return assert(true, "DXT1 header parses with zeroed masks");
}

// 6. Every accepted fourCC variant parses: DXT1..DXT5, DX10, pass-through.
fn t6() -> TestResult {
  let codes = Vec[Int].new();
  codes.push(DDS_FOURCC_DXT1);
  codes.push(DDS_FOURCC_DXT2);
  codes.push(DDS_FOURCC_DXT3);
  codes.push(DDS_FOURCC_DXT4);
  codes.push(DDS_FOURCC_DXT5);
  codes.push(DDS_FOURCC_DX10);
  var i = 0;
  while (i < codes.len()) {
    let code: Int = codes[i];
    var d = Vec[UInt8].new();
    if (code == DDS_FOURCC_DX10) {
      d = built_dx10();
    } else {
      d = built_dxt(code);
    }
    if (bad_img(dds_parse(&d))) { return assert(false, "recognized fourCC parses"); }
    let img = ok_img(dds_parse(&d));
    if (dds_fourcc(&img) != code) { return assert(false, "fourCC round-trips"); }
    if (!dds_fourcc_recognized(code)) { return assert(false, "variant is recognized"); }
    i = i + 1;
  }
  let passthru = Vec[Int].new();
  passthru.push(843666497);
  passthru.push(1429488450);
  passthru.push(1498831189);
  var k = 0;
  while (k < passthru.len()) {
    let code2: Int = passthru[k];
    let d2 = built_dxt(code2);
    if (bad_img(dds_parse(&d2))) { return assert(false, "pass-through fourCC parses"); }
    let img2 = ok_img(dds_parse(&d2));
    if (dds_fourcc(&img2) != code2) { return assert(false, "pass-through code round-trips"); }
    if (dds_fourcc_recognized(code2)) { return assert(false, "pass-through code stays unrecognized"); }
    k = k + 1;
  }
  return assert(true, "all accepted fourCC variants parse and round-trip");
}

// 7. DX10 block round-trip through parse and dds_build.
fn t7() -> TestResult {
  let prefix = built_dx10();
  if (prefix.len() != 148) { return assert(false, "dx10 prefix is 148 bytes"); }
  let d = with_payload(&prefix, 16);
  let img = ok_img(dds_parse(&d));
  if (!img.has_dx10) { return assert(false, "dx10 block detected"); }
  if (img.data_offset != 148) { return assert(false, "dx10 data offset 148"); }
  if (img.data_bytes != 16) { return assert(false, "dx10 payload is 16 bytes"); }
  if (!dds_has_dx10(&img)) { return assert(false, "has_dx10 accessor"); }
  if (dds_dxgi_format(&img) != 28) { return assert(false, "dxgi format 28"); }
  if (dds_resource_dimension(&img) != 3) { return assert(false, "resource dimension 3"); }
  if (dds_misc_flag(&img) != 0) { return assert(false, "misc flag 0"); }
  if (dds_array_size(&img) != 1) { return assert(false, "array size 1"); }
  if (dds_misc_flags2(&img) != 0) { return assert(false, "misc flags2 0"); }
  if (!streq(dds_fourcc_text(dds_fourcc(&img)), "DX10")) { return assert(false, "DX10 text accessor"); }
  let payload = ok_bytes(dds_payload(&d));
  let out = ok_bytes(dds_build(&img, &payload));
  if (!bytes_equal(&out, &d)) { return assert(false, "dds_build reproduces the dx10 file"); }
  return assert(true, "dx10 file parses and rebuilds byte-for-byte");
}

// 8. Non-DX10 file rebuilds byte-for-byte, header included.
fn t8() -> TestResult {
  let prefix = built_rgb();
  let d = with_payload(&prefix, 24);
  let img = ok_img(dds_parse(&d));
  let payload = ok_bytes(dds_payload(&d));
  let out = ok_bytes(dds_build(&img, &payload));
  if (!bytes_equal(&out, &d)) { return assert(false, "dds_build reproduces the rgb file"); }
  if (out.len() != 152) { return assert(false, "rebuilt file is 152 bytes"); }
  let h = rgb_hdr();
  let hb = ok_bytes(dds_build_header(&h));
  if (!bytes_equal(&hb, &prefix)) { return assert(false, "builder header is deterministic"); }
  return assert(true, "rgb build-then-parse round-trips byte-for-byte");
}

// 9. Structural validation: truncation, magic, sizes, reserved1/reserved2.
fn t9() -> TestResult {
  let d = built_rgb();
  let short = truncate(&d, 127);
  if (!hdr_err_is(dds_parse_header(&short), "dds: truncated header")) {
    return assert(false, "127 bytes is a truncated header");
  }
  if (!img_err_is(dds_parse(&short), "dds: truncated header")) {
    return assert(false, "full parse forwards truncation");
  }
  let bad = set_le32(&d, 0, 88);
  if (!hdr_err_is(dds_parse_header(&bad), "dds: bad magic")) {
    return assert(false, "corrupt magic is rejected");
  }
  let bad2 = set_le32(&d, 2, 84);
  if (!hdr_err_is(dds_parse_header(&bad2), "dds: bad magic")) {
    return assert(false, "corrupt magic byte 2 is rejected");
  }
  let sz = set_le32(&d, 4, 123);
  if (!hdr_err_is(dds_parse_header(&sz), "dds: invalid header size")) {
    return assert(false, "header size 123 is rejected");
  }
  let psz = set_le32(&d, 76, 31);
  if (!hdr_err_is(dds_parse_header(&psz), "dds: invalid pixel format size")) {
    return assert(false, "pixel format size 31 is rejected");
  }
  let res = set_le32(&d, 32, 7);
  if (!hdr_err_is(dds_parse_header(&res), "dds: nonzero reserved1")) {
    return assert(false, "nonzero reserved1 is rejected");
  }
  let res2 = set_le32(&d, 124, 9);
  let h = ok_hdr(dds_parse_header(&res2));
  if (h.reserved2 != 9) { return assert(false, "reserved2 is retained verbatim"); }
  let again = ok_bytes(dds_build_header(&h));
  if (!byte_is(again, 124, 9)) { return assert(false, "reserved2 is re-emitted"); }
  return assert(true, "structural header fields are validated and pinned");
}

// 10. Required flags and pitch/linear-size exclusivity.
fn t10() -> TestResult {
  let d = built_rgb();
  let no_caps = set_le32(&d, 8, DDSD_HEIGHT + DDSD_WIDTH + DDSD_PIXELFORMAT + DDSD_PITCH);
  if (!hdr_err_is(dds_parse_header(&no_caps), "dds: missing required flags")) {
    return assert(false, "missing DDSD_CAPS is rejected");
  }
  let no_width = set_le32(&d, 8, DDSD_CAPS + DDSD_HEIGHT + DDSD_PIXELFORMAT + DDSD_PITCH);
  if (!hdr_err_is(dds_parse_header(&no_width), "dds: missing required flags")) {
    return assert(false, "missing DDSD_WIDTH is rejected");
  }
  let both = set_le32(&d, 8, DDSD_CAPS + DDSD_HEIGHT + DDSD_WIDTH + DDSD_PIXELFORMAT + DDSD_PITCH + DDSD_LINEARSIZE);
  if (!hdr_err_is(dds_parse_header(&both), "dds: conflicting pitch flags")) {
    return assert(false, "PITCH plus LINEARSIZE is rejected");
  }
  let linear = set_le32(&d, 8, DDSD_CAPS + DDSD_HEIGHT + DDSD_WIDTH + DDSD_PIXELFORMAT + DDSD_LINEARSIZE);
  if (bad_hdr(dds_parse_header(&linear))) { return assert(false, "LINEARSIZE alone is fine"); }
  return assert(true, "required flags and pitch exclusivity are enforced");
}

// 11. Zero and oversized dimensions are rejected.
fn t11() -> TestResult {
  let d = built_rgb();
  let w0 = set_le32(&d, 16, 0);
  if (!hdr_err_is(dds_parse_header(&w0), "dds: invalid width")) {
    return assert(false, "width 0 is rejected");
  }
  let h0 = set_le32(&d, 12, 0);
  if (!hdr_err_is(dds_parse_header(&h0), "dds: invalid height")) {
    return assert(false, "height 0 is rejected");
  }
  let w1 = set_le32(&d, 16, 1000001);
  if (!hdr_err_is(dds_parse_header(&w1), "dds: invalid width")) {
    return assert(false, "width above the cap is rejected");
  }
  let h1 = set_le32(&d, 12, 1000001);
  if (!hdr_err_is(dds_parse_header(&h1), "dds: invalid height")) {
    return assert(false, "height above the cap is rejected");
  }
  return assert(true, "zero and oversized dimensions are rejected");
}

// 12. depth, mipMapCount and volume cross-checks.
fn t12() -> TestResult {
  let d = built_rgb();
  let dz = set_le32(&d, 24, 4);
  if (!hdr_err_is(dds_parse_header(&dz), "dds: depth without DDSD_DEPTH")) {
    return assert(false, "depth without the flag is rejected");
  }
  let dflag = set_le32(&d, 8, DDSD_CAPS + DDSD_HEIGHT + DDSD_WIDTH + DDSD_PIXELFORMAT + DDSD_PITCH + DDSD_DEPTH);
  if (!hdr_err_is(dds_parse_header(&dflag), "dds: invalid depth")) {
    return assert(false, "DDSD_DEPTH with depth 0 is rejected");
  }
  let mz = set_le32(&d, 8, DDSD_CAPS + DDSD_HEIGHT + DDSD_WIDTH + DDSD_PIXELFORMAT + DDSD_PITCH + DDSD_MIPMAPCOUNT);
  if (!hdr_err_is(dds_parse_header(&mz), "dds: invalid mipmap count")) {
    return assert(false, "DDSD_MIPMAPCOUNT with count 0 is rejected");
  }
  let mf = set_le32(&d, 28, 3);
  if (!hdr_err_is(dds_parse_header(&mf), "dds: mipmaps without DDSD_MIPMAPCOUNT")) {
    return assert(false, "count without the flag is rejected");
  }
  let vo = set_le32(&d, 112, DDSCAPS2_VOLUME);
  if (!hdr_err_is(dds_parse_header(&vo), "dds: volume without depth")) {
    return assert(false, "volume caps without depth is rejected");
  }
  var v = set_le32(&d, 24, 2);
  v = set_le32(&v, 8, DDSD_CAPS + DDSD_HEIGHT + DDSD_WIDTH + DDSD_PIXELFORMAT + DDSD_PITCH + DDSD_DEPTH);
  v = set_le32(&v, 112, DDSCAPS2_VOLUME);
  let vimg = ok_img(dds_parse(&v));
  if (dds_depth(&vimg) != 2) { return assert(false, "volume depth round-trips"); }
  var m = set_le32(&d, 28, 3);
  m = set_le32(&m, 8, DDSD_CAPS + DDSD_HEIGHT + DDSD_WIDTH + DDSD_PIXELFORMAT + DDSD_PITCH + DDSD_MIPMAPCOUNT);
  let mimg = ok_img(dds_parse(&m));
  if (dds_mipmaps(&mimg) != 3) { return assert(false, "mipmap count round-trips"); }
  return assert(true, "depth, mipmaps and volume caps are cross-checked");
}

// 13. Pixel format flag shapes.
fn t13() -> TestResult {
  let d = built_rgb();
  var f = set_le32(&d, 80, DDPF_FOURCC);
  f = set_le32(&f, 84, 0);
  if (!hdr_err_is(dds_parse_header(&f), "dds: missing fourCC")) {
    return assert(false, "FOURCC without a code is rejected");
  }
  var g = set_le32(&d, 80, DDPF_FOURCC + DDPF_RGB);
  g = set_le32(&g, 84, DDS_FOURCC_DXT1);
  if (!hdr_err_is(dds_parse_header(&g), "dds: conflicting pixel format flags")) {
    return assert(false, "FOURCC plus RGB is rejected");
  }
  let n = set_le32(&d, 80, 0);
  if (!hdr_err_is(dds_parse_header(&n), "dds: unsupported pixel format")) {
    return assert(false, "empty pixel format flags are rejected");
  }
  let u = set_le32(&d, 84, DDS_FOURCC_DXT1);
  if (!hdr_err_is(dds_parse_header(&u), "dds: unexpected fourCC")) {
    return assert(false, "RGB with a fourCC code is rejected");
  }
  let b8 = set_le32(&d, 88, 8);
  if (!hdr_err_is(dds_parse_header(&b8), "dds: unsupported RGB bit count")) {
    return assert(false, "8-bit RGB is rejected");
  }
  let b0 = set_le32(&d, 88, 0);
  if (!hdr_err_is(dds_parse_header(&b0), "dds: unsupported RGB bit count")) {
    return assert(false, "0-bit RGB is rejected");
  }
  return assert(true, "pixel format flag shapes are validated");
}

// 14. RGB mask rules, including the 16-bit 565 case.
fn t14() -> TestResult {
  let d = built_rgb();
  let zr = set_le32(&d, 92, 0);
  if (!hdr_err_is(dds_parse_header(&zr), "dds: invalid RGB masks")) {
    return assert(false, "zero red mask is rejected");
  }
  let ov = set_le32(&d, 96, 16711680);
  if (!hdr_err_is(dds_parse_header(&ov), "dds: overlapping color masks")) {
    return assert(false, "overlapping red and green is rejected");
  }
  let oa = set_le32(&d, 104, 16711680);
  if (!hdr_err_is(dds_parse_header(&oa), "dds: overlapping color masks")) {
    return assert(false, "overlapping alpha is rejected");
  }
  var orr = set_le32(&d, 88, 16);
  orr = set_le32(&orr, 92, 16711680);
  orr = set_le32(&orr, 96, 65280);
  orr = set_le32(&orr, 100, 255);
  if (!hdr_err_is(dds_parse_header(&orr), "dds: color mask out of range")) {
    return assert(false, "24-bit mask in a 16-bit format is rejected");
  }
  var v = set_le32(&d, 88, 16);
  v = set_le32(&v, 92, 63488);
  v = set_le32(&v, 96, 2016);
  v = set_le32(&v, 100, 31);
  let img = ok_img(dds_parse(&v));
  if (dds_rgb_bit_count(&img) != 16) { return assert(false, "565 bit count"); }
  if (dds_red_mask(&img) != 63488) { return assert(false, "565 red mask"); }
  if (dds_green_mask(&img) != 2016) { return assert(false, "565 green mask"); }
  if (dds_blue_mask(&img) != 31) { return assert(false, "565 blue mask"); }
  return assert(true, "RGB masks must be nonzero, disjoint and in range");
}

// 15. DXT10 block field validation.
fn t15() -> TestResult {
  let full = built_dx10();
  let d128 = truncate(&full, 128);
  if (!img_err_is(dds_parse(&d128), "dds: truncated dx10 header")) {
    return assert(false, "dx10 fourCC without the block is rejected");
  }
  if (dds_is_valid(&d128)) { return assert(false, "truncated dx10 buffer is invalid"); }
  let d147 = truncate(&full, 147);
  if (!img_err_is(dds_parse(&d147), "dds: truncated dx10 header")) {
    return assert(false, "147-byte dx10 buffer is rejected");
  }
  let dim0 = set_le32(&full, 132, 0);
  if (!img_err_is(dds_parse(&dim0), "dds: invalid resource dimension")) {
    return assert(false, "dimension 0 is rejected");
  }
  let dim5 = set_le32(&full, 132, 5);
  if (!img_err_is(dds_parse(&dim5), "dds: invalid resource dimension")) {
    return assert(false, "dimension 5 is rejected");
  }
  let arr0 = set_le32(&full, 140, 0);
  if (!img_err_is(dds_parse(&arr0), "dds: invalid array size")) {
    return assert(false, "array size 0 is rejected");
  }
  let img = ok_img(dds_parse(&full));
  if (img.data_bytes != 0) { return assert(false, "dx10 header-only parse has empty payload"); }
  return assert(true, "dx10 block fields are validated");
}

// 16. Builder range and semantic errors.
fn t16() -> TestResult {
  let hw = rgb_hdr_of(-1, 64, 24, 16711680, 65280, 255, 0);
  if (!bytes_err_is(dds_build_header(&hw), "dds: width out of range")) {
    return assert(false, "negative width is a range error");
  }
  let hh = rgb_hdr_of(32, -1, 24, 16711680, 65280, 255, 0);
  if (!bytes_err_is(dds_build_header(&hh), "dds: height out of range")) {
    return assert(false, "negative height is a range error");
  }
  let hx = fourcc_hdr(4294967296);
  if (!bytes_err_is(dds_build_header(&hx), "dds: fourCC out of range")) {
    return assert(false, "fourCC above u32 is a range error");
  }
  let bad_size = DdsHeader{
    size: 100; flags: DDSD_CAPS + DDSD_HEIGHT + DDSD_WIDTH + DDSD_PIXELFORMAT;
    height: 1; width: 1; pitch_or_linear_size: 0; depth: 0; mip_map_count: 0;
    pixel_format: zero_pf(); caps: 0; caps2: 0; caps3: 0; caps4: 0; reserved2: 0;
  };
  if (!bytes_err_is(dds_build_header(&bad_size), "dds: invalid header size")) {
    return assert(false, "builder requires size 124");
  }
  let bad_pf = rgb_hdr_of(1, 1, 8, 1, 2, 4, 0);
  if (!bytes_err_is(dds_build_header(&bad_pf), "dds: unsupported RGB bit count")) {
    return assert(false, "builder forwards parser mask/bit rules");
  }
  let dx_bad = dx10_of(28, 9, 0, 1, 0);
  if (!bytes_err_is(dds_build_dx10(&dx_bad), "dds: invalid resource dimension")) {
    return assert(false, "dx10 builder checks the dimension");
  }
  let dx_arr = dx10_of(28, 3, 0, 0, 0);
  if (!bytes_err_is(dds_build_dx10(&dx_arr), "dds: invalid array size")) {
    return assert(false, "dx10 builder checks the array size");
  }
  let dx_neg = dx10_of(-1, 3, 0, 1, 0);
  if (!bytes_err_is(dds_build_dx10(&dx_neg), "dds: dxgi format out of range")) {
    return assert(false, "dx10 builder checks the dxgi range");
  }
  return assert(true, "builder range and semantic errors are deterministic");
}

// 17. dds_build cross-checks the dx10 flag and the payload size.
fn t17() -> TestResult {
  let prefix = built_dx10();
  let d = with_payload(&prefix, 8);
  let img = ok_img(dds_parse(&d));
  let payload = ok_bytes(dds_payload(&d));
  let img_bad = DdsImage{
    header: img.header; dx10: img.dx10; has_dx10: false;
    data_offset: 148; data_bytes: 8;
  };
  if (!bytes_err_is(dds_build(&img_bad, &payload), "dds: dx10 flag mismatch")) {
    return assert(false, "has_dx10 must agree with the fourCC");
  }
  let short = truncate(&payload, 7);
  if (!bytes_err_is(dds_build(&img, &short), "dds: payload size mismatch")) {
    return assert(false, "payload length must equal data_bytes");
  }
  let img_dx = DdsImage{
    header: img.header; dx10: dx10_of(28, 9, 0, 1, 0); has_dx10: true;
    data_offset: 148; data_bytes: 8;
  };
  if (!bytes_err_is(dds_build(&img_dx, &payload), "dds: invalid resource dimension")) {
    return assert(false, "builder forwards dx10 field errors");
  }
  return assert(true, "dds_build cross-checks the dx10 flag and payload size");
}

// 18. Header-only buffers and empty payloads at both offsets.
fn t18() -> TestResult {
  let h = rgb_hdr();
  let hd = ok_bytes(dds_build_header(&h));
  if (!dds_is_valid(&hd)) { return assert(false, "128-byte rgb header is valid"); }
  let hdr_only = ok_img(dds_parse(&hd));
  if (hdr_only.data_bytes != 0) { return assert(false, "bare header payload is empty"); }
  let copy = ok_bytes(dds_payload(&hd));
  if (copy.len() != 0) { return assert(false, "bare header payload copy is empty"); }
  let hp = ok_hdr(dds_parse_header(&hd));
  if (hp.width != 32) { return assert(false, "header-only parse decodes width"); }
  let dx = built_dx10();
  if (!dds_is_valid(&dx)) { return assert(false, "148-byte dx10 header is valid"); }
  let di = ok_img(dds_parse(&dx));
  if (di.data_bytes != 0) { return assert(false, "bare dx10 payload is empty"); }
  if (!di.has_dx10) { return assert(false, "bare dx10 parse keeps the flag"); }
  let dp = ok_bytes(dds_payload(&dx));
  if (dp.len() != 0) { return assert(false, "bare dx10 payload copy is empty"); }
  return assert(true, "header-only buffers parse at both data offsets");
}

fn main() -> Int {
  io.println("=== xiom.dds conformance tests ===");
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
    io.println("xiom.dds: all tests passed");
  } else {
    io.println("xiom.dds: tests failed");
  }
  return failed;
}
