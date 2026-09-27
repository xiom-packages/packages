// XIOM -- xiom.orc conformance tests
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Covers the documented API over synthetic ORC files whose postscript,
// footer, stripe footers and metadata are hand-encoded protobufs built in
// this file: minimal postscript parsing, every error in the catalog (bad
// magic, postscript bounds, unsupported compression, footer/metadata
// bounds, truncated varints and fields, invalid wire types, non-printable
// field names, stripe overflow, type-tree validation), the printability
// and packing rules, stripe/type/stream/statistics accessors and their
// bounds errors, plus one full integration fixture.
//
// Harness style mirrors xiom.gguf: one fn tN() -> Int per test, called
// directly from main; main prints [PASS]/[FAIL] and returns the failure
// count. Str values are compared with str_compare.

module orc_tests
use xiom.io; use xiom.test;
use xiom.string; use xiom.string.builder; use xiom.string.compare;
use xiom.convert;
use xiom.orc;

// --------------------------------------------------
//  Harness helpers
// --------------------------------------------------

fn report(passed: Bool, name: Str) -> Int {
  if passed {
    io.println("  [PASS] " + name);
    return 0;
  }
  io.println("  [FAIL] " + name);
  return 1;
}

fn str_eq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn expect_orc_err(r: Result[Orc, Str], want: Str, name: Str) -> Int {
  if r.is_ok {
    return report(false, name + " (expected Err)");
  }
  let got: Str = r.error;
  if !str_eq(got, want) {
    return report(false, name + " (got: " + got + ")");
  }
  return report(true, name);
}

fn expect_int_err(r: Result[Int, Str], want: Str, name: Str) -> Int {
  if r.is_ok {
    return report(false, name + " (expected Err)");
  }
  let got: Str = r.error;
  if !str_eq(got, want) {
    return report(false, name + " (got: " + got + ")");
  }
  return report(true, name);
}

fn expect_str_err(r: Result[Str, Str], want: Str, name: Str) -> Int {
  if r.is_ok {
    return report(false, name + " (expected Err)");
  }
  let got: Str = r.error;
  if !str_eq(got, want) {
    return report(false, name + " (got: " + got + ")");
  }
  return report(true, name);
}

// --------------------------------------------------
//  Hand-encoded protobuf helpers
// --------------------------------------------------

fn push_bytes(out: &mut Vec[UInt8], src: &Vec[UInt8]) {
  var i = 0;
  while i < src.len() {
    let b: UInt8 = src[i];
    out.push(b);
    i = i + 1;
  }
}

fn zeros(n: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < n {
    v.push((0 as UInt8));
    i = i + 1;
  }
  return v;
}

// Base-128 varint for a non-negative value.
fn enc_varint(out: &mut Vec[UInt8], v: Int) {
  var q = v;
  var done = false;
  while !done {
    var b = q % 128;
    if b < 0 {
      b = b + 128;
    }
    q = (q - b) / 128;
    if q > 0 {
      out.push(((b + 128) as UInt8));
    } else {
      out.push((b as UInt8));
      done = true;
    }
  }
}

fn enc_tag(out: &mut Vec[UInt8], field: Int, wire: Int) {
  enc_varint(out, field * 8 + wire);
}

fn enc_uint(out: &mut Vec[UInt8], field: Int, v: Int) {
  enc_tag(out, field, 0);
  enc_varint(out, v);
}

fn enc_sub(out: &mut Vec[UInt8], field: Int, payload: &Vec[UInt8]) {
  enc_tag(out, field, 2);
  enc_varint(out, payload.len());
  push_bytes(out, payload);
}

fn enc_str(out: &mut Vec[UInt8], field: Int, s: Str) {
  var payload = Vec[UInt8].new();
  let n = string.str_len(s);
  var i = 0;
  while i < n {
    let b: UInt8 = string.byte_at(s, i);
    payload.push(b);
    i = i + 1;
  }
  enc_sub(out, field, &payload);
}

fn enc_packed(out: &mut Vec[UInt8], field: Int, vals: &Vec[Int]) {
  var payload = Vec[UInt8].new();
  var i = 0;
  while i < vals.len() {
    let v: Int = vals[i];
    enc_varint(&mut payload, v);
    i = i + 1;
  }
  enc_sub(out, field, &payload);
}

fn v_int(a: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  return v;
}

fn v_int2(a: Int, b: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  v.push(b);
  return v;
}

fn v_str2(a: Str, b: Str) -> Vec[Str] {
  var v = Vec[Str].new();
  v.push(a);
  v.push(b);
  return v;
}

// --------------------------------------------------
//  ORC fixture builders
// --------------------------------------------------

// Assemble "ORC" + body + postscript + one length byte.
fn wrap(ps: &Vec[UInt8], body: &Vec[UInt8]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  out.push((79 as UInt8));
  out.push((82 as UInt8));
  out.push((67 as UInt8));
  push_bytes(&mut out, body);
  push_bytes(&mut out, ps);
  out.push((ps.len() as UInt8));
  return out;
}

// PostScript with every field, magic "ORC" and a packed version list.
fn ps_new(footer_len: Int, compression: Int, block_size: Int, version: &Vec[Int], metadata_len: Int, writer_version: Int) -> Vec[UInt8] {
  var ps = Vec[UInt8].new();
  enc_uint(&mut ps, 1, footer_len);
  enc_uint(&mut ps, 2, compression);
  enc_uint(&mut ps, 3, block_size);
  enc_packed(&mut ps, 4, version);
  enc_uint(&mut ps, 5, metadata_len);
  enc_uint(&mut ps, 6, writer_version);
  enc_str(&mut ps, 8000, "ORC");
  return ps;
}

fn empty_ps() -> Vec[UInt8] {
  let v = v_int2(0, 12);
  return ps_new(0, 0, 262144, &v, 0, 9);
}

fn empty_orc() -> Vec[UInt8] {
  let ps = empty_ps();
  let body = Vec[UInt8].new();
  return wrap(&ps, &body);
}

fn t_scalar(kind: Int) -> Vec[UInt8] {
  var t = Vec[UInt8].new();
  enc_uint(&mut t, 1, kind);
  return t;
}

fn t_struct(subs: &Vec[Int], names: &Vec[Str]) -> Vec[UInt8] {
  var t = Vec[UInt8].new();
  enc_uint(&mut t, 1, 12);
  enc_packed(&mut t, 2, subs);
  var i = 0;
  while i < names.len() {
    let nm: Str = names[i];
    enc_str(&mut t, 3, nm);
    i = i + 1;
  }
  return t;
}

fn t_decimal(prec: Int, scale: Int) -> Vec[UInt8] {
  var t = Vec[UInt8].new();
  enc_uint(&mut t, 1, 14);
  enc_uint(&mut t, 5, prec);
  enc_uint(&mut t, 6, scale);
  return t;
}

fn t_varchar(maxlen: Int) -> Vec[UInt8] {
  var t = Vec[UInt8].new();
  enc_uint(&mut t, 1, 16);
  enc_uint(&mut t, 4, maxlen);
  return t;
}

fn stripe_info(off: Int, il: Int, dl: Int, fl: Int, rows: Int) -> Vec[UInt8] {
  var s = Vec[UInt8].new();
  enc_uint(&mut s, 1, off);
  enc_uint(&mut s, 2, il);
  enc_uint(&mut s, 3, dl);
  enc_uint(&mut s, 4, fl);
  enc_uint(&mut s, 5, rows);
  return s;
}

fn stream_info(kind: Int, col: Int, len: Int) -> Vec[UInt8] {
  var s = Vec[UInt8].new();
  enc_uint(&mut s, 1, kind);
  enc_uint(&mut s, 2, col);
  enc_uint(&mut s, 3, len);
  return s;
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

// Minimal uncompressed file: postscript fields and an empty footer.
fn t1() -> Int {
  let ps = empty_ps();
  let plen = ps.len();
  let body = Vec[UInt8].new();
  let buf = wrap(&ps, &body);
  let r = orc_parse(&buf);
  if !r.is_ok {
    return report(false, "minimal file parses (got: " + r.error + ")");
  }
  let o = r.value;
  if orc_compression(&o) != 0 {
    return report(false, "minimal: compression NONE");
  }
  if orc_block_size(&o) != 262144 {
    return report(false, "minimal: block size");
  }
  if orc_version_major(&o) != 0 || orc_version_minor(&o) != 12 {
    return report(false, "minimal: version 0.12");
  }
  if orc_version_count(&o) != 2 {
    return report(false, "minimal: two version parts");
  }
  if orc_writer_version(&o) != 9 {
    return report(false, "minimal: writer version ORC_14");
  }
  if !orc_footer_available(&o) {
    return report(false, "minimal: footer available");
  }
  if orc_postscript_offset(&o) != 3 || orc_postscript_length(&o) != plen {
    return report(false, "minimal: postscript bounds");
  }
  if orc_file_length(&o) != 3 + plen + 1 {
    return report(false, "minimal: file length");
  }
  let sc = orc_stripe_count(&o);
  let cc = orc_columns(&o);
  let rr = orc_rows(&o);
  if !sc.is_ok || sc.value != 0 {
    return report(false, "minimal: zero stripes");
  }
  if !cc.is_ok || cc.value != 0 {
    return report(false, "minimal: zero columns");
  }
  if !rr.is_ok || rr.value != 0 {
    return report(false, "minimal: zero rows");
  }
  return report(str_eq(orc_compression_name(0), "NONE"), "minimal postscript parses");
}

// Header magic.
fn t2() -> Int {
  var buf = empty_orc();
  buf[0] = 88;
  let r = orc_parse(&buf);
  return expect_orc_err(r, "orc: bad magic", "bad magic rejected");
}

// Buffer shorter than magic plus postscript length.
fn t3() -> Int {
  let buf = zeros(2);
  let r = orc_parse(&buf);
  return expect_orc_err(r, "orc: file too small", "short buffer rejected");
}

// Zero postscript length byte.
fn t4() -> Int {
  var buf = empty_orc();
  let n = buf.len();
  buf[n - 1] = 0;
  let r = orc_parse(&buf);
  return expect_orc_err(r, "orc: empty postscript", "empty postscript rejected");
}

// Postscript length pointing before the header magic.
fn t5() -> Int {
  var buf = zeros(10);
  buf[0] = 79;
  buf[1] = 82;
  buf[2] = 67;
  buf[9] = 200;
  let r = orc_parse(&buf);
  return expect_orc_err(r, "orc: postscript length out of bounds (len=200)", "postscript bounds rejected");
}

// Postscript magic field must be "ORC".
fn t6() -> Int {
  var ps = Vec[UInt8].new();
  enc_uint(&mut ps, 1, 0);
  enc_uint(&mut ps, 2, 0);
  enc_str(&mut ps, 8000, "ORX");
  let body = Vec[UInt8].new();
  let buf = wrap(&ps, &body);
  let r = orc_parse(&buf);
  return expect_orc_err(r, "orc: bad postscript magic", "bad postscript magic rejected");
}

// Compression kind above ZSTD.
fn t7() -> Int {
  let v = v_int2(0, 12);
  let ps = ps_new(0, 9, 262144, &v, 0, 9);
  let body = Vec[UInt8].new();
  let buf = wrap(&ps, &body);
  let r = orc_parse(&buf);
  return expect_orc_err(r, "orc: unsupported compression kind (kind=9)", "unknown compression rejected");
}

// A compressed file yields postscript metadata only.
fn t8() -> Int {
  let v = v_int2(0, 12);
  let ps = ps_new(0, 1, 262144, &v, 0, 9);
  let body = Vec[UInt8].new();
  let buf = wrap(&ps, &body);
  let r = orc_parse(&buf);
  if !r.is_ok {
    return report(false, "zlib file parses");
  }
  let o = r.value;
  if orc_compression(&o) != 1 {
    return report(false, "zlib: compression ZLIB");
  }
  if orc_footer_available(&o) {
    return report(false, "zlib: footer not available");
  }
  let cr = orc_columns(&o);
  if cr.is_ok {
    return report(false, "zlib: footer accessor gated");
  }
  return expect_int_err(cr, "orc: footer not available (compressed file)", "compressed file: postscript-only metadata");
}

// Footer length larger than the region before the postscript.
fn t9() -> Int {
  var ps = Vec[UInt8].new();
  enc_uint(&mut ps, 1, 1000);
  enc_uint(&mut ps, 2, 0);
  enc_str(&mut ps, 8000, "ORC");
  let body = Vec[UInt8].new();
  let buf = wrap(&ps, &body);
  let r = orc_parse(&buf);
  return expect_orc_err(r, "orc: footer length out of bounds (len=1000)", "footer length bounds rejected");
}

// Metadata length larger than the remaining region.
fn t10() -> Int {
  var ps = Vec[UInt8].new();
  enc_uint(&mut ps, 1, 0);
  enc_uint(&mut ps, 5, 1000);
  enc_str(&mut ps, 8000, "ORC");
  let body = Vec[UInt8].new();
  let buf = wrap(&ps, &body);
  let r = orc_parse(&buf);
  return expect_orc_err(r, "orc: metadata length out of bounds (len=1000)", "metadata length bounds rejected");
}

// A postscript ending inside a varint.
fn t11() -> Int {
  var ps = Vec[UInt8].new();
  enc_uint(&mut ps, 1, 0);
  enc_tag(&mut ps, 2, 0);
  ps.push((128 as UInt8));
  let body = Vec[UInt8].new();
  let buf = wrap(&ps, &body);
  let r = orc_parse(&buf);
  return expect_orc_err(r, "orc: truncated varint at offset 6", "truncated postscript varint rejected");
}

// A footer ending inside a varint.
fn t12() -> Int {
  var f = Vec[UInt8].new();
  f.push((8 as UInt8));
  f.push((128 as UInt8));
  let body = f;
  let v = v_int2(0, 12);
  let ps = ps_new(f.len(), 0, 262144, &v, 0, 9);
  let buf = wrap(&ps, &body);
  let r = orc_parse(&buf);
  return expect_orc_err(r, "orc: truncated varint at offset 4", "truncated footer protobuf rejected");
}

// Full footer: stripes, type tree, rows, statistics-presence flags.
fn t13() -> Int {
  let subs = v_int2(1, 2);
  let names = v_str2("a", "b");
  let t0 = t_struct(&subs, &names);
  let t1 = t_scalar(4);
  let t2 = t_scalar(7);
  var f = Vec[UInt8].new();
  enc_uint(&mut f, 1, 3);
  enc_uint(&mut f, 2, 23);
  let s0 = stripe_info(3, 4, 6, 0, 50);
  let s1 = stripe_info(13, 2, 5, 0, 0);
  enc_sub(&mut f, 3, &s0);
  enc_sub(&mut f, 3, &s1);
  enc_sub(&mut f, 4, &t0);
  enc_sub(&mut f, 4, &t1);
  enc_sub(&mut f, 4, &t2);
  enc_uint(&mut f, 5, 100);
  let st = Vec[UInt8].new();
  enc_sub(&mut f, 6, &st);
  enc_sub(&mut f, 6, &st);
  enc_uint(&mut f, 7, 10000);
  enc_uint(&mut f, 8, 9);
  let flen = f.len();
  let body = f;
  let v = v_int2(0, 12);
  let ps = ps_new(flen, 0, 262144, &v, 0, 7);
  let buf = wrap(&ps, &body);
  let r = orc_parse(&buf);
  if !r.is_ok {
    return report(false, "footer fixture parses (got: " + r.error + ")");
  }
  let o = r.value;
  var failed = 0;
  let sc = orc_stripe_count(&o);
  let rr = orc_rows(&o);
  let cc = orc_columns(&o);
  let hc = orc_stats_count(&o);
  if !sc.is_ok || sc.value != 2 {
    failed = failed + report(false, "footer: two stripes");
  }
  if !rr.is_ok || rr.value != 100 {
    failed = failed + report(false, "footer: 100 rows");
  }
  if !cc.is_ok || cc.value != 3 {
    failed = failed + report(false, "footer: three columns");
  }
  if !hc.is_ok || hc.value != 2 {
    failed = failed + report(false, "footer: two stat entries");
  }
  let hl = orc_header_length(&o);
  let cl = orc_content_length(&o);
  let rs = orc_row_index_stride(&o);
  let fw = orc_footer_writer_version(&o);
  if !hl.is_ok || hl.value != 3 {
    failed = failed + report(false, "footer: header length");
  }
  if !cl.is_ok || cl.value != 23 {
    failed = failed + report(false, "footer: content length");
  }
  if !rs.is_ok || rs.value != 10000 {
    failed = failed + report(false, "footer: row index stride");
  }
  if !fw.is_ok || fw.value != 9 {
    failed = failed + report(false, "footer: footer writer version");
  }
  if orc_footer_offset(&o) != 3 || orc_footer_length(&o) != flen {
    failed = failed + report(false, "footer: region bounds");
  }
  let so = orc_stripe_offset(&o, 0);
  let si = orc_stripe_index_length(&o, 0);
  let sd = orc_stripe_data_length(&o, 0);
  let sf = orc_stripe_footer_length(&o, 1);
  let sr = orc_stripe_rows(&o, 0);
  if !so.is_ok || so.value != 3 {
    failed = failed + report(false, "footer: stripe offset");
  }
  if !si.is_ok || si.value != 4 {
    failed = failed + report(false, "footer: stripe index length");
  }
  if !sd.is_ok || sd.value != 6 {
    failed = failed + report(false, "footer: stripe data length");
  }
  if !sf.is_ok || sf.value != 0 {
    failed = failed + report(false, "footer: stripe footer length");
  }
  if !sr.is_ok || sr.value != 50 {
    failed = failed + report(false, "footer: stripe rows");
  }
  let k0 = orc_column_kind(&o, 0);
  let k1 = orc_column_kind(&o, 1);
  let k2 = orc_column_kind(&o, 2);
  if !k0.is_ok || k0.value != 12 {
    failed = failed + report(false, "footer: struct root");
  }
  if !k1.is_ok || k1.value != 4 || !k2.is_ok || k2.value != 7 {
    failed = failed + report(false, "footer: scalar kinds");
  }
  let n0 = orc_column_field_count(&o, 0);
  let f0 = orc_column_field_name(&o, 0, 0);
  let f1 = orc_column_field_name(&o, 0, 1);
  if !n0.is_ok || n0.value != 2 {
    failed = failed + report(false, "footer: struct field count");
  }
  if !f0.is_ok || !str_eq(f0.value, "a") {
    failed = failed + report(false, "footer: first field name");
  }
  if !f1.is_ok || !str_eq(f1.value, "b") {
    failed = failed + report(false, "footer: second field name");
  }
  let s0c = orc_column_subtype_count(&o, 0);
  let s0v = orc_column_subtype(&o, 0, 0);
  let s1v = orc_column_subtype(&o, 0, 1);
  if !s0c.is_ok || s0c.value != 2 {
    failed = failed + report(false, "footer: subtype count");
  }
  if !s0v.is_ok || s0v.value != 1 || !s1v.is_ok || s1v.value != 2 {
    failed = failed + report(false, "footer: subtype ids");
  }
  let hs0 = orc_column_has_stats(&o, 0);
  let hs1 = orc_column_has_stats(&o, 1);
  let hs2 = orc_column_has_stats(&o, 2);
  if !hs0.is_ok || !hs0.value || !hs1.is_ok || !hs1.value {
    failed = failed + report(false, "footer: stats flags present");
  }
  if !hs2.is_ok || hs2.value {
    failed = failed + report(false, "footer: stats flag absent");
  }
  failed = failed + expect_int_err(orc_column_subtype(&o, 0, 2), "orc: subtype index out of range", "footer: subtype bounds");
  failed = failed + expect_str_err(orc_column_field_name(&o, 0, 2), "orc: field name index out of range", "footer: field name bounds");
  if failed == 0 {
    return report(true, "footer stripe/type/statistics metadata");
  }
  return 1;
}

// Stripe footer stream list with synthesized offsets.
fn t14() -> Int {
  let subs = v_int2(1, 2);
  let names = v_str2("a", "b");
  let t0 = t_struct(&subs, &names);
  let t1 = t_scalar(4);
  let t2 = t_scalar(7);
  var sf = Vec[UInt8].new();
  let st0 = stream_info(1, 1, 2);
  let st1 = stream_info(2, 1, 1);
  let st2 = stream_info(0, 0, 1);
  enc_sub(&mut sf, 1, &st0);
  enc_sub(&mut sf, 1, &st1);
  enc_sub(&mut sf, 1, &st2);
  let enc = Vec[UInt8].new();
  enc_sub(&mut sf, 2, &enc);
  let sflen = sf.len();
  var body = Vec[UInt8].new();
  var zz = 0;
  while zz < 10 {
    body.push((0 as UInt8));
    zz = zz + 1;
  }
  push_bytes(&mut body, &sf);
  var f = Vec[UInt8].new();
  enc_uint(&mut f, 1, 3);
  enc_uint(&mut f, 2, 13 + sflen);
  let s0 = stripe_info(3, 4, 6, sflen, 3);
  enc_sub(&mut f, 3, &s0);
  enc_sub(&mut f, 4, &t0);
  enc_sub(&mut f, 4, &t1);
  enc_sub(&mut f, 4, &t2);
  enc_uint(&mut f, 5, 3);
  let flen = f.len();
  push_bytes(&mut body, &f);
  let v = v_int2(0, 12);
  let ps = ps_new(flen, 0, 262144, &v, 0, 9);
  let buf = wrap(&ps, &body);
  let r = orc_parse(&buf);
  if !r.is_ok {
    return report(false, "stream fixture parses (got: " + r.error + ")");
  }
  let o = r.value;
  var failed = 0;
  let tc = orc_stream_count(&o);
  let sc = orc_stripe_stream_count(&o, 0);
  if !tc.is_ok || tc.value != 3 {
    failed = failed + report(false, "streams: total count");
  }
  if !sc.is_ok || sc.value != 3 {
    failed = failed + report(false, "streams: stripe count");
  }
  let k0 = orc_stream_kind(&o, 0, 0);
  let k1 = orc_stream_kind(&o, 0, 1);
  let k2 = orc_stream_kind(&o, 0, 2);
  if !k0.is_ok || k0.value != 1 || !k1.is_ok || k1.value != 2 || !k2.is_ok || k2.value != 0 {
    failed = failed + report(false, "streams: kinds DATA/LENGTH/PRESENT");
  }
  let c0 = orc_stream_column(&o, 0, 0);
  let c2 = orc_stream_column(&o, 0, 2);
  if !c0.is_ok || c0.value != 1 || !c2.is_ok || c2.value != 0 {
    failed = failed + report(false, "streams: columns");
  }
  let o0 = orc_stream_offset(&o, 0, 0);
  let o1 = orc_stream_offset(&o, 0, 1);
  let o2 = orc_stream_offset(&o, 0, 2);
  if !o0.is_ok || o0.value != 0 || !o1.is_ok || o1.value != 2 || !o2.is_ok || o2.value != 3 {
    failed = failed + report(false, "streams: synthesized offsets");
  }
  let l0 = orc_stream_length(&o, 0, 0);
  let l2 = orc_stream_length(&o, 0, 2);
  if !l0.is_ok || l0.value != 2 || !l2.is_ok || l2.value != 1 {
    failed = failed + report(false, "streams: lengths");
  }
  if !str_eq(orc_stream_kind_name(1), "DATA") {
    failed = failed + report(false, "streams: kind names");
  }
  failed = failed + expect_int_err(orc_stream_kind(&o, 0, 3), "orc: stream index out of range", "streams: index bounds");
  if failed == 0 {
    return report(true, "stripe footer stream list");
  }
  return 1;
}

// Metadata stripe statistics counts.
fn t15() -> Int {
  var f = Vec[UInt8].new();
  enc_uint(&mut f, 1, 3);
  enc_uint(&mut f, 2, 3);
  enc_uint(&mut f, 5, 0);
  let flen = f.len();
  let cst = Vec[UInt8].new();
  var ss0 = Vec[UInt8].new();
  enc_sub(&mut ss0, 1, &cst);
  enc_sub(&mut ss0, 1, &cst);
  var ss1 = Vec[UInt8].new();
  enc_sub(&mut ss1, 1, &cst);
  var m = Vec[UInt8].new();
  enc_sub(&mut m, 1, &ss0);
  enc_sub(&mut m, 1, &ss1);
  let mlen = m.len();
  var body = f;
  push_bytes(&mut body, &m);
  let v = v_int2(0, 12);
  let ps = ps_new(flen, 0, 262144, &v, mlen, 9);
  let buf = wrap(&ps, &body);
  let r = orc_parse(&buf);
  if !r.is_ok {
    return report(false, "metadata fixture parses (got: " + r.error + ")");
  }
  let o = r.value;
  var failed = 0;
  let n = orc_stripe_stats_count(&o);
  if !n.is_ok || n.value != 2 {
    failed = failed + report(false, "metadata: two stripe stats");
  }
  let c0 = orc_stripe_stats_cols(&o, 0);
  let c1 = orc_stripe_stats_cols(&o, 1);
  if !c0.is_ok || c0.value != 2 {
    failed = failed + report(false, "metadata: first stripe cols");
  }
  if !c1.is_ok || c1.value != 1 {
    failed = failed + report(false, "metadata: second stripe cols");
  }
  if orc_metadata_length(&o) != mlen {
    failed = failed + report(false, "metadata: region length");
  }
  failed = failed + expect_int_err(orc_stripe_stats_cols(&o, 2), "orc: stripe stats index out of range", "metadata: index bounds");
  if failed == 0 {
    return report(true, "file metadata stripe statistics");
  }
  return 1;
}

// Struct subtype referencing a column that does not exist.
fn t16() -> Int {
  let subs = v_int(7);
  let names = v_int_names_one();
  let t0 = t_struct(&subs, &names);
  let t1 = t_scalar(4);
  var f = Vec[UInt8].new();
  enc_uint(&mut f, 1, 3);
  enc_uint(&mut f, 2, 3);
  enc_sub(&mut f, 4, &t0);
  enc_sub(&mut f, 4, &t1);
  let body = f;
  let v = v_int2(0, 12);
  let ps = ps_new(f.len(), 0, 262144, &v, 0, 9);
  let buf = wrap(&ps, &body);
  let r = orc_parse(&buf);
  return expect_orc_err(r, "orc: subtype column out of range (column=0)", "bad subtype rejected");
}

// Struct whose field-name count differs from its subtype count.
fn t17() -> Int {
  let subs = v_int(1);
  let names = Vec[Str].new();
  let t0 = t_struct(&subs, &names);
  let t1 = t_scalar(4);
  var f = Vec[UInt8].new();
  enc_uint(&mut f, 1, 3);
  enc_uint(&mut f, 2, 3);
  enc_sub(&mut f, 4, &t0);
  enc_sub(&mut f, 4, &t1);
  let body = f;
  let v = v_int2(0, 12);
  let ps = ps_new(f.len(), 0, 262144, &v, 0, 9);
  let buf = wrap(&ps, &body);
  let r = orc_parse(&buf);
  return expect_orc_err(r, "orc: struct field name count mismatch (column=0)", "struct field mismatch rejected");
}

// Field name containing a non-printable byte.
fn t18() -> Int {
  let subs = v_int(1);
  var t0 = Vec[UInt8].new();
  enc_uint(&mut t0, 1, 12);
  enc_packed(&mut t0, 2, &subs);
  let name_payload_start = t0.len() + 2;
  let bad_in_t0 = name_payload_start + 1;
  var badbytes = Vec[UInt8].new();
  badbytes.push((97 as UInt8));
  badbytes.push((1 as UInt8));
  let bad = builder.sb_to_str(&badbytes);
  enc_str(&mut t0, 3, bad);
  let t1 = t_scalar(4);
  var f = Vec[UInt8].new();
  enc_uint(&mut f, 1, 3);
  enc_uint(&mut f, 2, 3);
  let f_prefix = f.len();
  enc_sub(&mut f, 4, &t0);
  let bad_in_f = f_prefix + 2 + bad_in_t0;
  enc_sub(&mut f, 4, &t1);
  let body = f;
  let v = v_int2(0, 12);
  let ps = ps_new(f.len(), 0, 262144, &v, 0, 9);
  let buf = wrap(&ps, &body);
  let r = orc_parse(&buf);
  let want = "orc: field name is not printable at offset " + convert.int_to_string(3 + bad_in_f);
  return expect_orc_err(r, want, "non-printable field name rejected");
}

// Stripe extent pointing past the end of the buffer.
fn t19() -> Int {
  var f = Vec[UInt8].new();
  enc_uint(&mut f, 1, 3);
  let s0 = stripe_info(3, 0, 1000, 0, 0);
  enc_sub(&mut f, 3, &s0);
  let body = f;
  let v = v_int2(0, 12);
  let ps = ps_new(f.len(), 0, 262144, &v, 0, 9);
  let buf = wrap(&ps, &body);
  let r = orc_parse(&buf);
  return expect_orc_err(r, "orc: stripe extends past end of buffer (stripe=0)", "stripe overflow rejected");
}

// Wire type 3 (start group) is rejected with its offset.
fn t20() -> Int {
  var f = Vec[UInt8].new();
  f.push((11 as UInt8));
  let body = f;
  let v = v_int2(0, 12);
  let ps = ps_new(1, 0, 262144, &v, 0, 9);
  let buf = wrap(&ps, &body);
  let r = orc_parse(&buf);
  return expect_orc_err(r, "orc: invalid wire type 3 at offset 3", "group wire type rejected");
}

// Unknown fields with wire types 1 and 5 are skipped.
fn t21() -> Int {
  var f = Vec[UInt8].new();
  enc_tag(&mut f, 9, 1);
  var k = 0;
  while k < 8 {
    f.push((0 as UInt8));
    k = k + 1;
  }
  enc_tag(&mut f, 9, 5);
  var k2 = 0;
  while k2 < 4 {
    f.push((0 as UInt8));
    k2 = k2 + 1;
  }
  enc_uint(&mut f, 5, 42);
  let body = f;
  let v = v_int2(0, 12);
  let ps = ps_new(f.len(), 0, 262144, &v, 0, 9);
  let buf = wrap(&ps, &body);
  let r = orc_parse(&buf);
  if !r.is_ok {
    return report(false, "unknown fields skip (got: " + r.error + ")");
  }
  let o = r.value;
  let rr = orc_rows(&o);
  return report(rr.is_ok && rr.value == 42, "wire types 1 and 5 skipped");
}

// Accessor bounds errors on the minimal file.
fn t22() -> Int {
  let buf = empty_orc();
  let r = orc_parse(&buf);
  if !r.is_ok {
    return report(false, "bounds fixture parses");
  }
  let o = r.value;
  var failed = 0;
  let p1 = orc_version_part(&o, 1);
  if !p1.is_ok || p1.value != 12 {
    failed = failed + report(false, "accessors: version part 1");
  }
  failed = failed + expect_int_err(orc_version_part(&o, 5), "orc: version part index out of range", "accessors: version bounds");
  failed = failed + expect_int_err(orc_stripe_offset(&o, 0), "orc: stripe index out of range", "accessors: stripe bounds");
  failed = failed + expect_int_err(orc_column_kind(&o, 0), "orc: column index out of range", "accessors: column bounds");
  failed = failed + expect_int_err(orc_stream_kind(&o, 0, 0), "orc: stripe index out of range", "accessors: stream stripe bounds");
  if failed == 0 {
    return report(true, "accessor bounds errors");
  }
  return 1;
}

// Unpacked version parts and an unpacked single subtype are accepted.
fn t23() -> Int {
  let subs = v_int2(1, 2);
  let names = v_str2("a", "b");
  let t0 = t_struct(&subs, &names);
  var t1 = Vec[UInt8].new();
  enc_uint(&mut t1, 1, 10);
  enc_uint(&mut t1, 2, 2);
  let t2 = t_scalar(7);
  var f = Vec[UInt8].new();
  enc_uint(&mut f, 1, 3);
  enc_uint(&mut f, 2, 3);
  enc_sub(&mut f, 4, &t0);
  enc_sub(&mut f, 4, &t1);
  enc_sub(&mut f, 4, &t2);
  var ps = Vec[UInt8].new();
  enc_uint(&mut ps, 1, f.len());
  enc_uint(&mut ps, 2, 0);
  enc_uint(&mut ps, 3, 262144);
  enc_uint(&mut ps, 4, 0);
  enc_uint(&mut ps, 4, 12);
  enc_uint(&mut ps, 5, 0);
  enc_uint(&mut ps, 6, 9);
  enc_str(&mut ps, 8000, "ORC");
  let body = f;
  let buf = wrap(&ps, &body);
  let r = orc_parse(&buf);
  if !r.is_ok {
    return report(false, "unpacked fixture parses (got: " + r.error + ")");
  }
  let o = r.value;
  var failed = 0;
  if orc_version_major(&o) != 0 || orc_version_minor(&o) != 12 {
    failed = failed + report(false, "unpacked: version parts");
  }
  let k1 = orc_column_kind(&o, 1);
  let sc = orc_column_subtype_count(&o, 1);
  let sv = orc_column_subtype(&o, 1, 0);
  if !k1.is_ok || k1.value != 10 {
    failed = failed + report(false, "unpacked: list kind");
  }
  if !sc.is_ok || sc.value != 1 || !sv.is_ok || sv.value != 2 {
    failed = failed + report(false, "unpacked: single subtype");
  }
  if failed == 0 {
    return report(true, "packed and unpacked repeated fields");
  }
  return 1;
}

// Documented name tables.
fn t24() -> Int {
  var failed = 0;
  if !str_eq(orc_compression_name(3), "LZ4") || !str_eq(orc_compression_name(4), "ZSTD") {
    failed = failed + report(false, "names: compression table");
  }
  if !str_eq(orc_compression_name(99), "unknown") {
    failed = failed + report(false, "names: unknown compression");
  }
  if !str_eq(orc_column_kind_name(14), "DECIMAL") || !str_eq(orc_column_kind_name(15), "DATE") {
    failed = failed + report(false, "names: decimal/date");
  }
  if !str_eq(orc_column_kind_name(9), "TIMESTAMP") || !str_eq(orc_column_kind_name(13), "UNION") {
    failed = failed + report(false, "names: timestamp/union");
  }
  if !str_eq(orc_column_kind_name(10), "LIST") || !str_eq(orc_column_kind_name(11), "MAP") {
    failed = failed + report(false, "names: list/map");
  }
  if !str_eq(orc_column_kind_name(18), "TIMESTAMP_INSTANT") || !str_eq(orc_column_kind_name(99), "unknown") {
    failed = failed + report(false, "names: instant/unknown");
  }
  if !str_eq(orc_stream_kind_name(3), "DICTIONARY_DATA") || !str_eq(orc_stream_kind_name(8), "BLOOM_FILTER_UTF8") {
    failed = failed + report(false, "names: stream kinds");
  }
  if !str_eq(orc_writer_version_name(0), "ORIGINAL") || !str_eq(orc_writer_version_name(9), "ORC_14") {
    failed = failed + report(false, "names: writer versions");
  }
  if !str_eq(orc_writer_version_name(99), "unknown") || !str_eq(orc_stream_kind_name(99), "unknown") {
    failed = failed + report(false, "names: unknown fallbacks");
  }
  if failed == 0 {
    return report(true, "name tables");
  }
  return 1;
}

// Integration: schema tree, stripe with streams, statistics, metadata.
fn t25() -> Int {
  var names = Vec[Str].new();
  names.push("id");
  names.push("tag");
  names.push("price");
  names.push("when");
  names.push("code");
  names.push("day");
  var subs = Vec[Int].new();
  subs.push(1);
  subs.push(2);
  subs.push(3);
  subs.push(4);
  subs.push(5);
  subs.push(6);
  let t0 = t_struct(&subs, &names);
  let t1 = t_scalar(4);
  let t2 = t_scalar(7);
  let t3 = t_decimal(10, 2);
  let t4 = t_scalar(9);
  let t5 = t_varchar(20);
  let t6 = t_scalar(15);
  var sf = Vec[UInt8].new();
  let st0 = stream_info(1, 1, 5);
  let st1 = stream_info(0, 0, 1);
  enc_sub(&mut sf, 1, &st0);
  enc_sub(&mut sf, 1, &st1);
  let stripe_bytes = 10 + sf.len();
  var body = Vec[UInt8].new();
  var zz = 0;
  while zz < 10 {
    body.push((0 as UInt8));
    zz = zz + 1;
  }
  push_bytes(&mut body, &sf);
  var f = Vec[UInt8].new();
  enc_uint(&mut f, 1, 3);
  enc_uint(&mut f, 2, 3 + stripe_bytes);
  let s0 = stripe_info(3, 4, 6, sf.len(), 7);
  enc_sub(&mut f, 3, &s0);
  enc_sub(&mut f, 4, &t0);
  enc_sub(&mut f, 4, &t1);
  enc_sub(&mut f, 4, &t2);
  enc_sub(&mut f, 4, &t3);
  enc_sub(&mut f, 4, &t4);
  enc_sub(&mut f, 4, &t5);
  enc_sub(&mut f, 4, &t6);
  enc_uint(&mut f, 5, 7);
  let cst = Vec[UInt8].new();
  enc_sub(&mut f, 6, &cst);
  enc_sub(&mut f, 6, &cst);
  let flen = f.len();
  push_bytes(&mut body, &f);
  let cstat = Vec[UInt8].new();
  var ss0 = Vec[UInt8].new();
  enc_sub(&mut ss0, 1, &cstat);
  enc_sub(&mut ss0, 1, &cstat);
  var m = Vec[UInt8].new();
  enc_sub(&mut m, 1, &ss0);
  let mlen = m.len();
  push_bytes(&mut body, &m);
  let v = v_int2(0, 12);
  let ps = ps_new(flen, 0, 262144, &v, mlen, 9);
  let buf = wrap(&ps, &body);
  let r = orc_parse(&buf);
  if !r.is_ok {
    return report(false, "integration fixture parses (got: " + r.error + ")");
  }
  let o = r.value;
  var failed = 0;
  let cc = orc_columns(&o);
  if !cc.is_ok || cc.value != 7 {
    failed = failed + report(false, "integration: seven columns");
  }
  let k3 = orc_column_kind(&o, 3);
  let k5 = orc_column_kind(&o, 5);
  if !k3.is_ok || k3.value != 14 {
    failed = failed + report(false, "integration: decimal column");
  }
  if !k5.is_ok || k5.value != 16 {
    failed = failed + report(false, "integration: varchar column");
  }
  let pr = orc_column_precision(&o, 3);
  let sc = orc_column_scale(&o, 3);
  let ml = orc_column_max_length(&o, 5);
  if !pr.is_ok || pr.value != 10 || !sc.is_ok || sc.value != 2 {
    failed = failed + report(false, "integration: decimal precision/scale");
  }
  if !ml.is_ok || ml.value != 20 {
    failed = failed + report(false, "integration: varchar max length");
  }
  let fc = orc_column_field_count(&o, 0);
  let nm = orc_column_field_name(&o, 0, 2);
  if !fc.is_ok || fc.value != 6 {
    failed = failed + report(false, "integration: field count");
  }
  if !nm.is_ok || !str_eq(nm.value, "price") {
    failed = failed + report(false, "integration: field name");
  }
  if orc_footer_offset(&o) != 3 + stripe_bytes {
    failed = failed + report(false, "integration: footer offset");
  }
  let rr = orc_rows(&o);
  if !rr.is_ok || rr.value != 7 {
    failed = failed + report(false, "integration: rows");
  }
  let tc = orc_stream_count(&o);
  let sk = orc_stream_kind(&o, 0, 0);
  let so = orc_stream_offset(&o, 0, 1);
  let sl = orc_stream_length(&o, 0, 0);
  if !tc.is_ok || tc.value != 2 {
    failed = failed + report(false, "integration: stream count");
  }
  if !sk.is_ok || sk.value != 1 {
    failed = failed + report(false, "integration: stream kind");
  }
  if !so.is_ok || so.value != 5 || !sl.is_ok || sl.value != 5 {
    failed = failed + report(false, "integration: stream offset/length");
  }
  let stc = orc_stats_count(&o);
  let h0 = orc_column_has_stats(&o, 0);
  let h6 = orc_column_has_stats(&o, 6);
  if !stc.is_ok || stc.value != 2 {
    failed = failed + report(false, "integration: stats count");
  }
  if !h0.is_ok || !h0.value || !h6.is_ok || h6.value {
    failed = failed + report(false, "integration: stats flags");
  }
  let mc = orc_stripe_stats_cols(&o, 0);
  if !mc.is_ok || mc.value != 2 {
    failed = failed + report(false, "integration: stripe stats cols");
  }
  if failed == 0 {
    return report(true, "full metadata integration");
  }
  return 1;
}

// Single-name helper kept separate to keep t16 readable.
fn v_int_names_one() -> Vec[Str] {
  var v = Vec[Str].new();
  v.push("a");
  return v;
}

// --------------------------------------------------
//  Main
// --------------------------------------------------

fn main() -> Int {
  io.println("=== xiom.orc conformance tests ===");
  var failed = 0;
  failed = failed + t1();
  failed = failed + t2();
  failed = failed + t3();
  failed = failed + t4();
  failed = failed + t5();
  failed = failed + t6();
  failed = failed + t7();
  failed = failed + t8();
  failed = failed + t9();
  failed = failed + t10();
  failed = failed + t11();
  failed = failed + t12();
  failed = failed + t13();
  failed = failed + t14();
  failed = failed + t15();
  failed = failed + t16();
  failed = failed + t17();
  failed = failed + t18();
  failed = failed + t19();
  failed = failed + t20();
  failed = failed + t21();
  failed = failed + t22();
  failed = failed + t23();
  failed = failed + t24();
  failed = failed + t25();
  if failed == 0 {
    io.println("xiom.orc: all tests passed");
  }
  return failed;
}
