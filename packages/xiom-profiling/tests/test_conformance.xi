// XIOM -- xiom.profiling conformance tests (26 checks)
// Port task: prove the pure-XIOM xiom.profiling module against its folded-text
// contract: parsing (simple, multi-space, blank lines, CRLF, malformed), the
// aggregation helpers (total, count_for, merge, leaf, leaf_totals, top) and
// depth collapsing.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// All Str equality goes through str_compare (BUG 17 discipline: `==` on Str
// values read from a Vec lowers to a pointer comparison); every Vec read in a
// helper is bound to a typed local before use. Result values are consumed by
// helpers returning plain Bool/Int/Str/Vec, so no Ok/Err is ever constructed
// in the test module.

module profiling_tests
use xiom.io; use xiom.test; use xiom.profiling;
use xiom.string.compare;

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn at(v: &Vec[Str], i: Int) -> Str {
  if i < 0 { return ""; }
  if i >= v.len() { return ""; }
  return v[i];
}

fn iat(v: &Vec[Int], i: Int) -> Int {
  if i < 0 { return -1; }
  if i >= v.len() { return -1; }
  return v[i];
}

fn parse_is_err(text: Str) -> Bool {
  let r = prof_parse(text);
  match r {
    Ok(_) => { return false; },
    Err(_) => { return true; },
  }
  return false;
}

fn parse_err_of(text: Str) -> Str {
  let r = prof_parse(text);
  match r {
    Ok(_) => { return ""; },
    Err(e) => { return e; },
  }
  return "";
}

fn stacks_of(text: Str) -> Vec[Str] {
  let r = prof_parse(text);
  match r {
    Ok(d) => {
      var out = Vec[Str].new();
      var i = 0;
      while i < d.stacks.len() {
        let s: Str = d.stacks[i];
        out.push(s);
        i = i + 1;
      }
      return out;
    },
    Err(_) => { return Vec[Str].new(); },
  }
  return Vec[Str].new();
}

fn counts_of(text: Str) -> Vec[Int] {
  let r = prof_parse(text);
  match r {
    Ok(d) => {
      var out = Vec[Int].new();
      var i = 0;
      while i < d.counts.len() {
        let c: Int = d.counts[i];
        out.push(c);
        i = i + 1;
      }
      return out;
    },
    Err(_) => { return Vec[Int].new(); },
  }
  return Vec[Int].new();
}

fn total_of(text: Str) -> Int {
  let r = prof_parse(text);
  match r {
    Ok(d) => { return prof_total(&d); },
    Err(_) => { return -1; },
  }
  return -1;
}

fn stack_count_of(text: Str) -> Int {
  let r = prof_parse(text);
  match r {
    Ok(d) => { return prof_stack_count(&d); },
    Err(_) => { return -1; },
  }
  return -1;
}

fn count_for_of(text: Str, stack: Str) -> Int {
  let r = prof_parse(text);
  match r {
    Ok(d) => { return prof_count_for(&d, stack); },
    Err(_) => { return -1; },
  }
  return -1;
}

fn merged_stacks_of(text: Str) -> Vec[Str] {
  let r = prof_parse(text);
  match r {
    Ok(d) => {
      let m = prof_merge_same(&d);
      var out = Vec[Str].new();
      var i = 0;
      while i < m.stacks.len() {
        let s: Str = m.stacks[i];
        out.push(s);
        i = i + 1;
      }
      return out;
    },
    Err(_) => { return Vec[Str].new(); },
  }
  return Vec[Str].new();
}

fn merged_counts_of(text: Str) -> Vec[Int] {
  let r = prof_parse(text);
  match r {
    Ok(d) => {
      let m = prof_merge_same(&d);
      var out = Vec[Int].new();
      var i = 0;
      while i < m.counts.len() {
        let c: Int = m.counts[i];
        out.push(c);
        i = i + 1;
      }
      return out;
    },
    Err(_) => { return Vec[Int].new(); },
  }
  return Vec[Int].new();
}

fn leaves_of(text: Str) -> Vec[Str] {
  let r = prof_parse(text);
  match r {
    Ok(d) => { return prof_leaf(&d); },
    Err(_) => { return Vec[Str].new(); },
  }
  return Vec[Str].new();
}

fn leaf_total_stacks_of(text: Str) -> Vec[Str] {
  let r = prof_parse(text);
  match r {
    Ok(d) => {
      let m = prof_leaf_totals(&d);
      var out = Vec[Str].new();
      var i = 0;
      while i < m.stacks.len() {
        let s: Str = m.stacks[i];
        out.push(s);
        i = i + 1;
      }
      return out;
    },
    Err(_) => { return Vec[Str].new(); },
  }
  return Vec[Str].new();
}

fn leaf_total_counts_of(text: Str) -> Vec[Int] {
  let r = prof_parse(text);
  match r {
    Ok(d) => {
      let m = prof_leaf_totals(&d);
      var out = Vec[Int].new();
      var i = 0;
      while i < m.counts.len() {
        let c: Int = m.counts[i];
        out.push(c);
        i = i + 1;
      }
      return out;
    },
    Err(_) => { return Vec[Int].new(); },
  }
  return Vec[Int].new();
}

fn top_lines_of(text: Str, k: Int) -> Vec[Str] {
  let r = prof_parse(text);
  match r {
    Ok(d) => { return prof_top(&d, k); },
    Err(_) => { return Vec[Str].new(); },
  }
  return Vec[Str].new();
}

fn collapse_stacks_of(text: Str, depth: Int) -> Vec[Str] {
  let r = prof_parse(text);
  match r {
    Ok(d) => {
      let m = prof_collapse_depth(&d, depth);
      var out = Vec[Str].new();
      var i = 0;
      while i < m.stacks.len() {
        let s: Str = m.stacks[i];
        out.push(s);
        i = i + 1;
      }
      return out;
    },
    Err(_) => { return Vec[Str].new(); },
  }
  return Vec[Str].new();
}

fn collapse_counts_of(text: Str, depth: Int) -> Vec[Int] {
  let r = prof_parse(text);
  match r {
    Ok(d) => {
      let m = prof_collapse_depth(&d, depth);
      var out = Vec[Int].new();
      var i = 0;
      while i < m.counts.len() {
        let c: Int = m.counts[i];
        out.push(c);
        i = i + 1;
      }
      return out;
    },
    Err(_) => { return Vec[Int].new(); },
  }
  return Vec[Int].new();
}

fn t1() -> TestResult {
  let st = stacks_of("main;work;leaf 7\n");
  let ct = counts_of("main;work;leaf 7\n");
  var ok = st.len() == 1;
  if !streq(at(&st, 0), "main;work;leaf") { ok = false; }
  if ct.len() != 1 { ok = false; }
  if iat(&ct, 0) != 7 { ok = false; }
  return assert(ok, "parse one folded line into stack text and count");
}

fn t2() -> TestResult {
  let st = stacks_of("main;work 3\nidle 1\nmain;work;io 2");
  let ct = counts_of("main;work 3\nidle 1\nmain;work;io 2");
  var ok = st.len() == 3;
  if !streq(at(&st, 0), "main;work") { ok = false; }
  if !streq(at(&st, 1), "idle") { ok = false; }
  if !streq(at(&st, 2), "main;work;io") { ok = false; }
  if ct.len() != 3 { ok = false; }
  if iat(&ct, 0) != 3 { ok = false; }
  if iat(&ct, 1) != 1 { ok = false; }
  if iat(&ct, 2) != 2 { ok = false; }
  return assert(ok, "multi-line input keeps file order, last line needs no LF");
}

fn t3() -> TestResult {
  let st = stacks_of("a;b  12\nc   4\nz 0");
  let ct = counts_of("a;b  12\nc   4\nz 0");
  var ok = st.len() == 3;
  if !streq(at(&st, 0), "a;b") { ok = false; }
  if !streq(at(&st, 1), "c") { ok = false; }
  if !streq(at(&st, 2), "z") { ok = false; }
  if iat(&ct, 0) != 12 { ok = false; }
  if iat(&ct, 1) != 4 { ok = false; }
  if iat(&ct, 2) != 0 { ok = false; }
  return assert(ok, "multiple separator spaces collapse; count 0 is valid");
}

fn t4() -> TestResult {
  let text = "\na 1\n\n\nb 2\n\n";
  let st = stacks_of(text);
  let ct = counts_of(text);
  var ok = st.len() == 2;
  if !streq(at(&st, 0), "a") { ok = false; }
  if !streq(at(&st, 1), "b") { ok = false; }
  if iat(&ct, 0) != 1 { ok = false; }
  if iat(&ct, 1) != 2 { ok = false; }
  if stack_count_of(text) != 2 { ok = false; }
  return assert(ok, "blank lines are skipped, not entries");
}

fn t5() -> TestResult {
  let crlf_st = stacks_of("a 1\r\nb 2\r\n");
  let crlf_ct = counts_of("a 1\r\nb 2\r\n");
  let cr_st = stacks_of("solo 3\r");
  let cr_ct = counts_of("solo 3\r");
  var ok = crlf_st.len() == 2;
  if !streq(at(&crlf_st, 0), "a") { ok = false; }
  if !streq(at(&crlf_st, 1), "b") { ok = false; }
  if iat(&crlf_ct, 0) != 1 { ok = false; }
  if iat(&crlf_ct, 1) != 2 { ok = false; }
  if cr_st.len() != 1 { ok = false; }
  if !streq(at(&cr_st, 0), "solo") { ok = false; }
  if iat(&cr_ct, 0) != 3 { ok = false; }
  return assert(ok, "CRLF input parses and a lone trailing CR is stripped");
}

fn t6() -> TestResult {
  var ok = !parse_is_err("");
  if stacks_of("").len() != 0 { ok = false; }
  if counts_of("").len() != 0 { ok = false; }
  if total_of("") != 0 { ok = false; }
  if stack_count_of("") != 0 { ok = false; }
  if count_for_of("", "a") != 0 { ok = false; }
  if merged_stacks_of("").len() != 0 { ok = false; }
  if merged_counts_of("").len() != 0 { ok = false; }
  if leaves_of("").len() != 0 { ok = false; }
  if leaf_total_stacks_of("").len() != 0 { ok = false; }
  if top_lines_of("", 3).len() != 0 { ok = false; }
  if collapse_stacks_of("", 2).len() != 0 { ok = false; }
  if !streq(parse_err_of(""), "") { ok = false; }
  return assert(ok, "empty input parses to an empty table for every operation");
}

fn t7() -> TestResult {
  var ok = parse_is_err("nope");
  if !streq(parse_err_of("nope"), "profiling: line 1: missing count") { ok = false; }
  if !streq(parse_err_of("a;b x"), "profiling: line 1: missing count") { ok = false; }
  return assert(ok, "a line without a trailing integer is malformed");
}

fn t8() -> TestResult {
  var ok = parse_is_err("a;b12");
  if !streq(parse_err_of("a;b12"), "profiling: line 1: missing separator") { ok = false; }
  if !streq(parse_err_of("a;b\t12"), "profiling: line 1: missing separator") { ok = false; }
  return assert(ok, "digits not preceded by a space are malformed");
}

fn t9() -> TestResult {
  var ok = parse_is_err(" 12");
  if !streq(parse_err_of(" 12"), "profiling: line 1: empty stack") { ok = false; }
  if !streq(parse_err_of("     7"), "profiling: line 1: empty stack") { ok = false; }
  return assert(ok, "a count with no stack text is malformed");
}

fn t10() -> TestResult {
  var ok = parse_is_err("a 99999999999999999999");
  if !streq(parse_err_of("a 99999999999999999999"), "profiling: line 1: count out of range") { ok = false; }
  if total_of("a 9223372036854775807") != 9223372036854775807 { ok = false; }
  if !parse_is_err("a 9223372036854775808") { ok = false; }
  return assert(ok, "counts that overflow a signed 64-bit Int are malformed");
}

fn t11() -> TestResult {
  var ok = streq(parse_err_of("a 1\n\nbogus\n"), "profiling: line 3: missing count");
  if !streq(parse_err_of("\n\n 9"), "profiling: line 3: empty stack") { ok = false; }
  return assert(ok, "error messages name the 1-based physical line, blanks included");
}

fn t12() -> TestResult {
  var ok = streq(parse_err_of("a 1 "), "profiling: line 1: missing count");
  if !streq(parse_err_of("a 1\t"), "profiling: line 1: missing count") { ok = false; }
  if !streq(parse_err_of(" "), "profiling: line 1: missing count") { ok = false; }
  return assert(ok, "trailing whitespace after the count makes the line malformed");
}

fn t13() -> TestResult {
  var ok = total_of("a 2\nb 3\nc 4\n") == 9;
  if stack_count_of("a 2\nb 3\nc 4\n") != 3 { ok = false; }
  if total_of("a 2\na 3\n") != 5 { ok = false; }
  if total_of("z 0\n") != 0 { ok = false; }
  return assert(ok, "total sums every count; stack_count reports entries");
}

fn t14() -> TestResult {
  let text = "a;b 1\nb 2\na;b 9\n";
  var ok = count_for_of(text, "a;b") == 1;
  if count_for_of(text, "b") != 2 { ok = false; }
  if count_for_of(text, "missing") != 0 { ok = false; }
  if count_for_of(text, "") != 0 { ok = false; }
  return assert(ok, "count_for is byte-exact, first match, 0 when absent");
}

fn t15() -> TestResult {
  let text = "a 2\nb 1\na 3\nb 4\nc 5\n";
  let st = merged_stacks_of(text);
  let ct = merged_counts_of(text);
  var ok = st.len() == 3;
  if !streq(at(&st, 0), "a") { ok = false; }
  if !streq(at(&st, 1), "b") { ok = false; }
  if !streq(at(&st, 2), "c") { ok = false; }
  if iat(&ct, 0) != 5 { ok = false; }
  if iat(&ct, 1) != 5 { ok = false; }
  if iat(&ct, 2) != 5 { ok = false; }
  return assert(ok, "merge_same sums duplicates in first-seen order");
}

fn t16() -> TestResult {
  let text = "x 1\ny 2\n";
  let st = merged_stacks_of(text);
  let ct = merged_counts_of(text);
  var ok = st.len() == 2;
  if !streq(at(&st, 0), "x") { ok = false; }
  if !streq(at(&st, 1), "y") { ok = false; }
  if iat(&ct, 0) != 1 { ok = false; }
  if iat(&ct, 1) != 2 { ok = false; }
  if merged_stacks_of("").len() != 0 { ok = false; }
  return assert(ok, "merge_same leaves distinct stacks untouched");
}

fn t17() -> TestResult {
  let leaves = leaves_of("a;b;c 1\nx;y 1\np;c 1\nq;y;z 1\n");
  var ok = leaves.len() == 3;
  if !streq(at(&leaves, 0), "c") { ok = false; }
  if !streq(at(&leaves, 1), "y") { ok = false; }
  if !streq(at(&leaves, 2), "z") { ok = false; }
  return assert(ok, "leaf lists distinct innermost frames in first-seen order");
}

fn t18() -> TestResult {
  let text = "a;b 2\nc;b 3\nd;e 4\nf;b 1\n";
  let st = leaf_total_stacks_of(text);
  let ct = leaf_total_counts_of(text);
  var ok = st.len() == 2;
  if !streq(at(&st, 0), "b") { ok = false; }
  if !streq(at(&st, 1), "e") { ok = false; }
  if iat(&ct, 0) != 6 { ok = false; }
  if iat(&ct, 1) != 4 { ok = false; }
  return assert(ok, "leaf_totals sums counts per distinct leaf in first-seen order");
}

fn t19() -> TestResult {
  let text = "solo 4\nother 1\nsolo 2\n";
  let leaves = leaves_of(text);
  let st = leaf_total_stacks_of(text);
  let ct = leaf_total_counts_of(text);
  var ok = leaves.len() == 2;
  if !streq(at(&leaves, 0), "solo") { ok = false; }
  if !streq(at(&leaves, 1), "other") { ok = false; }
  if st.len() != 2 { ok = false; }
  if !streq(at(&st, 0), "solo") { ok = false; }
  if !streq(at(&st, 1), "other") { ok = false; }
  if iat(&ct, 0) != 6 { ok = false; }
  if iat(&ct, 1) != 1 { ok = false; }
  return assert(ok, "single-frame stacks are their own leaf");
}

fn t20() -> TestResult {
  var st = Vec[Str].new();
  st.push("a;b"); st.push("c"); st.push("d"); st.push("e");
  var ct = Vec[Int].new();
  ct.push(5); ct.push(3); ct.push(3); ct.push(9);
  let data = ProfData{ stacks: st; counts: ct };
  let top = prof_top(&data, 4);
  var ok = top.len() == 4;
  if !streq(at(&top, 0), "e 9") { ok = false; }
  if !streq(at(&top, 1), "a;b 5") { ok = false; }
  if !streq(at(&top, 2), "c 3") { ok = false; }
  if !streq(at(&top, 3), "d 3") { ok = false; }
  return assert(ok, "top ranks by count descending and keeps ties first-seen");
}

fn t21() -> TestResult {
  var st = Vec[Str].new();
  st.push("x"); st.push("y"); st.push("z");
  var ct = Vec[Int].new();
  ct.push(5); ct.push(5); ct.push(1);
  let data = ProfData{ stacks: st; counts: ct };
  let all = prof_top(&data, 99);
  let none = prof_top(&data, 0);
  let negative = prof_top(&data, -1);
  let one = prof_top(&data, 1);
  var ok = all.len() == 3;
  if !streq(at(&all, 0), "x 5") { ok = false; }
  if !streq(at(&all, 1), "y 5") { ok = false; }
  if !streq(at(&all, 2), "z 1") { ok = false; }
  if none.len() != 0 { ok = false; }
  if negative.len() != 0 { ok = false; }
  if one.len() != 1 { ok = false; }
  if !streq(at(&one, 0), "x 5") { ok = false; }
  return assert(ok, "top clamps k to [0, size]");
}

fn t22() -> TestResult {
  let top = top_lines_of("x 5\ny 5\nz 1\n", 2);
  var ok = top.len() == 2;
  if !streq(at(&top, 0), "x 5") { ok = false; }
  if !streq(at(&top, 1), "y 5") { ok = false; }
  if top_lines_of("x 5\ny 5\nz 1\n", 3).len() != 3 { ok = false; }
  if top_lines_of("", 2).len() != 0 { ok = false; }
  return assert(ok, "top emits 'stack count' lines for parsed input");
}

fn t23() -> TestResult {
  let text = "a;b;c 5\nsolo 2\n";
  let st = collapse_stacks_of(text, 1);
  let ct = collapse_counts_of(text, 1);
  var ok = st.len() == 2;
  if !streq(at(&st, 0), "c") { ok = false; }
  if !streq(at(&st, 1), "solo") { ok = false; }
  if iat(&ct, 0) != 5 { ok = false; }
  if iat(&ct, 1) != 2 { ok = false; }
  return assert(ok, "collapse_depth 1 keeps only the leaf frame");
}

fn t24() -> TestResult {
  let two = collapse_stacks_of("a;b;c;d 5\n", 2);
  let four = collapse_stacks_of("a;b;c;d 5\n", 4);
  let deep = collapse_stacks_of("a;b;c;d 5\n", 99);
  var ok = two.len() == 1;
  if !streq(at(&two, 0), "c;d") { ok = false; }
  if !streq(at(&four, 0), "a;b;c;d") { ok = false; }
  if !streq(at(&deep, 0), "a;b;c;d") { ok = false; }
  return assert(ok, "collapse_depth keeps the last N frames, clamps deep values");
}

fn t25() -> TestResult {
  var ok = collapse_stacks_of("a;b;c 5\n", 0).len() == 0;
  if collapse_stacks_of("a;b;c 5\n", -3).len() != 0 { ok = false; }
  if collapse_stacks_of("", 2).len() != 0 { ok = false; }
  if collapse_counts_of("a;b;c 5\n", 0).len() != 0 { ok = false; }
  return assert(ok, "collapse_depth below 1 yields an empty table");
}

fn t26() -> TestResult {
  let text = "a;b;c 1\na;x;c 2\n";
  let st = collapse_stacks_of(text, 1);
  let ct = collapse_counts_of(text, 1);
  var ok = st.len() == 2;
  if !streq(at(&st, 0), "c") { ok = false; }
  if !streq(at(&st, 1), "c") { ok = false; }
  if iat(&ct, 0) != 1 { ok = false; }
  if iat(&ct, 1) != 2 { ok = false; }
  return assert(ok, "collapse_depth does not merge duplicate resulting stacks");
}

fn main() -> Int {
  io.println("=== xiom.profiling conformance tests ===");
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
    io.println("xiom.profiling: all tests passed");
  } else {
    io.println("xiom.profiling: tests failed");
  }
  return failed;
}
