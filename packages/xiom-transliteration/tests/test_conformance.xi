// XIOM -- xiom.transliteration conformance tests (20 checks)
// Port task: prove the pure-XIOM xiom.transliteration module against its
// documented rules (SPEC.md).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Covers the documented API: translit_is_ascii, translit_to_ascii (Latin-1
// and Latin Extended-A diacritics, Greek, Cyrillic, curly quotes, dashes,
// ellipsis, NBSP, unmapped codepoints dropped, invalid UTF-8 passthrough,
// empty input) and translit_slug (case folding, separator runs, edge dashes,
// punctuation-only input).
//
// All Str equality goes through str_compare: BUG 17 lowers `==` on Str
// values read from Vec[Str] elements to a pointer comparison, so every
// comparison below is routed through streq instead of `==`. Invalid and
// NBSP bytes are built with Vec[UInt8] + Str::from_utf8.

module transliteration_tests
use xiom.io; use xiom.test; use xiom.transliteration;
use xiom.string.compare;

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// Str from one raw byte (for invalid UTF-8 leads source literals cannot spell).
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

// Str from three raw bytes.
fn str_of3(a: Int, b: Int, c: Int) -> Str {
  var v = Vec[UInt8].new();
  v.push(a as UInt8);
  v.push(b as UInt8);
  v.push(c as UInt8);
  return Str::from_utf8(v);
}

fn t1() -> TestResult {
  var ok = translit_is_ascii("");
  if !translit_is_ascii("plain text 123!") { ok = false; }
  if translit_is_ascii("café") { ok = false; }
  if translit_is_ascii("Ελλάδα") { ok = false; }
  if translit_is_ascii("Москва") { ok = false; }
  if translit_is_ascii(str_of1(0xE9)) { ok = false; }
  if translit_is_ascii(str_of2(0xC3, 0xA9)) { ok = false; }
  return assert(ok, "is_ascii: true for ASCII, false for non-ASCII bytes");
}

fn t2() -> TestResult {
  var ok = streq(translit_to_ascii("café"), "cafe");
  if !streq(translit_to_ascii("Café au lait"), "Cafe au lait") { ok = false; }
  if !streq(translit_to_ascii("Ångström"), "Angstrom") { ok = false; }
  return assert(ok, "latin-1 accents: é->e, Å->A, ö->o");
}

fn t3() -> TestResult {
  var ok = streq(translit_to_ascii("Zürich"), "Zurich");
  if !streq(translit_to_ascii("über"), "uber") { ok = false; }
  if !streq(translit_to_ascii("München"), "Munchen") { ok = false; }
  return assert(ok, "latin-1 umlauts: ü->u");
}

fn t4() -> TestResult {
  var ok = streq(translit_to_ascii("niño"), "nino");
  if !streq(translit_to_ascii("España"), "Espana") { ok = false; }
  if !streq(translit_to_ascii("ça va"), "ca va") { ok = false; }
  if !streq(translit_to_ascii("Ç"), "C") { ok = false; }
  return assert(ok, "latin-1: ñ->n, ç->c");
}

fn t5() -> TestResult {
  var ok = streq(translit_to_ascii("æon"), "aeon");
  if !streq(translit_to_ascii("Æsir"), "AEsir") { ok = false; }
  if !streq(translit_to_ascii("œuvre"), "oeuvre") { ok = false; }
  if !streq(translit_to_ascii("Œuvre"), "OEuvre") { ok = false; }
  return assert(ok, "ligatures: æ->ae, œ->oe");
}

fn t6() -> TestResult {
  var ok = streq(translit_to_ascii("straße"), "strasse");
  if !streq(translit_to_ascii("Fußball"), "Fussball") { ok = false; }
  if !streq(translit_to_ascii("ß"), "ss") { ok = false; }
  return assert(ok, "sharp s: ß->ss");
}

fn t7() -> TestResult {
  var ok = streq(translit_to_ascii("Škoda"), "Skoda");
  if !streq(translit_to_ascii("žlutý"), "zluty") { ok = false; }
  if !streq(translit_to_ascii("Łódź"), "Lodz") { ok = false; }
  if !streq(translit_to_ascii("Đorđe"), "Dorde") { ok = false; }
  return assert(ok, "extended latin: š, ž, ł, đ, ý");
}

fn t8() -> TestResult {
  var ok = streq(translit_to_ascii("Ελλάδα"), "Ellada");
  if !streq(translit_to_ascii("θάλασσα"), "thalassa") { ok = false; }
  if !streq(translit_to_ascii("ψυχή"), "psyche") { ok = false; }
  if !streq(translit_to_ascii("Ξάνθη"), "Xanthe") { ok = false; }
  return assert(ok, "greek: Ελλάδα->Ellada, θ->th, ψ->ps, ξ->x");
}

fn t9() -> TestResult {
  var ok = streq(translit_to_ascii("Ελλάς"), "Ellas");
  if !streq(translit_to_ascii("Ωμέγα"), "Omega") { ok = false; }
  if !streq(translit_to_ascii("Άλφα"), "Alpha") { ok = false; }
  if !streq(translit_to_ascii("Νίκη"), "Nike") { ok = false; }
  return assert(ok, "greek: final sigma, accents, uppercase, φ->ph");
}

fn t10() -> TestResult {
  var ok = streq(translit_to_ascii("Москва"), "Moskva");
  if !streq(translit_to_ascii("жук"), "zhuk") { ok = false; }
  if !streq(translit_to_ascii("я"), "ya") { ok = false; }
  if !streq(translit_to_ascii("Я"), "Ya") { ok = false; }
  return assert(ok, "cyrillic: Москва->Moskva, жук->zhuk, я->ya");
}

fn t11() -> TestResult {
  var ok = streq(translit_to_ascii("Щука"), "Shchuka");
  if !streq(translit_to_ascii("Харьков"), "Kharkov") { ok = false; }
  if !streq(translit_to_ascii("Царь"), "Tsar") { ok = false; }
  if !streq(translit_to_ascii("Ёлка"), "Yolka") { ok = false; }
  return assert(ok, "cyrillic: щ->shch, х->kh, ц->ts, ь omitted, ё->yo");
}

fn t12() -> TestResult {
  var ok = streq(translit_to_ascii("‘left’"), "'left'");
  if !streq(translit_to_ascii("“smart”"), "\"smart\"") { ok = false; }
  return assert(ok, "curly quotes map to straight ASCII quotes");
}

fn t13() -> TestResult {
  var ok = streq(translit_to_ascii("a–b"), "a-b");
  if !streq(translit_to_ascii("a—b"), "a-b") { ok = false; }
  if !streq(translit_to_ascii("Wait…"), "Wait...") { ok = false; }
  return assert(ok, "en/em dash -> -, ellipsis -> ...");
}

fn t14() -> TestResult {
  let nbsp = str_of2(0xC2, 0xA0);
  var ok = streq(translit_to_ascii("a" + nbsp + "b"), "a b");
  if !streq(translit_to_ascii(nbsp), " ") { ok = false; }
  if !streq(translit_to_ascii("1" + nbsp + "000"), "1 000") { ok = false; }
  return assert(ok, "NBSP (U+00A0) becomes one ASCII space");
}

fn t15() -> TestResult {
  var ok = streq(translit_to_ascii("中"), "");
  if !streq(translit_to_ascii("a中b"), "ab") { ok = false; }
  if !streq(translit_to_ascii("✓"), "") { ok = false; }
  if !streq(translit_to_ascii("😀"), "") { ok = false; }
  if !streq(translit_to_ascii("→"), "") { ok = false; }
  return assert(ok, "unmapped codepoints (incl. 4-byte) are dropped");
}

fn t16() -> TestResult {
  var ok = streq(translit_to_ascii(str_of1(0xE9)), str_of1(0xE9));
  if !streq(translit_to_ascii(str_of2(0xE2, 0x82)), str_of2(0xE2, 0x82)) { ok = false; }
  if !streq(translit_to_ascii(str_of3(0xE2, 0x28, 0xA1)), str_of3(0xE2, 0x28, 0xA1)) { ok = false; }
  if !streq(translit_to_ascii(str_of2(0xC0, 0xAF)), str_of2(0xC0, 0xAF)) { ok = false; }
  let mixed = "é" + str_of1(0xE9);
  if !streq(translit_to_ascii(mixed), "e" + str_of1(0xE9)) { ok = false; }
  return assert(ok, "invalid UTF-8 passes through one byte at a time");
}

fn t17() -> TestResult {
  var ok = translit_is_ascii("");
  if !streq(translit_to_ascii(""), "") { ok = false; }
  if !streq(translit_slug(""), "") { ok = false; }
  return assert(ok, "empty input: ASCII, empty output, empty slug");
}

fn t18() -> TestResult {
  var ok = streq(translit_slug("Café Münster"), "cafe-munster");
  if !streq(translit_slug("Hello World"), "hello-world") { ok = false; }
  if !streq(translit_slug("MIXED Case"), "mixed-case") { ok = false; }
  return assert(ok, "slug: diacritics transliterate, then lowercase");
}

fn t19() -> TestResult {
  var ok = streq(translit_slug("a   b"), "a-b");
  if !streq(translit_slug("  über  "), "uber") { ok = false; }
  if !streq(translit_slug("a...b"), "a-b") { ok = false; }
  if !streq(translit_slug("---"), "") { ok = false; }
  if !streq(translit_slug("  --  "), "") { ok = false; }
  return assert(ok, "slug: runs collapse, edges trimmed");
}

fn t20() -> TestResult {
  var ok = streq(translit_slug("!!!"), "");
  if !streq(translit_slug("…"), "") { ok = false; }
  if !streq(translit_slug(" — "), "") { ok = false; }
  if !streq(translit_slug("中"), "") { ok = false; }
  if !streq(translit_slug("C++ & Rust"), "c-rust") { ok = false; }
  if !streq(translit_slug("Track 2"), "track-2") { ok = false; }
  return assert(ok, "slug: punctuation-only yields empty, digits survive");
}

fn main() -> Int {
  io.println("=== xiom.transliteration conformance tests ===");
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
    io.println("xiom.transliteration: all tests passed");
  } else {
    io.println("xiom.transliteration: tests failed");
  }
  return failed;
}
