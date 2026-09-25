// XIOM -- xiom.cbor conformance tests (20 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Covers the documented API: canonical integer encodes across every width
// boundary, integer decode and reserialize round-trips, non-shortest-form
// rejection, reserved additional info, indefinite lengths, tags, floats,
// simple values, breaks, malformed/truncated strings, length overflow and
// integer out of range, byte/text string payload access, array and map child
// ranges, canonical map ordering and duplicate rejection, bool/null/
// undefined, the nesting depth cap, compound round-trips, bounds-safe
// accessors and the 23/24/255/256/65535/65536 string length boundaries.
//
// Harness style mirrors xiom.hello / xiom.bencode: one fn tN() -> TestResult
// per check, called directly from main; main prints [PASS]/[FAIL] and
// returns the failure count. Str payloads are compared with str_compare
// (BUG 17 discipline: `==` on Str values read from a Vec lowers to a
// pointer comparison).

module cbor_tests
use xiom.io; use xiom.test;
use xiom.string; use xiom.string.compare; use xiom.string.builder;
use xiom.encoding.hex;
use xiom.cbor;

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

// Decode `data` and compare the error text with `want`.
fn err_is(data: Vec[UInt8], want: Str) -> Bool {
  let r = cbor_decode(data);
  if r.is_ok {
    return false;
  }
  return str_compare(r.error, want) == 0;
}

// Compare an encoder Result error text with `want`.
fn enc_err_is(r: Result[Vec[UInt8], Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_compare(r.error, want) == 0;
}

// Kind of the root token, or -1 when decoding fails.
fn root_kind(data: Vec[UInt8]) -> Int {
  let r = cbor_decode(data);
  if !r.is_ok {
    return -1;
  }
  let d: CborDoc = r.value;
  return cbor_kind(&d, 0);
}

// Integer value of the root token (0 when decoding fails).
fn root_int(data: Vec[UInt8]) -> Int {
  let r = cbor_decode(data);
  if !r.is_ok {
    return 0;
  }
  let d: CborDoc = r.value;
  return cbor_int_value(&d, 0);
}

// encode -> decode -> check kind/value -> reserialize for one integer.
fn int_roundtrip(n: Int) -> Bool {
  let enc = cbor_encode_int(n);
  let r = cbor_decode(enc);
  if !r.is_ok {
    return false;
  }
  let d: CborDoc = r.value;
  let k = cbor_kind(&d, 0);
  if k != cbor_kind_uint() && k != cbor_kind_negint() {
    return false;
  }
  if cbor_int_value(&d, 0) != n {
    return false;
  }
  let back = cbor_reserialize(&d);
  let again = cbor_encode_int(n);
  return bytes_equal(back, again);
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

// Initial byte of a vector, or -1 when empty.
fn first_byte(v: Vec[UInt8]) -> Int {
  if v.len() == 0 {
    return -1;
  }
  let b: UInt8 = v[0];
  return (b as Int) & 0xFF;
}

// Byte `i` of a vector widened to an Int, or -1 when out of range.
fn byte_at_v(v: Vec[UInt8], i: Int) -> Int {
  if i < 0 || i >= v.len() {
    return -1;
  }
  let b: UInt8 = v[i];
  return (b as Int) & 0xFF;
}

// `depth` nested single-element arrays around uint 0: 0x81 repeated, then
// 0x00 (CBOR containers need no closing byte).
fn nested_arrays(depth: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < depth {
    out.push(0x81 as UInt8);
    i = i + 1;
  }
  out.push(0x00 as UInt8);
  return out;
}

// `depth` nested single-pair maps around uint 0: {0: {0: ... 0}}.
fn nested_maps(depth: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < depth {
    out.push(0xA1 as UInt8);
    out.push(0x00 as UInt8);
    i = i + 1;
  }
  out.push(0x00 as UInt8);
  return out;
}

// Value token stored under the first text key equal to `want` in map token
// `map_tok`, or -1 when absent (linear pair scan).
fn map_get_text(doc: &CborDoc, map_tok: Int, want: Vec[UInt8]) -> Int {
  let count = cbor_child_count(doc, map_tok);
  var i = 0;
  while i + 1 < count {
    let kt = cbor_child(doc, map_tok, i);
    if cbor_kind(doc, kt) == cbor_kind_text() {
      let kb = cbor_text_bytes(doc, kt);
      if bytes_equal(kb, want) {
        return cbor_child(doc, map_tok, i + 1);
      }
    }
    i = i + 2;
  }
  return -1;
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  var ok = bytes_equal(cbor_encode_int(0), hb("00"));
  if !bytes_equal(cbor_encode_int(1), hb("01")) { ok = false; }
  if !bytes_equal(cbor_encode_int(10), hb("0a")) { ok = false; }
  if !bytes_equal(cbor_encode_int(23), hb("17")) { ok = false; }
  if !bytes_equal(cbor_encode_int(24), hb("1818")) { ok = false; }
  if !bytes_equal(cbor_encode_int(255), hb("18ff")) { ok = false; }
  if !bytes_equal(cbor_encode_int(256), hb("190100")) { ok = false; }
  if !bytes_equal(cbor_encode_int(65535), hb("19ffff")) { ok = false; }
  if !bytes_equal(cbor_encode_int(65536), hb("1a00010000")) { ok = false; }
  if !bytes_equal(cbor_encode_int(4294967295), hb("1affffffff")) { ok = false; }
  if !bytes_equal(cbor_encode_int(4294967296), hb("1b0000000100000000")) { ok = false; }
  if !bytes_equal(cbor_encode_int(9223372036854775807), hb("1b7fffffffffffffff")) { ok = false; }
  if !bytes_equal(cbor_encode_int(-1), hb("20")) { ok = false; }
  if !bytes_equal(cbor_encode_int(-10), hb("29")) { ok = false; }
  if !bytes_equal(cbor_encode_int(-24), hb("37")) { ok = false; }
  if !bytes_equal(cbor_encode_int(-25), hb("3818")) { ok = false; }
  if !bytes_equal(cbor_encode_int(-256), hb("38ff")) { ok = false; }
  if !bytes_equal(cbor_encode_int(-257), hb("390100")) { ok = false; }
  if !bytes_equal(cbor_encode_int(-65536), hb("39ffff")) { ok = false; }
  if !bytes_equal(cbor_encode_int(-65537), hb("3a00010000")) { ok = false; }
  if !bytes_equal(cbor_encode_int(-4294967296), hb("3affffffff")) { ok = false; }
  if !bytes_equal(cbor_encode_int(-4294967297), hb("3b0000000100000000")) { ok = false; }
  let int_min = 0 - 9223372036854775807 - 1;
  if !bytes_equal(cbor_encode_int(int_min), hb("3b7fffffffffffffff")) { ok = false; }
  return assert(ok, "canonical integer encodings across every width boundary");
}

fn t2() -> TestResult {
  var ok = root_kind(hb("00")) == cbor_kind_uint();
  if root_kind(hb("17")) != cbor_kind_uint() { ok = false; }
  if root_kind(hb("1818")) != cbor_kind_uint() { ok = false; }
  if root_kind(hb("3b7fffffffffffffff")) != cbor_kind_negint() { ok = false; }
  if root_int(hb("00")) != 0 { ok = false; }
  if root_int(hb("1818")) != 24 { ok = false; }
  if root_int(hb("190100")) != 256 { ok = false; }
  if root_int(hb("1b7fffffffffffffff")) != 9223372036854775807 { ok = false; }
  if root_int(hb("20")) != -1 { ok = false; }
  if root_int(hb("3818")) != -25 { ok = false; }
  if root_int(hb("390100")) != -257 { ok = false; }
  let int_min = 0 - 9223372036854775807 - 1;
  if root_int(hb("3b7fffffffffffffff")) != int_min { ok = false; }
  var vals = Vec[Int].new();
  vals.push(0);
  vals.push(1);
  vals.push(23);
  vals.push(24);
  vals.push(255);
  vals.push(256);
  vals.push(65535);
  vals.push(65536);
  vals.push(4294967295);
  vals.push(4294967296);
  vals.push(9223372036854775807);
  vals.push(-1);
  vals.push(-24);
  vals.push(-25);
  vals.push(-256);
  vals.push(-257);
  vals.push(-65536);
  vals.push(-65537);
  vals.push(-4294967296);
  vals.push(-4294967297);
  vals.push(int_min);
  var i = 0;
  while i < vals.len() {
    let n: Int = vals[i];
    if !int_roundtrip(n) { ok = false; }
    i = i + 1;
  }
  return assert(ok, "integer decode and reserialize round-trips across the Int range");
}

fn t3() -> TestResult {
  var ok = err_is(hb("1817"), "cbor: non-shortest form");
  if !err_is(hb("1900ff"), "cbor: non-shortest form") { ok = false; }
  if !err_is(hb("1a0000ffff"), "cbor: non-shortest form") { ok = false; }
  if !err_is(hb("1b00000000ffffffff"), "cbor: non-shortest form") { ok = false; }
  if !err_is(hb("3817"), "cbor: non-shortest form") { ok = false; }
  if !err_is(hb("3900ff"), "cbor: non-shortest form") { ok = false; }
  if !err_is(hb("580161"), "cbor: non-shortest form") { ok = false; }
  if !err_is(hb("780161"), "cbor: non-shortest form") { ok = false; }
  if !err_is(hb("590020"), "cbor: non-shortest form") { ok = false; }
  if !err_is(hb("9800"), "cbor: non-shortest form") { ok = false; }
  if !err_is(hb("9a00000000"), "cbor: non-shortest form") { ok = false; }
  if !err_is(hb("b800"), "cbor: non-shortest form") { ok = false; }
  if !err_is(hb("f800"), "cbor: non-shortest form") { ok = false; }
  if !err_is(hb("f81f"), "cbor: non-shortest form") { ok = false; }
  return assert(ok, "non-shortest arguments are rejected");
}

fn t4() -> TestResult {
  var ok = err_is(hb("1c"), "cbor: reserved additional info 28");
  if !err_is(hb("1d"), "cbor: reserved additional info 29") { ok = false; }
  if !err_is(hb("1e"), "cbor: reserved additional info 30") { ok = false; }
  if !err_is(hb("3c"), "cbor: reserved additional info 28") { ok = false; }
  if !err_is(hb("5d"), "cbor: reserved additional info 29") { ok = false; }
  if !err_is(hb("7e"), "cbor: reserved additional info 30") { ok = false; }
  if !err_is(hb("9c"), "cbor: reserved additional info 28") { ok = false; }
  if !err_is(hb("bd"), "cbor: reserved additional info 29") { ok = false; }
  if !err_is(hb("de"), "cbor: reserved additional info 30") { ok = false; }
  if !err_is(hb("fc"), "cbor: reserved additional info 28") { ok = false; }
  if !err_is(hb("1f"), "cbor: reserved additional info 31") { ok = false; }
  if !err_is(hb("3f"), "cbor: reserved additional info 31") { ok = false; }
  if !err_is(hb("df"), "cbor: reserved additional info 31") { ok = false; }
  return assert(ok, "reserved additional info 28-31 is rejected");
}

fn t5() -> TestResult {
  var ok = err_is(hb("5f"), "cbor: indefinite length not supported");
  if !err_is(hb("7f"), "cbor: indefinite length not supported") { ok = false; }
  if !err_is(hb("9f"), "cbor: indefinite length not supported") { ok = false; }
  if !err_is(hb("bf"), "cbor: indefinite length not supported") { ok = false; }
  if !err_is(hb("5f4100ff"), "cbor: indefinite length not supported") { ok = false; }
  if !err_is(hb("9f01ff"), "cbor: indefinite length not supported") { ok = false; }
  return assert(ok, "indefinite-length items are rejected");
}

fn t6() -> TestResult {
  var ok = err_is(hb("c0"), "cbor: tags not supported");
  if !err_is(hb("c6"), "cbor: tags not supported") { ok = false; }
  if !err_is(hb("d818"), "cbor: tags not supported") { ok = false; }
  if !err_is(hb("d9d9f7"), "cbor: tags not supported") { ok = false; }
  if !err_is(hb("db0000000000000000"), "cbor: tags not supported") { ok = false; }
  if !err_is(hb("db"), "cbor: tags not supported") { ok = false; }
  return assert(ok, "major type 6 tags are rejected from the initial byte");
}

fn t7() -> TestResult {
  var ok = err_is(hb("f90000"), "cbor: floats not supported");
  if !err_is(hb("fa00000000"), "cbor: floats not supported") { ok = false; }
  if !err_is(hb("fb0000000000000000"), "cbor: floats not supported") { ok = false; }
  if !err_is(hb("f9"), "cbor: floats not supported") { ok = false; }
  if !err_is(hb("e0"), "cbor: simple values not supported") { ok = false; }
  if !err_is(hb("f3"), "cbor: simple values not supported") { ok = false; }
  if !err_is(hb("f820"), "cbor: simple values not supported") { ok = false; }
  if !err_is(hb("f8ff"), "cbor: simple values not supported") { ok = false; }
  if !err_is(hb("f8"), "cbor: truncated input") { ok = false; }
  return assert(ok, "floats and unsupported simple values are rejected");
}

fn t8() -> TestResult {
  var ok = err_is(hb("ff"), "cbor: break outside indefinite item");
  if !err_is(hb("01ff"), "cbor: trailing data after top-level value") { ok = false; }
  if !err_is(hb("0000"), "cbor: trailing data after top-level value") { ok = false; }
  if !err_is(hb("f600"), "cbor: trailing data after top-level value") { ok = false; }
  if !err_is(hb("8000"), "cbor: trailing data after top-level value") { ok = false; }
  if !err_is(hb("810102"), "cbor: trailing data after top-level value") { ok = false; }
  if !err_is(hb(""), "cbor: truncated input") { ok = false; }
  return assert(ok, "break outside indefinite items and trailing data are rejected");
}

fn t9() -> TestResult {
  var ok = bytes_equal(cbor_encode_bytes(hb("")), hb("40"));
  let spam = ab("spam");
  let enc = cbor_encode_bytes(&spam);
  if !bytes_equal(enc, hb("447370616d")) { ok = false; }
  let r = cbor_decode(enc);
  if !r.is_ok {
    ok = false;
  } else {
    let d: CborDoc = r.value;
    if cbor_kind(&d, 0) != cbor_kind_bytes() { ok = false; }
    if cbor_bytes_len(&d, 0) != 4 { ok = false; }
    if !bytes_equal(cbor_bytes(&d, 0), ab("spam")) { ok = false; }
    if cbor_token_start(&d, 0) != 0 { ok = false; }
    if cbor_token_end(&d, 0) != 5 { ok = false; }
    if !bytes_equal(cbor_token_bytes(&d, 0), hb("447370616d")) { ok = false; }
    if !bytes_equal(cbor_reserialize(&d), hb("447370616d")) { ok = false; }
  }
  let e = cbor_decode(hb("40"));
  if !e.is_ok {
    ok = false;
  } else {
    let de: CborDoc = e.value;
    if cbor_bytes_len(&de, 0) != 0 { ok = false; }
    let eb = cbor_bytes(&de, 0);
    if eb.len() != 0 { ok = false; }
    if cbor_token_end(&de, 0) != 1 { ok = false; }
  }
  return assert(ok, "byte-string encodings, decode and payload access");
}

fn t10() -> TestResult {
  var ok = bytes_equal(cbor_encode_text(""), hb("60"));
  let enc = cbor_encode_text("héllo");
  let expected = concat_bytes(hb("66"), ab("héllo"));
  if !bytes_equal(enc, expected) { ok = false; }
  let r = cbor_decode(enc);
  if !r.is_ok {
    ok = false;
  } else {
    let d: CborDoc = r.value;
    if cbor_kind(&d, 0) != cbor_kind_text() { ok = false; }
    if cbor_text_len(&d, 0) != 6 { ok = false; }
    let got = cbor_text_bytes(&d, 0);
    if !bytes_equal(got, ab("héllo")) { ok = false; }
    let rebuilt = builder.sb_to_str(&got);
    if str_compare(rebuilt, "héllo") != 0 { ok = false; }
    if cbor_bytes_len(&d, 0) != -1 { ok = false; }
    if !bytes_equal(cbor_reserialize(&d), expected) { ok = false; }
  }
  let r2 = cbor_decode(hb("6161"));
  if !r2.is_ok {
    ok = false;
  } else {
    let d2: CborDoc = r2.value;
    if cbor_text_len(&d2, 0) != 1 { ok = false; }
    if cbor_bytes_len(&d2, 0) != -1 { ok = false; }
  }
  return assert(ok, "text-string encodings, UTF-8 byte length and round-trip");
}

fn t11() -> TestResult {
  var ok = err_is(hb("48"), "cbor: truncated input");
  if !err_is(hb("436162"), "cbor: truncated input") { ok = false; }
  if !err_is(hb("58"), "cbor: truncated input") { ok = false; }
  if !err_is(hb("5900"), "cbor: truncated input") { ok = false; }
  if !err_is(hb("5a000000"), "cbor: truncated input") { ok = false; }
  if !err_is(hb("5b00000000000000"), "cbor: truncated input") { ok = false; }
  if !err_is(hb("78"), "cbor: truncated input") { ok = false; }
  if !err_is(hb("5bffffffffffffffff"), "cbor: length overflow") { ok = false; }
  if !err_is(hb("7bffffffffffffffff"), "cbor: length overflow") { ok = false; }
  if !err_is(hb("9bffffffffffffffff"), "cbor: length overflow") { ok = false; }
  if !err_is(hb("1bffffffffffffffff"), "cbor: integer out of range") { ok = false; }
  if !err_is(hb("3bffffffffffffffff"), "cbor: integer out of range") { ok = false; }
  if !err_is(hb("1b8000000000000000"), "cbor: integer out of range") { ok = false; }
  return assert(ok, "malformed headers and out-of-range arguments are rejected");
}

fn t12() -> TestResult {
  let empty = Vec[Vec[UInt8]].new();
  var ok = bytes_equal(cbor_encode_array(&empty), hb("80"));
  var parts = Vec[Vec[UInt8]].new();
  parts.push(cbor_encode_int(1));
  parts.push(cbor_encode_text("a"));
  parts.push(cbor_encode_bool(true));
  let enc = cbor_encode_array(&parts);
  if !bytes_equal(enc, hb("83016161f5")) { ok = false; }
  let r = cbor_decode(enc);
  if !r.is_ok {
    ok = false;
  } else {
    let d: CborDoc = r.value;
    if cbor_kind(&d, 0) != cbor_kind_array() { ok = false; }
    if cbor_token_count(&d) != 4 { ok = false; }
    if cbor_child_count(&d, 0) != 3 { ok = false; }
    if cbor_child(&d, 0, 0) != 1 { ok = false; }
    if cbor_child(&d, 0, 1) != 2 { ok = false; }
    if cbor_child(&d, 0, 2) != 3 { ok = false; }
    if cbor_parent(&d, 1) != 0 { ok = false; }
    if cbor_parent(&d, 3) != 0 { ok = false; }
    if cbor_next_sibling(&d, 1) != 2 { ok = false; }
    if cbor_next_sibling(&d, 2) != 3 { ok = false; }
    if cbor_next_sibling(&d, 3) != -1 { ok = false; }
    if cbor_int_value(&d, 1) != 1 { ok = false; }
    if cbor_text_len(&d, 2) != 1 { ok = false; }
    if cbor_bool_value(&d, 3) != 1 { ok = false; }
    if !bytes_equal(cbor_reserialize(&d), hb("83016161f5")) { ok = false; }
  }
  var inner = Vec[Vec[UInt8]].new();
  inner.push(cbor_encode_int(1));
  let inner_bytes = cbor_encode_array(&inner);
  var outer = Vec[Vec[UInt8]].new();
  outer.push(inner_bytes);
  outer.push(cbor_encode_int(2));
  let enc2 = cbor_encode_array(&outer);
  if !bytes_equal(enc2, hb("82810102")) { ok = false; }
  let r2 = cbor_decode(enc2);
  if !r2.is_ok {
    ok = false;
  } else {
    let d2: CborDoc = r2.value;
    if cbor_token_count(&d2) != 4 { ok = false; }
    if cbor_child(&d2, 0, 0) != 1 { ok = false; }
    if cbor_child(&d2, 0, 1) != 3 { ok = false; }
    if cbor_next_sibling(&d2, 1) != 3 { ok = false; }
    if cbor_child_count(&d2, 1) != 1 { ok = false; }
    if cbor_child(&d2, 1, 0) != 2 { ok = false; }
    if cbor_parent(&d2, 2) != 1 { ok = false; }
    if cbor_parent(&d2, 3) != 0 { ok = false; }
    if !bytes_equal(cbor_reserialize(&d2), hb("82810102")) { ok = false; }
  }
  return assert(ok, "array encodings, child ranges and round-trip");
}

fn t13() -> TestResult {
  var keys = Vec[Vec[UInt8]].new();
  keys.push(cbor_encode_int(1));
  keys.push(cbor_encode_int(1000));
  keys.push(cbor_encode_text("z"));
  var vals = Vec[Vec[UInt8]].new();
  vals.push(cbor_encode_bool(true));
  vals.push(cbor_encode_bool(false));
  vals.push(cbor_encode_int(0));
  let mr = cbor_encode_map(&keys, &vals);
  if !mr.is_ok {
    return assert(false, "map decode, pair children and order-preserving reserialize");
  }
  let enc: Vec[UInt8] = mr.value;
  var ok = bytes_equal(enc, hb("a301f51903e8f4617a00"));
  let r = cbor_decode(enc);
  if !r.is_ok {
    ok = false;
  } else {
    let d: CborDoc = r.value;
    if cbor_kind(&d, 0) != cbor_kind_map() { ok = false; }
    if cbor_child_count(&d, 0) != 6 { ok = false; }
    if cbor_child(&d, 0, 0) != 1 { ok = false; }
    if cbor_child(&d, 0, 1) != 2 { ok = false; }
    if cbor_child(&d, 0, 2) != 3 { ok = false; }
    if cbor_child(&d, 0, 3) != 4 { ok = false; }
    if cbor_child(&d, 0, 4) != 5 { ok = false; }
    if cbor_child(&d, 0, 5) != 6 { ok = false; }
    if cbor_int_value(&d, 1) != 1 { ok = false; }
    if cbor_bool_value(&d, 2) != 1 { ok = false; }
    if cbor_int_value(&d, 3) != 1000 { ok = false; }
    if cbor_bool_value(&d, 4) != 0 { ok = false; }
    if cbor_text_len(&d, 5) != 1 { ok = false; }
    if cbor_int_value(&d, 6) != 0 { ok = false; }
    if !bytes_equal(cbor_reserialize(&d), enc) { ok = false; }
  }
  let e = Vec[Vec[UInt8]].new();
  let er = cbor_encode_map(&e, &e);
  if !er.is_ok {
    ok = false;
  } else {
    let eenc: Vec[UInt8] = er.value;
    if !bytes_equal(eenc, hb("a0")) { ok = false; }
  }
  let input = hb("a2617a0001f5");
  let ru = cbor_decode(input);
  if !ru.is_ok {
    ok = false;
  } else {
    let du: CborDoc = ru.value;
    if cbor_child_count(&du, 0) != 4 { ok = false; }
    if cbor_kind(&du, cbor_child(&du, 0, 0)) != cbor_kind_text() { ok = false; }
    if !bytes_equal(cbor_token_bytes(&du, cbor_child(&du, 0, 0)), hb("617a")) { ok = false; }
    if !bytes_equal(cbor_reserialize(&du), hb("a2617a0001f5")) { ok = false; }
  }
  return assert(ok, "map decode, pair children and order-preserving reserialize");
}

fn t14() -> TestResult {
  var keys = Vec[Vec[UInt8]].new();
  keys.push(cbor_encode_text("z"));
  keys.push(cbor_encode_int(1));
  keys.push(cbor_encode_int(1000));
  var vals = Vec[Vec[UInt8]].new();
  vals.push(cbor_encode_int(0));
  vals.push(cbor_encode_bool(false));
  vals.push(cbor_encode_bool(true));
  var ok = true;
  let r = cbor_encode_map(&keys, &vals);
  if !r.is_ok {
    ok = false;
  } else {
    let enc: Vec[UInt8] = r.value;
    if !bytes_equal(enc, hb("a301f41903e8f5617a00")) { ok = false; }
  }
  let dup1 = cbor_encode_int(1);
  let dup2 = cbor_encode_int(1);
  var dup_keys = Vec[Vec[UInt8]].new();
  dup_keys.push(dup1);
  dup_keys.push(dup2);
  var dup_vals = Vec[Vec[UInt8]].new();
  dup_vals.push(cbor_encode_bool(true));
  dup_vals.push(cbor_encode_bool(false));
  let dup_r = cbor_encode_map(&dup_keys, &dup_vals);
  if !enc_err_is(dup_r, "cbor: duplicate map key") { ok = false; }
  let t1 = cbor_encode_text("a");
  let t2 = cbor_encode_text("a");
  var tdup_keys = Vec[Vec[UInt8]].new();
  tdup_keys.push(t1);
  tdup_keys.push(t2);
  var tdup_vals = Vec[Vec[UInt8]].new();
  tdup_vals.push(cbor_encode_int(1));
  tdup_vals.push(cbor_encode_int(2));
  let tdup_r = cbor_encode_map(&tdup_keys, &tdup_vals);
  if !enc_err_is(tdup_r, "cbor: duplicate map key") { ok = false; }
  var one_val = Vec[Vec[UInt8]].new();
  one_val.push(cbor_encode_int(1));
  let mismatch_r = cbor_encode_map(&dup_keys, &one_val);
  if !enc_err_is(mismatch_r, "cbor: map keys/values length mismatch") { ok = false; }
  return assert(ok, "map encoder sorts keys and rejects duplicates and length mismatch");
}

fn t15() -> TestResult {
  var ok = bytes_equal(cbor_encode_bool(false), hb("f4"));
  if !bytes_equal(cbor_encode_bool(true), hb("f5")) { ok = false; }
  if !bytes_equal(cbor_encode_null(), hb("f6")) { ok = false; }
  if !bytes_equal(cbor_encode_undefined(), hb("f7")) { ok = false; }
  let r = cbor_decode(hb("f4"));
  if !r.is_ok {
    ok = false;
  } else {
    let d: CborDoc = r.value;
    if cbor_kind(&d, 0) != cbor_kind_bool() { ok = false; }
    if cbor_bool_value(&d, 0) != 0 { ok = false; }
    if cbor_int_value(&d, 0) != 0 { ok = false; }
    if !bytes_equal(cbor_reserialize(&d), hb("f4")) { ok = false; }
  }
  let r2 = cbor_decode(hb("f5"));
  if !r2.is_ok {
    ok = false;
  } else {
    let d2: CborDoc = r2.value;
    if cbor_bool_value(&d2, 0) != 1 { ok = false; }
  }
  let r3 = cbor_decode(hb("f6"));
  if !r3.is_ok {
    ok = false;
  } else {
    let d3: CborDoc = r3.value;
    if cbor_kind(&d3, 0) != cbor_kind_null() { ok = false; }
    if cbor_bool_value(&d3, 0) != -1 { ok = false; }
    if !bytes_equal(cbor_reserialize(&d3), hb("f6")) { ok = false; }
  }
  let r4 = cbor_decode(hb("f7"));
  if !r4.is_ok {
    ok = false;
  } else {
    let d4: CborDoc = r4.value;
    if cbor_kind(&d4, 0) != cbor_kind_undefined() { ok = false; }
    if !bytes_equal(cbor_reserialize(&d4), hb("f7")) { ok = false; }
  }
  return assert(ok, "false, true, null and undefined encode and decode");
}

fn t16() -> TestResult {
  var ok = cbor_max_depth() == 64;
  let deep = cbor_decode(nested_arrays(64));
  if !deep.is_ok {
    ok = false;
  } else {
    let d: CborDoc = deep.value;
    if cbor_kind(&d, 0) != cbor_kind_array() { ok = false; }
    if cbor_token_count(&d) != 65 { ok = false; }
    if cbor_kind(&d, 64) != cbor_kind_uint() { ok = false; }
    if !bytes_equal(cbor_reserialize(&d), nested_arrays(64)) { ok = false; }
  }
  if !err_is(nested_arrays(65), "cbor: nesting depth exceeds limit of 64") { ok = false; }
  let deep_map = cbor_decode(nested_maps(64));
  if !deep_map.is_ok {
    ok = false;
  } else {
    let dm: CborDoc = deep_map.value;
    if cbor_token_count(&dm) != 129 { ok = false; }
    if !bytes_equal(cbor_reserialize(&dm), nested_maps(64)) { ok = false; }
  }
  if !err_is(nested_maps(65), "cbor: nesting depth exceeds limit of 64") { ok = false; }
  return assert(ok, "nesting depth cap: 64 accepted, 65 rejected");
}

fn t17() -> TestResult {
  var keys = Vec[Vec[UInt8]].new();
  keys.push(cbor_encode_text("name"));
  keys.push(cbor_encode_text("tags"));
  keys.push(cbor_encode_text("ok"));
  keys.push(cbor_encode_text("nil"));
  keys.push(cbor_encode_text("raw"));
  keys.push(cbor_encode_text("n"));
  var vals = Vec[Vec[UInt8]].new();
  vals.push(cbor_encode_text("xiom"));
  var elems = Vec[Vec[UInt8]].new();
  elems.push(cbor_encode_int(1));
  elems.push(cbor_encode_int(2));
  elems.push(cbor_encode_int(3));
  vals.push(cbor_encode_array(&elems));
  vals.push(cbor_encode_bool(true));
  vals.push(cbor_encode_null());
  let raw = hb("0102");
  vals.push(cbor_encode_bytes(&raw));
  vals.push(cbor_encode_int(-1000));
  let mr = cbor_encode_map(&keys, &vals);
  if !mr.is_ok {
    return assert(false, "compound encode/decode/reserialize round-trip");
  }
  let enc: Vec[UInt8] = mr.value;
  let r = cbor_decode(enc);
  if !r.is_ok {
    return assert(false, "compound encode/decode/reserialize round-trip");
  }
  let d: CborDoc = r.value;
  var ok = cbor_kind(&d, 0) == cbor_kind_map();
  if cbor_child_count(&d, 0) != 12 { ok = false; }
  // Canonical order puts the encoded key "n" (0x616e) first.
  let first_key = cbor_child(&d, 0, 0);
  if cbor_kind(&d, first_key) != cbor_kind_text() { ok = false; }
  if !bytes_equal(cbor_text_bytes(&d, first_key), ab("n")) { ok = false; }
  let name_tok = map_get_text(&d, 0, ab("name"));
  if name_tok < 0 { ok = false; } else {
    if cbor_kind(&d, name_tok) != cbor_kind_text() { ok = false; }
    if cbor_text_len(&d, name_tok) != 4 { ok = false; }
    if !bytes_equal(cbor_text_bytes(&d, name_tok), ab("xiom")) { ok = false; }
  }
  let tags_tok = map_get_text(&d, 0, ab("tags"));
  if tags_tok < 0 { ok = false; } else {
    if cbor_kind(&d, tags_tok) != cbor_kind_array() { ok = false; }
    if cbor_child_count(&d, tags_tok) != 3 { ok = false; }
    if cbor_int_value(&d, cbor_child(&d, tags_tok, 0)) != 1 { ok = false; }
    if cbor_int_value(&d, cbor_child(&d, tags_tok, 1)) != 2 { ok = false; }
    if cbor_int_value(&d, cbor_child(&d, tags_tok, 2)) != 3 { ok = false; }
  }
  let ok_tok = map_get_text(&d, 0, ab("ok"));
  if ok_tok < 0 { ok = false; } else {
    if cbor_bool_value(&d, ok_tok) != 1 { ok = false; }
  }
  let nil_tok = map_get_text(&d, 0, ab("nil"));
  if nil_tok < 0 { ok = false; } else {
    if cbor_kind(&d, nil_tok) != cbor_kind_null() { ok = false; }
  }
  let raw_tok = map_get_text(&d, 0, ab("raw"));
  if raw_tok < 0 { ok = false; } else {
    if cbor_kind(&d, raw_tok) != cbor_kind_bytes() { ok = false; }
    if !bytes_equal(cbor_bytes(&d, raw_tok), hb("0102")) { ok = false; }
  }
  let n_tok = map_get_text(&d, 0, ab("n"));
  if n_tok < 0 { ok = false; } else {
    if cbor_int_value(&d, n_tok) != -1000 { ok = false; }
  }
  if map_get_text(&d, 0, ab("zzz")) != -1 { ok = false; }
  if !bytes_equal(cbor_reserialize(&d), enc) { ok = false; }
  return assert(ok, "compound encode/decode/reserialize round-trip");
}

fn t18() -> TestResult {
  let r = cbor_decode(hb("8101"));
  if !r.is_ok {
    return assert(false, "accessors are bounds-safe and report source offsets");
  }
  let d: CborDoc = r.value;
  var ok = cbor_token_count(&d) == 2;
  if cbor_root(&d) != 0 { ok = false; }
  if cbor_kind(&d, 0) != cbor_kind_array() { ok = false; }
  if cbor_kind(&d, 1) != cbor_kind_uint() { ok = false; }
  if cbor_kind(&d, -1) != -1 { ok = false; }
  if cbor_kind(&d, 2) != -1 { ok = false; }
  if cbor_parent(&d, 0) != -1 { ok = false; }
  if cbor_parent(&d, 1) != 0 { ok = false; }
  if cbor_parent(&d, 5) != -1 { ok = false; }
  if cbor_first_child(&d, 0) != 1 { ok = false; }
  if cbor_first_child(&d, 1) != -1 { ok = false; }
  if cbor_first_child(&d, -1) != -1 { ok = false; }
  if cbor_child_count(&d, 0) != 1 { ok = false; }
  if cbor_child_count(&d, 1) != 0 { ok = false; }
  if cbor_child_count(&d, 9) != 0 { ok = false; }
  if cbor_child(&d, 0, 0) != 1 { ok = false; }
  if cbor_child(&d, 0, 1) != -1 { ok = false; }
  if cbor_child(&d, 0, -1) != -1 { ok = false; }
  if cbor_child(&d, 1, 0) != -1 { ok = false; }
  if cbor_next_sibling(&d, 0) != -1 { ok = false; }
  if cbor_next_sibling(&d, 1) != -1 { ok = false; }
  if cbor_token_start(&d, 0) != 0 { ok = false; }
  if cbor_token_end(&d, 0) != 2 { ok = false; }
  if cbor_token_start(&d, 1) != 1 { ok = false; }
  if cbor_token_end(&d, 1) != 2 { ok = false; }
  if cbor_token_start(&d, -1) != -1 { ok = false; }
  if cbor_token_end(&d, 2) != -1 { ok = false; }
  if cbor_int_value(&d, 0) != 0 { ok = false; }
  if cbor_int_value(&d, 1) != 1 { ok = false; }
  if cbor_int_value(&d, 9) != 0 { ok = false; }
  if cbor_bool_value(&d, 1) != -1 { ok = false; }
  if cbor_bytes_len(&d, 1) != -1 { ok = false; }
  if cbor_text_len(&d, 1) != -1 { ok = false; }
  let b1 = cbor_bytes(&d, 1);
  if b1.len() != 0 { ok = false; }
  let t1 = cbor_text_bytes(&d, 1);
  if t1.len() != 0 { ok = false; }
  if !bytes_equal(cbor_token_bytes(&d, 0), hb("8101")) { ok = false; }
  if !bytes_equal(cbor_token_bytes(&d, 1), hb("01")) { ok = false; }
  let t9 = cbor_token_bytes(&d, 9);
  if t9.len() != 0 { ok = false; }
  return assert(ok, "accessors are bounds-safe and report source offsets");
}

fn t19() -> TestResult {
  let input = hb("a26161016162820203");
  let r = cbor_decode(input);
  if !r.is_ok {
    return assert(false, "hand-written nested map/array decode reconstructs exact bytes");
  }
  let d: CborDoc = r.value;
  var ok = cbor_kind(&d, 0) == cbor_kind_map();
  if cbor_token_count(&d) != 7 { ok = false; }
  if cbor_child_count(&d, 0) != 4 { ok = false; }
  if cbor_child(&d, 0, 0) != 1 { ok = false; }
  if cbor_child(&d, 0, 1) != 2 { ok = false; }
  if cbor_child(&d, 0, 2) != 3 { ok = false; }
  if cbor_child(&d, 0, 3) != 4 { ok = false; }
  if cbor_next_sibling(&d, 1) != 2 { ok = false; }
  if cbor_next_sibling(&d, 2) != 3 { ok = false; }
  if cbor_next_sibling(&d, 3) != 4 { ok = false; }
  if cbor_next_sibling(&d, 4) != -1 { ok = false; }
  if cbor_kind(&d, 1) != cbor_kind_text() { ok = false; }
  if cbor_kind(&d, 3) != cbor_kind_text() { ok = false; }
  if cbor_kind(&d, 4) != cbor_kind_array() { ok = false; }
  if cbor_int_value(&d, 2) != 1 { ok = false; }
  if cbor_int_value(&d, 5) != 2 { ok = false; }
  if cbor_int_value(&d, 6) != 3 { ok = false; }
  if cbor_parent(&d, 4) != 0 { ok = false; }
  if cbor_parent(&d, 5) != 4 { ok = false; }
  if cbor_child_count(&d, 4) != 2 { ok = false; }
  if cbor_child(&d, 4, 0) != 5 { ok = false; }
  if cbor_child(&d, 4, 1) != 6 { ok = false; }
  if cbor_token_start(&d, 1) != 1 { ok = false; }
  if cbor_token_end(&d, 1) != 3 { ok = false; }
  if cbor_token_start(&d, 4) != 6 { ok = false; }
  if cbor_token_end(&d, 4) != 9 { ok = false; }
  if !bytes_equal(cbor_token_bytes(&d, 1), hb("6161")) { ok = false; }
  if !bytes_equal(cbor_token_bytes(&d, 3), hb("6162")) { ok = false; }
  if !bytes_equal(cbor_token_bytes(&d, 4), hb("820203")) { ok = false; }
  if !bytes_equal(cbor_reserialize(&d), hb("a26161016162820203")) { ok = false; }
  return assert(ok, "hand-written nested map/array decode reconstructs exact bytes");
}

// Decode a byte string of length `n` and a text string of length `n` and
// verify payload length, payload bytes and reserialize.
fn string_boundary(n: Int) -> Bool {
  let payload = fill_bytes(n, 170);
  let enc = cbor_encode_bytes(&payload);
  let r = cbor_decode(enc);
  if !r.is_ok {
    return false;
  }
  let d: CborDoc = r.value;
  if cbor_bytes_len(&d, 0) != n {
    return false;
  }
  if !bytes_equal(cbor_bytes(&d, 0), fill_bytes(n, 170)) {
    return false;
  }
  if !bytes_equal(cbor_reserialize(&d), cbor_encode_bytes(&payload)) {
    return false;
  }
  let tenc = cbor_encode_text_bytes(&payload);
  let tr = cbor_decode(tenc);
  if !tr.is_ok {
    return false;
  }
  let td: CborDoc = tr.value;
  if cbor_text_len(&td, 0) != n {
    return false;
  }
  if !bytes_equal(cbor_text_bytes(&td, 0), fill_bytes(n, 170)) {
    return false;
  }
  if !bytes_equal(cbor_reserialize(&td), cbor_encode_text_bytes(&payload)) {
    return false;
  }
  return true;
}

fn t20() -> TestResult {
  var ok = string_boundary(0);
  if !string_boundary(1) { ok = false; }
  if !string_boundary(23) { ok = false; }
  if !string_boundary(24) { ok = false; }
  if !string_boundary(255) { ok = false; }
  if !string_boundary(256) { ok = false; }
  if !string_boundary(65535) { ok = false; }
  if !string_boundary(65536) { ok = false; }
  let p23 = fill_bytes(23, 170);
  let e23 = cbor_encode_bytes(&p23);
  if first_byte(e23) != 0x57 { ok = false; }
  let p24 = fill_bytes(24, 170);
  let e24 = cbor_encode_bytes(&p24);
  if first_byte(e24) != 0x58 { ok = false; }
  if byte_at_v(e24, 1) != 0x18 { ok = false; }
  let p255 = fill_bytes(255, 170);
  let e255 = cbor_encode_bytes(&p255);
  if first_byte(e255) != 0x58 { ok = false; }
  if byte_at_v(e255, 1) != 0xFF { ok = false; }
  let p256 = fill_bytes(256, 170);
  let e256 = cbor_encode_bytes(&p256);
  if first_byte(e256) != 0x59 { ok = false; }
  if byte_at_v(e256, 1) != 0x01 { ok = false; }
  if byte_at_v(e256, 2) != 0x00 { ok = false; }
  let p65536 = fill_bytes(65536, 170);
  let e65536 = cbor_encode_bytes(&p65536);
  if first_byte(e65536) != 0x5A { ok = false; }
  if byte_at_v(e65536, 1) != 0x00 { ok = false; }
  if byte_at_v(e65536, 2) != 0x01 { ok = false; }
  if byte_at_v(e65536, 3) != 0x00 { ok = false; }
  if byte_at_v(e65536, 4) != 0x00 { ok = false; }
  let text300 = cbor_encode_text_bytes(&fill_bytes(300, 97));
  if first_byte(text300) != 0x79 { ok = false; }
  if byte_at_v(text300, 1) != 0x01 { ok = false; }
  if byte_at_v(text300, 2) != 0x2C { ok = false; }
  return assert(ok, "string length boundaries 23/24/255/256/65535/65536");
}

fn main() -> Int {
  io.println("=== xiom.cbor conformance tests ===");
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
    io.println("xiom.cbor: all tests passed");
  } else {
    io.println("xiom.cbor: tests failed");
  }
  return failed;
}
