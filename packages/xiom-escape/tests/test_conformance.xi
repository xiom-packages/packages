// XIOM -- xiom.escape conformance tests (20 checks)
// Port task: prove the pure-XIOM xiom.escape module against its documented sets.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Covers the documented API: JSON escape/unescape (quotes, backslashes, the
// short escapes, control bytes as \u00XX, \uXXXX decoding and the error
// catalog), HTML escape/unescape (five named entities, decimal and hex
// numeric references, leniency, round trips), URL percent-encoding/decoding
// (reserved, space, unicode, round trip, bad percent) and POSIX shell
// double-quote escaping.
//
// All Str equality goes through str_compare: BUG 17 lowers `==` on Str values
// read from Vec[Str] elements to a pointer comparison, so every comparison
// below is routed through streq/err_eq instead of `==`.

module escape_tests
use xiom.io; use xiom.test; use xiom.escape;
use xiom.string;
use xiom.string.compare;

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// True when r is an Err whose message is exactly `want`.
fn err_eq(r: Result[Str, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return streq(r.error, want);
}

// Str from two raw bytes (for control bytes that source literals cannot spell).
fn str_of2(a: Int, b: Int) -> Str {
  var v = Vec[UInt8].new();
  v.push(a as UInt8);
  v.push(b as UInt8);
  return Str::from_utf8(v);
}

// Str from three raw bytes.
fn str_of3(a: Int, b: Int, c: Int) -> Str {
  var v = Vec[UInt8].new();
  v.push(a as UInt8);
  v.push(b as UInt8);
  v.push(c as UInt8);
  return Str::from_utf8(v);
}

fn t1() -> TestResult {
  let r = escape_json_string("a\"b\\c");
  var ok = streq(r, "a\\\"b\\\\c");
  let q = escape_json_string("\"");
  if !streq(q, "\\\"") { ok = false; }
  let bs = escape_json_string("\\");
  if !streq(bs, "\\\\") { ok = false; }
  return assert(ok, "json escape: quote and backslash");
}

fn t2() -> TestResult {
  let nl = escape_json_string("a\nb");
  var ok = streq(nl, "a\\nb");
  let tb = escape_json_string("a\tb");
  if !streq(tb, "a\\tb") { ok = false; }
  let cr = escape_json_string("a\rb");
  if !streq(cr, "a\\rb") { ok = false; }
  let bsp = escape_json_string(str_of3(97, 8, 98));
  if !streq(bsp, "a\\bb") { ok = false; }
  let ff = escape_json_string(str_of3(99, 12, 100));
  if !streq(ff, "c\\fd") { ok = false; }
  return assert(ok, "json escape: backspace, formfeed, newline, CR and tab");
}

fn t3() -> TestResult {
  let ctl = escape_json_string(str_of2(1, 31));
  var ok = streq(ctl, "\\u0001\\u001F");
  let mid = escape_json_string(str_of3(65, 2, 66));
  if !streq(mid, "A\\u0002B") { ok = false; }
  return assert(ok, "json escape: control bytes become \\u00XX uppercase");
}

fn t4() -> TestResult {
  let r = unescape_json_string("a\\\"b\\\\c");
  var ok = r.is_ok;
  if ok && !streq(r.value, "a\"b\\c") { ok = false; }
  let s = "x\ny\tz\r\"q\"\\w";
  let rt = unescape_json_string(escape_json_string(s));
  if !rt.is_ok { ok = false; }
  if rt.is_ok && !streq(rt.value, s) { ok = false; }
  return assert(ok, "json unescape: short escapes and full round trip");
}

fn t5() -> TestResult {
  let up = unescape_json_string("\\u0041");
  var ok = up.is_ok;
  if ok && !streq(up.value, "A") { ok = false; }
  let low = unescape_json_string("\\u0061");
  if !low.is_ok { ok = false; }
  if low.is_ok && !streq(low.value, "a") { ok = false; }
  let slash = unescape_json_string("a\\/b");
  if !slash.is_ok { ok = false; }
  if slash.is_ok && !streq(slash.value, "a/b") { ok = false; }
  let bf = unescape_json_string("\\b\\f\\n\\r\\t");
  if !bf.is_ok { ok = false; }
  if bf.is_ok {
    let bf_txt = bf.value;
    if bf_txt.len() != 5 { ok = false; }
  }
  return assert(ok, "json unescape: \\u0041, lowercase hex, \\/ and short escapes");
}

fn t6() -> TestResult {
  let r = unescape_json_string("\\u2713");
  var ok = r.is_ok;
  if ok {
    let txt = r.value;
    if txt.len() != 3 { ok = false; }
    if !streq(txt, "✓") { ok = false; }
  }
  let mixed = unescape_json_string("A\\u00e9B");
  if !mixed.is_ok { ok = false; }
  if mixed.is_ok {
    let m_txt = mixed.value;
    if m_txt.len() != 4 { ok = false; }
    if !streq(m_txt, "AéB") { ok = false; }
  }
  return assert(ok, "json unescape: \\u2713 and \\u00e9 encode to UTF-8");
}

fn t7() -> TestResult {
  let a = unescape_json_string("\\u12");
  let b = unescape_json_string("\\uZZZZ");
  let c = unescape_json_string("\\u123");
  var ok = err_eq(a, "escape: truncated unicode escape");
  if !err_eq(b, "escape: invalid unicode escape") { ok = false; }
  if !err_eq(c, "escape: truncated unicode escape") { ok = false; }
  return assert(ok, "json unescape: malformed \\u escapes are Err");
}

fn t8() -> TestResult {
  let trail = unescape_json_string("abc\\");
  let bad = unescape_json_string("\\q");
  let nul = unescape_json_string("\\u0000");
  let sur = unescape_json_string("\\ud800");
  var ok = err_eq(trail, "escape: trailing backslash");
  if !err_eq(bad, "escape: invalid escape sequence") { ok = false; }
  if !err_eq(nul, "escape: null escape not supported") { ok = false; }
  if !err_eq(sur, "escape: lone surrogate") { ok = false; }
  return assert(ok, "json unescape: trailing backslash, bad escape, NUL and surrogate");
}

fn t9() -> TestResult {
  let r = escape_html("<a href=\"x\">'&'</a>");
  var ok = streq(r, "&lt;a href=&quot;x&quot;&gt;&apos;&amp;&apos;&lt;/a&gt;");
  let clean = escape_html("plain text");
  if !streq(clean, "plain text") { ok = false; }
  return assert(ok, "html escape: all five entities");
}

fn t10() -> TestResult {
  let r = unescape_html("&amp; &lt; &gt; &quot; &apos;");
  var ok = streq(r, "& < > \" '");
  let once = unescape_html("&amp;lt;");
  if !streq(once, "&lt;") { ok = false; }
  return assert(ok, "html unescape: named entities decode in a single pass");
}

fn t11() -> TestResult {
  let dec = unescape_html("&#65;&#66;&#67;");
  var ok = streq(dec, "ABC");
  let hex = unescape_html("&#x41;&#X42;&#x2713;");
  if !streq(hex, "AB✓") { ok = false; }
  let big = unescape_html("&#128512;");
  if big.len() != 4 { ok = false; }
  return assert(ok, "html unescape: decimal and hex numeric references");
}

fn t12() -> TestResult {
  let s = "5 < 6 && 7 > 2, \"q\" and 'a'";
  let rt = unescape_html(escape_html(s));
  var ok = streq(rt, s);
  let u = "café & <ok>";
  if !streq(unescape_html(escape_html(u)), u) { ok = false; }
  return assert(ok, "html escape then unescape round-trips");
}

fn t13() -> TestResult {
  let at = unescape_html("AT&T");
  var ok = streq(at, "AT&T");
  let unknown = unescape_html("&nope; &#zz; &;");
  if !streq(unknown, "&nope; &#zz; &;") { ok = false; }
  let malformed = unescape_html("&#x; &#; &#xZZ;");
  if !streq(malformed, "&#x; &#; &#xZZ;") { ok = false; }
  return assert(ok, "html unescape: unknown and malformed references stay verbatim");
}

fn t14() -> TestResult {
  let r = escape_url_component("a b/c?d=e&f");
  var ok = streq(r, "a%20b%2Fc%3Fd%3De%26f");
  let reserved = escape_url_component("#[]@!$&'()*+,;=:");
  if !streq(reserved, "%23%5B%5D%40%21%24%26%27%28%29%2A%2B%2C%3B%3D%3A") { ok = false; }
  return assert(ok, "url encode: reserved characters and space");
}

fn t15() -> TestResult {
  let passthru = escape_url_component("Az09-_.~");
  var ok = streq(passthru, "Az09-_.~");
  let u = escape_url_component("é");
  if !streq(u, "%C3%A9") { ok = false; }
  let check = escape_url_component("✓");
  if !streq(check, "%E2%9C%93") { ok = false; }
  return assert(ok, "url encode: unreserved pass through, non-ASCII per UTF-8 byte");
}

fn t16() -> TestResult {
  let s = "one two/three?four=five&six%seven";
  let r = unescape_url_component(escape_url_component(s));
  var ok = r.is_ok;
  if ok && !streq(r.value, s) { ok = false; }
  let lo = unescape_url_component("a%2fb");
  if !lo.is_ok { ok = false; }
  if lo.is_ok && !streq(lo.value, "a/b") { ok = false; }
  let plus = unescape_url_component("a+b");
  if !plus.is_ok { ok = false; }
  if plus.is_ok && !streq(plus.value, "a+b") { ok = false; }
  return assert(ok, "url round trip; lowercase hex; + stays literal");
}

fn t17() -> TestResult {
  let one = unescape_url_component("%2");
  let tail = unescape_url_component("abc%");
  let bad = unescape_url_component("%GG");
  let mixed = unescape_url_component("abc%2G");
  var ok = err_eq(one, "escape: truncated percent escape");
  if !err_eq(tail, "escape: truncated percent escape") { ok = false; }
  if !err_eq(bad, "escape: invalid percent escape") { ok = false; }
  if !err_eq(mixed, "escape: invalid percent escape") { ok = false; }
  return assert(ok, "url decode: truncated and invalid percent escapes are Err");
}

fn t18() -> TestResult {
  let r = escape_shell_double("a\"b$c`d\\e");
  var ok = streq(r, "a\\\"b\\$c\\`d\\\\e");
  let plain = escape_shell_double("plain text-123!");
  if !streq(plain, "plain text-123!") { ok = false; }
  return assert(ok, "shell double-quote escaping: backslash, quote, dollar, backtick");
}

fn t19() -> TestResult {
  var v = Vec[UInt8].new();
  var i = 1;
  while i < 32 {
    v.push(i as UInt8);
    i = i + 1;
  }
  let raw = Str::from_utf8(v);
  let esc = escape_json_string(raw);
  let rt = unescape_json_string(esc);
  var ok = rt.is_ok;
  if ok {
    let txt = rt.value;
    if txt.len() != 31 { ok = false; }
    if !streq(txt, raw) { ok = false; }
  }
  if !string.str_contains(esc, "\\u0001") { ok = false; }
  if !string.str_contains(esc, "\\u001F") { ok = false; }
  return assert(ok, "json round trip: control bytes 0x01..0x1F become \\u00XX");
}

fn t20() -> TestResult {
  let r = escape_json_string("a/b");
  var ok = streq(r, "a/b");
  let u = escape_json_string("café ✓");
  if !streq(u, "café ✓") { ok = false; }
  let rt = unescape_json_string(u);
  if !rt.is_ok { ok = false; }
  if rt.is_ok && !streq(rt.value, "café ✓") { ok = false; }
  return assert(ok, "json escape: slash and non-ASCII pass through byte-exact");
}

fn main() -> Int {
  io.println("=== xiom.escape conformance tests ===");
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
    io.println("xiom.escape: all tests passed");
  } else {
    io.println("xiom.escape: tests failed");
  }
  return failed;
}
