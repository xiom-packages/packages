// XIOM -- xiom.l10n.name conformance tests (21 checks)
// Port task: prove the pure-XIOM xiom.l10n.name module against its documented
// ordering, list, initials and honorific contract.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Provenance: every fixture is a synthetic name built in-test (no real
// personal data). The ordering and conjunction rules pinned here are the
// v0.1.0 rules of the module under test (see SPEC.md).
//
// Compiler notes (v0.62.0): all Str equality goes through
// compare.str_compare (via streq) because `==` on Str read from a Vec[Str] is
// miscompiled (BUG 17 family); Vec[Str] elements are always bound to typed
// locals before comparison; test dispatch is a direct call chain
// (t1..t21 from main), never a Vec[fn] table.

module l10n_name_tests
use xiom.io; use xiom.test; use xiom.l10n.name;
use xiom.string.compare;

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn pn(pre: Str, giv: Str, mid: Str, fam: Str, suf: Str) -> PersonName {
  let p = PersonName{ prefix: pre; given: giv; middle: mid; family: fam; suffix: suf };
  return p;
}

fn disp(locale: Str, pre: Str, giv: Str, mid: Str, fam: Str, suf: Str) -> Str {
  let p = pn(pre, giv, mid, fam, suf);
  return name_display(locale, &p);
}

fn key_of(locale: Str, pre: Str, giv: Str, mid: Str, fam: Str, suf: Str) -> Str {
  let p = pn(pre, giv, mid, fam, suf);
  return name_sort_key(locale, &p);
}

fn initials_of(giv: Str, mid: Str) -> Str {
  let p = pn("", giv, mid, "", "");
  return name_initials(&p);
}

fn mk1(a: &PersonName) -> NameList {
  var l = name_list_new();
  name_list_push(&mut l, a);
  return l;
}

fn mk2(a: &PersonName, b: &PersonName) -> NameList {
  var l = name_list_new();
  name_list_push(&mut l, a);
  name_list_push(&mut l, b);
  return l;
}

fn mk3(a: &PersonName, b: &PersonName, c: &PersonName) -> NameList {
  var l = name_list_new();
  name_list_push(&mut l, a);
  name_list_push(&mut l, b);
  name_list_push(&mut l, c);
  return l;
}

fn list3_en() -> NameList {
  let a = pn("", "Alice", "", "Smith", "");
  let b = pn("", "Bob", "", "Jones", "");
  let c = pn("", "Carol", "", "Lee", "");
  return mk3(&a, &b, &c);
}

// ---------------------------------------------------------------------------
// Checks
// ---------------------------------------------------------------------------

fn t1() -> TestResult {
  var ok = streq(disp("en", "Dr.", "John", "Paul", "Smith", "Jr."), "Dr. John Paul Smith Jr.");
  if !streq(disp("en-US", "", "John", "Paul", "Smith", ""), "John Paul Smith") { ok = false; }
  if !streq(disp("", "", "John", "Paul", "Smith", ""), "John Paul Smith") { ok = false; }
  return assert(ok, "given-first default orders prefix given middle family suffix");
}

fn t2() -> TestResult {
  var ok = streq(disp("en", "", "John", "", "Smith", ""), "John Smith");
  if !streq(disp("en", "Dr.", "John", "", "", "Jr."), "Dr. John Jr.") { ok = false; }
  if !streq(disp("en", "", "", "", "Smith", "Jr."), "Smith Jr.") { ok = false; }
  if !streq(disp("en", "Dr.", "", "", "Smith", ""), "Dr. Smith") { ok = false; }
  return assert(ok, "empty parts are absent: no doubled or dangling spaces");
}

fn t3() -> TestResult {
  var ok = streq(disp("en", "", "", "", "", ""), "");
  if !streq(disp("zh", "", "", "", "", ""), "") { ok = false; }
  if !streq(disp("xx", "", "John", "", "Smith", ""), "John Smith") { ok = false; }
  if !streq(disp("unknown-locale", "", "John", "", "Smith", ""), "John Smith") { ok = false; }
  return assert(ok, "all-empty name renders \"\"; unknown locale falls back to given-first");
}

fn t4() -> TestResult {
  var ok = streq(disp("zh", "", "Wei", "", "Li", ""), "Li Wei");
  if !streq(disp("zh-CN", "", "Wei", "", "Li", ""), "Li Wei") { ok = false; }
  if !streq(disp("ja", "", "Wei", "", "Li", ""), "Li Wei") { ok = false; }
  if !streq(disp("ko", "", "Wei", "", "Li", ""), "Li Wei") { ok = false; }
  if !streq(disp("hu", "", "Wei", "", "Li", ""), "Li Wei") { ok = false; }
  return assert(ok, "family-first locales zh/ja/ko/hu order family given");
}

fn t5() -> TestResult {
  var ok = streq(disp("zh", "Dr.", "Wei", "Ming", "Li", "Jr."), "Dr. Li Wei Jr.");
  if !streq(disp("ja-JP", "Dr.", "Wei", "Ming", "Li", ""), "Dr. Li Wei") { ok = false; }
  if !streq(disp("ko_KR", "", "Wei", "Ming", "Li", "Jr."), "Li Wei Jr.") { ok = false; }
  return assert(ok, "family-first places prefix first, suffix last, middle omitted (v0.1.0)");
}

fn t6() -> TestResult {
  var ok = name_is_family_first_locale("zh");
  if !name_is_family_first_locale("zh-Hans") { ok = false; }
  if !name_is_family_first_locale("zh_CN") { ok = false; }
  if !name_is_family_first_locale("ZH") { ok = false; }
  if !name_is_family_first_locale("Ko-KR") { ok = false; }
  if !name_is_family_first_locale("hu-HU") { ok = false; }
  if name_is_family_first_locale("en") { ok = false; }
  if name_is_family_first_locale("") { ok = false; }
  if name_is_family_first_locale("xx") { ok = false; }
  return assert(ok, "locale classification: primary subtag, ASCII case-insensitive, default false");
}

fn t7() -> TestResult {
  let l = list3_en();
  var ok = streq(name_display_list("en", &l, 0), "Alice Smith, Bob Jones and Carol Lee");
  if name_list_len(&l) != 3 { ok = false; }
  return assert(ok, "list (default): comma joins with \" and \" before the last item");
}

fn t8() -> TestResult {
  let a = pn("", "Alice", "", "Smith", "");
  let b = pn("", "Bob", "", "Jones", "");
  let l2 = mk2(&a, &b);
  let l1 = mk1(&a);
  var ok = streq(name_display_list("en", &l2, 0), "Alice Smith and Bob Jones");
  if !streq(name_display_list("en", &l1, 0), "Alice Smith") { ok = false; }
  return assert(ok, "list (default): two items join with \" and \"; one item stands alone");
}

fn t9() -> TestResult {
  let a = pn("", "Alice", "", "Smith", "");
  let none = pn("", "", "", "", "");
  let b = pn("", "Bob", "", "Jones", "");
  let l = mk3(&a, &none, &b);
  var ok = streq(name_display_list("en", &l, 0), "Alice Smith and Bob Jones");
  if !streq(name_display_list("en", &l, 2), "Alice Smith…") { ok = false; }
  return assert(ok, "list: names that render empty are skipped, including inside a truncated window");
}

fn t10() -> TestResult {
  let l = list3_en();
  var ok = streq(name_display_list("zh", &l, 0), "Smith Alice、Jones Bob、Lee Carol");
  if !streq(name_display_list("ja", &l, 0), "Smith Alice・Jones Bob・Lee Carol") { ok = false; }
  if !streq(name_display_list("ko", &l, 0), "Smith Alice・Jones Bob・Lee Carol") { ok = false; }
  return assert(ok, "list (zh): ideographic-comma join; list (ja/ko): middle-dot join");
}

fn t11() -> TestResult {
  let l = list3_en();
  var ok = streq(name_display_list("hu", &l, 0), "Smith Alice, Jones Bob and Lee Carol");
  if !streq(name_display_list("xx", &l, 0), "Alice Smith, Bob Jones and Carol Lee") { ok = false; }
  return assert(ok, "list (hu and unknown locales): default comma + \" and \" style");
}

fn t12() -> TestResult {
  let l = list3_en();
  var ok = streq(name_display_list("en", &l, 2), "Alice Smith, Bob Jones…");
  if !streq(name_display_list("en", &l, 1), "Alice Smith…") { ok = false; }
  if !streq(name_display_list("zh", &l, 2), "Smith Alice、Jones Bob…") { ok = false; }
  return assert(ok, "list truncation: first max_items names plus the ellipsis marker");
}

fn t13() -> TestResult {
  let l = list3_en();
  var ok = streq(name_display_list("en", &l, 3), "Alice Smith, Bob Jones and Carol Lee");
  if !streq(name_display_list("en", &l, 5), "Alice Smith, Bob Jones and Carol Lee") { ok = false; }
  if !streq(name_display_list("en", &l, -1), "Alice Smith, Bob Jones and Carol Lee") { ok = false; }
  let n1 = pn("", "", "", "", "");
  let n2 = pn("", "", "", "", "");
  let n3 = pn("", "", "", "", "");
  let empties = mk3(&n1, &n2, &n3);
  if !streq(name_display_list("en", &empties, 2), "") { ok = false; }
  return assert(ok, "list: max_items >= length and <= 0 mean no truncation; all-empty is \"\"");
}

fn t14() -> TestResult {
  var ok = streq(initials_of("John", "Paul"), "J. P.");
  if !streq(initials_of("john", ""), "J.") { ok = false; }
  if !streq(initials_of("", "paul"), "P.") { ok = false; }
  if !streq(initials_of("", ""), "") { ok = false; }
  if !streq(initials_of("Jean-Luc", "Marie"), "J. M.") { ok = false; }
  return assert(ok, "initials: given then middle, uppercased, \".\"-suffixed, space-joined");
}

fn t15() -> TestResult {
  var ok = streq(initials_of("李", "明"), "李. 明.");
  if !streq(initials_of("3", ""), "3.") { ok = false; }
  if !streq(initials_of("'t", ""), "'.") { ok = false; }
  return assert(ok, "initials: non-ASCII and non-letter first characters are used as-is");
}

fn t16() -> TestResult {
  let p = pn("Dr.", "John", "Paul", "Smith", "Jr.");
  var ok = streq(name_initials(&p), "J. P.");
  let q = pn("", "", "", "Smith", "");
  if !streq(name_initials(&q), "") { ok = false; }
  return assert(ok, "initials: PersonName wrapper uses given and middle only");
}

fn t17() -> TestResult {
  var t = honorific_table_new();
  honorific_table_push(&mut t, "dr", "Dr.");
  honorific_table_push(&mut t, "prof", "Prof.");
  var ok = streq(name_honorific(&t, "dr"), "Dr.");
  if !streq(name_honorific(&t, "prof"), "Prof.") { ok = false; }
  if !streq(name_honorific(&t, "sir"), "") { ok = false; }
  if !streq(name_honorific(&t, ""), "") { ok = false; }
  if !streq(name_honorific(&t, "Dr."), "") { ok = false; }
  return assert(ok, "honorific: exact byte-wise caller-supplied keys; miss and empty key are \"\"");
}

fn t18() -> TestResult {
  var t = honorific_table_new();
  honorific_table_push(&mut t, "dr", "Dr.");
  honorific_table_push(&mut t, "dr", "Doctor");
  var ok = streq(name_honorific(&t, "dr"), "Dr.");
  if !streq(name_honorific(&t, "doctor"), "") { ok = false; }
  return assert(ok, "honorific: first matching pair wins; comparison is case-sensitive");
}

fn t19() -> TestResult {
  var ks = Vec[Str].new();
  ks.push("a");
  ks.push("b");
  var ts = Vec[Str].new();
  ts.push("Alpha");
  let ragged = HonorificTable{ keys: ks; titles: ts };
  var ok = streq(name_honorific(&ragged, "a"), "Alpha");
  if !streq(name_honorific(&ragged, "b"), "") { ok = false; }
  return assert(ok, "honorific: a ragged table is bounded by the shorter vector");
}

fn t20() -> TestResult {
  var ok = streq(key_of("en", "Dr.", "John", "Paul", "Smith", "Jr."), "Smith John Paul Dr. Jr.");
  if !streq(key_of("zh", "Dr.", "John", "Paul", "Smith", "Jr."), "Smith John Paul Dr. Jr.") { ok = false; }
  if !streq(key_of("en", "", "John", "", "", ""), "John") { ok = false; }
  return assert(ok, "sort key: family given middle prefix suffix, locale-independent");
}

fn t21() -> TestResult {
  let k1 = key_of("en", "", "Wei", "", "Li", "");
  let k2 = key_of("en", "", "John", "", "Smith", "");
  let k3 = key_of("zh", "", "Wei", "", "Li", "");
  var ok = compare.str_compare(k1, k2) < 0;
  if !(compare.str_compare(k2, k1) > 0) { ok = false; }
  if !streq(k1, k3) { ok = false; }
  if !streq(k1, "Li Wei") { ok = false; }
  return assert(ok, "sort key: byte-wise family-first ordering, same key for every locale");
}

fn main() -> Int {
  io.println("=== xiom.l10n.name conformance tests ===");
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
  if failed == 0 {
    io.println("xiom.l10n.name: all tests passed");
  } else {
    io.println("xiom.l10n.name: tests failed");
  }
  return failed;
}
