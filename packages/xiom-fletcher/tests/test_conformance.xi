// XIOM -- xiom.fletcher conformance tests (22 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Every expected checksum below was computed with independent reference
// implementations of the classic ones'-complement Fletcher checksum (two
// Python implementations -- per-byte reduction and fully deferred reduction
// -- agreeing on every vector), and the suite additionally re-derives the
// per-byte cadence with a test-local deferred reference (ref16/ref32).
//
// Canonical vectors pinned: "", "a", "abc", "abcdef", "abcdefgh",
// "123456789", "Hello, world!", the high-bit bytes ff 00 80 7f 01, the
// 300-byte and 1000-byte ramps (byte k = k % 256) and 1000 x 0xFF. The
// 300-byte ramp is the >= 255-byte wrap case (sum1 crosses the 255 modulus
// many times); the 1000-byte ramp and 1000 x 0xFF cross the 65535 modulus
// of Fletcher-32.
//
// Err strings are compared with compare.str_compare (BUG 17 discipline: `==`
// on Str values read from a Vec lowers to a pointer comparison); no Str is
// ever read out of a Vec in this suite and no Str `==` is used at all.
// Test dispatch is direct tN() calls -- no Vec[fn] table.

module fletcher_tests
use xiom.io; use xiom.test;
use xiom.fletcher;
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

// `n` bytes, byte k = k % 256 (the xiom.crc / xiom.fnv / xiom.murmur3
// fixture). 300 bytes is the wrap case for the Fletcher-16 modulus; 1000
// bytes crosses the Fletcher-32 modulus several times.
fn ramp(n: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < n {
    v.push((i % 256) as UInt8);
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

// Test-local reference Fletcher-16 with fully deferred reduction (no `%`
// until the end), independent of the module's per-byte cadence.
fn ref16(data: &Vec[UInt8]) -> Int {
  var s1 = 0;
  var s2 = 0;
  var i = 0;
  while i < data.len() {
    s1 = s1 + ((data[i] as Int) & 255);
    s2 = s2 + s1;
    i = i + 1;
  }
  return (s2 % 255) * 256 + (s1 % 255);
}

// Test-local reference Fletcher-32 with fully deferred reduction.
fn ref32(data: &Vec[UInt8]) -> Int {
  var s1 = 0;
  var s2 = 0;
  var i = 0;
  while i < data.len() {
    s1 = s1 + ((data[i] as Int) & 255);
    s2 = s2 + s1;
    i = i + 1;
  }
  return (s2 % 65535) * 65536 + (s1 % 65535);
}

// True when the incremental API reproduces the one-shot checksum at every
// split point of `data` (both chunks may be empty).
fn splits_match16(data: &Vec[UInt8]) -> Bool {
  let expect = fletcher16(data);
  var split = 0;
  while split <= data.len() {
    let head = chunk(data, 0, split);
    let tail = chunk(data, split, data.len());
    var s = fletcher16_init();
    s = fletcher16_update(s, &head);
    s = fletcher16_update(s, &tail);
    if fletcher16_finalize(s) != expect {
      return false;
    }
    split = split + 1;
  }
  return true;
}

fn splits_match32(data: &Vec[UInt8]) -> Bool {
  let expect = fletcher32(data);
  var split = 0;
  while split <= data.len() {
    let head = chunk(data, 0, split);
    let tail = chunk(data, split, data.len());
    var s = fletcher32_init();
    s = fletcher32_update(s, &head);
    s = fletcher32_update(s, &tail);
    if fletcher32_finalize(s) != expect {
      return false;
    }
    split = split + 1;
  }
  return true;
}

// True when feeding `data` in fixed `step`-byte chunks (last chunk short)
// reproduces the one-shot checksum.
fn stride_match16(data: &Vec[UInt8], step: Int) -> Bool {
  let expect = fletcher16(data);
  var s = fletcher16_init();
  var i = 0;
  while i < data.len() {
    var to = i + step;
    if to > data.len() {
      to = data.len();
    }
    let part = chunk(data, i, to);
    s = fletcher16_update(s, &part);
    i = to;
  }
  return fletcher16_finalize(s) == expect;
}

fn stride_match32(data: &Vec[UInt8], step: Int) -> Bool {
  let expect = fletcher32(data);
  var s = fletcher32_init();
  var i = 0;
  while i < data.len() {
    var to = i + step;
    if to > data.len() {
      to = data.len();
    }
    let part = chunk(data, i, to);
    s = fletcher32_update(s, &part);
    i = to;
  }
  return fletcher32_finalize(s) == expect;
}

fn t1() -> TestResult {
  var e = Vec[UInt8].new();
  var ok = fletcher16_init() == 0;
  if fletcher32_init() != 0 { ok = false; }
  if fletcher16(&e) != 0 { ok = false; }
  if fletcher32(&e) != 0 { ok = false; }
  if fletcher16_update(0, &e) != 0 { ok = false; }
  if fletcher32_update(0, &e) != 0 { ok = false; }
  if fletcher16_finalize(fletcher16_init()) != 0 { ok = false; }
  if fletcher32_finalize(fletcher32_init()) != 0 { ok = false; }
  return assert(ok, "init state is 0 and one-shot/update/finalize of empty input is 0 for both widths");
}

fn t2() -> TestResult {
  var e = Vec[UInt8].new();
  let a = bytes_of("a");
  let abc = bytes_of("abc");
  let abcdef = bytes_of("abcdef");
  let abcdefgh = bytes_of("abcdefgh");
  var ok = fletcher16(&e) == 0;
  if fletcher16(&a) != 24929 { ok = false; }
  if fletcher16(&abc) != 19495 { ok = false; }
  if fletcher16(&abcdef) != 8279 { ok = false; }
  if fletcher16(&abcdefgh) != 1575 { ok = false; }
  return assert(ok, "Fletcher-16 canonical vectors: empty 0x0000, a 0x6161, abc 0x4C27, abcdef 0x2057, abcdefgh 0x0627");
}

fn t3() -> TestResult {
  var e = Vec[UInt8].new();
  let a = bytes_of("a");
  let abc = bytes_of("abc");
  let abcdef = bytes_of("abcdef");
  let abcdefgh = bytes_of("abcdefgh");
  var ok = fletcher32(&e) == 0;
  if fletcher32(&a) != 6357089 { ok = false; }
  if fletcher32(&abc) != 38404390 { ok = false; }
  if fletcher32(&abcdef) != 135791189 { ok = false; }
  if fletcher32(&abcdefgh) != 234357540 { ok = false; }
  return assert(ok, "Fletcher-32 canonical vectors: empty 0x00000000, a 0x00610061, abc 0x024A0126, abcdef 0x08180255, abcdefgh 0x0DF80324");
}

fn t4() -> TestResult {
  let d = bytes_of("123456789");
  let hw = bytes_of("Hello, world!");
  var ok = fletcher16(&d) == 7902;
  if fletcher32(&d) != 152371677 { ok = false; }
  if fletcher16(&hw) != 29069 { ok = false; }
  if fletcher32(&hw) != 542180489 { ok = false; }
  return assert(ok, "123456789 (0x1EDE / 0x091501DD) and Hello, world! (0x718D / 0x20510489) pinned for both widths");
}

fn t5() -> TestResult {
  let hb = high_bytes();
  var ok = fletcher16(&hb) == 33025;
  if fletcher32(&hb) != 125436415 { ok = false; }
  return assert(ok, "high-bit bytes ff 00 80 7f 01 pinned: Fletcher-16 0x8101, Fletcher-32 0x077A01FF");
}

fn t6() -> TestResult {
  let p = ramp(300);
  var ok = fletcher16(&p) == 64181;
  if fletcher32(&p) != 3425600306 { ok = false; }
  return assert(ok, "300-byte ramp (wrap case, sum1 crosses 255 many times) pinned: 0xFAB5 / 0xCC2E8332");
}

fn t7() -> TestResult {
  let p = ramp(1000);
  let ff = repeat_byte(255, 1000);
  var ok = fletcher16(&p) == 25877;
  if fletcher32(&p) != 3900499757 { ok = false; }
  if fletcher16(&ff) != 0 { ok = false; }
  if fletcher32(&ff) != 2022171675 { ok = false; }
  return assert(ok, "deep-wrap vectors: 1000-byte ramp 0x6515 / 0xE87CE72D, 1000 x 0xFF 0x0000 / 0x7887E41B");
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
  var ok = fletcher16(&p0) == 0;
  if fletcher16(&p1) != 24929 { ok = false; }
  if fletcher16(&p2) != 9667 { ok = false; }
  if fletcher16(&p3) != 19495 { ok = false; }
  if fletcher16(&p4) != 55179 { ok = false; }
  if fletcher16(&p5) != 51440 { ok = false; }
  if fletcher16(&p6) != 8279 { ok = false; }
  if fletcher16(&p7) != 57022 { ok = false; }
  if fletcher16(&p8) != 1575 { ok = false; }
  if fletcher32(&p0) != 0 { ok = false; }
  if fletcher32(&p1) != 6357089 { ok = false; }
  if fletcher32(&p2) != 19136707 { ok = false; }
  if fletcher32(&p3) != 38404390 { ok = false; }
  if fletcher32(&p4) != 64225674 { ok = false; }
  if fletcher32(&p5) != 96666095 { ok = false; }
  if fletcher32(&p6) != 135791189 { ok = false; }
  if fletcher32(&p7) != 181666492 { ok = false; }
  if fletcher32(&p8) != 234357540 { ok = false; }
  return assert(ok, "all prefixes of \"abcdefgh\" pinned for lengths 0..8, both widths");
}

fn t9() -> TestResult {
  let full = bytes_of("abcdefgh");
  var ok = splits_match16(&full);
  if !splits_match32(&full) { ok = false; }
  return assert(ok, "incremental equals one-shot at every split of \"abcdefgh\", both widths");
}

fn t10() -> TestResult {
  let full = bytes_of("abcdef");
  var ok = splits_match16(&full);
  if !splits_match32(&full) { ok = false; }
  return assert(ok, "incremental equals one-shot at every split of \"abcdef\", both widths");
}

fn t11() -> TestResult {
  let p = ramp(300);
  var ok = stride_match16(&p, 1);
  if !stride_match32(&p, 1) { ok = false; }
  return assert(ok, "byte-at-a-time streaming over the 300-byte ramp equals one-shot, both widths");
}

fn t12() -> TestResult {
  let d = bytes_of("The quick brown fox jumps over the lazy dog");
  var ok = true;
  var step = 1;
  while step <= 7 {
    if !stride_match16(&d, step) { ok = false; }
    if !stride_match32(&d, step) { ok = false; }
    step = step + 1;
  }
  return assert(ok, "chunked streaming with step 1..7 equals one-shot for a 43-byte message, both widths");
}

fn t13() -> TestResult {
  let p = ramp(300);
  let s16 = fletcher16_update(fletcher16_init(), &p);
  var ok = s16 <= 65278;
  if s16 % 256 > 254 { ok = false; }
  if s16 / 256 > 254 { ok = false; }
  if !fletcher16_state_valid(s16) { ok = false; }
  if fletcher16_finalize(s16) != s16 { ok = false; }
  if s16 != 64181 { ok = false; }
  let s32 = fletcher32_update(fletcher32_init(), &p);
  if s32 > 4294901758 { ok = false; }
  if s32 % 65536 > 65534 { ok = false; }
  if s32 / 65536 > 65534 { ok = false; }
  if !fletcher32_state_valid(s32) { ok = false; }
  if fletcher32_finalize(s32) != s32 { ok = false; }
  if s32 != 3425600306 { ok = false; }
  var e = Vec[UInt8].new();
  let z16 = fletcher16_update(fletcher16_init(), &e);
  if z16 % 256 != 0 { ok = false; }
  if z16 / 256 != 0 { ok = false; }
  return assert(ok, "update results are canonical: sum1/sum2 in [0,254] / [0,65534], state_valid true, finalize the identity");
}

fn t14() -> TestResult {
  var ok = fletcher16_state_valid(0);
  if !fletcher16_state_valid(254) { ok = false; }
  if !fletcher16_state_valid(65278) { ok = false; }
  if fletcher16_state_valid(255) { ok = false; }
  if fletcher16_state_valid(511) { ok = false; }
  if fletcher16_state_valid(65279) { ok = false; }
  if fletcher16_state_valid(65280) { ok = false; }
  if fletcher16_state_valid(65535) { ok = false; }
  if fletcher16_state_valid(0 - 1) { ok = false; }
  if !fletcher32_state_valid(0) { ok = false; }
  if !fletcher32_state_valid(65534) { ok = false; }
  if !fletcher32_state_valid(4294901758) { ok = false; }
  if fletcher32_state_valid(65535) { ok = false; }
  if fletcher32_state_valid(4294901759) { ok = false; }
  if fletcher32_state_valid(4294967295) { ok = false; }
  if fletcher32_state_valid(4294967296) { ok = false; }
  if fletcher32_state_valid(0 - 1) { ok = false; }
  return assert(ok, "state_valid boundaries: [0,254]/[0,65278] and [0,65534]/[0,4294901758] accepted, wrap values rejected");
}

fn t15() -> TestResult {
  let a = bytes_of("a");
  let abc = bytes_of("abc");
  var e = Vec[UInt8].new();
  var ok = fletcher16_update(0 - 1, &e) == 0;
  if fletcher16_update(65535, &e) != 0 { ok = false; }
  if fletcher16_update(255, &e) != 0 { ok = false; }
  if fletcher16_update(4294901761, &e) != 1 { ok = false; }
  if fletcher16_update(511, &e) != 256 { ok = false; }
  if fletcher16_update(65278, &e) != 65278 { ok = false; }
  if fletcher16_update(0 - 1, &a) != 24929 { ok = false; }
  if fletcher16_update(24929 + 65536, &abc) != fletcher16_update(24929, &abc) { ok = false; }
  if fletcher16_finalize(65535) != 0 { ok = false; }
  if fletcher32_update(4294967295, &e) != 0 { ok = false; }
  if fletcher32_update(65535, &e) != 0 { ok = false; }
  if fletcher32_update(4294901759, &e) != 4294836224 { ok = false; }
  if fletcher32_update(131071, &e) != 65536 { ok = false; }
  if fletcher32_update(0 - 1, &a) != 6357089 { ok = false; }
  if fletcher32_update(6357089 + 4294967296, &abc) != fletcher32_update(6357089, &abc) { ok = false; }
  if fletcher32_finalize(4294967295) != 0 { ok = false; }
  return assert(ok, "unchecked update/finalize canonicalize any Int: low 16/32 bits, then each component modulo 255/65535");
}

fn t16() -> TestResult {
  let a = bytes_of("a");
  let abc = bytes_of("abc");
  let okr = fletcher16_update_checked(fletcher16_init(), &abc);
  var ok = false;
  if okr.is_ok {
    ok = okr.value == 19495;
  }
  let s16 = fletcher16(&a);
  let cont = fletcher16_update_checked(s16, &abc);
  if cont.is_ok {
    if cont.value != fletcher16_update(s16, &abc) { ok = false; }
  } else {
    ok = false;
  }
  let maxst = fletcher16_update_checked(65278, &abc);
  if !maxst.is_ok { ok = false; }
  let bad1 = fletcher16_update_checked(255, &abc);
  if !err_int_is(bad1, "fletcher: invalid state") { ok = false; }
  let bad2 = fletcher16_update_checked(0 - 1, &abc);
  if !err_int_is(bad2, "fletcher: invalid state") { ok = false; }
  let bad3 = fletcher16_update_checked(65280, &abc);
  if !err_int_is(bad3, "fletcher: invalid state") { ok = false; }
  let ok32 = fletcher32_update_checked(fletcher32_init(), &abc);
  var ok32v = false;
  if ok32.is_ok {
    ok32v = ok32.value == 38404390;
  }
  if !ok32v { ok = false; }
  let bad32 = fletcher32_update_checked(65535, &abc);
  if !err_int_is(bad32, "fletcher: invalid state") { ok = false; }
  let bad32b = fletcher32_update_checked(4294967296, &abc);
  if !err_int_is(bad32b, "fletcher: invalid state") { ok = false; }
  let max32 = fletcher32_update_checked(4294901758, &abc);
  if !max32.is_ok { ok = false; }
  return assert(ok, "checked update: Ok equal to the unchecked result for canonical states, pinned Err otherwise");
}

fn t17() -> TestResult {
  let r16 = fletcher16_finalize_checked(24929);
  var ok = false;
  if r16.is_ok {
    ok = r16.value == 24929;
  }
  let bad16 = fletcher16_finalize_checked(255);
  if !err_int_is(bad16, "fletcher: invalid state") { ok = false; }
  let bad16b = fletcher16_finalize_checked(65535);
  if !err_int_is(bad16b, "fletcher: invalid state") { ok = false; }
  let r32 = fletcher32_finalize_checked(6357089);
  var ok32 = false;
  if r32.is_ok {
    ok32 = r32.value == 6357089;
  }
  if !ok32 { ok = false; }
  let bad32 = fletcher32_finalize_checked(65535);
  if !err_int_is(bad32, "fletcher: invalid state") { ok = false; }
  let bad32b = fletcher32_finalize_checked(0 - 5);
  if !err_int_is(bad32b, "fletcher: invalid state") { ok = false; }
  return assert(ok, "checked finalize: identity Ok on canonical states, pinned Err otherwise, both widths");
}

fn t18() -> TestResult {
  let abc = bytes_of("abc");
  var ok = str_eq(fletcher16_hex(0), "0000");
  if !str_eq(fletcher16_hex(19495), "4c27") { ok = false; }
  if !str_eq(fletcher16_hex(65278), "fefe") { ok = false; }
  if !str_eq(fletcher16_hex(0 - 1), "ffff") { ok = false; }
  if !str_eq(fletcher16_hex(65536), "0000") { ok = false; }
  if !str_eq(fletcher16_hex(33025), "8101") { ok = false; }
  if !str_eq(fletcher16_hex(fletcher16(&abc)), "4c27") { ok = false; }
  if !str_eq(fletcher32_hex(0), "00000000") { ok = false; }
  if !str_eq(fletcher32_hex(38404390), "024a0126") { ok = false; }
  if !str_eq(fletcher32_hex(4294901758), "fffefffe") { ok = false; }
  if !str_eq(fletcher32_hex(0 - 1), "ffffffff") { ok = false; }
  if !str_eq(fletcher32_hex(4294967296), "00000000") { ok = false; }
  if !str_eq(fletcher32_hex(3425600306), "cc2e8332") { ok = false; }
  if !str_eq(fletcher32_hex(fletcher32(&abc)), "024a0126") { ok = false; }
  return assert(ok, "hex helpers render 4/8 lowercase unsigned digits, reduced modulo 2^16 / 2^32");
}

fn t19() -> TestResult {
  var e = Vec[UInt8].new();
  let a = bytes_of("a");
  let abc = bytes_of("abc");
  let abcdef = bytes_of("abcdef");
  let abcdefgh = bytes_of("abcdefgh");
  let n = bytes_of("123456789");
  let hb = high_bytes();
  let p300 = ramp(300);
  let p1000 = ramp(1000);
  var ok = ref16(&e) == fletcher16(&e);
  if ref32(&e) != fletcher32(&e) { ok = false; }
  if ref16(&a) != fletcher16(&a) { ok = false; }
  if ref32(&a) != fletcher32(&a) { ok = false; }
  if ref16(&abc) != fletcher16(&abc) { ok = false; }
  if ref32(&abc) != fletcher32(&abc) { ok = false; }
  if ref16(&abcdef) != fletcher16(&abcdef) { ok = false; }
  if ref32(&abcdef) != fletcher32(&abcdef) { ok = false; }
  if ref16(&abcdefgh) != fletcher16(&abcdefgh) { ok = false; }
  if ref32(&abcdefgh) != fletcher32(&abcdefgh) { ok = false; }
  if ref16(&n) != fletcher16(&n) { ok = false; }
  if ref32(&n) != fletcher32(&n) { ok = false; }
  if ref16(&hb) != fletcher16(&hb) { ok = false; }
  if ref32(&hb) != fletcher32(&hb) { ok = false; }
  if ref16(&p300) != fletcher16(&p300) { ok = false; }
  if ref32(&p300) != fletcher32(&p300) { ok = false; }
  if ref16(&p1000) != fletcher16(&p1000) { ok = false; }
  if ref32(&p1000) != fletcher32(&p1000) { ok = false; }
  return assert(ok, "test-local deferred-reduction reference agrees with the per-byte module on every pinned buffer, both widths");
}

fn t20() -> TestResult {
  let p = ramp(300);
  let q = ramp(300);
  var ok = fletcher16(&p) == fletcher16(&p);
  if fletcher16(&p) != fletcher16(&q) { ok = false; }
  if fletcher32(&p) != fletcher32(&q) { ok = false; }
  let abc = bytes_of("abc");
  let abd = bytes_of("abd");
  if fletcher16(&abc) == fletcher16(&abd) { ok = false; }
  if fletcher32(&abc) == fletcher32(&abd) { ok = false; }
  var other = Vec[UInt8].new();
  var i = 0;
  while i < 300 {
    other.push(((i + 1) % 256) as UInt8);
    i = i + 1;
  }
  if fletcher16(&other) == fletcher16(&p) { ok = false; }
  if fletcher32(&other) == fletcher32(&p) { ok = false; }
  var e = Vec[UInt8].new();
  if fletcher16_update(fletcher16_init(), &e) != fletcher16_init() { ok = false; }
  if fletcher32_update(fletcher32_init(), &e) != fletcher32_init() { ok = false; }
  return assert(ok, "checksums are deterministic and separate different inputs; empty update is the identity");
}

fn t21() -> TestResult {
  let p = ramp(300);
  var s16 = fletcher16_init();
  var s32 = fletcher32_init();
  var i = 0;
  while i < p.len() {
    var to = i + 7;
    if to > p.len() {
      to = p.len();
    }
    let part = chunk(&p, i, to);
    s16 = fletcher16_update(s16, &part);
    s32 = fletcher32_update(s32, &part);
    i = to;
  }
  var ok = fletcher16_finalize(s16) == fletcher16(&p);
  if fletcher32_finalize(s32) != fletcher32(&p) { ok = false; }
  if s16 != fletcher16_finalize(s16) { ok = false; }
  if s32 != fletcher32_finalize(s32) { ok = false; }
  let abc = bytes_of("abc");
  let one16 = fletcher16_update(fletcher16_init(), &abc);
  if fletcher16_finalize(one16) != fletcher16(&abc) { ok = false; }
  let one32 = fletcher32_update(fletcher32_init(), &abc);
  if fletcher32_finalize(one32) != fletcher32(&abc) { ok = false; }
  return assert(ok, "one-shot equals finalize(update(init, data)); 7-byte chunked stream over the 300-byte ramp round-trips");
}

fn t22() -> TestResult {
  let abc = bytes_of("abc");
  let r1 = fletcher16_update_checked(255, &abc);
  let r2 = fletcher16_update_checked(255, &abc);
  var ok = err_int_is(r1, "fletcher: invalid state");
  if !err_int_is(r2, "fletcher: invalid state") { ok = false; }
  if r1.is_ok || r2.is_ok { ok = false; }
  let f1 = fletcher16_finalize_checked(65280);
  if !err_int_is(f1, "fletcher: invalid state") { ok = false; }
  let u1 = fletcher32_update_checked(4294967295, &abc);
  let u2 = fletcher32_update_checked(4294967295, &abc);
  if !err_int_is(u1, "fletcher: invalid state") { ok = false; }
  if !err_int_is(u2, "fletcher: invalid state") { ok = false; }
  let v1 = fletcher32_finalize_checked(4294901759);
  if !err_int_is(v1, "fletcher: invalid state") { ok = false; }
  let good = fletcher16_finalize_checked(0);
  if !good.is_ok { ok = false; }
  return assert(ok, "the single error message \"fletcher: invalid state\" is deterministic and shared by every rejection path");
}

fn main() -> Int {
  io.println("=== xiom.fletcher conformance tests ===");
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
    io.println("xiom.fletcher: all tests passed");
  } else {
    io.println("xiom.fletcher: tests failed");
  }
  return failed;
}
