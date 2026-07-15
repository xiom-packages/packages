module xiom.test

use xiom.fmt;
use xiom.string;
use xiom.convert;

pub type TestFailure = {
  name: Str;
  message: Str;
} derive[Clone]

pub type TestResults = {
  passed: Int;
  failed: Int;
  total: Int;
  failures: Vec[TestFailure];
} derive[Clone]

pub type TestCase = {
  name: Str;
  passed: Bool;
  message: Str;
}

pub type TestSuite = {
  name: Str;
  cases: Vec[TestCase];
}

pub type BenchResult = {
  name: Str;
  iterations: Int;
  elapsed_ms: Int;
  ops_per_sec: Int;
}

pub fn TestResults.new() -> TestResults
ensures: result.passed == 0 && result.failed == 0
{
  return TestResults{
    passed: 0,
    failed: 0,
    total: 0,
    failures: Vec[TestFailure].new(),
  };
}

pub fn TestResults.merge(other: &TestResults) {
  passed = passed + other.passed;
  failed = failed + other.failed;
  total = passed + failed;
  var i: Int = 0;
  while i < other.failures.len() {
    var f = other.failures[i];
    failures.push(TestFailure{ name: f.name, message: f.message });
    i = i + 1;
  }
}

pub fn TestSuite.new(name: Str) -> TestSuite
requires: name.len() > 0
{
  return TestSuite{
    name: name,
    cases: Vec[TestCase].new(),
  };
}

pub fn TestSuite.add(suite: &mut TestSuite, case: TestCase) {
  suite.cases.push(case);
}

pub fn TestSuite.run() -> TestResults {
  var results = TestResults.new();
  var i: Int = 0;
  while i < cases.len() {
    var c = cases[i];
    if c.passed {
      results.passed = results.passed + 1;
    } else {
      results.failed = results.failed + 1;
      results.failures.push(TestFailure{ name: c.name, message: c.message });
    }
    i = i + 1;
  }
  results.total = results.passed + results.failed;
  return results;
}

pub fn TestSuite.failed_count() -> Int {
  var count: Int = 0;
  var i: Int = 0;
  while i < cases.len() {
    var c = cases[i];
    if !c.passed {
      count = count + 1;
    }
    i = i + 1;
  }
  return count;
}

pub fn TestSuite.passed_count() -> Int {
  var count: Int = 0;
  var i: Int = 0;
  while i < cases.len() {
    var c = cases[i];
    if c.passed {
      count = count + 1;
    }
    i = i + 1;
  }
  return count;
}

pub fn assert_eq(actual: Int, expected: Int, msg: Str) -> TestCase
requires: msg.len() > 0
{
  if actual == expected {
    return TestCase{ name: msg, passed: true, message: msg };
  } else {
    return TestCase{ name: msg, passed: false, message: msg };
  }
}

pub fn assert_ne(actual: Int, expected: Int, msg: Str) -> TestCase
requires: msg.len() > 0
{
  if actual != expected {
    return TestCase{ name: msg, passed: true, message: msg };
  } else {
    return TestCase{ name: msg, passed: false, message: msg };
  }
}

pub fn assert_true(condition: Bool, msg: Str) -> TestCase
requires: msg.len() > 0
{
  if condition {
    return TestCase{ name: msg, passed: true, message: msg };
  } else {
    return TestCase{ name: msg, passed: false, message: msg };
  }
}

pub fn assert_false(condition: Bool, msg: Str) -> TestCase
requires: msg.len() > 0
{
  if !condition {
    return TestCase{ name: msg, passed: true, message: msg };
  } else {
    return TestCase{ name: msg, passed: false, message: msg };
  }
}

pub fn assert_lt(actual: Int, expected: Int, msg: Str) -> TestCase
requires: msg.len() > 0
{
  if actual < expected {
    return TestCase{ name: msg, passed: true, message: msg };
  } else {
    return TestCase{ name: msg, passed: false, message: msg };
  }
}

pub fn assert_le(actual: Int, expected: Int, msg: Str) -> TestCase
requires: msg.len() > 0
{
  if actual <= expected {
    return TestCase{ name: msg, passed: true, message: msg };
  } else {
    return TestCase{ name: msg, passed: false, message: msg };
  }
}

pub fn assert_gt(actual: Int, expected: Int, msg: Str) -> TestCase
requires: msg.len() > 0
{
  if actual > expected {
    return TestCase{ name: msg, passed: true, message: msg };
  } else {
    return TestCase{ name: msg, passed: false, message: msg };
  }
}

pub fn assert_ge(actual: Int, expected: Int, msg: Str) -> TestCase
requires: msg.len() > 0
{
  if actual >= expected {
    return TestCase{ name: msg, passed: true, message: msg };
  } else {
    return TestCase{ name: msg, passed: false, message: msg };
  }
}

pub fn assert_some(opt: Option[Int], msg: Str) -> TestCase
requires: msg.len() > 0
{
  match opt {
    Some(val) => {
      return TestCase{ name: msg, passed: true, message: msg };
    }
    None => {
      return TestCase{ name: msg, passed: false, message: msg };
    }
  }
}

pub fn assert_none(opt: Option[Int], msg: Str) -> TestCase
requires: msg.len() > 0
{
  match opt {
    Some(val) => {
      return TestCase{ name: msg, passed: false, message: msg };
    }
    None => {
      return TestCase{ name: msg, passed: true, message: msg };
    }
  }
}

pub fn assert_ok(result: Result[Int, Str], msg: Str) -> TestCase
requires: msg.len() > 0
{
  match result {
    Ok(val) => {
      return TestCase{ name: msg, passed: true, message: msg };
    }
    Err(e) => {
      return TestCase{ name: msg, passed: false, message: msg };
    }
  }
}

pub fn assert_err(result: Result[Int, Str], msg: Str) -> TestCase
requires: msg.len() > 0
{
  match result {
    Ok(val) => {
      return TestCase{ name: msg, passed: false, message: msg };
    }
    Err(e) => {
      return TestCase{ name: msg, passed: true, message: msg };
    }
  }
}

pub fn assert_eq_str(actual: Str, expected: Str, msg: Str) -> TestCase
requires: msg.len() > 0
{
  if actual == expected {
    return TestCase{ name: msg, passed: true, message: msg };
  } else {
    return TestCase{ name: msg, passed: false, message: msg };
  }
}

pub fn assert_eq_bool(actual: Bool, expected: Bool, msg: Str) -> TestCase
requires: msg.len() > 0
{
  if actual == expected {
    return TestCase{ name: msg, passed: true, message: msg };
  } else {
    return TestCase{ name: msg, passed: false, message: msg };
  }
}

pub fn run_suite(suite: &TestSuite) -> TestResults {
  var results = TestResults.new();
  var i: Int = 0;
  while i < suite.cases.len() {
    var c = suite.cases[i];
    if c.passed {
      results.passed = results.passed + 1;
    } else {
      results.failed = results.failed + 1;
      results.failures.push(TestFailure{ name: c.name, message: c.message });
    }
    i = i + 1;
  }
  results.total = results.passed + results.failed;
  return results;
}

pub fn run_all(suites: &Vec[TestSuite]) -> TestResults
requires: suites.len() > 0
{
  var results = TestResults.new();
  var i: Int = 0;
  while i < suites.len() {
    var sr = run_suite(&suites[i]);
    results.merge(&sr);
    i = i + 1;
  }
  return results;
}

pub fn report(results: &TestResults) -> Str {
  var s0 = xiom.string.str_concat("Test Results: ", xiom.convert.int_to_string(results.passed));
  var s1 = xiom.string.str_concat(s0, " passed, ");
  var s2 = xiom.string.str_concat(s1, xiom.convert.int_to_string(results.failed));
  var s3 = xiom.string.str_concat(s2, " failed, ");
  var s4 = xiom.string.str_concat(s3, xiom.convert.int_to_string(results.total));
  var s5 = xiom.string.str_concat(s4, " total");
  return s5;
}

pub fn report_verbose(results: &TestResults) -> Str {
  if results.failed > 0 {
    return report_verbose_with_failures(results);
  } else {
    return report_verbose_no_failures(results);
  }
}

fn report_verbose_no_failures(results: &TestResults) -> Str {
  var s0 = xiom.string.str_concat("Test Results: ", xiom.convert.int_to_string(results.passed));
  var s1 = xiom.string.str_concat(s0, " passed, ");
  var s2 = xiom.string.str_concat(s1, xiom.convert.int_to_string(results.failed));
  var s3 = xiom.string.str_concat(s2, " failed, ");
  var s4 = xiom.string.str_concat(s3, xiom.convert.int_to_string(results.total));
  var s5 = xiom.string.str_concat(s4, " total");
  return s5;
}

fn report_verbose_with_failures(results: &TestResults) -> Str {
  var s0 = xiom.string.str_concat("Test Results: ", xiom.convert.int_to_string(results.passed));
  var s1 = xiom.string.str_concat(s0, " passed, ");
  var s2 = xiom.string.str_concat(s1, xiom.convert.int_to_string(results.failed));
  var s3 = xiom.string.str_concat(s2, " failed, ");
  var s4 = xiom.string.str_concat(s3, xiom.convert.int_to_string(results.total));
  var s5 = xiom.string.str_concat(s4, " total");
  var s6 = xiom.string.str_concat(s5, "\n\nFailures:");
  var s7 = build_failure_lines(s6, &results.failures, 0);
  return s7;
}

fn build_failure_lines(acc: Str, failures: &Vec[TestFailure], idx: Int) -> Str {
  if idx >= failures.len() {
    return acc;
  }
  var f = failures[idx];
  var a0 = xiom.string.str_concat(acc, "\n  - ");
  var a1 = xiom.string.str_concat(a0, f.name);
  var a2 = xiom.string.str_concat(a1, ": ");
  var a3 = xiom.string.str_concat(a2, f.message);
  return build_failure_lines(a3, failures, idx + 1);
}

pub fn bench_result(name: Str, iterations: Int, ms: Int) -> BenchResult
requires: name.len() > 0
requires: iterations > 0
requires: ms >= 0
{
  var ops: Int = 0;
  if ms > 0 {
    ops = (iterations * 1000) / ms;
  }
  return BenchResult{
    name: name,
    iterations: iterations,
    elapsed_ms: ms,
    ops_per_sec: ops,
  };
}

pub fn bench_report(result: &BenchResult) -> Str {
  var s0 = xiom.string.str_concat("Bench: ", result.name);
  var s1 = xiom.string.str_concat(s0, " — ");
  var s2 = xiom.string.str_concat(s1, xiom.convert.int_to_string(result.iterations));
  var s3 = xiom.string.str_concat(s2, " iter, ");
  var s4 = xiom.string.str_concat(s3, xiom.convert.int_to_string(result.elapsed_ms));
  var s5 = xiom.string.str_concat(s4, " ms, ");
  var s6 = xiom.string.str_concat(s5, xiom.convert.int_to_string(result.ops_per_sec));
  var s7 = xiom.string.str_concat(s6, " ops/sec");
  return s7;
}
