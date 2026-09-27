// XIOM -- xiom.badger conformance tests (20 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Covers the documented API against synthetic buffers assembled byte by byte,
// independent of src/badger.xi:
//   * CRC32C known-answer vectors ("123456789", 32 zero bytes, 00..1F, 32
//     0xFF bytes) plus an independent bit-serial reference over 256 bytes;
//   * the 20-byte value log header (field matrix, bit-63 raw expiry pattern,
//     reserved bytes, caps, truncation) and the multi-entry walk (spans,
//     consumed counts, total_bytes, max-entries and cap bounds);
//   * the meta bit table and names for all six defined bits;
//   * versioned keys (version/delete accessors, empty user key, bit-63 tag
//     rejection, short key, out-of-bounds span);
//   * the SST header (magic/version/block size/checksum type/reserved);
//   * SST data-block entries with shared-prefix reconstruction, entry and
//     value spans, entry offsets, zero-byte and overrun rejection;
//   * the 4-byte block trailer and its CRC32C check;
//   * the bloom block (parse, checksum, nbits/nhashes bounds, ceil bit-array
//     size, hash-pair known answers, membership with double hashing);
//   * the block index (parse, accessors, first-key-ge lookup, checksum and
//     length mismatch, caps) and the 16-byte table footer (index handle
//     bounds, checksum);
//   * the manifest header and 40-byte file-list entries (selectors, flags,
//     version bounds, consumed counts, crc, unknown-flag errors carrying the
//     file id);
//   * a composite SST file assembled from header + block + trailer + index +
//     bloom + footer and read back end to end.
//
// Every fixture is a synthetic byte buffer built in-test; no external data
// files. Str equality goes through str_compare (BUG 17 discipline: `==` on a
// Str read from a Vec lowers to a pointer comparison). The local CRC32C and
// FNV-1a-32 helpers are written independently of the module.

module badger_tests
use xiom.io; use xiom.test;
use xiom.badger;
use xiom.string;
use xiom.string.compare;

// --------------------------------------------------
//  Generic test helpers
// --------------------------------------------------

fn str_eq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn err_int_is(r: Result[Int, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return str_eq(r.error, want);
}

fn err_bool_is(r: Result[Bool, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return str_eq(r.error, want);
}

fn err_bytes_is(r: Result[Vec[UInt8], Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return str_eq(r.error, want);
}

fn err_key_is(r: Result[BadgerKey, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return str_eq(r.error, want);
}

fn err_vh_is(r: Result[BadgerVlogHeader, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return str_eq(r.error, want);
}

fn err_vwalk_is(r: Result[BadgerVlogWalk, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return str_eq(r.error, want);
}

fn err_ssth_is(r: Result[BadgerSstHeader, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return str_eq(r.error, want);
}

fn err_sse_is(r: Result[BadgerSstEntry, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return str_eq(r.error, want);
}

fn err_sse_list_is(r: Result[BadgerSstEntries, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return str_eq(r.error, want);
}

fn err_trailer_is(r: Result[BadgerSstBlockTrailer, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return str_eq(r.error, want);
}

fn err_idx_is(r: Result[BadgerSstIndex, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return str_eq(r.error, want);
}

fn err_ft_is(r: Result[BadgerSstFooter, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return str_eq(r.error, want);
}

fn err_bloom_is(r: Result[BadgerBloom, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return str_eq(r.error, want);
}

fn err_bhp_is(r: Result[BadgerBloomHashPair, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return str_eq(r.error, want);
}

fn err_mh_is(r: Result[BadgerManifestHeader, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return str_eq(r.error, want);
}

fn err_me_is(r: Result[BadgerManifestEntry, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return str_eq(r.error, want);
}

fn err_mf_is(r: Result[BadgerManifestFiles, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return str_eq(r.error, want);
}

fn int_is(r: Result[Int, Str], want: Int) -> Bool {
  if !r.is_ok { return false; }
  let v: Int = r.value;
  return v == want;
}

fn bool_is(r: Result[Bool, Str], want: Bool) -> Bool {
  if !r.is_ok { return false; }
  let v: Bool = r.value;
  if v == want { return true; }
  return false;
}

fn bytes_eq(a: &Vec[UInt8], b: &Vec[UInt8]) -> Bool {
  if a.len() != b.len() { return false; }
  var i = 0;
  while i < a.len() {
    let x: UInt8 = a[i];
    let y: UInt8 = b[i];
    if x != y { return false; }
    i = i + 1;
  }
  return true;
}

// --------------------------------------------------
//  Byte helpers (independent of src/badger.xi)
// --------------------------------------------------

fn gb(data: &Vec[UInt8], pos: Int) -> Int {
  return (data[pos] as Int) & 0xFF;
}

fn text(s: Str) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  push_text(&mut v, s);
  return v;
}

fn push_text(dst: &mut Vec[UInt8], s: Str) {
  var i = 0;
  while i < s.len() {
    dst.push(string.byte_at(s, i));
    i = i + 1;
  }
}

fn append_bytes(dst: &mut Vec[UInt8], src: &Vec[UInt8]) {
  var i = 0;
  while i < src.len() {
    let b: UInt8 = src[i];
    dst.push(b);
    i = i + 1;
  }
}

fn push_zeros(dst: &mut Vec[UInt8], n: Int) {
  var i = 0;
  while i < n {
    dst.push(0 as UInt8);
    i = i + 1;
  }
}

fn zeros(n: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  push_zeros(&mut v, n);
  return v;
}

fn set_at(src: &Vec[UInt8], pos: Int, v: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < src.len() {
    if i == pos {
      out.push(v as UInt8);
    } else {
      let b: UInt8 = src[i];
      out.push(b);
    }
    i = i + 1;
  }
  return out;
}

fn slice_of(src: &Vec[UInt8], start: Int, size: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < size {
    let b: UInt8 = src[start + i];
    out.push(b);
    i = i + 1;
  }
  return out;
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

fn push_le32(dst: &mut Vec[UInt8], v: Int) {
  dst.push(byte_of(v, 0));
  dst.push(byte_of(v, 1));
  dst.push(byte_of(v, 2));
  dst.push(byte_of(v, 3));
}

fn push_le64(dst: &mut Vec[UInt8], v: Int) {
  dst.push(byte_of(v, 0));
  dst.push(byte_of(v, 1));
  dst.push(byte_of(v, 2));
  dst.push(byte_of(v, 3));
  dst.push(byte_of(v, 4));
  dst.push(byte_of(v, 5));
  dst.push(byte_of(v, 6));
  dst.push(byte_of(v, 7));
}

fn le32(v: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  push_le32(&mut out, v);
  return out;
}

fn le64(v: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  push_le64(&mut out, v);
  return out;
}

fn push_varint(dst: &mut Vec[UInt8], v: Int) {
  var x = v;
  while x >= 128 {
    let b: Int = (x % 128) + 128;
    dst.push(b as UInt8);
    x = x / 128;
  }
  dst.push(x as UInt8);
}

fn pow2_local(k: Int) -> Int {
  var p = 1;
  var i = 0;
  while i < k {
    p = p * 2;
    i = i + 1;
  }
  return p;
}

fn ceil8_local(n: Int) -> Int {
  let q = n / 8;
  let r = n % 8;
  if r > 0 { return q + 1; }
  return q;
}

fn append_ints(dst: &mut Vec[Int], src: &Vec[Int]) {
  var i = 0;
  while i < src.len() {
    let v: Int = src[i];
    dst.push(v);
    i = i + 1;
  }
}

// Copy `body` and append the CRC32C of the body as u32 LE. Building the copy
// before the checksum keeps every Vec borrow single-ended (warning-free).
fn with_crc(body: &Vec[UInt8]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  append_bytes(&mut out, body);
  let crc = crc_local(body, 0, body.len());
  push_le32(&mut out, crc);
  return out;
}

// --------------------------------------------------
//  Independent CRC32C and FNV-1a-32 references
// --------------------------------------------------

fn crc_step_local(crc: Int, b: Int) -> Int {
  var c = crc ^ b;
  var k = 0;
  while k < 8 {
    let lsb = c % 2;
    c = c / 2;
    if lsb == 1 {
      c = c ^ 2197175160;
    }
    k = k + 1;
  }
  return c;
}

fn crc_local(data: &Vec[UInt8], start: Int, size: Int) -> Int {
  var c = 4294967295;
  var i = 0;
  while i < size {
    c = crc_step_local(c, gb(data, start + i));
    i = i + 1;
  }
  return (c ^ 4294967295) & 4294967295;
}

// 32-bit xor without bitwise operators (arithmetic bit loop).
fn bxor_local(a: Int, b: Int, bits: Int) -> Int {
  var x = a;
  var y = b;
  var out = 0;
  var bit = 1;
  var i = 0;
  while i < bits {
    let xb = x % 2;
    let yb = y % 2;
    if xb != yb {
      out = out + bit;
    }
    x = x / 2;
    y = y / 2;
    bit = bit * 2;
    i = i + 1;
  }
  return out;
}

fn fnv_local(data: &Vec[UInt8], off: Int, size: Int, domain: Int) -> Int {
  var h = 2166136261;
  if domain != 0 {
    h = (bxor_local(h, domain, 32) * 16777619) % 4294967296;
  }
  var i = 0;
  while i < size {
    h = (bxor_local(h, gb(data, off + i), 32) * 16777619) % 4294967296;
    i = i + 1;
  }
  return h;
}

fn probes_local(data: &Vec[UInt8], off: Int, size: Int, nbits: Int, nhashes: Int) -> Vec[Int] {
  var out = Vec[Int].new();
  let h1 = fnv_local(data, off, size, 1);
  var h2 = fnv_local(data, off, size, 2);
  if h2 == 0 { h2 = 1; }
  if h2 == 4294967295 { h2 = 1; }
  var i = 0;
  while i < nhashes {
    out.push((h1 + i * h2) % nbits);
    i = i + 1;
  }
  return out;
}

// Build a bit array of ceil(nbits/8) bytes from a list of bit indices.
fn bloom_build(nbits: Int, indices: &Vec[Int]) -> Vec[UInt8] {
  let size = ceil8_local(nbits);
  var out = Vec[UInt8].new();
  var bi = 0;
  while bi < size {
    var val = 0;
    var j = 0;
    while j < indices.len() {
      let idx: Int = indices[j];
      if idx / 8 == bi {
        let p = pow2_local(idx % 8);
        if (val / p) % 2 != 1 {
          val = val + p;
        }
      }
      j = j + 1;
    }
    out.push(val as UInt8);
    bi = bi + 1;
  }
  return out;
}

// --------------------------------------------------
//  Fixture builders
// --------------------------------------------------

// 20-byte value log header; `expires` must fit a positive Int.
fn vlog_header_bytes(klen: Int, vlen: Int, expires: Int, meta: Int, umeta: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  push_le32(&mut out, klen);
  push_le32(&mut out, vlen);
  push_le64(&mut out, expires);
  out.push(meta as UInt8);
  out.push(umeta as UInt8);
  out.push(0 as UInt8);
  out.push(0 as UInt8);
  return out;
}

// 20-byte value log header with the raw expiry pattern 0x8000000000000000
// (bit 63 set: a negative Int on the module side).
fn vlog_header_hi(klen: Int, vlen: Int, meta: Int, umeta: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  push_le32(&mut out, klen);
  push_le32(&mut out, vlen);
  push_le64(&mut out, 0);
  out.push(meta as UInt8);
  out.push(umeta as UInt8);
  out.push(0 as UInt8);
  out.push(0 as UInt8);
  return set_at(&out, 15, 128);
}

// Three value log entries:
//   0: "user1" -> "value-one",  expires 1700000000, meta DELETE, umeta 7
//   1: "user2" -> "",           expires 0,           meta VP|TXN, umeta 0
//   2: "user3" -> "v3",         expires bit63 raw,   meta BIT_TXN|MERGE, umeta 200
// Entry offsets 0, 34, 59; total 86.
fn vlog_buf() -> Vec[UInt8] {
  var b = Vec[UInt8].new();
  append_bytes(&mut b, &vlog_header_bytes(5, 9, 1700000000, BADGER_META_DELETE, 7));
  append_bytes(&mut b, &text("user1"));
  append_bytes(&mut b, &text("value-one"));
  append_bytes(&mut b, &vlog_header_bytes(5, 0, 0, 6, 0));
  append_bytes(&mut b, &text("user2"));
  append_bytes(&mut b, &vlog_header_hi(5, 2, 48, 200));
  append_bytes(&mut b, &text("user3"));
  append_bytes(&mut b, &text("v3"));
  return b;
}

// 16-byte SST header.
fn sst_header_bytes(block_size: Int, ctype: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  push_le32(&mut out, BADGER_SST_MAGIC);
  push_le32(&mut out, BADGER_SST_VERSION);
  push_le32(&mut out, block_size);
  out.push(ctype as UInt8);
  out.push(0 as UInt8);
  out.push(0 as UInt8);
  out.push(0 as UInt8);
  return out;
}

// Prefix-compressed data block body (46 bytes):
//   shared 0 "apple"  -> "red"
//   shared 2 "ricot"  -> "orange"      (reconstructs "apricot")
//   shared 0 "banana" -> "yellow"
//   shared 0 "cat"    -> ""
// Entry offsets 0, 11, 25, 40.
fn sst_block_body() -> Vec[UInt8] {
  var b = Vec[UInt8].new();
  push_varint(&mut b, 0); push_varint(&mut b, 5); push_varint(&mut b, 3);
  append_bytes(&mut b, &text("apple"));
  append_bytes(&mut b, &text("red"));
  push_varint(&mut b, 2); push_varint(&mut b, 5); push_varint(&mut b, 6);
  append_bytes(&mut b, &text("ricot"));
  append_bytes(&mut b, &text("orange"));
  push_varint(&mut b, 0); push_varint(&mut b, 6); push_varint(&mut b, 6);
  append_bytes(&mut b, &text("banana"));
  append_bytes(&mut b, &text("yellow"));
  push_varint(&mut b, 0); push_varint(&mut b, 3); push_varint(&mut b, 0);
  append_bytes(&mut b, &text("cat"));
  return b;
}

// Two-entry block index body: apple -> (16, 50), banana -> (66, 60).
// entries_end 47, crc at 47, size 51.
fn index_buf_2() -> Vec[UInt8] {
  var body = Vec[UInt8].new();
  push_le32(&mut body, 2);
  push_le64(&mut body, 16);
  push_le32(&mut body, 50);
  push_le32(&mut body, 5);
  append_bytes(&mut body, &text("apple"));
  push_le64(&mut body, 66);
  push_le32(&mut body, 60);
  push_le32(&mut body, 6);
  append_bytes(&mut body, &text("banana"));
  return with_crc(&body);
}

// Bloom block with the given bit count/hash count and bit array; crc covers
// the 8 header bytes plus the bit array.
fn bloom_buf(nbits: Int, nhashes: Int, bits: &Vec[UInt8]) -> Vec[UInt8] {
  var body = Vec[UInt8].new();
  push_le32(&mut body, nbits);
  push_le32(&mut body, nhashes);
  append_bytes(&mut body, bits);
  return with_crc(&body);
}

// 16-byte table footer with a correct checksum over the handle bytes.
fn footer_bytes(ioff: Int, isize: Int) -> Vec[UInt8] {
  var body = Vec[UInt8].new();
  push_le64(&mut body, ioff);
  push_le32(&mut body, isize);
  return with_crc(&body);
}

// 20-byte manifest header (creation "unused" when 0).
fn manifest_header_bytes(creation: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  push_le32(&mut out, BADGER_MANIFEST_MAGIC);
  push_le32(&mut out, BADGER_MANIFEST_VERSION);
  push_le64(&mut out, creation);
  push_le32(&mut out, 0);
  return out;
}

// 40-byte manifest file-list entry.
fn manifest_entry_bytes(id: Int, checksum: Int, size: Int, flags: Int, minv: Int, maxv: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  push_le64(&mut out, id);
  push_le32(&mut out, checksum);
  push_le64(&mut out, size);
  push_le32(&mut out, flags);
  push_le64(&mut out, minv);
  push_le64(&mut out, maxv);
  return out;
}

// Three-file manifest list (4 + 3*40 + 4 = 128 bytes):
//   file 1, crc 2864434397, size 4096, KEY_RANGE, versions 10..20
//   file 2, crc 1,          size 8192, DELETED,   versions 0..0
//   file 3, crc 2,          size 512,  3,         versions 30..40
fn manifest_files_buf() -> Vec[UInt8] {
  var body = Vec[UInt8].new();
  push_le32(&mut body, 3);
  append_bytes(&mut body, &manifest_entry_bytes(1, 2864434397, 4096, BADGER_TABLE_FLAG_KEY_RANGE, 10, 20));
  append_bytes(&mut body, &manifest_entry_bytes(2, 1, 8192, BADGER_TABLE_FLAG_DELETED, 0, 0));
  append_bytes(&mut body, &manifest_entry_bytes(3, 2, 512, BADGER_TABLE_FLAG_KNOWN, 30, 40));
  return with_crc(&body);
}

// One-entry manifest list with a caller-chosen flags value and correct crc.
fn manifest_one_file(id: Int, flags: Int) -> Vec[UInt8] {
  var body = Vec[UInt8].new();
  push_le32(&mut body, 1);
  append_bytes(&mut body, &manifest_entry_bytes(id, 0, 100, flags, 1, 2));
  return with_crc(&body);
}

// --------------------------------------------------
//  t1: constants
// --------------------------------------------------

fn t1() -> TestResult {
  let name = "constants: sizes, caps, magic values, flag bits";
  var ok = true;
  if BADGER_VLOG_HEADER_SIZE != 20 { ok = false; }
  if BADGER_VLOG_ENTRY_CAP != 1048576 { ok = false; }
  if BADGER_META_DELETE != 1 { ok = false; }
  if BADGER_META_VALUE_POINTER != 2 { ok = false; }
  if BADGER_META_TRANSACTION != 4 { ok = false; }
  if BADGER_META_FIN_TXN != 8 { ok = false; }
  if BADGER_META_BIT_TXN != 16 { ok = false; }
  if BADGER_META_MERGE_ENTRY != 32 { ok = false; }
  if BADGER_META_ALL != 63 { ok = false; }
  if BADGER_KEY_TAG_SIZE != 8 { ok = false; }
  if BADGER_SST_MAGIC != 1380402242 { ok = false; }
  if BADGER_SST_VERSION != 1 { ok = false; }
  if BADGER_SST_HEADER_SIZE != 16 { ok = false; }
  if BADGER_SST_BLOCK_TRAILER_SIZE != 4 { ok = false; }
  if BADGER_SST_FOOTER_SIZE != 16 { ok = false; }
  if BADGER_BLOOM_MAX_HASHES != 64 { ok = false; }
  if BADGER_MANIFEST_MAGIC != 1296516162 { ok = false; }
  if BADGER_MANIFEST_VERSION != 1 { ok = false; }
  if BADGER_MANIFEST_HEADER_SIZE != 20 { ok = false; }
  if BADGER_MANIFEST_ENTRY_SIZE != 40 { ok = false; }
  if BADGER_TABLE_FLAG_DELETED != 1 { ok = false; }
  if BADGER_TABLE_FLAG_KEY_RANGE != 2 { ok = false; }
  if BADGER_TABLE_FLAG_KNOWN != 3 { ok = false; }
  if !str_eq(badger_version(), "0.1.0") { ok = false; }
  if !str_eq(BADGER_MODULE_VERSION, "0.1.0") { ok = false; }
  let magic_bytes = text("BDGR");
  if !badger_sst_magic_ok(&magic_bytes, 0) { ok = false; }
  let mgmt_bytes = text("BDGM");
  if badger_sst_magic_ok(&mgmt_bytes, 0) { ok = false; }
  return assert(ok, name);
}

// --------------------------------------------------
//  t2: CRC32C known-answer vectors
// --------------------------------------------------

fn t2() -> TestResult {
  let name = "crc32c: known-answer vectors, empty, ranges, local cross-check";
  var ok = true;
  if badger_crc32c(&zeros(0), 0, 0) != 0 { ok = false; }
  let kat = text("123456789");
  if badger_crc32c(&kat, 0, 9) != 3808858755 { ok = false; }
  let z32 = zeros(32);
  if badger_crc32c(&z32, 0, 32) != 2324772522 { ok = false; }
  var seq = Vec[UInt8].new();
  var i = 0;
  while i < 32 {
    seq.push(i as UInt8);
    i = i + 1;
  }
  if badger_crc32c(&seq, 0, 32) != 1188919630 { ok = false; }
  var ff = Vec[UInt8].new();
  i = 0;
  while i < 32 {
    ff.push(255 as UInt8);
    i = i + 1;
  }
  if badger_crc32c(&ff, 0, 32) != 1655221059 { ok = false; }
  var big = Vec[UInt8].new();
  i = 0;
  while i < 256 {
    big.push(i as UInt8);
    i = i + 1;
  }
  if badger_crc32c(&big, 0, 256) != crc_local(&big, 0, 256) { ok = false; }
  if badger_crc32c(&big, 7, 249) != crc_local(&big, 7, 249) { ok = false; }
  if badger_crc32c(&big, 250, 10) != -1 { ok = false; }
  if badger_crc32c(&big, -1, 1) != -1 { ok = false; }
  if badger_crc32c(&big, 0, -1) != -1 { ok = false; }
  return assert(ok, name);
}

// --------------------------------------------------
//  t3: value log header field matrix
// --------------------------------------------------

fn t3() -> TestResult {
  let name = "vlog header: field matrix, caps, reserved bytes, truncation";
  var ok = true;
  let v = vlog_buf();
  let h0 = badger_parse_vlog_header(&v, 0);
  if !h0.is_ok { ok = false; } else {
    let h = h0.value;
    if h.key_len != 5 { ok = false; }
    if h.val_len != 9 { ok = false; }
    if h.expires_at != 1700000000 { ok = false; }
    if h.meta != 1 { ok = false; }
    if h.user_meta != 7 { ok = false; }
    if badger_vlog_entry_total(&h) != 34 { ok = false; }
  }
  let h1 = badger_parse_vlog_header(&v, 34);
  if !h1.is_ok { ok = false; } else {
    let h = h1.value;
    if h.key_len != 5 { ok = false; }
    if h.val_len != 0 { ok = false; }
    if h.expires_at != 0 { ok = false; }
    if h.meta != 6 { ok = false; }
    if h.user_meta != 0 { ok = false; }
    if badger_vlog_entry_total(&h) != 25 { ok = false; }
  }
  let h2 = badger_parse_vlog_header(&v, 59);
  if !h2.is_ok { ok = false; } else {
    let h = h2.value;
    if h.key_len != 5 { ok = false; }
    if h.val_len != 2 { ok = false; }
    if h.expires_at != (0 - 9223372036854775807 - 1) { ok = false; }
    if h.meta != 48 { ok = false; }
    if h.user_meta != 200 { ok = false; }
    if badger_vlog_entry_total(&h) != 27 { ok = false; }
  }
  if !err_vh_is(badger_parse_vlog_header(&v, -1), "badger: vlog header out of bounds at 0") { ok = false; }
  let short = slice_of(&v, 0, 19);
  if !err_vh_is(badger_parse_vlog_header(&short, 0), "badger: vlog header truncated at 0") { ok = false; }
  let reserved = set_at(&v, 18, 5);
  if !err_vh_is(badger_parse_vlog_header(&reserved, 0), "badger: vlog header reserved bytes nonzero at 18") { ok = false; }
  let kcap = vlog_header_bytes(2097152, 0, 0, 0, 0);
  if !err_vh_is(badger_parse_vlog_header(&kcap, 0), "badger: vlog key length exceeds cap at 0") { ok = false; }
  let vcap = vlog_header_bytes(0, 2097152, 0, 0, 0);
  if !err_vh_is(badger_parse_vlog_header(&vcap, 0), "badger: vlog value length exceeds cap at 4") { ok = false; }
  return assert(ok, name);
}

// --------------------------------------------------
//  t4: value log multi-entry walk
// --------------------------------------------------

fn t4() -> TestResult {
  let name = "vlog walk: spans, expanded vectors, consumed counts, empty walk";
  var ok = true;
  let v = vlog_buf();
  if v.len() != 86 { ok = false; }
  let wr = badger_vlog_walk(&v, 0, 86, 10);
  if !wr.is_ok { ok = false; } else {
    let w = wr.value;
    if badger_vlog_count(&w) != 3 { ok = false; }
    if w.total_bytes != 86 { ok = false; }
    if !int_is(badger_vlog_field(&w, 0, BADGER_VLOG_FIELD_OFFSET), 0) { ok = false; }
    if !int_is(badger_vlog_field(&w, 1, BADGER_VLOG_FIELD_OFFSET), 34) { ok = false; }
    if !int_is(badger_vlog_field(&w, 2, BADGER_VLOG_FIELD_OFFSET), 59) { ok = false; }
    if !int_is(badger_vlog_field(&w, 0, BADGER_VLOG_FIELD_KEY_OFFSET), 20) { ok = false; }
    if !int_is(badger_vlog_field(&w, 1, BADGER_VLOG_FIELD_KEY_OFFSET), 54) { ok = false; }
    if !int_is(badger_vlog_field(&w, 2, BADGER_VLOG_FIELD_KEY_OFFSET), 79) { ok = false; }
    if !int_is(badger_vlog_field(&w, 0, BADGER_VLOG_FIELD_KEY_SIZE), 5) { ok = false; }
    if !int_is(badger_vlog_field(&w, 0, BADGER_VLOG_FIELD_VALUE_OFFSET), 25) { ok = false; }
    if !int_is(badger_vlog_field(&w, 1, BADGER_VLOG_FIELD_VALUE_OFFSET), 59) { ok = false; }
    if !int_is(badger_vlog_field(&w, 2, BADGER_VLOG_FIELD_VALUE_OFFSET), 84) { ok = false; }
    if !int_is(badger_vlog_field(&w, 0, BADGER_VLOG_FIELD_VALUE_SIZE), 9) { ok = false; }
    if !int_is(badger_vlog_field(&w, 1, BADGER_VLOG_FIELD_VALUE_SIZE), 0) { ok = false; }
    if !int_is(badger_vlog_field(&w, 2, BADGER_VLOG_FIELD_VALUE_SIZE), 2) { ok = false; }
    if !int_is(badger_vlog_field(&w, 0, BADGER_VLOG_FIELD_META), 1) { ok = false; }
    if !int_is(badger_vlog_field(&w, 1, BADGER_VLOG_FIELD_META), 6) { ok = false; }
    if !int_is(badger_vlog_field(&w, 2, BADGER_VLOG_FIELD_META), 48) { ok = false; }
    if !int_is(badger_vlog_field(&w, 0, BADGER_VLOG_FIELD_USER_META), 7) { ok = false; }
    if !int_is(badger_vlog_field(&w, 2, BADGER_VLOG_FIELD_USER_META), 200) { ok = false; }
    if !int_is(badger_vlog_field(&w, 0, BADGER_VLOG_FIELD_EXPIRES_AT), 1700000000) { ok = false; }
    if !int_is(badger_vlog_field(&w, 2, BADGER_VLOG_FIELD_EXPIRES_AT), (0 - 9223372036854775807 - 1)) { ok = false; }
    if !int_is(badger_vlog_field(&w, 0, BADGER_VLOG_FIELD_COUNT), 3) { ok = false; }
    if !err_int_is(badger_vlog_field(&w, 9, BADGER_VLOG_FIELD_OFFSET), "badger: vlog field index out of range at 9") { ok = false; }
    if !err_int_is(badger_vlog_field(&w, -1, BADGER_VLOG_FIELD_OFFSET), "badger: vlog field index out of range at -1") { ok = false; }
    let wk0 = badger_vlog_key_bytes(&v, &w, 0);
    let wk2 = badger_vlog_key_bytes(&v, &w, 2);
    let wv0 = badger_vlog_value_bytes(&v, &w, 0);
    let wv2 = badger_vlog_value_bytes(&v, &w, 2);
    if !bytes_eq(&wk0, &text("user1")) { ok = false; }
    if !bytes_eq(&wk2, &text("user3")) { ok = false; }
    if !bytes_eq(&wv0, &text("value-one")) { ok = false; }
    if badger_vlog_value_bytes(&v, &w, 1).len() != 0 { ok = false; }
    if !bytes_eq(&wv2, &text("v3")) { ok = false; }
    if badger_vlog_key_bytes(&v, &w, 7).len() != 0 { ok = false; }
  }
  let empty = badger_vlog_walk(&v, 86, 86, 5);
  if !empty.is_ok { ok = false; } else {
    let w = empty.value;
    if badger_vlog_count(&w) != 0 { ok = false; }
    if w.total_bytes != 0 { ok = false; }
  }
  return assert(ok, name);
}

// --------------------------------------------------
//  t5: value log walk bounds and caps
// --------------------------------------------------

fn t5() -> TestResult {
  let name = "vlog walk: trailing bytes, truncation, caps, max entries, limits";
  var ok = true;
  let v = vlog_buf();
  if !err_vwalk_is(badger_vlog_walk(&v, -1, 86, 5), "badger: vlog walk start out of bounds at 0") { ok = false; }
  if !err_vwalk_is(badger_vlog_walk(&v, 0, 87, 5), "badger: vlog walk limit out of bounds at 87") { ok = false; }
  if !err_vwalk_is(badger_vlog_walk(&v, 10, 5, 5), "badger: vlog walk limit before start at 5") { ok = false; }
  if !err_vwalk_is(badger_vlog_walk(&v, 0, 86, 0), "badger: vlog walk max entries must be positive at 0") { ok = false; }
  if !err_vwalk_is(badger_vlog_walk(&v, 0, 86, 2), "badger: vlog walk exceeds max entries at 59") { ok = false; }
  var extra = Vec[UInt8].new();
  append_bytes(&mut extra, &v);
  push_zeros(&mut extra, 10);
  if !err_vwalk_is(badger_vlog_walk(&extra, 0, 96, 5), "badger: vlog walk trailing bytes at 86") { ok = false; }
  let trunc_entry = vlog_header_bytes(5, 100, 0, 0, 0);
  var tb = Vec[UInt8].new();
  append_bytes(&mut tb, &trunc_entry);
  append_bytes(&mut tb, &text("user1"));
  if !err_vwalk_is(badger_vlog_walk(&tb, 0, tb.len(), 5), "badger: vlog entry truncated at 0") { ok = false; }
  let big = vlog_header_bytes(524288, 524288, 0, 0, 0);
  if !err_vwalk_is(badger_vlog_walk(&big, 0, big.len(), 5), "badger: vlog entry exceeds cap at 0") { ok = false; }
  if !err_vwalk_is(badger_vlog_walk(&v, 80, 86, 5), "badger: vlog walk trailing bytes at 80") { ok = false; }
  return assert(ok, name);
}

// --------------------------------------------------
//  t6: meta bit table
// --------------------------------------------------

fn t6() -> TestResult {
  let name = "meta bits: all six names, combinations, membership, known mask";
  var ok = true;
  if !str_eq(badger_meta_bit_name(BADGER_META_DELETE), "DELETE") { ok = false; }
  if !str_eq(badger_meta_bit_name(BADGER_META_VALUE_POINTER), "VALUE_POINTER") { ok = false; }
  if !str_eq(badger_meta_bit_name(BADGER_META_TRANSACTION), "TRANSACTION") { ok = false; }
  if !str_eq(badger_meta_bit_name(BADGER_META_FIN_TXN), "FIN_TXN") { ok = false; }
  if !str_eq(badger_meta_bit_name(BADGER_META_BIT_TXN), "BIT_TXN") { ok = false; }
  if !str_eq(badger_meta_bit_name(BADGER_META_MERGE_ENTRY), "MERGE_ENTRY") { ok = false; }
  if !str_eq(badger_meta_bit_name(64), "") { ok = false; }
  if !str_eq(badger_meta_bit_name(0), "") { ok = false; }
  if !str_eq(badger_meta_names(0), "") { ok = false; }
  if !str_eq(badger_meta_names(1), "DELETE") { ok = false; }
  if !str_eq(badger_meta_names(3), "DELETE|VALUE_POINTER") { ok = false; }
  if !str_eq(badger_meta_names(6), "VALUE_POINTER|TRANSACTION") { ok = false; }
  if !str_eq(badger_meta_names(48), "BIT_TXN|MERGE_ENTRY") { ok = false; }
  if !str_eq(badger_meta_names(63), "DELETE|VALUE_POINTER|TRANSACTION|FIN_TXN|BIT_TXN|MERGE_ENTRY") { ok = false; }
  if badger_meta_has(6, BADGER_META_VALUE_POINTER) == false { ok = false; }
  if badger_meta_has(6, BADGER_META_TRANSACTION) == false { ok = false; }
  if badger_meta_has(6, BADGER_META_DELETE) { ok = false; }
  if badger_meta_has(6, 0) { ok = false; }
  if badger_meta_known(0) == false { ok = false; }
  if badger_meta_known(63) == false { ok = false; }
  if badger_meta_known(64) { ok = false; }
  if badger_meta_known(-1) { ok = false; }
  return assert(ok, name);
}

// --------------------------------------------------
//  t7: versioned keys
// --------------------------------------------------

fn t7() -> TestResult {
  let name = "key: version/delete accessors, empty user key, tag bounds";
  var ok = true;
  var b1 = text("hello");
  append_bytes(&mut b1, &le64(84));
  let r1 = badger_key_decode(&b1, 0, 13);
  if !r1.is_ok { ok = false; } else {
    let k = r1.value;
    if k.user_offset != 0 { ok = false; }
    if badger_key_user_size(&k) != 5 { ok = false; }
    if badger_key_version(&k) != 42 { ok = false; }
    if badger_key_deleted(&k) { ok = false; }
    if badger_key_tagged(&k) != 84 { ok = false; }
    if !bytes_eq(&badger_key_user_bytes(&b1, &k), &text("hello")) { ok = false; }
  }
  var b2 = text("k");
  append_bytes(&mut b2, &le64(87));
  let r2 = badger_key_decode(&b2, 0, 9);
  if !r2.is_ok { ok = false; } else {
    let k = r2.value;
    if badger_key_version(&k) != 43 { ok = false; }
    if badger_key_deleted(&k) == false { ok = false; }
    if badger_key_tagged(&k) != 87 { ok = false; }
    if badger_key_user_size(&k) != 1 { ok = false; }
  }
  let b3 = le64(2);
  let r3 = badger_key_decode(&b3, 0, 8);
  if !r3.is_ok { ok = false; } else {
    let k = r3.value;
    if badger_key_user_size(&k) != 0 { ok = false; }
    if badger_key_version(&k) != 1 { ok = false; }
    if badger_key_deleted(&k) { ok = false; }
  }
  let b4 = text("k");
  if !err_key_is(badger_key_decode(&b4, 0, 7), "badger: key shorter than version tag at 0") { ok = false; }
  if !err_key_is(badger_key_decode(&b1, 0, 14), "badger: key span out of bounds at 0") { ok = false; }
  if !err_key_is(badger_key_decode(&b1, -1, 13), "badger: key span out of bounds at 0") { ok = false; }
  var b5 = text("hello");
  var hi = Vec[UInt8].new();
  push_zeros(&mut hi, 8);
  let hi2 = set_at(&hi, 7, 128);
  append_bytes(&mut b5, &hi2);
  if !err_key_is(badger_key_decode(&b5, 0, 13), "badger: key version exceeds Int range at 5") { ok = false; }
  return assert(ok, name);
}

// --------------------------------------------------
//  t8: SST header
// --------------------------------------------------

fn t8() -> TestResult {
  let name = "sst header: magic, version, block size, checksum type, reserved";
  var ok = true;
  let hdr = sst_header_bytes(4096, BADGER_SST_CHECKSUM_CRC32C);
  let r = badger_parse_sst_header(&hdr);
  if !r.is_ok { ok = false; } else {
    let h = r.value;
    if h.magic != BADGER_SST_MAGIC { ok = false; }
    if h.version != 1 { ok = false; }
    if h.block_size != 4096 { ok = false; }
    if h.checksum_type != 1 { ok = false; }
  }
  if !badger_sst_magic_ok(&hdr, 0) { ok = false; }
  if badger_sst_magic_ok(&hdr, 13) { ok = false; }
  if !err_ssth_is(badger_parse_sst_header(&zeros(15)), "badger: sst header truncated at 0") { ok = false; }
  let bad_magic = set_at(&hdr, 0, 0);
  if !err_ssth_is(badger_parse_sst_header(&bad_magic), "badger: sst bad magic at 0") { ok = false; }
  let bad_ver = set_at(&hdr, 4, 2);
  if !err_ssth_is(badger_parse_sst_header(&bad_ver), "badger: sst unsupported version at 4") { ok = false; }
  let bad_size = sst_header_bytes(0, BADGER_SST_CHECKSUM_CRC32C);
  if !err_ssth_is(badger_parse_sst_header(&bad_size), "badger: sst block size out of range at 8") { ok = false; }
  let big_size = sst_header_bytes(8388609, BADGER_SST_CHECKSUM_CRC32C);
  if !err_ssth_is(badger_parse_sst_header(&big_size), "badger: sst block size out of range at 8") { ok = false; }
  let bad_ct = sst_header_bytes(4096, 2);
  if !err_ssth_is(badger_parse_sst_header(&bad_ct), "badger: sst unknown checksum type at 12") { ok = false; }
  let bad_res = set_at(&hdr, 13, 1);
  if !err_ssth_is(badger_parse_sst_header(&bad_res), "badger: sst reserved bytes nonzero at 13") { ok = false; }
  let none_ct = sst_header_bytes(1024, BADGER_SST_CHECKSUM_NONE);
  let none_r = badger_parse_sst_header(&none_ct);
  if !none_r.is_ok { ok = false; } else {
    let nh = none_r.value;
    if nh.checksum_type != BADGER_SST_CHECKSUM_NONE { ok = false; }
  }
  return assert(ok, name);
}

// --------------------------------------------------
//  t9: SST data-block entries
// --------------------------------------------------

fn t9() -> TestResult {
  let name = "sst block: prefix-compressed entries, keys, values, offsets";
  var ok = true;
  let body = sst_block_body();
  if body.len() != 46 { ok = false; }
  let r = badger_sst_block_entries(&body, 46);
  if !r.is_ok { ok = false; } else {
    let e = r.value;
    if badger_sst_block_count(&e) != 4 { ok = false; }
    let bk0 = badger_sst_block_key(&e, 0);
    let bk1 = badger_sst_block_key(&e, 1);
    let bk2 = badger_sst_block_key(&e, 2);
    let bk3 = badger_sst_block_key(&e, 3);
    if !bytes_eq(&bk0, &text("apple")) { ok = false; }
    if !bytes_eq(&bk1, &text("apricot")) { ok = false; }
    if !bytes_eq(&bk2, &text("banana")) { ok = false; }
    if !bytes_eq(&bk3, &text("cat")) { ok = false; }
    if badger_sst_block_shared(&e, 0) != 0 { ok = false; }
    if badger_sst_block_shared(&e, 1) != 2 { ok = false; }
    if badger_sst_block_shared(&e, 2) != 0 { ok = false; }
    if badger_sst_block_shared(&e, 9) != -1 { ok = false; }
    if badger_sst_block_entry_offset(&e, 0) != 0 { ok = false; }
    if badger_sst_block_entry_offset(&e, 1) != 11 { ok = false; }
    if badger_sst_block_entry_offset(&e, 2) != 25 { ok = false; }
    if badger_sst_block_entry_offset(&e, 3) != 40 { ok = false; }
    let sv0 = badger_sst_block_value(&body, &e, 0);
    let sv1 = badger_sst_block_value(&body, &e, 1);
    let sv2 = badger_sst_block_value(&body, &e, 2);
    if !bytes_eq(&sv0, &text("red")) { ok = false; }
    if !bytes_eq(&sv1, &text("orange")) { ok = false; }
    if !bytes_eq(&sv2, &text("yellow")) { ok = false; }
    if badger_sst_block_value(&body, &e, 3).len() != 0 { ok = false; }
    if badger_sst_block_key(&e, -1).len() != 0 { ok = false; }
  }
  let empty_prev = Vec[UInt8].new();
  let e0 = badger_parse_sst_block_entry(&body, 0, 46, &empty_prev);
  if !e0.is_ok { ok = false; } else {
    let en = e0.value;
    if en.shared_len != 0 { ok = false; }
    if en.key_len != 5 { ok = false; }
    if en.val_len != 3 { ok = false; }
    if en.key_offset != 3 { ok = false; }
    if en.value_offset != 8 { ok = false; }
    if en.entry_bytes != 11 { ok = false; }
    if !bytes_eq(&en.key, &text("apple")) { ok = false; }
  }
  let e1 = badger_parse_sst_block_entry(&body, 11, 46, &text("apple"));
  if !e1.is_ok { ok = false; } else {
    let en = e1.value;
    if en.shared_len != 2 { ok = false; }
    if en.entry_bytes != 14 { ok = false; }
    if !bytes_eq(&en.key, &text("apricot")) { ok = false; }
  }
  let empty_block = zeros(0);
  let eb = badger_sst_block_entries(&empty_block, 0);
  if !eb.is_ok { ok = false; } else {
    let e = eb.value;
    if badger_sst_block_count(&e) != 0 { ok = false; }
  }
  return assert(ok, name);
}

// --------------------------------------------------
//  t10: SST block entry errors
// --------------------------------------------------

fn t10() -> TestResult {
  let name = "sst block entry: truncation, overflow, overruns, caps, zero bytes";
  var ok = true;
  let empty_prev = Vec[UInt8].new();
  var tv = Vec[UInt8].new();
  tv.push(128 as UInt8);
  if !err_sse_is(badger_parse_sst_block_entry(&tv, 0, 1, &empty_prev), "badger: sst block entry: truncated at 0") { ok = false; }
  var ovf = Vec[UInt8].new();
  var i = 0;
  while i < 5 {
    ovf.push(255 as UInt8);
    i = i + 1;
  }
  if !err_sse_is(badger_parse_sst_block_entry(&ovf, 0, 5, &empty_prev), "badger: sst block entry: overflow at 0") { ok = false; }
  var sh = Vec[UInt8].new();
  sh.push(1 as UInt8); sh.push(1 as UInt8); sh.push(0 as UInt8); sh.push(97 as UInt8);
  if !err_sse_is(badger_parse_sst_block_entry(&sh, 0, 4, &empty_prev), "badger: sst block entry shared beyond previous key at 0") { ok = false; }
  var ko = Vec[UInt8].new();
  ko.push(0 as UInt8); ko.push(5 as UInt8); ko.push(0 as UInt8); ko.push(97 as UInt8); ko.push(98 as UInt8);
  if !err_sse_is(badger_parse_sst_block_entry(&ko, 0, 5, &empty_prev), "badger: sst block entry key overrun at 0") { ok = false; }
  var vo = Vec[UInt8].new();
  vo.push(0 as UInt8); vo.push(1 as UInt8); vo.push(4 as UInt8); vo.push(97 as UInt8); vo.push(120 as UInt8); vo.push(121 as UInt8);
  if !err_sse_is(badger_parse_sst_block_entry(&vo, 0, 6, &empty_prev), "badger: sst block entry value overrun at 0") { ok = false; }
  var kcap = Vec[UInt8].new();
  kcap.push(0 as UInt8); kcap.push(129 as UInt8); kcap.push(128 as UInt8); kcap.push(64 as UInt8); kcap.push(0 as UInt8);
  if !err_sse_is(badger_parse_sst_block_entry(&kcap, 0, 5, &empty_prev), "badger: sst block entry key length exceeds cap at 0") { ok = false; }
  var z = Vec[UInt8].new();
  z.push(0 as UInt8); z.push(0 as UInt8); z.push(0 as UInt8);
  let zr = badger_sst_block_entries(&z, 3);
  if !zr.is_ok { ok = false; } else {
    let e = zr.value;
    if badger_sst_block_count(&e) != 1 { ok = false; }
    if badger_sst_block_key(&e, 0).len() != 0 { ok = false; }
    if badger_sst_block_value(&z, &e, 0).len() != 0 { ok = false; }
    if badger_sst_block_entry_offset(&e, 0) != 0 { ok = false; }
  }
  if !err_sse_list_is(badger_sst_block_entries(&z, 4), "badger: sst block limit out of bounds at 0") { ok = false; }
  if !err_sse_list_is(badger_sst_block_entries(&z, -1), "badger: sst block limit out of bounds at 0") { ok = false; }
  let one = badger_parse_sst_block_entry(&z, 0, 3, &empty_prev);
  if !one.is_ok { ok = false; } else {
    let en = one.value;
    if en.entry_bytes != 3 { ok = false; }
    if en.key.len() != 0 { ok = false; }
    if en.val_len != 0 { ok = false; }
  }
  return assert(ok, name);
}

// --------------------------------------------------
//  t11: SST block trailer
// --------------------------------------------------

fn t11() -> TestResult {
  let name = "sst block trailer: crc parse and verification, truncation";
  var ok = true;
  let body = sst_block_body();
  let want = crc_local(&body, 0, 46);
  let tr = le32(want);
  let r = badger_parse_sst_block_trailer(&tr, 0);
  if !r.is_ok { ok = false; } else {
    let t = r.value;
    if t.crc != want { ok = false; }
  }
  if badger_sst_block_trailer_ok(&body, 0, 46, want) == false { ok = false; }
  if badger_sst_block_trailer_ok(&body, 0, 46, want + 1) { ok = false; }
  if badger_sst_block_trailer_ok(&body, 0, 46, -1) { ok = false; }
  if badger_sst_block_trailer_ok(&body, 0, 90, want) { ok = false; }
  if !err_trailer_is(badger_parse_sst_block_trailer(&zeros(3), 0), "badger: sst block trailer truncated at 0") { ok = false; }
  if !err_trailer_is(badger_parse_sst_block_trailer(&tr, 10), "badger: sst block trailer truncated at 10") { ok = false; }
  if !err_trailer_is(badger_parse_sst_block_trailer(&tr, -1), "badger: sst block trailer truncated at 0") { ok = false; }
  return assert(ok, name);
}

// --------------------------------------------------
//  t12: bloom parse and hash pair
// --------------------------------------------------

fn t12() -> TestResult {
  let name = "bloom: hash known answers, parse, checksum, bounds, ceil size";
  var ok = true;
  if !int_is(badger_fnv1a32(&text(""), 0, 0), 2166136261) { ok = false; }
  if !int_is(badger_fnv1a32(&text("a"), 0, 1), 3826002220) { ok = false; }
  if !int_is(badger_fnv1a32(&text("foobar"), 0, 6), 3214735720) { ok = false; }
  let hp = badger_bloom_hash_pair(&text("apple"), 0, 5);
  if !hp.is_ok { ok = false; } else {
    let p = hp.value;
    if p.h1 != 4230784436 { ok = false; }
    if p.h2 != 1993265727 { ok = false; }
  }
  let hp2 = badger_bloom_hash_pair(&text("key"), 0, 3);
  if !hp2.is_ok { ok = false; } else {
    let p = hp2.value;
    if p.h1 != 1387155387 { ok = false; }
    if p.h2 != 156451820 { ok = false; }
  }
  if !err_bhp_is(badger_bloom_hash_pair(&text("key"), 0, 4), "badger: hash span out of bounds at 0") { ok = false; }
  if !err_int_is(badger_fnv1a32(&text("key"), -1, 3), "badger: hash span out of bounds at 0") { ok = false; }
  var indices = Vec[Int].new();
  append_ints(&mut indices, &probes_local(&text("apple"), 0, 5, 64, 3));
  append_ints(&mut indices, &probes_local(&text("key"), 0, 3, 64, 3));
  append_ints(&mut indices, &probes_local(&text("banana"), 0, 6, 64, 3));
  let bits = bloom_build(64, &indices);
  if bits.len() != 8 { ok = false; }
  let bl = bloom_buf(64, 3, &bits);
  if bl.len() != 20 { ok = false; }
  let r = badger_bloom_parse(&bl, 0, 20);
  if !r.is_ok { ok = false; } else {
    let b = r.value;
    if b.nbits != 64 { ok = false; }
    if b.nhashes != 3 { ok = false; }
    if b.bits_offset != 8 { ok = false; }
    if b.bits_size != 8 { ok = false; }
    if b.crc != crc_local(&bl, 0, 16) { ok = false; }
  }
  let bl9 = bloom_buf(9, 1, &zeros(2));
  let r9 = badger_bloom_parse(&bl9, 0, bl9.len());
  if !r9.is_ok { ok = false; } else {
    let b = r9.value;
    if b.nbits != 9 { ok = false; }
    if b.bits_size != 2 { ok = false; }
  }
  let z = bloom_buf(64, 3, &zeros(8));
  let rz = badger_bloom_parse(&z, 0, z.len());
  if !rz.is_ok { ok = false; }
  let zero_bits = zeros(8);
  if !err_bloom_is(badger_bloom_parse(&zero_bits, 0, 8), "badger: bloom nbits zero at 0") { ok = false; }
  var cap_buf = Vec[UInt8].new();
  push_le32(&mut cap_buf, 8388609);
  push_le32(&mut cap_buf, 3);
  if !err_bloom_is(badger_bloom_parse(&cap_buf, 0, 8), "badger: bloom bit count exceeds cap at 0") { ok = false; }
  var nohash = Vec[UInt8].new();
  push_le32(&mut nohash, 64);
  push_le32(&mut nohash, 0);
  if !err_bloom_is(badger_bloom_parse(&nohash, 0, 8), "badger: bloom hash count out of range at 4") { ok = false; }
  var manyhash = Vec[UInt8].new();
  push_le32(&mut manyhash, 64);
  push_le32(&mut manyhash, 65);
  if !err_bloom_is(badger_bloom_parse(&manyhash, 0, 8), "badger: bloom hash count out of range at 4") { ok = false; }
  if !err_bloom_is(badger_bloom_parse(&bl, 0, 15), "badger: bloom bit array overrun at 0") { ok = false; }
  if !err_bloom_is(badger_bloom_parse(&bl, 0, 19), "badger: bloom length mismatch at 0") { ok = false; }
  if !err_bloom_is(badger_bloom_parse(&bl, -1, 20), "badger: bloom truncated at 0") { ok = false; }
  if !err_bloom_is(badger_bloom_parse(&bl, 0, 7), "badger: bloom truncated at 0") { ok = false; }
  let orig_bit = gb(&bl, 9);
  let corrupt = set_at(&bl, 9, orig_bit + 1);
  if !err_bloom_is(badger_bloom_parse(&corrupt, 0, 20), "badger: bloom checksum mismatch at 16") { ok = false; }
  return assert(ok, name);
}

// --------------------------------------------------
//  t13: bloom membership
// --------------------------------------------------

fn t13() -> TestResult {
  let name = "bloom membership: inserted keys present, absent key rejected";
  var ok = true;
  var indices = Vec[Int].new();
  append_ints(&mut indices, &probes_local(&text("apple"), 0, 5, 64, 3));
  append_ints(&mut indices, &probes_local(&text("key"), 0, 3, 64, 3));
  append_ints(&mut indices, &probes_local(&text("banana"), 0, 6, 64, 3));
  let bits = bloom_build(64, &indices);
  let bl = bloom_buf(64, 3, &bits);
  let apple = text("apple");
  let key = text("key");
  let banana = text("banana");
  let zzz = text("zzz");
  let r = badger_bloom_parse(&bl, 0, 20);
  if !r.is_ok { ok = false; } else {
    let b = r.value;
    if !bool_is(badger_bloom_has(&bl, &apple, &b, 0, 5), true) { ok = false; }
    if !bool_is(badger_bloom_has(&bl, &key, &b, 0, 3), true) { ok = false; }
    if !bool_is(badger_bloom_has(&bl, &banana, &b, 0, 6), true) { ok = false; }
    if !bool_is(badger_bloom_has(&bl, &zzz, &b, 0, 3), false) { ok = false; }
    if !err_bool_is(badger_bloom_has(&bl, &apple, &b, 0, 6), "badger: hash span out of bounds at 0") { ok = false; }
  }
  let z = bloom_buf(64, 3, &zeros(8));
  let rz = badger_bloom_parse(&z, 0, z.len());
  if !rz.is_ok { ok = false; } else {
    let b = rz.value;
    if !bool_is(badger_bloom_has(&z, &apple, &b, 0, 5), false) { ok = false; }
  }
  return assert(ok, name);
}

// --------------------------------------------------
//  t14: block index
// --------------------------------------------------

fn t14() -> TestResult {
  let name = "sst index: entries, accessors, first-key lookup, checksum, caps";
  var ok = true;
  let ix = index_buf_2();
  if ix.len() != 51 { ok = false; }
  let r = badger_sst_index_parse(&ix, 0, 51);
  if !r.is_ok { ok = false; } else {
    let x = r.value;
    if badger_sst_index_count(&x) != 2 { ok = false; }
    if badger_sst_index_offset(&x, 0) != 16 { ok = false; }
    if badger_sst_index_offset(&x, 1) != 66 { ok = false; }
    if badger_sst_index_size(&x, 0) != 50 { ok = false; }
    if badger_sst_index_size(&x, 1) != 60 { ok = false; }
    if badger_sst_index_offset(&x, 9) != -1 { ok = false; }
    if badger_sst_index_size(&x, -1) != -1 { ok = false; }
    let kx0 = badger_sst_index_key(&x, 0);
    let kx1 = badger_sst_index_key(&x, 1);
    if !bytes_eq(&kx0, &text("apple")) { ok = false; }
    if !bytes_eq(&kx1, &text("banana")) { ok = false; }
    if badger_sst_index_key(&x, 5).len() != 0 { ok = false; }
    if x.entries_end != 47 { ok = false; }
    if x.crc != crc_local(&ix, 0, 47) { ok = false; }
    let target_apple = text("apple");
    let target_apricot = text("apricot");
    let target_banana = text("banana");
    let target_aaa = text("aaa");
    let target_zzz = text("zzz");
    if badger_sst_index_lookup(&target_apple, &x, 0, 5) != 0 { ok = false; }
    if badger_sst_index_lookup(&target_apricot, &x, 0, 7) != 1 { ok = false; }
    if badger_sst_index_lookup(&target_banana, &x, 0, 6) != 1 { ok = false; }
    if badger_sst_index_lookup(&target_aaa, &x, 0, 3) != 0 { ok = false; }
    if badger_sst_index_lookup(&target_zzz, &x, 0, 3) != -1 { ok = false; }
    if badger_sst_index_lookup(&target_apple, &x, -1, 5) != -1 { ok = false; }
    if badger_sst_index_lookup(&target_apple, &x, 0, 6) != -1 { ok = false; }
    if target_apricot.len() != 7 { ok = false; }
    if target_banana.len() != 6 { ok = false; }
    if target_aaa.len() != 3 { ok = false; }
    if target_zzz.len() != 3 { ok = false; }
  }
  if !err_idx_is(badger_sst_index_parse(&ix, 0, 7), "badger: sst index truncated at 0") { ok = false; }
  if !err_idx_is(badger_sst_index_parse(&ix, -1, 51), "badger: sst index truncated at 0") { ok = false; }
  if !err_idx_is(badger_sst_index_parse(&ix, 0, 61), "badger: sst index truncated at 0") { ok = false; }
  var cap = Vec[UInt8].new();
  push_le32(&mut cap, 100001);
  push_le32(&mut cap, 0);
  if !err_idx_is(badger_sst_index_parse(&cap, 0, 8), "badger: sst index count exceeds cap at 0") { ok = false; }
  var short_e = Vec[UInt8].new();
  push_le32(&mut short_e, 1);
  push_zeros(&mut short_e, 15);
  if !err_idx_is(badger_sst_index_parse(&short_e, 0, 19), "badger: sst index entry overruns at 4") { ok = false; }
  var hi_off = Vec[UInt8].new();
  push_le32(&mut hi_off, 1);
  push_zeros(&mut hi_off, 8);
  let hi_off2 = set_at(&hi_off, 11, 128);
  var hi_off3 = Vec[UInt8].new();
  append_bytes(&mut hi_off3, &hi_off2);
  push_zeros(&mut hi_off3, 8);
  push_le32(&mut hi_off3, 0);
  if !err_idx_is(badger_sst_index_parse(&hi_off3, 0, hi_off3.len()), "badger: sst index block offset exceeds Int range at 4") { ok = false; }
  var kcap = Vec[UInt8].new();
  push_le32(&mut kcap, 1);
  push_zeros(&mut kcap, 8);
  push_le32(&mut kcap, 0);
  push_le32(&mut kcap, 1048577);
  if !err_idx_is(badger_sst_index_parse(&kcap, 0, 20), "badger: sst index key length exceeds cap at 4") { ok = false; }
  let bad_crc = set_at(&ix, 47, 0);
  if !err_idx_is(badger_sst_index_parse(&bad_crc, 0, 51), "badger: sst index checksum mismatch at 47") { ok = false; }
  var longer = Vec[UInt8].new();
  append_bytes(&mut longer, &ix);
  longer.push(0 as UInt8);
  if !err_idx_is(badger_sst_index_parse(&longer, 0, 52), "badger: sst index length mismatch at 0") { ok = false; }
  var empty_body = Vec[UInt8].new();
  push_le32(&mut empty_body, 0);
  let empty_ix = with_crc(&empty_body);
  let re = badger_sst_index_parse(&empty_ix, 0, 8);
  if !re.is_ok { ok = false; } else {
    let x = re.value;
    if x.count != 0 { ok = false; }
    if x.entries_end != 4 { ok = false; }
  }
  return assert(ok, name);
}

// --------------------------------------------------
//  t15: table footer
// --------------------------------------------------

fn t15() -> TestResult {
  let name = "sst footer: handle bounds, checksum, footer_ok, truncation";
  var ok = true;
  // A 40-byte file: 16 header bytes + 8 index bytes + the 16-byte footer.
  var file = Vec[UInt8].new();
  push_zeros(&mut file, 16);
  push_zeros(&mut file, 8);
  append_bytes(&mut file, &footer_bytes(16, 8));
  let r = badger_sst_footer_parse(&file);
  if !r.is_ok { ok = false; } else {
    let f = r.value;
    if f.index_offset != 16 { ok = false; }
    if f.index_size != 8 { ok = false; }
    if f.crc != crc_local(&file, 24, 12) { ok = false; }
    if badger_sst_footer_ok(&f, 40) == false { ok = false; }
    if badger_sst_footer_ok(&f, 39) { ok = false; }
    if badger_sst_footer_ok(&f, 20) { ok = false; }
  }
  if !err_ft_is(badger_sst_footer_parse(&zeros(15)), "badger: sst footer truncated at 0") { ok = false; }
  let f1 = footer_bytes(16, 8);
  let orig_crc_byte = gb(&f1, 12);
  let bad_crc = set_at(&f1, 12, orig_crc_byte + 1);
  if !err_ft_is(badger_sst_footer_parse(&bad_crc), "badger: sst footer checksum mismatch at 0") { ok = false; }
  let low = footer_bytes(8, 8);
  if !err_ft_is(badger_sst_footer_parse(&low), "badger: sst footer index handle out of range at 0") { ok = false; }
  let big = footer_bytes(16, 100);
  if !err_ft_is(badger_sst_footer_parse(&big), "badger: sst footer index handle out of range at 0") { ok = false; }
  var hi = Vec[UInt8].new();
  push_zeros(&mut hi, 8);
  let hi2 = set_at(&hi, 7, 128);
  var hi_body = Vec[UInt8].new();
  append_bytes(&mut hi_body, &hi2);
  push_le32(&mut hi_body, 8);
  let hi3 = with_crc(&hi_body);
  if !err_ft_is(badger_sst_footer_parse(&hi3), "badger: sst footer index offset exceeds Int range at 0") { ok = false; }
  return assert(ok, name);
}

// --------------------------------------------------
//  t16: manifest header
// --------------------------------------------------

fn t16() -> TestResult {
  let name = "manifest header: magic, version, creation, reserved, truncation";
  var ok = true;
  let mh = manifest_header_bytes(1700000000);
  let r = badger_manifest_header_parse(&mh);
  if !r.is_ok { ok = false; } else {
    let h = r.value;
    if h.magic != BADGER_MANIFEST_MAGIC { ok = false; }
    if h.version != 1 { ok = false; }
    if h.creation != 1700000000 { ok = false; }
    if h.reserved != 0 { ok = false; }
  }
  let unused = manifest_header_bytes(0);
  let ru = badger_manifest_header_parse(&unused);
  if !ru.is_ok { ok = false; } else {
    let h = ru.value;
    if h.creation != 0 { ok = false; }
  }
  if !err_mh_is(badger_manifest_header_parse(&zeros(19)), "badger: manifest header truncated at 0") { ok = false; }
  let bad_magic = set_at(&mh, 0, 0);
  if !err_mh_is(badger_manifest_header_parse(&bad_magic), "badger: manifest bad magic at 0") { ok = false; }
  let bad_ver = set_at(&mh, 4, 2);
  if !err_mh_is(badger_manifest_header_parse(&bad_ver), "badger: manifest unsupported version at 4") { ok = false; }
  let hi_creation = set_at(&mh, 15, 128);
  if !err_mh_is(badger_manifest_header_parse(&hi_creation), "badger: manifest creation exceeds Int range at 8") { ok = false; }
  let bad_res = set_at(&mh, 16, 1);
  if !err_mh_is(badger_manifest_header_parse(&bad_res), "badger: manifest reserved nonzero at 16") { ok = false; }
  return assert(ok, name);
}

// --------------------------------------------------
//  t17: manifest file list
// --------------------------------------------------

fn t17() -> TestResult {
  let name = "manifest files: entries, selectors, flags, consumed counts, crc";
  var ok = true;
  let mf = manifest_files_buf();
  if mf.len() != 128 { ok = false; }
  let r = badger_manifest_files_parse(&mf, 0);
  if !r.is_ok { ok = false; } else {
    let f = r.value;
    if badger_manifest_file_count(&f) != 3 { ok = false; }
    if f.total_bytes != 128 { ok = false; }
    if f.crc != crc_local(&mf, 0, 124) { ok = false; }
    if !int_is(badger_manifest_file_field(&f, 0, BADGER_FILE_FIELD_ID), 1) { ok = false; }
    if !int_is(badger_manifest_file_field(&f, 1, BADGER_FILE_FIELD_ID), 2) { ok = false; }
    if !int_is(badger_manifest_file_field(&f, 2, BADGER_FILE_FIELD_ID), 3) { ok = false; }
    if !int_is(badger_manifest_file_field(&f, 0, BADGER_FILE_FIELD_CHECKSUM), 2864434397) { ok = false; }
    if !int_is(badger_manifest_file_field(&f, 1, BADGER_FILE_FIELD_CHECKSUM), 1) { ok = false; }
    if !int_is(badger_manifest_file_field(&f, 0, BADGER_FILE_FIELD_SIZE), 4096) { ok = false; }
    if !int_is(badger_manifest_file_field(&f, 1, BADGER_FILE_FIELD_SIZE), 8192) { ok = false; }
    if !int_is(badger_manifest_file_field(&f, 2, BADGER_FILE_FIELD_SIZE), 512) { ok = false; }
    if !int_is(badger_manifest_file_field(&f, 0, BADGER_FILE_FIELD_FLAGS), 2) { ok = false; }
    if !int_is(badger_manifest_file_field(&f, 1, BADGER_FILE_FIELD_FLAGS), 1) { ok = false; }
    if !int_is(badger_manifest_file_field(&f, 2, BADGER_FILE_FIELD_FLAGS), 3) { ok = false; }
    if !int_is(badger_manifest_file_field(&f, 0, BADGER_FILE_FIELD_MIN_VERSION), 10) { ok = false; }
    if !int_is(badger_manifest_file_field(&f, 0, BADGER_FILE_FIELD_MAX_VERSION), 20) { ok = false; }
    if !int_is(badger_manifest_file_field(&f, 2, BADGER_FILE_FIELD_MIN_VERSION), 30) { ok = false; }
    if !int_is(badger_manifest_file_field(&f, 2, BADGER_FILE_FIELD_MAX_VERSION), 40) { ok = false; }
    if !int_is(badger_manifest_file_field(&f, 0, BADGER_FILE_FIELD_OFFSET), 4) { ok = false; }
    if !int_is(badger_manifest_file_field(&f, 2, BADGER_FILE_FIELD_OFFSET), 84) { ok = false; }
    if !int_is(badger_manifest_file_field(&f, 0, BADGER_FILE_FIELD_COUNT), 3) { ok = false; }
    if !err_int_is(badger_manifest_file_field(&f, 9, BADGER_FILE_FIELD_ID), "badger: manifest file index out of range at 9") { ok = false; }
    if !err_int_is(badger_manifest_file_field(&f, -1, BADGER_FILE_FIELD_ID), "badger: manifest file index out of range at -1") { ok = false; }
  }
  let e0 = badger_manifest_entry_parse(&mf, 4);
  if !e0.is_ok { ok = false; } else {
    let e = e0.value;
    if e.offset != 4 { ok = false; }
    if e.consumed != 40 { ok = false; }
    if e.id != 1 { ok = false; }
    if e.min_version != 10 { ok = false; }
    if e.max_version != 20 { ok = false; }
    if badger_manifest_entry_deleted(&e) { ok = false; }
    if badger_manifest_entry_has_range(&e) == false { ok = false; }
  }
  let e1 = badger_manifest_entry_parse(&mf, 44);
  if !e1.is_ok { ok = false; } else {
    let e = e1.value;
    if badger_manifest_entry_deleted(&e) == false { ok = false; }
    if badger_manifest_entry_has_range(&e) { ok = false; }
  }
  let e2 = badger_manifest_entry_parse(&mf, 84);
  if !e2.is_ok { ok = false; } else {
    let e = e2.value;
    if badger_manifest_entry_deleted(&e) == false { ok = false; }
    if badger_manifest_entry_has_range(&e) == false { ok = false; }
  }
  if !str_eq(badger_table_flag_name(0), "") { ok = false; }
  if !str_eq(badger_table_flag_name(1), "DELETED") { ok = false; }
  if !str_eq(badger_table_flag_name(2), "KEY_RANGE") { ok = false; }
  if !str_eq(badger_table_flag_name(3), "DELETED|KEY_RANGE") { ok = false; }
  if !str_eq(badger_table_flag_name(4), "") { ok = false; }
  return assert(ok, name);
}

// --------------------------------------------------
//  t18: manifest errors
// --------------------------------------------------

fn t18() -> TestResult {
  let name = "manifest errors: truncation, caps, unknown flags, version bounds";
  var ok = true;
  let mf = manifest_files_buf();
  if !err_mf_is(badger_manifest_files_parse(&zeros(3), 0), "badger: manifest file list truncated at 0") { ok = false; }
  var cap = Vec[UInt8].new();
  push_le32(&mut cap, 100001);
  push_zeros(&mut cap, 8);
  if !err_mf_is(badger_manifest_files_parse(&cap, 0), "badger: manifest file count exceeds cap at 0") { ok = false; }
  var one_entry = Vec[UInt8].new();
  push_le32(&mut one_entry, 2);
  append_bytes(&mut one_entry, &manifest_entry_bytes(1, 0, 1, 0, 0, 0));
  if !err_mf_is(badger_manifest_files_parse(&one_entry, 0), "badger: manifest file list truncated at 0") { ok = false; }
  let bad_crc = set_at(&mf, 12, 99);
  if !err_mf_is(badger_manifest_files_parse(&bad_crc, 0), "badger: manifest file list checksum mismatch at 124") { ok = false; }
  let unknown = manifest_one_file(7, 4);
  if !err_mf_is(badger_manifest_files_parse(&unknown, 0), "badger: manifest entry unknown flags for file 7 at 24") { ok = false; }
  if !err_me_is(badger_manifest_entry_parse(&mf, 124), "badger: manifest entry truncated at 124") { ok = false; }
  var id_hi = manifest_entry_bytes(0, 0, 10, 0, 0, 0);
  let id_hi2 = set_at(&id_hi, 7, 128);
  var id_body = Vec[UInt8].new();
  push_le32(&mut id_body, 1);
  append_bytes(&mut id_body, &id_hi2);
  let id_buf = with_crc(&id_body);
  if !err_mf_is(badger_manifest_files_parse(&id_buf, 0), "badger: manifest entry id exceeds Int range at 4") { ok = false; }
  var size_hi = manifest_entry_bytes(5, 0, 0, 0, 0, 0);
  let size_hi2 = set_at(&size_hi, 19, 128);
  var size_body = Vec[UInt8].new();
  push_le32(&mut size_body, 1);
  append_bytes(&mut size_body, &size_hi2);
  let size_buf = with_crc(&size_body);
  if !err_mf_is(badger_manifest_files_parse(&size_buf, 0), "badger: manifest entry size exceeds Int range at 16") { ok = false; }
  var min_hi = manifest_entry_bytes(5, 0, 10, 0, 0, 0);
  let min_hi2 = set_at(&min_hi, 31, 128);
  var min_body = Vec[UInt8].new();
  push_le32(&mut min_body, 1);
  append_bytes(&mut min_body, &min_hi2);
  let min_buf = with_crc(&min_body);
  if !err_mf_is(badger_manifest_files_parse(&min_buf, 0), "badger: manifest entry min version exceeds Int range at 28") { ok = false; }
  var max_hi = manifest_entry_bytes(5, 0, 10, 0, 0, 0);
  let max_hi2 = set_at(&max_hi, 39, 128);
  var max_body = Vec[UInt8].new();
  push_le32(&mut max_body, 1);
  append_bytes(&mut max_body, &max_hi2);
  let max_buf = with_crc(&max_body);
  if !err_mf_is(badger_manifest_files_parse(&max_buf, 0), "badger: manifest entry max version exceeds Int range at 36") { ok = false; }
  return assert(ok, name);
}

// --------------------------------------------------
//  t19: value log + versioned key walk (composite)
// --------------------------------------------------

fn t19() -> TestResult {
  let name = "vlog + keys: versioned keys through a three-entry walk";
  var ok = true;
  var v = Vec[UInt8].new();
  append_bytes(&mut v, &vlog_header_bytes(13, 3, 0, BADGER_META_DELETE, 0));
  var k1 = text("user1");
  append_bytes(&mut k1, &le64(200));
  append_bytes(&mut v, &k1);
  append_bytes(&mut v, &text("aaa"));
  append_bytes(&mut v, &vlog_header_bytes(13, 3, 0, BADGER_META_VALUE_POINTER, 9));
  var k2 = text("user2");
  append_bytes(&mut k2, &le64(401));
  append_bytes(&mut v, &k2);
  append_bytes(&mut v, &text("bbb"));
  append_bytes(&mut v, &vlog_header_bytes(13, 3, 0, 6, 0));
  var k3 = text("user3");
  append_bytes(&mut k3, &le64(600));
  append_bytes(&mut v, &k3);
  append_bytes(&mut v, &text("ccc"));
  let wr = badger_vlog_walk(&v, 0, v.len(), 10);
  if !wr.is_ok { ok = false; } else {
    let w = wr.value;
    if badger_vlog_count(&w) != 3 { ok = false; }
    if w.total_bytes != 108 { ok = false; }
    var i = 0;
    while i < 3 {
      let ko = badger_vlog_field(&w, i, BADGER_VLOG_FIELD_KEY_OFFSET);
      let ks = badger_vlog_field(&w, i, BADGER_VLOG_FIELD_KEY_SIZE);
      if !ko.is_ok { ok = false; } else {
        if !ks.is_ok { ok = false; } else {
          let koff: Int = ko.value;
          let ksz: Int = ks.value;
          let kr = badger_key_decode(&v, koff, ksz);
          if !kr.is_ok { ok = false; } else {
            let k = kr.value;
            let want_version = 100 + i * 100;
            if badger_key_version(&k) != want_version { ok = false; }
            if badger_key_user_size(&k) != 5 { ok = false; }
            if i == 1 {
              if badger_key_deleted(&k) == false { ok = false; }
            } else {
              if badger_key_deleted(&k) { ok = false; }
            }
          }
        }
      }
      i = i + 1;
    }
    if !int_is(badger_vlog_field(&w, 0, BADGER_VLOG_FIELD_META), 1) { ok = false; }
    if !int_is(badger_vlog_field(&w, 1, BADGER_VLOG_FIELD_META), 2) { ok = false; }
    if !int_is(badger_vlog_field(&w, 2, BADGER_VLOG_FIELD_META), 6) { ok = false; }
    if !str_eq(badger_meta_names(1), "DELETE") { ok = false; }
    if !str_eq(badger_meta_names(6), "VALUE_POINTER|TRANSACTION") { ok = false; }
  }
  return assert(ok, name);
}

// --------------------------------------------------
//  t20: composite SST file end to end
// --------------------------------------------------

fn t20() -> TestResult {
  let name = "composite SST: header + block + trailer + index + bloom + footer";
  var ok = true;
  // Bloom bits for "apple" over 64 bits with 3 hashes.
  var indices = Vec[Int].new();
  append_ints(&mut indices, &probes_local(&text("apple"), 0, 5, 64, 3));
  let bits = bloom_build(64, &indices);
  // Block body and its trailer CRC are computed before `file` is assembled.
  let body = sst_block_body();
  let trailer = le32(crc_local(&body, 0, 46));
  // Index body: count 1, block (16,46), key "apple"; crc appended by with_crc.
  var ix_body = Vec[UInt8].new();
  push_le32(&mut ix_body, 1);
  push_le64(&mut ix_body, 16);
  push_le32(&mut ix_body, 46);
  push_le32(&mut ix_body, 5);
  append_bytes(&mut ix_body, &text("apple"));
  let ix = with_crc(&ix_body);
  // Assemble: header 0..16, block 16..62, trailer 62..66, index 66..95,
  // bloom 95..115, footer 115..131 (index handle 66/29).
  var file = Vec[UInt8].new();
  append_bytes(&mut file, &sst_header_bytes(4096, BADGER_SST_CHECKSUM_CRC32C));
  append_bytes(&mut file, &body);
  append_bytes(&mut file, &trailer);
  append_bytes(&mut file, &ix);
  append_bytes(&mut file, &bloom_buf(64, 3, &bits));
  append_bytes(&mut file, &footer_bytes(66, 29));
  if file.len() != 131 { ok = false; }
  let hr = badger_parse_sst_header(&file);
  if !hr.is_ok { ok = false; } else {
    let h = hr.value;
    if h.block_size != 4096 { ok = false; }
  }
  let br = badger_sst_block_entries(&body, 46);
  if !br.is_ok { ok = false; } else {
    let e = br.value;
    if badger_sst_block_count(&e) != 4 { ok = false; }
    let bk = badger_sst_block_key(&e, 1);
    if !bytes_eq(&bk, &text("apricot")) { ok = false; }
  }
  let tr = slice_of(&file, 62, 4);
  let trr = badger_parse_sst_block_trailer(&tr, 0);
  if !trr.is_ok { ok = false; } else {
    let t = trr.value;
    if !badger_sst_block_trailer_ok(&file, 16, 46, t.crc) { ok = false; }
  }
  let apple = text("apple");
  let banana = text("banana");
  let aaa = text("aaa");
  let ixr = badger_sst_index_parse(&file, 66, 29);
  if !ixr.is_ok { ok = false; } else {
    let x = ixr.value;
    if badger_sst_index_count(&x) != 1 { ok = false; }
    if badger_sst_index_offset(&x, 0) != 16 { ok = false; }
    if badger_sst_index_size(&x, 0) != 46 { ok = false; }
    let xk = badger_sst_index_key(&x, 0);
    if !bytes_eq(&xk, &text("apple")) { ok = false; }
    if badger_sst_index_lookup(&apple, &x, 0, 5) != 0 { ok = false; }
    if badger_sst_index_lookup(&banana, &x, 0, 6) != -1 { ok = false; }
    if badger_sst_index_lookup(&aaa, &x, 0, 3) != 0 { ok = false; }
  }
  let blr = badger_bloom_parse(&file, 95, 20);
  if !blr.is_ok { ok = false; } else {
    let b = blr.value;
    if !bool_is(badger_bloom_has(&file, &apple, &b, 0, 5), true) { ok = false; }
    if !bool_is(badger_bloom_has(&file, &banana, &b, 0, 6), false) { ok = false; }
  }
  let fr = badger_sst_footer_parse(&file);
  if !fr.is_ok { ok = false; } else {
    let f = fr.value;
    if f.index_offset != 66 { ok = false; }
    if f.index_size != 29 { ok = false; }
    if badger_sst_footer_ok(&f, 131) == false { ok = false; }
    if badger_sst_footer_ok(&f, 95) { ok = false; }
  }
  return assert(ok, name);
}

// --------------------------------------------------
//  main
// --------------------------------------------------

fn main() -> Int {
  io.println("=== xiom.badger conformance tests ===");
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
  if failed == 0 {
    io.println("xiom.badger: all tests passed");
  } else {
    io.println("xiom.badger: tests failed");
  }
  return failed;
}
