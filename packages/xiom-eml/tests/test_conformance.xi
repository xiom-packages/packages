// XIOM -- xiom.eml conformance tests (24 checks)
// Greenfield package: prove the pure-XIOM xiom.eml module against its
// documented RFC 5322/MIME structure grammar, unfolding rules, boundary
// rules and error catalog.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Coverage: simple messages, header-name lowercasing, folded continuations
// (space/tab/multi-line), duplicate headers, no-blank-line bodies, LF/CRLF/
// lone-CR/mixed line endings, malformed header errors, first/all lookups,
// multipart detection, quoted/bare/missing boundaries, splitting into two
// and three parts, the closing delimiter, preamble/epilogue suppression,
// empty input, colons in values, body lines that look like delimiters and
// raw part preservation.
//
// All Str equality goes through str_compare: BUG 17 lowers `==` on Str values
// read from Vec[Str] elements to a pointer comparison, so every comparison
// below is routed through streq/str_at/opt_str_is instead of `==`.

module eml_tests
use xiom.io; use xiom.test; use xiom.eml;
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

// True when the text fails to parse with an "eml: " error message.
fn parse_err_prefix(text: Str) -> Bool {
  let r = eml_parse(text);
  match r {
    Ok(_) => { return false; },
    Err(e) => { return string.str_starts_with(e, "eml: "); },
  }
  return false;
}

fn t1() -> TestResult {
  let r = eml_parse("From: alice@example.com\r\nTo: bob@example.com\r\nSubject: Hello\r\n\r\nLine one\r\nLine two\r\n");
  var ok = false;
  match r {
    Ok(e) => {
      ok = eml_header_count(&e) == 3;
      if !opt_str_is(eml_header(&e, "from"), "alice@example.com") { ok = false; }
      if !opt_str_is(eml_header(&e, "to"), "bob@example.com") { ok = false; }
      if !opt_str_is(eml_header(&e, "subject"), "Hello") { ok = false; }
      if !streq(e.body, "Line one\r\nLine two\r\n") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "simple message headers and verbatim body");
}

fn t2() -> TestResult {
  let r = eml_parse("Content-Type: text/plain\r\nX-CUSTOM-Header: v1\r\n\r\n");
  var ok = false;
  match r {
    Ok(e) => {
      ok = eml_header_count(&e) == 2;
      let n0: Str = e.names[0];
      let n1: Str = e.names[1];
      if !streq(n0, "content-type") { ok = false; }
      if !streq(n1, "x-custom-header") { ok = false; }
      if !opt_str_is(eml_header(&e, "Content-Type"), "text/plain") { ok = false; }
      if !opt_str_is(eml_header(&e, "X-CUSTOM-HEADER"), "v1") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "header names are lowercased; lookup is case-insensitive");
}

fn t3() -> TestResult {
  let r = eml_parse("Subject: first\r\n second\r\n\tthird\r\n\r\n");
  var ok = false;
  match r {
    Ok(e) => {
      ok = eml_header_count(&e) == 1;
      if !opt_str_is(eml_header(&e, "subject"), "first second third") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let r2 = eml_parse("Subject: alpha \r\n beta\r\n\r\n");
  match r2 {
    Ok(e2) => {
      if !opt_str_is(eml_header(&e2, "subject"), "alpha beta") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "folded continuation lines unfold with a single space");
}

fn t4() -> TestResult {
  let r = eml_parse("Received: one\r\nReceived: two\r\nReceived: three\r\n\r\n");
  var ok = false;
  match r {
    Ok(e) => {
      ok = eml_header_count(&e) == 3;
      if !opt_str_is(eml_header(&e, "received"), "one") { ok = false; }
      let all = eml_headers_all(&e, "received");
      if all.len() != 3 { ok = false; }
      if !str_at(&all, 0, "one") { ok = false; }
      if !str_at(&all, 1, "two") { ok = false; }
      if !str_at(&all, 2, "three") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "duplicate headers are preserved in order");
}

fn t5() -> TestResult {
  let r = eml_parse("A: 1\r\nB: 2");
  var ok = false;
  match r {
    Ok(e) => {
      ok = eml_header_count(&e) == 2;
      if !streq(e.body, "") { ok = false; }
      if !opt_str_is(eml_header(&e, "b"), "2") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let r2 = eml_parse("A: 1");
  match r2 {
    Ok(e2) => {
      if eml_header_count(&e2) != 1 { ok = false; }
      if !streq(e2.body, "") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "a message with no blank line has an empty body");
}

fn t6() -> TestResult {
  let lf = eml_parse("A: 1\nB: 2\n\nbody\n");
  var ok = false;
  match lf {
    Ok(e) => {
      ok = eml_header_count(&e) == 2;
      if !opt_str_is(eml_header(&e, "b"), "2") { ok = false; }
      if !streq(e.body, "body\n") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let crlf = eml_parse("A: 1\r\nB: 2\r\n\r\nbody\r\n");
  match crlf {
    Ok(e2) => {
      if eml_header_count(&e2) != 2 { ok = false; }
      if !opt_str_is(eml_header(&e2, "b"), "2") { ok = false; }
      if !streq(e2.body, "body\r\n") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "LF-only and CRLF messages parse identically");
}

fn t7() -> TestResult {
  var ok = parse_err_prefix("A: 1\r\nBADHEADER\r\n\r\n");
  if !parse_err_prefix("this is not a header") { ok = false; }
  if parse_err_prefix("A: 1\r\n\r\nnot a header in the body") { ok = false; }
  return assert(ok, "header line without a colon is Err; body text is not parsed");
}

fn t8() -> TestResult {
  let r = eml_parse("X: 1\r\nX: 2\r\nY: 3\r\n\r\n");
  var ok = false;
  match r {
    Ok(e) => {
      ok = opt_str_is(eml_header(&e, "x"), "1");
      if !opt_str_is(eml_header(&e, "y"), "3") { ok = false; }
      if !opt_str_is(eml_header(&e, "Y"), "3") { ok = false; }
      if !opt_str_none(eml_header(&e, "z")) { ok = false; }
      let xs = eml_headers_all(&e, "x");
      if xs.len() != 2 { ok = false; }
      if !str_at(&xs, 0, "1") { ok = false; }
      if !str_at(&xs, 1, "2") { ok = false; }
      if eml_headers_all(&e, "z").len() != 0 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "header returns the first match and headers_all every match");
}

fn t9() -> TestResult {
  let plain = eml_parse("Content-Type: text/plain\r\n\r\n");
  let multi = eml_parse("Content-Type: multipart/mixed; boundary=m1\r\n\r\n");
  let upper = eml_parse("Content-Type: MULTIPART/MIXED; boundary=m2\r\n\r\n");
  let none = eml_parse("Subject: no content type\r\n\r\n");
  var ok = false;
  match plain {
    Ok(e) => { ok = !eml_is_multipart(&e); },
    Err(_) => { ok = false; },
  }
  match multi {
    Ok(e) => { if !eml_is_multipart(&e) { ok = false; } },
    Err(_) => { ok = false; },
  }
  match upper {
    Ok(e) => { if !eml_is_multipart(&e) { ok = false; } },
    Err(_) => { ok = false; },
  }
  match none {
    Ok(e) => {
      if eml_is_multipart(&e) { ok = false; }
      if !opt_str_none(eml_content_type_boundary(&e)) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "is_multipart detects multipart/ content types");
}

fn t10() -> TestResult {
  let bare = eml_parse("Content-Type: multipart/mixed; boundary=xyz\r\n\r\n");
  let ordered = eml_parse("Content-Type: multipart/mixed;charset=utf-8;boundary=b2;foo=bar\r\n\r\n");
  let missing = eml_parse("Content-Type: multipart/mixed; charset=utf-8\r\n\r\n");
  var ok = false;
  match bare {
    Ok(e) => { ok = opt_str_is(eml_content_type_boundary(&e), "xyz"); },
    Err(_) => { ok = false; },
  }
  match ordered {
    Ok(e) => { if !opt_str_is(eml_content_type_boundary(&e), "b2") { ok = false; } },
    Err(_) => { ok = false; },
  }
  match missing {
    Ok(e) => { if !opt_str_none(eml_content_type_boundary(&e)) { ok = false; } },
    Err(_) => { ok = false; },
  }
  return assert(ok, "bare boundary parameters are parsed in any position");
}

fn t11() -> TestResult {
  let quoted = eml_parse("Content-Type: multipart/mixed; boundary=\"abc-123\"\r\n\r\n");
  let spaced = eml_parse("Content-Type: multipart/mixed; boundary = \"spaced value\"\r\n\r\n");
  var ok = false;
  match quoted {
    Ok(e) => { ok = opt_str_is(eml_content_type_boundary(&e), "abc-123"); },
    Err(_) => { ok = false; },
  }
  match spaced {
    Ok(e) => { if !opt_str_is(eml_content_type_boundary(&e), "spaced value") { ok = false; } },
    Err(_) => { ok = false; },
  }
  return assert(ok, "quoted boundary values lose their quotes");
}

fn t12() -> TestResult {
  let r = eml_parse("Content-Type: multipart/mixed; boundary=b1\r\n\r\n--b1\r\nAAAA\r\n--b1\r\nBBBB\r\n--b1--\r\n");
  var ok = false;
  match r {
    Ok(e) => {
      let b = eml_content_type_boundary(&e);
      match b {
        Some(bn) => {
          let parts = eml_split_parts(&e, bn);
          ok = parts.len() == 2;
          if !str_at(&parts, 0, "AAAA") { ok = false; }
          if !str_at(&parts, 1, "BBBB") { ok = false; }
        },
        None => { ok = false; },
      }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "split_parts yields two parts using the parsed boundary");
}

fn t13() -> TestResult {
  let r = eml_parse("MIME-Version: 1.0\r\nContent-Type: multipart/mixed; boundary=b\r\n\r\n--b\r\none\r\n--b\r\ntwo\r\n--b\r\nthree\r\n--b--\r\n");
  var ok = false;
  match r {
    Ok(e) => {
      let parts = eml_split_parts(&e, "b");
      ok = parts.len() == 3;
      if !str_at(&parts, 0, "one") { ok = false; }
      if !str_at(&parts, 1, "two") { ok = false; }
      if !str_at(&parts, 2, "three") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "split_parts yields three parts in order");
}

fn t14() -> TestResult {
  let r = eml_parse("Content-Type: multipart/mixed; boundary=b\r\n\r\n--b\r\nonly\r\n--b--\r\nEPILOGUE\r\n");
  var ok = false;
  match r {
    Ok(e) => {
      let parts = eml_split_parts(&e, "b");
      ok = parts.len() == 1;
      if !str_at(&parts, 0, "only") { ok = false; }
      var i = 0;
      while i < parts.len() {
        if str_contains(parts[i], "EPILOGUE") { ok = false; }
        if streq(parts[i], "--b--") { ok = false; }
        i = i + 1;
      }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "the closing delimiter and epilogue are excluded");
}

fn t15() -> TestResult {
  let r = eml_parse("Content-Type: multipart/mixed; boundary=b\r\n\r\npreamble text\r\n--b\r\nX\r\n--b--\r\nepilogue --b--\r\n");
  var ok = false;
  match r {
    Ok(e) => {
      let parts = eml_split_parts(&e, "b");
      ok = parts.len() == 1;
      if !str_at(&parts, 0, "X") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "preamble and epilogue are ignored");
}

fn t16() -> TestResult {
  let r = eml_parse("");
  var ok = false;
  match r {
    Ok(e) => {
      ok = eml_header_count(&e) == 0;
      if !streq(e.body, "") { ok = false; }
      if eml_is_multipart(&e) { ok = false; }
      if !opt_str_none(eml_header(&e, "subject")) { ok = false; }
      if !opt_str_none(eml_content_type_boundary(&e)) { ok = false; }
      if eml_split_parts(&e, "b").len() != 0 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "empty text parses as an empty message");
}

fn t17() -> TestResult {
  let r = eml_parse("X: a:b:c\r\nDate: 10:20:30\r\n\r\n");
  var ok = false;
  match r {
    Ok(e) => {
      ok = eml_header_count(&e) == 2;
      if !opt_str_is(eml_header(&e, "x"), "a:b:c") { ok = false; }
      if !opt_str_is(eml_header(&e, "date"), "10:20:30") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "a colon inside a value is kept");
}

fn t18() -> TestResult {
  let r = eml_parse("Content-Type: multipart/mixed; boundary=b\r\n\r\n------\r\n--notb\r\ninline --b text\r\n--b\r\nX\r\n--b--\r\n");
  var ok = false;
  match r {
    Ok(e) => {
      let parts = eml_split_parts(&e, "b");
      ok = parts.len() == 1;
      if !str_at(&parts, 0, "X") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let r2 = eml_parse("Content-Type: multipart/mixed; boundary=b\r\n\r\n--b\r\nhello --b there\r\n--b--\r\n");
  match r2 {
    Ok(e2) => {
      let p2 = eml_split_parts(&e2, "b");
      if p2.len() != 1 { ok = false; }
      if !str_at(&p2, 0, "hello --b there") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "body lines that only resemble delimiters are part content");
}

fn t19() -> TestResult {
  let r = eml_parse("X:\r\nB: 2\r\n\r\n");
  var ok = false;
  match r {
    Ok(e) => {
      ok = eml_header_count(&e) == 2;
      if !opt_str_is(eml_header(&e, "x"), "") { ok = false; }
      if !opt_str_is(eml_header(&e, "b"), "2") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "an empty header value is kept and counted");
}

fn t20() -> TestResult {
  let r = eml_parse("Content-Type: multipart/mixed; boundary=b\r\n\r\n--b\r\nH: v\r\n\r\nbody\r\n--b--\r\n");
  var ok = false;
  match r {
    Ok(e) => {
      let parts = eml_split_parts(&e, "b");
      ok = parts.len() == 1;
      if !str_at(&parts, 0, "H: v\r\n\r\nbody") { ok = false; }
      if !str_contains(parts[0], "\r\n") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "parts are raw: internal CRLF sequences survive");
}

fn t21() -> TestResult {
  let r = eml_parse("Content-Type: multipart/mixed; boundary=b\r\n\r\n--b\r\nAAA\r\n--b\r\nBBB");
  var ok = false;
  match r {
    Ok(e) => {
      let parts = eml_split_parts(&e, "b");
      ok = parts.len() == 2;
      if !str_at(&parts, 0, "AAA") { ok = false; }
      if !str_at(&parts, 1, "BBB") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let r2 = eml_parse("Content-Type: multipart/mixed; boundary=b\r\n\r\n--b\r\nAAA");
  match r2 {
    Ok(e2) => {
      let p2 = eml_split_parts(&e2, "b");
      if p2.len() != 1 { ok = false; }
      if !str_at(&p2, 0, "AAA") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "an unterminated multipart body keeps its final part");
}

fn t22() -> TestResult {
  let a = eml_parse("A: 1\r\n\nbody");
  let b = eml_parse("A: 1\n\r\nbody");
  let c = eml_parse("A: 1\r\rbody");
  var ok = false;
  match a {
    Ok(e) => { ok = opt_str_is(eml_header(&e, "a"), "1"); if !streq(e.body, "body") { ok = false; } },
    Err(_) => { ok = false; },
  }
  match b {
    Ok(e) => { if !streq(e.body, "body") { ok = false; } },
    Err(_) => { ok = false; },
  }
  match c {
    Ok(e) => { if !streq(e.body, "body") { ok = false; } },
    Err(_) => { ok = false; },
  }
  return assert(ok, "CRLF+LF, LF+CRLF and lone CR blank lines are tolerated");
}

fn t23() -> TestResult {
  var ok = parse_err_prefix(" orphan\r\nA: 1\r\n\r\n");
  let r = eml_parse("A: 1\r\n \r\nB: 2\r\n\r\n");
  match r {
    Ok(e) => {
      if eml_header_count(&e) != 2 { ok = false; }
      if !opt_str_is(eml_header(&e, "a"), "1") { ok = false; }
      if !opt_str_is(eml_header(&e, "b"), "2") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "a continuation before any header is Err; a blank fold is harmless");
}

fn t24() -> TestResult {
  let r = eml_parse("Subject:   spaced value  \r\nX:\ttabbed\r\n\r\n");
  var ok = false;
  match r {
    Ok(e) => {
      ok = eml_header_count(&e) == 2;
      if !opt_str_is(eml_header(&e, "subject"), "spaced value") { ok = false; }
      if !opt_str_is(eml_header(&e, "x"), "tabbed") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "value whitespace after the colon is trimmed");
}

fn main() -> Int {
  io.println("=== xiom.eml conformance tests ===");
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
    io.println("xiom.eml: all tests passed");
  } else {
    io.println("xiom.eml: tests failed");
  }
  return failed;
}
