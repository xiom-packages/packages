// XIOM -- xiom.amqp conformance tests (21 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Covers the documented API end to end with synthetic byte buffers built
// in-test: the protocol header, the generic frame header (frame-end, short
// payload, oversized payload, trailing bytes), method frames for every
// class/method pair in the subset (pinned bytes plus encode -> parse ->
// encode round-trips), bit packing, shortstr/longstr bounds, recursive
// field tables and arrays with every supported field tag, content header
// frames with all 13 basic properties, body and heartbeat frames,
// malformed/truncated inputs and the value-tree navigation API.
//
// Str values are compared with str_compare (BUG 17 discipline), every Vec
// read is bound to a typed local, and Ok/Err are never constructed in test
// functions (only matched).

module amqp_tests
use xiom.io; use xiom.test;
use xiom.amqp;
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

// Encode result unwrapped to bytes ("" on Err, so the byte comparison
// fails); used only for inputs the test expects to succeed.
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

fn err_unit_is(r: Result[Unit, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_fh_is(r: Result[AmqpFrameHeader, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_mf_is(r: Result[AmqpMethodFrame, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_ch_is(r: Result[AmqpContentHeader, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_bf_is(r: Result[AmqpBodyFrame, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_hb_is(r: Result[AmqpHeartbeat, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_schema_is(r: Result[Vec[Int], Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

// --------------------------------------------------
//  Test-side tree builders
// --------------------------------------------------

fn a_octet(t: &mut AmqpTree, v: Int) { amqp_tree_push_octet(t, v); }
fn a_short(t: &mut AmqpTree, v: Int) { amqp_tree_push_short(t, v); }
fn a_long(t: &mut AmqpTree, v: Int) { amqp_tree_push_long(t, v); }
fn a_llong(t: &mut AmqpTree, v: Int) { amqp_tree_push_longlong(t, v); }
fn a_bit(t: &mut AmqpTree, v: Int) { amqp_tree_push_bit(t, v); }

fn a_shortstr(t: &mut AmqpTree, s: Str) {
  let b = bytes_of(s);
  amqp_tree_push_shortstr(t, &b);
}

fn a_longstr(t: &mut AmqpTree, s: Str) {
  let b = bytes_of(s);
  amqp_tree_push_longstr(t, &b);
}

fn a_table(t: &mut AmqpTree) { amqp_tree_begin_table(t); }
fn a_array(t: &mut AmqpTree) { amqp_tree_begin_array(t); }
fn a_end(t: &mut AmqpTree) { amqp_tree_end(t); }

fn f_bool(t: &mut AmqpTree, key: Str, v: Int) {
  let k = bytes_of(key);
  amqp_tree_push_field_bool(t, &k, v);
}

fn f_float(t: &mut AmqpTree, key: Str, bits: Int) {
  let k = bytes_of(key);
  amqp_tree_push_field_float(t, &k, bits);
}

fn f_short(t: &mut AmqpTree, key: Str, v: Int) {
  let k = bytes_of(key);
  amqp_tree_push_field_short(t, &k, v);
}

fn f_long(t: &mut AmqpTree, key: Str, v: Int) {
  let k = bytes_of(key);
  amqp_tree_push_field_long(t, &k, v);
}

fn f_llong(t: &mut AmqpTree, key: Str, v: Int) {
  let k = bytes_of(key);
  amqp_tree_push_field_longlong(t, &k, v);
}

fn f_dec(t: &mut AmqpTree, key: Str, scale: Int, v: Int) {
  let k = bytes_of(key);
  amqp_tree_push_field_decimal(t, &k, scale, v);
}

fn f_byte(t: &mut AmqpTree, key: Str, v: Int) {
  let k = bytes_of(key);
  amqp_tree_push_field_byte(t, &k, v);
}

fn f_ts(t: &mut AmqpTree, key: Str, v: Int) {
  let k = bytes_of(key);
  amqp_tree_push_field_timestamp(t, &k, v);
}

fn f_bytes(t: &mut AmqpTree, key: Str, s: Str) {
  let k = bytes_of(key);
  let v = bytes_of(s);
  amqp_tree_push_field_bytes(t, &k, &v);
}

fn f_void(t: &mut AmqpTree, key: Str) {
  let k = bytes_of(key);
  amqp_tree_push_field_void(t, &k);
}

fn f_tbl(t: &mut AmqpTree, key: Str) {
  let k = bytes_of(key);
  amqp_tree_begin_table_keyed(t, &k);
}

fn f_arr(t: &mut AmqpTree, key: Str) {
  let k = bytes_of(key);
  amqp_tree_begin_array_keyed(t, &k);
}

// Encode -> parse -> encode round-trip for a method frame. True when all
// three steps succeed and both byte streams are identical.
fn rt_method(cid: Int, mid: Int, args: AmqpTree) -> Bool {
  let f = AmqpMethodFrame{ channel: 1; class_id: cid; method_id: mid; args: args };
  let r1 = amqp_encode_method_frame(&f);
  if !r1.is_ok {
    return false;
  }
  let b1: Vec[UInt8] = r1.value;
  let r2 = amqp_parse_method_frame(&b1, amqp_default_frame_max());
  if !r2.is_ok {
    return false;
  }
  let f2: AmqpMethodFrame = r2.value;
  if f2.class_id != cid {
    return false;
  }
  if f2.method_id != mid {
    return false;
  }
  let r3 = amqp_encode_method_frame(&f2);
  if !r3.is_ok {
    return false;
  }
  let b2: Vec[UInt8] = r3.value;
  return bytes_equal(b1, b2);
}

// Encode -> parse -> encode round-trip for a content header frame.
fn rt_ch(h: AmqpContentHeader) -> Bool {
  let r1 = amqp_encode_content_header_frame(&h);
  if !r1.is_ok {
    return false;
  }
  let b1: Vec[UInt8] = r1.value;
  let r2 = amqp_parse_content_header_frame(&b1, amqp_default_frame_max());
  if !r2.is_ok {
    return false;
  }
  let h2: AmqpContentHeader = r2.value;
  let r3 = amqp_encode_content_header_frame(&h2);
  if !r3.is_ok {
    return false;
  }
  let b2: Vec[UInt8] = r3.value;
  return bytes_equal(b1, b2);
}

// A content header with no properties set.
fn empty_header() -> AmqpContentHeader {
  return AmqpContentHeader{
    channel: 1; class_id: 60; weight: 0; body_size: 0; flags: 0;
    content_type: Vec[UInt8].new(); content_encoding: Vec[UInt8].new();
    headers: amqp_tree_new(); delivery_mode: 0; priority: 0;
    correlation_id: Vec[UInt8].new(); reply_to: Vec[UInt8].new();
    expiration: Vec[UInt8].new(); message_id: Vec[UInt8].new();
    timestamp: 0; msg_type: Vec[UInt8].new(); user_id: Vec[UInt8].new();
    app_id: Vec[UInt8].new();
  };
}

// Schema argument count, or -1 for an unknown method.
fn schema_len(cid: Int, mid: Int) -> Int {
  let r = amqp_method_schema(cid, mid);
  if !r.is_ok {
    return -1;
  }
  let s: Vec[Int] = r.value;
  return s.len();
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  var ok = true;
  if !bytes_equal(amqp_encode_protocol_header(), hb("414d515000000901")) { ok = false; }
  let p1 = amqp_parse_protocol_header(&hb("414d515000000901"));
  if !p1.is_ok { ok = false; } else {
    let rev: Int = p1.value;
    if rev != 1 { ok = false; }
  }
  let p0 = amqp_parse_protocol_header(&hb("414d515000000900"));
  if !p0.is_ok { ok = false; } else {
    let rev0: Int = p0.value;
    if rev0 != 0 { ok = false; }
  }
  if !err_int_is(amqp_parse_protocol_header(&hb("414d5150")), "amqp: truncated protocol header") { ok = false; }
  if !err_int_is(amqp_parse_protocol_header(&hb("414d515100000901")), "amqp: bad protocol header") { ok = false; }
  if !err_int_is(amqp_parse_protocol_header(&hb("414d515000000801")), "amqp: bad protocol header") { ok = false; }
  if !err_int_is(amqp_parse_protocol_header(&hb("004d515000000901")), "amqp: bad protocol header") { ok = false; }
  if !err_int_is(amqp_parse_protocol_header(&hb("414d515000000902")), "amqp: bad protocol revision") { ok = false; }
  let e0 = amqp_encode_protocol_header_rev(0);
  if !e0.is_ok { ok = false; } else {
    let b0: Vec[UInt8] = e0.value;
    if !bytes_equal(b0, hb("414d515000000900")) { ok = false; }
  }
  let e1 = amqp_encode_protocol_header_rev(1);
  if !e1.is_ok { ok = false; } else {
    let b1: Vec[UInt8] = e1.value;
    if !bytes_equal(b1, amqp_encode_protocol_header()) { ok = false; }
  }
  if !err_bytes_is(amqp_encode_protocol_header_rev(2), "amqp: bad protocol revision") { ok = false; }
  if !err_bytes_is(amqp_encode_protocol_header_rev(-1), "amqp: bad protocol revision") { ok = false; }
  return assert(ok, "protocol header: pinned bytes, 0-9 revision, bad magic/version/revision");
}

fn t2() -> TestResult {
  var ok = true;
  let hb1 = hb("08000000000000ce");
  let h1 = amqp_parse_frame_header(&hb1, amqp_default_frame_max());
  if !h1.is_ok { ok = false; } else {
    let fh: AmqpFrameHeader = h1.value;
    if fh.frame_type != 8 { ok = false; }
    if fh.channel != 0 { ok = false; }
    if fh.payload_size != 0 { ok = false; }
    if fh.payload_start != 7 { ok = false; }
    if fh.frame_len != 8 { ok = false; }
  }
  let hb2 = hb("03000100000004deadbeefce");
  let h2 = amqp_parse_frame_header(&hb2, amqp_default_frame_max());
  if !h2.is_ok { ok = false; } else {
    let fh2: AmqpFrameHeader = h2.value;
    if fh2.frame_type != 3 { ok = false; }
    if fh2.channel != 1 { ok = false; }
    if fh2.payload_size != 4 { ok = false; }
    if fh2.frame_len != 12 { ok = false; }
  }
  if !err_fh_is(amqp_parse_frame_header(&hb("03000100000004deadbeefcf"), amqp_default_frame_max()), "amqp: bad frame end") { ok = false; }
  if !err_fh_is(amqp_parse_frame_header(&hb("03000100000004deadbeef"), amqp_default_frame_max()), "amqp: truncated frame") { ok = false; }
  if !err_fh_is(amqp_parse_frame_header(&hb("03000100000004deadbeefce00"), amqp_default_frame_max()), "amqp: trailing bytes") { ok = false; }
  if !err_fh_is(amqp_parse_frame_header(&hb("0400010000000000ce"), amqp_default_frame_max()), "amqp: bad frame type") { ok = false; }
  if !err_fh_is(amqp_parse_frame_header(&hb("03000100000009001122334455667788ce"), 8), "amqp: frame too large") { ok = false; }
  if !err_fh_is(amqp_parse_frame_header(&hb1, 7), "amqp: bad frame max") { ok = false; }
  if !err_fh_is(amqp_parse_frame_header(&hb("03000100000004deadbe"), amqp_default_frame_max()), "amqp: truncated frame") { ok = false; }
  return assert(ok, "frame header: pinned types/channels, bad end, short/oversized payload, trailing");
}

fn t3() -> TestResult {
  var ok = true;
  let b = hb("08000000000000ce");
  let r = amqp_parse_heartbeat_frame(&b, amqp_default_frame_max());
  if !r.is_ok { ok = false; } else {
    let h: AmqpHeartbeat = r.value;
    if h.channel != 0 { ok = false; }
  }
  let e = amqp_encode_heartbeat_frame(0);
  if !e.is_ok { ok = false; } else {
    let out: Vec[UInt8] = e.value;
    if !bytes_equal(out, b) { ok = false; }
  }
  if !err_hb_is(amqp_parse_heartbeat_frame(&hb("0800000000000100ce"), amqp_default_frame_max()), "amqp: bad heartbeat") { ok = false; }
  if !err_hb_is(amqp_parse_heartbeat_frame(&hb("08000100000000ce"), amqp_default_frame_max()), "amqp: bad heartbeat") { ok = false; }
  if !err_hb_is(amqp_parse_heartbeat_frame(&hb("03000100000000ce"), amqp_default_frame_max()), "amqp: bad frame type") { ok = false; }
  if !err_bytes_is(amqp_encode_heartbeat_frame(1), "amqp: bad heartbeat") { ok = false; }
  return assert(ok, "heartbeat frame: pinned bytes, non-zero payload/channel rejection");
}

fn t4() -> TestResult {
  var ok = true;
  let b = hb("03000100000004deadbeefce");
  let r = amqp_parse_body_frame(&b, amqp_default_frame_max());
  if !r.is_ok { ok = false; } else {
    let f: AmqpBodyFrame = r.value;
    if f.channel != 1 { ok = false; }
    let body: Vec[UInt8] = f.body;
    if !bytes_equal(body, hb("deadbeef")) { ok = false; }
    let e = amqp_encode_body_frame(&f);
    if !e.is_ok { ok = false; } else {
      let out: Vec[UInt8] = e.value;
      if !bytes_equal(out, b) { ok = false; }
    }
  }
  let be = hb("03000100000000ce");
  let re = amqp_parse_body_frame(&be, amqp_default_frame_max());
  if !re.is_ok { ok = false; } else {
    let fe: AmqpBodyFrame = re.value;
    let eb: Vec[UInt8] = fe.body;
    if eb.len() != 0 { ok = false; }
    let ee = amqp_encode_body_frame(&fe);
    if !ee.is_ok { ok = false; } else {
      let oue: Vec[UInt8] = ee.value;
      if !bytes_equal(oue, be) { ok = false; }
    }
  }
  let bx = hb("0300010000000400ceff01ce");
  let rx = amqp_parse_body_frame(&bx, amqp_default_frame_max());
  if !rx.is_ok { ok = false; } else {
    let fx: AmqpBodyFrame = rx.value;
    let bodyx: Vec[UInt8] = fx.body;
    if !bytes_equal(bodyx, hb("00ceff01")) { ok = false; }
  }
  if !err_bf_is(amqp_parse_body_frame(&hb("08000000000000ce"), amqp_default_frame_max()), "amqp: bad frame type") { ok = false; }
  let bad_ch = AmqpBodyFrame{ channel: 70000; body: hb("00") };
  if !err_bytes_is(amqp_encode_body_frame(&bad_ch), "amqp: bad channel") { ok = false; }
  return assert(ok, "body frame: pinned bytes, empty and binary payloads (0x00/0xCE), bad channel");
}

fn t5() -> TestResult {
  var ok = true;
  let b = hb("02000100000010003c0000000000000000000418000105ce");
  let r = amqp_parse_content_header_frame(&b, amqp_default_frame_max());
  if !r.is_ok { ok = false; } else {
    let h: AmqpContentHeader = r.value;
    if h.channel != 1 { ok = false; }
    if h.class_id != 60 { ok = false; }
    if h.weight != 0 { ok = false; }
    if h.body_size != 4 { ok = false; }
    if h.flags != 6144 { ok = false; }
    if h.delivery_mode != 1 { ok = false; }
    if h.priority != 5 { ok = false; }
    let ct: Vec[UInt8] = h.content_type;
    if ct.len() != 0 { ok = false; }
    let e = amqp_encode_content_header_frame(&h);
    if !e.is_ok { ok = false; } else {
      let out: Vec[UInt8] = e.value;
      if !bytes_equal(out, b) { ok = false; }
    }
  }
  var hdr = amqp_tree_new();
  a_table(&mut hdr);
  f_bool(&mut hdr, "k", 1);
  a_end(&mut hdr);
  var fl: Int = 0;
  fl = fl + amqp_basic_flag(0);
  fl = fl + amqp_basic_flag(1);
  fl = fl + amqp_basic_flag(2);
  fl = fl + amqp_basic_flag(3);
  fl = fl + amqp_basic_flag(4);
  fl = fl + amqp_basic_flag(5);
  fl = fl + amqp_basic_flag(6);
  fl = fl + amqp_basic_flag(7);
  fl = fl + amqp_basic_flag(8);
  fl = fl + amqp_basic_flag(9);
  fl = fl + amqp_basic_flag(10);
  fl = fl + amqp_basic_flag(11);
  fl = fl + amqp_basic_flag(12);
  let full = AmqpContentHeader{
    channel: 1; class_id: 60; weight: 0; body_size: 4096; flags: fl;
    content_type: bytes_of("application/json"); content_encoding: bytes_of("utf-8");
    headers: hdr; delivery_mode: 2; priority: 7;
    correlation_id: bytes_of("corr-1"); reply_to: bytes_of("reply.q");
    expiration: bytes_of("60000"); message_id: bytes_of("msg-1");
    timestamp: 1700000000; msg_type: bytes_of("event");
    user_id: bytes_of("guest"); app_id: bytes_of("tester");
  };
  let re = amqp_encode_content_header_frame(&full);
  if !re.is_ok { ok = false; } else {
    let bfull: Vec[UInt8] = re.value;
    let rr = amqp_parse_content_header_frame(&bfull, amqp_default_frame_max());
    if !rr.is_ok { ok = false; } else {
      let h2: AmqpContentHeader = rr.value;
      if h2.body_size != 4096 { ok = false; }
      if h2.delivery_mode != 2 { ok = false; }
      if h2.priority != 7 { ok = false; }
      if h2.timestamp != 1700000000 { ok = false; }
      let v0: Vec[UInt8] = h2.content_type;
      if !bytes_equal(v0, bytes_of("application/json")) { ok = false; }
      let v1: Vec[UInt8] = h2.content_encoding;
      if !bytes_equal(v1, bytes_of("utf-8")) { ok = false; }
      let v2: Vec[UInt8] = h2.correlation_id;
      if !bytes_equal(v2, bytes_of("corr-1")) { ok = false; }
      let v3: Vec[UInt8] = h2.reply_to;
      if !bytes_equal(v3, bytes_of("reply.q")) { ok = false; }
      let v4: Vec[UInt8] = h2.expiration;
      if !bytes_equal(v4, bytes_of("60000")) { ok = false; }
      let v5: Vec[UInt8] = h2.message_id;
      if !bytes_equal(v5, bytes_of("msg-1")) { ok = false; }
      let v6: Vec[UInt8] = h2.msg_type;
      if !bytes_equal(v6, bytes_of("event")) { ok = false; }
      let v7: Vec[UInt8] = h2.user_id;
      if !bytes_equal(v7, bytes_of("guest")) { ok = false; }
      let v8: Vec[UInt8] = h2.app_id;
      if !bytes_equal(v8, bytes_of("tester")) { ok = false; }
      let ht: AmqpTree = h2.headers;
      let kk = bytes_of("k");
      let nk = amqp_tree_find_key(&ht, 0, &kk);
      if amqp_tree_kind_at(&ht, nk) != amqp_kind_f_bool() { ok = false; }
      if amqp_tree_int_at(&ht, nk) != 1 { ok = false; }
    }
    if !rt_ch(full) { ok = false; }
  }
  var badc = empty_header();
  badc.class_id = 70;
  if !err_bytes_is(amqp_encode_content_header_frame(&badc), "amqp: bad content class") { ok = false; }
  var badw = empty_header();
  badw.weight = 1;
  if !err_bytes_is(amqp_encode_content_header_frame(&badw), "amqp: bad weight") { ok = false; }
  var badfl = empty_header();
  badfl.flags = 1;
  if !err_bytes_is(amqp_encode_content_header_frame(&badfl), "amqp: bad property flags") { ok = false; }
  var unflagged = empty_header();
  var unflag_tree = amqp_tree_new();
  a_table(&mut unflag_tree);
  f_bool(&mut unflag_tree, "k", 1);
  a_end(&mut unflag_tree);
  unflagged.headers = unflag_tree;
  if !err_bytes_is(amqp_encode_content_header_frame(&unflagged), "amqp: headers not flagged") { ok = false; }
  var badsz = empty_header();
  badsz.body_size = -1;
  if !err_bytes_is(amqp_encode_content_header_frame(&badsz), "amqp: value out of range") { ok = false; }
  var badch = empty_header();
  badch.channel = 70000;
  if !err_bytes_is(amqp_encode_content_header_frame(&badch), "amqp: bad channel") { ok = false; }
  if !err_ch_is(amqp_parse_content_header_frame(&hb("0200010000000E0046000000000000000000000000ce"), amqp_default_frame_max()), "amqp: bad content class") { ok = false; }
  if !err_ch_is(amqp_parse_content_header_frame(&hb("0200010000000E003c000100000000000000000000ce"), amqp_default_frame_max()), "amqp: bad weight") { ok = false; }
  if !err_ch_is(amqp_parse_content_header_frame(&hb("0200010000000E003c000000000000000000000001ce"), amqp_default_frame_max()), "amqp: bad property flags") { ok = false; }
  if !err_ch_is(amqp_parse_content_header_frame(&hb("0200010000000E003c000000000000000000000004ce"), amqp_default_frame_max()), "amqp: unsupported property") { ok = false; }
  if !err_ch_is(amqp_parse_content_header_frame(&hb("0200010000000E003c000000000000000000008000ce"), amqp_default_frame_max()), "amqp: truncated string") { ok = false; }
  if !err_ch_is(amqp_parse_content_header_frame(&hb("0200010000000F003c00000000000000000000000000ce"), amqp_default_frame_max()), "amqp: trailing bytes") { ok = false; }
  if !err_ch_is(amqp_parse_content_header_frame(&hb("02000100000012003c00000000000000000000000000000000ce"), amqp_default_frame_max()), "amqp: trailing bytes") { ok = false; }
  if !err_ch_is(amqp_parse_content_header_frame(&hb("0200010000000E003c0000ffffffffffffffff0000ce"), amqp_default_frame_max()), "amqp: integer out of range") { ok = false; }
  if !err_ch_is(amqp_parse_content_header_frame(&hb("0200010000000C003c00000000000000000000ce"), amqp_default_frame_max()), "amqp: truncated content header") { ok = false; }
  return assert(ok, "content header: pinned minimal frame, all 13 properties, header table, errors");
}

fn t6() -> TestResult {
  var ok = true;
  let b = hb("0100000000002C000a000a00090000001001786c0000000000000005026f6b740100000005504c41494e00000005656e5f5553ce");
  let r = amqp_parse_method_frame(&b, amqp_default_frame_max());
  if !r.is_ok { ok = false; } else {
    let f: AmqpMethodFrame = r.value;
    if f.channel != 0 { ok = false; }
    if f.class_id != 10 { ok = false; }
    if f.method_id != 10 { ok = false; }
    let a: AmqpTree = f.args;
    if amqp_tree_arg_count(&a) != 5 { ok = false; }
    if amqp_tree_kind_at(&a, 0) != amqp_argtype_octet() { ok = false; }
    if amqp_tree_int_at(&a, 0) != 0 { ok = false; }
    if amqp_tree_kind_at(&a, 1) != amqp_argtype_octet() { ok = false; }
    if amqp_tree_int_at(&a, 1) != 9 { ok = false; }
    let tn = amqp_tree_arg_node(&a, 2);
    if amqp_tree_kind_at(&a, tn) != amqp_argtype_table() { ok = false; }
    if amqp_tree_kid_count(&a, tn) != 2 { ok = false; }
    let kx = bytes_of("x");
    let nx = amqp_tree_find_key(&a, tn, &kx);
    if amqp_tree_kind_at(&a, nx) != amqp_kind_f_longlong() { ok = false; }
    if amqp_tree_int_at(&a, nx) != 5 { ok = false; }
    let kx2 = amqp_tree_key_at(&a, nx);
    if !bytes_equal(kx2, kx) { ok = false; }
    let kok = bytes_of("ok");
    let nok = amqp_tree_find_key(&a, tn, &kok);
    if amqp_tree_kind_at(&a, nok) != amqp_kind_f_bool() { ok = false; }
    if amqp_tree_int_at(&a, nok) != 1 { ok = false; }
    let m1 = amqp_tree_bytes_at(&a, amqp_tree_arg_node(&a, 3));
    if !bytes_equal(m1, bytes_of("PLAIN")) { ok = false; }
    let m2 = amqp_tree_bytes_at(&a, amqp_tree_arg_node(&a, 4));
    if !bytes_equal(m2, bytes_of("en_US")) { ok = false; }
    let e = amqp_encode_method_frame(&f);
    if !e.is_ok { ok = false; } else {
      let out: Vec[UInt8] = e.value;
      if !bytes_equal(out, b) { ok = false; }
    }
  }
  return assert(ok, "connection.start: pinned frame decode, table navigation, exact re-encode");
}

fn t7() -> TestResult {
  var ok = true;
  let tb = hb("0100000000000C000a001e07ff00020000003cce");
  let tr = amqp_parse_method_frame(&tb, amqp_default_frame_max());
  if !tr.is_ok { ok = false; } else {
    let f: AmqpMethodFrame = tr.value;
    if f.class_id != 10 { ok = false; }
    if f.method_id != 30 { ok = false; }
    let a: AmqpTree = f.args;
    if amqp_tree_arg_count(&a) != 3 { ok = false; }
    if amqp_tree_int_at(&a, amqp_tree_arg_node(&a, 0)) != 2047 { ok = false; }
    if amqp_tree_int_at(&a, amqp_tree_arg_node(&a, 1)) != 131072 { ok = false; }
    if amqp_tree_int_at(&a, amqp_tree_arg_node(&a, 2)) != 60 { ok = false; }
    let e = amqp_encode_method_frame(&f);
    if !e.is_ok { ok = false; } else {
      let out: Vec[UInt8] = e.value;
      if !bytes_equal(out, tb) { ok = false; }
    }
  }
  let cb = hb("0100000000000E000a003201400362796500000000ce");
  let cr = amqp_parse_method_frame(&cb, amqp_default_frame_max());
  if !cr.is_ok { ok = false; } else {
    let f: AmqpMethodFrame = cr.value;
    if f.class_id != 10 { ok = false; }
    if f.method_id != 50 { ok = false; }
    let a: AmqpTree = f.args;
    if amqp_tree_int_at(&a, amqp_tree_arg_node(&a, 0)) != 320 { ok = false; }
    let t0 = amqp_tree_bytes_at(&a, amqp_tree_arg_node(&a, 1));
    if !bytes_equal(t0, bytes_of("bye")) { ok = false; }
    let e = amqp_encode_method_frame(&f);
    if !e.is_ok { ok = false; } else {
      let out: Vec[UInt8] = e.value;
      if !bytes_equal(out, cb) { ok = false; }
    }
  }
  var t1 = amqp_tree_new();
  a_shortstr(&mut t1, "vh");
  a_shortstr(&mut t1, "");
  a_bit(&mut t1, 1);
  if !rt_method(10, 40, t1) { ok = false; }
  var t2 = amqp_tree_new();
  a_shortstr(&mut t2, "hosts");
  if !rt_method(10, 41, t2) { ok = false; }
  var t3 = amqp_tree_new();
  if !rt_method(10, 51, t3) { ok = false; }
  var t4 = amqp_tree_new();
  a_table(&mut t4);
  f_llong(&mut t4, "cap", 1);
  a_end(&mut t4);
  a_shortstr(&mut t4, "PLAIN");
  a_longstr(&mut t4, "response");
  a_shortstr(&mut t4, "en_US");
  if !rt_method(10, 11, t4) { ok = false; }
  var t5 = amqp_tree_new();
  a_short(&mut t5, 65535);
  a_long(&mut t5, 4294967295);
  a_short(&mut t5, 0);
  if !rt_method(10, 31, t5) { ok = false; }
  return assert(ok, "connection.tune/close pinned; open/start-ok/tune-ok/close-ok round-trips");
}

fn t8() -> TestResult {
  var ok = true;
  var t1 = amqp_tree_new();
  a_shortstr(&mut t1, "");
  if !rt_method(20, 10, t1) { ok = false; }
  var t2 = amqp_tree_new();
  a_longstr(&mut t2, "channel-id");
  if !rt_method(20, 11, t2) { ok = false; }
  var t3 = amqp_tree_new();
  a_short(&mut t3, 0);
  a_shortstr(&mut t3, "ok");
  a_short(&mut t3, 1);
  a_short(&mut t3, 2);
  if !rt_method(20, 40, t3) { ok = false; }
  var t4 = amqp_tree_new();
  if !rt_method(20, 41, t4) { ok = false; }
  return assert(ok, "channel.open/open-ok/close/close-ok: round-trip encode/decode");
}

fn t9() -> TestResult {
  var ok = true;
  let pb = hb("0100010000000B003c002800000002726b01ce");
  let pr = amqp_parse_method_frame(&pb, amqp_default_frame_max());
  if !pr.is_ok { ok = false; } else {
    let f: AmqpMethodFrame = pr.value;
    if f.class_id != 60 { ok = false; }
    if f.method_id != 40 { ok = false; }
    let a: AmqpTree = f.args;
    if amqp_tree_int_at(&a, amqp_tree_arg_node(&a, 3)) != 1 { ok = false; }
    if amqp_tree_int_at(&a, amqp_tree_arg_node(&a, 4)) != 0 { ok = false; }
    let rk = amqp_tree_bytes_at(&a, amqp_tree_arg_node(&a, 2));
    if !bytes_equal(rk, bytes_of("rk")) { ok = false; }
    let e = amqp_encode_method_frame(&f);
    if !e.is_ok { ok = false; } else {
      let out: Vec[UInt8] = e.value;
      if !bytes_equal(out, pb) { ok = false; }
    }
  }
  let pb2 = hb("0100010000000B003c002800000002726b03ce");
  let pr2 = amqp_parse_method_frame(&pb2, amqp_default_frame_max());
  if !pr2.is_ok { ok = false; } else {
    let f: AmqpMethodFrame = pr2.value;
    let a: AmqpTree = f.args;
    if amqp_tree_int_at(&a, amqp_tree_arg_node(&a, 3)) != 1 { ok = false; }
    if amqp_tree_int_at(&a, amqp_tree_arg_node(&a, 4)) != 1 { ok = false; }
    let e = amqp_encode_method_frame(&f);
    if !e.is_ok { ok = false; } else {
      let out: Vec[UInt8] = e.value;
      if !bytes_equal(out, pb2) { ok = false; }
    }
  }
  let ab = hb("0100010000000D003c0050000000000000000501ce");
  let ar = amqp_parse_method_frame(&ab, amqp_default_frame_max());
  if !ar.is_ok { ok = false; } else {
    let f: AmqpMethodFrame = ar.value;
    let a: AmqpTree = f.args;
    if amqp_tree_int_at(&a, amqp_tree_arg_node(&a, 0)) != 5 { ok = false; }
    if amqp_tree_int_at(&a, amqp_tree_arg_node(&a, 1)) != 1 { ok = false; }
    let e = amqp_encode_method_frame(&f);
    if !e.is_ok { ok = false; } else {
      let out: Vec[UInt8] = e.value;
      if !bytes_equal(out, ab) { ok = false; }
    }
  }
  var t1 = amqp_tree_new();
  a_long(&mut t1, 1024);
  a_short(&mut t1, 10);
  a_bit(&mut t1, 1);
  if !rt_method(60, 10, t1) { ok = false; }
  var t2 = amqp_tree_new();
  if !rt_method(60, 11, t2) { ok = false; }
  var t3 = amqp_tree_new();
  a_shortstr(&mut t3, "tag-1");
  a_llong(&mut t3, 7);
  a_bit(&mut t3, 1);
  a_shortstr(&mut t3, "ex");
  a_shortstr(&mut t3, "rk");
  if !rt_method(60, 60, t3) { ok = false; }
  var t4 = amqp_tree_new();
  a_short(&mut t4, 312);
  a_shortstr(&mut t4, "NO_ROUTE");
  a_shortstr(&mut t4, "ex");
  a_shortstr(&mut t4, "rk");
  if !rt_method(60, 50, t4) { ok = false; }
  var t5 = amqp_tree_new();
  a_llong(&mut t5, 9);
  a_bit(&mut t5, 1);
  a_bit(&mut t5, 1);
  if !rt_method(60, 120, t5) { ok = false; }
  var t6 = amqp_tree_new();
  a_short(&mut t6, 0);
  a_shortstr(&mut t6, "ex");
  a_shortstr(&mut t6, "rk");
  a_bit(&mut t6, 1);
  a_bit(&mut t6, 1);
  if !rt_method(60, 40, t6) { ok = false; }
  return assert(ok, "basic.publish/ack pinned bits; qos/deliver/return/nack round-trips");
}

fn t10() -> TestResult {
  var ok = true;
  let qb = hb("0100010000000D0032000A000001711D00000000ce");
  let qr = amqp_parse_method_frame(&qb, amqp_default_frame_max());
  if !qr.is_ok { ok = false; } else {
    let f: AmqpMethodFrame = qr.value;
    if f.class_id != 50 { ok = false; }
    if f.method_id != 10 { ok = false; }
    let a: AmqpTree = f.args;
    if amqp_tree_int_at(&a, amqp_tree_arg_node(&a, 2)) != 1 { ok = false; }
    if amqp_tree_int_at(&a, amqp_tree_arg_node(&a, 3)) != 0 { ok = false; }
    if amqp_tree_int_at(&a, amqp_tree_arg_node(&a, 4)) != 1 { ok = false; }
    if amqp_tree_int_at(&a, amqp_tree_arg_node(&a, 5)) != 1 { ok = false; }
    if amqp_tree_int_at(&a, amqp_tree_arg_node(&a, 6)) != 1 { ok = false; }
    let tn = amqp_tree_arg_node(&a, 7);
    if amqp_tree_kind_at(&a, tn) != amqp_argtype_table() { ok = false; }
    if amqp_tree_kid_count(&a, tn) != 0 { ok = false; }
    let e = amqp_encode_method_frame(&f);
    if !e.is_ok { ok = false; } else {
      let out: Vec[UInt8] = e.value;
      if !bytes_equal(out, qb) { ok = false; }
    }
  }
  var t1 = amqp_tree_new();
  a_shortstr(&mut t1, "q");
  a_long(&mut t1, 3);
  a_long(&mut t1, 4);
  if !rt_method(50, 11, t1) { ok = false; }
  var t2 = amqp_tree_new();
  a_short(&mut t2, 0);
  a_shortstr(&mut t2, "q");
  a_shortstr(&mut t2, "ex");
  a_shortstr(&mut t2, "rk");
  a_bit(&mut t2, 0);
  a_table(&mut t2);
  f_bool(&mut t2, "nx", 1);
  a_end(&mut t2);
  if !rt_method(50, 20, t2) { ok = false; }
  var t3 = amqp_tree_new();
  a_short(&mut t3, 0);
  a_shortstr(&mut t3, "q");
  a_shortstr(&mut t3, "ex");
  a_shortstr(&mut t3, "rk");
  a_table(&mut t3);
  a_end(&mut t3);
  if !rt_method(50, 50, t3) { ok = false; }
  var t4 = amqp_tree_new();
  a_short(&mut t4, 0);
  a_shortstr(&mut t4, "q");
  a_bit(&mut t4, 1);
  if !rt_method(50, 30, t4) { ok = false; }
  var t5 = amqp_tree_new();
  a_long(&mut t5, 9);
  if !rt_method(50, 31, t5) { ok = false; }
  var t6 = amqp_tree_new();
  a_short(&mut t6, 0);
  a_shortstr(&mut t6, "q");
  a_bit(&mut t6, 1);
  a_bit(&mut t6, 0);
  a_bit(&mut t6, 1);
  if !rt_method(50, 40, t6) { ok = false; }
  var t7 = amqp_tree_new();
  a_long(&mut t7, 2);
  if !rt_method(50, 41, t7) { ok = false; }
  return assert(ok, "queue.declare pinned bits; declare-ok/bind/unbind/purge/delete round-trips");
}

fn t11() -> TestResult {
  var ok = true;
  var t1 = amqp_tree_new();
  a_short(&mut t1, 0);
  a_shortstr(&mut t1, "ex");
  a_shortstr(&mut t1, "topic");
  a_bit(&mut t1, 0);
  a_bit(&mut t1, 1);
  a_bit(&mut t1, 0);
  a_bit(&mut t1, 0);
  a_bit(&mut t1, 0);
  a_table(&mut t1);
  a_end(&mut t1);
  if !rt_method(40, 10, t1) { ok = false; }
  var t2 = amqp_tree_new();
  a_short(&mut t2, 0);
  a_shortstr(&mut t2, "ex");
  a_bit(&mut t2, 1);
  a_bit(&mut t2, 0);
  if !rt_method(40, 20, t2) { ok = false; }
  var t3 = amqp_tree_new();
  a_short(&mut t3, 0);
  a_shortstr(&mut t3, "dst");
  a_shortstr(&mut t3, "src");
  a_shortstr(&mut t3, "rk");
  a_bit(&mut t3, 1);
  a_table(&mut t3);
  f_ts(&mut t3, "when", 1700000000);
  a_end(&mut t3);
  if !rt_method(40, 30, t3) { ok = false; }
  var t4 = amqp_tree_new();
  a_short(&mut t4, 0);
  a_shortstr(&mut t4, "dst");
  a_shortstr(&mut t4, "src");
  a_shortstr(&mut t4, "rk");
  a_bit(&mut t4, 1);
  a_table(&mut t4);
  a_end(&mut t4);
  if !rt_method(40, 40, t4) { ok = false; }
  // Bits are LSB-first: 0,1,0,0,0 packs to 0x02.
  let eb = hb("010001000000140028000a000002657805746f7069630200000000ce");
  let er = amqp_parse_method_frame(&eb, amqp_default_frame_max());
  if !er.is_ok { ok = false; } else {
    let f: AmqpMethodFrame = er.value;
    let a: AmqpTree = f.args;
    if amqp_tree_int_at(&a, amqp_tree_arg_node(&a, 3)) != 0 { ok = false; }
    if amqp_tree_int_at(&a, amqp_tree_arg_node(&a, 4)) != 1 { ok = false; }
    if amqp_tree_int_at(&a, amqp_tree_arg_node(&a, 5)) != 0 { ok = false; }
    if amqp_tree_int_at(&a, amqp_tree_arg_node(&a, 6)) != 0 { ok = false; }
    if amqp_tree_int_at(&a, amqp_tree_arg_node(&a, 7)) != 0 { ok = false; }
  }
  return assert(ok, "exchange.declare/delete/bind/unbind round-trips and LSB-first bit order");
}

fn t12() -> TestResult {
  var ok = true;
  let b = hb("0100010000000D0032000A000001711D00000000ce");
  let r = amqp_parse_method_frame(&b, amqp_default_frame_max());
  if !r.is_ok { ok = false; } else {
    let f: AmqpMethodFrame = r.value;
    let a: AmqpTree = f.args;
    if amqp_tree_kind_at(&a, amqp_tree_arg_node(&a, 2)) != amqp_argtype_bit() { ok = false; }
    if amqp_tree_int_at(&a, amqp_tree_arg_node(&a, 2)) != 1 { ok = false; }
    if amqp_tree_int_at(&a, amqp_tree_arg_node(&a, 3)) != 0 { ok = false; }
    if amqp_tree_int_at(&a, amqp_tree_arg_node(&a, 4)) != 1 { ok = false; }
    if amqp_tree_int_at(&a, amqp_tree_arg_node(&a, 5)) != 1 { ok = false; }
    if amqp_tree_int_at(&a, amqp_tree_arg_node(&a, 6)) != 1 { ok = false; }
  }
  var bt = amqp_tree_new();
  a_short(&mut bt, 0);
  a_shortstr(&mut bt, "");
  a_shortstr(&mut bt, "rk");
  a_bit(&mut bt, 1);
  a_bit(&mut bt, 2);
  let bad = AmqpMethodFrame{ channel: 1; class_id: 60; method_id: 40; args: bt };
  if !err_bytes_is(amqp_encode_method_frame(&bad), "amqp: bad bit") { ok = false; }
  var ct = amqp_tree_new();
  a_short(&mut ct, 0);
  a_shortstr(&mut ct, "");
  let cnt = AmqpMethodFrame{ channel: 1; class_id: 60; method_id: 40; args: ct };
  if !err_bytes_is(amqp_encode_method_frame(&cnt), "amqp: bad argument count") { ok = false; }
  var kt = amqp_tree_new();
  a_long(&mut kt, 0);
  a_short(&mut kt, 0);
  a_short(&mut kt, 0);
  let kind = AmqpMethodFrame{ channel: 1; class_id: 10; method_id: 30; args: kt };
  if !err_bytes_is(amqp_encode_method_frame(&kind), "amqp: bad argument kind") { ok = false; }
  var vt = amqp_tree_new();
  a_octet(&mut vt, 256);
  a_octet(&mut vt, 9);
  a_table(&mut vt);
  a_end(&mut vt);
  a_longstr(&mut vt, "");
  a_longstr(&mut vt, "");
  let val = AmqpMethodFrame{ channel: 0; class_id: 10; method_id: 10; args: vt };
  if !err_bytes_is(amqp_encode_method_frame(&val), "amqp: value out of range") { ok = false; }
  return assert(ok, "bit packing pinned; bad bit/argument count/kind/value-range encode errors");
}

fn t13() -> TestResult {
  var ok = true;
  // connection.open with a shortstr that claims 5 bytes but carries 2.
  if !err_mf_is(amqp_parse_method_frame(&hb("01000000000008000a002805616201ce"), amqp_default_frame_max()), "amqp: truncated string") { ok = false; }
  // connection.start-ok with a longstr that claims 4 bytes but carries 2.
  if !err_mf_is(amqp_parse_method_frame(&hb("01000000000010000a000b00000000016d000000046162ce"), amqp_default_frame_max()), "amqp: truncated string") { ok = false; }
  // Encoding a shortstr over 255 bytes fails.
  var big = Vec[UInt8].new();
  var i = 0;
  while i < 256 {
    big.push(97 as UInt8);
    i = i + 1;
  }
  var t1 = amqp_tree_new();
  let big_loc = msg_join(&big);
  amqp_tree_push_shortstr(&mut t1, &big);
  amqp_tree_push_shortstr(&mut t1, &big_loc);
  a_bit(&mut t1, 0);
  let f1 = AmqpMethodFrame{ channel: 0; class_id: 10; method_id: 40; args: t1 };
  if !err_bytes_is(amqp_encode_method_frame(&f1), "amqp: string too long") { ok = false; }
  // A 300-byte longstr round-trips exactly.
  var big2 = Vec[UInt8].new();
  i = 0;
  while i < 300 {
    big2.push((i % 256) as UInt8);
    i = i + 1;
  }
  var t2 = amqp_tree_new();
  a_table(&mut t2);
  a_end(&mut t2);
  let mech = bytes_of("PLAIN");
  amqp_tree_push_shortstr(&mut t2, &mech);
  amqp_tree_push_longstr(&mut t2, &big2);
  let loc = bytes_of("en_US");
  amqp_tree_push_shortstr(&mut t2, &loc);
  let f2 = AmqpMethodFrame{ channel: 0; class_id: 10; method_id: 11; args: t2 };
  let r2 = amqp_encode_method_frame(&f2);
  if !r2.is_ok { ok = false; } else {
    let b2: Vec[UInt8] = r2.value;
    let pr = amqp_parse_method_frame(&b2, amqp_default_frame_max());
    if !pr.is_ok { ok = false; } else {
      let f2b: AmqpMethodFrame = pr.value;
      let a2: AmqpTree = f2b.args;
      let got = amqp_tree_bytes_at(&a2, amqp_tree_arg_node(&a2, 2));
      if !bytes_equal(got, big2) { ok = false; }
      let e2 = amqp_encode_method_frame(&f2b);
      if !e2.is_ok { ok = false; } else {
        let ob: Vec[UInt8] = e2.value;
        if !bytes_equal(ob, b2) { ok = false; }
      }
    }
  }
  // A table key over 255 bytes fails on encode.
  var t3 = amqp_tree_new();
  a_table(&mut t3);
  let longkey = msg_join(&big);
  amqp_tree_push_field_void(&mut t3, &longkey);
  a_end(&mut t3);
  a_shortstr(&mut t3, "PLAIN");
  a_longstr(&mut t3, "");
  a_shortstr(&mut t3, "");
  let f3 = AmqpMethodFrame{ channel: 0; class_id: 10; method_id: 11; args: t3 };
  if !err_bytes_is(amqp_encode_method_frame(&f3), "amqp: string too long") { ok = false; }
  return assert(ok, "shortstr/longstr bounds: truncated decode, >255 encode, 300-byte round-trip");
}

// Placeholder helper kept trivial: returns its input (used to exercise a
// second binding path for the same buffer in t13).
fn msg_join(v: &Vec[UInt8]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < v.len() {
    out.push(v[i]);
    i = i + 1;
  }
  return out;
}

fn t14() -> TestResult {
  var ok = true;
  var t = amqp_tree_new();
  a_table(&mut t);
  f_bool(&mut t, "b1", 1);
  f_float(&mut t, "f1", 1065353216);
  f_short(&mut t, "s1", -1234);
  f_long(&mut t, "i1", -123456789);
  f_llong(&mut t, "l1", -1234567890123);
  f_dec(&mut t, "d1", 2, -9999);
  f_byte(&mut t, "y1", -7);
  f_ts(&mut t, "t1", 1234567890);
  f_bytes(&mut t, "x1", "raw");
  f_void(&mut t, "v1");
  f_tbl(&mut t, "tbl");
  f_long(&mut t, "deep", 42);
  a_end(&mut t);
  f_arr(&mut t, "arr");
  let none = bytes_of("");
  amqp_tree_push_field_long(&mut t, &none, 1);
  amqp_tree_push_field_bool(&mut t, &none, 0);
  a_end(&mut t);
  a_end(&mut t);
  a_shortstr(&mut t, "PLAIN");
  a_longstr(&mut t, "resp");
  a_shortstr(&mut t, "en_US");
  let f = AmqpMethodFrame{ channel: 0; class_id: 10; method_id: 11; args: t };
  let r1 = amqp_encode_method_frame(&f);
  if !r1.is_ok { ok = false; } else {
    let b1: Vec[UInt8] = r1.value;
    let r2 = amqp_parse_method_frame(&b1, amqp_default_frame_max());
    if !r2.is_ok { ok = false; } else {
      let f2: AmqpMethodFrame = r2.value;
      let a: AmqpTree = f2.args;
      let tn = amqp_tree_arg_node(&a, 0);
      if amqp_tree_kid_count(&a, tn) != 12 { ok = false; }
      let kb = bytes_of("b1");
      if amqp_tree_kind_at(&a, amqp_tree_find_key(&a, tn, &kb)) != amqp_kind_f_bool() { ok = false; }
      let kf = bytes_of("f1");
      let nf = amqp_tree_find_key(&a, tn, &kf);
      if amqp_tree_kind_at(&a, nf) != amqp_kind_f_float() { ok = false; }
      if amqp_tree_int_at(&a, nf) != 1065353216 { ok = false; }
      let ks = bytes_of("s1");
      let ns = amqp_tree_find_key(&a, tn, &ks);
      if amqp_tree_kind_at(&a, ns) != amqp_kind_f_short() { ok = false; }
      if amqp_tree_int_at(&a, ns) != -1234 { ok = false; }
      let ki = bytes_of("i1");
      let ni = amqp_tree_find_key(&a, tn, &ki);
      if amqp_tree_kind_at(&a, ni) != amqp_kind_f_long() { ok = false; }
      if amqp_tree_int_at(&a, ni) != -123456789 { ok = false; }
      let kl = bytes_of("l1");
      let nl = amqp_tree_find_key(&a, tn, &kl);
      if amqp_tree_kind_at(&a, nl) != amqp_kind_f_longlong() { ok = false; }
      if amqp_tree_int_at(&a, nl) != -1234567890123 { ok = false; }
      let kd = bytes_of("d1");
      let nd = amqp_tree_find_key(&a, tn, &kd);
      if amqp_tree_kind_at(&a, nd) != amqp_kind_f_decimal() { ok = false; }
      if amqp_tree_int_at(&a, nd) != -9999 { ok = false; }
      if amqp_tree_aux_at(&a, nd) != 2 { ok = false; }
      let ky = bytes_of("y1");
      let ny = amqp_tree_find_key(&a, tn, &ky);
      if amqp_tree_kind_at(&a, ny) != amqp_kind_f_byte() { ok = false; }
      if amqp_tree_int_at(&a, ny) != -7 { ok = false; }
      let kt = bytes_of("t1");
      let nt = amqp_tree_find_key(&a, tn, &kt);
      if amqp_tree_kind_at(&a, nt) != amqp_kind_f_timestamp() { ok = false; }
      if amqp_tree_int_at(&a, nt) != 1234567890 { ok = false; }
      let kx = bytes_of("x1");
      let nx = amqp_tree_find_key(&a, tn, &kx);
      if amqp_tree_kind_at(&a, nx) != amqp_kind_f_bytes() { ok = false; }
      let xb = amqp_tree_bytes_at(&a, nx);
      if !bytes_equal(xb, bytes_of("raw")) { ok = false; }
      let kv = bytes_of("v1");
      let nv = amqp_tree_find_key(&a, tn, &kv);
      if amqp_tree_kind_at(&a, nv) != amqp_kind_f_void() { ok = false; }
      let ktb = bytes_of("tbl");
      let ntb = amqp_tree_find_key(&a, tn, &ktb);
      if amqp_tree_kind_at(&a, ntb) != amqp_argtype_table() { ok = false; }
      let kdeep = bytes_of("deep");
      if amqp_tree_int_at(&a, amqp_tree_find_key(&a, ntb, &kdeep)) != 42 { ok = false; }
      let ka = bytes_of("arr");
      let na = amqp_tree_find_key(&a, tn, &ka);
      if amqp_tree_kind_at(&a, na) != amqp_argtype_array() { ok = false; }
      if amqp_tree_kid_count(&a, na) != 2 { ok = false; }
      let kz = bytes_of("");
      if amqp_tree_int_at(&a, amqp_tree_find_key(&a, na, &kz)) != 1 { ok = false; }
      let e2 = amqp_encode_method_frame(&f2);
      if !e2.is_ok { ok = false; } else {
        let ob: Vec[UInt8] = e2.value;
        if !bytes_equal(ob, b1) { ok = false; }
      }
    }
  }
  return assert(ok, "field table: all 12 supported tags, nested table/array, round-trip");
}

fn t15() -> TestResult {
  var ok = true;
  var t = amqp_tree_new();
  a_table(&mut t);
  f_tbl(&mut t, "a");
  f_tbl(&mut t, "b");
  f_tbl(&mut t, "c");
  f_long(&mut t, "leaf", 7);
  a_end(&mut t);
  a_end(&mut t);
  a_end(&mut t);
  f_long(&mut t, "z", 9);
  a_end(&mut t);
  a_shortstr(&mut t, "");
  a_longstr(&mut t, "");
  a_shortstr(&mut t, "");
  let f = AmqpMethodFrame{ channel: 0; class_id: 10; method_id: 11; args: t };
  let r1 = amqp_encode_method_frame(&f);
  if !r1.is_ok { ok = false; } else {
    let b1: Vec[UInt8] = r1.value;
    let r2 = amqp_parse_method_frame(&b1, amqp_default_frame_max());
    if !r2.is_ok { ok = false; } else {
      let f2: AmqpMethodFrame = r2.value;
      let a: AmqpTree = f2.args;
      let root = amqp_tree_arg_node(&a, 0);
      if amqp_tree_kid_count(&a, root) != 2 { ok = false; }
      let ka = bytes_of("a");
      let na = amqp_tree_find_key(&a, root, &ka);
      if amqp_tree_kid_count(&a, na) != 1 { ok = false; }
      let kb = bytes_of("b");
      let nb = amqp_tree_find_key(&a, na, &kb);
      if amqp_tree_kid_count(&a, nb) != 1 { ok = false; }
      let kc = bytes_of("c");
      let nc = amqp_tree_find_key(&a, nb, &kc);
      if amqp_tree_kid_count(&a, nc) != 1 { ok = false; }
      let kleaf = bytes_of("leaf");
      let nleaf = amqp_tree_find_key(&a, nc, &kleaf);
      if amqp_tree_kind_at(&a, nleaf) != amqp_kind_f_long() { ok = false; }
      if amqp_tree_int_at(&a, nleaf) != 7 { ok = false; }
      let kbk = amqp_tree_key_at(&a, amqp_tree_kid_node(&a, root, 0));
      if !bytes_equal(kbk, bytes_of("a")) { ok = false; }
      let kz = bytes_of("z");
      let nz = amqp_tree_find_key(&a, root, &kz);
      if amqp_tree_int_at(&a, nz) != 9 { ok = false; }
      let knope = bytes_of("nope");
      if amqp_tree_find_key(&a, root, &knope) != -1 { ok = false; }
      let e2 = amqp_encode_method_frame(&f2);
      if !e2.is_ok { ok = false; } else {
        let ob: Vec[UInt8] = e2.value;
        if !bytes_equal(ob, b1) { ok = false; }
      }
    }
  }
  return assert(ok, "field table recursion: 3 levels, kid_count/kid_node/find_key, round-trip");
}

fn t16() -> TestResult {
  var ok = true;
  if !err_mf_is(amqp_parse_method_frame(&hb("01000000000008000a000b00000064ce"), amqp_default_frame_max()), "amqp: bad table") { ok = false; }
  if !err_mf_is(amqp_parse_method_frame(&hb("0100000000000B000a000b00000003016b51ce"), amqp_default_frame_max()), "amqp: bad field tag") { ok = false; }
  if !err_mf_is(amqp_parse_method_frame(&hb("0100000000000C000a000b00000004016b7402ce"), amqp_default_frame_max()), "amqp: bad bool") { ok = false; }
  if !err_mf_is(amqp_parse_method_frame(&hb("0100000000000F000a000b0000000701614100000009ce"), amqp_default_frame_max()), "amqp: bad array") { ok = false; }
  if !err_mf_is(amqp_parse_method_frame(&hb("01000000000013000a000b0000000b017454ffffffffffffffffce"), amqp_default_frame_max()), "amqp: integer out of range") { ok = false; }
  // 33 nested tables exceed the depth limit of 32 (encoded without a limit).
  var t = amqp_tree_new();
  a_table(&mut t);
  var i = 0;
  while i < 33 {
    f_tbl(&mut t, "k");
    i = i + 1;
  }
  f_long(&mut t, "leaf", 1);
  i = 0;
  while i < 33 {
    a_end(&mut t);
    i = i + 1;
  }
  a_end(&mut t);
  a_shortstr(&mut t, "");
  a_longstr(&mut t, "");
  a_shortstr(&mut t, "");
  let f = AmqpMethodFrame{ channel: 0; class_id: 10; method_id: 11; args: t };
  let r1 = amqp_encode_method_frame(&f);
  if !r1.is_ok { ok = false; } else {
    let b1: Vec[UInt8] = r1.value;
    if !err_mf_is(amqp_parse_method_frame(&b1, amqp_default_frame_max()), "amqp: table nesting too deep") { ok = false; }
  }
  return assert(ok, "malformed tables: overrun, bad tag, bad bool, bad array, deep nesting");
}

fn t17() -> TestResult {
  var ok = true;
  if !err_schema_is(amqp_method_schema(99, 1), "amqp: unknown method") { ok = false; }
  if !err_schema_is(amqp_method_schema(10, 99), "amqp: unknown method") { ok = false; }
  if !err_schema_is(amqp_method_schema(-1, 0), "amqp: unknown method") { ok = false; }
  if !err_mf_is(amqp_parse_method_frame(&hb("0100000000000400630001ce"), amqp_default_frame_max()), "amqp: unknown method") { ok = false; }
  if !err_mf_is(amqp_parse_method_frame(&hb("01000000000003000a00ce"), amqp_default_frame_max()), "amqp: truncated method") { ok = false; }
  var t1 = amqp_tree_new();
  let empty_f = AmqpMethodFrame{ channel: 1; class_id: 99; method_id: 1; args: t1 };
  if !err_bytes_is(amqp_encode_method_frame(&empty_f), "amqp: unknown method") { ok = false; }
  var t2 = amqp_tree_new();
  a_octet(&mut t2, 0);
  let bad_class = AmqpMethodFrame{ channel: 1; class_id: 70000; method_id: 1; args: t2 };
  if !err_bytes_is(amqp_encode_method_frame(&bad_class), "amqp: bad class id") { ok = false; }
  var t3 = amqp_tree_new();
  let bad_mid = AmqpMethodFrame{ channel: 1; class_id: 10; method_id: -1; args: t3 };
  if !err_bytes_is(amqp_encode_method_frame(&bad_mid), "amqp: bad method id") { ok = false; }
  var t4 = amqp_tree_new();
  a_short(&mut t4, 0);
  let bad_ch = AmqpMethodFrame{ channel: 70000; class_id: 10; method_id: 30; args: t4 };
  if !err_bytes_is(amqp_encode_method_frame(&bad_ch), "amqp: bad channel") { ok = false; }
  // Trailing bytes after a complete method payload.
  let good = hb("0100010000000D003c0050000000000000000501ce");
  var extra = Vec[UInt8].new();
  var i = 0;
  while i < good.len() {
    extra.push(good[i]);
    i = i + 1;
  }
  extra.push(0 as UInt8);
  if !err_mf_is(amqp_parse_method_frame(&extra, amqp_default_frame_max()), "amqp: trailing bytes") { ok = false; }
  return assert(ok, "unknown methods, bad class/method/channel ids, truncated method, trailing bytes");
}

fn t18() -> TestResult {
  var ok = true;
  var t1 = amqp_tree_new();
  a_llong(&mut t1, 4611686018427387904);
  a_bit(&mut t1, 1);
  let f1 = AmqpMethodFrame{ channel: 1; class_id: 60; method_id: 80; args: t1 };
  let r1 = amqp_encode_method_frame(&f1);
  if !r1.is_ok { ok = false; } else {
    let b1: Vec[UInt8] = r1.value;
    let p1 = amqp_parse_method_frame(&b1, amqp_default_frame_max());
    if !p1.is_ok { ok = false; } else {
      let f1b: AmqpMethodFrame = p1.value;
      let a1: AmqpTree = f1b.args;
      if amqp_tree_int_at(&a1, amqp_tree_arg_node(&a1, 0)) != 4611686018427387904 { ok = false; }
    }
  }
  var h = empty_header();
  h.body_size = 1099511627776;
  h.timestamp = 1099511627776;
  h.flags = amqp_basic_flag(6);
  if !rt_ch(h) { ok = false; }
  var t2 = amqp_tree_new();
  a_table(&mut t2);
  f_llong(&mut t2, "neg", -1);
  f_long(&mut t2, "min", -2147483648);
  f_short(&mut t2, "smin", -32768);
  f_byte(&mut t2, "bmin", -128);
  f_dec(&mut t2, "dmax", 255, -1);
  f_llong(&mut t2, "lmax", 9223372036854775807);
  a_end(&mut t2);
  a_shortstr(&mut t2, "");
  a_longstr(&mut t2, "");
  a_shortstr(&mut t2, "");
  let f2 = AmqpMethodFrame{ channel: 0; class_id: 10; method_id: 11; args: t2 };
  let r2 = amqp_encode_method_frame(&f2);
  if !r2.is_ok { ok = false; } else {
    let b2: Vec[UInt8] = r2.value;
    let p2 = amqp_parse_method_frame(&b2, amqp_default_frame_max());
    if !p2.is_ok { ok = false; } else {
      let f2b: AmqpMethodFrame = p2.value;
      let a2: AmqpTree = f2b.args;
      let tn = amqp_tree_arg_node(&a2, 0);
      let kn = bytes_of("neg");
      if amqp_tree_int_at(&a2, amqp_tree_find_key(&a2, tn, &kn)) != -1 { ok = false; }
      let km = bytes_of("min");
      if amqp_tree_int_at(&a2, amqp_tree_find_key(&a2, tn, &km)) != -2147483648 { ok = false; }
      let ksm = bytes_of("smin");
      if amqp_tree_int_at(&a2, amqp_tree_find_key(&a2, tn, &ksm)) != -32768 { ok = false; }
      let kbm = bytes_of("bmin");
      if amqp_tree_int_at(&a2, amqp_tree_find_key(&a2, tn, &kbm)) != -128 { ok = false; }
      let kd = bytes_of("dmax");
      let ndm = amqp_tree_find_key(&a2, tn, &kd);
      if amqp_tree_int_at(&a2, ndm) != -1 { ok = false; }
      if amqp_tree_aux_at(&a2, ndm) != 255 { ok = false; }
      let klm = bytes_of("lmax");
      if amqp_tree_int_at(&a2, amqp_tree_find_key(&a2, tn, &klm)) != 9223372036854775807 { ok = false; }
      let e2 = amqp_encode_method_frame(&f2b);
      if !e2.is_ok { ok = false; } else {
        let ob: Vec[UInt8] = e2.value;
        if !bytes_equal(ob, b2) { ok = false; }
      }
    }
  }
  return assert(ok, "64/32/16/8-bit boundary values: 2^62 tag, 2^40 size/timestamp, signed minima");
}

fn t19() -> TestResult {
  var ok = true;
  if schema_len(10, 10) != 5 { ok = false; }
  if schema_len(10, 11) != 4 { ok = false; }
  if schema_len(10, 30) != 3 { ok = false; }
  if schema_len(10, 31) != 3 { ok = false; }
  if schema_len(10, 40) != 3 { ok = false; }
  if schema_len(10, 41) != 1 { ok = false; }
  if schema_len(10, 50) != 4 { ok = false; }
  if schema_len(10, 51) != 0 { ok = false; }
  if schema_len(20, 10) != 1 { ok = false; }
  if schema_len(20, 11) != 1 { ok = false; }
  if schema_len(20, 40) != 4 { ok = false; }
  if schema_len(20, 41) != 0 { ok = false; }
  if schema_len(40, 10) != 9 { ok = false; }
  if schema_len(40, 20) != 4 { ok = false; }
  if schema_len(40, 30) != 6 { ok = false; }
  if schema_len(40, 40) != 6 { ok = false; }
  if schema_len(50, 10) != 8 { ok = false; }
  if schema_len(50, 11) != 3 { ok = false; }
  if schema_len(50, 20) != 6 { ok = false; }
  if schema_len(50, 30) != 3 { ok = false; }
  if schema_len(50, 31) != 1 { ok = false; }
  if schema_len(50, 40) != 5 { ok = false; }
  if schema_len(50, 41) != 1 { ok = false; }
  if schema_len(50, 50) != 5 { ok = false; }
  if schema_len(60, 10) != 3 { ok = false; }
  if schema_len(60, 11) != 0 { ok = false; }
  if schema_len(60, 40) != 5 { ok = false; }
  if schema_len(60, 50) != 4 { ok = false; }
  if schema_len(60, 60) != 5 { ok = false; }
  if schema_len(60, 80) != 2 { ok = false; }
  if schema_len(60, 120) != 3 { ok = false; }
  if schema_len(60, 90) != -1 { ok = false; }
  if schema_len(0, 0) != -1 { ok = false; }
  let r = amqp_method_schema(10, 10);
  if !r.is_ok { ok = false; } else {
    let s: Vec[Int] = r.value;
    let k0: Int = s[0];
    let k1: Int = s[1];
    let k2: Int = s[2];
    let k3: Int = s[3];
    let k4: Int = s[4];
    if k0 != amqp_argtype_octet() { ok = false; }
    if k1 != amqp_argtype_octet() { ok = false; }
    if k2 != amqp_argtype_table() { ok = false; }
    if k3 != amqp_argtype_longstr() { ok = false; }
    if k4 != amqp_argtype_longstr() { ok = false; }
  }
  return assert(ok, "method schemas: argument counts and connection.start type sequence");
}

fn t20() -> TestResult {
  var ok = true;
  var body = Vec[UInt8].new();
  var i = 0;
  while i < 300 {
    body.push((i % 256) as UInt8);
    i = i + 1;
  }
  let bf = AmqpBodyFrame{ channel: 7; body: body };
  let br = amqp_encode_body_frame(&bf);
  if !br.is_ok { ok = false; } else {
    let bb: Vec[UInt8] = br.value;
    let bp = amqp_parse_body_frame(&bb, amqp_default_frame_max());
    if !bp.is_ok { ok = false; } else {
      let b2: AmqpBodyFrame = bp.value;
      if b2.channel != 7 { ok = false; }
      let got: Vec[UInt8] = b2.body;
      if got.len() != 300 { ok = false; }
      let be = amqp_encode_body_frame(&b2);
      if !be.is_ok { ok = false; } else {
        let bre: Vec[UInt8] = be.value;
        if !bytes_equal(bre, bb) { ok = false; }
      }
    }
  }
  var hdr = amqp_tree_new();
  a_table(&mut hdr);
  f_bytes(&mut hdr, "blob", "0123456789abcdef0123456789abcdef");
  f_bool(&mut hdr, "flag", 1);
  a_end(&mut hdr);
  var hs = Vec[UInt8].new();
  i = 0;
  while i < 300 {
    hs.push(65 as UInt8);
    i = i + 1;
  }
  let h = AmqpContentHeader{
    channel: 2; class_id: 60; weight: 0; body_size: 300; flags: amqp_basic_flag(2);
    content_type: Vec[UInt8].new(); content_encoding: Vec[UInt8].new();
    headers: hdr; delivery_mode: 0; priority: 0;
    correlation_id: Vec[UInt8].new(); reply_to: Vec[UInt8].new();
    expiration: Vec[UInt8].new(); message_id: Vec[UInt8].new();
    timestamp: 0; msg_type: Vec[UInt8].new(); user_id: Vec[UInt8].new();
    app_id: Vec[UInt8].new();
  };
  if !rt_ch(h) { ok = false; }
  // Two concatenated frames are rejected as trailing bytes by the strict
  // single-frame parsers.
  let one = hb("08000000000000ce");
  var two = Vec[UInt8].new();
  i = 0;
  while i < one.len() {
    two.push(one[i]);
    i = i + 1;
  }
  i = 0;
  while i < one.len() {
    two.push(one[i]);
    i = i + 1;
  }
  if !err_hb_is(amqp_parse_heartbeat_frame(&two, amqp_default_frame_max()), "amqp: trailing bytes") { ok = false; }
  return assert(ok, "large body/header round-trips; concatenated frames rejected as trailing bytes");
}

fn t21() -> TestResult {
  var ok = true;
  var t = amqp_tree_new();
  if amqp_tree_len(&t) != 0 { ok = false; }
  if amqp_tree_arg_count(&t) != 0 { ok = false; }
  if amqp_tree_arg_node(&t, 0) != -1 { ok = false; }
  if amqp_tree_kind_at(&t, 0) != -1 { ok = false; }
  if amqp_tree_kind_at(&t, -1) != -1 { ok = false; }
  if amqp_tree_int_at(&t, 0) != 0 { ok = false; }
  if amqp_tree_aux_at(&t, 0) != 0 { ok = false; }
  if amqp_tree_key_at(&t, 0).len() != 0 { ok = false; }
  if amqp_tree_bytes_at(&t, 0).len() != 0 { ok = false; }
  if amqp_tree_kid_count(&t, amqp_tree_arg_node(&t, 0)) != -1 { ok = false; }
  if amqp_tree_kid_node(&t, 0, 0) != -1 { ok = false; }
  if amqp_tree_find_key(&t, 0, &bytes_of("x")) != -1 { ok = false; }
  a_long(&mut t, 5);
  a_table(&mut t);
  f_long(&mut t, "inner", 6);
  a_end(&mut t);
  a_shortstr(&mut t, "tail");
  if amqp_tree_arg_count(&t) != 3 { ok = false; }
  if amqp_tree_arg_node(&t, 0) != 0 { ok = false; }
  if amqp_tree_arg_node(&t, 1) != 1 { ok = false; }
  if amqp_tree_arg_node(&t, 2) != 4 { ok = false; }
  if amqp_tree_arg_node(&t, 3) != -1 { ok = false; }
  if amqp_tree_kid_count(&t, 0) != -1 { ok = false; }
  if amqp_tree_kid_count(&t, 1) != 1 { ok = false; }
  if amqp_tree_kid_node(&t, 1, 0) != 2 { ok = false; }
  if amqp_tree_kid_node(&t, 1, 1) != -1 { ok = false; }
  if amqp_tree_find_key(&t, 1, &bytes_of("inner")) != 2 { ok = false; }
  if amqp_tree_find_key(&t, 1, &bytes_of("missing")) != -1 { ok = false; }
  if amqp_tree_kind_at(&t, amqp_tree_kid_node(&t, 1, 0)) != amqp_kind_f_long() { ok = false; }
  return assert(ok, "value tree navigation: bounds, arg/kid indexing, find_key, empty tree");
}

fn main() -> Int {
  io.println("=== xiom.amqp conformance tests ===");
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
  if failed == 0 {
    io.println("xiom.amqp: all tests passed");
  } else {
    io.println("xiom.amqp: tests failed");
  }
  return failed;
}
