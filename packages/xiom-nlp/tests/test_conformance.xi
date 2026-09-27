// XIOM -- xiom.nlp conformance tests (27 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Covers: tokenizer offsets and edge cases (apostrophes, digits, bytes >=
// 128 as separators, empty inputs, out-of-range accessors); ASCII lowercase
// and case-insensitive comparison; sentence splitting with the abbreviation
// guard list, the decimal guard, repeated terminators and whitespace
// handling; the Porter stemmer through every step with the classic 1980
// paper examples, the public measure/contains-vowel/ends-* predicates, the
// checked error offsets, and the statistics helpers.
//
// All inputs are built in this file; no external data. Str equality goes
// through str_compare (BUG 17: `==` on Str values read from Vec[Str]
// elements lowers to a pointer comparison), and every Vec element is bound
// to a typed local before use.

module nlp_tests
use xiom.io; use xiom.test;
use xiom.nlp;
use xiom.string;
use xiom.string.compare;

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
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

fn bytes3(a: Int, b: Int, c: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  v.push(a as UInt8);
  v.push(b as UInt8);
  v.push(c as UInt8);
  return v;
}

fn str_bytes2(a: Int, b: Int) -> Str {
  var v = Vec[UInt8].new();
  v.push(a as UInt8);
  v.push(b as UInt8);
  return Str::from_utf8(v);
}

fn stem_str(s: Str) -> Str {
  let w = bytes_of(s);
  let r = nlp_stem(&w);
  return Str::from_utf8(r);
}

fn stem_is(s: Str, want: Str) -> Bool {
  return streq(stem_str(s), want);
}

fn sent_count(text: Str) -> Int {
  let ss = nlp_sentences(text);
  return nlp_sentence_count(&ss);
}

fn sent_text_is(text: Str, i: Int, want: Str) -> Bool {
  let ss = nlp_sentences(text);
  return streq(nlp_sentence_text(&ss, i), want);
}

fn checked_code(w: &Vec[UInt8]) -> Int {
  let r = nlp_stem_checked(w);
  match r {
    Ok(_) => { return 0; },
    Err(e) => { return nlp_error_code(&e); },
  };
  return -1;
}

fn checked_offset(w: &Vec[UInt8]) -> Int {
  let r = nlp_stem_checked(w);
  match r {
    Ok(_) => { return -1; },
    Err(e) => { return nlp_error_offset(&e); },
  };
  return -2;
}

fn checked_is_ok(w: &Vec[UInt8]) -> Bool {
  let r = nlp_stem_checked(w);
  match r {
    Ok(_) => { return true; },
    Err(_) => { return false; },
  };
  return false;
}

fn t1() -> TestResult {
  let t = nlp_tokenize("Hello, world!");
  var ok = nlp_token_count(&t) == 2;
  if nlp_token_start(&t, 0) != 0 { ok = false; }
  if nlp_token_end(&t, 0) != 5 { ok = false; }
  if !streq(nlp_token_text(&t, 0), "Hello") { ok = false; }
  if nlp_token_start(&t, 1) != 7 { ok = false; }
  if nlp_token_end(&t, 1) != 12 { ok = false; }
  if !streq(nlp_token_text(&t, 1), "world") { ok = false; }
  return assert(ok, "tokenizer: two words with exact byte offsets");
}

fn t2() -> TestResult {
  let t = nlp_tokenize("don't 42x a'b''c");
  var ok = nlp_token_count(&t) == 3;
  if !streq(nlp_token_text(&t, 0), "don't") { ok = false; }
  if nlp_token_start(&t, 0) != 0 { ok = false; }
  if nlp_token_end(&t, 0) != 5 { ok = false; }
  if !streq(nlp_token_text(&t, 1), "42x") { ok = false; }
  if nlp_token_start(&t, 1) != 6 { ok = false; }
  if nlp_token_end(&t, 1) != 9 { ok = false; }
  if !streq(nlp_token_text(&t, 2), "a'b''c") { ok = false; }
  if nlp_token_start(&t, 2) != 10 { ok = false; }
  if nlp_token_end(&t, 2) != 16 { ok = false; }
  let tb = nlp_token_bytes(&t, 0);
  if tb.len() != 5 { ok = false; }
  return assert(ok, "tokenizer: apostrophes and digits are word bytes");
}

fn t3() -> TestResult {
  let a = nlp_tokenize("");
  var ok = nlp_token_count(&a) == 0;
  let b = nlp_tokenize("  ,.;:!?-_ \t\n");
  if nlp_token_count(&b) != 0 { ok = false; }
  let c = nlp_tokenize("...");
  if nlp_token_count(&c) != 0 { ok = false; }
  let d = nlp_tokenize("hi");
  if nlp_token_count(&d) != 1 { ok = false; }
  return assert(ok, "tokenizer: empty and separator-only inputs yield no tokens");
}

fn t4() -> TestResult {
  let text = "a" + str_bytes2(195, 169) + "b";
  let t = nlp_tokenize(text);
  var ok = nlp_token_count(&t) == 2;
  if nlp_token_start(&t, 0) != 0 { ok = false; }
  if nlp_token_end(&t, 0) != 1 { ok = false; }
  if nlp_token_start(&t, 1) != 3 { ok = false; }
  if nlp_token_end(&t, 1) != 4 { ok = false; }
  let q = nlp_tokenize("'' x");
  if nlp_token_count(&q) != 2 { ok = false; }
  if !streq(nlp_token_text(&q, 0), "''") { ok = false; }
  return assert(ok, "tokenizer: bytes >= 128 separate; apostrophe runs are tokens");
}

fn t5() -> TestResult {
  let t = nlp_tokenize("one two");
  var ok = nlp_token_count(&t) == 2;
  if nlp_token_start(&t, -1) != -1 { ok = false; }
  if nlp_token_start(&t, 2) != -1 { ok = false; }
  if nlp_token_end(&t, -5) != -1 { ok = false; }
  if nlp_token_end(&t, 7) != -1 { ok = false; }
  if !streq(nlp_token_text(&t, -1), "") { ok = false; }
  if !streq(nlp_token_text(&t, 2), "") { ok = false; }
  let b = nlp_token_bytes(&t, 2);
  if b.len() != 0 { ok = false; }
  if nlp_token_equals(&t, 2, "two") { ok = false; }
  if nlp_token_equals_ci(&t, -1, "one") { ok = false; }
  return assert(ok, "tokenizer: out-of-range accessors return -1/empty/false");
}

fn t6() -> TestResult {
  let t = nlp_tokenize("Hello world");
  var ok = nlp_token_equals(&t, 0, "Hello");
  if nlp_token_equals(&t, 0, "hello") { ok = false; }
  if !nlp_token_equals_ci(&t, 0, "HELLO") { ok = false; }
  if !nlp_token_equals_ci(&t, 0, "hello") { ok = false; }
  if nlp_token_equals_ci(&t, 0, "hell") { ok = false; }
  if !nlp_token_equals_ci(&t, 1, "WORLD") { ok = false; }
  return assert(ok, "tokens: case-sensitive and case-insensitive comparison");
}

fn t7() -> TestResult {
  let la: Int = (nlp_lower_byte(65u8) as Int) & 0xFF;
  var ok = la == 97;
  let lz: Int = (nlp_lower_byte(90u8) as Int) & 0xFF;
  if lz != 122 { ok = false; }
  let ld: Int = (nlp_lower_byte(48u8) as Int) & 0xFF;
  if ld != 48 { ok = false; }
  let raw = bytes_of("a" + str_bytes2(195, 169));
  let low = nlp_lower_bytes(&raw);
  if low.len() != 3 { ok = false; }
  let b0: UInt8 = low[0];
  let b1: UInt8 = low[1];
  let b2: UInt8 = low[2];
  let v0: Int = (b0 as Int) & 0xFF;
  let v1: Int = (b1 as Int) & 0xFF;
  let v2: Int = (b2 as Int) & 0xFF;
  if v0 != 97 { ok = false; }
  if v1 != 195 { ok = false; }
  if v2 != 169 { ok = false; }
  let lower = nlp_lower_bytes(&bytes_of("AbC!z"));
  if !streq(Str::from_utf8(lower), "abc!z") { ok = false; }
  if !streq(nlp_lower_str("MiXeD 9Z"), "mixed 9z") { ok = false; }
  let e1 = bytes_of("AbC");
  let e2 = bytes_of("aBc");
  if !nlp_ci_equals(&e1, &e2) { ok = false; }
  let e3 = bytes_of("abd");
  if nlp_ci_equals(&e1, &e3) { ok = false; }
  let e4 = bytes_of("ab");
  if nlp_ci_equals(&e1, &e4) { ok = false; }
  return assert(ok, "case: lower byte/bytes/str, non-ASCII passthrough, ci equality");
}

fn t8() -> TestResult {
  let ss = nlp_sentences("One. Two! Three?");
  var ok = nlp_sentence_count(&ss) == 3;
  if nlp_sentence_start(&ss, 0) != 0 { ok = false; }
  if nlp_sentence_end(&ss, 0) != 4 { ok = false; }
  if !streq(nlp_sentence_text(&ss, 0), "One.") { ok = false; }
  if nlp_sentence_start(&ss, 1) != 5 { ok = false; }
  if nlp_sentence_end(&ss, 1) != 9 { ok = false; }
  if !streq(nlp_sentence_text(&ss, 1), "Two!") { ok = false; }
  if nlp_sentence_start(&ss, 2) != 10 { ok = false; }
  if nlp_sentence_end(&ss, 2) != 16 { ok = false; }
  if !streq(nlp_sentence_text(&ss, 2), "Three?") { ok = false; }
  return assert(ok, "sentences: terminators with whitespace and end");
}

fn t9() -> TestResult {
  let a = "Mr. Smith went home. He slept.";
  var ok = sent_count(a) == 2;
  if !sent_text_is(a, 0, "Mr. Smith went home.") { ok = false; }
  if !sent_text_is(a, 1, "He slept.") { ok = false; }
  let b = "Dr. X vs. Y went to St. Louis.";
  if sent_count(b) != 1 { ok = false; }
  let c = "Mrs. Lee and Ms. Poe met Prof. Field.";
  if sent_count(c) != 1 { ok = false; }
  return assert(ok, "sentences: Mr./Mrs./Dr./Ms./Prof./St./vs. guards");
}

fn t10() -> TestResult {
  let a = "e.g. apples, i.e. pears; etc. all fruit.";
  var ok = sent_count(a) == 1;
  let b = "See e.g. the appendix. Then stop.";
  if sent_count(b) != 2 { ok = false; }
  return assert(ok, "sentences: e.g./i.e./etc. guards");
}

fn t11() -> TestResult {
  let a = "Pi is 3.14 exactly. Really.";
  var ok = sent_count(a) == 2;
  if !sent_text_is(a, 0, "Pi is 3.14 exactly.") { ok = false; }
  let b = "It is 3. 14 percent.";
  if sent_count(b) != 1 { ok = false; }
  return assert(ok, "sentences: decimal guard keeps 3.14 and 3. 14 intact");
}

fn t12() -> TestResult {
  let a = nlp_sentences("No terminator here");
  var ok = nlp_sentence_count(&a) == 1;
  if nlp_sentence_start(&a, 0) != 0 { ok = false; }
  if nlp_sentence_end(&a, 0) != 18 { ok = false; }
  let b = nlp_sentences("   ");
  if nlp_sentence_count(&b) != 0 { ok = false; }
  let c = nlp_sentences("");
  if nlp_sentence_count(&c) != 0 { ok = false; }
  let d = nlp_sentences("  Hello!  ");
  if nlp_sentence_count(&d) != 1 { ok = false; }
  if nlp_sentence_start(&d, 0) != 2 { ok = false; }
  if nlp_sentence_end(&d, 0) != 8 { ok = false; }
  return assert(ok, "sentences: unterminated tail, whitespace-only, trimmed spans");
}

fn t13() -> TestResult {
  let a = "Wait... What?";
  var ok = sent_count(a) == 2;
  if !sent_text_is(a, 0, "Wait...") { ok = false; }
  if !sent_text_is(a, 1, "What?") { ok = false; }
  let b = "Hi!! Really?!";
  if sent_count(b) != 2 { ok = false; }
  if !sent_text_is(b, 0, "Hi!!") { ok = false; }
  if !sent_text_is(b, 1, "Really?!") { ok = false; }
  return assert(ok, "sentences: runs of terminators end at the last one");
}

fn t14() -> TestResult {
  let ss = nlp_sentences("One.");
  var ok = nlp_sentence_count(&ss) == 1;
  if nlp_sentence_start(&ss, -1) != -1 { ok = false; }
  if nlp_sentence_start(&ss, 1) != -1 { ok = false; }
  if nlp_sentence_end(&ss, 9) != -1 { ok = false; }
  if !streq(nlp_sentence_text(&ss, -2), "") { ok = false; }
  if !streq(nlp_sentence_text(&ss, 1), "") { ok = false; }
  return assert(ok, "sentences: out-of-range accessors return -1/empty");
}

fn t15() -> TestResult {
  var ok = stem_is("caresses", "caress");
  if !stem_is("ponies", "poni") { ok = false; }
  if !stem_is("ties", "ti") { ok = false; }
  if !stem_is("caress", "caress") { ok = false; }
  if !stem_is("cats", "cat") { ok = false; }
  if !stem_is("possesses", "possess") { ok = false; }
  return assert(ok, "porter 1a: SSES/IES/SS/S (ties->ti per Porter 1980)");
}

fn t16() -> TestResult {
  var ok = stem_is("feed", "feed");
  if !stem_is("agreed", "agre") { ok = false; }
  if !stem_is("plastered", "plaster") { ok = false; }
  if !stem_is("bled", "bled") { ok = false; }
  if !stem_is("motoring", "motor") { ok = false; }
  if !stem_is("sing", "sing") { ok = false; }
  return assert(ok, "porter 1b: EED/ED/ING with vowel and measure conditions");
}

fn t17() -> TestResult {
  var ok = stem_is("conflated", "conflat");
  if !stem_is("troubled", "troubl") { ok = false; }
  if !stem_is("sized", "size") { ok = false; }
  if !stem_is("hopping", "hop") { ok = false; }
  if !stem_is("tanned", "tan") { ok = false; }
  if !stem_is("falling", "fall") { ok = false; }
  if !stem_is("hissing", "hiss") { ok = false; }
  if !stem_is("fizzed", "fizz") { ok = false; }
  if !stem_is("failing", "fail") { ok = false; }
  if !stem_is("filing", "file") { ok = false; }
  return assert(ok, "porter 1b: AT/BL/IZ restore, double consonant, cvc + E");
}

fn t18() -> TestResult {
  var ok = stem_is("happy", "happi");
  if !stem_is("sky", "sky") { ok = false; }
  return assert(ok, "porter 1c: Y -> I only when the stem has a vowel");
}

fn t19() -> TestResult {
  var ok = stem_is("relational", "relat");
  if !stem_is("conditional", "condit") { ok = false; }
  if !stem_is("rational", "ration") { ok = false; }
  if !stem_is("valenci", "valenc") { ok = false; }
  if !stem_is("hesitanci", "hesit") { ok = false; }
  if !stem_is("digitizer", "digit") { ok = false; }
  if !stem_is("conformabli", "conform") { ok = false; }
  return assert(ok, "porter 2: ATIONAL/TIONAL/ENCI/ANCI/IZER/ABLI");
}

fn t20() -> TestResult {
  var ok = stem_is("radicalli", "radic");
  if !stem_is("differentli", "differ") { ok = false; }
  if !stem_is("vileli", "vile") { ok = false; }
  if !stem_is("analogousli", "analog") { ok = false; }
  if !stem_is("vietnamization", "vietnam") { ok = false; }
  if !stem_is("predication", "predic") { ok = false; }
  if !stem_is("operator", "oper") { ok = false; }
  return assert(ok, "porter 2/4: ALLI/ENTLI/ELI/OUSLI/IZATION/ATION/ATOR");
}

fn t21() -> TestResult {
  var ok = stem_is("feudalism", "feudal");
  if !stem_is("decisiveness", "decis") { ok = false; }
  if !stem_is("hopefulness", "hope") { ok = false; }
  if !stem_is("callousness", "callous") { ok = false; }
  if !stem_is("formaliti", "formal") { ok = false; }
  if !stem_is("sensitiviti", "sensit") { ok = false; }
  if !stem_is("sensibiliti", "sensibl") { ok = false; }
  return assert(ok, "porter 2/3/4: ALISM/IVENESS/FULNESS/OUSNESS/ALITI/IVITI/BILITI");
}

fn t22() -> TestResult {
  var ok = stem_is("triplicate", "triplic");
  if !stem_is("formative", "form") { ok = false; }
  if !stem_is("formalize", "formal") { ok = false; }
  if !stem_is("electriciti", "electr") { ok = false; }
  if !stem_is("electrical", "electr") { ok = false; }
  if !stem_is("hopeful", "hope") { ok = false; }
  if !stem_is("goodness", "good") { ok = false; }
  return assert(ok, "porter 3/4: ICATE/ATIVE/ALIZE/ICITI/ICAL/FUL/NESS");
}

fn t23() -> TestResult {
  var ok = stem_is("revival", "reviv");
  if !stem_is("allowance", "allow") { ok = false; }
  if !stem_is("inference", "infer") { ok = false; }
  if !stem_is("airliner", "airlin") { ok = false; }
  if !stem_is("gyroscopic", "gyroscop") { ok = false; }
  if !stem_is("adjustable", "adjust") { ok = false; }
  if !stem_is("defensible", "defens") { ok = false; }
  if !stem_is("irritant", "irrit") { ok = false; }
  if !stem_is("replacement", "replac") { ok = false; }
  if !stem_is("adjustment", "adjust") { ok = false; }
  if !stem_is("dependent", "depend") { ok = false; }
  if !stem_is("adoption", "adopt") { ok = false; }
  if !stem_is("homologou", "homolog") { ok = false; }
  if !stem_is("communism", "commun") { ok = false; }
  if !stem_is("activate", "activ") { ok = false; }
  if !stem_is("angulariti", "angular") { ok = false; }
  if !stem_is("homologous", "homolog") { ok = false; }
  if !stem_is("effective", "effect") { ok = false; }
  if !stem_is("bowdlerize", "bowdler") { ok = false; }
  return assert(ok, "porter 4: AL/ANCE/ENCE/ER/IC/ABLE/.../IVE/IZE (m>1)");
}

fn t24() -> TestResult {
  var ok = stem_is("probate", "probat");
  if !stem_is("rate", "rate") { ok = false; }
  if !stem_is("cease", "ceas") { ok = false; }
  if !stem_is("controll", "control") { ok = false; }
  if !stem_is("roll", "roll") { ok = false; }
  return assert(ok, "porter 5a/5b: E removal and final LL -> L");
}

fn t25() -> TestResult {
  let trouble = bytes_of("trouble");
  let trees = bytes_of("trees");
  let tree = bytes_of("tree");
  let tr = bytes_of("tr");
  let private_w = bytes_of("private");
  let troubles = bytes_of("troubles");
  let orrery = bytes_of("orrery");
  let fall = bytes_of("fall");
  let fail = bytes_of("fail");
  let hop = bytes_of("hop");
  let tray = bytes_of("tray");
  let rate = bytes_of("rate");
  let sky = bytes_of("sky");
  let empty = Vec[UInt8].new();
  var ok = nlp_measure(&trouble) == 1;
  if nlp_measure(&trees) != 1 { ok = false; }
  if nlp_measure(&tree) != 0 { ok = false; }
  if nlp_measure(&tr) != 0 { ok = false; }
  if nlp_measure(&private_w) != 2 { ok = false; }
  if nlp_measure(&troubles) != 2 { ok = false; }
  if nlp_measure(&orrery) != 2 { ok = false; }
  if nlp_measure(&empty) != 0 { ok = false; }
  if !nlp_contains_vowel(&tree) { ok = false; }
  if nlp_contains_vowel(&tr) { ok = false; }
  if !nlp_contains_vowel(&sky) { ok = false; }
  if !nlp_ends_with(&trouble, "ble") { ok = false; }
  if !nlp_ends_with(&tr, "tr") { ok = false; }
  if nlp_ends_with(&tr, "tree") { ok = false; }
  if !nlp_ends_double_consonant(&fall) { ok = false; }
  if nlp_ends_double_consonant(&fail) { ok = false; }
  if nlp_ends_double_consonant(&empty) { ok = false; }
  if !nlp_ends_cvc(&hop) { ok = false; }
  if nlp_ends_cvc(&tray) { ok = false; }
  if nlp_ends_cvc(&rate) { ok = false; }
  if nlp_ends_cvc(&fail) { ok = false; }
  if nlp_ends_cvc(&empty) { ok = false; }
  return assert(ok, "porter predicates: measure/contains-vowel/ends-*");
}

fn t26() -> TestResult {
  let nonascii = bytes3(97, 195, 169);
  var ok = checked_code(&nonascii) == 1;
  if checked_offset(&nonascii) != 1 { ok = false; }
  let empty = Vec[UInt8].new();
  if checked_code(&empty) != 2 { ok = false; }
  if checked_offset(&empty) != 0 { ok = false; }
  let two = bytes_of("ab");
  if !checked_is_ok(&two) { ok = false; }
  if !streq(Str::from_utf8(nlp_stem(&two)), "ab") { ok = false; }
  let upper = bytes_of("Cats");
  if !checked_is_ok(&upper) { ok = false; }
  if !streq(Str::from_utf8(nlp_stem(&upper)), "Cat") { ok = false; }
  let allcaps = bytes_of("CATS");
  if !checked_is_ok(&allcaps) { ok = false; }
  if !streq(Str::from_utf8(nlp_stem(&allcaps)), "CATS") { ok = false; }
  let lax = nlp_stem(&nonascii);
  if lax.len() != 3 { ok = false; }
  if !streq(Str::from_utf8(lax), Str::from_utf8(bytes3(97, 195, 169))) { ok = false; }
  let empty2 = Vec[UInt8].new();
  let le = nlp_stem(&empty2);
  if le.len() != 0 { ok = false; }
  return assert(ok, "stemmer: checked errors carry offsets; lax passes rejected input through");
}

fn t27() -> TestResult {
  let t = nlp_tokenize("Dogs dog cat cats");
  var ok = nlp_token_count(&t) == 4;
  if nlp_total_token_length(&t) != 14 { ok = false; }
  if nlp_avg_token_length(&t) != 3 { ok = false; }
  if nlp_distinct_stem_count(&t) != 2 { ok = false; }
  let e = nlp_tokenize("");
  if nlp_total_token_length(&e) != 0 { ok = false; }
  if nlp_avg_token_length(&e) != 0 { ok = false; }
  if nlp_distinct_stem_count(&e) != 0 { ok = false; }
  let u = nlp_tokenize("Run running RUNS");
  if nlp_distinct_stem_count(&u) != 1 { ok = false; }
  return assert(ok, "statistics: count, total/avg length, distinct stems");
}

fn main() -> Int {
  io.println("=== xiom.nlp conformance tests ===");
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
  if failed == 0 {
    io.println("xiom.nlp: all tests passed");
  } else {
    io.println("xiom.nlp: tests failed");
  }
  return failed;
}
