// XIOM -- xiom.rpm conformance tests (19 checks)
// Port task: prove the pure-XIOM xiom.rpm lead/header parser against the
// documented RPM byte layouts and error catalog.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Covers: the lead magic probe on full/short/bad/header-only buffers; every
// lead field with pinned values; lead truncation and each bad magic byte;
// the archnum/type/os canonical name maps; header prefix bytes and pinned
// index entries (tag/type/offset/count) on a 14-entry synthetic header;
// STRING, INT32 (with sign extension), CHAR, NULL and wrong-type tag
// lookups; the package-level convenience getters; absent-tag behavior;
// count-0/store-0 headers; truncated prefix/index/store errors; wrong
// header magic and version; headers at non-zero absolute offsets;
// STRING_ARRAY count/element rendering; out-of-store span clamping; the
// tags-vector drift guard; lead name edge cases (66 bytes without NUL,
// leading NUL, embedded NUL); and whole-file validate/parse cuts of the
// lead, signature header and main header.
//
// Str equality goes through str_compare (BUG 17 discipline: `==` on Str
// values read from a Vec lowers to a pointer comparison). Every byte buffer
// is hand-built in this file with Vec[UInt8].push, so the parser is
// exercised against bytes the test controls.

module rpm_tests
use xiom.io; use xiom.test;
use xiom.rpm;
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

fn str_eq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn err_lead_is(r: Result[RpmLead, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_header_is(r: Result[RpmHeader, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_pkg_is(r: Result[RpmPackage, Str], want: Str) -> Bool {
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
//  Byte builders (independent of src/rpm.xi)
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

fn push_u16be(v: &mut Vec[UInt8], x: Int) {
  v.push((x / 256) as UInt8);
  v.push((x % 256) as UInt8);
}

fn push_u32be(v: &mut Vec[UInt8], x: Int) {
  v.push((x / 16777216) as UInt8);
  v.push(((x / 65536) % 256) as UInt8);
  v.push(((x / 256) % 256) as UInt8);
  v.push((x % 256) as UInt8);
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

// One complete 96-byte program lead: magic, version, type, archnum, the
// 66-byte NUL-padded name, osnum, signature_type and 16 reserved bytes.
fn mk_lead_full(major: Int, minor: Int, ptype: Int, archnum: Int, name: Str, osnum: Int, sigtype: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  v.push(RPM_LEAD_MAGIC_0 as UInt8);
  v.push(RPM_LEAD_MAGIC_1 as UInt8);
  v.push(RPM_LEAD_MAGIC_2 as UInt8);
  v.push(RPM_LEAD_MAGIC_3 as UInt8);
  v.push(major as UInt8);
  v.push(minor as UInt8);
  push_u16be(&mut v, ptype);
  push_u16be(&mut v, archnum);
  push_text(&mut v, name);
  push_zeros(&mut v, 66 - name.len());
  push_u16be(&mut v, osnum);
  push_u16be(&mut v, sigtype);
  push_zeros(&mut v, 16);
  return v;
}

// Append one index entry (tag, type, offset, count) to a flat entry vector.
fn append_entry(e: &mut Vec[Int], tag: Int, tp: Int, ofs: Int, cnt: Int) {
  e.push(tag);
  e.push(tp);
  e.push(ofs);
  e.push(cnt);
}

// One complete header structure: magic+version, 4 reserved bytes, entry
// count, store size, the flat index entries and the store.
fn mk_header(entries: Vec[Int], store: Vec[UInt8]) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  v.push(RPM_HEADER_MAGIC_0 as UInt8);
  v.push(RPM_HEADER_MAGIC_1 as UInt8);
  v.push(RPM_HEADER_MAGIC_2 as UInt8);
  v.push(RPM_HEADER_VERSION as UInt8);
  push_zeros(&mut v, 4);
  push_u32be(&mut v, entries.len() / RPM_HDR_STRIDE);
  push_u32be(&mut v, store.len());
  var i = 0;
  while i < entries.len() {
    let x: Int = entries[i];
    push_u32be(&mut v, x);
    i = i + 1;
  }
  var j = 0;
  while j < store.len() {
    let b: UInt8 = store[j];
    v.push(b);
    j = j + 1;
  }
  return v;
}

// A whole synthetic file prefix: lead + empty signature header + main header.
fn mk_rpm_with(entries: Vec[Int], store: Vec[UInt8]) -> Vec[UInt8] {
  let lead = mk_lead_full(3, 0, 0, 1, "testpkg-1.2.3-7", 1, 5);
  var se = Vec[Int].new();
  var ss = Vec[UInt8].new();
  let sig = mk_header(se, ss);
  return concat(concat(lead, sig), mk_header(entries, store));
}

// Standard synthetic main header used by several tests. Store layout:
//   0  "testpkg"            8  "1.2.3"              14 "7"
//   16 "a test package"     31 "MIT"                35 "Applications/System"
//   55 "linux"              61 "x86_64"             68 "zstd"
//   73 BUILDTIME u32be 1700000000
//   77 "alpha\0beta\0"      88 'c' (one unterminated byte)
//   89 "d\0"
// Store length: 91. Entries: the ten common tags plus a CHAR probe (1126),
// a STRING_ARRAY (DESCRIPTION 1005), a NULL (9999) and a STRING (PACKAGER
// 1015). Entry count: 14.
fn std_main() -> Vec[UInt8] {
  var st = Vec[UInt8].new();
  let o_name: Int = st.len();
  push_text(&mut st, "testpkg"); st.push(0 as UInt8);
  let o_ver: Int = st.len();
  push_text(&mut st, "1.2.3"); st.push(0 as UInt8);
  let o_rel: Int = st.len();
  push_text(&mut st, "7"); st.push(0 as UInt8);
  let o_sum: Int = st.len();
  push_text(&mut st, "a test package"); st.push(0 as UInt8);
  let o_lic: Int = st.len();
  push_text(&mut st, "MIT"); st.push(0 as UInt8);
  let o_grp: Int = st.len();
  push_text(&mut st, "Applications/System"); st.push(0 as UInt8);
  let o_os: Int = st.len();
  push_text(&mut st, "linux"); st.push(0 as UInt8);
  let o_arch: Int = st.len();
  push_text(&mut st, "x86_64"); st.push(0 as UInt8);
  let o_pc: Int = st.len();
  push_text(&mut st, "zstd"); st.push(0 as UInt8);
  let o_bt: Int = st.len();
  push_u32be(&mut st, 1700000000);
  let o_arr: Int = st.len();
  push_text(&mut st, "alpha"); st.push(0 as UInt8);
  push_text(&mut st, "beta"); st.push(0 as UInt8);
  let o_ch: Int = st.len();
  st.push(99 as UInt8);
  let o_pk: Int = st.len();
  push_text(&mut st, "d"); st.push(0 as UInt8);
  var e = Vec[Int].new();
  append_entry(&mut e, RPM_TAG_NAME, RPM_TYPE_STRING, o_name, 1);
  append_entry(&mut e, RPM_TAG_VERSION, RPM_TYPE_STRING, o_ver, 1);
  append_entry(&mut e, RPM_TAG_RELEASE, RPM_TYPE_STRING, o_rel, 1);
  append_entry(&mut e, RPM_TAG_SUMMARY, RPM_TYPE_STRING, o_sum, 1);
  append_entry(&mut e, RPM_TAG_BUILDTIME, RPM_TYPE_INT32, o_bt, 1);
  append_entry(&mut e, RPM_TAG_LICENSE, RPM_TYPE_STRING, o_lic, 1);
  append_entry(&mut e, RPM_TAG_GROUP, RPM_TYPE_STRING, o_grp, 1);
  append_entry(&mut e, RPM_TAG_OS, RPM_TYPE_STRING, o_os, 1);
  append_entry(&mut e, RPM_TAG_ARCH, RPM_TYPE_STRING, o_arch, 1);
  append_entry(&mut e, RPM_TAG_PAYLOADCOMPRESSOR, RPM_TYPE_STRING, o_pc, 1);
  append_entry(&mut e, 1126, RPM_TYPE_CHAR, o_ch, 1);
  append_entry(&mut e, 1005, RPM_TYPE_STRING_ARRAY, o_arr, 2);
  append_entry(&mut e, 9999, RPM_TYPE_NULL, 0, 0);
  append_entry(&mut e, 1015, RPM_TYPE_STRING, o_pk, 1);
  return mk_header(e, st);
}

// The standard main header wrapped in lead + empty signature header.
fn std_file() -> Vec[UInt8] {
  let lead = mk_lead_full(3, 0, 0, 1, "testpkg-1.2.3-7", 1, 5);
  var se = Vec[Int].new();
  var ss = Vec[UInt8].new();
  let sig = mk_header(se, ss);
  return concat(concat(lead, sig), std_main());
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  let lead = mk_lead_full(3, 0, 0, 1, "t-1-1", 1, 5);
  var ok = lead.len() == 96;
  if !rpm_is_rpm(&lead) { ok = false; }
  var empty = Vec[UInt8].new();
  if rpm_is_rpm(&empty) { ok = false; }
  let three = prefix(lead, 3);
  if rpm_is_rpm(&three) { ok = false; }
  let four = prefix(lead, 4);
  if !rpm_is_rpm(&four) { ok = false; }
  let hdr_only = hb("8eade801");
  if rpm_is_rpm(&hdr_only) { ok = false; }
  let bad0 = set_byte(lead, 0, 236);
  if rpm_is_rpm(&bad0) { ok = false; }
  let bad3 = set_byte(lead, 3, 0);
  if rpm_is_rpm(&bad3) { ok = false; }
  return assert(ok, "lead magic probe: full, short, bad and header-only buffers");
}

fn t2() -> TestResult {
  let lead = mk_lead_full(3, 2, 1, 16, "pkg-1.0-1", 1, 5);
  let r = rpm_parse_lead(&lead);
  if !r.is_ok {
    return assert(false, "full lead must parse");
  }
  let l: RpmLead = r.value;
  var ok = l.major == 3;
  if l.minor != 2 { ok = false; }
  if l.ptype != 1 { ok = false; }
  if l.archnum != 16 { ok = false; }
  let nm: Str = l.name;
  if !str_eq(nm, "pkg-1.0-1") { ok = false; }
  if l.osnum != 1 { ok = false; }
  if l.signature_type != 5 { ok = false; }
  if (lead[80] as Int) != 0 { ok = false; }
  if (lead[95] as Int) != 0 { ok = false; }
  return assert(ok, "lead fields: major/minor/type/archnum/name/osnum/sigtype");
}

fn t3() -> TestResult {
  let full = mk_lead_full(3, 0, 0, 1, "x", 1, 5);
  let cut = prefix(full, 95);
  var ok = err_lead_is(rpm_parse_lead(&cut), "rpm: truncated lead");
  var empty = Vec[UInt8].new();
  if !err_lead_is(rpm_parse_lead(&empty), "rpm: truncated lead") { ok = false; }
  let bad0 = set_byte(full, 0, 0);
  if !err_lead_is(rpm_parse_lead(&bad0), "rpm: bad lead magic") { ok = false; }
  let bad1 = set_byte(full, 1, 170);
  if !err_lead_is(rpm_parse_lead(&bad1), "rpm: bad lead magic") { ok = false; }
  let bad2 = set_byte(full, 2, 239);
  if !err_lead_is(rpm_parse_lead(&bad2), "rpm: bad lead magic") { ok = false; }
  let bad3 = set_byte(full, 3, 220);
  if !err_lead_is(rpm_parse_lead(&bad3), "rpm: bad lead magic") { ok = false; }
  if !rpm_parse_lead(&full).is_ok { ok = false; }
  return assert(ok, "short leads and each wrong magic byte are rejected");
}

fn t4() -> TestResult {
  var ok = str_eq(rpm_lead_arch_name(0), "noarch");
  if !str_eq(rpm_lead_arch_name(1), "i386") { ok = false; }
  if !str_eq(rpm_lead_arch_name(2), "alpha") { ok = false; }
  if !str_eq(rpm_lead_arch_name(3), "sparc") { ok = false; }
  if !str_eq(rpm_lead_arch_name(4), "mips") { ok = false; }
  if !str_eq(rpm_lead_arch_name(5), "ppc") { ok = false; }
  if !str_eq(rpm_lead_arch_name(6), "m68k") { ok = false; }
  if !str_eq(rpm_lead_arch_name(7), "sgi") { ok = false; }
  if !str_eq(rpm_lead_arch_name(8), "rs6000") { ok = false; }
  if !str_eq(rpm_lead_arch_name(9), "ia64") { ok = false; }
  if !str_eq(rpm_lead_arch_name(10), "mipsel") { ok = false; }
  if !str_eq(rpm_lead_arch_name(11), "mips64") { ok = false; }
  if !str_eq(rpm_lead_arch_name(12), "arm") { ok = false; }
  if !str_eq(rpm_lead_arch_name(13), "m68kmint") { ok = false; }
  if !str_eq(rpm_lead_arch_name(14), "s390") { ok = false; }
  if !str_eq(rpm_lead_arch_name(15), "s390x") { ok = false; }
  if !str_eq(rpm_lead_arch_name(16), "ppc64") { ok = false; }
  if !str_eq(rpm_lead_arch_name(17), "sh") { ok = false; }
  if !str_eq(rpm_lead_arch_name(18), "xtensa") { ok = false; }
  if !str_eq(rpm_lead_arch_name(19), "aarch64") { ok = false; }
  if !str_eq(rpm_lead_arch_name(20), "mipsr6") { ok = false; }
  if !str_eq(rpm_lead_arch_name(21), "mipsr6el") { ok = false; }
  if !str_eq(rpm_lead_arch_name(22), "unknown") { ok = false; }
  if !str_eq(rpm_lead_arch_name(-1), "unknown") { ok = false; }
  if !str_eq(rpm_lead_type_name(0), "binary") { ok = false; }
  if !str_eq(rpm_lead_type_name(1), "source") { ok = false; }
  if !str_eq(rpm_lead_type_name(2), "unknown") { ok = false; }
  if !str_eq(rpm_lead_os_name(1), "linux") { ok = false; }
  if !str_eq(rpm_lead_os_name(0), "unknown") { ok = false; }
  if !str_eq(rpm_lead_os_name(3), "unknown") { ok = false; }
  return assert(ok, "lead archnum/type/os canonical name maps");
}

fn t5() -> TestResult {
  let hbts = std_main();
  var ok = hbts.len() == 16 + 14 * 16 + 91;
  if (hbts[0] as Int) != RPM_HEADER_MAGIC_0 { ok = false; }
  if (hbts[1] as Int) != RPM_HEADER_MAGIC_1 { ok = false; }
  if (hbts[2] as Int) != RPM_HEADER_MAGIC_2 { ok = false; }
  if (hbts[3] as Int) != RPM_HEADER_VERSION { ok = false; }
  if (hbts[4] as Int) != 0 { ok = false; }
  if (hbts[7] as Int) != 0 { ok = false; }
  if (hbts[11] as Int) != 14 { ok = false; }
  if (hbts[15] as Int) != 91 { ok = false; }
  if (hbts[18] as Int) != 3 { ok = false; }
  if (hbts[19] as Int) != 232 { ok = false; }
  if (hbts[23] as Int) != RPM_TYPE_STRING { ok = false; }
  let r = rpm_parse_header(&hbts, 0);
  if !r.is_ok {
    return assert(false, "synthetic header must parse");
  }
  let h: RpmHeader = r.value;
  if rpm_header_count(&h) != 14 { ok = false; }
  if rpm_header_store_len(&h) != 91 { ok = false; }
  if rpm_header_entry_tag(&h, 0) != RPM_TAG_NAME { ok = false; }
  if rpm_header_entry_type(&h, 0) != RPM_TYPE_STRING { ok = false; }
  if rpm_header_entry_offset(&h, 0) != 0 { ok = false; }
  if rpm_header_entry_count(&h, 0) != 1 { ok = false; }
  if rpm_header_entry_tag(&h, 4) != RPM_TAG_BUILDTIME { ok = false; }
  if rpm_header_entry_type(&h, 4) != RPM_TYPE_INT32 { ok = false; }
  if rpm_header_entry_offset(&h, 4) != 73 { ok = false; }
  if rpm_header_entry_tag(&h, 11) != 1005 { ok = false; }
  if rpm_header_entry_type(&h, 11) != RPM_TYPE_STRING_ARRAY { ok = false; }
  if rpm_header_entry_offset(&h, 11) != 77 { ok = false; }
  if rpm_header_entry_count(&h, 11) != 2 { ok = false; }
  if rpm_header_entry_type(&h, 12) != RPM_TYPE_NULL { ok = false; }
  if rpm_header_tag_type(&h, RPM_TAG_BUILDTIME) != RPM_TYPE_INT32 { ok = false; }
  if rpm_header_find(&h, 1015) != 13 { ok = false; }
  return assert(ok, "header prefix bytes and pinned index entries");
}

fn t6() -> TestResult {
  let hbts = std_main();
  let r = rpm_parse_header(&hbts, 0);
  if !r.is_ok {
    return assert(false, "synthetic header must parse");
  }
  let h: RpmHeader = r.value;
  var ok = str_eq(rpm_header_tag_str(&h, RPM_TAG_NAME), "testpkg");
  if !str_eq(rpm_header_tag_str(&h, RPM_TAG_VERSION), "1.2.3") { ok = false; }
  if !str_eq(rpm_header_tag_str(&h, RPM_TAG_RELEASE), "7") { ok = false; }
  if !str_eq(rpm_header_tag_str(&h, RPM_TAG_SUMMARY), "a test package") { ok = false; }
  if !str_eq(rpm_header_tag_str(&h, RPM_TAG_LICENSE), "MIT") { ok = false; }
  if !str_eq(rpm_header_tag_str(&h, RPM_TAG_GROUP), "Applications/System") { ok = false; }
  if !str_eq(rpm_header_tag_str(&h, RPM_TAG_OS), "linux") { ok = false; }
  if !str_eq(rpm_header_tag_str(&h, RPM_TAG_ARCH), "x86_64") { ok = false; }
  if !str_eq(rpm_header_tag_str(&h, RPM_TAG_PAYLOADCOMPRESSOR), "zstd") { ok = false; }
  if !str_eq(rpm_header_tag_str(&h, 1015), "d") { ok = false; }
  if !str_eq(rpm_header_tag_str(&h, 9999), "") { ok = false; }
  if !str_eq(rpm_header_tag_str(&h, 4242), "") { ok = false; }
  if rpm_header_has_tag(&h, RPM_TAG_NAME) != true { ok = false; }
  if rpm_header_has_tag(&h, 4242) != false { ok = false; }
  return assert(ok, "STRING tag lookup across the common header tags");
}

fn t7() -> TestResult {
  let hbts = std_main();
  let r = rpm_parse_header(&hbts, 0);
  if !r.is_ok {
    return assert(false, "synthetic header must parse");
  }
  let h: RpmHeader = r.value;
  var ok = rpm_header_tag_int(&h, RPM_TAG_BUILDTIME) == 1700000000;
  if rpm_header_tag_int(&h, 1126) != 99 { ok = false; }
  if rpm_header_tag_int(&h, 9999) != -1 { ok = false; }
  if rpm_header_tag_int(&h, RPM_TAG_NAME) != -1 { ok = false; }
  if rpm_header_tag_int(&h, 4242) != -1 { ok = false; }
  if !str_eq(rpm_header_tag_str(&h, RPM_TAG_BUILDTIME), "") { ok = false; }
  if !str_eq(rpm_header_tag_str(&h, 1126), "") { ok = false; }
  if !str_eq(rpm_header_tag_str(&h, 9999), "") { ok = false; }
  if rpm_header_has_tag(&h, 1126) != true { ok = false; }
  // INT32 0x80000000 is -2147483648 after sign extension. The store starts
  // at 16 + 14*16; BUILDTIME is 73 bytes in.
  let store_at: Int = 16 + 14 * 16;
  let neg = set_range(hbts, store_at + 73, hb("80000000"));
  let nr = rpm_parse_header(&neg, 0);
  if !nr.is_ok {
    ok = false;
  } else {
    let nh: RpmHeader = nr.value;
    if rpm_header_tag_int(&nh, RPM_TAG_BUILDTIME) != -2147483648 { ok = false; }
  }
  return assert(ok, "INT32 (signed), CHAR, NULL, wrong-type and absent lookups");
}

fn t8() -> TestResult {
  let f = std_file();
  let r = rpm_parse(&f);
  if !r.is_ok {
    return assert(false, "synthetic rpm must parse");
  }
  let p: RpmPackage = r.value;
  var ok = str_eq(rpm_get_name(&p), "testpkg");
  if !str_eq(rpm_get_version(&p), "1.2.3") { ok = false; }
  if !str_eq(rpm_get_release(&p), "7") { ok = false; }
  if !str_eq(rpm_get_summary(&p), "a test package") { ok = false; }
  if !str_eq(rpm_get_license(&p), "MIT") { ok = false; }
  if !str_eq(rpm_get_group(&p), "Applications/System") { ok = false; }
  if !str_eq(rpm_get_os(&p), "linux") { ok = false; }
  if !str_eq(rpm_get_arch(&p), "x86_64") { ok = false; }
  if !str_eq(rpm_get_payload_compressor(&p), "zstd") { ok = false; }
  if rpm_get_buildtime(&p) != 1700000000 { ok = false; }
  if p.major != 3 { ok = false; }
  if p.minor != 0 { ok = false; }
  if p.ptype != 0 { ok = false; }
  if p.archnum != 1 { ok = false; }
  if p.osnum != 1 { ok = false; }
  if p.signature_type != 5 { ok = false; }
  if !str_eq(p.lead_name, "testpkg-1.2.3-7") { ok = false; }
  if rpm_header_count(&p.header) != 14 { ok = false; }
  return assert(ok, "package getters and lead fields on a full synthetic file");
}

fn t9() -> TestResult {
  var e = Vec[Int].new();
  append_entry(&mut e, RPM_TAG_NAME, RPM_TYPE_STRING, 0, 1);
  var st = Vec[UInt8].new();
  push_text(&mut st, "only"); st.push(0 as UInt8);
  let hbts = mk_header(e, st);
  let r = rpm_parse_header(&hbts, 0);
  if !r.is_ok {
    return assert(false, "one-entry header must parse");
  }
  let h: RpmHeader = r.value;
  var ok = str_eq(rpm_header_tag_str(&h, RPM_TAG_NAME), "only");
  if rpm_header_has_tag(&h, RPM_TAG_VERSION) { ok = false; }
  if rpm_header_tag_type(&h, RPM_TAG_VERSION) != -1 { ok = false; }
  if rpm_header_tag_int(&h, RPM_TAG_VERSION) != -1 { ok = false; }
  if !str_eq(rpm_header_tag_str(&h, RPM_TAG_VERSION), "") { ok = false; }
  if rpm_header_tag_str_array_count(&h, RPM_TAG_NAME) != -1 { ok = false; }
  if !str_eq(rpm_header_tag_str_array_at(&h, RPM_TAG_NAME, 0), "") { ok = false; }
  if rpm_header_tag_int(&h, RPM_TAG_BUILDTIME) != -1 { ok = false; }
  if rpm_header_find(&h, RPM_TAG_NAME) != 0 { ok = false; }
  return assert(ok, "absent tags: no entry, -1 type/int, \"\" string");
}

fn t10() -> TestResult {
  var e = Vec[Int].new();
  var st = Vec[UInt8].new();
  let hbts = mk_header(e, st);
  var ok = hbts.len() == 16;
  let r = rpm_parse_header(&hbts, 0);
  if !r.is_ok {
    return assert(false, "empty header must parse");
  }
  let h: RpmHeader = r.value;
  if rpm_header_count(&h) != 0 { ok = false; }
  if rpm_header_store_len(&h) != 0 { ok = false; }
  if rpm_header_find(&h, RPM_TAG_NAME) != -1 { ok = false; }
  if !str_eq(rpm_header_tag_str(&h, RPM_TAG_NAME), "") { ok = false; }
  if rpm_header_tag_int(&h, RPM_TAG_BUILDTIME) != -1 { ok = false; }
  var e2 = Vec[Int].new();
  var st2 = Vec[UInt8].new();
  let f = mk_rpm_with(e2, st2);
  if !rpm_validate(&f).is_ok { ok = false; }
  let pr = rpm_parse(&f);
  if !pr.is_ok {
    ok = false;
  } else {
    let p: RpmPackage = pr.value;
    if !str_eq(rpm_get_name(&p), "") { ok = false; }
    if rpm_header_count(&p.header) != 0 { ok = false; }
  }
  return assert(ok, "empty header: count 0, store 0, absent lookups");
}

fn t11() -> TestResult {
  let hbts = std_main();
  var ok = true;
  let p8 = prefix(hbts, 8);
  if !err_header_is(rpm_parse_header(&p8, 0), "rpm: truncated header") { ok = false; }
  let p15 = prefix(hbts, 15);
  if !err_header_is(rpm_parse_header(&p15, 0), "rpm: truncated header") { ok = false; }
  let cut_index = prefix(hbts, 16 + 14 * 16 - 1);
  if !err_header_is(rpm_parse_header(&cut_index, 0), "rpm: truncated index") { ok = false; }
  let cut_store = prefix(hbts, 16 + 14 * 16 + 90);
  if !err_header_is(rpm_parse_header(&cut_store, 0), "rpm: truncated store") { ok = false; }
  var empty = Vec[UInt8].new();
  if !err_header_is(rpm_parse_header(&empty, -1), "rpm: truncated header") { ok = false; }
  if !err_header_is(rpm_parse_header(&empty, 5), "rpm: truncated header") { ok = false; }
  return assert(ok, "truncated prefix, index and store are distinct errors");
}

fn t12() -> TestResult {
  let hbts = std_main();
  let bad0 = set_byte(hbts, 0, 143);
  var ok = err_header_is(rpm_parse_header(&bad0, 0), "rpm: bad header magic");
  let bad2 = set_byte(hbts, 2, 233);
  if !err_header_is(rpm_parse_header(&bad2, 0), "rpm: bad header magic") { ok = false; }
  let badver = set_byte(hbts, 3, 2);
  if !err_header_is(rpm_parse_header(&badver, 0), "rpm: bad header version") { ok = false; }
  let lead = mk_lead_full(3, 0, 0, 1, "x", 1, 5);
  let bad_sig = concat(lead, bad0);
  if !err_pkg_is(rpm_parse(&bad_sig), "rpm: bad signature header") { ok = false; }
  if !err_unit_is(rpm_validate(&bad_sig), "rpm: bad signature header") { ok = false; }
  return assert(ok, "wrong header magic/version and a bad signature header");
}

fn t13() -> TestResult {
  let hbts = std_main();
  var junk = Vec[UInt8].new();
  junk.push(1 as UInt8);
  junk.push(2 as UInt8);
  junk.push(3 as UInt8);
  let shifted = concat(junk, hbts);
  let r = rpm_parse_header(&shifted, 3);
  if !r.is_ok {
    return assert(false, "shifted header must parse");
  }
  let h: RpmHeader = r.value;
  var ok = rpm_header_count(&h) == 14;
  if !str_eq(rpm_header_tag_str(&h, RPM_TAG_NAME), "testpkg") { ok = false; }
  if rpm_header_entry_offset(&h, 0) != 0 { ok = false; }
  if rpm_header_store_len(&h) != 91 { ok = false; }
  return assert(ok, "header parsed at a non-zero absolute offset");
}

fn t14() -> TestResult {
  let hbts = std_main();
  let r = rpm_parse_header(&hbts, 0);
  if !r.is_ok {
    return assert(false, "synthetic header must parse");
  }
  let h: RpmHeader = r.value;
  var ok = rpm_header_tag_str_array_count(&h, 1005) == 2;
  if !str_eq(rpm_header_tag_str(&h, 1005), "alpha") { ok = false; }
  if !str_eq(rpm_header_tag_str_array_at(&h, 1005, 0), "alpha") { ok = false; }
  if !str_eq(rpm_header_tag_str_array_at(&h, 1005, 1), "beta") { ok = false; }
  if !str_eq(rpm_header_tag_str_array_at(&h, 1005, 2), "") { ok = false; }
  if !str_eq(rpm_header_tag_str_array_at(&h, 1005, -1), "") { ok = false; }
  if rpm_header_tag_str_array_count(&h, RPM_TAG_NAME) != -1 { ok = false; }
  if !str_eq(rpm_header_tag_str_array_at(&h, RPM_TAG_NAME, 0), "") { ok = false; }
  // An array whose declared count exceeds the terminated run: elements past
  // the run render "" but the count field is still reported.
  var e = Vec[Int].new();
  append_entry(&mut e, 1005, RPM_TYPE_STRING_ARRAY, 0, 3);
  var st = Vec[UInt8].new();
  push_text(&mut st, "a"); st.push(0 as UInt8);
  push_text(&mut st, "b"); st.push(0 as UInt8);
  let arr_bytes = mk_header(e, st);
  let ar = rpm_parse_header(&arr_bytes, 0);
  if !ar.is_ok {
    ok = false;
  } else {
    let ah: RpmHeader = ar.value;
    if !str_eq(rpm_header_tag_str_array_at(&ah, 1005, 1), "b") { ok = false; }
    if !str_eq(rpm_header_tag_str_array_at(&ah, 1005, 2), "") { ok = false; }
    if rpm_header_tag_str_array_count(&ah, 1005) != 3 { ok = false; }
  }
  return assert(ok, "STRING_ARRAY count, elements and rendering");
}

fn t15() -> TestResult {
  var e = Vec[Int].new();
  append_entry(&mut e, 1000, RPM_TYPE_STRING, 3, 1);
  append_entry(&mut e, 1001, RPM_TYPE_INT32, 1, 1);
  append_entry(&mut e, 1002, RPM_TYPE_CHAR, 7, 1);
  append_entry(&mut e, 1003, RPM_TYPE_STRING_ARRAY, 9, 2);
  var st = Vec[UInt8].new();
  push_text(&mut st, "abc");
  let hbts = mk_header(e, st);
  let r = rpm_parse_header(&hbts, 0);
  if !r.is_ok {
    return assert(false, "bounded header must parse");
  }
  let h: RpmHeader = r.value;
  var ok = rpm_header_count(&h) == 4;
  if !str_eq(rpm_header_tag_str(&h, 1000), "") { ok = false; }
  if rpm_header_tag_int(&h, 1001) != -1 { ok = false; }
  if rpm_header_tag_int(&h, 1002) != -1 { ok = false; }
  if !str_eq(rpm_header_tag_str(&h, 1003), "") { ok = false; }
  if !str_eq(rpm_header_tag_str_array_at(&h, 1003, 0), "") { ok = false; }
  if rpm_header_tag_str_array_count(&h, 1003) != 2 { ok = false; }
  // A span that exactly fits is still read.
  var e2 = Vec[Int].new();
  append_entry(&mut e2, RPM_TAG_BUILDTIME, RPM_TYPE_INT32, 0, 1);
  var st2 = Vec[UInt8].new();
  push_u32be(&mut st2, 42);
  let hb2 = mk_header(e2, st2);
  let r2 = rpm_parse_header(&hb2, 0);
  if !r2.is_ok {
    ok = false;
  } else {
    let h2: RpmHeader = r2.value;
    if rpm_header_tag_int(&h2, RPM_TAG_BUILDTIME) != 42 { ok = false; }
  }
  return assert(ok, "accessors clamp out-of-store spans to -1 / \"\"");
}

fn t16() -> TestResult {
  var ok = true;
  // Unknown type (9, I18NSTRING-like) with an in-range offset is accepted.
  var e0 = Vec[Int].new();
  append_entry(&mut e0, 1005, 9, 0, 1);
  var s0 = Vec[UInt8].new();
  push_text(&mut s0, "x"); s0.push(0 as UInt8);
  let f0 = mk_rpm_with(e0, s0);
  if !rpm_validate(&f0).is_ok { ok = false; }
  // An INT32 entry whose span exceeds the store.
  var e1 = Vec[Int].new();
  append_entry(&mut e1, RPM_TAG_BUILDTIME, RPM_TYPE_INT32, 4, 2);
  var s1 = Vec[UInt8].new();
  push_u32be(&mut s1, 7);
  let f1 = mk_rpm_with(e1, s1);
  if !err_unit_is(rpm_validate(&f1), "rpm: tag out of range") { ok = false; }
  // A STRING without a terminating NUL: validate rejects, the accessor
  // still renders the bytes up to the end of the store.
  var e2 = Vec[Int].new();
  append_entry(&mut e2, RPM_TAG_NAME, RPM_TYPE_STRING, 0, 1);
  var s2 = Vec[UInt8].new();
  push_text(&mut s2, "abc");
  let f2 = mk_rpm_with(e2, s2);
  if !err_unit_is(rpm_validate(&f2), "rpm: string missing NUL") { ok = false; }
  let hr = rpm_parse(&f2);
  if !hr.is_ok {
    ok = false;
  } else {
    let p: RpmPackage = hr.value;
    if !str_eq(rpm_get_name(&p), "abc") { ok = false; }
  }
  // A STRING_ARRAY with more declared elements than terminated strings.
  var e3 = Vec[Int].new();
  append_entry(&mut e3, 1005, RPM_TYPE_STRING_ARRAY, 0, 3);
  var s3 = Vec[UInt8].new();
  push_text(&mut s3, "a"); s3.push(0 as UInt8);
  let f3 = mk_rpm_with(e3, s3);
  if !err_unit_is(rpm_validate(&f3), "rpm: string missing NUL") { ok = false; }
  // A STRING offset exactly at the end of the store.
  var e4 = Vec[Int].new();
  append_entry(&mut e4, RPM_TAG_NAME, RPM_TYPE_STRING, 3, 1);
  var s4 = Vec[UInt8].new();
  push_text(&mut s4, "abc");
  let f4 = mk_rpm_with(e4, s4);
  if !err_unit_is(rpm_validate(&f4), "rpm: tag out of range") { ok = false; }
  return assert(ok, "rpm_validate entry bounds, NULs and unknown types");
}

fn t17() -> TestResult {
  let hbts = std_main();
  let r = rpm_parse_header(&hbts, 0);
  if !r.is_ok {
    return assert(false, "synthetic header must parse");
  }
  let h: RpmHeader = r.value;
  var ok = rpm_header_entry_tag(&h, 13) == 1015;
  if rpm_header_entry_tag(&h, -1) != -1 { ok = false; }
  if rpm_header_entry_tag(&h, 14) != -1 { ok = false; }
  if rpm_header_entry_type(&h, 14) != -1 { ok = false; }
  if rpm_header_entry_offset(&h, 14) != -1 { ok = false; }
  if rpm_header_entry_count(&h, 14) != -1 { ok = false; }
  if rpm_header_find(&h, -1) != -1 { ok = false; }
  // Drift guard: a tags vector that is not a whole number of entries must
  // never be read as entries.
  var t2 = Vec[Int].new();
  t2.push(1);
  var s2 = Vec[UInt8].new();
  let h2 = RpmHeader{ tags: t2; store: s2; };
  if rpm_header_count(&h2) != -1 { ok = false; }
  if rpm_header_find(&h2, 1) != -1 { ok = false; }
  if rpm_header_tag_type(&h2, 1) != -1 { ok = false; }
  if rpm_header_tag_int(&h2, 1) != -1 { ok = false; }
  if !str_eq(rpm_header_tag_str(&h2, 1), "") { ok = false; }
  if rpm_header_entry_tag(&h2, 0) != -1 { ok = false; }
  if rpm_header_store_len(&h2) != 0 { ok = false; }
  return assert(ok, "entry index ranges and the tags drift guard");
}

fn t18() -> TestResult {
  // A 66-byte name field without a NUL is returned in full.
  var long = Vec[UInt8].new();
  var i = 0;
  while i < 66 {
    long.push(97 as UInt8);
    i = i + 1;
  }
  let lname: Str = Str::from_utf8(long);
  let lead = mk_lead_full(3, 0, 0, 1, lname, 1, 5);
  var ok = lead.len() == 96;
  let r = rpm_parse_lead(&lead);
  if !r.is_ok {
    return assert(false, "66-byte name lead must parse");
  }
  let l: RpmLead = r.value;
  let nm: Str = l.name;
  if nm.len() != 66 { ok = false; }
  if !str_eq(nm, lname) { ok = false; }
  // A NUL as the first name byte yields an empty name.
  let lead0 = set_byte(mk_lead_full(3, 0, 0, 1, "abc", 1, 5), 10, 0);
  let r0 = rpm_parse_lead(&lead0);
  if !r0.is_ok {
    ok = false;
  } else {
    let l0: RpmLead = r0.value;
    if !str_eq(l0.name, "") { ok = false; }
  }
  // An embedded NUL ends the name; later bytes are ignored.
  let leadm = set_byte(mk_lead_full(3, 0, 0, 1, "abcd", 1, 5), 12, 0);
  let rm = rpm_parse_lead(&leadm);
  if !rm.is_ok {
    ok = false;
  } else {
    let lm: RpmLead = rm.value;
    if !str_eq(lm.name, "ab") { ok = false; }
  }
  return assert(ok, "lead name: full 66 bytes, leading NUL, embedded NUL");
}

fn t19() -> TestResult {
  let f = std_file();
  var ok = rpm_validate(&f).is_ok;
  let cut_lead = prefix(f, 40);
  if !err_unit_is(rpm_validate(&cut_lead), "rpm: truncated lead") { ok = false; }
  if !err_pkg_is(rpm_parse(&cut_lead), "rpm: truncated lead") { ok = false; }
  let bad_magic = set_byte(f, 1, 0);
  if !err_unit_is(rpm_validate(&bad_magic), "rpm: bad lead magic") { ok = false; }
  let cut_sig = prefix(f, 96 + 10);
  if !err_unit_is(rpm_validate(&cut_sig), "rpm: bad signature header") { ok = false; }
  if !err_pkg_is(rpm_parse(&cut_sig), "rpm: bad signature header") { ok = false; }
  let main_start: Int = 96 + 16;
  let cut_main = prefix(f, main_start + 4);
  if !err_unit_is(rpm_validate(&cut_main), "rpm: truncated header") { ok = false; }
  let cut_idx = prefix(f, main_start + 16 + 14 * 16 - 1);
  if !err_unit_is(rpm_validate(&cut_idx), "rpm: truncated index") { ok = false; }
  let cut_store = prefix(f, f.len() - 1);
  if !err_unit_is(rpm_validate(&cut_store), "rpm: truncated store") { ok = false; }
  return assert(ok, "whole-file validate: lead, signature and main-header cuts");
}

fn main() -> Int {
  io.println("=== xiom.rpm conformance tests ===");
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
  if failed == 0 {
    io.println("xiom.rpm: all tests passed");
  } else {
    io.println("xiom.rpm: tests failed");
  }
  return failed;
}
