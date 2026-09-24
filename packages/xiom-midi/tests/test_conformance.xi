// XIOM -- xiom.midi conformance tests (24 checks)
// Port task: prove the pure-XIOM xiom.midi structure reader.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Covers the documented API: "MThd" magic detection, the three header
// accessors (format, track count, signed division), VLQ decoding (0, 127,
// 128, 0x0FFFFFFF, truncation, overlong), the "MTrk" chunk walk (offsets,
// lengths, count matching, bounds), event counting with running status,
// note on/off tallies (note-on velocity 0 counts as a note-off), meta and
// sysex event lengths, End of Track semantics, and the full error catalog.
// All fixtures are built in-test with byte pushes.
//
// Str values from Result errors are compared with str_compare through
// typed locals (BUG 17 discipline: `==` on Str values read from a Vec
// lowers to a pointer comparison). Raw bytes widen through `as Int`.

module midi_tests
use xiom.io; use xiom.test;
use xiom.midi;
use xiom.string;
use xiom.string.compare;

// --------------------------------------------------
//  Byte-building helpers (in-test fixtures)
// --------------------------------------------------

fn push_byte(out: &mut Vec[UInt8], v: Int) {
  out.push(v as UInt8);
}

fn push_be16(out: &mut Vec[UInt8], v: Int) {
  out.push(((v / 256) % 256) as UInt8);
  out.push((v % 256) as UInt8);
}

fn push_be32(out: &mut Vec[UInt8], v: Int) {
  out.push(((v / 16777216) % 256) as UInt8);
  out.push(((v / 65536) % 256) as UInt8);
  out.push(((v / 256) % 256) as UInt8);
  out.push((v % 256) as UInt8);
}

fn push_ascii(out: &mut Vec[UInt8], s: Str) {
  var i = 0;
  while i < s.len() {
    out.push(string.byte_at(s, i));
    i = i + 1;
  }
}

// MIDI variable-length quantity encoding of a non-negative Int (test-side
// encoder): most-significant 7-bit group first, continuation flag on all
// but the last byte.
fn push_vlq(out: &mut Vec[UInt8], v: Int) {
  var groups = Vec[Int].new();
  var n = v;
  groups.push(n % 128);
  n = n / 128;
  while n > 0 {
    groups.push(n % 128);
    n = n / 128;
  }
  var i = groups.len() - 1;
  while i >= 0 {
    let g: Int = groups[i];
    if i == 0 {
      push_byte(out, g);
    } else {
      push_byte(out, g + 128);
    }
    i = i - 1;
  }
}

fn concat2(a: Vec[UInt8], b: Vec[UInt8]) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < a.len() {
    v.push(a[i]);
    i = i + 1;
  }
  var j = 0;
  while j < b.len() {
    v.push(b[j]);
    j = j + 1;
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

// 14-byte "MThd" header: magic, length 6, format, declared track count,
// division (written as the raw unsigned 16-bit value).
fn build_header(format: Int, ntrks: Int, division: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  push_ascii(&mut out, "MThd");
  push_be32(&mut out, 6);
  push_be16(&mut out, format);
  push_be16(&mut out, ntrks);
  push_be16(&mut out, division);
  return out;
}

// "MTrk" chunk: tag, big-endian payload length, payload verbatim.
fn build_track(payload: Vec[UInt8]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  push_ascii(&mut out, "MTrk");
  push_be32(&mut out, payload.len());
  var i = 0;
  while i < payload.len() {
    out.push(payload[i]);
    i = i + 1;
  }
  return out;
}

// Basic track payload: delta 0 note-on C4 vel 64, delta 480 note-off C4,
// delta 0 End of Track. 13 bytes, so the single track chunk payload starts
// at absolute offset 14 + 8 = 22.
fn basic_payload() -> Vec[UInt8] {
  var p = Vec[UInt8].new();
  push_byte(&mut p, 0);
  push_byte(&mut p, 0x90);
  push_byte(&mut p, 0x3C);
  push_byte(&mut p, 0x40);
  push_vlq(&mut p, 480);
  push_byte(&mut p, 0x80);
  push_byte(&mut p, 0x3C);
  push_byte(&mut p, 0x40);
  push_byte(&mut p, 0);
  push_byte(&mut p, 0xFF);
  push_byte(&mut p, 0x2F);
  push_byte(&mut p, 0);
  return p;
}

// Minimal format 0 file: one track, division 480 (ticks per quarter note).
fn minimal_file() -> Vec[UInt8] {
  let h = build_header(0, 1, 480);
  let t = build_track(basic_payload());
  return concat2(h, t);
}

// Format 1 file with two tracks: track 0 has one note plus End of Track
// (8-byte payload), track 1 has a program change plus End of Track (7-byte
// payload). Chunk payloads start at offsets 22 and 38.
fn two_track_file() -> Vec[UInt8] {
  var a = Vec[UInt8].new();
  push_byte(&mut a, 0);
  push_byte(&mut a, 0x90);
  push_byte(&mut a, 0x3C);
  push_byte(&mut a, 0x40);
  push_byte(&mut a, 0);
  push_byte(&mut a, 0xFF);
  push_byte(&mut a, 0x2F);
  push_byte(&mut a, 0);
  var b = Vec[UInt8].new();
  push_byte(&mut b, 0);
  push_byte(&mut b, 0xC0);
  push_byte(&mut b, 0x05);
  push_byte(&mut b, 0);
  push_byte(&mut b, 0xFF);
  push_byte(&mut b, 0x2F);
  push_byte(&mut b, 0);
  let h = build_header(1, 2, 480);
  let ta = build_track(a);
  let tb = build_track(b);
  return concat2(concat2(h, ta), tb);
}

// A single-track file around an arbitrary payload.
fn file_with_payload(payload: Vec[UInt8]) -> Vec[UInt8] {
  let h = build_header(0, 1, 480);
  let t = build_track(payload);
  return concat2(h, t);
}

// --------------------------------------------------
//  Assertion helpers
// --------------------------------------------------

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn int_ok_is(r: Result[Int, Str], want: Int) -> Bool {
  if !r.is_ok {
    return false;
  }
  let v: Int = r.value;
  return v == want;
}

fn err_int_is(r: Result[Int, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return streq(r.error, want);
}

fn pair_is(r: Result[(Int, Int), Str], want0: Int, want1: Int) -> Bool {
  if !r.is_ok {
    return false;
  }
  let pair = r.value;
  let v0: Int = pair.0;
  let v1: Int = pair.1;
  return v0 == want0 && v1 == want1;
}

fn err_pair_is(r: Result[(Int, Int), Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return streq(r.error, want);
}

fn err_tracks_is(r: Result[MidiTracks, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return streq(r.error, want);
}

fn int_vec_is(v: &Vec[Int], idx: Int, want: Int) -> Bool {
  if idx < 0 || idx >= v.len() {
    return false;
  }
  let got: Int = v[idx];
  return got == want;
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  let full = minimal_file();
  var ok = midi_is_file(&full);
  var magic = Vec[UInt8].new();
  push_ascii(&mut magic, "MThd");
  if !midi_is_file(&magic) { ok = false; }
  let bad = set_byte(&full, 0, 88);
  if midi_is_file(&bad) { ok = false; }
  let empty = Vec[UInt8].new();
  if midi_is_file(&empty) { ok = false; }
  let short = truncate(&full, 3);
  if midi_is_file(&short) { ok = false; }
  return assert(ok, "is_file accepts the MThd tag and rejects bad magic and short input");
}

fn t2() -> TestResult {
  let h0 = build_header(0, 0, 480);
  let h1 = build_header(1, 0, 480);
  let h2 = build_header(2, 0, 480);
  let h3 = build_header(3, 0, 480);
  var ok = int_ok_is(midi_format(&h0), 0);
  if !int_ok_is(midi_format(&h1), 1) { ok = false; }
  if !int_ok_is(midi_format(&h2), 2) { ok = false; }
  if !err_int_is(midi_format(&h3), "midi: invalid format") { ok = false; }
  return assert(ok, "format reads 0/1/2 and rejects 3");
}

fn t3() -> TestResult {
  let h0 = build_header(2, 0, 480);
  let h1 = build_header(0, 1, 480);
  let h2 = build_header(0, 2, 480);
  let h255 = build_header(0, 255, 480);
  var ok = int_ok_is(midi_track_count(&h0), 0);
  if !int_ok_is(midi_track_count(&h1), 1) { ok = false; }
  if !int_ok_is(midi_track_count(&h2), 2) { ok = false; }
  if !int_ok_is(midi_track_count(&h255), 255) { ok = false; }
  return assert(ok, "track_count reads the declared header field (0/1/2/255)");
}

fn t4() -> TestResult {
  let h480 = build_header(0, 1, 480);
  let hmax = build_header(0, 1, 32767);
  let hsmpte = build_header(0, 1, 0xE728);
  let hmin = build_header(0, 1, 0x8000);
  var ok = int_ok_is(midi_division(&h480), 480);
  if !int_ok_is(midi_division(&hmax), 32767) { ok = false; }
  if !int_ok_is(midi_division(&hsmpte), -6360) { ok = false; }
  if !int_ok_is(midi_division(&hmin), -32768) { ok = false; }
  return assert(ok, "division is signed: 480, 32767, SMPTE 0xE728 = -6360, 0x8000 = -32768");
}

fn t5() -> TestResult {
  let empty = Vec[UInt8].new();
  let full = minimal_file();
  let short = truncate(&full, 13);
  let bad_magic = set_byte(&full, 0, 88);
  let bad_len = set_byte(&full, 7, 8);
  var ok = err_int_is(midi_format(&empty), "midi: truncated header");
  if !err_int_is(midi_track_count(&empty), "midi: truncated header") { ok = false; }
  if !err_int_is(midi_division(&empty), "midi: truncated header") { ok = false; }
  if !err_tracks_is(midi_track_chunks(&empty), "midi: truncated header") { ok = false; }
  if !err_int_is(midi_format(&short), "midi: truncated header") { ok = false; }
  if !err_int_is(midi_track_count(&bad_magic), "midi: bad MThd magic") { ok = false; }
  if !err_int_is(midi_division(&bad_magic), "midi: bad MThd magic") { ok = false; }
  if !err_tracks_is(midi_track_chunks(&bad_magic), "midi: bad MThd magic") { ok = false; }
  if !err_int_is(midi_format(&bad_len), "midi: bad header length") { ok = false; }
  if !err_int_is(midi_track_count(&bad_len), "midi: bad header length") { ok = false; }
  if !err_int_is(midi_division(&bad_len), "midi: bad header length") { ok = false; }
  if !err_tracks_is(midi_track_chunks(&bad_len), "midi: bad header length") { ok = false; }
  return assert(ok, "header catalog: truncated / bad magic / bad header length on every accessor");
}

fn t6() -> TestResult {
  var b0 = Vec[UInt8].new();
  push_byte(&mut b0, 0);
  var b1 = Vec[UInt8].new();
  push_byte(&mut b1, 127);
  var b2 = Vec[UInt8].new();
  push_byte(&mut b2, 0x7F);
  push_byte(&mut b2, 0x00);
  var ok = pair_is(midi_varlen(&b0, 0), 0, 1);
  if !pair_is(midi_varlen(&b1, 0), 127, 1) { ok = false; }
  if !pair_is(midi_varlen(&b2, 1), 0, 2) { ok = false; }
  return assert(ok, "varlen single-byte 0 and 127, non-zero start offset");
}

fn t7() -> TestResult {
  var b128 = Vec[UInt8].new();
  push_byte(&mut b128, 0x81);
  push_byte(&mut b128, 0x00);
  var b255 = Vec[UInt8].new();
  push_byte(&mut b255, 0x81);
  push_byte(&mut b255, 0x7F);
  var b16383 = Vec[UInt8].new();
  push_byte(&mut b16383, 0xFF);
  push_byte(&mut b16383, 0x7F);
  var b624485 = Vec[UInt8].new();
  push_byte(&mut b624485, 0xA6);
  push_byte(&mut b624485, 0x8E);
  push_byte(&mut b624485, 0x65);
  var ok = pair_is(midi_varlen(&b128, 0), 128, 2);
  if !pair_is(midi_varlen(&b255, 0), 255, 2) { ok = false; }
  if !pair_is(midi_varlen(&b16383, 0), 16383, 2) { ok = false; }
  if !pair_is(midi_varlen(&b624485, 0), 624485, 3) { ok = false; }
  return assert(ok, "varlen two- and three-byte values 128, 255, 16383, 624485");
}

fn t8() -> TestResult {
  var b = Vec[UInt8].new();
  push_byte(&mut b, 0xFF);
  push_byte(&mut b, 0xFF);
  push_byte(&mut b, 0xFF);
  push_byte(&mut b, 0x7F);
  var ok = pair_is(midi_varlen(&b, 0), 268435455, 4);
  return assert(ok, "varlen four-byte maximum 0x0FFFFFFF = 268435455");
}

fn t9() -> TestResult {
  var t1 = Vec[UInt8].new();
  push_byte(&mut t1, 0x80);
  var t2 = Vec[UInt8].new();
  push_byte(&mut t2, 0x80);
  push_byte(&mut t2, 0x80);
  var t3 = Vec[UInt8].new();
  push_byte(&mut t3, 0x80);
  push_byte(&mut t3, 0x80);
  push_byte(&mut t3, 0x80);
  var over4 = Vec[UInt8].new();
  push_byte(&mut over4, 0xFF);
  push_byte(&mut over4, 0xFF);
  push_byte(&mut over4, 0xFF);
  push_byte(&mut over4, 0xFF);
  var over5 = Vec[UInt8].new();
  push_byte(&mut over5, 0x80);
  push_byte(&mut over5, 0x80);
  push_byte(&mut over5, 0x80);
  push_byte(&mut over5, 0x80);
  push_byte(&mut over5, 0x00);
  var ok = err_pair_is(midi_varlen(&t1, -1), "midi: negative offset");
  if !err_pair_is(midi_varlen(&t1, 0), "midi: truncated varlen") { ok = false; }
  if !err_pair_is(midi_varlen(&t2, 0), "midi: truncated varlen") { ok = false; }
  if !err_pair_is(midi_varlen(&t3, 0), "midi: truncated varlen") { ok = false; }
  if !err_pair_is(midi_varlen(&t1, 5), "midi: truncated varlen") { ok = false; }
  if !err_pair_is(midi_varlen(&over4, 0), "midi: overlong varlen") { ok = false; }
  if !err_pair_is(midi_varlen(&over5, 0), "midi: overlong varlen") { ok = false; }
  return assert(ok, "varlen errors: negative offset, truncation, overlong (5-byte stream)");
}

fn t10() -> TestResult {
  let f = minimal_file();
  let r = midi_track_chunks(&f);
  if !r.is_ok {
    return assert(false, "track chunks walk: offset and declared length of the single MTrk");
  }
  let s = r.value;
  var ok = s.offsets.len() == 1 && s.lengths.len() == 1;
  if f.len() != 35 { ok = false; }
  if !int_vec_is(&s.offsets, 0, 22) { ok = false; }
  if !int_vec_is(&s.lengths, 0, 13) { ok = false; }
  return assert(ok, "track chunks walk: offset and declared length of the single MTrk");
}

fn t11() -> TestResult {
  let f = two_track_file();
  let r = midi_track_chunks(&f);
  if !r.is_ok {
    return assert(false, "two track chunks: file-order offsets 22 and 38, lengths 8 and 7");
  }
  let s = r.value;
  var ok = s.offsets.len() == 2 && s.lengths.len() == 2;
  if f.len() != 45 { ok = false; }
  if !int_vec_is(&s.offsets, 0, 22) { ok = false; }
  if !int_vec_is(&s.offsets, 1, 38) { ok = false; }
  if !int_vec_is(&s.lengths, 0, 8) { ok = false; }
  if !int_vec_is(&s.lengths, 1, 7) { ok = false; }
  return assert(ok, "two track chunks: file-order offsets 22 and 38, lengths 8 and 7");
}

fn t12() -> TestResult {
  let zero_tracks = build_header(0, 0, 480);
  let rz = midi_track_chunks(&zero_tracks);
  var ok = rz.is_ok;
  if rz.is_ok {
    let sz = rz.value;
    if sz.offsets.len() != 0 { ok = false; }
    if sz.lengths.len() != 0 { ok = false; }
  }
  let empty_payload = Vec[UInt8].new();
  let empty_track = file_with_payload(empty_payload);
  let re = midi_track_chunks(&empty_track);
  if !re.is_ok { ok = false; }
  elif re.value.lengths.len() != 1 { ok = false; }
  if !int_ok_is(midi_track_event_count(&empty_track, 0), 0) { ok = false; }
  if !pair_is(midi_note_events(&empty_track, 0), 0, 0) { ok = false; }
  return assert(ok, "zero declared tracks yield empty vectors; a zero-length chunk is accepted");
}

fn t13() -> TestResult {
  let h1 = build_header(0, 1, 480);
  var tail = Vec[UInt8].new();
  push_ascii(&mut tail, "MTr");
  let short = concat2(h1, tail);
  var badmagic = Vec[UInt8].new();
  push_ascii(&mut badmagic, "MTrX");
  push_be32(&mut badmagic, 0);
  let bad_magic = concat2(h1, badmagic);
  var huge = Vec[UInt8].new();
  push_ascii(&mut huge, "MTrk");
  push_be32(&mut huge, 100);
  let out_of_range = concat2(h1, huge);
  let mismatch_two = concat2(build_header(0, 2, 480), build_track(basic_payload()));
  let mismatch_zero = h1;
  var ok = err_tracks_is(midi_track_chunks(&short), "midi: truncated track chunk");
  if !err_tracks_is(midi_track_chunks(&bad_magic), "midi: bad track magic") { ok = false; }
  if !err_tracks_is(midi_track_chunks(&out_of_range), "midi: track chunk out of range") { ok = false; }
  if !err_tracks_is(midi_track_chunks(&mismatch_two), "midi: track count mismatch") { ok = false; }
  if !err_tracks_is(midi_track_chunks(&mismatch_zero), "midi: track count mismatch") { ok = false; }
  return assert(ok, "chunk errors: truncated header, bad magic, out of range, count mismatch");
}

fn t14() -> TestResult {
  let f = minimal_file();
  var ok = int_ok_is(midi_track_event_count(&f, 0), 3);
  if !pair_is(midi_note_events(&f, 0), 1, 1) { ok = false; }
  return assert(ok, "basic track: 3 events, 1 note-on and 1 note-off");
}

fn t15() -> TestResult {
  // Running status: the second event omits 0x90 and reuses it, with
  // velocity 0, so it is a note-off.
  var p = Vec[UInt8].new();
  push_byte(&mut p, 0);
  push_byte(&mut p, 0x90);
  push_byte(&mut p, 0x3C);
  push_byte(&mut p, 0x40);
  push_byte(&mut p, 0);
  push_byte(&mut p, 0x3C);
  push_byte(&mut p, 0x00);
  push_byte(&mut p, 0);
  push_byte(&mut p, 0xFF);
  push_byte(&mut p, 0x2F);
  push_byte(&mut p, 0);
  let f = file_with_payload(p);
  var ok = int_ok_is(midi_track_event_count(&f, 0), 3);
  if !pair_is(midi_note_events(&f, 0), 1, 1) { ok = false; }
  return assert(ok, "running status reuses 0x90; velocity 0 counts as a note-off");
}

fn t16() -> TestResult {
  // Tempo meta (FF 51 03 ...), F0 sysex with a 2-byte payload, F7 escape
  // sysex with a 1-byte payload, then End of Track.
  var p = Vec[UInt8].new();
  push_byte(&mut p, 0);
  push_byte(&mut p, 0xFF);
  push_byte(&mut p, 0x51);
  push_byte(&mut p, 0x03);
  push_byte(&mut p, 0x07);
  push_byte(&mut p, 0xA1);
  push_byte(&mut p, 0x20);
  push_byte(&mut p, 0);
  push_byte(&mut p, 0xF0);
  push_byte(&mut p, 0x02);
  push_byte(&mut p, 0x7E);
  push_byte(&mut p, 0x7F);
  push_byte(&mut p, 0);
  push_byte(&mut p, 0xF7);
  push_byte(&mut p, 0x01);
  push_byte(&mut p, 0x7F);
  push_byte(&mut p, 0);
  push_byte(&mut p, 0xFF);
  push_byte(&mut p, 0x2F);
  push_byte(&mut p, 0);
  let f = file_with_payload(p);
  var ok = int_ok_is(midi_track_event_count(&f, 0), 4);
  if !pair_is(midi_note_events(&f, 0), 0, 0) { ok = false; }
  return assert(ok, "meta (VLQ length 3), F0/F7 sysex and End of Track are walked");
}

fn t17() -> TestResult {
  // Data after the End of Track must not be counted: the walk stops at
  // FF 2F 00, so the trailing note-on is invisible to both readers.
  var p = Vec[UInt8].new();
  push_byte(&mut p, 0);
  push_byte(&mut p, 0xFF);
  push_byte(&mut p, 0x2F);
  push_byte(&mut p, 0);
  push_byte(&mut p, 0);
  push_byte(&mut p, 0x90);
  push_byte(&mut p, 0x3C);
  push_byte(&mut p, 0x40);
  let stopped = file_with_payload(p);
  var ok = int_ok_is(midi_track_event_count(&stopped, 0), 1);
  if !pair_is(midi_note_events(&stopped, 0), 0, 0) { ok = false; }
  // A track without End of Track is counted up to its declared end.
  var q = Vec[UInt8].new();
  push_byte(&mut q, 0);
  push_byte(&mut q, 0x90);
  push_byte(&mut q, 0x3C);
  push_byte(&mut q, 0x40);
  push_byte(&mut q, 0);
  push_byte(&mut q, 0x80);
  push_byte(&mut q, 0x3C);
  push_byte(&mut q, 0x40);
  let open = file_with_payload(q);
  if !int_ok_is(midi_track_event_count(&open, 0), 2) { ok = false; }
  if !pair_is(midi_note_events(&open, 0), 1, 1) { ok = false; }
  return assert(ok, "End of Track stops the walk; a missing End of Track counts to the track end");
}

fn t18() -> TestResult {
  var p1 = Vec[UInt8].new();
  push_byte(&mut p1, 0);
  push_byte(&mut p1, 0x90);
  push_byte(&mut p1, 0x3C);
  let short_data = file_with_payload(p1);
  var p2 = Vec[UInt8].new();
  push_byte(&mut p2, 0x83);
  push_byte(&mut p2, 0x60);
  let delta_only = file_with_payload(p2);
  var p3 = Vec[UInt8].new();
  push_byte(&mut p3, 0);
  push_byte(&mut p3, 0xF0);
  push_byte(&mut p3, 0x05);
  push_byte(&mut p3, 0x7E);
  let short_sysex = file_with_payload(p3);
  var p4 = Vec[UInt8].new();
  push_byte(&mut p4, 0);
  push_byte(&mut p4, 0xFF);
  push_byte(&mut p4, 0x01);
  push_byte(&mut p4, 0x05);
  push_byte(&mut p4, 0x61);
  let short_meta = file_with_payload(p4);
  var ok = err_int_is(midi_track_event_count(&short_data, 0), "midi: truncated event");
  if !err_pair_is(midi_note_events(&short_data, 0), "midi: truncated event") { ok = false; }
  if !err_int_is(midi_track_event_count(&delta_only, 0), "midi: truncated event") { ok = false; }
  if !err_int_is(midi_track_event_count(&short_sysex, 0), "midi: truncated event") { ok = false; }
  if !err_int_is(midi_track_event_count(&short_meta, 0), "midi: truncated event") { ok = false; }
  return assert(ok, "events crossing the track end are Err: data, delta, sysex, meta");
}

fn t19() -> TestResult {
  // A data byte with no prior channel status.
  var p = Vec[UInt8].new();
  push_byte(&mut p, 0);
  push_byte(&mut p, 0x3C);
  push_byte(&mut p, 0x40);
  let no_status = file_with_payload(p);
  // A meta event clears running status, so the following data byte fails.
  var q = Vec[UInt8].new();
  push_byte(&mut q, 0);
  push_byte(&mut q, 0x90);
  push_byte(&mut q, 0x3C);
  push_byte(&mut q, 0x40);
  push_byte(&mut q, 0);
  push_byte(&mut q, 0xFF);
  push_byte(&mut q, 0x01);
  push_byte(&mut q, 0);
  push_byte(&mut q, 0);
  push_byte(&mut q, 0x3C);
  push_byte(&mut q, 0x40);
  let cleared = file_with_payload(q);
  var ok = err_int_is(midi_track_event_count(&no_status, 0), "midi: missing running status");
  if !err_pair_is(midi_note_events(&no_status, 0), "midi: missing running status") { ok = false; }
  if !err_int_is(midi_track_event_count(&cleared, 0), "midi: missing running status") { ok = false; }
  return assert(ok, "running status without a prior status byte, and after a meta event, is Err");
}

fn t20() -> TestResult {
  var p = Vec[UInt8].new();
  push_byte(&mut p, 0);
  push_byte(&mut p, 0xF1);
  push_byte(&mut p, 0x00);
  let f1 = file_with_payload(p);
  var q = Vec[UInt8].new();
  push_byte(&mut q, 0);
  push_byte(&mut q, 0xF8);
  let f8 = file_with_payload(q);
  var ok = err_int_is(midi_track_event_count(&f1, 0), "midi: bad status byte");
  if !err_int_is(midi_track_event_count(&f8, 0), "midi: bad status byte") { ok = false; }
  return assert(ok, "status bytes outside channel/meta/sysex (F1, F8) are Err");
}

fn t21() -> TestResult {
  var p = Vec[UInt8].new();
  push_byte(&mut p, 0);
  push_byte(&mut p, 0xFF);
  push_byte(&mut p, 0x2F);
  push_byte(&mut p, 0x01);
  push_byte(&mut p, 0x00);
  let f = file_with_payload(p);
  var ok = err_int_is(midi_track_event_count(&f, 0), "midi: bad end of track");
  if !err_pair_is(midi_note_events(&f, 0), "midi: bad end of track") { ok = false; }
  return assert(ok, "End of Track with a non-zero length is Err");
}

fn t22() -> TestResult {
  let f = minimal_file();
  var ok = err_int_is(midi_track_event_count(&f, 1), "midi: track index out of range");
  if !err_int_is(midi_track_event_count(&f, -1), "midi: track index out of range") { ok = false; }
  let two = two_track_file();
  if !err_int_is(midi_track_event_count(&two, 2), "midi: track index out of range") { ok = false; }
  if !err_pair_is(midi_note_events(&two, 2), "midi: track index out of range") { ok = false; }
  if !err_pair_is(midi_note_events(&f, -1), "midi: track index out of range") { ok = false; }
  return assert(ok, "track_index outside 0..count-1 is Err for both readers");
}

fn t23() -> TestResult {
  let f = two_track_file();
  var ok = int_ok_is(midi_format(&f), 1);
  if !int_ok_is(midi_track_count(&f), 2) { ok = false; }
  if !int_ok_is(midi_track_event_count(&f, 0), 2) { ok = false; }
  if !int_ok_is(midi_track_event_count(&f, 1), 2) { ok = false; }
  if !pair_is(midi_note_events(&f, 0), 1, 0) { ok = false; }
  if !pair_is(midi_note_events(&f, 1), 0, 0) { ok = false; }
  return assert(ok, "format 1 file: per-track event counts and note tallies");
}

fn t24() -> TestResult {
  // 8n note-off, 9n note-on vel 64, 9n note-on vel 0, End of Track.
  var p = Vec[UInt8].new();
  push_byte(&mut p, 0);
  push_byte(&mut p, 0x80);
  push_byte(&mut p, 0x3C);
  push_byte(&mut p, 0x00);
  push_byte(&mut p, 0);
  push_byte(&mut p, 0x90);
  push_byte(&mut p, 0x3C);
  push_byte(&mut p, 0x40);
  push_byte(&mut p, 0);
  push_byte(&mut p, 0x90);
  push_byte(&mut p, 0x3C);
  push_byte(&mut p, 0x00);
  push_byte(&mut p, 0);
  push_byte(&mut p, 0xFF);
  push_byte(&mut p, 0x2F);
  push_byte(&mut p, 0);
  let f = file_with_payload(p);
  var ok = int_ok_is(midi_track_event_count(&f, 0), 4);
  if !pair_is(midi_note_events(&f, 0), 1, 2) { ok = false; }
  return assert(ok, "note tally: 1 note-on, 2 note-offs (8n plus 9n velocity 0)");
}

fn main() -> Int {
  io.println("=== xiom.midi conformance tests ===");
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
    io.println("xiom.midi: all tests passed");
  } else {
    io.println("xiom.midi: tests failed");
  }
  return failed;
}
