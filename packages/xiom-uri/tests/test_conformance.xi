// XIOM -- xiom.uri conformance tests (22 checks)
// Greenfield task: prove the pure-XIOM xiom.uri module against the RFC 3986
// generic syntax and the documented component helpers.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Coverage map (see SPEC.md section 8): full URL split, no-authority
// (mailto), relative path, query-only and fragment-only forms, three parse ->
// to_string round trips, percent decode (mixed case, literal '+', malformed
// escapes) and encode in both modes (reserved literal vs fully encoded,
// uppercase hex), byte-wise UTF-8 encoding, host/userinfo/port extraction
// (user:pass@host:8080, IPv6 [::1]:443), port error cases, query_get first
// match and decoding, is_absolute, malformed schemes, empty input, the
// appendix-B ':' rule and encode/decode round trips.
//
// All Str equality goes through str_compare: BUG 17 lowers `==` on Str values
// read from Vec[Str] elements to a pointer comparison, so every comparison
// below is routed through streq.

module uri_tests
use xiom.io; use xiom.test; use xiom.uri;
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

// Ok(text) with text equal to `want`.
fn uri_ok_is(r: Result[Str, Str], want: Str) -> Bool {
  match r {
    Ok(v) => { return streq(v, want); },
    Err(_) => { return false; },
  }
  return false;
}

// Err whose message starts with "uri: ".
fn uri_err_prefix(r: Result[Str, Str]) -> Bool {
  match r {
    Ok(_) => { return false; },
    Err(e) => { return string.str_starts_with(e, "uri: "); },
  }
  return false;
}

// Err with exactly `want` as the message.
fn uri_err_is(r: Result[Str, Str], want: Str) -> Bool {
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

// True when `s` parses to exactly the five pinned components.
fn split_is(s: Str, sch: Str, auth: Str, path: Str, q: Str, frag: Str) -> Bool {
  let r = uri_parse(s);
  match r {
    Ok(u) => {
      if !streq(u.scheme, sch) { return false; }
      if !streq(u.authority, auth) { return false; }
      if !streq(u.path, path) { return false; }
      if !streq(u.query, q) { return false; }
      if !streq(u.fragment, frag) { return false; }
      return true;
    },
    Err(_) => { return false; },
  }
  return false;
}

// True when parse then to_string reproduces `s` exactly.
fn rt_is(s: Str) -> Bool {
  let r = uri_parse(s);
  match r {
    Ok(u) => { return streq(uri_to_string(&u), s); },
    Err(_) => { return false; },
  }
  return false;
}

// A Uri with only the authority set.
fn uri_with(auth: Str) -> Uri {
  return Uri{ scheme: ""; authority: auth; path: ""; query: ""; fragment: ""; };
}

// A Uri with only the query set.
fn query_uri(q: Str) -> Uri {
  return Uri{ scheme: ""; authority: ""; path: ""; query: q; fragment: ""; };
}

fn host_of(auth: Str) -> Str {
  let u = uri_with(auth);
  return uri_host(&u);
}

fn port_of(auth: Str) -> Int {
  let u = uri_with(auth);
  return uri_port(&u);
}

fn qget(q: Str, name: Str) -> Option[Str] {
  let u = query_uri(q);
  return uri_query_get(&u, name);
}

fn abs_of(s: Str) -> Bool {
  let r = uri_parse(s);
  match r {
    Ok(u) => { return uri_is_absolute(&u); },
    Err(_) => { return false; },
  }
  return false;
}

// True when `s` parses with an Err message starting "uri: ".
fn parse_err_prefix(s: Str) -> Bool {
  let r = uri_parse(s);
  match r {
    Ok(_) => { return false; },
    Err(e) => { return string.str_starts_with(e, "uri: "); },
  }
  return false;
}

// True when `s` parses with exactly `want` as the Err message.
fn parse_err_is(s: Str, want: Str) -> Bool {
  let r = uri_parse(s);
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

// True when encode (both modes) then decode reproduces `s`.
fn pct_rt(s: Str) -> Bool {
  let e1 = uri_percent_encode(s, false);
  let d1 = uri_percent_decode(e1);
  var ok = false;
  match d1 {
    Ok(v) => { ok = streq(v, s); },
    Err(_) => { ok = false; },
  }
  if !ok { return false; }
  let e2 = uri_percent_encode(s, true);
  let d2 = uri_percent_decode(e2);
  var ok2 = false;
  match d2 {
    Ok(v2) => { ok2 = streq(v2, s); },
    Err(_) => { ok2 = false; },
  }
  return ok2;
}

fn t1() -> TestResult {
  let ok = split_is("https://user:pass@example.com:8080/path/to?x=1&y=2#frag",
    "https", "user:pass@example.com:8080", "/path/to", "x=1&y=2", "frag");
  return assert(ok, "parse: full URL split pinned");
}

fn t2() -> TestResult {
  let ok = split_is("mailto:user@example.com", "mailto", "", "user@example.com", "", "");
  return assert(ok, "parse: no-authority mailto form");
}

fn t3() -> TestResult {
  let ok = split_is("docs/guide.html", "", "", "docs/guide.html", "", "");
  return assert(ok, "parse: relative path");
}

fn t4() -> TestResult {
  let ok = split_is("?q=hello&lang=en", "", "", "", "q=hello&lang=en", "");
  return assert(ok, "parse: query-only reference");
}

fn t5() -> TestResult {
  let ok = split_is("#section-2", "", "", "", "", "section-2");
  return assert(ok, "parse: fragment-only reference");
}

fn t6() -> TestResult {
  var ok = rt_is("https://user@example.com:8443/a/b?q=1&r=2#frag");
  if !rt_is("mailto:user@example.com") { ok = false; }
  if !rt_is("/assets/app.js?v=2") { ok = false; }
  return assert(ok, "round-trip: parse then to_string for three forms");
}

fn t7() -> TestResult {
  var ok = uri_ok_is(uri_percent_decode("%48%65llo%20World"), "Hello World");
  if !uri_ok_is(uri_percent_decode("%2f%2F"), "//") { ok = false; }
  if !uri_ok_is(uri_percent_decode("%41%62%43"), "AbC") { ok = false; }
  if !uri_ok_is(uri_percent_decode("%68%C3%A9llo"), "héllo") { ok = false; }
  if !uri_ok_is(uri_percent_decode("plain"), "plain") { ok = false; }
  if !uri_ok_is(uri_percent_decode(""), "") { ok = false; }
  return assert(ok, "percent decode: mixed-case hex and plain bytes");
}

fn t8() -> TestResult {
  var ok = uri_err_is(uri_percent_decode("%2"), "uri: truncated percent escape");
  if !uri_err_prefix(uri_percent_decode("%")) { ok = false; }
  if !uri_err_prefix(uri_percent_decode("abc%")) { ok = false; }
  if !uri_err_is(uri_percent_decode("%2G"), "uri: invalid percent escape") { ok = false; }
  if !uri_err_prefix(uri_percent_decode("%GG")) { ok = false; }
  if !uri_err_prefix(uri_percent_decode("100%x")) { ok = false; }
  return assert(ok, "percent decode: malformed escapes are Err");
}

fn t9() -> TestResult {
  var ok = uri_ok_is(uri_percent_decode("a+b"), "a+b");
  if !uri_ok_is(uri_percent_decode("%2B"), "+") { ok = false; }
  if !uri_ok_is(uri_percent_decode("+%20+"), "+ +") { ok = false; }
  return assert(ok, "percent decode: '+' stays a literal plus");
}

fn t10() -> TestResult {
  var ok = streq(uri_percent_encode("a b/c?d=e&f", false), "a%20b/c?d=e&f");
  if !streq(uri_percent_encode("~._-", false), "~._-") { ok = false; }
  if !streq(uri_percent_encode(":/?#[]@!$&'()*+,;=", false), ":/?#[]@!$&'()*+,;=") { ok = false; }
  if !streq(uri_percent_encode("100%", false), "100%25") { ok = false; }
  if !streq(uri_percent_encode("é", false), "%C3%A9") { ok = false; }
  return assert(ok, "percent encode: reserved kept literal (mode false)");
}

fn t11() -> TestResult {
  var ok = streq(uri_percent_encode("a b/c?d=e&f", true), "a%20b%2Fc%3Fd%3De%26f");
  if !streq(uri_percent_encode("~._-", true), "~._-") { ok = false; }
  if !streq(uri_percent_encode("+", true), "%2B") { ok = false; }
  if !streq(uri_percent_encode("100%", true), "100%25") { ok = false; }
  if !streq(uri_percent_encode(":/?#[]@!$&'()*+,;=", true), "%3A%2F%3F%23%5B%5D%40%21%24%26%27%28%29%2A%2B%2C%3B%3D") { ok = false; }
  return assert(ok, "percent encode: fully encoded uppercase hex (mode true)");
}

fn t12() -> TestResult {
  var ok = streq(uri_percent_encode("héllo", false), "h%C3%A9llo");
  if !streq(uri_percent_encode("héllo", true), "h%C3%A9llo") { ok = false; }
  if !streq(uri_percent_encode("😀", false), "%F0%9F%98%80") { ok = false; }
  if !streq(uri_percent_encode("😀", true), "%F0%9F%98%80") { ok = false; }
  if !uri_ok_is(uri_percent_decode("%F0%9F%98%80"), "😀") { ok = false; }
  return assert(ok, "percent encode: unicode bytes encoded byte-wise");
}

fn t13() -> TestResult {
  var ok = streq(host_of("user:pass@host:8080"), "host");
  if !streq(host_of("example.com"), "example.com") { ok = false; }
  if !streq(host_of("user@example.com"), "example.com") { ok = false; }
  if !streq(host_of("user:pass@[::1]:443"), "[::1]") { ok = false; }
  if !streq(host_of(""), "") { ok = false; }
  return assert(ok, "host: authority minus userinfo and port");
}

fn t14() -> TestResult {
  var ok = streq(host_of("[::1]:443"), "[::1]");
  if port_of("[::1]:443") != 443 { ok = false; }
  if !streq(host_of("[2001:db8::1]"), "[2001:db8::1]") { ok = false; }
  if port_of("[2001:db8::1]") != -1 { ok = false; }
  if port_of("[::1]:") != -1 { ok = false; }
  if port_of("[::1]:abc") != -1 { ok = false; }
  return assert(ok, "host/port: IPv6 brackets kept, invalid port -1");
}

fn t15() -> TestResult {
  var ok = port_of("host:8080") == 8080;
  if port_of("host") != -1 { ok = false; }
  if port_of("host:") != -1 { ok = false; }
  if port_of("host:abc") != -1 { ok = false; }
  if port_of("user:pass@host:99") != 99 { ok = false; }
  if port_of("example.com:65535") != 65535 { ok = false; }
  if port_of("") != -1 { ok = false; }
  return assert(ok, "port: parsed when present, -1 when absent or invalid");
}

fn t16() -> TestResult {
  var ok = opt_is(qget("a=1&b=hello%20world&a=3", "a"), "1");
  if !opt_is(qget("a=1&b=hello%20world&a=3", "b"), "hello world") { ok = false; }
  if !opt_none(qget("a=1&b=2", "c")) { ok = false; }
  if !opt_none(qget("a=1&b=2", "A")) { ok = false; }
  if !opt_is(qget("flag&x=1", "flag"), "") { ok = false; }
  if !opt_none(qget("", "a")) { ok = false; }
  return assert(ok, "query_get: first match wins, value decoded");
}

fn t17() -> TestResult {
  var ok = opt_is(qget("x=%zz&y=ok", "x"), "%zz");
  if !opt_is(qget("x=%zz&y=ok", "y"), "ok") { ok = false; }
  if !opt_is(qget("a%20b=1", "a%20b"), "1") { ok = false; }
  if !opt_none(qget("a%20b=1", "a b")) { ok = false; }
  if !opt_is(qget("k=a+b", "k"), "a+b") { ok = false; }
  return assert(ok, "query_get: raw name match, invalid escape literal");
}

fn t18() -> TestResult {
  var ok = abs_of("http://example.com/x");
  if !abs_of("mailto:a@b") { ok = false; }
  if abs_of("/p") { ok = false; }
  if abs_of("?q") { ok = false; }
  if abs_of("#f") { ok = false; }
  if abs_of("") { ok = false; }
  if abs_of("docs/x") { ok = false; }
  return assert(ok, "is_absolute: scheme non-empty only");
}

fn t19() -> TestResult {
  var ok = parse_err_is(":x", "uri: empty scheme");
  if !parse_err_prefix("1abc:x") { ok = false; }
  if !parse_err_prefix("a_b:x") { ok = false; }
  if !parse_err_prefix("a b:x") { ok = false; }
  if !parse_err_prefix("ht%tp:x") { ok = false; }
  if !split_is("a+b.c-d:x", "a+b.c-d", "", "x", "", "") { ok = false; }
  return assert(ok, "malformed schemes are Err, valid scheme chars accepted");
}

fn t20() -> TestResult {
  var ok = split_is("", "", "", "", "", "");
  if !rt_is("") { ok = false; }
  if !parse_err_is(":", "uri: empty scheme") { ok = false; }
  return assert(ok, "empty string parses to five empty components");
}

fn t21() -> TestResult {
  var ok = split_is("/a:b/c", "", "", "/a:b/c", "", "");
  if !split_is("a/b:c", "", "", "a/b:c", "", "") { ok = false; }
  if !split_is("?x:y", "", "", "", "x:y", "") { ok = false; }
  if !split_is("http://h/a:b?c:d#e:f", "http", "h", "/a:b", "c:d", "e:f") { ok = false; }
  return assert(ok, "':' after the first '/' is not a scheme separator");
}

fn t22() -> TestResult {
  var ok = pct_rt("a b");
  if !pct_rt("é") { ok = false; }
  if !pct_rt("a/b?c=d&e") { ok = false; }
  if !pct_rt("100% +") { ok = false; }
  if !pct_rt("😀 ok") { ok = false; }
  let bare = Uri{ scheme: ""; authority: ""; path: "p"; query: ""; fragment: ""; };
  if !streq(uri_to_string(&bare), "p") { ok = false; }
  let full = Uri{ scheme: "https"; authority: "h:1"; path: "/x"; query: "q=1"; fragment: "z" };
  if !streq(uri_to_string(&full), "https://h:1/x?q=1#z") { ok = false; }
  return assert(ok, "percent and to_string round-trips, '//' rule");
}

fn main() -> Int {
  io.println("=== xiom.uri conformance tests ===");
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
    io.println("xiom.uri: all tests passed");
  } else {
    io.println("xiom.uri: tests failed");
  }
  return failed;
}
