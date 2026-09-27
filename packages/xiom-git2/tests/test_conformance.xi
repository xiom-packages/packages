// XIOM -- xiom.git2 conformance tests (24 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Covers the documented API against synthetic buffers built inside this
// file: stored/fixed/dynamic DEFLATE streams (the Huffman streams are
// emitted by an independent LSB/MSB bit writer with its own copy of the
// RFC 1951 code tables), zlib headers and Adler trailers, loose-object
// headers, tree entry walks (SHA-1 and SHA-256 id sizes), commit/tag
// headers with folded gpgsig lines, delta opcode vectors, pack headers and
// entry headers (size continuation groups, OFS_DELTA distances, REF_DELTA
// ids), a full two-entry pack with an OFS_DELTA and its trailer, and a
// version-2 pack index with fanout lookup, 64-bit offsets and CRC
// verification. Malformed inputs exercise every error class.
//
// Str equality goes through str_compare (BUG 17 discipline).

module git2_tests
use xiom.io; use xiom.test;
use xiom.git2;
use xiom.string;
use xiom.string.compare;
use xiom.encoding.hex;
use xiom.convert;

// --------------------------------------------------
//  Generic helpers
// --------------------------------------------------

// Expected bytes for a hex string.
fn hb(hexstr: Str) -> Vec[UInt8] {
  let r = hex.hex_decode(hexstr);
  if r.is_ok {
    return r.value;
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

// True when v has exactly the bytes of s.
fn bytes_str(v: Vec[UInt8], s: Str) -> Bool {
  if v.len() != s.len() {
    return false;
  }
  var i = 0;
  while i < v.len() {
    let b = (v[i] as Int) & 0xFF;
    let c = (string.byte_at(s, i) as Int) & 0xFF;
    if b != c {
      return false;
    }
    i = i + 1;
  }
  return true;
}

fn str_eq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn push_all(out: &mut Vec[UInt8], v: &Vec[UInt8]) {
  var i = 0;
  while i < v.len() {
    out.push(v[i]);
    i = i + 1;
  }
}

fn push_be32(out: &mut Vec[UInt8], v: Int) {
  out.push(((v / 16777216) % 256) as UInt8);
  out.push(((v / 65536) % 256) as UInt8);
  out.push(((v / 256) % 256) as UInt8);
  out.push((v % 256) as UInt8);
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

fn err_bytes_is(r: Result[Vec[UInt8], Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return str_eq(r.error, want);
}

fn err_int_is(r: Result[Int, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return str_eq(r.error, want);
}

fn err_loose_is(r: Result[GitLooseObject, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return str_eq(r.error, want);
}

fn err_tree_is(r: Result[GitTree, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return str_eq(r.error, want);
}

fn err_commit_is(r: Result[GitCommit, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return str_eq(r.error, want);
}

fn err_tag_is(r: Result[GitTag, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return str_eq(r.error, want);
}

fn err_phead_is(r: Result[GitPackHeader, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return str_eq(r.error, want);
}

fn err_pentry_is(r: Result[GitPackEntryHeader, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return str_eq(r.error, want);
}

fn err_pack_is(r: Result[GitPack, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return str_eq(r.error, want);
}

fn err_pidx_is(r: Result[GitIndex, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return str_eq(r.error, want);
}

fn err_bool_is(r: Result[Bool, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return str_eq(r.error, want);
}

fn int_is(r: Result[Int, Str], want: Int) -> Bool {
  if !r.is_ok { return false; }
  let v: Int = r.value;
  return v == want;
}

fn str_is(r: Result[Str, Str], want: Str) -> Bool {
  if !r.is_ok { return false; }
  let v: Str = r.value;
  return str_eq(v, want);
}

fn bool_is(r: Result[Bool, Str], want: Bool) -> Bool {
  if !r.is_ok { return false; }
  let v: Bool = r.value;
  return v == want;
}

// --------------------------------------------------
//  Independent bit writer (LSB-first values, MSB-first codes)
// --------------------------------------------------

type _W = {
  acc: Vec[UInt8];
  cur: Int;
  n: Int;
}

fn _w_new() -> _W {
  return _W{
    acc: Vec[UInt8].new();
    cur: 0;
    n: 0;
  };
}

fn pow2(k: Int) -> Int {
  var v = 1;
  var i = 0;
  while i < k {
    v = v * 2;
    i = i + 1;
  }
  return v;
}

fn w_bit(w: &mut _W, bit: Int) {
  w.cur = w.cur + bit * pow2(w.n);
  w.n = w.n + 1;
  if w.n == 8 {
    w.acc.push(w.cur as UInt8);
    w.cur = 0;
    w.n = 0;
  }
}

fn w_bits(w: &mut _W, value: Int, count: Int) {
  var i = 0;
  while i < count {
    w_bit(w, (value / pow2(i)) % 2);
    i = i + 1;
  }
}

fn w_code(w: &mut _W, code: Int, count: Int) {
  var i = 0;
  while i < count {
    w_bit(w, (code / pow2(count - 1 - i)) % 2);
    i = i + 1;
  }
}

fn w_result(w: &mut _W) -> Vec[UInt8] {
  if w.n > 0 {
    w.acc.push(w.cur as UInt8);
    w.cur = 0;
    w.n = 0;
  }
  var out = Vec[UInt8].new();
  var i = 0;
  while i < w.acc.len() {
    let b: UInt8 = w.acc[i];
    out.push(b);
    i = i + 1;
  }
  return out;
}

// --------------------------------------------------
//  DEFLATE / zlib fixture builders
// --------------------------------------------------

// One final stored block (BTYPE 00), no zlib wrapper.
fn deflate_stored(payload: &Vec[UInt8]) -> Vec[UInt8] {
  var w = _w_new();
  w_bit(&mut w, 1);
  w_bits(&mut w, 0, 2);
  while w.n != 0 {
    w_bit(&mut w, 0);
  }
  let len = payload.len();
  w_bits(&mut w, len % 256, 8);
  w_bits(&mut w, len / 256, 8);
  let nlen = 65535 - len;
  w_bits(&mut w, nlen % 256, 8);
  w_bits(&mut w, nlen / 256, 8);
  var i = 0;
  while i < len {
    let b: UInt8 = payload[i];
    w_bits(&mut w, (b as Int) & 0xFF, 8);
    i = i + 1;
  }
  return w_result(&mut w);
}

// zlib (RFC 1950) wrapper: 0x78 0x01 header + deflate + big-endian Adler-32
// of `plain` (the uncompressed bytes).
fn zlib_wrap(deflate: &Vec[UInt8], plain: &Vec[UInt8]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  out.push(120 as UInt8);
  out.push(1 as UInt8);
  push_all(&mut out, deflate);
  let a = git2_adler32(plain);
  push_be32(&mut out, a);
  return out;
}

// Fixed-Huffman code and length for a literal/length symbol.
fn fixed_lit_code(sym: Int) -> Int {
  if sym <= 143 { return 48 + sym; }
  if sym <= 255 { return 400 + (sym - 144); }
  if sym <= 279 { return sym - 256; }
  return 192 + (sym - 280);
}

fn fixed_lit_len(sym: Int) -> Int {
  if sym <= 143 { return 8; }
  if sym <= 255 { return 9; }
  if sym <= 279 { return 7; }
  return 8;
}

fn emit_fixed(w: &mut _W, sym: Int) {
  w_code(w, fixed_lit_code(sym), fixed_lit_len(sym));
}

// Fixed-Huffman block: the ASCII literals of s, then end-of-block.
fn deflate_fixed_literals(s: Str) -> Vec[UInt8] {
  var w = _w_new();
  w_bit(&mut w, 1);
  w_bits(&mut w, 1, 2);
  var i = 0;
  while i < s.len() {
    emit_fixed(&mut w, (string.byte_at(s, i) as Int) & 0xFF);
    i = i + 1;
  }
  emit_fixed(&mut w, 256);
  return w_result(&mut w);
}

// Fixed-Huffman block "abc" + copy(length 3, distance 3): yields "abcabc".
fn deflate_fixed_match() -> Vec[UInt8] {
  var w = _w_new();
  w_bit(&mut w, 1);
  w_bits(&mut w, 1, 2);
  emit_fixed(&mut w, 97);
  emit_fixed(&mut w, 98);
  emit_fixed(&mut w, 99);
  emit_fixed(&mut w, 257);
  w_code(&mut w, 2, 5);
  emit_fixed(&mut w, 256);
  return w_result(&mut w);
}

// Dynamic-Huffman block with a two-symbol literal table (97 'a' and 256 EOB,
// one bit each), an empty distance table and a two-symbol code-length table
// (0 and 1, one bit each). Yields "aa".
fn deflate_dynamic_aa() -> Vec[UInt8] {
  var w = _w_new();
  w_bit(&mut w, 1);
  w_bits(&mut w, 2, 2);
  w_bits(&mut w, 0, 5);
  w_bits(&mut w, 0, 5);
  w_bits(&mut w, 14, 4);
  var idx = 0;
  while idx < 18 {
    var lv = 0;
    if idx == 3 { lv = 1; }
    if idx == 17 { lv = 1; }
    w_bits(&mut w, lv, 3);
    idx = idx + 1;
  }
  var i = 0;
  while i < 258 {
    var sym = 0;
    if i == 97 { sym = 1; }
    if i == 256 { sym = 1; }
    w_code(&mut w, sym, 1);
    i = i + 1;
  }
  w_code(&mut w, 0, 1);
  w_code(&mut w, 0, 1);
  w_code(&mut w, 1, 1);
  return w_result(&mut w);
}

// Git OFS_DELTA negative-offset varint (7-bit groups, +1 per group).
fn ofs_encode(v: Int) -> Vec[UInt8] {
  var tmp = Vec[Int].new();
  var val = v;
  var keep = 1;
  while keep == 1 {
    tmp.push(val % 128);
    val = val / 128;
    if val == 0 {
      keep = 0;
    } else {
      val = val - 1;
    }
  }
  var out = Vec[UInt8].new();
  var i = tmp.len() - 1;
  while i >= 0 {
    let g: Int = tmp[i];
    if i > 0 {
      out.push((g + 128) as UInt8);
    } else {
      out.push(g as UInt8);
    }
    i = i - 1;
  }
  return out;
}

// --------------------------------------------------
//  Object fixture builders
// --------------------------------------------------

// A 20-byte id with every byte equal to v.
fn id20(v: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < 20 {
    out.push(v as UInt8);
    i = i + 1;
  }
  return out;
}

// A 20-byte id whose first two bytes are a and b (rest zero).
fn id_pref(a: Int, b: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  out.push(a as UInt8);
  out.push(b as UInt8);
  var i = 0;
  while i < 18 {
    out.push(0 as UInt8);
    i = i + 1;
  }
  return out;
}

// Tree payload entry: mode Str literal + space + name + NUL + id bytes.
fn tree_entry(mode: Str, name: Str, id: &Vec[UInt8]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < mode.len() {
    out.push(string.byte_at(mode, i));
    i = i + 1;
  }
  out.push(32 as UInt8);
  i = 0;
  while i < name.len() {
    out.push(string.byte_at(name, i));
    i = i + 1;
  }
  out.push(0 as UInt8);
  push_all(&mut out, id);
  return out;
}

// Commit payload with tree, one parent, author, committer, an encoding
// header, a folded gpgsig and a two-line message.
fn commit_fixture() -> Vec[UInt8] {
  var raw = Vec[UInt8].new();
  var i = 0;
  let tree_hex = "1111111111111111111111111111111111111111";
  let par_hex = "2222222222222222222222222222222222222222";
  _push_str(&mut raw, "tree ");
  _push_str(&mut raw, tree_hex);
  _push_str(&mut raw, "\n");
  _push_str(&mut raw, "parent ");
  _push_str(&mut raw, par_hex);
  _push_str(&mut raw, "\n");
  _push_str(&mut raw, "author A U Thor <a@example.com> 1700000000 +0000\n");
  _push_str(&mut raw, "committer C O Mitter <c@example.com> 1700000100 +0000\n");
  _push_str(&mut raw, "encoding UTF-8\n");
  _push_str(&mut raw, "gpgsig -----BEGIN PGP SIGNATURE-----\n");
  _push_str(&mut raw, " abcdef\n");
  _push_str(&mut raw, " -----END PGP SIGNATURE-----\n");
  _push_str(&mut raw, "x-custom value\n");
  _push_str(&mut raw, "\n");
  _push_str(&mut raw, "subject line\n\nbody line\n");
  return raw;
}

// Tag payload with object, type, tag, tagger and a message.
fn tag_fixture() -> Vec[UInt8] {
  var raw = Vec[UInt8].new();
  _push_str(&mut raw, "object 3333333333333333333333333333333333333333\n");
  _push_str(&mut raw, "type commit\n");
  _push_str(&mut raw, "tag v1.0\n");
  _push_str(&mut raw, "tagger T A Gger <t@example.com> 1700000200 +0000\n");
  _push_str(&mut raw, "\n");
  _push_str(&mut raw, "release text\n");
  return raw;
}

fn _push_str(out: &mut Vec[UInt8], s: Str) {
  var i = 0;
  while i < s.len() {
    out.push(string.byte_at(s, i));
    i = i + 1;
  }
}

// Two-entry pack:
//   entry 0 at offset 12: BLOB "hello" (stored zlib stream)
//   entry 1 at offset 29: OFS_DELTA (distance 17) whose delta copies the
//   whole base and inserts "xyz" -> "helloxyz"
// followed by a 20-byte trailer of 0x00..0x13.
fn pack_fixture() -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  out.push(80 as UInt8);
  out.push(65 as UInt8);
  out.push(67 as UInt8);
  out.push(75 as UInt8);
  push_be32(&mut out, 2);
  push_be32(&mut out, 2);
  let base_plain = hb("68656C6C6F");
  let e0 = zlib_wrap(&deflate_stored(&base_plain), &base_plain);
  out.push(53 as UInt8);
  push_all(&mut out, &e0);
  let entry1_off = out.len();
  var delta = Vec[UInt8].new();
  delta.push(5 as UInt8);
  delta.push(8 as UInt8);
  delta.push(144 as UInt8);
  delta.push(5 as UInt8);
  delta.push(3 as UInt8);
  delta.push(120 as UInt8);
  delta.push(121 as UInt8);
  delta.push(122 as UInt8);
  let e1 = zlib_wrap(&deflate_stored(&delta), &delta);
  let distance = entry1_off - 12;
  out.push(104 as UInt8);
  push_all(&mut out, &ofs_encode(distance));
  push_all(&mut out, &e1);
  var i = 0;
  while i < 20 {
    out.push(i as UInt8);
    i = i + 1;
  }
  return out;
}

// Index v2 from parallel inputs: ids flattened (id_size per object, sorted),
// stored CRC values, stored 4-byte offsets, and the 64-bit offset table.
fn idx_build(ids: &Vec[UInt8], crcs: &Vec[Int], raws: &Vec[Int], larges: &Vec[Int]) -> Vec[UInt8] {
  let count = crcs.len();
  var out = Vec[UInt8].new();
  out.push(255 as UInt8);
  out.push(116 as UInt8);
  out.push(79 as UInt8);
  out.push(99 as UInt8);
  push_be32(&mut out, 2);
  var i = 0;
  var b = 0;
  while b < 256 {
    var c = 0;
    i = 0;
    while i < count {
      let fb = (ids[i * 20] as Int) & 0xFF;
      if fb <= b {
        c = c + 1;
      }
      i = i + 1;
    }
    push_be32(&mut out, c);
    b = b + 1;
  }
  push_all(&mut out, ids);
  i = 0;
  while i < count {
    let c: Int = crcs[i];
    push_be32(&mut out, c);
    i = i + 1;
  }
  i = 0;
  while i < count {
    let r: Int = raws[i];
    push_be32(&mut out, r);
    i = i + 1;
  }
  i = 0;
  while i < larges.len() {
    let l: Int = larges[i];
    push_be32(&mut out, l / 4294967296);
    push_be32(&mut out, l % 4294967296);
    i = i + 1;
  }
  push_all(&mut out, &zeros(20));
  push_all(&mut out, &zeros(20));
  return out;
}

// Independent table-less CRC-32 (reflected 0xEDB88320) for cross-checking
// the library implementation.
fn test_crc32_range(data: &Vec[UInt8], start: Int, end: Int) -> Int {
  var c = 4294967295;
  var i = start;
  while i < end {
    let b = (data[i] as Int) & 0xFF;
    c = c ^ b;
    var k = 0;
    while k < 8 {
      if c % 2 == 1 {
        c = c / 2 ^ 3988292384;
      } else {
        c = c / 2;
      }
      k = k + 1;
    }
    i = i + 1;
  }
  return c ^ 4294967295;
}

// Patch four big-endian bytes at off.
fn patch_be32(v: &mut Vec[UInt8], off: Int, val: Int) {
  v[off] = ((val / 16777216) % 256) as UInt8;
  v[off + 1] = ((val / 65536) % 256) as UInt8;
  v[off + 2] = ((val / 256) % 256) as UInt8;
  v[off + 3] = (val % 256) as UInt8;
}

// --------------------------------------------------
//  t1-t12
// --------------------------------------------------

fn t1() -> TestResult {
  var ok = str_eq(git2_version(), "0.1.0");
  if git2_sha1_size() != 20 { ok = false; }
  if git2_sha256_size() != 32 { ok = false; }
  if git2_pack_header_size() != 12 { ok = false; }
  if git2_pack_trailer_size() != 20 { ok = false; }
  if git2_zlib_header_size() != 2 { ok = false; }
  if git2_zlib_trailer_size() != 4 { ok = false; }
  if git2_idx_fanout_size() != 1024 { ok = false; }
  if git2_idx_magic() != 4285812579 { ok = false; }
  if !str_eq(git2_object_type_name(1), "commit") { ok = false; }
  if !str_eq(git2_object_type_name(2), "tree") { ok = false; }
  if !str_eq(git2_object_type_name(3), "blob") { ok = false; }
  if !str_eq(git2_object_type_name(4), "tag") { ok = false; }
  if !str_eq(git2_object_type_name(99), "") { ok = false; }
  if git2_object_type_code("blob") != 3 { ok = false; }
  if git2_object_type_code("NOPE") != 0 { ok = false; }
  return assert(ok, "version, layout sizes, idx magic and the object type table");
}

fn t2() -> TestResult {
  let z = hb("7801010500FAFF68656C6C6F062C0215");
  let r = git2_zlib_decode(&z);
  var ok = true;
  if !r.is_ok {
    ok = false;
  } else {
    let v: Vec[UInt8] = r.value;
    if !bytes_str(v, "hello") { ok = false; }
  }
  var out = Vec[UInt8].new();
  out.push(65 as UInt8);
  let rr = git2_deflate_decode_into(&z, 2, &mut out);
  if !rr.is_ok {
    ok = false;
  } else {
    let end: Int = rr.value;
    if end != 12 { ok = false; }
  }
  if !bytes_str(out, "Ahello") { ok = false; }
  return assert(ok, "stored zlib stream decodes to \"hello\"; raw deflate appends at offset 2");
}

fn t3() -> TestResult {
  var ok = true;
  let h = hb("68656C6C6F");
  if git2_adler32(&h) != 103547413 { ok = false; }
  var empty = Vec[UInt8].new();
  if git2_adler32(&empty) != 1 { ok = false; }
  let ello = hb("656C6C6F");
  if git2_adler32_range(&h, 1, 5) != git2_adler32(&ello) { ok = false; }
  var z = hb("7801010500FAFF68656C6C6F062C0215");
  let b: UInt8 = z[15];
  z[15] = (((b as Int) + 1) % 256) as UInt8;
  if !err_bytes_is(git2_zlib_decode(&z), "git2: adler mismatch at 12") { ok = false; }
  var z2 = hb("7801010500FAFF68656C6C6F062C0215");
  z2.push(0 as UInt8);
  if !err_bytes_is(git2_zlib_decode(&z2), "git2: trailing bytes after zlib stream at 16") { ok = false; }
  return assert(ok, "Adler-32 vectors, trailer mismatch and trailing bytes");
}

fn t4() -> TestResult {
  var ok = true;
  var bad = hb("7802010500FAFF68656C6C6F062C0215");
  if !err_bytes_is(git2_zlib_decode(&bad), "git2: bad zlib fcheck at 0") { ok = false; }
  var fdict = hb("7820010500FAFF68656C6C6F062C0215");
  if !err_bytes_is(git2_zlib_decode(&fdict), "git2: zlib preset dictionary unsupported at 0") { ok = false; }
  var method = hb("7901010500FAFF68656C6C6F062C0215");
  if !err_bytes_is(git2_zlib_decode(&method), "git2: unsupported zlib method at 0") { ok = false; }
  var window = hb("8801010500FAFF68656C6C6F062C0215");
  if !err_bytes_is(git2_zlib_decode(&window), "git2: invalid zlib window size at 0") { ok = false; }
  var short1 = hb("78");
  if !err_bytes_is(git2_zlib_decode(&short1), "git2: truncated zlib header at 0") { ok = false; }
  let short2 = hb("7801010500FAFF68");
  var out2 = Vec[UInt8].new();
  if !err_int_is(git2_deflate_decode_into(&short2, 2, &mut out2), "git2: truncated stored block at 3") { ok = false; }
  return assert(ok, "zlib header validation: fcheck, method, window, FDICT, truncation");
}

fn t5() -> TestResult {
  let d = deflate_fixed_literals("abc");
  var out = Vec[UInt8].new();
  let r = git2_deflate_decode_into(&d, 0, &mut out);
  var ok = true;
  if !r.is_ok {
    ok = false;
  } else {
    let end: Int = r.value;
    if end != d.len() { ok = false; }
  }
  if !bytes_str(out, "abc") { ok = false; }
  let plain = hb("616263");
  let z = zlib_wrap(&d, &plain);
  let r2 = git2_zlib_decode(&z);
  if !r2.is_ok {
    ok = false;
  } else {
    let v: Vec[UInt8] = r2.value;
    if !bytes_str(v, "abc") { ok = false; }
  }
  return assert(ok, "fixed-Huffman literals (code 0x91 etc.) decode to \"abc\"");
}

fn t6() -> TestResult {
  let d = deflate_fixed_match();
  var out = Vec[UInt8].new();
  let r = git2_deflate_decode_into(&d, 0, &mut out);
  var ok = true;
  if !r.is_ok {
    ok = false;
  } else {
    let end: Int = r.value;
    if end != d.len() { ok = false; }
  }
  if !bytes_str(out, "abcabc") { ok = false; }
  return assert(ok, "fixed-Huffman LZ77 back-reference (length 3, distance 3)");
}

fn t7() -> TestResult {
  let d = deflate_dynamic_aa();
  var out = Vec[UInt8].new();
  let r = git2_deflate_decode_into(&d, 0, &mut out);
  var ok = true;
  if !r.is_ok {
    ok = false;
  } else {
    let end: Int = r.value;
    if end != d.len() { ok = false; }
  }
  if !bytes_str(out, "aa") { ok = false; }
  let plain = hb("6161");
  let z = zlib_wrap(&d, &plain);
  let r2 = git2_zlib_decode(&z);
  if !r2.is_ok {
    ok = false;
  } else {
    let v: Vec[UInt8] = r2.value;
    if !bytes_str(v, "aa") { ok = false; }
  }
  return assert(ok, "dynamic-Huffman block: code-length table and two-symbol literals");
}

fn t8() -> TestResult {
  var ok = true;
  var out = Vec[UInt8].new();
  let btype3 = hb("07");
  if !err_int_is(git2_deflate_decode_into(&btype3, 0, &mut out), "git2: invalid deflate block type at 0") { ok = false; }
  var empty = Vec[UInt8].new();
  var out2 = Vec[UInt8].new();
  if !err_int_is(git2_deflate_decode_into(&empty, 0, &mut out2), "git2: truncated deflate block header at 0") { ok = false; }
  let far = hb("0302");
  var out3 = Vec[UInt8].new();
  if !err_int_is(git2_deflate_decode_into(&far, 0, &mut out3), "git2: distance too far back at 1") { ok = false; }
  let badlen = hb("0105000000");
  var out4 = Vec[UInt8].new();
  if !err_int_is(git2_deflate_decode_into(&badlen, 0, &mut out4), "git2: stored block length check failed at 1") { ok = false; }
  return assert(ok, "deflate rejects block type 3, truncation, distance 0 base and bad NLEN");
}

fn t9() -> TestResult {
  var raw = Vec[UInt8].new();
  _push_str(&mut raw, "blob 5");
  raw.push(0 as UInt8);
  _push_str(&mut raw, "hello");
  let r = git2_loose_split(&raw);
  var ok = true;
  if !r.is_ok {
    ok = false;
  } else {
    let v: GitLooseObject = r.value;
    if v.object_type != 3 { ok = false; }
    if !str_eq(v.type_name, "blob") { ok = false; }
    if v.declared_size != 5 { ok = false; }
    if v.header_size != 7 { ok = false; }
    if !bytes_str(v.payload, "hello") { ok = false; }
  }
  var z = Vec[UInt8].new();
  _push_str(&mut z, "tree 0");
  z.push(0 as UInt8);
  let r2 = git2_loose_split(&z);
  if !r2.is_ok {
    ok = false;
  } else {
    let v2: GitLooseObject = r2.value;
    if v2.object_type != 2 { ok = false; }
    if v2.declared_size != 0 { ok = false; }
    if v2.payload.len() != 0 { ok = false; }
  }
  var c = Vec[UInt8].new();
  _push_str(&mut c, "commit 0");
  c.push(0 as UInt8);
  let r3 = git2_loose_split(&c);
  if !r3.is_ok { ok = false; }
  if !r3.is_ok {
    ok = false;
  } else {
    let v3: GitLooseObject = r3.value;
    if v3.object_type != 1 { ok = false; }
  }
  return assert(ok, "loose \"<type> <size>\\0<payload>\" split: blob, empty tree, commit");
}

fn t10() -> TestResult {
  var ok = true;
  var nonul = Vec[UInt8].new();
  _push_str(&mut nonul, "blob 5");
  if !err_loose_is(git2_loose_split(&nonul), "git2: loose header missing NUL at 0") { ok = false; }
  var nosep = Vec[UInt8].new();
  _push_str(&mut nosep, "blobx5");
  nosep.push(0 as UInt8);
  if !err_loose_is(git2_loose_split(&nosep), "git2: loose header missing type separator at 0") { ok = false; }
  var notype = Vec[UInt8].new();
  _push_str(&mut notype, " 5");
  notype.push(0 as UInt8);
  if !err_loose_is(git2_loose_split(&notype), "git2: loose header missing type at 0") { ok = false; }
  var nosize = Vec[UInt8].new();
  _push_str(&mut nosize, "blob ");
  nosize.push(0 as UInt8);
  if !err_loose_is(git2_loose_split(&nosize), "git2: loose header missing size at 5") { ok = false; }
  var notnum = Vec[UInt8].new();
  _push_str(&mut notnum, "blob x");
  notnum.push(0 as UInt8);
  _push_str(&mut notnum, "hello");
  if !err_loose_is(git2_loose_split(&notnum), "git2: loose size is not decimal at 5") { ok = false; }
  var lead0 = Vec[UInt8].new();
  _push_str(&mut lead0, "blob 05");
  lead0.push(0 as UInt8);
  _push_str(&mut lead0, "hello");
  if !err_loose_is(git2_loose_split(&lead0), "git2: loose size has leading zero at 5") { ok = false; }
  var mis = Vec[UInt8].new();
  _push_str(&mut mis, "blob 6");
  mis.push(0 as UInt8);
  _push_str(&mut mis, "hello");
  if !err_loose_is(git2_loose_split(&mis), "git2: loose size mismatch at 7") { ok = false; }
  var unk = Vec[UInt8].new();
  _push_str(&mut unk, "frob 5");
  unk.push(0 as UInt8);
  _push_str(&mut unk, "hello");
  if !err_loose_is(git2_loose_split(&unk), "git2: unknown loose object type at 0") { ok = false; }
  return assert(ok, "loose header rejects missing NUL/separator/size, non-decimal, leading zero, size mismatch, unknown type");
}

fn t11() -> TestResult {
  var plain = Vec[UInt8].new();
  _push_str(&mut plain, "blob 5");
  plain.push(0 as UInt8);
  _push_str(&mut plain, "hello");
  let z = zlib_wrap(&deflate_stored(&plain), &plain);
  let r = git2_loose_parse(&z);
  var ok = true;
  if !r.is_ok {
    ok = false;
  } else {
    let v: GitLooseObject = r.value;
    if v.object_type != 3 { ok = false; }
    if v.header_size != 7 { ok = false; }
    if !bytes_str(v.payload, "hello") { ok = false; }
  }
  var cut = Vec[UInt8].new();
  var i = 0;
  while i < 10 {
    cut.push(z[i]);
    i = i + 1;
  }
  if !err_loose_is(git2_loose_parse(&cut), "git2: truncated stored block at 3") { ok = false; }
  return assert(ok, "zlib-compressed loose blob parses; truncated stream rejected");
}

fn t12() -> TestResult {
  let a = id20(1);
  let s = id20(2);
  var payload = Vec[UInt8].new();
  push_all(&mut payload, &tree_entry("100644", "a", &a));
  push_all(&mut payload, &tree_entry("40000", "sub", &s));
  let r = git2_tree_walk(&payload, 20);
  var ok = true;
  if !r.is_ok {
    ok = false;
  } else {
    let t: GitTree = r.value;
    if t.entry_count != 2 { ok = false; }
    if t.id_size != 20 { ok = false; }
    if !str_is(git2_tree_mode(&t, 0), "100644") { ok = false; }
    if !str_is(git2_tree_name(&t, 0), "a") { ok = false; }
    let m0: Int = t.entry_mode_value[0];
    if m0 != 33188 { ok = false; }
    if !int_is(git2_tree_id_byte(&t, 0, 0), 1) { ok = false; }
    let m1: Int = t.entry_mode_value[1];
    if m1 != 16384 { ok = false; }
    if !int_is(git2_tree_id_byte(&t, 1, 19), 2) { ok = false; }
    if t.entry_id.len() != 40 { ok = false; }
  }
  let a32 = zeros(32);
  var p32 = Vec[UInt8].new();
  push_all(&mut p32, &tree_entry("100644", "f", &a32));
  let r32 = git2_tree_walk(&p32, 32);
  if !r32.is_ok {
    ok = false;
  } else {
    let t32: GitTree = r32.value;
    if t32.entry_id.len() != 32 { ok = false; }
    if !int_is(git2_tree_id_byte(&t32, 0, 31), 0) { ok = false; }
  }
  if !err_tree_is(git2_tree_walk(&p32, 21), "git2: bad id size at 0") { ok = false; }
  return assert(ok, "tree walk: entries, modes, names, raw ids (20 and 32 bytes)");
}

fn t13() -> TestResult {
  var ok = true;
  let a = id20(1);
  let b = id20(2);
  let e_stxt = tree_entry("100644", "sub.txt", &a);
  let e_sub = tree_entry("40000", "sub", &b);
  var p = Vec[UInt8].new();
  push_all(&mut p, &e_stxt);
  push_all(&mut p, &e_sub);
  let r = git2_tree_walk(&p, 20);
  if !r.is_ok { ok = false; }
  var p2 = Vec[UInt8].new();
  push_all(&mut p2, &e_sub);
  push_all(&mut p2, &e_stxt);
  let off = e_sub.len();
  let want = "git2: tree entries out of order at " + convert.int_to_string(off);
  if !err_tree_is(git2_tree_walk(&p2, 20), want) { ok = false; }
  var p3 = Vec[UInt8].new();
  let e_a1 = tree_entry("100644", "a", &a);
  let e_a2 = tree_entry("100644", "a", &b);
  push_all(&mut p3, &e_a1);
  push_all(&mut p3, &e_a2);
  let off3 = e_a1.len();
  if !err_tree_is(git2_tree_walk(&p3, 20), "git2: duplicate tree entry at " + convert.int_to_string(off3)) { ok = false; }
  return assert(ok, "tree ordering: directory names sort as name + '/'; duplicates rejected");
}

fn t14() -> TestResult {
  var ok = true;
  var p = Vec[UInt8].new();
  _push_str(&mut p, "100644");
  _push_str(&mut p, "a");
  p.push(0 as UInt8);
  push_all(&mut p, &id20(1));
  if !err_tree_is(git2_tree_walk(&p, 20), "git2: missing tree mode separator at 6") { ok = false; }
  var p2 = Vec[UInt8].new();
  push_all(&mut p2, &tree_entry("0644", "a", &id20(1)));
  if !err_tree_is(git2_tree_walk(&p2, 20), "git2: tree mode has leading zero at 0") { ok = false; }
  var p3 = Vec[UInt8].new();
  push_all(&mut p3, &tree_entry("1006444", "a", &id20(1)));
  if !err_tree_is(git2_tree_walk(&p3, 20), "git2: tree mode too long at 0") { ok = false; }
  var p4 = Vec[UInt8].new();
  push_all(&mut p4, &tree_entry("100644", "", &id20(1)));
  if !err_tree_is(git2_tree_walk(&p4, 20), "git2: empty tree name at 7") { ok = false; }
  var p5 = Vec[UInt8].new();
  push_all(&mut p5, &tree_entry("100644", "a/b", &id20(1)));
  if !err_tree_is(git2_tree_walk(&p5, 20), "git2: tree name contains slash at 8") { ok = false; }
  var p6 = Vec[UInt8].new();
  _push_str(&mut p6, "100644");
  _push_str(&mut p6, " a");
  push_all(&mut p6, &id20(1));
  if !err_tree_is(git2_tree_walk(&p6, 20), "git2: unterminated tree name at 7") { ok = false; }
  let full = tree_entry("100644", "a", &id20(1));
  var p7 = Vec[UInt8].new();
  var i = 0;
  while i < 19 {
    p7.push(full[i]);
    i = i + 1;
  }
  if !err_tree_is(git2_tree_walk(&p7, 20), "git2: truncated tree id at 9") { ok = false; }
  return assert(ok, "tree entry rejects missing separator, bad modes, empty/slashed names, truncation");
}

fn t15() -> TestResult {
  let raw = commit_fixture();
  let r = git2_commit_parse(&raw);
  var ok = true;
  if !r.is_ok {
    ok = false;
  } else {
    let c: GitCommit = r.value;
    if c.id_size != 20 { ok = false; }
    if !int_is(git2_commit_tree_byte(&c, 0), 17) { ok = false; }
    if git2_commit_parent_count(&c) != 1 { ok = false; }
    if !int_is(git2_commit_parent_byte(&c, 0, 0), 34) { ok = false; }
    if !str_eq(c.author, "A U Thor <a@example.com> 1700000000 +0000") { ok = false; }
    if !str_eq(c.committer, "C O Mitter <c@example.com> 1700000100 +0000") { ok = false; }
    if !str_eq(c.encoding, "UTF-8") { ok = false; }
    if !str_eq(c.gpgsig, "-----BEGIN PGP SIGNATURE-----\nabcdef\n-----END PGP SIGNATURE-----") { ok = false; }
    if c.other_keys.len() != 1 {
      ok = false;
    } else {
      let k: Str = c.other_keys[0];
      if !str_eq(k, "x-custom") { ok = false; }
    }
    let want_msg = "subject line\n\nbody line\n";
    if !str_eq(c.message, want_msg) { ok = false; }
    if c.header_end != raw.len() - want_msg.len() { ok = false; }
    let pl: Int = c.parent_id.len();
    if pl != 20 { ok = false; }
  }
  return assert(ok, "commit parse: tree/parent ids, author/committer, encoding, folded gpgsig, message");
}

fn t16() -> TestResult {
  var ok = true;
  var p1 = Vec[UInt8].new();
  _push_str(&mut p1, "author A <a@b> 1 +0000\ncommitter C <c@d> 2 +0000\n\nmsg\n");
  if !err_commit_is(git2_commit_parse(&p1), "git2: commit tree must be first at 0") { ok = false; }
  var p2 = Vec[UInt8].new();
  _push_str(&mut p2, "tree zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz\n");
  _push_str(&mut p2, "author A <a@b> 1 +0000\ncommitter C <c@d> 2 +0000\n\nmsg\n");
  if !err_commit_is(git2_commit_parse(&p2), "git2: invalid tree id at 5") { ok = false; }
  var p3 = Vec[UInt8].new();
  _push_str(&mut p3, "tree aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n");
  _push_str(&mut p3, "author A <a@b> 1 +0000\ncommitter C <c@d> 2 +0000\n\nmsg\n");
  if !err_commit_is(git2_commit_parse(&p3), "git2: invalid tree id length at 5") { ok = false; }
  var p4 = Vec[UInt8].new();
  _push_str(&mut p4, "tree 1111111111111111111111111111111111111111\n");
  _push_str(&mut p4, "tree 1111111111111111111111111111111111111111\n");
  _push_str(&mut p4, "author A <a@b> 1 +0000\ncommitter C <c@d> 2 +0000\n\nmsg\n");
  if !err_commit_is(git2_commit_parse(&p4), "git2: duplicate tree header at 46") { ok = false; }
  var p5 = Vec[UInt8].new();
  _push_str(&mut p5, "tree 1111111111111111111111111111111111111111\n");
  _push_str(&mut p5, "parent 2222222222222222222222222222222222222222222222222222222222222222\n");
  _push_str(&mut p5, "author A <a@b> 1 +0000\ncommitter C <c@d> 2 +0000\n\nmsg\n");
  if !err_commit_is(git2_commit_parse(&p5), "git2: parent id length mismatch at 53") { ok = false; }
  var p6 = Vec[UInt8].new();
  _push_str(&mut p6, "tree 1111111111111111111111111111111111111111\n");
  _push_str(&mut p6, "committer C <c@d> 2 +0000\n\nmsg\n");
  if !err_commit_is(git2_commit_parse(&p6), "git2: commit missing author") { ok = false; }
  var p7 = Vec[UInt8].new();
  _push_str(&mut p7, "tree 1111111111111111111111111111111111111111\n");
  _push_str(&mut p7, "author x\n");
  _push_str(&mut p7, "committer y\n");
  _push_str(&mut p7, "\n");
  _push_str(&mut p7, "ab");
  p7.push(0 as UInt8);
  _push_str(&mut p7, "cd");
  if !err_commit_is(git2_commit_parse(&p7), "git2: NUL byte in commit message at 70") { ok = false; }
  return assert(ok, "commit rejects bad first header, ids, duplicates, missing author, NUL message");
}

fn t17() -> TestResult {
  let raw = tag_fixture();
  let r = git2_tag_parse(&raw);
  var ok = true;
  if !r.is_ok {
    ok = false;
  } else {
    let t: GitTag = r.value;
    if t.id_size != 20 { ok = false; }
    if t.target_type != 1 { ok = false; }
    if !str_eq(t.target_type_raw, "commit") { ok = false; }
    if !str_eq(t.tag_name, "v1.0") { ok = false; }
    if !str_eq(t.tagger, "T A Gger <t@example.com> 1700000200 +0000") { ok = false; }
    if !str_eq(t.message, "release text\n") { ok = false; }
    let ol: Int = t.object_id.len();
    if ol != 20 { ok = false; }
  }
  var p1 = Vec[UInt8].new();
  _push_str(&mut p1, "type commit\n\nmsg\n");
  if !err_tag_is(git2_tag_parse(&p1), "git2: tag object must be first at 0") { ok = false; }
  var p2 = Vec[UInt8].new();
  _push_str(&mut p2, "object 3333333333333333333333333333333333333333\n");
  _push_str(&mut p2, "type blobx\n");
  _push_str(&mut p2, "tag v1\n");
  _push_str(&mut p2, "\nmsg\n");
  if !err_tag_is(git2_tag_parse(&p2), "git2: unknown tag object type at 53") { ok = false; }
  var p3 = Vec[UInt8].new();
  _push_str(&mut p3, "object 3333333333333333333333333333333333333333\n");
  _push_str(&mut p3, "type tag\n");
  _push_str(&mut p3, "\nmsg\n");
  if !err_tag_is(git2_tag_parse(&p3), "git2: tag missing tag name") { ok = false; }
  var p4 = Vec[UInt8].new();
  _push_str(&mut p4, "object 3333333333333333333333333333333333333333\n");
  _push_str(&mut p4, "object 3333333333333333333333333333333333333333\n");
  _push_str(&mut p4, "type tag\ntag v1\n\nmsg\n");
  if !err_tag_is(git2_tag_parse(&p4), "git2: duplicate object header at 48") { ok = false; }
  return assert(ok, "tag parse: object/type/tag/tagger/message; rejects ordering and duplicate errors");
}

fn pattern(n: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < n {
    v.push((i % 251) as UInt8);
    i = i + 1;
  }
  return v;
}

fn t18() -> TestResult {
  var ok = true;
  let base = hb("68656C6C6F");
  var d = Vec[UInt8].new();
  d.push(5 as UInt8);
  d.push(8 as UInt8);
  d.push(144 as UInt8);
  d.push(5 as UInt8);
  d.push(3 as UInt8);
  d.push(120 as UInt8);
  d.push(121 as UInt8);
  d.push(122 as UInt8);
  let r = git2_delta_apply(&base, &d);
  if !r.is_ok {
    ok = false;
  } else {
    let v: Vec[UInt8] = r.value;
    if !bytes_str(v, "helloxyz") { ok = false; }
  }
  var e = Vec[UInt8].new();
  let empty = Vec[UInt8].new();
  e.push(0 as UInt8);
  e.push(2 as UInt8);
  e.push(2 as UInt8);
  e.push(104 as UInt8);
  e.push(105 as UInt8);
  let r2 = git2_delta_apply(&empty, &e);
  if !r2.is_ok {
    ok = false;
  } else {
    let v2: Vec[UInt8] = r2.value;
    if !bytes_str(v2, "hi") { ok = false; }
  }
  let big = pattern(300);
  var m = Vec[UInt8].new();
  m.push(172 as UInt8);
  m.push(2 as UInt8);
  m.push(4 as UInt8);
  m.push(145 as UInt8);
  m.push(200 as UInt8);
  m.push(4 as UInt8);
  let r3 = git2_delta_apply(&big, &m);
  if !r3.is_ok {
    ok = false;
  } else {
    let v3: Vec[UInt8] = r3.value;
    if v3.len() != 4 { ok = false; }
    var k = 0;
    while k < 4 {
      let w: UInt8 = big[200 + k];
      if v3[k] != w { ok = false; }
      k = k + 1;
    }
  }
  return assert(ok, "delta apply: copy + insert, empty base, multi-byte size varint and copy offset");
}

fn t19() -> TestResult {
  var ok = true;
  let base = hb("68656C6C6F");
  var src_bad = Vec[UInt8].new();
  src_bad.push(4 as UInt8);
  src_bad.push(5 as UInt8);
  src_bad.push(144 as UInt8);
  src_bad.push(5 as UInt8);
  if !err_bytes_is(git2_delta_apply(&base, &src_bad), "git2: delta source size mismatch at 0") { ok = false; }
  var tgt_bad = Vec[UInt8].new();
  tgt_bad.push(5 as UInt8);
  tgt_bad.push(7 as UInt8);
  tgt_bad.push(144 as UInt8);
  tgt_bad.push(5 as UInt8);
  if !err_bytes_is(git2_delta_apply(&base, &tgt_bad), "git2: delta target size mismatch at 0") { ok = false; }
  var op0 = Vec[UInt8].new();
  op0.push(5 as UInt8);
  op0.push(0 as UInt8);
  op0.push(0 as UInt8);
  if !err_bytes_is(git2_delta_apply(&base, &op0), "git2: reserved delta opcode at 2") { ok = false; }
  var oor = Vec[UInt8].new();
  oor.push(5 as UInt8);
  oor.push(5 as UInt8);
  oor.push(145 as UInt8);
  oor.push(4 as UInt8);
  oor.push(5 as UInt8);
  if !err_bytes_is(git2_delta_apply(&base, &oor), "git2: delta copy out of range at 2") { ok = false; }
  var trunc = Vec[UInt8].new();
  trunc.push(5 as UInt8);
  trunc.push(5 as UInt8);
  trunc.push(129 as UInt8);
  if !err_bytes_is(git2_delta_apply(&base, &trunc), "git2: truncated delta copy at 3") { ok = false; }
  var tins = Vec[UInt8].new();
  tins.push(5 as UInt8);
  tins.push(2 as UInt8);
  tins.push(3 as UInt8);
  tins.push(65 as UInt8);
  if !err_bytes_is(git2_delta_apply(&base, &tins), "git2: truncated delta insert at 3") { ok = false; }
  var overs = Vec[UInt8].new();
  var i = 0;
  while i < 9 {
    overs.push(128 as UInt8);
    i = i + 1;
  }
  if !err_bytes_is(git2_delta_apply(&base, &overs), "git2: oversized delta size at 0") { ok = false; }
  return assert(ok, "delta rejects size mismatches, reserved opcode, out-of-range copy, truncations, oversized varint");
}

fn clone_bytes(v: &Vec[UInt8]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  push_all(&mut out, v);
  return out;
}

fn t20() -> TestResult {
  let p = pack_fixture();
  let h = git2_pack_header(&p);
  var ok = true;
  if !h.is_ok {
    ok = false;
  } else {
    let ph: GitPackHeader = h.value;
    if ph.version != 2 { ok = false; }
    if ph.object_count != 2 { ok = false; }
    if ph.header_size != 12 { ok = false; }
  }
  var bad = clone_bytes(&p);
  bad[0] = 66 as UInt8;
  if !err_phead_is(git2_pack_header(&bad), "git2: bad pack magic at 0") { ok = false; }
  var badver = clone_bytes(&p);
  patch_be32(&mut badver, 4, 1);
  if !err_phead_is(git2_pack_header(&badver), "git2: unsupported pack version at 4") { ok = false; }
  let short = hb("5041434B0000000200");
  if !err_phead_is(git2_pack_header(&short), "git2: truncated pack header at 0") { ok = false; }
  let e1 = git2_pack_entry_header(&hb("35"), 0, 20);
  if !e1.is_ok {
    ok = false;
  } else {
    let h1: GitPackEntryHeader = e1.value;
    if h1.entry_type != 3 { ok = false; }
    if h1.size != 5 { ok = false; }
    if h1.header_size != 1 { ok = false; }
    if h1.data_offset != 1 { ok = false; }
  }
  let e2 = git2_pack_entry_header(&hb("B83E"), 0, 20);
  if !e2.is_ok {
    ok = false;
  } else {
    let h2: GitPackEntryHeader = e2.value;
    if h2.entry_type != 3 { ok = false; }
    if h2.size != 1000 { ok = false; }
    if h2.header_size != 2 { ok = false; }
  }
  var obuf = zeros(30);
  obuf[20] = 104 as UInt8;
  obuf[21] = 5 as UInt8;
  let e3 = git2_pack_entry_header(&obuf, 20, 20);
  if !e3.is_ok {
    ok = false;
  } else {
    let h3: GitPackEntryHeader = e3.value;
    if h3.entry_type != 6 { ok = false; }
    if h3.base_distance != 5 { ok = false; }
    if h3.base_offset != 15 { ok = false; }
    if h3.header_size != 2 { ok = false; }
    if h3.data_offset != 22 { ok = false; }
  }
  var rbuf = Vec[UInt8].new();
  rbuf.push(117 as UInt8);
  var i = 0;
  while i < 20 {
    rbuf.push((170 + i) as UInt8);
    i = i + 1;
  }
  let e4 = git2_pack_entry_header(&rbuf, 0, 20);
  if !e4.is_ok {
    ok = false;
  } else {
    let h4: GitPackEntryHeader = e4.value;
    if h4.entry_type != 7 { ok = false; }
    if h4.header_size != 21 { ok = false; }
    if h4.data_offset != 21 { ok = false; }
    let bl: Int = h4.base_id.len();
    if bl != 20 { ok = false; }
    let b0: UInt8 = h4.base_id[0];
    if ((b0 as Int) & 0xFF) != 170 { ok = false; }
  }
  if !err_pentry_is(git2_pack_entry_header(&hb("50"), 0, 20), "git2: invalid pack entry type at 0") { ok = false; }
  if !err_pentry_is(git2_pack_entry_header(&hb("B8"), 0, 20), "git2: truncated pack entry header at 0") { ok = false; }
  var obig = hb("B8808080808080808080");
  if !err_pentry_is(git2_pack_entry_header(&obig, 0, 20), "git2: oversized pack entry size at 0") { ok = false; }
  var otr = zeros(22);
  otr[20] = 104 as UInt8;
  otr[21] = 128 as UInt8;
  if !err_pentry_is(git2_pack_entry_header(&otr, 20, 20), "git2: truncated ofs delta at 22") { ok = false; }
  var ozero = zeros(30);
  ozero[20] = 104 as UInt8;
  ozero[21] = 0 as UInt8;
  if !err_pentry_is(git2_pack_entry_header(&ozero, 20, 20), "git2: invalid ofs delta distance at 20") { ok = false; }
  var orange = zeros(30);
  orange[12] = 104 as UInt8;
  orange[13] = 17 as UInt8;
  if !err_pentry_is(git2_pack_entry_header(&orange, 12, 20), "git2: ofs delta base out of range at 12") { ok = false; }
  return assert(ok, "pack header/entry headers: size groups, OFS distance, REF id, malformed forms");
}

fn t21() -> TestResult {
  let p = pack_fixture();
  let r = git2_pack_walk(&p, 20);
  var ok = true;
  if !r.is_ok {
    ok = false;
  } else {
    let pk: GitPack = r.value;
    if pk.object_count != 2 { ok = false; }
    if git2_pack_count(&pk) != 2 { ok = false; }
    if !int_is(git2_pack_entry_type(&pk, 0), 3) { ok = false; }
    if !int_is(git2_pack_entry_offset(&pk, 0), 12) { ok = false; }
    if !int_is(git2_pack_entry_size(&pk, 1), 8) { ok = false; }
    let t1v: Int = pk.entry_type[1];
    if t1v != 6 { ok = false; }
    let bo: Int = pk.entry_base_offset[1];
    if bo != 12 { ok = false; }
    let bd: Int = pk.entry_base_distance[1];
    if bd != 17 { ok = false; }
    let cl: Int = pk.checksum.len();
    if cl != 20 { ok = false; }
    let c0: UInt8 = pk.checksum[0];
    if ((c0 as Int) & 0xFF) != 0 { ok = false; }
    let c19: UInt8 = pk.checksum[19];
    if ((c19 as Int) & 0xFF) != 19 { ok = false; }
    let r0 = git2_pack_resolve(&pk, 0);
    if !r0.is_ok {
      ok = false;
    } else {
      let v0: Vec[UInt8] = r0.value;
      if !bytes_str(v0, "hello") { ok = false; }
    }
    let r1 = git2_pack_resolve(&pk, 1);
    if !r1.is_ok {
      ok = false;
    } else {
      let v1: Vec[UInt8] = r1.value;
      if !bytes_str(v1, "helloxyz") { ok = false; }
    }
    let pr = git2_pack_payload(&pk, 1);
    if !pr.is_ok {
      ok = false;
    } else {
      let pv: Vec[UInt8] = pr.value;
      let pvl: Int = pv.len();
      if pvl != 8 { ok = false; }
    }
    let s0: Int = pk.entry_offset[0];
    let e0: Int = pk.entry_end[0];
    let s1: Int = pk.entry_offset[1];
    let e1: Int = pk.entry_end[1];
    if git2_crc32_range(&p, s0, e0) != test_crc32_range(&p, s0, e0) { ok = false; }
    if git2_crc32_range(&p, s1, e1) != test_crc32_range(&p, s1, e1) { ok = false; }
    if git2_crc32(hb("313233343536373839")) != 3421780262 { ok = false; }
  }
  var p2 = pack_fixture();
  patch_be32(&mut p2, 8, 1000);
  if !err_pack_is(git2_pack_walk(&p2, 20), "git2: pack object count exceeds file size at 8") { ok = false; }
  var p3 = Vec[UInt8].new();
  var i = 0;
  while i < 60 {
    p3.push(p[i]);
    i = i + 1;
  }
  if !err_pack_is(git2_pack_walk(&p3, 20), "git2: entry overruns pack trailer at 29") { ok = false; }
  return assert(ok, "pack walk: OFS delta resolves \"helloxyz\"; trailer preserved; CRC check vector");
}

fn t22() -> TestResult {
  var ids = Vec[UInt8].new();
  push_all(&mut ids, &id20(1));
  push_all(&mut ids, &id20(2));
  var crcs = Vec[Int].new();
  crcs.push(286331153);
  crcs.push(572662306);
  var raws = Vec[Int].new();
  raws.push(12);
  raws.push(29);
  var larges = Vec[Int].new();
  let ix = idx_build(&ids, &crcs, &raws, &larges);
  let r = git2_idx_parse(&ix, 20);
  var ok = true;
  if !r.is_ok {
    ok = false;
  } else {
    let idx: GitIndex = r.value;
    if git2_idx_count(&idx) != 2 { ok = false; }
    if !int_is(git2_idx_fanout(&idx, 0), 0) { ok = false; }
    if !int_is(git2_idx_fanout(&idx, 1), 1) { ok = false; }
    if !int_is(git2_idx_fanout(&idx, 2), 2) { ok = false; }
    if !int_is(git2_idx_fanout(&idx, 255), 2) { ok = false; }
    if git2_idx_lookup(&idx, &id20(2), 20) != 1 { ok = false; }
    if git2_idx_lookup(&idx, &id20(1), 20) != 0 { ok = false; }
    if git2_idx_lookup(&idx, &id20(3), 20) != -1 { ok = false; }
    if git2_idx_lookup(&idx, &id20(1), 32) != -1 { ok = false; }
    if !int_is(git2_idx_offset(&idx, 1), 29) { ok = false; }
    if !int_is(git2_idx_crc(&idx, 1), 572662306) { ok = false; }
    if !int_is(git2_idx_id_byte(&idx, 1, 0), 2) { ok = false; }
    let cs: Int = idx.pack_checksum.len();
    if cs != 20 { ok = false; }
  }
  var ids1 = Vec[UInt8].new();
  push_all(&mut ids1, &id20(3));
  var crcs1 = Vec[Int].new();
  crcs1.push(858993459);
  var raws1 = Vec[Int].new();
  raws1.push(2147483648);
  var larges1 = Vec[Int].new();
  larges1.push(4886718345);
  let ix2 = idx_build(&ids1, &crcs1, &raws1, &larges1);
  let r2 = git2_idx_parse(&ix2, 20);
  if !r2.is_ok {
    ok = false;
  } else {
    let idx2: GitIndex = r2.value;
    if !int_is(git2_idx_offset(&idx2, 0), 4886718345) { ok = false; }
    let nl: Int = idx2.large_offset.len();
    if nl != 1 { ok = false; }
  }
  return assert(ok, "idx v2: fanout bounds, sorted-id lookup, CRCs, 64-bit offset table");
}

fn t23() -> TestResult {
  let p = pack_fixture();
  let wr = git2_pack_walk(&p, 20);
  var ok = true;
  var ids = Vec[UInt8].new();
  push_all(&mut ids, &id20(1));
  push_all(&mut ids, &id20(2));
  var crcs = Vec[Int].new();
  var raws = Vec[Int].new();
  raws.push(12);
  raws.push(29);
  var larges = Vec[Int].new();
  var ix = Vec[UInt8].new();
  if !wr.is_ok {
    ok = false;
  } else {
    let pk: GitPack = wr.value;
    let s0: Int = pk.entry_offset[0];
    let e0: Int = pk.entry_end[0];
    let s1: Int = pk.entry_offset[1];
    let e1: Int = pk.entry_end[1];
    crcs.push(test_crc32_range(&p, s0, e0));
    crcs.push(test_crc32_range(&p, s1, e1));
    ix = idx_build(&ids, &crcs, &raws, &larges);
    let r = git2_idx_parse(&ix, 20);
    if !r.is_ok {
      ok = false;
    } else {
      let idx: GitIndex = r.value;
      if !bool_is(git2_idx_verify_crc(&idx, &p, 0), true) { ok = false; }
      if !bool_is(git2_idx_verify_crc(&idx, &p, 1), true) { ok = false; }
      var ix2 = clone_bytes(&ix);
      patch_be32(&mut ix2, 1072, 1);
      let r2 = git2_idx_parse(&ix2, 20);
      if !r2.is_ok {
        ok = false;
      } else {
        let idx2: GitIndex = r2.value;
        if !bool_is(git2_idx_verify_crc(&idx2, &p, 0), false) { ok = false; }
      }
    }
  }
  var bad = clone_bytes(&ix);
  bad[0] = 1 as UInt8;
  if !err_pidx_is(git2_idx_parse(&bad, 20), "git2: bad idx magic at 0") { ok = false; }
  var badver = clone_bytes(&ix);
  patch_be32(&mut badver, 4, 3);
  if !err_pidx_is(git2_idx_parse(&badver, 20), "git2: unsupported idx version at 4") { ok = false; }
  var badfan = clone_bytes(&ix);
  patch_be32(&mut badfan, 28, 0);
  if !err_pidx_is(git2_idx_parse(&badfan, 20), "git2: idx fanout not monotonic at 28") { ok = false; }
  var badmism = clone_bytes(&ix);
  patch_be32(&mut badmism, 12, 0);
  if !err_pidx_is(git2_idx_parse(&badmism, 20), "git2: idx fanout mismatch at 12") { ok = false; }
  var idsu = Vec[UInt8].new();
  push_all(&mut idsu, &id20(1));
  push_all(&mut idsu, &id_pref(1, 2));
  push_all(&mut idsu, &id_pref(1, 1));
  var crcsu = Vec[Int].new();
  crcsu.push(1);
  crcsu.push(2);
  crcsu.push(3);
  var rawsu = Vec[Int].new();
  rawsu.push(12);
  rawsu.push(29);
  rawsu.push(40);
  let ixu = idx_build(&idsu, &crcsu, &rawsu, &larges);
  if !err_pidx_is(git2_idx_parse(&ixu, 20), "git2: idx ids not sorted at 1072") { ok = false; }
  var cut = Vec[UInt8].new();
  var i = 0;
  while i < 100 {
    cut.push(ix[i]);
    i = i + 1;
  }
  if !err_pidx_is(git2_idx_parse(&cut, 20), "git2: truncated idx fanout at 100") { ok = false; }
  var extra = clone_bytes(&ix);
  extra.push(0 as UInt8);
  let want_tail = "git2: trailing bytes in idx at " + convert.int_to_string(ix.len());
  if !err_pidx_is(git2_idx_parse(&extra, 20), want_tail) { ok = false; }
  return assert(ok, "idx CRC verification and malformed magic/version/fanout/sorting/truncation/trailing");
}

fn t24() -> TestResult {
  var ok = true;
  var eh = Vec[UInt8].new();
  eh.push(117 as UInt8);
  var i = 0;
  while i < 20 {
    eh.push((171 + i) as UInt8);
    i = i + 1;
  }
  let r = git2_pack_entry_header(&eh, 0, 20);
  if !r.is_ok {
    ok = false;
  } else {
    let h: GitPackEntryHeader = r.value;
    if h.entry_type != 7 { ok = false; }
    if h.size != 5 { ok = false; }
    if h.header_size != 21 { ok = false; }
    if h.data_offset != 21 { ok = false; }
    let bl: Int = h.base_id.len();
    if bl != 20 { ok = false; }
    let b0: UInt8 = h.base_id[0];
    if ((b0 as Int) & 0xFF) != 171 { ok = false; }
  }
  var d = Vec[UInt8].new();
  d.push(5 as UInt8);
  d.push(5 as UInt8);
  d.push(144 as UInt8);
  d.push(5 as UInt8);
  let z = zlib_wrap(&deflate_stored(&d), &d);
  var pack = Vec[UInt8].new();
  pack.push(80 as UInt8);
  pack.push(65 as UInt8);
  pack.push(67 as UInt8);
  pack.push(75 as UInt8);
  push_be32(&mut pack, 2);
  push_be32(&mut pack, 1);
  pack.push(116 as UInt8);
  push_all(&mut pack, &id20(9));
  push_all(&mut pack, &z);
  push_all(&mut pack, &zeros(20));
  let wr = git2_pack_walk(&pack, 20);
  if !wr.is_ok {
    ok = false;
  } else {
    let pk: GitPack = wr.value;
    let t: Int = pk.entry_type[0];
    if t != 7 { ok = false; }
    if !err_bytes_is(git2_pack_resolve(&pk, 0), "git2: ref delta needs external base at 12") { ok = false; }
    let bid: UInt8 = pk.entry_base_id[0];
    if ((bid as Int) & 0xFF) != 9 { ok = false; }
    let nbid: Int = pk.entry_base_id.len();
    if nbid != 20 { ok = false; }
  }
  return assert(ok, "REF_DELTA header, walked ref pack, caller-side base error and preserved base id");
}

fn main() -> Int {
  io.println("=== xiom.git2 conformance tests ===");
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
    io.println("xiom.git2: all tests passed");
  } else {
    io.println("xiom.git2: tests failed");
  }
  return failed;
}



