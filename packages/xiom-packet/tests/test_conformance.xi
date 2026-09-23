// XIOM -- xiom.packet conformance tests (24 checks)
// Port task: prove the pure-XIOM xiom.packet framing codec against its
// documented wire format, CRC-32 vectors and decoder state rules.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Str payloads are compared with str_compare (BUG 17 discipline: `==` on
// Str values read from a Vec lowers to a pointer comparison). Read-only
// decoder accessors are routed through `&mut` helpers so no test function
// mixes a `&local` call with a later `&mut local` call (advisory E001).

module packet_tests
use xiom.io; use xiom.test;
use xiom.packet;
use xiom.string;
use xiom.string.compare;
use xiom.encoding.hex;

// Expected bytes for a hex string ("" on malformed input; the test then
// fails on the byte comparison).
fn hb(hexstr: Str) -> Vec[UInt8] {
  let r = hex.hex_decode(hexstr);
  match r {
    Ok(v) => { return v; },
    Err(_) => {},
  }
  return Vec[UInt8].new();
}

fn bytes_equal(a: Vec[UInt8], b: Vec[UInt8]) -> Bool {
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

fn bytes_of(s: Str) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < s.len() {
    v.push(string.byte_at(s, i));
    i = i + 1;
  }
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

fn str_eq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn err_bytes_is(r: Result[Vec[UInt8], Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_frames_is(r: Result[Vec[Vec[UInt8]], Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn frame_at_is(frames: &Vec[Vec[UInt8]], idx: Int, want: Vec[UInt8]) -> Bool {
  if idx < 0 || idx >= frames.len() {
    return false;
  }
  return bytes_equal(frames[idx], want);
}

// Read-only decoder accessors through `&mut` (E001 advisory avoidance).
fn dec_available(d: &mut PacketDecoder) -> Int {
  return packet_decoder_available(d);
}

fn dec_buffered(d: &mut PacketDecoder) -> Int {
  return packet_decoder_buffered(d);
}

// Prefix of a byte vector, used to build truncated inputs.
fn prefix(v: Vec[UInt8], n: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < n && i < v.len() {
    out.push(v[i]);
    i = i + 1;
  }
  return out;
}

// Suffix of a byte vector starting at index `start`.
fn suffix(v: Vec[UInt8], start: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = start;
  while i < v.len() {
    out.push(v[i]);
    i = i + 1;
  }
  return out;
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  var empty = Vec[UInt8].new();
  return assert(packet_crc32(&empty) == 0, "crc32 of empty input is 0");
}

fn t2() -> TestResult {
  return assert(packet_crc32(&bytes_of("123456789")) == 3421780262, "crc32 of 123456789 is 0xCBF43926 (3421780262)");
}

fn t3() -> TestResult {
  var ok = packet_crc32(&bytes_of("a")) == 3904355907;
  if packet_crc32(&bytes_of("abc")) != 891568578 { ok = false; }
  return assert(ok, "crc32 of a and abc matches the zlib values");
}

fn t4() -> TestResult {
  let high = hb("ff00807f01");
  return assert(packet_crc32(&high) == 852721342, "crc32 handles high-bit bytes (ff 00 80 7f 01)");
}

fn t5() -> TestResult {
  let payload = hb("010203");
  let f = packet_frame(&payload);
  return assert(bytes_equal(f, hb("030000000102031d80bc55")), "frame of {1,2,3} is exact 11 bytes");
}

fn t6() -> TestResult {
  var empty = Vec[UInt8].new();
  let f = packet_frame(&empty);
  var ok = bytes_equal(f, hb("0000000000000000"));
  let r = packet_parse_all(&f);
  if !r.is_ok { return assert(false, "empty payload frames as 8 zero bytes and parses back"); }
  let frames = r.value;
  if frames.len() != 1 { ok = false; }
  if frames.len() == 1 {
    let p0 = frames[0];
    if p0.len() != 0 { ok = false; }
  }
  return assert(ok, "empty payload frames as 8 zero bytes and parses back");
}

fn t7() -> TestResult {
  let payload = hb("ff00807f01");
  let f = packet_frame(&payload);
  return assert(bytes_equal(f, hb("05000000ff00807f01be7ed332")), "frame with high-bit payload is exact 13 bytes");
}

fn t8() -> TestResult {
  let payload = bytes_of("single frame payload");
  let f = packet_frame(&payload);
  let r = packet_parse_all(&f);
  var ok = r.is_ok;
  if r.is_ok {
    let frames = r.value;
    if frames.len() != 1 { ok = false; }
    if frames.len() == 1 {
      if !frame_at_is(&frames, 0, payload) { ok = false; }
    }
  }
  return assert(ok, "parse_all decodes a single frame");
}

fn t9() -> TestResult {
  let f1 = packet_frame(&bytes_of("one"));
  let f2 = packet_frame(&bytes_of("two"));
  let f3 = packet_frame(&bytes_of("three"));
  let all = concat2(concat2(f1, f2), f3);
  let r = packet_parse_all(&all);
  var ok = r.is_ok;
  if r.is_ok {
    let frames = r.value;
    if frames.len() != 3 { ok = false; }
    if frames.len() == 3 {
      if !frame_at_is(&frames, 0, bytes_of("one")) { ok = false; }
      if !frame_at_is(&frames, 1, bytes_of("two")) { ok = false; }
      if !frame_at_is(&frames, 2, bytes_of("three")) { ok = false; }
    }
  }
  return assert(ok, "parse_all decodes multiple frames in order");
}

fn t10() -> TestResult {
  var empty = Vec[UInt8].new();
  let r = packet_parse_all(&empty);
  var ok = r.is_ok;
  if r.is_ok {
    let frames = r.value;
    if frames.len() != 0 { ok = false; }
  }
  return assert(ok, "parse_all of empty input is an empty Ok");
}

fn t11() -> TestResult {
  let full = packet_frame(&bytes_of("abc"));
  let cut = prefix(full, full.len() - 1);
  let r1 = packet_parse_all(&cut);
  var ok = err_frames_is(r1, "packet: truncated frame");
  let short = hb("0300");
  let r2 = packet_parse_all(&short);
  if !err_frames_is(r2, "packet: truncated frame") { ok = false; }
  return assert(ok, "trailing partial frame is Err(packet: truncated frame)");
}

fn t12() -> TestResult {
  let badcrc = hb("030000000102031d80bc54");
  let r1 = packet_parse_all(&badcrc);
  var ok = err_frames_is(r1, "packet: crc mismatch");
  let badpayload = hb("030000000107031d80bc55");
  let r2 = packet_parse_all(&badpayload);
  if !err_frames_is(r2, "packet: crc mismatch") { ok = false; }
  return assert(ok, "crc-corrupted frame is Err(packet: crc mismatch)");
}

fn t13() -> TestResult {
  let f1 = packet_frame(&bytes_of("ok"));
  let partial = hb("0300000001");
  let all = concat2(f1, partial);
  let r = packet_parse_all(&all);
  var ok = err_frames_is(r, "packet: truncated frame");
  if packet_is_valid(&all) { ok = false; }
  return assert(ok, "valid frame plus partial frame is a whole-call Err");
}

fn t14() -> TestResult {
  let good = packet_frame(&bytes_of("abc"));
  var ok = packet_is_valid(&good);
  var empty = Vec[UInt8].new();
  if packet_is_valid(&empty) { ok = false; }
  let short = hb("0300");
  if packet_is_valid(&short) { ok = false; }
  let bad = hb("030000000102031d80bc54");
  if packet_is_valid(&bad) { ok = false; }
  let two = concat2(packet_frame(&bytes_of("a")), packet_frame(&bytes_of("b")));
  if packet_is_valid(&two) { ok = false; }
  return assert(ok, "packet_is_valid: one CRC-valid frame only");
}

fn t15() -> TestResult {
  var d = packet_decoder_new();
  let f = packet_frame(&bytes_of("hello"));
  packet_decoder_feed(&mut d, &f);
  var ok = dec_available(&mut d) == 1;
  if dec_buffered(&mut d) != f.len() { ok = false; }
  let t = packet_decoder_take(&mut d);
  if !t.is_ok { ok = false; } elif !bytes_equal(t.value, bytes_of("hello")) { ok = false; }
  if dec_available(&mut d) != 0 { ok = false; }
  if dec_buffered(&mut d) != 0 { ok = false; }
  return assert(ok, "decoder feed whole frame -> available/take/buffered");
}

fn t16() -> TestResult {
  var d = packet_decoder_new();
  let f = packet_frame(&bytes_of("xyz"));
  var ok = true;
  var i = 0;
  while i < f.len() {
    var one = Vec[UInt8].new();
    one.push(f[i]);
    packet_decoder_feed(&mut d, &one);
    let complete = dec_available(&mut d);
    if i + 1 < f.len() {
      if complete != 0 { ok = false; }
    } else {
      if complete != 1 { ok = false; }
    }
    i = i + 1;
  }
  let t = packet_decoder_take(&mut d);
  if !t.is_ok { ok = false; } elif !bytes_equal(t.value, bytes_of("xyz")) { ok = false; }
  if dec_buffered(&mut d) != 0 { ok = false; }
  return assert(ok, "decoder accepts a frame fed byte by byte");
}

fn t17() -> TestResult {
  var d = packet_decoder_new();
  let f1 = packet_frame(&bytes_of("first"));
  let f2 = packet_frame(&bytes_of("second"));
  let both = concat2(f1, f2);
  packet_decoder_feed(&mut d, &both);
  var ok = dec_available(&mut d) == 2;
  if dec_buffered(&mut d) != both.len() { ok = false; }
  let a = packet_decoder_take(&mut d);
  if !a.is_ok { ok = false; } elif !bytes_equal(a.value, bytes_of("first")) { ok = false; }
  if dec_available(&mut d) != 1 { ok = false; }
  let b = packet_decoder_take(&mut d);
  if !b.is_ok { ok = false; } elif !bytes_equal(b.value, bytes_of("second")) { ok = false; }
  if dec_available(&mut d) != 0 { ok = false; }
  if dec_buffered(&mut d) != 0 { ok = false; }
  return assert(ok, "two frames in one chunk decode in order");
}

fn t18() -> TestResult {
  var d = packet_decoder_new();
  let f = packet_frame(&bytes_of("abcdef"));
  let head = prefix(f, 3);
  packet_decoder_feed(&mut d, &head);
  var ok = dec_available(&mut d) == 0;
  if dec_buffered(&mut d) != 3 { ok = false; }
  let rest = suffix(f, 3);
  packet_decoder_feed(&mut d, &rest);
  if dec_available(&mut d) != 1 { ok = false; }
  if dec_buffered(&mut d) != f.len() { ok = false; }
  return assert(ok, "availability/buffered track a partial header then completion");
}

fn t19() -> TestResult {
  var d = packet_decoder_new();
  let empty_take = packet_decoder_take(&mut d);
  var ok = err_bytes_is(empty_take, "packet: no complete frame");
  let f = packet_frame(&bytes_of("tail"));
  let partial = prefix(f, f.len() - 1);
  packet_decoder_feed(&mut d, &partial);
  if dec_buffered(&mut d) != f.len() - 1 { ok = false; }
  let r = packet_decoder_take(&mut d);
  if !err_bytes_is(r, "packet: no complete frame") { ok = false; }
  if dec_buffered(&mut d) != f.len() - 1 { ok = false; }
  return assert(ok, "take with no complete frame is Err and consumes nothing");
}

fn t20() -> TestResult {
  var d = packet_decoder_new();
  let f1 = packet_frame(&bytes_of("alpha"));
  let f2 = packet_frame(&bytes_of("beta"));
  let chunk = concat2(f1, prefix(f2, 6));
  packet_decoder_feed(&mut d, &chunk);
  var ok = dec_available(&mut d) == 1;
  let a = packet_decoder_take(&mut d);
  if !a.is_ok { ok = false; } elif !bytes_equal(a.value, bytes_of("alpha")) { ok = false; }
  if dec_available(&mut d) != 0 { ok = false; }
  let tail = suffix(f2, 6);
  packet_decoder_feed(&mut d, &tail);
  if dec_available(&mut d) != 1 { ok = false; }
  let b = packet_decoder_take(&mut d);
  if !b.is_ok { ok = false; } elif !bytes_equal(b.value, bytes_of("beta")) { ok = false; }
  return assert(ok, "decoder holds a partial tail until it is completed");
}

fn t21() -> TestResult {
  var payload = Vec[UInt8].new();
  var i = 0;
  while i < 300 {
    payload.push((i % 256) as UInt8);
    i = i + 1;
  }
  let f = packet_frame(&payload);
  var ok = f.len() == 308;
  let r = packet_parse_all(&f);
  if !r.is_ok { return assert(false, "300-byte payload frames, checksums and round-trips"); }
  let frames = r.value;
  if frames.len() != 1 { ok = false; }
  if frames.len() == 1 {
    if !frame_at_is(&frames, 0, payload) { ok = false; }
  }
  if packet_crc32(&payload) != 985464046 { ok = false; }
  return assert(ok, "300-byte payload frames, checksums and round-trips");
}

fn t22() -> TestResult {
  var d = packet_decoder_new();
  let f1 = packet_frame(&bytes_of("good"));
  let bad = hb("030000000102031d80bc54");
  let f2 = packet_frame(&bytes_of("next"));
  let all = concat2(concat2(f1, bad), f2);
  packet_decoder_feed(&mut d, &all);
  var ok = dec_available(&mut d) == 3;
  let a = packet_decoder_take(&mut d);
  if !a.is_ok { ok = false; } elif !bytes_equal(a.value, bytes_of("good")) { ok = false; }
  let b = packet_decoder_take(&mut d);
  if !err_bytes_is(b, "packet: crc mismatch") { ok = false; }
  if dec_available(&mut d) != 1 { ok = false; }
  let c = packet_decoder_take(&mut d);
  if !c.is_ok { ok = false; } elif !bytes_equal(c.value, bytes_of("next")) { ok = false; }
  return assert(ok, "corrupt frame Errs and the decoder resyncs on the next frame");
}

fn t23() -> TestResult {
  var payload = Vec[UInt8].new();
  var i = 0;
  while i < 300 {
    payload.push((i % 256) as UInt8);
    i = i + 1;
  }
  let f = packet_frame(&payload);
  var ok = f.len() == 308;
  if (f[0] as Int) != 44 { ok = false; }
  if (f[1] as Int) != 1 { ok = false; }
  if (f[2] as Int) != 0 { ok = false; }
  if (f[3] as Int) != 0 { ok = false; }
  if (f[304] as Int) != 238 { ok = false; }
  if (f[305] as Int) != 252 { ok = false; }
  if (f[306] as Int) != 188 { ok = false; }
  if (f[307] as Int) != 58 { ok = false; }
  return assert(ok, "300-byte frame: LE length prefix and LE CRC trailer bytes");
}

fn t24() -> TestResult {
  var d = packet_decoder_new();
  let f1 = packet_frame(&bytes_of("one"));
  packet_decoder_feed(&mut d, &f1);
  let a = packet_decoder_take(&mut d);
  var ok = a.is_ok;
  if dec_buffered(&mut d) != 0 { ok = false; }
  let f2 = packet_frame(&bytes_of("two"));
  packet_decoder_feed(&mut d, &f2);
  if dec_buffered(&mut d) != f2.len() { ok = false; }
  if dec_available(&mut d) != 1 { ok = false; }
  let b = packet_decoder_take(&mut d);
  if !b.is_ok { ok = false; } elif !bytes_equal(b.value, bytes_of("two")) { ok = false; }
  return assert(ok, "feed compacts the consumed prefix and keeps decoding");
}

fn main() -> Int {
  io.println("=== xiom.packet conformance tests ===");
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
    io.println("xiom.packet: all tests passed");
  } else {
    io.println("xiom.packet: tests failed");
  }
  return failed;
}
