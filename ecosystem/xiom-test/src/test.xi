module xiom.test

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

pub fn TestResults.new() -> TestResults {
  return TestResults{
    passed: 0;
    failed: 0;
    total: 0;
    failures: Vec[TestFailure].new();
  };
}

pub fn TestResults.merge(other: &TestResults) {
  passed = passed + other.passed;
  failed = failed + other.failed;
  total = passed + failed;
  var i: Int = 0;
  while i < other.failures.len() {
    var f = other.failures[i];
    failures.push(TestFailure{ name: f.name; message: f.message; });
    i = i + 1;
  }
}

pub fn assert_eq[T: Eq](actual: T, expected: T, msg: Str)
  requires: actual == expected
{
}

pub fn assert_true(condition: Bool, msg: Str)
  requires: condition
{
}

pub fn assert_false(condition: Bool, msg: Str)
  requires: !condition
{
}

pub fn run_tests(tests: Vec[TestResults]) -> TestResults {
  var result = TestResults.new();
  var i: Int = 0;
  while i < tests.len() {
    result.merge(&tests[i]);
    i = i + 1;
  }
  return result;
}
