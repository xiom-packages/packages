// XIOM -- xiom.mongo conformance tests (23 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Covers the documented API with synthetic buffers built in-test: the BSON
// document frame and every implemented element type, nested documents and
// arrays, the nesting depth cap, malformed length/value framing, bounds-safe
// accessors, the wire header, unknown opcodes preserved raw, OP_MSG sections
// (kind 0 body, kind 1 document sequences, checksum flag), the legacy
// opcodes, OP_COMPRESSED, consumed counts over concatenated messages and
// exact byte-offset error messages.
//
// Harness style mirrors xiom.hello / xiom.cbor / xiom.amqp: one fn tN() ->
// TestResult per check, called directly from main; main prints
// [PASS]/[FAIL] and returns the failure count. Str payloads are compared
// with str_compare (BUG 17 discipline: `==` on a Str read from a Vec lowers
// to a pointer comparison).

module mongo_tests
use xiom.io; use xiom.test;
use xiom.string; use xiom.string.compare; use xiom.string.builder;
use xiom.convert; use xiom.encoding.hex;
use xiom.mongo;

// --------------------------------------------------
//  Byte-buffer helpers
// --------------------------------------------------

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

// Decimal rendering of a non-negative Int (for exact error-offset texts).
fn ist(n: Int) -> Str {
  return convert.int.int_to_string(n);
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

fn push_vec(out: &mut Vec[UInt8], v: &Vec[UInt8]) {
  var i = 0;
  while i < v.len() {
    out.push(v[i]);
    i = i + 1;
  }
}

fn concat2(a: Vec[UInt8], b: Vec[UInt8]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  push_vec(&mut out, &a);
  push_vec(&mut out, &b);
  return out;
}

fn concat3(a: Vec[UInt8], b: Vec[UInt8], c: Vec[UInt8]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  push_vec(&mut out, &a);
  push_vec(&mut out, &b);
  push_vec(&mut out, &c);
  return out;
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

fn fill_bytes(n: Int, b: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < n {
    v.push(b as UInt8);
    i = i + 1;
  }
  return v;
}

fn slice_bytes(v: Vec[UInt8], from: Int, to: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = from;
  while i < to {
    out.push(v[i]);
    i = i + 1;
  }
  return out;
}

// Little-endian two's-complement 32-bit word.
fn le32(v: Int) -> Vec[UInt8] {
  var x = v % 4294967296;
  if x < 0 { x = x + 4294967296; }
  var out = Vec[UInt8].new();
  out.push((x % 256) as UInt8);
  x = x / 256;
  out.push((x % 256) as UInt8);
  x = x / 256;
  out.push((x % 256) as UInt8);
  x = x / 256;
  out.push((x % 256) as UInt8);
  return out;
}

// Little-endian two's-complement 64-bit word.
fn le64(v: Int) -> Vec[UInt8] {
  var x = v % 18446744073709551616;
  if x < 0 { x = x + 18446744073709551616; }
  var out = Vec[UInt8].new();
  var i = 0;
  while i < 8 {
    out.push((x % 256) as UInt8);
    x = x / 256;
    i = i + 1;
  }
  return out;
}

// A NUL-terminated cstring.
fn cstr(s: Str) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  let b = ab(s);
  push_vec(&mut out, &b);
  out.push(0 as UInt8);
  return out;
}

// --------------------------------------------------
//  BSON builders
// --------------------------------------------------

// A document from already-encoded elements: int32 total length + elements +
// 0x00 terminator.
fn doc(parts: Vec[Vec[UInt8]]) -> Vec[UInt8] {
  var body = Vec[UInt8].new();
  var i = 0;
  while i < parts.len() {
    let part: Vec[UInt8] = parts[i];
    push_vec(&mut body, &part);
    i = i + 1;
  }
  var out = Vec[UInt8].new();
  let total = 4 + body.len() + 1;
  push_vec(&mut out, &le32(total));
  push_vec(&mut out, &body);
  out.push(0 as UInt8);
  return out;
}

// One element: type byte + cstring key + payload.
fn el(t: Int, key: Str, payload: Vec[UInt8]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  out.push(t as UInt8);
  push_vec(&mut out, &cstr(key));
  push_vec(&mut out, &payload);
  return out;
}

fn null_el(key: Str) -> Vec[UInt8] {
  return el(10, key, Vec[UInt8].new());
}

fn undef_el(key: Str) -> Vec[UInt8] {
  return el(6, key, Vec[UInt8].new());
}

fn min_el(key: Str) -> Vec[UInt8] {
  return el(255, key, Vec[UInt8].new());
}

fn max_el(key: Str) -> Vec[UInt8] {
  return el(127, key, Vec[UInt8].new());
}

fn i32_el(key: Str, v: Int) -> Vec[UInt8] {
  return el(16, key, le32(v));
}

fn i64_el(key: Str, v: Int) -> Vec[UInt8] {
  return el(18, key, le64(v));
}

fn date_el(key: Str, ms: Int) -> Vec[UInt8] {
  return el(9, key, le64(ms));
}

fn bool_el(key: Str, b: Int) -> Vec[UInt8] {
  var p = Vec[UInt8].new();
  p.push(b as UInt8);
  return el(8, key, p);
}

// Double from its raw little-endian 8-byte pattern.
fn dbl_el(key: Str, raw: Vec[UInt8]) -> Vec[UInt8] {
  return el(1, key, raw);
}

// Timestamp from its raw words (increment, seconds).
fn ts_el(key: Str, increment: Int, seconds: Int) -> Vec[UInt8] {
  return el(17, key, concat2(le32(increment), le32(seconds)));
}

fn oid_el(key: Str, bytes: Vec[UInt8]) -> Vec[UInt8] {
  return el(7, key, bytes);
}

fn dec_el(key: Str, bytes: Vec[UInt8]) -> Vec[UInt8] {
  return el(19, key, bytes);
}

fn bin_el(key: Str, subtype: Int, data: Vec[UInt8]) -> Vec[UInt8] {
  var p = Vec[UInt8].new();
  push_vec(&mut p, &le32(data.len()));
  p.push(subtype as UInt8);
  push_vec(&mut p, &data);
  return el(5, key, p);
}

fn regex_el(key: Str, pattern: Str, options: Str) -> Vec[UInt8] {
  return el(11, key, concat2(cstr(pattern), cstr(options)));
}

fn str_el(key: Str, s: Str) -> Vec[UInt8] {
  var p = Vec[UInt8].new();
  push_vec(&mut p, &le32(ab(s).len() + 1));
  push_vec(&mut p, &ab(s));
  p.push(0 as UInt8);
  return el(2, key, p);
}

fn sym_el(key: Str, s: Str) -> Vec[UInt8] {
  var p = Vec[UInt8].new();
  push_vec(&mut p, &le32(ab(s).len() + 1));
  push_vec(&mut p, &ab(s));
  p.push(0 as UInt8);
  return el(14, key, p);
}

fn js_el(key: Str, s: Str) -> Vec[UInt8] {
  var p = Vec[UInt8].new();
  push_vec(&mut p, &le32(ab(s).len() + 1));
  push_vec(&mut p, &ab(s));
  p.push(0 as UInt8);
  return el(13, key, p);
}

fn embedded_el(key: Str, inner: Vec[UInt8]) -> Vec[UInt8] {
  return el(3, key, inner);
}

fn array_el(key: Str, inner: Vec[UInt8]) -> Vec[UInt8] {
  return el(4, key, inner);
}

fn code_el(key: Str, code: Str, scope: Vec[UInt8]) -> Vec[UInt8] {
  var cp = Vec[UInt8].new();
  push_vec(&mut cp, &le32(ab(code).len() + 1));
  push_vec(&mut cp, &ab(code));
  cp.push(0 as UInt8);
  let total = 4 + cp.len() + scope.len();
  var p = Vec[UInt8].new();
  push_vec(&mut p, &le32(total));
  push_vec(&mut p, &cp);
  push_vec(&mut p, &scope);
  return el(15, key, p);
}

// --------------------------------------------------
//  Wire builders
// --------------------------------------------------

fn msg(op: Int, req: Int, resp: Int, body: Vec[UInt8]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  let total = 16 + body.len();
  push_vec(&mut out, &le32(total));
  push_vec(&mut out, &le32(req));
  push_vec(&mut out, &le32(resp));
  push_vec(&mut out, &le32(op));
  push_vec(&mut out, &body);
  return out;
}

fn opmsg_body(flags: Int, sections: Vec[Vec[UInt8]]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  push_vec(&mut out, &le32(flags));
  var i = 0;
  while i < sections.len() {
    let s: Vec[UInt8] = sections[i];
    push_vec(&mut out, &s);
    i = i + 1;
  }
  return out;
}

fn sec0(d: Vec[UInt8]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  out.push(0 as UInt8);
  push_vec(&mut out, &d);
  return out;
}

// kind 1: 0x01 + int32 size (includes the size field itself) + identifier
// cstring + documents.
fn sec1(ident: Str, docs: Vec[Vec[UInt8]]) -> Vec[UInt8] {
  var body = cstr(ident);
  var i = 0;
  while i < docs.len() {
    let d: Vec[UInt8] = docs[i];
    push_vec(&mut body, &d);
    i = i + 1;
  }
  var out = Vec[UInt8].new();
  out.push(1 as UInt8);
  push_vec(&mut out, &le32(4 + body.len()));
  push_vec(&mut out, &body);
  return out;
}

// --------------------------------------------------
//  Decode helpers (each decodes independently and degrades to a sentinel)
// --------------------------------------------------

fn ok_doc(data: Vec[UInt8]) -> Bool {
  let r = bson_parse_document(data);
  return r.is_ok;
}

fn err_is(data: Vec[UInt8], want: Str) -> Bool {
  let r = bson_parse_document(data);
  if r.is_ok {
    return false;
  }
  return str_compare(r.error, want) == 0;
}

fn msg_err_is(data: Vec[UInt8], want: Str) -> Bool {
  let r = mongo_parse_message(data);
  if r.is_ok {
    return false;
  }
  return str_compare(r.error, want) == 0;
}

fn msg_ok(data: Vec[UInt8]) -> Bool {
  let r = mongo_parse_message(data);
  return r.is_ok;
}

// Root child token with key `key`, or -2 when the document does not decode.
fn dfind_tok(data: Vec[UInt8], key: Str) -> Int {
  let r = bson_parse_document(data);
  if !r.is_ok {
    return -2;
  }
  let d: BsonDoc = r.value;
  return bson_find_key_str(&d, 0, key);
}

fn dkind(data: Vec[UInt8], key: Str) -> Int {
  let r = bson_parse_document(data);
  if !r.is_ok {
    return -2;
  }
  let d: BsonDoc = r.value;
  let t = bson_find_key_str(&d, 0, key);
  if t < 0 {
    return -1;
  }
  return bson_kind(&d, t);
}

fn dval(data: Vec[UInt8], key: Str) -> Int {
  let r = bson_parse_document(data);
  if !r.is_ok {
    return 0;
  }
  let d: BsonDoc = r.value;
  let t = bson_find_key_str(&d, 0, key);
  if t < 0 {
    return 0;
  }
  return bson_int_value(&d, t);
}

fn dbool(data: Vec[UInt8], key: Str) -> Int {
  let r = bson_parse_document(data);
  if !r.is_ok {
    return -2;
  }
  let d: BsonDoc = r.value;
  let t = bson_find_key_str(&d, 0, key);
  if t < 0 {
    return -1;
  }
  return bson_bool_value(&d, t);
}

fn dbytes(data: Vec[UInt8], key: Str) -> Vec[UInt8] {
  let r = bson_parse_document(data);
  if !r.is_ok {
    return Vec[UInt8].new();
  }
  let d: BsonDoc = r.value;
  let t = bson_find_key_str(&d, 0, key);
  if t < 0 {
    return Vec[UInt8].new();
  }
  return bson_payload_bytes(&d, t);
}

fn dlen(data: Vec[UInt8], key: Str) -> Int {
  let r = bson_parse_document(data);
  if !r.is_ok {
    return -2;
  }
  let d: BsonDoc = r.value;
  let t = bson_find_key_str(&d, 0, key);
  if t < 0 {
    return -1;
  }
  return bson_payload_len(&d, t);
}

fn dsub(data: Vec[UInt8], key: Str) -> Int {
  let r = bson_parse_document(data);
  if !r.is_ok {
    return -2;
  }
  let d: BsonDoc = r.value;
  let t = bson_find_key_str(&d, 0, key);
  if t < 0 {
    return -1;
  }
  return bson_binary_subtype(&d, t);
}

fn dword_low(data: Vec[UInt8], key: Str) -> Int {
  let r = bson_parse_document(data);
  if !r.is_ok {
    return -2;
  }
  let d: BsonDoc = r.value;
  let t = bson_find_key_str(&d, 0, key);
  if t < 0 {
    return -1;
  }
  return bson_word_low(&d, t);
}

fn dword_high(data: Vec[UInt8], key: Str) -> Int {
  let r = bson_parse_document(data);
  if !r.is_ok {
    return -2;
  }
  let d: BsonDoc = r.value;
  let t = bson_find_key_str(&d, 0, key);
  if t < 0 {
    return -1;
  }
  return bson_word_high(&d, t);
}

// Root child count of `key`, or -2 on decode error and -1 when missing.
fn dchild_count(data: Vec[UInt8], key: Str) -> Int {
  let r = bson_parse_document(data);
  if !r.is_ok {
    return -2;
  }
  let d: BsonDoc = r.value;
  let t = bson_find_key_str(&d, 0, key);
  if t < 0 {
    return -1;
  }
  return bson_child_count(&d, t);
}

// Index of child `n` of the element `key` in the root document.
fn dchild(data: Vec[UInt8], key: Str, n: Int) -> Int {
  let r = bson_parse_document(data);
  if !r.is_ok {
    return -2;
  }
  let d: BsonDoc = r.value;
  let t = bson_find_key_str(&d, 0, key);
  if t < 0 {
    return -1;
  }
  return bson_child(&d, t, n);
}

// Kind/bytes/value/key of a child token index computed by dchild.
fn tkind(data: Vec[UInt8], t: Int) -> Int {
  let r = bson_parse_document(data);
  if !r.is_ok {
    return -2;
  }
  let d: BsonDoc = r.value;
  return bson_kind(&d, t);
}

fn tkey_is(data: Vec[UInt8], t: Int, want: Str) -> Bool {
  let r = bson_parse_document(data);
  if !r.is_ok {
    return false;
  }
  let d: BsonDoc = r.value;
  return bytes_equal(bson_key_bytes(&d, t), ab(want));
}

fn tval(data: Vec[UInt8], t: Int) -> Int {
  let r = bson_parse_document(data);
  if !r.is_ok {
    return 0;
  }
  let d: BsonDoc = r.value;
  return bson_int_value(&d, t);
}

// Message scalar helpers.
fn m_field_i32(data: Vec[UInt8], which: Int) -> Int {
  let r = mongo_parse_message(data);
  if !r.is_ok {
    return -99;
  }
  let m: MongoMsg = r.value;
  if which == 0 { return mongo_msg_opcode(&m); }
  if which == 1 { return mongo_msg_flags(&m); }
  if which == 2 { return mongo_msg_number_to_skip(&m); }
  if which == 3 { return mongo_msg_number_to_return(&m); }
  if which == 4 { return mongo_msg_starting_from(&m); }
  if which == 5 { return mongo_msg_number_returned(&m); }
  if which == 6 { return mongo_msg_zero(&m); }
  if which == 7 { return mongo_msg_cursor_count(&m); }
  if which == 8 { return mongo_msg_orig_opcode(&m); }
  if which == 9 { return mongo_msg_uncompressed_size(&m); }
  if which == 10 { return mongo_msg_compressor_id(&m); }
  if which == 11 { return mongo_msg_consumed(&m); }
  if which == 12 { return mongo_msg_request_id(&m); }
  if which == 13 { return mongo_msg_response_to(&m); }
  if which == 14 { return mongo_msg_cursor_id(&m); }
  if which == 15 { return mongo_msg_body_doc_index(&m); }
  return -98;
}

fn m_doc_count(data: Vec[UInt8]) -> Int {
  let r = mongo_parse_message(data);
  if !r.is_ok {
    return -1;
  }
  let m: MongoMsg = r.value;
  return mongo_msg_doc_count(&m);
}

fn m_sec_count(data: Vec[UInt8]) -> Int {
  let r = mongo_parse_message(data);
  if !r.is_ok {
    return -1;
  }
  let m: MongoMsg = r.value;
  return mongo_msg_section_count(&m);
}

fn m_sec_kind(data: Vec[UInt8], n: Int) -> Int {
  let r = mongo_parse_message(data);
  if !r.is_ok {
    return -99;
  }
  let m: MongoMsg = r.value;
  return mongo_msg_section_kind(&m, n);
}

fn m_sec_end(data: Vec[UInt8], n: Int) -> Int {
  let r = mongo_parse_message(data);
  if !r.is_ok {
    return -99;
  }
  let m: MongoMsg = r.value;
  return mongo_msg_section_end(&m, n);
}

fn m_sec_ident(data: Vec[UInt8], n: Int) -> Vec[UInt8] {
  let r = mongo_parse_message(data);
  if !r.is_ok {
    return Vec[UInt8].new();
  }
  let m: MongoMsg = r.value;
  return mongo_msg_section_ident_bytes(&m, n);
}

fn m_payload(data: Vec[UInt8]) -> Vec[UInt8] {
  let r = mongo_parse_message(data);
  if !r.is_ok {
    return Vec[UInt8].new();
  }
  let m: MongoMsg = r.value;
  return mongo_msg_payload(&m);
}

fn m_message_bytes(data: Vec[UInt8]) -> Vec[UInt8] {
  let r = mongo_parse_message(data);
  if !r.is_ok {
    return Vec[UInt8].new();
  }
  let m: MongoMsg = r.value;
  return mongo_msg_body(&m);
}

fn m_ns(data: Vec[UInt8]) -> Vec[UInt8] {
  let r = mongo_parse_message(data);
  if !r.is_ok {
    return Vec[UInt8].new();
  }
  let m: MongoMsg = r.value;
  return mongo_msg_namespace_bytes(&m);
}

fn m_checksum(data: Vec[UInt8]) -> Vec[UInt8] {
  let r = mongo_parse_message(data);
  if !r.is_ok {
    return Vec[UInt8].new();
  }
  let m: MongoMsg = r.value;
  return mongo_msg_checksum_bytes(&m);
}

fn m_cursor_at(data: Vec[UInt8], n: Int) -> Int {
  let r = mongo_parse_message(data);
  if !r.is_ok {
    return -99;
  }
  let m: MongoMsg = r.value;
  return mongo_msg_cursor_id_at(&m, n);
}

// Int value of `key` in top-level document `docn` of a message.
fn m_doc_key_int(data: Vec[UInt8], docn: Int, key: Str) -> Int {
  let r = mongo_parse_message(data);
  if !r.is_ok {
    return 0;
  }
  let m: MongoMsg = r.value;
  let root = mongo_msg_doc_root(&m, docn);
  if root < 0 {
    return 0;
  }
  let docs: BsonDoc = m.docs;
  let t = bson_find_key_str(&docs, root, key);
  if t < 0 {
    return 0;
  }
  return bson_int_value(&docs, t);
}

fn m_doc_key_kind(data: Vec[UInt8], docn: Int, key: Str) -> Int {
  let r = mongo_parse_message(data);
  if !r.is_ok {
    return -2;
  }
  let m: MongoMsg = r.value;
  let root = mongo_msg_doc_root(&m, docn);
  if root < 0 {
    return -1;
  }
  let docs: BsonDoc = m.docs;
  let t = bson_find_key_str(&docs, root, key);
  if t < 0 {
    return -1;
  }
  return bson_kind(&docs, t);
}

// String payload of `key` in top-level document `docn` of a message.
fn m_doc_key_bytes(data: Vec[UInt8], docn: Int, key: Str) -> Vec[UInt8] {
  let r = mongo_parse_message(data);
  if !r.is_ok {
    return Vec[UInt8].new();
  }
  let m: MongoMsg = r.value;
  let root = mongo_msg_doc_root(&m, docn);
  if root < 0 {
    return Vec[UInt8].new();
  }
  let docs: BsonDoc = m.docs;
  let t = bson_find_key_str(&docs, root, key);
  if t < 0 {
    return Vec[UInt8].new();
  }
  return bson_string_bytes(&docs, t);
}

// `depth` nested single-element embedded documents around an empty document.
fn nest(depth: Int) -> Vec[UInt8] {
  var inner = hb("0500000000");
  var i = 0;
  while i < depth {
    var parts = Vec[Vec[UInt8]].new();
    parts.push(embedded_el("a", inner));
    inner = doc(parts);
    i = i + 1;
  }
  return inner;
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  var parts = Vec[Vec[UInt8]].new();
  parts.push(i32_el("a", 1));
  parts.push(i64_el("b", 0 - 2));
  parts.push(bool_el("c", 1));
  parts.push(null_el("d"));
  parts.push(date_el("e", 1234567890));
  parts.push(dbl_el("f", le64(4607182418800017408)));
  parts.push(undef_el("g"));
  parts.push(min_el("h"));
  parts.push(max_el("i"));
  let d = doc(parts);
  var ok = ok_doc(d);
  if !ok { return assert(false, "bson root frame and scalar element walk"); }
  let r = bson_parse_document(d);
  let dd: BsonDoc = r.value;
  if bson_token_count(&dd) != 10 { ok = false; }
  if bson_root(&dd) != 0 { ok = false; }
  if bson_kind(&dd, 0) != bson_kind_root_document() { ok = false; }
  if bson_token_start(&dd, 0) != 0 { ok = false; }
  if bson_token_end(&dd, 0) != d.len() { ok = false; }
  if bson_parent(&dd, bson_child(&dd, 0, 0)) != 0 { ok = false; }
  if bson_token_start(&dd, bson_child(&dd, 0, 0)) != 4 { ok = false; }
  if bson_next_sibling(&dd, bson_child(&dd, 0, 8)) != -1 { ok = false; }
  if bson_key_len(&dd, 0) != -1 { ok = false; }
  if !bytes_equal(bson_key_bytes(&dd, bson_child(&dd, 0, 0)), ab("a")) { ok = false; }
  if dkind(d, "a") != bson_kind_int32() { ok = false; }
  if dval(d, "a") != 1 { ok = false; }
  if dkind(d, "b") != bson_kind_int64() { ok = false; }
  if dval(d, "b") != -2 { ok = false; }
  if dkind(d, "c") != bson_kind_bool() { ok = false; }
  if dbool(d, "c") != 1 { ok = false; }
  if dkind(d, "d") != bson_kind_null() { ok = false; }
  if dlen(d, "d") != 0 { ok = false; }
  if dkind(d, "e") != bson_kind_datetime() { ok = false; }
  if dval(d, "e") != 1234567890 { ok = false; }
  if dkind(d, "f") != bson_kind_double() { ok = false; }
  if dword_low(d, "f") != 0 { ok = false; }
  if dword_high(d, "f") != 1072693248 { ok = false; }
  if dlen(d, "f") != 8 { ok = false; }
  if dkind(d, "g") != bson_kind_undefined() { ok = false; }
  if dkind(d, "h") != bson_kind_min_key() { ok = false; }
  if dkind(d, "i") != bson_kind_max_key() { ok = false; }
  return assert(ok, "bson root frame and scalar element walk");
}

fn t2() -> TestResult {
  var parts = Vec[Vec[UInt8]].new();
  parts.push(str_el("s", "hi"));
  parts.push(sym_el("y", "sym"));
  parts.push(js_el("j", "var x=1"));
  parts.push(str_el("e", ""));
  let d = doc(parts);
  var ok = ok_doc(d);
  if dkind(d, "s") != bson_kind_string() { ok = false; }
  if !bytes_equal(dbytes(d, "s"), ab("hi")) { ok = false; }
  if dlen(d, "s") != 2 { ok = false; }
  if dkind(d, "y") != bson_kind_symbol() { ok = false; }
  if !bytes_equal(dbytes(d, "y"), ab("sym")) { ok = false; }
  if dkind(d, "j") != bson_kind_javascript() { ok = false; }
  if !bytes_equal(dbytes(d, "j"), ab("var x=1")) { ok = false; }
  if dkind(d, "e") != bson_kind_string() { ok = false; }
  if dlen(d, "e") != 0 { ok = false; }
  return assert(ok, "bson string/symbol/javascript payloads");
}

fn t3() -> TestResult {
  let payload = hb("00ff0001");
  var parts = Vec[Vec[UInt8]].new();
  parts.push(bin_el("b", 128, payload));
  parts.push(bin_el("z", 0, Vec[UInt8].new()));
  let d = doc(parts);
  var ok = ok_doc(d);
  if dkind(d, "b") != bson_kind_binary() { ok = false; }
  if dlen(d, "b") != 4 { ok = false; }
  if !bytes_equal(dbytes(d, "b"), payload) { ok = false; }
  if dsub(d, "b") != 128 { ok = false; }
  if dlen(d, "z") != 0 { ok = false; }
  if dsub(d, "z") != 0 { ok = false; }
  let big = fill_bytes(255, 171);
  var parts2 = Vec[Vec[UInt8]].new();
  parts2.push(bin_el("big", 4, big));
  let d2 = doc(parts2);
  if !ok_doc(d2) { ok = false; }
  if dlen(d2, "big") != 255 { ok = false; }
  if !bytes_equal(dbytes(d2, "big"), big) { ok = false; }
  return assert(ok, "bson binary with 0x00 bytes and subtype");
}

fn t4() -> TestResult {
  let oid = hb("00112233445566778899aabb");
  let deci = hb("0102030405060708090a0b0c0d0e0f10");
  var parts = Vec[Vec[UInt8]].new();
  parts.push(oid_el("o", oid));
  parts.push(dec_el("x", deci));
  parts.push(regex_el("r", "ab.*", "im"));
  let d = doc(parts);
  var ok = ok_doc(d);
  if dkind(d, "o") != bson_kind_object_id() { ok = false; }
  if dlen(d, "o") != 12 { ok = false; }
  if !bytes_equal(dbytes(d, "o"), oid) { ok = false; }
  if dkind(d, "x") != bson_kind_decimal128() { ok = false; }
  if dlen(d, "x") != 16 { ok = false; }
  if !bytes_equal(dbytes(d, "x"), deci) { ok = false; }
  if dkind(d, "r") != bson_kind_regex() { ok = false; }
  let r = bson_parse_document(d);
  let dd: BsonDoc = r.value;
  let tr = bson_find_key_str(&dd, 0, "r");
  if !bytes_equal(bson_regex_pattern_bytes(&dd, tr), ab("ab.*")) { ok = false; }
  if !bytes_equal(bson_regex_options_bytes(&dd, tr), ab("im")) { ok = false; }
  return assert(ok, "bson objectid, decimal128 and regex");
}

fn t5() -> TestResult {
  let neg_one = hb("000000000000f0bf");
  var parts = Vec[Vec[UInt8]].new();
  parts.push(dbl_el("n", neg_one));
  parts.push(ts_el("t", 7, 9));
  let d = doc(parts);
  var ok = ok_doc(d);
  if dkind(d, "n") != bson_kind_double() { ok = false; }
  if !bytes_equal(dbytes(d, "n"), neg_one) { ok = false; }
  if dword_low(d, "n") != 0 { ok = false; }
  if dword_high(d, "n") != 3220176896 { ok = false; }
  if dkind(d, "t") != bson_kind_timestamp() { ok = false; }
  if dword_low(d, "t") != 7 { ok = false; }
  if dword_high(d, "t") != 9 { ok = false; }
  if dlen(d, "t") != 8 { ok = false; }
  return assert(ok, "bson double and timestamp raw words");
}

fn t6() -> TestResult {
  var inner_parts = Vec[Vec[UInt8]].new();
  inner_parts.push(i32_el("b", 1));
  inner_parts.push(str_el("c", "z"));
  let inner = doc(inner_parts);
  var arr_parts = Vec[Vec[UInt8]].new();
  arr_parts.push(i32_el("0", 1));
  var deep_parts = Vec[Vec[UInt8]].new();
  deep_parts.push(i32_el("d", 2));
  arr_parts.push(embedded_el("1", doc(deep_parts)));
  let arr = doc(arr_parts);
  var parts = Vec[Vec[UInt8]].new();
  parts.push(embedded_el("a", inner));
  parts.push(array_el("arr", arr));
  let d = doc(parts);
  var ok = ok_doc(d);
  if dkind(d, "a") != bson_kind_embedded_document() { ok = false; }
  if dchild_count(d, "a") != 2 { ok = false; }
  if dchild_count(d, "arr") != 2 { ok = false; }
  if dkind(d, "arr") != bson_kind_array() { ok = false; }
  let t0 = dchild(d, "arr", 0);
  let t1 = dchild(d, "arr", 1);
  if tkind(d, t0) != bson_kind_int32() { ok = false; }
  if !tkey_is(d, t0, "0") { ok = false; }
  if tval(d, t0) != 1 { ok = false; }
  if tkind(d, t1) != bson_kind_embedded_document() { ok = false; }
  if !tkey_is(d, t1, "1") { ok = false; }
  // Nested find: "b" inside "a".
  let r = bson_parse_document(d);
  let dd: BsonDoc = r.value;
  let ta = bson_find_key_str(&dd, 0, "a");
  let tb = bson_find_key_str(&dd, ta, "b");
  if tb < 0 { ok = false; }
  if bson_int_value(&dd, tb) != 1 { ok = false; }
  if bson_parent(&dd, tb) != ta { ok = false; }
  let tc = bson_find_key_str(&dd, ta, "c");
  if !bytes_equal(bson_string_bytes(&dd, tc), ab("z")) { ok = false; }
  let tarr = bson_find_key_str(&dd, 0, "arr");
  let tdeep = bson_child(&dd, tarr, 1);
  let td = bson_find_key_str(&dd, tdeep, "d");
  if td < 0 { ok = false; }
  if bson_int_value(&dd, td) != 2 { ok = false; }
  if bson_next_sibling(&dd, tdeep) != -1 { ok = false; }
  return assert(ok, "bson embedded document and array children");
}

fn t7() -> TestResult {
  var parts = Vec[Vec[UInt8]].new();
  parts.push(i32_el("alpha", 1));
  parts.push(i32_el("beta", 2));
  let d = doc(parts);
  var ok = ok_doc(d);
  let ta = dfind_tok(d, "alpha");
  let tb = dfind_tok(d, "beta");
  if ta < 0 || tb < 0 { ok = false; }
  if ta == tb { ok = false; }
  if dfind_tok(d, "gamma") != -1 { ok = false; }
  let r = bson_parse_document(d);
  let dd: BsonDoc = r.value;
  var want = ab("beta");
  let tbytes = bson_find_key(&dd, 0, &want);
  if tbytes != tb { ok = false; }
  if bson_child_count(&dd, 0) != 2 { ok = false; }
  if bson_child(&dd, 0, 0) != ta { ok = false; }
  if bson_child(&dd, 0, 1) != tb { ok = false; }
  if bson_child(&dd, 0, 2) != -1 { ok = false; }
  return assert(ok, "bson find_key lookup");
}

fn t8() -> TestResult {
  var scope_parts = Vec[Vec[UInt8]].new();
  scope_parts.push(i32_el("x", 1));
  let scope = doc(scope_parts);
  var parts = Vec[Vec[UInt8]].new();
  parts.push(code_el("f", "function(){}", scope));
  let d = doc(parts);
  var ok = ok_doc(d);
  if dkind(d, "f") != bson_kind_code_w_scope() { ok = false; }
  if !bytes_equal(dbytes(d, "f"), ab("function(){}")) { ok = false; }
  let r = bson_parse_document(d);
  let dd: BsonDoc = r.value;
  let tf = bson_find_key_str(&dd, 0, "f");
  if bson_child_count(&dd, tf) != 1 { ok = false; }
  let tscope = bson_child(&dd, tf, 0);
  if bson_kind(&dd, tscope) != bson_kind_root_document() { ok = false; }
  if bson_key_len(&dd, tscope) != -1 { ok = false; }
  if bson_parent(&dd, tscope) != tf { ok = false; }
  let tx = bson_find_key_str(&dd, tscope, "x");
  if bson_int_value(&dd, tx) != 1 { ok = false; }
  return assert(ok, "bson code-with-scope");
}

fn t9() -> TestResult {
  var ok = ok_doc(nest(50));
  if !ok_doc(nest(100)) { ok = false; }
  if !err_is(nest(101), "bson: nesting depth exceeds limit of 100 at 707") { ok = false; }
  if !err_is(nest(102), "bson: nesting depth exceeds limit of 100 at 707") { ok = false; }
  if bson_max_depth() != 100 { ok = false; }
  return assert(ok, "bson nesting depth cap");
}

fn t10() -> TestResult {
  var ok = err_is(hb("04000000"), "bson: bad document length 4 at 0");
  if !err_is(hb("05000000"), "bson: truncated document at 0") { ok = false; }
  let no_term = concat2(le32(11), hb("10780001000000"));
  if !err_is(no_term, "bson: missing document terminator at 0") { ok = false; }
  let bad_len = concat3(le32(9), hb("0a6100"), hb("00ff"));
  if !err_is(bad_len, "bson: bad document length at 0") { ok = false; }
  if !err_is(hb("080000000c610000"), "bson: unknown element type 12 at 4") { ok = false; }
  let extra = concat2(hb("0c0000001078000100000000"), hb("00"));
  if !err_is(extra, "bson: trailing data after document at 12") { ok = false; }
  if !err_is(hb("14000000107800010000"), "bson: truncated document at 0") { ok = false; }
  return assert(ok, "bson malformed frames and lengths");
}

fn t11() -> TestResult {
  var ok = err_is(hb("0c0000000273000000000000"), "bson: bad string length 0 at 4");
  if !err_is(hb("0b0000000273000a00000000"), "bson: truncated string at 4") { ok = false; }
  if !err_is(hb("0e00000002730002000000414200"), "bson: unterminated string at 4") { ok = false; }
  if !err_is(hb("0c000000056200ffffffff00"), "bson: bad binary length -1 at 4") { ok = false; }
  if !err_is(hb("090000000862000200"), "bson: bad boolean 2 at 4") { ok = false; }
  if !err_is(hb("080000001078000100"), "bson: truncated element at 4") { ok = false; }
  if !err_is(hb("060000000a6162"), "bson: unterminated key at 5") { ok = false; }
  let short_oid = concat2(le32(18), concat2(hb("076f00"), fill_bytes(11, 170)));
  if !err_is(short_oid, "bson: truncated element at 4") { ok = false; }
  if !err_is(hb("0b0000000b720061626300"), "bson: unterminated regex at 4") { ok = false; }
  if !err_is(hb("0c0000000f63000a00000000"), "bson: bad code_w_scope length 10 at 4") { ok = false; }
  return assert(ok, "bson malformed values");
}

fn t12() -> TestResult {
  var parts = Vec[Vec[UInt8]].new();
  parts.push(i32_el("k", 5));
  parts.push(str_el("s", "v"));
  let d = doc(parts);
  let r = bson_parse_document(d);
  var ok = r.is_ok;
  if !ok { return assert(false, "bson accessors are bounds-safe"); }
  let dd: BsonDoc = r.value;
  let t = bson_find_key_str(&dd, 0, "k");
  let ts = bson_find_key_str(&dd, 0, "s");
  if bson_kind(&dd, -1) != -1 { ok = false; }
  if bson_kind(&dd, 999) != -1 { ok = false; }
  if bson_parent(&dd, 0) != -1 { ok = false; }
  if bson_parent(&dd, -3) != -1 { ok = false; }
  if bson_first_child(&dd, t) != -1 { ok = false; }
  if bson_child_count(&dd, t) != 0 { ok = false; }
  if bson_child(&dd, 0, -1) != -1 { ok = false; }
  if bson_child(&dd, 0, 99) != -1 { ok = false; }
  if bson_next_sibling(&dd, t) != ts { ok = false; }
  if bson_next_sibling(&dd, ts) != -1 { ok = false; }
  if bson_token_start(&dd, 99) != -1 { ok = false; }
  if bson_token_end(&dd, 99) != -1 { ok = false; }
  if bson_key_len(&dd, 99) != -1 { ok = false; }
  if bson_key_len(&dd, 0) != -1 { ok = false; }
  if bson_payload_len(&dd, 99) != -1 { ok = false; }
  if bson_int_value(&dd, ts) != 0 { ok = false; }
  if bson_bool_value(&dd, t) != -1 { ok = false; }
  if bson_binary_len(&dd, t) != -1 { ok = false; }
  if bson_binary_subtype(&dd, t) != -1 { ok = false; }
  if bson_word_high(&dd, t) != -1 { ok = false; }
  if bson_oid_bytes(&dd, t).len() != 0 { ok = false; }
  if bson_decimal_bytes(&dd, ts).len() != 0 { ok = false; }
  if bson_string_bytes(&dd, t).len() != 0 { ok = false; }
  if bson_regex_pattern_bytes(&dd, t).len() != 0 { ok = false; }
  if bson_regex_options_bytes(&dd, t).len() != 0 { ok = false; }
  if bson_find_key_str(&dd, t, "k") != -1 { ok = false; }
  return assert(ok, "bson accessors are bounds-safe");
}

fn t13() -> TestResult {
  let body = hb("deadbeef");
  let d = msg(9999, 7, 3, body);
  var ok = msg_ok(d);
  if !ok { return assert(false, "wire header and unknown opcode preserved raw"); }
  if m_field_i32(d, 0) != 9999 { ok = false; }
  if m_field_i32(d, 12) != 7 { ok = false; }
  if m_field_i32(d, 13) != 3 { ok = false; }
  if m_field_i32(d, 11) != 20 { ok = false; }
  if m_field_i32(d, 1) != -1 { ok = false; }
  if m_doc_count(d) != 0 { ok = false; }
  if !bytes_equal(m_payload(d), body) { ok = false; }
  if !bytes_equal(m_message_bytes(d), body) { ok = false; }
  let r = mongo_parse_message(d);
  let m: MongoMsg = r.value;
  if mongo_msg_opcode_known(&m) { ok = false; }
  if !bytes_equal(mongo_msg_namespace_bytes(&m), Vec[UInt8].new()) { ok = false; }
  if mongo_msg_checksum_bytes(&m).len() != 0 { ok = false; }
  if !msg_err_is(fill_bytes(15, 0), "mongo: truncated message header at 0") { ok = false; }
  let short_header = concat3(le32(10), le32(0), concat2(le32(0), le32(9999)));
  if !msg_err_is(short_header, "mongo: bad message length 10 at 0") { ok = false; }
  let slow = concat2(le32(40), concat2(le32(1), concat3(le32(0), le32(9999), hb("0102"))));
  if !msg_err_is(slow, "mongo: truncated message at 0: declared 40 bytes, have 18") { ok = false; }
  return assert(ok, "wire header and unknown opcode preserved raw");
}

fn t14() -> TestResult {
  var doc1_parts = Vec[Vec[UInt8]].new();
  doc1_parts.push(i32_el("x", 1));
  let doc1 = doc(doc1_parts);
  var secs = Vec[Vec[UInt8]].new();
  secs.push(sec0(doc1));
  let body = opmsg_body(0, secs);
  let d = msg(2013, 11, 0, body);
  var ok = msg_ok(d);
  if !ok { return assert(false, "OP_MSG kind 0 body and checksum bit"); }
  if m_field_i32(d, 0) != 2013 { ok = false; }
  if m_field_i32(d, 1) != 0 { ok = false; }
  if m_sec_count(d) != 1 { ok = false; }
  if m_sec_kind(d, 0) != 0 { ok = false; }
  if m_doc_count(d) != 1 { ok = false; }
  if m_field_i32(d, 15) != 0 { ok = false; }
  if m_doc_key_int(d, 0, "x") != 1 { ok = false; }
  if m_field_i32(d, 11) != 33 { ok = false; }
  if m_sec_end(d, 0) != 33 { ok = false; }
  let r = mongo_parse_message(d);
  let m: MongoMsg = r.value;
  if !bytes_equal(mongo_msg_section_ident_bytes(&m, 0), Vec[UInt8].new()) { ok = false; }
  if str_compare(mongo_msg_opcode_name(&m), "OP_MSG") != 0 { ok = false; }
  // checksumPresent: the trailing 4 bytes leave the sections untouched.
  var secs2 = Vec[Vec[UInt8]].new();
  secs2.push(sec0(doc1));
  let body2 = concat2(opmsg_body(1, secs2), le32(16909060));
  let d2 = msg(2013, 12, 0, body2);
  if !msg_ok(d2) { ok = false; }
  if m_field_i32(d2, 1) != 1 { ok = false; }
  if m_field_i32(d2, 11) != 37 { ok = false; }
  if m_sec_count(d2) != 1 { ok = false; }
  if m_doc_count(d2) != 1 { ok = false; }
  if !bytes_equal(m_checksum(d2), le32(16909060)) { ok = false; }
  if m_sec_end(d2, 0) != 33 { ok = false; }
  var secs3 = Vec[Vec[UInt8]].new();
  secs3.push(sec0(doc1));
  let body3 = concat2(opmsg_body(65539, secs3), le32(1));
  let d3 = msg(2013, 13, 0, body3);
  if !msg_ok(d3) { ok = false; }
  if m_field_i32(d3, 1) != 65539 { ok = false; }
  if str_compare(mongo_opcode_name(2013), "OP_MSG") != 0 { ok = false; }
  if str_compare(mongo_opcode_name(777), "") != 0 { ok = false; }
  if mongo_opcode_name(2004).len() == 0 { ok = false; }
  return assert(ok, "OP_MSG kind 0 body and checksum bit");
}

fn t15() -> TestResult {
  var d1p = Vec[Vec[UInt8]].new();
  d1p.push(i32_el("a", 1));
  let doc1 = doc(d1p);
  var d2p = Vec[Vec[UInt8]].new();
  d2p.push(str_el("b", "two"));
  let doc2 = doc(d2p);
  // Sequence only.
  var s1 = Vec[Vec[UInt8]].new();
  s1.push(sec1("documents", Vec[Vec[UInt8]].new()));
  let empty_seq = msg(2013, 1, 0, opmsg_body(0, s1));
  var docs_seq = Vec[Vec[UInt8]].new();
  docs_seq.push(doc1);
  docs_seq.push(doc2);
  var s2 = Vec[Vec[UInt8]].new();
  s2.push(sec1("documents", docs_seq));
  let seq_only = msg(2013, 1, 0, opmsg_body(0, s2));
  var ok = msg_ok(seq_only);
  if m_sec_count(seq_only) != 1 { ok = false; }
  if m_sec_kind(seq_only, 0) != 1 { ok = false; }
  if !bytes_equal(m_sec_ident(seq_only, 0), ab("documents")) { ok = false; }
  if m_doc_count(seq_only) != 2 { ok = false; }
  if m_field_i32(seq_only, 15) != -1 { ok = false; }
  if m_doc_key_int(seq_only, 0, "a") != 1 { ok = false; }
  if !bytes_equal(m_doc_key_bytes(seq_only, 1, "b"), ab("two")) { ok = false; }
  // Sequence then body (body must be last, and is allowed there).
  var s3 = Vec[Vec[UInt8]].new();
  s3.push(sec1("d", docs_seq));
  s3.push(sec0(doc1));
  let seq_then_body = msg(2013, 2, 0, opmsg_body(0, s3));
  if !msg_ok(seq_then_body) { ok = false; }
  if m_sec_count(seq_then_body) != 2 { ok = false; }
  if m_sec_kind(seq_then_body, 0) != 1 { ok = false; }
  if m_sec_kind(seq_then_body, 1) != 0 { ok = false; }
  if m_doc_count(seq_then_body) != 3 { ok = false; }
  if m_field_i32(seq_then_body, 15) != 2 { ok = false; }
  // Body then sequence: rejected.
  var s4 = Vec[Vec[UInt8]].new();
  s4.push(sec0(doc1));
  s4.push(sec1("d", docs_seq));
  let body_then_seq = msg(2013, 3, 0, opmsg_body(0, s4));
  let seq_at = 20 + 1 + doc1.len();
  if !msg_err_is(body_then_seq, "mongo: body section is not last at " + ist(seq_at)) { ok = false; }
  // Duplicate body.
  var s5 = Vec[Vec[UInt8]].new();
  s5.push(sec0(doc1));
  s5.push(sec0(doc1));
  let two_bodies = msg(2013, 4, 0, opmsg_body(0, s5));
  if !msg_err_is(two_bodies, "mongo: duplicate body section at " + ist(seq_at)) { ok = false; }
  // Unknown section kind.
  var unknown_body = Vec[UInt8].new();
  push_vec(&mut unknown_body, &le32(0));
  unknown_body.push(2 as UInt8);
  push_vec(&mut unknown_body, &doc1);
  if !msg_err_is(msg(2013, 5, 0, unknown_body), "mongo: unknown section kind 2 at 20") { ok = false; }
  // Bad section size.
  var bad_size_body = Vec[UInt8].new();
  push_vec(&mut bad_size_body, &le32(0));
  bad_size_body.push(1 as UInt8);
  push_vec(&mut bad_size_body, &le32(9));
  push_vec(&mut bad_size_body, &cstr("d"));
  push_vec(&mut bad_size_body, &doc1);
  if !msg_err_is(msg(2013, 6, 0, bad_size_body), "mongo: bad section size 9 at 20") { ok = false; }
  // Empty document sequence.
  var empty_docs = Vec[Vec[UInt8]].new();
  var s6 = Vec[Vec[UInt8]].new();
  s6.push(sec1("abcdef", empty_docs));
  let empty_sequence = msg(2013, 7, 0, opmsg_body(0, s6));
  if !msg_err_is(empty_sequence, "mongo: empty document sequence at 20") { ok = false; }
  // Missing sections entirely.
  var no_sections = Vec[UInt8].new();
  push_vec(&mut no_sections, &le32(0));
  if !msg_err_is(msg(2013, 8, 0, no_sections), "mongo: missing sections at 20") { ok = false; }
  // The empty sequence above also fails (it has no documents).
  if msg_ok(empty_seq) { ok = false; }
  return assert(ok, "OP_MSG kind 1 sequences and section errors");
}

fn t16() -> TestResult {
  var qp = Vec[Vec[UInt8]].new();
  qp.push(i32_el("x", 1));
  let query = doc(qp);
  var sp = Vec[Vec[UInt8]].new();
  sp.push(i32_el("y", 2));
  let selector = doc(sp);
  var body = Vec[UInt8].new();
  push_vec(&mut body, &le32(4));
  push_vec(&mut body, &cstr("db.coll"));
  push_vec(&mut body, &le32(1));
  push_vec(&mut body, &le32(2));
  push_vec(&mut body, &query);
  push_vec(&mut body, &selector);
  let d = msg(2004, 21, 0, body);
  var ok = msg_ok(d);
  if !ok { return assert(false, "OP_QUERY layout"); }
  if m_field_i32(d, 0) != 2004 { ok = false; }
  if m_field_i32(d, 1) != 4 { ok = false; }
  if !bytes_equal(m_ns(d), ab("db.coll")) { ok = false; }
  if m_field_i32(d, 2) != 1 { ok = false; }
  if m_field_i32(d, 3) != 2 { ok = false; }
  if m_doc_count(d) != 2 { ok = false; }
  if m_doc_key_int(d, 0, "x") != 1 { ok = false; }
  if m_doc_key_int(d, 1, "y") != 2 { ok = false; }
  if m_field_i32(d, 11) != d.len() { ok = false; }
  if str_compare(mongo_opcode_name(2004), "OP_QUERY") != 0 { ok = false; }
  // Query only (no selector).
  var body2 = Vec[UInt8].new();
  push_vec(&mut body2, &le32(0));
  push_vec(&mut body2, &cstr("db.coll"));
  push_vec(&mut body2, &le32(0));
  push_vec(&mut body2, &le32(0));
  push_vec(&mut body2, &query);
  let d2 = msg(2004, 22, 0, body2);
  if !msg_ok(d2) { ok = false; }
  if m_doc_count(d2) != 1 { ok = false; }
  // Trailing bytes after the query.
  var body3 = Vec[UInt8].new();
  push_vec(&mut body3, &le32(0));
  push_vec(&mut body3, &cstr("db.coll"));
  push_vec(&mut body3, &le32(0));
  push_vec(&mut body3, &le32(0));
  push_vec(&mut body3, &query);
  body3.push(255 as UInt8);
  let trail_at = 20 + 8 + 8 + query.len();
  if !msg_err_is(msg(2004, 23, 0, body3), "mongo: trailing bytes at " + ist(trail_at)) { ok = false; }
  // Empty namespace.
  var body4 = Vec[UInt8].new();
  push_vec(&mut body4, &le32(0));
  body4.push(0 as UInt8);
  push_vec(&mut body4, &le32(0));
  push_vec(&mut body4, &le32(0));
  push_vec(&mut body4, &query);
  if !msg_err_is(msg(2004, 24, 0, body4), "mongo: empty namespace at 20") { ok = false; }
  // Unterminated namespace.
  var body5 = Vec[UInt8].new();
  push_vec(&mut body5, &le32(0));
  push_vec(&mut body5, &fill_bytes(6, 65));
  if !msg_err_is(msg(2004, 25, 0, body5), "mongo: unterminated namespace at 20") { ok = false; }
  return assert(ok, "OP_QUERY layout");
}

fn t17() -> TestResult {
  var d1p = Vec[Vec[UInt8]].new();
  d1p.push(i32_el("a", 10));
  let doc1 = doc(d1p);
  var d2p = Vec[Vec[UInt8]].new();
  d2p.push(str_el("b", "bb"));
  let doc2 = doc(d2p);
  var body = Vec[UInt8].new();
  push_vec(&mut body, &le32(8));
  push_vec(&mut body, &le64(1234605616436508552));
  push_vec(&mut body, &le32(1));
  push_vec(&mut body, &le32(2));
  push_vec(&mut body, &doc1);
  push_vec(&mut body, &doc2);
  let d = msg(1, 31, 9, body);
  var ok = msg_ok(d);
  if !ok { return assert(false, "OP_REPLY layout and count errors"); }
  if m_field_i32(d, 0) != 1 { ok = false; }
  if m_field_i32(d, 1) != 8 { ok = false; }
  if m_field_i32(d, 14) != 1234605616436508552 { ok = false; }
  if m_field_i32(d, 4) != 1 { ok = false; }
  if m_field_i32(d, 5) != 2 { ok = false; }
  if m_doc_count(d) != 2 { ok = false; }
  if m_doc_key_int(d, 0, "a") != 10 { ok = false; }
  if !bytes_equal(m_doc_key_bytes(d, 1, "b"), ab("bb")) { ok = false; }
  if str_compare(mongo_opcode_name(1), "OP_REPLY") != 0 { ok = false; }
  // numberReturned too large.
  var bad = Vec[UInt8].new();
  push_vec(&mut bad, &le32(0));
  push_vec(&mut bad, &le64(0));
  push_vec(&mut bad, &le32(0));
  push_vec(&mut bad, &le32(3));
  push_vec(&mut bad, &doc1);
  push_vec(&mut bad, &doc2);
  let bad_at = 16 + 20 + doc1.len() + doc2.len();
  if !msg_err_is(msg(1, 32, 0, bad), "mongo: truncated document at " + ist(bad_at)) { ok = false; }
  // Trailing bytes when numberReturned is smaller.
  var fewer = Vec[UInt8].new();
  push_vec(&mut fewer, &le32(0));
  push_vec(&mut fewer, &le64(0));
  push_vec(&mut fewer, &le32(0));
  push_vec(&mut fewer, &le32(1));
  push_vec(&mut fewer, &doc1);
  push_vec(&mut fewer, &doc2);
  let trail_at = 16 + 20 + doc1.len();
  if !msg_err_is(msg(1, 33, 0, fewer), "mongo: trailing bytes at " + ist(trail_at)) { ok = false; }
  return assert(ok, "OP_REPLY layout and count errors");
}

fn t18() -> TestResult {
  var d1p = Vec[Vec[UInt8]].new();
  d1p.push(i32_el("a", 1));
  let doc1 = doc(d1p);
  var d2p = Vec[Vec[UInt8]].new();
  d2p.push(i32_el("b", 2));
  let doc2 = doc(d2p);
  var body = Vec[UInt8].new();
  push_vec(&mut body, &le32(16));
  push_vec(&mut body, &cstr("db.coll"));
  push_vec(&mut body, &doc1);
  push_vec(&mut body, &doc2);
  let d = msg(2002, 41, 0, body);
  var ok = msg_ok(d);
  if !ok { return assert(false, "OP_INSERT layout"); }
  if m_field_i32(d, 0) != 2002 { ok = false; }
  if m_field_i32(d, 1) != 16 { ok = false; }
  if !bytes_equal(m_ns(d), ab("db.coll")) { ok = false; }
  if m_doc_count(d) != 2 { ok = false; }
  if m_doc_key_int(d, 0, "a") != 1 { ok = false; }
  if m_doc_key_int(d, 1, "b") != 2 { ok = false; }
  if str_compare(mongo_opcode_name(2002), "OP_INSERT") != 0 { ok = false; }
  // No documents.
  var empty = Vec[UInt8].new();
  push_vec(&mut empty, &le32(0));
  push_vec(&mut empty, &cstr("db.coll"));
  if !msg_err_is(msg(2002, 42, 0, empty), "mongo: missing insert documents at 28") { ok = false; }
  return assert(ok, "OP_INSERT layout");
}

fn t19() -> TestResult {
  var selp = Vec[Vec[UInt8]].new();
  selp.push(i32_el("k", 3));
  let selector = doc(selp);
  var updp = Vec[Vec[UInt8]].new();
  updp.push(i32_el("n", 4));
  let update = doc(updp);
  var body = Vec[UInt8].new();
  push_vec(&mut body, &le32(0));
  push_vec(&mut body, &cstr("db.coll"));
  push_vec(&mut body, &le32(2));
  push_vec(&mut body, &selector);
  push_vec(&mut body, &update);
  let d = msg(2001, 51, 0, body);
  var ok = msg_ok(d);
  if !ok { return assert(false, "OP_UPDATE and OP_DELETE layout"); }
  if m_field_i32(d, 0) != 2001 { ok = false; }
  if m_field_i32(d, 6) != 0 { ok = false; }
  if m_field_i32(d, 1) != 2 { ok = false; }
  if m_doc_count(d) != 2 { ok = false; }
  if m_doc_key_int(d, 0, "k") != 3 { ok = false; }
  if m_doc_key_int(d, 1, "n") != 4 { ok = false; }
  // OP_DELETE with the same selector.
  var body2 = Vec[UInt8].new();
  push_vec(&mut body2, &le32(0));
  push_vec(&mut body2, &cstr("db.coll"));
  push_vec(&mut body2, &le32(2));
  push_vec(&mut body2, &selector);
  let d2 = msg(2006, 52, 0, body2);
  if !msg_ok(d2) { ok = false; }
  if m_field_i32(d2, 0) != 2006 { ok = false; }
  if m_doc_count(d2) != 1 { ok = false; }
  if m_doc_key_int(d2, 0, "k") != 3 { ok = false; }
  // Non-zero ZERO field.
  var bad = Vec[UInt8].new();
  push_vec(&mut bad, &le32(1));
  push_vec(&mut bad, &cstr("db.coll"));
  push_vec(&mut bad, &le32(0));
  push_vec(&mut bad, &selector);
  if !msg_err_is(msg(2006, 53, 0, bad), "mongo: bad zero field 1 at 16") { ok = false; }
  if !msg_err_is(msg(2005, 54, 0, bad), "mongo: bad zero field 1 at 16") { ok = false; }
  return assert(ok, "OP_UPDATE and OP_DELETE layout");
}

fn t20() -> TestResult {
  // OP_GET_MORE.
  var body = Vec[UInt8].new();
  push_vec(&mut body, &le32(0));
  push_vec(&mut body, &cstr("db.coll"));
  push_vec(&mut body, &le32(0));
  push_vec(&mut body, &le64(-1));
  let d = msg(2005, 61, 0, body);
  var ok = msg_ok(d);
  if !ok { return assert(false, "OP_GET_MORE and OP_KILL_CURSORS layout"); }
  if m_field_i32(d, 0) != 2005 { ok = false; }
  if m_field_i32(d, 3) != 0 { ok = false; }
  if m_field_i32(d, 14) != -1 { ok = false; }
  if !bytes_equal(m_ns(d), ab("db.coll")) { ok = false; }
  // OP_KILL_CURSORS.
  var body2 = Vec[UInt8].new();
  push_vec(&mut body2, &le32(0));
  push_vec(&mut body2, &le32(2));
  push_vec(&mut body2, &le64(5));
  push_vec(&mut body2, &le64(-7));
  let d2 = msg(2007, 62, 0, body2);
  if !msg_ok(d2) { ok = false; }
  if m_field_i32(d2, 0) != 2007 { ok = false; }
  if m_field_i32(d2, 7) != 2 { ok = false; }
  if m_cursor_at(d2, 0) != 5 { ok = false; }
  if m_cursor_at(d2, 1) != -7 { ok = false; }
  if m_cursor_at(d2, 2) != -1 { ok = false; }
  // Cursor count exceeds the body.
  var body3 = Vec[UInt8].new();
  push_vec(&mut body3, &le32(0));
  push_vec(&mut body3, &le32(3));
  push_vec(&mut body3, &le64(5));
  push_vec(&mut body3, &le64(-7));
  if !msg_err_is(msg(2007, 63, 0, body3), "mongo: truncated cursor ids at 24") { ok = false; }
  return assert(ok, "OP_GET_MORE and OP_KILL_CURSORS layout");
}

fn t21() -> TestResult {
  var body = Vec[UInt8].new();
  push_vec(&mut body, &le32(2013));
  push_vec(&mut body, &le32(100));
  body.push(0 as UInt8);
  push_vec(&mut body, &hb("01020304"));
  let d = msg(2012, 71, 0, body);
  var ok = msg_ok(d);
  if !ok { return assert(false, "OP_COMPRESSED layout"); }
  if m_field_i32(d, 0) != 2012 { ok = false; }
  if m_field_i32(d, 8) != 2013 { ok = false; }
  if m_field_i32(d, 9) != 100 { ok = false; }
  if m_field_i32(d, 10) != 0 { ok = false; }
  if !bytes_equal(m_payload(d), hb("01020304")) { ok = false; }
  if m_doc_count(d) != 0 { ok = false; }
  if str_compare(mongo_opcode_name(2012), "OP_COMPRESSED") != 0 { ok = false; }
  // Short header (payload byte missing).
  var short_body = Vec[UInt8].new();
  push_vec(&mut short_body, &le32(2013));
  push_vec(&mut short_body, &le32(100));
  if !msg_err_is(msg(2012, 72, 0, short_body), "mongo: truncated op_compressed header at 16") { ok = false; }
  // Negative uncompressed size.
  var neg_body = Vec[UInt8].new();
  push_vec(&mut neg_body, &le32(2013));
  push_vec(&mut neg_body, &le32(-1));
  neg_body.push(0 as UInt8);
  if !msg_err_is(msg(2012, 73, 0, neg_body), "mongo: bad uncompressed size -1 at 20") { ok = false; }
  return assert(ok, "OP_COMPRESSED layout");
}

fn t22() -> TestResult {
  var p1 = Vec[Vec[UInt8]].new();
  p1.push(i32_el("x", 1));
  var s1 = Vec[Vec[UInt8]].new();
  s1.push(sec0(doc(p1)));
  let m1 = msg(2013, 100, 0, opmsg_body(0, s1));
  var s3 = Vec[Vec[UInt8]].new();
  s3.push(sec0(doc(p1)));
  let m2 = msg(2013, 101, 0, opmsg_body(0, s3));
  let stream = concat2(m1, m2);
  var ok = true;
  let r1 = mongo_parse_message(stream);
  if !r1.is_ok { ok = false; }
  if ok {
    let mm: MongoMsg = r1.value;
    if mongo_msg_consumed(&mm) != m1.len() { ok = false; }
    if mongo_msg_request_id(&mm) != 100 { ok = false; }
  }
  let rest = slice_bytes(stream, m1.len(), stream.len());
  if !msg_ok(rest) { ok = false; }
  if m_field_i32(rest, 12) != 101 { ok = false; }
  if m_doc_key_int(rest, 0, "x") != 1 { ok = false; }
  return assert(ok, "message consumed count and concatenated stream");
}

fn t23() -> TestResult {
  // Exact offsets in BSON errors.
  var ok = err_is(hb("080000001078000100"), "bson: truncated element at 4");
  let bad_doc_len = concat3(le32(9), hb("0a6100"), hb("00ff"));
  if !err_is(bad_doc_len, "bson: bad document length at 0") { ok = false; }
  // Exact offsets in message errors.
  var body = Vec[UInt8].new();
  push_vec(&mut body, &le32(0));
  body.push(3 as UInt8);
  if !msg_err_is(msg(2013, 91, 0, body), "mongo: unknown section kind 3 at 20") { ok = false; }
  var body2 = Vec[UInt8].new();
  push_vec(&mut body2, &le32(0));
  body2.push(1 as UInt8);
  push_vec(&mut body2, &le32(9));
  push_vec(&mut body2, &cstr("d"));
  push_vec(&mut body2, &hb("0c0000001078000100000000"));
  if !msg_err_is(msg(2013, 92, 0, body2), "mongo: bad section size 9 at 20") { ok = false; }
  // Truncated document inside a message keeps the bson prefix and offset.
  var insert_body = Vec[UInt8].new();
  push_vec(&mut insert_body, &le32(0));
  push_vec(&mut insert_body, &cstr("db.c"));
  push_vec(&mut insert_body, &le32(40));
  if !msg_err_is(msg(2002, 93, 0, insert_body), "bson: truncated document at 25") { ok = false; }
  return assert(ok, "exact byte-offset error messages");
}

fn main() -> Int {
  io.println("=== xiom.mongo conformance tests ===");
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
    io.println("xiom.mongo: all tests passed");
  } else {
    io.println("xiom.mongo: tests failed");
  }
  return failed;
}
