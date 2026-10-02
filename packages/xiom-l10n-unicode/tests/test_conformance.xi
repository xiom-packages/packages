// XIOM -- xiom.l10n-unicode conformance tests (24 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Provenance: every category / combining-class / case / decomposition fixture
// is Unicode data (CPython 3.7 unicodedata, Unicode 11.0.0), cross-checked
// against Python's unicodedata.normalize for the normalization fixtures. The
// segmentation fixtures follow the documented (subset) rule sets in SPEC.md.
//
// BUG-17 notes: all Str equality goes through str_compare (via streq); every
// Vec[Int] element read is bound to a typed local; no Vec[Str] is used.
//
// Compiler note: test dispatch is a direct call chain (t1..t24 from main),
// never a Vec[fn] table; parallel checks are written so no vector can drift.

module l10n_unicode_tests
use xiom.io; use xiom.test;
use xiom.l10n.unicode;
use xiom.l10n.unicode.tables;
use xiom.string.compare;
use xiom.convert;

// ---------------------------------------------------------------------------
// Probe helpers
// ---------------------------------------------------------------------------

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn veq(a: &Vec[Int], b: &Vec[Int]) -> Bool {
  if a.len() != b.len() { return false; }
  var i = 0;
  while i < a.len() {
    let x: Int = a[i];
    let y: Int = b[i];
    if x != y { return false; }
    i = i + 1;
  }
  return true;
}

fn v1(v: &Vec[Int], a: Int) -> Bool {
  if v.len() != 1 { return false; }
  let x: Int = v[0];
  return x == a;
}

fn v2(v: &Vec[Int], a: Int, b: Int) -> Bool {
  if v.len() != 2 { return false; }
  let x: Int = v[0];
  let y: Int = v[1];
  return x == a && y == b;
}

fn v3(v: &Vec[Int], a: Int, b: Int, c: Int) -> Bool {
  if v.len() != 3 { return false; }
  let x: Int = v[0];
  let y: Int = v[1];
  let z: Int = v[2];
  return x == a && y == b && z == c;
}

fn bounds3_ok(b: &Vec[Int], a: Int, c: Int, d: Int) -> Bool {
  return v3(b, a, c, d);
}

fn bounds4_ok(b: &Vec[Int], a: Int, c: Int, d: Int, e: Int) -> Bool {
  if b.len() != 4 { return false; }
  let x: Int = b[0];
  let y: Int = b[1];
  let z: Int = b[2];
  let w: Int = b[3];
  return x == a && y == c && z == d && w == e;
}

fn norm_is(s: Str, form: Str, want: Str) -> Bool {
  match l10n_unicode_normalize(s, form) {
    Ok(r) => { return streq(r, want); },
    Err(e) => { return false; },
  }
  return false;
}

fn norm_err_is(s: Str, form: Str, want: Str) -> Bool {
  match l10n_unicode_normalize(s, form) {
    Ok(r) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

fn t1() -> TestResult {
  var ok = streq(l10n_unicode_version(), "11.0.0");
  if !l10n_unicode_is_covered(0x0041) { ok = false; }
  if !l10n_unicode_is_covered(0x1EC7) { ok = false; }
  if l10n_unicode_is_covered(0x4E00) { ok = false; }
  if l10n_unicode_is_covered(0 - 1) { ok = false; }
  if !streq(l10n_unicode_category(0x0041), "Lu") { ok = false; }
  if !streq(l10n_unicode_category(0x4E00), "") { ok = false; }
  if !streq(l10n_unicode_category(0x0378), "Cn") { ok = false; }
  return assert(ok, "coverage: version, covered/uncovered probes, Cn inside a covered range");
}

fn t2() -> TestResult {
  var ok = streq(l10n_unicode_category(0x00E9), "Ll");
  if !streq(l10n_unicode_category(0x00C9), "Lu") { ok = false; }
  if !streq(l10n_unicode_category(0x00D7), "Sm") { ok = false; }
  if !streq(l10n_unicode_category(0x00F7), "Sm") { ok = false; }
  if !streq(l10n_unicode_category(0x00B2), "No") { ok = false; }
  if !streq(l10n_unicode_category(0x00BD), "No") { ok = false; }
  if !streq(l10n_unicode_category(0x00B0), "So") { ok = false; }
  if !streq(l10n_unicode_category(0x00A0), "Zs") { ok = false; }
  if !streq(l10n_unicode_category(0x00AD), "Cf") { ok = false; }
  if !streq(l10n_unicode_category(0x0301), "Mn") { ok = false; }
  if !streq(l10n_unicode_category(0x00AA), "Lo") { ok = false; }
  return assert(ok, "category: Latin-1 letters, math symbols, numbers, spaces, marks");
}

fn t3() -> TestResult {
  var ok = l10n_unicode_is_letter(0x0041);
  if !l10n_unicode_is_letter(0x00E9) { ok = false; }
  if !l10n_unicode_is_letter(0x03B1) { ok = false; }
  if !l10n_unicode_is_digit(0x0037) { ok = false; }
  if l10n_unicode_is_digit(0x0041) { ok = false; }
  if !l10n_unicode_is_punct(0x0021) { ok = false; }
  if !l10n_unicode_is_symbol(0x0024) { ok = false; }
  if !l10n_unicode_is_symbol(0x00D7) { ok = false; }
  if !l10n_unicode_is_separator(0x00A0) { ok = false; }
  if !l10n_unicode_is_whitespace(0x0020) { ok = false; }
  if !l10n_unicode_is_whitespace(0x2003) { ok = false; }
  if !l10n_unicode_is_control(0x0001) { ok = false; }
  if !l10n_unicode_is_format(0x00AD) { ok = false; }
  if !l10n_unicode_is_mark(0x0301) { ok = false; }
  if !l10n_unicode_is_uppercase(0x00C9) { ok = false; }
  if !l10n_unicode_is_lowercase(0x00E9) { ok = false; }
  if !l10n_unicode_is_cased(0x01C5) { ok = false; }
  if l10n_unicode_is_letter(0x4E00) { ok = false; }
  return assert(ok, "predicates: letter/digit/punct/symbol/space/control/mark/case classes");
}

fn t4() -> TestResult {
  var ok = l10n_unicode_combining_class(0x0301) == 230;
  if l10n_unicode_combining_class(0x0323) != 220 { ok = false; }
  if l10n_unicode_combining_class(0x0327) != 202 { ok = false; }
  if l10n_unicode_combining_class(0x0316) != 220 { ok = false; }
  if l10n_unicode_combining_class(0x0334) != 1 { ok = false; }
  if l10n_unicode_combining_class(0x20D0) != 230 { ok = false; }
  if l10n_unicode_combining_class(0x00E9) != 0 { ok = false; }
  if l10n_unicode_combining_class(0x0041) != 0 { ok = false; }
  return assert(ok, "combining class: canonical mark classes 1/202/220/230 and starters at 0");
}

fn t5() -> TestResult {
  var ok = streq(l10n_unicode_script(0x00E9), "Latin");
  if !streq(l10n_unicode_script(0x03B1), "Greek") { ok = false; }
  if !streq(l10n_unicode_script(0x0416), "Cyrillic") { ok = false; }
  if !streq(l10n_unicode_script(0x0031), "Common") { ok = false; }
  if !streq(l10n_unicode_script(0x0301), "Inherited") { ok = false; }
  if !streq(l10n_unicode_block(0x00E9), "Latin-1 Supplement") { ok = false; }
  if !streq(l10n_unicode_block(0x03B1), "Greek and Coptic") { ok = false; }
  if !streq(l10n_unicode_block(0x0416), "Cyrillic") { ok = false; }
  if !streq(l10n_unicode_block(0x0301), "Combining Diacritical Marks") { ok = false; }
  if !streq(l10n_unicode_block(0x1F600), "Emoticons") { ok = false; }
  return assert(ok, "script and block lookup: Latin/Greek/Cyrillic/Common/Inherited and blocks");
}

fn t6() -> TestResult {
  let up_e = l10n_unicode_upper_cp(0x00E9);
  let lo_e = l10n_unicode_lower_cp(0x00C9);
  let up_ss = l10n_unicode_upper_cp(0x00DF);
  let lo_i = l10n_unicode_lower_cp(0x0130);
  let ti_dz = l10n_unicode_title_cp(0x01C6);
  let fo_ss = l10n_unicode_fold_cp(0x00DF);
  let fo_mu = l10n_unicode_fold_cp(0x00B5);
  let fo_sig = l10n_unicode_fold_cp(0x03C2);
  let up_dot = l10n_unicode_upper_cp(0x0131);
  var ok = v1(&up_e, 0x00C9);
  if !v1(&lo_e, 0x00E9) { ok = false; }
  if !v2(&up_ss, 0x0053, 0x0053) { ok = false; }
  if !v2(&lo_i, 0x0069, 0x0307) { ok = false; }
  if !v1(&ti_dz, 0x01C5) { ok = false; }
  if !v2(&fo_ss, 0x0073, 0x0073) { ok = false; }
  if !v1(&fo_mu, 0x03BC) { ok = false; }
  if !v1(&fo_sig, 0x03C3) { ok = false; }
  if !v1(&up_dot, 0x0049) { ok = false; }
  return assert(ok, "code point case maps: full upper/lower, ligature folds, title digraph, dotless i");
}

fn t7() -> TestResult {
  var ok = streq(l10n_unicode_upper("straße"), "STRASSE");
  if !streq(l10n_unicode_upper("café"), "CAFÉ") { ok = false; }
  if !streq(l10n_unicode_lower("İSTANBUL"), "i\u{0307}stanbul") { ok = false; }
  if !streq(l10n_unicode_title("ǆungla"), "ǅungla") { ok = false; }
  if !streq(l10n_unicode_title("hello world"), "Hello World") { ok = false; }
  if !streq(l10n_unicode_upper("ﬁ"), "FI") { ok = false; }
  if !streq(l10n_unicode_title("ﬁ"), "Fi") { ok = false; }
  return assert(ok, "string case: full uppercase expansion, dotted I lowercase, word-aware title");
}

fn t8() -> TestResult {
  var ok = streq(l10n_unicode_fold("Straße"), "strasse");
  if !streq(l10n_unicode_fold("ΣΟΦΟΣ"), "σοφοσ") { ok = false; }
  if !streq(l10n_unicode_fold("ς"), "σ") { ok = false; }
  if !streq(l10n_unicode_fold("µ"), "μ") { ok = false; }
  if !streq(l10n_unicode_fold("İ"), "i\u{0307}") { ok = false; }
  if !streq(l10n_unicode_fold_turkic("Iİ"), "ıi") { ok = false; }
  return assert(ok, "case folding: sharp s, final sigma, micro sign, and Turkic I/dotted I");
}

fn t9() -> TestResult {
  var ok = streq(l10n_unicode_nfd("é"), "e\u{0301}");
  if !streq(l10n_unicode_nfd("ệ"), "e\u{0323}\u{0302}") { ok = false; }
  if !streq(l10n_unicode_nfd("ǭ"), "o\u{0328}\u{0304}") { ok = false; }
  if !streq(l10n_unicode_nfd("ﬁ"), "ﬁ") { ok = false; }
  if !streq(l10n_unicode_nfd("ª"), "ª") { ok = false; }
  return assert(ok, "NFD: canonical decompositions, recursive base expansion, no compat folding");
}

fn t10() -> TestResult {
  let reordered = l10n_unicode_nfd("e\u{0302}\u{0323}");
  var ok = streq(reordered, "e\u{0323}\u{0302}");
  if !streq(reordered, l10n_unicode_nfd("e\u{0323}\u{0302}")) { ok = false; }
  if !streq(l10n_unicode_nfd("A\u{030A}"), "A\u{030A}") { ok = false; }
  return assert(ok, "NFD canonical ordering: ccc 220 (dot below) sorts before ccc 230 (circumflex)");
}

fn t11() -> TestResult {
  var ok = streq(l10n_unicode_nfc("e\u{0301}"), "é");
  if !streq(l10n_unicode_nfc("A\u{030A}"), "Å") { ok = false; }
  if !streq(l10n_unicode_nfc("e\u{0323}\u{0302}"), "ệ") { ok = false; }
  if !streq(l10n_unicode_nfc("o\u{0328}\u{0304}"), "ǭ") { ok = false; }
  if !streq(l10n_unicode_nfc("\u{0308}\u{0301}"), "\u{0308}\u{0301}") { ok = false; }
  return assert(ok, "NFC: composition after reordering, U+0344 composition exclusion honored");
}

fn t12() -> TestResult {
  var ok = streq(l10n_unicode_nfkd("ﬁ"), "fi");
  if !streq(l10n_unicode_nfkd("²"), "2") { ok = false; }
  if !streq(l10n_unicode_nfkd("½"), "1\u{2044}2") { ok = false; }
  if !streq(l10n_unicode_nfkd("é"), "e\u{0301}") { ok = false; }
  return assert(ok, "NFKD: compatibility folds for ligature, superscript and fraction forms");
}

fn t13() -> TestResult {
  var ok = streq(l10n_unicode_nfkc("ﬁ"), "fi");
  if !streq(l10n_unicode_nfkc("２"), "2") { ok = false; }
  if !streq(l10n_unicode_nfkc("ª"), "a") { ok = false; }
  if !streq(l10n_unicode_nfkc("é"), "é") { ok = false; }
  if !streq(l10n_unicode_nfkc("½"), "1\u{2044}2") { ok = false; }
  return assert(ok, "NFKC: compatibility decomposition followed by canonical composition");
}

fn t14() -> TestResult {
  var ok = l10n_unicode_is_normalized("é", "NFC");
  if l10n_unicode_is_normalized("e\u{0301}", "NFC") { ok = false; }
  if !l10n_unicode_is_normalized("e\u{0301}", "NFD") { ok = false; }
  if l10n_unicode_is_normalized("é", "NFD") { ok = false; }
  if l10n_unicode_is_normalized("é", "XYZ") { ok = false; }
  if !norm_is("e\u{0301}", "NFC", "é") { ok = false; }
  if !norm_is("ﬁ", "NFKD", "fi") { ok = false; }
  if !norm_err_is("abc", "XYZ", "l10n-unicode: unknown normalization form: XYZ") { ok = false; }
  return assert(ok, "is_normalized and normalize(Result): forms, unknown-form error, quick checks");
}

fn t15() -> TestResult {
  var ok = l10n_unicode_grapheme_count("abc") == 3;
  if l10n_unicode_grapheme_count("a\u{0301}b") != 2 { ok = false; }
  if l10n_unicode_grapheme_count("") != 0 { ok = false; }
  if l10n_unicode_grapheme_count("ab") != 2 { ok = false; }
  let b = l10n_unicode_grapheme_boundaries("a\u{0301}b");
  if !bounds3_ok(&b, 0, 3, 4) { ok = false; }
  return assert(ok, "graphemes: ASCII counting, base+mark cluster, byte offsets 0/3/4");
}

fn t16() -> TestResult {
  var ok = l10n_unicode_grapheme_count("\r\n") == 1;
  if l10n_unicode_grapheme_count("\r\n\r\n") != 2 { ok = false; }
  if l10n_unicode_grapheme_count("\u{1F1E6}\u{1F1E7}\u{1F1E8}") != 2 { ok = false; }
  if l10n_unicode_grapheme_count("\u{1F469}\u{200D}\u{1F469}") != 1 { ok = false; }
  if l10n_unicode_grapheme_count("\u{1F44D}\u{1F3FB}") != 1 { ok = false; }
  if l10n_unicode_grapheme_count("e\u{0301}\u{0302}") != 1 { ok = false; }
  return assert(ok, "graphemes: CRLF, RI flag pairing, ZWJ emoji, skin tone, extend chains");
}

fn t17() -> TestResult {
  var ok = l10n_unicode_word_count("hello world") == 2;
  if l10n_unicode_word_count("don't stop") != 2 { ok = false; }
  if l10n_unicode_word_count("a-b") != 2 { ok = false; }
  if l10n_unicode_word_count("x1 y2") != 2 { ok = false; }
  if l10n_unicode_word_count("3.14") != 1 { ok = false; }
  if l10n_unicode_word_count("   ") != 0 { ok = false; }
  return assert(ok, "words: UAX #29 mid-letter apostrophe, numeric keep, punctuation split, spaces");
}

fn t18() -> TestResult {
  var ok = true;
  let b1 = l10n_unicode_word_boundaries("don't stop");
  if !bounds4_ok(&b1, 0, 5, 6, 10) { ok = false; }
  let b2 = l10n_unicode_word_boundaries("a b");
  if !bounds4_ok(&b2, 0, 1, 2, 3) { ok = false; }
  return assert(ok, "word boundaries: byte offsets include 0 and end, apostrophe keeps one word");
}

fn t19() -> TestResult {
  var ok = l10n_unicode_sentence_count("One. Two! Three?") == 3;
  let b = l10n_unicode_sentence_boundaries("One. Two! Three?");
  if !bounds4_ok(&b, 0, 5, 10, 16) { ok = false; }
  if l10n_unicode_sentence_count("3.14 is pi.") != 1 { ok = false; }
  if l10n_unicode_sentence_count("Wait... What? Now!") != 3 { ok = false; }
  if l10n_unicode_sentence_count("") != 0 { ok = false; }
  return assert(ok, "sentences: terminator runs, decimal point guard, ellipsis, offsets");
}

fn t20() -> TestResult {
  var ok = l10n_unicode_sentence_count("\"Hi.\" Yes.") == 2;
  let b = l10n_unicode_sentence_boundaries("\"Hi.\" Yes.");
  if !bounds3_ok(&b, 0, 6, 10) { ok = false; }
  if l10n_unicode_sentence_count("Mr. Smith") != 2 { ok = false; }
  if l10n_unicode_sentence_count("Hello.World") != 1 { ok = false; }
  return assert(ok, "sentences: closing quote kept, no abbreviation dictionary, no break without space");
}

fn t21() -> TestResult {
  let covered = tables.tbl_covered();
  var ok = covered.len() >= 2;
  var i = 0;
  while i + 1 < covered.len() {
    let lo: Int = covered[i];
    let hi: Int = covered[i + 1];
    if lo > hi { ok = false; }
    if i > 0 {
      let prev_hi: Int = covered[i - 1];
      if lo <= prev_hi { ok = false; }
    }
    i = i + 2;
  }
  var cp = 0;
  while cp < 0x036F {
    if l10n_unicode_category_id(cp) < 0 { ok = false; }
    let c = l10n_unicode_combining_class(cp);
    if c < 0 || c > 240 { ok = false; }
    cp = cp + 13;
  }
  return assert(ok, "coverage table integrity: sorted disjoint ranges, full classification sweep");
}

fn t22() -> TestResult {
  let cat = tables.tbl_cat();
  let upper = tables.tbl_upper_simple();
  let multi = tables.tbl_multi();
  let canon = tables.tbl_canon();
  let wb = tables.tbl_wb();
  var ok = cat.len() % 3 == 0;
  if upper.len() % 2 != 0 { ok = false; }
  if multi.len() % 6 != 0 { ok = false; }
  if canon.len() % 6 != 0 { ok = false; }
  if wb.len() % 3 != 0 { ok = false; }
  var i = 1;
  while i < upper.len() / 2 {
    let prev: Int = upper[(i - 1) * 2];
    let cur: Int = upper[i * 2];
    if cur <= prev { ok = false; }
    i = i + 1;
  }
  i = 1;
  while i < canon.len() / 6 {
    let prev: Int = canon[(i - 1) * 6];
    let cur: Int = canon[i * 6];
    if cur <= prev { ok = false; }
    i = i + 1;
  }
  return assert(ok, "table shapes: strides divide evenly, case and decomposition keys ascending");
}

fn t23() -> TestResult {
  var ok = streq(l10n_unicode_upper("a\u{0001}b"), "A\u{0001}B");
  if !streq(l10n_unicode_fold("a\u{0001}b"), "a\u{0001}b") { ok = false; }
  if !streq(l10n_unicode_nfd("a\u{0001}b"), "a\u{0001}b") { ok = false; }
  if l10n_unicode_grapheme_count("a\u{0001}b") != 3 { ok = false; }
  let b = l10n_unicode_grapheme_boundaries("a\u{0001}b");
  if !bounds4_ok(&b, 0, 1, 2, 3) { ok = false; }
  return assert(ok, "control characters pass through case/norm and break grapheme clusters");
}

fn t24() -> TestResult {
  let s = "e\u{0302}\u{0323}Åﬁß";
  let d = l10n_unicode_nfd(s);
  let c = l10n_unicode_nfc(s);
  let kd = l10n_unicode_nfkd(s);
  let kc = l10n_unicode_nfkc(s);
  var ok = streq(l10n_unicode_nfd(d), d);
  if !streq(l10n_unicode_nfc(c), c) { ok = false; }
  if !streq(l10n_unicode_nfkd(kd), kd) { ok = false; }
  if !streq(l10n_unicode_nfkc(kc), kc) { ok = false; }
  if !streq(l10n_unicode_nfc(d), c) { ok = false; }
  if !streq(l10n_unicode_nfd("é"), l10n_unicode_nfd("e\u{0301}")) { ok = false; }
  return assert(ok, "normalization idempotence and NFD/NFC round-trip on a mixed string");
}

fn main() -> Int {
  io.println("=== xiom.l10n-unicode conformance tests ===");
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
  if failed == 0 {
    io.println("xiom.l10n-unicode: all tests passed");
  } else {
    io.println("xiom.l10n-unicode: tests failed");
  }
  return failed;
}
