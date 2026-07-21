module xiom.crypto.sha

use xiom.math;
use xiom.encoding;

type LoopI = { i: Int; }
type Sha256RoundState = { a: Int; b: Int; c: Int; d: Int; e: Int; f: Int; g: Int; h: Int; i: Int; }
type Sha512RoundState = { a: Int; b: Int; c: Int; d: Int; e: Int; f: Int; g: Int; h: Int; i: Int; }
type Sha256HashState = { h0: Int; h1: Int; h2: Int; h3: Int; h4: Int; h5: Int; h6: Int; h7: Int; chunk_start: Int; }
type Sha512HashState = { h0: Int; h1: Int; h2: Int; h3: Int; h4: Int; h5: Int; h6: Int; h7: Int; chunk_start: Int; }
type WordBuildState = { word: Int; j: Int; }
type AppendState = { j: Int; }
type IntW = { v: Int; }

pub fn sha256_initial_h0() -> Int { return 0x6a09e667; }
pub fn sha256_initial_h1() -> Int { return 0xbb67ae85; }
pub fn sha256_initial_h2() -> Int { return 0x3c6ef372; }
pub fn sha256_initial_h3() -> Int { return 0xa54ff53a; }
pub fn sha256_initial_h4() -> Int { return 0x510e527f; }
pub fn sha256_initial_h5() -> Int { return 0x9b05688c; }
pub fn sha256_initial_h6() -> Int { return 0x1f83d9ab; }
pub fn sha256_initial_h7() -> Int { return 0x5be0cd19; }

pub fn sha256_k(index: Int) -> Int {
  var idx = IntW{ v: index; };
  if idx.v == 0 { return 0x428a2f98; };
  if idx.v == 1 { return 0x71374491; };
  if idx.v == 2 { return 0xb5c0fbcf; };
  if idx.v == 3 { return 0xe9b5dba5; };
  if idx.v == 4 { return 0x3956c25b; };
  if idx.v == 5 { return 0x59f111f1; };
  if idx.v == 6 { return 0x923f82a4; };
  if idx.v == 7 { return 0xab1c5ed5; };
  if idx.v == 8 { return 0xd807aa98; };
  if idx.v == 9 { return 0x12835b01; };
  if idx.v == 10 { return 0x243185be; };
  if idx.v == 11 { return 0x550c7dc3; };
  if idx.v == 12 { return 0x72be5d74; };
  if idx.v == 13 { return 0x80deb1fe; };
  if idx.v == 14 { return 0x9bdc06a7; };
  if idx.v == 15 { return 0xc19bf174; };
  if idx.v == 16 { return 0xe49b69c1; };
  if idx.v == 17 { return 0xefbe4786; };
  if idx.v == 18 { return 0x0fc19dc6; };
  if idx.v == 19 { return 0x240ca1cc; };
  if idx.v == 20 { return 0x2de92c6f; };
  if idx.v == 21 { return 0x4a7484aa; };
  if idx.v == 22 { return 0x5cb0a9dc; };
  if idx.v == 23 { return 0x76f988da; };
  if idx.v == 24 { return 0x983e5152; };
  if idx.v == 25 { return 0xa831c66d; };
  if idx.v == 26 { return 0xb00327c8; };
  if idx.v == 27 { return 0xbf597fc7; };
  if idx.v == 28 { return 0xc6e00bf3; };
  if idx.v == 29 { return 0xd5a79147; };
  if idx.v == 30 { return 0x06ca6351; };
  if idx.v == 31 { return 0x14292967; };
  if idx.v == 32 { return 0x27b70a85; };
  if idx.v == 33 { return 0x2e1b2138; };
  if idx.v == 34 { return 0x4d2c6dfc; };
  if idx.v == 35 { return 0x53380d13; };
  if idx.v == 36 { return 0x650a7354; };
  if idx.v == 37 { return 0x766a0abb; };
  if idx.v == 38 { return 0x81c2c92e; };
  if idx.v == 39 { return 0x92722c85; };
  if idx.v == 40 { return 0xa2bfe8a1; };
  if idx.v == 41 { return 0xa81a664b; };
  if idx.v == 42 { return 0xc24b8b70; };
  if idx.v == 43 { return 0xc76c51a3; };
  if idx.v == 44 { return 0xd192e819; };
  if idx.v == 45 { return 0xd6990624; };
  if idx.v == 46 { return 0xf40e3585; };
  if idx.v == 47 { return 0x106aa070; };
  if idx.v == 48 { return 0x19a4c116; };
  if idx.v == 49 { return 0x1e376c08; };
  if idx.v == 50 { return 0x2748774c; };
  if idx.v == 51 { return 0x34b0bcb5; };
  if idx.v == 52 { return 0x391c0cb3; };
  if idx.v == 53 { return 0x4ed8aa4a; };
  if idx.v == 54 { return 0x5b9cca4f; };
  if idx.v == 55 { return 0x682e6ff3; };
  if idx.v == 56 { return 0x748f82ee; };
  if idx.v == 57 { return 0x78a5636f; };
  if idx.v == 58 { return 0x84c87814; };
  if idx.v == 59 { return 0x8cc70208; };
  if idx.v == 60 { return 0x90befffa; };
  if idx.v == 61 { return 0xa4506ceb; };
  if idx.v == 62 { return 0xbef9a3f7; };
  if idx.v == 63 { return 0xc67178f2; };
  return 0;
}

fn rotr(x: Int, n: Int) -> Int {
  var lo = xiom.math.bit_and(xiom.math.shr(x, n), xiom.math.shl(1, 32 - n) - 1);
  var hi = xiom.math.shl(xiom.math.bit_and(x, xiom.math.shl(1, n) - 1), 32 - n);
  return xiom.math.bit_or(lo, hi);
}

fn ch(x: Int, y: Int, z: Int) -> Int {
  return xiom.math.bit_xor(xiom.math.bit_and(x, y), xiom.math.bit_and(xiom.math.bit_not(x), z));
}

fn maj(x: Int, y: Int, z: Int) -> Int {
  return xiom.math.bit_xor(xiom.math.bit_xor(xiom.math.bit_and(x, y), xiom.math.bit_and(x, z)), xiom.math.bit_and(y, z));
}

fn sigma0(x: Int) -> Int {
  return xiom.math.bit_xor(xiom.math.bit_xor(rotr(x, 2), rotr(x, 7)), rotr(x, 22));
}

fn sigma0_small(x: Int) -> Int {
  return xiom.math.bit_xor(xiom.math.bit_xor(rotr(x, 17), rotr(x, 19)), xiom.math.bit_and(xiom.math.shr(x, 10), 0x3FFFFF));
}

fn sigma1(x: Int) -> Int {
  return xiom.math.bit_xor(xiom.math.bit_xor(rotr(x, 13), rotr(x, 6)), rotr(x, 25));
}

fn sigma1_small(x: Int) -> Int {
  return xiom.math.bit_xor(xiom.math.bit_xor(rotr(x, 7), rotr(x, 18)), xiom.math.bit_and(xiom.math.shr(x, 3), 0x1FFFFFFF));
}

pub fn sha256(data: &Vec[Int]) -> Vec[Int]
  ensures: result.len() == 32
{
  var padded = pad_sha256(data);

  var w = Vec[Int].new();
  var lp = LoopI{ i: 0 };
  while lp.i < 64 {
    w.push(0);
    lp = LoopI{ i: lp.i + 1 };
  }

  var st = Sha256HashState{
    h0: sha256_initial_h0();
    h1: sha256_initial_h1();
    h2: sha256_initial_h2();
    h3: sha256_initial_h3();
    h4: sha256_initial_h4();
    h5: sha256_initial_h5();
    h6: sha256_initial_h6();
    h7: sha256_initial_h7();
    chunk_start: 0;
  };

  while st.chunk_start < padded.len() {
    lp = LoopI{ i: 0 };
    while lp.i < 16 {
      var idx = st.chunk_start + lp.i * 4;
      var word0 = xiom.math.shl(xiom.math.bit_and(padded[idx], 0xFF), 24);
      var word1 = xiom.math.bit_or(word0, xiom.math.shl(xiom.math.bit_and(padded[idx + 1], 0xFF), 16));
      var word2 = xiom.math.bit_or(word1, xiom.math.shl(xiom.math.bit_and(padded[idx + 2], 0xFF), 8));
      var word3 = xiom.math.bit_or(word2, xiom.math.bit_and(padded[idx + 3], 0xFF));
      w[lp.i] = word3;
      lp = LoopI{ i: lp.i + 1 };
    }

    lp = LoopI{ i: 16 };
    while lp.i < 64 {
      var s0 = sigma0_small(w[lp.i - 15]);
      var s1 = sigma1_small(w[lp.i - 2]);
      w[lp.i] = w[lp.i - 16] + s0 + w[lp.i - 7] + s1;
      lp = LoopI{ i: lp.i + 1 };
    }

    var cur = Sha256RoundState{
      a: st.h0; b: st.h1; c: st.h2; d: st.h3;
      e: st.h4; f: st.h5; g: st.h6; h: st.h7;
      i: 0;
    };
    while cur.i < 64 {
      var sig1_e = sigma1(cur.e);
      var ch_efg = ch(cur.e, cur.f, cur.g);
      var t1 = cur.h + sig1_e + ch_efg + sha256_k(cur.i) + w[cur.i];
      var t2 = sigma0(cur.a) + maj(cur.a, cur.b, cur.c);
      cur = Sha256RoundState{
        a: t1 + t2; b: cur.a; c: cur.b; d: cur.c;
        e: cur.d + t1; f: cur.e; g: cur.f; h: cur.g;
        i: cur.i + 1;
      };
    }

    st = Sha256HashState{
      h0: st.h0 + cur.a;
      h1: st.h1 + cur.b;
      h2: st.h2 + cur.c;
      h3: st.h3 + cur.d;
      h4: st.h4 + cur.e;
      h5: st.h5 + cur.f;
      h6: st.h6 + cur.g;
      h7: st.h7 + cur.h;
      chunk_start: st.chunk_start + 64;
    };
  }

  var result = Vec[Int].new();
  result.push(xiom.math.bit_and(xiom.math.shr(st.h0, 24), 0xFF));
  result.push(xiom.math.bit_and(xiom.math.shr(st.h0, 16), 0xFF));
  result.push(xiom.math.bit_and(xiom.math.shr(st.h0, 8), 0xFF));
  result.push(xiom.math.bit_and(st.h0, 0xFF));
  result.push(xiom.math.bit_and(xiom.math.shr(st.h1, 24), 0xFF));
  result.push(xiom.math.bit_and(xiom.math.shr(st.h1, 16), 0xFF));
  result.push(xiom.math.bit_and(xiom.math.shr(st.h1, 8), 0xFF));
  result.push(xiom.math.bit_and(st.h1, 0xFF));
  result.push(xiom.math.bit_and(xiom.math.shr(st.h2, 24), 0xFF));
  result.push(xiom.math.bit_and(xiom.math.shr(st.h2, 16), 0xFF));
  result.push(xiom.math.bit_and(xiom.math.shr(st.h2, 8), 0xFF));
  result.push(xiom.math.bit_and(st.h2, 0xFF));
  result.push(xiom.math.bit_and(xiom.math.shr(st.h3, 24), 0xFF));
  result.push(xiom.math.bit_and(xiom.math.shr(st.h3, 16), 0xFF));
  result.push(xiom.math.bit_and(xiom.math.shr(st.h3, 8), 0xFF));
  result.push(xiom.math.bit_and(st.h3, 0xFF));
  result.push(xiom.math.bit_and(xiom.math.shr(st.h4, 24), 0xFF));
  result.push(xiom.math.bit_and(xiom.math.shr(st.h4, 16), 0xFF));
  result.push(xiom.math.bit_and(xiom.math.shr(st.h4, 8), 0xFF));
  result.push(xiom.math.bit_and(st.h4, 0xFF));
  result.push(xiom.math.bit_and(xiom.math.shr(st.h5, 24), 0xFF));
  result.push(xiom.math.bit_and(xiom.math.shr(st.h5, 16), 0xFF));
  result.push(xiom.math.bit_and(xiom.math.shr(st.h5, 8), 0xFF));
  result.push(xiom.math.bit_and(st.h5, 0xFF));
  result.push(xiom.math.bit_and(xiom.math.shr(st.h6, 24), 0xFF));
  result.push(xiom.math.bit_and(xiom.math.shr(st.h6, 16), 0xFF));
  result.push(xiom.math.bit_and(xiom.math.shr(st.h6, 8), 0xFF));
  result.push(xiom.math.bit_and(st.h6, 0xFF));
  result.push(xiom.math.bit_and(xiom.math.shr(st.h7, 24), 0xFF));
  result.push(xiom.math.bit_and(xiom.math.shr(st.h7, 16), 0xFF));
  result.push(xiom.math.bit_and(xiom.math.shr(st.h7, 8), 0xFF));
  result.push(xiom.math.bit_and(st.h7, 0xFF));
  return result;
}

pub fn sha256_hex(data: &Vec[Int]) -> Str
  requires: data.len() > 0
  ensures: result.len() == 64
{
  var hash = sha256(data);
  return xiom.encoding.hex_encode(&hash);
}

pub fn sha256_hmac(data: &Vec[Int], key: &Vec[Int]) -> Vec[Int]
  requires: data.len() > 0
  requires: key.len() > 0
  ensures: result.len() == 32
{
  var block_size_w = IntW{ v: 64; };
  var key_work = Vec[Int].new();

  if key.len() > block_size_w.v {
    var hashed = sha256(key);
    var lp = LoopI{ i: 0 };
    while lp.i < hashed.len() {
      key_work.push(hashed[lp.i]);
      lp = LoopI{ i: lp.i + 1 };
    }
    lp = LoopI{ i: hashed.len() };
    while lp.i < block_size_w.v {
      key_work.push(0);
      lp = LoopI{ i: lp.i + 1 };
    }
  } else {
    var lp = LoopI{ i: 0 };
    while lp.i < key.len() {
      key_work.push(key[lp.i]);
      lp = LoopI{ i: lp.i + 1 };
    }
    lp = LoopI{ i: key.len() };
    while lp.i < block_size_w.v {
      key_work.push(0);
      lp = LoopI{ i: lp.i + 1 };
    }
  };

  var o_key_pad = Vec[Int].new();
  var i_key_pad = Vec[Int].new();
  var lp = LoopI{ i: 0 };
  while lp.i < block_size_w.v {
    o_key_pad.push(xiom.math.bit_xor(key_work[lp.i], 0x5c));
    i_key_pad.push(xiom.math.bit_xor(key_work[lp.i], 0x36));
    lp = LoopI{ i: lp.i + 1 };
  }

  var inner_data = Vec[Int].new();
  lp = LoopI{ i: 0 };
  while lp.i < i_key_pad.len() {
    inner_data.push(i_key_pad[lp.i]);
    lp = LoopI{ i: lp.i + 1 };
  }
  lp = LoopI{ i: 0 };
  while lp.i < data.len() {
    inner_data.push(data[lp.i]);
    lp = LoopI{ i: lp.i + 1 };
  }
  var inner_hash = sha256(&inner_data);

  var outer_data = Vec[Int].new();
  lp = LoopI{ i: 0 };
  while lp.i < o_key_pad.len() {
    outer_data.push(o_key_pad[lp.i]);
    lp = LoopI{ i: lp.i + 1 };
  }
  lp = LoopI{ i: 0 };
  while lp.i < inner_hash.len() {
    outer_data.push(inner_hash[lp.i]);
    lp = LoopI{ i: lp.i + 1 };
  }
  return sha256(&outer_data);
}

pub fn sha512_initial_h0() -> Int { return 0x6a09e667f3bcc908; }
pub fn sha512_initial_h1() -> Int { return 0xbb67ae8584caa73b; }
pub fn sha512_initial_h2() -> Int { return 0x3c6ef372fe94f82b; }
pub fn sha512_initial_h3() -> Int { return 0xa54ff53a5f1d36f1; }
pub fn sha512_initial_h4() -> Int { return 0x510e527fade682d1; }
pub fn sha512_initial_h5() -> Int { return 0x9b05688c2b3e6c1f; }
pub fn sha512_initial_h6() -> Int { return 0x1f83d9abfb41bd6b; }
pub fn sha512_initial_h7() -> Int { return 0x5be0cd19137e2179; }

pub fn sha512_k(index: Int) -> Int {
  var idx = IntW{ v: index; };
  if idx.v == 0 { return 0x428a2f98d728ae22; };
  if idx.v == 1 { return 0x7137449123ef65cd; };
  if idx.v == 2 { return 0xb5c0fbcfec4d3b2f; };
  if idx.v == 3 { return 0xe9b5dba58189dbbc; };
  if idx.v == 4 { return 0x3956c25bf348b538; };
  if idx.v == 5 { return 0x59f111f1b605d019; };
  if idx.v == 6 { return 0x923f82a4af194f9b; };
  if idx.v == 7 { return 0xab1c5ed5da6d8118; };
  if idx.v == 8 { return 0xd807aa98a3030242; };
  if idx.v == 9 { return 0x12835b0145706fbe; };
  if idx.v == 10 { return 0x243185be4ee4b28c; };
  if idx.v == 11 { return 0x550c7dc3d5ffb4e2; };
  if idx.v == 12 { return 0x72be5d74f27b896f; };
  if idx.v == 13 { return 0x80deb1fe3b1696b1; };
  if idx.v == 14 { return 0x9bdc06a725c71235; };
  if idx.v == 15 { return 0xc19bf174cf692694; };
  if idx.v == 16 { return 0xe49b69c19ef14ad2; };
  if idx.v == 17 { return 0xefbe4786384f25e3; };
  if idx.v == 18 { return 0x0fc19dc68b8cd5b5; };
  if idx.v == 19 { return 0x240ca1cc77ac9c65; };
  if idx.v == 20 { return 0x2de92c6f592b0275; };
  if idx.v == 21 { return 0x4a7484aa6ea6e483; };
  if idx.v == 22 { return 0x5cb0a9dcbd41fbd4; };
  if idx.v == 23 { return 0x76f988da831153b5; };
  if idx.v == 24 { return 0x983e5152ee66dfab; };
  if idx.v == 25 { return 0xa831c66d2db43210; };
  if idx.v == 26 { return 0xb00327c898fb213f; };
  if idx.v == 27 { return 0xbf597fc7beef0ee4; };
  if idx.v == 28 { return 0xc6e00bf33da88fc2; };
  if idx.v == 29 { return 0xd5a79147930aa725; };
  if idx.v == 30 { return 0x06ca6351e003826f; };
  if idx.v == 31 { return 0x142929670a0e6e70; };
  if idx.v == 32 { return 0x27b70a8546d22ffc; };
  if idx.v == 33 { return 0x2e1b21385c26c926; };
  if idx.v == 34 { return 0x4d2c6dfc5ac42aed; };
  if idx.v == 35 { return 0x53380d139d95b3df; };
  if idx.v == 36 { return 0x650a73548baf63de; };
  if idx.v == 37 { return 0x766a0abb3c77b2a8; };
  if idx.v == 38 { return 0x81c2c92e47edaee6; };
  if idx.v == 39 { return 0x92722c851482353b; };
  if idx.v == 40 { return 0xa2bfe8a14cf10364; };
  if idx.v == 41 { return 0xa81a664bbc423001; };
  if idx.v == 42 { return 0xc24b8b70d0f89791; };
  if idx.v == 43 { return 0xc76c51a30654be30; };
  if idx.v == 44 { return 0xd192e819d6ef5218; };
  if idx.v == 45 { return 0xd69906245565a910; };
  if idx.v == 46 { return 0xf40e35855771202a; };
  if idx.v == 47 { return 0x106aa07032bbd1b8; };
  if idx.v == 48 { return 0x19a4c116b8d2d0c8; };
  if idx.v == 49 { return 0x1e376c085141ab53; };
  if idx.v == 50 { return 0x2748774cdf8eeb99; };
  if idx.v == 51 { return 0x34b0bcb5e19b48a8; };
  if idx.v == 52 { return 0x391c0cb3c5c95a63; };
  if idx.v == 53 { return 0x4ed8aa4ae3418acb; };
  if idx.v == 54 { return 0x5b9cca4f7763e373; };
  if idx.v == 55 { return 0x682e6ff3d6b2b8a3; };
  if idx.v == 56 { return 0x748f82ee5defb2fc; };
  if idx.v == 57 { return 0x78a5636f43172f60; };
  if idx.v == 58 { return 0x84c87814a1f0ab72; };
  if idx.v == 59 { return 0x8cc702081a6439ec; };
  if idx.v == 60 { return 0x90befffa23631e28; };
  if idx.v == 61 { return 0xa4506cebde82bde9; };
  if idx.v == 62 { return 0xbef9a3f7b2c67915; };
  if idx.v == 63 { return 0xc67178f2e372532b; };
  if idx.v == 64 { return 0xca273eceea26619c; };
  if idx.v == 65 { return 0xd186b8c721c0c207; };
  if idx.v == 66 { return 0xeada7dd6cde0eb1e; };
  if idx.v == 67 { return 0xf57d4f7fee6ed178; };
  if idx.v == 68 { return 0x06f067aa72176fba; };
  if idx.v == 69 { return 0x0a637dc5a2c898a6; };
  if idx.v == 70 { return 0x113f9804bef90dae; };
  if idx.v == 71 { return 0x1b710b35131c471b; };
  if idx.v == 72 { return 0x28db77f523047d84; };
  if idx.v == 73 { return 0x32caab7b40c72493; };
  if idx.v == 74 { return 0x3c9ebe0a15c9bebc; };
  if idx.v == 75 { return 0x431d67c49c100d4c; };
  if idx.v == 76 { return 0x4cc5d4becb3e42b6; };
  if idx.v == 77 { return 0x597f299cfc657e2a; };
  if idx.v == 78 { return 0x5fcb6fab3ad6faec; };
  if idx.v == 79 { return 0x6c44198c4a475817; };
  return 0;
}

fn rotr64(x: Int, n: Int) -> Int {
  var lo = xiom.math.bit_and(xiom.math.shr(x, n), xiom.math.shl(1, 64 - n) - 1);
  var hi = xiom.math.shl(xiom.math.bit_and(x, xiom.math.shl(1, n) - 1), 64 - n);
  return xiom.math.bit_or(lo, hi);
}

fn sigma0_64(x: Int) -> Int {
  return xiom.math.bit_xor(xiom.math.bit_xor(rotr64(x, 28), rotr64(x, 34)), rotr64(x, 39));
}

fn sigma1_64(x: Int) -> Int {
  return xiom.math.bit_xor(xiom.math.bit_xor(rotr64(x, 14), rotr64(x, 18)), rotr64(x, 41));
}

fn sigma0_small_64(x: Int) -> Int {
  return xiom.math.bit_xor(xiom.math.bit_xor(rotr64(x, 1), rotr64(x, 8)), xiom.math.bit_and(xiom.math.shr(x, 7), 0x1FFFFFFFFFFFFFF));
}

fn sigma1_small_64(x: Int) -> Int {
  return xiom.math.bit_xor(xiom.math.bit_xor(rotr64(x, 19), rotr64(x, 61)), xiom.math.bit_and(xiom.math.shr(x, 6), 0x3FFFFFFFFFFFFFF));
}

pub fn sha512(data: &Vec[Int]) -> Vec[Int]
  ensures: result.len() == 64
{
  var padded = pad_sha512(data);

  var w = Vec[Int].new();
  var lp = LoopI{ i: 0 };
  while lp.i < 80 {
    w.push(0);
    lp = LoopI{ i: lp.i + 1 };
  }

  var st = Sha512HashState{
    h0: sha512_initial_h0();
    h1: sha512_initial_h1();
    h2: sha512_initial_h2();
    h3: sha512_initial_h3();
    h4: sha512_initial_h4();
    h5: sha512_initial_h5();
    h6: sha512_initial_h6();
    h7: sha512_initial_h7();
    chunk_start: 0;
  };

  while st.chunk_start < padded.len() {
    lp = LoopI{ i: 0 };
    while lp.i < 16 {
      var idx = st.chunk_start + lp.i * 8;
      var ws = WordBuildState{ word: 0; j: 0; };
      while ws.j < 8 {
        ws = WordBuildState{
          word: xiom.math.bit_or(xiom.math.shl(ws.word, 8), xiom.math.bit_and(padded[idx + ws.j], 0xFF));
          j: ws.j + 1;
        };
      }
      w[lp.i] = ws.word;
      lp = LoopI{ i: lp.i + 1 };
    }

    lp = LoopI{ i: 16 };
    while lp.i < 80 {
      var s0 = sigma0_small_64(w[lp.i - 15]);
      var s1 = sigma1_small_64(w[lp.i - 2]);
      w[lp.i] = w[lp.i - 16] + s0 + w[lp.i - 7] + s1;
      lp = LoopI{ i: lp.i + 1 };
    }

    var cur = Sha512RoundState{
      a: st.h0; b: st.h1; c: st.h2; d: st.h3;
      e: st.h4; f: st.h5; g: st.h6; h: st.h7;
      i: 0;
    };
    while cur.i < 80 {
      var sig1_e = sigma1_64(cur.e);
      var ch_efg = ch(cur.e, cur.f, cur.g);
      var t1 = cur.h + sig1_e + ch_efg + sha512_k(cur.i) + w[cur.i];
      var t2 = sigma0_64(cur.a) + maj(cur.a, cur.b, cur.c);
      cur = Sha512RoundState{
        a: t1 + t2; b: cur.a; c: cur.b; d: cur.c;
        e: cur.d + t1; f: cur.e; g: cur.f; h: cur.g;
        i: cur.i + 1;
      };
    }

    st = Sha512HashState{
      h0: st.h0 + cur.a;
      h1: st.h1 + cur.b;
      h2: st.h2 + cur.c;
      h3: st.h3 + cur.d;
      h4: st.h4 + cur.e;
      h5: st.h5 + cur.f;
      h6: st.h6 + cur.g;
      h7: st.h7 + cur.h;
      chunk_start: st.chunk_start + 128;
    };
  }

  var result = Vec[Int].new();
  append_int64_be(&result, st.h0);
  append_int64_be(&result, st.h1);
  append_int64_be(&result, st.h2);
  append_int64_be(&result, st.h3);
  append_int64_be(&result, st.h4);
  append_int64_be(&result, st.h5);
  append_int64_be(&result, st.h6);
  append_int64_be(&result, st.h7);
  return result;
}

pub fn sha512_hex(data: &Vec[Int]) -> Str
  requires: data.len() > 0
  ensures: result.len() == 128
{
  var hash = sha512(data);
  return xiom.encoding.hex_encode(&hash);
}

fn append_int64_be(result: &Vec[Int], value: Int) {
  var val_w = IntW{ v: value; };
  var st = AppendState{ j: 7 };
  while st.j >= 0 {
    result.push(xiom.math.bit_and(xiom.math.shr(val_w.v, st.j * 8), 0xFF));
    st = AppendState{ j: st.j - 1 };
  }
}

fn pad_sha256(data: &Vec[Int]) -> Vec[Int] {
  var result = Vec[Int].new();
  var lp = LoopI{ i: 0 };
  while lp.i < data.len() {
    result.push(xiom.math.bit_and(data[lp.i], 0xFF));
    lp = LoopI{ i: lp.i + 1 };
  }

  result.push(0x80);

  var current_len = result.len();
  var raw_pn = 64 - (current_len % 64);
  var pn_w = IntW{ v: raw_pn; };
  if pn_w.v < 8 {
    pn_w = IntW{ v: pn_w.v + 64; };
  };

  var pad_limit = IntW{ v: pn_w.v - 8; };
  lp = LoopI{ i: 0 };
  while lp.i < pad_limit.v {
    result.push(0);
    lp = LoopI{ i: lp.i + 1 };
  }

  result.push(xiom.math.bit_and(xiom.math.shr(data.len() * 8, 56), 0xFF));
  result.push(xiom.math.bit_and(xiom.math.shr(data.len() * 8, 48), 0xFF));
  result.push(xiom.math.bit_and(xiom.math.shr(data.len() * 8, 40), 0xFF));
  result.push(xiom.math.bit_and(xiom.math.shr(data.len() * 8, 32), 0xFF));
  result.push(xiom.math.bit_and(xiom.math.shr(data.len() * 8, 24), 0xFF));
  result.push(xiom.math.bit_and(xiom.math.shr(data.len() * 8, 16), 0xFF));
  result.push(xiom.math.bit_and(xiom.math.shr(data.len() * 8, 8), 0xFF));
  result.push(xiom.math.bit_and(data.len() * 8, 0xFF));

  return result;
}

fn pad_sha512(data: &Vec[Int]) -> Vec[Int] {
  var result = Vec[Int].new();
  var lp = LoopI{ i: 0 };
  while lp.i < data.len() {
    result.push(xiom.math.bit_and(data[lp.i], 0xFF));
    lp = LoopI{ i: lp.i + 1 };
  }

  result.push(0x80);

  var current_len = result.len();
  var raw_pn = 128 - (current_len % 128);
  var pn_w = IntW{ v: raw_pn; };
  if pn_w.v < 16 {
    pn_w = IntW{ v: pn_w.v + 128; };
  };

  var pad_limit = IntW{ v: pn_w.v - 16; };
  lp = LoopI{ i: 0 };
  while lp.i < pad_limit.v {
    result.push(0);
    lp = LoopI{ i: lp.i + 1 };
  }

  lp = LoopI{ i: 0 };
  while lp.i < 8 {
    result.push(0);
    lp = LoopI{ i: lp.i + 1 };
  }

  result.push(xiom.math.bit_and(xiom.math.shr(data.len() * 8, 56), 0xFF));
  result.push(xiom.math.bit_and(xiom.math.shr(data.len() * 8, 48), 0xFF));
  result.push(xiom.math.bit_and(xiom.math.shr(data.len() * 8, 40), 0xFF));
  result.push(xiom.math.bit_and(xiom.math.shr(data.len() * 8, 32), 0xFF));
  result.push(xiom.math.bit_and(xiom.math.shr(data.len() * 8, 24), 0xFF));
  result.push(xiom.math.bit_and(xiom.math.shr(data.len() * 8, 16), 0xFF));
  result.push(xiom.math.bit_and(xiom.math.shr(data.len() * 8, 8), 0xFF));
  result.push(xiom.math.bit_and(data.len() * 8, 0xFF));

  return result;
}
