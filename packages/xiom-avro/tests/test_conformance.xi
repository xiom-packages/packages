// XIOM -- xiom.avro conformance tests (20 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Covers the documented API: canonical zig-zag varints at every width
// boundary (0, -1, 1, 63/64, 2^31-1, -2^31, 2^31, -2^31-1, INT64_MAX,
// INT64_MIN), decode round-trips, 10-byte varint caps and overlong/overflow
// rejection, int32 range enforcement, booleans, null, bytes/string lengths
// and UTF-8 payloads, NUL-string rejection, negative-length anomalies with
// offsets, float/double raw LE round-trips and size validation, fixed(n),
// enum/union indices, array/map block framing including negative-size
// skips, the Object Container File header (magic, metadata, codec, sync),
// malformed and truncated inputs, and the whole-buffer round-trip helpers.
//
// All input buffers are synthetic and built in-test (no external data
// files). Harness style mirrors xiom.hello / xiom.cbor / xiom.bencode: one
// fn tN() -> TestResult per check, called directly from main; main prints
// [PASS]/[FAIL] and returns the failure count. Str payloads are compared
// with str_compare, never with `==` on values read out of a Vec[Str].

module avro_tests
use xiom.io; use xiom.test;
use xiom.string; use xiom.string.compare; use xiom.string.builder;
use xiom.encoding.hex;
use xiom.avro;

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

// Bytes of a Str, byte-for-byte (byte_at indexes bytes, so UTF-8 literals
// work too).
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

fn longs_equal(a: Vec[Int], b: Vec[Int]) -> Bool {
  if a.len() != b.len() {
    return false;
  }
  var i = 0;
  while i < a.len() {
    let x: Int = a[i];
    let y: Int = b[i];
    if x != y {
      return false;
    }
    i = i + 1;
  }
  return true;
}

fn concat_bytes(a: Vec[UInt8], b: Vec[UInt8]) -> Vec[UInt8] {
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
  return v;
}

// `n` copies of byte `b`.
fn fill_bytes(n: Int, b: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < n {
    v.push(b as UInt8);
    i = i + 1;
  }
  return v;
}

// Byte `i` of a vector widened to an Int, or -1 when out of range.
fn byte_at_v(v: Vec[UInt8], i: Int) -> Int {
  if i < 0 || i >= v.len() {
    return -1;
  }
  let b: UInt8 = v[i];
  return (b as Int) & 0xFF;
}

// `&mut` variants of the cursor getters: using only these between reader
// calls keeps the advisory E001 borrow note away (same discipline as the
// library's _cbyte_mut helper).
fn cur_pos_mut(cur: &mut AvroCursor) -> Int {
  return avro_cursor_pos(cur);
}

fn cur_len_mut(cur: &mut AvroCursor) -> Int {
  return avro_cursor_len(cur);
}

fn cur_remaining_mut(cur: &mut AvroCursor) -> Int {
  return avro_cursor_remaining(cur);
}

fn cur_done_mut(cur: &mut AvroCursor) -> Bool {
  return avro_cursor_done(cur);
}

// --------------------------------------------------
//  Result assertions
// --------------------------------------------------

fn err_int_is(r: Result[Int, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_compare(r.error, want) == 0;
}

fn err_bool_is(r: Result[Bool, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_compare(r.error, want) == 0;
}

fn err_bytes_is(r: Result[Vec[UInt8], Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_compare(r.error, want) == 0;
}

fn err_str_is(r: Result[Str, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_compare(r.error, want) == 0;
}

fn err_hdr_is(r: Result[AvroOcfHeader, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_compare(r.error, want) == 0;
}

fn ok_long(data: Vec[UInt8], want: Int) -> Bool {
  let r = avro_decode_long(data);
  if !r.is_ok {
    return false;
  }
  let v: Int = r.value;
  return v == want;
}

fn ok_int(data: Vec[UInt8], want: Int) -> Bool {
  let r = avro_decode_int(data);
  if !r.is_ok {
    return false;
  }
  let v: Int = r.value;
  return v == want;
}

fn ok_bool_val(data: Vec[UInt8], want: Bool) -> Bool {
  let r = avro_decode_boolean(data);
  if !r.is_ok {
    return false;
  }
  let v: Bool = r.value;
  return v == want;
}

fn roundtrip_long(n: Int) -> Bool {
  let enc = avro_encode_long(n);
  let r = avro_decode_long(enc);
  if !r.is_ok {
    return false;
  }
  let v: Int = r.value;
  return v == n;
}

fn array_long_ok(data: Vec[UInt8], want: Vec[Int]) -> Bool {
  let r = avro_decode_array_long(data);
  if !r.is_ok {
    return false;
  }
  let got: Vec[Int] = r.value;
  return longs_equal(got, want);
}

fn array_err_is(data: Vec[UInt8], want: Str) -> Bool {
  let r = avro_decode_array_long(data);
  if r.is_ok {
    return false;
  }
  return str_compare(r.error, want) == 0;
}

// Decode a map<bytes,long> and compare entries; also checks that the two
// parallel output vectors do not drift.
fn map_long_ok(data: Vec[UInt8], want_keys: Vec[Vec[UInt8]], want_vals: Vec[Int]) -> Bool {
  var ks = Vec[Vec[UInt8]].new();
  var vs = Vec[Int].new();
  let r = avro_decode_map_bytes_long(data, &mut ks, &mut vs);
  if !r.is_ok {
    return false;
  }
  let n: Int = r.value;
  if n != want_keys.len() {
    return false;
  }
  if ks.len() != vs.len() {
    return false;
  }
  var i = 0;
  while i < ks.len() {
    let kb: Vec[UInt8] = ks[i];
    let wb: Vec[UInt8] = want_keys[i];
    if !bytes_equal(kb, wb) {
      return false;
    }
    i = i + 1;
  }
  i = 0;
  while i < vs.len() {
    let v: Int = vs[i];
    let w: Int = want_vals[i];
    if v != w {
      return false;
    }
    i = i + 1;
  }
  return true;
}

fn longs1(a: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  return v;
}

fn longs2(a: Int, b: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  v.push(b);
  return v;
}

fn longs3(a: Int, b: Int, c: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  v.push(b);
  v.push(c);
  return v;
}

fn longs4(a: Int, b: Int, c: Int, d: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  v.push(b);
  v.push(c);
  v.push(d);
  return v;
}

fn strs1(a: Str) -> Vec[Str] {
  var v = Vec[Str].new();
  v.push(a);
  return v;
}

fn strs2(a: Str, b: Str) -> Vec[Str] {
  var v = Vec[Str].new();
  v.push(a);
  v.push(b);
  return v;
}

fn keyvec1(a: Str) -> Vec[Vec[UInt8]] {
  var v = Vec[Vec[UInt8]].new();
  v.push(ab(a));
  return v;
}

fn keyvec2(a: Str, b: Str) -> Vec[Vec[UInt8]] {
  var v = Vec[Vec[UInt8]].new();
  v.push(ab(a));
  v.push(ab(b));
  return v;
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  var ok = bytes_equal(avro_encode_long(0), hb("00"));
  if !bytes_equal(avro_encode_long(-1), hb("01")) { ok = false; }
  if !bytes_equal(avro_encode_long(1), hb("02")) { ok = false; }
  if !bytes_equal(avro_encode_long(-2), hb("03")) { ok = false; }
  if !bytes_equal(avro_encode_long(2), hb("04")) { ok = false; }
  if !bytes_equal(avro_encode_long(-3), hb("05")) { ok = false; }
  if !bytes_equal(avro_encode_long(63), hb("7e")) { ok = false; }
  if !bytes_equal(avro_encode_long(64), hb("8001")) { ok = false; }
  if !bytes_equal(avro_encode_long(-64), hb("7f")) { ok = false; }
  if !bytes_equal(avro_encode_long(-65), hb("8101")) { ok = false; }
  if !bytes_equal(avro_encode_long(2147483647), hb("feffffff0f")) { ok = false; }
  if !bytes_equal(avro_encode_long(-2147483648), hb("ffffffff0f")) { ok = false; }
  if !bytes_equal(avro_encode_long(2147483648), hb("8080808010")) { ok = false; }
  if !bytes_equal(avro_encode_long(-2147483649), hb("8180808010")) { ok = false; }
  if !bytes_equal(avro_encode_long(9223372036854775807), hb("feffffffffffffffff01")) { ok = false; }
  if !bytes_equal(avro_encode_long(-9223372036854775807 - 1), hb("ffffffffffffffffff01")) { ok = false; }
  return assert(ok, "zig-zag varint encodings across every width boundary");
}

fn t2() -> TestResult {
  var vals = Vec[Int].new();
  vals.push(0);
  vals.push(-1);
  vals.push(1);
  vals.push(2);
  vals.push(-2);
  vals.push(63);
  vals.push(-64);
  vals.push(64);
  vals.push(-65);
  vals.push(2147483647);
  vals.push(-2147483648);
  vals.push(2147483648);
  vals.push(-2147483649);
  vals.push(9223372036854775807);
  vals.push(-9223372036854775807 - 1);
  var ok = true;
  var i = 0;
  while i < vals.len() {
    let n: Int = vals[i];
    if !roundtrip_long(n) { ok = false; }
    i = i + 1;
  }
  return assert(ok, "zig-zag varint decode round-trips across the Int range");
}

fn t3() -> TestResult {
  var ok = err_int_is(avro_decode_long(hb("8080808080808080808080")), "avro: varint longer than 10 bytes at offset 0");
  if !err_int_is(avro_decode_long(hb("ffffffffffffffffffff")), "avro: varint longer than 10 bytes at offset 0") { ok = false; }
  if !err_int_is(avro_decode_long(hb("ffffffffffffffffff02")), "avro: varint overflow at offset 0") { ok = false; }
  if !err_int_is(avro_decode_long(hb("80")), "avro: truncated input at offset 1") { ok = false; }
  if !err_int_is(avro_decode_long(hb("")), "avro: truncated input at offset 0") { ok = false; }
  if !err_int_is(avro_decode_long(hb("0000")), "avro: trailing data at offset 1") { ok = false; }
  // Non-minimal encodings of at most 10 bytes decode (the spec does not
  // require the shortest form on read).
  if !ok_long(hb("8000"), 0) { ok = false; }
  if !ok_long(hb("80808080808080808000"), 0) { ok = false; }
  if avro_max_varint_bytes() != 10 { ok = false; }
  return assert(ok, "overlong varints are rejected, 10-byte encodings are capped");
}

fn t4() -> TestResult {
  var ok = ok_int(hb("feffffff0f"), 2147483647);
  if !ok_int(hb("ffffffff0f"), -2147483648) { ok = false; }
  if !ok_int(hb("7e"), 63) { ok = false; }
  if !err_int_is(avro_decode_int(hb("8080808010")), "avro: int out of range at offset 0") { ok = false; }
  if !err_int_is(avro_decode_int(hb("8180808010")), "avro: int out of range at offset 0") { ok = false; }
  // The same value is a valid long.
  if !ok_long(hb("8080808010"), 2147483648) { ok = false; }
  var cur = avro_cursor(hb("dc01"));
  let r = avro_read_int(&mut cur);
  if !r.is_ok {
    ok = false;
  } else {
    let v: Int = r.value;
    if v != 110 { ok = false; }
    if cur_pos_mut(&mut cur) != 2 { ok = false; }
  }
  return assert(ok, "int32 range is enforced on decode, long accepts 2^31");
}

fn t5() -> TestResult {
  var ok = bytes_equal(avro_encode_boolean(true), hb("01"));
  if !bytes_equal(avro_encode_boolean(false), hb("00")) { ok = false; }
  if !ok_bool_val(hb("01"), true) { ok = false; }
  if !ok_bool_val(hb("00"), false) { ok = false; }
  if !err_bool_is(avro_decode_boolean(hb("02")), "avro: invalid boolean 0x02 at offset 0") { ok = false; }
  if !err_bool_is(avro_decode_boolean(hb("80")), "avro: invalid boolean 0x80 at offset 0") { ok = false; }
  if !err_bool_is(avro_decode_boolean(hb("")), "avro: truncated input at offset 0") { ok = false; }
  if !err_bool_is(avro_decode_boolean(hb("0101")), "avro: trailing data at offset 1") { ok = false; }
  return assert(ok, "boolean octets 0/1 encode, decode and reject other values");
}

fn t6() -> TestResult {
  var ok = avro_encode_null().len() == 0;
  var cur = avro_cursor(Vec[UInt8].new());
  let rn = avro_read_null(&mut cur);
  if !rn.is_ok { ok = false; }
  if cur_pos_mut(&mut cur) != 0 { ok = false; }
  var parts = Vec[Vec[UInt8]].new();
  parts.push(avro_encode_null());
  parts.push(avro_encode_long(5));
  parts.push(avro_encode_string("x"));
  let rec = avro_encode_record(&parts);
  if !bytes_equal(rec, hb("0a0278")) { ok = false; }
  var cur2 = avro_cursor(rec);
  let r1 = avro_read_null(&mut cur2);
  if !r1.is_ok { ok = false; }
  let r2 = avro_read_long(&mut cur2);
  if !r2.is_ok {
    ok = false;
  } else {
    let v: Int = r2.value;
    if v != 5 { ok = false; }
  }
  let r3 = avro_read_string(&mut cur2);
  if !r3.is_ok {
    ok = false;
  } else {
    let s: Str = r3.value;
    if str_compare(s, "x") != 0 { ok = false; }
  }
  if !cur_done_mut(&mut cur2) { ok = false; }
  return assert(ok, "null is zero bytes; records concatenate fields");
}

fn t7() -> TestResult {
  var ok = bytes_equal(avro_encode_bytes(ab("spam")), hb("087370616d"));
  if !bytes_equal(avro_encode_bytes(hb("")), hb("00")) { ok = false; }
  let r = avro_decode_bytes(hb("087370616d"));
  if !r.is_ok {
    ok = false;
  } else {
    let b: Vec[UInt8] = r.value;
    if !bytes_equal(b, ab("spam")) { ok = false; }
  }
  let e = avro_decode_bytes(hb("00"));
  if !e.is_ok {
    ok = false;
  } else {
    let eb: Vec[UInt8] = e.value;
    if eb.len() != 0 { ok = false; }
  }
  let big = fill_bytes(300, 170);
  let enc = avro_encode_bytes(big);
  if byte_at_v(enc, 0) != 0xD8 { ok = false; }
  if byte_at_v(enc, 1) != 0x04 { ok = false; }
  if enc.len() != 302 { ok = false; }
  let rb = avro_decode_bytes(enc);
  if !rb.is_ok {
    ok = false;
  } else {
    let got: Vec[UInt8] = rb.value;
    if !bytes_equal(got, fill_bytes(300, 170)) { ok = false; }
  }
  return assert(ok, "bytes encode as zig-zag length plus payload");
}

fn t8() -> TestResult {
  var ok = err_bytes_is(avro_decode_bytes(hb("01")), "avro: negative length -1 at offset 0");
  if !err_bytes_is(avro_decode_bytes(hb("03")), "avro: negative length -2 at offset 0") { ok = false; }
  if !err_bytes_is(avro_decode_bytes(hb("08737061")), "avro: truncated input at offset 1") { ok = false; }
  if !err_bytes_is(avro_decode_bytes(hb("80")), "avro: truncated input at offset 1") { ok = false; }
  var cur = avro_cursor(hb("0003"));
  let r1 = avro_read_bytes(&mut cur);
  if !r1.is_ok {
    ok = false;
  } else {
    let v: Vec[UInt8] = r1.value;
    if v.len() != 0 { ok = false; }
  }
  let r2 = avro_read_bytes(&mut cur);
  if !err_bytes_is(r2, "avro: negative length -2 at offset 1") { ok = false; }
  return assert(ok, "negative and truncated byte lengths carry byte offsets");
}

fn t9() -> TestResult {
  let enc = avro_encode_string("héllo");
  var ok = byte_at_v(enc, 0) == 0x0C;
  if enc.len() != 7 { ok = false; }
  let r = avro_decode_string(enc);
  if !r.is_ok {
    ok = false;
  } else {
    let s: Str = r.value;
    if str_compare(s, "héllo") != 0 { ok = false; }
  }
  let e = avro_decode_string(hb("00"));
  if !e.is_ok {
    ok = false;
  } else {
    let es: Str = e.value;
    if str_compare(es, "") != 0 { ok = false; }
  }
  if !err_str_is(avro_decode_string(hb("0200")), "avro: string contains NUL at offset 1") { ok = false; }
  if !err_str_is(avro_decode_string(hb("046100")), "avro: string contains NUL at offset 2") { ok = false; }
  var cur = avro_cursor(hb("0200"));
  let rb = avro_read_string_bytes(&mut cur);
  if !rb.is_ok {
    ok = false;
  } else {
    let b: Vec[UInt8] = rb.value;
    if !bytes_equal(b, hb("00")) { ok = false; }
  }
  return assert(ok, "string encodes UTF-8 byte length; NUL payloads are rejected");
}

fn t10() -> TestResult {
  let f = avro_encode_float_le(hb("3f800000"));
  var ok = f.is_ok;
  if f.is_ok {
    let fb: Vec[UInt8] = f.value;
    if !bytes_equal(fb, hb("3f800000")) { ok = false; }
  }
  let d = avro_encode_double_le(hb("3ff0000000000000"));
  if !d.is_ok {
    ok = false;
  } else {
    let db: Vec[UInt8] = d.value;
    if !bytes_equal(db, hb("3ff0000000000000")) { ok = false; }
  }
  let df = avro_decode_float(hb("3f800000"));
  if !df.is_ok {
    ok = false;
  } else {
    let dbf: Vec[UInt8] = df.value;
    if !bytes_equal(dbf, hb("3f800000")) { ok = false; }
  }
  if !err_bytes_is(avro_encode_float_le(hb("3f8000")), "avro: float requires 4 bytes, got 3") { ok = false; }
  if !err_bytes_is(avro_encode_double_le(hb("3ff00000000000")), "avro: double requires 8 bytes, got 7") { ok = false; }
  if !err_bytes_is(avro_decode_float(hb("3f8000")), "avro: truncated input at offset 0") { ok = false; }
  if !err_bytes_is(avro_decode_float(hb("3f80000000")), "avro: trailing data at offset 4") { ok = false; }
  if !bytes_equal(avro_encode_fixed(ab("AB")), ab("AB")) { ok = false; }
  var cur = avro_cursor(hb("deadbeef"));
  let rf = avro_read_fixed(&mut cur, 2);
  if !rf.is_ok {
    ok = false;
  } else {
    let fbv: Vec[UInt8] = rf.value;
    if !bytes_equal(fbv, hb("dead")) { ok = false; }
  }
  if cur_pos_mut(&mut cur) != 2 { ok = false; }
  if !err_bytes_is(avro_read_fixed(&mut cur, -1), "avro: negative fixed size -1 at offset 2") { ok = false; }
  if !err_bytes_is(avro_read_fixed(&mut cur, 3), "avro: truncated input at offset 2") { ok = false; }
  if !err_bytes_is(avro_decode_fixed(hb("deadbeef"), 3), "avro: trailing data at offset 3") { ok = false; }
  return assert(ok, "float/double are raw LE octets; fixed(n) is raw and size-checked");
}

fn t11() -> TestResult {
  let e = avro_encode_enum_index(2);
  var ok = false;
  if e.is_ok {
    let eb: Vec[UInt8] = e.value;
    ok = bytes_equal(eb, hb("04"));
  }
  if !err_bytes_is(avro_encode_enum_index(-1), "avro: negative enum index -1") { ok = false; }
  let u = avro_encode_union_index(0);
  if !u.is_ok {
    ok = false;
  } else {
    let ub: Vec[UInt8] = u.value;
    if !bytes_equal(ub, hb("00")) { ok = false; }
  }
  if !err_bytes_is(avro_encode_union_index(-1), "avro: negative union index -1") { ok = false; }
  var cur = avro_cursor(hb("01"));
  let rn = avro_read_enum_index(&mut cur);
  if !err_int_is(rn, "avro: negative enum index -1 at offset 0") { ok = false; }
  var cur2 = avro_cursor(hb("01"));
  let ru = avro_read_union_index(&mut cur2);
  if !err_int_is(ru, "avro: negative union index -1 at offset 0") { ok = false; }
  var cur3 = avro_cursor(hb("feffffff0f"));
  let rv = avro_read_enum_index(&mut cur3);
  if !rv.is_ok {
    ok = false;
  } else {
    let v: Int = rv.value;
    if v != 2147483647 { ok = false; }
  }
  var cur4 = avro_cursor(hb("8080808010"));
  let rw = avro_read_enum_index(&mut cur4);
  if !err_int_is(rw, "avro: int out of range at offset 0") { ok = false; }
  var cur5 = avro_cursor(hb("feffffffffffffffff01"));
  let rz = avro_read_union_index(&mut cur5);
  if !rz.is_ok {
    ok = false;
  } else {
    let v2: Int = rz.value;
    if v2 != 9223372036854775807 { ok = false; }
  }
  return assert(ok, "enum and union indices are non-negative zig-zag ints/longs");
}

fn t12() -> TestResult {
  var ok = bytes_equal(avro_encode_array_long(longs3(1, 2, 3)), hb("0602040600"));
  if !array_long_ok(hb("0602040600"), longs3(1, 2, 3)) { ok = false; }
  if !array_long_ok(hb("04010300"), longs2(-1, -2)) { ok = false; }
  var empty = Vec[Int].new();
  if !bytes_equal(avro_encode_array_long(empty), hb("00")) { ok = false; }
  var none = Vec[Int].new();
  if !array_long_ok(hb("00"), none) { ok = false; }
  var parts = Vec[Vec[UInt8]].new();
  parts.push(avro_encode_long(7));
  parts.push(avro_encode_long(-8));
  if !bytes_equal(avro_encode_array_block(&parts), hb("040e0f")) { ok = false; }
  if !bytes_equal(avro_encode_array(&parts), hb("040e0f00")) { ok = false; }
  if !array_long_ok(hb("040e0f00"), longs2(7, -8)) { ok = false; }
  return assert(ok, "array<long> round-trips; block framing is count + items + 0");
}

fn t13() -> TestResult {
  var ok = array_long_ok(hb("04020404060800"), longs4(1, 2, 3, 4));
  if !array_long_ok(hb("03aabb020a00"), longs1(5)) { ok = false; }
  if !array_err_is(hb("7e"), "avro: truncated input at offset 1") { ok = false; }
  if !array_err_is(hb("03aa"), "avro: truncated input at offset 1") { ok = false; }
  if !array_err_is(hb("020a"), "avro: truncated input at offset 2") { ok = false; }
  let minl = avro_encode_long(-9223372036854775807 - 1);
  if !array_err_is(minl, "avro: invalid block count at offset 0") { ok = false; }
  return assert(ok, "array blocks skip negative-size blocks and reject truncation");
}

fn t14() -> TestResult {
  let e = avro_encode_map_of_longs(strs2("a", "b"), longs2(1, 2));
  var ok = false;
  if e.is_ok {
    let eb: Vec[UInt8] = e.value;
    ok = bytes_equal(eb, hb("0402610202620400"));
  }
  if !map_long_ok(hb("0402610202620400"), keyvec2("a", "b"), longs2(1, 2)) { ok = false; }
  if !map_long_ok(hb("03aabb0202610a00"), keyvec1("a"), longs1(5)) { ok = false; }
  var no_keys = Vec[Str].new();
  var no_vals = Vec[Int].new();
  let em = avro_encode_map_of_longs(no_keys, no_vals);
  if !em.is_ok {
    ok = false;
  } else {
    let emb: Vec[UInt8] = em.value;
    if !bytes_equal(emb, hb("00")) { ok = false; }
  }
  let mm = avro_encode_map_of_longs(strs1("a"), longs2(1, 2));
  if !err_bytes_is(mm, "avro: map keys/values length mismatch") { ok = false; }
  var dk = Vec[Vec[UInt8]].new();
  var dv = Vec[Int].new();
  if !err_int_is(avro_decode_map_bytes_long(hb("060261"), &mut dk, &mut dv), "avro: truncated input at offset 1") { ok = false; }
  var parts = Vec[Vec[UInt8]].new();
  parts.push(avro_encode_string("k"));
  var pvals = Vec[Vec[UInt8]].new();
  pvals.push(avro_encode_long(7));
  let mb = avro_encode_map_block(&parts, &pvals);
  if !mb.is_ok {
    ok = false;
  } else {
    let mbb: Vec[UInt8] = mb.value;
    if !bytes_equal(mbb, hb("02026b0e")) { ok = false; }
  }
  return assert(ok, "map<bytes,long> round-trips; blocks, skips and mismatch errors");
}

fn t15() -> TestResult {
  var h = avro_ocf_magic();
  h = concat_bytes(h, hb("04"));
  h = concat_bytes(h, hb("166176726f2e736368656d61"));
  h = concat_bytes(h, hb("06696e74"));
  h = concat_bytes(h, hb("146176726f2e636f646563"));
  h = concat_bytes(h, hb("086e756c6c"));
  h = concat_bytes(h, hb("00"));
  h = concat_bytes(h, hb("000102030405060708090a0b0c0d0e0f"));
  let r = avro_parse_ocf_header(h);
  if !r.is_ok {
    return assert(false, "OCF header parses magic, metadata, codec and sync");
  }
  let hdr: AvroOcfHeader = r.value;
  var ok = avro_ocf_header_len(&hdr) == 54;
  if avro_ocf_metadata_count(&hdr) != 2 { ok = false; }
  if !bytes_equal(avro_ocf_codec(&hdr), ab("null")) { ok = false; }
  if !bytes_equal(avro_ocf_codec_or_null(&hdr), ab("null")) { ok = false; }
  if !bytes_equal(avro_ocf_schema(&hdr), ab("int")) { ok = false; }
  if avro_ocf_metadata_find(&hdr, ab("avro.schema")) != 0 { ok = false; }
  if avro_ocf_metadata_find(&hdr, ab("avro.codec")) != 1 { ok = false; }
  if avro_ocf_metadata_find(&hdr, ab("missing")) != -1 { ok = false; }
  if !bytes_equal(avro_ocf_metadata_key(&hdr, 0), ab("avro.schema")) { ok = false; }
  if !bytes_equal(avro_ocf_metadata_key(&hdr, 1), ab("avro.codec")) { ok = false; }
  if !bytes_equal(avro_ocf_metadata_value(&hdr, 1), ab("null")) { ok = false; }
  if avro_ocf_metadata_key(&hdr, 2).len() != 0 { ok = false; }
  if avro_ocf_metadata_value(&hdr, -1).len() != 0 { ok = false; }
  if !bytes_equal(avro_ocf_sync(&hdr), hb("000102030405060708090a0b0c0d0e0f")) { ok = false; }
  if avro_ocf_sync_byte(&hdr, 0) != 0 { ok = false; }
  if avro_ocf_sync_byte(&hdr, 15) != 15 { ok = false; }
  if avro_ocf_sync_byte(&hdr, 16) != -1 { ok = false; }
  if avro_ocf_sync_byte(&hdr, -1) != -1 { ok = false; }
  if avro_ocf_sync_size() != 16 { ok = false; }
  if !bytes_equal(avro_ocf_magic(), hb("4f626a01")) { ok = false; }
  // Extra bytes after the header belong to the first data block and are not
  // consumed by the header parser.
  let with_block = concat_bytes(h, hb("aa"));
  let r2 = avro_parse_ocf_header(with_block);
  if !r2.is_ok {
    ok = false;
  } else {
    let hdr2: AvroOcfHeader = r2.value;
    if avro_ocf_header_len(&hdr2) != 54 { ok = false; }
  }
  return assert(ok, "OCF header parses magic, metadata, codec and sync");
}

fn t16() -> TestResult {
  var ok = err_hdr_is(avro_parse_ocf_header(hb("4f626a02")), "avro: bad magic at offset 0");
  if !err_hdr_is(avro_parse_ocf_header(hb("00000000")), "avro: bad magic at offset 0") { ok = false; }
  if !err_hdr_is(avro_parse_ocf_header(hb("4f626b01")), "avro: bad magic at offset 0") { ok = false; }
  if !err_hdr_is(avro_parse_ocf_header(hb("4f62")), "avro: truncated input at offset 0") { ok = false; }
  var h = avro_ocf_magic();
  if !err_hdr_is(avro_parse_ocf_header(h), "avro: truncated input at offset 4") { ok = false; }
  h = concat_bytes(h, hb("04"));
  if !err_hdr_is(avro_parse_ocf_header(h), "avro: truncated input at offset 5") { ok = false; }
  h = concat_bytes(h, hb("16"));
  if !err_hdr_is(avro_parse_ocf_header(h), "avro: truncated input at offset 5") { ok = false; }
  // A well-formed block count whose first key length overruns the buffer.
  var e = avro_ocf_magic();
  e = concat_bytes(e, hb("020261"));
  e = concat_bytes(e, hb("16"));
  if !err_hdr_is(avro_parse_ocf_header(e), "avro: truncated input at offset 8") { ok = false; }
  // Negative metadata block: skipped verbatim.
  var n = avro_ocf_magic();
  n = concat_bytes(n, hb("03aabb00"));
  n = concat_bytes(n, hb("000102030405060708090a0b0c0d0e0f"));
  let rn = avro_parse_ocf_header(n);
  if !rn.is_ok {
    ok = false;
  } else {
    let nh: AvroOcfHeader = rn.value;
    if avro_ocf_metadata_count(&nh) != 0 { ok = false; }
    if avro_ocf_header_len(&nh) != 24 { ok = false; }
    if !bytes_equal(avro_ocf_codec(&nh), hb("")) { ok = false; }
    if !bytes_equal(avro_ocf_codec_or_null(&nh), ab("null")) { ok = false; }
    if !bytes_equal(avro_ocf_schema(&nh), hb("")) { ok = false; }
  }
  // Truncated sync marker: 4 magic + 1 count + 15 of 16 sync bytes.
  var t = avro_ocf_magic();
  t = concat_bytes(t, hb("00"));
  t = concat_bytes(t, hb("000102030405060708090a0b0c0d0e"));
  if !err_hdr_is(avro_parse_ocf_header(t), "avro: truncated input at offset 5") { ok = false; }
  return assert(ok, "OCF header rejects bad magic and truncated metadata/sync");
}

fn t17() -> TestResult {
  var ok = ok_long(hb("00"), 0);
  if !err_bytes_is(avro_decode_bytes(hb("087370616dff")), "avro: trailing data at offset 5") { ok = false; }
  if !array_err_is(hb("020a00ff"), "avro: trailing data at offset 3") { ok = false; }
  var cur = avro_cursor(hb("01020304"));
  if cur_len_mut(&mut cur) != 4 { ok = false; }
  if cur_pos_mut(&mut cur) != 0 { ok = false; }
  if cur_remaining_mut(&mut cur) != 4 { ok = false; }
  if cur_done_mut(&mut cur) { ok = false; }
  let s1 = avro_cursor_skip(&mut cur, 2);
  if !s1.is_ok {
    ok = false;
  } else {
    let p: Int = s1.value;
    if p != 2 { ok = false; }
  }
  if cur_remaining_mut(&mut cur) != 2 { ok = false; }
  if !err_int_is(avro_cursor_skip(&mut cur, -1), "avro: negative skip -1 at offset 2") { ok = false; }
  if !err_int_is(avro_cursor_skip(&mut cur, 3), "avro: truncated input at offset 2") { ok = false; }
  let s2 = avro_cursor_skip(&mut cur, 2);
  if !s2.is_ok { ok = false; }
  if !cur_done_mut(&mut cur) { ok = false; }
  let s3 = avro_cursor_skip(&mut cur, 0);
  if !s3.is_ok { ok = false; }
  return assert(ok, "whole-buffer helpers reject trailing data; cursor bounds are safe");
}

fn t18() -> TestResult {
  var parts = Vec[Vec[UInt8]].new();
  parts.push(avro_encode_long(-64));
  parts.push(avro_encode_int(100));
  parts.push(avro_encode_string("héllo"));
  parts.push(avro_encode_boolean(true));
  let rec = avro_encode_record(&parts);
  var expected = hb("7fc8010c");
  expected = concat_bytes(expected, ab("héllo"));
  expected = concat_bytes(expected, hb("01"));
  var ok = bytes_equal(rec, expected);
  var cur = avro_cursor(rec);
  let r1 = avro_read_long(&mut cur);
  if !r1.is_ok {
    ok = false;
  } else {
    let v1: Int = r1.value;
    if v1 != -64 { ok = false; }
  }
  let r2 = avro_read_int(&mut cur);
  if !r2.is_ok {
    ok = false;
  } else {
    let v2: Int = r2.value;
    if v2 != 100 { ok = false; }
  }
  let r3 = avro_read_string(&mut cur);
  if !r3.is_ok {
    ok = false;
  } else {
    let v3: Str = r3.value;
    if str_compare(v3, "héllo") != 0 { ok = false; }
  }
  let r4 = avro_read_boolean(&mut cur);
  if !r4.is_ok {
    ok = false;
  } else {
    let v4: Bool = r4.value;
    if !v4 { ok = false; }
  }
  if !cur_done_mut(&mut cur) { ok = false; }
  if cur_pos_mut(&mut cur) != rec.len() { ok = false; }
  return assert(ok, "record fields decode in order from their concatenation");
}

// Encode, decode and verify one byte-string length boundary.
fn len_boundary(n: Int) -> Bool {
  let payload = fill_bytes(n, 170);
  let enc = avro_encode_bytes(payload);
  let r = avro_decode_bytes(enc);
  if !r.is_ok {
    return false;
  }
  let got: Vec[UInt8] = r.value;
  if got.len() != n {
    return false;
  }
  return bytes_equal(got, fill_bytes(n, 170));
}

fn t19() -> TestResult {
  var ok = len_boundary(0);
  if !len_boundary(1) { ok = false; }
  if !len_boundary(63) { ok = false; }
  if !len_boundary(64) { ok = false; }
  if !len_boundary(127) { ok = false; }
  if !len_boundary(128) { ok = false; }
  if !len_boundary(255) { ok = false; }
  if !len_boundary(256) { ok = false; }
  let e63 = avro_encode_bytes(fill_bytes(63, 170));
  if byte_at_v(e63, 0) != 0x7E { ok = false; }
  let e64 = avro_encode_bytes(fill_bytes(64, 170));
  if byte_at_v(e64, 0) != 0x80 { ok = false; }
  if byte_at_v(e64, 1) != 0x01 { ok = false; }
  let e127 = avro_encode_bytes(fill_bytes(127, 170));
  if byte_at_v(e127, 0) != 0xFE { ok = false; }
  if byte_at_v(e127, 1) != 0x01 { ok = false; }
  let e128 = avro_encode_bytes(fill_bytes(128, 170));
  if byte_at_v(e128, 0) != 0x80 { ok = false; }
  if byte_at_v(e128, 1) != 0x02 { ok = false; }
  return assert(ok, "byte-string lengths 0/1/63/64/127/128/255/256 round-trip");
}

fn t20() -> TestResult {
  var cur = avro_cursor(hb("0080"));
  let r1 = avro_read_long(&mut cur);
  if !r1.is_ok {
    return assert(false, "error offsets are measured from the buffer start");
  }
  let r2 = avro_read_long(&mut cur);
  var ok = err_int_is(r2, "avro: truncated input at offset 2");
  var over = hb("00");
  var j = 0;
  while j < 11 {
    over = concat_bytes(over, hb("80"));
    j = j + 1;
  }
  var cur2 = avro_cursor(over);
  let q1 = avro_read_long(&mut cur2);
  if !q1.is_ok { ok = false; }
  let q2 = avro_read_long(&mut cur2);
  if !err_int_is(q2, "avro: varint longer than 10 bytes at offset 1") { ok = false; }
  var ovf = hb("0000ffffffffffffffffff02");
  var cur3 = avro_cursor(ovf);
  let w1 = avro_read_long(&mut cur3);
  if !w1.is_ok { ok = false; }
  let w2 = avro_read_long(&mut cur3);
  if !w2.is_ok { ok = false; }
  let w3 = avro_read_long(&mut cur3);
  if !err_int_is(w3, "avro: varint overflow at offset 2") { ok = false; }
  var cur4 = avro_cursor(hb("00000001"));
  let x1 = avro_read_long(&mut cur4);
  if !x1.is_ok { ok = false; }
  let x2 = avro_read_long(&mut cur4);
  if !x2.is_ok { ok = false; }
  let x3 = avro_read_long(&mut cur4);
  if !x3.is_ok { ok = false; }
  let x4 = avro_read_bytes(&mut cur4);
  if !err_bytes_is(x4, "avro: negative length -1 at offset 3") { ok = false; }
  return assert(ok, "error offsets are measured from the buffer start");
}

fn main() -> Int {
  io.println("=== xiom.avro conformance tests ===");
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
    io.println("xiom.avro: all tests passed");
  } else {
    io.println("xiom.avro: tests failed");
  }
  return failed;
}
