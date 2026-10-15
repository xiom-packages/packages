// XIOM -- xiom.template conformance tests (43 checks)
// Port task: prove the pure-XIOM xiom.template module against its SPEC.
// v0.2.0: t1-t22 pin the placeholder surface (xiom.template, unchanged);
// t23-t43 pin the block surface (xiom.template.blocks): sections, loops,
// inverted sections, dotted paths, auto-escaping, error offsets, caps.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// All Str equality goes through str_compare: BUG 17 lowers `==` on Str values
// read from Vec[Str] elements to a pointer comparison, so every comparison
// below is routed through streq/ok_is/err_is instead of `==`.

module template_tests
use xiom.io; use xiom.test; use xiom.template; use xiom.template.blocks;
use xiom.string; use xiom.string.builder; use xiom.string.compare;

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// True when r is Ok and its payload is exactly `want`.
fn ok_is(r: Result[Str, Str], want: Str) -> Bool {
  if !r.is_ok {
    return false;
  }
  return streq(r.value, want);
}

// True when r is Err and its message is exactly `want`.
fn err_is(r: Result[Str, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return streq(r.error, want);
}

// Small Vec[Str] builders for inline key/value tables.
fn v1(a: Str) -> Vec[Str] {
  var v = Vec[Str].new();
  v.push(a);
  return v;
}

fn v2(a: Str, b: Str) -> Vec[Str] {
  var v = Vec[Str].new();
  v.push(a);
  v.push(b);
  return v;
}

fn v3(a: Str, b: Str, c: Str) -> Vec[Str] {
  var v = Vec[Str].new();
  v.push(a);
  v.push(b);
  v.push(c);
  return v;
}

// Element-wise list checks (via str_compare, never `==`).
fn list_is(items: &Vec[Str], a: Str) -> Bool {
  if items.len() != 1 {
    return false;
  }
  let first: Str = items[0];
  return streq(first, a);
}

fn list_is2(items: &Vec[Str], a: Str, b: Str) -> Bool {
  if items.len() != 2 {
    return false;
  }
  let first: Str = items[0];
  let second: Str = items[1];
  var ok = streq(first, a);
  if !streq(second, b) { ok = false; }
  return ok;
}

fn list_is3(items: &Vec[Str], a: Str, b: Str, c: Str) -> Bool {
  if items.len() != 3 {
    return false;
  }
  let first: Str = items[0];
  let second: Str = items[1];
  let third: Str = items[2];
  var ok = streq(first, a);
  if !streq(second, b) { ok = false; }
  if !streq(third, c) { ok = false; }
  return ok;
}

fn t1() -> TestResult {
  var empty = Vec[Str].new();
  let r = template_render("Hello, world!", &empty, &empty);
  var ok = ok_is(r, "Hello, world!");
  let l = template_render_lenient("Hello, world!", &empty, &empty);
  if !streq(l, "Hello, world!") { ok = false; }
  return assert(ok, "plain text passes through unchanged");
}

fn t2() -> TestResult {
  var keys = v1("name");
  var values = v1("Ada");
  let r = template_render("Hello, {{name}}!", &keys, &values);
  return assert(ok_is(r, "Hello, Ada!"), "single placeholder substitutes");
}

fn t3() -> TestResult {
  var keys = v3("a", "b", "c");
  var values = v3("1", "2", "3");
  let r = template_render("{{a}}+{{b}}={{c}}", &keys, &values);
  return assert(ok_is(r, "1+2=3"), "multiple placeholders substitute");
}

fn t4() -> TestResult {
  var keys = v1("name");
  var values = v1("Ada");
  let r = template_render("{{ name }}/{{name }}/{{  name  }}", &keys, &values);
  return assert(ok_is(r, "Ada/Ada/Ada"), "spaces inside braces are ignored");
}

fn t5() -> TestResult {
  var keys = v1("name");
  var values = v1("Ada");
  let r = template_render("Hi {{who}}!", &keys, &values);
  return assert(err_is(r, "template: missing key: who"), "missing key is an Err in strict mode");
}

fn t6() -> TestResult {
  var keys = v1("name");
  var values = v1("Ada");
  let r = template_render_lenient("Hi {{who}}!", &keys, &values);
  return assert(streq(r, "Hi !"), "missing key renders empty in lenient mode");
}

fn t7() -> TestResult {
  var keys = v2("k", "k");
  var values = v2("first", "second");
  let r = template_render("{{k}}/{{k}}", &keys, &values);
  var ok = ok_is(r, "first/first");
  var keys2 = v2("k", "k");
  var values2 = v2("first", "second");
  let l = template_render_lenient("{{k}}", &keys2, &values2);
  if !streq(l, "first") { ok = false; }
  return assert(ok, "duplicate key: the first match wins");
}

fn t8() -> TestResult {
  var empty = Vec[Str].new();
  let r1 = template_render("a{{! note }}b", &empty, &empty);
  var ok = ok_is(r1, "ab");
  let r2 = template_render("a{{!note}}b", &empty, &empty);
  if !ok_is(r2, "ab") { ok = false; }
  let r3 = template_render("{{ ! spaced }}x", &empty, &empty);
  if !ok_is(r3, "x") { ok = false; }
  return assert(ok, "comments are removed");
}

fn t9() -> TestResult {
  var empty = Vec[Str].new();
  let r1 = template_render("{{{{", &empty, &empty);
  var ok = ok_is(r1, "{{");
  let r2 = template_render("a{{{{b", &empty, &empty);
  if !ok_is(r2, "a{{b") { ok = false; }
  let r3 = template_render("{{{{name}}", &empty, &empty);
  if !ok_is(r3, "{{name}}") { ok = false; }
  return assert(ok, "quadruple braces emit one literal {{");
}

fn t10() -> TestResult {
  var empty = Vec[Str].new();
  let r1 = template_render("a {{b", &empty, &empty);
  var ok = err_is(r1, "template: unterminated placeholder");
  let r2 = template_render("{{", &empty, &empty);
  if !err_is(r2, "template: unterminated placeholder") { ok = false; }
  let r3 = template_render("x{{! never closed", &empty, &empty);
  if !err_is(r3, "template: unterminated placeholder") { ok = false; }
  return assert(ok, "unterminated placeholder is an Err in strict mode");
}

fn t11() -> TestResult {
  var empty = Vec[Str].new();
  let r1 = template_render_lenient("a {{b", &empty, &empty);
  var ok = streq(r1, "a ");
  let r2 = template_render_lenient("{{", &empty, &empty);
  if !streq(r2, "") { ok = false; }
  let r3 = template_render_lenient("x{{! never closed", &empty, &empty);
  if !streq(r3, "x") { ok = false; }
  return assert(ok, "unterminated placeholder drops the tail in lenient mode");
}

fn t12() -> TestResult {
  var keys = v2("a", "b");
  var values = v2("1", "2");
  let r = template_render("{{a}}{{b}}{{a}}{{b}}", &keys, &values);
  return assert(ok_is(r, "1212"), "adjacent placeholders render back to back");
}

fn t13() -> TestResult {
  var empty = Vec[Str].new();
  let r = template_render("", &empty, &empty);
  var ok = ok_is(r, "");
  let l = template_render_lenient("", &empty, &empty);
  if !streq(l, "") { ok = false; }
  let ks = template_keys("");
  if ks.len() != 0 { ok = false; }
  return assert(ok, "empty template renders empty and has no keys");
}

fn t14() -> TestResult {
  var keys = v1("a");
  var values = v1("");
  let r = template_render("x{{a}}y", &keys, &values);
  var ok = ok_is(r, "xy");
  var keys2 = v2("a", "b");
  var values2 = v2("", "B");
  let r2 = template_render("{{a}}{{b}}", &keys2, &values2);
  if !ok_is(r2, "B") { ok = false; }
  return assert(ok, "an empty value substitutes as empty (not missing)");
}

fn t15() -> TestResult {
  let ks = template_keys("{{b}} {{a}} {{b}} {{c}} {{a}}");
  var ok = list_is3(&ks, "b", "a", "c");
  let ks2 = template_keys("{{x}}{{! a }}{{a}}{{a}}{{!x}}");
  if !list_is2(&ks2, "x", "a") { ok = false; }
  let ks3 = template_keys("{{{{ {{z}}");
  if !list_is(&ks3, "z") { ok = false; }
  return assert(ok, "template_keys is first-seen, deduped and comment-free");
}

fn t16() -> TestResult {
  var keys = v1("b");
  let need = template_needs_keys("{{a}}{{b}}{{c}}{{a}}", &keys);
  var ok = list_is2(&need, "a", "c");
  var none = Vec[Str].new();
  let all = template_needs_keys("{{a}}{{b}}{{a}}", &none);
  if !list_is2(&all, "a", "b") { ok = false; }
  let commented = template_needs_keys("{{!x}}{{a}}", &none);
  if !list_is(&commented, "a") { ok = false; }
  return assert(ok, "template_needs_keys reports missing keys in first-seen order");
}

fn t17() -> TestResult {
  var keys = v2("a", "b");
  var values = v2("{{b}}", "EXPANDED");
  let r = template_render("{{a}}", &keys, &values);
  var ok = ok_is(r, "{{b}}");
  let r2 = template_render("{{a}}{{a}}", &keys, &values);
  if !ok_is(r2, "{{b}}{{b}}") { ok = false; }
  var keys1 = v1("a");
  var values1 = v1("{{name}}");
  let l = template_render_lenient("x{{a}}", &keys1, &values1);
  if !streq(l, "x{{name}}") { ok = false; }
  return assert(ok, "substituted values are not re-expanded (single pass)");
}

fn t18() -> TestResult {
  var keys = v1("");
  var values = v1("E");
  let r = template_render("[{{}}]", &keys, &values);
  var ok = ok_is(r, "[E]");
  var empty = Vec[Str].new();
  let r2 = template_render("[{{}}]", &empty, &empty);
  if !err_is(r2, "template: missing key: ") { ok = false; }
  let l = template_render_lenient("[{{}}]", &empty, &empty);
  if !streq(l, "[]") { ok = false; }
  return assert(ok, "the empty name matches the empty-string key");
}

fn t19() -> TestResult {
  var keys = v1("");
  var values = v1("E");
  let r = template_render("{{  }}", &keys, &values);
  var ok = ok_is(r, "E");
  var empty = Vec[Str].new();
  let r2 = template_render("{{  }}", &empty, &empty);
  if !err_is(r2, "template: missing key: ") { ok = false; }
  return assert(ok, "a whitespace-only placeholder is the empty name");
}

fn t20() -> TestResult {
  var keys = v1("x");
  var values = v1("é");
  let r = template_render("café {{x}} ✓", &keys, &values);
  var ok = ok_is(r, "café é ✓");
  let ks = template_keys("café {{x}} ✓");
  if !list_is(&ks, "x") { ok = false; }
  return assert(ok, "non-ASCII text passes through byte-exact");
}

fn t21() -> TestResult {
  var keys = v2("a", "b");
  var values = v1("1");
  let r1 = template_render("{{a}}", &keys, &values);
  var ok = ok_is(r1, "1");
  let r2 = template_render("{{b}}", &keys, &values);
  if !err_is(r2, "template: missing key: b") { ok = false; }
  let need = template_needs_keys("{{a}}{{b}}", &keys);
  if need.len() != 0 { ok = false; }
  return assert(ok, "a key without a parallel value counts as missing");
}

fn t22() -> TestResult {
  var empty = Vec[Str].new();
  let r1 = template_render("a {b} c", &empty, &empty);
  var ok = ok_is(r1, "a {b} c");
  let r2 = template_render("}{", &empty, &empty);
  if !ok_is(r2, "}{") { ok = false; }
  let r3 = template_render("a}}b", &empty, &empty);
  if !ok_is(r3, "a}}b") { ok = false; }
  var keys = v1("a");
  var values = v1("X");
  let r4 = template_render("{{a}}}", &keys, &values);
  if !ok_is(r4, "X}") { ok = false; }
  return assert(ok, "lone braces and stray }} are literal text");
}

// --------------------------------------------------
//  v0.2.0 block surface (xiom.template.blocks)
// --------------------------------------------------

// `part` repeated `n` times as one Str (cap tests; builder-backed).
fn rep(part: Str, n: Int) -> Str {
  var sb = builder.sb_new();
  var i = 0;
  while i < n {
    builder.sb_push_str(&mut sb, part);
    i = i + 1;
  }
  return builder.sb_to_str(&sb);
}

fn t23() -> TestResult {
  var d = template_data_new();
  var items = v3("red", "green", "blue");
  template_data_set_list(&mut d, "items", &items);
  let r = template_render_blocks("<{{#items}}{{.}},{{/items}}>", &d, true);
  var ok = ok_is(r, "<red,green,blue,>");
  var one = v1("solo");
  template_data_set_list(&mut d, "one", &one);
  let r2 = template_render_blocks("[{{#one}}{{.}}{{/one}}]", &d, true);
  if !ok_is(r2, "[solo]") { ok = false; }
  return assert(ok, "list sections iterate and {{.}} is the item");
}

fn t24() -> TestResult {
  var d = template_data_new();
  var none = Vec[Str].new();
  template_data_set_list(&mut d, "empty", &none);
  template_data_set_str(&mut d, "blank", "");
  template_data_set_bool(&mut d, "no", false);
  let r = template_render_blocks("a{{#empty}}X{{/empty}}b{{#blank}}Y{{/blank}}c{{#no}}Z{{/no}}d", &d, true);
  var ok = ok_is(r, "abcd");
  let rl = template_render_blocks_lenient("a{{#empty}}X{{/empty}}b{{#blank}}Y{{/blank}}c{{#no}}Z{{/no}}d", &d, true);
  if !streq(rl, "abcd") { ok = false; }
  return assert(ok, "empty list, empty Str and false Bool sections are skipped");
}

fn t25() -> TestResult {
  var d = template_data_new();
  template_data_set_bool(&mut d, "yes", true);
  template_data_set_str(&mut d, "word", "w");
  template_data_set_str(&mut d, "grp.x", "1");
  let r = template_render_blocks("{{#yes}}Y{{/yes}}{{#word}}W{{/word}}{{#grp}}{{x}}{{/grp}}", &d, true);
  return assert(ok_is(r, "YW1"), "true Bool, non-empty Str and dotted group sections render once");
}

fn t26() -> TestResult {
  var d = template_data_new();
  template_data_set_bool(&mut d, "on", true);
  template_data_set_bool(&mut d, "off", false);
  var none = Vec[Str].new();
  template_data_set_list(&mut d, "none", &none);
  var some = v2("a", "b");
  template_data_set_list(&mut d, "some", &some);
  let r = template_render_blocks("{{^on}}1{{/on}}{{^off}}2{{/off}}{{^none}}3{{/none}}{{^some}}4{{/some}}", &d, true);
  var ok = ok_is(r, "23");
  let rl = template_render_blocks_lenient("{{^gone}}G{{/gone}}", &d, true);
  if !streq(rl, "G") { ok = false; }
  return assert(ok, "inverted sections render when falsy/empty and skip when truthy");
}

fn t27() -> TestResult {
  var d = template_data_new();
  template_data_set_str(&mut d, "user.name", "Ada");
  template_data_set_str(&mut d, "user.address.city", "Athens");
  template_data_set_str(&mut d, "site", "BLOG");
  let r = template_render_blocks("{{#user}}{{#address}}{{city}}|{{name}}{{/address}}/{{site}}{{/user}}", &d, true);
  return assert(ok_is(r, "Athens|Ada/BLOG"), "nested sections, dotted paths and ancestor fallback resolve in order");
}

fn t28() -> TestResult {
  var d = template_data_new();
  template_data_set_str(&mut d, "label", "L");
  var items = v2("x", "y");
  template_data_set_list(&mut d, "items", &items);
  let r = template_render_blocks("{{#items}}{{label}}:{{.}};{{/items}}", &d, true);
  var ok = ok_is(r, "L:x;L:y;");
  template_data_set_str(&mut d, "meta.unit", "u");
  let r2 = template_render_blocks("{{#items}}{{meta.unit}}{{.}}{{/items}}", &d, true);
  if !ok_is(r2, "uxuy") { ok = false; }
  return assert(ok, "non-dot keys inside a list section resolve against the parent context");
}

fn t29() -> TestResult {
  var d = template_data_new();
  var outer = v2("A", "B");
  var inner = v2("1", "2");
  template_data_set_list(&mut d, "outer", &outer);
  template_data_set_list(&mut d, "inner", &inner);
  let r = template_render_blocks("{{#outer}}{{#inner}}{{.}}{{/inner}}|{{/outer}}", &d, true);
  return assert(ok_is(r, "12|12|"), "nested list sections iterate the inner list per outer item");
}

fn t30() -> TestResult {
  var d = template_data_new();
  template_data_set_str(&mut d, "v", "<&>\"'");
  let r = template_render_blocks("{{v}}", &d, true);
  var ok = ok_is(r, "&lt;&amp;&gt;&quot;&#39;");
  let r2 = template_render_blocks("x{{v}}y", &d, true);
  if !ok_is(r2, "x&lt;&amp;&gt;&quot;&#39;y") { ok = false; }
  return assert(ok, "auto-escape escapes < > & \" ' in {{name}} substitutions");
}

fn t31() -> TestResult {
  var d = template_data_new();
  template_data_set_str(&mut d, "v", "<&>\"'");
  let r = template_render_blocks("{{{v}}}|{{&v}}|{{ & v }}", &d, true);
  return assert(ok_is(r, "<&>\"'|<&>\"'|<&>\"'"), "{{{name}}} and {{&name}} interpolate raw (never escaped)");
}

fn t32() -> TestResult {
  var d = template_data_new();
  template_data_set_str(&mut d, "v", "<&>\"'");
  let r = template_render_blocks("{{v}}", &d, false);
  var ok = ok_is(r, "<&>\"'");
  var l = v1("<a>");
  template_data_set_list(&mut d, "l", &l);
  let r2 = template_render_blocks("{{#l}}{{.}}{{/l}}", &d, false);
  if !ok_is(r2, "<a>") { ok = false; }
  return assert(ok, "escape_html=false renders every value verbatim");
}

fn t33() -> TestResult {
  var d = template_data_new();
  template_data_set_str(&mut d, "w", "café");
  var us = v3("é", "✓", "日本");
  template_data_set_list(&mut d, "us", &us);
  let r = template_render_blocks("{{w}}|{{#us}}{{.}},{{/us}}", &d, true);
  var ok = ok_is(r, "café|é,✓,日本,");
  let r2 = template_render_blocks("{{#us}}{{.}}={{w}};{{/us}}", &d, true);
  if !ok_is(r2, "é=café;✓=café;日本=café;") { ok = false; }
  return assert(ok, "multi-byte UTF-8 passes through byte-exact (escape mode included)");
}

fn t34() -> TestResult {
  var d = template_data_new();
  template_data_set_bool(&mut d, "a", true);
  template_data_set_bool(&mut d, "b", true);
  let r1 = template_render_blocks("{{#a}}x", &d, true);
  var ok = err_is(r1, "template: unterminated section 'a' at byte 0");
  let r2 = template_render_blocks("{{#a}}{{#b}}", &d, true);
  if !err_is(r2, "template: unterminated section 'b' at byte 6") { ok = false; }
  let r3 = template_render_blocks("{{#a}}{{#b}}x{{/b}}", &d, true);
  if !err_is(r3, "template: unterminated section 'a' at byte 0") { ok = false; }
  return assert(ok, "unterminated sections are strict Errs at the opening offset");
}

fn t35() -> TestResult {
  var d = template_data_new();
  template_data_set_bool(&mut d, "a", true);
  let r1 = template_render_blocks("{{#a}}x{{/b}}", &d, true);
  var ok = err_is(r1, "template: mismatched close 'b' at byte 7 (expected 'a')");
  let r2 = template_render_blocks("{{/x}}", &d, true);
  if !err_is(r2, "template: mismatched close 'x' at byte 0") { ok = false; }
  return assert(ok, "mismatched and stray closes are strict Errs at the close offset");
}

fn t36() -> TestResult {
  var d = template_data_new();
  template_data_set_str(&mut d, "name", "N");
  let r1 = template_render_blocks("abc{{name", &d, true);
  var ok = err_is(r1, "template: unclosed interpolation at byte 3");
  let r2 = template_render_blocks("a{{{x}}", &d, true);
  if !err_is(r2, "template: unclosed interpolation at byte 1") { ok = false; }
  let r3 = template_render_blocks("x{{! nope", &d, true);
  if !err_is(r3, "template: unclosed interpolation at byte 1") { ok = false; }
  return assert(ok, "an unclosed {{ (placeholder, triple, comment) is a strict Err at its offset");
}

fn t37() -> TestResult {
  var d = template_data_new();
  let r1 = template_render_blocks("{{missing}}", &d, true);
  var ok = err_is(r1, "template: unknown key: missing at byte 0");
  let r2 = template_render_blocks("ab{{#gone}}x{{/gone}}", &d, true);
  if !err_is(r2, "template: unknown key: gone at byte 2") { ok = false; }
  let r3 = template_render_blocks("{{.}}", &d, true);
  if !err_is(r3, "template: unknown key: . at byte 0") { ok = false; }
  let r4 = template_render_blocks("{{^gone}}x{{/gone}}", &d, true);
  if !err_is(r4, "template: unknown key: gone at byte 0") { ok = false; }
  return assert(ok, "strict mode reports unknown keys with byte offsets");
}

fn t38() -> TestResult {
  var d = template_data_new();
  var items = v2("a", "b");
  template_data_set_list(&mut d, "items", &items);
  template_data_set_bool(&mut d, "yes", true);
  let r1 = template_render_blocks_lenient("x{{gone}}y", &d, true);
  var ok = streq(r1, "xy");
  let r2 = template_render_blocks_lenient("x{{#gone}}Z{{/gone}}y", &d, true);
  if !streq(r2, "xy") { ok = false; }
  let r3 = template_render_blocks_lenient("x{{^gone}}G{{/gone}}y", &d, true);
  if !streq(r3, "xGy") { ok = false; }
  let r4 = template_render_blocks_lenient("{{#items}}x{{/bogus}}", &d, true);
  if !streq(r4, "xx") { ok = false; }
  let r5 = template_render_blocks_lenient("{{#items}}x", &d, true);
  if !streq(r5, "xx") { ok = false; }
  let r6 = template_render_blocks_lenient("{{#items}}x{{/item", &d, true);
  if !streq(r6, "x") { ok = false; }
  let r7 = template_render_blocks_lenient("{{#yes}}w{{/yes}}{{#no}}k{{/no}}", &d, true);
  if !streq(r7, "w") { ok = false; }
  return assert(ok, "lenient mode skips unknown keys, ignores bad closes and virtual-closes at EOF");
}

fn t39() -> TestResult {
  var d = template_data_new();
  template_data_set_bool(&mut d, "a", true);
  let deep = rep("{{#a}}", 65) + "Z" + rep("{{/a}}", 65);
  let r = template_render_blocks(deep, &d, true);
  var ok = err_is(r, "template: nesting exceeds 64 at byte 384");
  let ok64 = rep("{{#a}}", 64) + "Z" + rep("{{/a}}", 64);
  let r2 = template_render_blocks(ok64, &d, true);
  if !ok_is(r2, "Z") { ok = false; }
  let rl = template_render_blocks_lenient(deep, &d, true);
  if !streq(rl, "") { ok = false; }
  return assert(ok, "TEMPLATE_MAX_DEPTH=64: the 65th section is a strict Err / suppressed in lenient");
}

fn t40() -> TestResult {
  if TEMPLATE_MAX_OUTPUT != 8388608 { return assert(false, "TEMPLATE_MAX_OUTPUT caps strict Errs and truncates lenient output"); }
  var item = rep("x", 1024);
  var big = Vec[Str].new();
  var i = 0;
  while i < 8194 {
    big.push(item);
    i = i + 1;
  }
  var d = template_data_new();
  template_data_set_list(&mut d, "big", &big);
  let r = template_render_blocks("{{#big}}{{.}}{{/big}}", &d, true);
  var ok = err_is(r, "template: output exceeds 8388608 bytes at byte 8");
  let rl = template_render_blocks_lenient("{{#big}}{{.}}{{/big}}", &d, true);
  var lok = rl.len() == TEMPLATE_MAX_OUTPUT;
  if rl.len() > 0 {
    // str_slice reads through the raw pointer: string.byte_at clamps past
    // 1 MiB in the runtime, so the tail is verified with a slice, not byte_at.
    let head = string.str_slice(rl, 0, 4);
    let tail = string.str_slice(rl, rl.len() - 4, rl.len());
    if !streq(head, "xxxx") { lok = false; }
    if !streq(tail, "xxxx") { lok = false; }
  } else {
    lok = false;
  }
  if !lok { ok = false; }
  return assert(ok, "TEMPLATE_MAX_OUTPUT caps strict Errs and truncates lenient output");
}

fn t41() -> TestResult {
  var d = template_data_new();
  template_data_set_str(&mut d, "title", "Tea & \"Coffee\"");
  var items = v2("<one>", "two & more");
  template_data_set_list(&mut d, "items", &items);
  template_data_set_str(&mut d, "foot", "<i>raw</i>");
  let tmpl = "<h1>{{title}}</h1><ul>{{#items}}<li>{{.}}</li>{{/items}}</ul>{{^items}}<p>empty</p>{{/items}}<footer>{{&foot}}</footer>";
  let want = "<h1>Tea &amp; &quot;Coffee&quot;</h1><ul><li>&lt;one&gt;</li><li>two &amp; more</li></ul><footer><i>raw</i></footer>";
  let r = template_render_blocks(tmpl, &d, true);
  return assert(ok_is(r, want), "KAT: a mixed page renders to the hand-computed output");
}

fn t42() -> TestResult {
  var d = template_data_new();
  var arr = v1("one");
  template_data_set_str(&mut d, "a", "1");
  template_data_set_bool(&mut d, "b", true);
  template_data_set_list(&mut d, "c", &arr);
  var ok = template_data_len(&d) == 3;
  if TEMPLATE_VALUE_STR != 0 { ok = false; }
  if TEMPLATE_VALUE_BOOL != 1 { ok = false; }
  if TEMPLATE_VALUE_LIST != 2 { ok = false; }
  if !template_data_has(&d, "a") { ok = false; }
  if template_data_has(&d, "zz") { ok = false; }
  if template_data_kind(&d, "a") != TEMPLATE_VALUE_STR { ok = false; }
  if template_data_kind(&d, "b") != TEMPLATE_VALUE_BOOL { ok = false; }
  if template_data_kind(&d, "c") != TEMPLATE_VALUE_LIST { ok = false; }
  if template_data_kind(&d, "zz") != -1 { ok = false; }
  template_data_set_str(&mut d, "a", "2");
  if template_data_len(&d) != 3 { ok = false; }
  arr.push("late");
  let r = template_render_blocks("{{#c}}{{.}}{{/c}}", &d, true);
  if !ok_is(r, "one") { ok = false; }
  let r2 = template_render_blocks("{{a}}", &d, true);
  if !ok_is(r2, "2") { ok = false; }
  return assert(ok, "data accessors, replace-in-place and list copy semantics");
}

fn t43() -> TestResult {
  var d = template_data_new();
  template_data_set_str(&mut d, "name", "N");
  template_data_set_bool(&mut d, "flag", true);
  let r1 = template_render_blocks("a{{! c }}b{{name}}", &d, true);
  var ok = ok_is(r1, "abN");
  let r2 = template_render_blocks("{{{{x}}", &d, true);
  if !ok_is(r2, "{{x}}") { ok = false; }
  let r3 = template_render_blocks("{{  name  }}", &d, true);
  if !ok_is(r3, "N") { ok = false; }
  let r4 = template_render_blocks("{{# flag }}ok{{/ flag }}", &d, true);
  if !ok_is(r4, "ok") { ok = false; }
  let r5 = template_render_blocks("a}}b{ c", &d, true);
  if !ok_is(r5, "a}}b{ c") { ok = false; }
  let r6 = template_render_blocks("{{name}}}", &d, true);
  if !ok_is(r6, "N}") { ok = false; }
  return assert(ok, "comments, quadruples, spaced tags and lone braces keep the v0.1 conventions");
}

fn main() -> Int {
  io.println("=== xiom.template conformance tests ===");
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
  let r28 = t28();
  if r28.passed { io.println("  [PASS] " + r28.name); } else { io.println("  [FAIL] " + r28.name); failed = failed + 1; }
  let r29 = t29();
  if r29.passed { io.println("  [PASS] " + r29.name); } else { io.println("  [FAIL] " + r29.name); failed = failed + 1; }
  let r30 = t30();
  if r30.passed { io.println("  [PASS] " + r30.name); } else { io.println("  [FAIL] " + r30.name); failed = failed + 1; }
  let r31 = t31();
  if r31.passed { io.println("  [PASS] " + r31.name); } else { io.println("  [FAIL] " + r31.name); failed = failed + 1; }
  let r32 = t32();
  if r32.passed { io.println("  [PASS] " + r32.name); } else { io.println("  [FAIL] " + r32.name); failed = failed + 1; }
  let r33 = t33();
  if r33.passed { io.println("  [PASS] " + r33.name); } else { io.println("  [FAIL] " + r33.name); failed = failed + 1; }
  let r34 = t34();
  if r34.passed { io.println("  [PASS] " + r34.name); } else { io.println("  [FAIL] " + r34.name); failed = failed + 1; }
  let r35 = t35();
  if r35.passed { io.println("  [PASS] " + r35.name); } else { io.println("  [FAIL] " + r35.name); failed = failed + 1; }
  let r36 = t36();
  if r36.passed { io.println("  [PASS] " + r36.name); } else { io.println("  [FAIL] " + r36.name); failed = failed + 1; }
  let r37 = t37();
  if r37.passed { io.println("  [PASS] " + r37.name); } else { io.println("  [FAIL] " + r37.name); failed = failed + 1; }
  let r38 = t38();
  if r38.passed { io.println("  [PASS] " + r38.name); } else { io.println("  [FAIL] " + r38.name); failed = failed + 1; }
  let r39 = t39();
  if r39.passed { io.println("  [PASS] " + r39.name); } else { io.println("  [FAIL] " + r39.name); failed = failed + 1; }
  let r40 = t40();
  if r40.passed { io.println("  [PASS] " + r40.name); } else { io.println("  [FAIL] " + r40.name); failed = failed + 1; }
  let r41 = t41();
  if r41.passed { io.println("  [PASS] " + r41.name); } else { io.println("  [FAIL] " + r41.name); failed = failed + 1; }
  let r42 = t42();
  if r42.passed { io.println("  [PASS] " + r42.name); } else { io.println("  [FAIL] " + r42.name); failed = failed + 1; }
  let r43 = t43();
  if r43.passed { io.println("  [PASS] " + r43.name); } else { io.println("  [FAIL] " + r43.name); failed = failed + 1; }
  if failed == 0 {
    io.println("xiom.template: all tests passed");
  } else {
    io.println("xiom.template: tests failed");
  }
  return failed;
}
