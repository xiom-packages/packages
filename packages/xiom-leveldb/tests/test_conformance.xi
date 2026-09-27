// XIOM -- xiom.leveldb conformance tests (18 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Covers the documented API: LEB128 varint32/varint64 boundaries, overflow
// and consumed counts; internal keys (tag layout, type table, comparator);
// CRC32C Castagnoli vectors and the LevelDB rotation mask; 7-byte log
// headers; FULL and FIRST/MIDDLE/LAST log reassembly across 32 KiB blocks
// with masked CRC verification; the log boundary rule; block entries with
// prefix compression; the restart array; whole-block iteration; the 5-byte
// block trailer; both 48-byte footer layouts; bounded BlockHandles; and
// index-block entries.
//
// Every fixture is a synthetic byte buffer built in-test; no external data
// files. Err strings are compared with compare.str_compare (BUG 17
// discipline: `==` on Str lowers to a pointer comparison). The CRC32C is
// pinned against known-answer vectors and cross-checked against an
// independent bit-serial reference written below.

module leveldb_tests
use xiom.io; use xiom.test;
use xiom.leveldb;
use xiom.string;
use xiom.string.compare;
use xiom.encoding.hex;

// --------------------------------------------------
//  Generic helpers
// --------------------------------------------------

fn hb(hexstr: Str) -> Vec[UInt8] {
  let r = hex.hex_decode(hexstr);
  if r.is_ok {
    return r.value;
  }
  return Vec[UInt8].new();
}

fn str_eq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn gb(data: &Vec[UInt8], pos: Int) -> Int {
  return (data[pos] as Int) & 0xFF;
}

fn bytes_eq(a: &Vec[UInt8], b: &Vec[UInt8]) -> Bool {
  if a.len() != b.len() { return false; }
  var i = 0;
  while i < a.len() {
    if gb(a, i) != gb(b, i) { return false; }
    i = i + 1;
  }
  return true;
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
    dst.push(src[i]);
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

fn repeat_byte(b: Int, n: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < n {
    v.push(b as UInt8);
    i = i + 1;
  }
  return v;
}

fn set_at(src: &Vec[UInt8], pos: Int, v: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < src.len() {
    if i == pos {
      out.push(v as UInt8);
    } else {
      out.push(src[i]);
    }
    i = i + 1;
  }
  return out;
}

fn slice_of(src: &Vec[UInt8], start: Int, size: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < size {
    out.push(src[start + i]);
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

fn push_le16(dst: &mut Vec[UInt8], v: Int) {
  dst.push(byte_of(v, 0));
  dst.push(byte_of(v, 1));
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

fn push_varint(dst: &mut Vec[UInt8], v: Int) {
  var x = v;
  while x >= 128 {
    let b: Int = (x % 128) + 128;
    dst.push(b as UInt8);
    x = x / 128;
  }
  dst.push(x as UInt8);
}

// --------------------------------------------------
//  Independent CRC32C reference (bit-serial)
// --------------------------------------------------

fn crc_local_step(crc: Int, b: Int) -> Int {
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
    c = crc_local_step(c, gb(data, start + i));
    i = i + 1;
  }
  return (c ^ 4294967295) & 4294967295;
}

fn mask_local(crc: Int) -> Int {
  let rot = ((crc / 32768) + (crc % 32768) * 131072) & 4294967295;
  return (rot + 2726488792) & 4294967295;
}

fn crc_masked_local(data: &Vec[UInt8], start: Int, size: Int) -> Int {
  return mask_local(crc_local(data, start, size));
}

// --------------------------------------------------
//  Fixture builders
// --------------------------------------------------

// Entries + restart array of a valid data block (no trailer):
//   "apple"  -> "red"    (shared 0, 11 bytes at 0)
//   "apricot"-> "orange" (shared 2, 14 bytes at 11)
//   "banana" -> "yellow" (shared 0, 15 bytes at 25, restart)
//   "cat"    -> ""       (shared 0, 6 bytes at 40)
// entries_end = 46, restart array = u32 LE offsets [0, 25] then u32 LE
// count 2 (upstream LevelDB stores the offsets before the count), body 58.
fn data_block_body() -> Vec[UInt8] {
  var b = Vec[UInt8].new();
  push_varint(&mut b, 0); push_varint(&mut b, 5); push_varint(&mut b, 3);
  push_text(&mut b, "apple");
  push_text(&mut b, "red");
  push_varint(&mut b, 2); push_varint(&mut b, 5); push_varint(&mut b, 6);
  push_text(&mut b, "ricot");
  push_text(&mut b, "orange");
  push_varint(&mut b, 0); push_varint(&mut b, 6); push_varint(&mut b, 6);
  push_text(&mut b, "banana");
  push_text(&mut b, "yellow");
  push_varint(&mut b, 0); push_varint(&mut b, 3); push_varint(&mut b, 0);
  push_text(&mut b, "cat");
  push_le32(&mut b, 0); push_le32(&mut b, 25); push_le32(&mut b, 2);
  return b;
}

// Index-block body: "apple" -> handle(100, 50), "banana" -> handle(1000, 200).
// entries_end = 23, restart array = offsets [0, 10] then count 2, body 35.
fn index_block_body() -> Vec[UInt8] {
  var b = Vec[UInt8].new();
  push_varint(&mut b, 0); push_varint(&mut b, 5); push_varint(&mut b, 2);
  push_text(&mut b, "apple");
  push_varint(&mut b, 100); push_varint(&mut b, 50);
  push_varint(&mut b, 0); push_varint(&mut b, 6); push_varint(&mut b, 4);
  push_text(&mut b, "banana");
  push_varint(&mut b, 1000); push_varint(&mut b, 200);
  push_le32(&mut b, 0); push_le32(&mut b, 10); push_le32(&mut b, 2);
  return b;
}

// One physical log fragment: masked CRC32C u32 LE, u16 LE length, type byte,
// payload.
fn log_frag(payload: &Vec[UInt8], t: Int) -> Vec[UInt8] {
  var f = Vec[UInt8].new();
  push_le32(&mut f, crc_masked_local(payload, 0, payload.len()));
  push_le16(&mut f, payload.len());
  f.push(t as UInt8);
  append_bytes(&mut f, payload);
  return f;
}

// A short block that is exactly one fragment (feed handles short blocks).
fn block_of(frag: &Vec[UInt8]) -> Vec[UInt8] {
  var b = Vec[UInt8].new();
  append_bytes(&mut b, frag);
  return b;
}

// A fragment padded with zeros to a full 32768-byte block.
fn padded_block(frag: &Vec[UInt8]) -> Vec[UInt8] {
  var b = Vec[UInt8].new();
  append_bytes(&mut b, frag);
  if b.len() < 32768 {
    push_zeros(&mut b, 32768 - b.len());
  }
  return b;
}

// --------------------------------------------------
//  Result error helpers
// --------------------------------------------------

fn err_vint_is(r: Result[LevelDbVarint, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return str_eq(r.error, want);
}

fn err_ikey_is(r: Result[LevelDbInternalKey, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return str_eq(r.error, want);
}

fn err_entry_is(r: Result[LevelDbBlockEntry, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return str_eq(r.error, want);
}

fn err_restarts_is(r: Result[LevelDbBlockRestarts, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return str_eq(r.error, want);
}

fn err_bentries_is(r: Result[LevelDbBlockEntries, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return str_eq(r.error, want);
}

fn err_batch_is(r: Result[LevelDbLogBatch, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return str_eq(r.error, want);
}

fn err_footer_is(r: Result[LevelDbFooter, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return str_eq(r.error, want);
}

fn err_trailer_is(r: Result[LevelDbBlockTrailer, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return str_eq(r.error, want);
}

fn err_int_is(r: Result[Int, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return str_eq(r.error, want);
}

fn err_bytes_is(r: Result[Vec[UInt8], Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return str_eq(r.error, want);
}

fn err_lh_is(r: Result[LevelDbLogHeader, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return str_eq(r.error, want);
}

fn err_bhandle_is(r: Result[LevelDbBlockHandle, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return str_eq(r.error, want);
}

fn err_index_is(r: Result[LevelDbIndex, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return str_eq(r.error, want);
}

// --------------------------------------------------
//  t1: varint32 boundaries, consumed counts, encoders
// --------------------------------------------------

fn t1() -> TestResult {
  let name = "varint32: boundaries, consumed counts, round-trip";
  var ok = true;
  let cases = hb("007F8001FF01FFFF03808001FFFFFF7F8080808001FFFFFFFF0F");
  let starts = Vec[Int].new();
  starts.push(0); starts.push(1); starts.push(2); starts.push(4);
  starts.push(6); starts.push(9); starts.push(12); starts.push(16);
  starts.push(21);
  let wants = Vec[Int].new();
  wants.push(0); wants.push(127); wants.push(128); wants.push(255);
  wants.push(65535); wants.push(16384); wants.push(268435455);
  wants.push(268435456); wants.push(4294967295);
  let lens = Vec[Int].new();
  lens.push(1); lens.push(1); lens.push(2); lens.push(2);
  lens.push(3); lens.push(3); lens.push(4); lens.push(5); lens.push(5);
  var i = 0;
  while i < 9 {
    let p: Int = starts[i];
    let w: Int = wants[i];
    let l: Int = lens[i];
    let r = leveldb_parse_varint32(&cases, p);
    if !r.is_ok {
      ok = false;
    } else {
      let rv = r.value;
      if rv.value != w { ok = false; }
      if rv.size != l { ok = false; }
      if leveldb_varint32_size(w) != l { ok = false; }
    }
    i = i + 1;
  }
  let nc = leveldb_parse_varint32(&hb("8000"), 0);
  if !nc.is_ok { ok = false; } else {
    let nv = nc.value;
    if nv.value != 0 { ok = false; }
    if nv.size != 2 { ok = false; }
  }
  var enc = Vec[UInt8].new();
  if !leveldb_push_varint32(&mut enc, 4294967295) { ok = false; }
  if enc.len() != 5 { ok = false; }
  let back = leveldb_parse_varint32(&enc, 0);
  if !back.is_ok { ok = false; } else {
    let bv = back.value;
    if bv.value != 4294967295 { ok = false; }
  }
  var none = Vec[UInt8].new();
  if leveldb_push_varint32(&mut none, -1) { ok = false; }
  if leveldb_push_varint32(&mut none, 4294967296) { ok = false; }
  if none.len() != 0 { ok = false; }
  if leveldb_varint32_size(-1) != -1 { ok = false; }
  if leveldb_varint32_size(4294967296) != -1 { ok = false; }
  return assert(ok, name);
}

// --------------------------------------------------
//  t2: varint64 boundaries, Int-range and overflow rejection
// --------------------------------------------------

fn t2() -> TestResult {
  let name = "varint64: boundaries, Int-range and overflow rejection";
  var ok = true;
  let r0 = leveldb_parse_varint64(&hb("00"), 0);
  if !r0.is_ok { ok = false; } else {
    let v = r0.value;
    if v.value != 0 { ok = false; }
    if v.size != 1 { ok = false; }
  }
  let r1 = leveldb_parse_varint64(&hb("8001"), 0);
  if !r1.is_ok { ok = false; } else {
    let v = r1.value;
    if v.value != 128 { ok = false; }
    if v.size != 2 { ok = false; }
  }
  var enc = Vec[UInt8].new();
  push_varint(&mut enc, 1099511627776);
  if enc.len() != 6 { ok = false; }
  let r40 = leveldb_parse_varint64(&enc, 0);
  if !r40.is_ok { ok = false; } else {
    let v = r40.value;
    if v.value != 1099511627776 { ok = false; }
    if v.size != 6 { ok = false; }
  }
  var mx = Vec[UInt8].new();
  push_varint(&mut mx, 9223372036854775807);
  if mx.len() != 9 { ok = false; }
  let rmx = leveldb_parse_varint64(&mx, 0);
  if !rmx.is_ok { ok = false; } else {
    let v = rmx.value;
    if v.value != 9223372036854775807 { ok = false; }
    if v.size != 9 { ok = false; }
  }
  var ex = Vec[UInt8].new();
  var i = 0;
  while i < 9 {
    ex.push(255 as UInt8);
    i = i + 1;
  }
  ex.push(1 as UInt8);
  if !err_vint_is(leveldb_parse_varint64(&ex, 0), "varint64: value exceeds Int range at 0") { ok = false; }
  let ovf = set_at(&ex, 9, 2);
  if !err_vint_is(leveldb_parse_varint64(&ovf, 0), "varint64: overflow at 0") { ok = false; }
  let ovc = set_at(&ex, 9, 129);
  if !err_vint_is(leveldb_parse_varint64(&ovc, 0), "varint64: overflow at 0") { ok = false; }
  if !err_vint_is(leveldb_parse_varint64(&hb("80"), 0), "varint64: truncated at 0") { ok = false; }
  var none = Vec[UInt8].new();
  if leveldb_push_varint64(&mut none, -1) { ok = false; }
  if none.len() != 0 { ok = false; }
  if leveldb_varint64_size(1099511627776) != 6 { ok = false; }
  if leveldb_varint64_size(9223372036854775807) != 9 { ok = false; }
  if leveldb_varint64_size(-1) != -1 { ok = false; }
  return assert(ok, name);
}

// --------------------------------------------------
//  t3: malformed varints carry the byte offset
// --------------------------------------------------

fn t3() -> TestResult {
  let name = "varint: malformed inputs and byte-offset errors";
  var ok = true;
  if !err_vint_is(leveldb_parse_varint32(&hb("80"), 0), "varint32: truncated at 0") { ok = false; }
  if !err_vint_is(leveldb_parse_varint32(&hb("0180"), 1), "varint32: truncated at 1") { ok = false; }
  if !err_vint_is(leveldb_parse_varint32(&hb("FFFFFFFF10"), 0), "varint32: overflow at 0") { ok = false; }
  if !err_vint_is(leveldb_parse_varint32(&hb("FFFFFFFF80"), 0), "varint32: overflow at 0") { ok = false; }
  if !err_vint_is(leveldb_parse_varint64(&hb("010280"), 2), "varint64: truncated at 2") { ok = false; }
  let big = leveldb_parse_varint32(&hb("FFFFFFFF0F"), 0);
  if !big.is_ok { ok = false; } else {
    let bv = big.value;
    if bv.value != 4294967295 { ok = false; }
  }
  return assert(ok, name);
}

// --------------------------------------------------
//  t4: internal keys: tag layout, type table, comparator
// --------------------------------------------------

fn t4() -> TestResult {
  let name = "internal keys: tag layout, type table, comparator";
  var ok = true;
  let uk = text("user");
  let er = leveldb_internal_key_encode(&uk, 5, 1);
  if !er.is_ok { ok = false; } else {
    let ek = er.value;
    if ek.len() != 12 { ok = false; }
    let pr = leveldb_parse_internal_key(&ek);
    if !pr.is_ok { ok = false; } else {
      let k = pr.value;
      let user = leveldb_internal_key_user_key(&k);
      if !bytes_eq(&user, &uk) { ok = false; }
      if leveldb_internal_key_sequence(&k) != 5 { ok = false; }
      if leveldb_internal_key_type(&k) != 1 { ok = false; }
      if k.tag != 1281 { ok = false; }
      if !str_eq(leveldb_internal_key_type_name(k.ktype), "VALUE") { ok = false; }
    }
  }
  let hand = hb("757365720105000000000000");
  let hr = leveldb_parse_internal_key(&hand);
  if !hr.is_ok { ok = false; } else {
    let hk = hr.value;
    if leveldb_internal_key_sequence(&hk) != 5 { ok = false; }
    if leveldb_internal_key_type(&hk) != 1 { ok = false; }
    if hk.tag != 1281 { ok = false; }
  }
  if !err_ikey_is(leveldb_parse_internal_key(&hb("01020304050607")), "internal key: too short at 0") { ok = false; }
  if !err_ikey_is(leveldb_parse_internal_key(&hb("757365720105000000000080")), "internal key: tag exceeds Int range at 4") { ok = false; }
  if !err_bytes_is(leveldb_internal_key_encode(&zeros(0), 5, 1), "internal key: empty user key at 0") { ok = false; }
  if !err_bytes_is(leveldb_internal_key_encode(&uk, 5, 7), "internal key: bad type at 0") { ok = false; }
  if !err_bytes_is(leveldb_internal_key_encode(&uk, -1, 1), "internal key: bad sequence at 0") { ok = false; }
  if leveldb_internal_key_tag(5, 1) != 1281 { ok = false; }
  if leveldb_internal_key_tag(-1, 1) != -1 { ok = false; }
  if leveldb_internal_key_tag(5, 9) != -1 { ok = false; }
  if !leveldb_internal_key_valid_type(0) { ok = false; }
  if !leveldb_internal_key_valid_type(1) { ok = false; }
  if leveldb_internal_key_valid_type(2) { ok = false; }
  if !str_eq(leveldb_internal_key_type_name(0), "DELETION") { ok = false; }
  if !str_eq(leveldb_internal_key_type_name(9), "") { ok = false; }
  // Comparator: same user key, higher sequence first; VALUE before DELETION.
  let a = leveldb_parse_internal_key(&hb("6B0105000000000000"));
  let b = leveldb_parse_internal_key(&hb("6B0104000000000000"));
  let c = leveldb_parse_internal_key(&hb("6B0005000000000000"));
  let d = leveldb_parse_internal_key(&hb("6C0000000000000000"));
  if !a.is_ok || !b.is_ok || !c.is_ok || !d.is_ok {
    ok = false;
  } else {
    let ka = a.value;
    let kb = b.value;
    let kc = c.value;
    let kd = d.value;
    if leveldb_internal_key_compare(&ka, &kb) != -1 { ok = false; }
    if leveldb_internal_key_compare(&kb, &ka) != 1 { ok = false; }
    if leveldb_internal_key_compare(&ka, &ka) != 0 { ok = false; }
    if leveldb_internal_key_compare(&ka, &kc) != -1 { ok = false; }
    if leveldb_internal_key_compare(&kc, &ka) != 1 { ok = false; }
    if leveldb_internal_key_compare(&ka, &kd) != -1 { ok = false; }
  }
  let x = text("abc");
  let y = text("abd");
  let z = text("ab");
  if leveldb_bytewise_compare(&x, &x) != 0 { ok = false; }
  if leveldb_bytewise_compare(&x, &y) != -1 { ok = false; }
  if leveldb_bytewise_compare(&y, &x) != 1 { ok = false; }
  if leveldb_bytewise_compare(&z, &x) != -1 { ok = false; }
  if leveldb_bytewise_compare(&x, &z) != 1 { ok = false; }
  return assert(ok, name);
}

// --------------------------------------------------
//  t5: CRC32C vectors and the LevelDB mask
// --------------------------------------------------

fn t5() -> TestResult {
  let name = "crc32c: known-answer vectors, mask/unmask, range";
  var ok = true;
  if leveldb_crc32c(&zeros(0), 0, 0) != 0 { ok = false; }
  let kat = text("123456789");
  if leveldb_crc32c(&kat, 0, 9) != 3808858755 { ok = false; }
  if leveldb_crc32c_masked(&kat, 0, 9) != 3347755237 { ok = false; }
  if leveldb_mask_crc32c(0) != 2726488792 { ok = false; }
  if leveldb_unmask_crc32c(2726488792) != 0 { ok = false; }
  if leveldb_unmask_crc32c(3347755237) != 3808858755 { ok = false; }
  if leveldb_crc32c_masked(&hb("00"), 0, 1) != 1227198418 { ok = false; }
  if leveldb_crc32c_masked(&hb("FF"), 0, 1) != 2726619352 { ok = false; }
  let kats = hb("000102");
  if leveldb_crc32c(&kats, 0, 3) != 2466073594 { ok = false; }
  var seq = Vec[UInt8].new();
  var i = 0;
  while i < 256 {
    seq.push(i as UInt8);
    i = i + 1;
  }
  if leveldb_crc32c(&seq, 0, 256) != crc_local(&seq, 0, 256) { ok = false; }
  if leveldb_crc32c_masked(&seq, 0, 256) != crc_masked_local(&seq, 0, 256) { ok = false; }
  let rt = Vec[Int].new();
  rt.push(0); rt.push(1); rt.push(3808858755); rt.push(4294967295);
  var j = 0;
  while j < 4 {
    let x: Int = rt[j];
    if leveldb_mask_crc32c(leveldb_unmask_crc32c(x)) != x { ok = false; }
    j = j + 1;
  }
  if leveldb_crc32c(&seq, 250, 10) != -1 { ok = false; }
  if leveldb_crc32c(&seq, -1, 1) != -1 { ok = false; }
  if leveldb_mask_crc32c(-1) != -1 { ok = false; }
  if leveldb_mask_crc32c(4294967296) != -1 { ok = false; }
  if leveldb_unmask_crc32c(-5) != -1 { ok = false; }
  return assert(ok, name);
}

// --------------------------------------------------
//  t6: 7-byte log header
// --------------------------------------------------

fn t6() -> TestResult {
  let name = "log header: fields, CRC, type table, truncation";
  var ok = true;
  let p = text("abc");
  let frag = log_frag(&p, 1);
  if frag.len() != 10 { ok = false; }
  let hr = leveldb_parse_log_header(&frag, 0);
  if !hr.is_ok {
    return assert(false, name);
  }
  let h = hr.value;
  if h.crc != crc_masked_local(&p, 0, 3) { ok = false; }
  if h.length != 3 { ok = false; }
  if h.rtype != 1 { ok = false; }
  if !leveldb_log_fragment_crc_ok(&frag, 0) { ok = false; }
  let cor = set_at(&frag, 9, 0);
  if leveldb_log_fragment_crc_ok(&cor, 0) { ok = false; }
  if !str_eq(leveldb_log_record_type_name(1), "FULL") { ok = false; }
  if !str_eq(leveldb_log_record_type_name(2), "FIRST") { ok = false; }
  if !str_eq(leveldb_log_record_type_name(3), "MIDDLE") { ok = false; }
  if !str_eq(leveldb_log_record_type_name(4), "LAST") { ok = false; }
  if !str_eq(leveldb_log_record_type_name(0), "") { ok = false; }
  if !str_eq(leveldb_log_record_type_name(5), "") { ok = false; }
  if !err_lh_is(leveldb_parse_log_header(&frag, 4), "log header: truncated at 4") { ok = false; }
  if !err_lh_is(leveldb_parse_log_header(&hb("010203040506"), 0), "log header: truncated at 0") { ok = false; }
  let t0 = set_at(&frag, 6, 0);
  if !err_lh_is(leveldb_parse_log_header(&t0, 0), "log header: bad record type at 0") { ok = false; }
  let t5 = set_at(&frag, 6, 5);
  if !err_lh_is(leveldb_parse_log_header(&t5, 0), "log header: bad record type at 0") { ok = false; }
  let over = set_at(&frag, 4, 100);
  if !err_lh_is(leveldb_parse_log_header(&over, 0), "log record: length overruns block at 0") { ok = false; }
  return assert(ok, name);
}

// --------------------------------------------------
//  t7: log feed of FULL records and trailers
// --------------------------------------------------

fn t7() -> TestResult {
  let name = "log feed: FULL record, base offsets, trailers";
  var ok = true;
  let p = text("hello-leveldb");
  let frag = log_frag(&p, 1);
  if frag.len() != 20 { ok = false; }
  let blk = padded_block(&frag);
  if blk.len() != 32768 { ok = false; }
  let st = leveldb_log_state_new();
  let fr = leveldb_log_feed(&blk, 0, &st, true);
  if !fr.is_ok {
    return assert(false, name);
  }
  let fb = fr.value;
  if fb.payloads.len() != 1 { ok = false; } else {
    let one: Vec[UInt8] = fb.payloads[0];
    if !bytes_eq(&one, &p) { ok = false; }
  }
  if fb.rtypes.len() != 1 { ok = false; } else {
    let rt0: Int = fb.rtypes[0];
    if rt0 != 1 { ok = false; }
  }
  if fb.starts.len() != 1 { ok = false; } else {
    let s0: Int = fb.starts[0];
    if s0 != 0 { ok = false; }
  }
  if fb.ends.len() != 1 { ok = false; } else {
    let e0: Int = fb.ends[0];
    if e0 != 20 { ok = false; }
  }
  if fb.next_have { ok = false; }
  if fb.next_start != -1 { ok = false; }
  let fr2 = leveldb_log_feed(&blk, 32768, &st, true);
  if !fr2.is_ok { ok = false; } else {
    let f2 = fr2.value;
    if f2.starts.len() != 1 { ok = false; } else {
      let s0: Int = f2.starts[0];
      if s0 != 32768 { ok = false; }
    }
    if f2.ends.len() != 1 { ok = false; } else {
      let e0: Int = f2.ends[0];
      if e0 != 32788 { ok = false; }
    }
  }
  // CRC checking can be disabled: a corrupted stored CRC parses fine.
  let badcrc = set_at(&frag, 0, 9);
  let badblk = padded_block(&badcrc);
  let fr3 = leveldb_log_feed(&badblk, 0, &st, false);
  if !fr3.is_ok { ok = false; }
  let fr4 = leveldb_log_feed(&badblk, 0, &st, true);
  if !err_batch_is(fr4, "log: crc mismatch at 0") { ok = false; }
  // Short zero trailer (< 7 bytes) is accepted; nonzero is rejected.
  let short = block_of(&frag);
  let fr5 = leveldb_log_feed(&short, 0, &st, true);
  if !fr5.is_ok { ok = false; } else {
    let f5 = fr5.value;
    if f5.payloads.len() != 1 { ok = false; }
  }
  var dirty = block_of(&frag);
  dirty.push(9 as UInt8);
  if !err_batch_is(leveldb_log_feed(&dirty, 0, &st, true), "log: nonzero trailer at 20") { ok = false; }
  // An all-zero block is a trailer: no records, no error.
  let none = leveldb_log_feed(&zeros(40), 0, &st, true);
  if !none.is_ok { ok = false; } else {
    let nz = none.value;
    if nz.payloads.len() != 0 { ok = false; }
    if nz.next_have { ok = false; }
  }
  return assert(ok, name);
}

// --------------------------------------------------
//  t8: FIRST/MIDDLE/LAST reassembly across blocks
// --------------------------------------------------

fn t8() -> TestResult {
  let name = "log feed: FIRST/MIDDLE/LAST reassembly across blocks";
  var ok = true;
  let st0 = leveldb_log_state_new();
  let fa = log_frag(&text("ABCDE"), 2);
  let blk_a = padded_block(&fa);
  let ra = leveldb_log_feed(&blk_a, 0, &st0, true);
  if !ra.is_ok {
    return assert(false, name);
  }
  let ba = ra.value;
  if ba.payloads.len() != 0 { ok = false; }
  if !ba.next_have { ok = false; }
  if ba.next_start != 0 { ok = false; }
  let carry: Vec[UInt8] = ba.next_partial;
  if !bytes_eq(&carry, &text("ABCDE")) { ok = false; }
  let st_a = LevelDbLogState{ have_partial: true; partial: carry; start: 0; };
  var block_b = Vec[UInt8].new();
  let fm = log_frag(&text("FGHIJ"), 3);
  let fl = log_frag(&text("KLMN"), 4);
  let ff = log_frag(&text("tail"), 1);
  append_bytes(&mut block_b, &fm);
  append_bytes(&mut block_b, &fl);
  append_bytes(&mut block_b, &ff);
  if block_b.len() != 34 { ok = false; }
  push_zeros(&mut block_b, 32768 - block_b.len());
  let rb = leveldb_log_feed(&block_b, 32768, &st_a, true);
  if !rb.is_ok {
    return assert(false, name);
  }
  let bb = rb.value;
  if bb.payloads.len() != 2 { ok = false; } else {
    let p0: Vec[UInt8] = bb.payloads[0];
    let p1: Vec[UInt8] = bb.payloads[1];
    if !bytes_eq(&p0, &text("ABCDEFGHIJKLMN")) { ok = false; }
    if !bytes_eq(&p1, &text("tail")) { ok = false; }
  }
  if bb.rtypes.len() != 2 { ok = false; } else {
    let r0: Int = bb.rtypes[0];
    let r1: Int = bb.rtypes[1];
    if r0 != 4 { ok = false; }
    if r1 != 1 { ok = false; }
  }
  if bb.starts.len() != 2 { ok = false; } else {
    let s0: Int = bb.starts[0];
    let s1: Int = bb.starts[1];
    if s0 != 0 { ok = false; }
    if s1 != 32791 { ok = false; }
  }
  if bb.ends.len() != 2 { ok = false; } else {
    let e0: Int = bb.ends[0];
    let e1: Int = bb.ends[1];
    if e0 != 32791 { ok = false; }
    if e1 != 32802 { ok = false; }
  }
  if bb.next_have { ok = false; }
  let carry2: Vec[UInt8] = bb.next_partial;
  let st_b = LevelDbLogState{ have_partial: false; partial: carry2; start: -1; };
  let fin_a = leveldb_log_finish(&st_a);
  if !err_int_is(fin_a, "log: incomplete fragmented record at 0") { ok = false; }
  let fin_b = leveldb_log_finish(&st_b);
  if !fin_b.is_ok { ok = false; }
  return assert(ok, name);
}

// --------------------------------------------------
//  t9: log sequencing and CRC errors
// --------------------------------------------------

fn t9() -> TestResult {
  let name = "log feed: sequencing, CRC and length errors";
  var ok = true;
  let st = leveldb_log_state_new();
  let full = padded_block(&log_frag(&text("hello"), 1));
  if !err_batch_is(leveldb_log_feed(&padded_block(&log_frag(&text("hello"), 3)), 0, &st, true), "log: MIDDLE without FIRST at 0") { ok = false; }
  if !err_batch_is(leveldb_log_feed(&padded_block(&log_frag(&text("hello"), 4)), 0, &st, true), "log: LAST without FIRST at 0") { ok = false; }
  let corrupt = set_at(&full, 9, 0);
  if !err_batch_is(leveldb_log_feed(&corrupt, 0, &st, true), "log: crc mismatch at 0") { ok = false; }
  var badtype = Vec[UInt8].new();
  push_le32(&mut badtype, 1);
  push_le16(&mut badtype, 3);
  badtype.push(7 as UInt8);
  push_text(&mut badtype, "abc");
  push_zeros(&mut badtype, 32768 - badtype.len());
  if !err_batch_is(leveldb_log_feed(&badtype, 0, &st, true), "log header: bad record type at 0") { ok = false; }
  var over = Vec[UInt8].new();
  push_le32(&mut over, 1);
  push_le16(&mut over, 40000);
  over.push(1 as UInt8);
  push_zeros(&mut over, 32768 - over.len());
  if !err_batch_is(leveldb_log_feed(&over, 0, &st, true), "log record: length overruns block at 0") { ok = false; }
  let ra = leveldb_log_feed(&padded_block(&log_frag(&text("AB"), 2)), 0, &st, true);
  if !ra.is_ok { return assert(false, name); }
  let ba = ra.value;
  let carry: Vec[UInt8] = ba.next_partial;
  let open = LevelDbLogState{ have_partial: true; partial: carry; start: 0; };
  if !err_batch_is(leveldb_log_feed(&full, 32768, &open, true), "log: unexpected FULL in fragmented record at 32768") { ok = false; }
  let first2 = padded_block(&log_frag(&text("XY"), 2));
  if !err_batch_is(leveldb_log_feed(&first2, 32768, &open, true), "log: FIRST while fragment open at 32768") { ok = false; }
  return assert(ok, name);
}

// --------------------------------------------------
//  t10: 32 KiB block boundary rule
// --------------------------------------------------

fn t10() -> TestResult {
  let name = "log boundary: 32 KiB remainder and fragment fit";
  var ok = true;
  if leveldb_log_block_size() != 32768 { ok = false; }
  if leveldb_log_block_remainder(0) != 32768 { ok = false; }
  if leveldb_log_block_remainder(1) != 32767 { ok = false; }
  if leveldb_log_block_remainder(32767) != 1 { ok = false; }
  if leveldb_log_block_remainder(32768) != 32768 { ok = false; }
  if leveldb_log_block_remainder(32769) != 32767 { ok = false; }
  if leveldb_log_block_remainder(-1) != -1 { ok = false; }
  if !leveldb_log_fits_in_block(0, 32761) { ok = false; }
  if leveldb_log_fits_in_block(0, 32762) { ok = false; }
  if leveldb_log_fits_in_block(32767, 0) { ok = false; }
  if !leveldb_log_fits_in_block(32761, 0) { ok = false; }
  if leveldb_log_fits_in_block(-1, 0) { ok = false; }
  if leveldb_log_fits_in_block(0, -1) { ok = false; }
  // A fragment whose payload exactly fills the block is accepted.
  let big = log_frag(&zeros(32761), 1);
  if big.len() != 32768 { ok = false; }
  let st = leveldb_log_state_new();
  let fr = leveldb_log_feed(&big, 0, &st, true);
  if !fr.is_ok { ok = false; } else {
    let fb = fr.value;
    if fb.payloads.len() != 1 { ok = false; } else {
      let p0: Vec[UInt8] = fb.payloads[0];
      if p0.len() != 32761 { ok = false; }
    }
    if fb.ends.len() != 1 { ok = false; } else {
      let e0: Int = fb.ends[0];
      if e0 != 32768 { ok = false; }
    }
  }
  // A header at offset 32761 that claims 5 payload bytes crosses the
  // boundary: 32761 + 7 + 5 > 32768.
  var edge = Vec[UInt8].new();
  push_zeros(&mut edge, 32761);
  push_le32(&mut edge, 0);
  push_le16(&mut edge, 5);
  edge.push(1 as UInt8);
  if edge.len() != 32768 { ok = false; }
  if !err_lh_is(leveldb_parse_log_header(&edge, 32761), "log record: length overruns block at 32761") { ok = false; }
  return assert(ok, name);
}

// --------------------------------------------------
//  t11: block entry parsing
// --------------------------------------------------

fn t11() -> TestResult {
  let name = "block entry: prefix compression, consumed counts, bounds";
  var ok = true;
  let body = data_block_body();
  if body.len() != 58 { ok = false; }
  let empty = Vec[UInt8].new();
  let e1r = leveldb_parse_block_entry(&body, 0, 46, &empty);
  if !e1r.is_ok {
    return assert(false, name);
  }
  let e1 = e1r.value;
  if e1.shared_len != 0 { ok = false; }
  if e1.non_shared_len != 5 { ok = false; }
  if e1.value_len != 3 { ok = false; }
  if e1.entry_bytes != 11 { ok = false; }
  if e1.value_offset != 8 { ok = false; }
  let k1: Vec[UInt8] = e1.key;
  if !bytes_eq(&k1, &text("apple")) { ok = false; }
  let v1 = leveldb_block_entry_value(&body, &e1);
  if !bytes_eq(&v1, &text("red")) { ok = false; }
  let e2r = leveldb_parse_block_entry(&body, 11, 46, &k1);
  if !e2r.is_ok { ok = false; } else {
    let e2 = e2r.value;
    if e2.shared_len != 2 { ok = false; }
    if e2.non_shared_len != 5 { ok = false; }
    if e2.value_len != 6 { ok = false; }
    if e2.entry_bytes != 14 { ok = false; }
    if e2.value_offset != 19 { ok = false; }
    let k2: Vec[UInt8] = e2.key;
    if !bytes_eq(&k2, &text("apricot")) { ok = false; }
    let v2 = leveldb_block_entry_value(&body, &e2);
    if !bytes_eq(&v2, &text("orange")) { ok = false; }
    let e3r = leveldb_parse_block_entry(&body, 25, 46, &k2);
    if !e3r.is_ok { ok = false; } else {
      let e3 = e3r.value;
      if e3.shared_len != 0 { ok = false; }
      if e3.entry_bytes != 15 { ok = false; }
      if e3.value_offset != 34 { ok = false; }
      let k3: Vec[UInt8] = e3.key;
      if !bytes_eq(&k3, &text("banana")) { ok = false; }
      let v3 = leveldb_block_entry_value(&body, &e3);
      if !bytes_eq(&v3, &text("yellow")) { ok = false; }
    }
  }
  let e4r = leveldb_parse_block_entry(&body, 40, 46, &text("z"));
  if !e4r.is_ok { ok = false; } else {
    let e4 = e4r.value;
    if e4.shared_len != 0 { ok = false; }
    if e4.value_len != 0 { ok = false; }
    if e4.entry_bytes != 6 { ok = false; }
    if e4.value_offset != 46 { ok = false; }
    let k4: Vec[UInt8] = e4.key;
    if !bytes_eq(&k4, &text("cat")) { ok = false; }
  }
  if !err_entry_is(leveldb_parse_block_entry(&body, 11, 46, &empty), "block entry: shared beyond previous key at 11") { ok = false; }
  if !err_entry_is(leveldb_parse_block_entry(&hb("00090161"), 0, 4, &empty), "block entry: key overrun at 0") { ok = false; }
  if !err_entry_is(leveldb_parse_block_entry(&hb("0001056162"), 0, 6, &empty), "block entry: value overrun at 0") { ok = false; }
  if !err_entry_is(leveldb_parse_block_entry(&hb("02"), 0, 1, &empty), "block entry: truncated at 1") { ok = false; }
  if !err_entry_is(leveldb_parse_block_entry(&hb("FFFFFFFF10"), 0, 5, &empty), "block entry: overflow at 0") { ok = false; }
  return assert(ok, name);
}

// --------------------------------------------------
//  t12: restart array parsing
// --------------------------------------------------

fn t12() -> TestResult {
  let name = "block restarts: offsets, entries_end and malformed arrays";
  var ok = true;
  let body = data_block_body();
  let rr = leveldb_parse_block_restarts(&body);
  if !rr.is_ok {
    return assert(false, name);
  }
  let rv = rr.value;
  if rv.count != 2 { ok = false; }
  if rv.entries_end != 46 { ok = false; }
  if rv.offsets.len() != 2 { ok = false; } else {
    let o0: Int = rv.offsets[0];
    let o1: Int = rv.offsets[1];
    if o0 != 0 { ok = false; }
    if o1 != 25 { ok = false; }
  }
  if !err_restarts_is(leveldb_parse_block_restarts(&zeros(3)), "block restarts: truncated at 0") { ok = false; }
  if !err_restarts_is(leveldb_parse_block_restarts(&hb("00000000")), "block restarts: zero count at 0") { ok = false; }
  if !err_restarts_is(leveldb_parse_block_restarts(&hb("02000000")), "block restarts: bad count at 0") { ok = false; }
  if !err_restarts_is(leveldb_parse_block_restarts(&hb("000000000400000001000000")), "block restarts: first offset is not zero at 4") { ok = false; }
  if !err_restarts_is(leveldb_parse_block_restarts(&hb("0000000000000000000000000000000002000000")), "block restarts: offsets not increasing at 12") { ok = false; }
  if !err_restarts_is(leveldb_parse_block_restarts(&hb("00000000000000000900000001000000")), "block restarts: offset out of range at 8") { ok = false; }
  let empty_r = leveldb_parse_block_restarts(&hb("0000000001000000"));
  if !empty_r.is_ok { ok = false; } else {
    let er = empty_r.value;
    if er.count != 1 { ok = false; }
    if er.entries_end != 0 { ok = false; }
  }
  return assert(ok, name);
}

// --------------------------------------------------
//  t13: whole-block iteration over restart points
// --------------------------------------------------

fn t13() -> TestResult {
  let name = "block entries: parallel vectors and restart-point checks";
  var ok = true;
  let body = data_block_body();
  let wr = leveldb_parse_block_entries(&body);
  if !wr.is_ok {
    return assert(false, name);
  }
  let w = wr.value;
  if leveldb_block_entries_count(&w) != 4 { ok = false; }
  if w.shared_lens.len() != 4 { ok = false; } else {
    let sh0: Int = w.shared_lens[0];
    let sh1: Int = w.shared_lens[1];
    let sh2: Int = w.shared_lens[2];
    let sh3: Int = w.shared_lens[3];
    if sh0 != 0 { ok = false; }
    if sh1 != 2 { ok = false; }
    if sh2 != 0 { ok = false; }
    if sh3 != 0 { ok = false; }
  }
  let k0 = leveldb_block_entries_key(&w, 0);
  let k1 = leveldb_block_entries_key(&w, 1);
  let k2 = leveldb_block_entries_key(&w, 2);
  let k3 = leveldb_block_entries_key(&w, 3);
  if !bytes_eq(&k0, &text("apple")) { ok = false; }
  if !bytes_eq(&k1, &text("apricot")) { ok = false; }
  if !bytes_eq(&k2, &text("banana")) { ok = false; }
  if !bytes_eq(&k3, &text("cat")) { ok = false; }
  let v0 = leveldb_block_entries_value(&body, &w, 0);
  let v1 = leveldb_block_entries_value(&body, &w, 1);
  let v2 = leveldb_block_entries_value(&body, &w, 2);
  let v3 = leveldb_block_entries_value(&body, &w, 3);
  if !bytes_eq(&v0, &text("red")) { ok = false; }
  if !bytes_eq(&v1, &text("orange")) { ok = false; }
  if !bytes_eq(&v2, &text("yellow")) { ok = false; }
  if v3.len() != 0 { ok = false; }
  if leveldb_block_entries_entry_offset(&w, 0) != 0 { ok = false; }
  if leveldb_block_entries_entry_offset(&w, 1) != 11 { ok = false; }
  if leveldb_block_entries_entry_offset(&w, 2) != 25 { ok = false; }
  if leveldb_block_entries_entry_offset(&w, 3) != 40 { ok = false; }
  if leveldb_block_entries_restart_index(&w, 0) != 0 { ok = false; }
  if leveldb_block_entries_restart_index(&w, 1) != 2 { ok = false; }
  if leveldb_block_entries_restart_index(&w, 2) != -1 { ok = false; }
  if leveldb_block_entries_shared(&w, 1) != 2 { ok = false; }
  if leveldb_block_entries_shared(&w, 4) != -1 { ok = false; }
  if leveldb_block_entries_key(&w, -1).len() != 0 { ok = false; }
  let bad_off = set_at(&body, 50, 26);
  if !err_bentries_is(leveldb_parse_block_entries(&bad_off), "block: restart offset misses entry boundary at 26") { ok = false; }
  let bad_shared = set_at(&body, 50, 11);
  if !err_bentries_is(leveldb_parse_block_entries(&bad_shared), "block: restart entry with shared bytes at 11") { ok = false; }
  let er0 = leveldb_block_entry_at_restart(&body, 0);
  if !er0.is_ok { ok = false; } else {
    let e0 = er0.value;
    let ek0: Vec[UInt8] = e0.key;
    if !bytes_eq(&ek0, &text("apple")) { ok = false; }
  }
  let er1 = leveldb_block_entry_at_restart(&body, 1);
  if !er1.is_ok { ok = false; } else {
    let e1 = er1.value;
    let ek1: Vec[UInt8] = e1.key;
    if !bytes_eq(&ek1, &text("banana")) { ok = false; }
  }
  if !err_entry_is(leveldb_block_entry_at_restart(&body, 2), "block: restart index out of range at 2") { ok = false; }
  if !err_entry_is(leveldb_block_entry_at_restart(&body, -1), "block: restart index out of range at -1") { ok = false; }
  let empty_body = hb("0000000001000000");
  let ew = leveldb_parse_block_entries(&empty_body);
  if !ew.is_ok { ok = false; } else {
    let ewb = ew.value;
    if ewb.count != 0 { ok = false; }
    if ewb.restart_indices.len() != 0 { ok = false; }
  }
  return assert(ok, name);
}

// --------------------------------------------------
//  t14: block trailer
// --------------------------------------------------

fn t14() -> TestResult {
  let name = "block trailer: compression flag, CRC, truncation";
  var ok = true;
  let body = data_block_body();
  var tr = Vec[UInt8].new();
  tr.push(0 as UInt8);
  push_le32(&mut tr, crc_masked_local(&body, 0, body.len()));
  if tr.len() != 5 { ok = false; }
  let trr = leveldb_parse_block_trailer(&tr, 0);
  if !trr.is_ok {
    return assert(false, name);
  }
  let t0 = trr.value;
  if t0.compression != 0 { ok = false; }
  if t0.crc != crc_masked_local(&body, 0, body.len()) { ok = false; }
  if !leveldb_block_trailer_crc_ok(&body, &t0) { ok = false; }
  let snappy = set_at(&tr, 0, 1);
  let trs = leveldb_parse_block_trailer(&snappy, 0);
  if !trs.is_ok { ok = false; } else {
    let ts = trs.value;
    if ts.compression != 1 { ok = false; }
    if leveldb_block_trailer_crc_ok(&body, &ts) { ok = false; }
  }
  let unk = set_at(&tr, 0, 2);
  if !err_trailer_is(leveldb_parse_block_trailer(&unk, 0), "block trailer: unknown compression at 0") { ok = false; }
  if !err_trailer_is(leveldb_parse_block_trailer(&hb("00000000"), 0), "block trailer: truncated at 0") { ok = false; }
  if !err_trailer_is(leveldb_parse_block_trailer(&hb("0000000000"), 1), "block trailer: truncated at 1") { ok = false; }
  let corrupt = set_at(&body, 5, 200);
  if leveldb_block_trailer_crc_ok(&corrupt, &t0) { ok = false; }
  return assert(ok, name);
}

// --------------------------------------------------
//  t15: 48-byte footer, fixed-width layout
// --------------------------------------------------

fn t15() -> TestResult {
  let name = "footer fixed: round-trip, magic, padding, handle range";
  var ok = true;
  let f = leveldb_build_footer(100, 50, 200, 60);
  if f.len() != 48 { ok = false; }
  if !leveldb_table_magic_ok(&f, 40) { ok = false; }
  if leveldb_table_magic_ok(&f, 41) { ok = false; }
  let df = leveldb_parse_footer(&f);
  if !df.is_ok {
    return assert(false, name);
  }
  let d0 = df.value;
  if d0.metaindex_offset != 100 { ok = false; }
  if d0.metaindex_size != 50 { ok = false; }
  if d0.index_offset != 200 { ok = false; }
  if d0.index_size != 60 { ok = false; }
  let bm = set_at(&f, 40, 0);
  if !err_footer_is(leveldb_parse_footer(&bm), "footer: bad magic at 40") { ok = false; }
  let pad = set_at(&f, 35, 9);
  if !err_footer_is(leveldb_parse_footer(&pad), "footer: nonzero padding at 35") { ok = false; }
  let trunc = slice_of(&f, 0, 47);
  if !err_footer_is(leveldb_parse_footer(&trunc), "footer: truncated at 0") { ok = false; }
  let big = set_at(&f, 7, 128);
  if !err_footer_is(leveldb_parse_footer(&big), "footer: metaindex offset exceeds Int range at 0") { ok = false; }
  let big2 = set_at(&f, 31, 128);
  if !err_footer_is(leveldb_parse_footer(&big2), "footer: index size exceeds Int range at 24") { ok = false; }
  let chk = leveldb_footer_check(&d0, 1000);
  if !chk.is_ok { ok = false; }
  let f2 = leveldb_build_footer(100, 50, 200, 60);
  let d2r = leveldb_parse_footer(&f2);
  if !d2r.is_ok { ok = false; } else {
    let d2 = d2r.value;
    if !err_int_is(leveldb_footer_check(&d2, 210), "footer: index handle out of range at 200") { ok = false; }
  }
  if !err_int_is(leveldb_footer_check(&d0, -1), "footer: negative file size at 0") { ok = false; }
  return assert(ok, name);
}

// --------------------------------------------------
//  t16: 48-byte footer, LEB128 layout
// --------------------------------------------------

fn t16() -> TestResult {
  let name = "footer varint: round-trip, bounded handles, padding";
  var ok = true;
  let fv = leveldb_build_footer_varint(100, 50, 200, 60);
  if fv.len() != 48 { ok = false; }
  if gb(&fv, 0) != 100 { ok = false; }
  if gb(&fv, 1) != 50 { ok = false; }
  if gb(&fv, 2) != 200 { ok = false; }
  if gb(&fv, 3) != 1 { ok = false; }
  if gb(&fv, 4) != 60 { ok = false; }
  if gb(&fv, 20) != 0 { ok = false; }
  if gb(&fv, 39) != 0 { ok = false; }
  if !leveldb_table_magic_ok(&fv, 40) { ok = false; }
  let df = leveldb_parse_footer_varint(&fv);
  if !df.is_ok {
    return assert(false, name);
  }
  let d0 = df.value;
  if d0.metaindex_offset != 100 { ok = false; }
  if d0.metaindex_size != 50 { ok = false; }
  if d0.index_offset != 200 { ok = false; }
  if d0.index_size != 60 { ok = false; }
  let bm = set_at(&fv, 40, 0);
  if !err_footer_is(leveldb_parse_footer_varint(&bm), "footer: bad magic at 40") { ok = false; }
  let pad = set_at(&fv, 20, 7);
  if !err_footer_is(leveldb_parse_footer_varint(&pad), "footer: nonzero padding at 20") { ok = false; }
  let magic8 = slice_of(&fv, 40, 8);
  var stuck = repeat_byte(128, 40);
  append_bytes(&mut stuck, &magic8);
  if !err_footer_is(leveldb_parse_footer_varint(&stuck), "footer: bad metaindex handle at 0") { ok = false; }
  let chk = leveldb_footer_check(&d0, 1000);
  if !chk.is_ok { ok = false; }
  return assert(ok, name);
}

// --------------------------------------------------
//  t17: index block entries with bounded BlockHandles
// --------------------------------------------------

fn t17() -> TestResult {
  let name = "index block: separator keys and bounded BlockHandles";
  var ok = true;
  let ib = index_block_body();
  if ib.len() != 35 { ok = false; }
  let ir = leveldb_parse_index_block(&ib);
  if !ir.is_ok {
    return assert(false, name);
  }
  let ix = ir.value;
  if leveldb_index_count(&ix) != 2 { ok = false; }
  let k0 = leveldb_index_key(&ix, 0);
  let k1 = leveldb_index_key(&ix, 1);
  if !bytes_eq(&k0, &text("apple")) { ok = false; }
  if !bytes_eq(&k1, &text("banana")) { ok = false; }
  let h0 = leveldb_index_handle(&ix, 0);
  if h0.offset != 100 { ok = false; }
  if h0.size != 50 { ok = false; }
  if h0.encoded_len != 2 { ok = false; }
  let h1 = leveldb_index_handle(&ix, 1);
  if h1.offset != 1000 { ok = false; }
  if h1.size != 200 { ok = false; }
  if h1.encoded_len != 4 { ok = false; }
  let h9 = leveldb_index_handle(&ix, 9);
  if h9.offset != -1 { ok = false; }
  if leveldb_index_key(&ix, -1).len() != 0 { ok = false; }
  if !err_index_is(leveldb_parse_index_block(&hb("000100610000000001000000")), "index: empty block handle at 0") { ok = false; }
  if !err_index_is(leveldb_parse_index_block(&hb("000103616432FF0000000001000000")), "index: block handle overrun at 0") { ok = false; }
  if !err_index_is(leveldb_parse_index_block(&hb("00010161800000000001000000")), "index: bad block handle at 0") { ok = false; }
  let empty_index = leveldb_parse_index_block(&hb("0000000001000000"));
  if !empty_index.is_ok { ok = false; } else {
    let ei = empty_index.value;
    if ei.count != 0 { ok = false; }
  }
  return assert(ok, name);
}

// --------------------------------------------------
//  t18: BlockHandle encode/decode and version
// --------------------------------------------------

fn t18() -> TestResult {
  let name = "block handle: encode/decode, bounds, overflow";
  var ok = true;
  var enc = Vec[UInt8].new();
  if !leveldb_block_handle_encode(&mut enc, 100, 50) { ok = false; }
  if enc.len() != 2 { ok = false; }
  if gb(&enc, 0) != 100 { ok = false; }
  if gb(&enc, 1) != 50 { ok = false; }
  let h1 = leveldb_block_handle_decode(&enc, 0, 2);
  if !h1.is_ok { ok = false; } else {
    let v = h1.value;
    if v.offset != 100 { ok = false; }
    if v.size != 50 { ok = false; }
    if v.encoded_len != 2 { ok = false; }
  }
  if !err_bhandle_is(leveldb_block_handle_decode(&enc, 0, 1), "block handle size: truncated at 1") { ok = false; }
  var enc2 = Vec[UInt8].new();
  if !leveldb_block_handle_encode(&mut enc2, 1000, 200) { ok = false; }
  if enc2.len() != 4 { ok = false; }
  let h2 = leveldb_block_handle_decode(&enc2, 0, 4);
  if !h2.is_ok { ok = false; } else {
    let v = h2.value;
    if v.offset != 1000 { ok = false; }
    if v.size != 200 { ok = false; }
    if v.encoded_len != 4 { ok = false; }
  }
  var ovf = Vec[UInt8].new();
  var i = 0;
  while i < 9 {
    ovf.push(255 as UInt8);
    i = i + 1;
  }
  ovf.push(2 as UInt8);
  if !err_bhandle_is(leveldb_block_handle_decode(&ovf, 0, 10), "block handle offset: overflow at 0") { ok = false; }
  var none = Vec[UInt8].new();
  if leveldb_block_handle_encode(&mut none, -1, 5) { ok = false; }
  if leveldb_block_handle_encode(&mut none, 5, -1) { ok = false; }
  if none.len() != 0 { ok = false; }
  if !str_eq(leveldb_version(), "0.1.0") { ok = false; }
  return assert(ok, name);
}

// --------------------------------------------------
//  main
// --------------------------------------------------

fn main() -> Int {
  io.println("=== xiom.leveldb conformance tests ===");
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
    io.println("xiom.leveldb: all tests passed");
  } else {
    io.println("xiom.leveldb: tests failed");
  }
  return failed;
}
