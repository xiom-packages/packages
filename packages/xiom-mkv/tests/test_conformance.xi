// XIOM -- xiom.mkv conformance tests (20 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Every fixture is a synthetic Matroska/WebM byte stream assembled in-test
// from small helpers (VINT encoders, element builders, an EBML-header
// builder); no external data files are read. The suite covers: VINT ID and
// size encode/decode including multi-byte widths and the unknown-size
// sentinel; malformed VINTs (zero first byte, reserved all-zero data, more
// than 8 bytes, truncation); the EBML header fields and DocType validation;
// Info defaults and full Info parsing (TimestampScale, Float Duration in
// both 4- and 8-byte encodings, MuxingApp, WritingApp, UTF-8 Title); track
// records (video, audio, multiple entries, LanguageIETF); known-size and
// unknown-size Cluster skipping; refusal of truncated/unknown-size elements,
// bad integer widths, bad floats, bad text and bad TimestampScale; and the
// out-of-range behavior of every accessor.
//
// Discipline (compiler v0.61.3): every Vec element read is bound to a typed
// local, every Str equality goes through xiom.string.compare.str_compare,
// every UInt8 read is widened with `& 0xFF`, and Ok/Err are only constructed
// through the tiny leaf helpers below.

module mkv_tests
use xiom.io; use xiom.test;
use xiom.mkv;
use xiom.string;
use xiom.string.compare;

// --------------------------------------------------
//  Comparison helpers
// --------------------------------------------------

fn str_eq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn err_file_is(r: Result[MkvFile, Str], want: Str) -> Bool {
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

// True when `s`'s bytes are exactly `want`; avoids relying on Str literals
// for non-ASCII text.
fn str_bytes_eq(s: Str, want: Vec[UInt8]) -> Bool {
  if string.byte_count(s) != want.len() {
    return false;
  }
  var i = 0;
  while i < want.len() {
    let w: UInt8 = want[i];
    let b: Int = (string.byte_at(s, i) as Int) & 0xFF;
    if b != ((w as Int) & 0xFF) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// --------------------------------------------------
//  Byte building helpers
// --------------------------------------------------

fn push_byte(v: &mut Vec[UInt8], b: Int) {
  v.push(b as UInt8);
}

fn push_bytes(v: &mut Vec[UInt8], b: &Vec[UInt8]) {
  var i = 0;
  while i < b.len() {
    v.push(b[i]);
    i = i + 1;
  }
}

// 2^k.
fn pow2(k: Int) -> Int {
  var p = 1;
  var i = 0;
  while i < k {
    p = p * 2;
    i = i + 1;
  }
  return p;
}

// Byte `k` (0 = least significant) of the non-negative value `v`.
fn shift_byte(v: Int, k: Int) -> Int {
  var q = v;
  var i = 0;
  while i < k {
    q = q / 256;
    i = i + 1;
  }
  return q % 256;
}

// Append the low `width` bytes of `value` in big-endian order.
fn push_be(v: &mut Vec[UInt8], value: Int, width: Int) {
  var i = width - 1;
  while i >= 0 {
    push_byte(v, shift_byte(value, i));
    i = i - 1;
  }
}

// Smallest VINT size width (1..8) that can carry `v` without hitting the
// all-ones unknown-size pattern: v <= 2^(7w) - 2.
fn size_width_for(v: Int) -> Int {
  var w = 1;
  while w < 8 {
    if v <= pow2(7 * w) - 2 {
      return w;
    }
    w = w + 1;
  }
  return 8;
}

// Encode `v` as an EBML size VINT (unknown-size sentinel not used).
fn enc_size(v: Int) -> Vec[UInt8] {
  let w = size_width_for(v);
  var out = Vec[UInt8].new();
  push_be(&mut out, v + pow2(7 * w), w);
  return out;
}

// Encode the unknown-size sentinel of `w` bytes: marker bits plus all data
// bits one (0xFF, 0x7FFF, 0x3FFFFF, ...).
fn enc_unknown_size(w: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  let marker = pow2(7 * w);
  push_be(&mut out, marker + marker - 1, w);
  return out;
}

// Encode an element ID as its natural big-endian bytes (marker bits kept):
// the width is the one whose marker range [2^(7w), 2^(8w)) contains `id`.
fn enc_id(id: Int) -> Vec[UInt8] {
  var w = 1;
  var lo = 128;
  var hi = 256;
  while w < 4 {
    if id >= lo && id < hi {
      var out = Vec[UInt8].new();
      push_be(&mut out, id, w);
      return out;
    }
    w = w + 1;
    lo = lo * 128;
    hi = hi * 256;
  }
  var out = Vec[UInt8].new();
  push_be(&mut out, id, 4);
  return out;
}

// One complete element: ID VINT + size VINT + body.
fn elem(id: Int, body: &Vec[UInt8]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  let idb = enc_id(id);
  push_bytes(&mut out, &idb);
  let sb = enc_size(body.len());
  push_bytes(&mut out, &sb);
  push_bytes(&mut out, body);
  return out;
}

// One element whose size uses the 1-byte unknown-size sentinel.
fn elem_unknown(id: Int, body: &Vec[UInt8]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  let idb = enc_id(id);
  push_bytes(&mut out, &idb);
  push_byte(&mut out, 255);
  push_bytes(&mut out, body);
  return out;
}

// Unsigned big-endian integer body of `width` bytes.
fn uint_body(v: Int, width: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  push_be(&mut out, v, width);
  return out;
}

// ASCII/UTF-8 body of a Str.
fn bytes_of(s: Str) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < string.byte_count(s) {
    let b: Int = (string.byte_at(s, i) as Int) & 0xFF;
    push_byte(&mut out, b);
    i = i + 1;
  }
  return out;
}

// First `n` bytes of `v` (fewer when `v` is shorter).
fn prefix_of(v: &Vec[UInt8], n: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < n && i < v.len() {
    out.push(v[i]);
    i = i + 1;
  }
  return out;
}

// --------------------------------------------------
//  Fixture builders
// --------------------------------------------------

// Standard EBML header: version 1, read version 1, max id 4, max size 8,
// the given DocType, DocTypeVersion 4, DocTypeReadVersion 2.
fn std_header(doctype: Str) -> Vec[UInt8] {
  var body = Vec[UInt8].new();
  let b1 = uint_body(1, 1);
  let e1 = elem(0x4286, &b1);
  push_bytes(&mut body, &e1);
  let b2 = uint_body(1, 1);
  let e2 = elem(0x42F7, &b2);
  push_bytes(&mut body, &e2);
  let b3 = uint_body(4, 1);
  let e3 = elem(0x42F2, &b3);
  push_bytes(&mut body, &e3);
  let b4 = uint_body(8, 1);
  let e4 = elem(0x42F3, &b4);
  push_bytes(&mut body, &e4);
  let b5 = bytes_of(doctype);
  let e5 = elem(0x4282, &b5);
  push_bytes(&mut body, &e5);
  let b6 = uint_body(4, 1);
  let e6 = elem(0x4287, &b6);
  push_bytes(&mut body, &e6);
  let b7 = uint_body(2, 1);
  let e7 = elem(0x4288, &b7);
  push_bytes(&mut body, &e7);
  return elem(0x1A45DFA3, &body);
}

// header + Segment(segment_body), the Segment with a known size.
fn std_file(hdr: Vec[UInt8], segment_body: Vec[UInt8]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  push_bytes(&mut out, &hdr);
  let seg = elem(0x18538067, &segment_body);
  push_bytes(&mut out, &seg);
  return out;
}

fn info_elem(body: &Vec[UInt8]) -> Vec[UInt8] {
  return elem(0x1549A966, body);
}

fn tracks_elem(body: &Vec[UInt8]) -> Vec[UInt8] {
  return elem(0x1654AE6B, body);
}

fn track_entry_elem(body: &Vec[UInt8]) -> Vec[UInt8] {
  return elem(0xAE, body);
}

fn cluster_elem(body: &Vec[UInt8]) -> Vec[UInt8] {
  return elem(0x1F43B675, body);
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  var ok = true;
  var b1 = Vec[UInt8].new();
  push_byte(&mut b1, 0xAE);
  let r1 = mkv_vint_id(&b1, 0);
  if !r1.is_ok { ok = false; } else {
    let v: Int = r1.value;
    if v != 0xAE { ok = false; }
  }
  if mkv_vint_width(&b1, 0) != 1 { ok = false; }
  var b2 = Vec[UInt8].new();
  push_byte(&mut b2, 0x1A);
  push_byte(&mut b2, 0x45);
  push_byte(&mut b2, 0xDF);
  push_byte(&mut b2, 0xA3);
  let r2 = mkv_vint_id(&b2, 0);
  if !r2.is_ok { ok = false; } else {
    let v: Int = r2.value;
    if v != 0x1A45DFA3 { ok = false; }
  }
  let w2 = mkv_vint_id_width(&b2, 0);
  if !w2.is_ok { ok = false; } else {
    let v: Int = w2.value;
    if v != 4 { ok = false; }
  }
  var b3 = Vec[UInt8].new();
  push_byte(&mut b3, 0x22);
  push_byte(&mut b3, 0xB5);
  push_byte(&mut b3, 0x9C);
  let r3 = mkv_vint_id(&b3, 0);
  if !r3.is_ok { ok = false; } else {
    let v: Int = r3.value;
    if v != 0x22B59C { ok = false; }
  }
  var b4 = Vec[UInt8].new();
  push_byte(&mut b4, 0xEC);
  let r4 = mkv_vint_id(&b4, 0);
  if !r4.is_ok { ok = false; } else {
    let v: Int = r4.value;
    if v != 0xEC { ok = false; }
  }
  return assert(ok, "vint_id: 1/3/4-byte IDs keep marker bits");
}

fn t2() -> TestResult {
  var ok = true;
  var b1 = Vec[UInt8].new();
  push_byte(&mut b1, 0x81);
  let r1 = mkv_vint_size(&b1, 0);
  if !r1.is_ok { ok = false; } else {
    let v: Int = r1.value;
    if v != 1 { ok = false; }
  }
  var b2 = Vec[UInt8].new();
  push_byte(&mut b2, 0xBF);
  let r2 = mkv_vint_size(&b2, 0);
  if !r2.is_ok { ok = false; } else {
    let v: Int = r2.value;
    if v != 63 { ok = false; }
  }
  var b3 = Vec[UInt8].new();
  push_byte(&mut b3, 0x40);
  push_byte(&mut b3, 0x7F);
  let r3 = mkv_vint_size(&b3, 0);
  if !r3.is_ok { ok = false; } else {
    let v: Int = r3.value;
    if v != 127 { ok = false; }
  }
  let w3 = mkv_vint_size_width(&b3, 0);
  if !w3.is_ok { ok = false; } else {
    let v: Int = w3.value;
    if v != 2 { ok = false; }
  }
  var b4 = Vec[UInt8].new();
  push_byte(&mut b4, 0x20);
  push_byte(&mut b4, 0x00);
  push_byte(&mut b4, 0x01);
  let r4 = mkv_vint_size(&b4, 0);
  if !r4.is_ok { ok = false; } else {
    let v: Int = r4.value;
    if v != 1 { ok = false; }
  }
  var b5 = Vec[UInt8].new();
  push_byte(&mut b5, 0x10);
  push_byte(&mut b5, 0x00);
  push_byte(&mut b5, 0x00);
  push_byte(&mut b5, 0x00);
  let r5 = mkv_vint_size(&b5, 0);
  if !r5.is_ok { ok = false; } else {
    let v: Int = r5.value;
    if v != 0 { ok = false; }
  }
  return assert(ok, "vint_size: marker stripped for 1..4-byte sizes");
}

fn t3() -> TestResult {
  var ok = true;
  var b1 = Vec[UInt8].new();
  push_byte(&mut b1, 0xFF);
  let r1 = mkv_vint_size(&b1, 0);
  if !r1.is_ok { ok = false; } else {
    let v: Int = r1.value;
    if v != -1 { ok = false; }
  }
  var b2 = Vec[UInt8].new();
  push_byte(&mut b2, 0x7F);
  push_byte(&mut b2, 0xFF);
  let r2 = mkv_vint_size(&b2, 0);
  if !r2.is_ok { ok = false; } else {
    let v: Int = r2.value;
    if v != -1 { ok = false; }
  }
  let w2 = mkv_vint_size_width(&b2, 0);
  if !w2.is_ok { ok = false; } else {
    let v: Int = w2.value;
    if v != 2 { ok = false; }
  }
  var b3 = Vec[UInt8].new();
  push_byte(&mut b3, 0x3F);
  push_byte(&mut b3, 0xFF);
  push_byte(&mut b3, 0xFF);
  let r3 = mkv_vint_size(&b3, 0);
  if !r3.is_ok { ok = false; } else {
    let v: Int = r3.value;
    if v != -1 { ok = false; }
  }
  var b4 = Vec[UInt8].new();
  push_byte(&mut b4, 0x0F);
  push_byte(&mut b4, 0xFF);
  push_byte(&mut b4, 0xFF);
  push_byte(&mut b4, 0xFF);
  push_byte(&mut b4, 0xFF);
  push_byte(&mut b4, 0xFF);
  push_byte(&mut b4, 0xFF);
  push_byte(&mut b4, 0xFF);
  let r4 = mkv_vint_size(&b4, 0);
  if !r4.is_ok { ok = false; } else {
    let v: Int = r4.value;
    if v != -1 { ok = false; }
  }
  var b5 = Vec[UInt8].new();
  push_byte(&mut b5, 0x01);
  push_byte(&mut b5, 0x00);
  push_byte(&mut b5, 0x00);
  push_byte(&mut b5, 0x00);
  push_byte(&mut b5, 0x00);
  push_byte(&mut b5, 0x00);
  push_byte(&mut b5, 0x00);
  push_byte(&mut b5, 0x05);
  let r5 = mkv_vint_size(&b5, 0);
  if !r5.is_ok { ok = false; } else {
    let v: Int = r5.value;
    if v != 5 { ok = false; }
  }
  return assert(ok, "vint_size: unknown-size sentinel and 8-byte sizes");
}

fn t4() -> TestResult {
  var ok = true;
  var b1 = Vec[UInt8].new();
  push_byte(&mut b1, 0x00);
  if !err_int_is(mkv_vint_id(&b1, 0), "mkv: invalid vint") { ok = false; }
  if !err_int_is(mkv_vint_size(&b1, 0), "mkv: invalid vint") { ok = false; }
  var b2 = Vec[UInt8].new();
  push_byte(&mut b2, 0x80);
  if !err_int_is(mkv_vint_id(&b2, 0), "mkv: invalid vint") { ok = false; }
  let sz = mkv_vint_size(&b2, 0);
  if !sz.is_ok { ok = false; } else {
    let v: Int = sz.value;
    if v != 0 { ok = false; }
  }
  var b3 = Vec[UInt8].new();
  push_byte(&mut b3, 0x40);
  push_byte(&mut b3, 0x00);
  if !err_int_is(mkv_vint_id(&b3, 0), "mkv: invalid vint") { ok = false; }
  var b4 = Vec[UInt8].new();
  push_byte(&mut b4, 0x40);
  if !err_int_is(mkv_vint_id(&b4, 0), "mkv: truncated vint") { ok = false; }
  if !err_int_is(mkv_vint_size(&b4, 0), "mkv: truncated vint") { ok = false; }
  let empty = Vec[UInt8].new();
  if !err_int_is(mkv_vint_id(&empty, 0), "mkv: truncated vint") { ok = false; }
  if !err_int_is(mkv_vint_id(&b4, 9), "mkv: truncated vint") { ok = false; }
  if mkv_vint_width(&b4, 9) != 0 { ok = false; }
  if mkv_vint_width(&b4, -1) != 0 { ok = false; }
  return assert(ok, "vint: zero first byte, reserved pattern, truncation");
}

fn t5() -> TestResult {
  let hdr = std_header("matroska");
  let empty = Vec[UInt8].new();
  let file = std_file(hdr, empty);
  var ok = mkv_is_file(&file);
  var short = Vec[UInt8].new();
  push_byte(&mut short, 0x1A);
  push_byte(&mut short, 0x45);
  push_byte(&mut short, 0xDF);
  push_byte(&mut short, 0xA3);
  if mkv_is_file(&short) { ok = false; }
  let nothing = Vec[UInt8].new();
  if mkv_is_file(&nothing) { ok = false; }
  var zero = Vec[UInt8].new();
  push_byte(&mut zero, 0x00);
  push_byte(&mut zero, 0x00);
  push_byte(&mut zero, 0x00);
  push_byte(&mut zero, 0x00);
  push_byte(&mut zero, 0x00);
  if mkv_is_file(&zero) { ok = false; }
  var sniff = Vec[UInt8].new();
  push_byte(&mut sniff, 0x1A);
  push_byte(&mut sniff, 0x45);
  push_byte(&mut sniff, 0xDF);
  push_byte(&mut sniff, 0xA3);
  push_byte(&mut sniff, 0x00);
  if !mkv_is_file(&sniff) { ok = false; }
  return assert(ok, "is_file: EBML ID sniff and 5-byte minimum");
}

fn t6() -> TestResult {
  let hdr = std_header("matroska");
  let hdr_len = hdr.len();
  let empty = Vec[UInt8].new();
  let info = info_elem(&empty);
  let seg_body = info;
  let seg = elem(0x18538067, &seg_body);
  let file = std_file(hdr, seg_body);
  let r = mkv_parse(&file);
  if !r.is_ok {
    return assert(false, "header: minimal matroska file parses");
  }
  let f = r.value;
  var ok = true;
  if mkv_segment_offset(&f) != hdr_len { ok = false; }
  if mkv_segment_size(&f) != info.len() { ok = false; }
  if mkv_ebml_version(&f) != 1 { ok = false; }
  if mkv_ebml_read_version(&f) != 1 { ok = false; }
  if mkv_ebml_max_id_length(&f) != 4 { ok = false; }
  if mkv_ebml_max_size_length(&f) != 8 { ok = false; }
  if !str_eq(mkv_doctype(&f), "matroska") { ok = false; }
  if mkv_doctype_version(&f) != 4 { ok = false; }
  if mkv_doctype_read_version(&f) != 2 { ok = false; }
  if mkv_info_offset(&f) != file.len() - info.len() { ok = false; }
  if mkv_timestamp_scale(&f) != 1000000 { ok = false; }
  if mkv_track_count(&f) != 0 { ok = false; }
  if mkv_cluster_count(&f) != 0 { ok = false; }
  if seg.len() == 0 { ok = false; }
  return assert(ok, "ebml header: fields, segment offset/size, info offset");
}

fn t7() -> TestResult {
  var ok = true;
  let webm_hdr = std_header("webm");
  let empty1 = Vec[UInt8].new();
  let webm_file = std_file(webm_hdr, empty1);
  let wr = mkv_parse(&webm_file);
  if !wr.is_ok { ok = false; } else {
    let wf = wr.value;
    if !str_eq(mkv_doctype(&wf), "webm") { ok = false; }
  }
  let bad_hdr = std_header("quicktime");
  let empty2 = Vec[UInt8].new();
  let bad_file = std_file(bad_hdr, empty2);
  if !err_file_is(mkv_parse(&bad_file), "mkv: bad doctype") { ok = false; }
  var no_dt_body = Vec[UInt8].new();
  let nv = uint_body(1, 1);
  let ne = elem(0x4286, &nv);
  push_bytes(&mut no_dt_body, &ne);
  let no_dt_hdr = elem(0x1A45DFA3, &no_dt_body);
  let empty3 = Vec[UInt8].new();
  let no_dt_file = std_file(no_dt_hdr, empty3);
  if !err_file_is(mkv_parse(&no_dt_file), "mkv: bad doctype") { ok = false; }
  var empty_dt_body = Vec[UInt8].new();
  let ev = uint_body(1, 1);
  let ee = elem(0x4286, &ev);
  push_bytes(&mut empty_dt_body, &ee);
  var nothing = Vec[UInt8].new();
  let edt = elem(0x4282, &nothing);
  push_bytes(&mut empty_dt_body, &edt);
  let empty_dt_hdr = elem(0x1A45DFA3, &empty_dt_body);
  let empty_dt_file = std_file(empty_dt_hdr, nothing);
  if !err_file_is(mkv_parse(&empty_dt_file), "mkv: bad doctype") { ok = false; }
  var rv_body = Vec[UInt8].new();
  let rv = uint_body(2, 1);
  let rve = elem(0x42F7, &rv);
  push_bytes(&mut rv_body, &rve);
  let dtb = bytes_of("matroska");
  let dte = elem(0x4282, &dtb);
  push_bytes(&mut rv_body, &dte);
  let rv_hdr = elem(0x1A45DFA3, &rv_body);
  let empty4 = Vec[UInt8].new();
  let rv_file = std_file(rv_hdr, empty4);
  if !err_file_is(mkv_parse(&rv_file), "mkv: unsupported ebml version") { ok = false; }
  return assert(ok, "doctype: webm accepted, bad/missing/empty rejected");
}

fn t8() -> TestResult {
  var ok = true;
  let hdr = std_header("matroska");
  let empty = Vec[UInt8].new();
  let info = info_elem(&empty);
  let with_info = std_file(hdr, info);
  let r = mkv_parse(&with_info);
  if !r.is_ok { ok = false; } else {
    let f = r.value;
    if mkv_timestamp_scale(&f) != 1000000 { ok = false; }
    if mkv_duration_milli_units(&f) != -1 { ok = false; }
    if mkv_duration_nanos(&f) != -1 { ok = false; }
    if mkv_duration_millis(&f) != -1 { ok = false; }
    if !str_eq(mkv_muxing_app(&f), "") { ok = false; }
    if !str_eq(mkv_writing_app(&f), "") { ok = false; }
    if !str_eq(mkv_title(&f), "") { ok = false; }
  }
  let hdr2 = std_header("matroska");
  let none = Vec[UInt8].new();
  let without_info = std_file(hdr2, none);
  let r2 = mkv_parse(&without_info);
  if !r2.is_ok { ok = false; } else {
    let f2 = r2.value;
    if mkv_info_offset(&f2) != -1 { ok = false; }
    if mkv_timestamp_scale(&f2) != 1000000 { ok = false; }
  }
  return assert(ok, "info: defaults with empty or absent Info element");
}

fn t9() -> TestResult {
  var body = Vec[UInt8].new();
  let ts = uint_body(100000, 3);
  let tse = elem(0x2AD7B1, &ts);
  push_bytes(&mut body, &tse);
  var f32 = Vec[UInt8].new();
  push_byte(&mut f32, 0x44);
  push_byte(&mut f32, 0x9A);
  push_byte(&mut f32, 0x50);
  push_byte(&mut f32, 0x00);
  let de = elem(0x4489, &f32);
  push_bytes(&mut body, &de);
  let ma = bytes_of("libmak");
  let mae = elem(0x4D80, &ma);
  push_bytes(&mut body, &mae);
  let wa = bytes_of("xiom.mkv");
  let wae = elem(0x5741, &wa);
  push_bytes(&mut body, &wae);
  var title = Vec[UInt8].new();
  push_byte(&mut title, 0x43);
  push_byte(&mut title, 0x61);
  push_byte(&mut title, 0x66);
  push_byte(&mut title, 0xC3);
  push_byte(&mut title, 0xA9);
  let te = elem(0x7BA9, &title);
  push_bytes(&mut body, &te);
  let unk = uint_body(7, 1);
  let unke = elem(0x1F123456, &unk);
  push_bytes(&mut body, &unke);
  let info = info_elem(&body);
  let hdr = std_header("matroska");
  let file = std_file(hdr, info);
  let r = mkv_parse(&file);
  if !r.is_ok {
    return assert(false, "info: full Info element parses");
  }
  let f = r.value;
  var ok = true;
  if mkv_timestamp_scale(&f) != 100000 { ok = false; }
  if mkv_duration_milli_units(&f) != 1234500 { ok = false; }
  if mkv_duration_nanos(&f) != 123450000 { ok = false; }
  if mkv_duration_millis(&f) != 123450 { ok = false; }
  if !str_eq(mkv_muxing_app(&f), "libmak") { ok = false; }
  if !str_eq(mkv_writing_app(&f), "xiom.mkv") { ok = false; }
  if !str_bytes_eq(mkv_title(&f), title) { ok = false; }
  return assert(ok, "info: TimestampScale, Duration, apps, UTF-8 Title");
}

fn t10() -> TestResult {
  var ok = true;
  // float32 48000.0 -> 48000000 milliHz; float64 48000.0 -> same.
  var b1 = Vec[UInt8].new();
  let t1v = uint_body(1000000, 3);
  let t1e = elem(0x2AD7B1, &t1v);
  push_bytes(&mut b1, &t1e);
  var s1 = Vec[UInt8].new();
  push_byte(&mut s1, 0x47);
  push_byte(&mut s1, 0x3B);
  push_byte(&mut s1, 0x80);
  push_byte(&mut s1, 0x00);
  let d1 = elem(0x4489, &s1);
  push_bytes(&mut b1, &d1);
  let f1 = std_file(std_header("matroska"), info_elem(&b1));
  let r1 = mkv_parse(&f1);
  if !r1.is_ok { ok = false; } else {
    let f = r1.value;
    if mkv_duration_milli_units(&f) != 48000000 { ok = false; }
    if mkv_duration_nanos(&f) != 48000000000 { ok = false; }
  }
  var b2 = Vec[UInt8].new();
  var s2 = Vec[UInt8].new();
  push_byte(&mut s2, 0x40);
  push_byte(&mut s2, 0xE7);
  push_byte(&mut s2, 0x70);
  push_byte(&mut s2, 0x00);
  push_byte(&mut s2, 0x00);
  push_byte(&mut s2, 0x00);
  push_byte(&mut s2, 0x00);
  push_byte(&mut s2, 0x00);
  let d2 = elem(0x4489, &s2);
  push_bytes(&mut b2, &d2);
  let f2 = std_file(std_header("matroska"), info_elem(&b2));
  let r2 = mkv_parse(&f2);
  if !r2.is_ok { ok = false; } else {
    let f = r2.value;
    if mkv_duration_milli_units(&f) != 48000000 { ok = false; }
  }
  var b3 = Vec[UInt8].new();
  var s3 = Vec[UInt8].new();
  push_byte(&mut s3, 0x3F);
  push_byte(&mut s3, 0x00);
  push_byte(&mut s3, 0x00);
  push_byte(&mut s3, 0x00);
  let d3 = elem(0x4489, &s3);
  push_bytes(&mut b3, &d3);
  let f3 = std_file(std_header("matroska"), info_elem(&b3));
  let r3 = mkv_parse(&f3);
  if !r3.is_ok { ok = false; } else {
    let f = r3.value;
    if mkv_duration_milli_units(&f) != 500 { ok = false; }
  }
  var b4 = Vec[UInt8].new();
  var s4 = Vec[UInt8].new();
  push_byte(&mut s4, 0xBF);
  push_byte(&mut s4, 0x00);
  push_byte(&mut s4, 0x00);
  push_byte(&mut s4, 0x00);
  let d4 = elem(0x4489, &s4);
  push_bytes(&mut b4, &d4);
  let f4 = std_file(std_header("matroska"), info_elem(&b4));
  let r4 = mkv_parse(&f4);
  if !r4.is_ok { ok = false; } else {
    let f = r4.value;
    if mkv_duration_milli_units(&f) != -500 { ok = false; }
  }
  var b5 = Vec[UInt8].new();
  var s5 = Vec[UInt8].new();
  let d5 = elem(0x4489, &s5);
  push_bytes(&mut b5, &d5);
  let f5 = std_file(std_header("matroska"), info_elem(&b5));
  let r5 = mkv_parse(&f5);
  if !r5.is_ok { ok = false; } else {
    let f = r5.value;
    if mkv_duration_milli_units(&f) != 0 { ok = false; }
  }
  return assert(ok, "info: Float Duration decodes in 4- and 8-byte forms");
}

fn t11() -> TestResult {
  var body = Vec[UInt8].new();
  let n = uint_body(1, 1);
  let ne = elem(0xD7, &n);
  push_bytes(&mut body, &ne);
  let u = uint_body(0x1234567890, 5);
  let ue = elem(0x73C5, &u);
  push_bytes(&mut body, &ue);
  let ty = uint_body(1, 1);
  let tye = elem(0x83, &ty);
  push_bytes(&mut body, &tye);
  let ci = bytes_of("V_VP8");
  let cie = elem(0x86, &ci);
  push_bytes(&mut body, &cie);
  let nm = bytes_of("Main Video");
  let nme = elem(0x536E, &nm);
  push_bytes(&mut body, &nme);
  let lg = bytes_of("eng");
  let lge = elem(0x22B59C, &lg);
  push_bytes(&mut body, &lge);
  let li = bytes_of("en-US");
  let lie = elem(0x22B59D, &li);
  push_bytes(&mut body, &lie);
  var vbody = Vec[UInt8].new();
  let pw = uint_body(1920, 2);
  let pwe = elem(0xB0, &pw);
  push_bytes(&mut vbody, &pwe);
  let ph = uint_body(1080, 2);
  let phe = elem(0xBA, &ph);
  push_bytes(&mut vbody, &phe);
  let ve = elem(0xE0, &vbody);
  push_bytes(&mut body, &ve);
  let dd = uint_body(40000000, 4);
  let dde = elem(0x23E383, &dd);
  push_bytes(&mut body, &dde);
  let entry = track_entry_elem(&body);
  let tracks = tracks_elem(&entry);
  let hdr = std_header("matroska");
  let file = std_file(hdr, tracks);
  let r = mkv_parse(&file);
  if !r.is_ok {
    return assert(false, "tracks: video TrackEntry parses");
  }
  let f = r.value;
  var ok = true;
  if mkv_track_count(&f) != 1 { ok = false; }
  if mkv_track_offset(&f) != file.len() - entry.len() { ok = false; }
  if mkv_track_number(&f, 0) != 1 { ok = false; }
  if mkv_track_uid(&f, 0) != 0x1234567890 { ok = false; }
  if mkv_track_type(&f, 0) != 1 { ok = false; }
  if !str_eq(mkv_track_codec_id(&f, 0), "V_VP8") { ok = false; }
  if !str_eq(mkv_track_name(&f, 0), "Main Video") { ok = false; }
  if !str_eq(mkv_track_language(&f, 0), "eng") { ok = false; }
  if !str_eq(mkv_track_language_ietf(&f, 0), "en-US") { ok = false; }
  if mkv_track_video_width(&f, 0) != 1920 { ok = false; }
  if mkv_track_video_height(&f, 0) != 1080 { ok = false; }
  if mkv_track_audio_sampling_millihz(&f, 0) != 0 { ok = false; }
  if mkv_track_audio_channels(&f, 0) != 0 { ok = false; }
  return assert(ok, "tracks: video TrackEntry with Video and unknown child");
}

fn t12() -> TestResult {
  var body = Vec[UInt8].new();
  let n = uint_body(2, 1);
  let ne = elem(0xD7, &n);
  push_bytes(&mut body, &ne);
  let u = uint_body(42, 1);
  let ue = elem(0x73C5, &u);
  push_bytes(&mut body, &ue);
  let ty = uint_body(2, 1);
  let tye = elem(0x83, &ty);
  push_bytes(&mut body, &tye);
  let ci = bytes_of("A_OPUS");
  let cie = elem(0x86, &ci);
  push_bytes(&mut body, &cie);
  var abody = Vec[UInt8].new();
  var f64 = Vec[UInt8].new();
  push_byte(&mut f64, 0x40);
  push_byte(&mut f64, 0xE7);
  push_byte(&mut f64, 0x70);
  push_byte(&mut f64, 0x00);
  push_byte(&mut f64, 0x00);
  push_byte(&mut f64, 0x00);
  push_byte(&mut f64, 0x00);
  push_byte(&mut f64, 0x00);
  let sfe = elem(0xB5, &f64);
  push_bytes(&mut abody, &sfe);
  let ch = uint_body(2, 1);
  let che = elem(0x9F, &ch);
  push_bytes(&mut abody, &che);
  let bd = uint_body(16, 1);
  let bde = elem(0x6264, &bd);
  push_bytes(&mut abody, &bde);
  let ae = elem(0xE1, &abody);
  push_bytes(&mut body, &ae);
  let entry = track_entry_elem(&body);
  let tracks = tracks_elem(&entry);
  let file = std_file(std_header("matroska"), tracks);
  let r = mkv_parse(&file);
  if !r.is_ok {
    return assert(false, "tracks: audio TrackEntry parses");
  }
  let f = r.value;
  var ok = true;
  if mkv_track_count(&f) != 1 { ok = false; }
  if mkv_track_number(&f, 0) != 2 { ok = false; }
  if mkv_track_uid(&f, 0) != 42 { ok = false; }
  if mkv_track_type(&f, 0) != 2 { ok = false; }
  if !str_eq(mkv_track_codec_id(&f, 0), "A_OPUS") { ok = false; }
  if mkv_track_audio_sampling_millihz(&f, 0) != 48000000 { ok = false; }
  if mkv_track_audio_channels(&f, 0) != 2 { ok = false; }
  if mkv_track_video_width(&f, 0) != 0 { ok = false; }
  if mkv_track_video_height(&f, 0) != 0 { ok = false; }
  return assert(ok, "tracks: audio TrackEntry, float64 SamplingFrequency");
}

fn t13() -> TestResult {
  var e1 = Vec[UInt8].new();
  let n1 = uint_body(1, 1);
  let n1e = elem(0xD7, &n1);
  push_bytes(&mut e1, &n1e);
  let t1 = uint_body(1, 1);
  let t1e = elem(0x83, &t1);
  push_bytes(&mut e1, &t1e);
  let c1 = bytes_of("V_VP8");
  let c1e = elem(0x86, &c1);
  push_bytes(&mut e1, &c1e);
  var e2 = Vec[UInt8].new();
  let n2 = uint_body(2, 1);
  let n2e = elem(0xD7, &n2);
  push_bytes(&mut e2, &n2e);
  let t2 = uint_body(2, 1);
  let t2e = elem(0x83, &t2);
  push_bytes(&mut e2, &t2e);
  let c2 = bytes_of("A_VORBIS");
  let c2e = elem(0x86, &c2);
  push_bytes(&mut e2, &c2e);
  var e3 = Vec[UInt8].new();
  let n3 = uint_body(3, 1);
  let n3e = elem(0xD7, &n3);
  push_bytes(&mut e3, &n3e);
  let t3 = uint_body(17, 1);
  let t3e = elem(0x83, &t3);
  push_bytes(&mut e3, &t3e);
  let c3 = bytes_of("S_TEXT/UTF8");
  let c3e = elem(0x86, &c3);
  push_bytes(&mut e3, &c3e);
  let nm3 = bytes_of("Subs");
  let nm3e = elem(0x536E, &nm3);
  push_bytes(&mut e3, &nm3e);
  let li3 = bytes_of("en");
  let li3e = elem(0x22B59D, &li3);
  push_bytes(&mut e3, &li3e);
  var tracks_body = Vec[UInt8].new();
  let te1 = track_entry_elem(&e1);
  push_bytes(&mut tracks_body, &te1);
  let te2 = track_entry_elem(&e2);
  push_bytes(&mut tracks_body, &te2);
  let te3 = track_entry_elem(&e3);
  push_bytes(&mut tracks_body, &te3);
  let tracks = tracks_elem(&tracks_body);
  let file = std_file(std_header("matroska"), tracks);
  let r = mkv_parse(&file);
  if !r.is_ok {
    return assert(false, "tracks: three TrackEntries parse");
  }
  let f = r.value;
  var ok = true;
  if mkv_track_count(&f) != 3 { ok = false; }
  if mkv_track_number(&f, 0) != 1 { ok = false; }
  if mkv_track_number(&f, 1) != 2 { ok = false; }
  if mkv_track_number(&f, 2) != 3 { ok = false; }
  if mkv_track_type(&f, 0) != 1 { ok = false; }
  if mkv_track_type(&f, 1) != 2 { ok = false; }
  if mkv_track_type(&f, 2) != 17 { ok = false; }
  if !str_eq(mkv_track_codec_id(&f, 2), "S_TEXT/UTF8") { ok = false; }
  if !str_eq(mkv_track_name(&f, 2), "Subs") { ok = false; }
  if !str_eq(mkv_track_language_ietf(&f, 2), "en") { ok = false; }
  if mkv_track_offset(&f, 1) != mkv_track_offset(&f, 0) + te1.len() { ok = false; }
  if mkv_track_offset(&f, 2) != mkv_track_offset(&f, 1) + te2.len() { ok = false; }
  if mkv_track_number(&f, 3) != -1 { ok = false; }
  if mkv_track_number(&f, -1) != -1 { ok = false; }
  if !str_eq(mkv_track_codec_id(&f, 3), "") { ok = false; }
  return assert(ok, "tracks: multiple entries, order, types, index guards");
}

fn t14() -> TestResult {
  var frame1 = Vec[UInt8].new();
  push_byte(&mut frame1, 0x1A);
  push_byte(&mut frame1, 0x45);
  push_byte(&mut frame1, 0xDF);
  push_byte(&mut frame1, 0xA3);
  push_byte(&mut frame1, 0xDE);
  push_byte(&mut frame1, 0xAD);
  push_byte(&mut frame1, 0xBE);
  push_byte(&mut frame1, 0xEF);
  var frame2 = Vec[UInt8].new();
  push_byte(&mut frame2, 0x00);
  push_byte(&mut frame2, 0x01);
  push_byte(&mut frame2, 0xFF);
  push_byte(&mut frame2, 0x7F);
  let c1 = cluster_elem(&frame1);
  let c2 = cluster_elem(&frame2);
  var tags_body = Vec[UInt8].new();
  let tag = bytes_of("test");
  let tage = elem(0x7373, &tag);
  push_bytes(&mut tags_body, &tage);
  let tags = elem(0x1254C367, &tags_body);
  var seg_body = Vec[UInt8].new();
  let empty = Vec[UInt8].new();
  let info = info_elem(&empty);
  push_bytes(&mut seg_body, &info);
  push_bytes(&mut seg_body, &c1);
  push_bytes(&mut seg_body, &c2);
  push_bytes(&mut seg_body, &tags);
  let file = std_file(std_header("matroska"), seg_body);
  let r = mkv_parse(&file);
  if !r.is_ok {
    return assert(false, "clusters: sized clusters skipped, Tags parses");
  }
  let f = r.value;
  var ok = true;
  if mkv_cluster_count(&f) != 2 { ok = false; }
  if mkv_cluster_offset(&f, 1) != mkv_cluster_offset(&f, 0) + c1.len() { ok = false; }
  if mkv_cluster_end_offset(&f, 0) != mkv_cluster_offset(&f, 0) + c1.len() { ok = false; }
  if mkv_cluster_end_offset(&f, 1) != mkv_cluster_offset(&f, 1) + c2.len() { ok = false; }
  if mkv_cluster_size(&f, 0) != frame1.len() { ok = false; }
  if mkv_cluster_size(&f, 1) != frame2.len() { ok = false; }
  if mkv_cluster_data_offset(&f, 0) < mkv_cluster_offset(&f, 0) { ok = false; }
  if mkv_cluster_data_offset(&f, 0) + frame1.len() != mkv_cluster_end_offset(&f, 0) { ok = false; }
  if mkv_cluster_is_unknown_size(&f, 0) { ok = false; }
  if mkv_cluster_is_unknown_size(&f, 1) { ok = false; }
  if mkv_cluster_count(&f) != 2 { ok = false; }
  if mkv_cluster_offset(&f, 2) != -1 { ok = false; }
  if mkv_cluster_end_offset(&f, -1) != -1 { ok = false; }
  if mkv_cluster_is_unknown_size(&f, 2) { ok = false; }
  return assert(ok, "clusters: spans follow declared sizes, frames ignored");
}

fn t15() -> TestResult {
  var ok = true;
  var frame = Vec[UInt8].new();
  push_byte(&mut frame, 0x81);
  push_byte(&mut frame, 0x02);
  push_byte(&mut frame, 0x03);
  push_byte(&mut frame, 0x04);
  var tags_body = Vec[UInt8].new();
  let tag = bytes_of("boundary");
  let tage = elem(0x7373, &tag);
  push_bytes(&mut tags_body, &tage);
  let tags = elem(0x1254C367, &tags_body);
  var frame2 = Vec[UInt8].new();
  push_byte(&mut frame2, 0xAA);
  push_byte(&mut frame2, 0xBB);
  let c2 = cluster_elem(&frame2);
  let cu = elem_unknown(0x1F43B675, &frame);
  var seg_body = Vec[UInt8].new();
  push_bytes(&mut seg_body, &cu);
  push_bytes(&mut seg_body, &tags);
  push_bytes(&mut seg_body, &c2);
  let file = std_file(std_header("matroska"), seg_body);
  let r = mkv_parse(&file);
  if !r.is_ok { ok = false; } else {
    let f = r.value;
    if mkv_cluster_count(&f) != 2 { ok = false; }
    if !mkv_cluster_is_unknown_size(&f, 0) { ok = false; }
    if mkv_cluster_size(&f, 0) != -1 { ok = false; }
    if mkv_cluster_end_offset(&f, 0) != mkv_cluster_offset(&f, 0) + cu.len() { ok = false; }
    if mkv_cluster_end_offset(&f, 1) != file.len() { ok = false; }
  }
  var frame3 = Vec[UInt8].new();
  push_byte(&mut frame3, 0x10);
  push_byte(&mut frame3, 0x20);
  var cu2 = elem_unknown(0x1F43B675, &frame3);
  let file2 = std_file(std_header("matroska"), cu2);
  let r2 = mkv_parse(&file2);
  if !r2.is_ok { ok = false; } else {
    let f2 = r2.value;
    if mkv_cluster_count(&f2) != 1 { ok = false; }
    if !mkv_cluster_is_unknown_size(&f2, 0) { ok = false; }
    if mkv_cluster_end_offset(&f2, 0) != file2.len() { ok = false; }
  }
  var fake = Vec[UInt8].new();
  push_byte(&mut fake, 0x1F);
  push_byte(&mut fake, 0x43);
  push_byte(&mut fake, 0xB6);
  push_byte(&mut fake, 0x75);
  push_byte(&mut fake, 0x20);
  push_byte(&mut fake, 0xFF);
  push_byte(&mut fake, 0xFF);
  push_byte(&mut fake, 0x99);
  push_byte(&mut fake, 0x99);
  let cu3 = elem_unknown(0x1F43B675, &fake);
  var seg3 = Vec[UInt8].new();
  push_bytes(&mut seg3, &cu3);
  let tags3 = elem(0x1254C367, &tags_body);
  push_bytes(&mut seg3, &tags3);
  let file3 = std_file(std_header("matroska"), seg3);
  let r3 = mkv_parse(&file3);
  if !r3.is_ok { ok = false; } else {
    let f3 = r3.value;
    if mkv_cluster_count(&f3) != 1 { ok = false; }
    if mkv_cluster_end_offset(&f3, 0) != mkv_cluster_offset(&f3, 0) + cu3.len() { ok = false; }
  }
  return assert(ok, "clusters: unknown size ends at next valid top-level ID");
}

fn t16() -> TestResult {
  var ok = true;
  var info_trunc = Vec[UInt8].new();
  let it_id = enc_id(0x1549A966);
  push_bytes(&mut info_trunc, &it_id);
  let it_sz = enc_size(100);
  push_bytes(&mut info_trunc, &it_sz);
  push_byte(&mut info_trunc, 0x01);
  push_byte(&mut info_trunc, 0x02);
  push_byte(&mut info_trunc, 0x03);
  let f_trunc = std_file(std_header("matroska"), info_trunc);
  if !err_file_is(mkv_parse(&f_trunc), "mkv: truncated element") { ok = false; }
  var zero_id = Vec[UInt8].new();
  push_byte(&mut zero_id, 0x00);
  push_byte(&mut zero_id, 0x01);
  let f_zero = std_file(std_header("matroska"), zero_id);
  if !err_file_is(mkv_parse(&f_zero), "mkv: invalid vint") { ok = false; }
  var unk_hdr = Vec[UInt8].new();
  let magic = enc_id(0x1A45DFA3);
  push_bytes(&mut unk_hdr, &magic);
  push_byte(&mut unk_hdr, 0xFF);
  push_byte(&mut unk_hdr, 0x00);
  let f_unk = mkv_parse(&unk_hdr);
  if !err_file_is(f_unk, "mkv: bad ebml header size") { ok = false; }
  var zero_hdr = Vec[UInt8].new();
  let magic2 = enc_id(0x1A45DFA3);
  push_bytes(&mut zero_hdr, &magic2);
  push_byte(&mut zero_hdr, 0x80);
  let f_zh = mkv_parse(&zero_hdr);
  if !err_file_is(f_zh, "mkv: bad ebml header size") { ok = false; }
  var unk_info_body = Vec[UInt8].new();
  let unk_child_id = enc_id(0x2AD7B1);
  push_bytes(&mut unk_info_body, &unk_child_id);
  push_byte(&mut unk_info_body, 0xFF);
  let f_unk_info = std_file(std_header("matroska"), info_elem(&unk_info_body));
  if !err_file_is(mkv_parse(&f_unk_info), "mkv: unknown-size element") { ok = false; }
  var bad_int_entry = Vec[UInt8].new();
  let bi_id = enc_id(0xD7);
  push_bytes(&mut bad_int_entry, &bi_id);
  let bi_sz = enc_size(9);
  push_bytes(&mut bad_int_entry, &bi_sz);
  var k = 0;
  while k < 9 {
    push_byte(&mut bad_int_entry, 1);
    k = k + 1;
  }
  let bad_int_wrapped = track_entry_elem(&bad_int_entry);
  let tracks_bad = tracks_elem(&bad_int_wrapped);
  let f_bad_int = std_file(std_header("matroska"), tracks_bad);
  if !err_file_is(mkv_parse(&f_bad_int), "mkv: bad integer width") { ok = false; }
  var no_num_entry = Vec[UInt8].new();
  let ty = uint_body(2, 1);
  let tye = elem(0x83, &ty);
  push_bytes(&mut no_num_entry, &tye);
  let no_num_wrapped = track_entry_elem(&no_num_entry);
  let tracks_no_num = tracks_elem(&no_num_wrapped);
  let f_no_num = std_file(std_header("matroska"), tracks_no_num);
  if !err_file_is(mkv_parse(&f_no_num), "mkv: bad track number") { ok = false; }
  return assert(ok, "malformed: truncation, zero id, unknown size, widths");
}

fn t17() -> TestResult {
  var ok = true;
  let empty = Vec[UInt8].new();
  let e = mkv_parse(&empty);
  if e.is_ok { ok = false; }
  let short = Vec[UInt8].new();
  let magic = enc_id(0x1A45DFA3);
  if mkv_parse(&short).is_ok { ok = false; }
  var magic_only = Vec[UInt8].new();
  push_bytes(&mut magic_only, &magic);
  if mkv_parse(&magic_only).is_ok { ok = false; }
  let hdr = std_header("matroska");
  let no_seg = mkv_parse(&hdr);
  if !err_file_is(no_seg, "mkv: segment not found") { ok = false; }
  var other_top = Vec[UInt8].new();
  push_bytes(&mut other_top, &hdr);
  let bogus_body = uint_body(1, 1);
  let bogus = elem(0xEC, &bogus_body);
  push_bytes(&mut other_top, &bogus);
  if !err_file_is(mkv_parse(&other_top), "mkv: segment not found") { ok = false; }
  var trunc_seg = Vec[UInt8].new();
  push_bytes(&mut trunc_seg, &hdr);
  let seg_id = enc_id(0x18538067);
  push_bytes(&mut trunc_seg, &seg_id);
  let big = enc_size(1000);
  push_bytes(&mut trunc_seg, &big);
  push_byte(&mut trunc_seg, 0x01);
  push_byte(&mut trunc_seg, 0x02);
  if !err_file_is(mkv_parse(&trunc_seg), "mkv: truncated segment") { ok = false; }
  let full_body = info_elem(&empty);
  let yes_seg = std_file(hdr, full_body);
  var lens = Vec[Int].new();
  lens.push(1);
  lens.push(4);
  lens.push(5);
  lens.push(yes_seg.len() / 2);
  lens.push(yes_seg.len() - 1);
  var li = 0;
  while li < lens.len() {
    let k: Int = lens[li];
    let p = prefix_of(&yes_seg, k);
    if p.len() != k { ok = false; }
    if mkv_parse(&p).is_ok { ok = false; }
    li = li + 1;
  }
  return assert(ok, "truncated input: prefixes never parse as a file");
}

fn t18() -> TestResult {
  var ok = true;
  var values = Vec[Int].new();
  values.push(0);
  values.push(1);
  values.push(126);
  values.push(127);
  values.push(128);
  values.push(16382);
  values.push(16383);
  values.push(16384);
  values.push(2097150);
  values.push(2097151);
  values.push(1048576);
  var i = 0;
  while i < values.len() {
    let v: Int = values[i];
    let enc = enc_size(v);
    let r = mkv_vint_size(&enc, 0);
    if !r.is_ok { ok = false; } else {
      let got: Int = r.value;
      if got != v { ok = false; }
    }
    let w = size_width_for(v);
    let wr = mkv_vint_size_width(&enc, 0);
    if !wr.is_ok { ok = false; } else {
      let got: Int = wr.value;
      if got != w { ok = false; }
    }
    i = i + 1;
  }
  var w = 1;
  while w <= 8 {
    let enc = enc_unknown_size(w);
    let r = mkv_vint_size(&enc, 0);
    if !r.is_ok { ok = false; } else {
      let got: Int = r.value;
      if got != -1 { ok = false; }
    }
    let wr = mkv_vint_size_width(&enc, 0);
    if !wr.is_ok { ok = false; } else {
      let got: Int = wr.value;
      if got != w { ok = false; }
    }
    w = w + 1;
  }
  var ids = Vec[Int].new();
  ids.push(0xAE);
  ids.push(0x83);
  ids.push(0x86);
  ids.push(0xD7);
  ids.push(0x9F);
  ids.push(0xB0);
  ids.push(0xBA);
  ids.push(0xB5);
  ids.push(0xE0);
  ids.push(0xE1);
  ids.push(0xEC);
  ids.push(0xBF);
  ids.push(0x4286);
  ids.push(0x42F3);
  ids.push(0x4489);
  ids.push(0x4D80);
  ids.push(0x5741);
  ids.push(0x7BA9);
  ids.push(0x73C5);
  ids.push(0x536E);
  ids.push(0x22B59C);
  ids.push(0x22B59D);
  ids.push(0x2AD7B1);
  ids.push(0x114D9B74);
  ids.push(0x1549A966);
  ids.push(0x1654AE6B);
  ids.push(0x18538067);
  ids.push(0x1A45DFA3);
  ids.push(0x1C53BB6B);
  ids.push(0x1F43B675);
  i = 0;
  while i < ids.len() {
    let v: Int = ids[i];
    let enc = enc_id(v);
    let r = mkv_vint_id(&enc, 0);
    if !r.is_ok { ok = false; } else {
      let got: Int = r.value;
      if got != v { ok = false; }
    }
    i = i + 1;
  }
  var sbytes = enc_size(63);
  var want = Vec[UInt8].new();
  push_byte(&mut want, 0xBF);
  if !bytes_equal(sbytes, want) { ok = false; }
  var zbytes = enc_size(0);
  var zwant = Vec[UInt8].new();
  push_byte(&mut zwant, 0x80);
  if !bytes_equal(zbytes, zwant) { ok = false; }
  return assert(ok, "vint round-trip: sizes, unknown sentinels, ID table");
}

fn t19() -> TestResult {
  var ok = true;
  var nul_body = Vec[UInt8].new();
  var nul_text = Vec[UInt8].new();
  push_byte(&mut nul_text, 0x41);
  push_byte(&mut nul_text, 0x00);
  push_byte(&mut nul_text, 0x42);
  let nt = elem(0x7BA9, &nul_text);
  push_bytes(&mut nul_body, &nt);
  let f_nul = std_file(std_header("matroska"), info_elem(&nul_body));
  if !err_file_is(mkv_parse(&f_nul), "mkv: bad text field") { ok = false; }
  var bad_utf_body = Vec[UInt8].new();
  var bad_utf = Vec[UInt8].new();
  push_byte(&mut bad_utf, 0xC3);
  push_byte(&mut bad_utf, 0x28);
  let bu = elem(0x7BA9, &bad_utf);
  push_bytes(&mut bad_utf_body, &bu);
  let f_utf = std_file(std_header("matroska"), info_elem(&bad_utf_body));
  if !err_file_is(mkv_parse(&f_utf), "mkv: bad text field") { ok = false; }
  var inf_body = Vec[UInt8].new();
  push_byte(&mut inf_body, 0x7F);
  push_byte(&mut inf_body, 0x80);
  push_byte(&mut inf_body, 0x00);
  push_byte(&mut inf_body, 0x00);
  let infe = elem(0x4489, &inf_body);
  var dur_body = Vec[UInt8].new();
  push_bytes(&mut dur_body, &infe);
  let f_inf = std_file(std_header("matroska"), info_elem(&dur_body));
  if !err_file_is(mkv_parse(&f_inf), "mkv: bad float") { ok = false; }
  var short_float_body = Vec[UInt8].new();
  var short_float = Vec[UInt8].new();
  push_byte(&mut short_float, 0x01);
  push_byte(&mut short_float, 0x02);
  let sfe = elem(0x4489, &short_float);
  push_bytes(&mut short_float_body, &sfe);
  let f_sf = std_file(std_header("matroska"), info_elem(&short_float_body));
  if !err_file_is(mkv_parse(&f_sf), "mkv: bad float") { ok = false; }
  var zero_ts_body = Vec[UInt8].new();
  let zts = uint_body(0, 1);
  let ztse = elem(0x2AD7B1, &zts);
  push_bytes(&mut zero_ts_body, &ztse);
  let f_ts = std_file(std_header("matroska"), info_elem(&zero_ts_body));
  if !err_file_is(mkv_parse(&f_ts), "mkv: bad timestamp scale") { ok = false; }
  var audio_entry = Vec[UInt8].new();
  let an = uint_body(1, 1);
  let ane = elem(0xD7, &an);
  push_bytes(&mut audio_entry, &ane);
  var abody = Vec[UInt8].new();
  var bad_sf = Vec[UInt8].new();
  push_byte(&mut bad_sf, 0x7F);
  push_byte(&mut bad_sf, 0x80);
  push_byte(&mut bad_sf, 0x00);
  push_byte(&mut bad_sf, 0x00);
  let bsfe = elem(0xB5, &bad_sf);
  push_bytes(&mut abody, &bsfe);
  let aae = elem(0xE1, &abody);
  push_bytes(&mut audio_entry, &aae);
  let audio_wrapped = track_entry_elem(&audio_entry);
  let f_audio = std_file(std_header("matroska"), tracks_elem(&audio_wrapped));
  if !err_file_is(mkv_parse(&f_audio), "mkv: bad float") { ok = false; }
  return assert(ok, "validation: NUL/invalid UTF-8 text, bad floats, zero scale");
}

fn t20() -> TestResult {
  let hdr = std_header("matroska");
  let empty = Vec[UInt8].new();
  let file = std_file(hdr, empty);
  let r = mkv_parse(&file);
  if !r.is_ok {
    return assert(false, "guards: minimal file parses");
  }
  let f = r.value;
  var ok = true;
  if !mkv_is_file(&file) { ok = false; }
  if mkv_track_count(&f) != 0 { ok = false; }
  if mkv_track_offset(&f, 0) != -1 { ok = false; }
  if mkv_track_number(&f, 0) != -1 { ok = false; }
  if mkv_track_uid(&f, 0) != -1 { ok = false; }
  if mkv_track_type(&f, 0) != -1 { ok = false; }
  if !str_eq(mkv_track_codec_id(&f, 0), "") { ok = false; }
  if !str_eq(mkv_track_name(&f, 0), "") { ok = false; }
  if !str_eq(mkv_track_language(&f, 0), "") { ok = false; }
  if !str_eq(mkv_track_language_ietf(&f, 0), "") { ok = false; }
  if mkv_track_video_width(&f, 0) != -1 { ok = false; }
  if mkv_track_video_height(&f, 0) != -1 { ok = false; }
  if mkv_track_audio_sampling_millihz(&f, 0) != -1 { ok = false; }
  if mkv_track_audio_channels(&f, 0) != -1 { ok = false; }
  if mkv_cluster_count(&f) != 0 { ok = false; }
  if mkv_cluster_offset(&f, 0) != -1 { ok = false; }
  if mkv_cluster_data_offset(&f, 0) != -1 { ok = false; }
  if mkv_cluster_size(&f, 0) != -1 { ok = false; }
  if mkv_cluster_end_offset(&f, 0) != -1 { ok = false; }
  if mkv_cluster_is_unknown_size(&f, 0) { ok = false; }
  if mkv_info_offset(&f) != -1 { ok = false; }
  if mkv_segment_size(&f) != 0 { ok = false; }
  if !str_eq(mkv_doctype(&f), "matroska") { ok = false; }
  return assert(ok, "guards: empty store accessors are range-safe");
}

// --------------------------------------------------
//  Harness
// --------------------------------------------------

fn main() -> Int {
  io.println("=== xiom.mkv conformance tests ===");
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
    io.println("xiom.mkv: all tests passed");
  } else {
    io.println("xiom.mkv: tests failed");
  }
  return failed;
}
