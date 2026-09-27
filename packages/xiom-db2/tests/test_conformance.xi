// XIOM -- xiom.db2 conformance tests (22 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Covers the documented API: DSS frame headers and the format matrix, the
// multi-frame message assembler (including same-correlation chains), the
// DDM short and extended length forms, the codepoint/name/category tables
// and the mandate-vs-verified deltas, the ASCII-vs-opaque text decoders,
// SECMEC lists, TYPDEFNAM byte orders, FDODSC/FDODTA/SQLDTA rows with null
// indicators, and SQLCARD in both platform byte orders. Every buffer is
// synthesized in-test from hex literals (xiom.encoding.hex) and the
// package's own readers; no external data files, no network.
//
// Str payloads are compared with str_compare (BUG 17 discipline: `==` on
// Str values read from a Vec lowers to a pointer comparison).

module db2_tests
use xiom.io; use xiom.test;
use xiom.string; use xiom.string.compare;
use xiom.encoding.hex;
use xiom.db2;

// --------------------------------------------------
//  Test helpers
// --------------------------------------------------

// Bytes for a hex string ("" decodes to an empty vector).
fn hb(hexstr: Str) -> Vec[UInt8] {
  let r = hex.hex_decode(hexstr);
  match r {
    Ok(v) => { return v; },
    Err(_) => {},
  }
  return Vec[UInt8].new();
}

fn bytes_equal(a: Vec[UInt8], b: Vec[UInt8]) -> Bool {
  if a.len() != b.len() {
    return false;
  }
  var i = 0;
  while i < a.len() {
    let x: UInt8 = a[i];
    let y: UInt8 = b[i];
    if ((x as Int) & 0xFF) != ((y as Int) & 0xFF) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// True when the byte vector equals the hex string.
fn bytes_is(a: Vec[UInt8], want: Str) -> Bool {
  return bytes_equal(a, hb(want));
}

// True when both strings are byte-identical (BUG 17 discipline).
fn str_is(s: Str, want: Str) -> Bool {
  return str_compare(s, want) == 0;
}

fn err_is_f(r: Result[Db2Frame, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_compare(r.error, want) == 0;
}

fn err_is_d(r: Result[Db2Ddm, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_compare(r.error, want) == 0;
}

fn err_is_dl(r: Result[Db2DdmList, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_compare(r.error, want) == 0;
}

fn err_is_m(r: Result[Db2Messages, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_compare(r.error, want) == 0;
}

fn err_is_t(r: Result[Db2Text, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_compare(r.error, want) == 0;
}

fn err_is_v(r: Result[Vec[Int], Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_compare(r.error, want) == 0;
}

fn err_is_dsc(r: Result[Db2Descriptor, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_compare(r.error, want) == 0;
}

fn err_is_row(r: Result[Db2DtaRow, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_compare(r.error, want) == 0;
}

fn err_is_card(r: Result[Db2SqlCard, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_compare(r.error, want) == 0;
}

fn err_is_i(r: Result[Int, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_compare(r.error, want) == 0;
}

fn err_is_b(r: Result[Vec[UInt8], Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_compare(r.error, want) == 0;
}

// --------------------------------------------------
//  Buffer builders
// --------------------------------------------------

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

fn be16(v: Int) -> Vec[UInt8] {
  var x = v % 65536;
  if x < 0 {
    x = x + 65536;
  }
  var out = Vec[UInt8].new();
  out.push(((x / 256) % 256) as UInt8);
  out.push((x % 256) as UInt8);
  return out;
}

fn be32(v: Int) -> Vec[UInt8] {
  var x = v % 4294967296;
  if x < 0 {
    x = x + 4294967296;
  }
  var out = Vec[UInt8].new();
  out.push(((x / 16777216) % 256) as UInt8);
  out.push(((x / 65536) % 256) as UInt8);
  out.push(((x / 256) % 256) as UInt8);
  out.push((x % 256) as UInt8);
  return out;
}

fn le32(v: Int) -> Vec[UInt8] {
  var x = v % 4294967296;
  if x < 0 {
    x = x + 4294967296;
  }
  var out = Vec[UInt8].new();
  out.push((x % 256) as UInt8);
  out.push(((x / 256) % 256) as UInt8);
  out.push(((x / 65536) % 256) as UInt8);
  out.push(((x / 16777216) % 256) as UInt8);
  return out;
}

fn rep_byte(b: Int, n: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < n {
    out.push((b % 256) as UInt8);
    i = i + 1;
  }
  return out;
}

// Every UTF-8 byte of an ASCII string.
fn sbytes(s: Str) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  let n: Int = string.str_len(s);
  while i < n {
    out.push(string.byte_at(s, i));
    i = i + 1;
  }
  return out;
}

// The first `n` bytes of `v` (n must fit).
fn take_n(v: Vec[UInt8], n: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < n {
    out.push(v[i]);
    i = i + 1;
  }
  return out;
}

// A DSS frame with an explicit magic byte (for corruption tests).
fn frame_raw(magic: Int, fmt: Int, corr: Int, payload: Vec[UInt8]) -> Vec[UInt8] {
  var out = be16(6 + payload.len());
  out.push((magic % 256) as UInt8);
  out.push((fmt % 256) as UInt8);
  out = cat(out, be16(corr));
  out = cat(out, payload);
  return out;
}

// A well-formed DSS frame (magic 0xD0).
fn frame(fmt: Int, corr: Int, payload: Vec[UInt8]) -> Vec[UInt8] {
  return frame_raw(208, fmt, corr, payload);
}

// A DDM in the 2-byte length form.
fn ddm(code: Int, payload: Vec[UInt8]) -> Vec[UInt8] {
  var out = be16(4 + payload.len());
  out = cat(out, be16(code));
  out = cat(out, payload);
  return out;
}

// A DDM in the extended 4-byte length form (0x8008 + u32 total).
fn ddm_long(code: Int, payload: Vec[UInt8]) -> Vec[UInt8] {
  var out = be16(32776);
  out = cat(out, be16(code));
  out = cat(out, be32(8 + payload.len()));
  out = cat(out, payload);
  return out;
}

// The VCM wire form: 2-byte big-endian length then the ASCII bytes.
fn vcm(s: Str) -> Vec[UInt8] {
  return cat(be16(string.str_len(s)), sbytes(s));
}

// A descriptor with three columns: INT(4), VARCHAR(variable), BIGINT(8).
fn desc3() -> Vec[UInt8] {
  var out = hb("0C76D0");
  out = cat(out, hb("030004"));
  out = cat(out, hb("393FFF"));
  out = cat(out, hb("170008"));
  out = cat(out, hb("0671E4D00001"));
  return out;
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  var ok = true;
  if db2_dss_magic() != 208 { ok = false; }
  if db2_dss_header_len() != 6 { ok = false; }
  if db2_dss_max_len() != 32767 { ok = false; }
  if db2_dss_len_continuation_bit() != 32768 { ok = false; }
  if db2_dss_flag_chained() != 64 { ok = false; }
  if db2_dss_flag_continue_on_error() != 32 { ok = false; }
  if db2_dss_flag_same_correlation() != 16 { ok = false; }
  if db2_dss_type_mask() != 15 { ok = false; }
  if !str_is(db2_dss_type_name(db2_dss_type_request()), "REQUEST") { ok = false; }
  if !str_is(db2_dss_type_name(db2_dss_type_reply()), "REPLY") { ok = false; }
  if !str_is(db2_dss_type_name(db2_dss_type_object()), "OBJECT") { ok = false; }
  if !str_is(db2_dss_type_name(db2_dss_type_communications()), "COMMUNICATION") { ok = false; }
  if !str_is(db2_dss_type_name(db2_dss_type_request_no_reply()), "REQUEST_NOREPLY") { ok = false; }
  if !str_is(db2_dss_type_name(9), "UNKNOWN") { ok = false; }
  if !db2_dss_type_known(1) || db2_dss_type_known(0) { ok = false; }
  if !str_is(db2_protocol_name(), "DRDA") { ok = false; }
  return assert(ok, "DSS constants, types and protocol metadata");
}

fn t2() -> TestResult {
  var ok = true;
  let payload: Vec[UInt8] = hb("0B00FF");
  let data: Vec[UInt8] = frame(65, 7, payload);
  var r = db2_reader_new(data);
  let fr = db2_frame_parse(&mut r);
  if !fr.is_ok { ok = false; } else {
    let f: Db2Frame = fr.value;
    if f.length != 9 { ok = false; }
    if f.format != 65 { ok = false; }
    if f.dss_type != 1 { ok = false; }
    if !f.chained { ok = false; }
    if f.continue_on_error { ok = false; }
    if f.same_correlation { ok = false; }
    if f.correlation != 7 { ok = false; }
    let fp: Vec[UInt8] = f.payload;
    if !bytes_is(fp, "0B00FF") { ok = false; }
    if db2_frame_consumed(&f) != 9 { ok = false; }
  }
  if db2_reader_pos(&r) != 9 { ok = false; }
  if db2_reader_remaining(&r) != 0 { ok = false; }
  return assert(ok, "single DSS frame parse, payload, consumed and cursor");
}

fn t3() -> TestResult {
  var fmts = Vec[Int].new();
  fmts.push(1);
  fmts.push(81);
  fmts.push(67);
  fmts.push(2);
  fmts.push(5);
  var types = Vec[Int].new();
  types.push(1);
  types.push(1);
  types.push(3);
  types.push(2);
  types.push(5);
  var chaineds = Vec[Bool].new();
  chaineds.push(false);
  chaineds.push(true);
  chaineds.push(true);
  chaineds.push(false);
  chaineds.push(false);
  var sames = Vec[Bool].new();
  sames.push(false);
  sames.push(true);
  sames.push(false);
  sames.push(false);
  sames.push(false);
  var data = Vec[UInt8].new();
  data = cat(data, frame(1, 1, hb("41")));
  data = cat(data, frame(81, 2, hb("42")));
  data = cat(data, frame(67, 3, hb("43")));
  data = cat(data, frame(2, 4, hb("44")));
  data = cat(data, frame(5, 5, hb("45")));
  var r = db2_reader_new(data);
  var ok = true;
  var i = 0;
  while i < fmts.len() {
    let fr = db2_frame_parse(&mut r);
    if !fr.is_ok {
      ok = false;
    } else {
      let f: Db2Frame = fr.value;
      let ef: Int = fmts[i];
      let et: Int = types[i];
      let ec: Bool = chaineds[i];
      let es: Bool = sames[i];
      if f.format != ef { ok = false; }
      if f.dss_type != et { ok = false; }
      if f.chained != ec { ok = false; }
      if f.same_correlation != es { ok = false; }
      if f.correlation != i + 1 { ok = false; }
    }
    i = i + 1;
  }
  if db2_reader_remaining(&r) != 0 { ok = false; }
  return assert(ok, "DSS format matrix: request, chained/same-id, object, reply, no-reply");
}

fn t4() -> TestResult {
  var ok = true;
  var r = db2_reader_new(hb("0009D001"));
  if !err_is_f(db2_frame_parse(&mut r), "db2: truncated input at offset 0") { ok = false; }
  var r2 = db2_reader_new(frame_raw(209, 1, 1, hb("")));
  if !err_is_f(db2_frame_parse(&mut r2), "db2: bad DSS magic 0xD1 at offset 2 (expected 0xD0)") { ok = false; }
  var r3 = db2_reader_new(cat(be16(4), hb("D0010001")));
  if !err_is_f(db2_frame_parse(&mut r3), "db2: DSS length 4 below minimum 6 at offset 0") { ok = false; }
  var r4 = db2_reader_new(cat(be16(20), hb("D0010001000000")));
  if !err_is_f(db2_frame_parse(&mut r4), "db2: DSS length 20 overruns buffer (9 bytes remain) at offset 0") { ok = false; }
  var r5 = db2_reader_new(cat(be16(32772), hb("D0010001")));
  if !err_is_f(db2_frame_parse(&mut r5), "db2: continued (large) DSS length 0x8004 not supported by db2_frame_parse at offset 0") { ok = false; }
  var r6 = db2_reader_new(frame(17, 1, hb("")));
  if !err_is_f(db2_frame_parse(&mut r6), "db2: same-correlation bit set on unchained DSS at offset 3") { ok = false; }
  var r7 = db2_reader_new(frame(33, 1, hb("")));
  if !err_is_f(db2_frame_parse(&mut r7), "db2: continue-on-error bit set on unchained DSS at offset 3") { ok = false; }
  var r8 = db2_reader_new(frame(129, 1, hb("")));
  if !err_is_f(db2_frame_parse(&mut r8), "db2: DSS format bit 0x80 set at offset 3") { ok = false; }
  return assert(ok, "frame rejects: truncation, magic, short length, overrun, continuation, flag misuse");
}

fn t5() -> TestResult {
  var data = Vec[UInt8].new();
  data = cat(data, frame(81, 5, hb("AA")));
  data = cat(data, frame(1, 5, hb("BB")));
  data = cat(data, frame(2, 9, hb("CCCC")));
  var ok = true;
  let mr = db2_frames_assemble(data);
  if !mr.is_ok {
    ok = false;
  } else {
    let m: Db2Messages = mr.value;
    if m.payloads.len() != 2 { ok = false; }
    if m.frame_total != 3 { ok = false; }
    if m.consumed != 22 { ok = false; }
    if m.frame_counts.len() != 2 { ok = false; }
    let c0: Int = m.frame_counts[0];
    let c1: Int = m.frame_counts[1];
    if c0 != 2 || c1 != 1 { ok = false; }
    let p0: Vec[UInt8] = m.payloads[0];
    let p1: Vec[UInt8] = m.payloads[1];
    if !bytes_is(p0, "AABB") { ok = false; }
    if !bytes_is(p1, "CCCC") { ok = false; }
    let k0: Int = m.correlations[0];
    let k1: Int = m.correlations[1];
    if k0 != 5 || k1 != 9 { ok = false; }
    let t0: Int = m.types[0];
    let t1: Int = m.types[1];
    if t0 != 1 || t1 != 2 { ok = false; }
  }
  return assert(ok, "multi-frame message assembly with same-correlation chain");
}

fn t6() -> TestResult {
  var ok = true;
  var a = Vec[UInt8].new();
  a = cat(a, frame(65, 1, hb("AA")));
  a = cat(a, frame(65, 2, hb("BB")));
  if !err_is_m(db2_frames_assemble(a), "db2: chained DSS has no following frame at offset 14") { ok = false; }
  var b = Vec[UInt8].new();
  b = cat(b, frame(81, 5, hb("AA")));
  b = cat(b, frame(1, 6, hb("BB")));
  if !err_is_m(db2_frames_assemble(b), "db2: correlation id 6 changed mid-chain (expected 5) at offset 7") { ok = false; }
  var c = Vec[UInt8].new();
  c = cat(c, frame(65, 1, hb("AA")));
  c = cat(c, frame_raw(209, 1, 1, hb("BB")));
  if !err_is_m(db2_frames_assemble(c), "db2: bad DSS magic 0xD1 at offset 9 (expected 0xD0)") { ok = false; }
  // A differing-correlation chain (no same-id flag) is legal.
  var d = Vec[UInt8].new();
  d = cat(d, frame(65, 1, hb("AA")));
  d = cat(d, frame(65, 2, hb("BB")));
  d = cat(d, frame(1, 3, hb("CC")));
  let dr = db2_frames_assemble(d);
  if !dr.is_ok { ok = false; } else {
    let m: Db2Messages = dr.value;
    if m.payloads.len() != 1 { ok = false; }
    let fc: Int = m.frame_counts[0];
    if fc != 3 { ok = false; }
    let p0: Vec[UInt8] = m.payloads[0];
    if !bytes_is(p0, "AABBCC") { ok = false; }
  }
  return assert(ok, "assembly rejects and legal differing-correlation chains");
}

fn t7() -> TestResult {
  var ok = true;
  if !str_is(db2_cp_name(db2_cp_excsat()), "EXCSAT") { ok = false; }
  if !str_is(db2_cp_name(db2_cp_secchk()), "SECCHK") { ok = false; }
  if !str_is(db2_cp_name(db2_cp_sqlcard()), "SQLCARD") { ok = false; }
  if !str_is(db2_cp_name(db2_cp_qrydta()), "QRYDTA") { ok = false; }
  if !str_is(db2_cp_name(db2_cp_fdodsc()), "FDODSC") { ok = false; }
  if !str_is(db2_cp_name(db2_cp_sqldtard()), "SQLDTARD") { ok = false; }
  if !str_is(db2_cp_name(db2_cp_rdbaflrm()), "RDBAFLRM") { ok = false; }
  if !str_is(db2_cp_name(0x7777), "") { ok = false; }
  if !db2_cp_known(db2_cp_sqlcard()) { ok = false; }
  if db2_cp_known(0x7777) { ok = false; }
  if !db2_cp_is_command(db2_cp_excsat()) { ok = false; }
  if db2_cp_is_command(db2_cp_srvnam()) { ok = false; }
  if !db2_cp_is_parameter(db2_cp_rdbnam()) { ok = false; }
  if !db2_cp_is_sql_data(db2_cp_qrydta()) { ok = false; }
  if !db2_cp_is_reply_message(db2_cp_opnqryrm()) { ok = false; }
  return assert(ok, "codepoint names and category predicates");
}

fn t8() -> TestResult {
  var ok = true;
  if db2_cp_excsat() != 0x1041 { ok = false; }
  if db2_cp_accsec() != 0x106D { ok = false; }
  if db2_cp_secchk() != 0x106E { ok = false; }
  if db2_cp_accrdb() != 0x2001 { ok = false; }
  if db2_cp_excsqlstt() != 0x200B { ok = false; }
  if db2_cp_opnqry() != 0x200C { ok = false; }
  if db2_cp_endbnd() != 0x2009 { ok = false; }
  if db2_cp_clsqry() != 0x2005 { ok = false; }
  if db2_cp_dscrdbtbl() != 0x2012 { ok = false; }
  if db2_cp_sqlcard() != 0x2408 { ok = false; }
  if db2_cp_sqldard() != 0x2411 { ok = false; }
  if db2_cp_sqldtard() != 0x2413 { ok = false; }
  if db2_cp_sqldta() != 0x2412 { ok = false; }
  if db2_cp_sqlstt() != 0x2414 { ok = false; }
  if db2_cp_qrydsc() != 0x241A { ok = false; }
  if db2_cp_fdodsc() != 0x0010 { ok = false; }
  if db2_cp_rdbacccl() != 0x210F { ok = false; }
  if db2_cp_qryblksz() != 0x2114 { ok = false; }
  if db2_cp_secmec() != 0x11A2 { ok = false; }
  if db2_cp_rdbnam() != 0x2110 { ok = false; }
  if db2_cp_srvnam() != 0x116D { ok = false; }
  if db2_cp_extnam() != 0x115E { ok = false; }
  if db2_cp_prdid() != 0x112E { ok = false; }
  if db2_cp_typdefnam() != 0x002F { ok = false; }
  if db2_cp_typdefovr() != 0x0035 { ok = false; }
  if db2_cp_sqlstt_parameter() != 0x2124 { ok = false; }
  return assert(ok, "verified codepoint values and the mandate-vs-verified deltas");
}

fn t9() -> TestResult {
  var ok = true;
  let inner: Vec[UInt8] = cat(ddm(4446, sbytes("abc")), ddm(4461, sbytes("srv")));
  let data: Vec[UInt8] = ddm(4161, inner);
  var r = db2_reader_new(data);
  let dr = db2_ddm_read(&mut r);
  if !dr.is_ok {
    ok = false;
  } else {
    let d: Db2Ddm = dr.value;
    if d.code != 4161 { ok = false; }
    if d.length != 18 { ok = false; }
    if d.long_form { ok = false; }
    if d.ext_bytes != 0 { ok = false; }
    let dp: Vec[UInt8] = d.payload;
    if !bytes_equal(dp, inner) { ok = false; }
    if db2_ddm_consumed(&d) != 18 { ok = false; }
  }
  if db2_reader_pos(&r) != 18 { ok = false; }
  let lr = db2_ddms_parse(inner);
  if !lr.is_ok {
    ok = false;
  } else {
    let l: Db2DdmList = lr.value;
    if db2_ddm_list_count(&l) != 2 { ok = false; }
    let c0: Int = l.codes[0];
    let c1: Int = l.codes[1];
    if c0 != 4446 || c1 != 4461 { ok = false; }
    let l0: Int = l.lengths[0];
    let l1: Int = l.lengths[1];
    if l0 != 7 || l1 != 7 { ok = false; }
    let p0: Vec[UInt8] = l.payloads[0];
    let p1: Vec[UInt8] = l.payloads[1];
    if !bytes_is(p0, "616263") { ok = false; }
    if !bytes_is(p1, "737276") { ok = false; }
    if db2_ddm_list_find(&l, 4461) != 1 { ok = false; }
    if db2_ddm_list_find(&l, 1234) != -1 { ok = false; }
  }
  return assert(ok, "DDM short form single read and flat list walk");
}

fn t10() -> TestResult {
  var ok = true;
  let inner: Vec[UInt8] = cat(ddm(16, hb("030004")), ddm(5242, hb("00AABBCC")));
  let data: Vec[UInt8] = ddm_long(9234, inner);
  var r = db2_reader_new(data);
  let dr = db2_ddm_read(&mut r);
  if !dr.is_ok {
    ok = false;
  } else {
    let d: Db2Ddm = dr.value;
    if d.code != 9234 { ok = false; }
    if !d.long_form { ok = false; }
    if d.ext_bytes != 4 { ok = false; }
    if d.length != 8 + inner.len() { ok = false; }
    let dp2: Vec[UInt8] = d.payload;
    if !bytes_equal(dp2, inner) { ok = false; }
  }
  if !db2_cp_is_long_length(9234) { ok = false; }
  if db2_cp_is_long_length(4161) { ok = false; }
  if db2_ddm_ext4_marker() != 32776 { ok = false; }
  if db2_ddm_ext6_marker() != 32778 { ok = false; }
  if db2_ddm_ext8_marker() != 32780 { ok = false; }
  if db2_ddm_streaming_marker() != 32772 { ok = false; }
  var r2 = db2_reader_new(data);
  let ar = db2_ddm_read_as(&mut r2, true);
  if !ar.is_ok { ok = false; }
  var r3 = db2_reader_new(data);
  if !err_is_d(db2_ddm_read_as(&mut r3, false), "db2: DDM 0x2412 is unexpectedly in extended length form at offset 0") { ok = false; }
  var r4 = db2_reader_new(ddm(4161, hb("00")));
  if !err_is_d(db2_ddm_read_as(&mut r4, true), "db2: DDM 0x1041 is not in extended length form at offset 0") { ok = false; }
  return assert(ok, "DDM extended 4-byte length form and form enforcement");
}

fn t11() -> TestResult {
  var ok = true;
  var r = db2_reader_new(hb("10"));
  if !err_is_d(db2_ddm_read(&mut r), "db2: truncated DDM length at offset 0") { ok = false; }
  var r2 = db2_reader_new(hb("0004"));
  if !err_is_d(db2_ddm_read(&mut r2), "db2: truncated DDM codepoint at offset 2") { ok = false; }
  var r3 = db2_reader_new(hb("00031041"));
  if !err_is_d(db2_ddm_read(&mut r3), "db2: DDM length 3 below minimum 4 at offset 0") { ok = false; }
  var r4 = db2_reader_new(hb("000A104100"));
  if !err_is_d(db2_ddm_read(&mut r4), "db2: DDM length 10 overruns buffer (5 bytes remain) at offset 0") { ok = false; }
  var r5 = db2_reader_new(hb("8005104100"));
  if !err_is_d(db2_ddm_read(&mut r5), "db2: invalid extended DDM length marker 0x8005 at offset 0") { ok = false; }
  var r6 = db2_reader_new(hb("8004241B"));
  if !err_is_d(db2_ddm_read(&mut r6), "db2: layer-B streaming DDM length 0x8004 not supported for codepoint 0x241B at offset 0") { ok = false; }
  var r7 = db2_reader_new(hb("800C1041FF00000000000000"));
  if !err_is_d(db2_ddm_read(&mut r7), "db2: extended DDM length exceeds signed range at offset 4") { ok = false; }
  var r8 = db2_reader_new(hb("8008104100000006"));
  if !err_is_d(db2_ddm_read(&mut r8), "db2: extended DDM length 6 below header size 8 at offset 0") { ok = false; }
  var r9 = db2_reader_new(hb("8008104100"));
  if !err_is_d(db2_ddm_read(&mut r9), "db2: truncated extended DDM length at offset 4") { ok = false; }
  return assert(ok, "DDM rejects: truncation, minimum, overrun, extended markers");
}

fn t12() -> TestResult {
  var ok = true;
  var inner = Vec[UInt8].new();
  inner = cat(inner, ddm(4446, sbytes("pydrda")));
  inner = cat(inner, ddm(4461, sbytes("host1")));
  inner = cat(inner, ddm(4442, sbytes("1.0")));
  let data: Vec[UInt8] = frame(1, 1, ddm(4161, inner));
  var r = db2_reader_new(data);
  let fr = db2_frame_parse(&mut r);
  if !fr.is_ok { ok = false; } else {
    let f: Db2Frame = fr.value;
    if !str_is(db2_dss_type_name(f.dss_type), "REQUEST") { ok = false; }
    let fpl: Vec[UInt8] = f.payload;
    let lr = db2_ddms_parse(fpl);
    if !lr.is_ok { ok = false; } else {
      let l: Db2DdmList = lr.value;
      if db2_ddm_list_count(&l) != 1 { ok = false; }
      let c0: Int = l.codes[0];
      if c0 != 4161 { ok = false; }
      if !str_is(db2_cp_name(c0), "EXCSAT") { ok = false; }
      let p0: Vec[UInt8] = l.payloads[0];
      let ir = db2_ddms_parse(p0);
      if !ir.is_ok { ok = false; } else {
        let il: Db2DdmList = ir.value;
        if db2_ddm_list_count(&il) != 3 { ok = false; }
        let e0: Vec[UInt8] = il.payloads[0];
        let e1: Vec[UInt8] = il.payloads[1];
        let e2: Vec[UInt8] = il.payloads[2];
        let t0: Db2Text = db2_text_ascii(e0);
        let t1: Db2Text = db2_text_ascii(e1);
        let t2: Db2Text = db2_text_ascii(e2);
        if !str_is(t0.text, "pydrda") { ok = false; }
        if !str_is(t1.text, "host1") { ok = false; }
        if !str_is(t2.text, "1.0") { ok = false; }
        if !t0.ascii || !t1.ascii || !t2.ascii { ok = false; }
      }
    }
  }
  return assert(ok, "EXCSAT frame walk with EXTNAM/SRVNAM/SRVRLSLV text decode");
}

fn t13() -> TestResult {
  var ok = true;
  let eb: Db2Text = db2_text_ascii(hb("E3C5E7E3"));
  if eb.ascii { ok = false; }
  if !str_is(eb.text, "") { ok = false; }
  if !bytes_is(eb.bytes, "E3C5E7E3") { ok = false; }
  let pad: Vec[UInt8] = hb("4142432020");
  let pt: Db2Text = db2_text_ascii(pad);
  if !str_is(pt.text, "ABC  ") { ok = false; }
  if !str_is(db2_text_trimmed(&pt), "ABC") { ok = false; }
  let zt: Db2Text = db2_text_nul_terminated(hb("51544453514C58383600FF"));
  if !str_is(zt.text, "QTDSQLX86") { ok = false; }
  if !zt.ascii { ok = false; }
  let st: Db2Text = db2_text_ascii(hb("51544453514C58383600FF"));
  if st.ascii { ok = false; }
  if !str_is(db2_text_trimmed(&eb), "") { ok = false; }
  return assert(ok, "ASCII vs opaque text decode, padding trim and NUL termination");
}

fn t14() -> TestResult {
  var ok = true;
  var inner = Vec[UInt8].new();
  inner = cat(inner, ddm(4514, cat(be16(3), be16(9))));
  inner = cat(inner, ddm(8464, sbytes("SAMPLE")));
  inner = cat(inner, ddm(4512, sbytes("db2inst1")));
  let lr = db2_ddms_parse(inner);
  if !lr.is_ok {
    ok = false;
  } else {
    let l: Db2DdmList = lr.value;
    if db2_ddm_list_count(&l) != 3 { ok = false; }
    let si: Int = db2_ddm_list_find(&l, 4514);
    if si != 0 { ok = false; }
    let sp: Vec[UInt8] = l.payloads[si];
    let sr = db2_secmec_parse(sp);
    if !sr.is_ok {
      ok = false;
    } else {
      let vals: Vec[Int] = sr.value;
      if vals.len() != 2 { ok = false; }
      let v0: Int = vals[0];
      let v1: Int = vals[1];
      if v0 != 3 || v1 != 9 { ok = false; }
      if !str_is(db2_secmec_name(v0), "USRIDPWD") { ok = false; }
      if !str_is(db2_secmec_name(v1), "EUSRIDPWD") { ok = false; }
      if !db2_secmec_known(v0) || !db2_secmec_known(v1) { ok = false; }
    }
    let ri: Int = db2_ddm_list_find(&l, 8464);
    let rp: Vec[UInt8] = l.payloads[ri];
    if !str_is(db2_text_ascii(rp).text, "SAMPLE") { ok = false; }
  }
  if !err_is_v(db2_secmec_parse(hb("00")), "db2: odd SECMEC payload length 1 at offset 0") { ok = false; }
  if db2_secmec_known(2) { ok = false; }
  if !str_is(db2_secmec_name(2), "UNKNOWN") { ok = false; }
  return assert(ok, "SECCHK codepoint walk, SECMEC list decode and names");
}

fn t15() -> TestResult {
  var ok = true;
  var inner = Vec[UInt8].new();
  inner = cat(inner, ddm(8464, sbytes("SAMPLE")));
  inner = cat(inner, ddm(8463, be16(0x2407)));
  inner = cat(inner, ddm(4398, sbytes("SQL12010")));
  inner = cat(inner, ddm(47, sbytes("QTDSQLX86")));
  inner = cat(inner, ddm(0x7777, hb("CAFE")));
  let lr = db2_ddms_parse(inner);
  if !lr.is_ok {
    ok = false;
  } else {
    let l: Db2DdmList = lr.value;
    if db2_ddm_list_count(&l) != 5 { ok = false; }
    let ui: Int = db2_ddm_list_find(&l, 0x7777);
    if ui != 4 { ok = false; }
    let up: Vec[UInt8] = l.payloads[ui];
    if !bytes_is(up, "CAFE") { ok = false; }
    if !str_is(db2_cp_name(0x7777), "") { ok = false; }
    let ti: Int = db2_ddm_list_find(&l, 47);
    let tp: Vec[UInt8] = l.payloads[ti];
    let tt: Db2Text = db2_text_ascii(tp);
    if !str_is(tt.text, "QTDSQLX86") { ok = false; }
    if db2_tydefnam_byteorder(tt.text) != db2_byteorder_little() { ok = false; }
    if db2_tydefnam_byteorder("QTDSQL370") != db2_byteorder_big() { ok = false; }
    if db2_tydefnam_byteorder("QTDSQL400") != db2_byteorder_big() { ok = false; }
    if db2_tydefnam_byteorder("NOPE") != db2_byteorder_unknown() { ok = false; }
    if db2_byteorder_little() != 1 || db2_byteorder_big() != 0 { ok = false; }
  }
  return assert(ok, "ACCRDB walk, TYPDEFNAM byte order and unknown codepoint preservation");
}

fn t16() -> TestResult {
  var ok = true;
  var r = db2_reader_new(cat(vcm("abc"), vcm("")));
  let tr = db2_vcm_read(&mut r);
  if !tr.is_ok {
    ok = false;
  } else {
    let t: Db2Text = tr.value;
    if !str_is(t.text, "abc") { ok = false; }
    if !t.ascii { ok = false; }
  }
  let tr2 = db2_vcm_read(&mut r);
  if !tr2.is_ok { ok = false; } else {
    let t2: Db2Text = tr2.value;
    if !str_is(t2.text, "") { ok = false; }
  }
  if db2_reader_remaining(&r) != 0 { ok = false; }
  var r2 = db2_reader_new(cat(be16(5), hb("6162")));
  if !err_is_t(db2_vcm_read(&mut r2), "db2: truncated VCM at offset 0") { ok = false; }
  var r3 = db2_reader_new(hb("61"));
  if !err_is_t(db2_vcm_read(&mut r3), "db2: truncated VCM at offset 0") { ok = false; }
  return assert(ok, "VCM length-prefixed string read and truncation errors");
}

// A SQLCARD: SQLCA group (flag, SQLCODE, state, errproc, xgrp flag,
// SQLERRD[6], SQLWARN[11]) then the SQLDIAGGRP VCMs and the 0xFF marker.
fn mk_sqlca(sqlcode: Int, update: Int, msgs: Str, little: Bool) -> Vec[UInt8] {
  var p = Vec[UInt8].new();
  p.push(0 as UInt8);
  if little {
    p = cat(p, le32(sqlcode));
  } else {
    p = cat(p, be32(sqlcode));
  }
  p = cat(p, sbytes("23505"));
  p = cat(p, rep_byte(0, 8));
  p.push(0 as UInt8);
  if little {
    p = cat(p, le32(0));
    p = cat(p, le32(0));
    p = cat(p, le32(update));
  } else {
    p = cat(p, be32(0));
    p = cat(p, be32(0));
    p = cat(p, be32(update));
  }
  p = cat(p, be32(0));
  p = cat(p, be32(0));
  p = cat(p, be32(0));
  p = cat(p, rep_byte(32, 11));
  p = cat(p, vcm("SAMPLE"));
  p = cat(p, vcm(msgs));
  p = cat(p, vcm(""));
  p.push(255 as UInt8);
  return p;
}

fn t17() -> TestResult {
  var ok = true;
  let card: Vec[UInt8] = mk_sqlca(-803, 42, "duplicate k", false);
  let cr = db2_sqlcard_parse(card, db2_byteorder_big());
  if !cr.is_ok {
    ok = false;
  } else {
    let c: Db2SqlCard = cr.value;
    if !c.present { ok = false; }
    if c.sqlcode != -803 { ok = false; }
    if !str_is(c.sqlstate, "23505") { ok = false; }
    if !c.sqlstate_ascii { ok = false; }
    if !str_is(c.rdbnam, "SAMPLE") { ok = false; }
    if !c.rdbnam_ascii { ok = false; }
    if c.errd.len() != 6 { ok = false; }
    if c.update_count != 42 { ok = false; }
    if !c.sqlwarn_present { ok = false; }
    if c.sqlwarn.len() != 11 { ok = false; }
    let w0: UInt8 = c.sqlwarn[0];
    if ((w0 as Int) & 0xFF) != 32 { ok = false; }
    if !str_is(c.message, "duplicate k") { ok = false; }
    if !c.message_ascii { ok = false; }
    let mb: Vec[UInt8] = c.message_bytes;
    let dt: Vec[UInt8] = c.diag_tail;
    if !bytes_is(mb, "6475706C6963617465206B") { ok = false; }
    if !bytes_is(dt, "FF") { ok = false; }
    if c.errproc.len() != 8 { ok = false; }
  }
  let cr2 = db2_sqlcard_parse(mk_sqlca(-803, 0, "dup", true), db2_byteorder_little());
  if !cr2.is_ok {
    ok = false;
  } else {
    let c2: Db2SqlCard = cr2.value;
    if c2.sqlcode != -803 { ok = false; }
    if !str_is(c2.message, "dup") { ok = false; }
  }
  return assert(ok, "SQLCARD big- and little-endian SQLCA decode with message text");
}

fn t18() -> TestResult {
  var ok = true;
  let nr = db2_sqlcard_parse(hb("FF"), db2_byteorder_big());
  if !nr.is_ok {
    ok = false;
  } else {
    let c: Db2SqlCard = nr.value;
    if c.present { ok = false; }
  }
  if !err_is_card(db2_sqlcard_parse(hb("00"), db2_byteorder_big()), "db2: SQLCARD too short (1 bytes, need 19) at offset 0") { ok = false; }
  if !err_is_card(db2_sqlcard_parse(cat(hb("12"), rep_byte(0, 18)), db2_byteorder_big()), "db2: SQLCARD group flag 0x12 invalid at offset 0") { ok = false; }
  let full: Vec[UInt8] = mk_sqlca(0, 7, "", false);
  let fixed: Vec[UInt8] = take_n(full, 54);
  let fr = db2_sqlcard_parse(fixed, db2_byteorder_big());
  if !fr.is_ok {
    ok = false;
  } else {
    let c: Db2SqlCard = fr.value;
    if !c.present { ok = false; }
    if c.update_count != 7 { ok = false; }
    if !str_is(c.rdbnam, "") { ok = false; }
    if !str_is(c.message, "") { ok = false; }
    if c.diag_tail.len() != 0 { ok = false; }
  }
  let nogrp: Vec[UInt8] = cat(take_n(full, 18), hb("FF"));
  let gr = db2_sqlcard_parse(nogrp, db2_byteorder_big());
  if !gr.is_ok {
    ok = false;
  } else {
    let c2: Db2SqlCard = gr.value;
    if c2.errd.len() != 0 { ok = false; }
    if c2.sqlwarn_present { ok = false; }
  }
  if !err_is_card(db2_sqlcard_parse(cat(take_n(full, 54), cat(be16(9), hb("6162"))), db2_byteorder_big()), "db2: truncated VCM at offset 54") { ok = false; }
  if !err_is_card(db2_sqlcard_parse(cat(take_n(full, 18), hb("33")), db2_byteorder_big()), "db2: SQLCARD extended group flag 0x33 invalid at offset 18") { ok = false; }
  return assert(ok, "SQLCARD null form, short cards, absent extended group and errors");
}

fn t19() -> TestResult {
  var ok = true;
  let dr = db2_fdodsc_parse(desc3());
  if !dr.is_ok {
    ok = false;
  } else {
    let d: Db2Descriptor = dr.value;
    if d.count != 3 { ok = false; }
    let t0: Int = d.types[0];
    let t1: Int = d.types[1];
    let t2: Int = d.types[2];
    if t0 != 3 || t1 != 57 || t2 != 23 { ok = false; }
    let l0: Int = d.lengths[0];
    let l1: Int = d.lengths[1];
    let l2: Int = d.lengths[2];
    if l0 != 4 { ok = false; }
    if l1 != 16383 { ok = false; }
    if l2 != 8 { ok = false; }
    if !bytes_is(d.trailer, "0671E4D00001") { ok = false; }
  }
  if !err_is_dsc(db2_fdodsc_parse(hb("00")), "db2: FDODSC descriptor too short (1 bytes) at offset 0") { ok = false; }
  if !err_is_dsc(db2_fdodsc_parse(hb("0176D0")), "db2: FDODSC descriptor length 1 invalid at offset 0") { ok = false; }
  if !err_is_dsc(db2_fdodsc_parse(hb("0476FF00")), "db2: FDODSC marker 0x76FF (expected 0x76D0) at offset 1") { ok = false; }
  if !err_is_dsc(db2_fdodsc_parse(hb("0476D000")), "db2: FDODSC triplet bytes 1 not a multiple of 3 at offset 0") { ok = false; }
  return assert(ok, "FDODSC descriptor triplets, trailer and malformed forms");
}

fn t20() -> TestResult {
  var ok = true;
  var dta = Vec[UInt8].new();
  dta.push(0 as UInt8);
  dta = cat(dta, be32(7));
  dta.push(0 as UInt8);
  dta = cat(dta, be16(2));
  dta = cat(dta, sbytes("hi"));
  dta.push(255 as UInt8);
  let sq: Vec[UInt8] = cat(ddm(16, desc3()), ddm(5242, dta));
  let rr = db2_sqldta_parse(sq);
  if !rr.is_ok {
    ok = false;
  } else {
    let row: Db2DtaRow = rr.value;
    if row.col_count != 3 { ok = false; }
    if row.consumed != 11 { ok = false; }
    let n0: Bool = row.null_flags[0];
    let n1: Bool = row.null_flags[1];
    let n2: Bool = row.null_flags[2];
    if n0 || n1 || !n2 { ok = false; }
    let v0: Vec[UInt8] = row.values[0];
    let v1: Vec[UInt8] = row.values[1];
    let v2: Vec[UInt8] = row.values[2];
    if !bytes_is(v0, "00000007") { ok = false; }
    if !bytes_is(v1, "6869") { ok = false; }
    if v2.len() != 0 { ok = false; }
  }
  if !err_is_row(db2_sqldta_parse(ddm(5242, hb("00"))), "db2: SQLDTA missing FDODSC at offset 0") { ok = false; }
  if !err_is_row(db2_sqldta_parse(ddm(16, desc3())), "db2: SQLDTA missing FDODTA at offset 0") { ok = false; }
  let bad_dta: Vec[UInt8] = cat(hb("01"), take_n(dta, dta.len() - 1));
  let sq_bad: Vec[UInt8] = cat(ddm(16, desc3()), ddm(5242, bad_dta));
  if !err_is_row(db2_sqldta_parse(sq_bad), "db2: invalid FDODTA null indicator 1 at offset 0") { ok = false; }
  return assert(ok, "SQLDTA row decode with fixed, variable-length and null columns");
}

fn t21() -> TestResult {
  var ok = true;
  let d = Db2Descriptor{ count: 1; types: Vec[Int].new(); lengths: Vec[Int].new(); trailer: Vec[UInt8].new(); };
  var t = Vec[Int].new();
  t.push(3);
  var l = Vec[Int].new();
  l.push(4);
  let d2 = Db2Descriptor{ count: 1; types: t; lengths: l; trailer: Vec[UInt8].new(); };
  if !err_is_row(db2_fdodta_parse(hb("01AABBCC"), &d2), "db2: invalid FDODTA null indicator 1 at offset 0") { ok = false; }
  if !err_is_row(db2_fdodta_parse(hb("00AABBCC"), &d2), "db2: truncated FDODTA value at offset 1") { ok = false; }
  var t2 = Vec[Int].new();
  t2.push(57);
  var l2 = Vec[Int].new();
  l2.push(16383);
  let d3 = Db2Descriptor{ count: 1; types: t2; lengths: l2; trailer: Vec[UInt8].new() };
  if !err_is_row(db2_fdodta_parse(hb("00AA"), &d3), "db2: truncated input at offset 1") { ok = false; }
  if !err_is_row(db2_fdodta_parse(hb("00"), &d3), "db2: truncated input at offset 1") { ok = false; }
  if d.count != 1 { ok = false; }
  return assert(ok, "FDODTA null indicator, fixed and variable-length truncation errors");
}

fn t22() -> TestResult {
  var ok = true;
  var r = db2_reader_new(hb("01FF000300000004"));
  let a = db2_read_u8(&mut r);
  let b = db2_read_u8(&mut r);
  let c = db2_read_u16(&mut r);
  let d = db2_read_u32(&mut r);
  if !a.is_ok || !b.is_ok || !c.is_ok || !d.is_ok {
    ok = false;
  } else {
    if a.value != 1 { ok = false; }
    if b.value != 255 { ok = false; }
    if c.value != 3 { ok = false; }
    if d.value != 4 { ok = false; }
  }
  let rp = db2_reader_pos(&r);
  let rem = db2_reader_remaining(&r);
  if rp != 8 { ok = false; }
  if rem != 0 { ok = false; }
  var rm = db2_reader_new(hb("0102"));
  if db2_reader_pos_mut(&mut rm) != 0 { ok = false; }
  var re = db2_reader_new(hb(""));
  if !err_is_i(db2_read_u8(&mut re), "db2: truncated input at offset 0") { ok = false; }
  var r2 = db2_reader_new(hb("01"));
  if !err_is_i(db2_read_u16(&mut r2), "db2: truncated input at offset 0") { ok = false; }
  var r3 = db2_reader_new(hb("010203"));
  if !err_is_i(db2_read_u32(&mut r3), "db2: truncated input at offset 0") { ok = false; }
  // End-to-end: a chained EXCSAT + ACCSEC + ACCRDB request assembles into
  // one message whose DDM list carries the three command codepoints.
  var msg = Vec[UInt8].new();
  msg = cat(msg, frame(65, 1, ddm(4161, ddm(4446, sbytes("xiom")))));
  msg = cat(msg, frame(65, 1, ddm(4205, ddm(4514, be16(3)))));
  msg = cat(msg, frame(1, 1, ddm(8193, ddm(8464, sbytes("SAMPLE")))));
  let mr = db2_frames_assemble(msg);
  if !mr.is_ok {
    ok = false;
  } else {
    let m: Db2Messages = mr.value;
    if m.payloads.len() != 1 { ok = false; }
    let fc: Int = m.frame_counts[0];
    if fc != 3 { ok = false; }
    if m.frame_total != 3 { ok = false; }
    if m.consumed != msg.len() { ok = false; }
    let p0: Vec[UInt8] = m.payloads[0];
    let lr = db2_ddms_parse(p0);
    if !lr.is_ok { ok = false; } else {
      let l: Db2DdmList = lr.value;
      if db2_ddm_list_count(&l) != 3 { ok = false; }
      let c0: Int = l.codes[0];
      let c1: Int = l.codes[1];
      let c2: Int = l.codes[2];
      if c0 != 4161 || c1 != 4205 || c2 != 8193 { ok = false; }
      if !str_is(db2_cp_name(c0), "EXCSAT") { ok = false; }
      if !str_is(db2_cp_name(c1), "ACCSEC") { ok = false; }
      if !str_is(db2_cp_name(c2), "ACCRDB") { ok = false; }
      let d0: Int = l.lengths[0];
      if d0 != 12 { ok = false; }
      let pl0: Vec[UInt8] = l.payloads[0];
      let ir = db2_ddms_parse(pl0);
      if !ir.is_ok { ok = false; } else {
        let il: Db2DdmList = ir.value;
        let ip: Vec[UInt8] = il.payloads[0];
        if !str_is(db2_text_ascii(ip).text, "xiom") { ok = false; }
      }
    }
  }
  return assert(ok, "reader primitives and end-to-end chained handshake walk");
}

// --------------------------------------------------
//  Runner
// --------------------------------------------------

fn main() -> Int {
  io.println("=== xiom.db2 conformance tests ===");
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
  if failed == 0 {
    io.println("xiom.db2: all tests passed");
  } else {
    io.println("xiom.db2: tests failed");
  }
  return failed;
}
