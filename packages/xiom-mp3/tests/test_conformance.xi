// XIOM -- xiom.mp3 conformance tests (21 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Covers the documented API: pinned MPEG-1/2/2.5 frame headers (all version
// and layer combinations), the per-version/layer bitrate and sample-rate
// tables, padding and frame-length formulas, the samples-per-frame table,
// frame-level and scan error paths, multi-frame scans (CBR, VBR, leading
// junk, trailing junk, truncated frames, ID3v1 tail), the ID3v2.3/2.4
// header (syncsafe sizes, flags, errors), the ID3v2 frame walk and text
// frames (TIT2/TPE1/TALB/TRCK/TYER/TDRC/TCON, unsynchronisation, NUL and
// encoding handling) and the ID3v1 128-byte tail tag.
//
// Every fixture is a synthetic byte buffer built in-test; no external data
// files. Err strings and Str fields are compared with
// compare.str_compare (BUG 17 discipline: `==` on Str lowers to a pointer
// comparison).

module mp3_tests
use xiom.io; use xiom.test;
use xiom.mp3;
use xiom.string;
use xiom.string.compare;
use xiom.encoding.hex;
use xiom.string.builder;
use xiom.convert;

// Expected bytes for a hex string ("" on malformed input; the test then
// fails on the byte comparison).
fn hb(hexstr: Str) -> Vec[UInt8] {
  let r = hex.hex_decode(hexstr);
  if r.is_ok {
    return r.value;
  }
  return Vec[UInt8].new();
}

fn bytes_equal(a: &Vec[UInt8], b: &Vec[UInt8]) -> Bool {
  if a.len() != b.len() {
    return false;
  }
  var i = 0;
  while i < a.len() {
    if a[i] != b[i] {
      return false;
    }
    i = i + 1;
  }
  return true;
}

fn str_eq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
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

// Byte `k` (0 = least significant) of `v` as a UInt8.
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

fn push_be32(dst: &mut Vec[UInt8], v: Int) {
  dst.push(byte_of(v, 3));
  dst.push(byte_of(v, 2));
  dst.push(byte_of(v, 1));
  dst.push(byte_of(v, 0));
}

fn append_bytes(dst: &mut Vec[UInt8], src: &Vec[UInt8]) {
  var i = 0;
  while i < src.len() {
    dst.push(src[i]);
    i = i + 1;
  }
}

fn truncate(data: &Vec[UInt8], n: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < n {
    out.push(data[i]);
    i = i + 1;
  }
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

fn gb(data: &Vec[UInt8], pos: Int) -> Int {
  return (data[pos] as Int) & 0xFF;
}

// --------------------------------------------------
//  Independent fixture builders (deliberately do not call the codec)
// --------------------------------------------------

fn vbits_of(version: Int) -> Int {
  if version == 1 { return 3; }
  if version == 2 { return 2; }
  return 0;
}

fn lbits_of(layer: Int) -> Int {
  if layer == 1 { return 3; }
  if layer == 2 { return 2; }
  return 1;
}

// 4 header bytes: "crc" is 1 when a CRC is present.
fn hdr(version: Int, layer: Int, br_index: Int, sr_index: Int, pad: Int, mode: Int, crc: Int) -> Vec[UInt8] {
  var h = Vec[UInt8].new();
  h.push(255 as UInt8);
  h.push((224 + vbits_of(version) * 8 + lbits_of(layer) * 2 + (1 - crc)) as UInt8);
  h.push((br_index * 16 + sr_index * 4 + pad * 2) as UInt8);
  h.push((mode * 64) as UInt8);
  return h;
}

// Fixture-side bitrate table (independent duplicate of the codec table).
fn kbps_local(version: Int, layer: Int, index: Int) -> Int {
  if version == 1 {
    if layer == 1 {
      return index * 32;
    }
    if layer == 2 {
      if index == 1 { return 32; }
      if index == 2 { return 48; }
      if index == 3 { return 56; }
      if index == 4 { return 64; }
      if index == 5 { return 80; }
      if index == 6 { return 96; }
      if index == 7 { return 112; }
      if index == 8 { return 128; }
      if index == 9 { return 160; }
      if index == 10 { return 192; }
      if index == 11 { return 224; }
      if index == 12 { return 256; }
      if index == 13 { return 320; }
      return 384;
    }
    if index == 1 { return 32; }
    if index == 2 { return 40; }
    if index == 3 { return 48; }
    if index == 4 { return 56; }
    if index == 5 { return 64; }
    if index == 6 { return 80; }
    if index == 7 { return 96; }
    if index == 8 { return 112; }
    if index == 9 { return 128; }
    if index == 10 { return 160; }
    if index == 11 { return 192; }
    if index == 12 { return 224; }
    if index == 13 { return 256; }
    return 320;
  }
  if layer == 1 {
    if index == 1 { return 32; }
    if index == 2 { return 48; }
    if index == 3 { return 56; }
    if index == 4 { return 64; }
    if index == 5 { return 80; }
    if index == 6 { return 96; }
    if index == 7 { return 112; }
    if index == 8 { return 128; }
    if index == 9 { return 144; }
    if index == 10 { return 160; }
    if index == 11 { return 176; }
    if index == 12 { return 192; }
    if index == 13 { return 224; }
    return 256;
  }
  if index == 1 { return 8; }
  if index == 2 { return 16; }
  if index == 3 { return 24; }
  if index == 4 { return 32; }
  if index == 5 { return 40; }
  if index == 6 { return 48; }
  if index == 7 { return 56; }
  if index == 8 { return 64; }
  if index == 9 { return 80; }
  if index == 10 { return 96; }
  if index == 11 { return 112; }
  if index == 12 { return 128; }
  if index == 13 { return 144; }
  return 160;
}

fn rate_local(version: Int, index: Int) -> Int {
  if version == 1 {
    if index == 0 { return 44100; }
    if index == 1 { return 48000; }
    return 32000;
  }
  if version == 2 {
    if index == 0 { return 22050; }
    if index == 1 { return 24000; }
    return 16000;
  }
  if index == 0 { return 11025; }
  if index == 1 { return 12000; }
  return 8000;
}

fn frame_len_local(version: Int, layer: Int, kbps: Int, rate: Int, pad: Int) -> Int {
  if layer == 1 {
    return ((12 * kbps * 1000) / rate + pad) * 4;
  }
  if layer == 2 {
    return (144 * kbps * 1000) / rate + pad;
  }
  if version == 1 {
    return (144 * kbps * 1000) / rate + pad;
  }
  return (72 * kbps * 1000) / rate + pad;
}

// One complete fixture frame: header plus a zero payload of the fixture-side
// computed length.
fn frame(version: Int, layer: Int, br_index: Int, sr_index: Int, pad: Int, mode: Int) -> Vec[UInt8] {
  var f = hdr(version, layer, br_index, sr_index, pad, mode, 0);
  let kbps = kbps_local(version, layer, br_index);
  let rate = rate_local(version, sr_index);
  let total = frame_len_local(version, layer, kbps, rate, pad);
  var i = 4;
  while i < total {
    f.push(0 as UInt8);
    i = i + 1;
  }
  return f;
}

fn frames_times(version: Int, layer: Int, br_index: Int, sr_index: Int, pad: Int, mode: Int, n: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < n {
    let f = frame(version, layer, br_index, sr_index, pad, mode);
    append_bytes(&mut out, &f);
    i = i + 1;
  }
  return out;
}

fn syncsafe(n: Int) -> Vec[UInt8] {
  var rem = n;
  var b3 = rem % 128;
  rem = rem / 128;
  var b2 = rem % 128;
  rem = rem / 128;
  var b1 = rem % 128;
  rem = rem / 128;
  var b0 = rem % 128;
  var v = Vec[UInt8].new();
  v.push(b0 as UInt8);
  v.push(b1 as UInt8);
  v.push(b2 as UInt8);
  v.push(b3 as UInt8);
  return v;
}

fn str_bytes(s: Str) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < s.len() {
    v.push(string.byte_at(s, i));
    i = i + 1;
  }
  return v;
}

// One ID3v2 frame: 4-byte id, size (plain u32 for v2.3, syncsafe for v2.4),
// 2 zero flag bytes, payload.
fn raw_frame(version: Int, id: Str, payload: &Vec[UInt8]) -> Vec[UInt8] {
  var f = Vec[UInt8].new();
  var i = 0;
  while i < 4 {
    f.push(string.byte_at(id, i));
    i = i + 1;
  }
  if version == 4 {
    let sz = syncsafe(payload.len());
    append_bytes(&mut f, &sz);
  } else {
    push_be32(&mut f, payload.len());
  }
  f.push(0 as UInt8);
  f.push(0 as UInt8);
  append_bytes(&mut f, payload);
  return f;
}

// One latin1 (encoding 0) text frame.
fn text_frame(version: Int, id: Str, text: Str) -> Vec[UInt8] {
  var p = Vec[UInt8].new();
  p.push(0 as UInt8);
  let tb = str_bytes(text);
  append_bytes(&mut p, &tb);
  return raw_frame(version, id, &p);
}

// Full ID3v2 tag: "ID3", major version, revision 0, flags, syncsafe payload
// size, payload.
fn id3v2_tag(version: Int, flags: Int, payload: &Vec[UInt8]) -> Vec[UInt8] {
  var t = Vec[UInt8].new();
  t.push(73 as UInt8);
  t.push(68 as UInt8);
  t.push(51 as UInt8);
  t.push(version as UInt8);
  t.push(0 as UInt8);
  t.push(flags as UInt8);
  let sz = syncsafe(payload.len());
  append_bytes(&mut t, &sz);
  append_bytes(&mut t, payload);
  return t;
}

// Fixed-size ID3v1 field: the Str bytes, zero padded to `n`.
fn fixed_str(dst: &mut Vec[UInt8], s: Str, n: Int) {
  var i = 0;
  while i < n {
    var b = 0;
    if i < s.len() {
      b = (string.byte_at(s, i) as Int) & 0xFF;
    }
    dst.push(b as UInt8);
    i = i + 1;
  }
}

// 128-byte ID3v1 tail tag; `track < 0` emits the ID3v1.0 30-byte comment.
fn id3v1_bytes(title: Str, artist: Str, album: Str, year: Str, comment: Str, track: Int, genre: Int) -> Vec[UInt8] {
  var t = Vec[UInt8].new();
  t.push(84 as UInt8);
  t.push(65 as UInt8);
  t.push(71 as UInt8);
  fixed_str(&mut t, title, 30);
  fixed_str(&mut t, artist, 30);
  fixed_str(&mut t, album, 30);
  fixed_str(&mut t, year, 4);
  if track >= 0 {
    fixed_str(&mut t, comment, 28);
    t.push(0 as UInt8);
    t.push(track as UInt8);
  } else {
    fixed_str(&mut t, comment, 30);
  }
  t.push(genre as UInt8);
  return t;
}

// ID3v2.3-style unsynchronisation: after every 0xFF byte insert 0x00.
fn unsync_bytes(logical: &Vec[UInt8]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < logical.len() {
    let b = (logical[i] as Int) & 0xFF;
    out.push(logical[i]);
    if b == 255 {
      out.push(0 as UInt8);
    }
    i = i + 1;
  }
  return out;
}

fn err_int_is(r: Result[Int, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_header_is(r: Result[Mp3FrameHeader, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_scan_is(r: Result[Mp3Scan, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_id3v2_is(r: Result[Mp3Id3v2Info, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_frames_is(r: Result[Mp3Id3v2Frames, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_v1_is(r: Result[Mp3Id3v1, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_str_is(r: Result[Str, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

// Big-endian integer field check on a raw buffer (independent of the codec).
fn be_u32_at(data: &Vec[UInt8], pos: Int) -> Int {
  var v = 0;
  var i = 0;
  while i < 4 {
    v = v * 256 + gb(data, pos + i);
    i = i + 1;
  }
  return v;
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  let data = hb("FFFB9000");
  let pr = mp3_parse_frame_header(&data, 0);
  if !pr.is_ok { return assert(false, "frame header: pinned MPEG-1 Layer III fields"); }
  let h = pr.value;
  var ok = true;
  if h.version != 1 { ok = false; }
  if h.layer != 3 { ok = false; }
  if h.bitrate_kbps != 128 { ok = false; }
  if h.sample_rate != 44100 { ok = false; }
  if h.padding { ok = false; }
  if h.crc { ok = false; }
  if h.channel_mode != 0 { ok = false; }
  if h.mode_extension != 0 { ok = false; }
  if h.copyright { ok = false; }
  if h.original { ok = false; }
  if h.emphasis != 0 { ok = false; }
  if h.frame_length != 417 { ok = false; }
  if h.samples_per_frame != 1152 { ok = false; }
  if mp3_frame_duration_ms(&h) != 26 { ok = false; }
  if !str_eq(mp3_version_name(1), "MPEG-1") { ok = false; }
  if !str_eq(mp3_layer_name(3), "Layer III") { ok = false; }
  if !str_eq(mp3_channel_mode_name(0), "stereo") { ok = false; }
  if !str_eq(mp3_emphasis_name(0), "none") { ok = false; }
  // Same frame, padded + CRC + mono + mode extension + flags + emphasis.
  let data2 = hb("FFFA92EF");
  let pr2 = mp3_parse_frame_header(&data2, 0);
  if !pr2.is_ok { ok = false; } else {
    let h2 = pr2.value;
    if h2.frame_length != 418 { ok = false; }
    if !h2.padding { ok = false; }
    if !h2.crc { ok = false; }
    if h2.channel_mode != 3 { ok = false; }
    if h2.mode_extension != 2 { ok = false; }
    if !h2.copyright { ok = false; }
    if !h2.original { ok = false; }
    if h2.emphasis != 3 { ok = false; }
    if !str_eq(mp3_channel_mode_name(3), "mono") { ok = false; }
    if !str_eq(mp3_emphasis_name(3), "CCITT J.17") { ok = false; }
  }
  return assert(ok, "frame header: pinned MPEG-1 Layer III fields");
}

fn t2() -> TestResult {
  var ok = true;
  // MPEG-1 Layer I 448 kbps 32000 Hz, padded: (12*448000/32000 + 1)*4 = 676.
  let d1 = hdr(1, 1, 14, 2, 1, 0, 0);
  let p1 = mp3_parse_frame_header(&d1, 0);
  if !p1.is_ok { ok = false; } else {
    let h1 = p1.value;
    if h1.bitrate_kbps != 448 { ok = false; }
    if h1.sample_rate != 32000 { ok = false; }
    if h1.frame_length != 676 { ok = false; }
    if h1.samples_per_frame != 384 { ok = false; }
    if mp3_frame_duration_ms(&h1) != 12 { ok = false; }
  }
  // MPEG-1 Layer II 384 kbps 48000 Hz: 144*384000/48000 = 1152.
  let d2 = hdr(1, 2, 14, 1, 0, 0, 0);
  let p2 = mp3_parse_frame_header(&d2, 0);
  if !p2.is_ok { ok = false; } else {
    let h2 = p2.value;
    if h2.frame_length != 1152 { ok = false; }
    if h2.samples_per_frame != 1152 { ok = false; }
  }
  // MPEG-2 Layer III 160 kbps 16000 Hz, padded: 72*160000/16000 + 1 = 721.
  let d3 = hdr(2, 3, 14, 2, 1, 0, 0);
  let p3 = mp3_parse_frame_header(&d3, 0);
  if !p3.is_ok { ok = false; } else {
    let h3 = p3.value;
    if h3.version != 2 { ok = false; }
    if h3.layer != 3 { ok = false; }
    if h3.frame_length != 721 { ok = false; }
    if h3.samples_per_frame != 576 { ok = false; }
    if mp3_frame_duration_ms(&h3) != 36 { ok = false; }
  }
  // MPEG-2.5 Layer III 8 kbps 8000 Hz: 72*8000/8000 = 72.
  let d4 = hdr(25, 3, 1, 2, 0, 0, 0);
  let p4 = mp3_parse_frame_header(&d4, 0);
  if !p4.is_ok { ok = false; } else {
    let h4 = p4.value;
    if h4.version != 25 { ok = false; }
    if h4.frame_length != 72 { ok = false; }
    if h4.samples_per_frame != 576 { ok = false; }
  }
  // MPEG-2.5 Layer I 32 kbps 11025 Hz: (12*32000/11025)*4 = 34*4 = 136.
  let d5 = hdr(25, 1, 1, 0, 0, 0, 0);
  let p5 = mp3_parse_frame_header(&d5, 0);
  if !p5.is_ok { ok = false; } else {
    let h5 = p5.value;
    if h5.frame_length != 136 { ok = false; }
    if h5.samples_per_frame != 384 { ok = false; }
  }
  // MPEG-2 Layer II 16 kbps 24000 Hz: 144*16000/24000 = 96.
  let d6 = hdr(2, 2, 2, 1, 0, 0, 0);
  let p6 = mp3_parse_frame_header(&d6, 0);
  if !p6.is_ok { ok = false; } else {
    let h6 = p6.value;
    if h6.frame_length != 96 { ok = false; }
    if h6.samples_per_frame != 1152 { ok = false; }
  }
  // Direct helper edges.
  if mp3_frame_length(1, 3, 0, 44100, false) != 0 { ok = false; }
  if mp3_frame_length(1, 3, 128, 0, false) != 0 { ok = false; }
  if mp3_frame_length(9, 3, 128, 44100, false) != 0 { ok = false; }
  return assert(ok, "frame length formulas across version/layer/padding");
}

fn t3() -> TestResult {
  var m1l1 = Vec[Int].new();
  m1l1.push(0); m1l1.push(32); m1l1.push(64); m1l1.push(96);
  m1l1.push(128); m1l1.push(160); m1l1.push(192); m1l1.push(224);
  m1l1.push(256); m1l1.push(288); m1l1.push(320); m1l1.push(352);
  m1l1.push(384); m1l1.push(416); m1l1.push(448);
  var m1l2 = Vec[Int].new();
  m1l2.push(0); m1l2.push(32); m1l2.push(48); m1l2.push(56);
  m1l2.push(64); m1l2.push(80); m1l2.push(96); m1l2.push(112);
  m1l2.push(128); m1l2.push(160); m1l2.push(192); m1l2.push(224);
  m1l2.push(256); m1l2.push(320); m1l2.push(384);
  var m1l3 = Vec[Int].new();
  m1l3.push(0); m1l3.push(32); m1l3.push(40); m1l3.push(48);
  m1l3.push(56); m1l3.push(64); m1l3.push(80); m1l3.push(96);
  m1l3.push(112); m1l3.push(128); m1l3.push(160); m1l3.push(192);
  m1l3.push(224); m1l3.push(256); m1l3.push(320);
  var m2l1 = Vec[Int].new();
  m2l1.push(0); m2l1.push(32); m2l1.push(48); m2l1.push(56);
  m2l1.push(64); m2l1.push(80); m2l1.push(96); m2l1.push(112);
  m2l1.push(128); m2l1.push(144); m2l1.push(160); m2l1.push(176);
  m2l1.push(192); m2l1.push(224); m2l1.push(256);
  var m2l23 = Vec[Int].new();
  m2l23.push(0); m2l23.push(8); m2l23.push(16); m2l23.push(24);
  m2l23.push(32); m2l23.push(40); m2l23.push(48); m2l23.push(56);
  m2l23.push(64); m2l23.push(80); m2l23.push(96); m2l23.push(112);
  m2l23.push(128); m2l23.push(144); m2l23.push(160);
  var ok = true;
  var i = 0;
  while i <= 14 {
    let w1: Int = m1l1[i];
    if mp3_bitrate_kbps(1, 1, i) != w1 { ok = false; }
    let w2: Int = m1l2[i];
    if mp3_bitrate_kbps(1, 2, i) != w2 { ok = false; }
    let w3: Int = m1l3[i];
    if mp3_bitrate_kbps(1, 3, i) != w3 { ok = false; }
    let w4: Int = m2l1[i];
    if mp3_bitrate_kbps(2, 1, i) != w4 { ok = false; }
    if mp3_bitrate_kbps(25, 1, i) != w4 { ok = false; }
    let w5: Int = m2l23[i];
    if mp3_bitrate_kbps(2, 2, i) != w5 { ok = false; }
    if mp3_bitrate_kbps(2, 3, i) != w5 { ok = false; }
    if mp3_bitrate_kbps(25, 2, i) != w5 { ok = false; }
    if mp3_bitrate_kbps(25, 3, i) != w5 { ok = false; }
    i = i + 1;
  }
  return assert(ok, "bitrate tables: all five version/layer families, indices 0-14");
}

fn t4() -> TestResult {
  var ok = true;
  if mp3_bitrate_kbps(1, 3, 0) != 0 { ok = false; }
  if mp3_bitrate_kbps(1, 3, 15) != -1 { ok = false; }
  if mp3_bitrate_kbps(1, 3, 16) != -1 { ok = false; }
  if mp3_bitrate_kbps(1, 3, -1) != -1 { ok = false; }
  if mp3_bitrate_kbps(7, 3, 5) != -1 { ok = false; }
  if mp3_bitrate_kbps(1, 4, 5) != -1 { ok = false; }
  if !err_header_is(mp3_parse_frame_header(&hb("FFFBF000"), 0), "mp3: bad bitrate index at 0") { ok = false; }
  if !err_header_is(mp3_parse_frame_header(&hb("FFFB0000"), 0), "mp3: free format at 0") { ok = false; }
  let d = hdr(1, 3, 9, 0, 0, 0, 0);
  let pr = mp3_parse_frame_header(&d, 0);
  if !pr.is_ok { ok = false; } elif pr.value.bitrate_kbps != 128 { ok = false; }
  return assert(ok, "bitrate edges: free format, bad index, invalid version/layer");
}

fn t5() -> TestResult {
  var ok = true;
  if mp3_sample_rate(1, 0) != 44100 { ok = false; }
  if mp3_sample_rate(1, 1) != 48000 { ok = false; }
  if mp3_sample_rate(1, 2) != 32000 { ok = false; }
  if mp3_sample_rate(2, 0) != 22050 { ok = false; }
  if mp3_sample_rate(2, 1) != 24000 { ok = false; }
  if mp3_sample_rate(2, 2) != 16000 { ok = false; }
  if mp3_sample_rate(25, 0) != 11025 { ok = false; }
  if mp3_sample_rate(25, 1) != 12000 { ok = false; }
  if mp3_sample_rate(25, 2) != 8000 { ok = false; }
  if mp3_sample_rate(1, 3) != 0 { ok = false; }
  if mp3_sample_rate(9, 0) != 0 { ok = false; }
  if !err_header_is(mp3_parse_frame_header(&hb("FFFB9C00"), 0), "mp3: bad sample rate index at 0") { ok = false; }
  let d1 = hdr(2, 3, 9, 2, 0, 0, 0);
  let p1 = mp3_parse_frame_header(&d1, 0);
  if !p1.is_ok { ok = false; } elif p1.value.sample_rate != 16000 { ok = false; }
  let d2 = hdr(25, 3, 9, 0, 0, 0, 0);
  let p2 = mp3_parse_frame_header(&d2, 0);
  if !p2.is_ok { ok = false; } elif p2.value.sample_rate != 11025 { ok = false; }
  return assert(ok, "sample-rate tables for MPEG-1/2/2.5; index 3 is reserved");
}

fn t6() -> TestResult {
  var ok = true;
  if mp3_samples_per_frame(1, 1) != 384 { ok = false; }
  if mp3_samples_per_frame(2, 1) != 384 { ok = false; }
  if mp3_samples_per_frame(25, 1) != 384 { ok = false; }
  if mp3_samples_per_frame(1, 2) != 1152 { ok = false; }
  if mp3_samples_per_frame(2, 2) != 1152 { ok = false; }
  if mp3_samples_per_frame(25, 2) != 1152 { ok = false; }
  if mp3_samples_per_frame(1, 3) != 1152 { ok = false; }
  if mp3_samples_per_frame(2, 3) != 576 { ok = false; }
  if mp3_samples_per_frame(25, 3) != 576 { ok = false; }
  if mp3_samples_per_frame(9, 1) != 0 { ok = false; }
  if mp3_samples_per_frame(1, 9) != 0 { ok = false; }
  if !str_eq(mp3_version_name(2), "MPEG-2") { ok = false; }
  if !str_eq(mp3_version_name(25), "MPEG-2.5") { ok = false; }
  if !str_eq(mp3_version_name(9), "") { ok = false; }
  if !str_eq(mp3_layer_name(1), "Layer I") { ok = false; }
  if !str_eq(mp3_layer_name(2), "Layer II") { ok = false; }
  if !str_eq(mp3_layer_name(4), "") { ok = false; }
  if !str_eq(mp3_channel_mode_name(1), "joint stereo") { ok = false; }
  if !str_eq(mp3_channel_mode_name(2), "dual channel") { ok = false; }
  if !str_eq(mp3_channel_mode_name(9), "") { ok = false; }
  if !str_eq(mp3_emphasis_name(1), "50/15 ms") { ok = false; }
  if !str_eq(mp3_emphasis_name(2), "reserved") { ok = false; }
  if !str_eq(mp3_emphasis_name(9), "") { ok = false; }
  return assert(ok, "samples-per-frame table and version/layer/mode/emphasis names");
}

fn t7() -> TestResult {
  var ok = true;
  let empty = Vec[UInt8].new();
  let four = hb("FFFB9000");
  if !err_header_is(mp3_parse_frame_header(&empty, 0), "mp3: truncated frame header at 0") { ok = false; }
  if !err_header_is(mp3_parse_frame_header(&hb("FFFB"), 0), "mp3: truncated frame header at 0") { ok = false; }
  if !err_header_is(mp3_parse_frame_header(&four, 1), "mp3: truncated frame header at 1") { ok = false; }
  if !err_header_is(mp3_parse_frame_header(&four, 4), "mp3: truncated frame header at 4") { ok = false; }
  if !err_header_is(mp3_parse_frame_header(&four, -1), "mp3: offset out of range") { ok = false; }
  if !err_header_is(mp3_parse_frame_header(&hb("00FB9000"), 0), "mp3: bad sync at 0") { ok = false; }
  if !err_header_is(mp3_parse_frame_header(&hb("FF009000"), 0), "mp3: bad sync at 0") { ok = false; }
  if !err_header_is(mp3_parse_frame_header(&hb("FFEB9000"), 0), "mp3: reserved version at 0") { ok = false; }
  if !err_header_is(mp3_parse_frame_header(&hb("FFF99000"), 0), "mp3: reserved layer at 0") { ok = false; }
  return assert(ok, "frame header errors: truncation, sync, reserved version/layer");
}

fn t8() -> TestResult {
  var ok = true;
  var data = Vec[UInt8].new();
  let junk = hb("00010203040506");
  append_bytes(&mut data, &junk);
  let f = frame(1, 3, 9, 0, 0, 0);
  append_bytes(&mut data, &f);
  let r0 = mp3_find_frame(&data, 0);
  if !r0.is_ok { ok = false; } elif r0.value != 7 { ok = false; }
  let r1 = mp3_find_frame(&data, 3);
  if !r1.is_ok { ok = false; } elif r1.value != 7 { ok = false; }
  let r2 = mp3_find_frame(&data, 7);
  if !r2.is_ok { ok = false; } elif r2.value != 7 { ok = false; }
  let r3 = mp3_find_frame(&data, 8);
  if !err_int_is(r3, "mp3: no frame found") { ok = false; }
  let r4 = mp3_find_frame(&data, data.len());
  if !err_int_is(r4, "mp3: no frame found") { ok = false; }
  let r5 = mp3_find_frame(&data, data.len() + 1);
  if !err_int_is(r5, "mp3: offset out of range") { ok = false; }
  let r6 = mp3_find_frame(&data, -1);
  if !err_int_is(r6, "mp3: offset out of range") { ok = false; }
  let zeros = repeat_byte(0, 32);
  if !err_int_is(mp3_find_frame(&zeros, 0), "mp3: no frame found") { ok = false; }
  let ff = repeat_byte(255, 16);
  if !err_int_is(mp3_find_frame(&ff, 0), "mp3: no frame found") { ok = false; }
  // A free-format candidate after 3 junk bytes.
  var ff_data = hb("414243");
  let ffh = hdr(1, 3, 0, 0, 0, 0, 0);
  append_bytes(&mut ff_data, &ffh);
  append_bytes(&mut ff_data, &f);
  if !err_int_is(mp3_find_frame(&ff_data, 0), "mp3: free format at 3") { ok = false; }
  return assert(ok, "find_frame: junk scan, bounds, free format, no-frame paths");
}

fn t9() -> TestResult {
  let data = frames_times(1, 3, 9, 0, 0, 0, 10);
  let sr = mp3_scan(&data);
  if !sr.is_ok { return assert(false, "scan: 10 consecutive CBR frames, offsets, duration"); }
  let sc = sr.value;
  var ok = true;
  if data.len() != 4170 { ok = false; }
  if sc.start != 0 { ok = false; }
  if sc.offset != 0 { ok = false; }
  if sc.frame_count != 10 { ok = false; }
  if sc.end_offset != 4170 { ok = false; }
  if sc.trailing_bytes != 0 { ok = false; }
  if sc.corrupted { ok = false; }
  if sc.version != 1 { ok = false; }
  if sc.layer != 3 { ok = false; }
  if sc.sample_rate != 44100 { ok = false; }
  if sc.bitrate_kbps != 128 { ok = false; }
  if sc.channel_mode != 0 { ok = false; }
  if sc.samples_per_frame != 1152 { ok = false; }
  if sc.total_samples != 11520 { ok = false; }
  if sc.duration_ms != 261 { ok = false; }
  if sc.frame_offsets.len() != 10 { ok = false; }
  if sc.frame_lengths.len() != 10 { ok = false; }
  let o0: Int = sc.frame_offsets[0];
  let o9: Int = sc.frame_offsets[9];
  let l9: Int = sc.frame_lengths[9];
  if o0 != 0 { ok = false; }
  if o9 != 3753 { ok = false; }
  if l9 != 417 { ok = false; }
  return assert(ok, "scan: 10 consecutive CBR frames, offsets, duration");
}

fn t10() -> TestResult {
  var ok = true;
  let two = frames_times(1, 3, 9, 0, 0, 0, 2);
  var d1 = Vec[UInt8].new();
  append_bytes(&mut d1, &two);
  append_bytes(&mut d1, &hb("AABBCC"));
  let s1 = mp3_scan(&d1);
  if !s1.is_ok { ok = false; } else {
    let sc = s1.value;
    if sc.frame_count != 2 { ok = false; }
    if sc.trailing_bytes != 3 { ok = false; }
    if !sc.corrupted { ok = false; }
    if sc.end_offset != 834 { ok = false; }
  }
  var d2 = Vec[UInt8].new();
  append_bytes(&mut d2, &two);
  append_bytes(&mut d2, &hb("AABB"));
  let s2 = mp3_scan(&d2);
  if !s2.is_ok { ok = false; } else {
    let sc = s2.value;
    if sc.frame_count != 2 { ok = false; }
    if sc.trailing_bytes != 2 { ok = false; }
    if !sc.corrupted { ok = false; }
  }
  // A declared frame whose payload does not fully fit is corruption.
  var d3 = Vec[UInt8].new();
  append_bytes(&mut d3, &two);
  let stub = truncate(&frame(1, 3, 9, 0, 0, 0), 10);
  append_bytes(&mut d3, &stub);
  let s3 = mp3_scan(&d3);
  if !s3.is_ok { ok = false; } else {
    let sc = s3.value;
    if sc.frame_count != 2 { ok = false; }
    if sc.trailing_bytes != 10 { ok = false; }
    if !sc.corrupted { ok = false; }
  }
  // A frame with a different sample rate stops the run as corruption.
  var d4 = Vec[UInt8].new();
  append_bytes(&mut d4, &two);
  let other = frame(1, 3, 9, 1, 0, 0);
  append_bytes(&mut d4, &other);
  let s4 = mp3_scan(&d4);
  if !s4.is_ok { ok = false; } else {
    let sc = s4.value;
    if sc.frame_count != 2 { ok = false; }
    if !sc.corrupted { ok = false; }
    if sc.trailing_bytes != 384 { ok = false; }
  }
  // A first frame whose payload is truncated is a hard error.
  let only_header = hb("FFFB9000");
  if !err_scan_is(mp3_scan(&only_header), "mp3: truncated frame at 0") { ok = false; }
  let one = frames_times(1, 3, 9, 0, 0, 0, 1);
  let s5 = mp3_scan(&one);
  if !s5.is_ok { ok = false; } else {
    let sc = s5.value;
    if sc.frame_count != 1 { ok = false; }
    if sc.corrupted { ok = false; }
    if sc.trailing_bytes != 0 { ok = false; }
    if sc.duration_ms != 26 { ok = false; }
  }
  return assert(ok, "scan: trailing junk, partial frames, mismatched rate, truncated first frame");
}

fn t11() -> TestResult {
  var ok = true;
  // VBR: three 128 kbps frames (417 bytes) then two 160 kbps frames (522).
  var data = Vec[UInt8].new();
  append_bytes(&mut data, &frames_times(1, 3, 9, 0, 0, 0, 3));
  append_bytes(&mut data, &frames_times(1, 3, 10, 0, 0, 0, 2));
  let sr = mp3_scan(&data);
  if !sr.is_ok { ok = false; } else {
    let sc = sr.value;
    if sc.frame_count != 5 { ok = false; }
    if sc.total_samples != 5760 { ok = false; }
    if sc.duration_ms != 130 { ok = false; }
    if sc.corrupted { ok = false; }
    if sc.end_offset != 2295 { ok = false; }
    let o1: Int = sc.frame_offsets[1];
    let o3: Int = sc.frame_offsets[3];
    let l3: Int = sc.frame_lengths[3];
    if o1 != 417 { ok = false; }
    if o3 != 1251 { ok = false; }
    if l3 != 522 { ok = false; }
  }
  // Scan from an explicit start: five junk bytes then three frames.
  var d2 = Vec[UInt8].new();
  append_bytes(&mut d2, &hb("0001020304"));
  append_bytes(&mut d2, &frames_times(1, 3, 9, 0, 0, 0, 3));
  let s0 = mp3_scan_from(&d2, 0);
  if !s0.is_ok { ok = false; } else {
    let sc = s0.value;
    if sc.start != 0 { ok = false; }
    if sc.offset != 5 { ok = false; }
    if sc.frame_count != 3 { ok = false; }
    if sc.duration_ms != 78 { ok = false; }
  }
  let s3 = mp3_scan_from(&d2, 3);
  if !s3.is_ok { ok = false; } else {
    let sc = s3.value;
    if sc.start != 3 { ok = false; }
    if sc.offset != 5 { ok = false; }
    if sc.frame_count != 3 { ok = false; }
  }
  let s9 = mp3_scan_from(&d2, 9);
  if !s9.is_ok { ok = false; } else {
    let sc = s9.value;
    if sc.start != 9 { ok = false; }
    if sc.offset != 422 { ok = false; }
    if sc.frame_count != 2 { ok = false; }
    if sc.duration_ms != 52 { ok = false; }
  }
  return assert(ok, "scan: VBR mix and explicit start offsets");
}

fn t12() -> TestResult {
  var ok = true;
  let payload = repeat_byte(0, 20);
  let tag = id3v2_tag(3, 0, &payload);
  if tag.len() != 30 { ok = false; }
  var data = Vec[UInt8].new();
  append_bytes(&mut data, &tag);
  append_bytes(&mut data, &frames_times(1, 3, 9, 0, 0, 0, 4));
  let sr = mp3_scan(&data);
  if !sr.is_ok { ok = false; } else {
    let sc = sr.value;
    if sc.start != 30 { ok = false; }
    if sc.offset != 30 { ok = false; }
    if sc.frame_count != 4 { ok = false; }
    if sc.corrupted { ok = false; }
    if sc.duration_ms != 104 { ok = false; }
  }
  // A trailing ID3v1 tag ends the scan cleanly.
  var data2 = Vec[UInt8].new();
  append_bytes(&mut data2, &data);
  let tail = id3v1_bytes("T", "A", "B", "2026", "C", 1, 17);
  append_bytes(&mut data2, &tail);
  let s2 = mp3_scan(&data2);
  if !s2.is_ok { ok = false; } else {
    let sc = s2.value;
    if sc.frame_count != 4 { ok = false; }
    if sc.corrupted { ok = false; }
    if sc.trailing_bytes != 128 { ok = false; }
    if sc.end_offset != 1698 { ok = false; }
  }
  if !mp3_has_id3v1(&data2) { ok = false; }
  if mp3_has_id3v1(&data) { ok = false; }
  // A malformed ID3v2 header poisons mp3_scan instead of being skipped.
  var bad = Vec[UInt8].new();
  append_bytes(&mut bad, &hb("49443309000000000000"));
  append_bytes(&mut bad, &frames_times(1, 3, 9, 0, 0, 0, 1));
  if !err_scan_is(mp3_scan(&bad), "mp3: unsupported id3v2 version at 3") { ok = false; }
  return assert(ok, "scan: leading ID3v2 skipped, trailing ID3v1 recognized");
}

fn t13() -> TestResult {
  var ok = true;
  var tag = Vec[UInt8].new();
  append_bytes(&mut tag, &hb("49443303000000000014"));
  append_bytes(&mut tag, &repeat_byte(0, 20));
  let r = mp3_id3v2_header(&tag);
  if !r.is_ok { ok = false; } else {
    let i = r.value;
    if i.version != 3 { ok = false; }
    if i.revision != 0 { ok = false; }
    if i.flags != 0 { ok = false; }
    if i.payload_size != 20 { ok = false; }
    if i.total_size != 30 { ok = false; }
    if i.unsynchronised { ok = false; }
    if i.extended_header { ok = false; }
    if i.experimental { ok = false; }
    if i.footer { ok = false; }
  }
  var tag4 = Vec[UInt8].new();
  append_bytes(&mut tag4, &hb("4944330400f000000000"));
  let r4 = mp3_id3v2_header(&tag4);
  if !r4.is_ok { ok = false; } else {
    let i = r4.value;
    if i.version != 4 { ok = false; }
    if i.flags != 240 { ok = false; }
    if !i.unsynchronised { ok = false; }
    if !i.extended_header { ok = false; }
    if !i.experimental { ok = false; }
    if !i.footer { ok = false; }
    if i.payload_size != 0 { ok = false; }
    if i.total_size != 10 { ok = false; }
  }
  // Pinned syncsafe size 256 = 0x00 0x00 0x02 0x00.
  var tag256 = Vec[UInt8].new();
  append_bytes(&mut tag256, &hb("49443304000000000200"));
  append_bytes(&mut tag256, &repeat_byte(0, 256));
  let r256 = mp3_id3v2_header(&tag256);
  if !r256.is_ok { ok = false; } else {
    if r256.value.payload_size != 256 { ok = false; }
    if r256.value.total_size != 266 { ok = false; }
  }
  if !err_id3v2_is(mp3_id3v2_header(&hb("4944330300000000")), "mp3: truncated id3v2 header at 0") { ok = false; }
  if !err_id3v2_is(mp3_id3v2_header(&repeat_byte(0, 10)), "mp3: bad id3v2 magic at 0") { ok = false; }
  if !err_id3v2_is(mp3_id3v2_header(&hb("49443305000000000000")), "mp3: unsupported id3v2 version at 3") { ok = false; }
  if !err_id3v2_is(mp3_id3v2_header(&hb("49443303000080000000")), "mp3: bad syncsafe size at 6") { ok = false; }
  if !err_id3v2_is(mp3_id3v2_header(&hb("49443303000000000064")), "mp3: id3v2 size overrun at 6") { ok = false; }
  return assert(ok, "ID3v2 header: v2.3/v2.4 fields, syncsafe sizes, error catalog");
}

fn t14() -> TestResult {
  var payload = Vec[UInt8].new();
  append_bytes(&mut payload, &text_frame(3, "TIT2", "Hello"));
  append_bytes(&mut payload, &text_frame(3, "TPE1", "World"));
  append_bytes(&mut payload, &text_frame(3, "TALB", "Album X"));
  append_bytes(&mut payload, &text_frame(3, "TRCK", "7"));
  append_bytes(&mut payload, &text_frame(3, "TYER", "2026"));
  append_bytes(&mut payload, &text_frame(3, "TCON", "Rock"));
  append_bytes(&mut payload, &repeat_byte(0, 6));
  let tag = id3v2_tag(3, 0, &payload);
  var ok = true;
  let fr = mp3_id3v2_frames(&tag);
  if !fr.is_ok { return assert(false, "ID3v2.3 text frames: ids, sizes, convenience readers"); }
  let frames = fr.value;
  if mp3_id3v2_frame_count(&frames) != 6 { ok = false; }
  if !str_eq(mp3_id3v2_frame_id(&frames, 0), "TIT2") { ok = false; }
  if !str_eq(mp3_id3v2_frame_id(&frames, 2), "TALB") { ok = false; }
  if !str_eq(mp3_id3v2_frame_id(&frames, 5), "TCON") { ok = false; }
  if mp3_id3v2_frame_size(&frames, 0) != 6 { ok = false; }
  if mp3_id3v2_frame_size(&frames, 3) != 2 { ok = false; }
  if !str_eq(mp3_id3v2_frame_text(&frames, 0), "Hello") { ok = false; }
  if !str_eq(mp3_id3v2_frame_text(&frames, 5), "Rock") { ok = false; }
  if mp3_id3v2_find(&frames, "TALB") != 2 { ok = false; }
  if mp3_id3v2_find(&frames, "XXXX") != -1 { ok = false; }
  if !str_eq(mp3_id3v2_text(&frames, "TPE1"), "World") { ok = false; }
  if !str_eq(mp3_id3v2_text(&frames, "XXXX"), "") { ok = false; }
  if !str_eq(mp3_id3v2_frame_id(&frames, -1), "") { ok = false; }
  if !str_eq(mp3_id3v2_frame_id(&frames, 99), "") { ok = false; }
  if mp3_id3v2_frame_size(&frames, 99) != -1 { ok = false; }
  if !str_eq(mp3_id3v2_frame_text(&frames, 99), "") { ok = false; }
  let t = mp3_id3v2_title(&tag);
  if !t.is_ok { ok = false; } elif !str_eq(t.value, "Hello") { ok = false; }
  let a = mp3_id3v2_artist(&tag);
  if !a.is_ok { ok = false; } elif !str_eq(a.value, "World") { ok = false; }
  let al = mp3_id3v2_album(&tag);
  if !al.is_ok { ok = false; } elif !str_eq(al.value, "Album X") { ok = false; }
  let tr = mp3_id3v2_track(&tag);
  if !tr.is_ok { ok = false; } elif !str_eq(tr.value, "7") { ok = false; }
  let yr = mp3_id3v2_year(&tag);
  if !yr.is_ok { ok = false; } elif !str_eq(yr.value, "2026") { ok = false; }
  let ge = mp3_id3v2_genre(&tag);
  if !ge.is_ok { ok = false; } elif !str_eq(ge.value, "Rock") { ok = false; }
  return assert(ok, "ID3v2.3 text frames: ids, sizes, convenience readers");
}

fn t15() -> TestResult {
  var ok = true;
  // A v2.4 frame with syncsafe size 130 (a v2.3 read would give 258).
  var big = Vec[UInt8].new();
  big.push(0 as UInt8);
  append_bytes(&mut big, &repeat_byte(65, 129));
  let p15 = raw_frame(4, "TIT2", &big);
  let fr = mp3_id3v2_frames(&id3v2_tag(4, 0, &p15));
  if !fr.is_ok { ok = false; } else {
    let frames = fr.value;
    if mp3_id3v2_frame_count(&frames) != 1 { ok = false; }
    if mp3_id3v2_frame_size(&frames, 0) != 130 { ok = false; }
    let t0: Str = frames.texts[0];
    let wanta = builder.sb_to_str(&repeat_byte(65, 129));
    if !str_eq(t0, wanta) { ok = false; }
  }
  // TDRC is the v2.4 year frame.
  var p16 = Vec[UInt8].new();
  append_bytes(&mut p16, &text_frame(4, "TDRC", "2026"));
  let tag16 = id3v2_tag(4, 0, &p16);
  let yr = mp3_id3v2_year(&tag16);
  if !yr.is_ok { ok = false; } elif !str_eq(yr.value, "2026") { ok = false; }
  // Bad v2.4 frame size (high bit set in the first size byte).
  var bad_p = Vec[UInt8].new();
  var bf = Vec[UInt8].new();
  let idb = str_bytes("TIT2");
  append_bytes(&mut bf, &idb);
  bf.push(128 as UInt8);
  bf.push(0 as UInt8);
  bf.push(0 as UInt8);
  bf.push(10 as UInt8);
  bf.push(0 as UInt8);
  bf.push(0 as UInt8);
  append_bytes(&mut bf, &repeat_byte(0, 10));
  append_bytes(&mut bad_p, &bf);
  if !err_frames_is(mp3_id3v2_frames(&id3v2_tag(4, 0, &bad_p)), "mp3: bad id3v2 frame size at 0") { ok = false; }
  // A v2.4 frame whose declared size overruns the payload.
  var over_p = Vec[UInt8].new();
  var of2 = Vec[UInt8].new();
  append_bytes(&mut of2, &idb);
  let sz200 = syncsafe(200);
  append_bytes(&mut of2, &sz200);
  of2.push(0 as UInt8);
  of2.push(0 as UInt8);
  append_bytes(&mut of2, &repeat_byte(0, 10));
  append_bytes(&mut over_p, &of2);
  if !err_frames_is(mp3_id3v2_frames(&id3v2_tag(4, 0, &over_p)), "mp3: id3v2 frame overrun at 0") { ok = false; }
  // The extended header flag is rejected by the frame walk (minimal handling).
  var ext_p = Vec[UInt8].new();
  append_bytes(&mut ext_p, &text_frame(3, "TIT2", "x"));
  if !err_frames_is(mp3_id3v2_frames(&id3v2_tag(3, 64, &ext_p)), "mp3: unsupported id3v2 extended header at 5") { ok = false; }
  return assert(ok, "ID3v2.4 syncsafe frame sizes, TDRC, frame errors");
}

fn t16() -> TestResult {
  // Logical (de-unsynchronised) TIT2 frame: encoding 0, "A", 0xFF, "B".
  var logical = Vec[UInt8].new();
  let idb = str_bytes("TIT2");
  append_bytes(&mut logical, &idb);
  push_be32(&mut logical, 4);
  logical.push(0 as UInt8);
  logical.push(0 as UInt8);
  logical.push(0 as UInt8);
  logical.push(65 as UInt8);
  logical.push(255 as UInt8);
  logical.push(66 as UInt8);
  let phys = unsync_bytes(&logical);
  let tag = id3v2_tag(3, 128, &phys);
  var ok = true;
  let fr = mp3_id3v2_frames(&tag);
  if !fr.is_ok { return assert(false, "ID3v2 unsynchronisation: de-escape and text bytes"); }
  let frames = fr.value;
  if mp3_id3v2_frame_count(&frames) != 1 { ok = false; }
  if mp3_id3v2_frame_size(&frames, 0) != 4 { ok = false; }
  let t0: Str = frames.texts[0];
  let want = builder.sb_to_str(&hb("41FF42"));
  if !str_eq(t0, want) { ok = false; }
  if (string.byte_at(t0, 0) as Int) & 0xFF != 65 { ok = false; }
  if (string.byte_at(t0, 1) as Int) & 0xFF != 255 { ok = false; }
  if (string.byte_at(t0, 2) as Int) & 0xFF != 66 { ok = false; }
  return assert(ok, "ID3v2 unsynchronisation: de-escape and text bytes");
}

fn t17() -> TestResult {
  var data = repeat_byte(90, 100);
  let tail = id3v1_bytes("Title", "Artist", "Album", "2026", "Comment", 5, 17);
  if tail.len() != 128 { return assert(false, "ID3v1.1 tail: fields, track byte, genre"); }
  append_bytes(&mut data, &tail);
  var ok = true;
  if !mp3_has_id3v1(&data) { ok = false; }
  let r = mp3_id3v1(&data);
  if !r.is_ok { return assert(false, "ID3v1.1 tail: fields, track byte, genre"); }
  let v = r.value;
  if !str_eq(v.title, "Title") { ok = false; }
  if !str_eq(v.artist, "Artist") { ok = false; }
  if !str_eq(v.album, "Album") { ok = false; }
  if !str_eq(v.year, "2026") { ok = false; }
  if !str_eq(v.comment, "Comment") { ok = false; }
  if !v.has_track { ok = false; }
  if v.track != 5 { ok = false; }
  if v.genre != 17 { ok = false; }
  if !str_eq(mp3_id3v1_genre_name(v.genre), "Rock") { ok = false; }
  if !str_eq(mp3_id3v1_genre_name(0), "Blues") { ok = false; }
  if !str_eq(mp3_id3v1_genre_name(79), "Hard Rock") { ok = false; }
  if !str_eq(mp3_id3v1_genre_name(80), "") { ok = false; }
  if !str_eq(mp3_id3v1_genre_name(148), "") { ok = false; }
  if !str_eq(mp3_id3v1_genre_name(255), "") { ok = false; }
  if !str_eq(mp3_id3v1_genre_name(-1), "") { ok = false; }
  return assert(ok, "ID3v1.1 tail: fields, track byte, genre");
}

fn t18() -> TestResult {
  var ok = true;
  // ID3v1.0: full 30-byte comment, no track byte.
  let tail = id3v1_bytes("T", "A", "B", "1999", "a comment that is long...", -1, 79);
  var data = repeat_byte(0, 128);
  append_bytes(&mut data, &tail);
  let r = mp3_id3v1(&data);
  if !r.is_ok { ok = false; } else {
    let v = r.value;
    if v.has_track { ok = false; }
    if v.track != 0 { ok = false; }
    if !str_eq(v.comment, "a comment that is long...") { ok = false; }
    if !str_eq(v.year, "1999") { ok = false; }
    if v.genre != 79 { ok = false; }
  }
  let empty = Vec[UInt8].new();
  if !err_v1_is(mp3_id3v1(&empty), "mp3: empty input") { ok = false; }
  if !err_v1_is(mp3_id3v1(&repeat_byte(0, 127)), "mp3: truncated id3v1 tag (128 bytes required)") { ok = false; }
  if !err_v1_is(mp3_id3v1(&repeat_byte(0, 128)), "mp3: no id3v1 tag at 0") { ok = false; }
  if !err_v1_is(mp3_id3v1(&repeat_byte(0, 200)), "mp3: no id3v1 tag at 72") { ok = false; }
  if mp3_has_id3v1(&repeat_byte(0, 128)) { ok = false; }
  if mp3_has_id3v1(&repeat_byte(0, 127)) { ok = false; }
  return assert(ok, "ID3v1.0 tail and id3v1 error catalog");
}

fn t19() -> TestResult {
  var ok = true;
  if !err_header_is(mp3_parse_frame_header(&hb("FFFB90"), 0), "mp3: truncated frame header at 0") { ok = false; }
  if !err_scan_is(mp3_scan(&hb("FFFB")), "mp3: no frame found") { ok = false; }
  let empty = Vec[UInt8].new();
  if !err_scan_is(mp3_scan(&empty), "mp3: no frame found") { ok = false; }
  if !err_scan_is(mp3_scan(&repeat_byte(255, 64)), "mp3: no frame found") { ok = false; }
  if !err_scan_is(mp3_scan_from(&frames_times(1, 3, 9, 0, 0, 0, 1), -1), "mp3: offset out of range") { ok = false; }
  if !err_scan_is(mp3_scan_from(&frames_times(1, 3, 9, 0, 0, 0, 1), 1000), "mp3: offset out of range") { ok = false; }
  // Scanning from just inside a frame finds no second frame (zero payloads).
  let one = frames_times(1, 3, 9, 0, 0, 0, 1);
  if !err_scan_is(mp3_scan_from(&one, 1), "mp3: no frame found") { ok = false; }
  return assert(ok, "malformed and truncated inputs: scan and offset errors");
}

fn t20() -> TestResult {
  var ok = true;
  // NUL-separated values keep only the first string.
  var p1 = Vec[UInt8].new();
  p1.push(0 as UInt8);
  p1.push(65 as UInt8);
  p1.push(66 as UInt8);
  p1.push(0 as UInt8);
  p1.push(67 as UInt8);
  p1.push(68 as UInt8);
  // Unsupported encoding (1 = UTF-16): id recorded, text empty.
  var p2 = Vec[UInt8].new();
  p2.push(1 as UInt8);
  let hello = str_bytes("Hello");
  append_bytes(&mut p2, &hello);
  // Non-text frame: recorded with its size, no text.
  var p3 = hb("00010203");
  var payload = Vec[UInt8].new();
  append_bytes(&mut payload, &raw_frame(3, "TIT2", &p1));
  append_bytes(&mut payload, &raw_frame(3, "TIT2", &p2));
  append_bytes(&mut payload, &raw_frame(3, "APIC", &p3));
  let tag = id3v2_tag(3, 0, &payload);
  let fr = mp3_id3v2_frames(&tag);
  if !fr.is_ok { return assert(false, "ID3v2 text details: NUL stop, encoding filter, non-text frames"); }
  let frames = fr.value;
  if mp3_id3v2_frame_count(&frames) != 3 { ok = false; }
  if !str_eq(mp3_id3v2_frame_text(&frames, 0), "AB") { ok = false; }
  if !str_eq(mp3_id3v2_frame_text(&frames, 1), "") { ok = false; }
  if !str_eq(mp3_id3v2_frame_text(&frames, 2), "") { ok = false; }
  if mp3_id3v2_frame_size(&frames, 0) != 6 { ok = false; }
  if mp3_id3v2_frame_size(&frames, 1) != 6 { ok = false; }
  if mp3_id3v2_frame_size(&frames, 2) != 4 { ok = false; }
  if !str_eq(mp3_id3v2_frame_id(&frames, 2), "APIC") { ok = false; }
  return assert(ok, "ID3v2 text details: NUL stop, encoding filter, non-text frames");
}

fn t21() -> TestResult {
  var ok = true;
  // Frame durations from the samples/rate tables.
  let h1 = hdr(1, 1, 14, 2, 0, 0, 0);
  let p1 = mp3_parse_frame_header(&h1, 0);
  if !p1.is_ok { ok = false; } elif mp3_frame_duration_ms(&p1.value) != 12 { ok = false; }
  let h2 = hdr(2, 3, 14, 2, 0, 0, 0);
  let p2 = mp3_parse_frame_header(&h2, 0);
  if !p2.is_ok { ok = false; } elif mp3_frame_duration_ms(&p2.value) != 36 { ok = false; }
  // 38 frames of 1152 samples at 44100 Hz -> 992 ms (floor).
  let data = frames_times(1, 3, 9, 0, 0, 0, 38);
  let sr = mp3_scan(&data);
  if !sr.is_ok { ok = false; } else {
    let sc = sr.value;
    if sc.frame_count != 38 { ok = false; }
    if sc.total_samples != 43776 { ok = false; }
    if sc.duration_ms != 992 { ok = false; }
  }
  return assert(ok, "frame duration and scan duration floor arithmetic");
}

fn main() -> Int {
  io.println("=== xiom.mp3 conformance tests ===");
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
  if failed == 0 {
    io.println("xiom.mp3: all tests passed");
  } else {
    io.println("xiom.mp3: tests failed");
  }
  return failed;
}
