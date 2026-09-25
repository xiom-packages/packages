// XIOM -- xiom.bech32 conformance tests (20 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Covers the documented API against the pinned BIP-173 and BIP-350 test
// vectors (valid and invalid), the 90-character limit, HRP rules, mixed-case
// rejection with uppercase folding, variant detection and the
// "bech32: wrong variant" distinction, the 8->5 / 5->8 convertbits
// directions with their padding rules, canonical lowercase emission,
// round-trips and the accessors.
//
// All Str equality goes through str_compare (BUG 17 discipline: `==` on Str
// values read from a Vec lowers to a pointer comparison). Expected byte
// vectors are built with the stdlib xiom.encoding.hex decoder, independent
// of the module under test; the pinned Bech32/Bech32m strings are copied
// from the BIP-173 / BIP-350 test-vector sections and were cross-checked
// against a reference polymod implementation before being pinned here.
//
// Result payloads are bound to a local before any reference is taken
// (v0.61.3 reads an empty Vec through a direct Result-payload reference).

module bech32_tests
use xiom.io; use xiom.test; use xiom.bech32;
use xiom.string; use xiom.string.compare;
use xiom.string.builder; use xiom.encoding.hex;

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

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
    if (((a[i] as Int) & 0xFF) != ((b[i] as Int) & 0xFF)) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

fn ints_equal(a: Vec[Int], b: Vec[Int]) -> Bool {
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

// Inclusive range lo..hi.
fn ints_range(lo: Int, hi: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  var i = lo;
  while i <= hi {
    v.push(i);
    i = i + 1;
  }
  return v;
}

// Inclusive descending range hi..lo.
fn ints_desc(hi: Int, lo: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  var i = hi;
  while i >= lo {
    v.push(i);
    i = i - 1;
  }
  return v;
}

fn ints_rep(n: Int, value: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  var i = 0;
  while i < n {
    v.push(value);
    i = i + 1;
  }
  return v;
}

// Test-local alphabet mapping (a literal copy of the BIP-173 table, not the
// module's bech32_charset); -1 for a character outside the alphabet.
fn ints_of_str(s: Str) -> Vec[Int] {
  let cset = "qpzry9x8gf2tvdw0s3jn54khce6mua7l";
  var out = Vec[Int].new();
  var i = 0;
  while i < s.len() {
    let b = (string.byte_at(s, i) as Int) & 0xFF;
    var j = 0;
    var found = -1;
    while j < 32 {
      if (((string.byte_at(cset, j) as Int) & 0xFF) == b) {
        found = j;
        break;
      }
      j = j + 1;
    }
    out.push(found);
    i = i + 1;
  }
  return out;
}

fn prepend(v: Int, rest: Vec[Int]) -> Vec[Int] {
  var out = Vec[Int].new();
  out.push(v);
  var i = 0;
  while i < rest.len() {
    out.push(rest[i]);
    i = i + 1;
  }
  return out;
}

fn drop_first(v: Vec[Int]) -> Vec[Int] {
  var out = Vec[Int].new();
  var i = 1;
  while i < v.len() {
    out.push(v[i]);
    i = i + 1;
  }
  return out;
}

// Deterministic byte sequence of length n (covers 0 and bytes >= 0x80).
fn seq_bytes(n: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < n {
    v.push(((i * 37 + 7) % 256) as UInt8);
    i = i + 1;
  }
  return v;
}

fn str_prefixed_byte(b: Int, suffix: Str) -> Str {
  var sb = Vec[UInt8].new();
  builder.sb_push_byte(&mut sb, b as UInt8);
  builder.sb_push_str(&mut sb, suffix);
  return builder.sb_to_str(&sb);
}

fn str_suffixed_byte(prefix: Str, b: Int) -> Str {
  var sb = Vec[UInt8].new();
  builder.sb_push_str(&mut sb, prefix);
  builder.sb_push_byte(&mut sb, b as UInt8);
  return builder.sb_to_str(&sb);
}

// True when r is Err with exactly the message `want`.
fn dec_err_is(r: Result[Bech32, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return streq(r.error, want);
}

fn str_err_is(r: Result[Str, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return streq(r.error, want);
}

fn ints_err_is(r: Result[Vec[Int], Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return streq(r.error, want);
}

fn bytes_err_is(r: Result[Vec[UInt8], Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return streq(r.error, want);
}

// Result of bech32_decode is Ok with (hrp, variant, data.len()) as wanted.
fn dec_is(s: Str, want_hrp: Str, want_variant: Int, want_len: Int) -> Bool {
  let r = bech32_decode(s);
  if !r.is_ok {
    return false;
  }
  let d = r.value;
  if !streq(d.hrp, want_hrp) {
    return false;
  }
  if d.variant != want_variant {
    return false;
  }
  return d.data.len() == want_len;
}

// Result of bech32_decode_variant is Ok with the wanted fields.
fn dec_variant_is(s: Str, want_variant: Int, want_hrp: Str, want_len: Int) -> Bool {
  let r = bech32_decode_variant(s, want_variant);
  if !r.is_ok {
    return false;
  }
  let d = r.value;
  if !streq(d.hrp, want_hrp) {
    return false;
  }
  if d.variant != want_variant {
    return false;
  }
  return d.data.len() == want_len;
}

fn dec_payload_is(s: Str, want: Vec[Int]) -> Bool {
  let r = bech32_decode(s);
  if !r.is_ok {
    return false;
  }
  let d = r.value;
  return ints_equal(d.data, want);
}

// encode(hrp, data, variant) is Ok and exactly `want`.
fn enc_is(hrp: Str, data: Vec[Int], variant: Int, want: Str) -> Bool {
  let r = bech32_encode(hrp, &data, variant);
  if !r.is_ok {
    return false;
  }
  return streq(r.value, want);
}

// decode -> encode reproduces the canonical (lowercase) form `want`.
fn reencode_is(s: Str, want: Str) -> Bool {
  let r = bech32_decode(s);
  if !r.is_ok {
    return false;
  }
  let d = r.value;
  let enc = bech32_encode(d.hrp, &d.data, d.variant);
  if !enc.is_ok {
    return false;
  }
  return streq(enc.value, want);
}

fn t1() -> TestResult {
  var ok = streq(bech32_charset(), "qpzry9x8gf2tvdw0s3jn54khce6mua7l");
  if bech32_charset().len() != 32 { ok = false; }
  if BECH32_VARIANT_BECH32 != 0 { ok = false; }
  if BECH32_VARIANT_BECH32M != 1 { ok = false; }
  var i = 0;
  while i < 32 {
    var j = i + 1;
    while j < 32 {
      let a = (string.byte_at(bech32_charset(), i) as Int) & 0xFF;
      let b = (string.byte_at(bech32_charset(), j) as Int) & 0xFF;
      if a == b { ok = false; }
      j = j + 1;
    }
    i = i + 1;
  }
  return assert(ok, "charset is the BIP-173 table, unique, 32 characters");
}

fn t2() -> TestResult {
  var ok = dec_is("A12UEL5L", "a", BECH32_VARIANT_BECH32, 0);
  if !dec_is("a12uel5l", "a", BECH32_VARIANT_BECH32, 0) { ok = false; }
  if !dec_is("an83characterlonghumanreadablepartthatcontainsthenumber1andtheexcludedcharactersbio1tt5tgs", "an83characterlonghumanreadablepartthatcontainsthenumber1andtheexcludedcharactersbio", BECH32_VARIANT_BECH32, 0) { ok = false; }
  if !dec_is("abcdef1qpzry9x8gf2tvdw0s3jn54khce6mua7lmqqqxw", "abcdef", BECH32_VARIANT_BECH32, 32) { ok = false; }
  if !dec_is("11qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqc8247j", "1", BECH32_VARIANT_BECH32, 82) { ok = false; }
  if !dec_is("split1checkupstagehandshakeupstreamerranterredcaperred2y9e3w", "split", BECH32_VARIANT_BECH32, 48) { ok = false; }
  if !dec_is("?1ezyfcl", "?", BECH32_VARIANT_BECH32, 0) { ok = false; }
  if !dec_payload_is("abcdef1qpzry9x8gf2tvdw0s3jn54khce6mua7lmqqqxw", ints_range(0, 31)) { ok = false; }
  if !dec_payload_is("11qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqc8247j", ints_rep(82, 0)) { ok = false; }
  return assert(ok, "BIP-173 valid vectors decode as Bech32 with pinned fields");
}

fn t3() -> TestResult {
  var ok = dec_is("A1LQFN3A", "a", BECH32_VARIANT_BECH32M, 0);
  if !dec_is("a1lqfn3a", "a", BECH32_VARIANT_BECH32M, 0) { ok = false; }
  if !dec_is("an83characterlonghumanreadablepartthatcontainsthetheexcludedcharactersbioandnumber11sg7hg6", "an83characterlonghumanreadablepartthatcontainsthetheexcludedcharactersbioandnumber1", BECH32_VARIANT_BECH32M, 0) { ok = false; }
  if !dec_is("abcdef1l7aum6echk45nj3s0wdvt2fg8x9yrzpqzd3ryx", "abcdef", BECH32_VARIANT_BECH32M, 32) { ok = false; }
  if !dec_is("11llllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllludsr8", "1", BECH32_VARIANT_BECH32M, 82) { ok = false; }
  if !dec_is("split1checkupstagehandshakeupstreamerranterredcaperredlc445v", "split", BECH32_VARIANT_BECH32M, 48) { ok = false; }
  if !dec_is("?1v759aa", "?", BECH32_VARIANT_BECH32M, 0) { ok = false; }
  if !dec_payload_is("abcdef1l7aum6echk45nj3s0wdvt2fg8x9yrzpqzd3ryx", ints_desc(31, 0)) { ok = false; }
  if !dec_payload_is("11llllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllludsr8", ints_rep(82, 31)) { ok = false; }
  return assert(ok, "BIP-350 valid vectors decode as Bech32m with pinned fields");
}

fn t4() -> TestResult {
  var ok = reencode_is("A12UEL5L", "a12uel5l");
  if !reencode_is("a12uel5l", "a12uel5l") { ok = false; }
  if !reencode_is("an83characterlonghumanreadablepartthatcontainsthenumber1andtheexcludedcharactersbio1tt5tgs", "an83characterlonghumanreadablepartthatcontainsthenumber1andtheexcludedcharactersbio1tt5tgs") { ok = false; }
  if !reencode_is("abcdef1qpzry9x8gf2tvdw0s3jn54khce6mua7lmqqqxw", "abcdef1qpzry9x8gf2tvdw0s3jn54khce6mua7lmqqqxw") { ok = false; }
  if !reencode_is("11qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqc8247j", "11qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqc8247j") { ok = false; }
  if !reencode_is("split1checkupstagehandshakeupstreamerranterredcaperred2y9e3w", "split1checkupstagehandshakeupstreamerranterredcaperred2y9e3w") { ok = false; }
  if !reencode_is("?1ezyfcl", "?1ezyfcl") { ok = false; }
  if !reencode_is("A1LQFN3A", "a1lqfn3a") { ok = false; }
  if !reencode_is("a1lqfn3a", "a1lqfn3a") { ok = false; }
  if !reencode_is("an83characterlonghumanreadablepartthatcontainsthetheexcludedcharactersbioandnumber11sg7hg6", "an83characterlonghumanreadablepartthatcontainsthetheexcludedcharactersbioandnumber11sg7hg6") { ok = false; }
  if !reencode_is("abcdef1l7aum6echk45nj3s0wdvt2fg8x9yrzpqzd3ryx", "abcdef1l7aum6echk45nj3s0wdvt2fg8x9yrzpqzd3ryx") { ok = false; }
  if !reencode_is("11llllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllludsr8", "11llllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllludsr8") { ok = false; }
  if !reencode_is("split1checkupstagehandshakeupstreamerranterredcaperredlc445v", "split1checkupstagehandshakeupstreamerranterredcaperredlc445v") { ok = false; }
  if !reencode_is("?1v759aa", "?1v759aa") { ok = false; }
  return assert(ok, "all 14 valid vectors re-encode to their canonical lowercase form");
}

fn t5() -> TestResult {
  var ok = enc_is("a", Vec[Int].new(), BECH32_VARIANT_BECH32, "a12uel5l");
  if !enc_is("a", Vec[Int].new(), BECH32_VARIANT_BECH32M, "a1lqfn3a") { ok = false; }
  if !enc_is("?", Vec[Int].new(), BECH32_VARIANT_BECH32, "?1ezyfcl") { ok = false; }
  if !enc_is("?", Vec[Int].new(), BECH32_VARIANT_BECH32M, "?1v759aa") { ok = false; }
  if !enc_is("abcdef", ints_range(0, 31), BECH32_VARIANT_BECH32, "abcdef1qpzry9x8gf2tvdw0s3jn54khce6mua7lmqqqxw") { ok = false; }
  if !enc_is("abcdef", ints_desc(31, 0), BECH32_VARIANT_BECH32M, "abcdef1l7aum6echk45nj3s0wdvt2fg8x9yrzpqzd3ryx") { ok = false; }
  if !enc_is("1", ints_rep(82, 0), BECH32_VARIANT_BECH32, "11qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqc8247j") { ok = false; }
  if !enc_is("1", ints_rep(82, 31), BECH32_VARIANT_BECH32M, "11llllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllludsr8") { ok = false; }
  let split_payload = ints_of_str("checkupstagehandshakeupstreamerranterredcaperred");
  if !enc_is("split", split_payload, BECH32_VARIANT_BECH32, "split1checkupstagehandshakeupstreamerranterredcaperred2y9e3w") { ok = false; }
  let split_payload_m = ints_of_str("checkupstagehandshakeupstreamerranterredcaperred");
  if !enc_is("split", split_payload_m, BECH32_VARIANT_BECH32M, "split1checkupstagehandshakeupstreamerranterredcaperredlc445v") { ok = false; }
  return assert(ok, "pinned encodes reproduce the BIP-173 / BIP-350 vectors");
}

fn t6() -> TestResult {
  var ok = dec_err_is(bech32_decode(" 1nwldj5"), "bech32: invalid hrp character");
  if !dec_err_is(bech32_decode(str_prefixed_byte(0x7F, "1axkwrx")), "bech32: invalid hrp character") { ok = false; }
  if !dec_err_is(bech32_decode(str_prefixed_byte(0x80, "1eym55h")), "bech32: invalid hrp character") { ok = false; }
  if !dec_err_is(bech32_decode("an84characterslonghumanreadablepartthatcontainsthenumber1andtheexcludedcharactersbio1569pvx"), "bech32: bad length") { ok = false; }
  if !dec_err_is(bech32_decode("pzry9x0s0muk"), "bech32: missing separator") { ok = false; }
  if !dec_err_is(bech32_decode("1pzry9x0s0muk"), "bech32: missing separator") { ok = false; }
  if !dec_err_is(bech32_decode("x1b4n0q5v"), "bech32: invalid data character") { ok = false; }
  if !dec_err_is(bech32_decode("li1dgmt3"), "bech32: bad length") { ok = false; }
  if !dec_err_is(bech32_decode(str_suffixed_byte("de1lg7wt", 0xFF)), "bech32: invalid data character") { ok = false; }
  if !dec_err_is(bech32_decode("A1G7SGD8"), "bech32: bad checksum") { ok = false; }
  if !dec_err_is(bech32_decode("10a06t8"), "bech32: bad length") { ok = false; }
  if !dec_err_is(bech32_decode("1qzzfhee"), "bech32: missing separator") { ok = false; }
  return assert(ok, "BIP-173 invalid vectors map to the documented error catalog");
}

fn t7() -> TestResult {
  var ok = dec_err_is(bech32_decode(" 1xj0phk"), "bech32: invalid hrp character");
  if !dec_err_is(bech32_decode(str_prefixed_byte(0x80, "1vctc34")), "bech32: invalid hrp character") { ok = false; }
  if !dec_err_is(bech32_decode("an84characterslonghumanreadablepartthatcontainsthetheexcludedcharactersbioandnumber11d6pts4"), "bech32: bad length") { ok = false; }
  if !dec_err_is(bech32_decode("qyrz8wqd2c9m"), "bech32: missing separator") { ok = false; }
  if !dec_err_is(bech32_decode("1qyrz8wqd2c9m"), "bech32: missing separator") { ok = false; }
  if !dec_err_is(bech32_decode("y1b0jsk6g"), "bech32: invalid data character") { ok = false; }
  if !dec_err_is(bech32_decode("lt1igcx5c0"), "bech32: invalid data character") { ok = false; }
  if !dec_err_is(bech32_decode("in1muywd"), "bech32: bad length") { ok = false; }
  if !dec_err_is(bech32_decode("mm1crxm3i"), "bech32: invalid data character") { ok = false; }
  if !dec_err_is(bech32_decode("au1s5cgom"), "bech32: invalid data character") { ok = false; }
  if !dec_err_is(bech32_decode("M1VUXWEZ"), "bech32: bad checksum") { ok = false; }
  if !dec_err_is(bech32_decode("16plkw9"), "bech32: bad length") { ok = false; }
  if !dec_err_is(bech32_decode("1p2gdwpf"), "bech32: missing separator") { ok = false; }
  return assert(ok, "BIP-350 invalid vectors map to the documented error catalog");
}

fn t8() -> TestResult {
  var ok = dec_is("A12UEL5L", "a", BECH32_VARIANT_BECH32, 0);
  if !dec_is("A1LQFN3A", "a", BECH32_VARIANT_BECH32M, 0) { ok = false; }
  if !dec_err_is(bech32_decode("A12uel5l"), "bech32: mixed case") { ok = false; }
  if !dec_err_is(bech32_decode("a12UEL5L"), "bech32: mixed case") { ok = false; }
  if !dec_err_is(bech32_decode("tb1p0xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7vq47Zagq"), "bech32: mixed case") { ok = false; }
  if !dec_err_is(bech32_decode("tb1qrp33g0q5c5txsp9arysrx4k6zdkfs4nce4xj0gdcccefvpysxf3q0sL5k7"), "bech32: mixed case") { ok = false; }
  if !dec_err_is(bech32_decode("Abcdef1qpzry9x8gf2tvdw0s3jn54khce6mua7lmqqqxw"), "bech32: mixed case") { ok = false; }
  return assert(ok, "mixed case is rejected, uppercase-only folds to lowercase");
}

fn t9() -> TestResult {
  var ok = dec_is("bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kemeawh", "bc", BECH32_VARIANT_BECH32M, 33);
  if !dec_is("bc1p0xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7vqh2y7hd", "bc", BECH32_VARIANT_BECH32, 53) { ok = false; }
  if !dec_err_is(bech32_decode_variant("bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kemeawh", BECH32_VARIANT_BECH32), "bech32: wrong variant") { ok = false; }
  if !dec_err_is(bech32_decode_variant("bc1p0xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7vqh2y7hd", BECH32_VARIANT_BECH32M), "bech32: wrong variant") { ok = false; }
  if !dec_err_is(bech32_decode_variant("A12UEL5L", BECH32_VARIANT_BECH32M), "bech32: wrong variant") { ok = false; }
  if !dec_err_is(bech32_decode_variant("A1LQFN3A", BECH32_VARIANT_BECH32), "bech32: wrong variant") { ok = false; }
  if !dec_variant_is("bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kemeawh", BECH32_VARIANT_BECH32M, "bc", 33) { ok = false; }
  if !dec_variant_is("bc1p0xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7vqh2y7hd", BECH32_VARIANT_BECH32, "bc", 53) { ok = false; }
  if !bech32_is_valid("bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kemeawh") { ok = false; }
  if !dec_err_is(bech32_decode_variant("a12uel5l", 2), "bech32: bad variant") { ok = false; }
  return assert(ok, "single-constant validation: wrong variant vs bad checksum");
}

fn t10() -> TestResult {
  var ok = bech32_is_valid("A12UEL5L");
  if !bech32_is_valid("a1lqfn3a") { ok = false; }
  if !bech32_is_valid("abcdef1qpzry9x8gf2tvdw0s3jn54khce6mua7lmqqqxw") { ok = false; }
  if !bech32_is_valid("abcdef1l7aum6echk45nj3s0wdvt2fg8x9yrzpqzd3ryx") { ok = false; }
  if !bech32_is_valid("11qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqc8247j") { ok = false; }
  if !bech32_is_valid("?1v759aa") { ok = false; }
  if bech32_is_valid("A12uel5l") { ok = false; }
  if bech32_is_valid("x1b4n0q5v") { ok = false; }
  if bech32_is_valid("A1G7SGD8") { ok = false; }
  if bech32_is_valid("M1VUXWEZ") { ok = false; }
  if bech32_is_valid("pzry9x0s0muk") { ok = false; }
  if bech32_is_valid("1pzry9x0s0muk") { ok = false; }
  if bech32_is_valid("") { ok = false; }
  if bech32_is_valid("A1") { ok = false; }
  return assert(ok, "bech32_is_valid mirrors bech32_decode on both vector sets");
}

fn t11() -> TestResult {
  let fb = hb("666f6f626172");
  let sym = bech32_bytes_to_symbols(&fb);
  var ok = true;
  var want = Vec[Int].new();
  want.push(12); want.push(25); want.push(23); want.push(22); want.push(30);
  want.push(24); want.push(19); want.push(1); want.push(14); want.push(8);
  if !ints_equal(sym, want) { ok = false; }
  if sym.len() != 10 { ok = false; }
  let empty = Vec[UInt8].new();
  if bech32_bytes_to_symbols(&empty).len() != 0 { ok = false; }
  let one = hb("ff");
  let one_sym = bech32_bytes_to_symbols(&one);
  var one_want = Vec[Int].new();
  one_want.push(31); one_want.push(28);
  if !ints_equal(one_sym, one_want) { ok = false; }
  let z = hb("0000");
  let z_sym = bech32_bytes_to_symbols(&z);
  if !ints_equal(z_sym, ints_rep(4, 0)) { ok = false; }
  return assert(ok, "8->5 conversion pads the trailing group with zero bits");
}

fn t12() -> TestResult {
  let r = bech32_symbols_to_bytes(&ints_range(0, 31));
  var ok = r.is_ok;
  if r.is_ok {
    if !bytes_equal(r.value, hb("00443214c74254b635cf84653a56d7c675be77df")) { ok = false; }
  }
  let fb = bech32_symbols_to_bytes(&ints_of_str("qg6pzg5z9lxwgv3h")); // 16 symbols -> 10 bytes
  if !fb.is_ok { ok = false; }
  if fb.is_ok {
    if !bytes_equal(fb.value, hb("02341122822fcce43237")) { ok = false; }
  }
  let empty = Vec[Int].new();
  let er = bech32_symbols_to_bytes(&empty);
  if !er.is_ok { ok = false; }
  if er.is_ok && er.value.len() != 0 { ok = false; }
  return assert(ok, "5->8 conversion reproduces pinned bytes");
}

fn t13() -> TestResult {
  var ok = true;
  var n = 0;
  while n <= 24 {
    let data = seq_bytes(n);
    let sym = bech32_bytes_to_symbols(&data);
    if sym.len() != ((n * 8 + 4) / 5) { ok = false; }
    let back = bech32_symbols_to_bytes(&sym);
    if !back.is_ok { ok = false; }
    if back.is_ok {
      if !bytes_equal(back.value, data) { ok = false; }
    }
    n = n + 1;
  }
  return assert(ok, "8->5->8 round-trips for 0..24 byte lengths");
}

fn t14() -> TestResult {
  let empty = Vec[Int].new();
  var ok = ints_err_is(bech32_convertbits(&empty, 0, 5, true), "bech32: invalid bits");
  if !ints_err_is(bech32_convertbits(&empty, 8, 0, true), "bech32: invalid bits") { ok = false; }
  if !ints_err_is(bech32_convertbits(&empty, 9, 5, true), "bech32: invalid bits") { ok = false; }
  if !ints_err_is(bech32_convertbits(&empty, 5, 9, false), "bech32: invalid bits") { ok = false; }
  var over = Vec[Int].new();
  over.push(32);
  if !ints_err_is(bech32_convertbits(&over, 5, 8, false), "bech32: convertbits overflow") { ok = false; }
  var neg = Vec[Int].new();
  neg.push(-1);
  if !ints_err_is(bech32_convertbits(&neg, 5, 8, false), "bech32: convertbits overflow") { ok = false; }
  var b256 = Vec[Int].new();
  b256.push(256);
  if !ints_err_is(bech32_convertbits(&b256, 8, 5, true), "bech32: convertbits overflow") { ok = false; }
  var one9 = Vec[Int].new();
  one9.push(1);
  if !bytes_err_is(bech32_symbols_to_bytes(&one9), "bech32: invalid padding") { ok = false; }
  var over_sym = Vec[Int].new();
  over_sym.push(32);
  if !bytes_err_is(bech32_symbols_to_bytes(&over_sym), "bech32: convertbits overflow") { ok = false; }
  if !ints_err_is(bech32_convertbits(&one9, 5, 8, false), "bech32: invalid padding") { ok = false; }
  return assert(ok, "convertbits reports invalid bits, overflow and invalid padding");
}

fn t15() -> TestResult {
  let empty = Vec[Int].new();
  var ok = ints_err_is(bech32_convertbits(&empty, 9, 9, true), "bech32: invalid bits");
  var one = Vec[Int].new();
  one.push(0);
  var p32 = Vec[Int].new();
  p32.push(32);
  var pneg = Vec[Int].new();
  pneg.push(-1);
  if !str_err_is(bech32_encode("", one, BECH32_VARIANT_BECH32), "bech32: invalid hrp length") { ok = false; }
  if !str_err_is(bech32_encode("BC", one, BECH32_VARIANT_BECH32), "bech32: mixed case") { ok = false; }
  if !str_err_is(bech32_encode("b c", one, BECH32_VARIANT_BECH32), "bech32: invalid hrp character") { ok = false; }
  if !str_err_is(bech32_encode(str_prefixed_byte(0x7F, "bc"), one, BECH32_VARIANT_BECH32), "bech32: invalid hrp character") { ok = false; }
  if !str_err_is(bech32_encode("bc", p32, BECH32_VARIANT_BECH32), "bech32: invalid data value") { ok = false; }
  if !str_err_is(bech32_encode("bc", pneg, BECH32_VARIANT_BECH32), "bech32: invalid data value") { ok = false; }
  if !str_err_is(bech32_encode("bc", one, 2), "bech32: bad variant") { ok = false; }
  if !str_err_is(bech32_encode("bc", one, -1), "bech32: bad variant") { ok = false; }
  return assert(ok, "encoder error catalog");
}

fn t16() -> TestResult {
  let long_hrp = "an83characterlonghumanreadablepartthatcontainsthenumber1andtheexcludedcharactersbio";
  var ok = long_hrp.len() == 83;
  if !enc_is(long_hrp, Vec[Int].new(), BECH32_VARIANT_BECH32, "an83characterlonghumanreadablepartthatcontainsthenumber1andtheexcludedcharactersbio1tt5tgs") { ok = false; }
  if !str_err_is(bech32_encode("an84characterslonghumanreadablepartthatcontainsthenumber1andtheexcludedcharactersbio", Vec[Int].new(), BECH32_VARIANT_BECH32), "bech32: invalid hrp length") { ok = false; }
  let one = Vec[Int].new();
  one.push(0);
  if !str_err_is(bech32_encode(long_hrp, one, BECH32_VARIANT_BECH32), "bech32: bad length") { ok = false; }
  if !str_err_is(bech32_encode(long_hrp, one, BECH32_VARIANT_BECH32M), "bech32: bad length") { ok = false; }
  if !dec_err_is(bech32_decode("A1"), "bech32: bad length") { ok = false; }
  if !dec_err_is(bech32_decode("a1"), "bech32: bad length") { ok = false; }
  return assert(ok, "90-character total limit and 83-character HRP limit");
}

fn t17() -> TestResult {
  var ok = dec_err_is(bech32_decode(str_prefixed_byte(0x20, "1nwldj5")), "bech32: invalid hrp character");
  if !dec_err_is(bech32_decode(str_prefixed_byte(0x7F, "1axkwrx")), "bech32: invalid hrp character") { ok = false; }
  if !dec_err_is(bech32_decode(str_prefixed_byte(0x80, "1vctc34")), "bech32: invalid hrp character") { ok = false; }
  if !dec_err_is(bech32_decode(str_suffixed_byte("de1lg7wt", 0xFF)), "bech32: invalid data character") { ok = false; }
  let built = str_suffixed_byte("de1lg7wt", 0xFF);
  if built.len() != 9 { ok = false; }
  if ((string.byte_at(built, 8) as Int) & 0xFF) != 255 { ok = false; }
  return assert(ok, "raw HRP bytes 0x20/0x7F/0x80 and data byte 0xFF are rejected");
}

fn enc_from_bytes_is(hrp: Str, hexstr: Str, version: Int, variant: Int, want: Str) -> Bool {
  let prog = hb(hexstr);
  let sym = bech32_bytes_to_symbols(&prog);
  let payload = prepend(version, sym);
  if payload.len() + hrp.len() + 7 > 90 { return false; }
  return enc_is(hrp, payload, variant, want);
}

fn dec_to_bytes_is(s: Str, want_hrp: Str, variant: Int, want_version: Int, hexstr: Str) -> Bool {
  let r = bech32_decode_variant(s, variant);
  if !r.is_ok { return false; }
  let d = r.value;
  if !streq(d.hrp, want_hrp) { return false; }
  if d.data.len() < 1 { return false; }
  let ver: Int = d.data[0];
  if ver != want_version { return false; }
  let rest = drop_first(d.data);
  let conv = bech32_symbols_to_bytes(&rest);
  if !conv.is_ok { return false; }
  return bytes_equal(conv.value, hb(hexstr));
}

fn t18() -> TestResult {
  var ok = enc_from_bytes_is("bc", "751e76e8199196d454941c45d1b3a323f1433bd6", 0, BECH32_VARIANT_BECH32, "bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4");
  if !enc_from_bytes_is("bc", "79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798", 1, BECH32_VARIANT_BECH32M, "bc1p0xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7vqzk5jj0") { ok = false; }
  if !enc_from_bytes_is("tb", "1863143c14c5166804bd19203356da136c985678cd4d27a1b8c6329604903262", 0, BECH32_VARIANT_BECH32, "tb1qrp33g0q5c5txsp9arysrx4k6zdkfs4nce4xj0gdcccefvpysxf3q0sl5k7") { ok = false; }
  if !dec_to_bytes_is("bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4", "bc", BECH32_VARIANT_BECH32, 0, "751e76e8199196d454941c45d1b3a323f1433bd6") { ok = false; }
  if !dec_to_bytes_is("bc1p0xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7vqzk5jj0", "bc", BECH32_VARIANT_BECH32M, 1, "79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798") { ok = false; }
  if !dec_to_bytes_is("tb1qrp33g0q5c5txsp9arysrx4k6zdkfs4nce4xj0gdcccefvpysxf3q0sl5k7", "tb", BECH32_VARIANT_BECH32, 0, "1863143c14c5166804bd19203356da136c985678cd4d27a1b8c6329604903262") { ok = false; }
  return assert(ok, "bech32/bech32m end-to-end pins from raw bytes to address and back");
}

fn t19() -> TestResult {
  let r = bech32_decode("abcdef1qpzry9x8gf2tvdw0s3jn54khce6mua7lmqqqxw");
  var ok = r.is_ok;
  if r.is_ok {
    let d = r.value;
    if !streq(bech32_hrp(&d), "abcdef") { ok = false; }
    if bech32_variant(&d) != BECH32_VARIANT_BECH32 { ok = false; }
    let data = bech32_data(&d);
    if !ints_equal(data, ints_range(0, 31)) { ok = false; }
  }
  let m = bech32_decode("abcdef1l7aum6echk45nj3s0wdvt2fg8x9yrzpqzd3ryx");
  if m.is_ok {
    let d2 = m.value;
    if !streq(bech32_hrp(&d2), "abcdef") { ok = false; }
    if bech32_variant(&d2) != BECH32_VARIANT_BECH32M { ok = false; }
    let data2 = bech32_data(&d2);
    if !ints_equal(data2, ints_desc(31, 0)) { ok = false; }
  } else {
    ok = false;
  }
  return assert(ok, "bech32_hrp / bech32_variant / bech32_data accessors");
}

fn t20() -> TestResult {
  var ok = true;
  var n = 0;
  while n <= 12 {
    let data = seq_bytes(n);
    let sym = bech32_bytes_to_symbols(&data);
    let e0 = bech32_encode("bc", &sym, BECH32_VARIANT_BECH32);
    let e1 = bech32_encode("bc", &sym, BECH32_VARIANT_BECH32M);
    if !e0.is_ok { ok = false; }
    if !e1.is_ok { ok = false; }
    if e0.is_ok {
      if e0.value.len() > 90 { ok = false; }
      let d0 = bech32_decode_variant(e0.value, BECH32_VARIANT_BECH32);
      if !d0.is_ok { ok = false; }
      if d0.is_ok {
        let v0 = d0.value;
        if !streq(v0.hrp, "bc") { ok = false; }
        if !ints_equal(v0.data, sym) { ok = false; }
        let back0 = bech32_symbols_to_bytes(&v0.data);
        if !back0.is_ok { ok = false; }
        if back0.is_ok {
          if !bytes_equal(back0.value, data) { ok = false; }
        }
      }
    }
    if e1.is_ok {
      let d1 = bech32_decode_variant(e1.value, BECH32_VARIANT_BECH32M);
      if !d1.is_ok { ok = false; }
      if d1.is_ok {
        let v1 = d1.value;
        if v1.variant != BECH32_VARIANT_BECH32M { ok = false; }
        let back1 = bech32_symbols_to_bytes(&v1.data);
        if !back1.is_ok { ok = false; }
        if back1.is_ok {
          if !bytes_equal(back1.value, data) { ok = false; }
        }
      }
    }
    n = n + 1;
  }
  return assert(ok, "full encode/decode round-trip for 0..12 bytes in both variants");
}

fn main() -> Int {
  io.println("=== xiom.bech32 conformance tests ===");
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
    io.println("xiom.bech32: all tests passed");
  } else {
    io.println("xiom.bech32: tests failed");
  }
  return failed;
}
