module xiom.crypto.md5

fn md5_s(index: Int) -> Int {
  if index == 0 { return 7; };
  if index == 1 { return 12; };
  if index == 2 { return 17; };
  if index == 3 { return 22; };
  if index == 4 { return 7; };
  if index == 5 { return 12; };
  if index == 6 { return 17; };
  if index == 7 { return 22; };
  if index == 8 { return 7; };
  if index == 9 { return 12; };
  if index == 10 { return 17; };
  if index == 11 { return 22; };
  if index == 12 { return 7; };
  if index == 13 { return 12; };
  if index == 14 { return 17; };
  if index == 15 { return 22; };
  if index == 16 { return 5; };
  if index == 17 { return 9; };
  if index == 18 { return 14; };
  if index == 19 { return 20; };
  if index == 20 { return 5; };
  if index == 21 { return 9; };
  if index == 22 { return 14; };
  if index == 23 { return 20; };
  if index == 24 { return 5; };
  if index == 25 { return 9; };
  if index == 26 { return 14; };
  if index == 27 { return 20; };
  if index == 28 { return 5; };
  if index == 29 { return 9; };
  if index == 30 { return 14; };
  if index == 31 { return 20; };
  if index == 32 { return 4; };
  if index == 33 { return 11; };
  if index == 34 { return 16; };
  if index == 35 { return 23; };
  if index == 36 { return 4; };
  if index == 37 { return 11; };
  if index == 38 { return 16; };
  if index == 39 { return 23; };
  if index == 40 { return 4; };
  if index == 41 { return 11; };
  if index == 42 { return 16; };
  if index == 43 { return 23; };
  if index == 44 { return 4; };
  if index == 45 { return 11; };
  if index == 46 { return 16; };
  if index == 47 { return 23; };
  if index == 48 { return 6; };
  if index == 49 { return 10; };
  if index == 50 { return 15; };
  if index == 51 { return 21; };
  if index == 52 { return 6; };
  if index == 53 { return 10; };
  if index == 54 { return 15; };
  if index == 55 { return 21; };
  if index == 56 { return 6; };
  if index == 57 { return 10; };
  if index == 58 { return 15; };
  if index == 59 { return 21; };
  if index == 60 { return 6; };
  if index == 61 { return 10; };
  if index == 62 { return 15; };
  if index == 63 { return 21; };
  return 0;
}

fn md5_k(index: Int) -> Int {
  if index == 0 { return 0xd76aa478; };
  if index == 1 { return 0xe8c7b756; };
  if index == 2 { return 0x242070db; };
  if index == 3 { return 0xc1bdceee; };
  if index == 4 { return 0xf57c0faf; };
  if index == 5 { return 0x4787c62a; };
  if index == 6 { return 0xa8304613; };
  if index == 7 { return 0xfd469501; };
  if index == 8 { return 0x698098d8; };
  if index == 9 { return 0x8b44f7af; };
  if index == 10 { return 0xffff5bb1; };
  if index == 11 { return 0x895cd7be; };
  if index == 12 { return 0x6b901122; };
  if index == 13 { return 0xfd987193; };
  if index == 14 { return 0xa679438e; };
  if index == 15 { return 0x49b40821; };
  if index == 16 { return 0xf61e2562; };
  if index == 17 { return 0xc040b340; };
  if index == 18 { return 0x265e5a51; };
  if index == 19 { return 0xe9b6c7aa; };
  if index == 20 { return 0xd62f105d; };
  if index == 21 { return 0x02441453; };
  if index == 22 { return 0xd8a1e681; };
  if index == 23 { return 0xe7d3fbc8; };
  if index == 24 { return 0x21e1cde6; };
  if index == 25 { return 0xc33707d6; };
  if index == 26 { return 0xf4d50d87; };
  if index == 27 { return 0x455a14ed; };
  if index == 28 { return 0xa9e3e905; };
  if index == 29 { return 0xfcefa3f8; };
  if index == 30 { return 0x676f02d9; };
  if index == 31 { return 0x8d2a4c8a; };
  if index == 32 { return 0xfffa3942; };
  if index == 33 { return 0x8771f681; };
  if index == 34 { return 0x6d9d6122; };
  if index == 35 { return 0xfde5380c; };
  if index == 36 { return 0xa4beea44; };
  if index == 37 { return 0x4bdecfa9; };
  if index == 38 { return 0xf6bb4b60; };
  if index == 39 { return 0xbebfbc70; };
  if index == 40 { return 0x289b7ec6; };
  if index == 41 { return 0xeaa127fa; };
  if index == 42 { return 0xd4ef3085; };
  if index == 43 { return 0x04881d05; };
  if index == 44 { return 0xd9d4d039; };
  if index == 45 { return 0xe6db99e5; };
  if index == 46 { return 0x1fa27cf8; };
  if index == 47 { return 0xc4ac5665; };
  if index == 48 { return 0xf4292244; };
  if index == 49 { return 0x432aff97; };
  if index == 50 { return 0xab9423a7; };
  if index == 51 { return 0xfc93a039; };
  if index == 52 { return 0x655b59c3; };
  if index == 53 { return 0x8f0ccc92; };
  if index == 54 { return 0xffeff47d; };
  if index == 55 { return 0x85845dd1; };
  if index == 56 { return 0x6fa87e4f; };
  if index == 57 { return 0xfe2ce6e0; };
  if index == 58 { return 0xa3014314; };
  if index == 59 { return 0x4e0811a1; };
  if index == 60 { return 0xf7537e82; };
  if index == 61 { return 0xbd3af235; };
  if index == 62 { return 0x2ad7d2bb; };
  if index == 63 { return 0xeb86d391; };
  return 0;
}

fn rotr_32(x: Int, n: Int) -> Int {
  var lo = (x >> n) & ((1 << (32 - n)) - 1);
  var hi = (x & ((1 << n) - 1)) << (32 - n);
  return lo | hi;
}

fn md5_f(x: Int, y: Int, z: Int) -> Int {
  return (x & y) | ((~x) & z);
}

fn md5_g(x: Int, y: Int, z: Int) -> Int {
  return (x & z) | (y & (~z));
}

fn md5_h(x: Int, y: Int, z: Int) -> Int {
  return x ^ y ^ z;
}

fn md5_i(x: Int, y: Int, z: Int) -> Int {
  return y ^ (x | (~z));
}

pub fn md5(data: &Vec[Int]) -> Vec[Int] {
  var a0 = 0x67452301;
  var b0 = 0xefcdab89;
  var c0 = 0x98badcfe;
  var d0 = 0x10325476;

  var padded = pad_md5(data);

  var m = Vec[Int].new();
  var x = 0;
  while x < 16 {
    m.push(0);
    x = x + 1;
  }

  var offset = 0;
  while offset < padded.len() {
    var i = 0;
    while i < 16 {
      var idx = offset + i * 4;
      m[i] = (padded[idx] & 0xFF) | ((padded[idx + 1] & 0xFF) << 8) | ((padded[idx + 2] & 0xFF) << 16) | ((padded[idx + 3] & 0xFF) << 24);
      i = i + 1;
    }

    var a = a0;
    var b = b0;
    var c = c0;
    var d = d0;

    i = 0;
    while i < 64 {
      var f_val = 0;
      var g = 0;
      if i < 16 {
        f_val = md5_f(b, c, d);
        g = i;
      }
      elif i < 32 {
        f_val = md5_g(b, c, d);
        g = (5 * i + 1) % 16;
      }
      elif i < 48 {
        f_val = md5_h(b, c, d);
        g = (3 * i + 5) % 16;
      } else {
        f_val = md5_i(b, c, d);
        g = (7 * i) % 16;
      };

      var temp = d;
      d = c;
      c = b;
      b = b + rotr_32(a + f_val + md5_k(i) + m[g], md5_s(i));
      a = temp;
      i = i + 1;
    }

    a0 = a0 + a;
    b0 = b0 + b;
    c0 = c0 + c;
    d0 = d0 + d;

    offset = offset + 64;
  }

  var result = Vec[Int].new();
  append_uint32_le(&result, a0);
  append_uint32_le(&result, b0);
  append_uint32_le(&result, c0);
  append_uint32_le(&result, d0);
  return result;
}

pub fn md5_hex(data: &Vec[Int]) -> Str {
  var hash = md5(data);
  return hex_encode_md5(&hash);
}

fn append_uint32_le(result: &Vec[Int], value: Int) {
  result.push(value & 0xFF);
  result.push((value >> 8) & 0xFF);
  result.push((value >> 16) & 0xFF);
  result.push((value >> 24) & 0xFF);
}

fn pad_md5(data: &Vec[Int]) -> Vec[Int] {
  var result = Vec[Int].new();
  var i = 0;
  while i < data.len() {
    result.push(data[i] & 0xFF);
    i = i + 1;
  }

  result.push(0x80);

  var bit_len = data.len() * 8;
  var current_len = result.len();
  var padding_needed = 64 - (current_len % 64);
  if padding_needed < 8 {
    padding_needed = padding_needed + 64;
  };

  i = 0;
  while i < padding_needed - 8 {
    result.push(0);
    i = i + 1;
  }

  result.push(bit_len & 0xFF);
  result.push((bit_len >> 8) & 0xFF);
  result.push((bit_len >> 16) & 0xFF);
  result.push((bit_len >> 24) & 0xFF);
  result.push(0);
  result.push(0);
  result.push(0);
  result.push(0);

  return result;
}

fn hex_encode_md5(data: &Vec[Int]) -> Str {
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

fn hex_digit(n: Int) -> Str {
  if n == 0 { return "0"; };
  if n == 1 { return "1"; };
  if n == 2 { return "2"; };
  if n == 3 { return "3"; };
  if n == 4 { return "4"; };
  if n == 5 { return "5"; };
  if n == 6 { return "6"; };
  if n == 7 { return "7"; };
  if n == 8 { return "8"; };
  if n == 9 { return "9"; };
  if n == 10 { return "a"; };
  if n == 11 { return "b"; };
  if n == 12 { return "c"; };
  if n == 13 { return "d"; };
  if n == 14 { return "e"; };
  return "f";
}
