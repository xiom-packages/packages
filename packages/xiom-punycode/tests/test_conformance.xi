// XIOM -- xiom.punycode conformance tests (20 checks)
// Port task: prove the pure-XIOM xiom.punycode module against RFC 3492.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Covers the documented API: punycode_encode_label (RFC 3492 examples, ASCII
// passthrough, single/short non-ASCII labels, Greek and Cyrillic, invalid
// UTF-8), punycode_decode_label (RFC 3492 examples, case-insensitive digits,
// case-preserving basic section, invalid digits, truncated runs, overflow),
// punycode_to_ascii / punycode_to_unicode (xn-- prefix handling, empty labels,
// error propagation, domain round-trips) and punycode_is_ascii_label.
//
// All Str equality goes through str_compare: BUG 17 lowers `==` on Str values
// read from Vec[Str] elements to a pointer comparison, so every comparison
// below is routed through streq instead of `==`. Raw invalid bytes are built
// with Vec[UInt8] + Str::from_utf8, exactly as in the transliteration tests.

module punycode_tests
use xiom.io; use xiom.test; use xiom.punycode;
use xiom.string; use xiom.string.compare;

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// Str from one raw byte (for invalid UTF-8 source literals cannot spell).
fn str_of1(a: Int) -> Str {
  var v = Vec[UInt8].new();
  v.push(a as UInt8);
  return Str::from_utf8(v);
}

// Str from two raw bytes.
fn str_of2(a: Int, b: Int) -> Str {
  var v = Vec[UInt8].new();
  v.push(a as UInt8);
  v.push(b as UInt8);
  return Str::from_utf8(v);
}

// True when r is an Err whose message starts with "punycode: ".
fn str_err(r: Result[Str, Str]) -> Bool {
  if r.is_ok {
    return false;
  }
  let m: Str = r.error;
  if m.len() < 10 {
    return false;
  }
  return streq(string.str_slice(m, 0, 10), "punycode: ");
}

// True when punycode_encode_label(label) is Ok and equals `want`.
fn enc_is(label: Str, want: Str) -> Bool {
  let r = punycode_encode_label(label);
  if !r.is_ok {
    return false;
  }
  let v: Str = r.value;
  return streq(v, want);
}

// True when punycode_decode_label(label) is Ok and equals `want`.
fn dec_is(label: Str, want: Str) -> Bool {
  let r = punycode_decode_label(label);
  if !r.is_ok {
    return false;
  }
  let v: Str = r.value;
  return streq(v, want);
}

// True when punycode_to_ascii(domain) is Ok and equals `want`.
fn ascii_is(domain: Str, want: Str) -> Bool {
  let r = punycode_to_ascii(domain);
  if !r.is_ok {
    return false;
  }
  let v: Str = r.value;
  return streq(v, want);
}

// True when punycode_to_unicode(domain) is Ok and equals `want`.
fn unicode_is(domain: Str, want: Str) -> Bool {
  let r = punycode_to_unicode(domain);
  if !r.is_ok {
    return false;
  }
  let v: Str = r.value;
  return streq(v, want);
}

// True when label survives encode-then-decode unchanged.
fn rt(label: Str) -> Bool {
  let e = punycode_encode_label(label);
  if !e.is_ok {
    return false;
  }
  let ev: Str = e.value;
  let d = punycode_decode_label(ev);
  if !d.is_ok {
    return false;
  }
  let dv: Str = d.value;
  return streq(dv, label);
}

// True when a domain survives to_ascii-then-to_unicode unchanged.
fn dom_rt(domain: Str) -> Bool {
  let a = punycode_to_ascii(domain);
  if !a.is_ok {
    return false;
  }
  let av: Str = a.value;
  let u = punycode_to_unicode(av);
  if !u.is_ok {
    return false;
  }
  let uv: Str = u.value;
  return streq(uv, domain);
}

fn t1() -> TestResult {
  var ok = enc_is("bücher", "bcher-kva");
  if !enc_is("mañana", "maana-pta") { ok = false; }
  if !enc_is("例え", "r8jz45g") { ok = false; }
  if !enc_is("Δ", "swa") { ok = false; }
  return assert(ok, "encode: RFC 3492 examples (bucher, manana, CJK, delta)");
}

fn t2() -> TestResult {
  var ok = dec_is("bcher-kva", "bücher");
  if !dec_is("maana-pta", "mañana") { ok = false; }
  if !dec_is("r8jz45g", "例え") { ok = false; }
  if !dec_is("swa", "Δ") { ok = false; }
  return assert(ok, "decode: RFC 3492 examples (bucher, manana, CJK, delta)");
}

fn t3() -> TestResult {
  var ok = enc_is("", "");
  if !enc_is("hello", "hello") { ok = false; }
  if !enc_is("example.com", "example.com") { ok = false; }
  if !enc_is("xn--bcher-kva", "xn--bcher-kva") { ok = false; }
  if !enc_is("a-b-c-123", "a-b-c-123") { ok = false; }
  return assert(ok, "encode: all-ASCII labels return unchanged");
}

fn t4() -> TestResult {
  var ok = enc_is("ä", "4ca");
  if !enc_is("ü", "tda") { ok = false; }
  if !enc_is("Ü", "wca") { ok = false; }
  if !enc_is("café", "caf-dma") { ok = false; }
  if !enc_is("münchen", "mnchen-3ya") { ok = false; }
  return assert(ok, "encode: short non-ASCII labels (umlauts, cafe)");
}

fn t5() -> TestResult {
  var ok = punycode_is_ascii_label("");
  if !punycode_is_ascii_label("abc-123.xn--") { ok = false; }
  if punycode_is_ascii_label("bücher") { ok = false; }
  if punycode_is_ascii_label("Δ") { ok = false; }
  if punycode_is_ascii_label(str_of1(0xFF)) { ok = false; }
  if punycode_is_ascii_label(str_of1(0x80)) { ok = false; }
  return assert(ok, "is_ascii_label: true only when every byte is < 0x80");
}

fn t6() -> TestResult {
  var ok = ascii_is("münchen.de", "xn--mnchen-3ya.de");
  if !ascii_is("bücher.example", "xn--bcher-kva.example") { ok = false; }
  if !ascii_is("example.com", "example.com") { ok = false; }
  if !ascii_is("例え.example", "xn--r8jz45g.example") { ok = false; }
  return assert(ok, "to_ascii: non-ASCII labels gain xn--, ASCII labels pass");
}

fn t7() -> TestResult {
  var ok = unicode_is("xn--mnchen-3ya.de", "münchen.de");
  if !unicode_is("xn--bcher-kva.example", "bücher.example") { ok = false; }
  if !unicode_is("example.com", "example.com") { ok = false; }
  return assert(ok, "to_unicode: xn-- labels decode, ASCII labels pass");
}

fn t8() -> TestResult {
  var ok = unicode_is("XN--R8JZ45G", "例え");
  if !unicode_is("XN--SWA", "Δ") { ok = false; }
  if !unicode_is("Xn--R8jZ45g", "例え") { ok = false; }
  if !unicode_is("XN--BCHER-KVA.DE", "BüCHER.DE") { ok = false; }
  return assert(ok, "to_unicode: xn-- prefix and digits are case-insensitive");
}

fn t9() -> TestResult {
  var ok = ascii_is("", "");
  if !ascii_is("a..b", "a..b") { ok = false; }
  if !ascii_is("münchen..de", "xn--mnchen-3ya..de") { ok = false; }
  if !ascii_is("münchen.de.", "xn--mnchen-3ya.de.") { ok = false; }
  if !unicode_is("", "") { ok = false; }
  if !unicode_is("xn--mnchen-3ya..de", "münchen..de") { ok = false; }
  if !dec_is("", "") { ok = false; }
  return assert(ok, "empty labels are preserved in both directions");
}

fn t10() -> TestResult {
  var ok = str_err(punycode_decode_label("bcher-kv!"));
  if !str_err(punycode_decode_label("!!!")) { ok = false; }
  if !str_err(punycode_decode_label("a_b")) { ok = false; }
  if !str_err(punycode_decode_label("bcher kv")) { ok = false; }
  if !str_err(punycode_decode_label("bcher-kv.")) { ok = false; }
  if !str_err(punycode_decode_label("é")) { ok = false; }
  return assert(ok, "decode: bytes outside the digit alphabet are Err");
}

fn t11() -> TestResult {
  let zs: Str = string.str_repeat("z", 60);
  let nines: Str = string.str_repeat("9", 60);
  var ok = str_err(punycode_decode_label(zs));
  if !str_err(punycode_decode_label(nines)) { ok = false; }
  if !str_err(punycode_decode_label("bcher-" + zs)) { ok = false; }
  if !str_err(punycode_decode_label("a" + nines)) { ok = false; }
  return assert(ok, "decode: long digit runs overflow and are Err");
}

fn t12() -> TestResult {
  var ok = str_err(punycode_encode_label(str_of1(0xFF)));
  if !str_err(punycode_encode_label(str_of1(0x80))) { ok = false; }
  if !str_err(punycode_encode_label(str_of2(0xC3, 0x28))) { ok = false; }
  if !str_err(punycode_encode_label(str_of2(0xE2, 0x82))) { ok = false; }
  if !str_err(punycode_encode_label(str_of2(0xC0, 0xAF))) { ok = false; }
  return assert(ok, "encode: invalid UTF-8 is Err (stray, truncated, overlong)");
}

fn t13() -> TestResult {
  var ok = enc_is("ελλάδα", "hxakic4aa");
  if !dec_is("hxakic4aa", "ελλάδα") { ok = false; }
  if !rt("ελλάδα") { ok = false; }
  if !ascii_is("ελλάδα.gr", "xn--hxakic4aa.gr") { ok = false; }
  return assert(ok, "greek: ελλάδα round-trips through its pinned encoding");
}

fn t14() -> TestResult {
  var ok = enc_is("москва", "80adxhks");
  if !dec_is("80adxhks", "москва") { ok = false; }
  if !rt("москва") { ok = false; }
  if !ascii_is("москва.ru", "xn--80adxhks.ru") { ok = false; }
  return assert(ok, "cyrillic: москва round-trips through its pinned encoding");
}

fn t15() -> TestResult {
  var ok = rt("bücher");
  if !rt("münchen") { ok = false; }
  if !rt("mañana") { ok = false; }
  if !rt("例え") { ok = false; }
  if !rt("Δ") { ok = false; }
  return assert(ok, "dotless labels: encode then decode restores the label");
}

fn t16() -> TestResult {
  var ok = dom_rt("münchen.de");
  if !dom_rt("bücher.example") { ok = false; }
  if !dom_rt("例え.example") { ok = false; }
  if !dom_rt("ελλάδα.gr") { ok = false; }
  if !dom_rt("москва.ru") { ok = false; }
  if !dom_rt("café.fr") { ok = false; }
  return assert(ok, "domains: to_ascii then to_unicode restores the domain");
}

fn t17() -> TestResult {
  var ok = dec_is("BCHER-KVA", "BüCHER");
  if !dec_is("MNCHEN-3YA", "MüNCHEN") { ok = false; }
  if !dec_is("bcher-kva", "bücher") { ok = false; }
  return assert(ok, "decode: basic code points keep their original case");
}

fn t18() -> TestResult {
  var ok = str_err(punycode_to_ascii(str_of1(0xFF)));
  if !str_err(punycode_to_ascii(str_of2(0xC3, 0x28))) { ok = false; }
  if !str_err(punycode_to_ascii("ok." + str_of1(0xE9))) { ok = false; }
  if !str_err(punycode_to_unicode("xn--bcher-kv!")) { ok = false; }
  if !str_err(punycode_to_unicode("xn--!!!")) { ok = false; }
  return assert(ok, "domain functions propagate label errors as Err");
}

fn t19() -> TestResult {
  var ok = ascii_is("xn--r8jz45g.example", "xn--r8jz45g.example");
  if !unicode_is("bücher.example", "bücher.example") { ok = false; }
  if !ascii_is("xn--bcher-kva", "xn--bcher-kva") { ok = false; }
  if !unicode_is("xn--", "") { ok = false; }
  return assert(ok, "to_ascii never re-encodes; to_unicode leaves other labels alone");
}

fn t20() -> TestResult {
  var inputs = Vec[Str].new();
  inputs.push("bücher");
  inputs.push("mañana");
  inputs.push("例え");
  inputs.push("Δ");
  inputs.push("ελλάδα");
  inputs.push("москва");
  inputs.push("café");
  inputs.push("münchen");
  inputs.push("Ü");
  inputs.push("ä");
  var ok = true;
  var i = 0;
  while i < inputs.len() {
    let s: Str = inputs[i];
    if !rt(s) { ok = false; }
    i = i + 1;
  }
  return assert(ok, "round-trip batch: every pinned label survives encode/decode");
}

fn main() -> Int {
  io.println("=== xiom.punycode conformance tests ===");
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
    io.println("xiom.punycode: all tests passed");
  } else {
    io.println("xiom.punycode: tests failed");
  }
  return failed;
}
