// XIOM -- xiom.markdown conformance tests (27 checks)
// Port task: prove the pure-XIOM xiom.markdown module against its documented subset.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Covers the documented API: every heading level, paragraph joining and
// splitting, inline bold/italic/code/link rendering, list and blockquote
// blocks, thematic breaks, fenced code with and without a language tag,
// escaping of text, code content and link URLs, empty input, a mixed
// document, and the documented no-nesting emphasis behavior.
//
// All Str equality goes through str_compare: BUG 17 lowers `==` on Str values
// read from Vec[Str] elements to a pointer comparison, so every output check
// below is routed through the streq helper.

module markdown_tests
use xiom.io; use xiom.test;
use xiom.markdown;
use xiom.string.compare;

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// --------------------------------------------------
//  Heading levels
// --------------------------------------------------

fn t1() -> TestResult {
  let got = markdown_to_html("# Title");
  return assert(streq(got, "<h1>Title</h1>"), "h1 heading");
}

fn t2() -> TestResult {
  let got = markdown_to_html("## Sub");
  return assert(streq(got, "<h2>Sub</h2>"), "h2 heading");
}

fn t3() -> TestResult {
  let got = markdown_to_html("### Three");
  return assert(streq(got, "<h3>Three</h3>"), "h3 heading");
}

fn t4() -> TestResult {
  let got = markdown_to_html("#### Four");
  return assert(streq(got, "<h4>Four</h4>"), "h4 heading");
}

fn t5() -> TestResult {
  let got = markdown_to_html("##### Five");
  return assert(streq(got, "<h5>Five</h5>"), "h5 heading");
}

fn t6() -> TestResult {
  let got = markdown_to_html("###### Six");
  return assert(streq(got, "<h6>Six</h6>"), "h6 heading");
}

fn t7() -> TestResult {
  let seven = markdown_to_html("####### Seven");
  var ok = streq(seven, "<p>####### Seven</p>");
  let nospace = markdown_to_html("#NoSpace");
  if !streq(nospace, "<p>#NoSpace</p>") { ok = false; }
  let bare = markdown_to_html("##");
  if !streq(bare, "<h2></h2>") { ok = false; }
  return assert(ok, "7+ hashes and '#' without a space are paragraphs; bare hashes are an empty heading");
}

// --------------------------------------------------
//  Paragraphs
// --------------------------------------------------

fn t8() -> TestResult {
  let got = markdown_to_html("Hello world");
  return assert(streq(got, "<p>Hello world</p>"), "plain single-line paragraph");
}

fn t9() -> TestResult {
  let joined = markdown_to_html("line one\nline two");
  var ok = streq(joined, "<p>line one line two</p>");
  let split = markdown_to_html("first\n\nsecond");
  if !streq(split, "<p>first</p>\n<p>second</p>") { ok = false; }
  return assert(ok, "paragraph lines join with a space and blank lines split blocks");
}

// --------------------------------------------------
//  Inline markup
// --------------------------------------------------

fn t10() -> TestResult {
  let got = markdown_to_html("**bold** text");
  var ok = streq(got, "<p><strong>bold</strong> text</p>");
  let two = markdown_to_html("**a** and **b**");
  if !streq(two, "<p><strong>a</strong> and <strong>b</strong></p>") { ok = false; }
  return assert(ok, "**bold** renders strong");
}

fn t11() -> TestResult {
  let got = markdown_to_html("*italic* text");
  var ok = streq(got, "<p><em>italic</em> text</p>");
  let mid = markdown_to_html("a *b* c");
  if !streq(mid, "<p>a <em>b</em> c</p>") { ok = false; }
  return assert(ok, "*italic* renders em");
}

fn t12() -> TestResult {
  let got = markdown_to_html("use `x + y` here");
  return assert(streq(got, "<p>use <code>x + y</code> here</p>"), "`code` renders code");
}

fn t13() -> TestResult {
  let code = markdown_to_html("use `a < b & c` now");
  var ok = streq(code, "<p>use <code>a &lt; b &amp; c</code> now</p>");
  let plain = markdown_to_html("1 < 2 & \"q\"");
  if !streq(plain, "<p>1 &lt; 2 &amp; &quot;q&quot;</p>") { ok = false; }
  return assert(ok, "inline code content and plain text are HTML-escaped");
}

fn t14() -> TestResult {
  let got = markdown_to_html("[A & B](x?a=1&b=2)");
  var ok = streq(got, "<p><a href=\"x?a=1&amp;b=2\">A &amp; B</a></p>");
  let quoted = markdown_to_html("[q](\"x\")");
  if !streq(quoted, "<p><a href=\"&quot;x&quot;\">q</a></p>") { ok = false; }
  let inner = markdown_to_html("[**hi**](u)");
  if !streq(inner, "<p><a href=\"u\"><strong>hi</strong></a></p>") { ok = false; }
  return assert(ok, "links escape the URL attribute and parse link text inline");
}

// --------------------------------------------------
//  Lists
// --------------------------------------------------

fn t15() -> TestResult {
  let dash = markdown_to_html("- a\n- b");
  var ok = streq(dash, "<ul>\n<li>a</li>\n<li>b</li>\n</ul>");
  let star = markdown_to_html("* x\n* y");
  if !streq(star, "<ul>\n<li>x</li>\n<li>y</li>\n</ul>") { ok = false; }
  let after = markdown_to_html("- a\ntext");
  if !streq(after, "<ul>\n<li>a</li>\n</ul>\n<p>text</p>") { ok = false; }
  return assert(ok, "bullet lists render as ul with one li per item");
}

fn t16() -> TestResult {
  let got = markdown_to_html("1. one\n2. two\n10. ten");
  var ok = streq(got, "<ol>\n<li>one</li>\n<li>two</li>\n<li>ten</li>\n</ol>");
  let start = markdown_to_html("7. seven");
  if !streq(start, "<ol>\n<li>seven</li>\n</ol>") { ok = false; }
  return assert(ok, "ordered lists accept any digit count and ignore the start number");
}

fn t24() -> TestResult {
  let ul = markdown_to_html("- **a** and `b`");
  var ok = streq(ul, "<ul>\n<li><strong>a</strong> and <code>b</code></li>\n</ul>");
  let ol = markdown_to_html("1. [x](u) plus *i*");
  if !streq(ol, "<ol>\n<li><a href=\"u\">x</a> plus <em>i</em></li>\n</ol>") { ok = false; }
  return assert(ok, "list items render inline formatting");
}

// --------------------------------------------------
//  Blockquotes, hr, fenced code
// --------------------------------------------------

fn t17() -> TestResult {
  let one = markdown_to_html("> quoted");
  var ok = streq(one, "<blockquote>\n<p>quoted</p>\n</blockquote>");
  let two = markdown_to_html("> line one\n> line two");
  if !streq(two, "<blockquote>\n<p>line one line two</p>\n</blockquote>") { ok = false; }
  let list = markdown_to_html("> - a\n> - b");
  if !streq(list, "<blockquote>\n<ul>\n<li>a</li>\n<li>b</li>\n</ul>\n</blockquote>") { ok = false; }
  return assert(ok, "blockquotes collect > lines and render inner blocks");
}

fn t18() -> TestResult {
  let dash = markdown_to_html("---");
  var ok = streq(dash, "<hr>");
  let star = markdown_to_html("***");
  if !streq(star, "<hr>") { ok = false; }
  let middle = markdown_to_html("a\n\n---\n\nb");
  if !streq(middle, "<p>a</p>\n<hr>\n<p>b</p>") { ok = false; }
  return assert(ok, "--- and *** alone render as hr");
}

fn t19() -> TestResult {
  let got = markdown_to_html("```rust\nfn main() {}\n```");
  return assert(streq(got, "<pre><code class=\"language-rust\">fn main() {}</code></pre>"), "fenced code with a language tag");
}

fn t20() -> TestResult {
  let esc = markdown_to_html("```\na < b & c\n```");
  var ok = streq(esc, "<pre><code>a &lt; b &amp; c</code></pre>");
  let multi = markdown_to_html("```\nl1\nl2\n```");
  if !streq(multi, "<pre><code>l1\nl2</code></pre>") { ok = false; }
  let unclosed = markdown_to_html("```\nx");
  if !streq(unclosed, "<pre><code>x</code></pre>") { ok = false; }
  return assert(ok, "fenced code escapes content, keeps line breaks and closes leniently at EOF");
}

// --------------------------------------------------
//  Escaping, empty input, mixed document
// --------------------------------------------------

fn t21() -> TestResult {
  let got = markdown_escape("a & b < c > d \"e\"");
  var ok = streq(got, "a &amp; b &lt; c &gt; d &quot;e&quot;");
  let empty = markdown_escape("");
  if !streq(empty, "") { ok = false; }
  let plain = markdown_escape("plain text 123");
  if !streq(plain, "plain text 123") { ok = false; }
  return assert(ok, "markdown_escape escapes & < > \" and passes plain text through");
}

fn t22() -> TestResult {
  let got = markdown_to_html("# Title\n\nIntro **bold** and `code`.\n\n- one\n- two\n\n1. first\n2. second\n\n> quoted\n\n---\n\n```xi\nlet x = 1 < 2;\n```");
  let want = "<h1>Title</h1>\n<p>Intro <strong>bold</strong> and <code>code</code>.</p>\n<ul>\n<li>one</li>\n<li>two</li>\n</ul>\n<ol>\n<li>first</li>\n<li>second</li>\n</ol>\n<blockquote>\n<p>quoted</p>\n</blockquote>\n<hr>\n<pre><code class=\"language-xi\">let x = 1 &lt; 2;</code></pre>";
  return assert(streq(got, want), "mixed document renders every block type in order");
}

fn t23() -> TestResult {
  let empty = markdown_to_html("");
  var ok = streq(empty, "");
  let blanks = markdown_to_html("\n\n  \n");
  if !streq(blanks, "") { ok = false; }
  let spaces = markdown_to_html("   ");
  if !streq(spaces, "") { ok = false; }
  return assert(ok, "empty and whitespace-only input render nothing");
}

// --------------------------------------------------
//  Documented limits and separators
// --------------------------------------------------

fn t25() -> TestResult {
  let got = markdown_to_html("**bold *and italic* text**");
  return assert(streq(got, "<p><strong>bold *and italic* text</strong></p>"), "emphasis does not nest (inner markers stay literal)");
}

fn t26() -> TestResult {
  let inline = markdown_to_html("# A **b** `c`");
  var ok = streq(inline, "<h1>A <strong>b</strong> <code>c</code></h1>");
  let sep = markdown_to_html("# A\n\ntext");
  if !streq(sep, "<h1>A</h1>\n<p>text</p>") { ok = false; }
  return assert(ok, "headings render inline markup and blocks are LF-separated");
}

fn t27() -> TestResult {
  let got = markdown_to_html("# A\r\n\r\nb");
  return assert(streq(got, "<h1>A</h1>\n<p>b</p>"), "CRLF input parses like LF input");
}

fn main() -> Int {
  io.println("=== xiom.markdown conformance tests ===");
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
  let r27 = t27();
  if r27.passed { io.println("  [PASS] " + r27.name); } else { io.println("  [FAIL] " + r27.name); failed = failed + 1; }
  if failed == 0 {
    io.println("xiom.markdown: all tests passed");
  } else {
    io.println("xiom.markdown: tests failed");
  }
  return failed;
}
