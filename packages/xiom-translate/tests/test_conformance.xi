// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
// XIOM -- xiom.translate conformance tests (28 checks)
// Port task: prove the pure-XIOM xiom.translate module against its
// documented subsets (SPEC.md).
//
// Coverage: phrasebook pair validation, term lookup with case re-application,
// checked error codes, word-by-word application, detection for the six
// languages plus empty/no-signal/distinctive-character cases, Cyrillic <->
// Latin and Greek <-> Latin transliteration (digraphs, signs, invalid UTF-8
// passthrough), and the glossary value (add/lookup/has/apply/rejected
// entries).
//
// BUG-17 notes: all Str equality goes through str_compare (via streq);
// every Vec[Int] element read is bound to a typed local; no Vec[Str] is
// used. Test dispatch is a direct call chain (t1..t28 from main), never a
// Vec[fn] table.

module translate_tests
use xiom.io; use xiom.test;
use xiom.translate;
use xiom.string;
use xiom.string.compare;

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// Str from two raw bytes (for the invalid-UTF-8 passthrough check).
fn str_of2(a: Int, b: Int) -> Str {
  var v = Vec[UInt8].new();
  v.push(a as UInt8);
  v.push(b as UInt8);
  return Str::from_utf8(v);
}

fn checked_ok(pair: Str, term: Str, want: Str) -> Bool {
  match translate_term_checked(pair, term) {
    Ok(v) => { return streq(v, want); },
    Err(c) => { return false; },
  };
  return false;
}

fn checked_err(pair: Str, term: Str, want: Int) -> Bool {
  match translate_term_checked(pair, term) {
    Ok(v) => { return false; },
    Err(c) => { return c == want; },
  };
  return false;
}

// ---------------------------------------------------------------------------
// Phrasebook
// ---------------------------------------------------------------------------

fn t1() -> TestResult {
  var ok = translate_pair_supported("en-fr");
  if !translate_pair_supported("fr-en") { ok = false; }
  if !translate_pair_supported("de-es") { ok = false; }
  if !translate_pair_supported("es-de") { ok = false; }
  if translate_pair_supported("en") { ok = false; }
  if translate_pair_supported("en-en") { ok = false; }
  if translate_pair_supported("en-xx") { ok = false; }
  if translate_pair_supported("xx-fr") { ok = false; }
  if translate_pair_supported("") { ok = false; }
  if translate_pair_supported("en-fr-x") { ok = false; }
  return assert(ok, "pair support: 12 directed pairs, malformed/equal refused");
}

fn t2() -> TestResult {
  var ok = streq(translate_term("en-fr", "hello"), "bonjour");
  if !streq(translate_term("en-fr", "thanks"), "merci") { ok = false; }
  if !streq(translate_term("fr-en", "bonjour"), "hello") { ok = false; }
  if !streq(translate_term("fr-en", "merci"), "thanks") { ok = false; }
  return assert(ok, "en-fr / fr-en concept lookup");
}

fn t3() -> TestResult {
  var ok = streq(translate_term("en-de", "water"), "wasser");
  if !streq(translate_term("en-de", "bread"), "brot") { ok = false; }
  if !streq(translate_term("de-en", "wasser"), "water") { ok = false; }
  if !streq(translate_term("de-en", "hallo"), "hello") { ok = false; }
  return assert(ok, "en-de / de-en concept lookup");
}

fn t4() -> TestResult {
  var ok = streq(translate_term("en-es", "friend"), "amigo");
  if !streq(translate_term("es-en", "amigo"), "friend") { ok = false; }
  if !streq(translate_term("de-es", "wasser"), "agua") { ok = false; }
  if !streq(translate_term("es-de", "agua"), "wasser") { ok = false; }
  if !streq(translate_term("fr-es", "merci"), "gracias") { ok = false; }
  return assert(ok, "pivot pairs through the shared concept table");
}

fn t5() -> TestResult {
  var ok = streq(translate_term("en-fr", "hello"), "bonjour");
  if !streq(translate_term("en-fr", "Hello"), "Bonjour") { ok = false; }
  if !streq(translate_term("en-fr", "HELLO"), "BONJOUR") { ok = false; }
  if !streq(translate_term("en-fr", "hELLO"), "bonjour") { ok = false; }
  return assert(ok, "term case re-application (lower/capitalized/upper/mixed)");
}

fn t6() -> TestResult {
  var ok = streq(translate_term("en-fr", "computer"), "");
  if !streq(translate_term("en-fr", ""), "") { ok = false; }
  if !streq(translate_term("en-xx", "hello"), "") { ok = false; }
  if !streq(translate_term("en-en", "hello"), "") { ok = false; }
  return assert(ok, "unknown term or unsupported pair yields empty");
}

fn t7() -> TestResult {
  var ok = checked_ok("en-fr", "hello", "bonjour");
  if !checked_err("en-en", "hello", 1) { ok = false; }
  if !checked_err("xx-fr", "hello", 1) { ok = false; }
  if !checked_err("en-fr", "computer", 2) { ok = false; }
  return assert(ok, "term_checked: Ok path, Err(1) pair, Err(2) term");
}

fn t8() -> TestResult {
  return assert(streq(translate_apply("en-fr", "hello friend, thanks!"), "bonjour ami, merci!"), "apply: words replaced, punctuation kept");
}

fn t9() -> TestResult {
  var ok = streq(translate_apply("fr-en", "bonjour le monde"), "hello le monde");
  if !streq(translate_apply("en-fr", "Hello, friend!"), "Bonjour, ami!") { ok = false; }
  if !streq(translate_apply("en-xx", "hello"), "hello") { ok = false; }
  return assert(ok, "apply: unknown words kept, case re-applied, bad pair passthrough");
}

fn t10() -> TestResult {
  var ok = string.str_contains(translate_terms(), "hello");
  if !string.str_contains(translate_terms(), "water") { ok = false; }
  if !string.str_contains(translate_terms(), "three") { ok = false; }
  if !streq(translate_languages(), "en,fr,de,es") { ok = false; }
  if translate_concept_count() != 22 { ok = false; }
  return assert(ok, "terms/languages listing and concept count");
}

fn t11() -> TestResult {
  var ok = streq(translate_apply("en-fr", "hello\nworld"), "bonjour\nworld");
  if !streq(translate_apply("en-fr", "water,water"), "eau,eau") { ok = false; }
  if !streq(translate_apply("en-fr", ""), "") { ok = false; }
  return assert(ok, "apply: newline, repeated word, empty text");
}

// ---------------------------------------------------------------------------
// Language detection
// ---------------------------------------------------------------------------

fn t12() -> TestResult {
  let s = "The quick brown fox and the lazy dog in the house";
  var ok = streq(detect_language(s), "en");
  if detect_language(s) != "en" { ok = false; }
  return assert(ok, "detect: English sentence");
}

fn t13() -> TestResult {
  let s = "Der Mann und die Frau gehen in das Haus und trinken Wasser";
  var ok = streq(detect_language(s), "de");
  if !(detect_language_score(s, "de") > detect_language_score(s, "en")) { ok = false; }
  return assert(ok, "detect: German sentence, de over en");
}

fn t14() -> TestResult {
  let s = "Le chat et la souris sont dans la maison avec un livre";
  return assert(streq(detect_language(s), "fr"), "detect: French sentence");
}

fn t15() -> TestResult {
  let s = "El gato y la casa de la amiga con un libro en la mesa";
  return assert(streq(detect_language(s), "es"), "detect: Spanish sentence");
}

fn t16() -> TestResult {
  let s = "Il gatto e la casa della donna con un libro che parla di Roma";
  return assert(streq(detect_language(s), "it"), "detect: Italian sentence");
}

fn t17() -> TestResult {
  let s = "Het huis van de man en de vrouw met een boek op tafel";
  return assert(streq(detect_language(s), "nl"), "detect: Dutch sentence");
}

fn t18() -> TestResult {
  var ok = streq(detect_language(""), "");
  if !streq(detect_language("12345 !!! ???"), "") { ok = false; }
  if detect_language_score("", "en") != 0 { ok = false; }
  if detect_language_score("the and", "xx") != 0 { ok = false; }
  if detect_language_count() != 6 { ok = false; }
  if !streq(detect_language_supported(), "en,de,fr,es,it,nl") { ok = false; }
  return assert(ok, "detect: no-signal, empty, unknown code, supported list");
}

fn t19() -> TestResult {
  var ok = streq(detect_language("Straße"), "de");
  if !streq(detect_language("señor"), "es") { ok = false; }
  if !streq(detect_language("München"), "de") { ok = false; }
  return assert(ok, "detect: distinctive characters (sharp s, n-tilde, u-umlaut)");
}

fn t20() -> TestResult {
  let s = "The quick brown fox and the lazy dog in the house";
  var ok = detect_language_score(s, "en") > detect_language_score(s, "es");
  if detect_language_score(s, "en") <= 0 { ok = false; }
  let a = detect_language(s);
  let b = detect_language(s);
  if !streq(a, b) { ok = false; }
  return assert(ok, "detect: score ordering and determinism across calls");
}

// ---------------------------------------------------------------------------
// Script transliteration
// ---------------------------------------------------------------------------

fn t21() -> TestResult {
  var ok = streq(translit_cyrillic_to_latin("Привет"), "Privet");
  if !streq(translit_cyrillic_to_latin("Москва"), "Moskva") { ok = false; }
  if !streq(translit_cyrillic_to_latin("Санкт-Петербург"), "Sankt-Peterburg") { ok = false; }
  return assert(ok, "cyrillic->latin: basic words");
}

fn t22() -> TestResult {
  var ok = streq(translit_cyrillic_to_latin("Щука"), "Shchuka");
  if !streq(translit_cyrillic_to_latin("Журавлёв"), "Zhuravlev") { ok = false; }
  if !streq(translit_cyrillic_to_latin("объект"), "obekt") { ok = false; }
  if !streq(translit_cyrillic_to_latin("мягкий"), "myagkiy") { ok = false; }
  return assert(ok, "cyrillic->latin: digraphs, Yo, hard/soft sign dropped");
}

fn t23() -> TestResult {
  var ok = streq(translit_latin_to_cyrillic("Privet"), "Привет");
  if !streq(translit_latin_to_cyrillic("Moskva"), "Москва") { ok = false; }
  if !streq(translit_latin_to_cyrillic("Yuriy"), "Юрий") { ok = false; }
  return assert(ok, "latin->cyrillic: basic words and case");
}

fn t24() -> TestResult {
  var ok = streq(translit_latin_to_cyrillic("shchuka"), "щука");
  if !streq(translit_latin_to_cyrillic("Shchuka"), "Щука") { ok = false; }
  if !streq(translit_latin_to_cyrillic("zhurnal"), "журнал") { ok = false; }
  if !streq(translit_latin_to_cyrillic("knyaz"), "княз") { ok = false; }
  return assert(ok, "latin->cyrillic: longest-match digraphs, case");
}

fn t25() -> TestResult {
  var ok = streq(translit_greek_to_latin("Ελλάδα"), "Ellada");
  if !streq(translit_greek_to_latin("θάλασσα"), "thalassa") { ok = false; }
  if !streq(translit_greek_to_latin("λόγος"), "logos") { ok = false; }
  if !streq(translit_greek_to_latin("Ξάνθη"), "Xanthi") { ok = false; }
  if !streq(translit_greek_to_latin("ψυχή"), "psuchi") { ok = false; }
  return assert(ok, "greek->latin: letters, tonos, final sigma, digraphs");
}

fn t26() -> TestResult {
  var ok = streq(translit_latin_to_greek("thema"), "θεμα");
  if !streq(translit_latin_to_greek("thalassa"), "θαλασσα") { ok = false; }
  if !streq(translit_latin_to_greek("Thema"), "Θεμα") { ok = false; }
  if !streq(translit_latin_to_greek(translit_greek_to_latin("θάλασσα")), "θαλασσα") { ok = false; }
  return assert(ok, "latin->greek: digraphs, case, round trip without accents");
}

fn t27() -> TestResult {
  var ok = streq(translit_cyrillic_to_latin(""), "");
  if !streq(translit_latin_to_cyrillic(""), "") { ok = false; }
  if !streq(translit_greek_to_latin(""), "") { ok = false; }
  if !streq(translit_latin_to_greek(""), "") { ok = false; }
  if !streq(translit_cyrillic_to_latin("abc 123!"), "abc 123!") { ok = false; }
  if !streq(translit_greek_to_latin("abc 123!"), "abc 123!") { ok = false; }
  if !streq(translit_latin_to_cyrillic("123 !?"), "123 !?") { ok = false; }
  if !streq(translit_latin_to_greek("123 !?"), "123 !?") { ok = false; }
  let bad = str_of2(0xE9, 0x41);
  if !streq(translit_cyrillic_to_latin(bad), bad) { ok = false; }
  if !streq(translit_greek_to_latin(bad), bad) { ok = false; }
  return assert(ok, "translit: empty, ASCII passthrough, invalid byte passthrough");
}

// ---------------------------------------------------------------------------
// Glossary
// ---------------------------------------------------------------------------

fn t28() -> TestResult {
  var g = glossary_new();
  var ok = glossary_len(&g) == 0;
  g = glossary_add(&g, "network", "reseau");
  g = glossary_add(&g, "file", "fichier");
  if glossary_len(&g) != 2 { ok = false; }
  if !streq(glossary_lookup(&g, "network"), "reseau") { ok = false; }
  if !streq(glossary_lookup(&g, "FILE"), "fichier") { ok = false; }
  if !glossary_has(&g, "File") { ok = false; }
  if glossary_has(&g, "disk") { ok = false; }
  g = glossary_add(&g, "network", "netz");
  if glossary_len(&g) != 3 { ok = false; }
  if !streq(glossary_lookup(&g, "network"), "netz") { ok = false; }
  var applied = streq(glossary_apply(&g, "The network and the file."), "The netz and the fichier.");
  if !applied { ok = false; }
  let before = glossary_len(&g);
  g = glossary_add(&g, "bad\nkey", "x");
  if glossary_len(&g) != before { ok = false; }
  g = glossary_add(&g, "", "x");
  if glossary_len(&g) != before { ok = false; }
  if !streq(glossary_lookup(&g, "bad\nkey"), "") { ok = false; }
  return assert(ok, "glossary: add/len/ci lookup/has/apply/rejected entries");
}

// ---------------------------------------------------------------------------

fn main() -> Int {
  io.println("=== xiom.translate conformance tests ===");
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
  let r24 = t24();
  if r24.passed { io.println("  [PASS] " + r24.name); } else { io.println("  [FAIL] " + r24.name); failed = failed + 1; }
  let r25 = t25();
  if r25.passed { io.println("  [PASS] " + r25.name); } else { io.println("  [FAIL] " + r25.name); failed = failed + 1; }
  let r26 = t26();
  if r26.passed { io.println("  [PASS] " + r26.name); } else { io.println("  [FAIL] " + r26.name); failed = failed + 1; }
  let r27 = t27();
  if r27.passed { io.println("  [PASS] " + r27.name); } else { io.println("  [FAIL] " + r27.name); failed = failed + 1; }
  let r28 = t28();
  if r28.passed { io.println("  [PASS] " + r28.name); } else { io.println("  [FAIL] " + r28.name); failed = failed + 1; }
  if failed == 0 {
    io.println("xiom.translate: all tests passed");
  } else {
    io.println("xiom.translate: tests failed");
  }
  return failed;
}
