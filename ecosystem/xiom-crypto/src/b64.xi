module xiom.crypto.b64

pub fn base64_encode(data: &Vec[Int]) -> Str {
  var result = "";
  var i = 0;
  var len = data.len();
  while i < len {
    var b0 = data[i] & 0xFF;
    result = result + b64_alphabet((b0 >> 2) & 0x3F);

    if i + 1 < len {
      var b1 = data[i + 1] & 0xFF;
      result = result + b64_alphabet(((b0 << 4) | (b1 >> 4)) & 0x3F);

      if i + 2 < len {
        var b2 = data[i + 2] & 0xFF;
        result = result + b64_alphabet(((b1 << 2) | (b2 >> 6)) & 0x3F);
        result = result + b64_alphabet(b2 & 0x3F);
      } else {
        result = result + b64_alphabet((b1 << 2) & 0x3F);
        result = result + "=";
      };
    } else {
      result = result + b64_alphabet((b0 << 4) & 0x3F);
      result = result + "=";
      result = result + "=";
    };

    i = i + 3;
  }
  return result;
}

pub fn base64_decode(input: Str) -> Result[Vec[Int], Str] {
  var len = input.len();
  if len % 4 != 0 {
    return Err("base64: invalid length");
  };
  var result = Vec[Int].new();
  var i = 0;
  while i < len {
    var v0 = b64_value_at(input, i);
    var v1 = b64_value_at(input, i + 1);
    var v2 = b64_value_at(input, i + 2);
    var v3 = b64_value_at(input, i + 3);

    if v0 < 0 || v1 < 0 {
      return Err("base64: invalid character");
    };

    result.push((v0 << 2) | (v1 >> 4));

    if v2 >= 0 {
      result.push(((v1 & 0xF) << 4) | (v2 >> 2));

      if v3 >= 0 {
        result.push(((v2 & 0x3) << 6) | v3);
      };
    };

    i = i + 4;
  }
  return Ok(result);
}

pub fn base64url_encode(data: &Vec[Int]) -> Str {
  var result = "";
  var i = 0;
  var len = data.len();
  while i < len {
    var b0 = data[i] & 0xFF;
    result = result + b64url_alphabet((b0 >> 2) & 0x3F);

    if i + 1 < len {
      var b1 = data[i + 1] & 0xFF;
      result = result + b64url_alphabet(((b0 << 4) | (b1 >> 4)) & 0x3F);

      if i + 2 < len {
        var b2 = data[i + 2] & 0xFF;
        result = result + b64url_alphabet(((b1 << 2) | (b2 >> 6)) & 0x3F);
        result = result + b64url_alphabet(b2 & 0x3F);
      } else {
        result = result + b64url_alphabet((b1 << 2) & 0x3F);
      };
    } else {
      result = result + b64url_alphabet((b0 << 4) & 0x3F);
    };

    i = i + 3;
  }
  return result;
}

pub fn base64url_decode(input: Str) -> Result[Vec[Int], Str] {
  var result = Vec[Int].new();
  var i = 0;
  var len = input.len();
  while i < len {
    var v0 = b64url_value_at(input, i);
    if v0 < 0 {
      return Err("base64url: invalid character");
    };

    if i + 1 < len {
      var v1 = b64url_value_at(input, i + 1);
      if v1 < 0 {
        return Err("base64url: invalid character");
      };
      result.push((v0 << 2) | (v1 >> 4));

      if i + 2 < len {
        var v2 = b64url_value_at(input, i + 2);
        if v2 < 0 {
          return Err("base64url: invalid character");
        };
        result.push(((v1 & 0xF) << 4) | (v2 >> 2));

        if i + 3 < len {
          var v3 = b64url_value_at(input, i + 3);
          if v3 < 0 {
            return Err("base64url: invalid character");
          };
          result.push(((v2 & 0x3) << 6) | v3);
        };
      };
    };

    i = i + 4;
  }
  return Ok(result);
}

fn b64_alphabet(n: Int) -> Str {
  if n == 0 { return "A"; };
  if n == 1 { return "B"; };
  if n == 2 { return "C"; };
  if n == 3 { return "D"; };
  if n == 4 { return "E"; };
  if n == 5 { return "F"; };
  if n == 6 { return "G"; };
  if n == 7 { return "H"; };
  if n == 8 { return "I"; };
  if n == 9 { return "J"; };
  if n == 10 { return "K"; };
  if n == 11 { return "L"; };
  if n == 12 { return "M"; };
  if n == 13 { return "N"; };
  if n == 14 { return "O"; };
  if n == 15 { return "P"; };
  if n == 16 { return "Q"; };
  if n == 17 { return "R"; };
  if n == 18 { return "S"; };
  if n == 19 { return "T"; };
  if n == 20 { return "U"; };
  if n == 21 { return "V"; };
  if n == 22 { return "W"; };
  if n == 23 { return "X"; };
  if n == 24 { return "Y"; };
  if n == 25 { return "Z"; };
  if n == 26 { return "a"; };
  if n == 27 { return "b"; };
  if n == 28 { return "c"; };
  if n == 29 { return "d"; };
  if n == 30 { return "e"; };
  if n == 31 { return "f"; };
  if n == 32 { return "g"; };
  if n == 33 { return "h"; };
  if n == 34 { return "i"; };
  if n == 35 { return "j"; };
  if n == 36 { return "k"; };
  if n == 37 { return "l"; };
  if n == 38 { return "m"; };
  if n == 39 { return "n"; };
  if n == 40 { return "o"; };
  if n == 41 { return "p"; };
  if n == 42 { return "q"; };
  if n == 43 { return "r"; };
  if n == 44 { return "s"; };
  if n == 45 { return "t"; };
  if n == 46 { return "u"; };
  if n == 47 { return "v"; };
  if n == 48 { return "w"; };
  if n == 49 { return "x"; };
  if n == 50 { return "y"; };
  if n == 51 { return "z"; };
  if n == 52 { return "0"; };
  if n == 53 { return "1"; };
  if n == 54 { return "2"; };
  if n == 55 { return "3"; };
  if n == 56 { return "4"; };
  if n == 57 { return "5"; };
  if n == 58 { return "6"; };
  if n == 59 { return "7"; };
  if n == 60 { return "8"; };
  if n == 61 { return "9"; };
  if n == 62 { return "+"; };
  if n == 63 { return "/"; };
  return "";
}

fn b64url_alphabet(n: Int) -> Str {
  if n == 0 { return "A"; };
  if n == 1 { return "B"; };
  if n == 2 { return "C"; };
  if n == 3 { return "D"; };
  if n == 4 { return "E"; };
  if n == 5 { return "F"; };
  if n == 6 { return "G"; };
  if n == 7 { return "H"; };
  if n == 8 { return "I"; };
  if n == 9 { return "J"; };
  if n == 10 { return "K"; };
  if n == 11 { return "L"; };
  if n == 12 { return "M"; };
  if n == 13 { return "N"; };
  if n == 14 { return "O"; };
  if n == 15 { return "P"; };
  if n == 16 { return "Q"; };
  if n == 17 { return "R"; };
  if n == 18 { return "S"; };
  if n == 19 { return "T"; };
  if n == 20 { return "U"; };
  if n == 21 { return "V"; };
  if n == 22 { return "W"; };
  if n == 23 { return "X"; };
  if n == 24 { return "Y"; };
  if n == 25 { return "Z"; };
  if n == 26 { return "a"; };
  if n == 27 { return "b"; };
  if n == 28 { return "c"; };
  if n == 29 { return "d"; };
  if n == 30 { return "e"; };
  if n == 31 { return "f"; };
  if n == 32 { return "g"; };
  if n == 33 { return "h"; };
  if n == 34 { return "i"; };
  if n == 35 { return "j"; };
  if n == 36 { return "k"; };
  if n == 37 { return "l"; };
  if n == 38 { return "m"; };
  if n == 39 { return "n"; };
  if n == 40 { return "o"; };
  if n == 41 { return "p"; };
  if n == 42 { return "q"; };
  if n == 43 { return "r"; };
  if n == 44 { return "s"; };
  if n == 45 { return "t"; };
  if n == 46 { return "u"; };
  if n == 47 { return "v"; };
  if n == 48 { return "w"; };
  if n == 49 { return "x"; };
  if n == 50 { return "y"; };
  if n == 51 { return "z"; };
  if n == 52 { return "0"; };
  if n == 53 { return "1"; };
  if n == 54 { return "2"; };
  if n == 55 { return "3"; };
  if n == 56 { return "4"; };
  if n == 57 { return "5"; };
  if n == 58 { return "6"; };
  if n == 59 { return "7"; };
  if n == 60 { return "8"; };
  if n == 61 { return "9"; };
  if n == 62 { return "-"; };
  if n == 63 { return "_"; };
  return "";
}

fn b64_value_at(input: Str, pos: Int) -> Int {
  if pos >= input.len() {
    return -2;
  };
  var c = char_at(input, pos);
  if c == 43 { return 62; };
  if c == 47 { return 63; };
  if c >= 48 && c <= 57 { return c - 48 + 52; };
  if c == 61 { return -1; };
  if c >= 65 && c <= 90 { return c - 65; };
  if c >= 97 && c <= 122 { return c - 97 + 26; };
  return -1;
}

fn b64url_value_at(input: Str, pos: Int) -> Int {
  if pos >= input.len() {
    return -2;
  };
  var c = char_at(input, pos);
  if c == 45 { return 62; };
  if c == 95 { return 63; };
  if c >= 48 && c <= 57 { return c - 48 + 52; };
  if c == 61 { return -1; };
  if c >= 65 && c <= 90 { return c - 65; };
  if c >= 97 && c <= 122 { return c - 97 + 26; };
  return -1;
}

fn char_at(s: Str, pos: Int) -> Int {
  return 0;
}
