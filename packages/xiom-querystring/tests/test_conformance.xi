// XIOM -- xiom.querystring conformance tests (20 checks)
// Port task: prove the pure-XIOM xiom.querystring module against its
// documented application/x-www-form-urlencoded rules.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Coverage map (see SPEC.md section 6): simple pairs; repeated names kept in
// order and get_all; a segment without '='; skipped empty segments; the
// optional leading '?'; '+' -> space and '%2B' -> '+'; mixed-case %XX and
// malformed escapes kept literal; empty names and empty values; percent
// decoded names; qs_set replace-first and append immutability; qs_remove all
// matches; pinned serialization (space -> '+', unreserved kept, uppercase
// %XX); the empty query; parse -> serialize -> parse round-trips; component
// encode/decode round-trips; '?' after the first byte stays literal; and the
// str_compare discipline for names read out of Vec[Str].
//
// All Str equality goes through str_compare: BUG 17 lowers `==` on Str values
// read from Vec[Str] elements to a pointer comparison, so every comparison
// below is routed through streq/opt_is/val_is instead of `==`.

module querystring_tests
use xiom.io; use xiom.test; use xiom.querystring;
use xiom.string.compare;

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn opt_is(o: Option[Str], want: Str) -> Bool {
  match o {
    Some(v) => { return streq(v, want); },
    None => { return false; },
  }
  return false;
}

fn opt_none(o: Option[Str]) -> Bool {
  match o {
    Some(_) => { return false; },
    None => { return true; },
  }
  return true;
}

// Element `i` of a value vector compared by content; false out of range.
fn val_is(values: &Vec[Str], i: Int, want: Str) -> Bool {
  if i < 0 || i >= values.len() { return false; }
  return streq(values[i], want);
}

fn t1() -> TestResult {
  var q = qs_parse("a=1&b=2&c=3");
  var ok = qs_count(&q) == 3;
  if !opt_is(qs_get(&q, "a"), "1") { ok = false; }
  if !opt_is(qs_get(&q, "b"), "2") { ok = false; }
  if !opt_is(qs_get(&q, "c"), "3") { ok = false; }
  if !streq(qs_serialize(&q), "a=1&b=2&c=3") { ok = false; }
  return assert(ok, "parse: simple pairs are kept in order");
}

fn t2() -> TestResult {
  var q = qs_parse("a=1&b=2&a=3&a=4");
  var ok = qs_count(&q) == 4;
  if !opt_is(qs_get(&q, "a"), "1") { ok = false; }
  let all = qs_get_all(&q, "a");
  if all.len() != 3 { ok = false; }
  if !val_is(&all, 0, "1") { ok = false; }
  if !val_is(&all, 1, "3") { ok = false; }
  if !val_is(&all, 2, "4") { ok = false; }
  let bs = qs_get_all(&q, "b");
  if bs.len() != 1 { ok = false; }
  if !val_is(&bs, 0, "2") { ok = false; }
  let none = qs_get_all(&q, "z");
  if none.len() != 0 { ok = false; }
  if !streq(qs_serialize(&q), "a=1&b=2&a=3&a=4") { ok = false; }
  return assert(ok, "parse: repeated names are preserved and get_all returns all");
}

fn t3() -> TestResult {
  var q = qs_parse("flag&a=1&other");
  var ok = qs_count(&q) == 3;
  if !opt_is(qs_get(&q, "flag"), "") { ok = false; }
  if !opt_is(qs_get(&q, "other"), "") { ok = false; }
  if !opt_is(qs_get(&q, "a"), "1") { ok = false; }
  if !streq(qs_serialize(&q), "flag=&a=1&other=") { ok = false; }
  return assert(ok, "parse: a segment without '=' gets an empty value");
}

fn t4() -> TestResult {
  var q = qs_parse("a=1&&b=2&");
  var empty = qs_parse("&&");
  var ok = qs_count(&q) == 2;
  if !streq(qs_serialize(&q), "a=1&b=2") { ok = false; }
  if qs_count(&empty) != 0 { ok = false; }
  if !streq(qs_serialize(&empty), "") { ok = false; }
  return assert(ok, "parse: empty segments are skipped");
}

fn t5() -> TestResult {
  var q = qs_parse("?a=1&b=2");
  var only = qs_parse("?");
  var ok = qs_count(&q) == 2;
  if !opt_is(qs_get(&q, "a"), "1") { ok = false; }
  if !opt_is(qs_get(&q, "b"), "2") { ok = false; }
  if !streq(qs_serialize(&q), "a=1&b=2") { ok = false; }
  if qs_count(&only) != 0 { ok = false; }
  return assert(ok, "parse: one leading '?' is tolerated and dropped");
}

fn t6() -> TestResult {
  var q = qs_parse("q=a+b&r=c%2Bd");
  var ok = qs_count(&q) == 2;
  if !opt_is(qs_get(&q, "q"), "a b") { ok = false; }
  if !opt_is(qs_get(&q, "r"), "c+d") { ok = false; }
  if !streq(qs_decode_component("a+b"), "a b") { ok = false; }
  if !streq(qs_decode_component("c%2Bd"), "c+d") { ok = false; }
  if !streq(qs_encode_component("a b"), "a+b") { ok = false; }
  if !streq(qs_encode_component("c+d"), "c%2Bd") { ok = false; }
  return assert(ok, "'+' decodes to space and '%2B' to a literal plus");
}

fn t7() -> TestResult {
  var ok = streq(qs_decode_component("%41%6a%4A"), "AjJ");
  if !streq(qs_decode_component("%2F%3f"), "/?") { ok = false; }
  if !streq(qs_decode_component("%7e"), "~") { ok = false; }
  if !streq(qs_encode_component(qs_decode_component("%c3%a9")), "%C3%A9") { ok = false; }
  return assert(ok, "decode: %XX accepts mixed-case hex and re-encodes uppercase");
}

fn t8() -> TestResult {
  var ok = streq(qs_decode_component("%"), "%");
  if !streq(qs_decode_component("100%"), "100%") { ok = false; }
  if !streq(qs_decode_component("%2"), "%2") { ok = false; }
  if !streq(qs_decode_component("%zz"), "%zz") { ok = false; }
  if !streq(qs_decode_component("a%4"), "a%4") { ok = false; }
  if !streq(qs_decode_component("%4G1"), "%4G1") { ok = false; }
  return assert(ok, "decode: malformed percent escapes are kept literal");
}

fn t9() -> TestResult {
  var q = qs_parse("=v&a=&=");
  var ok = qs_count(&q) == 3;
  if !opt_is(qs_get(&q, ""), "v") { ok = false; }
  if !opt_is(qs_get(&q, "a"), "") { ok = false; }
  let empty_names = qs_get_all(&q, "");
  if empty_names.len() != 2 { ok = false; }
  if !val_is(&empty_names, 1, "") { ok = false; }
  if !streq(qs_serialize(&q), "=v&a=&=") { ok = false; }
  return assert(ok, "parse: empty names and empty values are preserved");
}

fn t10() -> TestResult {
  var q = qs_parse("%61=%31&b%20c=d%26e");
  var ok = qs_count(&q) == 2;
  if !opt_is(qs_get(&q, "a"), "1") { ok = false; }
  if !opt_is(qs_get(&q, "b c"), "d&e") { ok = false; }
  if !streq(qs_serialize(&q), "a=1&b+c=d%26e") { ok = false; }
  return assert(ok, "parse: names and values are percent-decoded");
}

fn t11() -> TestResult {
  var q = qs_parse("a=1&b=2&a=3");
  var q2 = qs_set(&q, "a", "X");
  var ok = qs_count(&q2) == 3;
  if !opt_is(qs_get(&q2, "a"), "X") { ok = false; }
  if !streq(qs_serialize(&q2), "a=X&b=2&a=3") { ok = false; }
  let all = qs_get_all(&q2, "a");
  if all.len() != 2 { ok = false; }
  if !val_is(&all, 1, "3") { ok = false; }
  return assert(ok, "set: replaces only the first match, in place");
}

fn t12() -> TestResult {
  var q = qs_parse("a=1");
  var q2 = qs_set(&q, "b", "2");
  var q3 = qs_set(&q2, "a", "9");
  var ok = streq(qs_serialize(&q2), "a=1&b=2");
  if !streq(qs_serialize(&q3), "a=9&b=2") { ok = false; }
  if !streq(qs_serialize(&q), "a=1") { ok = false; }
  if qs_count(&q) != 1 { ok = false; }
  var empty = qs_parse("");
  var added = qs_set(&empty, "k", "v");
  if !streq(qs_serialize(&added), "k=v") { ok = false; }
  return assert(ok, "set: appends when absent and never mutates the source");
}

fn t13() -> TestResult {
  var q = qs_parse("a=1&b=2&a=3&c=4");
  var q2 = qs_remove(&q, "a");
  var ok = streq(qs_serialize(&q2), "b=2&c=4");
  var q3 = qs_remove(&q2, "zz");
  if !streq(qs_serialize(&q3), "b=2&c=4") { ok = false; }
  var q4 = qs_remove(&q3, "b");
  if !streq(qs_serialize(&q4), "c=4") { ok = false; }
  var q5 = qs_remove(&q4, "c");
  if !streq(qs_serialize(&q5), "") { ok = false; }
  if !streq(qs_serialize(&q), "a=1&b=2&a=3&c=4") { ok = false; }
  return assert(ok, "remove: removes every pair with the name, source intact");
}

fn t14() -> TestResult {
  var q = qs_parse("aa=1&Ab=2");
  var ok = qs_has(&q, "aa");
  if !qs_has(&q, "Ab") { ok = false; }
  if qs_has(&q, "a") { ok = false; }
  if qs_has(&q, "ab") { ok = false; }
  if qs_has(&q, "AA") { ok = false; }
  if qs_has(&q, "") { ok = false; }
  return assert(ok, "has: matches the whole name, case-sensitively");
}

fn t15() -> TestResult {
  var q = qs_parse("a=hello world&b=x%26y&c=%c3%a9");
  var ok = qs_count(&q) == 3;
  if !streq(qs_serialize(&q), "a=hello+world&b=x%26y&c=%C3%A9") { ok = false; }
  if !streq(qs_encode_component("a b+c&d=e/f?g~h-i_j.k"), "a+b%2Bc%26d%3De%2Ff%3Fg~h-i_j.k") { ok = false; }
  return assert(ok, "serialize: pins '+' for space, unreserved kept, uppercase %XX");
}

fn t16() -> TestResult {
  var q = qs_parse("");
  var only = qs_parse("?");
  var ok = qs_count(&q) == 0;
  if !streq(qs_serialize(&q), "") { ok = false; }
  if qs_count(&only) != 0 { ok = false; }
  if !streq(qs_serialize(&only), "") { ok = false; }
  if !opt_none(qs_get(&q, "a")) { ok = false; }
  if qs_has(&q, "a") { ok = false; }
  return assert(ok, "empty query: zero pairs, empty serialization, None get");
}

fn t17() -> TestResult {
  let source = "a=1&b=hello+world&c=%26&d=&=v";
  var q = qs_parse(source);
  var ok = qs_count(&q) == 5;
  if !streq(qs_serialize(&q), source) { ok = false; }
  var back = qs_parse(qs_serialize(&q));
  if qs_count(&back) != 5 { ok = false; }
  if !opt_is(qs_get(&back, "a"), "1") { ok = false; }
  if !opt_is(qs_get(&back, "b"), "hello world") { ok = false; }
  if !opt_is(qs_get(&back, "c"), "&") { ok = false; }
  if !opt_is(qs_get(&back, "d"), "") { ok = false; }
  if !opt_is(qs_get(&back, ""), "v") { ok = false; }
  return assert(ok, "round-trip: parse -> serialize -> parse is stable");
}

fn t18() -> TestResult {
  var samples = Vec[Str].new();
  samples.push("plain");
  samples.push("a b");
  samples.push("a+b");
  samples.push("a&b=c?d/e");
  samples.push("100%");
  samples.push("%2F");
  samples.push("~-._");
  var ok = true;
  var i = 0;
  while i < samples.len() {
    let s: Str = samples[i];
    let enc = qs_encode_component(s);
    let dec = qs_decode_component(enc);
    if !streq(dec, s) { ok = false; }
    i = i + 1;
  }
  if !streq(qs_decode_component("100%25"), "100%") { ok = false; }
  if !streq(qs_encode_component(qs_decode_component("a+b%2Bc")), "a+b%2Bc") { ok = false; }
  return assert(ok, "component: encode then decode round-trips ASCII samples");
}

fn t19() -> TestResult {
  var q = qs_parse("a=1?b=2");
  var q2 = qs_parse("a=?");
  var ok = qs_count(&q) == 1;
  if !opt_is(qs_get(&q, "a"), "1?b=2") { ok = false; }
  if !opt_is(qs_get(&q2, "a"), "?") { ok = false; }
  var q3 = qs_parse("??a=1");
  if !opt_is(qs_get(&q3, "?a"), "1") { ok = false; }
  return assert(ok, "parse: only a leading '?' is special, later ones are literal");
}

fn t20() -> TestResult {
  var q = qs_parse("k=1&k=2&key=3&K=4");
  var ok = qs_count(&q) == 4;
  if !opt_is(qs_get(&q, "k"), "1") { ok = false; }
  if !opt_is(qs_get(&q, "key"), "3") { ok = false; }
  if !opt_is(qs_get(&q, "K"), "4") { ok = false; }
  let all = qs_get_all(&q, "k");
  if all.len() != 2 { ok = false; }
  if !val_is(&all, 0, "1") { ok = false; }
  if !val_is(&all, 1, "2") { ok = false; }
  if !streq(qs_serialize(&q), "k=1&k=2&key=3&K=4") { ok = false; }
  var q2 = qs_set(&q, "key", "9");
  if !streq(qs_serialize(&q2), "k=1&k=2&key=9&K=4") { ok = false; }
  return assert(ok, "names compare by content, not identity (str_compare)");
}

fn main() -> Int {
  io.println("=== xiom.querystring conformance tests ===");
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
    io.println("xiom.querystring: all tests passed");
  } else {
    io.println("xiom.querystring: tests failed");
  }
  return failed;
}
