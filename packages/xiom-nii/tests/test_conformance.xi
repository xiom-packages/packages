// XIOM -- xiom.nii conformance tests (18 checks)
// Port task: prove the pure-XIOM xiom.nii NIfTI-1 header codec against its
// documented 348-byte layout, endianness handling and error catalog.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Covers the documented API: canonical builder byte layout at pinned
// offsets; the datatype/bitpix table; dims, scalar and text accessors; all
// singleton float, pixdim and srow raw/hex tokens; magic kinds; little- and
// big-endian detection with a byte-swapped fixture; the validation catalog
// (sizeof_hdr, dims, datatype, bitpix, magic, vox_offset); the extension
// flag; builder setters and their errors with an unchanged builder; and
// full builder -> bytes -> parse -> bytes round-trips.
//
// Harness style mirrors xiom.hello / xiom.tlv: one fn tN() -> TestResult per
// check, called directly from main; main prints [PASS]/[FAIL] and returns
// the failure count. Str values are compared with str_compare (BUG 17
// discipline) and every Vec element read is bound to a typed local.

module nii_tests
use xiom.io; use xiom.test;
use xiom.string; use xiom.string.builder; use xiom.string.compare;
use xiom.encoding.hex;
use xiom.nii;
use xiom.nii.NII_HEADER_LEN;
use xiom.nii.NII_MAGIC_SINGLE;
use xiom.nii.NII_MAGIC_PAIR;
use xiom.nii.NII_EXT_NONE;
use xiom.nii.NII_EXT_UNKNOWN;
use xiom.nii.NII_FLOAT_VOX_OFFSET;
use xiom.nii.NII_FLOAT_SCL_SLOPE;
use xiom.nii.NII_FLOAT_QUATERN_B;
use xiom.nii.NII_FLOAT_QOFFSET_X;

// --------------------------------------------------
//  Harness helpers
// --------------------------------------------------

fn report(passed: Bool, name: Str) -> Int {
  if passed {
    io.println("  [PASS] " + name);
    return 0;
  }
  io.println("  [FAIL] " + name);
  return 1;
}

fn str_eq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn err_header_is(r: Result[NiftiHeader, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  let got: Str = r.error;
  return str_eq(got, want);
}

fn err_bytes_is(r: Result[Vec[UInt8], Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  let got: Str = r.error;
  return str_eq(got, want);
}

fn err_unit_is(r: Result[Unit, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  let got: Str = r.error;
  return str_eq(got, want);
}

fn err_int_is(r: Result[Int, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  let got: Str = r.error;
  return str_eq(got, want);
}

fn err_str_is(r: Result[Str, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  let got: Str = r.error;
  return str_eq(got, want);
}

// --------------------------------------------------
//  Byte helpers
// --------------------------------------------------

fn hb(hexstr: Str) -> Vec[UInt8] {
  let r = hex.hex_decode(hexstr);
  match r {
    Ok(v) => { return v; },
    Err(_) => {},
  }
  return Vec[UInt8].new();
}

fn bytes_equal(a: Vec[UInt8], b: Vec[UInt8]) -> Bool {
  if a.len() != b.len() {
    return false;
  }
  var i = 0;
  while i < a.len() {
    let x: UInt8 = a[i];
    let y: UInt8 = b[i];
    if x != y {
      return false;
    }
    i = i + 1;
  }
  return true;
}

fn bytes_at_equal(v: Vec[UInt8], base: Int, want: Vec[UInt8]) -> Bool {
  if base < 0 {
    return false;
  }
  if v.len() < base + want.len() {
    return false;
  }
  var i = 0;
  while i < want.len() {
    let x: UInt8 = v[base + i];
    let y: UInt8 = want[i];
    if x != y {
      return false;
    }
    i = i + 1;
  }
  return true;
}

fn all_zero(v: Vec[UInt8], off: Int, size: Int) -> Bool {
  if off < 0 || size < 0 {
    return false;
  }
  if off + size > v.len() {
    return false;
  }
  var i = 0;
  while i < size {
    let b: UInt8 = v[off + i];
    let x = (b as Int) & 0xFF;
    if x != 0 {
      return false;
    }
    i = i + 1;
  }
  return true;
}

fn repeat_byte(b: Int, n: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < n {
    v.push(b as UInt8);
    i = i + 1;
  }
  return v;
}

fn cat(a: Vec[UInt8], b: Vec[UInt8]) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < a.len() {
    let x: UInt8 = a[i];
    v.push(x);
    i = i + 1;
  }
  var j = 0;
  while j < b.len() {
    let y: UInt8 = b[j];
    v.push(y);
    j = j + 1;
  }
  return v;
}

fn set_u8(v: &mut Vec[UInt8], off: Int, val: Int) {
  v[off] = val as UInt8;
  return;
}

fn set_u16_le(v: &mut Vec[UInt8], off: Int, val: Int) {
  var x = val;
  if x < 0 { x = x + 65536; }
  v[off] = (x % 256) as UInt8;
  v[off + 1] = ((x / 256) % 256) as UInt8;
  return;
}

fn set_u32_le(v: &mut Vec[UInt8], off: Int, val: Int) {
  v[off] = (val % 256) as UInt8;
  v[off + 1] = ((val / 256) % 256) as UInt8;
  v[off + 2] = ((val / 65536) % 256) as UInt8;
  v[off + 3] = ((val / 16777216) % 256) as UInt8;
  return;
}

// --------------------------------------------------
//  Fixtures and accessor predicates
// --------------------------------------------------

// Canonical builder header or an empty vector when the builder fails (the
// caller's assertions then fail).
fn fixture() -> Vec[UInt8] {
  let b = nii_builder_new();
  let fr = nii_builder_finish(&b);
  if !fr.is_ok {
    return Vec[UInt8].new();
  }
  let v: Vec[UInt8] = fr.value;
  return v;
}

// Canonical header with every documented field set to a distinct value.
fn full_fixture() -> Vec[UInt8] {
  var b = nii_builder_new();
  if !nii_builder_set_dim(&mut b, 0, 3).is_ok { return Vec[UInt8].new(); }
  if !nii_builder_set_dim(&mut b, 1, 64).is_ok { return Vec[UInt8].new(); }
  if !nii_builder_set_dim(&mut b, 2, 64).is_ok { return Vec[UInt8].new(); }
  if !nii_builder_set_dim(&mut b, 3, 32).is_ok { return Vec[UInt8].new(); }
  if !nii_builder_set_datatype(&mut b, 16).is_ok { return Vec[UInt8].new(); }
  let f_vox = hb("0000b043");
  if !nii_builder_set_float(&mut b, 0, &f_vox).is_ok { return Vec[UInt8].new(); }
  let f_slope = hb("0000803f");
  if !nii_builder_set_float(&mut b, 1, &f_slope).is_ok { return Vec[UInt8].new(); }
  let f_cal = hb("00002041");
  if !nii_builder_set_float(&mut b, 3, &f_cal).is_ok { return Vec[UInt8].new(); }
  let f_qx = hb("0000803e");
  if !nii_builder_set_float(&mut b, 13, &f_qx).is_ok { return Vec[UInt8].new(); }
  let f_pd1 = hb("00000040");
  if !nii_builder_set_pixdim(&mut b, 1, &f_pd1).is_ok { return Vec[UInt8].new(); }
  if !nii_builder_set_pixdim(&mut b, 2, &f_pd1).is_ok { return Vec[UInt8].new(); }
  let f_pd3 = hb("00008040");
  if !nii_builder_set_pixdim(&mut b, 3, &f_pd3).is_ok { return Vec[UInt8].new(); }
  let f_one = hb("0000803f");
  if !nii_builder_set_srow(&mut b, 0, 0, &f_one).is_ok { return Vec[UInt8].new(); }
  if !nii_builder_set_srow(&mut b, 1, 1, &f_one).is_ok { return Vec[UInt8].new(); }
  if !nii_builder_set_srow(&mut b, 2, 2, &f_one).is_ok { return Vec[UInt8].new(); }
  let f_m32 = hb("000000c2");
  if !nii_builder_set_srow(&mut b, 0, 3, &f_m32).is_ok { return Vec[UInt8].new(); }
  let f_m16 = hb("000080c1");
  if !nii_builder_set_srow(&mut b, 2, 3, &f_m16).is_ok { return Vec[UInt8].new(); }
  if !nii_builder_set_qform_code(&mut b, 1).is_ok { return Vec[UInt8].new(); }
  if !nii_builder_set_sform_code(&mut b, 2).is_ok { return Vec[UInt8].new(); }
  if !nii_builder_set_intent_code(&mut b, 3).is_ok { return Vec[UInt8].new(); }
  if !nii_builder_set_descrip(&mut b, "XIOM NIfTI-1 header").is_ok { return Vec[UInt8].new(); }
  if !nii_builder_set_aux_file(&mut b, "aux.bin").is_ok { return Vec[UInt8].new(); }
  if !nii_builder_set_intent_name(&mut b, "mean").is_ok { return Vec[UInt8].new(); }
  let fr = nii_builder_finish(&b);
  if !fr.is_ok {
    return Vec[UInt8].new();
  }
  let v: Vec[UInt8] = fr.value;
  return v;
}

fn float_hex_is(h: &NiftiHeader, field: Int, want: Str) -> Bool {
  let r = nii_float_hex(h, field);
  if !r.is_ok {
    return false;
  }
  let s: Str = r.value;
  return str_eq(s, want);
}

fn pixdim_hex_is(h: &NiftiHeader, i: Int, want: Str) -> Bool {
  let r = nii_pixdim_hex(h, i);
  if !r.is_ok {
    return false;
  }
  let s: Str = r.value;
  return str_eq(s, want);
}

fn srow_hex_is(h: &NiftiHeader, row: Int, col: Int, want: Str) -> Bool {
  let r = nii_srow_hex(h, row, col);
  if !r.is_ok {
    return false;
  }
  let s: Str = r.value;
  return str_eq(s, want);
}

// Byte-swap one field of a little-endian fixture so the record becomes the
// documented big-endian form (independent mirror of the layout table).
fn swap_at(v: &mut Vec[UInt8], off: Int, size: Int) {
  var i = 0;
  var j = size - 1;
  while i < j {
    let a: UInt8 = v[off + i];
    let b: UInt8 = v[off + j];
    v[off + i] = b;
    v[off + j] = a;
    i = i + 1;
    j = j - 1;
  }
  return;
}

fn to_big_endian(le: Vec[UInt8]) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var c = 0;
  while c < le.len() {
    let x: UInt8 = le[c];
    v.push(x);
    c = c + 1;
  }
  swap_at(&mut v, 0, 4);
  swap_at(&mut v, 32, 4);
  swap_at(&mut v, 36, 2);
  var i = 0;
  while i < 8 {
    swap_at(&mut v, 40 + i * 2, 2);
    i = i + 1;
  }
  swap_at(&mut v, 56, 4);
  swap_at(&mut v, 60, 4);
  swap_at(&mut v, 64, 4);
  swap_at(&mut v, 68, 2);
  swap_at(&mut v, 70, 2);
  swap_at(&mut v, 72, 2);
  swap_at(&mut v, 74, 2);
  i = 0;
  while i < 8 {
    swap_at(&mut v, 76 + i * 4, 4);
    i = i + 1;
  }
  swap_at(&mut v, 108, 4);
  swap_at(&mut v, 112, 4);
  swap_at(&mut v, 116, 4);
  swap_at(&mut v, 120, 2);
  swap_at(&mut v, 124, 4);
  swap_at(&mut v, 128, 4);
  swap_at(&mut v, 132, 4);
  swap_at(&mut v, 136, 4);
  swap_at(&mut v, 140, 4);
  swap_at(&mut v, 144, 4);
  swap_at(&mut v, 252, 2);
  swap_at(&mut v, 254, 2);
  swap_at(&mut v, 256, 4);
  swap_at(&mut v, 260, 4);
  swap_at(&mut v, 264, 4);
  swap_at(&mut v, 268, 4);
  swap_at(&mut v, 272, 4);
  swap_at(&mut v, 276, 4);
  i = 0;
  while i < 12 {
    swap_at(&mut v, 280 + i * 4, 4);
    i = i + 1;
  }
  return v;
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  let b = nii_builder_new();
  let fr = nii_builder_finish(&b);
  if !fr.is_ok {
    return assert(false, "default builder must finish");
  }
  let data: Vec[UInt8] = fr.value;
  var ok = data.len() == NII_HEADER_LEN;
  let pr = nii_parse(&data);
  if !pr.is_ok {
    return assert(false, "default header must parse");
  }
  let h: NiftiHeader = pr.value;
  if nii_sizeof_hdr(&h) != NII_HEADER_LEN { ok = false; }
  if nii_swapped(&h) { ok = false; }
  if nii_dim_count(&h) != 3 { ok = false; }
  var i = 1;
  while i < 8 {
    let d = nii_dim(&h, i);
    if !d.is_ok {
      ok = false;
    } else {
      let dv: Int = d.value;
      if dv != 1 { ok = false; }
    }
    i = i + 1;
  }
  if nii_datatype(&h) != 2 { ok = false; }
  if nii_bitpix(&h) != 8 { ok = false; }
  if nii_magic_kind(&h) != NII_MAGIC_SINGLE { ok = false; }
  if nii_ext_flag(&h) != NII_EXT_UNKNOWN { ok = false; }
  if !float_hex_is(&h, NII_FLOAT_VOX_OFFSET, "0000b043") { ok = false; }
  var k = 0;
  while k < 8 {
    if !pixdim_hex_is(&h, k, "0000803f") { ok = false; }
    k = k + 1;
  }
  if !str_eq(nii_descrip(&h), "") { ok = false; }
  if !str_eq(nii_aux_file(&h), "") { ok = false; }
  if !str_eq(nii_intent_name(&h), "") { ok = false; }
  if !bytes_equal(nii_to_bytes(&h), data) { ok = false; }
  return assert(ok, "default builder: 348 bytes, dims, uint8/8, magic n+1, floats, round-trip");
}

fn t2() -> TestResult {
  let data = fixture();
  var ok = data.len() == NII_HEADER_LEN;
  if !bytes_at_equal(data, 0, hb("5c010000")) { ok = false; }
  if !all_zero(data, 4, 36) { ok = false; }
  if !bytes_at_equal(data, 40, hb("0300010001000100010001000100")) { ok = false; }
  if !all_zero(data, 56, 12) { ok = false; }
  if !bytes_at_equal(data, 68, hb("0000020008000000")) { ok = false; }
  if !bytes_at_equal(data, 76, hb("0000803f0000803f0000803f0000803f")) { ok = false; }
  if !bytes_at_equal(data, 92, hb("0000803f0000803f0000803f0000803f")) { ok = false; }
  if !bytes_at_equal(data, 108, hb("0000b043")) { ok = false; }
  if !all_zero(data, 112, 36) { ok = false; }
  if !all_zero(data, 148, 80) { ok = false; }
  if !all_zero(data, 228, 24) { ok = false; }
  if !all_zero(data, 252, 4) { ok = false; }
  if !all_zero(data, 256, 72) { ok = false; }
  if !all_zero(data, 328, 16) { ok = false; }
  if !bytes_at_equal(data, 344, hb("6e2b3100")) { ok = false; }
  return assert(ok, "canonical bytes: pinned offsets, dim/pixdim/vox_offset, NUL magic");
}

fn t3() -> TestResult {
  var ok = nii_datatype_bitpix(2) == 8;
  if nii_datatype_bitpix(4) != 16 { ok = false; }
  if nii_datatype_bitpix(8) != 32 { ok = false; }
  if nii_datatype_bitpix(16) != 32 { ok = false; }
  if nii_datatype_bitpix(32) != 64 { ok = false; }
  if nii_datatype_bitpix(64) != 64 { ok = false; }
  if nii_datatype_bitpix(0) != -1 { ok = false; }
  if nii_datatype_bitpix(1) != -1 { ok = false; }
  if nii_datatype_bitpix(128) != -1 { ok = false; }
  if nii_datatype_bitpix(256) != -1 { ok = false; }
  if nii_datatype_bitpix(2048) != -1 { ok = false; }
  if nii_datatype_bitpix(-5) != -1 { ok = false; }
  if !str_eq(nii_datatype_name(2), "NIFTI_TYPE_UINT8") { ok = false; }
  if !str_eq(nii_datatype_name(4), "NIFTI_TYPE_INT16") { ok = false; }
  if !str_eq(nii_datatype_name(8), "NIFTI_TYPE_INT32") { ok = false; }
  if !str_eq(nii_datatype_name(16), "NIFTI_TYPE_FLOAT32") { ok = false; }
  if !str_eq(nii_datatype_name(32), "NIFTI_TYPE_COMPLEX64") { ok = false; }
  if !str_eq(nii_datatype_name(64), "NIFTI_TYPE_FLOAT64") { ok = false; }
  if !str_eq(nii_datatype_name(0), "") { ok = false; }
  if !str_eq(nii_datatype_name(128), "") { ok = false; }
  if !nii_datatype_known(2) { ok = false; }
  if !nii_datatype_known(64) { ok = false; }
  if nii_datatype_known(128) { ok = false; }
  if nii_datatype_known(-1) { ok = false; }
  return assert(ok, "datatype table: UINT8..FLOAT64 bitpix and names, unknown codes rejected");
}

fn t4() -> TestResult {
  var b = nii_builder_new();
  if !nii_builder_set_dim(&mut b, 0, 4).is_ok { return assert(false, "set dim 0"); }
  if !nii_builder_set_dim(&mut b, 1, 64).is_ok { return assert(false, "set dim 1"); }
  if !nii_builder_set_dim(&mut b, 2, 128).is_ok { return assert(false, "set dim 2"); }
  if !nii_builder_set_dim(&mut b, 3, 32).is_ok { return assert(false, "set dim 3"); }
  if !nii_builder_set_dim(&mut b, 4, 5).is_ok { return assert(false, "set dim 4"); }
  let fr = nii_builder_finish(&b);
  if !fr.is_ok { return assert(false, "finish"); }
  let data: Vec[UInt8] = fr.value;
  let pr = nii_parse(&data);
  if !pr.is_ok { return assert(false, "parse"); }
  let h: NiftiHeader = pr.value;
  var ok = nii_dim_count(&h) == 4;
  let d1 = nii_dim(&h, 1);
  let d2 = nii_dim(&h, 2);
  let d3 = nii_dim(&h, 3);
  let d4 = nii_dim(&h, 4);
  let d5 = nii_dim(&h, 5);
  if !d1.is_ok { ok = false; } elif d1.value != 64 { ok = false; }
  if !d2.is_ok { ok = false; } elif d2.value != 128 { ok = false; }
  if !d3.is_ok { ok = false; } elif d3.value != 32 { ok = false; }
  if !d4.is_ok { ok = false; } elif d4.value != 5 { ok = false; }
  if !d5.is_ok { ok = false; } elif d5.value != 1 { ok = false; }
  if !err_int_is(nii_dim(&h, -1), "nii: dim index out of range") { ok = false; }
  if !err_int_is(nii_dim(&h, 8), "nii: dim index out of range") { ok = false; }
  var be = nii_builder_new();
  if !err_unit_is(nii_builder_set_dim(&mut be, -1, 1), "nii: dim index out of range") { ok = false; }
  if !err_unit_is(nii_builder_set_dim(&mut be, 8, 1), "nii: dim index out of range") { ok = false; }
  if !err_unit_is(nii_builder_set_dim(&mut be, 0, -1), "nii: negative dimension") { ok = false; }
  if !err_unit_is(nii_builder_set_dim(&mut be, 0, 32768), "nii: dimension out of range") { ok = false; }
  return assert(ok, "dims: count/extents, scalar index, signed widths and setter errors");
}

fn t5() -> TestResult {
  var b = nii_builder_new();
  var tokens = Vec[Vec[UInt8]].new();
  var k = 0;
  while k < 16 {
    let t = repeat_byte(k + 1, 4);
    if !nii_builder_set_float(&mut b, k, &t).is_ok { return assert(false, "set float"); }
    tokens.push(t);
    k = k + 1;
  }
  let fr = nii_builder_finish(&b);
  if !fr.is_ok { return assert(false, "finish"); }
  let data: Vec[UInt8] = fr.value;
  let pr = nii_parse(&data);
  if !pr.is_ok { return assert(false, "parse"); }
  let h: NiftiHeader = pr.value;
  var ok = true;
  k = 0;
  while k < 16 {
    let t: Vec[UInt8] = tokens[k];
    let want = nii_raw_hex(&t);
    let got = nii_float_hex(&h, k);
    if !got.is_ok { ok = false; } else {
      let gs: Str = got.value;
      if !str_eq(gs, want) { ok = false; }
    }
    let raw = nii_float_raw(&h, k);
    if !raw.is_ok { ok = false; } else {
      let rv: Vec[UInt8] = raw.value;
      if !bytes_equal(rv, t) { ok = false; }
    }
    k = k + 1;
  }
  if !float_hex_is(&h, NII_FLOAT_VOX_OFFSET, "01010101") { ok = false; }
  if !float_hex_is(&h, NII_FLOAT_SCL_SLOPE, "02020202") { ok = false; }
  if !float_hex_is(&h, NII_FLOAT_QUATERN_B, "0b0b0b0b") { ok = false; }
  if !float_hex_is(&h, NII_FLOAT_QOFFSET_X, "0e0e0e0e") { ok = false; }
  if !err_bytes_is(nii_float_raw(&h, 16), "nii: float field out of range") { ok = false; }
  if !err_bytes_is(nii_float_raw(&h, -1), "nii: float field out of range") { ok = false; }
  if !err_str_is(nii_float_hex(&h, 16), "nii: float field out of range") { ok = false; }
  let short = repeat_byte(1, 3);
  var bf = nii_builder_new();
  if !err_unit_is(nii_builder_set_float(&mut bf, 0, &short), "nii: float token must be 4 bytes") { ok = false; }
  if !err_unit_is(nii_builder_set_float(&mut bf, 16, &short), "nii: float field out of range") { ok = false; }
  if !str_eq(nii_raw_hex(&short), "010101") { ok = false; }
  var empty = Vec[UInt8].new();
  if !str_eq(nii_raw_hex(&empty), "") { ok = false; }
  if !str_eq(nii_raw_hex(&short), hex.hex_encode(&short)) { ok = false; }
  return assert(ok, "singleton float ids: raw/hex tokens for 0..15 and error catalog");
}

fn t6() -> TestResult {
  var b = nii_builder_new();
  let pd1 = hb("00000040");
  let pd2 = hb("00004040");
  let s00 = hb("0000803f");
  let s03 = hb("0000b043");
  let s23 = hb("000080bf");
  if !nii_builder_set_pixdim(&mut b, 1, &pd1).is_ok { return assert(false, "set pixdim 1"); }
  if !nii_builder_set_pixdim(&mut b, 2, &pd2).is_ok { return assert(false, "set pixdim 2"); }
  if !nii_builder_set_srow(&mut b, 0, 0, &s00).is_ok { return assert(false, "set srow 00"); }
  if !nii_builder_set_srow(&mut b, 0, 3, &s03).is_ok { return assert(false, "set srow 03"); }
  if !nii_builder_set_srow(&mut b, 1, 1, &s00).is_ok { return assert(false, "set srow 11"); }
  if !nii_builder_set_srow(&mut b, 2, 3, &s23).is_ok { return assert(false, "set srow 23"); }
  let fr = nii_builder_finish(&b);
  if !fr.is_ok { return assert(false, "finish"); }
  let data: Vec[UInt8] = fr.value;
  let pr = nii_parse(&data);
  if !pr.is_ok { return assert(false, "parse"); }
  let h: NiftiHeader = pr.value;
  var ok = pixdim_hex_is(&h, 0, "0000803f");
  if !pixdim_hex_is(&h, 1, "00000040") { ok = false; }
  if !pixdim_hex_is(&h, 2, "00004040") { ok = false; }
  if !pixdim_hex_is(&h, 3, "0000803f") { ok = false; }
  if !srow_hex_is(&h, 0, 0, "0000803f") { ok = false; }
  if !srow_hex_is(&h, 0, 3, "0000b043") { ok = false; }
  if !srow_hex_is(&h, 1, 1, "0000803f") { ok = false; }
  if !srow_hex_is(&h, 2, 3, "000080bf") { ok = false; }
  let r00 = nii_srow_raw(&h, 0, 0);
  if !r00.is_ok { ok = false; } else {
    let rv: Vec[UInt8] = r00.value;
    if !bytes_equal(rv, s00) { ok = false; }
  }
  if !err_bytes_is(nii_pixdim_raw(&h, 8), "nii: pixdim index out of range") { ok = false; }
  if !err_bytes_is(nii_pixdim_raw(&h, -1), "nii: pixdim index out of range") { ok = false; }
  if !err_str_is(nii_pixdim_hex(&h, 9), "nii: pixdim index out of range") { ok = false; }
  if !err_bytes_is(nii_srow_raw(&h, 3, 0), "nii: srow index out of range") { ok = false; }
  if !err_bytes_is(nii_srow_raw(&h, 0, 4), "nii: srow index out of range") { ok = false; }
  if !err_bytes_is(nii_srow_raw(&h, -1, 0), "nii: srow index out of range") { ok = false; }
  if !err_str_is(nii_srow_hex(&h, 0, -1), "nii: srow index out of range") { ok = false; }
  let short = repeat_byte(9, 2);
  var bg = nii_builder_new();
  if !err_unit_is(nii_builder_set_pixdim(&mut bg, 0, &short), "nii: float token must be 4 bytes") { ok = false; }
  if !err_unit_is(nii_builder_set_srow(&mut bg, 0, 0, &short), "nii: float token must be 4 bytes") { ok = false; }
  if !err_unit_is(nii_builder_set_pixdim(&mut bg, 8, &short), "nii: pixdim index out of range") { ok = false; }
  if !err_unit_is(nii_builder_set_srow(&mut bg, 3, 0, &short), "nii: srow index out of range") { ok = false; }
  return assert(ok, "pixdim and srow: raw/hex tokens at pinned indices and index errors");
}

fn t7() -> TestResult {
  var b = nii_builder_new();
  if !nii_builder_set_magic(&mut b, NII_MAGIC_PAIR).is_ok { return assert(false, "set pair magic"); }
  let fr = nii_builder_finish(&b);
  if !fr.is_ok { return assert(false, "finish"); }
  let pair: Vec[UInt8] = fr.value;
  var ok = bytes_at_equal(pair, 344, hb("6e693100"));
  let pr = nii_parse(&pair);
  if !pr.is_ok { ok = false; } else {
    let hp: NiftiHeader = pr.value;
    if nii_magic_kind(&hp) != NII_MAGIC_PAIR { ok = false; }
  }
  var bh = nii_builder_new();
  if !err_unit_is(nii_builder_set_magic(&mut bh, 2), "nii: invalid magic kind") { ok = false; }
  if !err_unit_is(nii_builder_set_magic(&mut bh, -1), "nii: invalid magic kind") { ok = false; }
  var bad = fixture();
  set_u8(&mut bad, 345, 99);
  if !err_header_is(nii_parse(&bad), "nii: invalid magic") { ok = false; }
  var bad2 = fixture();
  set_u8(&mut bad2, 346, 50);
  if !err_header_is(nii_parse(&bad2), "nii: invalid magic") { ok = false; }
  var bad3 = fixture();
  set_u8(&mut bad3, 347, 1);
  if !err_header_is(nii_parse(&bad3), "nii: invalid magic") { ok = false; }
  var good = fixture();
  set_u8(&mut good, 345, 105);
  let gr = nii_parse(&good);
  if !gr.is_ok { ok = false; } else {
    let hg: NiftiHeader = gr.value;
    if nii_magic_kind(&hg) != NII_MAGIC_PAIR { ok = false; }
  }
  return assert(ok, "magic: n+1/ni1 kinds, byte-exact magic field and invalid-magic rejection");
}

fn t8() -> TestResult {
  let le = full_fixture();
  if le.len() != NII_HEADER_LEN { return assert(false, "LE fixture must be 348 bytes"); }
  let be = to_big_endian(le);
  var ok = bytes_at_equal(be, 0, hb("0000015c"));
  if !bytes_at_equal(be, 344, hb("6e2b3100")) { ok = false; }
  let prle = nii_parse(&le);
  if !prle.is_ok { return assert(false, "LE fixture must parse"); }
  let hl: NiftiHeader = prle.value;
  if nii_swapped(&hl) { ok = false; }
  let prbe = nii_parse(&be);
  if !prbe.is_ok { return assert(false, "BE fixture must parse"); }
  let hb_: NiftiHeader = prbe.value;
  if !nii_swapped(&hb_) { ok = false; }
  if nii_sizeof_hdr(&hb_) != 348 { ok = false; }
  if nii_dim_count(&hb_) != 3 { ok = false; }
  let d1 = nii_dim(&hb_, 1);
  let d3 = nii_dim(&hb_, 3);
  if !d1.is_ok { ok = false; } elif d1.value != 64 { ok = false; }
  if !d3.is_ok { ok = false; } elif d3.value != 32 { ok = false; }
  if nii_datatype(&hb_) != 16 { ok = false; }
  if nii_bitpix(&hb_) != 32 { ok = false; }
  if nii_qform_code(&hb_) != 1 { ok = false; }
  if nii_sform_code(&hb_) != 2 { ok = false; }
  if !float_hex_is(&hb_, NII_FLOAT_VOX_OFFSET, "0000b043") { ok = false; }
  if !float_hex_is(&hb_, NII_FLOAT_SCL_SLOPE, "0000803f") { ok = false; }
  if !float_hex_is(&hb_, NII_FLOAT_QOFFSET_X, "0000803e") { ok = false; }
  if !pixdim_hex_is(&hb_, 3, "00008040") { ok = false; }
  if !srow_hex_is(&hb_, 0, 3, "000000c2") { ok = false; }
  if !srow_hex_is(&hb_, 2, 3, "000080c1") { ok = false; }
  if !str_eq(nii_descrip(&hb_), "XIOM NIfTI-1 header") { ok = false; }
  if !str_eq(nii_aux_file(&hb_), "aux.bin") { ok = false; }
  if !str_eq(nii_intent_name(&hb_), "mean") { ok = false; }
  if !bytes_equal(nii_to_bytes(&hb_), le) { ok = false; }
  if !bytes_equal(nii_to_bytes(&hl), le) { ok = false; }
  return assert(ok, "endianness: BE fixture detected, accessors match LE, normalization to canonical LE");
}

fn t9() -> TestResult {
  var empty = Vec[UInt8].new();
  var ok = err_header_is(nii_parse(&empty), "nii: buffer too small for header");
  let short = repeat_byte(0, 347);
  if !err_header_is(nii_parse(&short), "nii: buffer too small for header") { ok = false; }
  let zeros = repeat_byte(0, 348);
  if !err_header_is(nii_parse(&zeros), "nii: unsupported sizeof_hdr 0") { ok = false; }
  var mut540 = fixture();
  set_u32_le(&mut mut540, 0, 540);
  if !err_header_is(nii_parse(&mut540), "nii: unsupported sizeof_hdr 540") { ok = false; }
  var mut347 = fixture();
  set_u32_le(&mut mut347, 0, 347);
  if !err_header_is(nii_parse(&mut347), "nii: unsupported sizeof_hdr 347") { ok = false; }
  return assert(ok, "sizeof_hdr: short buffers and any non-348 size rejected with the decoded value");
}

fn t10() -> TestResult {
  var bad1 = fixture();
  set_u16_le(&mut bad1, 42, -1);
  var ok = err_header_is(nii_parse(&bad1), "nii: negative dimension");
  var bad2 = fixture();
  set_u16_le(&mut bad2, 40, -3);
  if !err_header_is(nii_parse(&bad2), "nii: negative dimension") { ok = false; }
  var bad3 = fixture();
  set_u16_le(&mut bad3, 54, -32768);
  if !err_header_is(nii_parse(&bad3), "nii: negative dimension") { ok = false; }
  let good = fixture();
  if !nii_parse(&good).is_ok { ok = false; }
  return assert(ok, "dims validation: any negative dim[0..7] is rejected, zeros are allowed");
}

fn t11() -> TestResult {
  var bad1 = fixture();
  set_u16_le(&mut bad1, 70, 0);
  var ok = err_header_is(nii_parse(&bad1), "nii: unknown datatype 0");
  var bad2 = fixture();
  set_u16_le(&mut bad2, 70, 128);
  if !err_header_is(nii_parse(&bad2), "nii: unknown datatype 128") { ok = false; }
  var bad3 = fixture();
  set_u16_le(&mut bad3, 70, 2048);
  if !err_header_is(nii_parse(&bad3), "nii: unknown datatype 2048") { ok = false; }
  var bad4 = fixture();
  set_u16_le(&mut bad4, 70, 64);
  if !err_header_is(nii_parse(&bad4), "nii: bitpix does not match datatype") { ok = false; }
  var bad5 = fixture();
  set_u16_le(&mut bad5, 72, 7);
  if !err_header_is(nii_parse(&bad5), "nii: bitpix does not match datatype") { ok = false; }
  var b = nii_builder_new();
  if !nii_builder_set_datatype(&mut b, 64).is_ok { return assert(false, "set float64"); }
  let fr = nii_builder_finish(&b);
  if !fr.is_ok { return assert(false, "finish float64"); }
  let f64: Vec[UInt8] = fr.value;
  let pr = nii_parse(&f64);
  if !pr.is_ok { ok = false; } else {
    let h: NiftiHeader = pr.value;
    if nii_datatype(&h) != 64 { ok = false; }
    if nii_bitpix(&h) != 64 { ok = false; }
  }
  var b11 = nii_builder_new();
  if !err_unit_is(nii_builder_set_datatype(&mut b11, 128), "nii: unknown datatype 128") { ok = false; }
  return assert(ok, "datatype validation: unknown codes and bitpix mismatches rejected, table types accepted");
}

fn t12() -> TestResult {
  let negzero = hb("00000080");
  let negone = hb("000080bf");
  let positive = hb("0000803f");
  var b1 = nii_builder_new();
  var ok = nii_builder_set_float(&mut b1, NII_FLOAT_VOX_OFFSET, &negzero).is_ok;
  if !err_bytes_is(nii_builder_finish(&b1), "nii: negative vox_offset") { ok = false; }
  var b2 = nii_builder_new();
  if !nii_builder_set_float(&mut b2, NII_FLOAT_VOX_OFFSET, &negone).is_ok { ok = false; }
  if !err_bytes_is(nii_builder_finish(&b2), "nii: negative vox_offset") { ok = false; }
  var bad = fixture();
  set_u8(&mut bad, 111, 128);
  if !err_header_is(nii_parse(&bad), "nii: negative vox_offset") { ok = false; }
  var bad2 = fixture();
  set_u8(&mut bad2, 108, 0);
  set_u8(&mut bad2, 109, 0);
  set_u8(&mut bad2, 110, 128);
  set_u8(&mut bad2, 111, 191);
  if !err_header_is(nii_parse(&bad2), "nii: negative vox_offset") { ok = false; }
  var b3 = nii_builder_new();
  if !nii_builder_set_float(&mut b3, NII_FLOAT_VOX_OFFSET, &positive).is_ok { ok = false; }
  let fr = nii_builder_finish(&b3);
  if !fr.is_ok { ok = false; } else {
    let data: Vec[UInt8] = fr.value;
    let pr = nii_parse(&data);
    if !pr.is_ok { ok = false; } else {
      let h: NiftiHeader = pr.value;
      if !float_hex_is(&h, NII_FLOAT_VOX_OFFSET, "0000803f") { ok = false; }
    }
  }
  var neg_slope = fixture();
  set_u8(&mut neg_slope, 114, 128);
  set_u8(&mut neg_slope, 115, 191);
  let npr = nii_parse(&neg_slope);
  if !npr.is_ok { ok = false; } else {
    let hn: NiftiHeader = npr.value;
    if !float_hex_is(&hn, NII_FLOAT_SCL_SLOPE, "000080bf") { ok = false; }
  }
  return assert(ok, "vox_offset >= 0 via IEEE-754 sign bit (incl. -0.0); negative scl_slope allowed");
}

fn t13() -> TestResult {
  var b = nii_builder_new();
  if !nii_builder_set_intent_code(&mut b, 1001).is_ok { return assert(false, "set intent"); }
  if !nii_builder_set_qform_code(&mut b, 1).is_ok { return assert(false, "set qform"); }
  if !nii_builder_set_sform_code(&mut b, 2).is_ok { return assert(false, "set sform"); }
  if !nii_builder_set_slice_start(&mut b, 3).is_ok { return assert(false, "set slice start"); }
  if !nii_builder_set_slice_end(&mut b, 7).is_ok { return assert(false, "set slice end"); }
  if !nii_builder_set_slice_code(&mut b, 2).is_ok { return assert(false, "set slice code"); }
  if !nii_builder_set_xyzt_units(&mut b, 10).is_ok { return assert(false, "set units"); }
  let fr = nii_builder_finish(&b);
  if !fr.is_ok { return assert(false, "finish"); }
  let data: Vec[UInt8] = fr.value;
  let pr = nii_parse(&data);
  if !pr.is_ok { return assert(false, "parse"); }
  let h: NiftiHeader = pr.value;
  var ok = nii_intent_code(&h) == 1001;
  if nii_qform_code(&h) != 1 { ok = false; }
  if nii_sform_code(&h) != 2 { ok = false; }
  if nii_slice_start(&h) != 3 { ok = false; }
  if nii_slice_end(&h) != 7 { ok = false; }
  if nii_slice_code(&h) != 2 { ok = false; }
  if nii_xyzt_units(&h) != 10 { ok = false; }
  var b2 = nii_builder_new();
  if !nii_builder_set_slice_start(&mut b2, -1).is_ok { return assert(false, "set signed slice start"); }
  if !nii_builder_set_slice_end(&mut b2, -2).is_ok { return assert(false, "set signed slice end"); }
  let fr2 = nii_builder_finish(&b2);
  if !fr2.is_ok { return assert(false, "finish signed"); }
  let data2: Vec[UInt8] = fr2.value;
  let pr2 = nii_parse(&data2);
  if !pr2.is_ok { ok = false; } else {
    let h2: NiftiHeader = pr2.value;
    if nii_slice_start(&h2) != -1 { ok = false; }
    if nii_slice_end(&h2) != -2 { ok = false; }
  }
  var b13 = nii_builder_new();
  if !err_unit_is(nii_builder_set_qform_code(&mut b13, -1), "nii: form code out of range") { ok = false; }
  if !err_unit_is(nii_builder_set_sform_code(&mut b13, 40000), "nii: form code out of range") { ok = false; }
  if !err_unit_is(nii_builder_set_intent_code(&mut b13, -1), "nii: intent code out of range") { ok = false; }
  if !err_unit_is(nii_builder_set_slice_start(&mut b13, 40000), "nii: slice index out of range") { ok = false; }
  if !err_unit_is(nii_builder_set_slice_end(&mut b13, -40000), "nii: slice index out of range") { ok = false; }
  if !err_unit_is(nii_builder_set_slice_code(&mut b13, 256), "nii: slice code out of range") { ok = false; }
  if !err_unit_is(nii_builder_set_xyzt_units(&mut b13, -1), "nii: units out of range") { ok = false; }
  return assert(ok, "scalar accessors: intent/qform/sform/slice/units values, signed slice, range errors");
}

fn t14() -> TestResult {
  var b = nii_builder_new();
  if !nii_builder_set_descrip(&mut b, "abc").is_ok { return assert(false, "set descrip"); }
  if !nii_builder_set_aux_file(&mut b, "ab").is_ok { return assert(false, "set aux"); }
  if !nii_builder_set_intent_name(&mut b, "z").is_ok { return assert(false, "set intent name"); }
  let fr = nii_builder_finish(&b);
  if !fr.is_ok { return assert(false, "finish"); }
  var data: Vec[UInt8] = fr.value;
  set_u8(&mut data, 152, 200);
  set_u8(&mut data, 231, 255);
  set_u8(&mut data, 330, 7);
  let pr = nii_parse(&data);
  if !pr.is_ok { return assert(false, "parse"); }
  let h: NiftiHeader = pr.value;
  var ok = str_eq(nii_descrip(&h), "abc");
  if !str_eq(nii_aux_file(&h), "ab") { ok = false; }
  if !str_eq(nii_intent_name(&h), "z") { ok = false; }
  var sb = Vec[UInt8].new();
  var i = 0;
  while i < 80 {
    sb.push(120 as UInt8);
    i = i + 1;
  }
  let s80 = builder.sb_to_str(&sb);
  var b2 = nii_builder_new();
  if !nii_builder_set_descrip(&mut b2, s80).is_ok { return assert(false, "set 80-byte descrip"); }
  let fr2 = nii_builder_finish(&b2);
  if !fr2.is_ok { return assert(false, "finish 80-byte descrip"); }
  let data2: Vec[UInt8] = fr2.value;
  if !bytes_at_equal(data2, 148, repeat_byte(120, 80)) { ok = false; }
  let pr2 = nii_parse(&data2);
  if !pr2.is_ok { ok = false; } else {
    let h2: NiftiHeader = pr2.value;
    if !str_eq(nii_descrip(&h2), s80) { ok = false; }
  }
  sb.push(120 as UInt8);
  let s81 = builder.sb_to_str(&sb);
  var b14 = nii_builder_new();
  if !err_unit_is(nii_builder_set_descrip(&mut b14, s81), "nii: text too long") { ok = false; }
  var sb24 = Vec[UInt8].new();
  i = 0;
  while i < 25 {
    sb24.push(97 as UInt8);
    i = i + 1;
  }
  let s25 = builder.sb_to_str(&sb24);
  if !err_unit_is(nii_builder_set_aux_file(&mut b14, s25), "nii: text too long") { ok = false; }
  var sb16 = Vec[UInt8].new();
  i = 0;
  while i < 17 {
    sb16.push(98 as UInt8);
    i = i + 1;
  }
  let s17 = builder.sb_to_str(&sb16);
  if !err_unit_is(nii_builder_set_intent_name(&mut b14, s17), "nii: text too long") { ok = false; }
  return assert(ok, "text fields: descrip/aux_file/intent_name, NUL trimming, 80-byte full, length errors");
}

fn t15() -> TestResult {
  let f = fixture();
  var ok = NII_EXT_UNKNOWN == -1;
  if NII_EXT_NONE != 0 { ok = false; }
  let r0 = nii_parse(&f);
  if !r0.is_ok { return assert(false, "348-byte parse"); }
  let h0: NiftiHeader = r0.value;
  if nii_ext_flag(&h0) != NII_EXT_UNKNOWN { ok = false; }
  let f351 = cat(f, repeat_byte(0, 3));
  let r1 = nii_parse(&f351);
  if !r1.is_ok { ok = false; } else {
    let h1: NiftiHeader = r1.value;
    if nii_ext_flag(&h1) != NII_EXT_UNKNOWN { ok = false; }
  }
  let f352 = cat(f, hb("00000000"));
  let r2 = nii_parse(&f352);
  if !r2.is_ok { ok = false; } else {
    let h2: NiftiHeader = r2.value;
    if nii_ext_flag(&h2) != NII_EXT_NONE { ok = false; }
  }
  let f353 = cat(f, hb("01000000"));
  let r3 = nii_parse(&f353);
  if !r3.is_ok { ok = false; } else {
    let h3: NiftiHeader = r3.value;
    if nii_ext_flag(&h3) != 1 { ok = false; }
    if !bytes_equal(nii_to_bytes(&h3), f) { ok = false; }
  }
  let f354 = cat(f, hb("07aabbcc"));
  let r4 = nii_parse(&f354);
  if !r4.is_ok { ok = false; } else {
    let h4: NiftiHeader = r4.value;
    if nii_ext_flag(&h4) != 7 { ok = false; }
  }
  let f400 = cat(f, repeat_byte(0, 52));
  let r5 = nii_parse(&f400);
  if !r5.is_ok { ok = false; } else {
    let h5: NiftiHeader = r5.value;
    if nii_ext_flag(&h5) != NII_EXT_NONE { ok = false; }
  }
  return assert(ok, "extension flag: unknown below 352 bytes, byte 348 reported for longer buffers");
}

fn t16() -> TestResult {
  let b0 = nii_builder_new();
  let f0 = nii_builder_finish(&b0);
  if !f0.is_ok { return assert(false, "initial finish"); }
  let before: Vec[UInt8] = f0.value;
  var b = nii_builder_new();
  var ok = err_unit_is(nii_builder_set_dim(&mut b, -1, 1), "nii: dim index out of range");
  if !err_unit_is(nii_builder_set_dim(&mut b, 8, 1), "nii: dim index out of range") { ok = false; }
  if !err_unit_is(nii_builder_set_dim(&mut b, 0, -1), "nii: negative dimension") { ok = false; }
  if !err_unit_is(nii_builder_set_dim(&mut b, 0, 32768), "nii: dimension out of range") { ok = false; }
  if !err_unit_is(nii_builder_set_datatype(&mut b, 3), "nii: unknown datatype 3") { ok = false; }
  let short = repeat_byte(1, 3);
  if !err_unit_is(nii_builder_set_float(&mut b, 0, &short), "nii: float token must be 4 bytes") { ok = false; }
  if !err_unit_is(nii_builder_set_float(&mut b, 16, &short), "nii: float field out of range") { ok = false; }
  if !err_unit_is(nii_builder_set_pixdim(&mut b, 8, &short), "nii: pixdim index out of range") { ok = false; }
  if !err_unit_is(nii_builder_set_srow(&mut b, 3, 0, &short), "nii: srow index out of range") { ok = false; }
  if !err_unit_is(nii_builder_set_qform_code(&mut b, -1), "nii: form code out of range") { ok = false; }
  if !err_unit_is(nii_builder_set_sform_code(&mut b, 40000), "nii: form code out of range") { ok = false; }
  if !err_unit_is(nii_builder_set_intent_code(&mut b, -1), "nii: intent code out of range") { ok = false; }
  if !err_unit_is(nii_builder_set_slice_start(&mut b, 40000), "nii: slice index out of range") { ok = false; }
  if !err_unit_is(nii_builder_set_slice_code(&mut b, -1), "nii: slice code out of range") { ok = false; }
  if !err_unit_is(nii_builder_set_xyzt_units(&mut b, 256), "nii: units out of range") { ok = false; }
  if !err_unit_is(nii_builder_set_magic(&mut b, 5), "nii: invalid magic kind") { ok = false; }
  let fr = nii_builder_finish(&b);
  if !fr.is_ok { ok = false; } else {
    let after: Vec[UInt8] = fr.value;
    if !bytes_equal(after, before) { ok = false; }
  }
  return assert(ok, "builder errors: every documented setter failure leaves the canonical header unchanged");
}

fn t17() -> TestResult {
  var b = nii_builder_new();
  if !nii_builder_set_magic(&mut b, NII_MAGIC_PAIR).is_ok { return assert(false, "set pair"); }
  if !nii_builder_set_datatype(&mut b, 4).is_ok { return assert(false, "set int16"); }
  if !nii_builder_set_dim(&mut b, 0, 2).is_ok { return assert(false, "set dim0"); }
  if !nii_builder_set_dim(&mut b, 1, 4).is_ok { return assert(false, "set dim1"); }
  if !nii_builder_set_dim(&mut b, 2, 4).is_ok { return assert(false, "set dim2"); }
  let fr = nii_builder_finish(&b);
  if !fr.is_ok { return assert(false, "finish"); }
  let data: Vec[UInt8] = fr.value;
  let pr = nii_parse(&data);
  if !pr.is_ok { return assert(false, "parse"); }
  let h: NiftiHeader = pr.value;
  var ok = nii_magic_kind(&h) == NII_MAGIC_PAIR;
  if nii_datatype(&h) != 4 { ok = false; }
  if nii_bitpix(&h) != 16 { ok = false; }
  if nii_dim_count(&h) != 2 { ok = false; }
  let d1 = nii_dim(&h, 1);
  let d2 = nii_dim(&h, 2);
  if !d1.is_ok { ok = false; } elif d1.value != 4 { ok = false; }
  if !d2.is_ok { ok = false; } elif d2.value != 4 { ok = false; }
  if !bytes_equal(nii_to_bytes(&h), data) { ok = false; }
  return assert(ok, "ni1 header pair: magic kind 1, int16/16 datatype and dims round-trip");
}

fn t18() -> TestResult {
  let f = full_fixture();
  if f.len() != NII_HEADER_LEN {
    return assert(false, "full fixture must be 348 bytes");
  }
  let pr = nii_parse(&f);
  if !pr.is_ok {
    return assert(false, "full fixture must parse");
  }
  let h: NiftiHeader = pr.value;
  var ok = nii_dim_count(&h) == 3;
  if nii_datatype(&h) != 16 { ok = false; }
  if nii_bitpix(&h) != 32 { ok = false; }
  if nii_qform_code(&h) != 1 { ok = false; }
  if nii_sform_code(&h) != 2 { ok = false; }
  if nii_intent_code(&h) != 3 { ok = false; }
  if !pixdim_hex_is(&h, 1, "00000040") { ok = false; }
  if !pixdim_hex_is(&h, 3, "00008040") { ok = false; }
  if !float_hex_is(&h, NII_FLOAT_VOX_OFFSET, "0000b043") { ok = false; }
  if !float_hex_is(&h, NII_FLOAT_SCL_SLOPE, "0000803f") { ok = false; }
  if !srow_hex_is(&h, 0, 0, "0000803f") { ok = false; }
  if !srow_hex_is(&h, 0, 3, "000000c2") { ok = false; }
  if !srow_hex_is(&h, 1, 1, "0000803f") { ok = false; }
  if !srow_hex_is(&h, 2, 3, "000080c1") { ok = false; }
  if !str_eq(nii_descrip(&h), "XIOM NIfTI-1 header") { ok = false; }
  if !str_eq(nii_aux_file(&h), "aux.bin") { ok = false; }
  if !str_eq(nii_intent_name(&h), "mean") { ok = false; }
  if nii_magic_kind(&h) != NII_MAGIC_SINGLE { ok = false; }
  if nii_ext_flag(&h) != NII_EXT_UNKNOWN { ok = false; }
  let qb = nii_float_raw(&h, NII_FLOAT_QUATERN_B);
  if !qb.is_ok { ok = false; } else {
    let qv: Vec[UInt8] = qb.value;
    if !str_eq(nii_raw_hex(&qv), "00000000") { ok = false; }
  }
  let out1 = nii_to_bytes(&h);
  if !bytes_equal(out1, f) { ok = false; }
  let pr2 = nii_parse(&out1);
  if !pr2.is_ok { ok = false; } else {
    let h2: NiftiHeader = pr2.value;
    if !bytes_equal(nii_to_bytes(&h2), f) { ok = false; }
    if !float_hex_is(&h2, NII_FLOAT_QOFFSET_X, "0000803e") { ok = false; }
    if !str_eq(nii_descrip(&h2), "XIOM NIfTI-1 header") { ok = false; }
  }
  let padded = cat(f, hb("00000000"));
  let pr3 = nii_parse(&padded);
  if !pr3.is_ok { ok = false; } else {
    let h3: NiftiHeader = pr3.value;
    if nii_ext_flag(&h3) != NII_EXT_NONE { ok = false; }
    if !bytes_equal(nii_to_bytes(&h3), f) { ok = false; }
  }
  return assert(ok, "full field matrix: builder -> parse -> canonical bytes, padded variant");
}

fn main() -> Int {
  io.println("=== xiom.nii conformance tests ===");
  var failed: Int = 0;
  let r1 = t1();
  failed = failed + report(r1.passed, r1.name);
  let r2 = t2();
  failed = failed + report(r2.passed, r2.name);
  let r3 = t3();
  failed = failed + report(r3.passed, r3.name);
  let r4 = t4();
  failed = failed + report(r4.passed, r4.name);
  let r5 = t5();
  failed = failed + report(r5.passed, r5.name);
  let r6 = t6();
  failed = failed + report(r6.passed, r6.name);
  let r7 = t7();
  failed = failed + report(r7.passed, r7.name);
  let r8 = t8();
  failed = failed + report(r8.passed, r8.name);
  let r9 = t9();
  failed = failed + report(r9.passed, r9.name);
  let r10 = t10();
  failed = failed + report(r10.passed, r10.name);
  let r11 = t11();
  failed = failed + report(r11.passed, r11.name);
  let r12 = t12();
  failed = failed + report(r12.passed, r12.name);
  let r13 = t13();
  failed = failed + report(r13.passed, r13.name);
  let r14 = t14();
  failed = failed + report(r14.passed, r14.name);
  let r15 = t15();
  failed = failed + report(r15.passed, r15.name);
  let r16 = t16();
  failed = failed + report(r16.passed, r16.name);
  let r17 = t17();
  failed = failed + report(r17.passed, r17.name);
  let r18 = t18();
  failed = failed + report(r18.passed, r18.name);
  if failed == 0 {
    io.println("xiom.nii: all tests passed");
  } else {
    io.println("xiom.nii: tests failed");
  }
  return failed;
}
