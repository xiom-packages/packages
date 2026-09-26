// XIOM -- xiom.efi conformance tests (22 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Port task: prove the pure-XIOM xiom.efi codec against the rules pinned in
// SPEC.md: the 24-byte small header, the 32-byte large-file header with the
// 0xFFFFFF extended-size rule, the section walk with its documented per-type
// headers (COMPRESSION, GUID_DEFINED, VERSION, USER_INTERFACE,
// FREEFORM_SUBTYPE_GUID), unknown-type pass-through, the 4-byte section and
// 8-byte file alignment padding, the raw integrity-check stances, the error
// catalog and build/parse round trips.
//
// Fixtures are assembled byte by byte in this file, so ffs_parse is
// exercised against bytes the test controls rather than only against
// ffs_build. Str comparisons go through xiom.string.compare's str_compare
// (BUG 17: `==` on Str values read from Vec elements lowers to a pointer
// comparison); every Vec element read is bound to an explicitly typed local
// and every `&` argument is a local binding (never a field or call result).

module efi_tests
use xiom.io; use xiom.test;
use xiom.efi;
use xiom.string;
use xiom.string.compare;
use xiom.encoding.hex;

// --------------------------------------------------
//  Byte helpers (independent of src/efi.xi)
// --------------------------------------------------

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn bytes_equal(a: Vec[UInt8], b: Vec[UInt8]) -> Bool {
  if a.len() != b.len() { return false; }
  var i = 0;
  while i < a.len() {
    if a[i] != b[i] { return false; }
    i = i + 1;
  }
  return true;
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

// Bytes for a hex string (empty on malformed input; the test then fails on
// the byte comparison).
fn hb(hexstr: Str) -> Vec[UInt8] {
  let r = hex.hex_decode(hexstr);
  if r.is_ok {
    let b: Vec[UInt8] = r.value;
    return b;
  }
  return Vec[UInt8].new();
}

fn zeros(n: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < n {
    v.push(0 as UInt8);
    i = i + 1;
  }
  return v;
}

fn concat(a: Vec[UInt8], b: Vec[UInt8]) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < a.len() {
    v.push(a[i]);
    i = i + 1;
  }
  var j = 0;
  while j < b.len() {
    v.push(b[j]);
    j = j + 1;
  }
  return v;
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

fn put_le16(v: Vec[UInt8], pos: Int, val: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < v.len() {
    if i == pos {
      out.push((val % 256) as UInt8);
    } elif i == pos + 1 {
      out.push(((val / 256) % 256) as UInt8);
    } else {
      out.push(v[i]);
    }
    i = i + 1;
  }
  return out;
}

fn put_le24(v: Vec[UInt8], pos: Int, val: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < v.len() {
    if i == pos {
      out.push((val % 256) as UInt8);
    } elif i == pos + 1 {
      out.push(((val / 256) % 256) as UInt8);
    } elif i == pos + 2 {
      out.push(((val / 65536) % 256) as UInt8);
    } else {
      out.push(v[i]);
    }
    i = i + 1;
  }
  return out;
}

fn le24_at(v: Vec[UInt8], pos: Int) -> Int {
  let b0: Int = (v[pos] as Int) & 0xFF;
  let b1: Int = (v[pos + 1] as Int) & 0xFF;
  let b2: Int = (v[pos + 2] as Int) & 0xFF;
  return b0 + b1 * 256 + b2 * 65536;
}

// Independent additive byte sum used to cross-check the codec's checksum
// helpers.
fn sum_range(v: &Vec[UInt8], start: Int, count: Int) -> Int {
  var s = 0;
  var i = 0;
  while i < count {
    let b: Int = (v[start + i] as Int) & 0xFF;
    s = s + b;
    i = i + 1;
  }
  return s;
}

fn err_file_is(r: Result[FfsFile, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return streq(r.error, want);
}

fn err_bytes_is(r: Result[Vec[UInt8], Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return streq(r.error, want);
}

// --------------------------------------------------
//  Byte-level fixtures
// --------------------------------------------------

// Small file: name 00..ff, type 0x07, attributes 0x00, state 0x07, declared
// size 48. Section 0: RAW (0x19), 8 bytes, data "abcd" + 2 pad. Section 1:
// USER_INTERFACE (0x15), 16 bytes, "boot" UTF-16LE + NUL + 2 pad.
fn small_fixture() -> Vec[UInt8] {
  let s: Str = "00112233445566778899aabbccddeeff" + "0000" + "07" + "00" + "300000" + "07" + "08000019abcd0000" + "1000001562006f006f00740000000000";
  return hb(s);
}

// One VERSION section (0x14), 8 bytes: BuildNumber 0x0102 LE, Version 0x0304
// LE. File declared size 32.
fn version_fixture() -> Vec[UInt8] {
  let s: Str = "00112233445566778899aabbccddeeff" + "0000" + "07" + "00" + "200000" + "00" + "08000014" + "0201" + "0403";
  return hb(s);
}

// One GUID_DEFINED section (0x02), 28 bytes: GUID 01..10, DataOffset 24,
// Attributes 1, data "xyz{" (4 bytes, so no section pad). File declared
// size 56 with a 4-byte trailing zero file-alignment pad.
fn guid_fixture() -> Vec[UInt8] {
  let s: Str = "ffeeddccbbaa99887766554433221100" + "0000" + "07" + "00" + "380000" + "07" + "1c000002" + "0102030405060708090a0b0c0d0e0f10" + "1800" + "0100" + "78797a7b" + "00000000";
  return hb(s);
}

// One COMPRESSION section (0x01), 12 bytes: uncompressed length 0x00010000,
// raw nested payload "deadbeef". File declared size 40.
fn compression_fixture() -> Vec[UInt8] {
  let s: Str = "ffeeddccbbaa99887766554433221100" + "0000" + "07" + "00" + "280000" + "07" + "0c000001" + "00000100" + "deadbeef" + "00000000";
  return hb(s);
}

// One unknown section type (0x42), 8 bytes, data "aabb" + 2 pad. File
// declared size 32.
fn unknown_fixture() -> Vec[UInt8] {
  let s: Str = "00112233445566778899aabbccddeeff" + "0000" + "07" + "00" + "200000" + "07" + "08000042aabb0000";
  return hb(s);
}

// Large file: attribute bit 0x01 set, 24-bit size field 0xFFFFFF, ExtendedSize
// 40 (u64 LE), one RAW section (8 bytes) at offset 32.
fn large_fixture() -> Vec[UInt8] {
  let s: Str = "ffeeddccbbaa99887766554433221100" + "0000" + "0b" + "01" + "ffffff" + "07" + "2800000000000000" + "08000019dead0000";
  return hb(s);
}

// One UI section whose second code unit is 0x00E9 (non-ASCII -> '?').
fn ui_nonascii_fixture() -> Vec[UInt8] {
  let s: Str = "00112233445566778899aabbccddeeff" + "0000" + "07" + "00" + "280000" + "07" + "0c000015" + "4100e9000000" + "0000" + "00000000";
  return hb(s);
}

// Section walk diagnostics: a valid RAW section then a 2-byte non-zero tail
// (declared size 34) or a 2-byte zero pad.
fn tail_fixture(tail_hex: Str) -> Vec[UInt8] {
  let s: Str = "00112233445566778899aabbccddeeff" + "0000" + "07" + "00" + "220000" + "07" + "08000019abcd0000" + tail_hex;
  return hb(s);
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  let data = small_fixture();
  let pr = ffs_parse(&data);
  if !pr.is_ok { return assert(false, "small fixture must parse"); }
  let f: FfsFile = pr.value;
  var ok = data.len() == 48;
  if !streq(ffs_file_name(&f), "00112233445566778899aabbccddeeff") { ok = false; }
  if ffs_file_type(&f) != 7 { ok = false; }
  if ffs_file_attributes(&f) != 0 { ok = false; }
  if ffs_file_size(&f) != 48 { ok = false; }
  if ffs_file_state(&f) != 7 { ok = false; }
  if ffs_file_integrity_check(&f) != 0 { ok = false; }
  if ffs_file_is_large(&f) { ok = false; }
  if ffs_file_header_size(&f) != 24 { ok = false; }
  return assert(ok, "small fixture: header fields pinned");
}

fn t2() -> TestResult {
  let data = small_fixture();
  let pr = ffs_parse(&data);
  if !pr.is_ok { return assert(false, "small fixture must parse"); }
  let f: FfsFile = pr.value;
  var ok = ffs_section_count(&f) == 2;
  if ffs_section_type(&f, 0) != 25 { ok = false; }
  if ffs_section_type(&f, 1) != 21 { ok = false; }
  if ffs_section_size(&f, 0) != 8 { ok = false; }
  if ffs_section_size(&f, 1) != 16 { ok = false; }
  if ffs_section_offset(&f, 0) != 24 { ok = false; }
  if ffs_section_offset(&f, 1) != 32 { ok = false; }
  if ffs_section_data_offset(&f, 0) != 28 { ok = false; }
  if ffs_section_data_offset(&f, 1) != 36 { ok = false; }
  if ffs_section_data_size(&f, 0) != 4 { ok = false; }
  if ffs_section_data_size(&f, 1) != 12 { ok = false; }
  return assert(ok, "small fixture: section columns pinned");
}

fn t3() -> TestResult {
  let data = small_fixture();
  let pr = ffs_parse(&data);
  if !pr.is_ok { return assert(false, "small fixture must parse"); }
  let f: FfsFile = pr.value;
  let rr0 = ffs_section_raw(&data, &f, 0);
  if !rr0.is_ok { return assert(false, "raw 0 must succeed"); }
  let r0: Vec[UInt8] = rr0.value;
  var ok = bytes_equal(r0, hb("08000019abcd0000"));
  let rd0 = ffs_section_data(&data, &f, 0);
  if !rd0.is_ok { return assert(false, "data 0 must succeed"); }
  let d0: Vec[UInt8] = rd0.value;
  if !bytes_equal(d0, hb("abcd0000")) { ok = false; }
  let rr1 = ffs_section_raw(&data, &f, 1);
  if !rr1.is_ok { return assert(false, "raw 1 must succeed"); }
  let r1: Vec[UInt8] = rr1.value;
  if !bytes_equal(r1, hb("1000001562006f006f00740000000000")) { ok = false; }
  let rd1 = ffs_section_data(&data, &f, 1);
  if !rd1.is_ok { return assert(false, "data 1 must succeed"); }
  let d1: Vec[UInt8] = rd1.value;
  if !bytes_equal(d1, hb("62006f006f00740000000000")) { ok = false; }
  return assert(ok, "section raw and data spans are exact");
}

fn t4() -> TestResult {
  let data = small_fixture();
  let pr = ffs_parse(&data);
  if !pr.is_ok { return assert(false, "small fixture must parse"); }
  let f: FfsFile = pr.value;
  var ok = streq(ffs_section_ui_string(&data, &f, 1), "boot");
  if !streq(ffs_section_ui_string(&data, &f, 0), "") { ok = false; }
  let data2 = ui_nonascii_fixture();
  let pr2 = ffs_parse(&data2);
  if !pr2.is_ok { return assert(false, "non-ASCII UI fixture must parse"); }
  let f2: FfsFile = pr2.value;
  if !streq(ffs_section_ui_string(&data2, &f2, 0), "A?") { ok = false; }
  return assert(ok, "UI strings decode from UTF-16LE; non-ASCII becomes '?'");
}

fn t5() -> TestResult {
  let data = version_fixture();
  let pr = ffs_parse(&data);
  if !pr.is_ok { return assert(false, "version fixture must parse"); }
  let f: FfsFile = pr.value;
  var ok = ffs_section_count(&f) == 1;
  if ffs_section_type(&f, 0) != 20 { ok = false; }
  if ffs_section_build_number(&data, &f, 0) != 258 { ok = false; }
  if ffs_section_version(&data, &f, 0) != 772 { ok = false; }
  let rd = ffs_section_data(&data, &f, 0);
  if !rd.is_ok { ok = false; } else {
    let body: Vec[UInt8] = rd.value;
    if !bytes_equal(body, hb("02010403")) { ok = false; }
  }
  let body2: Vec[UInt8] = hb("02010403");
  let br = ffs_build("00112233445566778899aabbccddeeff", 7, 0, 0, 20, &body2);
  if !br.is_ok { ok = false; } else {
    let built: Vec[UInt8] = br.value;
    if !bytes_equal(built, data) { ok = false; }
  }
  return assert(ok, "VERSION section fields and builder round-trip");
}

fn t6() -> TestResult {
  let data = guid_fixture();
  let pr = ffs_parse(&data);
  if !pr.is_ok { return assert(false, "GUID fixture must parse"); }
  let f: FfsFile = pr.value;
  var ok = data.len() == 56;
  if ffs_file_size(&f) != 56 { ok = false; }
  if ffs_section_count(&f) != 1 { ok = false; }
  if ffs_section_type(&f, 0) != 2 { ok = false; }
  if !streq(ffs_section_guid(&data, &f, 0), "0102030405060708090a0b0c0d0e0f10") { ok = false; }
  if ffs_section_guid_data_offset(&data, &f, 0) != 24 { ok = false; }
  if ffs_section_guid_attributes(&data, &f, 0) != 1 { ok = false; }
  if ffs_section_data_offset(&f, 0) != 48 { ok = false; }
  if ffs_section_data_size(&f, 0) != 4 { ok = false; }
  let rd = ffs_section_data(&data, &f, 0);
  if !rd.is_ok { ok = false; } else {
    let body: Vec[UInt8] = rd.value;
    if !bytes_equal(body, hb("78797a7b")) { ok = false; }
  }
  return assert(ok, "GUID_DEFINED section: GUID, data offset, attributes, span");
}

fn t7() -> TestResult {
  let data = compression_fixture();
  let pr = ffs_parse(&data);
  if !pr.is_ok { return assert(false, "compression fixture must parse"); }
  let f: FfsFile = pr.value;
  var ok = ffs_section_count(&f) == 1;
  if ffs_section_type(&f, 0) != 1 { ok = false; }
  if ffs_section_compression_length(&data, &f, 0) != 65536 { ok = false; }
  if ffs_section_data_offset(&f, 0) != 32 { ok = false; }
  if ffs_section_data_size(&f, 0) != 4 { ok = false; }
  let rd = ffs_section_data(&data, &f, 0);
  if !rd.is_ok { ok = false; } else {
    let body: Vec[UInt8] = rd.value;
    if !bytes_equal(body, hb("deadbeef")) { ok = false; }
  }
  return assert(ok, "COMPRESSION section: length field, raw nested payload");
}

fn t8() -> TestResult {
  let data = unknown_fixture();
  let pr = ffs_parse(&data);
  if !pr.is_ok { return assert(false, "unknown-type fixture must parse"); }
  let f: FfsFile = pr.value;
  var ok = ffs_section_count(&f) == 1;
  if ffs_section_type(&f, 0) != 66 { ok = false; }
  if !streq(ffs_section_type_name(66), "UNKNOWN") { ok = false; }
  let rd = ffs_section_data(&data, &f, 0);
  if !rd.is_ok { ok = false; } else {
    let body: Vec[UInt8] = rd.value;
    if !bytes_equal(body, hb("aabb0000")) { ok = false; }
  }
  return assert(ok, "unknown section types pass through raw");
}

fn t9() -> TestResult {
  var ok = streq(ffs_file_type_name(1), "RAW");
  if !streq(ffs_file_type_name(2), "FREEFORM") { ok = false; }
  if !streq(ffs_file_type_name(3), "SECURITY_CORE") { ok = false; }
  if !streq(ffs_file_type_name(4), "PEI_CORE") { ok = false; }
  if !streq(ffs_file_type_name(5), "DXE_CORE") { ok = false; }
  if !streq(ffs_file_type_name(7), "DRIVER") { ok = false; }
  if !streq(ffs_file_type_name(9), "APPLICATION") { ok = false; }
  if !streq(ffs_file_type_name(10), "SMM") { ok = false; }
  if !streq(ffs_file_type_name(11), "FIRMWARE_VOLUME_IMAGE") { ok = false; }
  if !streq(ffs_file_type_name(12), "COMBINED_PEIM") { ok = false; }
  if !streq(ffs_file_type_name(13), "PEIM") { ok = false; }
  if !streq(ffs_file_type_name(14), "DXE_DRIVER") { ok = false; }
  if !streq(ffs_file_type_name(15), "SMM_DRIVER") { ok = false; }
  if !streq(ffs_file_type_name(16), "SMM_CORE") { ok = false; }
  if !streq(ffs_file_type_name(224), "OEM") { ok = false; }
  if !streq(ffs_file_type_name(239), "OEM") { ok = false; }
  if !streq(ffs_file_type_name(240), "PAD") { ok = false; }
  if !streq(ffs_file_type_name(241), "FFS") { ok = false; }
  if !streq(ffs_file_type_name(254), "FFS") { ok = false; }
  if !streq(ffs_file_type_name(255), "FREE_SPACE") { ok = false; }
  if !streq(ffs_file_type_name(66), "UNKNOWN") { ok = false; }
  if !streq(ffs_section_type_name(1), "COMPRESSION") { ok = false; }
  if !streq(ffs_section_type_name(2), "GUID_DEFINED") { ok = false; }
  if !streq(ffs_section_type_name(3), "DISPOSABLE") { ok = false; }
  if !streq(ffs_section_type_name(16), "PE32") { ok = false; }
  if !streq(ffs_section_type_name(17), "PIC") { ok = false; }
  if !streq(ffs_section_type_name(18), "TE") { ok = false; }
  if !streq(ffs_section_type_name(19), "DXE_DEPEX") { ok = false; }
  if !streq(ffs_section_type_name(20), "VERSION") { ok = false; }
  if !streq(ffs_section_type_name(21), "USER_INTERFACE") { ok = false; }
  if !streq(ffs_section_type_name(22), "COMPATIBILITY16") { ok = false; }
  if !streq(ffs_section_type_name(23), "FIRMWARE_VOLUME_IMAGE") { ok = false; }
  if !streq(ffs_section_type_name(24), "FREEFORM_SUBTYPE_GUID") { ok = false; }
  if !streq(ffs_section_type_name(25), "RAW") { ok = false; }
  if !streq(ffs_section_type_name(27), "PEI_DEPEX") { ok = false; }
  if !streq(ffs_section_type_name(28), "SMM_DEPEX") { ok = false; }
  if !streq(ffs_section_type_name(66), "UNKNOWN") { ok = false; }
  return assert(ok, "documented type-name tables");
}

fn t10() -> TestResult {
  let data = large_fixture();
  let pr = ffs_parse(&data);
  if !pr.is_ok { return assert(false, "large fixture must parse"); }
  let f: FfsFile = pr.value;
  var ok = data.len() == 40;
  if !streq(ffs_file_name(&f), "ffeeddccbbaa99887766554433221100") { ok = false; }
  if ffs_file_type(&f) != 11 { ok = false; }
  if ffs_file_attributes(&f) != 1 { ok = false; }
  if !ffs_file_is_large(&f) { ok = false; }
  if ffs_file_header_size(&f) != 32 { ok = false; }
  if ffs_file_size(&f) != 40 { ok = false; }
  if ffs_file_state(&f) != 7 { ok = false; }
  if ffs_section_count(&f) != 1 { ok = false; }
  if ffs_section_type(&f, 0) != 25 { ok = false; }
  if ffs_section_size(&f, 0) != 8 { ok = false; }
  if ffs_section_offset(&f, 0) != 32 { ok = false; }
  if ffs_section_data_offset(&f, 0) != 36 { ok = false; }
  if ffs_section_data_size(&f, 0) != 4 { ok = false; }
  let rd = ffs_section_data(&data, &f, 0);
  if !rd.is_ok { ok = false; } else {
    let body: Vec[UInt8] = rd.value;
    if !bytes_equal(body, hb("dead0000")) { ok = false; }
  }
  return assert(ok, "large-file fixture: 32-byte header and ExtendedSize");
}

fn t11() -> TestResult {
  let empty = Vec[UInt8].new();
  var ok = err_file_is(ffs_parse(&empty), "efi: truncated header");
  let short23 = prefix(small_fixture(), 23);
  if !err_file_is(ffs_parse(&short23), "efi: truncated header") { ok = false; }
  let large31 = prefix(large_fixture(), 31);
  if !err_file_is(ffs_parse(&large31), "efi: truncated header") { ok = false; }
  let bad_field = put_le24(large_fixture(), 20, 3145728);
  if !err_file_is(ffs_parse(&bad_field), "efi: bad large-file size") { ok = false; }
  let neg = set_byte(large_fixture(), 31, 128);
  if !err_file_is(ffs_parse(&neg), "efi: bad file size") { ok = false; }
  return assert(ok, "parse errors: header truncation and large-file rule");
}

fn t12() -> TestResult {
  let zero = put_le24(small_fixture(), 20, 0);
  var ok = err_file_is(ffs_parse(&zero), "efi: bad file size");
  let tiny = put_le24(small_fixture(), 20, 23);
  if !err_file_is(ffs_parse(&tiny), "efi: bad file size") { ok = false; }
  let big = put_le24(small_fixture(), 20, 64);
  if !err_file_is(ffs_parse(&big), "efi: truncated file") { ok = false; }
  let cut = prefix(small_fixture(), 47);
  if !err_file_is(ffs_parse(&cut), "efi: truncated file") { ok = false; }
  let lcut = prefix(large_fixture(), 36);
  if !err_file_is(ffs_parse(&lcut), "efi: truncated file") { ok = false; }
  return assert(ok, "parse errors: file size and buffer truncation");
}

fn t13() -> TestResult {
  let s0 = put_le24(small_fixture(), 24, 0);
  var ok = err_file_is(ffs_parse(&s0), "efi: bad section size");
  let s3 = put_le24(small_fixture(), 24, 3);
  if !err_file_is(ffs_parse(&s3), "efi: bad section size") { ok = false; }
  let over = put_le24(small_fixture(), 24, 40);
  if !err_file_is(ffs_parse(&over), "efi: section overruns file") { ok = false; }
  let tail_bad = tail_fixture("0102");
  if !err_file_is(ffs_parse(&tail_bad), "efi: truncated section") { ok = false; }
  let tail_pad = tail_fixture("0000");
  let pr = ffs_parse(&tail_pad);
  if !pr.is_ok { ok = false; } else {
    let f: FfsFile = pr.value;
    if ffs_section_count(&f) != 1 { ok = false; }
    if ffs_file_size(&f) != 34 { ok = false; }
  }
  let one_pad = tail_fixture("00");
  let op = put_le24(one_pad, 20, 33);
  let pr2 = ffs_parse(&op);
  if !pr2.is_ok { ok = false; } else {
    let f2: FfsFile = pr2.value;
    if ffs_section_count(&f2) != 1 { ok = false; }
  }
  return assert(ok, "parse errors: section size, overrun and trailer");
}

fn t14() -> TestResult {
  let comp: Vec[UInt8] = hb("00112233445566778899aabbccddeeff" + "0000" + "07" + "00" + "1e0000" + "07" + "060000010000");
  var ok = err_file_is(ffs_parse(&comp), "efi: section too small");
  let ver: Vec[UInt8] = hb("00112233445566778899aabbccddeeff" + "0000" + "07" + "00" + "1e0000" + "07" + "060000140201");
  if !err_file_is(ffs_parse(&ver), "efi: section too small") { ok = false; }
  let freeg: Vec[UInt8] = hb("00112233445566778899aabbccddeeff" + "0000" + "07" + "00" + "280000" + "07" + "10000018" + "000000000000000000000000");
  if !err_file_is(ffs_parse(&freeg), "efi: section too small") { ok = false; }
  let gdef: Vec[UInt8] = hb("00112233445566778899aabbccddeeff" + "0000" + "07" + "00" + "2c0000" + "07" + "14000002" + "00000000000000000000000000000000");
  if !err_file_is(ffs_parse(&gdef), "efi: section too small") { ok = false; }
  let doff_low = put_le16(guid_fixture(), 44, 10);
  if !err_file_is(ffs_parse(&doff_low), "efi: bad section data offset") { ok = false; }
  let doff_high = put_le16(guid_fixture(), 44, 40);
  if !err_file_is(ffs_parse(&doff_high), "efi: bad section data offset") { ok = false; }
  return assert(ok, "parse errors: per-type minima and GUID data offset");
}

fn t15() -> TestResult {
  let no_nul: Vec[UInt8] = hb("00112233445566778899aabbccddeeff" + "0000" + "07" + "00" + "200000" + "07" + "08000015" + "41004200");
  var ok = err_file_is(ffs_parse(&no_nul), "efi: bad ui string");
  let odd: Vec[UInt8] = hb("00112233445566778899aabbccddeeff" + "0000" + "07" + "00" + "1f0000" + "07" + "07000015" + "410042");
  if !err_file_is(ffs_parse(&odd), "efi: bad ui string") { ok = false; }
  return assert(ok, "parse errors: invalid UI strings");
}

fn t16() -> TestResult {
  let data = small_fixture();
  let pr = ffs_parse(&data);
  if !pr.is_ok { return assert(false, "small fixture must parse"); }
  let f: FfsFile = pr.value;
  var ok = ffs_header_checksum(&data, &f) == 202;
  if ffs_data_checksum(&data, &f) != 142 { ok = false; }
  if !ffs_integrity_ok(&data, &f) { ok = false; }
  let hzero = set_byte(data, 16, 0);
  if ffs_header_checksum(&hzero, &f) != 202 { ok = false; }
  let dsum: Int = sum_range(&data, 24, 24);
  let want_data: Int = (256 - dsum % 256) % 256;
  if ffs_data_checksum(&data, &f) != want_data { ok = false; }
  let cks = put_le16(set_byte(data, 19, 64), 16, 36604);
  let cpr = ffs_parse(&cks);
  if !cpr.is_ok { return assert(false, "checksum fixture must parse"); }
  let cf: FfsFile = cpr.value;
  if ffs_header_checksum(&cks, &cf) != 252 { ok = false; }
  if !ffs_integrity_ok(&cks, &cf) { ok = false; }
  let corrupt = set_byte(cks, 27, 0);
  let xpr = ffs_parse(&corrupt);
  if !xpr.is_ok { ok = false; } else {
    let xf: FfsFile = xpr.value;
    if ffs_integrity_ok(&corrupt, &xf) { ok = false; }
  }
  let nonzero = set_byte(data, 16, 1);
  let npr = ffs_parse(&nonzero);
  if !npr.is_ok { ok = false; } else {
    let nf: FfsFile = npr.value;
    if ffs_integrity_ok(&nonzero, &nf) { ok = false; }
  }
  let short = prefix(data, 20);
  if ffs_header_checksum(&short, &f) != -1 { ok = false; }
  if ffs_data_checksum(&short, &f) != -1 { ok = false; }
  if ffs_integrity_ok(&short, &f) { ok = false; }
  return assert(ok, "integrity stances: zero vector and additive checksums");
}

fn t17() -> TestResult {
  let body: Vec[UInt8] = hb("abcd");
  let br = ffs_build("00112233445566778899aabbccddeeff", 7, 0, 7, 25, &body);
  if !br.is_ok { return assert(false, "build must succeed"); }
  let built: Vec[UInt8] = br.value;
  var ok = built.len() == 32;
  if !bytes_equal(built, hb("00112233445566778899aabbccddeeff" + "0000" + "07" + "00" + "200000" + "07" + "08000019abcd0000")) { ok = false; }
  let pr = ffs_parse(&built);
  if !pr.is_ok { return assert(false, "built file must parse"); }
  let f: FfsFile = pr.value;
  if !streq(ffs_file_name(&f), "00112233445566778899aabbccddeeff") { ok = false; }
  if ffs_section_count(&f) != 1 { ok = false; }
  if ffs_section_type(&f, 0) != 25 { ok = false; }
  if ffs_section_size(&f, 0) != 8 { ok = false; }
  if ffs_file_size(&f) != 32 { ok = false; }
  return assert(ok, "builder: canonical RAW bytes and parse-back");
}

fn t18() -> TestResult {
  let body: Vec[UInt8] = hb("62006f006f0074000000");
  let br = ffs_build("00112233445566778899aabbccddeeff", 7, 0, 7, 21, &body);
  if !br.is_ok { return assert(false, "UI build must succeed"); }
  let built: Vec[UInt8] = br.value;
  var ok = bytes_equal(built, hb("00112233445566778899aabbccddeeff" + "0000" + "07" + "00" + "280000" + "07" + "10000015" + "62006f006f0074000000" + "0000"));
  if built.len() != 40 { ok = false; }
  let pr = ffs_parse(&built);
  if !pr.is_ok { return assert(false, "built UI file must parse"); }
  let f: FfsFile = pr.value;
  if !streq(ffs_section_ui_string(&built, &f, 0), "boot") { ok = false; }
  if ffs_section_size(&f, 0) != 16 { ok = false; }
  if ffs_section_data_size(&f, 0) != 12 { ok = false; }
  return assert(ok, "builder: UI section bytes, alignment and parse-back");
}

fn t19() -> TestResult {
  let b0 = Vec[UInt8].new();
  let b1: Vec[UInt8] = hb("ab");
  let b2: Vec[UInt8] = hb("abcd");
  let b3: Vec[UInt8] = hb("abcdef");
  let b4: Vec[UInt8] = hb("abcdef0102");
  let r0 = ffs_build("00112233445566778899aabbccddeeff", 7, 0, 0, 25, &b0);
  let r1 = ffs_build("00112233445566778899aabbccddeeff", 7, 0, 0, 25, &b1);
  let r2 = ffs_build("00112233445566778899aabbccddeeff", 7, 0, 0, 25, &b2);
  let r3 = ffs_build("00112233445566778899aabbccddeeff", 7, 0, 0, 25, &b3);
  let r4 = ffs_build("00112233445566778899aabbccddeeff", 7, 0, 0, 25, &b4);
  var ok = r0.is_ok && r1.is_ok && r2.is_ok && r3.is_ok && r4.is_ok;
  if !ok { return assert(false, "all five builds must succeed"); }
  let g0: Vec[UInt8] = r0.value;
  let g1: Vec[UInt8] = r1.value;
  let g2: Vec[UInt8] = r2.value;
  let g3: Vec[UInt8] = r3.value;
  let g4: Vec[UInt8] = r4.value;
  if g0.len() % 8 != 0 { ok = false; }
  if g1.len() % 8 != 0 { ok = false; }
  if g2.len() % 8 != 0 { ok = false; }
  if g3.len() % 8 != 0 { ok = false; }
  if g4.len() % 8 != 0 { ok = false; }
  let s0: Int = le24_at(g0, 24);
  let s1: Int = le24_at(g1, 24);
  let s2: Int = le24_at(g2, 24);
  let s3: Int = le24_at(g3, 24);
  let s4: Int = le24_at(g4, 24);
  if s0 != 4 || s0 % 4 != 0 { ok = false; }
  if s1 != 8 || s1 % 4 != 0 { ok = false; }
  if s2 != 8 || s2 % 4 != 0 { ok = false; }
  if s3 != 8 || s3 % 4 != 0 { ok = false; }
  if s4 != 12 || s4 % 4 != 0 { ok = false; }
  let p1 = ffs_parse(&g1);
  if !p1.is_ok { ok = false; } else {
    let f1: FfsFile = p1.value;
    if ffs_section_count(&f1) != 1 { ok = false; }
    if ffs_section_data_size(&f1, 0) != 4 { ok = false; }
  }
  return assert(ok, "builder: 4-byte section and 8-byte file alignment");
}

fn t20() -> TestResult {
  let body: Vec[UInt8] = hb("abcd");
  let b2: Vec[UInt8] = hb("0201");
  let b3: Vec[UInt8] = hb("000000");
  let b16: Vec[UInt8] = hb("00");
  let b19: Vec[UInt8] = hb("0102030405060708090a0b0c0d0e0f101112");
  let b20bad: Vec[UInt8] = hb("0102030405060708090a0b0c0d0e0f100a000100");
  let b_ui_bad: Vec[UInt8] = hb("4100");
  let b_ui_odd: Vec[UInt8] = hb("410042");
  var ok = err_bytes_is(ffs_build("0123", 7, 0, 0, 25, &body), "efi: bad name");
  if !err_bytes_is(ffs_build("00112233445566778899aabbccddeeff0", 7, 0, 0, 25, &body), "efi: bad name") { ok = false; }
  if !err_bytes_is(ffs_build("zz112233445566778899aabbccddeeff", 7, 0, 0, 25, &body), "efi: bad name") { ok = false; }
  if !err_bytes_is(ffs_build("00112233445566778899aabbccddeeff", -1, 0, 0, 25, &body), "efi: bad file type") { ok = false; }
  if !err_bytes_is(ffs_build("00112233445566778899aabbccddeeff", 256, 0, 0, 25, &body), "efi: bad file type") { ok = false; }
  if !err_bytes_is(ffs_build("00112233445566778899aabbccddeeff", 7, 256, 0, 25, &body), "efi: bad attributes") { ok = false; }
  if !err_bytes_is(ffs_build("00112233445566778899aabbccddeeff", 7, 1, 0, 25, &body), "efi: large files unsupported") { ok = false; }
  if !err_bytes_is(ffs_build("00112233445566778899aabbccddeeff", 7, 0, -1, 25, &body), "efi: bad state") { ok = false; }
  if !err_bytes_is(ffs_build("00112233445566778899aabbccddeeff", 7, 0, 256, 25, &body), "efi: bad state") { ok = false; }
  if !err_bytes_is(ffs_build("00112233445566778899aabbccddeeff", 7, 0, 0, -1, &body), "efi: bad section type") { ok = false; }
  if !err_bytes_is(ffs_build("00112233445566778899aabbccddeeff", 7, 0, 0, 256, &body), "efi: bad section type") { ok = false; }
  if !err_bytes_is(ffs_build("00112233445566778899aabbccddeeff", 7, 0, 0, 20, &b2), "efi: bad section body") { ok = false; }
  if !err_bytes_is(ffs_build("00112233445566778899aabbccddeeff", 7, 0, 0, 1, &b3), "efi: bad section body") { ok = false; }
  if !err_bytes_is(ffs_build("00112233445566778899aabbccddeeff", 7, 0, 0, 24, &b16), "efi: bad section body") { ok = false; }
  if !err_bytes_is(ffs_build("00112233445566778899aabbccddeeff", 7, 0, 0, 2, &b19), "efi: bad section body") { ok = false; }
  if !err_bytes_is(ffs_build("00112233445566778899aabbccddeeff", 7, 0, 0, 2, &b20bad), "efi: bad section body") { ok = false; }
  if !err_bytes_is(ffs_build("00112233445566778899aabbccddeeff", 7, 0, 0, 21, &b_ui_bad), "efi: bad section body") { ok = false; }
  if !err_bytes_is(ffs_build("00112233445566778899aabbccddeeff", 7, 0, 0, 21, &b_ui_odd), "efi: bad section body") { ok = false; }
  return assert(ok, "builder errors: name, type, attributes, state, body");
}

fn drift_file() -> FfsFile {
  var ty = Vec[Int].new();
  ty.push(25);
  var sz = Vec[Int].new();
  sz.push(8);
  var of = Vec[Int].new();
  of.push(24);
  var dof = Vec[Int].new();
  var dsz = Vec[Int].new();
  dsz.push(4);
  let f = FfsFile{
    name: "00112233445566778899aabbccddeeff";
    integrity_check: 0;
    file_type: 7;
    attributes: 0;
    size: 32;
    state: 0;
    large: false;
    header_size: 24;
    section_types: ty;
    section_sizes: sz;
    section_offsets: of;
    section_data_offsets: dof;
    section_data_sizes: dsz;
  };
  return f;
}

fn t21() -> TestResult {
  let data = small_fixture();
  let pr = ffs_parse(&data);
  if !pr.is_ok { return assert(false, "small fixture must parse"); }
  let f: FfsFile = pr.value;
  var ok = ffs_section_count(&f) == 2;
  if ffs_section_type(&f, -1) != -1 { ok = false; }
  if ffs_section_type(&f, 2) != -1 { ok = false; }
  if ffs_section_size(&f, 2) != -1 { ok = false; }
  if ffs_section_offset(&f, -3) != -1 { ok = false; }
  if ffs_section_data_offset(&f, 9) != -1 { ok = false; }
  if ffs_section_data_size(&f, 2) != -1 { ok = false; }
  if !err_bytes_is(ffs_section_raw(&data, &f, -1), "efi: index out of range") { ok = false; }
  if !err_bytes_is(ffs_section_raw(&data, &f, 2), "efi: index out of range") { ok = false; }
  if !err_bytes_is(ffs_section_data(&data, &f, 2), "efi: index out of range") { ok = false; }
  if ffs_section_version(&data, &f, 0) != -1 { ok = false; }
  if ffs_section_build_number(&data, &f, 0) != -1 { ok = false; }
  if !streq(ffs_section_ui_string(&data, &f, 0), "") { ok = false; }
  if !streq(ffs_section_guid(&data, &f, 0), "") { ok = false; }
  if ffs_section_guid_data_offset(&data, &f, 0) != -1 { ok = false; }
  if ffs_section_guid_attributes(&data, &f, 1) != -1 { ok = false; }
  if ffs_section_compression_length(&data, &f, 0) != -1 { ok = false; }
  let df = drift_file();
  if ffs_section_count(&df) != 0 { ok = false; }
  if ffs_section_type(&df, 0) != -1 { ok = false; }
  if ffs_section_size(&df, 0) != -1 { ok = false; }
  if !err_bytes_is(ffs_section_raw(&data, &df, 0), "efi: index out of range") { ok = false; }
  if !streq(ffs_section_ui_string(&data, &df, 0), "") { ok = false; }
  return assert(ok, "accessors out of range and drifted vectors");
}

fn t22() -> TestResult {
  let data = small_fixture();
  let pr = ffs_parse(&data);
  if !pr.is_ok { return assert(false, "small fixture must parse"); }
  let f: FfsFile = pr.value;
  let cut40 = prefix(data, 40);
  var ok = err_bytes_is(ffs_section_raw(&cut40, &f, 1), "efi: span out of bounds");
  let cut38 = prefix(data, 38);
  if !err_bytes_is(ffs_section_data(&cut38, &f, 1), "efi: span out of bounds") { ok = false; }
  let raw0 = ffs_section_raw(&cut40, &f, 0);
  if !raw0.is_ok { ok = false; } else {
    let r0: Vec[UInt8] = raw0.value;
    if !bytes_equal(r0, hb("08000019abcd0000")) { ok = false; }
  }
  let ui = ffs_section_ui_string(&cut40, &f, 1);
  if !streq(ui, "") { ok = false; }
  return assert(ok, "spans out of bounds are Err and read as empty");
}

fn main() -> Int {
  io.println("=== xiom.efi conformance tests ===");
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
    io.println("xiom.efi: all tests passed");
  } else {
    io.println("xiom.efi: tests failed");
  }
  return failed;
}
