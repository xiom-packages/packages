module xiom.crypto.hex

pub fn hex_encode(data: &Vec[Int]) -> Str
  requires: data.len() > 0;
  ensures: result.len() == data.len() * 2;
{
  var result = "";
  var i = 0;
  while i < data.len() {
    var b = data[i] & 0xFF;
    var hi = (b >> 4) & 0xF;
    var lo = b & 0xF;
    result = result + hex_digit(hi) + hex_digit(lo);
    i = i + 1;
  }
  return result;
}

pub fn hex_encode_upper(data: &Vec[Int]) -> Str {
  var result = "";
  var i = 0;
  while i < data.len() {
    var b = data[i] & 0xFF;
    var hi = (b >> 4) & 0xF;
    var lo = b & 0xF;
    result = result + hex_digit_upper(hi) + hex_digit_upper(lo);
    i = i + 1;
  }
  return result;
}

pub fn hex_decode(input: Str) -> Result[Vec[Int], Str]
  requires: input.len() > 0;
{
  var len = input.len();
  if len % 2 != 0 {
    return Err("hex: odd length string");
  };
  var result = Vec[Int].new();
  var i = 0;
  while i < len {
    var hi = hex_value_at(input, i);
    var lo = hex_value_at(input, i + 1);
    if hi < 0 {
      return Err("hex: invalid character");
    };
    if lo < 0 {
      return Err("hex: invalid character");
    };
    result.push((hi << 4) | lo);
    i = i + 2;
  }
  return Ok(result);
}

fn hex_digit(n: Int) -> Str {
  if n < 10 {
    return chr(48 + n);
  };
  return chr(87 + n);
}

fn hex_digit_upper(n: Int) -> Str {
  if n < 10 {
    return chr(48 + n);
  };
  return chr(55 + n);
}

fn hex_value_at(input: Str, pos: Int) -> Int {
  var c = char_at(input, pos);
  if c >= 48 && c <= 57 {
    return c - 48;
  };
  if c >= 65 && c <= 70 {
    return c - 55;
  };
  if c >= 97 && c <= 102 {
    return c - 87;
  };
  return -1;
}

fn chr(code: Int) -> Str {
  if code == 48 { return "0"; };
  if code == 49 { return "1"; };
  if code == 50 { return "2"; };
  if code == 51 { return "3"; };
  if code == 52 { return "4"; };
  if code == 53 { return "5"; };
  if code == 54 { return "6"; };
  if code == 55 { return "7"; };
  if code == 56 { return "8"; };
  if code == 57 { return "9"; };
  if code == 97 { return "a"; };
  if code == 98 { return "b"; };
  if code == 99 { return "c"; };
  if code == 100 { return "d"; };
  if code == 101 { return "e"; };
  if code == 102 { return "f"; };
  return "";
}

fn char_at(s: Str, pos: Int) -> Int {
  return 0;
}
