// XIOM -- xiom.secret conformance tests (20 checks)
// Port task: prove the pure-XIOM xiom.secret module against its documented
// redaction rules.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Covers the documented API: Luhn (valid, invalid, non-digit and empty
// input), email masking and detection, card-like runs (spaces, dashes,
// contiguous, too short, too long, doubled separators), PEM private-key
// blocks (multiline, missing END, mismatched END, non-private label), Bearer
// credentials, AWS AKIA ids, long vs short token runs, one-pass multi-secret
// redaction, verbatim placeholders, empty/clean text and sensitive key names.
//
// All Str equality goes through str_compare: BUG 17 lowers `==` on Str values
// read from Vec[Str] elements to a pointer comparison, so every comparison
// below is routed through streq.

module secret_tests
use xiom.io; use xiom.test; use xiom.secret;
use xiom.string;
use xiom.string.compare;

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn t1() -> TestResult {
  var ok = secret_luhn_ok("79927398713");
  if !secret_luhn_ok("4539578763621486") { ok = false; }
  if !secret_luhn_ok("4111111111111111") { ok = false; }
  if !secret_luhn_ok("4222222222222") { ok = false; }
  return assert(ok, "luhn: known-valid checksums pass");
}

fn t2() -> TestResult {
  var ok = !secret_luhn_ok("79927398710");
  if secret_luhn_ok("4111111111111112") { ok = false; }
  if secret_luhn_ok("4539578763621487") { ok = false; }
  if secret_luhn_ok("4111a") { ok = false; }
  if secret_luhn_ok("4111 1111 1111 1111") { ok = false; }
  if secret_luhn_ok("") { ok = false; }
  return assert(ok, "luhn: bad checksum, non-digit and empty input fail");
}

fn t3() -> TestResult {
  var ok = streq(secret_mask_email("alice@example.com"), "a***@example.com");
  if !streq(secret_mask_email("a@b"), "a***@b") { ok = false; }
  if !streq(secret_mask_email("a.b@c.d"), "a***@c.d") { ok = false; }
  return assert(ok, "mask_email: first byte kept, rest of local part becomes ***");
}

fn t4() -> TestResult {
  var ok = streq(secret_mask_email("not an email"), "not an email");
  if !streq(secret_mask_email("@b"), "@b") { ok = false; }
  if !streq(secret_mask_email("a@"), "a@") { ok = false; }
  if !streq(secret_mask_email("a@b."), "a@b.") { ok = false; }
  if !streq(secret_mask_email("a..b@c.d"), "a..b@c.d") { ok = false; }
  if !streq(secret_mask_email("contact a@b now"), "contact a@b now") { ok = false; }
  if !streq(secret_mask_email(""), "") { ok = false; }
  return assert(ok, "mask_email: non-emails and embedded addresses are unchanged");
}

fn t5() -> TestResult {
  var ok = secret_contains_email("contact alice@example.com now");
  if !secret_contains_email("x a@b y") { ok = false; }
  if !secret_contains_email("first.last+tag@sub.example.co") { ok = false; }
  return assert(ok, "contains_email: plain, short and tagged addresses found");
}

fn t6() -> TestResult {
  var ok = !secret_contains_email("plain text");
  if secret_contains_email("@nope") { ok = false; }
  if secret_contains_email("a@") { ok = false; }
  if secret_contains_email("no-at-sign.example.com") { ok = false; }
  if secret_contains_email("a@-b") { ok = false; }
  if secret_contains_email("user@-host-") { ok = false; }
  return assert(ok, "contains_email: missing parts and bad domain labels are not emails");
}

fn t7() -> TestResult {
  var ok = secret_contains_card("pay 4539 5787 6362 1486 now");
  if !secret_contains_card("4539578763621486") { ok = false; }
  if !secret_contains_card("6222222222222222222") { ok = false; }
  return assert(ok, "contains_card: space-separated, 16-digit and 19-digit runs pass Luhn");
}

fn t8() -> TestResult {
  var ok = secret_contains_card("4539-5787-6362-1486");
  if !secret_contains_card("4222222222222") { ok = false; }
  if !secret_contains_card("4222 2222 2222 2") { ok = false; }
  return assert(ok, "contains_card: dash separators and a 13-digit number pass");
}

fn t9() -> TestResult {
  var ok = !secret_contains_card("4539 5787 6362 1487");
  if secret_contains_card("453957876362") { ok = false; }
  if secret_contains_card("12345678901234567890") { ok = false; }
  if secret_contains_card("4539  5787  6362  1486") { ok = false; }
  if secret_contains_card("") { ok = false; }
  return assert(ok, "contains_card: bad checksum, 12/20 digits and doubled separators fail");
}

fn t10() -> TestResult {
  let card = secret_redact("card 4222 2222 2222 2 end", "[C]");
  var ok = streq(card, "card [C] end");
  if !streq(secret_redact("id 422222222222", "[C]"), "id 422222222222") { ok = false; }
  return assert(ok, "redact: card-like run replaced whole, 12-digit id kept");
}

fn t11() -> TestResult {
  let pem = "pre\n-----BEGIN PRIVATE KEY-----\nMIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQ\n-----END PRIVATE KEY-----\npost";
  let got = secret_redact(pem, "[K]");
  var ok = streq(got, "pre\n[K]\npost");
  if string.str_contains(got, "MIIEvQ") { ok = false; }
  if string.str_contains(got, "BEGIN") { ok = false; }
  return assert(ok, "redact: multiline PEM private-key block replaced whole");
}

fn t12() -> TestResult {
  let missing = secret_redact("-----BEGIN PRIVATE KEY-----\nMIIEvQ\n", "[K]");
  var ok = streq(missing, "-----BEGIN PRIVATE KEY-----\nMIIEvQ\n");
  let mismatched = secret_redact("-----BEGIN PRIVATE KEY-----\nQUJD\n-----END RSA PRIVATE KEY-----\n", "[K]");
  if !streq(mismatched, "-----BEGIN PRIVATE KEY-----\nQUJD\n-----END RSA PRIVATE KEY-----\n") { ok = false; }
  return assert(ok, "redact: PEM without a matching END line is unchanged");
}

fn t13() -> TestResult {
  let rsa = secret_redact("-----BEGIN RSA PRIVATE KEY-----\nQUJD\n-----END RSA PRIVATE KEY-----", "[K]");
  var ok = streq(rsa, "[K]");
  let cert = secret_redact("-----BEGIN CERTIFICATE-----\nQUJD\n-----END CERTIFICATE-----", "[K]");
  if !streq(cert, "-----BEGIN CERTIFICATE-----\nQUJD\n-----END CERTIFICATE-----") { ok = false; }
  return assert(ok, "redact: RSA label is a private key, CERTIFICATE is not");
}

fn t14() -> TestResult {
  let a = secret_redact("Authorization: Bearer abc123.def", "[B]");
  var ok = streq(a, "Authorization: [B]");
  if !streq(secret_redact("Bearer", "[B]"), "Bearer") { ok = false; }
  if !streq(secret_redact("bearer abc", "[B]"), "bearer abc") { ok = false; }
  if !streq(secret_redact("xBearer abc", "[B]"), "xBearer abc") { ok = false; }
  return assert(ok, "redact: Bearer credential replaced, bare or embedded keyword kept");
}

fn t15() -> TestResult {
  let a = secret_redact("aws AKIAIOSFODNN7EXAMPLE;", "[A]");
  var ok = streq(a, "aws [A];");
  let short = "AKIAIOSFODNN7EXAMPL";
  if !streq(secret_redact(short, "[A]"), short) { ok = false; }
  let glued = "xAKIAIOSFODNN7EXAMPLE";
  if !streq(secret_redact(glued, "[A]"), glued) { ok = false; }
  return assert(ok, "redact: AKIA id replaced, 19-byte or glued ids kept");
}

fn t16() -> TestResult {
  let long32 = "0123456789abcdef0123456789abcdef";
  var ok = streq(secret_redact("t " + long32 + " e", "[T]"), "t [T] e");
  let short31 = "0123456789abcdef0123456789abcde";
  if !streq(secret_redact(short31, "[T]"), short31) { ok = false; }
  let b64 = "dGhpcyBpcyBhIHZlcnkgbG9uZyB0b2tlbiB2YWx1ZQ==";
  if !streq(secret_redact("tok " + b64 + " end", "[T]"), "tok [T] end") { ok = false; }
  return assert(ok, "redact: 32+ byte token runs replaced, 31-byte run kept");
}

fn t17() -> TestResult {
  let got = secret_redact("card 4539 5787 6362 1486 mail a@b.com", "[R]");
  var ok = streq(got, "card [R] mail [R]");
  if string.str_contains(got, "a***@") { ok = false; }
  return assert(ok, "redact: cards and emails are replaced, emails not masked");
}

fn t18() -> TestResult {
  let line = "m a@b.com t AKIAIOSFODNN7EXAMPLE c 4539 5787 6362 1486";
  let got = secret_redact(line, "<P>");
  return assert(streq(got, "m <P> t <P> c <P>"), "redact: three secrets on one line");
}

fn t19() -> TestResult {
  var ok = streq(secret_redact("x a@b.com y", "<*>"), "x <*> y");
  if !streq(secret_redact("a@b.com", ""), "") { ok = false; }
  if !streq(secret_redact("clean text 123", "X"), "clean text 123") { ok = false; }
  if !streq(secret_redact("", "X"), "") { ok = false; }
  return assert(ok, "redact: placeholder verbatim, empty placeholder deletes, clean text kept");
}

fn t20() -> TestResult {
  var ok = secret_is_sensitive_key("password");
  if !secret_is_sensitive_key("DB_PASSWORD") { ok = false; }
  if !secret_is_sensitive_key("api_key") { ok = false; }
  if !secret_is_sensitive_key("myApiKeyValue") { ok = false; }
  if !secret_is_sensitive_key("Authorization") { ok = false; }
  if !secret_is_sensitive_key("private_key_pem") { ok = false; }
  if !secret_is_sensitive_key("ACCESS_TOKEN") { ok = false; }
  if secret_is_sensitive_key("username") { ok = false; }
  if secret_is_sensitive_key("monkey") { ok = false; }
  if secret_is_sensitive_key("") { ok = false; }
  if secret_is_sensitive_key("card_number") { ok = false; }
  return assert(ok, "sensitive keys: lowercased substring rules for the seven markers");
}

fn main() -> Int {
  io.println("=== xiom.secret conformance tests ===");
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
    io.println("xiom.secret: all tests passed");
  } else {
    io.println("xiom.secret: tests failed");
  }
  return failed;
}
