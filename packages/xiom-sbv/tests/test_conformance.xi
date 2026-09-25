// XIOM -- xiom.sbv conformance tests (20 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Covers the documented API: two-cue parsing with exact times, multi-line
// payload order, CRLF normalization, timestamp parse/format values and
// boundaries, the timestamp error catalog (shape vs range, digit counts,
// separators, hour width), end-before-start, optional comma whitespace,
// missing comma, cue without payload, payload before timing, text before the
// first cue, empty input, canonical emission, parse -> format -> parse
// round-trips, accessor sentinels, duration, UTF-8 payloads, whitespace-only
// lines, greedy payload, and drifted vectors.
//
// All Str equality goes through str_compare (BUG 17 discipline: `==` on Str
// values read from Vec[Str] lowers to a pointer comparison), and every
// element read goes through a typed local.

module sbv_tests
use xiom.io; use xiom.test; use xiom.sbv;
use xiom.string.compare;

// Shared two-cue SBV document. sbv_format of the parsed track reproduces
// this exact text (test t14 uses it).
fn sbv_doc() -> Str {
  return "0:00:01.000,0:00:02.500\nhello world\n\n0:00:03.000,0:00:04.000\nsecond cue\n";
}

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn err_sbv_is(r: Result[Sbv, Str], want: Str) -> Bool {
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

// Structural comparison: cue count, times, payload line counts and every
// payload line.
fn same_sbv(a: &Sbv, b: &Sbv) -> Bool {
  let na = sbv_cue_count(a);
  if na != sbv_cue_count(b) { return false; }
  var i = 0;
  while i < na {
    if sbv_cue_start_ms(a, i) != sbv_cue_start_ms(b, i) { return false; }
    if sbv_cue_end_ms(a, i) != sbv_cue_end_ms(b, i) { return false; }
    if sbv_cue_line_count(a, i) != sbv_cue_line_count(b, i) { return false; }
    let ta: Str = sbv_cue_text(a, i);
    let tb: Str = sbv_cue_text(b, i);
    if !streq(ta, tb) { return false; }
    var j = 0;
    while j < sbv_cue_line_count(a, i) {
      let la: Str = sbv_cue_line(a, i, j);
      let lb: Str = sbv_cue_line(b, i, j);
      if !streq(la, lb) { return false; }
      j = j + 1;
    }
    i = i + 1;
  }
  return true;
}

fn cue_is(s: &Sbv, i: Int, want_a: Int, want_b: Int, want_text: Str) -> Bool {
  if sbv_cue_start_ms(s, i) != want_a { return false; }
  if sbv_cue_end_ms(s, i) != want_b { return false; }
  let got: Str = sbv_cue_text(s, i);
  return streq(got, want_text);
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  let r = sbv_parse(sbv_doc());
  if !r.is_ok { return assert(false, "sbv_parse: two cues with exact times"); }
  let s = r.value;
  var ok = sbv_cue_count(&s) == 2;
  if !cue_is(&s, 0, 1000, 2500, "hello world") { ok = false; }
  if !cue_is(&s, 1, 3000, 4000, "second cue") { ok = false; }
  if sbv_cue_line_count(&s, 0) != 1 { ok = false; }
  if sbv_cue_line_count(&s, 1) != 1 { ok = false; }
  return assert(ok, "sbv_parse: two cues with exact times");
}

fn t2() -> TestResult {
  let doc = "0:00:01.000,0:00:04.000\nfirst line\nsecond line\nthird\n";
  let r = sbv_parse(doc);
  if !r.is_ok { return assert(false, "payload lines keep order and join with LF"); }
  let s = r.value;
  var ok = sbv_cue_line_count(&s, 0) == 3;
  let l0: Str = sbv_cue_line(&s, 0, 0);
  let l1: Str = sbv_cue_line(&s, 0, 1);
  let l2: Str = sbv_cue_line(&s, 0, 2);
  if !streq(l0, "first line") { ok = false; }
  if !streq(l1, "second line") { ok = false; }
  if !streq(l2, "third") { ok = false; }
  let txt: Str = sbv_cue_text(&s, 0);
  if !streq(txt, "first line\nsecond line\nthird") { ok = false; }
  return assert(ok, "payload lines keep order and join with LF");
}

fn t3() -> TestResult {
  let crlf = "0:00:01.000,0:00:02.000\r\nline one\r\nline two\r\n\r\n0:00:03.000,0:00:04.000\r\nlast\r\n";
  let lf = "0:00:01.000,0:00:02.000\nline one\nline two\n\n0:00:03.000,0:00:04.000\nlast\n";
  let rc = sbv_parse(crlf);
  let rl = sbv_parse(lf);
  if !rc.is_ok { return assert(false, "CRLF and LF documents parse identically"); }
  if !rl.is_ok { return assert(false, "CRLF and LF documents parse identically"); }
  let sc = rc.value;
  let sl = rl.value;
  var ok = same_sbv(&sc, &sl);
  let fc: Str = sbv_format(&sc);
  if !streq(fc, lf) { ok = false; }
  return assert(ok, "CRLF and LF documents parse identically");
}

fn t4() -> TestResult {
  var ok = ok_int(sbv_parse_timestamp("0:00:00.000")) == 0;
  if ok_int(sbv_parse_timestamp("0:00:00.001")) != 1 { ok = false; }
  if ok_int(sbv_parse_timestamp("1:02:03.456")) != 3723456 { ok = false; }
  if ok_int(sbv_parse_timestamp("9:59:59.999")) != 35999999 { ok = false; }
  if ok_int(sbv_parse_timestamp("99:59:59.999")) != 359999999 { ok = false; }
  let f0: Str = sbv_format_timestamp(0);
  let f1: Str = sbv_format_timestamp(1);
  let f2: Str = sbv_format_timestamp(3723456);
  let f3: Str = sbv_format_timestamp(-7);
  let f4: Str = sbv_format_timestamp(359999999);
  let f5: Str = sbv_format_timestamp(360000000);
  if !streq(f0, "0:00:00.000") { ok = false; }
  if !streq(f1, "0:00:00.001") { ok = false; }
  if !streq(f2, "1:02:03.456") { ok = false; }
  if !streq(f3, "0:00:00.000") { ok = false; }
  if !streq(f4, "99:59:59.999") { ok = false; }
  if !streq(f5, "100:00:00.000") { ok = false; }
  return assert(ok, "timestamp helpers convert to exact milliseconds");
}

fn t5() -> TestResult {
  var ok = err_int_is(sbv_parse_timestamp("0:00:01.00"), "sbv: bad timestamp shape");
  if !err_int_is(sbv_parse_timestamp("0:00:01.0000"), "sbv: bad timestamp shape") { ok = false; }
  if !err_int_is(sbv_parse_timestamp("0:00:01,000"), "sbv: bad timestamp shape") { ok = false; }
  if !err_int_is(sbv_parse_timestamp("0.00:01.000"), "sbv: bad timestamp shape") { ok = false; }
  if !err_int_is(sbv_parse_timestamp("0:0:01.000"), "sbv: bad timestamp shape") { ok = false; }
  if !err_int_is(sbv_parse_timestamp("0:00:1.0000"), "sbv: bad timestamp shape") { ok = false; }
  if !err_int_is(sbv_parse_timestamp("000:00:01.000"), "sbv: bad timestamp shape") { ok = false; }
  if !err_int_is(sbv_parse_timestamp(":00:01.000"), "sbv: bad timestamp shape") { ok = false; }
  if !err_int_is(sbv_parse_timestamp("0:00:01.000 "), "sbv: bad timestamp shape") { ok = false; }
  if !err_int_is(sbv_parse_timestamp(""), "sbv: bad timestamp shape") { ok = false; }
  if !err_int_is(sbv_parse_timestamp("0:60:00.000"), "sbv: timestamp out of range") { ok = false; }
  if !err_int_is(sbv_parse_timestamp("0:00:61.000"), "sbv: timestamp out of range") { ok = false; }
  if ok_int(sbv_parse_timestamp("00:00:01.000")) != 1000 { ok = false; }
  return assert(ok, "timestamp shape, range and hour-width rules");
}

fn t6() -> TestResult {
  let bad = "0:00:05.000,0:00:02.000\nx\n";
  var ok = err_sbv_is(sbv_parse(bad), "sbv: end before start");
  let eq = sbv_parse("0:00:02.000,0:00:02.000\nx\n");
  if !eq.is_ok {
    ok = false;
  } else {
    let s = eq.value;
    if sbv_cue_start_ms(&s, 0) != 2000 { ok = false; }
    if sbv_cue_end_ms(&s, 0) != 2000 { ok = false; }
    if sbv_cue_duration_ms(&s, 0) != 0 { ok = false; }
  }
  return assert(ok, "end before start is Err; equal times are allowed");
}

fn t7() -> TestResult {
  let spaced = "0:00:01.000 , 0:00:02.000\nx\n";
  let tabbed = "0:00:01.000\t,\t0:00:02.000\nx\n";
  let edged = " 0:00:01.000,0:00:02.000 \nx\n";
  let r1 = sbv_parse(spaced);
  let r2 = sbv_parse(tabbed);
  let r3 = sbv_parse(edged);
  var ok = r1.is_ok;
  if r1.is_ok {
    let s = r1.value;
    if sbv_cue_start_ms(&s, 0) != 1000 { ok = false; }
    if sbv_cue_end_ms(&s, 0) != 2000 { ok = false; }
    let f: Str = sbv_format(&s);
    if !streq(f, "0:00:01.000,0:00:02.000\nx\n") { ok = false; }
  }
  if !r2.is_ok { ok = false; }
  if !r3.is_ok { ok = false; }
  return assert(ok, "whitespace around the comma is accepted, never emitted");
}

fn t8() -> TestResult {
  var ok = err_sbv_is(sbv_parse("0:00:01.000 0:00:02.000\nx\n"), "sbv: missing comma");
  if !err_sbv_is(sbv_parse("0:00:01.000-0:00:02.000\nx\n"), "sbv: missing comma") { ok = false; }
  if !err_sbv_is(sbv_parse("0:00:01.000,0:00:02.000 extra\nx\n"), "sbv: bad timestamp shape") { ok = false; }
  if !err_sbv_is(sbv_parse("hello, world\n"), "sbv: bad timestamp shape") { ok = false; }
  let later = "0:00:01.000,0:00:02.000\nx\n\n0:00:03.000 0:00:04.000\ny\n";
  if !err_sbv_is(sbv_parse(later), "sbv: missing comma") { ok = false; }
  return assert(ok, "the comma is required and closing text is not allowed");
}

fn t9() -> TestResult {
  let eof = "0:00:01.000,0:00:02.000\n";
  let blank = "0:00:01.000,0:00:02.000\n\n0:00:03.000,0:00:04.000\ny\n";
  var ok = err_sbv_is(sbv_parse(eof), "sbv: cue without payload");
  if !err_sbv_is(sbv_parse(blank), "sbv: cue without payload") { ok = false; }
  return assert(ok, "every cue needs at least one payload line");
}

fn t10() -> TestResult {
  let tail = "0:00:01.000,0:00:02.000\nx\n\nworld\n";
  let joined = "0:00:01.000,0:00:02.000\nx\n\nworld\n0:00:03.000,0:00:04.000\ny\n";
  var ok = err_sbv_is(sbv_parse(tail), "sbv: payload before timing");
  if !err_sbv_is(sbv_parse(joined), "sbv: payload before timing") { ok = false; }
  return assert(ok, "text after a cue must open with a timing line");
}

fn t11() -> TestResult {
  let leading = "hello\n0:00:01.000,0:00:02.000\nx\n";
  let blanks = "\n\nworld\n";
  var ok = err_sbv_is(sbv_parse(leading), "sbv: text before first cue");
  if !err_sbv_is(sbv_parse(blanks), "sbv: text before first cue") { ok = false; }
  return assert(ok, "text before the first cue is Err");
}

fn t12() -> TestResult {
  var ok = err_sbv_is(sbv_parse(""), "sbv: empty input");
  if !err_sbv_is(sbv_parse("\n\n"), "sbv: empty input") { ok = false; }
  if !err_sbv_is(sbv_parse("\r\n\r\n"), "sbv: empty input") { ok = false; }
  return assert(ok, "a document without cue blocks is Err");
}

fn t13() -> TestResult {
  let messy = "\r\n00:00:01.000 , 00:00:02.500\r\nHello\r\nWorld\r\n\r\n\r\n0:00:03.000,0:00:04.000\t\r\nsecond\r\n";
  let want = "0:00:01.000,0:00:02.500\nHello\nWorld\n\n0:00:03.000,0:00:04.000\nsecond\n";
  let r = sbv_parse(messy);
  if !r.is_ok { return assert(false, "canonical output normalizes hours, commas and blanks"); }
  let s = r.value;
  let f: Str = sbv_format(&s);
  return assert(streq(f, want), "canonical output normalizes hours, commas and blanks");
}

fn t14() -> TestResult {
  let doc = "0:00:01.000,0:00:02.500\nhello world\n\n0:00:03.000,0:00:04.000\nsecond cue\nline two\n";
  let r = sbv_parse(doc);
  if !r.is_ok { return assert(false, "canonical documents round-trip parse -> format -> parse"); }
  let s = r.value;
  let f: Str = sbv_format(&s);
  var ok = streq(f, doc);
  let r2 = sbv_parse(f);
  if !r2.is_ok {
    ok = false;
  } else {
    let s2 = r2.value;
    if !same_sbv(&s, &s2) { ok = false; }
    let f2: Str = sbv_format(&s2);
    if !streq(f2, doc) { ok = false; }
  }
  return assert(ok, "canonical documents round-trip parse -> format -> parse");
}

fn t15() -> TestResult {
  let r = sbv_parse(sbv_doc());
  if !r.is_ok { return assert(false, "accessors return sentinels out of range"); }
  let s = r.value;
  var ok = sbv_cue_count(&s) == 2;
  if sbv_cue_start_ms(&s, -1) != -1 { ok = false; }
  if sbv_cue_start_ms(&s, 2) != -1 { ok = false; }
  if sbv_cue_end_ms(&s, -1) != -1 { ok = false; }
  if sbv_cue_end_ms(&s, 9) != -1 { ok = false; }
  if sbv_cue_duration_ms(&s, -1) != -1 { ok = false; }
  if sbv_cue_duration_ms(&s, 2) != -1 { ok = false; }
  if sbv_cue_line_count(&s, -1) != 0 { ok = false; }
  if sbv_cue_line_count(&s, 2) != 0 { ok = false; }
  let l_lo: Str = sbv_cue_line(&s, 0, -1);
  let l_hi: Str = sbv_cue_line(&s, 0, 99);
  if !streq(l_lo, "") { ok = false; }
  if !streq(l_hi, "") { ok = false; }
  let t_lo: Str = sbv_cue_text(&s, -1);
  let t_hi: Str = sbv_cue_text(&s, 7);
  if !streq(t_lo, "") { ok = false; }
  if !streq(t_hi, "") { ok = false; }
  return assert(ok, "accessors return sentinels out of range");
}

fn t16() -> TestResult {
  let doc = "0:00:01.000,0:00:02.000\nhéllo — 世界\n   \nnaïve ✓\n";
  let r = sbv_parse(doc);
  if !r.is_ok { return assert(false, "payload bytes round-trip; whitespace-only lines are text"); }
  let s = r.value;
  var ok = sbv_cue_line_count(&s, 0) == 3;
  let txt: Str = sbv_cue_text(&s, 0);
  if !streq(txt, "héllo — 世界\n   \nnaïve ✓") { ok = false; }
  let f: Str = sbv_format(&s);
  if !streq(f, doc) { ok = false; }
  return assert(ok, "payload bytes round-trip; whitespace-only lines are text");
}

fn t17() -> TestResult {
  let doc = "0:00:01.000,0:00:02.000\nfirst\n0:00:03.000,0:00:04.000\n";
  let r = sbv_parse(doc);
  if !r.is_ok { return assert(false, "payload is greedy: timing-like lines stay text"); }
  let s = r.value;
  var ok = sbv_cue_count(&s) == 1;
  if sbv_cue_line_count(&s, 0) != 2 { ok = false; }
  let l1: Str = sbv_cue_line(&s, 0, 1);
  if !streq(l1, "0:00:03.000,0:00:04.000") { ok = false; }
  let txt: Str = sbv_cue_text(&s, 0);
  if !streq(txt, "first\n0:00:03.000,0:00:04.000") { ok = false; }
  let f: Str = sbv_format(&s);
  if !streq(f, doc) { ok = false; }
  return assert(ok, "payload is greedy: timing-like lines stay text");
}

fn t18() -> TestResult {
  let doc = "0:00:00.000,0:00:00.000\nx\n\n99:59:59.999,99:59:59.999\ny\n";
  let r = sbv_parse(doc);
  if !r.is_ok { return assert(false, "zero, 1 ms and 99-hour boundaries are exact"); }
  let s = r.value;
  var ok = sbv_cue_start_ms(&s, 0) == 0;
  if sbv_cue_end_ms(&s, 0) != 0 { ok = false; }
  if !cue_is(&s, 1, 359999999, 359999999, "y") { ok = false; }
  let f: Str = sbv_format(&s);
  if !streq(f, doc) { ok = false; }
  let one = sbv_parse("0:00:00.000,0:00:00.001\nz\n");
  if !one.is_ok {
    ok = false;
  } else {
    let s3 = one.value;
    if sbv_cue_end_ms(&s3, 0) != 1 { ok = false; }
  }
  return assert(ok, "zero, 1 ms and 99-hour boundaries are exact");
}

fn t19() -> TestResult {
  let sts = Vec[Int].new();
  let ens = Vec[Int].new();
  let ps = Vec[Int].new();
  let pe = Vec[Int].new();
  let ls = Vec[Str].new();
  sts.push(1000);
  ens.push(2000);
  ps.push(5);
  pe.push(9);
  let s = Sbv{ starts: sts; ends: ens; payload_starts: ps; payload_ends: pe; lines: ls; };
  var ok = sbv_cue_count(&s) == 1;
  if sbv_cue_start_ms(&s, 0) != 1000 { ok = false; }
  if sbv_cue_end_ms(&s, 0) != 2000 { ok = false; }
  if sbv_cue_duration_ms(&s, 0) != 1000 { ok = false; }
  if sbv_cue_line_count(&s, 0) != 0 { ok = false; }
  let txt: Str = sbv_cue_text(&s, 0);
  if !streq(txt, "") { ok = false; }
  let f: Str = sbv_format(&s);
  if !streq(f, "0:00:01.000,0:00:02.000\n") { ok = false; }
  return assert(ok, "drifted vectors are clamped, never read out of bounds");
}

fn t20() -> TestResult {
  let doc = "0:00:01.000,0:00:02.500\nx\n\n0:00:03.000,0:00:03.000\ny\n";
  let r = sbv_parse(doc);
  if !r.is_ok { return assert(false, "cue durations are end minus start"); }
  let s = r.value;
  var ok = sbv_cue_duration_ms(&s, 0) == 1500;
  if sbv_cue_duration_ms(&s, 1) != 0 { ok = false; }
  if sbv_cue_duration_ms(&s, -1) != -1 { ok = false; }
  if sbv_cue_duration_ms(&s, 5) != -1 { ok = false; }
  return assert(ok, "cue durations are end minus start");
}

fn main() -> Int {
  io.println("=== xiom.sbv conformance tests ===");
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
    io.println("xiom.sbv: all tests passed");
  } else {
    io.println("xiom.sbv: tests failed");
  }
  return failed;
}
