// XIOM -- xiom.cookie conformance tests (20 checks)
// Port task: prove the pure-XIOM xiom.cookie module against its documented
// request and Set-Cookie grammar.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Coverage map (see SPEC.md section 6): request parsing with trimming,
// multiple pairs, duplicate first-wins, skipped segments and empty names,
// request serialization and round-trip, get/count on empty and ragged jars,
// full Set-Cookie parsing, case-insensitive attributes, Max-Age valid/invalid,
// Secure/HttpOnly flags, SameSite canonicalization, the two error messages,
// serialize omission rules, values containing '=', empty inputs and
// case-sensitive request names.
//
// All Str equality goes through str_compare: BUG 17 lowers `==` on Str values
// read from Vec[Str] elements to a pointer comparison, so every comparison
// below is routed through streq/opt_is instead of `==`.

module cookie_tests
use xiom.io; use xiom.test; use xiom.cookie;
use xiom.string;
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

// True when the header fails to parse with a "cookie: " error message.
fn set_err_prefix(r: Result[SetCookie, Str]) -> Bool {
  match r {
    Ok(_) => { return false; },
    Err(e) => { return string.str_starts_with(e, "cookie: "); },
  }
  return false;
}

// True when the header fails to parse with exactly `want` as the message.
fn set_err_is(r: Result[SetCookie, Str], want: Str) -> Bool {
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

// max_age of an Ok header, or -2 on Err (so the caller can detect the error).
fn age_of(r: Result[SetCookie, Str]) -> Int {
  match r {
    Ok(c) => { return c.max_age; },
    Err(_) => { return -2; },
  }
  return -2;
}

// serialize an Ok header; "" on Err.
fn ser_of(r: Result[SetCookie, Str]) -> Str {
  match r {
    Ok(c) => { return cookie_serialize_set(&c); },
    Err(_) => { return ""; },
  }
  return "";
}

// SameSite of an Ok header; "" on Err.
fn same_of(r: Result[SetCookie, Str]) -> Str {
  match r {
    Ok(c) => { return c.same_site; },
    Err(_) => { return ""; },
  }
  return "";
}

// Path of an Ok header; "" on Err.
fn path_of(r: Result[SetCookie, Str]) -> Str {
  match r {
    Ok(c) => { return c.path; },
    Err(_) => { return ""; },
  }
  return "";
}

// Secure flag of an Ok header; false on Err.
fn secure_of(r: Result[SetCookie, Str]) -> Bool {
  match r {
    Ok(c) => { return c.secure; },
    Err(_) => { return false; },
  }
  return false;
}

// HttpOnly flag of an Ok header; false on Err.
fn http_of(r: Result[SetCookie, Str]) -> Bool {
  match r {
    Ok(c) => { return c.http_only; },
    Err(_) => { return false; },
  }
  return false;
}

fn t1() -> TestResult {
  var jar = cookie_parse_request("a=1; b=2; c=3");
  var ok = cookie_count(&jar) == 3;
  if !opt_is(cookie_get(&jar, "a"), "1") { ok = false; }
  if !opt_is(cookie_get(&jar, "b"), "2") { ok = false; }
  if !opt_is(cookie_get(&jar, "c"), "3") { ok = false; }
  return assert(ok, "request: parses simple name=value pairs");
}

fn t2() -> TestResult {
  var jar = cookie_parse_request("  a = 1 ;  b= 2  ; c  ; d =x");
  var ok = cookie_count(&jar) == 3;
  if !opt_is(cookie_get(&jar, "a"), "1") { ok = false; }
  if !opt_is(cookie_get(&jar, "b"), "2") { ok = false; }
  if !opt_is(cookie_get(&jar, "d"), "x") { ok = false; }
  if !opt_none(cookie_get(&jar, "c")) { ok = false; }
  return assert(ok, "request: whitespace is trimmed around names and values");
}

fn t3() -> TestResult {
  var jar = cookie_parse_request("x=1; y=2; z=3; w=4");
  var ok = cookie_count(&jar) == 4;
  if !streq(cookie_serialize_request(&jar), "x=1; y=2; z=3; w=4") { ok = false; }
  return assert(ok, "request: multiple pairs serialize in order");
}

fn t4() -> TestResult {
  var jar = cookie_parse_request("a=1; b=2; a=3; b=4; a=5");
  var ok = cookie_count(&jar) == 2;
  if !opt_is(cookie_get(&jar, "a"), "1") { ok = false; }
  if !opt_is(cookie_get(&jar, "b"), "2") { ok = false; }
  if !streq(cookie_serialize_request(&jar), "a=1; b=2") { ok = false; }
  return assert(ok, "request: duplicate names keep the first occurrence");
}

fn t5() -> TestResult {
  var jar = cookie_parse_request("a=1; junk; b=2; ;; c; d=");
  var ok = cookie_count(&jar) == 3;
  if !opt_is(cookie_get(&jar, "a"), "1") { ok = false; }
  if !opt_is(cookie_get(&jar, "b"), "2") { ok = false; }
  if !opt_is(cookie_get(&jar, "d"), "") { ok = false; }
  return assert(ok, "request: segments without '=' are skipped");
}

fn t6() -> TestResult {
  var jar = cookie_parse_request("=x; a=1; =; b=2");
  var ok = cookie_count(&jar) == 2;
  if !opt_none(cookie_get(&jar, "")) { ok = false; }
  if !opt_is(cookie_get(&jar, "a"), "1") { ok = false; }
  if !opt_is(cookie_get(&jar, "b"), "2") { ok = false; }
  return assert(ok, "request: empty names are skipped");
}

fn t7() -> TestResult {
  var jar = cookie_parse_request("one=1; two=22; three=333");
  let text = cookie_serialize_request(&jar);
  var back = cookie_parse_request(text);
  var ok = streq(text, "one=1; two=22; three=333");
  if cookie_count(&back) != 3 { ok = false; }
  if !opt_is(cookie_get(&back, "one"), "1") { ok = false; }
  if !opt_is(cookie_get(&back, "two"), "22") { ok = false; }
  if !opt_is(cookie_get(&back, "three"), "333") { ok = false; }
  return assert(ok, "request: serialize then parse round-trips");
}

fn t8() -> TestResult {
  var empty = CookieJar{ names: Vec[Str].new(); values: Vec[Str].new(); };
  var ok = cookie_count(&empty) == 0;
  if !opt_none(cookie_get(&empty, "a")) { ok = false; }
  if !streq(cookie_serialize_request(&empty), "") { ok = false; }
  var ragged = cookie_parse_request("a=1");
  ragged.values.pop();
  if cookie_count(&ragged) != 0 { ok = false; }
  return assert(ok, "get/count: empty and ragged jars are inert");
}

fn t9() -> TestResult {
  let r = cookie_parse_set("sid=abc123; Path=/; Domain=example.com; Max-Age=3600; Secure; HttpOnly; SameSite=Lax");
  var ok = false;
  match r {
    Ok(c) => {
      ok = streq(c.name, "sid");
      if !streq(c.value, "abc123") { ok = false; }
      if !streq(c.path, "/") { ok = false; }
      if !streq(c.domain, "example.com") { ok = false; }
      if c.max_age != 3600 { ok = false; }
      if !c.secure { ok = false; }
      if !c.http_only { ok = false; }
      if !streq(c.same_site, "Lax") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "set: parses a full attribute list");
}

fn t10() -> TestResult {
  let r = cookie_parse_set("s=1; pAtH=/x; DOMAIN=e.com; max-age=7; sEcUrE; hTtPoNlY; sAmEsItE=StRiCt");
  var ok = false;
  match r {
    Ok(c) => {
      ok = streq(c.path, "/x");
      if !streq(c.domain, "e.com") { ok = false; }
      if c.max_age != 7 { ok = false; }
      if !c.secure { ok = false; }
      if !c.http_only { ok = false; }
      if !streq(c.same_site, "Strict") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "set: attribute names are case-insensitive");
}

fn t11() -> TestResult {
  var ok = age_of(cookie_parse_set("a=1; Max-Age=3600")) == 3600;
  if age_of(cookie_parse_set("a=1; Max-Age=0")) != 0 { ok = false; }
  if age_of(cookie_parse_set("a=1; Max-Age=-1")) != -1 { ok = false; }
  if age_of(cookie_parse_set("a=1; Max-Age=+5")) != 5 { ok = false; }
  if !string.str_contains(ser_of(cookie_parse_set("a=1; Max-Age=0")), "; Max-Age=0") { ok = false; }
  if string.str_contains(ser_of(cookie_parse_set("a=1; Max-Age=-1")), "Max-Age") { ok = false; }
  return assert(ok, "set: Max-Age accepts signed integers");
}

fn t12() -> TestResult {
  var ok = age_of(cookie_parse_set("a=1; Max-Age=abc")) == -1;
  if age_of(cookie_parse_set("a=1; Max-Age=12x")) != -1 { ok = false; }
  if age_of(cookie_parse_set("a=1; Max-Age=")) != -1 { ok = false; }
  if age_of(cookie_parse_set("a=1; Max-Age=-")) != -1 { ok = false; }
  if age_of(cookie_parse_set("a=1; Max-Age=1 2")) != -1 { ok = false; }
  if age_of(cookie_parse_set("a=1; Max-Age=9999999999999999999")) != -1 { ok = false; }
  if age_of(cookie_parse_set("a=1; Max-Age=bad; Path=/p")) != -1 { ok = false; }
  if !streq(path_of(cookie_parse_set("a=1; Max-Age=bad; Path=/p")), "/p") { ok = false; }
  return assert(ok, "set: malformed Max-Age is ignored, later attributes still apply");
}

fn t13() -> TestResult {
  var ok = !secure_of(cookie_parse_set("a=1"));
  if http_of(cookie_parse_set("a=1")) { ok = false; }
  if !secure_of(cookie_parse_set("a=1; Secure")) { ok = false; }
  if !http_of(cookie_parse_set("a=1; HttpOnly")) { ok = false; }
  let both = cookie_parse_set("a=1; Secure; HttpOnly");
  if !secure_of(both) { ok = false; }
  if !http_of(both) { ok = false; }
  if secure_of(cookie_parse_set("a=1; Secure=1")) { ok = false; }
  if http_of(cookie_parse_set("a=1; HttpOnly=1")) { ok = false; }
  return assert(ok, "set: Secure and HttpOnly are bare flags");
}

fn t14() -> TestResult {
  var ok = streq(same_of(cookie_parse_set("a=1; SameSite=lax")), "Lax");
  if !streq(same_of(cookie_parse_set("a=1; SameSite=NONE")), "None") { ok = false; }
  if !streq(same_of(cookie_parse_set("a=1; SameSite=STRICT")), "Strict") { ok = false; }
  if !streq(same_of(cookie_parse_set("a=1; SameSite=weird")), "weird") { ok = false; }
  if !streq(same_of(cookie_parse_set("a=1; SameSite=")), "") { ok = false; }
  if !streq(same_of(cookie_parse_set("a=1; SameSite = Lax")), "Lax") { ok = false; }
  return assert(ok, "set: SameSite canonicalizes known values, keeps others raw");
}

fn t15() -> TestResult {
  var ok = set_err_prefix(cookie_parse_set(""));
  if !set_err_prefix(cookie_parse_set("   ")) { ok = false; }
  if !set_err_prefix(cookie_parse_set("plain")) { ok = false; }
  if !set_err_prefix(cookie_parse_set("; a=1")) { ok = false; }
  if !set_err_prefix(cookie_parse_set("=v; Path=/")) { ok = false; }
  if !set_err_is(cookie_parse_set("plain"), "cookie: missing name=value pair") { ok = false; }
  if !set_err_is(cookie_parse_set("=v"), "cookie: empty cookie name") { ok = false; }
  return assert(ok, "set: missing name=value is Err with a cookie: message");
}

fn t16() -> TestResult {
  var bare = SetCookie{
    name: "n";
    value: "v";
    path: "";
    domain: "";
    max_age: -1;
    secure: false;
    http_only: false;
    same_site: "";
  };
  var ok = streq(cookie_serialize_set(&bare), "n=v");
  bare.path = "/p";
  if !streq(cookie_serialize_set(&bare), "n=v; Path=/p") { ok = false; }
  bare.path = "";
  bare.max_age = 0;
  if !streq(cookie_serialize_set(&bare), "n=v; Max-Age=0") { ok = false; }
  var full = SetCookie{
    name: "n";
    value: "v";
    path: "/p";
    domain: "d.com";
    max_age: 5;
    secure: true;
    http_only: true;
    same_site: "Lax";
  };
  if !streq(cookie_serialize_set(&full), "n=v; Path=/p; Domain=d.com; Max-Age=5; Secure; HttpOnly; SameSite=Lax") { ok = false; }
  return assert(ok, "set: serialize omits empty attributes and keeps order");
}

fn t17() -> TestResult {
  var jar = cookie_parse_request("token=abc=def; x=1");
  var ok = cookie_count(&jar) == 2;
  if !opt_is(cookie_get(&jar, "token"), "abc=def") { ok = false; }
  let r = cookie_parse_set("t=a=b=c; Path=/");
  var ok2 = false;
  match r {
    Ok(c) => {
      ok2 = streq(c.value, "a=b=c");
      if !streq(c.path, "/") { ok2 = false; }
    },
    Err(_) => { ok2 = false; },
  }
  return assert(ok && ok2, "values may contain '=' and stay whole");
}

fn t18() -> TestResult {
  var a = cookie_parse_request("");
  var b = cookie_parse_request("   ");
  var c = cookie_parse_request("; ;");
  var ok = cookie_count(&a) == 0;
  if cookie_count(&b) != 0 { ok = false; }
  if cookie_count(&c) != 0 { ok = false; }
  if !streq(cookie_serialize_request(&a), "") { ok = false; }
  return assert(ok, "request: empty and separator-only input yields an empty jar");
}

fn t19() -> TestResult {
  let source = "sid=abc123; Path=/; Domain=example.com; Max-Age=3600; Secure; HttpOnly; SameSite=Lax";
  let r = cookie_parse_set(source);
  var ok = false;
  match r {
    Ok(c) => {
      let text = cookie_serialize_set(&c);
      ok = streq(text, source);
      let r2 = cookie_parse_set(text);
      match r2 {
        Ok(c2) => {
          if !streq(c2.name, "sid") { ok = false; }
          if !streq(c2.value, "abc123") { ok = false; }
          if !streq(c2.path, "/") { ok = false; }
          if !streq(c2.domain, "example.com") { ok = false; }
          if c2.max_age != 3600 { ok = false; }
          if !c2.secure { ok = false; }
          if !c2.http_only { ok = false; }
          if !streq(c2.same_site, "Lax") { ok = false; }
        },
        Err(_) => { ok = false; },
      }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "set: parse then serialize round-trips a full header");
}

fn t20() -> TestResult {
  var jar = cookie_parse_request("A=1; a=2");
  var ok = cookie_count(&jar) == 2;
  if !opt_is(cookie_get(&jar, "A"), "1") { ok = false; }
  if !opt_is(cookie_get(&jar, "a"), "2") { ok = false; }
  var trimmed = cookie_parse_request("n=1 ; n = 2");
  if cookie_count(&trimmed) != 1 { ok = false; }
  if !opt_is(cookie_get(&trimmed, "n"), "1") { ok = false; }
  var tail = cookie_parse_request("x=1;");
  if cookie_count(&tail) != 1 { ok = false; }
  return assert(ok, "request: names are case-sensitive and trim before dedup");
}

fn main() -> Int {
  io.println("=== xiom.cookie conformance tests ===");
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
    io.println("xiom.cookie: all tests passed");
  } else {
    io.println("xiom.cookie: tests failed");
  }
  return failed;
}
