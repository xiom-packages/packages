// XIOM -- xiom.video conformance tests (24 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Every fixture is a synthetic byte buffer built in-test (or produced by the
// package's own muxers and then patched); no external file is ever read.
// Coverage: magic sniffing for avi/mkv/mp4/ogg/raw and the format-name
// mapping; FourCC decode with printable-ASCII validation; integer timebase
// rescaling (rounding half away from zero, negatives); the frame model;
// HH:MM:SS.mmm formatting; the raw XRAW mux/demux round-trip (tracks, frames,
// timestamps, key flags, odd/binary payloads); raw malformed inputs (magic,
// version, truncated header/record, oversized payload, bad track); the
// minimal RIFF/AVI writer structure (RIFF/AVI, avih, strl, movi, idx1,
// word alignment) and its demux round-trip; idx1 cross-check status (ok,
// mismatch, absent); AVI container/header/movi error cases; the mux and
// demux dispatch; builder validation; out-of-range accessor guards; and mux
// determinism.
//
// Discipline (compiler v0.62.2): every Vec element read is bound to a typed
// local, every Str equality goes through xiom.string.compare.str_compare,
// every UInt8 read/write is widened with `& 0xFF` / cast back, `r.value` of
// a Result[Vec[UInt8], Str] is bound to a typed local before being passed to
// a &Vec parameter (trap 4), and no mixed-bracket type typo exists anywhere.

module video_tests
use xiom.io; use xiom.test;
use xiom.video;
use xiom.video.store;
use xiom.video.avi;
use xiom.video.raw;
use xiom.video.container;
use xiom.string.compare;

// --------------------------------------------------
//  Comparison helpers
// --------------------------------------------------

fn str_eq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn err_stream_is(r: Result[VideoStream, Str], want: Str) -> Bool {
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

fn err_int_is(r: Result[Int, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn ok_bytes_or_empty(r: Result[Vec[UInt8], Str]) -> Vec[UInt8] {
  if r.is_ok {
    let b: Vec[UInt8] = r.value;
    return b;
  }
  return Vec[UInt8].new();
}

fn bytes_equal(a: Vec[UInt8], b: Vec[UInt8]) -> Bool {
  if a.len() != b.len() {
    return false;
  }
  var i = 0;
  while i < a.len() {
    let x: UInt8 = a[i];
    let y: UInt8 = b[i];
    if x != y {
      return false;
    }
    i = i + 1;
  }
  return true;
}

fn track_eq(s: &VideoStream, i: Int, kind: Int, codec: Int, scale: Int, rate: Int, length: Int, w: Int, h: Int, ch: Int, sr: Int) -> Bool {
  if video_track_kind(s, i) != kind { return false; }
  if video_track_codec(s, i) != codec { return false; }
  if video_track_scale(s, i) != scale { return false; }
  if video_track_rate(s, i) != rate { return false; }
  if video_track_length(s, i) != length { return false; }
  if video_track_width(s, i) != w { return false; }
  if video_track_height(s, i) != h { return false; }
  if video_track_channels(s, i) != ch { return false; }
  if video_track_sample_rate(s, i) != sr { return false; }
  return true;
}

fn frame_eq(s: &VideoStream, i: Int, track: Int, pts: Int, dts: Int, dur: Int, key: Int, data: &Vec[UInt8]) -> Bool {
  if video_frame_track(s, i) != track { return false; }
  if video_frame_pts(s, i) != pts { return false; }
  if video_frame_dts(s, i) != dts { return false; }
  if video_frame_duration(s, i) != dur { return false; }
  if video_frame_is_key(s, i) != key { return false; }
  let got = video_frame_data(s, i);
  return bytes_equal(got, data);
}

// --------------------------------------------------
//  Fixture builders (all pure Int/Vec helpers)
// --------------------------------------------------

fn push_byte(v: &mut Vec[UInt8], b: Int) {
  v.push(b as UInt8);
}

fn push_bytes(v: &mut Vec[UInt8], b: &Vec[UInt8]) {
  var i = 0;
  while i < b.len() {
    let x: UInt8 = b[i];
    v.push(x);
    i = i + 1;
  }
}

fn push_u16le(v: &mut Vec[UInt8], x: Int) {
  var n = ((x % 65536) + 65536) % 65536;
  push_byte(v, n % 256);
  push_byte(v, (n / 256) % 256);
}

fn push_u32le(v: &mut Vec[UInt8], x: Int) {
  var n = ((x % 4294967296) + 4294967296) % 4294967296;
  push_byte(v, n % 256);
  push_byte(v, (n / 256) % 256);
  push_byte(v, (n / 65536) % 256);
  push_byte(v, (n / 16777216) % 256);
}

fn push_fcc(v: &mut Vec[UInt8], f: Int) {
  push_byte(v, (f / 16777216) % 256);
  push_byte(v, (f / 65536) % 256);
  push_byte(v, (f / 256) % 256);
  push_byte(v, f % 256);
}

fn push_chunk(v: &mut Vec[UInt8], ckid: Int, body: &Vec[UInt8]) {
  push_fcc(v, ckid);
  push_u32le(v, body.len());
  push_bytes(v, body);
  if body.len() % 2 == 1 {
    push_byte(v, 0);
  }
}

fn push_list(v: &mut Vec[UInt8], ltype: Int, body: &Vec[UInt8]) {
  push_fcc(v, VIDEO_FCC_LIST);
  push_u32le(v, body.len() + 4);
  push_fcc(v, ltype);
  push_bytes(v, body);
}

fn fcc_at(data: &Vec[UInt8], pos: Int) -> Int {
  let b0: Int = (data[pos] as Int) & 0xFF;
  let b1: Int = (data[pos + 1] as Int) & 0xFF;
  let b2: Int = (data[pos + 2] as Int) & 0xFF;
  let b3: Int = (data[pos + 3] as Int) & 0xFF;
  return b0 * 16777216 + b1 * 65536 + b2 * 256 + b3;
}

fn find_fcc(data: &Vec[UInt8], f: Int) -> Int {
  var i = 0;
  while i + 4 <= data.len() {
    if fcc_at(data, i) == f {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

fn set_byte(v: &mut Vec[UInt8], i: Int, b: Int) {
  v[i] = b as UInt8;
}

fn set_u32le(v: &mut Vec[UInt8], pos: Int, x: Int) {
  var n = ((x % 4294967296) + 4294967296) % 4294967296;
  set_byte(v, pos, n % 256);
  set_byte(v, pos + 1, (n / 256) % 256);
  set_byte(v, pos + 2, (n / 65536) % 256);
  set_byte(v, pos + 3, (n / 16777216) % 256);
}

fn copy_bytes(src: &Vec[UInt8]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < src.len() {
    let b: UInt8 = src[i];
    out.push(b);
    i = i + 1;
  }
  return out;
}

fn truncate_to(v: &Vec[UInt8], n: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < n {
    if i >= v.len() {
      return out;
    }
    let b: UInt8 = v[i];
    out.push(b);
    i = i + 1;
  }
  return out;
}

fn pattern(n: Int, seed: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < n {
    push_byte(&mut v, (i * 37 + seed * 11 + 3) % 251);
    i = i + 1;
  }
  return v;
}

fn avih_bytes(streams: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  push_u32le(&mut v, 40000);
  push_u32le(&mut v, 0);
  push_u32le(&mut v, 0);
  push_u32le(&mut v, VIDEO_AVI_HASINDEX);
  push_u32le(&mut v, 0);
  push_u32le(&mut v, 0);
  push_u32le(&mut v, streams);
  push_u32le(&mut v, 0);
  push_u32le(&mut v, 0);
  push_u32le(&mut v, 0);
  push_u32le(&mut v, 0);
  push_u32le(&mut v, 0);
  push_u32le(&mut v, 0);
  push_u32le(&mut v, 0);
  return v;
}

fn strh_bytes(handler: Int, codec: Int, scale: Int, rate: Int, length: Int, w: Int, h: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  push_fcc(&mut v, handler);
  push_u32le(&mut v, codec);
  push_u32le(&mut v, 0);
  push_u16le(&mut v, 0);
  push_u16le(&mut v, 0);
  push_u32le(&mut v, 0);
  push_u32le(&mut v, scale);
  push_u32le(&mut v, rate);
  push_u32le(&mut v, 0);
  push_u32le(&mut v, length);
  push_u32le(&mut v, 0);
  push_u32le(&mut v, 0);
  push_u32le(&mut v, 0);
  push_u16le(&mut v, 0);
  push_u16le(&mut v, 0);
  push_u16le(&mut v, w);
  push_u16le(&mut v, h);
  return v;
}

fn strf_video_bytes(codec: Int, w: Int, h: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  push_u32le(&mut v, 40);
  push_u32le(&mut v, w);
  push_u32le(&mut v, h);
  push_u16le(&mut v, 1);
  push_u16le(&mut v, 24);
  push_u32le(&mut v, codec);
  push_u32le(&mut v, 0);
  push_u32le(&mut v, 0);
  push_u32le(&mut v, 0);
  push_u32le(&mut v, 0);
  push_u32le(&mut v, 0);
  return v;
}

fn strl_video(handler: Int, codec: Int, scale: Int, rate: Int, length: Int, w: Int, h: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  let sh = strh_bytes(handler, codec, scale, rate, length, w, h);
  let sf = strf_video_bytes(codec, w, h);
  push_chunk(&mut v, VIDEO_FCC_STRH, &sh);
  push_chunk(&mut v, VIDEO_FCC_STRF, &sf);
  return v;
}

fn avi_min(streams: Int, strls: &Vec[Vec[UInt8]], movi: &Vec[UInt8], idx: &Vec[UInt8], with_idx: Bool) -> Vec[UInt8] {
  var hdrl = Vec[UInt8].new();
  let ah = avih_bytes(streams);
  push_chunk(&mut hdrl, VIDEO_FCC_AVIH, &ah);
  var i = 0;
  while i < strls.len() {
    let sl: Vec[Vec[UInt8]] = strls;
    let one: Vec[UInt8] = sl[i];
    push_list(&mut hdrl, VIDEO_FCC_STRL, &one);
    i = i + 1;
  }
  var body = Vec[UInt8].new();
  push_fcc(&mut body, VIDEO_FCC_AVI);
  push_list(&mut body, VIDEO_FCC_HDRL, &hdrl);
  push_list(&mut body, VIDEO_FCC_MOVI, movi);
  if with_idx {
    push_chunk(&mut body, VIDEO_FCC_IDX1, idx);
  }
  var out = Vec[UInt8].new();
  push_fcc(&mut out, VIDEO_FCC_RIFF);
  push_u32le(&mut out, body.len());
  push_bytes(&mut out, &body);
  return out;
}

fn movi_one(ckid: Int, payload: &Vec[UInt8]) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  push_chunk(&mut v, ckid, payload);
  return v;
}

fn idx_one(ckid: Int, flags: Int, off: Int, size: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  push_fcc(&mut v, ckid);
  push_u32le(&mut v, flags);
  push_u32le(&mut v, off);
  push_u32le(&mut v, size);
  return v;
}

// Deterministic two-track store used by the raw/AVI round-trip checks.
fn build_store_a() -> VideoStream {
  var s = video_stream_new();
  video_add_track(&mut s, VIDEO_KIND_VIDEO, 0x64697678, 1, 25, 3, 640, 480, 0, 0);
  video_add_track(&mut s, VIDEO_KIND_AUDIO, 1, 1, 48000, 2, 0, 0, 2, 48000);
  let p0 = pattern(5, 1);
  let p1 = pattern(1, 2);
  let p2 = pattern(3, 3);
  let a0 = pattern(4, 4);
  let a1 = pattern(2, 5);
  video_add_frame(&mut s, 0, 0, 0, 40, 1, 0x30306463, &p0);
  video_add_frame(&mut s, 1, 0, 0, 0, 1, 0, &a0);
  video_add_frame(&mut s, 0, 40, 40, 40, 0, 0x30306463, &p1);
  video_add_frame(&mut s, 1, 0, 0, 0, 0, 0, &a1);
  video_add_frame(&mut s, 0, 80, 80, 40, 0, 0x30306463, &p2);
  return s;
}

// One-track, one-frame valid XRAW stream (integer codec tag).
fn raw_one_frame() -> Vec[UInt8] {
  var s = video_stream_new();
  video_add_track(&mut s, VIDEO_KIND_VIDEO, 0x64697678, 1, 25, 1, 32, 16, 0, 0);
  let p = pattern(5, 7);
  video_add_frame(&mut s, 0, 0, 0, 40, 1, 0, &p);
  return ok_bytes_or_empty(raw_mux(&s));
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  var ok = true;
  var avi = Vec[UInt8].new();
  push_fcc(&mut avi, VIDEO_FCC_RIFF);
  push_u32le(&mut avi, 4);
  push_fcc(&mut avi, VIDEO_FCC_AVI);
  if video_sniff(&avi) != VIDEO_FMT_AVI { ok = false; }
  var mkv = Vec[UInt8].new();
  push_byte(&mut mkv, 0x1A);
  push_byte(&mut mkv, 0x45);
  push_byte(&mut mkv, 0xDF);
  push_byte(&mut mkv, 0xA3);
  if video_sniff(&mkv) != VIDEO_FMT_MKV { ok = false; }
  var mp4 = Vec[UInt8].new();
  push_u32le(&mut mp4, 24);
  push_fcc(&mut mp4, VIDEO_FCC_FTYP);
  if video_sniff(&mp4) != VIDEO_FMT_MP4 { ok = false; }
  var ogg = Vec[UInt8].new();
  push_fcc(&mut ogg, VIDEO_FCC_OGGS);
  push_u32le(&mut ogg, 0);
  if video_sniff(&ogg) != VIDEO_FMT_OGG { ok = false; }
  var rawb = Vec[UInt8].new();
  push_fcc(&mut rawb, VIDEO_FCC_XRAW);
  push_u32le(&mut rawb, 0);
  if video_sniff(&rawb) != VIDEO_FMT_RAW { ok = false; }
  // A lone RIFF (WAV) is not AVI.
  var wav = Vec[UInt8].new();
  push_fcc(&mut wav, VIDEO_FCC_RIFF);
  push_u32le(&mut wav, 4);
  push_fcc(&mut wav, 0x57415645);
  if video_sniff(&wav) != VIDEO_FMT_UNKNOWN { ok = false; }
  var tiny = Vec[UInt8].new();
  push_byte(&mut tiny, 0x52);
  if video_sniff(&tiny) != VIDEO_FMT_UNKNOWN { ok = false; }
  var junk = Vec[UInt8].new();
  var k = 0;
  while k < 12 {
    push_byte(&mut junk, 0x7A);
    k = k + 1;
  }
  if video_sniff(&junk) != VIDEO_FMT_UNKNOWN { ok = false; }
  if !str_eq(video_format_name(VIDEO_FMT_AVI), "avi") { ok = false; }
  if !str_eq(video_format_name(VIDEO_FMT_MKV), "mkv") { ok = false; }
  if !str_eq(video_format_name(VIDEO_FMT_MP4), "mp4") { ok = false; }
  if !str_eq(video_format_name(VIDEO_FMT_OGG), "ogg") { ok = false; }
  if !str_eq(video_format_name(VIDEO_FMT_RAW), "raw") { ok = false; }
  if !str_eq(video_format_name(999), "unknown") { ok = false; }
  return assert(ok, "sniff: avi/mkv/mp4/ogg/raw + format-name mapping");
}

fn t2() -> TestResult {
  var ok = true;
  let r1 = video_fourcc_to_str(VIDEO_FCC_MOVI);
  if !r1.is_ok { ok = false; } else {
    if !str_eq(r1.value, "movi") { ok = false; }
  }
  let r2 = video_fourcc_to_str(0x30306463);
  if !r2.is_ok { ok = false; } else {
    if !str_eq(r2.value, "00dc") { ok = false; }
  }
  let r3 = video_fourcc_to_str(0x00006463);
  if r3.is_ok { ok = false; } else {
    if !str_eq(r3.error, "video: bad fourcc") { ok = false; }
  }
  let r4 = video_fourcc_to_str(0x80006463);
  if r4.is_ok { ok = false; } else {
    if !str_eq(r4.error, "video: bad fourcc") { ok = false; }
  }
  let r5 = video_fourcc_to_str(0x30310020);
  if r5.is_ok { ok = false; } else {
    if !str_eq(r5.error, "video: bad fourcc") { ok = false; }
  }
  return assert(ok, "fourcc: printable tables and NUL/control rejection");
}

fn t3() -> TestResult {
  var ok = true;
  if video_frame_duration_ms(25, 1) != 40 { ok = false; }
  if video_frame_duration_ms(30000, 1001) != 33 { ok = false; }
  if video_frame_duration_ms(24, 1) != 42 { ok = false; }
  if video_rescale(90, 1, 25, 1, 1000) != 3600 { ok = false; }
  if video_rescale(-3, 1, 2, 1, 1000) != -1500 { ok = false; }
  // Half away from zero: 1/3 -> 333, 2/3 -> 667, -1/2000 -> -1.
  if video_rescale(1, 1, 3, 1, 1000) != 333 { ok = false; }
  if video_rescale(2, 1, 3, 1, 1000) != 667 { ok = false; }
  if video_rescale(-1, 1, 2000, 1, 1000) != -1 { ok = false; }
  if video_units_to_ms(1500, 1, 1000) != 1500 { ok = false; }
  if video_ms_to_units(1500, 1, 25) != 38 { ok = false; }
  // Invalid timebases return 0 instead of dividing by zero.
  if video_rescale(5, 0, 1, 1, 1000) != 0 { ok = false; }
  if video_rescale(5, 1, -1, 1, 1000) != 0 { ok = false; }
  let tb = video_timebase_new(1, 1000);
  if !video_timebase_valid(&tb) { ok = false; }
  if video_timebase_rescale(250, &tb, 1, 25) != 6 { ok = false; }
  let bad = video_timebase_new(0, 5);
  if video_timebase_valid(&bad) { ok = false; }
  return assert(ok, "timebase: integer rescale, rounding, negatives, invalid input");
}

fn t4() -> TestResult {
  var ok = true;
  let f = video_frame_new(2, 100, 90, 40, 5);
  if f.track != 2 { ok = false; }
  if f.pts != 100 { ok = false; }
  if f.dts != 90 { ok = false; }
  if f.duration != 40 { ok = false; }
  if f.keyframe != 1 { ok = false; }
  if !video_frame_valid(&f) { ok = false; }
  if video_frame_end(&f) != 140 { ok = false; }
  let z = video_frame_new(0, 0, 0, 0, 0);
  if z.keyframe != 0 { ok = false; }
  if !video_frame_valid(&z) { ok = false; }
  let bad = video_frame_new(-1, 0, 0, 0, 0);
  if video_frame_valid(&bad) { ok = false; }
  let bad2 = video_frame_new(0, -5, 0, 0, 0);
  if video_frame_valid(&bad2) { ok = false; }
  let last = video_frame_new(0, 0, 0, 33, 1);
  if video_frame_end(&last) != 33 { ok = false; }
  return assert(ok, "frame model: fields, normalisation, validity, end");
}

fn t5() -> TestResult {
  var ok = true;
  if !str_eq(video_format_time(3661234, 1, 1000), "01:01:01.234") { ok = false; }
  if !str_eq(video_format_time(0, 1, 1000), "00:00:00.000") { ok = false; }
  if !str_eq(video_format_time(61000, 1, 1000), "00:01:01.000") { ok = false; }
  if !str_eq(video_format_time(-500, 1, 1000), "00:00:00.000") { ok = false; }
  if !str_eq(video_format_time(2500, 1, 25), "00:01:40.000") { ok = false; }
  return assert(ok, "format_time: HH:MM:SS.mmm, clamps, rescaled ticks");
}

fn t6() -> TestResult {
  let s = build_store_a();
  let r = raw_mux(&s);
  if !r.is_ok {
    return assert(false, "raw mux succeeds");
  }
  let bytes: Vec[UInt8] = r.value;
  if video_sniff(&bytes) != VIDEO_FMT_RAW {
    return assert(false, "raw bytes sniff as raw");
  }
  let d = raw_demux(&bytes);
  if !d.is_ok {
    return assert(false, "raw demux succeeds");
  }
  let t = d.value;
  var ok = true;
  if video_format(&t) != VIDEO_FMT_RAW { ok = false; }
  if video_track_count(&t) != 2 { ok = false; }
  if video_frame_count(&t) != 5 { ok = false; }
  if !track_eq(&t, 0, VIDEO_KIND_VIDEO, 0x64697678, 1, 25, 3, 640, 480, 0, 0) { ok = false; }
  if !track_eq(&t, 1, VIDEO_KIND_AUDIO, 1, 1, 48000, 2, 0, 0, 2, 48000) { ok = false; }
  if video_stream_duration_ms(&t) != 120 { ok = false; }
  let a = pattern(5, 1);
  let b = pattern(1, 2);
  let c = pattern(3, 3);
  let e = pattern(4, 4);
  let g = pattern(2, 5);
  if !frame_eq(&t, 0, 0, 0, 0, 40, 1, &a) { ok = false; }
  if !frame_eq(&t, 1, 1, 0, 0, 0, 1, &e) { ok = false; }
  if !frame_eq(&t, 2, 0, 40, 40, 40, 0, &b) { ok = false; }
  if !frame_eq(&t, 3, 1, 0, 0, 0, 0, &g) { ok = false; }
  if !frame_eq(&t, 4, 0, 80, 80, 40, 0, &c) { ok = false; }
  if video_track_frame_count(&t, 0) != 3 { ok = false; }
  if video_track_frame_count(&t, 1) != 2 { ok = false; }
  return assert(ok, "raw round-trip: tracks, frames, timestamps, keys, payloads");
}

fn t7() -> TestResult {
  var ok = true;
  let s = build_store_a();
  let r1 = raw_mux(&s);
  let r2 = raw_mux(&s);
  let b1: Vec[UInt8] = ok_bytes_or_empty(r1);
  let b2: Vec[UInt8] = ok_bytes_or_empty(r2);
  if !bytes_equal(b1, b2) { ok = false; }
  let empty = video_stream_new();
  let re = raw_mux(&empty);
  let eb: Vec[UInt8] = ok_bytes_or_empty(re);
  if eb.len() != 8 { ok = false; }
  let de = raw_demux(&eb);
  if !de.is_ok { ok = false; } else {
    let es: VideoStream = de.value;
    if video_track_count(&es) != 0 { ok = false; }
    if video_frame_count(&es) != 0 { ok = false; }
    if video_stream_duration_ms(&es) != 0 { ok = false; }
  }
  return assert(ok, "raw mux is deterministic; empty stream round-trips");
}

fn t8() -> TestResult {
  var ok = true;
  let good: Vec[UInt8] = raw_one_frame();
  // Truncated / wrong magic / wrong version.
  let short = truncate_to(&good, 4);
  if !err_stream_is(raw_demux(&short), "video: truncated header") { ok = false; }
  var bad_magic = copy_bytes(&good);
  set_byte(&mut bad_magic, 0, 0x59);
  if !err_stream_is(raw_demux(&bad_magic), "video: not a raw stream") { ok = false; }
  var bad_ver = copy_bytes(&good);
  set_byte(&mut bad_ver, 4, 2);
  if !err_stream_is(raw_demux(&bad_ver), "video: bad raw version") { ok = false; }
  // Track table truncation: 1 track needs 8 + 36 bytes.
  let table_cut = truncate_to(&good, 20);
  if !err_stream_is(raw_demux(&table_cut), "video: truncated header") { ok = false; }
  // Trailing partial record (drop the last payload byte).
  let rec_cut = truncate_to(&good, good.len() - 1);
  if !err_stream_is(raw_demux(&rec_cut), "video: truncated record") { ok = false; }
  // Oversized record payload (patch the size field at record offset 44 + 20).
  var big = copy_bytes(&good);
  set_u32le(&mut big, 64, 1000000);
  if !err_stream_is(raw_demux(&big), "video: truncated record") { ok = false; }
  // Out-of-range track number in the first record.
  var bad_trk = copy_bytes(&good);
  set_u32le(&mut bad_trk, 44, 5);
  if !err_stream_is(raw_demux(&bad_trk), "video: bad track index") { ok = false; }
  // A zero-length payload record is legal.
  var s = video_stream_new();
  video_add_track(&mut s, VIDEO_KIND_VIDEO, 0, 1, 1000, 0, 0, 0, 0, 0);
  let empty_p = Vec[UInt8].new();
  video_add_frame(&mut s, 0, 0, 0, 0, 1, 0, &empty_p);
  let z = ok_bytes_or_empty(raw_mux(&s));
  let dz = raw_demux(&z);
  if !dz.is_ok { ok = false; } else {
    let zs: VideoStream = dz.value;
    if video_frame_count(&zs) != 1 { ok = false; }
    if video_frame_size(&zs, 0) != 0 { ok = false; }
  }
  return assert(ok, "raw errors: magic, version, truncation, size, bad track");
}

fn t9() -> TestResult {
  let s = build_store_a();
  let m = avi_mux(&s);
  if !m.is_ok {
    return assert(false, "avi mux succeeds");
  }
  let b: Vec[UInt8] = m.value;
  var ok = true;
  if video_sniff(&b) != VIDEO_FMT_AVI { ok = false; }
  if fcc_at(&b, 0) != VIDEO_FCC_RIFF { ok = false; }
  if fcc_at(&b, 8) != VIDEO_FCC_AVI { ok = false; }
  let declared = (b[4] as Int) & 0xFF;
  let d1 = (b[5] as Int) & 0xFF;
  let d2 = (b[6] as Int) & 0xFF;
  let d3 = (b[7] as Int) & 0xFF;
  let size_field = declared + d1 * 256 + d2 * 65536 + d3 * 16777216;
  if size_field + 8 != b.len() { ok = false; }
  if find_fcc(&b, VIDEO_FCC_HDRL) < 0 { ok = false; }
  if find_fcc(&b, VIDEO_FCC_AVIH) < 0 { ok = false; }
  if find_fcc(&b, VIDEO_FCC_STRH) < 0 { ok = false; }
  if find_fcc(&b, VIDEO_FCC_STRF) < 0 { ok = false; }
  if find_fcc(&b, VIDEO_FCC_MOVI) < 0 { ok = false; }
  if find_fcc(&b, VIDEO_FCC_IDX1) < 0 { ok = false; }
  if find_fcc(&b, 0x30306463) < 0 { ok = false; }
  if find_fcc(&b, 0x30317762) < 0 { ok = false; }
  return assert(ok, "avi writer: RIFF/AVI, hdrl/avih/strl, movi chunks, idx1 size");
}

fn t10() -> TestResult {
  let s = build_store_a();
  let m = avi_mux(&s);
  if !m.is_ok {
    return assert(false, "avi mux succeeds");
  }
  let b: Vec[UInt8] = m.value;
  let d = avi_demux(&b);
  if !d.is_ok {
    return assert(false, "avi demux succeeds");
  }
  let t = d.value;
  var ok = true;
  if video_format(&t) != VIDEO_FMT_AVI { ok = false; }
  if video_track_count(&t) != 2 { ok = false; }
  if video_frame_count(&t) != 5 { ok = false; }
  if !track_eq(&t, 0, VIDEO_KIND_VIDEO, 0x64697678, 1, 25, 3, 640, 480, 0, 0) { ok = false; }
  if !track_eq(&t, 1, VIDEO_KIND_AUDIO, 1, 1, 48000, 2, 0, 0, 2, 48000) { ok = false; }
  // Video pts/duration derive from the stream timebase (1/25 s = 40 ms);
  // audio ticks are 1/48000 s and truncate to 0 ms.
  let p0 = pattern(5, 1);
  let a0 = pattern(4, 4);
  if !frame_eq(&t, 0, 0, 0, 0, 40, 1, &p0) { ok = false; }
  if !frame_eq(&t, 1, 1, 0, 0, 0, 1, &a0) { ok = false; }
  if video_frame_pts(&t, 2) != 40 { ok = false; }
  if video_frame_pts(&t, 4) != 80 { ok = false; }
  if video_frame_duration(&t, 4) != 40 { ok = false; }
  if video_index_entries(&t) != 5 { ok = false; }
  if video_index_ok(&t) != VIDEO_INDEX_OK { ok = false; }
  if video_flags(&t) != VIDEO_AVI_HASINDEX { ok = false; }
  if video_stream_duration_ms(&t) != 120 { ok = false; }
  if video_frame_chunk_offset(&t, 0) <= 0 { ok = false; }
  return assert(ok, "avi round-trip: headers, tracks, frames, timebase, idx1 ok");
}

fn t11() -> TestResult {
  let s = build_store_a();
  let b: Vec[UInt8] = ok_bytes_or_empty(avi_mux(&s));
  let ip = find_fcc(&b, VIDEO_FCC_IDX1);
  if ip < 0 {
    return assert(false, "idx1 present");
  }
  // Entry fields start at ip + 8: ckid, flags, off, size. Break the size.
  var patched = b;
  let entry = ip + 8;
  set_u32le(&mut patched, entry + 12, 999);
  let d = avi_demux(&patched);
  if !d.is_ok {
    return assert(false, "avi with a mismatched index still parses");
  }
  let t = d.value;
  var ok = true;
  if video_index_entries(&t) != 5 { ok = false; }
  if video_index_ok(&t) != VIDEO_INDEX_BAD { ok = false; }
  if video_frame_count(&t) != 5 { ok = false; }
  return assert(ok, "avi index mismatch: parse continues, index_ok=BAD");
}

fn t12() -> TestResult {
  let s = build_store_a();
  let b: Vec[UInt8] = ok_bytes_or_empty(avi_mux(&s));
  let ip = find_fcc(&b, VIDEO_FCC_IDX1);
  if ip < 0 {
    return assert(false, "idx1 present");
  }
  // Cut the trailing idx1 chunk and fix the RIFF size.
  let cut = truncate_to(&b, ip);
  var trimmed = cut;
  set_u32le(&mut trimmed, 4, trimmed.len() - 8);
  let d = avi_demux(&trimmed);
  if !d.is_ok {
    return assert(false, "avi without an index parses");
  }
  let t = d.value;
  var ok = true;
  if video_index_ok(&t) != VIDEO_INDEX_NONE { ok = false; }
  if video_index_entries(&t) != 0 { ok = false; }
  if video_frame_count(&t) != 5 { ok = false; }
  if video_frame_is_key(&t, 0) != 0 { ok = false; }
  return assert(ok, "avi without idx1: VIDEO_INDEX_NONE, no key flags");
}

fn t13() -> TestResult {
  var ok = true;
  let short_buf = Vec[UInt8].new();
  if !err_stream_is(avi_demux(&short_buf), "video: truncated header") { ok = false; }
  var wav = Vec[UInt8].new();
  push_fcc(&mut wav, VIDEO_FCC_RIFF);
  push_u32le(&mut wav, 4);
  push_fcc(&mut wav, 0x57415645);
  if !err_stream_is(avi_demux(&wav), "video: not avi") { ok = false; }
  let s = build_store_a();
  var b: Vec[UInt8] = ok_bytes_or_empty(avi_mux(&s));
  var huge = copy_bytes(&b);
  set_u32le(&mut huge, 4, 0x7FFFFFFF);
  if !err_stream_is(avi_demux(&huge), "video: bad riff size") { ok = false; }
  var trunc = copy_bytes(&b);
  let hp = find_fcc(&trunc, VIDEO_FCC_HDRL);
  if hp < 0 { ok = false; } else {
    set_u32le(&mut trunc, hp - 4, 0x7FFFFFFF);
    if !err_stream_is(avi_demux(&trunc), "video: truncated chunk") { ok = false; }
  }
  // No hdrl list at all.
  var no_hdrl = Vec[UInt8].new();
  var body = Vec[UInt8].new();
  push_fcc(&mut body, VIDEO_FCC_AVI);
  let empty_body = Vec[UInt8].new();
  push_list(&mut body, VIDEO_FCC_MOVI, &empty_body);
  push_fcc(&mut no_hdrl, VIDEO_FCC_RIFF);
  push_u32le(&mut no_hdrl, body.len());
  push_bytes(&mut no_hdrl, &body);
  if !err_stream_is(avi_demux(&no_hdrl), "video: missing header list") { ok = false; }
  return assert(ok, "avi errors: header, not-avi, riff size, truncation, no hdrl");
}

fn t14() -> TestResult {
  var ok = true;
  let empty_strls = Vec[Vec[UInt8]].new();
  let empty_movi = Vec[UInt8].new();
  let empty_idx = Vec[UInt8].new();
  // hdrl with avih but no strl.
  let no_strl = avi_min(1, &empty_strls, &empty_movi, &empty_idx, false);
  if !err_stream_is(avi_demux(&no_strl), "video: missing stream header") { ok = false; }
  // strl with strh only.
  var strh_only = Vec[UInt8].new();
  let sh = strh_bytes(VIDEO_FCC_VIDS, 0x30306463, 1, 25, 0, 16, 16);
  push_chunk(&mut strh_only, VIDEO_FCC_STRH, &sh);
  var one = Vec[Vec[UInt8]].new();
  one.push(strh_only);
  let no_strf = avi_min(1, &one, &empty_movi, &empty_idx, false);
  if !err_stream_is(avi_demux(&no_strf), "video: missing stream format") { ok = false; }
  // strf before strh.
  var reversed = Vec[UInt8].new();
  let sf = strf_video_bytes(0x30306463, 16, 16);
  push_chunk(&mut reversed, VIDEO_FCC_STRF, &sf);
  push_chunk(&mut reversed, VIDEO_FCC_STRH, &sh);
  var two = Vec[Vec[UInt8]].new();
  two.push(reversed);
  let bad_order = avi_min(1, &two, &empty_movi, &empty_idx, false);
  if !err_stream_is(avi_demux(&bad_order), "video: bad stream order") { ok = false; }
  // Declared stream count mismatch (avih says 3, one strl).
  let good_strl = strl_video(VIDEO_FCC_VIDS, 0x30306463, 1, 25, 0, 16, 16);
  var three = Vec[Vec[UInt8]].new();
  three.push(good_strl);
  let bad_count = avi_min(3, &three, &empty_movi, &empty_idx, false);
  if !err_stream_is(avi_demux(&bad_count), "video: bad stream count") { ok = false; }
  // Truncated avih body.
  var short_avih = Vec[UInt8].new();
  push_u32le(&mut short_avih, 1);
  push_u32le(&mut short_avih, 2);
  push_u32le(&mut short_avih, 3);
  let tiny_avih = truncate_to(&short_avih, 10);
  var hdrl_bad = Vec[UInt8].new();
  push_chunk(&mut hdrl_bad, VIDEO_FCC_AVIH, &tiny_avih);
  var bad_avih_body = Vec[UInt8].new();
  push_fcc(&mut bad_avih_body, VIDEO_FCC_AVI);
  push_list(&mut bad_avih_body, VIDEO_FCC_HDRL, &hdrl_bad);
  var bad_avih = Vec[UInt8].new();
  push_fcc(&mut bad_avih, VIDEO_FCC_RIFF);
  push_u32le(&mut bad_avih, bad_avih_body.len());
  push_bytes(&mut bad_avih, &bad_avih_body);
  if !err_stream_is(avi_demux(&bad_avih), "video: truncated main header") { ok = false; }
  // Truncated strh body.
  var short_strh = truncate_to(&sh, 20);
  var strl_bad = Vec[UInt8].new();
  push_chunk(&mut strl_bad, VIDEO_FCC_STRH, &short_strh);
  var four = Vec[Vec[UInt8]].new();
  four.push(strl_bad);
  let bad_strh = avi_min(1, &four, &empty_movi, &empty_idx, false);
  if !err_stream_is(avi_demux(&bad_strh), "video: truncated stream header") { ok = false; }
  // Truncated strf body.
  var short_strf = truncate_to(&sf, 10);
  var strl_bad2 = Vec[UInt8].new();
  push_chunk(&mut strl_bad2, VIDEO_FCC_STRH, &sh);
  push_chunk(&mut strl_bad2, VIDEO_FCC_STRF, &short_strf);
  var five = Vec[Vec[UInt8]].new();
  five.push(strl_bad2);
  let bad_strf = avi_min(1, &five, &empty_movi, &empty_idx, false);
  if !err_stream_is(avi_demux(&bad_strf), "video: truncated stream format") { ok = false; }
  return assert(ok, "avi header errors: strl/strh/strf/avih validation");
}

fn t15() -> TestResult {
  var ok = true;
  let pl = pattern(5, 9);
  var one = Vec[Vec[UInt8]].new();
  let good_strl = strl_video(VIDEO_FCC_VIDS, 0x30306463, 1, 25, 0, 16, 16);
  one.push(good_strl);
  let movi = movi_one(0x30306463, &pl);
  let idx = idx_one(0x30306463, VIDEO_AVI_KEYFRAME, 4, 5);
  let good = avi_min(1, &one, &movi, &idx, true);
  let d = avi_demux(&good);
  if !d.is_ok {
    return assert(false, "hand-built avi parses");
  }
  let t = d.value;
  if video_frame_count(&t) != 1 { ok = false; }
  if video_index_ok(&t) != VIDEO_INDEX_OK { ok = false; }
  if video_frame_is_key(&t, 0) != 1 { ok = false; }
  // Bad stream number: patch the first chunk's stream digits from "00" to "05".
  var bad_trk = good;
  let cp = find_fcc(&bad_trk, 0x30306463);
  if cp < 0 { ok = false; } else {
    set_byte(&mut bad_trk, cp + 1, 0x35);
    if !err_stream_is(avi_demux(&bad_trk), "video: bad stream number") { ok = false; }
  }
  // Bad index size (not a multiple of 16).
  var bad_idx = Vec[UInt8].new();
  var k = 0;
  while k < 17 {
    push_byte(&mut bad_idx, 0);
    k = k + 1;
  }
  let bad_index = avi_min(1, &one, &movi, &bad_idx, true);
  if !err_stream_is(avi_demux(&bad_index), "video: bad index size") { ok = false; }
  return assert(ok, "avi movi/index errors: stream number, index size, flags");
}

fn t16() -> TestResult {
  var ok = true;
  let empty = video_stream_new();
  if !err_bytes_is(avi_mux(&empty), "video: no streams") { ok = false; }
  let re = raw_mux(&empty);
  if !re.is_ok { ok = false; }
  let s = build_store_a();
  let m = avi_mux(&s);
  if !m.is_ok { ok = false; }
  return assert(ok, "mux validation: avi needs a stream, raw allows empty");
}

fn t17() -> TestResult {
  var ok = true;
  let s = build_store_a();
  let rb: Vec[UInt8] = ok_bytes_or_empty(raw_mux(&s));
  let rd = video_demux(&rb);
  if !rd.is_ok { ok = false; } else {
    let rs: VideoStream = rd.value;
    if video_format(&rs) != VIDEO_FMT_RAW { ok = false; }
  }
  let ab: Vec[UInt8] = ok_bytes_or_empty(avi_mux(&s));
  let ad = video_demux(&ab);
  if !ad.is_ok { ok = false; } else {
      let avi_s: VideoStream = ad.value;
      if video_format(&avi_s) != VIDEO_FMT_AVI { ok = false; }
  }
  var mkv = Vec[UInt8].new();
  push_byte(&mut mkv, 0x1A);
  push_byte(&mut mkv, 0x45);
  push_byte(&mut mkv, 0xDF);
  push_byte(&mut mkv, 0xA3);
  push_u32le(&mut mkv, 0);
  if !err_stream_is(video_demux(&mkv), "video: unsupported format") { ok = false; }
  var mp4 = Vec[UInt8].new();
  push_u32le(&mut mp4, 16);
  push_fcc(&mut mp4, VIDEO_FCC_FTYP);
  push_u32le(&mut mp4, 0);
  if !err_stream_is(video_demux(&mp4), "video: unsupported format") { ok = false; }
  var ogg = Vec[UInt8].new();
  push_fcc(&mut ogg, VIDEO_FCC_OGGS);
  push_u32le(&mut ogg, 0);
  push_u32le(&mut ogg, 0);
  if !err_stream_is(video_demux(&ogg), "video: unsupported format") { ok = false; }
  var junk = Vec[UInt8].new();
  var k = 0;
  while k < 12 {
    push_byte(&mut junk, 0x7A);
    k = k + 1;
  }
  if !err_stream_is(video_demux(&junk), "video: unknown format") { ok = false; }
  let empty = Vec[UInt8].new();
  if !err_stream_is(video_demux(&empty), "video: truncated header") { ok = false; }
  if !err_bytes_is(video_mux(&s, VIDEO_FMT_MKV), "video: unsupported format") { ok = false; }
  return assert(ok, "dispatch: raw/avi parse, mkv/mp4/ogg unsupported, unknown");
}

fn t18() -> TestResult {
  var ok = true;
  var s = video_stream_new();
  if !err_int_is(video_add_track(&mut s, 0, 0, 1, 25, 0, 0, 0, 0, 0), "video: bad track kind") { ok = false; }
  if !err_int_is(video_add_track(&mut s, 4, 0, 1, 25, 0, 0, 0, 0, 0), "video: bad track kind") { ok = false; }
  if !err_int_is(video_add_track(&mut s, VIDEO_KIND_VIDEO, 0, 0, 25, 0, 0, 0, 0, 0), "video: bad timebase") { ok = false; }
  if !err_int_is(video_add_track(&mut s, VIDEO_KIND_VIDEO, 0, 1, -25, 0, 0, 0, 0, 0), "video: bad timebase") { ok = false; }
  if !err_int_is(video_add_track(&mut s, VIDEO_KIND_VIDEO, -1, 1, 25, 0, 0, 0, 0, 0), "video: bad codec") { ok = false; }
  if !err_int_is(video_add_track(&mut s, VIDEO_KIND_VIDEO, 0, 1, 25, -1, 0, 0, 0, 0), "video: bad track field") { ok = false; }
  if video_track_count(&s) != 0 { ok = false; }
  let r0 = video_add_track(&mut s, VIDEO_KIND_VIDEO, 7, 1, 25, 3, 16, 16, 0, 0);
  if !r0.is_ok { ok = false; } else {
    let idx: Int = r0.value;
    if idx != 0 { ok = false; }
  }
  let p = pattern(4, 2);
  if !err_int_is(video_add_frame(&mut s, 5, 0, 0, 1, 0, 0, &p), "video: bad track index") { ok = false; }
  if !err_int_is(video_add_frame(&mut s, 0, -1, 0, 1, 0, 0, &p), "video: bad timestamp") { ok = false; }
  if !err_int_is(video_add_frame(&mut s, 0, 0, -1, 1, 0, 0, &p), "video: bad timestamp") { ok = false; }
  if !err_int_is(video_add_frame(&mut s, 0, 0, 0, -1, 0, 0, &p), "video: bad duration") { ok = false; }
  if !err_int_is(video_add_frame_span(&mut s, 0, 0, 0, 1, 0, 0, &p, -1, 2), "video: bad payload span") { ok = false; }
  if !err_int_is(video_add_frame_span(&mut s, 0, 0, 0, 1, 0, 0, &p, 2, 99), "video: bad payload span") { ok = false; }
  let rf = video_add_frame(&mut s, 0, 10, 5, 40, 2, 0, &p);
  if !rf.is_ok { ok = false; } else {
    let fi: Int = rf.value;
    if fi != 0 { ok = false; }
  }
  if video_frame_count(&s) != 1 { ok = false; }
  if video_frame_is_key(&s, 0) != 1 { ok = false; }
  // Out-of-range setters and getters are ignored/empty, never a crash.
  video_set_frame_key(&mut s, 9, 1);
  video_set_frame_chunk_offset(&mut s, 9, 99);
  let empty_data = video_frame_data(&s, 9);
  if empty_data.len() != 0 { ok = false; }
  return assert(ok, "builder validation: kinds, timebases, timestamps, spans");
}

fn t19() -> TestResult {
  var ok = true;
  var s = video_stream_new();
  if video_format(&s) != VIDEO_FMT_UNKNOWN { ok = false; }
  if video_stream_width(&s) != 0 { ok = false; }
  if video_stream_height(&s) != 0 { ok = false; }
  if video_stream_duration_ms(&s) != 0 { ok = false; }
  if video_index_entries(&s) != 0 { ok = false; }
  if video_index_ok(&s) != VIDEO_INDEX_NONE { ok = false; }
  if video_flags(&s) != 0 { ok = false; }
  if video_track_count(&s) != 0 { ok = false; }
  if video_track_kind(&s, 0) != -1 { ok = false; }
  if video_track_codec(&s, 0) != -1 { ok = false; }
  if video_track_duration_ms(&s, 0) != -1 { ok = false; }
  if video_frame_count(&s) != 0 { ok = false; }
  if video_frame_pts(&s, 0) != -1 { ok = false; }
  if video_frame_size(&s, 0) != -1 { ok = false; }
  if video_frame_codec(&s, 0) != -1 { ok = false; }
  if video_frame_chunk_offset(&s, 0) != -1 { ok = false; }
  let d = video_frame_data(&s, 0);
  if d.len() != 0 { ok = false; }
  let f = video_frame_at(&s, 0);
  if f.track != -1 { ok = false; }
  if video_track_frame_count(&s, 0) != 0 { ok = false; }
  // Setters clamp nothing on an empty store but never crash.
  video_set_format(&mut s, VIDEO_FMT_AVI);
  video_set_size(&mut s, 8, 8);
  video_set_duration_ms(&mut s, 5);
  video_set_flags(&mut s, 1);
  video_set_index(&mut s, 2, VIDEO_INDEX_BAD);
  if video_format(&s) != VIDEO_FMT_AVI { ok = false; }
  if video_stream_duration_ms(&s) != 5 { ok = false; }
  if video_index_ok(&s) != VIDEO_INDEX_BAD { ok = false; }
  return assert(ok, "guards: empty store accessors are range-safe");
}

fn t20() -> TestResult {
  var ok = true;
  var s = video_stream_new();
  video_add_track(&mut s, VIDEO_KIND_VIDEO, 0, 1, 1000, 2500, 0, 0, 0, 0);
  video_add_track(&mut s, VIDEO_KIND_VIDEO, 0, 1001, 30000, 9009, 0, 0, 0, 0);
  if video_track_duration_ms(&s, 0) != 2500 { ok = false; }
  if video_track_duration_ms(&s, 1) != 300600 { ok = false; }
  if !str_eq(video_format_time(300600, 1, 1000), "00:05:00.600") { ok = false; }
  if video_tick_ms(1, 25) != 40 { ok = false; }
  if video_tick_ms(1, 1000) != 1 { ok = false; }
  if video_units_to_ms(3, 1, 25) != 120 { ok = false; }
  if video_ms_to_units(120, 1, 25) != 3 { ok = false; }
  return assert(ok, "duration math: track durations, tick sizes, conversions");
}

fn t21() -> TestResult {
  var ok = true;
  var s = video_stream_new();
  video_add_track(&mut s, VIDEO_KIND_VIDEO, 0, 1, 25, 3, 16, 16, 0, 0);
  // Payloads with NUL, 0x80 and 0xFF bytes plus odd sizes survive both
  // containers byte-for-byte.
  var p0 = Vec[UInt8].new();
  push_byte(&mut p0, 0);
  push_byte(&mut p0, 128);
  push_byte(&mut p0, 255);
  var p1 = Vec[UInt8].new();
  push_byte(&mut p1, 0);
  var p2 = Vec[UInt8].new();
  push_byte(&mut p2, 255);
  push_byte(&mut p2, 1);
  push_byte(&mut p2, 2);
  push_byte(&mut p2, 3);
  push_byte(&mut p2, 4);
  video_add_frame(&mut s, 0, 0, 0, 40, 1, 0, &p0);
  video_add_frame(&mut s, 0, 40, 40, 40, 0, 0, &p1);
  video_add_frame(&mut s, 0, 80, 80, 40, 0, 0, &p2);
  let rb = ok_bytes_or_empty(raw_mux(&s));
  let rd = raw_demux(&rb);
  if !rd.is_ok { ok = false; } else {
    let rs: VideoStream = rd.value;
    if !frame_eq(&rs, 0, 0, 0, 0, 40, 1, &p0) { ok = false; }
    if !frame_eq(&rs, 1, 0, 40, 40, 40, 0, &p1) { ok = false; }
    if !frame_eq(&rs, 2, 0, 80, 80, 40, 0, &p2) { ok = false; }
  }
  let ab = ok_bytes_or_empty(avi_mux(&s));
  let ad = avi_demux(&ab);
  if !ad.is_ok { ok = false; } else {
    let avi_s: VideoStream = ad.value;
    if !frame_eq(&avi_s, 0, 0, 0, 0, 40, 1, &p0) { ok = false; }
    if !frame_eq(&avi_s, 1, 0, 40, 40, 40, 0, &p1) { ok = false; }
    if !frame_eq(&avi_s, 2, 0, 80, 80, 40, 0, &p2) { ok = false; }
  }
  return assert(ok, "binary fidelity: NUL/0x80/0xFF payloads, odd sizes");
}

fn t22() -> TestResult {
  var ok = true;
  var s = video_stream_new();
  video_add_track(&mut s, VIDEO_KIND_VIDEO, 0x64697678, 1, 25, 2, 16, 16, 0, 0);
  video_add_track(&mut s, VIDEO_KIND_AUDIO, 1, 1, 48000, 1, 0, 0, 2, 48000);
  video_add_track(&mut s, VIDEO_KIND_OTHER, 0x74787431, 1, 1000, 1, 0, 0, 0, 0);
  let p = pattern(4, 3);
  video_add_frame(&mut s, 0, 0, 0, 40, 1, 0, &p);
  video_add_frame(&mut s, 1, 0, 0, 0, 1, 0, &p);
  video_add_frame(&mut s, 2, 0, 0, 1, 1, 0, &p);
  let b: Vec[UInt8] = ok_bytes_or_empty(avi_mux(&s));
  let d = avi_demux(&b);
  if !d.is_ok {
    return assert(false, "three-kind avi parses");
  }
  let t = d.value;
  if video_track_count(&t) != 3 { ok = false; }
  if video_frame_count(&t) != 3 { ok = false; }
  // Chunk tags: "00dc" video, "01wb" audio, "02tx" other.
  if video_frame_codec(&t, 0) != 0x30306463 { ok = false; }
  if video_frame_codec(&t, 1) != 0x30317762 { ok = false; }
  if video_frame_codec(&t, 2) != 0x30327478 { ok = false; }
  if video_track_kind(&t, 2) != VIDEO_KIND_OTHER { ok = false; }
  let tag = video_fourcc_to_str(video_frame_codec(&t, 1));
  if !tag.is_ok { ok = false; } else {
    if !str_eq(tag.value, "01wb") { ok = false; }
  }
  return assert(ok, "chunk ids: per-track digits and dc/wb/tx types");
}

fn t23() -> TestResult {
  let s = build_store_a();
  let m1 = ok_bytes_or_empty(avi_mux(&s));
  let m2 = ok_bytes_or_empty(avi_mux(&s));
  var ok = bytes_equal(m1, m2);
  let d1 = avi_demux(&m1);
  let d2 = avi_demux(&m2);
  if !d1.is_ok || !d2.is_ok {
    return assert(false, "both avi muxes parse");
  }
  let a: VideoStream = d1.value;
  let b: VideoStream = d2.value;
  if video_frame_count(&a) != video_frame_count(&b) { ok = false; }
  var i = 0;
  while i < video_frame_count(&a) {
    if video_frame_pts(&a, i) != video_frame_pts(&b, i) { ok = false; }
    let da = video_frame_data(&a, i);
    let db = video_frame_data(&b, i);
    if !bytes_equal(da, db) { ok = false; }
    i = i + 1;
  }
  return assert(ok, "avi mux determinism: identical bytes and parsed snapshots");
}

fn t24() -> TestResult {
  var ok = true;
  let s = build_store_a();
  let a1 = video_mux(&s, VIDEO_FMT_AVI);
  let a2 = video_mux_avi(&s);
  let a1b: Vec[UInt8] = ok_bytes_or_empty(a1);
  let a2b: Vec[UInt8] = ok_bytes_or_empty(a2);
  if !bytes_equal(a1b, a2b) { ok = false; }
  let r1 = video_mux(&s, VIDEO_FMT_RAW);
  let r2 = video_mux_raw(&s);
  let r1b: Vec[UInt8] = ok_bytes_or_empty(r1);
  let r2b: Vec[UInt8] = ok_bytes_or_empty(r2);
  if !bytes_equal(r1b, r2b) { ok = false; }
  let d = video_demux(&r1b);
  if !d.is_ok { ok = false; } else {
    let ds: VideoStream = d.value;
    if video_track_count(&ds) != 2 { ok = false; }
  }
  return assert(ok, "mux dispatch: aliases and format selection agree");
}

// --------------------------------------------------
//  Harness
// --------------------------------------------------

fn main() -> Int {
  io.println("=== xiom.video conformance tests ===");
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
  let r21 = t21();
  if r21.passed { io.println("  [PASS] " + r21.name); } else { io.println("  [FAIL] " + r21.name); failed = failed + 1; }
  let r22 = t22();
  if r22.passed { io.println("  [PASS] " + r22.name); } else { io.println("  [FAIL] " + r22.name); failed = failed + 1; }
  let r23 = t23();
  if r23.passed { io.println("  [PASS] " + r23.name); } else { io.println("  [FAIL] " + r23.name); failed = failed + 1; }
  let r24 = t24();
  if r24.passed { io.println("  [PASS] " + r24.name); } else { io.println("  [FAIL] " + r24.name); failed = failed + 1; }
  if failed == 0 {
    io.println("xiom.video: all tests passed");
  } else {
    io.println("xiom.video: tests failed");
  }
  return failed;
}
