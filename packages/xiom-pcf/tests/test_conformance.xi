// XIOM -- xiom.pcf conformance tests (20 checks)
// Port task: prove the pure-XIOM xiom.pcf X11 PCF codec subset against the
// documented file header, table directory, metrics formats, bitmaps layout,
// encodings layout and error catalog.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Coverage: a canonical nine-table fixture (hand-built, layout-pinned) with
// accessors for every documented table type; all three metrics word orders
// (0 big-endian, 1 little-endian, 2 byte-mixed) with pinned raw bytes; the
// bitmap span/offset accessors and byte copier; the encodings run/pool
// accessors and the documented first-match glyph lookup; raw-span
// preservation of every optional table and a byte-exact parse -> raw-span ->
// reassemble round trip; header-only/truncated-directory inputs; magic
// errors; missing metrics/bitmaps; compressed and unsupported metrics
// formats; metrics/bitmaps/encodings size and bounds errors; directory
// bounds errors; an empty two-table font; unknown and duplicate table types;
// and cross-format metric agreement.
//
// Str values are never compared with `==`; error messages and names go
// through compare.str_compare.

module pcf_tests
use xiom.io; use xiom.test;
use xiom.pcf;
use xiom.string.compare;
use xiom.encoding.hex;

// --------------------------------------------------
//  Test helpers
// --------------------------------------------------

// Expected bytes for a hex string ("" on malformed input; the test then
// fails on the byte comparison).
fn hb(hexstr: Str) -> Vec[UInt8] {
  let r = hex.hex_decode(hexstr);
  if r.is_ok {
    let v: Vec[UInt8] = r.value;
    return v;
  }
  return Vec[UInt8].new();
}

fn bytes_equal(a: Vec[UInt8], b: Vec[UInt8]) -> Bool {
  if a.len() != b.len() {
    return false;
  }
  var i = 0;
  while i < a.len() {
    let x: Int = (a[i] as Int) & 0xFF;
    let y: Int = (b[i] as Int) & 0xFF;
    if x != y {
      return false;
    }
    i = i + 1;
  }
  return true;
}

fn ints_equal(a: Vec[Int], b: Vec[Int]) -> Bool {
  if a.len() != b.len() {
    return false;
  }
  var i = 0;
  while i < a.len() {
    let x: Int = a[i];
    let y: Int = b[i];
    if x != y {
      return false;
    }
    i = i + 1;
  }
  return true;
}

fn str_eq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn err_font_is(r: Result[PcfFont, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  let e: Str = r.error;
  return str_eq(e, want);
}

fn err_bytes_is(r: Result[Vec[UInt8], Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  let e: Str = r.error;
  return str_eq(e, want);
}

fn err_ints_is(r: Result[Vec[Int], Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  let e: Str = r.error;
  return str_eq(e, want);
}

// Value of a successful byte Result, or an empty vector (callers only use it
// after checking is_ok).
fn ok_bytes(r: Result[Vec[UInt8], Str]) -> Vec[UInt8] {
  if r.is_ok {
    let v: Vec[UInt8] = r.value;
    return v;
  }
  return Vec[UInt8].new();
}

// Value of a successful Int-vector Result, or an empty vector.
fn ok_ints(r: Result[Vec[Int], Str]) -> Vec[Int] {
  if r.is_ok {
    let v: Vec[Int] = r.value;
    return v;
  }
  return Vec[Int].new();
}

// Prefix of a byte vector, used to build short source buffers.
fn prefix(v: Vec[UInt8], n: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < n && i < v.len() {
    out.push(v[i]);
    i = i + 1;
  }
  return out;
}

// Byte slice of a vector; the caller pins in-bounds offsets.
fn slice(v: Vec[UInt8], off: Int, len: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < len && off + i < v.len() {
    out.push(v[off + i]);
    i = i + 1;
  }
  return out;
}

// --------------------------------------------------
//  Byte writers and patchers (little-endian unless noted)
// --------------------------------------------------

fn put_u16le(out: &mut Vec[UInt8], v: Int) {
  out.push((v % 256) as UInt8);
  out.push(((v / 256) % 256) as UInt8);
}

fn put_u16be(out: &mut Vec[UInt8], v: Int) {
  out.push(((v / 256) % 256) as UInt8);
  out.push((v % 256) as UInt8);
}

fn put_u32le(out: &mut Vec[UInt8], v: Int) {
  out.push((v % 256) as UInt8);
  out.push(((v / 256) % 256) as UInt8);
  out.push(((v / 65536) % 256) as UInt8);
  out.push(((v / 16777216) % 256) as UInt8);
}

fn put_u32be(out: &mut Vec[UInt8], v: Int) {
  out.push(((v / 16777216) % 256) as UInt8);
  out.push(((v / 65536) % 256) as UInt8);
  out.push(((v / 256) % 256) as UInt8);
  out.push((v % 256) as UInt8);
}

fn put_bytes(out: &mut Vec[UInt8], src: &Vec[UInt8]) {
  var i = 0;
  while i < src.len() {
    out.push(src[i]);
    i = i + 1;
  }
}

fn patch_byte(buf: &mut Vec[UInt8], off: Int, v: Int) {
  buf[off] = (v % 256) as UInt8;
}

fn patch_u16le(buf: &mut Vec[UInt8], off: Int, v: Int) {
  buf[off] = (v % 256) as UInt8;
  buf[off + 1] = ((v / 256) % 256) as UInt8;
}

fn patch_u32le(buf: &mut Vec[UInt8], off: Int, v: Int) {
  buf[off] = (v % 256) as UInt8;
  buf[off + 1] = ((v / 256) % 256) as UInt8;
  buf[off + 2] = ((v / 65536) % 256) as UInt8;
  buf[off + 3] = ((v / 16777216) % 256) as UInt8;
}

// --------------------------------------------------
//  Unsigned readers (for pinning fixture bytes independently of the parser)
// --------------------------------------------------

fn rd8(v: &Vec[UInt8], off: Int) -> Int {
  return (v[off] as Int) & 0xFF;
}

fn rd16be(v: &Vec[UInt8], off: Int) -> Int {
  return rd8(v, off) * 256 + rd8(v, off + 1);
}

fn rd32be(v: &Vec[UInt8], off: Int) -> Int {
  return rd8(v, off) * 16777216 + rd8(v, off + 1) * 65536 + rd8(v, off + 2) * 256 + rd8(v, off + 3);
}

fn rd32le(v: &Vec[UInt8], off: Int) -> Int {
  return rd8(v, off) + rd8(v, off + 1) * 256 + rd8(v, off + 2) * 65536 + rd8(v, off + 3) * 16777216;
}

// --------------------------------------------------
//  Canonical fixture builders
// --------------------------------------------------

// Append one metric word in the requested order (`msb` true = big-endian).
fn put_mword(out: &mut Vec[UInt8], v: Int, msb: Bool) {
  if msb {
    put_u16be(out, v);
  } else {
    put_u16le(out, v);
  }
}

// Metrics table for the two-glyph fixture. Glyph 0: lsb -1, rsb 2, advance 5,
// ascent 8, descent -2, attributes 1; glyph 1: lsb -3, rsb 6, advance 7,
// ascent 9, descent -4, attributes 0xABCD. Format 0 = count and words
// big-endian; format 1 = count and words little-endian; format 2 =
// byte-mixed (count little-endian, words big-endian).
fn metrics_table(fmt: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  if fmt == 0 {
    put_u32be(&mut out, 2);
  } else {
    put_u32le(&mut out, 2);
  }
  let msb: Bool = fmt != 1;
  put_mword(&mut out, 65535, msb);
  put_mword(&mut out, 2, msb);
  put_mword(&mut out, 5, msb);
  put_mword(&mut out, 8, msb);
  put_mword(&mut out, 65534, msb);
  put_mword(&mut out, 1, msb);
  put_mword(&mut out, 65533, msb);
  put_mword(&mut out, 6, msb);
  put_mword(&mut out, 7, msb);
  put_mword(&mut out, 9, msb);
  put_mword(&mut out, 65532, msb);
  put_mword(&mut out, 43981, msb);
  return out;
}

// Bitmaps table for the two-glyph fixture: count 2, per glyph a metrics
// offset and a bitmap offset, then the two padded sizes (4 and 8), then the
// bitmap bytes. Data area starts at 4 + 12*2 = 28, so glyph 0's bitmap is
// at table offset 28 and glyph 1's at 32; the table is 40 bytes.
fn bitmaps_table() -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  put_u32le(&mut out, 2);
  put_u32le(&mut out, 4);
  put_u32le(&mut out, 28);
  put_u32le(&mut out, 16);
  put_u32le(&mut out, 32);
  put_u32le(&mut out, 4);
  put_u32le(&mut out, 8);
  let pixels = hb("aabbccdd0123456789abcdef");
  put_bytes(&mut out, &pixels);
  return out;
}

// Encodings table for the two-glyph fixture: minimum 65, maximum 67, glyph 0
// maps 65 and 66, glyph 1 maps 67. Per-glyph arrays are u16 (starts, then
// counts); the pool follows.
fn encodings_table() -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  put_u16le(&mut out, 65);
  put_u16le(&mut out, 67);
  put_u16le(&mut out, 0);
  put_u16le(&mut out, 2);
  put_u16le(&mut out, 2);
  put_u16le(&mut out, 1);
  put_u16le(&mut out, 65);
  put_u16le(&mut out, 66);
  put_u16le(&mut out, 67);
  return out;
}

// Raw payloads for the optional raw-span tables, plus an unknown type.
fn raw_table_bytes(ttype: Int) -> Vec[UInt8] {
  if ttype == 1 {
    return hb("0102030405060708");
  }
  if ttype == 8 {
    return hb("aabb");
  }
  if ttype == 256 {
    return hb("01000200");
  }
  if ttype == 512 {
    return hb("414243");
  }
  if ttype == 1024 {
    return hb("010203040506");
  }
  if ttype == 2048 {
    return hb("0badc0de0badc0");
  }
  if ttype == 1048576 {
    return hb("deadbeef");
  }
  return Vec[UInt8].new();
}

// Format field used when building a table: the metrics table carries the
// caller's format, properties carries a non-zero raw format (7) and the
// unknown table carries 3; every other table carries 0.
fn tfmt_for(ttype: Int, fmt: Int) -> Int {
  if ttype == 2 {
    return fmt;
  }
  if ttype == 1 {
    return 7;
  }
  if ttype == 1048576 {
    return 3;
  }
  return 0;
}

fn table_for(ttype: Int, fmt: Int) -> Vec[UInt8] {
  if ttype == 2 {
    return metrics_table(fmt);
  }
  if ttype == 4 {
    return bitmaps_table();
  }
  if ttype == 16 {
    return encodings_table();
  }
  return raw_table_bytes(ttype);
}

// Build a fixture whose directory lists exactly `types`, with the table
// payloads laid out in directory order (directory occupies 8 + 16*n bytes).
fn fixture_with_types(fmt: Int, types: Vec[Int]) -> Vec[UInt8] {
  let n = types.len();
  var out = Vec[UInt8].new();
  out.push(1 as UInt8);
  out.push(102 as UInt8);
  out.push(99 as UInt8);
  out.push(112 as UInt8);
  put_u32le(&mut out, n);
  var off = 8 + 16 * n;
  var i = 0;
  while i < n {
    let t: Int = types[i];
    let tb: Vec[UInt8] = table_for(t, fmt);
    put_u32le(&mut out, t);
    put_u32le(&mut out, tfmt_for(t, fmt));
    put_u32le(&mut out, tb.len());
    put_u32le(&mut out, off);
    off = off + tb.len();
    i = i + 1;
  }
  i = 0;
  while i < n {
    let t2: Int = types[i];
    let tb2: Vec[UInt8] = table_for(t2, fmt);
    put_bytes(&mut out, &tb2);
    i = i + 1;
  }
  return out;
}

fn all_types() -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(2);
  v.push(4);
  v.push(16);
  v.push(1);
  v.push(8);
  v.push(256);
  v.push(512);
  v.push(1024);
  v.push(2048);
  return v;
}

fn types_without(drop_type: Int) -> Vec[Int] {
  let all = all_types();
  var v = Vec[Int].new();
  var i = 0;
  while i < all.len() {
    let t: Int = all[i];
    if t != drop_type {
      v.push(t);
    }
    i = i + 1;
  }
  return v;
}

fn fixture(fmt: Int) -> Vec[UInt8] {
  return fixture_with_types(fmt, all_types());
}

// Eight-byte header with zero tables.
fn header_only() -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  out.push(1 as UInt8);
  out.push(102 as UInt8);
  out.push(99 as UInt8);
  out.push(112 as UInt8);
  put_u32le(&mut out, 0);
  return out;
}

// Two-table empty font: metrics count 0 and bitmaps count 0 (both tables are
// four bytes). The bitmap data area is empty.
fn empty_font() -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  out.push(1 as UInt8);
  out.push(102 as UInt8);
  out.push(99 as UInt8);
  out.push(112 as UInt8);
  put_u32le(&mut out, 2);
  put_u32le(&mut out, 2);
  put_u32le(&mut out, 1);
  put_u32le(&mut out, 4);
  put_u32le(&mut out, 40);
  put_u32le(&mut out, 4);
  put_u32le(&mut out, 0);
  put_u32le(&mut out, 4);
  put_u32le(&mut out, 44);
  put_u32le(&mut out, 0);
  put_u32le(&mut out, 0);
  return out;
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  let data = fixture(1);
  var ok = data.len() == 268;
  let r = pcf_parse(&data);
  if !r.is_ok {
    return assert(false, "canonical fixture must parse");
  }
  let p: PcfFont = r.value;
  if pcf_table_count(&p) != 9 { ok = false; }
  let types = pcf_table_type(&p, 0);
  if types != 2 { ok = false; }
  if pcf_table_type(&p, 1) != 4 { ok = false; }
  if pcf_table_type(&p, 2) != 16 { ok = false; }
  if pcf_table_type(&p, 3) != 1 { ok = false; }
  if pcf_table_type(&p, 4) != 8 { ok = false; }
  if pcf_table_type(&p, 5) != 256 { ok = false; }
  if pcf_table_type(&p, 6) != 512 { ok = false; }
  if pcf_table_type(&p, 7) != 1024 { ok = false; }
  if pcf_table_type(&p, 8) != 2048 { ok = false; }
  if pcf_table_format(&p, 0) != 1 { ok = false; }
  if pcf_table_format(&p, 3) != 7 { ok = false; }
  if pcf_table_format(&p, 1) != 0 { ok = false; }
  if pcf_table_offset(&p, 0) != 152 { ok = false; }
  if pcf_table_offset(&p, 1) != 180 { ok = false; }
  if pcf_table_offset(&p, 2) != 220 { ok = false; }
  if pcf_table_offset(&p, 3) != 238 { ok = false; }
  if pcf_table_offset(&p, 4) != 246 { ok = false; }
  if pcf_table_offset(&p, 5) != 248 { ok = false; }
  if pcf_table_offset(&p, 6) != 252 { ok = false; }
  if pcf_table_offset(&p, 7) != 255 { ok = false; }
  if pcf_table_offset(&p, 8) != 261 { ok = false; }
  if pcf_table_size(&p, 0) != 28 { ok = false; }
  if pcf_table_size(&p, 1) != 40 { ok = false; }
  if pcf_table_size(&p, 2) != 18 { ok = false; }
  if pcf_table_size(&p, 3) != 8 { ok = false; }
  if pcf_table_size(&p, 4) != 2 { ok = false; }
  if pcf_table_size(&p, 5) != 4 { ok = false; }
  if pcf_table_size(&p, 6) != 3 { ok = false; }
  if pcf_table_size(&p, 7) != 6 { ok = false; }
  if pcf_table_size(&p, 8) != 7 { ok = false; }
  if pcf_table_find(&p, 2) != 0 { ok = false; }
  if pcf_table_find(&p, 16) != 2 { ok = false; }
  if pcf_table_find(&p, 2048) != 8 { ok = false; }
  if pcf_table_find(&p, 32) != -1 { ok = false; }
  if pcf_table_find(&p, 0) != -1 { ok = false; }
  if !pcf_has_table(&p, 4) { ok = false; }
  if pcf_has_table(&p, 32) { ok = false; }
  if pcf_table_type(&p, 9) != -1 { ok = false; }
  if pcf_table_type(&p, -1) != -1 { ok = false; }
  if pcf_table_format(&p, 100) != -1 { ok = false; }
  if pcf_table_offset(&p, -2) != -1 { ok = false; }
  if pcf_table_size(&p, 9) != -1 { ok = false; }
  if pcf_glyph_count(&p) != 2 { ok = false; }
  return assert(ok, "canonical nine-table fixture: directory pinned");
}

fn t2() -> TestResult {
  let data = fixture(1);
  let r = pcf_parse(&data);
  if !r.is_ok {
    return assert(false, "canonical fixture must parse");
  }
  let p: PcfFont = r.value;
  var ok = pcf_metrics_format(&p) == 1;
  if pcf_metric_lsb(&p, 0) != -1 { ok = false; }
  if pcf_metric_rsb(&p, 0) != 2 { ok = false; }
  if pcf_metric_advance(&p, 0) != 5 { ok = false; }
  if pcf_metric_ascent(&p, 0) != 8 { ok = false; }
  if pcf_metric_descent(&p, 0) != -2 { ok = false; }
  if pcf_metric_attributes(&p, 0) != 1 { ok = false; }
  if pcf_metric_lsb(&p, 1) != -3 { ok = false; }
  if pcf_metric_rsb(&p, 1) != 6 { ok = false; }
  if pcf_metric_advance(&p, 1) != 7 { ok = false; }
  if pcf_metric_ascent(&p, 1) != 9 { ok = false; }
  if pcf_metric_descent(&p, 1) != -4 { ok = false; }
  if pcf_metric_attributes(&p, 1) != 43981 { ok = false; }
  if pcf_metric_lsb(&p, 2) != 0 { ok = false; }
  if pcf_metric_lsb(&p, -1) != 0 { ok = false; }
  if pcf_metric_attributes(&p, 5) != 0 { ok = false; }
  var want = Vec[Int].new();
  want.push(-1);
  want.push(2);
  want.push(5);
  want.push(8);
  want.push(-2);
  want.push(1);
  let got = ok_ints(pcf_metrics_at(&p, 0));
  if !ints_equal(got, want) { ok = false; }
  if !err_ints_is(pcf_metrics_at(&p, 2), "pcf: index out of range") { ok = false; }
  if !err_ints_is(pcf_metrics_at(&p, -1), "pcf: index out of range") { ok = false; }
  return assert(ok, "little-endian metrics: all six fields per glyph");
}

fn t3() -> TestResult {
  let data = fixture(0);
  var ok = data.len() == 268;
  let r = pcf_parse(&data);
  if !r.is_ok {
    return assert(false, "big-endian metrics fixture must parse");
  }
  let p: PcfFont = r.value;
  if pcf_metrics_format(&p) != 0 { ok = false; }
  if pcf_metric_lsb(&p, 0) != -1 { ok = false; }
  if pcf_metric_descent(&p, 0) != -2 { ok = false; }
  if pcf_metric_attributes(&p, 0) != 1 { ok = false; }
  if pcf_metric_lsb(&p, 1) != -3 { ok = false; }
  if pcf_metric_advance(&p, 1) != 7 { ok = false; }
  if pcf_metric_attributes(&p, 1) != 43981 { ok = false; }
  let raw = ok_bytes(pcf_table_raw(&data, &p, 2));
  if !bytes_equal(raw, hb("00000002ffff000200050008fffe0001fffd000600070009fffcabcd")) { ok = false; }
  if rd32be(&data, 152) != 2 { ok = false; }
  if rd16be(&data, 156) != 65535 { ok = false; }
  if rd16be(&data, 178) != 43981 { ok = false; }
  return assert(ok, "metrics format 0: count and words big-endian, bytes pinned");
}

fn t4() -> TestResult {
  let data = fixture(2);
  var ok = data.len() == 268;
  let r = pcf_parse(&data);
  if !r.is_ok {
    return assert(false, "byte-mixed metrics fixture must parse");
  }
  let p: PcfFont = r.value;
  if pcf_metrics_format(&p) != 2 { ok = false; }
  if pcf_metric_lsb(&p, 0) != -1 { ok = false; }
  if pcf_metric_rsb(&p, 1) != 6 { ok = false; }
  if pcf_metric_ascent(&p, 1) != 9 { ok = false; }
  if pcf_metric_attributes(&p, 0) != 1 { ok = false; }
  if pcf_metric_attributes(&p, 1) != 43981 { ok = false; }
  let raw = ok_bytes(pcf_table_raw(&data, &p, 2));
  if !bytes_equal(raw, hb("02000000ffff000200050008fffe0001fffd000600070009fffcabcd")) { ok = false; }
  if rd32le(&data, 152) != 2 { ok = false; }
  if rd16be(&data, 156) != 65535 { ok = false; }
  return assert(ok, "metrics format 2: byte-mixed count/words, bytes pinned");
}

fn t5() -> TestResult {
  let data = fixture(1);
  let r = pcf_parse(&data);
  if !r.is_ok {
    return assert(false, "canonical fixture must parse");
  }
  let p: PcfFont = r.value;
  var ok = pcf_bitmap_span(&p, 0) == 4;
  if pcf_bitmap_span(&p, 1) != 8 { ok = false; }
  if pcf_bitmap_span(&p, 2) != -1 { ok = false; }
  if pcf_bitmap_span(&p, -1) != -1 { ok = false; }
  if pcf_bitmap_raw_offset(&p, 0) != 28 { ok = false; }
  if pcf_bitmap_raw_offset(&p, 1) != 32 { ok = false; }
  if pcf_bitmap_raw_offset(&p, 9) != -1 { ok = false; }
  if pcf_glyph_metrics_offset(&p, 0) != 4 { ok = false; }
  if pcf_glyph_metrics_offset(&p, 1) != 16 { ok = false; }
  if pcf_glyph_metrics_offset(&p, 2) != -1 { ok = false; }
  if pcf_bitmap_size(&p) != 12 { ok = false; }
  if !bytes_equal(ok_bytes(pcf_bitmap_bytes(&data, &p, 0)), hb("aabbccdd")) { ok = false; }
  if !bytes_equal(ok_bytes(pcf_bitmap_bytes(&data, &p, 1)), hb("0123456789abcdef")) { ok = false; }
  if !err_bytes_is(pcf_bitmap_bytes(&data, &p, 2), "pcf: index out of range") { ok = false; }
  if !err_bytes_is(pcf_bitmap_bytes(&data, &p, -1), "pcf: index out of range") { ok = false; }
  let cut = prefix(data, 190);
  if !err_bytes_is(pcf_bitmap_bytes(&cut, &p, 0), "pcf: bitmap bytes out of bounds") { ok = false; }
  return assert(ok, "bitmap spans, offsets, total size and byte copier");
}

fn t6() -> TestResult {
  let data = fixture(1);
  let r = pcf_parse(&data);
  if !r.is_ok {
    return assert(false, "canonical fixture must parse");
  }
  let p: PcfFont = r.value;
  var ok = pcf_has_encodings(&p);
  if pcf_encoding_min(&p) != 65 { ok = false; }
  if pcf_encoding_max(&p) != 67 { ok = false; }
  if pcf_encoding_count(&p, 0) != 2 { ok = false; }
  if pcf_encoding_count(&p, 1) != 1 { ok = false; }
  if pcf_encoding_count(&p, 2) != -1 { ok = false; }
  if pcf_encoding_count(&p, -1) != -1 { ok = false; }
  if pcf_encoding_at(&p, 0, 0) != 65 { ok = false; }
  if pcf_encoding_at(&p, 0, 1) != 66 { ok = false; }
  if pcf_encoding_at(&p, 1, 0) != 67 { ok = false; }
  if pcf_encoding_at(&p, 1, 1) != -1 { ok = false; }
  if pcf_encoding_at(&p, 0, -1) != -1 { ok = false; }
  if pcf_encoding_at(&p, 2, 0) != -1 { ok = false; }
  let e0 = ok_ints(pcf_encodings_at(&p, 0));
  var want = Vec[Int].new();
  want.push(65);
  want.push(66);
  if !ints_equal(e0, want) { ok = false; }
  if !err_ints_is(pcf_encodings_at(&p, 2), "pcf: index out of range") { ok = false; }
  if pcf_glyph_for_encoding(&p, 65) != 0 { ok = false; }
  if pcf_glyph_for_encoding(&p, 66) != 0 { ok = false; }
  if pcf_glyph_for_encoding(&p, 67) != 1 { ok = false; }
  if pcf_glyph_for_encoding(&p, 64) != -1 { ok = false; }
  if pcf_glyph_for_encoding(&p, 68) != -1 { ok = false; }
  if pcf_glyph_for_encoding(&p, 65535) != -1 { ok = false; }
  if pcf_glyph_for_encoding(&p, -1) != -1 { ok = false; }
  return assert(ok, "encodings runs, pool and first-match glyph lookup");
}

fn t7() -> TestResult {
  let data = fixture(1);
  let r = pcf_parse(&data);
  if !r.is_ok {
    return assert(false, "canonical fixture must parse");
  }
  let p: PcfFont = r.value;
  var ok = bytes_equal(ok_bytes(pcf_table_raw(&data, &p, 1)), hb("0102030405060708"));
  if !bytes_equal(ok_bytes(pcf_table_raw(&data, &p, 8)), hb("aabb")) { ok = false; }
  if !bytes_equal(ok_bytes(pcf_table_raw(&data, &p, 256)), hb("01000200")) { ok = false; }
  if !bytes_equal(ok_bytes(pcf_table_raw(&data, &p, 512)), hb("414243")) { ok = false; }
  if !bytes_equal(ok_bytes(pcf_table_raw(&data, &p, 1024)), hb("010203040506")) { ok = false; }
  if !bytes_equal(ok_bytes(pcf_table_raw(&data, &p, 2048)), hb("0badc0de0badc0")) { ok = false; }
  if !bytes_equal(ok_bytes(pcf_table_raw(&data, &p, 16)), encodings_table()) { ok = false; }
  if !bytes_equal(ok_bytes(pcf_table_raw(&data, &p, 2)), metrics_table(1)) { ok = false; }
  if !bytes_equal(ok_bytes(pcf_table_raw(&data, &p, 4)), bitmaps_table()) { ok = false; }
  if !err_bytes_is(pcf_table_raw(&data, &p, 32), "pcf: no such table") { ok = false; }
  if !err_bytes_is(pcf_table_raw(&data, &p, 0), "pcf: no such table") { ok = false; }
  let cut = prefix(data, 100);
  if !err_bytes_is(pcf_table_raw(&cut, &p, 512), "pcf: table out of bounds") { ok = false; }
  return assert(ok, "optional tables are preserved as exact raw spans");
}

fn t8() -> TestResult {
  let data = fixture(1);
  let r = pcf_parse(&data);
  if !r.is_ok {
    return assert(false, "canonical fixture must parse");
  }
  let p: PcfFont = r.value;
  var rebuilt = Vec[UInt8].new();
  rebuilt.push(1 as UInt8);
  rebuilt.push(102 as UInt8);
  rebuilt.push(99 as UInt8);
  rebuilt.push(112 as UInt8);
  put_u32le(&mut rebuilt, pcf_table_count(&p));
  var off2 = 8 + 16 * pcf_table_count(&p);
  var i = 0;
  while i < pcf_table_count(&p) {
    let t: Int = pcf_table_type(&p, i);
    let f: Int = pcf_table_format(&p, i);
    let off: Int = pcf_table_offset(&p, i);
    let size: Int = pcf_table_size(&p, i);
    let want_slice: Vec[UInt8] = slice(data, off, size);
    let got: Vec[UInt8] = ok_bytes(pcf_table_raw(&data, &p, t));
    if !bytes_equal(got, want_slice) { return assert(false, "raw span must equal the file slice"); }
    put_u32le(&mut rebuilt, t);
    put_u32le(&mut rebuilt, f);
    put_u32le(&mut rebuilt, size);
    put_u32le(&mut rebuilt, off2);
    off2 = off2 + size;
    i = i + 1;
  }
  i = 0;
  while i < pcf_table_count(&p) {
    let t2: Int = pcf_table_type(&p, i);
    let got2: Vec[UInt8] = ok_bytes(pcf_table_raw(&data, &p, t2));
    put_bytes(&mut rebuilt, &got2);
    i = i + 1;
  }
  return assert(bytes_equal(rebuilt, data), "parse -> raw spans -> reassemble is byte-exact");
}

fn t9() -> TestResult {
  let only = header_only();
  var ok = err_font_is(pcf_parse(&only), "pcf: missing metrics table");
  var two = Vec[UInt8].new();
  two.push(1 as UInt8);
  two.push(102 as UInt8);
  two.push(99 as UInt8);
  two.push(112 as UInt8);
  put_u32le(&mut two, 1);
  if !err_font_is(pcf_parse(&two), "pcf: truncated table directory") { ok = false; }
  var three = Vec[UInt8].new();
  three.push(1 as UInt8);
  three.push(102 as UInt8);
  three.push(99 as UInt8);
  three.push(112 as UInt8);
  put_u32le(&mut three, 2);
  put_u32le(&mut three, 2);
  put_u32le(&mut three, 1);
  put_u32le(&mut three, 4);
  put_u32le(&mut three, 40);
  if !err_font_is(pcf_parse(&three), "pcf: truncated table directory") { ok = false; }
  return assert(ok, "header-only and truncated table directory are errors");
}

fn t10() -> TestResult {
  let empty = Vec[UInt8].new();
  var ok = err_font_is(pcf_parse(&empty), "pcf: truncated header");
  let seven = hb("01666370000000");
  if !err_font_is(pcf_parse(&seven), "pcf: truncated header") { ok = false; }
  let zeros = hb("0000000000000000");
  if !err_font_is(pcf_parse(&zeros), "pcf: bad magic") { ok = false; }
  let bad1 = hb("0066637000000000");
  if !err_font_is(pcf_parse(&bad1), "pcf: bad magic") { ok = false; }
  let bad3 = hb("0166637100000000");
  if !err_font_is(pcf_parse(&bad3), "pcf: bad magic") { ok = false; }
  var patched = fixture(1);
  patch_byte(&mut patched, 0, 2);
  if !err_font_is(pcf_parse(&patched), "pcf: bad magic") { ok = false; }
  return assert(ok, "truncated headers and all four magic bytes are checked");
}

fn t11() -> TestResult {
  let no_metrics = fixture_with_types(1, types_without(2));
  var ok = err_font_is(pcf_parse(&no_metrics), "pcf: missing metrics table");
  let no_bitmaps = fixture_with_types(1, types_without(4));
  if !err_font_is(pcf_parse(&no_bitmaps), "pcf: missing bitmaps table") { ok = false; }
  var only_metrics = Vec[Int].new();
  only_metrics.push(2);
  let om = fixture_with_types(1, only_metrics);
  if !err_font_is(pcf_parse(&om), "pcf: missing bitmaps table") { ok = false; }
  var only_bitmaps = Vec[Int].new();
  only_bitmaps.push(4);
  let ob = fixture_with_types(1, only_bitmaps);
  if !err_font_is(pcf_parse(&ob), "pcf: missing metrics table") { ok = false; }
  return assert(ok, "metrics and bitmaps are required; others are not");
}

fn t12() -> TestResult {
  var compressed = fixture(1);
  patch_u32le(&mut compressed, 12, 65536);
  var ok = err_font_is(pcf_parse(&compressed), "pcf: compressed metrics unsupported");
  var legacy = fixture(1);
  patch_u32le(&mut legacy, 12, 256);
  if !err_font_is(pcf_parse(&legacy), "pcf: compressed metrics unsupported") { ok = false; }
  var unsupported = fixture(1);
  patch_u32le(&mut unsupported, 12, 3);
  if !err_font_is(pcf_parse(&unsupported), "pcf: unsupported metrics format") { ok = false; }
  var huge = fixture(1);
  patch_u32le(&mut huge, 12, 4294967295);
  if !err_font_is(pcf_parse(&huge), "pcf: unsupported metrics format") { ok = false; }
  return assert(ok, "compressed markers are recognized; other formats are rejected");
}

fn t13() -> TestResult {
  var small = fixture(1);
  patch_u32le(&mut small, 16, 27);
  var ok = err_font_is(pcf_parse(&small), "pcf: bad metrics table size");
  var big = fixture(1);
  patch_u32le(&mut big, 16, 40);
  if !err_font_is(pcf_parse(&big), "pcf: bad metrics table size") { ok = false; }
  var count3 = fixture(1);
  patch_u32le(&mut count3, 152, 3);
  if !err_font_is(pcf_parse(&count3), "pcf: bad metrics table size") { ok = false; }
  var count0 = fixture(1);
  patch_u32le(&mut count0, 152, 0);
  if !err_font_is(pcf_parse(&count0), "pcf: bad metrics table size") { ok = false; }
  return assert(ok, "metrics size must be exactly 4 + 12*count");
}

fn t14() -> TestResult {
  var three = fixture(1);
  patch_u32le(&mut three, 180, 3);
  var ok = err_font_is(pcf_parse(&three), "pcf: glyph count mismatch");
  var one = fixture(1);
  patch_u32le(&mut one, 180, 1);
  if !err_font_is(pcf_parse(&one), "pcf: glyph count mismatch") { ok = false; }
  return assert(ok, "bitmaps glyph count must equal the metrics count");
}

fn t15() -> TestResult {
  var bo_high = fixture(1);
  patch_u32le(&mut bo_high, 196, 39);
  var ok = err_font_is(pcf_parse(&bo_high), "pcf: bitmap out of bounds");
  var bo_low = fixture(1);
  patch_u32le(&mut bo_low, 188, 27);
  if !err_font_is(pcf_parse(&bo_low), "pcf: bitmap out of bounds") { ok = false; }
  var span_big = fixture(1);
  patch_u32le(&mut span_big, 204, 9);
  if !err_font_is(pcf_parse(&span_big), "pcf: bitmap out of bounds") { ok = false; }
  var mo_bad = fixture(1);
  patch_u32le(&mut mo_bad, 192, 8);
  if !err_font_is(pcf_parse(&mo_bad), "pcf: bad metrics offset") { ok = false; }
  var permissive = fixture(1);
  patch_u32le(&mut permissive, 200, 6);
  let r2 = pcf_parse(&permissive);
  if !r2.is_ok {
    ok = false;
  } else {
    let p2: PcfFont = r2.value;
    if pcf_bitmap_span(&p2, 0) != 6 { ok = false; }
    if pcf_bitmap_size(&p2) != 12 { ok = false; }
  }
  return assert(ok, "bitmap offsets/spans are bounded; stored span is authoritative");
}

fn t16() -> TestResult {
  var too_small = fixture(1);
  patch_u32le(&mut too_small, 48, 11);
  var ok = err_font_is(pcf_parse(&too_small), "pcf: bad encodings table size");
  var odd_pool = fixture(1);
  patch_u32le(&mut odd_pool, 48, 13);
  if !err_font_is(pcf_parse(&odd_pool), "pcf: bad encodings table size") { ok = false; }
  var bad_range = fixture(1);
  patch_u16le(&mut bad_range, 222, 64);
  if !err_font_is(pcf_parse(&bad_range), "pcf: bad encoding range") { ok = false; }
  var bad_value = fixture(1);
  patch_u16le(&mut bad_value, 234, 68);
  if !err_font_is(pcf_parse(&bad_value), "pcf: encoding out of range") { ok = false; }
  var bad_run = fixture(1);
  patch_u16le(&mut bad_run, 226, 3);
  if !err_font_is(pcf_parse(&bad_run), "pcf: bad encoding run") { ok = false; }
  var bad_run2 = fixture(1);
  patch_u16le(&mut bad_run2, 228, 5);
  if !err_font_is(pcf_parse(&bad_run2), "pcf: bad encoding run") { ok = false; }
  var bad_first = fixture(1);
  patch_u16le(&mut bad_first, 224, 1);
  patch_u16le(&mut bad_first, 228, 0);
  if !err_font_is(pcf_parse(&bad_first), "pcf: bad encoding run") { ok = false; }
  return assert(ok, "encodings size, range, pool values and runs are validated");
}

fn t17() -> TestResult {
  var off_bad = fixture(1);
  patch_u32le(&mut off_bad, 68, 261);
  var ok = err_font_is(pcf_parse(&off_bad), "pcf: table out of bounds");
  var size_bad = fixture(1);
  patch_u32le(&mut size_bad, 64, 100);
  if !err_font_is(pcf_parse(&size_bad), "pcf: table out of bounds") { ok = false; }
  var accel_bad = fixture(1);
  patch_u32le(&mut accel_bad, 144, 10);
  if !err_font_is(pcf_parse(&accel_bad), "pcf: table out of bounds") { ok = false; }
  var many = fixture(1);
  patch_u32le(&mut many, 4, 1000);
  if !err_font_is(pcf_parse(&many), "pcf: truncated table directory") { ok = false; }
  return assert(ok, "directory table spans must lie inside the buffer");
}

fn t18() -> TestResult {
  let data = empty_font();
  var ok = data.len() == 48;
  let r = pcf_parse(&data);
  if !r.is_ok {
    return assert(false, "empty two-table font must parse");
  }
  let p: PcfFont = r.value;
  if pcf_glyph_count(&p) != 0 { ok = false; }
  if pcf_table_count(&p) != 2 { ok = false; }
  if pcf_bitmap_size(&p) != 0 { ok = false; }
  if pcf_bitmap_span(&p, 0) != -1 { ok = false; }
  if !err_bytes_is(pcf_bitmap_bytes(&data, &p, 0), "pcf: index out of range") { ok = false; }
  if !err_ints_is(pcf_metrics_at(&p, 0), "pcf: index out of range") { ok = false; }
  if pcf_metric_lsb(&p, 0) != 0 { ok = false; }
  if pcf_has_encodings(&p) { ok = false; }
  if pcf_encoding_min(&p) != -1 { ok = false; }
  if pcf_encoding_max(&p) != -1 { ok = false; }
  if pcf_encoding_count(&p, 0) != 0 { ok = false; }
  if pcf_encoding_at(&p, 0, 0) != -1 { ok = false; }
  if !err_ints_is(pcf_encodings_at(&p, 0), "pcf: no encodings table") { ok = false; }
  if pcf_glyph_for_encoding(&p, 65) != -1 { ok = false; }
  return assert(ok, "zero-glyph font parses; absent encodings read as no mappings");
}

fn t19() -> TestResult {
  var types = all_types();
  types.push(1048576);
  let data = fixture_with_types(1, types);
  let r = pcf_parse(&data);
  if !r.is_ok {
    return assert(false, "unknown-table fixture must parse");
  }
  let p: PcfFont = r.value;
  var ok = pcf_table_count(&p) == 10;
  if pcf_table_find(&p, 1048576) != 9 { ok = false; }
  if pcf_table_format(&p, 9) != 3 { ok = false; }
  if !bytes_equal(ok_bytes(pcf_table_raw(&data, &p, 1048576)), hb("deadbeef")) { ok = false; }
  var dup = Vec[Int].new();
  dup.push(2);
  dup.push(4);
  dup.push(2);
  dup.push(16);
  let ddata = fixture_with_types(1, dup);
  let dr = pcf_parse(&ddata);
  if !dr.is_ok {
    return assert(false, "duplicate-table fixture must parse");
  }
  let dp: PcfFont = dr.value;
  if pcf_table_count(&dp) != 4 { ok = false; }
  if pcf_table_find(&dp, 2) != 0 { ok = false; }
  if !bytes_equal(ok_bytes(pcf_table_raw(&ddata, &dp, 2)), metrics_table(1)) { ok = false; }
  var reversed = Vec[Int].new();
  reversed.push(4);
  reversed.push(2);
  let rdata = fixture_with_types(1, reversed);
  let rr = pcf_parse(&rdata);
  if !rr.is_ok {
    ok = false;
  } else {
    let rp: PcfFont = rr.value;
    if pcf_glyph_count(&rp) != 2 { ok = false; }
    if pcf_table_find(&rp, 2) != 1 { ok = false; }
  }
  return assert(ok, "unknown types are preserved; duplicates keep the first; order is free");
}

fn t20() -> TestResult {
  let a = fixture(0);
  let b = fixture(1);
  let c = fixture(2);
  let ra = pcf_parse(&a);
  let rb = pcf_parse(&b);
  let rc = pcf_parse(&c);
  if !ra.is_ok || !rb.is_ok || !rc.is_ok {
    return assert(false, "all three metrics formats must parse");
  }
  let pa: PcfFont = ra.value;
  let pb: PcfFont = rb.value;
  let pc: PcfFont = rc.value;
  var ok = true;
  var g = 0;
  while g < pcf_glyph_count(&pb) {
    if pcf_metric_lsb(&pa, g) != pcf_metric_lsb(&pb, g) { ok = false; }
    if pcf_metric_rsb(&pa, g) != pcf_metric_rsb(&pb, g) { ok = false; }
    if pcf_metric_advance(&pa, g) != pcf_metric_advance(&pb, g) { ok = false; }
    if pcf_metric_ascent(&pa, g) != pcf_metric_ascent(&pb, g) { ok = false; }
    if pcf_metric_descent(&pa, g) != pcf_metric_descent(&pb, g) { ok = false; }
    if pcf_metric_attributes(&pa, g) != pcf_metric_attributes(&pb, g) { ok = false; }
    if pcf_metric_lsb(&pc, g) != pcf_metric_lsb(&pb, g) { ok = false; }
    if pcf_metric_attributes(&pc, g) != pcf_metric_attributes(&pb, g) { ok = false; }
    if pcf_bitmap_span(&pa, g) != pcf_bitmap_span(&pb, g) { ok = false; }
    if pcf_bitmap_raw_offset(&pc, g) != pcf_bitmap_raw_offset(&pb, g) { ok = false; }
    g = g + 1;
  }
  if pcf_encoding_min(&pa) != pcf_encoding_min(&pb) { ok = false; }
  if pcf_encoding_max(&pc) != pcf_encoding_max(&pb) { ok = false; }
  var i = 0;
  while i < pcf_table_count(&pb) {
    if pcf_table_type(&pa, i) != pcf_table_type(&pb, i) { ok = false; }
    if pcf_table_offset(&pc, i) != pcf_table_offset(&pb, i) { ok = false; }
    if pcf_table_size(&pa, i) != pcf_table_size(&pb, i) { ok = false; }
    i = i + 1;
  }
  let b2 = fixture(1);
  let rb2 = pcf_parse(&b2);
  if !rb2.is_ok {
    ok = false;
  } else {
    let pb2: PcfFont = rb2.value;
    if pcf_glyph_count(&pb2) != pcf_glyph_count(&pb) { ok = false; }
    if pcf_metric_descent(&pb2, 1) != pcf_metric_descent(&pb, 1) { ok = false; }
    if pcf_glyph_for_encoding(&pb2, 67) != 1 { ok = false; }
  }
  return assert(ok, "all three metrics formats agree; parsing is deterministic");
}

// --------------------------------------------------
//  Harness
// --------------------------------------------------

fn report(r: TestResult) -> Int {
  if r.passed {
    io.println("  [PASS] " + r.name);
    return 0;
  }
  io.println("  [FAIL] " + r.name);
  return 1;
}

fn main() -> Int {
  io.println("=== xiom.pcf conformance tests ===");
  var failed: Int = 0;
  failed = failed + report(t1());
  failed = failed + report(t2());
  failed = failed + report(t3());
  failed = failed + report(t4());
  failed = failed + report(t5());
  failed = failed + report(t6());
  failed = failed + report(t7());
  failed = failed + report(t8());
  failed = failed + report(t9());
  failed = failed + report(t10());
  failed = failed + report(t11());
  failed = failed + report(t12());
  failed = failed + report(t13());
  failed = failed + report(t14());
  failed = failed + report(t15());
  failed = failed + report(t16());
  failed = failed + report(t17());
  failed = failed + report(t18());
  failed = failed + report(t19());
  failed = failed + report(t20());
  if failed == 0 {
    io.println("xiom.pcf: all tests passed");
  } else {
    io.println("xiom.pcf: tests failed");
  }
  return failed;
}
