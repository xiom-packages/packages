// XIOM -- xiom.flac conformance tests (18 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Covers the documented API: the "fLaC" marker, every metadata block type
// (STREAMINFO fields and MD5 hex, PADDING, APPLICATION, SEEKTABLE,
// VORBIS_COMMENT, CUESHEET, PICTURE), the metadata block index, the whole
// error catalog, the fixed-block-size frame header, variable block size and
// sample-rate/block-size extra fields, UTF-8 coded numbers (1-7 bytes),
// channel assignments and sample-size codes, the table/name helpers and
// CRC-8 vectors.
//
// Every fixture is a synthetic byte buffer built in-test; no external data
// files. Err strings and Str fields are compared with
// compare.str_compare (BUG 17 discipline: `==` on Str lowers to a pointer
// comparison). The CRC-8 is checked against pinned CRC-8/SMBUS constants
// and against an independent bit-serial reference written below.
//
// Pinned CRC-8 values (poly 0x07, init 0, MSB-first, no reflection, no
// final xor; cross-checked against the CRC-8/SMBUS known-answer test):
//   ""                                               -> 0
//   "123456789" (ASCII)                              -> 244 (0xF4)
//   one byte 0x00                                    -> 0
//   one byte 0xFF                                    -> 243 (0xF3)
//   one byte 0x80                                    -> 137 (0x89)
//   frame header FF F8 C9 08 00                      -> 149 (0x95)

module flac_tests
use xiom.io; use xiom.test;
use xiom.flac;
use xiom.string;
use xiom.string.compare;
use xiom.encoding.hex;

// --------------------------------------------------
//  Generic helpers
// --------------------------------------------------

fn hb(hexstr: Str) -> Vec[UInt8] {
  let r = hex.hex_decode(hexstr);
  if r.is_ok {
    return r.value;
  }
  return Vec[UInt8].new();
}

fn str_eq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn gb(data: &Vec[UInt8], pos: Int) -> Int {
  return (data[pos] as Int) & 0xFF;
}

fn repeat_byte(b: Int, n: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < n {
    v.push(b as UInt8);
    i = i + 1;
  }
  return v;
}

fn zeros(n: Int) -> Vec[UInt8] {
  return repeat_byte(0, n);
}

fn push_text(dst: &mut Vec[UInt8], s: Str) {
  var i = 0;
  while i < s.len() {
    dst.push(string.byte_at(s, i));
    i = i + 1;
  }
}

fn append_bytes(dst: &mut Vec[UInt8], src: &Vec[UInt8]) {
  var i = 0;
  while i < src.len() {
    dst.push(src[i]);
    i = i + 1;
  }
}

fn cat(a: Vec[UInt8], b: Vec[UInt8]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  append_bytes(&mut out, &a);
  append_bytes(&mut out, &b);
  return out;
}

fn set_byte(data: &Vec[UInt8], pos: Int, v: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < data.len() {
    if i == pos {
      out.push(v as UInt8);
    } else {
      out.push(data[i]);
    }
    i = i + 1;
  }
  return out;
}

// Byte `k` of `v` (0 = least significant) as UInt8; negative values yield
// their low two's-complement bytes (-1 -> 255 for every k).
fn byte_of(v: Int, k: Int) -> UInt8 {
  var q = v;
  var i = 0;
  while i < k {
    var r = q % 256;
    if r < 0 { r = r + 256; }
    q = (q - r) / 256;
    i = i + 1;
  }
  var b = q % 256;
  if b < 0 { b = b + 256; }
  return b as UInt8;
}

fn push_be16(dst: &mut Vec[UInt8], v: Int) {
  dst.push(byte_of(v, 1));
  dst.push(byte_of(v, 0));
}

fn push_be24(dst: &mut Vec[UInt8], v: Int) {
  dst.push(byte_of(v, 2));
  dst.push(byte_of(v, 1));
  dst.push(byte_of(v, 0));
}

fn push_be32(dst: &mut Vec[UInt8], v: Int) {
  dst.push(byte_of(v, 3));
  dst.push(byte_of(v, 2));
  dst.push(byte_of(v, 1));
  dst.push(byte_of(v, 0));
}

fn push_be64(dst: &mut Vec[UInt8], v: Int) {
  dst.push(byte_of(v, 7));
  dst.push(byte_of(v, 6));
  dst.push(byte_of(v, 5));
  dst.push(byte_of(v, 4));
  dst.push(byte_of(v, 3));
  dst.push(byte_of(v, 2));
  dst.push(byte_of(v, 1));
  dst.push(byte_of(v, 0));
}

fn push_le32(dst: &mut Vec[UInt8], v: Int) {
  dst.push(byte_of(v, 0));
  dst.push(byte_of(v, 1));
  dst.push(byte_of(v, 2));
  dst.push(byte_of(v, 3));
}

// Decode `d` at 0 and require value == `want` and lead-byte length
// == `len_want`.
fn chk_num(d: &Vec[UInt8], want: Int, len_want: Int) -> Bool {
  if flac_utf8_size(gb(d, 0)) != len_want {
    return false;
  }
  let r = flac_parse_utf8_number(d, 0);
  if !r.is_ok {
    return false;
  }
  if r.value != want {
    return false;
  }
  return true;
}

// --------------------------------------------------
//  Independent CRC-8 reference (bit-serial, different formulation)
// --------------------------------------------------

fn crc8_local_step(crc: Int, b: Int) -> Int {
  var c = crc ^ b;
  var k = 0;
  while k < 8 {
    let top = c / 128;
    c = (c % 128) * 2;
    if top == 1 {
      c = c ^ 7;
    }
    k = k + 1;
  }
  return c;
}

fn crc8_local_range(data: &Vec[UInt8], start: Int, size: Int) -> Int {
  var crc = 0;
  var i = 0;
  while i < size {
    crc = crc8_local_step(crc, gb(data, start + i));
    i = i + 1;
  }
  return crc;
}

// --------------------------------------------------
//  Result error helpers
// --------------------------------------------------

fn err_meta_is(r: Result[FlacMetadata, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return str_eq(r.error, want);
}

fn err_si_is(r: Result[FlacStreamInfo, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return str_eq(r.error, want);
}

fn err_num_is(r: Result[Int, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return str_eq(r.error, want);
}

fn err_frame_is(r: Result[FlacFrameHeader, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return str_eq(r.error, want);
}

fn err_vorbis_is(r: Result[FlacVorbisComment, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return str_eq(r.error, want);
}

fn err_picture_is(r: Result[FlacPicture, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return str_eq(r.error, want);
}

// --------------------------------------------------
//  Fixture builders (deliberately independent of src/flac.xi)
// --------------------------------------------------

fn marker() -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  v.push(102 as UInt8);
  v.push(76 as UInt8);
  v.push(97 as UInt8);
  v.push(67 as UInt8);
  return v;
}

// One metadata block: header byte (last*128 + type), 24-bit BE length,
// payload.
fn block(last: Int, btype: Int, payload: &Vec[UInt8]) -> Vec[UInt8] {
  var b = Vec[UInt8].new();
  b.push((last * 128 + btype) as UInt8);
  push_be24(&mut b, payload.len());
  append_bytes(&mut b, payload);
  return b;
}

fn md5_seq(base: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < 16 {
    v.push((base + i) as UInt8);
    i = i + 1;
  }
  return v;
}

// 34-byte STREAMINFO payload.
fn streaminfo_payload(minb: Int, maxb: Int, minf: Int, maxf: Int, sr: Int, ch: Int, bps: Int, total: Int, md5: &Vec[UInt8]) -> Vec[UInt8] {
  var p = Vec[UInt8].new();
  push_be16(&mut p, minb);
  push_be16(&mut p, maxb);
  push_be24(&mut p, minf);
  push_be24(&mut p, maxf);
  p.push((sr / 4096 % 256) as UInt8);
  p.push((sr / 16 % 256) as UInt8);
  p.push(((sr % 16) * 16 + (ch - 1) * 2 + (bps - 1) / 16) as UInt8);
  p.push((((bps - 1) % 16) * 16 + total / 4294967296 % 16) as UInt8);
  push_be32(&mut p, total % 4294967296);
  append_bytes(&mut p, md5);
  return p;
}

// The canonical test STREAMINFO: 4096-sample blocks, 44100 Hz stereo 16-bit,
// 12,345,678 samples, MD5 bytes 00..0f.
fn si_std() -> Vec[UInt8] {
  let md5 = md5_seq(0);
  return streaminfo_payload(4096, 4096, 1000, 2000, 44100, 2, 16, 12345678, &md5);
}

// marker + STREAMINFO (not last) + one last block of `btype`.
fn with_si(btype: Int, payload: &Vec[UInt8]) -> Vec[UInt8] {
  var s = marker();
  let si = si_std();
  append_bytes(&mut s, &block(0, 0, &si));
  append_bytes(&mut s, &block(1, btype, payload));
  return s;
}

fn app_payload(id: Str, data: &Vec[UInt8]) -> Vec[UInt8] {
  var p = Vec[UInt8].new();
  push_text(&mut p, id);
  append_bytes(&mut p, data);
  return p;
}

// One 18-byte SEEKTABLE entry. `sample`/`offset` of -1 produce the
// 0xFFFFFFFFFFFFFFFF placeholder.
fn seek_entry(sample: Int, offset: Int, frames: Int) -> Vec[UInt8] {
  var e = Vec[UInt8].new();
  push_be64(&mut e, sample);
  push_be64(&mut e, offset);
  push_be16(&mut e, frames);
  return e;
}

// VORBIS_COMMENT payload from a vendor string and a comment list.
fn vorbis_payload(vendor: Str, comments: &Vec[Str]) -> Vec[UInt8] {
  var p = Vec[UInt8].new();
  push_le32(&mut p, vendor.len());
  push_text(&mut p, vendor);
  push_le32(&mut p, comments.len());
  var i = 0;
  while i < comments.len() {
    let c: Str = comments[i];
    push_le32(&mut p, c.len());
    push_text(&mut p, c);
    i = i + 1;
  }
  return p;
}

// PICTURE payload.
fn picture_payload(ptype: Int, mime: Str, desc: Str, w: Int, h: Int, depth: Int, colors: Int, data: &Vec[UInt8]) -> Vec[UInt8] {
  var p = Vec[UInt8].new();
  push_be32(&mut p, ptype);
  push_be32(&mut p, mime.len());
  push_text(&mut p, mime);
  push_be32(&mut p, desc.len());
  push_text(&mut p, desc);
  push_be32(&mut p, w);
  push_be32(&mut p, h);
  push_be32(&mut p, depth);
  push_be32(&mut p, colors);
  push_be32(&mut p, data.len());
  append_bytes(&mut p, data);
  return p;
}

// Minimal valid CUESHEET: 396-byte fixed part, one track, one index point
// (444 bytes total).
fn cuesheet_min() -> Vec[UInt8] {
  var c = zeros(444);
  c = set_byte(&c, 395, 1);
  c = set_byte(&c, 404, 1);
  c = set_byte(&c, 431, 1);
  c = set_byte(&c, 440, 1);
  return c;
}

// One frame header from raw field bytes; the CRC byte is filled in with the
// independent reference implementation.
fn frame_bytes(b1: Int, b2: Int, b3: Int, num: &Vec[UInt8], extra: &Vec[UInt8]) -> Vec[UInt8] {
  var f = Vec[UInt8].new();
  f.push(255 as UInt8);
  f.push(b1 as UInt8);
  f.push(b2 as UInt8);
  f.push(b3 as UInt8);
  append_bytes(&mut f, num);
  append_bytes(&mut f, extra);
  var crc = 0;
  var i = 0;
  while i < f.len() {
    crc = crc8_local_step(crc, (f[i] as Int) & 0xFF);
    i = i + 1;
  }
  f.push(crc as UInt8);
  return f;
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  let md5 = md5_seq(0);
  let si = streaminfo_payload(4096, 4096, 1000, 2000, 44100, 2, 16, 12345678, &md5);
  var ok = true;
  if si.len() != 34 { return assert(false, "streaminfo: fields, MD5 hex, block index"); }
  let sr = flac_parse_streaminfo(&si);
  if !sr.is_ok { return assert(false, "streaminfo: fields, MD5 hex, block index"); }
  let info = sr.value;
  if info.min_block_size != 4096 { ok = false; }
  if info.max_block_size != 4096 { ok = false; }
  if info.min_frame_size != 1000 { ok = false; }
  if info.max_frame_size != 2000 { ok = false; }
  if info.sample_rate != 44100 { ok = false; }
  if info.channels != 2 { ok = false; }
  if info.bits_per_sample != 16 { ok = false; }
  if info.total_samples != 12345678 { ok = false; }
  if !str_eq(info.md5_hex, "000102030405060708090a0b0c0d0e0f") { ok = false; }
  var s = marker();
  append_bytes(&mut s, &block(1, 0, &si));
  let mr = flac_parse_metadata(&s);
  if !mr.is_ok { ok = false; } else {
    let m = mr.value;
    if !m.has_streaminfo { ok = false; }
    if m.metadata_size != 42 { ok = false; }
    if m.audio_offset != 42 { ok = false; }
    if flac_audio_offset(&m) != 42 { ok = false; }
    if flac_metadata_size(&m) != 42 { ok = false; }
    if flac_block_count(&m) != 1 { ok = false; }
    if flac_block_offset(&m, 0) != 4 { ok = false; }
    if flac_block_type(&m, 0) != 0 { ok = false; }
    if flac_block_length(&m, 0) != 34 { ok = false; }
    if m.sample_rate != 44100 { ok = false; }
    if m.channels != 2 { ok = false; }
    if m.bits_per_sample != 16 { ok = false; }
    if m.total_samples != 12345678 { ok = false; }
    if !str_eq(m.md5_hex, "000102030405060708090a0b0c0d0e0f") { ok = false; }
  }
  if !str_eq(flac_metadata_type_name(0), "STREAMINFO") { ok = false; }
  if !str_eq(flac_metadata_type_name(6), "PICTURE") { ok = false; }
  if !str_eq(flac_metadata_type_name(7), "") { ok = false; }
  return assert(ok, "streaminfo: fields, MD5 hex, block index");
}

fn t2() -> TestResult {
  let md5 = repeat_byte(255, 16);
  let si = streaminfo_payload(16, 65535, 0, 16777215, 192000, 8, 32, 68719476735, &md5);
  let mr = flac_parse_metadata(&cat(marker(), block(1, 0, &si)));
  var ok = true;
  if !mr.is_ok { return assert(false, "streaminfo edge values: u36 samples, 8 channels, 32 bps"); }
  let m = mr.value;
  if m.min_block_size != 16 { ok = false; }
  if m.max_block_size != 65535 { ok = false; }
  if m.min_frame_size != 0 { ok = false; }
  if m.max_frame_size != 16777215 { ok = false; }
  if m.sample_rate != 192000 { ok = false; }
  if m.channels != 8 { ok = false; }
  if m.bits_per_sample != 32 { ok = false; }
  if m.total_samples != 68719476735 { ok = false; }
  if !str_eq(m.md5_hex, "ffffffffffffffffffffffffffffffff") { ok = false; }
  let zr = flac_parse_streaminfo(&zeros(34));
  if !zr.is_ok { ok = false; } else {
    let z = zr.value;
    if z.sample_rate != 0 { ok = false; }
    if z.channels != 1 { ok = false; }
    if z.bits_per_sample != 1 { ok = false; }
    if z.total_samples != 0 { ok = false; }
    if !str_eq(z.md5_hex, "00000000000000000000000000000000") { ok = false; }
  }
  return assert(ok, "streaminfo edge values: u36 samples, 8 channels, 32 bps");
}

fn t3() -> TestResult {
  var ok = true;
  let empty = Vec[UInt8].new();
  if !err_meta_is(flac_parse_metadata(&empty), "flac: empty input") { ok = false; }
  if !err_meta_is(flac_parse_metadata(&hb("664C61")), "flac: truncated stream marker at 0") { ok = false; }
  if !err_meta_is(flac_parse_metadata(&hb("664C6144")), "flac: bad stream marker at 0") { ok = false; }
  if !err_meta_is(flac_parse_metadata(&hb("6C6143")), "flac: truncated stream marker at 0") { ok = false; }
  if !err_meta_is(flac_parse_metadata(&hb("664C6143")), "flac: missing last metadata block at 4") { ok = false; }
  if !err_meta_is(flac_parse_metadata(&hb("664C61438000")), "flac: truncated block header at 4") { ok = false; }
  if !err_meta_is(flac_parse_metadata(&hb("664C61438000002200000000000000000000")), "flac: block overrun at 4") { ok = false; }
  var s = marker();
  let si = si_std();
  append_bytes(&mut s, &block(0, 0, &si));
  if !err_meta_is(flac_parse_metadata(&s), "flac: missing last metadata block at 42") { ok = false; }
  if !err_meta_is(flac_parse_metadata(&cat(marker(), block(1, 1, &zeros(4)))), "flac: missing streaminfo at 4") { ok = false; }
  var d = marker();
  append_bytes(&mut d, &block(0, 0, &si));
  append_bytes(&mut d, &block(1, 0, &si));
  if !err_meta_is(flac_parse_metadata(&d), "flac: duplicate streaminfo at 42") { ok = false; }
  return assert(ok, "marker, truncation and ordering error catalog");
}

fn t4() -> TestResult {
  var ok = true;
  if !err_meta_is(flac_parse_metadata(&with_si(7, &zeros(0))), "flac: invalid block type at 42") { ok = false; }
  if !err_meta_is(flac_parse_metadata(&with_si(126, &zeros(0))), "flac: invalid block type at 42") { ok = false; }
  if !err_meta_is(flac_parse_metadata(&with_si(127, &zeros(0))), "flac: forbidden block type at 42") { ok = false; }
  if !err_meta_is(flac_parse_metadata(&cat(marker(), block(1, 0, &zeros(33)))), "flac: bad streaminfo length at 4") { ok = false; }
  if !err_si_is(flac_parse_streaminfo(&zeros(33)), "flac: bad streaminfo length at 0") { ok = false; }
  if !err_si_is(flac_parse_streaminfo(&zeros(35)), "flac: bad streaminfo length at 0") { ok = false; }
  if !err_meta_is(flac_parse_metadata(&cat(marker(), block(1, 4, &zeros(8)))), "flac: missing streaminfo at 4") { ok = false; }
  return assert(ok, "block type ranges and streaminfo length checks");
}

fn t5() -> TestResult {
  var s = marker();
  let si = si_std();
  append_bytes(&mut s, &block(0, 0, &si));
  append_bytes(&mut s, &block(0, 1, &zeros(10)));
  let app = app_payload("APPL", &hb("0102030405"));
  append_bytes(&mut s, &block(1, 2, &app));
  let mr = flac_parse_metadata(&s);
  var ok = true;
  if !mr.is_ok { return assert(false, "padding and application blocks"); }
  let m = mr.value;
  if flac_block_count(&m) != 3 { ok = false; }
  if flac_block_offset(&m, 1) != 42 { ok = false; }
  if flac_block_offset(&m, 2) != 56 { ok = false; }
  if flac_block_type(&m, 1) != 1 { ok = false; }
  if flac_block_type(&m, 2) != 2 { ok = false; }
  if flac_block_length(&m, 1) != 10 { ok = false; }
  if flac_block_length(&m, 2) != 9 { ok = false; }
  if flac_padding_bytes(&m) != 10 { ok = false; }
  if flac_application_count(&m) != 1 { ok = false; }
  if !str_eq(flac_application_id(&m, 0), "APPL") { ok = false; }
  if flac_application_data_length(&m, 0) != 5 { ok = false; }
  if m.audio_offset != 69 { ok = false; }
  if !err_meta_is(flac_parse_metadata(&with_si(2, &hb("010203"))), "flac: short application block at 42") { ok = false; }
  let appnul = cat(hb("41004243"), &hb("0000"));
  let m2r = flac_parse_metadata(&with_si(2, &appnul));
  if !m2r.is_ok { ok = false; } else {
    let m2 = m2r.value;
    if !str_eq(flac_application_id(&m2, 0), "A") { ok = false; }
    if flac_application_data_length(&m2, 0) != 2 { ok = false; }
  }
  return assert(ok, "padding and application blocks");
}

fn t6() -> TestResult {
  var payload = seek_entry(1000, 2000, 4096);
  let e2 = seek_entry(-1, -1, 0);
  append_bytes(&mut payload, &e2);
  let mr = flac_parse_metadata(&with_si(3, &payload));
  var ok = true;
  if !mr.is_ok { return assert(false, "seektable entries and placeholder clamping"); }
  let m = mr.value;
  if flac_seek_count(&m) != 2 { ok = false; }
  if flac_seek_sample(&m, 0) != 1000 { ok = false; }
  if flac_seek_offset(&m, 0) != 2000 { ok = false; }
  if flac_seek_frame_samples(&m, 0) != 4096 { ok = false; }
  if flac_seek_sample(&m, 1) != 9223372036854775807 { ok = false; }
  if flac_seek_offset(&m, 1) != 9223372036854775807 { ok = false; }
  if flac_seek_frame_samples(&m, 1) != 0 { ok = false; }
  if flac_seek_sample(&m, 2) != -1 { ok = false; }
  let er = flac_parse_metadata(&with_si(3, &zeros(0)));
  if !er.is_ok { ok = false; } else {
    let em = er.value;
    if flac_seek_count(&em) != 0 { ok = false; }
  }
  if !err_meta_is(flac_parse_metadata(&with_si(3, &zeros(19))), "flac: bad seektable length at 42") { ok = false; }
  return assert(ok, "seektable entries and placeholder clamping");
}

fn t7() -> TestResult {
  var cl = Vec[Str].new();
  cl.push("ARTIST=Someone");
  cl.push("TITLE=Track");
  let vp = vorbis_payload("xiom test", &cl);
  let mr = flac_parse_metadata(&with_si(4, &vp));
  var ok = true;
  if !mr.is_ok { return assert(false, "vorbis comment: vendor, comments, NUL and overrun"); }
  let m = mr.value;
  if !str_eq(flac_vendor(&m), "xiom test") { ok = false; }
  if flac_comment_count(&m) != 2 { ok = false; }
  if !str_eq(flac_comment(&m, 0), "ARTIST=Someone") { ok = false; }
  if !str_eq(flac_comment(&m, 1), "TITLE=Track") { ok = false; }
  let empty_cl = Vec[Str].new();
  let m0r = flac_parse_metadata(&with_si(4, &vorbis_payload("", &empty_cl)));
  if !m0r.is_ok { ok = false; } else {
    let m0 = m0r.value;
    if !str_eq(flac_vendor(&m0), "") { ok = false; }
    if flac_comment_count(&m0) != 0 { ok = false; }
  }
  var raw = Vec[UInt8].new();
  push_le32(&mut raw, 1);
  push_text(&mut raw, "V");
  push_le32(&mut raw, 1);
  push_le32(&mut raw, 5);
  push_text(&mut raw, "AB");
  raw.push(0 as UInt8);
  raw.push(67 as UInt8);
  raw.push(68 as UInt8);
  let mnr = flac_parse_metadata(&with_si(4, &raw));
  if !mnr.is_ok { ok = false; } else {
    let mn = mnr.value;
    if !str_eq(flac_vendor(&mn), "V") { ok = false; }
    if !str_eq(flac_comment(&mn, 0), "AB") { ok = false; }
  }
  var bad = Vec[UInt8].new();
  push_le32(&mut bad, 100);
  push_text(&mut bad, "V");
  if !err_meta_is(flac_parse_metadata(&with_si(4, &bad)), "flac: vorbis comment overrun at 42") { ok = false; }
  let vt = cat(vp, hb("00"));
  if !err_meta_is(flac_parse_metadata(&with_si(4, &vt)), "flac: vorbis comment overrun at 42") { ok = false; }
  return assert(ok, "vorbis comment: vendor, comments, NUL and overrun");
}

fn t8() -> TestResult {
  let data1 = hb("0102030405");
  let p1 = picture_payload(3, "image/png", "cover", 640, 480, 24, 0, &data1);
  let p2 = picture_payload(4, "image/jpeg", "", 1, 2, 8, 256, &zeros(0));
  var s = marker();
  let si = si_std();
  append_bytes(&mut s, &block(0, 0, &si));
  append_bytes(&mut s, &block(0, 6, &p1));
  append_bytes(&mut s, &block(1, 6, &p2));
  let mr = flac_parse_metadata(&s);
  var ok = true;
  if !mr.is_ok { return assert(false, "picture: fields, multiple pictures and overrun"); }
  let m = mr.value;
  if flac_picture_count(&m) != 2 { ok = false; }
  if flac_picture_type(&m, 0) != 3 { ok = false; }
  if !str_eq(flac_picture_mime(&m, 0), "image/png") { ok = false; }
  if !str_eq(flac_picture_description(&m, 0), "cover") { ok = false; }
  if flac_picture_width(&m, 0) != 640 { ok = false; }
  if flac_picture_height(&m, 0) != 480 { ok = false; }
  if flac_picture_depth(&m, 0) != 24 { ok = false; }
  if flac_picture_colors(&m, 0) != 0 { ok = false; }
  if flac_picture_data_length(&m, 0) != 5 { ok = false; }
  if flac_picture_type(&m, 1) != 4 { ok = false; }
  if !str_eq(flac_picture_mime(&m, 1), "image/jpeg") { ok = false; }
  if !str_eq(flac_picture_description(&m, 1), "") { ok = false; }
  if flac_picture_width(&m, 1) != 1 { ok = false; }
  if flac_picture_height(&m, 1) != 2 { ok = false; }
  if flac_picture_depth(&m, 1) != 8 { ok = false; }
  if flac_picture_colors(&m, 1) != 256 { ok = false; }
  if flac_picture_data_length(&m, 1) != 0 { ok = false; }
  if flac_picture_type(&m, 2) != -1 { ok = false; }
  if !str_eq(flac_picture_mime(&m, -1), "") { ok = false; }
  var badp = Vec[UInt8].new();
  push_be32(&mut badp, 3);
  push_be32(&mut badp, 1);
  push_text(&mut badp, "m");
  push_be32(&mut badp, 0);
  push_be32(&mut badp, 1);
  push_be32(&mut badp, 2);
  push_be32(&mut badp, 3);
  push_be32(&mut badp, 0);
  push_be32(&mut badp, 10);
  badp.push(9 as UInt8);
  if !err_meta_is(flac_parse_metadata(&with_si(6, &badp)), "flac: picture block overrun at 42") { ok = false; }
  let p1t = cat(p1, hb("00"));
  if !err_meta_is(flac_parse_metadata(&with_si(6, &p1t)), "flac: picture block overrun at 42") { ok = false; }
  if !err_meta_is(flac_parse_metadata(&with_si(6, &hb("0000000300000000"))), "flac: picture block overrun at 42") { ok = false; }
  return assert(ok, "picture: fields, multiple pictures and overrun");
}

fn t9() -> TestResult {
  let c = cuesheet_min();
  let mr = flac_parse_metadata(&with_si(5, &c));
  var ok = true;
  if !mr.is_ok { return assert(false, "cuesheet: length-checked walk"); }
  let m = mr.value;
  if flac_cuesheet_count(&m) != 1 { ok = false; }
  if flac_cuesheet_track_count(&m, 0) != 1 { ok = false; }
  if flac_cuesheet_length(&m, 0) != 444 { ok = false; }
  if flac_cuesheet_track_count(&m, 1) != -1 { ok = false; }
  if flac_cuesheet_length(&m, 1) != -1 { ok = false; }
  if !err_meta_is(flac_parse_metadata(&with_si(5, &zeros(395))), "flac: bad cuesheet length at 42") { ok = false; }
  var c2 = zeros(444);
  c2 = set_byte(&c2, 395, 1);
  c2 = set_byte(&c2, 404, 1);
  c2 = set_byte(&c2, 431, 2);
  if !err_meta_is(flac_parse_metadata(&with_si(5, &c2)), "flac: bad cuesheet length at 42") { ok = false; }
  let c3 = cat(c, hb("00"));
  if !err_meta_is(flac_parse_metadata(&with_si(5, &c3)), "flac: bad cuesheet length at 42") { ok = false; }
  return assert(ok, "cuesheet: length-checked walk");
}

fn t10() -> TestResult {
  var s = marker();
  let si = si_std();
  append_bytes(&mut s, &block(0, 0, &si));
  append_bytes(&mut s, &block(0, 1, &zeros(6)));
  append_bytes(&mut s, &block(0, 3, &seek_entry(1000, 2000, 4096)));
  var cl = Vec[Str].new();
  cl.push("K");
  append_bytes(&mut s, &block(0, 4, &vorbis_payload("V", &cl)));
  append_bytes(&mut s, &block(0, 6, &picture_payload(1, "a", "", 1, 1, 1, 1, &zeros(0))));
  append_bytes(&mut s, &block(1, 2, &app_payload("TEST", &zeros(0))));
  let mr = flac_parse_metadata(&s);
  var ok = true;
  if !mr.is_ok { return assert(false, "multi-block metadata index and offsets"); }
  let m = mr.value;
  if flac_block_count(&m) != 6 { ok = false; }
  if flac_block_type(&m, 0) != 0 { ok = false; }
  if flac_block_type(&m, 1) != 1 { ok = false; }
  if flac_block_type(&m, 2) != 3 { ok = false; }
  if flac_block_type(&m, 3) != 4 { ok = false; }
  if flac_block_type(&m, 4) != 6 { ok = false; }
  if flac_block_type(&m, 5) != 2 { ok = false; }
  if flac_block_offset(&m, 0) != 4 { ok = false; }
  if flac_block_offset(&m, 1) != 42 { ok = false; }
  if flac_block_offset(&m, 2) != 52 { ok = false; }
  if flac_block_offset(&m, 3) != 74 { ok = false; }
  if flac_block_offset(&m, 4) != 92 { ok = false; }
  if flac_block_offset(&m, 5) != 129 { ok = false; }
  if flac_block_length(&m, 0) != 34 { ok = false; }
  if flac_block_length(&m, 1) != 6 { ok = false; }
  if flac_block_length(&m, 2) != 18 { ok = false; }
  if flac_block_length(&m, 3) != 14 { ok = false; }
  if flac_block_length(&m, 4) != 33 { ok = false; }
  if flac_block_length(&m, 5) != 4 { ok = false; }
  if m.audio_offset != 137 { ok = false; }
  if flac_seek_count(&m) != 1 { ok = false; }
  if flac_seek_sample(&m, 0) != 1000 { ok = false; }
  if flac_seek_offset(&m, 0) != 2000 { ok = false; }
  if flac_seek_frame_samples(&m, 0) != 4096 { ok = false; }
  if !str_eq(flac_vendor(&m), "V") { ok = false; }
  if flac_comment_count(&m) != 1 { ok = false; }
  if !str_eq(flac_comment(&m, 0), "K") { ok = false; }
  if flac_picture_count(&m) != 1 { ok = false; }
  if flac_picture_type(&m, 0) != 1 { ok = false; }
  if flac_picture_width(&m, 0) != 1 { ok = false; }
  if flac_picture_depth(&m, 0) != 1 { ok = false; }
  if flac_picture_colors(&m, 0) != 1 { ok = false; }
  if flac_application_count(&m) != 1 { ok = false; }
  if !str_eq(flac_application_id(&m, 0), "TEST") { ok = false; }
  if flac_padding_bytes(&m) != 6 { ok = false; }
  return assert(ok, "multi-block metadata index and offsets");
}

fn t11() -> TestResult {
  let d = hb("FFF8C9080095");
  let pr = flac_parse_frame_header(&d, 0);
  var ok = true;
  if !pr.is_ok { return assert(false, "frame header: pinned fixed-blocksize vector and CRC"); }
  let h = pr.value;
  if h.blocking_strategy != 0 { ok = false; }
  if h.block_size_code != 12 { ok = false; }
  if h.sample_rate_code != 9 { ok = false; }
  if h.channel_assignment != 0 { ok = false; }
  if h.sample_size_code != 4 { ok = false; }
  if h.channels != 1 { ok = false; }
  if h.block_size != 4096 { ok = false; }
  if h.sample_rate != 44100 { ok = false; }
  if h.bits_per_sample != 16 { ok = false; }
  if h.number != 0 { ok = false; }
  if h.number_bytes != 1 { ok = false; }
  if h.crc8 != 149 { ok = false; }
  if !h.crc8_ok { ok = false; }
  if h.header_size != 6 { ok = false; }
  if flac_crc8(&d, 0, 5) != 149 { ok = false; }
  if crc8_local_range(&d, 0, 5) != 149 { ok = false; }
  if !str_eq(flac_blocking_strategy_name(0), "fixed") { ok = false; }
  if !str_eq(flac_blocking_strategy_name(1), "variable") { ok = false; }
  if !str_eq(flac_blocking_strategy_name(2), "") { ok = false; }
  if !err_frame_is(flac_parse_frame_header(&d, 1), "flac: bad sync at 1") { ok = false; }
  return assert(ok, "frame header: pinned fixed-blocksize vector and CRC");
}

fn t12() -> TestResult {
  var ok = true;
  let a = frame_bytes(249, 108, 172, &hb("E188B4"), &hb("C730"));
  let ar = flac_parse_frame_header(&a, 0);
  if !ar.is_ok { return assert(false, "frame header: variable strategy and extra fields"); }
  let ha = ar.value;
  if ha.blocking_strategy != 1 { ok = false; }
  if ha.block_size_code != 6 { ok = false; }
  if ha.sample_rate_code != 12 { ok = false; }
  if ha.channel_assignment != 10 { ok = false; }
  if ha.sample_size_code != 6 { ok = false; }
  if ha.channels != 2 { ok = false; }
  if ha.block_size != 200 { ok = false; }
  if ha.sample_rate != 48000 { ok = false; }
  if ha.bits_per_sample != 24 { ok = false; }
  if ha.number != 4660 { ok = false; }
  if ha.number_bytes != 3 { ok = false; }
  if ha.header_size != 10 { ok = false; }
  if !ha.crc8_ok { ok = false; }
  if !str_eq(flac_channel_assignment_name(10), "mid/side stereo") { ok = false; }
  let b = frame_bytes(248, 126, 128, &hb("05"), &hb("0FFF10E0"));
  let br = flac_parse_frame_header(&b, 0);
  if !br.is_ok { ok = false; } else {
    let hb2 = br.value;
    if hb2.blocking_strategy != 0 { ok = false; }
    if hb2.block_size != 4096 { ok = false; }
    if hb2.sample_rate != 43200 { ok = false; }
    if hb2.bits_per_sample != 0 { ok = false; }
    if hb2.channels != 2 { ok = false; }
    if hb2.number != 5 { ok = false; }
    if hb2.header_size != 10 { ok = false; }
    if !hb2.crc8_ok { ok = false; }
  }
  if !err_frame_is(flac_parse_frame_header(&hb("FFF87E80050F"), 0), "flac: truncated frame header at 0") { ok = false; }
  if !err_frame_is(flac_parse_frame_header(&hb("FFF8CC0800"), 0), "flac: truncated frame header at 0") { ok = false; }
  return assert(ok, "frame header: variable strategy and extra fields");
}

fn t13() -> TestResult {
  var ok = true;
  let v00 = hb("00");
  let v7f = hb("7F");
  let v80 = hb("C280");
  let v7ff = hb("DFBF");
  let v800 = hb("E0A080");
  let vffff = hb("EFBFBF");
  let v10000 = hb("F0908080");
  let v1fffff = hb("F7BFBFBF");
  let v200000 = hb("F888808080");
  let v3ffffff = hb("FBBFBFBFBF");
  let v4000000 = hb("FC8480808080");
  let v7fffffff = hb("FDBFBFBFBFBF");
  let v80000000 = hb("FE828080808080");
  let vfffffffff = hb("FEBFBFBFBFBFBF");
  if flac_utf8_size(0) != 1 { ok = false; }
  if flac_utf8_size(127) != 1 { ok = false; }
  if flac_utf8_size(128) != -1 { ok = false; }
  if flac_utf8_size(191) != -1 { ok = false; }
  if flac_utf8_size(192) != 2 { ok = false; }
  if flac_utf8_size(223) != 2 { ok = false; }
  if flac_utf8_size(224) != 3 { ok = false; }
  if flac_utf8_size(240) != 4 { ok = false; }
  if flac_utf8_size(248) != 5 { ok = false; }
  if flac_utf8_size(252) != 6 { ok = false; }
  if flac_utf8_size(254) != 7 { ok = false; }
  if flac_utf8_size(255) != -1 { ok = false; }
  if flac_utf8_size(256) != -1 { ok = false; }
  if flac_utf8_size(-1) != -1 { ok = false; }
  if !chk_num(&v00, 0, 1) { ok = false; }
  if !chk_num(&v7f, 127, 1) { ok = false; }
  if !chk_num(&v80, 128, 2) { ok = false; }
  if !chk_num(&v7ff, 2047, 2) { ok = false; }
  if !chk_num(&v800, 2048, 3) { ok = false; }
  if !chk_num(&vffff, 65535, 3) { ok = false; }
  if !chk_num(&v10000, 65536, 4) { ok = false; }
  if !chk_num(&v1fffff, 2097151, 4) { ok = false; }
  if !chk_num(&v200000, 2097152, 5) { ok = false; }
  if !chk_num(&v3ffffff, 67108863, 5) { ok = false; }
  if !chk_num(&v4000000, 67108864, 6) { ok = false; }
  if !chk_num(&v7fffffff, 2147483647, 6) { ok = false; }
  if !chk_num(&v80000000, 2147483648, 7) { ok = false; }
  if !chk_num(&vfffffffff, 68719476735, 7) { ok = false; }
  if !err_num_is(flac_parse_utf8_number(&hb("80"), 0), "flac: invalid utf8 number at 0") { ok = false; }
  if !err_num_is(flac_parse_utf8_number(&hb("BF"), 0), "flac: invalid utf8 number at 0") { ok = false; }
  if !err_num_is(flac_parse_utf8_number(&hb("FF"), 0), "flac: invalid utf8 number at 0") { ok = false; }
  if !err_num_is(flac_parse_utf8_number(&hb("C2"), 0), "flac: truncated utf8 number at 0") { ok = false; }
  if !err_num_is(flac_parse_utf8_number(&hb("C200"), 0), "flac: invalid utf8 number at 1") { ok = false; }
  if !err_num_is(flac_parse_utf8_number(&hb("C080"), 0), "flac: overlong utf8 number at 0") { ok = false; }
  if !err_num_is(flac_parse_utf8_number(&hb("C1BF"), 0), "flac: overlong utf8 number at 0") { ok = false; }
  if !err_num_is(flac_parse_utf8_number(&hb("E08080"), 0), "flac: overlong utf8 number at 0") { ok = false; }
  if !err_num_is(flac_parse_utf8_number(&hb("E09FBF"), 0), "flac: overlong utf8 number at 0") { ok = false; }
  let empty = Vec[UInt8].new();
  if !err_num_is(flac_parse_utf8_number(&empty, 0), "flac: truncated utf8 number at 0") { ok = false; }
  if !err_num_is(flac_parse_utf8_number(&hb("00"), -1), "flac: offset out of range") { ok = false; }
  if !err_num_is(flac_parse_utf8_number(&hb("00"), 1), "flac: truncated utf8 number at 1") { ok = false; }
  return assert(ok, "utf8 coded numbers: 1-7 bytes, overlong and invalid forms");
}

fn t14() -> TestResult {
  var ok = true;
  if flac_block_size_for_code(0) != 0 { ok = false; }
  if flac_block_size_for_code(1) != 192 { ok = false; }
  if flac_block_size_for_code(2) != 576 { ok = false; }
  if flac_block_size_for_code(3) != 1152 { ok = false; }
  if flac_block_size_for_code(4) != 2304 { ok = false; }
  if flac_block_size_for_code(5) != 4608 { ok = false; }
  if flac_block_size_for_code(6) != -1 { ok = false; }
  if flac_block_size_for_code(7) != -1 { ok = false; }
  if flac_block_size_for_code(8) != 256 { ok = false; }
  if flac_block_size_for_code(9) != 512 { ok = false; }
  if flac_block_size_for_code(10) != 1024 { ok = false; }
  if flac_block_size_for_code(11) != 2048 { ok = false; }
  if flac_block_size_for_code(12) != 4096 { ok = false; }
  if flac_block_size_for_code(13) != 8192 { ok = false; }
  if flac_block_size_for_code(14) != 16384 { ok = false; }
  if flac_block_size_for_code(15) != 32768 { ok = false; }
  if flac_block_size_for_code(16) != 0 { ok = false; }
  if flac_block_size_for_code(-1) != 0 { ok = false; }
  if flac_sample_rate_for_code(0) != 0 { ok = false; }
  if flac_sample_rate_for_code(1) != 88200 { ok = false; }
  if flac_sample_rate_for_code(2) != 176400 { ok = false; }
  if flac_sample_rate_for_code(3) != 192000 { ok = false; }
  if flac_sample_rate_for_code(4) != 8000 { ok = false; }
  if flac_sample_rate_for_code(5) != 16000 { ok = false; }
  if flac_sample_rate_for_code(6) != 22050 { ok = false; }
  if flac_sample_rate_for_code(7) != 24000 { ok = false; }
  if flac_sample_rate_for_code(8) != 32000 { ok = false; }
  if flac_sample_rate_for_code(9) != 44100 { ok = false; }
  if flac_sample_rate_for_code(10) != 48000 { ok = false; }
  if flac_sample_rate_for_code(11) != 96000 { ok = false; }
  if flac_sample_rate_for_code(12) != -1 { ok = false; }
  if flac_sample_rate_for_code(13) != -1 { ok = false; }
  if flac_sample_rate_for_code(14) != -1 { ok = false; }
  if flac_sample_rate_for_code(15) != -2 { ok = false; }
  if flac_sample_rate_for_code(16) != 0 { ok = false; }
  if flac_bits_per_sample_for_code(0) != 0 { ok = false; }
  if flac_bits_per_sample_for_code(1) != 8 { ok = false; }
  if flac_bits_per_sample_for_code(2) != 12 { ok = false; }
  if flac_bits_per_sample_for_code(3) != -1 { ok = false; }
  if flac_bits_per_sample_for_code(4) != 16 { ok = false; }
  if flac_bits_per_sample_for_code(5) != 20 { ok = false; }
  if flac_bits_per_sample_for_code(6) != 24 { ok = false; }
  if flac_bits_per_sample_for_code(7) != 32 { ok = false; }
  if flac_bits_per_sample_for_code(8) != -1 { ok = false; }
  var a = 0;
  while a <= 7 {
    if flac_channel_assignment_channels(a) != a + 1 { ok = false; }
    if !str_eq(flac_channel_assignment_name(a), "independent") { ok = false; }
    a = a + 1;
  }
  if flac_channel_assignment_channels(8) != 2 { ok = false; }
  if flac_channel_assignment_channels(9) != 2 { ok = false; }
  if flac_channel_assignment_channels(10) != 2 { ok = false; }
  if flac_channel_assignment_channels(11) != -1 { ok = false; }
  if flac_channel_assignment_channels(-1) != -1 { ok = false; }
  if !str_eq(flac_channel_assignment_name(8), "left/side stereo") { ok = false; }
  if !str_eq(flac_channel_assignment_name(9), "right/side stereo") { ok = false; }
  if !str_eq(flac_channel_assignment_name(10), "mid/side stereo") { ok = false; }
  if !str_eq(flac_channel_assignment_name(11), "") { ok = false; }
  if !str_eq(flac_metadata_type_name(1), "PADDING") { ok = false; }
  if !str_eq(flac_metadata_type_name(2), "APPLICATION") { ok = false; }
  if !str_eq(flac_metadata_type_name(3), "SEEKTABLE") { ok = false; }
  if !str_eq(flac_metadata_type_name(4), "VORBIS_COMMENT") { ok = false; }
  if !str_eq(flac_metadata_type_name(5), "CUESHEET") { ok = false; }
  return assert(ok, "code tables and name helpers");
}

fn t15() -> TestResult {
  var ok = true;
  if !err_frame_is(flac_parse_frame_header(&hb("FFF7900000"), 0), "flac: bad sync at 0") { ok = false; }
  if !err_frame_is(flac_parse_frame_header(&hb("7FF8C9080095"), 0), "flac: bad sync at 0") { ok = false; }
  if !err_frame_is(flac_parse_frame_header(&hb("FFFAC9080095"), 0), "flac: reserved bit set at 0") { ok = false; }
  if !err_frame_is(flac_parse_frame_header(&hb("FFF809080095"), 0), "flac: reserved block size at 0") { ok = false; }
  if !err_frame_is(flac_parse_frame_header(&hb("FFF8CF080095"), 0), "flac: reserved sample rate at 0") { ok = false; }
  if !err_frame_is(flac_parse_frame_header(&hb("FFF8C9B80095"), 0), "flac: reserved channel assignment at 0") { ok = false; }
  if !err_frame_is(flac_parse_frame_header(&hb("FFF8C9060095"), 0), "flac: reserved sample size at 0") { ok = false; }
  if !err_frame_is(flac_parse_frame_header(&hb("FFF8C9090095"), 0), "flac: reserved bit set at 0") { ok = false; }
  if !err_frame_is(flac_parse_frame_header(&hb("FFF8C908"), 0), "flac: truncated frame header at 0") { ok = false; }
  if !err_frame_is(flac_parse_frame_header(&hb("FFF8C90800"), 0), "flac: truncated frame header at 0") { ok = false; }
  if !err_frame_is(flac_parse_frame_header(&hb("FFF8C9080095"), -1), "flac: offset out of range") { ok = false; }
  if !err_frame_is(flac_parse_frame_header(&hb("FFF8C9080095"), 6), "flac: truncated frame header at 6") { ok = false; }
  // A fixed-blocksize number must fit 31 bits; the same 7-byte number is
  // legal with the variable-blocksize strategy.
  if !err_frame_is(flac_parse_frame_header(&hb("FFF8C908FE828080808080"), 0), "flac: frame number out of range at 4") { ok = false; }
  let vars = frame_bytes(249, 201, 8, &hb("FE828080808080"), &zeros(0));
  let vr = flac_parse_frame_header(&vars, 0);
  if !vr.is_ok { ok = false; } else {
    let hv = vr.value;
    if hv.number != 2147483648 { ok = false; }
    if hv.number_bytes != 7 { ok = false; }
    if hv.header_size != 12 { ok = false; }
    if !hv.crc8_ok { ok = false; }
  }
  let maxs = frame_bytes(248, 201, 8, &hb("FDBFBFBFBFBF"), &zeros(0));
  let xr = flac_parse_frame_header(&maxs, 0);
  if !xr.is_ok { ok = false; } elif xr.value.number != 2147483647 { ok = false; }
  return assert(ok, "frame header: reserved patterns, truncation and number range");
}

fn t16() -> TestResult {
  var ok = true;
  let empty = Vec[UInt8].new();
  if flac_crc8(&empty, 0, 0) != 0 { ok = false; }
  if flac_crc8(&hb("313233343536373839"), 0, 9) != 244 { ok = false; }
  if crc8_local_range(&hb("313233343536373839"), 0, 9) != 244 { ok = false; }
  if flac_crc8(&hb("00"), 0, 1) != 0 { ok = false; }
  if flac_crc8(&hb("FF"), 0, 1) != 243 { ok = false; }
  if flac_crc8(&hb("80"), 0, 1) != 137 { ok = false; }
  let d = hb("FFF8C9080095");
  if flac_crc8(&d, 0, 5) != 149 { ok = false; }
  if flac_crc8(&d, -1, 1) != -1 { ok = false; }
  if flac_crc8(&d, 0, 7) != -1 { ok = false; }
  if flac_crc8(&d, 6, 0) != 0 { ok = false; }
  var big = Vec[UInt8].new();
  var i = 0;
  while i < 256 {
    big.push(i as UInt8);
    i = i + 1;
  }
  if flac_crc8(&big, 0, 256) != crc8_local_range(&big, 0, 256) { ok = false; }
  // A mismatching stored CRC is reported, not rejected.
  let bad = set_byte(&d, 5, 148);
  let br = flac_parse_frame_header(&bad, 0);
  if !br.is_ok { ok = false; } else {
    let h = br.value;
    if h.crc8 != 148 { ok = false; }
    if h.crc8_ok { ok = false; }
    if h.header_size != 6 { ok = false; }
  }
  return assert(ok, "crc8: pinned vectors, bounds guard and mismatch flag");
}

fn t17() -> TestResult {
  let si = si_std();
  var s = marker();
  append_bytes(&mut s, &block(1, 0, &si));
  let mr = flac_parse_metadata(&s);
  var ok = true;
  if !mr.is_ok { return assert(false, "empty-collection accessors and range guards"); }
  let m = mr.value;
  if flac_block_offset(&m, -1) != -1 { ok = false; }
  if flac_block_offset(&m, 1) != -1 { ok = false; }
  if flac_block_type(&m, 1) != -1 { ok = false; }
  if flac_block_length(&m, 1) != -1 { ok = false; }
  if flac_seek_count(&m) != 0 { ok = false; }
  if flac_seek_sample(&m, 0) != -1 { ok = false; }
  if flac_seek_offset(&m, 0) != -1 { ok = false; }
  if flac_seek_frame_samples(&m, 0) != -1 { ok = false; }
  if flac_application_count(&m) != 0 { ok = false; }
  if !str_eq(flac_application_id(&m, 0), "") { ok = false; }
  if flac_application_data_length(&m, 0) != -1 { ok = false; }
  if !str_eq(flac_vendor(&m), "") { ok = false; }
  if flac_comment_count(&m) != 0 { ok = false; }
  if !str_eq(flac_comment(&m, 0), "") { ok = false; }
  if flac_cuesheet_count(&m) != 0 { ok = false; }
  if flac_cuesheet_track_count(&m, 0) != -1 { ok = false; }
  if flac_cuesheet_length(&m, 0) != -1 { ok = false; }
  if flac_picture_count(&m) != 0 { ok = false; }
  if flac_picture_type(&m, 0) != -1 { ok = false; }
  if !str_eq(flac_picture_mime(&m, 0), "") { ok = false; }
  if !str_eq(flac_picture_description(&m, 0), "") { ok = false; }
  if flac_picture_width(&m, 0) != -1 { ok = false; }
  if flac_picture_height(&m, 0) != -1 { ok = false; }
  if flac_picture_depth(&m, 0) != -1 { ok = false; }
  if flac_picture_colors(&m, 0) != -1 { ok = false; }
  if flac_picture_data_length(&m, 0) != -1 { ok = false; }
  return assert(ok, "empty-collection accessors and range guards");
}

fn t18() -> TestResult {
  var cl = Vec[Str].new();
  cl.push("A=1");
  let vp = vorbis_payload("xiom", &cl);
  let pp = picture_payload(3, "image/png", "x", 2, 4, 8, 0, &hb("AABB"));
  var s = marker();
  let si = si_std();
  append_bytes(&mut s, &block(0, 0, &si));
  append_bytes(&mut s, &block(0, 4, &vp));
  append_bytes(&mut s, &block(1, 6, &pp));
  let expected = s.len();
  let fr = frame_bytes(248, 201, 8, &hb("00"), &zeros(0));
  append_bytes(&mut s, &fr);
  let mr = flac_parse_metadata(&s);
  var ok = true;
  if !mr.is_ok { return assert(false, "end-to-end stream: metadata then first frame"); }
  let m = mr.value;
  if m.audio_offset != expected { ok = false; }
  let hdr = flac_parse_frame_header(&s, m.audio_offset);
  if !hdr.is_ok { ok = false; } else {
    let h = hdr.value;
    if h.header_size != 6 { ok = false; }
    if h.block_size != 4096 { ok = false; }
    if h.sample_rate != 44100 { ok = false; }
    if h.channels != 1 { ok = false; }
    if !h.crc8_ok { ok = false; }
  }
  let vr = flac_parse_vorbis_comment(&vp);
  if !vr.is_ok { ok = false; } else {
    let vc = vr.value;
    if !str_eq(vc.vendor, "xiom") { ok = false; }
    if vc.comments.len() != 1 { ok = false; }
  }
  let pr = flac_parse_picture(&pp);
  if !pr.is_ok { ok = false; } else {
    let pic = pr.value;
    if pic.width != 2 { ok = false; }
    if pic.height != 4 { ok = false; }
    if pic.data_length != 2 { ok = false; }
    if !str_eq(pic.mime, "image/png") { ok = false; }
  }
  if !err_vorbis_is(flac_parse_vorbis_comment(&hb("01000000")), "flac: vorbis comment overrun at 0") { ok = false; }
  if !err_picture_is(flac_parse_picture(&hb("00000003")), "flac: picture block overrun at 0") { ok = false; }
  return assert(ok, "end-to-end stream: metadata then first frame");
}

fn main() -> Int {
  io.println("=== xiom.flac conformance tests ===");
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
    io.println("xiom.flac: all tests passed");
  } else {
    io.println("xiom.flac: tests failed");
  }
  return failed;
}
