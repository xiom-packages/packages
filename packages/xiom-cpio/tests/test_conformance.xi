// XIOM -- xiom.cpio conformance tests (20 checks)
// Port task: prove the pure-XIOM xiom.cpio codec against the documented
// newc/odc header layouts, alignment rules and error catalog.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Covers: the pinned canonical trailers; hand-built newc/odc entries with
// pinned field bytes, offsets and data slices; 4-byte (newc) and 2-byte
// (odc) header+name and data padding; non-zero and truncated padding errors;
// multiple entries, order and trailering; junk after the trailer; missing
// trailer; bad magic; truncated header/name/data; non-hex and non-octal
// digits (with uppercase hex accepted); missing NUL and namesize mismatches;
// encode-side errors (bad format, metadata length, size overflow) with an
// untouched buffer; build argument errors; full newc/odc build -> parse ->
// rebuild byte-identical round-trips; mixed-format streams; accessor range
// behavior; data-copy bounds; trailer-name exactness; and alignment
// invariants across name/data sizes.
//
// Str equality goes through str_compare (BUG 17 discipline: `==` on Str
// values read from a Vec lowers to a pointer comparison). Hand-built
// archives are assembled byte by byte in this file, so the parser is
// exercised against bytes the test controls rather than against cpio_build.

module cpio_tests
use xiom.io; use xiom.test;
use xiom.cpio;
use xiom.string;
use xiom.string.compare;
use xiom.encoding.hex;

// --------------------------------------------------
//  Generic test helpers
// --------------------------------------------------

// Expected bytes for a hex string ("" on malformed input; the caller then
// fails on the length/byte checks).
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

fn str_eq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn err_archive_is(r: Result[CpioArchive, Str], want: Str) -> Bool {
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

fn err_unit_is(r: Result[Unit, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

// --------------------------------------------------
//  Byte helpers (independent of src/cpio.xi)
// --------------------------------------------------

fn bytes_of(s: Str) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < s.len() {
    v.push(string.byte_at(s, i));
    i = i + 1;
  }
  return v;
}

fn push_text(v: &mut Vec[UInt8], s: Str) {
  var i = 0;
  while i < s.len() {
    v.push(string.byte_at(s, i));
    i = i + 1;
  }
}

fn push_zeros(v: &mut Vec[UInt8], n: Int) {
  var i = 0;
  while i < n {
    v.push(0 as UInt8);
    i = i + 1;
  }
}

fn zeros(n: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  push_zeros(&mut v, n);
  return v;
}

fn push_hex(v: &mut Vec[UInt8], val: Int, digits: Int) {
  var div: Int = 1;
  var k = 1;
  while k < digits {
    div = div * 16;
    k = k + 1;
  }
  var n = val;
  var i = 0;
  while i < digits {
    let d: Int = (n / div) % 16;
    n = n % div;
    if d < 10 {
      v.push((48 + d) as UInt8);
    } else {
      v.push((87 + d) as UInt8);
    }
    div = div / 16;
    i = i + 1;
  }
}

fn push_octal(v: &mut Vec[UInt8], val: Int, digits: Int) {
  var div: Int = 1;
  var k = 1;
  while k < digits {
    div = div * 8;
    k = k + 1;
  }
  var n = val;
  var i = 0;
  while i < digits {
    let d: Int = (n / div) % 8;
    n = n % div;
    v.push((48 + d) as UInt8);
    div = div / 8;
    i = i + 1;
  }
}

fn slice(v: Vec[UInt8], start: Int, end: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = start;
  while i < end && i < v.len() {
    out.push(v[i]);
    i = i + 1;
  }
  return out;
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

fn concat(a: Vec[UInt8], b: Vec[UInt8]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < a.len() {
    out.push(a[i]);
    i = i + 1;
  }
  i = 0;
  while i < b.len() {
    out.push(b[i]);
    i = i + 1;
  }
  return out;
}

// Copy of `v` with byte `pos` replaced.
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

// Copy of `v` with `src` written over [pos, pos + src.len()).
fn set_range(v: Vec[UInt8], pos: Int, src: Vec[UInt8]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < v.len() {
    if i >= pos && i < pos + src.len() {
      out.push(src[i - pos]);
    } else {
      out.push(v[i]);
    }
    i = i + 1;
  }
  return out;
}

fn data_of(n: Int, seed: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < n {
    v.push(((seed + i) % 251) as UInt8);
    i = i + 1;
  }
  return v;
}

// --------------------------------------------------
//  Hand-built archives (independent of src/cpio.xi)
// --------------------------------------------------

// One complete newc entry: header + name + NUL + 4-byte alignment padding +
// data + 4-byte alignment padding. The header filesize is data.len().
fn mk_newc_entry(name: Str, ino: Int, mode: Int, uid: Int, gid: Int, nlink: Int, mtime: Int, devmajor: Int, devminor: Int, rdevmajor: Int, rdevminor: Int, check: Int, data: Vec[UInt8]) -> Vec[UInt8] {
  var h = Vec[UInt8].new();
  push_text(&mut h, "070701");
  push_hex(&mut h, ino, 8);
  push_hex(&mut h, mode, 8);
  push_hex(&mut h, uid, 8);
  push_hex(&mut h, gid, 8);
  push_hex(&mut h, nlink, 8);
  push_hex(&mut h, mtime, 8);
  push_hex(&mut h, data.len(), 8);
  push_hex(&mut h, devmajor, 8);
  push_hex(&mut h, devminor, 8);
  push_hex(&mut h, rdevmajor, 8);
  push_hex(&mut h, rdevminor, 8);
  push_hex(&mut h, name.len() + 1, 8);
  push_hex(&mut h, check, 8);
  push_text(&mut h, name);
  h.push(0 as UInt8);
  push_zeros(&mut h, (4 - ((110 + name.len() + 1) % 4)) % 4);
  var i = 0;
  while i < data.len() {
    h.push(data[i]);
    i = i + 1;
  }
  push_zeros(&mut h, (4 - (data.len() % 4)) % 4);
  return h;
}

// One complete odc entry: header + name + NUL + 2-byte alignment padding +
// data + 2-byte alignment padding. The header filesize is data.len().
fn mk_odc_entry(name: Str, dev: Int, ino: Int, mode: Int, uid: Int, gid: Int, nlink: Int, rdev: Int, mtime: Int, data: Vec[UInt8]) -> Vec[UInt8] {
  var h = Vec[UInt8].new();
  push_text(&mut h, "070707");
  push_octal(&mut h, dev, 6);
  push_octal(&mut h, ino, 6);
  push_octal(&mut h, mode, 6);
  push_octal(&mut h, uid, 6);
  push_octal(&mut h, gid, 6);
  push_octal(&mut h, nlink, 6);
  push_octal(&mut h, rdev, 6);
  push_octal(&mut h, mtime, 11);
  push_octal(&mut h, name.len() + 1, 6);
  push_octal(&mut h, data.len(), 11);
  push_text(&mut h, name);
  h.push(0 as UInt8);
  push_zeros(&mut h, (2 - ((76 + name.len() + 1) % 2)) % 2);
  var i = 0;
  while i < data.len() {
    h.push(data[i]);
    i = i + 1;
  }
  push_zeros(&mut h, (2 - (data.len() % 2)) % 2);
  return h;
}

fn newc_trailer() -> Vec[UInt8] {
  return mk_newc_entry("TRAILER!!!", 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, zeros(0));
}

fn odc_trailer() -> Vec[UInt8] {
  return mk_odc_entry("TRAILER!!!", 0, 0, 0, 0, 0, 1, 0, 0, zeros(0));
}

// 11 metadata values in CPIO_META_* order.
fn meta_of(ino: Int, mode: Int, uid: Int, gid: Int, nlink: Int, mtime: Int, devmajor: Int, devminor: Int, rdevmajor: Int, rdevminor: Int, check: Int) -> Vec[Int] {
  var m = Vec[Int].new();
  m.push(ino);
  m.push(mode);
  m.push(uid);
  m.push(gid);
  m.push(nlink);
  m.push(mtime);
  m.push(devmajor);
  m.push(devminor);
  m.push(rdevmajor);
  m.push(rdevminor);
  m.push(check);
  return m;
}

// `entries` * 11 zero metadata values (nlink 0; the codec attaches no
// semantics to the value).
fn zero_meta(entries: Int) -> Vec[Int] {
  var m = Vec[Int].new();
  var i = 0;
  while i < entries * 11 {
    m.push(0);
    i = i + 1;
  }
  return m;
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  let want = newc_trailer();
  var ok = want.len() == 124;
  let pr = cpio_parse(&want);
  if !pr.is_ok {
    return assert(false, "trailer-only newc archive must parse");
  }
  let ar: CpioArchive = pr.value;
  if cpio_count(&ar) != 0 { ok = false; }
  var names = Vec[Str].new();
  var datas = Vec[Vec[UInt8]].new();
  var metas = Vec[Int].new();
  let br = cpio_build(CPIO_FORMAT_NEWC, &names, &datas, &metas);
  if !br.is_ok {
    return assert(false, "empty newc build must succeed");
  }
  let built: Vec[UInt8] = br.value;
  if built.len() != 124 { ok = false; }
  if !bytes_equal(built, want) { ok = false; }
  let pr2 = cpio_parse(&built);
  if !pr2.is_ok {
    return assert(false, "built empty archive must parse");
  }
  let a2: CpioArchive = pr2.value;
  if cpio_count(&a2) != 0 { ok = false; }
  return assert(ok, "empty newc archive is the pinned 124-byte trailer");
}

fn t2() -> TestResult {
  var payload = Vec[UInt8].new();
  payload.push(97 as UInt8);
  payload.push(98 as UInt8);
  payload.push(99 as UInt8);
  let ent = mk_newc_entry("a.txt", 42, 33188, 1000, 1000, 1, 1700000000, 8, 1, 0, 0, 0, payload);
  var ok = ent.len() == 120;
  if !bytes_equal(slice(ent, 0, 6), bytes_of("070701")) { ok = false; }
  if !bytes_equal(slice(ent, 6, 14), bytes_of("0000002a")) { ok = false; }
  if !bytes_equal(slice(ent, 54, 62), bytes_of("00000003")) { ok = false; }
  if !bytes_equal(slice(ent, 94, 102), bytes_of("00000006")) { ok = false; }
  if !bytes_equal(slice(ent, 110, 116), hb("612e74787400")) { ok = false; }
  if (ent[119] as Int) != 0 { ok = false; }
  let stream = concat(ent, newc_trailer());
  let pr = cpio_parse(&stream);
  if !pr.is_ok {
    return assert(false, "hand-built newc entry must parse");
  }
  let ar: CpioArchive = pr.value;
  if cpio_count(&ar) != 1 { ok = false; }
  if cpio_entry_format(&ar, 0) != CPIO_FORMAT_NEWC { ok = false; }
  if !str_eq(cpio_entry_name(&ar, 0), "a.txt") { ok = false; }
  if cpio_entry_ino(&ar, 0) != 42 { ok = false; }
  if cpio_entry_mode(&ar, 0) != 33188 { ok = false; }
  if cpio_entry_uid(&ar, 0) != 1000 { ok = false; }
  if cpio_entry_gid(&ar, 0) != 1000 { ok = false; }
  if cpio_entry_nlink(&ar, 0) != 1 { ok = false; }
  if cpio_entry_mtime(&ar, 0) != 1700000000 { ok = false; }
  if cpio_entry_devmajor(&ar, 0) != 8 { ok = false; }
  if cpio_entry_devminor(&ar, 0) != 1 { ok = false; }
  if cpio_entry_rdevmajor(&ar, 0) != 0 { ok = false; }
  if cpio_entry_rdevminor(&ar, 0) != 0 { ok = false; }
  if cpio_entry_check(&ar, 0) != 0 { ok = false; }
  if cpio_entry_filesize(&ar, 0) != 3 { ok = false; }
  if cpio_entry_data_offset(&ar, 0) != 116 { ok = false; }
  if cpio_entry_next_offset(&ar, 0) != 120 { ok = false; }
  let d = cpio_entry_data(&stream, &ar, 0);
  if !d.is_ok {
    ok = false;
  } else {
    let dv: Vec[UInt8] = d.value;
    if !bytes_equal(dv, payload) { ok = false; }
  }
  if (stream[120] as Int) != 48 { ok = false; }
  return assert(ok, "newc entry: pinned bytes, fields, offsets and data");
}

fn t3() -> TestResult {
  var names = Vec[Str].new();
  names.push("bc");
  names.push("b");
  var datas = Vec[Vec[UInt8]].new();
  datas.push(data_of(5, 1));
  datas.push(zeros(0));
  let zmeta = zero_meta(2);
  let br = cpio_build(CPIO_FORMAT_NEWC, &names, &datas, &zmeta);
  if !br.is_ok {
    return assert(false, "newc build must succeed");
  }
  let built: Vec[UInt8] = br.value;
  var ok = built.len() == 360;
  let pr = cpio_parse(&built);
  if !pr.is_ok {
    return assert(false, "built alignment archive must parse");
  }
  let ar: CpioArchive = pr.value;
  if cpio_count(&ar) != 2 { ok = false; }
  if cpio_entry_data_offset(&ar, 0) != 116 { ok = false; }
  if cpio_entry_next_offset(&ar, 0) != 124 { ok = false; }
  if cpio_entry_filesize(&ar, 0) != 5 { ok = false; }
  if cpio_entry_data_offset(&ar, 1) != 236 { ok = false; }
  if cpio_entry_next_offset(&ar, 1) != 236 { ok = false; }
  if (built[113] as Int) != 0 { ok = false; }
  if (built[114] as Int) != 0 { ok = false; }
  if (built[115] as Int) != 0 { ok = false; }
  if (built[121] as Int) != 0 { ok = false; }
  if (built[122] as Int) != 0 { ok = false; }
  if (built[123] as Int) != 0 { ok = false; }
  let bad_name_pad = set_byte(built, 113, 65);
  if !err_archive_is(cpio_parse(&bad_name_pad), "cpio: alignment mismatch") { ok = false; }
  let bad_data_pad = set_byte(built, 121, 7);
  if !err_archive_is(cpio_parse(&bad_data_pad), "cpio: alignment mismatch") { ok = false; }
  let cut = prefix(built, 114);
  if !err_archive_is(cpio_parse(&cut), "cpio: alignment mismatch") { ok = false; }
  return assert(ok, "newc 4-byte padding offsets and padding validation");
}

fn t4() -> TestResult {
  var payload = Vec[UInt8].new();
  payload.push(104 as UInt8);
  payload.push(105 as UInt8);
  let ent = mk_odc_entry("x", 7, 8, 33188, 1000, 1000, 1, 0, 1234567890, payload);
  var ok = ent.len() == 80;
  if !bytes_equal(slice(ent, 0, 6), bytes_of("070707")) { ok = false; }
  if !bytes_equal(slice(ent, 6, 12), bytes_of("000007")) { ok = false; }
  if !bytes_equal(slice(ent, 12, 18), bytes_of("000010")) { ok = false; }
  if !bytes_equal(slice(ent, 18, 24), bytes_of("100644")) { ok = false; }
  if !bytes_equal(slice(ent, 59, 65), bytes_of("000002")) { ok = false; }
  if !bytes_equal(slice(ent, 65, 76), bytes_of("00000000002")) { ok = false; }
  if !bytes_equal(slice(ent, 76, 78), hb("7800")) { ok = false; }
  let stream = concat(ent, odc_trailer());
  let pr = cpio_parse(&stream);
  if !pr.is_ok {
    return assert(false, "hand-built odc entry must parse");
  }
  let ar: CpioArchive = pr.value;
  if cpio_count(&ar) != 1 { ok = false; }
  if cpio_entry_format(&ar, 0) != CPIO_FORMAT_ODC { ok = false; }
  if !str_eq(cpio_entry_name(&ar, 0), "x") { ok = false; }
  if cpio_entry_ino(&ar, 0) != 8 { ok = false; }
  if cpio_entry_mode(&ar, 0) != 33188 { ok = false; }
  if cpio_entry_uid(&ar, 0) != 1000 { ok = false; }
  if cpio_entry_gid(&ar, 0) != 1000 { ok = false; }
  if cpio_entry_nlink(&ar, 0) != 1 { ok = false; }
  if cpio_entry_mtime(&ar, 0) != 1234567890 { ok = false; }
  if cpio_entry_devmajor(&ar, 0) != 7 { ok = false; }
  if cpio_entry_devminor(&ar, 0) != -1 { ok = false; }
  if cpio_entry_rdevmajor(&ar, 0) != 0 { ok = false; }
  if cpio_entry_rdevminor(&ar, 0) != -1 { ok = false; }
  if cpio_entry_check(&ar, 0) != -1 { ok = false; }
  if cpio_entry_filesize(&ar, 0) != 2 { ok = false; }
  if cpio_entry_data_offset(&ar, 0) != 78 { ok = false; }
  if cpio_entry_next_offset(&ar, 0) != 80 { ok = false; }
  let d = cpio_entry_data(&stream, &ar, 0);
  if !d.is_ok {
    ok = false;
  } else {
    let dv: Vec[UInt8] = d.value;
    if !bytes_equal(dv, payload) { ok = false; }
  }
  // The encoder ignores odc-absent fields: rebuilding with -1 for them must
  // reproduce the hand-built bytes exactly.
  var names = Vec[Str].new();
  names.push("x");
  var datas = Vec[Vec[UInt8]].new();
  datas.push(payload);
  let m4 = meta_of(8, 33188, 1000, 1000, 1, 1234567890, 7, -1, 0, -1, -1);
  let br = cpio_build(CPIO_FORMAT_ODC, &names, &datas, &m4);
  if !br.is_ok {
    ok = false;
  } else {
    let built: Vec[UInt8] = br.value;
    if !bytes_equal(built, stream) { ok = false; }
  }
  return assert(ok, "odc entry: fields, combined dev/rdev and pinned bytes");
}

fn t5() -> TestResult {
  var names = Vec[Str].new();
  names.push("ab");
  var datas = Vec[Vec[UInt8]].new();
  datas.push(data_of(1, 2));
  let zmeta = zero_meta(1);
  let br = cpio_build(CPIO_FORMAT_ODC, &names, &datas, &zmeta);
  if !br.is_ok {
    return assert(false, "odc build must succeed");
  }
  let built: Vec[UInt8] = br.value;
  var ok = built.len() == 170;
  let pr = cpio_parse(&built);
  if !pr.is_ok {
    return assert(false, "built odc archive must parse");
  }
  let ar: CpioArchive = pr.value;
  if cpio_count(&ar) != 1 { ok = false; }
  if cpio_entry_data_offset(&ar, 0) != 80 { ok = false; }
  if cpio_entry_filesize(&ar, 0) != 1 { ok = false; }
  if cpio_entry_next_offset(&ar, 0) != 82 { ok = false; }
  if (built[79] as Int) != 0 { ok = false; }
  if (built[81] as Int) != 0 { ok = false; }
  let bad_name_pad = set_byte(built, 79, 9);
  if !err_archive_is(cpio_parse(&bad_name_pad), "cpio: alignment mismatch") { ok = false; }
  let bad_data_pad = set_byte(built, 81, 9);
  if !err_archive_is(cpio_parse(&bad_data_pad), "cpio: alignment mismatch") { ok = false; }
  let empty = odc_trailer();
  if empty.len() != 88 { ok = false; }
  var no_names = Vec[Str].new();
  var no_datas = Vec[Vec[UInt8]].new();
  var no_metas = Vec[Int].new();
  let er = cpio_build(CPIO_FORMAT_ODC, &no_names, &no_datas, &no_metas);
  if !er.is_ok {
    ok = false;
  } else {
    let eb: Vec[UInt8] = er.value;
    if !bytes_equal(eb, empty) { ok = false; }
    let epr = cpio_parse(&eb);
    if !epr.is_ok {
      ok = false;
    } else {
      let ea: CpioArchive = epr.value;
      if cpio_count(&ea) != 0 { ok = false; }
    }
  }
  return assert(ok, "odc 2-byte padding offsets and 88-byte empty archive");
}

fn t6() -> TestResult {
  var names = Vec[Str].new();
  names.push("a");
  names.push("bb");
  names.push("ccc");
  var datas = Vec[Vec[UInt8]].new();
  datas.push(zeros(0));
  datas.push(data_of(1, 5));
  datas.push(data_of(8, 6));
  let zmeta = zero_meta(3);
  let br = cpio_build(CPIO_FORMAT_NEWC, &names, &datas, &zmeta);
  if !br.is_ok {
    return assert(false, "three-entry build must succeed");
  }
  let built: Vec[UInt8] = br.value;
  let pr = cpio_parse(&built);
  if !pr.is_ok {
    return assert(false, "three-entry archive must parse");
  }
  let ar: CpioArchive = pr.value;
  var ok = cpio_count(&ar) == 3;
  if !str_eq(cpio_entry_name(&ar, 0), "a") { ok = false; }
  if !str_eq(cpio_entry_name(&ar, 1), "bb") { ok = false; }
  if !str_eq(cpio_entry_name(&ar, 2), "ccc") { ok = false; }
  if cpio_entry_filesize(&ar, 0) != 0 { ok = false; }
  if cpio_entry_filesize(&ar, 1) != 1 { ok = false; }
  if cpio_entry_filesize(&ar, 2) != 8 { ok = false; }
  let d1 = cpio_entry_data(&built, &ar, 1);
  if !d1.is_ok { ok = false; } else {
    let d1v: Vec[UInt8] = d1.value;
    if !bytes_equal(d1v, data_of(1, 5)) { ok = false; }
  }
  let d2 = cpio_entry_data(&built, &ar, 2);
  if !d2.is_ok { ok = false; } else {
    let d2v: Vec[UInt8] = d2.value;
    if !bytes_equal(d2v, data_of(8, 6)) { ok = false; }
  }
  // Bytes after the trailer are ignored.
  let junk = concat(built, hb("00ff00"));
  let jr = cpio_parse(&junk);
  if !jr.is_ok {
    ok = false;
  } else {
    let ja: CpioArchive = jr.value;
    if cpio_count(&ja) != 3 { ok = false; }
  }
  // A stream without a trailer is an error, including the empty buffer.
  let no_trailer = prefix(built, built.len() - 124);
  if !err_archive_is(cpio_parse(&no_trailer), "cpio: missing trailer") { ok = false; }
  var empty_buf = Vec[UInt8].new();
  if !err_archive_is(cpio_parse(&empty_buf), "cpio: missing trailer") { ok = false; }
  return assert(ok, "three entries in order; trailer stops parsing; missing trailer Err");
}

fn t7() -> TestResult {
  var empty_buf = Vec[UInt8].new();
  var ok = err_archive_is(cpio_parse(&empty_buf), "cpio: missing trailer");
  let short_magic = bytes_of("07080");
  if !err_archive_is(cpio_parse(&short_magic), "cpio: truncated header") { ok = false; }
  let newc_only = bytes_of("070701");
  if !err_archive_is(cpio_parse(&newc_only), "cpio: truncated header") { ok = false; }
  let odc_only = bytes_of("070707");
  if !err_archive_is(cpio_parse(&odc_only), "cpio: truncated header") { ok = false; }
  let bad = bytes_of("070702");
  if !err_archive_is(cpio_parse(&bad), "cpio: bad magic") { ok = false; }
  let ent = mk_newc_entry("m", 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, zeros(0));
  let stream = concat(ent, newc_trailer());
  let bad_first = set_byte(stream, 0, 56);
  if !err_archive_is(cpio_parse(&bad_first), "cpio: bad magic") { ok = false; }
  let bad_last = set_byte(stream, 5, 50);
  if !err_archive_is(cpio_parse(&bad_last), "cpio: bad magic") { ok = false; }
  let cut = prefix(stream, 60);
  if !err_archive_is(cpio_parse(&cut), "cpio: truncated header") { ok = false; }
  if cpio_detect_format(&bytes_of("070701")) != CPIO_FORMAT_NEWC { ok = false; }
  if cpio_detect_format(&bytes_of("070707")) != CPIO_FORMAT_ODC { ok = false; }
  if cpio_detect_format(&bytes_of("070702")) != -1 { ok = false; }
  if cpio_detect_format(&bytes_of("07070")) != -1 { ok = false; }
  if cpio_detect_format(&empty_buf) != -1 { ok = false; }
  if cpio_detect_format(&bytes_of("XXXXXX")) != -1 { ok = false; }
  return assert(ok, "magic detection and header truncation errors");
}

fn t8() -> TestResult {
  let ent = mk_newc_entry("h", 1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, zeros(0));
  let stream = concat(ent, newc_trailer());
  var ok = cpio_parse(&stream).is_ok;
  let bad_ino = set_byte(stream, 6, 103);
  if !err_archive_is(cpio_parse(&bad_ino), "cpio: non-hex digit") { ok = false; }
  let bad_check = set_byte(stream, 102, 122);
  if !err_archive_is(cpio_parse(&bad_check), "cpio: non-hex digit") { ok = false; }
  let upper = set_range(ent, 6, bytes_of("0000002A"));
  let ustream = concat(upper, newc_trailer());
  let pr = cpio_parse(&ustream);
  if !pr.is_ok {
    ok = false;
  } else {
    let ar: CpioArchive = pr.value;
    if cpio_count(&ar) != 1 { ok = false; }
    if cpio_entry_ino(&ar, 0) != 42 { ok = false; }
  }
  return assert(ok, "non-hex digits Err; uppercase hex digits parse");
}

fn t9() -> TestResult {
  let ent = mk_odc_entry("h", 1, 2, 3, 4, 5, 1, 6, 7, zeros(0));
  let stream = concat(ent, odc_trailer());
  var ok = cpio_parse(&stream).is_ok;
  let bad_ino = set_byte(stream, 12, 56);
  if !err_archive_is(cpio_parse(&bad_ino), "cpio: bad octal") { ok = false; }
  let bad_mtime = set_byte(stream, 48, 97);
  if !err_archive_is(cpio_parse(&bad_mtime), "cpio: bad octal") { ok = false; }
  let bad_namesize = set_byte(stream, 59, 120);
  if !err_archive_is(cpio_parse(&bad_namesize), "cpio: bad octal") { ok = false; }
  let bad_filesize = set_byte(stream, 65, 57);
  if !err_archive_is(cpio_parse(&bad_filesize), "cpio: bad octal") { ok = false; }
  let pr = cpio_parse(&stream);
  if !pr.is_ok {
    ok = false;
  } else {
    let ar: CpioArchive = pr.value;
    if cpio_entry_ino(&ar, 0) != 2 { ok = false; }
    if cpio_entry_mtime(&ar, 0) != 7 { ok = false; }
    if cpio_entry_filesize(&ar, 0) != 0 { ok = false; }
  }
  return assert(ok, "non-octal odc digits Err; leading zeros parse");
}

fn t10() -> TestResult {
  let ent = mk_newc_entry("a.txt", 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, zeros(0));
  let stream = concat(ent, newc_trailer());
  let no_nul = set_byte(stream, 115, 122);
  var ok = err_archive_is(cpio_parse(&no_nul), "cpio: name missing NUL");
  let trailing = set_range(stream, 94, hb("3030303030303038"));
  if !err_archive_is(cpio_parse(&trailing), "cpio: bad namesize") { ok = false; }
  let zero_size = set_range(stream, 94, hb("3030303030303030"));
  if !err_archive_is(cpio_parse(&zero_size), "cpio: bad namesize") { ok = false; }
  // An empty name (namesize 1, just the NUL) is a valid entry name.
  let empty_named = mk_newc_entry("", 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, zeros(0));
  let estream = concat(empty_named, newc_trailer());
  let pr = cpio_parse(&estream);
  if !pr.is_ok {
    ok = false;
  } else {
    let ar: CpioArchive = pr.value;
    if cpio_count(&ar) != 1 { ok = false; }
    if !str_eq(cpio_entry_name(&ar, 0), "") { ok = false; }
  }
  return assert(ok, "name NUL/namesize validation; empty name parses");
}

fn t11() -> TestResult {
  let ent = mk_newc_entry("a.txt", 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, data_of(3, 4));
  let stream = concat(ent, newc_trailer());
  let big_name = set_range(ent, 94, hb("3030303030306338"));
  var ok = err_archive_is(cpio_parse(&big_name), "cpio: truncated name");
  let cut_data = prefix(stream, 118);
  if !err_archive_is(cpio_parse(&cut_data), "cpio: truncated data") { ok = false; }
  let big_size = set_range(ent, 54, hb("3030306634323430"));
  let bstream = concat(big_size, newc_trailer());
  if !err_archive_is(cpio_parse(&bstream), "cpio: truncated data") { ok = false; }
  return assert(ok, "truncated name and data are the documented errors");
}

fn t12() -> TestResult {
  var out = Vec[UInt8].new();
  var ok = true;
  let empty = zeros(0);
  let m = meta_of(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11);
  if !err_unit_is(cpio_append(&mut out, 2, "n", &m, &empty), "cpio: bad format") { ok = false; }
  var short_m = Vec[Int].new();
  short_m.push(0);
  if !err_unit_is(cpio_append(&mut out, CPIO_FORMAT_NEWC, "n", &short_m, &empty), "cpio: metadata length mismatch") { ok = false; }
  let big = meta_of(4294967296, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0);
  if !err_unit_is(cpio_append(&mut out, CPIO_FORMAT_NEWC, "n", &big, &empty), "cpio: size overflow") { ok = false; }
  let neg = meta_of(-1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0);
  if !err_unit_is(cpio_append(&mut out, CPIO_FORMAT_NEWC, "n", &neg, &empty), "cpio: size overflow") { ok = false; }
  let odc_big = meta_of(262144, 0, 0, 0, 0, 0, 0, -1, 0, -1, -1);
  if !err_unit_is(cpio_append(&mut out, CPIO_FORMAT_ODC, "n", &odc_big, &empty), "cpio: size overflow") { ok = false; }
  let odc_time = meta_of(0, 0, 0, 0, 0, 8589934592, 0, -1, 0, -1, -1);
  if !err_unit_is(cpio_append(&mut out, CPIO_FORMAT_ODC, "n", &odc_time, &empty), "cpio: size overflow") { ok = false; }
  if !err_unit_is(cpio_append_trailer(&mut out, 7), "cpio: bad format") { ok = false; }
  if out.len() != 0 { ok = false; }
  // An odc name of 262143 bytes has namesize 262144, which does not fit the
  // 6 octal digits of the odc namesize field.
  var huge = Vec[UInt8].new();
  var i = 0;
  while i < 262143 {
    huge.push(110 as UInt8);
    i = i + 1;
  }
  let huge_name = Str::from_utf8(huge);
  if !err_unit_is(cpio_append(&mut out, CPIO_FORMAT_ODC, huge_name, &m, &empty), "cpio: size overflow") { ok = false; }
  if out.len() != 0 { ok = false; }
  let tr = cpio_append_trailer(&mut out, CPIO_FORMAT_NEWC);
  if !tr.is_ok { ok = false; }
  if out.len() != 124 { ok = false; }
  return assert(ok, "encode errors are Err and leave the buffer untouched");
}

fn t13() -> TestResult {
  var names = Vec[Str].new();
  names.push("n");
  var datas = Vec[Vec[UInt8]].new();
  datas.push(zeros(0));
  let zmeta = zero_meta(1);
  var ok = err_bytes_is(cpio_build(3, &names, &datas, &zmeta), "cpio: bad format");
  var no_datas = Vec[Vec[UInt8]].new();
  if !err_bytes_is(cpio_build(CPIO_FORMAT_NEWC, &names, &no_datas, &zmeta), "cpio: entry count mismatch") { ok = false; }
  var short_meta = Vec[Int].new();
  short_meta.push(0);
  if !err_bytes_is(cpio_build(CPIO_FORMAT_NEWC, &names, &datas, &short_meta), "cpio: metadata length mismatch") { ok = false; }
  var no_names = Vec[Str].new();
  var no_metas = Vec[Int].new();
  let er = cpio_build(CPIO_FORMAT_ODC, &no_names, &no_datas, &no_metas);
  if !er.is_ok {
    ok = false;
  } else {
    let eb: Vec[UInt8] = er.value;
    if !bytes_equal(eb, odc_trailer()) { ok = false; }
  }
  return assert(ok, "build argument validation and empty odc build");
}

fn t14() -> TestResult {
  var names = Vec[Str].new();
  names.push("bin/x");
  names.push("empty");
  names.push("big");
  var datas = Vec[Vec[UInt8]].new();
  datas.push(data_of(6, 3));
  datas.push(zeros(0));
  datas.push(data_of(17, 9));
  var metas = Vec[Int].new();
  metas.push(9); metas.push(33188); metas.push(1000); metas.push(1000);
  metas.push(1); metas.push(1700000000); metas.push(1); metas.push(2);
  metas.push(0); metas.push(0); metas.push(0);
  metas.push(10); metas.push(16384); metas.push(0); metas.push(0);
  metas.push(2); metas.push(0); metas.push(0); metas.push(0);
  metas.push(0); metas.push(0); metas.push(7);
  metas.push(4294967295); metas.push(4294967295); metas.push(4294967295);
  metas.push(4294967295); metas.push(4294967295); metas.push(4294967295);
  metas.push(4294967295); metas.push(4294967295); metas.push(4294967295);
  metas.push(4294967295); metas.push(4294967295);
  let br = cpio_build(CPIO_FORMAT_NEWC, &names, &datas, &metas);
  if !br.is_ok {
    return assert(false, "newc round-trip build must succeed");
  }
  let built: Vec[UInt8] = br.value;
  let pr = cpio_parse(&built);
  if !pr.is_ok {
    return assert(false, "newc round-trip must parse");
  }
  let ar: CpioArchive = pr.value;
  var ok = cpio_count(&ar) == 3;
  if !str_eq(cpio_entry_name(&ar, 0), "bin/x") { ok = false; }
  if !str_eq(cpio_entry_name(&ar, 1), "empty") { ok = false; }
  if !str_eq(cpio_entry_name(&ar, 2), "big") { ok = false; }
  if cpio_entry_ino(&ar, 0) != 9 { ok = false; }
  if cpio_entry_mode(&ar, 0) != 33188 { ok = false; }
  if cpio_entry_uid(&ar, 0) != 1000 { ok = false; }
  if cpio_entry_nlink(&ar, 1) != 2 { ok = false; }
  if cpio_entry_check(&ar, 1) != 7 { ok = false; }
  if cpio_entry_ino(&ar, 2) != 4294967295 { ok = false; }
  if cpio_entry_mtime(&ar, 2) != 4294967295 { ok = false; }
  if cpio_entry_devminor(&ar, 2) != 4294967295 { ok = false; }
  let d2 = cpio_entry_data(&built, &ar, 2);
  if !d2.is_ok { ok = false; } else {
    let d2v: Vec[UInt8] = d2.value;
    if !bytes_equal(d2v, data_of(17, 9)) { ok = false; }
  }
  // Rebuild from parsed accessors only.
  var names2 = Vec[Str].new();
  var datas2 = Vec[Vec[UInt8]].new();
  var metas2 = Vec[Int].new();
  var e = 0;
  while e < cpio_count(&ar) {
    names2.push(cpio_entry_name(&ar, e));
    let dd = cpio_entry_data(&built, &ar, e);
    if !dd.is_ok { ok = false; } else {
      let dv: Vec[UInt8] = dd.value;
      datas2.push(dv);
    }
    metas2.push(cpio_entry_ino(&ar, e));
    metas2.push(cpio_entry_mode(&ar, e));
    metas2.push(cpio_entry_uid(&ar, e));
    metas2.push(cpio_entry_gid(&ar, e));
    metas2.push(cpio_entry_nlink(&ar, e));
    metas2.push(cpio_entry_mtime(&ar, e));
    metas2.push(cpio_entry_devmajor(&ar, e));
    metas2.push(cpio_entry_devminor(&ar, e));
    metas2.push(cpio_entry_rdevmajor(&ar, e));
    metas2.push(cpio_entry_rdevminor(&ar, e));
    metas2.push(cpio_entry_check(&ar, e));
    e = e + 1;
  }
  let rb = cpio_build(CPIO_FORMAT_NEWC, &names2, &datas2, &metas2);
  if !rb.is_ok {
    ok = false;
  } else {
    let rebuilt: Vec[UInt8] = rb.value;
    if !bytes_equal(rebuilt, built) { ok = false; }
  }
  return assert(ok, "newc build -> parse -> rebuild is byte-identical");
}

fn t15() -> TestResult {
  var names = Vec[Str].new();
  names.push("d1");
  names.push("d22");
  var datas = Vec[Vec[UInt8]].new();
  datas.push(data_of(3, 11));
  datas.push(data_of(4, 12));
  let zmeta = zero_meta(2);
  let dr = cpio_build(CPIO_FORMAT_ODC, &names, &datas, &zmeta);
  if !dr.is_ok {
    return assert(false, "odc round-trip build must succeed");
  }
  let built: Vec[UInt8] = dr.value;
  let pr = cpio_parse(&built);
  if !pr.is_ok {
    return assert(false, "odc round-trip must parse");
  }
  let ar: CpioArchive = pr.value;
  var ok = cpio_count(&ar) == 2;
  if cpio_entry_format(&ar, 0) != CPIO_FORMAT_ODC { ok = false; }
  if !str_eq(cpio_entry_name(&ar, 0), "d1") { ok = false; }
  if !str_eq(cpio_entry_name(&ar, 1), "d22") { ok = false; }
  if cpio_entry_filesize(&ar, 0) != 3 { ok = false; }
  if cpio_entry_filesize(&ar, 1) != 4 { ok = false; }
  if cpio_entry_devminor(&ar, 0) != -1 { ok = false; }
  if cpio_entry_rdevminor(&ar, 0) != -1 { ok = false; }
  if cpio_entry_check(&ar, 0) != -1 { ok = false; }
  let d0 = cpio_entry_data(&built, &ar, 0);
  if !d0.is_ok { ok = false; } else {
    let d0v: Vec[UInt8] = d0.value;
    if !bytes_equal(d0v, data_of(3, 11)) { ok = false; }
  }
  let d1 = cpio_entry_data(&built, &ar, 1);
  if !d1.is_ok { ok = false; } else {
    let d1v: Vec[UInt8] = d1.value;
    if !bytes_equal(d1v, data_of(4, 12)) { ok = false; }
  }
  var names2 = Vec[Str].new();
  var datas2 = Vec[Vec[UInt8]].new();
  var metas2 = Vec[Int].new();
  var e = 0;
  while e < cpio_count(&ar) {
    names2.push(cpio_entry_name(&ar, e));
    let dd = cpio_entry_data(&built, &ar, e);
    if !dd.is_ok { ok = false; } else {
      let dv: Vec[UInt8] = dd.value;
      datas2.push(dv);
    }
    metas2.push(cpio_entry_ino(&ar, e));
    metas2.push(cpio_entry_mode(&ar, e));
    metas2.push(cpio_entry_uid(&ar, e));
    metas2.push(cpio_entry_gid(&ar, e));
    metas2.push(cpio_entry_nlink(&ar, e));
    metas2.push(cpio_entry_mtime(&ar, e));
    metas2.push(cpio_entry_devmajor(&ar, e));
    metas2.push(cpio_entry_devminor(&ar, e));
    metas2.push(cpio_entry_rdevmajor(&ar, e));
    metas2.push(cpio_entry_rdevminor(&ar, e));
    metas2.push(cpio_entry_check(&ar, e));
    e = e + 1;
  }
  let rb = cpio_build(CPIO_FORMAT_ODC, &names2, &datas2, &metas2);
  if !rb.is_ok {
    ok = false;
  } else {
    let rebuilt: Vec[UInt8] = rb.value;
    if !bytes_equal(rebuilt, built) { ok = false; }
  }
  return assert(ok, "odc build -> parse -> rebuild is byte-identical");
}

fn t16() -> TestResult {
  var a = Vec[UInt8].new();
  a.push(97 as UInt8);
  a.push(97 as UInt8);
  var b = Vec[UInt8].new();
  b.push(98 as UInt8);
  b.push(98 as UInt8);
  let e0 = mk_newc_entry("n", 1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, a);
  let e1 = mk_odc_entry("o", 0, 2, 0, 0, 0, 1, 0, 0, b);
  let stream = concat(concat(e0, e1), newc_trailer());
  let pr = cpio_parse(&stream);
  if !pr.is_ok {
    return assert(false, "mixed-format stream must parse");
  }
  let ar: CpioArchive = pr.value;
  var ok = cpio_count(&ar) == 2;
  if cpio_entry_format(&ar, 0) != CPIO_FORMAT_NEWC { ok = false; }
  if cpio_entry_format(&ar, 1) != CPIO_FORMAT_ODC { ok = false; }
  if !str_eq(cpio_entry_name(&ar, 0), "n") { ok = false; }
  if !str_eq(cpio_entry_name(&ar, 1), "o") { ok = false; }
  if cpio_entry_data_offset(&ar, 0) != 112 { ok = false; }
  if cpio_entry_next_offset(&ar, 0) != 116 { ok = false; }
  if cpio_entry_data_offset(&ar, 1) != 194 { ok = false; }
  if cpio_entry_next_offset(&ar, 1) != 196 { ok = false; }
  let d0 = cpio_entry_data(&stream, &ar, 0);
  if !d0.is_ok { ok = false; } else {
    let d0v: Vec[UInt8] = d0.value;
    if !bytes_equal(d0v, a) { ok = false; }
  }
  let d1 = cpio_entry_data(&stream, &ar, 1);
  if !d1.is_ok { ok = false; } else {
    let d1v: Vec[UInt8] = d1.value;
    if !bytes_equal(d1v, b) { ok = false; }
  }
  return assert(ok, "one stream may mix newc and odc entries");
}

fn t17() -> TestResult {
  let ent = mk_newc_entry("r", 5, 6, 7, 8, 1, 9, 10, 11, 12, 13, 14, data_of(2, 15));
  let stream = concat(ent, newc_trailer());
  let pr = cpio_parse(&stream);
  if !pr.is_ok {
    return assert(false, "accessor archive must parse");
  }
  let ar: CpioArchive = pr.value;
  var ok = cpio_count(&ar) == 1;
  if !str_eq(cpio_entry_name(&ar, -1), "") { ok = false; }
  if !str_eq(cpio_entry_name(&ar, 1), "") { ok = false; }
  if cpio_entry_format(&ar, -1) != -1 { ok = false; }
  if cpio_entry_format(&ar, 1) != -1 { ok = false; }
  if cpio_entry_field(&ar, 0, -1) != -1 { ok = false; }
  if cpio_entry_field(&ar, 0, 11) != -1 { ok = false; }
  if cpio_entry_field(&ar, 1, 0) != -1 { ok = false; }
  if cpio_entry_field(&ar, -1, 0) != -1 { ok = false; }
  let want_meta = meta_of(5, 6, 7, 8, 1, 9, 10, 11, 12, 13, 14);
  var k = 0;
  while k < 11 {
    let want_k: Int = want_meta[k];
    if cpio_entry_field(&ar, 0, k) != want_k { ok = false; }
    k = k + 1;
  }
  if cpio_entry_ino(&ar, 1) != -1 { ok = false; }
  if cpio_entry_mode(&ar, 1) != -1 { ok = false; }
  if cpio_entry_filesize(&ar, -1) != -1 { ok = false; }
  if cpio_entry_filesize(&ar, 1) != -1 { ok = false; }
  if cpio_entry_data_offset(&ar, -1) != -1 { ok = false; }
  if cpio_entry_data_offset(&ar, 1) != -1 { ok = false; }
  if cpio_entry_next_offset(&ar, -1) != -1 { ok = false; }
  if cpio_entry_next_offset(&ar, 1) != -1 { ok = false; }
  if !err_bytes_is(cpio_entry_data(&stream, &ar, -1), "cpio: entry out of range") { ok = false; }
  if !err_bytes_is(cpio_entry_data(&stream, &ar, 1), "cpio: entry out of range") { ok = false; }
  return assert(ok, "accessors report -1 / \"\" / Err out of range");
}

fn t18() -> TestResult {
  let ent = mk_newc_entry("z", 1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, data_of(5, 16));
  let stream = concat(ent, newc_trailer());
  let pr = cpio_parse(&stream);
  if !pr.is_ok {
    return assert(false, "data archive must parse");
  }
  let ar: CpioArchive = pr.value;
  var ok = true;
  let full = cpio_entry_data(&stream, &ar, 0);
  if !full.is_ok { ok = false; } else {
    let fv: Vec[UInt8] = full.value;
    if !bytes_equal(fv, data_of(5, 16)) { ok = false; }
  }
  let cut = prefix(stream, 116);
  if !err_bytes_is(cpio_entry_data(&cut, &ar, 0), "cpio: truncated data") { ok = false; }
  let zero_ent = mk_newc_entry("q", 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, zeros(0));
  let zstream = concat(zero_ent, newc_trailer());
  let zr = cpio_parse(&zstream);
  if !zr.is_ok {
    ok = false;
  } else {
    let za: CpioArchive = zr.value;
    let zd = cpio_entry_data(&zstream, &za, 0);
    if !zd.is_ok { ok = false; } else {
      let zv: Vec[UInt8] = zd.value;
      if zv.len() != 0 { ok = false; }
    }
  }
  return assert(ok, "cpio_entry_data slices exactly and bounds-checks");
}

fn t19() -> TestResult {
  let near = mk_newc_entry("TRAILER!!", 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, zeros(0));
  let far = mk_newc_entry("TRAILER!!!!", 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, zeros(0));
  let near_stream = concat(near, newc_trailer());
  let far_stream = concat(far, newc_trailer());
  var ok = true;
  let nr = cpio_parse(&near_stream);
  if !nr.is_ok {
    ok = false;
  } else {
    let na: CpioArchive = nr.value;
    if cpio_count(&na) != 1 { ok = false; }
    if !str_eq(cpio_entry_name(&na, 0), "TRAILER!!") { ok = false; }
  }
  let fr = cpio_parse(&far_stream);
  if !fr.is_ok {
    ok = false;
  } else {
    let fa: CpioArchive = fr.value;
    if cpio_count(&fa) != 1 { ok = false; }
    if !str_eq(cpio_entry_name(&fa, 0), "TRAILER!!!!") { ok = false; }
  }
  // Parsing stops at the trailer, so a trailer whose own padding is cut off
  // still terminates the archive cleanly.
  let whole = newc_trailer();
  let cut_trailer = prefix(whole, 121);
  let cr = cpio_parse(&cut_trailer);
  if !cr.is_ok {
    ok = false;
  } else {
    let ca: CpioArchive = cr.value;
    if cpio_count(&ca) != 0 { ok = false; }
  }
  var tr_out = Vec[UInt8].new();
  let trn = cpio_append_trailer(&mut tr_out, CPIO_FORMAT_NEWC);
  if !trn.is_ok { ok = false; }
  if tr_out.len() != 124 { ok = false; }
  var tr_out2 = Vec[UInt8].new();
  let tro = cpio_append_trailer(&mut tr_out2, CPIO_FORMAT_ODC);
  if !tro.is_ok { ok = false; }
  if tr_out2.len() != 88 { ok = false; }
  return assert(ok, "only the exact TRAILER!!! name terminates an archive");
}

fn t20() -> TestResult {
  var names = Vec[Str].new();
  names.push("n1");
  names.push("n22");
  names.push("n333");
  names.push("n4444");
  var ok = true;
  var dsize = 0;
  while dsize < 6 {
    var datas = Vec[Vec[UInt8]].new();
    datas.push(data_of(dsize, 20));
    datas.push(data_of(dsize, 21));
    datas.push(data_of(dsize, 22));
    datas.push(data_of(dsize, 23));
    let zmeta = zero_meta(4);
    let nr = cpio_build(CPIO_FORMAT_NEWC, &names, &datas, &zmeta);
    let orr = cpio_build(CPIO_FORMAT_ODC, &names, &datas, &zmeta);
    if !nr.is_ok || !orr.is_ok {
      ok = false;
    } else {
      let nb: Vec[UInt8] = nr.value;
      let ob: Vec[UInt8] = orr.value;
      let npr = cpio_parse(&nb);
      let opr = cpio_parse(&ob);
      if !npr.is_ok || !opr.is_ok {
        ok = false;
      } else {
        let na: CpioArchive = npr.value;
        let oa: CpioArchive = opr.value;
        if cpio_count(&na) != 4 { ok = false; }
        if cpio_count(&oa) != 4 { ok = false; }
        var e = 0;
        while e < 4 {
          let noff: Int = cpio_entry_data_offset(&na, e);
          let nnxt: Int = cpio_entry_next_offset(&na, e);
          let nsz: Int = cpio_entry_filesize(&na, e);
          if noff % 4 != 0 { ok = false; }
          if nnxt % 4 != 0 { ok = false; }
          if nnxt < noff + nsz { ok = false; }
          if nnxt - (noff + nsz) > 3 { ok = false; }
          let ooff: Int = cpio_entry_data_offset(&oa, e);
          let onxt: Int = cpio_entry_next_offset(&oa, e);
          let osz: Int = cpio_entry_filesize(&oa, e);
          if ooff % 2 != 0 { ok = false; }
          if onxt % 2 != 0 { ok = false; }
          if onxt < ooff + osz { ok = false; }
          if onxt - (ooff + osz) > 1 { ok = false; }
          let nd = cpio_entry_data(&nb, &na, e);
          if !nd.is_ok { ok = false; } else {
            let ndv: Vec[UInt8] = nd.value;
            if !bytes_equal(ndv, data_of(dsize, 20 + e)) { ok = false; }
          }
          let od = cpio_entry_data(&ob, &oa, e);
          if !od.is_ok { ok = false; } else {
            let odv: Vec[UInt8] = od.value;
            if !bytes_equal(odv, data_of(dsize, 20 + e)) { ok = false; }
          }
          e = e + 1;
        }
      }
    }
    dsize = dsize + 1;
  }
  return assert(ok, "alignment invariants hold across name and data sizes");
}

fn main() -> Int {
  io.println("=== xiom.cpio conformance tests ===");
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
    io.println("xiom.cpio: all tests passed");
  } else {
    io.println("xiom.cpio: tests failed");
  }
  return failed;
}
