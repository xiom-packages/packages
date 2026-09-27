// XIOM -- xiom.mysql conformance tests (20 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Covers the documented API: the constant tables (framing, capabilities,
// status flags, the full column type table, charset subset, commands, packet
// kinds, auth kinds), packet framing with the 0xFFFFFF continuation rule,
// little-endian primitives, length-encoded values with their boundary
// encodings and error offsets, the handshake v10 codec, the handshake
// response 41 (lenenc / secure / NUL auth variants and connect attrs), the
// SSL request, OK/ERR/EOF/LOCAL INFILE, commands, and result-set packets
// (column count, column definition, text rows).
//
// Harness style mirrors xiom.cassandra / xiom.thrift: one fn tN() ->
// TestResult per check, called directly from main; main prints
// [PASS]/[FAIL] and returns the failure count. Synthetic buffers are built
// in-test from hex literals (xiom.encoding.hex) and from the package's own
// writers; no external data files. Str payloads are compared with
// str_compare (BUG 17 discipline: `==` on Str values read from a Vec lowers
// to a pointer comparison).

module mysql_tests
use xiom.io; use xiom.test;
use xiom.string; use xiom.string.compare;
use xiom.encoding.hex;
use xiom.mysql;

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

// True when both strings are byte-identical (BUG 17 discipline).
fn str_is(s: Str, want: Str) -> Bool {
  return str_compare(s, want) == 0;
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

fn err_is_bts(r: Result[Vec[UInt8], Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_compare(r.error, want) == 0;
}

fn err_is_lenenc(r: Result[MysqlLenenc, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_compare(r.error, want) == 0;
}

fn err_is_header(r: Result[MysqlPacketHeader, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_compare(r.error, want) == 0;
}

fn err_is_packet(r: Result[MysqlPacket, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_compare(r.error, want) == 0;
}

fn err_is_message(r: Result[MysqlMessage, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_compare(r.error, want) == 0;
}

fn err_is_handshake(r: Result[MysqlHandshake, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_compare(r.error, want) == 0;
}

fn err_is_ssl(r: Result[MysqlSslRequest, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_compare(r.error, want) == 0;
}

fn err_is_response(r: Result[MysqlHandshakeResponse, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_compare(r.error, want) == 0;
}

fn err_is_okp(r: Result[MysqlOk, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_compare(r.error, want) == 0;
}

fn err_is_errp(r: Result[MysqlErr, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_compare(r.error, want) == 0;
}

fn err_is_eofp(r: Result[MysqlEof, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_compare(r.error, want) == 0;
}

fn err_is_command(r: Result[MysqlCommand, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_compare(r.error, want) == 0;
}

fn err_is_column(r: Result[MysqlColumn, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_compare(r.error, want) == 0;
}

fn err_is_row(r: Result[MysqlTextRow, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_compare(r.error, want) == 0;
}

// Bytes of the currently accumulated writer output.
fn wbytes(w: &MysqlWriter) -> Vec[UInt8] {
  return mysql_writer_bytes(w);
}

// Encoded bytes of a length-encoded integer as a hex string ("<err>" when
// the value is rejected).
fn lenenc_hex(v: Int) -> Str {
  var w = mysql_writer_new();
  let wr = mysql_write_lenenc_int(&mut w, v);
  if !wr.is_ok {
    return "<err>";
  }
  let b: Vec[UInt8] = mysql_writer_bytes(&w);
  return hex.hex_encode(&b);
}

// The canonical synthetic handshake v10 packet used by t5/t6.
fn hs_hex() -> Str {
  let zeros10 = string.str_repeat("00", 10);
  return "0a" + "382e302e333500" + "39300000" + "0102030405060708" + "00" + "0082" + "2d" + "0200" + "1800" + "15" + zeros10 + "090a0b0c0d0e0f101112131400" + "63616368696e675f736861325f70617373776f726400";
}

// The same handshake as a struct, with the same field values.
fn mk_hs() -> MysqlHandshake {
  var p1 = Vec[UInt8].new();
  var i = 1;
  while i <= 8 {
    p1.push(i as UInt8);
    i = i + 1;
  }
  var p2 = Vec[UInt8].new();
  var j = 9;
  while j <= 20 {
    p2.push(j as UInt8);
    j = j + 1;
  }
  p2.push(0);
  return MysqlHandshake{ protocol_version: 10; server_version: "8.0.35"; connection_id: 12345; capability_flags: 1606144; character_set: 45; status_flags: 2; auth_plugin_data_len: 21; auth_plugin_data_1: p1; auth_plugin_data_2: p2; auth_plugin_name: "caching_sha2_password"; };
}

// The canonical synthetic handshake response (lenenc auth variant).
fn mk_resp_lenenc() -> MysqlHandshakeResponse {
  var auth = Vec[UInt8].new();
  auth.push(170);
  auth.push(187);
  var names = Vec[Str].new();
  names.push("a");
  names.push("b");
  var values = Vec[Str].new();
  values.push("1");
  values.push("2");
  return MysqlHandshakeResponse{ capability_flags: 3670536; max_packet_size: 16777216; character_set: 255; username: "root"; auth_response_kind: 3; auth_response: auth; database: "test"; auth_plugin_name: "caching_sha2_password"; attr_names: names; attr_values: values; };
}

// The canonical synthetic column definition used by t13.
fn mk_col() -> MysqlColumn {
  return MysqlColumn{ catalog: "def"; schema: ""; table_name: ""; org_table: ""; name: "a"; org_name: ""; charset: 45; column_length: 11; type_code: 3; flags: 0; decimals: 0; };
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  var ok = true;
  if mysql_protocol_handshake_v10() != 10 { ok = false; }
  if mysql_packet_header_len() != 4 { ok = false; }
  if mysql_max_payload_len() != 16777215 { ok = false; }
  if mysql_default_max_packet_size() != 16777216 { ok = false; }
  if mysql_sequence_modulus() != 256 { ok = false; }
  if mysql_ssl_request_len() != 32 { ok = false; }
  if mysql_sequence_next(0) != 1 { ok = false; }
  if mysql_sequence_next(254) != 255 { ok = false; }
  if mysql_sequence_next(255) != 0 { ok = false; }
  if mysql_sequence_next(-1) != 0 { ok = false; }
  if mysql_sequence_next(256) != 1 { ok = false; }
  if !mysql_packet_is_continuation(16777215) { ok = false; }
  if mysql_packet_is_continuation(16777214) { ok = false; }
  if mysql_packet_is_continuation(0) { ok = false; }
  var w = mysql_writer_new();
  let wr = mysql_write_packet_header(&mut w, 3, 7);
  if !wr.is_ok { ok = false; }
  let b: Vec[UInt8] = wbytes(&w);
  if !str_is(hex.hex_encode(&b), "03000007") { ok = false; }
  var r = mysql_reader_new(b);
  let hr = mysql_read_packet_header(&mut r);
  if !hr.is_ok { ok = false; } else {
    let h: MysqlPacketHeader = hr.value;
    if mysql_packet_header_payload_len(&h) != 3 { ok = false; }
    if mysql_packet_header_sequence_id(&h) != 7 { ok = false; }
  }
  var we = mysql_writer_new();
  if !err_is_b(mysql_write_packet_header(&mut we, 16777216, 0), "mysql: payload length 16777216 exceeds 16777215") { ok = false; }
  var we2 = mysql_writer_new();
  if !err_is_b(mysql_write_packet_header(&mut we2, -1, 0), "mysql: bad payload length -1") { ok = false; }
  if !err_is_header(mysql_read_packet_header(&mut mysql_reader_new(hb("0300"))), "mysql: truncated input at offset 0") { ok = false; }
  if !err_is_header(mysql_read_packet_header(&mut mysql_reader_new(hb("030000"))), "mysql: truncated input at offset 3") { ok = false; }
  return assert(ok, "framing constants, packet header bytes, sequence wrap and header errors");
}

fn t2() -> TestResult {
  var ok = true;
  var payload = Vec[UInt8].new();
  payload.push(1);
  payload.push(2);
  payload.push(3);
  var w = mysql_writer_new();
  let wr = mysql_write_packet(&mut w, &payload, 5);
  if !wr.is_ok { ok = false; } else {
    if wr.value != 6 { ok = false; }
  }
  let bytes: Vec[UInt8] = wbytes(&w);
  if !str_is(hex.hex_encode(&bytes), "03000005010203") { ok = false; }
  var r = mysql_reader_new(bytes);
  let pr = mysql_read_packet(&mut r);
  if !pr.is_ok { ok = false; } else {
    let p: MysqlPacket = pr.value;
    if mysql_packet_payload_len(&p) != 3 { ok = false; }
    if mysql_packet_sequence_id(&p) != 5 { ok = false; }
    let pb: Vec[UInt8] = mysql_packet_payload(&p);
    if !bytes_equal(pb, payload) { ok = false; }
  }
  let empty = Vec[UInt8].new();
  var w2 = mysql_writer_new();
  let wr2 = mysql_write_packet(&mut w2, &empty, 0);
  if !wr2.is_ok { ok = false; } else {
    if wr2.value != 1 { ok = false; }
  }
  let b2: Vec[UInt8] = wbytes(&w2);
  if !str_is(hex.hex_encode(&b2), "00000000") { ok = false; }
  var w3 = mysql_writer_new();
  let small = hb("aa");
  let wr3 = mysql_write_packet(&mut w3, &small, 0);
  if !wr3.is_ok { ok = false; }
  var w4 = mysql_writer_new();
  let wr4 = mysql_write_packet(&mut w4, &small, 0);
  if !wr4.is_ok { ok = false; }
  var wcat = mysql_writer_new();
  mysql_write_bytes(&mut wcat, &wbytes(&w3));
  mysql_write_bytes(&mut wcat, &wbytes(&w4));
  var rc = mysql_reader_new(wbytes(&wcat));
  let p1r = mysql_read_packet(&mut rc);
  if !p1r.is_ok { ok = false; } else {
    let p1: MysqlPacket = p1r.value;
    if mysql_packet_sequence_id(&p1) != 0 { ok = false; }
  }
  let p2r = mysql_read_packet(&mut rc);
  if !p2r.is_ok { ok = false; } else {
    let p2: MysqlPacket = p2r.value;
    if mysql_packet_sequence_id(&p2) != 0 { ok = false; }
  }
  if mysql_reader_remaining(&rc) != 0 { ok = false; }
  return assert(ok, "packet write/read round-trip, empty packet, concatenated packets and truncation");
}

fn t3() -> TestResult {
  var ok = true;
  if !str_is(lenenc_hex(0), "00") { ok = false; }
  if !str_is(lenenc_hex(250), "fa") { ok = false; }
  if !str_is(lenenc_hex(251), "fcfb00") { ok = false; }
  if !str_is(lenenc_hex(65535), "fcffff") { ok = false; }
  if !str_is(lenenc_hex(65536), "fd000001") { ok = false; }
  if !str_is(lenenc_hex(16777215), "fdffffff") { ok = false; }
  if !str_is(lenenc_hex(16777216), "fe0000000100000000") { ok = false; }
  if !str_is(lenenc_hex(9223372036854775807), "feffffffffffffff7f") { ok = false; }
  var r0 = mysql_reader_new(hb("00"));
  let i0 = mysql_read_lenenc_int(&mut r0);
  if !i0.is_ok { ok = false; } else {
    if i0.value != 0 { ok = false; }
  }
  var r1 = mysql_reader_new(hb("fcfb00"));
  let i1 = mysql_read_lenenc_int(&mut r1);
  if !i1.is_ok { ok = false; } else {
    if i1.value != 251 { ok = false; }
  }
  var r2 = mysql_reader_new(hb("fd000001"));
  let i2 = mysql_read_lenenc_int(&mut r2);
  if !i2.is_ok { ok = false; } else {
    if i2.value != 65536 { ok = false; }
  }
  var r3 = mysql_reader_new(hb("fe0000000100000000"));
  let i3 = mysql_read_lenenc_int(&mut r3);
  if !i3.is_ok { ok = false; } else {
    if i3.value != 16777216 { ok = false; }
  }
  var r4 = mysql_reader_new(hb("feffffffffffffff7f"));
  let i4 = mysql_read_lenenc_int(&mut r4);
  if !i4.is_ok { ok = false; } else {
    if i4.value != 9223372036854775807 { ok = false; }
  }
  var rn = mysql_reader_new(hb("fb"));
  let nn = mysql_read_lenenc_int_nullable(&mut rn);
  if !nn.is_ok { ok = false; } else {
    let l: MysqlLenenc = nn.value;
    if !mysql_lenenc_is_null(&l) { ok = false; }
    if mysql_lenenc_value(&l) != 0 { ok = false; }
  }
  if !err_is_i(mysql_read_lenenc_int(&mut mysql_reader_new(hb("fb"))), "mysql: null length-encoded integer at offset 0") { ok = false; }
  if !err_is_i(mysql_read_lenenc_int(&mut mysql_reader_new(hb("ff"))), "mysql: invalid length-encoded first byte 255 at offset 0") { ok = false; }
  if !err_is_i(mysql_read_lenenc_int(&mut mysql_reader_new(hb("fc00"))), "mysql: truncated input at offset 1") { ok = false; }
  if !err_is_i(mysql_read_lenenc_int(&mut mysql_reader_new(hb("fd0000"))), "mysql: truncated input at offset 1") { ok = false; }
  if !err_is_i(mysql_read_lenenc_int(&mut mysql_reader_new(hb("fe00000000000000"))), "mysql: truncated input at offset 1") { ok = false; }
  if !err_is_i(mysql_read_lenenc_int(&mut mysql_reader_new(hb("fe0000000000000080"))), "mysql: 64-bit length-encoded value out of range at offset 1") { ok = false; }
  if !err_is_i(mysql_read_lenenc_int(&mut mysql_reader_new(hb(""))), "mysql: truncated input at offset 0") { ok = false; }
  if !err_is_lenenc(mysql_read_lenenc_int_nullable(&mut mysql_reader_new(hb("ff"))), "mysql: invalid length-encoded first byte 255 at offset 0") { ok = false; }
  var wh = mysql_writer_new();
  if !err_is_b(mysql_write_lenenc_int(&mut wh, -1), "mysql: bad length-encoded integer -1") { ok = false; }
  return assert(ok, "length-encoded integer boundary encodings, nullable marker and rejection offsets");
}

fn t4() -> TestResult {
  var ok = true;
  var w = mysql_writer_new();
  let wr = mysql_write_lenenc_str(&mut w, "abc");
  if !wr.is_ok { ok = false; }
  let b: Vec[UInt8] = wbytes(&w);
  if !str_is(hex.hex_encode(&b), "03616263") { ok = false; }
  var r = mysql_reader_new(b);
  let sr = mysql_read_lenenc_str(&mut r);
  if !sr.is_ok { ok = false; } else {
    if !str_is(sr.value, "abc") { ok = false; }
  }
  var we = mysql_writer_new();
  let wre = mysql_write_lenenc_str(&mut we, "");
  if !wre.is_ok { ok = false; }
  let eb: Vec[UInt8] = wbytes(&we);
  if !str_is(hex.hex_encode(&eb), "00") { ok = false; }
  var re = mysql_reader_new(eb);
  let sre = mysql_read_lenenc_str(&mut re);
  if !sre.is_ok { ok = false; } else {
    if !str_is(sre.value, "") { ok = false; }
  }
  var wn = mysql_writer_new();
  mysql_write_lenenc_null(&mut wn);
  let nb: Vec[UInt8] = wbytes(&wn);
  if !str_is(hex.hex_encode(&nb), "fb") { ok = false; }
  if !err_is_s(mysql_read_lenenc_str(&mut mysql_reader_new(hb("fb"))), "mysql: null length-encoded string at offset 0") { ok = false; }
  if !err_is_s(mysql_read_lenenc_str(&mut mysql_reader_new(hb("0a61"))), "mysql: truncated input at offset 1") { ok = false; }
  if !err_is_s(mysql_read_lenenc_str(&mut mysql_reader_new(hb("01ff"))), "mysql: invalid utf-8") { ok = false; }
  if !err_is_s(mysql_read_lenenc_str(&mut mysql_reader_new(hb("0100"))), "mysql: string contains nul") { ok = false; }
  var wb = mysql_writer_new();
  let raw = hb("00ff");
  mysql_write_lenenc_bytes(&mut wb, &raw);
  let bb: Vec[UInt8] = wbytes(&wb);
  if !str_is(hex.hex_encode(&bb), "0200ff") { ok = false; }
  var rb = mysql_reader_new(bb);
  let br = mysql_read_lenenc_bytes(&mut rb);
  if !br.is_ok { ok = false; } else {
    let got: Vec[UInt8] = br.value;
    if !bytes_equal(got, raw) { ok = false; }
  }
  if !err_is_bts(mysql_read_lenenc_bytes(&mut mysql_reader_new(hb("fb"))), "mysql: null length-encoded string at offset 0") { ok = false; }
  if !err_is_bts(mysql_read_lenenc_bytes(&mut mysql_reader_new(hb("05aa"))), "mysql: truncated input at offset 1") { ok = false; }
  return assert(ok, "length-encoded string/bytes round-trip, null marker and validation errors");
}

fn t5() -> TestResult {
  var ok = true;
  var r = mysql_reader_new(hb(hs_hex()));
  let hr = mysql_read_handshake(&mut r);
  if !hr.is_ok { ok = false; } else {
    let h: MysqlHandshake = hr.value;
    if mysql_handshake_protocol_version(&h) != 10 { ok = false; }
    if !str_is(mysql_handshake_server_version(&h), "8.0.35") { ok = false; }
    if mysql_handshake_connection_id(&h) != 12345 { ok = false; }
    if mysql_handshake_capability_flags(&h) != 1606144 { ok = false; }
    if !mysql_handshake_has_capability(&h, mysql_capability_protocol_41()) { ok = false; }
    if !mysql_handshake_has_capability(&h, mysql_capability_secure_connection()) { ok = false; }
    if !mysql_handshake_has_capability(&h, mysql_capability_plugin_auth()) { ok = false; }
    if !mysql_handshake_has_capability(&h, mysql_capability_connect_attrs()) { ok = false; }
    if mysql_handshake_has_capability(&h, mysql_capability_ssl()) { ok = false; }
    if mysql_handshake_character_set(&h) != 45 { ok = false; }
    if mysql_handshake_status_flags(&h) != 2 { ok = false; }
    if mysql_handshake_auth_plugin_data_len(&h) != 21 { ok = false; }
    let p1: Vec[UInt8] = mysql_handshake_auth_plugin_data_1(&h);
    if !str_is(hex.hex_encode(&p1), "0102030405060708") { ok = false; }
    let p2: Vec[UInt8] = mysql_handshake_auth_plugin_data_2(&h);
    if p2.len() != 13 { ok = false; }
    let combo: Vec[UInt8] = mysql_handshake_auth_plugin_data(&h);
    if combo.len() != 20 { ok = false; }
    let first: Int = (combo[0] as Int) & 0xFF;
    let last: Int = (combo[19] as Int) & 0xFF;
    if first != 1 { ok = false; }
    if last != 20 { ok = false; }
    if !str_is(mysql_handshake_auth_plugin_name(&h), "caching_sha2_password") { ok = false; }
  }
  if mysql_reader_remaining(&r) != 0 { ok = false; }
  if !err_is_handshake(mysql_read_handshake(&mut mysql_reader_new(hb("09"))), "mysql: unsupported protocol version 9 at offset 0") { ok = false; }
  if !err_is_handshake(mysql_read_handshake(&mut mysql_reader_new(hb("0a"))), "mysql: unterminated string at offset 1") { ok = false; }
  if !err_is_handshake(mysql_read_handshake(&mut mysql_reader_new(hb(""))), "mysql: truncated input at offset 0") { ok = false; }
  let short = "0a" + "382e302e333500" + "39300000";
  if !err_is_handshake(mysql_read_handshake(&mut mysql_reader_new(hb(short))), "mysql: truncated input at offset 12") { ok = false; }
  return assert(ok, "handshake v10 decode: fields, capability bits, auth data combo and errors");
}

fn t6() -> TestResult {
  var ok = true;
  let h: MysqlHandshake = mk_hs();
  var w = mysql_writer_new();
  let wr = mysql_write_handshake(&mut w, &h);
  if !wr.is_ok { ok = false; }
  let b: Vec[UInt8] = wbytes(&w);
  if !str_is(hex.hex_encode(&b), hs_hex()) { ok = false; }
  var r = mysql_reader_new(b);
  let hr = mysql_read_handshake(&mut r);
  if !hr.is_ok { ok = false; } else {
    let h2: MysqlHandshake = hr.value;
    if mysql_handshake_connection_id(&h2) != 12345 { ok = false; }
    if !str_is(mysql_handshake_auth_plugin_name(&h2), "caching_sha2_password") { ok = false; }
    let p2: Vec[UInt8] = mysql_handshake_auth_plugin_data_2(&h2);
    if p2.len() != 13 { ok = false; }
  }
  var bad1 = mk_hs();
  bad1.protocol_version = 9;
  var wb1 = mysql_writer_new();
  if !err_is_b(mysql_write_handshake(&mut wb1, &bad1), "mysql: unsupported protocol version 9") { ok = false; }
  var bad2 = mk_hs();
  var short1 = Vec[UInt8].new();
  short1.push(1);
  short1.push(2);
  short1.push(3);
  bad2.auth_plugin_data_1 = short1;
  var wb2 = mysql_writer_new();
  if !err_is_b(mysql_write_handshake(&mut wb2, &bad2), "mysql: bad auth plugin data part 1 length 3") { ok = false; }
  var bad3 = mk_hs();
  bad3.capability_flags = -1;
  var wb3 = mysql_writer_new();
  if !err_is_b(mysql_write_handshake(&mut wb3, &bad3), "mysql: bad capability flags -1") { ok = false; }
  return assert(ok, "handshake v10 writer is byte-exact and validates version, auth data part 1 and flags");
}

fn t7() -> TestResult {
  var ok = true;
  let resp: MysqlHandshakeResponse = mk_resp_lenenc();
  var w = mysql_writer_new();
  let wr = mysql_write_handshake_response(&mut w, &resp);
  if !wr.is_ok { ok = false; }
  let b: Vec[UInt8] = wbytes(&w);
  let zeros23 = string.str_repeat("00", 23);
  let plugin_hex = "63616368696e675f736861325f70617373776f7264";
  let expected = "08023800" + "00000001" + "ff" + zeros23 + "726f6f7400" + "02aabb" + "7465737400" + plugin_hex + "00" + "08" + "0161013101620132";
  if !str_is(hex.hex_encode(&b), expected) { ok = false; }
  var r = mysql_reader_new(b);
  let rr = mysql_read_handshake_response(&mut r);
  if !rr.is_ok { ok = false; } else {
    let h: MysqlHandshakeResponse = rr.value;
    if mysql_response_capability_flags(&h) != 3670536 { ok = false; }
    if mysql_response_max_packet_size(&h) != 16777216 { ok = false; }
    if mysql_response_character_set(&h) != 255 { ok = false; }
    if !str_is(mysql_response_username(&h), "root") { ok = false; }
    if mysql_response_auth_kind(&h) != 3 { ok = false; }
    let auth: Vec[UInt8] = mysql_response_auth_response(&h);
    if !str_is(hex.hex_encode(&auth), "aabb") { ok = false; }
    if !str_is(mysql_response_database(&h), "test") { ok = false; }
    if !str_is(mysql_response_auth_plugin_name(&h), "caching_sha2_password") { ok = false; }
    if mysql_response_attr_count(&h) != 2 { ok = false; }
    if !str_is(mysql_response_attr_name(&h, 0), "a") { ok = false; }
    if !str_is(mysql_response_attr_value_at(&h, 0), "1") { ok = false; }
    if !str_is(mysql_response_attr_value_at(&h, 999), "") { ok = false; }
    if !str_is(mysql_response_attr_value(&h, "b"), "2") { ok = false; }
    if !str_is(mysql_response_attr_value(&h, "zz"), "") { ok = false; }
    if !str_is(mysql_response_attr_name(&h, -1), "") { ok = false; }
  }
  if mysql_reader_remaining(&r) != 0 { ok = false; }
  return assert(ok, "handshake response 41 (lenenc auth, db, plugin, attrs) is byte-exact and round-trips");
}

fn t8() -> TestResult {
  var ok = true;
  var auth20 = Vec[UInt8].new();
  var i = 1;
  while i <= 20 {
    auth20.push(i as UInt8);
    i = i + 1;
  }
  var secure = MysqlHandshakeResponse{ capability_flags: 33280; max_packet_size: 16777216; character_set: 45; username: "u"; auth_response_kind: 2; auth_response: auth20; database: ""; auth_plugin_name: ""; attr_names: Vec[Str].new(); attr_values: Vec[Str].new(); };
  var ws = mysql_writer_new();
  let wrs = mysql_write_handshake_response(&mut ws, &secure);
  if !wrs.is_ok { ok = false; }
  let bs: Vec[UInt8] = wbytes(&ws);
  if !str_is(hex.hex_encode(&bs), "00820000" + "00000001" + "2d" + string.str_repeat("00", 23) + "7500" + "14" + "0102030405060708090a0b0c0d0e0f1011121314") { ok = false; }
  var rs = mysql_reader_new(bs);
  let rrs = mysql_read_handshake_response(&mut rs);
  if !rrs.is_ok { ok = false; } else {
    let h: MysqlHandshakeResponse = rrs.value;
    if mysql_response_auth_kind(&h) != 2 { ok = false; }
    let a: Vec[UInt8] = mysql_response_auth_response(&h);
    if !bytes_equal(a, auth20) { ok = false; }
  }
  var token = Vec[UInt8].new();
  token.push(116);
  token.push(111);
  token.push(107);
  token.push(101);
  token.push(110);
  var nulv = MysqlHandshakeResponse{ capability_flags: 512; max_packet_size: 1024; character_set: 33; username: "u"; auth_response_kind: 1; auth_response: token; database: ""; auth_plugin_name: ""; attr_names: Vec[Str].new(); attr_values: Vec[Str].new(); };
  var wn = mysql_writer_new();
  let wrn = mysql_write_handshake_response(&mut wn, &nulv);
  if !wrn.is_ok { ok = false; }
  let bn: Vec[UInt8] = wbytes(&wn);
  if !str_is(hex.hex_encode(&bn), "00020000" + "00040000" + "21" + string.str_repeat("00", 23) + "7500" + "746f6b656e00") { ok = false; }
  var rn = mysql_reader_new(bn);
  let rrn = mysql_read_handshake_response(&mut rn);
  if !rrn.is_ok { ok = false; } else {
    let h2: MysqlHandshakeResponse = rrn.value;
    if mysql_response_auth_kind(&h2) != 1 { ok = false; }
    let a2: Vec[UInt8] = mysql_response_auth_response(&h2);
    if !bytes_equal(a2, token) { ok = false; }
  }
  var mismatch = nulv;
  mismatch.auth_response_kind = 3;
  var wm = mysql_writer_new();
  if !err_is_b(mysql_write_handshake_response(&mut wm, &mismatch), "mysql: handshake response auth kind 3 does not match capability flags") { ok = false; }
  var big = Vec[UInt8].new();
  var j = 0;
  while j < 300 {
    big.push(65);
    j = j + 1;
  }
  var toobig = MysqlHandshakeResponse{ capability_flags: 32768; max_packet_size: 1024; character_set: 33; username: "u"; auth_response_kind: 2; auth_response: big; database: ""; auth_plugin_name: ""; attr_names: Vec[Str].new(); attr_values: Vec[Str].new(); };
  var wbg = mysql_writer_new();
  if !err_is_b(mysql_write_handshake_response(&mut wbg, &toobig), "mysql: auth response length 300 exceeds 255") { ok = false; }
  var an = Vec[Str].new();
  an.push("a");
  var av = Vec[Str].new();
  var attrbad = MysqlHandshakeResponse{ capability_flags: 32768; max_packet_size: 1024; character_set: 33; username: "u"; auth_response_kind: 2; auth_response: auth20; database: ""; auth_plugin_name: ""; attr_names: an; attr_values: av; };
  var wab = mysql_writer_new();
  if !err_is_b(mysql_write_handshake_response(&mut wab, &attrbad), "mysql: connect attrs name/value count mismatch") { ok = false; }
  var wextra = mysql_writer_new();
  mysql_write_bytes(&mut wextra, &bn);
  mysql_write_u8(&mut wextra, 0);
  if !err_is_response(mysql_read_handshake_response(&mut mysql_reader_new(wbytes(&wextra))), "mysql: trailing bytes at offset 40") { ok = false; }
  return assert(ok, "handshake response secure/NUL auth variants, byte layout and writer validation errors");
}

fn t9() -> TestResult {
  var ok = true;
  var w = mysql_writer_new();
  mysql_write_ssl_request(&mut w, 2560, 16777216, 45);
  let b: Vec[UInt8] = wbytes(&w);
  if b.len() != 32 { ok = false; }
  let zeros23 = string.str_repeat("00", 23);
  if !str_is(hex.hex_encode(&b), "000a0000" + "00000001" + "2d" + zeros23) { ok = false; }
  if !mysql_is_ssl_request_payload(&b) { ok = false; }
  var r = mysql_reader_new(b);
  let sr = mysql_read_ssl_request(&mut r);
  if !sr.is_ok { ok = false; } else {
    let s: MysqlSslRequest = sr.value;
    if mysql_ssl_request_capability_flags(&s) != 2560 { ok = false; }
    if mysql_ssl_request_max_packet_size(&s) != 16777216 { ok = false; }
    if mysql_ssl_request_character_set(&s) != 45 { ok = false; }
  }
  var nos = mysql_writer_new();
  mysql_write_ssl_request(&mut nos, 512, 1024, 45);
  let nb: Vec[UInt8] = wbytes(&nos);
  if mysql_is_ssl_request_payload(&nb) { ok = false; }
  if !err_is_ssl(mysql_read_ssl_request(&mut mysql_reader_new(nb)), "mysql: ssl request without CLIENT_SSL at offset 0") { ok = false; }
  let short = hb("000a0000" + "00000001" + "2d" + string.str_repeat("00", 22));
  if !err_is_ssl(mysql_read_ssl_request(&mut mysql_reader_new(short)), "mysql: bad ssl request length 31 at offset 0") { ok = false; }
  var ws = mysql_writer_new();
  mysql_write_ssl_request(&mut ws, 2560, 16777216, 45);
  if !err_is_response(mysql_read_handshake_response(&mut mysql_reader_new(wbytes(&ws))), "mysql: unterminated string at offset 32") { ok = false; }
  return assert(ok, "32-byte SSL request: exact bytes, detection, field decode and errors");
}

fn t10() -> TestResult {
  var ok = true;
  var r = mysql_reader_new(hb("00000002000000"));
  let orr = mysql_read_ok(&mut r);
  if !orr.is_ok { ok = false; } else {
    let o: MysqlOk = orr.value;
    if mysql_ok_affected_rows(&o) != 0 { ok = false; }
    if mysql_ok_last_insert_id(&o) != 0 { ok = false; }
    if mysql_ok_status_flags(&o) != 2 { ok = false; }
    if mysql_ok_warnings(&o) != 0 { ok = false; }
    if !str_is(mysql_ok_info(&o), "") { ok = false; }
  }
  var r2 = mysql_reader_new(hb("00" + "fcfb00" + "01" + "0200" + "0100" + "6869"));
  let orr2 = mysql_read_ok(&mut r2);
  if !orr2.is_ok { ok = false; } else {
    let o2: MysqlOk = orr2.value;
    if mysql_ok_affected_rows(&o2) != 251 { ok = false; }
    if mysql_ok_last_insert_id(&o2) != 1 { ok = false; }
    if mysql_ok_status_flags(&o2) != 2 { ok = false; }
    if mysql_ok_warnings(&o2) != 1 { ok = false; }
    if !str_is(mysql_ok_info(&o2), "hi") { ok = false; }
  }
  var okv = MysqlOk{ affected_rows: 251; last_insert_id: 1; status_flags: 2; warnings: 1; info: "hi"; };
  var w = mysql_writer_new();
  let wr = mysql_write_ok(&mut w, &okv);
  if !wr.is_ok { ok = false; }
  let b: Vec[UInt8] = wbytes(&w);
  if !str_is(hex.hex_encode(&b), "00" + "fcfb00" + "01" + "0200" + "0100" + "6869") { ok = false; }
  var neg = MysqlOk{ affected_rows: -1; last_insert_id: 0; status_flags: 0; warnings: 0; info: ""; };
  var wn = mysql_writer_new();
  if !err_is_b(mysql_write_ok(&mut wn, &neg), "mysql: bad length-encoded integer -1") { ok = false; }
  if !err_is_okp(mysql_read_ok(&mut mysql_reader_new(hb("01"))), "mysql: not an OK packet (first byte 1) at offset 0") { ok = false; }
  if !err_is_okp(mysql_read_ok(&mut mysql_reader_new(hb("0000"))), "mysql: truncated input at offset 2") { ok = false; }
  return assert(ok, "OK packet 0x00: exact bytes, lenenc counters, info and error paths");
}

fn t11() -> TestResult {
  var ok = true;
  let errhex = "ff0404" + "234859303030" + "546f6f206d616e7920636f6e6e656374696f6e73";
  var r = mysql_reader_new(hb(errhex));
  let er = mysql_read_err(&mut r);
  if !er.is_ok { ok = false; } else {
    let e: MysqlErr = er.value;
    if mysql_err_code(&e) != 1028 { ok = false; }
    if !mysql_err_has_sqlstate(&e) { ok = false; }
    if !str_is(mysql_err_sqlstate(&e), "HY000") { ok = false; }
    if !str_is(mysql_err_message(&e), "Too many connections") { ok = false; }
  }
  var r2 = mysql_reader_new(hb("ff0404" + "626164"));
  let er2 = mysql_read_err(&mut r2);
  if !er2.is_ok { ok = false; } else {
    let e2: MysqlErr = er2.value;
    if mysql_err_code(&e2) != 1028 { ok = false; }
    if mysql_err_has_sqlstate(&e2) { ok = false; }
    if !str_is(mysql_err_sqlstate(&e2), "") { ok = false; }
    if !str_is(mysql_err_message(&e2), "bad") { ok = false; }
  }
  var ev = MysqlErr{ code: 1028; has_sqlstate: true; sqlstate: "HY000"; message: "Too many connections"; };
  var w = mysql_writer_new();
  let wr = mysql_write_err(&mut w, &ev);
  if !wr.is_ok { ok = false; }
  let b: Vec[UInt8] = wbytes(&w);
  if !str_is(hex.hex_encode(&b), errhex) { ok = false; }
  var ev2 = MysqlErr{ code: 1028; has_sqlstate: false; sqlstate: ""; message: "bad"; };
  var w2 = mysql_writer_new();
  let wr2 = mysql_write_err(&mut w2, &ev2);
  if !wr2.is_ok { ok = false; }
  let b2: Vec[UInt8] = wbytes(&w2);
  if !str_is(hex.hex_encode(&b2), "ff0404626164") { ok = false; }
  var evbad = MysqlErr{ code: 1; has_sqlstate: true; sqlstate: "HY00"; message: "x"; };
  var w3 = mysql_writer_new();
  if !err_is_b(mysql_write_err(&mut w3, &evbad), "mysql: bad sqlstate length 4") { ok = false; }
  if !err_is_errp(mysql_read_err(&mut mysql_reader_new(hb("00"))), "mysql: not an ERR packet (first byte 0) at offset 0") { ok = false; }
  if !err_is_errp(mysql_read_err(&mut mysql_reader_new(hb("ff04"))), "mysql: truncated input at offset 1") { ok = false; }
  if !err_is_errp(mysql_read_err(&mut mysql_reader_new(hb("ff0404236162"))), "mysql: truncated input at offset 4") { ok = false; }
  return assert(ok, "ERR packet 0xFF: code, SQLSTATE marker, message and error paths");
}

fn t12() -> TestResult {
  var ok = true;
  var r = mysql_reader_new(hb("fe01000200"));
  let er = mysql_read_eof(&mut r);
  if !er.is_ok { ok = false; } else {
    let e: MysqlEof = er.value;
    if mysql_eof_warnings(&e) != 1 { ok = false; }
    if mysql_eof_status_flags(&e) != 2 { ok = false; }
  }
  var ev = MysqlEof{ warnings: 1; status_flags: 2; };
  var w = mysql_writer_new();
  mysql_write_eof(&mut w, &ev);
  let b: Vec[UInt8] = wbytes(&w);
  if !str_is(hex.hex_encode(&b), "fe01000200") { ok = false; }
  var rt = mysql_reader_new(hb("fe01000200ff"));
  if !err_is_eofp(mysql_read_eof(&mut rt), "mysql: trailing bytes at offset 5") { ok = false; }
  var rn = mysql_reader_new(hb("00"));
  if !err_is_eofp(mysql_read_eof(&mut rn), "mysql: not an EOF packet (first byte 0) at offset 0") { ok = false; }
  let empty = Vec[UInt8].new();
  if mysql_packet_kind(&empty) != 6 { ok = false; }
  let k_ok = hb("00");
  if mysql_packet_kind(&k_ok) != 0 { ok = false; }
  let k_li = hb("fb78");
  if mysql_packet_kind(&k_li) != 1 { ok = false; }
  let k_eof = hb("fe");
  if mysql_packet_kind(&k_eof) != 2 { ok = false; }
  let k_err = hb("ff00");
  if mysql_packet_kind(&k_err) != 3 { ok = false; }
  let k_l8 = hb("fe000000000000000000");
  if mysql_packet_kind(&k_l8) != 4 { ok = false; }
  let k_oth = hb("03616263");
  if mysql_packet_kind(&k_oth) != 5 { ok = false; }
  if !str_is(mysql_packet_kind_name(0), "OK") { ok = false; }
  if !str_is(mysql_packet_kind_name(1), "LOCAL_INFILE") { ok = false; }
  if !str_is(mysql_packet_kind_name(2), "EOF") { ok = false; }
  if !str_is(mysql_packet_kind_name(3), "ERR") { ok = false; }
  if !str_is(mysql_packet_kind_name(4), "LENENC_8") { ok = false; }
  if !str_is(mysql_packet_kind_name(5), "OTHER") { ok = false; }
  if !str_is(mysql_packet_kind_name(6), "EMPTY") { ok = false; }
  if !str_is(mysql_packet_kind_name(7), "UNKNOWN") { ok = false; }
  if mysql_binary_row_marker() != 0 { ok = false; }
  let brh = hb("0000");
  if !mysql_is_binary_row_header(&brh) { ok = false; }
  let brh2 = hb("01");
  if mysql_is_binary_row_header(&brh2) { ok = false; }
  if mysql_is_binary_row_header(&empty) { ok = false; }
  var lr = mysql_reader_new(hb("fb2f746d702f782e637376"));
  let lrr = mysql_read_local_infile(&mut lr);
  if !lrr.is_ok { ok = false; } else {
    if !str_is(lrr.value, "/tmp/x.csv") { ok = false; }
  }
  let lp = hb("fb2f746d702f782e637376");
  let fnr = mysql_local_infile_filename(&lp);
  if !fnr.is_ok { ok = false; } else {
    if !str_is(fnr.value, "/tmp/x.csv") { ok = false; }
  }
  let nlp = hb("03616263");
  if !err_is_s(mysql_local_infile_filename(&nlp), "mysql: not a LOCAL INFILE packet (first byte 3) at offset 0") { ok = false; }
  return assert(ok, "EOF packet, context-free packet kinds and LOCAL INFILE filename");
}

fn t13() -> TestResult {
  var ok = true;
  var r1 = mysql_reader_new(hb("03"));
  let c1 = mysql_read_column_count(&mut r1);
  if !c1.is_ok { ok = false; } else {
    if c1.value != 3 { ok = false; }
  }
  var r2 = mysql_reader_new(hb("fc0001"));
  let c2 = mysql_read_column_count(&mut r2);
  if !c2.is_ok { ok = false; } else {
    if c2.value != 256 { ok = false; }
  }
  var r3 = mysql_reader_new(hb("00"));
  if !err_is_i(mysql_read_column_count(&mut r3), "mysql: bad column count 0 at offset 0") { ok = false; }
  var r4 = mysql_reader_new(hb("fb"));
  if !err_is_i(mysql_read_column_count(&mut r4), "mysql: null length-encoded integer at offset 0") { ok = false; }
  var w1 = mysql_writer_new();
  let wc1 = mysql_write_column_count(&mut w1, 3);
  if !wc1.is_ok { ok = false; }
  let cb: Vec[UInt8] = wbytes(&w1);
  if !str_is(hex.hex_encode(&cb), "03") { ok = false; }
  var w2 = mysql_writer_new();
  if !err_is_b(mysql_write_column_count(&mut w2, 0), "mysql: bad column count 0") { ok = false; }
  let colhex = "036465660000000161000c2d000b000000030000000000";
  var rc = mysql_reader_new(hb(colhex));
  let colr = mysql_read_column_definition(&mut rc);
  if !colr.is_ok { ok = false; } else {
    let c: MysqlColumn = colr.value;
    if !str_is(mysql_column_catalog(&c), "def") { ok = false; }
    if !str_is(mysql_column_schema(&c), "") { ok = false; }
    if !str_is(mysql_column_table(&c), "") { ok = false; }
    if !str_is(mysql_column_org_table(&c), "") { ok = false; }
    if !str_is(mysql_column_name(&c), "a") { ok = false; }
    if !str_is(mysql_column_org_name(&c), "") { ok = false; }
    if mysql_column_charset(&c) != 45 { ok = false; }
    if mysql_column_length(&c) != 11 { ok = false; }
    if mysql_column_type_code(&c) != 3 { ok = false; }
    if !str_is(mysql_column_type_name(&c), "LONG") { ok = false; }
    if mysql_column_flags(&c) != 0 { ok = false; }
    if mysql_column_decimals(&c) != 0 { ok = false; }
  }
  let cdef: MysqlColumn = mk_col();
  var wc = mysql_writer_new();
  let wcr = mysql_write_column_definition(&mut wc, &cdef);
  if !wcr.is_ok { ok = false; }
  let cb2: Vec[UInt8] = wbytes(&wc);
  if !str_is(hex.hex_encode(&cb2), colhex) { ok = false; }
  var rf = mysql_reader_new(hb("03646566000000016100" + "0d" + "2d000b000000030000000000"));
  if !err_is_column(mysql_read_column_definition(&mut rf), "mysql: bad column definition filler 13 at offset 10") { ok = false; }
  var rt = mysql_reader_new(hb(colhex + "00"));
  if !err_is_column(mysql_read_column_definition(&mut rt), "mysql: trailing bytes at offset 23") { ok = false; }
  var ru = mysql_reader_new(hb("01ff0000000161000c2d000b000000030000000000"));
  if !err_is_column(mysql_read_column_definition(&mut ru), "mysql: invalid utf-8") { ok = false; }
  return assert(ok, "column count and column definition packet 41: bytes, fields and errors");
}

fn t14() -> TestResult {
  var ok = true;
  let rowhex = "03616263fb00";
  var r = mysql_reader_new(hb(rowhex));
  let rr = mysql_read_text_row(&mut r, 3);
  if !rr.is_ok { ok = false; } else {
    let row: MysqlTextRow = rr.value;
    if mysql_text_row_cell_count(&row) != 3 { ok = false; }
    if mysql_text_row_null_count(&row) != 1 { ok = false; }
    if mysql_text_row_cell_is_null(&row, 0) { ok = false; }
    if !mysql_text_row_cell_is_null(&row, 1) { ok = false; }
    if mysql_text_row_cell_is_null(&row, 2) { ok = false; }
    if !str_is(mysql_text_row_cell_str(&row, 0), "abc") { ok = false; }
    if !str_is(mysql_text_row_cell_str(&row, 1), "") { ok = false; }
    if !str_is(mysql_text_row_cell_str(&row, 2), "") { ok = false; }
    if mysql_text_row_cell_is_null(&row, 99) { ok = false; }
    if !str_is(mysql_text_row_cell_str(&row, 99), "") { ok = false; }
  }
  var vals = Vec[Str].new();
  vals.push("abc");
  vals.push("");
  vals.push("");
  var nuls = Vec[Bool].new();
  nuls.push(false);
  nuls.push(true);
  nuls.push(false);
  let rowv = MysqlTextRow{ values: vals; nulls: nuls; };
  var w = mysql_writer_new();
  let wr = mysql_write_text_row(&mut w, &rowv);
  if !wr.is_ok { ok = false; }
  let b: Vec[UInt8] = wbytes(&w);
  if !str_is(hex.hex_encode(&b), rowhex) { ok = false; }
  var rt = mysql_reader_new(hb(rowhex));
  if !err_is_row(mysql_read_text_row(&mut rt, 2), "mysql: trailing bytes in text row at offset 5") { ok = false; }
  var rtr = mysql_reader_new(hb(""));
  if !err_is_row(mysql_read_text_row(&mut rtr, 1), "mysql: truncated input at offset 0") { ok = false; }
  var rh = mysql_reader_new(hb("056162"));
  if !err_is_row(mysql_read_text_row(&mut rh, 1), "mysql: truncated input at offset 1") { ok = false; }
  var ri = mysql_reader_new(hb("01ff"));
  if !err_is_row(mysql_read_text_row(&mut ri, 1), "mysql: invalid utf-8") { ok = false; }
  var rn = mysql_reader_new(hb(""));
  if !err_is_row(mysql_read_text_row(&mut rn, -1), "mysql: bad length -1 at offset 0") { ok = false; }
  var vbad = Vec[Str].new();
  vbad.push("a");
  vbad.push("b");
  var nbad = Vec[Bool].new();
  nbad.push(false);
  let rowbad = MysqlTextRow{ values: vbad; nulls: nbad; };
  var wb = mysql_writer_new();
  if !err_is_b(mysql_write_text_row(&mut wb, &rowbad), "mysql: text row cell count mismatch") { ok = false; }
  return assert(ok, "text-protocol row: lenenc cells, NULL marker, parallel vectors and errors");
}

fn t15() -> TestResult {
  var ok = true;
  if mysql_capability_long_password() != 1 { ok = false; }
  if mysql_capability_found_rows() != 2 { ok = false; }
  if mysql_capability_long_flag() != 4 { ok = false; }
  if mysql_capability_connect_with_db() != 8 { ok = false; }
  if mysql_capability_no_schema() != 16 { ok = false; }
  if mysql_capability_compress() != 32 { ok = false; }
  if mysql_capability_odbc() != 64 { ok = false; }
  if mysql_capability_local_files() != 128 { ok = false; }
  if mysql_capability_ignore_space() != 256 { ok = false; }
  if mysql_capability_protocol_41() != 512 { ok = false; }
  if mysql_capability_interactive() != 1024 { ok = false; }
  if mysql_capability_ssl() != 2048 { ok = false; }
  if mysql_capability_ignore_sigpipe() != 4096 { ok = false; }
  if mysql_capability_transactions() != 8192 { ok = false; }
  if mysql_capability_reserved() != 16384 { ok = false; }
  if mysql_capability_secure_connection() != 32768 { ok = false; }
  if mysql_capability_multi_statements() != 65536 { ok = false; }
  if mysql_capability_multi_results() != 131072 { ok = false; }
  if mysql_capability_ps_multi_results() != 262144 { ok = false; }
  if mysql_capability_plugin_auth() != 524288 { ok = false; }
  if mysql_capability_connect_attrs() != 1048576 { ok = false; }
  if mysql_capability_plugin_auth_lenenc_client_data() != 2097152 { ok = false; }
  if mysql_capability_can_handle_expired_passwords() != 4194304 { ok = false; }
  if mysql_capability_session_track() != 8388608 { ok = false; }
  if mysql_capability_deprecate_eof() != 16777216 { ok = false; }
  if !mysql_capabilities_known(33554431) { ok = false; }
  if !mysql_capabilities_known(0) { ok = false; }
  if mysql_capabilities_known(67108863) { ok = false; }
  if mysql_capabilities_known(-1) { ok = false; }
  let caps: Int = mysql_capability_protocol_41() + mysql_capability_ssl();
  if !mysql_capability_set(caps, mysql_capability_ssl()) { ok = false; }
  if mysql_capability_set(caps, mysql_capability_plugin_auth()) { ok = false; }
  if mysql_status_in_trans() != 1 { ok = false; }
  if mysql_status_autocommit() != 2 { ok = false; }
  if mysql_status_more_results_exists() != 8 { ok = false; }
  if mysql_status_no_good_index_used() != 16 { ok = false; }
  if mysql_status_no_index_used() != 32 { ok = false; }
  if mysql_status_cursor_exists() != 64 { ok = false; }
  if mysql_status_last_row_sent() != 128 { ok = false; }
  if mysql_status_db_dropped() != 256 { ok = false; }
  if mysql_status_no_backslash_escapes() != 512 { ok = false; }
  if mysql_status_metadata_changed() != 1024 { ok = false; }
  if mysql_status_query_was_slow() != 2048 { ok = false; }
  if mysql_status_ps_out_params() != 4096 { ok = false; }
  if mysql_status_in_trans_readonly() != 8192 { ok = false; }
  if mysql_status_session_state_changed() != 16384 { ok = false; }
  if !mysql_status_flags_known(32763) { ok = false; }
  if mysql_status_flags_known(32764) { ok = false; }
  if mysql_status_flags_known(-1) { ok = false; }
  return assert(ok, "capability flag table, known mask, status flag table and helpers");
}

fn t16() -> TestResult {
  var ok = true;
  if mysql_type_decimal() != 0 { ok = false; }
  if mysql_type_tiny() != 1 { ok = false; }
  if mysql_type_short() != 2 { ok = false; }
  if mysql_type_long() != 3 { ok = false; }
  if mysql_type_float() != 4 { ok = false; }
  if mysql_type_double() != 5 { ok = false; }
  if mysql_type_null() != 6 { ok = false; }
  if mysql_type_timestamp() != 7 { ok = false; }
  if mysql_type_longlong() != 8 { ok = false; }
  if mysql_type_int24() != 9 { ok = false; }
  if mysql_type_date() != 10 { ok = false; }
  if mysql_type_time() != 11 { ok = false; }
  if mysql_type_datetime() != 12 { ok = false; }
  if mysql_type_year() != 13 { ok = false; }
  if mysql_type_newdate() != 14 { ok = false; }
  if mysql_type_varchar() != 15 { ok = false; }
  if mysql_type_bit() != 16 { ok = false; }
  if mysql_type_timestamp2() != 17 { ok = false; }
  if mysql_type_datetime2() != 18 { ok = false; }
  if mysql_type_time2() != 19 { ok = false; }
  if mysql_type_typed_array() != 20 { ok = false; }
  if mysql_type_json() != 245 { ok = false; }
  if mysql_type_newdecimal() != 246 { ok = false; }
  if mysql_type_enum() != 247 { ok = false; }
  if mysql_type_set() != 248 { ok = false; }
  if mysql_type_tiny_blob() != 249 { ok = false; }
  if mysql_type_medium_blob() != 250 { ok = false; }
  if mysql_type_long_blob() != 251 { ok = false; }
  if mysql_type_blob() != 252 { ok = false; }
  if mysql_type_var_string() != 253 { ok = false; }
  if mysql_type_string() != 254 { ok = false; }
  if mysql_type_geometry() != 255 { ok = false; }
  if !str_is(mysql_type_name(0), "DECIMAL") { ok = false; }
  if !str_is(mysql_type_name(1), "TINY") { ok = false; }
  if !str_is(mysql_type_name(2), "SHORT") { ok = false; }
  if !str_is(mysql_type_name(3), "LONG") { ok = false; }
  if !str_is(mysql_type_name(4), "FLOAT") { ok = false; }
  if !str_is(mysql_type_name(5), "DOUBLE") { ok = false; }
  if !str_is(mysql_type_name(6), "NULL") { ok = false; }
  if !str_is(mysql_type_name(7), "TIMESTAMP") { ok = false; }
  if !str_is(mysql_type_name(8), "LONGLONG") { ok = false; }
  if !str_is(mysql_type_name(9), "INT24") { ok = false; }
  if !str_is(mysql_type_name(10), "DATE") { ok = false; }
  if !str_is(mysql_type_name(11), "TIME") { ok = false; }
  if !str_is(mysql_type_name(12), "DATETIME") { ok = false; }
  if !str_is(mysql_type_name(13), "YEAR") { ok = false; }
  if !str_is(mysql_type_name(14), "NEWDATE") { ok = false; }
  if !str_is(mysql_type_name(15), "VARCHAR") { ok = false; }
  if !str_is(mysql_type_name(16), "BIT") { ok = false; }
  if !str_is(mysql_type_name(17), "TIMESTAMP2") { ok = false; }
  if !str_is(mysql_type_name(18), "DATETIME2") { ok = false; }
  if !str_is(mysql_type_name(19), "TIME2") { ok = false; }
  if !str_is(mysql_type_name(20), "TYPED_ARRAY") { ok = false; }
  if !str_is(mysql_type_name(245), "JSON") { ok = false; }
  if !str_is(mysql_type_name(246), "NEWDECIMAL") { ok = false; }
  if !str_is(mysql_type_name(247), "ENUM") { ok = false; }
  if !str_is(mysql_type_name(248), "SET") { ok = false; }
  if !str_is(mysql_type_name(249), "TINY_BLOB") { ok = false; }
  if !str_is(mysql_type_name(250), "MEDIUM_BLOB") { ok = false; }
  if !str_is(mysql_type_name(251), "LONG_BLOB") { ok = false; }
  if !str_is(mysql_type_name(252), "BLOB") { ok = false; }
  if !str_is(mysql_type_name(253), "VAR_STRING") { ok = false; }
  if !str_is(mysql_type_name(254), "STRING") { ok = false; }
  if !str_is(mysql_type_name(255), "GEOMETRY") { ok = false; }
  if !str_is(mysql_type_name(21), "UNKNOWN") { ok = false; }
  if !str_is(mysql_type_name(244), "UNKNOWN") { ok = false; }
  if !str_is(mysql_type_name(-1), "UNKNOWN") { ok = false; }
  if !mysql_type_known(0) { ok = false; }
  if !mysql_type_known(20) { ok = false; }
  if !mysql_type_known(245) { ok = false; }
  if !mysql_type_known(255) { ok = false; }
  if mysql_type_known(21) { ok = false; }
  if mysql_type_known(244) { ok = false; }
  if mysql_type_known(-1) { ok = false; }
  if mysql_type_known(256) { ok = false; }
  return assert(ok, "full column type table 0x00..0xFF, names and known boundaries");
}

fn t17() -> TestResult {
  var ok = true;
  if mysql_charset_big5_chinese_ci() != 1 { ok = false; }
  if mysql_charset_latin1_swedish_ci() != 8 { ok = false; }
  if mysql_charset_gbk_chinese_ci() != 28 { ok = false; }
  if mysql_charset_utf8_general_ci() != 33 { ok = false; }
  if mysql_charset_utf8mb4_general_ci() != 45 { ok = false; }
  if mysql_charset_utf8mb4_bin() != 46 { ok = false; }
  if mysql_charset_binary() != 63 { ok = false; }
  if mysql_charset_utf8mb4_unicode_ci() != 224 { ok = false; }
  if mysql_charset_utf8mb4_0900_ai_ci() != 255 { ok = false; }
  if !str_is(mysql_charset_name(1), "big5_chinese_ci") { ok = false; }
  if !str_is(mysql_charset_name(8), "latin1_swedish_ci") { ok = false; }
  if !str_is(mysql_charset_name(28), "gbk_chinese_ci") { ok = false; }
  if !str_is(mysql_charset_name(33), "utf8_general_ci") { ok = false; }
  if !str_is(mysql_charset_name(45), "utf8mb4_general_ci") { ok = false; }
  if !str_is(mysql_charset_name(46), "utf8mb4_bin") { ok = false; }
  if !str_is(mysql_charset_name(63), "binary") { ok = false; }
  if !str_is(mysql_charset_name(224), "utf8mb4_unicode_ci") { ok = false; }
  if !str_is(mysql_charset_name(255), "utf8mb4_0900_ai_ci") { ok = false; }
  if !str_is(mysql_charset_name(47), "UNKNOWN") { ok = false; }
  if !mysql_charset_known(45) { ok = false; }
  if !mysql_charset_known(255) { ok = false; }
  if mysql_charset_known(47) { ok = false; }
  if mysql_charset_known(-1) { ok = false; }
  if mysql_com_sleep() != 0 { ok = false; }
  if mysql_com_quit() != 1 { ok = false; }
  if mysql_com_init_db() != 2 { ok = false; }
  if mysql_com_query() != 3 { ok = false; }
  if mysql_com_field_list() != 4 { ok = false; }
  if mysql_com_ping() != 14 { ok = false; }
  if mysql_com_stmt_prepare() != 22 { ok = false; }
  if mysql_com_stmt_execute() != 23 { ok = false; }
  if mysql_com_reset_connection() != 31 { ok = false; }
  if !mysql_command_known(0) { ok = false; }
  if !mysql_command_known(31) { ok = false; }
  if mysql_command_known(32) { ok = false; }
  if mysql_command_known(-1) { ok = false; }
  if !str_is(mysql_command_name(0), "COM_SLEEP") { ok = false; }
  if !str_is(mysql_command_name(1), "COM_QUIT") { ok = false; }
  if !str_is(mysql_command_name(2), "COM_INIT_DB") { ok = false; }
  if !str_is(mysql_command_name(3), "COM_QUERY") { ok = false; }
  if !str_is(mysql_command_name(14), "COM_PING") { ok = false; }
  if !str_is(mysql_command_name(22), "COM_STMT_PREPARE") { ok = false; }
  if !str_is(mysql_command_name(23), "COM_STMT_EXECUTE") { ok = false; }
  if !str_is(mysql_command_name(31), "COM_RESET_CONNECTION") { ok = false; }
  if !str_is(mysql_command_name(32), "UNKNOWN") { ok = false; }
  return assert(ok, "charset subset, command constant table, names and known boundaries");
}

fn t18() -> TestResult {
  var ok = true;
  var wq = mysql_writer_new();
  let wqr = mysql_write_com_query(&mut wq, "SELECT 1");
  if !wqr.is_ok { ok = false; }
  let qb: Vec[UInt8] = wbytes(&wq);
  if !str_is(hex.hex_encode(&qb), "0353454c4543542031") { ok = false; }
  var rq = mysql_reader_new(qb);
  let qr = mysql_read_command(&mut rq);
  if !qr.is_ok { ok = false; } else {
    let c: MysqlCommand = qr.value;
    if mysql_command_code(&c) != 3 { ok = false; }
    if !str_is(mysql_command_arg(&c), "SELECT 1") { ok = false; }
  }
  var wi = mysql_writer_new();
  let wir = mysql_write_com_init_db(&mut wi, "test");
  if !wir.is_ok { ok = false; }
  let ib: Vec[UInt8] = wbytes(&wi);
  if !str_is(hex.hex_encode(&ib), "0274657374") { ok = false; }
  var ri = mysql_reader_new(ib);
  let ir = mysql_read_command(&mut ri);
  if !ir.is_ok { ok = false; } else {
    let c2: MysqlCommand = ir.value;
    if mysql_command_code(&c2) != 2 { ok = false; }
    if !str_is(mysql_command_arg(&c2), "test") { ok = false; }
  }
  var wquit = mysql_writer_new();
  mysql_write_com_quit(&mut wquit);
  let quitb: Vec[UInt8] = wbytes(&wquit);
  if !str_is(hex.hex_encode(&quitb), "01") { ok = false; }
  var rquit = mysql_reader_new(quitb);
  let qur = mysql_read_command(&mut rquit);
  if !qur.is_ok { ok = false; } else {
    let c3: MysqlCommand = qur.value;
    if mysql_command_code(&c3) != 1 { ok = false; }
    if !str_is(mysql_command_arg(&c3), "") { ok = false; }
  }
  var wping = mysql_writer_new();
  mysql_write_com_ping(&mut wping);
  let pingb: Vec[UInt8] = wbytes(&wping);
  if !str_is(hex.hex_encode(&pingb), "0e") { ok = false; }
  var rping = mysql_reader_new(pingb);
  let pr = mysql_read_command(&mut rping);
  if !pr.is_ok { ok = false; } else {
    let c4: MysqlCommand = pr.value;
    if mysql_command_code(&c4) != 14 { ok = false; }
  }
  var wp = mysql_writer_new();
  let wpr = mysql_write_com_stmt_prepare(&mut wp, "SELECT ?");
  if !wpr.is_ok { ok = false; }
  let pb: Vec[UInt8] = wbytes(&wp);
  var rp = mysql_reader_new(pb);
  let ppr = mysql_read_command(&mut rp);
  if !ppr.is_ok { ok = false; } else {
    let c5: MysqlCommand = ppr.value;
    if mysql_command_code(&c5) != 22 { ok = false; }
    if !str_is(mysql_command_arg(&c5), "SELECT ?") { ok = false; }
  }
  var rt = mysql_reader_new(hb("0100"));
  if !err_is_command(mysql_read_command(&mut rt), "mysql: unexpected trailing bytes for command 1 at offset 1") { ok = false; }
  var ru = mysql_reader_new(hb("20"));
  let ur = mysql_read_command(&mut ru);
  if !ur.is_ok { ok = false; } else {
    let c6: MysqlCommand = ur.value;
    if mysql_command_code(&c6) != 32 { ok = false; }
  }
  var ru2 = mysql_reader_new(hb("2000"));
  if !err_is_command(mysql_read_command(&mut ru2), "mysql: unexpected trailing bytes for command 32 at offset 1") { ok = false; }
  var rempty = mysql_reader_new(hb(""));
  if !err_is_command(mysql_read_command(&mut rempty), "mysql: truncated input at offset 0") { ok = false; }
  if !str_is(mysql_auth_response_kind_name(0), "NONE") { ok = false; }
  if !str_is(mysql_auth_response_kind_name(1), "NUL_STRING") { ok = false; }
  if !str_is(mysql_auth_response_kind_name(2), "SECURE") { ok = false; }
  if !str_is(mysql_auth_response_kind_name(3), "LENENC") { ok = false; }
  if !str_is(mysql_auth_response_kind_name(4), "UNKNOWN") { ok = false; }
  if mysql_auth_response_kind_none() != 0 { ok = false; }
  if mysql_auth_response_kind_nul_string() != 1 { ok = false; }
  if mysql_auth_response_kind_secure() != 2 { ok = false; }
  if mysql_auth_response_kind_lenenc() != 3 { ok = false; }
  return assert(ok, "command packets (QUERY/INIT_DB/QUIT/PING/STMT_PREPARE) and auth kind table");
}

fn t19() -> TestResult {
  var ok = true;
  var payload = Vec[UInt8].new();
  payload.push(1);
  payload.push(2);
  payload.push(3);
  var w = mysql_writer_new();
  let wr = mysql_write_message(&mut w, &payload, 0);
  if !wr.is_ok { ok = false; } else {
    if wr.value != 1 { ok = false; }
  }
  let b: Vec[UInt8] = wbytes(&w);
  if !str_is(hex.hex_encode(&b), "03000000010203") { ok = false; }
  var r = mysql_reader_new(b);
  let mr = mysql_read_message(&mut r);
  if !mr.is_ok { ok = false; } else {
    let m: MysqlMessage = mr.value;
    if mysql_message_packet_count(&m) != 1 { ok = false; }
    if mysql_message_first_sequence(&m) != 0 { ok = false; }
    if mysql_message_last_sequence(&m) != 0 { ok = false; }
    let mp: Vec[UInt8] = mysql_message_payload(&m);
    if !bytes_equal(mp, payload) { ok = false; }
  }
  let empty = Vec[UInt8].new();
  var w0 = mysql_writer_new();
  let wr0 = mysql_write_message(&mut w0, &empty, 0);
  if !wr0.is_ok { ok = false; } else {
    if wr0.value != 1 { ok = false; }
  }
  let b0: Vec[UInt8] = wbytes(&w0);
  if !str_is(hex.hex_encode(&b0), "00000000") { ok = false; }
  var r0 = mysql_reader_new(b0);
  let mr0 = mysql_read_message(&mut r0);
  if !mr0.is_ok { ok = false; } else {
    let m0: MysqlMessage = mr0.value;
    if mysql_message_packet_count(&m0) != 1 { ok = false; }
    let mp0: Vec[UInt8] = mysql_message_payload(&m0);
    if mp0.len() != 0 { ok = false; }
  }
  var wa = mysql_writer_new();
  let w1 = mysql_write_message(&mut wa, &payload, 0);
  if !w1.is_ok { ok = false; } else {
    let w2 = mysql_write_message(&mut wa, &payload, w1.value);
    if !w2.is_ok { ok = false; }
  }
  var ra = mysql_reader_new(wbytes(&wa));
  let ma1 = mysql_read_message(&mut ra);
  if !ma1.is_ok { ok = false; } else {
    let m1: MysqlMessage = ma1.value;
    if mysql_message_first_sequence(&m1) != 0 { ok = false; }
  }
  let ma2 = mysql_read_message(&mut ra);
  if !ma2.is_ok { ok = false; } else {
    let m2: MysqlMessage = ma2.value;
    if mysql_message_first_sequence(&m2) != 1 { ok = false; }
  }
  var rt = mysql_reader_new(hb("0a0000"));
  if !err_is_message(mysql_read_message(&mut rt), "mysql: truncated input at offset 3") { ok = false; }
  var rt2 = mysql_reader_new(hb("0a000000010203"));
  if !err_is_message(mysql_read_message(&mut rt2), "mysql: truncated input at offset 4") { ok = false; }
  var rt3 = mysql_reader_new(hb("ffffff00"));
  if !err_is_message(mysql_read_message(&mut rt3), "mysql: truncated input at offset 4") { ok = false; }
  return assert(ok, "message reassembly: single, empty, concatenated and truncated messages");
}

fn t20() -> TestResult {
  var ok = true;
  let limit = mysql_max_payload_len();
  if !mysql_packet_is_continuation(limit) { ok = false; }
  if mysql_packet_is_continuation(limit - 1) { ok = false; }
  if mysql_packet_is_continuation(0) { ok = false; }
  var wh = mysql_writer_new();
  let whr = mysql_write_packet_header(&mut wh, limit, 7);
  if !whr.is_ok { ok = false; }
  let hbts: Vec[UInt8] = wbytes(&wh);
  if !str_is(hex.hex_encode(&hbts), "ffffff07") { ok = false; }
  var rh = mysql_reader_new(hbts);
  let rhh = mysql_read_packet_header(&mut rh);
  if !rhh.is_ok { ok = false; } else {
    let h: MysqlPacketHeader = rhh.value;
    if mysql_packet_header_payload_len(&h) != limit { ok = false; }
    if mysql_packet_header_sequence_id(&h) != 7 { ok = false; }
  }
  var rh2 = mysql_reader_new(hb("ffffff07"));
  if !err_is_packet(mysql_read_packet(&mut rh2), "mysql: truncated input at offset 4") { ok = false; }
  var w2 = mysql_writer_new();
  if !err_is_b(mysql_write_packet_header(&mut w2, limit + 1, 0), "mysql: payload length 16777216 exceeds 16777215") { ok = false; }
  var w3 = mysql_writer_new();
  let w3r = mysql_write_packet_header(&mut w3, limit, 255);
  if !w3r.is_ok { ok = false; }
  let seqb: Vec[UInt8] = wbytes(&w3);
  if !str_is(hex.hex_encode(&seqb), "ffffffff") { ok = false; }
  var rmsg = mysql_reader_new(hb("ffffff00"));
  if !err_is_message(mysql_read_message(&mut rmsg), "mysql: truncated input at offset 4") { ok = false; }
  var rpkt = mysql_reader_new(hb("ffffff00"));
  if !err_is_packet(mysql_read_packet(&mut rpkt), "mysql: truncated input at offset 4") { ok = false; }
  return assert(ok, "0xFFFFFF continuation boundary: max header bytes, hostile length and truncation");
}

fn main() -> Int {
  io.println("=== xiom.mysql conformance tests ===");
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
    io.println("xiom.mysql: all tests passed");
  } else {
    io.println("xiom.mysql: tests failed");
  }
  return failed;
}


