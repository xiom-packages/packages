// XIOM -- xiom.translation conformance tests (22 checks)
// Port task: prove the pure-XIOM xiom.translation module against its SPEC.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Coverage: key/value parsing with both separators, comments, duplicates,
// CRLF, malformed-line errors, multi-locale get/locales/keys, catalog_add
// append/replace/immutability, catalog_missing, the three-level translate
// fallback chain, placeholder interpolation (multiple, repeated, unknown,
// values with braces, empty names/values, unterminated brace), brace
// literalness and str_compare discipline for content-equal strings that come
// from separate allocations.
//
// All Str equality goes through str_compare: BUG 17 lowers `==` on Str values
// read from Vec[Str] elements to a pointer comparison, so every comparison
// below is routed through streq/str_at/opt_str_is instead of `==`.

module translation_tests
use xiom.io; use xiom.test; use xiom.translation;
use xiom.string;
use xiom.string.compare;

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn str_at(v: &Vec[Str], i: Int, want: Str) -> Bool {
  if i < 0 || i >= v.len() { return false; }
  let got: Str = v[i];
  return streq(got, want);
}

fn opt_str_is(o: Option[Str], want: Str) -> Bool {
  match o {
    Some(v) => { return streq(v, want); },
    None => { return false; },
  }
  return false;
}

fn opt_str_none(o: Option[Str]) -> Bool {
  match o {
    Some(_) => { return false; },
    None => { return true; },
  }
  return true;
}

// True when the text fails to parse with a "translation: " error message.
fn parse_err_prefix(text: Str) -> Bool {
  let r = catalog_parse("en", text);
  match r {
    Ok(_) => { return false; },
    Err(e) => { return string.str_starts_with(e, "translation: "); },
  }
  return false;
}

// True when the text fails to parse with exactly `want` as the message.
fn parse_err_is(text: Str, want: Str) -> Bool {
  let r = catalog_parse("en", text);
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn t1() -> TestResult {
  let r = catalog_parse("en", "hello = Hello world\nbye=Bye");
  var ok = false;
  match r {
    Ok(c) => {
      ok = opt_str_is(catalog_get(&c, "en", "hello"), "Hello world");
      if !opt_str_is(catalog_get(&c, "en", "bye"), "Bye") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "parse basic pairs and trim whitespace");
}

fn t2() -> TestResult {
  let r = catalog_parse("en", "hello: Hello\nnote = a:b:c\nempty:");
  var ok = false;
  match r {
    Ok(c) => {
      ok = opt_str_is(catalog_get(&c, "en", "hello"), "Hello");
      if !opt_str_is(catalog_get(&c, "en", "note"), "a:b:c") { ok = false; }
      if !opt_str_is(catalog_get(&c, "en", "empty"), "") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "colon separator and first-separator rule");
}

fn t3() -> TestResult {
  let r = catalog_parse("en", "; semicolon comment\n# hash comment\n   # indented\n\nkey=value\n;tail with = sign");
  var ok = false;
  match r {
    Ok(c) => {
      ok = opt_str_is(catalog_get(&c, "en", "key"), "value");
      let ks = catalog_keys(&c, "en");
      if ks.len() != 1 { ok = false; }
      if !str_at(&ks, 0, "key") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "comments and blank lines are ignored");
}

fn t4() -> TestResult {
  let r = catalog_parse("en", "a=1\nb=2\na=3\nb=4\na=5");
  var ok = false;
  match r {
    Ok(c) => {
      ok = opt_str_is(catalog_get(&c, "en", "a"), "5");
      if !opt_str_is(catalog_get(&c, "en", "b"), "4") { ok = false; }
      let ks = catalog_keys(&c, "en");
      if ks.len() != 2 { ok = false; }
      if !str_at(&ks, 0, "a") { ok = false; }
      if !str_at(&ks, 1, "b") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "duplicate key last wins in place");
}

fn t5() -> TestResult {
  let r = catalog_parse("en", "a=1\r\nb=2\r\nc=3\r");
  var ok = false;
  match r {
    Ok(c) => {
      let ks = catalog_keys(&c, "en");
      ok = ks.len() == 3;
      if !opt_str_is(catalog_get(&c, "en", "a"), "1") { ok = false; }
      if !opt_str_is(catalog_get(&c, "en", "b"), "2") { ok = false; }
      if !opt_str_is(catalog_get(&c, "en", "c"), "3") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "CRLF line endings parse");
}

fn t6() -> TestResult {
  var ok = parse_err_is("no separator here", "translation: missing separator in line: no separator here");
  if !parse_err_is("  :  ", "translation: empty key in line: :") { ok = false; }
  if !parse_err_prefix("= value") { ok = false; }
  if !parse_err_prefix(": value") { ok = false; }
  if !parse_err_prefix("key") { ok = false; }
  return assert(ok, "malformed lines are Err with a translation: prefix");
}

fn t7() -> TestResult {
  let r = catalog_parse("en", "hello=Hello");
  var ok = false;
  match r {
    Ok(c0) => {
      let c = catalog_add(&c0, "fr", "hello", "Bonjour");
      ok = opt_str_is(catalog_get(&c, "en", "hello"), "Hello");
      if !opt_str_is(catalog_get(&c, "fr", "hello"), "Bonjour") { ok = false; }
      if !opt_str_none(catalog_get(&c, "de", "hello")) { ok = false; }
      if !opt_str_none(catalog_get(&c, "fr", "missing")) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "get reads entries across locales");
}

fn t8() -> TestResult {
  let r = catalog_parse("en", "a=1");
  var ok = false;
  match r {
    Ok(c0) => {
      let c1 = catalog_add(&c0, "fr", "a", "un");
      let c2 = catalog_add(&c1, "de", "a", "ein");
      let c3 = catalog_add(&c2, "fr", "b", "deux");
      let ls = catalog_locales(&c3);
      ok = ls.len() == 3;
      if !str_at(&ls, 0, "en") { ok = false; }
      if !str_at(&ls, 1, "fr") { ok = false; }
      if !str_at(&ls, 2, "de") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "catalog_locales keeps first-seen order");
}

fn t9() -> TestResult {
  let r = catalog_parse("en", "b=1\na=2\nc=3");
  var ok = false;
  match r {
    Ok(c0) => {
      let c1 = catalog_add(&c0, "en", "a", "updated");
      var ks = catalog_keys(&c1, "en");
      ok = ks.len() == 3;
      if !str_at(&ks, 0, "b") { ok = false; }
      if !str_at(&ks, 1, "a") { ok = false; }
      if !str_at(&ks, 2, "c") { ok = false; }
      if !opt_str_is(catalog_get(&c1, "en", "a"), "updated") { ok = false; }
      ks.push("zzz");
      let again = catalog_keys(&c1, "en");
      if again.len() != 3 { ok = false; }
      let none = catalog_keys(&c1, "fr");
      if none.len() != 0 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "catalog_keys keeps locale order and copies");
}

fn t10() -> TestResult {
  let r = catalog_parse("en", "a=1");
  var ok = false;
  match r {
    Ok(c0) => {
      let c1 = catalog_add(&c0, "en", "b", "2");
      let c2 = catalog_add(&c1, "en", "a", "9");
      ok = opt_str_is(catalog_get(&c1, "en", "a"), "1");
      if !opt_str_is(catalog_get(&c1, "en", "b"), "2") { ok = false; }
      if !opt_str_is(catalog_get(&c2, "en", "a"), "9") { ok = false; }
      if !opt_str_is(catalog_get(&c2, "en", "b"), "2") { ok = false; }
      let ks = catalog_keys(&c2, "en");
      if ks.len() != 2 { ok = false; }
      if !str_at(&ks, 0, "a") { ok = false; }
      if !str_at(&ks, 1, "b") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "catalog_add appends new and replaces existing");
}

fn t11() -> TestResult {
  let r = catalog_parse("en", "a=1");
  var ok = false;
  match r {
    Ok(c0) => {
      let c1 = catalog_add(&c0, "fr", "a", "un");
      ok = opt_str_is(catalog_get(&c0, "en", "a"), "1");
      if !opt_str_none(catalog_get(&c0, "fr", "a")) { ok = false; }
      let ls0 = catalog_locales(&c0);
      if ls0.len() != 1 { ok = false; }
      if !opt_str_is(catalog_get(&c1, "fr", "a"), "un") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "catalog_add returns a new catalog (input unchanged)");
}

fn t12() -> TestResult {
  let r = catalog_parse("en", "a=1\nb=2\nc=3\nd=4");
  var ok = false;
  match r {
    Ok(c0) => {
      let c1 = catalog_add(&c0, "fr", "a", "un");
      let c2 = catalog_add(&c1, "fr", "c", "trois");
      let c3 = catalog_add(&c2, "fr", "x", "hors");
      let miss = catalog_missing(&c3, "fr", "en");
      ok = miss.len() == 2;
      if !str_at(&miss, 0, "b") { ok = false; }
      if !str_at(&miss, 1, "d") { ok = false; }
      let rev = catalog_missing(&c3, "en", "fr");
      if rev.len() != 1 { ok = false; }
      if !str_at(&rev, 0, "x") { ok = false; }
      let all_de = catalog_missing(&c3, "de", "en");
      if all_de.len() != 4 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "catalog_missing reports fallback-only keys in order");
}

fn t13() -> TestResult {
  let r = catalog_parse("en", "greeting=Hello");
  var names = Vec[Str].new();
  var values = Vec[Str].new();
  var ok = false;
  match r {
    Ok(c0) => {
      let c = catalog_add(&c0, "fr", "greeting", "Bonjour");
      ok = streq(catalog_translate(&c, "fr", "en", "greeting", &names, &values), "Bonjour");
      if !streq(catalog_translate(&c, "en", "fr", "greeting", &names, &values), "Hello") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "translate prefers the locale over the fallback");
}

fn t14() -> TestResult {
  let r = catalog_parse("en", "greeting=Hello");
  var names = Vec[Str].new();
  var values = Vec[Str].new();
  var ok = false;
  match r {
    Ok(c) => {
      ok = streq(catalog_translate(&c, "fr", "en", "greeting", &names, &values), "Hello");
      if !streq(catalog_translate(&c, "de", "en", "greeting", &names, &values), "Hello") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "translate falls back to the fallback locale");
}

fn t15() -> TestResult {
  let r = catalog_parse("en", "greeting=Hello");
  var names = Vec[Str].new();
  var values = Vec[Str].new();
  names.push("name");
  values.push("Ada");
  var ok = false;
  match r {
    Ok(c) => {
      ok = streq(catalog_translate(&c, "fr", "en", "app.title", &names, &values), "app.title");
      if !streq(catalog_translate(&c, "fr", "en", "hi.{name}", &names, &values), "hi.Ada") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "translate falls back to the key itself");
}

fn t16() -> TestResult {
  let r = catalog_parse("en", "hi=Hello, {name}! Welcome to {place}, {name}.");
  var names = Vec[Str].new();
  names.push("name");
  names.push("place");
  var values = Vec[Str].new();
  values.push("Ada");
  values.push("Paris");
  var ok = false;
  match r {
    Ok(c) => {
      ok = streq(catalog_translate(&c, "en", "fr", "hi", &names, &values), "Hello, Ada! Welcome to Paris, Ada.");
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "placeholder substitution: multiple and repeated");
}

fn t17() -> TestResult {
  let r = catalog_parse("en", "one=[{missing}]\ntwo=x{gone}y{b}");
  var names = Vec[Str].new();
  names.push("b");
  var values = Vec[Str].new();
  values.push("B");
  var ok = false;
  match r {
    Ok(c) => {
      ok = streq(catalog_translate(&c, "en", "fr", "one", &names, &values), "[]");
      if !streq(catalog_translate(&c, "en", "fr", "two", &names, &values), "xyB") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "unknown placeholder names render empty");
}

fn t18() -> TestResult {
  let r = catalog_parse("en", "k=v={a}");
  var names = Vec[Str].new();
  names.push("a");
  names.push("b");
  var values = Vec[Str].new();
  values.push("{b}");
  values.push("B");
  var ok = false;
  match r {
    Ok(c) => {
      ok = streq(catalog_translate(&c, "en", "fr", "k", &names, &values), "v={b}");
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "substituted values are not re-scanned");
}

fn t19() -> TestResult {
  let r = catalog_parse("en", "k=x{y}z\nk2={}\nk3=\nk4=a{");
  var none_names = Vec[Str].new();
  var none_values = Vec[Str].new();
  var empty_names = Vec[Str].new();
  empty_names.push("");
  var empty_values = Vec[Str].new();
  empty_values.push("E");
  var ok = false;
  match r {
    Ok(c) => {
      ok = streq(catalog_translate(&c, "en", "fr", "k", &none_names, &none_values), "xz");
      if !streq(catalog_translate(&c, "en", "fr", "k2", &empty_names, &empty_values), "E") { ok = false; }
      if !streq(catalog_translate(&c, "en", "fr", "k3", &none_names, &none_values), "") { ok = false; }
      if !streq(catalog_translate(&c, "en", "fr", "k4", &none_names, &none_values), "a{") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "empty names, empty values and an unterminated {");
}

fn t20() -> TestResult {
  let r1 = catalog_parse("en", "");
  let r2 = catalog_parse("en", "\n\n  \n;# only comments\n");
  var names = Vec[Str].new();
  var values = Vec[Str].new();
  var ok = false;
  match r1 {
    Ok(c) => {
      ok = catalog_locales(&c).len() == 0;
      if catalog_keys(&c, "en").len() != 0 { ok = false; }
      if !opt_str_none(catalog_get(&c, "en", "k")) { ok = false; }
      if catalog_missing(&c, "en", "fr").len() != 0 { ok = false; }
      if !streq(catalog_translate(&c, "en", "fr", "k", &names, &values), "k") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  match r2 {
    Ok(c2) => {
      if catalog_locales(&c2).len() != 0 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "an empty catalog is valid and inert");
}

fn t21() -> TestResult {
  let r = catalog_parse("en", "k1={{x}}\nk2=a}}b\nk3=}\nk4=x{y");
  var names = Vec[Str].new();
  names.push("x");
  var values = Vec[Str].new();
  values.push("X");
  var ok = false;
  match r {
    Ok(c) => {
      ok = streq(catalog_translate(&c, "en", "fr", "k1", &names, &values), "}");
      if !streq(catalog_translate(&c, "en", "fr", "k2", &names, &values), "a}}b") { ok = false; }
      if !streq(catalog_translate(&c, "en", "fr", "k3", &names, &values), "}") { ok = false; }
      if !streq(catalog_translate(&c, "en", "fr", "k4", &names, &values), "x{y") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "braces are literal except {name}; {{ is not special");
}

fn t22() -> TestResult {
  let r = catalog_parse("en", "k=v");
  var ok = false;
  match r {
    Ok(c) => {
      let loc = string.str_slice("enx", 0, 2);
      let key = string.str_slice("kx", 0, 1);
      let c1 = catalog_add(&c, loc, key, "w");
      let ls = catalog_locales(&c1);
      ok = ls.len() == 1;
      if !str_at(&ls, 0, "en") { ok = false; }
      if !opt_str_is(catalog_get(&c1, "en", "k"), "w") { ok = false; }
      if !opt_str_is(catalog_get(&c1, "en", key), "w") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "catalog compares locales and keys by content");
}

fn main() -> Int {
  io.println("=== xiom.translation conformance tests ===");
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
  if failed == 0 {
    io.println("xiom.translation: all tests passed");
  } else {
    io.println("xiom.translation: tests failed");
  }
  return failed;
}
