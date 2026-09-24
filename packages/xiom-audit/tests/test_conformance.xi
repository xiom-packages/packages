// XIOM -- xiom.audit conformance tests (23 checks)
// Port task: prove the pure-XIOM xiom.audit module against its chain contract.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module audit_tests
use xiom.io; use xiom.test; use xiom.audit; use xiom.convert;
use xiom.string.compare;

// All Str equality goes through str_compare: BUG 17 lowers `==` on Str values
// read from Vec[Str] elements to a pointer comparison, so every text check
// below is routed through streq.
//
// Read-only operations are wrapped in helpers that take `&mut`, so a
// `&local` read call is never followed by a `&mut local` call in the same
// function body (advisory E001). Each helper calls the real `&`-based API.

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn len_of(log: &mut AuditLog) -> Int {
  return audit_len(log);
}

fn entry_of(log: &mut AuditLog, i: Int) -> Str {
  return audit_entry(log, i);
}

fn hash_of(log: &mut AuditLog, i: Int) -> Int {
  return audit_hash(log, i);
}

fn head_of(log: &mut AuditLog) -> Int {
  return audit_head_hash(log);
}

fn verify_of(log: &mut AuditLog) -> Bool {
  return audit_verify(log);
}

fn prefix_of(log: &mut AuditLog, up_to: Int) -> Bool {
  return audit_verify_prefix(log, up_to);
}

fn export_of(log: &mut AuditLog) -> Str {
  return audit_export(log);
}

fn t1() -> TestResult {
  let h = audit_hash_fnv1a("");
  var ok = h == 2166136261;
  if audit_hash_fnv1a("") != 2166136261 { ok = false; }
  return assert(ok, "fnv1a empty string is the offset basis 0x811C9DC5");
}

fn t2() -> TestResult {
  let h = audit_hash_fnv1a("a");
  var ok = h == 3826002220;
  if audit_hash_fnv1a("a") != 3826002220 { ok = false; }
  return assert(ok, "fnv1a of \"a\" is 0xE40C292C");
}

fn t3() -> TestResult {
  let h = audit_hash_fnv1a("foobar");
  var ok = h == 3214735720;
  if audit_hash_fnv1a("foobar") != 3214735720 { ok = false; }
  return assert(ok, "fnv1a of \"foobar\" is 0xBF9CF968");
}

fn t4() -> TestResult {
  let a1 = audit_hash_fnv1a("audit");
  let a2 = audit_hash_fnv1a("audit");
  var ok = a1 == a2;
  if audit_hash_fnv1a("audit!") == a1 { ok = false; }
  if audit_hash_fnv1a("audit ") == a1 { ok = false; }
  if a1 < 0 { ok = false; }
  if a1 > 4294967295 { ok = false; }
  return assert(ok, "fnv1a is deterministic, 32-bit and separates nearby inputs");
}

fn t5() -> TestResult {
  var log = audit_new();
  var ok = len_of(&mut log) == 0;
  if head_of(&mut log) != 0 { ok = false; }
  if !verify_of(&mut log) { ok = false; }
  if !streq(export_of(&mut log), "") { ok = false; }
  return assert(ok, "fresh log is empty, head 0, verify true, export empty");
}

fn t6() -> TestResult {
  var log = audit_new();
  let h = audit_append(&mut log, "first");
  let stored = hash_of(&mut log, 0);
  var ok = h == stored;
  if len_of(&mut log) != 1 { ok = false; }
  if !verify_of(&mut log) { ok = false; }
  return assert(ok, "append returns the hash stored at the new index");
}

fn t7() -> TestResult {
  var a = audit_new();
  var b = audit_new();
  audit_append(&mut a, "alpha");
  audit_append(&mut a, "beta");
  audit_append(&mut b, "alpha");
  audit_append(&mut b, "beta");
  var ok = head_of(&mut a) == head_of(&mut b);
  if hash_of(&mut a, 0) != hash_of(&mut b, 0) { ok = false; }
  if hash_of(&mut a, 1) != hash_of(&mut b, 1) { ok = false; }
  if !verify_of(&mut a) { ok = false; }
  if !verify_of(&mut b) { ok = false; }
  return assert(ok, "two logs fed the same entries build the same chain");
}

fn t8() -> TestResult {
  var log = audit_new();
  audit_append(&mut log, "x");
  audit_append(&mut log, "x");
  var ok = hash_of(&mut log, 0) != hash_of(&mut log, 1);
  if !verify_of(&mut log) { ok = false; }
  return assert(ok, "the same entry at different positions chains to different hashes");
}

fn t9() -> TestResult {
  var log = audit_new();
  var ok = verify_of(&mut log);
  var i = 0;
  while i < 10 {
    audit_append(&mut log, "entry");
    if !verify_of(&mut log) { ok = false; }
    if len_of(&mut log) != i + 1 { ok = false; }
    i = i + 1;
  }
  return assert(ok, "verify is true for a fresh log and after every append");
}

fn t10() -> TestResult {
  var log = audit_new();
  audit_append(&mut log, "original");
  let h = hash_of(&mut log, 0);
  log.entries[0] = "tampered";
  var ok = !verify_of(&mut log);
  if hash_of(&mut log, 0) != h { ok = false; }
  if !streq(entry_of(&mut log, 0), "tampered") { ok = false; }
  return assert(ok, "mutating a stored entry makes verify false");
}

fn t11() -> TestResult {
  var log = audit_new();
  audit_append(&mut log, "a");
  audit_append(&mut log, "b");
  audit_append(&mut log, "c");
  var ok = verify_of(&mut log);
  let mid: Int = log.hashes[1];
  log.hashes[1] = mid + 1;
  if verify_of(&mut log) { ok = false; }
  if hash_of(&mut log, 1) != mid + 1 { ok = false; }
  return assert(ok, "mutating a middle hash breaks verification");
}

fn t12() -> TestResult {
  var log = audit_new();
  audit_append(&mut log, "a");
  audit_append(&mut log, "b");
  var ok = verify_of(&mut log);
  log.hashes.pop();
  if verify_of(&mut log) { ok = false; }
  if head_of(&mut log) != hash_of(&mut log, 0) { ok = false; }
  return assert(ok, "a truncated hash vector fails whole-log verification");
}

fn t13() -> TestResult {
  var log = audit_new();
  audit_append(&mut log, "a");
  audit_append(&mut log, "b");
  audit_append(&mut log, "c");
  var ok = prefix_of(&mut log, 0);
  if !prefix_of(&mut log, -1) { ok = false; }
  if !prefix_of(&mut log, 2) { ok = false; }
  if !prefix_of(&mut log, 3) { ok = false; }
  if !prefix_of(&mut log, 99) { ok = false; }
  log.entries[1] = "B";
  if prefix_of(&mut log, 2) { ok = false; }
  if !prefix_of(&mut log, 1) { ok = false; }
  if prefix_of(&mut log, 99) { ok = false; }
  return assert(ok, "verify_prefix checks exactly [0, up_to) with clamping");
}

fn t14() -> TestResult {
  var a = audit_new();
  var b = audit_new();
  audit_append(&mut a, "x");
  audit_append(&mut b, "y");
  var ok = head_of(&mut a) != head_of(&mut b);
  if head_of(&mut a) != hash_of(&mut a, 0) { ok = false; }
  return assert(ok, "head hash follows the last entry and its content");
}

fn t15() -> TestResult {
  var a = audit_new();
  var b = audit_new();
  audit_append(&mut a, "one");
  audit_append(&mut b, "one");
  let before = head_of(&mut a);
  audit_append(&mut b, "two");
  var ok = before == head_of(&mut a);
  if head_of(&mut b) == before { ok = false; }
  if head_of(&mut b) != hash_of(&mut b, 1) { ok = false; }
  return assert(ok, "appending moves the head and identical prefixes agree");
}

fn t16() -> TestResult {
  var log = audit_new();
  audit_append(&mut log, "first");
  let h = hash_of(&mut log, 0);
  let want = "0|" + convert.int_to_string(h) + "|first";
  var ok = streq(export_of(&mut log), want);
  return assert(ok, "export line is <seq>|<hash>|<entry>");
}

fn t17() -> TestResult {
  var log = audit_new();
  audit_append(&mut log, "a");
  audit_append(&mut log, "b");
  let h0 = hash_of(&mut log, 0);
  let h1 = hash_of(&mut log, 1);
  let want = "0|" + convert.int_to_string(h0) + "|a\n1|" + convert.int_to_string(h1) + "|b";
  var ok = streq(export_of(&mut log), want);
  return assert(ok, "export joins lines with LF and numbers entries from 0");
}

fn t18() -> TestResult {
  var log = audit_new();
  audit_append(&mut log, "a|b");
  audit_append(&mut log, "line1\nline2");
  let h0 = hash_of(&mut log, 0);
  let h1 = hash_of(&mut log, 1);
  let e0 = "a" + "\\" + "|b";
  let e1 = "line1" + "\\" + "nline2";
  let want = "0|" + convert.int_to_string(h0) + "|" + e0 + "\n1|" + convert.int_to_string(h1) + "|" + e1;
  var ok = streq(export_of(&mut log), want);
  if e0.len() != 4 { ok = false; }
  if e1.len() != 12 { ok = false; }
  return assert(ok, "export escapes '|' as \\| and LF as \\n");
}

fn t19() -> TestResult {
  var log = audit_new();
  var ok = hash_of(&mut log, 0) == -1;
  if !streq(entry_of(&mut log, 0), "") { ok = false; }
  if hash_of(&mut log, -1) != -1 { ok = false; }
  if !streq(entry_of(&mut log, -1), "") { ok = false; }
  audit_append(&mut log, "one");
  if hash_of(&mut log, 1) != -1 { ok = false; }
  if !streq(entry_of(&mut log, 1), "") { ok = false; }
  if !streq(entry_of(&mut log, -5), "") { ok = false; }
  return assert(ok, "out-of-range entry is empty and out-of-range hash is -1");
}

fn t20() -> TestResult {
  var log = audit_new();
  audit_append(&mut log, "zero");
  audit_append(&mut log, "one");
  audit_append(&mut log, "two");
  var ok = streq(entry_of(&mut log, 0), "zero");
  if !streq(entry_of(&mut log, 1), "one") { ok = false; }
  if !streq(entry_of(&mut log, 2), "two") { ok = false; }
  if len_of(&mut log) != 3 { ok = false; }
  return assert(ok, "entries are stored in append order");
}

fn t21() -> TestResult {
  var log = audit_new();
  var i = 0;
  while i < 100 {
    audit_append(&mut log, "entry-" + convert.int_to_string(i));
    i = i + 1;
  }
  var ok = len_of(&mut log) == 100;
  if !verify_of(&mut log) { ok = false; }
  if head_of(&mut log) != hash_of(&mut log, 99) { ok = false; }
  if hash_of(&mut log, 0) == hash_of(&mut log, 99) { ok = false; }
  return assert(ok, "a 100-entry chain verifies end to end");
}

fn t22() -> TestResult {
  var log = audit_new();
  var i = 0;
  while i < 20 {
    audit_append(&mut log, "e" + convert.int_to_string(i));
    i = i + 1;
  }
  var ok = verify_of(&mut log);
  log.entries[10] = "MUTATED";
  if verify_of(&mut log) { ok = false; }
  if !prefix_of(&mut log, 10) { ok = false; }
  return assert(ok, "tampering one link breaks verification of the whole chain");
}

fn t23() -> TestResult {
  var log = audit_new();
  let h = audit_append(&mut log, "");
  var ok = h == hash_of(&mut log, 0);
  if h != audit_hash_fnv1a("0:") { ok = false; }
  let h2 = audit_append(&mut log, "");
  if h2 == h { ok = false; }
  if !verify_of(&mut log) { ok = false; }
  return assert(ok, "an empty entry hashes the payload \"0:\" and still chains");
}

fn main() -> Int {
  io.println("=== xiom.audit conformance tests ===");
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
  if failed == 0 {
    io.println("xiom.audit: all tests passed");
  } else {
    io.println("xiom.audit: tests failed");
  }
  return failed;
}
