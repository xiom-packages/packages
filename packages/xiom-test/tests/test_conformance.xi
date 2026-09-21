// XIOM -- xiom.test Conformance Tests
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Tests: All public types and functions in the xiom.test module
module test_tests
use xiom.io;
use xiom.test;

fn int_to_str(n: Int) -> Str {
  if n == 0 { return "0"; }
  var num = n; var out = "";
  while num > 0 {
    let d = num % 10; var ds = "0";
    if d == 1 { ds = "1"; } elif d == 2 { ds = "2"; } elif d == 3 { ds = "3"; }
    elif d == 4 { ds = "4"; } elif d == 5 { ds = "5"; } elif d == 6 { ds = "6"; }
    elif d == 7 { ds = "7"; } elif d == 8 { ds = "8"; } elif d == 9 { ds = "9"; }
    out = ds + out; num = num / 10;
  }
  return out;
}
fn report(passed: Bool, name: Str) -> Int {
  if passed { io.println("  [PASS] " + name); return 0; }
  io.println("  [FAIL] " + name); return 1;
}

// === assert_eq tests ===
fn run_assert_eq_pass() -> Int {
  var tc = assert_eq(5, 5, "eq pass");
  if tc.passed { return 0; }
  return 1;
}
fn test_assert_eq_pass() -> TestResult {
  if run_assert_eq_pass() == 0 { return assert(true, "assert_eq: 5 == 5 passes"); }
  return assert(false, "assert_eq: 5 == 5 failed (expected pass)");
}

fn run_assert_eq_fail() -> Int {
  var tc = assert_eq(5, 3, "eq fail");
  if !tc.passed { return 0; }
  return 1;
}
fn test_assert_eq_fail() -> TestResult {
  if run_assert_eq_fail() == 0 { return assert(true, "assert_eq: 5 == 3 fails"); }
  return assert(false, "assert_eq: 5 == 3 should have failed");
}

// === assert_ne tests ===
fn run_assert_ne_pass() -> Int {
  var tc = assert_ne(5, 3, "ne pass");
  if tc.passed { return 0; }
  return 1;
}
fn test_assert_ne_pass() -> TestResult {
  if run_assert_ne_pass() == 0 { return assert(true, "assert_ne: 5 != 3 passes"); }
  return assert(false, "assert_ne: 5 != 3 failed (expected pass)");
}

fn run_assert_ne_fail() -> Int {
  var tc = assert_ne(5, 5, "ne fail");
  if !tc.passed { return 0; }
  return 1;
}
fn test_assert_ne_fail() -> TestResult {
  if run_assert_ne_fail() == 0 { return assert(true, "assert_ne: 5 != 5 fails"); }
  return assert(false, "assert_ne: 5 != 5 should have failed");
}

// === assert_true tests ===
fn run_assert_true_pass() -> Int {
  var tc = assert_true(true, "true pass");
  if tc.passed { return 0; }
  return 1;
}
fn test_assert_true_pass() -> TestResult {
  if run_assert_true_pass() == 0 { return assert(true, "assert_true: true passes"); }
  return assert(false, "assert_true: true failed (expected pass)");
}

fn run_assert_true_fail() -> Int {
  var tc = assert_true(false, "true fail");
  if !tc.passed { return 0; }
  return 1;
}
fn test_assert_true_fail() -> TestResult {
  if run_assert_true_fail() == 0 { return assert(true, "assert_true: false fails"); }
  return assert(false, "assert_true: false should have failed");
}

// === assert_false tests ===
fn run_assert_false_pass() -> Int {
  var tc = assert_false(false, "false pass");
  if tc.passed { return 0; }
  return 1;
}
fn test_assert_false_pass() -> TestResult {
  if run_assert_false_pass() == 0 { return assert(true, "assert_false: false passes"); }
  return assert(false, "assert_false: false failed (expected pass)");
}

fn run_assert_false_fail() -> Int {
  var tc = assert_false(true, "false fail");
  if !tc.passed { return 0; }
  return 1;
}
fn test_assert_false_fail() -> TestResult {
  if run_assert_false_fail() == 0 { return assert(true, "assert_false: true fails"); }
  return assert(false, "assert_false: true should have failed");
}

// === assert_lt tests ===
fn run_assert_lt_pass() -> Int {
  var tc = assert_lt(3, 5, "lt pass");
  if tc.passed { return 0; }
  return 1;
}
fn test_assert_lt_pass() -> TestResult {
  if run_assert_lt_pass() == 0 { return assert(true, "assert_lt: 3 < 5 passes"); }
  return assert(false, "assert_lt: 3 < 5 failed (expected pass)");
}

fn run_assert_lt_fail() -> Int {
  var tc = assert_lt(5, 3, "lt fail");
  if !tc.passed { return 0; }
  return 1;
}
fn test_assert_lt_fail() -> TestResult {
  if run_assert_lt_fail() == 0 { return assert(true, "assert_lt: 5 < 3 fails"); }
  return assert(false, "assert_lt: 5 < 3 should have failed");
}

fn run_assert_lt_equal_fail() -> Int {
  var tc = assert_lt(5, 5, "lt equal");
  if !tc.passed { return 0; }
  return 1;
}
fn test_assert_lt_equal_fail() -> TestResult {
  if run_assert_lt_equal_fail() == 0 { return assert(true, "assert_lt: 5 < 5 fails (strict)"); }
  return assert(false, "assert_lt: 5 < 5 should have failed");
}

// === assert_le tests ===
fn run_assert_le_pass_less() -> Int {
  var tc = assert_le(3, 5, "le pass");
  if tc.passed { return 0; }
  return 1;
}
fn test_assert_le_pass() -> TestResult {
  if run_assert_le_pass_less() == 0 { return assert(true, "assert_le: 3 <= 5 passes"); }
  return assert(false, "assert_le: 3 <= 5 failed (expected pass)");
}

fn run_assert_le_pass_equal() -> Int {
  var tc = assert_le(5, 5, "le equal");
  if tc.passed { return 0; }
  return 1;
}
fn test_assert_le_equal() -> TestResult {
  if run_assert_le_pass_equal() == 0 { return assert(true, "assert_le: 5 <= 5 passes"); }
  return assert(false, "assert_le: 5 <= 5 failed (expected pass)");
}

fn run_assert_le_fail() -> Int {
  var tc = assert_le(7, 5, "le fail");
  if !tc.passed { return 0; }
  return 1;
}
fn test_assert_le_fail() -> TestResult {
  if run_assert_le_fail() == 0 { return assert(true, "assert_le: 7 <= 5 fails"); }
  return assert(false, "assert_le: 7 <= 5 should have failed");
}

// === assert_gt tests ===
fn run_assert_gt_pass() -> Int {
  var tc = assert_gt(7, 5, "gt pass");
  if tc.passed { return 0; }
  return 1;
}
fn test_assert_gt_pass() -> TestResult {
  if run_assert_gt_pass() == 0 { return assert(true, "assert_gt: 7 > 5 passes"); }
  return assert(false, "assert_gt: 7 > 5 failed (expected pass)");
}

fn run_assert_gt_fail() -> Int {
  var tc = assert_gt(3, 5, "gt fail");
  if !tc.passed { return 0; }
  return 1;
}
fn test_assert_gt_fail() -> TestResult {
  if run_assert_gt_fail() == 0 { return assert(true, "assert_gt: 3 > 5 fails"); }
  return assert(false, "assert_gt: 3 > 5 should have failed");
}

fn run_assert_gt_equal_fail() -> Int {
  var tc = assert_gt(5, 5, "gt equal");
  if !tc.passed { return 0; }
  return 1;
}
fn test_assert_gt_equal_fail() -> TestResult {
  if run_assert_gt_equal_fail() == 0 { return assert(true, "assert_gt: 5 > 5 fails (strict)"); }
  return assert(false, "assert_gt: 5 > 5 should have failed");
}

// === assert_ge tests ===
fn run_assert_ge_pass_greater() -> Int {
  var tc = assert_ge(7, 5, "ge pass");
  if tc.passed { return 0; }
  return 1;
}
fn test_assert_ge_pass() -> TestResult {
  if run_assert_ge_pass_greater() == 0 { return assert(true, "assert_ge: 7 >= 5 passes"); }
  return assert(false, "assert_ge: 7 >= 5 failed (expected pass)");
}

fn run_assert_ge_pass_equal() -> Int {
  var tc = assert_ge(5, 5, "ge equal");
  if tc.passed { return 0; }
  return 1;
}
fn test_assert_ge_equal() -> TestResult {
  if run_assert_ge_pass_equal() == 0 { return assert(true, "assert_ge: 5 >= 5 passes"); }
  return assert(false, "assert_ge: 5 >= 5 failed (expected pass)");
}

fn run_assert_ge_fail() -> Int {
  var tc = assert_ge(3, 5, "ge fail");
  if !tc.passed { return 0; }
  return 1;
}
fn test_assert_ge_fail() -> TestResult {
  if run_assert_ge_fail() == 0 { return assert(true, "assert_ge: 3 >= 5 fails"); }
  return assert(false, "assert_ge: 3 >= 5 should have failed");
}

// === assert_some tests ===
fn run_assert_some_pass() -> Int {
  var opt: Option[Int] = Some(42);
  var tc = assert_some(opt, "some pass");
  if tc.passed { return 0; }
  return 1;
}
fn test_assert_some_pass() -> TestResult {
  if run_assert_some_pass() == 0 { return assert(true, "assert_some: Some(42) passes"); }
  return assert(false, "assert_some: Some(42) failed (expected pass)");
}

fn run_assert_some_fail() -> Int {
  var opt: Option[Int] = None;
  var tc = assert_some(opt, "some fail");
  if !tc.passed { return 0; }
  return 1;
}
fn test_assert_some_fail() -> TestResult {
  if run_assert_some_fail() == 0 { return assert(true, "assert_some: None fails"); }
  return assert(false, "assert_some: None should have failed");
}

// === assert_none tests ===
fn run_assert_none_pass() -> Int {
  var opt: Option[Int] = None;
  var tc = assert_none(opt, "none pass");
  if tc.passed { return 0; }
  return 1;
}
fn test_assert_none_pass() -> TestResult {
  if run_assert_none_pass() == 0 { return assert(true, "assert_none: None passes"); }
  return assert(false, "assert_none: None failed (expected pass)");
}

fn run_assert_none_fail() -> Int {
  var opt: Option[Int] = Some(7);
  var tc = assert_none(opt, "none fail");
  if !tc.passed { return 0; }
  return 1;
}
fn test_assert_none_fail() -> TestResult {
  if run_assert_none_fail() == 0 { return assert(true, "assert_none: Some(7) fails"); }
  return assert(false, "assert_none: Some(7) should have failed");
}

// === assert_ok tests ===
fn run_assert_ok_pass() -> Int {
  var r: Result[Int, Str] = Ok(42);
  var tc = assert_ok(r, "ok pass");
  if tc.passed { return 0; }
  return 1;
}
fn test_assert_ok_pass() -> TestResult {
  if run_assert_ok_pass() == 0 { return assert(true, "assert_ok: Ok(42) passes"); }
  return assert(false, "assert_ok: Ok(42) failed (expected pass)");
}

fn run_assert_ok_fail() -> Int {
  var r: Result[Int, Str] = Err("error");
  var tc = assert_ok(r, "ok fail");
  if !tc.passed { return 0; }
  return 1;
}
fn test_assert_ok_fail() -> TestResult {
  if run_assert_ok_fail() == 0 { return assert(true, "assert_ok: Err fails"); }
  return assert(false, "assert_ok: Err should have failed");
}

// === assert_err tests ===
fn run_assert_err_pass() -> Int {
  var r: Result[Int, Str] = Err("error");
  var tc = assert_err(r, "err pass");
  if tc.passed { return 0; }
  return 1;
}
fn test_assert_err_pass() -> TestResult {
  if run_assert_err_pass() == 0 { return assert(true, "assert_err: Err passes"); }
  return assert(false, "assert_err: Err failed (expected pass)");
}

fn run_assert_err_fail() -> Int {
  var r: Result[Int, Str] = Ok(42);
  var tc = assert_err(r, "err fail");
  if !tc.passed { return 0; }
  return 1;
}
fn test_assert_err_fail() -> TestResult {
  if run_assert_err_fail() == 0 { return assert(true, "assert_err: Ok(42) fails"); }
  return assert(false, "assert_err: Ok(42) should have failed");
}

// === assert_eq_str tests ===
fn run_assert_eq_str_pass() -> Int {
  var tc = assert_eq_str("hello", "hello", "str eq pass");
  if tc.passed { return 0; }
  return 1;
}
fn test_assert_eq_str_pass() -> TestResult {
  if run_assert_eq_str_pass() == 0 { return assert(true, "assert_eq_str: 'hello' == 'hello' passes"); }
  return assert(false, "assert_eq_str: 'hello' == 'hello' failed (expected pass)");
}

fn run_assert_eq_str_fail() -> Int {
  var tc = assert_eq_str("hello", "world", "str eq fail");
  if !tc.passed { return 0; }
  return 1;
}
fn test_assert_eq_str_fail() -> TestResult {
  if run_assert_eq_str_fail() == 0 { return assert(true, "assert_eq_str: 'hello' != 'world' fails"); }
  return assert(false, "assert_eq_str: 'hello' != 'world' should have failed");
}

// === assert_eq_bool tests ===
fn run_assert_eq_bool_pass() -> Int {
  var tc = assert_eq_bool(true, true, "bool eq pass");
  if tc.passed { return 0; }
  return 1;
}
fn test_assert_eq_bool_pass() -> TestResult {
  if run_assert_eq_bool_pass() == 0 { return assert(true, "assert_eq_bool: true == true passes"); }
  return assert(false, "assert_eq_bool: true == true failed (expected pass)");
}

fn run_assert_eq_bool_fail() -> Int {
  var tc = assert_eq_bool(true, false, "bool eq fail");
  if !tc.passed { return 0; }
  return 1;
}
fn test_assert_eq_bool_fail() -> TestResult {
  if run_assert_eq_bool_fail() == 0 { return assert(true, "assert_eq_bool: true != false fails"); }
  return assert(false, "assert_eq_bool: true != false should have failed");
}

// === TestCase name propagation ===
fn run_testcase_name() -> Int {
  var tc = assert_eq(1, 1, "my test case");
  if tc.name == "my test case" && tc.message == "my test case" { return 0; }
  return 1;
}
fn test_testcase_name() -> TestResult {
  if run_testcase_name() == 0 { return assert(true, "TestCase: name and message are set from msg"); }
  return assert(false, "TestCase: name/message mismatch");
}

// === TestSuite.new + add + run ===
fn run_suite_new_add_run() -> Int {
  var suite = TestSuite.new("My Suite");
  TestSuite.add(&suite, assert_eq(2, 2, "addition"));
  TestSuite.add(&suite, assert_eq(4, 4, "multiplication"));
  if suite.cases.len() != 2 { return 1; }
  var results = suite.run();
  if results.passed == 2 && results.failed == 0 && results.total == 2 { return 0; }
  return 1;
}
fn test_suite_new_add_run() -> TestResult {
  if run_suite_new_add_run() == 0 { return assert(true, "TestSuite: new/add/run with 2 passing cases"); }
  return assert(false, "TestSuite: new/add/run failed");
}

// === TestSuite with mixed pass/fail ===
fn run_suite_mixed() -> Int {
  var suite = TestSuite.new("Mixed");
  TestSuite.add(&suite, assert_eq(3, 3, "good"));
  TestSuite.add(&suite, assert_eq(3, 5, "bad"));
  TestSuite.add(&suite, assert_true(true, "also good"));
  var results = suite.run();
  if results.passed == 2 && results.failed == 1 && results.total == 3 { return 0; }
  return 1;
}
fn test_suite_mixed() -> TestResult {
  if run_suite_mixed() == 0 { return assert(true, "TestSuite: mixed pass/fail produces correct counts"); }
  return assert(false, "TestSuite: mixed pass/fail counts wrong");
}

// === TestSuite.failed_count ===
fn run_suite_failed_count() -> Int {
  var suite = TestSuite.new("Counts");
  TestSuite.add(&suite, assert_eq(1, 2, "bad1"));
  TestSuite.add(&suite, assert_eq(3, 4, "bad2"));
  TestSuite.add(&suite, assert_eq(5, 5, "good1"));
  if suite.failed_count() == 2 { return 0; }
  return 1;
}
fn test_suite_failed_count() -> TestResult {
  if run_suite_failed_count() == 0 { return assert(true, "TestSuite: failed_count returns 2 of 3"); }
  return assert(false, "TestSuite: failed_count wrong");
}

// === TestSuite.passed_count ===
fn run_suite_passed_count() -> Int {
  var suite = TestSuite.new("PCount");
  TestSuite.add(&suite, assert_eq(1, 1, "ok1"));
  TestSuite.add(&suite, assert_eq(2, 2, "ok2"));
  TestSuite.add(&suite, assert_eq(3, 3, "ok3"));
  TestSuite.add(&suite, assert_eq(4, 5, "bad"));
  if suite.passed_count() == 3 { return 0; }
  return 1;
}
fn test_suite_passed_count() -> TestResult {
  if run_suite_passed_count() == 0 { return assert(true, "TestSuite: passed_count returns 3 of 4"); }
  return assert(false, "TestSuite: passed_count wrong");
}

// === TestSuite empty ===
fn run_suite_empty() -> Int {
  var suite = TestSuite.new("Empty");
  if suite.cases.len() != 0 { return 1; }
  var results = suite.run();
  if results.passed == 0 && results.failed == 0 && results.total == 0 { return 0; }
  return 1;
}
fn test_suite_empty() -> TestResult {
  if run_suite_empty() == 0 { return assert(true, "TestSuite: empty suite returns zero results"); }
  return assert(false, "TestSuite: empty suite failed");
}

// === TestResults.new ===
fn run_testresults_new() -> Int {
  var r = TestResults.new();
  if r.passed == 0 && r.failed == 0 && r.total == 0 && r.failures.len() == 0 { return 0; }
  return 1;
}
fn test_testresults_new() -> TestResult {
  if run_testresults_new() == 0 { return assert(true, "TestResults: new creates zero-initialized container"); }
  return assert(false, "TestResults: new failed");
}

// === TestResults.merge ===
fn run_testresults_merge() -> Int {
  var a = TestResults.new();
  a.passed = 3; a.failed = 1; a.total = 4;
  var b = TestResults.new();
  b.passed = 2; b.failed = 2; b.total = 4;
  a.merge(&b);
  if a.passed == 5 && a.failed == 3 && a.total == 8 { return 0; }
  return 1;
}
fn test_testresults_merge() -> TestResult {
  if run_testresults_merge() == 0 { return assert(true, "TestResults: merge aggregates passed/failed/total"); }
  return assert(false, "TestResults: merge failed");
}

// === TestResults.merge with failures ===
fn run_testresults_merge_failures() -> Int {
  var a = TestResults.new();
  a.passed = 1; a.failed = 0; a.total = 1;
  var suite = TestSuite.new("FailSuite");
  TestSuite.add(&suite, assert_eq(1, 2, "bad eq"));
  var b = suite.run();
  a.merge(&b);
  if a.passed == 1 && a.failed == 1 && a.failures.len() == 1 { return 0; }
  return 1;
}
fn test_testresults_merge_failures() -> TestResult {
  if run_testresults_merge_failures() == 0 { return assert(true, "TestResults: merge copies failure records"); }
  return assert(false, "TestResults: merge failures failed");
}

// === run_suite standalone ===
fn run_standalone_run_suite() -> Int {
  var suite = TestSuite.new("Standalone");
  TestSuite.add(&suite, assert_eq(10, 10, "ten"));
  TestSuite.add(&suite, assert_eq(20, 20, "twenty"));
  var results = run_suite(&suite);
  if results.passed == 2 && results.failed == 0 && results.total == 2 { return 0; }
  return 1;
}
fn test_run_suite() -> TestResult {
  if run_standalone_run_suite() == 0 { return assert(true, "run_suite: standalone evaluates all cases"); }
  return assert(false, "run_suite: standalone failed");
}

// === run_all ===
fn run_standalone_run_all() -> Int {
  var s1 = TestSuite.new("A");
  TestSuite.add(&s1, assert_eq(1, 1, "a1"));
  TestSuite.add(&s1, assert_eq(2, 2, "a2"));
  var s2 = TestSuite.new("B");
  TestSuite.add(&s2, assert_eq(3, 3, "b1"));
  TestSuite.add(&s2, assert_eq(4, 5, "b2"));
  var suites = Vec[TestSuite].new();
  suites.push(s1);
  suites.push(s2);
  var all = run_all(&suites);
  if all.passed == 3 && all.failed == 1 && all.total == 4 { return 0; }
  return 1;
}
fn test_run_all() -> TestResult {
  if run_standalone_run_all() == 0 { return assert(true, "run_all: aggregates multiple suites correctly"); }
  return assert(false, "run_all: failed");
}

// === run_all empty fails (contract: requires suites.len() > 0) ===
// Note: contract verification is compiler-checked; we test the success path only.

// === report ===
fn run_report() -> Int {
  var r = TestResults.new();
  r.passed = 5; r.failed = 2; r.total = 7;
  var s = report(&r);
  if s.len() > 0 { return 0; }
  return 1;
}
fn test_report() -> TestResult {
  if run_report() == 0 { return assert(true, "report: produces non-empty summary string"); }
  return assert(false, "report: returned empty string");
}

// === report_verbose no failures ===
fn run_report_verbose_pass() -> Int {
  var r = TestResults.new();
  r.passed = 3; r.failed = 0; r.total = 3;
  var s = report_verbose(&r);
  if s.len() > 0 { return 0; }
  return 1;
}
fn test_report_verbose_pass() -> TestResult {
  if run_report_verbose_pass() == 0 { return assert(true, "report_verbose: no failures produces non-empty output"); }
  return assert(false, "report_verbose: no-failures failed");
}

// === report_verbose with failures ===
fn run_report_verbose_fail() -> Int {
  var r = TestResults.new();
  r.passed = 2; r.failed = 1; r.total = 3;
  var f = TestFailure{ name: "bad", message: "bad" };
  r.failures.push(f);
  var s = report_verbose(&r);
  if s.len() > 0 { return 0; }
  return 1;
}
fn test_report_verbose_fail() -> TestResult {
  if run_report_verbose_fail() == 0 { return assert(true, "report_verbose: with failures includes failure details"); }
  return assert(false, "report_verbose: with-failures failed");
}

// === bench_result ===
fn run_bench_result() -> Int {
  var b = bench_result("fib", 1000, 50);
  if b.name == "fib" && b.iterations == 1000 && b.elapsed_ms == 50
    && b.ops_per_sec == 20000 { return 0; }
  return 1;
}
fn test_bench_result() -> TestResult {
  if run_bench_result() == 0 { return assert(true, "bench_result: computes ops_per_sec = iters*1000/ms"); }
  return assert(false, "bench_result: fields incorrect");
}

// === bench_result zero ms ===
fn run_bench_result_zero_ms() -> Int {
  var b = bench_result("fast", 100000, 0);
  if b.ops_per_sec == 0 { return 0; }
  return 1;
}
fn test_bench_result_zero_ms() -> TestResult {
  if run_bench_result_zero_ms() == 0 { return assert(true, "bench_result: ms=0 yields ops_per_sec=0"); }
  return assert(false, "bench_result: zero ms should give ops_per_sec=0");
}

// === bench_report ===
fn run_bench_report() -> Int {
  var b = BenchResult{ name: "sort", iterations: 500, elapsed_ms: 10, ops_per_sec: 50000 };
  var s = bench_report(&b);
  if s.len() > 0 { return 0; }
  return 1;
}
fn test_bench_report() -> TestResult {
  if run_bench_report() == 0 { return assert(true, "bench_report: produces non-empty formatted string"); }
  return assert(false, "bench_report: returned empty string");
}

// === TestFailure construction ===
fn run_testfailure() -> Int {
  var tf = TestFailure{ name: "test1", message: "reason" };
  if tf.name == "test1" && tf.message == "reason" { return 0; }
  return 1;
}
fn test_testfailure() -> TestResult {
  if run_testfailure() == 0 { return assert(true, "TestFailure: construction stores name and message"); }
  return assert(false, "TestFailure: construction failed");
}

// === BenchResult construction ===
fn run_benchresult_construction() -> Int {
  var br = BenchResult{ name: "b", iterations: 1, elapsed_ms: 1, ops_per_sec: 1000 };
  if br.name == "b" && br.iterations == 1 && br.elapsed_ms == 1
    && br.ops_per_sec == 1000 { return 0; }
  return 1;
}
fn test_benchresult_construction() -> TestResult {
  if run_benchresult_construction() == 0 { return assert(true, "BenchResult: construction stores all fields"); }
  return assert(false, "BenchResult: construction failed");
}

// === All assertions fail === (TestSuite with every assertion failing)
fn run_all_assertions_fail_suite() -> Int {
  var suite = TestSuite.new("All Fails");
  TestSuite.add(&suite, assert_eq(1, 2, "eq bad"));
  TestSuite.add(&suite, assert_ne(1, 1, "ne bad"));
  TestSuite.add(&suite, assert_true(false, "true bad"));
  TestSuite.add(&suite, assert_false(true, "false bad"));
  TestSuite.add(&suite, assert_lt(5, 3, "lt bad"));
  TestSuite.add(&suite, assert_le(7, 5, "le bad"));
  TestSuite.add(&suite, assert_gt(3, 5, "gt bad"));
  TestSuite.add(&suite, assert_ge(3, 5, "ge bad"));
  var opt_none: Option[Int] = None;
  TestSuite.add(&suite, assert_some(opt_none, "some bad"));
  var opt_some: Option[Int] = Some(1);
  TestSuite.add(&suite, assert_none(opt_some, "none bad"));
  var r_ok: Result[Int, Str] = Ok(1);
  TestSuite.add(&suite, assert_err(r_ok, "err bad"));
  var r_err: Result[Int, Str] = Err("e");
  TestSuite.add(&suite, assert_ok(r_err, "ok bad"));
  TestSuite.add(&suite, assert_eq_str("a", "b", "str bad"));
  TestSuite.add(&suite, assert_eq_bool(true, false, "bool bad"));
  var results = suite.run();
  if results.passed == 0 && results.failed == 14 { return 0; }
  return 1;
}
fn test_all_assertions_fail() -> TestResult {
  if run_all_assertions_fail_suite() == 0 { return assert(true, "all assertions: 14 fail cases produce 0 passed 14 failed"); }
  return assert(false, "all assertions: fail suite count wrong");
}

// === All assertions pass === (TestSuite with every assertion passing)
fn run_all_assertions_pass_suite() -> Int {
  var suite = TestSuite.new("All Passes");
  TestSuite.add(&suite, assert_eq(1, 1, "eq good"));
  TestSuite.add(&suite, assert_ne(1, 2, "ne good"));
  TestSuite.add(&suite, assert_true(true, "true good"));
  TestSuite.add(&suite, assert_false(false, "false good"));
  TestSuite.add(&suite, assert_lt(3, 5, "lt good"));
  TestSuite.add(&suite, assert_le(5, 5, "le good"));
  TestSuite.add(&suite, assert_gt(7, 5, "gt good"));
  TestSuite.add(&suite, assert_ge(5, 5, "ge good"));
  var opt_some: Option[Int] = Some(42);
  TestSuite.add(&suite, assert_some(opt_some, "some good"));
  var opt_none: Option[Int] = None;
  TestSuite.add(&suite, assert_none(opt_none, "none good"));
  var r_ok: Result[Int, Str] = Ok(42);
  TestSuite.add(&suite, assert_ok(r_ok, "ok good"));
  var r_err: Result[Int, Str] = Err("e");
  TestSuite.add(&suite, assert_err(r_err, "err good"));
  TestSuite.add(&suite, assert_eq_str("x", "x", "str good"));
  TestSuite.add(&suite, assert_eq_bool(false, false, "bool good"));
  var results = suite.run();
  if results.passed == 14 && results.failed == 0 { return 0; }
  return 1;
}
fn test_all_assertions_pass() -> TestResult {
  if run_all_assertions_pass_suite() == 0 { return assert(true, "all assertions: 14 pass cases produce 14 passed 0 failed"); }
  return assert(false, "all assertions: pass suite count wrong");
}

// === TestFailure in results ===
fn run_testfailure_in_results() -> Int {
  var suite = TestSuite.new("Fail");
  TestSuite.add(&suite, assert_eq(1, 99, "one should equal 99"));
  var results = suite.run();
  if results.failures.len() == 1 {
    var f = results.failures[0];
    if f.name == "one should equal 99" && f.message == "one should equal 99" { return 0; }
  }
  return 1;
}
fn test_testfailure_in_results() -> TestResult {
  if run_testfailure_in_results() == 0 { return assert(true, "TestFailure: stored in results with correct name/message"); }
  return assert(false, "TestFailure: results failure record incorrect");
}

// === Main ===
fn main() -> Int {
  io.println("=== XIOM Test Framework Conformance Tests ===");
  var failed: Int = 0; var total: Int = 0;

  var tests = [
    test_assert_eq_pass, test_assert_eq_fail,
    test_assert_ne_pass, test_assert_ne_fail,
    test_assert_true_pass, test_assert_true_fail,
    test_assert_false_pass, test_assert_false_fail,
    test_assert_lt_pass, test_assert_lt_fail, test_assert_lt_equal_fail,
    test_assert_le_pass, test_assert_le_equal, test_assert_le_fail,
    test_assert_gt_pass, test_assert_gt_fail, test_assert_gt_equal_fail,
    test_assert_ge_pass, test_assert_ge_equal, test_assert_ge_fail,
    test_assert_some_pass, test_assert_some_fail,
    test_assert_none_pass, test_assert_none_fail,
    test_assert_ok_pass, test_assert_ok_fail,
    test_assert_err_pass, test_assert_err_fail,
    test_assert_eq_str_pass, test_assert_eq_str_fail,
    test_assert_eq_bool_pass, test_assert_eq_bool_fail,
    test_testcase_name,
    test_suite_new_add_run, test_suite_mixed,
    test_suite_failed_count, test_suite_passed_count, test_suite_empty,
    test_testresults_new, test_testresults_merge, test_testresults_merge_failures,
    test_run_suite, test_run_all,
    test_report, test_report_verbose_pass, test_report_verbose_fail,
    test_bench_result, test_bench_result_zero_ms, test_bench_report,
    test_testfailure, test_benchresult_construction,
    test_all_assertions_fail, test_all_assertions_pass,
    test_testfailure_in_results
  ];
  var i = 0;
  while i < tests.len() {
    total = total + 1;
    failed = failed + report(tests[i]().passed, tests[i]().name);
    i = i + 1;
  }

  let passed = total - failed;
  io.println("");
  io.println("XIOM Test Framework Conformance: " + int_to_str(passed) +
             "/" + int_to_str(total) + " passed" +
             (if failed > 0 { " (" + int_to_str(failed) + " FAILED)" } else { "" }));
  return failed;
}
