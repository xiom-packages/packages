// XIOM -- xiom.adler32 conformance tests (22 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Every expected checksum below was computed with independent references:
// Python's zlib.adler32 (the original C implementation) plus two pure-Python
// references -- per-byte reduction and fully deferred reduction -- agreeing
// on every vector. The suite additionally re-derives the module's deferred
// cadence with a local per-byte reference (ref_bytewise) and a fully deferred
// one (ref_deferred), including on inputs longer than 5552 bytes, which is
// the proof obligation for the documented reduction cadence.
//
// Canonical vectors pinned: "", "a", "abc", "Wikipedia", "abcdef",
// "123456789", "Hello, world!", the high-bit bytes ff 00 80 7f 01, 1000x 0xFF,
// the 300/1000/5552/5553/6000-byte ramps (byte k = k % 256), 5552x/5553x/6000x
// 0xFF and 6000 zero bytes. The 5552-byte boundary is the zlib NMAX: the
// 5553/6000-byte fixtures cross it and prove deferred == per-byte reduction.
//
// Err strings are compared with compare.str_compare (BUG 17 discipline: `==`
// on Str values read from a Vec lowers to a pointer comparison); no Str is
// ever read out of a Vec in this suite and no Str `==` is used at all.
// Test dispatch is direct tN() calls -- no Vec[fn] table.

module adler32_tests
use xiom.io; use xiom.test;
use xiom.adler32;
use xiom.string;
use xiom.string.compare;

fn str_eq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn err_int_is(r: Result[Int, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn bytes_of(s: Str) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < s.len() {
    v.push(string.byte_at(s, i));
    i = i + 1;
  }
  return v;
}

// Bytes [from, to) of `d`, as a fresh vector (streaming tests must feed
// their own buffers; see the &struct.field / &result.value traps).
fn chunk(d: &Vec[UInt8], from: Int, to: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = from;
  while i < to {
    v.push(d[i]);
    i = i + 1;
  }
  return v;
}

// `n` copies of byte `b`.
fn repeat_byte(b: Int, n: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < n {
    v.push(b as UInt8);
    i = i + 1;
  }
  return v;
}

// `n` bytes, byte k = k % 256 (the xiom.crc / xiom.fletcher / xiom.fnv
// fixture). 5553 bytes and beyond cross the 5552-byte NMAX reduction
// boundary; 6000 bytes is the required wrap case.
fn ramp(n: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < n {
    v.push((i % 256) as UInt8);
    i = i + 1;
  }
  return v;
}

// ff 00 80 7f 01: exercises masked byte widening for values with bit 7 set.
fn high_bytes() -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  v.push(255);
  v.push(0);
  v.push(128);
  v.push(127);
  v.push(1);
  return v;
}

// Test-local Adler-32 reference with per-byte reduction (the RFC 1950
// recurrence, one `% 65521` after every byte), independent of the module's
// deferred cadence.
fn ref_bytewise(data: &Vec[UInt8]) -> Int {
  var s1 = 1;
  var s2 = 0;
  var i = 0;
  while i < data.len() {
    s1 = (s1 + ((data[i] as Int) & 255)) % 65521;
    s2 = (s2 + s1) % 65521;
    i = i + 1;
  }
  return s2 * 65536 + s1;
}

// Test-local Adler-32 reference with fully deferred reduction: no `%` until
// the very end. This is the other extreme of the cadence, and it must agree
// with both the module and ref_bytewise.
fn ref_deferred(data: &Vec[UInt8]) -> Int {
  var s1 = 1;
  var s2 = 0;
  var i = 0;
  while i < data.len() {
    s1 = s1 + ((data[i] as Int) & 255);
    s2 = s2 + s1;
    i = i + 1;
  }
  return (s2 % 65521) * 65536 + (s1 % 65521);
}

// True when both test-local references agree with the module on `data`.
fn refs_agree(data: &Vec[UInt8]) -> Bool {
  let m = adler32(data);
  if ref_bytewise(data) != m {
    return false;
  }
  if ref_deferred(data) != m {
    return false;
  }
  return true;
}

// True when the incremental API reproduces the one-shot checksum at every
// split point of `data` (both chunks may be empty).
fn splits_match(data: &Vec[UInt8]) -> Bool {
  let expect = adler32(data);
  var split = 0;
  while split <= data.len() {
    let head = chunk(data, 0, split);
    let tail = chunk(data, split, data.len());
    var s = adler32_init();
    s = adler32_update(s, &head);
    s = adler32_update(s, &tail);
    if adler32_finalize(s) != expect {
      return false;
    }
    split = split + 1;
  }
  return true;
}

// True when feeding `data` in fixed `step`-byte chunks (last chunk short)
// reproduces the one-shot checksum.
fn stride_match(data: &Vec[UInt8], step: Int) -> Bool {
  let expect = adler32(data);
  var s = adler32_init();
  var i = 0;
  while i < data.len() {
    var to = i + step;
    if to > data.len() {
      to = data.len();
    }
    let part = chunk(data, i, to);
    s = adler32_update(s, &part);
    i = to;
  }
  return adler32_finalize(s) == expect;
}

fn t1() -> TestResult {
  var e = Vec[UInt8].new();
  var ok = adler32_init() == 1;
  if adler32(&e) != 1 { ok = false; }
  if adler32_update(adler32_init(), &e) != 1 { ok = false; }
  if adler32_finalize(adler32_init()) != 1 { ok = false; }
  return assert(ok, "init state is 1 and one-shot/update/finalize of the empty input is 1 (0x00000001)");
}

fn t2() -> TestResult {
  var e = Vec[UInt8].new();
  let a = bytes_of("a");
  let abc = bytes_of("abc");
  let wiki = bytes_of("Wikipedia");
  var ok = adler32(&e) == 1;
  if adler32(&a) != 6422626 { ok = false; }
  if adler32(&abc) != 38600999 { ok = false; }
  if adler32(&wiki) != 300286872 { ok = false; }
  return assert(ok, "canonical vectors: empty 0x00000001, a 0x00620062, abc 0x024D0127, Wikipedia 0x11E60398");
}

fn t3() -> TestResult {
  let abcdef = bytes_of("abcdef");
  let digits = bytes_of("123456789");
  let hw = bytes_of("Hello, world!");
  var ok = adler32(&abcdef) == 136184406;
  if adler32(&digits) != 152961502 { ok = false; }
  if adler32(&hw) != 543032458 { ok = false; }
  return assert(ok, "abcdef 0x081E0256, 123456789 0x091E01DE, Hello, world! 0x205E048A pinned");
}

fn t4() -> TestResult {
  let hb = high_bytes();
  var ok = adler32(&hb) == 125764096;
  return assert(ok, "high-bit bytes ff 00 80 7f 01 pinned: 0x077F0200 (masked widening)");
}

fn t5() -> TestResult {
  let ff = repeat_byte(255, 1000);
  var ok = adler32(&ff) == 3874088006;
  return assert(ok, "1000 x 0xFF pinned: 0xE6E9E446");
}

fn t6() -> TestResult {
  let p = ramp(6000);
  let z = repeat_byte(0, 6000);
  var ok = adler32(&p) == 1525910894;
  if adler32(&z) != 393216001 { ok = false; }
  return assert(ok, "6000-byte wrap case: ramp 0x5AF38D6E, 6000 zeros 0x17700001 (s2 = 6000)");
}

fn t7() -> TestResult {
  let r5552 = ramp(5552);
  let r5553 = ramp(5553);
  let f5552 = repeat_byte(255, 5552);
  let f5553 = repeat_byte(255, 5553);
  let f6000 = repeat_byte(255, 6000);
  var ok = adler32(&r5552) == 2043458111;
  if adler32(&r5553) != 751481583 { ok = false; }
  if adler32(&f5552) != 4052720524 { ok = false; }
  if adler32(&f5553) != 2385091723 { ok = false; }
  if adler32(&f6000) != 2761382378 { ok = false; }
  return assert(ok, "NMAX boundary pinned: ramp5552 0x79CCB23F, ramp5553 0x2CCAB2EF, ff5552 0xF18F9B8C, ff5553 0x8E299C8B, ff6000 0xA49759EA");
}

fn t8() -> TestResult {
  let d = bytes_of("abcdefgh");
  let p0 = chunk(&d, 0, 0);
  let p1 = chunk(&d, 0, 1);
  let p2 = chunk(&d, 0, 2);
  let p3 = chunk(&d, 0, 3);
  let p4 = chunk(&d, 0, 4);
  let p5 = chunk(&d, 0, 5);
  let p6 = chunk(&d, 0, 6);
  let p7 = chunk(&d, 0, 7);
  let p8 = chunk(&d, 0, 8);
  var ok = adler32(&p0) == 1;
  if adler32(&p1) != 6422626 { ok = false; }
  if adler32(&p2) != 19267780 { ok = false; }
  if adler32(&p3) != 38600999 { ok = false; }
  if adler32(&p4) != 64487819 { ok = false; }
  if adler32(&p5) != 96993776 { ok = false; }
  if adler32(&p6) != 136184406 { ok = false; }
  if adler32(&p7) != 182125245 { ok = false; }
  if adler32(&p8) != 234881829 { ok = false; }
  return assert(ok, "all prefixes of \"abcdefgh\" pinned for lengths 0..8");
}

fn t9() -> TestResult {
  let full = bytes_of("abcdefgh");
  var ok = splits_match(&full);
  return assert(ok, "incremental equals one-shot at every split of \"abcdefgh\"");
}

fn t10() -> TestResult {
  let full = bytes_of("abcdef");
  var ok = splits_match(&full);
  return assert(ok, "incremental equals one-shot at every split of \"abcdef\"");
}

fn t11() -> TestResult {
  let p = ramp(6000);
  var ok = stride_match(&p, 1);
  return assert(ok, "byte-at-a-time streaming over the 6000-byte ramp (crosses NMAX) equals one-shot");
}

fn t12() -> TestResult {
  let d = bytes_of("The quick brown fox jumps over the lazy dog");
  var ok = true;
  var step = 1;
  while step <= 7 {
    if !stride_match(&d, step) { ok = false; }
    step = step + 1;
  }
  let p = ramp(6000);
  if !stride_match(&p, 5551) { ok = false; }
  if !stride_match(&p, 5552) { ok = false; }
  if !stride_match(&p, 5553) { ok = false; }
  return assert(ok, "chunked streaming steps 1..7 over a 43-byte message and steps 5551/5552/5553 over the 6000-byte ramp equal one-shot");
}

fn t13() -> TestResult {
  let p = ramp(6000);
  let s = adler32_update(adler32_init(), &p);
  var ok = s <= 4293984240;
  if s % 65536 > 65520 { ok = false; }
  if s / 65536 > 65520 { ok = false; }
  if !adler32_state_valid(s) { ok = false; }
  if adler32_finalize(s) != s { ok = false; }
  if s != 1525910894 { ok = false; }
  var e = Vec[UInt8].new();
  let z = adler32_update(adler32_init(), &e);
  if z % 65536 != 1 { ok = false; }
  if z / 65536 != 0 { ok = false; }
  return assert(ok, "update results are canonical: s1/s2 in [0, 65520], state_valid true, finalize the identity, ramp6000 pinned");
}

fn t14() -> TestResult {
  var ok = adler32_state_valid(0);
  if !adler32_state_valid(1) { ok = false; }
  if !adler32_state_valid(65520) { ok = false; }
  if !adler32_state_valid(65536) { ok = false; }
  if !adler32_state_valid(917518) { ok = false; }
  if !adler32_state_valid(4293918720) { ok = false; }
  if !adler32_state_valid(4293984240) { ok = false; }
  if adler32_state_valid(65521) { ok = false; }
  if adler32_state_valid(65535) { ok = false; }
  if adler32_state_valid(4293984241) { ok = false; }
  if adler32_state_valid(4294901759) { ok = false; }
  if adler32_state_valid(4294901760) { ok = false; }
  if adler32_state_valid(4294967295) { ok = false; }
  if adler32_state_valid(4294967296) { ok = false; }
  if adler32_state_valid(0 - 1) { ok = false; }
  return assert(ok, "state_valid boundaries: [0, 4293984240] with s1 <= 65520 accepted, modulus-fold and 32-bit wrap values rejected");
}

fn t15() -> TestResult {
  var e = Vec[UInt8].new();
  let abc = bytes_of("abc");
  var ok = adler32_update(0 - 1, &e) == 917518;
  if adler32_update(65521, &e) != 0 { ok = false; }
  if adler32_update(65535, &e) != 14 { ok = false; }
  if adler32_update(65536, &e) != 65536 { ok = false; }
  if adler32_update(4294901760, &e) != 917504 { ok = false; }
  if adler32_update(4294901761, &e) != 917505 { ok = false; }
  if adler32_update(4293984240, &e) != 4293984240 { ok = false; }
  if adler32_update(4293984241, &e) != 4293918720 { ok = false; }
  if adler32_update(4294967296, &e) != 0 { ok = false; }
  if adler32_finalize(65521) != 0 { ok = false; }
  if adler32_finalize(0 - 1) != 917518 { ok = false; }
  if adler32_update(38600999 + 4294967296, &abc) != adler32_update(38600999, &abc) { ok = false; }
  if adler32_update(0 - 1, &abc) != adler32_update(917518, &abc) { ok = false; }
  if adler32_update(adler32(&abc), &e) != adler32(&abc) { ok = false; }
  return assert(ok, "unchecked update/finalize canonicalize any Int: low 32 bits, then each component modulo 65521");
}

fn t16() -> TestResult {
  let abc = bytes_of("abc");
  let okr = adler32_update_checked(adler32_init(), &abc);
  var ok = false;
  if okr.is_ok {
    ok = okr.value == 38600999;
  }
  let s = adler32(abc);
  let cont = adler32_update_checked(s, &abc);
  if cont.is_ok {
    if cont.value != adler32_update(s, &abc) { ok = false; }
  } else {
    ok = false;
  }
  let maxst = adler32_update_checked(4293984240, &abc);
  if !maxst.is_ok { ok = false; }
  let zero = adler32_update_checked(0, &abc);
  if !zero.is_ok { ok = false; }
  let bad1 = adler32_update_checked(65521, &abc);
  if !err_int_is(bad1, "adler32: invalid state") { ok = false; }
  let bad2 = adler32_update_checked(0 - 1, &abc);
  if !err_int_is(bad2, "adler32: invalid state") { ok = false; }
  let bad3 = adler32_update_checked(4293984241, &abc);
  if !err_int_is(bad3, "adler32: invalid state") { ok = false; }
  let bad4 = adler32_update_checked(4294967296, &abc);
  if !err_int_is(bad4, "adler32: invalid state") { ok = false; }
  return assert(ok, "checked update: Ok equal to the unchecked result for canonical states, pinned Err otherwise");
}

fn t17() -> TestResult {
  let r = adler32_finalize_checked(38600999);
  var ok = false;
  if r.is_ok {
    ok = r.value == 38600999;
  }
  let bad1 = adler32_finalize_checked(65521);
  if !err_int_is(bad1, "adler32: invalid state") { ok = false; }
  let bad2 = adler32_finalize_checked(4294901760);
  if !err_int_is(bad2, "adler32: invalid state") { ok = false; }
  let bad3 = adler32_finalize_checked(0 - 5);
  if !err_int_is(bad3, "adler32: invalid state") { ok = false; }
  let good = adler32_finalize_checked(1);
  if !good.is_ok { ok = false; }
  return assert(ok, "checked finalize: identity Ok on canonical states, pinned Err otherwise");
}

fn t18() -> TestResult {
  let abc = bytes_of("abc");
  var ok = str_eq(adler32_hex(0), "00000000");
  if !str_eq(adler32_hex(1), "00000001") { ok = false; }
  if !str_eq(adler32_hex(6422626), "00620062") { ok = false; }
  if !str_eq(adler32_hex(38600999), "024d0127") { ok = false; }
  if !str_eq(adler32_hex(300286872), "11e60398") { ok = false; }
  if !str_eq(adler32_hex(3874088006), "e6e9e446") { ok = false; }
  if !str_eq(adler32_hex(4293984240), "fff0fff0") { ok = false; }
  if !str_eq(adler32_hex(0 - 1), "ffffffff") { ok = false; }
  if !str_eq(adler32_hex(4294967296), "00000000") { ok = false; }
  if !str_eq(adler32_hex(adler32(&abc)), "024d0127") { ok = false; }
  return assert(ok, "hex helper renders 8 lowercase unsigned digits, reduced modulo 2^32");
}

fn t19() -> TestResult {
  var e = Vec[UInt8].new();
  let a = bytes_of("a");
  let abc = bytes_of("abc");
  let wiki = bytes_of("Wikipedia");
  let abcdef = bytes_of("abcdef");
  let abcdefgh = bytes_of("abcdefgh");
  let digits = bytes_of("123456789");
  let hw = bytes_of("Hello, world!");
  let hb = high_bytes();
  let f1000 = repeat_byte(255, 1000);
  let r300 = ramp(300);
  let r1000 = ramp(1000);
  let r5552 = ramp(5552);
  let r5553 = ramp(5553);
  let r6000 = ramp(6000);
  let f6000 = repeat_byte(255, 6000);
  let z6000 = repeat_byte(0, 6000);
  var ok = refs_agree(&e);
  if !refs_agree(&a) { ok = false; }
  if !refs_agree(&abc) { ok = false; }
  if !refs_agree(&wiki) { ok = false; }
  if !refs_agree(&abcdef) { ok = false; }
  if !refs_agree(&abcdefgh) { ok = false; }
  if !refs_agree(&digits) { ok = false; }
  if !refs_agree(&hw) { ok = false; }
  if !refs_agree(&hb) { ok = false; }
  if !refs_agree(&f1000) { ok = false; }
  if !refs_agree(&r300) { ok = false; }
  if !refs_agree(&r1000) { ok = false; }
  if !refs_agree(&r5552) { ok = false; }
  if !refs_agree(&r5553) { ok = false; }
  if !refs_agree(&r6000) { ok = false; }
  if !refs_agree(&f6000) { ok = false; }
  if !refs_agree(&z6000) { ok = false; }
  return assert(ok, "per-byte and fully deferred test-local references agree with the module on every pinned buffer, including >5552-byte inputs");
}

fn t20() -> TestResult {
  let p = ramp(6000);
  let q = ramp(6000);
  let abc = bytes_of("abc");
  let abd = bytes_of("abd");
  var e = Vec[UInt8].new();
  var ok = adler32(&p) == adler32(&p);
  if adler32(&p) != adler32(&q) { ok = false; }
  if adler32(&abc) == adler32(&abd) { ok = false; }
  if adler32(&abc) != 38600999 { ok = false; }
  if adler32(&abd) != 38666536 { ok = false; }
  if adler32_update(adler32_init(), &e) != adler32_init() { ok = false; }
  if adler32_update(adler32(&abc), &e) != adler32(&abc) { ok = false; }
  return assert(ok, "checksums are deterministic and separate different inputs; empty update is the identity");
}

fn t21() -> TestResult {
  let p = ramp(6000);
  var s = adler32_init();
  var i = 0;
  while i < p.len() {
    var to = i + 5552;
    if to > p.len() {
      to = p.len();
    }
    let part = chunk(&p, i, to);
    s = adler32_update(s, &part);
    i = to;
  }
  var ok = adler32_finalize(s) == adler32(&p);
  let abc = bytes_of("abc");
  let one = adler32_update(adler32_init(), &abc);
  if adler32_finalize(one) != adler32(&abc) { ok = false; }
  if one != 38600999 { ok = false; }
  return assert(ok, "one-shot equals finalize(update(init, data)); 5552-byte chunked stream over the 6000-byte ramp round-trips");
}

fn t22() -> TestResult {
  let abc = bytes_of("abc");
  let r1 = adler32_update_checked(65521, &abc);
  let r2 = adler32_update_checked(65521, &abc);
  var ok = err_int_is(r1, "adler32: invalid state");
  if !err_int_is(r2, "adler32: invalid state") { ok = false; }
  if r1.is_ok || r2.is_ok { ok = false; }
  let f1 = adler32_finalize_checked(4293984241);
  if !err_int_is(f1, "adler32: invalid state") { ok = false; }
  let u1 = adler32_update_checked(4294967296, &abc);
  if !err_int_is(u1, "adler32: invalid state") { ok = false; }
  let v1 = adler32_finalize_checked(4294967295);
  if !err_int_is(v1, "adler32: invalid state") { ok = false; }
  let good = adler32_update_checked(1, &abc);
  if !good.is_ok { ok = false; }
  return assert(ok, "the single error message \"adler32: invalid state\" is deterministic and shared by every rejection path");
}

fn main() -> Int {
  io.println("=== xiom.adler32 conformance tests ===");
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
    io.println("xiom.adler32: all tests passed");
  } else {
    io.println("xiom.adler32: tests failed");
  }
  return failed;
}
