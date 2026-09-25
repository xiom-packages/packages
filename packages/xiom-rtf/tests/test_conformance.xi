// XIOM -- xiom.rtf conformance tests (26 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Covers the documented subset: the {\rtf1 document start, group nesting and
// depths, control words with parameters, control symbols, hex escapes,
// unicode escapes and fallbacks, surrogate handling, CRLF normalization,
// the error catalog, accessors, canonical emission and round-trip.
//
// All Str equality goes through str_compare: BUG 17 lowers `==` on Str values
// read from Vec[Str] elements to a pointer comparison, so every token check
// below is routed through the streq/tok_is helpers.

module rtf_tests
use xiom.io; use xiom.test;
use xiom.rtf;
use xiom.string;
use xiom.string.compare;

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn empty_tokens() -> RtfTokens {
  return RtfTokens{
    kinds: Vec[Str].new();
    texts: Vec[Str].new();
    params: Vec[Int].new();
    depth: Vec[Int].new();
  };
}

// Parse, falling back to an empty stream on error: tests that expect a
// successful parse always check token counts and contents, so a rejected
// document cannot make them pass.
fn parsed(text: Str) -> RtfTokens {
  let r = rtf_parse(text);
  match r {
    Ok(t) => { return t; },
    Err(_) => { return empty_tokens(); },
  }
  return empty_tokens();
}

// True when parsing `text` fails with exactly the error `want`.
fn err_is(text: Str, want: Str) -> Bool {
  let r = rtf_parse(text);
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

// True when token `i` has the wanted kind, text, parameter and depth.
fn tok_is(t: &RtfTokens, i: Int, kind: Str, text: Str, param: Int, depth: Int) -> Bool {
  if !streq(rtf_kind(t, i), kind) { return false; }
  if !streq(rtf_text(t, i), text) { return false; }
  if rtf_param(t, i) != param { return false; }
  if rtf_depth(t, i) != depth { return false; }
  return true;
}

// True when two token streams agree on count, kind, text, parameter and
// depth for every token.
fn tokens_eq(a: &RtfTokens, b: &RtfTokens) -> Bool {
  if a.kinds.len() != b.kinds.len() { return false; }
  var i = 0;
  while i < a.kinds.len() {
    if !streq(rtf_kind(a, i), rtf_kind(b, i)) { return false; }
    if !streq(rtf_text(a, i), rtf_text(b, i)) { return false; }
    let pa: Int = a.params[i];
    let pb: Int = b.params[i];
    if pa != pb { return false; }
    let da: Int = a.depth[i];
    let db: Int = b.depth[i];
    if da != db { return false; }
    i = i + 1;
  }
  return true;
}

// True when `s` is exactly the three bytes w0, w1, w2.
fn bytes_eq3(s: Str, w0: Int, w1: Int, w2: Int) -> Bool {
  if s.len() != 3 { return false; }
  let a: Int = (string.byte_at(s, 0) as Int) & 0xFF;
  let b: Int = (string.byte_at(s, 1) as Int) & 0xFF;
  let c: Int = (string.byte_at(s, 2) as Int) & 0xFF;
  if a != w0 { return false; }
  if b != w1 { return false; }
  if c != w2 { return false; }
  return true;
}

// True when `s` is exactly the four bytes w0..w3.
fn bytes_eq4(s: Str, w0: Int, w1: Int, w2: Int, w3: Int) -> Bool {
  if s.len() != 4 { return false; }
  let a: Int = (string.byte_at(s, 0) as Int) & 0xFF;
  let b: Int = (string.byte_at(s, 1) as Int) & 0xFF;
  let c: Int = (string.byte_at(s, 2) as Int) & 0xFF;
  let d: Int = (string.byte_at(s, 3) as Int) & 0xFF;
  if a != w0 { return false; }
  if b != w1 { return false; }
  if c != w2 { return false; }
  if d != w3 { return false; }
  return true;
}

fn t1() -> TestResult {
  let t = parsed("{\\rtf1}");
  let np = rtf_no_param();
  var ok = rtf_token_count(&t) == 3;
  if !tok_is(&t, 0, "group_open", "", np, 0) { ok = false; }
  if !tok_is(&t, 1, "control", "rtf", 1, 1) { ok = false; }
  if !tok_is(&t, 2, "group_close", "", np, 1) { ok = false; }
  return assert(ok, "document start: {\\rtf1} yields group_open, control rtf=1, group_close");
}

fn t2() -> TestResult {
  let t = parsed("{\\rtf1\\ansi\\deff0}");
  let np = rtf_no_param();
  var ok = rtf_token_count(&t) == 5;
  if !tok_is(&t, 2, "control", "ansi", np, 1) { ok = false; }
  if !tok_is(&t, 3, "control", "deff", 0, 1) { ok = false; }
  if rtf_has_param(&t, 2) { ok = false; }
  if !rtf_has_param(&t, 3) { ok = false; }
  return assert(ok, "control words: optional numeric parameter and rtf_has_param");
}

fn t3() -> TestResult {
  let t = parsed("{\\rtf1\\li-360\\sb120}");
  var ok = rtf_token_count(&t) == 5;
  if !tok_is(&t, 2, "control", "li", -360, 1) { ok = false; }
  if !tok_is(&t, 3, "control", "sb", 120, 1) { ok = false; }
  return assert(ok, "control words: signed and multi-digit parameters");
}

fn t4() -> TestResult {
  let t = parsed("{\\rtf1 a\\\\b\\{c\\}d}");
  let np = rtf_no_param();
  var ok = rtf_token_count(&t) == 10;
  if !tok_is(&t, 2, "text", "a", np, 1) { ok = false; }
  if !tok_is(&t, 3, "symbol", "\\", np, 1) { ok = false; }
  if !tok_is(&t, 4, "text", "b", np, 1) { ok = false; }
  if !tok_is(&t, 5, "symbol", "{", np, 1) { ok = false; }
  if !tok_is(&t, 6, "text", "c", np, 1) { ok = false; }
  if !tok_is(&t, 7, "symbol", "}", np, 1) { ok = false; }
  if !tok_is(&t, 8, "text", "d", np, 1) { ok = false; }
  if !streq(rtf_plain_text(&t), "a\\b{c}d") { ok = false; }
  return assert(ok, "control symbols: escaped backslash and braces are literal text");
}

fn t5() -> TestResult {
  let t = parsed("{\\rtf1{a{b}c}}");
  let np = rtf_no_param();
  var ok = rtf_token_count(&t) == 10;
  if !tok_is(&t, 0, "group_open", "", np, 0) { ok = false; }
  if !tok_is(&t, 2, "group_open", "", np, 1) { ok = false; }
  if !tok_is(&t, 3, "text", "a", np, 2) { ok = false; }
  if !tok_is(&t, 4, "group_open", "", np, 2) { ok = false; }
  if !tok_is(&t, 5, "text", "b", np, 3) { ok = false; }
  if !tok_is(&t, 6, "group_close", "", np, 3) { ok = false; }
  if !tok_is(&t, 7, "text", "c", np, 2) { ok = false; }
  if !tok_is(&t, 8, "group_close", "", np, 2) { ok = false; }
  if !tok_is(&t, 9, "group_close", "", np, 1) { ok = false; }
  return assert(ok, "groups: nesting depths on opens, contents and closes");
}

fn t6() -> TestResult {
  let t = parsed("{\\rtf1\\'41\\'2e}");
  var ok = rtf_token_count(&t) == 5;
  if !tok_is(&t, 2, "hex", "41", 65, 1) { ok = false; }
  if !tok_is(&t, 3, "hex", "2e", 46, 1) { ok = false; }
  if rtf_hex_value(&t, 2) != 65 { ok = false; }
  if rtf_hex_value(&t, 3) != 46 { ok = false; }
  if rtf_hex_value(&t, 1) != -1 { ok = false; }
  if !streq(rtf_plain_text(&t), "A.") { ok = false; }
  return assert(ok, "hex escapes: byte tokens, value accessor and plain text");
}

fn t7() -> TestResult {
  let t = parsed("{\\rtf1\\'4A\\'bF}");
  var ok = rtf_token_count(&t) == 5;
  if !tok_is(&t, 2, "hex", "4a", 74, 1) { ok = false; }
  if !tok_is(&t, 3, "hex", "bf", 191, 1) { ok = false; }
  return assert(ok, "hex escapes: digits normalize to lowercase, any case accepted");
}

fn t8() -> TestResult {
  let t = parsed("{\\rtf1\\u65?}");
  var ok = rtf_token_count(&t) == 4;
  if !tok_is(&t, 2, "unicode", "A", 65, 1) { ok = false; }
  if !streq(rtf_plain_text(&t), "A") { ok = false; }
  let e = parsed("{\\rtf1\\u8364?}");
  var ok2 = rtf_token_count(&e) == 4;
  if !streq(rtf_kind(&e, 2), "unicode") { ok2 = false; }
  if rtf_param(&e, 2) != 8364 { ok2 = false; }
  if rtf_depth(&e, 2) != 1 { ok2 = false; }
  if !bytes_eq3(rtf_text(&e, 2), 226, 130, 172) { ok2 = false; }
  if !bytes_eq3(rtf_plain_text(&e), 226, 130, 172) { ok2 = false; }
  if !ok2 { ok = false; }
  return assert(ok, "unicode escapes: \\u65? is A and \\u8364? is the 3-byte euro sign");
}

fn t9() -> TestResult {
  let t = parsed("{\\rtf1\\u-10179?}");
  var ok = rtf_token_count(&t) == 4;
  if !streq(rtf_kind(&t, 2), "unicode") { ok = false; }
  if rtf_param(&t, 2) != 55357 { ok = false; }
  if rtf_depth(&t, 2) != 1 { ok = false; }
  if !bytes_eq3(rtf_text(&t, 2), 237, 160, 189) { ok = false; }
  let p = parsed("{\\rtf1\\u-10179\\u-8704?}");
  var ok2 = rtf_token_count(&p) == 5;
  if rtf_param(&p, 2) != 55357 { ok2 = false; }
  if rtf_param(&p, 3) != 56832 { ok2 = false; }
  if !bytes_eq4(rtf_plain_text(&p), 240, 159, 152, 128) { ok2 = false; }
  if !ok2 { ok = false; }
  return assert(ok, "unicode escapes: negative values add 65536 and a surrogate pair joins");
}

fn t10() -> TestResult {
  let a = parsed("{\\rtf1\\u65}");
  var ok = rtf_token_count(&a) == 4;
  if !streq(rtf_plain_text(&a), "A") { ok = false; }
  let b = parsed("{\\rtf1\\u65\\b}");
  if rtf_token_count(&b) != 5 { ok = false; }
  if !tok_is(&b, 3, "control", "b", rtf_no_param(), 1) { ok = false; }
  let c = parsed("{\\rtf1\\u65 ?}");
  if rtf_token_count(&c) != 4 { ok = false; }
  if !streq(rtf_plain_text(&c), "A") { ok = false; }
  let d = parsed("{\\rtf1\\u65  x}");
  if rtf_token_count(&d) != 5 { ok = false; }
  if !tok_is(&d, 3, "text", "x", rtf_no_param(), 1) { ok = false; }
  if !streq(rtf_plain_text(&d), "Ax") { ok = false; }
  return assert(ok, "unicode fallback: absent, control-adjacent and one byte fallback all accepted");
}

fn t11() -> TestResult {
  let t = parsed("{\\rtf1 a\r\nb\rc\nd}");
  var ok = rtf_token_count(&t) == 4;
  if !tok_is(&t, 2, "text", "a\nb\nc\nd", rtf_no_param(), 1) { ok = false; }
  if !streq(rtf_plain_text(&t), "a\nb\nc\nd") { ok = false; }
  return assert(ok, "text runs: CRLF and lone CR normalize to LF");
}

fn t12() -> TestResult {
  var ok = err_is("hello", "rtf: text before document start at 0");
  if !err_is("", "rtf: text before document start at 0") { ok = false; }
  if !err_is("  {\\rtf1}", "rtf: text before document start at 0") { ok = false; }
  if !err_is("{\\rtf2}", "rtf: text before document start at 5") { ok = false; }
  if !err_is("{\\rtf}", "rtf: text before document start at 5") { ok = false; }
  if !err_is("{\\rtf12}", "rtf: bad document start at 1") { ok = false; }
  return assert(ok, "document start: text before the prefix, wrong version, wrong rtf parameter");
}

fn t13() -> TestResult {
  var ok = err_is("{\\rtf1", "rtf: unbalanced braces at 0");
  if !err_is("{\\rtf1{a}", "rtf: unbalanced braces at 0") { ok = false; }
  if !err_is("{\\rtf1}x", "rtf: trailing bytes after document end at 7") { ok = false; }
  if !err_is("{\\rtf1}{}", "rtf: trailing bytes after document end at 7") { ok = false; }
  return assert(ok, "braces: unclosed groups and trailing bytes after the outer close");
}

fn t14() -> TestResult {
  var ok = err_is("{\\rtf1\\#}", "rtf: bad control word at 6");
  if !err_is("{\\rtf1\\", "rtf: bad control word at 6") { ok = false; }
  if !err_is("{\\rtf1\\abcdefghijklmnopqrstuvwxyzabcdefg}", "rtf: bad control word at 6") { ok = false; }
  let t = parsed("{\\rtf1\\abcdefghijklmnopqrstuvwxyzabcdef}");
  if rtf_token_count(&t) != 4 { ok = false; }
  if !tok_is(&t, 2, "control", "abcdefghijklmnopqrstuvwxyzabcdef", rtf_no_param(), 1) { ok = false; }
  return assert(ok, "control words: non-letters, EOF and names over 32 letters are rejected");
}

fn t15() -> TestResult {
  var ok = err_is("{\\rtf1\\li2147483648}", "rtf: numeric overflow at 6");
  if !err_is("{\\rtf1\\li99999999999}", "rtf: numeric overflow at 6") { ok = false; }
  let a = parsed("{\\rtf1\\li2147483647}");
  if !tok_is(&a, 2, "control", "li", 2147483647, 1) { ok = false; }
  let b = parsed("{\\rtf1\\li-2147483648}");
  if !tok_is(&b, 2, "control", "li", -2147483648, 1) { ok = false; }
  return assert(ok, "numeric parameters: signed 32-bit bounds and overflow errors");
}

fn t16() -> TestResult {
  var ok = err_is("{\\rtf1\\u}", "rtf: truncated unicode escape at 6");
  if !err_is("{\\rtf1\\u\\b}", "rtf: truncated unicode escape at 6") { ok = false; }
  if !err_is("{\\rtf1\\u-}", "rtf: truncated unicode escape at 6") { ok = false; }
  let t = parsed("{\\rtf1\\u69}");
  if !tok_is(&t, 2, "unicode", "E", 69, 1) { ok = false; }
  return assert(ok, "unicode escapes: a missing numeric parameter is a truncation error");
}

fn t17() -> TestResult {
  var ok = err_is("{\\rtf1\\'4}", "rtf: bad hex escape at 6");
  if !err_is("{\\rtf1\\'zz}", "rtf: bad hex escape at 6") { ok = false; }
  if !err_is("{\\rtf1\\'}", "rtf: bad hex escape at 6") { ok = false; }
  let t = parsed("{\\rtf1\\'4a}");
  if !tok_is(&t, 2, "hex", "4a", 74, 1) { ok = false; }
  return assert(ok, "hex escapes: non-hex and short digit pairs are rejected");
}

fn t18() -> TestResult {
  var ok = err_is("{\\rtf1\\u32768}", "rtf: unicode value out of range at 6");
  if !err_is("{\\rtf1\\u99999}", "rtf: unicode value out of range at 6") { ok = false; }
  if !err_is("{\\rtf1\\u-32769}", "rtf: unicode value out of range at 6") { ok = false; }
  let t = parsed("{\\rtf1\\u-32768?}");
  var ok2 = rtf_token_count(&t) == 4;
  if rtf_param(&t, 2) != 32768 { ok2 = false; }
  if !bytes_eq3(rtf_text(&t, 2), 232, 128, 128) { ok2 = false; }
  if !ok2 { ok = false; }
  return assert(ok, "unicode escapes: parameters outside signed 16-bit are out of range");
}

fn t19() -> TestResult {
  let t = parsed("{\\rtf1}");
  var ok = streq(rtf_kind(&t, -1), "");
  if !streq(rtf_kind(&t, 99), "") { ok = false; }
  if !streq(rtf_text(&t, -1), "") { ok = false; }
  if rtf_param(&t, 99) != rtf_no_param() { ok = false; }
  if rtf_depth(&t, -1) != -1 { ok = false; }
  if rtf_hex_value(&t, 99) != -1 { ok = false; }
  if rtf_has_param(&t, -5) { ok = false; }
  let a = parsed("{\\rtf1\\b0}");
  if !rtf_has_param(&a, 2) { ok = false; }
  if rtf_has_param(&a, 0) { ok = false; }
  return assert(ok, "accessors: out-of-range indices return \"\", -1 and the no-param sentinel");
}

fn t20() -> TestResult {
  let t = parsed("{\\rtf1\\ansi\\deff0 \\u65? Hello}");
  var ok = streq(rtf_emit(&t), "{\\rtf1 \\ansi \\deff0 \\u65 ? Hello}");
  let h = parsed("{\\rtf1\\'4A}");
  if !streq(rtf_emit(&h), "{\\rtf1 \\'4a}") { ok = false; }
  let s = parsed("{\\rtf1\\u-10179?}");
  if !streq(rtf_emit(&s), "{\\rtf1 \\u-10179 ?}") { ok = false; }
  return assert(ok, "canonical emitter: single spaces, lowercase hex, signed \\u with ? fallback");
}

fn t21() -> TestResult {
  let src = "{\\rtf1\\ansi \\b bold\\i  \\{q\\} \\'41 \\u65?\\u-10179\\u-8704?}";
  let t1 = parsed(src);
  let out1 = rtf_emit(&t1);
  let t2 = parsed(out1);
  var ok = tokens_eq(&t1, &t2);
  if !streq(rtf_emit(&t2), out1) { ok = false; }
  if !streq(rtf_plain_text(&t1), rtf_plain_text(&t2)) { ok = false; }
  return assert(ok, "round-trip: parse -> emit -> parse is token-identical, emit idempotent");
}

fn t22() -> TestResult {
  let t = parsed("{\\rtf1 Hi \\'41\\u66? \\{x\\} \\\\ end}");
  return assert(streq(rtf_plain_text(&t), "Hi AB {x} \\ end"), "plain text: text, hex, unicode and symbols, control words excluded");
}

fn t23() -> TestResult {
  let t = parsed("{\\rtf1}");
  var ok = rtf_token_count(&t) == 3;
  if !streq(rtf_plain_text(&t), "") { ok = false; }
  let n = parsed("{\\rtf1{}}");
  if rtf_token_count(&n) != 5 { ok = false; }
  if !tok_is(&n, 2, "group_open", "", rtf_no_param(), 1) { ok = false; }
  if !tok_is(&n, 3, "group_close", "", rtf_no_param(), 2) { ok = false; }
  if !tok_is(&n, 4, "group_close", "", rtf_no_param(), 1) { ok = false; }
  return assert(ok, "empty documents and empty nested groups tokenize cleanly");
}

fn t24() -> TestResult {
  let t = parsed("{\\rtf1\\u0?}");
  var ok = rtf_token_count(&t) == 4;
  if !tok_is(&t, 2, "unicode", "", 0, 1) { ok = false; }
  if !streq(rtf_plain_text(&t), "") { ok = false; }
  let out = rtf_emit(&t);
  if !streq(out, "{\\rtf1 \\u0 ?}") { ok = false; }
  let t2 = parsed(out);
  if !tokens_eq(&t, &t2) { ok = false; }
  return assert(ok, "code unit 0: empty text, skipped by plain text, canonical \\u0 ? round-trips");
}

fn t25() -> TestResult {
  let t = parsed("{\\rtf1\\'00x}");
  var ok = rtf_token_count(&t) == 5;
  if !tok_is(&t, 2, "hex", "00", 0, 1) { ok = false; }
  if !streq(rtf_plain_text(&t), "x") { ok = false; }
  if rtf_hex_value(&t, 2) != 0 { ok = false; }
  return assert(ok, "hex escape \\'00: byte value 0 is kept, plain text skips the NUL");
}

fn t26() -> TestResult {
  let t = parsed("{\\rtf1\\u65{}x}");
  var ok = rtf_token_count(&t) == 7;
  if !tok_is(&t, 3, "group_open", "", rtf_no_param(), 1) { ok = false; }
  if !tok_is(&t, 4, "group_close", "", rtf_no_param(), 2) { ok = false; }
  if !tok_is(&t, 5, "text", "x", rtf_no_param(), 1) { ok = false; }
  return assert(ok, "unicode fallback: a following brace is not consumed as the fallback byte");
}

fn main() -> Int {
  io.println("=== xiom.rtf conformance tests ===");
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
  let r25 = t25();
  if r25.passed { io.println("  [PASS] " + r25.name); } else { io.println("  [FAIL] " + r25.name); failed = failed + 1; }
  let r26 = t26();
  if r26.passed { io.println("  [PASS] " + r26.name); } else { io.println("  [FAIL] " + r26.name); failed = failed + 1; }
  if failed == 0 {
    io.println("xiom.rtf: all tests passed");
  } else {
    io.println("xiom.rtf: tests failed");
  }
  return failed;
}
