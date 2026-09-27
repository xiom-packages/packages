// XIOM -- xiom.ethereum conformance tests (23 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Covers the documented API with synthetic buffers built in-test:
// RLP single-byte/short/long/nested items, canonicality rejections,
// truncation, trailing data, the depth cap, encoders and reserialization;
// legacy transaction field listing (EIP-155 preimage and signed shape);
// ABI uint/int/bool/address/bytesM/bytes32 round-trips and bounds errors;
// dynamic bytes and fixed-length dynamic arrays with malformed offsets;
// function-call data shape; hex rendering and address normalization.
//
// Harness style mirrors xiom.hello / xiom.bencode: one fn tN() -> TestResult
// per check, called directly from main; main prints [PASS]/[FAIL] and
// returns the failure count. Str payloads are compared with str_compare
// (BUG 17 discipline: `==` on Str values read from a Vec lowers to a
// pointer comparison).

module ethereum_tests
use xiom.io; use xiom.test;
use xiom.string; use xiom.string.compare;
use xiom.encoding.hex;
use xiom.ethereum;

// Expected bytes for a hex string ("" on malformed input; the test then
// fails on the byte comparison).
fn hb(hexstr: Str) -> Vec[UInt8] {
  let r = hex.hex_decode(hexstr);
  if !r.is_ok {
    return Vec[UInt8].new();
  }
  let v: Vec[UInt8] = r.value;
  return v;
}

// Bytes of a Str, byte-for-byte (byte_at indexes bytes).
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

// `n` copies of byte value `b` (0..255).
fn rep_byte(b: Int, n: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < n {
    v.push(b as UInt8);
    i = i + 1;
  }
  return v;
}

fn zeros(n: Int) -> Vec[UInt8] {
  return rep_byte(0, n);
}

// `n` properly nested RLP lists wrapped around a single 0x80 byte, built
// from the inside out (short form while the payload is <= 55 bytes, long
// form after that).
fn nest_lists(n: Int) -> Vec[UInt8] {
  var item = Vec[UInt8].new();
  item.push(0x80 as UInt8);
  var i = 0;
  while i < n {
    var head = Vec[UInt8].new();
    if item.len() <= 55 {
      head.push((0xC0 + item.len()) as UInt8);
    } else {
      head.push(0xF8 as UInt8);
      head.push((item.len() & 0xFF) as UInt8);
    }
    let joined = concat_bytes(head, item);
    item = joined;
    i = i + 1;
  }
  return item;
}

// Byte `i` of a byte vector widened to an Int (0..255).
fn bv(v: &Vec[UInt8], i: Int) -> Int {
  let b: UInt8 = v[i];
  return (b as Int) & 0xFF;
}

// Decode `data` and compare the RLP error text with `want`.
fn err_is(data: Vec[UInt8], want: Str) -> Bool {
  let r = rlp_decode(data);
  if r.is_ok {
    return false;
  }
  return str_compare(r.error, want) == 0;
}

// Result[Vec[UInt8], Str] error starts with `prefix`.
fn bprefix(r: Result[Vec[UInt8], Str], prefix: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return string.str_starts_with(r.error, prefix);
}

// Result[Int, Str] error starts with `prefix`.
fn iprefix(r: Result[Int, Str], prefix: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return string.str_starts_with(r.error, prefix);
}

// Result[Str, Str] error starts with `prefix`.
fn sprefix(r: Result[Str, Str], prefix: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return string.str_starts_with(r.error, prefix);
}

fn str_is(s: Str, want: Str) -> Bool {
  return str_compare(s, want) == 0;
}

// Canonical uint<256> word bytes of a non-negative value.
fn word_of(n: Int) -> Vec[UInt8] {
  let r = abi_encode_uint(n, 256);
  if !r.is_ok {
    return Vec[UInt8].new();
  }
  let v: Vec[UInt8] = r.value;
  return v;
}

// Encoded RLP integer, or empty on error.
fn rlp_int(n: Int) -> Vec[UInt8] {
  let r = rlp_encode_int(n);
  if !r.is_ok {
    return Vec[UInt8].new();
  }
  let v: Vec[UInt8] = r.value;
  return v;
}

// A one-item RLP list containing the encoded integer `n`.
fn rlp_int_list(n: Int) -> Vec[UInt8] {
  var parts = Vec[Vec[UInt8]].new();
  let e = rlp_int(n);
  parts.push(e);
  return rlp_encode_list(&parts);
}

// --------------------------------------------------
//  RLP tests
// --------------------------------------------------

fn t1() -> TestResult {
  var ok = err_is(Vec[UInt8].new(), "rlp: truncated input");
  let r0 = rlp_decode(hb("00"));
  if !r0.is_ok {
    ok = false;
  } else {
    let d: RlpDoc = r0.value;
    if rlp_kind(&d, 0) != rlp_kind_bytes() { ok = false; }
    if !rlp_is_bytes(&d, 0) { ok = false; }
    if rlp_is_list(&d, 0) { ok = false; }
    if rlp_payload_len(&d, 0) != 1 { ok = false; }
    if rlp_payload_start(&d, 0) != 0 { ok = false; }
    if rlp_payload_end(&d, 0) != 1 { ok = false; }
    if !bytes_equal(rlp_item_bytes(&d, 0), hb("00")) { ok = false; }
    if !bytes_equal(rlp_token_bytes(&d, 0), hb("00")) { ok = false; }
  }
  let r7 = rlp_decode(hb("7f"));
  if !r7.is_ok {
    ok = false;
  } else {
    let d: RlpDoc = r7.value;
    if rlp_payload_len(&d, 0) != 1 { ok = false; }
    if !bytes_equal(rlp_item_bytes(&d, 0), hb("7f")) { ok = false; }
  }
  if !bytes_equal(rlp_encode_bytes(&hb("00")), hb("00")) { ok = false; }
  if !bytes_equal(rlp_encode_bytes(&hb("7f")), hb("7f")) { ok = false; }
  return assert(ok, "RLP single-byte items round-trip (< 0x80)");
}

fn t2() -> TestResult {
  let r = rlp_decode(hb("80"));
  if !r.is_ok {
    return assert(false, "RLP short strings");
  }
  let d: RlpDoc = r.value;
  var ok = rlp_payload_len(&d, 0) == 0;
  if !bytes_equal(rlp_item_bytes(&d, 0), Vec[UInt8].new()) { ok = false; }
  let rd = rlp_decode(hb("83646f67"));
  if !rd.is_ok {
    ok = false;
  } else {
    let dog: RlpDoc = rd.value;
    if rlp_payload_len(&dog, 0) != 3 { ok = false; }
    if !bytes_equal(rlp_item_bytes(&dog, 0), ab("dog")) { ok = false; }
    if !bytes_equal(rlp_reserialize(&dog), hb("83646f67")) { ok = false; }
  }
  let b55 = rep_byte(97, 55);
  let e55 = rlp_encode_bytes(&b55);
  if bv(&e55, 0) != 0xB7 { ok = false; }
  if e55.len() != 56 { ok = false; }
  let r55 = rlp_decode(e55);
  if !r55.is_ok {
    ok = false;
  } else {
    let d55: RlpDoc = r55.value;
    if rlp_payload_len(&d55, 0) != 55 { ok = false; }
    if !bytes_equal(rlp_item_bytes(&d55, 0), b55) { ok = false; }
  }
  if !bytes_equal(rlp_encode_bytes(&Vec[UInt8].new()), hb("80")) { ok = false; }
  if !bytes_equal(rlp_encode_str("dog"), hb("83646f67")) { ok = false; }
  return assert(ok, "RLP short strings: empty, text, 55-byte boundary");
}

fn t3() -> TestResult {
  let b56 = rep_byte(98, 56);
  let e56 = rlp_encode_bytes(&b56);
  var ok = e56.len() == 58;
  if bv(&e56, 0) != 0xB8 { ok = false; }
  if bv(&e56, 1) != 0x38 { ok = false; }
  let r56 = rlp_decode(e56);
  if !r56.is_ok {
    ok = false;
  } else {
    let d: RlpDoc = r56.value;
    if rlp_payload_len(&d, 0) != 56 { ok = false; }
    if !bytes_equal(rlp_item_bytes(&d, 0), b56) { ok = false; }
    if !bytes_equal(rlp_reserialize(&d), rlp_encode_bytes(&rep_byte(98, 56))) { ok = false; }
  }
  let b300 = rep_byte(99, 300);
  let e300 = rlp_encode_bytes(&b300);
  if bv(&e300, 0) != 0xB9 { ok = false; }
  if bv(&e300, 1) != 0x01 { ok = false; }
  if bv(&e300, 2) != 0x2C { ok = false; }
  if e300.len() != 303 { ok = false; }
  let r300 = rlp_decode(e300);
  if !r300.is_ok {
    ok = false;
  } else {
    let d300: RlpDoc = r300.value;
    if rlp_payload_len(&d300, 0) != 300 { ok = false; }
    if !bytes_equal(rlp_item_bytes(&d300, 0), b300) { ok = false; }
  }
  return assert(ok, "RLP long strings: 56 and 300 bytes");
}

fn t4() -> TestResult {
  var parts = Vec[Vec[UInt8]].new();
  let cat = rlp_encode_str("cat");
  let dog = rlp_encode_str("dog");
  parts.push(cat);
  parts.push(dog);
  let top = rlp_encode_list(&parts);
  var ok = bytes_equal(top, hb("c88363617483646f67"));
  let r = rlp_decode(top);
  if !r.is_ok {
    return assert(false, "RLP short lists and nesting");
  }
  let d: RlpDoc = r.value;
  if rlp_token_count(&d) != 3 { ok = false; }
  if rlp_root(&d) != 0 { ok = false; }
  if rlp_kind(&d, 0) != rlp_kind_list() { ok = false; }
  if rlp_child_count(&d, 0) != 2 { ok = false; }
  if rlp_first_child(&d, 0) != 1 { ok = false; }
  if rlp_child(&d, 0, 0) != 1 { ok = false; }
  if rlp_child(&d, 0, 1) != 2 { ok = false; }
  if rlp_child(&d, 0, 2) != -1 { ok = false; }
  if rlp_parent(&d, 1) != 0 { ok = false; }
  if rlp_parent(&d, 2) != 0 { ok = false; }
  if rlp_parent(&d, 0) != -1 { ok = false; }
  if rlp_next_sibling(&d, 1) != 2 { ok = false; }
  if rlp_next_sibling(&d, 2) != -1 { ok = false; }
  if rlp_token_start(&d, 0) != 0 { ok = false; }
  if rlp_token_end(&d, 0) != 9 { ok = false; }
  if rlp_payload_start(&d, 0) != 1 { ok = false; }
  if rlp_payload_end(&d, 0) != 9 { ok = false; }
  if rlp_payload_len(&d, 0) != 8 { ok = false; }
  if !bytes_equal(rlp_item_bytes(&d, 1), ab("cat")) { ok = false; }
  if !bytes_equal(rlp_item_bytes(&d, 2), ab("dog")) { ok = false; }
  if !bytes_equal(rlp_reserialize(&d), top) { ok = false; }
  // [[], []] -- a two-item list of two empty lists.
  var inner = Vec[Vec[UInt8]].new();
  let e0 = rlp_encode_list(&inner);
  let e1 = rlp_encode_list(&inner);
  inner.push(e0);
  inner.push(e1);
  if !bytes_equal(rlp_encode_list(&inner), hb("c2c0c0")) { ok = false; }
  let r2 = rlp_decode(hb("c2c0c0"));
  if !r2.is_ok {
    ok = false;
  } else {
    let d2: RlpDoc = r2.value;
    if rlp_token_count(&d2) != 3 { ok = false; }
    if rlp_child_count(&d2, 0) != 2 { ok = false; }
    if rlp_child_count(&d2, 1) != 0 { ok = false; }
    if rlp_child_count(&d2, 2) != 0 { ok = false; }
    if rlp_kind(&d2, 1) != rlp_kind_list() { ok = false; }
    if rlp_payload_start(&d2, 1) != 2 { ok = false; }
    if rlp_payload_end(&d2, 1) != 2 { ok = false; }
  }
  return assert(ok, "RLP short lists: children, spans, nesting, reserialize");
}

fn t5() -> TestResult {
  var parts = Vec[Vec[UInt8]].new();
  var i = 0;
  while i < 60 {
    let one = rlp_encode_bytes(&hb("01"));
    parts.push(one);
    i = i + 1;
  }
  let top = rlp_encode_list(&parts);
  var ok = bv(&top, 0) == 0xF8;
  if bv(&top, 1) != 60 { ok = false; }
  if top.len() != 62 { ok = false; }
  let r = rlp_decode(top);
  if !r.is_ok {
    return assert(false, "RLP long lists");
  }
  let d: RlpDoc = r.value;
  if rlp_child_count(&d, 0) != 60 { ok = false; }
  if rlp_token_count(&d) != 61 { ok = false; }
  if rlp_payload_len(&d, 0) != 60 { ok = false; }
  let last = rlp_child(&d, 0, 59);
  if last != 60 { ok = false; }
  if rlp_next_sibling(&d, 59) != 60 { ok = false; }
  if rlp_next_sibling(&d, 60) != -1 { ok = false; }
  if !bytes_equal(rlp_reserialize(&d), top) { ok = false; }
  return assert(ok, "RLP long lists: 60 children and header bytes");
}

fn t6() -> TestResult {
  var ok = err_is(hb("8100"), "rlp: non-canonical single byte");
  if !err_is(hb("817f"), "rlp: non-canonical single byte") { ok = false; }
  if !err_is(concat_bytes(hb("b837"), rep_byte(97, 55)), "rlp: non-canonical long length") { ok = false; }
  if !err_is(concat_bytes(hb("b90038"), rep_byte(97, 56)), "rlp: leading zero in length") { ok = false; }
  if !err_is(hb("b800"), "rlp: leading zero in length") { ok = false; }
  if !err_is(hb("b838"), "rlp: truncated input") { ok = false; }
  if !err_is(concat_bytes(hb("f837"), rep_byte(1, 55)), "rlp: non-canonical long length") { ok = false; }
  if !err_is(hb("f90000"), "rlp: leading zero in length") { ok = false; }
  if !err_is(hb("f800"), "rlp: leading zero in length") { ok = false; }
  return assert(ok, "RLP canonicality rejections");
}

fn t7() -> TestResult {
  var ok = err_is(hb("83"), "rlp: truncated input");
  if !err_is(hb("836361"), "rlp: truncated input") { ok = false; }
  if !err_is(hb("b8"), "rlp: truncated input") { ok = false; }
  if !err_is(hb("c1"), "rlp: truncated input") { ok = false; }
  if !err_is(hb("c183"), "rlp: truncated input") { ok = false; }
  if !err_is(hb("8080"), "rlp: trailing data after top-level item") { ok = false; }
  if !err_is(hb("c0c0"), "rlp: trailing data after top-level item") { ok = false; }
  if !err_is(hb("c283616263"), "rlp: list payload overrun") { ok = false; }
  return assert(ok, "RLP truncation, trailing data and list overrun");
}

fn t8() -> TestResult {
  var ok = true;
  let r = rlp_decode(nest_lists(64));
  if !r.is_ok {
    ok = false;
  } else {
    let d: RlpDoc = r.value;
    if rlp_child_count(&d, 0) != 1 { ok = false; }
  }
  if !err_is(nest_lists(65), "rlp: nesting depth exceeds limit of 64") { ok = false; }
  return assert(ok, "RLP depth cap: 64 accepted, 65 rejected");
}

fn t9() -> TestResult {
  var ok = bytes_equal(rlp_int(0), hb("80"));
  if !bytes_equal(rlp_int(1), hb("01")) { ok = false; }
  if !bytes_equal(rlp_int(127), hb("7f")) { ok = false; }
  if !bytes_equal(rlp_int(128), hb("8180")) { ok = false; }
  if !bytes_equal(rlp_int(255), hb("81ff")) { ok = false; }
  if !bytes_equal(rlp_int(256), hb("820100")) { ok = false; }
  if !bytes_equal(rlp_int(1024), hb("820400")) { ok = false; }
  if !bprefix(rlp_encode_int(-1), "rlp: integer must be non-negative") { ok = false; }
  let empty = Vec[Vec[UInt8]].new();
  if !bytes_equal(rlp_encode_list(&empty), hb("c0")) { ok = false; }
  var one = Vec[Vec[UInt8]].new();
  let empty_bytes = Vec[UInt8].new();
  let e80 = rlp_encode_bytes(&empty_bytes);
  one.push(e80);
  if !bytes_equal(rlp_encode_list(&one), hb("c180")) { ok = false; }
  if !bytes_equal(rlp_encode_str(""), hb("80")) { ok = false; }
  return assert(ok, "RLP encoders: integers, bytes, lists");
}

// --------------------------------------------------
//  Transaction field listing tests
// --------------------------------------------------

fn t10() -> TestResult {
  let addr = hb("52908400098527886e0f7030069857d2e4169ee7");
  var parts = Vec[Vec[UInt8]].new();
  parts.push(rlp_int(9));
  parts.push(rlp_int(20000000000));
  parts.push(rlp_int(21000));
  parts.push(rlp_encode_bytes(&addr));
  parts.push(rlp_int(1000000000000000000));
  parts.push(rlp_encode_bytes(&Vec[UInt8].new()));
  parts.push(rlp_int(1));
  parts.push(rlp_int(0));
  parts.push(rlp_int(0));
  let top = rlp_encode_list(&parts);
  let r = rlp_decode(top);
  if !r.is_ok {
    return assert(false, "EIP-155 transaction preimage field listing");
  }
  let d: RlpDoc = r.value;
  var ok = tx_field_count(&d, 0) == 9;
  if tx_field(&d, 0, 9) != -1 { ok = false; }
  let nonce = tx_nonce(&d, 0);
  let gas_price = tx_gas_price(&d, 0);
  let gas_limit = tx_gas_limit(&d, 0);
  let to = tx_to(&d, 0);
  let value = tx_value(&d, 0);
  let data = tx_data(&d, 0);
  let chain = tx_chain_id(&d, 0);
  if nonce != 1 { ok = false; }
  if gas_price != 2 { ok = false; }
  if gas_limit != 3 { ok = false; }
  if to != 4 { ok = false; }
  if value != 5 { ok = false; }
  if data != 6 { ok = false; }
  if chain != 7 { ok = false; }
  if rlp_payload_len(&d, nonce) != 1 { ok = false; }
  if !bytes_equal(rlp_item_bytes(&d, nonce), hb("09")) { ok = false; }
  if rlp_payload_len(&d, gas_price) != 5 { ok = false; }
  if rlp_payload_len(&d, gas_limit) != 2 { ok = false; }
  if rlp_payload_len(&d, to) != 20 { ok = false; }
  if !bytes_equal(rlp_item_bytes(&d, to), addr) { ok = false; }
  if rlp_payload_len(&d, value) != 8 { ok = false; }
  if rlp_payload_len(&d, data) != 0 { ok = false; }
  if rlp_payload_len(&d, chain) != 1 { ok = false; }
  if !tx_is_unsigned_155(&d, 0) { ok = false; }
  if tx_v(&d, 0) != 7 { ok = false; }
  if tx_r(&d, 0) != 8 { ok = false; }
  if tx_s(&d, 0) != 9 { ok = false; }
  return assert(ok, "EIP-155 transaction preimage field listing");
}

fn t11() -> TestResult {
  var parts = Vec[Vec[UInt8]].new();
  parts.push(rlp_int(9));
  parts.push(rlp_int(20000000000));
  parts.push(rlp_int(21000));
  parts.push(rlp_encode_bytes(&hb("52908400098527886e0f7030069857d2e4169ee7")));
  parts.push(rlp_int(1000000000000000000));
  parts.push(rlp_encode_bytes(&Vec[UInt8].new()));
  parts.push(rlp_int(37));
  parts.push(rlp_encode_bytes(&rep_byte(0xAA, 32)));
  parts.push(rlp_encode_bytes(&rep_byte(0xBB, 32)));
  let top = rlp_encode_list(&parts);
  let r = rlp_decode(top);
  if !r.is_ok {
    return assert(false, "signed legacy transaction field listing");
  }
  let d: RlpDoc = r.value;
  var ok = tx_field_count(&d, 0) == 9;
  if tx_is_unsigned_155(&d, 0) { ok = false; }
  if tx_chain_id(&d, 0) != -1 { ok = false; }
  let v = tx_v(&d, 0);
  let rr = tx_r(&d, 0);
  let ss = tx_s(&d, 0);
  if v != 7 { ok = false; }
  if rr != 8 { ok = false; }
  if ss != 9 { ok = false; }
  if rlp_payload_len(&d, v) != 1 { ok = false; }
  if rlp_payload_len(&d, rr) != 32 { ok = false; }
  if rlp_payload_len(&d, ss) != 32 { ok = false; }
  // A non-list token has no transaction fields.
  if tx_field_count(&d, 1) != 0 { ok = false; }
  if tx_field(&d, 1, 0) != -1 { ok = false; }
  if tx_chain_id(&d, 1) != -1 { ok = false; }
  return assert(ok, "signed legacy transaction field listing and chain-id note");
}

// --------------------------------------------------
//  ABI tests
// --------------------------------------------------

fn t12() -> TestResult {
  var ok = true;
  let m8 = abi_encode_uint(255, 8);
  if !m8.is_ok {
    ok = false;
  } else {
    let w: Vec[UInt8] = m8.value;
    if w.len() != 32 { ok = false; }
    if bv(&w, 31) != 0xFF { ok = false; }
    let dr = abi_decode_uint(&w, 0, 8);
    if !dr.is_ok {
      ok = false;
    } else if dr.value != 255 {
      ok = false;
    }
  }
  let m16 = abi_encode_uint(65535, 16);
  if !m16.is_ok {
    ok = false;
  } else {
    let w16: Vec[UInt8] = m16.value;
    let d16 = abi_decode_uint(&w16, 0, 16);
    if !d16.is_ok {
      ok = false;
    } else if d16.value != 65535 {
      ok = false;
    }
  }
  let m64 = abi_encode_uint(9223372036854775807, 64);
  if !m64.is_ok {
    ok = false;
  } else {
    let w64: Vec[UInt8] = m64.value;
    let d64 = abi_decode_uint(&w64, 0, 64);
    if !d64.is_ok {
      ok = false;
    } else if d64.value != 9223372036854775807 {
      ok = false;
    }
  }
  let m256 = abi_encode_uint(0, 256);
  if !m256.is_ok {
    ok = false;
  } else {
    let w0: Vec[UInt8] = m256.value;
    if !bytes_equal(w0, zeros(32)) { ok = false; }
    let d0 = abi_decode_uint(&w0, 0, 256);
    if !d0.is_ok {
      ok = false;
    } else if d0.value != 0 {
      ok = false;
    }
  }
  if !bprefix(abi_encode_uint(256, 8), "abi: uint value exceeds uint width 8") { ok = false; }
  if !bprefix(abi_encode_uint(65536, 16), "abi: uint value exceeds uint width 16") { ok = false; }
  if !bprefix(abi_encode_uint(-1, 256), "abi: uint value is negative") { ok = false; }
  if !bprefix(abi_encode_uint(1, 0), "abi: invalid uint width 0") { ok = false; }
  if !bprefix(abi_encode_uint(1, 7), "abi: invalid uint width 7") { ok = false; }
  if !bprefix(abi_encode_uint(1, 264), "abi: invalid uint width 264") { ok = false; }
  if !bprefix(abi_encode_uint(1, 4), "abi: invalid uint width 4") { ok = false; }
  return assert(ok, "ABI uint<M> encode/decode round-trips and bounds errors");
}

fn t13() -> TestResult {
  var ok = true;
  let w256 = word_of(256);
  if !iprefix(abi_decode_uint(&w256, 0, 8), "abi: uint word exceeds uint width 8") { ok = false; }
  let big = concat_bytes(hb("01"), zeros(31));
  if !iprefix(abi_decode_uint(&big, 0, 256), "abi: uint word does not fit Int") { ok = false; }
  let neg = concat_bytes(zeros(24), hb("80"));
  let negw = concat_bytes(neg, zeros(7));
  if !iprefix(abi_decode_uint(&negw, 0, 256), "abi: uint word does not fit Int") { ok = false; }
  if !iprefix(abi_decode_uint(&w256, 0, 0), "abi: invalid uint width 0") { ok = false; }
  if !bprefix(abi_read_word(&w256, -1), "abi: word out of bounds at offset -1") { ok = false; }
  if !bprefix(abi_read_word(&w256, 1), "abi: word out of bounds at offset 1") { ok = false; }
  if !bprefix(abi_read_word(&hb("00"), 0), "abi: word out of bounds at offset 0") { ok = false; }
  let short = hb("0011");
  if !bprefix(abi_decode_uint(&short, 0, 256), "abi: word out of bounds at offset 0") { ok = false; }
  let w31 = rep_byte(0, 31);
  if !iprefix(abi_decode_uint_word(&w31, 256), "abi: word must be 32 bytes") { ok = false; }
  return assert(ok, "ABI uint word strictness and byte-offset errors");
}

fn t14() -> TestResult {
  var ok = true;
  let int_min = 0 - 9223372036854775807 - 1;
  let em1 = abi_encode_int(-1, 256);
  if !em1.is_ok {
    ok = false;
  } else {
    let w: Vec[UInt8] = em1.value;
    if !bytes_equal(w, rep_byte(0xFF, 32)) { ok = false; }
    let dr = abi_decode_int(&w, 0, 256);
    if !dr.is_ok {
      ok = false;
    } else if dr.value != -1 {
      ok = false;
    }
  }
  let emin = abi_encode_int(int_min, 256);
  if !emin.is_ok {
    ok = false;
  } else {
    let w2: Vec[UInt8] = emin.value;
    if bv(&w2, 0) != 0xFF { ok = false; }
    if bv(&w2, 23) != 0xFF { ok = false; }
    if bv(&w2, 24) != 0x80 { ok = false; }
    if bv(&w2, 25) != 0x00 { ok = false; }
    if bv(&w2, 31) != 0x00 { ok = false; }
    let d2 = abi_decode_int(&w2, 0, 256);
    if !d2.is_ok {
      ok = false;
    } else if d2.value != int_min {
      ok = false;
    }
  }
  let e8 = abi_encode_int(-128, 8);
  if !e8.is_ok {
    ok = false;
  } else {
    let w8: Vec[UInt8] = e8.value;
    if bv(&w8, 31) != 0x80 { ok = false; }
    let d8 = abi_decode_int(&w8, 0, 8);
    if !d8.is_ok {
      ok = false;
    } else if d8.value != -128 {
      ok = false;
    }
  }
  let p127 = abi_encode_int(127, 8);
  if !p127.is_ok {
    ok = false;
  } else {
    let wp: Vec[UInt8] = p127.value;
    let dp = abi_decode_int(&wp, 0, 8);
    if !dp.is_ok {
      ok = false;
    } else if dp.value != 127 {
      ok = false;
    }
  }
  if !bprefix(abi_encode_int(128, 8), "abi: int value exceeds int width 8") { ok = false; }
  if !bprefix(abi_encode_int(-129, 8), "abi: int value exceeds int width 8") { ok = false; }
  if !bprefix(abi_encode_int(8, 4), "abi: invalid int width 4") { ok = false; }
  // 0x00...0080 (byte 24 set) is not the sign extension of a 64-bit Int.
  let not_ext = concat_bytes(concat_bytes(zeros(24), hb("80")), zeros(7));
  if !iprefix(abi_decode_int(&not_ext, 0, 256), "abi: int word does not fit Int") { ok = false; }
  let int64_max = abi_encode_int(9223372036854775807, 64);
  if !int64_max.is_ok {
    ok = false;
  } else {
    let wm: Vec[UInt8] = int64_max.value;
    let dm = abi_decode_int(&wm, 0, 64);
    if !dm.is_ok {
      ok = false;
    } else if dm.value != 9223372036854775807 {
      ok = false;
    }
  }
  return assert(ok, "ABI int<M> two's complement round-trips and bounds errors");
}

fn t15() -> TestResult {
  var ok = true;
  let f = abi_encode_bool(0);
  if !f.is_ok {
    ok = false;
  } else {
    let wf: Vec[UInt8] = f.value;
    if !bytes_equal(wf, zeros(32)) { ok = false; }
    let df = abi_decode_bool(&wf, 0);
    if !df.is_ok {
      ok = false;
    } else if df.value {
      ok = false;
    }
  }
  let t = abi_encode_bool(1);
  if !t.is_ok {
    ok = false;
  } else {
    let wt: Vec[UInt8] = t.value;
    if bv(&wt, 31) != 1 { ok = false; }
    let dt = abi_decode_bool(&wt, 0);
    if !dt.is_ok {
      ok = false;
    } else if !dt.value {
      ok = false;
    }
  }
  if !bprefix(abi_encode_bool(2), "abi: bool value must be 0 or 1") { ok = false; }
  let two = concat_bytes(zeros(31), hb("02"));
  if !bprefix(abi_decode_bool(&two, 0), "abi: bool word must be 0 or 1") { ok = false; }
  let high = concat_bytes(hb("0100"), zeros(30));
  if !bprefix(abi_decode_bool(&high, 0), "abi: bool word must be 0 or 1") { ok = false; }
  if !bprefix(abi_decode_bool_word(&zeros(31)), "abi: word must be 32 bytes") { ok = false; }
  return assert(ok, "ABI bool: 0/1 words only, other values rejected");
}

fn t16() -> TestResult {
  let addr = hb("52908400098527886e0f7030069857d2e4169ee7");
  var ok = true;
  let e = abi_encode_address(&addr);
  if !e.is_ok {
    return assert(false, "ABI address words");
  }
  let w: Vec[UInt8] = e.value;
  var i = 0;
  while i < 12 {
    if bv(&w, i) != 0 { ok = false; }
    i = i + 1;
  }
  if !bytes_equal(abi_decode_address(&w, 0).value, addr) { ok = false; }
  if !bprefix(abi_encode_address(&rep_byte(1, 19)), "abi: address value must be 20 bytes") { ok = false; }
  if !bprefix(abi_encode_address(&rep_byte(1, 21)), "abi: address value must be 20 bytes") { ok = false; }
  let misaligned = concat_bytes(hb("01"), zeros(31));
  if !bprefix(abi_decode_address(&misaligned, 0), "abi: address word is not right-aligned") { ok = false; }
  return assert(ok, "ABI address: 20 bytes right-aligned in a word");
}

fn t17() -> TestResult {
  var ok = true;
  let three = ab("abc");
  let want32 = concat_bytes(ab("abc"), zeros(29));
  let e = abi_encode_bytes32(&three);
  if !e.is_ok {
    ok = false;
  } else {
    let w: Vec[UInt8] = e.value;
    if bv(&w, 0) != 97 { ok = false; }
    if bv(&w, 2) != 99 { ok = false; }
    if bv(&w, 3) != 0 { ok = false; }
    if bv(&w, 31) != 0 { ok = false; }
    let d = abi_decode_bytes32(&w, 0);
    if !d.is_ok {
      ok = false;
    } else {
      let dv: Vec[UInt8] = d.value;
      if dv.len() != 32 { ok = false; }
      if !bytes_equal(dv, want32) { ok = false; }
    }
  }
  let full = rep_byte(0x5A, 32);
  let ef = abi_encode_bytes32(&full);
  if !ef.is_ok {
    ok = false;
  } else {
    let wf: Vec[UInt8] = ef.value;
    let df = abi_decode_bytes32(&wf, 0);
    if !df.is_ok {
      ok = false;
    } else if !bytes_equal(df.value, full) {
      ok = false;
    }
  }
  let e4 = abi_encode_bytes_m(&hb("deadbeef"), 4);
  if !e4.is_ok {
    ok = false;
  } else {
    let w4: Vec[UInt8] = e4.value;
    if bv(&w4, 3) != 0xEF { ok = false; }
    if bv(&w4, 4) != 0 { ok = false; }
    let d4 = abi_decode_bytes_m(&w4, 0, 4);
    if !d4.is_ok {
      ok = false;
    } else if !bytes_equal(d4.value, hb("deadbeef")) {
      ok = false;
    }
  }
  if !bprefix(abi_encode_bytes_m(&rep_byte(1, 5), 4), "abi: fixed bytes value exceeds width 4") { ok = false; }
  if !bprefix(abi_encode_bytes_m(&three, 0), "abi: invalid fixed-bytes width 0") { ok = false; }
  if !bprefix(abi_encode_bytes_m(&three, 33), "abi: invalid fixed-bytes width 33") { ok = false; }
  let badpad = concat_bytes(hb("deadbeef"), concat_bytes(hb("01"), zeros(27)));
  if !bprefix(abi_decode_bytes_m(&badpad, 0, 4), "abi: fixed bytes padding is not zero") { ok = false; }
  return assert(ok, "ABI bytes32 / bytes<M>: left-aligned, zero padding enforced");
}

fn t18() -> TestResult {
  let payload = ab("hello");
  let enc = abi_encode_dynamic_bytes(&payload);
  var ok = enc.len() == 96;
  if bv(&enc, 31) != 32 { ok = false; }
  if bv(&enc, 63) != 5 { ok = false; }
  if bv(&enc, 64) != 104 { ok = false; }
  if bv(&enc, 68) != 111 { ok = false; }
  if bv(&enc, 69) != 0 { ok = false; }
  let d = abi_decode_dynamic_bytes(&enc, 0, 0);
  if !d.is_ok {
    ok = false;
  } else if !bytes_equal(d.value, payload) {
    ok = false;
  }
  let empty = Vec[UInt8].new();
  let de = abi_decode_dynamic_bytes(&abi_encode_dynamic_bytes(&empty), 0, 0);
  if !de.is_ok {
    ok = false;
  } else if de.value.len() != 0 {
    ok = false;
  }
  // Bytes-safe: the payload may contain 0x00.
  let nully = hb("00010200ff");
  let dn = abi_decode_dynamic_bytes(&abi_encode_dynamic_bytes(&nully), 0, 0);
  if !dn.is_ok {
    ok = false;
  } else if !bytes_equal(dn.value, nully) {
    ok = false;
  }
  // Call-style: selector + static word + offset word, then the tail.
  let sel = hb("a9059cbb");
  let head = concat_bytes(word_of(5), word_of(64));
  let tail = abi_encode_dynamic_bytes_tail(&payload);
  let cr = abi_encode_call(&sel, &head, &tail);
  if !cr.is_ok {
    ok = false;
  } else {
    let call: Vec[UInt8] = cr.value;
    if call.len() != 4 + 64 + 64 { ok = false; }
    let ds = abi_decode_uint(&call, 4, 256);
    if !ds.is_ok {
      ok = false;
    } else if ds.value != 5 {
      ok = false;
    }
    let dd = abi_decode_dynamic_bytes(&call, 36, 4);
    if !dd.is_ok {
      ok = false;
    } else if !bytes_equal(dd.value, payload) {
      ok = false;
    }
  }
  return assert(ok, "ABI dynamic bytes: standalone and call-style round-trips");
}

fn t19() -> TestResult {
  var ok = true;
  let mis = concat_bytes(word_of(33), zeros(32));
  if !bprefix(abi_decode_dynamic_bytes(&mis, 0, 0), "abi: dynamic offset is not word-aligned at offset 0") { ok = false; }
  let far = concat_bytes(word_of(64), zeros(32));
  if !bprefix(abi_decode_dynamic_bytes(&far, 0, 0), "abi: dynamic offset out of bounds at offset 0") { ok = false; }
  let into = concat_bytes(word_of(0), zeros(32));
  if !bprefix(abi_decode_dynamic_bytes(&into, 0, 0), "abi: dynamic offset points into the head at offset 0") { ok = false; }
  let bad_off = concat_bytes(hb("01"), zeros(31));
  if !bprefix(abi_decode_dynamic_bytes(&bad_off, 0, 0), "abi: offset word exceeds Int at offset 0") { ok = false; }
  let bad_len = concat_bytes(word_of(32), concat_bytes(hb("01"), zeros(31)));
  if !bprefix(abi_decode_dynamic_bytes(&bad_len, 0, 0), "abi: length word exceeds Int at offset 32") { ok = false; }
  let big_len = concat_bytes(word_of(32), concat_bytes(word_of(64), zeros(32)));
  if !bprefix(abi_decode_dynamic_bytes(&big_len, 0, 0), "abi: dynamic data out of bounds at offset 64") { ok = false; }
  let unpadded = concat_bytes(word_of(32), concat_bytes(word_of(5), rep_byte(9, 5)));
  if !bprefix(abi_decode_dynamic_bytes(&unpadded, 0, 0), "abi: dynamic data out of bounds at offset 64") { ok = false; }
  let short = concat_bytes(word_of(32), zeros(8));
  if !bprefix(abi_decode_dynamic_bytes(&short, 0, 0), "abi: dynamic offset out of bounds at offset 0") { ok = false; }
  if !bprefix(abi_decode_dynamic_bytes(&word_of(32), 40, 0), "abi: word out of bounds at offset 40") { ok = false; }
  return assert(ok, "ABI dynamic bytes: malformed offsets and truncation");
}

fn t20() -> TestResult {
  var words = Vec[Vec[UInt8]].new();
  words.push(word_of(1));
  words.push(word_of(2));
  let e255 = abi_encode_uint(255, 256);
  if !e255.is_ok {
    return assert(false, "ABI dynamic word arrays");
  }
  let w255: Vec[UInt8] = e255.value;
  words.push(w255);
  let er = abi_encode_word_array(&words);
  var ok = true;
  if !er.is_ok {
    return assert(false, "ABI dynamic word arrays");
  }
  let enc: Vec[UInt8] = er.value;
  if enc.len() != 32 + 32 + 96 { ok = false; }
  let cnt = abi_decode_array_count(&enc, 0, 0);
  if !cnt.is_ok {
    ok = false;
  } else if cnt.value != 3 {
    ok = false;
  }
  let vals = abi_decode_uint_array(&enc, 0, 0, 256);
  if !vals.is_ok {
    ok = false;
  } else {
    let vs: Vec[Int] = vals.value;
    if vs.len() != 3 { ok = false; }
    if vs[0] != 1 { ok = false; }
    if vs[1] != 2 { ok = false; }
    if vs[2] != 255 { ok = false; }
  }
  let e1 = abi_array_element(&enc, 0, 0, 1);
  if !e1.is_ok {
    ok = false;
  } else {
    let w1: Vec[UInt8] = e1.value;
    let dv = abi_decode_uint_word(&w1, 256);
    if !dv.is_ok {
      ok = false;
    } else if dv.value != 2 {
      ok = false;
    }
  }
  if !bprefix(abi_array_element(&enc, 0, 0, 3), "abi: array index out of range") { ok = false; }
  let huge = concat_bytes(word_of(32), word_of(100));
  if !iprefix(abi_decode_array_count(&huge, 0, 0), "abi: array elements out of bounds at offset 64") { ok = false; }
  let empt = concat_bytes(word_of(32), word_of(0));
  let ce = abi_decode_array_count(&empt, 0, 0);
  if !ce.is_ok {
    ok = false;
  } else if ce.value != 0 {
    ok = false;
  }
  var bad = Vec[Vec[UInt8]].new();
  bad.push(rep_byte(1, 31));
  if !bprefix(abi_encode_word_array_tail(&bad), "abi: array element must be 32 bytes") { ok = false; }
  return assert(ok, "ABI dynamic arrays: length word, elements, bounds");
}

fn t21() -> TestResult {
  let sel = hb("a9059cbb");
  let head = concat_bytes(word_of(5), word_of(64));
  let payload = ab("hi");
  let tail = abi_encode_dynamic_bytes_tail(&payload);
  let cr = abi_encode_call(&sel, &head, &tail);
  var ok = true;
  if !cr.is_ok {
    return assert(false, "ABI function-call data shape");
  }
  let call: Vec[UInt8] = cr.value;
  if call.len() != 4 + 64 + 32 + 32 { ok = false; }
  let sr = abi_call_selector(&call);
  if !sr.is_ok {
    ok = false;
  } else if !bytes_equal(sr.value, sel) {
    ok = false;
  }
  let ar = abi_call_args(&call);
  if !ar.is_ok {
    ok = false;
  } else if ar.value.len() != 128 {
    ok = false;
  }
  if abi_call_args_offset() != 4 { ok = false; }
  let dd = abi_decode_dynamic_bytes(&call, abi_call_args_offset() + 32, abi_call_args_offset());
  if !dd.is_ok {
    ok = false;
  } else if !bytes_equal(dd.value, payload) {
    ok = false;
  }
  if !bprefix(abi_encode_call(&hb("a9059c"), &head, &tail), "abi: selector must be 4 bytes") { ok = false; }
  if !bprefix(abi_call_selector(&hb("a9059c")), "abi: call data shorter than selector") { ok = false; }
  if !bprefix(abi_call_args(&hb("a9059c")), "abi: call data shorter than selector") { ok = false; }
  return assert(ok, "ABI function-call data shape: selector, head, tail");
}

// --------------------------------------------------
//  Hex and address tests
// --------------------------------------------------

fn t22() -> TestResult {
  var ok = str_is(eth_hex_bytes(&Vec[UInt8].new()), "0x");
  if !str_is(eth_hex_bytes(&hb("00ff10")), "0x00ff10") { ok = false; }
  if !str_is(eth_hex_bytes(&hb("deadbeef")), "0xdeadbeef") { ok = false; }
  let z = eth_hex_uint(0, 1);
  if !z.is_ok {
    ok = false;
  } else if !str_is(z.value, "0x00") {
    ok = false;
  }
  let f = eth_hex_uint(255, 1);
  if !f.is_ok {
    ok = false;
  } else if !str_is(f.value, "0xff") {
    ok = false;
  }
  let w2 = eth_hex_uint(256, 2);
  if !w2.is_ok {
    ok = false;
  } else if !str_is(w2.value, "0x0100") {
    ok = false;
  }
  let w32 = eth_hex_uint(1, 32);
  if !w32.is_ok {
    ok = false;
  } else if string.str_len(w32.value) != 66 {
    ok = false;
  }
  if !sprefix(eth_hex_uint(-1, 1), "eth: quantity is negative") { ok = false; }
  if !sprefix(eth_hex_uint(1, 0), "eth: quantity width must be 1..32 bytes") { ok = false; }
  if !sprefix(eth_hex_uint(1, 33), "eth: quantity width must be 1..32 bytes") { ok = false; }
  if !sprefix(eth_hex_uint(256, 1), "eth: quantity exceeds width 1 bytes") { ok = false; }
  return assert(ok, "hex rendering: 0x prefix, lowercase, zero padding");
}

fn t23() -> TestResult {
  var ok = true;
  let n1 = eth_address_normalize("0x52908400098527886E0F7030069857D2E4169EE7");
  if !n1.is_ok {
    ok = false;
  } else if !str_is(n1.value, "0x52908400098527886e0f7030069857d2e4169ee7") {
    ok = false;
  }
  let n2 = eth_address_normalize("52908400098527886e0f7030069857d2e4169ee7");
  if !n2.is_ok {
    ok = false;
  } else if !str_is(n2.value, "0x52908400098527886e0f7030069857d2e4169ee7") {
    ok = false;
  }
  let n3 = eth_address_normalize("0X52908400098527886E0F7030069857D2E4169EE7");
  if !n3.is_ok {
    ok = false;
  } else if !str_is(n3.value, "0x52908400098527886e0f7030069857d2e4169ee7") {
    ok = false;
  }
  if !sprefix(eth_address_normalize("0x123"), "eth: address must be 40 hex digits") { ok = false; }
  if !sprefix(eth_address_normalize("0x52908400098527886e0f7030069857d2e4169ee"), "eth: address must be 40 hex digits") { ok = false; }
  if !sprefix(eth_address_normalize("0xgg908400098527886e0f7030069857d2e4169ee7"), "eth: address contains a non-hex character") { ok = false; }
  let br = eth_address_bytes("0x52908400098527886e0f7030069857d2e4169ee7");
  if !br.is_ok {
    ok = false;
  } else {
    let b: Vec[UInt8] = br.value;
    if b.len() != 20 { ok = false; }
    if bv(&b, 0) != 0x52 { ok = false; }
    if bv(&b, 19) != 0xE7 { ok = false; }
    let fr = eth_address_from_bytes(&b);
    if !fr.is_ok {
      ok = false;
    } else if !str_is(fr.value, "0x52908400098527886e0f7030069857d2e4169ee7") {
      ok = false;
    }
  }
  if !sprefix(eth_address_from_bytes(&rep_byte(1, 19)), "eth: address bytes must be 20 bytes") { ok = false; }
  return assert(ok, "address normalization, validation and byte round-trip");
}

fn main() -> Int {
  io.println("=== xiom.ethereum conformance tests ===");
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
  if failed == 0 {
    io.println("xiom.ethereum: all tests passed");
  } else {
    io.println("xiom.ethereum: tests failed");
  }
  return failed;
}
