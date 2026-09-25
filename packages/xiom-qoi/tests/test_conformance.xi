// XIOM -- xiom.qoi conformance tests (20 checks)
// Port task: prove the pure-XIOM xiom.qoi module against QOI containers and op streams.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module qoi_tests
use xiom.io; use xiom.test; use xiom.qoi;
use xiom.string; use xiom.string.compare;

// All Str equality goes through str_compare: `==` on Str lowered from a
// Vec[Str] element is a pointer comparison in v0.61.3, so every error-message
// comparison is routed through streq.

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// ASCII bytes of a literal.
fn bytes_of(s: Str) -> Vec[UInt8] {
  let v = Vec[UInt8].new();
  let n = s.len();
  var i = 0;
  while (i < n) {
    let b: UInt8 = string.byte_at(s, i);
    v.push(b);
    i = i + 1;
  }
  return v;
}

// Byte-wise equality of two vectors (0..255 widened).
fn vec_eq(a: &Vec[UInt8], b: &Vec[UInt8]) -> Bool {
  if (a.len() != b.len()) { return false; }
  var i = 0;
  while (i < a.len()) {
    let x: Int = (a[i] as Int) & 0xFF;
    let y: Int = (b[i] as Int) & 0xFF;
    if (x != y) { return false; }
    i = i + 1;
  }
  return true;
}

fn byte_is(data: &Vec[UInt8], i: Int, want: Int) -> Bool {
  let b: Int = (data[i] as Int) & 0xFF;
  return b == want;
}

// n zero bytes.
fn zeros(n: Int) -> Vec[UInt8] {
  let v = Vec[UInt8].new();
  var i = 0;
  while (i < n) {
    v.push(0 as UInt8);
    i = i + 1;
  }
  return v;
}

// Append a big-endian 32-bit value (test-side header construction).
fn push_be32(v: &mut Vec[UInt8], n: Int) {
  v.push(((n / 16777216) % 256) as UInt8);
  v.push(((n / 65536) % 256) as UInt8);
  v.push(((n / 256) % 256) as UInt8);
  v.push((n % 256) as UInt8);
}

// Hand-built 14-byte QOI header: magic, BE32(w), BE32(h), channels, colorspace.
fn raw_header(w: Int, h: Int, ch: Int, cs: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  v.push(113 as UInt8); // 'q'
  v.push(111 as UInt8); // 'o'
  v.push(105 as UInt8); // 'i'
  v.push(102 as UInt8); // 'f'
  push_be32(&mut v, w);
  push_be32(&mut v, h);
  v.push(ch as UInt8);
  v.push(cs as UInt8);
  return v;
}

// The 8-byte end marker: 7 * 0x00, 0x01.
fn marker() -> Vec[UInt8] {
  let v = Vec[UInt8].new();
  var i = 0;
  while (i < 7) {
    v.push(0 as UInt8);
    i = i + 1;
  }
  v.push(1 as UInt8);
  return v;
}

// Append every byte of `src` to `dst`.
fn append(dst: &mut Vec[UInt8], src: &Vec[UInt8]) {
  var i = 0;
  while (i < src.len()) {
    let b: UInt8 = src[i];
    dst.push(b);
    i = i + 1;
  }
}

// A complete file: header + ops + end marker.
fn file_of(w: Int, h: Int, ch: Int, cs: Int, ops: &Vec[UInt8]) -> Vec[UInt8] {
  var out = raw_header(w, h, ch, cs);
  append(&mut out, ops);
  append(&mut out, marker());
  return out;
}

// Op payload builders.
fn op_rgb(out: &mut Vec[UInt8], r: Int, g: Int, b: Int) {
  out.push(254 as UInt8);
  out.push(r as UInt8);
  out.push(g as UInt8);
  out.push(b as UInt8);
}

fn op_rgba(out: &mut Vec[UInt8], r: Int, g: Int, b: Int, a: Int) {
  out.push(255 as UInt8);
  out.push(r as UInt8);
  out.push(g as UInt8);
  out.push(b as UInt8);
  out.push(a as UInt8);
}

fn op_index(out: &mut Vec[UInt8], idx: Int) {
  out.push(idx as UInt8);
}

fn op_diff(out: &mut Vec[UInt8], dr: Int, dg: Int, db: Int) {
  out.push((64 + (dr + 2) * 16 + (dg + 2) * 4 + (db + 2)) as UInt8);
}

fn op_luma(out: &mut Vec[UInt8], dg: Int, dr_dg: Int, db_dg: Int) {
  out.push((128 + (dg + 32)) as UInt8);
  out.push(((dr_dg + 8) * 16 + (db_dg + 8)) as UInt8);
}

fn op_run(out: &mut Vec[UInt8], n: Int) {
  out.push((192 + (n - 1)) as UInt8);
}

// The six-op canonical sequence used by several checks: INDEX 3, DIFF
// (1, -2, 0), LUMA (5, -3, 7), RUN 4, RGB (1, 2, 3), RGBA (4, 5, 6, 7).
// It covers 1 + 1 + 1 + 4 + 1 + 1 = 9 pixels.
fn six_ops() -> Vec[UInt8] {
  var ops = Vec[UInt8].new();
  op_index(&mut ops, 3);
  op_diff(&mut ops, 1, -2, 0);
  op_luma(&mut ops, 5, -3, 7);
  op_run(&mut ops, 4);
  op_rgb(&mut ops, 1, 2, 3);
  op_rgba(&mut ops, 4, 5, 6, 7);
  return ops;
}

// The extreme-tag sequence: INDEX 0 / 63, DIFF (0x40) / (0x7F), LUMA
// (0x80 0x00) / (0xBF 0xFF), RUN 1 / 62. It covers 69 pixels.
fn boundary_ops() -> Vec[UInt8] {
  var ops = Vec[UInt8].new();
  op_index(&mut ops, 0);
  op_index(&mut ops, 63);
  op_diff(&mut ops, -2, -2, -2);
  op_diff(&mut ops, 1, 1, 1);
  op_luma(&mut ops, -32, -8, -8);
  op_luma(&mut ops, 31, 7, 7);
  op_run(&mut ops, 1);
  op_run(&mut ops, 62);
  return ops;
}

// Copy of an Int vector (for hand-built record sets).
fn copy_ints(src: &Vec[Int]) -> Vec[Int] {
  let out = Vec[Int].new();
  var i = 0;
  while (i < src.len()) {
    let v: Int = src[i];
    out.push(v);
    i = i + 1;
  }
  return out;
}

// An Int vector of n zeros.
fn zeros_ints(n: Int) -> Vec[Int] {
  let out = Vec[Int].new();
  var i = 0;
  while (i < n) {
    out.push(0);
    i = i + 1;
  }
  return out;
}

// Hand-built record set for emitter/walker error checks (op_offset is filled
// with zeros, which neither path consults).
fn manual_stream(w: Int, h: Int, ch: Int, cs: Int, ks: &Vec[Int], sp: &Vec[Int], aa: &Vec[Int], bb: &Vec[Int], cc: &Vec[Int], dd: &Vec[Int]) -> QoiStream {
  let k2: Vec[Int] = copy_ints(ks);
  let s2: Vec[Int] = copy_ints(sp);
  let a2: Vec[Int] = copy_ints(aa);
  let b2: Vec[Int] = copy_ints(bb);
  let c2: Vec[Int] = copy_ints(cc);
  let d2: Vec[Int] = copy_ints(dd);
  let o2: Vec[Int] = zeros_ints(k2.len());
  return QoiStream{
    width: w;
    height: h;
    channels: ch;
    colorspace: cs;
    op_kind: k2;
    op_offset: o2;
    op_span: s2;
    op_a: a2;
    op_b: b2;
    op_c: c2;
    op_d: d2;
  };
}

// A manual record set with exactly one record.
fn one_record(w: Int, h: Int, ch: Int, cs: Int, kind: Int, span: Int, a: Int, b: Int, c: Int, d: Int) -> QoiStream {
  let ks = Vec[Int].new();
  ks.push(kind);
  let sp = Vec[Int].new();
  sp.push(span);
  let aa = Vec[Int].new();
  aa.push(a);
  let bb = Vec[Int].new();
  bb.push(b);
  let cc = Vec[Int].new();
  cc.push(c);
  let dd = Vec[Int].new();
  dd.push(d);
  return manual_stream(w, h, ch, cs, ks, sp, aa, bb, cc, dd);
}

fn ok_stream(r: Result[QoiStream, Str]) -> QoiStream {
  match r {
    Ok(v) => { return v; },
    Err(e) => { return QoiStream{ width: 0; height: 0; channels: 0; colorspace: -1; op_kind: Vec[Int].new(); op_offset: Vec[Int].new(); op_span: Vec[Int].new(); op_a: Vec[Int].new(); op_b: Vec[Int].new(); op_c: Vec[Int].new(); op_d: Vec[Int].new(); }; },
  }
}

fn stream_err_is(r: Result[QoiStream, Str], want: Str) -> Bool {
  match r {
    Ok(v) => { return false; },
    Err(e) => { return streq(e, want); },
  }
}

fn ok_bytes(r: Result[Vec[UInt8], Str]) -> Vec[UInt8] {
  match r {
    Ok(v) => { return v; },
    Err(e) => { return Vec[UInt8].new(); },
  }
}

fn bytes_err_is(r: Result[Vec[UInt8], Str], want: Str) -> Bool {
  match r {
    Ok(v) => { return false; },
    Err(e) => { return streq(e, want); },
  }
}

fn ok_walk(r: Result[QoiWalk, Str]) -> QoiWalk {
  match r {
    Ok(v) => { return v; },
    Err(e) => { return QoiWalk{ op_count: -1; pixel_count: -1; checksum: -1; }; },
  }
}

fn walk_err_is(r: Result[QoiWalk, Str], want: Str) -> Bool {
  match r {
    Ok(v) => { return false; },
    Err(e) => { return streq(e, want); },
  }
}

fn t1() -> TestResult {
  var ops = Vec[UInt8].new();
  op_rgb(&mut ops, 10, 20, 30);
  let data = file_of(1, 1, 3, 0, ops);
  if (data.len() != 26) { return assert(false, "1x1 RGB file is 14 + 4 + 8 bytes"); }
  let q = ok_stream(qoi_parse(data));
  if (qoi_width(&q) != 1) { return assert(false, "width 1"); }
  if (qoi_height(&q) != 1) { return assert(false, "height 1"); }
  if (qoi_channels(&q) != 3) { return assert(false, "channels 3"); }
  if (qoi_colorspace(&q) != 0) { return assert(false, "colorspace 0"); }
  if (qoi_data_offset(&q) != 14) { return assert(false, "data offset 14"); }
  if (qoi_pixel_count(&q) != 1) { return assert(false, "pixel count 1"); }
  if (qoi_header_size() != 14) { return assert(false, "header size 14"); }
  if (qoi_end_marker_size() != 8) { return assert(false, "end marker size 8"); }
  if (qoi_max_pixels() != 400000000) { return assert(false, "documented cap 400000000"); }
  if (qoi_op_count(&q) != 1) { return assert(false, "one op"); }
  if (qoi_op_kind(&q, 0) != qoi_kind_rgb()) { return assert(false, "op kind RGB"); }
  if (qoi_op_offset(&q, 0) != 14) { return assert(false, "op offset 14"); }
  if (qoi_op_span(&q, 0) != 4) { return assert(false, "op span 4"); }
  if (qoi_op_a(&q, 0) != 10) { return assert(false, "op r 10"); }
  if (qoi_op_b(&q, 0) != 20) { return assert(false, "op g 20"); }
  if (qoi_op_c(&q, 0) != 30) { return assert(false, "op b 30"); }
  if (qoi_op_d(&q, 0) != -1) { return assert(false, "op d unused"); }
  if (qoi_op_flags(&q, 0) != qoi_flag_raw()) { return assert(false, "RGB flag raw"); }
  if (qoi_run_length(&q, 0) != -1) { return assert(false, "RGB has no run length"); }
  let again = ok_bytes(qoi_emit(&q));
  if (!vec_eq(again, data)) { return assert(false, "emit is byte-identical"); }
  return assert(true, "1x1 RGB parses, accesses and re-emits byte-exactly");
}

fn t2() -> TestResult {
  let ops = six_ops();
  let data = file_of(3, 3, 3, 0, ops);
  if (data.len() != 36) { return assert(false, "six-op file is 36 bytes"); }
  let q = ok_stream(qoi_parse(data));
  if (qoi_op_count(&q) != 6) { return assert(false, "six ops parse"); }
  if (qoi_pixel_count(&q) != 9) { return assert(false, "six ops cover 9 pixels"); }
  if (qoi_op_kind(&q, 0) != qoi_kind_index()) { return assert(false, "op 0 is INDEX"); }
  if (qoi_op_a(&q, 0) != 3) { return assert(false, "INDEX 3"); }
  if (qoi_op_b(&q, 0) != -1) { return assert(false, "INDEX has no b"); }
  if (qoi_op_c(&q, 0) != -1) { return assert(false, "INDEX has no c"); }
  if (qoi_op_d(&q, 0) != -1) { return assert(false, "INDEX has no d"); }
  if (qoi_op_span(&q, 0) != 1) { return assert(false, "INDEX span 1"); }
  if (qoi_op_flags(&q, 0) != qoi_flag_index()) { return assert(false, "INDEX flag"); }
  if (qoi_op_kind(&q, 1) != qoi_kind_diff()) { return assert(false, "op 1 is DIFF"); }
  if (qoi_op_a(&q, 1) != 1) { return assert(false, "DIFF dr 1"); }
  if (qoi_op_b(&q, 1) != -2) { return assert(false, "DIFF dg -2"); }
  if (qoi_op_c(&q, 1) != 0) { return assert(false, "DIFF db 0"); }
  if (qoi_op_d(&q, 1) != -1) { return assert(false, "DIFF has no d"); }
  if (qoi_op_flags(&q, 1) != qoi_flag_delta()) { return assert(false, "DIFF flag"); }
  if (qoi_op_kind(&q, 2) != qoi_kind_luma()) { return assert(false, "op 2 is LUMA"); }
  if (qoi_op_span(&q, 2) != 2) { return assert(false, "LUMA span 2"); }
  if (qoi_op_a(&q, 2) != 5) { return assert(false, "LUMA dg 5"); }
  if (qoi_op_b(&q, 2) != -3) { return assert(false, "LUMA dr-dg -3"); }
  if (qoi_op_c(&q, 2) != 7) { return assert(false, "LUMA db-dg 7"); }
  if (qoi_op_d(&q, 2) != -1) { return assert(false, "LUMA has no d"); }
  if (qoi_op_flags(&q, 2) != qoi_flag_delta()) { return assert(false, "LUMA flag"); }
  if (qoi_op_kind(&q, 3) != qoi_kind_run()) { return assert(false, "op 3 is RUN"); }
  if (qoi_run_length(&q, 3) != 4) { return assert(false, "RUN 4"); }
  if (qoi_op_a(&q, 3) != 4) { return assert(false, "RUN slot a is the length"); }
  if (qoi_op_flags(&q, 3) != qoi_flag_run()) { return assert(false, "RUN flag"); }
  if (qoi_op_kind(&q, 4) != qoi_kind_rgb()) { return assert(false, "op 4 is RGB"); }
  if (qoi_op_span(&q, 4) != 4) { return assert(false, "RGB span 4"); }
  if (qoi_op_a(&q, 4) != 1) { return assert(false, "RGB r 1"); }
  if (qoi_op_b(&q, 4) != 2) { return assert(false, "RGB g 2"); }
  if (qoi_op_c(&q, 4) != 3) { return assert(false, "RGB b 3"); }
  if (qoi_op_d(&q, 4) != -1) { return assert(false, "RGB has no d"); }
  if (qoi_op_flags(&q, 4) != qoi_flag_raw()) { return assert(false, "RGB flag"); }
  if (qoi_op_kind(&q, 5) != qoi_kind_rgba()) { return assert(false, "op 5 is RGBA"); }
  if (qoi_op_span(&q, 5) != 5) { return assert(false, "RGBA span 5"); }
  if (qoi_op_a(&q, 5) != 4) { return assert(false, "RGBA r 4"); }
  if (qoi_op_b(&q, 5) != 5) { return assert(false, "RGBA g 5"); }
  if (qoi_op_c(&q, 5) != 6) { return assert(false, "RGBA b 6"); }
  if (qoi_op_d(&q, 5) != 7) { return assert(false, "RGBA a 7"); }
  if (qoi_op_flags(&q, 5) != qoi_flag_raw()) { return assert(false, "RGBA flag"); }
  if (qoi_op_offset(&q, 5) != 23) { return assert(false, "RGBA offset 23"); }
  let again = ok_bytes(qoi_emit(&q));
  if (!vec_eq(again, data)) { return assert(false, "six ops re-emit byte-exactly"); }
  return assert(true, "all six op kinds parse into flat records and re-emit");
}

fn t3() -> TestResult {
  let ops = six_ops();
  let data = file_of(3, 3, 3, 0, ops);
  let q = ok_stream(qoi_parse(data));
  if (qoi_op_kind(&q, -1) != -1) { return assert(false, "kind at -1 is -1"); }
  if (qoi_op_kind(&q, 6) != -1) { return assert(false, "kind at count is -1"); }
  if (qoi_op_flags(&q, -1) != -1) { return assert(false, "flags at -1 is -1"); }
  if (qoi_op_flags(&q, 6) != -1) { return assert(false, "flags at count is -1"); }
  if (qoi_op_offset(&q, -1) != -1) { return assert(false, "offset at -1 is -1"); }
  if (qoi_op_offset(&q, 6) != -1) { return assert(false, "offset at count is -1"); }
  if (qoi_op_span(&q, -1) != -1) { return assert(false, "span at -1 is -1"); }
  if (qoi_op_span(&q, 6) != -1) { return assert(false, "span at count is -1"); }
  if (qoi_op_a(&q, -1) != -1) { return assert(false, "slot a at -1 is -1"); }
  if (qoi_op_b(&q, 6) != -1) { return assert(false, "slot b at count is -1"); }
  if (qoi_op_c(&q, -1) != -1) { return assert(false, "slot c at -1 is -1"); }
  if (qoi_op_d(&q, 6) != -1) { return assert(false, "slot d at count is -1"); }
  if (qoi_run_length(&q, -1) != -1) { return assert(false, "run length at -1 is -1"); }
  if (qoi_run_length(&q, 6) != -1) { return assert(false, "run length at count is -1"); }
  if (qoi_run_length(&q, 4) != -1) { return assert(false, "run length on RGB is -1"); }
  return assert(true, "out-of-range record accessors return the -1 sentinel");
}

fn t4() -> TestResult {
  let three = zeros(3);
  if (!stream_err_is(qoi_parse(three), "qoi: truncated header")) {
    return assert(false, "3-byte buffer is a truncated header");
  }
  let empty = Vec[UInt8].new();
  if (!stream_err_is(qoi_parse(empty), "qoi: truncated header")) {
    return assert(false, "empty buffer is a truncated header");
  }
  let magic4 = bytes_of("qoif");
  if (!stream_err_is(qoi_parse(magic4), "qoi: truncated header")) {
    return assert(false, "4-byte magic-only buffer is a truncated header");
  }
  let bad4 = bytes_of("qoiX");
  if (!stream_err_is(qoi_parse(bad4), "qoi: bad magic")) {
    return assert(false, "qoiX is bad magic");
  }
  let ten = bytes_of("qoif123456");
  if (!stream_err_is(qoi_parse(ten), "qoi: truncated header")) {
    return assert(false, "10 bytes with good magic is a truncated header");
  }
  let header_only = raw_header(1, 1, 3, 0);
  if (!stream_err_is(qoi_parse(header_only), "qoi: truncated op")) {
    return assert(false, "a header without ops is a truncated op");
  }
  return assert(true, "header truncation and magic are validated in order");
}

fn t5() -> TestResult {
  let zw = raw_header(0, 1, 3, 0);
  if (!stream_err_is(qoi_parse(zw), "qoi: zero width")) {
    return assert(false, "width 0 is zero width");
  }
  let zh = raw_header(1, 0, 3, 0);
  if (!stream_err_is(qoi_parse(zh), "qoi: zero height")) {
    return assert(false, "height 0 is zero height");
  }
  let zw_bad = raw_header(0, 1, 2, 9);
  if (!stream_err_is(qoi_parse(zw_bad), "qoi: zero width")) {
    return assert(false, "dimensions are validated before channels/colorspace");
  }
  let wh_zero = raw_header(4294967295, 0, 3, 0);
  if (!stream_err_is(qoi_parse(wh_zero), "qoi: zero height")) {
    return assert(false, "zero height is reported before the width cap");
  }
  return assert(true, "zero dimensions are rejected before any op scanning");
}

fn t6() -> TestResult {
  if (qoi_max_pixels() != 400000000) { return assert(false, "cap is 400000000"); }
  if (!stream_err_is(qoi_parse(raw_header(400000001, 1, 3, 0)), "qoi: dimension overflow")) {
    return assert(false, "width above the cap overflows");
  }
  if (!stream_err_is(qoi_parse(raw_header(1, 400000001, 3, 0)), "qoi: dimension overflow")) {
    return assert(false, "height above the cap overflows");
  }
  if (!stream_err_is(qoi_parse(raw_header(20000, 20001, 3, 0)), "qoi: dimension overflow")) {
    return assert(false, "width*height above the cap overflows");
  }
  if (!stream_err_is(qoi_parse(raw_header(4294967295, 1, 3, 0)), "qoi: dimension overflow")) {
    return assert(false, "u32 max width overflows");
  }
  if (!stream_err_is(qoi_parse(raw_header(1, 4294967295, 3, 0)), "qoi: dimension overflow")) {
    return assert(false, "u32 max height overflows");
  }
  let at_cap = raw_header(20000, 20000, 3, 0);
  if (!stream_err_is(qoi_parse(at_cap), "qoi: truncated op")) {
    return assert(false, "20000x20000 (exactly 400,000,000) is accepted by the cap check");
  }
  let at_cap2 = raw_header(1, 400000000, 3, 0);
  if (!stream_err_is(qoi_parse(at_cap2), "qoi: truncated op")) {
    return assert(false, "1x400000000 is accepted by the cap check");
  }
  return assert(true, "the 400,000,000-pixel cap is inclusive and overflow-safe");
}

fn t7() -> TestResult {
  if (!stream_err_is(qoi_parse(raw_header(1, 1, 0, 0)), "qoi: invalid channels")) {
    return assert(false, "channels 0 is invalid");
  }
  if (!stream_err_is(qoi_parse(raw_header(1, 1, 2, 0)), "qoi: invalid channels")) {
    return assert(false, "channels 2 is invalid");
  }
  if (!stream_err_is(qoi_parse(raw_header(1, 1, 5, 0)), "qoi: invalid channels")) {
    return assert(false, "channels 5 is invalid");
  }
  if (!stream_err_is(qoi_parse(raw_header(1, 1, 255, 9)), "qoi: invalid channels")) {
    return assert(false, "channels are validated before colorspace");
  }
  if (!stream_err_is(qoi_parse(raw_header(1, 1, 3, 2)), "qoi: invalid colorspace")) {
    return assert(false, "colorspace 2 is invalid");
  }
  if (!stream_err_is(qoi_parse(raw_header(1, 1, 3, 255)), "qoi: invalid colorspace")) {
    return assert(false, "colorspace 255 is invalid");
  }
  if (!stream_err_is(qoi_parse(raw_header(1, 1, 4, 1)), "qoi: truncated op")) {
    return assert(false, "channels 4 / colorspace 1 pass validation");
  }
  return assert(true, "channels 3/4 and colorspace 0/1 are the only accepted values");
}

fn t8() -> TestResult {
  let d1 = raw_header(1, 1, 3, 0);
  d1.push(254 as UInt8);
  d1.push(1 as UInt8);
  d1.push(2 as UInt8);
  if (!stream_err_is(qoi_parse(d1), "qoi: truncated op")) {
    return assert(false, "RGB with 2 of 3 payload bytes is truncated");
  }
  let d2 = raw_header(1, 1, 3, 0);
  d2.push(255 as UInt8);
  d2.push(1 as UInt8);
  d2.push(2 as UInt8);
  d2.push(3 as UInt8);
  if (!stream_err_is(qoi_parse(d2), "qoi: truncated op")) {
    return assert(false, "RGBA with 3 of 4 payload bytes is truncated");
  }
  let d3 = raw_header(1, 1, 3, 0);
  d3.push(128 as UInt8);
  if (!stream_err_is(qoi_parse(d3), "qoi: truncated op")) {
    return assert(false, "LUMA with no second byte is truncated");
  }
  var d4 = raw_header(3, 1, 3, 0);
  op_rgb(&mut d4, 9, 9, 9);
  if (!stream_err_is(qoi_parse(d4), "qoi: truncated op")) {
    return assert(false, "an op stream that runs out before the budget is truncated");
  }
  let d5 = raw_header(1, 1, 3, 0);
  if (!stream_err_is(qoi_parse(d5), "qoi: truncated op")) {
    return assert(false, "no ops at all is a truncated op");
  }
  return assert(true, "a buffer ending inside the op section is qoi: truncated op");
}

fn t9() -> TestResult {
  let d1 = raw_header(1, 1, 3, 0);
  d1.push(193 as UInt8);
  if (!stream_err_is(qoi_parse(d1), "qoi: run overflow")) {
    return assert(false, "RUN 2 with one pixel left overflows");
  }
  let d2 = raw_header(1, 1, 3, 0);
  d2.push(253 as UInt8);
  if (!stream_err_is(qoi_parse(d2), "qoi: run overflow")) {
    return assert(false, "RUN 62 with one pixel left overflows");
  }
  var d3 = raw_header(3, 1, 3, 0);
  op_rgb(&mut d3, 1, 2, 3);
  d3.push(194 as UInt8);
  if (!stream_err_is(qoi_parse(d3), "qoi: run overflow")) {
    return assert(false, "RUN 3 after one pixel with two left overflows");
  }
  var okops = Vec[UInt8].new();
  op_run(&mut okops, 1);
  let ok_file = file_of(1, 1, 3, 0, okops);
  let q1 = ok_stream(qoi_parse(ok_file));
  if (qoi_run_length(&q1, 0) != 1) { return assert(false, "RUN 1 is legal"); }
  if (qoi_op_count(&q1) != 1) { return assert(false, "RUN 1 is one op"); }
  var okops2 = Vec[UInt8].new();
  op_rgb(&mut okops2, 1, 2, 3);
  op_run(&mut okops2, 2);
  let ok_file2 = file_of(3, 1, 3, 0, okops2);
  let q2 = ok_stream(qoi_parse(ok_file2));
  if (qoi_run_length(&q2, 1) != 2) { return assert(false, "RUN 2 fills the budget exactly"); }
  if (qoi_pixel_count(&q2) != 3) { return assert(false, "1 + 2 pixels"); }
  let again = ok_bytes(qoi_emit(&q2));
  if (!vec_eq(again, ok_file2)) { return assert(false, "RGB + RUN 2 re-emits byte-exactly"); }
  return assert(true, "runs may fill the pixel budget exactly but never pass it");
}

fn t10() -> TestResult {
  var ops = Vec[UInt8].new();
  op_rgb(&mut ops, 1, 2, 3);
  let good = file_of(1, 1, 3, 0, ops);
  if (good.len() != 26) { return assert(false, "reference file is 26 bytes"); }
  let short = file_of(1, 1, 3, 0, ops);
  short.pop();
  if (!stream_err_is(qoi_parse(short), "qoi: truncated end marker")) {
    return assert(false, "7 bytes of marker is truncated");
  }
  let badlast = file_of(1, 1, 3, 0, ops);
  badlast[25] = 0 as UInt8;
  if (!stream_err_is(qoi_parse(badlast), "qoi: bad end marker")) {
    return assert(false, "marker without the final 0x01 is bad");
  }
  let badmid = file_of(1, 1, 3, 0, ops);
  badmid[21] = 7 as UInt8;
  if (!stream_err_is(qoi_parse(badmid), "qoi: bad end marker")) {
    return assert(false, "a non-zero marker byte is bad");
  }
  let extra = file_of(1, 1, 3, 0, ops);
  extra.push(0 as UInt8);
  if (!stream_err_is(qoi_parse(extra), "qoi: trailing data")) {
    return assert(false, "a byte after the marker is trailing data");
  }
  let q = ok_stream(qoi_parse(good));
  if (qoi_op_count(&q) != 1) { return assert(false, "the reference file still parses"); }
  return assert(true, "the end marker must be exact and terminal");
}

fn t11() -> TestResult {
  let ops = six_ops();
  let data = file_of(3, 3, 4, 1, ops);
  if (data.len() != 36) { return assert(false, "six-op file is 36 bytes"); }
  if (!byte_is(data, 0, 113)) { return assert(false, "magic byte 0 is q"); }
  if (!byte_is(data, 1, 111)) { return assert(false, "magic byte 1 is o"); }
  if (!byte_is(data, 2, 105)) { return assert(false, "magic byte 2 is i"); }
  if (!byte_is(data, 3, 102)) { return assert(false, "magic byte 3 is f"); }
  if (!byte_is(data, 4, 0)) { return assert(false, "width byte 0"); }
  if (!byte_is(data, 5, 0)) { return assert(false, "width byte 1"); }
  if (!byte_is(data, 6, 0)) { return assert(false, "width byte 2"); }
  if (!byte_is(data, 7, 3)) { return assert(false, "width byte 3"); }
  if (!byte_is(data, 8, 0)) { return assert(false, "height byte 0"); }
  if (!byte_is(data, 9, 0)) { return assert(false, "height byte 1"); }
  if (!byte_is(data, 10, 0)) { return assert(false, "height byte 2"); }
  if (!byte_is(data, 11, 3)) { return assert(false, "height byte 3"); }
  if (!byte_is(data, 12, 4)) { return assert(false, "channels byte"); }
  if (!byte_is(data, 13, 1)) { return assert(false, "colorspace byte"); }
  if (!byte_is(data, 14, 3)) { return assert(false, "first op tag is INDEX 3"); }
  var k = 28;
  while (k < 35) {
    if (!byte_is(data, k, 0)) { return assert(false, "marker leading zeroes"); }
    k = k + 1;
  }
  if (!byte_is(data, 35, 1)) { return assert(false, "marker final byte"); }
  let q = ok_stream(qoi_parse(data));
  let again = ok_bytes(qoi_emit(&q));
  if (!vec_eq(again, data)) { return assert(false, "emit is byte-identical"); }
  return assert(true, "canonical emit writes the header, ops and marker byte-for-byte");
}

fn t12() -> TestResult {
  let bad_kind = one_record(1, 1, 3, 0, 9, 1, 0, -1, -1, -1);
  if (!bytes_err_is(qoi_emit(&bad_kind), "qoi: invalid record")) {
    return assert(false, "kind 9 is rejected");
  }
  let bad_d = one_record(1, 1, 3, 0, 0, 4, 0, 0, 0, 0);
  if (!bytes_err_is(qoi_emit(&bad_d), "qoi: invalid record")) {
    return assert(false, "RGB with slot d set is rejected");
  }
  let bad_span = one_record(1, 1, 3, 0, 0, 5, 0, 0, 0, -1);
  if (!bytes_err_is(qoi_emit(&bad_span), "qoi: invalid record")) {
    return assert(false, "RGB with span 5 is rejected");
  }
  let bad_px = one_record(2, 2, 3, 0, 0, 4, 0, 0, 0, -1);
  if (!bytes_err_is(qoi_emit(&bad_px), "qoi: invalid record")) {
    return assert(false, "ops covering 1 of 4 pixels are rejected");
  }
  let bad_run = one_record(1, 1, 3, 0, 5, 1, 62, -1, -1, -1);
  if (!bytes_err_is(qoi_emit(&bad_run), "qoi: invalid record")) {
    return assert(false, "RUN 62 covering 62 of 1 pixels is rejected");
  }
  let bad_hdr = one_record(0, 1, 3, 0, 5, 1, 1, -1, -1, -1);
  if (!bytes_err_is(qoi_emit(&bad_hdr), "qoi: invalid record")) {
    return assert(false, "a zero dimension is rejected");
  }
  let ks = Vec[Int].new();
  ks.push(0);
  ks.push(0);
  let sp = Vec[Int].new();
  sp.push(4);
  let aa = Vec[Int].new();
  aa.push(0);
  let bb = Vec[Int].new();
  bb.push(0);
  let cc = Vec[Int].new();
  cc.push(0);
  let dd = Vec[Int].new();
  dd.push(-1);
  let drifted = manual_stream(1, 1, 3, 0, ks, sp, aa, bb, cc, dd);
  if (!bytes_err_is(qoi_emit(&drifted), "qoi: invalid record")) {
    return assert(false, "non-parallel record vectors are rejected");
  }
  let ok = one_record(1, 1, 3, 0, 5, 1, 1, -1, -1, -1);
  var okops = Vec[UInt8].new();
  op_run(&mut okops, 1);
  let expected = file_of(1, 1, 3, 0, okops);
  let emitted = ok_bytes(qoi_emit(&ok));
  if (!vec_eq(emitted, expected)) {
    return assert(false, "a hand-built RUN 1 record emits a valid file");
  }
  let parsed = ok_stream(qoi_parse(emitted));
  if (qoi_run_length(&parsed, 0) != 1) { return assert(false, "the emitted file parses back"); }
  return assert(true, "the emitter validates record consistency before writing");
}

fn t13() -> TestResult {
  let ops = six_ops();
  let data = file_of(3, 3, 3, 0, ops);
  let q = ok_stream(qoi_parse(data));
  let w = ok_walk(qoi_walk(&q));
  if (w.op_count != 6) { return assert(false, "walk sees 6 ops"); }
  if (w.pixel_count != 9) { return assert(false, "walk sees 9 pixels"); }
  if (w.checksum != 67) { return assert(false, "documented checksum is 67"); }
  var runops = Vec[UInt8].new();
  op_run(&mut runops, 1);
  let run_file = file_of(1, 1, 3, 0, runops);
  let q2 = ok_stream(qoi_parse(run_file));
  let w2 = ok_walk(qoi_walk(&q2));
  if (w2.op_count != 1) { return assert(false, "one op walked"); }
  if (w2.pixel_count != 1) { return assert(false, "one pixel walked"); }
  if (w2.checksum != 6) { return assert(false, "single RUN kind checksum is 6"); }
  return assert(true, "the walk counts pixels, ops and the documented kind checksum");
}

fn t14() -> TestResult {
  var ops = Vec[UInt8].new();
  op_index(&mut ops, 5);
  op_index(&mut ops, 5);
  let data = file_of(2, 1, 3, 0, ops);
  let q = ok_stream(qoi_parse(data));
  if (qoi_op_count(&q) != 2) { return assert(false, "two INDEX ops parse"); }
  if (!walk_err_is(qoi_walk(&q), "qoi: repeated index")) {
    return assert(false, "two INDEX ops to the same index are rejected");
  }
  var ops2 = Vec[UInt8].new();
  op_index(&mut ops2, 5);
  op_index(&mut ops2, 6);
  let q2 = ok_stream(qoi_parse(file_of(2, 1, 3, 0, ops2)));
  let w2 = ok_walk(qoi_walk(&q2));
  if (w2.checksum != 9) { return assert(false, "INDEX 5 then INDEX 6 checksum is 9"); }
  var ops3 = Vec[UInt8].new();
  op_index(&mut ops3, 5);
  op_rgb(&mut ops3, 1, 1, 1);
  let q3 = ok_stream(qoi_parse(file_of(2, 1, 3, 0, ops3)));
  let w3 = ok_walk(qoi_walk(&q3));
  if (w3.pixel_count != 2) { return assert(false, "INDEX then RGB is accepted"); }
  return assert(true, "consecutive INDEX ops must address different indices");
}

fn t15() -> TestResult {
  let over = one_record(1, 1, 3, 0, 5, 1, 62, -1, -1, -1);
  if (!walk_err_is(qoi_walk(&over), "qoi: run overflow")) {
    return assert(false, "walk rejects a RUN past the budget");
  }
  let under = one_record(2, 2, 3, 0, 0, 4, 0, 0, 0, -1);
  if (!walk_err_is(qoi_walk(&under), "qoi: pixel count mismatch")) {
    return assert(false, "walk rejects too few pixels");
  }
  let ks = Vec[Int].new();
  ks.push(0);
  ks.push(0);
  let sp = Vec[Int].new();
  sp.push(4);
  sp.push(4);
  let aa = Vec[Int].new();
  aa.push(0);
  aa.push(0);
  let bb = Vec[Int].new();
  bb.push(0);
  bb.push(0);
  let cc = Vec[Int].new();
  cc.push(0);
  cc.push(0);
  let dd = Vec[Int].new();
  dd.push(-1);
  dd.push(-1);
  let over2 = manual_stream(1, 1, 3, 0, ks, sp, aa, bb, cc, dd);
  if (!walk_err_is(qoi_walk(&over2), "qoi: pixel count overflow")) {
    return assert(false, "walk rejects too many pixels mid-stream");
  }
  return assert(true, "the bounded walk never lets the pixel count pass the budget");
}

fn t16() -> TestResult {
  let ops = boundary_ops();
  let data = file_of(3, 23, 3, 0, ops);
  let q = ok_stream(qoi_parse(data));
  if (qoi_op_count(&q) != 8) { return assert(false, "eight boundary ops"); }
  if (qoi_op_a(&q, 0) != 0) { return assert(false, "INDEX 0"); }
  if (qoi_op_a(&q, 1) != 63) { return assert(false, "INDEX 63"); }
  if (qoi_op_a(&q, 2) != -2) { return assert(false, "DIFF dr -2"); }
  if (qoi_op_b(&q, 2) != -2) { return assert(false, "DIFF dg -2"); }
  if (qoi_op_c(&q, 2) != -2) { return assert(false, "DIFF db -2"); }
  if (qoi_op_a(&q, 3) != 1) { return assert(false, "DIFF dr 1"); }
  if (qoi_op_b(&q, 3) != 1) { return assert(false, "DIFF dg 1"); }
  if (qoi_op_c(&q, 3) != 1) { return assert(false, "DIFF db 1"); }
  if (qoi_op_kind(&q, 4) != qoi_kind_luma()) { return assert(false, "LUMA min"); }
  if (qoi_op_a(&q, 4) != -32) { return assert(false, "LUMA dg -32"); }
  if (qoi_op_b(&q, 4) != -8) { return assert(false, "LUMA dr-dg -8"); }
  if (qoi_op_c(&q, 4) != -8) { return assert(false, "LUMA db-dg -8"); }
  if (qoi_op_a(&q, 5) != 31) { return assert(false, "LUMA dg 31"); }
  if (qoi_op_b(&q, 5) != 7) { return assert(false, "LUMA dr-dg 7"); }
  if (qoi_op_c(&q, 5) != 7) { return assert(false, "LUMA db-dg 7"); }
  if (qoi_run_length(&q, 6) != 1) { return assert(false, "RUN 1 boundary"); }
  if (qoi_run_length(&q, 7) != 62) { return assert(false, "RUN 62 boundary"); }
  if (qoi_op_offset(&q, 4) != 18) { return assert(false, "LUMA offset 18"); }
  if (qoi_op_offset(&q, 5) != 20) { return assert(false, "second LUMA offset 20"); }
  if (qoi_op_offset(&q, 7) != 23) { return assert(false, "RUN 62 offset 23"); }
  let w = ok_walk(qoi_walk(&q));
  if (w.op_count != 8) { return assert(false, "walk sees 8 ops"); }
  if (w.pixel_count != 69) { return assert(false, "walk sees 69 pixels"); }
  if (w.checksum != 182) { return assert(false, "documented boundary checksum is 182"); }
  let again = ok_bytes(qoi_emit(&q));
  if (!vec_eq(again, data)) { return assert(false, "boundary ops re-emit byte-exactly"); }
  return assert(true, "every op tag boundary decodes to its documented payload");
}

fn t17() -> TestResult {
  var ops = Vec[UInt8].new();
  op_rgb(&mut ops, 0, 0, 0);
  op_rgb(&mut ops, 255, 255, 255);
  op_rgba(&mut ops, 255, 0, 255, 0);
  let data = file_of(3, 1, 4, 0, ops);
  let q = ok_stream(qoi_parse(data));
  if (qoi_op_a(&q, 0) != 0) { return assert(false, "black R 0"); }
  if (qoi_op_b(&q, 0) != 0) { return assert(false, "black G 0"); }
  if (qoi_op_c(&q, 0) != 0) { return assert(false, "black B 0"); }
  if (qoi_op_a(&q, 1) != 255) { return assert(false, "white R 255"); }
  if (qoi_op_b(&q, 1) != 255) { return assert(false, "white G 255"); }
  if (qoi_op_c(&q, 1) != 255) { return assert(false, "white B 255"); }
  if (qoi_op_kind(&q, 2) != qoi_kind_rgba()) { return assert(false, "third op is RGBA"); }
  if (qoi_op_a(&q, 2) != 255) { return assert(false, "RGBA R 255"); }
  if (qoi_op_b(&q, 2) != 0) { return assert(false, "RGBA G 0"); }
  if (qoi_op_c(&q, 2) != 255) { return assert(false, "RGBA B 255"); }
  if (qoi_op_d(&q, 2) != 0) { return assert(false, "RGBA A 0"); }
  let w = ok_walk(qoi_walk(&q));
  if (w.pixel_count != 3) { return assert(false, "three pixels"); }
  if (w.checksum != 9) { return assert(false, "RGB, RGB, RGBA checksum is 9"); }
  let again = ok_bytes(qoi_emit(&q));
  if (!vec_eq(again, data)) { return assert(false, "payload extremes re-emit byte-exactly"); }
  return assert(true, "channel payloads 0 and 255 survive parse and re-emit");
}

fn t18() -> TestResult {
  var ops1 = Vec[UInt8].new();
  op_rgba(&mut ops1, 9, 8, 7, 6);
  let d1 = file_of(1, 1, 3, 1, ops1);
  let q1 = ok_stream(qoi_parse(d1));
  if (qoi_channels(&q1) != 3) { return assert(false, "channels 3 header"); }
  if (qoi_colorspace(&q1) != 1) { return assert(false, "colorspace 1 header"); }
  if (qoi_op_kind(&q1, 0) != qoi_kind_rgba()) { return assert(false, "RGBA op under channels 3"); }
  let again1 = ok_bytes(qoi_emit(&q1));
  if (!vec_eq(again1, d1)) { return assert(false, "channels 3 with RGBA re-emits"); }
  var ops2 = Vec[UInt8].new();
  op_rgb(&mut ops2, 1, 2, 3);
  let d2 = file_of(1, 1, 4, 0, ops2);
  let q2 = ok_stream(qoi_parse(d2));
  if (qoi_channels(&q2) != 4) { return assert(false, "channels 4 header"); }
  if (qoi_op_kind(&q2, 0) != qoi_kind_rgb()) { return assert(false, "RGB op under channels 4"); }
  let again2 = ok_bytes(qoi_emit(&q2));
  if (!vec_eq(again2, d2)) { return assert(false, "channels 4 with RGB re-emits"); }
  if (!stream_err_is(qoi_parse(raw_header(1, 1, 3, 1)), "qoi: truncated op")) {
    return assert(false, "colorspace 1 alone is a valid header");
  }
  return assert(true, "the channels byte does not restrict which ops may appear");
}

fn t19() -> TestResult {
  var ops = Vec[UInt8].new();
  ops.push(0 as UInt8);
  ops.push(0 as UInt8);
  let data = file_of(1, 2, 3, 0, ops);
  let q = ok_stream(qoi_parse(data));
  if (qoi_op_count(&q) != 2) { return assert(false, "the budget forces both INDEX ops to parse"); }
  if (qoi_op_kind(&q, 0) != qoi_kind_index()) { return assert(false, "first op is INDEX"); }
  if (qoi_op_a(&q, 0) != 0) { return assert(false, "first index is 0"); }
  if (qoi_op_offset(&q, 1) != 15) { return assert(false, "second op offset 15"); }
  if (qoi_op_span(&q, 1) != 1) { return assert(false, "second op span 1"); }
  let again = ok_bytes(qoi_emit(&q));
  if (!vec_eq(again, data)) { return assert(false, "leading-zero ops re-emit byte-exactly"); }
  if (!walk_err_is(qoi_walk(&q), "qoi: repeated index")) {
    return assert(false, "the walk still rejects the repeated index");
  }
  var ops1 = Vec[UInt8].new();
  ops1.push(0 as UInt8);
  let d1 = file_of(1, 1, 3, 0, ops1);
  let q1 = ok_stream(qoi_parse(d1));
  let w1 = ok_walk(qoi_walk(&q1));
  if (w1.checksum != 3) { return assert(false, "single INDEX 0 checksum is 3"); }
  return assert(true, "the pixel budget, not marker-looking zeroes, bounds the op stream");
}

fn t20() -> TestResult {
  let ops = six_ops();
  let data = file_of(3, 3, 3, 0, ops);
  let q = ok_stream(qoi_parse(data));
  let n = qoi_op_count(&q);
  if (n != 6) { return assert(false, "six ops"); }
  if (qoi_data_offset(&q) != 14) { return assert(false, "ops start at 14"); }
  if (qoi_op_offset(&q, 0) != 14) { return assert(false, "first op offset 14"); }
  var i = 1;
  while (i < n) {
    let prev: Int = qoi_op_offset(&q, i - 1) + qoi_op_span(&q, i - 1);
    let cur: Int = qoi_op_offset(&q, i);
    if (prev != cur) { return assert(false, "op offsets are contiguous"); }
    i = i + 1;
  }
  let last: Int = qoi_op_offset(&q, n - 1) + qoi_op_span(&q, n - 1);
  if (last != data.len() - 8) { return assert(false, "the ops end exactly at the marker"); }
  let flags = Vec[Int].new();
  flags.push(qoi_flag_index());
  flags.push(qoi_flag_delta());
  flags.push(qoi_flag_delta());
  flags.push(qoi_flag_run());
  flags.push(qoi_flag_raw());
  flags.push(qoi_flag_raw());
  var k = 0;
  while (k < n) {
    let want: Int = flags[k];
    let got: Int = qoi_op_flags(&q, k);
    if (want != got) { return assert(false, "per-op class flags follow the catalog"); }
    k = k + 1;
  }
  return assert(true, "op offsets chain from 14 to the end marker and flags match kinds");
}

fn main() -> Int {
  io.println("=== xiom.qoi conformance tests ===");
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
    io.println("xiom.qoi: all tests passed");
  } else {
    io.println("xiom.qoi: tests failed");
  }
  return failed;
}
