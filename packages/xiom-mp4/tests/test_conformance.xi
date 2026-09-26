// XIOM -- xiom.mp4 conformance tests (33 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Covers the documented API against synthetic byte buffers built in-test
// (no external data files):
//   * box framing: 32-bit size, 64-bit largesize, size == 0 to end of
//     context, uuid user type hex, free/skip/wide leaves;
//   * the recursive tree walk (depths, parents, container flags, indented
//     tree text) over moov/trak/mdia/minf/stbl/dinf/edts;
//   * ftyp major/minor/compatible brands;
//   * mvhd (v0 and v1), tkhd (track id, duration, 16.16 width/height
//     rounded), mdhd (timescale/duration/language), hdlr handlers, stsd
//     sample-entry fourccs and visual dimensions, elst counts, stco/co64
//     chunk counts, stsz sample counts;
//   * fragmented (moof) detection and moov-at-end layout detection;
//   * the malformed-input catalog: short buffer, truncated header, size
//     below 8, size beyond the buffer, child overrunning its parent,
//     nesting depth over the 32 limit, truncated largesize, largesize
//     below the header, truncated uuid user type, ftyp/mvhd payload
//     errors, mdhd language, stco/co64/stsz entry overflow and stsd
//     entry overrun, non-printable box type.
//
// Harness style mirrors xiom.gguf: one fn tN() -> Int per check, called
// directly from main; main prints [PASS]/[FAIL] and returns the failure
// count. Str payloads are compared with str_compare and every Vec element
// read is bound to a typed local.

module mp4_tests
use xiom.io; use xiom.test;
use xiom.string; use xiom.string.compare;
use xiom.mp4;

// --------------------------------------------------
//  Harness helpers
// --------------------------------------------------

fn report(passed: Bool, name: Str) -> Int {
  if passed {
    io.println("  [PASS] " + name);
    return 0;
  }
  io.println("  [FAIL] " + name);
  return 1;
}

fn str_eq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn expect_file_err(r: Result[Mp4File, Str], want: Str, name: Str) -> Int {
  if r.is_ok {
    return report(false, name + " (expected Err)");
  }
  let got: Str = r.error;
  if !str_eq(got, want) {
    return report(false, name + " (got: " + got + ")");
  }
  return report(true, name);
}

// True when `needle` occurs in `hay` (hand rolled; avoids an extra import).
fn contains(hay: Str, needle: Str) -> Bool {
  let hn = string.str_len(hay);
  let nn = string.str_len(needle);
  if nn == 0 {
    return true;
  }
  if nn > hn {
    return false;
  }
  var i = 0;
  while i + nn <= hn {
    let part = string.str_slice(hay, i, i + nn);
    if str_eq(part, needle) {
      return true;
    }
    i = i + 1;
  }
  return false;
}

// --------------------------------------------------
//  Fixture builders (big-endian)
// --------------------------------------------------

fn push_u8(v: &mut Vec[UInt8], x: Int) {
  v.push(((x & 0xFF) as UInt8));
}

fn push_u16(v: &mut Vec[UInt8], x: Int) {
  push_u8(v, x / 256);
  push_u8(v, x % 256);
}

fn push_u32(v: &mut Vec[UInt8], x: Int) {
  push_u8(v, x / 16777216);
  push_u8(v, (x / 65536) % 256);
  push_u8(v, (x / 256) % 256);
  push_u8(v, x % 256);
}

fn push_u64(v: &mut Vec[UInt8], x: Int) {
  push_u32(v, x / 4294967296);
  push_u32(v, x % 4294967296);
}

fn push_ascii(v: &mut Vec[UInt8], s: Str) {
  var i = 0;
  let n = string.str_len(s);
  while i < n {
    let raw: UInt8 = string.byte_at(s, i);
    v.push(raw);
    i = i + 1;
  }
}

fn zero_n(v: &mut Vec[UInt8], n: Int) {
  var i = 0;
  while i < n {
    v.push((0 as UInt8));
    i = i + 1;
  }
}

fn patch_u32(v: &mut Vec[UInt8], pos: Int, x: Int) {
  v[pos] = (((x / 16777216) % 256) as UInt8);
  v[pos + 1] = (((x / 65536) % 256) as UInt8);
  v[pos + 2] = (((x / 256) % 256) as UInt8);
  v[pos + 3] = ((x % 256) as UInt8);
}

// Open a box: placeholder size plus four-character type. Close with
// end_box, which patches the size.
fn add_box(v: &mut Vec[UInt8], tag: Str) -> Int {
  let start = v.len();
  push_u32(v, 0);
  push_ascii(v, tag);
  return start;
}

fn end_box(v: &mut Vec[UInt8], start: Int) {
  patch_u32(v, start, v.len() - start);
}

fn copy_into(dst: &mut Vec[UInt8], src: &Vec[UInt8]) {
  var i = 0;
  let n = src.len();
  while i < n {
    let raw: UInt8 = src[i];
    dst.push(raw);
    i = i + 1;
  }
}

// Box with a declared 64-bit largesize (size field == 1).
fn add_box64(v: &mut Vec[UInt8], tag: Str, payload: Int) -> Int {
  let start = v.len();
  push_u32(v, 1);
  push_ascii(v, tag);
  push_u64(v, 16 + payload);
  zero_n(v, payload);
  return start;
}

// Box whose size field is 0 (extends to the end of the file).
fn add_box_to_end(v: &mut Vec[UInt8], tag: Str, payload: Int) -> Int {
  let start = v.len();
  push_u32(v, 0);
  push_ascii(v, tag);
  zero_n(v, payload);
  return start;
}

fn add_mdat(v: &mut Vec[UInt8], payload: Int) -> Int {
  let start = add_box(v, "mdat");
  zero_n(v, payload);
  end_box(v, start);
  return start;
}

fn add_free_like(v: &mut Vec[UInt8], tag: Str, payload: Int) -> Int {
  let start = add_box(v, tag);
  zero_n(v, payload);
  end_box(v, start);
  return start;
}

// uuid box: 4 size, "uuid", 16 user-type bytes 00..0f, payload, patched.
fn add_uuid_box(v: &mut Vec[UInt8], payload: Int) -> Int {
  let start = add_box(v, "uuid");
  var i = 0;
  while i < 16 {
    v.push((i as UInt8));
    i = i + 1;
  }
  zero_n(v, payload);
  end_box(v, start);
  return start;
}

// Packed 15-bit mdhd language (three 5-bit letters, 1 = 'a').
fn pack_lang(c1: Int, c2: Int, c3: Int) -> Int {
  return c1 * 1024 + c2 * 32 + c3;
}

fn add_mvhd_v0(v: &mut Vec[UInt8], timescale: Int, duration: Int) -> Int {
  let start = add_box(v, "mvhd");
  push_u32(v, 0);
  push_u32(v, 0);
  push_u32(v, 0);
  push_u32(v, timescale);
  push_u32(v, duration);
  push_u32(v, 65536);
  push_u16(v, 256);
  push_u16(v, 0);
  zero_n(v, 8);
  zero_n(v, 36);
  zero_n(v, 24);
  push_u32(v, 2);
  end_box(v, start);
  return start;
}

fn add_mvhd_v1(v: &mut Vec[UInt8], timescale: Int, duration: Int) -> Int {
  let start = add_box(v, "mvhd");
  push_u32(v, 16777216);
  push_u32(v, 0);
  push_u32(v, 0);
  push_u32(v, 0);
  push_u32(v, 0);
  push_u32(v, timescale);
  push_u32(v, duration / 4294967296);
  push_u32(v, duration % 4294967296);
  push_u32(v, 65536);
  push_u16(v, 256);
  push_u16(v, 0);
  zero_n(v, 8);
  zero_n(v, 36);
  zero_n(v, 24);
  push_u32(v, 2);
  end_box(v, start);
  return start;
}

fn add_tkhd_v0(v: &mut Vec[UInt8], track_id: Int, duration: Int, w_fixed: Int, h_fixed: Int) -> Int {
  let start = add_box(v, "tkhd");
  push_u32(v, 7);
  push_u32(v, 0);
  push_u32(v, 0);
  push_u32(v, track_id);
  push_u32(v, 0);
  push_u32(v, duration);
  zero_n(v, 8);
  push_u16(v, 0);
  push_u16(v, 0);
  push_u16(v, 0);
  push_u16(v, 0);
  zero_n(v, 36);
  push_u32(v, w_fixed);
  push_u32(v, h_fixed);
  end_box(v, start);
  return start;
}

fn add_mdhd_v0(v: &mut Vec[UInt8], timescale: Int, duration: Int, lang: Int) -> Int {
  let start = add_box(v, "mdhd");
  push_u32(v, 0);
  push_u32(v, 0);
  push_u32(v, 0);
  push_u32(v, timescale);
  push_u32(v, duration);
  push_u16(v, lang);
  push_u16(v, 0);
  end_box(v, start);
  return start;
}

fn add_hdlr(v: &mut Vec[UInt8], handler: Str) -> Int {
  let start = add_box(v, "hdlr");
  push_u32(v, 0);
  push_u32(v, 0);
  push_ascii(v, handler);
  zero_n(v, 12);
  push_ascii(v, "Handler");
  push_u8(v, 0);
  end_box(v, start);
  return start;
}

fn add_video_entry(v: &mut Vec[UInt8], tag: Str, width: Int, height: Int) -> Int {
  let start = add_box(v, tag);
  zero_n(v, 6);
  push_u16(v, 1);
  push_u16(v, 0);
  push_u16(v, 0);
  zero_n(v, 12);
  push_u16(v, width);
  push_u16(v, height);
  push_u32(v, 4718592);
  push_u32(v, 4718592);
  zero_n(v, 4);
  push_u16(v, 1);
  zero_n(v, 32);
  push_u16(v, 24);
  push_u16(v, 65535);
  end_box(v, start);
  return start;
}

fn add_audio_entry(v: &mut Vec[UInt8], tag: Str) -> Int {
  let start = add_box(v, tag);
  zero_n(v, 6);
  push_u16(v, 1);
  zero_n(v, 8);
  push_u16(v, 2);
  push_u16(v, 16);
  push_u16(v, 0);
  push_u16(v, 0);
  push_u32(v, 2890137600);
  end_box(v, start);
  return start;
}

fn stsd_begin(v: &mut Vec[UInt8], declared: Int) -> Int {
  let start = add_box(v, "stsd");
  push_u32(v, 0);
  push_u32(v, declared);
  return start;
}

fn add_elst_v0(v: &mut Vec[UInt8], count: Int) -> Int {
  let start = add_box(v, "elst");
  push_u32(v, 0);
  push_u32(v, count);
  zero_n(v, count * 12);
  end_box(v, start);
  return start;
}

fn add_stco(v: &mut Vec[UInt8], count: Int) -> Int {
  let start = add_box(v, "stco");
  push_u32(v, 0);
  push_u32(v, count);
  var i = 0;
  while i < count {
    push_u32(v, 1000 + i * 8);
    i = i + 1;
  }
  end_box(v, start);
  return start;
}

fn add_co64(v: &mut Vec[UInt8], count: Int) -> Int {
  let start = add_box(v, "co64");
  push_u32(v, 0);
  push_u32(v, count);
  var i = 0;
  while i < count {
    push_u64(v, 1000 + i * 8);
    i = i + 1;
  }
  end_box(v, start);
  return start;
}

fn add_stsz(v: &mut Vec[UInt8], uniform: Int, count: Int) -> Int {
  let start = add_box(v, "stsz");
  push_u32(v, 0);
  push_u32(v, uniform);
  push_u32(v, count);
  if uniform == 0 {
    var i = 0;
    while i < count {
      push_u32(v, 512 + i);
      i = i + 1;
    }
  }
  end_box(v, start);
  return start;
}

fn add_mdia_hdlr(v: &mut Vec[UInt8], handler: Str) {
  let md = add_box(v, "mdia");
  add_hdlr(v, handler);
  end_box(v, md);
}

// Full movie: ftyp + moov{mvhd, trak{tkhd, edts{elst}, mdia{mdhd, hdlr,
// minf{dinf{dref}, stbl{stsd{avc1, mp4a}, stco, co64, stsz}}}}} + mdat.
fn full_movie() -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  let fs = add_box(&mut v, "ftyp");
  push_ascii(&mut v, "isom");
  push_u32(&mut v, 512);
  push_ascii(&mut v, "isom");
  push_ascii(&mut v, "iso2");
  push_ascii(&mut v, "avc1");
  push_ascii(&mut v, "mp41");
  end_box(&mut v, fs);
  let mo = add_box(&mut v, "moov");
  add_mvhd_v0(&mut v, 1000, 5000);
  let tr = add_box(&mut v, "trak");
  add_tkhd_v0(&mut v, 1, 5000, 41975808, 23592960);
  let ed = add_box(&mut v, "edts");
  add_elst_v0(&mut v, 2);
  end_box(&mut v, ed);
  let md = add_box(&mut v, "mdia");
  add_mdhd_v0(&mut v, 48000, 240000, pack_lang(5, 14, 7));
  add_hdlr(&mut v, "vide");
  let mi = add_box(&mut v, "minf");
  let di = add_box(&mut v, "dinf");
  let dr = add_box(&mut v, "dref");
  push_u32(&mut v, 0);
  push_u32(&mut v, 0);
  end_box(&mut v, dr);
  end_box(&mut v, di);
  let st = add_box(&mut v, "stbl");
  let sd = stsd_begin(&mut v, 2);
  add_video_entry(&mut v, "avc1", 640, 360);
  add_audio_entry(&mut v, "mp4a");
  end_box(&mut v, sd);
  add_stco(&mut v, 3);
  add_co64(&mut v, 2);
  add_stsz(&mut v, 0, 3);
  end_box(&mut v, st);
  end_box(&mut v, mi);
  end_box(&mut v, md);
  end_box(&mut v, tr);
  end_box(&mut v, mo);
  add_mdat(&mut v, 32);
  return v;
}

// `levels` nested moov boxes around a free leaf.
fn nested_containers(levels: Int) -> Vec[UInt8] {
  var cur = Vec[UInt8].new();
  let inner = add_box(&mut cur, "free");
  end_box(&mut cur, inner);
  var k = 0;
  while k < levels {
    var wrapped = Vec[UInt8].new();
    let s = add_box(&mut wrapped, "moov");
    copy_into(&mut wrapped, &cur);
    end_box(&mut wrapped, s);
    cur = wrapped;
    k = k + 1;
  }
  var out = Vec[UInt8].new();
  copy_into(&mut out, &cur);
  return out;
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

// Whole-file parse: ftyp first, moov before mdat, box tree recorded.
fn t1() -> Int {
  let buf = full_movie();
  let r = mp4_parse(&buf);
  if !r.is_ok {
    return report(false, "full movie parses");
  }
  let f = r.value;
  if mp4_ftyp_count(&f) != 1 {
    return report(false, "full movie: one ftyp");
  }
  if !mp4_has_ftyp(&f) {
    return report(false, "full movie: starts with ftyp");
  }
  if mp4_box_count(&f) < 15 {
    return report(false, "full movie: at least 15 boxes");
  }
  if mp4_moov_count(&f) != 1 {
    return report(false, "full movie: one moov");
  }
  if mp4_mdat_count(&f) != 1 {
    return report(false, "full movie: one mdat");
  }
  return report(true, "full movie parses (ftyp/moov/mdat)");
}

// ftyp: major brand, minor version, four compatible brands.
fn t2() -> Int {
  let buf = full_movie();
  let r = mp4_parse(&buf);
  if !r.is_ok {
    return report(false, "ftyp brands parse");
  }
  let f = r.value;
  let mr = mp4_ftyp_major(&f, 0);
  if !mr.is_ok {
    return report(false, "ftyp major present");
  }
  let major: Str = mr.value;
  if !str_eq(major, "isom") {
    return report(false, "ftyp major is isom");
  }
  if mp4_ftyp_minor(&f, 0) != 512 {
    return report(false, "ftyp minor is 512");
  }
  if mp4_ftyp_brand_count(&f, 0) != 4 {
    return report(false, "ftyp has 4 compatible brands");
  }
  let b0r = mp4_ftyp_brand(&f, 0, 0);
  let b3r = mp4_ftyp_brand(&f, 0, 3);
  if !b0r.is_ok || !b3r.is_ok {
    return report(false, "ftyp brand accessors");
  }
  let b0: Str = b0r.value;
  let b3: Str = b3r.value;
  return report(str_eq(b0, "isom") && str_eq(b3, "mp41"), "ftyp brand list isom..mp41");
}

// mvhd version 0: timescale and 32-bit duration.
fn t3() -> Int {
  let buf = full_movie();
  let r = mp4_parse(&buf);
  if !r.is_ok {
    return report(false, "mvhd v0 parses");
  }
  let f = r.value;
  if mp4_mvhd_count(&f) != 1 {
    return report(false, "mvhd v0: one box");
  }
  if mp4_mvhd_version(&f, 0) != 0 {
    return report(false, "mvhd v0: version 0");
  }
  if mp4_mvhd_timescale(&f, 0) != 1000 {
    return report(false, "mvhd v0: timescale 1000");
  }
  return report(mp4_mvhd_duration(&f, 0) == 5000, "mvhd v0: duration 5000");
}

// mvhd version 1: timescale and 64-bit duration.
fn t4() -> Int {
  var v = Vec[UInt8].new();
  let mo = add_box(&mut v, "moov");
  add_mvhd_v1(&mut v, 90000, 300000000);
  end_box(&mut v, mo);
  let r = mp4_parse(&v);
  if !r.is_ok {
    return report(false, "mvhd v1 parses");
  }
  let f = r.value;
  if mp4_mvhd_version(&f, 0) != 1 {
    return report(false, "mvhd v1: version 1");
  }
  if mp4_mvhd_timescale(&f, 0) != 90000 {
    return report(false, "mvhd v1: timescale 90000");
  }
  return report(mp4_mvhd_duration(&f, 0) == 300000000, "mvhd v1: duration 300000000");
}

// tkhd version 0: track id, duration, 16.16 width/height rounded.
fn t5() -> Int {
  let buf = full_movie();
  let r = mp4_parse(&buf);
  if !r.is_ok {
    return report(false, "tkhd v0 parses");
  }
  let f = r.value;
  if mp4_tkhd_count(&f) != 1 {
    return report(false, "tkhd v0: one box");
  }
  if mp4_tkhd_track_id(&f, 0) != 1 {
    return report(false, "tkhd v0: track id 1");
  }
  if mp4_tkhd_duration(&f, 0) != 5000 {
    return report(false, "tkhd v0: duration 5000");
  }
  if mp4_tkhd_width(&f, 0) != 641 {
    return report(false, "tkhd v0: 640.5 rounds to 641");
  }
  return report(mp4_tkhd_height(&f, 0) == 360, "tkhd v0: height 360");
}

// mdhd version 0: timescale, duration and packed language "eng".
fn t6() -> Int {
  let buf = full_movie();
  let r = mp4_parse(&buf);
  if !r.is_ok {
    return report(false, "mdhd v0 parses");
  }
  let f = r.value;
  if mp4_mdhd_count(&f) != 1 {
    return report(false, "mdhd v0: one box");
  }
  if mp4_mdhd_timescale(&f, 0) != 48000 {
    return report(false, "mdhd v0: timescale 48000");
  }
  if mp4_mdhd_duration(&f, 0) != 240000 {
    return report(false, "mdhd v0: duration 240000");
  }
  let lr = mp4_mdhd_language(&f, 0);
  if !lr.is_ok {
    return report(false, "mdhd v0: language present");
  }
  let lang: Str = lr.value;
  return report(str_eq(lang, "eng"), "mdhd v0: language eng");
}

// hdlr: three handler types in stsd-like mdia wrappers.
fn t7() -> Int {
  var v = Vec[UInt8].new();
  let fs = add_box(&mut v, "ftyp");
  push_ascii(&mut v, "isom");
  push_u32(&mut v, 0);
  end_box(&mut v, fs);
  let mo = add_box(&mut v, "moov");
  add_mdia_hdlr(&mut v, "vide");
  add_mdia_hdlr(&mut v, "soun");
  add_mdia_hdlr(&mut v, "text");
  end_box(&mut v, mo);
  let r = mp4_parse(&v);
  if !r.is_ok {
    return report(false, "hdlr parses");
  }
  let f = r.value;
  if mp4_hdlr_count(&f) != 3 {
    return report(false, "hdlr: three handlers");
  }
  let h0r = mp4_hdlr_handler(&f, 0);
  let h1r = mp4_hdlr_handler(&f, 1);
  let h2r = mp4_hdlr_handler(&f, 2);
  if !h0r.is_ok || !h1r.is_ok || !h2r.is_ok {
    return report(false, "hdlr: handlers present");
  }
  let h0: Str = h0r.value;
  let h1: Str = h1r.value;
  let h2: Str = h2r.value;
  return report(str_eq(h0, "vide") && str_eq(h1, "soun") && str_eq(h2, "text"), "hdlr: vide/soun/text");
}

// stsd: declared count, sample-entry fourccs and visual dimensions.
fn t8() -> Int {
  let buf = full_movie();
  let r = mp4_parse(&buf);
  if !r.is_ok {
    return report(false, "stsd parses");
  }
  let f = r.value;
  if mp4_stsd_count(&f) != 1 {
    return report(false, "stsd: one box");
  }
  if mp4_stsd_entry_count(&f, 0) != 2 {
    return report(false, "stsd: declared entry count 2");
  }
  if mp4_sample_entry_count(&f) != 2 {
    return report(false, "stsd: two sample entries");
  }
  let e0r = mp4_sample_entry_fourcc(&f, 0);
  let e1r = mp4_sample_entry_fourcc(&f, 1);
  if !e0r.is_ok || !e1r.is_ok {
    return report(false, "stsd: entry fourccs present");
  }
  let e0: Str = e0r.value;
  let e1: Str = e1r.value;
  if !str_eq(e0, "avc1") || !str_eq(e1, "mp4a") {
    return report(false, "stsd: avc1 then mp4a");
  }
  if mp4_sample_entry_width(&f, 0) != 640 {
    return report(false, "stsd: avc1 width 640");
  }
  if mp4_sample_entry_height(&f, 0) != 360 {
    return report(false, "stsd: avc1 height 360");
  }
  if mp4_sample_entry_width(&f, 1) != -1 {
    return report(false, "stsd: mp4a has no visual width");
  }
  return report(mp4_sample_entry_stsd(&f, 0) == 0, "stsd: entry owner index 0");
}

// elst: one box with two entries.
fn t9() -> Int {
  let buf = full_movie();
  let r = mp4_parse(&buf);
  if !r.is_ok {
    return report(false, "elst parses");
  }
  let f = r.value;
  if mp4_elst_count(&f) != 1 {
    return report(false, "elst: one box");
  }
  if mp4_elst_version(&f, 0) != 0 {
    return report(false, "elst: version 0");
  }
  return report(mp4_elst_entry_count(&f, 0) == 2, "elst: two entries");
}

// stco and co64 chunk-offset counts and kinds.
fn t10() -> Int {
  let buf = full_movie();
  let r = mp4_parse(&buf);
  if !r.is_ok {
    return report(false, "stco/co64 parse");
  }
  let f = r.value;
  if mp4_chunk_offset_table_count(&f) != 2 {
    return report(false, "stco/co64: two tables");
  }
  if mp4_chunk_offset_kind(&f, 0) != 0 {
    return report(false, "stco/co64: first is stco");
  }
  if mp4_chunk_offset_count(&f, 0) != 3 {
    return report(false, "stco/co64: stco count 3");
  }
  if mp4_chunk_offset_kind(&f, 1) != 1 {
    return report(false, "stco/co64: second is co64");
  }
  return report(mp4_chunk_offset_count(&f, 1) == 2, "stco/co64: co64 count 2");
}

// stsz: sample count and uniform size.
fn t11() -> Int {
  let buf = full_movie();
  let r = mp4_parse(&buf);
  if !r.is_ok {
    return report(false, "stsz parses");
  }
  let f = r.value;
  if mp4_stsz_count(&f) != 1 {
    return report(false, "stsz: one box");
  }
  if mp4_stsz_sample_count(&f, 0) != 3 {
    return report(false, "stsz: sample count 3");
  }
  return report(mp4_stsz_uniform_size(&f, 0) == 0, "stsz: uniform size 0");
}

// 64-bit box: size field 1, largesize includes the 16-byte header.
fn t12() -> Int {
  var v = Vec[UInt8].new();
  let fs = add_box(&mut v, "ftyp");
  push_ascii(&mut v, "isom");
  push_u32(&mut v, 0);
  push_ascii(&mut v, "mp41");
  end_box(&mut v, fs);
  add_box64(&mut v, "mdat", 10);
  let r = mp4_parse(&v);
  if !r.is_ok {
    return report(false, "64-bit mdat parses");
  }
  let f = r.value;
  let i = mp4_find_box(&f, "mdat");
  if i < 0 {
    return report(false, "64-bit mdat: found");
  }
  if mp4_box_header_size(&f, i) != 16 {
    return report(false, "64-bit mdat: header size 16");
  }
  if mp4_box_size(&f, i) != 26 {
    return report(false, "64-bit mdat: size 26");
  }
  return report(mp4_total_len(&f) == 46, "64-bit mdat: file length 46");
}

// size == 0 box extends to the end of the file.
fn t13() -> Int {
  var v = Vec[UInt8].new();
  let fs = add_box(&mut v, "ftyp");
  push_ascii(&mut v, "isom");
  push_u32(&mut v, 0);
  push_ascii(&mut v, "mp41");
  end_box(&mut v, fs);
  add_box_to_end(&mut v, "mdat", 16);
  let r = mp4_parse(&v);
  if !r.is_ok {
    return report(false, "size==0 mdat parses");
  }
  let f = r.value;
  let i = mp4_find_box(&f, "mdat");
  if i < 0 {
    return report(false, "size==0 mdat: found");
  }
  if mp4_box_offset(&f, i) != 20 {
    return report(false, "size==0 mdat: offset 20");
  }
  return report(mp4_box_size(&f, i) == 24, "size==0 mdat: size 24 to EOF");
}

// uuid box: 16-byte user type hex, header size 24.
fn t14() -> Int {
  var v = Vec[UInt8].new();
  let fs = add_box(&mut v, "ftyp");
  push_ascii(&mut v, "isom");
  push_u32(&mut v, 0);
  end_box(&mut v, fs);
  add_uuid_box(&mut v, 4);
  let r = mp4_parse(&v);
  if !r.is_ok {
    return report(false, "uuid box parses");
  }
  let f = r.value;
  let i = mp4_find_box(&f, "uuid");
  if i < 0 {
    return report(false, "uuid box: found");
  }
  if mp4_box_header_size(&f, i) != 24 {
    return report(false, "uuid box: header size 24");
  }
  let ur = mp4_box_uuid(&f, i);
  if !ur.is_ok {
    return report(false, "uuid box: user type present");
  }
  let uh: Str = ur.value;
  if !str_eq(uh, "000102030405060708090a0b0c0d0e0f") {
    return report(false, "uuid box: hex user type");
  }
  let fr = mp4_box_uuid(&f, 0);
  return report(!fr.is_ok, "uuid box: ftyp is not uuid");
}

// Tree walk: depths, parents, container flags and indented text.
fn t15() -> Int {
  let buf = full_movie();
  let r = mp4_parse(&buf);
  if !r.is_ok {
    return report(false, "tree walk parses");
  }
  let f = r.value;
  let stbl = mp4_find_box(&f, "stbl");
  if stbl < 0 {
    return report(false, "tree walk: stbl found");
  }
  if mp4_box_depth(&f, stbl) != 4 {
    return report(false, "tree walk: stbl depth 4");
  }
  let minf = mp4_find_box(&f, "minf");
  if mp4_box_parent(&f, stbl) != minf {
    return report(false, "tree walk: stbl parent is minf");
  }
  let mdia = mp4_find_box(&f, "mdia");
  if mp4_box_parent(&f, minf) != mdia {
    return report(false, "tree walk: minf parent is mdia");
  }
  if !mp4_box_is_container(&f, stbl) {
    return report(false, "tree walk: stbl is a container");
  }
  let trak = mp4_find_box(&f, "free_none");
  if trak != -1 {
    return report(false, "tree walk: missing type is -1");
  }
  let text = mp4_tree_text(&f);
  if !contains(text, "stbl") {
    return report(false, "tree text: lists stbl");
  }
  return report(contains(text, "        stbl"), "tree text: stbl indented 8 spaces");
}

// free / skip / wide are accepted as opaque leaves.
fn t16() -> Int {
  var v = Vec[UInt8].new();
  let fs = add_box(&mut v, "ftyp");
  push_ascii(&mut v, "isom");
  push_u32(&mut v, 0);
  end_box(&mut v, fs);
  add_free_like(&mut v, "free", 4);
  add_free_like(&mut v, "skip", 4);
  add_free_like(&mut v, "wide", 4);
  let r = mp4_parse(&v);
  if !r.is_ok {
    return report(false, "free/skip/wide parse");
  }
  let f = r.value;
  if mp4_box_count(&f) != 4 {
    return report(false, "free/skip/wide: four boxes");
  }
  if mp4_find_box(&f, "free") < 0 || mp4_find_box(&f, "skip") < 0 {
    return report(false, "free/skip/wide: free and skip found");
  }
  return report(mp4_find_box(&f, "wide") >= 0, "free/skip/wide: wide found");
}

// Fragmented file: two moof fragments around mdat boxes.
fn t17() -> Int {
  var v = Vec[UInt8].new();
  let fs = add_box(&mut v, "ftyp");
  push_ascii(&mut v, "isom");
  push_u32(&mut v, 0);
  push_ascii(&mut v, "iso5");
  end_box(&mut v, fs);
  add_free_like(&mut v, "moof", 4);
  add_mdat(&mut v, 4);
  add_free_like(&mut v, "moof", 4);
  add_mdat(&mut v, 4);
  let r = mp4_parse(&v);
  if !r.is_ok {
    return report(false, "fragmented file parses");
  }
  let f = r.value;
  if mp4_moof_count(&f) != 2 {
    return report(false, "fragmented: two moof boxes");
  }
  if mp4_mdat_count(&f) != 2 {
    return report(false, "fragmented: two mdat boxes");
  }
  if !mp4_is_fragmented(&f) {
    return report(false, "fragmented: is_fragmented true");
  }
  return report(mp4_moov_count(&f) == 0, "fragmented: no moov");
}

// moov-at-end layout: ftyp + mdat + moov.
fn t18() -> Int {
  var v = Vec[UInt8].new();
  let fs = add_box(&mut v, "ftyp");
  push_ascii(&mut v, "isom");
  push_u32(&mut v, 0);
  end_box(&mut v, fs);
  add_mdat(&mut v, 8);
  let mo = add_box(&mut v, "moov");
  add_mvhd_v0(&mut v, 1000, 2000);
  end_box(&mut v, mo);
  let r = mp4_parse(&v);
  if !r.is_ok {
    return report(false, "moov-at-end parses");
  }
  let f = r.value;
  if !mp4_has_mdat(&f) {
    return report(false, "moov-at-end: has mdat");
  }
  if !mp4_is_moov_at_end(&f) {
    return report(false, "moov-at-end: detected");
  }
  let buf2 = full_movie();
  let r2 = mp4_parse(&buf2);
  if !r2.is_ok {
    return report(false, "moov-at-end: control parses");
  }
  let f2 = r2.value;
  return report(!mp4_is_moov_at_end(&f2), "moov-at-end: false when moov first");
}

// Short buffer.
fn t19() -> Int {
  var v = Vec[UInt8].new();
  zero_n(&mut v, 4);
  let r = mp4_parse(&v);
  return expect_file_err(r, "mp4: buffer too small for box header", "short buffer rejected");
}

// Truncated box header (trailing 4 bytes after a valid box).
fn t20() -> Int {
  var v = Vec[UInt8].new();
  let fs = add_box(&mut v, "ftyp");
  push_ascii(&mut v, "isom");
  push_u32(&mut v, 0);
  end_box(&mut v, fs);
  zero_n(&mut v, 4);
  let r = mp4_parse(&v);
  return expect_file_err(r, "mp4: truncated box header", "truncated box header rejected");
}

// Declared size below 8.
fn t21() -> Int {
  var v = Vec[UInt8].new();
  push_u32(&mut v, 7);
  push_ascii(&mut v, "free");
  zero_n(&mut v, 8);
  let r = mp4_parse(&v);
  return expect_file_err(r, "mp4: box size below 8", "size below 8 rejected");
}

// Declared size beyond the buffer.
fn t22() -> Int {
  var v = Vec[UInt8].new();
  push_u32(&mut v, 100);
  push_ascii(&mut v, "mdat");
  zero_n(&mut v, 12);
  let r = mp4_parse(&v);
  return expect_file_err(r, "mp4: box extends beyond buffer", "size beyond buffer rejected");
}

// Child box overruns its parent container.
fn t23() -> Int {
  var v = Vec[UInt8].new();
  let mo = add_box(&mut v, "moov");
  let fr = add_box(&mut v, "free");
  patch_u32(&mut v, fr, 100);
  zero_n(&mut v, 4);
  patch_u32(&mut v, mo, 24);
  zero_n(&mut v, 180);
  let r = mp4_parse(&v);
  return expect_file_err(r, "mp4: box overruns parent container", "child overrun rejected");
}

// Nesting deeper than the 32-level limit.
fn t24() -> Int {
  let v = nested_containers(40);
  let r = mp4_parse(&v);
  return expect_file_err(r, "mp4: nesting depth exceeds limit", "depth over limit rejected");
}

// size == 1 without room for the 64-bit largesize.
fn t25() -> Int {
  var v = Vec[UInt8].new();
  push_u32(&mut v, 1);
  push_ascii(&mut v, "mdat");
  zero_n(&mut v, 4);
  let r = mp4_parse(&v);
  return expect_file_err(r, "mp4: truncated largesize", "truncated largesize rejected");
}

// largesize below the 16-byte header.
fn t26() -> Int {
  var v = Vec[UInt8].new();
  push_u32(&mut v, 1);
  push_ascii(&mut v, "mdat");
  push_u64(&mut v, 8);
  zero_n(&mut v, 16);
  let r = mp4_parse(&v);
  return expect_file_err(r, "mp4: box size below header", "largesize below header rejected");
}

// uuid box without room for its 16-byte user type.
fn t27() -> Int {
  var v = Vec[UInt8].new();
  push_u32(&mut v, 24);
  push_ascii(&mut v, "uuid");
  zero_n(&mut v, 8);
  let r = mp4_parse(&v);
  return expect_file_err(r, "mp4: truncated uuid user type", "truncated uuid rejected");
}

// ftyp payload too short for major brand + minor version.
fn t28() -> Int {
  var v = Vec[UInt8].new();
  let fs = add_box(&mut v, "ftyp");
  push_u32(&mut v, 512);
  end_box(&mut v, fs);
  let r = mp4_parse(&v);
  return expect_file_err(r, "mp4: ftyp too short", "ftyp too short rejected");
}

// mvhd payload too short for its version-0 fields.
fn t29() -> Int {
  var v = Vec[UInt8].new();
  let m = add_box(&mut v, "mvhd");
  push_u32(&mut v, 0);
  zero_n(&mut v, 8);
  end_box(&mut v, m);
  let r = mp4_parse(&v);
  return expect_file_err(r, "mp4: mvhd too short", "short mvhd rejected");
}

// mdhd language with an out-of-range code point.
fn t30() -> Int {
  var v = Vec[UInt8].new();
  let m = add_box(&mut v, "moov");
  add_mdhd_v0(&mut v, 48000, 1000, 0);
  end_box(&mut v, m);
  let r = mp4_parse(&v);
  return expect_file_err(r, "mp4: mdhd bad language", "bad mdhd language rejected");
}

// stco declared entry count exceeds the payload.
fn t31() -> Int {
  var v = Vec[UInt8].new();
  let s = add_box(&mut v, "stco");
  push_u32(&mut v, 0);
  push_u32(&mut v, 100);
  zero_n(&mut v, 4);
  end_box(&mut v, s);
  let r = mp4_parse(&v);
  return expect_file_err(r, "mp4: stco entries exceed box", "stco overflow rejected");
}

// stsd entry size overruns the stsd box.
fn t32() -> Int {
  var v = Vec[UInt8].new();
  let s = stsd_begin(&mut v, 1);
  let e = add_box(&mut v, "mp4a");
  zero_n(&mut v, 4);
  patch_u32(&mut v, e, 500);
  end_box(&mut v, s);
  let r = mp4_parse(&v);
  return expect_file_err(r, "mp4: stsd entry overruns stsd box", "stsd entry overrun rejected");
}

// Non-printable four character type.
fn t33() -> Int {
  var v = Vec[UInt8].new();
  push_u32(&mut v, 8);
  push_u8(&mut v, 0);
  push_u8(&mut v, 1);
  push_u8(&mut v, 2);
  push_u8(&mut v, 3);
  let r = mp4_parse(&v);
  return expect_file_err(r, "mp4: non-printable box type", "non-printable type rejected");
}

fn main() -> Int {
  io.println("=== xiom.mp4 conformance tests ===");
  var failed = 0;
  failed = failed + t1();
  failed = failed + t2();
  failed = failed + t3();
  failed = failed + t4();
  failed = failed + t5();
  failed = failed + t6();
  failed = failed + t7();
  failed = failed + t8();
  failed = failed + t9();
  failed = failed + t10();
  failed = failed + t11();
  failed = failed + t12();
  failed = failed + t13();
  failed = failed + t14();
  failed = failed + t15();
  failed = failed + t16();
  failed = failed + t17();
  failed = failed + t18();
  failed = failed + t19();
  failed = failed + t20();
  failed = failed + t21();
  failed = failed + t22();
  failed = failed + t23();
  failed = failed + t24();
  failed = failed + t25();
  failed = failed + t26();
  failed = failed + t27();
  failed = failed + t28();
  failed = failed + t29();
  failed = failed + t30();
  failed = failed + t31();
  failed = failed + t32();
  failed = failed + t33();
  if failed == 0 {
    io.println("xiom.mp4: all tests passed");
  } else {
    io.println("xiom.mp4: tests failed");
  }
  return failed;
}
