// XIOM -- xiom.ar conformance tests (20 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Covers the documented API: the pinned canonical ar_build bytes (global
// magic, space-padded name, decimal mtime/uid/gid/size, octal mode,
// terminator 0x60 0x0A, 0x0A odd-size pad); hand-built archives with pinned
// names, fields, header/data offsets and data slices; BSD "#1/<len>"
// extended names (including names with spaces); plain-name rules (trailing
// '/' stripped, 16-byte exact field, space terminates); the odd-size padding
// rules and their errors; build -> parse -> build byte-identical round
// trips; global magic and header truncation errors; bad terminator bytes;
// malformed decimal and octal fields; size/data mismatches; the rejection of
// the GNU special members "/", "//", "/N" and "/SYM64/"; the 16/17/255/256
// name boundaries; build validation with untouched buffers; accessor bounds
// and data slicing; ar_global + ar_append composition; numeric field forms
// (leading zeros and spaces); member offset arithmetic; and magic-only
// (empty) archives.
//
// Str equality goes through str_compare (BUG 17 discipline: `==` on Str
// values read from a Vec lowers to a pointer comparison). Hand-built
// archives are assembled byte by byte in this file, so the parser is
// exercised against bytes the test controls rather than against ar_build.

module ar_tests
use xiom.io; use xiom.test;
use xiom.ar;
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

fn err_archive_is(r: Result[ArArchive, Str], want: Str) -> Bool {
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
//  Byte helpers (independent of src/ar.xi)
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

// Left-aligned decimal digits space padded to `width`.
fn push_dec_pad(v: &mut Vec[UInt8], val: Int, width: Int) {
  var digits = Vec[UInt8].new();
  if val == 0 {
    digits.push(48 as UInt8);
  } else {
    var n = val;
    while n > 0 {
      let d: Int = n % 10;
      digits.push((48 + d) as UInt8);
      n = n / 10;
    }
  }
  var i: Int = digits.len() - 1;
  while i >= 0 {
    v.push(digits[i]);
    i = i - 1;
  }
  var used: Int = digits.len();
  while used < width {
    v.push(32 as UInt8);
    used = used + 1;
  }
}

// Left-aligned octal digits space padded to `width`.
fn push_oct_pad(v: &mut Vec[UInt8], val: Int, width: Int) {
  var digits = Vec[UInt8].new();
  if val == 0 {
    digits.push(48 as UInt8);
  } else {
    var n = val;
    while n > 0 {
      let d: Int = n % 8;
      digits.push((48 + d) as UInt8);
      n = n / 8;
    }
  }
  var i: Int = digits.len() - 1;
  while i >= 0 {
    v.push(digits[i]);
    i = i - 1;
  }
  var used: Int = digits.len();
  while used < width {
    v.push(32 as UInt8);
    used = used + 1;
  }
}

fn dec_str(n: Int) -> Str {
  var v = Vec[UInt8].new();
  push_dec_pad(&mut v, n, 0);
  return Str::from_utf8(v);
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

fn cat(a: Vec[UInt8], b: Vec[UInt8]) -> Vec[UInt8] {
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

fn meta4(mtime: Int, uid: Int, gid: Int, mode: Int) -> Vec[Int] {
  var m = Vec[Int].new();
  m.push(mtime);
  m.push(uid);
  m.push(gid);
  m.push(mode);
  return m;
}

// --------------------------------------------------
//  Hand-built archives (independent of src/ar.xi)
// --------------------------------------------------

fn magic() -> Vec[UInt8] {
  return hb("213c617263683e0a");
}

// Plain 16-byte name field: the name bytes then spaces (callers keep the
// name at 16 bytes or less).
fn plain16(name: Str) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  push_text(&mut v, name);
  while v.len() < 16 {
    v.push(32 as UInt8);
  }
  return v;
}

// BSD extended name field: "#1/<s>" then spaces to 16 bytes.
fn bsd16_text(s: Str) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  push_text(&mut v, "#1/");
  push_text(&mut v, s);
  while v.len() < 16 {
    v.push(32 as UInt8);
  }
  return v;
}

fn bsd16(n: Int) -> Vec[UInt8] {
  return bsd16_text(dec_str(n));
}

// One complete member with an explicit name field, declared size and pad
// mode: -1 = no pad byte, otherwise the pad byte value (only written when
// the declared size is odd).
fn mk_member_ex(name_field: Vec[UInt8], mtime: Int, uid: Int, gid: Int, mode: Int, size: Int, body: Vec[UInt8], pad: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < name_field.len() {
    v.push(name_field[i]);
    i = i + 1;
  }
  push_dec_pad(&mut v, mtime, 12);
  push_dec_pad(&mut v, uid, 6);
  push_dec_pad(&mut v, gid, 6);
  push_oct_pad(&mut v, mode, 8);
  push_dec_pad(&mut v, size, 10);
  v.push(96 as UInt8);
  v.push(10 as UInt8);
  i = 0;
  while i < body.len() {
    v.push(body[i]);
    i = i + 1;
  }
  if size % 2 == 1 && pad >= 0 {
    v.push(pad as UInt8);
  }
  return v;
}

// Canonical member: size = body.len(), '\n' pad when odd.
fn mk_member(name_field: Vec[UInt8], mtime: Int, uid: Int, gid: Int, mode: Int, body: Vec[UInt8]) -> Vec[UInt8] {
  return mk_member_ex(name_field, mtime, uid, gid, mode, body.len(), body, 10);
}

fn mk_plain(name: Str, mtime: Int, uid: Int, gid: Int, mode: Int, data: Vec[UInt8]) -> Vec[UInt8] {
  return mk_member(plain16(name), mtime, uid, gid, mode, data);
}

fn mk_bsd(name: Str, mtime: Int, uid: Int, gid: Int, mode: Int, data: Vec[UInt8]) -> Vec[UInt8] {
  var body = Vec[UInt8].new();
  push_text(&mut body, name);
  var i = 0;
  while i < data.len() {
    body.push(data[i]);
    i = i + 1;
  }
  return mk_member(bsd16(name.len()), mtime, uid, gid, mode, body);
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  var names = Vec[Str].new();
  names.push("a.txt");
  var datas = Vec[Vec[UInt8]].new();
  datas.push(bytes_of("abc"));
  let metas = meta4(1700000000, 1000, 1000, 33188);
  let r = ar_build(&names, &datas, &metas);
  if !r.is_ok { return assert(false, "ar_build must succeed"); }
  let out: Vec[UInt8] = r.value;
  let want = hb("213c617263683e0a" + "612e7478742020202020202020202020" + "313730303030303030302020" + "313030302020" + "313030302020" + "3130303634342020" + "33202020202020202020" + "600a" + "6162630a");
  var ok = out.len() == 72;
  if !bytes_equal(out, want) { ok = false; }
  let pr = ar_parse(&out);
  if !pr.is_ok {
    return assert(false, "the built archive must parse");
  }
  let ar: ArArchive = pr.value;
  if ar_count(&ar) != 1 { ok = false; }
  if !str_eq(ar_entry_name(&ar, 0), "a.txt") { ok = false; }
  if ar_entry_size(&ar, 0) != 3 { ok = false; }
  if ar_entry_mtime(&ar, 0) != 1700000000 { ok = false; }
  if ar_entry_uid(&ar, 0) != 1000 { ok = false; }
  if ar_entry_gid(&ar, 0) != 1000 { ok = false; }
  if ar_entry_mode(&ar, 0) != 33188 { ok = false; }
  if ar_entry_header_offset(&ar, 0) != 8 { ok = false; }
  if ar_entry_data_offset(&ar, 0) != 68 { ok = false; }
  let d = ar_entry_data(&out, &ar, 0);
  if !d.is_ok { ok = false; } else { if !bytes_equal(d.value, bytes_of("abc")) { ok = false; } }
  return assert(ok, "ar_build emits the pinned canonical member and round-trips");
}

fn t2() -> TestResult {
  let m1 = mk_plain("one.txt", 100, 1, 2, 420, bytes_of("abc"));
  let m2 = mk_plain("two", 0, 0, 0, 33188, zeros(0));
  let arc = cat(cat(magic(), m1), m2);
  var ok = arc.len() == 132;
  if (arc[71] as Int) != 10 { ok = false; }
  let pr = ar_parse(&arc);
  if !pr.is_ok {
    return assert(false, "hand-built archive must parse");
  }
  let ar: ArArchive = pr.value;
  if ar_count(&ar) != 2 { ok = false; }
  if !str_eq(ar_entry_name(&ar, 0), "one.txt") { ok = false; }
  if !str_eq(ar_entry_name(&ar, 1), "two") { ok = false; }
  if ar_entry_size(&ar, 0) != 3 { ok = false; }
  if ar_entry_size(&ar, 1) != 0 { ok = false; }
  if ar_entry_mtime(&ar, 0) != 100 { ok = false; }
  if ar_entry_mtime(&ar, 1) != 0 { ok = false; }
  if ar_entry_uid(&ar, 0) != 1 { ok = false; }
  if ar_entry_gid(&ar, 0) != 2 { ok = false; }
  if ar_entry_mode(&ar, 0) != 420 { ok = false; }
  if ar_entry_mode(&ar, 1) != 33188 { ok = false; }
  if ar_entry_header_offset(&ar, 0) != 8 { ok = false; }
  if ar_entry_header_offset(&ar, 1) != 72 { ok = false; }
  if ar_entry_data_offset(&ar, 0) != 68 { ok = false; }
  if ar_entry_data_offset(&ar, 1) != 132 { ok = false; }
  let d0 = ar_entry_data(&arc, &ar, 0);
  if !d0.is_ok { ok = false; } else { if !bytes_equal(d0.value, bytes_of("abc")) { ok = false; } }
  let d1 = ar_entry_data(&arc, &ar, 1);
  if !d1.is_ok { ok = false; } else { if d1.value.len() != 0 { ok = false; } }
  return assert(ok, "hand-built plain members: names, fields and offsets");
}

fn t3() -> TestResult {
  let m1 = mk_bsd("verylong.txt!", 7, 8, 9, 420, bytes_of("abc"));
  let m2 = mk_bsd("a b", 0, 0, 0, 420, bytes_of("xy"));
  let arc = cat(cat(magic(), m1), m2);
  var ok = arc.len() == 8 + 76 + 66;
  let pr = ar_parse(&arc);
  if !pr.is_ok {
    return assert(false, "BSD archive must parse");
  }
  let ar: ArArchive = pr.value;
  if ar_count(&ar) != 2 { ok = false; }
  if !str_eq(ar_entry_name(&ar, 0), "verylong.txt!") { ok = false; }
  if !str_eq(ar_entry_name(&ar, 1), "a b") { ok = false; }
  if ar_entry_size(&ar, 0) != 3 { ok = false; }
  if ar_entry_size(&ar, 1) != 2 { ok = false; }
  if ar_entry_header_offset(&ar, 1) != 84 { ok = false; }
  if ar_entry_data_offset(&ar, 0) != 8 + 60 + 13 { ok = false; }
  if ar_entry_data_offset(&ar, 1) != 84 + 60 + 3 { ok = false; }
  let d0 = ar_entry_data(&arc, &ar, 0);
  if !d0.is_ok { ok = false; } else { if !bytes_equal(d0.value, bytes_of("abc")) { ok = false; } }
  let d1 = ar_entry_data(&arc, &ar, 1);
  if !d1.is_ok { ok = false; } else { if !bytes_equal(d1.value, bytes_of("xy")) { ok = false; } }
  if !bytes_equal(slice(arc, 68, 81), hb("766572796c6f6e672e74787421")) { ok = false; }
  return assert(ok, "BSD #1/<len> names decode and locate the payload");
}

fn t4() -> TestResult {
  let m1 = mk_plain("foo/", 0, 0, 0, 420, zeros(0));
  let m2 = mk_plain("0123456789abcdef", 0, 0, 0, 420, zeros(0));
  let m3 = mk_plain("ab cd", 0, 0, 0, 420, zeros(0));
  let arc = cat(cat(cat(magic(), m1), m2), m3);
  let pr = ar_parse(&arc);
  if !pr.is_ok {
    return assert(false, "name archive must parse");
  }
  let ar: ArArchive = pr.value;
  var ok = ar_count(&ar) == 3;
  if !str_eq(ar_entry_name(&ar, 0), "foo") { ok = false; }
  if !str_eq(ar_entry_name(&ar, 1), "0123456789abcdef") { ok = false; }
  if !str_eq(ar_entry_name(&ar, 2), "ab") { ok = false; }
  return assert(ok, "plain names: trailing / stripped, 16-byte exact, space terminates");
}

fn t5() -> TestResult {
  let a0 = mk_plain("a", 0, 0, 0, 420, zeros(0));
  let a1 = mk_plain("b", 0, 0, 0, 420, bytes_of("x"));
  let a2 = mk_plain("c", 0, 0, 0, 420, bytes_of("xy"));
  let a3 = mk_plain("d", 0, 0, 0, 420, bytes_of("xyz"));
  var ok = a0.len() == 60;
  if a1.len() != 62 { ok = false; }
  if a2.len() != 62 { ok = false; }
  if a3.len() != 64 { ok = false; }
  if (a1[61] as Int) != 10 { ok = false; }
  if (a3[63] as Int) != 10 { ok = false; }
  let arc = cat(cat(cat(cat(magic(), a0), a1), a2), a3);
  let pr = ar_parse(&arc);
  if !pr.is_ok {
    return assert(false, "padding archive must parse");
  }
  let ar: ArArchive = pr.value;
  if ar_count(&ar) != 4 { ok = false; }
  if ar_entry_size(&ar, 0) != 0 { ok = false; }
  if ar_entry_size(&ar, 1) != 1 { ok = false; }
  if ar_entry_size(&ar, 2) != 2 { ok = false; }
  if ar_entry_size(&ar, 3) != 3 { ok = false; }
  let no_pad = cat(magic(), mk_member_ex(plain16("e"), 0, 0, 0, 420, 1, bytes_of("x"), -1));
  if !err_archive_is(ar_parse(&no_pad), "ar: missing padding") { ok = false; }
  let zero_pad = cat(magic(), mk_member_ex(plain16("e"), 0, 0, 0, 420, 1, bytes_of("x"), 0));
  if !err_archive_is(ar_parse(&zero_pad), "ar: bad padding") { ok = false; }
  let space_pad = cat(magic(), mk_member_ex(plain16("e"), 0, 0, 0, 420, 1, bytes_of("x"), 32));
  if !err_archive_is(ar_parse(&space_pad), "ar: bad padding") { ok = false; }
  return assert(ok, "odd members carry one 0x0A pad; missing/bad pad Err");
}

fn t6() -> TestResult {
  var names = Vec[Str].new();
  names.push("one.txt");
  names.push("two");
  names.push("averyverylongname");
  var datas = Vec[Vec[UInt8]].new();
  datas.push(data_of(1, 3));
  datas.push(zeros(0));
  datas.push(data_of(4, 7));
  var metas = Vec[Int].new();
  metas.push(1); metas.push(2); metas.push(3); metas.push(33188);
  metas.push(0); metas.push(0); metas.push(0); metas.push(420);
  metas.push(9); metas.push(8); metas.push(7); metas.push(493);
  let r1 = ar_build(&names, &datas, &metas);
  if !r1.is_ok { return assert(false, "build must succeed"); }
  let first: Vec[UInt8] = r1.value;
  let pr = ar_parse(&first);
  if !pr.is_ok { return assert(false, "built archive must parse"); }
  let ar: ArArchive = pr.value;
  var ok = ar_count(&ar) == 3;
  var names2 = Vec[Str].new();
  var datas2 = Vec[Vec[UInt8]].new();
  var metas2 = Vec[Int].new();
  var e = 0;
  while e < ar_count(&ar) {
    names2.push(ar_entry_name(&ar, e));
    let dd = ar_entry_data(&first, &ar, e);
    if !dd.is_ok {
      ok = false;
    } else {
      let dv: Vec[UInt8] = dd.value;
      datas2.push(dv);
    }
    metas2.push(ar_entry_mtime(&ar, e));
    metas2.push(ar_entry_uid(&ar, e));
    metas2.push(ar_entry_gid(&ar, e));
    metas2.push(ar_entry_mode(&ar, e));
    e = e + 1;
  }
  let r2 = ar_build(&names2, &datas2, &metas2);
  if !r2.is_ok {
    ok = false;
  } else {
    let second: Vec[UInt8] = r2.value;
    if !bytes_equal(first, second) { ok = false; }
  }
  return assert(ok, "build -> parse -> build is byte-identical");
}

fn t7() -> TestResult {
  var empty = Vec[UInt8].new();
  var ok = err_archive_is(ar_parse(&empty), "ar: bad global magic");
  let short = hb("213c617263683e");
  if !err_archive_is(ar_parse(&short), "ar: bad global magic") { ok = false; }
  let wrong = hb("213c617263683e0d");
  if !err_archive_is(ar_parse(&wrong), "ar: bad global magic") { ok = false; }
  let only = magic();
  let orc = ar_parse(&only);
  if !orc.is_ok {
    ok = false;
  } else {
    let oa: ArArchive = orc.value;
    if ar_count(&oa) != 0 { ok = false; }
  }
  let tail59 = cat(magic(), zeros(59));
  if !err_archive_is(ar_parse(&tail59), "ar: truncated header") { ok = false; }
  let good = cat(magic(), mk_plain("a", 0, 0, 0, 420, zeros(0)));
  let partial = cat(good, zeros(30));
  if !err_archive_is(ar_parse(&partial), "ar: truncated header") { ok = false; }
  if !ar_parse(&good).is_ok { ok = false; }
  return assert(ok, "global magic and member header truncation are Err");
}

fn t8() -> TestResult {
  let good = cat(magic(), mk_plain("a", 0, 0, 0, 420, zeros(0)));
  var ok = ar_parse(&good).is_ok;
  let bad1 = set_byte(good, 8 + 58, 97);
  if !err_archive_is(ar_parse(&bad1), "ar: bad terminator") { ok = false; }
  let bad2 = set_byte(good, 8 + 59, 32);
  if !err_archive_is(ar_parse(&bad2), "ar: bad terminator") { ok = false; }
  let bad3 = set_byte(good, 8 + 59, 0);
  if !err_archive_is(ar_parse(&bad3), "ar: bad terminator") { ok = false; }
  return assert(ok, "wrong terminator bytes are Err");
}

fn t9() -> TestResult {
  let good = cat(magic(), mk_plain("a", 42, 7, 8, 420, bytes_of("x")));
  var ok = ar_parse(&good).is_ok;
  let bad_mtime = set_byte(good, 8 + 16, 120);
  if !err_archive_is(ar_parse(&bad_mtime), "ar: bad decimal field") { ok = false; }
  let bad_uid = set_byte(good, 8 + 28, 45);
  if !err_archive_is(ar_parse(&bad_uid), "ar: bad decimal field") { ok = false; }
  let bad_gid = set_byte(good, 8 + 34, 46);
  if !err_archive_is(ar_parse(&bad_gid), "ar: bad decimal field") { ok = false; }
  let bad_size = set_byte(good, 8 + 48, 122);
  if !err_archive_is(ar_parse(&bad_size), "ar: bad decimal field") { ok = false; }
  let gap = set_range(good, 8 + 16, bytes_of("4 2"));
  if !err_archive_is(ar_parse(&gap), "ar: bad decimal field") { ok = false; }
  let blank = set_range(good, 8 + 16, bytes_of("            "));
  if !err_archive_is(ar_parse(&blank), "ar: bad decimal field") { ok = false; }
  let bad_bsd = cat(magic(), mk_member_ex(bsd16_text("xx"), 0, 0, 0, 420, 0, zeros(0), 10));
  if !err_archive_is(ar_parse(&bad_bsd), "ar: bad decimal field") { ok = false; }
  return assert(ok, "malformed decimal fields are Err");
}

fn t10() -> TestResult {
  let good = cat(magic(), mk_plain("m", 0, 0, 0, 33188, zeros(0)));
  let pr = ar_parse(&good);
  var ok = false;
  if pr.is_ok {
    let ar: ArArchive = pr.value;
    ok = ar_entry_mode(&ar, 0) == 33188;
  }
  let bad8 = set_byte(good, 8 + 40, 56);
  if !err_archive_is(ar_parse(&bad8), "ar: bad octal field") { ok = false; }
  let badg = set_byte(good, 8 + 44, 103);
  if !err_archive_is(ar_parse(&badg), "ar: bad octal field") { ok = false; }
  let blanks = set_range(good, 8 + 40, bytes_of("        "));
  if !err_archive_is(ar_parse(&blanks), "ar: bad octal field") { ok = false; }
  let simple = cat(magic(), mk_plain("m", 0, 0, 0, 420, zeros(0)));
  let pr2 = ar_parse(&simple);
  if !pr2.is_ok {
    ok = false;
  } else {
    let a2: ArArchive = pr2.value;
    if ar_entry_mode(&a2, 0) != 420 { ok = false; }
  }
  return assert(ok, "mode is decoded as ASCII octal");
}

fn t11() -> TestResult {
  let declared10 = cat(magic(), mk_member_ex(plain16("t"), 0, 0, 0, 420, 10, bytes_of("abcde"), 10));
  var ok = err_archive_is(ar_parse(&declared10), "ar: truncated data");
  let header_only = cat(magic(), mk_member_ex(plain16("t"), 0, 0, 0, 420, 10, zeros(0), 10));
  if !err_archive_is(ar_parse(&header_only), "ar: truncated data") { ok = false; }
  let mismatch = cat(magic(), mk_member_ex(bsd16(10), 0, 0, 0, 420, 4, bytes_of("abcd"), 10));
  if !err_archive_is(ar_parse(&mismatch), "ar: size/data mismatch") { ok = false; }
  let exact = cat(magic(), mk_bsd("wxyz", 0, 0, 0, 420, zeros(0)));
  let er = ar_parse(&exact);
  if !er.is_ok {
    ok = false;
  } else {
    let ea: ArArchive = er.value;
    if !str_eq(ar_entry_name(&ea, 0), "wxyz") { ok = false; }
    if ar_entry_size(&ea, 0) != 0 { ok = false; }
  }
  return assert(ok, "truncated data and BSD size/data mismatch are Err");
}

fn t12() -> TestResult {
  let slash = cat(magic(), mk_member(plain16("/"), 0, 0, 0, 420, zeros(0)));
  var ok = err_archive_is(ar_parse(&slash), "ar: unsupported special member");
  let dslash = cat(magic(), mk_member(plain16("//"), 0, 0, 0, 420, zeros(0)));
  if !err_archive_is(ar_parse(&dslash), "ar: unsupported special member") { ok = false; }
  let ref = cat(magic(), mk_member(plain16("/12"), 0, 0, 0, 420, zeros(0)));
  if !err_archive_is(ar_parse(&ref), "ar: unsupported special member") { ok = false; }
  let sym64 = cat(magic(), mk_member(plain16("/SYM64/"), 0, 0, 0, 420, zeros(0)));
  if !err_archive_is(ar_parse(&sym64), "ar: unsupported special member") { ok = false; }
  return assert(ok, "GNU special members are rejected with a clear error");
}

fn t13() -> TestResult {
  let n16 = "0123456789abcdef";
  let n17 = "0123456789abcdefg";
  var long255 = Vec[UInt8].new();
  var i = 0;
  while i < 255 {
    long255.push(107 as UInt8);
    i = i + 1;
  }
  let name255 = Str::from_utf8(long255);
  var long256 = Vec[UInt8].new();
  i = 0;
  while i < 256 {
    long256.push(107 as UInt8);
    i = i + 1;
  }
  let name256 = Str::from_utf8(long256);
  var datas = Vec[Vec[UInt8]].new();
  datas.push(zeros(0));
  let metas = meta4(0, 0, 0, 420);
  var names16 = Vec[Str].new();
  names16.push(n16);
  let r16 = ar_build(&names16, &datas, &metas);
  var ok = r16.is_ok;
  if r16.is_ok {
    let b16: Vec[UInt8] = r16.value;
    if !bytes_equal(slice(b16, 8, 24), bytes_of(n16)) { ok = false; }
    let pr = ar_parse(&b16);
    if !pr.is_ok {
      ok = false;
    } else {
      let ar: ArArchive = pr.value;
      if !str_eq(ar_entry_name(&ar, 0), n16) { ok = false; }
    }
  }
  var names17 = Vec[Str].new();
  names17.push(n17);
  let r17 = ar_build(&names17, &datas, &metas);
  if !r17.is_ok {
    ok = false;
  } else {
    let b17: Vec[UInt8] = r17.value;
    if !bytes_equal(slice(b17, 8, 13), bytes_of("#1/17")) { ok = false; }
    let pr = ar_parse(&b17);
    if !pr.is_ok {
      ok = false;
    } else {
      let ar: ArArchive = pr.value;
      if !str_eq(ar_entry_name(&ar, 0), n17) { ok = false; }
    }
  }
  var names255 = Vec[Str].new();
  names255.push(name255);
  if !ar_build(&names255, &datas, &metas).is_ok { ok = false; }
  var names256 = Vec[Str].new();
  names256.push(name256);
  if !err_bytes_is(ar_build(&names256, &datas, &metas), "ar: name too long") { ok = false; }
  var names0 = Vec[Str].new();
  names0.push("");
  if !err_bytes_is(ar_build(&names0, &datas, &metas), "ar: bad name") { ok = false; }
  let zero_bsd = cat(magic(), mk_member_ex(bsd16(0), 0, 0, 0, 420, 0, zeros(0), 10));
  if !err_archive_is(ar_parse(&zero_bsd), "ar: bad name") { ok = false; }
  let huge_bsd = cat(magic(), mk_member_ex(bsd16(256), 0, 0, 0, 420, 256, zeros(0), 10));
  if !err_archive_is(ar_parse(&huge_bsd), "ar: name too long") { ok = false; }
  return assert(ok, "16/17/255/256-byte names and empty names");
}

fn t14() -> TestResult {
  var names = Vec[Str].new();
  names.push("a");
  var datas = Vec[Vec[UInt8]].new();
  datas.push(zeros(0));
  let d0: Vec[UInt8] = datas[0];
  var out = Vec[UInt8].new();
  var m3 = Vec[Int].new();
  m3.push(0);
  m3.push(0);
  m3.push(0);
  let m5 = meta4(0, 0, 0, 420);
  var m5b = Vec[Int].new();
  m5b.push(0); m5b.push(0); m5b.push(0); m5b.push(0); m5b.push(0);
  var ok = err_unit_is(ar_append(&mut out, "a", &m3, &d0), "ar: metadata length mismatch");
  if !err_unit_is(ar_append(&mut out, "a", &m5b, &d0), "ar: metadata length mismatch") { ok = false; }
  let m_neg = meta4(-1, 0, 0, 420);
  if !err_unit_is(ar_append(&mut out, "a", &m_neg, &d0), "ar: field overflow") { ok = false; }
  let m_uid = meta4(0, 1000000, 0, 420);
  if !err_unit_is(ar_append(&mut out, "a", &m_uid, &d0), "ar: field overflow") { ok = false; }
  let m_gid = meta4(0, 0, 1000000, 420);
  if !err_unit_is(ar_append(&mut out, "a", &m_gid, &d0), "ar: field overflow") { ok = false; }
  let m_mode = meta4(0, 0, 0, 16777216);
  if !err_unit_is(ar_append(&mut out, "a", &m_mode, &d0), "ar: field overflow") { ok = false; }
  let m_time = meta4(1000000000000, 0, 0, 420);
  if !err_unit_is(ar_append(&mut out, "a", &m_time, &d0), "ar: field overflow") { ok = false; }
  if out.len() != 0 { ok = false; }
  let a_ok = ar_append(&mut out, "a", &m5, &d0);
  if !a_ok.is_ok { ok = false; }
  if out.len() != 60 { ok = false; }
  var two_datas = Vec[Vec[UInt8]].new();
  two_datas.push(zeros(0));
  two_datas.push(zeros(0));
  if !err_bytes_is(ar_build(&names, &two_datas, &m5), "ar: entry count mismatch") { ok = false; }
  if !err_bytes_is(ar_build(&names, &datas, &m3), "ar: metadata length mismatch") { ok = false; }
  var no_names = Vec[Str].new();
  var no_datas = Vec[Vec[UInt8]].new();
  var no_metas = Vec[Int].new();
  let empty_build = ar_build(&no_names, &no_datas, &no_metas);
  if !empty_build.is_ok {
    ok = false;
  } else {
    let eb: Vec[UInt8] = empty_build.value;
    if !bytes_equal(eb, magic()) { ok = false; }
  }
  return assert(ok, "build validation errors and untouched buffers");
}

fn t15() -> TestResult {
  let arc = cat(magic(), mk_plain("z", 5, 6, 7, 420, bytes_of("xy")));
  let pr = ar_parse(&arc);
  if !pr.is_ok { return assert(false, "archive must parse"); }
  let ar: ArArchive = pr.value;
  var ok = ar_count(&ar) == 1;
  if !str_eq(ar_entry_name(&ar, -1), "") { ok = false; }
  if !str_eq(ar_entry_name(&ar, 1), "") { ok = false; }
  if ar_entry_size(&ar, -1) != -1 { ok = false; }
  if ar_entry_size(&ar, 1) != -1 { ok = false; }
  if ar_entry_mtime(&ar, 1) != -1 { ok = false; }
  if ar_entry_uid(&ar, -1) != -1 { ok = false; }
  if ar_entry_gid(&ar, 1) != -1 { ok = false; }
  if ar_entry_mode(&ar, -1) != -1 { ok = false; }
  if ar_entry_header_offset(&ar, 1) != -1 { ok = false; }
  if ar_entry_data_offset(&ar, -1) != -1 { ok = false; }
  if !err_bytes_is(ar_entry_data(&arc, &ar, -1), "ar: entry out of range") { ok = false; }
  if !err_bytes_is(ar_entry_data(&arc, &ar, 1), "ar: entry out of range") { ok = false; }
  let cut = slice(arc, 0, 68);
  if !err_bytes_is(ar_entry_data(&cut, &ar, 0), "ar: truncated data") { ok = false; }
  let d = ar_entry_data(&arc, &ar, 0);
  if !d.is_ok {
    ok = false;
  } else {
    if !bytes_equal(d.value, bytes_of("xy")) { ok = false; }
  }
  let zero = cat(magic(), mk_plain("q", 0, 0, 0, 420, zeros(0)));
  let zr = ar_parse(&zero);
  if !zr.is_ok {
    ok = false;
  } else {
    let za: ArArchive = zr.value;
    let zd = ar_entry_data(&zero, &za, 0);
    if !zd.is_ok {
      ok = false;
    } else {
      if zd.value.len() != 0 { ok = false; }
    }
  }
  return assert(ok, "out-of-range accessors and data slicing");
}

fn t16() -> TestResult {
  var arc = ar_global();
  var ok = bytes_equal(arc, magic());
  let m = meta4(3, 4, 5, 420);
  let d = bytes_of("abc");
  let a1 = ar_append(&mut arc, "one", &m, &d);
  let a2 = ar_append(&mut arc, "two", &m, &d);
  if !a1.is_ok || !a2.is_ok { ok = false; }
  if arc.len() != 8 + 64 + 64 { ok = false; }
  let pr = ar_parse(&arc);
  if !pr.is_ok {
    ok = false;
  } else {
    let ar: ArArchive = pr.value;
    if ar_count(&ar) != 2 { ok = false; }
    if !str_eq(ar_entry_name(&ar, 0), "one") { ok = false; }
    if !str_eq(ar_entry_name(&ar, 1), "two") { ok = false; }
  }
  var member_only = Vec[UInt8].new();
  let bad = ar_append(&mut member_only, "one", &m, &d);
  if !bad.is_ok { ok = false; }
  if !err_archive_is(ar_parse(&member_only), "ar: bad global magic") { ok = false; }
  return assert(ok, "ar_global + ar_append compose a valid archive");
}

fn t17() -> TestResult {
  var m = mk_plain("n", 42, 42, 42, 420, zeros(42));
  m = set_range(m, 16, bytes_of("000000000042"));
  m = set_range(m, 28, bytes_of("000042"));
  m = set_range(m, 34, bytes_of("000042"));
  m = set_range(m, 40, bytes_of(" 644    "));
  m = set_range(m, 48, bytes_of("0000000042"));
  let arc = cat(magic(), m);
  let pr = ar_parse(&arc);
  if !pr.is_ok { return assert(false, "numeric-form archive must parse"); }
  let ar: ArArchive = pr.value;
  var ok = ar_entry_mtime(&ar, 0) == 42;
  if ar_entry_uid(&ar, 0) != 42 { ok = false; }
  if ar_entry_gid(&ar, 0) != 42 { ok = false; }
  if ar_entry_mode(&ar, 0) != 420 { ok = false; }
  if ar_entry_size(&ar, 0) != 42 { ok = false; }
  return assert(ok, "leading zeros and spaces are accepted in numeric fields");
}

fn t18() -> TestResult {
  let m1 = mk_plain("a", 0, 0, 0, 420, bytes_of("x"));
  let m2 = mk_plain("b", 0, 0, 0, 420, bytes_of("xy"));
  let m3 = mk_plain("c", 0, 0, 0, 420, bytes_of("xyz"));
  let arc = cat(cat(cat(magic(), m1), m2), m3);
  var ok = arc.len() == 196;
  let pr = ar_parse(&arc);
  if !pr.is_ok { return assert(false, "offset archive must parse"); }
  let ar: ArArchive = pr.value;
  if ar_count(&ar) != 3 { ok = false; }
  if ar_entry_header_offset(&ar, 0) != 8 { ok = false; }
  if ar_entry_header_offset(&ar, 1) != 70 { ok = false; }
  if ar_entry_header_offset(&ar, 2) != 132 { ok = false; }
  if ar_entry_data_offset(&ar, 0) != 68 { ok = false; }
  if ar_entry_data_offset(&ar, 1) != 130 { ok = false; }
  if ar_entry_data_offset(&ar, 2) != 192 { ok = false; }
  return assert(ok, "header and data offsets pin the member layout");
}

fn t19() -> TestResult {
  var names = Vec[Str].new();
  names.push("a b.txt");
  var datas = Vec[Vec[UInt8]].new();
  datas.push(bytes_of("hi"));
  let m = meta4(0, 0, 0, 420);
  let r = ar_build(&names, &datas, &m);
  if !r.is_ok { return assert(false, "build must succeed"); }
  let out: Vec[UInt8] = r.value;
  var ok = bytes_equal(slice(out, 8, 12), bytes_of("#1/7"));
  let pr = ar_parse(&out);
  if !pr.is_ok {
    ok = false;
  } else {
    let ar: ArArchive = pr.value;
    if !str_eq(ar_entry_name(&ar, 0), "a b.txt") { ok = false; }
    if ar_entry_data_offset(&ar, 0) != 8 + 60 + 7 { ok = false; }
    if ar_entry_size(&ar, 0) != 2 { ok = false; }
  }
  var names2 = Vec[Str].new();
  names2.push("dir/");
  let r2 = ar_build(&names2, &datas, &m);
  if !r2.is_ok {
    ok = false;
  } else {
    let b2: Vec[UInt8] = r2.value;
    let pr2 = ar_parse(&b2);
    if !pr2.is_ok {
      ok = false;
    } else {
      let a2: ArArchive = pr2.value;
      if !str_eq(ar_entry_name(&a2, 0), "dir/") { ok = false; }
    }
  }
  return assert(ok, "names with spaces or trailing / use BSD extended encoding");
}

fn t20() -> TestResult {
  let only = magic();
  var ok = only.len() == 8;
  let pr = ar_parse(&only);
  if !pr.is_ok {
    ok = false;
  } else {
    let ar: ArArchive = pr.value;
    if ar_count(&ar) != 0 { ok = false; }
  }
  var no_names = Vec[Str].new();
  var no_datas = Vec[Vec[UInt8]].new();
  var no_metas = Vec[Int].new();
  let br = ar_build(&no_names, &no_datas, &no_metas);
  if !br.is_ok {
    ok = false;
  } else {
    let built: Vec[UInt8] = br.value;
    if !bytes_equal(built, only) { ok = false; }
    let pr2 = ar_parse(&built);
    if !pr2.is_ok {
      ok = false;
    } else {
      let a2: ArArchive = pr2.value;
      if ar_count(&a2) != 0 { ok = false; }
    }
  }
  if !bytes_equal(ar_global(), only) { ok = false; }
  return assert(ok, "a magic-only archive has zero entries");
}

fn main() -> Int {
  io.println("=== xiom.ar conformance tests ===");
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
    io.println("xiom.ar: all tests passed");
  } else {
    io.println("xiom.ar: tests failed");
  }
  return failed;
}
