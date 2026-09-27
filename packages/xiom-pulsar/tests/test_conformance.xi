// XIOM -- xiom.pulsar conformance tests
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Covers the documented API end to end with synthetic buffers built in-test
// (independent test-side varint/u32/field builders, plus pinned hex):
// varint boundaries and overflow rejection, u32/i32/i64 readers, fixed32/64,
// field keys, length-delimited values, unknown-field skip, packed repeated
// runs, MessageIdData (partition/batch defaults, ack_set summary), CONNECT /
// CONNECTED / SUBSCRIBE / PRODUCER / SEND / MESSAGE / SEND_RECEIPT / ACK /
// PING / PONG / unknown-command decoding, MessageMetadata (properties,
// partition_key, event_time, deliver_at_time, compression), unknown-field
// preservation, malformed frame lengths with byte-offset errors, encode ->
// decode round-trips and the nesting cap.
//
// Str values are compared with str_compare (BUG 17 discipline), every Vec
// read is bound to a typed local, and Ok/Err are never constructed in test
// functions (only matched).

module pulsar_tests
use xiom.io; use xiom.test;
use xiom.pulsar;
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

fn err_bytes_is(r: Result[Vec[UInt8], Str], want: Str) -> Bool {
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

fn err_scalar_is(r: Result[PulsarScalar, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_delim_is(r: Result[PulsarDelimited, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_step_is(r: Result[PulsarFieldStep, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_mid_is(r: Result[PulsarMessageId, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_meta_is(r: Result[PulsarMessageMetadata, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_cmd_is(r: Result[PulsarCommand, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_frame_is(r: Result[PulsarFrame, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_advance_is(r: Result[PulsarAdvance, Str], want: Str) -> Bool {
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
fn t_u32(out: &mut Vec[UInt8], v: Int) {
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

fn t_field_i32(out: &mut Vec[UInt8], field_number: Int, v: Int) {
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

// A nested KeyValue body as MessageMetadata property pairs.
fn t_property(out: &mut Vec[UInt8], k: Str, v: Str) {
  var kv = Vec[UInt8].new();
  t_field_str(&mut kv, 1, k);
  t_field_str(&mut kv, 2, v);
  t_field_bytes(out, 4, &kv);
}

// A nested MessageIdData field.
fn t_mid(out: &mut Vec[UInt8], field_number: Int, ledger: Int, entry: Int, partition: Int, batch: Int, acks: &Vec[Int]) {
  var body = Vec[UInt8].new();
  t_field_varint(&mut body, 1, ledger);
  t_field_varint(&mut body, 2, entry);
  if partition != -1 {
    t_field_i32(&mut body, 3, partition);
  }
  if batch != -1 {
    t_field_i32(&mut body, 4, batch);
  }
  var i = 0;
  while i < acks.len() {
    let v: Int = acks[i];
    t_field_i32(&mut body, 5, v);
    i = i + 1;
  }
  t_field_bytes(out, field_number, &body);
}

// A whole BaseCommand: type field 1 plus the body field (number == type).
fn t_command(out: &mut Vec[UInt8], t: Int, body: &Vec[UInt8]) {
  t_field_varint(out, 1, t);
  t_field_bytes(out, t, body);
}

// A whole frame built by the test (same layout as the library writer).
fn t_frame(command: &Vec[UInt8], has_meta: Bool, metadata: &Vec[UInt8], payload: &Vec[UInt8]) -> Vec[UInt8] {
  var inner = 4 + command.len();
  if has_meta {
    inner = inner + 4 + metadata.len();
  }
  inner = inner + payload.len();
  var out = Vec[UInt8].new();
  t_u32(&mut out, inner);
  t_u32(&mut out, command.len());
  push_bytes(&mut out, command);
  if has_meta {
    t_u32(&mut out, metadata.len());
    push_bytes(&mut out, metadata);
  }
  push_bytes(&mut out, payload);
  return out;
}

// --------------------------------------------------
//  Tests
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
    let e = pulsar_encode_varint(v);
    if !e.is_ok {
      ok = false;
    } else {
      let enc: Vec[UInt8] = e.value;
      let d = pulsar_read_varint(&enc, 0);
      if !d.is_ok {
        ok = false;
      } else {
        let s: PulsarScalar = d.value;
        if s.value != v {
          ok = false;
        }
        if s.size != enc.len() {
          ok = false;
        }
      }
    }
    i = i + 1;
  }
  if !bytes_equal(enc_ok(pulsar_encode_varint(300)), hb("ac02")) { ok = false; }
  if !bytes_equal(enc_ok(pulsar_encode_varint(0)), hb("00")) { ok = false; }
  if pulsar_max_varint_bytes() != 10 { ok = false; }
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
  if !err_scalar_is(pulsar_read_varint(&too_long, 0), "pulsar: varint too long at offset 0") { ok = false; }
  // 10th byte with data bits above bit 0: 64-bit overflow.
  var overflow = hb("ffffffffffffffffff02");
  if !err_scalar_is(pulsar_read_varint(&overflow, 0), "pulsar: varint overflows 64 bits at offset 0") { ok = false; }
  // 10th byte carrying bit 63: outside the signed Int range.
  var signed_hi = hb("ffffffffffffffffff01");
  if !err_scalar_is(pulsar_read_varint(&signed_hi, 0), "pulsar: varint exceeds signed 64-bit range at offset 0") { ok = false; }
  if !err_scalar_is(pulsar_read_varint(hb("80"), 0), "pulsar: truncated varint at offset 1") { ok = false; }
  if !err_scalar_is(pulsar_read_varint(hb("80"), 5), "pulsar: varint out of bounds at offset 5") { ok = false; }
  if !err_scalar_is(pulsar_read_varint(hb("80"), 0), "pulsar: truncated varint at offset 1") { ok = false; }
  return assert(ok, "varint overflow, too-long, signed-range and truncation errors");
}

fn t3() -> TestResult {
  var ok = true;
  var two32 = enc_ok(pulsar_encode_varint(4294967296));
  if !err_scalar_is(pulsar_read_varint_u32(&two32, 0), "pulsar: varint exceeds u32 at offset 0") { ok = false; }
  let d32 = pulsar_read_varint_u32(&two32, 0);
  if d32.is_ok { ok = false; }
  // Test-side sign-extended -1 (10 bytes).
  var neg = Vec[UInt8].new();
  t_varint_signed(&mut neg, -1);
  if neg.len() != 10 { ok = false; }
  let i32r = pulsar_read_varint_i32(&neg, 0);
  if !i32r.is_ok {
    ok = false;
  } else {
    let s: PulsarScalar = i32r.value;
    if s.value != -1 { ok = false; }
    if s.size != 10 { ok = false; }
  }
  let i64r = pulsar_read_varint_i64(&neg, 0);
  if !i64r.is_ok {
    ok = false;
  } else {
    let s: PulsarScalar = i64r.value;
    if s.value != -1 { ok = false; }
  }
  if !err_scalar_is(pulsar_read_varint(&neg, 0), "pulsar: varint exceeds signed 64-bit range at offset 0") { ok = false; }
  let five = hb("05");
  let i32b = pulsar_read_varint_i32(&five, 0);
  if !i32b.is_ok {
    ok = false;
  } else {
    let s: PulsarScalar = i32b.value;
    if s.value != 5 { ok = false; }
  }
  return assert(ok, "u32/i32/i64 readers: u32 cap, sign-extended -1, small values");
}

fn t4() -> TestResult {
  var ok = true;
  let f32 = pulsar_read_fixed32(hb("01000000"), 0);
  if !f32.is_ok {
    ok = false;
  } else {
    let s: PulsarScalar = f32.value;
    if s.value != 1 { ok = false; }
    if s.size != 4 { ok = false; }
  }
  let f32m = pulsar_read_fixed32(hb("ffffffff"), 0);
  if !f32m.is_ok {
    ok = false;
  } else {
    let s: PulsarScalar = f32m.value;
    if s.value != 4294967295 { ok = false; }
  }
  if !err_scalar_is(pulsar_read_fixed32(hb("0102"), 0), "pulsar: truncated fixed32 at offset 2") { ok = false; }
  let f64 = pulsar_read_fixed64(hb("0100000000000000"), 0);
  if !f64.is_ok {
    ok = false;
  } else {
    let s: PulsarScalar = f64.value;
    if s.value != 1 { ok = false; }
    if s.size != 8 { ok = false; }
  }
  if !err_scalar_is(pulsar_read_fixed64(hb("ffffffffffffffff"), 0), "pulsar: fixed64 exceeds signed 64-bit range at offset 0") { ok = false; }
  if !err_scalar_is(pulsar_read_fixed64(hb("010203"), 0), "pulsar: truncated fixed64 at offset 3") { ok = false; }
  return assert(ok, "fixed32/fixed64 reads, truncation and fixed64 range");
}

fn t5() -> TestResult {
  var ok = true;
  if pulsar_key(9, 2) != 74 { ok = false; }
  if pulsar_key_field_number(74) != 9 { ok = false; }
  if pulsar_key_wire_type(74) != 2 { ok = false; }
  if pulsar_key(1, 0) != 8 { ok = false; }
  if !bytes_equal(enc_ok(pulsar_encode_key(1, 0)), hb("08")) { ok = false; }
  if !bytes_equal(enc_ok(pulsar_encode_key(9, 2)), hb("4a")) { ok = false; }
  if !err_bytes_is(pulsar_encode_key(0, 0), "pulsar: bad field number") { ok = false; }
  if !err_bytes_is(pulsar_encode_key(1, 3), "pulsar: bad wire type") { ok = false; }
  return assert(ok, "field keys: encode, split and validation");
}

fn t6() -> TestResult {
  var ok = true;
  let d = pulsar_read_delimited(hb("03414243"), 0);
  if !d.is_ok {
    ok = false;
  } else {
    let x: PulsarDelimited = d.value;
    if x.start != 1 { ok = false; }
    if x.size != 3 { ok = false; }
    if x.total != 4 { ok = false; }
  }
  if !err_delim_is(pulsar_read_delimited(hb("054142"), 0), "pulsar: truncated length-delimited field at offset 3") { ok = false; }
  if !err_delim_is(pulsar_read_delimited(hb("80"), 0), "pulsar: truncated varint at offset 1") { ok = false; }
  let empty = pulsar_read_delimited(hb("00"), 0);
  if !empty.is_ok {
    ok = false;
  } else {
    let x: PulsarDelimited = empty.value;
    if x.size != 0 { ok = false; }
    if x.total != 1 { ok = false; }
  }
  return assert(ok, "length-delimited read, empty value and truncation");
}

fn t7() -> TestResult {
  var ok = true;
  let s0 = pulsar_skip_field(hb("ac02"), 0, 0);
  if !s0.is_ok {
    ok = false;
  } else {
    let a: PulsarAdvance = s0.value;
    if a.pos != 2 { ok = false; }
    if a.size != 2 { ok = false; }
  }
  let s1 = pulsar_skip_field(hb("0102030405060708"), 0, 1);
  if !s1.is_ok {
    ok = false;
  } else {
    let a: PulsarAdvance = s1.value;
    if a.pos != 8 { ok = false; }
  }
  let s2 = pulsar_skip_field(hb("03414243"), 0, 2);
  if !s2.is_ok {
    ok = false;
  } else {
    let a: PulsarAdvance = s2.value;
    if a.pos != 4 { ok = false; }
  }
  let s5 = pulsar_skip_field(hb("01020304"), 0, 5);
  if !s5.is_ok {
    ok = false;
  } else {
    let a: PulsarAdvance = s5.value;
    if a.pos != 4 { ok = false; }
  }
  if !err_advance_is(pulsar_skip_field(hb("00"), 0, 3), "pulsar: unsupported wire type 3 at offset 0") { ok = false; }
  if !err_advance_is(pulsar_skip_field(hb("0102"), 0, 1), "pulsar: truncated fixed64 at offset 2") { ok = false; }
  return assert(ok, "unknown-field skip for wire types 0/1/2/5 and rejection");
}

fn t8() -> TestResult {
  var ok = true;
  var out = Vec[Int].new();
  let r = pulsar_read_packed_varints(hb("010203"), 0, 3, &mut out);
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
  if !err_int_is(pulsar_read_packed_varints(hb("8001"), 0, 1, &mut out2), "pulsar: packed run crosses boundary at offset 0") { ok = false; }
  var out3 = Vec[Int].new();
  let r3 = pulsar_read_packed_varints(hb("ac02"), 0, 2, &mut out3);
  if !r3.is_ok {
    ok = false;
  } else {
    let v: Int = out3[0];
    if v != 300 { ok = false; }
  }
  return assert(ok, "packed repeated varints: values, multi-byte and boundary");
}

fn t9() -> TestResult {
  var ok = true;
  // Pinned MessageIdData: ledger 1, entry 2, batch_index 5 (partition absent).
  let r = pulsar_parse_message_id_body(hb("080110022005"), 0, 6, 1);
  if !r.is_ok {
    return assert(false, "message id body decodes");
  }
  let m: PulsarMessageId = r.value;
  if m.ledger_id != 1 { ok = false; }
  if m.entry_id != 2 { ok = false; }
  if m.partition != -1 { ok = false; }
  if m.batch_index != 5 { ok = false; }
  if pulsar_message_id_ack_count(&m) != 0 { ok = false; }
  if m.ack_set_bits != 0 { ok = false; }
  // Explicit partition and batch, negative allowed (-1 default written).
  var body = Vec[UInt8].new();
  t_field_varint(&mut body, 1, 7);
  t_field_varint(&mut body, 2, 8);
  t_field_i32(&mut body, 3, -1);
  t_field_i32(&mut body, 4, 9);
  let r2 = pulsar_parse_message_id_body(&body, 0, body.len(), 1);
  if !r2.is_ok {
    ok = false;
  } else {
    let m2: PulsarMessageId = r2.value;
    if m2.ledger_id != 7 || m2.entry_id != 8 { ok = false; }
    if m2.partition != -1 { ok = false; }
    if m2.batch_index != 9 { ok = false; }
  }
  if !err_mid_is(pulsar_parse_message_id_body(hb("0801"), 0, 9, 1), "pulsar: bad message range at offset 0") { ok = false; }
  return assert(ok, "MessageIdData decode: defaults, explicit fields, bad range");
}

fn t10() -> TestResult {
  var ok = true;
  // Unpacked ack_set: entries 1 and 4 -> bits 2^1 + 2^4 = 18.
  let r = pulsar_parse_message_id_body(hb("0801100228012804"), 0, 8, 1);
  if !r.is_ok {
    return assert(false, "unpacked ack_set decodes");
  }
  let m: PulsarMessageId = r.value;
  if pulsar_message_id_ack_count(&m) != 2 { ok = false; }
  if pulsar_message_id_ack_at(&m, 0) != 1 { ok = false; }
  if pulsar_message_id_ack_at(&m, 1) != 4 { ok = false; }
  if m.ack_set_bits != 18 { ok = false; }
  if !pulsar_message_id_ack_has(&m, 1) { ok = false; }
  if !pulsar_message_id_ack_has(&m, 4) { ok = false; }
  if pulsar_message_id_ack_has(&m, 2) { ok = false; }
  // Packed ack_set: same entries, field 5 wire type 2.
  let r2 = pulsar_parse_message_id_body(hb("080110022a020104"), 0, 8, 1);
  if !r2.is_ok {
    ok = false;
  } else {
    let m2: PulsarMessageId = r2.value;
    if pulsar_message_id_ack_count(&m2) != 2 { ok = false; }
    if m2.ack_set_bits != 18 { ok = false; }
  }
  // Summary folds v into bit (v % 63): entry 63 sets bit 0, entry 64 sets bit 1.
  let r3 = pulsar_parse_message_id_body(hb("08011002283f2840"), 0, 8, 1);
  if !r3.is_ok {
    ok = false;
  } else {
    let m3: PulsarMessageId = r3.value;
    if m3.ack_set_bits != 1 + 2 { ok = false; }
    if !pulsar_message_id_ack_has(&m3, 63) { ok = false; }
    if !pulsar_message_id_ack_has(&m3, 64) { ok = false; }
    if pulsar_message_id_ack_has(&m3, 2) { ok = false; }
  }
  return assert(ok, "ack_set: unpacked + packed entries and 63-bit summary");
}

fn t11() -> TestResult {
  var ok = true;
  var body = Vec[UInt8].new();
  t_field_str(&mut body, 1, "test-client");
  t_field_varint(&mut body, 4, 19);
  t_field_str(&mut body, 5, "token");
  var cmd = Vec[UInt8].new();
  t_command(&mut cmd, 2, &body);
  let r = pulsar_decode_base_command(&cmd);
  if !r.is_ok {
    return assert(false, "CONNECT decodes");
  }
  let c: PulsarCommand = r.value;
  if c.cmd_type != 2 { ok = false; }
  if !c.known { ok = false; }
  if !c.has_body { ok = false; }
  if !str_eq(c.client_version, "test-client") { ok = false; }
  if !str_eq(c.auth_method_name, "token") { ok = false; }
  if c.protocol_version != 19 { ok = false; }
  if !c.has_protocol_version { ok = false; }
  if pulsar_command_unknown_fields(&c) != 0 { ok = false; }
  if pulsar_command_field_count(&c) != 5 { ok = false; }
  if !str_eq(pulsar_cmd_type_name(c.cmd_type), "CONNECT") { ok = false; }
  return assert(ok, "CONNECT decode: client_version, protocol_version, auth_method_name");
}

fn t12() -> TestResult {
  var ok = true;
  var body = Vec[UInt8].new();
  t_field_str(&mut body, 1, "broker-1.0");
  t_field_varint(&mut body, 2, 21);
  t_field_varint(&mut body, 3, 5242880);
  var cmd = Vec[UInt8].new();
  t_command(&mut cmd, 3, &body);
  let r = pulsar_decode_base_command(&cmd);
  if !r.is_ok {
    return assert(false, "CONNECTED decodes");
  }
  let c: PulsarCommand = r.value;
  if c.cmd_type != 3 { ok = false; }
  if !str_eq(c.server_version, "broker-1.0") { ok = false; }
  if c.protocol_version != 21 { ok = false; }
  if c.max_message_size != 5242880 { ok = false; }
  if !c.has_max_message_size { ok = false; }
  if pulsar_command_unknown_fields(&c) != 0 { ok = false; }
  return assert(ok, "CONNECTED decode: server_version, protocol_version, max_message_size");
}

fn t13() -> TestResult {
  var ok = true;
  var body = Vec[UInt8].new();
  t_field_str(&mut body, 1, "persistent://public/default/t");
  t_field_str(&mut body, 2, "sub");
  t_field_varint(&mut body, 3, 1);
  t_field_varint(&mut body, 4, 42);
  t_field_varint(&mut body, 5, 7);
  t_field_varint(&mut body, 8, 0);
  var cmd = Vec[UInt8].new();
  t_command(&mut cmd, 4, &body);
  let r = pulsar_decode_base_command(&cmd);
  if !r.is_ok {
    return assert(false, "SUBSCRIBE decodes");
  }
  let c: PulsarCommand = r.value;
  if !str_eq(c.topic, "persistent://public/default/t") { ok = false; }
  if !str_eq(c.subscription, "sub") { ok = false; }
  if c.sub_type != 1 { ok = false; }
  if !str_eq(pulsar_sub_type_name(c.sub_type), "Shared") { ok = false; }
  if c.consumer_id != 42 { ok = false; }
  if c.request_id != 7 { ok = false; }
  if !c.has_durable { ok = false; }
  if c.durable { ok = false; }
  if pulsar_command_durable(&c) { ok = false; }
  // Durable absent -> proto2 default true.
  var body2 = Vec[UInt8].new();
  t_field_str(&mut body2, 1, "t");
  t_field_str(&mut body2, 2, "s");
  t_field_varint(&mut body2, 3, 0);
  t_field_varint(&mut body2, 4, 1);
  t_field_varint(&mut body2, 5, 2);
  var cmd2 = Vec[UInt8].new();
  t_command(&mut cmd2, 4, &body2);
  let r2 = pulsar_decode_base_command(&cmd2);
  if !r2.is_ok {
    ok = false;
  } else {
    let c2: PulsarCommand = r2.value;
    if c2.has_durable { ok = false; }
    if !pulsar_command_durable(&c2) { ok = false; }
    if c2.sub_type != 0 { ok = false; }
  }
  return assert(ok, "SUBSCRIBE decode: topic, subscription, sub_type, durable default");
}

fn t14() -> TestResult {
  var ok = true;
  var body = Vec[UInt8].new();
  t_field_str(&mut body, 1, "persistent://public/default/p");
  t_field_varint(&mut body, 2, 55);
  t_field_varint(&mut body, 3, 77);
  t_field_str(&mut body, 4, "p1");
  var cmd = Vec[UInt8].new();
  t_command(&mut cmd, 5, &body);
  let r = pulsar_decode_base_command(&cmd);
  if !r.is_ok {
    return assert(false, "PRODUCER decodes");
  }
  let c: PulsarCommand = r.value;
  if !str_eq(c.topic, "persistent://public/default/p") { ok = false; }
  if c.producer_id != 55 { ok = false; }
  if c.request_id != 77 { ok = false; }
  if !str_eq(c.producer_name, "p1") { ok = false; }
  return assert(ok, "PRODUCER decode: topic, producer_id, request_id, producer_name");
}

fn t15() -> TestResult {
  var ok = true;
  var body = Vec[UInt8].new();
  t_field_varint(&mut body, 1, 9);
  t_field_varint(&mut body, 2, 100);
  t_field_varint(&mut body, 3, 3);
  var cmd = Vec[UInt8].new();
  t_command(&mut cmd, 6, &body);
  var meta = Vec[UInt8].new();
  t_field_str(&mut meta, 1, "prod");
  t_field_varint(&mut meta, 2, 100);
  t_field_varint(&mut meta, 3, 1234567890);
  t_property(&mut meta, "k1", "v1");
  t_property(&mut meta, "k2", "v2");
  t_field_varint(&mut meta, 8, 1);
  t_field_varint(&mut meta, 9, 11);
  let payload = hb("010203");
  let frame = t_frame(&cmd, true, &meta, &payload);
  let r = pulsar_parse_frame(&frame);
  if !r.is_ok {
    return assert(false, "SEND frame decodes");
  }
  let fr: PulsarFrame = r.value;
  if pulsar_frame_command_type(&fr) != 6 { ok = false; }
  let c: PulsarCommand = fr.command;
  if c.producer_id != 9 { ok = false; }
  if c.sequence_id != 100 { ok = false; }
  if pulsar_command_num_messages(&c) != 3 { ok = false; }
  if !c.has_num_messages { ok = false; }
  if !fr.has_metadata { ok = false; }
  if !str_eq(fr.metadata.producer_name, "prod") { ok = false; }
  if fr.metadata.sequence_id != 100 { ok = false; }
  if fr.metadata.publish_time != 1234567890 { ok = false; }
  if pulsar_metadata_property_count(&fr.metadata) != 2 { ok = false; }
  if !bytes_equal(pulsar_metadata_property_key(&fr.metadata, 0), bytes_of("k1")) { ok = false; }
  if !bytes_equal(pulsar_metadata_property_value(&fr.metadata, 0), bytes_of("v1")) { ok = false; }
  if !bytes_equal(pulsar_metadata_property_key(&fr.metadata, 1), bytes_of("k2")) { ok = false; }
  if fr.metadata.compression != 1 { ok = false; }
  if !str_eq(pulsar_compression_name(fr.metadata.compression), "LZ4") { ok = false; }
  if fr.metadata.uncompressed_size != 11 { ok = false; }
  if !bytes_equal(fr.payload, payload) { ok = false; }
  if pulsar_frame_consumed(&fr) != frame.len() { ok = false; }
  if fr.payload_offset != frame.len() - 3 { ok = false; }
  // A SEND frame without the metadata tail keeps an empty payload tail.
  let frame2 = t_frame(&cmd, false, Vec[UInt8].new(), Vec[UInt8].new());
  let r2 = pulsar_parse_frame(&frame2);
  if !r2.is_ok {
    ok = false;
  } else {
    let fr2: PulsarFrame = r2.value;
    if fr2.has_metadata { ok = false; }
    if pulsar_frame_payload_len(&fr2) != 0 { ok = false; }
    if pulsar_frame_consumed(&fr2) != frame2.len() { ok = false; }
  }
  return assert(ok, "SEND frame: command fields, metadata, properties, payload, consumed");
}

fn t16() -> TestResult {
  var ok = true;
  var acks = Vec[Int].new();
  acks.push(3);
  var body = Vec[UInt8].new();
  t_field_varint(&mut body, 1, 5);
  t_mid(&mut body, 2, 10, 20, 1, 2, &acks);
  t_field_varint(&mut body, 3, 4);
  var cmd = Vec[UInt8].new();
  t_command(&mut cmd, 9, &body);
  let r = pulsar_decode_base_command(&cmd);
  if !r.is_ok {
    return assert(false, "MESSAGE decodes");
  }
  let c: PulsarCommand = r.value;
  if c.consumer_id != 5 { ok = false; }
  if !c.has_message_id { ok = false; }
  if c.message_id.ledger_id != 10 { ok = false; }
  if c.message_id.entry_id != 20 { ok = false; }
  if c.message_id.partition != 1 { ok = false; }
  if c.message_id.batch_index != 2 { ok = false; }
  if pulsar_message_id_ack_count(&c.message_id) != 1 { ok = false; }
  if pulsar_message_id_ack_at(&c.message_id, 0) != 3 { ok = false; }
  if c.message_id.ack_set_bits != 8 { ok = false; }
  if c.redelivery_count != 4 { ok = false; }
  return assert(ok, "MESSAGE decode: consumer_id, nested MessageIdData, redelivery_count");
}

fn t17() -> TestResult {
  var ok = true;
  var body = Vec[UInt8].new();
  t_field_varint(&mut body, 1, 7);
  t_field_varint(&mut body, 2, 8);
  var none = Vec[Int].new();
  t_mid(&mut body, 3, 1000, 2000, -1, -1, &none);
  var cmd = Vec[UInt8].new();
  t_command(&mut cmd, 7, &body);
  let r = pulsar_decode_base_command(&cmd);
  if !r.is_ok {
    return assert(false, "SEND_RECEIPT decodes");
  }
  let c: PulsarCommand = r.value;
  if c.producer_id != 7 { ok = false; }
  if c.sequence_id != 8 { ok = false; }
  if !c.has_message_id { ok = false; }
  if c.message_id.ledger_id != 1000 { ok = false; }
  if c.message_id.entry_id != 2000 { ok = false; }
  if c.message_id.partition != -1 { ok = false; }
  if c.message_id.batch_index != -1 { ok = false; }
  return assert(ok, "SEND_RECEIPT decode: producer_id, sequence_id, message_id");
}

fn t18() -> TestResult {
  var ok = true;
  var none = Vec[Int].new();
  var body = Vec[UInt8].new();
  t_field_varint(&mut body, 1, 3);
  t_field_varint(&mut body, 2, 1);
  t_mid(&mut body, 3, 1, 2, -1, -1, &none);
  t_mid(&mut body, 3, 3, 4, 2, -1, &none);
  t_field_varint(&mut body, 8, 99);
  var cmd = Vec[UInt8].new();
  t_command(&mut cmd, 10, &body);
  let r = pulsar_decode_base_command(&cmd);
  if !r.is_ok {
    return assert(false, "ACK decodes");
  }
  let c: PulsarCommand = r.value;
  if c.consumer_id != 3 { ok = false; }
  if c.ack_type != 1 { ok = false; }
  if !str_eq(pulsar_ack_type_name(c.ack_type), "Cumulative") { ok = false; }
  if pulsar_mid_list_len(&c.ack_ids) != 2 { ok = false; }
  if pulsar_mid_list_ledger(&c.ack_ids, 0) != 1 { ok = false; }
  if pulsar_mid_list_entry(&c.ack_ids, 0) != 2 { ok = false; }
  if pulsar_mid_list_partition(&c.ack_ids, 0) != -1 { ok = false; }
  if pulsar_mid_list_batch_index(&c.ack_ids, 0) != -1 { ok = false; }
  if pulsar_mid_list_ledger(&c.ack_ids, 1) != 3 { ok = false; }
  if pulsar_mid_list_entry(&c.ack_ids, 1) != 4 { ok = false; }
  if pulsar_mid_list_partition(&c.ack_ids, 1) != 2 { ok = false; }
  if pulsar_mid_list_ledger(&c.ack_ids, 9) != 0 { ok = false; }
  if pulsar_mid_list_partition(&c.ack_ids, 9) != -1 { ok = false; }
  if c.request_id != 99 { ok = false; }
  return assert(ok, "ACK decode: consumer_id, ack_type, repeated message_id list");
}

fn t19() -> TestResult {
  var ok = true;
  // PING: type 18, empty body field 18 (key 0x92 0x01, length 0).
  var cmd = hb("0812920100");
  let r = pulsar_decode_base_command(&cmd);
  if !r.is_ok {
    return assert(false, "PING decodes");
  }
  let c: PulsarCommand = r.value;
  if c.cmd_type != 18 { ok = false; }
  if !c.known { ok = false; }
  if !c.has_body { ok = false; }
  if !str_eq(pulsar_cmd_type_name(c.cmd_type), "PING") { ok = false; }
  if !bytes_equal(c.raw, cmd) { ok = false; }
  // PONG.
  var cmd2 = hb("08139a0100");
  let r2 = pulsar_decode_base_command(&cmd2);
  if !r2.is_ok {
    ok = false;
  } else {
    let c2: PulsarCommand = r2.value;
    if c2.cmd_type != 19 { ok = false; }
    if !str_eq(pulsar_cmd_type_name(c2.cmd_type), "PONG") { ok = false; }
  }
  // Unknown type 77 with a body; everything is preserved raw.
  var cmd3 = hb("084dea04020801");
  let r3 = pulsar_decode_base_command(&cmd3);
  if !r3.is_ok {
    ok = false;
  } else {
    let c3: PulsarCommand = r3.value;
    if c3.known { ok = false; }
    if c3.cmd_type != 77 { ok = false; }
    if pulsar_command_unknown_fields(&c3) < 1 { ok = false; }
    if c3.unknown_bytes.len() == 0 { ok = false; }
    if !bytes_equal(c3.raw, cmd3) { ok = false; }
    if !str_eq(pulsar_cmd_type_name(c3.cmd_type), "UNKNOWN") { ok = false; }
  }
  if !err_cmd_is(pulsar_decode_base_command(&Vec[UInt8].new()), "pulsar: empty base command") { ok = false; }
  let fld0 = pulsar_decode_base_command(hb("00"));
  if fld0.is_ok { ok = false; }
  return assert(ok, "PING/PONG decode and unknown-command raw preservation");
}

fn t20() -> TestResult {
  var ok = true;
  var meta = Vec[UInt8].new();
  t_field_str(&mut meta, 1, "p");
  t_field_varint(&mut meta, 2, 1);
  t_field_varint(&mut meta, 3, 2);
  t_property(&mut meta, "a", "1");
  t_property(&mut meta, "b", "2");
  t_field_str(&mut meta, 6, "pk");
  t_field_varint(&mut meta, 8, 3);
  t_field_varint(&mut meta, 9, 5);
  t_field_varint(&mut meta, 12, 3);
  t_field_varint(&mut meta, 19, 4);
  t_field_varint(&mut meta, 99, 1);
  let r = pulsar_parse_metadata_body(&meta, 0, meta.len(), 1);
  if !r.is_ok {
    return assert(false, "metadata decodes");
  }
  let m: PulsarMessageMetadata = r.value;
  if !str_eq(m.producer_name, "p") { ok = false; }
  if !m.has_producer_name { ok = false; }
  if m.sequence_id != 1 || !m.has_sequence_id { ok = false; }
  if m.publish_time != 2 || !m.has_publish_time { ok = false; }
  if pulsar_metadata_property_count(&m) != 2 { ok = false; }
  if !bytes_equal(pulsar_metadata_property_key(&m, 0), bytes_of("a")) { ok = false; }
  if !bytes_equal(pulsar_metadata_property_value(&m, 1), bytes_of("2")) { ok = false; }
  if !str_eq(m.partition_key, "pk") { ok = false; }
  if !m.has_partition_key { ok = false; }
  if m.compression != 3 { ok = false; }
  if !str_eq(pulsar_compression_name(m.compression), "ZSTD") { ok = false; }
  if m.uncompressed_size != 5 { ok = false; }
  if m.event_time != 3 || !m.has_event_time { ok = false; }
  if m.deliver_at_time != 4 || !m.has_deliver_at_time { ok = false; }
  if m.unknown_fields != 1 { ok = false; }
  // Defaults.
  let md = pulsar_metadata_new();
  if md.has_producer_name || md.has_compression { ok = false; }
  if md.compression != pulsar_compression_none() { ok = false; }
  if pulsar_metadata_property_count(&md) != 0 { ok = false; }
  // Nested metadata field via pulsar_parse_metadata_at.
  var buf = Vec[UInt8].new();
  t_field_bytes(&mut buf, 50, &meta);
  let r2 = pulsar_parse_metadata_at(&buf, 0, 1);
  if !r2.is_ok {
    ok = false;
  } else {
    let mr: PulsarMetaRead = r2.value;
    if !str_eq(mr.metadata.producer_name, "p") { ok = false; }
    if mr.pos != buf.len() { ok = false; }
  }
  return assert(ok, "MessageMetadata decode: properties, optional fields, unknown count");
}

fn t21() -> TestResult {
  var ok = true;
  var body = Vec[UInt8].new();
  t_field_str(&mut body, 1, "c1");
  t_field_bytes(&mut body, 3, &hb("aabb"));
  t_field_varint(&mut body, 4, 17);
  var cmd = Vec[UInt8].new();
  t_command(&mut cmd, 2, &body);
  let r = pulsar_decode_base_command(&cmd);
  if !r.is_ok {
    return assert(false, "CONNECT with unknown field decodes");
  }
  let c: PulsarCommand = r.value;
  if !str_eq(c.client_version, "c1") { ok = false; }
  if c.protocol_version != 17 { ok = false; }
  if pulsar_command_unknown_fields(&c) != 1 { ok = false; }
  if c.unknown_bytes.len() == 0 { ok = false; }
  if !bytes_equal(c.raw, cmd) { ok = false; }
  return assert(ok, "unknown body fields counted and preserved raw");
}

fn t22() -> TestResult {
  var ok = true;
  // Truncated frame header.
  if !err_frame_is(pulsar_parse_frame(hb("010203")), "pulsar: truncated frame header at offset 3") { ok = false; }
  // total_size below 4.
  if !err_frame_is(pulsar_parse_frame(hb("0000000000000000")), "pulsar: bad total size at offset 0") { ok = false; }
  // Declared frame longer than the buffer.
  if !err_frame_is(pulsar_parse_frame(hb("0000000a000000040102")), "pulsar: truncated frame at offset 10") { ok = false; }
  // command_size larger than total_size - 4.
  if !err_frame_is(pulsar_parse_frame(hb("0000000400000001")), "pulsar: bad command size at offset 4") { ok = false; }
  // SEND frame with a metadata size larger than the remaining bytes.
  if !err_frame_is(pulsar_parse_frame(hb("0000000e0000000408063200000000050102")), "pulsar: bad metadata size at offset 12") { ok = false; }
  // SEND frame with 1-3 trailing bytes where the metadata size belongs.
  if !err_frame_is(pulsar_parse_frame(hb("0000000a00000004080632000102")), "pulsar: truncated metadata size at offset 14") { ok = false; }
  // Unknown command without a body field is accepted (known=false).
  var cmd = hb("084d");
  let fr = t_frame(&cmd, false, Vec[UInt8].new(), Vec[UInt8].new());
  let r = pulsar_parse_frame(&fr);
  if !r.is_ok {
    ok = false;
  } else {
    let f: PulsarFrame = r.value;
    if f.command.known { ok = false; }
    if f.command.cmd_type != 77 { ok = false; }
  }
  return assert(ok, "malformed frame lengths fail with byte-offset errors");
}

fn t23() -> TestResult {
  var ok = true;
  // Decode a hand-built CONNECT, re-encode it, and decode the re-encoded
  // bytes; both forms must be byte-identical and field-identical.
  var body = Vec[UInt8].new();
  t_field_str(&mut body, 1, "rt-client");
  t_field_varint(&mut body, 4, 19);
  t_field_str(&mut body, 5, "token");
  var cmd = Vec[UInt8].new();
  t_command(&mut cmd, 2, &body);
  let r = pulsar_decode_base_command(&cmd);
  if !r.is_ok {
    return assert(false, "round-trip source decodes");
  }
  let c: PulsarCommand = r.value;
  let er = pulsar_encode_command(&c);
  if !er.is_ok {
    ok = false;
  } else {
    let enc: Vec[UInt8] = er.value;
    if !bytes_equal(enc, cmd) { ok = false; }
    let r2 = pulsar_decode_base_command(&enc);
    if !r2.is_ok {
      ok = false;
    } else {
      let c2: PulsarCommand = r2.value;
      if !str_eq(c2.client_version, "rt-client") { ok = false; }
      if c2.protocol_version != 19 { ok = false; }
    }
  }
  // Metadata round-trip.
  var meta = Vec[UInt8].new();
  t_field_str(&mut meta, 1, "prod");
  t_field_varint(&mut meta, 2, 5);
  t_property(&mut meta, "kk", "vv");
  t_field_varint(&mut meta, 8, 2);
  let mr = pulsar_parse_metadata_body(&meta, 0, meta.len(), 1);
  if !mr.is_ok {
    ok = false;
  } else {
    let m: PulsarMessageMetadata = mr.value;
    let er2 = pulsar_encode_metadata(&m);
    if !er2.is_ok {
      ok = false;
    } else {
      let enc2: Vec[UInt8] = er2.value;
      if !bytes_equal(enc2, meta) { ok = false; }
    }
  }
  // MessageIdData round-trip (with an ack entry).
  var none = Vec[Int].new();
  var midbuf = Vec[UInt8].new();
  t_mid(&mut midbuf, 1, 4, 5, 6, 7, &none);
  let mir = pulsar_parse_message_id_at(&midbuf, 0, 1);
  if !mir.is_ok {
    ok = false;
  } else {
    let mread: PulsarMidRead = mir.value;
    let er3 = pulsar_encode_message_id_field(1, &mread.id);
    if !er3.is_ok {
      ok = false;
    } else {
      let enc3: Vec[UInt8] = er3.value;
      if !bytes_equal(enc3, midbuf) { ok = false; }
    }
    if mread.pos != midbuf.len() { ok = false; }
  }
  // Whole-frame round-trip through the library writer.
  let cr = pulsar_decode_base_command(&cmd);
  if cr.is_ok {
    let cc: PulsarCommand = cr.value;
    let ce = pulsar_encode_command(&cc);
    if !ce.is_ok {
      ok = false;
    } else {
      let cb: Vec[UInt8] = ce.value;
      let payload = bytes_of("hi");
      let fr = pulsar_encode_frame(&cb, false, Vec[UInt8].new(), &payload);
      let pr = pulsar_parse_frame(&fr);
      if !pr.is_ok {
        ok = false;
      } else {
        let pf: PulsarFrame = pr.value;
        if pf.command.cmd_type != 2 { ok = false; }
        if !str_eq(pf.command.client_version, "rt-client") { ok = false; }
        if !bytes_equal(pf.payload, payload) { ok = false; }
        if pulsar_frame_consumed(&pf) != fr.len() { ok = false; }
      }
    }
  }
  return assert(ok, "encode -> decode round-trips: command, metadata, message id, frame");
}

fn t24() -> TestResult {
  var ok = true;
  let body = hb("0801");
  if !err_mid_is(pulsar_parse_message_id_body(&body, 0, body.len(), 17), "pulsar: nesting depth exceeds limit of 16 at offset 0") { ok = false; }
  let okd = pulsar_parse_message_id_body(&body, 0, body.len(), 16);
  if !okd.is_ok { ok = false; }
  if !err_meta_is(pulsar_parse_metadata_body(&body, 0, body.len(), 100), "pulsar: nesting depth exceeds limit of 16 at offset 0") { ok = false; }
  if pulsar_max_depth() != 16 { ok = false; }
  return assert(ok, "nesting depth cap enforced on message id and metadata");
}

fn t25() -> TestResult {
  var ok = true;
  if pulsar_protocol_version() != 21 { ok = false; }
  if pulsar_cmd_connect() != 2 || pulsar_cmd_connected() != 3 { ok = false; }
  if pulsar_cmd_subscribe() != 4 || pulsar_cmd_producer() != 5 { ok = false; }
  if pulsar_cmd_send() != 6 || pulsar_cmd_send_receipt() != 7 { ok = false; }
  if pulsar_cmd_send_error() != 8 || pulsar_cmd_message() != 9 { ok = false; }
  if pulsar_cmd_ack() != 10 || pulsar_cmd_flow() != 11 { ok = false; }
  if pulsar_cmd_unsubscribe() != 12 || pulsar_cmd_success() != 13 { ok = false; }
  if pulsar_cmd_error() != 14 || pulsar_cmd_close_producer() != 15 { ok = false; }
  if pulsar_cmd_close_consumer() != 16 || pulsar_cmd_producer_success() != 17 { ok = false; }
  if pulsar_cmd_ping() != 18 || pulsar_cmd_pong() != 19 { ok = false; }
  if pulsar_cmd_partitioned_metadata() != 21 { ok = false; }
  if pulsar_cmd_partitioned_metadata_response() != 22 { ok = false; }
  if pulsar_cmd_lookup() != 23 || pulsar_cmd_lookup_response() != 24 { ok = false; }
  if pulsar_cmd_get_last_message_id() != 29 { ok = false; }
  if pulsar_cmd_get_topics_of_namespace() != 32 { ok = false; }
  if !str_eq(pulsar_cmd_type_name(6), "SEND") { ok = false; }
  if !str_eq(pulsar_cmd_type_name(20), "REDELIVER_UNACKNOWLEDGED_MESSAGES") { ok = false; }
  if !str_eq(pulsar_cmd_type_name(99), "UNKNOWN") { ok = false; }
  if !str_eq(pulsar_sub_type_name(0), "Exclusive") { ok = false; }
  if !str_eq(pulsar_sub_type_name(3), "Key_Shared") { ok = false; }
  if !str_eq(pulsar_ack_type_name(0), "Individual") { ok = false; }
  if !str_eq(pulsar_ack_type_name(2), "UNKNOWN") { ok = false; }
  if !str_eq(pulsar_compression_name(4), "SNAPPY") { ok = false; }
  if pulsar_cmd_type_known(77) { ok = false; }
  if !pulsar_cmd_type_known(9) { ok = false; }
  if pulsar_wire_varint() != 0 || pulsar_wire_fixed64() != 1 { ok = false; }
  if pulsar_wire_length_delimited() != 2 || pulsar_wire_fixed32() != 5 { ok = false; }
  return assert(ok, "command/compression/subscription/ack names and wire constants");
}

fn t26() -> TestResult {
  var ok = true;
  // CONNECT field 1 payload [0x41, 0x00]: the NUL sits at absolute offset 7.
  if !err_cmd_is(pulsar_decode_base_command(hb("080212040a024100")), "pulsar: string contains nul at offset 7") { ok = false; }
  // CONNECT field 1 payload [0xC3, 0x28]: invalid continuation at offset 6.
  if !err_cmd_is(pulsar_decode_base_command(hb("080212040a02c328")), "pulsar: invalid utf-8 at offset 6") { ok = false; }
  // A truncated 2-byte sequence at the end of the payload.
  if !err_cmd_is(pulsar_decode_base_command(hb("080212030a01c3")), "pulsar: invalid utf-8 at offset 6") { ok = false; }
  // Valid multi-byte UTF-8 decodes (café = 5 bytes).
  var body = Vec[UInt8].new();
  t_field_str(&mut body, 1, "café");
  var cmd = Vec[UInt8].new();
  t_command(&mut cmd, 2, &body);
  let r = pulsar_decode_base_command(&cmd);
  if !r.is_ok {
    ok = false;
  } else {
    let c: PulsarCommand = r.value;
    if c.client_version.len() != 5 { ok = false; }
  }
  // Encoder emits the canonical string field (key, length, bytes).
  if !bytes_equal(enc_ok(pulsar_encode_string_field(1, "ok")), hb("0a026f6b")) { ok = false; }
  if !err_bytes_is(pulsar_encode_varint(-1), "pulsar: negative varint value") { ok = false; }
  return assert(ok, "Str decoding rejects NUL and invalid UTF-8; encoder emits canonical fields");
}

fn t27() -> TestResult {
  var ok = true;
  var body1 = Vec[UInt8].new();
  t_field_varint(&mut body1, 1, 1);
  var cmd1 = Vec[UInt8].new();
  t_command(&mut cmd1, 13, &body1);
  let frame1 = t_frame(&cmd1, false, Vec[UInt8].new(), Vec[UInt8].new());
  var body2 = Vec[UInt8].new();
  t_field_varint(&mut body2, 1, 7);
  t_field_varint(&mut body2, 2, 5);
  t_field_str(&mut body2, 3, "t2");
  var cmd2 = Vec[UInt8].new();
  t_command(&mut cmd2, 14, &body2);
  var payload2 = Vec[UInt8].new();
  payload2.push(9 as UInt8);
  let frame2 = t_frame(&cmd2, false, Vec[UInt8].new(), &payload2);
  var stream = Vec[UInt8].new();
  push_bytes(&mut stream, &frame1);
  push_bytes(&mut stream, &frame2);
  let r1 = pulsar_parse_frame_at(&stream, 0);
  if !r1.is_ok {
    return assert(false, "first frame decodes");
  }
  let f1: PulsarFrame = r1.value;
  if pulsar_frame_consumed(&f1) != frame1.len() { ok = false; }
  if f1.command.cmd_type != 13 { ok = false; }
  if f1.command.request_id != 1 { ok = false; }
  let r2 = pulsar_parse_frame_at(&stream, pulsar_frame_consumed(&f1));
  if !r2.is_ok {
    ok = false;
  } else {
    let f2: PulsarFrame = r2.value;
    if f2.command.cmd_type != 14 { ok = false; }
    if f2.command.error_code != 5 { ok = false; }
    if !str_eq(f2.command.error_message, "t2") { ok = false; }
    if !bytes_equal(f2.payload, payload2) { ok = false; }
  }
  if !err_frame_is(pulsar_parse_frame_at(&stream, -1), "pulsar: negative frame offset") { ok = false; }
  return assert(ok, "parse-frame-at: consumed counts, sequential frames, negative offset");
}

fn main() -> Int {
  io.println("=== xiom.pulsar conformance tests ===");
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
  let r27 = t27();
  if r27.passed { io.println("  [PASS] " + r27.name); } else { io.println("  [FAIL] " + r27.name); failed = failed + 1; }
  if failed == 0 {
    io.println("xiom.pulsar: all tests passed");
  } else {
    io.println("xiom.pulsar: tests failed");
  }
  return failed;
}

