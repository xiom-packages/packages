// XIOM -- xiom.sectest conformance tests (22 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Greenfield package: prove the pure-XIOM xiom.sectest header parser and
// security-header policy against the documented rules in SPEC.md.
//
// Coverage: parsing (CRLF, OWS, empty values, duplicates, folded and
// malformed lines), case-insensitive lookups, every rule of the policy
// (missing/present/edge values), report ordering, severity counts, summary,
// passed flag and accessor bounds. All Str comparisons go through
// str_compare.

module sectest_tests
use xiom.io; use xiom.test; use xiom.sectest;
use xiom.string; use xiom.string.compare;

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// True when finding `i` has exactly the wanted rule, severity and message.
fn finding_is(r: &SectestReport, i: Int, rule: Str, sev: Str, msg: Str) -> Bool {
  if !streq(sectest_finding_rule(r, i), rule) { return false; }
  if !streq(sectest_finding_severity(r, i), sev) { return false; }
  if !streq(sectest_finding_message(r, i), msg) { return false; }
  return true;
}

// True when the report contains at least one finding for `rule`.
fn has_rule(r: &SectestReport, rule: Str) -> Bool {
  var i = 0;
  while i < sectest_finding_count(r) {
    if streq(sectest_finding_rule(r, i), rule) { return true; }
    i = i + 1;
  }
  return false;
}

// True when parsing fails with exactly the message `want`.
fn parse_err_is(text: Str, want: Str) -> Bool {
  let r = sectest_headers_parse(text);
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

// Exact good block used by several checks.
fn good_block() -> Str {
  return "Strict-Transport-Security: max-age=63072000; includeSubDomains\nContent-Security-Policy: default-src 'self'\nX-Content-Type-Options: nosniff\nX-Frame-Options: DENY\nReferrer-Policy: strict-origin-when-cross-origin\nPermissions-Policy: geolocation=()\n";
}

// The hardened block with `from` replaced by `to`: isolates one rule's
// finding at index 0.
fn variant(from: Str, to: Str) -> Str {
  return string.str_replace_all(good_block(), from, to);
}

// The hardened block without one header line: isolates a missing-header rule.
fn without(line: Str) -> Str {
  return string.str_replace_all(good_block(), line, "");
}

fn t1() -> TestResult {
  let r = sectest_headers_parse("Content-Type: text/html\nX-Trace: abc\n");
  var ok = false;
  match r {
    Ok(h) => {
      ok = sectest_header_count(&h) == 2;
      if !streq(sectest_header_name(&h, 0), "Content-Type") { ok = false; }
      if !streq(sectest_header_value(&h, 0), "text/html") { ok = false; }
      if !streq(sectest_header_name(&h, 1), "X-Trace") { ok = false; }
      if !streq(sectest_header_value(&h, 1), "abc") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "header lines parse into names and values in order");
}

fn t2() -> TestResult {
  let r = sectest_headers_parse("X-A :  spaced value  \r\n\r\nX-Empty:\r\n");
  var ok = false;
  match r {
    Ok(h) => {
      ok = sectest_header_count(&h) == 2;
      if !streq(sectest_header_name(&h, 0), "X-A") { ok = false; }
      if !streq(sectest_header_value(&h, 0), "spaced value") { ok = false; }
      if !streq(sectest_header_value(&h, 1), "") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "CRLF, blank lines and OWS around the colon are handled");
}

fn t3() -> TestResult {
  let r = sectest_headers_parse("X-Frame-Options: DENY\nx-frame-options: SAMEORIGIN\n");
  var ok = false;
  match r {
    Ok(h) => {
      ok = sectest_header_count_named(&h, "X-FRAME-OPTIONS") == 2;
      if !streq(sectest_header_get(&h, "x-FRAME-options"), "DENY") { ok = false; }
      if !streq(sectest_header_get(&h, "X-Missing"), "") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "lookups are case-insensitive and return the first duplicate");
}

fn t4() -> TestResult {
  var ok = parse_err_is("NoColonHere\n", "sectest: malformed header line 1");
  if !parse_err_is(": value", "sectest: malformed header line 1") { ok = false; }
  if !parse_err_is("A: 1\n folded", "sectest: folded header line 2") { ok = false; }
  let empty = sectest_headers_parse("");
  match empty {
    Ok(h) => { if sectest_header_count(&h) != 0 { ok = false; } },
    Err(_) => { ok = false; },
  }
  return assert(ok, "malformed and folded lines are Err with line numbers");
}

fn t5() -> TestResult {
  let r = sectest_headers_parse("X-Frame-Options: DENY\n");
  var ok = false;
  match r {
    Ok(h) => {
      let rep = sectest_check(&h);
      ok = finding_is(&rep, 0, "hsts", "high", "missing Strict-Transport-Security");
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "a missing HSTS header is a high finding");
}

fn t6() -> TestResult {
  let r = sectest_headers_parse(good_block());
  var ok = false;
  match r {
    Ok(h) => {
      let rep = sectest_check(&h);
      ok = sectest_finding_count(&rep) == 0;
      if !sectest_passed(&rep) { ok = false; }
      if !streq(sectest_summary(&rep), "no findings") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "the fully hardened block has no findings");
}

fn t7() -> TestResult {
  let r = sectest_headers_parse(variant("max-age=63072000", "max-age=3600"));
  var ok = false;
  match r {
    Ok(h) => {
      let rep = sectest_check(&h);
      ok = sectest_finding_count(&rep) == 1;
      if !finding_is(&rep, 0, "hsts", "medium", "HSTS max-age 3600 is below 31536000") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "an HSTS max-age below one year is a medium finding");
}

fn t8() -> TestResult {
  var ok = false;
  let r1 = sectest_headers_parse(variant("Strict-Transport-Security: max-age=63072000; includeSubDomains", "Strict-Transport-Security: includeSubDomains"));
  match r1 {
    Ok(h) => {
      let rep = sectest_check(&h);
      ok = sectest_finding_count(&rep) == 1;
      if !finding_is(&rep, 0, "hsts", "medium", "HSTS without max-age") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let r2 = sectest_headers_parse(variant("max-age=63072000", "max-age=abc"));
  match r2 {
    Ok(h) => {
      let rep = sectest_check(&h);
      if sectest_finding_count(&rep) != 1 { ok = false; }
      if !finding_is(&rep, 0, "hsts", "medium", "HSTS max-age is not a number") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "a missing or malformed HSTS max-age is a medium finding");
}

fn t9() -> TestResult {
  let r = sectest_headers_parse(variant("; includeSubDomains", ""));
  var ok = false;
  match r {
    Ok(h) => {
      let rep = sectest_check(&h);
      ok = sectest_finding_count(&rep) == 1;
      if !finding_is(&rep, 0, "hsts", "low", "HSTS without includeSubDomains") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "HSTS without includeSubDomains is a low finding");
}

fn t10() -> TestResult {
  var ok = false;
  let r1 = sectest_headers_parse(good_block());
  match r1 {
    Ok(h) => {
      let rep = sectest_check(&h);
      ok = !has_rule(&rep, "csp");
    },
    Err(_) => { ok = false; },
  }
  let r2 = sectest_headers_parse(variant("default-src 'self'", "default-src 'self'; script-src 'unsafe-inline' 'unsafe-eval'"));
  match r2 {
    Ok(h) => {
      let rep = sectest_check(&h);
      if sectest_finding_count(&rep) != 2 { ok = false; }
      if !finding_is(&rep, 0, "csp", "medium", "CSP allows 'unsafe-inline'") { ok = false; }
      if !finding_is(&rep, 1, "csp", "medium", "CSP allows 'unsafe-eval'") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let r3 = sectest_headers_parse(without("Content-Security-Policy: default-src 'self'\n"));
  match r3 {
    Ok(h) => {
      let rep = sectest_check(&h);
      if sectest_finding_count(&rep) != 1 { ok = false; }
      if !finding_is(&rep, 0, "csp", "high", "missing Content-Security-Policy") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "CSP missing, unsafe-inline and unsafe-eval are detected");
}

fn t11() -> TestResult {
  var ok = false;
  let r1 = sectest_headers_parse(variant("nosniff", "NoSniff"));
  match r1 {
    Ok(h) => {
      let rep = sectest_check(&h);
      ok = !has_rule(&rep, "x-content-type-options");
    },
    Err(_) => { ok = false; },
  }
  let r2 = sectest_headers_parse(variant("nosniff", "sniff"));
  match r2 {
    Ok(h) => {
      let rep = sectest_check(&h);
      if sectest_finding_count(&rep) != 1 { ok = false; }
      if !finding_is(&rep, 0, "x-content-type-options", "medium", "X-Content-Type-Options is not nosniff") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "X-Content-Type-Options must be nosniff (case-insensitive)");
}

fn t12() -> TestResult {
  var ok = false;
  let r1 = sectest_headers_parse(variant("X-Frame-Options: DENY", "X-Frame-Options: sameorigin"));
  match r1 {
    Ok(h) => {
      let rep = sectest_check(&h);
      ok = !has_rule(&rep, "x-frame-options");
    },
    Err(_) => { ok = false; },
  }
  let r2 = sectest_headers_parse(variant("X-Frame-Options: DENY", "X-Frame-Options: ALLOW-FROM https://example.com"));
  match r2 {
    Ok(h) => {
      let rep = sectest_check(&h);
      if sectest_finding_count(&rep) != 1 { ok = false; }
      if !finding_is(&rep, 0, "x-frame-options", "medium", "X-Frame-Options is not DENY or SAMEORIGIN") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "X-Frame-Options must be DENY or SAMEORIGIN");
}

fn t13() -> TestResult {
  var ok = false;
  let r1 = sectest_headers_parse(variant("strict-origin-when-cross-origin", "no-referrer"));
  match r1 {
    Ok(h) => {
      let rep = sectest_check(&h);
      ok = !has_rule(&rep, "referrer-policy");
    },
    Err(_) => { ok = false; },
  }
  let r2 = sectest_headers_parse(variant("strict-origin-when-cross-origin", "always"));
  match r2 {
    Ok(h) => {
      let rep = sectest_check(&h);
      if sectest_finding_count(&rep) != 1 { ok = false; }
      if !finding_is(&rep, 0, "referrer-policy", "low", "Referrer-Policy value is not recognized") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let r3 = sectest_headers_parse(without("Referrer-Policy: strict-origin-when-cross-origin\n"));
  match r3 {
    Ok(h) => {
      let rep = sectest_check(&h);
      if sectest_finding_count(&rep) != 1 { ok = false; }
      if !finding_is(&rep, 0, "referrer-policy", "low", "missing Referrer-Policy") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "Referrer-Policy tokens are checked against the documented set");
}

fn t14() -> TestResult {
  var ok = false;
  let r1 = sectest_headers_parse(good_block());
  match r1 {
    Ok(h) => {
      let rep = sectest_check(&h);
      ok = !has_rule(&rep, "permissions-policy");
    },
    Err(_) => { ok = false; },
  }
  let r2 = sectest_headers_parse(without("Permissions-Policy: geolocation=()\n"));
  match r2 {
    Ok(h) => {
      let rep = sectest_check(&h);
      if sectest_finding_count(&rep) != 1 { ok = false; }
      if !finding_is(&rep, 0, "permissions-policy", "low", "missing Permissions-Policy") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "Permissions-Policy presence is required");
}

fn t15() -> TestResult {
  let text = good_block() + "X-XSS-Protection: 1; mode=block\n";
  let r = sectest_headers_parse(text);
  var ok = false;
  match r {
    Ok(h) => {
      let rep = sectest_check(&h);
      ok = sectest_finding_count(&rep) == 1;
      if !finding_is(&rep, 0, "x-xss-protection", "info", "X-XSS-Protection is deprecated") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "a present X-XSS-Protection header is an info finding");
}

fn t16() -> TestResult {
  let text = good_block() + "Server: nginx/1.25\nX-Powered-By: PHP/8.3\n";
  let r = sectest_headers_parse(text);
  var ok = false;
  match r {
    Ok(h) => {
      let rep = sectest_check(&h);
      ok = sectest_finding_count(&rep) == 2;
      if !finding_is(&rep, 0, "disclosure", "low", "information disclosure via Server") { ok = false; }
      if !finding_is(&rep, 1, "disclosure", "low", "information disclosure via X-Powered-By") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "server-identifying headers are low disclosure findings");
}

fn t17() -> TestResult {
  let text = "X-Frame-Options: ALLOW-FROM https://x\nServer: nginx\nX-XSS-Protection: 1; mode=block\n";
  let r = sectest_headers_parse(text);
  var ok = false;
  match r {
    Ok(h) => {
      let rep = sectest_check(&h);
      ok = sectest_finding_count(&rep) == 8;
      if !finding_is(&rep, 0, "hsts", "high", "missing Strict-Transport-Security") { ok = false; }
      if !finding_is(&rep, 1, "csp", "high", "missing Content-Security-Policy") { ok = false; }
      if !finding_is(&rep, 2, "x-content-type-options", "medium", "missing X-Content-Type-Options") { ok = false; }
      if !finding_is(&rep, 3, "x-frame-options", "medium", "X-Frame-Options is not DENY or SAMEORIGIN") { ok = false; }
      if !finding_is(&rep, 4, "referrer-policy", "low", "missing Referrer-Policy") { ok = false; }
      if !finding_is(&rep, 5, "permissions-policy", "low", "missing Permissions-Policy") { ok = false; }
      if !finding_is(&rep, 6, "x-xss-protection", "info", "X-XSS-Protection is deprecated") { ok = false; }
      if !finding_is(&rep, 7, "disclosure", "low", "information disclosure via Server") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "findings are reported in the fixed rule order");
}

fn t18() -> TestResult {
  let text = "X-Frame-Options: ALLOW-FROM https://x\nServer: nginx\nX-XSS-Protection: 1; mode=block\n";
  let r = sectest_headers_parse(text);
  var ok = false;
  match r {
    Ok(h) => {
      let rep = sectest_check(&h);
      ok = sectest_count_severity(&rep, "high") == 2;
      if sectest_count_severity(&rep, "medium") != 2 { ok = false; }
      if sectest_count_severity(&rep, "low") != 3 { ok = false; }
      if sectest_count_severity(&rep, "info") != 1 { ok = false; }
      if !streq(sectest_summary(&rep), "8 findings: 2 high, 2 medium, 3 low, 1 info") { ok = false; }
      if sectest_passed(&rep) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "severity counts and the summary line are deterministic");
}

fn t19() -> TestResult {
  var ok = false;
  let r = sectest_headers_parse(good_block());
  match r {
    Ok(h) => {
      let rep = sectest_check(&h);
      ok = sectest_passed(&rep);
      if sectest_finding_count(&rep) != 0 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "a hardened block passes the high/medium gate");
}

fn t20() -> TestResult {
  let r = sectest_headers_parse("");
  var ok = false;
  match r {
    Ok(h) => {
      ok = sectest_header_count(&h) == 0;
      if !streq(sectest_header_name(&h, 0), "") { ok = false; }
      if !streq(sectest_header_value(&h, -1), "") { ok = false; }
      if !streq(sectest_header_get(&h, "X-Any"), "") { ok = false; }
      if sectest_header_count_named(&h, "X-Any") != 0 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "empty blocks and out-of-range accessors are safe");
}

fn t21() -> TestResult {
  let r = sectest_headers_parse("X-Frame-Options: DENY\nX-Frame-Options: ALLOW-FROM https://x\n");
  var ok = false;
  match r {
    Ok(h) => {
      ok = sectest_header_count(&h) == 2;
      if sectest_header_count_named(&h, "X-Frame-Options") != 2 { ok = false; }
      if !streq(sectest_header_get(&h, "X-Frame-Options"), "DENY") { ok = false; }
      let rep = sectest_check(&h);
      if has_rule(&rep, "x-frame-options") { ok = false; }
      if sectest_count_severity(&rep, "medium") != 1 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "duplicate headers are preserved; the first wins for checks");
}

fn t22() -> TestResult {
  let r = sectest_headers_parse("strict-transport-security: MAX-AGE=63072000; IncludeSubDomains\nx-content-type-options: NOSNIFF\n");
  var ok = false;
  match r {
    Ok(h) => {
      let rep = sectest_check(&h);
      ok = !has_rule(&rep, "hsts");
      if has_rule(&rep, "x-content-type-options") { ok = false; }
      if sectest_count_severity(&rep, "high") != 1 { ok = false; }
      if sectest_count_severity(&rep, "medium") != 1 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "header names and HSTS directives match case-insensitively");
}

fn main() -> Int {
  io.println("=== xiom.sectest conformance tests ===");
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
    io.println("xiom.sectest: all tests passed");
  } else {
    io.println("xiom.sectest: tests failed");
  }
  return failed;
}
