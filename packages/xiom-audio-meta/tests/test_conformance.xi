// XIOM -- xiom.audio-meta conformance tests (25 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Deterministic, self-contained suite: every fixture is built byte by byte
// in memory (no external files, no randomness). Covers the full public API:
// MIDI SMF header/track/varlen parsing and its error catalog; MOD header,
// signature subset, order and pattern statistics; XM, S3M, IT and NSF header
// parsing with their pattern/instrument geometry and error catalogs; the
// 40-entry chiptune registry (metadata, full magic round-trip, detection and
// rejection); and the per-format is_valid wrappers.
//
// Err strings are compared with string.str_compare (BUG 17 discipline:
// `==` on non-literal Str values is not reliable).

module audio_meta_tests
use xiom.io; use xiom.test;
use xiom.audio_meta;
use xiom.audio_meta.trackers;
use xiom.audio_meta.chiptune;
use xiom.string;
use xiom.string.builder;

// --------------------------------------------------
//  Fixture helpers
// --------------------------------------------------

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

fn push_be32(dst: &mut Vec[UInt8], v: Int) {
  dst.push(byte_of(v, 3));
  dst.push(byte_of(v, 2));
  dst.push(byte_of(v, 1));
  dst.push(byte_of(v, 0));
}

fn push_le16(dst: &mut Vec[UInt8], v: Int) {
  dst.push(byte_of(v, 0));
  dst.push(byte_of(v, 1));
}

fn push_le32(dst: &mut Vec[UInt8], v: Int) {
  dst.push(byte_of(v, 0));
  dst.push(byte_of(v, 1));
  dst.push(byte_of(v, 2));
  dst.push(byte_of(v, 3));
}

fn push_zeros(dst: &mut Vec[UInt8], n: Int) {
  var i = 0;
  while i < n {
    dst.push(0 as UInt8);
    i = i + 1;
  }
}

fn push_str_bytes(dst: &mut Vec[UInt8], s: Str) {
  builder.sb_push_str(dst, s);
}

fn append_bytes(dst: &mut Vec[UInt8], src: &Vec[UInt8]) {
  var i = 0;
  while i < src.len() {
    dst.push(src[i]);
    i = i + 1;
  }
}

fn concat_bytes(a: &Vec[UInt8], b: &Vec[UInt8]) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  append_bytes(&mut v, a);
  append_bytes(&mut v, b);
  return v;
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

fn set_be16(data: &Vec[UInt8], pos: Int, v: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < data.len() {
    if i >= pos && i < pos + 2 {
      out.push(byte_of(v, pos + 1 - i));
    } else {
      out.push(data[i]);
    }
    i = i + 1;
  }
  return out;
}

fn set_be32(data: &Vec[UInt8], pos: Int, v: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < data.len() {
    if i >= pos && i < pos + 4 {
      out.push(byte_of(v, pos + 3 - i));
    } else {
      out.push(data[i]);
    }
    i = i + 1;
  }
  return out;
}

fn set_le16(data: &Vec[UInt8], pos: Int, v: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < data.len() {
    if i >= pos && i < pos + 2 {
      out.push(byte_of(v, i - pos));
    } else {
      out.push(data[i]);
    }
    i = i + 1;
  }
  return out;
}

fn set_le32(data: &Vec[UInt8], pos: Int, v: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < data.len() {
    if i >= pos && i < pos + 4 {
      out.push(byte_of(v, i - pos));
    } else {
      out.push(data[i]);
    }
    i = i + 1;
  }
  return out;
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
  return string.str_compare(a, b) == 0;
}

fn push_varlen(dst: &mut Vec[UInt8], v: Int) {
  if v < 128 {
    dst.push(v as UInt8);
    return;
  }
  if v < 16384 {
    dst.push(((v / 128) + 128) as UInt8);
    dst.push((v % 128) as UInt8);
    return;
  }
  dst.push(((v / 16384) + 128) as UInt8);
  dst.push((((v / 128) % 128) + 128) as UInt8);
  dst.push((v % 128) as UInt8);
}

fn err_midi_is(r: Result[MidiInfo, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return str_eq(r.error, want);
}

fn err_mod_is(r: Result[ModInfo, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return str_eq(r.error, want);
}

fn err_xm_is(r: Result[XmInfo, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return str_eq(r.error, want);
}

fn err_s3m_is(r: Result[S3mInfo, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return str_eq(r.error, want);
}

fn err_it_is(r: Result[ItInfo, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return str_eq(r.error, want);
}

fn err_nsf_is(r: Result[NsfInfo, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return str_eq(r.error, want);
}

// --------------------------------------------------
//  MIDI fixtures
// --------------------------------------------------

fn midi_hdr(fmt: Int, ntrks: Int, div: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  push_str_bytes(&mut v, "MThd");
  push_be32(&mut v, 6);
  push_be16(&mut v, fmt);
  push_be16(&mut v, ntrks);
  push_be16(&mut v, div);
  return v;
}

fn midi_track(evs: &Vec[UInt8]) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  push_str_bytes(&mut v, "MTrk");
  push_be32(&mut v, evs.len());
  append_bytes(&mut v, evs);
  return v;
}

fn midi_min_events() -> Vec[UInt8] {
  var e = Vec[UInt8].new();
  e.push(0 as UInt8);
  e.push(255 as UInt8);
  e.push(81 as UInt8);
  e.push(3 as UInt8);
  e.push(7 as UInt8);
  e.push(161 as UInt8);
  e.push(32 as UInt8);
  e.push(0 as UInt8);
  e.push(255 as UInt8);
  e.push(47 as UInt8);
  e.push(0 as UInt8);
  return e;
}

fn midi_full_events() -> Vec[UInt8] {
  var e = Vec[UInt8].new();
  e.push(0 as UInt8);
  e.push(255 as UInt8);
  e.push(81 as UInt8);
  e.push(3 as UInt8);
  e.push(7 as UInt8);
  e.push(161 as UInt8);
  e.push(32 as UInt8);
  e.push(0 as UInt8);
  e.push(255 as UInt8);
  e.push(3 as UInt8);
  e.push(4 as UInt8);
  push_str_bytes(&mut e, "Test");
  e.push(0 as UInt8);
  e.push(144 as UInt8);
  e.push(60 as UInt8);
  e.push(64 as UInt8);
  e.push(0 as UInt8);
  e.push(62 as UInt8);
  e.push(80 as UInt8);
  e.push(96 as UInt8);
  e.push(128 as UInt8);
  e.push(60 as UInt8);
  e.push(64 as UInt8);
  e.push(0 as UInt8);
  e.push(240 as UInt8);
  e.push(2 as UInt8);
  e.push(126 as UInt8);
  e.push(247 as UInt8);
  e.push(0 as UInt8);
  e.push(255 as UInt8);
  e.push(47 as UInt8);
  e.push(0 as UInt8);
  return e;
}

fn midi_minimal() -> Vec[UInt8] {
  return concat_bytes(&midi_hdr(0, 1, 96), &midi_track(&midi_min_events()));
}

// --------------------------------------------------
//  MOD fixture
// --------------------------------------------------

fn mod_fixture(sig: Str, channels: Int, song_len: Int, max_order: Int, pat_count: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  push_str_bytes(&mut v, "Test MOD");
  push_zeros(&mut v, 12);
  push_str_bytes(&mut v, "Sample");
  push_zeros(&mut v, 16);
  push_be16(&mut v, 8);
  v.push(0 as UInt8);
  v.push(64 as UInt8);
  push_be16(&mut v, 0);
  push_be16(&mut v, 2);
  push_zeros(&mut v, 30 * 30);
  v.push(song_len as UInt8);
  v.push(0 as UInt8);
  var i = 0;
  while i < 128 {
    if i < song_len {
      var e = 0;
      if max_order > 0 {
        e = i % (max_order + 1);
      }
      v.push(e as UInt8);
    } else {
      v.push(0 as UInt8);
    }
    i = i + 1;
  }
  push_str_bytes(&mut v, sig);
  let pat_size = 64 * channels * 4;
  var z = 0;
  while z < pat_count * pat_size {
    v.push(0 as UInt8);
    z = z + 1;
  }
  if pat_count > 0 {
    v[1084] = 1 as UInt8;
    v[1085] = 172 as UInt8;
    v[1086] = 16 as UInt8;
  }
  return v;
}

// --------------------------------------------------
//  XM fixture
// --------------------------------------------------

fn xm_fixture(song_len: Int, pats: Int, rows0: Int, samples: Int, sample_len: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  push_str_bytes(&mut v, "Extended Module: ");
  push_str_bytes(&mut v, "XIOM XM");
  push_zeros(&mut v, 13);
  v.push(26 as UInt8);
  push_str_bytes(&mut v, "XIOM Tool");
  push_zeros(&mut v, 11);
  push_le16(&mut v, 260);
  push_le32(&mut v, 276);
  push_le16(&mut v, song_len);
  push_le16(&mut v, 0);
  push_le16(&mut v, 4);
  push_le16(&mut v, pats);
  push_le16(&mut v, 1);
  push_le16(&mut v, 1);
  push_le16(&mut v, 6);
  push_le16(&mut v, 125);
  var i = 0;
  while i < 256 {
    if i < song_len {
      v.push((i % pats) as UInt8);
    } else {
      v.push(0 as UInt8);
    }
    i = i + 1;
  }
  i = 0;
  while i < pats {
    var r = 32;
    if i == 0 {
      r = rows0;
    }
    push_le32(&mut v, 9);
    v.push(1 as UInt8);
    push_le16(&mut v, r);
    push_le16(&mut v, 2);
    v.push(0 as UInt8);
    v.push(0 as UInt8);
    i = i + 1;
  }
  push_le32(&mut v, 29);
  push_zeros(&mut v, 23);
  push_le16(&mut v, samples);
  var s = 0;
  while s < samples {
    push_le32(&mut v, sample_len);
    push_le32(&mut v, 0);
    push_le32(&mut v, 0);
    v.push(64 as UInt8);
    v.push(0 as UInt8);
    v.push(0 as UInt8);
    v.push(128 as UInt8);
    v.push(0 as UInt8);
    v.push(0 as UInt8);
    push_zeros(&mut v, 22);
    var d = 0;
    while d < sample_len {
      v.push(17 as UInt8);
      d = d + 1;
    }
    s = s + 1;
  }
  return v;
}

// --------------------------------------------------
//  S3M fixture
// --------------------------------------------------

fn s3m_fixture(ordnum: Int, insnum: Int, patnum: Int, pat_ptr: Int, pat_rows: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  push_str_bytes(&mut v, "S3M Test");
  push_zeros(&mut v, 20);
  v.push(26 as UInt8);
  v.push(16 as UInt8);
  v.push(0 as UInt8);
  v.push(0 as UInt8);
  push_le16(&mut v, ordnum);
  push_le16(&mut v, insnum);
  push_le16(&mut v, patnum);
  push_le16(&mut v, 0);
  push_le16(&mut v, 4864);
  push_le16(&mut v, 2);
  push_str_bytes(&mut v, "SCRM");
  v.push(64 as UInt8);
  v.push(6 as UInt8);
  v.push(125 as UInt8);
  v.push(176 as UInt8);
  v.push(0 as UInt8);
  v.push(0 as UInt8);
  push_zeros(&mut v, 8);
  push_zeros(&mut v, 32);
  var i = 0;
  while i < ordnum {
    if i < 2 {
      v.push(i as UInt8);
    } else {
      v.push(0 as UInt8);
    }
    i = i + 1;
  }
  i = 0;
  while i < insnum {
    push_le16(&mut v, 0);
    i = i + 1;
  }
  i = 0;
  while i < patnum {
    if i == 0 || pat_ptr == 0 {
      push_le16(&mut v, 0);
    } else {
      push_le16(&mut v, pat_ptr);
    }
    i = i + 1;
  }
  if pat_ptr > 0 {
    let target = pat_ptr * 16;
    while v.len() < target {
      v.push(0 as UInt8);
    }
    push_le16(&mut v, 4);
    push_le16(&mut v, pat_rows);
    v.push(0 as UInt8);
    v.push(0 as UInt8);
  }
  return v;
}

// --------------------------------------------------
//  IT fixture
// --------------------------------------------------

fn it_fixture(ordnum: Int, patnum: Int, pat_ptr: Int, pat_rows: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  push_str_bytes(&mut v, "IMPM");
  push_str_bytes(&mut v, "IT Test");
  push_zeros(&mut v, 19);
  push_zeros(&mut v, 2);
  push_le16(&mut v, ordnum);
  push_le16(&mut v, 0);
  push_le16(&mut v, 0);
  push_le16(&mut v, patnum);
  push_le16(&mut v, 532);
  push_le16(&mut v, 512);
  push_le16(&mut v, 0);
  push_le16(&mut v, 0);
  v.push(64 as UInt8);
  v.push(48 as UInt8);
  v.push(6 as UInt8);
  v.push(125 as UInt8);
  v.push(128 as UInt8);
  v.push(0 as UInt8);
  push_le16(&mut v, 0);
  push_le32(&mut v, 0);
  push_le32(&mut v, 0);
  push_zeros(&mut v, 64);
  push_zeros(&mut v, 64);
  var i = 0;
  while i < ordnum {
    if i == 0 {
      v.push(0 as UInt8);
    } else {
      v.push(254 as UInt8);
    }
    i = i + 1;
  }
  i = 0;
  while i < patnum {
    push_le32(&mut v, pat_ptr);
    i = i + 1;
  }
  if pat_ptr > 0 {
    while v.len() < pat_ptr {
      v.push(0 as UInt8);
    }
    push_le32(&mut v, 8);
    push_le16(&mut v, pat_rows);
    push_le16(&mut v, 0);
  }
  return v;
}

// --------------------------------------------------
//  NSF fixture
// --------------------------------------------------

fn nsf_fixture() -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  push_str_bytes(&mut v, "NESM");
  v.push(26 as UInt8);
  v.push(1 as UInt8);
  v.push(2 as UInt8);
  v.push(1 as UInt8);
  push_le16(&mut v, 32768);
  push_le16(&mut v, 32768);
  push_le16(&mut v, 32771);
  push_str_bytes(&mut v, "Test Song");
  push_zeros(&mut v, 23);
  push_str_bytes(&mut v, "Tester");
  push_zeros(&mut v, 26);
  push_str_bytes(&mut v, "2026 XIOM");
  push_zeros(&mut v, 23);
  push_le16(&mut v, 16577);
  var i = 0;
  while i < 8 {
    v.push(i as UInt8);
    i = i + 1;
  }
  push_le16(&mut v, 20000);
  v.push(1 as UInt8);
  v.push(0 as UInt8);
  push_zeros(&mut v, 4);
  var d = 0;
  while d < 16 {
    v.push(170 as UInt8);
    d = d + 1;
  }
  return v;
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  let data = midi_minimal();
  let pr = midi_parse(&data);
  if !pr.is_ok { return assert(false, "MIDI minimal format-0 fields"); }
  let m = pr.value;
  var ok = true;
  if m.format != 0 { ok = false; }
  if m.ntrks != 1 { ok = false; }
  if m.division != 96 { ok = false; }
  if m.ppq != 96 { ok = false; }
  if m.smpte { ok = false; }
  if m.total_events != 2 { ok = false; }
  if m.meta_events != 2 { ok = false; }
  if m.end_of_tracks != 1 { ok = false; }
  if m.first_tempo_us != 500000 { ok = false; }
  if m.ticks != 0 { ok = false; }
  let smpte_hdr = midi_hdr(0, 1, 59176);
  let smpte_data = concat_bytes(&smpte_hdr, &midi_track(&midi_min_events()));
  let sr = midi_parse(&smpte_data);
  if !sr.is_ok { ok = false; } else {
    let sm = sr.value;
    if !sm.smpte { ok = false; }
    if sm.smpte_fps != -25 { ok = false; }
    if sm.smpte_tpf != 40 { ok = false; }
    if sm.ppq != 0 { ok = false; }
  }
  return assert(ok, "MIDI minimal format-0 fields");
}

fn t2() -> TestResult {
  let data = concat_bytes(&midi_hdr(1, 1, 96), &midi_track(&midi_full_events()));
  let pr = midi_parse(&data);
  if !pr.is_ok { return assert(false, "MIDI full event set aggregates"); }
  let m = pr.value;
  var ok = true;
  if m.format != 1 { ok = false; }
  if m.total_events != 7 { ok = false; }
  if m.channel_events != 3 { ok = false; }
  if m.meta_events != 3 { ok = false; }
  if m.sysex_events != 1 { ok = false; }
  if m.note_ons != 2 { ok = false; }
  if m.end_of_tracks != 1 { ok = false; }
  if m.first_tempo_us != 500000 { ok = false; }
  if m.ticks != 96 { ok = false; }
  if !str_eq(m.track_name, "Test") { ok = false; }
  return assert(ok, "MIDI full event set aggregates");
}

fn t3() -> TestResult {
  var e = Vec[UInt8].new();
  push_varlen(&mut e, 0);
  e.push(144 as UInt8); e.push(60 as UInt8); e.push(64 as UInt8);
  push_varlen(&mut e, 127);
  e.push(144 as UInt8); e.push(60 as UInt8); e.push(64 as UInt8);
  push_varlen(&mut e, 128);
  e.push(144 as UInt8); e.push(60 as UInt8); e.push(64 as UInt8);
  push_varlen(&mut e, 16383);
  e.push(144 as UInt8); e.push(60 as UInt8); e.push(64 as UInt8);
  push_varlen(&mut e, 16384);
  e.push(144 as UInt8); e.push(60 as UInt8); e.push(64 as UInt8);
  e.push(0 as UInt8);
  e.push(255 as UInt8); e.push(47 as UInt8); e.push(0 as UInt8);
  let data = concat_bytes(&midi_hdr(0, 1, 96), &midi_track(&e));
  let pr = midi_parse(&data);
  if !pr.is_ok { return assert(false, "MIDI varlen delta boundaries"); }
  let m = pr.value;
  var ok = true;
  if m.ticks != 33022 { ok = false; }
  if m.note_ons != 5 { ok = false; }
  if m.channel_events != 5 { ok = false; }
  return assert(ok, "MIDI varlen delta boundaries");
}

fn t4() -> TestResult {
  let empty = Vec[UInt8].new();
  let short_buf = repeat_byte(65, 10);
  let bad_magic = set_byte(&midi_minimal(), 0, 88);
  let short_chunk = set_be32(&midi_minimal(), 4, 5);
  let bad_len = set_be32(&midi_minimal(), 4, 1000);
  var ok = err_midi_is(midi_parse(&empty), "midi: empty input");
  if !err_midi_is(midi_parse(&short_buf), "midi: truncated header") { ok = false; }
  if !err_midi_is(midi_parse(&bad_magic), "midi: bad MThd magic") { ok = false; }
  if !err_midi_is(midi_parse(&short_chunk), "midi: short header chunk") { ok = false; }
  if !err_midi_is(midi_parse(&bad_len), "midi: truncated header") { ok = false; }
  return assert(ok, "MIDI header errors: empty, short, magic, chunk length");
}

fn t5() -> TestResult {
  let m0 = midi_minimal();
  let bad_format = set_be16(&m0, 8, 3);
  let zero_tracks = set_be16(&m0, 10, 0);
  let zero_div = set_be16(&m0, 12, 0);
  var e_bad_status = Vec[UInt8].new();
  e_bad_status.push(0 as UInt8);
  e_bad_status.push(241 as UInt8);
  let bad_status = concat_bytes(&midi_hdr(0, 1, 96), &midi_track(&e_bad_status));
  var e_running = Vec[UInt8].new();
  e_running.push(0 as UInt8);
  e_running.push(60 as UInt8);
  e_running.push(64 as UInt8);
  let bad_running = concat_bytes(&midi_hdr(0, 1, 96), &midi_track(&e_running));
  var e_varlen = Vec[UInt8].new();
  e_varlen.push(128 as UInt8);
  e_varlen.push(128 as UInt8);
  e_varlen.push(128 as UInt8);
  e_varlen.push(128 as UInt8);
  e_varlen.push(0 as UInt8);
  let bad_varlen = concat_bytes(&midi_hdr(0, 1, 96), &midi_track(&e_varlen));
  var e_trunc = Vec[UInt8].new();
  e_trunc.push(0 as UInt8);
  let trunc_ev = concat_bytes(&midi_hdr(0, 1, 96), &midi_track(&e_trunc));
  let overrun = set_be32(&midi_minimal(), 18, 1000);
  let missing = set_be16(&m0, 10, 2);
  let trailing = concat_bytes(&m0, &repeat_byte(0, 1));
  var ok = err_midi_is(midi_parse(&bad_format), "midi: bad format");
  if !err_midi_is(midi_parse(&zero_tracks), "midi: zero tracks") { ok = false; }
  if !err_midi_is(midi_parse(&zero_div), "midi: bad division") { ok = false; }
  if !err_midi_is(midi_parse(&bad_status), "midi: bad status") { ok = false; }
  if !err_midi_is(midi_parse(&bad_running), "midi: bad running status") { ok = false; }
  if !err_midi_is(midi_parse(&bad_varlen), "midi: bad varlen") { ok = false; }
  if !err_midi_is(midi_parse(&trunc_ev), "midi: truncated event") { ok = false; }
  if !err_midi_is(midi_parse(&overrun), "midi: track chunk overrun") { ok = false; }
  if !err_midi_is(midi_parse(&missing), "midi: missing track chunk") { ok = false; }
  if !err_midi_is(midi_parse(&trailing), "midi: trailing data") { ok = false; }
  return assert(ok, "MIDI event/stream errors");
}

fn t6() -> TestResult {
  let data = mod_fixture("M.K.", 4, 1, 0, 1);
  let pr = mod_parse(&data);
  if !pr.is_ok { return assert(false, "MOD 4-channel header and statistics"); }
  let m = pr.value;
  var ok = true;
  if !str_eq(m.title, "Test MOD") { ok = false; }
  if !str_eq(m.signature, "M.K.") { ok = false; }
  if m.channels != 4 { ok = false; }
  if m.song_length != 1 { ok = false; }
  if m.restart != 0 { ok = false; }
  if m.patterns != 1 { ok = false; }
  if m.order.len() != 1 { ok = false; }
  if m.sample_count != 1 { ok = false; }
  if m.sample_bytes != 16 { ok = false; }
  if m.cells != 256 { ok = false; }
  if m.notes != 1 { ok = false; }
  if m.instruments != 1 { ok = false; }
  return assert(ok, "MOD 4-channel header and statistics");
}

fn t7() -> TestResult {
  let data = mod_fixture("6CHN", 6, 2, 1, 2);
  let pr = mod_parse(&data);
  if !pr.is_ok { return assert(false, "MOD 6-channel signature and pattern geometry"); }
  let m = pr.value;
  var ok = true;
  if !str_eq(m.signature, "6CHN") { ok = false; }
  if m.channels != 6 { ok = false; }
  if m.patterns != 2 { ok = false; }
  if m.order.len() != 2 { ok = false; }
  let o0: Int = m.order[0];
  let o1: Int = m.order[1];
  if o0 != 0 { ok = false; }
  if o1 != 1 { ok = false; }
  if m.cells != 768 { ok = false; }
  let data8 = mod_fixture("8CHN", 8, 1, 0, 1);
  if !mod_is_valid(&data8) { ok = false; }
  return assert(ok, "MOD 6-channel signature and pattern geometry");
}

fn t8() -> TestResult {
  let good = mod_fixture("M.K.", 4, 1, 0, 1);
  let short_buf = repeat_byte(0, 100);
  let bad_sig = mod_fixture("XXXX", 4, 1, 0, 1);
  let zero_len = set_byte(&good, 950, 0);
  let big_order = set_byte(&good, 952, 200);
  let cut = truncate(&good, 1084 + 512);
  var ok = err_mod_is(mod_parse(&short_buf), "mod: truncated header");
  if !err_mod_is(mod_parse(&bad_sig), "mod: bad signature") { ok = false; }
  if !err_mod_is(mod_parse(&zero_len), "mod: zero song length") { ok = false; }
  if !err_mod_is(mod_parse(&big_order), "mod: bad order entry") { ok = false; }
  if !err_mod_is(mod_parse(&cut), "mod: truncated pattern data") { ok = false; }
  return assert(ok, "MOD error catalog");
}

fn t9() -> TestResult {
  let data = xm_fixture(3, 2, 64, 0, 0);
  let pr = xm_parse(&data);
  if !pr.is_ok { return assert(false, "XM header fields"); }
  let m = pr.value;
  var ok = true;
  if !str_eq(m.name, "XIOM XM") { ok = false; }
  if !str_eq(m.tracker, "XIOM Tool") { ok = false; }
  if m.version != 260 { ok = false; }
  if m.header_size != 276 { ok = false; }
  if m.song_length != 3 { ok = false; }
  if m.restart != 0 { ok = false; }
  if m.channels != 4 { ok = false; }
  if m.patterns != 2 { ok = false; }
  if m.instruments != 1 { ok = false; }
  if m.flags != 1 { ok = false; }
  if m.tempo != 6 { ok = false; }
  if m.bpm != 125 { ok = false; }
  if m.order.len() != 3 { ok = false; }
  let o0: Int = m.order[0];
  let o1: Int = m.order[1];
  let o2: Int = m.order[2];
  if o0 != 0 { ok = false; }
  if o1 != 1 { ok = false; }
  if o2 != 0 { ok = false; }
  return assert(ok, "XM header fields");
}

fn t10() -> TestResult {
  let data = xm_fixture(2, 2, 64, 0, 0);
  let pr = xm_parse(&data);
  if !pr.is_ok { return assert(false, "XM pattern and instrument geometry"); }
  let m = pr.value;
  var ok = true;
  if m.pattern_rows.len() != 2 { ok = false; }
  if m.pattern_data.len() != 2 { ok = false; }
  let r0: Int = m.pattern_rows[0];
  let r1: Int = m.pattern_rows[1];
  let d0: Int = m.pattern_data[0];
  let d1: Int = m.pattern_data[1];
  if r0 != 64 { ok = false; }
  if r1 != 32 { ok = false; }
  if d0 != 2 { ok = false; }
  if d1 != 2 { ok = false; }
  if m.instrument_bytes != 29 { ok = false; }
  if m.sample_count != 0 { ok = false; }
  if m.sample_bytes != 0 { ok = false; }
  let sampled = xm_fixture(1, 1, 64, 2, 4);
  let spr = xm_parse(&sampled);
  if !spr.is_ok { ok = false; } else {
    let sm = spr.value;
    if sm.instrument_bytes != 29 { ok = false; }
    if sm.sample_count != 2 { ok = false; }
    if sm.sample_bytes != 8 { ok = false; }
  }
  return assert(ok, "XM pattern and instrument geometry");
}

fn t11() -> TestResult {
  let good = xm_fixture(2, 2, 64, 0, 0);
  let empty = Vec[UInt8].new();
  let short_buf = repeat_byte(0, 30);
  let bad_magic = set_byte(&good, 0, 88);
  let bad_marker = set_byte(&good, 37, 0);
  let bad_hsize = set_le32(&good, 60, 100);
  let bad_channels = set_le16(&good, 68, 0);
  var ok = err_xm_is(xm_parse(&empty), "xm: empty input");
  if !err_xm_is(xm_parse(&short_buf), "xm: truncated header") { ok = false; }
  if !err_xm_is(xm_parse(&bad_magic), "xm: bad magic") { ok = false; }
  if !err_xm_is(xm_parse(&bad_marker), "xm: missing 0x1A marker") { ok = false; }
  if !err_xm_is(xm_parse(&bad_hsize), "xm: bad header size") { ok = false; }
  if !err_xm_is(xm_parse(&bad_channels), "xm: bad channel count") { ok = false; }
  return assert(ok, "XM header error catalog");
}

fn t12() -> TestResult {
  let good = xm_fixture(2, 2, 64, 0, 0);
  let bad_order = set_byte(&good, 80, 2);
  let bad_tempo = set_le16(&good, 76, 0);
  let bad_bpm = set_le16(&good, 78, 20);
  let bad_rows = set_le16(&good, 341, 0);
  let cut_pattern = truncate(&good, 340);
  let trailing = concat_bytes(&good, &repeat_byte(0, 1));
  let bad_instrument = set_le32(&good, 358, 10);
  var ok = err_xm_is(xm_parse(&bad_order), "xm: bad order entry");
  if !err_xm_is(xm_parse(&bad_tempo), "xm: bad tempo") { ok = false; }
  if !err_xm_is(xm_parse(&bad_bpm), "xm: bad bpm") { ok = false; }
  if !err_xm_is(xm_parse(&bad_rows), "xm: bad pattern rows") { ok = false; }
  if !err_xm_is(xm_parse(&cut_pattern), "xm: truncated pattern header") { ok = false; }
  if !err_xm_is(xm_parse(&trailing), "xm: trailing data") { ok = false; }
  if !err_xm_is(xm_parse(&bad_instrument), "xm: bad instrument size") { ok = false; }
  return assert(ok, "XM pattern/instrument error catalog");
}

fn t13() -> TestResult {
  let data = s3m_fixture(2, 1, 2, 0, 64);
  let pr = s3m_parse(&data);
  if !pr.is_ok { return assert(false, "S3M header, orders and null patterns"); }
  let m = pr.value;
  var ok = true;
  if !str_eq(m.name, "S3M Test") { ok = false; }
  if m.ordnum != 2 { ok = false; }
  if m.insnum != 1 { ok = false; }
  if m.patnum != 2 { ok = false; }
  if m.cwtv != 4864 { ok = false; }
  if m.ffi != 2 { ok = false; }
  if m.global_volume != 64 { ok = false; }
  if m.initial_speed != 6 { ok = false; }
  if m.initial_tempo != 125 { ok = false; }
  if m.master_volume != 176 { ok = false; }
  if m.order.len() != 2 { ok = false; }
  let o0: Int = m.order[0];
  let o1: Int = m.order[1];
  if o0 != 0 { ok = false; }
  if o1 != 1 { ok = false; }
  if m.pattern_rows.len() != 2 { ok = false; }
  let r0: Int = m.pattern_rows[0];
  let r1: Int = m.pattern_rows[1];
  let p0: Int = m.pattern_packed[0];
  let p1: Int = m.pattern_packed[1];
  if r0 != 64 { ok = false; }
  if r1 != 64 { ok = false; }
  if p0 != 0 { ok = false; }
  if p1 != 0 { ok = false; }
  return assert(ok, "S3M header, orders and null patterns");
}

fn t14() -> TestResult {
  let data = s3m_fixture(2, 1, 2, 7, 32);
  let pr = s3m_parse(&data);
  if !pr.is_ok { return assert(false, "S3M paragraph pattern pointer"); }
  let m = pr.value;
  var ok = true;
  let r0: Int = m.pattern_rows[0];
  let r1: Int = m.pattern_rows[1];
  let p1: Int = m.pattern_packed[1];
  if r0 != 64 { ok = false; }
  if r1 != 32 { ok = false; }
  if p1 != 4 { ok = false; }
  return assert(ok, "S3M paragraph pattern pointer");
}

fn t15() -> TestResult {
  let good = s3m_fixture(2, 1, 2, 7, 32);
  let empty = Vec[UInt8].new();
  let short_buf = repeat_byte(0, 40);
  let bad_marker = set_byte(&good, 28, 0);
  let bad_type = set_byte(&good, 29, 0);
  let bad_magic = set_byte(&good, 44, 0);
  let zero_orders = set_le16(&good, 32, 0);
  let bad_tempo = set_byte(&good, 50, 10);
  let cut_tables = truncate(&good, 100);
  let bad_ptr = set_le16(&good, 100, 200);
  let bad_rows = set_le16(&good, 114, 0);
  var ok = err_s3m_is(s3m_parse(&empty), "s3m: empty input");
  if !err_s3m_is(s3m_parse(&short_buf), "s3m: truncated header") { ok = false; }
  if !err_s3m_is(s3m_parse(&bad_marker), "s3m: missing 0x1A marker") { ok = false; }
  if !err_s3m_is(s3m_parse(&bad_type), "s3m: bad file type") { ok = false; }
  if !err_s3m_is(s3m_parse(&bad_magic), "s3m: bad SCRM magic") { ok = false; }
  if !err_s3m_is(s3m_parse(&zero_orders), "s3m: bad order count") { ok = false; }
  if !err_s3m_is(s3m_parse(&bad_tempo), "s3m: bad initial tempo") { ok = false; }
  if !err_s3m_is(s3m_parse(&cut_tables), "s3m: truncated tables") { ok = false; }
  if !err_s3m_is(s3m_parse(&bad_ptr), "s3m: bad pattern pointer") { ok = false; }
  if !err_s3m_is(s3m_parse(&bad_rows), "s3m: bad pattern rows") { ok = false; }
  return assert(ok, "S3M error catalog");
}

fn t16() -> TestResult {
  let data = it_fixture(2, 1, 0, 64);
  let pr = it_parse(&data);
  if !pr.is_ok { return assert(false, "IT header and null pattern"); }
  let m = pr.value;
  var ok = true;
  if !str_eq(m.name, "IT Test") { ok = false; }
  if m.ordnum != 2 { ok = false; }
  if m.insnum != 0 { ok = false; }
  if m.smpnum != 0 { ok = false; }
  if m.patnum != 1 { ok = false; }
  if m.cwtv != 532 { ok = false; }
  if m.cmwt != 512 { ok = false; }
  if m.global_volume != 64 { ok = false; }
  if m.mix_volume != 48 { ok = false; }
  if m.initial_speed != 6 { ok = false; }
  if m.initial_tempo != 125 { ok = false; }
  if m.order.len() != 2 { ok = false; }
  let o0: Int = m.order[0];
  let o1: Int = m.order[1];
  if o0 != 0 { ok = false; }
  if o1 != 254 { ok = false; }
  let r0: Int = m.pattern_rows[0];
  if r0 != 64 { ok = false; }
  return assert(ok, "IT header and null pattern");
}

fn t17() -> TestResult {
  let data = it_fixture(2, 1, 200, 32);
  let pr = it_parse(&data);
  if !pr.is_ok { return assert(false, "IT pattern pointer geometry"); }
  let m = pr.value;
  var ok = true;
  let r0: Int = m.pattern_rows[0];
  let p0: Int = m.pattern_packed[0];
  if r0 != 32 { ok = false; }
  if p0 != 8 { ok = false; }
  return assert(ok, "IT pattern pointer geometry");
}

fn t18() -> TestResult {
  let good = it_fixture(2, 1, 200, 32);
  let empty = Vec[UInt8].new();
  let short_buf = repeat_byte(0, 100);
  let bad_magic = set_byte(&good, 0, 88);
  let zero_orders = set_le16(&good, 32, 0);
  let bad_gv = set_byte(&good, 48, 200);
  let bad_tempo = set_byte(&good, 51, 10);
  let cut_tables = truncate(&good, 195);
  let bad_order = set_byte(&good, 192, 1);
  let bad_ptr = set_le32(&good, 194, 204);
  let bad_rows = set_le16(&good, 204, 0);
  var ok = err_it_is(it_parse(&empty), "it: empty input");
  if !err_it_is(it_parse(&short_buf), "it: truncated header") { ok = false; }
  if !err_it_is(it_parse(&bad_magic), "it: bad IMPM magic") { ok = false; }
  if !err_it_is(it_parse(&zero_orders), "it: bad order count") { ok = false; }
  if !err_it_is(it_parse(&bad_gv), "it: bad global volume") { ok = false; }
  if !err_it_is(it_parse(&bad_tempo), "it: bad initial tempo") { ok = false; }
  if !err_it_is(it_parse(&cut_tables), "it: truncated tables") { ok = false; }
  if !err_it_is(it_parse(&bad_order), "it: bad order entry") { ok = false; }
  if !err_it_is(it_parse(&bad_ptr), "it: bad pattern pointer") { ok = false; }
  if !err_it_is(it_parse(&bad_rows), "it: bad pattern rows") { ok = false; }
  return assert(ok, "IT error catalog");
}

fn t19() -> TestResult {
  let data = nsf_fixture();
  let pr = nsf_parse(&data);
  if !pr.is_ok { return assert(false, "NSF header fields"); }
  let m = pr.value;
  var ok = true;
  if m.version != 1 { ok = false; }
  if m.total_songs != 2 { ok = false; }
  if m.starting_song != 1 { ok = false; }
  if m.load_address != 32768 { ok = false; }
  if m.init_address != 32768 { ok = false; }
  if m.play_address != 32771 { ok = false; }
  if !str_eq(m.name, "Test Song") { ok = false; }
  if !str_eq(m.artist, "Tester") { ok = false; }
  if !str_eq(m.copyright, "2026 XIOM") { ok = false; }
  if m.ntsc_speed != 16577 { ok = false; }
  if m.pal_speed != 20000 { ok = false; }
  if m.pal_flag != 1 { ok = false; }
  if m.chip_flags != 0 { ok = false; }
  if m.banks.len() != 8 { ok = false; }
  let b7: Int = m.banks[7];
  if b7 != 7 { ok = false; }
  if m.data_size != 16 { ok = false; }
  return assert(ok, "NSF header fields");
}

fn t20() -> TestResult {
  let good = nsf_fixture();
  let empty = Vec[UInt8].new();
  let short_buf = repeat_byte(0, 50);
  let bad_magic = set_byte(&good, 0, 88);
  let bad_marker = set_byte(&good, 4, 0);
  let bad_version = set_byte(&good, 5, 3);
  let zero_songs = set_byte(&good, 6, 0);
  let bad_start = set_byte(&good, 7, 2);
  var ok = err_nsf_is(nsf_parse(&empty), "nsf: empty input");
  if !err_nsf_is(nsf_parse(&short_buf), "nsf: truncated header") { ok = false; }
  if !err_nsf_is(nsf_parse(&bad_magic), "nsf: bad NESM magic") { ok = false; }
  if !err_nsf_is(nsf_parse(&bad_marker), "nsf: bad NESM magic") { ok = false; }
  if !err_nsf_is(nsf_parse(&bad_version), "nsf: bad version") { ok = false; }
  if !err_nsf_is(nsf_parse(&zero_songs), "nsf: zero songs") { ok = false; }
  if !err_nsf_is(nsf_parse(&bad_start), "nsf: bad starting song") { ok = false; }
  return assert(ok, "NSF error catalog");
}

fn t21() -> TestResult {
  var ok = true;
  if chiptune_count() != 40 { ok = false; }
  let e0 = chiptune_entry(0);
  if !str_eq(e0.id, "nsf") { ok = false; }
  if e0.magic_offset != 0 { ok = false; }
  if e0.magic.len() != 5 { ok = false; }
  let e1 = chiptune_entry(1);
  if !str_eq(e1.id, "mod") { ok = false; }
  if e1.magic_offset != 1080 { ok = false; }
  if e1.magic.len() != 4 { ok = false; }
  let e2 = chiptune_entry(2);
  if !str_eq(e2.id, "xm") { ok = false; }
  let e3 = chiptune_entry(3);
  if !str_eq(e3.id, "s3m") { ok = false; }
  if e3.magic_offset != 44 { ok = false; }
  let e4 = chiptune_entry(4);
  if !str_eq(e4.id, "it") { ok = false; }
  let e25 = chiptune_entry(25);
  if !str_eq(e25.id, "669") { ok = false; }
  let e39 = chiptune_entry(39);
  if !str_eq(e39.id, "sc68") { ok = false; }
  let e40 = chiptune_entry(40);
  if !str_eq(e40.id, "") { ok = false; }
  if e40.magic.len() != 0 { ok = false; }
  let em1 = chiptune_entry(-1);
  if !str_eq(em1.id, "") { ok = false; }
  return assert(ok, "chiptune registry metadata and sentinels");
}

fn t22() -> TestResult {
  var ok = true;
  var i = 0;
  while i < chiptune_count() {
    let e = chiptune_entry(i);
    let off = e.magic_offset;
    let m = e.magic.len();
    var buf = Vec[UInt8].new();
    push_zeros(&mut buf, off + m + 2);
    var k = 0;
    while k < m {
      buf[off + k] = e.magic[k];
      k = k + 1;
    }
    let hit = chiptune_detect(&buf);
    if hit != i { ok = false; }
    let id = chiptune_detect_id(&buf);
    if !str_eq(id, e.id) { ok = false; }
    i = i + 1;
  }
  return assert(ok, "chiptune registry full magic round-trip");
}

fn t23() -> TestResult {
  let nsf = nsf_fixture();
  let mod = mod_fixture("M.K.", 4, 1, 0, 1);
  let xm = xm_fixture(2, 2, 64, 0, 0);
  let s3m = s3m_fixture(2, 1, 2, 7, 32);
  let it = it_fixture(2, 1, 200, 32);
  let mid = midi_minimal();
  var ok = true;
  if chiptune_detect(&nsf) != 0 { ok = false; }
  if chiptune_detect(&mod) != 1 { ok = false; }
  if chiptune_detect(&xm) != 2 { ok = false; }
  if chiptune_detect(&s3m) != 3 { ok = false; }
  if chiptune_detect(&it) != 4 { ok = false; }
  if chiptune_detect(&mid) != 5 { ok = false; }
  return assert(ok, "chiptune detection on module headers");
}

fn t24() -> TestResult {
  let empty = Vec[UInt8].new();
  let zeros = repeat_byte(0, 1200);
  var junk = Vec[UInt8].new();
  push_str_bytes(&mut junk, "hello world");
  var ok = true;
  if chiptune_detect(&empty) != -1 { ok = false; }
  if chiptune_detect(&zeros) != -1 { ok = false; }
  if chiptune_detect(&junk) != -1 { ok = false; }
  if !str_eq(chiptune_detect_id(&junk), "") { ok = false; }
  let mid = midi_minimal();
  if !str_eq(chiptune_detect_id(&mid), "mid") { ok = false; }
  return assert(ok, "chiptune rejection and detect_id");
}

fn t25() -> TestResult {
  let mid = midi_minimal();
  let mod = mod_fixture("M.K.", 4, 1, 0, 1);
  let xm = xm_fixture(2, 2, 64, 0, 0);
  let s3m = s3m_fixture(2, 1, 2, 7, 32);
  let it = it_fixture(2, 1, 200, 32);
  let nsf = nsf_fixture();
  let empty = Vec[UInt8].new();
  var ok = true;
  if !midi_is_valid(&mid) { ok = false; }
  if !mod_is_valid(&mod) { ok = false; }
  if !xm_is_valid(&xm) { ok = false; }
  if !s3m_is_valid(&s3m) { ok = false; }
  if !it_is_valid(&it) { ok = false; }
  if !nsf_is_valid(&nsf) { ok = false; }
  if midi_is_valid(&empty) { ok = false; }
  if mod_is_valid(&empty) { ok = false; }
  if xm_is_valid(&empty) { ok = false; }
  if s3m_is_valid(&empty) { ok = false; }
  if it_is_valid(&empty) { ok = false; }
  if nsf_is_valid(&empty) { ok = false; }
  if mod_is_valid(&xm) { ok = false; }
  if xm_is_valid(&mod) { ok = false; }
  if nsf_is_valid(&s3m) { ok = false; }
  return assert(ok, "per-format is_valid wrappers and cross-format rejection");
}

fn main() -> Int {
  io.println("=== xiom.audio-meta conformance tests ===");
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
  let r25 = t25();
  if r25.passed { io.println("  [PASS] " + r25.name); } else { io.println("  [FAIL] " + r25.name); failed = failed + 1; }
  if failed == 0 {
    io.println("xiom.audio-meta: all tests passed");
  } else {
    io.println("xiom.audio-meta: tests failed");
  }
  return failed;
}
