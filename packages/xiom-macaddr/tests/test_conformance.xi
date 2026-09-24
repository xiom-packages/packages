// XIOM -- xiom.macaddr conformance tests (20 checks)
// Port task: prove the pure-XIOM xiom.macaddr module against its SPEC.md.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Covers the documented API: parsing in all four notations (colon pairs,
// dash pairs, Cisco dotted triplets, bare 12 hex digits), case-insensitivity,
// cross-notation equality, format/format_upper (including masking of bits
// above 48), the pinned OUI/NIC split, the multicast/local/unicast flag
// bits, the broadcast constant and predicate, the zero address and the
// 48-bit maximum.
//
// All Str equality goes through str_compare: BUG 17 lowers `==` on Str
// values read from Vec[Str] elements to a pointer comparison, so every
// comparison below is routed through streq. The module under test never
// compares Str values at all.

module macaddr_tests
use xiom.io; use xiom.test; use xiom.macaddr;
use xiom.string.compare;

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// True when r is Ok and its value equals `want`.
fn parsed_is(r: Result[Int, Str], want: Int) -> Bool {
  if !r.is_ok {
    return false;
  }
  return r.value == want;
}

// True when r is Err with exactly the message `want`.
fn parsed_err(r: Result[Int, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return streq(r.error, want);
}

// True when s parses and formats back to exactly `canonical`.
fn roundtrip_canonical(s: Str, canonical: Str) -> Bool {
  let r = mac_parse(s);
  if !r.is_ok {
    return false;
  }
  return streq(mac_format(r.value), canonical);
}

fn t1() -> TestResult {
  var ok = parsed_is(mac_parse("aa:bb:cc:dd:ee:ff"), 0xAABBCCDDEEFF);
  if !parsed_is(mac_parse("00:11:22:33:44:55"), 0x001122334455) { ok = false; }
  if !parsed_is(mac_parse("01:00:5e:00:00:01"), 0x01005E000001) { ok = false; }
  return assert(ok, "parse colon-separated lowercase pairs");
}

fn t2() -> TestResult {
  var ok = parsed_is(mac_parse("AA:BB:CC:DD:EE:FF"), 0xAABBCCDDEEFF);
  if !parsed_is(mac_parse("aA:bB:cC:dD:eE:fF"), 0xAABBCCDDEEFF) { ok = false; }
  if !parsed_is(mac_parse("00:11:22:33:44:55"), 0x001122334455) { ok = false; }
  return assert(ok, "parse is case-insensitive");
}

fn t3() -> TestResult {
  var ok = parsed_is(mac_parse("aa-bb-cc-dd-ee-ff"), 0xAABBCCDDEEFF);
  if !parsed_is(mac_parse("AA-BB-CC-DD-EE-FF"), 0xAABBCCDDEEFF) { ok = false; }
  if !parsed_is(mac_parse("00-11-22-33-44-55"), 0x001122334455) { ok = false; }
  return assert(ok, "parse dash-separated pairs");
}

fn t4() -> TestResult {
  var ok = parsed_is(mac_parse("aabb.ccdd.eeff"), 0xAABBCCDDEEFF);
  if !parsed_is(mac_parse("AABB.CCDD.EEFF"), 0xAABBCCDDEEFF) { ok = false; }
  if !parsed_is(mac_parse("0011.2233.4455"), 0x001122334455) { ok = false; }
  return assert(ok, "parse Cisco dotted triplets");
}

fn t5() -> TestResult {
  var ok = parsed_is(mac_parse("aabbccddeeff"), 0xAABBCCDDEEFF);
  if !parsed_is(mac_parse("AABBCCDDEEFF"), 0xAABBCCDDEEFF) { ok = false; }
  if !parsed_is(mac_parse("001122334455"), 0x001122334455) { ok = false; }
  return assert(ok, "parse 12 bare hex digits");
}

fn t6() -> TestResult {
  let a = mac_parse("aa:bb:cc:dd:ee:ff");
  let b = mac_parse("aa-bb-cc-dd-ee-ff");
  let c = mac_parse("aabb.ccdd.eeff");
  let d = mac_parse("aabbccddeeff");
  var ok = a.is_ok && b.is_ok && c.is_ok && d.is_ok;
  if ok {
    if a.value != b.value { ok = false; }
    if b.value != c.value { ok = false; }
    if c.value != d.value { ok = false; }
    if a.value != 0xAABBCCDDEEFF { ok = false; }
  }
  return assert(ok, "all four notations parse to the same value");
}

fn t7() -> TestResult {
  var ok = roundtrip_canonical("aa:bb:cc:dd:ee:ff", "aa:bb:cc:dd:ee:ff");
  if !roundtrip_canonical("AA-BB-CC-DD-EE-FF", "aa:bb:cc:dd:ee:ff") { ok = false; }
  if !roundtrip_canonical("aabb.ccdd.eeff", "aa:bb:cc:dd:ee:ff") { ok = false; }
  if !roundtrip_canonical("AABBCCDDEEFF", "aa:bb:cc:dd:ee:ff") { ok = false; }
  if !roundtrip_canonical("00:11:22:33:44:55", "00:11:22:33:44:55") { ok = false; }
  return assert(ok, "parse then format produces canonical lowercase text");
}

fn t8() -> TestResult {
  var ok = parsed_err(mac_parse(""), "mac: invalid length");
  if !parsed_err(mac_parse("aa:bb"), "mac: invalid length") { ok = false; }
  if !parsed_err(mac_parse("aa:bb:cc:dd:e"), "mac: invalid length") { ok = false; }
  if !parsed_err(mac_parse("aa:bb:cc:dd:ee:f"), "mac: invalid length") { ok = false; }
  if !parsed_err(mac_parse("aabbccddeeff0"), "mac: invalid length") { ok = false; }
  if !parsed_err(mac_parse("aa:bb:cc:dd:ee:ff:"), "mac: invalid length") { ok = false; }
  return assert(ok, "wrong lengths are Err(mac: invalid length)");
}

fn t9() -> TestResult {
  var ok = parsed_err(mac_parse("gg:bb:cc:dd:ee:ff"), "mac: invalid character");
  if !parsed_err(mac_parse("aa:bb:cc:dd:ee:fg"), "mac: invalid character") { ok = false; }
  if !parsed_err(mac_parse("aabb.ccgd.eeff"), "mac: invalid character") { ok = false; }
  if !parsed_err(mac_parse("aabbccddeefg"), "mac: invalid character") { ok = false; }
  if !parsed_err(mac_parse("aa:bb:cc:dd:ee:f "), "mac: invalid character") { ok = false; }
  return assert(ok, "non-hex bytes are Err(mac: invalid character)");
}

fn t10() -> TestResult {
  var ok = parsed_err(mac_parse("aa:bb-cc:dd:ee:ff"), "mac: invalid separator");
  if !parsed_err(mac_parse("aa.bb.cc.dd.ee.ff"), "mac: invalid separator") { ok = false; }
  if !parsed_err(mac_parse("aabb-ccdd.eeff"), "mac: invalid separator") { ok = false; }
  if !parsed_err(mac_parse("aabb.ccdd-eeff"), "mac: invalid separator") { ok = false; }
  if !parsed_err(mac_parse("aa;bb;cc;dd;ee;ff"), "mac: invalid separator") { ok = false; }
  return assert(ok, "mixed or wrong separators are Err(mac: invalid separator)");
}

fn t11() -> TestResult {
  var ok = streq(mac_format(-1), "ff:ff:ff:ff:ff:ff");
  if !streq(mac_format(1 << 48), "00:00:00:00:00:00") { ok = false; }
  if !streq(mac_format(0xFFAABBCCDDEEFF), "aa:bb:cc:dd:ee:ff") { ok = false; }
  if !streq(mac_format(0x1FFFFFFFFFFFF), "ff:ff:ff:ff:ff:ff") { ok = false; }
  if !streq(mac_format(0x1000000000000 | 0x001122334455), "00:11:22:33:44:55") { ok = false; }
  return assert(ok, "mac_format masks bits above 48");
}

fn t12() -> TestResult {
  var ok = streq(mac_format_upper(0xAABBCCDDEE0F), "AA:BB:CC:DD:EE:0F");
  if !streq(mac_format_upper(0), "00:00:00:00:00:00") { ok = false; }
  if !streq(mac_format_upper(0x001122334455), "00:11:22:33:44:55") { ok = false; }
  if !streq(mac_format(0xAABBCCDDEE0F), "aa:bb:cc:dd:ee:0f") { ok = false; }
  return assert(ok, "mac_format_upper emits uppercase hex");
}

fn t13() -> TestResult {
  let b = 0xAABBCCDDEEFF;
  var ok = mac_oui(b) == 0xAABBCC;
  if mac_nic(b) != 0xDDEEFF { ok = false; }
  if mac_oui(0x001122334455) != 0x001122 { ok = false; }
  if mac_nic(0x001122334455) != 0x334455 { ok = false; }
  if ((mac_oui(b) << 24) | mac_nic(b)) != b { ok = false; }
  if mac_oui(0xFFAABBCCDDEEFF) != 0xAABBCC { ok = false; }
  if mac_nic(0xFFAABBCCDDEEFF) != 0xDDEEFF { ok = false; }
  return assert(ok, "oui is bits 47..24 and nic bits 23..0");
}

fn t14() -> TestResult {
  var ok = mac_is_multicast(0x01005E000001);
  if !mac_is_multicast(0xFFFFFFFFFFFF) { ok = false; }
  if !mac_is_multicast(0x030000000000) { ok = false; }
  if mac_is_multicast(0x001122334455) { ok = false; }
  if mac_is_multicast(0x020000000000) { ok = false; }
  if mac_is_multicast(0) { ok = false; }
  return assert(ok, "multicast is bit 0 of the first octet (01:00:5e:...)");
}

fn t15() -> TestResult {
  var ok = mac_is_local(0x020000000000);
  if !mac_is_local(0xFE0000000000) { ok = false; }
  if !mac_is_local(0x030000000000) { ok = false; }
  if mac_is_local(0x001122334455) { ok = false; }
  if mac_is_local(0x010000000000) { ok = false; }
  if mac_is_local(0) { ok = false; }
  return assert(ok, "local bit is bit 1 of the first octet (02:... true)");
}

fn t16() -> TestResult {
  var ok = mac_is_unicast(0x001122334455);
  if !mac_is_unicast(0) { ok = false; }
  if !mac_is_unicast(0x020000000000) { ok = false; }
  if mac_is_unicast(0x01005E000001) { ok = false; }
  if mac_is_unicast(0xFFFFFFFFFFFF) { ok = false; }
  return assert(ok, "unicast is the complement of multicast");
}

fn t17() -> TestResult {
  var ok = mac_broadcast() == 0xFFFFFFFFFFFF;
  if !mac_is_broadcast(mac_broadcast()) { ok = false; }
  if !mac_is_broadcast(0xFFFFFFFFFFFF) { ok = false; }
  if !mac_is_broadcast(0x1FFFFFFFFFFFF) { ok = false; }
  if mac_is_broadcast(0) { ok = false; }
  if mac_is_broadcast(0xFE1122334455) { ok = false; }
  if mac_is_broadcast(0xFFFFFFFF) { ok = false; }
  return assert(ok, "broadcast constant and predicate pin all 48 bits");
}

fn t18() -> TestResult {
  var ok = parsed_is(mac_parse("00:00:00:00:00:00"), 0);
  if !parsed_is(mac_parse("0000.0000.0000"), 0) { ok = false; }
  if !parsed_is(mac_parse("000000000000"), 0) { ok = false; }
  if !streq(mac_format(0), "00:00:00:00:00:00") { ok = false; }
  if !streq(mac_format_upper(0), "00:00:00:00:00:00") { ok = false; }
  if mac_oui(0) != 0 { ok = false; }
  if mac_nic(0) != 0 { ok = false; }
  if mac_is_multicast(0) { ok = false; }
  if mac_is_local(0) { ok = false; }
  if !mac_is_unicast(0) { ok = false; }
  if mac_is_broadcast(0) { ok = false; }
  return assert(ok, "zero address parses, formats and flags cleanly");
}

fn t19() -> TestResult {
  let max = 0xFFFFFFFFFFFF;
  var ok = parsed_is(mac_parse("ff:ff:ff:ff:ff:ff"), max);
  if !parsed_is(mac_parse("FF-FF-FF-FF-FF-FF"), max) { ok = false; }
  if !parsed_is(mac_parse("ffff.ffff.ffff"), max) { ok = false; }
  if !parsed_is(mac_parse("ffffffffffff"), max) { ok = false; }
  if mac_oui(max) != 0xFFFFFF { ok = false; }
  if mac_nic(max) != 0xFFFFFF { ok = false; }
  if !streq(mac_format(max), "ff:ff:ff:ff:ff:ff") { ok = false; }
  return assert(ok, "48-bit maximum parses and formats");
}

fn t20() -> TestResult {
  let m = 0xAABBCCDDEEFF;
  let lower = mac_format(m);
  let upper = mac_format_upper(m);
  var ok = streq(lower, "aa:bb:cc:dd:ee:ff");
  if !streq(upper, "AA:BB:CC:DD:EE:FF") { ok = false; }
  let back1 = mac_parse(lower);
  let back2 = mac_parse(upper);
  if !back1.is_ok || !back2.is_ok { ok = false; }
  if back1.is_ok {
    if back1.value != m { ok = false; }
    if !streq(mac_format(back1.value), lower) { ok = false; }
  }
  if back2.is_ok {
    if back2.value != m { ok = false; }
  }
  return assert(ok, "format -> parse -> format round-trips both cases");
}

fn main() -> Int {
  io.println("=== xiom.macaddr conformance tests ===");
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
    io.println("xiom.macaddr: all tests passed");
  } else {
    io.println("xiom.macaddr: tests failed");
  }
  return failed;
}
