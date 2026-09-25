// XIOM -- xiom.tzif conformance tests (17 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Port task: prove the pure-XIOM xiom.tzif codec against RFC 8536 and the
// rules pinned in SPEC.md. The two embedded fixtures are the annotated
// example files of RFC 8536 appendices B.1 (version 1 UTC with leap
// seconds, 272 bytes) and B.2 (version 2 Pacific/Honolulu, 329 bytes),
// byte for byte. Synthetic fixtures for the error catalog are assembled in
// this file with independent big-endian writers, so tzif_parse is exercised
// against bytes the test controls.
//
// Str values are never compared with `==` (BUG 17 discipline: `==` on a Str
// read from a Vec lowers to a pointer comparison); error messages go
// through compare.str_compare, and every Vec element read is bound to an
// explicitly typed local.

module tzif_tests
use xiom.io; use xiom.test;
use xiom.tzif;
use xiom.string;
use xiom.string.compare;
use xiom.encoding.hex;

// --------------------------------------------------
//  Byte and assertion helpers (independent of src/tzif.xi)
// --------------------------------------------------

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn hb(hexstr: Str) -> Vec[UInt8] {
  let r = hex.hex_decode(hexstr);
  if !r.is_ok { return Vec[UInt8].new(); }
  let v: Vec[UInt8] = r.value;
  return v;
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

fn push_zeros(v: &mut Vec[UInt8], n: Int) {
  var i = 0;
  while i < n {
    v.push(0 as UInt8);
    i = i + 1;
  }
}

fn push_bytes(out: &mut Vec[UInt8], src: &Vec[UInt8]) {
  var i = 0;
  while i < src.len() {
    out.push(src[i]);
    i = i + 1;
  }
}

// Byte `shift` of `val` in two's complement (0 = least significant byte).
// Arithmetic only, mirroring the module's writer.
fn be_byte(val: Int, shift: Int) -> UInt8 {
  var q = val;
  var k = 0;
  while k < shift {
    var r = q % 256;
    if r < 0 { r = r + 256; }
    q = (q - r) / 256;
    k = k + 1;
  }
  var b = q % 256;
  if b < 0 { b = b + 256; }
  return b as UInt8;
}

fn push_be(out: &mut Vec[UInt8], val: Int, size: Int) {
  var i = size - 1;
  while i >= 0 {
    out.push(be_byte(val, i));
    i = i - 1;
  }
}

// Version byte, 15 reserved bytes, then isutcnt, isstdcnt, leapcnt, timecnt,
// typecnt, charcnt as big-endian u32.
fn head_bytes(ver: Int, timecnt: Int, typecnt: Int, charcnt: Int, leapcnt: Int, isstdcnt: Int, isutcnt: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  v.push(84 as UInt8);
  v.push(90 as UInt8);
  v.push(105 as UInt8);
  v.push(102 as UInt8);
  v.push(ver as UInt8);
  push_zeros(&mut v, 15);
  push_be(&mut v, isutcnt, 4);
  push_be(&mut v, isstdcnt, 4);
  push_be(&mut v, leapcnt, 4);
  push_be(&mut v, timecnt, 4);
  push_be(&mut v, typecnt, 4);
  push_be(&mut v, charcnt, 4);
  return v;
}

// One ttinfo record: utoff 0, isdst 0, desigidx 0.
fn push_zero_type(v: &mut Vec[UInt8]) {
  push_be(v, 0, 4);
  v.push(0 as UInt8);
  v.push(0 as UInt8);
}

// The designation table of a single "UTC" type.
fn push_utc_table(v: &mut Vec<UInt8>) {
  v.push(85 as UInt8);
  v.push(84 as UInt8);
  v.push(67 as UInt8);
  v.push(0 as UInt8);
}

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

fn prefix(v: Vec[UInt8], n: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < n && i < v.len() {
    out.push(v[i]);
    i = i + 1;
  }
  return out;
}

fn err_file_is(r: Result[TzifFile, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return streq(r.error, want);
}

fn err_bytes_is(r: Result[Vec[UInt8], Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return streq(r.error, want);
}

fn err_int_is(r: Result[Int, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return streq(r.error, want);
}

fn err_str_is(r: Result[Str, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return streq(r.error, want);
}

fn int_is(r: Result[Int, Str], want: Int) -> Bool {
  if !r.is_ok { return false; }
  let v: Int = r.value;
  return v == want;
}

fn str_is(r: Result[Str, Str], want: Str) -> Bool {
  if !r.is_ok { return false; }
  let v: Str = r.value;
  return streq(v, want);
}

// Result value or a sentinel no assertion uses.
fn ok_int(r: Result[Int, Str]) -> Int {
  if !r.is_ok { return -999999; }
  let v: Int = r.value;
  return v;
}

// Compare a whole accessor sequence. kind: 0 times, 1 transition types,
// 2 utoffs, 3 isdsts, 4 standard indicators, 5 UT indicators, 6 designation
// indices, 7 leap occurrences, 8 leap corrections.
fn int_seq_ok(f: &TzifFile, want: Vec[Int], kind: Int) -> Bool {
  var i = 0;
  while i < want.len() {
    let w: Int = want[i];
    var got = -999999;
    if kind == 0 { got = ok_int(tzif_transition_time(f, i)); }
    elif kind == 1 { got = ok_int(tzif_transition_type(f, i)); }
    elif kind == 2 { got = ok_int(tzif_type_utoff(f, i)); }
    elif kind == 3 { got = ok_int(tzif_type_isdst(f, i)); }
    elif kind == 4 { got = ok_int(tzif_std_indicator(f, i)); }
    elif kind == 5 { got = ok_int(tzif_ut_indicator(f, i)); }
    elif kind == 6 {
      if i >= f.desig_indices.len() { return false; }
      let dv: Int = f.desig_indices[i];
      got = dv;
    }
    elif kind == 7 { got = ok_int(tzif_leap_occur(f, i)); }
    elif kind == 8 { got = ok_int(tzif_leap_correction(f, i)); }
    if got != w { return false; }
    i = i + 1;
  }
  return true;
}

// Compare the decoded designation of every local time type.
fn designation_seq_ok(f: &TzifFile, want: Vec[Str]) -> Bool {
  var i = 0;
  while i < want.len() {
    let w: Str = want[i];
    if !str_is(tzif_type_designation(f, i), w) { return false; }
    i = i + 1;
  }
  return true;
}

// Compare the decoded designation of every transition.
fn transition_designation_seq_ok(f: &TzifFile, want: Vec[Str]) -> Bool {
  var i = 0;
  while i < want.len() {
    let w: Str = want[i];
    if !str_is(tzif_transition_designation(f, i), w) { return false; }
    i = i + 1;
  }
  return true;
}

// Minimal valid version 1 file: one type (utoff 0, no DST, designation
// "UTC"), no transitions, no leaps, no indicators. 54 bytes.
fn mk_utc_v1() -> Vec[UInt8] {
  var v = head_bytes(0, 0, 1, 4, 0, 0, 0);
  push_zero_type(&mut v);
  push_utc_table(&mut v);
  return v;
}

// Same, with a one-byte standard/wall and UT/local indicator table each
// (isstdcnt = isutcnt = typecnt = 1). 56 bytes.
fn mk_utc_v1_ind(sv: Int, uv: Int) -> Vec<UInt8> {
  var v = head_bytes(0, 0, 1, 4, 0, 1, 1);
  push_zero_type(&mut v);
  push_utc_table(&mut v);
  v.push(sv as UInt8);
  v.push(uv as UInt8);
  return v;
}

// A hand-built version 2 file: one "UTC" type, the version 1 block with no
// transitions, a 64-bit second block with one type-0 transition per entry
// of `times`, no leaps and no indicators, then the footer 0x0A + token +
// 0x0A.
fn mk_v2_fixture(times: Vec[Int], footer_token: Str) -> Vec[UInt8] {
  var v = head_bytes(50, 0, 1, 4, 0, 0, 0);
  push_zero_type(&mut v);
  push_utc_table(&mut v);
  var h2 = head_bytes(50, times.len(), 1, 4, 0, 0, 0);
  push_bytes(&mut v, &h2);
  var i = 0;
  while i < times.len() {
    let tv: Int = times[i];
    push_be(&mut v, tv, 8);
    i = i + 1;
  }
  i = 0;
  while i < times.len() {
    v.push(0 as UInt8);
    i = i + 1;
  }
  push_zero_type(&mut v);
  push_utc_table(&mut v);
  v.push(10 as UInt8);
  var k = 0;
  while k < footer_token.len() {
    v.push(string.byte_at(footer_token, k));
    k = k + 1;
  }
  v.push(10 as UInt8);
  return v;
}

// A one-type, one-transition version 1 source for tzif_build_v1 error
// probes.
fn build_probe(version: Int, time0: Int, ti0: Int, utoff0: Int, isdst0: Int, desig0: Str, sv0: Int, uv0: Int) -> Result[Vec[UInt8], Str] {
  var times = Vec[Int].new();
  times.push(time0);
  var tis = Vec[Int].new();
  tis.push(ti0);
  var uos = Vec[Int].new();
  uos.push(utoff0);
  var ids = Vec[Int].new();
  ids.push(isdst0);
  var dis = Vec[Int].new();
  dis.push(0);
  var dss = Vec[Str].new();
  dss.push(desig0);
  var los = Vec[Int].new();
  var lcs = Vec[Int].new();
  var s1 = Vec[Int].new();
  s1.push(sv0);
  var s2 = Vec[Int].new();
  s2.push(uv0);
  let f = TzifFile{
    version: version;
    timecnt: times.len();
    typecnt: 1;
    leapcnt: 0;
    charcnt: 4;
    isstdcnt: 1;
    isutcnt: 1;
    times: times;
    type_indices: tis;
    utoffs: uos;
    isdsts: ids;
    desig_indices: dis;
    designations: dss;
    leap_occurs: los;
    leap_corrections: lcs;
    isstd: s1;
    isut: s2;
    footer: "";
  };
  return tzif_build_v1(&f);
}

// A source whose vector lengths are deliberately inconsistent. which:
// 1 transition vectors, 2 leap vectors, 3 ttinfo vectors,
// 4 standard indicators, 5 UT indicators, 6 all valid.
fn build_probe_mismatch(which: Int) -> Result[Vec[UInt8], Str] {
  var times = Vec[Int].new();
  var tis = Vec[Int].new();
  var uos = Vec[Int].new();
  var ids = Vec[Int].new();
  var dis = Vec[Int].new();
  var dss = Vec[Str].new();
  var los = Vec[Int].new();
  var lcs = Vec[Int].new();
  var s1 = Vec[Int].new();
  var s2 = Vec[Int].new();
  uos.push(0);
  ids.push(0);
  dis.push(0);
  dss.push("EST");
  if which == 1 {
    times.push(0);
  } elif which == 2 {
    los.push(0);
  } elif which == 3 {
    dss.push("EDT");
  } elif which == 4 {
    s1.push(0);
    s1.push(0);
  } elif which == 5 {
    s2.push(0);
    s2.push(0);
  } elif which == 6 {
    s1.push(0);
    s2.push(0);
  }
  let f = TzifFile{
    version: 1;
    timecnt: times.len();
    typecnt: 1;
    leapcnt: los.len();
    charcnt: 4;
    isstdcnt: s1.len();
    isutcnt: s2.len();
    times: times;
    type_indices: tis;
    utoffs: uos;
    isdsts: ids;
    desig_indices: dis;
    designations: dss;
    leap_occurs: los;
    leap_corrections: lcs;
    isstd: s1;
    isut: s2;
    footer: "";
  };
  return tzif_build_v1(&f);
}

// RFC 8536 appendix B.1: version 1 file for UTC with 27 leap-second
// records, 272 bytes.
fn rfc_b1() -> Vec[UInt8] {
  return hb("545a69660000000000000000000000000000000000000001000000010000001b0000000000000001000000040000000000005554430004b258000000000105a4ec010000000207861f820000000309675303000000040b488684000000050d2b0b85000000060f0c3f060000000710ed72870000000812cea60800000009159fca890000000a1780fe0a0000000b1962318b0000000c1d25ea0c0000000d21dae50d0000000e259e9d8e0000000f277fd10f000000102a50f590000000112c322911000000122e135c920000001330e724130000001433b8489400000015368c10150000001643b71b9600000017495c0797000000184fef93180000001955932d990000001a5868469a0000001b0000");
}

// RFC 8536 appendix B.2: version 2 file for Pacific/Honolulu, 329 bytes.
fn rfc_b2() -> Vec[UInt8] {
  return hb("545a69663200000000000000000000000000000000000006000000060000000000000007000000060000001480000000bb054348bb217158cb893dc8d223f470d2614938d58d734801020103040105ffff6c020000ffff6c580004ffff7a680108ffff7a68010cffff7a680110ffff736000044c4d540048535400484454004857540048505400000000000100000000000100545a696632000000000000000000000000000000000000060000000600000000000000070000000600000014ffffffff74e070beffffffffbb054348ffffffffbb217158ffffffffcb893dc8ffffffffd223f470ffffffffd2614938ffffffffd58d734801020103040105ffff6c020000ffff6c580004ffff7a680108ffff7a68010cffff7a680110ffff736000044c4d5400485354004844540048575400485054000000000001000000000001000a48535431300a");
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  let b1 = rfc_b1();
  var ok = b1.len() == 272;
  let r = tzif_parse(&b1);
  if !r.is_ok { return assert(false, "RFC B.1 must parse"); }
  let f: TzifFile = r.value;
  if tzif_version(&f) != 1 { ok = false; }
  if tzif_timecnt(&f) != 0 { ok = false; }
  if tzif_typecnt(&f) != 1 { ok = false; }
  if tzif_leapcnt(&f) != 27 { ok = false; }
  if tzif_charcnt(&f) != 4 { ok = false; }
  if tzif_isstdcnt(&f) != 1 { ok = false; }
  if tzif_isutcnt(&f) != 1 { ok = false; }
  if !int_is(tzif_type_utoff(&f, 0), 0) { ok = false; }
  if !int_is(tzif_type_isdst(&f, 0), 0) { ok = false; }
  if !str_is(tzif_type_designation(&f, 0), "UTC") { ok = false; }
  if !int_is(tzif_leap_occur(&f, 0), 78796800) { ok = false; }
  if !int_is(tzif_leap_correction(&f, 0), 1) { ok = false; }
  if !int_is(tzif_leap_occur(&f, 26), 1483228826) { ok = false; }
  if !int_is(tzif_leap_correction(&f, 26), 27) { ok = false; }
  if !int_is(tzif_std_indicator(&f, 0), 0) { ok = false; }
  if !int_is(tzif_ut_indicator(&f, 0), 0) { ok = false; }
  if !streq(tzif_footer(&f), "") { ok = false; }
  return assert(ok, "RFC 8536 B.1 v1 UTC parses with 27 leap records");
}

fn t2() -> TestResult {
  let b1 = rfc_b1();
  let r = tzif_parse(&b1);
  if !r.is_ok { return assert(false, "RFC B.1 must parse"); }
  let f: TzifFile = r.value;
  let br = tzif_build_v1(&f);
  if !br.is_ok { return assert(false, "B.1 rebuild must succeed"); }
  let built: Vec[UInt8] = br.value;
  var ok = built.len() == 272;
  if !bytes_equal(built, b1) { ok = false; }
  return assert(ok, "v1 round-trip: parse then build reproduces RFC B.1 exactly");
}

fn t3() -> TestResult {
  let b2 = rfc_b2();
  var ok = b2.len() == 329;
  let r = tzif_parse(&b2);
  if !r.is_ok { return assert(false, "RFC B.2 must parse"); }
  let f: TzifFile = r.value;
  if tzif_version(&f) != 2 { ok = false; }
  if tzif_timecnt(&f) != 7 { ok = false; }
  if tzif_typecnt(&f) != 6 { ok = false; }
  if tzif_leapcnt(&f) != 0 { ok = false; }
  if tzif_charcnt(&f) != 20 { ok = false; }
  if tzif_isstdcnt(&f) != 6 { ok = false; }
  if tzif_isutcnt(&f) != 6 { ok = false; }
  var wt = Vec[Int].new();
  wt.push(-2334101314);
  wt.push(-1157283000);
  wt.push(-1155436200);
  wt.push(-880198200);
  wt.push(-769395600);
  wt.push(-765376200);
  wt.push(-712150200);
  if !int_seq_ok(&f, wt, 0) { ok = false; }
  var wti = Vec[Int].new();
  wti.push(1);
  wti.push(2);
  wti.push(1);
  wti.push(3);
  wti.push(4);
  wti.push(1);
  wti.push(5);
  if !int_seq_ok(&f, wti, 1) { ok = false; }
  var wu = Vec[Int].new();
  wu.push(-37886);
  wu.push(-37800);
  wu.push(-34200);
  wu.push(-34200);
  wu.push(-34200);
  wu.push(-36000);
  if !int_seq_ok(&f, wu, 2) { ok = false; }
  var wd = Vec[Int].new();
  wd.push(0);
  wd.push(0);
  wd.push(1);
  wd.push(1);
  wd.push(1);
  wd.push(0);
  if !int_seq_ok(&f, wd, 3) { ok = false; }
  var wdname = Vec[Str].new();
  wdname.push("LMT");
  wdname.push("HST");
  wdname.push("HDT");
  wdname.push("HWT");
  wdname.push("HPT");
  wdname.push("HST");
  if !designation_seq_ok(&f, wdname) { ok = false; }
  var wtdname = Vec[Str].new();
  wtdname.push("HST");
  wtdname.push("HDT");
  wtdname.push("HST");
  wtdname.push("HWT");
  wtdname.push("HPT");
  wtdname.push("HST");
  wtdname.push("HST");
  if !transition_designation_seq_ok(&f, wtdname) { ok = false; }
  var ws = Vec[Int].new();
  ws.push(0);
  ws.push(0);
  ws.push(0);
  ws.push(0);
  ws.push(1);
  ws.push(0);
  if !int_seq_ok(&f, ws, 4) { ok = false; }
  if !int_seq_ok(&f, ws, 5) { ok = false; }
  if !streq(tzif_footer(&f), "HST10") { ok = false; }
  return assert(ok, "RFC 8536 B.2 v2 Honolulu exposes the 64-bit block and footer");
}

fn t4() -> TestResult {
  let b2 = rfc_b2();
  // A corrupt isdst byte inside the skipped version 1 block must not matter.
  let skip_bad = set_byte(b2, 83, 2);
  let r1 = tzif_parse(&skip_bad);
  var ok = r1.is_ok;
  if ok {
    let f1: TzifFile = r1.value;
    if !int_is(tzif_transition_time(&f1, 0), -2334101314) { ok = false; }
    if tzif_timecnt(&f1) != 7 { ok = false; }
  }
  // The same corruption in the parsed second block is an error.
  let real_bad = set_byte(b2, 258, 2);
  if !err_file_is(tzif_parse(&real_bad), "tzif: invalid DST flag") { ok = false; }
  return assert(ok, "v2 skips the v1 block but validates the 64-bit block");
}

fn t5() -> TestResult {
  var ok = true;
  // -9223372036854775807 is 0x8000000000000001: the most negative value
  // that can be negated in Int.
  var one = Vec[Int].new();
  one.push(-9223372036854775807);
  let good = mk_v2_fixture(one, "UTC0");
  let r1 = tzif_parse(&good);
  if !r1.is_ok { ok = false; } else {
    let f1: TzifFile = r1.value;
    if !int_is(tzif_transition_time(&f1, 0), -9223372036854775807) { ok = false; }
    if !streq(tzif_footer(&f1), "UTC0") { ok = false; }
  }
  // 0x8000000000000000 (INT64_MIN) cannot be negated in Int.
  var zero = Vec[Int].new();
  zero.push(0);
  let bad = mk_v2_fixture(zero, "");
  let patched = set_byte(bad, 98, 128);
  if !err_file_is(tzif_parse(&patched), "tzif: 64-bit value out of Int range") { ok = false; }
  return assert(ok, "64-bit transition times handle the full Int range, INT64_MIN rejected");
}

fn t6() -> TestResult {
  let b1 = rfc_b1();
  let b2 = rfc_b2();
  var ok = err_file_is(tzif_parse(&set_byte(b1, 0, 88)), "tzif: bad magic");
  if !err_file_is(tzif_parse(&set_byte(b1, 3, 88)), "tzif: bad magic") { ok = false; }
  if !err_file_is(tzif_parse(&set_byte(b1, 4, 49)), "tzif: unsupported version") { ok = false; }
  if !err_file_is(tzif_parse(&set_byte(b2, 147, 88)), "tzif: bad second header magic") { ok = false; }
  if !err_file_is(tzif_parse(&set_byte(b2, 151, 0)), "tzif: second header version mismatch") { ok = false; }
  if !err_file_is(tzif_parse(&set_byte(b2, 151, 51)), "tzif: second header version mismatch") { ok = false; }
  return assert(ok, "magic and version validation, including the second header");
}

fn t7() -> TestResult {
  let b1 = rfc_b1();
  let b2 = rfc_b2();
  var ok = err_file_is(tzif_parse(&prefix(b1, 43)), "tzif: truncated header");
  if !err_file_is(tzif_parse(&prefix(b2, 150)), "tzif: truncated second header") { ok = false; }
  if !err_file_is(tzif_parse(&prefix(b1, 44)), "tzif: data block overruns buffer") { ok = false; }
  if !err_file_is(tzif_parse(&prefix(b1, 271)), "tzif: data block overruns buffer") { ok = false; }
  return assert(ok, "truncated headers and blocks are the documented errors");
}

fn t8() -> TestResult {
  var ok = err_file_is(tzif_parse(&head_bytes(0, 0, 0, 4, 0, 0, 0)), "tzif: zero time type count");
  if !err_file_is(tzif_parse(&head_bytes(0, 0, 1, 0, 0, 0, 0)), "tzif: zero designation count") { ok = false; }
  return assert(ok, "typecnt and charcnt must be nonzero");
}

fn t9() -> TestResult {
  var ok = err_file_is(tzif_parse(&head_bytes(0, 0, 1, 4, 0, 2, 0)), "tzif: standard indicator count mismatch");
  if !err_file_is(tzif_parse(&head_bytes(0, 0, 1, 4, 0, 0, 2)), "tzif: UT indicator count mismatch") { ok = false; }
  return assert(ok, "indicator counts must be 0 or typecnt");
}

fn t10() -> TestResult {
  var v = head_bytes(0, 1, 1, 4, 0, 0, 0);
  push_be(&mut v, 123, 4);
  v.push(1 as UInt8);
  push_zero_type(&mut v);
  push_utc_table(&mut v);
  var ok = err_file_is(tzif_parse(&v), "tzif: transition type index out of range");
  var good = head_bytes(0, 1, 1, 4, 0, 0, 0);
  push_be(&mut good, 123, 4);
  good.push(0 as UInt8);
  push_zero_type(&mut good);
  push_utc_table(&mut good);
  let rg = tzif_parse(&good);
  if !rg.is_ok { ok = false; } else {
    let f: TzifFile = rg.value;
    if !int_is(tzif_transition_time(&f, 0), 123) { ok = false; }
    if !int_is(tzif_transition_type(&f, 0), 0) { ok = false; }
  }
  return assert(ok, "transition type indices are bounded by typecnt");
}

fn t11() -> TestResult {
  var ok = err_file_is(tzif_parse(&set_byte(mk_utc_v1(), 49, 4)), "tzif: designation index out of range");
  if !err_file_is(tzif_parse(&set_byte(mk_utc_v1(), 53, 65)), "tzif: unterminated designation") { ok = false; }
  var e = head_bytes(0, 0, 1, 1, 0, 0, 0);
  push_zero_type(&mut e);
  e.push(0 as UInt8);
  let re = tzif_parse(&e);
  if !re.is_ok { ok = false; } else {
    let fe: TzifFile = re.value;
    if !str_is(tzif_type_designation(&fe, 0), "") { ok = false; }
  }
  return assert(ok, "designation indices bound and NUL-terminated; empty designation allowed");
}

fn t12() -> TestResult {
  var ok = err_file_is(tzif_parse(&set_byte(mk_utc_v1(), 44, 128)), "tzif: invalid UT offset");
  if !err_file_is(tzif_parse(&set_byte(mk_utc_v1(), 48, 2)), "tzif: invalid DST flag") { ok = false; }
  if !err_file_is(tzif_parse(&mk_utc_v1_ind(2, 0)), "tzif: invalid indicator value") { ok = false; }
  if !err_file_is(tzif_parse(&mk_utc_v1_ind(0, 2)), "tzif: invalid indicator value") { ok = false; }
  if !err_file_is(tzif_parse(&mk_utc_v1_ind(0, 1)), "tzif: UT indicator without standard indicator") { ok = false; }
  let rv = tzif_parse(&mk_utc_v1_ind(1, 1));
  if !rv.is_ok { ok = false; } else {
    let fv: TzifFile = rv.value;
    if !int_is(tzif_std_indicator(&fv, 0), 1) { ok = false; }
    if !int_is(tzif_ut_indicator(&fv, 0), 1) { ok = false; }
  }
  return assert(ok, "utoff, isdst and indicator value validation with one valid case");
}

fn t13() -> TestResult {
  let b1 = rfc_b1();
  let b2 = rfc_b2();
  var ok = err_file_is(tzif_parse(&append_byte(b1, 0)), "tzif: trailing bytes");
  if !err_file_is(tzif_parse(&prefix(b2, 328)), "tzif: missing footer") { ok = false; }
  if !err_file_is(tzif_parse(&set_byte(b2, 322, 65)), "tzif: missing footer") { ok = false; }
  if !err_file_is(tzif_parse(&set_byte(b2, 323, 0)), "tzif: NUL in footer") { ok = false; }
  if !err_file_is(tzif_parse(&append_byte(b2, 0)), "tzif: trailing bytes") { ok = false; }
  return assert(ok, "v1 rejects trailing bytes; v2 requires a NUL-free delimited footer");
}

fn t14() -> TestResult {
  let b2 = rfc_b2();
  let r = tzif_parse(&b2);
  if !r.is_ok { return assert(false, "RFC B.2 must parse"); }
  let f: TzifFile = r.value;
  var ok = err_int_is(tzif_transition_time(&f, -1), "tzif: index out of range");
  if !err_int_is(tzif_transition_time(&f, 7), "tzif: index out of range") { ok = false; }
  if !err_int_is(tzif_transition_type(&f, 7), "tzif: index out of range") { ok = false; }
  if !err_int_is(tzif_type_utoff(&f, 6), "tzif: index out of range") { ok = false; }
  if !err_int_is(tzif_type_isdst(&f, -1), "tzif: index out of range") { ok = false; }
  if !err_str_is(tzif_type_designation(&f, 6), "tzif: index out of range") { ok = false; }
  if !err_str_is(tzif_transition_designation(&f, 7), "tzif: index out of range") { ok = false; }
  if !err_int_is(tzif_leap_occur(&f, 0), "tzif: index out of range") { ok = false; }
  if !err_int_is(tzif_leap_correction(&f, -1), "tzif: index out of range") { ok = false; }
  let u = mk_utc_v1();
  let ru = tzif_parse(&u);
  if !ru.is_ok { ok = false; } else {
    let fu: TzifFile = ru.value;
    if !err_int_is(tzif_std_indicator(&fu, 0), "tzif: no standard indicator table") { ok = false; }
    if !err_int_is(tzif_ut_indicator(&fu, 0), "tzif: no UT indicator table") { ok = false; }
  }
  return assert(ok, "element accessors bound-check and report absent indicator tables");
}

fn t15() -> TestResult {
  var times = Vec[Int].new();
  times.push(-2147483648);
  times.push(1000000000);
  var tis = Vec[Int].new();
  tis.push(1);
  tis.push(0);
  var uos = Vec[Int].new();
  uos.push(-18000);
  uos.push(3600);
  var ids = Vec[Int].new();
  ids.push(0);
  ids.push(1);
  var dis = Vec[Int].new();
  dis.push(0);
  dis.push(6);
  var dss = Vec[Str].new();
  dss.push("EST");
  dss.push("EDT");
  var los = Vec[Int].new();
  los.push(78796800);
  var lcs = Vec[Int].new();
  lcs.push(1);
  var s1 = Vec[Int].new();
  s1.push(1);
  s1.push(0);
  var s2 = Vec[Int].new();
  s2.push(0);
  s2.push(0);
  let f = TzifFile{
    version: 1;
    timecnt: 2;
    typecnt: 2;
    leapcnt: 1;
    charcnt: 8;
    isstdcnt: 2;
    isutcnt: 2;
    times: times;
    type_indices: tis;
    utoffs: uos;
    isdsts: ids;
    desig_indices: dis;
    designations: dss;
    leap_occurs: los;
    leap_corrections: lcs;
    isstd: s1;
    isut: s2;
    footer: "";
  };
  let br = tzif_build_v1(&f);
  if !br.is_ok { return assert(false, "v1 build must succeed"); }
  let built: Vec<UInt8> = br.value;
  let want = hb("545a696600000000000000000000000000000000000000020000000200000001000000020000000200000008800000003b9aca000100ffffb9b0000000000e100104455354004544540004b258000000000101000000");
  var ok = bytes_equal(built, want);
  if built.len() != want.len() { ok = false; }
  let pr = tzif_parse(&built);
  if !pr.is_ok { ok = false; } else {
    let fp: TzifFile = pr.value;
    if tzif_version(&fp) != 1 { ok = false; }
    if tzif_timecnt(&fp) != 2 { ok = false; }
    if !int_is(tzif_transition_time(&fp, 0), -2147483648) { ok = false; }
    if !int_is(tzif_transition_time(&fp, 1), 1000000000) { ok = false; }
    if !int_is(tzif_transition_type(&fp, 0), 1) { ok = false; }
    if !int_is(tzif_type_utoff(&fp, 1), 3600) { ok = false; }
    if !int_is(tzif_type_isdst(&fp, 1), 1) { ok = false; }
    if !str_is(tzif_type_designation(&fp, 0), "EST") { ok = false; }
    if !str_is(tzif_transition_designation(&fp, 1), "EST") { ok = false; }
    if !int_is(tzif_leap_occur(&fp, 0), 78796800) { ok = false; }
    if !int_is(tzif_leap_correction(&fp, 0), 1) { ok = false; }
    if !int_is(tzif_std_indicator(&fp, 0), 1) { ok = false; }
    if !int_is(tzif_std_indicator(&fp, 1), 0) { ok = false; }
    if !int_is(tzif_ut_indicator(&fp, 0), 0) { ok = false; }
    if !streq(tzif_footer(&fp), "") { ok = false; }
  }
  return assert(ok, "v1 builder writes pinned big-endian bytes with a canonical designation table");
}

fn t16() -> TestResult {
  var ok = err_bytes_is(build_probe(2, 0, 0, 0, 0, "EST", 0, 0), "tzif: builder writes version 1 only");
  if !err_bytes_is(build_probe(1, 2147483648, 0, 0, 0, "EST", 0, 0), "tzif: transition time out of range") { ok = false; }
  if !err_bytes_is(build_probe(1, -2147483649, 0, 0, 0, "EST", 0, 0), "tzif: transition time out of range") { ok = false; }
  if !err_bytes_is(build_probe(1, 0, 1, 0, 0, "EST", 0, 0), "tzif: transition type index out of range") { ok = false; }
  if !err_bytes_is(build_probe(1, 0, 0, -2147483648, 0, "EST", 0, 0), "tzif: invalid UT offset") { ok = false; }
  if !err_bytes_is(build_probe(1, 0, 0, 2147483648, 0, "EST", 0, 0), "tzif: UT offset out of range") { ok = false; }
  if !err_bytes_is(build_probe(1, 0, 0, 0, 2, "EST", 0, 0), "tzif: invalid DST flag") { ok = false; }
  if !err_bytes_is(build_probe(1, 0, 0, 0, 0, "EST", 2, 0), "tzif: invalid indicator value") { ok = false; }
  if !err_bytes_is(build_probe(1, 0, 0, 0, 0, "EST", 0, 1), "tzif: UT indicator without standard indicator") { ok = false; }
  if !err_bytes_is(build_probe_mismatch(1), "tzif: transition vector length mismatch") { ok = false; }
  if !err_bytes_is(build_probe_mismatch(2), "tzif: leap vector length mismatch") { ok = false; }
  if !err_bytes_is(build_probe_mismatch(3), "tzif: ttinfo vector length mismatch") { ok = false; }
  if !err_bytes_is(build_probe_mismatch(4), "tzif: standard indicator count mismatch") { ok = false; }
  if !err_bytes_is(build_probe_mismatch(5), "tzif: UT indicator count mismatch") { ok = false; }
  let good = build_probe_mismatch(6);
  if !good.is_ok { ok = false; } else {
    let gb: Vec[UInt8] = good.value;
    if gb.len() != 56 { ok = false; }
  }
  return assert(ok, "v1 builder rejects out-of-range fields and inconsistent vectors");
}

fn t17() -> TestResult {
  var times = Vec[Int].new();
  times.push(5000000000);
  times.push(-5000000000);
  let v = mk_v2_fixture(times, "");
  let r = tzif_parse(&v);
  if !r.is_ok { return assert(false, "hand-built v2 must parse"); }
  let f: TzifFile = r.value;
  var ok = tzif_version(&f) == 2;
  if tzif_timecnt(&f) != 2 { ok = false; }
  if !int_is(tzif_transition_time(&f, 0), 5000000000) { ok = false; }
  if !int_is(tzif_transition_time(&f, 1), -5000000000) { ok = false; }
  if !int_is(tzif_type_utoff(&f, 0), 0) { ok = false; }
  if !str_is(tzif_type_designation(&f, 0), "UTC") { ok = false; }
  if !str_is(tzif_transition_designation(&f, 1), "UTC") { ok = false; }
  if !streq(tzif_footer(&f), "") { ok = false; }
  return assert(ok, "hand-built v2 round-trip: >32-bit times and empty footer");
}

fn main() -> Int {
  io.println("=== xiom.tzif conformance tests ===");
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
    io.println("xiom.tzif: all tests passed");
  } else {
    io.println("xiom.tzif: tests failed");
  }
  return failed;
}
