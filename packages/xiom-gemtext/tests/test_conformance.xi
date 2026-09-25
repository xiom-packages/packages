// XIOM -- xiom.gemtext conformance tests (23 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Covers the documented API: every line kind, heading levels and boundaries,
// link url/label forms, the missing-url error, the URL-whitespace stance,
// quotes, list items, blank lines, CRLF normalization, control-byte rejection,
// preformatted blocks (alt text, raw content, spans, lenient EOF), the empty
// document, canonical emission with a single trailing newline, out-of-range
// accessors and idempotent canonicalization.
//
// All Str equality goes through str_compare: BUG 17 lowers `==` on Str values
// read from Vec[Str] elements to a pointer comparison, so every check below is
// routed through the streq helper.

module gemtext_tests
use xiom.io; use xiom.test;
use xiom.gemtext;
use xiom.string.compare;

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// --------------------------------------------------
//  Vec builders for expected kinds/texts
// --------------------------------------------------

fn w1(a: Str) -> Vec[Str] {
  var v = Vec[Str].new();
  v.push(a);
  return v;
}

fn w3(a: Str, b: Str, c: Str) -> Vec[Str] {
  var v = Vec[Str].new();
  v.push(a);
  v.push(b);
  v.push(c);
  return v;
}

fn w4(a: Str, b: Str, c: Str, d: Str) -> Vec[Str] {
  var v = Vec[Str].new();
  v.push(a);
  v.push(b);
  v.push(c);
  v.push(d);
  return v;
}

fn w5(a: Str, b: Str, c: Str, d: Str, e: Str) -> Vec[Str] {
  var v = Vec[Str].new();
  v.push(a);
  v.push(b);
  v.push(c);
  v.push(d);
  v.push(e);
  return v;
}

fn w6(a: Str, b: Str, c: Str, d: Str, e: Str, f: Str) -> Vec[Str] {
  var v = Vec[Str].new();
  v.push(a);
  v.push(b);
  v.push(c);
  v.push(d);
  v.push(e);
  v.push(f);
  return v;
}

fn w7(a: Str, b: Str, c: Str, d: Str, e: Str, f: Str, g: Str) -> Vec[Str] {
  var v = Vec[Str].new();
  v.push(a);
  v.push(b);
  v.push(c);
  v.push(d);
  v.push(e);
  v.push(f);
  v.push(g);
  return v;
}

// --------------------------------------------------
//  Parse helpers
// --------------------------------------------------

// True when `d` has exactly the wanted kinds and texts, one entry per line.
fn doc_fields(d: &GemtextDoc, want_kinds: &Vec[Str], want_texts: &Vec[Str]) -> Bool {
  if gemtext_line_count(d) != want_kinds.len() { return false; }
  if gemtext_line_count(d) != want_texts.len() { return false; }
  var i = 0;
  while i < want_kinds.len() {
    if !streq(gemtext_kind(d, i), want_kinds[i]) { return false; }
    if !streq(gemtext_text(d, i), want_texts[i]) { return false; }
    i = i + 1;
  }
  return true;
}

// True when parsing `text` yields exactly the wanted kinds and texts.
fn doc_is(text: Str, want_kinds: &Vec[Str], want_texts: &Vec[Str]) -> Bool {
  let r = gemtext_parse(text);
  match r {
    Ok(d) => { return doc_fields(&d, want_kinds, want_texts); },
    Err(_) => { return false; },
  }
  return false;
}

// True when parsing `text` fails with exactly the error `want`.
fn err_is(text: Str, want: Str) -> Bool {
  let r = gemtext_parse(text);
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

// True when parsing `text` succeeds and emits exactly `want`.
fn emit_is(text: Str, want: Str) -> Bool {
  let r = gemtext_parse(text);
  match r {
    Ok(d) => { return streq(gemtext_emit(&d), want); },
    Err(_) => { return false; },
  }
  return false;
}

// True when `text` canonicalizes to `want` and canonicalization is idempotent
// (emitting the emitted form returns the same bytes).
fn canon_is(text: Str, want: Str) -> Bool {
  let r = gemtext_parse(text);
  match r {
    Ok(d) => {
      let once = gemtext_emit(&d);
      if !streq(once, want) { return false; }
      let r2 = gemtext_parse(once);
      match r2 {
        Ok(d2) => { return streq(gemtext_emit(&d2), once); },
        Err(_) => { return false; },
      }
      return false;
    },
    Err(_) => { return false; },
  }
  return false;
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  let r = gemtext_parse("# Title\nSome text\n=> https://example.com Label text\n* item\n> quoted\n\n");
  match r {
    Ok(d) => {
      let wk = w6("heading", "text", "link", "list-item", "quote", "blank");
      let wt = w6("Title", "Some text", "", "item", "quoted", "");
      var ok = doc_fields(&d, &wk, &wt);
      if gemtext_line_count(&d) != 6 { ok = false; }
      if gemtext_heading_level(&d, 0) != 1 { ok = false; }
      if gemtext_heading_level(&d, 1) != 0 { ok = false; }
      if !streq(gemtext_link_url(&d, 2), "https://example.com") { ok = false; }
      if !streq(gemtext_link_label(&d, 2), "Label text") { ok = false; }
      if !streq(gemtext_link_url(&d, 0), "") { ok = false; }
      if !streq(gemtext_emit(&d), "# Title\nSome text\n=> https://example.com Label text\n* item\n> quoted\n\n") { ok = false; }
      return assert(ok, "mixed document: kinds, texts, urls, labels and order");
    },
    Err(_) => { return assert(false, "mixed document: parse failed"); },
  }
  return assert(false, "unreachable");
}

fn t2() -> TestResult {
  let r = gemtext_parse("# One\n## Two\n### Three\n");
  match r {
    Ok(d) => {
      var ok = gemtext_line_count(&d) == 3;
      if gemtext_heading_level(&d, 0) != 1 { ok = false; }
      if gemtext_heading_level(&d, 1) != 2 { ok = false; }
      if gemtext_heading_level(&d, 2) != 3 { ok = false; }
      if !streq(gemtext_text(&d, 0), "One") { ok = false; }
      if !streq(gemtext_kind(&d, 1), "heading") { ok = false; }
      if gemtext_heading_level(&d, 9) != 0 { ok = false; }
      if !streq(gemtext_emit(&d), "# One\n## Two\n### Three\n") { ok = false; }
      return assert(ok, "heading levels 1, 2 and 3");
    },
    Err(_) => { return assert(false, "heading levels: parse failed"); },
  }
  return assert(false, "unreachable");
}

fn t3() -> TestResult {
  let r = gemtext_parse("#### Four\n#NoSpace\n######## Eight\n###\n#\n");
  match r {
    Ok(d) => {
      let wk = w5("text", "text", "text", "heading", "heading");
      let wt = w5("#### Four", "#NoSpace", "######## Eight", "", "");
      var ok = doc_fields(&d, &wk, &wt);
      if gemtext_heading_level(&d, 3) != 3 { ok = false; }
      if gemtext_heading_level(&d, 4) != 1 { ok = false; }
      return assert(ok, "4+ hashes and '#' without a space are text; bare hashes are empty headings");
    },
    Err(_) => { return assert(false, "heading boundaries: parse failed"); },
  }
  return assert(false, "unreachable");
}

fn t4() -> TestResult {
  let wk = w1("heading");
  let wt = w1("spaced");
  var ok = doc_is("#   spaced   \n", &wk, &wt);
  if !emit_is("#   spaced   \n", "# spaced\n") { ok = false; }
  let tk = w1("text");
  let tt = w1("##\ttabbed");
  if !doc_is("##\ttabbed\n", &tk, &tt) { ok = false; }
  return assert(ok, "heading text is trimmed and only a literal space opens a heading");
}

fn t5() -> TestResult {
  let r = gemtext_parse("=> https://example.com/path?a=1 Label text\n");
  match r {
    Ok(d) => {
      var ok = gemtext_line_count(&d) == 1;
      if !streq(gemtext_kind(&d, 0), "link") { ok = false; }
      if !streq(gemtext_text(&d, 0), "") { ok = false; }
      if !streq(gemtext_link_url(&d, 0), "https://example.com/path?a=1") { ok = false; }
      if !streq(gemtext_link_label(&d, 0), "Label text") { ok = false; }
      if gemtext_heading_level(&d, 0) != 0 { ok = false; }
      if !streq(gemtext_emit(&d), "=> https://example.com/path?a=1 Label text\n") { ok = false; }
      return assert(ok, "link with label: url and label accessors, text is empty");
    },
    Err(_) => { return assert(false, "link with label: parse failed"); },
  }
  return assert(false, "unreachable");
}

fn t6() -> TestResult {
  let r = gemtext_parse("=>https://x\n");
  match r {
    Ok(d) => {
      var ok = streq(gemtext_link_url(&d, 0), "https://x");
      if !streq(gemtext_link_label(&d, 0), "") { ok = false; }
      if !streq(gemtext_emit(&d), "=> https://x\n") { ok = false; }
      return assert(ok, "link without label: url only, canonical '=> url'");
    },
    Err(_) => { return assert(false, "link without label: parse failed"); },
  }
  return assert(false, "unreachable");
}

fn t7() -> TestResult {
  var ok = err_is("=>", "gemtext: link with missing url at 0");
  if !err_is("=>   ", "gemtext: link with missing url at 0") { ok = false; }
  if !err_is("=>\t\n", "gemtext: link with missing url at 0") { ok = false; }
  if !err_is("a\n=>\n", "gemtext: link with missing url at 2") { ok = false; }
  return assert(ok, "link with missing url is an error at the line start");
}

fn t8() -> TestResult {
  var ok = emit_is("=> https://a b/c\n", "=> https://a b/c\n");
  let r = gemtext_parse("=> https://a  two words\n");
  match r {
    Ok(d) => {
      if !streq(gemtext_link_url(&d, 0), "https://a") { ok = false; }
      if !streq(gemtext_link_label(&d, 0), "two words") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let r2 = gemtext_parse("=>   https://x   \n");
  match r2 {
    Ok(d2) => {
      if !streq(gemtext_link_url(&d2, 0), "https://x") { ok = false; }
      if !streq(gemtext_link_label(&d2, 0), "") { ok = false; }
      if !streq(gemtext_emit(&d2), "=> https://x\n") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "url whitespace stance: whitespace ends the url, label keeps inner spaces");
}

fn t9() -> TestResult {
  let wk = w4("list-item", "list-item", "text", "text");
  let wt = w4("one", "", "** not", "*-");
  let r = gemtext_parse("* one\n*\n** not\n*-\n");
  match r {
    Ok(d) => {
      var ok = doc_fields(&d, &wk, &wt);
      if gemtext_heading_level(&d, 0) != 0 { ok = false; }
      if !streq(gemtext_emit(&d), "* one\n*\n** not\n*-\n") { ok = false; }
      return assert(ok, "list items: '* text', lone '*', '**' and '*-' are text");
    },
    Err(_) => { return assert(false, "list items: parse failed"); },
  }
  return assert(false, "unreachable");
}

fn t10() -> TestResult {
  let wk = w4("quote", "quote", "quote", "quote");
  let wt = w4("one", "", "no space", ">");
  let r = gemtext_parse("> one\n>\n>no space\n>>\n");
  match r {
    Ok(d) => {
      var ok = doc_fields(&d, &wk, &wt);
      if !streq(gemtext_emit(&d), "> one\n>\n> no space\n> >\n") { ok = false; }
      return assert(ok, "quotes: space optional, empty quote, '>' content");
    },
    Err(_) => { return assert(false, "quotes: parse failed"); },
  }
  return assert(false, "unreachable");
}

fn t11() -> TestResult {
  let r = gemtext_parse("   \n\t\n");
  var ok = false;
  match r {
    Ok(d) => {
      ok = gemtext_line_count(&d) == 2;
      if !streq(gemtext_kind(&d, 0), "blank") { ok = false; }
      if !streq(gemtext_text(&d, 1), "") { ok = false; }
      if !streq(gemtext_emit(&d), "\n\n") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  if !emit_is("a\n\nb\n", "a\n\nb\n") { ok = false; }
  return assert(ok, "blank lines: whitespace-only is blank and emits empty");
}

fn t12() -> TestResult {
  let r = gemtext_parse("");
  match r {
    Ok(d) => {
      var ok = gemtext_line_count(&d) == 0;
      if gemtext_preformatted_span_count(&d) != 0 { ok = false; }
      if !streq(gemtext_kind(&d, 0), "") { ok = false; }
      if !streq(gemtext_text(&d, -1), "") { ok = false; }
      if gemtext_heading_level(&d, 0) != 0 { ok = false; }
      if !streq(gemtext_link_url(&d, 0), "") { ok = false; }
      if !streq(gemtext_link_label(&d, 0), "") { ok = false; }
      if gemtext_preformatted_start(&d, 0) != -1 { ok = false; }
      if gemtext_preformatted_end(&d, 0) != -1 { ok = false; }
      if !streq(gemtext_emit(&d), "") { ok = false; }
      return assert(ok, "empty document: zero lines, empty emit, safe accessors");
    },
    Err(_) => { return assert(false, "empty document: parse failed"); },
  }
  return assert(false, "unreachable");
}

fn t13() -> TestResult {
  let wk = w3("heading", "blank", "text");
  let wt = w3("A", "", "b");
  var ok = doc_is("# A\r\n\r\nb\r\n", &wk, &wt);
  if !emit_is("# A\r\n\r\nb\r\n", "# A\n\nb\n") { ok = false; }
  if !emit_is("\r\n", "\n") { ok = false; }
  return assert(ok, "CRLF input parses like LF and emits LF");
}

fn t14() -> TestResult {
  let wk = w4("preformatted", "preformatted-text", "preformatted-text", "preformatted");
  let wt = w4("Python", "print('hi')", "x = 1", "");
  let r = gemtext_parse("``` Python\nprint('hi')\nx = 1\n```\n");
  match r {
    Ok(d) => {
      var ok = doc_fields(&d, &wk, &wt);
      if gemtext_preformatted_span_count(&d) != 1 { ok = false; }
      if gemtext_preformatted_start(&d, 0) != 0 { ok = false; }
      if gemtext_preformatted_end(&d, 0) != 4 { ok = false; }
      if !streq(gemtext_emit(&d), "``` Python\nprint('hi')\nx = 1\n```\n") { ok = false; }
      return assert(ok, "preformatted block: alt text and one span");
    },
    Err(_) => { return assert(false, "preformatted block: parse failed"); },
  }
  return assert(false, "unreachable");
}

fn t15() -> TestResult {
  let wk = w7("preformatted", "preformatted-text", "preformatted-text", "preformatted-text", "preformatted-text", "preformatted-text", "preformatted");
  let wt = w7("", "=> https://x", "# heading?", "* item?", "   ", "> quote?", "");
  let src = "```\n=> https://x\n# heading?\n* item?\n   \n> quote?\n```\n";
  let r = gemtext_parse(src);
  match r {
    Ok(d) => {
      var ok = doc_fields(&d, &wk, &wt);
      if !streq(gemtext_link_url(&d, 1), "") { ok = false; }
      if gemtext_heading_level(&d, 2) != 0 { ok = false; }
      if !streq(gemtext_kind(&d, 4), "preformatted-text") { ok = false; }
      if gemtext_preformatted_span_count(&d) != 1 { ok = false; }
      if gemtext_preformatted_start(&d, 0) != 0 { ok = false; }
      if gemtext_preformatted_end(&d, 0) != 7 { ok = false; }
      if !streq(gemtext_emit(&d), src) { ok = false; }
      return assert(ok, "preformatted content is raw, even when it looks like markup");
    },
    Err(_) => { return assert(false, "preformatted raw: parse failed"); },
  }
  return assert(false, "unreachable");
}

fn t16() -> TestResult {
  var ok = emit_is("```\n```\n", "```\n```\n");
  let r = gemtext_parse("```\n```\n");
  match r {
    Ok(d) => {
      if gemtext_preformatted_span_count(&d) != 1 { ok = false; }
      if gemtext_preformatted_start(&d, 0) != 0 { ok = false; }
      if gemtext_preformatted_end(&d, 0) != 2 { ok = false; }
      if gemtext_line_count(&d) != 2 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let r2 = gemtext_parse("```\ncode\n");
  match r2 {
    Ok(d2) => {
      if gemtext_preformatted_span_count(&d2) != 1 { ok = false; }
      if gemtext_preformatted_end(&d2, 0) != 2 { ok = false; }
      if !streq(gemtext_emit(&d2), "```\ncode\n") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  if !emit_is("```", "```\n") { ok = false; }
  return assert(ok, "empty block, unclosed block (lenient EOF) and trailing newline");
}

fn t17() -> TestResult {
  var ok = emit_is("```  alt text  \n```\n", "``` alt text\n```\n");
  let r = gemtext_parse("```  alt text  \n```\n");
  match r {
    Ok(d) => {
      if !streq(gemtext_text(&d, 0), "alt text") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let r2 = gemtext_parse("````\n```\n");
  match r2 {
    Ok(d2) => {
      if !streq(gemtext_text(&d2, 0), "`") { ok = false; }
      if !streq(gemtext_emit(&d2), "``` `\n```\n") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  if !emit_is("``` Python extra words\n```\n", "``` Python extra words\n```\n") { ok = false; }
  return assert(ok, "alt text is trimmed; extra backticks and spaces become alt text");
}

fn t18() -> TestResult {
  var ok = emit_is("# A", "# A\n");
  if !emit_is("", "") { ok = false; }
  if !emit_is("\n\n", "\n\n") { ok = false; }
  if !emit_is("a\nb", "a\nb\n") { ok = false; }
  if !emit_is("a\nb\n", "a\nb\n") { ok = false; }
  return assert(ok, "canonical emitter: single trailing newline, empty document stays empty");
}

fn t19() -> TestResult {
  var ok = err_is("\x01", "gemtext: control byte 1 at 0");
  if !err_is("ab\x02c", "gemtext: control byte 2 at 2") { ok = false; }
  if !err_is("a\x7Fb", "gemtext: control byte 127 at 1") { ok = false; }
  if !err_is("a\rb", "gemtext: control byte 13 at 1") { ok = false; }
  if !err_is("a\x1Fb", "gemtext: control byte 31 at 1") { ok = false; }
  return assert(ok, "control bytes are rejected with their offset");
}

fn t20() -> TestResult {
  let wk = w1("text");
  let wt = w1("a\tb");
  var ok = doc_is("a\tb\n", &wk, &wt);
  if !err_is("```\n\x01\n```\n", "gemtext: control byte 1 at 4") { ok = false; }
  if !err_is("```\n\x7F\n```\n", "gemtext: control byte 127 at 4") { ok = false; }
  if !err_is("a\r", "gemtext: control byte 13 at 1") { ok = false; }
  return assert(ok, "tab is allowed; controls are rejected inside preformatted blocks too");
}

fn t21() -> TestResult {
  let want = "#### Four\n# Title\n=> url\n> no space\n\ntext   \n";
  return assert(canon_is("#### Four\n#   Title   \n=>url\n>no space\n   \ntext   \n", want), "canonicalization is idempotent, text lines stay verbatim");
}

fn t22() -> TestResult {
  let r = gemtext_parse("```\n```\n");
  match r {
    Ok(d) => {
      var ok = gemtext_preformatted_span_count(&d) == 1;
      if gemtext_preformatted_start(&d, 0) != 0 { ok = false; }
      if gemtext_preformatted_end(&d, 0) != 2 { ok = false; }
      if gemtext_preformatted_start(&d, 1) != -1 { ok = false; }
      if gemtext_preformatted_end(&d, -1) != -1 { ok = false; }
      if gemtext_preformatted_start(&d, 99) != -1 { ok = false; }
      return assert(ok, "preformatted span accessors: pairs and out-of-range -1");
    },
    Err(_) => { return assert(false, "span accessors: parse failed"); },
  }
  return assert(false, "unreachable");
}

fn t23() -> TestResult {
  let src = "caf\u{e9} \u{2713}\n> r\u{e9}sum\u{e9}\n";
  let r = gemtext_parse(src);
  match r {
    Ok(d) => {
      var ok = gemtext_line_count(&d) == 2;
      if !streq(gemtext_kind(&d, 0), "text") { ok = false; }
      if !streq(gemtext_text(&d, 0), "caf\u{e9} \u{2713}") { ok = false; }
      if !streq(gemtext_text(&d, 1), "r\u{e9}sum\u{e9}") { ok = false; }
      if !streq(gemtext_emit(&d), src) { ok = false; }
      return assert(ok, "non-ASCII UTF-8 text passes through byte-exact");
    },
    Err(_) => { return assert(false, "non-ASCII text: parse failed"); },
  }
  return assert(false, "unreachable");
}

fn main() -> Int {
  io.println("=== xiom.gemtext conformance tests ===");
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
  if failed == 0 {
    io.println("xiom.gemtext: all tests passed");
  } else {
    io.println("xiom.gemtext: tests failed");
  }
  return failed;
}
