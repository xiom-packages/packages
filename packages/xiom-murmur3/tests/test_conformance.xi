// XIOM -- xiom.murmur3 conformance tests (18 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Every expected digest below was computed with two independent reference
// implementations of the published MurmurHash3 x86_32 algorithm -- a
// BigInteger/struct-based Python port and a Math.imul/shift-based Node.js
// port -- and the two agree on all of them. The boundary cases pin the
// canonical smhasher values: the short-key digests for seed 0 and the
// smhasher VerificationTest value 0xB0F57EE3 (2968878819) for the
// 256-prefix key schedule (prefix {0..i-1} hashed with seed 256 - i, the
// 1024 little-endian digest bytes hashed with seed 0).
//
// Str comparisons in this suite only ever compare murmur3_x86_32_hex()
// results with string literals (the xiom.hello pattern); no Str is ever
// read out of a Vec, so BUG 17 is unreachable. Mutable state is always
// passed with an explicit `&mut` at the call site, and test dispatch is
// direct tN() calls -- no Vec[fn] table.

module murmur3_tests
use xiom.io; use xiom.test;
use xiom.murmur3;
use xiom.string;

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
// their own buffers; see the &struct.field trap).
fn chunk(d: &Vec[UInt8], from: Int, to: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = from;
  while i < to {
    v.push(d[i]);
    i = i + 1;
  }
  return v;
}

// ff 00 80 7f 01: exercises byte widening for values with bit 7 set.
fn high_bytes() -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  v.push(255);
  v.push(0);
  v.push(128);
  v.push(127);
  v.push(1);
  return v;
}

// 300 bytes, byte k = k % 256 (the xiom.crc/xiom.fnv fixture).
fn pattern_300() -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < 300 {
    v.push((i % 256) as UInt8);
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

// The byte ramp 0x00..0xFF (the smhasher verification key material).
fn ramp_256() -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < 256 {
    v.push(i as UInt8);
    i = i + 1;
  }
  return v;
}

// One-shot digest of `data`, fed to the streaming API in fixed `step`
// chunks; -1 when a streaming call reports an error (never expected).
fn stride_match(data: &Vec[UInt8], seed: Int, step: Int) -> Int {
  let expect = murmur3_x86_32(data, seed);
  var s = murmur3_x86_32_init(seed);
  var i = 0;
  while i < data.len() {
    var to = i + step;
    if to > data.len() {
      to = data.len();
    }
    let part = chunk(data, i, to);
    let r = murmur3_x86_32_update(&mut s, &part);
    if !r.is_ok {
      return 0 - 1;
    }
    i = to;
  }
  let f = murmur3_x86_32_finalize(&s);
  if !f.is_ok {
    return 0 - 1;
  }
  if f.value == expect {
    return 1;
  }
  return 0;
}

// True when the streaming API reproduces the one-shot digest at every
// split point of `data` (both chunks may be empty).
fn splits_match(data: &Vec[UInt8], seed: Int) -> Bool {
  let expect = murmur3_x86_32(data, seed);
  var split = 0;
  while split <= data.len() {
    let head = chunk(data, 0, split);
    let tail = chunk(data, split, data.len());
    var s = murmur3_x86_32_init(seed);
    let r1 = murmur3_x86_32_update(&mut s, &head);
    let r2 = murmur3_x86_32_update(&mut s, &tail);
    if !r1.is_ok {
      return false;
    }
    if !r2.is_ok {
      return false;
    }
    let f = murmur3_x86_32_finalize(&s);
    if !f.is_ok {
      return false;
    }
    if f.value != expect {
      return false;
    }
    split = split + 1;
  }
  return true;
}

// True when the streaming tail of `s` is exactly the three bytes
// b0, b1, b2 (in stream order).
fn tail_is(s: &Murmur3State, b0: Int, b1: Int, b2: Int) -> Bool {
  let t = murmur3_x86_32_state_tail(s);
  if t.len() != 3 {
    return false;
  }
  if ((t[0] as Int) & 255) != b0 {
    return false;
  }
  if ((t[1] as Int) & 255) != b1 {
    return false;
  }
  if ((t[2] as Int) & 255) != b2 {
    return false;
  }
  return true;
}

// Forged state for the error-path checks: kind 1 = negative h1,
// 2 = h1 >= 2^32, 3 = negative length, 4 = four buffered tail bytes.
fn make_bad_state(kind: Int) -> Murmur3State {
  if kind == 1 {
    return Murmur3State{ h1: 0 - 1; length: 0; tail: Vec[UInt8].new() };
  }
  if kind == 2 {
    return Murmur3State{ h1: 4294967296; length: 0; tail: Vec[UInt8].new() };
  }
  if kind == 3 {
    return Murmur3State{ h1: 0; length: 0 - 5; tail: Vec[UInt8].new() };
  }
  var t = Vec[UInt8].new();
  t.push(1u8);
  t.push(2u8);
  t.push(3u8);
  t.push(4u8);
  return Murmur3State{ h1: 0; length: 4; tail: t };
}

fn t1() -> TestResult {
  var ok = murmur3_x86_32_c1() == 3432918353;
  if murmur3_x86_32_c2() != 461845907 { ok = false; }
  if murmur3_x86_32_fmix_c1() != 2246822507 { ok = false; }
  if murmur3_x86_32_fmix_c2() != 3266489909 { ok = false; }
  if murmur3_x86_32_default_seed() != 0 { ok = false; }
  if murmur3_x86_32_smhasher_seed() != 256 { ok = false; }
  if murmur3_x86_32_smhasher_value() != 2968878819 { ok = false; }
  return assert(ok, "specification constants 0xCC9E2D51/0x1B873593/0x85EBCA6B/0xC2B2AE35, seeds 0 and 256, smhasher value 0xB0F57EE3");
}

fn t2() -> TestResult {
  var ok = murmur3_x86_32_rotl32(0, 0) == 0;
  if murmur3_x86_32_rotl32(1, 0) != 1 { ok = false; }
  if murmur3_x86_32_rotl32(2147483648, 1) != 1 { ok = false; }
  if murmur3_x86_32_rotl32(1, 31) != 2147483648 { ok = false; }
  if murmur3_x86_32_rotl32(4294967295, 16) != 4294967295 { ok = false; }
  if murmur3_x86_32_rotl32(305419896, 16) != 1450709556 { ok = false; }
  if murmur3_x86_32_rotl32(3735928559, 15) != 3749179222 { ok = false; }
  if murmur3_x86_32_rotl32(3735928559, 13) != 3084778453 { ok = false; }
  if murmur3_x86_32_rotl32(0, 17) != 0 { ok = false; }
  if murmur3_x86_32_rotl32(0 - 1, 1) != 4294967295 { ok = false; }
  if murmur3_x86_32_rotl32(1, 32 + 31) != 2147483648 { ok = false; }
  if murmur3_x86_32_rotl32(1, 0 - 31) != 2 { ok = false; }
  return assert(ok, "rotl32 arithmetic scheme pinned (bit-31 operands, r = 0/1/13/15/16/31, r modulo 32, negative inputs)");
}

fn t3() -> TestResult {
  var e = Vec[UInt8].new();
  let a = bytes_of("a");
  let abc = bytes_of("abc");
  let hw = bytes_of("Hello, world!");
  var ok = murmur3_x86_32(&e, 0) == 0;
  if murmur3_x86_32(&a, 0) != 1009084850 { ok = false; }
  if murmur3_x86_32(&abc, 0) != 3017643002 { ok = false; }
  if murmur3_x86_32(&hw, 0) != 3224780355 { ok = false; }
  return assert(ok, "canonical seed-0 vectors: empty 0x00000000, a 0x3C2569B2, abc 0xB3DD93FA, Hello, world! 0xC0363E43");
}

fn t4() -> TestResult {
  var e = Vec[UInt8].new();
  let abc = bytes_of("abc");
  let hw = bytes_of("Hello, world!");
  var ok = murmur3_x86_32(&abc, 1) == 2859854335;
  if murmur3_x86_32(&abc, 0 - 1) != 4236296879 { ok = false; }
  if murmur3_x86_32(&abc, 2538058380) != 3360318173 { ok = false; }
  if murmur3_x86_32(&hw, 1) != 2858272859 { ok = false; }
  if murmur3_x86_32(&e, 1) != 1364076727 { ok = false; }
  return assert(ok, "nonzero-seed vectors: abc at seeds 1/0x9747B28C/0xFFFFFFFF, Hello, world! at seed 1, empty at seed 1");
}

fn t5() -> TestResult {
  let full = bytes_of("abcdefgh");
  let p0 = chunk(&full, 0, 0);
  let p1 = chunk(&full, 0, 1);
  let p2 = chunk(&full, 0, 2);
  let p3 = chunk(&full, 0, 3);
  let p4 = chunk(&full, 0, 4);
  let p5 = chunk(&full, 0, 5);
  let p6 = chunk(&full, 0, 6);
  let p7 = chunk(&full, 0, 7);
  var ok = murmur3_x86_32(&p0, 0) == 0;
  if murmur3_x86_32(&p1, 0) != 1009084850 { ok = false; }
  if murmur3_x86_32(&p2, 0) != 2613040991 { ok = false; }
  if murmur3_x86_32(&p3, 0) != 3017643002 { ok = false; }
  if murmur3_x86_32(&p4, 0) != 1139631978 { ok = false; }
  if murmur3_x86_32(&p5, 0) != 3902511862 { ok = false; }
  if murmur3_x86_32(&p6, 0) != 1635893381 { ok = false; }
  if murmur3_x86_32(&p7, 0) != 2285673222 { ok = false; }
  if murmur3_x86_32(&full, 0) != 1239272644 { ok = false; }
  return assert(ok, "all lengths 0..8 of \"abcdefgh\" pinned (tail sizes 0..3 and complete blocks)");
}

fn t6() -> TestResult {
  let hb = high_bytes();
  let a = bytes_of("a");
  var ok = murmur3_x86_32(&hb, 0) == 2205632464;
  if murmur3_x86_32(&hb, 0 - 1) != 1130567226 { ok = false; }
  if murmur3_x86_32(&a, 0 - 1) != 711476519 { ok = false; }
  return assert(ok, "high-bit bytes ff 00 80 7f 01 pinned at seed 0 and seed 0xFFFFFFFF; \"a\" at 0xFFFFFFFF");
}

fn t7() -> TestResult {
  let p = pattern_300();
  var ok = murmur3_x86_32(&p, 0) == 1707895027;
  if murmur3_x86_32(&p, 1) != 2227354444 { ok = false; }
  if murmur3_x86_32(&p, 123456789) != 2624066624 { ok = false; }
  if murmur3_x86_32(&p, 0 - 1) != 1269644128 { ok = false; }
  let q = bytes_of("The quick brown fox jumps over the lazy dog");
  if murmur3_x86_32(&q, 0) != 776992547 { ok = false; }
  if murmur3_x86_32(&q, 123456789) != 1863259233 { ok = false; }
  let ff = repeat_byte(255, 1000);
  if murmur3_x86_32(&ff, 0) != 2640418211 { ok = false; }
  return assert(ok, "long inputs: 300-byte ramp at four seeds, 43-byte sentence at two seeds, 1000 x 0xFF");
}

fn t8() -> TestResult {
  let key = ramp_256();
  var hashes = Vec[UInt8].new();
  var i = 0;
  while i < 256 {
    let prefix = chunk(&key, 0, i);
    let d = murmur3_x86_32(&prefix, 256 - i);
    hashes.push((d % 256) as UInt8);
    hashes.push(((d / 256) % 256) as UInt8);
    hashes.push(((d / 65536) % 256) as UInt8);
    hashes.push(((d / 16777216) % 256) as UInt8);
    i = i + 1;
  }
  var ok = hashes.len() == 1024;
  if murmur3_x86_32(&hashes, 0) != 2968878819 { ok = false; }
  return assert(ok, "smhasher VerificationTest value 0xB0F57EE3 for the canonical 256-prefix key schedule");
}

fn t9() -> TestResult {
  let hw0 = bytes_of("Hello, world!");
  let hw1 = bytes_of("Hello, world!");
  var ok = splits_match(&hw0, 0);
  if !splits_match(&hw1, 1) { ok = false; }
  return assert(ok, "streaming at every split of \"Hello, world!\" equals one-shot at seed 0 and seed 1");
}

fn t10() -> TestResult {
  let d0 = bytes_of("abcdefgh");
  let d1 = bytes_of("abcdefgh");
  var ok = splits_match(&d0, 0);
  if !splits_match(&d1, 123456789) { ok = false; }
  return assert(ok, "streaming at every split of \"abcdefgh\" (block and tail boundaries) equals one-shot");
}

fn t11() -> TestResult {
  let p = pattern_300();
  var ok = stride_match(&p, 0, 1) == 1;
  return assert(ok, "byte-at-a-time streaming over the 300-byte ramp equals one-shot 0x65CC68F3");
}

fn t12() -> TestResult {
  let d = bytes_of("The quick brown fox jumps over the lazy dog");
  var ok = true;
  var step = 1;
  while step <= 7 {
    if stride_match(&d, 0, step) != 1 { ok = false; }
    step = step + 1;
  }
  if stride_match(&d, 1, 3) != 1 { ok = false; }
  if stride_match(&d, 123456789, 5) != 1 { ok = false; }
  return assert(ok, "streaming with chunk sizes 1..7 and mixed seeds equals one-shot for a 43-byte message");
}

fn t13() -> TestResult {
  // Readers run after the updates of each state so the advisory v0.61.3
  // borrow checker does not see an immutable borrow ahead of a `&mut`.
  var fresh = murmur3_x86_32_init(0);
  var ok = murmur3_x86_32_state_h1(&fresh) == 0;
  if murmur3_x86_32_state_length(&fresh) != 0 { ok = false; }
  if murmur3_x86_32_state_tail_len(&fresh) != 0 { ok = false; }
  if !murmur3_x86_32_state_is_valid(&fresh) { ok = false; }
  let three = bytes_of("abc");
  let four = bytes_of("defg");
  var s = murmur3_x86_32_init(0);
  let r1 = murmur3_x86_32_update(&mut s, &three);
  let r2 = murmur3_x86_32_update(&mut s, &four);
  if !r1.is_ok { ok = false; }
  if !r2.is_ok { ok = false; }
  if murmur3_x86_32_state_length(&s) != 7 { ok = false; }
  if murmur3_x86_32_state_tail_len(&s) != 3 { ok = false; }
  if !tail_is(&s, 101, 102, 103) { ok = false; }
  if !murmur3_x86_32_state_is_valid(&s) { ok = false; }
  var short = murmur3_x86_32_init(0);
  let r3 = murmur3_x86_32_update(&mut short, &three);
  if !r3.is_ok { ok = false; }
  if murmur3_x86_32_state_length(&short) != 3 { ok = false; }
  if murmur3_x86_32_state_tail_len(&short) != 3 { ok = false; }
  if !tail_is(&short, 97, 98, 99) { ok = false; }
  var s2 = murmur3_x86_32_init(0 - 1);
  if murmur3_x86_32_state_h1(&s2) != 4294967295 { ok = false; }
  var s3 = murmur3_x86_32_init(4294967301);
  if murmur3_x86_32_state_h1(&s3) != 5 { ok = false; }
  return assert(ok, "state accessors track h1/length/tail across updates; init reduces the seed modulo 2^32");
}

fn t14() -> TestResult {
  var e = Vec[UInt8].new();
  var s = murmur3_x86_32_init(0);
  let f0 = murmur3_x86_32_finalize(&s);
  var ok = f0.is_ok;
  if !f0.is_ok {
    ok = false;
  } elif f0.value != 0 {
    ok = false;
  }
  let r0 = murmur3_x86_32_update(&mut s, &e);
  if !r0.is_ok { ok = false; }
  let f1 = murmur3_x86_32_finalize(&s);
  if !f1.is_ok { ok = false; }
  if f1.value != 0 { ok = false; }
  let f2 = murmur3_x86_32_finalize(&s);
  if !f2.is_ok { ok = false; }
  if f2.value != f1.value { ok = false; }
  if murmur3_x86_32_state_length(&s) != 0 { ok = false; }
  var s2 = murmur3_x86_32_init(0);
  let a = bytes_of("Hello, ");
  let b = bytes_of("world!");
  let ra = murmur3_x86_32_update(&mut s2, &a);
  let re = murmur3_x86_32_update(&mut s2, &e);
  let rb = murmur3_x86_32_update(&mut s2, &b);
  if !ra.is_ok { ok = false; }
  if !re.is_ok { ok = false; }
  if !rb.is_ok { ok = false; }
  let f3 = murmur3_x86_32_finalize(&s2);
  if !f3.is_ok { ok = false; }
  if f3.value != 3224780355 { ok = false; }
  return assert(ok, "empty stream hashes to 0, empty updates are no-ops, finalize is repeatable and non-destructive");
}

fn t15() -> TestResult {
  let d = bytes_of("abc");
  var ok = true;
  var kind = 1;
  while kind <= 4 {
    var s = make_bad_state(kind);
    if murmur3_x86_32_state_is_valid(&s) { ok = false; }
    let ru = murmur3_x86_32_update(&mut s, &d);
    if ru.is_ok {
      ok = false;
    } elif str_compare(ru.error, "murmur3: invalid streaming state") != 0 {
      ok = false;
    }
    let rf = murmur3_x86_32_finalize(&s);
    if rf.is_ok {
      ok = false;
    } elif str_compare(rf.error, "murmur3: invalid streaming state") != 0 {
      ok = false;
    }
    kind = kind + 1;
  }
  var forged = make_bad_state(4);
  let rejected = murmur3_x86_32_update(&mut forged, &d);
  if rejected.is_ok { ok = false; }
  if murmur3_x86_32_state_tail_len(&forged) != 4 { ok = false; }
  if murmur3_x86_32_state_length(&forged) != 4 { ok = false; }
  var good = murmur3_x86_32_init(7);
  let rg = murmur3_x86_32_update(&mut good, &d);
  if !rg.is_ok { ok = false; }
  if !murmur3_x86_32_state_is_valid(&good) { ok = false; }
  return assert(ok, "invalid states rejected by update/finalize with the pinned Err message, state untouched, valid states stay valid");
}

fn t16() -> TestResult {
  let hw = bytes_of("Hello, world!");
  var ok = murmur3_x86_32_hex(0) == "00000000";
  if murmur3_x86_32_hex(4294967295) != "ffffffff" { ok = false; }
  if murmur3_x86_32_hex(0 - 1) != "ffffffff" { ok = false; }
  if murmur3_x86_32_hex(4294967301) != "00000005" { ok = false; }
  if murmur3_x86_32_hex(murmur3_x86_32(&hw, 0)) != "c0363e43" { ok = false; }
  if murmur3_x86_32_hex(murmur3_x86_32(&hw, 1)) != "aa5dc85b" { ok = false; }
  return assert(ok, "murmur3_x86_32_hex renders the low 32 bits as 8 unsigned hex digits");
}

fn t17() -> TestResult {
  let d = bytes_of("Hello, world!");
  let same = bytes_of("Hello, world!");
  let other = bytes_of("Hello, world?");
  var ok = murmur3_x86_32(&d, 0) == murmur3_x86_32(&d, 0);
  if murmur3_x86_32(&d, 0) != murmur3_x86_32(&same, 0) { ok = false; }
  if murmur3_x86_32(&d, 0) == murmur3_x86_32(&d, 1) { ok = false; }
  if murmur3_x86_32(&d, 0) == murmur3_x86_32(&other, 0) { ok = false; }
  let p = pattern_300();
  if murmur3_x86_32(&p, 5) != murmur3_x86_32(&p, 5) { ok = false; }
  return assert(ok, "hashing is deterministic, seed-sensitive and input-sensitive");
}

fn t18() -> TestResult {
  let d = bytes_of("abc");
  var ok = murmur3_x86_32(&d, 0 - 1) == murmur3_x86_32(&d, 4294967295);
  if murmur3_x86_32(&d, 4294967301) != murmur3_x86_32(&d, 5) { ok = false; }
  if murmur3_x86_32(&d, 0 - 4294967296) != murmur3_x86_32(&d, 0) { ok = false; }
  if murmur3_x86_32(&d, 0) != murmur3_x86_32(&d, murmur3_x86_32_default_seed()) { ok = false; }
  return assert(ok, "seed is reduced modulo 2^32: -1 == 0xFFFFFFFF, 2^32 + 5 == 5, -2^32 == 0, 0 == default_seed");
}

fn main() -> Int {
  io.println("=== xiom.murmur3 conformance tests ===");
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
    io.println("xiom.murmur3: all tests passed");
  } else {
    io.println("xiom.murmur3: tests failed");
  }
  return failed;
}
