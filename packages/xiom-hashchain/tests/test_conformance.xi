// XIOM -- xiom.hashchain conformance tests (20 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Covers: the empty chain, the genesis rule (32 zero prev bytes), append and
// chain_from_payloads round-trips, pinned SHA-256 digest vectors computed
// independently with .NET SHA-256 (empty payload, "abc", the 55/56/64-byte
// padding boundaries, a three-block linked chain), digest size 32,
// determinism (append-built vs from_payloads-built), structural invariants
// with pinned messages, payload/digest/prev tampering detected at the FIRST
// broken index, payload reordering, whole-block reordering, empty payloads,
// traversal accessors, hex rendering, and the construction details (domain
// separator and length-prefixed preimage).
//
// The test module never shares a hash implementation with the library: every
// expected digest below is pinned from ground truth computed outside XIOM
// with .NET SHA-256. All Str equality goes through
// compare.str_compare on typed locals (BUG 17 discipline); Vec[Int] reads are
// bound to typed locals; every UInt8 read is widened with (x as Int) & 0xFF.
//
// Ground truth (preimage = ASCII("xiom.hashchain.v1.block") || prev(32) ||
// uint64_be(payload.len()) || payload, computed with .NET SHA256):
//   prev = 32 zero bytes, payload ""       -> 3ffa10c4...b57af
//   prev = 32 zero bytes, payload "abc"    -> ae4bc409...9f183
//   prev = digest above, payload "def"     -> c0163411...bd559
//   prev = 32 zero bytes, payload "genesis"-> ce7325cb...60753c
//   prev = 32 zero bytes, payload 55 x "a" -> 48557b1a...c0fe6
//   prev = 32 zero bytes, payload 56 x "a" -> be6bd486...91a16
//   prev = 32 zero bytes, payload 64 x "a" -> b296aa77...5f694
//   chain "aaa" -> d0, then "bbb" -> d1, then "ccc" -> d2 (see constants)

module hashchain_tests
use xiom.io; use xiom.test; use xiom.hashchain;
use xiom.string; use xiom.string.compare;

// --------------------------------------------------
//  Pinned vectors (computed outside XIOM with .NET SHA256)
// --------------------------------------------------

const V_EMPTY: Str = "3ffa10c4a3b2f48a1ddfb40e296ec65eeec931c7076bf52e0072dbf5303b57af";
const V_ABC: Str = "ae4bc4096045e1b295a1d769dbb71f60d53bb4d66374b97ce76e2de27e59f183";
const V_CHAIN1: Str = "c0163411c394af33960b11a4273d4861b5f269f14fa78068e5db39ade20bd559";
const V_GENESIS: Str = "ce7325cbe2e110fb8384fd8be8571eb1325a3e2ab8bd4928a49280917760753c";
const V55: Str = "48557b1a8a96c9ebeacb31bbde4b85ede278f59c982ad675bc93bbabf5fc0fe6";
const V56: Str = "be6bd486bbe767f64d9452de87cc58a973a06809e8cf16991ebcdfdb16891a16";
const V64: Str = "b296aa774b1540e37c97f5201efe90065f8df973cd039d121d059ed8a3f5f694";
const D0: Str = "fab461d274f2bb69de398dc40de4f4e24f757b859cca19643002a6f049d9b96d";
const D1: Str = "4e62d047f32b13c602fa414203792d9005e47dec18f375b74b3e563baf71ed54";
const D2: Str = "9f8232e7010f8c3446bf9704c0a3a5c7cbf27cc903116b60becb00567e5ee684";
const E2: Str = "c8c83cf986ba8fc779886ed1651eecac8cf03376499db7d3a98757c9831fb920";
const V_HELLO: Str = "bf91594452f406ff578a1b82c4a9c53cf393a498368e905a48e5330ef217db92";
const V_ABCD_E: Str = "2d71165abb6d6549d04d501c37578db178bc0b626d9b676e0906d198d6415b82";
const V_DDD: Str = "77d08800b505567fb3d40c6ca718253ecbb62fcdd32ea6a328e0bc854d285632";
const W_ABC_LEN2: Str = "dc8f4b2e65bacfad6b7962557ea8694fe82de691a2f2a2eba401e75be4b689d7";
const N_ABC: Str = "8a295b0cbf1f5a594280696ad7707164e2b8beb0e614ad52bc7d78ff8ac12a82";

// --------------------------------------------------
//  Result and byte helpers
// --------------------------------------------------

fn str_is(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn err_bool_is(r: Result[Bool, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  let got = r.error;
  return str_is(got, want);
}

fn err_int_is(r: Result[Int, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  let got = r.error;
  return str_is(got, want);
}

fn err_bytes_is(r: Result[Vec[UInt8], Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  let got = r.error;
  return str_is(got, want);
}

fn err_chain_is(r: Result[HashChain, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  let got = r.error;
  return str_is(got, want);
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

fn repeat_char(ch: Str, n: Int) -> Str {
  var out = "";
  var i = 0;
  while i < n {
    out = out + ch;
    i = i + 1;
  }
  return out;
}

fn repeat_bytes(b: Int, n: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < n {
    v.push(b as UInt8);
    i = i + 1;
  }
  return v;
}

fn zeros(n: Int) -> Vec[UInt8] {
  return repeat_bytes(0, n);
}

fn bytes_equal(a: Vec[UInt8], b: Vec[UInt8]) -> Bool {
  if a.len() != b.len() {
    return false;
  }
  var i = 0;
  while i < a.len() {
    let x = (a[i] as Int) & 0xFF;
    let y = (b[i] as Int) & 0xFF;
    if x != y {
      return false;
    }
    i = i + 1;
  }
  return true;
}

fn cat(a: Vec[UInt8], b: Vec[UInt8]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < a.len() {
    out.push(a[i]);
    i = i + 1;
  }
  i = 0;
  while i < b.len() {
    out.push(b[i]);
    i = i + 1;
  }
  return out;
}

// Copy of `v` with byte `pos` replaced.
fn set_byte(v: Vec[UInt8], pos: Int, b: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < v.len() {
    if i == pos {
      out.push(b as UInt8);
    } else {
      out.push(v[i]);
    }
    i = i + 1;
  }
  return out;
}

fn slice_bytes(v: Vec[UInt8], start: Int, end: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = start;
  while i < end {
    out.push(v[i]);
    i = i + 1;
  }
  return out;
}

fn hex_digit_value(ch: Str) -> Int {
  let c = (string.byte_at(ch, 0) as Int) & 0xFF;
  if c >= 48 {
    if c <= 57 {
      return c - 48;
    }
  }
  return c - 87;
}

fn hex_to_bytes(s: Str) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i + 1 < s.len() {
    let hi = hex_digit_value(string.str_slice(s, i, i + 1));
    let lo = hex_digit_value(string.str_slice(s, i + 1, i + 2));
    v.push((hi * 16 + lo) as UInt8);
    i = i + 2;
  }
  return v;
}

fn hex_is(buf: Vec[UInt8], want: Str) -> Bool {
  let got = chain_hex(&buf);
  return str_is(got, want);
}

// --------------------------------------------------
//  Digest access helpers (module calls, results unwrapped)
// --------------------------------------------------


fn compute_digest_of(prev: Vec[UInt8], payload: Vec[UInt8]) -> Vec[UInt8] {
  let r = chain_compute_digest(&prev, &payload);
  if r.is_ok { return r.value; }
  return Vec[UInt8].new();
}

fn compute_hex(prev: Vec[UInt8], payload: Vec[UInt8]) -> Str {
  let d = compute_digest_of(prev, payload);
  return chain_hex(&d);
}

// --------------------------------------------------
//  Module unwrap helpers
// --------------------------------------------------

fn digest_at(c: &HashChain, i: Int) -> Vec[UInt8] {
  let r = chain_block_digest(c, i);
  if r.is_ok { return r.value; }
  return Vec[UInt8].new();
}

fn prev_at(c: &HashChain, i: Int) -> Vec[UInt8] {
  let r = chain_block_prev(c, i);
  if r.is_ok { return r.value; }
  return Vec[UInt8].new();
}

fn payload_at(c: &HashChain, i: Int) -> Vec[UInt8] {
  let r = chain_block_payload(c, i);
  if r.is_ok { return r.value; }
  return Vec[UInt8].new();
}

fn len_at(c: &HashChain, i: Int) -> Int {
  let r = chain_block_len(c, i);
  if r.is_ok { return r.value; }
  return -1;
}

fn tip_index_of(c: &HashChain) -> Int {
  let r = chain_tip_index(c);
  if r.is_ok { return r.value; }
  return -1;
}

fn tip_digest_of(c: &HashChain) -> Vec[UInt8] {
  let r = chain_tip_digest(c);
  if r.is_ok { return r.value; }
  return Vec[UInt8].new();
}

fn verifies(c: &HashChain) -> Bool {
  let r = chain_verify(c);
  if !r.is_ok { return false; }
  return r.value;
}

fn verify_err(c: &HashChain, want: Str) -> Bool {
  let r = chain_verify(c);
  if r.is_ok { return false; }
  let got = r.error;
  return str_is(got, want);
}

fn chain_literal(count: Int, offsets: Vec[Int], payload: Vec[UInt8], prevs: Vec[UInt8], digests: Vec[UInt8]) -> HashChain {
  return HashChain{ count: count; payload_offsets: offsets; payload_bytes: payload; prev_digests: prevs; digests: digests };
}

fn from_payloads_of(data: Vec[UInt8], offsets: Vec[Int]) -> HashChain {
  let r = chain_from_payloads(&data, &offsets);
  if r.is_ok { return r.value; }
  return chain_new();
}

fn build3_append() -> HashChain {
  let a = bytes_of("aaa");
  let b = bytes_of("bbb");
  let c = bytes_of("ccc");
  let c0 = chain_new();
  let c1 = chain_append(&c0, &a);
  let c2 = chain_append(&c1, &b);
  return chain_append(&c2, &c);
}

fn build3_flat() -> HashChain {
  let data = bytes_of("aaabbbccc");
  var offs = Vec[Int].new();
  offs.push(0);
  offs.push(3);
  offs.push(6);
  offs.push(9);
  return from_payloads_of(data, offs);
}

fn all_digests_equal(a: &HashChain, b: &HashChain) -> Bool {
  if chain_len(a) != chain_len(b) { return false; }
  var i = 0;
  while i < chain_len(a) {
    if !bytes_equal(digest_at(a, i), digest_at(b, i)) { return false; }
    i = i + 1;
  }
  return true;
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  let c = chain_new();
  var ok = chain_len(&c) == 0;
  if !chain_is_empty(&c) { ok = false; }
  if c.count != 0 { ok = false; }
  let ol = c.payload_offsets.len();
  if ol != 1 { ok = false; }
  let first = c.payload_offsets[0];
  if first != 0 { ok = false; }
  if c.payload_bytes.len() != 0 { ok = false; }
  if c.prev_digests.len() != 0 { ok = false; }
  if c.digests.len() != 0 { ok = false; }
  if !verifies(&c) { ok = false; }
  let bp = chain_block_payload(&c, 0);
  if !err_bytes_is(bp, "hashchain: block index 0 out of range (chain is empty)") { ok = false; }
  let ti = chain_tip_index(&c);
  if !err_int_is(ti, "hashchain: chain has no tip (count 0)") { ok = false; }
  let td = chain_tip_digest(&c);
  if !err_bytes_is(td, "hashchain: chain has no tip (count 0)") { ok = false; }
  let no_payload = bytes_of("");
  let ix = chain_index_of(&c, &no_payload);
  if ix != -1 { ok = false; }
  return assert(ok, "empty chain: shape, verify Ok(true), accessors report no blocks");
}

fn t2() -> TestResult {
  let c0 = chain_new();
  let g = bytes_of("genesis");
  let c = chain_append(&c0, &g);
  var ok = chain_len(&c) == 1;
  if chain_is_empty(&c) { ok = false; }
  if !bytes_equal(prev_at(&c, 0), zeros(32)) { ok = false; }
  if !hex_is(digest_at(&c, 0), V_GENESIS) { ok = false; }
  if !verifies(&c) { ok = false; }
  if !hex_is(compute_digest_of(zeros(32), g), V_GENESIS) { ok = false; }
  return assert(ok, "genesis block: zero prev digest, pinned digest, verify Ok");
}

fn t3() -> TestResult {
  let c0 = chain_new();
  let p = bytes_of("hello chain");
  let c = chain_append(&c0, &p);
  var ok = chain_digest_size() == 32;
  if chain_len(&c) != 1 { ok = false; }
  if digest_at(&c, 0).len() != 32 { ok = false; }
  if tip_index_of(&c) != 0 { ok = false; }
  if !bytes_equal(tip_digest_of(&c), digest_at(&c, 0)) { ok = false; }
  if !hex_is(digest_at(&c, 0), V_HELLO) { ok = false; }
  if !verifies(&c) { ok = false; }
  return assert(ok, "one-block chain: append/verify round-trip, digest size 32");
}

fn t4() -> TestResult {
  let c = build3_append();
  var ok = chain_len(&c) == 3;
  if !bytes_equal(prev_at(&c, 0), zeros(32)) { ok = false; }
  if !bytes_equal(prev_at(&c, 1), digest_at(&c, 0)) { ok = false; }
  if !bytes_equal(prev_at(&c, 2), digest_at(&c, 1)) { ok = false; }
  if !hex_is(digest_at(&c, 0), D0) { ok = false; }
  if !hex_is(digest_at(&c, 1), D1) { ok = false; }
  if !hex_is(digest_at(&c, 2), D2) { ok = false; }
  if tip_index_of(&c) != 2 { ok = false; }
  if !bytes_equal(tip_digest_of(&c), digest_at(&c, 2)) { ok = false; }
  if !verifies(&c) { ok = false; }
  return assert(ok, "three-block chain: prev links, pinned digests, tip accessors");
}

fn t5() -> TestResult {
  var ok = str_is(compute_hex(zeros(32), bytes_of("")), V_EMPTY);
  if !str_is(compute_hex(zeros(32), bytes_of("abc")), V_ABC) { ok = false; }
  if !str_is(compute_hex(hex_to_bytes(V_ABC), bytes_of("def")), V_CHAIN1) { ok = false; }
  if !str_is(compute_hex(zeros(32), bytes_of(repeat_char("a", 55))), V55) { ok = false; }
  if !str_is(compute_hex(zeros(32), bytes_of(repeat_char("a", 56))), V56) { ok = false; }
  if !str_is(compute_hex(zeros(32), bytes_of(repeat_char("a", 64))), V64) { ok = false; }
  if compute_digest_of(zeros(32), bytes_of("abc")).len() != 32 { ok = false; }
  return assert(ok, "pinned SHA-256 vectors: empty, abc, linked def, 55/56/64-byte padding");
}

fn t6() -> TestResult {
  let a = build3_append();
  let b = build3_flat();
  var ok = all_digests_equal(&a, &b);
  if !verifies(&a) { ok = false; }
  if !verifies(&b) { ok = false; }
  let c = build3_flat();
  if !all_digests_equal(&a, &c) { ok = false; }
  var i = 0;
  while i < 3 {
    if !bytes_equal(payload_at(&a, i), payload_at(&b, i)) { ok = false; }
    i = i + 1;
  }
  return assert(ok, "determinism: append-built and from_payloads-built chains are identical");
}

fn t7() -> TestResult {
  let base = build3_append();
  let pay = base.payload_bytes;
  let pay2 = set_byte(pay, 4, 120);
  let offs = base.payload_offsets;
  let pvs = base.prev_digests;
  let dgs = base.digests;
  let c = chain_literal(3, offs, pay2, pvs, dgs);
  return assert(verify_err(&c, "hashchain: block 1 digest mismatch (payload or stored digest tampered)"), "tampered payload is detected at block 1");
}

fn t8() -> TestResult {
  let base = build3_append();
  let pay2 = set_byte(base.payload_bytes, 0, 120);
  let dgs2 = set_byte(base.digests, 2 * 32 + 5, 200);
  let offs = base.payload_offsets;
  let pvs = base.prev_digests;
  let c = chain_literal(3, offs, pay2, pvs, dgs2);
  return assert(verify_err(&c, "hashchain: block 0 digest mismatch (payload or stored digest tampered)"), "first broken index wins: block 0 reported even with block 2 damage");
}

fn t9() -> TestResult {
  let base = build3_append();
  let d2 = set_byte(base.digests, 2 * 32 + 5, 200);
  let offs = base.payload_offsets;
  let pay = base.payload_bytes;
  let pvs = base.prev_digests;
  let c2 = chain_literal(3, offs, pay, pvs, d2);
  var ok = verify_err(&c2, "hashchain: block 2 digest mismatch (payload or stored digest tampered)");
  let d0 = set_byte(base.digests, 3, 0);
  let offs2 = base.payload_offsets;
  let pay2 = base.payload_bytes;
  let pvs2 = base.prev_digests;
  let c0 = chain_literal(3, offs2, pay2, pvs2, d0);
  if !verify_err(&c0, "hashchain: block 0 digest mismatch (payload or stored digest tampered)") { ok = false; }
  return assert(ok, "tampered stored digests are detected at their own index");
}

fn t10() -> TestResult {
  let base = build3_append();
  let pv1 = set_byte(base.prev_digests, 32, 1);
  let offs = base.payload_offsets;
  let pay = base.payload_bytes;
  let dgs = base.digests;
  let c1 = chain_literal(3, offs, pay, pv1, dgs);
  var ok = verify_err(&c1, "hashchain: block 1 prev link broken (prev digest mismatch)");
  let pv0 = repeat_bytes(171, 32);
  let pv0full = cat(pv0, cat(digest_at(&base, 0), digest_at(&base, 1)));
  let offs2 = base.payload_offsets;
  let pay2 = base.payload_bytes;
  let dgs2 = base.digests;
  let c0 = chain_literal(3, offs2, pay2, pv0full, dgs2);
  if !verify_err(&c0, "hashchain: block 0 prev digest must be the 32 zero bytes (genesis rule)") { ok = false; }
  return assert(ok, "prev tamper: link break at block 1; nonzero genesis prev caught by the genesis rule");
}

fn t11() -> TestResult {
  let base = build3_append();
  var pay = base.payload_bytes;
  pay = set_byte(pay, 0, 99);
  pay = set_byte(pay, 1, 99);
  pay = set_byte(pay, 2, 99);
  pay = set_byte(pay, 6, 97);
  pay = set_byte(pay, 7, 97);
  pay = set_byte(pay, 8, 97);
  let offs = base.payload_offsets;
  let pvs = base.prev_digests;
  let dgs = base.digests;
  let c = chain_literal(3, offs, pay, pvs, dgs);
  var ok = verify_err(&c, "hashchain: block 0 digest mismatch (payload or stored digest tampered)");
  var pay2 = base.payload_bytes;
  pay2 = set_byte(pay2, 3, 99);
  pay2 = set_byte(pay2, 4, 99);
  pay2 = set_byte(pay2, 5, 99);
  pay2 = set_byte(pay2, 6, 98);
  pay2 = set_byte(pay2, 7, 98);
  pay2 = set_byte(pay2, 8, 98);
  let offs2 = base.payload_offsets;
  let pvs2 = base.prev_digests;
  let dgs2 = base.digests;
  let c2 = chain_literal(3, offs2, pay2, pvs2, dgs2);
  if !verify_err(&c2, "hashchain: block 1 digest mismatch (payload or stored digest tampered)") { ok = false; }
  return assert(ok, "reordered payloads: first swapped payload position reported");
}

fn t12() -> TestResult {
  let base = build3_append();
  let z = zeros(32);
  let pv_swapped = cat(z, cat(digest_at(&base, 1), digest_at(&base, 0)));
  let dg_swapped = cat(digest_at(&base, 0), cat(digest_at(&base, 2), digest_at(&base, 1)));
  let offs = base.payload_offsets;
  let pay = base.payload_bytes;
  let c = chain_literal(3, offs, pay, pv_swapped, dg_swapped);
  var ok = verify_err(&c, "hashchain: block 1 prev link broken (prev digest mismatch)");
  let pv01 = cat(digest_at(&base, 0), cat(z, digest_at(&base, 1)));
  let dg01 = cat(digest_at(&base, 1), cat(digest_at(&base, 0), digest_at(&base, 2)));
  let offs2 = base.payload_offsets;
  let pay2 = base.payload_bytes;
  let c2 = chain_literal(3, offs2, pay2, pv01, dg01);
  if !verify_err(&c2, "hashchain: block 0 prev digest must be the 32 zero bytes (genesis rule)") { ok = false; }
  return assert(ok, "whole-block reordering: links break at the first moved block");
}

fn t13() -> TestResult {
  let c = build3_flat();
  var ok = verifies(&c);
  let e = bytes_of("");
  var offs_empty = Vec[Int].new();
  let r1 = chain_from_payloads(&e, &offs_empty);
  if !err_chain_is(r1, "hashchain: payload_offsets must be non-empty") { ok = false; }
  let d3 = bytes_of("abc");
  var offs1 = Vec[Int].new();
  offs1.push(1);
  offs1.push(3);
  let r2 = chain_from_payloads(&d3, &offs1);
  if !err_chain_is(r2, "hashchain: payload_offsets[0] must be 0 (got 1)") { ok = false; }
  let d1 = bytes_of("a");
  var offs2 = Vec[Int].new();
  offs2.push(0);
  offs2.push(2);
  offs2.push(1);
  let r3 = chain_from_payloads(&d1, &offs2);
  if !err_chain_is(r3, "hashchain: payload_offsets[2]=1 is below payload_offsets[1]=2") { ok = false; }
  let d4 = bytes_of("abcd");
  var offs3 = Vec[Int].new();
  offs3.push(0);
  offs3.push(3);
  let r4 = chain_from_payloads(&d4, &offs3);
  if !err_chain_is(r4, "hashchain: payload_offsets[1]=3 must equal payload bytes length 4") { ok = false; }
  var offs4 = Vec[Int].new();
  offs4.push(0);
  let r5 = chain_from_payloads(&e, &offs4);
  if !r5.is_ok { ok = false; }
  let ec = from_payloads_of(e, offs4);
  if chain_len(&ec) != 0 { ok = false; }
  if !verifies(&ec) { ok = false; }
  return assert(ok, "from_payloads: round-trip plus the pinned offset error catalog");
}

fn t14() -> TestResult {
  let data = bytes_of("abcd");
  var offs = Vec[Int].new();
  offs.push(0);
  offs.push(0);
  offs.push(4);
  offs.push(4);
  let c = from_payloads_of(data, offs);
  var ok = chain_len(&c) == 3;
  if !verifies(&c) { ok = false; }
  if len_at(&c, 0) != 0 { ok = false; }
  if len_at(&c, 1) != 4 { ok = false; }
  if len_at(&c, 2) != 0 { ok = false; }
  if !bytes_equal(payload_at(&c, 1), bytes_of("abcd")) { ok = false; }
  if !hex_is(digest_at(&c, 0), V_EMPTY) { ok = false; }
  if !hex_is(digest_at(&c, 2), E2) { ok = false; }
  if !hex_is(digest_at(&c, 1), V_ABCD_E) { ok = false; }
  let no_payload = bytes_of("");
  let abcd_p = bytes_of("abcd");
  if chain_index_of(&c, &no_payload) != 0 { ok = false; }
  if chain_index_of(&c, &abcd_p) != 1 { ok = false; }
  return assert(ok, "empty payloads are legal and keep the links intact");
}

fn t15() -> TestResult {
  let c = build3_append();
  var ok = chain_len(&c) == 3;
  if len_at(&c, 0) != 3 { ok = false; }
  if !bytes_equal(payload_at(&c, 1), bytes_of("bbb")) { ok = false; }
  let bbb_p = bytes_of("bbb");
  let zzz_p = bytes_of("zzz");
  let no_payload = bytes_of("");
  if chain_index_of(&c, &bbb_p) != 1 { ok = false; }
  if chain_index_of(&c, &zzz_p) != -1 { ok = false; }
  if chain_index_of(&c, &no_payload) != -1 { ok = false; }
  let r3 = chain_block_digest(&c, 3);
  if !err_bytes_is(r3, "hashchain: block index 3 out of range 0..2 (count 3)") { ok = false; }
  let rm1 = chain_block_digest(&c, -1);
  if !err_bytes_is(rm1, "hashchain: block index -1 out of range 0..2 (count 3)") { ok = false; }
  let rp = chain_block_payload(&c, 3);
  if !err_bytes_is(rp, "hashchain: block index 3 out of range 0..2 (count 3)") { ok = false; }
  let rl = chain_block_len(&c, 3);
  if !err_int_is(rl, "hashchain: block index 3 out of range 0..2 (count 3)") { ok = false; }
  let bad_prev = bytes_of("x");
  let abc_p = bytes_of("abc");
  let rw = chain_compute_digest(&abc_p, &bad_prev);
  if !err_bytes_is(rw, "hashchain: prev digest must be 32 bytes (got 3)") { ok = false; }
  return assert(ok, "traversal accessors and out-of-range errors are precise");
}

fn t16() -> TestResult {
  let d3 = bytes_of("abc");
  var o1 = Vec[Int].new();
  o1.push(0);
  o1.push(3);
  var z1 = zeros(32);
  let short_dg = slice_bytes(hex_to_bytes(V_ABC), 0, 10);
  let c1 = chain_literal(1, o1, d3, z1, short_dg);
  var ok = verify_err(&c1, "hashchain: digests length 10 must equal count * 32 = 32");
  let d3b = bytes_of("abc");
  var o2 = Vec[Int].new();
  o2.push(0);
  o2.push(3);
  let dg2 = hex_to_bytes(V_ABC);
  let z2 = slice_bytes(zeros(32), 0, 3);
  let c2 = chain_literal(1, o2, d3b, z2, dg2);
  if !verify_err(&c2, "hashchain: prev_digests length 3 must equal count * 32 = 32") { ok = false; }
  let d3c = bytes_of("abc");
  var o3 = Vec[Int].new();
  o3.push(0);
  o3.push(3);
  o3.push(9);
  let z3 = zeros(32);
  let dg3 = hex_to_bytes(V_ABC);
  let c3 = chain_literal(1, o3, d3c, z3, dg3);
  if !verify_err(&c3, "hashchain: payload_offsets length 3 must equal count + 1 = 2") { ok = false; }
  var o4 = Vec[Int].new();
  o4.push(0);
  let e0 = bytes_of("");
  let z4 = Vec[UInt8].new();
  let dg4 = Vec[UInt8].new();
  let c4 = chain_literal(-1, o4, e0, z4, dg4);
  if !verify_err(&c4, "hashchain: chain count -1 is negative") { ok = false; }
  let d3x = bytes_of("abc");
  var o5 = Vec[Int].new();
  o5.push(0);
  o5.push(2);
  let z5 = zeros(32);
  let dg5 = hex_to_bytes(V_ABC);
  let c5 = chain_literal(1, o5, d3x, z5, dg5);
  if !verify_err(&c5, "hashchain: payload_offsets[1]=2 must equal payload bytes length 3") { ok = false; }
  let d3d = bytes_of("abc");
  var o6 = Vec[Int].new();
  o6.push(1);
  o6.push(3);
  let z6 = zeros(32);
  let dg6 = hex_to_bytes(V_ABC);
  let c6 = chain_literal(1, o6, d3d, z6, dg6);
  if !verify_err(&c6, "hashchain: payload_offsets[0] must be 0 (got 1)") { ok = false; }
  return assert(ok, "structural invariants: length, count and offset problems are named");
}

fn t17() -> TestResult {
  let empty = Vec[UInt8].new();
  var ok = str_is(chain_hex(&empty), "");
  if !hex_is(bytes_of("abc"), "616263") { ok = false; }
  var b80 = Vec[UInt8].new();
  b80.push(128 as UInt8);
  if !hex_is(b80, "80") { ok = false; }
  var bff = Vec[UInt8].new();
  bff.push(255 as UInt8);
  if !hex_is(bff, "ff") { ok = false; }
  let c = build3_append();
  if !hex_is(digest_at(&c, 0), D0) { ok = false; }
  return assert(ok, "hex rendering: lowercase, empty, and high-bit bytes");
}

fn t18() -> TestResult {
  let c0 = chain_new();
  let p55 = bytes_of(repeat_char("a", 55));
  let c55 = chain_append(&c0, &p55);
  var ok = hex_is(digest_at(&c55, 0), V55);
  if !verifies(&c55) { ok = false; }
  let c1 = chain_new();
  let p56 = bytes_of(repeat_char("a", 56));
  let c56 = chain_append(&c1, &p56);
  if !hex_is(digest_at(&c56, 0), V56) { ok = false; }
  if !verifies(&c56) { ok = false; }
  let c2 = chain_new();
  let p64 = bytes_of(repeat_char("a", 64));
  let c64 = chain_append(&c2, &p64);
  if !hex_is(digest_at(&c64, 0), V64) { ok = false; }
  if !verifies(&c64) { ok = false; }
  return assert(ok, "SHA-256 padding boundaries 55/56/64 bytes hold through chain_append");
}

fn t19() -> TestResult {
  let z = zeros(32);
  let p = bytes_of("abc");
  let d = compute_digest_of(z, p);
  var ok = str_is(chain_hex(&d), V_ABC);
  if str_is(chain_hex(&d), W_ABC_LEN2) { ok = false; }
  if str_is(chain_hex(&d), N_ABC) { ok = false; }
  return assert(ok, "digest construction: domain separator and length prefix are hashed (pinned)");
}

fn t20() -> TestResult {
  let base = build3_append();
  let len_before = chain_len(&base);
  let d0_before = digest_at(&base, 0);
  let p = bytes_of("ddd");
  let grown = chain_append(&base, &p);
  var ok = chain_len(&base) == len_before;
  if !bytes_equal(digest_at(&base, 0), d0_before) { ok = false; }
  if chain_len(&grown) != 4 { ok = false; }
  if !bytes_equal(payload_at(&grown, 3), p) { ok = false; }
  if !bytes_equal(prev_at(&grown, 3), digest_at(&grown, 2)) { ok = false; }
  if !hex_is(digest_at(&grown, 3), V_DDD) { ok = false; }
  if !verifies(&grown) { ok = false; }
  let empty_p = bytes_of("");
  let grown2 = chain_append(&grown, &empty_p);
  if chain_len(&grown2) != 5 { ok = false; }
  if !verifies(&grown2) { ok = false; }
  return assert(ok, "append returns a new chain: input untouched, growth links and verifies");
}

fn main() -> Int {
  io.println("=== xiom.hashchain conformance tests ===");
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
    io.println("xiom.hashchain: all tests passed");
  } else {
    io.println("xiom.hashchain: tests failed");
  }
  return failed;
}
