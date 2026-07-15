module xiom.crypto.md5

use xiom.math;
use xiom.encoding;

type LoopState = { i: Int; }
type IntVal = { v: Int; }
type Rot32State = { x: Int; n: Int; }
type FGHIState = { x: Int; y: Int; z: Int; }
type Md5State = { a: Int; b: Int; c: Int; d: Int; }
type Md5RoundState = { a: Int; b: Int; c: Int; d: Int; i: Int; }

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
  var s = Rot32State{ x: x; n: n; };
  var shr_val = xiom.math.shr(s.x, s.n);
  var mask = xiom.math.shl(1, s.n) - 1;
  var hi = xiom.math.bit_and(s.x, mask);
  var n_compl = 32 - s.n;
  var hi_shifted = xiom.math.shl(hi, n_compl);
  return xiom.math.bit_or(shr_val, hi_shifted);
}

fn md5_f(x: Int, y: Int, z: Int) -> Int {
  var s = FGHIState{ x: x; y: y; z: z; };
  var lhs = xiom.math.bit_and(s.x, s.y);
  var not_x = xiom.math.bit_not(s.x);
  var rhs = xiom.math.bit_and(not_x, s.z);
  return xiom.math.bit_or(lhs, rhs);
}

fn md5_g(x: Int, y: Int, z: Int) -> Int {
  var s = FGHIState{ x: x; y: y; z: z; };
  var not_z = xiom.math.bit_not(s.z);
  var lhs = xiom.math.bit_and(s.x, s.z);
  var rhs = xiom.math.bit_and(s.y, not_z);
  return xiom.math.bit_or(lhs, rhs);
}

fn md5_h(x: Int, y: Int, z: Int) -> Int {
  var s = FGHIState{ x: x; y: y; z: z; };
  var t = xiom.math.bit_xor(s.x, s.y);
  return xiom.math.bit_xor(t, s.z);
}

fn md5_i(x: Int, y: Int, z: Int) -> Int {
  var s = FGHIState{ x: x; y: y; z: z; };
  var not_z = xiom.math.bit_not(s.z);
  var t = xiom.math.bit_or(s.x, not_z);
  return xiom.math.bit_xor(s.y, t);
}

pub fn md5(data: &Vec[Int]) -> Vec[Int]
  requires: data.len() > 0
  ensures: result.len() == 16
{
  var state = Md5State{ a: 0x67452301; b: 0xefcdab89; c: 0x98badcfe; d: 0x10325476; };

  var padded = pad_md5(data);

  var m = Vec[Int].new();
  var ms = LoopState{ i: 0; };
  while ms.i < 16 {
    m.push(0);
    ms = LoopState{ i: ms.i + 1; };
  }

  var offset = 0;
  while offset < padded.len() {
    var ls = LoopState{ i: 0; };
    while ls.i < 16 {
      var idx = offset + ls.i * 4;
      var b0 = xiom.math.bit_and(padded[idx], 0xFF);
      var b1 = xiom.math.shl(xiom.math.bit_and(padded[idx + 1], 0xFF), 8);
      var b2 = xiom.math.shl(xiom.math.bit_and(padded[idx + 2], 0xFF), 16);
      var b3 = xiom.math.shl(xiom.math.bit_and(padded[idx + 3], 0xFF), 24);
      var w1 = xiom.math.bit_or(b0, b1);
      var w2 = xiom.math.bit_or(w1, b2);
      var word = xiom.math.bit_or(w2, b3);
      m[ls.i] = word;
      ls = LoopState{ i: ls.i + 1; };
    }

    var cur = Md5RoundState{ a: state.a; b: state.b; c: state.c; d: state.d; i: 0; };
    while cur.i < 64 {
      var f_val = 0;
      var g = 0;
      if cur.i < 16 {
        f_val = md5_f(cur.b, cur.c, cur.d);
        g = cur.i;
      }
      elif cur.i < 32 {
        f_val = md5_g(cur.b, cur.c, cur.d);
        g = (5 * cur.i + 1) % 16;
      }
      elif cur.i < 48 {
        f_val = md5_h(cur.b, cur.c, cur.d);
        g = (3 * cur.i + 5) % 16;
      } else {
        f_val = md5_i(cur.b, cur.c, cur.d);
        g = (7 * cur.i) % 16;
      };

      var new_b = cur.b + rotr_32(cur.a + f_val + md5_k(cur.i) + m[g], md5_s(cur.i));
      cur = Md5RoundState{ a: cur.d; b: new_b; c: cur.b; d: cur.c; i: cur.i + 1; };
    }

    state = Md5State{ a: state.a + cur.a; b: state.b + cur.b; c: state.c + cur.c; d: state.d + cur.d; };

    offset = offset + 64;
  }

  var result = Vec[Int].new();
  append_uint32_le(&result, state.a);
  append_uint32_le(&result, state.b);
  append_uint32_le(&result, state.c);
  append_uint32_le(&result, state.d);
  return result;
}

pub fn md5_hex(data: &Vec[Int]) -> Str
  requires: data.len() > 0
  ensures: result.len() == 32
{
  var hash = md5(data);
  return xiom.encoding.hex_encode(&hash);
}

fn append_uint32_le(result: &Vec[Int], value: Int) {
  var s = IntVal{ v: value; };
  result.push(xiom.math.bit_and(s.v, 0xFF));
  result.push(xiom.math.bit_and(xiom.math.shr(s.v, 8), 0xFF));
  result.push(xiom.math.bit_and(xiom.math.shr(s.v, 16), 0xFF));
  result.push(xiom.math.bit_and(xiom.math.shr(s.v, 24), 0xFF));
}

fn pad_md5(data: &Vec[Int]) -> Vec[Int] {
  var result = Vec[Int].new();
  var ls = LoopState{ i: 0; };
  while ls.i < data.len() {
    result.push(xiom.math.bit_and(data[ls.i], 0xFF));
    ls = LoopState{ i: ls.i + 1; };
  }

  result.push(0x80);

  var bit_len = data.len() * 8;
  var current_len = result.len();
  var padding_needed = 64 - (current_len % 64);
  if padding_needed < 8 {
    padding_needed = padding_needed + 64;
  };

  var ls2 = LoopState{ i: 0; };
  while ls2.i < padding_needed - 8 {
    result.push(0);
    ls2 = LoopState{ i: ls2.i + 1; };
  }

  var bl = IntVal{ v: bit_len; };
  result.push(xiom.math.bit_and(bl.v, 0xFF));
  result.push(xiom.math.bit_and(xiom.math.shr(bl.v, 8), 0xFF));
  result.push(xiom.math.bit_and(xiom.math.shr(bl.v, 16), 0xFF));
  result.push(xiom.math.bit_and(xiom.math.shr(bl.v, 24), 0xFF));
  result.push(0);
  result.push(0);
  result.push(0);
  result.push(0);

  return result;
}
