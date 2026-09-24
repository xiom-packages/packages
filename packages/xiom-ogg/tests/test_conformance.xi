// XIOM -- xiom.ogg conformance tests (22 checks)
// Port task: prove the pure-XIOM xiom.ogg page walk and Ogg CRC-32.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Fixtures are assembled byte by byte (pushes), independent of src/ogg.xi.
// The checksum is verified against pinned, independently computed constants
// and against an independent bit-serial reference CRC written below. Str
// equality goes through str_compare (BUG 17 discipline: `==` on Str values
// read from a Vec lowers to a pointer comparison).
//
// Pinned CRC-32 values (poly 0x04C11DB7, init 0, MSB-first, no reflection,
// no final xor; cross-checked against the CRC-32/MPEG-2 known-answer test):
//   ""                                                -> 0
//   "123456789"                                       -> 2309065087 (0x89A1897F)
//   bytes 0..15                                       -> 4233616773 (0xFC57DD85)
//   one-page fixture (29 bytes, checksum field zeroed) -> 3609392314 (0xD722F4BA)

module ogg_tests
use xiom.io; use xiom.test;
use xiom.ogg;
use xiom.string;
use xiom.string.compare;

// --------------------------------------------------
//  Helpers
// --------------------------------------------------

fn str_eq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn err_pages_is(r: Result[OggPages, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return str_eq(r.error, want);
}

fn err_bool_is(r: Result[Bool, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return str_eq(r.error, want);
}

fn push_text(v: &mut Vec[UInt8], s: Str) {
  var i = 0;
  while i < s.len() {
    v.push(string.byte_at(s, i));
    i = i + 1;
  }
}

fn ascii_bytes(s: Str) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  push_text(&mut v, s);
  return v;
}

fn push_zeros(v: &mut Vec[UInt8], n: Int) {
  var i = 0;
  while i < n {
    v.push(0 as UInt8);
    i = i + 1;
  }
}

fn zeros(n: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  push_zeros(&mut v, n);
  return v;
}

fn push_bytes(v: &mut Vec[UInt8], src: &Vec[UInt8]) {
  var i = 0;
  while i < src.len() {
    v.push(src[i]);
    i = i + 1;
  }
}

fn concat(a: Vec[UInt8], b: Vec[UInt8]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  push_bytes(&mut out, &a);
  push_bytes(&mut out, &b);
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

// Byte `k` of `v` (0 = least significant) as UInt8; negative values yield
// their low two's-complement bytes (-1 -> 255 for every k).
fn byte_of(v: Int, k: Int) -> UInt8 {
  var q = v;
  var i = 0;
  while i < k {
    var r = q % 256;
    if r < 0 { r = r + 256; }
    q = (q - r) / 256;
    i = i + 1;
  }
  var b = q % 256;
  if b < 0 { b = b + 256; }
  return b as UInt8;
}

fn push_le(v: &mut Vec[UInt8], val: Int, size: Int) {
  var i = 0;
  while i < size {
    v.push(byte_of(val, i));
    i = i + 1;
  }
}

// Copy of `v` with byte `pos` replaced.
fn set_byte(v: Vec[UInt8], pos: Int, b: Int) -> Vec[UInt8] {
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

// Copy of `v` with the low 4 bytes of `val` written little-endian at `pos`.
fn set_le32(v: Vec[UInt8], pos: Int, val: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < v.len() {
    if i >= pos && i < pos + 4 {
      out.push(byte_of(val, i - pos));
    } else {
      out.push(v[i]);
    }
    i = i + 1;
  }
  return out;
}

// Independent bit-serial Ogg CRC-32: same parameters as the library
// implementation, deliberately written as a different algorithm (one bit
// at a time) so a shared mistake is unlikely.
fn pow2(k: Int) -> Int {
  var d: Int = 1;
  var i = 0;
  while i < k {
    d = d * 2;
    i = i + 1;
  }
  return d;
}

fn bit_of(v: Int, k: Int) -> Int {
  return (v / pow2(k)) % 2;
}

fn ref_crc(data: &Vec[UInt8]) -> Int {
  var crc: Int = 0;
  var i = 0;
  while i < data.len() {
    let b: Int = (data[i] as Int) & 0xFF;
    var k = 7;
    while k >= 0 {
      let feedback: Int = (crc / 2147483648) ^ bit_of(b, k);
      crc = (crc % 2147483648) * 2;
      if feedback == 1 {
        crc = crc ^ 79764919;
      }
      k = k - 1;
    }
    i = i + 1;
  }
  return crc;
}

// Hand-built Ogg page with the 4 checksum bytes left as zero, so ref_crc
// over the buffer is the authentic page checksum. Call with_crc to store it.
fn mk_page(flags: Int, granule: Int, serial: Int, seq: Int, lacing: &Vec[Int], body: &Vec[UInt8]) -> Vec[UInt8] {
  var p = Vec[UInt8].new();
  push_text(&mut p, "OggS");
  p.push(0 as UInt8);
  p.push(flags as UInt8);
  push_le(&mut p, granule, 8);
  push_le(&mut p, serial, 4);
  push_le(&mut p, seq, 4);
  push_zeros(&mut p, 4);
  p.push(lacing.len() as UInt8);
  var i = 0;
  while i < lacing.len() {
    let lv: Int = lacing[i];
    p.push(lv as UInt8);
    i = i + 1;
  }
  push_bytes(&mut p, body);
  return p;
}

fn with_crc(page: Vec[UInt8]) -> Vec[UInt8] {
  let c = ref_crc(&page);
  return set_le32(page, 22, c);
}

fn pattern(n: Int, seed: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < n {
    v.push(((seed + i * 7) % 251) as UInt8);
    i = i + 1;
  }
  return v;
}

fn ramp16() -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < 16 {
    v.push(i as UInt8);
    i = i + 1;
  }
  return v;
}

// One page, flags BOS (2), granule 0, serial 1234, sequence 0, one segment
// with a 1-byte body (0xAA); total size 29.
fn one_page() -> Vec[UInt8] {
  var lacing = Vec[Int].new();
  lacing.push(1);
  var body = Vec[UInt8].new();
  body.push(170 as UInt8);
  return with_crc(mk_page(2, 0, 1234, 0, &lacing, &body));
}

// Two pages, serial 777: page 0 is 31 bytes (lacing 3, body pattern(3,1)),
// page 1 is 32 bytes (lacing 1+2, body pattern(3,4), flags EOS).
fn two_pages() -> Vec[UInt8] {
  var l1 = Vec[Int].new();
  l1.push(3);
  let b1 = pattern(3, 1);
  let p1 = with_crc(mk_page(2, 960, 777, 0, &l1, &b1));
  var l2 = Vec[Int].new();
  l2.push(1);
  l2.push(2);
  let b2 = pattern(3, 4);
  let p2 = with_crc(mk_page(4, 1920, 777, 1, &l2, &b2));
  return concat(p1, p2);
}

// Three pages demonstrating multiplexed bitstreams: sizes 29 + 30 + 29.
fn three_pages() -> Vec[UInt8] {
  var l1 = Vec[Int].new();
  l1.push(1);
  var b1 = Vec[UInt8].new();
  b1.push(1 as UInt8);
  let p1 = with_crc(mk_page(2, 0, 11, 0, &l1, &b1));
  var l2 = Vec[Int].new();
  l2.push(2);
  var b2 = Vec[UInt8].new();
  b2.push(2 as UInt8);
  b2.push(3 as UInt8);
  let p2 = with_crc(mk_page(2, 0, 22, 0, &l2, &b2));
  var l3 = Vec[Int].new();
  l3.push(1);
  var b3 = Vec[UInt8].new();
  b3.push(4 as UInt8);
  let p3 = with_crc(mk_page(4, 100, 11, 1, &l3, &b3));
  return concat(concat(p1, p2), p3);
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  let d = one_page();
  var ok = d.len() == 29;
  let r = ogg_parse_pages(&d);
  if !r.is_ok {
    return assert(false, "one page: offset/size/flags/granule/serial/sequence pinned");
  }
  let p = r.value;
  if ogg_page_count(&p) != 1 { ok = false; }
  let off0: Int = p.offsets[0];
  let size0: Int = p.sizes[0];
  let flag0: Int = p.flags[0];
  let gran0: Int = p.granules[0];
  let ser0: Int = p.serials[0];
  let seq0: Int = p.sequences[0];
  if off0 != 0 { ok = false; }
  if size0 != 29 { ok = false; }
  if flag0 != 2 { ok = false; }
  if gran0 != 0 { ok = false; }
  if ser0 != 1234 { ok = false; }
  if seq0 != 0 { ok = false; }
  if ogg_page_offset(&p, 0) != 0 { ok = false; }
  if ogg_page_serial(&p, 0) != 1234 { ok = false; }
  return assert(ok, "one page: offset/size/flags/granule/serial/sequence pinned");
}

fn t2() -> TestResult {
  let d = two_pages();
  var ok = d.len() == 63;
  let r = ogg_parse_pages(&d);
  if !r.is_ok {
    return assert(false, "two pages: offsets, sizes and fields pinned");
  }
  let p = r.value;
  if ogg_page_count(&p) != 2 { ok = false; }
  let off0: Int = p.offsets[0];
  let off1: Int = p.offsets[1];
  let size0: Int = p.sizes[0];
  let size1: Int = p.sizes[1];
  let flag0: Int = p.flags[0];
  let flag1: Int = p.flags[1];
  let gran0: Int = p.granules[0];
  let gran1: Int = p.granules[1];
  let ser0: Int = p.serials[0];
  let ser1: Int = p.serials[1];
  let seq0: Int = p.sequences[0];
  let seq1: Int = p.sequences[1];
  if off0 != 0 { ok = false; }
  if off1 != 31 { ok = false; }
  if size0 != 31 { ok = false; }
  if size1 != 32 { ok = false; }
  if flag0 != 2 { ok = false; }
  if flag1 != 4 { ok = false; }
  if gran0 != 960 { ok = false; }
  if gran1 != 1920 { ok = false; }
  if ser0 != 777 { ok = false; }
  if ser1 != 777 { ok = false; }
  if seq0 != 0 { ok = false; }
  if seq1 != 1 { ok = false; }
  if ogg_page_offset(&p, 1) != 31 { ok = false; }
  if ogg_page_serial(&p, 1) != 777 { ok = false; }
  return assert(ok, "two pages: offsets, sizes and fields pinned");
}

fn t3() -> TestResult {
  let empty = Vec[UInt8].new();
  let nine = ascii_bytes("123456789");
  let ramp = ramp16();
  var ok = ogg_crc32(&empty) == 0;
  if ogg_crc32(&nine) != 2309065087 { ok = false; }
  if ogg_crc32(&ramp) != 4233616773 { ok = false; }
  return assert(ok, "CRC-32 pinned: empty 0, \"123456789\", bytes 0..15");
}

fn t4() -> TestResult {
  let empty = Vec[UInt8].new();
  let nine = ascii_bytes("123456789");
  let fox = ascii_bytes("The quick brown fox jumps over the lazy dog");
  let page = one_page();
  let pages = two_pages();
  var l = Vec[Int].new();
  l.push(1);
  var b = Vec[UInt8].new();
  b.push(170 as UInt8);
  let raw = mk_page(2, 0, 1234, 0, &l, &b);
  var ok = ref_crc(&empty) == ogg_crc32(&empty);
  if ref_crc(&nine) != ogg_crc32(&nine) { ok = false; }
  if ref_crc(&fox) != ogg_crc32(&fox) { ok = false; }
  if ref_crc(&page) != ogg_crc32(&page) { ok = false; }
  if ref_crc(&pages) != ogg_crc32(&pages) { ok = false; }
  if ref_crc(&raw) != 3609392314 { ok = false; }
  if ogg_crc32(&raw) != 3609392314 { ok = false; }
  return assert(ok, "independent bit-serial reference agrees with ogg_crc32");
}

fn t5() -> TestResult {
  let base = ascii_bytes("123456789");
  let c0 = ogg_crc32(&base);
  let f0 = set_byte(base, 0, 48);
  let f8 = set_byte(base, 8, 56);
  let page = one_page();
  let corrupt = set_byte(page, 28, 171);
  var ok = ogg_crc32(&f0) != c0;
  if ogg_crc32(&f8) == c0 { ok = false; }
  if ogg_crc32(&corrupt) == ogg_crc32(&page) { ok = false; }
  if ogg_crc32(&f0) != ref_crc(&f0) { ok = false; }
  if ogg_crc32(&f8) != ref_crc(&f8) { ok = false; }
  return assert(ok, "flipping any covered byte changes the CRC");
}

fn t6() -> TestResult {
  let good_page = one_page();
  let corrupt_page = set_byte(good_page, 28, 171);
  let zeroed_crc = set_byte(good_page, 22, 0);
  let g = ogg_page_crc_ok(&good_page, 0);
  let c = ogg_page_crc_ok(&corrupt_page, 0);
  let z = ogg_page_crc_ok(&zeroed_crc, 0);
  var ok = g.is_ok;
  if !g.is_ok { ok = false; } elif !g.value { ok = false; }
  if !c.is_ok { ok = false; } elif c.value { ok = false; }
  if !z.is_ok { ok = false; } elif z.value { ok = false; }
  return assert(ok, "crc_ok true for a correct page, false when corrupted");
}

fn t7() -> TestResult {
  let d = two_pages();
  let r0 = ogg_page_crc_ok(&d, 0);
  let r1 = ogg_page_crc_ok(&d, 1);
  var ok = r0.is_ok;
  if !r0.is_ok { ok = false; } elif !r0.value { ok = false; }
  if !r1.is_ok { ok = false; } elif !r1.value { ok = false; }
  return assert(ok, "crc_ok verifies both pages of a two-page stream");
}

fn t8() -> TestResult {
  let d = one_page();
  let v1 = set_byte(d, 4, 1);
  let v255 = set_byte(d, 4, 255);
  let two = two_pages();
  let v2 = set_byte(two, 35, 1);
  var ok = err_pages_is(ogg_parse_pages(&v1), "ogg: unsupported version");
  if !err_pages_is(ogg_parse_pages(&v255), "ogg: unsupported version") { ok = false; }
  if !err_pages_is(ogg_parse_pages(&v2), "ogg: unsupported version") { ok = false; }
  if !err_bool_is(ogg_page_crc_ok(&v1, 0), "ogg: unsupported version") { ok = false; }
  return assert(ok, "version != 0 is Err");
}

fn t9() -> TestResult {
  let d = one_page();
  let p1 = prefix(d, 1);
  let p4 = prefix(d, 4);
  let p26 = prefix(d, 26);
  var ok = err_pages_is(ogg_parse_pages(&p1), "ogg: truncated page header");
  if !err_pages_is(ogg_parse_pages(&p4), "ogg: truncated page header") { ok = false; }
  if !err_pages_is(ogg_parse_pages(&p26), "ogg: truncated page header") { ok = false; }
  if !err_bool_is(ogg_page_crc_ok(&p26, 0), "ogg: truncated page header") { ok = false; }
  return assert(ok, "truncated page header (< 27 bytes) is Err");
}

fn t10() -> TestResult {
  let d = one_page();
  let nsegs3 = set_byte(d, 26, 3);
  let cut27 = prefix(d, 27);
  let two = two_pages();
  let cut59 = prefix(two, 59);
  var ok = err_pages_is(ogg_parse_pages(&nsegs3), "ogg: truncated segment table");
  if !err_pages_is(ogg_parse_pages(&cut27), "ogg: truncated segment table") { ok = false; }
  if !err_pages_is(ogg_parse_pages(&cut59), "ogg: truncated segment table") { ok = false; }
  return assert(ok, "truncated segment table is Err");
}

fn t11() -> TestResult {
  let d = one_page();
  let cut28 = prefix(d, 28);
  var l = Vec[Int].new();
  l.push(255);
  l.push(255);
  l.push(1);
  let body = pattern(511, 3);
  let raw = mk_page(4, 55, 9, 2, &l, &body);
  let big = with_crc(raw);
  let cut540 = prefix(big, 540);
  let two = two_pages();
  let cut62 = prefix(two, 62);
  var ok = err_pages_is(ogg_parse_pages(&cut28), "ogg: truncated page data");
  if !err_pages_is(ogg_parse_pages(&cut540), "ogg: truncated page data") { ok = false; }
  if !err_pages_is(ogg_parse_pages(&cut62), "ogg: truncated page data") { ok = false; }
  if !err_bool_is(ogg_page_crc_ok(&cut540, 0), "ogg: truncated page data") { ok = false; }
  return assert(ok, "truncated page data is Err");
}

fn t12() -> TestResult {
  let d = one_page();
  let j4 = concat(d, ascii_bytes("junk"));
  let j10 = concat(d, zeros(10));
  let j2 = concat(d, zeros(2));
  let two = two_pages();
  let bad2 = set_byte(two, 31, 88);
  var ok = err_pages_is(ogg_parse_pages(&j4), "ogg: trailing garbage");
  if !err_pages_is(ogg_parse_pages(&j10), "ogg: trailing garbage") { ok = false; }
  if !err_pages_is(ogg_parse_pages(&j2), "ogg: trailing garbage") { ok = false; }
  if !err_pages_is(ogg_parse_pages(&bad2), "ogg: trailing garbage") { ok = false; }
  return assert(ok, "trailing garbage after the last page is Err");
}

fn t13() -> TestResult {
  let two = two_pages();
  let cut36 = prefix(two, 36);
  let cut57 = prefix(two, 57);
  var ok = err_pages_is(ogg_parse_pages(&cut36), "ogg: truncated page header");
  if !err_pages_is(ogg_parse_pages(&cut57), "ogg: truncated page header") { ok = false; }
  return assert(ok, "partial second page is a truncated header");
}

fn t14() -> TestResult {
  let empty = Vec[UInt8].new();
  var ok = err_pages_is(ogg_parse_pages(&empty), "ogg: empty input");
  if !err_bool_is(ogg_page_crc_ok(&empty, 0), "ogg: empty input") { ok = false; }
  return assert(ok, "empty input is Err");
}

fn t15() -> TestResult {
  let d = one_page();
  let b0 = set_byte(d, 0, 88);
  let b3 = set_byte(d, 3, 88);
  var ok = err_pages_is(ogg_parse_pages(&b0), "ogg: bad capture pattern");
  if !err_pages_is(ogg_parse_pages(&b3), "ogg: bad capture pattern") { ok = false; }
  if !err_bool_is(ogg_page_crc_ok(&b0, 0), "ogg: bad capture pattern") { ok = false; }
  return assert(ok, "bad capture pattern on the first page is Err");
}

fn t16() -> TestResult {
  let d = one_page();
  let r = ogg_parse_pages(&d);
  if !r.is_ok { return assert(false, "out-of-range accessors return -1"); }
  let p = r.value;
  var ok = ogg_page_count(&p) == 1;
  if ogg_page_offset(&p, -1) != -1 { ok = false; }
  if ogg_page_offset(&p, 1) != -1 { ok = false; }
  if ogg_page_offset(&p, 999) != -1 { ok = false; }
  if ogg_page_serial(&p, -1) != -1 { ok = false; }
  if ogg_page_serial(&p, 1) != -1 { ok = false; }
  let two = two_pages();
  let r2 = ogg_parse_pages(&two);
  if !r2.is_ok {
    ok = false;
  } else {
    let p2 = r2.value;
    if ogg_page_count(&p2) != 2 { ok = false; }
    if ogg_page_offset(&p2, 2) != -1 { ok = false; }
    if ogg_page_serial(&p2, 2) != -1 { ok = false; }
  }
  return assert(ok, "out-of-range accessors return -1; page_count tracks pages");
}

fn t17() -> TestResult {
  let d = two_pages();
  var ok = err_bool_is(ogg_page_crc_ok(&d, -1), "ogg: page index out of range");
  if !err_bool_is(ogg_page_crc_ok(&d, 2), "ogg: page index out of range") { ok = false; }
  if !err_bool_is(ogg_page_crc_ok(&d, 99), "ogg: page index out of range") { ok = false; }
  return assert(ok, "crc_ok out-of-range page index is Err");
}

fn t18() -> TestResult {
  var lacing = Vec[Int].new();
  var body = Vec[UInt8].new();
  let raw = mk_page(6, 0, 99, 7, &lacing, &body);
  var ok = raw.len() == 27;
  if ogg_crc32(&raw) != 4017816242 { ok = false; }
  let d = with_crc(raw);
  let r = ogg_parse_pages(&d);
  if !r.is_ok {
    ok = false;
  } else {
    let p = r.value;
    let size0: Int = p.sizes[0];
    let flag0: Int = p.flags[0];
    let gran0: Int = p.granules[0];
    let ser0: Int = p.serials[0];
    let seq0: Int = p.sequences[0];
    if ogg_page_count(&p) != 1 { ok = false; }
    if size0 != 27 { ok = false; }
    if flag0 != 6 { ok = false; }
    if gran0 != 0 { ok = false; }
    if ser0 != 99 { ok = false; }
    if seq0 != 7 { ok = false; }
    let c = ogg_page_crc_ok(&d, 0);
    if !c.is_ok { ok = false; } elif !c.value { ok = false; }
  }
  return assert(ok, "zero-segment page is valid (27 bytes)");
}

fn t19() -> TestResult {
  var lacing = Vec[Int].new();
  lacing.push(255);
  lacing.push(255);
  lacing.push(1);
  let body = pattern(511, 3);
  let raw = mk_page(4, 55, 9, 2, &lacing, &body);
  var ok = raw.len() == 541;
  if ogg_crc32(&raw) != 1086650952 { ok = false; }
  let d = with_crc(raw);
  let r = ogg_parse_pages(&d);
  if !r.is_ok {
    ok = false;
  } else {
    let p = r.value;
    let size0: Int = p.sizes[0];
    let gran0: Int = p.granules[0];
    let ser0: Int = p.serials[0];
    let seq0: Int = p.sequences[0];
    if ogg_page_count(&p) != 1 { ok = false; }
    if size0 != 541 { ok = false; }
    if gran0 != 55 { ok = false; }
    if ser0 != 9 { ok = false; }
    if seq0 != 2 { ok = false; }
    let c = ogg_page_crc_ok(&d, 0);
    if !c.is_ok { ok = false; } elif !c.value { ok = false; }
  }
  return assert(ok, "511-byte body across 3 lacing values (size 541)");
}

fn t20() -> TestResult {
  var lacing = Vec[Int].new();
  lacing.push(1);
  var body = Vec[UInt8].new();
  body.push(0 as UInt8);
  let neg = with_crc(mk_page(0, -1, 5, 9, &lacing, &body));
  let big = with_crc(mk_page(0, 1234605616436508552, 5, 9, &lacing, &body));
  let r1 = ogg_parse_pages(&neg);
  let r2 = ogg_parse_pages(&big);
  var ok = r1.is_ok;
  if !r1.is_ok {
    ok = false;
  } else {
    let p1 = r1.value;
    let g0: Int = p1.granules[0];
    if g0 != 9223372036854775807 { ok = false; }
  }
  if !r2.is_ok {
    ok = false;
  } else {
    let p2 = r2.value;
    let g1: Int = p2.granules[0];
    if g1 != 1234605616436508552 { ok = false; }
  }
  return assert(ok, "granule position clamps to Int max, wide values survive");
}

fn t21() -> TestResult {
  let d = three_pages();
  var ok = d.len() == 88;
  let r = ogg_parse_pages(&d);
  if !r.is_ok {
    ok = false;
  } else {
    let p = r.value;
    let off1: Int = p.offsets[1];
    let off2: Int = p.offsets[2];
    let f0: Int = p.flags[0];
    let f1: Int = p.flags[1];
    let f2: Int = p.flags[2];
    let g2: Int = p.granules[2];
    let s0: Int = p.serials[0];
    let s1: Int = p.serials[1];
    let s2: Int = p.serials[2];
    let q0: Int = p.sequences[0];
    let q1: Int = p.sequences[1];
    let q2: Int = p.sequences[2];
    if ogg_page_count(&p) != 3 { ok = false; }
    if off1 != 29 { ok = false; }
    if off2 != 59 { ok = false; }
    if f0 != 2 { ok = false; }
    if f1 != 2 { ok = false; }
    if f2 != 4 { ok = false; }
    if g2 != 100 { ok = false; }
    if s0 != 11 { ok = false; }
    if s1 != 22 { ok = false; }
    if s2 != 11 { ok = false; }
    if q0 != 0 { ok = false; }
    if q1 != 0 { ok = false; }
    if q2 != 1 { ok = false; }
  }
  return assert(ok, "multiplexed pages keep order and per-page identities");
}

fn t22() -> TestResult {
  let d = three_pages();
  let corrupt = set_byte(d, 57, 99);
  let r0 = ogg_page_crc_ok(&corrupt, 0);
  let r1 = ogg_page_crc_ok(&corrupt, 1);
  let r2 = ogg_page_crc_ok(&corrupt, 2);
  var ok = r0.is_ok;
  if !r0.is_ok { ok = false; } elif !r0.value { ok = false; }
  if !r1.is_ok { ok = false; } elif r1.value { ok = false; }
  if !r2.is_ok { ok = false; } elif !r2.value { ok = false; }
  return assert(ok, "crc_ok verifies only the selected page");
}

fn main() -> Int {
  io.println("=== xiom.ogg conformance tests ===");
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
    io.println("xiom.ogg: all tests passed");
  } else {
    io.println("xiom.ogg: tests failed");
  }
  return failed;
}
