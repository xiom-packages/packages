// XIOM -- xiom.subtitle conformance tests (20 checks)
// Port task: prove the pure-XIOM xiom.subtitle module (SRT + WebVTT).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Covers the documented API: SRT parsing (two cues, multi-line text, CRLF,
// exact millisecond times), SRT formatting (re-numbering, LF, blank
// separators, exact output), WebVTT parsing (header, NOTE blocks, '.' and
// ',' timestamps, ignored cue settings), WebVTT formatting, shifting with
// clamping, total duration, the strict index policy, the error catalog, the
// cue accessors including out-of-range sentinels, and empty inputs.
//
// All Str equality goes through str_compare (BUG 17 discipline: `==` on Str
// values read from Vec[Str] lowers to a pointer comparison), and every
// element read goes through a typed local.

module subtitle_tests
use xiom.io; use xiom.test; use xiom.subtitle;
use xiom.string.compare;

// Shared two-cue SRT document. srt_format of the parsed track reproduces
// this exact text (test t6).
fn srt_doc() -> Str {
  return "1\n00:00:01,000 --> 00:00:02,500\nhello world\n\n2\n00:00:03,000 --> 00:00:04,000\nsecond cue\n";
}

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn cue_is(s: &Subtitle, i: Int, want_a: Int, want_b: Int, want_text: Str) -> Bool {
  if subtitle_start_ms(s, i) != want_a { return false; }
  if subtitle_end_ms(s, i) != want_b { return false; }
  let got: Str = subtitle_text(s, i);
  return streq(got, want_text);
}

fn same_sub(a: &Subtitle, b: &Subtitle) -> Bool {
  let na = subtitle_cue_count(a);
  if na != subtitle_cue_count(b) { return false; }
  var i = 0;
  while i < na {
    if subtitle_start_ms(a, i) != subtitle_start_ms(b, i) { return false; }
    if subtitle_end_ms(a, i) != subtitle_end_ms(b, i) { return false; }
    let ta: Str = subtitle_text(a, i);
    let tb: Str = subtitle_text(b, i);
    if !streq(ta, tb) { return false; }
    i = i + 1;
  }
  return true;
}

fn err_sub_is(r: Result[Subtitle, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return streq(r.error, want);
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  let r = srt_parse(srt_doc());
  if !r.is_ok { return assert(false, "srt_parse: two cues with exact times"); }
  let s = r.value;
  var ok = subtitle_cue_count(&s) == 2;
  if !cue_is(&s, 0, 1000, 2500, "hello world") { ok = false; }
  if !cue_is(&s, 1, 3000, 4000, "second cue") { ok = false; }
  return assert(ok, "srt_parse: two cues with exact times");
}

fn t2() -> TestResult {
  let doc = "1\n00:00:01,000 --> 00:00:04,000\nfirst line\nsecond line\nthird\n";
  let r = srt_parse(doc);
  if !r.is_ok { return assert(false, "srt_parse: multi-line cue text joins with LF"); }
  let s = r.value;
  var ok = subtitle_cue_count(&s) == 1;
  if !cue_is(&s, 0, 1000, 4000, "first line\nsecond line\nthird") { ok = false; }
  return assert(ok, "srt_parse: multi-line cue text joins with LF");
}

fn t3() -> TestResult {
  let doc = "1\r\n00:00:01,000 --> 00:00:02,000\r\nline one\r\nline two\r\n\r\n2\r\n00:00:03,000 --> 00:00:04,000\r\nlast\r\n";
  let r = srt_parse(doc);
  if !r.is_ok { return assert(false, "srt_parse: CRLF documents parse like LF"); }
  let s = r.value;
  var ok = subtitle_cue_count(&s) == 2;
  if !cue_is(&s, 0, 1000, 2000, "line one\nline two") { ok = false; }
  if !cue_is(&s, 1, 3000, 4000, "last") { ok = false; }
  return assert(ok, "srt_parse: CRLF documents parse like LF");
}

fn t4() -> TestResult {
  let doc = "1\n01:02:03,456 --> 10:00:00,000\nx\n";
  let r = srt_parse(doc);
  if !r.is_ok { return assert(false, "timestamps parse to exact milliseconds"); }
  let s = r.value;
  var ok = subtitle_start_ms(&s, 0) == 3723456;
  if subtitle_end_ms(&s, 0) != 36000000 { ok = false; }
  let one = srt_parse("1\n00:00:00,000 --> 00:00:00,001\ny\n");
  if !one.is_ok {
    ok = false;
  } else {
    let s2 = one.value;
    if subtitle_end_ms(&s2, 0) != 1 { ok = false; }
  }
  return assert(ok, "timestamps parse to exact milliseconds");
}

fn t5() -> TestResult {
  let r = srt_parse(srt_doc());
  if !r.is_ok { return assert(false, "srt_format -> srt_parse round-trips"); }
  let s = r.value;
  let f = srt_format(&s);
  let r2 = srt_parse(f);
  if !r2.is_ok { return assert(false, "srt_format -> srt_parse round-trips"); }
  let s2 = r2.value;
  return assert(same_sub(&s, &s2), "srt_format -> srt_parse round-trips");
}

fn t6() -> TestResult {
  let r = srt_parse(srt_doc());
  if !r.is_ok { return assert(false, "srt_format re-numbers from 1 and joins with LF"); }
  let s = r.value;
  let f = srt_format(&s);
  return assert(streq(f, srt_doc()), "srt_format re-numbers from 1 and joins with LF");
}

fn t7() -> TestResult {
  let doc = "WEBVTT\n\nNOTE this comment\nspans two lines\n\n00:00:01.000 --> 00:00:02.000\nfirst\n\n00:00:03.000 --> 00:00:04.000\nsecond\n";
  let r = vtt_parse(doc);
  if !r.is_ok { return assert(false, "vtt_parse: header + NOTE skipped, two cues"); }
  let s = r.value;
  var ok = subtitle_cue_count(&s) == 2;
  if !cue_is(&s, 0, 1000, 2000, "first") { ok = false; }
  if !cue_is(&s, 1, 3000, 4000, "second") { ok = false; }
  return assert(ok, "vtt_parse: header + NOTE skipped, two cues");
}

fn t8() -> TestResult {
  let dot = "WEBVTT\n\n01:02:03.456 --> 01:02:04.500\nx\n";
  let comma = "WEBVTT\n\n01:02:03,456 --> 01:02:04,500\nx\n";
  let rd = vtt_parse(dot);
  if !rd.is_ok { return assert(false, "vtt timestamps use '.' and also accept ','"); }
  let sd = rd.value;
  var ok = subtitle_start_ms(&sd, 0) == 3723456;
  if subtitle_end_ms(&sd, 0) != 3724500 { ok = false; }
  let rc = vtt_parse(comma);
  if !rc.is_ok {
    ok = false;
  } else {
    let sc = rc.value;
    if subtitle_start_ms(&sc, 0) != 3723456 { ok = false; }
  }
  return assert(ok, "vtt timestamps use '.' and also accept ','");
}

fn t9() -> TestResult {
  let doc = "WEBVTT\n\n00:00:01.000 --> 00:00:02.000 align:middle line:90% position:50%\ntext\n";
  let r = vtt_parse(doc);
  if !r.is_ok { return assert(false, "vtt cue settings after the arrow are ignored"); }
  let s = r.value;
  var ok = subtitle_cue_count(&s) == 1;
  if !cue_is(&s, 0, 1000, 2000, "text") { ok = false; }
  return assert(ok, "vtt cue settings after the arrow are ignored");
}

fn t10() -> TestResult {
  let doc = "WEBVTT\n\n00:00:01.000 --> 00:00:02.500\nhello world\n\n00:00:03.000 --> 00:00:04.000\nsecond cue\n";
  let r = vtt_parse(doc);
  if !r.is_ok { return assert(false, "vtt_format -> vtt_parse round-trips without indices"); }
  let s = r.value;
  let f = vtt_format(&s);
  var ok = streq(f, doc);
  let r2 = vtt_parse(f);
  if !r2.is_ok {
    ok = false;
  } else {
    let s2 = r2.value;
    if !same_sub(&s, &s2) { ok = false; }
  }
  return assert(ok, "vtt_format -> vtt_parse round-trips without indices");
}

fn t11() -> TestResult {
  let r = srt_parse(srt_doc());
  if !r.is_ok { return assert(false, "subtitle_shift(+1500) shifts both times"); }
  let s = r.value;
  let m = subtitle_shift(&s, 1500);
  var ok = subtitle_cue_count(&m) == 2;
  if !cue_is(&m, 0, 2500, 4000, "hello world") { ok = false; }
  if !cue_is(&m, 1, 4500, 5500, "second cue") { ok = false; }
  if subtitle_start_ms(&s, 0) != 1000 { ok = false; }
  return assert(ok, "subtitle_shift(+1500) shifts both times");
}

fn t12() -> TestResult {
  let r = srt_parse(srt_doc());
  if !r.is_ok { return assert(false, "subtitle_shift(-2500) clamps both times at 0"); }
  let s = r.value;
  let m = subtitle_shift(&s, -2500);
  var ok = subtitle_cue_count(&m) == 2;
  if !cue_is(&m, 0, 0, 0, "hello world") { ok = false; }
  if !cue_is(&m, 1, 500, 1500, "second cue") { ok = false; }
  return assert(ok, "subtitle_shift(-2500) clamps both times at 0");
}

fn t13() -> TestResult {
  let r = srt_parse(srt_doc());
  if !r.is_ok { return assert(false, "subtitle_total_duration_ms is the max end"); }
  let s = r.value;
  var ok = subtitle_total_duration_ms(&s) == 4000;
  let e = vtt_parse("WEBVTT\n");
  if !e.is_ok {
    ok = false;
  } else {
    let es = e.value;
    if subtitle_total_duration_ms(&es) != 0 { ok = false; }
  }
  return assert(ok, "subtitle_total_duration_ms is the max end");
}

fn t14() -> TestResult {
  let one_dash = "1\n00:00:01,000 -> 00:00:02,000\nx\n";
  let two_dash = "1\n00:00:01,000 -- 00:00:02,000\nx\n";
  var ok = err_sub_is(srt_parse(one_dash), "subtitle: missing arrow");
  if !err_sub_is(srt_parse(two_dash), "subtitle: missing arrow") { ok = false; }
  let vtt = "WEBVTT\n\n00:00:01.000 - 00:00:02.000\nx\n";
  if !err_sub_is(vtt_parse(vtt), "subtitle: missing arrow") { ok = false; }
  return assert(ok, "a timestamp line without an arrow is Err");
}

fn t15() -> TestResult {
  let short_ms = "1\n00:00:01,00 --> 00:00:02,000\nx\n";
  let minute = "1\n00:60:00,000 --> 00:00:02,000\nx\n";
  let second = "1\n00:00:61,000 --> 00:00:02,000\nx\n";
  let alpha = "1\n0a:00:01,000 --> 00:00:02,000\nx\n";
  let seps = "1\n00-00-01,000 --> 00:00:02,000\nx\n";
  var ok = err_sub_is(srt_parse(short_ms), "subtitle: bad time");
  if !err_sub_is(srt_parse(minute), "subtitle: bad time") { ok = false; }
  if !err_sub_is(srt_parse(second), "subtitle: bad time") { ok = false; }
  if !err_sub_is(srt_parse(alpha), "subtitle: bad time") { ok = false; }
  if !err_sub_is(srt_parse(seps), "subtitle: bad time") { ok = false; }
  return assert(ok, "malformed timestamps are Err(\"subtitle: bad time\")");
}

fn t16() -> TestResult {
  let first_two = "2\n00:00:01,000 --> 00:00:02,000\nx\n";
  let non_numeric = "x\n00:00:01,000 --> 00:00:02,000\nx\n";
  let zero = "0\n00:00:01,000 --> 00:00:02,000\nx\n";
  let jump = "1\n00:00:01,000 --> 00:00:02,000\nx\n\n3\n00:00:03,000 --> 00:00:04,000\ny\n";
  var ok = err_sub_is(srt_parse(first_two), "subtitle: bad index");
  if !err_sub_is(srt_parse(non_numeric), "subtitle: bad index") { ok = false; }
  if !err_sub_is(srt_parse(zero), "subtitle: bad index") { ok = false; }
  if !err_sub_is(srt_parse(jump), "subtitle: bad index") { ok = false; }
  return assert(ok, "cue indices must be strictly sequential from 1");
}

fn t17() -> TestResult {
  let no_text = "1\n00:00:01,000 --> 00:00:02,000\n";
  let no_ts = "1\n";
  let vtt_no_head = "00:00:01.000 --> 00:00:02.000\nx\n";
  let vtt_bad_head = "WEBVTTX\n\n00:00:01.000 --> 00:00:02.000\nx\n";
  let vtt_no_text = "WEBVTT\n\n00:00:01.000 --> 00:00:02.000\n";
  var ok = err_sub_is(srt_parse(no_text), "subtitle: missing cue text");
  if !err_sub_is(srt_parse(no_ts), "subtitle: malformed block") { ok = false; }
  if !err_sub_is(vtt_parse(vtt_no_head), "subtitle: missing WEBVTT header") { ok = false; }
  if !err_sub_is(vtt_parse(vtt_bad_head), "subtitle: missing WEBVTT header") { ok = false; }
  if !err_sub_is(vtt_parse(vtt_no_text), "subtitle: missing cue text") { ok = false; }
  return assert(ok, "structural errors carry the documented messages");
}

fn t18() -> TestResult {
  let r1 = srt_parse("");
  let r2 = srt_parse("\n\n");
  let r3 = vtt_parse("");
  var ok = err_sub_is(r1, "subtitle: empty input");
  if !err_sub_is(r2, "subtitle: empty input") { ok = false; }
  if !err_sub_is(r3, "subtitle: missing WEBVTT header") { ok = false; }
  let e = vtt_parse("WEBVTT\n");
  if !e.is_ok {
    ok = false;
  } else {
    let es = e.value;
    if subtitle_cue_count(&es) != 0 { ok = false; }
    if !streq(vtt_format(&es), "WEBVTT\n") { ok = false; }
    if !streq(srt_format(&es), "") { ok = false; }
  }
  return assert(ok, "empty documents: SRT is Err, an empty VTT is valid");
}

fn t19() -> TestResult {
  let r = srt_parse(srt_doc());
  if !r.is_ok { return assert(false, "accessors return cue fields and sentinels"); }
  let s = r.value;
  var ok = subtitle_cue_count(&s) == 2;
  if subtitle_start_ms(&s, 0) != 1000 { ok = false; }
  if subtitle_start_ms(&s, 1) != 3000 { ok = false; }
  if subtitle_end_ms(&s, 0) != 2500 { ok = false; }
  if subtitle_end_ms(&s, 1) != 4000 { ok = false; }
  if subtitle_start_ms(&s, -1) != -1 { ok = false; }
  if subtitle_start_ms(&s, 2) != -1 { ok = false; }
  if subtitle_end_ms(&s, -1) != -1 { ok = false; }
  if subtitle_end_ms(&s, 9) != -1 { ok = false; }
  let oob_hi: Str = subtitle_text(&s, 2);
  if !streq(oob_hi, "") { ok = false; }
  let oob_lo: Str = subtitle_text(&s, -1);
  if !streq(oob_lo, "") { ok = false; }
  return assert(ok, "accessors return cue fields and sentinels");
}

fn t20() -> TestResult {
  let e = vtt_parse("WEBVTT\n\nNOTE only a comment\n");
  if !e.is_ok { return assert(false, "an empty VTT shifts to an empty track"); }
  let es = e.value;
  var ok = subtitle_cue_count(&es) == 0;
  let m = subtitle_shift(&es, 2500);
  if subtitle_cue_count(&m) != 0 { ok = false; }
  if subtitle_total_duration_ms(&m) != 0 { ok = false; }
  if !streq(srt_format(&m), "") { ok = false; }
  if !streq(vtt_format(&m), "WEBVTT\n") { ok = false; }
  return assert(ok, "an empty VTT shifts to an empty track");
}

fn main() -> Int {
  io.println("=== xiom.subtitle conformance tests ===");
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
    io.println("xiom.subtitle: all tests passed");
  } else {
    io.println("xiom.subtitle: tests failed");
  }
  return failed;
}
