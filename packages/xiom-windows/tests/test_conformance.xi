// XIOM -- xiom.windows conformance tests (25 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Covers the documented read-only REGF structure parser: a synthetic hive
// (base block + three hbins + root/child/grand/other/A/B keys, lf/li/ri
// lists, values of every storage kind: inline DWORD, direct QWORD,
// REG_SZ, REG_MULTI_SZ, REG_BINARY and db big data, one sk cell, one
// deleted nk cell) plus malformed-signature/version/offset/size/cell
// cases. Fixture bytes are assembled here byte by byte (independent of
// src/windows.xi). Str equality goes through str_compare (BUG 17
// discipline: `==` on a Str read from a Vec lowers to a pointer compare).

module windows_tests
use xiom.io; use xiom.test;
use xiom.windows;
use xiom.string;
use xiom.string.compare;

// --------------------------------------------------
//  Generic test helpers
// --------------------------------------------------

fn str_eq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn err_hive_is(r: Result[RegfHive, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_int_is(r: Result[Int, Str], want: Str) -> Bool {
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

fn err_strs_is(r: Result[Vec[Str], Str], want: Str) -> Bool {
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

fn str_is(r: Result[Str, Str], want: Str) -> Bool {
  if !r.is_ok {
    return false;
  }
  let v: Str = r.value;
  return str_eq(v, want);
}

// Expected "regf: ... at 0x%08x" text for a malformed-input check.
fn msg(m: Str, off: Int) -> Str {
  return m + " at 0x" + h8(off);
}

// 8 lowercase hex digits of `v` (independent of the parser's helper).
fn h8(v: Int) -> Str {
  var out = Vec[UInt8].new();
  var q = v;
  var i = 0;
  while i < 8 {
    var r = q % 16;
    if r < 0 {
      r = r + 16;
    }
    q = (q - r) / 16;
    if r < 10 {
      out.push((48 + r) as UInt8);
    } else {
      out.push((87 + r) as UInt8);
    }
    i = i + 1;
  }
  var lo = 0;
  var hi = 7;
  while lo < hi {
    let tmp: UInt8 = out[lo];
    out[lo] = out[hi];
    out[hi] = tmp;
    lo = lo + 1;
    hi = hi - 1;
  }
  return Str::from_utf8(out);
}

// --------------------------------------------------
//  Byte helpers (independent of src/windows.xi)
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

fn put_u8(v: &mut Vec[UInt8], off: Int, val: Int) {
  v[off] = (val % 256) as UInt8;
}

// Byte `k` (0 = least significant) of `val`'s two's-complement pattern.
fn low_byte(val: Int, k: Int) -> Int {
  var q = val;
  var i = 0;
  while i < k {
    var r = q % 256;
    if r < 0 {
      r = r + 256;
    }
    q = (q - r) / 256;
    i = i + 1;
  }
  var b = q % 256;
  if b < 0 {
    b = b + 256;
  }
  return b;
}

// Patch `size` (1..8) little-endian bytes at `off` with `val`.
fn put_uint(v: &mut Vec[UInt8], off: Int, val: Int, size: Int) {
  var i = 0;
  while i < size {
    v[off + i] = low_byte(val, i) as UInt8;
    i = i + 1;
  }
}

fn bytes_of(s: Str) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < s.len() {
    out.push(((s.byte_at(i) as Int) & 0xFF) as UInt8);
    i = i + 1;
  }
  return out;
}

fn utf8_of(codes: Vec[Int]) -> Str {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < codes.len() {
    let c: Int = codes[i];
    v.push(c as UInt8);
    i = i + 1;
  }
  return Str::from_utf8(v);
}

// UTF-16LE bytes of a list of code points.
fn utf16_of(codes: Vec[Int]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < codes.len() {
    let c: Int = codes[i];
    out.push((c % 256) as UInt8);
    out.push(((c / 256) % 256) as UInt8);
    i = i + 1;
  }
  return out;
}

// --------------------------------------------------
//  Fixture helpers
// --------------------------------------------------

// Write an hbin header: signature, offset-from-first, size, reserved
// zeros, timestamp, spare.
fn put_hbin(buf: &mut Vec[UInt8], abs: Int, rel: Int, size: Int, ts: Int) {
  put_u8(buf, abs, 104);
  put_u8(buf, abs + 1, 98);
  put_u8(buf, abs + 2, 105);
  put_u8(buf, abs + 3, 110);
  put_uint(buf, abs + 4, rel, 4);
  put_uint(buf, abs + 8, size, 4);
  put_uint(buf, abs + 20, ts, 8);
}

// Place one cell: signed size (negative when allocated), payload bytes,
// zero padding to an 8-byte multiple. Returns the total cell size.
fn place(buf: &mut Vec[UInt8], pos: Int, alloc: Bool, payload: Vec[UInt8]) -> Int {
  let n = payload.len();
  var total = 4 + n;
  var pad = total % 8;
  if pad != 0 {
    pad = 8 - pad;
  }
  total = total + pad;
  if alloc {
    put_uint(buf, pos, 0 - total, 4);
  } else {
    put_uint(buf, pos, total, 4);
  }
  var i = 0;
  while i < n {
    put_u8(buf, pos + 4 + i, (payload[i] as Int) & 0xFF);
    i = i + 1;
  }
  return total;
}

// nk payload: 76 fixed bytes with name length + name bytes; cross
// references stay zero and are patched by the fixture builder.
fn mk_nk(name_len: Int, name_bytes: Vec[UInt8]) -> Vec[UInt8] {
  var p = zeros(76 + name_bytes.len());
  put_u8(&mut p, 0, 110);
  put_u8(&mut p, 1, 107);
  put_uint(&mut p, 72, name_len, 2);
  var i = 0;
  while i < name_bytes.len() {
    put_u8(&mut p, 76 + i, (name_bytes[i] as Int) & 0xFF);
    i = i + 1;
  }
  return p;
}

// vk payload: 20 fixed bytes with name length + name bytes.
fn mk_vk(name_len: Int, name_bytes: Vec[UInt8]) -> Vec[UInt8] {
  var p = zeros(20 + name_bytes.len());
  put_u8(&mut p, 0, 118);
  put_u8(&mut p, 1, 107);
  put_uint(&mut p, 2, name_len, 2);
  var i = 0;
  while i < name_bytes.len() {
    put_u8(&mut p, 20 + i, (name_bytes[i] as Int) & 0xFF);
    i = i + 1;
  }
  return p;
}

// Single-element Int vector (vector literals are avoided).
fn v1(a: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  return v;
}

fn v4(a: Int, b: Int, c: Int, d: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  v.push(b);
  v.push(c);
  v.push(d);
  return v;
}

fn v5(a: Int, b: Int, c: Int, d: Int, e: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  v.push(b);
  v.push(c);
  v.push(d);
  v.push(e);
  return v;
}

// Backslash separator, built at runtime so no escape sequence is needed.
fn bs() -> Str {
  return utf8_of(v1(92));
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

// Patch the cross-reference fields of an nk cell.
fn set_nk(buf: &mut Vec[UInt8], cell: Int, flags: Int, parent: Int, sub_count: Int, sub_list: Int, vol_count: Int, vol_list: Int, val_count: Int, val_list: Int, sec: Int, class_off: Int) {
  put_uint(buf, cell + 6, flags, 2);
  put_uint(buf, cell + 20, parent, 4);
  put_uint(buf, cell + 24, sub_count, 4);
  put_uint(buf, cell + 28, vol_count, 4);
  put_uint(buf, cell + 32, sub_list, 4);
  put_uint(buf, cell + 36, vol_list, 4);
  put_uint(buf, cell + 40, val_count, 4);
  put_uint(buf, cell + 44, val_list, 4);
  put_uint(buf, cell + 48, sec, 4);
  put_uint(buf, cell + 52, class_off, 4);
}

// Patch the cross-reference fields of a vk cell.
fn set_vk(buf: &mut Vec[UInt8], cell: Int, size_raw: Int, data_off: Int, dtype: Int, flags: Int) {
  put_uint(buf, cell + 8, size_raw, 4);
  put_uint(buf, cell + 12, data_off, 4);
  put_uint(buf, cell + 16, dtype, 4);
  put_uint(buf, cell + 20, flags, 2);
}

// --------------------------------------------------
//  The conformance fixture (28672 bytes)
// --------------------------------------------------
//
//   base block            0..4095      "regf", seq 1/1, file type 0,
//                                      format 1, root rel 0x20, hbin data
//                                      size 24576, cluster 1, name "TEST"
//   hbin 0                0x1000       size 4096, rel 0, ts 0x111...
//     cells from 0x1020:  root nk (0x1020, 88), child nk (0x1078, 96),
//     grand nk (0x10D8, 88), other nk (0x1130, 88), A nk (0x1188, 88),
//     B nk (0x11E0, 88), lf list (0x1238, 24), li list (0x1250, 16),
//     ri list (0x1260, 16), li list (0x1270, 16), value lists (0x1280/16,
//     0x1290/16, 0x12A0/8), six vk cells (0x12A8..0x1348, 32 each), qword
//     data (0x1368, 16), sz data (0x1378, 16), multi data (0x1388, 16),
//     bin data (0x1398, 16), db (0x13A8, 16), segment list (0x13B8, 16),
//     sk (0x13C8, 32), deleted nk (0x13E8, 88), free filler (0x1440,3008)
//   hbin 1                0x2000       size 16384, rel 4096, ts 0x222...
//     big segment 1 (0x2020, 16352)
//   hbin 2                0x6000       size 4096, rel 20480, ts 0x333...
//     big segment 2 (0x6020, 8), free filler (0x6028, 4056)
//
// Tree: ROOT {Child {Grand}, Other {A, B}}; values in walk order:
// Dword (inline 0x11223344), Qword (direct), Sz (direct "Hello"),
// Multi (direct "A","B"), Bin (direct 5 bytes), Big (db, 16345 bytes).
fn fx() -> Vec[UInt8] {
  var buf = zeros(28672);
  put_hbin(&mut buf, 4096, 0, 4096, 0x1111111111111111);
  put_hbin(&mut buf, 8192, 4096, 16384, 0x2222222222222222);
  put_hbin(&mut buf, 24576, 20480, 4096, 0x3333333333333333);
  var pos = 4128;
  let a_root = pos;
  pos = pos + place(&mut buf, pos, true, mk_nk(4, bytes_of("ROOT")));
  let a_child = pos;
  pos = pos + place(&mut buf, pos, true, mk_nk(10, utf16_of(v5(67, 104, 105, 108, 100))));
  let a_grand = pos;
  pos = pos + place(&mut buf, pos, true, mk_nk(8, utf16_of(v4(67, 97, 102, 233))));
  let a_other = pos;
  pos = pos + place(&mut buf, pos, true, mk_nk(5, bytes_of("Other")));
  let a_a = pos;
  pos = pos + place(&mut buf, pos, true, mk_nk(1, bytes_of("A")));
  let a_b = pos;
  pos = pos + place(&mut buf, pos, true, mk_nk(1, bytes_of("B")));
  let a_lf = pos;
  pos = pos + place(&mut buf, pos, true, zeros(20));
  let a_li1 = pos;
  pos = pos + place(&mut buf, pos, true, zeros(8));
  let a_ri = pos;
  pos = pos + place(&mut buf, pos, true, zeros(8));
  let a_li2 = pos;
  pos = pos + place(&mut buf, pos, true, zeros(12));
  let a_vl1 = pos;
  pos = pos + place(&mut buf, pos, true, zeros(12));
  let a_vl2 = pos;
  pos = pos + place(&mut buf, pos, true, zeros(8));
  let a_vl3 = pos;
  pos = pos + place(&mut buf, pos, true, zeros(4));
  let a_dword = pos;
  pos = pos + place(&mut buf, pos, true, mk_vk(5, bytes_of("Dword")));
  let a_qword_vk = pos;
  pos = pos + place(&mut buf, pos, true, mk_vk(5, bytes_of("Qword")));
  let a_sz_vk = pos;
  pos = pos + place(&mut buf, pos, true, mk_vk(2, bytes_of("Sz")));
  let a_multi_vk = pos;
  pos = pos + place(&mut buf, pos, true, mk_vk(5, bytes_of("Multi")));
  let a_bin_vk = pos;
  pos = pos + place(&mut buf, pos, true, mk_vk(3, bytes_of("Bin")));
  let a_big_vk = pos;
  pos = pos + place(&mut buf, pos, true, mk_vk(3, bytes_of("Big")));
  let a_qword = pos;
  pos = pos + place(&mut buf, pos, true, zeros(8));
  let a_sz = pos;
  pos = pos + place(&mut buf, pos, true, zeros(12));
  let a_multi = pos;
  pos = pos + place(&mut buf, pos, true, zeros(10));
  let a_bin = pos;
  pos = pos + place(&mut buf, pos, true, zeros(5));
  let a_db = pos;
  pos = pos + place(&mut buf, pos, true, zeros(8));
  let a_seglist = pos;
  pos = pos + place(&mut buf, pos, true, zeros(8));
  let a_sk = pos;
  pos = pos + place(&mut buf, pos, true, zeros(28));
  pos = pos + place(&mut buf, pos, false, mk_nk(3, bytes_of("Old")));
  pos = pos + place(&mut buf, pos, false, zeros(3000));
  pos = 8192 + 32;
  let a_seg1 = pos;
  pos = pos + place(&mut buf, pos, true, zeros(16344));
  pos = 24576 + 32;
  let a_seg2 = pos;
  pos = pos + place(&mut buf, pos, true, zeros(1));
  pos = pos + place(&mut buf, pos, false, zeros(4050));
  let r = 4096;
  put_u8(&mut buf, 0, 114);
  put_u8(&mut buf, 1, 101);
  put_u8(&mut buf, 2, 103);
  put_u8(&mut buf, 3, 102);
  put_uint(&mut buf, 4, 1, 4);
  put_uint(&mut buf, 8, 1, 4);
  put_uint(&mut buf, 12, 0x0102030405060708, 8);
  put_uint(&mut buf, 20, 1, 4);
  put_uint(&mut buf, 24, 5, 4);
  put_uint(&mut buf, 28, 0, 4);
  put_uint(&mut buf, 32, 1, 4);
  put_uint(&mut buf, 36, a_root - r, 4);
  put_uint(&mut buf, 40, 24576, 4);
  put_uint(&mut buf, 44, 1, 4);
  put_u8(&mut buf, 48, 84);
  put_u8(&mut buf, 50, 69);
  put_u8(&mut buf, 52, 83);
  put_u8(&mut buf, 54, 84);
  set_nk(&mut buf, a_root, 36, 0xFFFFFFFF, 2, a_lf - r, 0, 0xFFFFFFFF, 3, a_vl1 - r, a_sk - r, 0xFFFFFFFF);
  put_uint(&mut buf, a_root + 56, 8, 4);
  put_uint(&mut buf, a_root + 60, 0, 4);
  put_uint(&mut buf, a_root + 64, 12, 4);
  put_uint(&mut buf, a_root + 68, 16345, 4);
  set_nk(&mut buf, a_child, 0, a_root - r, 1, a_li1 - r, 0, 0xFFFFFFFF, 2, a_vl2 - r, a_sk - r, 0xFFFFFFFF);
  set_nk(&mut buf, a_grand, 0, a_child - r, 0, 0xFFFFFFFF, 0, 0xFFFFFFFF, 0, 0xFFFFFFFF, a_sk - r, 0xFFFFFFFF);
  set_nk(&mut buf, a_other, 32, a_root - r, 2, a_ri - r, 0, 0xFFFFFFFF, 1, a_vl3 - r, a_sk - r, 0xFFFFFFFF);
  set_nk(&mut buf, a_a, 32, a_other - r, 0, 0xFFFFFFFF, 0, 0xFFFFFFFF, 0, 0xFFFFFFFF, a_sk - r, 0xFFFFFFFF);
  set_nk(&mut buf, a_b, 32, a_other - r, 0, 0xFFFFFFFF, 0, 0xFFFFFFFF, 0, 0xFFFFFFFF, a_sk - r, 0xFFFFFFFF);
  put_u8(&mut buf, a_lf + 4, 108);
  put_u8(&mut buf, a_lf + 5, 102);
  put_uint(&mut buf, a_lf + 6, 2, 2);
  put_uint(&mut buf, a_lf + 8, a_child - r, 4);
  put_uint(&mut buf, a_lf + 12, 0, 4);
  put_uint(&mut buf, a_lf + 16, a_other - r, 4);
  put_uint(&mut buf, a_lf + 20, 0, 4);
  put_u8(&mut buf, a_li1 + 4, 108);
  put_u8(&mut buf, a_li1 + 5, 105);
  put_uint(&mut buf, a_li1 + 6, 1, 2);
  put_uint(&mut buf, a_li1 + 8, a_grand - r, 4);
  put_u8(&mut buf, a_ri + 4, 114);
  put_u8(&mut buf, a_ri + 5, 105);
  put_uint(&mut buf, a_ri + 6, 1, 2);
  put_uint(&mut buf, a_ri + 8, a_li2 - r, 4);
  put_u8(&mut buf, a_li2 + 4, 108);
  put_u8(&mut buf, a_li2 + 5, 105);
  put_uint(&mut buf, a_li2 + 6, 2, 2);
  put_uint(&mut buf, a_li2 + 8, a_a - r, 4);
  put_uint(&mut buf, a_li2 + 12, a_b - r, 4);
  put_uint(&mut buf, a_vl1 + 4, a_dword - r, 4);
  put_uint(&mut buf, a_vl1 + 8, a_qword_vk - r, 4);
  put_uint(&mut buf, a_vl1 + 12, a_sz_vk - r, 4);
  put_uint(&mut buf, a_vl2 + 4, a_multi_vk - r, 4);
  put_uint(&mut buf, a_vl2 + 8, a_bin_vk - r, 4);
  put_uint(&mut buf, a_vl3 + 4, a_big_vk - r, 4);
  set_vk(&mut buf, a_dword, 0x80000004, 0x11223344, 4, 1);
  set_vk(&mut buf, a_qword_vk, 8, a_qword - r, 11, 1);
  set_vk(&mut buf, a_sz_vk, 12, a_sz - r, 1, 1);
  set_vk(&mut buf, a_multi_vk, 10, a_multi - r, 7, 1);
  set_vk(&mut buf, a_bin_vk, 5, a_bin - r, 3, 1);
  set_vk(&mut buf, a_big_vk, 16345, a_db - r, 3, 1);
  put_uint(&mut buf, a_qword + 4, 0x1122334455667788, 8);
  put_u8(&mut buf, a_sz + 4, 72);
  put_u8(&mut buf, a_sz + 6, 101);
  put_u8(&mut buf, a_sz + 8, 108);
  put_u8(&mut buf, a_sz + 10, 108);
  put_u8(&mut buf, a_sz + 12, 111);
  put_u8(&mut buf, a_multi + 4, 65);
  put_u8(&mut buf, a_multi + 8, 66);
  put_u8(&mut buf, a_bin + 4, 1);
  put_u8(&mut buf, a_bin + 5, 2);
  put_u8(&mut buf, a_bin + 6, 3);
  put_u8(&mut buf, a_bin + 7, 4);
  put_u8(&mut buf, a_bin + 8, 5);
  put_u8(&mut buf, a_db + 4, 100);
  put_u8(&mut buf, a_db + 5, 98);
  put_uint(&mut buf, a_db + 6, 2, 2);
  put_uint(&mut buf, a_db + 8, a_seglist - r, 4);
  put_uint(&mut buf, a_seglist + 4, a_seg1 - r, 4);
  put_uint(&mut buf, a_seglist + 8, a_seg2 - r, 4);
  put_u8(&mut buf, a_seg1 + 4, 0xAB);
  put_u8(&mut buf, a_seg1 + 4 + 16343, 0xCD);
  put_u8(&mut buf, a_seg2 + 4, 0x42);
  put_u8(&mut buf, a_sk + 4, 115);
  put_u8(&mut buf, a_sk + 5, 107);
  put_uint(&mut buf, a_sk + 16, 1, 4);
  put_uint(&mut buf, a_sk + 20, 8, 4);
  return buf;
}

// --------------------------------------------------
//  Structure and walk tests
// --------------------------------------------------

fn t1() -> TestResult {
  let d = fx();
  let r = regf_parse(&d);
  if !r.is_ok {
    return assert(false, "fixture must parse");
  }
  let f: RegfHive = r.value;
  var ok = regf_key_count(&f) == 6;
  if regf_value_count(&f) != 6 {
    ok = false;
  }
  if regf_cell_count(&f) != 31 {
    ok = false;
  }
  if regf_hbin_count(&f) != 3 {
    ok = false;
  }
  if regf_free_cell_count(&f) != 3 {
    ok = false;
  }
  return assert(ok, "fixture parses: 6 keys, 6 values, 31 cells, 3 hbins, 3 free cells");
}

fn t2() -> TestResult {
  let d = fx();
  let r = regf_parse(&d);
  if !r.is_ok {
    return assert(false, "fixture must parse");
  }
  let f: RegfHive = r.value;
  var ok = regf_primary_sequence(&f) == 1;
  if regf_secondary_sequence(&f) != 1 {
    ok = false;
  }
  if regf_sequence_mismatch(&f) {
    ok = false;
  }
  if regf_timestamp(&f) != 0x0102030405060708 {
    ok = false;
  }
  if regf_version_major(&f) != 1 {
    ok = false;
  }
  if regf_version_minor(&f) != 5 {
    ok = false;
  }
  if regf_file_type(&f) != 0 {
    ok = false;
  }
  if regf_file_format(&f) != 1 {
    ok = false;
  }
  if regf_root_cell_offset(&f) != 0x20 {
    ok = false;
  }
  if regf_root_offset(&f) != 0x1020 {
    ok = false;
  }
  if regf_hbin_data_size(&f) != 24576 {
    ok = false;
  }
  if regf_cluster_factor(&f) != 1 {
    ok = false;
  }
  if regf_checksum(&f) != 0 {
    ok = false;
  }
  if !str_eq(regf_file_name(&f), "TEST") {
    ok = false;
  }
  return assert(ok, "base block fields: sequence, timestamp, version, type, format, offsets, name");
}

fn t3() -> TestResult {
  let d = fx();
  let r = regf_parse(&d);
  if !r.is_ok {
    return assert(false, "fixture must parse");
  }
  let f: RegfHive = r.value;
  var ok = int_is(regf_hbin_offset(&f, 0), 4096);
  if !int_is(regf_hbin_rel_offset(&f, 0), 0) {
    ok = false;
  }
  if !int_is(regf_hbin_size(&f, 0), 4096) {
    ok = false;
  }
  if !int_is(regf_hbin_timestamp(&f, 0), 0x1111111111111111) {
    ok = false;
  }
  if !int_is(regf_hbin_offset(&f, 1), 8192) {
    ok = false;
  }
  if !int_is(regf_hbin_rel_offset(&f, 1), 4096) {
    ok = false;
  }
  if !int_is(regf_hbin_size(&f, 1), 16384) {
    ok = false;
  }
  if !int_is(regf_hbin_timestamp(&f, 1), 0x2222222222222222) {
    ok = false;
  }
  if !int_is(regf_hbin_offset(&f, 2), 24576) {
    ok = false;
  }
  if !int_is(regf_hbin_rel_offset(&f, 2), 20480) {
    ok = false;
  }
  if !int_is(regf_hbin_size(&f, 2), 4096) {
    ok = false;
  }
  if !int_is(regf_hbin_timestamp(&f, 2), 0x3333333333333333) {
    ok = false;
  }
  if !int_is(regf_hbin_spare(&f, 0), 0) {
    ok = false;
  }
  if !err_int_is(regf_hbin_size(&f, 3), "regf: index out of range") {
    ok = false;
  }
  return assert(ok, "hbin table: absolute/relative offsets, 4096-multiple sizes, timestamps");
}

fn t4() -> TestResult {
  let d = fx();
  let r = regf_parse(&d);
  if !r.is_ok {
    return assert(false, "fixture must parse");
  }
  let f: RegfHive = r.value;
  var ok = int_is(regf_cell_offset(&f, 0), 0x1020);
  if !int_is(regf_cell_size(&f, 0), 88) {
    ok = false;
  }
  if !int_is(regf_cell_allocated(&f, 0), 1) {
    ok = false;
  }
  if !int_is(regf_cell_kind(&f, 0), 1) {
    ok = false;
  }
  if !int_is(regf_cell_hbin(&f, 0), 0) {
    ok = false;
  }
  if !int_is(regf_cell_offset(&f, 26), 0x13E8) {
    ok = false;
  }
  if !int_is(regf_cell_size(&f, 26), 88) {
    ok = false;
  }
  if !int_is(regf_cell_allocated(&f, 26), 0) {
    ok = false;
  }
  if !int_is(regf_cell_kind(&f, 26), 1) {
    ok = false;
  }
  if !int_is(regf_cell_offset(&f, 28), 0x2020) {
    ok = false;
  }
  if !int_is(regf_cell_size(&f, 28), 16352) {
    ok = false;
  }
  if !int_is(regf_cell_hbin(&f, 28), 1) {
    ok = false;
  }
  if !int_is(regf_cell_offset(&f, 30), 0x6028) {
    ok = false;
  }
  if !int_is(regf_cell_size(&f, 30), 4056) {
    ok = false;
  }
  if !int_is(regf_cell_allocated(&f, 30), 0) {
    ok = false;
  }
  if !int_is(regf_cell_kind(&f, 30), 0) {
    ok = false;
  }
  if regf_cell_index_by_offset(&f, 0x1020) != 0 {
    ok = false;
  }
  if regf_cell_index_by_offset(&f, 0x1024) != -1 {
    ok = false;
  }
  if !err_int_is(regf_cell_offset(&f, 31), "regf: index out of range") {
    ok = false;
  }
  return assert(ok, "cell table: offsets, sizes, allocated flags, kinds, hbin index, lookup");
}

fn t5() -> TestResult {
  let d = fx();
  let r = regf_parse(&d);
  if !r.is_ok {
    return assert(false, "fixture must parse");
  }
  let f: RegfHive = r.value;
  var ok = int_is(regf_key_field(&f, 0, REGF_KEY_FIELD_FLAGS), 36);
  if !int_is(regf_key_field(&f, 0, REGF_KEY_FIELD_PARENT_OFFSET), 0xFFFFFFFF) {
    ok = false;
  }
  if !int_is(regf_key_field(&f, 0, REGF_KEY_FIELD_SUBKEY_COUNT), 2) {
    ok = false;
  }
  if !int_is(regf_key_field(&f, 0, REGF_KEY_FIELD_VOLATILE_SUBKEY_COUNT), 0) {
    ok = false;
  }
  if !int_is(regf_key_field(&f, 0, REGF_KEY_FIELD_SUBKEY_LIST_OFFSET), 0x238) {
    ok = false;
  }
  if !int_is(regf_key_field(&f, 0, REGF_KEY_FIELD_VALUE_COUNT), 3) {
    ok = false;
  }
  if !int_is(regf_key_field(&f, 0, REGF_KEY_FIELD_VALUE_LIST_OFFSET), 0x280) {
    ok = false;
  }
  if !int_is(regf_key_field(&f, 0, REGF_KEY_FIELD_SECURITY_OFFSET), 0x3C8) {
    ok = false;
  }
  if !int_is(regf_key_field(&f, 0, REGF_KEY_FIELD_CLASS_OFFSET), 0xFFFFFFFF) {
    ok = false;
  }
  if !int_is(regf_key_field(&f, 0, REGF_KEY_FIELD_LARGEST_SUBKEY_NAME), 8) {
    ok = false;
  }
  if !int_is(regf_key_field(&f, 0, REGF_KEY_FIELD_LARGEST_VALUE_NAME), 12) {
    ok = false;
  }
  if !int_is(regf_key_field(&f, 0, REGF_KEY_FIELD_LARGEST_VALUE_DATA), 16345) {
    ok = false;
  }
  if !int_is(regf_key_field(&f, 0, REGF_KEY_FIELD_NAME_LENGTH), 4) {
    ok = false;
  }
  if !int_is(regf_key_field(&f, 0, REGF_KEY_FIELD_CELL_OFFSET), 0x1020) {
    ok = false;
  }
  if !int_is(regf_key_field(&f, 0, REGF_KEY_FIELD_SUBKEY_LIST_COUNT), 2) {
    ok = false;
  }
  if !int_is(regf_key_field(&f, 0, REGF_KEY_FIELD_VALUE_LIST_COUNT), 3) {
    ok = false;
  }
  if !int_is(regf_key_parent(&f, 0), -1) {
    ok = false;
  }
  return assert(ok, "root nk fields via selectors: flags, counts, offsets, largest lengths");
}

fn t6() -> TestResult {
  let d = fx();
  let r = regf_parse(&d);
  if !r.is_ok {
    return assert(false, "fixture must parse");
  }
  let f: RegfHive = r.value;
  var ok = str_is(regf_key_name(&f, 0), "ROOT");
  if !str_is(regf_key_name(&f, 1), "Child") {
    ok = false;
  }
  if !str_is(regf_key_name(&f, 2), "Other") {
    ok = false;
  }
  if !str_is(regf_key_name(&f, 3), utf8_of(v5(67, 97, 102, 195, 169))) {
    ok = false;
  }
  if !str_is(regf_key_name(&f, 4), "A") {
    ok = false;
  }
  if !str_is(regf_key_name(&f, 5), "B") {
    ok = false;
  }
  if !int_is(regf_key_field(&f, 1, REGF_KEY_FIELD_NAME_LENGTH), 10) {
    ok = false;
  }
  if !int_is(regf_key_field(&f, 3, REGF_KEY_FIELD_NAME_LENGTH), 8) {
    ok = false;
  }
  if !err_str_is(regf_key_name(&f, 6), "regf: index out of range") {
    ok = false;
  }
  if !err_str_is(regf_key_name(&f, -1), "regf: index out of range") {
    ok = false;
  }
  return assert(ok, "key names: ASCII COMP_NAME, UTF-16LE (incl. non-ASCII), lengths, bounds");
}

fn t7() -> TestResult {
  let d = fx();
  let r = regf_parse(&d);
  if !r.is_ok {
    return assert(false, "fixture must parse");
  }
  let f: RegfHive = r.value;
  var ok = int_is(regf_key_parent(&f, 1), 0);
  if !int_is(regf_key_parent(&f, 2), 0) {
    ok = false;
  }
  if !int_is(regf_key_parent(&f, 3), 1) {
    ok = false;
  }
  if !int_is(regf_key_parent(&f, 4), 2) {
    ok = false;
  }
  if !int_is(regf_key_parent(&f, 5), 2) {
    ok = false;
  }
  if !int_is(regf_key_subkey_count(&f, 0), 2) {
    ok = false;
  }
  if !int_is(regf_key_subkey_count(&f, 1), 1) {
    ok = false;
  }
  if !int_is(regf_key_subkey_count(&f, 2), 2) {
    ok = false;
  }
  if !int_is(regf_key_subkey_count(&f, 3), 0) {
    ok = false;
  }
  if !int_is(regf_key_subkey(&f, 0, 0), 1) {
    ok = false;
  }
  if !int_is(regf_key_subkey(&f, 0, 1), 2) {
    ok = false;
  }
  if !int_is(regf_key_subkey(&f, 1, 0), 3) {
    ok = false;
  }
  if !int_is(regf_key_subkey(&f, 2, 0), 4) {
    ok = false;
  }
  if !int_is(regf_key_subkey(&f, 2, 1), 5) {
    ok = false;
  }
  if !int_is(regf_key_value_count(&f, 0), 3) {
    ok = false;
  }
  if !int_is(regf_key_value_count(&f, 1), 2) {
    ok = false;
  }
  if !int_is(regf_key_value_count(&f, 2), 1) {
    ok = false;
  }
  if !int_is(regf_key_value(&f, 0, 0), 0) {
    ok = false;
  }
  if !int_is(regf_key_value(&f, 0, 2), 2) {
    ok = false;
  }
  if !int_is(regf_key_value(&f, 1, 1), 4) {
    ok = false;
  }
  if !int_is(regf_key_value(&f, 2, 0), 5) {
    ok = false;
  }
  if !err_int_is(regf_key_subkey(&f, 0, 2), "regf: index out of range") {
    ok = false;
  }
  if !err_int_is(regf_key_value(&f, 3, 0), "regf: index out of range") {
    ok = false;
  }
  return assert(ok, "BFS walk: parent links, subkey/value CSR ranges, bounds errors");
}

fn t8() -> TestResult {
  let d = fx();
  let r = regf_parse(&d);
  if !r.is_ok {
    return assert(false, "fixture must parse");
  }
  let f: RegfHive = r.value;
  var ok = int_is(regf_key_field(&f, 0, REGF_KEY_FIELD_TIMESTAMP), 0);
  if !int_is(regf_key_field(&f, 0, REGF_KEY_FIELD_ACCESS_BITS), 0) {
    ok = false;
  }
  if !int_is(regf_key_field(&f, 0, REGF_KEY_FIELD_WORK_VAR), 0) {
    ok = false;
  }
  if !int_is(regf_key_field(&f, 0, REGF_KEY_FIELD_CLASS_NAME_LENGTH), 0) {
    ok = false;
  }
  if !err_int_is(regf_key_field(&f, 6, REGF_KEY_FIELD_FLAGS), "regf: index out of range") {
    ok = false;
  }
  if !err_int_is(regf_key_field(&f, -1, REGF_KEY_FIELD_FLAGS), "regf: index out of range") {
    ok = false;
  }
  if !err_int_is(regf_key_field(&f, 0, REGF_KEY_FIELD_COUNT), "regf: bad field selector") {
    ok = false;
  }
  if !err_int_is(regf_key_field(&f, 0, -1), "regf: bad field selector") {
    ok = false;
  }
  return assert(ok, "key field accessor: remaining selectors and error strings");
}

fn t9() -> TestResult {
  let d = fx();
  let r = regf_parse(&d);
  if !r.is_ok {
    return assert(false, "fixture must parse");
  }
  let f: RegfHive = r.value;
  var ok = regf_key_find(&f, 0, "child") == 1;
  if regf_key_find(&f, 0, "OTHER") != 2 {
    ok = false;
  }
  if regf_key_find(&f, 2, "b") != 5 {
    ok = false;
  }
  if regf_key_find(&f, 0, "A") != -1 {
    ok = false;
  }
  if regf_key_find(&f, 0, "nope") != -1 {
    ok = false;
  }
  if regf_key_find(&f, 99, "x") != -1 {
    ok = false;
  }
  if !regf_name_equal("RoOt", "ROOT") {
    ok = false;
  }
  if regf_name_equal("ROOT", "ROOTA") {
    ok = false;
  }
  let nested = "ROOT" + bs() + "Child" + bs();
  if !int_is(regf_path_resolve(&f, nested), 1) {
    ok = false;
  }
  let rel = "child";
  if !int_is(regf_path_resolve(&f, rel), 1) {
    ok = false;
  }
  let deep = "other" + bs() + "a";
  if !int_is(regf_path_resolve(&f, deep), 4) {
    ok = false;
  }
  let dotted = bs() + "Other" + bs();
  if !int_is(regf_path_resolve(&f, dotted), 2) {
    ok = false;
  }
  if !int_is(regf_path_resolve(&f, ""), 0) {
    ok = false;
  }
  let missing = "Child" + bs() + "Nope";
  if !err_int_is(regf_path_resolve(&f, missing), "regf: key not found") {
    ok = false;
  }
  return assert(ok, "case-insensitive child lookup and backslash path resolution");
}

fn t10() -> TestResult {
  let d = fx();
  let r = regf_parse(&d);
  if !r.is_ok {
    return assert(false, "fixture must parse");
  }
  let f: RegfHive = r.value;
  var ok = int_is(regf_value_field(&f, 0, REGF_VALUE_FIELD_NAME_LENGTH), 5);
  if !int_is(regf_value_field(&f, 0, REGF_VALUE_FIELD_DATA_SIZE), 4) {
    ok = false;
  }
  if !int_is(regf_value_field(&f, 0, REGF_VALUE_FIELD_DATA_OFFSET), 0x11223344) {
    ok = false;
  }
  if !int_is(regf_value_field(&f, 0, REGF_VALUE_FIELD_DATA_TYPE), 4) {
    ok = false;
  }
  if !int_is(regf_value_field(&f, 0, REGF_VALUE_FIELD_FLAGS), 1) {
    ok = false;
  }
  if !int_is(regf_value_field(&f, 0, REGF_VALUE_FIELD_CELL_OFFSET), 0x12A8) {
    ok = false;
  }
  if !int_is(regf_value_field(&f, 0, REGF_VALUE_FIELD_INLINE), 1) {
    ok = false;
  }
  if !int_is(regf_value_field(&f, 0, REGF_VALUE_FIELD_BIG_DATA), 0) {
    ok = false;
  }
  if !int_is(regf_value_field(&f, 0, REGF_VALUE_FIELD_SEGMENT_COUNT), 0) {
    ok = false;
  }
  if !int_is(regf_value_field(&f, 1, REGF_VALUE_FIELD_DATA_SIZE), 8) {
    ok = false;
  }
  if !int_is(regf_value_field(&f, 1, REGF_VALUE_FIELD_DATA_TYPE), 11) {
    ok = false;
  }
  if !int_is(regf_value_field(&f, 1, REGF_VALUE_FIELD_SEGMENT_COUNT), 1) {
    ok = false;
  }
  if !int_is(regf_value_field(&f, 2, REGF_VALUE_FIELD_DATA_TYPE), 1) {
    ok = false;
  }
  if !int_is(regf_value_field(&f, 3, REGF_VALUE_FIELD_DATA_TYPE), 7) {
    ok = false;
  }
  if !int_is(regf_value_field(&f, 5, REGF_VALUE_FIELD_DATA_SIZE), 16345) {
    ok = false;
  }
  if !int_is(regf_value_field(&f, 5, REGF_VALUE_FIELD_BIG_DATA), 1) {
    ok = false;
  }
  if !int_is(regf_value_field(&f, 5, REGF_VALUE_FIELD_SEGMENT_COUNT), 2) {
    ok = false;
  }
  if !err_int_is(regf_value_field(&f, 6, REGF_VALUE_FIELD_DATA_TYPE), "regf: index out of range") {
    ok = false;
  }
  if !err_int_is(regf_value_field(&f, 0, REGF_VALUE_FIELD_COUNT), "regf: bad field selector") {
    ok = false;
  }
  return assert(ok, "value metadata: sizes, raw offsets, types, inline/big flags, segment counts");
}

fn t11() -> TestResult {
  let d = fx();
  let r = regf_parse(&d);
  if !r.is_ok {
    return assert(false, "fixture must parse");
  }
  let f: RegfHive = r.value;
  var ok = str_is(regf_value_name(&f, 0), "Dword");
  if !str_is(regf_value_name(&f, 1), "Qword") {
    ok = false;
  }
  if !str_is(regf_value_name(&f, 2), "Sz") {
    ok = false;
  }
  if !str_is(regf_value_name(&f, 3), "Multi") {
    ok = false;
  }
  if !str_is(regf_value_name(&f, 4), "Bin") {
    ok = false;
  }
  if !str_is(regf_value_name(&f, 5), "Big") {
    ok = false;
  }
  if !err_str_is(regf_value_name(&f, 6), "regf: index out of range") {
    ok = false;
  }
  return assert(ok, "value names decode (compressed ASCII) with bounds errors");
}

fn t12() -> TestResult {
  let d = fx();
  let r = regf_parse(&d);
  if !r.is_ok {
    return assert(false, "fixture must parse");
  }
  let f: RegfHive = r.value;
  var ok = int_is(regf_value_dword(&d, &f, 0), 0x11223344);
  let dr = regf_value_data(&d, &f, 0);
  if !dr.is_ok {
    ok = false;
  } else {
    let bb: Vec[UInt8] = dr.value;
    if bb.len() != 4 {
      ok = false;
    } else {
      if ((bb[0] as Int) & 0xFF) != 0x44 {
        ok = false;
      }
      if ((bb[1] as Int) & 0xFF) != 0x33 {
        ok = false;
      }
      if ((bb[2] as Int) & 0xFF) != 0x22 {
        ok = false;
      }
      if ((bb[3] as Int) & 0xFF) != 0x11 {
        ok = false;
      }
    }
  }
  if !err_int_is(regf_value_dword(&d, &f, 1), "regf: value is not a dword") {
    ok = false;
  }
  if !err_int_is(regf_value_dword(&d, &f, -1), "regf: index out of range") {
    ok = false;
  }
  return assert(ok, "inline DWORD: value 0x11223344 and raw bytes live in the offset field");
}

fn t13() -> TestResult {
  let d = fx();
  let r = regf_parse(&d);
  if !r.is_ok {
    return assert(false, "fixture must parse");
  }
  let f: RegfHive = r.value;
  var ok = int_is(regf_value_qword(&d, &f, 1), 0x1122334455667788);
  let dr = regf_value_data(&d, &f, 1);
  if !dr.is_ok {
    ok = false;
  } else {
    let bb: Vec[UInt8] = dr.value;
    if bb.len() != 8 {
      ok = false;
    } else {
      if ((bb[0] as Int) & 0xFF) != 0x88 {
        ok = false;
      }
      if ((bb[7] as Int) & 0xFF) != 0x11 {
        ok = false;
      }
    }
  }
  if !err_int_is(regf_value_qword(&d, &f, 0), "regf: value is not a qword") {
    ok = false;
  }
  return assert(ok, "direct QWORD data: 0x1122334455667788 little-endian");
}

fn t14() -> TestResult {
  let d = fx();
  let r = regf_parse(&d);
  if !r.is_ok {
    return assert(false, "fixture must parse");
  }
  let f: RegfHive = r.value;
  let dr = regf_value_data(&d, &f, 2);
  var ok = false;
  if dr.is_ok {
    let bb: Vec[UInt8] = dr.value;
    ok = bb.len() == 12;
  }
  if !str_is(regf_value_str(&d, &f, 2), "Hello") {
    ok = false;
  }
  if !err_str_is(regf_value_str(&d, &f, 0), "regf: value is not a string") {
    ok = false;
  }
  return assert(ok, "REG_SZ: 12 raw bytes (UTF-16LE + NUL), decoded text without terminator");
}

fn t15() -> TestResult {
  let d = fx();
  let r = regf_parse(&d);
  if !r.is_ok {
    return assert(false, "fixture must parse");
  }
  let f: RegfHive = r.value;
  let mr = regf_value_multi_str(&d, &f, 3);
  var ok = false;
  if mr.is_ok {
    let ms: Vec[Str] = mr.value;
    ok = ms.len() == 2;
    if ok {
      let m0: Str = ms[0];
      let m1: Str = ms[1];
      if !str_eq(m0, "A") {
        ok = false;
      }
      if !str_eq(m1, "B") {
        ok = false;
      }
    }
  }
  if !err_strs_is(regf_value_multi_str(&d, &f, 4), "regf: value is not a multi string") {
    ok = false;
  }
  return assert(ok, "REG_MULTI_SZ: A and B recovered, trailing empty group dropped");
}

fn t16() -> TestResult {
  let d = fx();
  let r = regf_parse(&d);
  if !r.is_ok {
    return assert(false, "fixture must parse");
  }
  let f: RegfHive = r.value;
  let dr = regf_value_data(&d, &f, 5);
  var ok = false;
  if dr.is_ok {
    let bb: Vec[UInt8] = dr.value;
    ok = bb.len() == 16345;
    if ok {
      if ((bb[0] as Int) & 0xFF) != 0xAB {
        ok = false;
      }
      if ((bb[16343] as Int) & 0xFF) != 0xCD {
        ok = false;
      }
      if ((bb[16344] as Int) & 0xFF) != 0x42 {
        ok = false;
      }
    }
  }
  return assert(ok, "db big data: 16345 bytes reassembled across two segments in order");
}

fn t17() -> TestResult {
  let d = fx();
  let r = regf_parse(&d);
  if !r.is_ok {
    return assert(false, "fixture must parse");
  }
  let f: RegfHive = r.value;
  var ok = int_is(regf_key_sk(&f, 0, REGF_SK_FIELD_OFFSET), 0x13C8);
  if !int_is(regf_key_sk(&f, 0, REGF_SK_FIELD_REFERENCE_COUNT), 1) {
    ok = false;
  }
  if !int_is(regf_key_sk(&f, 0, REGF_SK_FIELD_DESCRIPTOR_SIZE), 8) {
    ok = false;
  }
  if !int_is(regf_key_sk(&f, 0, REGF_SK_FIELD_FLAGS), 0) {
    ok = false;
  }
  if !int_is(regf_key_sk(&f, 3, REGF_SK_FIELD_OFFSET), 0x13C8) {
    ok = false;
  }
  if !err_int_is(regf_key_sk(&f, 0, REGF_SK_FIELD_COUNT), "regf: bad field selector") {
    ok = false;
  }
  if !err_int_is(regf_key_sk(&f, 6, REGF_SK_FIELD_OFFSET), "regf: index out of range") {
    ok = false;
  }
  return assert(ok, "sk records: security cell offset, reference count, descriptor span, flags");
}

fn t18() -> TestResult {
  let d = fx();
  let r = regf_parse(&d);
  if !r.is_ok {
    return assert(false, "fixture must parse");
  }
  let f: RegfHive = r.value;
  var ok = regf_free_cell_count(&f) == 3;
  if regf_deleted_nk_count(&f) != 1 {
    ok = false;
  }
  if !int_is(regf_cell_allocated(&f, 26), 0) {
    ok = false;
  }
  if !int_is(regf_cell_kind(&f, 26), REGF_KIND_NK) {
    ok = false;
  }
  if !int_is(regf_cell_offset(&f, 26), 0x13E8) {
    ok = false;
  }
  if !int_is(regf_cell_allocated(&f, 27), 0) {
    ok = false;
  }
  if !int_is(regf_cell_kind(&f, 27), REGF_KIND_UNKNOWN) {
    ok = false;
  }
  return assert(ok, "free/deleted cells: allocated flag 0, stale nk tag stays visible");
}

fn t19() -> TestResult {
  var d = fx();
  put_uint(&mut d, 8, 2, 4);
  let r = regf_parse(&d);
  var ok = false;
  if r.is_ok {
    let f: RegfHive = r.value;
    ok = regf_sequence_mismatch(&f);
    if regf_primary_sequence(&f) != 1 {
      ok = false;
    }
    if regf_secondary_sequence(&f) != 2 {
      ok = false;
    }
    if regf_key_count(&f) != 6 {
      ok = false;
    }
  }
  return assert(ok, "sequence mismatch is a warning state: parse succeeds, flag is set");
}

fn t20() -> TestResult {
  let d = fx();
  let short = prefix(d, 4095);
  var fails = "";
  if !err_hive_is(regf_parse(&short), msg("regf: truncated base block", 0)) {
    fails = fails + " trunc";
  }
  var v1 = fx();
  put_u8(&mut v1, 2, 0);
  if !err_hive_is(regf_parse(&v1), msg("regf: bad base block signature", 0)) {
    fails = fails + " sig";
  }
  var v2 = fx();
  put_uint(&mut v2, 20, 2, 4);
  if !err_hive_is(regf_parse(&v2), msg("regf: bad version", 20)) {
    fails = fails + " major";
  }
  var v3 = fx();
  put_uint(&mut v3, 24, 2, 4);
  if !err_hive_is(regf_parse(&v3), msg("regf: bad version", 20)) {
    fails = fails + " minor2";
  }
  var v4 = fx();
  put_uint(&mut v4, 24, 6, 4);
  if !err_hive_is(regf_parse(&v4), msg("regf: bad version", 20)) {
    fails = fails + " minor6";
  }
  var v5 = fx();
  put_uint(&mut v5, 28, 3, 4);
  if !err_hive_is(regf_parse(&v5), msg("regf: bad file type", 28)) {
    fails = fails + " type";
  }
  var v6 = fx();
  put_uint(&mut v6, 32, 2, 4);
  if !err_hive_is(regf_parse(&v6), msg("regf: bad file format", 32)) {
    fails = fails + " format";
  }
  var v7 = fx();
  put_uint(&mut v7, 40, 0, 4);
  if !err_hive_is(regf_parse(&v7), msg("regf: bad hive bins data size", 40)) {
    fails = fails + " hds0";
  }
  var v8 = fx();
  put_uint(&mut v8, 40, 22000, 4);
  if !err_hive_is(regf_parse(&v8), msg("regf: bad hive bins data size", 40)) {
    fails = fails + " hds22000";
  }
  var v9 = fx();
  put_uint(&mut v9, 40, 61440, 4);
  if !err_hive_is(regf_parse(&v9), msg("regf: bad hive bins data size", 40)) {
    fails = fails + " hds61440";
  }
  var v10 = fx();
  put_uint(&mut v10, 36, 0xFFFFFFFF, 4);
  if !err_hive_is(regf_parse(&v10), msg("regf: bad root cell offset", 36)) {
    fails = fails + " rootff";
  }
  var v11 = fx();
  put_uint(&mut v11, 36, 24576, 4);
  if !err_hive_is(regf_parse(&v11), msg("regf: bad root cell offset", 36)) {
    fails = fails + " rootoob";
  }
  if fails.len() == 0 {
    return assert(true, "malformed base block: truncation, signature, version, type, format, sizes, root");
  }
  return assert(false, "malformed base block fails:" + fails);
}

fn t21() -> TestResult {
  var v1 = fx();
  put_u8(&mut v1, 0x1000, 0);
  var ok = err_hive_is(regf_parse(&v1), msg("regf: bad hbin signature", 0x1000));
  var v2 = fx();
  put_uint(&mut v2, 0x1004, 64, 4);
  if !err_hive_is(regf_parse(&v2), msg("regf: bad hbin offset", 0x1004)) {
    ok = false;
  }
  var v3 = fx();
  put_uint(&mut v3, 0x1008, 4000, 4);
  if !err_hive_is(regf_parse(&v3), msg("regf: bad hbin size", 0x1008)) {
    ok = false;
  }
  var v4 = fx();
  put_uint(&mut v4, 0x1008, 0x100000, 4);
  if !err_hive_is(regf_parse(&v4), msg("regf: bad hbin size", 0x1008)) {
    ok = false;
  }
  return assert(ok, "malformed hbin: signature, non-monotonic offset, zero/non-4096-multiple size");
}

fn t22() -> TestResult {
  var v1 = fx();
  put_uint(&mut v1, 0x1020, 0, 4);
  var ok = err_hive_is(regf_parse(&v1), msg("regf: bad cell size", 0x1020));
  var v2 = fx();
  put_uint(&mut v2, 0x1020, -87, 4);
  if !err_hive_is(regf_parse(&v2), msg("regf: bad cell size", 0x1020)) {
    ok = false;
  }
  var v3 = fx();
  put_uint(&mut v3, 0x1020, -5000, 4);
  if !err_hive_is(regf_parse(&v3), msg("regf: bad cell size", 0x1020)) {
    ok = false;
  }
  return assert(ok, "malformed cell sizes: zero, non-multiple of 8, past the hbin end");
}

fn t23() -> TestResult {
  var v1 = fx();
  put_uint(&mut v1, 0x123E, 3, 2);
  var ok = err_hive_is(regf_parse(&v1), msg("regf: bad subkey list size", 0x1238));
  var v2 = fx();
  put_uint(&mut v2, 0x1038, 3, 4);
  if !err_hive_is(regf_parse(&v2), msg("regf: subkey count mismatch", 0x1038)) {
    ok = false;
  }
  var v3 = fx();
  put_uint(&mut v3, 0x1040, 0x2A8, 4);
  if !err_hive_is(regf_parse(&v3), msg("regf: bad subkey list", 0x12A8)) {
    ok = false;
  }
  var v4 = fx();
  put_uint(&mut v4, 0x1248, 0x3E8, 4);
  if !err_hive_is(regf_parse(&v4), msg("regf: cell not allocated", 0x13E8)) {
    ok = false;
  }
  var v5 = fx();
  put_uint(&mut v5, 0x1248, 0x2A8, 4);
  if !err_hive_is(regf_parse(&v5), msg("regf: unexpected cell kind", 0x12A8)) {
    ok = false;
  }
  return assert(ok, "subkey list errors: span, nk/list count mismatch, kind, free-cell child");
}

fn t24() -> TestResult {
  var fails = "";
  var v1 = fx();
  put_uint(&mut v1, 0x12B0, 0x80000005, 4);
  if !err_hive_is(regf_parse(&v1), msg("regf: bad inline data size", 0x12B0)) {
    fails = fails + " inline";
  }
  var v2 = fx();
  put_uint(&mut v2, 0x12D4, 0x7FFFF, 4);
  if !err_hive_is(regf_parse(&v2), msg("regf: bad cell offset", 0x12D4)) {
    fails = fails + " offset";
  }
  var v3 = fx();
  put_uint(&mut v3, 0x1334, 0x3E8, 4);
  if !err_hive_is(regf_parse(&v3), msg("regf: cell not allocated", 0x13E8)) {
    fails = fails + " free";
  }
  var v4 = fx();
  put_uint(&mut v4, 0x1330, 20, 4);
  if !err_hive_is(regf_parse(&v4), msg("regf: bad value data size", 0x1330)) {
    fails = fails + " span";
  }
  var v5 = fx();
  put_uint(&mut v5, 0x13AE, 1, 2);
  if !err_hive_is(regf_parse(&v5), msg("regf: bad big data segment count", 0x13AE)) {
    fails = fails + " dbseg";
  }
  if fails.len() == 0 {
    return assert(true, "value data errors: inline size, offset bounds, free cell, data span, db segments");
  }
  return assert(false, "value data errors fail:" + fails);
}

fn t25() -> TestResult {
  let d = fx();
  let r = regf_parse(&d);
  if !r.is_ok {
    return assert(false, "fixture must parse");
  }
  let f: RegfHive = r.value;
  var ok = err_int_is(regf_cell_offset(&f, -1), "regf: index out of range");
  if !err_int_is(regf_cell_kind(&f, 31), "regf: index out of range") {
    ok = false;
  }
  if !err_str_is(regf_key_name(&f, 99), "regf: index out of range") {
    ok = false;
  }
  if !err_str_is(regf_value_name(&f, 6), "regf: index out of range") {
    ok = false;
  }
  if !err_bytes_is(regf_value_data(&d, &f, 6), "regf: index out of range") {
    ok = false;
  }
  if !err_strs_is(regf_value_multi_str(&d, &f, 99), "regf: index out of range") {
    ok = false;
  }
  if !err_int_is(regf_value_dword(&d, &f, 6), "regf: index out of range") {
    ok = false;
  }
  if !err_int_is(regf_key_subkey(&f, 0, 5), "regf: index out of range") {
    ok = false;
  }
  if !err_int_is(regf_key_sk(&f, 0, 9), "regf: bad field selector") {
    ok = false;
  }
  return assert(ok, "accessor error strings: index out of range and bad field selector");
}

fn main() -> Int {
  io.println("=== xiom.windows conformance tests ===");
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
  if failed == 0 {
    io.println("xiom.windows: all tests passed");
  } else {
    io.println("xiom.windows: tests failed");
  }
  return failed;
}
