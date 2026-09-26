// XIOM -- xiom.cab conformance tests (17 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Port task: prove the pure-XIOM xiom.cab header/directory codec against the
// [MS-CAB] CFHEADER/CFFOLDER/CFFILE layout: the exact pinned canonical
// 88-byte build, version 1.1/1.3/2.0 setID handling, header and directory
// validation (signature, reserved fields, cbCabinet, optional reserve area,
// prev/next strings, folder/file directory extents, coffFiles), the name
// policy (printable ASCII, UTF attribute gated on version 1.3), folder data
// span bounds, raw typeCompress pass-through with the known-code predicate,
// the packed DOS date/time decoded form, accessor sentinels, a two-folder
// fixture and build validation. Fixtures are assembled byte by byte in this
// file (little-endian helpers below) so cab_parse is exercised against bytes
// the test controls, not only against cab_build.
//
// Str equality goes through str_compare (BUG 17 discipline: `==` on Str
// values read from a Vec lowers to a pointer comparison).

module cab_tests
use xiom.io; use xiom.test;
use xiom.cab;
use xiom.string;
use xiom.string.compare;
use xiom.encoding.hex;

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

fn name_is(a: &CabArchive, i: Int, want: Str) -> Bool {
  return str_eq(cab_file_name(a, i), want);
}

fn err_archive_is(r: Result[CabArchive, Str], want: Str) -> Bool {
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

// --------------------------------------------------
//  Byte helpers (independent of src/cab.xi)
// --------------------------------------------------

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

fn push_le16(v: &mut Vec[UInt8], val: Int) {
  v.push((val % 256) as UInt8);
  v.push(((val / 256) % 256) as UInt8);
}

fn push_le32(v: &mut Vec[UInt8], val: Int) {
  v.push((val % 256) as UInt8);
  v.push(((val / 256) % 256) as UInt8);
  v.push(((val / 65536) % 256) as UInt8);
  v.push(((val / 16777216) % 256) as UInt8);
}

fn zeros(n: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  push_zeros(&mut v, n);
  return v;
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

fn prefix(v: Vec[UInt8], n: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < n && i < v.len() {
    out.push(v[i]);
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

fn set_u16(v: Vec[UInt8], pos: Int, val: Int) -> Vec[UInt8] {
  var s = Vec[UInt8].new();
  push_le16(&mut s, val);
  return set_range(v, pos, s);
}

fn set_u32(v: Vec[UInt8], pos: Int, val: Int) -> Vec[UInt8] {
  var s = Vec[UInt8].new();
  push_le32(&mut s, val);
  return set_range(v, pos, s);
}

// --------------------------------------------------
//  Fixture builders (independent of src/cab.xi)
// --------------------------------------------------

// CFHEADER through iCabinet: `cab_size` is cbCabinet, `coff` is coffFiles.
// The optional setID/iCabinet pair is written only when the documented
// "1.3 or greater" rule holds.
fn hdr(vmin: Int, vmaj: Int, nfolders: Int, nfiles: Int, flags: Int, cab_size: Int, coff: Int, setid: Int, icab: Int) -> Vec[UInt8] {
  var h = Vec[UInt8].new();
  push_text(&mut h, "MSCF");
  push_le32(&mut h, 0);
  push_le32(&mut h, cab_size);
  push_le32(&mut h, 0);
  push_le32(&mut h, coff);
  push_le32(&mut h, 0);
  h.push(vmin as UInt8);
  h.push(vmaj as UInt8);
  push_le16(&mut h, nfolders);
  push_le16(&mut h, nfiles);
  push_le16(&mut h, flags);
  if cab_version_has_setid(vmaj, vmin) {
    push_le16(&mut h, setid);
    push_le16(&mut h, icab);
  }
  return h;
}

// CFFOLDER entry without reserve bytes.
fn fent(off: Int, count: Int, comp: Int) -> Vec[UInt8] {
  var f = Vec[UInt8].new();
  push_le32(&mut f, off);
  push_le16(&mut f, count);
  push_le16(&mut f, comp);
  return f;
}

// CFFOLDER entry with `res` appended as its per-folder reserve bytes.
fn fent_res(off: Int, count: Int, comp: Int, res: Vec[UInt8]) -> Vec[UInt8] {
  return concat(fent(off, count, comp), res);
}

// CFFILE entry over raw name bytes (the NUL terminator is appended).
fn file_ent_raw(size: Int, uoff: Int, ifolder: Int, date: Int, time: Int, attribs: Int, name: Vec[UInt8]) -> Vec[UInt8] {
  var f = Vec[UInt8].new();
  push_le32(&mut f, size);
  push_le32(&mut f, uoff);
  push_le16(&mut f, ifolder);
  push_le16(&mut f, date);
  push_le16(&mut f, time);
  push_le16(&mut f, attribs);
  var i = 0;
  while i < name.len() {
    f.push(name[i]);
    i = i + 1;
  }
  f.push(0 as UInt8);
  return f;
}

// CFFILE entry over a printable Str name.
fn file_ent(size: Int, uoff: Int, ifolder: Int, date: Int, time: Int, attribs: Int, name: Str) -> Vec[UInt8] {
  var nb = Vec[UInt8].new();
  push_text(&mut nb, name);
  return file_ent_raw(size, uoff, ifolder, date, time, attribs, nb);
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  var names = Vec[Str].new();
  names.push("a.txt");
  names.push("b.bin");
  var sizes = Vec[Int].new();
  sizes.push(3);
  sizes.push(5);
  let r = cab_build(&names, &sizes);
  if !r.is_ok { return assert(false, "cab_build must succeed"); }
  let out = r.value;
  let want = hb("4d5343460000000058000000000000002c00000000000000030101000200000000000000580000000000000003000000000000000000000000002000612e7478740005000000030000000000000000002000622e62696e00");
  var ok = bytes_equal(out, want);
  let pr = cab_parse(&out);
  if !pr.is_ok {
    ok = false;
  } else {
    let a = pr.value;
    if cab_cabinet_size(&a) != 88 { ok = false; }
    if cab_version_major(&a) != 1 { ok = false; }
    if cab_version_minor(&a) != 3 { ok = false; }
    if cab_flags(&a) != 0 { ok = false; }
    if cab_set_id(&a) != 0 { ok = false; }
    if cab_i_cabinet(&a) != 0 { ok = false; }
    if cab_folder_count(&a) != 1 { ok = false; }
    if cab_file_count(&a) != 2 { ok = false; }
    if !name_is(&a, 0, "a.txt") { ok = false; }
    if !name_is(&a, 1, "b.bin") { ok = false; }
    if cab_file_size(&a, 0) != 3 { ok = false; }
    if cab_file_size(&a, 1) != 5 { ok = false; }
    if cab_file_offset(&a, 0) != 0 { ok = false; }
    if cab_file_offset(&a, 1) != 3 { ok = false; }
    if cab_file_folder(&a, 0) != 0 { ok = false; }
    if cab_file_attribs(&a, 0) != 32 { ok = false; }
    if cab_file_utf(&a, 0) { ok = false; }
    if cab_folder_start(&a, 0) != 88 { ok = false; }
    if cab_folder_data_count(&a, 0) != 0 { ok = false; }
    if cab_folder_compression(&a, 0) != 0 { ok = false; }
    if cab_reserved_header_len(&a) != 0 { ok = false; }
    if cab_reserved_folder_len(&a) != 0 { ok = false; }
    if cab_reserved_data_len(&a) != 0 { ok = false; }
    if cab_reserved_header_offset(&a) != 36 { ok = false; }
  }
  return assert(ok, "cab_build emits the pinned canonical 88-byte directory");
}

fn t2() -> TestResult {
  var ok = cab_version_has_setid(1, 3);
  if !cab_version_has_setid(2, 0) { ok = false; }
  if cab_version_has_setid(1, 2) { ok = false; }
  if cab_version_has_setid(0, 4) { ok = false; }
  let h11 = hdr(1, 1, 0, 0, 0, 32, 0, 0, 0);
  let p11 = cab_parse(&h11);
  if !p11.is_ok {
    ok = false;
  } else {
    let a11 = p11.value;
    if cab_version_major(&a11) != 1 { ok = false; }
    if cab_version_minor(&a11) != 1 { ok = false; }
    if cab_set_id(&a11) != -1 { ok = false; }
    if cab_i_cabinet(&a11) != -1 { ok = false; }
    if cab_folder_count(&a11) != 0 { ok = false; }
    if cab_file_count(&a11) != 0 { ok = false; }
  }
  let h13 = concat(hdr(3, 1, 1, 0, 0, 44, 44, 4660, 7), fent(44, 0, 0));
  let p13 = cab_parse(&h13);
  if !p13.is_ok {
    ok = false;
  } else {
    let a13 = p13.value;
    if cab_version_major(&a13) != 1 { ok = false; }
    if cab_version_minor(&a13) != 3 { ok = false; }
    if cab_set_id(&a13) != 4660 { ok = false; }
    if cab_i_cabinet(&a13) != 7 { ok = false; }
    if cab_folder_count(&a13) != 1 { ok = false; }
  }
  let h20 = concat(hdr(0, 2, 1, 0, 0, 44, 44, 255, 9), fent(44, 0, 0));
  let p20 = cab_parse(&h20);
  if !p20.is_ok {
    ok = false;
  } else {
    let a20 = p20.value;
    if cab_version_major(&a20) != 2 { ok = false; }
    if cab_version_minor(&a20) != 0 { ok = false; }
    if cab_set_id(&a20) != 255 { ok = false; }
    if cab_i_cabinet(&a20) != 9 { ok = false; }
  }
  return assert(ok, "version 1.1/1.3/2.0 setID presence and values");
}

fn t3() -> TestResult {
  let empty = Vec[UInt8].new();
  let three = hb("4d5343");
  let sig_only = hb("4d534346");
  let short = hb("4d5343460000000000000000");
  var ok = err_archive_is(cab_parse(&empty), "cab: bad signature");
  if !err_archive_is(cab_parse(&three), "cab: bad signature") { ok = false; }
  if !err_archive_is(cab_parse(&sig_only), "cab: truncated header") { ok = false; }
  if !err_archive_is(cab_parse(&short), "cab: truncated header") { ok = false; }
  var wrong = hb("4d5343ff");
  if !err_archive_is(cab_parse(&wrong), "cab: bad signature") { ok = false; }
  return assert(ok, "signature and short-buffer errors");
}

fn t4() -> TestResult {
  let base = concat(hdr(3, 1, 1, 0, 0, 44, 44, 0, 0), fent(44, 0, 0));
  if !cab_parse(&base).is_ok {
    return assert(false, "base fixture must parse");
  }
  let bad1 = set_u32(base, 4, 1);
  let bad2 = set_u32(base, 12, 1);
  let bad3 = set_u32(base, 20, 1);
  var ok = err_archive_is(cab_parse(&bad1), "cab: reserved field set");
  if !err_archive_is(cab_parse(&bad2), "cab: reserved field set") { ok = false; }
  if !err_archive_is(cab_parse(&bad3), "cab: reserved field set") { ok = false; }
  return assert(ok, "reserved1/reserved2/reserved3 must be zero");
}

fn t5() -> TestResult {
  var names = Vec[Str].new();
  names.push("a.txt");
  names.push("b.bin");
  var sizes = Vec[Int].new();
  sizes.push(3);
  sizes.push(5);
  let r = cab_build(&names, &sizes);
  if !r.is_ok { return assert(false, "cab_build must succeed"); }
  let base = r.value;
  let big = set_u32(base, 8, 89);
  let tiny = set_u32(base, 8, 31);
  let junk = concat(base, hb("00ff7f"));
  var ok = err_archive_is(cab_parse(&big), "cab: truncated cabinet");
  if !err_archive_is(cab_parse(&tiny), "cab: bad cabinet size") { ok = false; }
  let pj = cab_parse(&junk);
  if !pj.is_ok {
    ok = false;
  } else {
    let aj = pj.value;
    if cab_cabinet_size(&aj) != 88 { ok = false; }
    if cab_file_count(&aj) != 2 { ok = false; }
  }
  return assert(ok, "cbCabinet bounds and trailing bytes beyond it");
}

fn t6() -> TestResult {
  var fix = hdr(3, 1, 2, 1, 1, 82, 64, 0, 0);
  // Reserve descriptor: cbCFHeader 4, cbCFFolder 2, cbCFData 3, abReserve.
  push_le16(&mut fix, 4);
  fix.push(2 as UInt8);
  fix.push(3 as UInt8);
  fix.push(170 as UInt8);
  fix.push(187 as UInt8);
  fix.push(204 as UInt8);
  fix.push(221 as UInt8);
  var res0 = Vec[UInt8].new();
  res0.push(225 as UInt8);
  res0.push(226 as UInt8);
  var res1 = Vec[UInt8].new();
  res1.push(241 as UInt8);
  res1.push(242 as UInt8);
  fix = concat(fix, fent_res(82, 0, 0, res0));
  fix = concat(fix, fent_res(82, 0, 1, res1));
  fix = concat(fix, file_ent(0, 0, 0, 0, 0, 0, "x"));
  var ok = fix.len() == 82;
  let pr = cab_parse(&fix);
  if !pr.is_ok {
    ok = false;
  } else {
    let a = pr.value;
    if cab_flags(&a) != 1 { ok = false; }
    if cab_reserved_header_len(&a) != 4 { ok = false; }
    if cab_reserved_folder_len(&a) != 2 { ok = false; }
    if cab_reserved_data_len(&a) != 3 { ok = false; }
    if cab_reserved_header_offset(&a) != 40 { ok = false; }
    if cab_folder_count(&a) != 2 { ok = false; }
    if cab_folder_reserve_offset(&a, 0) != 52 { ok = false; }
    if cab_folder_reserve_offset(&a, 1) != 62 { ok = false; }
    if cab_folder_compression(&a, 0) != 0 { ok = false; }
    if cab_folder_compression(&a, 1) != 1 { ok = false; }
    if cab_file_count(&a) != 1 { ok = false; }
    if !name_is(&a, 0, "x") { ok = false; }
  }
  return assert(ok, "reserve descriptor, header span and per-folder spans");
}

fn t7() -> TestResult {
  var fix = hdr(3, 1, 1, 1, 12, 86, 68, 0, 0);
  push_text(&mut fix, "p.cab");
  fix.push(0 as UInt8);
  push_text(&mut fix, "pdisk");
  fix.push(0 as UInt8);
  push_text(&mut fix, "n.cab");
  fix.push(0 as UInt8);
  push_text(&mut fix, "ndisk");
  fix.push(0 as UInt8);
  fix = concat(fix, fent(86, 0, 0));
  fix = concat(fix, file_ent(0, 0, 0, 0, 0, 0, "f"));
  var ok = fix.len() == 86;
  let pr = cab_parse(&fix);
  if !pr.is_ok {
    ok = false;
  } else {
    let a = pr.value;
    if cab_flags(&a) != 12 { ok = false; }
    if cab_folder_count(&a) != 1 { ok = false; }
    if cab_file_count(&a) != 1 { ok = false; }
    if !name_is(&a, 0, "f") { ok = false; }
    if cab_folder_reserve_offset(&a, 0) != 68 { ok = false; }
  }
  let cut = set_u32(prefix(fix, 40), 8, 40);
  if !err_archive_is(cab_parse(&cut), "cab: truncated string") { ok = false; }
  return assert(ok, "prev/next strings are skipped; a cut string is Err");
}

fn t8() -> TestResult {
  var names = Vec[Str].new();
  names.push("ab");
  var sizes = Vec[Int].new();
  sizes.push(0);
  let r = cab_build(&names, &sizes);
  if !r.is_ok { return assert(false, "cab_build must succeed"); }
  let base = r.value;
  let p0 = cab_parse(&base);
  var ok = p0.is_ok;

  if ok {
    let a0 = p0.value;
    if !name_is(&a0, 0, "ab") { ok = false; }
    if cab_file_utf(&a0, 0) { ok = false; }
  }
  var bad = set_byte(base, 60, 7);
  if !err_archive_is(cab_parse(&bad), "cab: bad name") { ok = false; }
  bad = set_byte(base, 60, 127);
  if !err_archive_is(cab_parse(&bad), "cab: bad name") { ok = false; }
  bad = set_byte(base, 60, 0);
  if !err_archive_is(cab_parse(&bad), "cab: bad name") { ok = false; }
  bad = set_byte(base, 60, 233);
  if !err_archive_is(cab_parse(&bad), "cab: bad name") { ok = false; }
  var utf = set_byte(base, 58, 128);
  utf = set_byte(utf, 60, 233);
  let pu = cab_parse(&utf);
  if !pu.is_ok {
    ok = false;
  } else {
    let au = pu.value;
    if !cab_file_utf(&au, 0) { ok = false; }
    if cab_file_attribs(&au, 0) != 128 { ok = false; }
    if !name_is(&au, 0, Str::from_utf8(hb("e962"))) { ok = false; }
  }
  let old = concat(hdr(1, 1, 1, 1, 0, 59, 40, 0, 0), fent(59, 0, 0));
  let oldfix = concat(old, file_ent_raw(0, 0, 0, 0, 0, 128, hb("e962")));
  if !err_archive_is(cab_parse(&oldfix), "cab: bad name") { ok = false; }
  var cutname = set_u32(base, 8, 62);
  cutname = set_u32(cutname, 36, 0);
  if !err_archive_is(cab_parse(&cutname), "cab: truncated name") { ok = false; }
  return assert(ok, "printable policy, UTF gating on 1.3, NUL termination");
}

fn t9() -> TestResult {
  var names = Vec[Str].new();
  names.push("ab");
  var sizes = Vec[Int].new();
  sizes.push(0);
  let r = cab_build(&names, &sizes);
  if !r.is_ok { return assert(false, "cab_build must succeed"); }
  let base = r.value;
  let bad1 = set_u16(base, 52, 1);
  let bad2 = set_u16(base, 52, 65535);
  var ok = err_archive_is(cab_parse(&bad1), "cab: bad folder index");
  if !err_archive_is(cab_parse(&bad2), "cab: bad folder index") { ok = false; }
  if !cab_parse(&base).is_ok { ok = false; }
  return assert(ok, "iFolder must be below cFolders");
}

fn t10() -> TestResult {
  var names = Vec[Str].new();
  names.push("a.txt");
  names.push("b.bin");
  var sizes = Vec[Int].new();
  sizes.push(3);
  sizes.push(5);
  let r = cab_build(&names, &sizes);
  if !r.is_ok { return assert(false, "cab_build must succeed"); }
  let base = r.value;
  let past = set_u32(base, 36, 89);
  let count = set_u16(set_u32(base, 36, 88), 40, 1);
  let fits = set_u16(set_u32(base, 36, 80), 40, 1);
  var ok = err_archive_is(cab_parse(&past), "cab: folder data out of range");
  if !err_archive_is(cab_parse(&count), "cab: folder data out of range") { ok = false; }
  let pf = cab_parse(&fits);
  if !pf.is_ok {
    ok = false;
  } else {
    let af = pf.value;
    if cab_folder_start(&af, 0) != 80 { ok = false; }
    if cab_folder_data_count(&af, 0) != 1 { ok = false; }
  }
  return assert(ok, "folder coffCabStart/cCFData bounded by cbCabinet");
}

fn t11() -> TestResult {
  let fix = concat(hdr(3, 1, 2, 0, 0, 52, 52, 0, 0), concat(fent(52, 0, 0), fent(52, 0, 259)));
  let pr = cab_parse(&fix);
  var ok = pr.is_ok;
  if !ok {
    return assert(false, "compression fixture must parse");
  }
  let a = pr.value;
  if cab_folder_compression(&a, 0) != 0 { ok = false; }
  if cab_folder_compression(&a, 1) != 259 { ok = false; }
  if cab_compression_code(259) != 3 { ok = false; }
  if !cab_compression_known(259) { ok = false; }
  if cab_compression_code(0) != 0 { ok = false; }
  if cab_compression_code(1) != 1 { ok = false; }
  if cab_compression_code(2) != 2 { ok = false; }
  if !cab_compression_known(0) { ok = false; }
  if !cab_compression_known(1) { ok = false; }
  if !cab_compression_known(2) { ok = false; }
  if !cab_compression_known(3) { ok = false; }
  if !cab_compression_known(16) { ok = false; }
  if cab_compression_known(15) { ok = false; }
  if cab_compression_known(-1) { ok = false; }
  if cab_compression_code(-5) != -1 { ok = false; }
  let unknown = set_u16(fix, 50, 15);
  let pu = cab_parse(&unknown);
  if !pu.is_ok {
    ok = false;
  } else {
    let au = pu.value;
    if cab_folder_compression(&au, 1) != 15 { ok = false; }
    if cab_compression_code(cab_folder_compression(&au, 1)) != 15 { ok = false; }
    if cab_compression_known(cab_folder_compression(&au, 1)) { ok = false; }
  }
  return assert(ok, "raw typeCompress pass-through and known-code predicate");
}

fn t12() -> TestResult {
  let fix = concat(concat(hdr(3, 1, 1, 1, 0, 62, 44, 0, 0), fent(62, 0, 0)), file_ent(0, 0, 0, 23866, 25692, 32, "t"));
  let pr = cab_parse(&fix);
  if !pr.is_ok { return assert(false, "date/time fixture must parse"); }
  let a = pr.value;
  var ok = cab_file_date(&a, 0) == 23866;
  if cab_file_time(&a, 0) != 25692 { ok = false; }
  if cab_dos_date_year(cab_file_date(&a, 0)) != 2026 { ok = false; }
  if cab_dos_date_month(cab_file_date(&a, 0)) != 9 { ok = false; }
  if cab_dos_date_day(cab_file_date(&a, 0)) != 26 { ok = false; }
  if cab_dos_time_hour(cab_file_time(&a, 0)) != 12 { ok = false; }
  if cab_dos_time_minute(cab_file_time(&a, 0)) != 34 { ok = false; }
  if cab_dos_time_second(cab_file_time(&a, 0)) != 56 { ok = false; }
  if cab_dos_date_year(0) != 1980 { ok = false; }
  if cab_dos_date_month(0) != 0 { ok = false; }
  if cab_dos_date_day(0) != 0 { ok = false; }
  if cab_dos_time_hour(0) != 0 { ok = false; }
  if cab_dos_time_minute(0) != 0 { ok = false; }
  if cab_dos_time_second(0) != 0 { ok = false; }
  return assert(ok, "packed DOS date/time decode (2026-09-26 12:34:56)");
}

fn t13() -> TestResult {
  let foldoverflow = concat(hdr(3, 1, 100, 0, 0, 44, 44, 0, 0), fent(44, 0, 0));
  let fileoverflow = concat(hdr(3, 1, 1, 100, 0, 44, 44, 0, 0), fent(44, 0, 0));
  var names = Vec[Str].new();
  names.push("a.txt");
  names.push("b.bin");
  var sizes = Vec[Int].new();
  sizes.push(3);
  sizes.push(5);
  let r = cab_build(&names, &sizes);
  if !r.is_ok { return assert(false, "cab_build must succeed"); }
  let base = r.value;
  let lowcoff = set_u32(base, 16, 43);
  let highcoff = set_u32(base, 16, 89);
  var cutdir = set_u32(base, 8, 78);
  cutdir = set_u32(cutdir, 36, 0);
  var ok = err_archive_is(cab_parse(&foldoverflow), "cab: folder directory overflow");
  if !err_archive_is(cab_parse(&fileoverflow), "cab: file directory overflow") { ok = false; }
  if !err_archive_is(cab_parse(&lowcoff), "cab: coffFiles out of range") { ok = false; }
  if !err_archive_is(cab_parse(&highcoff), "cab: coffFiles out of range") { ok = false; }
  if !err_archive_is(cab_parse(&cutdir), "cab: truncated file directory") { ok = false; }
  if !cab_parse(&base).is_ok { ok = false; }
  return assert(ok, "directory extents and coffFiles bounds");
}

fn t14() -> TestResult {
  var names = Vec[Str].new();
  names.push("a.txt");
  names.push("b.bin");
  var sizes = Vec[Int].new();
  sizes.push(3);
  sizes.push(5);
  let r = cab_build(&names, &sizes);
  if !r.is_ok { return assert(false, "cab_build must succeed"); }
  let b = r.value;
  let pr = cab_parse(&b);
  if !pr.is_ok { return assert(false, "canonical fixture must parse"); }
  let a = pr.value;
  var ok = str_eq(cab_file_name(&a, -1), "");
  if !str_eq(cab_file_name(&a, 2), "") { ok = false; }
  if cab_file_size(&a, -1) != -1 { ok = false; }
  if cab_file_size(&a, 2) != -1 { ok = false; }
  if cab_file_offset(&a, -1) != -1 { ok = false; }
  if cab_file_folder(&a, -1) != -1 { ok = false; }
  if cab_file_date(&a, 2) != -1 { ok = false; }
  if cab_file_time(&a, -1) != -1 { ok = false; }
  if cab_file_attribs(&a, 2) != -1 { ok = false; }
  if cab_file_utf(&a, 2) { ok = false; }
  if cab_folder_start(&a, -1) != -1 { ok = false; }
  if cab_folder_start(&a, 1) != -1 { ok = false; }
  if cab_folder_data_count(&a, 5) != -1 { ok = false; }
  if cab_folder_compression(&a, -1) != -1 { ok = false; }
  if cab_folder_reserve_offset(&a, 1) != -1 { ok = false; }
  return assert(ok, "accessor sentinels for out-of-range indices");
}

fn t15() -> TestResult {
  var fix = hdr(3, 1, 2, 3, 0, 114, 52, 0, 0);
  fix = concat(fix, fent(90, 2, 1));
  fix = concat(fix, fent(100, 1, 3));
  fix = concat(fix, file_ent(0, 0, 0, 20000, 10000, 1, "r.txt"));
  fix = concat(fix, file_ent(1024, 0, 1, 0, 0, 32, "e.bin"));
  fix = concat(fix, file_ent(2048, 1024, 1, 0, 0, 160, "x"));
  var ok = fix.len() == 114;
  let pr = cab_parse(&fix);
  if !pr.is_ok {
    ok = false;
  } else {
    let a = pr.value;
    if cab_folder_count(&a) != 2 { ok = false; }
    if cab_file_count(&a) != 3 { ok = false; }
    if cab_folder_start(&a, 0) != 90 { ok = false; }
    if cab_folder_start(&a, 1) != 100 { ok = false; }
    if cab_folder_data_count(&a, 0) != 2 { ok = false; }
    if cab_folder_data_count(&a, 1) != 1 { ok = false; }
    if cab_folder_compression(&a, 0) != 1 { ok = false; }
    if cab_folder_compression(&a, 1) != 3 { ok = false; }
    if !name_is(&a, 0, "r.txt") { ok = false; }
    if !name_is(&a, 1, "e.bin") { ok = false; }
    if !name_is(&a, 2, "x") { ok = false; }
    if cab_file_folder(&a, 0) != 0 { ok = false; }
    if cab_file_folder(&a, 1) != 1 { ok = false; }
    if cab_file_folder(&a, 2) != 1 { ok = false; }
    if cab_file_size(&a, 0) != 0 { ok = false; }
    if cab_file_size(&a, 1) != 1024 { ok = false; }
    if cab_file_size(&a, 2) != 2048 { ok = false; }
    if cab_file_offset(&a, 2) != 1024 { ok = false; }
    if cab_file_attribs(&a, 0) != 1 { ok = false; }
    if cab_file_attribs(&a, 2) != 160 { ok = false; }
    if !cab_file_utf(&a, 2) { ok = false; }
    if cab_file_utf(&a, 0) { ok = false; }
    if cab_folder_reserve_offset(&a, 0) != 44 { ok = false; }
    if cab_folder_reserve_offset(&a, 1) != 52 { ok = false; }
  }
  let span = set_u32(set_u32(fix, 52, 4294967295), 56, 1);
  if !err_archive_is(cab_parse(&span), "cab: file span out of range") { ok = false; }
  return assert(ok, "two folders, three files and 32-bit file span bound");
}

fn t16() -> TestResult {
  var one = Vec[Str].new();
  one.push("a");
  var none = Vec[Int].new();
  var neg = Vec[Int].new();
  neg.push(-1);
  var huge = Vec[Int].new();
  huge.push(4294967296);
  var zero = Vec[Int].new();
  zero.push(0);
  var empty_name = Vec[Str].new();
  empty_name.push("");
  var tab_name = Vec[Str].new();
  tab_name.push(Str::from_utf8(hb("610962")));
  var long_name = Vec[Str].new();
  var long_bytes = Vec[UInt8].new();
  var i = 0;
  while i < 256 {
    long_bytes.push(110 as UInt8);
    i = i + 1;
  }
  long_name.push(Str::from_utf8(long_bytes));
  var ok = err_bytes_is(cab_build(&one, &none), "cab: entry count mismatch");
  if !err_bytes_is(cab_build(&one, &neg), "cab: size overflow") { ok = false; }
  if !err_bytes_is(cab_build(&one, &huge), "cab: size overflow") { ok = false; }
  if !err_bytes_is(cab_build(&empty_name, &zero), "cab: bad name") { ok = false; }
  if !err_bytes_is(cab_build(&tab_name, &zero), "cab: bad name") { ok = false; }
  if !err_bytes_is(cab_build(&long_name, &zero), "cab: name too long") { ok = false; }
  var ok255 = Vec[Str].new();
  var bytes255 = Vec[UInt8].new();
  i = 0;
  while i < 255 {
    bytes255.push(110 as UInt8);
    i = i + 1;
  }
  let s255: Str = Str::from_utf8(bytes255);
  ok255.push(s255);
  let r255 = cab_build(&ok255, &zero);
  if !r255.is_ok {
    ok = false;
  } else {
    let b255 = r255.value;
    if b255.len() != 316 { ok = false; }
    let p255 = cab_parse(&b255);
    if !p255.is_ok {
      ok = false;
    } else {
      let a255 = p255.value;
      let nm: Str = cab_file_name(&a255, 0);
      if nm.len() != 255 { ok = false; }
      if !name_is(&a255, 0, s255) { ok = false; }
    }
  }
  var spaced = Vec[Str].new();
  spaced.push("a b");
  var one_size = Vec[Int].new();
  one_size.push(1);
  let rs = cab_build(&spaced, &one_size);
  if !rs.is_ok {
    ok = false;
  } else {
    let sb: Vec[UInt8] = rs.value;
    let ps = cab_parse(&sb);
    if !ps.is_ok {
      ok = false;
    } else {
      let asp = ps.value;
      if !name_is(&asp, 0, "a b") { ok = false; }
    }
  }
  return assert(ok, "build validation and 255/256-byte name boundary");
}

fn t17() -> TestResult {
  var names = Vec[Str].new();
  names.push("a");
  names.push("bb");
  names.push("ccc");
  var sizes = Vec[Int].new();
  sizes.push(0);
  sizes.push(1);
  sizes.push(1000);
  let r1 = cab_build(&names, &sizes);
  if !r1.is_ok { return assert(false, "first build must succeed"); }
  let first = r1.value;
  let pr = cab_parse(&first);
  if !pr.is_ok { return assert(false, "built archive must parse"); }
  let a = pr.value;
  var names2 = Vec[Str].new();
  var sizes2 = Vec[Int].new();
  var i = 0;
  while i < cab_file_count(&a) {
    names2.push(cab_file_name(&a, i));
    sizes2.push(cab_file_size(&a, i));
    i = i + 1;
  }
  let r2 = cab_build(&names2, &sizes2);
  var ok = r2.is_ok;
  if r2.is_ok {
    let second: Vec[UInt8] = r2.value;
    if !bytes_equal(first, second) { ok = false; }
  }
  var no_names = Vec[Str].new();
  var no_sizes = Vec[Int].new();
  let re = cab_build(&no_names, &no_sizes);
  if !re.is_ok {
    ok = false;
  } else {
    let empty_cab = re.value;
    let want = hb("4d534346000000002c000000000000002c000000000000000301010000000000000000002c00000000000000");
    if !bytes_equal(empty_cab, want) { ok = false; }
    let pe = cab_parse(&empty_cab);
    if !pe.is_ok {
      ok = false;
    } else {
      let ae = pe.value;
      if cab_file_count(&ae) != 0 { ok = false; }
      if cab_folder_count(&ae) != 1 { ok = false; }
      if cab_folder_start(&ae, 0) != 44 { ok = false; }
      if cab_cabinet_size(&ae) != 44 { ok = false; }
    }
  }
  return assert(ok, "build -> parse -> build is byte-identical; empty cabinet pinned");
}

fn main() -> Int {
  io.println("=== xiom.cab conformance tests ===");
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
    io.println("xiom.cab: all tests passed");
  } else {
    io.println("xiom.cab: tests failed");
  }
  return failed;
}
