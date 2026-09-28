// XIOM -- xiom.locale conformance tests (24 checks)
// Port task: prove the pure-XIOM xiom.locale module against its documented
// BCP-47 parsing, canonicalization, RFC 4647 lookup and fallback contract.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module locale_tests
use xiom.io; use xiom.test; use xiom.locale;
use xiom.string.compare;

// All Str equality goes through str_compare: BUG 17 lowers `==` on Str values
// read from Vec[Str] elements to a pointer comparison, so every field and
// Vec element check below is routed through streq/vec_is instead of `==`.

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn vec_is(v: &Vec[Str], i: Int, want: Str) -> Bool {
  if i < 0 || i >= v.len() { return false; }
  return streq(v[i], want);
}

fn vec_len_is(v: &Vec[Str], want: Int) -> Bool {
  return v.len() == want;
}

// canonicalization result equals want.
fn canon_is(tag: Str, want: Str) -> Bool {
  let r = locale_canonical(tag);
  match r {
    Ok(v) => { return streq(v, want); },
    Err(_) => { return false; },
  }
  return false;
}

// parse fails with exactly want (byte-exact error message).
fn parse_err_is(tag: Str, want: Str) -> Bool {
  let r = locale_parse(tag);
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

// field 0 = language, 1 = script, 2 = region, 3 = private_use.
fn field_is(tag: Str, field: Int, want: Str) -> Bool {
  let r = locale_parse(tag);
  match r {
    Ok(loc) => {
      var v = "";
      if field == 0 { v = loc.language; }
      elif field == 1 { v = loc.script; }
      elif field == 2 { v = loc.region; }
      else { v = loc.private_use; }
      return streq(v, want);
    },
    Err(_) => { return false; },
  }
  return false;
}

// exactly three variants, in order.
fn variants_are(tag: Str, want0: Str, want1: Str, want2: Str) -> Bool {
  let r = locale_parse(tag);
  match r {
    Ok(loc) => {
      let vs: Vec[Str] = loc.variants;
      var ok = vec_len_is(&vs, 3);
      if !vec_is(&vs, 0, want0) { ok = false; }
      if !vec_is(&vs, 1, want1) { ok = false; }
      if !vec_is(&vs, 2, want2) { ok = false; }
      return ok;
    },
    Err(_) => { return false; },
  }
  return false;
}

// exactly one variant, equal to want0.
fn variant1_is(tag: Str, want0: Str) -> Bool {
  let r = locale_parse(tag);
  match r {
    Ok(loc) => {
      let vs: Vec[Str] = loc.variants;
      if !vec_len_is(&vs, 1) { return false; }
      return vec_is(&vs, 0, want0);
    },
    Err(_) => { return false; },
  }
  return false;
}

// exactly two extensions, in order.
fn ext2_is(tag: Str, want0: Str, want1: Str) -> Bool {
  let r = locale_parse(tag);
  match r {
    Ok(loc) => {
      let es: Vec[Str] = loc.extensions;
      if !vec_len_is(&es, 2) { return false; }
      if !vec_is(&es, 0, want0) { return false; }
      return vec_is(&es, 1, want1);
    },
    Err(_) => { return false; },
  }
  return false;
}

fn lookup_is(req: &Vec[Str], avail: &Vec[Str], want: Str) -> Bool {
  let r = locale_lookup(req, avail);
  match r {
    Some(v) => { return streq(v, want); },
    None => { return false; },
  }
  return false;
}

fn lookup_none(req: &Vec[Str], avail: &Vec[Str]) -> Bool {
  let r = locale_lookup(req, avail);
  match r {
    Some(_) => { return false; },
    None => { return true; },
  }
  return false;
}

fn chain_is(tag: Str, expected: &Vec[Str]) -> Bool {
  let got = locale_fallback_chain(tag);
  if got.len() != expected.len() { return false; }
  var i = 0;
  while i < got.len() {
    let g: Str = got[i];
    let e: Str = expected[i];
    if !streq(g, e) { return false; }
    i = i + 1;
  }
  return true;
}

fn registry_is(subtag: Str, want_name: Str, want_script: Str) -> Bool {
  let r = locale_registry_get(subtag);
  match r {
    Some(info) => {
      let nm: Str = info.name;
      let sc: Str = info.default_script;
      if !streq(nm, want_name) { return false; }
      return streq(sc, want_script);
    },
    None => { return false; },
  }
  return false;
}

fn registry_none(subtag: Str) -> Bool {
  let r = locale_registry_get(subtag);
  match r {
    Some(_) => { return false; },
    None => { return true; },
  }
  return false;
}

fn t1() -> TestResult {
  var ok = canon_is("EN-us", "en-US");
  if !canon_is("zh-hant-tw", "zh-Hant-TW") { ok = false; }
  if !canon_is("FR", "fr") { ok = false; }
  if !canon_is("sr-latn-rs", "sr-Latn-RS") { ok = false; }
  if !canon_is("de-DE", "de-DE") { ok = false; }
  return assert(ok, "canonical: language lower, script Titlecase, region upper");
}

fn t2() -> TestResult {
  var ok = canon_is("DE-de-1996", "de-DE-1996");
  if !canon_is("EN-LATN-US-U-CA-GREGORY-X-PHONEBK", "en-Latn-US-u-ca-gregory-x-phonebk") { ok = false; }
  if !canon_is("x-ABC-DEF", "x-abc-def") { ok = false; }
  if !canon_is("en-us-x-twain", "en-US-x-twain") { ok = false; }
  return assert(ok, "canonical: variants, extensions and private use lower");
}

fn t3() -> TestResult {
  var ok = field_is("zh-Hant-TW", 0, "zh");
  if !field_is("zh-Hant-TW", 1, "Hant") { ok = false; }
  if !field_is("zh-Hant-TW", 2, "TW") { ok = false; }
  if !field_is("en", 1, "") { ok = false; }
  if !field_is("en-US", 2, "US") { ok = false; }
  return assert(ok, "parse: language, script and region land in their fields");
}

fn t4() -> TestResult {
  var ok = variants_are("sl-rozaj-biske-1994", "rozaj", "biske", "1994");
  if !variant1_is("de-1901", "1901") { ok = false; }
  if !variant1_is("en-US-ABCD1", "abcd1") { ok = false; }
  return assert(ok, "parse: variants by shape (5-8 alnum, or digit + 3 alnum)");
}

fn t5() -> TestResult {
  var ok = ext2_is("en-a-bbb-c-ddd", "a-bbb", "c-ddd");
  if !ext2_is("en-US-u-ca-gregory-t-en-latn", "u-ca-gregory", "t-en-latn") { ok = false; }
  return assert(ok, "parse: extensions keep their singleton and subtags");
}

fn t6() -> TestResult {
  var ok = field_is("en-US-x-twain", 3, "twain");
  if !field_is("x-abc-def", 3, "abc-def") { ok = false; }
  if !field_is("x-abc-def", 0, "") { ok = false; }
  if !field_is("en-x-a", 3, "a") { ok = false; }
  return assert(ok, "parse: private use after x-, including private-use-only tags");
}

fn t7() -> TestResult {
  var ok = parse_err_is("", "locale: empty tag");
  if !parse_err_is("en-", "locale: empty subtag") { ok = false; }
  if !parse_err_is("-en", "locale: empty subtag") { ok = false; }
  if !parse_err_is("en--US", "locale: empty subtag") { ok = false; }
  if !parse_err_is("e", "locale: invalid language: e") { ok = false; }
  if !parse_err_is("1n", "locale: invalid language: 1n") { ok = false; }
  return assert(ok, "invalid: empty tag, empty subtags, bad language");
}

fn t8() -> TestResult {
  var ok = parse_err_is("en-12", "locale: invalid subtag: 12");
  if !parse_err_is("en-abc", "locale: invalid subtag: abc") { ok = false; }
  if !parse_err_is("en-Latn-US-ABCD", "locale: invalid subtag: ABCD") { ok = false; }
  if !parse_err_is("en-US-Latn", "locale: invalid subtag: Latn") { ok = false; }
  if !parse_err_is("en-abcdefghi", "locale: invalid subtag: abcdefghi") { ok = false; }
  return assert(ok, "invalid: subtags that match no position or break strict order");
}

fn t9() -> TestResult {
  var ok = parse_err_is("en-u", "locale: extension without subtags: u");
  if !parse_err_is("en-a-b", "locale: extension without subtags: a") { ok = false; }
  if !parse_err_is("en-a-b_c", "locale: invalid extension subtag: b_c") { ok = false; }
  if !parse_err_is("en-x", "locale: empty private use") { ok = false; }
  if !parse_err_is("en-x-abcdefghi", "locale: invalid private-use subtag: abcdefghi") { ok = false; }
  return assert(ok, "invalid: extension and private-use misuse");
}

fn t10() -> TestResult {
  var ok = parse_err_is("de-1901-1901", "locale: duplicate variant: 1901");
  if !parse_err_is("en-u-ca-gregory-u-nu-latn", "locale: duplicate singleton: u") { ok = false; }
  return assert(ok, "invalid: duplicate variants and duplicate singletons");
}

fn t11() -> TestResult {
  var ok = locale_is_valid("en");
  if !locale_is_valid("en-US") { ok = false; }
  if !locale_is_valid("zh-Hant-TW") { ok = false; }
  if !locale_is_valid("de-AT-1901") { ok = false; }
  if !locale_is_valid("en-a-bbb") { ok = false; }
  if !locale_is_valid("en-x-y") { ok = false; }
  if !locale_is_valid("x-a") { ok = false; }
  if !locale_is_valid("abcd") { ok = false; }
  return assert(ok, "valid: representative well-formed tags");
}

fn t12() -> TestResult {
  var ok = !locale_is_valid("");
  if locale_is_valid("en_") { ok = false; }
  if locale_is_valid(" en") { ok = false; }
  if locale_is_valid("en-") { ok = false; }
  if locale_is_valid("e") { ok = false; }
  if locale_is_valid("en-12") { ok = false; }
  if locale_is_valid("en-u") { ok = false; }
  if locale_is_valid("en-US-u") { ok = false; }
  return assert(ok, "valid: malformed tags are rejected");
}

fn t13() -> TestResult {
  var ok = registry_is("en", "English", "Latn");
  if !registry_is("zh", "Chinese", "Hans") { ok = false; }
  if !registry_is("JA", "Japanese", "Jpan") { ok = false; }
  if !registry_is("Cy", "Welsh", "Latn") { ok = false; }
  return assert(ok, "registry: known subtags, case-insensitive lookup");
}

fn t14() -> TestResult {
  let c = locale_registry_count();
  var ok = c >= 30 && c <= 50;
  if !registry_none("xx") { ok = false; }
  if !registry_none("") { ok = false; }
  if !registry_none("zzz") { ok = false; }
  return assert(ok, "registry: 30..50 rows and misses return None");
}

fn t15() -> TestResult {
  var avail = Vec[Str].new();
  avail.push("de-DE");
  avail.push("de");
  var req = Vec[Str].new();
  req.push("de-DE");
  var ok = lookup_is(&req, &avail, "de-DE");
  var req2 = Vec[Str].new();
  req2.push("de-AT");
  if !lookup_is(&req2, &avail, "de") { ok = false; }
  return assert(ok, "lookup: exact match first, then truncation (de-AT -> de)");
}

fn t16() -> TestResult {
  var avail = Vec[Str].new();
  avail.push("zh-Hant");
  avail.push("zh");
  var req = Vec[Str].new();
  req.push("zh-Hant-CN");
  var ok = lookup_is(&req, &avail, "zh-Hant");
  var req2 = Vec[Str].new();
  req2.push("zh-Hans-CN");
  if !lookup_is(&req2, &avail, "zh") { ok = false; }
  return assert(ok, "lookup: zh-Hant-CN -> zh-Hant before zh (RFC 4647 example)");
}

fn t17() -> TestResult {
  var avail = Vec[Str].new();
  avail.push("de");
  avail.push("en");
  var req = Vec[Str].new();
  req.push("fr-CA");
  req.push("de-AT");
  var ok = lookup_is(&req, &avail, "de");
  var req2 = Vec[Str].new();
  req2.push("en-GB");
  req2.push("de");
  if !lookup_is(&req2, &avail, "en") { ok = false; }
  return assert(ok, "lookup: requested order is the priority order");
}

fn t18() -> TestResult {
  var avail = Vec[Str].new();
  avail.push("zh");
  var req = Vec[Str].new();
  req.push("*");
  req.push("zh-Hant");
  var ok = lookup_is(&req, &avail, "zh");
  var req2 = Vec[Str].new();
  req2.push("*");
  if !lookup_none(&req2, &avail) { ok = false; }
  return assert(ok, "lookup: '*' is skipped and matches nothing by itself");
}

fn t19() -> TestResult {
  var avail = Vec[Str].new();
  avail.push("en-US");
  avail.push("zh-Hant");
  var req = Vec[Str].new();
  req.push("EN-us");
  var ok = lookup_is(&req, &avail, "en-US");
  var req2 = Vec[Str].new();
  req2.push("ZH-hant");
  if !lookup_is(&req2, &avail, "zh-Hant") { ok = false; }
  return assert(ok, "lookup: case-insensitive, returns available casing");
}

fn t20() -> TestResult {
  var avail = Vec[Str].new();
  avail.push("en-US");
  avail.push("en");
  var req = Vec[Str].new();
  req.push("en-US-u-ca-gregory");
  var ok = lookup_is(&req, &avail, "en-US");
  var avail2 = Vec[Str].new();
  avail2.push("zh-Hant-CN");
  avail2.push("zh");
  var req2 = Vec[Str].new();
  req2.push("zh-Hant-CN-x-private1-private2");
  if !lookup_is(&req2, &avail2, "zh-Hant-CN") { ok = false; }
  return assert(ok, "lookup: extensions and private use truncate as in RFC 4647");
}

fn t21() -> TestResult {
  var avail = Vec[Str].new();
  avail.push("de");
  avail.push("en");
  var req = Vec[Str].new();
  req.push("fr");
  var ok = lookup_none(&req, &avail);
  var req2 = Vec[Str].new();
  req2.push("fr-CA");
  if !lookup_none(&req2, &avail) { ok = false; }
  var av_empty = Vec[Str].new();
  if !lookup_none(&req, &av_empty) { ok = false; }
  return assert(ok, "lookup: no match and empty available list return None");
}

fn t22() -> TestResult {
  var e1 = Vec[Str].new();
  e1.push("de-AT");
  e1.push("de");
  var ok = chain_is("de-AT", &e1);
  var e2 = Vec[Str].new();
  e2.push("en");
  if !chain_is("en", &e2) { ok = false; }
  var e3 = Vec[Str].new();
  e3.push("sr-Latn-RS");
  e3.push("sr-Latn");
  e3.push("sr");
  if !chain_is("sr-latn-rs", &e3) { ok = false; }
  return assert(ok, "fallback: most specific first, right-to-left truncation");
}

fn t23() -> TestResult {
  var e1 = Vec[Str].new();
  e1.push("zh-Hant-CN-u-ca-chinese-x-priv");
  e1.push("zh-Hant-CN");
  e1.push("zh-Hant");
  e1.push("zh");
  var ok = chain_is("zh-Hant-CN-u-ca-chinese-x-priv", &e1);
  var e2 = Vec[Str].new();
  e2.push("en-u-ca-gregory");
  e2.push("en");
  if !chain_is("en-u-ca-gregory", &e2) { ok = false; }
  return assert(ok, "fallback: extensions and private use dropped before truncation");
}

fn t24() -> TestResult {
  var empty = Vec[Str].new();
  var ok = chain_is("", &empty);
  if !chain_is("en-", &empty) { ok = false; }
  if !chain_is("??", &empty) { ok = false; }
  var e1 = Vec[Str].new();
  e1.push("x-priv");
  if !chain_is("x-priv", &e1) { ok = false; }
  return assert(ok, "fallback: invalid tags yield no chain, private-use-only is one step");
}

fn main() -> Int {
  io.println("=== xiom.locale conformance tests ===");
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
    io.println("xiom.locale: all tests passed");
  } else {
    io.println("xiom.locale: tests failed");
  }
  return failed;
}
