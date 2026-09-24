// XIOM -- xiom.telnet conformance tests (18 checks)
// Port task: prove the pure-XIOM xiom.telnet negotiation codec.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Coverage map (see SPEC.md section 6): exact negotiation bytes and the
// verb/option error catalog, parsing all four verbs, event order, SB
// payload offsets/lengths (plain, doubled IAC, empty, option 255), the
// truncation catalog, IAC inside SB, unknown IAC commands, data skipping,
// 0xFF escaping/unescaping with round-trips, empty input and the
// bounds-safe event accessors.
//
// v0.61.3 discipline: Result payloads are read through `is_ok` / `value` /
// `error` (tftp/midi precedent), Str comparison goes through
// xiom.string.compare.str_compare (BUG 17), and raw bytes widen through
// `as Int` before any comparison.

module telnet_tests
use xiom.io; use xiom.test;
use xiom.telnet;
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

fn str_eq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// Copy data[off, off+len) -- used to read an SB payload out of the input
// using the offset/length the parser reported.
fn slice_of(data: &Vec[UInt8], off: Int, len: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = off;
  while i < off + len {
    out.push(data[i]);
    i = i + 1;
  }
  return out;
}

// --------------------------------------------------
//  Result assertions and accessor shortcuts
// --------------------------------------------------

fn err_bytes_is(r: Result[Vec[UInt8], Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_events_is(r: Result[TelnetEvents, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn kind_is(e: &TelnetEvents, i: Int, want: Int) -> Bool {
  return telnet_kind(e, i) == want;
}

fn option_is(e: &TelnetEvents, i: Int, want: Int) -> Bool {
  return telnet_option(e, i) == want;
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  let will = telnet_build_negotiation(TELNET_WILL, 1);
  let wont = telnet_build_negotiation(TELNET_WONT, 3);
  let do_cmd = telnet_build_negotiation(TELNET_DO, 24);
  let dont_cmd = telnet_build_negotiation(TELNET_DONT, 255);
  var ok = will.is_ok && wont.is_ok && do_cmd.is_ok && dont_cmd.is_ok;
  if ok {
    if !bytes_equal(will.value, hb("fffb01")) { ok = false; }
    if !bytes_equal(wont.value, hb("fffc03")) { ok = false; }
    if !bytes_equal(do_cmd.value, hb("fffd18")) { ok = false; }
    if !bytes_equal(dont_cmd.value, hb("fffeff")) { ok = false; }
    if will.value.len() != 3 { ok = false; }
  }
  return assert(ok, "build: WILL/WONT/DO/DONT render exact IAC verb option bytes");
}

fn t2() -> TestResult {
  var ok = err_bytes_is(telnet_build_negotiation(TELNET_SB, 1), "telnet: verb out of range");
  if !err_bytes_is(telnet_build_negotiation(TELNET_IAC, 1), "telnet: verb out of range") { ok = false; }
  if !err_bytes_is(telnet_build_negotiation(TELNET_SE, 1), "telnet: verb out of range") { ok = false; }
  if !err_bytes_is(telnet_build_negotiation(0, 1), "telnet: verb out of range") { ok = false; }
  if !err_bytes_is(telnet_build_negotiation(-1, 1), "telnet: verb out of range") { ok = false; }
  if !err_bytes_is(telnet_build_negotiation(TELNET_WILL, -1), "telnet: option out of range") { ok = false; }
  if !err_bytes_is(telnet_build_negotiation(TELNET_DONT, 256), "telnet: option out of range") { ok = false; }
  if !err_bytes_is(telnet_build_negotiation(250, 999), "telnet: verb out of range") { ok = false; }
  let lo = telnet_build_negotiation(TELNET_WILL, 0);
  let hi = telnet_build_negotiation(TELNET_DONT, 255);
  if lo.is_ok {
    if !bytes_equal(lo.value, hb("fffb00")) { ok = false; }
  } else {
    ok = false;
  }
  if hi.is_ok {
    if !bytes_equal(hi.value, hb("fffeff")) { ok = false; }
  } else {
    ok = false;
  }
  return assert(ok, "build: invalid verb/option Err; option 0 and 255 are valid");
}

fn t3() -> TestResult {
  let r = telnet_parse(&hb("fffb01fffc02"));
  var ok = r.is_ok;
  if r.is_ok {
    let e = r.value;
    ok = telnet_event_count(&e) == 2;
    if !kind_is(&e, 0, 1) { ok = false; }
    if !kind_is(&e, 1, 2) { ok = false; }
    if !option_is(&e, 0, 1) { ok = false; }
    if !option_is(&e, 1, 2) { ok = false; }
  }
  return assert(ok, "parse: WILL 1 and WONT 2 are events in stream order");
}

fn t4() -> TestResult {
  let r = telnet_parse(&hb("fffd18fffeff"));
  var ok = r.is_ok;
  if r.is_ok {
    let e = r.value;
    ok = telnet_event_count(&e) == 2;
    if !kind_is(&e, 0, 3) { ok = false; }
    if !kind_is(&e, 1, 4) { ok = false; }
    if !option_is(&e, 0, 24) { ok = false; }
    if !option_is(&e, 1, 255) { ok = false; }
  }
  return assert(ok, "parse: DO 24 and DONT 255 are events in stream order");
}

fn t5() -> TestResult {
  let r = telnet_parse(&hb("fffb01fffd03fffc02fffe04fffa0541fff0"));
  var ok = r.is_ok;
  if r.is_ok {
    let e = r.value;
    ok = telnet_event_count(&e) == 5;
    if !kind_is(&e, 0, 1) { ok = false; }
    if !kind_is(&e, 1, 3) { ok = false; }
    if !kind_is(&e, 2, 2) { ok = false; }
    if !kind_is(&e, 3, 4) { ok = false; }
    if !kind_is(&e, 4, 5) { ok = false; }
    if !option_is(&e, 0, 1) { ok = false; }
    if !option_is(&e, 1, 3) { ok = false; }
    if !option_is(&e, 2, 2) { ok = false; }
    if !option_is(&e, 3, 4) { ok = false; }
    if !option_is(&e, 4, 5) { ok = false; }
    if telnet_payload_offset(&e, 0) != -1 { ok = false; }
    if telnet_payload_length(&e, 0) != 0 { ok = false; }
    if telnet_payload_offset(&e, 1) != -1 { ok = false; }
    if telnet_payload_length(&e, 1) != 0 { ok = false; }
    if telnet_payload_offset(&e, 2) != -1 { ok = false; }
    if telnet_payload_length(&e, 2) != 0 { ok = false; }
    if telnet_payload_offset(&e, 3) != -1 { ok = false; }
    if telnet_payload_length(&e, 3) != 0 { ok = false; }
    if telnet_payload_offset(&e, 4) != 15 { ok = false; }
    if telnet_payload_length(&e, 4) != 1 { ok = false; }
  }
  return assert(ok, "parse: five mixed events keep stream order and payload slots");
}

fn t6() -> TestResult {
  let data = hb("fffa18010203fff0");
  let r = telnet_parse(&data);
  var ok = r.is_ok;
  if r.is_ok {
    let e = r.value;
    ok = telnet_event_count(&e) == 1;
    if !kind_is(&e, 0, 5) { ok = false; }
    if !option_is(&e, 0, 24) { ok = false; }
    if telnet_payload_offset(&e, 0) != 3 { ok = false; }
    if telnet_payload_length(&e, 0) != 3 { ok = false; }
    if !bytes_equal(slice_of(&data, 3, 3), hb("010203")) { ok = false; }
  }
  return assert(ok, "SB: payload offset 3 and length 3 pin the raw bytes 01 02 03");
}

fn t7() -> TestResult {
  let data = hb("fffa01ffff41fff0");
  let r = telnet_parse(&data);
  var ok = r.is_ok;
  if r.is_ok {
    let e = r.value;
    ok = telnet_event_count(&e) == 1;
    if !kind_is(&e, 0, 5) { ok = false; }
    if !option_is(&e, 0, 1) { ok = false; }
    if telnet_payload_offset(&e, 0) != 3 { ok = false; }
    if telnet_payload_length(&e, 0) != 3 { ok = false; }
    if !bytes_equal(slice_of(&data, 3, 3), hb("ffff41")) { ok = false; }
  }
  return assert(ok, "SB: doubled IAC stays raw (counts two bytes) in the payload");
}

fn t8() -> TestResult {
  let data = hb("fffa01fff0");
  let r = telnet_parse(&data);
  var ok = r.is_ok;
  if r.is_ok {
    let e = r.value;
    ok = telnet_event_count(&e) == 1;
    if !kind_is(&e, 0, 5) { ok = false; }
    if !option_is(&e, 0, 1) { ok = false; }
    if telnet_payload_offset(&e, 0) != 3 { ok = false; }
    if telnet_payload_length(&e, 0) != 0 { ok = false; }
    if slice_of(&data, 3, 0).len() != 0 { ok = false; }
  }
  return assert(ok, "SB: empty payload is a valid event with length 0");
}

fn t9() -> TestResult {
  let data = hb("fffaff0042fff0");
  let r = telnet_parse(&data);
  var ok = r.is_ok;
  if r.is_ok {
    let e = r.value;
    ok = telnet_event_count(&e) == 1;
    if !kind_is(&e, 0, 5) { ok = false; }
    if !option_is(&e, 0, 255) { ok = false; }
    if telnet_payload_offset(&e, 0) != 3 { ok = false; }
    if telnet_payload_length(&e, 0) != 2 { ok = false; }
    if !bytes_equal(slice_of(&data, 3, 2), hb("0042")) { ok = false; }
  }
  return assert(ok, "SB: option 255 and a NUL payload byte are preserved");
}

fn t10() -> TestResult {
  var ok = err_events_is(telnet_parse(&hb("ff")), "telnet: truncated IAC");
  if !err_events_is(telnet_parse(&hb("fffb")), "telnet: truncated negotiation") { ok = false; }
  if !err_events_is(telnet_parse(&hb("fffd")), "telnet: truncated negotiation") { ok = false; }
  if !err_events_is(telnet_parse(&hb("fffa")), "telnet: truncated subnegotiation") { ok = false; }
  if !err_events_is(telnet_parse(&hb("fffa01")), "telnet: unterminated subnegotiation") { ok = false; }
  if !err_events_is(telnet_parse(&hb("fffa0141")), "telnet: unterminated subnegotiation") { ok = false; }
  if !err_events_is(telnet_parse(&hb("fffa01ff")), "telnet: unterminated subnegotiation") { ok = false; }
  return assert(ok, "truncation catalog: bare IAC, verb without option, unterminated SB");
}

fn t11() -> TestResult {
  var ok = err_events_is(telnet_parse(&hb("fffa01ff41fff0")), "telnet: IAC in subnegotiation must be followed by IAC or SE");
  if !err_events_is(telnet_parse(&hb("fffa01ff01")), "telnet: IAC in subnegotiation must be followed by IAC or SE") { ok = false; }
  if !err_events_is(telnet_parse(&hb("fffa01fffb01fff0")), "telnet: IAC in subnegotiation must be followed by IAC or SE") { ok = false; }
  return assert(ok, "SB: IAC followed by anything but IAC or SE is an Err");
}

fn t12() -> TestResult {
  var ok = err_events_is(telnet_parse(&hb("fff1")), "telnet: unknown IAC command");
  if !err_events_is(telnet_parse(&hb("ff00")), "telnet: unknown IAC command") { ok = false; }
  if !err_events_is(telnet_parse(&hb("ffef")), "telnet: unknown IAC command") { ok = false; }
  if !err_events_is(telnet_parse(&hb("fff0")), "telnet: unknown IAC command") { ok = false; }
  if !err_events_is(telnet_parse(&hb("4142fff1")), "telnet: unknown IAC command") { ok = false; }
  return assert(ok, "unknown IAC commands (NOP, NUL, 239, stray SE) are Err");
}

fn t13() -> TestResult {
  let plain = telnet_parse(&hb("48656c6c6f"));
  var ok = plain.is_ok;
  if plain.is_ok {
    if telnet_event_count(&plain.value) != 0 { ok = false; }
  }
  let escaped = telnet_parse(&hb("41ffff42"));
  if escaped.is_ok {
    if telnet_event_count(&escaped.value) != 0 { ok = false; }
  } else {
    ok = false;
  }
  let mixed = telnet_parse(&hb("41fffb0142"));
  if mixed.is_ok {
    let em = mixed.value;
    if telnet_event_count(&em) != 1 { ok = false; }
    if !kind_is(&em, 0, 1) { ok = false; }
    if !option_is(&em, 0, 1) { ok = false; }
  } else {
    ok = false;
  }
  return assert(ok, "data bytes (plain and escaped IAC) are skipped, not events");
}

fn t14() -> TestResult {
  var ok = telnet_escape_data(&hb("")).len() == 0;
  if !bytes_equal(telnet_escape_data(&hb("41ff42")), hb("41ffff42")) { ok = false; }
  if !bytes_equal(telnet_escape_data(&hb("ff")), hb("ffff")) { ok = false; }
  if !bytes_equal(telnet_escape_data(&hb("ffff")), hb("ffffffff")) { ok = false; }
  if !bytes_equal(telnet_escape_data(&hb("00ff01")), hb("00ffff01")) { ok = false; }
  return assert(ok, "escape: every 0xFF is doubled, other bytes pass through");
}

fn t15() -> TestResult {
  let one = telnet_unescape_data(&hb("ffff"));
  var ok = one.len() == 1;
  if one.len() == 1 {
    if ((one[0] as Int) & 0xFF) != 255 { ok = false; }
  }
  if !bytes_equal(telnet_unescape_data(&hb("41ffff42")), hb("41ff42")) { ok = false; }
  if !bytes_equal(telnet_unescape_data(&hb("ff")), hb("ff")) { ok = false; }
  if !bytes_equal(telnet_unescape_data(&hb("fffb01")), hb("fffb01")) { ok = false; }
  if !bytes_equal(telnet_unescape_data(&hb("")), hb("")) { ok = false; }
  return assert(ok, "unescape: IAC IAC collapses; lone IAC and other IAC bytes pass through");
}

fn t16() -> TestResult {
  let a = hb("");
  let b = hb("00");
  let c = hb("ff");
  let d = hb("00ffff01");
  let e = hb("ffffffffff");
  let ea = telnet_escape_data(&a);
  var ok = bytes_equal(telnet_unescape_data(&ea), a);
  let eb = telnet_escape_data(&b);
  if !bytes_equal(telnet_unescape_data(&eb), b) { ok = false; }
  let ec = telnet_escape_data(&c);
  if !bytes_equal(telnet_unescape_data(&ec), c) { ok = false; }
  let ed = telnet_escape_data(&d);
  if !bytes_equal(telnet_unescape_data(&ed), d) { ok = false; }
  let ee = telnet_escape_data(&e);
  if !bytes_equal(telnet_unescape_data(&ee), e) { ok = false; }
  let uc = telnet_unescape_data(&ec);
  let ec2 = telnet_escape_data(&uc);
  if !bytes_equal(ec2, ec) { ok = false; }
  if ec.len() != 2 { ok = false; }
  if ee.len() != 10 { ok = false; }
  return assert(ok, "round-trip: unescape(escape(x)) == x and escape of a wire buffer is stable");
}

fn t17() -> TestResult {
  let r = telnet_parse(&hb(""));
  var ok = r.is_ok;
  if r.is_ok {
    let e = r.value;
    if telnet_event_count(&e) != 0 { ok = false; }
    if telnet_kind(&e, 0) != -1 { ok = false; }
    if telnet_kind(&e, -1) != -1 { ok = false; }
    if telnet_option(&e, 0) != -1 { ok = false; }
    if telnet_payload_offset(&e, 0) != -1 { ok = false; }
    if telnet_payload_length(&e, 0) != -1 { ok = false; }
  }
  var raw = Vec[UInt8].new();
  let r2 = telnet_parse(&raw);
  if !r2.is_ok {
    ok = false;
  } else {
    let e2 = r2.value;
    if telnet_event_count(&e2) != 0 { ok = false; }
  }
  return assert(ok, "empty input: Ok with zero events; accessors on empty are bounds-safe");
}

fn t18() -> TestResult {
  let r = telnet_parse(&hb("fffb01fffa18010203fff0"));
  var ok = r.is_ok;
  if r.is_ok {
    let e = r.value;
    ok = telnet_event_count(&e) == 2;
    if !kind_is(&e, 0, 1) { ok = false; }
    if !option_is(&e, 0, 1) { ok = false; }
    if telnet_payload_offset(&e, 0) != -1 { ok = false; }
    if telnet_payload_length(&e, 0) != 0 { ok = false; }
    if !kind_is(&e, 1, 5) { ok = false; }
    if !option_is(&e, 1, 24) { ok = false; }
    if telnet_payload_offset(&e, 1) != 6 { ok = false; }
    if telnet_payload_length(&e, 1) != 3 { ok = false; }
    if telnet_kind(&e, 2) != -1 { ok = false; }
    if telnet_option(&e, 2) != -1 { ok = false; }
    if telnet_payload_offset(&e, 2) != -1 { ok = false; }
    if telnet_payload_length(&e, 2) != -1 { ok = false; }
    if telnet_kind(&e, -7) != -1 { ok = false; }
    if telnet_option(&e, -7) != -1 { ok = false; }
    if telnet_payload_offset(&e, -7) != -1 { ok = false; }
    if telnet_payload_length(&e, -7) != -1 { ok = false; }
  }
  return assert(ok, "accessors: valid values pinned, out-of-range indices return -1");
}

fn main() -> Int {
  io.println("=== xiom.telnet conformance tests ===");
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
    io.println("xiom.telnet: all tests passed");
  } else {
    io.println("xiom.telnet: tests failed");
  }
  return failed;
}
