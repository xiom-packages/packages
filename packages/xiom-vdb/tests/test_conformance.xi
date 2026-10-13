// XIOM -- xiom.vdb conformance tests
// Port task: prove the pure-XIOM OpenVDB ".vdb" container reader.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Fixtures are assembled byte by byte from the documented OpenVDB layout
// (see SPEC.md), independently of src/vdb.xi. The zlib streams embedded
// below were produced with CPython 3.7's zlib module (an independent
// implementation): `zlib.compress(payload, 6)` for the dense/sparse leaf
// payloads and `zlib.compressobj(...)` for the stored-block, fixed-Huffman
// and dynamic-Huffman vectors; each stream was decompressed in Python and
// compared byte-for-byte with its expected payload at generation time.
// Str equality goes through compare.str_compare (BUG 17 discipline).
//
// Pinned independently computed values:
//   adler32("")          = 1
//   adler32("123456789") = 152961502 (0x091E01DE)
//   adler32(z_dyn_raw)   = 3366075432 (0xC8A23C28)
//   z_dense -> 2048 bytes; z_sparse -> 684 bytes; z_dyn_raw -> 200 bytes

module vdb_tests

use xiom.io;
use xiom.test;
use xiom.string;
use xiom.string.compare;
use xiom.convert.itos;
use xiom.convert.ftos;
use xiom.num.float;
use xiom.vdb;

// --------------------------------------------------
//  Helpers
// --------------------------------------------------

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

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

fn push_bytes(v: &mut Vec[UInt8], src: &Vec[UInt8]) {
  var i = 0;
  while i < src.len() {
    v.push(src[i]);
    i = i + 1;
  }
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

fn push_text(v: &mut Vec[UInt8], s: Str) {
  var i = 0;
  while i < s.len() {
    v.push(string.byte_at(s, i));
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

fn err_code_bytes(r: Result[Vec[UInt8], VdbError], want: Int) -> Bool {
  if r.is_ok { return false; }
  return r.error.code == want;
}

fn err_code_tree(r: Result[VdbTree, VdbError], want: Int) -> Bool {
  if r.is_ok { return false; }
  return r.error.code == want;
}

fn err_code_leaf(r: Result[VdbLeaf, VdbError], want: Int) -> Bool {
  if r.is_ok { return false; }
  return r.error.code == want;
}

fn err_code_file(r: Result[VdbFile, VdbError], want: Int) -> Bool {
  if r.is_ok { return false; }
  return r.error.code == want;
}

fn err_code_meta(r: Result[VdbMetaMap, VdbError], want: Int) -> Bool {
  if r.is_ok { return false; }
  return r.error.code == want;
}

fn err_code_xform(r: Result[VdbTransform, VdbError], want: Int) -> Bool {
  if r.is_ok { return false; }
  return r.error.code == want;
}

fn err_code_hdr(r: Result[VdbHeader, VdbError], want: Int) -> Bool {
  if r.is_ok { return false; }
  return r.error.code == want;
}

fn err_code_str(r: Result[Str, VdbError], want: Int) -> Bool {
  if r.is_ok { return false; }
  return r.error.code == want;
}

fn err_code_int(r: Result[Int, VdbError], want: Int) -> Bool {
  if r.is_ok { return false; }
  return r.error.code == want;
}

// --------------------------------------------------
//  Embedded zlib vectors (generated with CPython zlib)
// --------------------------------------------------

// zlib level 6 of the dense 512-float payload
// 76 bytes
fn z_dense() -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  v.push(120); v.push(156); v.push(99); v.push(96); v.push(248); v.push(113); v.push(128); v.push(129); v.push(225); v.push(6);
  v.push(16); v.push(239); v.push(0); v.push(226); v.push(25); v.push(64); v.push(92); v.push(0); v.push(196); v.push(6);
  v.push(64); v.push(252); v.push(96); v.push(63); v.push(3); v.push(131); v.push(3); v.push(16); v.push(55); v.push(216);
  v.push(49); v.push(48); v.push(44); v.push(176); v.push(103); v.push(96); v.push(16); v.push(112); v.push(96); v.push(96);
  v.push(8); v.push(0); v.push(226); v.push(14); v.push(32); v.push(94); v.push(1); v.push(196); v.push(39); v.push(128);
  v.push(248); v.push(5); v.push(16); v.push(143); v.push(234); v.push(31); v.push(213); v.push(63); v.push(170); v.push(127);
  v.push(84); v.push(255); v.push(168); v.push(254); v.push(81); v.push(253); v.push(163); v.push(250); v.push(135); v.push(154);
  v.push(126); v.push(0); v.push(74); v.push(154); v.push(39); v.push(127);
  return v;
}

// zlib level 6 of the 171 sparse active float values
// 38 bytes
fn z_sparse() -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  v.push(120); v.push(156); v.push(99); v.push(96); v.push(96); v.push(176); v.push(103); v.push(96); v.push(72); v.push(112);
  v.push(96); v.push(96); v.push(184); v.push(0); v.push(196); v.push(10); v.push(64); v.push(188); v.push(1); v.push(136);
  v.push(15); v.push(0); v.push(197); v.push(38); v.push(0); v.push(233); v.push(81); v.push(185); v.push(81); v.push(185);
  v.push(193); v.push(35); v.push(7); v.push(0); v.push(244); v.push(96); v.push(123); v.push(64);
  return v;
}

// zlib of the empty payload
// 8 bytes
fn z_empty() -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  v.push(120); v.push(156); v.push(3); v.push(0); v.push(0); v.push(0); v.push(0); v.push(1);
  return v;
}

// zlib level 0 (stored block) of 'stored block payload!'
// 32 bytes
fn z_stored() -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  v.push(120); v.push(1); v.push(1); v.push(21); v.push(0); v.push(234); v.push(255); v.push(115); v.push(116); v.push(111);
  v.push(114); v.push(101); v.push(100); v.push(32); v.push(98); v.push(108); v.push(111); v.push(99); v.push(107); v.push(32);
  v.push(112); v.push(97); v.push(121); v.push(108); v.push(111); v.push(97); v.push(100); v.push(33); v.push(90); v.push(38);
  v.push(7); v.push(232);
  return v;
}

// zlib Z_FIXED strategy of 'fixed huffman hello hello hello hello'
// 28 bytes
fn z_fixed() -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  v.push(120); v.push(1); v.push(75); v.push(203); v.push(172); v.push(72); v.push(77); v.push(81); v.push(200); v.push(40);
  v.push(77); v.push(75); v.push(203); v.push(77); v.push(204); v.push(83); v.push(200); v.push(72); v.push(205); v.push(201);
  v.push(201); v.push(199); v.push(36); v.push(1); v.push(8); v.push(115); v.push(13); v.push(230);
  return v;
}

// zlib level 9 of a 200-byte skewed payload (dynamic-Huffman block)
// 161 bytes
fn z_dyn() -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  v.push(120); v.push(218); v.push(21); v.push(139); v.push(77); v.push(111); v.push(1); v.push(81); v.push(0); v.push(69);
  v.push(255); v.push(202); v.push(17); v.push(68); v.push(164); v.push(105); v.push(45); v.push(48); v.push(102); v.push(161);
  v.push(31); v.push(73); v.push(43); v.push(8); v.push(193); v.push(76); v.push(99); v.push(209); v.push(141); v.push(208);
  v.push(190); v.push(187); v.push(153); v.push(132); v.push(134); v.push(92); v.push(43); v.push(143); v.push(223); v.push(238);
  v.push(89); v.push(156); v.push(155); v.push(115); v.push(22); v.push(87); v.push(61); v.push(126); v.push(219); v.push(140);
  v.push(44); v.push(56); v.push(54); v.push(69); v.push(137); v.push(228); v.push(188); v.push(72); v.push(243); v.push(103);
  v.push(57); v.push(227); v.push(60); v.push(136); v.push(108); v.push(113); v.push(94); v.push(218); v.push(85); v.push(254);
  v.push(164); v.push(111); v.push(71); v.push(10); v.push(100); v.push(211); v.push(114); v.push(220); v.push(136); v.push(253);
  v.push(69); v.push(111); v.push(25); v.push(166); v.push(124); v.push(149); v.push(195); v.push(191); v.push(75); v.push(248);
  v.push(249); v.push(212); v.push(218); v.push(212); v.push(87); v.push(179); v.push(134); v.push(207); v.push(178); v.push(116);
  v.push(0); v.push(81); v.push(125); v.push(152); v.push(231); v.push(101); v.push(146); v.push(156); v.push(77); v.push(38);
  v.push(3); v.push(221); v.push(196); v.push(222); v.push(244); v.push(11); v.push(7); v.push(240); v.push(188); v.push(209);
  v.push(212); v.push(251); v.push(86); v.push(113); v.push(181); v.push(75); v.push(193); v.push(238); v.push(113); v.push(9);
  v.push(74); v.push(198); v.push(87); v.push(226); v.push(96); v.push(78); v.push(87); v.push(79); v.push(83); v.push(43);
  v.push(28); v.push(83); v.push(79); v.push(42); v.push(213); v.push(196); v.push(203); v.push(162); v.push(37); v.push(13);
  v.push(237); v.push(91); v.push(68); v.push(157); v.push(98); v.push(28); v.push(238); v.push(200); v.push(162); v.push(60);
  v.push(40);
  return v;
}

// raw payload of z_dyn (pinned from the generator)
// 200 bytes
fn z_dyn_raw() -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  v.push(101); v.push(52); v.push(32); v.push(98); v.push(41); v.push(32); v.push(69); v.push(116); v.push(101); v.push(32);
  v.push(32); v.push(113); v.push(37); v.push(101); v.push(32); v.push(82); v.push(32); v.push(101); v.push(101); v.push(116);
  v.push(56); v.push(81); v.push(101); v.push(101); v.push(116); v.push(99); v.push(116); v.push(101); v.push(116); v.push(54);
  v.push(32); v.push(117); v.push(55); v.push(124); v.push(32); v.push(96); v.push(32); v.push(116); v.push(56); v.push(82);
  v.push(116); v.push(116); v.push(106); v.push(56); v.push(43); v.push(101); v.push(83); v.push(116); v.push(124); v.push(32);
  v.push(81); v.push(32); v.push(101); v.push(116); v.push(116); v.push(32); v.push(39); v.push(116); v.push(124); v.push(94);
  v.push(101); v.push(32); v.push(109); v.push(123); v.push(101); v.push(62); v.push(54); v.push(32); v.push(116); v.push(32);
  v.push(82); v.push(61); v.push(101); v.push(116); v.push(100); v.push(111); v.push(116); v.push(82); v.push(32); v.push(32);
  v.push(89); v.push(67); v.push(101); v.push(85); v.push(116); v.push(32); v.push(35); v.push(80); v.push(75); v.push(36);
  v.push(116); v.push(117); v.push(101); v.push(116); v.push(101); v.push(101); v.push(110); v.push(32); v.push(32); v.push(101);
  v.push(32); v.push(106); v.push(64); v.push(116); v.push(32); v.push(45); v.push(79); v.push(32); v.push(101); v.push(32);
  v.push(56); v.push(32); v.push(94); v.push(54); v.push(101); v.push(116); v.push(32); v.push(32); v.push(32); v.push(51);
  v.push(32); v.push(32); v.push(32); v.push(109); v.push(116); v.push(32); v.push(53); v.push(81); v.push(116); v.push(100);
  v.push(32); v.push(32); v.push(116); v.push(76); v.push(36); v.push(37); v.push(101); v.push(63); v.push(96); v.push(101);
  v.push(124); v.push(80); v.push(97); v.push(32); v.push(32); v.push(116); v.push(32); v.push(97); v.push(32); v.push(32);
  v.push(101); v.push(32); v.push(100); v.push(101); v.push(32); v.push(116); v.push(32); v.push(32); v.push(68); v.push(116);
  v.push(32); v.push(32); v.push(110); v.push(116); v.push(32); v.push(114); v.push(125); v.push(116); v.push(73); v.push(101);
  v.push(32); v.push(116); v.push(101); v.push(100); v.push(113); v.push(116); v.push(32); v.push(32); v.push(72); v.push(106);
  v.push(101); v.push(33); v.push(101); v.push(32); v.push(46); v.push(78); v.push(39); v.push(101); v.push(101); v.push(60);
  v.push(116); v.push(116); v.push(126); v.push(124); v.push(32); v.push(101); v.push(47); v.push(81); v.push(71); v.push(100);
  return v;
}

// f32 packing of the dense pattern A(i) = (i % 16) - 8 + 0.25 (exactly
// representable in binary32), built with the test-side packer below.
fn expected_dense_payload() -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < 512 {
    put_f32(&mut v, ((i % 16) - 8) as Float64 + 0.25);
    i = i + 1;
  }
  return v;
}

// f32 packing of the sparse active pattern S(k) = (3*k % 7) + 0.5 for the
// 171 active offsets 3*k (active when i % 3 == 0).
fn expected_sparse_payload() -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var k = 0;
  while k < 171 {
    put_f32(&mut v, ((3 * k) % 7) as Float64 + 0.5);
    k = k + 1;
  }
  return v;
}

// --------------------------------------------------
//  Test-side IEEE-754 packers (independent of src/vdb.xi)
// --------------------------------------------------

fn f32_bits_exact(x: Float64) -> Int {
  let b: Int = float_bits(x);
  let sign: Int = (b >> 63) & 1;
  let exp: Int = (b >> 52) & 2047;
  let man: Int = b & 4503599627370495;
  if exp == 0 && man == 0 {
    if sign == 1 { return 0 - 2147483648; }
    return 0;
  }
  let exp32: Int = exp - 1023 + 127;
  let man32: Int = man / 536870912;
  return sign * 2147483648 + exp32 * 8388608 + man32;
}

fn f16_bits_exact(x: Float64) -> Int {
  let b: Int = float_bits(x);
  let sign: Int = (b >> 63) & 1;
  let exp: Int = (b >> 52) & 2047;
  let man: Int = b & 4503599627370495;
  if exp == 0 && man == 0 {
    if sign == 1 { return 32768; }
    return 0;
  }
  let exp5: Int = exp - 1023 + 15;
  let man10: Int = man / 4398046511104;
  return sign * 32768 + exp5 * 1024 + man10;
}

fn put_f32(v: &mut Vec[UInt8], x: Float64) {
  push_le(v, f32_bits_exact(x), 4);
}

fn put_f16(v: &mut Vec[UInt8], x: Float64) {
  push_le(v, f16_bits_exact(x), 2);
}

fn put_f64(v: &mut Vec[UInt8], x: Float64) {
  push_le(v, float_bits(x), 8);
}

fn put_str(v: &mut Vec[UInt8], s: Str) {
  push_le(v, s.len(), 4);
  push_text(v, s);
}

// --------------------------------------------------
//  t1..t12 -- Adler-32 and inflate
// --------------------------------------------------

fn t1() -> TestResult {
  let empty = zeros(0);
  let ascii9 = expected_ascii("123456789");
  let raw = z_dyn_raw();
  let a0 = vdb_adler32(&empty);
  let a1 = vdb_adler32(&ascii9);
  let a2 = vdb_adler32(&raw);
  var ok = a0 == 1;
  if a1 != 152961502 { ok = false; }
  if a2 != 3366075432 { ok = false; }
  return assert(ok, "adler32 matches the pinned Python-computed values");
}

fn expected_ascii(s: Str) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  push_text(&mut v, s);
  return v;
}

fn t2() -> TestResult {
  let z = z_empty();
  let r = vdb_zip_inflate(&z, 0);
  var ok = r.is_ok;
  if r.is_ok {
    let out: Vec[UInt8] = r.value;
    if out.len() != 0 { ok = false; }
  }
  return assert(ok, "inflate of the empty zlib stream yields 0 bytes");
}

fn t3() -> TestResult {
  let z = z_stored();
  let r = vdb_zip_inflate(&z, 21);
  var ok = r.is_ok;
  if r.is_ok {
    let out: Vec[UInt8] = r.value;
    if !streq(Str::from_utf8(out), "stored block payload!") { ok = false; }
  }
  return assert(ok, "inflate of a stored-block stream");
}

fn t4() -> TestResult {
  let z = z_fixed();
  let r = vdb_zip_inflate(&z, 37);
  var ok = r.is_ok;
  if r.is_ok {
    let out: Vec[UInt8] = r.value;
    if !streq(Str::from_utf8(out), "fixed huffman hello hello hello hello") { ok = false; }
  }
  return assert(ok, "inflate of a fixed-Huffman stream");
}

fn t5() -> TestResult {
  let z = z_dyn();
  let r = vdb_zip_inflate(&z, 200);
  var ok = r.is_ok;
  if r.is_ok {
    let out: Vec[UInt8] = r.value;
    let want = z_dyn_raw();
    if out.len() != want.len() { ok = false; }
    var i = 0;
    while i < want.len() && ok {
      let a: UInt8 = out[i];
      let b: UInt8 = want[i];
      if a != b { ok = false; }
      i = i + 1;
    }
  }
  return assert(ok, "inflate of a dynamic-Huffman stream yields the pinned 200 bytes");
}

fn t6() -> TestResult {
  let dense = expected_dense_payload();
  let z = z_dense();
  let r = vdb_zip_inflate(&z, 2048);
  var ok = r.is_ok && dense.len() == 2048;
  if r.is_ok {
    let out: Vec[UInt8] = r.value;
    if out.len() != dense.len() { ok = false; }
    var i = 0;
    while i < dense.len() && ok {
      let a: UInt8 = out[i];
      let b: UInt8 = dense[i];
      if a != b { ok = false; }
      i = i + 1;
    }
  }
  return assert(ok, "inflate of the dense leaf payload equals the test-side f32 packing");
}

fn t7() -> TestResult {
  let sparse = expected_sparse_payload();
  let z = z_sparse();
  let r = vdb_zip_inflate(&z, 684);
  var ok = r.is_ok && sparse.len() == 684;
  if r.is_ok {
    let out: Vec[UInt8] = r.value;
    if out.len() != sparse.len() { ok = false; }
    var i = 0;
    while i < sparse.len() && ok {
      let a: UInt8 = out[i];
      let b: UInt8 = sparse[i];
      if a != b { ok = false; }
      i = i + 1;
    }
  }
  return assert(ok, "inflate of the sparse active-value payload equals the test-side packing");
}

fn t8() -> TestResult {
  let z = z_dense();
  let truncated = prefix(z, 40);
  let short = prefix(z, 1);
  let bad = set_byte(z, 0, 0x77);
  let bad2 = set_byte(z, 1, 0x00);
  let fd = set_byte(set_byte(z, 0, 0x78), 1, 0x20);
  var ok = err_code_bytes(vdb_zip_inflate(&truncated, 2048), VDB_ERR_ZIP_INVALID);
  if !err_code_bytes(vdb_zip_inflate(&short, 2048), VDB_ERR_ZIP_INVALID) { ok = false; }
  if !err_code_bytes(vdb_zip_inflate(&bad, 2048), VDB_ERR_ZIP_INVALID) { ok = false; }
  if !err_code_bytes(vdb_zip_inflate(&bad2, 2048), VDB_ERR_ZIP_INVALID) { ok = false; }
  if !err_code_bytes(vdb_zip_inflate(&fd, 2048), VDB_ERR_ZIP_INVALID) { ok = false; }
  return assert(ok, "corrupt zlib headers and truncated streams are typed ZIP_INVALID errors");
}

fn t9() -> TestResult {
  let z = z_dense();
  let last: Int = z.len() - 1;
  let bad_adler = set_byte(z, last, (byte_of(z[last] as Int, 0) as Int) ^ 1);
  let z2 = z_dense();
  var ok = err_code_bytes(vdb_zip_inflate(&bad_adler, 2048), VDB_ERR_ZIP_ADLER);
  if !err_code_bytes(vdb_zip_inflate(&z2, 2047), VDB_ERR_ZIP_INVALID) { ok = false; }
  if !err_code_bytes(vdb_zip_inflate(&z2, 2049), VDB_ERR_ZIP_INVALID) { ok = false; }
  return assert(ok, "Adler mismatch and size mismatch are distinct typed errors");
}

fn t10() -> TestResult {
  let z = z_dense();
  let ok = err_code_bytes(vdb_zip_inflate(&z, 33554433), VDB_ERR_LIMIT_EXCEEDED);
  return assert(ok, "inflate output beyond the 16 MiB cap is a typed LIMIT error");
}

// --------------------------------------------------
//  Hand-built ".vdb" fixtures (documented layout)
// --------------------------------------------------
//
// Every fixture below is assembled byte by byte from the OpenVDB layout
// documented in SPEC.md. Node masks, mask-compression metadata bytes,
// inactive-value records, selection masks and value chunks are written
// exactly as the reader consumes them; the writer here is test-local and
// has no shared code with src/vdb.xi.

fn A(i: Int) -> Float64 {
  return ((i % 16) - 8) as Float64 + 0.25;
}

fn S(k: Int) -> Float64 {
  return ((3 * k) % 7) as Float64 + 0.5;
}

fn H(i: Int) -> Float64 {
  return ((i % 8) - 4) as Float64 + 0.5;
}

fn V(i: Int, c: Int) -> Float64 {
  return ((i % 4) + c) as Float64;
}

fn V2(i: Int, c: Int) -> Float64 {
  return 10.0 + ((i % 4) + c) as Float64;
}

fn bits_vec(x: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(x);
  return v;
}

fn bits_range_upto(n: Int, step: Int, rem: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  var i = 0;
  while i < n {
    if i % step == rem {
      v.push(i);
    }
    i = i + 1;
  }
  return v;
}

// Mask of `size_bits` bits with the given offsets turned on.
fn mask_of(bits_on: &Vec[Int], size_bits: Int) -> Vec[UInt8] {
  var m = zeros(size_bits / 8);
  var i = 0;
  while i < bits_on.len() {
    let b: Int = bits_on[i];
    let byte_i: Int = b / 8;
    let cur: UInt8 = m[byte_i];
    m[byte_i] = ((cur as Int) | (1 << (b % 8))) as UInt8;
    i = i + 1;
  }
  return m;
}

fn mask_all_on() -> Vec[UInt8] {
  var m = Vec[UInt8].new();
  push_zeros(&mut m, 64);
  var i = 0;
  while i < 64 {
    m[i] = 255 as UInt8;
    i = i + 1;
  }
  return m;
}

// Active offsets i with i % 3 == 0 (171 of 512) -- the sparse leaf mask.
fn mask_sparse() -> Vec[UInt8] {
  let bits = bits_range_upto(512, 3, 0);
  return mask_of(&bits, 512);
}

// Selection-mask offsets i with i % 2 == 0 (used by metadata 3 leaves).
fn mask_sel() -> Vec[UInt8] {
  let bits = bits_range_upto(512, 2, 0);
  return mask_of(&bits, 512);
}

fn mask_is_on(m: &Vec[UInt8], i: Int) -> Bool {
  let byte_i: Int = i / 8;
  let b: UInt8 = m[byte_i];
  return ((((b as Int) & 0xFF) >> (i % 8)) % 2) == 1;
}

fn mask_count(m: &Vec[UInt8]) -> Int {
  var n = 0;
  var i = 0;
  while i < 512 {
    if mask_is_on(m, i) {
      n = n + 1;
    }
    i = i + 1;
  }
  return n;
}

fn put_i32(v: &mut Vec[UInt8], x: Int) {
  push_le(v, x, 4);
}

fn put_i64(v: &mut Vec[UInt8], x: Int) {
  push_le(v, x, 8);
}

fn put_vec3d(v: &mut Vec[UInt8], a: Float64, b: Float64, c: Float64) {
  put_f64(v, a);
  put_f64(v, b);
  put_f64(v, c);
}

fn put_vec3f(v: &mut Vec[UInt8], a: Float64, b: Float64, c: Float64) {
  put_f32(v, a);
  put_f32(v, b);
  put_f32(v, c);
}

fn put_meta_string(v: &mut Vec[UInt8], name: Str, value: Str) {
  put_str(v, name);
  put_str(v, "string");
  put_i32(v, value.len());
  push_text(v, value);
}

fn put_meta_int32(v: &mut Vec[UInt8], name: Str, value: Int) {
  put_str(v, name);
  put_str(v, "int32");
  put_i32(v, 4);
  put_i32(v, value);
}

fn put_meta_bool(v: &mut Vec[UInt8], name: Str, value: Bool) {
  put_str(v, name);
  put_str(v, "bool");
  put_i32(v, 1);
  if value {
    v.push(1 as UInt8);
  } else {
    v.push(0 as UInt8);
  }
}

fn put_meta_float(v: &mut Vec[UInt8], name: Str, value: Float64) {
  put_str(v, name);
  put_str(v, "float");
  put_i32(v, 4);
  put_f32(v, value);
}

fn put_meta_double(v: &mut Vec[UInt8], name: Str, value: Float64) {
  put_str(v, name);
  put_str(v, "double");
  put_i32(v, 8);
  put_f64(v, value);
}

fn put_header(v: &mut Vec[UInt8], version: Int, major: Int, minor: Int, has_offsets: Bool, uuid: Str) {
  push_le(v, VDB_MAGIC, 8);
  push_le(v, version, 4);
  push_le(v, major, 4);
  push_le(v, minor, 4);
  if has_offsets {
    v.push(1 as UInt8);
  } else {
    v.push(0 as UInt8);
  }
  push_text(v, uuid);
}

// File-level MetaMap: creator (string) and a pinned int32.
fn put_file_meta(v: &mut Vec[UInt8]) {
  put_i32(v, 2);
  put_meta_string(v, "creator", "xiom-vdb-tests");
  put_meta_int32(v, "file_int", 42);
}

fn xf_uniform_scale(s: Float64) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  put_str(&mut v, "UniformScaleMap");
  put_vec3d(&mut v, s, s, s);
  put_vec3d(&mut v, s, s, s);
  put_vec3d(&mut v, 2.0, 2.0, 2.0);
  put_vec3d(&mut v, 4.0, 4.0, 4.0);
  put_vec3d(&mut v, 1.0, 1.0, 1.0);
  return v;
}

fn xf_scale_translate(tx: Float64, ty: Float64, tz: Float64) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  put_str(&mut v, "UniformScaleTranslateMap");
  put_vec3d(&mut v, tx, ty, tz);
  put_vec3d(&mut v, 2.0, 2.0, 2.0);
  put_vec3d(&mut v, 2.0, 2.0, 2.0);
  put_vec3d(&mut v, 0.5, 0.5, 0.5);
  put_vec3d(&mut v, 0.25, 0.25, 0.25);
  put_vec3d(&mut v, 0.25, 0.25, 0.25);
  return v;
}

fn xf_translation(tx: Float64, ty: Float64, tz: Float64) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  put_str(&mut v, "TranslationMap");
  put_vec3d(&mut v, tx, ty, tz);
  return v;
}

// Row-major 4x4 with diagonal `s` and translation (tx, ty, tz).
fn xf_affine_diag(s: Float64, tx: Float64, ty: Float64, tz: Float64) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  put_str(&mut v, "AffineMap");
  put_f64(&mut v, s); put_f64(&mut v, 0.0); put_f64(&mut v, 0.0); put_f64(&mut v, tx);
  put_f64(&mut v, 0.0); put_f64(&mut v, s); put_f64(&mut v, 0.0); put_f64(&mut v, ty);
  put_f64(&mut v, 0.0); put_f64(&mut v, 0.0); put_f64(&mut v, s); put_f64(&mut v, tz);
  put_f64(&mut v, 0.0); put_f64(&mut v, 0.0); put_f64(&mut v, 0.0); put_f64(&mut v, 1.0);
  return v;
}

// Value chunk after a node's metadata: mode 0 = raw, 1 = zip flags,
// 2 = blosc flags. With compression flags the test writer always emits the
// raw fallback form (negative i64 prefix + raw bytes), which the format
// defines for both zip and blosc; an active-less node under zip writes the
// 8-byte zlib stream of the empty payload (matching compress2 output).
fn put_chunk(v: &mut Vec<UInt8>, payload: &Vec[UInt8], mode: Int) {
  if mode == 0 {
    push_bytes(v, payload);
    return;
  }
  if payload.len() == 0 {
    if mode == 1 {
      put_i64(v, 8);
      push_bytes(v, &z_empty());
    }
    return;
  }
  put_i64(v, 0 - payload.len());
  push_bytes(v, payload);
}

// L5 internal node (32768-bit masks) with one child and at most one active
// tile. Metadata 2 (one saved inactive value 0.0 + active-only payload).
fn l5_f32(child_bit: Int, on_bit: Int, tile: Float64, mode: Int, half: Bool, child: &Vec[UInt8]) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  push_bytes(&mut v, &mask_of(&bits_vec(child_bit), 32768));
  var on_bits = Vec[Int].new();
  if on_bit >= 0 {
    on_bits.push(on_bit);
  }
  push_bytes(&mut v, &mask_of(&on_bits, 32768));
  v.push(2 as UInt8);
  put_f32(&mut v, 0.0);
  if on_bit >= 0 {
    var payload = Vec[UInt8].new();
    if half {
      put_f16(&mut payload, tile);
    } else {
      put_f32(&mut payload, tile);
    }
    put_chunk(&mut v, &payload, mode);
  } else {
    var empty = Vec[UInt8].new();
    put_chunk(&mut v, &empty, mode);
  }
  push_bytes(&mut v, child);
  return v;
}

// L4 internal node (4096-bit masks); `leaf_topo` is the concatenated
// 64-byte masks of its leaf children in child-offset order.
fn l4_f32(child_bits: &Vec[Int], on_bit: Int, tile: Float64, mode: Int, half: Bool, leaf_topo: &Vec[UInt8]) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  push_bytes(&mut v, &mask_of(child_bits, 4096));
  var on_bits = Vec[Int].new();
  if on_bit >= 0 {
    on_bits.push(on_bit);
  }
  push_bytes(&mut v, &mask_of(&on_bits, 4096));
  v.push(2 as UInt8);
  put_f32(&mut v, 0.0);
  if on_bit >= 0 {
    var payload = Vec[UInt8].new();
    if half {
      put_f16(&mut payload, tile);
    } else {
      put_f32(&mut payload, tile);
    }
    put_chunk(&mut v, &payload, mode);
  } else {
    var empty = Vec[UInt8].new();
    put_chunk(&mut v, &empty, mode);
  }
  push_bytes(&mut v, leaf_topo);
  return v;
}

// Vec3s (vec3f) internal nodes: no active tiles; the single saved inactive
// value is the zero vector (12 logical bytes), which differs from the
// background. mode is only ever 0 here.
fn l5_vec(child_bit: Int, child: &Vec[UInt8]) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  push_bytes(&mut v, &mask_of(&bits_vec(child_bit), 32768));
  push_bytes(&mut v, &zeros(4096));
  v.push(2 as UInt8);
  push_zeros(&mut v, 12);
  push_bytes(&mut v, child);
  return v;
}

fn l4_vec(child_bits: &Vec<Int>, leaf_topo: &Vec<UInt8>) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  push_bytes(&mut v, &mask_of(child_bits, 4096));
  push_bytes(&mut v, &zeros(512));
  v.push(2 as UInt8);
  push_zeros(&mut v, 12);
  push_bytes(&mut v, leaf_topo);
  return v;
}

// Leaf buffer: mask + metadata + optional records + value chunk.
fn leaf_meta0_raw(mask: &Vec[UInt8], payload: &Vec<UInt8>) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  push_bytes(&mut v, mask);
  v.push(0 as UInt8);
  push_bytes(&mut v, payload);
  return v;
}

fn leaf_meta0_zip(mask: &Vec<UInt8>, z: &Vec<UInt8>) -> Vec<UInt8> {
  var v = Vec[UInt8].new();
  push_bytes(&mut v, mask);
  v.push(0 as UInt8);
  put_i64(&mut v, z.len());
  push_bytes(&mut v, z);
  return v;
}

fn leaf_meta3_raw(mask: &Vec[UInt8], sel: &Vec<UInt8>, payload: &Vec<UInt8>) -> Vec<UInt8> {
  var v = Vec[UInt8].new();
  push_bytes(&mut v, mask);
  v.push(3 as UInt8);
  push_bytes(&mut v, sel);
  push_bytes(&mut v, payload);
  return v;
}

fn leaf_meta3_zip(mask: &Vec<UInt8>, sel: &Vec<UInt8>, z: &Vec<UInt8>) -> Vec<UInt8> {
  var v = Vec[UInt8].new();
  push_bytes(&mut v, mask);
  v.push(3 as UInt8);
  push_bytes(&mut v, sel);
  put_i64(&mut v, z.len());
  push_bytes(&mut v, z);
  return v;
}

// Tree topology: buffer count 1, f32 background, optional root tile,
// one root child at the origin.
fn topo_f32(bg: Float64, with_tile: Bool, child: &Vec[UInt8]) -> Vec<UInt8] {
  var v = Vec[UInt8].new();
  put_i32(&mut v, 1);
  put_f32(&mut v, bg);
  if with_tile {
    put_i32(&mut v, 1);
  } else {
    put_i32(&mut v, 0);
  }
  put_i32(&mut v, 1);
  if with_tile {
    put_i32(&mut v, 0); put_i32(&mut v, 0); put_i32(&mut v, 0);
    put_f32(&mut v, 1.0);
    v.push(1 as UInt8);
  }
  put_i32(&mut v, 0); put_i32(&mut v, 0); put_i32(&mut v, 0);
  push_bytes(&mut v, child);
  return v;
}

// Tree topology with no tiles and no children at all (empty grid).
fn topo_empty(bg: Float64) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  put_i32(&mut v, 1);
  put_f32(&mut v, bg);
  put_i32(&mut v, 0);
  put_i32(&mut v, 0);
  return v;
}

// Tree topology with a vec3f background, no root tiles, one root child.
fn topo_vec(bg: Float64, child: &Vec<UInt8>) -> Vec<UInt8> {
  var v = Vec[UInt8].new();
  put_i32(&mut v, 1);
  put_vec3f(&mut v, bg, bg, bg);
  put_i32(&mut v, 0);
  put_i32(&mut v, 1);
  put_i32(&mut v, 0); put_i32(&mut v, 0); put_i32(&mut v, 0);
  push_bytes(&mut v, child);
  return v;
}

// Value payloads built from the deterministic patterns.
fn payload_dense() -> Vec[UInt8] {
  return expected_dense_payload();
}

fn payload_sparse() -> Vec<UInt8> {
  return expected_sparse_payload();
}

fn payload_half() -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < 512 {
    put_f16(&mut v, H(i));
    i = i + 1;
  }
  return v;
}

fn payload_vec0() -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < 512 {
    var c = 0;
    while c < 3 {
      put_f32(&mut v, V(i, c));
      c = c + 1;
    }
    i = i + 1;
  }
  return v;
}

fn payload_vec5() -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < 512 {
    var c = 0;
    while c < 3 {
      put_f32(&mut v, V2(i, c));
      c = c + 1;
    }
    i = i + 1;
  }
  return v;
}

// Descriptor + body for a seekable grid (declared positions are exact;
// `block_delta` perturbs the declared block position for corruption tests).
fn put_desc_seek(f: &mut Vec[UInt8], name: Str, typ: Str, parent: Str,
    meta: &Vec[UInt8], xf: &Vec[UInt8], topo: &Vec[UInt8], bufs: &Vec[UInt8], comp: Int, block_delta: Int) {
  put_str(f, name);
  put_str(f, typ);
  put_str(f, parent);
  let body_start: Int = f.len() + 24;
  let block: Int = body_start + 4 + meta.len() + xf.len() + topo.len() + block_delta;
  let end: Int = body_start + 4 + meta.len() + xf.len() + topo.len() + bufs.len();
  put_i64(f, body_start);
  put_i64(f, block);
  put_i64(f, end);
  put_i32(f, comp);
  push_bytes(f, meta);
  push_bytes(f, xf);
  push_bytes(f, topo);
  push_bytes(f, bufs);
}

// Descriptor + body for a streamed (non-seekable) grid: zero positions.
fn put_desc_stream(f: &mut Vec<UInt8], name: Str, typ: Str, parent: Str,
    meta: &Vec[UInt8], xf: &Vec<UInt8], topo: &Vec<UInt8], bufs: &Vec<UInt8], comp: Int) {
  put_str(f, name);
  put_str(f, typ);
  put_str(f, parent);
  put_i64(f, 0);
  put_i64(f, 0);
  put_i64(f, 0);
  put_i32(f, comp);
  push_bytes(f, meta);
  push_bytes(f, xf);
  push_bytes(f, topo);
  push_bytes(f, bufs);
}

// Descriptor + body for an instance grid (metadata + transform only;
// block position 0, end position after the transform).
fn put_desc_instance(f: &mut Vec<UInt8], name: Str, typ: Str, parent: Str,
    meta: &Vec<UInt8], xf: &Vec<UInt8], comp: Int) {
  put_str(f, name);
  put_str(f, typ);
  put_str(f, parent);
  let body_start: Int = f.len() + 24;
  let end: Int = body_start + 4 + meta.len() + xf.len();
  put_i64(f, body_start);
  put_i64(f, 0);
  put_i64(f, end);
  put_i32(f, comp);
  push_bytes(f, meta);
  push_bytes(f, xf);
}

fn fx_density_meta() -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  put_i32(&mut v, 6);
  put_meta_string(&mut v, "class", "fog volume");
  put_meta_string(&mut v, "creator", "xiom-vdb-tests");
  put_meta_int32(&mut v, "int_meta", 7);
  put_meta_bool(&mut v, "bool_meta", true);
  put_meta_float(&mut v, "float_meta", 0.5);
  put_meta_double(&mut v, "double_meta", -2.5);
  return v;
}

// Fixture A: 225/1 offsets, 4 grids -- density (mask compression, two
// leaves, one sparse with a selection mask), zipfield (zip + active mask),
// density_copy (instance of density), empty (no tiles/children).
fn fx_a(block_delta: Int, leaf0_meta: Int) -> Vec[UInt8] {
  var f = Vec[UInt8].new();
  put_header(&mut f, 225, 13, 1, true, "01234567-89ab-cdef-0123-456789abcdef");
  put_file_meta(&mut f);
  put_i32(&mut f, 4);

  // Grid 0: density
  let d_meta = fx_density_meta();
  let d_xf = xf_uniform_scale(0.5);
  let l4 = l4_f32(&bits_sel_01(), 3, 9.0, 0, false, &concat(mask_all_on(), mask_sparse()));
  let l5 = l5_f32(0, 2, 5.0, 0, false, &l4);
  let d_topo = topo_f32(0.25, true, &l5);
  var d_bufs = Vec[UInt8].new();
  push_bytes(&mut d_bufs, &mask_all_on());
  d_bufs.push(leaf0_meta as UInt8);
  push_bytes(&mut d_bufs, &payload_dense());
  push_bytes(&mut d_bufs, &leaf_meta3_raw(&mask_sparse(), &mask_sel(), &payload_sparse()));
  put_desc_seek(&mut f, "density", "Tree_float_5_4_3", "", &d_meta, &d_xf, &d_topo, &d_bufs, 2, block_delta);

  // Grid 1: zipfield
  let z_meta = zero_meta();
  let z_xf = xf_scale_translate(1.0, 2.0, 3.0);
  let z_l4 = l4_f32(&bits_vec(0), 2, 3.0, 1, false, &mask_all_on());
  let z_l5 = l5_f32(0, 1, 4.0, 1, false, &z_l4);
  let z_topo = topo_f32(0.5, false, &z_l5);
  let z_bufs = leaf_meta0_zip(&mask_all_on(), &z_dense());
  put_desc_seek(&mut f, "zipfield", "Tree_float_5_4_3", "", &z_meta, &z_xf, &z_topo, &z_bufs, 3, 0);

  // Grid 2: density_copy (instance of density)
  let i_meta = zero_meta();
  let i_xf = xf_uniform_scale(0.5);
  put_desc_instance(&mut f, "density_copy", "Tree_float_5_4_3", "density", &i_meta, &i_xf, 2);

  // Grid 3: empty
  let e_meta = zero_meta();
  let e_xf = xf_translation(7.0, 8.0, 9.0);
  let e_topo = topo_empty(0.0);
  let e_bufs = Vec[UInt8].new();
  put_desc_seek(&mut f, "empty", "Tree_float_5_4_3", "", &e_meta, &e_xf, &e_topo, &e_bufs, 0, 0);

  return f;
}

fn zero_meta() -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  put_i32(&mut v, 0);
  return v;
}

fn bits_sel_01() -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(0);
  v.push(1);
  return v;
}

// Fixture B: 225/0 offsets (streamed), 2 grids -- half-storage float grid
// and a vec3f grid with two leaves and an AffineMap transform.
fn fx_b() -> Vec[UInt8] {
  var f = Vec[UInt8].new();
  put_header(&mut f, 225, 13, 1, false, "00000000-0000-0000-0000-000000000000");
  put_i32(&mut f, 1);
  put_meta_string(&mut f, "creator", "xiom-vdb-tests");
  put_i32(&mut f, 2);

  // Grid 0: hf (float stored as binary16 halves)
  let h_meta = fx_half_meta();
  let h_xf = xf_uniform_scale(0.25);
  let h_l4 = l4_f32(&bits_vec(0), 2, 3.0, 0, true, &mask_all_on());
  let h_l5 = l5_f32(0, 1, 2.0, 0, true, &h_l4);
  let h_topo = topo_f32(1.5, false, &h_l5);
  let h_bufs = leaf_meta0_raw(&mask_all_on(), &payload_half());
  put_desc_stream(&mut f, "hf", "Tree_float_5_4_3_HalfFloat", "", &h_meta, &h_xf, &h_topo, &h_bufs, 2);

  // Grid 1: vec (vec3f, two leaves at local z = 0 and z = 5)
  let v_meta = fx_vec_meta();
  let v_xf = xf_affine_diag(2.0, 1.0, 2.0, 3.0);
  var v_leaf_topo = Vec[UInt8].new();
  push_bytes(&mut v_leaf_topo, &mask_all_on());
  push_bytes(&mut v_leaf_topo, &mask_all_on());
  let v_l4 = l4_vec(&bits_05(), &v_leaf_topo);
  let v_l5 = l5_vec(0, &v_l4);
  let v_topo = topo_vec(0.5, &v_l5);
  var v_bufs = Vec[UInt8].new();
  push_bytes(&mut v_bufs, &leaf_meta0_raw(&mask_all_on(), &payload_vec0()));
  push_bytes(&mut v_bufs, &leaf_meta0_raw(&mask_all_on(), &payload_vec5()));
  put_desc_stream(&mut f, "vec", "Tree_vec3s_5_4_3", "", &v_meta, &v_xf, &v_topo, &v_bufs, 2);

  return f;
}

fn fx_half_meta() -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  put_i32(&mut v, 1);
  put_meta_string(&mut v, "class", "level set");
  return v;
}

fn fx_vec_meta() -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  put_i32(&mut v, 1);
  put_meta_string(&mut v, "class", "staggered");
  return v;
}

fn bits_05() -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(0);
  v.push(5);
  return v;
}

// Fixture C: 225/1, one zlib-compressed sparse leaf with a selection mask.
fn fx_c() -> Vec[UInt8] {
  var f = Vec[UInt8].new();
  put_header(&mut f, 225, 13, 1, true, "01234567-89ab-cdef-0123-456789abcdef");
  put_file_meta(&mut f);
  put_i32(&mut f, 1);
  let c_meta = fx_density_meta();
  let c_xf = xf_uniform_scale(0.5);
  let c_l4 = l4_f32(&bits_vec(0), 2, 6.0, 1, false, &mask_sparse());
  let c_l5 = l5_f32(0, 1, 5.0, 1, false, &c_l4);
  let c_topo = topo_f32(0.0, false, &c_l5);
  let c_bufs = leaf_meta3_zip(&mask_sparse(), &mask_sel(), &z_sparse());
  put_desc_seek(&mut f, "zipsparse", "Tree_float_5_4_3", "", &c_meta, &c_xf, &c_topo, &c_bufs, 3, 0);
  return f;
}

// Tiny single-grid fixture for corruption cases: leaf metadata byte
// `leaf_meta` at the top of the leaf buffer, body negotiated by `comp`.
fn fx_tiny(comp: Int, typ: Str, leaf_meta: Int, chunk: &Vec[UInt8]) -> Vec[UInt8] {
  var f = Vec[UInt8].new();
  put_header(&mut f, 225, 13, 1, true, "01234567-89ab-cdef-0123-456789abcdef");
  put_i32(&mut f, 0);
  put_i32(&mut f, 1);
  var mode = 0;
  if (comp & 4) != 0 {
    mode = 2;
  } elif (comp & 1) != 0 {
    mode = 1;
  }
  let t_meta = zero_meta();
  let t_xf = xf_uniform_scale(1.0);
  let t_l4 = l4_f32(&bits_vec(0), 1, 3.0, mode, false, &mask_all_on());
  let t_l5 = l5_f32(0, 1, 2.0, mode, false, &t_l4);
  let t_topo = topo_f32(0.0, false, &t_l5);
  var t_bufs = Vec[UInt8].new();
  push_bytes(&mut t_bufs, &mask_all_on());
  t_bufs.push(leaf_meta as UInt8);
  push_bytes(&mut t_bufs, chunk);
  put_desc_seek(&mut f, "tiny", typ, "", &t_meta, &t_xf, &t_topo, &t_bufs, comp, 0);
  return f;
}

// A blosc-framed leaf chunk: 16 opaque bytes behind a positive i64 prefix.
fn blosc_junk_chunk() -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  put_i64(&mut v, 16);
  push_zeros(&mut v, 16);
  return v;
}

// --------------------------------------------------
//  t11..t30 -- container, metadata, transform, tree, leaf, corruptions
// --------------------------------------------------

fn t11() -> TestResult {
  let a = fx_a(0, 0);
  let h = vdb_parse_header(&a);
  var ok = h.is_ok;
  if h.is_ok {
    let hd = h.value;
    if hd.file_version != 225 { ok = false; }
    if hd.library_major != 13 { ok = false; }
    if hd.library_minor != 1 { ok = false; }
    if !hd.has_grid_offsets { ok = false; }
    if !streq(hd.uuid, "01234567-89ab-cdef-0123-456789abcdef") { ok = false; }
  }
  let b = fx_b();
  let h2 = vdb_parse_header(&b);
  if h2.is_ok {
    let hd2 = h2.value;
    if hd2.has_grid_offsets { ok = false; }
  } else { ok = false; }
  let short = prefix(a, 30);
  if !err_code_hdr(vdb_parse_header(&short), VDB_ERR_TRUNCATED_HEADER) { ok = false; }
  let badmagic = set_byte(a, 0, 0);
  if !err_code_hdr(vdb_parse_header(&badmagic), VDB_ERR_BAD_MAGIC) { ok = false; }
  let v221 = set_byte(a, 8, 221);
  if !err_code_hdr(vdb_parse_header(&v221), VDB_ERR_UNSUPPORTED_VERSION) { ok = false; }
  let v226 = set_byte(a, 8, 226);
  if !err_code_hdr(vdb_parse_header(&v226), VDB_ERR_UNSUPPORTED_VERSION) { ok = false; }
  let v222 = set_byte(a, 8, 222);
  if !vdb_parse_header(&v222).is_ok { ok = false; }
  if !vdb_magic_ok(&a) { ok = false; }
  if !vdb_magic_ok(&short) { ok = false; }
  let tiny = prefix(a, 4);
  if vdb_magic_ok(&tiny) { ok = false; }
  return assert(ok, "header: magic, version range, UUID and offsets flag");
}

fn t12() -> TestResult {
  let a = fx_a(0, 0);
  let r = vdb_open(&a);
  var ok = r.is_ok;
  if r.is_ok {
    let f = r.value;
    if vdb_grid_count(&f) != 4 { ok = false; }
    if !streq(vdb_grid_name(&f, 0), "density") { ok = false; }
    if !streq(vdb_grid_name(&f, 1), "zipfield") { ok = false; }
    if !streq(vdb_grid_name(&f, 2), "density_copy") { ok = false; }
    if !streq(vdb_grid_name(&f, 3), "empty") { ok = false; }
    if !streq(vdb_grid_type(&f, 1), "Tree_float_5_4_3") { ok = false; }
    if !streq(vdb_grid_instance_parent(&f, 2), "density") { ok = false; }
    if vdb_grid_instance_parent(&f, 0).len() != 0 { ok = false; }
    if vdb_find_grid(&f, "zipfield") != 1 { ok = false; }
    if vdb_find_grid(&f, "nope") != -1 { ok = false; }
    if vdb_grid_pos(&f, 0) != vdb_grid_body_offset(&f, 0) { ok = false; }
    if vdb_grid_pos(&f, 3) != vdb_grid_body_offset(&f, 3) { ok = false; }
    if vdb_grid_block_pos(&f, 2) != 0 { ok = false; }
    if vdb_grid_end_pos(&f, 0) <= vdb_grid_pos(&f, 0) { ok = false; }
    if vdb_grid_name(&f, 9).len() != 0 { ok = false; }
    if vdb_grid_pos(&f, -1) != -1 { ok = false; }
  }
  return assert(ok, "open: descriptor table, names, instance parent, positions");
}

fn t13() -> TestResult {
  let a = fx_a(0, 0);
  let r = vdb_open(&a);
  var ok = r.is_ok;
  if r.is_ok {
    let f = r.value;
    let m: VdbMetaMap = f.meta;
    if vdb_meta_count(&m) != 2 { ok = false; }
    if !streq(vdb_meta_name(&m, 0), "creator") { ok = false; }
    if !streq(vdb_meta_type(&m, 0), "string") { ok = false; }
    let s = vdb_meta_string(&a, &m, 0);
    if s.is_ok {
      if !streq(s.value, "xiom-vdb-tests") { ok = false; }
    } else { ok = false; }
    let n = vdb_meta_int(&a, &m, 1);
    if n.is_ok {
      if n.value != 42 { ok = false; }
    } else { ok = false; }
    if vdb_meta_find(&m, "file_int") != 1 { ok = false; }
    if vdb_meta_find(&m, "absent") != -1 { ok = false; }
    if vdb_meta_value_bytes(&m, 0) != 14 { ok = false; }
    if vdb_meta_value(&a, &m, 9).is_ok { ok = false; }
    if !err_code_bytes(vdb_meta_value(&a, &m, 9), VDB_ERR_INDEX_OUT_OF_RANGE) { ok = false; }
    if !err_code_str(vdb_meta_string(&a, &m, 1), VDB_ERR_META_TYPE_MISMATCH) { ok = false; }
    if vdb_meta_name(&m, 5).len() != 0 { ok = false; }
    if vdb_meta_value_offset(&m, 5) != -1 { ok = false; }
  }
  return assert(ok, "file metadata: names, types, typed decoders, bounds");
}

fn t14() -> TestResult {
  let a = fx_a(0, 0);
  let r = vdb_open(&a);
  var ok = r.is_ok;
  if r.is_ok {
    let f = r.value;
    let gr = vdb_grid_meta(&a, &f, 0);
    if gr.is_ok {
      let m = gr.value;
      if vdb_meta_count(&m) != 6 { ok = false; }
      if vdb_meta_find(&m, "class") != 0 { ok = false; }
      let cls = vdb_meta_string(&a, &m, 0);
      if cls.is_ok {
        if !streq(cls.value, "fog volume") { ok = false; }
      } else { ok = false; }
      let iv = vdb_meta_int(&a, &m, 2);
      if iv.is_ok {
        if iv.value != 7 { ok = false; }
      } else { ok = false; }
      let bv = vdb_meta_bool(&a, &m, 3);
      if bv.is_ok {
        if !bv.value { ok = false; }
      } else { ok = false; }
      let fv = vdb_meta_float(&a, &m, 4);
      if fv.is_ok {
        if fv.value != 0.5 { ok = false; }
      } else { ok = false; }
      let dv = vdb_meta_float(&a, &m, 5);
      if dv.is_ok {
        if dv.value != (0.0 - 2.5) { ok = false; }
      } else { ok = false; }
      if !err_code_int(vdb_meta_int(&a, &m, 4), VDB_ERR_META_TYPE_MISMATCH) { ok = false; }
      if !err_code_int(vdb_meta_int(&a, &m, 8), VDB_ERR_INDEX_OUT_OF_RANGE) { ok = false; }
    } else { ok = false; }
  }
  return assert(ok, "grid metadata: class/creator/integer/bool/float/double decoding");
}

fn t15() -> TestResult {
  let a = fx_a(0, 0);
  let r = vdb_open(&a);
  var ok = r.is_ok;
  if r.is_ok {
    let f = r.value;
    let t0 = vdb_grid_transform(&a, &f, 0);
    if t0.is_ok {
      let x = t0.value;
      if !streq(x.map_type, "UniformScaleMap") { ok = false; }
      if x.map_kind != VDB_MAP_KIND_SCALE { ok = false; }
      let vx: Float64 = x.voxel_size[0];
      if vx != 0.5 { ok = false; }
    } else { ok = false; }
    let t1 = vdb_grid_transform(&a, &f, 1);
    if t1.is_ok {
      let x = t1.value;
      if x.map_kind != VDB_MAP_KIND_SCALE_TRANSLATE { ok = false; }
      let vx: Float64 = x.voxel_size[2];
      let tx: Float64 = x.translation[0];
      let tz: Float64 = x.translation[2];
      if vx != 2.0 { ok = false; }
      if tx != 1.0 { ok = false; }
      if tz != 3.0 { ok = false; }
    } else { ok = false; }
    let t3 = vdb_grid_transform(&a, &f, 3);
    if t3.is_ok {
      let x = t3.value;
      if x.map_kind != VDB_MAP_KIND_TRANSLATION { ok = false; }
      let vx: Float64 = x.voxel_size[0];
      let ty: Float64 = x.translation[1];
      if vx != 1.0 { ok = false; }
      if ty != 8.0 { ok = false; }
    } else { ok = false; }
    if !err_code_xform(vdb_grid_transform(&a, &f, 9), VDB_ERR_INDEX_OUT_OF_RANGE) { ok = false; }
  }
  return assert(ok, "transforms: uniform-scale, scale-translate, translation maps");
}

fn t16() -> TestResult {
  // Unsupported transform and unsupported grid type surfaces.
  let empty = Vec[UInt8].new();
  var bad = Vec[UInt8].new();
  put_header(&mut bad, 225, 13, 1, true, "01234567-89ab-cdef-0123-456789abcdef");
  put_i32(&mut bad, 0);
  put_i32(&mut bad, 1);
  let meta = zero_meta();
  var xf = Vec[UInt8].new();
  put_str(&mut xf, "NonlinearFrustumMap");
  push_zeros(&mut xf, 48);
  put_desc_seek(&mut bad, "frustum", "Tree_float_5_4_3", "", &meta, &xf, &empty, &empty, 0, 0);
  var ok = false;
  let r = vdb_open(&bad);
  if r.is_ok {
    let f = r.value;
    if err_code_xform(vdb_grid_transform(&bad, &f, 0), VDB_ERR_UNSUPPORTED_TRANSFORM) { ok = true; }
  }
  var uns = Vec[UInt8].new();
  put_header(&mut uns, 225, 13, 1, true, "01234567-89ab-cdef-0123-456789abcdef");
  put_i32(&mut uns, 0);
  put_i32(&mut uns, 1);
  let xf2 = xf_uniform_scale(1.0);
  put_desc_seek(&mut uns, "flags", "Tree_bool_5_4_3", "", &meta, &xf2, &empty, &empty, 0, 0);
  let r2 = vdb_open(&uns);
  if r2.is_ok {
    let f2 = r2.value;
    if err_code_tree(vdb_grid_tree(&uns, &f2, 0), VDB_ERR_UNSUPPORTED_GRID_TYPE) { ok = true; } else { ok = false; }
  } else { ok = false; }
  // Non-seekable files must refuse to skip unsupported grid bodies at open.
  var uns2 = Vec[UInt8].new();
  put_header(&mut uns2, 225, 13, 1, false, "00000000-0000-0000-0000-000000000000");
  put_i32(&mut uns2, 0);
  put_i32(&mut uns2, 1);
  put_desc_stream(&mut uns2, "flags", "Tree_bool_5_4_3", "", &meta, &xf2, &empty, &empty, 0);
  if !err_code_file(vdb_open(&uns2), VDB_ERR_UNSUPPORTED_GRID_TYPE) { ok = false; }
  return assert(ok, "unsupported transform and grid types are typed errors");
}

fn t17() -> TestResult {
  let a = fx_a(0, 0);
  let r = vdb_open(&a);
  var ok = r.is_ok;
  if r.is_ok {
    let f = r.value;
    let tr = vdb_grid_tree(&a, &f, 0);
    if tr.is_ok {
      let t = tr.value;
      if t.leaf_count != 2 { ok = false; }
      if t.element_kind != VDB_ELEM_F32 { ok = false; }
      if t.from_half { ok = false; }
      if t.components != 1 { ok = false; }
      if t.compression != 2 { ok = false; }
      let bg: Float64 = t.background[0];
      if bg != 0.25 { ok = false; }
      if t.root_tile_count != 1 { ok = false; }
      if t.root_child_count != 1 { ok = false; }
      if t.origins[0] != 0 || t.origins[1] != 0 || t.origins[2] != 0 { ok = false; }
      if t.origins[3] != 0 || t.origins[4] != 0 || t.origins[5] != 8 { ok = false; }
      if t.topology_end != t.buffers_offset { ok = false; }
      if t.buffers_end <= t.buffers_offset { ok = false; }
      if t.buffer_offsets[0] != t.buffers_offset { ok = false; }
      if t.buffer_offsets[1] <= t.buffer_offsets[0] { ok = false; }
    } else { ok = false; }
  }
  return assert(ok, "tree walk: leaf origins, background, counts, buffer index");
}

fn t18() -> TestResult {
  let a = fx_a(0, 0);
  let r = vdb_open(&a);
  var ok = r.is_ok;
  if r.is_ok {
    let f = r.value;
    let tr = vdb_grid_tree(&a, &f, 0);
    if tr.is_ok {
      let t = tr.value;
      let lr = vdb_read_leaf(&a, &t, 0);
      if lr.is_ok {
        let l = lr.value;
        if l.metadata != 0 { ok = false; }
        if l.value_count != 512 { ok = false; }
        if l.components != 1 { ok = false; }
        if l.from_half { ok = false; }
        if l.logical_width != 4 || l.payload_width != 4 { ok = false; }
        if l.payload.len() != 2048 { ok = false; }
        if vdb_leaf_active_count(&l) != 512 { ok = false; }
        if l.values.len() != 512 { ok = false; }
        var i = 0;
        while i < 512 {
          let v: Float64 = l.values[i];
          if v != A(i) { ok = false; }
          i = i + 1;
        }
        if !vdb_leaf_contains(&l, 7, 7, 7) { ok = false; }
        if vdb_leaf_contains(&l, 8, 0, 0) { ok = false; }
        if vdb_leaf_voxel_offset(&l, 0, 0, 1) != 1 { ok = false; }
        if vdb_leaf_voxel_offset(&l, 1, 0, 0) != 64 { ok = false; }
        if vdb_leaf_voxel_offset(&l, -1, 0, 0) != -1 { ok = false; }
      } else { ok = false; }
      if !err_code_leaf(vdb_read_leaf(&a, &t, 2), VDB_ERR_INDEX_OUT_OF_RANGE) { ok = false; }
      if !err_code_leaf(vdb_read_leaf(&a, &t, -1), VDB_ERR_INDEX_OUT_OF_RANGE) { ok = false; }
    } else { ok = false; }
  }
  return assert(ok, "dense raw leaf: metadata 0, 512 active values, patterns, bounds");
}

fn t19() -> TestResult {
  let a = fx_a(0, 0);
  let r = vdb_open(&a);
  var ok = r.is_ok;
  if r.is_ok {
    let f = r.value;
    let tr = vdb_grid_tree(&a, &f, 0);
    if tr.is_ok {
      let t = tr.value;
      let lr = vdb_read_leaf(&a, &t, 1);
      if lr.is_ok {
        let l = lr.value;
        if l.metadata != 3 { ok = false; }
        if vdb_leaf_active_count(&l) != 171 { ok = false; }
        if l.payload.len() != 684 { ok = false; }
        // active positions carry S(k); inactive positions reconstruct
        // +0.25 (selection bit on) or -0.25 (off) from the background.
        let v0: Float64 = l.values[0];
        if v0 != S(0) { ok = false; }
        let v3: Float64 = l.values[3];
        if v3 != S(1) { ok = false; }
        let v1: Float64 = l.values[1];
        if v1 != (0.0 - 0.25) { ok = false; }
        let v2: Float64 = l.values[2];
        if v2 != 0.25 { ok = false; }
        let v4: Float64 = l.values[4];
        if v4 != 0.25 { ok = false; }
        let v5: Float64 = l.values[5];
        if v5 != (0.0 - 0.25) { ok = false; }
        let vr = vdb_leaf_component(&l, 0, 0, 11, 0);
        if vr.is_ok {
          if vr.value != S(1) { ok = false; }
        } else { ok = false; }
        if vdb_leaf_component(&l, 8, 0, 8, 0).is_ok { ok = false; }
        if vdb_leaf_component(&l, 0, 0, 8, 1).is_ok { ok = false; }
        if vdb_leaf_is_active(&l, 1, 0, 8) { ok = false; }
        if !vdb_leaf_is_active(&l, 0, 0, 11) { ok = false; }
      } else { ok = false; }
    } else { ok = false; }
  }
  return assert(ok, "selection-mask leaf: 171 active, inactive +-background reconstruction");
}

fn t20() -> TestResult {
  let a = fx_a(0, 0);
  let r = vdb_open(&a);
  var ok = r.is_ok;
  if r.is_ok {
    let f = r.value;
    let tr = vdb_grid_tree(&a, &f, 1);
    if tr.is_ok {
      let t = tr.value;
      if t.leaf_count != 1 { ok = false; }
      if t.compression != 3 { ok = false; }
      if f.block_pos[1] != t.buffers_offset { ok = false; }
      if f.end_pos[1] != t.buffers_end { ok = false; }
      let lr = vdb_read_leaf(&a, &t, 0);
      if lr.is_ok {
        let l = lr.value;
        if l.metadata != 0 { ok = false; }
        if l.payload.len() != 2048 { ok = false; }
        let v0: Float64 = l.values[0];
        if v0 != A(0) { ok = false; }
        let v100: Float64 = l.values[100];
        if v100 != A(100) { ok = false; }
        let v511: Float64 = l.values[511];
        if v511 != A(511) { ok = false; }
      } else { ok = false; }
    } else { ok = false; }
  }
  return assert(ok, "zip leaf chunk: inflate, position cross-check, dense values");
}

fn t21() -> TestResult {
  let a = fx_a(0, 0);
  let r = vdb_open(&a);
  var ok = r.is_ok;
  if r.is_ok {
    let f = r.value;
    let tr = vdb_grid_tree(&a, &f, 0);
    if tr.is_ok {
      let t = tr.value;
      let v1 = vdb_read_voxel(&a, &t, 3, 5, 6);
      if v1.is_ok {
        let x = v1.value;
        if !x.found { ok = false; }
        if !x.active { ok = false; }
        let w: Float64 = x.values[0];
        if w != A(3 * 64 + 5 * 8 + 6) { ok = false; }
      } else { ok = false; }
      let v2 = vdb_read_voxel(&a, &t, 0, 0, 9);
      if v2.is_ok {
        let x = v2.value;
        if !x.found { ok = false; }
        if x.active { ok = false; }
        let w: Float64 = x.values[0];
        if w != (0.0 - 0.25) { ok = false; }
      } else { ok = false; }
      let v3 = vdb_read_voxel(&a, &t, 0, 0, 8);
      if v3.is_ok {
        let x = v3.value;
        if !x.found { ok = false; }
        if !x.active { ok = false; }
        let w: Float64 = x.values[0];
        if w != S(0) { ok = false; }
      } else { ok = false; }
      let v4 = vdb_read_voxel(&a, &t, 100, 0, 0);
      if v4.is_ok {
        let x = v4.value;
        if x.found { ok = false; }
        if x.values.len() != 0 { ok = false; }
      } else { ok = false; }
      if vdb_find_leaf(&t, 0, 0, 0) != 0 { ok = false; }
      if vdb_find_leaf(&t, 0, 0, 8) != 1 { ok = false; }
      if vdb_find_leaf(&t, 0, 0, 7) != 0 { ok = false; }
      if vdb_find_leaf(&t, -1, 0, 0) != -1 { ok = false; }
    } else { ok = false; }
  }
  return assert(ok, "voxel access: leaf lookup, active state, background misses");
}

fn t22() -> TestResult {
  let b = fx_b();
  let r = vdb_open(&b);
  var ok = r.is_ok;
  if r.is_ok {
    let f = r.value;
    if vdb_grid_count(&f) != 2 { ok = false; }
    if vdb_grid_pos(&f, 0) != 0 { ok = false; }
    if vdb_grid_end_pos(&f, 0) != 0 { ok = false; }
    if vdb_grid_body_offset(&f, 0) <= 0 { ok = false; }
    let tr = vdb_grid_tree(&b, &f, 0);
    if tr.is_ok {
      let t = tr.value;
      if !t.from_half { ok = false; }
      if t.element_kind != VDB_ELEM_F32 { ok = false; }
      if t.leaf_count != 1 { ok = false; }
      let bg: Float64 = t.background[0];
      if bg != 1.5 { ok = false; }
      let lr = vdb_read_leaf(&b, &t, 0);
      if lr.is_ok {
        let l = lr.value;
        if !l.from_half { ok = false; }
        if l.logical_width != 4 || l.payload_width != 2 { ok = false; }
        if l.payload.len() != 1024 { ok = false; }
        var i = 0;
        while i < 512 {
          let v: Float64 = l.values[i];
          if v != H(i) { ok = false; }
          i = i + 1;
        }
        let b0: Int = l.metadata;
        if b0 != 0 { ok = false; }
      } else { ok = false; }
    } else { ok = false; }
  }
  return assert(ok, "streamed file: half-storage float grid (binary16 promotion)");
}

fn t23() -> TestResult {
  let b = fx_b();
  let r = vdb_open(&b);
  var ok = r.is_ok;
  if r.is_ok {
    let f = r.value;
    let tr = vdb_grid_tree(&b, &f, 1);
    if tr.is_ok {
      let t = tr.value;
      if t.components != 3 { ok = false; }
      if t.element_kind != VDB_ELEM_VEC3F { ok = false; }
      if t.leaf_count != 2 { ok = false; }
      if t.origins[3] != 0 || t.origins[5] != 40 { ok = false; }
      let lr = vdb_read_leaf(&b, &t, 0);
      if lr.is_ok {
        let l = lr.value;
        if l.components != 3 { ok = false; }
        if l.values.len() != 1536 { ok = false; }
        let v0: Float64 = l.values[0];
        let v1: Float64 = l.values[1];
        let v2: Float64 = l.values[2];
        if v0 != 0.0 || v1 != 1.0 || v2 != 2.0 { ok = false; }
        let w5: Float64 = l.values[5 * 3 + 2];
        if w5 != V(5, 2) { ok = false; }
      } else { ok = false; }
      let lr2 = vdb_read_leaf(&b, &t, 1);
      if lr2.is_ok {
        let l = lr2.value;
        let v0: Float64 = l.values[0];
        if v0 != 10.0 { ok = false; }
      } else { ok = false; }
      let vx = vdb_read_voxel(&b, &t, 0, 0, 45);
      if vx.is_ok {
        let x = vx.value;
        if !x.found { ok = false; }
        if x.components != 3 { ok = false; }
        let c0: Float64 = x.values[0];
        let c1: Float64 = x.values[1];
        let c2: Float64 = x.values[2];
        if c0 != V2(5, 0) { ok = false; }
        if c1 != V2(5, 1) { ok = false; }
        if c2 != V2(5, 2) { ok = false; }
      } else { ok = false; }
      let t2 = vdb_grid_transform(&b, &f, 1);
      if t2.is_ok {
        let x = t2.value;
        if x.map_kind != VDB_MAP_KIND_AFFINE { ok = false; }
        let vx0: Float64 = x.voxel_size[0];
        if vx0 != 2.0 { ok = false; }
        let tx: Float64 = x.translation[0];
        let tz: Float64 = x.translation[2];
        if tx != 1.0 || tz != 3.0 { ok = false; }
      } else { ok = false; }
    } else { ok = false; }
  }
  return assert(ok, "vec3f grid: 3 components, 2 leaves, AffineMap voxel norms");
}

fn t24() -> TestResult {
  let c = fx_c();
  let r = vdb_open(&c);
  var ok = r.is_ok;
  if r.is_ok {
    let f = r.value;
    let tr = vdb_grid_tree(&c, &f, 0);
    if tr.is_ok {
      let t = tr.value;
      let lr = vdb_read_leaf(&c, &t, 0);
      if lr.is_ok {
        let l = lr.value;
        if l.metadata != 3 { ok = false; }
        if vdb_leaf_active_count(&l) != 171 { ok = false; }
        if l.payload.len() != 684 { ok = false; }
        let v0: Float64 = l.values[0];
        if v0 != S(0) { ok = false; }
        let v6: Float64 = l.values[6];
        if v6 != S(2) { ok = false; }
        let v1: Float64 = l.values[1];
        if v1 != (0.0 - 0.0) { ok = false; }
        let v2: Float64 = l.values[2];
        if v2 != 0.0 { ok = false; }
      } else { ok = false; }
    } else { ok = false; }
  }
  return assert(ok, "zip + selection mask: sparse zlib payload with +-0.0 background");
}

fn t25() -> TestResult {
  let a = fx_a(0, 0);
  let r = vdb_open(&a);
  var ok = r.is_ok;
  if r.is_ok {
    let f = r.value;
    let gr = vdb_grid_meta(&a, &f, 2);
    if gr.is_ok {
      let m = gr.value;
      if vdb_meta_count(&m) != 0 { ok = false; }
    } else { ok = false; }
    let xr = vdb_grid_transform(&a, &f, 2);
    if !xr.is_ok { ok = false; }
    if !err_code_tree(vdb_grid_tree(&a, &f, 2), VDB_ERR_INSTANCE_GRID) { ok = false; }
    let tr = vdb_grid_tree(&a, &f, 3);
    if tr.is_ok {
      let t = tr.value;
      if t.leaf_count != 0 { ok = false; }
      if t.buffers_end != t.buffers_offset { ok = false; }
      if !err_code_leaf(vdb_read_leaf(&a, &t, 0), VDB_ERR_INDEX_OUT_OF_RANGE) { ok = false; }
      let vx = vdb_read_voxel(&a, &t, 0, 0, 0);
      if vx.is_ok {
        if vx.value.found { ok = false; }
      } else { ok = false; }
    } else { ok = false; }
  }
  return assert(ok, "instance grid surfaces its parent; empty grid has no leaves");
}

fn t26() -> TestResult {
  // Out-of-range conventions across the grid-level API.
  let a = fx_a(0, 0);
  let r = vdb_open(&a);
  var ok = r.is_ok;
  if r.is_ok {
    let f = r.value;
    if !err_code_meta(vdb_grid_meta(&a, &f, -1), VDB_ERR_INDEX_OUT_OF_RANGE) { ok = false; }
    if !err_code_meta(vdb_grid_meta(&a, &f, 4), VDB_ERR_INDEX_OUT_OF_RANGE) { ok = false; }
    if !err_code_xform(vdb_grid_transform(&a, &f, 4), VDB_ERR_INDEX_OUT_OF_RANGE) { ok = false; }
    if !err_code_tree(vdb_grid_tree(&a, &f, -1), VDB_ERR_INDEX_OUT_OF_RANGE) { ok = false; }
    if vdb_grid_body_offset(&f, 4) != -1 { ok = false; }
    if vdb_grid_type(&f, -2).len() != 0 { ok = false; }
  }
  return assert(ok, "grid-level accessors and parsers honour index bounds");
}

fn t27() -> TestResult {
  let a = fx_a(0, 0);
  let short = prefix(a, a.len() - 100);
  var ok = err_code_file(vdb_open(&short), VDB_ERR_TRUNCATED);
  let baddelta = fx_a(1, 0);
  let r = vdb_open(&baddelta);
  if r.is_ok {
    let f = r.value;
    if !err_code_tree(vdb_grid_tree(&baddelta, &f, 0), VDB_ERR_BAD_LAYOUT) { ok = false; }
  } else { ok = false; }
  let badmeta = fx_a(0, 9);
  let r2 = vdb_open(&badmeta);
  if r2.is_ok {
    let f2 = r2.value;
    if !err_code_tree(vdb_grid_tree(&badmeta, &f2, 0), VDB_ERR_BAD_NODE_DATA) { ok = false; }
  } else { ok = false; }
  let badcomp = fx_tiny(8, "Tree_float_5_4_3", 0, &Vec[UInt8].new());
  let r3 = vdb_open(&badcomp);
  if r3.is_ok {
    let f3 = r3.value;
    if !err_code_tree(vdb_grid_tree(&badcomp, &f3, 0), VDB_ERR_UNSUPPORTED_COMPRESSION) { ok = false; }
  } else { ok = false; }
  return assert(ok, "corruptions: truncation, bad positions, metadata byte, flags");
}

fn t28() -> TestResult {
  let bl = fx_tiny(6, "Tree_float_5_4_3", 0, &blosc_junk_chunk());
  let r = vdb_open(&bl);
  var ok = r.is_ok;
  if r.is_ok {
    let f = r.value;
    let tr = vdb_grid_tree(&bl, &f, 0);
    if tr.is_ok {
      let t = tr.value;
      if t.compression != 6 { ok = false; }
      if !err_code_leaf(vdb_read_leaf(&bl, &t, 0), VDB_ERR_UNSUPPORTED_COMPRESSION) { ok = false; }
    } else { ok = false; }
  }
  return assert(ok, "blosc: structure walks, value decode is a typed error");
}

fn t29() -> TestResult {
  // Patch a leaf-buffer byte inside the sparse leaf chunk of fixture A by
  // rebuilding with a corrupted z_sparse payload in fixture C.
  var c = fx_c();
  let z = z_sparse();
  let badz = set_byte(z, z.len() - 1, (byte_of(z[z.len() - 1] as Int, 0) as Int) ^ 1);
  var f2 = Vec[UInt8].new();
  put_header(&mut f2, 225, 13, 1, true, "01234567-89ab-cdef-0123-456789abcdef");
  put_file_meta(&mut f2);
  put_i32(&mut f2, 1);
  let c_meta = fx_density_meta();
  let c_xf = xf_uniform_scale(0.5);
  let c_l4 = l4_f32(&bits_vec(0), 2, 6.0, 1, false, &mask_sparse());
  let c_l5 = l5_f32(0, 1, 5.0, 1, false, &c_l4);
  let c_topo = topo_f32(0.0, false, &c_l5);
  let c_bufs = leaf_meta3_zip(&mask_sparse(), &mask_sel(), &badz);
  put_desc_seek(&mut f2, "zipsparse", "Tree_float_5_4_3", "", &c_meta, &c_xf, &c_topo, &c_bufs, 3, 0);
  let r = vdb_open(&f2);
  var ok = false;
  if r.is_ok {
    let ff = r.value;
    let tr = vdb_grid_tree(&f2, &ff, 0);
    if tr.is_ok {
      let t = tr.value;
      if err_code_leaf(vdb_read_leaf(&f2, &t, 0), VDB_ERR_ZIP_ADLER) { ok = true; }
    }
  }
  return assert(ok, "corrupt zlib payload inside a leaf is a typed ZIP_ADLER error");
}

fn t30() -> TestResult {
  // Metadata value copy and accessor edge cases.
  let a = fx_a(0, 0);
  let r = vdb_open(&a);
  var ok = r.is_ok;
  if r.is_ok {
    let f = r.value;
    let m: VdbMetaMap = f.meta;
    let vr = vdb_meta_value(&a, &m, 0);
    if vr.is_ok {
      let v: Vec[UInt8] = vr.value;
      if v.len() != 14 { ok = false; }
      if !streq(Str::from_utf8(v), "xiom-vdb-tests") { ok = false; }
    } else { ok = false; }
    if vdb_meta_type(&m, 9).len() != 0 { ok = false; }
    if vdb_meta_value_bytes(&m, 9) != -1 { ok = false; }
  }
  return assert(ok, "metadata value copy and accessor conventions");
}

fn main() -> Int {
  io.println("=== xiom.vdb conformance tests ===");
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
  let r24 = t24();
  if r24.passed { io.println("  [PASS] " + r24.name); } else { io.println("  [FAIL] " + r24.name); failed = failed + 1; }
  let r25 = t25();
  if r25.passed { io.println("  [PASS] " + r25.name); } else { io.println("  [FAIL] " + r25.name); failed = failed + 1; }
  let r26 = t26();
  if r26.passed { io.println("  [PASS] " + r26.name); } else { io.println("  [FAIL] " + r26.name); failed = failed + 1; }
  let r27 = t27();
  if r27.passed { io.println("  [PASS] " + r27.name); } else { io.println("  [FAIL] " + r27.name); failed = failed + 1; }
  let r28 = t28();
  if r28.passed { io.println("  [PASS] " + r28.name); } else { io.println("  [FAIL] " + r28.name); failed = failed + 1; }
  let r29 = t29();
  if r29.passed { io.println("  [PASS] " + r29.name); } else { io.println("  [FAIL] " + r29.name); failed = failed + 1; }
  let r30 = t30();
  if r30.passed { io.println("  [PASS] " + r30.name); } else { io.println("  [FAIL] " + r30.name); failed = failed + 1; }
  if failed == 0 {
    io.println("xiom.vdb: all tests passed");
  } else {
    io.println("xiom.vdb: tests failed");
  }
  return failed;
}
