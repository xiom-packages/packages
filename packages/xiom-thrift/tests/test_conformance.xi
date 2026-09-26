// XIOM -- xiom.thrift conformance tests (24 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Covers the documented API: strict and legacy message headers, all four
// message types, field headers (including negative ids and STOP), every
// primitive codec (BOOL, BYTE, I16, I32, I64, DOUBLE raw bits, STRING),
// strict UTF-8 validation and NUL rejection, list/set/map headers with the
// collection-size guards, recursive skip through nested struct/map/list/
// set values, the nesting-depth cap, the flat parallel-vector struct model
// with its round-trip and error paths, a composite message round-trip, and
// the reader/writer lifecycle accessors.
//
// Harness style mirrors xiom.cbor / xiom.iso8583: one fn tN() -> TestResult
// per check, called directly from main; main prints [PASS]/[FAIL] and
// returns the failure count. Synthetic buffers are built in-test from hex
// literals (xiom.encoding.hex); no external data files. Str payloads are
// compared with str_compare (BUG 17 discipline: `==` on Str values read
// from a Vec lowers to a pointer comparison).

module thrift_tests
use xiom.io; use xiom.test;
use xiom.string; use xiom.string.compare;
use xiom.encoding.hex;
use xiom.thrift;

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

// Bytes of a Str, byte-for-byte (UTF-8 literals included).
fn ab(s: Str) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  let n = string.str_len(s);
  var i = 0;
  while i < n {
    let b: UInt8 = string.byte_at(s, i);
    v.push(b);
    i = i + 1;
  }
  return v;
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

// Append every byte of `v` to `out`.
fn append_bytes(out: &mut Vec[UInt8], v: Vec[UInt8]) {
  var i = 0;
  while i < v.len() {
    out.push(v[i]);
    i = i + 1;
  }
}

// First byte of a vector as 0..255, or -1 when empty.
fn first_byte(v: Vec[UInt8]) -> Int {
  if v.len() == 0 {
    return -1;
  }
  let b: UInt8 = v[0];
  return (b as Int) & 0xFF;
}

fn err_is_i(r: Result[Int, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_compare(r.error, want) == 0;
}

fn err_is_b(r: Result[Bool, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_compare(r.error, want) == 0;
}

fn err_is_s(r: Result[Str, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_compare(r.error, want) == 0;
}

fn err_is_bytes(r: Result[Vec[UInt8], Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_compare(r.error, want) == 0;
}

fn err_is_msg(r: Result[ThriftMessage, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_compare(r.error, want) == 0;
}

fn err_is_field(r: Result[ThriftField, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_compare(r.error, want) == 0;
}

fn err_is_lhdr(r: Result[ThriftListHeader, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_compare(r.error, want) == 0;
}

fn err_is_mhdr(r: Result[ThriftMapHeader, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_compare(r.error, want) == 0;
}

fn err_is_struct(r: Result[ThriftStruct, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_compare(r.error, want) == 0;
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  var w = thrift_writer_new();
  thrift_write_message_begin(&mut w, "ping", thrift_msg_call(), 1);
  var ok = bytes_equal(thrift_writer_bytes(&w), hb("800100010000000470696e6700000001"));
  var w2 = thrift_writer_new();
  thrift_write_message_begin(&mut w2, "ping", thrift_msg_reply(), 2);
  if !bytes_equal(thrift_writer_bytes(&w2), hb("800100020000000470696e6700000002")) { ok = false; }
  var w3 = thrift_writer_new();
  thrift_write_message_begin(&mut w3, "f", thrift_msg_exception(), 3);
  if !bytes_equal(thrift_writer_bytes(&w3), hb("80010003000000016600000003")) { ok = false; }
  var w4 = thrift_writer_new();
  thrift_write_message_begin(&mut w4, "", thrift_msg_oneway(), 4);
  if !bytes_equal(thrift_writer_bytes(&w4), hb("800100040000000000000004")) { ok = false; }
  if thrift_protocol_version() != 2147549184 { ok = false; }
  return assert(ok, "strict message header encodes version|type, name and seqid");
}

fn t2() -> TestResult {
  var r = thrift_reader_new(hb("800100010000000470696e6700000001"));
  let mr = thrift_read_message_begin(&mut r);
  var ok = mr.is_ok;
  if mr.is_ok {
    let m: ThriftMessage = mr.value;
    if str_compare(thrift_message_name(&m), "ping") != 0 { ok = false; }
    if thrift_message_type(&m) != thrift_msg_call() { ok = false; }
    if thrift_message_seqid(&m) != 1 { ok = false; }
    if !thrift_message_strict(&m) { ok = false; }
  }
  if thrift_reader_remaining(&r) != 0 { ok = false; }
  var r2 = thrift_reader_new(hb("8001000400000003666f6f00000009"));
  let mr2 = thrift_read_message_begin(&mut r2);
  if !mr2.is_ok { ok = false; } else {
    let m2: ThriftMessage = mr2.value;
    if str_compare(m2.name, "foo") != 0 { ok = false; }
    if m2.msg_type != thrift_msg_oneway() { ok = false; }
    if m2.seqid != 9 { ok = false; }
    if !m2.strict { ok = false; }
  }
  return assert(ok, "strict message header decodes name, type, seqid and strict flag");
}

fn t3() -> TestResult {
  var r = thrift_reader_new(hb("0000000470696e670100000007"));
  let mr = thrift_read_message_begin(&mut r);
  var ok = mr.is_ok;
  if mr.is_ok {
    let m: ThriftMessage = mr.value;
    if str_compare(m.name, "ping") != 0 { ok = false; }
    if m.msg_type != thrift_msg_call() { ok = false; }
    if m.seqid != 7 { ok = false; }
    if m.strict { ok = false; }
  }
  var r2 = thrift_reader_new(hb("0000000470696e670400000008"));
  let mr2 = thrift_read_message_begin(&mut r2);
  if !mr2.is_ok { ok = false; } else {
    let m2: ThriftMessage = mr2.value;
    if m2.msg_type != thrift_msg_oneway() { ok = false; }
    if m2.seqid != 8 { ok = false; }
    if m2.strict { ok = false; }
    if str_compare(m2.name, "ping") != 0 { ok = false; }
  }
  var w = thrift_writer_new();
  thrift_write_message_begin_legacy(&mut w, "ping", thrift_msg_reply(), 7);
  if !bytes_equal(thrift_writer_bytes(&w), hb("0000000470696e670200000007")) { ok = false; }
  return assert(ok, "legacy (name-first) message headers are detected and decoded");
}

fn t4() -> TestResult {
  var r = thrift_reader_new(hb("800200010000000470696e6700000001"));
  var ok = err_is_msg(thrift_read_message_begin(&mut r), "thrift: bad strict version");
  var r2 = thrift_reader_new(hb("800100050000000470696e6700000001"));
  if !err_is_msg(thrift_read_message_begin(&mut r2), "thrift: unknown message type 5") { ok = false; }
  var r3 = thrift_reader_new(hb("0000000470696e670500000007"));
  if !err_is_msg(thrift_read_message_begin(&mut r3), "thrift: unknown message type 5") { ok = false; }
  var r4 = thrift_reader_new(hb("0000000470696e670000000007"));
  if !err_is_msg(thrift_read_message_begin(&mut r4), "thrift: unknown message type 0") { ok = false; }
  var r5 = thrift_reader_new(hb("80010001"));
  if !err_is_msg(thrift_read_message_begin(&mut r5), "thrift: truncated input") { ok = false; }
  var r6 = thrift_reader_new(hb("8001000100000004"));
  if !err_is_msg(thrift_read_message_begin(&mut r6), "thrift: truncated input") { ok = false; }
  var r7 = thrift_reader_new(hb("800100010000000470696e67"));
  if !err_is_msg(thrift_read_message_begin(&mut r7), "thrift: truncated input") { ok = false; }
  var r8 = thrift_reader_new(hb("000000ff7069"));
  if !err_is_msg(thrift_read_message_begin(&mut r8), "thrift: truncated input") { ok = false; }
  var r9 = thrift_reader_new(hb("800100010000000470006e6700000001"));
  if !err_is_msg(thrift_read_message_begin(&mut r9), "thrift: invalid message name") { ok = false; }
  var r10 = thrift_reader_new(hb("800100070000000470696e6700000001"));
  if !err_is_msg(thrift_read_message_begin(&mut r10), "thrift: unknown message type 7") { ok = false; }
  return assert(ok, "malformed message headers are rejected with deterministic errors");
}

fn t5() -> TestResult {
  var w = thrift_writer_new();
  thrift_write_field_begin(&mut w, thrift_t_i32(), 3);
  var ok = bytes_equal(thrift_writer_bytes(&w), hb("080003"));
  var w2 = thrift_writer_new();
  thrift_write_field_begin(&mut w2, thrift_t_i32(), -2);
  if !bytes_equal(thrift_writer_bytes(&w2), hb("08fffe")) { ok = false; }
  var w3 = thrift_writer_new();
  thrift_write_field_stop(&mut w3);
  if !bytes_equal(thrift_writer_bytes(&w3), hb("00")) { ok = false; }
  var r = thrift_reader_new(hb("080003"));
  let fr = thrift_read_field_begin(&mut r);
  if !fr.is_ok { ok = false; } else {
    let f: ThriftField = fr.value;
    if thrift_field_type(&f) != thrift_t_i32() { ok = false; }
    if thrift_field_id(&f) != 3 { ok = false; }
    if thrift_reader_pos(&r) != 3 { ok = false; }
  }
  var r2 = thrift_reader_new(hb("08fffe"));
  let fr2 = thrift_read_field_begin(&mut r2);
  if !fr2.is_ok { ok = false; } else {
    let f2: ThriftField = fr2.value;
    if f2.fid != -2 { ok = false; }
  }
  var r3 = thrift_reader_new(hb("00"));
  let fr3 = thrift_read_field_begin(&mut r3);
  if !fr3.is_ok { ok = false; } else {
    let f3: ThriftField = fr3.value;
    if f3.ftype != thrift_t_stop() { ok = false; }
    if f3.fid != 0 { ok = false; }
  }
  return assert(ok, "field headers encode and decode type and int16 id; STOP terminates");
}

fn t6() -> TestResult {
  var r = thrift_reader_new(hb("05"));
  var ok = err_is_field(thrift_read_field_begin(&mut r), "thrift: unknown type id 5");
  var r2 = thrift_reader_new(hb("01"));
  if !err_is_field(thrift_read_field_begin(&mut r2), "thrift: unknown type id 1") { ok = false; }
  var r3 = thrift_reader_new(hb("07"));
  if !err_is_field(thrift_read_field_begin(&mut r3), "thrift: unknown type id 7") { ok = false; }
  var r4 = thrift_reader_new(hb(""));
  if !err_is_field(thrift_read_field_begin(&mut r4), "thrift: truncated input") { ok = false; }
  var r5 = thrift_reader_new(hb("08"));
  if !err_is_field(thrift_read_field_begin(&mut r5), "thrift: truncated input") { ok = false; }
  var r6 = thrift_reader_new(hb("0800"));
  if !err_is_field(thrift_read_field_begin(&mut r6), "thrift: truncated input") { ok = false; }
  if !thrift_type_known(thrift_t_string()) { ok = false; }
  if !thrift_type_known(thrift_t_list()) { ok = false; }
  if thrift_type_known(thrift_t_stop()) { ok = false; }
  if thrift_type_known(1) { ok = false; }
  if thrift_type_known(5) { ok = false; }
  if thrift_type_known(16) { ok = false; }
  return assert(ok, "unknown field type ids and truncated field headers are rejected");
}

fn t7() -> TestResult {
  var w = thrift_writer_new();
  thrift_write_bool(&mut w, true);
  thrift_write_bool(&mut w, false);
  var ok = bytes_equal(thrift_writer_bytes(&w), hb("0100"));
  var r = thrift_reader_new(hb("01"));
  let b1 = thrift_read_bool(&mut r);
  if !b1.is_ok { ok = false; } else {
    if !b1.value { ok = false; }
  }
  var r2 = thrift_reader_new(hb("00"));
  let b2 = thrift_read_bool(&mut r2);
  if !b2.is_ok { ok = false; } else {
    if b2.value { ok = false; }
  }
  var r3 = thrift_reader_new(hb("02"));
  if !err_is_b(thrift_read_bool(&mut r3), "thrift: invalid bool value") { ok = false; }
  var r4 = thrift_reader_new(hb(""));
  if !err_is_b(thrift_read_bool(&mut r4), "thrift: truncated input") { ok = false; }
  if thrift_t_bool() != 2 { ok = false; }
  return assert(ok, "BOOL encodes as one byte, true = 1, and invalid values are rejected");
}

fn t8() -> TestResult {
  var w = thrift_writer_new();
  thrift_write_byte(&mut w, 0);
  thrift_write_byte(&mut w, 127);
  thrift_write_byte(&mut w, -1);
  thrift_write_byte(&mut w, -128);
  var ok = bytes_equal(thrift_writer_bytes(&w), hb("007fff80"));
  var vals = Vec[Int].new();
  vals.push(0);
  vals.push(127);
  vals.push(-1);
  vals.push(-128);
  var r = thrift_reader_new(hb("007fff80"));
  var i = 0;
  while i < vals.len() {
    let want: Int = vals[i];
    let vr = thrift_read_byte(&mut r);
    if !vr.is_ok { ok = false; } else {
      if vr.value != want { ok = false; }
    }
    i = i + 1;
  }
  if thrift_reader_remaining(&r) != 0 { ok = false; }
  var r2 = thrift_reader_new(hb(""));
  if !err_is_i(thrift_read_byte(&mut r2), "thrift: truncated input") { ok = false; }
  return assert(ok, "BYTE encodes and decodes signed 8-bit values");
}

fn t9() -> TestResult {
  var w = thrift_writer_new();
  thrift_write_i16(&mut w, 256);
  thrift_write_i16(&mut w, -32768);
  thrift_write_i16(&mut w, 32767);
  thrift_write_i16(&mut w, -1);
  var ok = bytes_equal(thrift_writer_bytes(&w), hb("010080007fffffff"));
  var vals = Vec[Int].new();
  vals.push(256);
  vals.push(-32768);
  vals.push(32767);
  vals.push(-1);
  var r = thrift_reader_new(hb("010080007fffffff"));
  var i = 0;
  while i < vals.len() {
    let want: Int = vals[i];
    let vr = thrift_read_i16(&mut r);
    if !vr.is_ok { ok = false; } else {
      if vr.value != want { ok = false; }
    }
    i = i + 1;
  }
  if thrift_reader_remaining(&r) != 0 { ok = false; }
  var r2 = thrift_reader_new(hb("01"));
  if !err_is_i(thrift_read_i16(&mut r2), "thrift: truncated input") { ok = false; }
  return assert(ok, "I16 encodes and decodes signed 16-bit boundaries");
}

fn t10() -> TestResult {
  var w = thrift_writer_new();
  thrift_write_i32(&mut w, 2147483647);
  thrift_write_i32(&mut w, 0 - 2147483647 - 1);
  thrift_write_i32(&mut w, -1);
  thrift_write_i32(&mut w, 65536);
  var ok = bytes_equal(thrift_writer_bytes(&w), hb("7fffffff80000000ffffffff00010000"));
  var vals = Vec[Int].new();
  vals.push(2147483647);
  vals.push(0 - 2147483647 - 1);
  vals.push(-1);
  vals.push(65536);
  var r = thrift_reader_new(hb("7fffffff80000000ffffffff00010000"));
  var i = 0;
  while i < vals.len() {
    let want: Int = vals[i];
    let vr = thrift_read_i32(&mut r);
    if !vr.is_ok { ok = false; } else {
      if vr.value != want { ok = false; }
    }
    i = i + 1;
  }
  if thrift_reader_remaining(&r) != 0 { ok = false; }
  return assert(ok, "I32 encodes and decodes signed 32-bit boundaries");
}

fn t11() -> TestResult {
  var w = thrift_writer_new();
  thrift_write_i64(&mut w, 9223372036854775807);
  let int_min = 0 - 9223372036854775807 - 1;
  thrift_write_i64(&mut w, int_min);
  thrift_write_i64(&mut w, -1);
  thrift_write_i64(&mut w, 4294967296);
  var ok = bytes_equal(thrift_writer_bytes(&w), hb("7fffffffffffffff8000000000000000ffffffffffffffff0000000100000000"));
  var vals = Vec[Int].new();
  vals.push(9223372036854775807);
  vals.push(int_min);
  vals.push(-1);
  vals.push(4294967296);
  var r = thrift_reader_new(hb("7fffffffffffffff8000000000000000ffffffffffffffff0000000100000000"));
  var i = 0;
  while i < vals.len() {
    let want: Int = vals[i];
    let vr = thrift_read_i64(&mut r);
    if !vr.is_ok { ok = false; } else {
      if vr.value != want { ok = false; }
    }
    i = i + 1;
  }
  if thrift_reader_remaining(&r) != 0 { ok = false; }
  var r2 = thrift_reader_new(hb("00000000000000"));
  if !err_is_i(thrift_read_i64(&mut r2), "thrift: truncated input") { ok = false; }
  return assert(ok, "I64 encodes and decodes the full signed 64-bit range");
}

fn t12() -> TestResult {
  let one = 4607182418800017408;                                // 0x3FF0000000000000 = 1.0
  let neg2 = 0 - 4611686018427387904;                           // 0xC000000000000000 = -2.0
  let neg15 = 4609434218613702656 - 9223372036854775807 - 1;    // 0xBFF8000000000000 = -1.5
  var w = thrift_writer_new();
  thrift_write_double_bits(&mut w, one);
  thrift_write_double_bits(&mut w, neg2);
  thrift_write_double_bits(&mut w, neg15);
  thrift_write_double_bits(&mut w, 0);
  var ok = bytes_equal(thrift_writer_bytes(&w), hb("3ff0000000000000c000000000000000bff80000000000000000000000000000"));
  var vals = Vec[Int].new();
  vals.push(one);
  vals.push(neg2);
  vals.push(neg15);
  vals.push(0);
  var r = thrift_reader_new(hb("3ff0000000000000c000000000000000bff80000000000000000000000000000"));
  var i = 0;
  while i < vals.len() {
    let want: Int = vals[i];
    let vr = thrift_read_double_bits(&mut r);
    if !vr.is_ok { ok = false; } else {
      if vr.value != want { ok = false; }
    }
    i = i + 1;
  }
  if thrift_reader_remaining(&r) != 0 { ok = false; }
  return assert(ok, "DOUBLE carries exact IEEE-754 bit patterns (1.0, -2.0, -1.5, 0.0)");
}

fn t13() -> TestResult {
  var w = thrift_writer_new();
  thrift_write_string(&mut w, "héllo");
  var ok = bytes_equal(thrift_writer_bytes(&w), hb("0000000668c3a96c6c6f"));
  var w2 = thrift_writer_new();
  thrift_write_string(&mut w2, "");
  if !bytes_equal(thrift_writer_bytes(&w2), hb("00000000")) { ok = false; }
  var r = thrift_reader_new(hb("0000000668c3a96c6c6f"));
  let sr = thrift_read_string(&mut r);
  if !sr.is_ok { ok = false; } else {
    if str_compare(sr.value, "héllo") != 0 { ok = false; }
  }
  let payload = hb("00ff");
  var w3 = thrift_writer_new();
  thrift_write_binary(&mut w3, &payload);
  if !bytes_equal(thrift_writer_bytes(&w3), hb("0000000200ff")) { ok = false; }
  var r2 = thrift_reader_new(hb("0000000200ff"));
  let br2 = thrift_read_binary(&mut r2);
  if !br2.is_ok { ok = false; } else {
    if !bytes_equal(br2.value, payload) { ok = false; }
  }
  let emoji = hb("f09f9880");
  var w4 = thrift_writer_new();
  thrift_write_binary(&mut w4, &emoji);
  var r3 = thrift_reader_new(thrift_writer_bytes(&w4));
  let er = thrift_read_string(&mut r3);
  if !er.is_ok { ok = false; } else {
    if str_compare(er.value, "😀") != 0 { ok = false; }
  }
  var r4 = thrift_reader_new(hb("00000000"));
  let zr = thrift_read_string(&mut r4);
  if !zr.is_ok { ok = false; } else {
    if str_compare(zr.value, "") != 0 { ok = false; }
  }
  return assert(ok, "STRING writes u32 length + bytes; binary and UTF-8 round-trip");
}

fn t14() -> TestResult {
  var r = thrift_reader_new(hb("0000000100"));
  var ok = err_is_s(thrift_read_string(&mut r), "thrift: string contains nul");
  var r2 = thrift_reader_new(hb("00000002c0af"));
  if !err_is_s(thrift_read_string(&mut r2), "thrift: invalid utf-8") { ok = false; }
  var r3 = thrift_reader_new(hb("00000001c3"));
  if !err_is_s(thrift_read_string(&mut r3), "thrift: invalid utf-8") { ok = false; }
  var r4 = thrift_reader_new(hb("00000003eda080"));
  if !err_is_s(thrift_read_string(&mut r4), "thrift: invalid utf-8") { ok = false; }
  var r5 = thrift_reader_new(hb("00000001f5"));
  if !err_is_s(thrift_read_string(&mut r5), "thrift: invalid utf-8") { ok = false; }
  var r6 = thrift_reader_new(hb("ffffffff"));
  if !err_is_bytes(thrift_read_binary(&mut r6), "thrift: truncated input") { ok = false; }
  var r7 = thrift_reader_new(hb("000000056869"));
  if !err_is_bytes(thrift_read_binary(&mut r7), "thrift: truncated input") { ok = false; }
  var r8 = thrift_reader_new(hb("000000"));
  if !err_is_bytes(thrift_read_binary(&mut r8), "thrift: truncated input") { ok = false; }
  var r9 = thrift_reader_new(hb("00000001"));
  if !err_is_s(thrift_read_string(&mut r9), "thrift: truncated input") { ok = false; }
  var r10 = thrift_reader_new(hb("0000000100"));
  let br = thrift_read_binary(&mut r10);
  if !br.is_ok { ok = false; } else {
    if br.value.len() != 1 { ok = false; }
    if first_byte(br.value) != 0 { ok = false; }
  }
  return assert(ok, "string decoding validates UTF-8 and NUL; length overruns are truncated input");
}

fn t15() -> TestResult {
  var w = thrift_writer_new();
  thrift_write_list_begin(&mut w, thrift_t_i32(), 3);
  thrift_write_i32(&mut w, 1);
  thrift_write_i32(&mut w, 2);
  thrift_write_i32(&mut w, 3);
  var ok = bytes_equal(thrift_writer_bytes(&w), hb("0800000003000000010000000200000003"));
  var r = thrift_reader_new(hb("0800000003000000010000000200000003"));
  let lr = thrift_read_list_header(&mut r);
  if !lr.is_ok { ok = false; } else {
    let h: ThriftListHeader = lr.value;
    if thrift_list_header_type(&h) != thrift_t_i32() { ok = false; }
    if thrift_list_header_size(&h) != 3 { ok = false; }
  }
  var r2 = thrift_reader_new(hb("08ffffffff"));
  if !err_is_lhdr(thrift_read_list_header(&mut r2), "thrift: bad collection size -1") { ok = false; }
  var r3 = thrift_reader_new(hb("0800000005"));
  if !err_is_lhdr(thrift_read_list_header(&mut r3), "thrift: oversized collection") { ok = false; }
  var r4 = thrift_reader_new(hb("0500000001"));
  if !err_is_lhdr(thrift_read_list_header(&mut r4), "thrift: unknown type id 5") { ok = false; }
  var r5 = thrift_reader_new(hb("0000000001"));
  if !err_is_lhdr(thrift_read_list_header(&mut r5), "thrift: unknown type id 0") { ok = false; }
  var r6 = thrift_reader_new(hb("08"));
  if !err_is_lhdr(thrift_read_list_header(&mut r6), "thrift: truncated input") { ok = false; }
  var r7 = thrift_reader_new(hb("080000000500000001"));
  if !err_is_lhdr(thrift_read_list_header(&mut r7), "thrift: oversized collection") { ok = false; }
  if thrift_t_list() != 15 { ok = false; }
  return assert(ok, "LIST headers encode and decode element type and size with guards");
}

fn t16() -> TestResult {
  var w = thrift_writer_new();
  thrift_write_map_begin(&mut w, thrift_t_string(), thrift_t_i32(), 1);
  thrift_write_string(&mut w, "k");
  thrift_write_i32(&mut w, 9);
  var ok = bytes_equal(thrift_writer_bytes(&w), hb("0b0800000001000000016b00000009"));
  var r = thrift_reader_new(hb("0b08000000020000000100000002"));
  let mr = thrift_read_map_header(&mut r);
  if !mr.is_ok { ok = false; } else {
    let h: ThriftMapHeader = mr.value;
    if thrift_map_header_key_type(&h) != thrift_t_string() { ok = false; }
    if thrift_map_header_value_type(&h) != thrift_t_i32() { ok = false; }
    if thrift_map_header_size(&h) != 2 { ok = false; }
  }
  var r2 = thrift_reader_new(hb("0b08ffffffff"));
  if !err_is_mhdr(thrift_read_map_header(&mut r2), "thrift: bad collection size -1") { ok = false; }
  var r3 = thrift_reader_new(hb("0b0800000003"));
  if !err_is_mhdr(thrift_read_map_header(&mut r3), "thrift: oversized collection") { ok = false; }
  var r4 = thrift_reader_new(hb("050800000001"));
  if !err_is_mhdr(thrift_read_map_header(&mut r4), "thrift: unknown type id 5") { ok = false; }
  var r5 = thrift_reader_new(hb("080500000001"));
  if !err_is_mhdr(thrift_read_map_header(&mut r5), "thrift: unknown type id 5") { ok = false; }
  var r6 = thrift_reader_new(hb("0b"));
  if !err_is_mhdr(thrift_read_map_header(&mut r6), "thrift: truncated input") { ok = false; }
  var r7 = thrift_reader_new(hb("0b0800000002"));
  if !err_is_mhdr(thrift_read_map_header(&mut r7), "thrift: oversized collection") { ok = false; }
  if thrift_t_map() != 13 { ok = false; }
  return assert(ok, "MAP headers encode and decode key type, value type and size with guards");
}

fn t17() -> TestResult {
  var w = thrift_writer_new();
  thrift_write_set_begin(&mut w, thrift_t_bool(), 2);
  var ok = bytes_equal(thrift_writer_bytes(&w), hb("0200000002"));
  var r = thrift_reader_new(hb("020000000200ff"));
  let lr = thrift_read_set_header(&mut r);
  if !lr.is_ok { ok = false; } else {
    let h: ThriftListHeader = lr.value;
    if h.etype != thrift_t_bool() { ok = false; }
    if h.size != 2 { ok = false; }
  }
  var w2 = thrift_writer_new();
  thrift_write_set_begin(&mut w2, thrift_t_i64(), 1);
  thrift_write_i64(&mut w2, 7);
  var r2 = thrift_reader_new(thrift_writer_bytes(&w2));
  let lr2 = thrift_read_set_header(&mut r2);
  if !lr2.is_ok { ok = false; } else {
    let h2: ThriftListHeader = lr2.value;
    if h2.etype != thrift_t_i64() { ok = false; }
    if h2.size != 1 { ok = false; }
  }
  let v2 = thrift_read_i64(&mut r2);
  if !v2.is_ok { ok = false; } else {
    if v2.value != 7 { ok = false; }
  }
  var r3 = thrift_reader_new(hb("0500000000"));
  if !err_is_lhdr(thrift_read_set_header(&mut r3), "thrift: unknown type id 5") { ok = false; }
  if thrift_t_set() != 14 { ok = false; }
  return assert(ok, "SET headers share the list wire layout (element type + size)");
}

fn t18() -> TestResult {
  var buf = Vec[UInt8].new();
  append_bytes(&mut buf, hb("01"));
  append_bytes(&mut buf, hb("7f"));
  append_bytes(&mut buf, hb("3ff0000000000000"));
  append_bytes(&mut buf, hb("0100"));
  append_bytes(&mut buf, hb("0000002a"));
  append_bytes(&mut buf, hb("000000000000002a"));
  append_bytes(&mut buf, hb("00000003000102"));
  let total = buf.len();
  var r = thrift_reader_new(buf);
  var ok = true;
  let s1 = thrift_skip(&mut r, thrift_t_bool());
  if !s1.is_ok { ok = false; } else {
    if s1.value != 1 { ok = false; }
  }
  let s2 = thrift_skip(&mut r, thrift_t_byte());
  if !s2.is_ok { ok = false; } else {
    if s2.value != 1 { ok = false; }
  }
  let s3 = thrift_skip(&mut r, thrift_t_double());
  if !s3.is_ok { ok = false; } else {
    if s3.value != 8 { ok = false; }
  }
  let s4 = thrift_skip(&mut r, thrift_t_i16());
  if !s4.is_ok { ok = false; } else {
    if s4.value != 2 { ok = false; }
  }
  let s5 = thrift_skip(&mut r, thrift_t_i32());
  if !s5.is_ok { ok = false; } else {
    if s5.value != 4 { ok = false; }
  }
  let s6 = thrift_skip(&mut r, thrift_t_i64());
  if !s6.is_ok { ok = false; } else {
    if s6.value != 8 { ok = false; }
  }
  let s7 = thrift_skip(&mut r, thrift_t_string());
  if !s7.is_ok { ok = false; } else {
    if s7.value != 7 { ok = false; }
  }
  let s8 = thrift_skip(&mut r, thrift_t_i32());
  if !err_is_i(s8, "thrift: truncated input") { ok = false; }
  let s9 = thrift_skip(&mut r, thrift_t_stop());
  if !err_is_i(s9, "thrift: unknown type id 0") { ok = false; }
  let s10 = thrift_skip(&mut r, 16);
  if !err_is_i(s10, "thrift: unknown type id 16") { ok = false; }
  if thrift_reader_pos(&r) != total { ok = false; }
  if thrift_reader_remaining(&r) != 0 { ok = false; }
  return assert(ok, "skip consumes every primitive type and validates bounds");
}

fn t19() -> TestResult {
  var buf = Vec[UInt8].new();
  append_bytes(&mut buf, hb("0f0001"));                 // field 1: LIST
  append_bytes(&mut buf, hb("0800000002"));             // elem I32, size 2
  append_bytes(&mut buf, hb("0000000a00000014"));       // 10, 20
  append_bytes(&mut buf, hb("0d0002"));                 // field 2: MAP
  append_bytes(&mut buf, hb("0b08"));                   // key STRING, value I32
  append_bytes(&mut buf, hb("00000001"));               // size 1
  append_bytes(&mut buf, hb("0000000161"));             // key "a"
  append_bytes(&mut buf, hb("00000007"));               // value 7
  append_bytes(&mut buf, hb("0c0003"));                 // field 3: STRUCT
  append_bytes(&mut buf, hb("0a0001"));                 // inner I64 field 1
  append_bytes(&mut buf, hb("0000000000000005"));       // 5
  append_bytes(&mut buf, hb("00"));                     // inner STOP
  append_bytes(&mut buf, hb("0e0004"));                 // field 4: SET
  append_bytes(&mut buf, hb("0600000002"));             // elem I16, size 2
  append_bytes(&mut buf, hb("00010002"));               // 1, 2
  append_bytes(&mut buf, hb("00"));                     // outer STOP
  let total = buf.len();
  var r = thrift_reader_new(buf);
  var ok = true;
  let f1 = thrift_read_field_begin(&mut r);
  if !f1.is_ok { ok = false; } else {
    let fa: ThriftField = f1.value;
    if fa.ftype != thrift_t_list() { ok = false; }
    if fa.fid != 1 { ok = false; }
  }
  let s1 = thrift_skip(&mut r, thrift_t_list());
  if !s1.is_ok { ok = false; } else {
    if s1.value != 13 { ok = false; }
  }
  let f2 = thrift_read_field_begin(&mut r);
  if !f2.is_ok { ok = false; } else {
    let fb: ThriftField = f2.value;
    if fb.ftype != thrift_t_map() { ok = false; }
    if fb.fid != 2 { ok = false; }
  }
  let s2 = thrift_skip(&mut r, thrift_t_map());
  if !s2.is_ok { ok = false; } else {
    if s2.value != 15 { ok = false; }
  }
  let f3 = thrift_read_field_begin(&mut r);
  if !f3.is_ok { ok = false; } else {
    let fc: ThriftField = f3.value;
    if fc.ftype != thrift_t_struct() { ok = false; }
    if fc.fid != 3 { ok = false; }
  }
  let s3 = thrift_skip(&mut r, thrift_t_struct());
  if !s3.is_ok { ok = false; } else {
    if s3.value != 12 { ok = false; }
  }
  let f4 = thrift_read_field_begin(&mut r);
  if !f4.is_ok { ok = false; } else {
    let fd: ThriftField = f4.value;
    if fd.ftype != thrift_t_set() { ok = false; }
    if fd.fid != 4 { ok = false; }
  }
  let s4 = thrift_skip(&mut r, thrift_t_set());
  if !s4.is_ok { ok = false; } else {
    if s4.value != 9 { ok = false; }
  }
  let f5 = thrift_read_field_begin(&mut r);
  if !f5.is_ok { ok = false; } else {
    let fe: ThriftField = f5.value;
    if fe.ftype != thrift_t_stop() { ok = false; }
  }
  if thrift_reader_pos(&r) != total { ok = false; }
  return assert(ok, "skip recurses through nested struct, map, list and set values");
}

fn t20() -> TestResult {
  var ok = thrift_max_depth() == 64;
  var deep = Vec[UInt8].new();
  var i = 0;
  while i < 63 {
    append_bytes(&mut deep, hb("0c0001"));
    i = i + 1;
  }
  i = 0;
  while i < 64 {
    append_bytes(&mut deep, hb("00"));
    i = i + 1;
  }
  var r = thrift_reader_new(deep);
  let okr = thrift_skip(&mut r, thrift_t_struct());
  if !okr.is_ok {
    ok = false;
  } else {
    if okr.value != 253 { ok = false; }
    if thrift_reader_remaining(&r) != 0 { ok = false; }
  }
  var deep2 = Vec[UInt8].new();
  i = 0;
  while i < 64 {
    append_bytes(&mut deep2, hb("0c0001"));
    i = i + 1;
  }
  i = 0;
  while i < 64 {
    append_bytes(&mut deep2, hb("00"));
    i = i + 1;
  }
  var r2 = thrift_reader_new(deep2);
  let bad = thrift_skip(&mut r2, thrift_t_struct());
  if !err_is_i(bad, "thrift: nesting depth exceeds limit of 64") { ok = false; }
  return assert(ok, "skip depth cap: 64 nested structs accepted, 65 rejected");
}

// A fresh empty byte vector (one per parallel-vector slot, so no two
// entries share a buffer).
fn fresh_bytes() -> Vec[UInt8] {
  return Vec[UInt8].new();
}

fn fresh_ints() -> Vec[Int] {
  return Vec[Int].new();
}

fn fresh_vecbytes() -> Vec[Vec[UInt8]] {
  return Vec[Vec[UInt8]].new();
}

// Three-field flat struct: 1: BOOL true, 2: I32 -2, 7: STRING "hi".
fn mk_small_struct() -> ThriftStruct {
  var ids = Vec[Int].new();
  var types = Vec[Int].new();
  var ints = Vec[Int].new();
  var bytes = Vec[Vec[UInt8]].new();
  ids.push(1);
  types.push(thrift_t_bool());
  ints.push(1);
  bytes.push(fresh_bytes());
  ids.push(2);
  types.push(thrift_t_i32());
  ints.push(-2);
  bytes.push(fresh_bytes());
  ids.push(7);
  types.push(thrift_t_string());
  ints.push(0);
  bytes.push(ab("hi"));
  return ThriftStruct{ ids: ids; types: types; ints: ints; bytes: bytes; };
}

// Eight-field flat struct covering every representable type.
fn mk_wide_struct() -> ThriftStruct {
  var ids = Vec[Int].new();
  var types = Vec[Int].new();
  var ints = Vec[Int].new();
  var bytes = Vec[Vec[UInt8]].new();
  ids.push(1);
  types.push(thrift_t_bool());
  ints.push(0);
  bytes.push(fresh_bytes());
  ids.push(2);
  types.push(thrift_t_byte());
  ints.push(-5);
  bytes.push(fresh_bytes());
  ids.push(3);
  types.push(thrift_t_double());
  ints.push(4607182418800017408);
  bytes.push(fresh_bytes());
  ids.push(4);
  types.push(thrift_t_i16());
  ints.push(-1000);
  bytes.push(fresh_bytes());
  ids.push(5);
  types.push(thrift_t_i32());
  ints.push(70000);
  bytes.push(fresh_bytes());
  ids.push(6);
  types.push(thrift_t_i64());
  ints.push(0 - 4294967296);
  bytes.push(fresh_bytes());
  ids.push(7);
  types.push(thrift_t_string());
  ints.push(0);
  bytes.push(ab("hello"));
  ids.push(8);
  types.push(thrift_t_byte());
  ints.push(127);
  bytes.push(fresh_bytes());
  return ThriftStruct{ ids: ids; types: types; ints: ints; bytes: bytes; };
}

fn t21() -> TestResult {
  let s = mk_small_struct();
  let er = thrift_encode_struct(&s);
  var ok = er.is_ok;
  if er.is_ok {
    if !bytes_equal(er.value, hb("02000101080002fffffffe0b000700000002686900")) { ok = false; }
  }
  let dr = thrift_decode_struct(hb("02000101080002fffffffe0b000700000002686900"));
  if !dr.is_ok { ok = false; } else {
    let d: ThriftStruct = dr.value;
    if thrift_struct_count(&d) != 3 { ok = false; }
    if thrift_struct_id(&d, 0) != 1 { ok = false; }
    if thrift_struct_id(&d, 2) != 7 { ok = false; }
    if thrift_struct_type(&d, 1) != thrift_t_i32() { ok = false; }
    if thrift_struct_int(&d, 0) != 1 { ok = false; }
    if thrift_struct_int(&d, 1) != -2 { ok = false; }
    if thrift_struct_field_index(&d, 7) != 2 { ok = false; }
    if thrift_struct_field_index(&d, 99) != -1 { ok = false; }
    let payload = thrift_struct_bytes(&d, 2);
    if !bytes_equal(payload, ab("hi")) { ok = false; }
    if thrift_struct_bytes(&d, 9).len() != 0 { ok = false; }
    if thrift_struct_id(&d, -1) != -1 { ok = false; }
    if thrift_struct_int(&d, 9) != 0 { ok = false; }
    if thrift_struct_type(&d, 9) != -1 { ok = false; }
  }
  let wide = mk_wide_struct();
  let wr = thrift_encode_struct(&wide);
  if !wr.is_ok {
    ok = false;
  } else {
    let back = thrift_decode_struct(wr.value);
    if !back.is_ok {
      ok = false;
    } else {
      let d2: ThriftStruct = back.value;
      if thrift_struct_count(&d2) != 8 { ok = false; }
      var i = 0;
      while i < 8 {
        if thrift_struct_id(&d2, i) != thrift_struct_id(&wide, i) { ok = false; }
        if thrift_struct_type(&d2, i) != thrift_struct_type(&wide, i) { ok = false; }
        if thrift_struct_int(&d2, i) != thrift_struct_int(&wide, i) { ok = false; }
        let a = thrift_struct_bytes(&d2, i);
        let b = thrift_struct_bytes(&wide, i);
        if !bytes_equal(a, b) { ok = false; }
        i = i + 1;
      }
    }
  }
  return assert(ok, "flat struct model encodes, decodes and exposes parallel vectors");
}

fn t22() -> TestResult {
  var ids = Vec[Int].new();
  ids.push(1);
  let bad1 = ThriftStruct{ ids: ids; types: fresh_ints(); ints: fresh_ints(); bytes: fresh_vecbytes(); };
  var ok = err_is_bytes(thrift_encode_struct(&bad1), "thrift: struct vectors length mismatch");
  var ids2 = Vec[Int].new();
  ids2.push(1);
  var types2 = Vec[Int].new();
  types2.push(5);
  var ints2 = Vec[Int].new();
  ints2.push(0);
  var bytes2 = Vec[Vec[UInt8]].new();
  bytes2.push(fresh_bytes());
  let bad2 = ThriftStruct{ ids: ids2; types: types2; ints: ints2; bytes: bytes2; };
  if !err_is_bytes(thrift_encode_struct(&bad2), "thrift: unknown type id 5") { ok = false; }
  var ids3 = Vec[Int].new();
  ids3.push(1);
  var types3 = Vec[Int].new();
  types3.push(thrift_t_list());
  var ints3 = Vec[Int].new();
  ints3.push(0);
  var bytes3 = Vec[Vec[UInt8]].new();
  bytes3.push(fresh_bytes());
  let bad3 = ThriftStruct{ ids: ids3; types: types3; ints: ints3; bytes: bytes3; };
  if !err_is_bytes(thrift_encode_struct(&bad3), "thrift: struct field type not supported") { ok = false; }
  var ids4 = Vec[Int].new();
  ids4.push(1);
  var types4 = Vec[Int].new();
  types4.push(thrift_t_bool());
  var ints4 = Vec[Int].new();
  ints4.push(2);
  var bytes4 = Vec[Vec[UInt8]].new();
  bytes4.push(fresh_bytes());
  let bad4 = ThriftStruct{ ids: ids4; types: types4; ints: ints4; bytes: bytes4; };
  if !err_is_bytes(thrift_encode_struct(&bad4), "thrift: invalid bool value") { ok = false; }
  var ids5 = Vec[Int].new();
  ids5.push(40000);
  var types5 = Vec[Int].new();
  types5.push(thrift_t_i32());
  var ints5 = Vec[Int].new();
  ints5.push(0);
  var bytes5 = Vec[Vec[UInt8]].new();
  bytes5.push(fresh_bytes());
  let bad5 = ThriftStruct{ ids: ids5; types: types5; ints: ints5; bytes: bytes5; };
  if !err_is_bytes(thrift_encode_struct(&bad5), "thrift: field id out of range") { ok = false; }
  if !err_is_struct(thrift_decode_struct(hb("0000")), "thrift: trailing data") { ok = false; }
  if !err_is_struct(thrift_decode_struct(hb("0c000100")), "thrift: struct field type not supported") { ok = false; }
  if !err_is_struct(thrift_decode_struct(hb("0200010200")), "thrift: invalid bool value") { ok = false; }
  if !err_is_struct(thrift_decode_struct(hb("080001")), "thrift: truncated input") { ok = false; }
  if !err_is_struct(thrift_decode_struct(hb("")), "thrift: truncated input") { ok = false; }
  return assert(ok, "struct model rejects drift, unsupported types, bad bools and bad ids");
}

fn t23() -> TestResult {
  var w = thrift_writer_new();
  thrift_write_message_begin(&mut w, "svc", thrift_msg_call(), 42);
  thrift_write_field_begin(&mut w, thrift_t_i32(), 1);
  thrift_write_i32(&mut w, 7);
  thrift_write_field_begin(&mut w, thrift_t_string(), 2);
  thrift_write_string(&mut w, "hi");
  thrift_write_field_begin(&mut w, thrift_t_list(), 3);
  thrift_write_list_begin(&mut w, thrift_t_i32(), 2);
  thrift_write_i32(&mut w, 1);
  thrift_write_i32(&mut w, 2);
  thrift_write_field_begin(&mut w, thrift_t_map(), 4);
  thrift_write_map_begin(&mut w, thrift_t_string(), thrift_t_i32(), 1);
  thrift_write_string(&mut w, "k");
  thrift_write_i32(&mut w, 9);
  thrift_write_field_stop(&mut w);
  let wire = thrift_writer_bytes(&w);
  var r = thrift_reader_new(wire);
  let mr = thrift_read_message_begin(&mut r);
  var ok = mr.is_ok;
  if mr.is_ok {
    let m: ThriftMessage = mr.value;
    if str_compare(m.name, "svc") != 0 { ok = false; }
    if m.msg_type != thrift_msg_call() { ok = false; }
    if m.seqid != 42 { ok = false; }
  }
  let f1 = thrift_read_field_begin(&mut r);
  if !f1.is_ok { ok = false; } else {
    let fa: ThriftField = f1.value;
    if fa.ftype != thrift_t_i32() { ok = false; }
  }
  let v1 = thrift_read_i32(&mut r);
  if !v1.is_ok { ok = false; } else {
    if v1.value != 7 { ok = false; }
  }
  let f2 = thrift_read_field_begin(&mut r);
  if !f2.is_ok { ok = false; } else {
    let fb: ThriftField = f2.value;
    if fb.ftype != thrift_t_string() { ok = false; }
  }
  let s2 = thrift_read_string(&mut r);
  if !s2.is_ok { ok = false; } else {
    if str_compare(s2.value, "hi") != 0 { ok = false; }
  }
  let f3 = thrift_read_field_begin(&mut r);
  if !f3.is_ok { ok = false; } else {
    let fc: ThriftField = f3.value;
    if fc.ftype != thrift_t_list() { ok = false; }
  }
  let l3 = thrift_read_list_header(&mut r);
  if !l3.is_ok { ok = false; } else {
    let h3: ThriftListHeader = l3.value;
    if h3.etype != thrift_t_i32() { ok = false; }
    if h3.size != 2 { ok = false; }
  }
  let e1 = thrift_read_i32(&mut r);
  if !e1.is_ok { ok = false; } else {
    if e1.value != 1 { ok = false; }
  }
  let e2 = thrift_read_i32(&mut r);
  if !e2.is_ok { ok = false; } else {
    if e2.value != 2 { ok = false; }
  }
  let f4 = thrift_read_field_begin(&mut r);
  if !f4.is_ok { ok = false; } else {
    let fd: ThriftField = f4.value;
    if fd.ftype != thrift_t_map() { ok = false; }
  }
  let m4 = thrift_read_map_header(&mut r);
  if !m4.is_ok { ok = false; } else {
    let h4: ThriftMapHeader = m4.value;
    if h4.ktype != thrift_t_string() { ok = false; }
    if h4.vtype != thrift_t_i32() { ok = false; }
    if h4.size != 1 { ok = false; }
  }
  let k4 = thrift_read_string(&mut r);
  if !k4.is_ok { ok = false; } else {
    if str_compare(k4.value, "k") != 0 { ok = false; }
  }
  let v4 = thrift_read_i32(&mut r);
  if !v4.is_ok { ok = false; } else {
    if v4.value != 9 { ok = false; }
  }
  let f5 = thrift_read_field_begin(&mut r);
  if !f5.is_ok { ok = false; } else {
    let fe: ThriftField = f5.value;
    if fe.ftype != thrift_t_stop() { ok = false; }
  }
  if thrift_reader_remaining(&r) != 0 { ok = false; }
  var r2 = thrift_reader_new(thrift_writer_bytes(&w));
  let mr2 = thrift_read_message_begin(&mut r2);
  if !mr2.is_ok { ok = false; }
  var fields = 0;
  var go = true;
  while go {
    let fk = thrift_read_field_begin(&mut r2);
    if !fk.is_ok {
      go = false;
      ok = false;
    } else {
      let ff: ThriftField = fk.value;
      if ff.ftype == thrift_t_stop() {
        go = false;
      } else {
        let sk = thrift_skip(&mut r2, ff.ftype);
        if !sk.is_ok {
          go = false;
          ok = false;
        } else {
          fields = fields + 1;
        }
      }
    }
  }
  if fields != 4 { ok = false; }
  if thrift_reader_remaining(&r2) != 0 { ok = false; }
  return assert(ok, "composite message with struct fields and containers round-trips and skips");
}

fn t24() -> TestResult {
  let w = thrift_writer_new();
  var ok = thrift_writer_len(&w) == 0;
  if thrift_writer_bytes(&w).len() != 0 { ok = false; }
  var r = thrift_reader_new(hb("010203"));
  if thrift_reader_pos(&r) != 0 { ok = false; }
  if thrift_reader_remaining(&r) != 3 { ok = false; }
  let b = thrift_read_byte(&mut r);
  if !b.is_ok { ok = false; } else {
    if b.value != 1 { ok = false; }
  }
  if thrift_reader_pos(&r) != 1 { ok = false; }
  if thrift_reader_remaining(&r) != 2 { ok = false; }
  if thrift_t_stop() != 0 { ok = false; }
  if thrift_t_bool() != 2 { ok = false; }
  if thrift_t_byte() != 3 { ok = false; }
  if thrift_t_double() != 4 { ok = false; }
  if thrift_t_i16() != 6 { ok = false; }
  if thrift_t_i32() != 8 { ok = false; }
  if thrift_t_i64() != 10 { ok = false; }
  if thrift_t_string() != 11 { ok = false; }
  if thrift_t_struct() != 12 { ok = false; }
  if thrift_t_map() != 13 { ok = false; }
  if thrift_t_set() != 14 { ok = false; }
  if thrift_t_list() != 15 { ok = false; }
  if thrift_msg_call() != 1 { ok = false; }
  if thrift_msg_reply() != 2 { ok = false; }
  if thrift_msg_exception() != 3 { ok = false; }
  if thrift_msg_oneway() != 4 { ok = false; }
  return assert(ok, "reader/writer lifecycle, type ids and message type ids");
}

fn main() -> Int {
  io.println("=== xiom.thrift conformance tests ===");
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
  if failed == 0 {
    io.println("xiom.thrift: all tests passed");
  } else {
    io.println("xiom.thrift: tests failed");
  }
  return failed;
}


