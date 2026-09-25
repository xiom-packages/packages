// XIOM -- xiom.woff conformance tests (24 checks)
// Port task: prove the pure-XIOM xiom.woff header/table-directory codec
// against the documented WOFF 1.0 container layout and error catalog.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Covers: canonical build bytes and padding; build -> parse round-trips;
// signature/length/reserved/directory validation; tag range; the
// compLength <= origLength policy with the compressed predicate and raw
// zlib bytes; totalSfntSize arithmetic; overlapping spans; zero-length
// tables; metadata and private block spans (valid, unaligned, out of
// bounds, overlapping); accessor and copier guards; tag_of; and the
// builder's error catalog.
//
// Str values are never compared with `==` (BUG 17 discipline: `==` on a
// Str read from a Vec lowers to a pointer comparison); error messages go
// through compare.str_compare.

module woff_tests
use xiom.io; use xiom.test;
use xiom.woff;
use xiom.string;
use xiom.string.compare;
use xiom.encoding.hex;

// --------------------------------------------------
//  Test helpers
// --------------------------------------------------

// Expected bytes for a hex string ("" on malformed input; the test then
// fails on the byte comparison).
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
    if a[i] != b[i] {
      return false;
    }
    i = i + 1;
  }
  return true;
}

fn str_eq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn err_woff_is(r: Result[Woff, Str], want: Str) -> Bool {
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

// Unsigned big-endian readers for pinning fixture/emit bytes.
fn rd8(v: &Vec[UInt8], off: Int) -> Int {
  return (v[off] as Int) & 0xFF;
}

fn rd16(v: &Vec[UInt8], off: Int) -> Int {
  return rd8(v, off) * 256 + rd8(v, off + 1);
}

fn rd32(v: &Vec[UInt8], off: Int) -> Int {
  return rd8(v, off) * 16777216 + rd8(v, off + 1) * 65536 + rd8(v, off + 2) * 256 + rd8(v, off + 3);
}

// Big-endian appenders for building fixtures.
fn put_u16(out: &mut Vec[UInt8], v: Int) {
  out.push(((v / 256) % 256) as UInt8);
  out.push((v % 256) as UInt8);
}

fn put_u32(out: &mut Vec[UInt8], v: Int) {
  out.push(((v / 16777216) % 256) as UInt8);
  out.push(((v / 65536) % 256) as UInt8);
  out.push(((v / 256) % 256) as UInt8);
  out.push((v % 256) as UInt8);
}

fn put_bytes(out: &mut Vec[UInt8], v: &Vec[UInt8]) {
  var i = 0;
  while i < v.len() {
    out.push(v[i]);
    i = i + 1;
  }
}

// In-place field patches for building malformed variants of a fixture.
fn patch_byte(buf: &mut Vec[UInt8], off: Int, v: Int) {
  buf[off] = (v % 256) as UInt8;
}

fn patch_u16(buf: &mut Vec[UInt8], off: Int, v: Int) {
  buf[off] = ((v / 256) % 256) as UInt8;
  buf[off + 1] = (v % 256) as UInt8;
}

fn patch_u32(buf: &mut Vec[UInt8], off: Int, v: Int) {
  buf[off] = ((v / 16777216) % 256) as UInt8;
  buf[off + 1] = ((v / 65536) % 256) as UInt8;
  buf[off + 2] = ((v / 256) % 256) as UInt8;
  buf[off + 3] = (v % 256) as UInt8;
}

fn slice(v: Vec[UInt8], off: Int, len: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < len && off + i < v.len() {
    out.push(v[off + i]);
    i = i + 1;
  }
  return out;
}

fn extend(a: Vec[UInt8], b: Vec[UInt8]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < a.len() {
    out.push(a[i]);
    i = i + 1;
  }
  var j = 0;
  while j < b.len() {
    out.push(b[j]);
    j = j + 1;
  }
  return out;
}

fn zeros(n: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < n {
    out.push(0 as UInt8);
    i = i + 1;
  }
  return out;
}

fn table_is(data: &Vec[UInt8], w: &Woff, i: Int, want: Vec[UInt8]) -> Bool {
  let r = woff_table_data(data, w, i);
  if !r.is_ok {
    return false;
  }
  let v: Vec[UInt8] = r.value;
  return bytes_equal(v, want);
}

fn meta_is(data: &Vec[UInt8], w: &Woff, want: Vec[UInt8]) -> Bool {
  let r = woff_meta_copy(data, w);
  if !r.is_ok {
    return false;
  }
  let v: Vec[UInt8] = r.value;
  return bytes_equal(v, want);
}

fn priv_is(data: &Vec[UInt8], w: &Woff, want: Vec[UInt8]) -> Bool {
  let r = woff_priv_copy(data, w);
  if !r.is_ok {
    return false;
  }
  let v: Vec[UInt8] = r.value;
  return bytes_equal(v, want);
}

// --------------------------------------------------
//  Fixtures
// --------------------------------------------------

// Canonical valid single-table container: 44-byte header + one "glyf"
// entry (offset 64, 4 raw bytes, checksum 0xAABBCCDD) + table data.
// Layout: header 0..44, entry 44..64, data 64..68, length 68,
// totalSfntSize 12 + 16 + 4 = 32.
fn base_1table() -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  put_u32(&mut out, 2001684038); // "wOFF"
  put_u32(&mut out, 65536);      // flavor 0x00010000
  put_u32(&mut out, 68);         // length
  put_u16(&mut out, 1);          // numTables
  put_u16(&mut out, 0);          // reserved
  put_u32(&mut out, 32);         // totalSfntSize
  put_u16(&mut out, 0);          // majorVersion
  put_u16(&mut out, 0);          // minorVersion
  put_u32(&mut out, 0);          // metaOffset
  put_u32(&mut out, 0);          // metaLength
  put_u32(&mut out, 0);          // metaOrigLength
  put_u32(&mut out, 0);          // privOffset
  put_u32(&mut out, 0);          // privLength
  put_u32(&mut out, 1735162214); // "glyf"
  put_u32(&mut out, 64);         // offset
  put_u32(&mut out, 4);          // compLength
  put_u32(&mut out, 4);          // origLength
  put_u32(&mut out, 2864434397); // origChecksum 0xAABBCCDD
  put_bytes(&mut out, hb("cafebabe"));
  return out;
}

// Canonical valid two-table container: "cmap" at 84 and "glyf" at 88,
// 4 raw bytes each, length 92, totalSfntSize 12 + 32 + 4 + 4 = 52.
fn base_2table() -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  put_u32(&mut out, 2001684038); // "wOFF"
  put_u32(&mut out, 65536);      // flavor
  put_u32(&mut out, 92);         // length
  put_u16(&mut out, 2);          // numTables
  put_u16(&mut out, 0);          // reserved
  put_u32(&mut out, 52);         // totalSfntSize
  put_u16(&mut out, 0);          // majorVersion
  put_u16(&mut out, 0);          // minorVersion
  put_u32(&mut out, 0);
  put_u32(&mut out, 0);
  put_u32(&mut out, 0);
  put_u32(&mut out, 0);
  put_u32(&mut out, 0);
  put_u32(&mut out, 1668112752); // "cmap"
  put_u32(&mut out, 84);         // offset
  put_u32(&mut out, 4);          // compLength
  put_u32(&mut out, 4);          // origLength
  put_u32(&mut out, 1);          // origChecksum
  put_u32(&mut out, 1735162214); // "glyf"
  put_u32(&mut out, 88);         // offset
  put_u32(&mut out, 4);          // compLength
  put_u32(&mut out, 4);          // origLength
  put_u32(&mut out, 2);          // origChecksum
  put_bytes(&mut out, hb("01020304"));
  put_bytes(&mut out, hb("05060708"));
  return out;
}

// Single table plus a metadata block: table 64..68, compressed metadata
// 68..74 (6 bytes, metaOrigLength 100), length 74.
fn meta_1table() -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  put_u32(&mut out, 2001684038); // "wOFF"
  put_u32(&mut out, 65536);      // flavor
  put_u32(&mut out, 74);         // length
  put_u16(&mut out, 1);          // numTables
  put_u16(&mut out, 0);          // reserved
  put_u32(&mut out, 32);         // totalSfntSize
  put_u16(&mut out, 0);          // majorVersion
  put_u16(&mut out, 0);          // minorVersion
  put_u32(&mut out, 68);         // metaOffset
  put_u32(&mut out, 6);          // metaLength
  put_u32(&mut out, 100);        // metaOrigLength
  put_u32(&mut out, 0);          // privOffset
  put_u32(&mut out, 0);          // privLength
  put_u32(&mut out, 1735162214); // "glyf"
  put_u32(&mut out, 64);         // offset
  put_u32(&mut out, 4);          // compLength
  put_u32(&mut out, 4);          // origLength
  put_u32(&mut out, 2864434397); // origChecksum
  put_bytes(&mut out, hb("cafebabe"));
  put_bytes(&mut out, hb("1f8b08000000"));
  return out;
}

// Single table plus both optional blocks: table 64..68, metadata 68..72
// (4 bytes, metaOrigLength 20), private data 72..76 (4 bytes),
// length 76.
fn both_blocks() -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  put_u32(&mut out, 2001684038); // "wOFF"
  put_u32(&mut out, 65536);      // flavor
  put_u32(&mut out, 76);         // length
  put_u16(&mut out, 1);          // numTables
  put_u16(&mut out, 0);          // reserved
  put_u32(&mut out, 32);         // totalSfntSize
  put_u16(&mut out, 0);          // majorVersion
  put_u16(&mut out, 0);          // minorVersion
  put_u32(&mut out, 68);         // metaOffset
  put_u32(&mut out, 4);          // metaLength
  put_u32(&mut out, 20);         // metaOrigLength
  put_u32(&mut out, 72);         // privOffset
  put_u32(&mut out, 4);          // privLength
  put_u32(&mut out, 1735162214); // "glyf"
  put_u32(&mut out, 64);         // offset
  put_u32(&mut out, 4);          // compLength
  put_u32(&mut out, 4);          // origLength
  put_u32(&mut out, 2864434397); // origChecksum
  put_bytes(&mut out, hb("cafebabe"));
  put_bytes(&mut out, hb("1f8b0800"));
  put_bytes(&mut out, hb("0badc0de"));
  return out;
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  var tags = Vec[Int].new();
  tags.push(1330851634); // "OS/2"
  tags.push(1668112752); // "cmap"
  tags.push(1735162214); // "glyf"
  var datas = Vec[Vec[UInt8]].new();
  datas.push(hb("001122"));
  datas.push(hb("cafe"));
  datas.push(hb("deadbeef99"));
  var sums = Vec[Int].new();
  sums.push(1);
  sums.push(2);
  sums.push(4294967295);
  let br = woff_build(65536, &tags, &datas, &sums);
  if !br.is_ok { return assert(false, "build must succeed"); }
  let built: Vec[UInt8] = br.value;
  var ok = built.len() == 120;
  let pr = woff_parse(&built);
  if !pr.is_ok { return assert(false, "built container must parse"); }
  let w: Woff = pr.value;
  if woff_flavor(&w) != 65536 { ok = false; }
  if woff_length(&w) != 120 { ok = false; }
  if woff_num_tables(&w) != 3 { ok = false; }
  if woff_total_sfnt_size(&w) != 76 { ok = false; }
  if woff_major_version(&w) != 0 { ok = false; }
  if woff_minor_version(&w) != 0 { ok = false; }
  if woff_table_tag(&w, 0) != 1330851634 { ok = false; }
  if woff_table_tag(&w, 1) != 1668112752 { ok = false; }
  if woff_table_tag(&w, 2) != 1735162214 { ok = false; }
  if woff_table_offset(&w, 0) != 104 { ok = false; }
  if woff_table_offset(&w, 1) != 108 { ok = false; }
  if woff_table_offset(&w, 2) != 112 { ok = false; }
  if woff_table_comp_length(&w, 0) != 3 { ok = false; }
  if woff_table_orig_length(&w, 2) != 5 { ok = false; }
  if woff_table_checksum(&w, 2) != 4294967295 { ok = false; }
  if woff_table_is_compressed(&w, 0) { ok = false; }
  if woff_find_tag_str(&w, "glyf") != 2 { ok = false; }
  if woff_find_tag(&w, 1668112752) != 1 { ok = false; }
  if woff_find_tag_str(&w, "nope") != -1 { ok = false; }
  if woff_has_metadata(&w) { ok = false; }
  if woff_has_private(&w) { ok = false; }
  if !table_is(&built, &w, 0, hb("001122")) { ok = false; }
  if !table_is(&built, &w, 1, hb("cafe")) { ok = false; }
  if !table_is(&built, &w, 2, hb("deadbeef99")) { ok = false; }
  return assert(ok, "build -> parse round-trip pins header, directory and table bytes");
}

fn t2() -> TestResult {
  var tags = Vec[Int].new();
  tags.push(1735162214); // "glyf"
  var datas = Vec[Vec[UInt8]].new();
  datas.push(hb("01020304"));
  var sums = Vec[Int].new();
  sums.push(287454020); // 0x11223344
  let br = woff_build(65536, &tags, &datas, &sums);
  if !br.is_ok { return assert(false, "build must succeed"); }
  let b: Vec[UInt8] = br.value;
  var ok = b.len() == 68;
  if !bytes_equal(slice(b, 0, 4), hb("774f4646")) { ok = false; }
  if rd32(&b, 4) != 65536 { ok = false; }
  if rd32(&b, 8) != 68 { ok = false; }
  if rd16(&b, 12) != 1 { ok = false; }
  if rd16(&b, 14) != 0 { ok = false; }
  if rd32(&b, 16) != 32 { ok = false; }
  if rd16(&b, 20) != 0 { ok = false; }
  if rd16(&b, 22) != 0 { ok = false; }
  if rd32(&b, 24) != 0 { ok = false; }
  if rd32(&b, 28) != 0 { ok = false; }
  if rd32(&b, 32) != 0 { ok = false; }
  if rd32(&b, 36) != 0 { ok = false; }
  if rd32(&b, 40) != 0 { ok = false; }
  if rd32(&b, 44) != 1735162214 { ok = false; }
  if rd32(&b, 48) != 64 { ok = false; }
  if rd32(&b, 52) != 4 { ok = false; }
  if rd32(&b, 56) != 4 { ok = false; }
  if rd32(&b, 60) != 287454020 { ok = false; }
  if !bytes_equal(slice(b, 64, 4), hb("01020304")) { ok = false; }
  let pr = woff_parse(&b);
  if !pr.is_ok { ok = false; }
  return assert(ok, "single-table build emits the canonical 68-byte layout");
}

fn t3() -> TestResult {
  var tags = Vec[Int].new();
  tags.push(1330851634); // "OS/2"
  tags.push(1668112752); // "cmap"
  tags.push(1735162214); // "glyf"
  var datas = Vec[Vec[UInt8]].new();
  datas.push(hb("001122"));     // 3 bytes -> pad 1 at 107
  datas.push(hb("cafe"));       // 2 bytes -> pad 2 at 110..112
  datas.push(hb("deadbeef99")); // 5 bytes -> pad 3 at 117..120
  var sums = Vec[Int].new();
  sums.push(1);
  sums.push(2);
  sums.push(3);
  let br = woff_build(65536, &tags, &datas, &sums);
  if !br.is_ok { return assert(false, "build must succeed"); }
  let b: Vec[UInt8] = br.value;
  var ok = b.len() == 120;
  if rd32(&b, 48) != 104 { ok = false; }
  if rd32(&b, 68) != 108 { ok = false; }
  if rd32(&b, 88) != 112 { ok = false; }
  if rd8(&b, 107) != 0 { ok = false; }
  if rd8(&b, 110) != 0 { ok = false; }
  if rd8(&b, 111) != 0 { ok = false; }
  if rd8(&b, 117) != 0 { ok = false; }
  if rd8(&b, 118) != 0 { ok = false; }
  if rd8(&b, 119) != 0 { ok = false; }
  var padded = b;
  patch_byte(&mut padded, 107, 170);
  let pr = woff_parse(&padded);
  var ok2 = pr.is_ok;
  if pr.is_ok {
    let w: Woff = pr.value;
    if !table_is(&padded, &w, 0, hb("001122")) { ok2 = false; }
    if woff_table_offset(&w, 1) != 108 { ok2 = false; }
  }
  return assert(ok && ok2, "build pads every table to 4 bytes; padding is not inspected on parse");
}

fn t4() -> TestResult {
  var empty = Vec[UInt8].new();
  var ok = err_woff_is(woff_parse(&empty), "woff: truncated header");
  let short = zeros(43);
  if !err_woff_is(woff_parse(&short), "woff: truncated header") { ok = false; }
  let bare = zeros(44);
  if !err_woff_is(woff_parse(&bare), "woff: bad signature") { ok = false; }
  var w2 = zeros(44);
  patch_u32(&mut w2, 0, 2001684018); // "wOF2" (WOFF2)
  patch_u32(&mut w2, 8, 44);
  if !err_woff_is(woff_parse(&w2), "woff: bad signature") { ok = false; }
  var w3 = zeros(44);
  patch_u32(&mut w3, 0, 2001684038); // "wOFF"
  patch_u32(&mut w3, 8, 43);         // declared size below the header
  if !err_woff_is(woff_parse(&w3), "woff: length mismatch") { ok = false; }
  return assert(ok, "short buffers are truncated headers; wOF2 and wrong magic are bad signatures");
}

fn t5() -> TestResult {
  var b = base_1table();
  patch_u32(&mut b, 8, 69);
  var ok = err_woff_is(woff_parse(&b), "woff: length mismatch");
  let full = base_1table();
  let cut = slice(full, 0, 67);
  if !err_woff_is(woff_parse(&cut), "woff: length mismatch") { ok = false; }
  let base = base_1table();
  let trailed = extend(base, hb("00"));
  if !err_woff_is(woff_parse(&trailed), "woff: length mismatch") { ok = false; }
  return assert(ok, "the declared length must equal the buffer length (truncation and trailing bytes)");
}

fn t6() -> TestResult {
  var b = base_1table();
  patch_u16(&mut b, 14, 1);
  var ok = err_woff_is(woff_parse(&b), "woff: nonzero reserved");
  var b2 = base_1table();
  patch_u16(&mut b2, 14, 256); // 0x0100
  if !err_woff_is(woff_parse(&b2), "woff: nonzero reserved") { ok = false; }
  return assert(ok, "a non-zero reserved field is rejected");
}

fn t7() -> TestResult {
  var big = base_1table();
  patch_u16(&mut big, 12, 4097);
  var ok = err_woff_is(woff_parse(&big), "woff: too many tables");
  var dir = base_1table();
  patch_u16(&mut dir, 12, 5); // 44 + 100 > 68
  if !err_woff_is(woff_parse(&dir), "woff: truncated directory") { ok = false; }
  var cap = base_1table();
  patch_u16(&mut cap, 12, 4096); // at the cap: directory still overruns this buffer
  if !err_woff_is(woff_parse(&cap), "woff: truncated directory") { ok = false; }
  return assert(ok, "numTables above the cap and a directory that overruns the buffer are rejected");
}

fn t8() -> TestResult {
  var b1 = base_1table();
  patch_u32(&mut b1, 44, 524370241); // 0x1F414141: first byte 0x1F
  var ok = err_woff_is(woff_parse(&b1), "woff: invalid table tag");
  var b2 = base_1table();
  patch_byte(&mut b2, 46, 0);
  if !err_woff_is(woff_parse(&b2), "woff: invalid table tag") { ok = false; }
  var b3 = base_1table();
  patch_byte(&mut b3, 44, 127); // 0x7F
  if !err_woff_is(woff_parse(&b3), "woff: invalid table tag") { ok = false; }
  return assert(ok, "tag bytes outside 0x20..0x7E are rejected");
}

fn t9() -> TestResult {
  var b = base_1table();
  patch_u32(&mut b, 52, 5); // compLength 5 > origLength 4
  return assert(err_woff_is(woff_parse(&b), "woff: compressed length exceeds original"), "compLength greater than origLength is rejected");
}

fn t10() -> TestResult {
  var b = base_1table();
  patch_u32(&mut b, 48, 66); // not a multiple of 4
  return assert(err_woff_is(woff_parse(&b), "woff: unaligned table offset"), "table offsets must be 4-byte aligned");
}

fn t11() -> TestResult {
  var below = base_1table();
  patch_u32(&mut below, 48, 40); // before the directory end (64)
  var ok = err_woff_is(woff_parse(&below), "woff: table offset out of range");
  var above = base_1table();
  patch_u32(&mut above, 48, 72); // past the buffer end (68), 4-aligned
  if !err_woff_is(woff_parse(&above), "woff: table offset out of range") { ok = false; }
  return assert(ok, "table offsets outside the directory..buffer range are rejected");
}

fn t12() -> TestResult {
  var b = base_1table();
  patch_u32(&mut b, 52, 5);  // compLength 5
  patch_u32(&mut b, 56, 8);  // origLength 8 keeps comp <= orig
  return assert(err_woff_is(woff_parse(&b), "woff: table data out of bounds"), "table spans past the end of the buffer are rejected");
}

fn t13() -> TestResult {
  var low = base_1table();
  patch_u32(&mut low, 16, 28);
  var ok = err_woff_is(woff_parse(&low), "woff: bad total sfnt size");
  var high = base_1table();
  patch_u32(&mut high, 16, 36);
  if !err_woff_is(woff_parse(&high), "woff: bad total sfnt size") { ok = false; }
  var odd = base_1table();
  patch_u32(&mut odd, 16, 33);
  if !err_woff_is(woff_parse(&odd), "woff: bad total sfnt size") { ok = false; }
  return assert(ok, "totalSfntSize must equal 12 + 16*numTables + padded origLengths");
}

fn t14() -> TestResult {
  var full = base_2table();
  patch_u32(&mut full, 68, 84); // second table starts at the first
  var ok = err_woff_is(woff_parse(&full), "woff: overlapping tables");
  var part = base_2table();
  patch_u32(&mut part, 52, 8); // first table 84..92
  patch_u32(&mut part, 56, 8);
  patch_u32(&mut part, 16, 56); // 12 + 32 + 8 + 4
  if !err_woff_is(woff_parse(&part), "woff: overlapping tables") { ok = false; }
  return assert(ok, "overlapping table spans are rejected (full and partial)");
}

fn t15() -> TestResult {
  var z = base_1table();
  patch_u32(&mut z, 52, 0);
  patch_u32(&mut z, 56, 0);
  patch_u32(&mut z, 16, 28); // 12 + 16 + 0
  let pr = woff_parse(&z);
  var ok = pr.is_ok;
  if pr.is_ok {
    let w: Woff = pr.value;
    if woff_table_comp_length(&w, 0) != 0 { ok = false; }
    if woff_table_orig_length(&w, 0) != 0 { ok = false; }
    if woff_table_is_compressed(&w, 0) { ok = false; }
    if !table_is(&z, &w, 0, Vec[UInt8].new()) { ok = false; }
  }
  var z2 = base_2table();
  patch_u32(&mut z2, 68, 84); // empty second table shares the first's offset
  patch_u32(&mut z2, 72, 0);
  patch_u32(&mut z2, 76, 0);
  patch_u32(&mut z2, 16, 48); // 12 + 32 + 4 + 0
  let pr2 = woff_parse(&z2);
  var ok2 = pr2.is_ok;
  if pr2.is_ok {
    let w2: Woff = pr2.value;
    if woff_table_is_compressed(&w2, 1) { ok2 = false; }
    if !table_is(&z2, &w2, 1, Vec[UInt8].new()) { ok2 = false; }
    if !table_is(&z2, &w2, 0, hb("01020304")) { ok2 = false; }
  }
  var z3 = base_1table();
  patch_u32(&mut z3, 48, 68); // offset == buffer end, compLength 0
  patch_u32(&mut z3, 52, 0);
  patch_u32(&mut z3, 56, 0);
  patch_u32(&mut z3, 16, 28);
  let ok3 = woff_parse(&z3).is_ok;
  var z4 = base_1table();
  patch_u32(&mut z4, 52, 0); // compLength 0 with origLength 4: unmappable
  let ok4 = err_woff_is(woff_parse(&z4), "woff: zero compLength with nonzero origLength");
  return assert(ok && ok2 && ok3 && ok4, "zero-length tables are valid empty spans and never overlap");
}

fn t16() -> TestResult {
  let base = base_1table();
  var b = slice(base, 0, 66);
  patch_u32(&mut b, 8, 66);  // length 66
  patch_u32(&mut b, 16, 36); // 12 + 16 + 8
  patch_u32(&mut b, 52, 2);  // compLength 2 < origLength 6
  patch_u32(&mut b, 56, 6);
  let pr = woff_parse(&b);
  var ok = pr.is_ok;
  if pr.is_ok {
    let w: Woff = pr.value;
    if !woff_table_is_compressed(&w, 0) { ok = false; }
    if woff_table_comp_length(&w, 0) != 2 { ok = false; }
    if woff_table_orig_length(&w, 0) != 6 { ok = false; }
    if woff_total_sfnt_size(&w) != 36 { ok = false; }
    if !table_is(&b, &w, 0, hb("cafe")) { ok = false; }
  }
  return assert(ok, "compLength < origLength marks a compressed table kept raw");
}

fn t17() -> TestResult {
  let b = meta_1table();
  let pr = woff_parse(&b);
  var ok = pr.is_ok;
  if pr.is_ok {
    let w: Woff = pr.value;
    if !woff_has_metadata(&w) { ok = false; }
    if woff_has_private(&w) { ok = false; }
    if woff_meta_offset(&w) != 68 { ok = false; }
    if woff_meta_length(&w) != 6 { ok = false; }
    if woff_meta_orig_length(&w) != 100 { ok = false; }
    if woff_priv_offset(&w) != 0 { ok = false; }
    if woff_priv_length(&w) != 0 { ok = false; }
    if woff_length(&w) != 74 { ok = false; }
    if woff_num_tables(&w) != 1 { ok = false; }
    if !meta_is(&b, &w, hb("1f8b08000000")) { ok = false; }
    if !table_is(&b, &w, 0, hb("cafebabe")) { ok = false; }
    if !err_bytes_is(woff_priv_copy(&b, &w), "woff: no private data") { ok = false; }
  }
  var off = meta_1table();
  patch_u32(&mut off, 24, 200); // beyond the file: ignored while metaLength is 0
  patch_u32(&mut off, 28, 0);
  let pr2 = woff_parse(&off);
  var ok2 = pr2.is_ok;
  if pr2.is_ok {
    let w2: Woff = pr2.value;
    if woff_has_metadata(&w2) { ok2 = false; }
    if !err_bytes_is(woff_meta_copy(&off, &w2), "woff: no metadata") { ok2 = false; }
  }
  return assert(ok && ok2, "metadata accessors and raw copy; a zero metaLength ignores metaOffset");
}

fn t18() -> TestResult {
  var un = meta_1table();
  patch_u32(&mut un, 24, 66);
  var ok = err_woff_is(woff_parse(&un), "woff: unaligned metadata offset");
  var low = meta_1table();
  patch_u32(&mut low, 24, 60); // before the directory end (64)
  if !err_woff_is(woff_parse(&low), "woff: metadata out of bounds") { ok = false; }
  var past = meta_1table();
  patch_u32(&mut past, 24, 72); // 72 + 6 > 74
  if !err_woff_is(woff_parse(&past), "woff: metadata out of bounds") { ok = false; }
  var over = meta_1table();
  patch_u32(&mut over, 24, 76); // beyond the buffer end
  if !err_woff_is(woff_parse(&over), "woff: metadata out of bounds") { ok = false; }
  var lap = meta_1table();
  patch_u32(&mut lap, 24, 64); // inside the table span 64..68
  if !err_woff_is(woff_parse(&lap), "woff: metadata overlaps table") { ok = false; }
  return assert(ok, "metadata alignment, bounds and table-overlap errors");
}

fn t19() -> TestResult {
  let b = both_blocks();
  let pr = woff_parse(&b);
  var ok = pr.is_ok;
  if pr.is_ok {
    let w: Woff = pr.value;
    if !woff_has_metadata(&w) { ok = false; }
    if !woff_has_private(&w) { ok = false; }
    if woff_meta_offset(&w) != 68 { ok = false; }
    if woff_meta_length(&w) != 4 { ok = false; }
    if woff_meta_orig_length(&w) != 20 { ok = false; }
    if woff_priv_offset(&w) != 72 { ok = false; }
    if woff_priv_length(&w) != 4 { ok = false; }
    if !meta_is(&b, &w, hb("1f8b0800")) { ok = false; }
    if !priv_is(&b, &w, hb("0badc0de")) { ok = false; }
  }
  let base = base_1table();
  var p = extend(base, hb("c0ffee"));
  patch_u32(&mut p, 8, 71);
  patch_u32(&mut p, 36, 68);
  patch_u32(&mut p, 40, 3);
  let prp = woff_parse(&p);
  var ok2 = prp.is_ok;
  if prp.is_ok {
    let wp: Woff = prp.value;
    if !priv_is(&p, &wp, hb("c0ffee")) { ok2 = false; }
  }
  var tail = extend(base_1table(), hb("c0ffee"));
  patch_u32(&mut tail, 8, 71);
  patch_u32(&mut tail, 36, 68);
  patch_u32(&mut tail, 40, 2); // span 68..70 does not reach EOF: tolerated
  let ok2b = woff_parse(&tail).is_ok;
  var un = extend(base_1table(), hb("c0ffee"));
  patch_u32(&mut un, 8, 71);
  patch_u32(&mut un, 36, 66);
  patch_u32(&mut un, 40, 3);
  var ok3 = err_woff_is(woff_parse(&un), "woff: unaligned private offset");
  var ob = extend(base_1table(), hb("c0ffee"));
  patch_u32(&mut ob, 8, 71);
  patch_u32(&mut ob, 36, 64);
  patch_u32(&mut ob, 40, 100);
  if !err_woff_is(woff_parse(&ob), "woff: private data out of bounds") { ok3 = false; }
  var below = extend(base_1table(), hb("c0ffee"));
  patch_u32(&mut below, 8, 71);
  patch_u32(&mut below, 36, 60);
  patch_u32(&mut below, 40, 3);
  if !err_woff_is(woff_parse(&below), "woff: private data out of bounds") { ok3 = false; }
  var lap = extend(base_1table(), hb("c0ffee"));
  patch_u32(&mut lap, 8, 71);
  patch_u32(&mut lap, 36, 64);
  patch_u32(&mut lap, 40, 4);
  if !err_woff_is(woff_parse(&lap), "woff: private data overlaps table") { ok3 = false; }
  return assert(ok && ok2 && ok2b && ok3, "private block accessors and raw copy; private span errors");
}

fn t20() -> TestResult {
  var b = both_blocks();
  patch_u32(&mut b, 28, 6); // metadata 68..74 now runs into the private block 72..76
  return assert(err_woff_is(woff_parse(&b), "woff: metadata overlaps private data"), "metadata overlapping the private block is rejected");
}

fn t21() -> TestResult {
  let data = base_1table();
  let pr = woff_parse(&data);
  if !pr.is_ok { return assert(false, "fixture must parse"); }
  let w: Woff = pr.value;
  var ok = woff_table_tag(&w, -1) == -1;
  if woff_table_tag(&w, 1) != -1 { ok = false; }
  if woff_table_offset(&w, 1) != -1 { ok = false; }
  if woff_table_comp_length(&w, 1) != -1 { ok = false; }
  if woff_table_orig_length(&w, 1) != -1 { ok = false; }
  if woff_table_checksum(&w, 1) != -1 { ok = false; }
  if woff_table_is_compressed(&w, 1) { ok = false; }
  if woff_table_is_compressed(&w, -1) { ok = false; }
  if !err_bytes_is(woff_table_data(&data, &w, 1), "woff: index out of range") { ok = false; }
  if !err_bytes_is(woff_table_data(&data, &w, -1), "woff: index out of range") { ok = false; }
  let cut = slice(data, 0, 66);
  if !err_bytes_is(woff_table_data(&cut, &w, 0), "woff: table data out of bounds") { ok = false; }
  if !err_bytes_is(woff_meta_copy(&data, &w), "woff: no metadata") { ok = false; }
  if !err_bytes_is(woff_priv_copy(&data, &w), "woff: no private data") { ok = false; }
  var dup = base_2table();
  patch_u32(&mut dup, 44, 1735162214); // both entries are "glyf"
  let pr2 = woff_parse(&dup);
  var ok2 = pr2.is_ok;
  if pr2.is_ok {
    let w2: Woff = pr2.value;
    if woff_num_tables(&w2) != 2 { ok2 = false; }
    if woff_find_tag_str(&w2, "glyf") != 0 { ok2 = false; }
    if woff_find_tag(&w2, 1668112752) != -1 { ok2 = false; }
  }
  return assert(ok && ok2, "accessors and copiers guard bad indexes and short buffers; duplicate tags use first match");
}

fn t22() -> TestResult {
  var ok = woff_tag_of("glyf") == 1735162214;
  if woff_tag_of("OS/2") != 1330851634 { ok = false; }
  if woff_tag_of("~~~~") != 2122219134 { ok = false; }
  if woff_tag_of(" ab ") == -1 { ok = false; } // space is inside 0x20..0x7E
  if woff_tag_of("abc") != -1 { ok = false; }
  if woff_tag_of("abcde") != -1 { ok = false; }
  if woff_tag_of("") != -1 { ok = false; }
  if woff_tag_of("\u{007F}abc") != -1 { ok = false; }
  if woff_tag_of("\u{0001}abc") != -1 { ok = false; }
  return assert(ok, "woff_tag_of maps four printable-ASCII bytes and rejects everything else");
}

fn t23() -> TestResult {
  var tags = Vec[Int].new();
  var datas = Vec[Vec[UInt8]].new();
  var sums = Vec[Int].new();
  let br = woff_build(0, &tags, &datas, &sums);
  if !br.is_ok { return assert(false, "empty build must succeed"); }
  let b: Vec[UInt8] = br.value;
  var ok = b.len() == 44;
  if rd32(&b, 8) != 44 { ok = false; }
  if rd16(&b, 12) != 0 { ok = false; }
  if rd32(&b, 16) != 12 { ok = false; }
  let pr = woff_parse(&b);
  if !pr.is_ok { return assert(false, "44-byte container must parse"); }
  let w: Woff = pr.value;
  if woff_num_tables(&w) != 0 { ok = false; }
  if woff_total_sfnt_size(&w) != 12 { ok = false; }
  if woff_length(&w) != 44 { ok = false; }
  if woff_flavor(&w) != 0 { ok = false; }
  if woff_find_tag(&w, 1735162214) != -1 { ok = false; }
  if woff_table_tag(&w, 0) != -1 { ok = false; }
  if woff_table_is_compressed(&w, 0) { ok = false; }
  if !err_bytes_is(woff_table_data(&b, &w, 0), "woff: index out of range") { ok = false; }
  if !err_bytes_is(woff_meta_copy(&b, &w), "woff: no metadata") { ok = false; }
  if !err_bytes_is(woff_priv_copy(&b, &w), "woff: no private data") { ok = false; }
  return assert(ok, "an empty build produces the 44-byte header and parses to zero tables");
}

fn t24() -> TestResult {
  var tags = Vec[Int].new();
  tags.push(1735162214); // "glyf"
  var datas = Vec[Vec[UInt8]].new();
  datas.push(hb("00"));
  var sums = Vec[Int].new();
  sums.push(1);
  var ok = err_bytes_is(woff_build(-1, &tags, &datas, &sums), "woff: flavor out of range");
  if !err_bytes_is(woff_build(4294967296, &tags, &datas, &sums), "woff: flavor out of range") { ok = false; }
  var no_datas = Vec[Vec[UInt8]].new();
  var no_sums = Vec[Int].new();
  if !err_bytes_is(woff_build(1, &tags, &no_datas, &sums), "woff: table vectors length mismatch") { ok = false; }
  if !err_bytes_is(woff_build(1, &tags, &datas, &no_sums), "woff: table vectors length mismatch") { ok = false; }
  var bad_tags = Vec[Int].new();
  bad_tags.push(0);
  if !err_bytes_is(woff_build(1, &bad_tags, &datas, &sums), "woff: invalid table tag") { ok = false; }
  var neg_tags = Vec[Int].new();
  neg_tags.push(-1);
  if !err_bytes_is(woff_build(1, &neg_tags, &datas, &sums), "woff: invalid table tag") { ok = false; }
  var low_tags = Vec[Int].new();
  low_tags.push(524370241); // 0x1F414141
  if !err_bytes_is(woff_build(1, &low_tags, &datas, &sums), "woff: invalid table tag") { ok = false; }
  var bad_sums = Vec[Int].new();
  bad_sums.push(-1);
  if !err_bytes_is(woff_build(1, &tags, &datas, &bad_sums), "woff: checksum out of range") { ok = false; }
  var big_sums = Vec[Int].new();
  big_sums.push(4294967296);
  if !err_bytes_is(woff_build(1, &tags, &datas, &big_sums), "woff: checksum out of range") { ok = false; }
  var many_tags = Vec[Int].new();
  var many_datas = Vec[Vec[UInt8]].new();
  var many_sums = Vec[Int].new();
  var i = 0;
  while i < 4097 {
    many_tags.push(1094795585); // "AAAA"
    var empty = Vec[UInt8].new();
    many_datas.push(empty);
    many_sums.push(0);
    i = i + 1;
  }
  if !err_bytes_is(woff_build(1, &many_tags, &many_datas, &many_sums), "woff: too many tables") { ok = false; }
  return assert(ok, "builder validation: flavor, vector lengths, tags, checksums and the table cap");
}

fn main() -> Int {
  io.println("=== xiom.woff conformance tests ===");
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
  if failed == 0 {
    io.println("xiom.woff: all tests passed");
  } else {
    io.println("xiom.woff: tests failed");
  }
  return failed;
}
