// XIOM -- xiom.jwt conformance tests (24 checks)
// Port task: prove the pure-XIOM xiom.jwt module against its documented
// decode-only contract (no signature verification, no JSON parsing).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// All Str equality goes through str_compare: BUG 17 lowers `==` on Str values
// read from Vec[Str] elements to a pointer comparison, so every check below
// is routed through streq instead of `==`. Test tokens are fixed base64url
// literals computed independently of the module under test, so the suite
// would catch a broken local base64url helper.

module jwt_tests
use xiom.io; use xiom.test; use xiom.jwt;
use xiom.string; use xiom.string.compare;

// Header/payload/signature of the jwt.io HS256 example.
const H_HS256: Str = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9";
const P_JWTIO: Str = "eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ";
const S_JWTIO: Str = "SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c";

// Decoded text of the two segments above.
const H_HS256_JSON: Str = "{\"alg\":\"HS256\",\"typ\":\"JWT\"}";
const P_JWTIO_JSON: Str = "{\"sub\":\"1234567890\",\"name\":\"John Doe\",\"iat\":1516239022}";

// Extra headers/payloads used by the scanner and time checks.
const H_NOALG: Str = "eyJ0eXAiOiJKV1QifQ";                                  // {"typ":"JWT"}
const H_NONE: Str = "eyJhbGciOiJub25lIn0";                                  // {"alg":"none"}
const P_EXP1000: Str = "eyJleHAiOjEwMDB9";                                  // {"exp":1000}
const P_EXP_NEG: Str = "eyJleHAiOi01fQ";                                    // {"exp":-5}
const P_NBF500: Str = "eyJuYmYiOjUwMH0";                                    // {"nbf":500}
const P_MIX: Str = "eyJzdWIiOiJhYmMiLCJleHAiOjIwMDAwMDAwMDAsIm5iZiI6MTUwMDAwMDAwMCwibGV2ZWwiOi0zLCJpYXQiOjE1MTYyMzkwMjJ9";
const P_UNI: Str = "eyJuYW1lIjoiTcO8bmNoZW4g4pyTIn0";                       // {"name":"München ✓"}
const P_ESC: Str = "eyJhIjoieFwieSJ9";                                      // {"a":"x\"y"}
const P_STRINT: Str = "eyJleHAiOiIxMDAifQ";                                 // {"exp":"100"}
const P_FLOAT: Str = "eyJleHAiOjEyLjV9";                                    // {"exp":12.5}
const P_JUNK: Str = "eyJleHAiOjEyYWJjfQ";                                   // {"exp":12abc}
const P_BARE: Str = "eyJleHAiOi19";                                         // {"exp":-}
const P_MAX: Str = "eyJleHAiOjkyMjMzNzIwMzY4NTQ3NzU4MDd9";                  // {"exp":9223372036854775807}
const P_OVER: Str = "eyJleHAiOjk5OTk5OTk5OTk5OTk5OTk5OTk5fQ";              // {"exp":99999999999999999999}
const P_A1_PAD: Str = "eyJhIjoxfQ==";                                       // {"a":1} with '=' padding

// Join three raw segments into a compact token.
fn tok(h: Str, p: Str, s: Str) -> Str {
  return h + "." + p + "." + s;
}

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// True when r is Ok(text) with text equal to `want`.
fn str_ok_is(r: Result[Str, Str], want: Str) -> Bool {
  if !r.is_ok { return false; }
  return streq(r.value, want);
}

// True when r is an Err whose message starts with "jwt: ".
fn str_err(r: Result[Str, Str]) -> Bool {
  if r.is_ok { return false; }
  let m = r.error;
  if m.len() < 5 { return false; }
  return streq(string.str_slice(m, 0, 5), "jwt: ");
}

// True when r is Ok(v) with v equal to `want`.
fn int_ok_is(r: Result[Int, Str], want: Int) -> Bool {
  if !r.is_ok { return false; }
  return r.value == want;
}

// True when r is an Err whose message starts with "jwt: ".
fn int_err(r: Result[Int, Str]) -> Bool {
  if r.is_ok { return false; }
  let m = r.error;
  if m.len() < 5 { return false; }
  return streq(string.str_slice(m, 0, 5), "jwt: ");
}

// True when r is Ok(v) with v equal to `want`.
fn bool_ok_is(r: Result[Bool, Str], want: Bool) -> Bool {
  if !r.is_ok { return false; }
  return r.value == want;
}

// True when r is an Err whose message starts with "jwt: ".
fn bool_err(r: Result[Bool, Str]) -> Bool {
  if r.is_ok { return false; }
  let m = r.error;
  if m.len() < 5 { return false; }
  return streq(string.str_slice(m, 0, 5), "jwt: ");
}

fn t1() -> TestResult {
  let token = tok(H_HS256, P_JWTIO, S_JWTIO);
  return assert(jwt_is_shaped(token), "shaped: classic 3-segment JWT is true");
}

fn t2() -> TestResult {
  var ok = !jwt_is_shaped(H_HS256 + "." + P_JWTIO);
  if jwt_is_shaped("a.b.c.d.e") { ok = false; }
  if jwt_is_shaped(H_HS256 + "." + P_JWTIO + ".") { ok = false; }
  if jwt_is_shaped("") { ok = false; }
  if jwt_is_shaped("a+b.c.d") { ok = false; }
  return assert(ok, "shaped: 2/5 segments, empty segment, '+' are false");
}

fn t3() -> TestResult {
  let token = tok(H_HS256, P_JWTIO, S_JWTIO);
  var ok = jwt_segment_count(token) == 3;
  if jwt_segment_count("a.b.c.d.e") != 5 { ok = false; }
  if jwt_segment_count("abc") != 1 { ok = false; }
  if jwt_segment_count("") != 1 { ok = false; }
  if jwt_segment_count("a.b.c.d") != 4 { ok = false; }
  return assert(ok, "segment_count: 3 for JWS, 5 for JWE-style, 1 without dots");
}

fn t4() -> TestResult {
  let token = tok(H_HS256, P_JWTIO, S_JWTIO);
  var ok = str_ok_is(jwt_decode_segment(token, 0), H_HS256_JSON);
  if !str_ok_is(jwt_decode_segment(token, 1), P_JWTIO_JSON) { ok = false; }
  return assert(ok, "decode_segment: known base64url header/payload text");
}

fn t5() -> TestResult {
  let token = tok(H_HS256, P_JWTIO, S_JWTIO);
  var ok = str_err(jwt_decode_segment(token, 3));
  if !str_err(jwt_decode_segment(token, -1)) { ok = false; }
  if !str_err(jwt_decode_segment("..", 0)) { ok = false; }
  return assert(ok, "decode_segment: out-of-range and empty segment are Err");
}

fn t6() -> TestResult {
  var ok = str_err(jwt_decode_segment("a+b.c.d", 0));
  if !str_err(jwt_decode_segment("YQ=.c.d", 0)) { ok = false; }
  if !str_err(jwt_decode_segment("Y===.c.d", 0)) { ok = false; }
  if !str_err(jwt_decode_segment("aaaaa.c.d", 0)) { ok = false; }
  return assert(ok, "decode_segment: bad char, bad padding, impossible length are Err");
}

fn t7() -> TestResult {
  let token = tok(H_HS256, "_w", S_JWTIO);
  var ok = str_err(jwt_decode_segment(token, 1));
  if !str_err(jwt_payload_text(token)) { ok = false; }
  return assert(ok, "decode_segment: non-UTF-8 bytes are Err");
}

fn t8() -> TestResult {
  let token = tok(H_HS256, P_JWTIO, S_JWTIO);
  var ok = str_ok_is(jwt_header_text(token), H_HS256_JSON);
  if !str_ok_is(jwt_payload_text(token), P_JWTIO_JSON) { ok = false; }
  if !str_ok_is(jwt_signature_text(token), S_JWTIO) { ok = false; }
  return assert(ok, "header/payload decode; signature stays raw");
}

fn t9() -> TestResult {
  let two = H_HS256 + "." + P_JWTIO;
  var ok = str_err(jwt_header_text(two));
  if !str_err(jwt_payload_text(two)) { ok = false; }
  if !str_err(jwt_signature_text(two)) { ok = false; }
  if !str_err(jwt_header_text("")) { ok = false; }
  return assert(ok, "text accessors: non-3-segment tokens are Err");
}

fn t10() -> TestResult {
  let padded = tok(H_NONE, P_A1_PAD, "x");
  let unpadded = tok(H_NONE, "eyJhIjoxfQ", "x");
  var ok = str_ok_is(jwt_payload_text(padded), "{\"a\":1}");
  if !str_ok_is(jwt_payload_text(unpadded), "{\"a\":1}") { ok = false; }
  return assert(ok, "payload decode accepts optional '=' padding");
}

fn t11() -> TestResult {
  let token = tok(H_HS256, P_JWTIO, S_JWTIO);
  var ok = str_ok_is(jwt_alg(token), "HS256");
  if !str_ok_is(jwt_alg(tok(H_NONE, P_JWTIO, S_JWTIO)), "none") { ok = false; }
  return assert(ok, "alg: extracts the quoted header value");
}

fn t12() -> TestResult {
  var ok = str_err(jwt_alg(tok(H_NOALG, P_JWTIO, S_JWTIO)));
  if !str_err(jwt_alg("only.two")) { ok = false; }
  return assert(ok, "alg: missing key and malformed token are Err");
}

fn t13() -> TestResult {
  let token = tok(H_HS256, P_JWTIO, S_JWTIO);
  var ok = str_ok_is(jwt_claim_str(token, "sub"), "1234567890");
  if !str_ok_is(jwt_claim_str(token, "name"), "John Doe") { ok = false; }
  if !str_err(jwt_claim_str(token, "missing")) { ok = false; }
  return assert(ok, "claim_str: top-level string claim and missing key");
}

fn t14() -> TestResult {
  let token = tok(H_HS256, P_MIX, S_JWTIO);
  var ok = int_ok_is(jwt_claim_int(token, "iat"), 1516239022);
  if !int_ok_is(jwt_claim_int(token, "level"), -3) { ok = false; }
  if !int_ok_is(jwt_claim_int(token, "exp"), 2000000000) { ok = false; }
  return assert(ok, "claim_int: positive and negative top-level integers");
}

fn t15() -> TestResult {
  var ok = int_err(jwt_claim_int(tok(H_HS256, P_STRINT, S_JWTIO), "exp"));
  if !int_err(jwt_claim_int(tok(H_HS256, P_FLOAT, S_JWTIO), "exp")) { ok = false; }
  if !int_err(jwt_claim_int(tok(H_HS256, P_JUNK, S_JWTIO), "exp")) { ok = false; }
  if !int_err(jwt_claim_int(tok(H_HS256, P_BARE, S_JWTIO), "exp")) { ok = false; }
  if !int_err(jwt_claim_int(tok(H_HS256, P_MIX, S_JWTIO), "nope")) { ok = false; }
  return assert(ok, "claim_int: string/float/junk/bare/missing are Err");
}

fn t16() -> TestResult {
  var ok = int_ok_is(jwt_claim_int(tok(H_HS256, P_MAX, S_JWTIO), "exp"), 9223372036854775807);
  if !int_err(jwt_claim_int(tok(H_HS256, P_OVER, S_JWTIO), "exp")) { ok = false; }
  return assert(ok, "claim_int: 64-bit boundary accepted, overflow rejected");
}

fn t17() -> TestResult {
  let token = tok(H_HS256, P_EXP1000, S_JWTIO);
  var ok = bool_ok_is(jwt_expired(token, 999), false);
  if !bool_ok_is(jwt_expired(token, 1000), true) { ok = false; }
  if !bool_ok_is(jwt_expired(token, 1001), true) { ok = false; }
  return assert(ok, "expired: exp <= now is expired (exp == now boundary)");
}

fn t18() -> TestResult {
  let neg = tok(H_HS256, P_EXP_NEG, S_JWTIO);
  var ok = bool_ok_is(jwt_expired(neg, 0), true);
  if !bool_ok_is(jwt_expired(neg, -6), false) { ok = false; }
  if !bool_err(jwt_expired(tok(H_HS256, P_NBF500, S_JWTIO), 1000)) { ok = false; }
  if !bool_err(jwt_expired(tok(H_HS256, P_FLOAT, S_JWTIO), 1000)) { ok = false; }
  return assert(ok, "expired: negative exp, missing and malformed exp are handled");
}

fn t19() -> TestResult {
  let token = tok(H_HS256, P_NBF500, S_JWTIO);
  var ok = bool_ok_is(jwt_not_before_ok(token, 499), false);
  if !bool_ok_is(jwt_not_before_ok(token, 500), true) { ok = false; }
  if !bool_ok_is(jwt_not_before_ok(token, 501), true) { ok = false; }
  if !bool_err(jwt_not_before_ok(tok(H_HS256, P_EXP1000, S_JWTIO), 1000)) { ok = false; }
  return assert(ok, "nbf: true when now >= nbf; missing nbf is Err");
}

fn t20() -> TestResult {
  var ok = str_err(jwt_header_text(""));
  if !str_err(jwt_payload_text("a.b")) { ok = false; }
  if !str_err(jwt_header_text("a+b.c.d")) { ok = false; }
  if !str_err(jwt_payload_text("..")) { ok = false; }
  return assert(ok, "malformed tokens: empty, 2-segment, bad chars, empty segments");
}

fn t21() -> TestResult {
  let jwe = "a.b.c.d.e";
  var ok = !jwt_is_shaped(jwe);
  if jwt_segment_count(jwe) != 5 { ok = false; }
  if !str_err(jwt_header_text(jwe)) { ok = false; }
  return assert(ok, "JWE-style 5 segments: count 5, not shaped, text is Err");
}

fn t22() -> TestResult {
  let token = tok(H_HS256, P_UNI, S_JWTIO);
  var ok = str_ok_is(jwt_claim_str(token, "name"), "München ✓");
  return assert(ok, "unicode: claim_str returns decoded UTF-8 text");
}

fn t23() -> TestResult {
  let token = tok(H_HS256, P_ESC, S_JWTIO);
  var ok = str_ok_is(jwt_claim_str(token, "a"), "x\\");
  return assert(ok, "scanner: escapes are not decoded (documented subset)");
}

fn t24() -> TestResult {
  let token = tok(H_HS256, P_JWTIO, S_JWTIO);
  var ok = str_ok_is(jwt_signature_text(token), S_JWTIO);
  if !str_ok_is(jwt_signature_text(H_HS256 + "." + P_JWTIO + "."), "") { ok = false; }
  return assert(ok, "signature_text: raw segment, empty signature allowed");
}

fn main() -> Int {
  io.println("=== xiom.jwt conformance tests ===");
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
    io.println("xiom.jwt: all tests passed");
  } else {
    io.println("xiom.jwt: tests failed");
  }
  return failed;
}
