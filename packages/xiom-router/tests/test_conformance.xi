// XIOM -- xiom.router conformance tests (22 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Coverage map: see SPEC.md section 6. Every check is a named
// assert(cond, "name") call and main returns the failure count (0 = green).
// All Str equality goes through compare.str_compare via the local streq
// helper (BUG 17 discipline: `==` on Str values is never used). Every
// Vec element read is bound to a typed local first.

module router_tests

use xiom.io; use xiom.test; use xiom.router;
use xiom.string.compare;

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// True when r is Ok(v) with v == want.
fn int_ok_is(r: Result[Int, Str], want: Int) -> Bool {
  if !r.is_ok {
    return false;
  }
  let v: Int = r.value;
  return v == want;
}

// True when r is Err with exactly the message `want`.
fn int_err_is(r: Result[Int, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  let m: Str = r.error;
  return streq(m, want);
}

// True when r is Ok(v) with v equal to want.
fn str_ok_is(r: Result[Str, Str], want: Str) -> Bool {
  if !r.is_ok {
    return false;
  }
  let v: Str = r.value;
  return streq(v, want);
}

// True when r is Err with exactly the message `want`.
fn str_err_is(r: Result[Str, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  let m: Str = r.error;
  return streq(m, want);
}

// True when v and want are element-wise equal Str vectors.
fn str_list_is(v: Vec[Str], want: Vec[Str]) -> Bool {
  if v.len() != want.len() {
    return false;
  }
  var i = 0;
  while i < v.len() {
    let a: Str = v[i];
    let b: Str = want[i];
    if !streq(a, b) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  var r = router_new();
  let a = router_add(&mut r, "GET", "/users");
  var ok = int_ok_is(a, 0);
  let m = router_match(&r, "GET", "/users");
  if m.code != 200 { ok = false; }
  if m.index != 0 { ok = false; }
  if m.params.len() != 0 { ok = false; }
  if router_count(&r) != 1 { ok = false; }
  return assert(ok, "exact match: GET /users -> 200 index 0, no params");
}

fn t2() -> TestResult {
  var r = router_new();
  let a = router_add(&mut r, "GET", "/users/:id");
  let b = router_add(&mut r, "GET", "/users/me");
  var ok = int_ok_is(a, 0) && int_ok_is(b, 1);
  let m = router_match(&r, "GET", "/users/me");
  if m.code != 200 { ok = false; }
  if m.index != 0 { ok = false; }
  if m.params.len() != 1 { ok = false; }
  let p0: RouteParam = m.params[0];
  if !streq(p0.name, "id") { ok = false; }
  if !streq(p0.value, "me") { ok = false; }
  var r2 = router_new();
  let c = router_add(&mut r2, "GET", "/users/me");
  let d = router_add(&mut r2, "GET", "/users/:id");
  if !int_ok_is(c, 0) { ok = false; }
  if !int_ok_is(d, 1) { ok = false; }
  let m2 = router_match(&r2, "GET", "/users/me");
  if m2.code != 200 { ok = false; }
  if m2.index != 0 { ok = false; }
  if m2.params.len() != 0 { ok = false; }
  return assert(ok, "first-match: earlier registration wins over the literal (both orders)");
}

fn t3() -> TestResult {
  var r = router_new();
  let a = router_add(&mut r, "GET", "/users/:id");
  var ok = int_ok_is(a, 0);
  let m = router_match(&r, "GET", "/users/42");
  if m.code != 200 { ok = false; }
  if m.index != 0 { ok = false; }
  if m.params.len() != 1 { ok = false; }
  let p0: RouteParam = m.params[0];
  if !streq(p0.name, "id") { ok = false; }
  if !streq(p0.value, "42") { ok = false; }
  return assert(ok, "param capture: a single :id captures the raw segment");
}

fn t4() -> TestResult {
  var r = router_new();
  let a = router_add(&mut r, "GET", "/:a/b/:c");
  var ok = int_ok_is(a, 0);
  let m = router_match(&r, "GET", "/x/b/z");
  if m.code != 200 { ok = false; }
  if m.params.len() != 2 { ok = false; }
  let p0: RouteParam = m.params[0];
  let p1: RouteParam = m.params[1];
  if !streq(p0.name, "a") { ok = false; }
  if !streq(p0.value, "x") { ok = false; }
  if !streq(p1.name, "c") { ok = false; }
  if !streq(p1.value, "z") { ok = false; }
  let bad = router_match(&r, "GET", "/x/q/z");
  if bad.code != 404 { ok = false; }
  return assert(ok, "params: multiple captures in path order; literals must match");
}

fn t5() -> TestResult {
  var r = router_new();
  let a = router_add(&mut r, "GET", "/a/:p");
  var ok = int_ok_is(a, 0);
  let m = router_match(&r, "GET", "/a/");
  if m.code != 404 { ok = false; }
  if m.index != -1 { ok = false; }
  if m.params.len() != 0 { ok = false; }
  let allow = router_allowed_methods(&r, "/a/");
  if allow.len() != 0 { ok = false; }
  let m2 = router_match(&r, "GET", "/a");
  if m2.code != 404 { ok = false; }
  return assert(ok, "param rejects an empty segment: /a/:p does not match /a/");
}

fn t6() -> TestResult {
  var r = router_new();
  let a = router_add(&mut r, "GET", "/a/b");
  var ok = int_ok_is(a, 0);
  let m1 = router_match(&r, "GET", "/nope");
  let m2 = router_match(&r, "GET", "/a/b/c");
  let m3 = router_match(&r, "GET", "/a");
  if m1.code != 404 { ok = false; }
  if m1.index != -1 { ok = false; }
  if m1.params.len() != 0 { ok = false; }
  if m2.code != 404 { ok = false; }
  if m3.code != 404 { ok = false; }
  return assert(ok, "404: unknown path and segment-count mismatches");
}

fn t7() -> TestResult {
  var r = router_new();
  let a = router_add(&mut r, "GET", "/x");
  let b = router_add(&mut r, "POST", "/x");
  var ok = int_ok_is(a, 0) && int_ok_is(b, 1);
  let m = router_match(&r, "PUT", "/x");
  if m.code != 405 { ok = false; }
  if m.index != -1 { ok = false; }
  if m.params.len() != 0 { ok = false; }
  let allow = router_allowed_methods(&r, "/x");
  var want = Vec[Str].new();
  want.push("GET");
  want.push("POST");
  if !str_list_is(allow, want) { ok = false; }
  let g = router_match(&r, "GET", "/x");
  if g.code != 200 { ok = false; }
  if g.index != 0 { ok = false; }
  return assert(ok, "405: PUT /x -> 405 with Allow GET, POST; GET still 200");
}

fn t8() -> TestResult {
  var r = router_new();
  let a = router_add(&mut r, "get", "/y");
  var ok = int_ok_is(a, 0);
  let up = router_match(&r, "GET", "/y");
  if up.code != 405 { ok = false; }
  let lo = router_match(&r, "get", "/y");
  if lo.code != 200 { ok = false; }
  if lo.index != 0 { ok = false; }
  let mixed = router_match(&r, "Get", "/y");
  if mixed.code != 405 { ok = false; }
  return assert(ok, "method matching is byte-exact and case-sensitive");
}

fn t9() -> TestResult {
  var r = router_new();
  let a = router_add(&mut r, "GET", "/");
  var ok = int_ok_is(a, 0);
  let m = router_match(&r, "GET", "/");
  if m.code != 200 { ok = false; }
  if m.index != 0 { ok = false; }
  if m.params.len() != 0 { ok = false; }
  let noise = router_match(&r, "GET", "/x");
  if noise.code != 404 { ok = false; }
  let empty = router_match(&r, "GET", "");
  if empty.code != 200 { ok = false; }
  let allow = router_allowed_methods(&r, "/");
  if allow.len() != 1 { ok = false; }
  return assert(ok, "root: / is a zero-segment pattern (empty path matches it too)");
}

fn t10() -> TestResult {
  var r = router_new();
  let a = router_add(&mut r, "GET", "/a");
  var ok = int_ok_is(a, 0);
  let miss = router_match(&r, "GET", "/a/");
  if miss.code != 404 { ok = false; }
  let b = router_add(&mut r, "GET", "/a/");
  if !int_ok_is(b, 1) { ok = false; }
  let exact = router_match(&r, "GET", "/a/");
  if exact.code != 200 { ok = false; }
  if exact.index != 1 { ok = false; }
  let plain = router_match(&r, "GET", "/a");
  if plain.code != 200 { ok = false; }
  if plain.index != 0 { ok = false; }
  return assert(ok, "trailing slash is significant: /a and /a/ are distinct routes");
}

fn t11() -> TestResult {
  var r = router_new();
  let a = router_add(&mut r, "GET", "/api/v1/users/:id/books/:book");
  var ok = int_ok_is(a, 0);
  let m = router_match(&r, "GET", "/api/v1/users/7/books/42");
  if m.code != 200 { ok = false; }
  if m.index != 0 { ok = false; }
  if m.params.len() != 2 { ok = false; }
  let p0: RouteParam = m.params[0];
  let p1: RouteParam = m.params[1];
  if !streq(p0.name, "id") || !streq(p0.value, "7") { ok = false; }
  if !streq(p1.name, "book") || !streq(p1.value, "42") { ok = false; }
  let miss = router_match(&r, "GET", "/api/v1/users/7/books");
  if miss.code != 404 { ok = false; }
  return assert(ok, "multi-segment: five-segment pattern with two captures");
}

fn t12() -> TestResult {
  var r = router_new();
  var ok = int_err_is(router_add(&mut r, "", "/a"), "router: empty method");
  if !int_err_is(router_add(&mut r, "GET", ""), "router: pattern must start with '/'") { ok = false; }
  if !int_err_is(router_add(&mut r, "GET", "a/b"), "router: pattern must start with '/'") { ok = false; }
  if !int_err_is(router_add(&mut r, "GET", "/:"), "router: empty parameter name") { ok = false; }
  if !int_err_is(router_add(&mut r, "GET", "/a/:/b"), "router: empty parameter name") { ok = false; }
  if router_count(&r) != 0 { ok = false; }
  let good = router_add(&mut r, "GET", "/a/x:");
  if !int_ok_is(good, 0) { ok = false; }
  return assert(ok, "router_add validation: empty method/pattern, bad slash, empty param name");
}

fn t13() -> TestResult {
  var r = router_new();
  let a = router_add(&mut r, "GET", "/a");
  let b = router_add(&mut r, "POST", "/a");
  let c = router_add(&mut r, "DELETE", "/a/:id");
  var ok = int_ok_is(a, 0) && int_ok_is(b, 1) && int_ok_is(c, 2);
  if router_count(&r) != 3 { ok = false; }
  return assert(ok, "router_add returns consecutive indices 0, 1, 2");
}

fn t14() -> TestResult {
  var r = router_new();
  let a = router_add(&mut r, "GET", "/a");
  let b = router_add(&mut r, "POST", "/b/:id");
  var ok = int_ok_is(a, 0) && int_ok_is(b, 1);
  if !str_ok_is(router_method(&r, 0), "GET") { ok = false; }
  if !str_ok_is(router_method(&r, 1), "POST") { ok = false; }
  if !str_ok_is(router_pattern(&r, 0), "/a") { ok = false; }
  if !str_ok_is(router_pattern(&r, 1), "/b/:id") { ok = false; }
  if !str_err_is(router_method(&r, -1), "router: index out of range") { ok = false; }
  if !str_err_is(router_method(&r, 2), "router: index out of range") { ok = false; }
  if !str_err_is(router_pattern(&r, -1), "router: index out of range") { ok = false; }
  if !str_err_is(router_pattern(&r, 2), "router: index out of range") { ok = false; }
  if router_count(&r) != 2 { ok = false; }
  return assert(ok, "accessors: in-range Ok and out-of-range Err on both accessors");
}

fn t15() -> TestResult {
  var r = router_new();
  let a = router_add(&mut r, "GET", "/u/:id");
  let b = router_add(&mut r, "POST", "/u/:id");
  var ok = int_ok_is(a, 0) && int_ok_is(b, 1);
  let m = router_match(&r, "DELETE", "/u/7");
  if m.code != 405 { ok = false; }
  if m.index != -1 { ok = false; }
  if m.params.len() != 0 { ok = false; }
  let allow = router_allowed_methods(&r, "/u/7");
  var want = Vec[Str].new();
  want.push("GET");
  want.push("POST");
  if !str_list_is(allow, want) { ok = false; }
  return assert(ok, "405 on a param pattern reports no params but both methods");
}

fn t16() -> TestResult {
  var r = router_new();
  let a = router_add(&mut r, "GET", "/d");
  let b = router_add(&mut r, "GET", "/d");
  let c = router_add(&mut r, "POST", "/d");
  var ok = int_ok_is(a, 0) && int_ok_is(b, 1) && int_ok_is(c, 2);
  let allow = router_allowed_methods(&r, "/d");
  if allow.len() != 2 { ok = false; }
  var want = Vec[Str].new();
  want.push("GET");
  want.push("POST");
  if !str_list_is(allow, want) { ok = false; }
  return assert(ok, "allowed methods are deduplicated (GET, GET, POST -> GET, POST)");
}

fn t17() -> TestResult {
  var r = router_new();
  let a = router_add(&mut r, "POST", "/o");
  let b = router_add(&mut r, "GET", "/o");
  var ok = int_ok_is(a, 0) && int_ok_is(b, 1);
  let allow = router_allowed_methods(&r, "/o");
  var want = Vec[Str].new();
  want.push("POST");
  want.push("GET");
  if !str_list_is(allow, want) { ok = false; }
  return assert(ok, "allowed methods keep first-registration order");
}

fn t18() -> TestResult {
  var r = router_new();
  let a = router_add(&mut r, "GET", "/known");
  var ok = int_ok_is(a, 0);
  let allow = router_allowed_methods(&r, "/unknown");
  if allow.len() != 0 { ok = false; }
  let allow2 = router_allowed_methods(&r, "/known/more");
  if allow2.len() != 0 { ok = false; }
  return assert(ok, "allowed methods are empty when no shape matches");
}

fn t19() -> TestResult {
  var r = router_new();
  let a = router_add(&mut r, "POST", "/m");
  let b = router_add(&mut r, "GET", "/m");
  var ok = int_ok_is(a, 0) && int_ok_is(b, 1);
  let g = router_match(&r, "GET", "/m");
  if g.code != 200 { ok = false; }
  if g.index != 1 { ok = false; }
  let del = router_match(&r, "DELETE", "/m");
  if del.code != 405 { ok = false; }
  let post = router_match(&r, "POST", "/m");
  if post.code != 200 { ok = false; }
  if post.index != 0 { ok = false; }
  return assert(ok, "a later route's method match wins; 405 only with no method match");
}

fn t20() -> TestResult {
  var r = router_new();
  let a = router_add(&mut r, "GET", "/a//b");
  var ok = int_ok_is(a, 0);
  let m = router_match(&r, "GET", "/a//b");
  if m.code != 200 { ok = false; }
  if m.index != 0 { ok = false; }
  if m.params.len() != 0 { ok = false; }
  let miss = router_match(&r, "GET", "/a/x/b");
  if miss.code != 404 { ok = false; }
  let shorter = router_match(&r, "GET", "/a/b");
  if shorter.code != 404 { ok = false; }
  return assert(ok, "literal empty middle segment: /a//b matches itself only");
}

fn t21() -> TestResult {
  var r = router_new();
  let a = router_add(&mut r, "GET", "/f/:name");
  var ok = int_ok_is(a, 0);
  let m = router_match(&r, "GET", "/f/a%2Fb");
  if m.code != 200 { ok = false; }
  if m.params.len() != 1 { ok = false; }
  let p0: RouteParam = m.params[0];
  if !streq(p0.value, "a%2Fb") { ok = false; }
  let q = router_match(&r, "GET", "/f/x?y=1");
  if q.code != 200 { ok = false; }
  if q.params.len() != 1 { ok = false; }
  let p1: RouteParam = q.params[0];
  if !streq(p1.value, "x?y=1") { ok = false; }
  return assert(ok, "captures are raw: no percent-decoding, query not stripped");
}

fn t22() -> TestResult {
  var r = router_new();
  let a = router_add(&mut r, "GET", "/");
  let b = router_add(&mut r, "GET", "/users");
  let c = router_add(&mut r, "GET", "/users/:id");
  let d = router_add(&mut r, "POST", "/users");
  var ok = int_ok_is(a, 0) && int_ok_is(b, 1) && int_ok_is(c, 2) && int_ok_is(d, 3);
  let m1 = router_match(&r, "GET", "/users");
  if m1.code != 200 { ok = false; }
  if m1.index != 1 { ok = false; }
  if m1.params.len() != 0 { ok = false; }
  let m2 = router_match(&r, "GET", "/users/7");
  if m2.code != 200 { ok = false; }
  if m2.index != 2 { ok = false; }
  if m2.params.len() != 1 { ok = false; }
  let id: RouteParam = m2.params[0];
  if !streq(id.name, "id") { ok = false; }
  if !streq(id.value, "7") { ok = false; }
  let m3 = router_match(&r, "DELETE", "/users");
  if m3.code != 405 { ok = false; }
  let allow = router_allowed_methods(&r, "/users");
  var want = Vec[Str].new();
  want.push("GET");
  want.push("POST");
  if !str_list_is(allow, want) { ok = false; }
  let m4 = router_match(&r, "GET", "/missing");
  if m4.code != 404 { ok = false; }
  let m5 = router_match(&r, "GET", "/users/7");
  if m5.code != m2.code { ok = false; }
  if m5.index != m2.index { ok = false; }
  if m5.params.len() != m2.params.len() { ok = false; }
  if router_count(&r) != 4 { ok = false; }
  return assert(ok, "composite table: 200/404/405, Allow list, deterministic repeats");
}

fn main() -> Int {
  io.println("=== xiom.router conformance tests ===");
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
    io.println("xiom.router: all tests passed");
  } else {
    io.println("xiom.router: tests failed");
  }
  return failed;
}
