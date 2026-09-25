// XIOM -- xiom.ulid conformance tests (18 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Coverage map: see SPEC.md section 8. Every check is a named
// assert(cond, "name") call and main returns the failure count (0 = green).
// All Str equality goes through str_compare via the local streq helper
// (BUG 17 discipline: `==` on Str values read from Vec[Str] elements lowers
// to a pointer comparison, so no comparison below uses `==` on Str).
// Pinned vectors were computed with an independent arbitrary-precision
// reference implementation (PowerShell bigint) and cross-checked against the
// ULID specification's published example "01ARZ3NDEKTSV4RRFFQ69G5FAV"
// (timestamp 1469922850259) and its monotonic example pair
// "01BX5ZZKBKACTAV9WEVGEMMVRZ" -> "01BX5ZZKBKACTAV9WEVGEMMVS0".

module ulid_tests
use xiom.io; use xiom.test; use xiom.ulid;
use xiom.string; use xiom.string.builder; use xiom.string.compare;

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// True when r is Ok(v) with v == want.
fn int_ok_is(r: Result[Int, Str], want: Int) -> Bool {
  if !r.is_ok {
    return false;
  }
  let v: Int = r.value;
  return v == want;
}

// True when r is Err with exactly the message `want`.
fn int_err_is(r: Result[Int, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  let m: Str = r.error;
  return streq(m, want);
}

// True when r is Ok(v) with v equal to want.
fn str_ok_is(r: Result[Str, Str], want: Str) -> Bool {
  if !r.is_ok {
    return false;
  }
  let v: Str = r.value;
  return streq(v, want);
}

// True when r is Err with exactly the message `want`.
fn str_err_is(r: Result[Str, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  let m: Str = r.error;
  return streq(m, want);
}

// True when r is Ok(v) with v == want.
fn bool_ok_is(r: Result[Bool, Str], want: Bool) -> Bool {
  if !r.is_ok {
    return false;
  }
  let v: Bool = r.value;
  return v == want;
}

// True when r is Err with exactly the message `want`.
fn bool_err_is(r: Result[Bool, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  let m: Str = r.error;
  return streq(m, want);
}

// A Str of n repetitions of the single character c.
fn rep(c: Str, n: Int) -> Str {
  let b = string.byte_at(c, 0);
  var v = Vec[UInt8].new();
  var i = 0;
  while i < n {
    v.push(b);
    i = i + 1;
  }
  return builder.sb_to_str(&v);
}

// True when (ts, hi, lo) survives encode -> component decode -> canonical
// and reports as valid.
fn rt_case(ts: Int, hi: Int, lo: Int) -> Bool {
  let e = ulid_encode(ts, hi, lo);
  if !e.is_ok {
    return false;
  }
  let text: Str = e.value;
  if !int_ok_is(ulid_timestamp(text), ts) { return false; }
  if !int_ok_is(ulid_random_hi(text), hi) { return false; }
  if !int_ok_is(ulid_random_lo(text), lo) { return false; }
  if !str_ok_is(ulid_canonical(text), text) { return false; }
  if !ulid_is_valid(text) { return false; }
  return true;
}

fn t1() -> TestResult {
  let a = ulid_alphabet();
  var ok = streq(a, "0123456789ABCDEFGHJKMNPQRSTVWXYZ");
  if a.len() != 32 { ok = false; }
  var i = 0;
  while i < a.len() {
    let b = (string.byte_at(a, i) as Int) & 0xFF;
    if b == 73 || b == 76 || b == 79 || b == 85 { ok = false; }
    if b >= 97 && b <= 122 { ok = false; }
    i = i + 1;
  }
  return assert(ok, "alphabet: 32 canonical chars, no I/L/O/U, no lowercase");
}

fn t2() -> TestResult {
  var ok = str_ok_is(ulid_encode(0, 0, 0), "00000000000000000000000000");
  if !str_ok_is(ulid_encode(1, 0, 0), "00000000010000000000000000") { ok = false; }
  if !str_ok_is(ulid_encode(0, 1, 0), "00000000000000000100000000") { ok = false; }
  if !str_ok_is(ulid_encode(0, 0, 1), "00000000000000000000000001") { ok = false; }
  if !str_ok_is(ulid_encode(1469922850259, 921107718639, 797035380059), "01ARZ3NDEKTSV4RRFFQ69G5FAV") { ok = false; }
  if !str_ok_is(ulid_encode(1700000000000, 4886718345, 654570336784), "01HF7YAT0004HMASW9K1KPXCGG") { ok = false; }
  return assert(ok, "encode: pinned vectors incl. the ULID spec example");
}

fn t3() -> TestResult {
  var ok = str_ok_is(ulid_encode(281474976710655, 0, 0), "7ZZZZZZZZZ0000000000000000");
  if !str_ok_is(ulid_encode(0, 1099511627775, 0), "0000000000ZZZZZZZZ00000000") { ok = false; }
  if !str_ok_is(ulid_encode(0, 0, 1099511627775), "000000000000000000ZZZZZZZZ") { ok = false; }
  if !str_ok_is(ulid_encode(281474976710655, 1099511627775, 1099511627775), "7ZZZZZZZZZZZZZZZZZZZZZZZZZ") { ok = false; }
  return assert(ok, "encode: max timestamp and max randomness halves");
}

fn t4() -> TestResult {
  var ok = str_err_is(ulid_encode(-1, 0, 0), "ulid: timestamp out of range");
  if !str_err_is(ulid_encode(281474976710656, 0, 0), "ulid: timestamp out of range") { ok = false; }
  if !str_err_is(ulid_encode(0, -1, 0), "ulid: randomness out of range") { ok = false; }
  if !str_err_is(ulid_encode(0, 1099511627776, 0), "ulid: randomness out of range") { ok = false; }
  if !str_err_is(ulid_encode(0, 0, -1), "ulid: randomness out of range") { ok = false; }
  if !str_err_is(ulid_encode(0, 0, 1099511627776), "ulid: randomness out of range") { ok = false; }
  let top = ulid_encode(281474976710655, 1099511627775, 1099511627775);
  if !top.is_ok { ok = false; }
  return assert(ok, "encode: out-of-range timestamp and randomness halves are Err");
}

fn t5() -> TestResult {
  var ok = int_ok_is(ulid_timestamp("01ARZ3NDEKTSV4RRFFQ69G5FAV"), 1469922850259);
  if !int_ok_is(ulid_random_hi("01ARZ3NDEKTSV4RRFFQ69G5FAV"), 921107718639) { ok = false; }
  if !int_ok_is(ulid_random_lo("01ARZ3NDEKTSV4RRFFQ69G5FAV"), 797035380059) { ok = false; }
  if !int_ok_is(ulid_timestamp("00000000000000000000000000"), 0) { ok = false; }
  if !int_ok_is(ulid_random_hi("00000000000000000100000000"), 1) { ok = false; }
  if !int_ok_is(ulid_random_lo("00000000000000000000000001"), 1) { ok = false; }
  if !int_ok_is(ulid_timestamp("7ZZZZZZZZZ0000000000000000"), 281474976710655) { ok = false; }
  if !int_ok_is(ulid_random_hi("0000000000ZZZZZZZZ00000000"), 1099511627775) { ok = false; }
  if !int_ok_is(ulid_random_lo("000000000000000000ZZZZZZZZ"), 1099511627775) { ok = false; }
  return assert(ok, "decode: timestamp and randomness halves of pinned vectors");
}

fn t6() -> TestResult {
  let lower = "01arz3ndektsv4rrffq69g5fav";
  let mixed = "01ARZ3NDEKTSV4RRFFQ69g5Fav";
  let canon = "01ARZ3NDEKTSV4RRFFQ69G5FAV";
  var ok = int_ok_is(ulid_timestamp(lower), 1469922850259);
  if !int_ok_is(ulid_random_hi(lower), 921107718639) { ok = false; }
  if !int_ok_is(ulid_random_lo(lower), 797035380059) { ok = false; }
  if !str_ok_is(ulid_canonical(lower), canon) { ok = false; }
  if !str_ok_is(ulid_canonical(mixed), canon) { ok = false; }
  if !str_ok_is(ulid_canonical(canon), canon) { ok = false; }
  if !bool_ok_is(ulid_equal(lower, canon), true) { ok = false; }
  return assert(ok, "decode: lowercase and mixed case match canonical; canonical() folds up");
}

fn t7() -> TestResult {
  let empty = "";
  let s25 = rep("0", 25);
  let s27 = rep("0", 27);
  var ok = int_err_is(ulid_timestamp(empty), "ulid: expected 26 characters");
  if !int_err_is(ulid_timestamp(s25), "ulid: expected 26 characters") { ok = false; }
  if !int_err_is(ulid_timestamp(s27), "ulid: expected 26 characters") { ok = false; }
  if !int_err_is(ulid_random_hi(s25), "ulid: expected 26 characters") { ok = false; }
  if !int_err_is(ulid_random_lo(s25), "ulid: expected 26 characters") { ok = false; }
  if !str_err_is(ulid_canonical(s25), "ulid: expected 26 characters") { ok = false; }
  if !bool_err_is(ulid_equal(s25, "00000000000000000000000000"), "ulid: expected 26 characters") { ok = false; }
  return assert(ok, "validation: wrong lengths are Err (empty, 25 and 27)");
}

fn t8() -> TestResult {
  let p25 = rep("0", 25);
  var ok = int_err_is(ulid_timestamp(p25 + "I"), "ulid: invalid character");
  if !int_err_is(ulid_timestamp(p25 + "L"), "ulid: invalid character") { ok = false; }
  if !int_err_is(ulid_timestamp(p25 + "O"), "ulid: invalid character") { ok = false; }
  if !int_err_is(ulid_timestamp(p25 + "U"), "ulid: invalid character") { ok = false; }
  if !int_err_is(ulid_timestamp(p25 + "i"), "ulid: invalid character") { ok = false; }
  if !int_err_is(ulid_timestamp(p25 + "l"), "ulid: invalid character") { ok = false; }
  if !int_err_is(ulid_timestamp(p25 + "o"), "ulid: invalid character") { ok = false; }
  if !int_err_is(ulid_timestamp(p25 + "u"), "ulid: invalid character") { ok = false; }
  if !int_err_is(ulid_timestamp(rep("0", 25) + "!"), "ulid: invalid character") { ok = false; }
  if !int_err_is(ulid_timestamp(rep("0", 25) + "-"), "ulid: invalid character") { ok = false; }
  if !int_err_is(ulid_timestamp(rep("0", 25) + " "), "ulid: invalid character") { ok = false; }
  if !int_err_is(ulid_timestamp(rep("0", 24) + "é"), "ulid: invalid character") { ok = false; }
  return assert(ok, "validation: I/L/O/U either case, punctuation and non-ASCII are Err");
}

fn t9() -> TestResult {
  var ok = int_err_is(ulid_timestamp("8" + rep("0", 25)), "ulid: overflow");
  if !int_err_is(ulid_timestamp("9" + rep("0", 25)), "ulid: overflow") { ok = false; }
  if !int_err_is(ulid_timestamp(rep("Z", 26)), "ulid: overflow") { ok = false; }
  if !int_err_is(ulid_timestamp(rep("z", 26)), "ulid: overflow") { ok = false; }
  if !str_err_is(ulid_canonical("8" + rep("0", 25)), "ulid: overflow") { ok = false; }
  if !int_ok_is(ulid_timestamp("7" + rep("Z", 25)), 281474976710655) { ok = false; }
  return assert(ok, "validation: first character 8..Z overflows the 128-bit space");
}

fn t10() -> TestResult {
  var ok = ulid_is_valid("00000000000000000000000000");
  if !ulid_is_valid("00000000010000000000000000") { ok = false; }
  if !ulid_is_valid("01ARZ3NDEKTSV4RRFFQ69G5FAV") { ok = false; }
  if !ulid_is_valid("01arz3ndektsv4rrffq69g5fav") { ok = false; }
  if !ulid_is_valid("7ZZZZZZZZZZZZZZZZZZZZZZZZZ") { ok = false; }
  if ulid_is_valid("") { ok = false; }
  if ulid_is_valid(rep("0", 25)) { ok = false; }
  if ulid_is_valid(rep("0", 27)) { ok = false; }
  if ulid_is_valid(rep("0", 25) + "I") { ok = false; }
  if ulid_is_valid(rep("Z", 26)) { ok = false; }
  if ulid_is_valid(rep("0", 24) + "é") { ok = false; }
  return assert(ok, "is_valid: true for valid forms, false for every error kind");
}

fn t11() -> TestResult {
  let spec = "01ARZ3NDEKTSV4RRFFQ69G5FAV";
  let lower = "01arz3ndektsv4rrffq69g5fav";
  let zero = "00000000000000000000000000";
  let ts1 = "00000000010000000000000000";
  let ts2 = "00000000020000000000000000";
  let hi1 = "00000000000000000100000000";
  let lomax = "000000000000000000ZZZZZZZZ";
  var ok = int_ok_is(ulid_compare(spec, spec), 0);
  if !int_ok_is(ulid_compare(spec, lower), 0) { ok = false; }
  if !int_ok_is(ulid_compare(ts1, ts2), -1) { ok = false; }
  if !int_ok_is(ulid_compare(ts2, ts1), 1) { ok = false; }
  if !int_ok_is(ulid_compare(zero, hi1), -1) { ok = false; }
  if !int_ok_is(ulid_compare(zero, lomax), -1) { ok = false; }
  if !int_ok_is(ulid_compare(hi1, lomax), 1) { ok = false; }
  if !int_err_is(ulid_compare("", zero), "ulid: expected 26 characters") { ok = false; }
  if !int_err_is(ulid_compare(zero, rep("0", 25) + "I"), "ulid: invalid character") { ok = false; }
  if !int_err_is(ulid_compare(rep("0", 25) + "I", ""), "ulid: invalid character") { ok = false; }
  let lex = compare.str_compare(zero, hi1);
  if lex >= 0 { ok = false; }
  return assert(ok, "compare: timestamp, rand_hi, rand_lo order; case-insensitive; Err first arg first");
}

fn t12() -> TestResult {
  let spec = "01ARZ3NDEKTSV4RRFFQ69G5FAV";
  var ok = bool_ok_is(ulid_equal(spec, spec), true);
  if !bool_ok_is(ulid_equal(spec, "01arz3ndektsv4rrffq69g5fav"), true) { ok = false; }
  if !bool_ok_is(ulid_equal("00000000000000000000000000", "00000000000000000000000001"), false) { ok = false; }
  if !bool_ok_is(ulid_equal("00000000000000000100000000", "000000000000000000ZZZZZZZZ"), false) { ok = false; }
  if !bool_ok_is(ulid_equal(spec, "01ARZ3NDEKTSV4RRFFQ69G5FAW"), false) { ok = false; }
  if !bool_err_is(ulid_equal("", spec), "ulid: expected 26 characters") { ok = false; }
  if !bool_err_is(ulid_equal(spec, rep("Z", 26)), "ulid: overflow") { ok = false; }
  return assert(ok, "equal: decoded-value equality across case; Err propagation");
}

fn t13() -> TestResult {
  let prev = "01BX5ZZKBKACTAV9WEVGEMMVRZ";
  let next = "01BX5ZZKBKACTAV9WEVGEMMVS0";
  var ok = bool_ok_is(ulid_monotonic_ok(prev, next), true);
  if !bool_ok_is(ulid_monotonic_ok(next, prev), false) { ok = false; }
  if !bool_ok_is(ulid_monotonic_ok(prev, prev), false) { ok = false; }
  if !bool_ok_is(ulid_monotonic_ok(prev, "01BX5ZZKBKACTAV9WEVGEMMVRY"), false) { ok = false; }
  if !bool_ok_is(ulid_monotonic_ok("00000000010000000000000000", "00000000020000000000000000"), true) { ok = false; }
  if !bool_ok_is(ulid_monotonic_ok("00000000020000000000000000", "00000000010000000000000000"), false) { ok = false; }
  if !bool_ok_is(ulid_monotonic_ok("7ZZZZZZZZZ0000000000000000", "7ZZZZZZZZZ0000000000000001"), true) { ok = false; }
  if !bool_ok_is(ulid_monotonic_ok("7" + rep("Z", 25), "7" + rep("Z", 24) + "Y"), false) { ok = false; }
  if !bool_err_is(ulid_monotonic_ok("", prev), "ulid: expected 26 characters") { ok = false; }
  if !bool_err_is(ulid_monotonic_ok(prev, rep("Z", 26)), "ulid: overflow") { ok = false; }
  return assert(ok, "monotonic_ok: same-ms needs strictly greater randomness; spec pair");
}

fn t14() -> TestResult {
  var ok = rt_case(0, 0, 0);
  if !rt_case(1, 0, 0) { ok = false; }
  if !rt_case(0, 1, 0) { ok = false; }
  if !rt_case(0, 0, 1) { ok = false; }
  if !rt_case(1469922850259, 921107718639, 797035380059) { ok = false; }
  if !rt_case(1700000000000, 4886718345, 654570336784) { ok = false; }
  if !rt_case(281474976710655, 0, 0) { ok = false; }
  if !rt_case(0, 1099511627775, 0) { ok = false; }
  if !rt_case(0, 0, 1099511627775) { ok = false; }
  if !rt_case(281474976710655, 1099511627775, 1099511627775) { ok = false; }
  var i = 1;
  while i <= 200 {
    let ts = (i * 1000003 + 7) % 281474976710656;
    let hi = (i * 999983 + 13) % 1099511627776;
    let lo = (i * 7919 + 12345) % 1099511627776;
    if !rt_case(ts, hi, lo) { ok = false; }
    i = i + 1;
  }
  return assert(ok, "round-trip: boundaries and a 200-case pseudo-random sweep");
}

fn t15() -> TestResult {
  let zero = "00000000000000000000000000";
  var ok = str_ok_is(ulid_canonical(zero), zero);
  if !str_err_is(ulid_canonical(""), "ulid: expected 26 characters") { ok = false; }
  if !str_err_is(ulid_canonical(rep("0", 25) + "I"), "ulid: invalid character") { ok = false; }
  if !str_err_is(ulid_canonical("8" + rep("0", 25)), "ulid: overflow") { ok = false; }
  if !str_ok_is(ulid_canonical("7" + rep("z", 25)), "7" + rep("Z", 25)) { ok = false; }
  return assert(ok, "canonical: uppercase identity, lowercase folded, errors propagated");
}

fn t16() -> TestResult {
  let alpha = ulid_alphabet();
  let p25 = rep("0", 25);
  var ok = true;
  var v = 0;
  while v < 32 {
    let c = string.str_slice(alpha, v, v + 1);
    let s = p25 + c;
    if !ulid_is_valid(s) { ok = false; }
    if !int_ok_is(ulid_random_lo(s), v) { ok = false; }
    v = v + 1;
  }
  return assert(ok, "validation: every alphabet character is accepted at its value");
}

fn t17() -> TestResult {
  var ok = int_err_is(ulid_timestamp(rep("0", 24) + "I"), "ulid: expected 26 characters");
  if !int_err_is(ulid_timestamp("8" + rep("0", 24) + "!"), "ulid: invalid character") { ok = false; }
  if !int_err_is(ulid_timestamp("8" + rep("0", 25)), "ulid: overflow") { ok = false; }
  if !int_ok_is(ulid_timestamp("7" + rep("Z", 25)), 281474976710655) { ok = false; }
  return assert(ok, "validation order: length, then first invalid character, then overflow");
}

fn t18() -> TestResult {
  let e1 = ulid_encode(1700000000000, 4886718345, 654570336784);
  let e2 = ulid_encode(1700000000000, 4886718345, 654570336784);
  var ok = e1.is_ok;
  if !e2.is_ok { ok = false; }
  if e1.is_ok && e2.is_ok {
    let a: Str = e1.value;
    let b: Str = e2.value;
    if !streq(a, b) { ok = false; }
    let c1 = ulid_canonical(a);
    if !c1.is_ok { ok = false; }
    if !str_ok_is(ulid_canonical(a), a) { ok = false; }
    if !int_ok_is(ulid_compare(a, b), 0) { ok = false; }
  }
  let spec = "01ARZ3NDEKTSV4RRFFQ69G5FAV";
  let tsv = ulid_timestamp(spec);
  let hiv = ulid_random_hi(spec);
  let lov = ulid_random_lo(spec);
  let good = tsv.is_ok && hiv.is_ok && lov.is_ok;
  if !good { ok = false; }
  if !ulid_is_valid(spec) { ok = false; }
  let bad = ulid_timestamp(rep("Z", 26));
  if bad.is_ok { ok = false; }
  if ulid_is_valid(rep("Z", 26)) { ok = false; }
  return assert(ok, "determinism: repeated calls agree; accessors agree with is_valid");
}

fn main() -> Int {
  io.println("=== xiom.ulid conformance tests ===");
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
    io.println("xiom.ulid: all tests passed");
  } else {
    io.println("xiom.ulid: tests failed");
  }
  return failed;
}
