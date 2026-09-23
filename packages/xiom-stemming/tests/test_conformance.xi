// XIOM -- xiom.stemming conformance tests (34 checks)
// Port task: prove the pure-XIOM Porter stemmer against the classic fixtures.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module stemming_tests
use xiom.io; use xiom.test; use xiom.stemming;
use xiom.string.compare;

// All Str equality goes through str_compare: `==` between Str values read
// from a Vec[Str] (or returned by stem_all) can lower to a pointer compare.

fn eq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn elem_is(v: &Vec[Str], i: Int, want: Str) -> Bool {
  if i < 0 || i >= v.len() { return false; }
  return compare.str_compare(v[i], want) == 0;
}

fn t01_step1a_sses() -> TestResult {
  var ok = eq(stem("caresses"), "caress");
  if !eq(stem("possesses"), "possess") { ok = false; }
  return assert(ok, "step 1a: SSES -> SS");
}

fn t02_step1a_ies() -> TestResult {
  var ok = eq(stem("ponies"), "poni");
  if !eq(stem("ties"), "ti") { ok = false; }
  return assert(ok, "step 1a: IES -> I");
}

fn t03_step1a_ss() -> TestResult {
  var ok = eq(stem("caress"), "caress");
  if !eq(stem("press"), "press") { ok = false; }
  return assert(ok, "step 1a: SS -> SS is kept");
}

fn t04_step1a_s() -> TestResult {
  var ok = eq(stem("cats"), "cat");
  if !eq(stem("dogs"), "dog") { ok = false; }
  return assert(ok, "step 1a: S -> empty");
}

fn t05_step1b_eed() -> TestResult {
  var ok = eq(stem("feed"), "feed");
  if !eq(stem("agreed"), "agre") { ok = false; }
  return assert(ok, "step 1b: (m>0) EED -> EE, m==0 kept");
}

fn t06_step1b_ed() -> TestResult {
  var ok = eq(stem("plastered"), "plaster");
  if !eq(stem("bled"), "bled") { ok = false; }
  return assert(ok, "step 1b: (*v*) ED, vowel-less stem kept");
}

fn t07_step1b_ed_at() -> TestResult {
  return assert(eq(stem("conflated"), "conflat"), "step 1b: ED -> AT -> ATE -> E dropped");
}

fn t08_step1b_ed_bl() -> TestResult {
  return assert(eq(stem("troubled"), "troubl"), "step 1b: ED -> BL -> BLE -> E dropped");
}

fn t09_step1b_ed_iz() -> TestResult {
  return assert(eq(stem("sized"), "size"), "step 1b: ED -> IZ -> IZE survives step 5a");
}

fn t10_step1b_ing() -> TestResult {
  var ok = eq(stem("motoring"), "motor");
  if !eq(stem("sing"), "sing") { ok = false; }
  return assert(ok, "step 1b: (*v*) ING, vowel-less stem kept");
}

fn t11_step1b_double() -> TestResult {
  var ok = eq(stem("hopping"), "hop");
  if !eq(stem("tanned"), "tan") { ok = false; }
  return assert(ok, "step 1b: double consonant loses one letter");
}

fn t12_step1b_double_exception() -> TestResult {
  var ok = eq(stem("falling"), "fall");
  if !eq(stem("hissing"), "hiss") { ok = false; }
  if !eq(stem("fizzed"), "fizz") { ok = false; }
  return assert(ok, "step 1b: final l/s/z double is kept");
}

fn t13_step1b_cvc_e() -> TestResult {
  var ok = eq(stem("filing"), "file");
  if !eq(stem("failing"), "fail") { ok = false; }
  return assert(ok, "step 1b: m==1 and cvc gains E, other m==1 does not");
}

fn t14_step1c_y() -> TestResult {
  var ok = eq(stem("happy"), "happi");
  if !eq(stem("sky"), "sky") { ok = false; }
  return assert(ok, "step 1c: (*v*) Y -> I");
}

fn t15_step2_ational() -> TestResult {
  var ok = eq(stem("relational"), "relat");
  if !eq(stem("conditional"), "condit") { ok = false; }
  return assert(ok, "step 2: ATIONAL/TIONAL and the later steps");
}

fn t16_step2_tional_zero_measure() -> TestResult {
  return assert(eq(stem("rational"), "ration"), "step 2: zero-measure stem falls through to step 4 AL");
}

fn t17_step2_enci() -> TestResult {
  return assert(eq(stem("valency"), "valenc"), "step 2: ENCI -> ENCE, then step 5a drops E");
}

fn t18_step3_ical() -> TestResult {
  return assert(eq(stem("electrical"), "electr"), "step 3: ICAL -> IC then step 4 IC");
}

fn t19_step3_iciti() -> TestResult {
  return assert(eq(stem("electricity"), "electr"), "step 3: ICITI -> IC then step 4 IC");
}

fn t20_step3_ative() -> TestResult {
  return assert(eq(stem("operative"), "oper"), "step 3: ATIVE -> empty");
}

fn t21_step3_alize() -> TestResult {
  var ok = eq(stem("equalize"), "equal");
  if !eq(stem("formalize"), "formal") { ok = false; }
  return assert(ok, "step 3: ALIZE -> AL");
}

fn t22_step3_ness() -> TestResult {
  return assert(eq(stem("goodness"), "good"), "step 3: NESS -> empty");
}

fn t23_step4_ance_ent() -> TestResult {
  var ok = eq(stem("allowance"), "allow");
  if !eq(stem("dependent"), "depend") { ok = false; }
  return assert(ok, "step 4: ANCE and ENT need m>1");
}

fn t24_step4_ion() -> TestResult {
  return assert(eq(stem("adoption"), "adopt"), "step 4: ION after S or T");
}

fn t25_step4_ive_ous() -> TestResult {
  var ok = eq(stem("effective"), "effect");
  if !eq(stem("marvelous"), "marvel") { ok = false; }
  return assert(ok, "step 4: IVE and OUS need m>1");
}

fn t26_step5a_e() -> TestResult {
  var ok = eq(stem("probate"), "probat");
  if !eq(stem("rate"), "rate") { ok = false; }
  return assert(ok, "step 5a: E dropped for m>1, kept for m==1 cvc");
}

fn t27_step5b_l() -> TestResult {
  var ok = eq(stem("controlling"), "control");
  if !eq(stem("roll"), "roll") { ok = false; }
  return assert(ok, "step 5b: m>1 double L loses one letter");
}

fn t28_measure_classic() -> TestResult {
  var ok = stem_measure("tr") == 0;
  if stem_measure("tree") != 0 { ok = false; }
  if stem_measure("trouble") != 1 { ok = false; }
  if stem_measure("oats") != 1 { ok = false; }
  if stem_measure("trees") != 1 { ok = false; }
  if stem_measure("troubles") != 2 { ok = false; }
  if stem_measure("private") != 2 { ok = false; }
  if stem_measure("by") != 0 { ok = false; }
  return assert(ok, "stem_measure matches Porter's m examples");
}

fn t29_measure_edges() -> TestResult {
  var ok = stem_measure("") == 0;
  if stem_measure("a") != 0 { ok = false; }
  if stem_measure("ab") != 1 { ok = false; }
  if stem_measure("ba") != 0 { ok = false; }
  return assert(ok, "stem_measure handles empty and short words");
}

fn t30_stem_all_order() -> TestResult {
  var words = Vec[Str].new();
  words.push("caresses");
  words.push("ponies");
  words.push("cats");
  words.push("sky");
  let out = stem_all(&words);
  var ok = out.len() == 4;
  if !elem_is(&out, 0, "caress") { ok = false; }
  if !elem_is(&out, 1, "poni") { ok = false; }
  if !elem_is(&out, 2, "cat") { ok = false; }
  if !elem_is(&out, 3, "sky") { ok = false; }
  return assert(ok, "stem_all preserves input order and length");
}

fn t31_stem_all_empty() -> TestResult {
  var words = Vec[Str].new();
  let out = stem_all(&words);
  var ok = out.len() == 0;
  return assert(ok, "stem_all of an empty vector is empty");
}

fn t32_unchanged_short() -> TestResult {
  var ok = eq(stem(""), "");
  if !eq(stem("a"), "a") { ok = false; }
  if !eq(stem("ab"), "ab") { ok = false; }
  if !eq(stem("is"), "is") { ok = false; }
  if !eq(stem("as"), "as") { ok = false; }
  return assert(ok, "words shorter than three bytes are unchanged");
}

fn t33_unchanged_non_ascii_upper() -> TestResult {
  var ok = eq(stem("café"), "café");
  if !eq(stem("naïve"), "naïve") { ok = false; }
  if !eq(stem("Ärger"), "Ärger") { ok = false; }
  if !eq(stem("日本語"), "日本語") { ok = false; }
  if !eq(stem("Hello"), "Hello") { ok = false; }
  if !eq(stem("CATS"), "CATS") { ok = false; }
  if !eq(stem("don't"), "don't") { ok = false; }
  return assert(ok, "uppercase, punctuation and non-ASCII words are unchanged");
}

fn t34_idempotent() -> TestResult {
  var ok = eq(stem(stem("caresses")), "caress");
  if !eq(stem(stem("relational")), "relat") { ok = false; }
  if !eq(stem(stem("happy")), "happi") { ok = false; }
  if !eq(stem(stem("ponies")), "poni") { ok = false; }
  return assert(ok, "stemming a stem is a no-op");
}

fn main() -> Int {
  io.println("=== xiom.stemming conformance tests ===");
  var failed: Int = 0;
  let r1 = t01_step1a_sses();
  if r1.passed { io.println("  [PASS] " + r1.name); } else { io.println("  [FAIL] " + r1.name); failed = failed + 1; }
  let r2 = t02_step1a_ies();
  if r2.passed { io.println("  [PASS] " + r2.name); } else { io.println("  [FAIL] " + r2.name); failed = failed + 1; }
  let r3 = t03_step1a_ss();
  if r3.passed { io.println("  [PASS] " + r3.name); } else { io.println("  [FAIL] " + r3.name); failed = failed + 1; }
  let r4 = t04_step1a_s();
  if r4.passed { io.println("  [PASS] " + r4.name); } else { io.println("  [FAIL] " + r4.name); failed = failed + 1; }
  let r5 = t05_step1b_eed();
  if r5.passed { io.println("  [PASS] " + r5.name); } else { io.println("  [FAIL] " + r5.name); failed = failed + 1; }
  let r6 = t06_step1b_ed();
  if r6.passed { io.println("  [PASS] " + r6.name); } else { io.println("  [FAIL] " + r6.name); failed = failed + 1; }
  let r7 = t07_step1b_ed_at();
  if r7.passed { io.println("  [PASS] " + r7.name); } else { io.println("  [FAIL] " + r7.name); failed = failed + 1; }
  let r8 = t08_step1b_ed_bl();
  if r8.passed { io.println("  [PASS] " + r8.name); } else { io.println("  [FAIL] " + r8.name); failed = failed + 1; }
  let r9 = t09_step1b_ed_iz();
  if r9.passed { io.println("  [PASS] " + r9.name); } else { io.println("  [FAIL] " + r9.name); failed = failed + 1; }
  let r10 = t10_step1b_ing();
  if r10.passed { io.println("  [PASS] " + r10.name); } else { io.println("  [FAIL] " + r10.name); failed = failed + 1; }
  let r11 = t11_step1b_double();
  if r11.passed { io.println("  [PASS] " + r11.name); } else { io.println("  [FAIL] " + r11.name); failed = failed + 1; }
  let r12 = t12_step1b_double_exception();
  if r12.passed { io.println("  [PASS] " + r12.name); } else { io.println("  [FAIL] " + r12.name); failed = failed + 1; }
  let r13 = t13_step1b_cvc_e();
  if r13.passed { io.println("  [PASS] " + r13.name); } else { io.println("  [FAIL] " + r13.name); failed = failed + 1; }
  let r14 = t14_step1c_y();
  if r14.passed { io.println("  [PASS] " + r14.name); } else { io.println("  [FAIL] " + r14.name); failed = failed + 1; }
  let r15 = t15_step2_ational();
  if r15.passed { io.println("  [PASS] " + r15.name); } else { io.println("  [FAIL] " + r15.name); failed = failed + 1; }
  let r16 = t16_step2_tional_zero_measure();
  if r16.passed { io.println("  [PASS] " + r16.name); } else { io.println("  [FAIL] " + r16.name); failed = failed + 1; }
  let r17 = t17_step2_enci();
  if r17.passed { io.println("  [PASS] " + r17.name); } else { io.println("  [FAIL] " + r17.name); failed = failed + 1; }
  let r18 = t18_step3_ical();
  if r18.passed { io.println("  [PASS] " + r18.name); } else { io.println("  [FAIL] " + r18.name); failed = failed + 1; }
  let r19 = t19_step3_iciti();
  if r19.passed { io.println("  [PASS] " + r19.name); } else { io.println("  [FAIL] " + r19.name); failed = failed + 1; }
  let r20 = t20_step3_ative();
  if r20.passed { io.println("  [PASS] " + r20.name); } else { io.println("  [FAIL] " + r20.name); failed = failed + 1; }
  let r21 = t21_step3_alize();
  if r21.passed { io.println("  [PASS] " + r21.name); } else { io.println("  [FAIL] " + r21.name); failed = failed + 1; }
  let r22 = t22_step3_ness();
  if r22.passed { io.println("  [PASS] " + r22.name); } else { io.println("  [FAIL] " + r22.name); failed = failed + 1; }
  let r23 = t23_step4_ance_ent();
  if r23.passed { io.println("  [PASS] " + r23.name); } else { io.println("  [FAIL] " + r23.name); failed = failed + 1; }
  let r24 = t24_step4_ion();
  if r24.passed { io.println("  [PASS] " + r24.name); } else { io.println("  [FAIL] " + r24.name); failed = failed + 1; }
  let r25 = t25_step4_ive_ous();
  if r25.passed { io.println("  [PASS] " + r25.name); } else { io.println("  [FAIL] " + r25.name); failed = failed + 1; }
  let r26 = t26_step5a_e();
  if r26.passed { io.println("  [PASS] " + r26.name); } else { io.println("  [FAIL] " + r26.name); failed = failed + 1; }
  let r27 = t27_step5b_l();
  if r27.passed { io.println("  [PASS] " + r27.name); } else { io.println("  [FAIL] " + r27.name); failed = failed + 1; }
  let r28 = t28_measure_classic();
  if r28.passed { io.println("  [PASS] " + r28.name); } else { io.println("  [FAIL] " + r28.name); failed = failed + 1; }
  let r29 = t29_measure_edges();
  if r29.passed { io.println("  [PASS] " + r29.name); } else { io.println("  [FAIL] " + r29.name); failed = failed + 1; }
  let r30 = t30_stem_all_order();
  if r30.passed { io.println("  [PASS] " + r30.name); } else { io.println("  [FAIL] " + r30.name); failed = failed + 1; }
  let r31 = t31_stem_all_empty();
  if r31.passed { io.println("  [PASS] " + r31.name); } else { io.println("  [FAIL] " + r31.name); failed = failed + 1; }
  let r32 = t32_unchanged_short();
  if r32.passed { io.println("  [PASS] " + r32.name); } else { io.println("  [FAIL] " + r32.name); failed = failed + 1; }
  let r33 = t33_unchanged_non_ascii_upper();
  if r33.passed { io.println("  [PASS] " + r33.name); } else { io.println("  [FAIL] " + r33.name); failed = failed + 1; }
  let r34 = t34_idempotent();
  if r34.passed { io.println("  [PASS] " + r34.name); } else { io.println("  [FAIL] " + r34.name); failed = failed + 1; }
  if failed == 0 {
    io.println("xiom.stemming: all tests passed");
  } else {
    io.println("xiom.stemming: tests failed");
  }
  return failed;
}
