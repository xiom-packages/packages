// XIOM -- xiom.gpt conformance tests (17 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Port task: prove the pure-XIOM xiom.gpt codec against the rules pinned in
// SPEC.md: protective-MBR detection, the LBA-1 header, the partition entry
// array, the flat parallel entry vectors, the UTF-16LE name policy, the raw
// CRC-32 fields with the optional verification helpers, the documented error
// catalog and build/parse round trips (including unused entries).
//
// Fixtures are assembled byte by byte in this file, so gpt_parse is
// exercised against bytes the test controls rather than only against
// gpt_build. Str comparisons go through xiom.string.compare's str_compare
// (BUG 17: `==` on Str values read from Vec elements lowers to a pointer
// comparison); every Vec element read is bound to an explicitly typed local
// and every `&` argument is a local binding (never a field or call result).

module gpt_tests
use xiom.io; use xiom.test;
use xiom.gpt;
use xiom.string;
use xiom.string.compare;
use xiom.encoding.hex;

// --------------------------------------------------
//  Byte helpers (independent of src/gpt.xi)
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

fn zeros(n: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < n {
    v.push(0 as UInt8);
    i = i + 1;
  }
  return v;
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

fn fill_zero(v: Vec[UInt8], start: Int, count: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < v.len() {
    if i >= start && i < start + count {
      out.push(0 as UInt8);
    } else {
      out.push(v[i]);
    }
    i = i + 1;
  }
  return out;
}

fn put_le32(v: Vec[UInt8], pos: Int, val: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < v.len() {
    if i == pos {
      out.push((val % 256) as UInt8);
    } elif i == pos + 1 {
      out.push(((val / 256) % 256) as UInt8);
    } elif i == pos + 2 {
      out.push(((val / 65536) % 256) as UInt8);
    } elif i == pos + 3 {
      out.push(((val / 16777216) % 256) as UInt8);
    } else {
      out.push(v[i]);
    }
    i = i + 1;
  }
  return out;
}

fn le32_at(v: Vec[UInt8], pos: Int) -> Int {
  let b0: Int = (v[pos] as Int) & 0xFF;
  let b1: Int = (v[pos + 1] as Int) & 0xFF;
  let b2: Int = (v[pos + 2] as Int) & 0xFF;
  let b3: Int = (v[pos + 3] as Int) & 0xFF;
  return b0 + b1 * 256 + b2 * 65536 + b3 * 16777216;
}

fn all_zero(v: Vec[UInt8], start: Int, count: Int) -> Bool {
  var i = 0;
  while i < count {
    let b: Int = (v[start + i] as Int) & 0xFF;
    if b != 0 { return false; }
    i = i + 1;
  }
  return true;
}

fn push_le32(v: &mut Vec[UInt8], val: Int) {
  v.push((val % 256) as UInt8);
  v.push(((val / 256) % 256) as UInt8);
  v.push(((val / 65536) % 256) as UInt8);
  v.push(((val / 16777216) % 256) as UInt8);
}

fn push_le64(v: &mut Vec[UInt8], val: Int) {
  v.push((val % 256) as UInt8);
  v.push(((val / 256) % 256) as UInt8);
  v.push(((val / 65536) % 256) as UInt8);
  v.push(((val / 16777216) % 256) as UInt8);
  v.push(((val / 4294967296) % 256) as UInt8);
  v.push(((val / 1099511627776) % 256) as UInt8);
  v.push(((val / 281474976710656) % 256) as UInt8);
  v.push(((val / 72057594037927936) % 256) as UInt8);
}

// Append the 16 raw bytes encoded by a 32-character hex string via the
// stdlib decoder (empty on malformed input).
fn guid_push(v: &mut Vec[UInt8], hexstr: Str) {
  let bytes = hb(hexstr);
  var i = 0;
  while i < bytes.len() {
    v.push(bytes[i]);
    i = i + 1;
  }
}

// --------------------------------------------------
//  Byte-level fixtures
// --------------------------------------------------

// The protective MBR as the codec documents it (signature 0x55AA, one 0xEE
// entry covering the disk from LBA 1).
fn push_mbr(v: &mut Vec[UInt8], total_sectors: Int) {
  var i = 0;
  while i < 446 {
    v.push(0 as UInt8);
    i = i + 1;
  }
  v.push(0 as UInt8);
  v.push(0 as UInt8);
  v.push(2 as UInt8);
  v.push(0 as UInt8);
  v.push(238 as UInt8);
  v.push(255 as UInt8);
  v.push(255 as UInt8);
  v.push(255 as UInt8);
  push_le32(v, 1);
  push_le32(v, total_sectors - 1);
  i = 0;
  while i < 48 {
    v.push(0 as UInt8);
    i = i + 1;
  }
  v.push(85 as UInt8);
  v.push(170 as UInt8);
}

// The 92-byte GPT header, zero-padded to the end of its 512-byte sector.
fn push_header(v: &mut Vec[UInt8], revision: Int, hsize: Int, hcrc: Int, reserved: Int, current: Int, backup: Int, first: Int, last: Int, disk_hex: Str, elba: Int, count: Int, esize: Int, ecrc: Int) {
  var sig = bytes_of("EFI PART");
  var i = 0;
  while i < sig.len() {
    v.push(sig[i]);
    i = i + 1;
  }
  push_le32(v, revision);
  push_le32(v, hsize);
  push_le32(v, hcrc);
  push_le32(v, reserved);
  push_le64(v, current);
  push_le64(v, backup);
  push_le64(v, first);
  push_le64(v, last);
  guid_push(v, disk_hex);
  push_le64(v, elba);
  push_le32(v, count);
  push_le32(v, esize);
  push_le32(v, ecrc);
  while v.len() < 1024 {
    v.push(0 as UInt8);
  }
}

// One partition entry of `size` bytes from raw UTF-16LE code units, then
// zero-padded.
fn entry_units(ty: Str, uniq: Str, first: Int, last: Int, attrs: Int, units: Vec[Int], size: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  guid_push(&mut v, ty);
  guid_push(&mut v, uniq);
  push_le64(&mut v, first);
  push_le64(&mut v, last);
  push_le64(&mut v, attrs);
  var i = 0;
  while i < units.len() {
    let u: Int = units[i];
    v.push((u % 256) as UInt8);
    v.push(((u / 256) % 256) as UInt8);
    i = i + 1;
  }
  while v.len() < size {
    v.push(0 as UInt8);
  }
  return v;
}

// One partition entry whose name is the ASCII bytes of `name` followed by a
// 0x0000 terminator.
fn entry_named(ty: Str, uniq: Str, first: Int, last: Int, attrs: Int, name: Str, size: Int) -> Vec[UInt8] {
  var units = Vec[Int].new();
  var i = 0;
  while i < name.len() {
    units.push((string.byte_at(name, i) as Int) & 0xFF);
    i = i + 1;
  }
  units.push(0);
  return entry_units(ty, uniq, first, last, attrs, units, size);
}

fn entry_unused(size: Int) -> Vec[UInt8] {
  var units = Vec[Int].new();
  return entry_units("00000000000000000000000000000000", "00000000000000000000000000000000", 0, 0, 0, units, size);
}

// Patch the entry-array CRC (at header offset 88) and then the header CRC
// (at header offset 16), in that order.
fn seal(v: Vec[UInt8], hsize: Int, elba: Int, count: Int, esize: Int) -> Vec[UInt8] {
  let ecrc = gpt_crc32_range(&v, elba * 512, count * esize);
  var out = put_le32(v, 512 + 88, ecrc);
  let hcrc = gpt_crc32_range(&out, 512, hsize);
  out = put_le32(out, 512 + 16, hcrc);
  return out;
}

// Four 128-byte entry slots at LBA 2: "EFI System" used, one all-zero unused
// entry, one entry whose name carries a non-ASCII code unit, one unused.
fn fixture() -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  push_mbr(&mut v, 2048);
  push_header(&mut v, 65536, 92, 0, 0, 1, 2047, 34, 2014, "0123456789abcdef0123456789abcdef", 2, 4, 128, 0);
  v = concat(v, entry_named("00112233445566778899aabbccddeeff", "fedcba98765432100123456789abcdef", 2048, 4095, 5, "EFI System", 128));
  v = concat(v, entry_unused(128));
  var units = Vec[Int].new();
  units.push(65);
  units.push(66);
  units.push(233);
  units.push(67);
  units.push(0);
  v = concat(v, entry_units("112233445566778899aabbccddeeff00", "00112233445566778899aabbccddeeff", 4096, 8191, 0, units, 128));
  v = concat(v, entry_unused(128));
  return seal(v, 92, 2, 4, 128);
}

// One entry slot at LBA 2; the caller controls the code units, LBAs,
// attributes and the header backup LBA.
fn custom_fixture(units: Vec[Int], size: Int, first: Int, last: Int, attrs: Int, backup: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  push_mbr(&mut v, 4096);
  push_header(&mut v, 65536, 92, 0, 0, 1, backup, 3, 4062, "00112233445566778899aabbccddeeff", 2, 1, size, 0);
  v = concat(v, entry_units("aabbccddeeff00112233445566778899", "99887766554433221100ffeeddccbbaa", first, last, attrs, units, size));
  return seal(v, 92, 2, 1, size);
}

// Two entries, but the array starts at LBA 3 (LBA 2 is padding).
fn offset_entries_fixture() -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  push_mbr(&mut v, 4096);
  push_header(&mut v, 65536, 92, 0, 0, 1, 4095, 4, 4062, "0123456789abcdef0123456789abcdef", 3, 2, 128, 0);
  var i = 0;
  while i < 512 {
    v.push(0 as UInt8);
    i = i + 1;
  }
  v = concat(v, entry_named("00112233445566778899aabbccddeeff", "fedcba98765432100123456789abcdef", 20, 30, 0, "boot", 128));
  v = concat(v, entry_unused(128));
  return seal(v, 92, 3, 2, 128);
}

// --------------------------------------------------
//  GptTable fixtures
// --------------------------------------------------

fn good_guid() -> Str {
  return "0123456789abcdef0123456789abcdef";
}

fn no_strs() -> Vec[Str] {
  return Vec[Str].new();
}

fn no_ints() -> Vec[Int] {
  return Vec[Int].new();
}

fn one_strs(a: Str) -> Vec[Str] {
  var v = Vec[Str].new();
  v.push(a);
  return v;
}

fn one_ints(a: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  return v;
}

fn str2(a: Str, b: Str) -> Vec[Str] {
  var v = Vec[Str].new();
  v.push(a);
  v.push(b);
  return v;
}

fn int2(a: Int, b: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  v.push(b);
  return v;
}

fn table_of(rev: Int, count: Int, size: Int, guid: Str, tys: Vec[Str], ugs: Vec[Str], fls: Vec[Int], lls: Vec[Int], ats: Vec[Int], nms: Vec[Str]) -> GptTable {
  let t = GptTable{
    revision: rev;
    header_size: 92;
    header_crc: 0;
    reserved: 0;
    current_lba: 1;
    backup_lba: 0;
    first_usable_lba: 0;
    last_usable_lba: 0;
    disk_guid: guid;
    entries_lba: 2;
    entry_count: count;
    entry_size: size;
    entries_crc: 0;
    type_guids: tys;
    unique_guids: ugs;
    first_lbas: fls;
    last_lbas: lls;
    attributes: ats;
    names: nms;
  };
  return t;
}

fn table_empty(rev: Int, count: Int, size: Int, guid: Str) -> GptTable {
  return table_of(rev, count, size, guid, no_strs(), no_strs(), no_ints(), no_ints(), no_ints(), no_strs());
}

// Declared `count` slots, two provided entries (the builder zero-fills the
// rest).
fn two_entry_table(count: Int, size: Int) -> GptTable {
  return table_of(65536, count, size, good_guid(),
    str2("00112233445566778899aabbccddeeff", "aabbccddeeff00112233445566778899"),
    str2("fedcba98765432100123456789abcdef", "0123456789abcdeffedcba9876543210"),
    int2(2048, 8192),
    int2(4095, 12287),
    int2(5, 0),
    str2("EFI System", "data"));
}

// Drifted parallel vectors (used by the drift and build-error checks).
fn mismatch_table() -> GptTable {
  return table_of(65536, 4, 128, good_guid(),
    str2("00112233445566778899aabbccddeeff", "aabbccddeeff00112233445566778899"),
    one_strs("fedcba98765432100123456789abcdef"),
    int2(3, 5),
    int2(100, 200),
    int2(0, 0),
    str2("a", "b"));
}

fn count_too_small_table() -> GptTable {
  return table_of(65536, 1, 128, good_guid(),
    str2("00112233445566778899aabbccddeeff", "aabbccddeeff00112233445566778899"),
    str2("fedcba98765432100123456789abcdef", "0123456789abcdeffedcba9876543210"),
    int2(3, 5),
    int2(100, 200),
    int2(0, 0),
    str2("a", "b"));
}

fn bad_name_table() -> GptTable {
  return table_of(65536, 1, 128, good_guid(),
    one_strs("00112233445566778899aabbccddeeff"),
    one_strs("fedcba98765432100123456789abcdef"),
    one_ints(3),
    one_ints(100),
    one_ints(0),
    one_strs("AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"));
}

fn bad_lba_table() -> GptTable {
  return table_of(65536, 1, 128, good_guid(),
    one_strs("00112233445566778899aabbccddeeff"),
    one_strs("fedcba98765432100123456789abcdef"),
    one_ints(100),
    one_ints(50),
    one_ints(0),
    one_strs("a"));
}

fn neg_lba_table() -> GptTable {
  return table_of(65536, 1, 128, good_guid(),
    one_strs("00112233445566778899aabbccddeeff"),
    one_strs("fedcba98765432100123456789abcdef"),
    one_ints(-1),
    one_ints(50),
    one_ints(0),
    one_strs("a"));
}

fn bad_entry_guid_table() -> GptTable {
  return table_of(65536, 1, 128, good_guid(),
    one_strs("zz112233445566778899aabbccddeeff"),
    one_strs("fedcba98765432100123456789abcdef"),
    one_ints(3),
    one_ints(100),
    one_ints(0),
    one_strs("a"));
}

// --------------------------------------------------
//  Result helpers and derived fixtures
// --------------------------------------------------

fn err_table_is(r: Result[GptTable, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return streq(r.error, want);
}

fn err_bytes_is(r: Result[Vec[UInt8], Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return streq(r.error, want);
}

// The decoded name of the single custom-fixture entry.
fn name_of(units: Vec[Int]) -> Str {
  let data = custom_fixture(units, 128, 3, 100, 0, 4095);
  let pr = gpt_parse(&data);
  if !pr.is_ok { return "<parse>"; }
  let t = pr.value;
  return gpt_entry_name(&t, 0);
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  let data = fixture();
  var ok = gpt_has_protective_mbr(&data);
  let bad_sig = set_byte(data, 510, 0);
  if gpt_has_protective_mbr(&bad_sig) { ok = false; }
  let bad_type = set_byte(data, 450, 131);
  if gpt_has_protective_mbr(&bad_type) { ok = false; }
  let bad_extra = set_byte(data, 462, 1);
  if gpt_has_protective_mbr(&bad_extra) { ok = false; }
  let short = prefix(data, 511);
  if gpt_has_protective_mbr(&short) { ok = false; }
  return assert(ok, "protective MBR detection follows the documented shape");
}

fn t2() -> TestResult {
  let data = fixture();
  let pr = gpt_parse(&data);
  if !pr.is_ok { return assert(false, "fixture must parse"); }
  let t = pr.value;
  var ok = gpt_revision(&t) == 65536;
  if gpt_header_size(&t) != 92 { ok = false; }
  if gpt_reserved(&t) != 0 { ok = false; }
  if gpt_current_lba(&t) != 1 { ok = false; }
  if gpt_backup_lba(&t) != 2047 { ok = false; }
  if gpt_first_usable_lba(&t) != 34 { ok = false; }
  if gpt_last_usable_lba(&t) != 2014 { ok = false; }
  if !streq(gpt_disk_guid(&t), "0123456789abcdef0123456789abcdef") { ok = false; }
  let raw = hb("0123456789abcdef0123456789abcdef");
  if !streq(hex.hex_encode(&raw), gpt_disk_guid(&t)) { ok = false; }
  if gpt_entries_lba(&t) != 2 { ok = false; }
  if gpt_entry_size(&t) != 128 { ok = false; }
  if gpt_entry_count(&t) != 4 { ok = false; }
  let hzero = fill_zero(data, 512 + 16, 4);
  if gpt_header_crc(&t) != gpt_crc32_range(&hzero, 512, 92) { ok = false; }
  if gpt_entries_crc(&t) != gpt_crc32_range(&data, 1024, 512) { ok = false; }
  return assert(ok, "header scalars, GUID text and stored CRCs");
}

fn t3() -> TestResult {
  let data = fixture();
  let pr = gpt_parse(&data);
  if !pr.is_ok { return assert(false, "fixture must parse"); }
  let t = pr.value;
  var ok = gpt_entry_count(&t) == 4;
  if !streq(gpt_type_guid(&t, 0), "00112233445566778899aabbccddeeff") { ok = false; }
  if !streq(gpt_unique_guid(&t, 0), "fedcba98765432100123456789abcdef") { ok = false; }
  if gpt_entry_first_lba(&t, 0) != 2048 { ok = false; }
  if gpt_entry_last_lba(&t, 0) != 4095 { ok = false; }
  if gpt_entry_attributes(&t, 0) != 5 { ok = false; }
  if !streq(gpt_entry_name(&t, 0), "EFI System") { ok = false; }
  if !gpt_entry_in_use(&t, 0) { ok = false; }
  if gpt_entry_in_use(&t, 1) { ok = false; }
  if !streq(gpt_type_guid(&t, 1), "00000000000000000000000000000000") { ok = false; }
  if !streq(gpt_entry_name(&t, 1), "") { ok = false; }
  if !streq(gpt_type_guid(&t, 2), "112233445566778899aabbccddeeff00") { ok = false; }
  if gpt_entry_first_lba(&t, 2) != 4096 { ok = false; }
  if !gpt_entry_in_use(&t, 2) { ok = false; }
  if gpt_entry_in_use(&t, 3) { ok = false; }
  return assert(ok, "entry accessors, unused slots and the in-use predicate");
}

fn t4() -> TestResult {
  let data = fixture();
  let pr = gpt_parse(&data);
  if !pr.is_ok { return assert(false, "fixture must parse"); }
  let t = pr.value;
  var ok = streq(gpt_entry_name(&t, 2), "AB?C");
  let u2 = one_ints(20013);
  u2.push(0);
  if !streq(name_of(u2), "?") { ok = false; }
  let u3 = one_ints(127);
  u3.push(0);
  if !streq(name_of(u3), "?") { ok = false; }
  let u4 = one_ints(31);
  u4.push(0);
  if !streq(name_of(u4), "?") { ok = false; }
  var u5 = Vec[Int].new();
  u5.push(32);
  u5.push(126);
  u5.push(0);
  if !streq(name_of(u5), " ~") { ok = false; }
  var u6 = Vec[Int].new();
  u6.push(88);
  u6.push(89);
  u6.push(0);
  u6.push(90);
  u6.push(91);
  if !streq(name_of(u6), "XY") { ok = false; }
  var u7 = Vec[Int].new();
  var k = 0;
  while k < 36 {
    u7.push(65);
    k = k + 1;
  }
  let full = name_of(u7);
  if full.len() != 36 { ok = false; }
  return assert(ok, "UTF-16LE names: NUL stop, ASCII pass-through, '?' replacement");
}

fn t5() -> TestResult {
  let d = bytes_of("123456789");
  var ok = gpt_crc32(&d) == 3421780262;
  if gpt_crc32_range(&d, 0, 9) != 3421780262 { ok = false; }
  let e = Vec[UInt8].new();
  if gpt_crc32(&e) != 0 { ok = false; }
  if gpt_crc32_range(&d, 9, 0) != 0 { ok = false; }
  if gpt_crc32_range(&d, 0, 10) != -1 { ok = false; }
  if gpt_crc32_range(&d, 10, 0) != -1 { ok = false; }
  if gpt_crc32_range(&d, 9, 1) != -1 { ok = false; }
  if gpt_crc32_range(&d, -1, 1) != -1 { ok = false; }
  if gpt_crc32_range(&d, 0, -1) != -1 { ok = false; }
  return assert(ok, "CRC-32 known answers and range guards");
}

fn t6() -> TestResult {
  let data = fixture();
  let pr = gpt_parse(&data);
  if !pr.is_ok { return assert(false, "fixture must parse"); }
  let t = pr.value;
  var ok = gpt_header_crc_ok(&data, &t);
  if !gpt_entries_crc_ok(&data, &t) { ok = false; }
  let hbad = set_byte(data, 532, 7);
  let hp = gpt_parse(&hbad);
  if !hp.is_ok { return assert(false, "reserved byte change must still parse"); }
  let ht = hp.value;
  if gpt_header_crc_ok(&hbad, &ht) { ok = false; }
  if !gpt_entries_crc_ok(&hbad, &ht) { ok = false; }
  if gpt_reserved(&ht) != 7 { ok = false; }
  let ebad = set_byte(data, 1024, 255);
  let ep = gpt_parse(&ebad);
  if !ep.is_ok { return assert(false, "entry byte change must still parse"); }
  let et = ep.value;
  if !gpt_header_crc_ok(&ebad, &et) { ok = false; }
  if gpt_entries_crc_ok(&ebad, &et) { ok = false; }
  if !streq(gpt_type_guid(&et, 0), "ff112233445566778899aabbccddeeff") { ok = false; }
  return assert(ok, "CRC helpers detect corruption; parse never rejects a mismatch");
}

fn t7() -> TestResult {
  let short = prefix(fixture(), 1023);
  var ok = err_table_is(gpt_parse(&short), "gpt: truncated header");
  let bad_sig = set_byte(fixture(), 512, 88);
  if !err_table_is(gpt_parse(&bad_sig), "gpt: bad signature") { ok = false; }
  let h91 = put_le32(fixture(), 524, 91);
  if !err_table_is(gpt_parse(&h91), "gpt: bad header size") { ok = false; }
  let h513 = put_le32(fixture(), 524, 513);
  if !err_table_is(gpt_parse(&h513), "gpt: bad header size") { ok = false; }
  let cur0 = fill_zero(fixture(), 536, 8);
  if !err_table_is(gpt_parse(&cur0), "gpt: bad LBA") { ok = false; }
  let ent0 = fill_zero(fixture(), 584, 8);
  if !err_table_is(gpt_parse(&ent0), "gpt: bad LBA") { ok = false; }
  let fu0 = fill_zero(fixture(), 552, 8);
  if !err_table_is(gpt_parse(&fu0), "gpt: bad LBA") { ok = false; }
  let last0 = fill_zero(fixture(), 560, 8);
  if !err_table_is(gpt_parse(&last0), "gpt: bad LBA") { ok = false; }
  let range = put_le32(put_le32(fill_zero(fixture(), 552, 8), 552, 136), 553, 19);
  if !err_table_is(gpt_parse(&range), "gpt: bad usable range") { ok = false; }
  return assert(ok, "parse errors: truncation, signature, header size, LBAs");
}

fn t8() -> TestResult {
  let es127 = put_le32(fixture(), 596, 127);
  var ok = err_table_is(gpt_parse(&es127), "gpt: bad entry size");
  let es132 = put_le32(fixture(), 596, 132);
  if !err_table_is(gpt_parse(&es132), "gpt: bad entry size") { ok = false; }
  let c0 = put_le32(fixture(), 592, 0);
  if !err_table_is(gpt_parse(&c0), "gpt: bad entry count") { ok = false; }
  let c4097 = put_le32(fixture(), 592, 4097);
  if !err_table_is(gpt_parse(&c4097), "gpt: bad entry count") { ok = false; }
  let cut = prefix(fixture(), 1408);
  if !err_table_is(gpt_parse(&cut), "gpt: truncated entries") { ok = false; }
  let far = put_le32(fill_zero(fixture(), 584, 8), 588, 1);
  if !err_table_is(gpt_parse(&far), "gpt: truncated entries") { ok = false; }
  let neg = set_byte(fixture(), 1063, 128);
  if !err_table_is(gpt_parse(&neg), "gpt: bad LBA") { ok = false; }
  return assert(ok, "parse errors: entry size, count cap, array bounds, negative LBA");
}

fn t9() -> TestResult {
  let t = two_entry_table(4, 128);
  let b = gpt_build(&t, 2048);
  if !b.is_ok { return assert(false, "build must succeed"); }
  let data: Vec[UInt8] = b.value;
  var ok = data.len() == 1536;
  let pr = gpt_parse(&data);
  if !pr.is_ok { return assert(false, "built GPT must parse"); }
  let pt = pr.value;
  if gpt_entry_count(&pt) != 4 { ok = false; }
  if gpt_current_lba(&pt) != 1 { ok = false; }
  if gpt_backup_lba(&pt) != 2047 { ok = false; }
  if gpt_first_usable_lba(&pt) != 3 { ok = false; }
  if gpt_last_usable_lba(&pt) != 2045 { ok = false; }
  if gpt_entries_lba(&pt) != 2 { ok = false; }
  if !gpt_entry_in_use(&pt, 0) { ok = false; }
  if !gpt_entry_in_use(&pt, 1) { ok = false; }
  if gpt_entry_in_use(&pt, 2) { ok = false; }
  if gpt_entry_in_use(&pt, 3) { ok = false; }
  if !streq(gpt_entry_name(&pt, 0), "EFI System") { ok = false; }
  if !streq(gpt_entry_name(&pt, 1), "data") { ok = false; }
  if !streq(gpt_entry_name(&pt, 3), "") { ok = false; }
  if gpt_entry_first_lba(&pt, 1) != 8192 { ok = false; }
  if !gpt_header_crc_ok(&data, &pt) { ok = false; }
  if !gpt_entries_crc_ok(&data, &pt) { ok = false; }
  if !gpt_has_protective_mbr(&data) { ok = false; }
  let b2 = gpt_build(&pt, 2048);
  if !b2.is_ok { ok = false; }
  else {
    let data2: Vec[UInt8] = b2.value;
    if !bytes_equal(data2, data) { ok = false; }
  }
  return assert(ok, "builder geometry, unused slots and build->parse->build");
}

fn t10() -> TestResult {
  let t = two_entry_table(4, 128);
  let b = gpt_build(&t, 2048);
  if !b.is_ok { return assert(false, "build must succeed"); }
  let data: Vec[UInt8] = b.value;
  var ok = data.len() == 1536;
  if (data[446] as Int) != 0 { ok = false; }
  if (data[450] as Int) != 238 { ok = false; }
  if (data[451] as Int) != 255 { ok = false; }
  if (data[454] as Int) != 1 { ok = false; }
  if (data[455] as Int) != 0 { ok = false; }
  if (data[458] as Int) != 255 { ok = false; }
  if (data[459] as Int) != 7 { ok = false; }
  if (data[460] as Int) != 0 { ok = false; }
  if (data[510] as Int) != 85 { ok = false; }
  if (data[511] as Int) != 170 { ok = false; }
  if (data[512] as Int) != 69 { ok = false; }
  if (data[513] as Int) != 70 { ok = false; }
  if (data[514] as Int) != 73 { ok = false; }
  if (data[515] as Int) != 32 { ok = false; }
  if (data[516] as Int) != 80 { ok = false; }
  if (data[517] as Int) != 65 { ok = false; }
  if (data[518] as Int) != 82 { ok = false; }
  if (data[519] as Int) != 84 { ok = false; }
  if le32_at(data, 520) != 65536 { ok = false; }
  if le32_at(data, 524) != 92 { ok = false; }
  let hzero = fill_zero(data, 512 + 16, 4);
  if le32_at(data, 528) != gpt_crc32_range(&hzero, 512, 92) { ok = false; }
  if le32_at(data, 532) != 0 { ok = false; }
  if (data[536] as Int) != 1 { ok = false; }
  if le32_at(data, 584) != 2 { ok = false; }
  if !all_zero(data, 588, 4) { ok = false; }
  if le32_at(data, 592) != 4 { ok = false; }
  if le32_at(data, 596) != 128 { ok = false; }
  if le32_at(data, 600) != gpt_crc32_range(&data, 1024, 512) { ok = false; }
  let guid_raw = hb("0123456789abcdef0123456789abcdef");
  var gi = 0;
  while gi < 16 {
    if data[568 + gi] != guid_raw[gi] { ok = false; }
    gi = gi + 1;
  }
  let g1 = hb("00112233445566778899aabbccddeeff");
  var k = 0;
  while k < 16 {
    if data[1024 + k] != g1[k] { ok = false; }
    k = k + 1;
  }
  if (data[1080] as Int) != 69 { ok = false; }
  if (data[1081] as Int) != 0 { ok = false; }
  if (data[1082] as Int) != 70 { ok = false; }
  if (data[1084] as Int) != 73 { ok = false; }
  if (data[1088] as Int) != 83 { ok = false; }
  if (data[1089] as Int) != 0 { ok = false; }
  if !all_zero(data, 1024 + 256, 128) { ok = false; }
  return assert(ok, "builder pins MBR, 92-byte header, entry bytes and zero fill");
}

fn t11() -> TestResult {
  let bad_rev = table_empty(-1, 4, 128, good_guid());
  var ok = err_bytes_is(gpt_build(&bad_rev, 2048), "gpt: bad revision");
  let g1 = table_empty(65536, 4, 128, "0123");
  if !err_bytes_is(gpt_build(&g1, 2048), "gpt: bad guid") { ok = false; }
  let g2 = table_empty(65536, 4, 128, "0123456789abcdef0123456789abcdeZ");
  if !err_bytes_is(gpt_build(&g2, 2048), "gpt: bad guid") { ok = false; }
  let e1 = table_empty(65536, 4, 127, good_guid());
  if !err_bytes_is(gpt_build(&e1, 2048), "gpt: bad entry size") { ok = false; }
  let e2 = table_empty(65536, 4, 132, good_guid());
  if !err_bytes_is(gpt_build(&e2, 2048), "gpt: bad entry size") { ok = false; }
  let c0 = table_empty(65536, 0, 128, good_guid());
  if !err_bytes_is(gpt_build(&c0, 2048), "gpt: bad entry count") { ok = false; }
  let c9 = table_empty(65536, 4097, 128, good_guid());
  if !err_bytes_is(gpt_build(&c9, 2048), "gpt: bad entry count") { ok = false; }
  let big = table_empty(65536, 4096, 128, good_guid());
  if !err_bytes_is(gpt_build(&big, 1024), "gpt: disk too small") { ok = false; }
  let z = table_empty(65536, 4, 128, good_guid());
  if !err_bytes_is(gpt_build(&z, 0), "gpt: disk too small") { ok = false; }
  return assert(ok, "builder errors: revision, GUID, entry size, entry count, disk");
}

fn t12() -> TestResult {
  let mm = mismatch_table();
  var ok = err_bytes_is(gpt_build(&mm, 2048), "gpt: entry vector mismatch");
  let cs = count_too_small_table();
  if !err_bytes_is(gpt_build(&cs, 2048), "gpt: entry count too small") { ok = false; }
  let bn = bad_name_table();
  if !err_bytes_is(gpt_build(&bn, 2048), "gpt: bad entry name") { ok = false; }
  let bl = bad_lba_table();
  if !err_bytes_is(gpt_build(&bl, 2048), "gpt: bad entry LBA") { ok = false; }
  let nl = neg_lba_table();
  if !err_bytes_is(gpt_build(&nl, 2048), "gpt: bad entry LBA") { ok = false; }
  let bg = bad_entry_guid_table();
  if !err_bytes_is(gpt_build(&bg, 2048), "gpt: bad guid") { ok = false; }
  return assert(ok, "builder errors: vectors, names, entry LBAs, entry GUIDs");
}

fn t13() -> TestResult {
  let t = two_entry_table(4, 128);
  var ok = gpt_entry_count(&t) == 2;
  if !streq(gpt_type_guid(&t, -1), "") { ok = false; }
  if !streq(gpt_type_guid(&t, 2), "") { ok = false; }
  if !streq(gpt_unique_guid(&t, 5), "") { ok = false; }
  if gpt_entry_first_lba(&t, 2) != -1 { ok = false; }
  if gpt_entry_last_lba(&t, -1) != -1 { ok = false; }
  if gpt_entry_attributes(&t, 2) != 0 { ok = false; }
  if !streq(gpt_entry_name(&t, 2), "") { ok = false; }
  if gpt_entry_in_use(&t, 2) { ok = false; }
  if gpt_entry_in_use(&t, -1) { ok = false; }
  if !streq(gpt_type_guid(&t, 0), "00112233445566778899aabbccddeeff") { ok = false; }
  if gpt_entry_first_lba(&t, 1) != 8192 { ok = false; }
  return assert(ok, "accessors report empty/-1/0/false out of range");
}

fn t14() -> TestResult {
  let t = mismatch_table();
  var ok = gpt_entry_count(&t) == 1;
  if !streq(gpt_type_guid(&t, 1), "aabbccddeeff00112233445566778899") { ok = false; }
  if !streq(gpt_unique_guid(&t, 1), "") { ok = false; }
  if gpt_entry_first_lba(&t, 1) != 5 { ok = false; }
  if gpt_entry_last_lba(&t, 1) != 200 { ok = false; }
  if gpt_entry_attributes(&t, 1) != 0 { ok = false; }
  if !streq(gpt_entry_name(&t, 1), "b") { ok = false; }
  return assert(ok, "drifted parallel vectors guard each accessor");
}

fn t15() -> TestResult {
  let data = offset_entries_fixture();
  let pr = gpt_parse(&data);
  if !pr.is_ok { return assert(false, "offset fixture must parse"); }
  let t = pr.value;
  var ok = gpt_entries_lba(&t) == 3;
  if gpt_entry_count(&t) != 2 { ok = false; }
  if !streq(gpt_entry_name(&t, 0), "boot") { ok = false; }
  if gpt_entry_first_lba(&t, 0) != 20 { ok = false; }
  if gpt_entry_in_use(&t, 1) { ok = false; }
  if !gpt_header_crc_ok(&data, &t) { ok = false; }
  if !gpt_entries_crc_ok(&data, &t) { ok = false; }
  return assert(ok, "entry array is located through PartitionEntryLBA");
}

fn t16() -> TestResult {
  let t = two_entry_table(128, 128);
  let b = gpt_build(&t, 2048);
  if !b.is_ok { return assert(false, "128-slot build must succeed"); }
  let data: Vec[UInt8] = b.value;
  var ok = data.len() == 17408;
  let pr = gpt_parse(&data);
  if !pr.is_ok { return assert(false, "128-slot GPT must parse"); }
  let pt = pr.value;
  if gpt_entry_count(&pt) != 128 { ok = false; }
  if gpt_first_usable_lba(&pt) != 34 { ok = false; }
  if gpt_last_usable_lba(&pt) != 2014 { ok = false; }
  if gpt_backup_lba(&pt) != 2047 { ok = false; }
  if !gpt_entry_in_use(&pt, 0) { ok = false; }
  if !gpt_entry_in_use(&pt, 1) { ok = false; }
  if gpt_entry_in_use(&pt, 2) { ok = false; }
  if gpt_entry_in_use(&pt, 127) { ok = false; }
  if !all_zero(data, 1280, 16128) { ok = false; }
  let b2 = gpt_build(&pt, 2048);
  if !b2.is_ok { ok = false; }
  else {
    let data2: Vec[UInt8] = b2.value;
    if !bytes_equal(data2, data) { ok = false; }
  }
  return assert(ok, "canonical 128-slot layout, geometry and rebuild");
}

fn t17() -> TestResult {
  var units = Vec[Int].new();
  units.push(65);
  units.push(0);
  let data = custom_fixture(units, 128, 4294967296, 8589934592, 4611686018427387904, 4294967296);
  let pr = gpt_parse(&data);
  if !pr.is_ok { return assert(false, "64-bit fixture must parse"); }
  let t = pr.value;
  var ok = gpt_entry_first_lba(&t, 0) == 4294967296;
  if gpt_entry_last_lba(&t, 0) != 8589934592 { ok = false; }
  if gpt_entry_attributes(&t, 0) != 4611686018427387904 { ok = false; }
  if gpt_backup_lba(&t) != 4294967296 { ok = false; }
  if !streq(gpt_entry_name(&t, 0), "A") { ok = false; }
  let tt = two_entry_table(4, 128);
  let bb = gpt_build(&tt, 4294967297);
  if !bb.is_ok { ok = false; }
  else {
    let bd: Vec[UInt8] = bb.value;
    let bp = gpt_parse(&bd);
    if !bp.is_ok { ok = false; }
    else {
      let bt = bp.value;
      if gpt_backup_lba(&bt) != 4294967296 { ok = false; }
    }
  }
  return assert(ok, "64-bit LBA and attribute fields round-trip");
}

fn main() -> Int {
  io.println("=== xiom.gpt conformance tests ===");
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
  if failed == 0 {
    io.println("xiom.gpt: all tests passed");
  } else {
    io.println("xiom.gpt: tests failed");
  }
  return failed;
}
