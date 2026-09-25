// XIOM -- xiom.pcx conformance tests (18 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module pcx_tests
use xiom.io; use xiom.test; use xiom.pcx;
use xiom.string; use xiom.string.compare;

// All Str equality goes through str_compare: `==` on a Str lowered from a
// Vec[Str] element is a pointer comparison in v0.61.3.
fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// Append the low 16 bits of v, little-endian.
fn push_u16(out: &mut Vec[UInt8], v: Int) {
  out.push((v % 256) as UInt8);
  out.push(((v / 256) % 256) as UInt8);
}

// Hand-built 128-byte header, independent of the library: manufacturer 10,
// version 5, encoding 1, hdpi/vdpi 72, hscreen/vscreen 640x480, reserved 0,
// deterministic 48-byte header palette p(i) = (i * 5 + 7) % 256.
fn mk_hdr(bits: Int, planes: Int, xmin: Int, ymin: Int, xmax: Int, ymax: Int, bpl: Int, ptype: Int) -> Vec[UInt8] {
  var d = Vec[UInt8].new();
  d.push(10 as UInt8);
  d.push(5 as UInt8);
  d.push(1 as UInt8);
  d.push(bits as UInt8);
  push_u16(&mut d, xmin);
  push_u16(&mut d, ymin);
  push_u16(&mut d, xmax);
  push_u16(&mut d, ymax);
  push_u16(&mut d, 72);
  push_u16(&mut d, 72);
  var i = 0;
  while (i < 48) {
    d.push(((i * 5 + 7) % 256) as UInt8);
    i = i + 1;
  }
  d.push(0 as UInt8);
  d.push(planes as UInt8);
  push_u16(&mut d, bpl);
  push_u16(&mut d, ptype);
  push_u16(&mut d, 640);
  push_u16(&mut d, 480);
  while (d.len() < 128) {
    d.push(0 as UInt8);
  }
  return d;
}

// Append `count` opaque RLE bytes with values 1..count.
fn append_rle(out: &mut Vec[UInt8], count: Int) {
  var i = 0;
  while (i < count) {
    out.push(((i + 1) % 256) as UInt8);
    i = i + 1;
  }
}

// Append the VGA palette trailer: 0x0C marker plus 768 bytes
// v(j) = (j * 7 + 3) % 256.
fn append_vga(out: &mut Vec[UInt8]) {
  out.push(12 as UInt8);
  var j = 0;
  while (j < 768) {
    out.push(((j * 7 + 3) % 256) as UInt8);
    j = j + 1;
  }
}

fn concat_bytes(a: &Vec[UInt8], b: &Vec[UInt8]) -> Vec[UInt8] {
  let out = Vec[UInt8].new();
  var i = 0;
  while (i < a.len()) {
    let x: UInt8 = a[i];
    out.push(x);
    i = i + 1;
  }
  i = 0;
  while (i < b.len()) {
    let x: UInt8 = b[i];
    out.push(x);
    i = i + 1;
  }
  return out;
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

fn ok_int(r: Result[Int, Str]) -> Int {
  match r {
    Ok(v) => { return v; },
    Err(e) => { return -1; },
  }
}

fn int_err_is(r: Result[Int, Str], want: Str) -> Bool {
  match r {
    Ok(v) => { return false; },
    Err(e) => { return streq(e, want); },
  }
}

fn zero_hdr() -> PcxHeader {
  return PcxHeader{
    manufacturer: 0; version: 0; encoding: 0; bits_per_pixel: 0;
    xmin: 0; ymin: 0; xmax: 0; ymax: 0;
    hdpi: 0; vdpi: 0; reserved: 0; color_planes: 0;
    bytes_per_line: 0; palette_type: 0; hscreen: 0; vscreen: 0;
    width: 0; height: 0;
  };
}

fn zero_info() -> PcxInfo {
  return PcxInfo{
    header: zero_hdr(); has_vga_palette: false; trailer_offset: 0;
    pixel_offset: 0; pixel_bytes: 0;
  };
}

fn ok_hdr(r: Result[PcxHeader, Str]) -> PcxHeader {
  match r {
    Ok(v) => { return v; },
    Err(e) => { return zero_hdr(); },
  }
}

fn bad_hdr(r: Result[PcxHeader, Str]) -> Bool {
  match r {
    Ok(v) => { return false; },
    Err(e) => { return true; },
  }
}

fn hdr_err_is(r: Result[PcxHeader, Str], want: Str) -> Bool {
  match r {
    Ok(v) => { return false; },
    Err(e) => { return streq(e, want); },
  }
}

fn ok_info(r: Result[PcxInfo, Str]) -> PcxInfo {
  match r {
    Ok(v) => { return v; },
    Err(e) => { return zero_info(); },
  }
}

fn info_err_is(r: Result[PcxInfo, Str], want: Str) -> Bool {
  match r {
    Ok(v) => { return false; },
    Err(e) => { return streq(e, want); },
  }
}

// Valid builder header: 2x1, 8 bpp, 1 plane, 2 bytes per line.
fn base_h() -> PcxHeader {
  return PcxHeader{
    manufacturer: 10; version: 5; encoding: 1; bits_per_pixel: 8;
    xmin: 0; ymin: 0; xmax: 1; ymax: 0;
    hdpi: 72; vdpi: 72; reserved: 0; color_planes: 1;
    bytes_per_line: 2; palette_type: 1; hscreen: 640; vscreen: 480;
    width: 2; height: 1;
  };
}

// 48-byte builder palette p(i) = (i * 11 + 5) % 256.
fn base_pal() -> Vec[UInt8] {
  let p = Vec[UInt8].new();
  var i = 0;
  while (i < 48) {
    p.push(((i * 11 + 5) % 256) as UInt8);
    i = i + 1;
  }
  return p;
}

fn t1() -> TestResult {
  let d = mk_hdr(8, 1, 0, 0, 0, 0, 2, 1);
  if (d.len() != 128) { return assert(false, "hand-built header is 128 bytes"); }
  match pcx_parse_header(d) {
    Ok(h) => {
      if (h.manufacturer != 10) { return assert(false, "manufacturer is 10"); }
      if (h.version != 5) { return assert(false, "version is 5"); }
      if (h.encoding != 1) { return assert(false, "encoding is 1"); }
      if (h.bits_per_pixel != 8) { return assert(false, "bits per pixel is 8"); }
      if (h.xmin != 0) { return assert(false, "xmin is 0"); }
      if (h.ymin != 0) { return assert(false, "ymin is 0"); }
      if (h.xmax != 0) { return assert(false, "xmax is 0"); }
      if (h.ymax != 0) { return assert(false, "ymax is 0"); }
      if (h.hdpi != 72) { return assert(false, "hdpi is 72"); }
      if (h.vdpi != 72) { return assert(false, "vdpi is 72"); }
      if (h.reserved != 0) { return assert(false, "reserved is 0"); }
      if (h.color_planes != 1) { return assert(false, "color planes is 1"); }
      if (h.bytes_per_line != 2) { return assert(false, "bytes per line is 2"); }
      if (h.palette_type != 1) { return assert(false, "palette type is 1"); }
      if (h.hscreen != 640) { return assert(false, "hscreen is 640"); }
      if (h.vscreen != 480) { return assert(false, "vscreen is 480"); }
      if (h.width != 1) { return assert(false, "width is 1"); }
      if (h.height != 1) { return assert(false, "height is 1"); }
      return assert(true, "hand-built 1x1 8bpp header decodes every field");
    },
    Err(e) => { return assert(false, "hand-built header was rejected"); },
  }
}

fn t2() -> TestResult {
  var h = base_h();
  h.xmin = 1; h.ymin = 2; h.xmax = 320; h.ymax = 200;
  h.hdpi = 300; h.vdpi = 300;
  h.color_planes = 3; h.bytes_per_line = 322;
  h.width = 0; h.height = 0;
  let pal = base_pal();
  let d = ok_bytes(pcx_build_header(h, pal));
  if (d.len() != 128) { return assert(false, "built header is 128 bytes"); }
  if (!byte_is(d, 0, 10)) { return assert(false, "manufacturer byte is 10"); }
  if (!byte_is(d, 1, 5)) { return assert(false, "version byte is 5"); }
  if (!byte_is(d, 2, 1)) { return assert(false, "encoding byte is 1"); }
  if (!byte_is(d, 3, 8)) { return assert(false, "bits byte is 8"); }
  if (!byte_is(d, 4, 1)) { return assert(false, "xmin low byte"); }
  if (!byte_is(d, 5, 0)) { return assert(false, "xmin high byte"); }
  if (!byte_is(d, 6, 2)) { return assert(false, "ymin low byte"); }
  if (!byte_is(d, 7, 0)) { return assert(false, "ymin high byte"); }
  if (!byte_is(d, 8, 64)) { return assert(false, "xmax low byte"); }
  if (!byte_is(d, 9, 1)) { return assert(false, "xmax high byte"); }
  if (!byte_is(d, 10, 200)) { return assert(false, "ymax low byte"); }
  if (!byte_is(d, 11, 0)) { return assert(false, "ymax high byte"); }
  if (!byte_is(d, 12, 44)) { return assert(false, "hdpi low byte"); }
  if (!byte_is(d, 13, 1)) { return assert(false, "hdpi high byte"); }
  if (!byte_is(d, 14, 44)) { return assert(false, "vdpi low byte"); }
  if (!byte_is(d, 15, 1)) { return assert(false, "vdpi high byte"); }
  if (!byte_is(d, 16, 5)) { return assert(false, "palette starts at offset 16"); }
  if (!byte_is(d, 63, 10)) { return assert(false, "palette ends at offset 63"); }
  if (!byte_is(d, 64, 0)) { return assert(false, "reserved byte is 0"); }
  if (!byte_is(d, 65, 3)) { return assert(false, "planes byte is 3"); }
  if (!byte_is(d, 66, 66)) { return assert(false, "bytes per line low byte"); }
  if (!byte_is(d, 67, 1)) { return assert(false, "bytes per line high byte"); }
  if (!byte_is(d, 68, 1)) { return assert(false, "palette type low byte"); }
  if (!byte_is(d, 69, 0)) { return assert(false, "palette type high byte"); }
  if (!byte_is(d, 70, 128)) { return assert(false, "hscreen low byte"); }
  if (!byte_is(d, 71, 2)) { return assert(false, "hscreen high byte"); }
  if (!byte_is(d, 72, 224)) { return assert(false, "vscreen low byte"); }
  if (!byte_is(d, 73, 1)) { return assert(false, "vscreen high byte"); }
  var i = 74;
  while (i < 128) {
    if (!byte_is(d, i, 0)) { return assert(false, "filler bytes are zero"); }
    i = i + 1;
  }
  match pcx_parse_header(d) {
    Ok(b) => {
      if (b.xmin != 1) { return assert(false, "round-trip xmin"); }
      if (b.ymin != 2) { return assert(false, "round-trip ymin"); }
      if (b.xmax != 320) { return assert(false, "round-trip xmax"); }
      if (b.ymax != 200) { return assert(false, "round-trip ymax"); }
      if (b.width != 320) { return assert(false, "width is xmax - xmin + 1"); }
      if (b.height != 199) { return assert(false, "height is ymax - ymin + 1"); }
      if (b.hdpi != 300) { return assert(false, "round-trip hdpi"); }
      if (b.color_planes != 3) { return assert(false, "round-trip planes"); }
      if (b.bytes_per_line != 322) { return assert(false, "round-trip bytes per line"); }
      return assert(true, "build pins all 128 bytes and round-trips");
    },
    Err(e) => { return assert(false, "built header failed to parse"); },
  }
}

fn t3() -> TestResult {
  let d = mk_hdr(8, 1, 0, 0, 3, 3, 4, 1);
  let pal = ok_bytes(pcx_header_palette(d));
  if (pal.len() != 48) { return assert(false, "header palette is 48 bytes"); }
  if (!byte_is(pal, 0, 7)) { return assert(false, "palette byte 0 is 7"); }
  if (!byte_is(pal, 1, 12)) { return assert(false, "palette byte 1 is 12"); }
  if (!byte_is(pal, 47, 242)) { return assert(false, "palette byte 47 is 242"); }
  if (ok_int(pcx_header_palette_entry(d, 0)) != 461841) {
    return assert(false, "entry 0 packs 7/12/17 as 0xRRGGBB");
  }
  if (ok_int(pcx_header_palette_entry(d, 15)) != 15265266) {
    return assert(false, "entry 15 packs 232/237/242 as 0xRRGGBB");
  }
  if (!int_err_is(pcx_header_palette_entry(d, -1), "pcx: palette index out of range")) {
    return assert(false, "index -1 is Err");
  }
  if (!int_err_is(pcx_header_palette_entry(d, 16), "pcx: palette index out of range")) {
    return assert(false, "index 16 is Err");
  }
  return assert(true, "header palette bytes and packed entries round-trip");
}

fn t4() -> TestResult {
  let d = mk_hdr(8, 1, 0, 0, 3, 3, 4, 1);
  var body = Vec[UInt8].new();
  append_rle(&mut body, 4);
  append_vga(&mut body);
  let f = concat_bytes(d, body);
  if (f.len() != 901) { return assert(false, "file with trailer is 901 bytes"); }
  if (!pcx_has_vga_palette(f)) { return assert(false, "trailer is detected"); }
  let info = ok_info(pcx_parse(f));
  if (!info.has_vga_palette) { return assert(false, "parse reports the trailer"); }
  if (info.trailer_offset != 132) { return assert(false, "trailer offset is n - 769"); }
  if (info.pixel_offset != 128) { return assert(false, "pixel offset is 128"); }
  if (info.pixel_bytes != 4) { return assert(false, "pixel bytes end at the trailer"); }
  let pix = ok_bytes(pcx_pixel_data(f));
  if (pix.len() != 4) { return assert(false, "pixel slice is 4 bytes"); }
  if (!byte_is(pix, 0, 1)) { return assert(false, "pixel byte 0 is 1"); }
  if (!byte_is(pix, 3, 4)) { return assert(false, "pixel byte 3 is 4"); }
  let vga = ok_bytes(pcx_vga_palette(f));
  if (vga.len() != 768) { return assert(false, "VGA palette is 768 bytes"); }
  if (!byte_is(vga, 0, 3)) { return assert(false, "VGA byte 0 is 3"); }
  if (!byte_is(vga, 767, 252)) { return assert(false, "VGA byte 767 is 252"); }
  if (ok_int(pcx_vga_palette_entry(f, 0)) != 199185) {
    return assert(false, "VGA entry 0 packs 3/10/17");
  }
  if (ok_int(pcx_vga_palette_entry(f, 255)) != 15660540) {
    return assert(false, "VGA entry 255 packs 238/245/252");
  }
  if (!int_err_is(pcx_vga_palette_entry(f, 256), "pcx: vga palette index out of range")) {
    return assert(false, "VGA index 256 is Err");
  }
  return assert(true, "VGA palette trailer is detected and extracted exactly");
}

fn t5() -> TestResult {
  let d = mk_hdr(4, 1, 0, 0, 1, 1, 2, 1);
  var body = Vec[UInt8].new();
  append_rle(&mut body, 5);
  let f = concat_bytes(d, body);
  if (f.len() != 133) { return assert(false, "file without trailer is 133 bytes"); }
  if (pcx_has_vga_palette(f)) { return assert(false, "no trailer is detected"); }
  let info = ok_info(pcx_parse(f));
  if (info.has_vga_palette) { return assert(false, "parse reports no trailer"); }
  if (info.trailer_offset != 133) { return assert(false, "trailer offset is the file length"); }
  if (info.pixel_bytes != 5) { return assert(false, "pixel bytes run to the end"); }
  let pix = ok_bytes(pcx_pixel_data(f));
  if (pix.len() != 5) { return assert(false, "pixel slice is 5 bytes"); }
  if (!byte_is(pix, 0, 1)) { return assert(false, "pixel byte 0 is 1"); }
  if (!byte_is(pix, 4, 5)) { return assert(false, "pixel byte 4 is 5"); }
  if (!bytes_err_is(pcx_vga_palette(f), "pcx: missing vga palette trailer")) {
    return assert(false, "missing trailer is Err");
  }
  if (!int_err_is(pcx_vga_palette_entry(f, 0), "pcx: missing vga palette trailer")) {
    return assert(false, "VGA entry without a trailer is Err");
  }
  return assert(true, "without a trailer the span runs to the end of the file");
}

fn t6() -> TestResult {
  let d = mk_hdr(8, 1, 0, 0, 1, 0, 2, 1);
  var body = Vec[UInt8].new();
  append_rle(&mut body, 2);
  append_vga(&mut body);
  let f = concat_bytes(d, body);
  if (f.len() != 899) { return assert(false, "corruption fixture is 899 bytes"); }
  f[130] = 13 as UInt8;
  if (pcx_has_vga_palette(f)) { return assert(false, "corrupt marker is not a trailer"); }
  let info = ok_info(pcx_parse(f));
  if (info.has_vga_palette) { return assert(false, "parse reports no trailer"); }
  if (info.pixel_bytes != 771) { return assert(false, "span extends over the corrupt trailer"); }
  let pix = ok_bytes(pcx_pixel_data(f));
  if (pix.len() != 771) { return assert(false, "pixel slice is 771 bytes"); }
  if (!byte_is(pix, 2, 13)) { return assert(false, "corrupted marker sits inside the span"); }
  let h128 = mk_hdr(8, 1, 0, 0, 0, 0, 2, 1);
  var tiny = Vec[UInt8].new();
  append_vga(&mut tiny);
  let t = concat_bytes(h128, tiny);
  if (t.len() != 897) { return assert(false, "boundary fixture is 897 bytes"); }
  if (!pcx_has_vga_palette(t)) { return assert(false, "897-byte file carries a trailer"); }
  if (!info_err_is(pcx_parse(t), "pcx: truncated pixel data")) {
    return assert(false, "zero-byte pixel span is rejected");
  }
  let h127 = Vec[UInt8].new();
  var z = 0;
  while (z < 127) {
    h127.push(0 as UInt8);
    z = z + 1;
  }
  h127.push(12 as UInt8);
  let rest = Vec[UInt8].new();
  var j = 0;
  while (j < 768) {
    rest.push(0 as UInt8);
    j = j + 1;
  }
  let s896 = concat_bytes(h127, rest);
  if (s896.len() != 896) { return assert(false, "sub-boundary fixture is 896 bytes"); }
  if (pcx_has_vga_palette(s896)) { return assert(false, "marker at byte 127 is not a trailer"); }
  return assert(true, "trailer detection is marker-exact at the file end");
}

fn t7() -> TestResult {
  let empty = Vec[UInt8].new();
  if (!hdr_err_is(pcx_parse_header(empty), "pcx: truncated header")) {
    return assert(false, "empty buffer is Err");
  }
  if (!info_err_is(pcx_parse(empty), "pcx: truncated header")) {
    return assert(false, "full parse forwards truncation");
  }
  let short = Vec[UInt8].new();
  var i = 0;
  while (i < 127) {
    short.push(0 as UInt8);
    i = i + 1;
  }
  if (!hdr_err_is(pcx_parse_header(short), "pcx: truncated header")) {
    return assert(false, "127-byte buffer is Err");
  }
  let only_hdr = mk_hdr(8, 1, 0, 0, 0, 0, 2, 1);
  if (!info_err_is(pcx_parse(only_hdr), "pcx: truncated pixel data")) {
    return assert(false, "header-only buffer has no pixel span");
  }
  return assert(true, "short buffers are rejected with exact messages");
}

fn t8() -> TestResult {
  let d = mk_hdr(8, 1, 0, 0, 1, 0, 2, 1);
  d[0] = 11 as UInt8;
  if (!hdr_err_is(pcx_parse_header(d), "pcx: bad manufacturer")) {
    return assert(false, "manufacturer 11 is Err");
  }
  d[0] = 0 as UInt8;
  if (!hdr_err_is(pcx_parse_header(d), "pcx: bad manufacturer")) {
    return assert(false, "manufacturer 0 is Err");
  }
  d[0] = 255 as UInt8;
  if (!hdr_err_is(pcx_parse_header(d), "pcx: bad manufacturer")) {
    return assert(false, "manufacturer 255 is Err");
  }
  d[0] = 10 as UInt8;
  if (bad_hdr(pcx_parse_header(d))) { return assert(false, "manufacturer 10 is Ok"); }
  return assert(true, "manufacturer must be exactly 10");
}

fn t9() -> TestResult {
  let d = mk_hdr(8, 1, 0, 0, 1, 0, 2, 1);
  d[2] = 0 as UInt8;
  if (!hdr_err_is(pcx_parse_header(d), "pcx: unsupported encoding")) {
    return assert(false, "unencoded encoding 0 is Err");
  }
  d[2] = 2 as UInt8;
  if (!hdr_err_is(pcx_parse_header(d), "pcx: unsupported encoding")) {
    return assert(false, "encoding 2 is Err");
  }
  d[2] = 255 as UInt8;
  if (!hdr_err_is(pcx_parse_header(d), "pcx: unsupported encoding")) {
    return assert(false, "encoding 255 is Err");
  }
  d[2] = 1 as UInt8;
  if (bad_hdr(pcx_parse_header(d))) { return assert(false, "encoding 1 is Ok"); }
  return assert(true, "only RLE encoding (1) is accepted");
}

fn t10() -> TestResult {
  let d = mk_hdr(8, 1, 0, 0, 1, 0, 2, 1);
  var v = 0;
  while (v <= 5) {
    d[1] = v as UInt8;
    if (bad_hdr(pcx_parse_header(d))) { return assert(false, "version 0..5 is Ok"); }
    v = v + 1;
  }
  d[1] = 6 as UInt8;
  if (!hdr_err_is(pcx_parse_header(d), "pcx: unsupported version")) {
    return assert(false, "version 6 is Err");
  }
  d[1] = 255 as UInt8;
  if (!hdr_err_is(pcx_parse_header(d), "pcx: unsupported version")) {
    return assert(false, "version 255 is Err");
  }
  return assert(true, "versions 0..5 are accepted, newer ones rejected");
}

fn t11() -> TestResult {
  let a = mk_hdr(8, 1, 5, 0, 4, 0, 2, 1);
  if (!hdr_err_is(pcx_parse_header(a), "pcx: invalid geometry")) {
    return assert(false, "xmax < xmin is Err");
  }
  let b = mk_hdr(8, 1, 0, 5, 0, 4, 2, 1);
  if (!hdr_err_is(pcx_parse_header(b), "pcx: invalid geometry")) {
    return assert(false, "ymax < ymin is Err");
  }
  let c = mk_hdr(8, 1, 65535, 0, 0, 0, 2, 1);
  if (!hdr_err_is(pcx_parse_header(c), "pcx: invalid geometry")) {
    return assert(false, "wrapped x range is Err");
  }
  let d = mk_hdr(8, 1, 10, 3, 19, 8, 10, 1);
  let h = ok_hdr(pcx_parse_header(d));
  if (h.width != 10) { return assert(false, "width is 10"); }
  if (h.height != 6) { return assert(false, "height is 6"); }
  let e = mk_hdr(8, 1, 65535, 65535, 65535, 65535, 2, 1);
  let h2 = ok_hdr(pcx_parse_header(e));
  if (h2.width != 1) { return assert(false, "max-coordinate 1x1 is Ok"); }
  if (h2.height != 1) { return assert(false, "max-coordinate height is 1"); }
  return assert(true, "geometry is inclusive and must be non-negative");
}

fn t12() -> TestResult {
  let a = mk_hdr(8, 1, 0, 0, 2, 0, 3, 1);
  if (!hdr_err_is(pcx_parse_header(a), "pcx: invalid bytes per line")) {
    return assert(false, "odd bytes per line is Err");
  }
  let b = mk_hdr(8, 1, 0, 0, 2, 0, 2, 1);
  if (!hdr_err_is(pcx_parse_header(b), "pcx: invalid bytes per line")) {
    return assert(false, "short bytes per line is Err");
  }
  let c = mk_hdr(8, 1, 0, 0, 2, 0, 4, 1);
  if (bad_hdr(pcx_parse_header(c))) { return assert(false, "padded bytes per line is Ok"); }
  let d = mk_hdr(8, 1, 0, 0, 2, 0, 8, 1);
  if (bad_hdr(pcx_parse_header(d))) { return assert(false, "extra padding is Ok"); }
  let e = mk_hdr(8, 1, 0, 0, 0, 0, 0, 1);
  if (!hdr_err_is(pcx_parse_header(e), "pcx: invalid bytes per line")) {
    return assert(false, "zero bytes per line is Err");
  }
  let f = mk_hdr(1, 1, 0, 0, 15, 0, 3, 1);
  if (!hdr_err_is(pcx_parse_header(f), "pcx: invalid bytes per line")) {
    return assert(false, "1bpp width 16 with a 3-byte line is Err");
  }
  let g = mk_hdr(1, 1, 0, 0, 15, 0, 2, 1);
  if (bad_hdr(pcx_parse_header(g))) { return assert(false, "1bpp width 16 with a 2-byte line is Ok"); }
  if (pcx_scanline_bytes(1, 1) != 1) { return assert(false, "scanline(1,1) is 1"); }
  if (pcx_scanline_bytes(8, 1) != 1) { return assert(false, "scanline(8,1) is 1"); }
  if (pcx_scanline_bytes(9, 1) != 2) { return assert(false, "scanline(9,1) is 2"); }
  if (pcx_scanline_bytes(16, 1) != 2) { return assert(false, "scanline(16,1) is 2"); }
  if (pcx_scanline_bytes(5, 4) != 3) { return assert(false, "scanline(5,4) is 3"); }
  if (pcx_scanline_bytes(320, 8) != 320) { return assert(false, "scanline(320,8) is 320"); }
  if (pcx_scanline_bytes(321, 8) != 321) { return assert(false, "scanline(321,8) is 321"); }
  if (pcx_scanline_bytes(0, 8) != 0) { return assert(false, "scanline width 0 is 0"); }
  if (pcx_scanline_bytes(8, 0) != 0) { return assert(false, "scanline bits 0 is 0"); }
  return assert(true, "bytes per line must be even and hold one scanline");
}

fn t13() -> TestResult {
  let d = mk_hdr(8, 1, 0, 0, 1, 0, 2, 1);
  d[3] = 3 as UInt8;
  if (!hdr_err_is(pcx_parse_header(d), "pcx: invalid bits per pixel")) {
    return assert(false, "3 bits is Err");
  }
  d[3] = 0 as UInt8;
  if (!hdr_err_is(pcx_parse_header(d), "pcx: invalid bits per pixel")) {
    return assert(false, "0 bits is Err");
  }
  d[3] = 16 as UInt8;
  if (!hdr_err_is(pcx_parse_header(d), "pcx: invalid bits per pixel")) {
    return assert(false, "16 bits is Err");
  }
  d[3] = 255 as UInt8;
  if (!hdr_err_is(pcx_parse_header(d), "pcx: invalid bits per pixel")) {
    return assert(false, "255 bits is Err");
  }
  let bits = Vec[Int].new();
  bits.push(1); bits.push(2); bits.push(4); bits.push(8);
  var i = 0;
  while (i < bits.len()) {
    let b: Int = bits[i];
    let ok = mk_hdr(b, 1, 0, 0, 1, 0, 2, 1);
    if (bad_hdr(pcx_parse_header(ok))) { return assert(false, "1/2/4/8 bits are Ok"); }
    i = i + 1;
  }
  return assert(true, "bits per pixel is one of 1, 2, 4 or 8");
}

fn t14() -> TestResult {
  let a = mk_hdr(8, 0, 0, 0, 1, 0, 2, 1);
  if (!hdr_err_is(pcx_parse_header(a), "pcx: invalid color planes")) {
    return assert(false, "0 planes is Err");
  }
  let b = mk_hdr(8, 5, 0, 0, 1, 0, 2, 1);
  if (!hdr_err_is(pcx_parse_header(b), "pcx: invalid color planes")) {
    return assert(false, "5 planes is Err");
  }
  let c = mk_hdr(8, 255, 0, 0, 1, 0, 2, 1);
  if (!hdr_err_is(pcx_parse_header(c), "pcx: invalid color planes")) {
    return assert(false, "255 planes is Err");
  }
  let d = mk_hdr(2, 2, 0, 0, 1, 0, 2, 1);
  if (!hdr_err_is(pcx_parse_header(d), "pcx: invalid plane configuration")) {
    return assert(false, "2bpp 2 planes is Err");
  }
  let e = mk_hdr(4, 2, 0, 0, 1, 0, 2, 1);
  if (!hdr_err_is(pcx_parse_header(e), "pcx: invalid plane configuration")) {
    return assert(false, "4bpp 2 planes is Err");
  }
  let f = mk_hdr(8, 2, 0, 0, 1, 0, 2, 1);
  if (!hdr_err_is(pcx_parse_header(f), "pcx: invalid plane configuration")) {
    return assert(false, "8bpp 2 planes is Err");
  }
  let g = mk_hdr(1, 4, 0, 0, 1, 0, 2, 1);
  if (bad_hdr(pcx_parse_header(g))) { return assert(false, "1bpp 4 planes is Ok"); }
  let h = mk_hdr(8, 3, 0, 0, 1, 0, 2, 1);
  if (bad_hdr(pcx_parse_header(h))) { return assert(false, "8bpp 3 planes is Ok"); }
  let i = mk_hdr(8, 4, 0, 0, 1, 0, 2, 1);
  if (bad_hdr(pcx_parse_header(i))) { return assert(false, "8bpp 4 planes is Ok"); }
  return assert(true, "plane count is 1..4 and matches the documented table");
}

fn t15() -> TestResult {
  let a = mk_hdr(8, 1, 0, 0, 1, 0, 2, 3);
  if (!hdr_err_is(pcx_parse_header(a), "pcx: invalid palette type")) {
    return assert(false, "palette type 3 is Err");
  }
  let b = mk_hdr(8, 1, 0, 0, 1, 0, 2, 255);
  if (!hdr_err_is(pcx_parse_header(b), "pcx: invalid palette type")) {
    return assert(false, "palette type 255 is Err");
  }
  let c = mk_hdr(8, 1, 0, 0, 1, 0, 2, 1000);
  if (!hdr_err_is(pcx_parse_header(c), "pcx: invalid palette type")) {
    return assert(false, "palette type 1000 is Err");
  }
  let d = mk_hdr(8, 1, 0, 0, 1, 0, 2, 2);
  if (bad_hdr(pcx_parse_header(d))) { return assert(false, "8bpp grayscale is Ok"); }
  let e = mk_hdr(1, 1, 0, 0, 1, 0, 2, 2);
  if (bad_hdr(pcx_parse_header(e))) { return assert(false, "1bpp grayscale is Ok"); }
  let f = mk_hdr(4, 1, 0, 0, 1, 0, 2, 2);
  if (!hdr_err_is(pcx_parse_header(f), "pcx: invalid plane configuration")) {
    return assert(false, "4bpp grayscale is Err");
  }
  let g = mk_hdr(8, 3, 0, 0, 1, 0, 2, 2);
  if (!hdr_err_is(pcx_parse_header(g), "pcx: invalid plane configuration")) {
    return assert(false, "3-plane grayscale is Err");
  }
  let h = mk_hdr(8, 1, 0, 0, 1, 0, 2, 0);
  if (bad_hdr(pcx_parse_header(h))) { return assert(false, "palette type 0 is Ok"); }
  let i = mk_hdr(8, 3, 0, 0, 1, 0, 2, 1);
  if (bad_hdr(pcx_parse_header(i))) { return assert(false, "true-color palette type 1 is Ok"); }
  return assert(true, "palette type 0/1/2 selects the documented configurations");
}

fn t16() -> TestResult {
  let d = mk_hdr(8, 1, 0, 0, 5, 3, 6, 1);
  var body = Vec[UInt8].new();
  append_rle(&mut body, 6);
  append_vga(&mut body);
  let f = concat_bytes(d, body);
  if (ok_int(pcx_pixel_offset(f)) != 128) { return assert(false, "pixel offset is 128"); }
  if (ok_int(pcx_pixel_length(f)) != 6) { return assert(false, "pixel length is 6"); }
  let pix = ok_bytes(pcx_pixel_data(f));
  if (pix.len() != 6) { return assert(false, "pixel slice is 6 bytes"); }
  if (!byte_is(pix, 0, 1)) { return assert(false, "pixel byte 0 is 1"); }
  if (!byte_is(pix, 5, 6)) { return assert(false, "pixel byte 5 is 6"); }
  let h = ok_hdr(pcx_parse_header(f));
  if (pcx_decoded_bytes(h) != 24) { return assert(false, "decoded bytes are 6*1*4"); }
  var body2 = Vec[UInt8].new();
  append_rle(&mut body2, 9);
  let g = concat_bytes(d, body2);
  if (ok_int(pcx_pixel_offset(g)) != 128) { return assert(false, "pixel offset is 128 without a trailer"); }
  if (ok_int(pcx_pixel_length(g)) != 9) { return assert(false, "pixel length is 9 without a trailer"); }
  if (!int_err_is(pcx_pixel_length(d), "pcx: truncated pixel data")) {
    return assert(false, "header-only buffer has no length");
  }
  return assert(true, "span accessors locate the opaque RLE region");
}

fn t17() -> TestResult {
  let pal = base_pal();
  var h1 = base_h();
  h1.version = 6;
  if (!bytes_err_is(pcx_build_header(h1, pal), "pcx: unsupported version")) {
    return assert(false, "builder version 6 is Err");
  }
  var h2 = base_h();
  h2.encoding = 0;
  if (!bytes_err_is(pcx_build_header(h2, pal), "pcx: unsupported encoding")) {
    return assert(false, "builder encoding 0 is Err");
  }
  var h3 = base_h();
  h3.xmin = -1;
  if (!bytes_err_is(pcx_build_header(h3, pal), "pcx: invalid geometry")) {
    return assert(false, "builder negative xmin is Err");
  }
  var h4 = base_h();
  h4.xmax = 65536;
  if (!bytes_err_is(pcx_build_header(h4, pal), "pcx: invalid geometry")) {
    return assert(false, "builder oversized xmax is Err");
  }
  var h5 = base_h();
  h5.xmin = 5; h5.xmax = 4;
  if (!bytes_err_is(pcx_build_header(h5, pal), "pcx: invalid geometry")) {
    return assert(false, "builder reversed geometry is Err");
  }
  var h6 = base_h();
  h6.bytes_per_line = 3;
  if (!bytes_err_is(pcx_build_header(h6, pal), "pcx: invalid bytes per line")) {
    return assert(false, "builder odd line is Err");
  }
  var h7 = base_h();
  h7.color_planes = 5;
  if (!bytes_err_is(pcx_build_header(h7, pal), "pcx: invalid color planes")) {
    return assert(false, "builder 5 planes is Err");
  }
  var h8 = base_h();
  h8.palette_type = 3;
  if (!bytes_err_is(pcx_build_header(h8, pal), "pcx: invalid palette type")) {
    return assert(false, "builder palette type 3 is Err");
  }
  var h9 = base_h();
  h9.hdpi = -1;
  if (!bytes_err_is(pcx_build_header(h9, pal), "pcx: invalid resolution")) {
    return assert(false, "builder negative hdpi is Err");
  }
  var h10 = base_h();
  h10.vscreen = 70000;
  if (!bytes_err_is(pcx_build_header(h10, pal), "pcx: invalid screen size")) {
    return assert(false, "builder oversized screen is Err");
  }
  let p47 = Vec[UInt8].new();
  var i = 0;
  while (i < 47) {
    p47.push(0 as UInt8);
    i = i + 1;
  }
  if (!bytes_err_is(pcx_build_header(base_h(), p47), "pcx: invalid palette size")) {
    return assert(false, "47-byte palette is Err");
  }
  let p49 = Vec[UInt8].new();
  i = 0;
  while (i < 49) {
    p49.push(0 as UInt8);
    i = i + 1;
  }
  if (!bytes_err_is(pcx_build_header(base_h(), p49), "pcx: invalid palette size")) {
    return assert(false, "49-byte palette is Err");
  }
  if (!bytes_err_is(pcx_build_header(base_h(), Vec[UInt8].new()), "pcx: invalid palette size")) {
    return assert(false, "empty palette is Err");
  }
  if (bad_bytes(pcx_build_header(base_h(), pal))) {
    return assert(false, "valid builder input is Ok");
  }
  return assert(true, "builder checks palette size and every field range");
}

fn t18() -> TestResult {
  var h = base_h();
  h.xmax = 319; h.ymax = 199;
  h.color_planes = 3; h.bytes_per_line = 320;
  h.width = 0; h.height = 0;
  let pal = base_pal();
  let hdr = ok_bytes(pcx_build_header(h, pal));
  if (hdr.len() != 128) { return assert(false, "rebuilt header is 128 bytes"); }
  var body = Vec[UInt8].new();
  append_rle(&mut body, 10);
  append_vga(&mut body);
  let with_vga = concat_bytes(hdr, body);
  if (with_vga.len() != 907) { return assert(false, "file with trailer is 907 bytes"); }
  if (!pcx_has_vga_palette(with_vga)) { return assert(false, "rebuilt file carries a trailer"); }
  let info = ok_info(pcx_parse(with_vga));
  if (!info.has_vga_palette) { return assert(false, "parse reports the trailer"); }
  if (info.trailer_offset != 138) { return assert(false, "trailer offset 138"); }
  if (info.pixel_offset != 128) { return assert(false, "pixel offset 128"); }
  if (info.pixel_bytes != 10) { return assert(false, "pixel bytes 10"); }
  if (info.header.width != 320) { return assert(false, "width round-trip"); }
  if (info.header.height != 200) { return assert(false, "height round-trip"); }
  if (info.header.color_planes != 3) { return assert(false, "planes round-trip"); }
  if (info.header.bytes_per_line != 320) { return assert(false, "bytes per line round-trip"); }
  if (info.header.hdpi != 72) { return assert(false, "hdpi round-trip"); }
  let hp = ok_bytes(pcx_header_palette(with_vga));
  var i = 0;
  while (i < 48) {
    let a: Int = (hp[i] as Int) & 0xFF;
    let b: Int = (pal[i] as Int) & 0xFF;
    if (a != b) { return assert(false, "header palette survives the round-trip"); }
    i = i + 1;
  }
  let pix = ok_bytes(pcx_pixel_data(with_vga));
  if (pix.len() != 10) { return assert(false, "pixel slice is 10 bytes"); }
  if (!byte_is(pix, 0, 1)) { return assert(false, "pixel byte 0 is 1"); }
  if (!byte_is(pix, 9, 10)) { return assert(false, "pixel byte 9 is 10"); }
  let vga = ok_bytes(pcx_vga_palette(with_vga));
  if (vga.len() != 768) { return assert(false, "VGA palette is 768 bytes"); }
  if (!byte_is(vga, 767, 252)) { return assert(false, "VGA last byte is 252"); }
  var body2 = Vec[UInt8].new();
  append_rle(&mut body2, 10);
  let no_vga = concat_bytes(hdr, body2);
  if (no_vga.len() != 138) { return assert(false, "file without trailer is 138 bytes"); }
  if (pcx_has_vga_palette(no_vga)) { return assert(false, "no trailer is detected"); }
  let info2 = ok_info(pcx_parse(no_vga));
  if (info2.has_vga_palette) { return assert(false, "parse reports no trailer"); }
  if (info2.trailer_offset != 138) { return assert(false, "trailer offset is the file length"); }
  if (info2.pixel_bytes != 10) { return assert(false, "pixel bytes 10 without a trailer"); }
  if (ok_int(pcx_pixel_length(no_vga)) != 10) { return assert(false, "pixel length 10"); }
  return assert(true, "built files round-trip with and without the VGA trailer");
}

fn main() -> Int {
  io.println("=== xiom.pcx conformance tests ===");
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
    io.println("xiom.pcx: all tests passed");
  } else {
    io.println("xiom.pcx: tests failed");
  }
  return failed;
}
