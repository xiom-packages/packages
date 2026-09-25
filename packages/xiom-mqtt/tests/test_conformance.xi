// XIOM -- xiom.mqtt conformance tests (21 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Covers the documented API: remaining-length encoding pinned at every
// width boundary (0, 127, 128, 16383, 16384, 2097151, 2097152, 268435455),
// canonicality and truncation/overflow errors, fixed-header encode/parse
// with every flag rule, CONNECT (minimal and full payloads, errors),
// CONNACK, PUBLISH (QoS 0/1/2, DUP/RETAIN, binary payloads, errors),
// PUBACK, SUBSCRIBE/SUBACK, PINGREQ/DISCONNECT and encode -> parse ->
// encode round-trips.
//
// Str values are compared with str_compare (BUG 17 discipline), every Vec
// read is bound to a typed local, and error Result values are matched
// without constructing Ok/Err in the test functions.

module mqtt_tests
use xiom.io; use xiom.test;
use xiom.mqtt;
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

fn repeat_byte(b: Int, n: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < n {
    v.push(b as UInt8);
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

fn err_pair_is(r: Result[(Int, Int), Str], want: Str) -> Bool {
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

fn err_fh_is(r: Result[MqttFixedHeader, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_connect_is(r: Result[MqttConnect, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_connack_is(r: Result[MqttConnack, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_publish_is(r: Result[MqttPublish, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_subscribe_is(r: Result[MqttSubscribe, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_suback_is(r: Result[MqttSuback, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

// Remaining-length helpers.
fn rl_enc(n: Int) -> Vec[UInt8] {
  return enc_ok(mqtt_encode_remaining_length(n));
}

fn rl_is(n: Int, want: Str) -> Bool {
  return bytes_equal(rl_enc(n), hb(want));
}

fn dec_is(data: Vec[UInt8], off: Int, want_val: Int, want_next: Int) -> Bool {
  let r = mqtt_decode_remaining_length(&data, off);
  if !r.is_ok {
    return false;
  }
  let pair = r.value;
  let val: Int = pair.0;
  let next: Int = pair.1;
  return val == want_val && next == want_next;
}

fn fh_is(data: Vec[UInt8], want_type: Int, want_flags: Int, want_rem: Int, want_hlen: Int) -> Bool {
  let r = mqtt_parse_fixed_header(&data);
  if !r.is_ok {
    return false;
  }
  let h: MqttFixedHeader = r.value;
  return h.packet_type == want_type && h.flags == want_flags && h.remaining_length == want_rem && h.header_len == want_hlen;
}

// CONNECT spec with defaults: keepalive 60, clean session, no will, no
// credentials. Tests mutate the fields they exercise.
fn base_connect(cid: Vec[UInt8]) -> MqttConnect {
  return MqttConnect{
    client_id: cid;
    keepalive: 60;
    clean_session: true;
    will_present: false;
    will_qos: 0;
    will_retain: false;
    will_topic: Vec[UInt8].new();
    will_message: Vec[UInt8].new();
    username_present: false;
    password_present: false;
    username: Vec[UInt8].new();
    password: Vec[UInt8].new();
  };
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  var ok = rl_is(0, "00");
  if !rl_is(127, "7f") { ok = false; }
  if !rl_is(128, "8001") { ok = false; }
  if !rl_is(16383, "ff7f") { ok = false; }
  if !rl_is(16384, "808001") { ok = false; }
  if !rl_is(2097151, "ffff7f") { ok = false; }
  if !rl_is(2097152, "80808001") { ok = false; }
  if !rl_is(268435455, "ffffff7f") { ok = false; }
  if mqtt_remaining_length_size(0) != 1 { ok = false; }
  if mqtt_remaining_length_size(127) != 1 { ok = false; }
  if mqtt_remaining_length_size(128) != 2 { ok = false; }
  if mqtt_remaining_length_size(16383) != 2 { ok = false; }
  if mqtt_remaining_length_size(16384) != 3 { ok = false; }
  if mqtt_remaining_length_size(2097151) != 3 { ok = false; }
  if mqtt_remaining_length_size(2097152) != 4 { ok = false; }
  if mqtt_remaining_length_size(268435455) != 4 { ok = false; }
  if mqtt_remaining_length_size(-1) != 0 { ok = false; }
  if mqtt_remaining_length_size(268435456) != 0 { ok = false; }
  return assert(ok, "remaining length encode pinned across all four widths");
}

fn t2() -> TestResult {
  var ok = dec_is(hb("00"), 0, 0, 1);
  if !dec_is(hb("7f"), 0, 127, 1) { ok = false; }
  if !dec_is(hb("8001"), 0, 128, 2) { ok = false; }
  if !dec_is(hb("ff7f"), 0, 16383, 2) { ok = false; }
  if !dec_is(hb("808001"), 0, 16384, 3) { ok = false; }
  if !dec_is(hb("ffff7f"), 0, 2097151, 3) { ok = false; }
  if !dec_is(hb("80808001"), 0, 2097152, 4) { ok = false; }
  if !dec_is(hb("ffffff7f"), 0, 268435455, 4) { ok = false; }
  if !dec_is(hb("aa8001"), 1, 128, 3) { ok = false; }
  let stream = hb("8080800100");
  if !dec_is(stream, 0, 2097152, 4) { ok = false; }
  if !dec_is(stream, 4, 0, 5) { ok = false; }
  return assert(ok, "remaining length decode pinned incl. non-zero offsets");
}

fn t3() -> TestResult {
  let empty = Vec[UInt8].new();
  var ok = err_pair_is(mqtt_decode_remaining_length(&empty, 0), "mqtt: truncated packet");
  if !err_pair_is(mqtt_decode_remaining_length(&hb("80"), 0), "mqtt: truncated packet") { ok = false; }
  if !err_pair_is(mqtt_decode_remaining_length(&hb("ff"), 0), "mqtt: truncated packet") { ok = false; }
  if !err_pair_is(mqtt_decode_remaining_length(&hb("808080"), 0), "mqtt: truncated packet") { ok = false; }
  if !err_pair_is(mqtt_decode_remaining_length(&hb("01"), -1), "mqtt: negative offset") { ok = false; }
  if !err_pair_is(mqtt_decode_remaining_length(&hb("8000"), 0), "mqtt: bad remaining length") { ok = false; }
  if !err_pair_is(mqtt_decode_remaining_length(&hb("8100"), 0), "mqtt: bad remaining length") { ok = false; }
  if !err_pair_is(mqtt_decode_remaining_length(&hb("ac8200"), 0), "mqtt: bad remaining length") { ok = false; }
  if !err_pair_is(mqtt_decode_remaining_length(&hb("80808000"), 0), "mqtt: bad remaining length") { ok = false; }
  if !err_pair_is(mqtt_decode_remaining_length(&hb("ffffffff"), 0), "mqtt: bad remaining length") { ok = false; }
  if !err_pair_is(mqtt_decode_remaining_length(&hb("8080808000"), 0), "mqtt: bad remaining length") { ok = false; }
  if !err_bytes_is(mqtt_encode_remaining_length(-1), "mqtt: remaining length out of range") { ok = false; }
  if !err_bytes_is(mqtt_encode_remaining_length(268435456), "mqtt: remaining length out of range") { ok = false; }
  return assert(ok, "remaining length truncation, overlong and out-of-range errors");
}

fn t4() -> TestResult {
  var ok = bytes_equal(enc_ok(mqtt_encode_fixed_header(12, 0, 0)), hb("c000"));
  if !bytes_equal(enc_ok(mqtt_encode_fixed_header(1, 0, 20)), hb("1014")) { ok = false; }
  if !bytes_equal(enc_ok(mqtt_encode_fixed_header(3, 10, 5)), hb("3a05")) { ok = false; }
  if !bytes_equal(enc_ok(mqtt_encode_fixed_header(8, 2, 12)), hb("820c")) { ok = false; }
  if !bytes_equal(enc_ok(mqtt_encode_fixed_header(14, 0, 0)), hb("e000")) { ok = false; }
  if !err_bytes_is(mqtt_encode_fixed_header(0, 0, 0), "mqtt: bad packet type") { ok = false; }
  if !err_bytes_is(mqtt_encode_fixed_header(15, 0, 0), "mqtt: bad packet type") { ok = false; }
  if !err_bytes_is(mqtt_encode_fixed_header(4, 1, 0), "mqtt: bad fixed header flags") { ok = false; }
  if !err_bytes_is(mqtt_encode_fixed_header(6, 0, 0), "mqtt: bad fixed header flags") { ok = false; }
  if !err_bytes_is(mqtt_encode_fixed_header(3, 6, 0), "mqtt: bad qos") { ok = false; }
  if !err_bytes_is(mqtt_encode_fixed_header(1, 0, -1), "mqtt: remaining length out of range") { ok = false; }
  if !err_bytes_is(mqtt_encode_fixed_header(1, 0, 268435456), "mqtt: remaining length out of range") { ok = false; }
  return assert(ok, "fixed header encode pinned bytes and flag/type/range errors");
}

fn t5() -> TestResult {
  var ok = fh_is(hb("c000"), 12, 0, 0, 2);
  if !fh_is(hb("1014"), 1, 0, 20, 2) { ok = false; }
  if !fh_is(hb("3a05"), 3, 10, 5, 2) { ok = false; }
  if !fh_is(hb("820c"), 8, 2, 12, 2) { ok = false; }
  if !fh_is(hb("30ffffff7f"), 3, 0, 268435455, 5) { ok = false; }
  if !err_fh_is(mqtt_parse_fixed_header(&hb("")), "mqtt: truncated packet") { ok = false; }
  if !err_fh_is(mqtt_parse_fixed_header(&hb("00")), "mqtt: bad packet type") { ok = false; }
  if !err_fh_is(mqtt_parse_fixed_header(&hb("f0")), "mqtt: bad packet type") { ok = false; }
  if !err_fh_is(mqtt_parse_fixed_header(&hb("42")), "mqtt: bad fixed header flags") { ok = false; }
  if !err_fh_is(mqtt_parse_fixed_header(&hb("36")), "mqtt: bad qos") { ok = false; }
  if !err_fh_is(mqtt_parse_fixed_header(&hb("38")), "mqtt: truncated packet") { ok = false; }
  if !err_fh_is(mqtt_parse_fixed_header(&hb("c08000")), "mqtt: bad remaining length") { ok = false; }
  return assert(ok, "fixed header parse pinned bytes, type/flags/qos/varint errors");
}

fn t6() -> TestResult {
  let c = base_connect(bytes_of("client-1"));
  return assert(bytes_equal(enc_ok(mqtt_encode_connect(&c)), hb("101400044d5154540402003c0008636c69656e742d31")), "CONNECT minimal encode pinned bytes");
}

fn t7() -> TestResult {
  var c = base_connect(bytes_of("cid"));
  c.keepalive = 10;
  c.clean_session = false;
  c.will_present = true;
  c.will_qos = 1;
  c.will_retain = true;
  c.will_topic = bytes_of("w/t");
  c.will_message = bytes_of("bye");
  c.username_present = true;
  c.username = bytes_of("u");
  c.password_present = true;
  c.password = bytes_of("p");
  return assert(bytes_equal(enc_ok(mqtt_encode_connect(&c)), hb("101f00044d51545404ec000a00036369640003772f740003627965000175000170")), "CONNECT full encode pinned bytes (will + credentials)");
}

fn t8() -> TestResult {
  let r1 = mqtt_parse_connect(&hb("101400044d5154540402003c0008636c69656e742d31"));
  if !r1.is_ok { return assert(false, "minimal CONNECT must parse"); }
  let c1: MqttConnect = r1.value;
  var ok = c1.keepalive == 60;
  if !c1.clean_session { ok = false; }
  if c1.will_present { ok = false; }
  if c1.will_qos != 0 { ok = false; }
  if c1.will_retain { ok = false; }
  if c1.username_present || c1.password_present { ok = false; }
  let cid1: Vec[UInt8] = c1.client_id;
  let wt1: Vec[UInt8] = c1.will_topic;
  let wm1: Vec[UInt8] = c1.will_message;
  let un1: Vec[UInt8] = c1.username;
  let pw1: Vec[UInt8] = c1.password;
  if !bytes_equal(cid1, bytes_of("client-1")) { ok = false; }
  if wt1.len() != 0 || wm1.len() != 0 || un1.len() != 0 || pw1.len() != 0 { ok = false; }
  let r2 = mqtt_parse_connect(&hb("101f00044d51545404ec000a00036369640003772f740003627965000175000170"));
  if !r2.is_ok { return assert(false, "full CONNECT must parse"); }
  let c2: MqttConnect = r2.value;
  if c2.keepalive != 10 { ok = false; }
  if c2.clean_session { ok = false; }
  if !c2.will_present { ok = false; }
  if c2.will_qos != 1 { ok = false; }
  if !c2.will_retain { ok = false; }
  if !c2.username_present { ok = false; }
  if !c2.password_present { ok = false; }
  let cid2: Vec[UInt8] = c2.client_id;
  let wt2: Vec[UInt8] = c2.will_topic;
  let wm2: Vec[UInt8] = c2.will_message;
  let un2: Vec[UInt8] = c2.username;
  let pw2: Vec[UInt8] = c2.password;
  if !bytes_equal(cid2, bytes_of("cid")) { ok = false; }
  if !bytes_equal(wt2, bytes_of("w/t")) { ok = false; }
  if !bytes_equal(wm2, bytes_of("bye")) { ok = false; }
  if !bytes_equal(un2, bytes_of("u")) { ok = false; }
  if !bytes_equal(pw2, bytes_of("p")) { ok = false; }
  return assert(ok, "CONNECT parse fields: minimal and full payloads");
}

fn t9() -> TestResult {
  var ok = err_connect_is(mqtt_parse_connect(&hb("101400044d5154580402003c0008636c69656e742d31")), "mqtt: bad protocol name");
  if !err_connect_is(mqtt_parse_connect(&hb("101400044d5154540502003c0008636c69656e742d31")), "mqtt: bad protocol level") { ok = false; }
  if !err_connect_is(mqtt_parse_connect(&hb("101400044d5154540403003c0008636c69656e742d31")), "mqtt: bad connect flags") { ok = false; }
  if !err_connect_is(mqtt_parse_connect(&hb("c000")), "mqtt: bad packet type") { ok = false; }
  if !err_connect_is(mqtt_parse_connect(&hb("100500054d5154")), "mqtt: bad protocol name") { ok = false; }
  return assert(ok, "CONNECT parse rejects bad protocol name/level/reserved flag/type");
}

fn t10() -> TestResult {
  var ok = err_connect_is(mqtt_parse_connect(&hb("101100044d515454041c000000000001740000")), "mqtt: bad qos");
  if !err_connect_is(mqtt_parse_connect(&hb("100c00044d515454042200000000")), "mqtt: bad connect flags") { ok = false; }
  if !err_connect_is(mqtt_parse_connect(&hb("101400044d5154540402003c0008636c69656e742d3100")), "mqtt: trailing bytes") { ok = false; }
  if !err_connect_is(mqtt_parse_connect(&hb("101400044d5154540402003c0008636c69656e742d")), "mqtt: truncated packet") { ok = false; }
  return assert(ok, "CONNECT parse rejects will-QoS-3, retain-without-will, truncation");
}

fn t11() -> TestResult {
  var c = base_connect(bytes_of("cid"));
  c.keepalive = 70000;
  var ok = err_bytes_is(mqtt_encode_connect(&c), "mqtt: bad keepalive");
  var c2 = base_connect(bytes_of("cid"));
  c2.will_present = true;
  c2.will_qos = 5;
  c2.will_topic = bytes_of("t");
  if !err_bytes_is(mqtt_encode_connect(&c2), "mqtt: bad qos") { ok = false; }
  var c3 = base_connect(bytes_of("cid"));
  c3.will_present = true;
  if !err_bytes_is(mqtt_encode_connect(&c3), "mqtt: bad topic") { ok = false; }
  var c4 = base_connect(bytes_of("cid"));
  c4.will_topic = bytes_of("t");
  if !err_bytes_is(mqtt_encode_connect(&c4), "mqtt: bad connect flags") { ok = false; }
  var c5 = base_connect(bytes_of("cid"));
  c5.username = bytes_of("u");
  if !err_bytes_is(mqtt_encode_connect(&c5), "mqtt: bad connect flags") { ok = false; }
  var c6 = base_connect(bytes_of("cid"));
  c6.password = bytes_of("p");
  if !err_bytes_is(mqtt_encode_connect(&c6), "mqtt: bad connect flags") { ok = false; }
  var c7 = base_connect(repeat_byte(65, 65536));
  if !err_bytes_is(mqtt_encode_connect(&c7), "mqtt: string too long") { ok = false; }
  return assert(ok, "CONNECT encode validates keepalive, will flags, presence and lengths");
}

fn t12() -> TestResult {
  var ok = bytes_equal(enc_ok(mqtt_encode_connack(false, 0)), hb("20020000"));
  if !bytes_equal(enc_ok(mqtt_encode_connack(true, 0)), hb("20020100")) { ok = false; }
  if !bytes_equal(enc_ok(mqtt_encode_connack(false, 5)), hb("20020005")) { ok = false; }
  if !err_bytes_is(mqtt_encode_connack(false, 6), "mqtt: bad return code") { ok = false; }
  if !err_bytes_is(mqtt_encode_connack(true, 1), "mqtt: bad connack flags") { ok = false; }
  let r1 = mqtt_parse_connack(&hb("20020100"));
  if !r1.is_ok { return assert(false, "CONNACK must parse"); }
  let a1: MqttConnack = r1.value;
  if !a1.session_present || a1.return_code != 0 { ok = false; }
  let r2 = mqtt_parse_connack(&hb("20020005"));
  if !r2.is_ok { return assert(false, "refusal CONNACK must parse"); }
  let a2: MqttConnack = r2.value;
  if a2.session_present || a2.return_code != 5 { ok = false; }
  if !err_connack_is(mqtt_parse_connack(&hb("20020200")), "mqtt: bad connack flags") { ok = false; }
  if !err_connack_is(mqtt_parse_connack(&hb("20020101")), "mqtt: bad connack flags") { ok = false; }
  if !err_connack_is(mqtt_parse_connack(&hb("20020006")), "mqtt: bad return code") { ok = false; }
  if !err_connack_is(mqtt_parse_connack(&hb("2001")), "mqtt: truncated packet") { ok = false; }
  if !err_connack_is(mqtt_parse_connack(&hb("2003000000")), "mqtt: bad payload") { ok = false; }
  if !err_connack_is(mqtt_parse_connack(&hb("2002000000")), "mqtt: trailing bytes") { ok = false; }
  if !err_connack_is(mqtt_parse_connack(&hb("c000")), "mqtt: bad packet type") { ok = false; }
  return assert(ok, "CONNACK encode/parse pinned incl. session-present and refusal codes");
}

fn t13() -> TestResult {
  var ok = bytes_equal(enc_ok(mqtt_encode_publish(&bytes_of("a/b"), &bytes_of("hi"), 0, false, false, 0)), hb("30070003612f626869"));
  let r = mqtt_parse_publish(&hb("30070003612f626869"));
  if !r.is_ok { return assert(false, "QoS 0 PUBLISH must parse"); }
  let p: MqttPublish = r.value;
  let topic: Vec[UInt8] = p.topic;
  let payload: Vec[UInt8] = p.payload;
  if p.dup || p.qos != 0 || p.retain { ok = false; }
  if p.packet_id != 0 { ok = false; }
  if !bytes_equal(topic, bytes_of("a/b")) { ok = false; }
  if !bytes_equal(payload, bytes_of("hi")) { ok = false; }
  return assert(ok, "PUBLISH QoS 0 encode/parse pinned (topic, payload, no id)");
}

fn t14() -> TestResult {
  var ok = bytes_equal(enc_ok(mqtt_encode_publish(&bytes_of("t"), &bytes_of(""), 1, false, false, 10)), hb("3205000174000a"));
  if !bytes_equal(enc_ok(mqtt_encode_publish(&bytes_of("t"), &bytes_of("x"), 2, true, true, 7)), hb("3d06000174000778")) { ok = false; }
  if !bytes_equal(enc_ok(mqtt_encode_publish(&bytes_of("t"), &hb("00ff80"), 1, false, false, 1)), hb("3208000174000100ff80")) { ok = false; }
  let r1 = mqtt_parse_publish(&hb("3205000174000a"));
  if !r1.is_ok { return assert(false, "QoS 1 PUBLISH must parse"); }
  let p1: MqttPublish = r1.value;
  let t1: Vec[UInt8] = p1.topic;
  if p1.dup || p1.qos != 1 || p1.retain { ok = false; }
  if p1.packet_id != 10 { ok = false; }
  if !bytes_equal(t1, bytes_of("t")) { ok = false; }
  let r2 = mqtt_parse_publish(&hb("3d06000174000778"));
  if !r2.is_ok { return assert(false, "QoS 2 PUBLISH must parse"); }
  let p2: MqttPublish = r2.value;
  if !p2.dup || p2.qos != 2 || !p2.retain { ok = false; }
  if p2.packet_id != 7 { ok = false; }
  let r3 = mqtt_parse_publish(&hb("3208000174000100ff80"));
  if !r3.is_ok { return assert(false, "binary-payload PUBLISH must parse"); }
  let p3: MqttPublish = r3.value;
  let pay3: Vec[UInt8] = p3.payload;
  if p3.packet_id != 1 { ok = false; }
  if !bytes_equal(pay3, hb("00ff80")) { ok = false; }
  return assert(ok, "PUBLISH QoS 1/2 with DUP/RETAIN and a binary payload round-trip");
}

fn t15() -> TestResult {
  var ok = err_bytes_is(mqtt_encode_publish(&bytes_of("t"), &bytes_of("x"), 3, false, false, 1), "mqtt: bad qos");
  if !err_bytes_is(mqtt_encode_publish(&bytes_of("t"), &bytes_of("x"), 1, false, false, 0), "mqtt: packet id zero") { ok = false; }
  if !err_bytes_is(mqtt_encode_publish(&bytes_of("t"), &bytes_of("x"), 1, false, false, 70000), "mqtt: packet id out of range") { ok = false; }
  if !err_bytes_is(mqtt_encode_publish(&bytes_of("t"), &bytes_of("x"), 0, false, false, 5), "mqtt: unexpected packet id") { ok = false; }
  let empty_topic = Vec[UInt8].new();
  if !err_bytes_is(mqtt_encode_publish(&empty_topic, &bytes_of("x"), 0, false, false, 0), "mqtt: bad topic") { ok = false; }
  if !err_bytes_is(mqtt_encode_publish(&bytes_of("a/#"), &bytes_of("x"), 0, false, false, 0), "mqtt: bad topic") { ok = false; }
  if !err_publish_is(mqtt_parse_publish(&hb("3603000174")), "mqtt: bad qos") { ok = false; }
  if !err_publish_is(mqtt_parse_publish(&hb("32050001740000")), "mqtt: packet id zero") { ok = false; }
  if !err_publish_is(mqtt_parse_publish(&hb("30020000")), "mqtt: bad topic") { ok = false; }
  if !err_publish_is(mqtt_parse_publish(&hb("300400012b00")), "mqtt: bad topic") { ok = false; }
  if !err_publish_is(mqtt_parse_publish(&hb("300400056162")), "mqtt: truncated packet") { ok = false; }
  if !err_publish_is(mqtt_parse_publish(&hb("30070003612f62686900")), "mqtt: trailing bytes") { ok = false; }
  if !err_publish_is(mqtt_parse_publish(&hb("c000")), "mqtt: bad packet type") { ok = false; }
  if !mqtt_topic_is_valid(&bytes_of("a/b")) { ok = false; }
  if mqtt_topic_is_valid(&bytes_of("a/#")) { ok = false; }
  if mqtt_topic_is_valid(&empty_topic) { ok = false; }
  return assert(ok, "PUBLISH errors: QoS 3, zero id, bad topic, truncation, topic predicate");
}

fn t16() -> TestResult {
  var ok = bytes_equal(enc_ok(mqtt_encode_puback(1)), hb("40020001"));
  if !bytes_equal(enc_ok(mqtt_encode_puback(65535)), hb("4002ffff")) { ok = false; }
  if !err_bytes_is(mqtt_encode_puback(0), "mqtt: packet id zero") { ok = false; }
  if !err_bytes_is(mqtt_encode_puback(-1), "mqtt: packet id out of range") { ok = false; }
  let r1 = mqtt_parse_puback(&hb("40020001"));
  if !r1.is_ok { return assert(false, "PUBACK 1 must parse"); }
  if r1.value != 1 { ok = false; }
  let r2 = mqtt_parse_puback(&hb("4002ffff"));
  if !r2.is_ok { return assert(false, "PUBACK 65535 must parse"); }
  if r2.value != 65535 { ok = false; }
  if !err_int_is(mqtt_parse_puback(&hb("400100")), "mqtt: bad payload") { ok = false; }
  if !err_int_is(mqtt_parse_puback(&hb("40020000")), "mqtt: packet id zero") { ok = false; }
  if !err_int_is(mqtt_parse_puback(&hb("4002000100")), "mqtt: trailing bytes") { ok = false; }
  if !err_int_is(mqtt_parse_puback(&hb("c000")), "mqtt: bad packet type") { ok = false; }
  return assert(ok, "PUBACK encode/parse pinned and error catalog");
}

fn t17() -> TestResult {
  var filters = Vec[Vec[UInt8]].new();
  filters.push(bytes_of("a"));
  filters.push(bytes_of("b/#"));
  var qoss = Vec[Int].new();
  qoss.push(0);
  qoss.push(1);
  var ok = bytes_equal(enc_ok(mqtt_encode_subscribe(2, &filters, &qoss)), hb("820c0002000161000003622f2301"));
  let r = mqtt_parse_subscribe(&hb("820c0002000161000003622f2301"));
  if !r.is_ok { return assert(false, "SUBSCRIBE must parse"); }
  let s: MqttSubscribe = r.value;
  if s.packet_id != 2 { ok = false; }
  if s.filters.len() != 2 { ok = false; }
  if s.qoss.len() != 2 { ok = false; }
  let f0: Vec[UInt8] = s.filters[0];
  let f1: Vec[UInt8] = s.filters[1];
  let q0: Int = s.qoss[0];
  let q1: Int = s.qoss[1];
  if !bytes_equal(f0, bytes_of("a")) { ok = false; }
  if !bytes_equal(f1, bytes_of("b/#")) { ok = false; }
  if q0 != 0 { ok = false; }
  if q1 != 1 { ok = false; }
  return assert(ok, "SUBSCRIBE encode/parse pinned (id, filters, requested QoS)");
}

fn t18() -> TestResult {
  var filters = Vec[Vec[UInt8]].new();
  filters.push(bytes_of("a"));
  var no_qoss = Vec[Int].new();
  var ok = err_bytes_is(mqtt_encode_subscribe(1, &filters, &no_qoss), "mqtt: filters/qos length mismatch");
  var no_filters = Vec[Vec[UInt8]].new();
  var no_codes = Vec[Int].new();
  if !err_bytes_is(mqtt_encode_subscribe(1, &no_filters, &no_codes), "mqtt: bad payload") { ok = false; }
  var empty_filter = Vec[Vec[UInt8]].new();
  var ef = Vec[UInt8].new();
  empty_filter.push(ef);
  var one_qos = Vec[Int].new();
  one_qos.push(0);
  if !err_bytes_is(mqtt_encode_subscribe(1, &empty_filter, &one_qos), "mqtt: bad topic filter") { ok = false; }
  var bad_filter = Vec[Vec[UInt8]].new();
  bad_filter.push(bytes_of("a#b"));
  if !err_bytes_is(mqtt_encode_subscribe(1, &bad_filter, &one_qos), "mqtt: bad topic filter") { ok = false; }
  var qos3 = Vec[Int].new();
  qos3.push(3);
  if !err_bytes_is(mqtt_encode_subscribe(1, &filters, &qos3), "mqtt: bad qos") { ok = false; }
  if !err_bytes_is(mqtt_encode_subscribe(0, &filters, &one_qos), "mqtt: packet id zero") { ok = false; }
  if !err_subscribe_is(mqtt_parse_subscribe(&hb("82020001")), "mqtt: bad payload") { ok = false; }
  if !err_subscribe_is(mqtt_parse_subscribe(&hb("8206000100016103")), "mqtt: bad qos") { ok = false; }
  if !err_subscribe_is(mqtt_parse_subscribe(&hb("82050001000261")), "mqtt: truncated packet") { ok = false; }
  if !err_subscribe_is(mqtt_parse_subscribe(&hb("82050001000161")), "mqtt: truncated packet") { ok = false; }
  if !err_subscribe_is(mqtt_parse_subscribe(&hb("82080001000361236200")), "mqtt: bad topic filter") { ok = false; }
  if !err_subscribe_is(mqtt_parse_subscribe(&hb("8203000000")), "mqtt: packet id zero") { ok = false; }
  if !mqtt_topic_filter_is_valid(&bytes_of("b/#")) { ok = false; }
  if !mqtt_topic_filter_is_valid(&bytes_of("#")) { ok = false; }
  if mqtt_topic_filter_is_valid(&bytes_of("a#b")) { ok = false; }
  if mqtt_topic_filter_is_valid(&bytes_of("a/#/b")) { ok = false; }
  if mqtt_topic_filter_is_valid(&bytes_of("")) { ok = false; }
  return assert(ok, "SUBSCRIBE errors and filter predicate (mismatch, empty, bad wildcards, QoS 3)");
}

fn t19() -> TestResult {
  var codes = Vec[Int].new();
  codes.push(0);
  codes.push(1);
  codes.push(2);
  codes.push(128);
  var ok = bytes_equal(enc_ok(mqtt_encode_suback(1, &codes)), hb("9006000100010280"));
  let r = mqtt_parse_suback(&hb("9006000100010280"));
  if !r.is_ok { return assert(false, "SUBACK must parse"); }
  let s: MqttSuback = r.value;
  if s.packet_id != 1 { ok = false; }
  if s.codes.len() != 4 { ok = false; }
  let c0: Int = s.codes[0];
  let c1: Int = s.codes[1];
  let c2: Int = s.codes[2];
  let c3: Int = s.codes[3];
  if c0 != 0 || c1 != 1 || c2 != 2 || c3 != 128 { ok = false; }
  var bad = Vec[Int].new();
  bad.push(3);
  if !err_bytes_is(mqtt_encode_suback(1, &bad), "mqtt: bad suback code") { ok = false; }
  var bad2 = Vec[Int].new();
  bad2.push(129);
  if !err_bytes_is(mqtt_encode_suback(1, &bad2), "mqtt: bad suback code") { ok = false; }
  var empty_codes = Vec[Int].new();
  if !err_bytes_is(mqtt_encode_suback(1, &empty_codes), "mqtt: bad payload") { ok = false; }
  if !err_bytes_is(mqtt_encode_suback(0, &codes), "mqtt: packet id zero") { ok = false; }
  if !err_suback_is(mqtt_parse_suback(&hb("9003000103")), "mqtt: bad suback code") { ok = false; }
  if !err_suback_is(mqtt_parse_suback(&hb("9006000100")), "mqtt: truncated packet") { ok = false; }
  if !err_suback_is(mqtt_parse_suback(&hb("90020001")), "mqtt: bad payload") { ok = false; }
  if !err_suback_is(mqtt_parse_suback(&hb("9003000000")), "mqtt: packet id zero") { ok = false; }
  return assert(ok, "SUBACK encode/parse pinned incl. 0x80 and code errors");
}

fn t20() -> TestResult {
  var ok = bytes_equal(mqtt_encode_pingreq(), hb("c000"));
  if !bytes_equal(mqtt_encode_disconnect(), hb("e000")) { ok = false; }
  if !mqtt_parse_pingreq(&hb("c000")).is_ok { ok = false; }
  if !mqtt_parse_disconnect(&hb("e000")).is_ok { ok = false; }
  if !err_unit_is(mqtt_parse_pingreq(&hb("c001")), "mqtt: truncated packet") { ok = false; }
  if !err_unit_is(mqtt_parse_pingreq(&hb("c00100")), "mqtt: bad payload") { ok = false; }
  if !err_unit_is(mqtt_parse_pingreq(&hb("c0")), "mqtt: truncated packet") { ok = false; }
  if !err_unit_is(mqtt_parse_pingreq(&hb("e000")), "mqtt: bad packet type") { ok = false; }
  if !err_unit_is(mqtt_parse_disconnect(&hb("c000")), "mqtt: bad packet type") { ok = false; }
  if !err_unit_is(mqtt_parse_disconnect(&hb("e00100")), "mqtt: bad payload") { ok = false; }
  return assert(ok, "PINGREQ/DISCONNECT pinned bytes, empty-body parse and type errors");
}

fn t21() -> TestResult {
  var ok = true;
  var c = base_connect(bytes_of("client-1"));
  c.keepalive = 10;
  c.clean_session = false;
  c.will_present = true;
  c.will_qos = 1;
  c.will_retain = true;
  c.will_topic = bytes_of("w/t");
  c.will_message = bytes_of("bye");
  c.username_present = true;
  c.username = bytes_of("u");
  c.password_present = true;
  c.password = bytes_of("p");
  let ce1 = enc_ok(mqtt_encode_connect(&c));
  let cr = mqtt_parse_connect(&ce1);
  if !cr.is_ok { ok = false; } else {
    let c2: MqttConnect = cr.value;
    let ce2r = mqtt_encode_connect(&c2);
    if !ce2r.is_ok { ok = false; } else {
      let ce2: Vec[UInt8] = ce2r.value;
      if !bytes_equal(ce1, ce2) { ok = false; }
    }
  }
  var payload = Vec[UInt8].new();
  var i = 0;
  while i < 200 {
    payload.push((i % 251) as UInt8);
    i = i + 1;
  }
  let topic = bytes_of("sensors/temp");
  let pe1 = enc_ok(mqtt_encode_publish(&topic, &payload, 1, true, false, 5));
  let pr = mqtt_parse_publish(&pe1);
  if !pr.is_ok { ok = false; } else {
    let p2: MqttPublish = pr.value;
    let pay2: Vec[UInt8] = p2.payload;
    if !bytes_equal(pay2, payload) { ok = false; }
    let pe2r = mqtt_encode_publish(&topic, &pay2, p2.qos, p2.retain, p2.dup, p2.packet_id);
    if !pe2r.is_ok { ok = false; } else {
      let pe2: Vec[UInt8] = pe2r.value;
      if !bytes_equal(pe1, pe2) { ok = false; }
    }
  }
  var filters = Vec[Vec[UInt8]].new();
  filters.push(bytes_of("a"));
  filters.push(bytes_of("b/#"));
  var qoss = Vec[Int].new();
  qoss.push(0);
  qoss.push(1);
  let se1 = enc_ok(mqtt_encode_subscribe(2, &filters, &qoss));
  let sr = mqtt_parse_subscribe(&se1);
  if !sr.is_ok { ok = false; } else {
    let s2: MqttSubscribe = sr.value;
    let f0: Vec[UInt8] = s2.filters[0];
    let f1: Vec[UInt8] = s2.filters[1];
    let se2r = mqtt_encode_subscribe(s2.packet_id, &s2.filters, &s2.qoss);
    if !se2r.is_ok { ok = false; } else {
      let se2: Vec[UInt8] = se2r.value;
      if !bytes_equal(se1, se2) { ok = false; }
    }
    if !bytes_equal(f0, bytes_of("a")) { ok = false; }
    if !bytes_equal(f1, bytes_of("b/#")) { ok = false; }
  }
  var scodes = Vec[Int].new();
  scodes.push(0);
  scodes.push(2);
  scodes.push(128);
  let ae1 = enc_ok(mqtt_encode_suback(1, &scodes));
  let ar = mqtt_parse_suback(&ae1);
  if !ar.is_ok { ok = false; } else {
    let a2: MqttSuback = ar.value;
    let ae2r = mqtt_encode_suback(a2.packet_id, &a2.codes);
    if !ae2r.is_ok { ok = false; } else {
      let ae2: Vec[UInt8] = ae2r.value;
      if !bytes_equal(ae1, ae2) { ok = false; }
    }
  }
  return assert(ok, "encode -> parse -> encode round-trips for CONNECT/PUBLISH/SUBSCRIBE/SUBACK");
}

fn main() -> Int {
  io.println("=== xiom.mqtt conformance tests ===");
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
    io.println("xiom.mqtt: all tests passed");
  } else {
    io.println("xiom.mqtt: tests failed");
  }
  return failed;
}
