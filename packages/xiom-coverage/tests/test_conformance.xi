// XIOM -- xiom.coverage conformance tests (22 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure-XIOM proof of the xiom.coverage module against the documented .gcov
// text subset, its error catalog, its accessors, its summary math and its
// canonical emitter. Synthetic .gcov text is built in-test.
//
// Coverage: every record kind (Source/Graph/Data/Runs/Programs metadata,
// line records in all four count forms, function summaries, the three branch
// forms, call and unconditional records), multi-file ranges, metadata
// last-wins, blank/CRLF tolerance, count boundaries (0, leading zeros,
// 1000000000, overflow), all stdout-visible summary numbers (executable /
// covered / unexecuted lines, percents and basis points), pooled totals
// across files, event stream order, canonical emit and round trips, the full
// error catalog (unknown record, malformed line/function/branch/call/
// unconditional records, bad metadata, record before Source) with exact
// messages and byte offsets, out-of-range accessor sentinels and multi-byte
// UTF-8 round trips.
//
// All Str equality goes through str_compare: BUG 17 lowers `==` on Str
// values read from Vec[Str] elements to a pointer comparison, so every
// comparison below is routed through streq or a doc_equal helper.

module coverage_tests
use xiom.io; use xiom.test; use xiom.coverage;
use xiom.string.compare;

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// True when `text` fails to parse with exactly the message `want`.
fn err_is(text: Str, want: Str) -> Bool {
  let r = gcov_parse(text);
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

// Structural equality of one file's records in two documents.
fn file_equal(a: &GcovDoc, b: &GcovDoc, f: Int) -> Bool {
  if !streq(gcov_file_source(a, f), gcov_file_source(b, f)) { return false; }
  if gcov_file_has_graph(a, f) != gcov_file_has_graph(b, f) { return false; }
  if gcov_file_has_data(a, f) != gcov_file_has_data(b, f) { return false; }
  if !streq(gcov_file_graph(a, f), gcov_file_graph(b, f)) { return false; }
  if !streq(gcov_file_data(a, f), gcov_file_data(b, f)) { return false; }
  if gcov_file_runs(a, f) != gcov_file_runs(b, f) { return false; }
  if gcov_file_programs(a, f) != gcov_file_programs(b, f) { return false; }
  if gcov_file_line_count(a, f) != gcov_file_line_count(b, f) { return false; }
  var i = 0;
  while i < gcov_file_line_count(a, f) {
    if gcov_file_line_number(a, f, i) != gcov_file_line_number(b, f, i) { return false; }
    if gcov_file_line_count_value(a, f, i) != gcov_file_line_count_value(b, f, i) { return false; }
    if !streq(gcov_file_line_source(a, f, i), gcov_file_line_source(b, f, i)) { return false; }
    i = i + 1;
  }
  if gcov_file_branch_count(a, f) != gcov_file_branch_count(b, f) { return false; }
  i = 0;
  while i < gcov_file_branch_count(a, f) {
    if gcov_branch_index(a, f, i) != gcov_branch_index(b, f, i) { return false; }
    if gcov_branch_taken_count(a, f, i) != gcov_branch_taken_count(b, f, i) { return false; }
    i = i + 1;
  }
  if gcov_file_function_count(a, f) != gcov_file_function_count(b, f) { return false; }
  i = 0;
  while i < gcov_file_function_count(a, f) {
    if !streq(gcov_function_name(a, f, i), gcov_function_name(b, f, i)) { return false; }
    if gcov_function_called_count(a, f, i) != gcov_function_called_count(b, f, i) { return false; }
    if gcov_function_returned_percent(a, f, i) != gcov_function_returned_percent(b, f, i) { return false; }
    if gcov_function_blocks_percent(a, f, i) != gcov_function_blocks_percent(b, f, i) { return false; }
    i = i + 1;
  }
  if gcov_file_call_count(a, f) != gcov_file_call_count(b, f) { return false; }
  i = 0;
  while i < gcov_file_call_count(a, f) {
    if gcov_call_index(a, f, i) != gcov_call_index(b, f, i) { return false; }
    if !streq(gcov_call_tail(a, f, i), gcov_call_tail(b, f, i)) { return false; }
    i = i + 1;
  }
  if gcov_file_unconditional_count(a, f) != gcov_file_unconditional_count(b, f) { return false; }
  i = 0;
  while i < gcov_file_unconditional_count(a, f) {
    if gcov_unconditional_index(a, f, i) != gcov_unconditional_index(b, f, i) { return false; }
    if gcov_unconditional_taken(a, f, i) != gcov_unconditional_taken(b, f, i) { return false; }
    i = i + 1;
  }
  if gcov_file_event_count(a, f) != gcov_file_event_count(b, f) { return false; }
  i = 0;
  while i < gcov_file_event_count(a, f) {
    if gcov_event_kind(a, f, i) != gcov_event_kind(b, f, i) { return false; }
    if gcov_event_ref(a, f, i) != gcov_event_ref(b, f, i) { return false; }
    i = i + 1;
  }
  return true;
}

// Structural equality of two parsed documents.
fn doc_equal(a: &GcovDoc, b: &GcovDoc) -> Bool {
  if gcov_file_count(a) != gcov_file_count(b) { return false; }
  var f = 0;
  while f < gcov_file_count(a) {
    if !file_equal(a, b, f) { return false; }
    f = f + 1;
  }
  return true;
}

// parse -> emit -> parse is structure-preserving and emit is idempotent.
fn round_trip(text: Str) -> Bool {
  let r1 = gcov_parse(text);
  match r1 {
    Ok(d1) => {
      let once = gcov_emit(&d1);
      let r2 = gcov_parse(once);
      match r2 {
        Ok(d2) => {
          if !doc_equal(&d1, &d2) { return false; }
          let twice = gcov_emit(&d2);
          return streq(once, twice);
        },
        Err(_) => { return false; },
      }
    },
    Err(_) => { return false; },
  }
  return false;
}

// The complete happy-path stream reused by several checks. It is already in
// canonical form, so emit(text) must reproduce it byte for byte.
fn full_text() -> Str {
  return "-:0:Source:src/a.c\n-:0:Graph:obj/a.gcno\n-:0:Data:obj/a.gcda\n-:0:Runs:2\n-:0:Programs:1\nfunction main called 2 returned 100% blocks executed 80%\n1:3:int main() {\nbranch 0 taken 1\nbranch 1 never executed\ncall 0 returned 2\n2:4:  work();\nunconditional 0 taken 3\n#####:5:  if (x) {\n-:6:}\n=====:7:\n";
}

fn t1() -> TestResult {
  let r = gcov_parse(full_text());
  var ok = false;
  match r {
    Ok(d) => {
      ok = gcov_file_count(&d) == 1;
      if !streq(gcov_file_source(&d, 0), "src/a.c") { ok = false; }
      if !streq(gcov_file_graph(&d, 0), "obj/a.gcno") { ok = false; }
      if !gcov_file_has_graph(&d, 0) { ok = false; }
      if !streq(gcov_file_data(&d, 0), "obj/a.gcda") { ok = false; }
      if !gcov_file_has_data(&d, 0) { ok = false; }
      if gcov_file_runs(&d, 0) != 2 { ok = false; }
      if gcov_file_programs(&d, 0) != 1 { ok = false; }
      if gcov_file_line_count(&d, 0) != 5 { ok = false; }
      if gcov_file_line_number(&d, 0, 0) != 3 { ok = false; }
      if gcov_file_line_number(&d, 0, 4) != 7 { ok = false; }
      if gcov_file_line_count_value(&d, 0, 0) != 1 { ok = false; }
      if gcov_file_line_count_value(&d, 0, 1) != 2 { ok = false; }
      if gcov_file_line_count_value(&d, 0, 2) != GCOV_NOT_EXECUTED { ok = false; }
      if gcov_file_line_count_value(&d, 0, 3) != GCOV_NO_LINE { ok = false; }
      if gcov_file_line_count_value(&d, 0, 4) != GCOV_NO_CODE { ok = false; }
      if !streq(gcov_file_line_source(&d, 0, 0), "int main() {") { ok = false; }
      if !streq(gcov_file_line_source(&d, 0, 1), "  work();") { ok = false; }
      if !streq(gcov_file_line_source(&d, 0, 4), "") { ok = false; }
      if !gcov_line_executable(&d, 0, 0) { ok = false; }
      if !gcov_line_executable(&d, 0, 2) { ok = false; }
      if gcov_line_executable(&d, 0, 3) { ok = false; }
      if gcov_line_executable(&d, 0, 4) { ok = false; }
      if !gcov_line_covered(&d, 0, 0) { ok = false; }
      if gcov_line_covered(&d, 0, 2) { ok = false; }
      if gcov_file_executable_lines(&d, 0) != 3 { ok = false; }
      if gcov_file_covered_lines(&d, 0) != 2 { ok = false; }
      if gcov_file_unexecuted_lines(&d, 0) != 1 { ok = false; }
      if gcov_file_line_percent(&d, 0) != 66 { ok = false; }
      if gcov_file_line_basis_points(&d, 0) != 6666 { ok = false; }
      if gcov_file_branch_count(&d, 0) != 2 { ok = false; }
      if gcov_branch_index(&d, 0, 0) != 0 { ok = false; }
      if gcov_branch_index(&d, 0, 1) != 1 { ok = false; }
      if gcov_branch_taken_count(&d, 0, 0) != 1 { ok = false; }
      if gcov_branch_taken_count(&d, 0, 1) != -1 { ok = false; }
      if !gcov_branch_covered(&d, 0, 0) { ok = false; }
      if gcov_branch_covered(&d, 0, 1) { ok = false; }
      if gcov_file_branches_taken(&d, 0) != 1 { ok = false; }
      if gcov_file_branch_percent(&d, 0) != 50 { ok = false; }
      if gcov_file_branch_basis_points(&d, 0) != 5000 { ok = false; }
      if gcov_file_function_count(&d, 0) != 1 { ok = false; }
      if !streq(gcov_function_name(&d, 0, 0), "main") { ok = false; }
      if gcov_function_called_count(&d, 0, 0) != 2 { ok = false; }
      if gcov_function_returned_percent(&d, 0, 0) != 100 { ok = false; }
      if gcov_function_blocks_percent(&d, 0, 0) != 80 { ok = false; }
      if !gcov_function_covered(&d, 0, 0) { ok = false; }
      if gcov_file_functions_called(&d, 0) != 1 { ok = false; }
      if gcov_file_function_percent(&d, 0) != 100 { ok = false; }
      if gcov_file_function_basis_points(&d, 0) != 10000 { ok = false; }
      if gcov_file_call_count(&d, 0) != 1 { ok = false; }
      if gcov_call_index(&d, 0, 0) != 0 { ok = false; }
      if !streq(gcov_call_tail(&d, 0, 0), "2") { ok = false; }
      if gcov_file_unconditional_count(&d, 0) != 1 { ok = false; }
      if gcov_unconditional_index(&d, 0, 0) != 0 { ok = false; }
      if gcov_unconditional_taken(&d, 0, 0) != 3 { ok = false; }
      if gcov_file_event_count(&d, 0) != 10 { ok = false; }
      if gcov_event_kind(&d, 0, 0) != GCOV_EV_FUNCTION { ok = false; }
      if gcov_event_kind(&d, 0, 1) != GCOV_EV_LINE { ok = false; }
      if gcov_event_kind(&d, 0, 2) != GCOV_EV_BRANCH { ok = false; }
      if gcov_event_kind(&d, 0, 3) != GCOV_EV_BRANCH { ok = false; }
      if gcov_event_kind(&d, 0, 4) != GCOV_EV_CALL { ok = false; }
      if gcov_event_kind(&d, 0, 5) != GCOV_EV_LINE { ok = false; }
      if gcov_event_kind(&d, 0, 6) != GCOV_EV_UNCONDITIONAL { ok = false; }
      if gcov_event_kind(&d, 0, 7) != GCOV_EV_LINE { ok = false; }
      if gcov_event_ref(&d, 0, 0) != 0 { ok = false; }
      if gcov_event_ref(&d, 0, 3) != 1 { ok = false; }
      if gcov_event_ref(&d, 0, 7) != 2 { ok = false; }
      if gcov_event_ref(&d, 0, 9) != 4 { ok = false; }
      if gcov_total_line_executable(&d) != 3 { ok = false; }
      if gcov_total_line_covered(&d) != 2 { ok = false; }
      if gcov_total_line_percent(&d) != 66 { ok = false; }
      if gcov_total_line_basis_points(&d) != 6666 { ok = false; }
      if gcov_total_branch_count(&d) != 2 { ok = false; }
      if gcov_total_branches_taken(&d) != 1 { ok = false; }
      if gcov_total_branch_percent(&d) != 50 { ok = false; }
      if gcov_total_function_count(&d) != 1 { ok = false; }
      if gcov_total_functions_called(&d) != 1 { ok = false; }
      if gcov_total_function_percent(&d) != 100 { ok = false; }
      if !streq(gcov_emit(&d), full_text()) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  if !round_trip(full_text()) { ok = false; }
  return assert(ok, "every record kind parses with aligned accessors, summaries and canonical emit");
}

fn t2() -> TestResult {
  let text = "-:0:Source:one.c\n1:1:a\n#####:2:b\n-:0:Source:two.c\n0:10:c\n";
  let r = gcov_parse(text);
  var ok = false;
  match r {
    Ok(d) => {
      ok = gcov_file_count(&d) == 2;
      if !streq(gcov_file_source(&d, 0), "one.c") { ok = false; }
      if !streq(gcov_file_source(&d, 1), "two.c") { ok = false; }
      if gcov_file_line_count(&d, 0) != 2 { ok = false; }
      if gcov_file_line_count(&d, 1) != 1 { ok = false; }
      if gcov_file_line_number(&d, 1, 0) != 10 { ok = false; }
      if gcov_file_line_count_value(&d, 1, 0) != 0 { ok = false; }
      if gcov_file_runs(&d, 1) != -1 { ok = false; }
      if gcov_file_has_graph(&d, 0) { ok = false; }
      if gcov_file_executable_lines(&d, 0) != 2 { ok = false; }
      if gcov_file_covered_lines(&d, 0) != 1 { ok = false; }
      if gcov_file_unexecuted_lines(&d, 0) != 1 { ok = false; }
      if gcov_file_line_percent(&d, 0) != 50 { ok = false; }
      if gcov_file_executable_lines(&d, 1) != 1 { ok = false; }
      if gcov_file_covered_lines(&d, 1) != 0 { ok = false; }
      if gcov_file_line_percent(&d, 1) != 0 { ok = false; }
      if gcov_file_unexecuted_lines(&d, 1) != 1 { ok = false; }
      if gcov_total_line_executable(&d) != 3 { ok = false; }
      if gcov_total_line_covered(&d) != 1 { ok = false; }
      if gcov_total_line_percent(&d) != 33 { ok = false; }
      if gcov_total_line_basis_points(&d) != 3333 { ok = false; }
      if !streq(gcov_emit(&d), text) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  if !round_trip(text) { ok = false; }
  return assert(ok, "per-file ranges index each section independently and totals pool them");
}

fn t3() -> TestResult {
  let text = "-:0:Source:p.c\n        1:   12:  x = 1;\n  12345:   13:  y();\n0:14:  maybe();\n";
  let wanted = "-:0:Source:p.c\n1:12:  x = 1;\n12345:13:  y();\n0:14:  maybe();\n";
  let r = gcov_parse(text);
  var ok = false;
  match r {
    Ok(d) => {
      ok = gcov_file_line_count(&d) == 3;
      if gcov_file_line_number(&d, 0, 0) != 12 { ok = false; }
      if gcov_file_line_number(&d, 0, 1) != 13 { ok = false; }
      if gcov_file_line_number(&d, 0, 2) != 14 { ok = false; }
      if gcov_file_line_count_value(&d, 0, 0) != 1 { ok = false; }
      if gcov_file_line_count_value(&d, 0, 1) != 12345 { ok = false; }
      if gcov_file_line_count_value(&d, 0, 2) != 0 { ok = false; }
      if !streq(gcov_file_line_source(&d, 0, 0), "  x = 1;") { ok = false; }
      if !gcov_line_executable(&d, 0, 2) { ok = false; }
      if gcov_line_covered(&d, 0, 2) { ok = false; }
      if gcov_file_covered_lines(&d, 0) != 2 { ok = false; }
      if gcov_file_line_percent(&d, 0) != 66 { ok = false; }
      if !streq(gcov_emit(&d), wanted) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  if !round_trip(text) { ok = false; }
  return assert(ok, "padded counts and line numbers parse; count 0 is executable but uncovered");
}

fn t4() -> TestResult {
  let text = "-:0:Source:n.c\n-:1:only code-less lines\n=====:2:not in source\n";
  let r = gcov_parse(text);
  var ok = false;
  match r {
    Ok(d) => {
      ok = gcov_file_executable_lines(&d, 0) == 0;
      if gcov_file_covered_lines(&d, 0) != 0 { ok = false; }
      if gcov_file_unexecuted_lines(&d, 0) != 0 { ok = false; }
      if gcov_file_line_percent(&d, 0) != 0 { ok = false; }
      if gcov_file_line_basis_points(&d, 0) != 0 { ok = false; }
      if gcov_total_line_percent(&d) != 0 { ok = false; }
      if gcov_line_executable(&d, 0, 0) { ok = false; }
      if gcov_line_executable(&d, 0, 1) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  if !round_trip(text) { ok = false; }
  return assert(ok, "no executable lines: percents are 0 and unexecuted is 0");
}

fn t5() -> TestResult {
  let text = "-:0:Source:b.c\nbranch 0 taken 0\nbranch 1 taken never\nbranch 2 never executed\nbranch 3 taken 5\nbranch 4 taken 00\n";
  let r = gcov_parse(text);
  var ok = false;
  match r {
    Ok(d) => {
      ok = gcov_file_branch_count(&d, 0) == 5;
      if gcov_branch_taken_count(&d, 0, 0) != 0 { ok = false; }
      if gcov_branch_taken_count(&d, 0, 1) != -1 { ok = false; }
      if gcov_branch_taken_count(&d, 0, 2) != -1 { ok = false; }
      if gcov_branch_taken_count(&d, 0, 3) != 5 { ok = false; }
      if gcov_branch_taken_count(&d, 0, 4) != 0 { ok = false; }
      if gcov_file_branches_taken(&d, 0) != 1 { ok = false; }
      if gcov_file_branch_percent(&d, 0) != 20 { ok = false; }
      if gcov_file_branch_basis_points(&d, 0) != 2000 { ok = false; }
      if !gcov_branch_covered(&d, 0, 3) { ok = false; }
      if gcov_branch_covered(&d, 0, 0) { ok = false; }
      if gcov_branch_covered(&d, 0, 1) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  if !round_trip(text) { ok = false; }
  return assert(ok, "all three branch forms and count 0 parse; only taken >= 1 counts");
}

fn t6() -> TestResult {
  let text = "-:0:Source:f.c\nfunction a called 0 returned 0% blocks executed 0%\nfunction b called 3 returned 50% blocks executed 100%\n";
  let r = gcov_parse(text);
  var ok = false;
  match r {
    Ok(d) => {
      ok = gcov_file_function_count(&d, 0) == 2;
      if !streq(gcov_function_name(&d, 0, 0), "a") { ok = false; }
      if !streq(gcov_function_name(&d, 0, 1), "b") { ok = false; }
      if gcov_function_called_count(&d, 0, 0) != 0 { ok = false; }
      if gcov_function_called_count(&d, 0, 1) != 3 { ok = false; }
      if gcov_function_returned_percent(&d, 0, 0) != 0 { ok = false; }
      if gcov_function_returned_percent(&d, 0, 1) != 50 { ok = false; }
      if gcov_function_blocks_percent(&d, 0, 0) != 0 { ok = false; }
      if gcov_function_blocks_percent(&d, 0, 1) != 100 { ok = false; }
      if gcov_function_covered(&d, 0, 0) { ok = false; }
      if !gcov_function_covered(&d, 0, 1) { ok = false; }
      if gcov_file_functions_called(&d, 0) != 1 { ok = false; }
      if gcov_file_function_percent(&d, 0) != 50 { ok = false; }
      if gcov_file_function_basis_points(&d, 0) != 5000 { ok = false; }
      if gcov_total_function_count(&d) != 2 { ok = false; }
      if gcov_total_functions_called(&d) != 1 { ok = false; }
      if gcov_total_function_percent(&d) != 50 { ok = false; }
      if gcov_total_function_basis_points(&d) != 5000 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  if !round_trip(text) { ok = false; }
  return assert(ok, "function summaries parse with called/returned/blocks and coverage math");
}

fn t7() -> TestResult {
  let text = "\r\n-:0:Source:a.c\r\n   \r\n\t\r\n1:1:x\r\n\r\n";
  let r = gcov_parse(text);
  var ok = false;
  match r {
    Ok(d) => {
      ok = gcov_file_count(&d) == 1;
      if gcov_file_line_count(&d, 0) != 1 { ok = false; }
      if !streq(gcov_emit(&d), "-:0:Source:a.c\n1:1:x\n") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  if !round_trip(text) { ok = false; }
  return assert(ok, "CRLF line endings and blank/whitespace-only lines are tolerated");
}

fn t8() -> TestResult {
  let text = "-:0:Source:m.c\n-:0:Runs:1\n-:0:Runs:7\n-:0:Graph:g1.gcno\n-:0:Graph:g2.gcno\n-:0:Data:d.gcda\n-:0:Programs:4\n";
  let wanted = "-:0:Source:m.c\n-:0:Graph:g2.gcno\n-:0:Data:d.gcda\n-:0:Runs:7\n-:0:Programs:4\n";
  let r = gcov_parse(text);
  var ok = false;
  match r {
    Ok(d) => {
      ok = gcov_file_count(&d) == 1;
      if gcov_file_runs(&d, 0) != 7 { ok = false; }
      if !streq(gcov_file_graph(&d, 0), "g2.gcno") { ok = false; }
      if !gcov_file_has_graph(&d, 0) { ok = false; }
      if !streq(gcov_file_data(&d, 0), "d.gcda") { ok = false; }
      if !gcov_file_has_data(&d, 0) { ok = false; }
      if gcov_file_programs(&d, 0) != 4 { ok = false; }
      if !streq(gcov_emit(&d), wanted) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  if !round_trip(text) { ok = false; }
  return assert(ok, "repeated metadata records last-win and are emitted once in canonical order");
}

fn t9() -> TestResult {
  let r1 = gcov_parse("");
  var ok = false;
  match r1 {
    Ok(d) => {
      ok = gcov_file_count(&d) == 0;
      if !streq(gcov_emit(&d), "") { ok = false; }
      if gcov_total_line_percent(&d) != 0 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let r2 = gcov_parse("\n \n\t\n\r\n");
  match r2 {
    Ok(d) => {
      if gcov_file_count(&d) != 0 { ok = false; }
      if !streq(gcov_emit(&d), "") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let r3 = gcov_parse("   \r\n\t \r\n");
  match r3 {
    Ok(d) => {
      if gcov_file_count(&d) != 0 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "empty and blank-only inputs parse to an empty document that emits nothing");
}

fn t10() -> TestResult {
  var ok = err_is("1:1:x\n", "coverage: record before Source at line 1 byte 0");
  if !err_is("-:0:Source:a.c\nfoo\n", "coverage: unknown record at line 2 byte 15") { ok = false; }
  if !err_is("-:0:Source:a.c\n-:0:Foo:1\n", "coverage: unknown metadata at line 2 byte 15") { ok = false; }
  if !err_is("-:0:Source:a.c\n12x:1:y\n", "coverage: malformed line record at line 2 byte 15") { ok = false; }
  if !err_is("-:0:Source:a.c\n1:x:y\n", "coverage: malformed line record at line 2 byte 15") { ok = false; }
  if !err_is("-:0:Source:a.c\n1000000001:1:x\n", "coverage: malformed line record at line 2 byte 15") { ok = false; }
  if !err_is("-:0:Source:a.c\n1:1\n", "coverage: malformed line record at line 2 byte 15") { ok = false; }
  if !err_is("1:0:Source:x\n", "coverage: malformed line record at line 1 byte 0") { ok = false; }
  if !err_is("#####:0:Source:x\n", "coverage: malformed line record at line 1 byte 0") { ok = false; }
  if !err_is("12345678901:1:x\n", "coverage: malformed line record at line 1 byte 0") { ok = false; }
  if !err_is("-:0:Source:\n", "coverage: bad metadata value at line 1 byte 0") { ok = false; }
  if !err_is("-:0:Graph:a.gcno\n", "coverage: record before Source at line 1 byte 0") { ok = false; }
  if !err_is("-:0:Source:a\n-:0:Runs:x\n", "coverage: bad metadata value at line 2 byte 13") { ok = false; }
  if !err_is("-:0:Source:a\n-:0:Data:\n", "coverage: bad metadata value at line 2 byte 13") { ok = false; }
  if !err_is("-:0:Source:a\nfunction main called 1 returned 100% blocks executed\n", "coverage: malformed function record at line 2 byte 13") { ok = false; }
  if !err_is("-:0:Source:a\nfunction called 1 returned 100% blocks executed 50%\n", "coverage: malformed function record at line 2 byte 13") { ok = false; }
  if !err_is("-:0:Source:a\nfunction f called 1 returned 101% blocks executed 50%\n", "coverage: malformed function record at line 2 byte 13") { ok = false; }
  if !err_is("-:0:Source:a\nbranch 0 taken x\n", "coverage: malformed branch record at line 2 byte 13") { ok = false; }
  if !err_is("-:0:Source:a\nbranch 0 maybe 1\n", "coverage: malformed branch record at line 2 byte 13") { ok = false; }
  if !err_is("-:0:Source:a\ncall 0 return 1\n", "coverage: malformed call record at line 2 byte 13") { ok = false; }
  if !err_is("-:0:Source:a\ncall 0 returned\n", "coverage: malformed call record at line 2 byte 13") { ok = false; }
  if !err_is("-:0:Source:a\nunconditional 0 take 1\n", "coverage: malformed unconditional record at line 2 byte 13") { ok = false; }
  if !err_is("-:0:Source:a\nbranch 0 taken 1\n1:1:x\nfunction f called 1 returned 10% blocks executed 10% extra\n", "coverage: malformed function record at line 4 byte 36") { ok = false; }
  return assert(ok, "the error catalog fires with exact messages and byte offsets");
}

fn t11() -> TestResult {
  let r = gcov_parse("-:0:Source:o.c\n1:1:a\nbranch 0 taken 1\n2:2:b\nfunction f called 1 returned 100% blocks executed 100%\n");
  var ok = false;
  match r {
    Ok(d) => {
      ok = gcov_file_event_count(&d, 0) == 4;
      if gcov_event_kind(&d, 0, 0) != GCOV_EV_LINE { ok = false; }
      if gcov_event_kind(&d, 0, 1) != GCOV_EV_BRANCH { ok = false; }
      if gcov_event_kind(&d, 0, 2) != GCOV_EV_LINE { ok = false; }
      if gcov_event_kind(&d, 0, 3) != GCOV_EV_FUNCTION { ok = false; }
      if gcov_event_ref(&d, 0, 1) != 0 { ok = false; }
      if gcov_event_ref(&d, 0, 3) != 0 { ok = false; }
      if !streq(gcov_emit(&d), "-:0:Source:o.c\n1:1:a\nbranch 0 taken 1\n2:2:b\nfunction f called 1 returned 100% blocks executed 100%\n") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  if !round_trip("-:0:Source:o.c\n1:1:a\nbranch 0 taken 1\n2:2:b\nfunction f called 1 returned 100% blocks executed 100%\n") { ok = false; }
  return assert(ok, "event store preserves the input stream order for the emitter");
}

fn t12() -> TestResult {
  let text = "-:0:Source:c.c\n       12:    5:  z\nbranch  0 taken never\nbranch 1 never executed\n";
  let wanted = "-:0:Source:c.c\n12:5:  z\nbranch 0 never executed\nbranch 1 never executed\n";
  let r = gcov_parse(text);
  var ok = false;
  match r {
    Ok(d) => {
      ok = gcov_file_line_count(&d, 0) == 1;
      if gcov_file_branch_count(&d, 0) != 2 { ok = false; }
      if gcov_branch_taken_count(&d, 0, 0) != -1 { ok = false; }
      if gcov_branch_taken_count(&d, 0, 1) != -1 { ok = false; }
      if !streq(gcov_emit(&d), wanted) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  if !round_trip(text) { ok = false; }
  return assert(ok, "emit canonicalizes padding and never-taken branch forms");
}

fn t13() -> TestResult {
  let text = "-:0:Source:a.c\nfunction a called 1 returned 100% blocks executed 100%\n1:1:x\nbranch 0 taken 1\n-:0:Source:b.c\nfunction b called 0 returned 0% blocks executed 0%\n1:1:y\n#####:2:z\n-:3:w\nbranch 0 taken 0\n";
  let r = gcov_parse(text);
  var ok = false;
  match r {
    Ok(d) => {
      ok = gcov_total_line_executable(&d) == 3;
      if gcov_total_line_covered(&d) != 2 { ok = false; }
      if gcov_total_line_percent(&d) != 66 { ok = false; }
      if gcov_total_line_basis_points(&d) != 6666 { ok = false; }
      if gcov_total_branch_count(&d) != 2 { ok = false; }
      if gcov_total_branches_taken(&d) != 1 { ok = false; }
      if gcov_total_branch_percent(&d) != 50 { ok = false; }
      if gcov_total_branch_basis_points(&d) != 5000 { ok = false; }
      if gcov_total_function_count(&d) != 2 { ok = false; }
      if gcov_total_functions_called(&d) != 1 { ok = false; }
      if gcov_total_function_percent(&d) != 50 { ok = false; }
      if gcov_total_function_basis_points(&d) != 5000 { ok = false; }
      if gcov_file_line_percent(&d, 0) != 100 { ok = false; }
      if gcov_file_line_percent(&d, 1) != 50 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  if !round_trip(text) { ok = false; }
  return assert(ok, "totals pool all files exactly instead of averaging per-file percents");
}

fn t14() -> TestResult {
  let text = "-:0:Source:u.c\nunconditional 0 taken\nunconditional 1 taken 9\ncall 0 returned 100%\ncall 1 returned never\n";
  let r = gcov_parse(text);
  var ok = false;
  match r {
    Ok(d) => {
      ok = gcov_file_unconditional_count(&d, 0) == 2;
      if gcov_unconditional_index(&d, 0, 0) != 0 { ok = false; }
      if gcov_unconditional_index(&d, 0, 1) != 1 { ok = false; }
      if gcov_unconditional_taken(&d, 0, 0) != -1 { ok = false; }
      if gcov_unconditional_taken(&d, 0, 1) != 9 { ok = false; }
      if gcov_file_call_count(&d, 0) != 2 { ok = false; }
      if gcov_call_index(&d, 0, 0) != 0 { ok = false; }
      if !streq(gcov_call_tail(&d, 0, 0), "100%") { ok = false; }
      if !streq(gcov_call_tail(&d, 0, 1), "never") { ok = false; }
      if !streq(gcov_emit(&d), text) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  if !round_trip(text) { ok = false; }
  return assert(ok, "call tails are verbatim and unconditional counts are optional");
}

fn t15() -> TestResult {
  let text = "-:0:Source:cap.c\n1000000000:1:x\n0:2:y\n#####:3:z\n";
  let r = gcov_parse(text);
  var ok = false;
  match r {
    Ok(d) => {
      ok = gcov_file_line_count_value(&d, 0, 0) == 1000000000;
      if gcov_file_executable_lines(&d, 0) != 3 { ok = false; }
      if gcov_file_covered_lines(&d, 0) != 1 { ok = false; }
      if gcov_file_line_percent(&d, 0) != 33 { ok = false; }
      if gcov_file_line_basis_points(&d, 0) != 3333 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  if !round_trip(text) { ok = false; }
  return assert(ok, "counts up to 1000000000 are accepted and math stays integral");
}

fn t16() -> TestResult {
  let text = "-:0:Source:src/ünïcode.c\nfunction función called 1 returned 100% blocks executed 50%\n1:1:héllo wörld\n";
  let r = gcov_parse(text);
  var ok = false;
  match r {
    Ok(d) => {
      ok = !streq(gcov_file_source(&d, 0), "");
      if !streq(gcov_file_source(&d, 0), "src/ünïcode.c") { ok = false; }
      if !streq(gcov_function_name(&d, 0, 0), "función") { ok = false; }
      if !streq(gcov_file_line_source(&d, 0, 0), "héllo wörld") { ok = false; }
      if !streq(gcov_emit(&d), text) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  if !round_trip(text) { ok = false; }
  return assert(ok, "multi-byte UTF-8 in paths, names and source text round-trips byte-exact");
}

fn t17() -> TestResult {
  let r = gcov_parse("-:0:Source:z.c\n1:1:a\nbranch 0 taken 1\nfunction f called 1 returned 50% blocks executed 50%\ncall 0 returned 1\nunconditional 0 taken 1\n");
  var ok = false;
  match r {
    Ok(d) => {
      ok = gcov_file_count(&d) == 1;
      if !streq(gcov_file_source(&d, 9), "") { ok = false; }
      if !streq(gcov_file_source(&d, -1), "") { ok = false; }
      if gcov_file_line_count(&d, 9) != 0 { ok = false; }
      if gcov_file_line_count_value(&d, 0, 9) != -1 { ok = false; }
      if gcov_file_line_number(&d, 0, -1) != -1 { ok = false; }
      if !streq(gcov_file_line_source(&d, 0, 9), "") { ok = false; }
      if gcov_line_executable(&d, 0, 9) { ok = false; }
      if gcov_line_covered(&d, 0, 9) { ok = false; }
      if gcov_file_branch_count(&d, 9) != 0 { ok = false; }
      if gcov_branch_index(&d, 0, 9) != -1 { ok = false; }
      if gcov_branch_taken_count(&d, 0, -1) != -1 { ok = false; }
      if gcov_file_function_count(&d, 9) != 0 { ok = false; }
      if !streq(gcov_function_name(&d, 0, 9), "") { ok = false; }
      if gcov_function_called_count(&d, 0, 9) != -1 { ok = false; }
      if gcov_function_returned_percent(&d, 0, 9) != -1 { ok = false; }
      if gcov_function_blocks_percent(&d, 0, 9) != -1 { ok = false; }
      if gcov_function_covered(&d, 0, 9) { ok = false; }
      if gcov_file_call_count(&d, 9) != 0 { ok = false; }
      if gcov_call_index(&d, 0, 9) != -1 { ok = false; }
      if !streq(gcov_call_tail(&d, 0, 9), "") { ok = false; }
      if gcov_file_unconditional_count(&d, 9) != 0 { ok = false; }
      if gcov_unconditional_index(&d, 0, 9) != -1 { ok = false; }
      if gcov_unconditional_taken(&d, 0, 9) != -1 { ok = false; }
      if gcov_file_event_count(&d, 9) != 0 { ok = false; }
      if gcov_event_kind(&d, 0, 9) != -1 { ok = false; }
      if gcov_event_ref(&d, 0, 9) != -1 { ok = false; }
      if !streq(gcov_file_graph(&d, 9), "") { ok = false; }
      if gcov_file_has_graph(&d, 9) { ok = false; }
      if !streq(gcov_file_data(&d, 9), "") { ok = false; }
      if gcov_file_has_data(&d, 9) { ok = false; }
      if gcov_file_runs(&d, 9) != -1 { ok = false; }
      if gcov_file_programs(&d, 9) != -1 { ok = false; }
      if gcov_file_executable_lines(&d, 9) != 0 { ok = false; }
      if gcov_file_covered_lines(&d, 9) != 0 { ok = false; }
      if gcov_file_unexecuted_lines(&d, 9) != 0 { ok = false; }
      if gcov_file_line_percent(&d, 9) != 0 { ok = false; }
      if gcov_file_branch_percent(&d, 9) != 0 { ok = false; }
      if gcov_file_function_percent(&d, 9) != 0 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  if !streq(gcov_emit(&gcov_doc_new()), "") { ok = false; }
  return assert(ok, "out-of-range accessors return their documented sentinels");
}

fn t18() -> TestResult {
  let text = "-:0:Source:fz.c\nfunction z called 007 returned 7% blocks executed 7%\n";
  let r = gcov_parse(text);
  var ok = false;
  match r {
    Ok(d) => {
      ok = gcov_function_called_count(&d, 0, 0) == 7;
      if gcov_function_returned_percent(&d, 0, 0) != 7 { ok = false; }
      if gcov_function_blocks_percent(&d, 0, 0) != 7 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  if !round_trip(text) { ok = false; }
  return assert(ok, "leading zeros in function counts are accepted");
}

fn t19() -> TestResult {
  let text = "-:0:Source:e.c\n1:1:a\n";
  var ok = round_trip(text);
  if !round_trip("-:0:Source:e.c\nbranch 0 taken 7\n") { ok = false; }
  if !round_trip("-:0:Source:e.c\ncall 0 returned 3\nunconditional 0 taken\n") { ok = false; }
  if !round_trip("-:0:Source:a.c\n-:0:Source:b.c\n") { ok = false; }
  if !round_trip("\r\n-:0:Source:a.c\r\n1:1:x\r\n") { ok = false; }
  if !round_trip(full_text()) { ok = false; }
  return assert(ok, "round trips preserve structure and emit is idempotent");
}

fn t20() -> TestResult {
  let r = gcov_parse("-:0:Source:s.c\n#####:1:a\n#####:2:b\n1:3:c\n");
  var ok = false;
  match r {
    Ok(d) => {
      ok = gcov_file_unexecuted_lines(&d, 0) == 2;
      if gcov_file_covered_lines(&d, 0) != 1 { ok = false; }
      if gcov_file_executable_lines(&d, 0) != 3 { ok = false; }
      if gcov_file_line_percent(&d, 0) != 33 { ok = false; }
      if gcov_file_line_basis_points(&d, 0) != 3333 { ok = false; }
      if gcov_total_line_percent(&d) != 33 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "unexecuted lines = executable - covered, with floor percents");
}

fn t21() -> TestResult {
  let r = gcov_parse("-:0:Source:t.c\n1:1:a\nbranch 0 taken 1\nbranch 1 taken 1\nbranch 2 taken 1\n");
  var ok = false;
  match r {
    Ok(d) => {
      ok = gcov_file_branch_percent(&d, 0) == 100;
      if gcov_file_branch_basis_points(&d, 0) != 10000 { ok = false; }
      if gcov_file_branches_taken(&d, 0) != 3 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let r2 = gcov_parse("-:0:Source:t.c\n-:1:a\n");
  match r2 {
    Ok(d) => {
      if gcov_file_branch_percent(&d, 0) != 0 { ok = false; }
      if gcov_total_branch_percent(&d) != 0 { ok = false; }
      if gcov_total_function_percent(&d) != 0 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "branch and function percents are 0 when there are no such records");
}

fn t22() -> TestResult {
  let text = "-:0:Source:d.c\n-:1:x\n=====:2:y\n1:3:z\nbranch 1 taken 2\nbranch 0 never executed\nfunction b called 2 returned 50% blocks executed 25%\nfunction a called 0 returned 100% blocks executed 100%\n";
  let r = gcov_parse(text);
  var ok = false;
  match r {
    Ok(d) => {
      ok = gcov_branch_index(&d, 0, 0) == 1;
      if gcov_branch_index(&d, 0, 1) != 0 { ok = false; }
      if !streq(gcov_function_name(&d, 0, 0), "b") { ok = false; }
      if !streq(gcov_function_name(&d, 0, 1), "a") { ok = false; }
      if gcov_file_line_number(&d, 0, 0) != 1 { ok = false; }
      if gcov_file_line_number(&d, 0, 2) != 3 { ok = false; }
      if !streq(gcov_emit(&d), text) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  if !round_trip(text) { ok = false; }
  return assert(ok, "record indices are stored verbatim and order is deterministic");
}

fn main() -> Int {
  io.println("=== xiom.coverage conformance tests ===");
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
    io.println("xiom.coverage: all tests passed");
  } else {
    io.println("xiom.coverage: tests failed");
  }
  return failed;
}
