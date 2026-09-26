// XIOM -- xiom.psf conformance tests (20 checks)
// Port task: prove the pure-XIOM xiom.psf PSF1/PSF2 console-font codec
// against the documented layouts, accessors and error catalog.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Covers: hand-built PSF1 fixtures (256 and 512 glyphs), hand-built PSF2
// fixtures, unicode tables (per-glyph runs, terminators, empty lists,
// duplicate and special codepoints, first-match lookup), the strict
// trailing-bytes policy, header validation in order, glyph bounds, the
// glyph-span copier guards, canonical PSF1/PSF2 builds with and without
// unicode tables, and build -> parse -> build byte-exact round trips.
//
// Str values are never compared with `==`; error messages and names go
// through compare.str_compare.

module psf_tests
use xiom.io; use xiom.test;
use xiom.psf;
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

fn str_eq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn err_font_is(r: Result[PsfFont, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_bytes_is(r: Result[Vec[UInt8], Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn ok_font(r: Result[PsfFont, Str]) -> PsfFont {
  if r.is_ok {
    let f: PsfFont = r.value;
    return f;
  }
  return PsfFont{
    version: 0; char_count: 0; charsize: 0; height: 0; width: 0;
    has_unicode: false; glyph_offset: 0;
    uni_starts: Vec[Int].new(); uni_counts: Vec[Int].new(); uni_values: Vec[Int].new();
  };
}

fn ok_bytes(r: Result[Vec[UInt8], Str]) -> Vec[UInt8] {
  if r.is_ok {
    let v: Vec[UInt8] = r.value;
    return v;
  }
  return Vec[UInt8].new();
}

// Unsigned readers for pinning fixture/emit bytes.
fn rd8(v: &Vec[UInt8], off: Int) -> Int {
  return (v[off] as Int) & 0xFF;
}

fn rd16le(v: &Vec[UInt8], off: Int) -> Int {
  return rd8(v, off) + rd8(v, off + 1) * 256;
}

fn rd32le(v: &Vec[UInt8], off: Int) -> Int {
  return rd8(v, off) + rd8(v, off + 1) * 256 + rd8(v, off + 2) * 65536 + rd8(v, off + 3) * 16777216;
}

// Little-endian appenders for building fixtures.
fn put_u16le(out: &mut Vec[UInt8], v: Int) {
  out.push((v % 256) as UInt8);
  out.push(((v / 256) % 256) as UInt8);
}

fn put_u32le(out: &mut Vec[UInt8], v: Int) {
  out.push((v % 256) as UInt8);
  out.push(((v / 256) % 256) as UInt8);
  out.push(((v / 65536) % 256) as UInt8);
  out.push(((v / 16777216) % 256) as UInt8);
}

// In-place field patches for building malformed variants of a fixture.
fn patch_byte(buf: &mut Vec[UInt8], off: Int, v: Int) {
  buf[off] = (v % 256) as UInt8;
}

fn patch_u32le(buf: &mut Vec[UInt8], off: Int, v: Int) {
  buf[off] = (v % 256) as UInt8;
  buf[off + 1] = ((v / 256) % 256) as UInt8;
  buf[off + 2] = ((v / 65536) % 256) as UInt8;
  buf[off + 3] = ((v / 16777216) % 256) as UInt8;
}

fn slice(v: Vec[UInt8], off: Int, len: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < len && off + i < v.len() {
    out.push(v[off + i]);
    i = i + 1;
  }
  return out;
}

fn extend(a: Vec[UInt8], b: Vec[UInt8]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < a.len() {
    out.push(a[i]);
    i = i + 1;
  }
  var j = 0;
  while j < b.len() {
    out.push(b[j]);
    j = j + 1;
  }
  return out;
}

// A repeating glyph-byte pattern: byte i is i % 256.
fn glyph_pattern(n: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < n {
    out.push((i % 256) as UInt8);
    i = i + 1;
  }
  return out;
}

// `count` independent empty codepoint lists.
fn empty_lists(count: Int) -> Vec[Vec[Int]] {
  var out = Vec[Vec[Int]].new();
  var i = 0;
  while i < count {
    let e = Vec[Int].new();
    out.push(e);
    i = i + 1;
  }
  return out;
}

// Build per-glyph lists from a flat spec: a count, then that many
// codepoints, repeated. One list per block.
fn make_uni(spec: &Vec[Int]) -> Vec[Vec[Int]] {
  var out = Vec[Vec[Int]].new();
  var i = 0;
  while i < spec.len() {
    let n: Int = spec[i];
    i = i + 1;
    var list = Vec[Int].new();
    var k = 0;
    while k < n {
      let cp: Int = spec[i];
      list.push(cp);
      i = i + 1;
      k = k + 1;
    }
    out.push(list);
  }
  return out;
}

// One non-empty list (first glyph) followed by `count - 1` empty lists.
fn spec_one(count: Int, a: Int) -> Vec[Vec[Int]] {
  var spec = Vec[Int].new();
  spec.push(1);
  spec.push(a);
  var g = 1;
  while g < count {
    spec.push(0);
    g = g + 1;
  }
  return make_uni(&spec);
}

// --------------------------------------------------
//  Fixtures
// --------------------------------------------------

// PSF1 header + count * charsize glyph bytes; glyph g starts with byte
// (g * charsize) % 256.
fn psf1_hand(mode: Int, charsize: Int, count: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  out.push(54 as UInt8); // 0x36
  out.push(4 as UInt8);  // 0x04
  out.push(mode as UInt8);
  out.push(charsize as UInt8);
  var i = 0;
  while i < count * charsize {
    out.push((i % 256) as UInt8);
    i = i + 1;
  }
  return out;
}

// PSF2 32-byte header + count * charsize glyph bytes; same glyph pattern.
fn psf2_hand(flags: Int, count: Int, charsize: Int, height: Int, width: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  out.push(114 as UInt8); // 0x72
  out.push(181 as UInt8); // 0xB5
  out.push(74 as UInt8);  // 0x4A
  out.push(134 as UInt8); // 0x86
  put_u32le(&mut out, 0);   // version
  put_u32le(&mut out, 32);  // header size
  put_u32le(&mut out, flags);
  put_u32le(&mut out, count);
  put_u32le(&mut out, charsize);
  put_u32le(&mut out, height);
  put_u32le(&mut out, width);
  var i = 0;
  while i < count * charsize {
    out.push((i % 256) as UInt8);
    i = i + 1;
  }
  return out;
}

// Append the unicode table for `count` glyphs: each list's codepoints as
// little-endian u16 values, then a 0xFFFF terminator per glyph.
fn append_uni(out: &mut Vec[UInt8], uni: &Vec[Vec[Int]], count: Int) {
  var g = 0;
  while g < count {
    let list: Vec[Int] = uni[g];
    let ln = list.len();
    var i = 0;
    while i < ln {
      let cp: Int = list[i];
      put_u16le(out, cp);
      i = i + 1;
    }
    put_u16le(out, 65535);
    g = g + 1;
  }
}

fn psf1_uni_hand(mode: Int, charsize: Int, count: Int, uni: &Vec[Vec[Int]]) -> Vec[UInt8] {
  var out = psf1_hand(mode, charsize, count);
  append_uni(&mut out, uni, count);
  return out;
}

fn psf2_uni_hand(flags: Int, count: Int, charsize: Int, height: Int, width: Int, uni: &Vec[Vec[Int]]) -> Vec[UInt8] {
  var out = psf2_hand(flags, count, charsize, height, width);
  append_uni(&mut out, uni, count);
  return out;
}

// 256-glyph PSF1 unicode spec: g0 [0], g1 [1,1000], g2 [], g5 [2,5],
// g7 [8,7] (a literal "special" codepoint before its own glyph), g [g].
fn spec_psf1_256() -> Vec[Vec[Int]] {
  var spec = Vec[Int].new();
  var g = 0;
  while g < 256 {
    if g == 1 { spec.push(2); spec.push(1); spec.push(1000); }
    if g == 2 { spec.push(0); }
    if g == 5 { spec.push(2); spec.push(2); spec.push(5); }
    if g == 7 { spec.push(2); spec.push(8); spec.push(7); }
    if g != 1 && g != 2 && g != 5 && g != 7 { spec.push(1); spec.push(g); }
    g = g + 1;
  }
  return make_uni(&spec);
}

// 256-glyph spec with codepoints only on glyphs 0..2 (for the builder).
fn spec_psf1_256_small() -> Vec[Vec[Int]] {
  var spec = Vec[Int].new();
  var g = 0;
  while g < 256 {
    if g == 0 { spec.push(1); spec.push(65); }
    if g == 1 { spec.push(0); }
    if g == 2 { spec.push(2); spec.push(66); spec.push(67); }
    if g != 0 && g != 1 && g != 2 { spec.push(0); }
    g = g + 1;
  }
  return make_uni(&spec);
}

// 512-glyph spec: glyph g holds codepoint g % 256 (duplicates on purpose).
fn spec_psf1_512() -> Vec[Vec[Int]] {
  var spec = Vec[Int].new();
  var g = 0;
  while g < 512 {
    spec.push(1);
    spec.push(g % 256);
    g = g + 1;
  }
  return make_uni(&spec);
}

// Reconstruct the raw glyph byte vector of a parsed font through the
// documented per-glyph copier.
fn glyphs_of(data: &Vec[UInt8], f: &PsfFont) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var g = 0;
  while g < psf_charcount(f) {
    let r = psf_glyph_bytes(data, f, g);
    if r.is_ok {
      let chunk: Vec[UInt8] = r.value;
      var i = 0;
      while i < chunk.len() {
        out.push(chunk[i]);
        i = i + 1;
      }
    }
    g = g + 1;
  }
  return out;
}

// Reconstruct the per-glyph codepoint lists of a parsed font.
fn uni_of(f: &PsfFont) -> Vec[Vec[Int]] {
  var out = Vec[Vec[Int]].new();
  var g = 0;
  while g < psf_charcount(f) {
    var list = Vec[Int].new();
    let c = psf_unicode_count(f, g);
    var i = 0;
    while i < c {
      let cp = psf_unicode_at(f, g, i);
      list.push(cp);
      i = i + 1;
    }
    out.push(list);
    g = g + 1;
  }
  return out;
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  let src = psf1_hand(0, 8, 256);
  let f = ok_font(psf_parse(&src));
  var ok = psf_version(&f) == 1;
  if psf_charcount(&f) != 256 { ok = false; }
  if psf_charsize(&f) != 8 { ok = false; }
  if psf_height(&f) != 8 { ok = false; }
  if psf_width(&f) != 8 { ok = false; }
  if psf_has_unicode(&f) { ok = false; }
  if psf_glyph_span(&f, 0) != 8 { ok = false; }
  if psf_glyph_span(&f, 255) != 8 { ok = false; }
  if psf_glyph_span(&f, 256) != -1 { ok = false; }
  if psf_glyph_span(&f, -1) != -1 { ok = false; }
  if !bytes_equal(ok_bytes(psf_glyph_bytes(&src, &f, 0)), hb("0001020304050607")) { ok = false; }
  if !bytes_equal(ok_bytes(psf_glyph_bytes(&src, &f, 255)), hb("f8f9fafbfcfdfeff")) { ok = false; }
  if psf_unicode_count(&f, 0) != 0 { ok = false; }
  if psf_unicode_at(&f, 0, 0) != -1 { ok = false; }
  if psf_char_for_unicode(&f, 65) != -1 { ok = false; }
  return assert(ok, "canonical PSF1 256x8 parse pins header fields and glyph bytes");
}

fn t2() -> TestResult {
  let src = psf1_hand(1, 4, 512);
  let f = ok_font(psf_parse(&src));
  var ok = psf_version(&f) == 1;
  if psf_charcount(&f) != 512 { ok = false; }
  if psf_charsize(&f) != 4 { ok = false; }
  if psf_height(&f) != 4 { ok = false; }
  if psf_width(&f) != 8 { ok = false; }
  if psf_has_unicode(&f) { ok = false; }
  if psf_glyph_span(&f, 511) != 4 { ok = false; }
  if psf_glyph_span(&f, 512) != -1 { ok = false; }
  if rd8(&src, 2) != 1 { ok = false; }
  if !bytes_equal(ok_bytes(psf_glyph_bytes(&src, &f, 511)), hb("fcfdfeff")) { ok = false; }
  if !bytes_equal(ok_bytes(psf_glyph_bytes(&src, &f, 0)), hb("00010203")) { ok = false; }
  return assert(ok, "PSF1 mode bit 0 selects 512 glyphs and the last glyph reads back");
}

fn t3() -> TestResult {
  let uni = spec_psf1_256();
  let src = psf1_uni_hand(2, 8, 256, &uni);
  let f = ok_font(psf_parse(&src));
  var ok = psf_has_unicode(&f);
  if psf_unicode_count(&f, 0) != 1 { ok = false; }
  if psf_unicode_at(&f, 0, 0) != 0 { ok = false; }
  if psf_unicode_count(&f, 1) != 2 { ok = false; }
  if psf_unicode_at(&f, 1, 0) != 1 { ok = false; }
  if psf_unicode_at(&f, 1, 1) != 1000 { ok = false; }
  if psf_unicode_count(&f, 2) != 0 { ok = false; }
  if psf_unicode_at(&f, 2, 0) != -1 { ok = false; }
  if psf_unicode_count(&f, 7) != 2 { ok = false; }
  if psf_unicode_at(&f, 7, 0) != 8 { ok = false; }
  if psf_unicode_at(&f, 7, 1) != 7 { ok = false; }
  if psf_unicode_count(&f, 255) != 1 { ok = false; }
  if psf_unicode_at(&f, 255, 0) != 255 { ok = false; }
  if psf_unicode_count(&f, 256) != -1 { ok = false; }
  if psf_unicode_at(&f, 1, 2) != -1 { ok = false; }
  if psf_unicode_at(&f, 1, -1) != -1 { ok = false; }
  if psf_char_for_unicode(&f, 0) != 0 { ok = false; }
  if psf_char_for_unicode(&f, 1) != 1 { ok = false; }
  if psf_char_for_unicode(&f, 2) != 5 { ok = false; }
  if psf_char_for_unicode(&f, 5) != 5 { ok = false; }
  if psf_char_for_unicode(&f, 8) != 7 { ok = false; }
  if psf_char_for_unicode(&f, 7) != 7 { ok = false; }
  if psf_char_for_unicode(&f, 1000) != 1 { ok = false; }
  if psf_char_for_unicode(&f, 65534) != -1 { ok = false; }
  if psf_char_for_unicode(&f, 65535) != -1 { ok = false; }
  if psf_char_for_unicode(&f, -1) != -1 { ok = false; }
  return assert(ok, "PSF1 unicode table: per-glyph counts, literal specials and first-match lookup");
}

fn t4() -> TestResult {
  var ok = err_font_is(psf_parse(&hb("")), "psf: truncated header");
  if !err_font_is(psf_parse(&hb("36")), "psf: truncated header") { ok = false; }
  if !err_font_is(psf_parse(&hb("3604")), "psf: truncated header") { ok = false; }
  if !err_font_is(psf_parse(&hb("360400")), "psf: truncated header") { ok = false; }
  if !err_font_is(psf_parse(&hb("36050000")), "psf: bad signature") { ok = false; }
  if !err_font_is(psf_parse(&hb("36040400")), "psf: reserved mode bits") { ok = false; }
  if !err_font_is(psf_parse(&hb("36048000")), "psf: reserved mode bits") { ok = false; }
  if !err_font_is(psf_parse(&hb("36040000")), "psf: invalid charsize") { ok = false; }
  if !err_font_is(psf_parse(&hb("36040021")), "psf: invalid charsize") { ok = false; }
  let full = psf1_hand(0, 8, 256);
  let flen = full.len();
  let cut = slice(full, 0, flen - 1);
  if !err_font_is(psf_parse(&cut), "psf: glyph data out of bounds") { ok = false; }
  let base = psf1_hand(0, 8, 256);
  let trailed = extend(base, hb("00"));
  if !err_font_is(psf_parse(&trailed), "psf: trailing bytes") { ok = false; }
  let uni = spec_psf1_256();
  let ufull = psf1_uni_hand(2, 8, 256, &uni);
  let ulen = ufull.len();
  let cut1 = slice(ufull, 0, ulen - 1);
  if !err_font_is(psf_parse(&cut1), "psf: unicode table out of bounds") { ok = false; }
  let ufull2 = psf1_uni_hand(2, 8, 256, &uni);
  let ulen2 = ufull2.len();
  let cut2 = slice(ufull2, 0, ulen2 - 2);
  if !err_font_is(psf_parse(&cut2), "psf: unicode table out of bounds") { ok = false; }
  let ufull3 = psf1_uni_hand(2, 8, 256, &uni);
  let utrailed = extend(ufull3, hb("00"));
  if !err_font_is(psf_parse(&utrailed), "psf: trailing bytes") { ok = false; }
  return assert(ok, "PSF1 header, charsize, glyph bounds, terminator and trailing-bytes errors");
}

fn t5() -> TestResult {
  let src = psf2_hand(0, 4, 16, 16, 8);
  let f = ok_font(psf_parse(&src));
  var ok = psf_version(&f) == 2;
  if psf_charcount(&f) != 4 { ok = false; }
  if psf_charsize(&f) != 16 { ok = false; }
  if psf_height(&f) != 16 { ok = false; }
  if psf_width(&f) != 8 { ok = false; }
  if psf_has_unicode(&f) { ok = false; }
  if src.len() != 96 { ok = false; }
  if psf_glyph_span(&f, 0) != 16 { ok = false; }
  if psf_glyph_span(&f, 3) != 16 { ok = false; }
  if psf_glyph_span(&f, 4) != -1 { ok = false; }
  if !bytes_equal(ok_bytes(psf_glyph_bytes(&src, &f, 3)), hb("303132333435363738393a3b3c3d3e3f")) { ok = false; }
  if psf_unicode_count(&f, 0) != 0 { ok = false; }
  if psf_char_for_unicode(&f, 65) != -1 { ok = false; }
  return assert(ok, "canonical PSF2 parse pins the 32-byte header fields and glyph bytes");
}

fn t6() -> TestResult {
  let tiny = psf2_hand(0, 1, 1, 1, 1);
  let f1 = ok_font(psf_parse(&tiny));
  var ok = psf_version(&f1) == 2;
  if psf_width(&f1) != 1 { ok = false; }
  if psf_height(&f1) != 1 { ok = false; }
  if psf_charsize(&f1) != 1 { ok = false; }
  if psf_glyph_span(&f1, 0) != 1 { ok = false; }
  if !bytes_equal(ok_bytes(psf_glyph_bytes(&tiny, &f1, 0)), hb("00")) { ok = false; }
  let wide = psf2_hand(0, 1, 256, 1, 64);
  let f2 = ok_font(psf_parse(&wide));
  if psf_width(&f2) != 64 { ok = false; }
  if psf_charsize(&f2) != 256 { ok = false; }
  if psf_glyph_span(&f2, 0) != 256 { ok = false; }
  let tall = psf2_hand(0, 1, 8, 1000, 8);
  let f3 = ok_font(psf_parse(&tall));
  if psf_height(&f3) != 1000 { ok = false; }
  return assert(ok, "PSF2 accepts width 1 and 64, charsize 1 and 256, and any height >= 1");
}

fn t7() -> TestResult {
  var spec = Vec[Int].new();
  spec.push(1); spec.push(65);
  spec.push(2); spec.push(66); spec.push(67);
  spec.push(0);
  spec.push(1); spec.push(68);
  let uni = make_uni(&spec);
  let src = psf2_uni_hand(1, 4, 8, 8, 8, &uni);
  let f = ok_font(psf_parse(&src));
  var ok = psf_has_unicode(&f);
  if src.len() != 80 { ok = false; }
  if rd16le(&src, 64) != 65 { ok = false; }
  if rd16le(&src, 66) != 65535 { ok = false; }
  if rd16le(&src, 68) != 66 { ok = false; }
  if rd16le(&src, 70) != 67 { ok = false; }
  if rd16le(&src, 72) != 65535 { ok = false; }
  if rd16le(&src, 74) != 65535 { ok = false; }
  if rd16le(&src, 76) != 68 { ok = false; }
  if rd16le(&src, 78) != 65535 { ok = false; }
  if psf_unicode_count(&f, 0) != 1 { ok = false; }
  if psf_unicode_count(&f, 1) != 2 { ok = false; }
  if psf_unicode_count(&f, 2) != 0 { ok = false; }
  if psf_unicode_count(&f, 3) != 1 { ok = false; }
  if psf_unicode_at(&f, 1, 0) != 66 { ok = false; }
  if psf_unicode_at(&f, 1, 1) != 67 { ok = false; }
  if psf_unicode_at(&f, 3, 0) != 68 { ok = false; }
  if psf_char_for_unicode(&f, 65) != 0 { ok = false; }
  if psf_char_for_unicode(&f, 67) != 1 { ok = false; }
  if psf_char_for_unicode(&f, 68) != 3 { ok = false; }
  if psf_char_for_unicode(&f, 66) != 1 { ok = false; }
  if psf_char_for_unicode(&f, 0) != -1 { ok = false; }
  return assert(ok, "PSF2 unicode table pins raw bytes, counts and lookup");
}

fn t8() -> TestResult {
  var ok = err_font_is(psf_parse(&hb("72b54a86")), "psf: truncated header");
  let base = psf2_hand(0, 4, 16, 16, 8);
  let short = slice(base, 0, 31);
  if !err_font_is(psf_parse(&short), "psf: truncated header") { ok = false; }
  if !err_font_is(psf_parse(&hb("deadbeef")), "psf: bad signature") { ok = false; }
  var b = psf2_hand(0, 4, 16, 16, 8);
  patch_u32le(&mut b, 4, 1);
  if !err_font_is(psf_parse(&b), "psf: unsupported version") { ok = false; }
  var hs = psf2_hand(0, 4, 16, 16, 8);
  patch_u32le(&mut hs, 8, 28);
  if !err_font_is(psf_parse(&hs), "psf: bad header size") { ok = false; }
  var hs2 = psf2_hand(0, 4, 16, 16, 8);
  patch_u32le(&mut hs2, 8, 64);
  if !err_font_is(psf_parse(&hs2), "psf: bad header size") { ok = false; }
  var fl = psf2_hand(0, 4, 16, 16, 8);
  patch_u32le(&mut fl, 12, 2);
  if !err_font_is(psf_parse(&fl), "psf: reserved flag bits") { ok = false; }
  var fl2 = psf2_hand(0, 4, 16, 16, 8);
  patch_u32le(&mut fl2, 12, 2147483648);
  if !err_font_is(psf_parse(&fl2), "psf: reserved flag bits") { ok = false; }
  var cs = psf2_hand(0, 4, 16, 16, 8);
  patch_u32le(&mut cs, 20, 0);
  if !err_font_is(psf_parse(&cs), "psf: invalid charsize") { ok = false; }
  var cs2 = psf2_hand(0, 4, 16, 16, 8);
  patch_u32le(&mut cs2, 20, 257);
  if !err_font_is(psf_parse(&cs2), "psf: invalid charsize") { ok = false; }
  var wi = psf2_hand(0, 4, 16, 16, 8);
  patch_u32le(&mut wi, 28, 0);
  if !err_font_is(psf_parse(&wi), "psf: invalid width") { ok = false; }
  var wi2 = psf2_hand(0, 4, 16, 16, 8);
  patch_u32le(&mut wi2, 28, 65);
  if !err_font_is(psf_parse(&wi2), "psf: invalid width") { ok = false; }
  var he = psf2_hand(0, 4, 16, 16, 8);
  patch_u32le(&mut he, 24, 0);
  if !err_font_is(psf_parse(&he), "psf: invalid height") { ok = false; }
  var gb = psf2_hand(0, 4, 16, 16, 8);
  patch_u32le(&mut gb, 16, 5);
  if !err_font_is(psf_parse(&gb), "psf: glyph data out of bounds") { ok = false; }
  var tr = psf2_hand(0, 4, 16, 16, 8);
  let trailed = extend(tr, hb("00"));
  if !err_font_is(psf_parse(&trailed), "psf: trailing bytes") { ok = false; }
  var nf = psf2_hand(1, 4, 16, 16, 8);
  if !err_font_is(psf_parse(&nf), "psf: unicode table out of bounds") { ok = false; }
  var one = psf2_hand(1, 1, 4, 8, 8);
  let halfterm = extend(one, hb("ff"));
  if !err_font_is(psf_parse(&halfterm), "psf: unicode table out of bounds") { ok = false; }
  var two = psf2_hand(1, 1, 4, 8, 8);
  let fullterm = extend(two, hb("ffff"));
  var three = fullterm;
  let after = extend(three, hb("00"));
  if !err_font_is(psf_parse(&after), "psf: trailing bytes") { ok = false; }
  var four = psf2_hand(1, 1, 4, 8, 8);
  let fullterm2 = extend(four, hb("ffff"));
  let parsed = ok_font(psf_parse(&fullterm2));
  if !psf_has_unicode(&parsed) { ok = false; }
  if psf_unicode_count(&parsed, 0) != 0 { ok = false; }
  return assert(ok, "PSF2 header, bounds, terminator and trailing-bytes errors in order");
}

fn t9() -> TestResult {
  let empty2 = psf2_hand(0, 0, 8, 8, 8);
  let f = ok_font(psf_parse(&empty2));
  var ok = psf_version(&f) == 2;
  if psf_charcount(&f) != 0 { ok = false; }
  if psf_has_unicode(&f) { ok = false; }
  if psf_glyph_span(&f, 0) != -1 { ok = false; }
  if psf_unicode_count(&f, 0) != -1 { ok = false; }
  if psf_char_for_unicode(&f, 65) != -1 { ok = false; }
  if empty2.len() != 32 { ok = false; }
  let flagged = psf2_hand(1, 0, 8, 8, 8);
  let f2 = ok_font(psf_parse(&flagged));
  if !psf_has_unicode(&f2) { ok = false; }
  if psf_charcount(&f2) != 0 { ok = false; }
  if psf_unicode_count(&f2, 0) != -1 { ok = false; }
  if !err_font_is(psf_parse(&extend(psf2_hand(0, 0, 8, 8, 8), hb("00"))), "psf: trailing bytes") { ok = false; }
  return assert(ok, "a zero-glyph PSF2 header parses; one extra byte is trailing data");
}

fn t10() -> TestResult {
  let glyphs = glyph_pattern(1024);
  let uni = empty_lists(256);
  let built = ok_bytes(psf_build1(&glyphs, 4, &uni));
  var ok = built.len() == 1028;
  if rd8(&built, 0) != 54 { ok = false; }
  if rd8(&built, 1) != 4 { ok = false; }
  if rd8(&built, 2) != 0 { ok = false; }
  if rd8(&built, 3) != 4 { ok = false; }
  if rd8(&built, 4) != 0 { ok = false; }
  if rd8(&built, 1027) != 255 { ok = false; }
  let f = ok_font(psf_parse(&built));
  if psf_version(&f) != 1 { ok = false; }
  if psf_charcount(&f) != 256 { ok = false; }
  if psf_charsize(&f) != 4 { ok = false; }
  if psf_height(&f) != 4 { ok = false; }
  if psf_width(&f) != 8 { ok = false; }
  if psf_has_unicode(&f) { ok = false; }
  let back = glyphs_of(&built, &f);
  if !bytes_equal(back, glyphs) { ok = false; }
  let uni2 = empty_lists(256);
  let rebuilt = ok_bytes(psf_build1(&back, 4, &uni2));
  if !bytes_equal(rebuilt, built) { ok = false; }
  return assert(ok, "psf_build1 emits the canonical 256-glyph header and glyph area");
}

fn t11() -> TestResult {
  let glyphs = glyph_pattern(1024);
  let uni = empty_lists(512);
  let built = ok_bytes(psf_build1(&glyphs, 2, &uni));
  var ok = built.len() == 1028;
  if rd8(&built, 2) != 1 { ok = false; }
  if rd8(&built, 3) != 2 { ok = false; }
  let f = ok_font(psf_parse(&built));
  if psf_charcount(&f) != 512 { ok = false; }
  if psf_charsize(&f) != 2 { ok = false; }
  if psf_height(&f) != 2 { ok = false; }
  if !bytes_equal(ok_bytes(psf_glyph_bytes(&built, &f, 511)), hb("feff")) { ok = false; }
  let back = glyphs_of(&built, &f);
  let uni2 = empty_lists(512);
  if !bytes_equal(ok_bytes(psf_build1(&back, 2, &uni2)), built) { ok = false; }
  return assert(ok, "psf_build1 picks 512 glyphs from the buffer length and round-trips");
}

fn t12() -> TestResult {
  let glyphs = glyph_pattern(1024);
  let uni = spec_psf1_256_small();
  let built = ok_bytes(psf_build1(&glyphs, 4, &uni));
  var ok = built.len() == 1546;
  if rd8(&built, 2) != 2 { ok = false; }
  if rd16le(&built, 1028) != 65 { ok = false; }
  if rd16le(&built, 1030) != 65535 { ok = false; }
  if rd16le(&built, 1032) != 65535 { ok = false; }
  if rd16le(&built, 1034) != 66 { ok = false; }
  if rd16le(&built, 1036) != 67 { ok = false; }
  if rd16le(&built, 1038) != 65535 { ok = false; }
  if rd16le(&built, 1544) != 65535 { ok = false; }
  let f = ok_font(psf_parse(&built));
  if !psf_has_unicode(&f) { ok = false; }
  if psf_unicode_count(&f, 0) != 1 { ok = false; }
  if psf_unicode_at(&f, 0, 0) != 65 { ok = false; }
  if psf_unicode_count(&f, 1) != 0 { ok = false; }
  if psf_unicode_count(&f, 2) != 2 { ok = false; }
  if psf_unicode_at(&f, 2, 1) != 67 { ok = false; }
  if psf_char_for_unicode(&f, 67) != 2 { ok = false; }
  if psf_unicode_count(&f, 3) != 0 { ok = false; }
  let back = glyphs_of(&built, &f);
  let uni2 = uni_of(&f);
  let rebuilt = ok_bytes(psf_build1(&back, 4, &uni2));
  if !bytes_equal(rebuilt, built) { ok = false; }
  return assert(ok, "psf_build1 emits the unicode table with terminators and round-trips");
}

fn t13() -> TestResult {
  let glyphs = glyph_pattern(1024);
  let uni = empty_lists(256);
  var ok = err_bytes_is(psf_build1(&glyphs, 0, &uni), "psf: invalid charsize");
  if !err_bytes_is(psf_build1(&glyphs, 33, &uni), "psf: invalid charsize") { ok = false; }
  let badlen = glyph_pattern(100);
  if !err_bytes_is(psf_build1(&badlen, 4, &uni), "psf: bad glyph byte count") { ok = false; }
  let short_uni = empty_lists(255);
  if !err_bytes_is(psf_build1(&glyphs, 4, &short_uni), "psf: unicode entry count mismatch") { ok = false; }
  let bad_cp = spec_one(256, 65535);
  if !err_bytes_is(psf_build1(&glyphs, 4, &bad_cp), "psf: invalid codepoint") { ok = false; }
  let neg_cp = spec_one(256, -1);
  if !err_bytes_is(psf_build1(&glyphs, 4, &neg_cp), "psf: invalid codepoint") { ok = false; }
  let top_cp = spec_one(256, 65534);
  let built = ok_bytes(psf_build1(&glyphs, 4, &top_cp));
  let f = ok_font(psf_parse(&built));
  if psf_unicode_at(&f, 0, 0) != 65534 { ok = false; }
  return assert(ok, "psf_build1 validates charsize, glyph count, unicode count and codepoints");
}

fn t14() -> TestResult {
  let glyphs = glyph_pattern(32);
  let uni = empty_lists(4);
  let built = ok_bytes(psf_build2(&glyphs, 8, 16, 8, &uni));
  var ok = built.len() == 64;
  if rd8(&built, 0) != 114 { ok = false; }
  if rd8(&built, 1) != 181 { ok = false; }
  if rd8(&built, 2) != 74 { ok = false; }
  if rd8(&built, 3) != 134 { ok = false; }
  if rd32le(&built, 4) != 0 { ok = false; }
  if rd32le(&built, 8) != 32 { ok = false; }
  if rd32le(&built, 12) != 0 { ok = false; }
  if rd32le(&built, 16) != 4 { ok = false; }
  if rd32le(&built, 20) != 8 { ok = false; }
  if rd32le(&built, 24) != 16 { ok = false; }
  if rd32le(&built, 28) != 8 { ok = false; }
  if rd8(&built, 32) != 0 { ok = false; }
  if rd8(&built, 63) != 31 { ok = false; }
  let f = ok_font(psf_parse(&built));
  if psf_version(&f) != 2 { ok = false; }
  if psf_charcount(&f) != 4 { ok = false; }
  if psf_charsize(&f) != 8 { ok = false; }
  if psf_height(&f) != 16 { ok = false; }
  if psf_width(&f) != 8 { ok = false; }
  if psf_has_unicode(&f) { ok = false; }
  let back = glyphs_of(&built, &f);
  let uni2 = empty_lists(4);
  if !bytes_equal(back, glyphs) { ok = false; }
  if !bytes_equal(ok_bytes(psf_build2(&back, 8, 16, 8, &uni2)), built) { ok = false; }
  return assert(ok, "psf_build2 emits the canonical 32-byte little-endian header");
}

fn t15() -> TestResult {
  let glyphs = glyph_pattern(32);
  var spec = Vec[Int].new();
  spec.push(2); spec.push(65); spec.push(66);
  spec.push(0);
  spec.push(1); spec.push(67);
  spec.push(2); spec.push(68); spec.push(1000);
  let uni = make_uni(&spec);
  let built = ok_bytes(psf_build2(&glyphs, 8, 8, 8, &uni));
  var ok = built.len() == 82;
  if rd32le(&built, 12) != 1 { ok = false; }
  if rd16le(&built, 64) != 65 { ok = false; }
  if rd16le(&built, 66) != 66 { ok = false; }
  if rd16le(&built, 68) != 65535 { ok = false; }
  if rd16le(&built, 70) != 65535 { ok = false; }
  if rd16le(&built, 72) != 67 { ok = false; }
  if rd16le(&built, 74) != 65535 { ok = false; }
  if rd16le(&built, 76) != 68 { ok = false; }
  if rd16le(&built, 78) != 1000 { ok = false; }
  if rd16le(&built, 80) != 65535 { ok = false; }
  let f = ok_font(psf_parse(&built));
  if !psf_has_unicode(&f) { ok = false; }
  if psf_unicode_count(&f, 0) != 2 { ok = false; }
  if psf_unicode_count(&f, 1) != 0 { ok = false; }
  if psf_unicode_count(&f, 2) != 1 { ok = false; }
  if psf_unicode_count(&f, 3) != 2 { ok = false; }
  if psf_char_for_unicode(&f, 66) != 0 { ok = false; }
  if psf_char_for_unicode(&f, 1000) != 3 { ok = false; }
  let back = glyphs_of(&built, &f);
  let uni2 = uni_of(&f);
  let rebuilt = ok_bytes(psf_build2(&back, 8, 8, 8, &uni2));
  if !bytes_equal(rebuilt, built) { ok = false; }
  return assert(ok, "psf_build2 emits the unicode table and round-trips byte-exactly");
}

fn t16() -> TestResult {
  let glyphs = glyph_pattern(32);
  let uni = empty_lists(4);
  var ok = err_bytes_is(psf_build2(&glyphs, 0, 8, 8, &uni), "psf: invalid charsize");
  if !err_bytes_is(psf_build2(&glyphs, 257, 8, 8, &uni), "psf: invalid charsize") { ok = false; }
  if !err_bytes_is(psf_build2(&glyphs, 8, 0, 8, &uni), "psf: invalid height") { ok = false; }
  if !err_bytes_is(psf_build2(&glyphs, 8, 8, 0, &uni), "psf: invalid width") { ok = false; }
  if !err_bytes_is(psf_build2(&glyphs, 8, 8, 65, &uni), "psf: invalid width") { ok = false; }
  let odd = glyph_pattern(33);
  if !err_bytes_is(psf_build2(&odd, 8, 8, 8, &uni), "psf: bad glyph byte count") { ok = false; }
  let short_uni = empty_lists(3);
  if !err_bytes_is(psf_build2(&glyphs, 8, 8, 8, &short_uni), "psf: unicode entry count mismatch") { ok = false; }
  let bad_cp = spec_one(4, 70000);
  if !err_bytes_is(psf_build2(&glyphs, 8, 8, 8, &bad_cp), "psf: invalid codepoint") { ok = false; }
  let neg_cp = spec_one(4, -2);
  if !err_bytes_is(psf_build2(&glyphs, 8, 8, 8, &neg_cp), "psf: invalid codepoint") { ok = false; }
  return assert(ok, "psf_build2 validates charsize, height, width, glyph count and codepoints");
}

fn t17() -> TestResult {
  let src = psf1_hand(0, 4, 256);
  let f = ok_font(psf_parse(&src));
  var ok = err_bytes_is(psf_glyph_bytes(&src, &f, -1), "psf: index out of range");
  if !err_bytes_is(psf_glyph_bytes(&src, &f, 256), "psf: index out of range") { ok = false; }
  if !bytes_equal(ok_bytes(psf_glyph_bytes(&src, &f, 255)), hb("fcfdfeff")) { ok = false; }
  let short = slice(src, 0, 6);
  if !err_bytes_is(psf_glyph_bytes(&short, &f, 0), "psf: glyph data out of bounds") { ok = false; }
  if psf_unicode_count(&f, 0) != 0 { ok = false; }
  if psf_unicode_count(&f, -5) != -1 { ok = false; }
  if psf_unicode_at(&f, 0, 0) != -1 { ok = false; }
  if psf_unicode_at(&f, 0, -1) != -1 { ok = false; }
  if psf_char_for_unicode(&f, 0) != -1 { ok = false; }
  let uni = spec_one(256, 65);
  let withu = psf1_uni_hand(2, 4, 256, &uni);
  let f2 = ok_font(psf_parse(&withu));
  if psf_unicode_at(&f2, 0, 5) != -1 { ok = false; }
  if psf_unicode_at(&f2, 1, 0) != -1 { ok = false; }
  if psf_char_for_unicode(&f2, 64) != -1 { ok = false; }
  return assert(ok, "glyph copier and unicode accessors guard indexes, stale spans and absent tables");
}

fn t18() -> TestResult {
  var ok = err_font_is(psf_parse(&hb("")), "psf: truncated header");
  if !err_font_is(psf_parse(&hb("36")), "psf: truncated header") { ok = false; }
  if !err_font_is(psf_parse(&hb("3604")), "psf: truncated header") { ok = false; }
  if !err_font_is(psf_parse(&hb("72b54a")), "psf: truncated header") { ok = false; }
  if !err_font_is(psf_parse(&hb("dead")), "psf: truncated header") { ok = false; }
  if !err_font_is(psf_parse(&hb("72b54a86")), "psf: truncated header") { ok = false; }
  if !err_font_is(psf_parse(&hb("deadbeef")), "psf: bad signature") { ok = false; }
  if !err_font_is(psf_parse(&hb("72b54a87")), "psf: bad signature") { ok = false; }
  return assert(ok, "the magic dispatch distinguishes truncation from a bad signature");
}

fn t19() -> TestResult {
  let src = psf1_hand(2, 8, 256);
  var terminators = Vec[UInt8].new();
  var g = 0;
  while g < 256 {
    terminators.push(255 as UInt8);
    terminators.push(255 as UInt8);
    g = g + 1;
  }
  let allterm = extend(src, terminators);
  let f = ok_font(psf_parse(&allterm));
  var ok = psf_has_unicode(&f);
  if psf_unicode_count(&f, 0) != 0 { ok = false; }
  if psf_unicode_count(&f, 255) != 0 { ok = false; }
  if psf_unicode_at(&f, 0, 0) != -1 { ok = false; }
  if psf_char_for_unicode(&f, 0) != -1 { ok = false; }
  let glyphs = glyph_pattern(1024);
  let empties = empty_lists(256);
  let built = ok_bytes(psf_build1(&glyphs, 4, &empties));
  if rd8(&built, 2) != 0 { ok = false; }
  let f2 = ok_font(psf_parse(&built));
  if psf_has_unicode(&f2) { ok = false; }
  let two = psf2_hand(1, 2, 8, 8, 8);
  let terminators2 = hb("ffffffff");
  let allterm2 = extend(two, terminators2);
  let f3 = ok_font(psf_parse(&allterm2));
  if !psf_has_unicode(&f3) { ok = false; }
  if psf_unicode_count(&f3, 0) != 0 { ok = false; }
  return assert(ok, "all-terminator tables parse, and the builder collapses all-empty lists");
}

fn t20() -> TestResult {
  let one = psf1_hand(0, 1, 256);
  let f1 = ok_font(psf_parse(&one));
  var ok = psf_charsize(&f1) == 1;
  if psf_height(&f1) != 1 { ok = false; }
  if psf_glyph_span(&f1, 255) != 1 { ok = false; }
  if !bytes_equal(ok_bytes(psf_glyph_bytes(&one, &f1, 255)), hb("ff")) { ok = false; }
  let big = psf1_hand(0, 32, 256);
  let f2 = ok_font(psf_parse(&big));
  if psf_charsize(&f2) != 32 { ok = false; }
  if psf_height(&f2) != 32 { ok = false; }
  if psf_glyph_span(&f2, 255) != 32 { ok = false; }
  let uni = spec_psf1_512();
  let src = psf1_uni_hand(3, 1, 512, &uni);
  let f3 = ok_font(psf_parse(&src));
  if psf_charcount(&f3) != 512 { ok = false; }
  if psf_charsize(&f3) != 1 { ok = false; }
  if !psf_has_unicode(&f3) { ok = false; }
  if rd8(&src, 2) != 3 { ok = false; }
  if psf_unicode_count(&f3, 511) != 1 { ok = false; }
  if psf_unicode_at(&f3, 511, 0) != 255 { ok = false; }
  if psf_char_for_unicode(&f3, 255) != 255 { ok = false; }
  let glyphs = glyph_pattern(512);
  let built = ok_bytes(psf_build1(&glyphs, 1, &uni));
  let f4 = ok_font(psf_parse(&built));
  if psf_charcount(&f4) != 512 { ok = false; }
  if rd8(&built, 2) != 3 { ok = false; }
  let back = glyphs_of(&built, &f4);
  let uni2 = uni_of(&f4);
  if !bytes_equal(ok_bytes(psf_build1(&back, 1, &uni2)), built) { ok = false; }
  return assert(ok, "charsize 1 and 32 parse and a 512-glyph unicode font round-trips");
}

fn main() -> Int {
  io.println("=== xiom.psf conformance tests ===");
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
    io.println("xiom.psf: all tests passed");
  } else {
    io.println("xiom.psf: tests failed");
  }
  return failed;
}
