// XIOM -- xiom.lexer-fw conformance tests (28 checks)
// Port task: prove the pure-XIOM xiom.lexer module against its SPEC.md:
// scan state, byte matchers, keyword table, token stream and exact errors.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module lexer_tests
use xiom.io; use xiom.test; use xiom.lexer;
use xiom.string.compare; use xiom.convert;

// All Str equality goes through str_compare: BUG 17 lowers `==` on Str values
// read from Vec[Str] elements to a pointer comparison, so every token and
// message check below is routed through streq instead of `==`.

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

// Keyword/punctuation table shared by the scanning tests: 3 keywords and
// 13 punctuation entries (16 words).
fn make_table() -> KeywordTable {
  var t = lex_table_new();
  lex_table_add(&mut t, "let", LEX_KIND_KEYWORD);
  lex_table_add(&mut t, "if", LEX_KIND_KEYWORD);
  lex_table_add(&mut t, "return", LEX_KIND_KEYWORD);
  lex_table_add(&mut t, "=", LEX_KIND_PUNCT);
  lex_table_add(&mut t, "==", LEX_KIND_PUNCT);
  lex_table_add(&mut t, "->", LEX_KIND_PUNCT);
  lex_table_add(&mut t, "-", LEX_KIND_PUNCT);
  lex_table_add(&mut t, "+", LEX_KIND_PUNCT);
  lex_table_add(&mut t, "*", LEX_KIND_PUNCT);
  lex_table_add(&mut t, "{", LEX_KIND_PUNCT);
  lex_table_add(&mut t, "}", LEX_KIND_PUNCT);
  lex_table_add(&mut t, "(", LEX_KIND_PUNCT);
  lex_table_add(&mut t, ")", LEX_KIND_PUNCT);
  lex_table_add(&mut t, ",", LEX_KIND_PUNCT);
  lex_table_add(&mut t, ";", LEX_KIND_PUNCT);
  lex_table_add(&mut t, ".", LEX_KIND_PUNCT);
  return t;
}

fn empty_table() -> KeywordTable {
  return lex_table_new();
}

// The XIOM-like fixture scanned by the snippet tests: 20 tokens across four
// lines, both comment styles, keywords, idents, ints (underscored), a float
// and an escaped-free string.
fn snippet() -> Str {
  return "let x = 42;\nif x == 3.14 { return \"ok\"; } // done\n/* block\ncomment */ let y = 1_000;";
}

// ---------------------------------------------------------------------------
// Result extractors and predicates
// ---------------------------------------------------------------------------

// One-letter code per token kind: i n f s p k c e (? = unknown).
fn kind_char(k: Int) -> Str {
  if k == LEX_KIND_IDENTIFIER { return "i"; }
  if k == LEX_KIND_INTEGER { return "n"; }
  if k == LEX_KIND_FLOAT { return "f"; }
  if k == LEX_KIND_STRING { return "s"; }
  if k == LEX_KIND_PUNCT { return "p"; }
  if k == LEX_KIND_KEYWORD { return "k"; }
  if k == LEX_KIND_COMMENT { return "c"; }
  if k == LEX_KIND_EOF { return "e"; }
  return "?";
}

// Kind-code string of scanning `source` with the shared table.
fn kinds_code(source: Str) -> Str {
  let t = make_table();
  let r = lex_scan(source, &t);
  match r {
    Ok(st) => {
      var out = "";
      var i = 0;
      while i < lex_token_count(&st) {
        out = out + kind_char(lex_token_kind(&st, i));
        i = i + 1;
      }
      return out;
    },
    Err(_) => { return "<err>"; },
  }
  return "<err>";
}

// "|text|text" concatenation of the raw token texts of `source`.
fn texts_code(source: Str) -> Str {
  let t = make_table();
  let r = lex_scan(source, &t);
  match r {
    Ok(st) => {
      var out = "";
      var i = 0;
      while i < lex_token_count(&st) {
        out = out + "|" + token_text(source, &st, i);
        i = i + 1;
      }
      return out;
    },
    Err(_) => { return "<err>"; },
  }
  return "<err>";
}

// "line:col;line:col" for every token of `source`.
fn pos_code(source: Str) -> Str {
  let t = make_table();
  let r = lex_scan(source, &t);
  match r {
    Ok(st) => {
      var out = "";
      var i = 0;
      while i < lex_token_count(&st) {
        if i > 0 { out = out + ";"; }
        out = out + int_to_string(lex_token_line(&st, i)) + ":" + int_to_string(lex_token_col(&st, i));
        i = i + 1;
      }
      return out;
    },
    Err(_) => { return "<err>"; },
  }
  return "<err>";
}

fn scan_count(source: Str) -> Int {
  let t = make_table();
  let r = lex_scan(source, &t);
  match r {
    Ok(st) => { return lex_token_count(&st); },
    Err(_) => { return -1; },
  }
  return -1;
}

fn scan_err_is(source: Str, want: Str) -> Bool {
  let t = make_table();
  let r = lex_scan(source, &t);
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn scan_err_empty(source: Str, want: Str) -> Bool {
  let t = empty_table();
  let r = lex_scan(source, &t);
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn token_text_is(source: Str, i: Int, want: Str) -> Bool {
  let t = make_table();
  let r = lex_scan(source, &t);
  match r {
    Ok(st) => { return streq(token_text(source, &st, i), want); },
    Err(_) => { return false; },
  }
  return false;
}

// Matched-length extractors for the two Result-returning matchers (-1 = Err).
fn str_mlen(source: Str, at: Int) -> Int {
  let r = lex_match_string(source, at);
  match r {
    Ok(x) => { return x; },
    Err(_) => { return -1; },
  }
  return -1;
}

fn block_mlen(source: Str, at: Int) -> Int {
  let r = lex_match_block_comment(source, at);
  match r {
    Ok(x) => { return x; },
    Err(_) => { return -1; },
  }
  return -1;
}

fn str_merr(source: Str, at: Int, want: Str) -> Bool {
  let r = lex_match_string(source, at);
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn block_merr(source: Str, at: Int, want: Str) -> Bool {
  let r = lex_match_block_comment(source, at);
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

// ---------------------------------------------------------------------------
// Predicate helpers for tests that check many fields
// ---------------------------------------------------------------------------

fn accessors_ok() -> Bool {
  let t = make_table();
  let r = lex_scan("let x", &t);
  match r {
    Ok(st) => {
      if lex_token_count(&st) != 2 { return false; }
      if lex_token_kind(&st, 0) != LEX_KIND_KEYWORD { return false; }
      if lex_token_kind(&st, 1) != LEX_KIND_IDENTIFIER { return false; }
      if lex_token_start(&st, 0) != 0 { return false; }
      if lex_token_end(&st, 0) != 3 { return false; }
      if lex_token_line(&st, 0) != 1 { return false; }
      if lex_token_col(&st, 0) != 1 { return false; }
      if lex_token_start(&st, 1) != 4 { return false; }
      if lex_token_end(&st, 1) != 5 { return false; }
      if lex_token_col(&st, 1) != 5 { return false; }
      if lex_token_kind(&st, 2) != LEX_KIND_NONE { return false; }
      if lex_token_kind(&st, -1) != LEX_KIND_NONE { return false; }
      if lex_token_start(&st, 2) != -1 { return false; }
      if lex_token_end(&st, -2) != -1 { return false; }
      if lex_token_line(&st, 9) != -1 { return false; }
      if lex_token_col(&st, 9) != -1 { return false; }
      return true;
    },
    Err(_) => { return false; },
  }
  return false;
}

fn next_steps_ok() -> Bool {
  let t = make_table();
  var s = lex_state_new("ab");
  if lex_at_end(&s) { return false; }
  let r1 = lex_next(&mut s, &t);
  if !r1.is_ok { return false; }
  let tok1: Token = r1.value;
  if tok1.kind != LEX_KIND_IDENTIFIER { return false; }
  if tok1.start != 0 { return false; }
  if tok1.end != 2 { return false; }
  if tok1.line != 1 { return false; }
  if tok1.col != 1 { return false; }
  if lex_pos(&s) != 2 { return false; }
  let r2 = lex_next(&mut s, &t);
  if !r2.is_ok { return false; }
  let tok2: Token = r2.value;
  if tok2.kind != LEX_KIND_EOF { return false; }
  if tok2.start != 2 { return false; }
  if tok2.end != 2 { return false; }
  if tok2.line != 1 { return false; }
  if tok2.col != 3 { return false; }
  if !lex_at_end(&s) { return false; }
  let r3 = lex_next(&mut s, &t);
  if !r3.is_ok { return false; }
  let tok3: Token = r3.value;
  if tok3.kind != LEX_KIND_EOF { return false; }
  return true;
}

fn state_helpers_ok() -> Bool {
  var s = lex_state_new("abc\nd");
  if !streq(lex_state_source(&s), "abc\nd") { return false; }
  if lex_pos(&s) != 0 { return false; }
  if lex_line(&s) != 1 { return false; }
  if lex_col(&s) != 1 { return false; }
  if lex_at_end(&s) { return false; }
  if lex_peek(&s) != 97 { return false; }
  if lex_peek_at(&s, 1) != 98 { return false; }
  if lex_peek_at(&s, 99) != -1 { return false; }
  if lex_peek_at(&s, -1) != -1 { return false; }
  if !lex_expect(&mut s, 97) { return false; }
  if lex_pos(&s) != 1 { return false; }
  if lex_expect(&mut s, 122) { return false; }
  if !lex_expect_str(&mut s, "bc") { return false; }
  if lex_pos(&s) != 3 { return false; }
  if lex_expect_str(&mut s, "x") { return false; }
  if !lex_expect_str(&mut s, "") { return false; }
  lex_advance_n(&mut s, 1);
  if lex_line(&s) != 2 { return false; }
  if lex_col(&s) != 1 { return false; }
  if lex_peek(&s) != 100 { return false; }
  if !lex_expect(&mut s, 100) { return false; }
  if !lex_at_end(&s) { return false; }
  lex_advance(&mut s);
  if lex_pos(&s) != 5 { return false; }
  return true;
}

fn matchers_ok() -> Bool {
  if lex_match_identifier("foo bar", 0) != 3 { return false; }
  if lex_match_identifier("foo bar", 4) != 3 { return false; }
  if lex_match_identifier("9abc", 0) != 0 { return false; }
  if lex_match_identifier("_9", 0) != 2 { return false; }
  if lex_match_identifier("", 0) != 0 { return false; }
  if lex_match_integer("1_000 x", 0) != 5 { return false; }
  if lex_match_integer("42", 0) != 2 { return false; }
  if lex_match_integer("x1", 0) != 0 { return false; }
  if lex_match_float("3.14e10xyz", 0) != 7 { return false; }
  if lex_match_float("1.5e", 0) != 3 { return false; }
  if lex_match_float("6.02E+3", 0) != 7 { return false; }
  if lex_match_float("1.", 0) != 0 { return false; }
  if lex_match_float(".5", 0) != 0 { return false; }
  if lex_match_float("1_0.2", 0) != 5 { return false; }
  if lex_match_line_comment("// abc\ndef", 0) != 6 { return false; }
  if lex_match_line_comment("//", 0) != 2 { return false; }
  if lex_match_line_comment("/ abc", 0) != 0 { return false; }
  if str_mlen("\"ab\"", 0) != 4 { return false; }
  if str_mlen("x", 0) != 0 { return false; }
  if block_mlen("/* ab */ x", 0) != 8 { return false; }
  if block_mlen("/*/ */", 0) != 6 { return false; }
  if block_mlen("/ abc", 0) != 0 { return false; }
  return true;
}

fn table_api_ok() -> Bool {
  let t = make_table();
  if lex_table_len(&t) != 16 { return false; }
  if !streq(lex_table_word(&t, 0), "let") { return false; }
  if lex_table_kind(&t, 0) != LEX_KIND_KEYWORD { return false; }
  if lex_table_lookup(&t, "let") != LEX_KIND_KEYWORD { return false; }
  if lex_table_lookup(&t, "letx") != LEX_KIND_NONE { return false; }
  if lex_table_lookup(&t, "==") != LEX_KIND_PUNCT { return false; }
  if lex_table_lookup(&t, "") != LEX_KIND_NONE { return false; }
  if lex_table_classify(&t, "x") != LEX_KIND_IDENTIFIER { return false; }
  if lex_table_classify(&t, "if") != LEX_KIND_KEYWORD { return false; }
  if lex_table_classify(&t, "==") != LEX_KIND_PUNCT { return false; }
  if !streq(lex_table_word(&t, 99), "") { return false; }
  if lex_table_kind(&t, 99) != LEX_KIND_NONE { return false; }
  if lex_table_kind(&t, -1) != LEX_KIND_NONE { return false; }
  return true;
}

fn punct_word_ok() -> Bool {
  var t = lex_table_new();
  lex_table_add(&mut t, "and", LEX_KIND_PUNCT);
  let r = lex_scan("and or", &t);
  match r {
    Ok(st) => {
      if lex_token_count(&st) != 2 { return false; }
      if lex_token_kind(&st, 0) != LEX_KIND_PUNCT { return false; }
      if lex_token_kind(&st, 1) != LEX_KIND_IDENTIFIER { return false; }
      if !streq(token_text("and or", &st, 0), "and") { return false; }
      return true;
    },
    Err(_) => { return false; },
  }
  return false;
}

fn text_api_ok() -> Bool {
  if !streq(lex_span_text("let x", 0, 3), "let") { return false; }
  if !streq(lex_span_text("let x", 3, 0), "") { return false; }
  if !streq(lex_span_text("let x", -5, 99), "let x") { return false; }
  if !streq(lex_span_text("let x", 5, 5), "") { return false; }
  if !streq(lex_kind_name(LEX_KIND_NONE), "none") { return false; }
  if !streq(lex_kind_name(LEX_KIND_IDENTIFIER), "identifier") { return false; }
  if !streq(lex_kind_name(LEX_KIND_INTEGER), "integer") { return false; }
  if !streq(lex_kind_name(LEX_KIND_FLOAT), "float-literal") { return false; }
  if !streq(lex_kind_name(LEX_KIND_STRING), "string-literal") { return false; }
  if !streq(lex_kind_name(LEX_KIND_PUNCT), "punctuation") { return false; }
  if !streq(lex_kind_name(LEX_KIND_KEYWORD), "keyword") { return false; }
  if !streq(lex_kind_name(LEX_KIND_COMMENT), "comment") { return false; }
  if !streq(lex_kind_name(LEX_KIND_EOF), "EOF") { return false; }
  if !streq(lex_kind_name(12345), "none") { return false; }
  if !token_text_is("let x", 0, "let") { return false; }
  if !token_text_is("let x", 1, "x") { return false; }
  if !token_text_is("let x", 5, "") { return false; }
  if !token_text_is("let x", -1, "") { return false; }
  if !token_text_is(snippet(), 11, "\"ok\"") { return false; }
  return true;
}

fn determinism_ok() -> Bool {
  let src = "let x = 1; // c\n/* b */ \"s\"";
  let t1 = make_table();
  let r1 = lex_scan(src, &t1);
  let t2 = make_table();
  let r2 = lex_scan(src, &t2);
  if !r1.is_ok { return false; }
  if !r2.is_ok { return false; }
  let s1: TokenStream = r1.value;
  let s2: TokenStream = r2.value;
  if lex_token_count(&s1) != lex_token_count(&s2) { return false; }
  var i = 0;
  while i < lex_token_count(&s1) {
    if lex_token_kind(&s1, i) != lex_token_kind(&s2, i) { return false; }
    if lex_token_start(&s1, i) != lex_token_start(&s2, i) { return false; }
    if lex_token_end(&s1, i) != lex_token_end(&s2, i) { return false; }
    if !streq(token_text(src, &s1, i), token_text(src, &s2, i)) { return false; }
    i = i + 1;
  }
  return true;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

fn t1() -> TestResult {
  var ok = streq(kinds_code("foo bar _x a1b2"), "iiii");
  if !streq(texts_code("foo bar _x a1b2"), "|foo|bar|_x|a1b2") { ok = false; }
  return assert(ok, "identifiers: maximal [A-Za-z_][A-Za-z0-9_]* runs");
}

fn t2() -> TestResult {
  var ok = streq(kinds_code("let if lets returnx if"), "kkiik");
  if !streq(texts_code("let if lets returnx if"), "|let|if|lets|returnx|if") { ok = false; }
  return assert(ok, "keywords vs identifiers: exact text is the registered kind, prefixes stay idents");
}

fn t3() -> TestResult {
  return assert(streq(texts_code("0 42 007 1_000 12_34_56"), "|0|42|007|1_000|12_34_56"), "integers: digits with single underscores, verbatim");
}

fn t4() -> TestResult {
  var ok = streq(kinds_code("1__0 1_"), "nini");
  if !streq(texts_code("1__0 1_"), "|1|__0|1|_") { ok = false; }
  return assert(ok, "integer underscores: doubled and trailing underscores are not digits");
}

fn t5() -> TestResult {
  var ok = streq(kinds_code("3.14 1.5e10 2.0E+3 7.25e-2 1_0.2_5"), "fffff");
  if !streq(texts_code("3.14 1.5e10 2.0E+3 7.25e-2 1_0.2_5"), "|3.14|1.5e10|2.0E+3|7.25e-2|1_0.2_5") { ok = false; }
  return assert(ok, "floats: digits '.' digits with optional exponent and underscores");
}

fn t6() -> TestResult {
  var ok = streq(kinds_code("1.5e 1. -3"), "finppn");
  if !streq(texts_code("1.5e 1. -3"), "|1.5|e|1|.|-|3") { ok = false; }
  return assert(ok, "float maximal munch: '1.5e' splits, '1.' is int then dot, sign is caller-level");
}

fn t7() -> TestResult {
  var ok = streq(kinds_code("\"hello\""), "s");
  if !streq(texts_code("\"hello\""), "|\"hello\"") { ok = false; }
  if !streq(kinds_code("\"\""), "s") { ok = false; }
  if !streq(texts_code("\"\""), "|\"\"") { ok = false; }
  return assert(ok, "strings: quotes inclusive in the raw token text, empty literal");
}

fn t8() -> TestResult {
  let src = "\"a\\\"b\\\\c\\nd\"";
  var ok = streq(kinds_code(src), "s");
  if scan_count(src) != 1 { ok = false; }
  if !streq(texts_code(src), "|" + src) { ok = false; }
  return assert(ok, "strings: escaped quote/backslash/null keep the literal open and stay raw");
}

fn t9() -> TestResult {
  let src = "\"a\nb\" x";
  var ok = streq(kinds_code(src), "si");
  if !streq(texts_code(src), "|\"a\nb\"|x") { ok = false; }
  if !streq(pos_code(src), "1:1;2:4") { ok = false; }
  return assert(ok, "strings: a raw LF inside the literal is kept and line tracking continues");
}

fn t10() -> TestResult {
  var ok = streq(kinds_code("x // one\n y"), "ici");
  if !streq(texts_code("x // one\n y"), "|x|// one|y") { ok = false; }
  if !streq(pos_code("x // one\n y"), "1:1;1:3;2:2") { ok = false; }
  if !streq(kinds_code("//"), "c") { ok = false; }
  if !streq(texts_code("//"), "|//") { ok = false; }
  return assert(ok, "line comments: '//' to (not including) the LF, token text excludes the newline");
}

fn t11() -> TestResult {
  var ok = streq(kinds_code("/* a b */ x"), "ci");
  if !streq(texts_code("/* a b */ x"), "|/* a b */|x") { ok = false; }
  if !streq(pos_code("/* a b */ x"), "1:1;1:11") { ok = false; }
  return assert(ok, "block comments: delimiters inclusive, one token, next token position exact");
}

fn t12() -> TestResult {
  var ok = scan_count(snippet()) == 21;
  if !streq(kinds_code(snippet()), "kipnpkipfpksppcckipnp") { ok = false; }
  return assert(ok, "snippet: 21 tokens, kinds cover idents/ints/float/string/punct/keywords/both comments");
}

fn t13() -> TestResult {
  let want = "1:1;1:5;1:7;1:9;1:11;2:1;2:4;2:6;2:9;2:14;2:16;2:23;2:27;2:29;2:31;3:1;4:12;4:16;4:18;4:20;4:25";
  return assert(streq(pos_code(snippet()), want), "snippet: exact 1-based line:col for all 21 tokens");
}

fn t14() -> TestResult {
  var ok = streq(pos_code("a\nbb\n  ccc"), "1:1;2:1;3:3");
  if !streq(pos_code("a\r\nbb"), "1:1;2:1") { ok = false; }
  if !streq(pos_code("a\rb"), "1:1;1:3") { ok = false; }
  if !streq(kinds_code("a\nbb\n  ccc"), "iii") { ok = false; }
  return assert(ok, "line/col tracking: LF advances lines, CRLF is one newline, CR is one column");
}

fn t15() -> TestResult {
  var ok = scan_err_is("\"abc", "lexer: unterminated string at 0");
  if !scan_err_is("x \"y", "lexer: unterminated string at 2") { ok = false; }
  if !scan_err_is("\"a\\", "lexer: unterminated string at 0") { ok = false; }
  return assert(ok, "unterminated string: opening-quote position, also after a trailing backslash");
}

fn t16() -> TestResult {
  var ok = scan_err_is("\"a\\qb\"", "lexer: invalid escape at 2");
  if !str_merr("\"a\\qb\"", 0, "lexer: invalid escape at 2") { ok = false; }
  return assert(ok, "invalid escape: backslash position reported");
}

fn t17() -> TestResult {
  var ok = scan_err_is("/* abc", "lexer: unterminated block comment at 0");
  if !scan_err_is("x /* y", "lexer: unterminated block comment at 2") { ok = false; }
  if !scan_err_is("/*/", "lexer: unterminated block comment at 0") { ok = false; }
  if !block_merr("/*/", 0, "lexer: unterminated block comment at 0") { ok = false; }
  return assert(ok, "unterminated block comment: opening-slash position, '/*/' does not close");
}

fn t18() -> TestResult {
  var ok = scan_err_is("a @ b", "lexer: unexpected byte at 2");
  if !scan_err_is("#", "lexer: unexpected byte at 0") { ok = false; }
  if !scan_err_is("é", "lexer: unexpected byte at 0") { ok = false; }
  if !scan_err_empty("=", "lexer: unexpected byte at 0") { ok = false; }
  if !scan_err_empty("a = b", "lexer: unexpected byte at 2") { ok = false; }
  return assert(ok, "unexpected byte: exact position, non-ASCII widened+masked, table drives punctuation");
}

fn t19() -> TestResult {
  var ok = streq(kinds_code(""), "");
  if !streq(kinds_code(" \t\n\r "), "") { ok = false; }
  if scan_count("") != 0 { ok = false; }
  if scan_count("  ") != 0 { ok = false; }
  return assert(ok, "empty input: no tokens for empty or whitespace-only text");
}

fn t20() -> TestResult {
  return assert(accessors_ok(), "stream accessors: exact fields and NONE/-1 out-of-range values");
}

fn t21() -> TestResult {
  return assert(next_steps_ok(), "lex_next: one token per call, EOF sentinel at end, state advances");
}

fn t22() -> TestResult {
  return assert(state_helpers_ok(), "scan state: peek/peek_at/expect/expect_str/advance_n and line/col");
}

fn t23() -> TestResult {
  return assert(matchers_ok(), "matchers: standalone lengths for ident/int/float/string/comments");
}

fn t24() -> TestResult {
  return assert(str_merr("\"abc", 0, "lexer: unterminated string at 0"), "public string matcher: unterminated error");
}

fn t25() -> TestResult {
  return assert(table_api_ok(), "keyword table: parallel words/kinds, exact first-match lookup, range safety");
}

fn t26() -> TestResult {
  return assert(punct_word_ok(), "classification: a registered identifier word can classify as punctuation");
}

fn t27() -> TestResult {
  return assert(text_api_ok(), "token_text/span_text/kind_name: raw reconstruction, clamping, names");
}

fn t28() -> TestResult {
  return assert(determinism_ok(), "determinism: repeated scans yield identical tokens, positions and texts");
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
  io.println("=== xiom.lexer-fw conformance tests ===");
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
  failed = failed + report(t27());
  failed = failed + report(t28());
  if failed == 0 {
    io.println("xiom.lexer-fw: all tests passed");
  } else {
    io.println("xiom.lexer-fw: tests failed");
  }
  return failed;
}
