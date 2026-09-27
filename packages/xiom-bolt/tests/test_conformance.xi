// XIOM -- xiom.bolt conformance tests (18 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Covers the documented API against synthetic page images assembled here byte
// by byte, independent of src/bolt.xi: FNV-1a-64 known vectors; the meta pair
// (field values, txid-based selection, invalid-page fallback, checksum
// mismatch, truncation, page-size validation at the 1024/2048/4096/65536
// boundaries); the page header and its accessors; branch elements (pos/ksize/
// pgid/key span selectors, the child pointer array) with corrupt-pointer
// cases; leaf elements (flags/pos/ksize/vsize plus key/value spans) with
// corrupt-value cases; bucket leaf values (inline and non-inline); freelist
// pages (plain counts, the 0xFFFF overflow sentinel, continuation pages,
// out-of-range pgids); and the bounded tree walk (branch+leaf traversal order,
// depths, direct leaf roots, depth cap, out-of-order keys, cycles, bad child
// pointers, non-tree roots) plus the walk accessors and span copies.
//
// Str equality goes through str_compare (BUG 17 discipline: `==` on a Str
// read from a Vec lowers to a pointer comparison).

module bolt_tests
use xiom.io; use xiom.test;
use xiom.bolt;
use xiom.string.compare;

// --------------------------------------------------
//  Generic test helpers
// --------------------------------------------------

fn str_eq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn err_int_is(r: Result[Int, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_bool_is(r: Result[Bool, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_str_is(r: Result[Str, Str], want: Str) -> Bool {
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

fn err_ints_is(r: Result[Vec[Int], Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_page_is(r: Result[BoltPage, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_meta_is(r: Result[BoltMeta, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_pair_is(r: Result[BoltMetaPair, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_walk_is(r: Result[BoltWalk, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn int_is(r: Result[Int, Str], want: Int) -> Bool {
  if !r.is_ok {
    return false;
  }
  let v: Int = r.value;
  return v == want;
}

fn bool_is(r: Result[Bool, Str], want: Bool) -> Bool {
  if !r.is_ok {
    return false;
  }
  let v: Bool = r.value;
  if v == want {
    return true;
  }
  return false;
}

fn str_is(r: Result[Str, Str], want: Str) -> Bool {
  if !r.is_ok {
    return false;
  }
  let v: Str = r.value;
  return str_eq(v, want);
}

// --------------------------------------------------
//  Byte helpers (independent of src/bolt.xi)
// --------------------------------------------------

fn zeros(n: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < n {
    v.push(0 as UInt8);
    i = i + 1;
  }
  return v;
}

// Byte `k` (0 = least significant) of `val`'s two's-complement pattern.
fn low_byte(val: Int, k: Int) -> Int {
  var q = val;
  var i = 0;
  while i < k {
    var r = q % 256;
    if r < 0 { r = r + 256; }
    q = (q - r) / 256;
    i = i + 1;
  }
  var b = q % 256;
  if b < 0 { b = b + 256; }
  return b;
}

fn put_u8(v: &mut Vec[UInt8], off: Int, val: Int) {
  v[off] = (val % 256) as UInt8;
}

// Patch `size` (1..8) little-endian bytes at `off` with `val`.
fn put_uint(v: &mut Vec[UInt8], off: Int, val: Int, size: Int) {
  var i = 0;
  while i < size {
    v[off + i] = low_byte(val, i) as UInt8;
    i = i + 1;
  }
}

// Independent FNV-1a-64 over a buffer span (raw two's-complement result).
fn fnv1a(v: &Vec[UInt8], off: Int, size: Int) -> Int {
  var h = 0 - 3750763034362895579;
  var i = 0;
  while i < size {
    let b = (v[off + i] as Int) & 0xFF;
    var low = h % 256;
    if low < 0 { low = low + 256; }
    var x = low;
    var y = b;
    var out = 0;
    var bit = 1;
    while bit <= 128 {
      let xb = x % 2;
      let yb = y % 2;
      if xb != yb { out = out + bit; }
      x = x / 2;
      y = y / 2;
      bit = bit * 2;
    }
    h = (h - low) + out;
    h = h * 1099511628211;
    i = i + 1;
  }
  return h;
}

// --------------------------------------------------
//  Page-image builders
// --------------------------------------------------

// 16-byte page header: id u64, flags u16, count u16, overflow u32.
fn put_page_header(v: &mut Vec[UInt8], off: Int, id: Int, flags: Int, count: Int, overflow: Int) {
  put_uint(v, off, id, 8);
  put_uint(v, off + 8, flags, 2);
  put_uint(v, off + 10, count, 2);
  put_uint(v, off + 12, overflow, 4);
}

// 16-byte branch element: pos u32, ksize u32, pgid u64.
fn put_branch_elem(v: &mut Vec[UInt8], eoff: Int, pos: Int, ksize: Int, pgid: Int) {
  put_uint(v, eoff, pos, 4);
  put_uint(v, eoff + 4, ksize, 4);
  put_uint(v, eoff + 8, pgid, 8);
}

// 16-byte leaf element: flags u32, pos u32, ksize u32, vsize u32.
fn put_leaf_elem(v: &mut Vec[UInt8], eoff: Int, flags: Int, pos: Int, ksize: Int, vsize: Int) {
  put_uint(v, eoff, flags, 4);
  put_uint(v, eoff + 4, pos, 4);
  put_uint(v, eoff + 8, ksize, 4);
  put_uint(v, eoff + 12, vsize, 4);
}

// Write a full meta image at `off` and stamp its FNV-1a-64 checksum over the
// 56 bytes at off+16.
fn put_meta(v: &mut Vec[UInt8], off: Int, ps: Int, txid: Int, root: Int, seq: Int, freelist: Int, pgid: Int, magic: Int, version: Int) {
  put_uint(v, off, txid % 2, 8);
  put_uint(v, off + 8, 4, 2);
  put_uint(v, off + 10, 0, 2);
  put_uint(v, off + 12, 0, 4);
  put_uint(v, off + 16, magic, 4);
  put_uint(v, off + 20, version, 4);
  put_uint(v, off + 24, ps, 4);
  put_uint(v, off + 28, 0, 4);
  put_uint(v, off + 32, root, 8);
  put_uint(v, off + 40, seq, 8);
  put_uint(v, off + 48, freelist, 8);
  put_uint(v, off + 56, pgid, 8);
  put_uint(v, off + 64, txid, 8);
  put_uint(v, off + 72, 0, 8);
  let sum = fnv1a(v, off + 16, 56);
  put_uint(v, off + 72, sum, 8);
}

// Two-page (2048 bytes, page size 1024) database with a valid meta pair:
// meta0 txid 9, meta1 txid 10, both with root 3 / sequence 42/43.
fn fx_meta() -> Vec[UInt8] {
  var v = zeros(2048);
  put_meta(&mut v, 0, 1024, 9, 3, 42, 2, 11, BOLT_MAGIC, BOLT_VERSION);
  put_meta(&mut v, 1024, 1024, 10, 3, 43, 2, 11, BOLT_MAGIC, BOLT_VERSION);
  return v;
}

// Four-page (4096 bytes, page size 1024) database holding one branch page at
// pgid 2 (keys "c" and "m"; children pgid 3 twice) and one leaf page at
// pgid 3.
fn fx_branch() -> Vec[UInt8] {
  var v = zeros(4096);
  put_page_header(&mut v, 2048, 2, 1, 2, 0);
  put_branch_elem(&mut v, 2064, 32, 1, 3);
  put_branch_elem(&mut v, 2080, 20, 1, 3);
  put_u8(&mut v, 2096, 99);
  put_u8(&mut v, 2100, 109);
  put_page_header(&mut v, 3072, 3, 2, 2, 0);
  put_leaf_elem(&mut v, 3088, 0, 32, 1, 1);
  put_leaf_elem(&mut v, 3104, 0, 20, 1, 1);
  put_u8(&mut v, 3120, 97);
  put_u8(&mut v, 3121, 49);
  put_u8(&mut v, 3124, 98);
  put_u8(&mut v, 3125, 50);
  return v;
}

// Four-page database holding one leaf page at pgid 3 with keys "a" -> "1"
// and "b" -> "2".
fn fx_leaf() -> Vec[UInt8] {
  var v = zeros(4096);
  put_page_header(&mut v, 3072, 3, 2, 2, 0);
  put_leaf_elem(&mut v, 3088, 0, 32, 1, 1);
  put_leaf_elem(&mut v, 3104, 0, 20, 1, 1);
  put_u8(&mut v, 3120, 97);
  put_u8(&mut v, 3121, 49);
  put_u8(&mut v, 3124, 98);
  put_u8(&mut v, 3125, 50);
  return v;
}

// Four-page database holding one leaf page at pgid 1 with two bucket
// elements: an inline bucket (root 0, sequence 7) whose 34-byte inline leaf
// page holds "x" -> "y", and a non-inline bucket (root 9, sequence 0) with a
// 16-byte value.
fn fx_inline() -> Vec[UInt8] {
  var v = zeros(4096);
  put_page_header(&mut v, 1024, 1, 2, 2, 0);
  put_leaf_elem(&mut v, 1040, 1, 32, 1, 50);
  put_leaf_elem(&mut v, 1056, 1, 67, 1, 16);
  put_u8(&mut v, 1072, 107);
  put_uint(&mut v, 1073, 0, 8);
  put_uint(&mut v, 1081, 7, 8);
  put_page_header(&mut v, 1089, 0, 2, 1, 0);
  put_leaf_elem(&mut v, 1105, 0, 16, 1, 1);
  put_u8(&mut v, 1121, 120);
  put_u8(&mut v, 1122, 121);
  put_u8(&mut v, 1123, 98);
  put_uint(&mut v, 1124, 9, 8);
  put_uint(&mut v, 1132, 0, 8);
  return v;
}

// Six-page database with a two-level tree: branch root at pgid 3 (keys "c"
// and "m", children pgid 4 and pgid 5), leaf pgid 4 ("a" -> "1", "b" -> "2")
// and leaf pgid 5 ("n" -> "3", "z" -> "4"), plus a valid meta pair.
fn fx_tree() -> Vec[UInt8] {
  var v = zeros(6144);
  put_meta(&mut v, 0, 1024, 5, 3, 1, 2, 6, BOLT_MAGIC, BOLT_VERSION);
  put_meta(&mut v, 1024, 1024, 6, 3, 1, 2, 6, BOLT_MAGIC, BOLT_VERSION);
  put_page_header(&mut v, 3072, 3, 1, 2, 0);
  put_branch_elem(&mut v, 3088, 32, 1, 4);
  put_branch_elem(&mut v, 3104, 20, 1, 5);
  put_u8(&mut v, 3120, 99);
  put_u8(&mut v, 3124, 109);
  put_page_header(&mut v, 4096, 4, 2, 2, 0);
  put_leaf_elem(&mut v, 4112, 0, 32, 1, 1);
  put_leaf_elem(&mut v, 4128, 0, 20, 1, 1);
  put_u8(&mut v, 4144, 97);
  put_u8(&mut v, 4145, 49);
  put_u8(&mut v, 4148, 98);
  put_u8(&mut v, 4149, 50);
  put_page_header(&mut v, 5120, 5, 2, 2, 0);
  put_leaf_elem(&mut v, 5136, 0, 32, 1, 1);
  put_leaf_elem(&mut v, 5152, 0, 20, 1, 1);
  put_u8(&mut v, 5168, 110);
  put_u8(&mut v, 5169, 51);
  put_u8(&mut v, 5172, 122);
  put_u8(&mut v, 5173, 52);
  return v;
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  var empty = zeros(0);
  var one = zeros(1);
  put_u8(&mut one, 0, 97);
  var z56 = zeros(56);
  var d = zeros(4);
  var ok = int_is(bolt_fnv1a64(&empty, 0, 0), 0 - 3750763034362895579);
  if !int_is(bolt_fnv1a64(&one, 0, 1), 0 - 5808556873153909620) { ok = false; }
  if !int_is(bolt_fnv1a64(&z56, 0, 56), 0 - 8448432019781917307) { ok = false; }
  if !int_is(bolt_fnv1a64(&d, 0, 4), 5558979605539197941) { ok = false; }
  if !err_int_is(bolt_fnv1a64(&z56, 0, 57), "bolt: span out of bounds") { ok = false; }
  if !err_int_is(bolt_fnv1a64(&z56, -1, 1), "bolt: span out of bounds") { ok = false; }
  if !err_int_is(bolt_fnv1a64(&z56, 0, -1), "bolt: span out of bounds") { ok = false; }
  return assert(ok, "FNV-1a-64 known vectors (offset basis, 'a', 56 zeros, 4 zeros) and span bounds");
}

fn t2() -> TestResult {
  let d = fx_meta();
  let pr = bolt_meta_read(&d);
  if !pr.is_ok { return assert(false, "valid meta pair must parse"); }
  let pair: BoltMetaPair = pr.value;
  var ok = bolt_meta_selected(&pair) == BOLT_SELECT_META1;
  let r0 = bolt_meta_at(&pair, 0);
  let r1 = bolt_meta_at(&pair, 1);
  if !r0.is_ok || !r1.is_ok { return assert(false, "meta 0/1 must decode"); }
  let m0: BoltMeta = r0.value;
  let m1: BoltMeta = r1.value;
  if !bolt_meta_valid(&m0) { ok = false; }
  if !bolt_meta_valid(&m1) { ok = false; }
  if !int_is(bolt_meta_field(&m0, BOLT_META_FIELD_MAGIC), 0xED0CDAED) { ok = false; }
  if !int_is(bolt_meta_field(&m0, BOLT_META_FIELD_VERSION), 2) { ok = false; }
  if !int_is(bolt_meta_field(&m0, BOLT_META_FIELD_PAGE_SIZE), 1024) { ok = false; }
  if !int_is(bolt_meta_field(&m0, BOLT_META_FIELD_ROOT), 3) { ok = false; }
  if !int_is(bolt_meta_field(&m0, BOLT_META_FIELD_SEQUENCE), 42) { ok = false; }
  if !int_is(bolt_meta_field(&m0, BOLT_META_FIELD_FREELIST), 2) { ok = false; }
  if !int_is(bolt_meta_field(&m0, BOLT_META_FIELD_PGID), 11) { ok = false; }
  if !int_is(bolt_meta_field(&m0, BOLT_META_FIELD_TXID), 9) { ok = false; }
  if !int_is(bolt_meta_field(&m0, BOLT_META_FIELD_PAGE_ID), 1) { ok = false; }
  if !int_is(bolt_meta_field(&m0, BOLT_META_FIELD_OFFSET), 0) { ok = false; }
  if !int_is(bolt_meta_field(&m1, BOLT_META_FIELD_TXID), 10) { ok = false; }
  if !int_is(bolt_meta_field(&m1, BOLT_META_FIELD_PAGE_ID), 0) { ok = false; }
  if !int_is(bolt_meta_field(&m1, BOLT_META_FIELD_SEQUENCE), 43) { ok = false; }
  if !int_is(bolt_meta_field(&m1, BOLT_META_FIELD_OFFSET), 1024) { ok = false; }
  let c0 = bolt_meta_field(&m0, BOLT_META_FIELD_CHECKSUM);
  let k0 = bolt_meta_field(&m0, BOLT_META_FIELD_COMPUTED);
  let cs = bolt_meta_checksum(&d, 0);
  if !cs.is_ok { ok = false; } else {
    let cv: Int = cs.value;
    if !int_is(c0, cv) { ok = false; }
    if !int_is(k0, cv) { ok = false; }
  }
  if !int_is(bolt_meta_selected_field(&pair, BOLT_META_FIELD_TXID), 10) { ok = false; }
  let sm: BoltMeta = bolt_meta_selected_meta(&pair);
  if sm.txid != 10 { ok = false; }
  if !err_meta_is(bolt_meta_at(&pair, 2), "bolt: meta index out of range") { ok = false; }
  if !err_int_is(bolt_meta_field(&m0, BOLT_META_FIELD_COUNT), "bolt: bad field selector") { ok = false; }
  return assert(ok, "meta pair fields, page ids (txid%2), FNV checksum and higher-txid selection");
}

fn t3() -> TestResult {
  // meta1 checksum invalid: selection falls back to meta0.
  var v1 = fx_meta();
  put_u8(&mut v1, 1024 + 32, 7);
  let r1 = bolt_meta_read(&v1);
  var ok = r1.is_ok;
  if !ok { return assert(false, "meta0 still valid"); }
  let p1: BoltMetaPair = r1.value;
  if bolt_meta_selected(&p1) != BOLT_SELECT_META0 { ok = false; }
  let r1m1 = bolt_meta_at(&p1, 1);
  if !r1m1.is_ok { ok = false; } else {
    let m1: BoltMeta = r1m1.value;
    if bolt_meta_valid(&m1) { ok = false; }
    if m1.txid != 10 { ok = false; }
    if m1.checksum == m1.computed_checksum { ok = false; }
  }
  // meta0 invalid: selection picks meta1.
  var v2 = fx_meta();
  put_u8(&mut v2, 16, 0);
  let r2 = bolt_meta_read(&v2);
  if !r2.is_ok { ok = false; } else {
    let p2: BoltMetaPair = r2.value;
    if bolt_meta_selected(&p2) != BOLT_SELECT_META1 { ok = false; }
  }
  // Equal txids: meta0 wins the tie.
  var v3 = zeros(2048);
  put_meta(&mut v3, 0, 1024, 5, 3, 1, 2, 7, BOLT_MAGIC, BOLT_VERSION);
  put_meta(&mut v3, 1024, 1024, 5, 3, 1, 2, 7, BOLT_MAGIC, BOLT_VERSION);
  let r3 = bolt_meta_read(&v3);
  if !r3.is_ok { ok = false; } else {
    let p3: BoltMetaPair = r3.value;
    if bolt_meta_selected(&p3) != BOLT_SELECT_META0 { ok = false; }
  }
  return assert(ok, "invalid meta fallback (either page) and txid tie resolves to meta0");
}

fn t4() -> TestResult {
  // Both magic fields corrupt: no valid meta page.
  var v1 = fx_meta();
  put_u8(&mut v1, 16, 0);
  put_u8(&mut v1, 1024 + 16, 0);
  var ok = err_pair_is(bolt_meta_read(&v1), "bolt: no valid meta page at offset 0 or 1024");
  // Bad page-size field in meta0.
  var v2 = zeros(2048);
  put_uint(&mut v2, 24, 3000, 4);
  if !err_pair_is(bolt_meta_read(&v2), "bolt: bad page size") { ok = false; }
  var v3 = zeros(2048);
  put_uint(&mut v3, 24, 512, 4);
  if !err_pair_is(bolt_meta_read(&v3), "bolt: bad page size") { ok = false; }
  var v4 = zeros(2048);
  put_uint(&mut v4, 24, 131072, 4);
  if !err_pair_is(bolt_meta_read(&v4), "bolt: bad page size") { ok = false; }
  var v5 = zeros(2048);
  put_uint(&mut v5, 24, 0, 4);
  if !err_pair_is(bolt_meta_read(&v5), "bolt: bad page size") { ok = false; }
  // Truncated buffers.
  var v6 = zeros(20);
  if !err_pair_is(bolt_meta_read(&v6), "bolt: truncated meta") { ok = false; }
  var v7 = zeros(79);
  if !err_pair_is(bolt_meta_read(&v7), "bolt: truncated meta") { ok = false; }
  // One meta page only: page size read, pair missing.
  var v8 = zeros(1024);
  put_meta(&mut v8, 0, 1024, 4, 3, 1, 2, 5, BOLT_MAGIC, BOLT_VERSION);
  if !err_pair_is(bolt_meta_read(&v8), "bolt: truncated meta") { ok = false; }
  // bolt_meta_checksum bounds and the all-zero input vector.
  var v9 = zeros(79);
  if !err_int_is(bolt_meta_checksum(&v9, 0), "bolt: meta page out of bounds") { ok = false; }
  var v10 = zeros(80);
  if !int_is(bolt_meta_checksum(&v10, 0), 0 - 8448432019781917307) { ok = false; }
  if !err_int_is(bolt_meta_checksum(&v10, 1), "bolt: meta page out of bounds") { ok = false; }
  return assert(ok, "meta errors: bad magic pair, page-size policy, truncation, checksum bounds");
}

fn t5() -> TestResult {
  // Page-size policy: 1024/2048/4096 accepted on one buffer; 65536 accepted
  // on a two-meta-page buffer; illegal sizes rejected everywhere.
  var v = zeros(4096);
  put_page_header(&mut v, 0, 0, 2, 3, 0);
  var ok = true;
  let ra = bolt_read_page(&v, 1024, 0);
  let rb = bolt_read_page(&v, 2048, 0);
  let rc = bolt_read_page(&v, 4096, 0);
  if !ra.is_ok || !rb.is_ok || !rc.is_ok { return assert(false, "legal page sizes must read page 0"); }
  let pa: BoltPage = ra.value;
  if pa.count != 3 { ok = false; }
  if !err_page_is(bolt_read_page(&v, 0, 0), "bolt: bad page size") { ok = false; }
  if !err_page_is(bolt_read_page(&v, 512, 0), "bolt: bad page size") { ok = false; }
  if !err_page_is(bolt_read_page(&v, 1000, 0), "bolt: bad page size") { ok = false; }
  if !err_page_is(bolt_read_page(&v, 3000, 0), "bolt: bad page size") { ok = false; }
  if !err_page_is(bolt_read_page(&v, 131072, 0), "bolt: bad page size") { ok = false; }
  var big = zeros(131072);
  put_meta(&mut big, 0, 65536, 20, 3, 1, 2, 8, BOLT_MAGIC, BOLT_VERSION);
  put_meta(&mut big, 65536, 65536, 21, 4, 1, 2, 8, BOLT_MAGIC, BOLT_VERSION);
  let br = bolt_meta_read(&big);
  if !br.is_ok { ok = false; } else {
    let bp: BoltMetaPair = br.value;
    if bolt_meta_selected(&bp) != BOLT_SELECT_META1 { ok = false; }
    if !int_is(bolt_meta_selected_field(&bp, BOLT_META_FIELD_PAGE_SIZE), 65536) { ok = false; }
  }
  let pg = bolt_read_page(&big, 65536, 1);
  if !pg.is_ok { ok = false; } else {
    let p1: BoltPage = pg.value;
    if p1.offset != 65536 { ok = false; }
    if p1.flags != BOLT_PAGE_META { ok = false; }
  }
  if !err_page_is(bolt_read_page(&big, 65536, 2), "bolt: page id out of range: 2") { ok = false; }
  return assert(ok, "page-size policy: 1024/2048/4096/65536 accepted, 0/512/1000/3000/131072 rejected");
}

fn t6() -> TestResult {
  var v = zeros(4096);
  put_page_header(&mut v, 1024, 1, 2, 7, 0);
  put_page_header(&mut v, 2048, 2, 1, 2, 1);
  put_page_header(&mut v, 3072, 3, 0x20, 0, 0);
  var ok = true;
  let r1 = bolt_read_page(&v, 1024, 1);
  let r2 = bolt_read_page(&v, 1024, 2);
  if !r1.is_ok || !r2.is_ok { return assert(false, "leaf and branch pages must read"); }
  let p1: BoltPage = r1.value;
  let p2: BoltPage = r2.value;
  if bolt_page_id(&p1) != 1 { ok = false; }
  if bolt_page_flags(&p1) != BOLT_PAGE_LEAF { ok = false; }
  if bolt_page_count(&p1) != 7 { ok = false; }
  if bolt_page_overflow(&p1) != 0 { ok = false; }
  if bolt_page_offset(&p1) != 1024 { ok = false; }
  if bolt_page_span(&p1) != 1024 { ok = false; }
  if bolt_page_is_inline(&p1) { ok = false; }
  if bolt_page_id(&p2) != 2 { ok = false; }
  if bolt_page_flags(&p2) != BOLT_PAGE_BRANCH { ok = false; }
  if bolt_page_count(&p2) != 2 { ok = false; }
  if bolt_page_overflow(&p2) != 1 { ok = false; }
  if bolt_page_offset(&p2) != 2048 { ok = false; }
  // Unknown flags: bit 5 set, or no known bit at all.
  if !err_page_is(bolt_read_page(&v, 1024, 3), "bolt: unknown page flags at 3072") { ok = false; }
  if !err_page_is(bolt_read_page(&v, 1024, 0), "bolt: unknown page flags at 0") { ok = false; }
  if !err_page_is(bolt_read_page(&v, 1024, 4), "bolt: page id out of range: 4") { ok = false; }
  if !err_page_is(bolt_read_page(&v, 1024, -1), "bolt: page id out of range: -1") { ok = false; }
  return assert(ok, "page header fields, accessors, unknown flags and page-id bounds");
}

fn t7() -> TestResult {
  let d = fx_branch();
  let pr = bolt_read_page(&d, 1024, 2);
  if !pr.is_ok { return assert(false, "branch fixture must read"); }
  let pg: BoltPage = pr.value;
  var ok = true;
  if !int_is(bolt_branch_field(&d, &pg, 0, BOLT_BRANCH_FIELD_POS), 32) { ok = false; }
  if !int_is(bolt_branch_field(&d, &pg, 0, BOLT_BRANCH_FIELD_KSIZE), 1) { ok = false; }
  if !int_is(bolt_branch_field(&d, &pg, 0, BOLT_BRANCH_FIELD_PGID), 3) { ok = false; }
  if !int_is(bolt_branch_field(&d, &pg, 0, BOLT_BRANCH_FIELD_OFFSET), 2064) { ok = false; }
  if !int_is(bolt_branch_field(&d, &pg, 0, BOLT_BRANCH_FIELD_KEY_OFFSET), 2096) { ok = false; }
  if !int_is(bolt_branch_field(&d, &pg, 1, BOLT_BRANCH_FIELD_POS), 20) { ok = false; }
  if !int_is(bolt_branch_field(&d, &pg, 1, BOLT_BRANCH_FIELD_KEY_OFFSET), 2100) { ok = false; }
  if !str_is(bolt_span_str(&d, 2096, 1), "c") { ok = false; }
  let cp = bolt_branch_child_pgids(&d, &pg);
  if !cp.is_ok { ok = false; } else {
    let kids: Vec[Int] = cp.value;
    if kids.len() != 2 { ok = false; } else {
      let k0: Int = kids[0];
      let k1: Int = kids[1];
      if k0 != 3 { ok = false; }
      if k1 != 3 { ok = false; }
    }
  }
  if !err_int_is(bolt_branch_field(&d, &pg, 2, BOLT_BRANCH_FIELD_POS), "bolt: branch element index out of range") { ok = false; }
  if !err_int_is(bolt_branch_field(&d, &pg, -1, BOLT_BRANCH_FIELD_POS), "bolt: branch element index out of range") { ok = false; }
  if !err_int_is(bolt_branch_field(&d, &pg, 0, BOLT_BRANCH_FIELD_COUNT), "bolt: bad field selector") { ok = false; }
  let lr = bolt_read_page(&d, 1024, 3);
  if !lr.is_ok { ok = false; } else {
    let lp: BoltPage = lr.value;
    if !err_int_is(bolt_branch_field(&d, &lp, 0, BOLT_BRANCH_FIELD_POS), "bolt: not a branch page") { ok = false; }
    if !err_ints_is(bolt_branch_child_pgids(&d, &lp), "bolt: not a branch page") { ok = false; }
  }
  return assert(ok, "branch element selectors, child pointer array and index/type/selector errors");
}

fn t8() -> TestResult {
  var v = fx_branch();
  put_uint(&mut v, 2064, 4000, 4);
  let r1 = bolt_read_page(&v, 1024, 2);
  if !r1.is_ok { return assert(false, "branch fixture must read"); }
  let p1: BoltPage = r1.value;
  var ok = err_int_is(bolt_branch_field(&v, &p1, 0, BOLT_BRANCH_FIELD_POS), "bolt: branch element key out of page bounds at 2064");
  var v2 = fx_branch();
  put_uint(&mut v2, 2072, 4, 8);
  let r2 = bolt_read_page(&v2, 1024, 2);
  if !r2.is_ok { ok = false; } else {
    let p2: BoltPage = r2.value;
    if !err_int_is(bolt_branch_field(&v2, &p2, 0, BOLT_BRANCH_FIELD_PGID), "bolt: branch element page id out of range at 2064") { ok = false; }
  }
  var v3 = fx_branch();
  put_uint(&mut v3, 2072, -1, 8);
  let r3 = bolt_read_page(&v3, 1024, 2);
  if !r3.is_ok { ok = false; } else {
    let p3: BoltPage = r3.value;
    if !err_int_is(bolt_branch_field(&v3, &p3, 0, BOLT_BRANCH_FIELD_PGID), "bolt: branch element page id out of range at 2064") { ok = false; }
  }
  var v4 = fx_branch();
  put_uint(&mut v4, 2058, 1000, 2);
  let r4 = bolt_read_page(&v4, 1024, 2);
  if !r4.is_ok { ok = false; } else {
    let p4: BoltPage = r4.value;
    if !err_int_is(bolt_branch_field(&v4, &p4, 999, BOLT_BRANCH_FIELD_POS), "bolt: branch element out of page bounds at 18048") { ok = false; }
  }
  return assert(ok, "branch consistency: corrupt key pointer, out-of-range and negative pgids, element span");
}

fn t9() -> TestResult {
  let d = fx_leaf();
  let pr = bolt_read_page(&d, 1024, 3);
  if !pr.is_ok { return assert(false, "leaf fixture must read"); }
  let pg: BoltPage = pr.value;
  var ok = true;
  if !int_is(bolt_leaf_field(&d, &pg, 0, BOLT_LEAF_FIELD_FLAGS), 0) { ok = false; }
  if !int_is(bolt_leaf_field(&d, &pg, 0, BOLT_LEAF_FIELD_POS), 32) { ok = false; }
  if !int_is(bolt_leaf_field(&d, &pg, 0, BOLT_LEAF_FIELD_KSIZE), 1) { ok = false; }
  if !int_is(bolt_leaf_field(&d, &pg, 0, BOLT_LEAF_FIELD_VSIZE), 1) { ok = false; }
  if !int_is(bolt_leaf_field(&d, &pg, 0, BOLT_LEAF_FIELD_OFFSET), 3088) { ok = false; }
  if !int_is(bolt_leaf_field(&d, &pg, 0, BOLT_LEAF_FIELD_KEY_OFFSET), 3120) { ok = false; }
  if !int_is(bolt_leaf_field(&d, &pg, 0, BOLT_LEAF_FIELD_VALUE_OFFSET), 3121) { ok = false; }
  if !int_is(bolt_leaf_field(&d, &pg, 1, BOLT_LEAF_FIELD_POS), 20) { ok = false; }
  if !int_is(bolt_leaf_field(&d, &pg, 1, BOLT_LEAF_FIELD_KEY_OFFSET), 3124) { ok = false; }
  if !int_is(bolt_leaf_field(&d, &pg, 1, BOLT_LEAF_FIELD_VALUE_OFFSET), 3125) { ok = false; }
  if !str_is(bolt_span_str(&d, 3120, 1), "a") { ok = false; }
  if !str_is(bolt_span_str(&d, 3121, 1), "1") { ok = false; }
  if !str_is(bolt_span_str(&d, 3124, 1), "b") { ok = false; }
  if !str_is(bolt_span_str(&d, 3125, 1), "2") { ok = false; }
  if !bool_is(bolt_leaf_is_bucket(&d, &pg, 0), false) { ok = false; }
  if !err_int_is(bolt_leaf_bucket_field(&d, &pg, 0, BOLT_BUCKET_FIELD_ROOT), "bolt: leaf element is not a bucket") { ok = false; }
  if !err_page_is(bolt_inline_page(&d, &pg, 0), "bolt: leaf element is not a bucket") { ok = false; }
  return assert(ok, "leaf element selectors, key/value spans and non-bucket errors");
}

fn t10() -> TestResult {
  var v = fx_leaf();
  put_uint(&mut v, 3100, 10000, 4);
  put_page_header(&mut v, 3072, 3, 2, 65535, 0);
  put_page_header(&mut v, 2048, 2, 1, 0, 0);
  let pr = bolt_read_page(&v, 1024, 3);
  if !pr.is_ok { return assert(false, "leaf fixture must read"); }
  let pg: BoltPage = pr.value;
  var ok = err_int_is(bolt_leaf_field(&v, &pg, 0, BOLT_LEAF_FIELD_VALUE_OFFSET), "bolt: leaf element value out of page bounds at 3088");
  if !err_int_is(bolt_leaf_field(&v, &pg, 65534, BOLT_LEAF_FIELD_POS), "bolt: leaf element out of page bounds at 1051632") { ok = false; }
  let d2 = fx_leaf();
  let pr2 = bolt_read_page(&d2, 1024, 3);
  if !pr2.is_ok { ok = false; } else {
    let pg2: BoltPage = pr2.value;
    if !err_int_is(bolt_leaf_field(&d2, &pg2, 2, BOLT_LEAF_FIELD_POS), "bolt: leaf element index out of range") { ok = false; }
    if !err_int_is(bolt_leaf_field(&d2, &pg2, -1, BOLT_LEAF_FIELD_POS), "bolt: leaf element index out of range") { ok = false; }
    if !err_int_is(bolt_leaf_field(&d2, &pg2, 0, BOLT_LEAF_FIELD_COUNT), "bolt: bad field selector") { ok = false; }
  }
  let br = bolt_read_page(&v, 1024, 2);
  if !br.is_ok { ok = false; } else {
    let bp: BoltPage = br.value;
    if !err_int_is(bolt_leaf_field(&v, &bp, 0, BOLT_LEAF_FIELD_POS), "bolt: not a leaf page") { ok = false; }
  }
  if !err_bytes_is(bolt_span_bytes(&v, -1, 1), "bolt: span out of bounds") { ok = false; }
  if !err_bytes_is(bolt_span_bytes(&v, 0, -1), "bolt: span out of bounds") { ok = false; }
  if !err_bytes_is(bolt_span_bytes(&v, 4097, 0), "bolt: span out of bounds") { ok = false; }
  if !err_bytes_is(bolt_span_bytes(&v, 4096, 1), "bolt: span out of bounds") { ok = false; }
  let zr = bolt_span_bytes(&v, 4096, 0);
  if !zr.is_ok { ok = false; } else {
    let z: Vec[UInt8] = zr.value;
    if z.len() != 0 { ok = false; }
  }
  return assert(ok, "leaf consistency: corrupt value pointer, element span, index/type/selector and span bounds");
}

fn t11() -> TestResult {
  let d = fx_inline();
  let pr = bolt_read_page(&d, 1024, 1);
  if !pr.is_ok { return assert(false, "inline fixture must read"); }
  let pg: BoltPage = pr.value;
  var ok = true;
  if !bool_is(bolt_leaf_is_bucket(&d, &pg, 0), true) { ok = false; }
  if !bool_is(bolt_leaf_is_inline_bucket(&d, &pg, 0), true) { ok = false; }
  if !int_is(bolt_leaf_bucket_field(&d, &pg, 0, BOLT_BUCKET_FIELD_ROOT), 0) { ok = false; }
  if !int_is(bolt_leaf_bucket_field(&d, &pg, 0, BOLT_BUCKET_FIELD_SEQUENCE), 7) { ok = false; }
  if !str_is(bolt_span_str(&d, 1072, 1), "k") { ok = false; }
  let ir = bolt_inline_page(&d, &pg, 0);
  if !ir.is_ok { ok = false; } else {
    let ip: BoltPage = ir.value;
    if !bolt_page_is_inline(&ip) { ok = false; }
    if bolt_page_offset(&ip) != 1089 { ok = false; }
    if bolt_page_span(&ip) != 34 { ok = false; }
    if bolt_page_id(&ip) != 0 { ok = false; }
    if bolt_page_flags(&ip) != BOLT_PAGE_LEAF { ok = false; }
    if bolt_page_count(&ip) != 1 { ok = false; }
    if !int_is(bolt_leaf_field(&d, &ip, 0, BOLT_LEAF_FIELD_KEY_OFFSET), 1121) { ok = false; }
    if !int_is(bolt_leaf_field(&d, &ip, 0, BOLT_LEAF_FIELD_VALUE_OFFSET), 1122) { ok = false; }
    if !str_is(bolt_span_str(&d, 1121, 1), "x") { ok = false; }
    if !str_is(bolt_span_str(&d, 1122, 1), "y") { ok = false; }
  }
  if !bool_is(bolt_leaf_is_bucket(&d, &pg, 1), true) { ok = false; }
  if !bool_is(bolt_leaf_is_inline_bucket(&d, &pg, 1), false) { ok = false; }
  if !int_is(bolt_leaf_bucket_field(&d, &pg, 1, BOLT_BUCKET_FIELD_ROOT), 9) { ok = false; }
  if !int_is(bolt_leaf_bucket_field(&d, &pg, 1, BOLT_BUCKET_FIELD_SEQUENCE), 0) { ok = false; }
  if !str_is(bolt_span_str(&d, 1123, 1), "b") { ok = false; }
  if !err_page_is(bolt_inline_page(&d, &pg, 1), "bolt: bucket is not inline") { ok = false; }
  if !err_int_is(bolt_leaf_bucket_field(&d, &pg, 1, BOLT_BUCKET_FIELD_COUNT), "bolt: bad field selector") { ok = false; }
  return assert(ok, "inline bucket: header fields, inline page decode, non-inline bucket");
}

fn t12() -> TestResult {
  var v = zeros(6144);
  put_page_header(&mut v, 2048, 2, 0x10, 3, 0);
  put_page_header(&mut v, 3072, 3, 2, 2, 0);
  put_uint(&mut v, 2064, 0, 8);
  put_uint(&mut v, 2072, 1, 8);
  put_uint(&mut v, 2080, 5, 8);
  let pr = bolt_read_page(&v, 1024, 2);
  if !pr.is_ok { return assert(false, "freelist fixture must read"); }
  let pg: BoltPage = pr.value;
  var ok = int_is(bolt_freelist_count(&v, &pg), 3);
  let cr = bolt_freelist_pgids(&v, &pg);
  if !cr.is_ok { ok = false; } else {
    let ids: Vec[Int] = cr.value;
    if ids.len() != 3 { ok = false; } else {
      let i0: Int = ids[0];
      let i1: Int = ids[1];
      let i2: Int = ids[2];
      if i0 != 0 { ok = false; }
      if i1 != 1 { ok = false; }
      if i2 != 5 { ok = false; }
    }
  }
  if !int_is(bolt_freelist_pgid(&v, &pg, 0), 0) { ok = false; }
  if !int_is(bolt_freelist_pgid(&v, &pg, 2), 5) { ok = false; }
  if !err_int_is(bolt_freelist_pgid(&v, &pg, 3), "bolt: freelist index out of range") { ok = false; }
  if !err_int_is(bolt_freelist_pgid(&v, &pg, -1), "bolt: freelist index out of range") { ok = false; }
  let lr = bolt_read_page(&v, 1024, 3);
  if !lr.is_ok { ok = false; } else {
    let lp: BoltPage = lr.value;
    if !err_int_is(bolt_freelist_count(&v, &lp), "bolt: not a freelist page") { ok = false; }
  }
  return assert(ok, "freelist page: count, pgid list, index bounds and type check");
}

fn t13() -> TestResult {
  var v = zeros(6144);
  put_page_header(&mut v, 2048, 2, 0x10, 3, 0);
  put_uint(&mut v, 2064, 0, 8);
  put_uint(&mut v, 2072, 1, 8);
  put_uint(&mut v, 2080, 6, 8);
  let pr = bolt_read_page(&v, 1024, 2);
  if !pr.is_ok { return assert(false, "freelist fixture must read"); }
  let pg: BoltPage = pr.value;
  var ok = err_int_is(bolt_freelist_pgid(&v, &pg, 2), "bolt: freelist page id out of range at 2080");
  var v2 = zeros(6144);
  put_page_header(&mut v2, 2048, 2, 0x10, 2000, 0);
  let pr2 = bolt_read_page(&v2, 1024, 2);
  if !pr2.is_ok { ok = false; } else {
    let pg2: BoltPage = pr2.value;
    if !err_int_is(bolt_freelist_count(&v2, &pg2), "bolt: freelist count out of bounds") { ok = false; }
  }
  var v3 = zeros(6144);
  put_page_header(&mut v3, 2048, 2, 0x10, 3, 5);
  let pr3 = bolt_read_page(&v3, 1024, 2);
  if !pr3.is_ok { ok = false; } else {
    let pg3: BoltPage = pr3.value;
    if !err_int_is(bolt_freelist_count(&v3, &pg3), "bolt: freelist out of bounds at 2048") { ok = false; }
  }
  return assert(ok, "freelist consistency: pgid bounds, count overflow, continuation span bounds");
}

fn t14() -> TestResult {
  var v = zeros(8192);
  put_page_header(&mut v, 2048, 2, 0x10, 0xFFFF, 0);
  put_uint(&mut v, 2064, 3, 8);
  put_uint(&mut v, 2072, 7, 8);
  put_uint(&mut v, 2080, 6, 8);
  put_uint(&mut v, 2088, 5, 8);
  let pr = bolt_read_page(&v, 1024, 2);
  if !pr.is_ok { return assert(false, "sentinel fixture must read"); }
  let pg: BoltPage = pr.value;
  var ok = int_is(bolt_freelist_count(&v, &pg), 3);
  let cr = bolt_freelist_pgids(&v, &pg);
  if !cr.is_ok { ok = false; } else {
    let ids: Vec[Int] = cr.value;
    if ids.len() != 3 { ok = false; } else {
      let i0: Int = ids[0];
      let i1: Int = ids[1];
      let i2: Int = ids[2];
      if i0 != 7 { ok = false; }
      if i1 != 6 { ok = false; }
      if i2 != 5 { ok = false; }
    }
  }
  var v2 = zeros(8192);
  put_page_header(&mut v2, 2048, 2, 0x10, 0xFFFF, 0);
  put_uint(&mut v2, 2064, 1000000, 8);
  if !err_int_is(bolt_freelist_count(&v2, &pg), "bolt: freelist count out of bounds") { ok = false; }
  var v3 = zeros(8192);
  put_page_header(&mut v3, 2048, 2, 0x10, 0xFFFF, 0);
  put_uint(&mut v3, 2064, -1, 8);
  if !err_int_is(bolt_freelist_count(&v3, &pg), "bolt: freelist count out of bounds") { ok = false; }
  var v4 = zeros(8192);
  put_page_header(&mut v4, 2048, 2, 0x10, 0xFFFF, 0);
  put_uint(&mut v4, 2064, 0, 8);
  if !int_is(bolt_freelist_count(&v4, &pg), 0) { ok = false; }
  // A 200-entry list spanning one continuation page of a 256-page file.
  var big = zeros(262144);
  put_page_header(&mut big, 2048, 2, 0x10, 200, 1);
  var i = 0;
  while i < 200 {
    put_uint(&mut big, 2064 + 8 * i, i, 8);
    i = i + 1;
  }
  let br = bolt_read_page(&big, 1024, 2);
  if !br.is_ok { ok = false; } else {
    let bp: BoltPage = br.value;
    if !int_is(bolt_freelist_count(&big, &bp), 200) { ok = false; }
    let list = bolt_freelist_pgids(&big, &bp);
    if !list.is_ok { ok = false; } else {
      let ids: Vec[Int] = list.value;
      if ids.len() != 200 { ok = false; } else {
        let last: Int = ids[199];
        if last != 199 { ok = false; }
      }
    }
  }
  var big2 = zeros(262144);
  put_page_header(&mut big2, 2048, 2, 0x10, 255, 1);
  let br2 = bolt_read_page(&big2, 1024, 2);
  if !br2.is_ok { ok = false; } else {
    let bp2: BoltPage = br2.value;
    if !err_int_is(bolt_freelist_count(&big2, &bp2), "bolt: freelist count out of bounds") { ok = false; }
  }
  return assert(ok, "freelist 0xFFFF overflow sentinel: count word, bounds and continuation pages");
}

fn t15() -> TestResult {
  let d = fx_tree();
  let wr = bolt_walk_tree(&d, 1024, 3, BOLT_MAX_DEPTH);
  if !wr.is_ok { return assert(false, "branch+leaf walk must succeed"); }
  let w: BoltWalk = wr.value;
  var ok = bolt_walk_count(&w) == 4;
  if bolt_walk_leaf_count(&w) != 2 { ok = false; }
  if !int_is(bolt_walk_field(&w, 0, BOLT_ENTRY_FIELD_PAGE_ID), 4) { ok = false; }
  if !int_is(bolt_walk_field(&w, 1, BOLT_ENTRY_FIELD_PAGE_ID), 4) { ok = false; }
  if !int_is(bolt_walk_field(&w, 2, BOLT_ENTRY_FIELD_PAGE_ID), 5) { ok = false; }
  if !int_is(bolt_walk_field(&w, 3, BOLT_ENTRY_FIELD_PAGE_ID), 5) { ok = false; }
  if !int_is(bolt_walk_field(&w, 0, BOLT_ENTRY_FIELD_DEPTH), 2) { ok = false; }
  if !int_is(bolt_walk_field(&w, 3, BOLT_ENTRY_FIELD_DEPTH), 2) { ok = false; }
  if !int_is(bolt_walk_field(&w, 0, BOLT_ENTRY_FIELD_FLAGS), 0) { ok = false; }
  if !str_is(bolt_walk_key_str(&d, &w, 0), "a") { ok = false; }
  if !str_is(bolt_walk_value_str(&d, &w, 0), "1") { ok = false; }
  if !str_is(bolt_walk_key_str(&d, &w, 1), "b") { ok = false; }
  if !str_is(bolt_walk_value_str(&d, &w, 1), "2") { ok = false; }
  if !str_is(bolt_walk_key_str(&d, &w, 2), "n") { ok = false; }
  if !str_is(bolt_walk_value_str(&d, &w, 2), "3") { ok = false; }
  if !str_is(bolt_walk_key_str(&d, &w, 3), "z") { ok = false; }
  if !str_is(bolt_walk_value_str(&d, &w, 3), "4") { ok = false; }
  let k0 = bolt_walk_field(&w, 0, BOLT_ENTRY_FIELD_KEY_OFFSET);
  let k1 = bolt_walk_field(&w, 1, BOLT_ENTRY_FIELD_KEY_OFFSET);
  if !k0.is_ok || !k1.is_ok { ok = false; } else {
    let a: Int = k0.value;
    let b: Int = k1.value;
    if a >= b { ok = false; }
  }
  // Direct leaf root: depth 1, no branch pages.
  let lr = bolt_walk_tree(&d, 1024, 4, BOLT_MAX_DEPTH);
  if !lr.is_ok { ok = false; } else {
    let lw: BoltWalk = lr.value;
    if bolt_walk_count(&lw) != 2 { ok = false; }
    if !int_is(bolt_walk_field(&lw, 0, BOLT_ENTRY_FIELD_DEPTH), 1) { ok = false; }
    if bolt_walk_leaf_count(&lw) != 1 { ok = false; }
  }
  return assert(ok, "tree walk: order, spans, depths, page ids and direct leaf root");
}

fn t16() -> TestResult {
  var v = zeros(4096);
  put_page_header(&mut v, 1024, 1, 1, 1, 0);
  put_branch_elem(&mut v, 1040, 16, 1, 2);
  put_u8(&mut v, 1056, 97);
  put_page_header(&mut v, 2048, 2, 1, 1, 0);
  put_branch_elem(&mut v, 2064, 16, 1, 3);
  put_u8(&mut v, 2080, 98);
  put_page_header(&mut v, 3072, 3, 2, 1, 0);
  put_leaf_elem(&mut v, 3088, 0, 16, 1, 1);
  put_u8(&mut v, 3104, 99);
  put_u8(&mut v, 3105, 100);
  var ok = true;
  let r3 = bolt_walk_tree(&v, 1024, 1, 3);
  if !r3.is_ok { ok = false; } else {
    let w3: BoltWalk = r3.value;
    if bolt_walk_count(&w3) != 1 { ok = false; }
    if !int_is(bolt_walk_field(&w3, 0, BOLT_ENTRY_FIELD_DEPTH), 3) { ok = false; }
    if !str_is(bolt_walk_key_str(&v, &w3, 0), "c") { ok = false; }
    if !str_is(bolt_walk_value_str(&v, &w3, 0), "d") { ok = false; }
  }
  if !err_walk_is(bolt_walk_tree(&v, 1024, 1, 2), "bolt: tree too deep at page 2 (cap 2)") { ok = false; }
  if !err_walk_is(bolt_walk_tree(&v, 1024, 1, 0), "bolt: bad walk depth cap") { ok = false; }
  return assert(ok, "walk depth cap: three-level chain succeeds at cap 3 and fails at cap 2");
}

fn t17() -> TestResult {
  // Out-of-order leaf keys.
  var v1 = zeros(4096);
  put_page_header(&mut v1, 1024, 1, 2, 2, 0);
  put_leaf_elem(&mut v1, 1040, 0, 32, 1, 1);
  put_leaf_elem(&mut v1, 1056, 0, 20, 1, 1);
  put_u8(&mut v1, 1072, 98);
  put_u8(&mut v1, 1073, 49);
  put_u8(&mut v1, 1076, 97);
  put_u8(&mut v1, 1077, 50);
  var ok = err_walk_is(bolt_walk_tree(&v1, 1024, 1, BOLT_MAX_DEPTH), "bolt: leaf keys out of order at page 1 element 1");
  // Self-referencing branch page.
  var v2 = zeros(4096);
  put_page_header(&mut v2, 1024, 1, 1, 1, 0);
  put_branch_elem(&mut v2, 1040, 16, 1, 1);
  put_u8(&mut v2, 1056, 120);
  if !err_walk_is(bolt_walk_tree(&v2, 1024, 1, BOLT_MAX_DEPTH), "bolt: page revisited in walk: 1") { ok = false; }
  // Child pgid outside the buffer.
  var v3 = zeros(4096);
  put_page_header(&mut v3, 1024, 1, 1, 1, 0);
  put_branch_elem(&mut v3, 1040, 16, 1, 9);
  put_u8(&mut v3, 1056, 120);
  if !err_walk_is(bolt_walk_tree(&v3, 1024, 1, BOLT_MAX_DEPTH), "bolt: branch element page id out of range at 1040") { ok = false; }
  // Meta and freelist pages are not tree pages.
  var v4 = zeros(4096);
  put_page_header(&mut v4, 0, 0, 4, 0, 0);
  put_page_header(&mut v4, 1024, 1, 0x10, 0, 0);
  if !err_walk_is(bolt_walk_tree(&v4, 1024, 0, BOLT_MAX_DEPTH), "bolt: not a tree page at 0") { ok = false; }
  if !err_walk_is(bolt_walk_tree(&v4, 1024, 1, BOLT_MAX_DEPTH), "bolt: not a tree page at 1") { ok = false; }
  // Root bounds and page-size errors.
  if !err_walk_is(bolt_walk_tree(&v4, 1024, 4, BOLT_MAX_DEPTH), "bolt: root page id out of range: 4") { ok = false; }
  if !err_walk_is(bolt_walk_tree(&v4, 1024, -1, BOLT_MAX_DEPTH), "bolt: root page id out of range: -1") { ok = false; }
  if !err_walk_is(bolt_walk_tree(&v4, 1000, 0, BOLT_MAX_DEPTH), "bolt: bad page size") { ok = false; }
  return assert(ok, "walk errors: out-of-order keys, cycle, bad child pointer, non-tree roots, root bounds");
}

fn t18() -> TestResult {
  var v = zeros(4096);
  put_page_header(&mut v, 3072, 3, 2, 2, 0);
  put_leaf_elem(&mut v, 3088, 0, 32, 2, 2);
  put_leaf_elem(&mut v, 3104, 0, 20, 3, 0);
  put_u8(&mut v, 3120, 97);
  put_u8(&mut v, 3121, 98);
  put_u8(&mut v, 3122, 100);
  put_u8(&mut v, 3123, 101);
  put_u8(&mut v, 3124, 97);
  put_u8(&mut v, 3125, 98);
  put_u8(&mut v, 3126, 99);
  let wr = bolt_walk_tree(&v, 1024, 3, BOLT_MAX_DEPTH);
  if !wr.is_ok { return assert(false, "multi-byte key walk must succeed"); }
  let w: BoltWalk = wr.value;
  var ok = bolt_walk_count(&w) == 2;
  if !str_is(bolt_walk_key_str(&v, &w, 0), "ab") { ok = false; }
  if !str_is(bolt_walk_value_str(&v, &w, 0), "de") { ok = false; }
  if !str_is(bolt_walk_key_str(&v, &w, 1), "abc") { ok = false; }
  if !str_is(bolt_walk_value_str(&v, &w, 1), "") { ok = false; }
  if !int_is(bolt_walk_field(&w, 0, BOLT_ENTRY_FIELD_KEY_SIZE), 2) { ok = false; }
  if !int_is(bolt_walk_field(&w, 0, BOLT_ENTRY_FIELD_VALUE_SIZE), 2) { ok = false; }
  if !int_is(bolt_walk_field(&w, 1, BOLT_ENTRY_FIELD_VALUE_SIZE), 0) { ok = false; }
  if !err_int_is(bolt_walk_field(&w, 2, BOLT_ENTRY_FIELD_DEPTH), "bolt: walk index out of range") { ok = false; }
  if !err_int_is(bolt_walk_field(&w, -1, BOLT_ENTRY_FIELD_DEPTH), "bolt: walk index out of range") { ok = false; }
  if !err_int_is(bolt_walk_field(&w, 0, BOLT_ENTRY_FIELD_COUNT), "bolt: bad field selector") { ok = false; }
  if !err_str_is(bolt_walk_key_str(&v, &w, 2), "bolt: walk index out of range") { ok = false; }
  if !err_str_is(bolt_span_str(&v, -1, 1), "bolt: span out of bounds") { ok = false; }
  let sp = bolt_span_bytes(&v, 3120, 2);
  if !sp.is_ok { ok = false; } else {
    let b: Vec[UInt8] = sp.value;
    if b.len() != 2 { ok = false; } else {
      let b0 = (b[0] as Int) & 0xFF;
      let b1 = (b[1] as Int) & 0xFF;
      if b0 != 97 { ok = false; }
      if b1 != 98 { ok = false; }
    }
  }
  if !str_is(bolt_span_str(&v, 3120, 2), "ab") { ok = false; }
  return assert(ok, "walk accessors: multi-byte and prefix keys, empty value, index and bounds errors");
}

fn main() -> Int {
  io.println("=== xiom.bolt conformance tests ===");
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
  if failed == 0 {
    io.println("xiom.bolt: all tests passed");
  } else {
    io.println("xiom.bolt: tests failed");
  }
  return failed;
}
