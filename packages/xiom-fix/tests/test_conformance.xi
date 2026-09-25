// XIOM -- xiom.fix conformance tests (20 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Coverage: minimal, typical and FIXT.1.1 messages; tag count and accessors
// (first/last value, message type); duplicate tags; the empty-value policy;
// values containing '=' and punctuation; every parse error class (missing
// SOH, non-digit tag, missing '=', duplicate 8/9, field order, empty
// BeginString/MsgType, missing 35/10, trailing bytes, BodyLength format and
// value, CheckSum format and value, empty input); byte-exact round trips of
// six high-bit-free ASCII fixtures; canonical emit recomputing stale tags 9
// and 10; and the emit error catalog on hand-built messages.
//
// All Str equality goes through str_compare: BUG 17 lowers `==` on Str values
// read from Vec[Str] elements to a pointer comparison, so every comparison
// below routes through streq/opt_str_is/opt_str_none instead of `==`.

module fix_tests
use xiom.io; use xiom.test; use xiom.fix;
use xiom.string.compare;
use xiom.convert;

// Minimal single-field message: 8, 9, 35=D, 10.
const F1: Str = "8=FIX.4.2\x019=5\x0135=D\x0110=181\x01";

// NewOrderSingle with timestamps and a decimal price.
const F2: Str = "8=FIX.4.2\x019=137\x0135=D\x0149=CLIENT1\x0156=BROKER\x0134=2\x0152=20260925-21:00:00.000\x0111=ORD0001\x0121=1\x0155=AAPL\x0154=1\x0138=100\x0140=2\x0144=150.25\x0159=0\x0160=20260925-21:00:00.000\x0110=237\x01";

// Duplicate tags, an empty value and a value that contains '='.
const F3: Str = "8=FIX.4.2\x019=53\x0135=V\x0158=first\x0158=second\x0111=\x0144=a=b c\x0155=AAPL\x0155=MSFT\x0110=101\x01";

// Heartbeat with the FIXT.1.1 begin string.
const F4: Str = "8=FIXT.1.1\x019=65\x0135=0\x0149=CLIENT1\x0156=BROKER\x0134=1\x0152=20260925-21:00:00.000\x01112=TEST\x0110=217\x01";

// Execution report, MsgType 8.
const F5: Str = "8=FIX.4.2\x019=86\x0135=8\x0137=ORD0001\x01150=F\x0139=2\x0155=AAPL\x0154=1\x0138=100\x0140=2\x0144=150.25\x0132=100\x0131=150.25\x0114=100\x0110=216\x01";

// Punctuation-heavy values (pipes, carets, tildes, slash).
const F6: Str = "8=FIX.4.2\x019=53\x0135=D\x0158=ord|123^abc~def\x0155=EUR/USD\x0144=1.5\x0138=10\x0154=1\x0110=230\x01";

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn opt_str_is(o: Option[Str], want: Str) -> Bool {
  match o {
    Some(v) => { return streq(v, want); },
    None => { return false; },
  }
  return false;
}

fn opt_str_none(o: Option[Str]) -> Bool {
  match o {
    Some(_) => { return false; },
    None => { return true; },
  }
  return true;
}

// Parse text, or fall back to an empty message when it does not parse (the
// assertions fail loudly in that case).
fn parse_msg(text: Str) -> FixMessage {
  let r = fix_parse(text);
  match r {
    Ok(m) => { return m; },
    Err(_) => {},
  }
  return FixMessage{
    raw: "";
    tags: Vec[Int].new();
    starts: Vec[Int].new();
    ends: Vec[Int].new();
    body_length: 0;
    checksum: 0;
  };
}

// The parse error message, or "" when the text parsed.
fn parse_err(text: Str) -> Str {
  let r = fix_parse(text);
  match r {
    Ok(_) => { return ""; },
    Err(e) => { return e; },
  }
  return "";
}

// Canonical emit text, or "" when emit failed.
fn emit_ok(m: &FixMessage) -> Str {
  let r = fix_emit(m);
  if r.is_ok {
    let s: Str = r.value;
    return s;
  }
  return "";
}

// The emit error message, or "" when emit succeeded.
fn emit_err(m: &FixMessage) -> Str {
  let r = fix_emit(m);
  if r.is_ok {
    return "";
  }
  let e: Str = r.error;
  return e;
}

// True when parse -> emit reproduces `text` byte for byte.
fn roundtrip(text: Str) -> Bool {
  let m = parse_msg(text);
  let back = emit_ok(&m);
  return streq(back, text);
}

fn vec1(a: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  return v;
}

fn vec2(a: Int, b: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  v.push(b);
  return v;
}

fn vec4(a: Int, b: Int, c: Int, d: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  v.push(b);
  v.push(c);
  v.push(d);
  return v;
}

fn vec5(a: Int, b: Int, c: Int, d: Int, e: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  v.push(b);
  v.push(c);
  v.push(d);
  v.push(e);
  return v;
}

fn t1() -> TestResult {
  let m = parse_msg(F1);
  var ok = fix_tag_count(&m) == 4;
  if !streq(fix_msg_type(&m), "D") { ok = false; }
  if !opt_str_is(fix_value(&m, 8), "FIX.4.2") { ok = false; }
  if !opt_str_is(fix_value(&m, 9), "5") { ok = false; }
  if !opt_str_is(fix_value(&m, 35), "D") { ok = false; }
  if !opt_str_is(fix_value(&m, 10), "181") { ok = false; }
  if m.body_length != 5 { ok = false; }
  if m.checksum != 181 { ok = false; }
  return assert(ok, "minimal message parses with validated fields");
}

fn t2() -> TestResult {
  let m = parse_msg(F2);
  var ok = fix_tag_count(&m) == 17;
  if !streq(fix_msg_type(&m), "D") { ok = false; }
  if !opt_str_is(fix_value(&m, 49), "CLIENT1") { ok = false; }
  if !opt_str_is(fix_value(&m, 56), "BROKER") { ok = false; }
  if !opt_str_is(fix_value(&m, 34), "2") { ok = false; }
  if !opt_str_is(fix_value(&m, 52), "20260925-21:00:00.000") { ok = false; }
  if !opt_str_is(fix_value(&m, 11), "ORD0001") { ok = false; }
  if !opt_str_is(fix_value(&m, 55), "AAPL") { ok = false; }
  if !opt_str_is(fix_value(&m, 38), "100") { ok = false; }
  if !opt_str_is(fix_value(&m, 44), "150.25") { ok = false; }
  if !opt_str_is(fix_value(&m, 60), "20260925-21:00:00.000") { ok = false; }
  if m.body_length != 137 { ok = false; }
  if m.checksum != 237 { ok = false; }
  return assert(ok, "NewOrderSingle parses with every field addressable");
}

fn t3() -> TestResult {
  let m = parse_msg(F5);
  var ok = fix_tag_count(&m) == 15;
  if !streq(fix_msg_type(&m), "8") { ok = false; }
  if !opt_str_is(fix_value(&m, 37), "ORD0001") { ok = false; }
  if !opt_str_is(fix_value(&m, 150), "F") { ok = false; }
  if !opt_str_is(fix_value(&m, 39), "2") { ok = false; }
  if !opt_str_is(fix_value(&m, 32), "100") { ok = false; }
  if !opt_str_is(fix_value(&m, 31), "150.25") { ok = false; }
  if !opt_str_is(fix_value(&m, 14), "100") { ok = false; }
  if m.body_length != 86 { ok = false; }
  if m.checksum != 216 { ok = false; }
  return assert(ok, "execution report parses with three-digit tags");
}

fn t4() -> TestResult {
  let m = parse_msg(F4);
  var ok = fix_tag_count(&m) == 9;
  if !streq(fix_msg_type(&m), "0") { ok = false; }
  if !opt_str_is(fix_value(&m, 8), "FIXT.1.1") { ok = false; }
  if !opt_str_is(fix_value(&m, 112), "TEST") { ok = false; }
  if m.body_length != 65 { ok = false; }
  if m.checksum != 217 { ok = false; }
  return assert(ok, "FIXT.1.1 begin string and custom tag parse");
}

fn t5() -> TestResult {
  let m = parse_msg(F3);
  var ok = fix_tag_count(&m) == 10;
  if !opt_str_is(fix_value(&m, 58), "first") { ok = false; }
  if !opt_str_is(fix_value_last(&m, 58), "second") { ok = false; }
  if !opt_str_is(fix_value(&m, 55), "AAPL") { ok = false; }
  if !opt_str_is(fix_value_last(&m, 55), "MSFT") { ok = false; }
  if !opt_str_is(fix_value(&m, 44), "a=b c") { ok = false; }
  return assert(ok, "duplicate tags keep wire order; first/last differ");
}

fn t6() -> TestResult {
  let m = parse_msg(F3);
  var ok = opt_str_is(fix_value(&m, 11), "");
  if !opt_str_is(fix_value_last(&m, 11), "") { ok = false; }
  if !opt_str_none(fix_value(&m, 999)) { ok = false; }
  if !opt_str_none(fix_value_last(&m, 999)) { ok = false; }
  let p = parse_msg(F6);
  if !streq(fix_msg_type(&p), "D") { ok = false; }
  if !opt_str_is(fix_value(&p, 58), "ord|123^abc~def") { ok = false; }
  if !opt_str_is(fix_value(&p, 55), "EUR/USD") { ok = false; }
  if !opt_str_is(fix_value(&p, 44), "1.5") { ok = false; }
  if fix_tag_count(&p) != 9 { ok = false; }
  return assert(ok, "empty values and punctuation-heavy values are preserved");
}

fn t7() -> TestResult {
  let empty = FixMessage{
    raw: "";
    tags: Vec[Int].new();
    starts: Vec[Int].new();
    ends: Vec[Int].new();
    body_length: 0;
    checksum: 0;
  };
  var ok = fix_tag_count(&empty) == 0;
  if !streq(fix_msg_type(&empty), "") { ok = false; }
  if !opt_str_none(fix_value(&empty, 35)) { ok = false; }
  if !opt_str_none(fix_value_last(&empty, 35)) { ok = false; }
  return assert(ok, "accessors are inert on an empty message");
}

fn t8() -> TestResult {
  var ok = streq(parse_err("8=FIX.4.2\x019=5"), "fix: missing SOH terminator at offset " + convert.int_to_string(10));
  if !streq(parse_err("8=FIX.4.2"), "fix: missing SOH terminator at offset " + convert.int_to_string(0)) { ok = false; }
  return assert(ok, "a field without a SOH terminator is rejected with its offset");
}

fn t9() -> TestResult {
  var ok = streq(parse_err("8=FIX.4.2\x019=5\x013x=D\x0110=000\x01"), "fix: non-digit tag at offset " + convert.int_to_string(14));
  if !streq(parse_err("8=FIX.4.2\x019=5\x01=D\x0110=000\x01"), "fix: non-digit tag at offset " + convert.int_to_string(14)) { ok = false; }
  return assert(ok, "tags must be a non-empty run of digits");
}

fn t10() -> TestResult {
  var ok = streq(parse_err("8=FIX.4.2\x019=5\x0135D\x0110=000\x01"), "fix: missing '=' in field at offset " + convert.int_to_string(14));
  return assert(ok, "a field without '=' is rejected with its offset");
}

fn t11() -> TestResult {
  var ok = streq(parse_err("8=FIX.4.2\x019=5\x0135=D\x018=X\x0110=000\x01"), "fix: duplicate tag 8");
  if !streq(parse_err("8=FIX.4.2\x019=5\x0135=D\x019=6\x0110=000\x01"), "fix: duplicate tag 9") { ok = false; }
  return assert(ok, "duplicate tags 8 and 9 are rejected");
}

fn t12() -> TestResult {
  var ok = streq(parse_err("35=D\x0110=000\x01"), "fix: first field must be tag 8 (BeginString)");
  if !streq(parse_err("8=FIX.4.2\x0135=D\x0110=000\x01"), "fix: second field must be tag 9 (BodyLength)") { ok = false; }
  if !streq(parse_err("8=\x019=5\x0135=D\x0110=000\x01"), "fix: empty BeginString") { ok = false; }
  return assert(ok, "8 must be first, 9 second, and BeginString non-empty");
}

fn t13() -> TestResult {
  var ok = streq(parse_err("8=FIX.4.2\x019=6\x0135=D\x0110=181\x01"), "fix: BodyLength mismatch: declared 6 actual 5");
  if !streq(parse_err("8=FIX.4.2\x019=4\x0135=D\x0110=181\x01"), "fix: BodyLength mismatch: declared 4 actual 5") { ok = false; }
  if !streq(parse_err("8=FIX.4.2\x019=x5\x0135=D\x0110=181\x01"), "fix: BodyLength is not a non-negative integer") { ok = false; }
  if !streq(parse_err("8=FIX.4.2\x019=\x0135=D\x0110=181\x01"), "fix: BodyLength is not a non-negative integer") { ok = false; }
  if !streq(parse_err("8=FIX.4.2\x019=0000000000\x0135=D\x0110=181\x01"), "fix: BodyLength is not a non-negative integer") { ok = false; }
  return assert(ok, "BodyLength must be a decimal integer equal to the body bytes");
}

fn t14() -> TestResult {
  var ok = streq(parse_err("8=FIX.4.2\x019=5\x0135=D\x0110=18\x01"), "fix: invalid CheckSum at offset " + convert.int_to_string(22));
  if !streq(parse_err("8=FIX.4.2\x019=5\x0135=D\x0110=999\x01"), "fix: invalid CheckSum at offset " + convert.int_to_string(22)) { ok = false; }
  if !streq(parse_err("8=FIX.4.2\x019=5\x0135=D\x0110=abc\x01"), "fix: invalid CheckSum at offset " + convert.int_to_string(22)) { ok = false; }
  if !streq(parse_err("8=FIX.4.2\x019=5\x0135=D\x0110=0181\x01"), "fix: invalid CheckSum at offset " + convert.int_to_string(22)) { ok = false; }
  return assert(ok, "CheckSum must be exactly three digits in 000-255");
}

fn t15() -> TestResult {
  var ok = streq(parse_err("8=FIX.4.2\x019=5\x0135=D\x0110=182\x01"), "fix: CheckSum mismatch: declared 182 computed 181");
  if !streq(parse_err("8=FIX.4.2\x019=5\x0135=D\x0110=000\x01"), "fix: CheckSum mismatch: declared 0 computed 181") { ok = false; }
  return assert(ok, "a well-formed but wrong CheckSum is a mismatch error");
}

fn t16() -> TestResult {
  var ok = streq(parse_err(F1 + "X"), "fix: trailing bytes after checksum at offset " + convert.int_to_string(26));
  if !streq(parse_err(F1 + "10=181\x01"), "fix: trailing bytes after checksum at offset " + convert.int_to_string(26)) { ok = false; }
  return assert(ok, "the checksum field must be the last field");
}

fn t17() -> TestResult {
  var ok = streq(parse_err("8=FIX.4.2\x019=0\x0110=198\x01"), "fix: missing tag 35 (MsgType)");
  if !streq(parse_err("8=FIX.4.2\x019=999\x0135=\x0110=000\x01"), "fix: empty MsgType") { ok = false; }
  if !streq(parse_err("8=FIX.4.2\x019=5\x0135=D\x01"), "fix: missing tag 10 (CheckSum)") { ok = false; }
  if !streq(parse_err(""), "fix: empty message") { ok = false; }
  return assert(ok, "MsgType is mandatory and empty input is rejected");
}

fn t18() -> TestResult {
  var ok = roundtrip(F1);
  if !roundtrip(F2) { ok = false; }
  if !roundtrip(F3) { ok = false; }
  if !roundtrip(F4) { ok = false; }
  if !roundtrip(F5) { ok = false; }
  if !roundtrip(F6) { ok = false; }
  // A missing final SOH after tag 10 parses and emit adds the canonical SOH.
  let no_tail = "8=FIX.4.2\x019=5\x0135=D\x0110=181";
  let m = parse_msg(no_tail);
  if !streq(emit_ok(&m), F1) { ok = false; }
  return assert(ok, "six fixtures round-trip byte-exact; canonical emit restores the SOH");
}

fn t19() -> TestResult {
  let raw1 = "8=FIX.4.2\x019=999\x0135=D\x0110=999\x01";
  let m1 = FixMessage{
    raw: raw1;
    tags: vec4(8, 9, 35, 10);
    starts: vec4(2, 12, 19, 24);
    ends: vec4(9, 15, 20, 27);
    body_length: 999;
    checksum: 999;
  };
  var ok = streq(emit_ok(&m1), F1);
  let raw2 = "8=FIX.4.2\x019=1\x0135=D\x0158=x\x0110=999\x01";
  let m2 = FixMessage{
    raw: raw2;
    tags: vec5(8, 9, 35, 58, 10);
    starts: vec5(2, 12, 17, 22, 27);
    ends: vec5(9, 13, 18, 23, 30);
    body_length: 1;
    checksum: 999;
  };
  if !streq(emit_ok(&m2), "8=FIX.4.2\x019=10\x0135=D\x0158=x\x0110=004\x01") { ok = false; }
  return assert(ok, "emit recomputes BodyLength and CheckSum from tags and spans");
}

fn t20() -> TestResult {
  let bad_align = FixMessage{
    raw: "";
    tags: Vec[Int].new();
    starts: vec1(0);
    ends: Vec[Int].new();
    body_length: 0;
    checksum: 0;
  };
  var ok = streq(emit_err(&bad_align), "fix: cannot emit: field vectors are not aligned");
  let bad_no8 = FixMessage{
    raw: "35=D\x01";
    tags: vec2(35, 10);
    starts: vec2(3, 0);
    ends: vec2(4, 0);
    body_length: 0;
    checksum: 0;
  };
  if !streq(emit_err(&bad_no8), "fix: cannot emit without tag 8 (BeginString)") { ok = false; }
  let bad_reserved = FixMessage{
    raw: "8=FIX.4.2\x01D\x01";
    tags: vec2(8, 35);
    starts: vec2(2, 9);
    ends: vec2(9, 11);
    body_length: 0;
    checksum: 0;
  };
  if !streq(emit_err(&bad_reserved), "fix: cannot emit: value contains a reserved byte") { ok = false; }
  let bad_span = FixMessage{
    raw: "8=FIX.4.2\x01";
    tags: vec2(8, 35);
    starts: vec2(2, 100);
    ends: vec2(9, 120);
    body_length: 0;
    checksum: 0;
  };
  if !streq(emit_err(&bad_span), "fix: cannot emit: field span out of range") { ok = false; }
  let bad_dup = FixMessage{
    raw: "8=FIX.4.2\x018=X\x01";
    tags: vec2(8, 8);
    starts: vec2(2, 12);
    ends: vec2(9, 13);
    body_length: 0;
    checksum: 0;
  };
  if !streq(emit_err(&bad_dup), "fix: cannot emit: duplicate tag 8") { ok = false; }
  let bad_tag = FixMessage{
    raw: "8=FIX.4.2\x01";
    tags: vec2(8, 0);
    starts: vec2(2, 0);
    ends: vec2(9, 0);
    body_length: 0;
    checksum: 0;
  };
  if !streq(emit_err(&bad_tag), "fix: cannot emit: invalid tag") { ok = false; }
  return assert(ok, "emit rejects misaligned and malformed hand-built messages");
}

fn main() -> Int {
  io.println("=== xiom.fix conformance tests ===");
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
    io.println("xiom.fix: all tests passed");
  } else {
    io.println("xiom.fix: tests failed");
  }
  return failed;
}
