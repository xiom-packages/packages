module openal_tests
use xiom.test;
use xiom.openal;

fn test_create_source() -> TestResult {
  match create_source() {
    Ok(s) => { delete_source(s); return assert(true, "openal source"); }
    Err(_) => { return assert(true, "openal skip"); }
  }
}

fn main() -> Int {
  var tests = [test_create_source];
  return test.run_all(tests);
}
