// XIOM -- xiom.html conformance tests (22 checks)
// Port task: prove the pure-XIOM xiom.html sanitizer against its documented
// scanner rules, attribute policy and dropped-block rules.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Covers the documented API: the default allowlist (sorted, complete, the
// required 21 tags), tag allowlisting and case normalization, the href/title
// attribute policy (on* and every other attribute dropped, javascript: and
// data: hrefs dropped), script/style removal including their content, comment
// and declaration removal, entity and text preservation, stray '<' and
// unbalanced tags in tolerant mode, strip_tags, is_safe and empty input.
//
// All Str equality goes through str_compare: BUG 17 lowers `==` on Str values
// read from Vec[Str] elements to a pointer comparison, so every comparison
// below is routed through the streq helper instead of `==`.

module html_tests
use xiom.io; use xiom.test;
use xiom.html;
use xiom.string.compare;

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn has_tag(tags: &Vec[Str], want: Str) -> Bool {
  var i = 0;
  while i < tags.len() {
    if compare.str_compare(tags[i], want) == 0 {
      return true;
    }
    i = i + 1;
  }
  return false;
}

fn t1() -> TestResult {
  let def = html_default_allowed_tags();
  let clean = "<p>Hello <b>world</b></p>";
  let out = html_sanitize(clean, &def);
  var ok = streq(out, clean);
  let single = "<p>just a paragraph</p>";
  if !streq(html_sanitize(single, &def), single) { ok = false; }
  return assert(ok, "allowed p and b tags pass through unchanged");
}

fn t2() -> TestResult {
  let def = html_default_allowed_tags();
  var ok = streq(html_sanitize("<div>text</div>", &def), "text");
  if !streq(html_sanitize("<span>a</span>b", &def), "ab") { ok = false; }
  if !streq(html_sanitize("</div>", &def), "") { ok = false; }
  return assert(ok, "disallowed div stripped, its text content kept");
}

fn t3() -> TestResult {
  let def = html_default_allowed_tags();
  var ok = streq(html_sanitize("a<script>alert(\"x\")</script>b", &def), "ab");
  if !streq(html_sanitize("<p>a<script>x()</script>b</p>", &def), "<p>ab</p>") { ok = false; }
  var weird = Vec[Str].new();
  weird.push("script");
  if !streq(html_sanitize("a<script>x</script>b", &weird), "ab") { ok = false; }
  return assert(ok, "script blocks dropped including their content");
}

fn t4() -> TestResult {
  let def = html_default_allowed_tags();
  var ok = streq(html_sanitize("a<script>x", &def), "a");
  if !streq(html_sanitize("<script src=\"x.js\"></script>", &def), "") { ok = false; }
  return assert(ok, "unterminated script block dropped to EOF");
}

fn t5() -> TestResult {
  let def = html_default_allowed_tags();
  var ok = streq(html_sanitize("x<style>p { color: red; }</style>y", &def), "xy");
  if !streq(html_sanitize("<style>a{}</style>", &def), "") { ok = false; }
  return assert(ok, "style blocks dropped including their content");
}

fn t6() -> TestResult {
  let def = html_default_allowed_tags();
  var ok = streq(html_sanitize("<p onclick=\"evil()\">hi</p>", &def), "<p>hi</p>");
  if !streq(html_sanitize("<a href=\"/ok\" onmouseover=\"evil()\">x</a>", &def), "<a href=\"/ok\">x</a>") { ok = false; }
  return assert(ok, "all on* event handler attributes dropped");
}

fn t7() -> TestResult {
  let def = html_default_allowed_tags();
  var ok = streq(html_sanitize("<p class=\"c\" id=\"i\" style=\"color:red\">hi</p>", &def), "<p>hi</p>");
  if !streq(html_sanitize("<code data-x=\"1\" title=\"t\">z</code>", &def), "<code title=\"t\">z</code>") { ok = false; }
  return assert(ok, "attributes other than href and title dropped");
}

fn t8() -> TestResult {
  let def = html_default_allowed_tags();
  var ok = streq(html_sanitize("<a href=\"javascript:alert(1)\">x</a>", &def), "<a>x</a>");
  if !streq(html_sanitize("<a HREF=\"JaVaScRiPt:alert(1)\">x</a>", &def), "<a>x</a>") { ok = false; }
  if !streq(html_sanitize("<a href=\" javascript:alert(1)\">x</a>", &def), "<a>x</a>") { ok = false; }
  return assert(ok, "javascript: href values dropped");
}

fn t9() -> TestResult {
  let def = html_default_allowed_tags();
  var ok = streq(html_sanitize("<a href=\"data:text/plain,hi\">x</a>", &def), "<a>x</a>");
  if !streq(html_sanitize("<a href=\"DATA:TEXT/PLAIN,HI\">x</a>", &def), "<a>x</a>") { ok = false; }
  return assert(ok, "data: href values dropped");
}

fn t10() -> TestResult {
  let def = html_default_allowed_tags();
  let rel = "<a href=\"/about\">x</a>";
  var ok = streq(html_sanitize(rel, &def), rel);
  let query = "<a href=\"https://example.com/?a=1&amp;b=2\">x</a>";
  if !streq(html_sanitize(query, &def), query) { ok = false; }
  return assert(ok, "safe href kept with entities preserved verbatim");
}

fn t11() -> TestResult {
  let def = html_default_allowed_tags();
  let titled = "<p title=\"greeting\">hi</p>";
  var ok = streq(html_sanitize(titled, &def), titled);
  let js_title = "<p title=\"javascript:x\">t</p>";
  if !streq(html_sanitize(js_title, &def), js_title) { ok = false; }
  return assert(ok, "title kept; only href is scheme-checked");
}

fn t12() -> TestResult {
  let def = html_default_allowed_tags();
  var ok = streq(html_sanitize("<P>Hi</P>", &def), "<p>Hi</p>");
  if !streq(html_sanitize("<B>bold</B>", &def), "<b>bold</b>") { ok = false; }
  if !streq(html_sanitize("<A HREF=\"/x\">l</A>", &def), "<a href=\"/x\">l</a>") { ok = false; }
  return assert(ok, "uppercase tags and attribute names normalized");
}

fn t13() -> TestResult {
  let def = html_default_allowed_tags();
  var ok = streq(html_sanitize("a<!-- c -->b", &def), "ab");
  if !streq(html_sanitize("a<!-- <p>x</p> -->b", &def), "ab") { ok = false; }
  if !streq(html_sanitize("a<!--b", &def), "a") { ok = false; }
  if !streq(html_sanitize("<!DOCTYPE html><p>x</p>", &def), "<p>x</p>") { ok = false; }
  return assert(ok, "comments and declarations dropped");
}

fn t14() -> TestResult {
  let def = html_default_allowed_tags();
  var ok = streq(html_sanitize("a<br/>b", &def), "a<br/>b");
  if !streq(html_sanitize("a<br />b", &def), "a<br/>b") { ok = false; }
  if !streq(html_sanitize("<hr/>", &def), "<hr/>") { ok = false; }
  return assert(ok, "self-closing br and hr kept");
}

fn t15() -> TestResult {
  let def = html_default_allowed_tags();
  let nested = "<ul><li>one</li><li>two</li></ul>";
  var ok = streq(html_sanitize(nested, &def), nested);
  let quote = "<blockquote><p>q</p></blockquote>";
  if !streq(html_sanitize(quote, &def), quote) { ok = false; }
  return assert(ok, "nested allowed tags kept in place");
}

fn t16() -> TestResult {
  let def = html_default_allowed_tags();
  let ents = "a &amp; b &lt;tag&gt; &#65; &quot;q&quot;";
  var ok = streq(html_sanitize(ents, &def), ents);
  if !streq(html_sanitize("&amp;lt;", &def), "&amp;lt;") { ok = false; }
  return assert(ok, "text and entities preserved verbatim");
}

fn t17() -> TestResult {
  let def = html_default_allowed_tags();
  var ok = streq(html_sanitize("1 < 2", &def), "1 < 2");
  if !streq(html_sanitize("a <3 b", &def), "a <3 b") { ok = false; }
  if !streq(html_sanitize("x<p", &def), "x<p") { ok = false; }
  if !streq(html_sanitize("a <> b", &def), "a <> b") { ok = false; }
  return assert(ok, "stray '<' without a tag end passes through as text");
}

fn t18() -> TestResult {
  let def = html_default_allowed_tags();
  var ok = streq(html_sanitize("<b>bold", &def), "<b>bold");
  if !streq(html_sanitize("bold</b>", &def), "bold</b>") { ok = false; }
  if !streq(html_sanitize("<p><b>x</p>", &def), "<p><b>x</p>") { ok = false; }
  return assert(ok, "unbalanced tags pass through (no rebalancing)");
}

fn t19() -> TestResult {
  let def = html_default_allowed_tags();
  var ok = html_is_safe("<p>Hello</p>", &def);
  if html_is_safe("<p onclick=\"x\">ok</p>", &def) { ok = false; }
  if html_is_safe("a<script>x</script>b", &def) { ok = false; }
  if !html_is_safe("", &def) { ok = false; }
  let dirty = "<div onclick=\"e\">t</div><!--c-->";
  let once = html_sanitize(dirty, &def);
  let twice = html_sanitize(once, &def);
  if !streq(once, twice) { ok = false; }
  if !streq(once, "t") { ok = false; }
  return assert(ok, "is_safe true for clean input, false for dirty; sanitize idempotent");
}

fn t20() -> TestResult {
  var ok = streq(html_strip_tags("<p>Hello <b>world</b></p>"), "Hello world");
  if !streq(html_strip_tags("a<script>bad()</script>b<p>c</p>"), "abc") { ok = false; }
  if !streq(html_strip_tags("<b>&amp;</b>"), "&amp;") { ok = false; }
  if !streq(html_strip_tags("<ul><li>x</li></ul>"), "x") { ok = false; }
  return assert(ok, "strip_tags keeps text and entities, drops tags and script content");
}

fn t21() -> TestResult {
  let def = html_default_allowed_tags();
  var ok = streq(html_sanitize("", &def), "");
  if !streq(html_strip_tags(""), "") { ok = false; }
  if !html_is_safe("", &def) { ok = false; }
  if def.len() == 0 { ok = false; }
  return assert(ok, "empty input yields empty output");
}

fn t22() -> TestResult {
  let tags = html_default_allowed_tags();
  var expected = Vec[Str].new();
  expected.push("a");
  expected.push("b");
  expected.push("blockquote");
  expected.push("br");
  expected.push("code");
  expected.push("em");
  expected.push("h1");
  expected.push("h2");
  expected.push("h3");
  expected.push("h4");
  expected.push("h5");
  expected.push("h6");
  expected.push("hr");
  expected.push("i");
  expected.push("li");
  expected.push("ol");
  expected.push("p");
  expected.push("pre");
  expected.push("strong");
  expected.push("u");
  expected.push("ul");
  var ok = tags.len() == 21;
  if tags.len() == expected.len() {
    var i = 0;
    while i < tags.len() {
      if compare.str_compare(tags[i], expected[i]) != 0 { ok = false; }
      i = i + 1;
    }
  } else {
    ok = false;
  }
  var k = 0;
  while k + 1 < tags.len() {
    if compare.str_compare(tags[k], tags[k + 1]) > 0 { ok = false; }
    k = k + 1;
  }
  if has_tag(&tags, "div") { ok = false; }
  if has_tag(&tags, "script") { ok = false; }
  if has_tag(&tags, "style") { ok = false; }
  if has_tag(&tags, "img") { ok = false; }
  return assert(ok, "default allowlist is the 21 required tags, sorted");
}

fn main() -> Int {
  io.println("=== xiom.html conformance tests ===");
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
    io.println("xiom.html: all tests passed");
  } else {
    io.println("xiom.html: tests failed");
  }
  return failed;
}
