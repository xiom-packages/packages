// XIOM -- xiom.dynamo conformance tests
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Every check is a named assert(cond, "name") call, one fn per check, and
// main returns the failure count (0 = green). All synthetic JSON is built
// in-test. BUG 17 discipline: Str equality goes through
// xiom.string.compare.str_compare (never `==` on Str values read from a
// Vec), Vec element reads are bound to typed locals, and bytes widen with
// `(x as Int) & 0xFF`.

module dynamo_tests
use xiom.io; use xiom.test; use xiom.dynamo;
use xiom.string; use xiom.string.compare;

// --------------------------------------------------
//  Helpers
// --------------------------------------------------

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// Raw bytes of a Str (one byte per index).
fn sb(s: Str) -> Vec[UInt8] {
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
    if ((a[i] as Int) & 0xFF) != ((b[i] as Int) & 0xFF) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// True when r is Ok(text) equal to `want`.
fn str_ok_is(r: Result[Str, Str], want: Str) -> Bool {
  if !r.is_ok {
    return false;
  }
  let v: Str = r.value;
  return streq(v, want);
}

// True when r is Err with exactly the message `want`.
fn str_err_is(r: Result[Str, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  let m: Str = r.error;
  return streq(m, want);
}

// Parse an attribute value; absent item on failure so asserts fail loudly.
fn pv(s: Str) -> DynamoItem {
  let r = dynamo_av_parse_str(s);
  if !r.is_ok {
    return dynamo_item_wrap(dynamo_value_new(), -1);
  }
  let it: DynamoItem = r.value;
  return it;
}

// Parse an item; absent item on failure.
fn pi(s: Str) -> DynamoItem {
  let r = dynamo_item_parse_str(s);
  if !r.is_ok {
    return dynamo_item_wrap(dynamo_value_new(), -1);
  }
  let it: DynamoItem = r.value;
  return it;
}

// --------------------------------------------------
//  Checks 1-11: codec, accessors, validation
// --------------------------------------------------

fn t1() -> TestResult {
  var ok = streq(dynamo_base64_encode(&sb("")), "");
  let b1 = sb("f");
  if !streq(dynamo_base64_encode(&b1), "Zg==") { ok = false; }
  let b2 = sb("fo");
  if !streq(dynamo_base64_encode(&b2), "Zm8=") { ok = false; }
  let b3 = sb("foo");
  if !streq(dynamo_base64_encode(&b3), "Zm9v") { ok = false; }
  let b4 = sb("foob");
  if !streq(dynamo_base64_encode(&b4), "Zm9vYg==") { ok = false; }
  let b5 = sb("fooba");
  if !streq(dynamo_base64_encode(&b5), "Zm9vYmE=") { ok = false; }
  let b6 = sb("foobar");
  if !streq(dynamo_base64_encode(&b6), "Zm9vYmFy") { ok = false; }
  var raw = Vec[UInt8].new();
  raw.push(0);
  raw.push(255);
  raw.push(128);
  raw.push(1);
  raw.push(254);
  let enc = dynamo_base64_encode(&raw);
  if !streq(enc, "AP+AAf4=") { ok = false; }
  let dec = dynamo_base64_decode(enc);
  if !dec.is_ok { ok = false; }
  if dec.is_ok {
    let dv: Vec[UInt8] = dec.value;
    if !bytes_equal(dv, raw) { ok = false; }
  }
  let unp = dynamo_base64_decode("Zg");
  if !unp.is_ok { ok = false; }
  if unp.is_ok {
    let uv: Vec[UInt8] = unp.value;
    if uv.len() != 1 { ok = false; }
  }
  return assert(ok, "base64: canonical encode, round-trip, unpadded input");
}

fn t2() -> TestResult {
  var ok = true;
  let e1 = dynamo_base64_decode("A!");
  if e1.is_ok { ok = false; }
  if !e1.is_ok {
    let m: Str = e1.error;
    if !streq(m, "dynamo: base64 bad character at offset 1") { ok = false; }
  }
  let e2 = dynamo_base64_decode("A");
  if e2.is_ok { ok = false; }
  if !e2.is_ok {
    let m2: Str = e2.error;
    if !streq(m2, "dynamo: base64 bad length at offset 1") { ok = false; }
  }
  let e3 = dynamo_base64_decode("AB=");
  if e3.is_ok { ok = false; }
  if !e3.is_ok {
    let m3: Str = e3.error;
    if !streq(m3, "dynamo: base64 bad padding at offset 2") { ok = false; }
  }
  let e4 = dynamo_base64_decode("====");
  if e4.is_ok { ok = false; }
  if !e4.is_ok {
    let m4: Str = e4.error;
    if !streq(m4, "dynamo: base64 bad padding at offset 1") { ok = false; }
  }
  if !dynamo_base64_is_valid("Zm9v") { ok = false; }
  if !dynamo_base64_is_valid("Zg") { ok = false; }
  if !dynamo_base64_is_valid("") { ok = false; }
  if dynamo_base64_is_valid("A") { ok = false; }
  return assert(ok, "base64 errors: bad char, bad length, bad padding carry offsets");
}

fn t3() -> TestResult {
  var ok = true;
  var good = Vec[Str].new();
  good.push("0");
  good.push("-0");
  good.push("+12");
  good.push("12.5");
  good.push("1e3");
  good.push("1E-3");
  good.push("-12.34e+5");
  good.push("007");
  good.push("1234567890123456789012345678901234567890");
  var i = 0;
  while i < good.len() {
    let g: Str = good[i];
    if !dynamo_number_is_valid(g) { ok = false; }
    i = i + 1;
  }
  var bad = Vec[Str].new();
  bad.push("");
  bad.push("+");
  bad.push("-");
  bad.push(".5");
  bad.push("1.");
  bad.push("1e");
  bad.push("1e+");
  bad.push("NaN");
  bad.push("Inf");
  bad.push("Infinity");
  bad.push("0x10");
  bad.push("1 2");
  bad.push("1_000");
  bad.push("1..2");
  bad.push("1.2.3");
  bad.push("e3");
  var j = 0;
  while j < bad.len() {
    let b: Str = bad[j];
    if dynamo_number_is_valid(b) { ok = false; }
    j = j + 1;
  }
  if !str_ok_is(dynamo_number_check("1.5"), "") { ok = false; }
  if !str_err_is(dynamo_number_check(""), "dynamo: number is empty") { ok = false; }
  if !str_err_is(dynamo_number_check("+"), "dynamo: number has no digits at offset 1") { ok = false; }
  if !str_err_is(dynamo_number_check("1."), "dynamo: number missing fraction digits at offset 2") { ok = false; }
  if !str_err_is(dynamo_number_check("1e"), "dynamo: number missing exponent digits at offset 2") { ok = false; }
  if !str_err_is(dynamo_number_check("1 2"), "dynamo: number bad character at offset 1") { ok = false; }
  return assert(ok, "number validation: grammar accept/reject with offsets");
}

fn t4() -> TestResult {
  var ok = true;
  let it = pv("{\"N\":\"-12.34e+5\"}");
  if dynamo_item_kind(&it) != dynamo_av_n() { ok = false; }
  if !streq(dynamo_item_number_text(&it), "-12.34e+5") { ok = false; }
  if !streq(dynamo_item_number_int_text(&it), "-12") { ok = false; }
  if !streq(dynamo_item_number_frac_text(&it), "34") { ok = false; }
  if !streq(dynamo_item_number_exp_text(&it), "+5") { ok = false; }
  let it2 = pv("{\"N\":\"7\"}");
  if !streq(dynamo_item_number_int_text(&it2), "7") { ok = false; }
  if !streq(dynamo_item_number_frac_text(&it2), "") { ok = false; }
  if !streq(dynamo_item_number_exp_text(&it2), "") { ok = false; }
  return assert(ok, "number accessors: int/frac/exp text split");
}

fn t5() -> TestResult {
  var ok = true;
  let s = pv("{\"S\":\"a\\\"b\\\\c\"}");
  if dynamo_item_kind(&s) != dynamo_av_s() { ok = false; }
  if !streq(dynamo_item_string(&s), "a\"b\\c") { ok = false; }
  if !streq(dynamo_av_render(&s), "{\"S\":\"a\\\"b\\\\c\"}") { ok = false; }
  let n = pv("{\"N\":\"-1.5e-3\"}");
  if !streq(dynamo_av_render(&n), "{\"N\":\"-1.5e-3\"}") { ok = false; }
  let b = pv("{\"B\":\"AQI=\"}");
  if dynamo_item_kind(&b) != dynamo_av_b() { ok = false; }
  if !streq(dynamo_av_render(&b), "{\"B\":\"AQI=\"}") { ok = false; }
  let dec = dynamo_item_binary(&b);
  if !dec.is_ok { ok = false; }
  if dec.is_ok {
    let dv: Vec[UInt8] = dec.value;
    var want = Vec[UInt8].new();
    want.push(1);
    want.push(2);
    if !bytes_equal(dv, want) { ok = false; }
  }
  let nul = pv("{\"NULL\":true}");
  if dynamo_item_kind(&nul) != dynamo_av_null() { ok = false; }
  if !dynamo_item_is_null(&nul) { ok = false; }
  if !streq(dynamo_av_render(&nul), "{\"NULL\":true}") { ok = false; }
  let bt = pv("{\"BOOL\":true}");
  if !dynamo_item_bool(&bt) { ok = false; }
  if !streq(dynamo_av_render(&bt), "{\"BOOL\":true}") { ok = false; }
  let bf = pv("{\"BOOL\":false}");
  if dynamo_item_bool(&bf) { ok = false; }
  if !streq(dynamo_av_render(&bf), "{\"BOOL\":false}") { ok = false; }
  let uni = pv("{\"S\":\"\\u0041\\u00e9\"}");
  if !streq(dynamo_item_string(&uni), "A\u{00E9}") { ok = false; }
  if !streq(dynamo_av_render(&uni), "{\"S\":\"A\u{00E9}\"}") { ok = false; }
  let emo = pv("{\"S\":\"\\uD83D\\uDE00\"}");
  if !streq(dynamo_item_string(&emo), "\u{1F600}") { ok = false; }
  return assert(ok, "attribute value kinds: S/N/B/NULL/BOOL render and accessors");
}

fn t6() -> TestResult {
  var ok = true;
  let ss = pv("{\"SS\":[\"a\",\"b\"]}");
  if dynamo_item_kind(&ss) != dynamo_av_ss() { ok = false; }
  if dynamo_item_set_len(&ss) != 2 { ok = false; }
  if !streq(dynamo_item_set_text_at(&ss, 0), "a") { ok = false; }
  if !streq(dynamo_item_set_text_at(&ss, 1), "b") { ok = false; }
  if !streq(dynamo_av_render(&ss), "{\"SS\":[\"a\",\"b\"]}") { ok = false; }
  let ns = pv("{\"NS\":[\"1\",\"2.5\"]}");
  if dynamo_item_kind(&ns) != dynamo_av_ns() { ok = false; }
  if !streq(dynamo_item_set_text_at(&ns, 1), "2.5") { ok = false; }
  if !streq(dynamo_av_render(&ns), "{\"NS\":[\"1\",\"2.5\"]}") { ok = false; }
  let bs = pv("{\"BS\":[\"AQI=\"]}");
  if dynamo_item_kind(&bs) != dynamo_av_bs() { ok = false; }
  if !streq(dynamo_item_set_text_at(&bs, 0), "AQI=") { ok = false; }
  if !streq(dynamo_av_render(&bs), "{\"BS\":[\"AQI=\"]}") { ok = false; }
  return assert(ok, "sets: SS/NS/BS parse, member access and canonical render");
}

fn t7() -> TestResult {
  var ok = true;
  let it = pv("{\"M\":{\"k\":{\"L\":[{\"N\":\"1\"},{\"BOOL\":true}]}}}");
  if dynamo_item_kind(&it) != dynamo_av_m() { ok = false; }
  if dynamo_item_map_len(&it) != 1 { ok = false; }
  let inner = dynamo_item_map_get(&it, "k");
  if dynamo_item_kind(&inner) != dynamo_av_l() { ok = false; }
  if dynamo_item_list_len(&inner) != 2 { ok = false; }
  let e0 = dynamo_item_list_get(&inner, 0);
  if !streq(dynamo_item_number_text(&e0), "1") { ok = false; }
  let e1 = dynamo_item_list_get(&inner, 1);
  if !dynamo_item_bool(&e1) { ok = false; }
  let l = pv("{\"L\":[{\"S\":\"x\"},{\"M\":{\"a\":{\"S\":\"y\"}}}]}");
  if dynamo_item_list_len(&l) != 2 { ok = false; }
  let l1 = dynamo_item_list_get(&l, 1);
  let la = dynamo_item_map_get(&l1, "a");
  if !streq(dynamo_item_string(&la), "y") { ok = false; }
  if !streq(dynamo_av_render(&it), "{\"M\":{\"k\":{\"L\":[{\"N\":\"1\"},{\"BOOL\":true}]}}}") { ok = false; }
  return assert(ok, "nested M/L: map lookup by key and list by index");
}

fn t8() -> TestResult {
  var ok = true;
  let r1 = dynamo_av_parse_str("{}");
  if r1.is_ok { ok = false; }
  if !r1.is_ok {
    let m1: Str = r1.error;
    if !streq(m1, "dynamo: attribute value object is empty at offset 1") { ok = false; }
  }
  let r2 = dynamo_av_parse_str("{\"X\":\"a\"}");
  if r2.is_ok { ok = false; }
  if !r2.is_ok {
    let m2: Str = r2.error;
    if !streq(m2, "dynamo: unknown attribute value type: X at offset 1") { ok = false; }
  }
  let r3 = dynamo_av_parse_str("{\"S\":\"a\"");
  if r3.is_ok { ok = false; }
  if !r3.is_ok {
    let m3: Str = r3.error;
    if !streq(m3, "dynamo: attribute value must close with '}' at offset 8") { ok = false; }
  }
  let r4 = dynamo_av_parse_str("{\"NULL\":false}");
  if r4.is_ok { ok = false; }
  if !r4.is_ok {
    let m4: Str = r4.error;
    if !streq(m4, "dynamo: NULL must be true at offset 8") { ok = false; }
  }
  let r5 = dynamo_av_parse_str("{\"S\":\"a\",\"N\":\"1\"}");
  if r5.is_ok { ok = false; }
  if !r5.is_ok {
    let m5: Str = r5.error;
    if !streq(m5, "dynamo: attribute value must close with '}' at offset 8") { ok = false; }
  }
  let r6 = dynamo_av_parse_str("{\"S\":");
  if r6.is_ok { ok = false; }
  if !r6.is_ok {
    let m6: Str = r6.error;
    if !streq(m6, "dynamo: string value truncated at offset 5") { ok = false; }
  }
  let r7 = dynamo_av_parse_str("{\"S\":\"\\u0000\"}");
  if r7.is_ok { ok = false; }
  if !r7.is_ok {
    let m7: Str = r7.error;
    if !streq(m7, "dynamo: string value unicode escape is NUL at offset 6") { ok = false; }
  }
  let r8 = dynamo_av_parse_str("{\"S\":\"\\uD800x\"}");
  if r8.is_ok { ok = false; }
  if !r8.is_ok {
    let m8: Str = r8.error;
    if !streq(m8, "dynamo: string value truncated surrogate pair at offset 12") { ok = false; }
  }
  let r8b = dynamo_av_parse_str("{\"S\":\"\\uDC00\"}");
  if r8b.is_ok { ok = false; }
  if !r8b.is_ok {
    let m8b: Str = r8b.error;
    if !streq(m8b, "dynamo: string value lone surrogate at offset 6") { ok = false; }
  }
  let r9 = dynamo_av_parse_str("{\"S\":\"\\q\"}");
  if r9.is_ok { ok = false; }
  if !r9.is_ok {
    let m9: Str = r9.error;
    if !streq(m9, "dynamo: string value bad escape at offset 6") { ok = false; }
  }
  let r10 = dynamo_av_parse_str("{\"SS\":[]}");
  if r10.is_ok { ok = false; }
  if !r10.is_ok {
    let m10: Str = r10.error;
    if !streq(m10, "dynamo: empty set at offset 6") { ok = false; }
  }
  let r11 = dynamo_av_parse_str("{\"SS\":[\"a\",\"a\"]}");
  if r11.is_ok { ok = false; }
  if !r11.is_ok {
    let m11: Str = r11.error;
    if !streq(m11, "dynamo: duplicate set member at offset 11") { ok = false; }
  }
  let r12 = dynamo_av_parse_str("{\"M\":{\"a\":{\"S\":\"1\"},\"a\":{\"S\":\"2\"}}}");
  if r12.is_ok { ok = false; }
  if !r12.is_ok {
    let m12: Str = r12.error;
    if !streq(m12, "dynamo: duplicate attribute name at offset 20") { ok = false; }
  }
  let r13 = dynamo_av_parse_str("{\"M\":{\"\":{\"S\":\"1\"}}}");
  if r13.is_ok { ok = false; }
  if !r13.is_ok {
    let m13: Str = r13.error;
    if !streq(m13, "dynamo: empty attribute name at offset 6") { ok = false; }
  }
  var raw = Vec[UInt8].new();
  raw.push(123);
  raw.push(34);
  raw.push(83);
  raw.push(34);
  raw.push(58);
  raw.push(34);
  raw.push(1);
  raw.push(34);
  raw.push(125);
  let r14 = dynamo_av_parse(&raw, 0, raw.len());
  if r14.is_ok { ok = false; }
  return assert(ok, "malformed attribute values: offsets for object/type/escape/duplicate errors");
}

fn t9() -> TestResult {
  var ok = true;
  let it = pi("{\"id\":{\"S\":\"a\"},\"n\":{\"N\":\"-12.34e5\"},\"flag\":{\"BOOL\":true},\"nil\":{\"NULL\":true},\"bin\":{\"B\":\"AQI=\"},\"tags\":{\"SS\":[\"x\",\"y\"]}}");
  if dynamo_item_kind(&it) != dynamo_av_m() { ok = false; }
  if !streq(dynamo_item_kind_name(&it), "M") { ok = false; }
  if dynamo_item_map_len(&it) != 6 { ok = false; }
  let idv = dynamo_item_map_get(&it, "id");
  if !streq(dynamo_item_string(&idv), "a") { ok = false; }
  if !streq(dynamo_item_kind_name(&idv), "S") { ok = false; }
  let nv = dynamo_item_map_get(&it, "n");
  if !streq(dynamo_item_number_text(&nv), "-12.34e5") { ok = false; }
  if !streq(dynamo_item_number_int_text(&nv), "-12") { ok = false; }
  let fv = dynamo_item_map_get(&it, "flag");
  if !dynamo_item_bool(&fv) { ok = false; }
  let nilv = dynamo_item_map_get(&it, "nil");
  if !dynamo_item_is_null(&nilv) { ok = false; }
  let bv = dynamo_item_map_get(&it, "bin");
  let bdec = dynamo_item_binary(&bv);
  if !bdec.is_ok { ok = false; }
  let tv = dynamo_item_map_get(&it, "tags");
  if dynamo_item_set_len(&tv) != 2 { ok = false; }
  if !streq(dynamo_item_set_text_at(&tv, 1), "y") { ok = false; }
  let miss = dynamo_item_map_get(&it, "nope");
  if dynamo_item_present(&miss) { ok = false; }
  if dynamo_item_kind(&miss) != -1 { ok = false; }
  if !streq(dynamo_item_kind_name(&miss), "UNKNOWN") { ok = false; }
  let k0 = dynamo_item_map_key_at(&it, 0);
  if !streq(k0, "id") { ok = false; }
  return assert(ok, "item codec: typed accessors over a parsed item");
}

fn t10() -> TestResult {
  var ok = true;
  let src = "{\"id\":{\"S\":\"a\"},\"m\":{\"M\":{\"k\":{\"L\":[{\"N\":\"1\"},{\"NULL\":true}]}}}}";
  let it = pi(src);
  let r1 = dynamo_item_render(&it);
  if !streq(r1, src) { ok = false; }
  let it2 = pi(r1);
  let r2 = dynamo_item_render(&it2);
  if !streq(r2, r1) { ok = false; }
  let av1 = pv("{\"M\":{\"a\":{\"S\":\"x\"}}}");
  let ar = dynamo_av_render(&av1);
  if !streq(ar, "{\"M\":{\"a\":{\"S\":\"x\"}}}") { ok = false; }
  var tape = dynamo_value_new();
  let s1 = dynamo_value_push_string(&mut tape, "x");
  let s2 = dynamo_value_push_string(&mut tape, "y");
  var keys = Vec[Str].new();
  keys.push("a");
  keys.push("b");
  var nodes = Vec[Int].new();
  nodes.push(s1);
  nodes.push(s2);
  let mn = dynamo_value_push_map(&mut tape, &keys, &nodes);
  if !mn.is_ok { ok = false; }
  if mn.is_ok {
    let rv = dynamo_value_render(&tape, mn.value);
    if !streq(rv, "{\"M\":{\"a\":{\"S\":\"x\"},\"b\":{\"S\":\"y\"}}}") { ok = false; }
  }
  var dst = dynamo_value_new();
  let off = dynamo_value_merge(&mut dst, &tape);
  if off != 0 { ok = false; }
  if !streq(dynamo_value_render(&dst, dynamo_value_count(&dst) - 1), "{\"M\":{\"a\":{\"S\":\"x\"},\"b\":{\"S\":\"y\"}}}") { ok = false; }
  return assert(ok, "canonical render: item/AV round-trip and builder tape");
}

fn t11() -> TestResult {
  var ok = true;
  if dynamo_item_max_bytes() != 409600 { ok = false; }
  if dynamo_max_json_bytes() != 1048576 { ok = false; }
  if !dynamo_table_name_is_valid("abc") { ok = false; }
  if !dynamo_table_name_is_valid("my_table-1.2") { ok = false; }
  if dynamo_table_name_is_valid("ab") { ok = false; }
  if dynamo_table_name_is_valid("ab c") { ok = false; }
  var long = "";
  var i = 0;
  while i < 256 {
    long = long + "a";
    i = i + 1;
  }
  if dynamo_table_name_is_valid(long) { ok = false; }
  if !str_err_is(dynamo_table_name_check("ab"), "dynamo: table name length must be 3..255") { ok = false; }
  if !str_err_is(dynamo_table_name_check("ab c"), "dynamo: table name invalid character at offset 2") { ok = false; }
  if !dynamo_key_name_is_valid("uid") { ok = false; }
  if dynamo_key_name_is_valid("id") { ok = false; }
  if !str_err_is(dynamo_key_name_check("id"), "dynamo: key name length must be 3..255") { ok = false; }
  let small = sb("{\"id\":{\"S\":\"a\"}}");
  let chk = dynamo_item_check(&small, 0, small.len());
  if !chk.is_ok { ok = false; }
  if chk.is_ok {
    if chk.value != 16 { ok = false; }
  }
  var big = Vec[UInt8].new();
  var j = 0;
  while j < 409601 {
    big.push(32);
    j = j + 1;
  }
  let chk2 = dynamo_item_check(&big, 0, big.len());
  if chk2.is_ok { ok = false; }
  if !chk2.is_ok {
    let m: Str = chk2.error;
    if !streq(m, "dynamo: item exceeds 400KB (409600 bytes) at offset 409600") { ok = false; }
  }
  return assert(ok, "validation: name charset and 400KB item cap with offsets");
}

// True when r is Err with exactly the message `want` (Int payload).
fn int_err_is(r: Result[Int, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  let m: Str = r.error;
  return streq(m, want);
}

// --------------------------------------------------
//  Checks 12-21: requests, responses, builders
// --------------------------------------------------

fn t12() -> TestResult {
  var ok = true;
  let key = pi("{\"uid\":{\"S\":\"a\"}}");
  var r = dynamo_get_item_new("my_table", key);
  r.consistent_read = true;
  r.projection_expression = "uid, n";
  r.return_consumed_capacity = "TOTAL";
  let out = dynamo_get_item_render(&r);
  let want = "{\"TableName\":\"my_table\",\"Key\":{\"uid\":{\"S\":\"a\"}},\"ConsistentRead\":true,\"ProjectionExpression\":\"uid, n\",\"ReturnConsumedCapacity\":\"TOTAL\"}";
  if !str_ok_is(out, want) { ok = false; }
  let r2 = dynamo_get_item_new("my_table", key);
  let out2 = dynamo_get_item_render(&r2);
  let want2 = "{\"TableName\":\"my_table\",\"Key\":{\"uid\":{\"S\":\"a\"}}}";
  if !str_ok_is(out2, want2) { ok = false; }
  let r3 = dynamo_get_item_new("ab", key);
  let out3 = dynamo_get_item_render(&r3);
  if !str_err_is(out3, "dynamo: table name length must be 3..255") { ok = false; }
  let item = pi("{\"uid\":{\"S\":\"x\"},\"n\":{\"N\":\"1\"}}");
  var p = dynamo_put_item_new("my_table", item);
  p.condition_expression = "attribute_not_exists(uid)";
  p.return_values = "ALL_OLD";
  let pout = dynamo_put_item_render(&p);
  let pwant = "{\"TableName\":\"my_table\",\"Item\":{\"uid\":{\"S\":\"x\"},\"n\":{\"N\":\"1\"}},\"ConditionExpression\":\"attribute_not_exists(uid)\",\"ReturnValues\":\"ALL_OLD\"}";
  if !str_ok_is(pout, pwant) { ok = false; }
  return assert(ok, "GetItem/PutItem: canonical request renders and table validation");
}

fn t13() -> TestResult {
  var ok = true;
  let key = pi("{\"uid\":{\"S\":\"a\"}}");
  var u = dynamo_update_item_new("my_table", key);
  u.update_expression = "SET #v = :v";
  u.return_values = "UPDATED_NEW";
  let out = dynamo_update_item_render(&u);
  let want = "{\"TableName\":\"my_table\",\"Key\":{\"uid\":{\"S\":\"a\"}},\"UpdateExpression\":\"SET #v = :v\",\"ReturnValues\":\"UPDATED_NEW\"}";
  if !str_ok_is(out, want) { ok = false; }
  let u0 = dynamo_update_item_new("my_table", key);
  let out0 = dynamo_update_item_render(&u0);
  if !str_err_is(out0, "dynamo: UpdateItem needs an UpdateExpression or AttributeUpdates") { ok = false; }
  var u2 = dynamo_update_item_new("my_table", key);
  let val = pv("{\"N\":\"5\"}");
  var ups: DynamoAttributeUpdates = u2.attribute_updates;
  let add = dynamo_attribute_updates_add(&mut ups, "score", "PUT", &val);
  if !add.is_ok { ok = false; }
  let add_dup = dynamo_attribute_updates_add(&mut ups, "score", "PUT", &val);
  if add_dup.is_ok { ok = false; }
  if !add_dup.is_ok {
    let m: Str = add_dup.error;
    if !streq(m, "dynamo: duplicate attribute update: score") { ok = false; }
  }
  let add_bad = dynamo_attribute_updates_add(&mut ups, "other", "NOPE", &val);
  if add_bad.is_ok { ok = false; }
  if !add_bad.is_ok {
    let m2: Str = add_bad.error;
    if !streq(m2, "dynamo: attribute update action must be PUT, DELETE or ADD") { ok = false; }
  }
  u2.attribute_updates = ups;
  u2.has_attribute_updates = true;
  let out2 = dynamo_update_item_render(&u2);
  let want2 = "{\"TableName\":\"my_table\",\"Key\":{\"uid\":{\"S\":\"a\"}},\"AttributeUpdates\":{\"score\":{\"Value\":{\"N\":\"5\"},\"Action\":\"PUT\"}}}";
  if !str_ok_is(out2, want2) { ok = false; }
  return assert(ok, "UpdateItem: UpdateExpression and AttributeUpdates branches");
}

fn t14() -> TestResult {
  var ok = true;
  let key = pi("{\"uid\":{\"S\":\"a\"}}");
  var d = dynamo_delete_item_new("my_table", key);
  d.condition_expression = "attribute_exists(uid)";
  d.return_values = "ALL_OLD";
  let dout = dynamo_delete_item_render(&d);
  let dwant = "{\"TableName\":\"my_table\",\"Key\":{\"uid\":{\"S\":\"a\"}},\"ConditionExpression\":\"attribute_exists(uid)\",\"ReturnValues\":\"ALL_OLD\"}";
  if !str_ok_is(dout, dwant) { ok = false; }
  var q = dynamo_query_new("my_table");
  q.index_name = "gsi_1";
  q.key_condition_expression = "#k = :v";
  var nms: DynamoNameMap = q.expression_attribute_names;
  let na = dynamo_name_map_add(&mut nms, "#k", "uid");
  if !na.is_ok { ok = false; }
  q.expression_attribute_names = nms;
  let vitem = pv("{\"S\":\"a\"}");
  var vms: DynamoValueMap = q.expression_attribute_values;
  let va = dynamo_value_map_add(&mut vms, ":v", &vitem);
  if !va.is_ok { ok = false; }
  q.expression_attribute_values = vms;
  q.limit = 10;
  q.exclusive_start_key = pi("{\"uid\":{\"S\":\"b\"}}");
  q.has_exclusive_start_key = true;
  q.scan_index_forward = false;
  q.scan_index_forward_set = true;
  q.select = "ALL_ATTRIBUTES";
  let qout = dynamo_query_render(&q);
  let qwant = "{\"TableName\":\"my_table\",\"IndexName\":\"gsi_1\",\"KeyConditionExpression\":\"#k = :v\",\"ExpressionAttributeNames\":{\"#k\":\"uid\"},\"ExpressionAttributeValues\":{\":v\":{\"S\":\"a\"}},\"Limit\":10,\"ExclusiveStartKey\":{\"uid\":{\"S\":\"b\"}},\"ScanIndexForward\":false,\"Select\":\"ALL_ATTRIBUTES\"}";
  if !str_ok_is(qout, qwant) { ok = false; }
  return assert(ok, "DeleteItem and Query: full shape renders");
}

fn t15() -> TestResult {
  var ok = true;
  var s = dynamo_scan_new("my_table");
  s.filter_expression = "contains(#n, :p)";
  var nms: DynamoNameMap = s.expression_attribute_names;
  let na = dynamo_name_map_add(&mut nms, "#n", "name");
  if !na.is_ok { ok = false; }
  s.expression_attribute_names = nms;
  let vitem = pv("{\"S\":\"x\"}");
  var vms: DynamoValueMap = s.expression_attribute_values;
  let va = dynamo_value_map_add(&mut vms, ":p", &vitem);
  if !va.is_ok { ok = false; }
  s.expression_attribute_values = vms;
  s.limit = 3;
  s.select = "COUNT";
  s.consistent_read = true;
  let sout = dynamo_scan_render(&s);
  let swant = "{\"TableName\":\"my_table\",\"FilterExpression\":\"contains(#n, :p)\",\"ExpressionAttributeNames\":{\"#n\":\"name\"},\"ExpressionAttributeValues\":{\":p\":{\"S\":\"x\"}},\"Limit\":3,\"Select\":\"COUNT\",\"ConsistentRead\":true}";
  if !str_ok_is(sout, swant) { ok = false; }
  var bg = dynamo_batch_get_new();
  let at = dynamo_batch_get_add_table(&mut bg, "my_table", true, "uid");
  if !at.is_ok { ok = false; }
  let k1 = pi("{\"uid\":{\"S\":\"a\"}}");
  let k2 = pi("{\"uid\":{\"S\":\"b\"}}");
  let a1 = dynamo_batch_get_add_key(&mut bg, &k1);
  if !a1.is_ok { ok = false; }
  let a2 = dynamo_batch_get_add_key(&mut bg, &k2);
  if !a2.is_ok { ok = false; }
  if dynamo_batch_get_table_count(&bg) != 1 { ok = false; }
  let bout = dynamo_batch_get_render(&bg);
  let bwant = "{\"RequestItems\":{\"my_table\":{\"Keys\":[{\"uid\":{\"S\":\"a\"}},{\"uid\":{\"S\":\"b\"}}],\"ConsistentRead\":true,\"ProjectionExpression\":\"uid\"}}}";
  if !str_ok_is(bout, bwant) { ok = false; }
  let empty = dynamo_batch_get_new();
  let eout = dynamo_batch_get_render(&empty);
  if !str_err_is(eout, "dynamo: batch request has no tables") { ok = false; }
  return assert(ok, "Scan and BatchGet: expression maps, keys and RequestItems render");
}

fn t16() -> TestResult {
  var ok = true;
  var bw = dynamo_batch_write_new();
  let at = dynamo_batch_write_add_table(&mut bw, "my_table");
  if !at.is_ok { ok = false; }
  let it1 = pi("{\"uid\":{\"S\":\"x\"}}");
  let ap = dynamo_batch_write_add_put(&mut bw, &it1);
  if !ap.is_ok { ok = false; }
  let k1 = pi("{\"uid\":{\"S\":\"y\"}}");
  let ad = dynamo_batch_write_add_delete(&mut bw, &k1);
  if !ad.is_ok { ok = false; }
  let wout = dynamo_batch_write_render(&bw);
  let wwant = "{\"RequestItems\":{\"my_table\":[{\"PutRequest\":{\"Item\":{\"uid\":{\"S\":\"x\"}}}},{\"DeleteRequest\":{\"Key\":{\"uid\":{\"S\":\"y\"}}}}]}}";
  if !str_ok_is(wout, wwant) { ok = false; }
  var tx = dynamo_transact_write_new();
  let p1 = dynamo_transact_add_put(&mut tx, "my_table", &it1, "attribute_not_exists(uid)");
  if !p1.is_ok { ok = false; }
  let p2 = dynamo_transact_add_update(&mut tx, "my_table", &k1, "SET #v = :v");
  if !p2.is_ok { ok = false; }
  let p3 = dynamo_transact_add_delete(&mut tx, "my_table", &k1, "");
  if !p3.is_ok { ok = false; }
  let p4 = dynamo_transact_add_condition_check(&mut tx, "my_table", &k1, "attribute_exists(uid)");
  if !p4.is_ok { ok = false; }
  if dynamo_transact_count(&tx) != 4 { ok = false; }
  let tout = dynamo_transact_write_render(&tx);
  let twant = "{\"TransactItems\":[{\"Put\":{\"TableName\":\"my_table\",\"Item\":{\"uid\":{\"S\":\"x\"}},\"ConditionExpression\":\"attribute_not_exists(uid)\"}},{\"Update\":{\"TableName\":\"my_table\",\"Key\":{\"uid\":{\"S\":\"y\"}},\"UpdateExpression\":\"SET #v = :v\"}},{\"Delete\":{\"TableName\":\"my_table\",\"Key\":{\"uid\":{\"S\":\"y\"}}}},{\"ConditionCheck\":{\"TableName\":\"my_table\",\"Key\":{\"uid\":{\"S\":\"y\"}},\"ConditionExpression\":\"attribute_exists(uid)\"}}]}";
  if !str_ok_is(tout, twant) { ok = false; }
  let none = dynamo_transact_write_new();
  let nout = dynamo_transact_write_render(&none);
  if !str_err_is(nout, "dynamo: transact request has no items") { ok = false; }
  return assert(ok, "BatchWrite and TransactWrite: RequestItems and TransactItems renders");
}

fn t17() -> TestResult {
  var ok = true;
  let resp = sb("{\"Item\":{\"uid\":{\"S\":\"a\"},\"n\":{\"N\":\"1.5\"}},\"ConsumedCapacity\":{\"TableName\":\"my_table\",\"CapacityUnits\":1.5}}");
  let ir = dynamo_response_item(&resp);
  if !ir.is_ok { ok = false; }
  if ir.is_ok {
    let it: DynamoItem = ir.value;
    let uv = dynamo_item_map_get(&it, "uid");
    if !streq(dynamo_item_string(&uv), "a") { ok = false; }
    if dynamo_item_map_len(&it) != 2 { ok = false; }
  }
  let resp2 = sb("{\"Items\":[{\"uid\":{\"S\":\"a\"}},{\"uid\":{\"S\":\"b\"}}],\"Count\":2,\"ScannedCount\":5,\"LastEvaluatedKey\":{\"uid\":{\"S\":\"b\"}}}");
  let itemsr = dynamo_response_items(&resp2);
  if !itemsr.is_ok { ok = false; }
  if itemsr.is_ok {
    let items: DynamoItems = itemsr.value;
    if dynamo_items_count(&items) != 2 { ok = false; }
    let it1 = dynamo_items_get(&items, 1);
    let uv1 = dynamo_item_map_get(&it1, "uid");
    if !streq(dynamo_item_string(&uv1), "b") { ok = false; }
  }
  let counts = dynamo_response_counts(&resp2);
  if !counts.count_present { ok = false; }
  if counts.count != 2 { ok = false; }
  if !counts.scanned_present { ok = false; }
  if counts.scanned_count != 5 { ok = false; }
  let lk = dynamo_response_last_key(&resp2);
  if !lk.present { ok = false; }
  let lki: DynamoItem = lk.item;
  let lku = dynamo_item_map_get(&lki, "uid");
  if !streq(dynamo_item_string(&lku), "b") { ok = false; }
  let lk0 = dynamo_response_last_key(&resp);
  if lk0.present { ok = false; }
  return assert(ok, "responses: Item, Items, Count/ScannedCount and LastEvaluatedKey");
}

fn t18() -> TestResult {
  var ok = true;
  let resp = sb("{\"ConsumedCapacity\":{\"TableName\":\"my_table\",\"CapacityUnits\":1.5,\"ReadCapacityUnits\":0.5,\"WriteCapacityUnits\":1,\"Table\":{\"CapacityUnits\":1.5,\"ReadCapacityUnits\":0.5},\"GlobalSecondaryIndexes\":{\"gsi_1\":{\"CapacityUnits\":0.5,\"ReadCapacityUnits\":0.5}}}}");
  let cap = dynamo_response_capacity(&resp);
  if !cap.present { ok = false; }
  if !streq(cap.table_name, "my_table") { ok = false; }
  if !streq(cap.capacity_units, "1.5") { ok = false; }
  if !streq(cap.read_units, "0.5") { ok = false; }
  if !streq(cap.write_units, "1") { ok = false; }
  if !streq(cap.table_units, "1.5") { ok = false; }
  if !streq(cap.table_read_units, "0.5") { ok = false; }
  if dynamo_capacity_index_count(&cap) != 1 { ok = false; }
  if !streq(dynamo_capacity_index_name_at(&cap, 0), "gsi_1") { ok = false; }
  if !streq(dynamo_capacity_index_units_at(&cap, 0), "0.5") { ok = false; }
  let resp2 = sb("{\"UnprocessedItems\":{\"my_table\":[{\"PutRequest\":{\"Item\":{\"uid\":{\"S\":\"x\"}}}}]}}");
  let u = dynamo_response_unprocessed_items(&resp2);
  if !u.present { ok = false; }
  if u.table_names.len() != 1 { ok = false; }
  if !streq(u.table_names[0], "my_table") { ok = false; }
  if !streq(u.payloads[0], "[{\"PutRequest\":{\"Item\":{\"uid\":{\"S\":\"x\"}}}}]") { ok = false; }
  let resp3 = sb("{\"UnprocessedKeys\":{\"my_table\":{\"Keys\":[{\"uid\":{\"S\":\"a\"}}]}}}");
  let uk = dynamo_response_unprocessed_keys(&resp3);
  if !uk.present { ok = false; }
  if !streq(uk.payloads[0], "{\"Keys\":[{\"uid\":{\"S\":\"a\"}}]}") { ok = false; }
  let resp4 = sb("{\"__type\":\"com.amazonaws.dynamodb.v20120810#ResourceNotFoundException\",\"message\":\"Requested resource not found\"}");
  let e = dynamo_response_error(&resp4);
  if !e.has_error { ok = false; }
  if !streq(e.error_type, "com.amazonaws.dynamodb.v20120810#ResourceNotFoundException") { ok = false; }
  if !streq(e.message, "Requested resource not found") { ok = false; }
  if !dynamo_response_is_error(&resp4) { ok = false; }
  if dynamo_response_is_error(&resp) { ok = false; }
  return assert(ok, "responses: ConsumedCapacity breakdown, Unprocessed*, error envelope");
}

fn t19() -> TestResult {
  var ok = true;
  let r1 = dynamo_response_item(&sb("{\"Item\":"));
  if r1.is_ok { ok = false; }
  let r2 = dynamo_response_item(&sb("{\"Item\":{\"uid\":{\"S\":\"a\""));
  if r2.is_ok { ok = false; }
  let r3 = dynamo_response_items(&sb("{\"Count\":0}"));
  if r3.is_ok { ok = false; }
  if !r3.is_ok {
    let m3: Str = r3.error;
    if !streq(m3, "dynamo: json key not found: Items") { ok = false; }
  }
  let r4 = dynamo_response_span(&sb("[1]"), "Item");
  if r4.is_ok { ok = false; }
  if !r4.is_ok {
    let m4: Str = r4.error;
    if !streq(m4, "dynamo: response is not a JSON object at offset 0") { ok = false; }
  }
  var raw = Vec[UInt8].new();
  raw.push(123);
  raw.push(34);
  raw.push(97);
  raw.push(34);
  raw.push(58);
  raw.push(34);
  raw.push(1);
  raw.push(34);
  raw.push(125);
  let r5 = dynamo_response_span(&raw, "a");
  if r5.is_ok { ok = false; }
  if !r5.is_ok {
    let m5: Str = r5.error;
    if !streq(m5, "dynamo: json control byte at offset 6") { ok = false; }
  }
  let r6 = dynamo_response_span(&raw, "");
  if r6.is_ok { ok = false; }
  if !r6.is_ok {
    let m6: Str = r6.error;
    if !streq(m6, "dynamo: json empty key") { ok = false; }
  }
  let r7 = dynamo_response_item(&sb("{\"Item\":[1]}"));
  if r7.is_ok { ok = false; }
  return assert(ok, "malformed responses: truncation, control bytes, bad shapes");
}

fn t20() -> TestResult {
  var ok = true;
  if !streq(dynamo_version(), "0.1.0") { ok = false; }
  if dynamo_av_s() != 1 { ok = false; }
  if dynamo_av_n() != 2 { ok = false; }
  if dynamo_av_b() != 3 { ok = false; }
  if dynamo_av_ss() != 4 { ok = false; }
  if dynamo_av_ns() != 5 { ok = false; }
  if dynamo_av_bs() != 6 { ok = false; }
  if dynamo_av_m() != 7 { ok = false; }
  if dynamo_av_l() != 8 { ok = false; }
  if dynamo_av_null() != 9 { ok = false; }
  if dynamo_av_bool() != 10 { ok = false; }
  if !streq(dynamo_av_kind_name(dynamo_av_ss()), "SS") { ok = false; }
  if !streq(dynamo_av_kind_name(99), "UNKNOWN") { ok = false; }
  if !dynamo_av_kind_is_set(dynamo_av_ns()) { ok = false; }
  if dynamo_av_kind_is_set(dynamo_av_m()) { ok = false; }
  let absent = dynamo_item_wrap(dynamo_value_new(), -1);
  if dynamo_item_present(&absent) { ok = false; }
  if !streq(dynamo_av_render(&absent), "") { ok = false; }
  var tape = dynamo_value_new();
  let bad_num = dynamo_value_push_number(&mut tape, "");
  if bad_num.is_ok { ok = false; }
  if !int_err_is(bad_num, "dynamo: number is empty") { ok = false; }
  let bad_b64 = dynamo_value_push_binary(&mut tape, "A!");
  if bad_b64.is_ok { ok = false; }
  var good = Vec[Str].new();
  good.push("a");
  let bad_kind = dynamo_value_push_set(&mut tape, dynamo_av_m(), &good);
  if bad_kind.is_ok { ok = false; }
  if !int_err_is(bad_kind, "dynamo: set kind must be SS, NS or BS") { ok = false; }
  var empty = Vec[Str].new();
  let bad_empty = dynamo_value_push_set(&mut tape, dynamo_av_ss(), &empty);
  if bad_empty.is_ok { ok = false; }
  if !int_err_is(bad_empty, "dynamo: empty set") { ok = false; }
  var dup = Vec[Str].new();
  dup.push("a");
  dup.push("a");
  let bad_dup = dynamo_value_push_set(&mut tape, dynamo_av_ss(), &dup);
  if bad_dup.is_ok { ok = false; }
  if !int_err_is(bad_dup, "dynamo: duplicate set member") { ok = false; }
  var bad_nodes = Vec[Int].new();
  bad_nodes.push(99);
  let bad_list = dynamo_value_push_list(&mut tape, &bad_nodes);
  if bad_list.is_ok { ok = false; }
  if !int_err_is(bad_list, "dynamo: list item is not a node index") { ok = false; }
  var k1 = Vec[Str].new();
  k1.push("a");
  var n0 = Vec[Int].new();
  let bad_map = dynamo_value_push_map(&mut tape, &k1, &n0);
  if bad_map.is_ok { ok = false; }
  if !int_err_is(bad_map, "dynamo: map keys/values length mismatch") { ok = false; }
  return assert(ok, "predicates, version and builder error catalog");
}

fn t21() -> TestResult {
  var ok = true;
  var bg = dynamo_batch_get_new();
  let k1 = pi("{\"uid\":{\"S\":\"a\"}}");
  let no_table = dynamo_batch_get_add_key(&mut bg, &k1);
  if no_table.is_ok { ok = false; }
  if !no_table.is_ok {
    let m: Str = no_table.error;
    if !streq(m, "dynamo: batch key needs a table first") { ok = false; }
  }
  var tx = dynamo_transact_write_new();
  let no_expr = dynamo_transact_add_update(&mut tx, "my_table", &k1, "");
  if no_expr.is_ok { ok = false; }
  if !no_expr.is_ok {
    let m2: Str = no_expr.error;
    if !streq(m2, "dynamo: transact update needs an UpdateExpression") { ok = false; }
  }
  let no_cond = dynamo_transact_add_condition_check(&mut tx, "my_table", &k1, "");
  if no_cond.is_ok { ok = false; }
  var nm = dynamo_name_map_new();
  let na1 = dynamo_name_map_add(&mut nm, "#k", "uid");
  if !na1.is_ok { ok = false; }
  let na2 = dynamo_name_map_add(&mut nm, "#k", "other");
  if na2.is_ok { ok = false; }
  if !na2.is_ok {
    let m3: Str = na2.error;
    if !streq(m3, "dynamo: duplicate expression attribute name placeholder: #k") { ok = false; }
  }
  let na3 = dynamo_name_map_add(&mut nm, "", "x");
  if na3.is_ok { ok = false; }
  var vm = dynamo_value_map_new();
  let vi = pv("{\"S\":\"x\"}");
  let va1 = dynamo_value_map_add(&mut vm, ":v", &vi);
  if !va1.is_ok { ok = false; }
  let va2 = dynamo_value_map_add(&mut vm, ":v", &vi);
  if va2.is_ok { ok = false; }
  if !va2.is_ok {
    let m4: Str = va2.error;
    if !streq(m4, "dynamo: duplicate expression attribute value placeholder: :v") { ok = false; }
  }
  if dynamo_value_map_count(&vm) != 1 { ok = false; }
  if dynamo_name_map_count(&nm) != 1 { ok = false; }
  return assert(ok, "maps and transact/batch builder guards reject duplicates and gaps");
}

// --------------------------------------------------
//  Harness
// --------------------------------------------------

fn main() -> Int {
  io.println("=== xiom.dynamo conformance tests ===");
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
    io.println("xiom.dynamo: all tests passed");
  } else {
    io.println("xiom.dynamo: tests failed");
  }
  return failed;
}
