// XIOM -- xiom.lrc conformance tests (21 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Port task: prove the pure-XIOM xiom.lrc module against its documented
// grammar, error catalog and round-trip rules.
//
// Coverage: metadata tags, centis/millis timestamps, multiple timestamps per
// line, verbatim entry text, canonical emission (metadata order, source
// order, fraction normalization, signed offset), parse -> emit -> parse round
// trips, CRLF and missing final LF, skipped untimed lines, all seven error
// messages, offset semantics, accessor sentinels, empty/untimed-only
// documents, duplicate tags and zero-offset normalization.
//
// All Str equality goes through str_compare: BUG 17 lowers `==` on Str values
// read from Vec[Str] elements to a pointer comparison, so every comparison
// below is routed through streq and every Vec element read binds a typed
// local first. Test functions are called directly from main (no indexed
// Vec[fn] dispatch, which miscompiles).

module lrc_tests
use xiom.io; use xiom.test; use xiom.lrc;
use xiom.string;
use xiom.string.compare;

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn err_is(r: Result[Lyrics, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  let e: Str = r.error;
  return streq(e, want);
}

fn err_prefix(r: Result[Lyrics, Str], prefix: Str) -> Bool {
  if r.is_ok { return false; }
  let e: Str = r.error;
  return string.str_starts_with(e, prefix);
}

fn entry_is(l: &Lyrics, i: Int, ms: Int, text: Str) -> Bool {
  if lrc_time_ms(l, i) != ms { return false; }
  let got: Str = lrc_text(l, i);
  return streq(got, text);
}

fn same_lyrics(a: &Lyrics, b: &Lyrics) -> Bool {
  if !streq(lrc_title(a), lrc_title(b)) { return false; }
  if !streq(lrc_artist(a), lrc_artist(b)) { return false; }
  if !streq(lrc_album(a), lrc_album(b)) { return false; }
  if !streq(lrc_by(a), lrc_by(b)) { return false; }
  if lrc_offset_ms(a) != lrc_offset_ms(b) { return false; }
  if lrc_entry_count(a) != lrc_entry_count(b) { return false; }
  var i = 0;
  while i < lrc_entry_count(a) {
    if lrc_time_ms(a, i) != lrc_time_ms(b, i) { return false; }
    let ta: Str = lrc_text(a, i);
    let tb: Str = lrc_text(b, i);
    if !streq(ta, tb) { return false; }
    i = i + 1;
  }
  return true;
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  let doc = "[ti:Blue Hour]\n[ar:The XIOMs]\n[al:Port Works]\n[by:E. Notas]\n[offset:+250]\n[00:12.34]First line\n[00:15.00][00:18.50]Chorus\n";
  let r = lrc_parse(doc);
  if !r.is_ok { return assert(false, "parse: metadata tags and timed entries"); }
  let l = r.value;
  var ok = lrc_entry_count(&l) == 3;
  if !streq(lrc_title(&l), "Blue Hour") { ok = false; }
  if !streq(lrc_artist(&l), "The XIOMs") { ok = false; }
  if !streq(lrc_album(&l), "Port Works") { ok = false; }
  if !streq(lrc_by(&l), "E. Notas") { ok = false; }
  if lrc_offset_ms(&l) != 250 { ok = false; }
  if !entry_is(&l, 0, 12340, "First line") { ok = false; }
  if !entry_is(&l, 1, 15000, "Chorus") { ok = false; }
  if !entry_is(&l, 2, 18500, "Chorus") { ok = false; }
  return assert(ok, "parse: metadata tags and timed entries");
}

fn t2() -> TestResult {
  let doc = "[00:00.00]zero\n[01:02.03]centis\n[01:02.034]millis\n[59:59.999]last\n";
  let r = lrc_parse(doc);
  if !r.is_ok { return assert(false, "timestamps: centis and millis convert exactly"); }
  let l = r.value;
  var ok = lrc_entry_count(&l) == 4;
  if !entry_is(&l, 0, 0, "zero") { ok = false; }
  if !entry_is(&l, 1, 62030, "centis") { ok = false; }
  if !entry_is(&l, 2, 62034, "millis") { ok = false; }
  if !entry_is(&l, 3, 3599999, "last") { ok = false; }
  return assert(ok, "timestamps: centis and millis convert exactly");
}

fn t3() -> TestResult {
  let doc = "[00:03.00][00:01.00][00:02.00]line\n";
  let r = lrc_parse(doc);
  if !r.is_ok { return assert(false, "multiple timestamps on one line keep source order"); }
  let l = r.value;
  var ok = lrc_entry_count(&l) == 3;
  if !entry_is(&l, 0, 3000, "line") { ok = false; }
  if !entry_is(&l, 1, 1000, "line") { ok = false; }
  if !entry_is(&l, 2, 2000, "line") { ok = false; }
  return assert(ok, "multiple timestamps on one line keep source order");
}

fn t4() -> TestResult {
  let doc = "[00:01.00] spaced \n[00:02.00]\nplain text\n   \n[ar:Artist]\n";
  let r = lrc_parse(doc);
  if !r.is_ok { return assert(false, "entry text is verbatim after the last timestamp"); }
  let l = r.value;
  var ok = lrc_entry_count(&l) == 2;
  if !entry_is(&l, 0, 1000, " spaced ") { ok = false; }
  if !entry_is(&l, 1, 2000, "") { ok = false; }
  if !streq(lrc_artist(&l), "Artist") { ok = false; }
  return assert(ok, "entry text is verbatim after the last timestamp");
}

fn t5() -> TestResult {
  let doc = "[00:05.00]A\n[ti:Title]\n[ar:Artist]\n[al:Album]\n[by:Writer]\n[offset:-100]\n[00:12.345]B\n";
  let r = lrc_parse(doc);
  if !r.is_ok { return assert(false, "emit: canonical metadata order and entry order"); }
  let l = r.value;
  let got = lrc_emit(&l);
  let want = "[ti:Title]\n[ar:Artist]\n[al:Album]\n[by:Writer]\n[offset:-100]\n[00:05.00]A\n[00:12.345]B\n";
  return assert(streq(got, want), "emit: canonical metadata order and entry order");
}

fn t6() -> TestResult {
  let doc = "[ti:T]\r\n[ar:A]\r\n[00:01.00]one\r\n[00:02.50][00:03.50]two\r\n[offset:42]\r\n";
  let r1 = lrc_parse(doc);
  if !r1.is_ok { return assert(false, "parse -> emit -> parse round-trips"); }
  let l1 = r1.value;
  let f1 = lrc_emit(&l1);
  let r2 = lrc_parse(f1);
  if !r2.is_ok { return assert(false, "parse -> emit -> parse round-trips"); }
  let l2 = r2.value;
  var ok = same_lyrics(&l1, &l2);
  if lrc_entry_count(&l1) != 3 { ok = false; }
  if !entry_is(&l1, 0, 1000, "one") { ok = false; }
  if !entry_is(&l1, 1, 2500, "two") { ok = false; }
  if !entry_is(&l1, 2, 3500, "two") { ok = false; }
  let f2 = lrc_emit(&l2);
  if !streq(f1, f2) { ok = false; }
  if lrc_offset_ms(&l2) != 42 { ok = false; }
  return assert(ok, "parse -> emit -> parse round-trips");
}

fn t7() -> TestResult {
  let doc = "[ti:T]\r\n[00:01.00]a\r\n[00:02.00]b";
  let r = lrc_parse(doc);
  if !r.is_ok { return assert(false, "CRLF and a missing final LF parse like LF"); }
  let l = r.value;
  var ok = lrc_entry_count(&l) == 2;
  if !streq(lrc_title(&l), "T") { ok = false; }
  if !entry_is(&l, 0, 1000, "a") { ok = false; }
  if !entry_is(&l, 1, 2000, "b") { ok = false; }
  return assert(ok, "CRLF and a missing final LF parse like LF");
}

fn t8() -> TestResult {
  let doc = "plain text\n[00:01.00]x\n   \nnot a timestamp [00:09.00]\n";
  let r = lrc_parse(doc);
  if !r.is_ok { return assert(false, "untimed lines are skipped"); }
  let l = r.value;
  var ok = lrc_entry_count(&l) == 1;
  if !entry_is(&l, 0, 1000, "x") { ok = false; }
  return assert(ok, "untimed lines are skipped");
}

fn t9() -> TestResult {
  var ok = err_is(lrc_parse("[00:1.50]x\n"), "lrc: bad timestamp shape");
  if !err_is(lrc_parse("[0:01.50]x\n"), "lrc: bad timestamp shape") { ok = false; }
  if !err_is(lrc_parse("[00-01.50]x\n"), "lrc: bad timestamp shape") { ok = false; }
  if !err_is(lrc_parse("[00:01,50]x\n"), "lrc: bad timestamp shape") { ok = false; }
  if !err_is(lrc_parse("[00:01.5a]x\n"), "lrc: bad timestamp shape") { ok = false; }
  if !err_is(lrc_parse("[00:12]x\n"), "lrc: bad timestamp shape") { ok = false; }
  return assert(ok, "bad timestamp shapes are Err");
}

fn t10() -> TestResult {
  var ok = err_is(lrc_parse("[60:00.00]x\n"), "lrc: time out of range");
  if !err_is(lrc_parse("[00:60.00]x\n"), "lrc: time out of range") { ok = false; }
  if !err_is(lrc_parse("[99:99.99]x\n"), "lrc: time out of range") { ok = false; }
  return assert(ok, "minute/second out of range is Err");
}

fn t11() -> TestResult {
  var ok = err_is(lrc_parse("[00:12.1]x\n"), "lrc: bad fraction length");
  if !err_is(lrc_parse("[00:12.1234]x\n"), "lrc: bad fraction length") { ok = false; }
  if !err_is(lrc_parse("[00:12.12345]x\n"), "lrc: bad fraction length") { ok = false; }
  return assert(ok, "fraction length other than 2 or 3 is Err");
}

fn t12() -> TestResult {
  var ok = err_is(lrc_parse("[offset:abc]\n"), "lrc: bad offset value");
  if !err_is(lrc_parse("[offset:]\n"), "lrc: bad offset value") { ok = false; }
  if !err_is(lrc_parse("[offset:1.5]\n"), "lrc: bad offset value") { ok = false; }
  if !err_is(lrc_parse("[offset:--5]\n"), "lrc: bad offset value") { ok = false; }
  if !err_is(lrc_parse("[offset:+]\n"), "lrc: bad offset value") { ok = false; }
  if !err_is(lrc_parse("[offset: 5]\n"), "lrc: bad offset value") { ok = false; }
  if !err_is(lrc_parse("[offset:1234567890123456789]\n"), "lrc: bad offset value") { ok = false; }
  let p = lrc_parse("[offset:+250]\n");
  if !p.is_ok { return assert(false, "offset values: signed integers only"); }
  let lp = p.value;
  if lrc_offset_ms(&lp) != 250 { ok = false; }
  let m = lrc_parse("[offset:-250]\n");
  if !m.is_ok {
    ok = false;
  } else {
    let lm = m.value;
    if lrc_offset_ms(&lm) != -250 { ok = false; }
  }
  let z = lrc_parse("[offset:0]\n");
  if !z.is_ok {
    ok = false;
  } else {
    let lz = z.value;
    if lrc_offset_ms(&lz) != 0 { ok = false; }
  }
  let u = lrc_parse("[offset:999]\n");
  if !u.is_ok {
    ok = false;
  } else {
    let lu = u.value;
    if lrc_offset_ms(&lu) != 999 { ok = false; }
  }
  return assert(ok, "offset values: signed integers only");
}

fn t13() -> TestResult {
  var ok = err_is(lrc_parse("[ti]\n"), "lrc: tag missing colon");
  if !err_is(lrc_parse("[Chorus]\n"), "lrc: tag missing colon") { ok = false; }
  if !err_is(lrc_parse("[]\n"), "lrc: tag missing colon") { ok = false; }
  return assert(ok, "a bracket tag without a colon is Err");
}

fn t14() -> TestResult {
  var ok = err_is(lrc_parse("[00:12.34\n"), "lrc: unclosed bracket");
  if !err_is(lrc_parse("[ti:Title\n"), "lrc: unclosed bracket") { ok = false; }
  if !err_is(lrc_parse("[00:01.00][00:02.00\n"), "lrc: unclosed bracket") { ok = false; }
  return assert(ok, "unclosed brackets are Err");
}

fn t15() -> TestResult {
  var ok = err_prefix(lrc_parse("[re:some]\n"), "lrc: unknown tag");
  if !err_prefix(lrc_parse("[length:03:12]\n"), "lrc: unknown tag") { ok = false; }
  if !err_prefix(lrc_parse("[:x]\n"), "lrc: unknown tag") { ok = false; }
  return assert(ok, "unknown tag names are Err");
}

fn t16() -> TestResult {
  let r = lrc_parse("[offset:-250]\n[00:00.10]a\n[00:01.00]b\n");
  if !r.is_ok { return assert(false, "offset accessor and adjusted times"); }
  let l = r.value;
  var ok = lrc_offset_ms(&l) == -250;
  if lrc_time_ms(&l, 0) != 100 { ok = false; }
  if lrc_adjusted_time_ms(&l, 0) != 0 { ok = false; }
  if lrc_time_ms(&l, 1) != 1000 { ok = false; }
  if lrc_adjusted_time_ms(&l, 1) != 750 { ok = false; }
  if lrc_adjusted_time_ms(&l, -1) != -1 { ok = false; }
  if lrc_adjusted_time_ms(&l, 5) != -1 { ok = false; }
  let p = lrc_parse("[offset:+100]\n[00:00.10]a\n");
  if !p.is_ok {
    ok = false;
  } else {
    let lp = p.value;
    if lrc_adjusted_time_ms(&lp, 0) != 200 { ok = false; }
  }
  return assert(ok, "offset accessor and adjusted times");
}

fn t17() -> TestResult {
  let r = lrc_parse("[ti:T]\n[ar:A]\n[al:L]\n[by:B]\n[00:01.00]x\n");
  if !r.is_ok { return assert(false, "accessors return values and out-of-range sentinels"); }
  let l = r.value;
  var ok = lrc_entry_count(&l) == 1;
  if lrc_time_ms(&l, 0) != 1000 { ok = false; }
  if lrc_time_ms(&l, -1) != -1 { ok = false; }
  if lrc_time_ms(&l, 1) != -1 { ok = false; }
  let t0: Str = lrc_text(&l, 0);
  if !streq(t0, "x") { ok = false; }
  let low: Str = lrc_text(&l, -1);
  if !streq(low, "") { ok = false; }
  let high: Str = lrc_text(&l, 9);
  if !streq(high, "") { ok = false; }
  return assert(ok, "accessors return values and out-of-range sentinels");
}

fn t18() -> TestResult {
  let r1 = lrc_parse("");
  if !r1.is_ok { return assert(false, "empty and untimed-only documents are valid"); }
  let e1 = r1.value;
  var ok = lrc_entry_count(&e1) == 0;
  let f1: Str = lrc_emit(&e1);
  if !streq(f1, "") { ok = false; }
  let r2 = lrc_parse("\n\n");
  if !r2.is_ok {
    ok = false;
  } else {
    let e2 = r2.value;
    if lrc_entry_count(&e2) != 0 { ok = false; }
  }
  let r3 = lrc_parse("just words\nmore words\n");
  if !r3.is_ok {
    ok = false;
  } else {
    let e3 = r3.value;
    if lrc_entry_count(&e3) != 0 { ok = false; }
  }
  let r4 = lrc_parse("[ti:Only]\n");
  if !r4.is_ok {
    ok = false;
  } else {
    let e4 = r4.value;
    if lrc_entry_count(&e4) != 0 { ok = false; }
    if !streq(lrc_title(&e4), "Only") { ok = false; }
    let f4: Str = lrc_emit(&e4);
    if !streq(f4, "[ti:Only]\n") { ok = false; }
  }
  return assert(ok, "empty and untimed-only documents are valid");
}

fn t19() -> TestResult {
  let doc = "[ti:First]\n[00:01.00]a\n[ti:Second]\n[ar:A]\n[00:02.00]b\n";
  let r = lrc_parse(doc);
  if !r.is_ok { return assert(false, "duplicate tags: the last one wins; tags may follow entries"); }
  let l = r.value;
  var ok = lrc_entry_count(&l) == 2;
  if !streq(lrc_title(&l), "Second") { ok = false; }
  if !streq(lrc_artist(&l), "A") { ok = false; }
  if !entry_is(&l, 0, 1000, "a") { ok = false; }
  if !entry_is(&l, 1, 2000, "b") { ok = false; }
  return assert(ok, "duplicate tags: the last one wins; tags may follow entries");
}

fn t20() -> TestResult {
  let doc = "[offset:0]\n[00:01.500]a\n[00:01.234]b\n";
  let r1 = lrc_parse(doc);
  if !r1.is_ok { return assert(false, "emit normalizes fractions and drops a zero offset"); }
  let l1 = r1.value;
  let f1 = lrc_emit(&l1);
  var ok = streq(f1, "[00:01.50]a\n[00:01.234]b\n");
  let r2 = lrc_parse(f1);
  if !r2.is_ok {
    ok = false;
  } else {
    let l2 = r2.value;
    if !same_lyrics(&l1, &l2) { ok = false; }
    if !entry_is(&l2, 0, 1500, "a") { ok = false; }
    if !entry_is(&l2, 1, 1234, "b") { ok = false; }
    let f2 = lrc_emit(&l2);
    if !streq(f1, f2) { ok = false; }
  }
  return assert(ok, "emit normalizes fractions and drops a zero offset");
}

// A hand-built Lyrics: parse never produces a negative time or one above
// 59:59.999, so these emit edge cases need a manual value.
fn manual_lyrics() -> Lyrics {
  var times = Vec[Int].new();
  var texts = Vec[Str].new();
  times.push(-5);
  times.push(3600000);
  texts.push("neg");
  texts.push("hour");
  return Lyrics{
    title: "";
    artist: "";
    album: "";
    by_text: "";
    offset_ms: 0;
    times: times;
    texts: texts;
  };
}

fn t21() -> TestResult {
  let l = manual_lyrics();
  let f = lrc_emit(&l);
  var ok = lrc_entry_count(&l) == 2;
  if lrc_time_ms(&l, 0) != -5 { ok = false; }
  if !streq(f, "[00:00.00]neg\n[60:00.00]hour\n") { ok = false; }
  if !err_prefix(lrc_parse(f), "lrc:") { ok = false; }
  return assert(ok, "emit clamps negative times and prints total minutes");
}

fn main() -> Int {
  io.println("=== xiom.lrc conformance tests ===");
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
    io.println("xiom.lrc: all tests passed");
  } else {
    io.println("xiom.lrc: tests failed");
  }
  return failed;
}
