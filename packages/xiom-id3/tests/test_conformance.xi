// XIOM -- xiom.id3 conformance tests (21 checks)
// Port task: prove the pure-XIOM xiom.id3 module against hand-built ID3v2 tags.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Every tag is built in-test by pushing bytes (no fixtures, no hex): the
// 10-byte header, v2.3 plain big-endian and v2.4 syncsafe frame sizes, text
// payloads with encoding 0/1/3, padding and truncation are all explicit.
// Str equality goes through str_compare (BUG 17 discipline: `==` on Str
// values read from a Vec lowers to a pointer comparison), and Str elements
// are always read into typed locals first.

module id3_tests
use xiom.io; use xiom.test;
use xiom.id3;
use xiom.string; use xiom.string.compare;

// --------------------------------------------------
//  Assertion helpers
// --------------------------------------------------

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn accepts(tags: &Id3Tags, id: Str, want: Str) -> Bool {
  let got = id3_frame(tags, id);
  match got {
    Some(v) => { return streq(v, want); },
    None => { return false; },
  }
  return false;
}

fn missing(tags: &Id3Tags, id: Str) -> Bool {
  let got = id3_frame(tags, id);
  match got {
    Some(_) => { return false; },
    None => { return true; },
  }
  return true;
}

fn present(tags: &Id3Tags, id: Str) -> Bool {
  let got = id3_frame(tags, id);
  match got {
    Some(_) => { return true; },
    None => { return false; },
  }
  return false;
}

fn some_text(tags: &Id3Tags, id: Str) -> Str {
  let got = id3_frame(tags, id);
  match got {
    Some(v) => { return v; },
    None => { return ""; },
  }
}

fn err_int_is(r: Result[Int, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return streq(r.error, want);
}

fn err_str_is(r: Result[Str, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return streq(r.error, want);
}

fn err_tags_is(r: Result[Id3Tags, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return streq(r.error, want);
}

// Int value of an Ok Result; -1 when the Result is Err (a test that expects
// a value then fails on the comparison, not on a crash).
fn int_of(r: Result[Int, Str]) -> Int {
  if r.is_ok { return r.value; }
  return -1;
}

// Str value of an Ok Result; "" when the Result is Err.
fn str_of(r: Result[Str, Str]) -> Str {
  if r.is_ok { return r.value; }
  return "";
}

// --------------------------------------------------
//  Tag builders (byte pushes only)
// --------------------------------------------------

fn push_ascii(v: &mut Vec[UInt8], s: Str) {
  var i = 0;
  while i < s.len() {
    v.push(string.byte_at(s, i));
    i = i + 1;
  }
}

fn bytes_of(s: Str) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  push_ascii(&mut v, s);
  return v;
}

fn push_synchsafe(v: &mut Vec[UInt8], n: Int) {
  v.push(((n / 2097152) % 128) as UInt8);
  v.push(((n / 16384) % 128) as UInt8);
  v.push(((n / 128) % 128) as UInt8);
  v.push((n % 128) as UInt8);
}

fn push_be32(v: &mut Vec[UInt8], n: Int) {
  v.push(((n / 16777216) % 256) as UInt8);
  v.push(((n / 65536) % 256) as UInt8);
  v.push(((n / 256) % 256) as UInt8);
  v.push((n % 256) as UInt8);
}

fn push_u16(v: &mut Vec[UInt8], n: Int) {
  v.push(((n / 256) % 256) as UInt8);
  v.push((n % 256) as UInt8);
}

fn append_bytes(v: &mut Vec[UInt8], src: &Vec[UInt8]) {
  var i = 0;
  while i < src.len() {
    v.push(src[i]);
    i = i + 1;
  }
}

// Wrap a frame-region body in the 10-byte ID3v2 header for major version
// `ver`; the syncsafe tag size is body.len().
fn wrap_tag(ver: Int, body: &Vec[UInt8]) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  push_ascii(&mut v, "ID3");
  v.push(ver as UInt8);
  v.push(0 as UInt8);
  v.push(0 as UInt8);
  push_synchsafe(&mut v, body.len());
  append_bytes(&mut v, body);
  return v;
}

// Concatenate the frame bodies and wrap them in a header for `ver`.
fn wrap_frames(ver: Int, frames: &Vec[Vec[UInt8]]) -> Vec[UInt8] {
  var body = Vec[UInt8].new();
  var i = 0;
  while i < frames.len() {
    append_bytes(&mut body, &frames[i]);
    i = i + 1;
  }
  return wrap_tag(ver, &body);
}

// v2.3 frame: id, plain big-endian size, zero flags, payload.
fn frame23(id: Str, payload: &Vec[UInt8]) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  push_ascii(&mut v, id);
  push_be32(&mut v, payload.len());
  push_u16(&mut v, 0);
  append_bytes(&mut v, payload);
  return v;
}

// v2.4 frame: id, syncsafe size, zero flags, payload.
fn frame24(id: Str, payload: &Vec[UInt8]) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  push_ascii(&mut v, id);
  push_synchsafe(&mut v, payload.len());
  push_u16(&mut v, 0);
  append_bytes(&mut v, payload);
  return v;
}

// Text payload: encoding byte followed by the raw bytes of `text`.
fn tpayload(enc: Int, text: Str) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  v.push(enc as UInt8);
  push_ascii(&mut v, text);
  return v;
}

// One complete v2.3 text frame.
fn tf23(id: Str, enc: Int, text: Str) -> Vec[UInt8] {
  let p = tpayload(enc, text);
  return frame23(id, &p);
}

// One complete v2.4 text frame.
fn tf24(id: Str, enc: Int, text: Str) -> Vec[UInt8] {
  let p = tpayload(enc, text);
  return frame24(id, &p);
}

// The canonical fixture: a v2.3 tag with TIT2/TPE1/TALB (latin1).
fn std_tag() -> Vec[UInt8] {
  var frames = Vec[Vec[UInt8]].new();
  frames.push(tf23("TIT2", 0, "Song Title"));
  frames.push(tf23("TPE1", 0, "The Artist"));
  frames.push(tf23("TALB", 0, "The Album"));
  return wrap_frames(3, &frames);
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  let tag = std_tag();
  let empty = Vec[UInt8].new();
  let junk = bytes_of("not a tag!!");
  let idonly = bytes_of("ID3");
  var ok = id3_has_tag(&tag);
  if id3_has_tag(&empty) { ok = false; }
  if id3_has_tag(&junk) { ok = false; }
  if !id3_has_tag(&idonly) { ok = false; }
  return assert(ok, "has_tag: ID3 magic at offset 0 only");
}

fn t2() -> TestResult {
  let v3 = std_tag();
  var f4 = Vec[Vec[UInt8]].new();
  f4.push(tf24("TIT2", 0, "Four"));
  let v4 = wrap_frames(4, &f4);
  var f5 = Vec[Vec[UInt8]].new();
  f5.push(tf23("TIT2", 0, "Five"));
  let v5 = wrap_frames(5, &f5);
  var ok = int_of(id3_version(&v3)) == 3;
  if int_of(id3_version(&v4)) != 4 { ok = false; }
  if int_of(id3_version(&v5)) != 5 { ok = false; }
  return assert(ok, "version: major byte returned for 3, 4 and 5");
}

fn t3() -> TestResult {
  let tag = std_tag();
  let r = id3_tag_size(&tag);
  if !r.is_ok {
    return assert(false, "tag_size: fixture header parses");
  }
  var ok = r.value == tag.len();
  // Hand-pinned syncsafe header: size bytes 00 00 02 01 -> 257 + 10 = 267.
  var h = Vec[UInt8].new();
  push_ascii(&mut h, "ID3");
  h.push(3 as UInt8);
  h.push(0 as UInt8);
  h.push(0 as UInt8);
  h.push(0 as UInt8);
  h.push(0 as UInt8);
  h.push(2 as UInt8);
  h.push(1 as UInt8);
  var i = 0;
  while i < 257 {
    h.push(0 as UInt8);
    i = i + 1;
  }
  if int_of(id3_tag_size(&h)) != 267 { ok = false; }
  // Trailing audio bytes are not part of the declared tag size.
  var with_audio = Vec[UInt8].new();
  append_bytes(&mut with_audio, &tag);
  append_bytes(&mut with_audio, &bytes_of("TAIL"));
  if int_of(id3_tag_size(&with_audio)) != tag.len() { ok = false; }
  return assert(ok, "tag_size: syncsafe size + 10 header bytes (pinned)");
}

fn t4() -> TestResult {
  let tag = std_tag();
  let r = id3_text_frames(&tag);
  if !r.is_ok {
    return assert(false, "v2.3 fixture tag parses");
  }
  let tags = r.value;
  var ok = id3_frame_count(&tags) == 3;
  if !accepts(&tags, "TIT2", "Song Title") { ok = false; }
  if !accepts(&tags, "TPE1", "The Artist") { ok = false; }
  if !accepts(&tags, "TALB", "The Album") { ok = false; }
  if tags.ids.len() != tags.texts.len() { ok = false; }
  let id0 = tags.ids[0];
  let id2 = tags.ids[2];
  let text2 = tags.texts[2];
  if !streq(id0, "TIT2") { ok = false; }
  if !streq(id2, "TALB") { ok = false; }
  if !streq(text2, "The Album") { ok = false; }
  return assert(ok, "v2.3 tag: TIT2/TPE1/TALB collected in order");
}

fn t5() -> TestResult {
  var frames = Vec[Vec[UInt8]].new();
  frames.push(tf23("TIT2", 0, "First"));
  frames.push(tf23("TIT2", 0, "Second"));
  frames.push(tf23("TALB", 0, "Album"));
  let tag = wrap_frames(3, &frames);
  let r = id3_text_frames(&tag);
  if !r.is_ok {
    return assert(false, "duplicate TIT2 tag parses");
  }
  let tags = r.value;
  var ok = id3_frame_count(&tags) == 3;
  if !accepts(&tags, "TIT2", "First") { ok = false; }
  if !missing(&tags, "TPE1") { ok = false; }
  return assert(ok, "frame: first match wins; absent id is None");
}

fn t6() -> TestResult {
  let tag = std_tag();
  var ok = streq(str_of(id3_title(&tag)), "Song Title");
  if !streq(str_of(id3_artist(&tag)), "The Artist") { ok = false; }
  if !streq(str_of(id3_album(&tag)), "The Album") { ok = false; }
  var frames = Vec[Vec[UInt8]].new();
  frames.push(tf23("TIT2", 0, "Only Title"));
  let partial = wrap_frames(3, &frames);
  if !streq(str_of(id3_artist(&partial)), "") { ok = false; }
  if !streq(str_of(id3_album(&partial)), "") { ok = false; }
  return assert(ok, "title/artist/album accessors return Ok(\"\") when absent");
}

fn t7() -> TestResult {
  var frames = Vec[Vec[UInt8]].new();
  frames.push(tf23("TIT2", 3, "Café"));
  let tag = wrap_frames(3, &frames);
  let r = id3_text_frames(&tag);
  if !r.is_ok {
    return assert(false, "UTF-8 text frame parses");
  }
  let tags = r.value;
  var ok = accepts(&tags, "TIT2", "Café");
  let t = some_text(&tags, "TIT2");
  if t.len() != 5 { ok = false; }
  // UTF-8 e-acute is C3 A9; both bytes must survive verbatim.
  if (string.byte_at(t, 3) as Int) != 195 { ok = false; }
  if (string.byte_at(t, 4) as Int) != 169 { ok = false; }
  return assert(ok, "encoding 3 (UTF-8) preserves non-ASCII bytes");
}

fn t8() -> TestResult {
  var p = Vec[UInt8].new();
  p.push(0 as UInt8);
  p.push(233 as UInt8);
  p.push(252 as UInt8);
  var frames = Vec[Vec[UInt8]].new();
  frames.push(frame23("TPE1", &p));
  let tag = wrap_frames(3, &frames);
  let r = id3_text_frames(&tag);
  if !r.is_ok {
    return assert(false, "latin1 text frame parses");
  }
  let tags = r.value;
  let t = some_text(&tags, "TPE1");
  var ok = t.len() == 2;
  if (string.byte_at(t, 0) as Int) != 233 { ok = false; }
  if (string.byte_at(t, 1) as Int) != 252 { ok = false; }
  return assert(ok, "encoding 0 (latin1) bytes preserved verbatim");
}

fn t9() -> TestResult {
  var frames = Vec[Vec[UInt8]].new();
  frames.push(tf23("TIT2", 1, "UTF-16LE"));
  let tag = wrap_frames(3, &frames);
  let r = id3_text_frames(&tag);
  if !r.is_ok {
    return assert(false, "tag with unknown encoding still parses");
  }
  let tags = r.value;
  var ok = id3_frame_count(&tags) == 1;
  if !present(&tags, "TIT2") { ok = false; }
  if !accepts(&tags, "TIT2", "") { ok = false; }
  return assert(ok, "encoding 1 (unsupported) recorded with empty text");
}

fn t10() -> TestResult {
  var body = Vec[UInt8].new();
  let f = tf23("TIT2", 0, "Padded");
  append_bytes(&mut body, &f);
  var i = 0;
  while i < 6 {
    body.push(0 as UInt8);
    i = i + 1;
  }
  let tag = wrap_tag(3, &body);
  let r = id3_text_frames(&tag);
  if !r.is_ok {
    return assert(false, "padded tag parses");
  }
  let tags = r.value;
  var ok = id3_frame_count(&tags) == 1;
  if !accepts(&tags, "TIT2", "Padded") { ok = false; }
  if int_of(id3_tag_size(&tag)) != tag.len() { ok = false; }
  return assert(ok, "padding (zero frame id) stops the walk");
}

fn t11() -> TestResult {
  var body = Vec[UInt8].new();
  let f1 = tf23("TIT2", 0, "Keep");
  append_bytes(&mut body, &f1);
  push_ascii(&mut body, "TPE1");
  push_be32(&mut body, 0);
  push_u16(&mut body, 0);
  let f3 = tf23("TALB", 0, "Ignored");
  append_bytes(&mut body, &f3);
  let tag = wrap_tag(3, &body);
  let r = id3_text_frames(&tag);
  if !r.is_ok {
    return assert(false, "zero-size frame stops cleanly");
  }
  let tags = r.value;
  var ok = id3_frame_count(&tags) == 1;
  if !accepts(&tags, "TIT2", "Keep") { ok = false; }
  if !missing(&tags, "TALB") { ok = false; }
  return assert(ok, "frame size zero stops the walk");
}

fn t12() -> TestResult {
  let empty_body = Vec[UInt8].new();
  let tag = wrap_tag(3, &empty_body);
  let r = id3_text_frames(&tag);
  if !r.is_ok {
    return assert(false, "empty tag parses");
  }
  let tags = r.value;
  var ok = id3_frame_count(&tags) == 0;
  if !missing(&tags, "TIT2") { ok = false; }
  if int_of(id3_tag_size(&tag)) != 10 { ok = false; }
  return assert(ok, "empty tag: zero frames, size 10");
}

fn t13() -> TestResult {
  let junk = bytes_of("not a tag!!");
  var ok = !id3_has_tag(&junk);
  if !err_int_is(id3_version(&junk), "id3: bad magic") { ok = false; }
  if !err_int_is(id3_tag_size(&junk), "id3: bad magic") { ok = false; }
  if !err_tags_is(id3_text_frames(&junk), "id3: bad magic") { ok = false; }
  if !err_str_is(id3_title(&junk), "id3: bad magic") { ok = false; }
  return assert(ok, "no tag: has_tag false, readers Err bad magic");
}

fn t14() -> TestResult {
  let empty = Vec[UInt8].new();
  let three = bytes_of("ID3");
  var nine = bytes_of("ID3");
  var i = 0;
  while i < 6 {
    nine.push(120 as UInt8);
    i = i + 1;
  }
  var ok = err_int_is(id3_version(&empty), "id3: truncated header");
  if !err_int_is(id3_tag_size(&empty), "id3: truncated header") { ok = false; }
  if !err_tags_is(id3_text_frames(&empty), "id3: truncated header") { ok = false; }
  if !err_str_is(id3_title(&three), "id3: truncated header") { ok = false; }
  if !err_int_is(id3_version(&nine), "id3: truncated header") { ok = false; }
  if !err_tags_is(id3_text_frames(&three), "id3: truncated header") { ok = false; }
  return assert(ok, "truncated header (< 10 bytes) is Err");
}

fn t15() -> TestResult {
  var h = Vec[UInt8].new();
  push_ascii(&mut h, "ID3");
  h.push(3 as UInt8);
  h.push(0 as UInt8);
  h.push(0 as UInt8);
  push_synchsafe(&mut h, 100);
  var i = 0;
  while i < 10 {
    h.push(0 as UInt8);
    i = i + 1;
  }
  var ok = err_int_is(id3_tag_size(&h), "id3: tag size beyond buffer");
  if !err_tags_is(id3_text_frames(&h), "id3: tag size beyond buffer") { ok = false; }
  if !err_str_is(id3_album(&h), "id3: tag size beyond buffer") { ok = false; }
  return assert(ok, "declared tag size beyond the buffer is Err");
}

fn t16() -> TestResult {
  var body = Vec[UInt8].new();
  push_ascii(&mut body, "TIT2");
  push_be32(&mut body, 100);
  push_u16(&mut body, 0);
  body.push(0 as UInt8);
  let tag = wrap_tag(3, &body);
  var ok = int_of(id3_tag_size(&tag)) == tag.len();
  if !err_tags_is(id3_text_frames(&tag), "id3: frame size beyond tag") { ok = false; }
  if !err_str_is(id3_title(&tag), "id3: frame size beyond tag") { ok = false; }
  return assert(ok, "frame size beyond the tag is Err");
}

fn t17() -> TestResult {
  let long = string.str_repeat("x", 200);
  let p = tpayload(0, long);
  var frames = Vec[Vec[UInt8]].new();
  frames.push(frame24("TIT2", &p));
  frames.push(tf24("TPE1", 3, "After"));
  let tag = wrap_frames(4, &frames);
  let r = id3_text_frames(&tag);
  if !r.is_ok {
    return assert(false, "v2.4 syncsafe tag parses");
  }
  let tags = r.value;
  var ok = id3_frame_count(&tags) == 2;
  if !accepts(&tags, "TIT2", long) { ok = false; }
  if !accepts(&tags, "TPE1", "After") { ok = false; }
  return assert(ok, "v2.4 frame sizes are syncsafe (129..255 differs)");
}

fn t18() -> TestResult {
  var apic_payload = bytes_of("PNGDATA");
  var comm_payload = tpayload(1, "comment");
  var frames = Vec[Vec[UInt8]].new();
  frames.push(frame23("APIC", &apic_payload));
  frames.push(frame23("COMM", &comm_payload));
  frames.push(tf23("TIT2", 0, "Real Title"));
  let tag = wrap_frames(3, &frames);
  let r = id3_text_frames(&tag);
  if !r.is_ok {
    return assert(false, "tag with non-text frames parses");
  }
  let tags = r.value;
  var ok = id3_frame_count(&tags) == 1;
  if !accepts(&tags, "TIT2", "Real Title") { ok = false; }
  if !missing(&tags, "APIC") { ok = false; }
  if !missing(&tags, "COMM") { ok = false; }
  return assert(ok, "non-text frames are skipped, walk continues");
}

fn t19() -> TestResult {
  let p = tpayload(0, "Flagged");
  var f = Vec[UInt8].new();
  push_ascii(&mut f, "TIT2");
  push_be32(&mut f, p.len());
  push_u16(&mut f, 16384);
  append_bytes(&mut f, &p);
  var frames = Vec[Vec[UInt8]].new();
  frames.push(f);
  let tag = wrap_frames(3, &frames);
  let r = id3_text_frames(&tag);
  if !r.is_ok {
    return assert(false, "flagged frame parses");
  }
  let tags = r.value;
  var ok = id3_frame_count(&tags) == 1;
  if !accepts(&tags, "TIT2", "Flagged") { ok = false; }
  return assert(ok, "frame flag bytes are ignored");
}

fn t20() -> TestResult {
  var body = Vec[UInt8].new();
  let f = tf23("TIT2", 0, "Short pad");
  append_bytes(&mut body, &f);
  body.push(0 as UInt8);
  body.push(0 as UInt8);
  body.push(0 as UInt8);
  let tag = wrap_tag(3, &body);
  let r = id3_text_frames(&tag);
  if !r.is_ok {
    return assert(false, "short trailing padding parses");
  }
  let tags = r.value;
  var ok = id3_frame_count(&tags) == 1;
  if !accepts(&tags, "TIT2", "Short pad") { ok = false; }
  return assert(ok, "trailing padding shorter than a header is ignored");
}

fn t21() -> TestResult {
  var frames = Vec[Vec[UInt8]].new();
  frames.push(tf24("TIT2", 0, "V4 Title"));
  frames.push(tf24("TPE1", 0, "V4 Artist"));
  frames.push(tf24("TALB", 0, "V4 Album"));
  let tag = wrap_frames(4, &frames);
  var ok = int_of(id3_version(&tag)) == 4;
  if !streq(str_of(id3_title(&tag)), "V4 Title") { ok = false; }
  if !streq(str_of(id3_artist(&tag)), "V4 Artist") { ok = false; }
  if !streq(str_of(id3_album(&tag)), "V4 Album") { ok = false; }
  return assert(ok, "v2.4 tag: title/artist/album accessors");
}

fn main() -> Int {
  io.println("=== xiom.id3 conformance tests ===");
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
    io.println("xiom.id3: all tests passed");
  } else {
    io.println("xiom.id3: tests failed");
  }
  return failed;
}
