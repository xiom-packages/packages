// XIOM -- xiom.netstring conformance tests (21 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Covers the documented API: hand-built streams with pinned offsets and
// lengths (empty payload, ASCII payload, raw high bytes), multi-frame
// streams, exact append/build bytes with computed decimal lengths, the 9/10
// digit length boundary, the digit-count and frame-size tables, all six
// parse errors (bad length digits, missing colon, payload too short, missing
// comma, length overflow, trailing garbage), payload access errors, build
// and parse round-trips (including a 300-byte payload), and the cursor API
// (order, exhaustion, atomic failure, resumable truncation).
//
// Str values are compared through xiom.string.compare.str_compare (BUG 17
// discipline: `==` on a Str read from a Vec lowers to a pointer comparison)
// and every Vec read goes through a typed local before it is used.

module netstring_tests
use xiom.io; use xiom.test;
use xiom.netstring;
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

// ASCII bytes of a Str, one byte per character.
fn ab(s: Str) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < s.len() {
    v.push(string.byte_at(s, i));
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
    if (((a[i] as Int) & 0xFF) != ((b[i] as Int) & 0xFF)) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

fn str_eq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn err_list_is(r: Result[NetstringList, Str], want: Str) -> Bool {
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

fn err_int_is(r: Result[Int, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

// Mutable-taking cursor reads: passing `&mut` at the call sites keeps the
// advisory E001 borrow warning away when reads and netstring_cursor_next
// mix on the same cursor (the same device as xiom.bencode's _pbyte_mut).
fn cur_pos(c: &mut NetstringCursor) -> Int {
  return netstring_cursor_position(c);
}

fn cur_index(c: &mut NetstringCursor) -> Int {
  return netstring_cursor_index(c);
}

fn cur_off(c: &mut NetstringCursor) -> Int {
  return netstring_cursor_payload_offset(c);
}

fn cur_len(c: &mut NetstringCursor) -> Int {
  return netstring_cursor_payload_length(c);
}

// Parse the ASCII bytes of `s` as a netstring stream.
fn parse_ab(s: Str) -> Result[NetstringList, Str] {
  let data = ab(s);
  return netstring_parse(&data);
}

// Copy `len` bytes of `data` starting at `off`.
fn slice_at(data: &Vec[UInt8], off: Int, len: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < len {
    out.push(data[off + i]);
    i = i + 1;
  }
  return out;
}

// Payload bytes of frame `i`, or an empty vector on error (callers only use
// it after a successful parse and a checked index).
fn payload_at(data: &Vec[UInt8], l: &NetstringList, i: Int) -> Vec[UInt8] {
  let r = netstring_payload(data, l, i);
  match r {
    Ok(v) => { return v; },
    Err(_) => {},
  }
  return Vec[UInt8].new();
}

// True when frame `i`'s payload equals `want`.
fn payload_is(data: &Vec[UInt8], l: &NetstringList, i: Int, want: Vec[UInt8]) -> Bool {
  let r = netstring_payload(data, l, i);
  if !r.is_ok {
    return false;
  }
  let v: Vec[UInt8] = r.value;
  return bytes_equal(v, want);
}

// Concatenate three byte vectors.
fn concat3(a: Vec[UInt8], b: Vec[UInt8], c: Vec[UInt8]) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < a.len() {
    v.push(a[i]);
    i = i + 1;
  }
  var j = 0;
  while j < b.len() {
    v.push(b[j]);
    j = j + 1;
  }
  var k = 0;
  while k < c.len() {
    v.push(c[k]);
    k = k + 1;
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

// Deterministic byte pattern of length n using the full 0..255 range
// (including high bytes).
fn seq_bytes(n: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < n {
    v.push(((i * 7 + 3) % 256) as UInt8);
    i = i + 1;
  }
  return v;
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  var empty = Vec[UInt8].new();
  let r = netstring_parse(&empty);
  if !r.is_ok { return assert(false, "empty buffer must parse"); }
  let l: NetstringList = r.value;
  var ok = netstring_count(&l) == 0;
  if netstring_offset(&l, 0) != -1 { ok = false; }
  if netstring_length(&l, -1) != -1 { ok = false; }
  if !err_bytes_is(netstring_payload(&empty, &l, 0), "netstring: index out of range") { ok = false; }
  return assert(ok, "empty buffer parses to zero frames");
}

fn t2() -> TestResult {
  let data = ab("0:,");
  let r = netstring_parse(&data);
  if !r.is_ok { return assert(false, "0:, must parse"); }
  let l: NetstringList = r.value;
  var ok = netstring_count(&l) == 1;
  if netstring_offset(&l, 0) != 2 { ok = false; }
  if netstring_length(&l, 0) != 0 { ok = false; }
  if !payload_is(&data, &l, 0, Vec[UInt8].new()) { ok = false; }
  return assert(ok, "empty frame 0:, pins offset 2 and length 0");
}

fn t3() -> TestResult {
  let data = ab("5:hello,");
  let r = netstring_parse(&data);
  if !r.is_ok { return assert(false, "5:hello, must parse"); }
  let l: NetstringList = r.value;
  var ok = netstring_count(&l) == 1;
  if netstring_offset(&l, 0) != 2 { ok = false; }
  if netstring_length(&l, 0) != 5 { ok = false; }
  if !payload_is(&data, &l, 0, ab("hello")) { ok = false; }
  return assert(ok, "simple frame parses with an exact payload slice");
}

fn t4() -> TestResult {
  let data = ab("5: a,:1,");
  let r = netstring_parse(&data);
  if !r.is_ok { return assert(false, "raw payload frame must parse"); }
  let l: NetstringList = r.value;
  var ok = netstring_count(&l) == 1;
  if !payload_is(&data, &l, 0, ab(" a,:1")) { ok = false; }
  let raw = concat3(ab("3:"), hb("00ff80"), ab(","));
  let r2 = netstring_parse(&raw);
  if !r2.is_ok { ok = false; } else {
    let l2: NetstringList = r2.value;
    if netstring_count(&l2) != 1 { ok = false; }
    if !payload_is(&raw, &l2, 0, hb("00ff80")) { ok = false; }
  }
  return assert(ok, "payload bytes are raw: ':' and ',' inside, high bytes");
}

fn t5() -> TestResult {
  let data = ab("3:abc,0:,11:hello world,");
  let r = netstring_parse(&data);
  if !r.is_ok { return assert(false, "three-frame stream must parse"); }
  let l: NetstringList = r.value;
  var ok = netstring_count(&l) == 3;
  if netstring_offset(&l, 0) != 2 { ok = false; }
  if netstring_offset(&l, 1) != 8 { ok = false; }
  if netstring_offset(&l, 2) != 12 { ok = false; }
  if netstring_length(&l, 0) != 3 { ok = false; }
  if netstring_length(&l, 1) != 0 { ok = false; }
  if netstring_length(&l, 2) != 11 { ok = false; }
  if !payload_is(&data, &l, 0, ab("abc")) { ok = false; }
  if !payload_is(&data, &l, 1, Vec[UInt8].new()) { ok = false; }
  if !payload_is(&data, &l, 2, ab("hello world")) { ok = false; }
  return assert(ok, "multi-frame stream pins every offset and length");
}

fn t6() -> TestResult {
  var out = Vec[UInt8].new();
  let a = ab("abc");
  var empty = Vec[UInt8].new();
  let b = ab("hello world");
  netstring_append(&mut out, &a);
  netstring_append(&mut out, &empty);
  netstring_append(&mut out, &b);
  var ok = bytes_equal(out, ab("3:abc,0:,11:hello world,"));
  let p9 = repeat_byte(120, 9);
  var o9 = Vec[UInt8].new();
  netstring_append(&mut o9, &p9);
  if !bytes_equal(o9, concat3(ab("9:"), p9, ab(","))) { ok = false; }
  let p10 = repeat_byte(121, 10);
  var o10 = Vec[UInt8].new();
  netstring_append(&mut o10, &p10);
  if !bytes_equal(o10, concat3(ab("10:"), p10, ab(","))) { ok = false; }
  return assert(ok, "append writes computed lengths: 3/0/11, 9 and 10 digits");
}

fn t7() -> TestResult {
  var payloads = Vec[Vec[UInt8]].new();
  payloads.push(hb("00010203ff80"));
  payloads.push(ab("hello"));
  var empty = Vec[UInt8].new();
  payloads.push(empty);
  let built = netstring_build(&payloads);
  var manual = Vec[UInt8].new();
  let p0: Vec[UInt8] = payloads[0];
  let p1: Vec[UInt8] = payloads[1];
  let p2: Vec[UInt8] = payloads[2];
  netstring_append(&mut manual, &p0);
  netstring_append(&mut manual, &p1);
  netstring_append(&mut manual, &p2);
  var ok = bytes_equal(built, manual);
  let pr = netstring_parse(&built);
  if !pr.is_ok { ok = false; } else {
    let l: NetstringList = pr.value;
    if netstring_count(&l) != 3 { ok = false; }
    if !payload_is(&built, &l, 0, hb("00010203ff80")) { ok = false; }
    if !payload_is(&built, &l, 1, ab("hello")) { ok = false; }
    if !payload_is(&built, &l, 2, Vec[UInt8].new()) { ok = false; }
  }
  return assert(ok, "build equals per-frame appends and parses back");
}

fn t8() -> TestResult {
  var ok = netstring_digit_count(0) == 1;
  if netstring_digit_count(1) != 1 { ok = false; }
  if netstring_digit_count(9) != 1 { ok = false; }
  if netstring_digit_count(10) != 2 { ok = false; }
  if netstring_digit_count(99) != 2 { ok = false; }
  if netstring_digit_count(100) != 3 { ok = false; }
  if netstring_digit_count(999) != 3 { ok = false; }
  if netstring_digit_count(1000) != 4 { ok = false; }
  if netstring_digit_count(999999999) != 9 { ok = false; }
  if netstring_digit_count(1000000000) != 10 { ok = false; }
  if netstring_digit_count(-1) != -1 { ok = false; }
  if netstring_frame_size(0) != 3 { ok = false; }
  if netstring_frame_size(9) != 12 { ok = false; }
  if netstring_frame_size(10) != 14 { ok = false; }
  if netstring_frame_size(99) != 103 { ok = false; }
  if netstring_frame_size(100) != 105 { ok = false; }
  if netstring_frame_size(-1) != -1 { ok = false; }
  return assert(ok, "digit count and frame size tables");
}

fn t9() -> TestResult {
  let d9 = ab("9:123456789,");
  let r9 = netstring_parse(&d9);
  var ok = r9.is_ok;
  if r9.is_ok {
    let l9: NetstringList = r9.value;
    if netstring_count(&l9) != 1 { ok = false; }
    if netstring_offset(&l9, 0) != 2 { ok = false; }
    if netstring_length(&l9, 0) != 9 { ok = false; }
    if !payload_is(&d9, &l9, 0, ab("123456789")) { ok = false; }
  }
  let d10 = ab("10:1234567890,");
  let r10 = netstring_parse(&d10);
  if !r10.is_ok { ok = false; } else {
    let l10: NetstringList = r10.value;
    if netstring_count(&l10) != 1 { ok = false; }
    if netstring_offset(&l10, 0) != 3 { ok = false; }
    if netstring_length(&l10, 0) != 10 { ok = false; }
    if !payload_is(&d10, &l10, 0, ab("1234567890")) { ok = false; }
  }
  return assert(ok, "9- and 10-byte payloads parse with 1- and 2-digit lengths");
}

fn t10() -> TestResult {
  var ok = err_list_is(parse_ab(":"), "netstring: bad length digits");
  if !err_list_is(parse_ab("01:abc,"), "netstring: bad length digits") { ok = false; }
  if !err_list_is(parse_ab("00:,"), "netstring: bad length digits") { ok = false; }
  if !err_list_is(parse_ab("1x:abc,"), "netstring: bad length digits") { ok = false; }
  if !err_list_is(parse_ab("1 :abc,"), "netstring: bad length digits") { ok = false; }
  if !err_list_is(parse_ab("0:,00:,"), "netstring: bad length digits") { ok = false; }
  return assert(ok, "bad length digits: empty run, leading zero, non-colon end");
}

fn t11() -> TestResult {
  var ok = err_list_is(parse_ab("x:,"), "netstring: trailing garbage");
  if !err_list_is(parse_ab("3:abc,,"), "netstring: trailing garbage") { ok = false; }
  if !err_list_is(parse_ab(" 3:abc,"), "netstring: trailing garbage") { ok = false; }
  if !err_list_is(parse_ab("+3:abc,"), "netstring: trailing garbage") { ok = false; }
  if !err_list_is(parse_ab("3:abc,xyz"), "netstring: trailing garbage") { ok = false; }
  return assert(ok, "non-digit frame starts are trailing garbage");
}

fn t12() -> TestResult {
  var ok = err_list_is(parse_ab("3"), "netstring: missing colon");
  if !err_list_is(parse_ab("0"), "netstring: missing colon") { ok = false; }
  if !err_list_is(parse_ab("12"), "netstring: missing colon") { ok = false; }
  if !err_list_is(parse_ab("3:abc,4"), "netstring: missing colon") { ok = false; }
  if !err_list_is(parse_ab("9223372036854775807"), "netstring: missing colon") { ok = false; }
  return assert(ok, "a digit run that reaches the buffer end misses the colon");
}

fn t13() -> TestResult {
  var ok = err_list_is(parse_ab("5:abc,"), "netstring: payload too short");
  if !err_list_is(parse_ab("1:"), "netstring: payload too short") { ok = false; }
  if !err_list_is(parse_ab("10:12345,"), "netstring: payload too short") { ok = false; }
  if !err_list_is(parse_ab("1:a,3:xy"), "netstring: payload too short") { ok = false; }
  if !err_list_is(parse_ab("9223372036854775807:x"), "netstring: payload too short") { ok = false; }
  return assert(ok, "declared length beyond the remaining bytes is payload too short");
}

fn t14() -> TestResult {
  var ok = err_list_is(parse_ab("3:abc"), "netstring: missing comma");
  if !err_list_is(parse_ab("3:abcx"), "netstring: missing comma") { ok = false; }
  if !err_list_is(parse_ab("0:x"), "netstring: missing comma") { ok = false; }
  if !err_list_is(parse_ab("0:"), "netstring: missing comma") { ok = false; }
  if !err_list_is(parse_ab("3:abc,0:"), "netstring: missing comma") { ok = false; }
  return assert(ok, "a missing or wrong trailing comma is missing comma");
}

fn t15() -> TestResult {
  var ok = err_list_is(parse_ab("99999999999999999999:abc,"), "netstring: length overflow");
  if !err_list_is(parse_ab("9223372036854775808:x"), "netstring: length overflow") { ok = false; }
  if !err_list_is(parse_ab("99999999999999999999999"), "netstring: length overflow") { ok = false; }
  if !err_list_is(parse_ab("18446744073709551616:,"), "netstring: length overflow") { ok = false; }
  return assert(ok, "lengths above INT64_MAX overflow, colon or not");
}

fn t16() -> TestResult {
  let data = ab("3:abc,0:,5:hello,");
  var c = netstring_cursor_new();
  var ok = cur_pos(&mut c) == 0;
  if cur_index(&mut c) != 0 { ok = false; }
  if cur_off(&mut c) != -1 { ok = false; }
  if cur_len(&mut c) != -1 { ok = false; }
  let r0 = netstring_cursor_next(&data, &mut c);
  if !r0.is_ok { return assert(false, "first cursor next must succeed"); }
  let v0: Int = r0.value;
  if v0 != 0 { ok = false; }
  if cur_off(&mut c) != 2 { ok = false; }
  if cur_len(&mut c) != 3 { ok = false; }
  if cur_pos(&mut c) != 6 { ok = false; }
  if cur_index(&mut c) != 1 { ok = false; }
  if !bytes_equal(slice_at(&data, 2, 3), ab("abc")) { ok = false; }
  let r1 = netstring_cursor_next(&data, &mut c);
  if !r1.is_ok { ok = false; } else {
    let v1: Int = r1.value;
    if v1 != 1 { ok = false; }
  }
  if cur_off(&mut c) != 8 { ok = false; }
  if cur_len(&mut c) != 0 { ok = false; }
  if cur_pos(&mut c) != 9 { ok = false; }
  if cur_index(&mut c) != 2 { ok = false; }
  let r2 = netstring_cursor_next(&data, &mut c);
  if !r2.is_ok { ok = false; } else {
    let v2: Int = r2.value;
    if v2 != 2 { ok = false; }
  }
  if cur_off(&mut c) != 11 { ok = false; }
  if cur_len(&mut c) != 5 { ok = false; }
  if cur_pos(&mut c) != 17 { ok = false; }
  if cur_index(&mut c) != 3 { ok = false; }
  if !bytes_equal(slice_at(&data, 11, 5), ab("hello")) { ok = false; }
  let r3 = netstring_cursor_next(&data, &mut c);
  if !r3.is_ok { ok = false; } else {
    let v3: Int = r3.value;
    if v3 != -1 { ok = false; }
  }
  if cur_pos(&mut c) != 17 { ok = false; }
  if cur_index(&mut c) != 3 { ok = false; }
  return assert(ok, "cursor consumes frames in order and reports -1 at end");
}

fn t17() -> TestResult {
  let data = ab("3:abc,5:xy,");
  var c = netstring_cursor_new();
  let r0 = netstring_cursor_next(&data, &mut c);
  var ok = r0.is_ok;
  let pos0 = cur_pos(&mut c);
  let idx0 = cur_index(&mut c);
  let off0 = cur_off(&mut c);
  let len0 = cur_len(&mut c);
  let r1 = netstring_cursor_next(&data, &mut c);
  if !err_int_is(r1, "netstring: payload too short") { ok = false; }
  if cur_pos(&mut c) != pos0 { ok = false; }
  if cur_index(&mut c) != idx0 { ok = false; }
  if cur_off(&mut c) != off0 { ok = false; }
  if cur_len(&mut c) != len0 { ok = false; }
  if pos0 != 6 { ok = false; }
  if idx0 != 1 { ok = false; }
  let bad = ab("zz");
  var c2 = netstring_cursor_new();
  let r2 = netstring_cursor_next(&bad, &mut c2);
  if !err_int_is(r2, "netstring: trailing garbage") { ok = false; }
  if cur_pos(&mut c2) != 0 { ok = false; }
  if cur_index(&mut c2) != 0 { ok = false; }
  return assert(ok, "cursor errors are Err and leave the cursor unchanged");
}

fn t18() -> TestResult {
  let partial = ab("3:abc,4:de");
  var c = netstring_cursor_new();
  let r0 = netstring_cursor_next(&partial, &mut c);
  var ok = r0.is_ok;
  let r1 = netstring_cursor_next(&partial, &mut c);
  if !err_int_is(r1, "netstring: payload too short") { ok = false; }
  let pos = cur_pos(&mut c);
  let idx = cur_index(&mut c);
  if pos != 6 { ok = false; }
  if idx != 1 { ok = false; }
  let full = ab("3:abc,4:defg,");
  var c2 = NetstringCursor{ pos: pos; index: idx; payload_offset: -1; payload_length: -1; };
  let r2 = netstring_cursor_next(&full, &mut c2);
  if !r2.is_ok { ok = false; } else {
    let v2: Int = r2.value;
    if v2 != 1 { ok = false; }
  }
  if cur_off(&mut c2) != 8 { ok = false; }
  if cur_len(&mut c2) != 4 { ok = false; }
  if cur_pos(&mut c2) != 13 { ok = false; }
  if cur_index(&mut c2) != 2 { ok = false; }
  if !bytes_equal(slice_at(&full, 8, 4), ab("defg")) { ok = false; }
  let r3 = netstring_cursor_next(&full, &mut c2);
  if !r3.is_ok { ok = false; } else {
    let v3: Int = r3.value;
    if v3 != -1 { ok = false; }
  }
  return assert(ok, "a truncated tail leaves the cursor resumable");
}

fn t19() -> TestResult {
  let payload = seq_bytes(300);
  var built = Vec[UInt8].new();
  netstring_append(&mut built, &payload);
  var ok = built.len() == netstring_frame_size(300);
  if netstring_frame_size(300) != 305 { ok = false; }
  let pr = netstring_parse(&built);
  if !pr.is_ok { ok = false; } else {
    let l: NetstringList = pr.value;
    if netstring_count(&l) != 1 { ok = false; }
    if netstring_offset(&l, 0) != 4 { ok = false; }
    if netstring_length(&l, 0) != 300 { ok = false; }
    if !payload_is(&built, &l, 0, seq_bytes(300)) { ok = false; }
  }
  return assert(ok, "a 300-byte payload round-trips with a 3-digit length");
}

fn t20() -> TestResult {
  let data = ab("3:abc,5:hello,");
  let r = netstring_parse(&data);
  if !r.is_ok { return assert(false, "two-frame stream must parse"); }
  let l: NetstringList = r.value;
  var ok = netstring_count(&l) == 2;
  if !payload_is(&data, &l, 0, ab("abc")) { ok = false; }
  if !payload_is(&data, &l, 1, ab("hello")) { ok = false; }
  if !err_bytes_is(netstring_payload(&data, &l, 2), "netstring: index out of range") { ok = false; }
  if !err_bytes_is(netstring_payload(&data, &l, -1), "netstring: index out of range") { ok = false; }
  let short = ab("3:abc");
  if !err_bytes_is(netstring_payload(&short, &l, 1), "netstring: payload out of bounds") { ok = false; }
  return assert(ok, "payload slices are exact; bad index and short buffer are Err");
}

fn t21() -> TestResult {
  let data = ab("3:abc,0:,11:hello world,");
  let r = netstring_parse(&data);
  if !r.is_ok { return assert(false, "stream must parse"); }
  let l: NetstringList = r.value;
  var payloads = Vec[Vec[UInt8]].new();
  var i = 0;
  while i < netstring_count(&l) {
    let p: Vec[UInt8] = payload_at(&data, &l, i);
    payloads.push(p);
    i = i + 1;
  }
  let rebuilt = netstring_build(&payloads);
  var ok = netstring_count(&l) == 3;
  if !bytes_equal(rebuilt, data) { ok = false; }
  if rebuilt.len() != 24 { ok = false; }
  return assert(ok, "parse then build reproduces the original bytes exactly");
}

fn main() -> Int {
  io.println("=== xiom.netstring conformance tests ===");
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
    io.println("xiom.netstring: all tests passed");
  } else {
    io.println("xiom.netstring: tests failed");
  }
  return failed;
}
