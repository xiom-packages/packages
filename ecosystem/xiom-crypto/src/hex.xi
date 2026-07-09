module xiom.crypto.hex

use xiom.encoding;

pub fn hex_encode(data: &Vec[Int]) -> Str
  requires: data.len() > 0
  ensures: result.len() == data.len() * 2
{
  return xiom.encoding.hex_encode(data);
}

pub fn hex_encode_upper(data: &Vec[Int]) -> Str {
  return xiom.encoding.hex_encode_upper(data);
}

pub fn hex_decode(input: Str) -> Result[Vec[Int], Str]
  requires: input.len() > 0
{
  return xiom.encoding.hex_decode(input);
}
