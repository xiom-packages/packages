module xiom.crypto.sha

pub fn sha256_initial_h0() -> Int { return 0x6a09e667; }
pub fn sha256_initial_h1() -> Int { return 0xbb67ae85; }
pub fn sha256_initial_h2() -> Int { return 0x3c6ef372; }
pub fn sha256_initial_h3() -> Int { return 0xa54ff53a; }
pub fn sha256_initial_h4() -> Int { return 0x510e527f; }
pub fn sha256_initial_h5() -> Int { return 0x9b05688c; }
pub fn sha256_initial_h6() -> Int { return 0x1f83d9ab; }
pub fn sha256_initial_h7() -> Int { return 0x5be0cd19; }

pub fn sha256_k(index: Int) -> Int {
  if index == 0 { return 0x428a2f98; };
  if index == 1 { return 0x71374491; };
  if index == 2 { return 0xb5c0fbcf; };
  if index == 3 { return 0xe9b5dba5; };
  if index == 4 { return 0x3956c25b; };
  if index == 5 { return 0x59f111f1; };
  if index == 6 { return 0x923f82a4; };
  if index == 7 { return 0xab1c5ed5; };
  if index == 8 { return 0xd807aa98; };
  if index == 9 { return 0x12835b01; };
  if index == 10 { return 0x243185be; };
  if index == 11 { return 0x550c7dc3; };
  if index == 12 { return 0x72be5d74; };
  if index == 13 { return 0x80deb1fe; };
  if index == 14 { return 0x9bdc06a7; };
  if index == 15 { return 0xc19bf174; };
  if index == 16 { return 0xe49b69c1; };
  if index == 17 { return 0xefbe4786; };
  if index == 18 { return 0x0fc19dc6; };
  if index == 19 { return 0x240ca1cc; };
  if index == 20 { return 0x2de92c6f; };
  if index == 21 { return 0x4a7484aa; };
  if index == 22 { return 0x5cb0a9dc; };
  if index == 23 { return 0x76f988da; };
  if index == 24 { return 0x983e5152; };
  if index == 25 { return 0xa831c66d; };
  if index == 26 { return 0xb00327c8; };
  if index == 27 { return 0xbf597fc7; };
  if index == 28 { return 0xc6e00bf3; };
  if index == 29 { return 0xd5a79147; };
  if index == 30 { return 0x06ca6351; };
  if index == 31 { return 0x14292967; };
  if index == 32 { return 0x27b70a85; };
  if index == 33 { return 0x2e1b2138; };
  if index == 34 { return 0x4d2c6dfc; };
  if index == 35 { return 0x53380d13; };
  if index == 36 { return 0x650a7354; };
  if index == 37 { return 0x766a0abb; };
  if index == 38 { return 0x81c2c92e; };
  if index == 39 { return 0x92722c85; };
  if index == 40 { return 0xa2bfe8a1; };
  if index == 41 { return 0xa81a664b; };
  if index == 42 { return 0xc24b8b70; };
  if index == 43 { return 0xc76c51a3; };
  if index == 44 { return 0xd192e819; };
  if index == 45 { return 0xd6990624; };
  if index == 46 { return 0xf40e3585; };
  if index == 47 { return 0x106aa070; };
  if index == 48 { return 0x19a4c116; };
  if index == 49 { return 0x1e376c08; };
  if index == 50 { return 0x2748774c; };
  if index == 51 { return 0x34b0bcb5; };
  if index == 52 { return 0x391c0cb3; };
  if index == 53 { return 0x4ed8aa4a; };
  if index == 54 { return 0x5b9cca4f; };
  if index == 55 { return 0x682e6ff3; };
  if index == 56 { return 0x748f82ee; };
  if index == 57 { return 0x78a5636f; };
  if index == 58 { return 0x84c87814; };
  if index == 59 { return 0x8cc70208; };
  if index == 60 { return 0x90befffa; };
  if index == 61 { return 0xa4506ceb; };
  if index == 62 { return 0xbef9a3f7; };
  if index == 63 { return 0xc67178f2; };
  return 0;
}

fn rotr(x: Int, n: Int) -> Int {
  var lo = (x >> n) & ((1 << (32 - n)) - 1);
  var hi = (x & ((1 << n) - 1)) << (32 - n);
  return lo | hi;
}

fn ch(x: Int, y: Int, z: Int) -> Int {
  return (x & y) ^ ((~x) & z);
}

fn maj(x: Int, y: Int, z: Int) -> Int {
  return (x & y) ^ (x & z) ^ (y & z);
}

fn sigma0(x: Int) -> Int {
  return rotr(x, 2) ^ rotr(x, 7) ^ rotr(x, 22);
}

fn sigma0_small(x: Int) -> Int {
  return rotr(x, 17) ^ rotr(x, 19) ^ ((x >> 10) & 0x3FFFFF);
}

fn sigma1(x: Int) -> Int {
  return rotr(x, 13) ^ rotr(x, 6) ^ rotr(x, 25);
}

fn sigma1_small(x: Int) -> Int {
  return rotr(x, 7) ^ rotr(x, 18) ^ ((x >> 3) & 0x1FFFFFFF);
}

pub fn sha256(data: &Vec[Int]) -> Vec[Int] {
  var padded = pad_sha256(data);
  var h0 = sha256_initial_h0();
  var h1 = sha256_initial_h1();
  var h2 = sha256_initial_h2();
  var h3 = sha256_initial_h3();
  var h4 = sha256_initial_h4();
  var h5 = sha256_initial_h5();
  var h6 = sha256_initial_h6();
  var h7 = sha256_initial_h7();

  var w = Vec[Int].new();
  var i = 0;
  while i < 64 {
    w.push(0);
    i = i + 1;
  }

  var chunk_start = 0;
  while chunk_start < padded.len() {
    i = 0;
    while i < 16 {
      var idx = chunk_start + i * 4;
      var word = (padded[idx] & 0xFF) << 24;
      word = word | ((padded[idx + 1] & 0xFF) << 16);
      word = word | ((padded[idx + 2] & 0xFF) << 8);
      word = word | (padded[idx + 3] & 0xFF);
      w[i] = word;
      i = i + 1;
    }

    i = 16;
    while i < 64 {
      var s0 = sigma0_small(w[i - 15]);
      var s1 = sigma1_small(w[i - 2]);
      w[i] = w[i - 16] + s0 + w[i - 7] + s1;
      i = i + 1;
    }

    var a = h0;
    var b = h1;
    var c = h2;
    var d = h3;
    var e = h4;
    var f = h5;
    var g = h6;
    var h = h7;

    i = 0;
    while i < 64 {
      var t1 = h + sigma1(e) + ch(e, f, g) + sha256_k(i) + w[i];
      var t2 = sigma0(a) + maj(a, b, c);
      h = g;
      g = f;
      f = e;
      e = d + t1;
      d = c;
      c = b;
      b = a;
      a = t1 + t2;
      i = i + 1;
    }

    h0 = h0 + a;
    h1 = h1 + b;
    h2 = h2 + c;
    h3 = h3 + d;
    h4 = h4 + e;
    h5 = h5 + f;
    h6 = h6 + g;
    h7 = h7 + h;

    chunk_start = chunk_start + 64;
  }

  var result = Vec[Int].new();
  result.push((h0 >> 24) & 0xFF);
  result.push((h0 >> 16) & 0xFF);
  result.push((h0 >> 8) & 0xFF);
  result.push(h0 & 0xFF);
  result.push((h1 >> 24) & 0xFF);
  result.push((h1 >> 16) & 0xFF);
  result.push((h1 >> 8) & 0xFF);
  result.push(h1 & 0xFF);
  result.push((h2 >> 24) & 0xFF);
  result.push((h2 >> 16) & 0xFF);
  result.push((h2 >> 8) & 0xFF);
  result.push(h2 & 0xFF);
  result.push((h3 >> 24) & 0xFF);
  result.push((h3 >> 16) & 0xFF);
  result.push((h3 >> 8) & 0xFF);
  result.push(h3 & 0xFF);
  result.push((h4 >> 24) & 0xFF);
  result.push((h4 >> 16) & 0xFF);
  result.push((h4 >> 8) & 0xFF);
  result.push(h4 & 0xFF);
  result.push((h5 >> 24) & 0xFF);
  result.push((h5 >> 16) & 0xFF);
  result.push((h5 >> 8) & 0xFF);
  result.push(h5 & 0xFF);
  result.push((h6 >> 24) & 0xFF);
  result.push((h6 >> 16) & 0xFF);
  result.push((h6 >> 8) & 0xFF);
  result.push(h6 & 0xFF);
  result.push((h7 >> 24) & 0xFF);
  result.push((h7 >> 16) & 0xFF);
  result.push((h7 >> 8) & 0xFF);
  result.push(h7 & 0xFF);
  return result;
}

pub fn sha256_hex(data: &Vec[Int]) -> Str {
  var hash = sha256(data);
  return hex_encode(&hash);
}

pub fn sha256_hmac(data: &Vec[Int], key: &Vec[Int]) -> Vec[Int] {
  var block_size = 64;
  var key_work = Vec[Int].new();

  if key.len() > block_size {
    var hashed = sha256(key);
    var i = 0;
    while i < hashed.len() {
      key_work.push(hashed[i]);
      i = i + 1;
    }
    i = hashed.len();
    while i < block_size {
      key_work.push(0);
      i = i + 1;
    }
  } else {
    var i = 0;
    while i < key.len() {
      key_work.push(key[i]);
      i = i + 1;
    }
    i = key.len();
    while i < block_size {
      key_work.push(0);
      i = i + 1;
    }
  };

  var o_key_pad = Vec[Int].new();
  var i_key_pad = Vec[Int].new();
  var i = 0;
  while i < block_size {
    o_key_pad.push(key_work[i] ^ 0x5c);
    i_key_pad.push(key_work[i] ^ 0x36);
    i = i + 1;
  }

  var inner_data = Vec[Int].new();
  i = 0;
  while i < i_key_pad.len() {
    inner_data.push(i_key_pad[i]);
    i = i + 1;
  }
  i = 0;
  while i < data.len() {
    inner_data.push(data[i]);
    i = i + 1;
  }
  var inner_hash = sha256(&inner_data);

  var outer_data = Vec[Int].new();
  i = 0;
  while i < o_key_pad.len() {
    outer_data.push(o_key_pad[i]);
    i = i + 1;
  }
  i = 0;
  while i < inner_hash.len() {
    outer_data.push(inner_hash[i]);
    i = i + 1;
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
  if index == 0 { return 0x428a2f98d728ae22; };
  if index == 1 { return 0x7137449123ef65cd; };
  if index == 2 { return 0xb5c0fbcfec4d3b2f; };
  if index == 3 { return 0xe9b5dba58189dbbc; };
  if index == 4 { return 0x3956c25bf348b538; };
  if index == 5 { return 0x59f111f1b605d019; };
  if index == 6 { return 0x923f82a4af194f9b; };
  if index == 7 { return 0xab1c5ed5da6d8118; };
  if index == 8 { return 0xd807aa98a3030242; };
  if index == 9 { return 0x12835b0145706fbe; };
  if index == 10 { return 0x243185be4ee4b28c; };
  if index == 11 { return 0x550c7dc3d5ffb4e2; };
  if index == 12 { return 0x72be5d74f27b896f; };
  if index == 13 { return 0x80deb1fe3b1696b1; };
  if index == 14 { return 0x9bdc06a725c71235; };
  if index == 15 { return 0xc19bf174cf692694; };
  if index == 16 { return 0xe49b69c19ef14ad2; };
  if index == 17 { return 0xefbe4786384f25e3; };
  if index == 18 { return 0x0fc19dc68b8cd5b5; };
  if index == 19 { return 0x240ca1cc77ac9c65; };
  if index == 20 { return 0x2de92c6f592b0275; };
  if index == 21 { return 0x4a7484aa6ea6e483; };
  if index == 22 { return 0x5cb0a9dcbd41fbd4; };
  if index == 23 { return 0x76f988da831153b5; };
  if index == 24 { return 0x983e5152ee66dfab; };
  if index == 25 { return 0xa831c66d2db43210; };
  if index == 26 { return 0xb00327c898fb213f; };
  if index == 27 { return 0xbf597fc7beef0ee4; };
  if index == 28 { return 0xc6e00bf33da88fc2; };
  if index == 29 { return 0xd5a79147930aa725; };
  if index == 30 { return 0x06ca6351e003826f; };
  if index == 31 { return 0x142929670a0e6e70; };
  if index == 32 { return 0x27b70a8546d22ffc; };
  if index == 33 { return 0x2e1b21385c26c926; };
  if index == 34 { return 0x4d2c6dfc5ac42aed; };
  if index == 35 { return 0x53380d139d95b3df; };
  if index == 36 { return 0x650a73548baf63de; };
  if index == 37 { return 0x766a0abb3c77b2a8; };
  if index == 38 { return 0x81c2c92e47edaee6; };
  if index == 39 { return 0x92722c851482353b; };
  if index == 40 { return 0xa2bfe8a14cf10364; };
  if index == 41 { return 0xa81a664bbc423001; };
  if index == 42 { return 0xc24b8b70d0f89791; };
  if index == 43 { return 0xc76c51a30654be30; };
  if index == 44 { return 0xd192e819d6ef5218; };
  if index == 45 { return 0xd69906245565a910; };
  if index == 46 { return 0xf40e35855771202a; };
  if index == 47 { return 0x106aa07032bbd1b8; };
  if index == 48 { return 0x19a4c116b8d2d0c8; };
  if index == 49 { return 0x1e376c085141ab53; };
  if index == 50 { return 0x2748774cdf8eeb99; };
  if index == 51 { return 0x34b0bcb5e19b48a8; };
  if index == 52 { return 0x391c0cb3c5c95a63; };
  if index == 53 { return 0x4ed8aa4ae3418acb; };
  if index == 54 { return 0x5b9cca4f7763e373; };
  if index == 55 { return 0x682e6ff3d6b2b8a3; };
  if index == 56 { return 0x748f82ee5defb2fc; };
  if index == 57 { return 0x78a5636f43172f60; };
  if index == 58 { return 0x84c87814a1f0ab72; };
  if index == 59 { return 0x8cc702081a6439ec; };
  if index == 60 { return 0x90befffa23631e28; };
  if index == 61 { return 0xa4506cebde82bde9; };
  if index == 62 { return 0xbef9a3f7b2c67915; };
  if index == 63 { return 0xc67178f2e372532b; };
  if index == 64 { return 0xca273eceea26619c; };
  if index == 65 { return 0xd186b8c721c0c207; };
  if index == 66 { return 0xeada7dd6cde0eb1e; };
  if index == 67 { return 0xf57d4f7fee6ed178; };
  if index == 68 { return 0x06f067aa72176fba; };
  if index == 69 { return 0x0a637dc5a2c898a6; };
  if index == 70 { return 0x113f9804bef90dae; };
  if index == 71 { return 0x1b710b35131c471b; };
  if index == 72 { return 0x28db77f523047d84; };
  if index == 73 { return 0x32caab7b40c72493; };
  if index == 74 { return 0x3c9ebe0a15c9bebc; };
  if index == 75 { return 0x431d67c49c100d4c; };
  if index == 76 { return 0x4cc5d4becb3e42b6; };
  if index == 77 { return 0x597f299cfc657e2a; };
  if index == 78 { return 0x5fcb6fab3ad6faec; };
  if index == 79 { return 0x6c44198c4a475817; };
  return 0;
}

fn rotr64(x: Int, n: Int) -> Int {
  var lo = (x >> n) & ((1 << (64 - n)) - 1);
  var hi = (x & ((1 << n) - 1)) << (64 - n);
  return lo | hi;
}

fn sigma0_64(x: Int) -> Int {
  return rotr64(x, 28) ^ rotr64(x, 34) ^ rotr64(x, 39);
}

fn sigma1_64(x: Int) -> Int {
  return rotr64(x, 14) ^ rotr64(x, 18) ^ rotr64(x, 41);
}

fn sigma0_small_64(x: Int) -> Int {
  return rotr64(x, 1) ^ rotr64(x, 8) ^ ((x >> 7) & 0x1FFFFFFFFFFFFFF);
}

fn sigma1_small_64(x: Int) -> Int {
  return rotr64(x, 19) ^ rotr64(x, 61) ^ ((x >> 6) & 0x3FFFFFFFFFFFFFF);
}

pub fn sha512(data: &Vec[Int]) -> Vec[Int] {
  var padded = pad_sha512(data);
  var h0 = sha512_initial_h0();
  var h1 = sha512_initial_h1();
  var h2 = sha512_initial_h2();
  var h3 = sha512_initial_h3();
  var h4 = sha512_initial_h4();
  var h5 = sha512_initial_h5();
  var h6 = sha512_initial_h6();
  var h7 = sha512_initial_h7();

  var w = Vec[Int].new();
  var i = 0;
  while i < 80 {
    w.push(0);
    i = i + 1;
  }

  var chunk_start = 0;
  while chunk_start < padded.len() {
    i = 0;
    while i < 16 {
      var idx = chunk_start + i * 8;
      var word: Int = 0;
      var j = 0;
      while j < 8 {
        word = (word << 8) | (padded[idx + j] & 0xFF);
        j = j + 1;
      }
      w[i] = word;
      i = i + 1;
    }

    i = 16;
    while i < 80 {
      var s0 = sigma0_small_64(w[i - 15]);
      var s1 = sigma1_small_64(w[i - 2]);
      w[i] = w[i - 16] + s0 + w[i - 7] + s1;
      i = i + 1;
    }

    var a = h0;
    var b = h1;
    var c = h2;
    var d = h3;
    var e = h4;
    var f = h5;
    var g = h6;
    var h = h7;

    i = 0;
    while i < 80 {
      var t1 = h + sigma1_64(e) + ch(e, f, g) + sha512_k(i) + w[i];
      var t2 = sigma0_64(a) + maj(a, b, c);
      h = g;
      g = f;
      f = e;
      e = d + t1;
      d = c;
      c = b;
      b = a;
      a = t1 + t2;
      i = i + 1;
    }

    h0 = h0 + a;
    h1 = h1 + b;
    h2 = h2 + c;
    h3 = h3 + d;
    h4 = h4 + e;
    h5 = h5 + f;
    h6 = h6 + g;
    h7 = h7 + h;

    chunk_start = chunk_start + 128;
  }

  var result = Vec[Int].new();
  append_int64_be(&result, h0);
  append_int64_be(&result, h1);
  append_int64_be(&result, h2);
  append_int64_be(&result, h3);
  append_int64_be(&result, h4);
  append_int64_be(&result, h5);
  append_int64_be(&result, h6);
  append_int64_be(&result, h7);
  return result;
}

pub fn sha512_hex(data: &Vec[Int]) -> Str {
  var hash = sha512(data);
  return hex_encode(&hash);
}

fn append_int64_be(result: &Vec[Int], value: Int) {
  var j = 7;
  while j >= 0 {
    result.push((value >> (j * 8)) & 0xFF);
    j = j - 1;
  }
}

fn pad_sha256(data: &Vec[Int]) -> Vec[Int] {
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

  result.push((bit_len >> 56) & 0xFF);
  result.push((bit_len >> 48) & 0xFF);
  result.push((bit_len >> 40) & 0xFF);
  result.push((bit_len >> 32) & 0xFF);
  result.push((bit_len >> 24) & 0xFF);
  result.push((bit_len >> 16) & 0xFF);
  result.push((bit_len >> 8) & 0xFF);
  result.push(bit_len & 0xFF);

  return result;
}

fn pad_sha512(data: &Vec[Int]) -> Vec[Int] {
  var result = Vec[Int].new();
  var i = 0;
  while i < data.len() {
    result.push(data[i] & 0xFF);
    i = i + 1;
  }

  result.push(0x80);

  var bit_len = data.len() * 8;
  var current_len = result.len();
  var padding_needed = 128 - (current_len % 128);
  if padding_needed < 16 {
    padding_needed = padding_needed + 128;
  };

  i = 0;
  while i < padding_needed - 16 {
    result.push(0);
    i = i + 1;
  }

  i = 0;
  while i < 8 {
    result.push(0);
    i = i + 1;
  }

  result.push((bit_len >> 56) & 0xFF);
  result.push((bit_len >> 48) & 0xFF);
  result.push((bit_len >> 40) & 0xFF);
  result.push((bit_len >> 32) & 0xFF);
  result.push((bit_len >> 24) & 0xFF);
  result.push((bit_len >> 16) & 0xFF);
  result.push((bit_len >> 8) & 0xFF);
  result.push(bit_len & 0xFF);

  return result;
}

fn hex_encode(data: &Vec[Int]) -> Str {
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
  if n < 10 {
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
  };
  if n == 10 { return "a"; };
  if n == 11 { return "b"; };
  if n == 12 { return "c"; };
  if n == 13 { return "d"; };
  if n == 14 { return "e"; };
  return "f";
}
