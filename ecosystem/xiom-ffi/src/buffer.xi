module xiom.ffi.buffer

pub type FFIBuffer = {
  data: Vec[Int];
  capacity: Int;
}

fn buffer_new(capacity: Int) -> FFIBuffer {
  FFIBuffer { data: Vec[Int].new(), capacity: capacity }
}

fn buffer_write(buf: &mut FFIBuffer, data: &Vec[Int]) -> Result[Int, Str] {
  let available = buf.capacity - buf.data.len();
  if data.len() > available {
    Err("buffer_write: would exceed capacity")
  } else {
    let written = buffer_append_all(buf, data, 0);
    Ok(written)
  }
}

fn buffer_append_all(buf: &mut FFIBuffer, data: &Vec[Int], idx: Int) -> Int {
  if idx >= data.len() {
    data.len()
  } else {
    buf.data.push(data[idx]);
    buffer_append_all(buf, data, idx + 1)
  }
}

fn buffer_read(buf: &FFIBuffer, offset: Int, len: Int) -> Result[Vec[Int], Str] {
  if offset < 0 {
    Err("buffer_read: offset must be non-negative")
  } elif offset + len > buf.data.len() {
    Err("buffer_read: read range out of bounds")
  } else {
    let result = buffer_read_slice(buf, offset, len, 0, Vec[Int].new());
    Ok(result)
  }
}

fn buffer_read_slice(buf: &FFIBuffer, offset: Int, len: Int, idx: Int, acc: Vec[Int]) -> Vec[Int] {
  if idx >= len {
    acc
  } else {
    acc.push(buf.data[offset + idx]);
    buffer_read_slice(buf, offset, len, idx + 1, acc)
  }
}

fn buffer_clear(buf: &mut FFIBuffer) {
  buf.data = Vec[Int].new();
}
