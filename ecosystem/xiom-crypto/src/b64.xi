module xiom.crypto.b64

use xiom.encoding;

pub fn base64_encode(data: &Vec[Int]) -> Str
  requires: data.len() > 0
  ensures: result.len() > 0
{
  return xiom.encoding.base64_encode(data);
}

pub fn base64_decode(input: Str) -> Result[Vec[Int], Str]
  requires: input.len() > 0
{
  return xiom.encoding.base64_decode(input);
}

pub fn base64url_encode(data: &Vec[Int]) -> Str
  requires: data.len() > 0
{
  return xiom.encoding.base64url_encode(data);
}

pub fn base64url_decode(input: Str) -> Result[Vec[Int], Str]
  requires: input.len() > 0
{
  return xiom.encoding.base64url_decode(input);
}
