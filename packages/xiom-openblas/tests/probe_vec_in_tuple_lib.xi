module probe_tuple_lib

pub type Handle = Int;

pub fn make_handle() -> Result[Handle, Str] {
  return Ok(7);
}

pub fn pair() -> Result[(Handle, Vec[Int]), Str] {
  let h = make_handle()?;
  var v = Vec[Int].new();
  v.push(11);
  v.push(22);
  return Ok((h, v));
}