module probe_up_down.types

pub type SqliteError = {
  code: Int;
  message: Str;
}

pub fn SqliteError.new(code: Int, message: Str) -> SqliteError {
  return SqliteError{ code: code, message: message };
}
