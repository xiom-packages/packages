// XIOM -- xiom.http.middleware conformance tests (22 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Coverage map: see SPEC.md section 7. Every check is a named
// assert(cond, "name") call and main returns the failure count (0 = green).
// All Str equality goes through compare.str_compare via the local streq
// helper (`==` on Str values is never used). Every Vec element read is bound
// to a typed local first.

module middleware_tests

use xiom.io; use xiom.test; use xiom.http.middleware;
use xiom.string.compare;

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
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
  let r = middleware_request_id_new();
  var ok = r.is_ok;
  if ok {
    let id: Str = r.value;
    if id.len() != 32 { ok = false; }
    if !middleware_request_id_valid(id) { ok = false; }
  }
  return assert(ok, "request id new: Ok with 32 lowercase hex chars");
}

fn t2() -> TestResult {
  let a = middleware_request_id_new();
  let b = middleware_request_id_new();
  var ok = a.is_ok && b.is_ok;
  if ok {
    let x: Str = a.value;
    let y: Str = b.value;
    if !middleware_request_id_valid(x) { ok = false; }
    if !middleware_request_id_valid(y) { ok = false; }
    if streq(x, y) { ok = false; }
  }
  return assert(ok, "request id new: two calls differ and both are valid");
}

fn t3() -> TestResult {
  var ok = middleware_request_id_valid("0123456789abcdef0123456789abcdef");
  if !middleware_request_id_valid("00000000000000000000000000000000") { ok = false; }
  if !middleware_request_id_valid("ffffffffffffffffffffffffffffffff") { ok = false; }
  if !middleware_request_id_valid("deadbeefcafef00ddeadbeefcafef00d") { ok = false; }
  return assert(ok, "request id valid: accepts 32 lowercase hex chars");
}

fn t4() -> TestResult {
  var ok = true;
  if middleware_request_id_valid("") { ok = false; }
  if middleware_request_id_valid("0123456789abcdef0123456789abcde") { ok = false; }
  if middleware_request_id_valid("0123456789abcdef0123456789abcdef0") { ok = false; }
  if middleware_request_id_valid("0123456789ABCDEF0123456789abcdef") { ok = false; }
  if middleware_request_id_valid("0123456789abcdef0123456789abcdeg") { ok = false; }
  if middleware_request_id_valid("0123456789abcdef 123456789abcdef") { ok = false; }
  return assert(ok, "request id valid: rejects empty, wrong length, uppercase, non-hex");
}

fn t5() -> TestResult {
  let line = middleware_access_log_line("deadbeefcafef00ddeadbeefcafef00d", "GET", "/users", 200, 12, 345);
  return assert(streq(line, "request_id=deadbeefcafef00ddeadbeefcafef00d method=GET path=/users status=200 duration_ms=12 bytes=345"), "access log: exact line format");
}

fn t6() -> TestResult {
  let zero = middleware_access_log_line("00000000000000000000000000000000", "POST", "/", 204, 0, 0);
  var ok = streq(zero, "request_id=00000000000000000000000000000000 method=POST path=/ status=204 duration_ms=0 bytes=0");
  let big = middleware_access_log_line("deadbeefcafef00ddeadbeefcafef00d", "DELETE", "/api/v1/items/42", 500, 1234567890, 1048576);
  if !streq(big, "request_id=deadbeefcafef00ddeadbeefcafef00d method=DELETE path=/api/v1/items/42 status=500 duration_ms=1234567890 bytes=1048576") { ok = false; }
  return assert(ok, "access log: zero and large integer fields render exactly");
}

fn t7() -> TestResult {
  let h = middleware_cors_headers("https://app.example", "GET, POST", "Content-Type, Authorization", 600);
  var want = Vec[Str].new();
  want.push("Access-Control-Allow-Origin: https://app.example");
  want.push("Access-Control-Allow-Methods: GET, POST");
  want.push("Access-Control-Allow-Headers: Content-Type, Authorization");
  want.push("Access-Control-Max-Age: 600");
  return assert(str_list_is(h, want), "cors: all four headers, exact order and text");
}

fn t8() -> TestResult {
  let h = middleware_cors_headers("*", "", "", 0);
  var want = Vec[Str].new();
  want.push("Access-Control-Allow-Origin: *");
  return assert(str_list_is(h, want), "cors: only-origin output and wildcard passed through");
}

fn t9() -> TestResult {
  let h = middleware_cors_headers("", "", "", 0);
  let h2 = middleware_cors_headers("", "", "", -5);
  var ok = h.len() == 0;
  if h2.len() != 0 { ok = false; }
  return assert(ok, "cors: all empty yields an empty vector (negative max-age too)");
}

fn t10() -> TestResult {
  let one = middleware_cors_headers("https://x", "GET", "", 1);
  var want1 = Vec[Str].new();
  want1.push("Access-Control-Allow-Origin: https://x");
  want1.push("Access-Control-Allow-Methods: GET");
  want1.push("Access-Control-Max-Age: 1");
  var ok = str_list_is(one, want1);
  let zero = middleware_cors_headers("https://x", "GET", "", 0);
  var want0 = Vec[Str].new();
  want0.push("Access-Control-Allow-Origin: https://x");
  want0.push("Access-Control-Allow-Methods: GET");
  if !str_list_is(zero, want0) { ok = false; }
  let neg = middleware_cors_headers("https://x", "GET", "", -1);
  if !str_list_is(neg, want0) { ok = false; }
  return assert(ok, "cors: max-age <= 0 is skipped, max-age 1 is present and last");
}

fn t11() -> TestResult {
  let h = middleware_cors_headers("", "PUT", "X-Token", 300);
  var want = Vec[Str].new();
  want.push("Access-Control-Allow-Methods: PUT");
  want.push("Access-Control-Allow-Headers: X-Token");
  want.push("Access-Control-Max-Age: 300");
  return assert(str_list_is(h, want), "cors: empty origin skipped, later headers keep order");
}

fn t12() -> TestResult {
  let a = middleware_csrf_token_new();
  let b = middleware_csrf_token_new();
  var ok = a.is_ok && b.is_ok;
  if ok {
    let x: Str = a.value;
    let y: Str = b.value;
    if x.len() != 32 { ok = false; }
    if !middleware_request_id_valid(x) { ok = false; }
    if !middleware_request_id_valid(y) { ok = false; }
    if streq(x, y) { ok = false; }
  }
  return assert(ok, "csrf token new: Ok, 32 lowercase hex chars, two calls differ");
}

fn t13() -> TestResult {
  let r = middleware_csrf_token_new();
  var ok = r.is_ok;
  if ok {
    let tok: Str = r.value;
    if !middleware_csrf_valid(tok, tok) { ok = false; }
  }
  return assert(ok, "csrf valid: a fresh token validates against itself");
}

fn t14() -> TestResult {
  var ok = !middleware_csrf_valid("deadbeefcafef00ddeadbeefcafef00d", "deadbeefcafef00ddeadbeefcafef00e");
  if !middleware_csrf_valid("0123456789abcdef0123456789abcdef", "0123456789abcdef0123456789abcdef") { ok = false; }
  if middleware_csrf_valid("0123456789abcdef0123456789abcdef", "1123456789abcdef0123456789abcdef") { ok = false; }
  return assert(ok, "csrf valid: same length, one byte changed is false");
}

fn t15() -> TestResult {
  let r = middleware_csrf_token_new();
  var ok = r.is_ok;
  if ok {
    let tok: Str = r.value;
    if middleware_csrf_valid("", "") { ok = false; }
    if middleware_csrf_valid(tok, "") { ok = false; }
    if middleware_csrf_valid("", tok) { ok = false; }
  }
  return assert(ok, "csrf valid: empty token or empty expected is false");
}

fn t16() -> TestResult {
  var ok = true;
  if middleware_csrf_valid("0123456789abcdef0123456789abcde", "0123456789abcdef0123456789abcdef") { ok = false; }
  if middleware_csrf_valid("0123456789abcdef0123456789abcdef", "0123456789abcdef0123456789abcde") { ok = false; }
  if middleware_csrf_valid("a", "aa") { ok = false; }
  if middleware_csrf_valid("aa", "a") { ok = false; }
  return assert(ok, "csrf valid: different lengths are false");
}

fn t17() -> TestResult {
  let body = middleware_error_body(404, "not found");
  return assert(streq(body, "{\"error\":{\"status\":404,\"message\":\"not found\"}}"), "error body: exact simple JSON");
}

fn t18() -> TestResult {
  let msg = "a\"b\\c";
  let body = middleware_error_body(400, msg);
  return assert(streq(body, "{\"error\":{\"status\":400,\"message\":\"a\\\"b\\\\c\"}}"), "error body: quotes and backslashes escaped");
}

fn t19() -> TestResult {
  let msg = "a\nb\rc\td";
  let body = middleware_error_body(422, msg);
  return assert(streq(body, "{\"error\":{\"status\":422,\"message\":\"a\\nb\\rc\\td\"}}"), "error body: LF, CR and TAB escaped");
}

fn t20() -> TestResult {
  let a = middleware_error_content_type();
  let b = middleware_error_content_type();
  var ok = streq(a, "application/json");
  if !streq(a, b) { ok = false; }
  return assert(ok, "error content type: exact application/json");
}

fn t21() -> TestResult {
  let l1 = middleware_access_log_line("deadbeefcafef00ddeadbeefcafef00d", "GET", "/x", 200, 3, 9);
  let l2 = middleware_access_log_line("deadbeefcafef00ddeadbeefcafef00d", "GET", "/x", 200, 3, 9);
  var ok = streq(l1, l2);
  let c1 = middleware_cors_headers("*", "GET", "X", 60);
  let c2 = middleware_cors_headers("*", "GET", "X", 60);
  if !str_list_is(c1, c2) { ok = false; }
  let e1 = middleware_error_body(500, "boom");
  let e2 = middleware_error_body(500, "boom");
  if !streq(e1, e2) { ok = false; }
  let r = middleware_csrf_token_new();
  if r.is_ok {
    let tok: Str = r.value;
    let v1 = middleware_csrf_valid(tok, tok);
    let v2 = middleware_csrf_valid(tok, tok);
    if !v1 || !v2 { ok = false; }
  }
  return assert(ok, "deterministic repeats: identical inputs give identical outputs");
}

fn t22() -> TestResult {
  var ok = middleware_csrf_valid("abc", "abc");
  if middleware_csrf_valid("abc", "abd") { ok = false; }
  if middleware_csrf_valid("token", "tokenx") { ok = false; }
  if !middleware_csrf_valid("x", "x") { ok = false; }
  return assert(ok, "csrf valid: arbitrary non-empty equal-length bytes compare directly");
}

fn main() -> Int {
  io.println("=== xiom.http.middleware conformance tests ===");
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
    io.println("xiom.http.middleware: all tests passed");
  } else {
    io.println("xiom.http.middleware: tests failed");
  }
  return failed;
}
