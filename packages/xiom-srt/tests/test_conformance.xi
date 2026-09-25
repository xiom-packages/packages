// XIOM -- xiom.srt conformance tests (21 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Covers the documented API: two-cue parsing with exact times, multi-line
// payload order, CRLF normalization, timestamp parse/format values and
// boundaries, the timestamp error catalog (shape vs range, millisecond
// digits, comma vs dot), end-before-start, trailing settings pass-through,
// the structural error catalog (missing index, bad index, missing timing
// line, stray text, cue without payload, empty input), index renumbering on
// output, canonical formatting, parse -> format -> parse round-trips, every
// accessor including sentinels, UTF-8 payloads and whitespace-only lines.
//
// All Str equality goes through str_compare (BUG 17 discipline: `==` on Str
// values read from Vec[Str] lowers to a pointer comparison), and every
// element read goes through a typed local.

module srt_tests
use xiom.io; use xiom.test; use xiom.srt;
use xiom.string.compare;

// Shared two-cue SRT document. srt_format of the parsed track reproduces
// this exact text (test t16 uses it).
fn srt_doc() -> Str {
  return "1\n00:00:01,000 --> 00:00:02,500\nhello world\n\n2\n00:00:03,000 --> 00:00:04,000\nsecond cue\n";
}

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn err_srt_is(r: Result[Srt, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return streq(r.error, want);
}

fn err_int_is(r: Result[Int, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return streq(r.error, want);
}

fn ok_int(r: Result[Int, Str]) -> Int {
  if !r.is_ok { return -123456789; }
  return r.value;
}

// Structural comparison: cue count, times, settings, payload line counts and
// every payload line. Indices are not compared (the emitter renumbers them).
fn same_srt(a: &Srt, b: &Srt) -> Bool {
  let na = srt_cue_count(a);
  if na != srt_cue_count(b) { return false; }
  var i = 0;
  while i < na {
    if srt_cue_start_ms(a, i) != srt_cue_start_ms(b, i) { return false; }
    if srt_cue_end_ms(a, i) != srt_cue_end_ms(b, i) { return false; }
    if srt_cue_line_count(a, i) != srt_cue_line_count(b, i) { return false; }
    let sa: Str = srt_cue_settings(a, i);
    let sb: Str = srt_cue_settings(b, i);
    if !streq(sa, sb) { return false; }
    let ta: Str = srt_cue_text(a, i);
    let tb: Str = srt_cue_text(b, i);
    if !streq(ta, tb) { return false; }
    var j = 0;
    while j < srt_cue_line_count(a, i) {
      let la: Str = srt_cue_line(a, i, j);
      let lb: Str = srt_cue_line(b, i, j);
      if !streq(la, lb) { return false; }
      j = j + 1;
    }
    i = i + 1;
  }
  return true;
}

fn cue_is(s: &Srt, i: Int, want_idx: Int, want_a: Int, want_b: Int, want_text: Str) -> Bool {
  if srt_cue_index(s, i) != want_idx { return false; }
  if srt_cue_start_ms(s, i) != want_a { return false; }
  if srt_cue_end_ms(s, i) != want_b { return false; }
  let got: Str = srt_cue_text(s, i);
  return streq(got, want_text);
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  let r = srt_parse(srt_doc());
  if !r.is_ok { return assert(false, "srt_parse: two cues with exact times"); }
  let s = r.value;
  var ok = srt_cue_count(&s) == 2;
  if !cue_is(&s, 0, 1, 1000, 2500, "hello world") { ok = false; }
  if !cue_is(&s, 1, 2, 3000, 4000, "second cue") { ok = false; }
  if srt_cue_line_count(&s, 0) != 1 { ok = false; }
  if srt_cue_line_count(&s, 1) != 1 { ok = false; }
  return assert(ok, "srt_parse: two cues with exact times");
}

fn t2() -> TestResult {
  let doc = "1\n00:00:01,000 --> 00:00:04,000\nfirst line\nsecond line\nthird\n";
  let r = srt_parse(doc);
  if !r.is_ok { return assert(false, "payload lines keep order and join with LF"); }
  let s = r.value;
  var ok = srt_cue_line_count(&s, 0) == 3;
  let l0: Str = srt_cue_line(&s, 0, 0);
  let l1: Str = srt_cue_line(&s, 0, 1);
  let l2: Str = srt_cue_line(&s, 0, 2);
  if !streq(l0, "first line") { ok = false; }
  if !streq(l1, "second line") { ok = false; }
  if !streq(l2, "third") { ok = false; }
  let txt: Str = srt_cue_text(&s, 0);
  if !streq(txt, "first line\nsecond line\nthird") { ok = false; }
  return assert(ok, "payload lines keep order and join with LF");
}

fn t3() -> TestResult {
  let crlf = "1\r\n00:00:01,000 --> 00:00:02,000\r\nline one\r\nline two\r\n\r\n2\r\n00:00:03,000 --> 00:00:04,000\r\nlast\r\n";
  let lf = "1\n00:00:01,000 --> 00:00:02,000\nline one\nline two\n\n2\n00:00:03,000 --> 00:00:04,000\nlast\n";
  let rc = srt_parse(crlf);
  let rl = srt_parse(lf);
  if !rc.is_ok { return assert(false, "CRLF and LF documents parse identically"); }
  if !rl.is_ok { return assert(false, "CRLF and LF documents parse identically"); }
  let sc = rc.value;
  let sl = rl.value;
  var ok = same_srt(&sc, &sl);
  let fc: Str = srt_format(&sc);
  if !streq(fc, lf) { ok = false; }
  return assert(ok, "CRLF and LF documents parse identically");
}

fn t4() -> TestResult {
  var ok = ok_int(srt_parse_timestamp("00:00:00,000")) == 0;
  if ok_int(srt_parse_timestamp("00:00:00,001")) != 1 { ok = false; }
  if ok_int(srt_parse_timestamp("01:02:03,456")) != 3723456 { ok = false; }
  if ok_int(srt_parse_timestamp("99:59:59,999")) != 359999999 { ok = false; }
  let f0: Str = srt_format_timestamp(0);
  let f1: Str = srt_format_timestamp(3723456);
  let f2: Str = srt_format_timestamp(-7);
  if !streq(f0, "00:00:00,000") { ok = false; }
  if !streq(f1, "01:02:03,456") { ok = false; }
  if !streq(f2, "00:00:00,000") { ok = false; }
  return assert(ok, "timestamp helpers convert to exact milliseconds");
}

fn t5() -> TestResult {
  var ok = err_int_is(srt_parse_timestamp("00:00:01,00"), "srt: bad timestamp shape");
  if !err_int_is(srt_parse_timestamp("00:00:01,0000"), "srt: bad timestamp shape") { ok = false; }
  if !err_int_is(srt_parse_timestamp("00:00:01;000"), "srt: bad timestamp shape") { ok = false; }
  if !err_int_is(srt_parse_timestamp("0:00:01,000"), "srt: bad timestamp shape") { ok = false; }
  if !err_int_is(srt_parse_timestamp(""), "srt: bad timestamp shape") { ok = false; }
  if !err_int_is(srt_parse_timestamp("00:60:00,000"), "srt: timestamp out of range") { ok = false; }
  if !err_int_is(srt_parse_timestamp("00:00:61,000"), "srt: timestamp out of range") { ok = false; }
  if ok_int(srt_parse_timestamp("00:00:01.500")) != 1500 { ok = false; }
  return assert(ok, "timestamp shape, range and dot-comma rules");
}

fn t6() -> TestResult {
  let bad = "1\n00:00:05,000 --> 00:00:02,000\nx\n";
  var ok = err_srt_is(srt_parse(bad), "srt: end before start");
  let eq = srt_parse("1\n00:00:02,000 --> 00:00:02,000\nx\n");
  if !eq.is_ok {
    ok = false;
  } else {
    let s = eq.value;
    if srt_cue_start_ms(&s, 0) != 2000 { ok = false; }
    if srt_cue_end_ms(&s, 0) != 2000 { ok = false; }
  }
  return assert(ok, "end before start is Err; equal times are allowed");
}

fn t7() -> TestResult {
  let doc = "1\n00:00:01,000 --> 00:00:02,000 X1:100 X2:200 Y1:300 Y2:400\nHello\n";
  let r = srt_parse(doc);
  if !r.is_ok { return assert(false, "trailing settings pass through verbatim"); }
  let s = r.value;
  var ok = srt_cue_count(&s) == 1;
  let stg: Str = srt_cue_settings(&s, 0);
  if !streq(stg, "X1:100 X2:200 Y1:300 Y2:400") { ok = false; }
  let f: Str = srt_format(&s);
  if !streq(f, doc) { ok = false; }
  return assert(ok, "trailing settings pass through verbatim");
}

fn t8() -> TestResult {
  let direct = "00:00:01,000 --> 00:00:02,000\npayload\n";
  let after_blanks = "\n\n00:00:01,000 --> 00:00:02,000\npayload\n";
  var ok = err_srt_is(srt_parse(direct), "srt: missing index");
  if !err_srt_is(srt_parse(after_blanks), "srt: missing index") { ok = false; }
  return assert(ok, "a block without an index line is Err");
}

fn t9() -> TestResult {
  let zero = "0\n00:00:01,000 --> 00:00:02,000\nx\n";
  let alpha = "abc\n00:00:01,000 --> 00:00:02,000\nx\n";
  let mixed = "1a\n00:00:01,000 --> 00:00:02,000\nx\n";
  var ok = err_srt_is(srt_parse(zero), "srt: bad index");
  if !err_srt_is(srt_parse(alpha), "srt: bad index") { ok = false; }
  if !err_srt_is(srt_parse(mixed), "srt: bad index") { ok = false; }
  return assert(ok, "index lines must be positive decimal integers");
}

fn t10() -> TestResult {
  let doc = "1\nhello world\n00:00:01,000 --> 00:00:02,000\nx\n";
  var ok = err_srt_is(srt_parse(doc), "srt: stray text");
  let tail = "1\n00:00:01,000 --> 00:00:02,000\nx\n\nworld\n";
  if !err_srt_is(srt_parse(tail), "srt: bad index") { ok = false; }
  return assert(ok, "text where the timing line belongs is Err");
}

fn t11() -> TestResult {
  let eof = "1\n";
  let blank = "1\n\n00:00:01,000 --> 00:00:02,000\nx\n";
  var ok = err_srt_is(srt_parse(eof), "srt: missing timing line");
  if !err_srt_is(srt_parse(blank), "srt: missing timing line") { ok = false; }
  return assert(ok, "an index line must be followed by a timing line");
}

fn t12() -> TestResult {
  let eof = "1\n00:00:01,000 --> 00:00:02,000\n";
  let blank = "1\n00:00:01,000 --> 00:00:02,000\n\n2\n00:00:03,000 --> 00:00:04,000\ny\n";
  var ok = err_srt_is(srt_parse(eof), "srt: cue without payload");
  if !err_srt_is(srt_parse(blank), "srt: cue without payload") { ok = false; }
  return assert(ok, "every cue needs at least one payload line");
}

fn t13() -> TestResult {
  var ok = err_srt_is(srt_parse(""), "srt: empty input");
  if !err_srt_is(srt_parse("\n\n"), "srt: empty input") { ok = false; }
  if !err_srt_is(srt_parse("\r\n\r\n"), "srt: empty input") { ok = false; }
  return assert(ok, "a document without cue blocks is Err");
}

fn t14() -> TestResult {
  let doc = "7\n00:00:01,000 --> 00:00:02,000\nfirst\n\n3\n00:00:03,000 --> 00:00:04,000\nsecond\n\n007\n00:00:05,000 --> 00:00:06,000\nthird\n";
  let r = srt_parse(doc);
  if !r.is_ok { return assert(false, "indices need not be sequential; the emitter renumbers"); }
  let s = r.value;
  var ok = srt_cue_count(&s) == 3;
  if srt_cue_index(&s, 0) != 7 { ok = false; }
  if srt_cue_index(&s, 1) != 3 { ok = false; }
  if srt_cue_index(&s, 2) != 7 { ok = false; }
  let f: Str = srt_format(&s);
  let want = "1\n00:00:01,000 --> 00:00:02,000\nfirst\n\n2\n00:00:03,000 --> 00:00:04,000\nsecond\n\n3\n00:00:05,000 --> 00:00:06,000\nthird\n";
  if !streq(f, want) { ok = false; }
  let r2 = srt_parse(f);
  if !r2.is_ok {
    ok = false;
  } else {
    let s2 = r2.value;
    if srt_cue_index(&s2, 2) != 3 { ok = false; }
    if !same_srt(&s, &s2) { ok = false; }
  }
  return assert(ok, "indices need not be sequential; the emitter renumbers");
}

fn t15() -> TestResult {
  let messy = "\r\n007\r\n00:00:01.000 --> 00:00:02.500   X1:10\r\nHello\r\nWorld\r\n\r\n\r\n3\r\n00:00:03,000-->00:00:04,000\r\nsecond\r\n";
  let want = "1\n00:00:01,000 --> 00:00:02,500 X1:10\nHello\nWorld\n\n2\n00:00:03,000 --> 00:00:04,000\nsecond\n";
  let r = srt_parse(messy);
  if !r.is_ok { return assert(false, "canonical output normalizes separators, indices and blanks"); }
  let s = r.value;
  let f: Str = srt_format(&s);
  return assert(streq(f, want), "canonical output normalizes separators, indices and blanks");
}

fn t16() -> TestResult {
  let doc = "1\n00:00:01,000 --> 00:00:02,500\nhello world\n\n2\n00:00:03,000 --> 00:00:04,000 align:start\nsecond cue\nline two\n";
  let r = srt_parse(doc);
  if !r.is_ok { return assert(false, "canonical documents round-trip parse -> format -> parse"); }
  let s = r.value;
  let f: Str = srt_format(&s);
  var ok = streq(f, doc);
  let r2 = srt_parse(f);
  if !r2.is_ok {
    ok = false;
  } else {
    let s2 = r2.value;
    if !same_srt(&s, &s2) { ok = false; }
    let f2: Str = srt_format(&s2);
    if !streq(f2, doc) { ok = false; }
  }
  return assert(ok, "canonical documents round-trip parse -> format -> parse");
}

fn t17() -> TestResult {
  let r = srt_parse(srt_doc());
  if !r.is_ok { return assert(false, "accessors return sentinels out of range"); }
  let s = r.value;
  var ok = srt_cue_count(&s) == 2;
  if srt_cue_index(&s, -1) != -1 { ok = false; }
  if srt_cue_index(&s, 2) != -1 { ok = false; }
  if srt_cue_start_ms(&s, -1) != -1 { ok = false; }
  if srt_cue_start_ms(&s, 2) != -1 { ok = false; }
  if srt_cue_end_ms(&s, -1) != -1 { ok = false; }
  if srt_cue_end_ms(&s, 9) != -1 { ok = false; }
  let st_lo: Str = srt_cue_settings(&s, -1);
  let st_hi: Str = srt_cue_settings(&s, 5);
  if !streq(st_lo, "") { ok = false; }
  if !streq(st_hi, "") { ok = false; }
  if srt_cue_line_count(&s, -1) != 0 { ok = false; }
  if srt_cue_line_count(&s, 2) != 0 { ok = false; }
  let l_lo: Str = srt_cue_line(&s, 0, -1);
  let l_hi: Str = srt_cue_line(&s, 0, 99);
  if !streq(l_lo, "") { ok = false; }
  if !streq(l_hi, "") { ok = false; }
  let t_lo: Str = srt_cue_text(&s, -1);
  let t_hi: Str = srt_cue_text(&s, 7);
  if !streq(t_lo, "") { ok = false; }
  if !streq(t_hi, "") { ok = false; }
  return assert(ok, "accessors return sentinels out of range");
}

fn t18() -> TestResult {
  let doc = "1\n00:00:01,000 --> 00:00:02,000\nhéllo — 世界\n   \nnaïve ✓\n";
  let r = srt_parse(doc);
  if !r.is_ok { return assert(false, "payload bytes round-trip; whitespace-only lines are text"); }
  let s = r.value;
  var ok = srt_cue_line_count(&s, 0) == 3;
  let txt: Str = srt_cue_text(&s, 0);
  if !streq(txt, "héllo — 世界\n   \nnaïve ✓") { ok = false; }
  let f: Str = srt_format(&s);
  if !streq(f, doc) { ok = false; }
  return assert(ok, "payload bytes round-trip; whitespace-only lines are text");
}

fn t19() -> TestResult {
  let tight = "1\n00:00:01,000-->00:00:02,000\nx\n";
  let trail = "1\n00:00:01,000 --> 00:00:02,000 \t\nx\n";
  let r1 = srt_parse(tight);
  if !r1.is_ok { return assert(false, "arrows and empty settings are trimmed"); }
  let s1 = r1.value;
  var ok = srt_cue_start_ms(&s1, 0) == 1000;
  if srt_cue_end_ms(&s1, 0) != 2000 { ok = false; }
  let st1: Str = srt_cue_settings(&s1, 0);
  if !streq(st1, "") { ok = false; }
  let f1: Str = srt_format(&s1);
  if !streq(f1, "1\n00:00:01,000 --> 00:00:02,000\nx\n") { ok = false; }
  let r2 = srt_parse(trail);
  if !r2.is_ok {
    ok = false;
  } else {
    let s2 = r2.value;
    let st2: Str = srt_cue_settings(&s2, 0);
    if !streq(st2, "") { ok = false; }
  }
  return assert(ok, "arrows and empty settings are trimmed");
}

fn t20() -> TestResult {
  let doc = "1\n00:00:00,000 --> 00:00:00,000\nx\n\n2\n99:59:59,999 --> 99:59:59,999\ny\n";
  let r = srt_parse(doc);
  if !r.is_ok { return assert(false, "zero, 1 ms and 99-hour boundaries are exact"); }
  let s = r.value;
  var ok = srt_cue_start_ms(&s, 0) == 0;
  if srt_cue_end_ms(&s, 0) != 0 { ok = false; }
  if !cue_is(&s, 1, 2, 359999999, 359999999, "y") { ok = false; }
  let f: Str = srt_format(&s);
  if !streq(f, doc) { ok = false; }
  let one = srt_parse("1\n00:00:00,000 --> 00:00:00,001\nz\n");
  if !one.is_ok {
    ok = false;
  } else {
    let s3 = one.value;
    if srt_cue_end_ms(&s3, 0) != 1 { ok = false; }
  }
  return assert(ok, "zero, 1 ms and 99-hour boundaries are exact");
}

fn t21() -> TestResult {
  let idxs = Vec[Int].new();
  let sts = Vec[Int].new();
  let ens = Vec[Int].new();
  let st = Vec[Str].new();
  let ps = Vec[Int].new();
  let pe = Vec[Int].new();
  let ls = Vec[Str].new();
  idxs.push(1);
  sts.push(1000);
  ens.push(2000);
  st.push("");
  ps.push(5);
  pe.push(9);
  let s = Srt{ indexes: idxs; starts: sts; ends: ens; settings: st; payload_starts: ps; payload_ends: pe; lines: ls; };
  var ok = srt_cue_count(&s) == 1;
  if srt_cue_start_ms(&s, 0) != 1000 { ok = false; }
  if srt_cue_end_ms(&s, 0) != 2000 { ok = false; }
  if srt_cue_line_count(&s, 0) != 0 { ok = false; }
  let txt: Str = srt_cue_text(&s, 0);
  if !streq(txt, "") { ok = false; }
  let f: Str = srt_format(&s);
  if !streq(f, "1\n00:00:01,000 --> 00:00:02,000\n") { ok = false; }
  return assert(ok, "drifted vectors are clamped, never read out of bounds");
}

fn main() -> Int {
  io.println("=== xiom.srt conformance tests ===");
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
    io.println("xiom.srt: all tests passed");
  } else {
    io.println("xiom.srt: tests failed");
  }
  return failed;
}
