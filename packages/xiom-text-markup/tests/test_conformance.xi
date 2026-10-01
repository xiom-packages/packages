// XIOM -- xiom.text-markup conformance tests (26 checks)
// Port task: prove the pure-XIOM xiom.text_markup module against its SPEC.md:
// tag scanning, nesting validation, escapes/entities, span records, plain-text
// rendering, canonical re-serialization and the exact error catalog.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module text_markup_tests
use xiom.io; use xiom.test; use xiom.text_markup;
use xiom.string.compare;

// All Str equality goes through str_compare: BUG 17 lowers `==` on Str values
// read from Vec[Str] elements to a pointer comparison, so every rendered text
// and error message check below is routed through streq instead of `==`.

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// ---------------------------------------------------------------------------
// Result extractors
// ---------------------------------------------------------------------------

// Plain rendering of `src`, or "<err>" when it does not parse.
fn plain_of(src: Str) -> Str {
  let r = markup_parse(src);
  match r {
    Ok(m) => { return markup_to_plain(src, &m); },
    Err(_) => { return "<err>"; },
  }
  return "<err>";
}

// Canonical re-serialization of `src`, or "<err>" when it does not parse.
fn canon_of(src: Str) -> Str {
  let r = markup_parse(src);
  match r {
    Ok(m) => { return markup_to_canonical(src, &m); },
    Err(_) => { return "<err>"; },
  }
  return "<err>";
}

// Exact parse error of `src`, or "<ok>" when it parses.
fn err_of(src: Str) -> Str {
  let r = markup_parse(src);
  match r {
    Ok(_) => { return "<ok>"; },
    Err(e) => { return e; },
  }
  return "<ok>";
}

// ---------------------------------------------------------------------------
// Structural predicates
// ---------------------------------------------------------------------------

fn simple_span_ok() -> Bool {
  let src = "[b]bold[/b]";
  let r = markup_parse(src);
  match r {
    Ok(m) => {
      if markup_span_count(&m) != 1 { return false; }
      if markup_span_tag(&m, 0) != MARKUP_TAG_B { return false; }
      if markup_span_open_start(&m, 0) != 0 { return false; }
      if markup_span_open_end(&m, 0) != 3 { return false; }
      if markup_span_close_start(&m, 0) != 7 { return false; }
      if markup_span_close_end(&m, 0) != 11 { return false; }
      if !streq(markup_span_inner(src, &m, 0), "bold") { return false; }
      if !streq(markup_span_attr(src, &m, 0), "") { return false; }
      return true;
    },
    Err(_) => { return false; },
  }
  return false;
}

fn nested_bi_ok() -> Bool {
  let src = "[b]a[i]b[/i]c[/b]";
  let r = markup_parse(src);
  match r {
    Ok(m) => {
      if markup_span_count(&m) != 2 { return false; }
      if markup_span_tag(&m, 0) != MARKUP_TAG_B { return false; }
      if markup_span_tag(&m, 1) != MARKUP_TAG_I { return false; }
      if markup_span_open_start(&m, 0) != 0 { return false; }
      if markup_span_open_end(&m, 0) != 3 { return false; }
      if markup_span_close_start(&m, 0) != 13 { return false; }
      if markup_span_close_end(&m, 0) != 17 { return false; }
      if markup_span_open_start(&m, 1) != 4 { return false; }
      if markup_span_open_end(&m, 1) != 7 { return false; }
      if markup_span_close_start(&m, 1) != 8 { return false; }
      if markup_span_close_end(&m, 1) != 12 { return false; }
      return true;
    },
    Err(_) => { return false; },
  }
  return false;
}

fn nested_ub_ok() -> Bool {
  let src = "[u][b]x[/b][/u]";
  let r = markup_parse(src);
  match r {
    Ok(m) => {
      if markup_span_count(&m) != 2 { return false; }
      if markup_span_tag(&m, 0) != MARKUP_TAG_U { return false; }
      if markup_span_tag(&m, 1) != MARKUP_TAG_B { return false; }
      if markup_span_open_start(&m, 0) != 0 { return false; }
      if markup_span_close_start(&m, 0) != 11 { return false; }
      if markup_span_close_end(&m, 0) != 15 { return false; }
      if markup_span_open_start(&m, 1) != 3 { return false; }
      if markup_span_close_start(&m, 1) != 7 { return false; }
      if markup_span_close_end(&m, 1) != 11 { return false; }
      if !streq(markup_span_inner(src, &m, 1), "x") { return false; }
      return true;
    },
    Err(_) => { return false; },
  }
  return false;
}

fn code_span_ok() -> Bool {
  let src = "[code]a[0] &amp; b[/code]";
  let r = markup_parse(src);
  match r {
    Ok(m) => {
      if markup_span_count(&m) != 1 { return false; }
      if markup_span_tag(&m, 0) != MARKUP_TAG_CODE { return false; }
      if markup_span_open_start(&m, 0) != 0 { return false; }
      if markup_span_open_end(&m, 0) != 6 { return false; }
      if markup_span_close_start(&m, 0) != 18 { return false; }
      if markup_span_close_end(&m, 0) != 25 { return false; }
      if !streq(markup_span_inner(src, &m, 0), "a[0] &amp; b") { return false; }
      if !streq(markup_span_attr(src, &m, 0), "") { return false; }
      return true;
    },
    Err(_) => { return false; },
  }
  return false;
}

fn url_spans_ok() -> Bool {
  let s1 = "[url=https://x.io]click[/url]";
  let r1 = markup_parse(s1);
  match r1 {
    Ok(m1) => {
      if markup_span_count(&m1) != 1 { return false; }
      if markup_span_tag(&m1, 0) != MARKUP_TAG_URL { return false; }
      if markup_span_open_start(&m1, 0) != 0 { return false; }
      if markup_span_open_end(&m1, 0) != 18 { return false; }
      if markup_span_close_start(&m1, 0) != 23 { return false; }
      if markup_span_close_end(&m1, 0) != 29 { return false; }
      if !streq(markup_span_attr(s1, &m1, 0), "https://x.io") { return false; }
      if !streq(markup_span_inner(s1, &m1, 0), "click") { return false; }
    },
    Err(_) => { return false; },
  }
  let s2 = "[url]https://x.io[/url]";
  let r2 = markup_parse(s2);
  match r2 {
    Ok(m2) => {
      if markup_span_count(&m2) != 1 { return false; }
      if markup_span_tag(&m2, 0) != MARKUP_TAG_URL { return false; }
      if markup_span_open_end(&m2, 0) != 5 { return false; }
      if markup_span_close_start(&m2, 0) != 17 { return false; }
      if markup_span_close_end(&m2, 0) != 23 { return false; }
      if !streq(markup_span_attr(s2, &m2, 0), "") { return false; }
      if !streq(markup_span_inner(s2, &m2, 0), "https://x.io") { return false; }
    },
    Err(_) => { return false; },
  }
  return true;
}

fn accessors_ok() -> Bool {
  let src = "[b]x[/b]";
  let r = markup_parse(src);
  match r {
    Ok(m) => {
      if markup_span_count(&m) != 1 { return false; }
      if markup_span_tag(&m, 1) != MARKUP_TAG_NONE { return false; }
      if markup_span_tag(&m, -1) != MARKUP_TAG_NONE { return false; }
      if markup_span_open_start(&m, 1) != -1 { return false; }
      if markup_span_open_end(&m, -2) != -1 { return false; }
      if markup_span_close_start(&m, 9) != -1 { return false; }
      if markup_span_close_end(&m, 9) != -1 { return false; }
      if !streq(markup_span_attr(src, &m, 1), "") { return false; }
      if !streq(markup_span_inner(src, &m, 1), "") { return false; }
      if !streq(markup_span_inner(src, &m, -1), "") { return false; }
      return true;
    },
    Err(_) => { return false; },
  }
  return false;
}

fn multi_span_ok() -> Bool {
  let src = "[b]one[/b] [url=u]two[/url]";
  let r = markup_parse(src);
  match r {
    Ok(m) => {
      if markup_span_count(&m) != 2 { return false; }
      if markup_span_tag(&m, 0) != MARKUP_TAG_B { return false; }
      if markup_span_tag(&m, 1) != MARKUP_TAG_URL { return false; }
      if markup_span_open_start(&m, 0) != 0 { return false; }
      if markup_span_open_end(&m, 0) != 3 { return false; }
      if markup_span_close_start(&m, 0) != 6 { return false; }
      if markup_span_close_end(&m, 0) != 10 { return false; }
      if markup_span_open_start(&m, 1) != 11 { return false; }
      if markup_span_open_end(&m, 1) != 18 { return false; }
      if markup_span_close_start(&m, 1) != 21 { return false; }
      if markup_span_close_end(&m, 1) != 27 { return false; }
      if !streq(markup_span_inner(src, &m, 0), "one") { return false; }
      if !streq(markup_span_inner(src, &m, 1), "two") { return false; }
      if !streq(markup_span_attr(src, &m, 1), "u") { return false; }
      return true;
    },
    Err(_) => { return false; },
  }
  return false;
}

fn siblings_ok() -> Bool {
  let src = "[b]a[/b][i]b[/i][u]c[/u]";
  let r = markup_parse(src);
  match r {
    Ok(m) => {
      if markup_span_count(&m) != 3 { return false; }
      if markup_span_tag(&m, 0) != MARKUP_TAG_B { return false; }
      if markup_span_tag(&m, 1) != MARKUP_TAG_I { return false; }
      if markup_span_tag(&m, 2) != MARKUP_TAG_U { return false; }
      if markup_span_open_start(&m, 0) != 0 { return false; }
      if markup_span_close_start(&m, 0) != 4 { return false; }
      if markup_span_open_start(&m, 1) != 8 { return false; }
      if markup_span_close_start(&m, 1) != 12 { return false; }
      if markup_span_open_start(&m, 2) != 16 { return false; }
      if markup_span_close_start(&m, 2) != 20 { return false; }
      if markup_span_close_end(&m, 2) != 24 { return false; }
      return true;
    },
    Err(_) => { return false; },
  }
  return false;
}

fn roundtrip_ok() -> Bool {
  let src = "[b]a[/b][i]b\\[c\\][/i] [url=https://x.io]d[/url]";
  if !streq(canon_of(src), src) { return false; }
  if !streq(canon_of(canon_of(src)), canon_of(src)) { return false; }
  if !streq(plain_of(src), "ab[c] d") { return false; }
  let r = markup_parse(canon_of(src));
  match r {
    Ok(m) => {
      if markup_span_count(&m) != 3 { return false; }
      if markup_span_tag(&m, 0) != MARKUP_TAG_B { return false; }
      if markup_span_tag(&m, 1) != MARKUP_TAG_I { return false; }
      if markup_span_tag(&m, 2) != MARKUP_TAG_URL { return false; }
    },
    Err(_) => { return false; },
  }
  let e = "a &amp; b";
  let ce = canon_of(e);
  if !streq(ce, "a & b") { return false; }
  if !streq(canon_of(ce), ce) { return false; }
  if !streq(plain_of(ce), plain_of(e)) { return false; }
  return true;
}

fn determinism_ok() -> Bool {
  let src = "[u][b]x[/b][/u] [code]a[0][/code]";
  let r1 = markup_parse(src);
  let r2 = markup_parse(src);
  if !r1.is_ok { return false; }
  if !r2.is_ok { return false; }
  let m1: Markup = r1.value;
  let m2: Markup = r2.value;
  if markup_span_count(&m1) != markup_span_count(&m2) { return false; }
  var i = 0;
  while i < markup_span_count(&m1) {
    if markup_span_tag(&m1, i) != markup_span_tag(&m2, i) { return false; }
    if markup_span_open_start(&m1, i) != markup_span_open_start(&m2, i) { return false; }
    if markup_span_open_end(&m1, i) != markup_span_open_end(&m2, i) { return false; }
    if markup_span_close_start(&m1, i) != markup_span_close_start(&m2, i) { return false; }
    if markup_span_close_end(&m1, i) != markup_span_close_end(&m2, i) { return false; }
    if !streq(markup_span_attr(src, &m1, i), markup_span_attr(src, &m2, i)) { return false; }
    i = i + 1;
  }
  if !streq(plain_of(src), "x a[0]") { return false; }
  if !streq(canon_of(src), src) { return false; }
  return true;
}

fn is_valid_and_convenience_ok() -> Bool {
  if !markup_is_valid("[b]ok[/b]") { return false; }
  if markup_is_valid("[b]") { return false; }
  if markup_is_valid("[nope]") { return false; }
  let ok_plain = markup_plain("[b]x[/b]");
  if !ok_plain.is_ok { return false; }
  let vp: Str = ok_plain.value;
  if !streq(vp, "x") { return false; }
  let bad_plain = markup_plain("[b]");
  if bad_plain.is_ok { return false; }
  let ok_canon = markup_canonical("[b]x[/b]");
  if !ok_canon.is_ok { return false; }
  let vc: Str = ok_canon.value;
  if !streq(vc, "[b]x[/b]") { return false; }
  let ent = markup_plain("a &amp; b");
  if !ent.is_ok { return false; }
  let ve: Str = ent.value;
  if !streq(ve, "a & b") { return false; }
  return true;
}

fn names_and_codes_ok() -> Bool {
  if !streq(markup_tag_name(MARKUP_TAG_B), "b") { return false; }
  if !streq(markup_tag_name(MARKUP_TAG_I), "i") { return false; }
  if !streq(markup_tag_name(MARKUP_TAG_U), "u") { return false; }
  if !streq(markup_tag_name(MARKUP_TAG_CODE), "code") { return false; }
  if !streq(markup_tag_name(MARKUP_TAG_URL), "url") { return false; }
  if !streq(markup_tag_name(MARKUP_TAG_NONE), "none") { return false; }
  if !streq(markup_tag_name(42), "none") { return false; }
  if markup_tag_code("b") != MARKUP_TAG_B { return false; }
  if markup_tag_code("i") != MARKUP_TAG_I { return false; }
  if markup_tag_code("u") != MARKUP_TAG_U { return false; }
  if markup_tag_code("code") != MARKUP_TAG_CODE { return false; }
  if markup_tag_code("url") != MARKUP_TAG_URL { return false; }
  if markup_tag_code("x") != MARKUP_TAG_NONE { return false; }
  if markup_tag_code("") != MARKUP_TAG_NONE { return false; }
  if markup_tag_code("B") != MARKUP_TAG_NONE { return false; }
  return true;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

fn t1() -> TestResult {
  let src = "[b]bold[/b]";
  var ok = simple_span_ok();
  if !streq(plain_of(src), "bold") { ok = false; }
  if !streq(canon_of(src), "[b]bold[/b]") { ok = false; }
  return assert(ok, "simple tag: [b]bold[/b] spans, plain text and canonical form");
}

fn t2() -> TestResult {
  let src = "[b]a[i]b[/i]c[/b]";
  var ok = nested_bi_ok();
  if !streq(plain_of(src), "abc") { ok = false; }
  if !streq(canon_of(src), src) { ok = false; }
  return assert(ok, "nesting: [b][i] records in open order and stripped plain text");
}

fn t3() -> TestResult {
  let src = "[u][b]x[/b][/u]";
  var ok = nested_ub_ok();
  if !streq(plain_of(src), "x") { ok = false; }
  if !streq(canon_of(src), src) { ok = false; }
  return assert(ok, "nesting: [u] around [b], close spans inside the outer span");
}

fn t4() -> TestResult {
  let src = "[code]a[0] &amp; b[/code]";
  var ok = code_span_ok();
  if !streq(plain_of(src), "a[0] &amp; b") { ok = false; }
  if !streq(canon_of(src), src) { ok = false; }
  return assert(ok, "code: content is literal (entities not decoded, brackets kept)");
}

fn t5() -> TestResult {
  let src = "[code][b]x[/b][/code]";
  var ok = markup_is_valid(src);
  if !streq(plain_of(src), "[b]x[/b]") { ok = false; }
  if !streq(canon_of(src), src) { ok = false; }
  return assert(ok, "code: markup-looking bytes inside are not parsed as tags");
}

fn t6() -> TestResult {
  let src = "[url=https://x.io]click[/url]";
  var ok = url_spans_ok();
  if !streq(plain_of(src), "click") { ok = false; }
  if !streq(canon_of(src), src) { ok = false; }
  return assert(ok, "url attribute: [url=target] parses the raw attr span");
}

fn t7() -> TestResult {
  let src = "[url]https://x.io[/url]";
  var ok = url_spans_ok();
  if !streq(plain_of(src), "https://x.io") { ok = false; }
  if !streq(canon_of(src), src) { ok = false; }
  return assert(ok, "url without attribute: bare [url] round-trips without '='");
}

fn t8() -> TestResult {
  let src = "a \\[b\\] c \\\\ d";
  let escaped = "a [b] c \\ d";
  var ok = markup_is_valid(src);
  if !streq(plain_of(src), escaped) { ok = false; }
  if !streq(canon_of(src), src) { ok = false; }
  return assert(ok, "escapes: \\[ \\] \\\\ decode to [ ] \\ and re-serialize canonically");
}

fn t9() -> TestResult {
  let src = "a &amp; b &lt; c &gt; d &quot;e&quot;";
  let decoded = "a & b < c > d \"e\"";
  var ok = markup_is_valid(src);
  if !streq(plain_of(src), decoded) { ok = false; }
  if !streq(canon_of(src), decoded) { ok = false; }
  return assert(ok, "entities: four named entities decode; canonical keeps bare '& < > \"'");
}

fn t10() -> TestResult {
  let src = "a &foo; b & c";
  var ok = markup_is_valid(src);
  if !streq(plain_of(src), src) { ok = false; }
  if !streq(canon_of(src), src) { ok = false; }
  return assert(ok, "unknown entities and lone '&' pass through as literal text");
}

fn t11() -> TestResult {
  var ok = streq(err_of("[b]x"), "markup: unclosed tag 'b' at 0");
  if !streq(err_of("[b][i]x"), "markup: unclosed tag 'i' at 3") { ok = false; }
  if !streq(err_of("[code]abc"), "markup: unclosed tag 'code' at 0") { ok = false; }
  return assert(ok, "unclosed: innermost open tag reported at its own '[' position");
}

fn t12() -> TestResult {
  var ok = streq(err_of("[i][b]x[/i][/b]"), "markup: cross-nested tags 'b' and 'i' at 7");
  if !streq(err_of("[b][i][u]x[/i][/u][/b]"), "markup: cross-nested tags 'u' and 'i' at 10") { ok = false; }
  return assert(ok, "cross-nested: close skipping the innermost open reports both names");
}

fn t13() -> TestResult {
  var ok = streq(err_of("[/b]"), "markup: stray close tag 'b' at 0");
  if !streq(err_of("x[/i]"), "markup: stray close tag 'i' at 1") { ok = false; }
  if !streq(err_of("[url]x[/b]"), "markup: stray close tag 'b' at 6") { ok = false; }
  return assert(ok, "stray close: no matching open anywhere on the stack");
}

fn t14() -> TestResult {
  var ok = streq(err_of("[foo]x[/foo]"), "markup: unknown tag 'foo' at 0");
  if !streq(err_of("[B]x[/B]"), "markup: unknown tag 'B' at 0") { ok = false; }
  if !streq(err_of("[]x[]"), "markup: unknown tag '' at 0") { ok = false; }
  return assert(ok, "unknown tag: exact, case-sensitive name in the message");
}

fn t15() -> TestResult {
  var ok = streq(err_of("[b=x]x[/b]"), "markup: bad attribute for 'b' at 0");
  if !streq(err_of("[url=]x[/url]"), "markup: bad attribute for 'url' at 0") { ok = false; }
  if !streq(err_of("[code=x]x[/code]"), "markup: bad attribute for 'code' at 0") { ok = false; }
  return assert(ok, "bad attribute: attr on b/i/u/code and the empty url attr");
}

fn t16() -> TestResult {
  var ok = streq(err_of("[b"), "markup: unterminated tag at 0");
  if !streq(err_of("a [b=x"), "markup: unterminated tag at 2") { ok = false; }
  if !streq(err_of("[code"), "markup: unterminated tag at 0") { ok = false; }
  return assert(ok, "unterminated: '[' with no ']' before EOF, at the '[' position");
}

fn t17() -> TestResult {
  var ok = streq(err_of("a\\qb"), "markup: invalid escape at 1");
  if !streq(err_of("x \\"), "markup: invalid escape at 2") { ok = false; }
  if !streq(plain_of("x \\[ b"), "x [ b") { ok = false; }
  return assert(ok, "escapes: only \\[ \\] \\\\ are valid; positions are exact");
}

fn t18() -> TestResult {
  var ok = markup_is_valid("");
  if !streq(plain_of(""), "") { ok = false; }
  if !streq(canon_of(""), "") { ok = false; }
  if !streq(plain_of("plain text"), "plain text") { ok = false; }
  if !streq(canon_of("plain text"), "plain text") { ok = false; }
  return assert(ok, "empty and tag-free input: zero spans and identity rendering");
}

fn t19() -> TestResult {
  return assert(accessors_ok(), "accessors: out-of-range values are NONE/-1/\"\"");
}

fn t20() -> TestResult {
  let src = "[b]one[/b] [url=u]two[/url]";
  var ok = multi_span_ok();
  if !streq(plain_of(src), "one two") { ok = false; }
  if !streq(canon_of(src), src) { ok = false; }
  return assert(ok, "multiple spans: inner text and per-span attribute lookup");
}

fn t21() -> TestResult {
  return assert(roundtrip_ok(), "round-trip: canonical is idempotent and reparse-stable; entities normalize");
}

fn t22() -> TestResult {
  return assert(determinism_ok(), "determinism: repeated parses yield identical fields and renders");
}

fn t23() -> TestResult {
  return assert(is_valid_and_convenience_ok(), "markup_is_valid and markup_plain/markup_canonical convenience");
}

fn t24() -> TestResult {
  let src = "[b]a[/b][i]b[/i][u]c[/u]";
  var ok = siblings_ok();
  if !streq(plain_of(src), "abc") { ok = false; }
  if !streq(canon_of(src), src) { ok = false; }
  return assert(ok, "siblings: several closed spans in open order, closes ascending");
}

fn t25() -> TestResult {
  return assert(names_and_codes_ok(), "tag table: names and exact case-sensitive codes");
}

fn t26() -> TestResult {
  let src = "[url=a=b&c]x[/url]";
  let r = markup_parse(src);
  match r {
    Ok(m) => {
      if !streq(markup_span_attr(src, &m, 0), "a=b&c") { return assert(false, "url attr: first '=' splits name and raw value"); }
      if !streq(markup_span_inner(src, &m, 0), "x") { return assert(false, "url attr: first '=' splits name and raw value"); }
    },
    Err(_) => { return assert(false, "url attr: first '=' splits name and raw value"); },
  }
  var ok = streq(plain_of(src), "x");
  if !streq(canon_of(src), src) { ok = false; }
  return assert(ok, "url attr: first '=' splits name and raw value");
}

// ---------------------------------------------------------------------------

fn report(r: TestResult) -> Int {
  if r.passed {
    io.println("  [PASS] " + r.name);
    return 0;
  }
  io.println("  [FAIL] " + r.name);
  return 1;
}

fn main() -> Int {
  io.println("=== xiom.text-markup conformance tests ===");
  var failed: Int = 0;
  failed = failed + report(t1());
  failed = failed + report(t2());
  failed = failed + report(t3());
  failed = failed + report(t4());
  failed = failed + report(t5());
  failed = failed + report(t6());
  failed = failed + report(t7());
  failed = failed + report(t8());
  failed = failed + report(t9());
  failed = failed + report(t10());
  failed = failed + report(t11());
  failed = failed + report(t12());
  failed = failed + report(t13());
  failed = failed + report(t14());
  failed = failed + report(t15());
  failed = failed + report(t16());
  failed = failed + report(t17());
  failed = failed + report(t18());
  failed = failed + report(t19());
  failed = failed + report(t20());
  failed = failed + report(t21());
  failed = failed + report(t22());
  failed = failed + report(t23());
  failed = failed + report(t24());
  failed = failed + report(t25());
  failed = failed + report(t26());
  if failed == 0 {
    io.println("xiom.text-markup: all tests passed");
  } else {
    io.println("xiom.text-markup: tests failed");
  }
  return failed;
}
