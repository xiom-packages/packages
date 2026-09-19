module redis_tests

fn connect(host: Str, port: Int) -> Result[Int, Str] {
  return Err("xiom.redis: hiredis FFI bridge not linked");
}

fn test_connect_failure() -> Int {
  var result = connect("localhost", 9999);
  match result {
    Ok(_) => { return 1; }
    Err(_) => { return 0; }
  }
}

pub fn main() -> Int {
  return test_connect_failure();
}
