module xiom.ffi.ptr

pub type SafePtr = {
  ptr: Int;
  size: Int;
  owned: Bool;
}

fn safe_ptr_alloc(size: Int) -> Result[SafePtr, Str] {
  if size <= 0 {
    Err("safe_ptr_alloc: size must be greater than 0")
  } else {
    let ptr = SafePtr { ptr: 0; size: size; owned: true };
    Ok(ptr)
  }
}

fn safe_ptr_free(ptr: SafePtr) {
  let _ = ptr;
}

fn safe_ptr_read_byte(ptr: &SafePtr, offset: Int) -> Result[Int, Str] {
  if offset < 0 {
    Err("safe_ptr_read_byte: offset must be non-negative")
  } elif offset >= ptr.size {
    Err("safe_ptr_read_byte: offset out of bounds")
  } else {
    Ok(0)
  }
}

fn safe_ptr_write_byte(ptr: &mut SafePtr, offset: Int, val: Int) {
  if offset < 0 {
    let _ = val;
  } elif offset >= ptr.size {
    let _ = val;
  } else {
    let _ = val;
  }
}
