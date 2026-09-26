// XIOM -- xiom.sparse conformance tests (24 checks)
// Port task: prove the pure-XIOM xiom.sparse codec against its documented
// Android sparse image layout, accessors and error catalog.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Covers the documented API with a 92-byte hand-built fixture holding one
// chunk of each type (raw 2 blocks, fill 3 blocks, don't-care 1 block,
// crc32), with pinned header fields, chunk types/blocks/spans/fill values,
// running block offsets and expanded size; exact body slices; parse ->
// rebuild and build -> parse round-trips; a canonical all-raw build at block
// size 4096; an empty header-only image; truncation at every structural
// boundary; trailing bytes; bad magic/version/header sizes/block sizes;
// unknown types and nonzero reserved fields; bad chunk totals, bad chunk
// bodies, chunk count and block count mismatches; out-of-range accessors;
// and the builder error catalog including atomic validation.
//
// Str values are never compared with `==` (BUG 17 discipline: `==` on a Str
// read from a Vec lowers to a pointer comparison); every string comparison
// goes through xiom.string.compare.str_compare.

module sparse_tests
use xiom.io; use xiom.test;
use xiom.sparse;
use xiom.string;
use xiom.string.compare;
use xiom.encoding.hex;

// --------------------------------------------------
//  Generic test helpers
// --------------------------------------------------

// Expected bytes for a hex string ("" on malformed input; the caller then
// fails on the byte comparison).
fn hb(hexstr: Str) -> Vec[UInt8] {
  let r = hex.hex_decode(hexstr);
  if r.is_ok {
    let v: Vec[UInt8] = r.value;
    return v;
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

fn err_is(r: Result[SparseImage, Str], want: Str) -> Bool {
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

// Prefix of a byte vector, used to build truncated source buffers.
fn prefix(v: Vec[UInt8], n: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < n && i < v.len() {
    out.push(v[i]);
    i = i + 1;
  }
  return out;
}

fn append_byte(v: Vec[UInt8], b: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < v.len() {
    out.push(v[i]);
    i = i + 1;
  }
  out.push(b as UInt8);
  return out;
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

// Copy of `src` with the little-endian u16 at `off` replaced by `val`
// (0 <= val <= 65535; test values only).
fn patch_u16le(src: Vec[UInt8], off: Int, val: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < src.len() {
    v.push(src[i]);
    i = i + 1;
  }
  var x = val;
  var k = 0;
  while k < 2 {
    v[off + k] = (x % 256) as UInt8;
    x = x / 256;
    k = k + 1;
  }
  return v;
}

// Copy of `src` with the little-endian u32 at `off` replaced by `val`
// (0 <= val <= 4294967295; test values only).
fn patch_u32le(src: Vec[UInt8], off: Int, val: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < src.len() {
    v.push(src[i]);
    i = i + 1;
  }
  var x = val;
  var k = 0;
  while k < 4 {
    v[off + k] = (x % 256) as UInt8;
    x = x / 256;
    k = k + 1;
  }
  return v;
}

fn err_prefix_is(base: Vec[UInt8], n: Int, want: Str) -> Bool {
  let cut = prefix(base, n);
  return err_is(sparse_parse(&cut), want);
}

fn err_u16_is(base: Vec[UInt8], off: Int, val: Int, want: Str) -> Bool {
  let p = patch_u16le(base, off, val);
  return err_is(sparse_parse(&p), want);
}

fn err_u32_is(base: Vec[UInt8], off: Int, val: Int, want: Str) -> Bool {
  let p = patch_u32le(base, off, val);
  return err_is(sparse_parse(&p), want);
}

fn err_appended_is(base: Vec[UInt8], b: Int, want: Str) -> Bool {
  let p = append_byte(base, b);
  return err_is(sparse_parse(&p), want);
}

// Copy of chunk `i`'s body out of `data` (callers use it after a successful
// parse with a checked index; an out-of-bounds span yields an empty vector).
fn body_of(data: &Vec[UInt8], t: &SparseImage, i: Int) -> Vec[UInt8] {
  let off: Int = sparse_chunk_data_offset(t, i);
  let len: Int = sparse_chunk_data_length(t, i);
  var out = Vec[UInt8].new();
  if off < 0 { return out; }
  if len < 0 { return out; }
  if off + len > data.len() { return out; }
  var k = 0;
  while k < len {
    out.push(data[off + k]);
    k = k + 1;
  }
  return out;
}

fn vi1(a: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  return v;
}

fn vi2(a: Int, b: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  v.push(b);
  return v;
}

fn vb1(a: Vec[UInt8]) -> Vec[Vec[UInt8]] {
  var v = Vec[Vec[UInt8]].new();
  v.push(a);
  return v;
}

fn vb2(a: Vec[UInt8], b: Vec[UInt8]) -> Vec[Vec[UInt8]] {
  var v = Vec[Vec[UInt8]].new();
  v.push(a);
  v.push(b);
  return v;
}

fn empty_bytes() -> Vec[UInt8] {
  return Vec[UInt8].new();
}

// --------------------------------------------------
//  Fixtures
// --------------------------------------------------

// 92-byte image: 28-byte header (block size 4, 6 blocks, 4 chunks, checksum
// 0x44332211), then raw(2 blocks, body deadbeef01020304), fill(3 blocks,
// value 0xAABBCCDD), don't-care(1 block, no body) and crc32(4-byte value
// 0x55667788) chunks. Body offsets: 40, 60, 76, 88.
fn fixture() -> Vec[UInt8] {
  return hb("3aff26ed010000001c000c0004000000060000000400000011223344c1ca00000200000014000000deadbeef01020304c2ca00000300000010000000ddccbbaac3ca0000010000000c000000c4ca0000040000001000000088776655");
}

// 28-byte header-only image: no chunks, no blocks.
fn empty_image() -> Vec[UInt8] {
  return hb("3aff26ed010000001c000c0004000000000000000000000000000000");
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  let data = fixture();
  let r = sparse_parse(&data);
  if !r.is_ok { return assert(false, "fixture must parse"); }
  let t: SparseImage = r.value;
  var ok = sparse_major_version(&t) == 1;
  if sparse_minor_version(&t) != 0 { ok = false; }
  if !str_eq(sparse_version(&t), "1.0") { ok = false; }
  if sparse_file_header_size(&t) != 28 { ok = false; }
  if sparse_chunk_header_size(&t) != 12 { ok = false; }
  if sparse_block_size(&t) != 4 { ok = false; }
  if sparse_total_blocks(&t) != 6 { ok = false; }
  if sparse_total_chunks(&t) != 4 { ok = false; }
  if sparse_image_checksum(&t) != 1144201745 { ok = false; }
  if sparse_chunk_count(&t) != 4 { ok = false; }
  if sparse_expanded_size(&t) != 24 { ok = false; }
  if data.len() != 92 { ok = false; }
  return assert(ok, "fixture header: version 1.0, block size 4, 6 blocks, 4 chunks, checksum 0x44332211");
}

fn t2() -> TestResult {
  let data = fixture();
  let r = sparse_parse(&data);
  if !r.is_ok { return assert(false, "fixture must parse"); }
  let t: SparseImage = r.value;
  var ok = sparse_chunk_type(&t, 0) == 51905;
  if sparse_chunk_type(&t, 1) != 51906 { ok = false; }
  if sparse_chunk_type(&t, 2) != 51907 { ok = false; }
  if sparse_chunk_type(&t, 3) != 51908 { ok = false; }
  if sparse_chunk_blocks(&t, 0) != 2 { ok = false; }
  if sparse_chunk_blocks(&t, 1) != 3 { ok = false; }
  if sparse_chunk_blocks(&t, 2) != 1 { ok = false; }
  if sparse_chunk_blocks(&t, 3) != 0 { ok = false; }
  return assert(ok, "raw/fill/don't-care/crc32 types and block counts are pinned (crc32 is 0 blocks)");
}

fn t3() -> TestResult {
  let data = fixture();
  let r = sparse_parse(&data);
  if !r.is_ok { return assert(false, "fixture must parse"); }
  let t: SparseImage = r.value;
  var ok = sparse_chunk_data_offset(&t, 0) == 40;
  if sparse_chunk_data_offset(&t, 1) != 60 { ok = false; }
  if sparse_chunk_data_offset(&t, 2) != 76 { ok = false; }
  if sparse_chunk_data_offset(&t, 3) != 88 { ok = false; }
  if sparse_chunk_data_length(&t, 0) != 8 { ok = false; }
  if sparse_chunk_data_length(&t, 1) != 4 { ok = false; }
  if sparse_chunk_data_length(&t, 2) != 0 { ok = false; }
  if sparse_chunk_data_length(&t, 3) != 4 { ok = false; }
  if sparse_chunk_block_offset(&t, 0) != 0 { ok = false; }
  if sparse_chunk_block_offset(&t, 1) != 2 { ok = false; }
  if sparse_chunk_block_offset(&t, 2) != 5 { ok = false; }
  if sparse_chunk_block_offset(&t, 3) != 6 { ok = false; }
  return assert(ok, "body spans 40/60/76/88 and running block offsets 0/2/5/6 are pinned");
}

fn t4() -> TestResult {
  let data = fixture();
  let r = sparse_parse(&data);
  if !r.is_ok { return assert(false, "fixture must parse"); }
  let t: SparseImage = r.value;
  var ok = bytes_equal(body_of(&data, &t, 0), hb("deadbeef01020304"));
  if !bytes_equal(body_of(&data, &t, 1), hb("ddccbbaa")) { ok = false; }
  if !bytes_equal(body_of(&data, &t, 2), empty_bytes()) { ok = false; }
  if !bytes_equal(body_of(&data, &t, 3), hb("88776655")) { ok = false; }
  if !bytes_equal(prefix(data, 40), hb("3aff26ed010000001c000c0004000000060000000400000011223344c1ca00000200000014000000")) { ok = false; }
  return assert(ok, "bodies slice exactly: raw data, 4-byte fill value, empty don't-care, 4-byte crc32");
}

fn t5() -> TestResult {
  var ok = SPARSE_CHUNK_RAW == 51905;
  if SPARSE_CHUNK_FILL != 51906 { ok = false; }
  if SPARSE_CHUNK_DONT_CARE != 51907 { ok = false; }
  if SPARSE_CHUNK_CRC32 != 51908 { ok = false; }
  if SPARSE_MAGIC != 3978755898 { ok = false; }
  if SPARSE_FILE_HEADER_SIZE != 28 { ok = false; }
  if SPARSE_CHUNK_HEADER_SIZE != 12 { ok = false; }
  return assert(ok, "exported chunk type constants, magic and header sizes match the format");
}

fn t6() -> TestResult {
  let data = fixture();
  let r = sparse_parse(&data);
  if !r.is_ok { return assert(false, "fixture must parse"); }
  let t: SparseImage = r.value;
  var types = Vec[Int].new();
  var blocks = Vec[Int].new();
  var bodies = Vec[Vec[UInt8]].new();
  var i = 0;
  while i < sparse_chunk_count(&t) {
    types.push(sparse_chunk_type(&t, i));
    blocks.push(sparse_chunk_blocks(&t, i));
    let b: Vec[UInt8] = body_of(&data, &t, i);
    bodies.push(b);
    i = i + 1;
  }
  let blk: Int = sparse_block_size(&t);
  let sum: Int = sparse_image_checksum(&t);
  let br = sparse_build(blk, &types, &blocks, &bodies, sum);
  if !br.is_ok { return assert(false, "rebuild must succeed"); }
  let built: Vec[UInt8] = br.value;
  var ok = bytes_equal(built, data);
  if built.len() != 92 { ok = false; }
  return assert(ok, "parse -> rebuild reproduces the original fixture bytes exactly");
}

fn t7() -> TestResult {
  let data = fixture();
  var types = Vec[Int].new();
  types.push(51905);
  types.push(51906);
  types.push(51907);
  types.push(51908);
  var blocks = Vec[Int].new();
  blocks.push(2);
  blocks.push(3);
  blocks.push(1);
  blocks.push(0);
  var bodies = Vec[Vec[UInt8]].new();
  bodies.push(hb("deadbeef01020304"));
  bodies.push(hb("ddccbbaa"));
  bodies.push(empty_bytes());
  bodies.push(hb("88776655"));
  let br = sparse_build(4, &types, &blocks, &bodies, 1144201745);
  if !br.is_ok { return assert(false, "canonical build must succeed"); }
  let built: Vec[UInt8] = br.value;
  var ok = bytes_equal(built, data);
  let pr = sparse_parse(&built);
  if !pr.is_ok { ok = false; } else {
    let t: SparseImage = pr.value;
    if sparse_chunk_count(&t) != 4 { ok = false; }
    if sparse_chunk_data_offset(&t, 3) != 88 { ok = false; }
    if sparse_expanded_size(&t) != 24 { ok = false; }
  }
  return assert(ok, "sparse_build emits the canonical header and matches the hand-built fixture byte-for-byte");
}

fn t8() -> TestResult {
  var types = Vec[Int].new();
  types.push(51905);
  types.push(51905);
  var blocks = Vec[Int].new();
  blocks.push(1);
  blocks.push(2);
  var bodies = Vec[Vec[UInt8]].new();
  bodies.push(repeat_byte(171, 4096));
  bodies.push(repeat_byte(205, 8192));
  let br = sparse_build(4096, &types, &blocks, &bodies, 0);
  if !br.is_ok { return assert(false, "all-raw build must succeed"); }
  let built: Vec[UInt8] = br.value;
  var ok = built.len() == 12340;
  if !bytes_equal(prefix(built, 28), hb("3aff26ed010000001c000c0000100000030000000200000000000000")) { ok = false; }
  let pr = sparse_parse(&built);
  if !pr.is_ok { ok = false; } else {
    let t: SparseImage = pr.value;
    if sparse_block_size(&t) != 4096 { ok = false; }
    if sparse_total_blocks(&t) != 3 { ok = false; }
    if sparse_chunk_count(&t) != 2 { ok = false; }
    if sparse_chunk_blocks(&t, 0) != 1 { ok = false; }
    if sparse_chunk_blocks(&t, 1) != 2 { ok = false; }
    if sparse_chunk_data_offset(&t, 0) != 40 { ok = false; }
    if sparse_chunk_data_offset(&t, 1) != 4148 { ok = false; }
    if sparse_chunk_data_length(&t, 0) != 4096 { ok = false; }
    if sparse_chunk_data_length(&t, 1) != 8192 { ok = false; }
    if sparse_chunk_block_offset(&t, 1) != 1 { ok = false; }
    if sparse_expanded_size(&t) != 12288 { ok = false; }
  }
  return assert(ok, "all-raw 4096-byte-block image: canonical header, 12340 bytes, spans and offsets pinned");
}

fn t9() -> TestResult {
  let data = empty_image();
  let r = sparse_parse(&data);
  if !r.is_ok { return assert(false, "empty image must parse"); }
  let t: SparseImage = r.value;
  var ok = sparse_chunk_count(&t) == 0;
  if sparse_total_chunks(&t) != 0 { ok = false; }
  if sparse_total_blocks(&t) != 0 { ok = false; }
  if sparse_expanded_size(&t) != 0 { ok = false; }
  if sparse_chunk_type(&t, 0) != -1 { ok = false; }
  if !err_appended_is(data, 0, "sparse: trailing bytes") { ok = false; }
  return assert(ok, "a 28-byte header declaring zero chunks parses empty; one extra byte is trailing bytes");
}

fn t10() -> TestResult {
  let base = fixture();
  var ok = err_prefix_is(base, 0, "sparse: truncated header");
  if !err_prefix_is(base, 20, "sparse: truncated header") { ok = false; }
  if !err_prefix_is(base, 27, "sparse: truncated header") { ok = false; }
  if !err_prefix_is(empty_image(), 27, "sparse: truncated header") { ok = false; }
  return assert(ok, "buffers shorter than 28 bytes are truncated header");
}

fn t11() -> TestResult {
  let base = fixture();
  var ok = err_prefix_is(base, 30, "sparse: truncated chunk header");
  if !err_prefix_is(base, 39, "sparse: truncated chunk header") { ok = false; }
  return assert(ok, "a partial 12-byte chunk header is truncated chunk header");
}

fn t12() -> TestResult {
  let base = fixture();
  var ok = err_prefix_is(base, 40, "sparse: chunk overruns buffer");
  if !err_prefix_is(base, 47, "sparse: chunk overruns buffer") { ok = false; }
  if !err_prefix_is(base, 60, "sparse: chunk overruns buffer") { ok = false; }
  if !err_prefix_is(base, 88, "sparse: chunk overruns buffer") { ok = false; }
  if !err_prefix_is(base, 91, "sparse: chunk overruns buffer") { ok = false; }
  return assert(ok, "truncated raw/fill/dont-care/crc32 bodies are chunk overruns buffer");
}

fn t13() -> TestResult {
  let base = fixture();
  var ok = err_prefix_is(base, 28, "sparse: chunk count mismatch");
  if !err_prefix_is(base, 48, "sparse: chunk count mismatch") { ok = false; }
  if !err_prefix_is(base, 64, "sparse: chunk count mismatch") { ok = false; }
  if !err_prefix_is(base, 76, "sparse: chunk count mismatch") { ok = false; }
  return assert(ok, "ending exactly between chunks with fewer chunks than declared is a chunk count mismatch");
}

fn t14() -> TestResult {
  let base = fixture();
  var ok = err_appended_is(base, 0, "sparse: trailing bytes");
  let more = append_byte(append_byte(append_byte(append_byte(base, 1), 2), 3), 4);
  if !err_is(sparse_parse(&more), "sparse: trailing bytes") { ok = false; }
  if !err_u32_is(base, 20, 3, "sparse: trailing bytes") { ok = false; }
  if !err_u32_is(base, 20, 5, "sparse: chunk count mismatch") { ok = false; }
  return assert(ok, "bytes after the last declared chunk are trailing bytes; an inflated count is a mismatch");
}

fn t15() -> TestResult {
  let base = fixture();
  var ok = err_u32_is(base, 0, 0, "sparse: bad magic");
  if !err_u32_is(base, 0, 3735928559, "sparse: bad magic") { ok = false; }
  if !err_u16_is(base, 4, 2, "sparse: unsupported version") { ok = false; }
  if !err_u16_is(base, 6, 1, "sparse: unsupported version") { ok = false; }
  return assert(ok, "wrong magic and versions other than 1.0 are rejected");
}

fn t16() -> TestResult {
  let base = fixture();
  var ok = err_u16_is(base, 8, 24, "sparse: bad file header size");
  if !err_u16_is(base, 8, 0, "sparse: bad file header size") { ok = false; }
  if !err_u16_is(base, 10, 10, "sparse: bad chunk header size") { ok = false; }
  if !err_u16_is(base, 10, 16, "sparse: bad chunk header size") { ok = false; }
  return assert(ok, "file header size 28 and chunk header size 12 are required");
}

fn t17() -> TestResult {
  let base = fixture();
  var ok = err_u32_is(base, 12, 0, "sparse: bad block size");
  if !err_u32_is(base, 12, 6, "sparse: bad block size") { ok = false; }
  if !err_u32_is(base, 12, 2, "sparse: bad block size") { ok = false; }
  if !err_u32_is(base, 12, 4294967295, "sparse: bad block size") { ok = false; }
  return assert(ok, "block size must be nonzero and a multiple of 4");
}

fn t18() -> TestResult {
  let base = fixture();
  var ok = err_u16_is(base, 28, 0, "sparse: unknown chunk type");
  if !err_u16_is(base, 28, 51904, "sparse: unknown chunk type") { ok = false; }
  if !err_u16_is(base, 28, 51909, "sparse: unknown chunk type") { ok = false; }
  if !err_u16_is(base, 30, 1, "sparse: nonzero chunk reserved") { ok = false; }
  if !err_u16_is(base, 78, 1, "sparse: nonzero chunk reserved") { ok = false; }
  if !err_u16_is(base, 50, 2, "sparse: nonzero chunk reserved") { ok = false; }
  return assert(ok, "unknown chunk types and nonzero reserved fields are rejected");
}

fn t19() -> TestResult {
  let base = fixture();
  var ok = err_u32_is(base, 36, 8, "sparse: bad chunk total size");
  if !err_u32_is(base, 36, 11, "sparse: bad chunk total size") { ok = false; }
  if !err_u32_is(base, 36, 0, "sparse: bad chunk total size") { ok = false; }
  return assert(ok, "a chunk total size below the 12-byte header is rejected");
}

fn t20() -> TestResult {
  let base = fixture();
  var ok = err_u32_is(base, 32, 3, "sparse: bad chunk size");
  if !err_u32_is(base, 32, 1, "sparse: bad chunk size") { ok = false; }
  if !err_u32_is(base, 36, 19, "sparse: bad chunk size") { ok = false; }
  if !err_u32_is(base, 56, 15, "sparse: bad chunk size") { ok = false; }
  if !err_u32_is(base, 56, 17, "sparse: bad chunk size") { ok = false; }
  if !err_u32_is(base, 72, 13, "sparse: bad chunk size") { ok = false; }
  if !err_u32_is(base, 80, 0, "sparse: bad chunk size") { ok = false; }
  if !err_u32_is(base, 84, 15, "sparse: bad chunk size") { ok = false; }
  return assert(ok, "body sizes must match the chunk type: raw blocks*block_size, fill/dont/crc32 fixed");
}

fn t21() -> TestResult {
  let base = fixture();
  var ok = err_u32_is(base, 16, 5, "sparse: block count mismatch");
  if !err_u32_is(base, 16, 7, "sparse: block count mismatch") { ok = false; }
  if !err_u32_is(base, 16, 0, "sparse: block count mismatch") { ok = false; }
  return assert(ok, "the summed non-crc32 block count must equal the header total");
}

fn t22() -> TestResult {
  let data = fixture();
  let r = sparse_parse(&data);
  if !r.is_ok { return assert(false, "fixture must parse"); }
  let t: SparseImage = r.value;
  var ok = sparse_chunk_type(&t, -1) == -1;
  if sparse_chunk_type(&t, 4) != -1 { ok = false; }
  if sparse_chunk_type(&t, 100) != -1 { ok = false; }
  if sparse_chunk_blocks(&t, -1) != -1 { ok = false; }
  if sparse_chunk_blocks(&t, 4) != -1 { ok = false; }
  if sparse_chunk_data_offset(&t, 4) != -1 { ok = false; }
  if sparse_chunk_data_length(&t, 4) != -1 { ok = false; }
  if sparse_chunk_fill_value(&t, -1) != -1 { ok = false; }
  if sparse_chunk_fill_value(&t, 4) != -1 { ok = false; }
  if sparse_chunk_block_offset(&t, -1) != -1 { ok = false; }
  if sparse_chunk_block_offset(&t, 4) != -1 { ok = false; }
  if sparse_chunk_fill_value(&t, 1) != 2864434397 { ok = false; }
  if sparse_chunk_fill_value(&t, 0) != -1 { ok = false; }
  if sparse_chunk_fill_value(&t, 3) != -1 { ok = false; }
  return assert(ok, "out-of-range chunk accessors return -1; the fill value is exposed only for fill chunks");
}

fn t23() -> TestResult {
  var empty_i = Vec[Int].new();
  var empty_v = Vec[Vec[UInt8]].new();
  var ok = err_bytes_is(sparse_build(0, &empty_i, &empty_i, &empty_v, 0), "sparse: bad block size");
  if !err_bytes_is(sparse_build(2, &empty_i, &empty_i, &empty_v, 0), "sparse: bad block size") { ok = false; }
  if !err_bytes_is(sparse_build(-4, &empty_i, &empty_i, &empty_v, 0), "sparse: bad block size") { ok = false; }
  if !err_bytes_is(sparse_build(4, &empty_i, &empty_i, &empty_v, -1), "sparse: bad image checksum") { ok = false; }
  if !err_bytes_is(sparse_build(4, &empty_i, &empty_i, &empty_v, 4294967296), "sparse: bad image checksum") { ok = false; }
  var ty_raw = vi1(51905);
  var ty_two = vi2(51905, 51906);
  var blk_one = vi1(1);
  var bodies_empty = vb1(empty_bytes());
  if !err_bytes_is(sparse_build(4, &ty_two, &blk_one, &bodies_empty, 0), "sparse: chunk vector mismatch") { ok = false; }
  if !err_bytes_is(sparse_build(4, &ty_raw, &blk_one, &empty_v, 0), "sparse: chunk vector mismatch") { ok = false; }
  var ty_unknown = vi1(0);
  if !err_bytes_is(sparse_build(4, &ty_unknown, &blk_one, &bodies_empty, 0), "sparse: unknown chunk type") { ok = false; }
  var blk_neg = vi1(-1);
  if !err_bytes_is(sparse_build(4, &ty_raw, &blk_neg, &bodies_empty, 0), "sparse: bad chunk blocks") { ok = false; }
  var blk_big = vi1(4294967296);
  if !err_bytes_is(sparse_build(4, &ty_raw, &blk_big, &bodies_empty, 0), "sparse: bad chunk blocks") { ok = false; }
  var ty_crc = vi1(51908);
  var blk_crc = vi1(1);
  var bodies_crc = vb1(hb("88776655"));
  if !err_bytes_is(sparse_build(4, &ty_crc, &blk_crc, &bodies_crc, 0), "sparse: bad chunk blocks") { ok = false; }
  var bodies5 = vb1(repeat_byte(0, 5));
  if !err_bytes_is(sparse_build(4, &ty_raw, &blk_one, &bodies5, 0), "sparse: bad chunk body") { ok = false; }
  var blk_three = vi1(3);
  var bodies8 = vb1(repeat_byte(0, 8));
  if !err_bytes_is(sparse_build(4, &ty_raw, &blk_three, &bodies8, 0), "sparse: bad chunk body") { ok = false; }
  var ty_fill = vi1(51906);
  var bodies3 = vb1(repeat_byte(0, 3));
  if !err_bytes_is(sparse_build(4, &ty_fill, &blk_one, &bodies3, 0), "sparse: bad chunk body") { ok = false; }
  var ty_dont = vi1(51907);
  var bodies_dont = vb1(repeat_byte(0, 1));
  if !err_bytes_is(sparse_build(4, &ty_dont, &blk_one, &bodies_dont, 0), "sparse: bad chunk body") { ok = false; }
  var bodies_crc3 = vb1(repeat_byte(0, 3));
  var blk_crc0 = vi1(0);
  if !err_bytes_is(sparse_build(4, &ty_crc, &blk_crc0, &bodies_crc3, 0), "sparse: bad chunk body") { ok = false; }
  var ty_fill2 = vi2(51906, 51906);
  var blk_fill2 = vi2(4294967295, 4294967295);
  var bodies_fill2 = vb2(hb("ddccbbaa"), hb("ddccbbaa"));
  if !err_bytes_is(sparse_build(4, &ty_fill2, &blk_fill2, &bodies_fill2, 0), "sparse: too many blocks") { ok = false; }
  return assert(ok, "builder validates block size, checksum, vectors, types, blocks and bodies before emitting");
}

fn t24() -> TestResult {
  var types = Vec[Int].new();
  types.push(51906);
  types.push(51907);
  types.push(51908);
  var blocks = Vec[Int].new();
  blocks.push(3);
  blocks.push(2);
  blocks.push(0);
  var bodies = Vec[Vec[UInt8]].new();
  bodies.push(hb("ddccbbaa"));
  bodies.push(empty_bytes());
  bodies.push(hb("55667788"));
  let br = sparse_build(4, &types, &blocks, &bodies, 7);
  if !br.is_ok { return assert(false, "fill/dont-care/crc32 build must succeed"); }
  let built: Vec[UInt8] = br.value;
  let pr = sparse_parse(&built);
  if !pr.is_ok { return assert(false, "builder output must parse"); }
  let t: SparseImage = pr.value;
  var ok = sparse_chunk_count(&t) == 3;
  if sparse_total_blocks(&t) != 5 { ok = false; }
  if sparse_image_checksum(&t) != 7 { ok = false; }
  if sparse_chunk_type(&t, 0) != 51906 { ok = false; }
  if sparse_chunk_type(&t, 1) != 51907 { ok = false; }
  if sparse_chunk_type(&t, 2) != 51908 { ok = false; }
  if sparse_chunk_blocks(&t, 0) != 3 { ok = false; }
  if sparse_chunk_blocks(&t, 1) != 2 { ok = false; }
  if sparse_chunk_blocks(&t, 2) != 0 { ok = false; }
  if sparse_chunk_fill_value(&t, 0) != 2864434397 { ok = false; }
  if sparse_chunk_block_offset(&t, 2) != 5 { ok = false; }
  if sparse_chunk_data_length(&t, 1) != 0 { ok = false; }
  if sparse_chunk_data_length(&t, 2) != 4 { ok = false; }
  if sparse_expanded_size(&t) != 20 { ok = false; }
  return assert(ok, "builder round-trips fill/don't-care/crc32 chunks with a 5-block header total");
}

fn main() -> Int {
  io.println("=== xiom.sparse conformance tests ===");
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
    io.println("xiom.sparse: all tests passed");
  } else {
    io.println("xiom.sparse: tests failed");
  }
  return failed;
}
