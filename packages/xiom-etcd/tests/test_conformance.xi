// XIOM -- xiom.etcd conformance tests
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Covers the documented API end to end with synthetic buffers built in-test
// (independent test-side varint/u32/field builders, plus pinned hex):
// varint boundaries and overflow rejection, u32/i32/i64 readers,
// fixed32/64, field keys, length-delimited values, unknown-field skip,
// packed repeated runs, gRPC framing and sequential parsing, ResponseHeader,
// KeyValue, RangeRequest/RangeResponse, PutRequest/PutResponse,
// DeleteRangeRequest/DeleteRangeResponse, Compare/TxnRequest/TxnResponse
// with one-of dispatch and raw op re-decoding, WatchRequest/WatchResponse
// with events, the Lease messages, Auth messages, Status/MemberList, Alarm,
// Hash/HashKV, Snapshot, Compaction/Defragment responses, unknown-field
// preservation, malformed/truncated input with byte offsets, the nesting
// cap, defaults and the name/constant tables.
//
// Str values are compared with str_compare (BUG 17 discipline), every Vec
// read is bound to a typed local, and Ok/Err are never constructed in test
// functions (only matched).

module etcd_tests
use xiom.io; use xiom.test;
use xiom.etcd;
use xiom.string;
use xiom.string.compare;
use xiom.encoding.hex;

// Expected bytes for a hex string ("" on malformed input; the test then
// fails on the byte comparison).
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
    if a[i] != b[i] {
      return false;
    }
    i = i + 1;
  }
  return true;
}

fn bytes_of(s: Str) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < s.len() {
    v.push(string.byte_at(s, i));
    i = i + 1;
  }
  return v;
}

fn str_eq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn enc_ok(r: Result[Vec[UInt8], Str]) -> Vec[UInt8] {
  match r {
    Ok(v) => { return v; },
    Err(_) => {},
  }
  return Vec[UInt8].new();
}

fn err_scalar_is(r: Result[EtcdScalar, Str], want: Str) -> Bool {
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

fn err_bytes_is(r: Result[Vec[UInt8], Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_delim_is(r: Result[EtcdDelimited, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_advance_is(r: Result[EtcdAdvance, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_frame_is(r: Result[EtcdFrame, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_header_is(r: Result[EtcdHeader, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_kv_is(r: Result[EtcdKeyValue, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_range_req_is(r: Result[EtcdRangeRequest, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_range_resp_is(r: Result[EtcdRangeResponse, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_put_req_is(r: Result[EtcdPutRequest, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_status_is(r: Result[EtcdStatusResponse, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_watch_resp_is(r: Result[EtcdWatchResponse, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_txn_req_is(r: Result[EtcdTxnRequest, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn push_bytes(out: &mut Vec[UInt8], v: &Vec[UInt8]) {
  var i = 0;
  while i < v.len() {
    out.push(v[i]);
    i = i + 1;
  }
}

// Test-side u32 big-endian writer (independent of the library).
fn t_u32be(out: &mut Vec[UInt8], v: Int) {
  out.push((v / 16777216) as UInt8);
  out.push(((v / 65536) % 256) as UInt8);
  out.push(((v / 256) % 256) as UInt8);
  out.push((v % 256) as UInt8);
}

// Test-side varint writer for non-negative values.
fn t_varint(out: &mut Vec[UInt8], v: Int) {
  var x = v;
  while x >= 128 {
    out.push(((x % 128) + 128) as UInt8);
    x = x / 128;
  }
  out.push(x as UInt8);
}

// Test-side varint writer for any Int (negative values use the 10-byte
// sign-extended two's-complement form).
fn t_varint_signed(out: &mut Vec[UInt8], v: Int) {
  if v >= 0 {
    t_varint(out, v);
    return;
  }
  var x = v;
  var i = 0;
  while i < 9 {
    let m = ((x % 128) + 128) % 128;
    out.push((m + 128) as UInt8);
    x = (x - m) / 128;
    i = i + 1;
  }
  out.push(1 as UInt8);
}

fn t_key(out: &mut Vec[UInt8], field_number: Int, wire_type: Int) {
  t_varint(out, field_number * 8 + wire_type);
}

fn t_field_varint(out: &mut Vec[UInt8], field_number: Int, v: Int) {
  t_key(out, field_number, 0);
  t_varint(out, v);
}

fn t_field_i64(out: &mut Vec[UInt8], field_number: Int, v: Int) {
  t_key(out, field_number, 0);
  t_varint_signed(out, v);
}

fn t_field_str(out: &mut Vec[UInt8], field_number: Int, s: Str) {
  let b = bytes_of(s);
  t_key(out, field_number, 2);
  t_varint(out, b.len());
  push_bytes(out, &b);
}

fn t_field_bytes(out: &mut Vec[UInt8], field_number: Int, b: &Vec[UInt8]) {
  t_key(out, field_number, 2);
  t_varint(out, b.len());
  push_bytes(out, b);
}

// A whole gRPC frame built by the test (same layout as the library writer).
fn t_grpc(message: Vec[UInt8], flag: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  out.push(flag as UInt8);
  t_u32be(&mut out, message.len());
  push_bytes(&mut out, &message);
  return out;
}

// A nested ResponseHeader field.
fn t_header(out: &mut Vec[UInt8], field_number: Int, cluster: Int, member: Int, revision: Int, raft: Int) {
  var h = Vec[UInt8].new();
  t_field_varint(&mut h, 1, cluster);
  t_field_varint(&mut h, 2, member);
  t_field_varint(&mut h, 3, revision);
  t_field_varint(&mut h, 4, raft);
  t_field_bytes(out, field_number, &h);
}

// A nested KeyValue field.
fn t_kv(out: &mut Vec[UInt8], field_number: Int, key: Str, value: Str, create: Int, mod_rev: Int, ver: Int, lease: Int) {
  var kv = Vec[UInt8].new();
  t_field_str(&mut kv, 1, key);
  if create != 0 {
    t_field_varint(&mut kv, 2, create);
  }
  if mod_rev != 0 {
    t_field_varint(&mut kv, 3, mod_rev);
  }
  if ver != 0 {
    t_field_varint(&mut kv, 4, ver);
  }
  t_field_str(&mut kv, 5, value);
  if lease != 0 {
    t_field_varint(&mut kv, 6, lease);
  }
  t_field_bytes(out, field_number, &kv);
}

// A nested Member field.
fn t_member(out: &mut Vec[UInt8], field_number: Int, id: Int, name: Str, peers: &Vec[Vec[UInt8]], clients: &Vec[Vec[UInt8]], learner: Int) {
  var m = Vec[UInt8].new();
  t_field_varint(&mut m, 1, id);
  t_field_str(&mut m, 2, name);
  var i = 0;
  while i < peers.len() {
    let u: Vec[UInt8] = peers[i];
    t_field_bytes(&mut m, 3, &u);
    i = i + 1;
  }
  var j = 0;
  while j < clients.len() {
    let u: Vec[UInt8] = clients[j];
    t_field_bytes(&mut m, 4, &u);
    j = j + 1;
  }
  if learner != 0 {
    t_field_varint(&mut m, 5, 1);
  }
  t_field_bytes(out, field_number, &m);
}

// --------------------------------------------------
//  Wire primitives
// --------------------------------------------------

fn t1() -> TestResult {
  var ok = true;
  var vals = Vec[Int].new();
  vals.push(0);
  vals.push(1);
  vals.push(127);
  vals.push(128);
  vals.push(300);
  vals.push(16383);
  vals.push(16384);
  vals.push(4294967295);
  vals.push(9223372036854775807);
  var i = 0;
  while i < vals.len() {
    let v: Int = vals[i];
    let e = etcd_encode_varint(v);
    if !e.is_ok {
      ok = false;
    } else {
      let enc: Vec[UInt8] = e.value;
      let d = etcd_read_varint(&enc, 0);
      if !d.is_ok {
        ok = false;
      } else {
        let s: EtcdScalar = d.value;
        if s.value != v { ok = false; }
        if s.size != enc.len() { ok = false; }
      }
    }
    i = i + 1;
  }
  if !bytes_equal(enc_ok(etcd_encode_varint(300)), hb("ac02")) { ok = false; }
  if !bytes_equal(enc_ok(etcd_encode_varint(0)), hb("00")) { ok = false; }
  if etcd_max_varint_bytes() != 10 { ok = false; }
  return assert(ok, "varint boundaries round-trip (0,127,128,2^32-1,2^63-1)");
}

fn t2() -> TestResult {
  var ok = true;
  // 10 continuation bytes then an 11th: too long.
  var too_long = Vec[UInt8].new();
  var i = 0;
  while i < 10 {
    too_long.push(128 as UInt8);
    i = i + 1;
  }
  too_long.push(0 as UInt8);
  if !err_scalar_is(etcd_read_varint(&too_long, 0), "etcd: varint too long at offset 0") { ok = false; }
  // 10th byte with data bits above bit 0: 64-bit overflow.
  let overflow = hb("ffffffffffffffffff02");
  if !err_scalar_is(etcd_read_varint(&overflow, 0), "etcd: varint overflows 64 bits at offset 0") { ok = false; }
  // 10th byte carrying bit 63: outside the signed Int range.
  let signed_hi = hb("ffffffffffffffffff01");
  if !err_scalar_is(etcd_read_varint(&signed_hi, 0), "etcd: varint exceeds signed 64-bit range at offset 0") { ok = false; }
  let clip = hb("80");
  if !err_scalar_is(etcd_read_varint(&clip, 0), "etcd: truncated varint at offset 1") { ok = false; }
  if !err_scalar_is(etcd_read_varint(&clip, 5), "etcd: varint out of bounds at offset 5") { ok = false; }
  return assert(ok, "varint overflow, too-long, signed-range and truncation errors");
}

fn t3() -> TestResult {
  var ok = true;
  let two32 = enc_ok(etcd_encode_varint(4294967296));
  if !err_scalar_is(etcd_read_varint_u32(&two32, 0), "etcd: varint exceeds u32 at offset 0") { ok = false; }
  // Test-side sign-extended -1 (10 bytes).
  var neg = Vec[UInt8].new();
  t_varint_signed(&mut neg, -1);
  if neg.len() != 10 { ok = false; }
  let i32r = etcd_read_varint_i32(&neg, 0);
  if !i32r.is_ok {
    ok = false;
  } else {
    let s: EtcdScalar = i32r.value;
    if s.value != -1 { ok = false; }
    if s.size != 10 { ok = false; }
  }
  let i64r = etcd_read_varint_i64(&neg, 0);
  if !i64r.is_ok {
    ok = false;
  } else {
    let s: EtcdScalar = i64r.value;
    if s.value != -1 { ok = false; }
  }
  if !err_scalar_is(etcd_read_varint(&neg, 0), "etcd: varint exceeds signed 64-bit range at offset 0") { ok = false; }
  let five = hb("05");
  let i32b = etcd_read_varint_i32(&five, 0);
  if !i32b.is_ok {
    ok = false;
  } else {
    let s: EtcdScalar = i32b.value;
    if s.value != 5 { ok = false; }
  }
  return assert(ok, "u32/i32/i64 readers: u32 cap, sign-extended -1, small values");
}

fn t4() -> TestResult {
  var ok = true;
  let f32 = etcd_read_fixed32(hb("01000000"), 0);
  if !f32.is_ok {
    ok = false;
  } else {
    let s: EtcdScalar = f32.value;
    if s.value != 1 { ok = false; }
    if s.size != 4 { ok = false; }
  }
  let f32m = etcd_read_fixed32(hb("ffffffff"), 0);
  if !f32m.is_ok {
    ok = false;
  } else {
    let s: EtcdScalar = f32m.value;
    if s.value != 4294967295 { ok = false; }
  }
  if !err_scalar_is(etcd_read_fixed32(hb("0102"), 0), "etcd: truncated fixed32 at offset 2") { ok = false; }
  let f64 = etcd_read_fixed64(hb("0100000000000000"), 0);
  if !f64.is_ok {
    ok = false;
  } else {
    let s: EtcdScalar = f64.value;
    if s.value != 1 { ok = false; }
    if s.size != 8 { ok = false; }
  }
  if !err_scalar_is(etcd_read_fixed64(hb("ffffffffffffffff"), 0), "etcd: fixed64 exceeds signed 64-bit range at offset 0") { ok = false; }
  if !err_scalar_is(etcd_read_fixed64(hb("010203"), 0), "etcd: truncated fixed64 at offset 3") { ok = false; }
  return assert(ok, "fixed32/fixed64 reads, truncation and fixed64 range");
}

fn t5() -> TestResult {
  var ok = true;
  if etcd_key(9, 2) != 74 { ok = false; }
  if etcd_key_field_number(74) != 9 { ok = false; }
  if etcd_key_wire_type(74) != 2 { ok = false; }
  if etcd_key(1, 0) != 8 { ok = false; }
  if !bytes_equal(enc_ok(etcd_encode_key(1, 0)), hb("08")) { ok = false; }
  if !bytes_equal(enc_ok(etcd_encode_key(9, 2)), hb("4a")) { ok = false; }
  if !err_bytes_is(etcd_encode_key(0, 0), "etcd: bad field number") { ok = false; }
  if !err_bytes_is(etcd_encode_key(1, 3), "etcd: bad wire type") { ok = false; }
  return assert(ok, "field keys: encode, split and validation");
}

fn t6() -> TestResult {
  var ok = true;
  let d = etcd_read_delimited(hb("03414243"), 0);
  if !d.is_ok {
    ok = false;
  } else {
    let x: EtcdDelimited = d.value;
    if x.start != 1 { ok = false; }
    if x.size != 3 { ok = false; }
    if x.total != 4 { ok = false; }
  }
  if !err_delim_is(etcd_read_delimited(hb("054142"), 0), "etcd: truncated length-delimited field at offset 3") { ok = false; }
  if !err_delim_is(etcd_read_delimited(hb("80"), 0), "etcd: truncated varint at offset 1") { ok = false; }
  let empty = etcd_read_delimited(hb("00"), 0);
  if !empty.is_ok {
    ok = false;
  } else {
    let x: EtcdDelimited = empty.value;
    if x.size != 0 { ok = false; }
    if x.total != 1 { ok = false; }
  }
  return assert(ok, "length-delimited read, empty value and truncation");
}

fn t7() -> TestResult {
  var ok = true;
  let s0 = etcd_skip_field(hb("ac02"), 0, 0);
  if !s0.is_ok {
    ok = false;
  } else {
    let a: EtcdAdvance = s0.value;
    if a.pos != 2 { ok = false; }
    if a.size != 2 { ok = false; }
  }
  let s1 = etcd_skip_field(hb("0102030405060708"), 0, 1);
  if !s1.is_ok {
    ok = false;
  } else {
    let a: EtcdAdvance = s1.value;
    if a.pos != 8 { ok = false; }
  }
  let s2 = etcd_skip_field(hb("03414243"), 0, 2);
  if !s2.is_ok {
    ok = false;
  } else {
    let a: EtcdAdvance = s2.value;
    if a.pos != 4 { ok = false; }
  }
  let s5 = etcd_skip_field(hb("01020304"), 0, 5);
  if !s5.is_ok {
    ok = false;
  } else {
    let a: EtcdAdvance = s5.value;
    if a.pos != 4 { ok = false; }
  }
  if !err_advance_is(etcd_skip_field(hb("00"), 0, 3), "etcd: unsupported wire type 3 at offset 0") { ok = false; }
  if !err_advance_is(etcd_skip_field(hb("0102"), 0, 1), "etcd: truncated fixed64 at offset 2") { ok = false; }
  return assert(ok, "unknown-field skip for wire types 0/1/2/5 and rejection");
}

fn t8() -> TestResult {
  var ok = true;
  var out = Vec[Int].new();
  let r = etcd_read_packed_varints(hb("010203"), 0, 3, &mut out);
  if !r.is_ok {
    ok = false;
  } else {
    let n: Int = r.value;
    if n != 3 { ok = false; }
    if out.len() != 3 { ok = false; }
    let v0: Int = out[0];
    let v1: Int = out[1];
    let v2: Int = out[2];
    if v0 != 1 || v1 != 2 || v2 != 3 { ok = false; }
  }
  var out2 = Vec[Int].new();
  if !err_int_is(etcd_read_packed_varints(hb("8001"), 0, 1, &mut out2), "etcd: packed run crosses boundary at offset 0") { ok = false; }
  var out3 = Vec[Int].new();
  let r3 = etcd_read_packed_varints(hb("ac02"), 0, 2, &mut out3);
  if !r3.is_ok {
    ok = false;
  } else {
    let v: Int = out3[0];
    if v != 300 { ok = false; }
  }
  return assert(ok, "packed repeated varints: values, multi-byte and boundary");
}

// --------------------------------------------------
//  gRPC frame
// --------------------------------------------------

fn t9() -> TestResult {
  var ok = true;
  let msg = hb("0801");
  let frame = t_grpc(msg, 0);
  let r = etcd_parse_frame(&frame);
  if !r.is_ok {
    return assert(false, "grpc frame decodes: " + r.error);
  }
  let f: EtcdFrame = r.value;
  if etcd_frame_compressed(&f) != 0 { ok = false; }
  if etcd_frame_length(&f) != 2 { ok = false; }
  if !bytes_equal(etcd_frame_message(&f), msg) { ok = false; }
  if etcd_frame_consumed(&f) != 7 { ok = false; }
  if f.offset != 0 { ok = false; }
  if etcd_frame_consumed(&f) != frame.len() { ok = false; }
  // The compressed flag is preserved raw.
  let frame1 = t_grpc(msg, 1);
  let r1 = etcd_parse_frame(&frame1);
  if !r1.is_ok {
    ok = false;
  } else {
    let f1: EtcdFrame = r1.value;
    if etcd_frame_compressed(&f1) != 1 { ok = false; }
  }
  // encode -> parse round trip.
  let enc = etcd_encode_frame(&msg, 0);
  if !bytes_equal(enc, frame) { ok = false; }
  // Sequential frames via consumed counts.
  let msg2 = hb("1001");
  let frame2 = t_grpc(msg2, 0);
  var stream = Vec[UInt8].new();
  push_bytes(&mut stream, &frame);
  push_bytes(&mut stream, &frame2);
  let ra = etcd_parse_frame_at(&stream, 0);
  if !ra.is_ok {
    ok = false;
  } else {
    let fa: EtcdFrame = ra.value;
    if etcd_frame_consumed(&fa) != frame.len() { ok = false; }
    let rb = etcd_parse_frame_at(&stream, etcd_frame_consumed(&fa));
    if !rb.is_ok {
      ok = false;
    } else {
      let fb: EtcdFrame = rb.value;
      if !bytes_equal(etcd_frame_message(&fb), msg2) { ok = false; }
      if etcd_frame_consumed(&fb) != frame2.len() { ok = false; }
    }
  }
  if etcd_grpc_header_size() != 5 { ok = false; }
  if etcd_grpc_uncompressed() != 0 || etcd_grpc_compressed() != 1 { ok = false; }
  return assert(ok, "grpc frame: layout, consumed, flag, sequential parsing, round trip");
}

fn t10() -> TestResult {
  var ok = true;
  let empty = Vec[UInt8].new();
  if !err_frame_is(etcd_parse_frame(&empty), "etcd: truncated grpc frame header at offset 0") { ok = false; }
  let one = hb("00");
  if !err_frame_is(etcd_parse_frame(&one), "etcd: truncated grpc frame header at offset 1") { ok = false; }
  let short = hb("0000000005");
  if !err_frame_is(etcd_parse_frame(&short), "etcd: truncated grpc frame at offset 5") { ok = false; }
  let huge = hb("0001000001");
  if !err_frame_is(etcd_parse_frame(&huge), "etcd: grpc message exceeds 8 MiB at offset 0") { ok = false; }
  let frame = t_grpc(hb("0801"), 0);
  if !err_frame_is(etcd_parse_frame_at(&frame, -1), "etcd: negative frame offset") { ok = false; }
  if etcd_max_message_bytes() != 8388608 { ok = false; }
  return assert(ok, "grpc frame malformed lengths and byte-offset errors");
}

// --------------------------------------------------
//  Header, KeyValue, Range
// --------------------------------------------------

// Standalone ResponseHeader body (no enclosing field).
fn t_header_body(out: &mut Vec[UInt8], cluster: Int, member: Int, revision: Int, raft: Int) {
  t_field_varint(out, 1, cluster);
  t_field_varint(out, 2, member);
  t_field_varint(out, 3, revision);
  t_field_varint(out, 4, raft);
}

// Standalone KeyValue body (no enclosing field).
fn t_kv_body(out: &mut Vec[UInt8], key: Str, value: Str, create: Int, mod_rev: Int, ver: Int, lease: Int) {
  t_field_str(out, 1, key);
  if create != 0 {
    t_field_varint(out, 2, create);
  }
  if mod_rev != 0 {
    t_field_varint(out, 3, mod_rev);
  }
  if ver != 0 {
    t_field_varint(out, 4, ver);
  }
  t_field_str(out, 5, value);
  if lease != 0 {
    t_field_varint(out, 6, lease);
  }
}

fn t11() -> TestResult {
  var ok = true;
  var body = Vec[UInt8].new();
  t_header_body(&mut body, 11, 22, 33, 44);
  let r = etcd_decode_header(&body);
  if !r.is_ok {
    return assert(false, "header decodes: " + r.error);
  }
  let h: EtcdHeader = r.value;
  if !etcd_header_present(&h) { ok = false; }
  if etcd_header_cluster_id(&h) != 11 { ok = false; }
  if etcd_header_member_id(&h) != 22 { ok = false; }
  if etcd_header_revision(&h) != 33 { ok = false; }
  if etcd_header_raft_term(&h) != 44 { ok = false; }
  if etcd_unknown_count(&h.unknown) != 0 { ok = false; }
  // Empty header keeps present = false.
  let re = etcd_decode_header(&Vec[UInt8].new());
  if !re.is_ok {
    ok = false;
  } else {
    let he: EtcdHeader = re.value;
    if etcd_header_present(&he) { ok = false; }
  }
  // KeyValue round trip.
  var kb = Vec[UInt8].new();
  t_kv_body(&mut kb, "k", "v", 1, 2, 3, 4);
  let kr = etcd_decode_key_value(&kb);
  if !kr.is_ok {
    ok = false;
  } else {
    let kv: EtcdKeyValue = kr.value;
    if !bytes_equal(etcd_kv_key(&kv), bytes_of("k")) { ok = false; }
    if !bytes_equal(etcd_kv_value(&kv), bytes_of("v")) { ok = false; }
    if etcd_kv_create_revision(&kv) != 1 { ok = false; }
    if etcd_kv_mod_revision(&kv) != 2 { ok = false; }
    if etcd_kv_version(&kv) != 3 { ok = false; }
    if etcd_kv_lease(&kv) != 4 { ok = false; }
  }
  // Unknown field on a KeyValue is counted and preserved raw.
  var kb2 = Vec[UInt8].new();
  t_field_str(&mut kb2, 1, "k");
  t_field_varint(&mut kb2, 9, 7);
  let kr2 = etcd_decode_key_value(&kb2);
  if !kr2.is_ok {
    ok = false;
  } else {
    let kv2: EtcdKeyValue = kr2.value;
    if etcd_unknown_count(&kv2.unknown) != 1 { ok = false; }
    if etcd_unknown_bytes(&kv2.unknown).len() == 0 { ok = false; }
  }
  return assert(ok, "ResponseHeader and KeyValue decode, defaults and unknown count");
}

fn t12() -> TestResult {
  var ok = true;
  var body = Vec[UInt8].new();
  t_field_str(&mut body, 1, "a");
  t_field_str(&mut body, 2, "z");
  t_field_varint(&mut body, 3, 5);
  t_field_varint(&mut body, 4, 7);
  t_field_varint(&mut body, 5, 1);
  t_field_varint(&mut body, 6, 4);
  t_field_varint(&mut body, 7, 1);
  t_field_varint(&mut body, 8, 1);
  t_field_varint(&mut body, 9, 0);
  t_field_i64(&mut body, 10, -1);
  t_field_varint(&mut body, 11, 9);
  t_field_varint(&mut body, 12, 1);
  t_field_varint(&mut body, 13, 8);
  let r = etcd_decode_range_request(&body);
  if !r.is_ok {
    return assert(false, "range request decodes: " + r.error);
  }
  let req: EtcdRangeRequest = r.value;
  if !bytes_equal(req.key, bytes_of("a")) { ok = false; }
  if !bytes_equal(req.range_end, bytes_of("z")) { ok = false; }
  if req.limit != 5 { ok = false; }
  if req.revision != 7 { ok = false; }
  if req.sort_order != etcd_sort_ascend() { ok = false; }
  if req.sort_target != etcd_sort_target_value() { ok = false; }
  if !req.serializable { ok = false; }
  if !req.keys_only { ok = false; }
  if req.count_only { ok = false; }
  if req.min_mod_revision != -1 { ok = false; }
  if req.max_mod_revision != 9 { ok = false; }
  if req.min_create_revision != 1 { ok = false; }
  if req.max_create_revision != 8 { ok = false; }
  if !str_eq(etcd_sort_order_name(req.sort_order), "ASCEND") { ok = false; }
  if !str_eq(etcd_sort_target_name(req.sort_target), "VALUE") { ok = false; }
  if !str_eq(etcd_sort_order_name(99), "UNKNOWN") { ok = false; }
  // Empty request keeps every default.
  let re = etcd_decode_range_request(&Vec[UInt8].new());
  if !re.is_ok {
    ok = false;
  } else {
    let reqe: EtcdRangeRequest = re.value;
    if reqe.limit != 0 || reqe.serializable || reqe.keys_only || reqe.count_only { ok = false; }
    if !str_eq(etcd_sort_order_name(reqe.sort_order), "NONE") { ok = false; }
  }
  return assert(ok, "RangeRequest: all 13 fields, enums, defaults, names");
}

fn t13() -> TestResult {
  var ok = true;
  var body = Vec[UInt8].new();
  t_header(&mut body, 1, 1, 2, 5, 6);
  t_kv(&mut body, 2, "a", "va", 1, 5, 2, 0);
  t_kv(&mut body, 2, "b", "vb", 2, 6, 1, 7);
  t_field_varint(&mut body, 3, 1);
  t_field_varint(&mut body, 4, 2);
  let r = etcd_decode_range_response(&body);
  if !r.is_ok {
    return assert(false, "range response decodes: " + r.error);
  }
  let resp: EtcdRangeResponse = r.value;
  if !etcd_header_present(&resp.header) { ok = false; }
  if etcd_header_revision(&resp.header) != 5 { ok = false; }
  if etcd_kvlist_count(&resp.kvs) != 2 { ok = false; }
  if !resp.more { ok = false; }
  if resp.count != 2 { ok = false; }
  let kv0: EtcdKeyValue = etcd_kvlist_get(&resp.kvs, 0);
  if !bytes_equal(etcd_kv_key(&kv0), bytes_of("a")) { ok = false; }
  if !bytes_equal(etcd_kv_value(&kv0), bytes_of("va")) { ok = false; }
  if etcd_kv_create_revision(&kv0) != 1 { ok = false; }
  if etcd_kv_mod_revision(&kv0) != 5 { ok = false; }
  if etcd_kv_version(&kv0) != 2 { ok = false; }
  if etcd_kv_lease(&kv0) != 0 { ok = false; }
  let kv1: EtcdKeyValue = etcd_kvlist_get(&resp.kvs, 1);
  if !bytes_equal(etcd_kv_key(&kv1), bytes_of("b")) { ok = false; }
  if !bytes_equal(etcd_kv_value(&kv1), bytes_of("vb")) { ok = false; }
  if etcd_kv_lease(&kv1) != 7 { ok = false; }
  if !bytes_equal(etcd_kvlist_key(&resp.kvs, 1), bytes_of("b")) { ok = false; }
  if !bytes_equal(etcd_kvlist_value(&resp.kvs, 1), bytes_of("vb")) { ok = false; }
  // Out-of-range get returns defaults.
  let kvx: EtcdKeyValue = etcd_kvlist_get(&resp.kvs, 9);
  if etcd_kv_key(&kvx).len() != 0 { ok = false; }
  if etcd_kv_lease(&kvx) != 0 { ok = false; }
  if etcd_unknown_count(&resp.unknown) != 0 { ok = false; }
  return assert(ok, "RangeResponse: header, two kvs, more/count, parallel list integrity");
}

// --------------------------------------------------
//  Put/Delete, Txn, Watch
// --------------------------------------------------

fn t14() -> TestResult {
  var ok = true;
  var pb = Vec[UInt8].new();
  t_field_str(&mut pb, 1, "pk");
  t_field_str(&mut pb, 2, "pv");
  t_field_varint(&mut pb, 3, 9);
  t_field_varint(&mut pb, 4, 1);
  t_field_varint(&mut pb, 5, 0);
  t_field_varint(&mut pb, 6, 1);
  let r = etcd_decode_put_request(&pb);
  if !r.is_ok {
    return assert(false, "put request decodes: " + r.error);
  }
  let pr: EtcdPutRequest = r.value;
  if !bytes_equal(pr.key, bytes_of("pk")) { ok = false; }
  if !bytes_equal(pr.value, bytes_of("pv")) { ok = false; }
  if pr.lease != 9 { ok = false; }
  if !pr.prev_kv { ok = false; }
  if pr.ignore_value { ok = false; }
  if !pr.ignore_lease { ok = false; }
  var pbr = Vec[UInt8].new();
  t_header(&mut pbr, 1, 3, 4, 10, 2);
  t_kv(&mut pbr, 2, "pk", "old", 0, 4, 1, 0);
  let rr = etcd_decode_put_response(&pbr);
  if !rr.is_ok {
    ok = false;
  } else {
    let presp: EtcdPutResponse = rr.value;
    if !presp.has_prev_kv { ok = false; }
    if !bytes_equal(etcd_kv_key(&presp.prev_kv), bytes_of("pk")) { ok = false; }
    if !bytes_equal(etcd_kv_value(&presp.prev_kv), bytes_of("old")) { ok = false; }
    if etcd_kv_mod_revision(&presp.prev_kv) != 4 { ok = false; }
    if etcd_header_revision(&presp.header) != 10 { ok = false; }
  }
  var db = Vec[UInt8].new();
  t_field_str(&mut db, 1, "dk");
  t_field_str(&mut db, 2, "dz");
  t_field_varint(&mut db, 3, 1);
  let dr = etcd_decode_delete_range_request(&db);
  if !dr.is_ok {
    ok = false;
  } else {
    let dq: EtcdDeleteRangeRequest = dr.value;
    if !bytes_equal(dq.key, bytes_of("dk")) { ok = false; }
    if !bytes_equal(dq.range_end, bytes_of("dz")) { ok = false; }
    if !dq.prev_kv { ok = false; }
  }
  var dbr = Vec[UInt8].new();
  t_header(&mut dbr, 1, 1, 1, 20, 1);
  t_field_varint(&mut dbr, 2, 3);
  t_kv(&mut dbr, 3, "p1", "v1", 0, 19, 1, 0);
  t_kv(&mut dbr, 3, "p2", "v2", 0, 18, 1, 0);
  let drr = etcd_decode_delete_range_response(&dbr);
  if !drr.is_ok {
    ok = false;
  } else {
    let dresp: EtcdDeleteRangeResponse = drr.value;
    if dresp.deleted != 3 { ok = false; }
    if etcd_kvlist_count(&dresp.prev_kvs) != 2 { ok = false; }
    if !bytes_equal(etcd_kvlist_key(&dresp.prev_kvs, 1), bytes_of("p2")) { ok = false; }
    if etcd_header_revision(&dresp.header) != 20 { ok = false; }
  }
  return assert(ok, "PutRequest/PutResponse and DeleteRangeRequest/Response");
}

fn t15() -> TestResult {
  var ok = true;
  var cmp1 = Vec[UInt8].new();
  t_field_varint(&mut cmp1, 1, 0);
  t_field_varint(&mut cmp1, 2, 3);
  t_field_str(&mut cmp1, 3, "k");
  t_field_str(&mut cmp1, 7, "v");
  var cmp2 = Vec[UInt8].new();
  t_field_varint(&mut cmp2, 1, 1);
  t_field_varint(&mut cmp2, 2, 0);
  t_field_str(&mut cmp2, 3, "k2");
  t_field_varint(&mut cmp2, 4, 9);
  var range_body = Vec[UInt8].new();
  t_field_str(&mut range_body, 1, "a");
  var op1 = Vec[UInt8].new();
  t_field_bytes(&mut op1, 1, &range_body);
  let empty_txn = Vec[UInt8].new();
  var op2 = Vec[UInt8].new();
  t_field_bytes(&mut op2, 4, &empty_txn);
  var body = Vec[UInt8].new();
  t_field_bytes(&mut body, 1, &cmp1);
  t_field_bytes(&mut body, 1, &cmp2);
  t_field_bytes(&mut body, 2, &op1);
  t_field_bytes(&mut body, 3, &op2);
  let r = etcd_decode_txn_request(&body);
  if !r.is_ok {
    return assert(false, "txn request decodes: " + r.error);
  }
  let txn: EtcdTxnRequest = r.value;
  if etcd_cmp_count(&txn.compares) != 2 { ok = false; }
  let c0: EtcdCompare = etcd_cmp_get(&txn.compares, 0);
  if c0.result != etcd_compare_result_equal() { ok = false; }
  if c0.target != etcd_compare_target_value() { ok = false; }
  if !bytes_equal(c0.key, bytes_of("k")) { ok = false; }
  if c0.union_field != 7 { ok = false; }
  if !bytes_equal(c0.value, bytes_of("v")) { ok = false; }
  let c1: EtcdCompare = etcd_cmp_get(&txn.compares, 1);
  if c1.result != etcd_compare_result_greater() { ok = false; }
  if c1.union_field != 4 { ok = false; }
  if c1.version != 9 { ok = false; }
  if etcd_cmp_result(&txn.compares, 1) != 1 { ok = false; }
  if etcd_cmp_target(&txn.compares, 0) != 3 { ok = false; }
  if !bytes_equal(etcd_cmp_key(&txn.compares, 1), bytes_of("k2")) { ok = false; }
  if etcd_cmp_union_field(&txn.compares, 0) != 7 { ok = false; }
  if !str_eq(etcd_compare_result_name(c1.result), "GREATER") { ok = false; }
  if !str_eq(etcd_compare_target_name(c1.target), "VERSION") { ok = false; }
  if etcd_oplist_count(&txn.success) != 1 { ok = false; }
  if etcd_oplist_count(&txn.failure) != 1 { ok = false; }
  if etcd_oplist_kind(&txn.success, 0) != etcd_op_range() { ok = false; }
  if etcd_oplist_kind(&txn.failure, 0) != etcd_op_txn() { ok = false; }
  if !str_eq(etcd_op_name(etcd_oplist_kind(&txn.success, 0)), "RANGE") { ok = false; }
  // Re-decode the preserved raw RequestOp bodies.
  let raw0: Vec[UInt8] = etcd_oplist_raw(&txn.success, 0);
  let rr = etcd_parse_range_request_body(&raw0, 0, raw0.len(), 1);
  if !rr.is_ok {
    ok = false;
  } else {
    let rreq: EtcdRangeRequest = rr.value;
    if !bytes_equal(rreq.key, bytes_of("a")) { ok = false; }
  }
  let raw1: Vec[UInt8] = etcd_oplist_raw(&txn.failure, 0);
  if raw1.len() != 0 { ok = false; }
  // Out-of-range gets return defaults.
  let cx: EtcdCompare = etcd_cmp_get(&txn.compares, 5);
  if cx.result != 0 { ok = false; }
  if etcd_oplist_kind(&txn.success, 5) != 0 { ok = false; }
  return assert(ok, "Compare + TxnRequest: compares, one-of op kinds, raw re-decode");
}

fn t16() -> TestResult {
  var ok = true;
  var range_resp = Vec[UInt8].new();
  t_field_varint(&mut range_resp, 4, 2);
  var op1 = Vec[UInt8].new();
  t_field_bytes(&mut op1, 1, &range_resp);
  let empty_put = Vec[UInt8].new();
  var op2 = Vec[UInt8].new();
  t_field_bytes(&mut op2, 2, &empty_put);
  var body = Vec[UInt8].new();
  t_header(&mut body, 1, 1, 1, 42, 3);
  t_field_varint(&mut body, 2, 1);
  t_field_bytes(&mut body, 3, &op1);
  t_field_bytes(&mut body, 3, &op2);
  let r = etcd_decode_txn_response(&body);
  if !r.is_ok {
    return assert(false, "txn response decodes: " + r.error);
  }
  let resp: EtcdTxnResponse = r.value;
  if !resp.succeeded { ok = false; }
  if etcd_header_revision(&resp.header) != 42 { ok = false; }
  if etcd_oplist_count(&resp.responses) != 2 { ok = false; }
  if etcd_oplist_kind(&resp.responses, 0) != etcd_op_range() { ok = false; }
  if etcd_oplist_kind(&resp.responses, 1) != etcd_op_put() { ok = false; }
  let raw0: Vec[UInt8] = etcd_oplist_raw(&resp.responses, 0);
  let rr = etcd_parse_range_response_body(&raw0, 0, raw0.len(), 1);
  if !rr.is_ok {
    ok = false;
  } else {
    let rresp: EtcdRangeResponse = rr.value;
    if rresp.count != 2 { ok = false; }
  }
  return assert(ok, "TxnResponse: succeeded, response op one-of dispatch, raw re-decode");
}

fn t17() -> TestResult {
  var ok = true;
  var create = Vec[UInt8].new();
  t_field_str(&mut create, 1, "wk");
  t_field_str(&mut create, 2, "wz");
  t_field_varint(&mut create, 3, 5);
  t_field_varint(&mut create, 4, 1);
  t_field_varint(&mut create, 5, 0);
  var packed = Vec[UInt8].new();
  t_varint(&mut packed, 0);
  t_varint(&mut packed, 1);
  t_field_bytes(&mut create, 5, &packed);
  t_field_varint(&mut create, 6, 1);
  t_field_varint(&mut create, 7, 9);
  t_field_varint(&mut create, 8, 1);
  var body = Vec[UInt8].new();
  t_field_bytes(&mut body, 1, &create);
  let r = etcd_decode_watch_request(&body);
  if !r.is_ok {
    return assert(false, "watch create decodes: " + r.error);
  }
  let w: EtcdWatchRequest = r.value;
  if w.kind != 1 { ok = false; }
  if !bytes_equal(w.key, bytes_of("wk")) { ok = false; }
  if !bytes_equal(w.range_end, bytes_of("wz")) { ok = false; }
  if w.start_revision != 5 { ok = false; }
  if !w.progress_notify { ok = false; }
  if !w.prev_kv { ok = false; }
  if w.watch_id != 9 { ok = false; }
  if !w.fragment { ok = false; }
  if etcd_watch_filter_count(&w) != 3 { ok = false; }
  if etcd_watch_filter(&w, 0) != etcd_filter_noput() { ok = false; }
  if etcd_watch_filter(&w, 2) != etcd_filter_nodelete() { ok = false; }
  if !str_eq(etcd_watch_filter_name(etcd_filter_noput()), "NOPUT") { ok = false; }
  if !str_eq(etcd_watch_filter_name(5), "UNKNOWN") { ok = false; }
  // cancel branch.
  var cancel = Vec[UInt8].new();
  t_field_varint(&mut cancel, 1, 42);
  var body2 = Vec[UInt8].new();
  t_field_bytes(&mut body2, 2, &cancel);
  let r2 = etcd_decode_watch_request(&body2);
  if !r2.is_ok {
    ok = false;
  } else {
    let w2: EtcdWatchRequest = r2.value;
    if w2.kind != 2 { ok = false; }
    if w2.cancel_watch_id != 42 { ok = false; }
  }
  // progress branch.
  let empty = Vec[UInt8].new();
  var body3 = Vec[UInt8].new();
  t_field_bytes(&mut body3, 3, &empty);
  let r3 = etcd_decode_watch_request(&body3);
  if !r3.is_ok {
    ok = false;
  } else {
    let w3: EtcdWatchRequest = r3.value;
    if w3.kind != 3 { ok = false; }
  }
  return assert(ok, "WatchRequest: create (packed+unpacked filters), cancel, progress");
}

fn t18() -> TestResult {
  var ok = true;
  var ev1 = Vec[UInt8].new();
  t_field_varint(&mut ev1, 1, 0);
  t_kv(&mut ev1, 2, "a", "va", 0, 5, 1, 0);
  var ev2 = Vec[UInt8].new();
  t_field_varint(&mut ev2, 1, 1);
  t_kv(&mut ev2, 2, "b", "", 0, 6, 1, 0);
  t_kv(&mut ev2, 3, "b", "vb", 0, 4, 1, 0);
  var body = Vec[UInt8].new();
  t_header(&mut body, 1, 1, 1, 50, 5);
  t_field_varint(&mut body, 2, 7);
  t_field_varint(&mut body, 3, 1);
  t_field_str(&mut body, 6, "reason");
  t_field_varint(&mut body, 7, 1);
  t_field_bytes(&mut body, 11, &ev1);
  t_field_bytes(&mut body, 11, &ev2);
  let r = etcd_decode_watch_response(&body);
  if !r.is_ok {
    return assert(false, "watch response decodes: " + r.error);
  }
  let wr: EtcdWatchResponse = r.value;
  if wr.watch_id != 7 { ok = false; }
  if !wr.created { ok = false; }
  if wr.canceled { ok = false; }
  if !wr.fragment { ok = false; }
  if !str_eq(wr.cancel_reason, "reason") { ok = false; }
  if etcd_watch_event_count(&wr) != 2 { ok = false; }
  if etcd_watch_event_type(&wr, 0) != etcd_event_put() { ok = false; }
  if etcd_watch_event_type(&wr, 1) != etcd_event_delete() { ok = false; }
  if !str_eq(etcd_event_type_name(etcd_event_delete()), "DELETE") { ok = false; }
  let e0: EtcdEvent = etcd_watch_event_get(&wr, 0);
  if e0.kv_present != 1 { ok = false; }
  if e0.prev_present != 0 { ok = false; }
  if !bytes_equal(etcd_kv_key(&e0.kv), bytes_of("a")) { ok = false; }
  if !bytes_equal(etcd_kv_value(&e0.kv), bytes_of("va")) { ok = false; }
  if etcd_kv_mod_revision(&e0.kv) != 5 { ok = false; }
  let e1: EtcdEvent = etcd_watch_event_get(&wr, 1);
  if e1.kv_present != 1 { ok = false; }
  if e1.prev_present != 1 { ok = false; }
  if !bytes_equal(etcd_kv_key(&e1.prev), bytes_of("b")) { ok = false; }
  if !bytes_equal(etcd_kv_value(&e1.prev), bytes_of("vb")) { ok = false; }
  if etcd_kv_mod_revision(&e1.prev) != 4 { ok = false; }
  if !bytes_equal(etcd_watch_event_kv_key(&wr, 1), bytes_of("b")) { ok = false; }
  if !bytes_equal(etcd_watch_event_prev_key(&wr, 1), bytes_of("b")) { ok = false; }
  if etcd_watch_event_prev_key(&wr, 0).len() != 0 { ok = false; }
  let ex: EtcdEvent = etcd_watch_event_get(&wr, 9);
  if ex.kv_present != 0 { ok = false; }
  return assert(ok, "WatchResponse: events, kv/prev_kv, types, mirror integrity");
}

// --------------------------------------------------
//  Lease, Auth
// --------------------------------------------------

fn t19() -> TestResult {
  var ok = true;
  var g = Vec[UInt8].new();
  t_field_varint(&mut g, 1, 60);
  t_field_varint(&mut g, 2, 9);
  let r = etcd_decode_lease_grant_request(&g);
  if !r.is_ok {
    return assert(false, "lease grant request decodes: " + r.error);
  }
  let greq: EtcdLeaseGrantRequest = r.value;
  if greq.ttl != 60 { ok = false; }
  if greq.id != 9 { ok = false; }
  var gr = Vec[UInt8].new();
  t_header(&mut gr, 1, 1, 1, 3, 1);
  t_field_varint(&mut gr, 2, 9);
  t_field_varint(&mut gr, 3, 60);
  t_field_str(&mut gr, 4, "oops");
  let rr = etcd_decode_lease_grant_response(&gr);
  if !rr.is_ok {
    ok = false;
  } else {
    let gresp: EtcdLeaseGrantResponse = rr.value;
    if gresp.id != 9 { ok = false; }
    if gresp.ttl != 60 { ok = false; }
    if !gresp.has_error_text { ok = false; }
    if !str_eq(gresp.error_text, "oops") { ok = false; }
  }
  var k = Vec[UInt8].new();
  t_field_varint(&mut k, 1, 5);
  let kr = etcd_decode_lease_keep_alive_request(&k);
  if !kr.is_ok {
    ok = false;
  } else {
    let kreq: EtcdLeaseKeepAliveRequest = kr.value;
    if kreq.id != 5 { ok = false; }
  }
  var kresp = Vec[UInt8].new();
  t_header(&mut kresp, 1, 1, 1, 3, 1);
  t_field_varint(&mut kresp, 2, 5);
  t_field_varint(&mut kresp, 3, 30);
  let krr = etcd_decode_lease_keep_alive_response(&kresp);
  if !krr.is_ok {
    ok = false;
  } else {
    let kp: EtcdLeaseKeepAliveResponse = krr.value;
    if kp.id != 5 { ok = false; }
    if kp.ttl != 30 { ok = false; }
  }
  var rv = Vec[UInt8].new();
  t_field_varint(&mut rv, 1, 6);
  let rvr = etcd_decode_lease_revoke_request(&rv);
  if !rvr.is_ok {
    ok = false;
  } else {
    let rq: EtcdLeaseRevokeRequest = rvr.value;
    if rq.id != 6 { ok = false; }
  }
  var rhdr = Vec[UInt8].new();
  t_header(&mut rhdr, 1, 1, 1, 3, 1);
  let rhr = etcd_decode_lease_revoke_response(&rhdr);
  if !rhr.is_ok {
    ok = false;
  } else {
    let rh: EtcdHeader = rhr.value;
    if !etcd_header_present(&rh) { ok = false; }
    if etcd_header_member_id(&rh) != 1 { ok = false; }
    if etcd_header_revision(&rh) != 3 { ok = false; }
  }
  var ttlq = Vec[UInt8].new();
  t_field_varint(&mut ttlq, 1, 6);
  t_field_varint(&mut ttlq, 2, 1);
  let tq = etcd_decode_lease_time_to_live_request(&ttlq);
  if !tq.is_ok {
    ok = false;
  } else {
    let tqr: EtcdLeaseTimeToLiveRequest = tq.value;
    if tqr.id != 6 { ok = false; }
    if !tqr.keys { ok = false; }
  }
  var ttla = Vec[UInt8].new();
  t_header(&mut ttla, 1, 1, 1, 8, 1);
  t_field_varint(&mut ttla, 2, 6);
  t_field_varint(&mut ttla, 3, 10);
  t_field_varint(&mut ttla, 4, 20);
  let ka = bytes_of("ka");
  let kb = bytes_of("kb");
  t_field_bytes(&mut ttla, 5, &ka);
  t_field_bytes(&mut ttla, 5, &kb);
  let ta = etcd_decode_lease_time_to_live_response(&ttla);
  if !ta.is_ok {
    ok = false;
  } else {
    let tar: EtcdLeaseTimeToLiveResponse = ta.value;
    if tar.id != 6 { ok = false; }
    if tar.ttl != 10 { ok = false; }
    if tar.granted_ttl != 20 { ok = false; }
    if etcd_ttl_key_count(&tar) != 2 { ok = false; }
    if !bytes_equal(etcd_ttl_key(&tar, 0), bytes_of("ka")) { ok = false; }
    if !bytes_equal(etcd_ttl_key(&tar, 1), bytes_of("kb")) { ok = false; }
  }
  return assert(ok, "Lease: grant, keepalive, revoke, time-to-live (with keys)");
}

fn t20() -> TestResult {
  var ok = true;
  var areq = Vec[UInt8].new();
  t_field_str(&mut areq, 1, "root");
  t_field_str(&mut areq, 2, "pw");
  let r = etcd_decode_authenticate_request(&areq);
  if !r.is_ok {
    return assert(false, "authenticate request decodes: " + r.error);
  }
  let aq: EtcdAuthenticateRequest = r.value;
  if !str_eq(aq.name, "root") { ok = false; }
  if !str_eq(aq.password, "pw") { ok = false; }
  var aresp = Vec[UInt8].new();
  t_header(&mut aresp, 1, 1, 1, 4, 1);
  t_field_str(&mut aresp, 2, "tok");
  let rr = etcd_decode_authenticate_response(&aresp);
  if !rr.is_ok {
    ok = false;
  } else {
    let ar: EtcdAuthenticateResponse = rr.value;
    if !str_eq(ar.token, "tok") { ok = false; }
    if etcd_header_revision(&ar.header) != 4 { ok = false; }
  }
  var ua = Vec[UInt8].new();
  t_field_str(&mut ua, 1, "u");
  t_field_str(&mut ua, 2, "p");
  let opts = hb("aabb");
  t_field_bytes(&mut ua, 3, &opts);
  t_field_str(&mut ua, 4, "h");
  let ur = etcd_decode_user_add_request(&ua);
  if !ur.is_ok {
    ok = false;
  } else {
    let uq: EtcdUserAddRequest = ur.value;
    if !str_eq(uq.name, "u") { ok = false; }
    if !str_eq(uq.password, "p") { ok = false; }
    if !uq.has_options { ok = false; }
    if !bytes_equal(uq.options_raw, hb("aabb")) { ok = false; }
    if !uq.has_hashed_password { ok = false; }
    if !str_eq(uq.hashed_password, "h") { ok = false; }
  }
  var ra = Vec[UInt8].new();
  t_field_str(&mut ra, 1, "r");
  let rar = etcd_decode_role_add_request(&ra);
  if !rar.is_ok {
    ok = false;
  } else {
    let rq: EtcdRoleAddRequest = rar.value;
    if !str_eq(rq.name, "r") { ok = false; }
  }
  return assert(ok, "Auth: authenticate, user add (options raw), role add");
}

// --------------------------------------------------
//  Maintenance
// --------------------------------------------------

fn t21() -> TestResult {
  var ok = true;
  var sb = Vec[UInt8].new();
  t_header(&mut sb, 1, 7, 8, 900, 6);
  t_field_str(&mut sb, 2, "3.5.0");
  t_field_varint(&mut sb, 3, 100);
  t_field_varint(&mut sb, 4, 2);
  t_field_varint(&mut sb, 5, 300);
  t_field_varint(&mut sb, 6, 4);
  t_field_varint(&mut sb, 7, 90);
  t_field_varint(&mut sb, 8, 1);
  let r = etcd_decode_status_response(&sb);
  if !r.is_ok {
    return assert(false, "status response decodes: " + r.error);
  }
  let st: EtcdStatusResponse = r.value;
  if !str_eq(st.version, "3.5.0") { ok = false; }
  if st.db_size != 100 { ok = false; }
  if st.leader != 2 { ok = false; }
  if st.raft_index != 300 { ok = false; }
  if st.raft_term != 4 { ok = false; }
  if st.db_size_in_use != 90 { ok = false; }
  if !st.is_learner { ok = false; }
  if etcd_header_cluster_id(&st.header) != 7 { ok = false; }
  if etcd_header_member_id(&st.header) != 8 { ok = false; }
  var peers1 = Vec[Vec[UInt8]].new();
  peers1.push(bytes_of("http://p1"));
  peers1.push(bytes_of("http://p2"));
  var clients1 = Vec[Vec[UInt8]].new();
  clients1.push(bytes_of("http://c1"));
  var peers2 = Vec[Vec[UInt8]].new();
  peers2.push(bytes_of("http://p3"));
  var clients2 = Vec[Vec[UInt8]].new();
  clients2.push(bytes_of("http://c2"));
  clients2.push(bytes_of("http://c3"));
  var mb = Vec[UInt8].new();
  t_header(&mut mb, 1, 1, 1, 1000, 2);
  t_member(&mut mb, 2, 1, "n1", &peers1, &clients1, 0);
  t_member(&mut mb, 2, 2, "n2", &peers2, &clients2, 1);
  let mr = etcd_decode_member_list_response(&mb);
  if !mr.is_ok {
    return assert(false, "member list decodes: " + mr.error);
  }
  let ml: EtcdMemberListResponse = mr.value;
  if etcd_member_count(&ml) != 2 { ok = false; }
  if etcd_member_id(&ml, 0) != 1 { ok = false; }
  if etcd_member_id(&ml, 1) != 2 { ok = false; }
  if !bytes_equal(etcd_member_name(&ml, 0), bytes_of("n1")) { ok = false; }
  if !bytes_equal(etcd_member_name(&ml, 1), bytes_of("n2")) { ok = false; }
  if etcd_member_is_learner(&ml, 0) { ok = false; }
  if !etcd_member_is_learner(&ml, 1) { ok = false; }
  if etcd_member_peer_count(&ml, 0) != 2 { ok = false; }
  if etcd_member_peer_count(&ml, 1) != 1 { ok = false; }
  if !bytes_equal(etcd_member_peer_url(&ml, 0, 1), bytes_of("http://p2")) { ok = false; }
  if !bytes_equal(etcd_member_peer_url(&ml, 1, 0), bytes_of("http://p3")) { ok = false; }
  if etcd_member_client_count(&ml, 0) != 1 { ok = false; }
  if etcd_member_client_count(&ml, 1) != 2 { ok = false; }
  if !bytes_equal(etcd_member_client_url(&ml, 1, 1), bytes_of("http://c3")) { ok = false; }
  if etcd_member_peer_url(&ml, 0, 9).len() != 0 { ok = false; }
  if etcd_member_peer_count(&ml, 9) != 0 { ok = false; }
  if etcd_header_revision(&ml.header) != 1000 { ok = false; }
  return assert(ok, "StatusResponse and MemberListResponse (URL runs, learners)");
}

fn t22() -> TestResult {
  var ok = true;
  var ab = Vec[UInt8].new();
  t_field_varint(&mut ab, 1, 1);
  t_field_varint(&mut ab, 2, 5);
  t_field_varint(&mut ab, 3, 1);
  let r = etcd_decode_alarm_request(&ab);
  if !r.is_ok {
    return assert(false, "alarm request decodes: " + r.error);
  }
  let aq: EtcdAlarmRequest = r.value;
  if aq.alarm != etcd_alarm_type_nospace() { ok = false; }
  if aq.member_id != 5 { ok = false; }
  if aq.action != etcd_alarm_action_activate() { ok = false; }
  if !str_eq(etcd_alarm_type_name(aq.alarm), "NOSPACE") { ok = false; }
  if !str_eq(etcd_alarm_action_name(aq.action), "ACTIVATE") { ok = false; }
  var am1 = Vec[UInt8].new();
  t_field_varint(&mut am1, 1, 5);
  t_field_varint(&mut am1, 2, 1);
  var am2 = Vec[UInt8].new();
  t_field_varint(&mut am2, 1, 6);
  t_field_varint(&mut am2, 2, 2);
  var arbody = Vec[UInt8].new();
  t_header(&mut arbody, 1, 1, 1, 11, 1);
  t_field_bytes(&mut arbody, 2, &am1);
  t_field_bytes(&mut arbody, 2, &am2);
  let ar = etcd_decode_alarm_response(&arbody);
  if !ar.is_ok {
    ok = false;
  } else {
    let aresp: EtcdAlarmResponse = ar.value;
    if etcd_alarm_count(&aresp) != 2 { ok = false; }
    let a0: EtcdAlarmMember = etcd_alarm_member(&aresp, 0);
    if a0.member_id != 5 { ok = false; }
    if a0.alarm != etcd_alarm_type_nospace() { ok = false; }
    let a1: EtcdAlarmMember = etcd_alarm_member(&aresp, 1);
    if a1.member_id != 6 { ok = false; }
    if a1.alarm != etcd_alarm_type_corrupt() { ok = false; }
  }
  var hb1 = Vec[UInt8].new();
  t_field_varint(&mut hb1, 2, 12345);
  let hr = etcd_decode_hash_response(&hb1);
  if !hr.is_ok {
    ok = false;
  } else {
    let h: EtcdHashResponse = hr.value;
    if h.hash != 12345 { ok = false; }
    if etcd_header_present(&h.header) { ok = false; }
  }
  var hk = Vec[UInt8].new();
  t_field_varint(&mut hk, 2, 99);
  t_field_varint(&mut hk, 3, 7);
  t_field_varint(&mut hk, 4, 8);
  let hkr = etcd_decode_hash_kv_response(&hk);
  if !hkr.is_ok {
    ok = false;
  } else {
    let hk2: EtcdHashKvResponse = hkr.value;
    if hk2.hash != 99 { ok = false; }
    if hk2.compact_revision != 7 { ok = false; }
    if hk2.hash_revision != 8 { ok = false; }
  }
  let blob = bytes_of("abc");
  var sn = Vec[UInt8].new();
  t_field_varint(&mut sn, 2, 3);
  t_field_bytes(&mut sn, 3, &blob);
  let snr = etcd_decode_snapshot_response(&sn);
  if !snr.is_ok {
    ok = false;
  } else {
    let s: EtcdSnapshotResponse = snr.value;
    if s.remaining_bytes != 3 { ok = false; }
    if !bytes_equal(s.blob, bytes_of("abc")) { ok = false; }
  }
  var df = Vec[UInt8].new();
  t_header(&mut df, 1, 1, 1, 77, 1);
  let dfr = etcd_decode_defragment_response(&df);
  if !dfr.is_ok {
    ok = false;
  } else {
    let dh: EtcdHeader = dfr.value;
    if etcd_header_revision(&dh) != 77 { ok = false; }
  }
  var cp = Vec[UInt8].new();
  t_field_varint(&mut cp, 1, 12);
  t_field_varint(&mut cp, 2, 1);
  let cpr = etcd_decode_compaction_request(&cp);
  if !cpr.is_ok {
    ok = false;
  } else {
    let cq: EtcdCompactionRequest = cpr.value;
    if cq.revision != 12 { ok = false; }
    if !cq.physical { ok = false; }
  }
  var cpresp = Vec[UInt8].new();
  t_header(&mut cpresp, 1, 1, 1, 12, 1);
  let cprr = etcd_decode_compaction_response(&cpresp);
  if !cprr.is_ok {
    ok = false;
  } else {
    let cph: EtcdHeader = cprr.value;
    if etcd_header_revision(&cph) != 12 { ok = false; }
  }
  return assert(ok, "Alarm, Hash/HashKV, Snapshot, Compaction and Defragment");
}

// --------------------------------------------------
//  Unknown fields, malformed input, defaults, constants
// --------------------------------------------------

fn t23() -> TestResult {
  var ok = true;
  // Unknown fields on a RangeRequest are counted and preserved raw
  // (field 99 varint 7, field 100 bytes "xx").
  var body = Vec[UInt8].new();
  t_field_str(&mut body, 1, "k");
  t_field_varint(&mut body, 99, 7);
  let xx = bytes_of("xx");
  t_field_bytes(&mut body, 100, &xx);
  let r = etcd_decode_range_request(&body);
  if !r.is_ok {
    return assert(false, "range request with unknowns decodes: " + r.error);
  }
  let req: EtcdRangeRequest = r.value;
  if !bytes_equal(req.key, bytes_of("k")) { ok = false; }
  if etcd_unknown_count(&req.unknown) != 2 { ok = false; }
  if !bytes_equal(etcd_unknown_bytes(&req.unknown), hb("980607a206027878")) { ok = false; }
  return assert(ok, "unknown fields counted and preserved raw");
}

fn t24() -> TestResult {
  var ok = true;
  let empty = Vec[UInt8].new();
  if !err_put_req_is(etcd_decode_put_request(hb("00")), "etcd: field number 0 at offset 0") { ok = false; }
  if !err_put_req_is(etcd_decode_put_request(hb("0a054142")), "etcd: truncated length-delimited field at offset 4") { ok = false; }
  let crossing = hb("1203414243");
  if !err_range_resp_is(etcd_parse_range_response_body(&crossing, 0, 3, 1), "etcd: field crosses message boundary at offset 1") { ok = false; }
  if !err_put_req_is(etcd_decode_put_request(hb("0b")), "etcd: unsupported wire type 3 at offset 1") { ok = false; }
  if !err_status_is(etcd_decode_status_response(hb("12024100")), "etcd: string contains nul at offset 3") { ok = false; }
  if !err_status_is(etcd_decode_status_response(hb("1202c328")), "etcd: invalid utf-8 at offset 2") { ok = false; }
  let valid = hb("0a016b");
  if !err_range_req_is(etcd_parse_range_request_body(&valid, 5, 2, 1), "etcd: bad message range at offset 5") { ok = false; }
  if !err_range_resp_is(etcd_parse_range_response_body(&valid, 0, valid.len(), 17), "etcd: nesting depth exceeds limit of 16 at offset 0") { ok = false; }
  let clipped = hb("0880");
  if !err_header_is(etcd_decode_header(&clipped), "etcd: truncated varint at offset 2") { ok = false; }
  let okr = etcd_parse_range_request_body(&valid, 0, valid.len(), 16);
  if !okr.is_ok { ok = false; }
  if empty.len() != 0 { ok = false; }
  return assert(ok, "malformed input: offsets, boundary, depth cap, NUL/UTF-8");
}

fn t25() -> TestResult {
  var ok = true;
  // Empty messages keep proto3 defaults.
  let r = etcd_decode_range_request(&Vec[UInt8].new());
  if !r.is_ok {
    ok = false;
  } else {
    let req: EtcdRangeRequest = r.value;
    if req.limit != 0 || req.revision != 0 { ok = false; }
    if req.serializable || req.keys_only || req.count_only { ok = false; }
    if req.key.len() != 0 { ok = false; }
  }
  let r2 = etcd_decode_put_request(&Vec[UInt8].new());
  if !r2.is_ok {
    ok = false;
  } else {
    let pr: EtcdPutRequest = r2.value;
    if pr.lease != 0 || pr.prev_kv || pr.ignore_value || pr.ignore_lease { ok = false; }
  }
  let r3 = etcd_decode_key_value(&Vec[UInt8].new());
  if !r3.is_ok {
    ok = false;
  } else {
    let kvn: EtcdKeyValue = r3.value;
    if etcd_kv_lease(&kvn) != 0 { ok = false; }
    if etcd_kv_key(&kvn).len() != 0 { ok = false; }
  }
  let r4 = etcd_decode_watch_response(&Vec[UInt8].new());
  if !r4.is_ok {
    ok = false;
  } else {
    let wrn: EtcdWatchResponse = r4.value;
    if etcd_watch_event_count(&wrn) != 0 { ok = false; }
    if wrn.created || wrn.canceled { ok = false; }
  }
  let r5 = etcd_decode_member_list_response(&Vec[UInt8].new());
  if !r5.is_ok {
    ok = false;
  } else {
    let mln: EtcdMemberListResponse = r5.value;
    if etcd_member_count(&mln) != 0 { ok = false; }
    if etcd_member_peer_count(&mln, 0) != 0 { ok = false; }
  }
  // Constructors.
  let kv = etcd_key_value_new();
  if etcd_kv_mod_revision(&kv) != 0 { ok = false; }
  let wr2 = etcd_watch_response_new();
  if etcd_watch_event_count(&wr2) != 0 { ok = false; }
  let ml2 = etcd_member_list_new();
  if ml2.ids.len() != 0 { ok = false; }
  let ox = etcd_unknown_new();
  if etcd_unknown_count(&ox) != 0 { ok = false; }
  // Validated string materialization.
  let bs = etcd_bytes_to_str(&bytes_of("hi"));
  if !bs.is_ok {
    ok = false;
  } else {
    let s: Str = bs.value;
    if !str_eq(s, "hi") { ok = false; }
  }
  let bs2 = etcd_bytes_to_str(&hb("00"));
  if bs2.is_ok { ok = false; }
  let ss = etcd_span_to_str(&hb("026869"), 1, 2);
  if !ss.is_ok {
    ok = false;
  } else {
    let s2: Str = ss.value;
    if !str_eq(s2, "hi") { ok = false; }
  }
  let ss2 = etcd_span_to_str(&hb("026869"), 9, 2);
  if ss2.is_ok { ok = false; }
  return assert(ok, "defaults, constructors and validated string helpers");
}

fn t26() -> TestResult {
  var ok = true;
  if etcd_wire_varint() != 0 || etcd_wire_fixed64() != 1 { ok = false; }
  if etcd_wire_length_delimited() != 2 || etcd_wire_fixed32() != 5 { ok = false; }
  if etcd_sort_none() != 0 || etcd_sort_ascend() != 1 || etcd_sort_descend() != 2 { ok = false; }
  if etcd_sort_target_key() != 0 || etcd_sort_target_version() != 1 { ok = false; }
  if etcd_sort_target_create() != 2 || etcd_sort_target_mod() != 3 || etcd_sort_target_value() != 4 { ok = false; }
  if etcd_compare_result_equal() != 0 || etcd_compare_result_greater() != 1 { ok = false; }
  if etcd_compare_result_less() != 2 || etcd_compare_result_not_equal() != 3 { ok = false; }
  if etcd_compare_target_version() != 0 || etcd_compare_target_create() != 1 { ok = false; }
  if etcd_compare_target_mod() != 2 || etcd_compare_target_value() != 3 || etcd_compare_target_lease() != 4 { ok = false; }
  if etcd_event_put() != 0 || etcd_event_delete() != 1 { ok = false; }
  if etcd_filter_noput() != 0 || etcd_filter_nodelete() != 1 { ok = false; }
  if etcd_alarm_type_none() != 0 || etcd_alarm_type_nospace() != 1 || etcd_alarm_type_corrupt() != 2 { ok = false; }
  if etcd_alarm_action_get() != 0 || etcd_alarm_action_activate() != 1 || etcd_alarm_action_deactivate() != 2 { ok = false; }
  if etcd_op_range() != 1 || etcd_op_put() != 2 || etcd_op_delete_range() != 3 || etcd_op_txn() != 4 { ok = false; }
  if etcd_max_depth() != 16 { ok = false; }
  if etcd_max_list_entries() != 65536 || etcd_max_packed_entries() != 65536 { ok = false; }
  if !str_eq(etcd_sort_order_name(2), "DESCEND") { ok = false; }
  if !str_eq(etcd_sort_target_name(3), "MOD") { ok = false; }
  if !str_eq(etcd_compare_result_name(3), "NOT_EQUAL") { ok = false; }
  if !str_eq(etcd_compare_target_name(4), "LEASE") { ok = false; }
  if !str_eq(etcd_event_type_name(0), "PUT") { ok = false; }
  if !str_eq(etcd_alarm_type_name(2), "CORRUPT") { ok = false; }
  if !str_eq(etcd_alarm_action_name(1), "ACTIVATE") { ok = false; }
  if !str_eq(etcd_alarm_action_name(9), "UNKNOWN") { ok = false; }
  if !str_eq(etcd_op_name(4), "TXN") { ok = false; }
  if !str_eq(etcd_op_name(9), "UNKNOWN") { ok = false; }
  if !err_bytes_is(etcd_encode_varint(-1), "etcd: negative varint value") { ok = false; }
  return assert(ok, "constants, limits, name tables and encoder validation");
}

fn main() -> Int {
  io.println("=== xiom.etcd conformance tests ===");
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
  let r26 = t26();
  if r26.passed { io.println("  [PASS] " + r26.name); } else { io.println("  [FAIL] " + r26.name); failed = failed + 1; }
  if failed == 0 {
    io.println("xiom.etcd: all tests passed");
  } else {
    io.println("xiom.etcd: tests failed");
  }
  return failed;
}
