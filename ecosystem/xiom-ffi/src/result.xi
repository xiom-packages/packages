module xiom.ffi.result

pub type FFIError = {
  code: Int;
  message: Str;
}

pub fn ffi_check(code: Int, msg: Str) -> Result[Int, FFIError] {
  if code < 0 {
    Err(FFIError { code: code; message: msg })
  } else {
    Ok(code)
  }
}

pub fn ffi_ok() -> Int {
  0
}

pub fn ffi_error(code: Int, msg: Str) -> FFIError {
  FFIError { code: code; message: msg }
}
