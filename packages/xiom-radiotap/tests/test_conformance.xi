// XIOM -- xiom.radiotap conformance tests (19 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// The fixtures are assembled byte by byte (byte pushes), so the parser is
// exercised against bytes this test file controls. The canonical fixture is
// a 40-byte two-word radiotap header (word 0 chains to a zero word 1)
// carrying TSFT, FLAGS, RATE, CHANNEL, DBM_ANTSIGNAL, ANTENNA, FCS and
// XCHANNEL, followed by a 3-byte frame; alignment padding from the base
// header to TSFT and from FCS to XCHANNEL is exercised by both parsing and
// emit. A second fixture is the two-word header with an empty field pool.
// Error strings are compared through compare.str_compare (BUG 17
// discipline: `==` on a Str read from a Vec lowers to a pointer comparison).

module radiotap_tests
use xiom.io; use xiom.test;
use xiom.radiotap;
use xiom.string.compare;

// --------------------------------------------------
//  Helpers (independent of src/radiotap.xi)
// --------------------------------------------------

fn str_eq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn err_header_is(r: Result[RadiotapHeader, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_bytes_is(r: Result[Vec[UInt8], Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_int_is(r: Result[Int, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
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

fn bytes2(a: Int, b: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  v.push(a as UInt8);
  v.push(b as UInt8);
  return v;
}

fn bytes3(a: Int, b: Int, c: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  v.push(a as UInt8);
  v.push(b as UInt8);
  v.push(c as UInt8);
  return v;
}

fn iv1(a: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  return v;
}

fn iv2(a: Int, b: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  v.push(b);
  return v;
}

fn iv3(a: Int, b: Int, c: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  v.push(b);
  v.push(c);
  return v;
}

fn push_byte(v: &mut Vec[UInt8], b: Int) {
  v.push(b as UInt8);
}

fn push_le16(v: &mut Vec[UInt8], n: Int) {
  push_byte(v, n % 256);
  push_byte(v, (n / 256) % 256);
}

fn push_le32(v: &mut Vec[UInt8], n: Int) {
  push_byte(v, n % 256);
  push_byte(v, (n / 256) % 256);
  push_byte(v, (n / 65536) % 256);
  push_byte(v, (n / 16777216) % 256);
}

fn push_le64(v: &mut Vec[UInt8], n: Int) {
  push_byte(v, n % 256);
  push_byte(v, (n / 256) % 256);
  push_byte(v, (n / 65536) % 256);
  push_byte(v, (n / 16777216) % 256);
  push_byte(v, (n / 4294967296) % 256);
  push_byte(v, (n / 1099511627776) % 256);
  push_byte(v, (n / 281474976710656) % 256);
  push_byte(v, (n / 72057594037927936) % 256);
}

// A copy of `v` with byte `pos` replaced (fixtures for the error paths).
fn with_byte(v: Vec[UInt8], pos: Int, b: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < v.len() {
    if i == pos {
      out.push(b as UInt8);
    } else {
      out.push(v[i]);
    }
    i = i + 1;
  }
  return out;
}

// A copy of `v` with the little-endian length field (bytes 2..3) replaced.
fn with_len(v: Vec[UInt8], n: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < v.len() {
    if i == 2 {
      out.push((n % 256) as UInt8);
    } elif i == 3 {
      out.push(((n / 256) % 256) as UInt8);
    } else {
      out.push(v[i]);
    }
    i = i + 1;
  }
  return out;
}

fn prefix(v: Vec[UInt8], n: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < n && i < v.len() {
    out.push(v[i]);
    i = i + 1;
  }
  return out;
}

// Canonical 43-byte fixture: 40-byte two-word header plus a 3-byte frame
// AA BB CC. Word 0 = bits 0,1,2,3,5,11,14 + chain; word 1 = 0. Fields end
// at 40 after padding bytes at 12..15 (TSFT alignment) and 33..35
// (XCHANNEL alignment).
fn canonical_fixture() -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  push_byte(&mut v, 0);                  // version 0
  push_byte(&mut v, 0);                  // pad
  push_le16(&mut v, 40);                 // length
  push_le32(&mut v, 2148026415);         // present word 0 (0x8008482F)
  push_le32(&mut v, 0);                  // present word 1
  push_byte(&mut v, 0);                  // padding to TSFT (offset 16)
  push_byte(&mut v, 0);
  push_byte(&mut v, 0);
  push_byte(&mut v, 0);
  push_le64(&mut v, 72623859790382856);  // TSFT 0x0102030405060708
  push_byte(&mut v, 16);                 // FLAGS
  push_byte(&mut v, 108);                // RATE
  push_le16(&mut v, 2412);               // CHANNEL freq (MHz)
  push_le16(&mut v, 160);                // CHANNEL flags
  push_byte(&mut v, 214);                // DBM_ANTSIGNAL -42 (two's complement)
  push_byte(&mut v, 1);                  // ANTENNA
  push_byte(&mut v, 1);                  // FCS
  push_byte(&mut v, 0);                  // padding to XCHANNEL (offset 36)
  push_byte(&mut v, 0);
  push_byte(&mut v, 0);
  push_le32(&mut v, 7);                  // XCHANNEL
  push_byte(&mut v, 170);                // frame AA
  push_byte(&mut v, 187);                // frame BB
  push_byte(&mut v, 204);                // frame CC
  return v;
}

// A hand-built header for emit tests; `length`, `frame_off` and `frame_len`
// are ignored by radiotap_emit (it recomputes the length from the pool).
fn mk_header(version: Int, present0: Int, present1: Int, words: Int, bits: Vec[Int], values: Vec[Int]) -> RadiotapHeader {
  let h = RadiotapHeader{
    version: version;
    length: 0;
    present_words: words;
    present0: present0;
    present1: present1;
    bits: bits;
    values: values;
    frame_off: 0;
    frame_len: 0;
  };
  return h;
}

// Value of the first field with `bit`, or -1000000 when absent (callers
// compare against real expected values, so absence fails the check).
fn value_of(h: &RadiotapHeader, bit: Int) -> Int {
  let r = radiotap_value(h, bit);
  match r {
    Ok(v) => { return v; },
    Err(_) => {},
  }
  return -1000000;
}

// True when radiotap_emit fails with exactly `want`.
fn emit_err(h: &RadiotapHeader, want: Str) -> Bool {
  let r = radiotap_emit(h);
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  let fx = canonical_fixture();
  var ok = fx.len() == 43;
  let r = radiotap_parse(&fx);
  if !r.is_ok { return assert(false, "canonical two-word fixture must parse"); }
  let h: RadiotapHeader = r.value;
  if radiotap_version(&h) != 0 { ok = false; }
  if radiotap_length(&h) != 40 { ok = false; }
  if radiotap_present_count(&h) != 2 { ok = false; }
  if radiotap_present_word(&h, 0) != 2148026415 { ok = false; }
  if radiotap_present_word(&h, 1) != 0 { ok = false; }
  if radiotap_field_count(&h) != 8 { ok = false; }
  if radiotap_field_bit(&h, 0) != 0 { ok = false; }
  if radiotap_field_bit(&h, 1) != 1 { ok = false; }
  if radiotap_field_bit(&h, 2) != 2 { ok = false; }
  if radiotap_field_bit(&h, 3) != 3 { ok = false; }
  if radiotap_field_bit(&h, 4) != 5 { ok = false; }
  if radiotap_field_bit(&h, 5) != 11 { ok = false; }
  if radiotap_field_bit(&h, 6) != 14 { ok = false; }
  if radiotap_field_bit(&h, 7) != 19 { ok = false; }
  if radiotap_field_bit(&h, 8) != -1 { ok = false; }
  if radiotap_field_bit(&h, -1) != -1 { ok = false; }
  return assert(ok, "two-word fixture: base header, present words, bit order");
}

fn t2() -> TestResult {
  let fx = canonical_fixture();
  let r = radiotap_parse(&fx);
  if !r.is_ok { return assert(false, "canonical fixture must parse"); }
  let h: RadiotapHeader = r.value;
  var ok = value_of(&h, 0) == 72623859790382856;
  if value_of(&h, 1) != 16 { ok = false; }
  if value_of(&h, 2) != 108 { ok = false; }
  if value_of(&h, 3) != 10488172 { ok = false; }
  if value_of(&h, 5) != -42 { ok = false; }
  if value_of(&h, 11) != 1 { ok = false; }
  if value_of(&h, 14) != 1 { ok = false; }
  if value_of(&h, 19) != 7 { ok = false; }
  if radiotap_channel_freq(&h) != 2412 { ok = false; }
  if radiotap_channel_flags(&h) != 160 { ok = false; }
  let iv = radiotap_field_value_at(&h, 4);
  if !iv.is_ok { ok = false; } else { if iv.value != -42 { ok = false; } }
  let fv = radiotap_field_value_at(&h, 0);
  if !fv.is_ok { ok = false; } else { if fv.value != 72623859790382856 { ok = false; } }
  return assert(ok, "canonical fixture: every field value pinned");
}

fn t3() -> TestResult {
  let fx = canonical_fixture();
  let r = radiotap_parse(&fx);
  if !r.is_ok { return assert(false, "canonical fixture must parse"); }
  let h: RadiotapHeader = r.value;
  var ok = radiotap_find(&h, 0) == 0;
  if radiotap_find(&h, 5) != 4 { ok = false; }
  if radiotap_find(&h, 19) != 7 { ok = false; }
  if radiotap_find(&h, 6) != -1 { ok = false; }
  if radiotap_find(&h, 30) != -1 { ok = false; }
  if radiotap_find(&h, -3) != -1 { ok = false; }
  if !err_int_is(radiotap_value(&h, 6), "radiotap: field absent") { ok = false; }
  if !err_int_is(radiotap_value(&h, 99), "radiotap: field absent") { ok = false; }
  if !err_int_is(radiotap_field_value_at(&h, -1), "radiotap: field index out of range") { ok = false; }
  if !err_int_is(radiotap_field_value_at(&h, 8), "radiotap: field index out of range") { ok = false; }
  return assert(ok, "first-match lookup and absent/out-of-range errors");
}

fn t4() -> TestResult {
  let fx = canonical_fixture();
  let r = radiotap_parse(&fx);
  if !r.is_ok { return assert(false, "canonical fixture must parse"); }
  let h: RadiotapHeader = r.value;
  var ok = radiotap_frame_offset(&h) == 40;
  if radiotap_frame_length(&h) != 3 { ok = false; }
  let fr = radiotap_frame(&fx, &h);
  if !fr.is_ok { ok = false; } else {
    let b: Vec[UInt8] = fr.value;
    if !bytes_equal(b, bytes3(170, 187, 204)) { ok = false; }
  }
  let hdr = prefix(fx, 40);
  let r2 = radiotap_parse(&hdr);
  if !r2.is_ok { ok = false; } else {
    let h2: RadiotapHeader = r2.value;
    if radiotap_frame_offset(&h2) != 40 { ok = false; }
    if radiotap_frame_length(&h2) != 0 { ok = false; }
    let f2 = radiotap_frame(&hdr, &h2);
    if !f2.is_ok { ok = false; } else {
      let e: Vec[UInt8] = f2.value;
      if e.len() != 0 { ok = false; }
    }
  }
  let cut = prefix(fx, 41);
  if !err_bytes_is(radiotap_frame(&cut, &h), "radiotap: frame out of bounds") { ok = false; }
  return assert(ok, "frame span and slice; a short buffer is Err");
}

fn t5() -> TestResult {
  let fx = canonical_fixture();
  let r = radiotap_parse(&fx);
  if !r.is_ok { return assert(false, "canonical fixture must parse"); }
  let h: RadiotapHeader = r.value;
  let er = radiotap_emit(&h);
  if !er.is_ok { return assert(false, "emit must succeed"); }
  let out: Vec[UInt8] = er.value;
  var ok = out.len() == 40;
  if !bytes_equal(out, prefix(fx, 40)) { ok = false; }
  let r2 = radiotap_parse(&out);
  if !r2.is_ok { ok = false; } else {
    let h2: RadiotapHeader = r2.value;
    if radiotap_present_count(&h2) != 2 { ok = false; }
    if radiotap_field_count(&h2) != 8 { ok = false; }
    if value_of(&h2, 0) != 72623859790382856 { ok = false; }
    if value_of(&h2, 3) != 10488172 { ok = false; }
    if value_of(&h2, 5) != -42 { ok = false; }
    if value_of(&h2, 19) != 7 { ok = false; }
    let er2 = radiotap_emit(&h2);
    if !er2.is_ok { ok = false; } else {
      let out2: Vec[UInt8] = er2.value;
      if !bytes_equal(out2, out) { ok = false; }
    }
  }
  return assert(ok, "emit reproduces the canonical fixture byte-for-byte");
}

fn t6() -> TestResult {
  let fx = canonical_fixture();
  var empty = Vec[UInt8].new();
  var ok = err_header_is(radiotap_parse(&empty), "radiotap: truncated header");
  let p7 = prefix(fx, 7);
  if !err_header_is(radiotap_parse(&p7), "radiotap: truncated header") { ok = false; }
  let p1 = prefix(fx, 1);
  if !err_header_is(radiotap_parse(&p1), "radiotap: truncated header") { ok = false; }
  return assert(ok, "inputs shorter than the 8-byte base header are Err");
}

fn t7() -> TestResult {
  let fx = canonical_fixture();
  let v1 = with_byte(fx, 0, 1);
  var ok = err_header_is(radiotap_parse(&v1), "radiotap: bad version");
  let fx2 = canonical_fixture();
  let v255 = with_byte(fx2, 0, 255);
  if !err_header_is(radiotap_parse(&v255), "radiotap: bad version") { ok = false; }
  return assert(ok, "version != 0 is rejected");
}

fn t8() -> TestResult {
  var a = Vec[UInt8].new();
  push_byte(&mut a, 0);
  push_byte(&mut a, 0);
  push_le16(&mut a, 7);
  push_le32(&mut a, 0);
  var ok = err_header_is(radiotap_parse(&a), "radiotap: bad length");
  let fx = canonical_fixture();
  let b = with_len(fx, 44);
  if !err_header_is(radiotap_parse(&b), "radiotap: bad length") { ok = false; }
  let fx2 = canonical_fixture();
  let c = with_len(fx2, 41);
  if !err_header_is(radiotap_parse(&c), "radiotap: length mismatch") { ok = false; }
  let fx3 = canonical_fixture();
  let d = with_len(fx3, 42);
  if !err_header_is(radiotap_parse(&d), "radiotap: length mismatch") { ok = false; }
  let fx4 = canonical_fixture();
  let e = prefix(fx4, 39);
  if !err_header_is(radiotap_parse(&e), "radiotap: bad length") { ok = false; }
  var f = Vec[UInt8].new();
  push_byte(&mut f, 0);
  push_byte(&mut f, 0);
  push_le16(&mut f, 8);
  push_le32(&mut f, 0);
  let fr = radiotap_parse(&f);
  if !fr.is_ok { ok = false; } else {
    let h: RadiotapHeader = fr.value;
    if radiotap_length(&h) != 8 { ok = false; }
    if radiotap_field_count(&h) != 0 { ok = false; }
  }
  return assert(ok, "length < 8, length > buffer and length mismatch are Err");
}

fn t9() -> TestResult {
  var a = Vec[UInt8].new();
  push_byte(&mut a, 0);
  push_byte(&mut a, 0);
  push_le16(&mut a, 8);
  push_le32(&mut a, 2147483648);
  var ok = err_header_is(radiotap_parse(&a), "radiotap: bad present chain");
  var b = Vec[UInt8].new();
  push_byte(&mut b, 0);
  push_byte(&mut b, 0);
  push_le16(&mut b, 12);
  push_le32(&mut b, 2147483648);
  push_le32(&mut b, 2147483648);
  if !err_header_is(radiotap_parse(&b), "radiotap: too many present words") { ok = false; }
  var c = Vec[UInt8].new();
  push_byte(&mut c, 0);
  push_byte(&mut c, 0);
  push_le16(&mut c, 12);
  push_le32(&mut c, 2147483648);
  push_le32(&mut c, 0);
  push_byte(&mut c, 77);
  let cr = radiotap_parse(&c);
  if !cr.is_ok { ok = false; } else {
    let h: RadiotapHeader = cr.value;
    if radiotap_present_count(&h) != 2 { ok = false; }
    if radiotap_present_word(&h, 1) != 0 { ok = false; }
    if radiotap_field_count(&h) != 0 { ok = false; }
    if radiotap_frame_offset(&h) != 12 { ok = false; }
    if radiotap_frame_length(&h) != 1 { ok = false; }
  }
  var d = Vec[UInt8].new();
  push_byte(&mut d, 0);
  push_byte(&mut d, 0);
  push_le16(&mut d, 12);
  push_le32(&mut d, 2147483648);
  push_le32(&mut d, 1);
  if !err_header_is(radiotap_parse(&d), "radiotap: unsupported field") { ok = false; }
  return assert(ok, "present chain: 2 words accepted, 3 rejected, word-1 bits unsupported");
}

fn t10() -> TestResult {
  var a = Vec[UInt8].new();
  push_byte(&mut a, 0);
  push_byte(&mut a, 0);
  push_le16(&mut a, 8);
  push_le32(&mut a, 1048576);
  var ok = err_header_is(radiotap_parse(&a), "radiotap: unsupported field");
  var b = Vec[UInt8].new();
  push_byte(&mut b, 0);
  push_byte(&mut b, 0);
  push_le16(&mut b, 8);
  push_le32(&mut b, 1073741824);
  if !err_header_is(radiotap_parse(&b), "radiotap: unsupported field") { ok = false; }
  var c = Vec[UInt8].new();
  push_byte(&mut c, 0);
  push_byte(&mut c, 0);
  push_le16(&mut c, 12);
  push_le32(&mut c, 1048580);
  var i = 8;
  while i < 12 {
    push_byte(&mut c, 0);
    i = i + 1;
  }
  if !err_header_is(radiotap_parse(&c), "radiotap: unsupported field") { ok = false; }
  return assert(ok, "unknown present bits stop parsing as unsupported");
}

fn t11() -> TestResult {
  var a = Vec[UInt8].new();
  push_byte(&mut a, 0);
  push_byte(&mut a, 0);
  push_le16(&mut a, 12);
  push_le32(&mut a, 1);
  var i = 8;
  while i < 12 {
    push_byte(&mut a, 0);
    i = i + 1;
  }
  var ok = err_header_is(radiotap_parse(&a), "radiotap: truncated field");
  var b = Vec[UInt8].new();
  push_byte(&mut b, 0);
  push_byte(&mut b, 0);
  push_le16(&mut b, 10);
  push_le32(&mut b, 8);
  i = 8;
  while i < 10 {
    push_byte(&mut b, 0);
    i = i + 1;
  }
  if !err_header_is(radiotap_parse(&b), "radiotap: truncated field") { ok = false; }
  var c = Vec[UInt8].new();
  push_byte(&mut c, 0);
  push_byte(&mut c, 0);
  push_le16(&mut c, 8);
  push_le32(&mut c, 2);
  if !err_header_is(radiotap_parse(&c), "radiotap: truncated field") { ok = false; }
  var d = Vec[UInt8].new();
  push_byte(&mut d, 0);
  push_byte(&mut d, 0);
  push_le16(&mut d, 9);
  push_le32(&mut d, 2);
  push_byte(&mut d, 99);
  let dr = radiotap_parse(&d);
  if !dr.is_ok { ok = false; } else {
    let h: RadiotapHeader = dr.value;
    if value_of(&h, 1) != 99 { ok = false; }
  }
  return assert(ok, "fields that run past the declared length are truncated");
}

fn t12() -> TestResult {
  let fx = canonical_fixture();
  let a = with_byte(fx, 12, 1);
  var ok = err_header_is(radiotap_parse(&a), "radiotap: bad alignment padding");
  let fx2 = canonical_fixture();
  let b = with_byte(fx2, 35, 7);
  if !err_header_is(radiotap_parse(&b), "radiotap: bad alignment padding") { ok = false; }
  let fx3 = canonical_fixture();
  if !radiotap_parse(&fx3).is_ok { ok = false; }
  return assert(ok, "nonzero alignment padding is rejected; zero padding parses");
}

fn t13() -> TestResult {
  var a = Vec[UInt8].new();
  push_byte(&mut a, 0);
  push_byte(&mut a, 0);
  push_le16(&mut a, 16);
  push_le32(&mut a, 1);
  push_byte(&mut a, 255);
  push_byte(&mut a, 255);
  push_byte(&mut a, 255);
  push_byte(&mut a, 255);
  push_byte(&mut a, 255);
  push_byte(&mut a, 255);
  push_byte(&mut a, 255);
  push_byte(&mut a, 127);
  let ar = radiotap_parse(&a);
  var ok = ar.is_ok;
  if ar.is_ok {
    let h: RadiotapHeader = ar.value;
    if value_of(&h, 0) != 9223372036854775807 { ok = false; }
  }
  var b = Vec[UInt8].new();
  push_byte(&mut b, 0);
  push_byte(&mut b, 0);
  push_le16(&mut b, 16);
  push_le32(&mut b, 1);
  push_byte(&mut b, 0);
  push_byte(&mut b, 0);
  push_byte(&mut b, 0);
  push_byte(&mut b, 0);
  push_byte(&mut b, 0);
  push_byte(&mut b, 0);
  push_byte(&mut b, 0);
  push_byte(&mut b, 128);
  if !err_header_is(radiotap_parse(&b), "radiotap: tsft out of range") { ok = false; }
  var c = Vec[UInt8].new();
  push_byte(&mut c, 0);
  push_byte(&mut c, 0);
  push_le16(&mut c, 16);
  push_le32(&mut c, 1);
  push_byte(&mut c, 1);
  var j = 1;
  while j < 8 {
    push_byte(&mut c, 0);
    j = j + 1;
  }
  let cr = radiotap_parse(&c);
  if !cr.is_ok { ok = false; } else {
    let h2: RadiotapHeader = cr.value;
    if value_of(&h2, 0) != 1 { ok = false; }
  }
  return assert(ok, "TSFT is little-endian u64 capped at 2^63-1");
}

fn t14() -> TestResult {
  let h = mk_header(0, 524297, 0, 1, iv3(0, 3, 19), iv3(1, 2412, 9));
  let er = radiotap_emit(&h);
  if !er.is_ok { return assert(false, "hand-built header must emit"); }
  let out: Vec[UInt8] = er.value;
  var want = Vec[UInt8].new();
  push_byte(&mut want, 0);
  push_byte(&mut want, 0);
  push_le16(&mut want, 24);
  push_le32(&mut want, 524297);
  push_le64(&mut want, 1);
  push_le16(&mut want, 2412);
  push_le16(&mut want, 0);
  push_le32(&mut want, 9);
  var ok = bytes_equal(out, want);
  let pr = radiotap_parse(&out);
  if !pr.is_ok { ok = false; } else {
    let h2: RadiotapHeader = pr.value;
    if radiotap_field_count(&h2) != 3 { ok = false; }
    if value_of(&h2, 0) != 1 { ok = false; }
    if radiotap_channel_freq(&h2) != 2412 { ok = false; }
    if radiotap_channel_flags(&h2) != 0 { ok = false; }
    if value_of(&h2, 19) != 9 { ok = false; }
    if radiotap_frame_length(&h2) != 0 { ok = false; }
  }
  return assert(ok, "emit pins TSFT/CHANNEL/XCHANNEL alignment offsets");
}

fn t15() -> TestResult {
  let h1 = mk_header(0, 2, 0, 1, iv1(1), iv1(3));
  let er1 = radiotap_emit(&h1);
  if !er1.is_ok { return assert(false, "valid FLAGS header must emit"); }
  let out1: Vec[UInt8] = er1.value;
  var ok = out1.len() == 9;
  let b2: Int = (out1[2] as Int) & 0xFF;
  if b2 != 9 { ok = false; }
  var no_bits = Vec[Int].new();
  var no_vals = Vec[Int].new();
  let h2 = mk_header(1, 0, 0, 1, no_bits, no_vals);
  if !emit_err(&h2, "radiotap: bad version") { ok = false; }
  let h3 = mk_header(0, 3, 0, 1, iv2(1, 0), iv2(1, 2));
  if !emit_err(&h3, "radiotap: fields out of order") { ok = false; }
  let h4 = mk_header(0, 4, 0, 1, iv2(2, 2), iv2(1, 1));
  if !emit_err(&h4, "radiotap: fields out of order") { ok = false; }
  let h5 = mk_header(0, 2, 0, 1, iv1(1), iv1(256));
  if !emit_err(&h5, "radiotap: field value out of range") { ok = false; }
  let h6 = mk_header(0, 2, 0, 1, iv1(1), iv1(-1));
  if !emit_err(&h6, "radiotap: field value out of range") { ok = false; }
  let h7 = mk_header(0, 32, 0, 1, iv1(5), iv1(-129));
  if !emit_err(&h7, "radiotap: field value out of range") { ok = false; }
  let h8 = mk_header(0, 32, 0, 1, iv1(5), iv1(128));
  if !emit_err(&h8, "radiotap: field value out of range") { ok = false; }
  let h9 = mk_header(0, 33554432, 0, 1, iv1(25), iv1(0));
  if !emit_err(&h9, "radiotap: unsupported field") { ok = false; }
  let h10 = mk_header(0, 4, 0, 1, iv1(1), iv1(3));
  if !emit_err(&h10, "radiotap: present words mismatch") { ok = false; }
  let h11 = mk_header(0, 2, 0, 3, iv1(1), iv1(3));
  if !emit_err(&h11, "radiotap: present words mismatch") { ok = false; }
  var no_vals2 = Vec[Int].new();
  let h12 = mk_header(0, 2, 0, 1, iv1(1), no_vals2);
  if !emit_err(&h12, "radiotap: field pool mismatch") { ok = false; }
  let hs = mk_header(0, 32, 0, 1, iv1(5), iv1(-128));
  let es = radiotap_emit(&hs);
  if !es.is_ok { ok = false; } else {
    let sb: Vec[UInt8] = es.value;
    let ps = radiotap_parse(&sb);
    if !ps.is_ok { ok = false; } else {
      let hp: RadiotapHeader = ps.value;
      if value_of(&hp, 5) != -128 { ok = false; }
      if radiotap_present_word(&hp, 0) != 32 { ok = false; }
    }
  }
  return assert(ok, "emit rejects bad version, order, range, pool and present words");
}

fn t16() -> TestResult {
  let fx = canonical_fixture();
  let r = radiotap_parse(&fx);
  if !r.is_ok { return assert(false, "canonical fixture must parse"); }
  let h: RadiotapHeader = r.value;
  var ok = radiotap_present_word(&h, -1) == -1;
  if radiotap_present_word(&h, 2) != -1 { ok = false; }
  if radiotap_present_word(&h, 0) != 2148026415 { ok = false; }
  var a = Vec[UInt8].new();
  push_byte(&mut a, 0);
  push_byte(&mut a, 0);
  push_le16(&mut a, 8);
  push_le32(&mut a, 0);
  let ar = radiotap_parse(&a);
  if !ar.is_ok { ok = false; } else {
    let h1: RadiotapHeader = ar.value;
    if radiotap_present_count(&h1) != 1 { ok = false; }
    if radiotap_present_word(&h1, 1) != -1 { ok = false; }
  }
  return assert(ok, "present-word accessor guards");
}

fn t17() -> TestResult {
  var a = Vec[UInt8].new();
  push_byte(&mut a, 0);
  push_byte(&mut a, 0);
  push_le16(&mut a, 8);
  push_le32(&mut a, 0);
  push_byte(&mut a, 17);
  push_byte(&mut a, 34);
  let ar = radiotap_parse(&a);
  if !ar.is_ok { return assert(false, "zero-field header must parse"); }
  let h: RadiotapHeader = ar.value;
  var ok = radiotap_field_count(&h) == 0;
  if radiotap_present_count(&h) != 1 { ok = false; }
  if radiotap_present_word(&h, 0) != 0 { ok = false; }
  if radiotap_frame_offset(&h) != 8 { ok = false; }
  if radiotap_frame_length(&h) != 2 { ok = false; }
  if radiotap_find(&h, 0) != -1 { ok = false; }
  if !err_int_is(radiotap_value(&h, 0), "radiotap: field absent") { ok = false; }
  let fr = radiotap_frame(&a, &h);
  if !fr.is_ok { ok = false; } else {
    let b: Vec[UInt8] = fr.value;
    if !bytes_equal(b, bytes2(17, 34)) { ok = false; }
  }
  let er = radiotap_emit(&h);
  if !er.is_ok { ok = false; } else {
    let out: Vec[UInt8] = er.value;
    var want = Vec[UInt8].new();
    push_byte(&mut want, 0);
    push_byte(&mut want, 0);
    push_le16(&mut want, 8);
    push_le32(&mut want, 0);
    if !bytes_equal(out, want) { ok = false; }
  }
  return assert(ok, "zero-field header: empty pool, frame span and emit");
}

fn t18() -> TestResult {
  let h = mk_header(0, 1120, 0, 1, iv3(5, 6, 10), iv3(-42, -128, 127));
  let er = radiotap_emit(&h);
  if !er.is_ok { return assert(false, "signed header must emit"); }
  let out: Vec[UInt8] = er.value;
  var want = Vec[UInt8].new();
  push_byte(&mut want, 0);
  push_byte(&mut want, 0);
  push_le16(&mut want, 11);
  push_le32(&mut want, 1120);
  push_byte(&mut want, 214);
  push_byte(&mut want, 128);
  push_byte(&mut want, 127);
  var ok = bytes_equal(out, want);
  let pr = radiotap_parse(&out);
  if !pr.is_ok { ok = false; } else {
    let h2: RadiotapHeader = pr.value;
    if value_of(&h2, 5) != -42 { ok = false; }
    if value_of(&h2, 6) != -128 { ok = false; }
    if value_of(&h2, 10) != 127 { ok = false; }
    if radiotap_present_word(&h2, 0) != 1120 { ok = false; }
  }
  return assert(ok, "signed i8 fields emit two's complement and round-trip");
}

fn t19() -> TestResult {
  var no_bits = Vec[Int].new();
  var no_vals = Vec[Int].new();
  let h = mk_header(0, 2147483648, 0, 2, no_bits, no_vals);
  let er = radiotap_emit(&h);
  if !er.is_ok { return assert(false, "two-word empty header must emit"); }
  let out: Vec[UInt8] = er.value;
  var want = Vec[UInt8].new();
  push_byte(&mut want, 0);
  push_byte(&mut want, 0);
  push_le16(&mut want, 12);
  push_le32(&mut want, 2147483648);
  push_le32(&mut want, 0);
  var ok = bytes_equal(out, want);
  let pr = radiotap_parse(&out);
  if !pr.is_ok { ok = false; } else {
    let h2: RadiotapHeader = pr.value;
    if radiotap_present_count(&h2) != 2 { ok = false; }
    if radiotap_present_word(&h2, 1) != 0 { ok = false; }
    if radiotap_length(&h2) != 12 { ok = false; }
    if radiotap_field_count(&h2) != 0 { ok = false; }
  }
  return assert(ok, "second present word with no field bits round-trips");
}

fn main() -> Int {
  io.println("=== xiom.radiotap conformance tests ===");
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
  if failed == 0 {
    io.println("xiom.radiotap: all tests passed");
  } else {
    io.println("xiom.radiotap: tests failed");
  }
  return failed;
}
