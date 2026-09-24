// XIOM -- xiom.cidr conformance tests (22 checks)
// Port task: prove the pure-XIOM xiom.cidr module against its documented
// parsing, masking, containment and range semantics.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Coverage map: see SPEC.md section 7. Every check is a named
// assert(cond, "name") call and main returns the failure count (0 = green).
// No Vec[Str] value and no `==` on Str are used anywhere in this suite (BUG
// 17 lowers `==` on Str values read from Vec[Str] elements to a pointer
// comparison); every string comparison goes through compare.str_compare.

module cidr_tests
use xiom.io; use xiom.test; use xiom.cidr;
use xiom.string.compare;

// String equality through the stdlib comparator (never `==` on Str).
fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// Parsed value of a known-good dotted quad, or -1 when it fails to parse.
fn ipv(s: Str) -> Int {
  let r = cidr_ip_parse(s);
  if !r.is_ok {
    return -1;
  }
  return r.value;
}

// True when cidr_ip_parse(s) is Ok with exactly `want`.
fn ip_is(s: Str, want: Int) -> Bool {
  let r = cidr_ip_parse(s);
  if !r.is_ok {
    return false;
  }
  return r.value == want;
}

// True when cidr_ip_parse(s) is Err with exactly `want`.
fn ip_err_is(s: Str, want: Str) -> Bool {
  let r = cidr_ip_parse(s);
  if r.is_ok {
    return false;
  }
  return streq(r.error, want);
}

// True when cidr_parse(s) is Ok with exactly (want_net, want_prefix).
fn cidr_is(s: Str, want_net: Int, want_prefix: Int) -> Bool {
  let r = cidr_parse(s);
  if !r.is_ok {
    return false;
  }
  let t = r.value;
  return t.0 == want_net && t.1 == want_prefix;
}

// True when cidr_parse(s) is Err with exactly `want`.
fn cidr_err_is(s: Str, want: Str) -> Bool {
  let r = cidr_parse(s);
  if r.is_ok {
    return false;
  }
  return streq(r.error, want);
}

// Masking identities for one block: network == net & mask, broadcast ==
// network + host_count - 1, both ends contained, the address just outside
// either end excluded.
fn block_consistent(net: Int, prefix: Int) -> Bool {
  let m = cidr_mask(prefix);
  let n = cidr_network(net, prefix);
  if n != (net & m) {
    return false;
  }
  let b = cidr_broadcast(net, prefix);
  if b != n + cidr_host_count(prefix) - 1 {
    return false;
  }
  if !cidr_contains(net, prefix, n) {
    return false;
  }
  if !cidr_contains(net, prefix, b) {
    return false;
  }
  if prefix >= 1 {
    if cidr_contains(net, prefix, n - 1) {
      return false;
    }
  }
  if prefix >= 1 {
    if cidr_contains(net, prefix, b + 1) {
      return false;
    }
  }
  return true;
}

fn t1() -> TestResult {
  var ok = ip_is("0.0.0.0", 0);
  if !ip_is("1.2.3.4", 16909060) { ok = false; }
  if !ip_is("10.0.0.1", 167772161) { ok = false; }
  if !ip_is("128.0.0.0", 2147483648) { ok = false; }
  if !ip_is("192.168.1.1", 3232235777) { ok = false; }
  if !ip_is("223.255.255.255", 3758096383) { ok = false; }
  if !ip_is("255.255.255.255", 4294967295) { ok = false; }
  return assert(ok, "ip_parse: pinned dotted quads to 32-bit values");
}

fn t2() -> TestResult {
  var ok = streq(cidr_ip_format(0), "0.0.0.0");
  if !streq(cidr_ip_format(16909060), "1.2.3.4") { ok = false; }
  if !streq(cidr_ip_format(167772161), "10.0.0.1") { ok = false; }
  if !streq(cidr_ip_format(2147483648), "128.0.0.0") { ok = false; }
  if !streq(cidr_ip_format(3232235777), "192.168.1.1") { ok = false; }
  if !streq(cidr_ip_format(3758096383), "223.255.255.255") { ok = false; }
  if !streq(cidr_ip_format(4294967295), "255.255.255.255") { ok = false; }
  return assert(ok, "ip_format: pinned 32-bit values to dotted quads");
}

fn t3() -> TestResult {
  var ok = ip_is(cidr_ip_format(0), 0);
  if !ip_is(cidr_ip_format(1), 1) { ok = false; }
  if !ip_is(cidr_ip_format(255), 255) { ok = false; }
  if !ip_is(cidr_ip_format(256), 256) { ok = false; }
  if !ip_is(cidr_ip_format(65535), 65535) { ok = false; }
  if !ip_is(cidr_ip_format(65536), 65536) { ok = false; }
  if !ip_is(cidr_ip_format(16777215), 16777215) { ok = false; }
  if !ip_is(cidr_ip_format(16777216), 16777216) { ok = false; }
  if !ip_is(cidr_ip_format(2147483648), 2147483648) { ok = false; }
  if !ip_is(cidr_ip_format(4294967294), 4294967294) { ok = false; }
  if !ip_is(cidr_ip_format(4294967295), 4294967295) { ok = false; }
  return assert(ok, "round-trip: parse(format(v)) == v for boundary values");
}

fn t4() -> TestResult {
  var ok = ip_err_is("256.0.0.1", "cidr: invalid octet");
  if !ip_err_is("1.2.3.256", "cidr: invalid octet") { ok = false; }
  if !ip_err_is("999.1.1.1", "cidr: invalid octet") { ok = false; }
  if !ip_err_is("a.b.c.d", "cidr: invalid octet") { ok = false; }
  if !ip_err_is("1.2.3.+4", "cidr: invalid octet") { ok = false; }
  if !ip_err_is("1.2.-3.4", "cidr: invalid octet") { ok = false; }
  if !ip_err_is("1.2.3.4 ", "cidr: invalid octet") { ok = false; }
  if !ip_err_is("1234.2.3.4", "cidr: invalid octet") { ok = false; }
  if !ip_err_is("1.2.3.1234", "cidr: invalid octet") { ok = false; }
  return assert(ok, "ip_parse: bad octets rejected with exact errors");
}

fn t5() -> TestResult {
  var ok = ip_err_is("", "cidr: empty address");
  if !ip_err_is("1.2.3", "cidr: expected four octets") { ok = false; }
  if !ip_err_is("1.2.3.4.5", "cidr: expected four octets") { ok = false; }
  if !ip_err_is("1.2.3.4.5.6", "cidr: expected four octets") { ok = false; }
  if !ip_err_is(".1.2.3", "cidr: invalid octet") { ok = false; }
  if !ip_err_is("1.2.3.", "cidr: invalid octet") { ok = false; }
  if !ip_err_is("1..2.3", "cidr: invalid octet") { ok = false; }
  return assert(ok, "ip_parse: part count and empty part errors");
}

fn t6() -> TestResult {
  var ok = ip_is("0.0.0.0", 0);
  if !ip_is("1.2.3.0", 16909056) { ok = false; }
  if !ip_err_is("01.2.3.4", "cidr: invalid octet") { ok = false; }
  if !ip_err_is("1.02.3.4", "cidr: invalid octet") { ok = false; }
  if !ip_err_is("1.2.3.04", "cidr: invalid octet") { ok = false; }
  if !ip_err_is("00.1.2.3", "cidr: invalid octet") { ok = false; }
  if !ip_err_is("001.2.3.4", "cidr: invalid octet") { ok = false; }
  return assert(ok, "ip_parse: leading zeros rejected, bare 0 allowed");
}

fn t7() -> TestResult {
  var ok = cidr_is("192.168.1.77/24", ipv("192.168.1.0"), 24);
  if !cidr_is("10.1.2.3/8", ipv("10.0.0.0"), 8) { ok = false; }
  if !cidr_is("172.16.5.9/12", ipv("172.16.0.0"), 12) { ok = false; }
  if !cidr_is("172.20.5.9/16", ipv("172.20.0.0"), 16) { ok = false; }
  if !cidr_is("192.168.1.77/30", ipv("192.168.1.76"), 30) { ok = false; }
  if !cidr_is("1.2.3.4/32", 16909060, 32) { ok = false; }
  if !cidr_is("255.255.255.255/0", 0, 0) { ok = false; }
  return assert(ok, "cidr_parse: host bits are masked off");
}

fn t8() -> TestResult {
  var ok = cidr_is("0.0.0.0/0", 0, 0);
  if !cidr_is("1.2.3.4/0", 0, 0) { ok = false; }
  if !cidr_is("1.2.3.4/32", 16909060, 32) { ok = false; }
  if !cidr_is("10.0.0.1/31", ipv("10.0.0.0"), 31) { ok = false; }
  if !cidr_err_is("1.2.3.4/33", "cidr: prefix length out of range") { ok = false; }
  if !cidr_err_is("1.2.3.4/999", "cidr: prefix length out of range") { ok = false; }
  if !cidr_err_is("1.2.3.4/024", "cidr: invalid prefix length") { ok = false; }
  if !cidr_err_is("1.2.3.4/", "cidr: invalid prefix length") { ok = false; }
  if !cidr_err_is("1.2.3.4/-1", "cidr: invalid prefix length") { ok = false; }
  if !cidr_err_is("1.2.3.4/24x", "cidr: invalid prefix length") { ok = false; }
  if !cidr_err_is("1.2.3.4/24/8", "cidr: invalid prefix length") { ok = false; }
  if !cidr_err_is("1.2.3.4/2 4", "cidr: invalid prefix length") { ok = false; }
  return assert(ok, "cidr_parse: prefix 0..32, canonical decimal only");
}

fn t9() -> TestResult {
  var ok = cidr_err_is("", "cidr: empty input");
  if !cidr_err_is("1.2.3.4", "cidr: missing prefix length") { ok = false; }
  if !cidr_err_is("192.168.1.1", "cidr: missing prefix length") { ok = false; }
  if !cidr_err_is("1.2.3.256/24", "cidr: invalid octet") { ok = false; }
  if !cidr_err_is("1.2.3/24", "cidr: expected four octets") { ok = false; }
  if !cidr_err_is("/24", "cidr: expected four octets") { ok = false; }
  if !cidr_err_is("01.2.3.4/8", "cidr: invalid octet") { ok = false; }
  return assert(ok, "cidr_parse: missing slash and delegated address errors");
}

fn t10() -> TestResult {
  var ok = streq(cidr_format(ipv("192.168.1.0"), 24), "192.168.1.0/24");
  if !streq(cidr_format(0, 0), "0.0.0.0/0") { ok = false; }
  if !streq(cidr_format(4294967295, 32), "255.255.255.255/32") { ok = false; }
  if !streq(cidr_format(ipv("192.168.1.77"), 24), "192.168.1.0/24") { ok = false; }
  if !cidr_is(cidr_format(ipv("10.1.2.3"), 8), ipv("10.0.0.0"), 8) { ok = false; }
  if !cidr_is(cidr_format(4294967295, 12), ipv("255.240.0.0"), 12) { ok = false; }
  return assert(ok, "cidr_format: masked network text and round-trip");
}

fn t11() -> TestResult {
  var ok = cidr_mask(0) == 0;
  if cidr_mask(1) != 2147483648 { ok = false; }
  if cidr_mask(8) != 4278190080 { ok = false; }
  if cidr_mask(12) != 4293918720 { ok = false; }
  if cidr_mask(16) != 4294901760 { ok = false; }
  if cidr_mask(24) != 4294967040 { ok = false; }
  if cidr_mask(30) != 4294967292 { ok = false; }
  if cidr_mask(31) != 4294967294 { ok = false; }
  if cidr_mask(32) != 4294967295 { ok = false; }
  if cidr_mask(-1) != 0 { ok = false; }
  if cidr_mask(33) != 0 { ok = false; }
  if cidr_mask(64) != 0 { ok = false; }
  return assert(ok, "cidr_mask: pinned masks, 0 outside 0..32");
}

fn t12() -> TestResult {
  var ok = cidr_network(ipv("192.168.1.77"), 24) == ipv("192.168.1.0");
  if cidr_network(ipv("192.168.1.77"), 16) != ipv("192.168.0.0") { ok = false; }
  if cidr_network(ipv("192.168.1.77"), 8) != ipv("192.0.0.0") { ok = false; }
  if cidr_network(ipv("192.168.1.77"), 32) != ipv("192.168.1.77") { ok = false; }
  if cidr_network(ipv("192.168.1.77"), 0) != 0 { ok = false; }
  if cidr_network(4294967295, 8) != ipv("255.0.0.0") { ok = false; }
  if cidr_network(16909060, 33) != 0 { ok = false; }
  if cidr_network(16909060, -1) != 0 { ok = false; }
  return assert(ok, "cidr_network: ip & mask, out-of-range as /0");
}

fn t13() -> TestResult {
  var ok = cidr_broadcast(ipv("192.168.1.0"), 24) == ipv("192.168.1.255");
  if cidr_broadcast(ipv("192.168.0.0"), 16) != ipv("192.168.255.255") { ok = false; }
  if cidr_broadcast(ipv("192.168.1.0"), 30) != ipv("192.168.1.3") { ok = false; }
  if cidr_broadcast(ipv("192.168.1.77"), 32) != ipv("192.168.1.77") { ok = false; }
  if cidr_broadcast(0, 0) != 4294967295 { ok = false; }
  if cidr_broadcast(ipv("10.0.0.0"), 8) != ipv("10.255.255.255") { ok = false; }
  if cidr_broadcast(16909060, 33) != 4294967295 { ok = false; }
  return assert(ok, "cidr_broadcast: network | host bits");
}

fn t14() -> TestResult {
  let net = ipv("192.168.1.0");
  var ok = cidr_contains(net, 24, net);
  if !cidr_contains(net, 24, ipv("192.168.1.1")) { ok = false; }
  if !cidr_contains(net, 24, ipv("192.168.1.254")) { ok = false; }
  if !cidr_contains(net, 24, ipv("192.168.1.255")) { ok = false; }
  if cidr_contains(net, 24, ipv("192.168.0.255")) { ok = false; }
  if cidr_contains(net, 24, ipv("192.168.2.0")) { ok = false; }
  if !cidr_contains(ipv("192.168.1.77"), 32, ipv("192.168.1.77")) { ok = false; }
  if cidr_contains(ipv("192.168.1.77"), 32, ipv("192.168.1.78")) { ok = false; }
  if !cidr_contains(net, 31, ipv("192.168.1.1")) { ok = false; }
  if !cidr_contains(0, 0, ipv("255.255.255.255")) { ok = false; }
  if !cidr_contains(0, 0, 0) { ok = false; }
  if !cidr_contains(net, 24, ipv("192.168.1.77")) { ok = false; }
  return assert(ok, "cidr_contains: inclusive boundaries and /32");
}

fn t15() -> TestResult {
  var ok = cidr_overlap(ipv("10.0.0.0"), 8, ipv("10.1.2.0"), 24);
  if !cidr_overlap(ipv("10.1.2.0"), 24, ipv("10.0.0.0"), 8) { ok = false; }
  if !cidr_overlap(ipv("10.0.0.0"), 8, ipv("10.0.0.0"), 8) { ok = false; }
  if !cidr_overlap(ipv("10.0.0.0"), 8, ipv("10.255.255.255"), 32) { ok = false; }
  if cidr_overlap(ipv("10.0.0.0"), 8, ipv("11.0.0.0"), 8) { ok = false; }
  if cidr_overlap(ipv("192.168.1.0"), 24, ipv("192.168.2.0"), 24) { ok = false; }
  if cidr_overlap(ipv("192.168.1.0"), 32, ipv("192.168.1.1"), 32) { ok = false; }
  if !cidr_overlap(ipv("192.168.1.0"), 31, ipv("192.168.1.1"), 32) { ok = false; }
  if cidr_overlap(ipv("192.168.1.0"), 31, ipv("192.168.1.2"), 32) { ok = false; }
  if !cidr_overlap(0, 0, ipv("8.8.8.8"), 32) { ok = false; }
  return assert(ok, "cidr_overlap: containment, equality and disjoint blocks");
}

fn t16() -> TestResult {
  var ok = cidr_overlap(ipv("10.0.0.0"), 8, ipv("10.1.0.0"), 16) == cidr_overlap(ipv("10.1.0.0"), 16, ipv("10.0.0.0"), 8);
  if cidr_overlap(ipv("10.0.0.0"), 8, ipv("11.0.0.0"), 8) != cidr_overlap(ipv("11.0.0.0"), 8, ipv("10.0.0.0"), 8) { ok = false; }
  if cidr_overlap(ipv("172.16.0.0"), 12, ipv("172.31.0.0"), 16) != cidr_overlap(ipv("172.31.0.0"), 16, ipv("172.16.0.0"), 12) { ok = false; }
  if !cidr_overlap(ipv("172.16.0.0"), 12, ipv("172.31.0.0"), 16) { ok = false; }
  if cidr_overlap(ipv("172.16.0.0"), 12, ipv("172.32.0.0"), 16) { ok = false; }
  return assert(ok, "cidr_overlap: symmetric, /12 contains /16 but not outside");
}

fn t17() -> TestResult {
  var ok = cidr_host_count(0) == 4294967296;
  if cidr_host_count(8) != 16777216 { ok = false; }
  if cidr_host_count(24) != 256 { ok = false; }
  if cidr_host_count(30) != 4 { ok = false; }
  if cidr_host_count(31) != 2 { ok = false; }
  if cidr_host_count(32) != 1 { ok = false; }
  if cidr_host_count(-1) != 4294967296 { ok = false; }
  if cidr_host_count(33) != 4294967296 { ok = false; }
  return assert(ok, "cidr_host_count: pinned /0 /8 /24 /30 /31 /32, exact 2^32");
}

fn t18() -> TestResult {
  let net = ipv("192.168.1.0");
  var ok = cidr_first_host(net, 24) == ipv("192.168.1.1");
  if cidr_last_host(net, 24) != ipv("192.168.1.254") { ok = false; }
  if cidr_first_host(net, 30) != ipv("192.168.1.1") { ok = false; }
  if cidr_last_host(net, 30) != ipv("192.168.1.2") { ok = false; }
  if cidr_first_host(ipv("10.0.0.0"), 8) != ipv("10.0.0.1") { ok = false; }
  if cidr_last_host(ipv("10.0.0.0"), 8) != ipv("10.255.255.254") { ok = false; }
  if cidr_first_host(0, 0) != 1 { ok = false; }
  if cidr_last_host(0, 0) != 4294967294 { ok = false; }
  if cidr_first_host(ipv("192.168.1.77"), 24) != ipv("192.168.1.1") { ok = false; }
  return assert(ok, "first_host/last_host: usable range for 0..30");
}

fn t19() -> TestResult {
  let a = ipv("192.168.1.0");
  var ok = cidr_first_host(a, 31) == a;
  if cidr_last_host(a, 31) != a { ok = false; }
  let b = ipv("192.168.1.77");
  if cidr_first_host(b, 32) != b { ok = false; }
  if cidr_last_host(b, 32) != b { ok = false; }
  if cidr_first_host(0, 32) != 0 { ok = false; }
  if cidr_last_host(0, 32) != 0 { ok = false; }
  if cidr_first_host(4294967295, 32) != 4294967295 { ok = false; }
  if cidr_last_host(4294967295, 32) != 4294967295 { ok = false; }
  return assert(ok, "first_host/last_host: /31 and /32 return the network");
}

fn t20() -> TestResult {
  var ok = block_consistent(ipv("10.0.0.0"), 8);
  if !block_consistent(ipv("172.16.0.0"), 12) { ok = false; }
  if !block_consistent(ipv("192.168.1.0"), 24) { ok = false; }
  if !block_consistent(ipv("192.168.1.76"), 30) { ok = false; }
  if !block_consistent(ipv("100.64.0.0"), 10) { ok = false; }
  return assert(ok, "consistency: network/broadcast/contains agree per block");
}

fn t21() -> TestResult {
  var ok = cidr_network(4294967295, 0) == 0;
  if cidr_broadcast(0, 0) != 4294967295 { ok = false; }
  if !cidr_contains(0, 0, 0) { ok = false; }
  if !cidr_contains(0, 0, 4294967295) { ok = false; }
  if !cidr_contains(123, 0, 456) { ok = false; }
  if cidr_broadcast(4294967295, 32) != 4294967295 { ok = false; }
  if cidr_network(4294967296, 32) != 0 { ok = false; }
  if !streq(cidr_ip_format(4294967296), "0.0.0.0") { ok = false; }
  if !streq(cidr_ip_format(-1), "255.255.255.255") { ok = false; }
  return assert(ok, "/0 spans the whole space; values are masked to 32 bits");
}

fn t22() -> TestResult {
  var ok = cidr_last_host(0, 0) - cidr_first_host(0, 0) + 1 == cidr_host_count(0) - 2;
  if cidr_last_host(0, 0) - cidr_first_host(0, 0) != 4294967293 { ok = false; }
  if cidr_host_count(0) - 1 != 4294967295 { ok = false; }
  if cidr_network(4294967295, 32) != 4294967295 { ok = false; }
  if cidr_broadcast(ipv("223.255.255.255"), 32) != 3758096383 { ok = false; }
  if cidr_network(ipv("223.255.255.255"), 24) != 3758096128 { ok = false; }
  if cidr_host_count(24) * 16777216 != 4294967296 { ok = false; }
  return assert(ok, "huge values: 2^32 stays exact in 64-bit Int");
}

fn main() -> Int {
  io.println("=== xiom.cidr conformance tests ===");
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
  if failed == 0 {
    io.println("xiom.cidr: all tests passed");
  } else {
    io.println("xiom.cidr: tests failed");
  }
  return failed;
}
