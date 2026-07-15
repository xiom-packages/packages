module stb_tests
use xiom.test;
use xiom.stb;

fn test_failure_reason() -> TestResult {
  let reason = stb.failure_reason();
  return assert(true, "stb failure reason");
}

fn main() -> Int {
  var tests = [test_failure_reason];
  return test.run_all(tests);
}
