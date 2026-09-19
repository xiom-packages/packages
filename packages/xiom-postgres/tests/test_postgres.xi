module postgres_tests

fn connect(conn_string: Str) -> Result[Int, Str] {
  return Err("xiom.postgres: libpq FFI bridge not linked");
}

fn test_connect_failure() -> Int {
  var result = connect("host=invalid");
  match result {
    Ok(_) => { return 1; }
    Err(_) => { return 0; }
  }
}

pub fn main() -> Int {
  return test_connect_failure();
}
