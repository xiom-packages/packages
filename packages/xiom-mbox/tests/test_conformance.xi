// XIOM -- xiom.mbox conformance tests (18 checks)
// Greenfield package: prove the pure-XIOM xiom.mbox module against its
// documented separation rules, mboxrd quoting stance, byte-range accessors,
// header-separator detection, canonical emitter and error catalog.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Coverage: empty mailbox, leading-text errors, envelope/address/date raw
// text, LF/CRLF/mixed endings, bare CR as data, delimiter only at offset 0 or
// after an empty line, From-looking body lines, mboxrd raw vs decoded bodies,
// body offset/length spans up to the next delimiter, unterminated final
// message, header separator detection (with and without blank lines),
// caller-buffer body materialization, invalid indices, canonical emit shape,
// byte-for-byte round-trips and emit idempotence.
//
// All Str equality goes through str_compare: BUG 17 lowers `==` on Str values
// read from Vec[Str] elements to a pointer comparison, so every comparison
// below is routed through streq instead of `==`.

module mbox_tests
use xiom.io; use xiom.test; use xiom.mbox;
use xiom.string;
use xiom.string.builder;
use xiom.string.compare;

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// An empty mailbox, for the failure path of parse_ok.
fn empty_mb() -> Mailbox {
  return Mailbox{
    pool: "";
    env_start: Vec[Int].new();
    env_end: Vec[Int].new();
    body_start: Vec[Int].new();
    body_end: Vec[Int].new();
  };
}

// Parse `text`, expecting Ok; an empty mailbox is returned when it is Err, so
// the test's own assertions decide the verdict.
fn parse_ok(text: Str) -> Mailbox {
  let r = mbox_parse(text);
  match r {
    Ok(m) => { return m; },
    Err(_) => { return empty_mb(); },
  }
  return empty_mb();
}

// True when `text` fails to parse with an "mbox: " error message.
fn parse_err_prefix(text: Str) -> Bool {
  let r = mbox_parse(text);
  match r {
    Ok(_) => { return false; },
    Err(e) => { return string.str_starts_with(e, "mbox: "); },
  }
  return false;
}

// Message i's decoded body as a Str (mbox_body_into into a fresh buffer).
fn body_str(m: &Mailbox, i: Int) -> Str {
  var buf = Vec[UInt8].new();
  let n = mbox_body_into(m, i, &mut buf);
  if n != buf.len() { return "!append-count-mismatch"; }
  return builder.sb_to_str(&buf);
}

fn t1() -> TestResult {
  let e = parse_ok("");
  var ok = mbox_count(&e) == 0;
  if !streq(mbox_envelope_line(&e, 0), "") { ok = false; }
  if mbox_body_offset(&e, 0) != -1 { ok = false; }
  if !parse_err_prefix("not a mailbox\nFrom a\n") { ok = false; }
  if !parse_err_prefix("\nFrom a\n") { ok = false; }
  if !parse_err_prefix(" From a\n") { ok = false; }
  if !parse_err_prefix("From\n") { ok = false; }
  if !parse_err_prefix("From\tx\n") { ok = false; }
  return assert(ok, "empty mailbox is Ok with zero messages; leading text is Err");
}

fn t2() -> TestResult {
  let text = "From alice@example.com Mon Jan  1 00:00:00 2024\nH: v\n\nline1\nline2\n";
  let m = parse_ok(text);
  var ok = mbox_count(&m) == 1;
  if !streq(mbox_envelope_line(&m, 0), "From alice@example.com Mon Jan  1 00:00:00 2024") { ok = false; }
  if !streq(mbox_envelope_address(&m, 0), "alice@example.com") { ok = false; }
  if !streq(mbox_envelope_date(&m, 0), "Mon Jan  1 00:00:00 2024") { ok = false; }
  if mbox_body_offset(&m, 0) != 48 { ok = false; }
  if mbox_body_len(&m, 0) != 18 { ok = false; }
  if !streq(mbox_body_raw(&m, 0), "H: v\n\nline1\nline2\n") { ok = false; }
  if !streq(body_str(&m, 0), "H: v\n\nline1\nline2\n") { ok = false; }
  if mbox_header_separator(&m, 0) != 53 { ok = false; }
  if mbox_header_body_start(&m, 0) != 54 { ok = false; }
  return assert(ok, "single LF message: envelope, address, date, body span and separator");
}

fn t3() -> TestResult {
  let text = "From a@x\nA: 1\n\nm1\n\nFrom b@y\nB: 2\n\nm2\n";
  let m = parse_ok(text);
  var ok = mbox_count(&m) == 2;
  if !streq(mbox_envelope_line(&m, 0), "From a@x") { ok = false; }
  if !streq(mbox_envelope_line(&m, 1), "From b@y") { ok = false; }
  if !streq(mbox_envelope_address(&m, 1), "b@y") { ok = false; }
  if !streq(mbox_envelope_date(&m, 1), "") { ok = false; }
  if mbox_body_offset(&m, 0) != 9 { ok = false; }
  if mbox_body_len(&m, 0) != 10 { ok = false; }
  if !streq(body_str(&m, 0), "A: 1\n\nm1\n\n") { ok = false; }
  if mbox_body_offset(&m, 1) != 28 { ok = false; }
  if mbox_body_len(&m, 1) != 9 { ok = false; }
  if !streq(body_str(&m, 1), "B: 2\n\nm2\n") { ok = false; }
  if mbox_body_offset(&m, 1) + mbox_body_len(&m, 1) != text.len() { ok = false; }
  return assert(ok, "two LF messages: aligned byte ranges into the shared pool");
}

fn t4() -> TestResult {
  let text = "From a\r\nH: v\r\n\r\nbody\r\n";
  let m = parse_ok(text);
  var ok = mbox_count(&m) == 1;
  if !streq(mbox_envelope_line(&m, 0), "From a") { ok = false; }
  if !streq(mbox_body_raw(&m, 0), "H: v\r\n\r\nbody\r\n") { ok = false; }
  if mbox_body_len(&m, 0) != 14 { ok = false; }
  if mbox_header_separator(&m, 0) != 14 { ok = false; }
  if mbox_header_body_start(&m, 0) != 16 { ok = false; }
  if !streq(mbox_emit(&m, "\r\n"), text) { ok = false; }
  return assert(ok, "CRLF message: terminators stripped from spans, byte-exact CRLF emit");
}

fn t5() -> TestResult {
  let text = "From a@x\nA: 1\n\n>From quoted\n\nFrom b@y\nB: 2\n\nm2\n";
  let m = parse_ok(text);
  var ok = mbox_count(&m) == 2;
  if !streq(mbox_emit(&m, "\n"), text) { ok = false; }
  if !streq(mbox_envelope_line(&m, 1), "From b@y") { ok = false; }
  return assert(ok, "canonical LF mailbox round-trips byte-for-byte through emit");
}

fn t6() -> TestResult {
  let crlf = "From a@x\r\nA: 1\r\n\r\nm1\r\n\r\nFrom b@y\r\nB: 2\r\n\r\nm2\r\n";
  let m = parse_ok(crlf);
  var ok = mbox_count(&m) == 2;
  if !streq(mbox_emit(&m, "\r\n"), crlf) { ok = false; }
  if !streq(mbox_emit(&m, "\n"), "From a@x\nA: 1\n\nm1\n\nFrom b@y\nB: 2\n\nm2\n") { ok = false; }
  return assert(ok, "CRLF mailbox round-trips with CRLF and normalizes to LF");
}

fn t7() -> TestResult {
  let text = "From a\nFrom b\nA: 1\n";
  let m = parse_ok(text);
  var ok = mbox_count(&m) == 1;
  if !streq(mbox_body_raw(&m, 0), "From b\nA: 1\n") { ok = false; }
  if !streq(body_str(&m, 0), "From b\nA: 1\n") { ok = false; }
  let quoted = mbox_emit(&m, "\n");
  if !streq(quoted, "From a\n>From b\nA: 1\n") { ok = false; }
  let m2 = parse_ok(quoted);
  if mbox_count(&m2) != 1 { ok = false; }
  if !streq(body_str(&m2, 0), "From b\nA: 1\n") { ok = false; }
  return assert(ok, "From line not after a blank line is content and is re-quoted on emit");
}

fn t8() -> TestResult {
  let text = "From a\nA: 1\n\n\nFrom b\nB: 2\n";
  let m = parse_ok(text);
  var ok = mbox_count(&m) == 2;
  if !streq(body_str(&m, 0), "A: 1\n\n\n") { ok = false; }
  let out = mbox_emit(&m, "\n");
  if !streq(out, text) { ok = false; }
  if !str_contains(out, "\n\nFrom b\n") { ok = false; }
  return assert(ok, "a From line after an empty line opens a message; blank lines are preserved");
}

fn t9() -> TestResult {
  let text = "From a\nA: 1\n\n>From x\n>>From y\n\nFrom b\nB: 2\n";
  let m = parse_ok(text);
  var ok = mbox_count(&m) == 2;
  if !streq(mbox_body_raw(&m, 0), "A: 1\n\n>From x\n>>From y\n\n") { ok = false; }
  if !streq(body_str(&m, 0), "A: 1\n\nFrom x\n>From y\n\n") { ok = false; }
  if !str_contains(mbox_body_raw(&m, 0), ">From x") { ok = false; }
  if !str_contains(mbox_body_raw(&m, 0), ">>From y") { ok = false; }
  if !streq(mbox_emit(&m, "\n"), text) { ok = false; }
  return assert(ok, "mboxrd stance: raw pool keeps quotes, body_into unquotes one >, emit re-quotes");
}

fn t10() -> TestResult {
  let text = "From a\nA: 1\n\nbody";
  let m = parse_ok(text);
  var ok = mbox_count(&m) == 1;
  if !streq(body_str(&m, 0), "A: 1\n\nbody") { ok = false; }
  if mbox_body_len(&m, 0) != 10 { ok = false; }
  if mbox_body_offset(&m, 0) + mbox_body_len(&m, 0) != text.len() { ok = false; }
  if !streq(mbox_emit(&m, "\n"), text) { ok = false; }
  return assert(ok, "unterminated final message is accepted and emitted as parsed");
}

fn t11() -> TestResult {
  let m0 = parse_ok("From \n\nFrom b\nx\n");
  var ok = mbox_count(&m0) == 2;
  if !streq(mbox_envelope_line(&m0, 0), "From ") { ok = false; }
  if !streq(mbox_envelope_address(&m0, 0), "") { ok = false; }
  if !streq(mbox_envelope_date(&m0, 0), "") { ok = false; }
  let m1 = parse_ok("From alice@example.com\n");
  if !streq(mbox_envelope_address(&m1, 0), "alice@example.com") { ok = false; }
  if !streq(mbox_envelope_date(&m1, 0), "") { ok = false; }
  let m2 = parse_ok("From a b c\n");
  if !streq(mbox_envelope_address(&m2, 0), "a") { ok = false; }
  if !streq(mbox_envelope_date(&m2, 0), "b c") { ok = false; }
  let m3 = parse_ok("From alice@example.com\t Mon Jan  1 00:00:00 2024  \n");
  if !streq(mbox_envelope_address(&m3, 0), "alice@example.com") { ok = false; }
  if !streq(mbox_envelope_date(&m3, 0), "Mon Jan  1 00:00:00 2024") { ok = false; }
  return assert(ok, "envelope text is raw: empty, address-only, space and tab separated parts");
}

fn t12() -> TestResult {
  let m = parse_ok("From a\nA: 1\nB: 2\n\nbody\n");
  var ok = mbox_header_separator(&m, 0) == 17;
  if mbox_header_body_start(&m, 0) != 18 { ok = false; }
  let m2 = parse_ok("From a\nA: 1\nno blank line\n");
  if mbox_header_separator(&m2, 0) != -1 { ok = false; }
  if mbox_header_body_start(&m2, 0) != -1 { ok = false; }
  let m3 = parse_ok("From a\n\nbody only\n");
  if mbox_header_separator(&m3, 0) != 7 { ok = false; }
  if mbox_header_body_start(&m3, 0) != 8 { ok = false; }
  let m4 = parse_ok("From a\nH: v\n\n");
  if mbox_header_separator(&m4, 0) != 12 { ok = false; }
  if mbox_header_body_start(&m4, 0) != 13 { ok = false; }
  return assert(ok, "header separator: first empty body line, -1 when absent, headers-only case");
}

fn t13() -> TestResult {
  let m = parse_ok("From a\nA: 1\n\nX\rY\n");
  var ok = mbox_count(&m) == 1;
  if !streq(mbox_body_raw(&m, 0), "A: 1\n\nX\rY\n") { ok = false; }
  if !streq(body_str(&m, 0), "A: 1\n\nX\rY\n") { ok = false; }
  if !streq(mbox_emit(&m, "\n"), "From a\nA: 1\n\nX\rY\n") { ok = false; }
  let m2 = parse_ok("From a\nX\rY\n");
  if mbox_count(&m2) != 1 { ok = false; }
  if !streq(body_str(&m2, 0), "X\rY\n") { ok = false; }
  return assert(ok, "a bare CR is an ordinary data byte, never a line terminator");
}

fn t14() -> TestResult {
  let m = parse_ok("From a\nxA\n\nFrom b\nB: 1\n\nm2\n");
  let out = mbox_emit(&m, "\n");
  var ok = str_contains(out, "xA\n\nFrom b\n");
  if str_contains(out, "xA\n\n\nFrom b\n") { ok = false; }
  let m2 = parse_ok("From a\n\nFrom b\n");
  let out2 = mbox_emit(&m2, "\n");
  if !streq(out2, "From a\n\nFrom b\n") { ok = false; }
  return assert(ok, "canonical emit writes exactly one blank line between messages");
}

fn t15() -> TestResult {
  let m = parse_ok("From a\nabc\n");
  var buf = Vec[UInt8].new();
  buf.push(88u8);
  buf.push(89u8);
  let n = mbox_body_into(&m, 0, &mut buf);
  var ok = n == 4;
  if buf.len() != 6 { ok = false; }
  if buf[0] != 88u8 { ok = false; }
  let n2 = mbox_body_into(&m, 7, &mut buf);
  if n2 != 0 { ok = false; }
  if buf.len() != 6 { ok = false; }
  if mbox_body_offset(&m, -1) != -1 { ok = false; }
  if mbox_body_len(&m, 7) != 0 { ok = false; }
  if !streq(mbox_envelope_line(&m, 1), "") { ok = false; }
  return assert(ok, "body_into appends into the caller's buffer; invalid indices are inert");
}

fn t16() -> TestResult {
  let m = parse_ok("From a\r\nA: 1\n\nbody\r\n");
  var ok = mbox_count(&m) == 1;
  if !streq(mbox_emit(&m, "\n"), "From a\nA: 1\n\nbody\n") { ok = false; }
  if !streq(mbox_emit(&m, "\r\n"), "From a\r\nA: 1\r\n\r\nbody\r\n") { ok = false; }
  return assert(ok, "mixed line endings parse and the emitter normalizes to the requested eol");
}

fn t17() -> TestResult {
  let x = "From a\nFrom x\n\nFrom y\nB: 2\n";
  let m = parse_ok(x);
  var ok = mbox_count(&m) == 2;
  let y = mbox_emit(&m, "\n");
  if !streq(y, "From a\n>From x\n\nFrom y\nB: 2\n") { ok = false; }
  let m2 = parse_ok(y);
  if mbox_count(&m2) != 2 { ok = false; }
  if !streq(body_str(&m2, 0), body_str(&m, 0)) { ok = false; }
  if !streq(body_str(&m2, 1), body_str(&m, 1)) { ok = false; }
  let y2 = mbox_emit(&m2, "\n");
  if !streq(y2, y) { ok = false; }
  let m3 = parse_ok(y2);
  if mbox_count(&m3) != 2 { ok = false; }
  if !streq(body_str(&m3, 0), body_str(&m, 0)) { ok = false; }
  return assert(ok, "decoded round-trip is stable: parse/emit/parse keeps bodies, emit is idempotent");
}

fn t18() -> TestResult {
  let text = "From a\nX\n\nFrom b\nY\n";
  let m = parse_ok(text);
  var ok = mbox_count(&m) == 2;
  let e0 = mbox_body_offset(&m, 0) + mbox_body_len(&m, 0);
  if e0 != 10 { ok = false; }
  if mbox_body_offset(&m, 1) != 17 { ok = false; }
  if mbox_body_offset(&m, 1) + mbox_body_len(&m, 1) != text.len() { ok = false; }
  if !streq(mbox_envelope_line(&m, 1), "From b") { ok = false; }
  return assert(ok, "each body span ends at the next delimiter; the final one ends at the pool end");
}

fn main() -> Int {
  io.println("=== xiom.mbox conformance tests ===");
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
  if failed == 0 {
    io.println("xiom.mbox: all tests passed");
  } else {
    io.println("xiom.mbox: tests failed");
  }
  return failed;
}
