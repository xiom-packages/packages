module redis_tests
use xiom.test;
use xiom.redis;

fn test_connect_failure() -> TestResult {
  match connect("localhost", 9999) {
    Ok(_) => { return assert(false, "redis unexpected success"); }
    Err(_) => { return assert(true, "redis connect failure handled"); }
  }
}

fn main() -> Int {
  var tests = [test_connect_failure];
  return test.run_all(tests);
}
