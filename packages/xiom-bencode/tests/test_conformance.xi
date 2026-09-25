// XIOM -- xiom.bencode conformance tests (19 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Covers the documented API: canonical integer/string/list/dict encodings,
// token accessors and parent/child ranges, dictionary lookup and ordering,
// reserialize round-trips, every documented error path (truncated input,
// bad delimiters, bad length digits, integer overflow, negative zero, dict
// key order, duplicate keys, trailing data, nesting depth) and binary-safe
// byte handling (high bytes and UTF-8 payloads).
//
// Harness style mirrors xiom.hello / xiom.msgpack: one fn tN() -> TestResult
// per check, called directly from main; main prints [PASS]/[FAIL] and
// returns the failure count. Str payloads are compared with str_compare
// (BUG 17 discipline: `==` on Str values read from a Vec lowers to a
// pointer comparison).

module bencode_tests
use xiom.io; use xiom.test;
use xiom.string; use xiom.string.compare; use xiom.string.builder;
use xiom.encoding.hex;
use xiom.bencode;

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
  let r = bencode_decode(data);
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
fn root_kind(data: Vec<UInt8>) -> Int {
  let r = bencode_decode(data);
  if !r.is_ok {
    return -1;
  }
  let d: BencodeDoc = r.value;
  return bencode_kind(&d, 0);
}

// Integer value of the root token (0 when decoding fails).
fn root_int(data: Vec<UInt8>) -> Int {
  let r = bencode_decode(data);
  if !r.is_ok {
    return 0;
  }
  let d: BencodeDoc = r.value;
  return bencode_int_value(&d, 0);
}

// encode -> decode -> reserialize round-trip for one integer.
fn int_roundtrip(n: Int) -> Bool {
  let enc = bencode_encode_int(n);
  let r = bencode_decode(enc);
  if !r.is_ok {
    return false;
  }
  let d: BencodeDoc = r.value;
  if bencode_kind(&d, 0) != bencode_kind_int() {
    return false;
  }
  if bencode_int_value(&d, 0) != n {
    return false;
  }
  let back = bencode_reserialize(&d);
  let again = bencode_encode_int(n);
  return bytes_equal(back, again);
}

// `depth` nested lists around i0e, built byte-by-byte (no moves).
fn nested_lists(depth: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < depth {
    out.push(108 as UInt8);
    i = i + 1;
  }
  out.push(105 as UInt8);
  out.push(48 as UInt8);
  out.push(101 as UInt8);
  i = 0;
  while i < depth {
    out.push(101 as UInt8);
    i = i + 1;
  }
  return out;
}

// `depth` nested dicts, each with the single key "a", around i0e.
fn nested_dicts(depth: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < depth {
    out.push(100 as UInt8);
    out.push(49 as UInt8);
    out.push(58 as UInt8);
    out.push(97 as UInt8);
    i = i + 1;
  }
  out.push(105 as UInt8);
  out.push(48 as UInt8);
  out.push(101 as UInt8);
  i = 0;
  while i < depth {
    out.push(101 as UInt8);
    i = i + 1;
  }
  return out;
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  var ok = bytes_equal(bencode_encode_int(0), ab("i0e"));
  if !bytes_equal(bencode_encode_int(1), ab("i1e")) { ok = false; }
  if !bytes_equal(bencode_encode_int(42), ab("i42e")) { ok = false; }
  if !bytes_equal(bencode_encode_int(-1), ab("i-1e")) { ok = false; }
  if !bytes_equal(bencode_encode_int(-42), ab("i-42e")) { ok = false; }
  if !bytes_equal(bencode_encode_int(127), ab("i127e")) { ok = false; }
  if !bytes_equal(bencode_encode_int(9223372036854775807), ab("i9223372036854775807e")) { ok = false; }
  let int_min = 0 - 9223372036854775807 - 1;
  if !bytes_equal(bencode_encode_int(int_min), ab("i-9223372036854775808e")) { ok = false; }
  return assert(ok, "integer encodings match canonical bytes");
}

fn t2() -> TestResult {
  var ok = root_kind(ab("i0e")) == bencode_kind_int();
  if root_int(ab("i0e")) != 0 { ok = false; }
  if root_int(ab("i42e")) != 42 { ok = false; }
  if root_int(ab("i-42e")) != -42 { ok = false; }
  if root_int(ab("i-1e")) != -1 { ok = false; }
  if root_int(ab("i9223372036854775807e")) != 9223372036854775807 { ok = false; }
  let int_min = 0 - 9223372036854775807 - 1;
  if root_int(ab("i-9223372036854775808e")) != int_min { ok = false; }
  return assert(ok, "integer decode across the Int range");
}

fn t3() -> TestResult {
  var ok = err_is(ab("i"), "bencode: truncated input");
  if !err_is(ab("ie"), "bencode: bad integer digits") { ok = false; }
  if !err_is(ab("i-e"), "bencode: bad integer digits") { ok = false; }
  if !err_is(ab("i01e"), "bencode: bad integer digits") { ok = false; }
  if !err_is(ab("i-0e"), "bencode: negative zero in integer") { ok = false; }
  if !err_is(ab("i1x"), "bencode: bad delimiter") { ok = false; }
  if !err_is(ab("i0"), "bencode: truncated input") { ok = false; }
  if !err_is(ab("i-"), "bencode: truncated input") { ok = false; }
  if !err_is(ab("i9223372036854775808e"), "bencode: integer overflow") { ok = false; }
  if !err_is(ab("i-9223372036854775809e"), "bencode: integer overflow") { ok = false; }
  if !err_is(ab("i99999999999999999999999e"), "bencode: integer overflow") { ok = false; }
  return assert(ok, "malformed integers are rejected with catalog messages");
}

fn t4() -> TestResult {
  let spam = ab("spam");
  let empty = Vec[UInt8].new();
  var ok = bytes_equal(bencode_encode_bytes(&spam), ab("4:spam"));
  if !bytes_equal(bencode_encode_bytes(&empty), ab("0:")) { ok = false; }
  if !bytes_equal(bencode_encode_str("spam"), ab("4:spam")) { ok = false; }
  if !bytes_equal(bencode_encode_str(""), ab("0:")) { ok = false; }
  if !bytes_equal(bencode_encode_str("hello world!"), ab("12:hello world!")) { ok = false; }
  return assert(ok, "byte-string encodings");
}

fn t5() -> TestResult {
  let r = bencode_decode(ab("4:spam"));
  if !r.is_ok {
    return assert(false, "byte-string decode and payload access");
  }
  let d: BencodeDoc = r.value;
  var ok = bencode_kind(&d, 0) == bencode_kind_str();
  if bencode_str_len(&d, 0) != 4 { ok = false; }
  if !bytes_equal(bencode_str_bytes(&d, 0), ab("spam")) { ok = false; }
  if bencode_token_start(&d, 0) != 0 { ok = false; }
  if bencode_token_end(&d, 0) != 6 { ok = false; }
  if !bytes_equal(bencode_token_bytes(&d, 0), ab("4:spam")) { ok = false; }
  if !bytes_equal(bencode_reserialize(&d), ab("4:spam")) { ok = false; }
  let r2 = bencode_decode(ab("0:"));
  if !r2.is_ok { ok = false; } else {
    let d2: BencodeDoc = r2.value;
    if bencode_str_len(&d2, 0) != 0 { ok = false; }
    let b2 = bencode_str_bytes(&d2, 0);
    if b2.len() != 0 { ok = false; }
  }
  let r3 = bencode_decode(ab("12:hello world!"));
  if !r3.is_ok { ok = false; } else {
    let d3: BencodeDoc = r3.value;
    if bencode_str_len(&d3, 0) != 12 { ok = false; }
    if !bytes_equal(bencode_str_bytes(&d3, 0), ab("hello world!")) { ok = false; }
  }
  return assert(ok, "byte-string decode and payload access");
}

fn t6() -> TestResult {
  var ok = err_is(ab("5:abc"), "bencode: truncated input");
  if !err_is(ab("12"), "bencode: truncated input") { ok = false; }
  if !err_is(ab("12x:ab"), "bencode: bad delimiter") { ok = false; }
  if !err_is(ab("05:abcde"), "bencode: bad length digits") { ok = false; }
  if !err_is(ab("00:"), "bencode: bad length digits") { ok = false; }
  if !err_is(ab("99999999999999999999:"), "bencode: string length overflow") { ok = false; }
  if !err_is(ab(":x"), "bencode: bad type byte 0x3a") { ok = false; }
  if !err_is(hb("81"), "bencode: bad type byte 0x81") { ok = false; }
  return assert(ok, "malformed byte strings are rejected with catalog messages");
}

fn t7() -> TestResult {
  let r = bencode_decode(ab("li1ei2ee"));
  if !r.is_ok {
    return assert(false, "list decode and child ranges");
  }
  let d: BencodeDoc = r.value;
  var ok = bencode_kind(&d, 0) == bencode_kind_list();
  if bencode_token_count(&d) != 3 { ok = false; }
  if bencode_child_count(&d, 0) != 2 { ok = false; }
  if bencode_first_child(&d, 0) != 1 { ok = false; }
  if bencode_child(&d, 0, 0) != 1 { ok = false; }
  if bencode_child(&d, 0, 1) != 2 { ok = false; }
  if bencode_parent(&d, 1) != 0 { ok = false; }
  if bencode_parent(&d, 2) != 0 { ok = false; }
  if bencode_first_child(&d, 1) != -1 { ok = false; }
  if bencode_child_count(&d, 2) != 0 { ok = false; }
  if bencode_int_value(&d, 1) != 1 { ok = false; }
  if bencode_int_value(&d, 2) != 2 { ok = false; }
  let re = bencode_reserialize(&d);
  if !bytes_equal(re, ab("li1ei2ee")) { ok = false; }
  let r2 = bencode_decode(ab("le"));
  if !r2.is_ok { ok = false; } else {
    let d2: BencodeDoc = r2.value;
    if bencode_kind(&d2, 0) != bencode_kind_list() { ok = false; }
    if bencode_child_count(&d2, 0) != 0 { ok = false; }
    if bencode_first_child(&d2, 0) != -1 { ok = false; }
  }
  let r3 = bencode_decode(ab("lli1eee"));
  if !r3.is_ok { ok = false; } else {
    let d3: BencodeDoc = r3.value;
    if bencode_token_count(&d3) != 3 { ok = false; }
    if bencode_kind(&d3, 1) != bencode_kind_list() { ok = false; }
    if bencode_child_count(&d3, 1) != 1 { ok = false; }
    if bencode_child(&d3, 1, 0) != 2 { ok = false; }
    if bencode_int_value(&d3, 2) != 1 { ok = false; }
    let re3 = bencode_reserialize(&d3);
    if !bytes_equal(re3, ab("lli1eee")) { ok = false; }
  }
  return assert(ok, "list decode and child ranges");
}

fn t8() -> TestResult {
  let empty_parts = Vec[Vec[UInt8]].new();
  var ok = bytes_equal(bencode_encode_list(&empty_parts), ab("le"));
  let a = ab("i1e");
  let b = ab("4:spam");
  var parts = Vec[Vec[UInt8]].new();
  parts.push(a);
  parts.push(b);
  if !bytes_equal(bencode_encode_list(&parts), ab("li1e4:spame")) { ok = false; }
  let inner_part = ab("i0e");
  var inner_parts = Vec[Vec[UInt8]].new();
  inner_parts.push(inner_part);
  let inner = bencode_encode_list(&inner_parts);
  let x = ab("1:x");
  var outer = Vec[Vec[UInt8]].new();
  outer.push(inner);
  outer.push(x);
  let enc = bencode_encode_list(&outer);
  if !bytes_equal(enc, ab("lli0ee1:xe")) { ok = false; }
  let r = bencode_decode(enc);
  if !r.is_ok { ok = false; } else {
    let d: BencodeDoc = r.value;
    if bencode_child_count(&d, 0) != 2 { ok = false; }
    if bencode_child(&d, 0, 0) != 1 { ok = false; }
    if bencode_child(&d, 0, 1) != 3 { ok = false; }
    if bencode_kind(&d, 1) != bencode_kind_list() { ok = false; }
    if bencode_next_sibling(&d, 1) != 3 { ok = false; }
    if bencode_str_len(&d, 3) != 1 { ok = false; }
    let re = bencode_reserialize(&d);
    if !bytes_equal(re, ab("lli0ee1:xe")) { ok = false; }
  }
  return assert(ok, "list encodings and round-trip");
}

fn t9() -> TestResult {
  let r = bencode_decode(ab("d1:ai1e1:bi2ee"));
  if !r.is_ok {
    return assert(false, "dictionary decode, lookup and structure");
  }
  let d: BencodeDoc = r.value;
  var ok = bencode_kind(&d, 0) == bencode_kind_dict();
  if bencode_token_count(&d) != 5 { ok = false; }
  if bencode_child_count(&d, 0) != 4 { ok = false; }
  if bencode_first_child(&d, 0) != 1 { ok = false; }
  if bencode_child(&d, 0, 0) != 1 { ok = false; }
  if bencode_child(&d, 0, 1) != 2 { ok = false; }
  if bencode_child(&d, 0, 2) != 3 { ok = false; }
  if bencode_child(&d, 0, 3) != 4 { ok = false; }
  if bencode_parent(&d, 4) != 0 { ok = false; }
  if bencode_str_len(&d, 1) != 1 { ok = false; }
  if bencode_str_len(&d, 3) != 1 { ok = false; }
  if bencode_int_value(&d, 2) != 1 { ok = false; }
  if bencode_int_value(&d, 4) != 2 { ok = false; }
  let ka = ab("a");
  let kb = ab("b");
  let kc = ab("c");
  let ta = bencode_dict_get(&d, 0, &ka);
  let tb = bencode_dict_get(&d, 0, &kb);
  let tc = bencode_dict_get(&d, 0, &kc);
  if ta != 2 { ok = false; }
  if bencode_int_value(&d, ta) != 1 { ok = false; }
  if tb != 4 { ok = false; }
  if bencode_int_value(&d, tb) != 2 { ok = false; }
  if tc != -1 { ok = false; }
  if bencode_dict_get(&d, 1, &ka) != -1 { ok = false; }
  if bencode_str_len(&d, ta) != -1 { ok = false; }
  let re = bencode_reserialize(&d);
  if !bytes_equal(re, ab("d1:ai1e1:bi2ee")) { ok = false; }
  let r2 = bencode_decode(ab("de"));
  if !r2.is_ok { ok = false; } else {
    let d2: BencodeDoc = r2.value;
    if bencode_kind(&d2, 0) != bencode_kind_dict() { ok = false; }
    if bencode_child_count(&d2, 0) != 0 { ok = false; }
  }
  return assert(ok, "dictionary decode, lookup and structure");
}

fn t10() -> TestResult {
  var ok = err_is(ab("d1:bi2e1:ai1ee"), "bencode: dict key order violation");
  if !err_is(ab("d1:ai1e1:ai2ee"), "bencode: duplicate dict key") { ok = false; }
  if !err_is(ab("di1ei2ee"), "bencode: dict key must be a byte string") { ok = false; }
  if !err_is(ab("dl1:ae"), "bencode: dict key must be a byte string") { ok = false; }
  if !err_is(ab("d"), "bencode: truncated input") { ok = false; }
  if !err_is(ab("d1:a"), "bencode: truncated input") { ok = false; }
  if !err_is(ab("d1:ai1e"), "bencode: truncated input") { ok = false; }
  return assert(ok, "dictionary ordering and duplicate errors");
}

fn t11() -> TestResult {
  let kb = ab("b");
  let ka = ab("a");
  var keys = Vec[Vec[UInt8]].new();
  keys.push(kb);
  keys.push(ka);
  let vb = ab("i2e");
  let va = ab("i1e");
  var values = Vec[Vec[UInt8]].new();
  values.push(vb);
  values.push(va);
  var ok = true;
  let r = bencode_encode_dict(&keys, &values);
  if !r.is_ok {
    ok = false;
  } else {
    let enc: Vec[UInt8] = r.value;
    if !bytes_equal(enc, ab("d1:ai1e1:bi2ee")) { ok = false; }
  }
  let dup1 = ab("a");
  let dup2 = ab("a");
  var dup_keys = Vec[Vec[UInt8]].new();
  dup_keys.push(dup1);
  dup_keys.push(dup2);
  let d1 = ab("i1e");
  let d2 = ab("i2e");
  var dup_vals = Vec[Vec[UInt8]].new();
  dup_vals.push(d1);
  dup_vals.push(d2);
  let dup_r = bencode_encode_dict(&dup_keys, &dup_vals);
  if !enc_err_is(dup_r, "bencode: duplicate dict key") { ok = false; }
  let one_v = ab("i1e");
  var one_vals = Vec[Vec[UInt8]].new();
  one_vals.push(one_v);
  let mismatch_r = bencode_encode_dict(&dup_keys, &one_vals);
  if !enc_err_is(mismatch_r, "bencode: dict keys/values length mismatch") { ok = false; }
  let empty_keys = Vec[Vec[UInt8]].new();
  let empty_vals = Vec[Vec[UInt8]].new();
  let er = bencode_encode_dict(&empty_keys, &empty_vals);
  if !er.is_ok {
    ok = false;
  } else {
    let eenc: Vec[UInt8] = er.value;
    if !bytes_equal(eenc, ab("de")) { ok = false; }
  }
  return assert(ok, "dictionary encoder sorts keys and rejects duplicates");
}

fn t12() -> TestResult {
  var ok = err_is(ab("i1ei2e"), "bencode: trailing data after top-level value");
  if !err_is(ab("le "), "bencode: trailing data after top-level value") { ok = false; }
  if !err_is(ab("0:x"), "bencode: trailing data after top-level value") { ok = false; }
  if !err_is(ab("li1eee"), "bencode: trailing data after top-level value") { ok = false; }
  if !err_is(hb(""), "bencode: truncated input") { ok = false; }
  if !err_is(ab("x"), "bencode: bad type byte 0x78") { ok = false; }
  if !err_is(hb("00"), "bencode: bad type byte 0x00") { ok = false; }
  if !err_is(hb("ff"), "bencode: bad type byte 0xff") { ok = false; }
  return assert(ok, "trailing data and unrecognized type bytes");
}

fn t13() -> TestResult {
  var ok = bencode_max_depth() == 64;
  let deep_ok = bencode_decode(nested_lists(64));
  if !deep_ok.is_ok {
    ok = false;
  } else {
    let d: BencodeDoc = deep_ok.value;
    if bencode_kind(&d, 0) != bencode_kind_list() { ok = false; }
    if bencode_token_count(&d) != 65 { ok = false; }
    if bencode_kind(&d, 64) != bencode_kind_int() { ok = false; }
    let re = bencode_reserialize(&d);
    let want = nested_lists(64);
    if !bytes_equal(re, want) { ok = false; }
  }
  if !err_is(nested_lists(65), "bencode: nesting depth exceeds limit of 64") { ok = false; }
  let deep_dict = bencode_decode(nested_dicts(64));
  if !deep_dict.is_ok {
    ok = false;
  } else {
    let dd: BencodeDoc = deep_dict.value;
    if bencode_token_count(&dd) != 129 { ok = false; }
  }
  if !err_is(nested_dicts(65), "bencode: nesting depth exceeds limit of 64") { ok = false; }
  return assert(ok, "nesting depth cap: 64 accepted, 65 rejected");
}

fn t14() -> TestResult {
  let r = bencode_decode(ab("d1:ali1ei2ee1:bi-3ee"));
  if !r.is_ok {
    return assert(false, "reserialize rebuilds canonical compound bytes");
  }
  let d: BencodeDoc = r.value;
  var ok = bencode_kind(&d, 0) == bencode_kind_dict();
  if bencode_child_count(&d, 0) != 4 { ok = false; }
  let re = bencode_reserialize(&d);
  if !bytes_equal(re, ab("d1:ali1ei2ee1:bi-3ee")) { ok = false; }
  let nt = bencode_token_bytes(&d, 2);
  if !bytes_equal(nt, ab("li1ei2ee")) { ok = false; }
  let r2 = bencode_decode(ab("lli1eei2ee"));
  if !r2.is_ok {
    ok = false;
  } else {
    let d2: BencodeDoc = r2.value;
    let re2 = bencode_reserialize(&d2);
    if !bytes_equal(re2, ab("lli1eei2ee")) { ok = false; }
    if bencode_child_count(&d2, 0) != 2 { ok = false; }
    if bencode_child_count(&d2, 1) != 1 { ok = false; }
    if bencode_int_value(&d2, 3) != 2 { ok = false; }
  }
  return assert(ok, "reserialize rebuilds canonical compound bytes");
}

fn t15() -> TestResult {
  let r = bencode_decode(ab("d1:ai1ee"));
  if !r.is_ok {
    return assert(false, "accessors are bounds-safe and report offsets");
  }
  let d: BencodeDoc = r.value;
  var ok = bencode_token_count(&d) == 3;
  if bencode_root(&d) != 0 { ok = false; }
  if bencode_kind(&d, 0) != bencode_kind_dict() { ok = false; }
  if bencode_kind(&d, 1) != bencode_kind_str() { ok = false; }
  if bencode_kind(&d, 2) != bencode_kind_int() { ok = false; }
  if bencode_kind(&d, -1) != -1 { ok = false; }
  if bencode_kind(&d, 3) != -1 { ok = false; }
  if bencode_parent(&d, 0) != -1 { ok = false; }
  if bencode_parent(&d, 3) != -1 { ok = false; }
  if bencode_first_child(&d, 2) != -1 { ok = false; }
  if bencode_first_child(&d, 3) != -1 { ok = false; }
  if bencode_child_count(&d, 99) != 0 { ok = false; }
  if bencode_child(&d, 0, 2) != -1 { ok = false; }
  if bencode_child(&d, 2, 0) != -1 { ok = false; }
  if bencode_int_value(&d, 1) != 0 { ok = false; }
  if bencode_int_value(&d, 9) != 0 { ok = false; }
  if bencode_str_len(&d, 2) != -1 { ok = false; }
  if bencode_token_start(&d, -1) != -1 { ok = false; }
  if bencode_token_end(&d, 3) != -1 { ok = false; }
  if bencode_token_start(&d, 0) != 0 { ok = false; }
  if bencode_token_end(&d, 0) != 8 { ok = false; }
  if bencode_token_start(&d, 1) != 1 { ok = false; }
  if bencode_token_end(&d, 1) != 4 { ok = false; }
  if bencode_token_start(&d, 2) != 4 { ok = false; }
  if bencode_token_end(&d, 2) != 7 { ok = false; }
  let b1 = bencode_str_bytes(&d, 2);
  if b1.len() != 0 { ok = false; }
  let t1 = bencode_token_bytes(&d, 1);
  if !bytes_equal(t1, ab("1:a")) { ok = false; }
  let t2 = bencode_token_bytes(&d, 2);
  if !bytes_equal(t2, ab("i1e")) { ok = false; }
  let t9 = bencode_token_bytes(&d, 9);
  if t9.len() != 0 { ok = false; }
  return assert(ok, "accessors are bounds-safe and report offsets");
}

fn t16() -> TestResult {
  let s = "héllo";
  let enc = bencode_encode_str(s);
  let expected = concat_bytes(ab("6:"), ab("héllo"));
  var ok = bytes_equal(enc, expected);
  let r = bencode_decode(enc);
  if !r.is_ok {
    ok = false;
  } else {
    let d: BencodeDoc = r.value;
    if bencode_str_len(&d, 0) != 6 { ok = false; }
    let got = bencode_str_bytes(&d, 0);
    if !bytes_equal(got, ab("héllo")) { ok = false; }
    let rebuilt = builder.sb_to_str(&got);
    if str_compare(rebuilt, s) != 0 { ok = false; }
    let re = bencode_reserialize(&d);
    if !bytes_equal(re, expected) { ok = false; }
  }
  return assert(ok, "UTF-8 payload byte length and round-trip");
}

fn t17() -> TestResult {
  var ok = int_roundtrip(0);
  if !int_roundtrip(1) { ok = false; }
  if !int_roundtrip(-1) { ok = false; }
  if !int_roundtrip(10) { ok = false; }
  if !int_roundtrip(-10) { ok = false; }
  if !int_roundtrip(255) { ok = false; }
  if !int_roundtrip(256) { ok = false; }
  if !int_roundtrip(65535) { ok = false; }
  if !int_roundtrip(2147483647) { ok = false; }
  if !int_roundtrip(-2147483648) { ok = false; }
  if !int_roundtrip(4294967296) { ok = false; }
  if !int_roundtrip(9223372036854775807) { ok = false; }
  if !int_roundtrip(0 - 9223372036854775807 - 1) { ok = false; }
  return assert(ok, "encode/decode/reserialize round-trips every int boundary");
}

fn t18() -> TestResult {
  let kz = ab("z");
  let ke = ab("é");
  var keys = Vec[Vec[UInt8]].new();
  keys.push(kz);
  keys.push(ke);
  let vz = ab("i1e");
  let ve = ab("i2e");
  var values = Vec[Vec[UInt8]].new();
  values.push(vz);
  values.push(ve);
  var ok = true;
  let er = bencode_encode_dict(&keys, &values);
  if !er.is_ok {
    ok = false;
  } else {
    let enc: Vec[UInt8] = er.value;
    let expected = concat_bytes(concat_bytes(ab("d1:zi1e2:"), ab("é")), ab("i2ee"));
    if !bytes_equal(enc, expected) { ok = false; }
    let r = bencode_decode(enc);
    if !r.is_ok {
      ok = false;
    } else {
      let d: BencodeDoc = r.value;
      let qz = ab("z");
      let qe = ab("é");
      let tz = bencode_dict_get(&d, 0, &qz);
      let te = bencode_dict_get(&d, 0, &qe);
      if tz != 2 { ok = false; }
      if bencode_int_value(&d, tz) != 1 { ok = false; }
      if te != 4 { ok = false; }
      if bencode_int_value(&d, te) != 2 { ok = false; }
      let re = bencode_reserialize(&d);
      if !bytes_equal(re, expected) { ok = false; }
    }
  }
  if !err_is(ab("d2:éi2e1:zi1ee"), "bencode: dict key order violation") { ok = false; }
  if !err_is(ab("d1:zi1e1:zi2ee"), "bencode: duplicate dict key") { ok = false; }
  return assert(ok, "dictionary keys compare as unsigned bytes");
}

fn t19() -> TestResult {
  var elems = Vec[Vec[UInt8]].new();
  let e0 = ab("i0e");
  let e1 = ab("i-12345e");
  let e2 = ab("5:hello");
  elems.push(e0);
  elems.push(e1);
  elems.push(e2);
  let nested = bencode_encode_list(&elems);
  var keys = Vec[Vec[UInt8]].new();
  let k1 = ab("alpha");
  let k2 = ab("beta");
  keys.push(k1);
  keys.push(k2);
  var values = Vec[Vec[UInt8]].new();
  let v1 = ab("i1e");
  values.push(v1);
  values.push(nested);
  var ok = true;
  let dr = bencode_encode_dict(&keys, &values);
  if !dr.is_ok {
    ok = false;
  } else {
    let dict_enc: Vec[UInt8] = dr.value;
    var top = Vec[Vec[UInt8]].new();
    let spam = ab("4:spam");
    top.push(dict_enc);
    top.push(spam);
    let enc = bencode_encode_list(&top);
    let enc_again = bencode_encode_list(&top);
    let r = bencode_decode(enc);
    if !r.is_ok {
      ok = false;
    } else {
      let d: BencodeDoc = r.value;
      if bencode_kind(&d, 0) != bencode_kind_list() { ok = false; }
      if bencode_child_count(&d, 0) != 2 { ok = false; }
      if bencode_kind(&d, 1) != bencode_kind_dict() { ok = false; }
      if bencode_child_count(&d, 1) != 4 { ok = false; }
      if bencode_kind(&d, 2) != bencode_kind_str() { ok = false; }
      let ka = ab("alpha");
      let kb = ab("beta");
      let ta = bencode_dict_get(&d, 1, &ka);
      let tb = bencode_dict_get(&d, 1, &kb);
      if ta != 3 { ok = false; }
      if bencode_int_value(&d, ta) != 1 { ok = false; }
      if tb != 5 { ok = false; }
      if bencode_kind(&d, tb) != bencode_kind_list() { ok = false; }
      if bencode_child_count(&d, tb) != 3 { ok = false; }
      if bencode_int_value(&d, tb + 1) != 0 { ok = false; }
      if bencode_int_value(&d, tb + 2) != -12345 { ok = false; }
      if bencode_str_len(&d, tb + 3) != 5 { ok = false; }
      let re = bencode_reserialize(&d);
      if !bytes_equal(re, enc_again) { ok = false; }
    }
  }
  return assert(ok, "compound encode/decode/reserialize round-trip");
}

fn main() -> Int {
  io.println("=== xiom.bencode conformance tests ===");
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
  if failed == 0 {
    io.println("xiom.bencode: all tests passed");
  } else {
    io.println("xiom.bencode: tests failed");
  }
  return failed;
}
