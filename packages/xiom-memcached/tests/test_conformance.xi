// XIOM -- xiom.memcached conformance tests (22 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Covers the documented API: text request encoders (storage, retrieval,
// delete, incr/decr, touch, stats, flush_all, version, quit), text request
// parsing with consumed counts and binary-safe data blocks, the single-line
// response statuses and the VALUE/END retrieval response, the text flag
// bits, binary request/response encoders for the 13 supported opcodes,
// binary header/packet parsing with extras validation, the opcode/status/
// extras tables and a catalog of malformed inputs.
//
// Str values are compared with str_compare (BUG 17 discipline), every Vec
// read is bound to a typed local, and Result values are unwrapped through
// match arms that never construct Ok/Err in test code where avoidable.

module memcached_tests
use xiom.io; use xiom.test;
use xiom.memcached;
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

fn append_bytes(out: &mut Vec[UInt8], s: Str) {
  var i = 0;
  while i < s.len() {
    out.push(string.byte_at(s, i));
    i = i + 1;
  }
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

// Encode results unwrapped to bytes ("" on Err); used only for inputs the
// test expects to succeed.
fn enc_ok(r: Result[Vec[UInt8], Str]) -> Vec[UInt8] {
  match r {
    Ok(v) => { return v; },
    Err(_) => {},
  }
  return Vec[UInt8].new();
}

fn cmd_ok(d: Vec[UInt8], off: Int) -> TextCommand {
  match memcached.text_parse_command(&d, off) {
    Ok(c) => { return c; },
    Err(_) => {},
  }
  let ks = Vec[Vec[UInt8]].new();
  let bs = Vec[UInt8].new();
  return TextCommand{ verb: ""; keys: ks; flags: 0; exptime: 0; cas_id: 0; delta: 0; delay: 0; noreply: false; data: bs; arg: ""; consumed: 0 };
}

fn getresp_ok(d: Vec[UInt8], off: Int) -> TextGetResponse {
  match memcached.text_parse_get_response(&d, off) {
    Ok(r) => { return r; },
    Err(_) => {},
  }
  let a = Vec[Vec[UInt8]].new();
  let b = Vec[Int].new();
  let c = Vec[Int].new();
  let e = Vec[UInt8].new();
  let f = Vec[Int].new();
  return TextGetResponse{ keys: a; flags: b; cas: c; pool: e; spans: f; consumed: 0 };
}

fn header_ok(d: Vec[UInt8], off: Int) -> BinHeader {
  match memcached.bin_parse_header(&d, off) {
    Ok(h) => { return h; },
    Err(_) => {},
  }
  return BinHeader{ magic: 0; opcode: -1; key_len: 0; extras_len: 0; data_type: 0; status: 0; total_body: 0; opaque: 0; cas: 0; consumed: 0 };
}

fn packet_ok(d: Vec[UInt8], off: Int) -> BinPacket {
  match memcached.bin_parse_packet(&d, off) {
    Ok(p) => { return p; },
    Err(_) => {},
  }
  let ks = Vec[UInt8].new();
  let ex = Vec[UInt8].new();
  let vl = Vec[UInt8].new();
  return BinPacket{ magic: 0; opcode: -1; key_len: 0; extras_len: 0; data_type: 0; status: 0; opaque: 0; cas: 0; key: ks; extras: ex; value: vl; consumed: 0 };
}

fn setex_ok(r: Result[BinSetExtras, Str]) -> BinSetExtras {
  match r {
    Ok(v) => { return v; },
    Err(_) => {},
  }
  return BinSetExtras{ exptime: -1; flags: -1 };
}

fn dex_ok(r: Result[BinDeltaExtras, Str]) -> BinDeltaExtras {
  match r {
    Ok(v) => { return v; },
    Err(_) => {},
  }
  return BinDeltaExtras{ delta: -1; initial: -1; exptime: -1 };
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

fn err_pair_is(r: Result[(Int, Int), Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_cmd_is(r: Result[TextCommand, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_get_is(r: Result[TextGetResponse, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_header_is(r: Result[BinHeader, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_packet_is(r: Result[BinPacket, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn cmd_key_is(c: &TextCommand, i: Int, want: Str) -> Bool {
  if i < 0 || i >= c.keys.len() {
    return false;
  }
  let ks: Vec[Vec[UInt8]] = c.keys;
  let k: Vec[UInt8] = ks[i];
  return bytes_equal(k, bytes_of(want));
}

fn packet_extras_is(p: &BinPacket, want_hex: Str) -> Bool {
  let ex: Vec[UInt8] = p.extras;
  return bytes_equal(ex, hb(want_hex));
}

fn status_case_is(kw: Str, want_id: Int) -> Bool {
  var d = bytes_of(kw);
  append_bytes(&mut d, "\r\n");
  let r = memcached.text_parse_status(&d, 0);
  if !r.is_ok {
    return false;
  }
  let p = r.value;
  let sid: Int = p.0;
  let nxt: Int = p.1;
  return sid == want_id && nxt == d.len();
}

// ---------------------------------------------------------------------------
// Text protocol: encoders
// ---------------------------------------------------------------------------

fn t1() -> TestResult {
  var ok = true;
  let key = bytes_of("foo");
  let data = bytes_of("bar");
  if !bytes_equal(enc_ok(memcached.text_encode_set(&key, 5, 60, &data, false)), bytes_of("set foo 5 60 3\r\nbar\r\n")) { ok = false; }
  if !bytes_equal(enc_ok(memcached.text_encode_add(&key, 0, 0, &data, false)), bytes_of("add foo 0 0 3\r\nbar\r\n")) { ok = false; }
  if !bytes_equal(enc_ok(memcached.text_encode_replace(&key, 0, 0, &data, true)), bytes_of("replace foo 0 0 3 noreply\r\nbar\r\n")) { ok = false; }
  if !bytes_equal(enc_ok(memcached.text_encode_append(&key, 0, 0, &data, false)), bytes_of("append foo 0 0 3\r\nbar\r\n")) { ok = false; }
  if !bytes_equal(enc_ok(memcached.text_encode_prepend(&key, 0, 0, &data, false)), bytes_of("prepend foo 0 0 3\r\nbar\r\n")) { ok = false; }
  if !bytes_equal(enc_ok(memcached.text_encode_cas(&key, 0, 0, &data, 42, false)), bytes_of("cas foo 0 0 3 42\r\nbar\r\n")) { ok = false; }
  if !bytes_equal(enc_ok(memcached.text_encode_storage("cas", &key, 0, 0, &data, 42, true)), bytes_of("cas foo 0 0 3 42 noreply\r\nbar\r\n")) { ok = false; }
  return assert(ok, "text storage encoders emit canonical CRLF commands with data blocks");
}

fn t2() -> TestResult {
  var ok = true;
  let key = bytes_of("foo");
  let data = bytes_of("bar");
  if !err_bytes_is(memcached.text_encode_storage("store", &key, 0, 0, &data, -1, false), "memcached: bad storage command") { ok = false; }
  let empty = Vec[UInt8].new();
  if !err_bytes_is(memcached.text_encode_storage("set", &empty, 0, 0, &data, -1, false), "memcached: bad key") { ok = false; }
  let long_key = repeat_byte(97, 251);
  if !err_bytes_is(memcached.text_encode_storage("set", &long_key, 0, 0, &data, -1, false), "memcached: bad key") { ok = false; }
  let spaced = bytes_of("a b");
  if !err_bytes_is(memcached.text_encode_storage("set", &spaced, 0, 0, &data, -1, false), "memcached: bad key") { ok = false; }
  if !err_bytes_is(memcached.text_encode_storage("set", &key, -1, 0, &data, -1, false), "memcached: bad flags") { ok = false; }
  if !err_bytes_is(memcached.text_encode_storage("set", &key, 4294967296, 0, &data, -1, false), "memcached: bad flags") { ok = false; }
  if !err_bytes_is(memcached.text_encode_storage("set", &key, 0, -1, &data, -1, false), "memcached: bad exptime") { ok = false; }
  if !err_bytes_is(memcached.text_encode_cas(&key, 0, 0, &data, -1, false), "memcached: bad cas id") { ok = false; }
  if !err_bytes_is(memcached.text_encode_storage("set", &key, 0, 0, &data, 7, false), "memcached: bad cas id") { ok = false; }
  return assert(ok, "text storage encoder validation errors");
}

fn t3() -> TestResult {
  var ok = true;
  var keys = Vec[Vec[UInt8]].new();
  keys.push(bytes_of("foo"));
  keys.push(bytes_of("bar"));
  if !bytes_equal(enc_ok(memcached.text_encode_get(&keys, false)), bytes_of("get foo bar\r\n")) { ok = false; }
  if !bytes_equal(enc_ok(memcached.text_encode_get(&keys, true)), bytes_of("gets foo bar\r\n")) { ok = false; }
  let none = Vec[Vec[UInt8]].new();
  if !err_bytes_is(memcached.text_encode_get(&none, false), "memcached: bad args") { ok = false; }
  var bad = Vec[Vec[UInt8]].new();
  bad.push(bytes_of("a b"));
  if !err_bytes_is(memcached.text_encode_get(&bad, false), "memcached: bad key") { ok = false; }
  var bad2 = Vec[Vec[UInt8]].new();
  bad2.push(repeat_byte(97, 251));
  if !err_bytes_is(memcached.text_encode_get(&bad2, true), "memcached: bad key") { ok = false; }
  return assert(ok, "get/gets encoders and key validation");
}

fn t4() -> TestResult {
  var ok = true;
  let key = bytes_of("foo");
  if !bytes_equal(enc_ok(memcached.text_encode_delete(&key, false)), bytes_of("delete foo\r\n")) { ok = false; }
  if !bytes_equal(enc_ok(memcached.text_encode_delete(&key, true)), bytes_of("delete foo noreply\r\n")) { ok = false; }
  if !bytes_equal(enc_ok(memcached.text_encode_incr(&key, 5, false)), bytes_of("incr foo 5\r\n")) { ok = false; }
  if !bytes_equal(enc_ok(memcached.text_encode_decr(&key, 5, true)), bytes_of("decr foo 5 noreply\r\n")) { ok = false; }
  if !bytes_equal(enc_ok(memcached.text_encode_touch(&key, 30, false)), bytes_of("touch foo 30\r\n")) { ok = false; }
  if !err_bytes_is(memcached.text_encode_delta("mul", &key, 1, false), "memcached: bad delta command") { ok = false; }
  if !err_bytes_is(memcached.text_encode_incr(&key, -1, false), "memcached: bad delta") { ok = false; }
  if !err_bytes_is(memcached.text_encode_touch(&key, -2, false), "memcached: bad exptime") { ok = false; }
  let empty = Vec[UInt8].new();
  if !err_bytes_is(memcached.text_encode_delete(&empty, false), "memcached: bad key") { ok = false; }
  return assert(ok, "delete/incr/decr/touch encoders and errors");
}

fn t5() -> TestResult {
  var ok = true;
  if !bytes_equal(enc_ok(memcached.text_encode_stats("")), bytes_of("stats\r\n")) { ok = false; }
  if !bytes_equal(enc_ok(memcached.text_encode_stats("items")), bytes_of("stats items\r\n")) { ok = false; }
  if !err_bytes_is(memcached.text_encode_stats("a b"), "memcached: bad args") { ok = false; }
  if !bytes_equal(enc_ok(memcached.text_encode_flush_all(-1, false)), bytes_of("flush_all\r\n")) { ok = false; }
  if !bytes_equal(enc_ok(memcached.text_encode_flush_all(0, false)), bytes_of("flush_all 0\r\n")) { ok = false; }
  if !bytes_equal(enc_ok(memcached.text_encode_flush_all(10, true)), bytes_of("flush_all 10 noreply\r\n")) { ok = false; }
  if !err_bytes_is(memcached.text_encode_flush_all(-2, false), "memcached: bad exptime") { ok = false; }
  if !bytes_equal(memcached.text_encode_version(), bytes_of("version\r\n")) { ok = false; }
  if !bytes_equal(memcached.text_encode_quit(), bytes_of("quit\r\n")) { ok = false; }
  return assert(ok, "stats/flush_all/version/quit encoders");
}

fn t6() -> TestResult {
  var ok = true;
  if memcached.text_flags_pack(0, true, false) != 2 { ok = false; }
  if memcached.text_flags_pack(0, false, true) != 4 { ok = false; }
  if memcached.text_flags_pack(0, true, true) != 6 { ok = false; }
  if memcached.text_flags_pack(65532, true, true) != 65538 { ok = false; }
  if !memcached.text_flags_is_compressed(2) { ok = false; }
  if memcached.text_flags_is_compressed(1) { ok = false; }
  if !memcached.text_flags_is_compressed(6) { ok = false; }
  if !memcached.text_flags_is_serialized(4) { ok = false; }
  if memcached.text_flags_is_serialized(3) { ok = false; }
  if !memcached.text_flags_is_serialized(6) { ok = false; }
  if memcached.text_flags_user(2) != 0 { ok = false; }
  if memcached.text_flags_user(4) != 0 { ok = false; }
  if memcached.text_flags_user(6) != 0 { ok = false; }
  if memcached.text_flags_user(7) != 1 { ok = false; }
  if memcached.text_flags_user(5) != 1 { ok = false; }
  if memcached.text_flags_user(65535) != 65529 { ok = false; }
  return assert(ok, "text flag bits pack/decode");
}

// ---------------------------------------------------------------------------
// Text protocol: parsing
// ---------------------------------------------------------------------------

fn t7() -> TestResult {
  var ok = true;
  var buf = bytes_of("set foo 5 60 4\r\n");
  buf.push(1 as UInt8);
  buf.push(13 as UInt8);
  buf.push(10 as UInt8);
  buf.push(0 as UInt8);
  buf.push(13 as UInt8);
  buf.push(10 as UInt8);
  append_bytes(&mut buf, "get x\r\n");
  let c = cmd_ok(buf, 0);
  if !str_eq(c.verb, "set") { ok = false; }
  if c.keys.len() != 1 { ok = false; }
  if !cmd_key_is(&c, 0, "foo") { ok = false; }
  if c.flags != 5 { ok = false; }
  if c.exptime != 60 { ok = false; }
  if c.cas_id != -1 { ok = false; }
  if c.delta != -1 { ok = false; }
  if c.delay != -1 { ok = false; }
  if c.noreply { ok = false; }
  if c.consumed != 22 { ok = false; }
  var want_data = Vec[UInt8].new();
  want_data.push(1 as UInt8);
  want_data.push(13 as UInt8);
  want_data.push(10 as UInt8);
  want_data.push(0 as UInt8);
  let d: Vec[UInt8] = c.data;
  if !bytes_equal(d, want_data) { ok = false; }
  let c2 = cmd_ok(buf, 22);
  if !str_eq(c2.verb, "get") { ok = false; }
  if c2.keys.len() != 1 { ok = false; }
  if c2.consumed != 7 { ok = false; }
  return assert(ok, "parse set with binary-safe data block and consumed stops before trailing command");
}

fn t8() -> TestResult {
  var ok = true;
  let d1 = bytes_of("cas foo 0 0 3 42 noreply\r\nbar\r\n");
  let c1 = cmd_ok(d1, 0);
  if !str_eq(c1.verb, "cas") { ok = false; }
  if c1.cas_id != 42 { ok = false; }
  if !c1.noreply { ok = false; }
  if c1.consumed != d1.len() { ok = false; }
  let c1d: Vec[UInt8] = c1.data;
  if !bytes_equal(c1d, bytes_of("bar")) { ok = false; }
  let d2 = bytes_of("gets a bb ccc\r\n");
  let c2 = cmd_ok(d2, 0);
  if !str_eq(c2.verb, "gets") { ok = false; }
  if c2.keys.len() != 3 { ok = false; }
  if !cmd_key_is(&c2, 0, "a") { ok = false; }
  if !cmd_key_is(&c2, 1, "bb") { ok = false; }
  if !cmd_key_is(&c2, 2, "ccc") { ok = false; }
  if c2.consumed != d2.len() { ok = false; }
  return assert(ok, "parse cas with cas id/noreply and gets with multiple keys");
}

fn t9() -> TestResult {
  var ok = true;
  let d1 = bytes_of("delete k noreply\r\n");
  let c1 = cmd_ok(d1, 0);
  if !str_eq(c1.verb, "delete") { ok = false; }
  if !c1.noreply { ok = false; }
  if !cmd_key_is(&c1, 0, "k") { ok = false; }
  let d2 = bytes_of("incr n 7\r\n");
  let c2 = cmd_ok(d2, 0);
  if !str_eq(c2.verb, "incr") { ok = false; }
  if c2.delta != 7 { ok = false; }
  let d3 = bytes_of("decr n 7 noreply\r\n");
  let c3 = cmd_ok(d3, 0);
  if !str_eq(c3.verb, "decr") { ok = false; }
  if c3.delta != 7 { ok = false; }
  if !c3.noreply { ok = false; }
  let d4 = bytes_of("touch k 30\r\n");
  let c4 = cmd_ok(d4, 0);
  if !str_eq(c4.verb, "touch") { ok = false; }
  if c4.exptime != 30 { ok = false; }
  let d5 = bytes_of("stats items\r\n");
  let c5 = cmd_ok(d5, 0);
  if !str_eq(c5.verb, "stats") { ok = false; }
  if !str_eq(c5.arg, "items") { ok = false; }
  let d6 = bytes_of("stats\r\n");
  let c6 = cmd_ok(d6, 0);
  if !str_eq(c6.arg, "") { ok = false; }
  let d7 = bytes_of("flush_all 10 noreply\r\n");
  let c7 = cmd_ok(d7, 0);
  if !str_eq(c7.verb, "flush_all") { ok = false; }
  if c7.delay != 10 { ok = false; }
  if !c7.noreply { ok = false; }
  let d8 = bytes_of("flush_all\r\n");
  let c8 = cmd_ok(d8, 0);
  if c8.delay != -1 { ok = false; }
  let d9 = bytes_of("version\r\n");
  let c9 = cmd_ok(d9, 0);
  if !str_eq(c9.verb, "version") { ok = false; }
  if c9.consumed != 9 { ok = false; }
  let d10 = bytes_of("quit\r\n");
  let c10 = cmd_ok(d10, 0);
  if !str_eq(c10.verb, "quit") { ok = false; }
  return assert(ok, "parse delete/incr/decr/touch/stats/flush_all/version/quit");
}

fn t10() -> TestResult {
  var ok = true;
  let empty = Vec[UInt8].new();
  if !err_cmd_is(memcached.text_parse_command(&empty, 0), "memcached: truncated line") { ok = false; }
  let d1 = bytes_of("set foo 5 60 3\r\nbar");
  if !err_cmd_is(memcached.text_parse_command(&d1, 0), "memcached: truncated data") { ok = false; }
  let d2 = bytes_of("set foo 5 60 4\r\nbar\r\n");
  if !err_cmd_is(memcached.text_parse_command(&d2, 0), "memcached: truncated data") { ok = false; }
  let d3 = bytes_of("set foo x 60 3\r\nbar\r\n");
  if !err_cmd_is(memcached.text_parse_command(&d3, 0), "memcached: bad integer") { ok = false; }
  let d4 = bytes_of("set foo 5 60 abc\r\nbar\r\n");
  if !err_cmd_is(memcached.text_parse_command(&d4, 0), "memcached: bad integer") { ok = false; }
  let d5 = bytes_of("bogus a\r\n");
  if !err_cmd_is(memcached.text_parse_command(&d5, 0), "memcached: bad command") { ok = false; }
  let d6 = bytes_of("set foo 5 60\r\n");
  if !err_cmd_is(memcached.text_parse_command(&d6, 0), "memcached: bad args") { ok = false; }
  let d7 = bytes_of("set foo 5 60 3\r\nbarXY");
  if !err_cmd_is(memcached.text_parse_command(&d7, 0), "memcached: bad data block") { ok = false; }
  let d8 = bytes_of("set foo 5 60 2000000\r\n");
  if !err_cmd_is(memcached.text_parse_command(&d8, 0), "memcached: bad bytes") { ok = false; }
  let d9 = bytes_of("set foo 5 60 3 7\r\nbar\r\n");
  if !err_cmd_is(memcached.text_parse_command(&d9, 0), "memcached: bad args") { ok = false; }
  let d10 = bytes_of("cas foo 0 0 3\r\nbar\r\n");
  if !err_cmd_is(memcached.text_parse_command(&d10, 0), "memcached: bad args") { ok = false; }
  let d11 = bytes_of("set foo 4294967296 0 0\r\n\r\n");
  if !err_cmd_is(memcached.text_parse_command(&d11, 0), "memcached: bad integer") { ok = false; }
  let d12 = bytes_of("set foo 5 60 3");
  if !err_cmd_is(memcached.text_parse_command(&d12, 0), "memcached: truncated line") { ok = false; }
  var d14 = bytes_of("set ");
  let kk: Vec[UInt8] = repeat_byte(97, 251);
  var ki = 0;
  while ki < kk.len() {
    d14.push(kk[ki]);
    ki = ki + 1;
  }
  append_bytes(&mut d14, " 5 60 0\r\n\r\n");
  if !err_cmd_is(memcached.text_parse_command(&d14, 0), "memcached: bad key") { ok = false; }
  let valid = bytes_of("get x\r\n");
  if !err_cmd_is(memcached.text_parse_command(&valid, -1), "memcached: negative offset") { ok = false; }
  return assert(ok, "text command parse rejects truncation, bad sizes and non-numeric fields");
}

fn t11() -> TestResult {
  var ok = true;
  if !status_case_is("STORED", 1) { ok = false; }
  if !status_case_is("NOT_STORED", 2) { ok = false; }
  if !status_case_is("EXISTS", 3) { ok = false; }
  if !status_case_is("NOT_FOUND", 4) { ok = false; }
  if !status_case_is("DELETED", 5) { ok = false; }
  if !status_case_is("TOUCHED", 6) { ok = false; }
  if !status_case_is("OK", 7) { ok = false; }
  if !status_case_is("ERROR", 8) { ok = false; }
  if !status_case_is("CLIENT_ERROR bad command line format", 9) { ok = false; }
  if !status_case_is("SERVER_ERROR out of memory", 10) { ok = false; }
  if !status_case_is("VERSION 1.6.21", 11) { ok = false; }
  if !status_case_is("END", 12) { ok = false; }
  if !status_case_is("VALUE foo 0 1", 13) { ok = false; }
  if !status_case_is("stored", 1) { ok = false; }
  let bogus = bytes_of("BOGUS\r\n");
  if !err_pair_is(memcached.text_parse_status(&bogus, 0), "memcached: bad response line") { ok = false; }
  let nocrlf = bytes_of("STORED");
  if !err_pair_is(memcached.text_parse_status(&nocrlf, 0), "memcached: truncated line") { ok = false; }
  if !err_pair_is(memcached.text_parse_status(&nocrlf, -1), "memcached: negative offset") { ok = false; }
  if !err_pair_is(memcached.text_parse_status(&nocrlf, 6), "memcached: truncated line") { ok = false; }
  if !str_eq(memcached.text_status_name(4), "NOT_FOUND") { ok = false; }
  if !str_eq(memcached.text_status_name(99), "UNKNOWN") { ok = false; }
  if memcached.text_status_id("DELETED") != 5 { ok = false; }
  if memcached.text_status_id("nope") != 0 { ok = false; }
  return assert(ok, "text response status lines and status table");
}

fn t12() -> TestResult {
  var ok = true;
  var buf = bytes_of("VALUE foo 5 3\r\nabc\r\nVALUE bar 7 4\r\n");
  buf.push(0 as UInt8);
  buf.push(13 as UInt8);
  buf.push(10 as UInt8);
  buf.push(255 as UInt8);
  append_bytes(&mut buf, "\r\nEND\r\n");
  let r = getresp_ok(buf, 0);
  if memcached.text_values_count(&r) != 2 { ok = false; }
  if !bytes_equal(memcached.text_value_key(&r, 0), bytes_of("foo")) { ok = false; }
  if !bytes_equal(memcached.text_value_key(&r, 1), bytes_of("bar")) { ok = false; }
  if memcached.text_value_flags(&r, 0) != 5 { ok = false; }
  if memcached.text_value_flags(&r, 1) != 7 { ok = false; }
  if memcached.text_value_cas(&r, 0) != -1 { ok = false; }
  if !bytes_equal(memcached.text_value_data(&r, 0), bytes_of("abc")) { ok = false; }
  var want1 = Vec[UInt8].new();
  want1.push(0 as UInt8);
  want1.push(13 as UInt8);
  want1.push(10 as UInt8);
  want1.push(255 as UInt8);
  if !bytes_equal(memcached.text_value_data(&r, 1), want1) { ok = false; }
  if r.consumed != buf.len() { ok = false; }
  return assert(ok, "VALUE/END retrieval response with binary-safe payloads");
}

fn t13() -> TestResult {
  var ok = true;
  let miss = bytes_of("END\r\n");
  let r0 = getresp_ok(miss, 0);
  if memcached.text_values_count(&r0) != 0 { ok = false; }
  if r0.consumed != 5 { ok = false; }
  let d = bytes_of("VALUE foo 0 1 42\r\nx\r\nEND\r\n");
  let r = getresp_ok(d, 0);
  if memcached.text_values_count(&r) != 1 { ok = false; }
  if memcached.text_value_cas(&r, 0) != 42 { ok = false; }
  if !bytes_equal(memcached.text_value_data(&r, 0), bytes_of("x")) { ok = false; }
  if r.consumed != d.len() { ok = false; }
  if memcached.text_value_key(&r, 5).len() != 0 { ok = false; }
  if memcached.text_value_flags(&r, 5) != -1 { ok = false; }
  if memcached.text_value_cas(&r, -1) != -1 { ok = false; }
  if memcached.text_value_data(&r, 5).len() != 0 { ok = false; }
  return assert(ok, "empty retrieval response, gets cas and out-of-range accessors");
}

fn t14() -> TestResult {
  var ok = true;
  let d1 = bytes_of("VALUE foo 0 3");
  if !err_get_is(memcached.text_parse_get_response(&d1, 0), "memcached: truncated line") { ok = false; }
  let d2 = bytes_of("VALUE foo 0 3\r\nab");
  if !err_get_is(memcached.text_parse_get_response(&d2, 0), "memcached: truncated data") { ok = false; }
  let d3 = bytes_of("VALUE foo x 3\r\nabc\r\nEND\r\n");
  if !err_get_is(memcached.text_parse_get_response(&d3, 0), "memcached: bad integer") { ok = false; }
  let d4 = bytes_of("VALUE foo 0 3\r\nabcXY\r\nEND\r\n");
  if !err_get_is(memcached.text_parse_get_response(&d4, 0), "memcached: bad data block") { ok = false; }
  let d5 = bytes_of("VALUE foo 0 3 abc d\r\n");
  if !err_get_is(memcached.text_parse_get_response(&d5, 0), "memcached: bad response line") { ok = false; }
  let d6 = bytes_of("VALUE foo 0 1\r\nx\r\n");
  if !err_get_is(memcached.text_parse_get_response(&d6, 0), "memcached: truncated response") { ok = false; }
  let d7 = bytes_of("VALUE 5\r\n");
  if !err_get_is(memcached.text_parse_get_response(&d7, 0), "memcached: bad response line") { ok = false; }
  if !err_get_is(memcached.text_parse_get_response(&d6, -1), "memcached: negative offset") { ok = false; }
  return assert(ok, "retrieval response rejects malformed input");
}

// ---------------------------------------------------------------------------
// Binary protocol
// ---------------------------------------------------------------------------

fn t15() -> TestResult {
  var ok = true;
  let key = bytes_of("foo");
  if !bytes_equal(enc_ok(memcached.bin_encode_get(&key, 7)), hb("800000030000000000000003000000070000000000000000666f6f")) { ok = false; }
  if !bytes_equal(enc_ok(memcached.bin_encode_getk(&key, 9)), hb("800c00030000000000000003000000090000000000000000666f6f")) { ok = false; }
  if !bytes_equal(enc_ok(memcached.bin_encode_getkq(&key, 3)), hb("800d00030000000000000003000000030000000000000000666f6f")) { ok = false; }
  let h0 = header_ok(enc_ok(memcached.bin_encode_get(&key, 7)), 0);
  if h0.magic != 128 { ok = false; }
  if h0.opcode != 0 { ok = false; }
  if h0.key_len != 3 { ok = false; }
  if h0.extras_len != 0 { ok = false; }
  if h0.data_type != 0 { ok = false; }
  if h0.status != 0 { ok = false; }
  if h0.total_body != 3 { ok = false; }
  if h0.opaque != 7 { ok = false; }
  if h0.cas != 0 { ok = false; }
  if h0.consumed != 24 { ok = false; }
  return assert(ok, "binary GET/GETK/GETKQ request encoding and header fields");
}

fn t16() -> TestResult {
  var ok = true;
  let key = bytes_of("k");
  let val = bytes_of("v");
  if !bytes_equal(enc_ok(memcached.bin_encode_set(&key, &val, 5, 60, 0, 9)), hb("80010001080000000000000a0000000900000000000000000000003c000000056b76")) { ok = false; }
  if !bytes_equal(enc_ok(memcached.bin_encode_add(&key, &val, 0, 0, 0, 9)), hb("80020001080000000000000a00000009000000000000000000000000000000006b76")) { ok = false; }
  if !bytes_equal(enc_ok(memcached.bin_encode_replace(&key, &val, 7, 100, 0, 9)), hb("80030001080000000000000a00000009000000000000000000000064000000076b76")) { ok = false; }
  if !err_bytes_is(memcached.bin_encode_set(&key, &val, -1, 0, 0, 1), "memcached: bad flags") { ok = false; }
  if !err_bytes_is(memcached.bin_encode_set(&key, &val, 0, 4294967296, 0, 1), "memcached: bad exptime") { ok = false; }
  return assert(ok, "binary SET/ADD/REPLACE encoding with expiration+flags extras");
}

fn t17() -> TestResult {
  var ok = true;
  let key = bytes_of("n");
  if !bytes_equal(enc_ok(memcached.bin_encode_incr(&key, 1, 5, 0, 1)), hb("80050001140000000000001500000001000000000000000000000000000000010000000000000005000000006e")) { ok = false; }
  if !bytes_equal(enc_ok(memcached.bin_encode_decr(&key, 1, 5, 0, 2)), hb("80060001140000000000001500000002000000000000000000000000000000010000000000000005000000006e")) { ok = false; }
  if !err_bytes_is(memcached.bin_encode_incr(&key, -1, 0, 0, 1), "memcached: bad delta") { ok = false; }
  if !err_bytes_is(memcached.bin_encode_incr(&key, 0, -1, 0, 1), "memcached: bad initial") { ok = false; }
  return assert(ok, "binary INCR/DECR encoding with delta+initial+expiration extras");
}

fn t18() -> TestResult {
  var ok = true;
  let key = bytes_of("k");
  if !bytes_equal(enc_ok(memcached.bin_encode_delete(&key, 3)), hb("8004000100000000000000010000000300000000000000006b")) { ok = false; }
  if !bytes_equal(enc_ok(memcached.bin_encode_quit(0)), hb("800700000000000000000000000000000000000000000000")) { ok = false; }
  if !bytes_equal(enc_ok(memcached.bin_encode_noop(1)), hb("800a00000000000000000000000000010000000000000000")) { ok = false; }
  if !bytes_equal(enc_ok(memcached.bin_encode_version(1)), hb("800b00000000000000000000000000010000000000000000")) { ok = false; }
  if !bytes_equal(enc_ok(memcached.bin_encode_flush(0, 1)), hb("80080000040000000000000400000001000000000000000000000000")) { ok = false; }
  if !bytes_equal(enc_ok(memcached.bin_encode_flush(-1, 1)), hb("800800000000000000000000000000010000000000000000")) { ok = false; }
  if !err_bytes_is(memcached.bin_encode_flush(-2, 1), "memcached: bad exptime") { ok = false; }
  if !err_bytes_is(memcached.bin_encode_request(99, &key, &key, &key, 0, 0), "memcached: unknown opcode") { ok = false; }
  return assert(ok, "binary DELETE/QUIT/NOOP/VERSION/FLUSH encoding");
}

fn t19() -> TestResult {
  var ok = true;
  let key = bytes_of("k");
  let val = bytes_of("v");
  let p = packet_ok(enc_ok(memcached.bin_encode_set(&key, &val, 5, 60, 0, 9)), 0);
  if p.magic != 128 { ok = false; }
  if p.opcode != 1 { ok = false; }
  if p.key_len != 1 { ok = false; }
  if p.extras_len != 8 { ok = false; }
  if p.status != 0 { ok = false; }
  if p.opaque != 9 { ok = false; }
  if p.consumed != 34 { ok = false; }
  if !bytes_equal(p.key, bytes_of("k")) { ok = false; }
  if !bytes_equal(p.value, bytes_of("v")) { ok = false; }
  let se = setex_ok(memcached.bin_decode_set_extras(&p.extras));
  if se.exptime != 60 { ok = false; }
  if se.flags != 5 { ok = false; }
  let k2 = bytes_of("foo");
  let pq = packet_ok(enc_ok(memcached.bin_encode_getkq(&k2, 3)), 0);
  if pq.opcode != 13 { ok = false; }
  if pq.extras_len != 0 { ok = false; }
  if pq.value.len() != 0 { ok = false; }
  if pq.consumed != 27 { ok = false; }
  let nkey = bytes_of("n");
  let pi = packet_ok(enc_ok(memcached.bin_encode_incr(&nkey, 1, 5, 0, 1)), 0);
  let de = dex_ok(memcached.bin_decode_delta_extras(&pi.extras));
  if de.delta != 1 { ok = false; }
  if de.initial != 5 { ok = false; }
  if de.exptime != 0 { ok = false; }
  if pi.consumed != 45 { ok = false; }
  return assert(ok, "binary packet round-trips split extras/key/value with consumed counts");
}

fn t20() -> TestResult {
  var ok = true;
  let no_key = Vec[UInt8].new();
  let no_val = Vec[UInt8].new();
  var extras = Vec[UInt8].new();
  extras.push(0 as UInt8);
  extras.push(0 as UInt8);
  extras.push(0 as UInt8);
  extras.push(5 as UInt8);
  let val = bytes_of("abc");
  let ex: Vec[UInt8] = extras;
  if !bytes_equal(enc_ok(memcached.bin_encode_response(0, 0, &ex, &no_key, &val, 42, 5)), hb("81000000040000000000000700000005000000000000002a00000005616263")) { ok = false; }
  let pr = packet_ok(enc_ok(memcached.bin_encode_response(0, 0, &ex, &no_key, &val, 42, 5)), 0);
  if pr.magic != 129 { ok = false; }
  if pr.opcode != 0 { ok = false; }
  if pr.status != 0 { ok = false; }
  if pr.extras_len != 4 { ok = false; }
  if pr.cas != 42 { ok = false; }
  if pr.opaque != 5 { ok = false; }
  if pr.consumed != 31 { ok = false; }
  if !bytes_equal(pr.value, bytes_of("abc")) { ok = false; }
  let gf = memcached.bin_decode_get_extras(&pr.extras);
  if !gf.is_ok { ok = false; }
  if gf.value != 5 { ok = false; }
  if !err_int_is(memcached.bin_decode_get_extras(&no_key), "memcached: bad extras length") { ok = false; }
  let pe = packet_ok(enc_ok(memcached.bin_encode_response(0, 1, &no_key, &no_key, &no_val, 0, 5)), 0);
  if pe.status != 1 { ok = false; }
  if pe.extras_len != 0 { ok = false; }
  if pe.value.len() != 0 { ok = false; }
  if !bytes_equal(enc_ok(memcached.bin_encode_response(0, 1, &no_key, &no_key, &no_val, 0, 5)), hb("810000000000000100000000000000050000000000000000")) { ok = false; }
  return assert(ok, "binary response encoding, GET flags extras and error responses");
}

fn t21() -> TestResult {
  var ok = true;
  let truncated = hb("8000000300000000000000030000000700000000");
  if !err_header_is(memcached.bin_parse_header(&truncated, 0), "memcached: truncated header") { ok = false; }
  let bad_magic = hb("820000030000000000000003000000070000000000000000666f6f");
  if !err_header_is(memcached.bin_parse_header(&bad_magic, 0), "memcached: bad magic") { ok = false; }
  let bad_op = hb("809900030000000000000003000000070000000000000000666f6f");
  if !err_header_is(memcached.bin_parse_header(&bad_op, 0), "memcached: unknown opcode") { ok = false; }
  let bad_dt = hb("800000030001000000000003000000070000000000000000666f6f");
  if !err_header_is(memcached.bin_parse_header(&bad_dt, 0), "memcached: bad data type") { ok = false; }
  let bad_cas = hb("800000030000000000000003000000078000000000000000666f6f");
  if !err_header_is(memcached.bin_parse_header(&bad_cas, 0), "memcached: cas out of range") { ok = false; }
  let short_body = hb("80010001080000000000000a0000000900000000000000000000003c00");
  if !err_packet_is(memcached.bin_parse_packet(&short_body, 0), "memcached: truncated body") { ok = false; }
  let bad_extras = hb("80000003040000000000000700000007000000000000000000000000666f6f");
  if !err_packet_is(memcached.bin_parse_packet(&bad_extras, 0), "memcached: bad extras length") { ok = false; }
  let bad_keylen = hb("800000050000000000000003000000010000000000000000666f6f");
  if !err_packet_is(memcached.bin_parse_packet(&bad_keylen, 0), "memcached: bad key length") { ok = false; }
  let valid = hb("800000030000000000000003000000070000000000000000666f6f");
  if !err_header_is(memcached.bin_parse_header(&valid, -1), "memcached: negative offset") { ok = false; }
  let p = packet_ok(valid, 0);
  if !bytes_equal(p.key, bytes_of("foo")) { ok = false; }
  if p.consumed != 27 { ok = false; }
  return assert(ok, "binary parser rejects truncation, bad magic/opcode/type/sizes and high cas");
}

fn t22() -> TestResult {
  var ok = true;
  if memcached.bin_opcode_id("GET") != 0 { ok = false; }
  if memcached.bin_opcode_id("get") != 0 { ok = false; }
  if memcached.bin_opcode_id("SET") != 1 { ok = false; }
  if memcached.bin_opcode_id("ADD") != 2 { ok = false; }
  if memcached.bin_opcode_id("REPLACE") != 3 { ok = false; }
  if memcached.bin_opcode_id("DELETE") != 4 { ok = false; }
  if memcached.bin_opcode_id("INCR") != 5 { ok = false; }
  if memcached.bin_opcode_id("DECR") != 6 { ok = false; }
  if memcached.bin_opcode_id("QUIT") != 7 { ok = false; }
  if memcached.bin_opcode_id("FLUSH") != 8 { ok = false; }
  if memcached.bin_opcode_id("NOOP") != 10 { ok = false; }
  if memcached.bin_opcode_id("VERSION") != 11 { ok = false; }
  if memcached.bin_opcode_id("GETK") != 12 { ok = false; }
  if memcached.bin_opcode_id("GETKQ") != 13 { ok = false; }
  if memcached.bin_opcode_id("BOGUS") != -1 { ok = false; }
  if !str_eq(memcached.bin_opcode_name(13), "GETKQ") { ok = false; }
  if !str_eq(memcached.bin_opcode_name(99), "UNKNOWN") { ok = false; }
  if memcached.bin_status_id("SUCCESS") != 0 { ok = false; }
  if memcached.bin_status_id("NOT_FOUND") != 1 { ok = false; }
  if memcached.bin_status_id("KEY_ENOENT") != 1 { ok = false; }
  if memcached.bin_status_id("EXISTS") != 2 { ok = false; }
  if memcached.bin_status_id("TOO_LARGE") != 3 { ok = false; }
  if memcached.bin_status_id("E2BIG") != 3 { ok = false; }
  if memcached.bin_status_id("NOPE") != -1 { ok = false; }
  if !str_eq(memcached.bin_status_name(0), "SUCCESS") { ok = false; }
  if !str_eq(memcached.bin_status_name(1), "NOT_FOUND") { ok = false; }
  if !str_eq(memcached.bin_status_name(2), "EXISTS") { ok = false; }
  if !str_eq(memcached.bin_status_name(3), "TOO_LARGE") { ok = false; }
  if !str_eq(memcached.bin_status_name(5), "NOT_STORED") { ok = false; }
  if !str_eq(memcached.bin_status_name(7), "NOT_MY_VBUCKET") { ok = false; }
  if !str_eq(memcached.bin_status_name(32), "AUTH_ERROR") { ok = false; }
  if !str_eq(memcached.bin_status_name(33), "AUTH_CONTINUE") { ok = false; }
  if !str_eq(memcached.bin_status_name(129), "UNKNOWN_COMMAND") { ok = false; }
  if !str_eq(memcached.bin_status_name(130), "OUT_OF_MEMORY") { ok = false; }
  if !str_eq(memcached.bin_status_name(131), "NOT_SUPPORTED") { ok = false; }
  if !str_eq(memcached.bin_status_name(132), "INTERNAL_ERROR") { ok = false; }
  if !str_eq(memcached.bin_status_name(133), "BUSY") { ok = false; }
  if !str_eq(memcached.bin_status_name(134), "TEMP_FAILURE") { ok = false; }
  if !str_eq(memcached.bin_status_name(999), "UNKNOWN") { ok = false; }
  if !memcached.bin_status_is_success(0) { ok = false; }
  if memcached.bin_status_is_success(1) { ok = false; }
  if !memcached.bin_extras_len_is_valid(128, 1, 8) { ok = false; }
  if memcached.bin_extras_len_is_valid(128, 1, 4) { ok = false; }
  if !memcached.bin_extras_len_is_valid(128, 5, 20) { ok = false; }
  if memcached.bin_extras_len_is_valid(128, 5, 8) { ok = false; }
  if !memcached.bin_extras_len_is_valid(128, 8, 0) { ok = false; }
  if !memcached.bin_extras_len_is_valid(128, 8, 4) { ok = false; }
  if memcached.bin_extras_len_is_valid(128, 8, 8) { ok = false; }
  if !memcached.bin_extras_len_is_valid(128, 0, 0) { ok = false; }
  if !memcached.bin_extras_len_is_valid(129, 0, 4) { ok = false; }
  if memcached.bin_extras_len_is_valid(129, 0, 0) { ok = false; }
  if !memcached.bin_extras_len_is_valid(129, 5, 8) { ok = false; }
  if !memcached.bin_extras_len_is_valid(129, 1, 0) { ok = false; }
  if memcached.bin_extras_len_is_valid(130, 1, 8) { ok = false; }
  return assert(ok, "binary opcode, status and extras tables");
}

fn main() -> Int {
  io.println("=== xiom.memcached conformance tests ===");
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
    io.println("xiom.memcached: all tests passed");
  } else {
    io.println("xiom.memcached: tests failed");
  }
  return failed;
}
