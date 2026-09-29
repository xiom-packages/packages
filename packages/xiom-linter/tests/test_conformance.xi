// XIOM -- xiom.linter conformance tests (26 checks)
// Port task: prove the pure-XIOM xiom.linter module against its documented
// contract (line-oriented engine: registry, diagnostic bag, six rules,
// key = value config, deterministic text/CSV reports).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module linter_tests

use xiom.io; use xiom.test; use xiom.linter;
use xiom.string; use xiom.string.compare;

// All Str equality goes through str_compare: BUG 17 lowers `==` on Str values
// read from Vec[Str] elements to a pointer comparison, so every check below
// is routed through streq instead of `==`.

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// ---------------------------------------------------------------------------
// Result extractors with graceful fallbacks (a construction failure makes the
// value checks fail instead of aborting the whole suite)
// ---------------------------------------------------------------------------

fn int_of(r: Result[Int, Str]) -> Int {
  match r {
    Ok(x) => { return x; },
    Err(_) => { return -1; },
  }
  return -1;
}

fn int_err(r: Result[Int, Str], want: Str) -> Bool {
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn cfg_of(r: Result[LintConfig, Str]) -> LintConfig {
  match r {
    Ok(c) => { return c; },
    Err(_) => { return linter_config_new(); },
  }
  return linter_config_new();
}

fn cfg_err(r: Result[LintConfig, Str], want: Str) -> Bool {
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn reg_of(r: Result[RuleRegistry, Str]) -> RuleRegistry {
  match r {
    Ok(g) => { return g; },
    Err(_) => { return linter_registry_new(); },
  }
  return linter_registry_new();
}

fn reg_err(r: Result[RuleRegistry, Str], want: Str) -> Bool {
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

fn t1() -> TestResult {
  let reg = linter_registry_default();
  var ok = linter_rule_count(&reg) == 6;
  if !streq(linter_rule_id(&reg, 0), "trailing_whitespace") { ok = false; }
  if !streq(linter_rule_id(&reg, 1), "tab_indent") { ok = false; }
  if !streq(linter_rule_id(&reg, 2), "line_length") { ok = false; }
  if !streq(linter_rule_id(&reg, 3), "todo_marker") { ok = false; }
  if !streq(linter_rule_id(&reg, 4), "mixed_line_endings") { ok = false; }
  if !streq(linter_rule_id(&reg, 5), "missing_final_newline") { ok = false; }
  if linter_rule_severity_at(&reg, 0) != 1 { ok = false; }
  if linter_rule_severity_at(&reg, 1) != 1 { ok = false; }
  if linter_rule_severity_at(&reg, 2) != 1 { ok = false; }
  if linter_rule_severity_at(&reg, 3) != 0 { ok = false; }
  if linter_rule_severity_at(&reg, 4) != 1 { ok = false; }
  if linter_rule_severity_at(&reg, 5) != 1 { ok = false; }
  if !linter_rule_enabled(&reg, "todo_marker") { ok = false; }
  if !linter_rule_enabled_at(&reg, 5) { ok = false; }
  return assert(ok, "default registry has the six built-in rules");
}

fn t2() -> TestResult {
  var reg = linter_registry_new();
  let r0 = linter_register(&mut reg, "custom", 2, true);
  var ok = int_of(r0) == 0;
  if linter_rule_count(&reg) != 1 { ok = false; }
  if linter_rule_severity(&reg, "custom") != 2 { ok = false; }
  if !linter_rule_enabled(&reg, "custom") { ok = false; }
  if !int_err(linter_register(&mut reg, "custom", 1, false), "linter: duplicate rule id: custom") { ok = false; }
  if !int_err(linter_register(&mut reg, "", 1, false), "linter: rule id must not be empty") { ok = false; }
  if !int_err(linter_register(&mut reg, "boss", 3, false), "linter: severity must be 0, 1 or 2") { ok = false; }
  if !int_err(linter_register(&mut reg, "boss", -1, false), "linter: severity must be 0, 1 or 2") { ok = false; }
  if linter_rule_count(&reg) != 1 { ok = false; }
  return assert(ok, "register accepts one rule and rejects duplicates");
}

fn t3() -> TestResult {
  let reg = linter_registry_default();
  var ok = linter_rule_index(&reg, "line_length") == 2;
  if linter_rule_index(&reg, "nope") != -1 { ok = false; }
  if linter_rule_severity(&reg, "nope") != -1 { ok = false; }
  if linter_rule_enabled(&reg, "nope") { ok = false; }
  if linter_rule_severity(&reg, "todo_marker") != 0 { ok = false; }
  if linter_rule_severity(&reg, "mixed_line_endings") != 1 { ok = false; }
  if linter_rule_id(&reg, 99).len() != 0 { ok = false; }
  if linter_rule_severity_at(&reg, -1) != -1 { ok = false; }
  if linter_rule_enabled_at(&reg, 42) { ok = false; }
  return assert(ok, "id lookup and out-of-range accessors");
}

fn t4() -> TestResult {
  var reg = linter_registry_default();
  var ok = int_of(linter_disable(&mut reg, "tab_indent")) == 1;
  if linter_rule_enabled(&reg, "tab_indent") { ok = false; }
  if !int_err(linter_disable(&mut reg, "nope"), "linter: unknown rule id: nope") { ok = false; }
  if !int_err(linter_enable(&mut reg, "nope"), "linter: unknown rule id: nope") { ok = false; }
  if int_of(linter_enable(&mut reg, "tab_indent")) != 1 { ok = false; }
  if !linter_rule_enabled(&reg, "tab_indent") { ok = false; }
  if linter_rule_count(&reg) != 6 { ok = false; }
  return assert(ok, "enable and disable toggle rules by id");
}

fn t5() -> TestResult {
  var bag = linter_bag_new();
  var ok = linter_bag_count(&bag) == 0;
  linter_bag_add(&mut bag, 2, "rule_a", 3, 4, "first");
  linter_bag_add(&mut bag, 0, "rule_b", 7, 1, "second");
  if linter_bag_count(&bag) != 2 { ok = false; }
  if linter_bag_severity(&bag, 0) != 2 { ok = false; }
  if linter_bag_severity(&bag, 1) != 0 { ok = false; }
  if !streq(linter_bag_rule(&bag, 0), "rule_a") { ok = false; }
  if linter_bag_line(&bag, 1) != 7 { ok = false; }
  if linter_bag_column(&bag, 0) != 4 { ok = false; }
  if !streq(linter_bag_message(&bag, 1), "second") { ok = false; }
  let d = linter_bag_get(&bag, 0);
  if d.severity != 2 { ok = false; }
  if !streq(d.rule, "rule_a") { ok = false; }
  if d.line != 3 { ok = false; }
  if d.column != 4 { ok = false; }
  if !streq(d.message, "first") { ok = false; }
  if linter_bag_severity(&bag, 9) != -1 { ok = false; }
  if linter_bag_line(&bag, -1) != 0 { ok = false; }
  if linter_bag_rule(&bag, 5).len() != 0 { ok = false; }
  let z = linter_bag_get(&bag, 5);
  if z.line != 0 { ok = false; }
  if z.message.len() != 0 { ok = false; }
  return assert(ok, "bag add, count and accessors stay aligned");
}

fn t6() -> TestResult {
  var bag = linter_bag_new();
  linter_bag_add(&mut bag, 1, "a", 1, 1, "w1");
  linter_bag_add(&mut bag, 0, "b", 2, 1, "i1");
  linter_bag_add(&mut bag, 1, "c", 3, 1, "w2");
  linter_bag_add(&mut bag, 2, "d", 4, 1, "e1");
  let warns = linter_bag_filter_severity(&bag, 1);
  var ok = linter_bag_count(&warns) == 2;
  if !streq(linter_bag_rule(&warns, 0), "a") { ok = false; }
  if !streq(linter_bag_rule(&warns, 1), "c") { ok = false; }
  if linter_bag_line(&warns, 0) != 1 { ok = false; }
  if linter_bag_line(&warns, 1) != 3 { ok = false; }
  let errs = linter_bag_filter_severity(&bag, 2);
  if linter_bag_count(&errs) != 1 { ok = false; }
  if !streq(linter_bag_message(&errs, 0), "e1") { ok = false; }
  let none = linter_bag_filter_severity(&bag, 9);
  if linter_bag_count(&none) != 0 { ok = false; }
  if linter_bag_count(&bag) != 4 { ok = false; }
  return assert(ok, "filter keeps only the requested severity");
}

fn t7() -> TestResult {
  var src = linter_bag_new();
  linter_bag_add(&mut src, 0, "x", 5, 6, "m1");
  linter_bag_add(&mut src, 2, "y", 7, 8, "m2");
  var dst = linter_bag_new();
  linter_bag_add(&mut dst, 1, "z", 1, 1, "m0");
  linter_bag_merge(&mut dst, &src);
  var ok = linter_bag_count(&dst) == 3;
  if !streq(linter_bag_rule(&dst, 2), "y") { ok = false; }
  if linter_bag_severity(&dst, 2) != 2 { ok = false; }
  if linter_bag_line(&dst, 1) != 5 { ok = false; }
  if linter_bag_column(&dst, 1) != 6 { ok = false; }
  if !streq(linter_bag_message(&dst, 1), "m1") { ok = false; }
  if linter_bag_count(&src) != 2 { ok = false; }
  return assert(ok, "merge appends every diagnostic in order");
}

fn t8() -> TestResult {
  var bag = linter_bag_new();
  linter_bag_add(&mut bag, 1, "r1", 5, 1, "five");
  linter_bag_add(&mut bag, 1, "r2", 1, 1, "one-a");
  linter_bag_add(&mut bag, 1, "r3", 3, 1, "three");
  linter_bag_add(&mut bag, 1, "r4", 1, 2, "one-b");
  linter_bag_add(&mut bag, 1, "r5", 1, 3, "one-c");
  linter_bag_add(&mut bag, 1, "r6", 3, 2, "three-b");
  linter_bag_sort_by_line(&mut bag);
  var ok = linter_bag_count(&bag) == 6;
  if linter_bag_line(&bag, 0) != 1 { ok = false; }
  if linter_bag_line(&bag, 1) != 1 { ok = false; }
  if linter_bag_line(&bag, 2) != 1 { ok = false; }
  if linter_bag_line(&bag, 3) != 3 { ok = false; }
  if linter_bag_line(&bag, 4) != 3 { ok = false; }
  if linter_bag_line(&bag, 5) != 5 { ok = false; }
  if !streq(linter_bag_rule(&bag, 0), "r2") { ok = false; }
  if !streq(linter_bag_rule(&bag, 1), "r4") { ok = false; }
  if !streq(linter_bag_rule(&bag, 2), "r5") { ok = false; }
  if !streq(linter_bag_rule(&bag, 3), "r3") { ok = false; }
  if !streq(linter_bag_rule(&bag, 4), "r6") { ok = false; }
  if !streq(linter_bag_rule(&bag, 5), "r1") { ok = false; }
  if linter_bag_column(&bag, 1) != 2 { ok = false; }
  if !streq(linter_bag_message(&bag, 4), "three-b") { ok = false; }
  return assert(ok, "sort_by_line is stable and keeps fields aligned");
}

fn t9() -> TestResult {
  let hit = lint_trailing_whitespace("ok\nbad  \n");
  var ok = linter_bag_count(&hit) == 1;
  if !streq(linter_bag_rule(&hit, 0), "trailing_whitespace") { ok = false; }
  if linter_bag_severity(&hit, 0) != 1 { ok = false; }
  if linter_bag_line(&hit, 0) != 2 { ok = false; }
  if linter_bag_column(&hit, 0) != 4 { ok = false; }
  if !streq(linter_bag_message(&hit, 0), "trailing whitespace") { ok = false; }
  let clean = lint_trailing_whitespace("ok\nfine\n");
  if linter_bag_count(&clean) != 0 { ok = false; }
  let blank = lint_trailing_whitespace("  \n");
  if linter_bag_count(&blank) != 1 { ok = false; }
  if linter_bag_column(&blank, 0) != 1 { ok = false; }
  let tabs = lint_trailing_whitespace("x\t\n");
  if linter_bag_count(&tabs) != 1 { ok = false; }
  if linter_bag_column(&tabs, 0) != 2 { ok = false; }
  return assert(ok, "trailing whitespace hit, miss and blank line");
}

fn t10() -> TestResult {
  let hit = lint_tab_indent("\tx\n \ty\nz\n");
  var ok = linter_bag_count(&hit) == 2;
  if linter_bag_line(&hit, 0) != 1 { ok = false; }
  if linter_bag_column(&hit, 0) != 1 { ok = false; }
  if linter_bag_line(&hit, 1) != 2 { ok = false; }
  if linter_bag_column(&hit, 1) != 2 { ok = false; }
  if !streq(linter_bag_message(&hit, 0), "tab indentation") { ok = false; }
  if linter_bag_severity(&hit, 0) != 1 { ok = false; }
  let mid = lint_tab_indent("a\tb\n");
  if linter_bag_count(&mid) != 0 { ok = false; }
  let clean = lint_tab_indent("  ok\n");
  if linter_bag_count(&clean) != 0 { ok = false; }
  return assert(ok, "tab indentation flags leading tabs only");
}

fn t11() -> TestResult {
  let hit = lint_line_length("12345\n1234567\n", 5);
  var ok = linter_bag_count(&hit) == 1;
  if linter_bag_line(&hit, 0) != 2 { ok = false; }
  if linter_bag_column(&hit, 0) != 6 { ok = false; }
  if !streq(linter_bag_message(&hit, 0), "line length 7 exceeds 5") { ok = false; }
  if !streq(linter_bag_rule(&hit, 0), "line_length") { ok = false; }
  let exact = lint_line_length("12345\n", 5);
  if linter_bag_count(&exact) != 0 { ok = false; }
  let zero = lint_line_length("123456\n", 0);
  if linter_bag_count(&zero) != 0 { ok = false; }
  let multi = lint_line_length("aa\nbbbb\ncc\n", 2);
  if linter_bag_count(&multi) != 1 { ok = false; }
  if linter_bag_line(&multi, 0) != 2 { ok = false; }
  return assert(ok, "line length hit, exact fit and non-positive limit");
}

fn t12() -> TestResult {
  let hit = lint_todo_markers("TODO one\nno marker\nFIXME TODO\n");
  var ok = linter_bag_count(&hit) == 3;
  if linter_bag_line(&hit, 0) != 1 { ok = false; }
  if linter_bag_column(&hit, 0) != 1 { ok = false; }
  if !streq(linter_bag_message(&hit, 0), "TODO marker") { ok = false; }
  if linter_bag_severity(&hit, 0) != 0 { ok = false; }
  if linter_bag_line(&hit, 1) != 3 { ok = false; }
  if linter_bag_column(&hit, 1) != 1 { ok = false; }
  if !streq(linter_bag_message(&hit, 1), "FIXME marker") { ok = false; }
  if linter_bag_column(&hit, 2) != 7 { ok = false; }
  if !streq(linter_bag_message(&hit, 2), "TODO marker") { ok = false; }
  let miss = lint_todo_markers("todo fixme\n");
  if linter_bag_count(&miss) != 0 { ok = false; }
  let overlap = lint_todo_markers("TODOTODO\n");
  if linter_bag_count(&overlap) != 2 { ok = false; }
  if linter_bag_column(&overlap, 1) != 5 { ok = false; }
  return assert(ok, "TODO and FIXME markers are found exactly");
}

fn t13() -> TestResult {
  let hit = lint_mixed_line_endings("a\nb\r\nc\n");
  var ok = linter_bag_count(&hit) == 1;
  if linter_bag_line(&hit, 0) != 2 { ok = false; }
  if linter_bag_column(&hit, 0) != 1 { ok = false; }
  if !streq(linter_bag_message(&hit, 0), "mixed line endings") { ok = false; }
  if linter_bag_severity(&hit, 0) != 1 { ok = false; }
  let cr_mix = lint_mixed_line_endings("a\rb\n");
  if linter_bag_count(&cr_mix) != 1 { ok = false; }
  if linter_bag_line(&cr_mix, 0) != 2 { ok = false; }
  let lf_only = lint_mixed_line_endings("a\nb\n");
  if linter_bag_count(&lf_only) != 0 { ok = false; }
  let crlf_only = lint_mixed_line_endings("a\r\nb\r\n");
  if linter_bag_count(&crlf_only) != 0 { ok = false; }
  let none = lint_mixed_line_endings("abc");
  if linter_bag_count(&none) != 0 { ok = false; }
  let last_absent = lint_mixed_line_endings("a\nb\r\n");
  if linter_bag_count(&last_absent) != 1 { ok = false; }
  return assert(ok, "mixed line endings detected at the first divergence");
}

fn t14() -> TestResult {
  let miss = lint_missing_final_newline("a\nb");
  var ok = linter_bag_count(&miss) == 1;
  if linter_bag_line(&miss, 0) != 2 { ok = false; }
  if linter_bag_column(&miss, 0) != 2 { ok = false; }
  if !streq(linter_bag_message(&miss, 0), "missing final newline") { ok = false; }
  if linter_bag_severity(&miss, 0) != 1 { ok = false; }
  let lf = lint_missing_final_newline("a\n");
  if linter_bag_count(&lf) != 0 { ok = false; }
  let cr = lint_missing_final_newline("a\r");
  if linter_bag_count(&cr) != 0 { ok = false; }
  let empty = lint_missing_final_newline("");
  if linter_bag_count(&empty) != 0 { ok = false; }
  let one = lint_missing_final_newline("abc");
  if linter_bag_count(&one) != 1 { ok = false; }
  if linter_bag_column(&one, 0) != 4 { ok = false; }
  if linter_bag_line(&one, 0) != 1 { ok = false; }
  return assert(ok, "missing final newline edge cases");
}

fn t15() -> TestResult {
  let src = linter_scan("a\r\nbb\rccc\nd");
  var ok = src.lines.len() == 4;
  if src.lines.len() == 4 {
    let l0: Str = src.lines[0];
    let l1: Str = src.lines[1];
    let l2: Str = src.lines[2];
    let l3: Str = src.lines[3];
    if !streq(l0, "a") { ok = false; }
    if !streq(l1, "bb") { ok = false; }
    if !streq(l2, "ccc") { ok = false; }
    if !streq(l3, "d") { ok = false; }
    let e0: Int = src.eols[0];
    let e1: Int = src.eols[1];
    let e2: Int = src.eols[2];
    let e3: Int = src.eols[3];
    if e0 != 2 { ok = false; }
    if e1 != 3 { ok = false; }
    if e2 != 1 { ok = false; }
    if e3 != 0 { ok = false; }
  }
  let empty = linter_scan("");
  if empty.lines.len() != 0 { ok = false; }
  let just = linter_scan("\n");
  if just.lines.len() != 1 { ok = false; }
  return assert(ok, "scan keeps line content and terminator codes");
}

fn t16() -> TestResult {
  let cfg = cfg_of(linter_config_parse("# comment\n\nline_length_max = 60\nrule.tab_indent.enabled = false\n; semi comment\n"));
  var ok = linter_config_count(&cfg) == 2;
  if !streq(linter_config_key(&cfg, 0), "line_length_max") { ok = false; }
  if !streq(linter_config_value(&cfg, 0), "60") { ok = false; }
  if !streq(linter_config_key(&cfg, 1), "rule.tab_indent.enabled") { ok = false; }
  if !streq(linter_config_value(&cfg, 1), "false") { ok = false; }
  let got = linter_config_get(&cfg, "line_length_max");
  match got {
    None => { ok = false; },
    Some(v) => { if !streq(v, "60") { ok = false; } },
  }
  let missing = linter_config_get(&cfg, "nope");
  match missing {
    None => { },
    Some(_) => { ok = false; },
  }
  if int_of(linter_config_line_length(&cfg)) != 60 { ok = false; }
  return assert(ok, "config parse reads key = value settings");
}

fn t17() -> TestResult {
  let empty = linter_config_new();
  var ok = linter_config_count(&empty) == 0;
  if int_of(linter_config_line_length(&empty)) != 80 { ok = false; }
  if linter_default_line_length() != 80 { ok = false; }
  var cfg = linter_config_new();
  linter_config_set(&mut cfg, "line_length_max", "100");
  linter_config_set(&mut cfg, "line_length_max", "120");
  if linter_config_count(&cfg) != 1 { ok = false; }
  if int_of(linter_config_line_length(&cfg)) != 120 { ok = false; }
  if !streq(linter_config_value(&cfg, 0), "120") { ok = false; }
  var bad = linter_config_new();
  linter_config_set(&mut bad, "line_length_max", "x");
  if !int_err(linter_config_line_length(&bad), "linter: config: line_length_max must be a positive integer: x") { ok = false; }
  return assert(ok, "config defaults, last-wins and setter validation");
}

fn t18() -> TestResult {
  var ok = cfg_err(linter_config_parse("nope"), "linter: config line 1: expected key = value");
  if !cfg_err(linter_config_parse("= x"), "linter: config line 1: empty key") { ok = false; }
  if !cfg_err(linter_config_parse("wat = 1"), "linter: config line 1: unknown key: wat") { ok = false; }
  if !cfg_err(linter_config_parse("line_length_max = 0"), "linter: config line 1: line_length_max must be a positive integer: 0") { ok = false; }
  if !cfg_err(linter_config_parse("line_length_max = abc"), "linter: config line 1: line_length_max must be a positive integer: abc") { ok = false; }
  if !cfg_err(linter_config_parse("line_length_max = 1000001"), "linter: config line 1: line_length_max must be a positive integer: 1000001") { ok = false; }
  if !cfg_err(linter_config_parse("rule.x.enabled = maybe"), "linter: config line 1: enabled must be true, false, 1, 0, yes or no: maybe") { ok = false; }
  if !cfg_err(linter_config_parse("rule..enabled = true"), "linter: config line 1: unknown key: rule..enabled") { ok = false; }
  if !cfg_err(linter_config_parse("line_length_max = 10\nnope = 2"), "linter: config line 2: unknown key: nope") { ok = false; }
  return assert(ok, "config parse errors are exact and line-numbered");
}

fn t19() -> TestResult {
  let cfg = cfg_of(linter_config_parse("rule.tab_indent.enabled = false\nrule.todo_marker.enabled = no\nline_length_max = 40\n"));
  let reg = reg_of(linter_registry_from_config(&cfg));
  var ok = !linter_rule_enabled(&reg, "tab_indent");
  if linter_rule_enabled(&reg, "todo_marker") { ok = false; }
  if !linter_rule_enabled(&reg, "trailing_whitespace") { ok = false; }
  if linter_rule_count(&reg) != 6 { ok = false; }
  let ghost = cfg_of(linter_config_parse("rule.custom.enabled = true\n"));
  if !reg_err(linter_registry_from_config(&ghost), "linter: config: unknown rule id: custom") { ok = false; }
  var bad_bool = linter_config_new();
  linter_config_set(&mut bad_bool, "rule.todo_marker.enabled", "maybe");
  if !reg_err(linter_registry_from_config(&bad_bool), "linter: config: enabled must be true, false, 1, 0, yes or no: maybe") { ok = false; }
  var bad_key = linter_config_new();
  linter_config_set(&mut bad_key, "wat", "1");
  if !reg_err(linter_registry_from_config(&bad_key), "linter: config: unknown key: wat") { ok = false; }
  return assert(ok, "registry_from_config applies overrides and rejects bad ids");
}

fn t20() -> TestResult {
  let bag = lint_run("ok  \n\tbad\n", "rule.tab_indent.enabled = false\n");
  var ok = linter_bag_count(&bag) == 1;
  if !streq(linter_bag_rule(&bag, 0), "trailing_whitespace") { ok = false; }
  if linter_bag_line(&bag, 0) != 1 { ok = false; }
  if linter_bag_column(&bag, 0) != 3 { ok = false; }
  let bag2 = lint_run("ok  \n\tbad\n", "rule.tab_indent.enabled = true\n");
  if linter_bag_count(&bag2) != 2 { ok = false; }
  if !streq(linter_bag_rule(&bag2, 1), "tab_indent") { ok = false; }
  return assert(ok, "lint_run honors rule toggles");
}

fn t21() -> TestResult {
  let bag = lint_run("abcdef\n", "line_length_max = 3\n");
  var ok = linter_bag_count(&bag) == 1;
  if !streq(linter_bag_rule(&bag, 0), "line_length") { ok = false; }
  if !streq(linter_bag_message(&bag, 0), "line length 6 exceeds 3") { ok = false; }
  if linter_bag_column(&bag, 0) != 4 { ok = false; }
  let long_line = string.str_repeat("x", 81) + "\n";
  let bag2 = lint_run(long_line, "");
  if linter_bag_count(&bag2) != 1 { ok = false; }
  if !streq(linter_bag_message(&bag2, 0), "line length 81 exceeds 80") { ok = false; }
  let ok_line = string.str_repeat("x", 80) + "\n";
  let bag3 = lint_run(ok_line, "");
  if linter_bag_count(&bag3) != 0 { ok = false; }
  return assert(ok, "lint_run applies the configurable line length limit");
}

fn t22() -> TestResult {
  let bag = lint_run("bad  \n", "nope");
  var ok = linter_bag_count(&bag) == 1;
  if !streq(linter_bag_rule(&bag, 0), "config") { ok = false; }
  if linter_bag_severity(&bag, 0) != 2 { ok = false; }
  if linter_bag_line(&bag, 0) != 0 { ok = false; }
  if linter_bag_column(&bag, 0) != 0 { ok = false; }
  if !streq(linter_bag_message(&bag, 0), "linter: config line 1: expected key = value") { ok = false; }
  let bag2 = lint_run("bad  \n", "rule.ghost.enabled = true");
  if linter_bag_count(&bag2) != 1 { ok = false; }
  if !streq(linter_bag_message(&bag2, 0), "linter: config: unknown rule id: ghost") { ok = false; }
  return assert(ok, "lint_run fails closed on config errors");
}

fn t23() -> TestResult {
  var bag = linter_bag_new();
  linter_bag_add(&mut bag, 1, "trailing_whitespace", 3, 12, "trailing whitespace");
  linter_bag_add(&mut bag, 0, "todo_marker", 5, 1, "TODO marker");
  let text = linter_report_text(&bag);
  var ok = streq(text, "3:12: warning trailing_whitespace: trailing whitespace\n5:1: info todo_marker: TODO marker");
  let empty = linter_bag_new();
  if linter_report_text(&empty).len() != 0 { ok = false; }
  return assert(ok, "text report is byte-exact");
}

fn t24() -> TestResult {
  var bag = linter_bag_new();
  linter_bag_add(&mut bag, 1, "trailing_whitespace", 3, 12, "trailing whitespace");
  linter_bag_add(&mut bag, 2, "config", 0, 0, "bad, value with \"quotes\"");
  let csv = linter_report_csv(&bag);
  var ok = streq(csv, "1,trailing_whitespace,3,12,trailing whitespace\n2,config,0,0,\"bad, value with \"\"quotes\"\"\"");
  let empty = linter_bag_new();
  if linter_report_csv(&empty).len() != 0 { ok = false; }
  if !streq(linter_severity_name(9), "unknown") { ok = false; }
  return assert(ok, "csv report is byte-exact and quotes fields");
}

fn t25() -> TestResult {
  var bag = lint_run("\tTODO x  \nhello world, this is long\nend", "line_length_max = 10\n");
  var ok = linter_bag_count(&bag) == 5;
  if !streq(linter_bag_rule(&bag, 0), "trailing_whitespace") { ok = false; }
  if !streq(linter_bag_rule(&bag, 1), "tab_indent") { ok = false; }
  if !streq(linter_bag_rule(&bag, 2), "line_length") { ok = false; }
  if !streq(linter_bag_rule(&bag, 3), "todo_marker") { ok = false; }
  if !streq(linter_bag_rule(&bag, 4), "missing_final_newline") { ok = false; }
  if linter_bag_column(&bag, 0) != 8 { ok = false; }
  if linter_bag_column(&bag, 1) != 1 { ok = false; }
  if linter_bag_column(&bag, 3) != 2 { ok = false; }
  linter_bag_sort_by_line(&mut bag);
  if linter_bag_line(&bag, 2) != 1 { ok = false; }
  if !streq(linter_bag_rule(&bag, 2), "todo_marker") { ok = false; }
  if !streq(linter_bag_rule(&bag, 3), "line_length") { ok = false; }
  if !streq(linter_bag_message(&bag, 3), "line length 25 exceeds 10") { ok = false; }
  if linter_bag_line(&bag, 4) != 3 { ok = false; }
  if !streq(linter_bag_rule(&bag, 4), "missing_final_newline") { ok = false; }
  let warns = linter_bag_filter_severity(&bag, 1);
  if linter_bag_count(&warns) != 4 { ok = false; }
  let infos = linter_bag_filter_severity(&bag, 0);
  if linter_bag_count(&infos) != 1 { ok = false; }
  return assert(ok, "lint_run end-to-end with sort and filter");
}

fn t26() -> TestResult {
  var ok = streq(linter_version(), "xiom.linter 0.1.0");
  if !streq(linter_severity_name(0), "info") { ok = false; }
  if !streq(linter_severity_name(1), "warning") { ok = false; }
  if !streq(linter_severity_name(2), "error") { ok = false; }
  let reg = linter_registry_default();
  if linter_rule_severity(&reg, "nosuchrule") != -1 { ok = false; }
  return assert(ok, "version marker and severity names");
}

fn main() -> Int {
  io.println("=== xiom.linter conformance tests ===");
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
    io.println("xiom.linter: all tests passed");
  } else {
    io.println("xiom.linter: tests failed");
  }
  return failed;
}
